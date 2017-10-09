#!/bin/bash
clear

nodes=( $(docker node ls --format "{{.Hostname}}") )
manager=$(hostname)

echo "Listing containers on all nodes:"
echo "--------------------"

for node in "${nodes[@]}"
do
  if [ ${node} != ${manager} ]
  then
    ssh -q -o UserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no ${node} "docker ps --format \"[${node}] {{.ID}}: {{.Names}}\""
  else
    docker ps --format "[${node}] {{.ID}}: {{.Names}}"
  fi
done

