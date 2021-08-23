require "uuid"

require "./db"

class Record
  # !IMPORTANT! Don't rearrange, or you break the database
  enum Scope
    No15
    Chilla
    Lutra
    Obear
    Padko
  end

  GLOBAL_ID = Database::GLOBAL_ID

  class OutOfScope < Exception ; end

  @@global : Slice(Record) = scope_build { |scope| Record.new scope, GLOBAL_ID }
  @@db : Database?
  @@period = Time::Span.zero

  def self.scope_build
    scopes = Record::Scope.values
    Slice.new(scopes.size) do |i|
      yield scopes[i]
    end
  end

  def self.fetch(scope : Int32)
    @@global[scope]
  rescue IndexError
    raise OutOfScope.new
  end

  def self.fetch(scope : Scope)
    @@global[scope.value]
  end

  def self.fetch(scope : String)
    fetch Scope.parse(scope)
  rescue ArgumentError
    raise OutOfScope.new
  end

  def self.score(scope)
    fetch(scope).score
  end

  def self.period(scope)
    fetch(scope).period
  end

  def self.step_score(scope)
    fetch(scope).step_score
  end

  def self.init(@@db)
    @@global.each do |record|
      begin
        record.database = @@db
      rescue Database::NoResult
      end
    end
  end

  def self.save
    Scope.values.each { |s| fetch(s).save }
  end

  def self.global_autosave(period)
    need_spawn = @@period.zero? && !period.zero?
    @@period = period
    if need_spawn
      spawn do
        until @@period.zero?
          save
          sleep @@period
        end
      end
    end
  end

  getter scope : Scope
  getter id
  getter score
  getter period
  getter database : Database?

  @sec : Int32
  @global : Record?

  def initialize(@scope, @id = UUID.random, @score = 0_i64, @period = 0)
    @global = Record.fetch @scope if @id != GLOBAL_ID
    @sec = Time.monotonic.seconds
    self.database = @@db
  end

  def self.new(scope : String, id, score = 0_i64, period = 0)
    new Scope.parse(scope), id, score, period
  rescue ArgumentError
    raise OutOfScope.new
  end

  def self.new(scope : Int32, id, score = 0_i64, period = 0)
    s = Scope.from_value? scope
    raise OutOfScope.new if s.nil?
    new s, id, score, period
  end

  def step_score
    @global.try &.step_score

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
          @score, @period = db.load @scope.to_i, @id
        rescue Database::NoResult
        end
      end
    end
    db
  end

  def save
    @database.try &.save(self)
  end
end
