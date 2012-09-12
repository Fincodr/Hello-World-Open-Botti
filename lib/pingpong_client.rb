require 'socket'
require 'rubygems'
require 'json'
require 'fileutils'
# added libraries
require 'time'
require 'date'
require 'launchy'

module Pingpong

  class Client

    def initialize(player_name, server_host, server_port, debug_flags = nil)

      # banner
      log_message ""
      log_message " _______ __                      __       "
      log_message "|    ___|__|.-----.----.-----.--|  |.----."
      log_message "|    ___|  ||     |  __|  _  |  _  ||   _|"
      log_message "|___|   |__||__|__|____|_____|_____||__|  "
      log_message ""
      log_message "   H e l l o W o r l d O p e n   B o t"
      log_message "   Coded by Fincodr aka Mika Luoma-aho"
      log_message "   Send job offers to <fincodr@mxl.fi>"
      log_message ""

      # log initialize parameters
      log_message "initialize(#{player_name}, #{server_host}, #{server_port})"
      
      ###############################################
      #
      # Initialize global classes
      #                                    
      @ownPaddle = Paddle.new()
      @enemyPaddle = Paddle.new()
      @ball = Ball.new()

      ###############################################
      # Set starting values
      #
      @server_time = 0
      @server_time_elapsed = 0
      @server_time_delta = 0
      @local_time = get_localtimestamp
      @local_time_elapsed = 0
      @local_time_delta = 0

      ###############################################
      # last updated timestamps
      #
      @updatedLastTimestamp = 0
      @updatedDeltaTime = 0
      @updateRate = 100 # limit send rate to 10 msg/s

      ###############################################
      # AI settings
      #
      @maxIterations = 10

      ###############################################
      #
      # default configuration
      # will be updated from the gameIsOn server message
      #
      @config = Configuration.new()
      @config.set_arena( 640, 480 )
      @config.set_paddle( 10, 50 )
      @config.set_ball( 5 )

      ###############################################
      #
      # open socket to server
      #
      tcp = TCPSocket.open(server_host, server_port)
      play(player_name, tcp)
    end

    private

    def calculate_collision(y1, x2, y2, x3, y3)
      x1 = x3 - ((x2 - x3) / (y2 - y3)) * (y3 - y1)
      return x1
    end

    def on_the_same_line(x1, y1, x2, y2, x3, y3)
      begin
        return true if y1 == y2 && y2 == y3
        return true if x1 == x2 && x2 == x3
        amount = ((x3-x1) - ((x2 - x3) / (y2 - y3)) * (y3 - y1)).abs
        if amount < 2.0
          return true
        else
          return false
        end
      rescue
        # division by zero
        return false
      end
    end

    def play(player_name, tcp)
      log_message "> join(#{player_name})"
      tcp.puts join_message(player_name)
      react_to_messages_from_server tcp
    end

    def react_to_messages_from_server(tcp)
      while json = tcp.gets
        message = JSON.parse(json)
        case message['msgType']

          when 'joined'
            log_message "< joined: #{json}"
            Launchy.open(message['data'])

          when 'gameStarted'
            log_message "< gameStarted: #{json}"

          when 'gameIsOn'
            # update local time from clock
            @local_time = get_localtimestamp

            log_message "< gameIsOn: #{json}"
            msg = message['data']

            if @server_time != 0
              @server_time_delta = Integer(msg['time']) - @server_time
              @server_time_elapsed += @server_time_delta
            end

            @server_time = Integer(msg['time'])

            ###############################################
            #
            # update ball information from json packet
            #
            begin
              msg_ball = msg['ball']
              @ball.set_position( Float(msg_ball['pos']['x']), Float(msg_ball['pos']['y']) )
            rescue
              log_message "Warning: Ball block missing from json packet"
              # we don't know where the ball is, stop simulating
            end

            ###############################################
            #
            # update configuration information from json packet
            #
            begin
              msg_conf = msg['conf']
              @config.set_arena( msg_conf['maxWidth'], msg_conf['maxHeight'] )
              @config.set_paddle( msg_conf['paddleWidth'], msg_conf['paddleHeight'] )
              @config.set_ball( msg_conf['ballRadius'] )
            rescue
              log_message "Warning: Configuration block missing from json packet"
            end

            ###############################################
            #
            # update player information from json packet
            #
            begin
              msg_own = msg['left']
              msg_enemy = msg['right']
              @ownPaddle.set_position( 0, Float(msg_own['y']) )
              @enemyPaddle.set_position( @config.arenaWidth, Float(msg_enemy['y']) )
            rescue
              log_message "Warning: Player block missing from json packet"
            end

            ###############################################
            #
            # Simulation code
            #
            x3 = @ball.x2
            y3 = @ball.y2
            x2 = @ball.x
            y2 = @ball.y
            x1 = 0.0
            y1 = 0.0
            deltaX = x2-x3

            # if all points are on the same line, we can calculate ball trajectory
            if on_the_same_line( @ball.x, @ball.y, @ball.x2, @ball.y2, @ball.x3, @ball.y3 )

              if ( deltaX < 0 )

                # ball is coming towards us
                iterator = 0

                while iterator < @maxIterations

                  deltaX = x2-x3
                  deltaY = y2-y3

                  if deltaY < 0
                    y1 = @config.ballRadius
                  else
                    y1 = @config.arenaHeight - @config.ballRadius - 1
                  end

                  x1 = calculate_collision(y1, x2, y2, x3, y3)

                  if x1 < @config.paddleWidth + @config.ballRadius
                    # no collision, calculate direct line
                    x1 = @config.paddleWidth + @config.ballRadius
                    y1 = calculate_collision(x1, y2, x2, y3, x3)
                    @ownPaddle.set_target(y1)
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

                while iterator < @maxIterations*2

                  deltaX = x2-x3
                  deltaY = y2-y3

                  if deltaY < 0
                    y1 = @config.ballRadius
                  else
                    y1 = @config.arenaHeight - @config.ballRadius - 1
                  end

                  x1 = calculate_collision(y1, x2, y2, x3, y3)

                  if x1 < @config.paddleWidth + @config.ballRadius
                    # no collision, calculate direct line
                    x1 = @config.paddleWidth + @config.ballRadius
                    y1 = calculate_collision(x1, y2, x2, y3, x3)
                    @ownPaddle.set_target(y1)
                    break
                  end

                  if x1 > @config.arenaWidth - @config.paddleWidth - @config.ballRadius
                    # no collision, calculate direct line
                    x1 = @config.arenaWidth - @config.paddleWidth - @config.ballRadius
                    y1 = calculate_collision(x1, y2, x2, y3, x3)
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

                if iterator == @maxIterations*2
                  # ok, too much work, we can just go to middle
                  @ownPaddle.set_target( @config.arenaHeight / 2 )
                end

              end # /if

            end # /if on_the_same_line 

            if @local_time - @updatedLastTimestamp > @updateRate              

              @updatedLastTimestamp = @local_time

              # send update to server about the direction we should be going
              if ( @ownPaddle.target_y < @config.paddleHeight/2 )
                @ownPaddle.set_target( @config.paddleHeight / 2 )
              end if

              if ( @ownPaddle.target_y > @config.arenaHeight - @config.paddleHeight/2 - 1 )
                @ownPaddle.set_target( @config.arenaHeight - @config.paddleHeight/2 - 1 )
              end if

              delta = (@ownPaddle.y + (@config.paddleHeight / 2) - @ownPaddle.target_y).abs

              speed = 1.0

              if ( delta < 30 )
                speed = delta/30
              end

              if ( delta < 10 )
                speed = 0
              end

              if (@ownPaddle.y + (@config.paddleHeight / 2)) < @ownPaddle.target_y
                log_message "> changeDir(#{speed})"
                tcp.puts movement_message(speed)
              else
                log_message "> changeDir(#{-speed})"
                tcp.puts movement_message(-speed)
              end

            end # /if

          when 'gameIsOver'
            log_message "< gameIsOver: Winner is #{message['data']}"

          else
            # unknown message received
            log_message "< unknown_message: #{json}"
        end
      end
    end

    def join_message(player_name)
      %Q!{"msgType":"join","data":"#{player_name}"}!
    end

    def movement_message(delta)
      %Q!{"msgType":"changeDir","data":#{delta}}!
    end

    ###############################################
    # Function: log_message
    #
    # logs a message to the standard output with
    # timestamp information.
    #
    # returns:
    # - nothing
    def log_message(msg)
      timestamp = DateTime.now.strftime "[%Y%m%d-%H%M%S.%L]"
      puts "#{timestamp} #{msg}"
    end
    
    ###############################################
    # Function: predict_ball_position
    #
    # predicts ball trajectory from the start position
    # to either end of the arena
    # returns:
    # nil - if no end position can be predicted at this time
    # Point (class) - x and y position of the predicted location
    #
    def predict_ball_position(xPrev, yPrev, x, y)
    end

    def get_localtimestamp
      return (Time.now.to_f * 1000.0).to_i
    end

  end # /Client  

  class Configuration
    def initialize
      @arenaWidth = nil
      @arenaHeight = nil   
      @paddleWidth = nil
      @paddleHeight = nil
      @ballRadius = nil
    end
    def set_arena( w, h )
      @arenaWidth = w
      @arenaHeight = h
    end
    def set_paddle( w, h )
      @paddleWidth = w
      @paddleHeight = h
    end
    def set_ball( r )
      @ballRadius = r
    end
    attr_reader :arenaWidth
    attr_reader :arenaHeight
    attr_reader :paddleWidth
    attr_reader :paddleHeight
    attr_reader :ballRadius
  end # /Configuration

  ###############################################
  #
  # Class: Ball
  #
  # everything about the Ball
  #
  # methods:
  # - simulate
  # - is_on_the_same_line
  #
  class Ball
    def initialize
      @x = 0
      @y = 0
      @x2 = 0
      @y2 = 0
      @x3 = 0
      @y3 = 0
    end
    def set_position(x, y)
      @x3 = @x2
      @y3 = @y2
      @x2 = @x
      @y2 = @y
      @x = x
      @y = y
    end
    attr_reader :x
    attr_reader :y
    attr_reader :x2
    attr_reader :y2
    attr_reader :x3
    attr_reader :y3
  end # /Ball

  class Paddle
    def initialize
      @x = 0
      @y = 0
      @target_y = 0
    end
    def set_y( y )
      @y = y
    end
    def set_position( x, y )
      @x = x
      @y = y
    end
    def set_target( y )
      @target_y = y
    end
    attr_reader :x
    attr_reader :y
    attr_reader :target_y
  end # /class

end # / module

player_name = ARGV[0]
server_host = ARGV[1]
server_port = ARGV[2]
debug_flag = ARGV[3]
client = Pingpong::Client.new(player_name, server_host, server_port, debug_flag)
