#!/bin/bash

if [ -e ".tmp/client.pid" ]; then
  pidfile=.tmp/client.pid
  pid=`cat $pidfile`
  kill $pid 2>/dev/null
  rm $pidfile
  echo "Stopped the client"
else
  echo "No client running"
  exit 1
fi
