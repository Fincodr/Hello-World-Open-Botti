require 'rubygems'
require 'bundler/setup'
require_relative 'pingpong_client'

player_name = ARGV[0]
server_host = ARGV[1]
server_port = ARGV[2]
Pingpong::Client.new(player_name, server_host, server_port)
