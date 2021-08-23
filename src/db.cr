require "db"
require "sqlite3"
require "uuid"

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
        id     BLOB NOT NULL,
        scope  INTEGER NOT NULL,
        score  INTEGER DEFAULT 0,
        period INTEGER DEFAULT 0
      );
      SQLCMD
    @db.exec <<-SQLCMD
      CREATE TABLE IF NOT EXISTS ytbind (
        id       TEXT,
        score_id BLOB,
        name     TEXT NOT NULL,
        avatar   TEXT
      );
      SQLCMD
    @db.exec "CREATE UNIQUE INDEX IF NOT EXISTS scores_primary ON scores (id, scope);"
    @db.exec "CREATE INDEX IF NOT EXISTS scores_scope ON scores (scope);"
    @db.exec "CREATE UNIQUE INDEX IF NOT EXISTS ytbind_primary ON ytbind (id, score_id);"
    @db.exec "CREATE INDEX IF NOT EXISTS ytbind_id ON ytbind (id);"
    @db.exec "CREATE INDEX IF NOT EXISTS ytbind_score_id ON ytbind (score_id);"
  end

  def load(scope : Int32, id : UUID)
    score, period = @db.query_one "SELECT score, period FROM scores WHERE scope = ? AND id = ?;", scope, id.bytes.to_slice, as: {Int64, Int32}
    {score, period}
  rescue DB::NoResultsError
    raise NoResult.new
  end

  def save(scope : Int32, id : UUID, score : Int64, period : Int32)
    cmd = <<-SQLCMD
      INSERT INTO scores (id, scope, score, period)
        VALUES (?, ?, ?, ?)
        ON CONFLICT (id, scope) DO
        UPDATE SET score = ?, period = ?;
      SQLCMD
    @db.exec cmd,
      id.bytes.to_slice, scope, score, period,
      score, period
  end

  def save(record : Record)
    save record.scope.value, record.id, record.score, record.period
  end

  def top(scope : Int32, n = 100)
    res = [] of Tuple(UUID, Int64, Int32, String?, String?, String?)
    cmd = <<-SQLCMD
      SELECT s.id, SUM(s.score) AS score, MAX(s.period) AS period, COALESCE(yt.id, s.id) AS group_id, yt.id, yt.name, yt.avatar
        FROM scores s
        LEFT JOIN ytbind yt ON s.id = yt.score_id
        WHERE s.scope = ? AND s.id != ?
        GROUP BY group_id
        ORDER BY score DESC
        LIMIT ?;
      SQLCMD
    @db.query cmd, scope, GLOBAL_ID.bytes.to_slice, n do |rs|
      rs.each do
        id = UUID.new rs.read(Bytes)
        score = rs.read Int64
        period = rs.read Int32
        rs.read
        yt_id = rs.read String?
        name = rs.read String?
        avatar = rs.read String?
        res.push({ id, score, period, yt_id, name, avatar })
      end
    end
    res
  end
  
  def id_exist?(id : UUID)
    @db.query "SELECT id FROM scores WHERE id = ?;", id.bytes.to_slice
    true
  rescue DB::NoResultsError
    false
  end

  def ytbind(yt_id : String, score_id : UUID, name : String, avatar : String)
    cmd = <<-SQLCMD
      INSERT INTO ytbind (id, score_id, name, avatar)
        VALUES (?, ?, ?, ?)
        ON CONFLICT (id, score_id) DO
        UPDATE SET name = ?, avatar = ?;
      SQLCMD
    @db.exec cmd,
      yt_id, score_id.bytes.to_slice, name, avatar,
      name, avatar
  end
end
