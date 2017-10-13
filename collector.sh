#!/bin/bash
# (sh /home/pi/images/piarmy-collector/collector.sh &) > /dev/null 2>&1

clear

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

collectorContainer="piarmy_collector"
elasticsearchContainer="elasticsearch"
elasticsearchNode="piarmy04"

timestamp() {
  date +"%T"
}

while true
do
  # Check if piarmy-collector is running
  if [[ $(docker ps | grep ${collectorContainer}) ]]; then
    nodes=( $(docker node ls --format "{{.Hostname}}") )
    manager=$(hostname)

    for node in "${nodes[@]}"
    do
      ipAddress=$(docker node inspect ${node} --format "{{.Status.Addr}}")
      
      if [ ${node} != ${manager} ]
      then
        echo "[$(timestamp)] Collecting docker stats: ${node}"
        ssh -q -o UserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no pi@${ipAddress} 'docker inspect $(docker ps -q)' > $DIR/containerFiles/data/${node}.containers.updated.json

        sleep 1

        if [ ! -f $DIR/containerFiles/data/${node}.containers.json ]; then
          echo "[$(timestamp)] File not found, creating: $DIR/containerFiles/data/${node}.containers.json"
          touch $DIR/containerFiles/data/${node}.containers.json
        fi

        md5current=($(md5sum $DIR/containerFiles/data/${node}.containers.json))
        md5updated=($(md5sum $DIR/containerFiles/data/${node}.containers.updated.json))
        echo "[$(timestamp)] MD5 ${node}.containers.json:         ${md5current}"
        echo "[$(timestamp)] MD5 ${node}.containers.updated.json: ${md5updated}"
        
        if [ ${md5current} != ${md5updated} ]
        then
          # Replace file
          echo "[$(timestamp)] Moving file: ${node}.containers.updated.json -> ${node}.containers.json"
          mv $DIR/containerFiles/data/${node}.containers.updated.json $DIR/containerFiles/data/${node}.containers.json
        else
          # Remove updated file
          echo "[$(timestamp)] Removing file: ${node}.containers.updated.json"
          rm $DIR/containerFiles/data/${node}.containers.updated.json
        fi

        echo "[$(timestamp)] Collecting host stats: ${node}"

        # Check and create container files
        if [ ! -f $DIR/containerFiles/data/${node}.json ]; then
          echo "[$(timestamp)] File not found, creating: $DIR/containerFiles/data/${node}.json"
          touch $DIR/containerFiles/data/${node}.json
        fi

        if [ ! -f $DIR/containerFiles/data/${node}.updated.json ]; then
          echo "[$(timestamp)] File not found, creating: $DIR/containerFiles/data/${node}.updated.json"
          touch $DIR/containerFiles/data/${node}.updated.json
        fi

        # Temp
        nodeTempString=$(ssh -q -o UserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no pi@${ipAddress} 'vcgencmd measure_temp')
        nodeTemp=(${nodeTempString//=/ })
        nodeTemp=${nodeTemp[1]::-2}
        nodeTemp=$(echo "scale=2;((9/5) * $nodeTemp) + 32" |bc)

        # RAM
        totalRAM=$(ssh -q -o UserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no pi@${ipAddress} "free -h | grep Mem:" | awk '{print $2}' | sed 's/[^0-9]*//g' )
        usedRAM=$(ssh -q -o UserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no pi@${ipAddress} "free -h | grep Mem:" | awk '{print $3}' | sed 's/[^0-9]*//g' )
        freeRAM=$(ssh -q -o UserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no pi@${ipAddress} "free -h | grep Mem:" | awk '{print $4}' | sed 's/[^0-9]*//g' )

        # HDD
        totalHDD=$(ssh -q -o UserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no pi@${ipAddress} "df -h | grep /dev/root" | awk '{print $2}' | sed 's/[^(0-9)(.)]*//g' )
        usedHDD=$(ssh -q -o UserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no pi@${ipAddress} "df -h | grep /dev/root" | awk '{print $3}' | sed 's/[^(0-9)(.)]*//g' )
        freeHDD=$(ssh -q -o UserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no pi@${ipAddress} "df -h | grep /dev/root" | awk '{print $4}' | sed 's/[^(0-9)(.)]*//g' )

        # CPU 
        cpuUsage=$(ssh -q -o UserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no pi@${ipAddress} "top -bn 2 -d 0.01 | grep '^%Cpu' | tail -n 1" | awk '{print $2+$4+$6}')

        echo "{\"Id\":\"${node}\",\"Name\":\"${node}\",\"Ip\":\"${ipAddress}\",\"CPU\":\"${cpuUsage}\",\"Temp\":\"${nodeTemp}\",\"RAM\":{\"total\": \"${totalRAM}\",\"used\": \"${usedRAM}\",\"free\": \"${freeRAM}\"},\"HDD\":{\"total\": \"${totalHDD}\",\"used\": \"${usedHDD}\",\"free\": \"${freeHDD}\"}}" | tee $DIR/containerFiles/data/${node}.updated.json

        # Check if elasticsearch service is running, if so push stats
        if [[ $(docker service ls | grep ${elasticsearchContainer}) ]]; then
          echo "[$(timestamp)] Pushing data to the Elasticsearch container..."
          DATE=`date +%s%N | cut -b1-13`
          stats="{\"Date\":\"${DATE}\", \"Id\":\"${node}\",\"Name\":\"${node}\",\"Ip\":\"${ipAddress}\",\"CPU\":\"${cpuUsage}\",\"Temp\":\"${nodeTemp}\",\"RAM\":{\"total\": \"${totalRAM}\",\"used\": \"${usedRAM}\",\"free\": \"${freeRAM}\"},\"HDD\":{\"total\": \"${totalHDD}\",\"used\": \"${usedHDD}\",\"free\": \"${freeHDD}\"}}"
          curl -XPOST "http://${elasticsearchNode}:9200/docker_swarm_nodes/stats" -d "${stats}"
        else
          echo "[$(timestamp)] Elasticsearch container not running, skipping data push..."
        fi

        # Replace file
        echo "[$(timestamp)] Moving file: ${node}.updated.json -> ${node}.json"
        mv $DIR/containerFiles/data/${node}.updated.json $DIR/containerFiles/data/${node}.json

        echo "-----"
      else
        echo "[$(timestamp)] Collecting docker stats: ${node}"
        docker inspect $(docker ps -q) > $DIR/containerFiles/data/${node}.containers.updated.json

        sleep 1

        # Check and create container files
        if [ ! -f $DIR/containerFiles/data/${node}.containers.json ]; then
          echo "[$(timestamp)] File not found, creating: $DIR/containerFiles/data/${node}.containers.json"
          touch $DIR/containerFiles/data/${node}.containers.json
        fi

        if [ ! -f $DIR/containerFiles/data/${node}.containers.updated.json ]; then
          echo "[$(timestamp)] File not found, creating: $DIR/containerFiles/data/${node}.containers.updated.json"
          touch $DIR/containerFiles/data/${node}.containers.updated.json
        fi

        md5current=($(md5sum $DIR/containerFiles/data/${node}.containers.json))
        md5updated=($(md5sum $DIR/containerFiles/data/${node}.containers.updated.json))
        echo "[$(timestamp)] MD5 ${node}.containers.json:         ${md5current}"
        echo "[$(timestamp)] MD5 ${node}.containers.updated.json: ${md5updated}"
        
        if [ ${md5current} != ${md5updated} ]
        then
          # Replace file
          echo "[$(timestamp)] Moving file: ${node}.containers.updated.json -> ${node}.containers.json"
          mv $DIR/containerFiles/data/${node}.containers.updated.json $DIR/containerFiles/data/${node}.containers.json
        else
          # Remove updated file
          echo "[$(timestamp)] Removing file: ${node}.containers.updated.json"
          rm $DIR/containerFiles/data/${node}.containers.updated.json
        fi

        echo "[$(timestamp)] Collecting host stats: ${node}"

        # Check and create container files
        if [ ! -f $DIR/containerFiles/data/${node}.json ]; then
          echo "[$(timestamp)] File not found, creating: $DIR/containerFiles/data/${node}.json"
          touch $DIR/containerFiles/data/${node}.json
        fi

        if [ ! -f $DIR/containerFiles/data/${node}.updated.json ]; then
          echo "[$(timestamp)] File not found, creating: $DIR/containerFiles/data/${node}.updated.json"
          touch $DIR/containerFiles/data/${node}.updated.json
        fi

        # Temp
        nodeTempString=$(vcgencmd measure_temp)
        nodeTemp=(${nodeTempString//=/ })
        nodeTemp=${nodeTemp[1]::-2}
        nodeTemp=$(echo "scale=2;((9/5) * $nodeTemp) + 32" |bc)

        # RAM
        totalRAM=$(free -h | grep Mem: | awk '{print $2}' | sed 's/[^0-9]*//g' )
        usedRAM=$(free -h | grep Mem: | awk '{print $3}' | sed 's/[^0-9]*//g' )
        freeRAM=$(free -h | grep Mem: | awk '{print $4}' | sed 's/[^0-9]*//g' )

        # HDD
        totalHDD=$(df -h | grep /dev/root | awk '{print $2}' | sed 's/[^(0-9)(.)]*//g' )
        usedHDD=$(df -h | grep /dev/root | awk '{print $3}' | sed 's/[^(0-9)(.)]*//g' )
        freeHDD=$(df -h | grep /dev/root | awk '{print $4}' | sed 's/[^(0-9)(.)]*//g' )

        # CPU
        cpuUsage=$(top -bn 2 -d 0.01 | grep '^%Cpu' | tail -n 1 | awk '{print $2+$4+$6}')

        echo "{\"Id\":\"${node}\",\"Name\":\"${node}\",\"Ip\":\"${ipAddress}\",\"CPU\":\"${cpuUsage}\",\"Temp\":\"${nodeTemp}\",\"RAM\":{\"total\": \"${totalRAM}\",\"used\": \"${usedRAM}\",\"free\": \"${freeRAM}\"},\"HDD\":{\"total\": \"${totalHDD}\",\"used\": \"${usedHDD}\",\"free\": \"${freeHDD}\"}}" | tee $DIR/containerFiles/data/${node}.updated.json

        # Check if elasticsearch service is running, if so push stats
        if [[ $(docker service ls | grep ${elasticsearchContainer}) ]]; then
          echo "[$(timestamp)] Pushing data to the Elasticsearch container..."
          DATE=`date +%s%N | cut -b1-13`
          stats="{\"Date\":\"${DATE}\", \"Id\":\"${node}\",\"Name\":\"${node}\",\"Ip\":\"${ipAddress}\",\"CPU\":\"${cpuUsage}\",\"Temp\":\"${nodeTemp}\",\"RAM\":{\"total\": \"${totalRAM}\",\"used\": \"${usedRAM}\",\"free\": \"${freeRAM}\"},\"HDD\":{\"total\": \"${totalHDD}\",\"used\": \"${usedHDD}\",\"free\": \"${freeHDD}\"}}"
          curl -XPOST "http://${elasticsearchNode}:9200/docker_swarm_nodes/stats" -d "${stats}"
        else
          echo "[$(timestamp)] Elasticsearch container not running, skipping data push..."
        fi

        # Replace file
        echo "[$(timestamp)] Moving file: ${node}.updated.json -> ${node}.json"
        mv $DIR/containerFiles/data/${node}.updated.json $DIR/containerFiles/data/${node}.json

        # Docker services file
        # Check and create service file
        if [ ! -f $DIR/containerFiles/data/services.json ]; then
          echo "[$(timestamp)] File not found, creating: $DIR/containerFiles/data/services.json"
          touch $DIR/containerFiles/data/services.json
        fi

        if [ ! -f $DIR/containerFiles/data/services.updated.json ]; then
          echo "[$(timestamp)] File not found, creating: $DIR/containerFiles/data/services.updated.json"
          touch $DIR/containerFiles/data/services.updated.json
        fi

        docker inspect $(docker service ls -q) > $DIR/containerFiles/data/services.updated.json

        sleep 1

        md5current=($(md5sum $DIR/containerFiles/data/services.json))
        md5updated=($(md5sum $DIR/containerFiles/data/services.updated.json))
        echo "[$(timestamp)] MD5 services.json:         ${md5current}"
        echo "[$(timestamp)] MD5 services.updated.json: ${md5updated}"

        if [ ${md5current} != ${md5updated} ]
        then
          # Replace file
          echo "[$(timestamp)] Moving file: services.updated,json -> services.json"
          mv $DIR/containerFiles/data/services.updated.json $DIR/containerFiles/data/services.json
        else
          # Remove updated file
          echo "[$(timestamp)] Removing file: services.updated.json"
          rm $DIR/containerFiles/data/services.updated.json
        fi

        echo "-----"
      fi
    done

    sleep 15
  else
    echo "PiArmy Collector is not currently running. Will check again in 30 seconds..."
    sleep 30
  fi
  
done