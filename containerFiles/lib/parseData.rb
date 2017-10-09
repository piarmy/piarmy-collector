require 'awesome_print'
require 'json'
require 'redis'

module DockerData
  extend self

  def parse()
    redis            = Redis.new
    previousKeys     = redis.keys("*")
    newKeys          = nil
    parsedContainers = {}
    parsedNodes      = {}

    # Read container files
    Dir.glob('data/*container*.json') do |dataFile|
      if !dataFile.include? "updated"
        # Check for valid JSON between system file rewrites, avoid truncated files
        containersFile = File.open(dataFile).read
        validJSON      = false

        if !containersFile.empty?
          while !validJSON
            begin  
              containers = JSON.parse(containersFile)
              validJSON = true
            rescue Exception => e  
              puts e.message
              sleep 1
              puts "Error parsing JSON [#{dataFile}], retrying in 1 second..."
            end
          end

          nodeName = File.basename(dataFile).split(".")[0]

          parsedContainers["#{nodeName}"] ||= []

          containers.each do |container|
            newKeys ||= []
            newKeys.push("#{nodeName}:#{container['Id']}")

            redis.set("#{nodeName}:#{container['Id']}", container.to_json)
          end
        end
      end
    end

    # Read node files
    Dir.glob('data/*.json') do |dataFile|
      if !dataFile.include? "updated" and !dataFile.include? "container" and !dataFile.include? "service"
        # Check for valid JSON between system file rewrites, avoid truncated files
        nodeFile = File.open(dataFile).read
        validJSON      = false

        if !nodeFile.empty?
          while !validJSON
            begin  
              nodeData = JSON.parse(nodeFile)
              validJSON = true
            rescue Exception => e  
              puts e.message
              sleep 1
              puts "Error parsing JSON [#{dataFile}], retrying in 1 second..."
            end
          end

          nodeName = File.basename(dataFile).split(".")[0]

          # For some reason, sometimes RAM doesn't come in, check
          if !nodeData["RAM"].nil?
            parsedNodes["#{nodeName}"] ||= []

            newKeys ||= []
            newKeys.push("#{nodeName}").uniq!

            redis.set("#{nodeName}", nodeData.to_json)
          else
            newKeys ||= []
            newKeys.push("#{nodeName}").uniq!
          end
        end
      end
    end

    # Read services file
    servicesFile = File.open("data/services.json").read
    # Check for valid JSON between system file rewrites, avoid truncated files
    validJSON      = false

    if !servicesFile.empty?
      while !validJSON
        begin  
          servicesData = JSON.parse(servicesFile)
          validJSON = true
        rescue Exception => e  
          puts e.message
          sleep 1
          puts "Error parsing JSON [#{dataFile}], retrying in 1 second..."
        end
      end
    end

    servicesData.each do |service|
      newKeys ||= []
      newKeys.push("service:#{service['ID']}")

      redis.set("service:#{service['ID']}", service.to_json)
    end

    newKeys.uniq!
    currentRedisKeys = redis.keys("*").sort!

    if newKeys != currentRedisKeys.count
      if newKeys.count < previousKeys.count
        puts "Removing Keys in DB...".red
        (previousKeys - newKeys).each do |keyToDelete|
          redis.del(keyToDelete)
          puts "Deleted Redis key: #{keyToDelete}".red
        end
      end
    end

    puts "\nCurrent Docker objects:"
    dockerObjects              = {}
    dockerObjects[:nodes]      = []
    dockerObjects[:containers] = []
    dockerObjects[:services]   = []

    currentRedisKeys.each do |key|
      containerData = redis.get(key)

      if !containerData.nil?
        keyName = JSON.parse(redis.get(key))["Name"] || ""

        if keyName.include? "/"
          dockerObjects[:containers].push("#{key.split(":")[0]}: #{keyName}").sort!
        elsif key.include? "service:"
          dockerObjects[:services].push("#{key}").sort!
        else
          dockerObjects[:nodes].push("#{key}").sort!
        end
      else
        puts "Redis returned nil data...".red
      end
    end

    ap dockerObjects
    puts "-----\n"
  end
end