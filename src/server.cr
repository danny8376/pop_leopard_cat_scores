require "kemal"
require "base64"
require "json"
require "uuid/json"

require "./record"
require "./hasher"
require "./db"

TIMEOUT = 5.seconds
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

ws "/submit" do |socket|
  record = nil
  count = 0
  start = last = sec = Time.monotonic
  renew_salt = false
  hasher = Hasher::DUMMY
  spawn do # timeout watcher
    until socket.closed?
      if Time.monotonic - last > TIMEOUT
        socket.close
      end
      sleep 1.seconds
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
      else
        count += 1
      end
      if count > MAX_ALLOW_PPS
        # over score, just ignore now
      elsif !record.nil? && args.size >= 1 && args.size <= 5
        r = record.not_nil!
        hasher.gen_hash (Time.monotonic - start).total_seconds.to_i64
        idx = -1
        args.each_index do |i|
          idx = i if hasher.result == args.unsafe_fetch i
        end
        if idx != -1
          last = Time.monotonic
          hasher.score = r.step_score
          socket.send "ack,#{r.score},#{idx},#{hasher.renew_salt if renew_salt}"
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
