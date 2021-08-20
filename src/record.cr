require "uuid"

class Record
  @@score = 0_i64
  @@period = 0
  @@sec : Int32 = Time.monotonic.seconds

  def self.score
    @@score
  end

  def self.period
    @@period
  end

  def self.step_score
    if @@sec != Time.monotonic.seconds
      @@sec = Time.monotonic.seconds
      @@period += 1
    end
    @@score += 1
  end

  def self.init(db)
    begin
      @@score, @@period = db.load_global
    rescue Database::NoResult
    end
  end

  getter id
  getter score
  getter period
  getter database : Database?

  @sec : Int32

  def initialize(@id = UUID.random, @score = 0_i64, @period = 0)
    @sec = Time.monotonic.seconds
  end

  def step_score
    Record.step_score

    if @sec != Time.monotonic.seconds
      @sec = Time.monotonic.seconds
      @period += 1
    end
    @score += 1
  end

  def database=(db)
    if @database != db
      @database = db
      @database.try do |db|
        begin
          @score, @period = db.load id
        rescue Database::NoResult
        end
      end
    end
    db
  end

  def save
    @database.try do |db|
      db.save(self)
      db.save_global
    end
  end
end
