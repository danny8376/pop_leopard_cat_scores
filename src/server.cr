require "kemal"
require "base64"
require "json"
require "uuid/json"

require "./record"
require "./hasher"
require "./db"

TIMEOUT = 5.seconds
SAVE_PERIOD = 2.seconds
MAX_ALLOW_PPS = 350

database = Database.new
Record.init database

records = Hash(UUID, Record).new

def json_global(json)
  json.object do
    json.field "score", Record.score
    json.field "period", Record.period
  end
end

def json_record(json, record : Tuple(UUID, Int64, Int32))
  json.object do
    json.field "id", record[0]
    json.field "score", record[1]
    json.field "period", record[2]
  end
end

def json_record(json, record : Record)
  json_record json, { record.id, record.score, record.period }
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
      json = JSON.build do |json|
        json_global json
      end
      global_sockets.each do |socket|
        socket.send json
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
end

get "/top/:amount" do |env|
  amount = {env.params.url["amount"].to_i? || 10, 100}.min
  JSON.build do |json|
    json.object do
      json.field "global" do
        json_global json
      end
      json.field "top" do
        json.array do
          database.top(amount).each do |r|
            json_record json, r
          end
        end
      end
    end
  end
end

ws "/submit" do |socket, context|
  unless ["http://10.250.150.95", "https://no15rescute.github.io"].includes? context.request.headers["Origin"]?
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
      r.database = database
      records[r.id] = r
      hasher = Hasher.new r.id, r.score
      start = last = sec = Time.monotonic
      socket.send "init,#{r.id.to_s},#{r.score},#{hasher.result},#{hasher.salt}"
    when "contiune"
      if args.size >= 1
        begin
          id = UUID.new args[0]
          record = r = records[id]? || Record.new id
          r.database = database
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

at_exit do
  records.each_value { |r| r.save }
  database.save_global
  database.close
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
