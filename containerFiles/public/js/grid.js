$( document ).ready(function() {
  // WEBSOCKETS
  var Socket = "MozWebSocket" in window ? MozWebSocket : WebSocket;
  var ws = new Socket("ws://piarmy01:8001/viz/grid");

  var sparklines                             = {};
  var sparklineOptions                       = {};
  
  sparklineOptions["cpu-load"]               = {};
  sparklineOptions["cpu-load"].width         = "95%";
  sparklineOptions["cpu-load"].height        = "35px";
  sparklineOptions["cpu-load"].chartRangeMin = 0;
  sparklineOptions["cpu-load"].chartRangeMax = 100;
  sparklineOptions["cpu-load"].lineWidth     = 2;
  sparklineOptions["cpu-load"].spotColor     = "#fff";
  sparklineOptions["cpu-load"].lineColor     = "#fff";
  sparklineOptions["cpu-load"].fillColor     = false;

  sparklineOptions["cpu-temp"]               = {};
  sparklineOptions["cpu-temp"].width         = "95%";
  sparklineOptions["cpu-temp"].height        = "35px";
  sparklineOptions["cpu-temp"].chartRangeMin = 104;
  sparklineOptions["cpu-temp"].chartRangeMax = 176;
  sparklineOptions["cpu-temp"].lineWidth     = 2;
  sparklineOptions["cpu-temp"].spotColor     = "#fff";
  sparklineOptions["cpu-temp"].lineColor     = "#fff";
  sparklineOptions["cpu-temp"].fillColor     = false;

  var sparky = null;
  
  ws.onmessage = function(event) {
    message = JSON.parse(event.data);
    if(message.type == "nodeUpdate"){

      $.each(message.data, function( index, node ) {
        if($("#"+node.Id+" .cpu-load").html() !== node.CPU+"%"){
          console.log("Changing CPU LOAD:", node.Id, $("#"+node.Id+" .cpu-load").html(), " -> ", node.CPU+"%");

          $("#"+node.Id+" .cpu-load").html(node.CPU+"%");
          $("#"+node.Id+" .cpu-load").toggle( "highlight", {color: 'white'});
          $("#"+node.Id+" .cpu-load").toggle( "highlight", {color: 'white'});

          // Update cpu-load sparkline
          var currentSparkValues = $('#'+node.Name+' .sparkline .spark').data('sparkvalues');
          var currentSparkValues = sparklines[node.Name+"cpu-load"].data('sparkvalues');
          var updatedSparkValues = currentSparkValues+","+node.CPU;
          sparklines[node.Name+"cpu-load"].data('sparkvalues', updatedSparkValues);
          updatedSparkValues = updatedSparkValues.split(",");
          sparklines[node.Name+"cpu-load"].sparkline(updatedSparkValues, sparklineOptions["cpu-load"]);
        }

        if($("#"+node.Id+" .cpu-temp").html() !== node.Temp+"°F"){
          console.log("Changing CPU TEMP:", node.Id, $("#"+node.Id+" .cpu-temp").html(), " -> ", node.Temp+"°F");

          $("#"+node.Id+" .cpu-temp").html(node.Temp+"&deg;F");
          $("#"+node.Id+" .cpu-temp").toggle( "highlight", {color: 'white'});
          $("#"+node.Id+" .cpu-temp").toggle( "highlight", {color: 'white'});

          // Update cpu-temp sparkline
          var currentSparkValues = $('#'+node.Name+' .sparkline .spark').data('sparkvalues');
          var currentSparkValues = sparklines[node.Name+"cpu-temp"].data('sparkvalues');
          var updatedSparkValues = currentSparkValues+","+node.Temp;
          sparklines[node.Name+"cpu-temp"].data('sparkvalues', updatedSparkValues);
          updatedSparkValues = updatedSparkValues.split(",");
          sparklines[node.Name+"cpu-temp"].sparkline(updatedSparkValues, sparklineOptions["cpu-temp"]);
        }

        if($("#"+node.Id+" .ram-total").html() !== node.RAM.total){
          console.log("Changing RAM TOTAL:", node.Id, $("#"+node.Id+" .ram-total").html(), " -> ", node.RAM.total);

          $("#"+node.Id+" .ram-total").html(node.RAM.total);
          $("#"+node.Id+" .ram-total").toggle( "highlight", {color: 'white'});
          $("#"+node.Id+" .ram-total").toggle( "highlight", {color: 'white'});
        }

        if($("#"+node.Id+" .ram-free").html() !== node.RAM.free){
          console.log("Changing RAM FREE:", node.Id, $("#"+node.Id+" .ram-free").html(), " -> ", node.RAM.free);

          $("#"+node.Id+" .ram-free").html(node.RAM.free);
          $("#"+node.Id+" .ram-free").toggle( "highlight", {color: 'white'});
          $("#"+node.Id+" .ram-free").toggle( "highlight", {color: 'white'});
        }

        if($("#"+node.Id+" .ram-used").html() !== node.RAM.used){
          console.log("Changing RAM USED:", node.Id, $("#"+node.Id+" .ram-used").html(), " -> ", node.RAM.used);

          $("#"+node.Id+" .ram-used").html(node.RAM.used);
          $("#"+node.Id+" .ram-used").toggle( "highlight", {color: 'white'});
          $("#"+node.Id+" .ram-used").toggle( "highlight", {color: 'white'});
        }
        
      });
    } else {
      console.log("Unknown message type.");
    }
  };

  ws.onclose = function(event) {
    console.log("Closed - code: " + event.code + ", reason: " + event.reason + ", wasClean: " + event.wasClean);
  };

  ws.onopen = function() {
    console.log("connected...");
    msg      = {}
    msg.type = "ping"

    ws.send(JSON.stringify(msg));
  };


  var dockerSwarmContainerCount = 0;
  var dockerSwarmContainers     = [];
  var dockerSwarmNodeCount      = 0;
  var dockerSwarmNodes          = [];

  function getContainers(){
    $.ajax({
      url: "http://piarmy01:8000/containers?callback=containers",

      // The name of the callback parameter
      jsonp: "callback",
   
      // Tell jQuery we're expecting JSONP
      dataType: "jsonp",
   
      // Work with the response
      success: function(containers){
        dockerSwarmContainerCount = containers.length;
        $.each(containers, function( index, container ) {
          $.ajax({
            url: "http://piarmy01:8000/container/"+container[1]+"?callback=containerInfo",
            
            // The name of the callback parameter
            jsonp: "callback",
         
            // Tell jQuery we're expecting JSONP
            dataType: "jsonp",
         
            // Work with the response
            success: function(containerInfo) {
              containerInfo.node = container[0]
              dockerSwarmContainers.push(containerInfo);

              if(dockerSwarmContainers.length == dockerSwarmContainerCount){
                buildGrid();
              }
            },
            error: function( error ) {
              console.log(error);
            }
          });
        });
      },
      error: function( error ) {
        console.log(error);
      }
    });
  }

  function getNodes(){
    $.ajax({
      url: "http://piarmy01:8000/nodes?callback=nodes",

      // The name of the callback parameter
      jsonp: "callback",
   
      // Tell jQuery we're expecting JSONP
      dataType: "jsonp",
   
      // Work with the response
      success: function(nodes) {
        dockerSwarmNodeCount = nodes.length;

        $.each(nodes, function( index, node ) {
          $.ajax({
            url: "http://piarmy01:8000/nodes/"+node+"?callback=node",

            // The name of the callback parameter
            jsonp: "callback",
         
            // Tell jQuery we're expecting JSONP
            dataType: "jsonp",
         
            // Work with the response
            success: function(nodeInfo) {
              dockerSwarmNodes.push(nodeInfo);

              if(dockerSwarmNodes.length == dockerSwarmNodeCount){
                getContainers();
              }
            },
            error: function( error ) {
              console.log(error);
            }
          });
        });
      },
      error: function( error ) {
        console.log(error);
      }
    });
  }

  //This will sort the array
  function nodeSort(a, b){
    if (a.Name < b.Name)
      return -1;
    if (a.Name > b.Name)
      return 1;
    return 0;
  }

  function buildGrid(){
    dockerSwarmNodes.sort(nodeSort);

    console.log("dockerSwarmNodes:", dockerSwarmNodes);
    console.log("dockerSwarmContainers:", dockerSwarmContainers);

    $.each(dockerSwarmNodes, function( index, node ) {
      var containerHTML = "";
      var hereDoc;
      $.each(dockerSwarmContainers, function( index, container ) {
        hereDoc = "";
        if(container.node == node.Name){

          // Mounts
          var service = "";
          if(typeof container.serviceData !== "undefined"){
            service += "<tr><td nowrap>Service ID:</td><td nowrap>"+container.serviceData.ID+"</td></tr><tr><td nowrap>Created At:</td><td nowrap>"+container.serviceData.CreatedAt.substring(0,16)+"</td></tr><tr><td nowrap>Updated At:</td><td nowrap>"+container.serviceData.UpdatedAt.substring(0,16)+"</td></tr>";
          } 

          // IP Address
          var ipAddress = "";
          if(typeof container.NetworkSettings.Networks.piarmy !== "undefined"){
            ipAddress = container.NetworkSettings.Networks.piarmy.IPAddress;
          } else {
            ipAddress = "(none)";
          }

          // Ports
          var mappedPorts = "";
          if(typeof container.serviceData !== "undefined" && typeof container.serviceData.Endpoint.Ports !== "undefined"){
            $.each(container.serviceData.Endpoint.Ports, function( index, ports ) {
              mappedPorts += ports["PublishedPort"]+" -> "+ports["TargetPort"] + "<br />";
            });
          } else {
            mappedPorts += "(none)";
          }

          // Mounts
          mounts = "";
          if(container.Mounts.length > 0){
            $.each(container.Mounts, function( index, mount ) {
              mounts += "["+mount.Source+" -> "+mount.Destination+"]<br />"
            });
          } else {
            mounts += "(none)"
          }

          hereDoc = `
            <div class="col-md-3">
              <div class="card-container">
                <div class="card">

                  <div class="front">
                    <div class="content">
                      <div class="main">
                        <h3 class="name">`+container.Name.split(".")[0].slice(1)+`</h3>
                        <table class="table table-striped table-compact main-data">
                          <tr>
                            <td nowrap>Status:</td><td nowrap>`+container.State.Status+`</td>
                          </tr>`+(service !== "" ? service : `` )+`
                          <tr>
                            <td nowrap>IP Address:</td><td nowrap>`+ipAddress+`</td>
                          </tr>
                          <tr>
                            <td nowrap>Mapped Ports:</td><td nowrap>`+mappedPorts+`</td>
                          </tr>
                          <tr class="container-stats-label">
                            <td>Mounts</td><td>`+mounts+`</td>
                          </tr>
                        </table>
                      </div>
                      <div class="footer">
                        
                      </div>
                    </div>
                  </div> <!-- end front panel -->

                </div> <!-- end card -->
              </div> <!-- end card-container -->
            </div> <!-- end col sm 3 -->
          `.trim()
        }

        containerHTML += hereDoc;
        
      });

      var nodeDataHTML = ""

      nodeDataHTML += "<div>CPU Load: <span class='cpu-load'>"+node.CPU+"%</span><span class='cpu-load-sparkline sparkline'></span></div>"
      nodeDataHTML += "<div>CPU Temp: <span class='cpu-temp'>"+node.Temp+"&deg;F</span><span class='cpu-temp-sparkline sparkline'></span></div>"
      nodeDataHTML += "<div class='cpu-ram'>RAM<ul><li>Total: <span class='ram-total'>"+node.RAM.total+"</span></li><li>Free: <span class='ram-free'>"+node.RAM.free+"</span></li><li>Used: <span class='ram-used'>"+node.RAM.used+"</span></li></ul></div>"
      nodeDataHTML += "<div>HDD<ul><li>Total: <span class='hdd-total'>"+node.HDD.total+"</span></li><li>Free: <span class='hdd-free'>"+node.HDD.free+"</span></li><li>Used: <span class='hdd-used'>"+node.HDD.used+"</span></li></ul></div>"

      $('body').append("<div id="+node.Name+" class='row dockerNode'><div class='col-md-2'><div class='dockerNode-label'>"+node.Name+"</div><div class='node-stats'>"+nodeDataHTML+"</div></div><div class='col-md-10'><div class='row'>"+containerHTML+"</div></div></div>");

      $('.card').matchHeight();
      $('.card table.main-data tbody').matchHeight();
      $('.card table.main-data tbody tr').matchHeight();
      $('.card table.main-data tbody tr td').matchHeight();

      // Sparklines
      // CPU-LOAD
      sparklines[node.Name+"cpu-load"] = $('<span class="spark" data-sparkValues="'+node.CPU+'" >&nbsp;</span>');
      sparklines[node.Name+"cpu-load"].sparkline([node.CPU], sparklineOptions["cpu-load"]);
      $('#'+node.Name+' .cpu-load-sparkline').append(sparklines[node.Name+"cpu-load"]);

      // CPU-TEMP
      sparklines[node.Name+"cpu-temp"] = $('<span class="spark" data-sparkValues="'+node.Temp+'" >&nbsp;</span>');
      sparklines[node.Name+"cpu-temp"].sparkline([node.Temp], sparklineOptions["cpu-temp"]);
      $('#'+node.Name+' .cpu-temp-sparkline').append(sparklines[node.Name+"cpu-temp"]);
      
      // actually render any undrawn sparklines that are now visible in the DOM
      $.sparkline_display_visible();
    });
  }

  getNodes();
});