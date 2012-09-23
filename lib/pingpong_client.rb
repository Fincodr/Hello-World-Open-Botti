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
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#
# Additionally you are subject to the following restrictions:
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
require 'launchy' if $DEBUG
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

      # testmode settings
      @test_offset_cur = -1.0
      @test_offset_add = 0.05
      @test_in_progress = false

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

      # testmode settings
      @test_mode = 0 # 0 = off, 1 = test different offset powers

      # AI settings
      @AI_level = 1.0 # 1.0 = hardest, 0.0 normal and -1.0 easiest (helps the opponent side)
      @block_count = 0 # how many times we have blocked thus far
      @last_bounce_state = 0 # 0 = no collision, collision 1st, collision 2nd
      @paddle_safe_margin = 2
      @paddle_slowdown_margin = 20
      @paddle_slowdown_power = 1.0
      @target_offset = 0 # check if paddle up/down sides are correct and adjust!
      @max_paddle_speed = 1.0
      @last_sent_changedir = -99.0
      @max_iterations = 15 # should be enough
      @last_enemy_enter_angle = 0
      @last_enter_angle = 0
      @last_exit_angle = 0
      @last_enter_point = 0
      @last_dirX = 0
      @last_deviation = 0
      @hit_offset = 0
      @hit_offset_max = 0 # will be set again in the update phase
      @last_velocity = nil
      @max_velocity = nil
      @hit_offset_power = 0
      @old_offset_power = 0
      @last_avg_velocity = nil
      @opponent_best_target = 0
      @last_target_y = 0
      @last_target_result = nil
      @last_target_results = nil
      @last_target_ymin = 0
      @last_target_ymax = 0
      @last_target_opponent_y = 0

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
      @show_json = true

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
        begin
          msgtype = message['msgType']
        rescue
          msgtype = 'unknown'
        end
        case msgtype

          when 'joined'
            @log.write "< joined: #{json}"
            $stdout.flush
            Launchy.open(message['data']) if $DEBUG

          when 'gameStarted'
            @log.write "< gameStarted: #{json}"
            $stdout.flush

          when 'gameIsOn'

            # update local time from clock
            @local_time = get_localtimestamp

            if $DEBUG
              @log.write "< gameIsOn: lag:#{@local_vs_server_drift} #{json}"
            else
              if @show_json
                @show_json = false
                @log.write "< gameIsOn: lag:#{@local_vs_server_drift} #{json}"
              end
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
              h = msg_conf['paddleHeight'] / 2 - @paddle_safe_margin
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

            if not $DEBUG
              if @test_mode == 0
                str = sprintf "L:%d B:%.2f %.2f P:%.2f,%.2f C:%d %d %d %d %d", @local_vs_server_drift, @ball.x, @ball.y, @ownPaddle.y, @enemyPaddle.y, @config.ballRadius, @config.paddleWidth, @config.paddleHeight, @config.arenaWidth, @config.arenaHeight
                #@local_vs_server_drift} Ball:#{Integer(@ball.x)},#{Integer(@ball.y)},#{@config.ballRadius} Paddles:#{Integer(@ownPaddle.y)},#{Integer(@enemyPaddle.y)},#{@config.paddleWidth},#{@config.paddleHeight} Arena:#{@config.arenaWidth},#{@config.arenaHeight}
                @log.write "< gameIsOn: #{str}"
              end
            end

            #----------------------------------------------
            #
            # =======================================
            # Simulate world forward to compensate for
            # current lag (?) no noticeable lag at competition?
            # =======================================
            #
            # TODO ?
            #
            #----------------------------------------------


            ###############################################
            #
            # Simulation code start
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

                # ============================================================
                # No collision detected, all three points are on the same line
                # ============================================================
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

                    # Check if P1 is not on the same line with P2 and P3
                    if not @math.is_p1_on_the_same_p2p3_line( @ball.x, @ball.y, @ball.x2, @ball.y2, @ball.x3, @ball.y3 )

                      # ============================================================
                      # COLLISION CASE #1: P1 is not on the same line as P2 and P3
                      # ============================================================
                      @last_bounce_state = 1

                      @log.write "Info: COLLISION CASE #1: P1 is not on the same line as P2 and P3" if @test_mode == 0
                      #@log.debug "COLLISION CASE #1: P1 is not on the same line as P2 and P3"
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
                        #if rand(2) == 0
                        #  @AI_level = -1.0
                        #else
                        #  @AI_level = 1.0
                        #end
                        #x = @config.paddleWidth + @config.ballRadius
                        #y = @math.calculate_collision(x, y2, x2, y3, x3)
                        @ball.x2 = x1 + deltaX
                        @ball.y2 = y1 - deltaY
                      elsif x >= @config.arenaWidth - @config.paddleWidth - @config.ballRadius - 1
                        # collision with right paddle
                        #x = @config.arenaWidth - @config.paddleWidth - @config.ballRadius - 1
                        #y = @math.calculate_collision(x, y2, x2, y3, x3)
                        @ball.x2 = x1 + deltaX
                      else
                        # collision with arena edges
                        @ball.x2 = x1 - deltaX
                        @ball.y2 = y1 + deltaY
                      end

                      @ball.x3 = nil
                      @ball.y3 = nil

                    else
                      @last_bounce_state = 0
                      @log.write "Info: COLLISION CASE #3: Unknown collision state, all points are at the same line!" if @test_mode == 0
                    end

                  when 1

                    # Check if P3 is not on the same line with P1 and P2
                    if not @math.is_p3_on_the_same_p1p2_line( @ball.x, @ball.y, @ball.x2, @ball.y2, @ball.x3, @ball.y3 )

                      # ==========================================================
                      # COLLISION CASE #2: P3 is not on the same line as P1 and P2
                      # ==========================================================
                      @last_bounce_state = 2

                      @log.write "Info: COLLISION CASE #2: P3 is not on the same line as P1 and P2" if @test_mode == 0
                      # the last known point is not on the new line
                      # so we can just use the current point and
                      # previous position for velocity and heading
                      # we will however clear the last point info
                      @ball.x3 = nil
                      @ball.y3 = nil

                    else
                      @last_bounce_state = 0
                      @log.write "Info: COLLISION CASE #3: Unknown collision state, all points are at the same line!" if @test_mode == 0
                    end

                end #/ case

              end #/ on_the_same_line

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
              last_deltaX = @ball.x-@ball.x2
              last_deltaY = @ball.y-@ball.y2
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
                #@log.debug "#{@last_velocity} + #{velocity} / 2 = #{@last_avg_velocity} (max = #{@max_velocity})"
              else
                @last_avg_velocity = nil
              end
              @last_velocity = velocity
            end

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

              # TODO: Enable if we should not try to slow down with higher ball speeds
              #       Note: This seems to be unneccessary.
              #
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
              #
              # ---- /TODO

              # scale hit_offset depending on the last velocity
              # note: starting velocity is usually about 0.250
              @hit_offset_power = 1.0 - ( Float(@max_velocity/2) - 0.350 )
              @hit_offset_power = 1.0 if @hit_offset_power > 1.0
              @hit_offset_power = 0.0 if @hit_offset_power < 0.0

              # TODO: Enable if ball has too big velocity and calculated
              #       location is not good enough for catching.
              #
              #
              # ---- /TODO

            end                

            if @hit_offset_power != @old_offset_power
              #@log.debug "Offset power now at #{@hit_offset_power} (max velocity #{@max_velocity}"
              @old_offset_power = @hit_offset_power
            end

            #@log.write "Info: Server time delta = #{@server_time_delta} (fixed rate = #{@fixed_server_rate}" if $DEBUG

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
            if not @ball.x2.nil? and not @ball.x3.nil? and @math.on_the_same_line( @ball.x, @ball.y, @ball.x2, @ball.y2, @ball.x3, @ball.y3 )

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

                    if @test_in_progress
                      @log.debug "TESTMODE1: Completed one pass (offset = #{@test_offset_cur}"
                      @test_in_progress = false
                      @test_offset_cur += @test_offset_add
                      if @test_offset_cur > 1.0
                        @test_offset_cur = 0.0
                      end
                    end
                    @block_count += 1
                    @last_exit_angle = @math.calculate_line_angle( @ball.x2, @ball.y2, @ball.x, @ball.y )
                    #@log.write "Info: Last enter angle was #{@last_enter_angle} and exit angle is now #{@last_exit_angle}" if $DEBUG
                    # check deviation from normal bounce angle
                    expected_exit_angle = 180 - @last_enter_angle
                    @last_deviation = @last_exit_angle - expected_exit_angle
                    if @last_enter_angle <= 90
                      #@log.write "Info: Deviation from <90 to normal exit angle = #{@last_deviation}" if $DEBUG
                    else
                      #@log.write "Info: Deviation from >90 to normal exit angle = #{@last_deviation}" if $DEBUG
                    end

                    # we have changed direction, if the paddle was stationary
                    # we should look at the last own enter and exit angles
                    # and also the last calculated collision point
                    if @math.is_close_to @ownPaddle.y, @ownPaddle.y2, 0.1
                      if (@last_enter_point-@ownPaddle.y2).abs < @config.paddleHeight/2
                        @log.debug "TEST RESULTS: #{(@last_enter_point-@ownPaddle.y2).abs}, #{@last_avg_velocity}, #{(@last_deviation).abs}" if $DEBUG and @test_mode == 1
                        @log.write "TEST_RESULTS: #{@last_enter_point-@ownPaddle.y2}, #{@last_avg_velocity}, #{@last_deviation}"
                        #@log.debug "=======================================================" if $DEBUG
                        #@log.debug "== Avg velocity   : #{@last_avg_velocity}" if $DEBUG
                        #@log.debug "== Paddle Y       : #{@ownPaddle.y2}" if $DEBUG
                        #@log.debug "== Ball Hit Y     : #{@last_enter_point}" if $DEBUG
                        #@log.debug "== Offset         : #{@last_enter_point-@ownPaddle.y2}" if $DEBUG
                        #@log.debug "== Enter angle    : #{@last_enter_angle}" if $DEBUG
                        #@log.debug "== Exit angle     : #{@last_exit_angle} (Expected: #{expected_exit_angle})" if $DEBUG
                        #@log.debug "== Angle modifier : #{@last_deviation}" if $DEBUG
                        #@log.debug "=======================================================" if $DEBUG
                      end
                    end

                  end
                end
                @last_dirX = dirX
              end

              # try to solve
              solve_results = @math.solve_collisions x1, y1, x2, y2, @config, @max_iterations
              iterations = 0
              distance_to_player = 0
              distance_to_enemy = 0
              p = solve_results.point

              if p.x >= @config.arenaWidth - @config.paddleWidth - @config.ballRadius - 1
                # hit at opponent paddle
                iterations += solve_results.iterations
                distance_to_enemy += solve_results.distance
                distance_to_player += solve_results.distance

                time_to_enemy = distance_to_enemy / @last_avg_velocity

                # set the estimated enemy paddle location
                # @enemyPaddle.set_target(p.y)
                if not @last_target_result.nil?
                  temp_result = @last_target_result[1]
                  @log.debug "---------------------------------------------" if $DEBUG
                  @log.debug "Enter Angle was : #{@last_enter_angle}" if $DEBUG
                  @log.debug "Exit Angle was  : #{180-@last_enter_angle} (calculated)" if $DEBUG
                  @log.debug "Exit Angle was  : #{@last_exit_angle} (actual)" if $DEBUG
                  @log.debug "Exit Angle was  : #{temp_result["angle"]} (wanted)" if $DEBUG
                  @log.debug "Exit Angle DIFF : #{@last_exit_angle-(180-@last_enter_angle)} (actual)" if $DEBUG
                  @log.debug "Exit Angle DIFF : #{@math.top_secret_formula temp_result["offset"]} (wanted)" if $DEBUG
                  @log.debug "Exit Angle ERROR: #{(@last_exit_angle-(180-@last_enter_angle))-(@math.top_secret_formula temp_result["offset"])}" if $DEBUG
                  @log.debug "Used Offset was : #{temp_result["offset"]}" if $DEBUG
                  @log.debug "Used Power was  : #{temp_result["power"]}" if $DEBUG
                  @log.debug "Opponent-y was  : #{@last_target_opponent_y}" if $DEBUG
                  @log.debug "Target          : @ #{@last_target_y} | Real: @ #{p.y} | Diff: #{@last_target_y-p.y}" if $DEBUG
                  @log.debug "Target min/max  : @ #{@last_target_ymin} | #{@last_target_ymax}" if $DEBUG
                  @last_target_results.each { |key, value| 
                    @log.debug "(#{key}) => I:#{value["iterations"]} A:#{value["angle"]} P:#{value["power"]} Y:#{value["target-y"]} O:#{value["own-y"]}" if $DEBUG
                  }
                  @log.write "TARGET_RESULTS: #{@last_avg_velocity}, #{temp_result["offset"]}, #{@last_exit_angle-(180-@last_enter_angle)}, #{@math.top_secret_formula temp_result["offset"]}, #{(@last_exit_angle-(180-@last_enter_angle))-(@math.top_secret_formula temp_result["offset"])}"
                  @last_target_result = nil
                end

                # calculate opponent location at the time of impact
                # we know how long we have before the ball is going to hit
                # at the opponent side
                estimated_enemy_y = @enemyPaddle.y - (@enemyPaddle.avg_dy * (time_to_enemy/100))
                enemy_offset = -(estimated_enemy_y-p.y)
                enemy_offset = -22 if enemy_offset < -22
                enemy_offset = 22 if enemy_offset > 22
                #@log.debug "Est: #{estimated_enemy_y} | Offset: #{enemy_offset} | Diff: #{estimated_enemy_y-@enemyPaddle.y} | "

                #if not @enemyPaddle.avg_dy.nil?
                #  @log.debug "Opponent paddle @ #{@enemyPaddle.y}, Velocity #{@enemyPaddle.avg_dy}"
                #end

                # calculate current angle
                @last_enemy_enter_angle = @math.calculate_line_angle( p.x+p.dx, p.y+p.dy, p.x, p.y )
                
                # bounce back and simulate again
                #x2 = p.x + p.dx
                #y2 = p.y - p.dy
                #x1 = p.x
                #y1 = p.y

                exit_vector = Helpers::Vector2.new p.x, p.y, p.dx, -p.dy
                exit_vector.rotate @math.top_secret_formula enemy_offset

                solve_results = @math.solve_collisions exit_vector.x, exit_vector.y, exit_vector.x+exit_vector.dx, exit_vector.y+exit_vector.dy, @config, @max_iterations
                p = solve_results.point
              end

              if p.x <= @config.paddleWidth + @config.ballRadius
                # hit at our paddle
                iterations += solve_results.iterations
                distance_to_player += solve_results.distance
                @last_enter_angle = @math.calculate_line_angle( p.x+p.dx, p.y+p.dy, p.x, p.y )
                @last_enter_point = p.y

                #@log.debug "< Enter angle = #{@last_enter_angle}"

                # scale hit_offset depending on the estimated enter angle
                # safe angles are -25 .. +25 and anything over that should decrement the power
                offset_cut_value = @math.angle_to_hit_offset_cut @last_enter_angle, 7

                # set the offset top and bottom max values
                @hit_offset_top = -@hit_offset_max
                @hit_offset_bottom = @hit_offset_max
                if offset_cut_value <= 0
                  # we need to cut the bottom
                  @hit_offset_bottom += offset_cut_value * (1.0+(1.0-@hit_offset_power))
                else
                  # we need to cut the top
                  @hit_offset_top += offset_cut_value * (1.0+(1.0-@hit_offset_power))
                end

                @hit_offset_top_powerlimit = (Float(@hit_offset_top) / Float(@hit_offset_max)) #* @hit_offset_power
                @hit_offset_bottom_powerlimit = (Float(@hit_offset_bottom) / Float(@hit_offset_max)) #* @hit_offset_power

                #@log.debug "Offset P: #{@hit_offset_top_powerlimit}, #{@hit_offset_bottom_powerlimit} [#{@hit_offset_top}, #{@hit_offset_bottom}] < #{@hit_offset_power}"

                #@hit_offset_power *= angle_hit_offset_power
                #@log.debug "#{angle_hit_offset_power} => #{@hit_offset_power}"

                temp_AI_level = @AI_level

                if @AI_level < 0.0

                  #
                  # TODO: Fix this to use the new top and bottom offset powerlimits!
                  #
                  # we are trying to help the opponent :)
                  if @last_enter_angle <= 90
                    if @last_enter_angle >= 90-15
                      @deviation_from_straight = ( 90 - @last_enter_angle ) / 15
                    else
                      @deviation_from_straight = 1.0
                    end
                    temp_AI_level *= -@deviation_from_straight
                  else
                    if @last_enter_angle < 90+15
                      @deviation_from_straight = ( @last_enter_angle - 90 ) / 15
                    else
                      @deviation_from_straight = 1.0
                    end
                    temp_AI_level *= @deviation_from_straight
                  end
                  @hit_offset = (@hit_offset_max * @hit_offset_power) * temp_AI_level

                  # use testmode?
                  if @test_mode == 1
                    if @last_enter_angle >= 90-0.5 and @last_enter_angle <= 90+0.5
                      if not @test_in_progress
                        @log.debug "TESTMODE1: Activated for next pass"
                        @test_in_progress = true
                      end
                      offset_temp_max = @config.paddleHeight/2
                      @hit_offset = offset_temp_max * @test_offset_cur
                    end
                  end

                else

                  #----------------------------------------------
                  #
                  # =======================================
                  # Calculate where we should aim next ball
                  # =======================================
                  #
                  # To calculate best target of opportunity we
                  # need to simulate different situations that
                  # could happend with different paddle place-
                  # ments.
                  #
                  #----------------------------------------------
                  if distance_to_player > 300
                    # allow "switch" sides only if our distance to ball is more than 300 pixels
                    if @enemyPaddle.y < @config.arenaHeight / 2
                      @opponent_best_target = @config.arenaHeight - 1
                      #@log.debug "DOWN"
                    else
                      @opponent_best_target = 0
                      #@log.debug "UP"
                    end
                  end

                  # lets first simulate where the opponent is going to try to be
                  exit_vector = Helpers::Vector2.new p.x, p.y, p.dx, p.dy
                  test_vector = exit_vector.dup
                  opponent_location = @math.solve_collisions test_vector.x, test_vector.y, test_vector.x+test_vector.dx, test_vector.y+test_vector.dy, @config, @max_iterations
                  p2 = opponent_location.point
                  if p2.x >= @config.arenaWidth - @config.paddleWidth - @config.ballRadius - 1
                    @enemyPaddle.set_target p2.y
                    #@log.debug "Enemy is going to #{@enemyPaddle.target_y}"
                  else
                    # can't simulate, maybe too much bounces right now
                    @enemyPaddle.set_target @opponent_best_target
                  end

                  #@log.debug "Opp-y = #{@enemyPaddle.y} | Best target = #{opponent_best_target}" if $DEBUG
                  #
                  # Now that we know the best target of opportunity location
                  # we should calculate what is the best way to get to there
                  # since we do not know the secret formula behind the
                  # paddle physics we need to guess it.
                  #
                  # We can however estimate how much we can affect to
                  # the ball velocity using the offsets and from estimations
                  # we can create model for calculating offsets depending
                  # on the wanted target positions
                  #
                  # TODO: Gather data when the paddle is stationary and gets hit
                  #       from different angles. We need to know the exit angles
                  #       or the angle differences from normal vectors.
                  #
                  # Lets simulate seven different positions and estimated velocities
                  # - 100%
                  # - 50%
                  # = 0%
                  # + 50%
                  # + 100%
                  #
                  @start_power = @hit_offset_top_powerlimit
                  @power_add = 0.05
                  @max_power = @hit_offset_bottom_powerlimit
                  @simulations = {}

                  cur_power = @start_power

                  @last_target_ymin = @config.arenaHeight+1
                  @last_target_ymax = -1

                  while cur_power <= @max_power+0.001

                    test_vector = exit_vector.dup
                    test_offset = ((@hit_offset_max * @hit_offset_power) * @AI_level) * cur_power
                    angle_change = @math.top_secret_formula test_offset
                    test_vector.rotate angle_change
                    final_angle = @math.calculate_line_angle test_vector.x+test_vector.dx, test_vector.y-test_vector.dy, test_vector.x, test_vector.y 

                    # try to solve
                    solve_results = @math.solve_collisions test_vector.x, test_vector.y, test_vector.x+test_vector.dx, test_vector.y-test_vector.dy, @config, @max_iterations
                    p2 = solve_results.point
                    distance_back = solve_results.distance
                    if p2.x >= @config.arenaWidth - @config.paddleWidth - @config.ballRadius - 1
                      # we got result
                      # bounce back to us
                      test_vector2 = Helpers::Vector2.new p2.x, p2.y, p2.x-p2.dx, p2.y+p2.dy
                      solve_results2 = @math.solve_collisions test_vector2.x, test_vector2.y, test_vector2.x+test_vector2.dx, test_vector2.y-test_vector2.dy, @config, @max_iterations
                      p3 = solve_results2.point
                      distance_back += solve_results2.distance

                      distance_to_paddle = (p3.y - @ownPaddle.y).abs
                      paddle_time_to_ball = distance_to_paddle # own paddle moves at maximum of 10 pixels per 10th of a second
                      ball_time_to_paddle = (distance_back / @last_avg_velocity) / 100.0

                      #if paddle_time_to_ball < ball_time_to_paddle
                        # we can make it, keep the result
                        #@log.debug "Simulated back to us at #{p3.y}, Btime: #{ball_time_to_paddle}, Pd: #{distance_to_paddle}, Ptime: #{paddle_time_to_ball}"

                        # calculate which result would be the best
                        # TODO: use the target_y and current y to figure out where we should aim...
                        result_score = (p2.y - @opponent_best_target).abs.to_i
                        result = {}
                        result["offset"] = test_offset
                        result["angle"] = final_angle
                        result["power"] = cur_power
                        result["target-y"] = p2.y
                        @last_target_ymin = p2.y if p2.y < @last_target_ymin
                        @last_target_ymax = p2.y if p2.y > @last_target_ymax
                        result["own-y"] = p3.y
                        result["iterations"] = solve_results.iterations
                        @simulations[result_score] = result
                      #end

                    end

                    cur_power += @power_add

                  end # /while

                  if not @simulations.empty?
                    # we got some result we can use
                    # sort the results by score
                    sorted_results = @simulations.sort { |a,b| a<=>b }
                    #@log.debug "-------------------------------"
                    #@log.debug "Simulation normal y = #{@enemyPaddle.target_y}"
                    #@simulations.each { |key, value| 
                    #  @log.debug "(#{key}) => I:#{value["iterations"]} A:#{value["angle"]} P:#{value["power"]} Y:#{value["target-y"]} O:#{value["own-y"]}"
                    #}
                    # get the first result
                    best_result = sorted_results.first

                    # if the enter angle is too low we will try to change the angle 
                    #if @math.is_close_to(@last_enter_angle,90,2)
                    #  # get the ball moving
                    #  @log.debug "Note: Trying to get the ball moving at y-axis"
                    #  if @last_enter_angle < 90
                    #    used_power = @hit_offset_bottom_powerlimit
                    #  else
                    #    user_power = @hit_offset_top_powerlimit
                    #  end
                    #else
                      # normal AI activated
                      used_power = best_result[1]["power"]
                    #end

                    @hit_offset = ((@hit_offset_max * @hit_offset_power) * @AI_level) * used_power
                    if ( dirX < 0 )
                      @last_target_y = best_result[1]["target-y"]
                      @last_target_result = best_result.dup
                      @last_target_results = @simulations.dup
                      @last_target_opponent_y = @enemyPaddle.y
                    end
                  else
                    # we do not have any simulation results to use
                    # so we should just try to hit at center
                    @hit_offset = 0
                  end

                  #@log.debug "Hit offset >> #{@hit_offset} << #{cur_power} "
                  #@log.debug "Simulating from #{@start_power} to #{@max_power}, used power #{used_power}"

                  #@log.debug "Best score: #{best_result}"


                  # TODO: Test how it behaves with offset 0

                  #@log.debug "Our > #{best_result[1]['y']} - #{best_result[1]["power"]}"

                  # if we are at the start of the round we are just going to
                  # try to speed up the ball
                  #if @block_count < 2
                  #  # AI v0.9 - Not accurate but getting there..
                  #  if p.dy < 0
                  #    # Ball is going up
                  #    #if opponent_best_target < @config.arenaHeight/2
                  #      # We should aim up
                  #      @hit_offset = (@hit_offset_max * @hit_offset_top_powerlimit) * -@AI_level
                  #    #else
                  #    #  # We should aim down
                  #    #  @hit_offset = (@hit_offset_max * @hit_offset_power) * -@AI_level
                  #    #end
                  #  else                    
                  #    # Ball is going down
                  #    #if opponent_best_target < @config.arenaHeight/2
                  #    #  # We should aim up
                  #    #  @hit_offset = (@hit_offset_max * @hit_offset_power) * @AI_level
                  #    #else
                  #      # We should aim down
                  #      @hit_offset = (@hit_offset_max * @hit_offset_bottom_powerlimit) * @AI_level
                  #    #end
                  #  end
                  #end

                end

                @ownPaddle.set_target(p.y - @hit_offset)                

              else
                # ok, it was too much work, we should just go to middle and wait
                iterations += solve_results.iterations
                @ownPaddle.set_target( @config.arenaHeight / 2 )
                @log.debug "Bounces #{iterations} over max!" 
                #Distance to Player: #{distance_to_player}, Opp: #{distance_to_enemy}"
              end

            end
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
            else
              @lose_count += 1
            end
            @log.write "< gameIsOver: Winner is #{winner} | Win:#{@win_count} Lose:#{@lose_count} Total:#{@total_rounds}"
            @log.debug "gameIsOver: Winner is #{winner} | Win:#{@win_count} Lose:#{@lose_count} Total:#{@total_rounds}" if $DEBUG
            if winner == @player_name
              @log.write "Info: --WINNER--"
              @log.write "Info: Opponent enter angle was #{@last_enemy_enter_angle}"
              @log.write "Info: Opponent paddle was last at #{@enemyPaddle.y} [#{@enemyPaddle.y-@config.paddleHeight/2}..#{@enemyPaddle.y+@config.paddleHeight/2}]"
              @log.write "Info: Opponent paddle was going to #{@enemyPaddle.target_y} [#{@enemyPaddle.target_y-@config.paddleHeight/2}..#{@enemyPaddle.target_y+@config.paddleHeight/2}]"
              @log.write "Info: Ball last seen at #{@ball.x}, #{@ball.y} (velocity: #{@last_velocity})"
            else
              @log.write "Info: --LOSER--"
              @log.write "Info: Own enter angle was #{@last_enemy_enter_angle}"
              @log.write "Info: Own paddle was last at #{@ownPaddle.y} [#{@ownPaddle.y-@config.paddleHeight/2}..#{@ownPaddle.y+@config.paddleHeight/2}]"
              @log.write "Info: Own paddle was going to #{@ownPaddle.target_y} [#{@ownPaddle.target_y-@config.paddleHeight/2}..#{@ownPaddle.target_y+@config.paddleHeight/2}]"
              @log.write "Info: Own paddle hit offset was at #{@hit_offset} with power of #{@hit_offset_power}"
              @log.write "Info: Ball last seen at #{@ball.x}, #{@ball.y} (velocity: #{@last_velocity})"
            end
            if @scores.has_key?(winner)
              @scores[winner]+=1 # increment score for specified playername
            else
              @scores[winner]=1
            end
            @scores.each {|key, value| @log.write "Info: Score: #{key}: #{value}" }
            reset_round
            $stdout.flush
          else
            # unknown message received
            @log.write "< unknown_message: #{json}"
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
      @log.write "   H e l l o W o r l d O p e n   B o t  v1.0"
      @log.write ""
      @log.write "      Coded by Fincodr aka Mika Luoma-aho"
      @log.write "      Send job offers to <fincodr@mxl.fi>"
      @log.write ""
      $stdout.flush
    end

  end # /Client  

end # / module