require 'sinatra/base'
require 'awesome_print'
require 'json'
require 'redis'
require 'websocket-eventmachine-server'

require './lib/jsonp.rb'
require './lib/parseData.rb'

require 'eventmachine'

$websocket = nil

def run(opts)

  # Start he reactor
  EM.run do
    DockerData.parse()

    # define some defaults for our app
    server  = opts[:server] || 'thin'
    host    = opts[:host]   || '0.0.0.0'
    port    = opts[:port]   || '80'
    web_app = opts[:app]

    dispatch = Rack::Builder.app do
      map '/' do
        run web_app
      end
    end

    # NOTE that we have to use an EM-compatible web-server. There
    # might be more, but these are some that are currently available.
    unless ['thin', 'hatetepe', 'goliath'].include? server
      raise "Need an EM webserver, but #{server} isn't"
    end

    # Start the web server. Note that you are free to run other tasks
    # within your EM instance.
    Rack::Server.start({
      app:    dispatch,
      server: server,
      Host:   host,
      Port:   port,
      signals: false,
    })

    WebSocket::EventMachine::Server.start(:host => "0.0.0.0", :port => 81) do |ws|

      if $websocket.respond_to? :cancel
        $websocket.cancel()
      end

      $websocket = EM::PeriodicTimer.new(5) do
        nodeData = []
        Dir.glob('data/*.json') do |dataFile|
          if !dataFile.include? "updated" and !dataFile.include? "container" and !dataFile.include? "service"
            nodeData.push(JSON.parse(File.open(dataFile).read))
          end
        end

        if nodeData.count > 0
          msg         = {}
          msg["type"] = "nodeUpdate"
          msg["data"] = nodeData

          ws.send msg.to_json, :type => "text"
        end
      end

      ws.onopen do
        puts "Client connected"
      end

      ws.onmessage do |msg, type|
        puts "Received message:"
        ap JSON.parse(msg)
        ws.send msg, :type => type
      end

      ws.onclose do
        puts "Client disconnected"
      end

      ws.onerror do |error|
        ap "ERROR: #{error}"
      end
    end

    timer = EM::PeriodicTimer.new(7) do
      puts "\n[#{Time.now}] Eventmachine: Parsing Docker data...\n".green
      DockerData.parse()
    end

  end
end

