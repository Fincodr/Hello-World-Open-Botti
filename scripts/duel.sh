#!/bin/bash

playername=$1
host=$2
port=$3
othername=$4
pidfile=.tmp/client_$1.pid

if [ -z $port ]; then
  echo "Usage: `basename $0` <playername> <serverhost> <serverport> <othername>"
  echo ""
  echo "Starts a Pingpong Ruby client against a server (or othername player)"
  exit 1
fi

function ensure_pid_file() {
  mkdir .tmp 2>/dev/null
  touch $pidfile
}

function exit_if_running() {
  pid=`cat $pidfile`
  kill -0 $pid 2>/dev/null
  if [ "$?" == "0" ]; then
    echo "Client is already running (pid $pid)"
    exit 1
  fi
}

function start_client() {
  logfile=client.log
  echo "Logging into $logfile"
  (ruby lib/start.rb $playername $host $port $othername &>$logfile) & echo $! > $pidfile
}

ensure_pid_file
exit_if_running
start_client