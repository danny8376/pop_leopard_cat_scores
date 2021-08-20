require "uuid"
require "openssl"
require "base64"

class Hasher
  DUMMY = Hasher.new UUID.empty

  getter id : UUID
  property score : Int64
  getter result : String
  getter salt : String

  def initialize(@id, @score = 0_i64)
    @result = init_hash
    @salt = gen_salt
  end

  def gen_salt
    Random::DEFAULT.base64 9
  end

  def renew_salt
    @salt = gen_salt
  end

  def calc_hash(str)
    Base64.strict_encode(OpenSSL::MD5.hash(str).to_slice[0, 9])
  end

  def init_hash
    calc_hash "#{@id.hexstring}#{Time.utc.to_unix}"
  end

  def gen_hash(secs)
    @result = calc_hash "#{@result}|#{secs}|#{@score}|#{@salt}"
  end
end
