require "kemal"
require "base64"
require "json"
require "uuid/json"
require "http/client"
require "uri"

require "./record"
require "./hasher"
require "./db"

TIMEOUT = 5.seconds
SAVE_PERIOD = 2.seconds
MAX_ALLOW_PPS = 350

DATABASE = Database.new
Record.init DATABASE
Record.global_autosave SAVE_PERIOD

YT_API = HTTP::Client.new URI.parse("https://www.googleapis.com")

ALLOW_ORIGINS = %w(
http://10.250.150.95
http://home.saru.moe
https://home.saru.moe
https://no15rescute.github.io
https://springfish04.github.io
)

records = Hash(Tuple(Record::Scope, UUID), Record).new

def json_global(json, g : Record)
  json.object do
    json.field "score", g.score
    json.field "period", g.period
  end
end

def json_global(json, scope)
  json_global json, Record.fetch(scope)
end

def json_record(json, record : Tuple(UUID, Int64, Int32, String?, String?, String?))
  json.object do
    json.field "id", record[0]
    json.field "score", record[1]
    json.field "period", record[2]
    unless record[3].nil?
      json.field "yt_id", record[3]
      json.field "yt_name", record[4]
      json.field "yt_avatar", record[5]
    end
  end
end

def json_record(json, record : Record)
  json_record json, { record.id, record.score, record.period, nil, nil, nil }
end

get "/" do
  "Test"
end

get "/internal_status" do |env|
  "In memory records : #{records.size}"
end

get "/:scope/global" do |env|
  scope = env.params.url["scope"]
  JSON.build do |json|
    json_global json, scope
  end
rescue Record::OutOfScope
  halt env, 404
end

global_sockets = Record.scope_build do |scope|
  ary = [] of HTTP::WebSocket
  r = Record.fetch scope
  spawn do
    last = r.score
    while Kemal.config.running
      if last != r.score
        last = r.score
        unless ary.empty?
          json = JSON.build { |json| json_global json, r }
          ary.each { |socket| socket.send json }
        end
      end
      sleep 1.second
    end
  end
  ary
end

ws "/:scope/global" do |socket, context|
  scope = Record::Scope.parse? context.ws_route_lookup.params["scope"]
  if scope.nil?
    socket.close
  else
    ary = global_sockets[scope.not_nil!.value]
    ary.push socket
    socket.on_close do
      ary.delete socket
    end
    # init packet
    socket.send JSON.build { |json| json_global json, scope.not_nil! }
  end
rescue ArgumentError
  socket.close
end

def render_top(scope, global = Record.fetch(scope))
  JSON.build do |json|
    json.object do
      json.field "global" do
        json_global json, global
      end
      json.field "top" do
        json.array do
          DATABASE.top(scope, amount).each do |r|
            json_record json, r
          end
        end
      end
    end
  end
end


class TopTracker
  class Pair
    getter amount : Int32
    property cache
    getter sockets

    def initialize(@amount)
      @cache = ""
      @sockets = [] of HTTP::WebSocket
    end

    def send_all(msg = @cache)
      @sockets.each { |socket| socket.send msg }
    end
  end

  getter scope : Record::Scope

  @global : Record

  def initialize(@scope)
    @global = Record.fetch @scope
    @pairs = StaticArray(Pair, 100).new { |i| Pair.new i + 1 }
    @data = [] of Tuple(UUID, Int64, Int32, String?, String?, String?)
    @max = 0
    spawn do
      while Kemal.config.running
        if @max > 0
          @data = fetch
          render_caches true
        end
        sleep SAVE_PERIOD
      end
    end
  end

  def pairs(amount : Int32)
    @pairs[amount - 1]
  end

  def check_max
    @pairs.reverse_each do |pair|
      if pair.sockets.size > 0
        @max = pair.amount
        break
      end
    end
  end

  def send_init_packet(socket, pair)
    socket.send render_single(pair)
  end

  def join_socket(socket, amount)
    if amount > @max
      @max = amount
      fetch
    end
    pair = pairs(amount)
    ary = pair.sockets
    ary.push socket
    socket.on_close do
      ary.delete socket
      check_max if ary.empty?
    end
    send_init_packet(socket, pair)
  end

  def fetch(size = @max)
    amount = {size, @max}.max
    @data = DATABASE.top scope.value, amount
  end

  def render_caches(send = false)
    @pairs.each do |pair|
      if pair.sockets.size > 0
        pair.cache = render pair.amount
        pair.send_all if send
      else
        pair.cache = ""
      end
    end
  end

  def render_single(amount : Int32)
    render_single pairs(amount)
  end

  def render_single(pair : Pair)
    if pair.cache.empty?
      pair.cache = render pair.amount
    end
    pair.cache
  end

  def render(amount)
    fetch amount if @data.size < amount
    JSON.build do |json|
      json.object do
        json.field "global" do
          json_global json, @global
        end
        json.field "top" do
          json.array do
            @data[0, amount].each do |r|
              json_record json, r
            end
          end
        end
      end
    end
  end
end

top_trackers = Record.scope_build { |scope| TopTracker.new scope }