# Our simple hello-world app
class Collector < Sinatra::Base
  helpers Sinatra::Jsonp

  # threaded - False: Will take requests on the reactor thread
  #            True:  Will queue request for background thread
  configure do
    set :threaded, false
    set :root, File.dirname(__FILE__)
  end

  before do
    headers( 'Access-Control-Allow-Origin' => '*', 'Access-Control-Allow-Headers' => 'Origin, Content-Type, Accept, Authorization, Token' )
  end

  get '/' do
    redis      = Redis.new
    containers = []
    nodes      = {}

    redis.keys("*").each do |node|
      if !JSON.parse(redis.get(node))["Image"].nil?
        containerName = JSON.parse(redis.get(node))["Name"]

        containerName[0] = '' 

        nodeName    = node.split(":")[0]
        containerID = node.split(":")[1]

        nodes["#{nodeName}"] ||= []
        nodes["#{nodeName}"].push([containerID,containerName])

        nodes["#{nodeName}"].sort! {|a,b| a[1].gsub("_","-") <=> b[1].gsub("_","-")}
      end
    end

    html = ""

    nodes = nodes.sort.to_h

    nodes.each do |node|
      nodeName    = node[0]
      containers  = node[1]

      html << "<h3><a href=\"/nodes/#{nodeName}\">#{nodeName}</a></h3>"

      containers.each do |container|
        containerID   =  container[0]
        containerName =  container[1]
        html << "<div><a href=\"/container/#{containerID}\">#{containerName}</a></div>"
      end
    end

    html
  end

  get '/nodes/:nodeID/?' do
    nodeID   = params["nodeID"]
    redis    = Redis.new
    
    nodeInfo = JSON.parse(redis.get(nodeID))

    if !nodeInfo.nil?
      status 200
      jsonp nodeInfo
    else
      status 404
      {"error":"No nodes found."}
    end
  end

  get '/nodes/?' do
    redis       = Redis.new
    nodes       = []

    redis.keys("*").each do |node|
      if !node.include? ":"
        if JSON.parse(redis.get(node))["Image"].nil?
          nodes.push(node)
        end
      end
    end

    nodes.uniq!
    nodes.sort!

    if !nodes.empty?
      status 200
      jsonp nodes
    else
      status 404
      {"error":"No nodes found."}
    end
  end

  get '/containers/force/?' do
    redis           = Redis.new
    nodes           = []
    containers      = []
    links           = []
    nodesGraph      = []
    containersGraph = []
    linksGraph      = []

    redisKeys = redis.keys("*")

    redisKeys.each do |container|
      if !JSON.parse(redis.get(container))["Image"].nil?
        container = container.split(":")
        nodes.push(container[0]).uniq!
        containers.push(container[1]).uniq!
        links.push(container).uniq!
      end
    end

    # Node Attributes
    nodeColor                = "#ff7f0e"
    nodeRadius               = 20
    
    # Container Attributes
    containerColor           = "#aec7e8"
    containerRadius          = 10
    
    # Link Attributes
    nodeLinkStrokeWidth      = 2
    nodeLinkDistance         = 400
    nodeLinkStrength         = 0.9
    
    containerLinkStrokeWidth = 2
    containerLinkDistance    = 50
    containerLinkStrength    = 0.25

    nodes.each do |node|
      nodeHash          = {}
      nodeHash[:id]     = node
      nodeHash[:name]   = node
      nodeHash[:type]   = "node"
      nodeHash[:color]  = nodeColor
      nodeHash[:radius] = nodeRadius

      nodesGraph.push(nodeHash)
    end

    # Node Attributes
    containerColor  = "#aec7e8"
    containerRadius = 10

    containers.each do |container|
      containerNameKey       = redisKeys.select { |key| key.include? container }
      containerName          = JSON.parse(redis.get(containerNameKey))["Name"]
      containerName[0]       = ""
      
      containerHash          = {}
      containerHash[:id]     = container
      containerHash[:name]   = containerName
      containerHash[:type]   = "container"
      containerHash[:color]  = containerColor
      containerHash[:radius] = containerRadius

      nodesGraph.push(containerHash)
    end

    nodes.combination(2).to_a.each do |nodePair|
      linksHash               = {}
      linksHash[:source]      = nodesGraph.index { |node| node[:id] == nodePair[0] }
      linksHash[:target]      = nodesGraph.index { |node| node[:id] == nodePair[1] }
      linksHash[:strokeWidth] = nodeLinkStrokeWidth
      linksHash[:distance]    = nodeLinkDistance
      linksHash[:strength]    = nodeLinkStrength

      linksGraph.push(linksHash)
    end

    links.each do |relationship|
      linksHash               = {}
      linksHash[:source]      = nodesGraph.index { |node| node[:id] == relationship[0] }
      linksHash[:target]      = nodesGraph.index { |node| node[:id] == relationship[1] }
      linksHash[:strokeWidth] = containerLinkStrokeWidth
      linksHash[:distance]    = containerLinkDistance
      linksHash[:strength]    = containerLinkStrength

      linksGraph.push(linksHash)
    end

    graphData         = {}
    graphData[:nodes] = nodesGraph
    graphData[:links] = linksGraph

    if !graphData.nil?
      status 200
      jsonp graphData
    else
      status 404
      {"error":"No force data found"}
    end
  end

  get '/containers/tree/?' do
    redis               = Redis.new
    nodes               = []
    containers          = []
    links               = []
    graphData           = nil
    
    swarmRadius          = 15
    swarmColor           = "#ccc"
    swarmStroke          = "#fff"

    nodeRadius          = 15
    nodeColor           = "#ccc"
    nodeStroke          = "#fff"
    
    containerRadius     = 15
    containerColor      = "#ccc"
    containerStroke     = "#fff"
    
    treeData            = {}
    treeData[:name]     = "Swarm"
    treeData[:radius]   = swarmRadius
    treeData[:color]    = swarmColor
    treeData[:stroke]   = swarmStroke
    treeData[:icon]     = "\uf0c2"
    treeData[:children] = []

    redisKeys = redis.keys("*")

    redisKeys.each do |container|
      if !JSON.parse(redis.get(container))["Image"].nil?
        container = container.split(":")

        nodes.push(container[0]).uniq!
        containers.push(container[1]).uniq!
        links.push(container).uniq!
      end
    end

    nodes.sort!
    containers.sort!
    links.sort!

    nodes.each do |node|
      
    end

    nodes.each do |node|
      nodeData          = {}
      nodeData[:name]   = node
      nodeData[:radius] = nodeRadius
      nodeData[:color]  = nodeColor
      nodeData[:stroke] = nodeStroke
      nodeData[:icon]   = "\uf109"
      
      children          = []

      links.select {|link| link[0] == node }.each do |relationship|
        containerName          = JSON.parse(redis.get("#{relationship[0]}:#{relationship[1]}"))["Name"]
        containerName[0]       = ""
        
        containerData          = {}
        
        containerData[:name]   = containerName
        containerData[:radius] = containerRadius
        containerData[:color]  = containerColor
        containerData[:stroke] = containerStroke
        containerData[:icon]   = "\uf1b3"

        children.push(containerData)
      end

      nodeData[:children] = children
      
      treeData[:children].push(nodeData)

    end

    if !treeData.nil?
      status 200
      jsonp treeData
    else
      status 404
      {"error":"No tree data found"}
    end
  end

  get '/containers/?' do
    redis       = Redis.new
    containers  = []

    redis.keys("*").each do |container|
      if container.include? ":" and !container.include? "service"
        containerName = JSON.parse(redis.get(container))["Name"]
        containerName[0] = ''
        containers.push([container.split(":")[0], container.split(":")[1], containerName])
      end
    end

    containers.uniq!

    if !containers.empty?
      status 200
      jsonp containers
    else
      status 404
      {"error":"No containers found."}
    end
  end

  get '/container/:containerID/?' do
    containerID   = params[:containerID]
    redis         = Redis.new
    containerData = nil

    redis.keys("*").each do |container|
      if container.include? containerID
        containerData = JSON.parse(redis.get(container))

        serviceID = containerData["Config"]["Labels"]["com.docker.swarm.service.id"]

        if !serviceID.nil?
          containerData["serviceData"] = JSON.parse(redis.get("service:#{serviceID}"))
        end
      end
    end

    if !containerData.nil?
      status 200
      jsonp containerData
    else
      status 404
      {"error":"No container found with ID: #{containerID}"}
    end
  end

  get '/services/?' do
    redis       = Redis.new
    services  = []

    redis.keys("*").each do |service|
      if service.include? "service:"
        serviceName   = JSON.parse(redis.get(service))["Spec"]["Name"]
        serviceID = service.split(":")[1]
        
        services.push([serviceID, serviceName])
      end
    end

    services.uniq!
    services.sort! {|a,b| a[1].gsub("_","-") <=> b[1].gsub("_","-")}

    html = ""

    services.each do |service|
      serviceID    = service[0]
      serviceName  = service[1]

      html << "<h3><a href=\"/service/#{serviceID}\">#{serviceName}</a></h3>"
    end

    html
  end

  get '/service/:serviceID/?' do
    serviceID   = params[:serviceID]
    redis       = Redis.new
    serviceData = nil

    redis.keys("*").each do |service|
      if service.include? serviceID
        serviceData = JSON.parse(redis.get(service))
      end
    end

    if !serviceData.nil?
      status 200
      jsonp serviceData
    else
      status 404
      {"error":"No service found with ID: #{containerID}"}
    end
  end

  get '/viz/force/?' do
    erb :forceLayout
  end

  get '/viz/tree/?' do
    erb :tree
  end

  get '/viz/grid/?' do
    erb :grid
  end

  get '/viz/cardTest/?' do
    File.read(File.join('html', 'cardTest.html'))
  end

  options '*' do
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'HEAD,GET,PUT,DELETE,OPTIONS'
    response.headers['Access-Control-Allow-Headers'] = 'X-Requested-With, X-HTTP-Method-Override, Content-Type, Cache-Control, Accept'
  end
end

# start the application
run app: Collector.new