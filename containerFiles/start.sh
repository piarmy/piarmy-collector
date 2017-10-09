#!/bin/ash
clear

echo "Starting redis server..."
redis-server /etc/redis.conf
sleep 2

echo "Starting Sinatra..."
ruby app.rb