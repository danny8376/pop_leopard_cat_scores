require "db"
require "sqlite3"

require "./record"

class Database
  class NoResult < Exception
    def initialize(message = "No result")
      super(message)
    end
  end

  GLOBAL_ID = UUID.empty

  @db : DB::Database

  def initialize
    @db = DB.open "sqlite3:./scores.db"

    init_tables
  end

  def close
    @db.close
  end

  def init_tables
    @db.exec <<-SQLCMD
      CREATE TABLE IF NOT EXISTS scores (
        id     BLOB PRIMARY KEY,
        score  INTEGER DEFAULT 0,
        period INTEGER DEFAULT 0
      );
      SQLCMD
  end

  def load(id : UUID)
    begin
      score, period = @db.query_one "SELECT score, period FROM scores WHERE id = ?;", id.bytes.to_slice, as: {Int64, Int32}
      {score, period}
    rescue DB::NoResultsError
      raise NoResult.new
    end
  end

  def load_global
    load GLOBAL_ID
  end

  def save(id : UUID, score : Int64, period : Int32)
    cmd = <<-SQLCMD
      INSERT INTO scores (id, score, period)
        VALUES (?, ?, ?)
        ON CONFLICT (id) DO
        UPDATE SET score = ?, period = ?;
      SQLCMD
    @db.exec cmd,
      id.bytes.to_slice, score, period,
      score, period
  end

  def save(record : Record)
    save record.id, record.score, record.period
  end

  def save_global
    save GLOBAL_ID, Record.score, Record.period
  end

  def top(n = 100)
    res = [] of Tuple(UUID, Int64, Int32)
    @db.query "SELECT id, score, period FROM scores WHERE id != ? ORDER BY score DESC LIMIT ?;", GLOBAL_ID.bytes.to_slice, n do |rs|
      rs.each do
        id = UUID.new rs.read(Bytes)
        score = rs.read Int64
        period = rs.read Int32
        res.push({ id, score, period })
      end
    end
    res
  end
end
