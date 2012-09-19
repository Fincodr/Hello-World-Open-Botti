#encoding: utf-8

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

    def initialize(player_name, server_host, server_port, other_name = nil)

      @log = Helpers::Log.new

      # banner
      show_banner

      # log initialize parameters
      if other_name.nil?
        @log.write "initialize(#{player_name}, #{server_host}, #{server_port})"
      else
        @log.write "initialize(#{player_name}, #{server_host}, #{server_port}, #{other_name})"
      end
      
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
      if other_name.nil?
        play(player_name, tcp)
      else
        duel(player_name, other_name, tcp)
      end
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
      @local_vs_server_delta = nil
      @local_vs_server_drift = 0

      # last updated timestamps
      @updatedLastTimestamp = 0
      @updatedDeltaTime = 0
      @updateRate = 1000/9.9 # limit send rate to ~9.9 msg/s

      # AI settings
      @last_bounce_state = 0 # 0 = no collision, collision 1st, collision 2nd
      @AI_level = 1.0 # 1.0 = hardest, 0.0 normal and -1.0 easiest (helps the opponent side)
      @paddle_safe_margin = 6
      @paddle_slowdown_margin = 25
      @paddle_slowdown_power = 1.0
      @target_offset = 0 # check if paddle up/down sides are correct and adjust!
      @max_paddle_speed = 1.0
      @last_sent_changedir = -99.0
      @max_iterations = 10
      @last_enemy_enter_angle = 0
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
      @ball.reset
      @ownPaddle.reset
      @enemyPaddle.reset

      # round info
      @total_rounds += 1

      # temp
      @wanted_y = 240+25
      @old_wanted_y = @wanted_y
      @passed_wanted_y = false

    end

    def duel(player_name, other_name, tcp)
      @log.write "> duel(#{player_name} vs #{other_name})"
      tcp.puts duel_message(player_name, other_name)
      react_to_messages_from_server tcp
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
              @log.write "< gameIsOn: lag:#{@local_vs_server_drift} #{json}"
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

            # update local vs server delta (onetime)
            if @local_vs_server_delta.nil?
              @local_vs_server_delta = @local_time - @server_time
            end

            # update fixed server time
            @fixed_server_time_delta = @fixed_server_rate
            if @fixed_server_time.nil?
              @fixed_server_time = @server_time
            else
              @fixed_server_time += @fixed_server_time_delta
            end

            # debug output to compare server and fixed timesteps
            #@log.debug "S: #{@server_time} L: #{@local_time} D: #{(@local_time-@server_time)-@local_vs_server_delta}"
            @local_vs_server_drift = (@local_time-@server_time)-@local_vs_server_delta

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
              @config.set_arena( Float(msg_conf['maxWidth']), Float(msg_conf['maxHeight']) )
              @config.set_paddle( Float(msg_conf['paddleWidth']), Float(msg_conf['paddleHeight']) )
              @config.set_ball( Float(msg_conf['ballRadius']) )
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
            distance_to_player = 0
            distance_to_enemy = 0
            time_to_player = 0
            time_to_enemy = 0
            last_deltaX = 0
            last_deltaY = 0

            #----------------------------------------------
            #
            # ====================
            # Check for collisions
            # ====================
            #
            # Check for collisions and make corrections to
            # the ball velocity and heading information
            #
            # To check for collisions and calculate new
            # velocity and heading values we need to have
            # at least two history points
            #
            #----------------------------------------------
            if not @ball.x2.nil? and not @ball.x3.nil?

              # Case #1 - All points are on the same line
              if @math.on_the_same_line( @ball.x, @ball.y, @ball.x2, @ball.y2, @ball.x3, @ball.y3 )

                #@log.write "COLLISION CASE #0: No collision, all points are on the same line"
                # all points are on the same line
                @last_bounce_state = 0

              else

                x3 = @ball.x3
                y3 = @ball.y3
                x2 = @ball.x2
                y2 = @ball.y2
                x1 = @ball.x
                y1 = @ball.y

                case @last_bounce_state

                  when 0
                    # Case #2 - P1 is not on the same line with P2 and P3
                    if not @math.is_p1_on_the_same_p2p3_line( @ball.x, @ball.y, @ball.x2, @ball.y2, @ball.x3, @ball.y3 )
                      @last_bounce_state = 1
                      @log.write "COLLISION CASE #1: P1 is not on the same line as P2 and P3"
                      @log.debug "COLLISION CASE #1: P1 is not on the same line as P2 and P3"
                      # find the collision point using the current velocity
                      # Note: Can collide with any surface
                      deltaX = x2-x3
                      deltaY = y2-y3
                      if deltaY < 0
                        y = @config.ballRadius
                      else
                        y = @config.arenaHeight - @config.ballRadius - 1
                      end
                      # calculate what x-coordinate the ball is going to hit
                      x = @math.calculate_collision(y, x2, y2, x3, y3)
                      if x <= @config.paddleWidth + @config.ballRadius
                        # collision with left paddle
                        if rand(2) == 0
                          @AI_level = -1.0
                        else
                          @AI_level = 1.0
                        end
                        #x = @config.paddleWidth + @config.ballRadius
                        #y = @math.calculate_collision(x, y2, x2, y3, x3)
                        @ball.x2 = x1 + deltaX
                        @ball.y2 = y1 - deltaY
                      elsif x >= @config.arenaWidth - @config.paddleWidth - @config.ballRadius - 1
                        # collision with right paddle
                        #x = @config.arenaWidth - @config.paddleWidth - @config.ballRadius - 1
                        #y = @math.calculate_collision(x, y2, x2, y3, x3)
                        @ball.x2 = x1 + deltaX
                        @ball.y2 = y1 - deltaY
                      else
                        # collision with arena edges
                        @ball.x2 = x1 - deltaX
                        @ball.y2 = y1 + deltaY
                      end

                      @ball.x3 = nil
                      @ball.y3 = nil

                    else
                      @last_bounce_state = 0
                      @log.write "Warning: Unknown collision!"
                      # we do not know what is the situation
                      # just send the paddle to the ball-y
                      #@ownPaddle.set_target( @ball.y )
                    end

                  when 1
                    # Case #3 - P3 is not on the same line with P1 and P2
                    if not @math.is_p3_on_the_same_p1p2_line( @ball.x, @ball.y, @ball.x2, @ball.y2, @ball.x3, @ball.y3 )
                      @last_bounce_state = 2
                      @log.write "COLLISION CASE #2: P3 is not on the same line as P1 and P2"
                      @log.debug "COLLISION CASE #2: P3 is not on the same line as P1 and P2"
                      # the last known point is not on the new line
                      # so we can just use the current point and
                      # previous position for velocity and heading
                      # we will however clear the last point info
                      @ball.x3 = nil
                      @ball.y3 = nil

                    else
                      @last_bounce_state = 0
                      @log.write "Warning: Unknown collision!"
                      # we do not know what is the situation
                      # just send the paddle to the ball-y
                      #@ownPaddle.set_target( @ball.y )
                    end

                end #/ case

              end #/ on_the_same_line            else

            end #/ if ball.x2 and x3 are not nill

            #----------------------------------------------
            #
            # ==================
            # Calculate velocity
            # ==================
            #
            # We are keeping current velocity and maximum
            # velocity in local variables
            #
            # To calculate velocity we need to have atleast
            # one history point.
            #
            #----------------------------------------------
            if not @ball.x2.nil? and not @server_time_delta.nil?
              last_deltaX = @ball.x2-@ball.x
              last_deltaY = @ball.y2-@ball.y
              velocity = Math.hypot( last_deltaX, last_deltaY ) / @server_time_delta
              #@log.write "#{@ball.x2},#{@ball.y2} to #{@ball.x},#{@ball.y} = #{last_deltaX},#{last_deltaY} => #{@last_velocity}"
              # calculate average velocity
              if not @last_velocity.nil?
                @last_avg_velocity = (@last_velocity + velocity) / 2
                if not @max_velocity.nil?
                  if @last_avg_velocity > @max_velocity
                    @max_velocity = @last_avg_velocity
                  end
                else
                  @max_velocity = @last_avg_velocity
                end
                @log.debug "#{@last_velocity} + #{velocity} / 2 = #{@last_avg_velocity} (max = #{@max_velocity})"
              else
                @last_avg_velocity = nil
              end
              @last_velocity = velocity
            end

            #@log.debug "#{@last_velocity}"

            #if @max_velocity.nil?
            #  @max_velocity = @last_velocity
            #else
            #  if @last_velocity > @max_velocity
            #    @max_velocity = @last_velocity
            #  end
            #end

            #----------------------------------------------
            #
            # ===========================================
            # Setup the paddle slowdown and offset powers
            # ===========================================
            #
            # The slowdown power is used to set the usable
            # power level for slowing down the paddle to
            # the correct positions. When the ball velocity
            # is higher we must use less slowdown power
            # because we need to get to the "ball" position
            # faster.
            #
            # The offset power is used to set the usable
            # offset range for adjusting the ball heading.
            # When the velocity is higher we must use
            # smaller offset values to be able to hit
            # the ball at higher speeds. Offset power
            # is also scaled using the calculated
            # last enter angle so that if the ball is
            # coming in from high angle we are not going
            # to try to use offset that much.
            #
            #
            # Also depending on the AI level we are
            # adjusting the offset so that if we are
            # helping the opponent we are switching the
            # offset power to negative values.
            #
            # Note: If we dont know the ball velocity yet
            #       we are just setting the powers to full
            #
            #----------------------------------------------
            if not @max_velocity.nil?
              # set the paddle slowdown power depending on the last velocity reading
              #
              # paddle slowdown power is calculated from normal velocity to velocity + 0.5
              # and scaled accordingly so when velocity is 0.5 or over we get slowdown power
              # of zero (= no slowdown, but on the sides it will still always slowdown
              # atleast with margin of 5
              #@paddle_slowdown_power = 1.0 - (@max_velocity - 0.250)
              #@paddle_slowdown_power = 1.0 if @paddle_slowdown_power > 1.0
              #@paddle_slowdown_power = 0.5 if @paddle_slowdown_power < 0.5
              #@paddle_slowdown_power -= 0.5
              #@paddle_slowdown_power *= 2
              #@log.debug "Paddle slowdown power: #{@paddle_slowdown_power}"

              # scale hit_offset depending on the last velocity
              # note: starting velocity is usually about 0.250
              @hit_offset_power = 1.0 - ( Float(@max_velocity/3) - 0.250 )
              @hit_offset_power = 1.0 if @hit_offset_power > 1.0
              @hit_offset_power = 0.0 if @hit_offset_power < 0.0

              # scale hit_offset depending on the estimated enter angle
              # safe angles are -25 .. +25 and anything over that should decrement the power
              angle_hit_offset_power = @math.angle_to_hit_offset_power @last_enter_angle
              #@log.debug "Last enter angle: #{@last_enter_angle} = #{angle_hit_offset_power}"
              @hit_offset_power *= angle_hit_offset_power

              # scale hit_offset depenging on the current paddle location
              # so that when we are near the edges we are using less power to
              # change the trajectory (safe zone is paddleHeight area)
              #if @AI_level > 0.0
              #  begin
              #    location_hit_offset_power = 1.0 - (((@ownPaddle.y - @config.arenaHeight/2).abs - @config.paddleHeight) / (@config.arenaHeight/2 - @config.paddleHeight))
              #    location_hit_offset_power = 1.0 if location_hit_offset_power > 1.0
              #  rescue
              #    location_hit_offset_power = 1.0
              #  end
              #  @hit_offset_power *= location_hit_offset_power
              #  #@log.debug "Location hit offset power in effect at #{location_hit_offset_power}"
              #end
            #else
            #  @paddle_slowdown_power = 1.0
            #  @hit_offset_power = 1.0
            end                

            if @hit_offset_power != @old_offset_power
              @log.debug "Offset power now at #{@hit_offset_power} (max velocity #{@max_velocity}"
              @old_offset_power = @hit_offset_power
            end

            #@log.write "Info: Server time delta = #{@server_time_delta} (fixed rate = #{@fixed_server_rate}" if $DEBUG



            #----------------------------------------------
            #
            

            #----------------------------------------------
            #
            # ================================
            # Main future collision simulation
            # ================================
            #
            # Ball flight path is simulated for both
            # directions.
            #
            # First we start from the current ball position
            # and using the known velocity we calculate the
            # next collision point. The collision point
            # can be on the player/opponent paddle or at the
            # arena edges.
            #
            # a.) If the collision happends at the arena
            #     edges we then set the start location to
            #     that point and set the velocity again
            #     and then continue simulating.
            # b.) If the collision happends at the opponent
            #     paddle we can set the opponent target-y
            #     and continue simulating.
            # c.) If the collision happends at the player
            #     paddle we set that point as our target-y
            #
            # The local variables used are:
            #
            # - x1 = the ball (start/current) location
            # - y1 = the ball (start/current) location
            # - x2 = the ball previous location
            # - y2 = the ball previous location
            # - x = temporal left/right paddle edge
            # - y = temporal top/bottom arena edge
            # - deltaX = the ball x delta (x-velocity)
            # - deltaY = the ball y delta (y-velocity)
            # - iterator = simulated bounces count
            #
            # TODO: Set more iterations if ball initial velocity is away from us
            #
            #----------------------------------------------
            distance_to_player = 0
            distance_to_enemy = 0
            if not @ball.x2.nil? and not @server_time_delta.nil?
              x2 = @ball.x2
              y2 = @ball.y2
              x1 = @ball.x
              y1 = @ball.y
              iterator = 0
              # ======================
              # Set the direction flag
              # ======================
              # Direction flag is used for notifying the AI
              # of ball direction changes
              if ( last_deltaX < 0 )
                dirX = -1
              else
                dirX = 1
              end
              if dirX != @last_dirX
                if dirX > 0
                  if not x2.nil?
                    #@log.write "Info: Direction changed, now going towards enemy" if $DEBUG
                    #if not @max_velocity.nil?
                    #  if @max_velocity > 0.3
                    #    @AI_level = 1.0 # 1.0 = hardest, 0.0 normal and -1.0 easiest (helps the opponent side)
                    #  end
                    #end
                    @last_exit_angle = @math.calculate_line_angle( x2, y2, x1, y1 )
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
                end
                @last_dirX = dirX
              end

              # loop while we are simulating
              while iterator < @max_iterations

                deltaX = x1-x2
                deltaY = y1-y2

                # check the ball y-velocity and set the collision
                # check line y-coordinate
                if deltaY < 0
                  y = @config.ballRadius
                else
                  y = @config.arenaHeight - @config.ballRadius - 1
                end

                # calculate what x-coordinate the ball is going to hit
                x = @math.calculate_collision(y, x1, y1, x2, y2)

                # ball is going to hit the left side
                if x <= @config.paddleWidth + @config.ballRadius

                  # no collision, calculate direct line
                  x = @config.paddleWidth + @config.ballRadius
                  y = @math.calculate_collision(x, y1, x1, y2, x2)

                  # add the travelled path to the distances
                  distance_to_player += Math.hypot( x-x1, y-y1 )
                  if ( deltaX > 0 )
                    distance_to_enemy += Math.hypot( x-x1, y-y1 )
                  end

                  # calculate current angle
                  @last_enter_angle = @math.calculate_line_angle( x, y, x1, y1 )
                  # TODO: Should this be enabled? This would set the hit_offset to zero if
                  #       the ball is going to hit at the paddle area at the edge of the arena
                  #if y < @config.paddleHeight or y > (@config.arenaHeight - @config.paddleHeight)
                  #  @hit_offset = 0
                  #else
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
                  #end

                  @ownPaddle.set_target(y + @hit_offset)

                  #@log.write "Info: Own enter angle = #{@last_enter_angle}" if $DEBUG

                  # break out of the while-loop, no more simulation neccessary
                  break

                elsif x >= @config.arenaWidth - @config.paddleWidth - @config.ballRadius - 1

                  # no collision, calculate direct line
                  x = @config.arenaWidth - @config.paddleWidth - @config.ballRadius - 1
                  y = @math.calculate_collision(x, y1, x1, y2, x2)

                  # add the travelled path to the distances
                  distance_to_player += Math.hypot( x-x1, y-y1 )
                  if ( deltaX > 0 )
                    distance_to_enemy += Math.hypot( x-x1, y-y1 )
                  end

                  # set the estimated enemy paddle location
                  @enemyPaddle.set_target(y)

                  # calculate current angle
                  @last_enemy_enter_angle = @math.calculate_line_angle( x1, y1, x, y )

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

                  x2 = x + deltaX
                  y2 = y - deltaY
                  x1 = x
                  y1 = y

                  # increment iteration count
                  iterator+=1

                  # continue simulation from start
                  next

                else

                  # add the travelled path to the distances
                  distance_to_player += Math.hypot( x-x1, y-y1 )
                  if ( deltaX > 0 )
                    distance_to_enemy += Math.hypot( x-x1, y-y1 )
                  end

                  # Set new start position to the collision point (using the same velocity)
                  x2 = x - deltaX
                  y2 = y + deltaY
                  x1 = x
                  y1 = y

                  # increment iteration count
                  iterator+=1

                end #/if

              end # /while   

              #@log.debug "Iterations = #{iterator}"

              if iterator == @max_iterations
                # ok, it was too much work, we should just go to middle
                @ownPaddle.set_target( @config.arenaHeight / 2 )
              end

            else

              # no previous ball location known so we do not
              # know ball velocity and can't simulate the
              # ball path at all.
              # So we can only set the paddle target location to
              # the center of the arena
              #@ownPaddle.set_target( @config.arenaHeight / 2 )

            end

            #@log.debug "Distance to player: #{distance_to_player}, opponent: #{distance_to_enemy}"
            #
            # Simulation code end
            #
            ###############################################


            if @local_time - @updatedLastTimestamp > @updateRate && @ownPaddle.target_y != nil #&& @ownPaddle.avg_target_y != nil

              @updatedLastTimestamp = @local_time

              min_slowdown = 0
              is_at_border = false
              @wanted_y = @ownPaddle.target_y #.avg_target_y
              if @wanted_y < @config.paddleHeight/2 + 1
                @wanted_y = @config.paddleHeight/2 + 1
                min_slowdown = 5
                is_at_border = true
              end
              if @wanted_y > @config.arenaHeight - @config.paddleHeight/2 - 2
                @wanted_y = @config.arenaHeight - @config.paddleHeight/2 - 2
                min_slowdown = 5
                is_at_border = true
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

              # Quickly move to the ball direction if the ball is
              # very close
              #if distance_to_player < 25 && @last_dirX < 0 && is_at_border == false
              #  #@log.debug "Trying to speedup at the end."
              #  speed = 1.0
              #  delta = -last_deltaY * @AI_level
              #end

              if delta < 0
                @log.write "> changeDir(#{speed}) -> target: #{@ownPaddle.target_y}, current: #{@ownPaddle.y}" if $DEBUG
                tcp.puts movement_message(speed)
              elsif delta > 0
                @log.write "> changeDir(#{-speed}) -> target: #{@ownPaddle.target_y}, current: #{@ownPaddle.y}" if $DEBUG
                tcp.puts movement_message(-speed)
              else
                @log.write "> changeDir(0) -> target: #{@ownPaddle.target_y}, current: #{@ownPaddle.y}" if $DEBUG
                tcp.puts movement_message(0)
              end

            end # /if

          when 'gameIsOver'
            winner = message['data']
            if winner == @player_name
              @win_count += 1
              @log.write "--WINNER--"
              @log.write "Opponent enter angle was #{@last_enemy_enter_angle}"
              @log.write "Opponent paddle was last at #{@enemyPaddle.y} [#{@enemyPaddle.y-@config.paddleHeight/2}..#{@enemyPaddle.y+@config.paddleHeight/2}]"
              @log.write "Opponent paddle was going to #{@enemyPaddle.target_y} [#{@enemyPaddle.target_y-@config.paddleHeight/2}..#{@enemyPaddle.target_y+@config.paddleHeight/2}]"
              @log.write "Ball last seen at #{@ball.x}, #{@ball.y} (velocity: #{@last_velocity})"
            else
              @lose_count += 1
              @log.write "--LOSER--"
              @log.write "Own enter angle was #{@last_enemy_enter_angle}"
              @log.write "Own paddle was last at #{@ownPaddle.y} [#{@ownPaddle.y-@config.paddleHeight/2}..#{@ownPaddle.y+@config.paddleHeight/2}]"
              @log.write "Own paddle was going to #{@ownPaddle.target_y} [#{@ownPaddle.target_y-@config.paddleHeight/2}..#{@ownPaddle.target_y+@config.paddleHeight/2}]"
              @log.write "Own paddle hit offset was at #{@hit_offset} with power of #{@hit_offset_power}"
              @log.write "Ball last seen at #{@ball.x}, #{@ball.y} (velocity: #{@last_velocity})"
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
            $stdout.flush
          else
            # unknown message received
            @log.write "< unknown_message: #{json}" if $DEBUG
        end
      end
    end

    def join_message(player_name)
      %Q!{"msgType":"join","data":"#{player_name}"}!
    end

    def duel_message(player_name, other_name)
      %Q!{"msgType":"requestDuel","data":["#{player_name}","#{other_name}"]}!
    end

    def movement_message(delta)
      %Q!{"msgType":"changeDir","data":#{delta}}!
    end

    def get_localtimestamp
      return (Time.now.to_f * 1000.0).to_i
    end

    def show_banner
      @log.write ""
      @log.write "    _______ __                      __       "
      @log.write "   |    ___|__|.-----.----.-----.--|  |.----."
      @log.write "   |    ___|  ||     |  __|  _  |  _  ||   _|"
      @log.write "   |___|   |__||__|__|____|_____|_____||__|  "
      @log.write ""
      @log.write "   H e l l o W o r l d O p e n   B o t  v0.9"
      @log.write ""
      @log.write "      Coded by Fincodr aka Mika Luoma-aho"
      @log.write "      Send job offers to <fincodr@mxl.fi>"
      @log.write ""
      $stdout.flush
    end

  end # /Client  

end # / module