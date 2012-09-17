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
require 'socket'
require 'json'
require 'fileutils'
# added libraries
require 'time'
require 'date'
require 'launchy'
require 'benchmark' if $DEBUG
require_relative 'helpers'

module Pingpong

  class Client

    def initialize(player_name, server_host, server_port)

      @log = Helpers::Log.new

      # banner
      @log.write ""
      @log.write "    _______ __                      __       "
      @log.write "   |    ___|__|.-----.----.-----.--|  |.----."
      @log.write "   |    ___|  ||     |  __|  _  |  _  ||   _|"
      @log.write "   |___|   |__||__|__|____|_____|_____||__|  "
      @log.write ""
      @log.write "   H e l l o W o r l d O p e n   B o t  v0.7"
      @log.write ""
      @log.write "      Coded by Fincodr aka Mika Luoma-aho"
      @log.write "      Send job offers to <fincodr@mxl.fi>"
      @log.write ""

      # log initialize parameters
      @log.write "initialize(#{player_name}, #{server_host}, #{server_port})"
      
      # Initialize global classes
      @config = Helpers::Configuration.new()
      @ownPaddle = Helpers::Paddle.new
      @enemyPaddle = Helpers::Paddle.new
      @ball = Helpers::Ball.new
      @math = Helpers::Math.new
      @scores = Hash.new

      @player_name = player_name

      @total_rounds = 0
      @win_count = 0
      @lose_count = 0

      reset_round

      # open socket to server
      tcp = TCPSocket.open(server_host, server_port)
      play(player_name, tcp)
    end

    private

    def reset_round
      # Set starting values      
      @server_time = nil
      @server_time_elapsed = 0
      @server_time_delta = nil
      @fixed_server_time = nil
      @fixed_server_rate = 1000/10 # TODO: this should be calculated from last full three movement updates instead
      @fixed_server_time_elapsed = 0
      @fixed_server_time_delta = nil
      @local_time = get_localtimestamp
      @local_time_elapsed = 0
      @local_time_delta = 0

      # last updated timestamps
      @updatedLastTimestamp = 0
      @updatedDeltaTime = 0
      @updateRate = 1000/9.9 # limit send rate to ~9.9 msg/s

      # AI settings
      @AI_level = 0.0 # 1.0 = hardest, 0.0 normal and -1.0 easiest (helps the opponent side)
      @paddle_safe_margin = 3
      @paddle_slowdown_margin = 25
      @paddle_slowdown_power = 0
      @target_offset = 0 # check if paddle up/down sides are correct and adjust!
      @max_paddle_speed = 1.0
      @last_sent_changedir = -99.0
      @max_iterations = 10
      @last_enter_angle = 0
      @last_exit_angle = 0
      @last_dirX = 0
      @last_deviation = 0
      @hit_offset = 0
      @hit_offset_max = 0 # will be set again in the update phase
      @last_velocity = nil
      @max_velocity = nil
      @hit_offset_power = 0
      @old_offset_power = 0
      @last_avg_velocity = nil

      # default configuration
      # will be updated from the gameIsOn server message
      @config.set_arena( 640, 480 )
      @config.set_paddle( 10, 50 )
      @config.set_ball( 5 )

      # set class to default values
      @ball.set_position( 640/2, 480/2 )
      @ownPaddle.reset
      @enemyPaddle.reset

      # round info
      @total_rounds += 1

      # temp
      @wanted_y = 240+25
      @old_wanted_y = @wanted_y
      @passed_wanted_y = false

    end

    def play(player_name, tcp)
      @log.write "> join(#{player_name})"
      tcp.puts join_message(player_name)
      react_to_messages_from_server tcp
    end

    def react_to_messages_from_server(tcp)
      while json = tcp.gets
        message = JSON.parse(json)
        case message['msgType']

          when 'joined'
            @log.write "< joined: #{json}"
            Launchy.open(message['data'])

          when 'gameStarted'
            @log.write "< gameStarted: #{json}"

          when 'gameIsOn'

            # update local time from clock
            @local_time = get_localtimestamp

            if $DEBUG
              @log.write "< gameIsOn: #{json}"
            end
            msg = message['data']

            # update server time from json packet
            if not @server_time.nil?
              @server_time_delta = Integer(msg['time']) - @server_time
            end            
            @server_time = Integer(msg['time'])
            if not @server_time_delta.nil?
              @server_time_elapsed += @server_time_delta
            end

            # update fixed server time
            @fixed_server_time_delta = @fixed_server_rate
            if @fixed_server_time.nil?
              @fixed_server_time = @server_time
            else
              @fixed_server_time += @fixed_server_time_delta
            end

            # debug output to compare server and fixed timesteps
            #@log.debug "S: #{@server_time} F: #{@fixed_server_time} D: #{@fixed_server_time-@server_time}"

            # update ball information from json packet
            begin
              msg_ball = msg['ball']
              @ball.set_position( Float(msg_ball['pos']['x']), Float(msg_ball['pos']['y']) )
            rescue
              @log.write "Warning: Ball block missing from json packet"
              # we don't know where the ball is, stop simulating
            end

            # update configuration information from json packet
            begin
              msg_conf = msg['conf']
              @config.set_arena( msg_conf['maxWidth'], msg_conf['maxHeight'] )
              @config.set_paddle( msg_conf['paddleWidth'], msg_conf['paddleHeight'] )
              @config.set_ball( msg_conf['ballRadius'] )
              h = msg_conf['paddleHeight'] / 2 - @paddle_safe_margin # varmuuden vuoksi vielä 1 lisää marginaaliin :)
              if ( h < 5 )
                h = 0
              end
              @hit_offset_max = h
            rescue
              @log.write "Warning: Configuration block missing from json packet"
            end

            # update player information from json packet
            # player information is stored internally so that y is the center of paddle
            begin
              msg_own = msg['left']
              msg_enemy = msg['right']
              @ownPaddle.set_position( 0, Float(msg_own['y']) + @config.paddleHeight/2 )
              @enemyPaddle.set_position( @config.arenaWidth, Float(msg_enemy['y']) + @config.paddleHeight/2 )
            rescue
              @log.write "Warning: Player block missing from json packet"
            end

            ###############################################
            #
            # Simulation code start
            #
            # If all points are on the same line, we can calculate ball trajectory
            #
            distance_to_player = 0
            distance_to_enemy = 0
            time_to_player = 0
            time_to_enemy = 0
            last_deltaX = 0
            last_deltaY = 0

            if @math.on_the_same_line( @ball.x, @ball.y, @ball.x2, @ball.y2, @ball.x3, @ball.y3 )

              # set the start position
              x3 = @ball.x2
              y3 = @ball.y2
              x2 = @ball.x
              y2 = @ball.y

              # calculate velocity if the clock has advanced
              if not @server_time_delta.nil?

                velocity = (@ball.x2 - @ball.x).abs / @server_time_delta # Math.hypot( x2-x3,y2-y3 ) / @fixed_server_time_delta #@server_time_delta

                # calculate average velocity
                #if not @last_velocity.nil?
                #  @last_avg_velocity = (@last_velocity + velocity) / 2
                #  #@log.debug "#{@last_velocity} + #{velocity} / 2 = #{@last_avg_velocity}"
                #  if not @max_velocity.nil?
                #    if @last_avg_velocity > @max_velocity
                #      @max_velocity = @last_avg_velocity
                #    end
                #  else
                #    @max_velocity = @last_avg_velocity
                #  end
                #else
                #  @last_avg_velocity = nil
                #end

                @last_velocity = velocity

                if @max_velocity != nil
                  if @last_velocity > @max_velocity
                    #@log.debug "Max Velocity now #{@last_velocity}, Time = #{@server_time_elapsed}"
                    @max_velocity = @last_velocity
                  end
                else
                  @max_velocity = @last_velocity
                end

              end

              # when velocity gets over 0.5 we must try to win on the next pass
              #@log.debug "Velocity = #{@last_velocity}, Max Velocity = #{@max_velocity}, Elapsed time = #{@server_time_elapsed}"
              #if not @max_velocity.nil?
              #  if @max_velocity > 0.4
              #    @AI_level = 1.0 # 1.0 = hardest, 0.0 normal and -1.0 easiest (helps the opponent side)
              #  end
              #end

              last_deltaX = x2-x3
              last_deltaY = y2-y3

              if not @last_velocity.nil?
                # set the paddle slowdown power depending on the last velocity reading
                #
                # paddle slowdown power is calculated from normal velocity to velocity + 0.5
                # and scaled accordingly so when velocity is 0.5 or over we get slowdown power
                # of zero (= no slowdown, but on the sides it will still always slowdown
                # atleast with margin of 5
                @paddle_slowdown_power = 1.0 - (@max_velocity - 0.250)
                @paddle_slowdown_power = 1.0 if @paddle_slowdown_power > 1.0
                @paddle_slowdown_power = 0.5 if @paddle_slowdown_power < 0.5
                @paddle_slowdown_power -= 0.5
                @paddle_slowdown_power *= 2

                # scale hit_offset depending on the last velocity
                # note: starting velocity is usually about 0.250
                @hit_offset_power = 1.0 - ( @last_velocity - 0.250 )
                @hit_offset_power = 1.0 if @hit_offset_power > 1.0
                @hit_offset_power = 0.0 if @hit_offset_power < 0.0
              else
                @paddle_slowdown_power = 1.0
                @hit_offset_power = 1.0
              end                

              if @hit_offset_power != @old_offset_power
                #@log.debug "Offset power now at #{@hit_offset_power} (max velocity #{@max_velocity}"
                @old_offset_power = @hit_offset_power
              end

              #@log.write "Info: Server time delta = #{@server_time_delta} (fixed rate = #{@fixed_server_rate}" if $DEBUG
              #$stderr.puts "Info: Last velocity = #{@last_velocity}"
              x1 = 0.0
              y1 = 0.0
              deltaX = x2-x3
              if ( deltaX < 0 )
                dirX = -1
              else
                dirX = 1
              end
              if dirX != @last_dirX
                if dirX > 0
                  #@log.write "Info: Direction changed, now going towards enemy" if $DEBUG
                  @last_exit_angle = @math.calculate_line_angle( x3, y3, x2, y2 )
                  @log.write "Info: Last enter angle was #{@last_enter_angle} and exit angle is now #{@last_exit_angle}" if $DEBUG
                  # check deviation from normal bounce angle
                  expected_exit_angle = 180 - @last_enter_angle
                  @last_deviation = @last_exit_angle - expected_exit_angle
                  if @last_enter_angle <= 90
                    @log.write "Info: Deviation from <90 to normal exit angle = #{@last_deviation}" if $DEBUG
                  else
                    @log.write "Info: Deviation from >90 to normal exit angle = #{@last_deviation}" if $DEBUG
                  end
                end
                @last_dirX = dirX
              end

              if ( deltaX < 0 )

                # ball is coming towards us
                iterator = 0

                while iterator < @max_iterations

                  deltaX = x2-x3
                  deltaY = y2-y3

                  if deltaY < 0
                    y1 = @config.ballRadius
                  else
                    y1 = @config.arenaHeight - @config.ballRadius - 1
                  end

                  x1 = @math.calculate_collision(y1, x2, y2, x3, y3)

                  if x1 < @config.paddleWidth + @config.ballRadius
                    # no collision, calculate direct line
                    x1 = @config.paddleWidth + @config.ballRadius
                    y1 = @math.calculate_collision(x1, y2, x2, y3, x3)
                    distance_to_player += Math.hypot( x1-x2,y1-y2 )

                    # calculate current angle
                    @last_enter_angle = @math.calculate_line_angle( x1, y1, x2, y2 )
                    if y1 < @config.paddleHeight or y1 > (@config.arenaHeight - @config.paddleHeight)
                      @hit_offset = 0
                    else
                      temp_AI_level = @AI_level
                      if @last_enter_angle <= 90
                        if @AI_level < 0
                          # we are helping opponent :)
                          if @last_enter_angle >= 90-15
                            @deviation_from_straight = ( 90 - @last_enter_angle ) / 15
                          else
                            @deviation_from_straight = 1.0
                          end
                          temp_AI_level *= @deviation_from_straight
                        end
                        @hit_offset = -(@hit_offset_max * @hit_offset_power) * temp_AI_level
                      else
                        if @AI_level < 0
                          # we are helping opponent :)
                          if @last_enter_angle < 90+15
                            @deviation_from_straight = ( @last_enter_angle - 90 ) / 15
                          else
                            @deviation_from_straight = 1.0
                          end
                          temp_AI_level *= @deviation_from_straight
                        end
                        @hit_offset = (@hit_offset_max * @hit_offset_power) * temp_AI_level
                      end
                    end
                    @ownPaddle.set_target(y1 + @hit_offset)
                    @log.write "Info: Own enter angle = #{@last_enter_angle}" if $DEBUG
                    break
                  end

                  distance_to_player += Math.hypot( x1-x2,y1-y2 )

                  # Set new start position to the collision point (using the same velocity)
                  x2 = x1
                  y2 = y1
                  x3 = x2 - deltaX
                  y3 = y2 + deltaY

                  # increment iteration count
                  iterator+=1

                end # /while

              else

                # ball is going to opposite side
                # we can still calculate where it would hit and how it would bounce back to us
                iterator = 0
                
                while iterator < @max_iterations*2

                  deltaX = x2-x3
                  deltaY = y2-y3

                  if deltaY < 0
                    y1 = @config.ballRadius
                  else
                    y1 = @config.arenaHeight - @config.ballRadius - 1
                  end

                  x1 = @math.calculate_collision(y1, x2, y2, x3, y3)

                  if x1 < @config.paddleWidth + @config.ballRadius
                    # no collision, calculate direct line
                    x1 = @config.paddleWidth + @config.ballRadius
                    y1 = @math.calculate_collision(x1, y2, x2, y3, x3)
                    distance_to_player += Math.hypot( x1-x2,y1-y2 )
                    time_to_player = distance_to_player / @fixed_server_time_delta
                    # calculate current angle
                    @last_enter_angle = @math.calculate_line_angle( x1, y1, x2, y2 )
                    if y1 < @config.paddleHeight or y1 > (@config.arenaHeight - @config.paddleHeight)
                      @hit_offset = 0
                    else
                      temp_AI_level = @AI_level
                      if @last_enter_angle <= 90
                        if @AI_level < 0
                          # we are helping opponent :)
                          if @last_enter_angle >= 90-15
                            @deviation_from_straight = ( 90 - @last_enter_angle ) / 15
                          else
                            @deviation_from_straight = 1.0
                          end
                          temp_AI_level *= @deviation_from_straight
                        end
                        @hit_offset = -(@hit_offset_max * @hit_offset_power) * temp_AI_level
                      else
                        if @AI_level < 0
                          # we are helping opponent :)
                          if @last_enter_angle < 90+15
                            @deviation_from_straight = ( @last_enter_angle - 90 ) / 15
                          else
                            @deviation_from_straight = 1.0
                          end
                          temp_AI_level *= @deviation_from_straight
                        end
                        @hit_offset = (@hit_offset_max * @hit_offset_power) * temp_AI_level
                      end
                    end
                    @ownPaddle.set_target(y1 + @hit_offset)
                    @log.write "Info: Own enter angle = #{@last_enter_angle}" if $DEBUG
                    #@log.debug "Ball is going to hit at #{x1}, #{y1} with distance of #{distance_to_player} pixels."
                    break
                  end

                  if x1 > @config.arenaWidth - @config.paddleWidth - @config.ballRadius
                    # no collision, calculate direct line
                    x1 = @config.arenaWidth - @config.paddleWidth - @config.ballRadius
                    y1 = @math.calculate_collision(x1, y2, x2, y3, x3)
                    distance_to_player += Math.hypot( x1-x2,y1-y2 )
                    distance_to_enemy += Math.hypot( x1-x2,y1-y2 )
                    @enemyPaddle.set_target(y1)

                    # calculate current angle
                    #@last_enter_angle = @math.calculate_line_angle( x2, y2, x1, y1 )
                    #@log.write "Info: Enemy enter angle = #{@last_enter_angle}" if $DEBUG
                    #
                    # TODO:
                    #
                    #distance_to_paddle = (y1 - @enemyPaddle.y).abs
                    #
                    # calculate how many seconds it takes the ball to hit the enemy side
                    # calculate where enemy is going to be at that time
                    # get the difference and paddle location
                    #
                    #delta = (distance_to_enemy - distance_to_paddle)
                    #@log.debug "BallHit @ #{y1} (dist=#{distance_to_enemy}px), p-dist=#{distance_to_paddle} #{delta})"
                    # bounce ball back and continue

                    x2 = x1
                    y2 = y1
                    x3 = x2 + deltaX
                    y3 = y2 - deltaY
                    deltaX = x2-x3
                    deltaY = y2-y3
                    # increment iteration count
                    iterator+=1
                    next
                  end

                  distance_to_player += Math.hypot( x1-x2,y1-y2 )
                  if ( deltaX > 0 )
                    distance_to_enemy += Math.hypot( x1-x2,y1-y2 )
                  end

                  # Set new start position to the collision point (using the same velocity)
                  x2 = x1
                  y2 = y1
                  x3 = x2 - deltaX
                  y3 = y2 + deltaY

                  # increment iteration count
                  iterator+=1

                end # /while   

                if iterator == @max_iterations*2
                  # ok, too much work, we can just go to middle
                  #@ownPaddle.set_target( @config.arenaHeight / 2 )
                end

              end # /if

            else

              #@log.debug "Hit detected!"

            end # /if on_the_same_line 
            #
            # Simulation code end
            #
            ###############################################

            #@log.debug "< #{@last_enter_angle} | #{@paddle_slowdown_power}"

            if @local_time - @updatedLastTimestamp > @updateRate && @ownPaddle.target_y != nil #&& @ownPaddle.avg_target_y != nil

              @updatedLastTimestamp = @local_time

              min_slowdown = 0
              @wanted_y = @ownPaddle.target_y #.avg_target_y
              if @wanted_y < @config.paddleHeight/2 + 1
                @wanted_y = @config.paddleHeight/2 + 1
                min_slowdown = 5
              end
              if @wanted_y > @config.arenaHeight - @config.paddleHeight/2 - 2
                @wanted_y = @config.arenaHeight - @config.paddleHeight/2 - 2
                min_slowdown = 5
              end

              if @wanted_y != @old_wanted_y
                @intial_wanted_run = true
              end

              speed = @max_paddle_speed
              delta = @ownPaddle.y - @wanted_y
              #@log.debug "Wanted: #{@wanted_y} -> Got: #{@ownPaddle.y} -> Delta = #{delta} (#{@paddle_slowdown_power})"

              paddle_slowdown = @paddle_slowdown_margin * @paddle_slowdown_power
              if paddle_slowdown < min_slowdown
                paddle_slowdown = min_slowdown
              end
              if delta.abs < paddle_slowdown
                speed = delta.abs / paddle_slowdown
              end
              if speed > @max_paddle_speed
                speed = @max_paddle_speed
              end

              # ball distance is more than our delta
              # so move the paddle at maximum speed
              #if distance_to_player <= delta
              #  speed = 1.0
              #end

              #if not @max_velocity.nil?
              #  if @max_velocity > 0.5 && @AI_level == -1.0
              #    delta = @ownPaddle.y - @enemyPaddle.y #ball.y
              #    speed = (@ownPaddle.y - @enemyPaddle.y).abs / 10
              #  end
              #end

              if delta < 0
                @log.write "> changeDir(#{speed})" if $DEBUG
                tcp.puts movement_message(speed)
              elsif delta > 0
                @log.write "> changeDir(#{-speed})" if $DEBUG
                tcp.puts movement_message(-speed)
              else
                @log.write "> changeDir(0)" if $DEBUG
                tcp.puts movement_message(0)
              end

            end # /if

          when 'gameIsOver'
            winner = message['data']
            if winner == @player_name
              @win_count += 1
            else
              @lose_count += 1
            end
            @log.write "< gameIsOver: Winner is #{winner} | Win:#{@win_count} Lose:#{@lose_count} Total:#{@total_rounds}"
            @log.debug "gameIsOver: Winner is #{winner} | Win:#{@win_count} Lose:#{@lose_count} Total:#{@total_rounds}" if $DEBUG
            if @scores.has_key?(winner)
              @scores[winner]+=1 # increment score for specified playername
            else
              @scores[winner]=1
            end
            @scores.each {|key, value| @log.write "Info: Scores: #{key}: #{value}" }
            reset_round

          else
            # unknown message received
            @log.write "< unknown_message: #{json}" if $DEBUG
        end
      end
    end

    def join_message(player_name)
      %Q!{"msgType":"join","data":"#{player_name}"}!
    end

    def movement_message(delta)
      %Q!{"msgType":"changeDir","data":#{delta}}!
    end

    def get_localtimestamp
      return (Time.now.to_f * 1000.0).to_i
    end

  end # /Client  

end # / module