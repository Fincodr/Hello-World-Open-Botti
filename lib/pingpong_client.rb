require 'socket'
require 'json'
require 'fileutils'
# added libraries
require 'time'
require 'date'
require 'launchy'
require_relative 'helpers'

module Pingpong

  class Client

    def initialize(player_name, server_host, server_port)

      @log = Helpers::Log.new

      # banner
      @log.write ""
      @log.write " _______ __                      __       "
      @log.write "|    ___|__|.-----.----.-----.--|  |.----."
      @log.write "|    ___|  ||     |  __|  _  |  _  ||   _|"
      @log.write "|___|   |__||__|__|____|_____|_____||__|  "
      @log.write ""
      @log.write "   H e l l o W o r l d O p e n   B o t"
      @log.write "   Coded by Fincodr aka Mika Luoma-aho"
      @log.write "   Send job offers to <fincodr@mxl.fi>"
      @log.write ""

      # log initialize parameters
      @log.write "initialize(#{player_name}, #{server_host}, #{server_port})"
      
      # Initialize global classes
      @ownPaddle = Helpers::Paddle.new
      @enemyPaddle = Helpers::Paddle.new
      @ball = Helpers::Ball.new
      @math = Helpers::Math.new

      reset_round

      # open socket to server
      tcp = TCPSocket.open(server_host, server_port)
      play(player_name, tcp)
    end

    private

    def reset_round
      # Set starting values
      @server_time = 0
      @server_time_elapsed = 0
      @server_time_delta = 0
      @local_time = get_localtimestamp
      @local_time_elapsed = 0
      @local_time_delta = 0

      # last updated timestamps
      @updatedLastTimestamp = 0
      @updatedDeltaTime = 0
      @updateRate = 1000/9.5 # limit send rate to ~9.5 msg/s

      # AI settings
      @last_sent_changedir = -99.0
      @max_iterations = 10
      @last_enter_angle = 0
      @last_exit_angle = 0
      @last_dirX = 0
      @last_deviation = 0
      @hit_offset = 0
      @hit_offset_max = 25
      @last_velocity = 0
      @max_velocity = 0

      # default configuration
      # will be updated from the gameIsOn server message
      @config = Helpers::Configuration.new()
      @config.set_arena( 640, 480 )
      @config.set_paddle( 10, 50 )
      @config.set_ball( 5 )

      # set class to default values
      @ball.set_position( 640/2, 480/2 )
      @ownPaddle.set_y( 480/2 )
      @enemyPaddle.set_y( 480/2 )

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
            else
              @log.write "< gameIsOn: event fired"
            end
            msg = message['data']

            if @server_time != 0
              @server_time_delta = Integer(msg['time']) - @server_time
              @server_time_elapsed += @server_time_delta
            end

            @server_time = Integer(msg['time'])

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
              h = msg_conf['paddleHeight'] / 2 - (@config.ballRadius)
              if ( h < 5 )
                h = 0
              end
              @hit_offset_max = h
            rescue
              @log.write "Warning: Configuration block missing from json packet"
            end

            # update player information from json packet
            begin
              msg_own = msg['left']
              msg_enemy = msg['right']
              @ownPaddle.set_position( 0, Float(msg_own['y']) )
              @enemyPaddle.set_position( @config.arenaWidth, Float(msg_enemy['y']) )
            rescue
              @log.write "Warning: Player block missing from json packet"
            end

            ###############################################
            #
            # Simulation code start
            #
            # If all points are on the same line, we can calculate ball trajectory
            #
            if @math.on_the_same_line( @ball.x, @ball.y, @ball.x2, @ball.y2, @ball.x3, @ball.y3 )

              # set the start position
              x3 = @ball.x2
              y3 = @ball.y2
              x2 = @ball.x
              y2 = @ball.y
              @last_velocity = Math.hypot( x2-x3,y2-y3 ) / @server_time_delta
              if @last_velocity > @max_velocity
                #@log.debug "Max Velocity now #{@last_velocity}\tElapsed time = #{@server_time_elapsed}"
                @max_velocity = @last_velocity
              end

              # scale hit_offset depending on the max velocity
              # note: starting velocity is usually about 0.250
              @hit_offset_power = 1.0 - (@max_velocity-0.250)
              @hit_offset_power = 1.0 if @hit_offset_power > 1.0
              @hit_offset_power = 0.0 if @hit_offset_power < 0.0

              @log.write "Info: Server time delta = #{@server_time_delta}" if $DEBUG
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
                  @log.write "Info: Direction changed, now going towards enemy" if $DEBUG
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
                    # calculate current angle
                    @last_enter_angle = @math.calculate_line_angle( x1, y1, x2, y2 )
                    if @last_enter_angle <= 90
                      @hit_offset = -(@hit_offset_max * @hit_offset_power)
                    else
                      @hit_offset = (@hit_offset_max * @hit_offset_power)
                    end
                    @ownPaddle.set_target(y1 + @hit_offset)
                    @log.write "Info: Own enter angle = #{@last_enter_angle}" if $DEBUG
                    break
                  end

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

                #if @ball.x > @config.arenaWidth/6

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
                      @ownPaddle.set_target(y1)
                      # calculate current angle
                      @last_enter_angle = @math.calculate_line_angle( x1, y1, x2, y2 )
                      @log.write "Info: Own enter angle = #{@last_enter_angle}" if $DEBUG
                      break
                    end

                    if x1 > @config.arenaWidth - @config.paddleWidth - @config.ballRadius
                      # no collision, calculate direct line
                      x1 = @config.arenaWidth - @config.paddleWidth - @config.ballRadius
                      y1 = @math.calculate_collision(x1, y2, x2, y3, x3)
                      # calculate current angle
                      @last_enter_angle = @math.calculate_line_angle( x2, y2, x1, y1 )
                      @log.write "Info: Enemy enter angle = #{@last_enter_angle}" if $DEBUG
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

                    # Set new start position to the collision point (using the same velocity)
                    x2 = x1
                    y2 = y1
                    x3 = x2 - deltaX
                    y3 = y2 + deltaY

                    # increment iteration count
                    iterator+=1

                  end # /while   
                                 
                #end

                if iterator == @max_iterations*2
                  # ok, too much work, we can just go to middle
                  @ownPaddle.set_target( @config.arenaHeight / 2 )
                end

              end # /if

            end # /if on_the_same_line 
            #
            # Simulation code end
            #
            ###############################################

            if @local_time - @updatedLastTimestamp > @updateRate              

              @updatedLastTimestamp = @local_time

              # send update to server about the direction we should be going
              if ( @ownPaddle.target_y < @config.paddleHeight/2 )
                @ownPaddle.set_target( @config.paddleHeight / 2 )
              end if

              if ( @ownPaddle.target_y > @config.arenaHeight - @config.paddleHeight/2 - 1 )
                @ownPaddle.set_target( @config.arenaHeight - @config.paddleHeight/2 - 1 )
              end if

              delta = (@ownPaddle.y + (@config.paddleHeight / 2) - (@ownPaddle.target_y - @config.ballRadius/4)).abs

              speed = 1.0

              if ( delta < 10 )
                speed = delta/10
              end

              #if ( delta < 10 )
              #  speed = 0
              #end

              #if @last_dirX < 0 && @ball.x < @config.paddleWidth + 25
              #    tcp.puts movement_message(-1.0)
              #else
                if (@ownPaddle.y + (@config.paddleHeight / 2)) < (@ownPaddle.target_y - @config.ballRadius/4)
                  if @last_sent_changedir != speed
                    @log.write "> changeDir(#{speed})" if $DEBUG
                    @last_sent_changedir = speed
                    tcp.puts movement_message(speed)
                  end
                else
                  if @last_sent_changedir != -speed
                    @log.write "> changeDir(#{-speed})" if $DEBUG
                    @last_sent_changedir = -speed
                    tcp.puts movement_message(-speed)
                  end
                end
              #end             

            end # /if

          when 'gameIsOver'
            @log.write "< gameIsOver: Winner is #{message['data']}"
            @log.debug "gameIsOver: Winner is #{message['data']}" if $DEBUG
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