get "/:scope/top/:amount" do |env|
  scope = Record::Scope.parse env.params.url["scope"]
  amount = {1, {env.params.url["amount"].to_i? || 10, 100}.min }.max
  top_trackers[scope.value].render_single amount
rescue ArgumentError
  halt env, 404
end

ws "/:scope/top/:amount" do |socket, context|
  scope = Record::Scope.parse context.ws_route_lookup.params["scope"]
  amount = {1, {context.ws_route_lookup.params["amount"].to_i? || 10, 100}.min }.max
  top_trackers[scope.value].join_socket socket, amount
rescue ArgumentError
  socket.close
end

ws "/:scope/submit" do |socket, context|
  unless ALLOW_ORIGINS.includes? context.request.headers["Origin"]?
    socket.close HTTP::WebSocket::CloseCode::PolicyViolation, "not authorized"
    next
  end
  scope = Record::Scope.parse context.ws_route_lookup.params["scope"]

  record = nil
  count = 0
  start = last = sec = Time.monotonic
  renew_salt = false
  sync_sent = false
  hasher = Hasher::DUMMY
  spawn do # external timer
    save_last = Time.monotonic
    until socket.closed?
      now = Time.monotonic
      # timeout check
      if now - last > TIMEOUT
        socket.close
      end
      # save check
      if now - save_last > SAVE_PERIOD
        save_last = now
        record.try &.save
      end
      sleep 1.second
    end
  end
  socket.on_message do |message|
    args = message.split ','
    cmd = args.shift
    case cmd
    when "new"
      record = r = Record.new scope
      records[{scope, r.id}] = r
      hasher = Hasher.new r.id, r.score
      start = last = sec = Time.monotonic
      socket.send "init,#{r.id.to_s},#{r.score},#{hasher.result},#{hasher.salt}"
    when "contiune"
      if args.size >= 1
        begin
          id = UUID.new args[0]
          record = r = records[{scope, id}]? || Record.new scope, id
          hasher = Hasher.new r.id, r.score
          start = last = sec = Time.monotonic
          socket.send "init,#{r.id.to_s},#{r.score},#{hasher.result},#{hasher.salt}"
        rescue ArgumentError
        end
      end
    when "count"
      if sec != Time.monotonic.seconds
        sec = Time.monotonic.seconds
        count = 1
        renew_salt = true
        sync_sent = false
      else
        count += 1
      end
      if count > MAX_ALLOW_PPS
        # over score, just ignore now
      elsif !record.nil? && args.size >= 2 && args.size <= 8 && (no_nil = args.shift.to_i?)
        r = record.not_nil!
        no = no_nil.not_nil!
        hasher.gen_hash (Time.monotonic - start).total_seconds.to_i64
        idx = -1
        args.each_index do |i|
          idx = i if hasher.result == args.unsafe_fetch i
        end
        if idx != -1
          last = Time.monotonic
          r.step_score
          # make hasher score out of sync temporarily, sync it at ack command
          # which multiple async submission possible
          hasher.score += 1
          hasher.next
          sync_sent = false
        end
        if (renew_salt || idx != (args.size / 2).floor) && !sync_sent
          # needs to set before sending command (affect last hash for syncing)
          if idx == -1
            sync_sent = true
            hasher.score = r.score
            hasher.next
            socket.send "sync,#{hasher.last},#{r.score},#{hasher.renew_salt if renew_salt}"
          else
            socket.send "ack,#{no},#{idx},#{hasher.score},#{r.score},#{hasher.renew_salt if renew_salt}"
          end
          renew_salt = false
        end
      end
    end
  end
  socket.on_close do
    record.try do |r|
      r.save
      records.delete({scope, r.id})
    end
  end
rescue ArgumentError
  socket.close
end

post "/link/:id/yt" do |env|
  score_id = UUID.new env.params.url["id"]
  token_nil = env.request.body.try &.gets(512)
  if token_nil
    token = token_nil.not_nil!
    halt env, 404 unless DATABASE.id_exist? score_id
    res = YT_API.get "/youtube/v3/channels?part=snippet&mine=true&access_token=#{URI.encode token}"
    if res.status_code == 200
      begin
        json = JSON.parse res.body
        yt_id = json["items"][0]["id"].as_s
        name = json["items"][0]["snippet"]["title"].as_s
        avatar = json["items"][0]["snippet"]["thumbnails"]["default"]["url"].as_s
      rescue
        halt env, 500, "Debug: YouTube API response body : \r\n\r\n #{res.body}"
      end
      DATABASE.ytbind yt_id, score_id, name, avatar
      { status: "done", id: yt_id, name: name, avatar: avatar }.to_json
    else
      halt env, 403
    end
  else
    halt env, 403
  end
rescue ArgumentError
  halt env, 400
end

before_all do |env|
  origin = env.request.headers["Origin"]?
  if ALLOW_ORIGINS.includes? origin
    env.response.headers["Access-Control-Allow-Origin"] = origin.not_nil!
  end
end

at_exit do
  records.each_value { |r| r.save }
  Record.save
  DATABASE.close
end

# TODO: move this to config
if Kemal.config.env == "production"
  Kemal.run do |config|
    config.server.not_nil!.bind_unix "socket.sock"
    File.chmod("socket.sock", 0o777)
  end
else
  Kemal.run
end
