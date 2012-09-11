require 'socket'
require 'rubygems'
require 'json'
require 'fileutils'
require 'launchy'

module Pingpong

  class Client
    def initialize(player_name, server_host, server_port)

      puts ""
      puts " _______ __                      __       "
      puts "|    ___|__|.-----.----.-----.--|  |.----."
      puts "|    ___|  ||     |  __|  _  |  _  ||   _|"
      puts "|___|   |__||__|__|____|_____|_____||__|  "
      puts ""
      puts "       H e l l o W o r l d O p e n"
      puts "   Coded by Fincodr aka Mika Luoma-aho"
      puts ""

      puts "initialize( #{player_name}, #{server_host}, #{server_port} )"
                                          
      ###############################################
      # Create Ball and Paddle structs
      #
      Struct.new("Ball", :x, :y, :x2, :y2, :x3, :y3)
      @ball = Struct::Ball.new(0, 0, 0, 0, 0, 0)
      Struct.new("Paddle", :x, :y, :w, :h, :target_y)
      @ownPaddle = Struct::Paddle.new(0, 0, 10, 50, 0)
      @enemyPaddle = Struct::Paddle.new(0, 0, 10, 50, 0)
      ###############################################
      # Set starting values
      #
      @time = 0
      @time_elapsed = 0
      @time_delta = 0

      ###############################################
      # last updated timestamps
      #
      @updatedLastTimestamp = 0
      @updatedDeltaTime = 0
      @updateRate = 100

      @maxIterations = 10

      ###############################################
      # open socket to server
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
      tcp.puts join_message(player_name)
      react_to_messages_from_server tcp
    end

    def react_to_messages_from_server(tcp)
      while json = tcp.gets
        message = JSON.parse(json)
        case message['msgType']

          when 'joined'
            puts "joined: #{json}"
            Launchy.open(message['data'])

          when 'gameStarted'
            puts "gameStarted: #{json}"

          when 'gameIsOn'
            puts "gameIsOn: #{json}"
            msg = message['data']
            if @time != 0
              @time_delta = Integer(msg['time']) - @time
              @time_elapsed += @time_delta
            end
            @time = Integer(msg['time'])

            msg_own = msg['left']
            msg_enemy = msg['right']
            msg_ball = msg['ball']
            msg_conf = msg['conf']

            @ball[:x3] = @ball[:x2]
            @ball[:y3] = @ball[:y2]
            @ball[:x2] = @ball[:x]
            @ball[:y2] = @ball[:y]
            @ball[:x] = Float(msg_ball['pos']['x'])
            @ball[:y] = Float(msg_ball['pos']['y'])

            @ownPaddle[:y] = Float(msg_own['y'])
            @ownPaddle[:w] = Integer(msg_conf['paddleWidth'])
            @ownPaddle[:h] = Integer(msg_conf['paddleHeight'])
            @enemyPaddle[:y] = Float(msg_enemy['y'])

            # start from current ball position
            x3 = @ball[:x2]
            y3 = @ball[:y2]
            x2 = @ball[:x]
            y2 = @ball[:y]
            x1 = 0.0
            y1 = 0.0

            deltaX = x2-x3

            # if all points are on the same line, we can calculate ball trajectory
            if on_the_same_line(@ball[:x], @ball[:y], @ball[:x2], @ball[:y2], @ball[:x3], @ball[:y3])

              if ( deltaX < 0 )

                # ball is coming towards us
                iterator = 0

                while iterator < @maxIterations

                  deltaX = x2-x3
                  deltaY = y2-y3

                  if deltaY < 0
                    y1 = msg_conf['ballRadius']
                  else
                    y1 = msg_conf['maxHeight'] - msg_conf['ballRadius'] - 1
                  end

                  x1 = calculate_collision(y1, x2, y2, x3, y3)

                  if x1 < @ownPaddle[:w] + msg_conf['ballRadius']
                    # no collision, calculate direct line
                    x1 = @ownPaddle[:w] + msg_conf['ballRadius']
                    y1 = calculate_collision(x1, y2, x2, y3, x3)
                    @ownPaddle[:target_y] = y1
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
                    y1 = msg_conf['ballRadius']
                  else
                    y1 = msg_conf['maxHeight'] - msg_conf['ballRadius'] - 1
                  end

                  x1 = calculate_collision(y1, x2, y2, x3, y3)

                  if x1 < @ownPaddle[:w] + msg_conf['ballRadius']
                    # no collision, calculate direct line
                    x1 = @ownPaddle[:w] + msg_conf['ballRadius']
                    y1 = calculate_collision(x1, y2, x2, y3, x3)
                    @ownPaddle[:target_y] = y1
                    break
                  end

                  if x1 > msg_conf['maxWidth'] - @ownPaddle[:w] - msg_conf['ballRadius']
                    # no collision, calculate direct line
                    x1 = msg_conf['maxWidth'] - @ownPaddle[:w] - msg_conf['ballRadius']
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
                  @ownPaddle[:target_y] = msg_conf['maxHeight'] / 2
                end

              end

            end

            if @time - @updatedLastTimestamp > @updateRate              

              @updatedLastTimestamp = @time

              # send update to server about the direction we should be going
              puts "== SENDING UPDATE TO SERVER =="

              if ( @ownPaddle[:target_y] < @ownPaddle[:h]/2 )
                @ownPaddle[:target_y] = @ownPaddle[:h] / 2
              end if

              if ( @ownPaddle[:target_y] > msg_conf['maxHeight'] - @ownPaddle[:h]/2 - 1 )
                @ownPaddle[:target_y] = msg_conf['maxHeight'] - @ownPaddle[:h]/2 - 1
              end if

              delta = (@ownPaddle[:y] + (@ownPaddle[:h] / 2) - @ownPaddle[:target_y]).abs

              speed = 1.0

              if ( delta < 30 )
                speed = delta/30
              end

              if ( delta < 10 )
                speed = 0
              end

              if (@ownPaddle[:y] + (@ownPaddle[:h] / 2)) < @ownPaddle[:target_y]

                tcp.puts movement_message(speed)

              else

                tcp.puts movement_message(-speed)

              end

            end

          when 'gameIsOver'
            puts "gameIsOver: Winner is #{message['data']}"

          else
            # unknown message received
            puts "unknown_message: #{json}"
        end
      end
    end

    def join_message(player_name)
      %Q!{"msgType":"join","data":"#{player_name}"}!
    end

    def movement_message(delta)
      %Q!{"msgType":"changeDir","data":#{delta}}!
    end
  end
end

player_name = ARGV[0]
server_host = ARGV[1]
server_port = ARGV[2]
client = Pingpong::Client.new(player_name, server_host, server_port)
