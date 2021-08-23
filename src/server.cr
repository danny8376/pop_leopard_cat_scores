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

YT_API = HTTP::Client.new URI.parse("https://www.googleapis.com")

ALLOW_ORIGINS = ["http://10.250.150.95", "http://home.saru.moe", "https://no15rescute.github.io"]

records = Hash(UUID, Record).new

def json_global(json)
  json.object do
    json.field "score", Record.score
    json.field "period", Record.period
  end
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

get "/global" do |env|
  JSON.build do |json|
    json_global json
  end
end

global_sockets = [] of HTTP::WebSocket

spawn do
  last = Record.score
  while Kemal.config.running
    if last != Record.score
      last = Record.score
      unless global_sockets.empty?
        json = JSON.build { |json| json_global json }
        global_sockets.each { |socket| socket.send json }
      end
    end
    sleep 1.second
  end
end

ws "/global" do |socket|
  global_sockets.push socket
  socket.on_close do
    global_sockets.delete socket
  end
  # init packet
  socket.send JSON.build { |json| json_global json }
end

def render_top(amount)
  JSON.build do |json|
    json.object do
      json.field "global" do
        json_global json
      end
      json.field "top" do
        json.array do
          DATABASE.top(amount).each do |r|
            json_record json, r
          end
        end
      end
    end
  end
end

get "/top/:amount" do |env|
  amount = {env.params.url["amount"].to_i? || 10, 100}.min
  render_top amount
end

class TopWSPair
  getter amount : Int32
  getter sockets : Array(HTTP::WebSocket)
  def initialize(no)
    @amount = no + 1
    @sockets = [] of HTTP::WebSocket
    @json = ""
    spawn do
      while Kemal.config.running
        unless sockets.empty?
          @json = render_top @amount
          sockets.each { |socket| socket.send @json }
        end
        sleep SAVE_PERIOD
      end
    end
  end

  def send_init_packet(socket)
    if sockets.empty?
      @json = render_top @amount
    end
    socket.send @json
  end
end

top_sockets = StaticArray(TopWSPair, 100).new { |i| TopWSPair.new i }

ws "/top/:amount" do |socket, context|
  amount = {1, {context.ws_route_lookup.params["amount"].to_i? || 10, 100}.min }.max
  pair = top_sockets[amount - 1]
  pair.sockets.push socket
  socket.on_close do
    pair.sockets.delete socket
  end
  # init packet
  pair.send_init_packet socket
end

ws "/submit" do |socket, context|
  unless ALLOW_ORIGINS.includes? context.request.headers["Origin"]?
    socket.close HTTP::WebSocket::CloseCode::PolicyViolation, "not authorized"
    next
  end
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
      record = r = Record.new
      r.database = DATABASE
      records[r.id] = r
      hasher = Hasher.new r.id, r.score
      start = last = sec = Time.monotonic
      socket.send "init,#{r.id.to_s},#{r.score},#{hasher.result},#{hasher.salt}"
    when "contiune"
      if args.size >= 1
        begin
          id = UUID.new args[0]
          record = r = records[id]? || Record.new id
          r.database = DATABASE
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
      records.delete r.id
    end
  end
end

post "/link/:id/yt" do |env|
  score_id = UUID.new env.params.url["id"]
  token_nil = env.request.body.try &.gets(512)
  if token_nil
    token = token_nil.not_nil!
    DATABASE.load score_id
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
rescue Database::NoResult
  halt env, 404
end

before_all do |env|
  origin = env.request.headers["Origin"]?
  if ALLOW_ORIGINS.includes? origin
    env.response.headers["Access-Control-Allow-Origin"] = origin.not_nil!
  end
end

at_exit do
  records.each_value { |r| r.save }
  DATABASE.save_global
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
