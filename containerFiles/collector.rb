require 'redis'
require 'awesome_print'

redis = Redis.new

class Collector
	attr_accessor :containerHash

	def initialize()
		@containerHash = {}
	end

	def fetchContainers(ipAddress)
		require 'json'
		require 'open-uri'
		results = JSON.parse open("http://#{ipAddress}:8080/api/v1.3/subcontainers").read

		puts "Fetching containers for node: $ip"
		results.each do |container|
			unless container["aliases"].nil?
				@containerHash[container["aliases"][1]] = container["aliases"][0]
			end
		end
	end
end

collector = Collector.new

collector.fetchContainers("10.10.10.3")

ap collector