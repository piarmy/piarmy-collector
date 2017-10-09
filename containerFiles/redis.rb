require 'awesome_print'
require 'json'
require 'redis'

redis = Redis.new

puts "CONTAINERS:"
redis.keys("*").each do |node|
  puts "KEY: #{node.green}"
  puts "----------".green
  ap JSON.parse(redis.get(node))
  puts ""
  puts ""
end