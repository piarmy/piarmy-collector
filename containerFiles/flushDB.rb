require 'awesome_print'
require 'json'
require 'redis'

redis = Redis.new

redis.flushdb()

puts "Redis flushed..."
ap redis.keys("*")