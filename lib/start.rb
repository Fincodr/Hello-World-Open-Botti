#
#     _/_/_/_/  _/                                      _/
#    _/            _/_/_/      _/_/_/    _/_/      _/_/_/  _/  _/_/
#   _/_/_/    _/  _/    _/  _/        _/    _/  _/    _/  _/_/
#  _/        _/  _/    _/  _/        _/    _/  _/    _/  _/
# _/        _/  _/    _/    _/_/_/    _/_/      _/_/_/  _/
#
# Copyright (c) 2012 Mika Luoma-aho <fincodr@mxl.fi>
#
# This source code and software is provided 'as-is', without any express or implied warranty.
# In no event will the authors be held liable for any damages arising from the use of this source code or software.
#
# Permission is granted to HelloWorldOpen organization to use this software and sourcecode as part of the
# HelloWorldOpen competition as explained in the HelloWorldOpen competition rules.
#
# You are however subject to the following restrictions:
#
# 1. The origin of this software must not be misrepresented; you must not claim that you wrote the original software.
#    If you use this software's source code in a product, an acknowledgment in the documentation will be required.
# 2. Altered versions must be plainly marked as such, and must not be misrepresented as being the original software.
# 3. This notice may not be removed or altered from any distribution.
# 4. Contact author if you need special licensing or usage terms.
#
require 'rubygems'
require 'bundler/setup'
require_relative 'pingpong_client'

player_name = ARGV[0]
server_host = ARGV[1]
server_port = ARGV[2]
Pingpong::Client.new(player_name, server_host, server_port)
