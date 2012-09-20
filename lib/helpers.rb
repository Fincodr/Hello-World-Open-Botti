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
# 4. Contact author if you need special license terms.
#
module Helpers

  class Log

    ###############################################
    #
    # Function: log_message
    #
    # logs a message to the standard output with
    # timestamp information.
    #
    # returns:
    # - nothing
    def write(msg)
      timestamp = DateTime.now.strftime "[%Y%m%d-%H%M%S.%L]"
      puts "#{timestamp} #{msg}"
    end

    def debug(msg)
      timestamp = DateTime.now.strftime "[%Y%m%d-%H%M%S.%L]"
      $stderr.puts "#{timestamp} #{msg}"
    end

  end

  class SolveResult
    def initialize x, y, dx, dy, distance, iterations
      @distance = distance
      @iterations = iterations
      @point = Vector2.new x, y, dx, dy
    end
    attr_accessor :distance
    attr_accessor :iterations
    attr_accessor :point
  end

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

  class Vector2
    def initialize x, y, dx, dy
      @x = x
      @y = y
      @dx = dx
      @dy = dy
    end
    def set_position x, y
      @x = x
      @y = y
    end
    def set_velocity dx, dy
      @dx = x
      @dy = y
    end
    def scale sz
      @dx *= sz
      @dy *= sz
    end
    def normalize
      power = Math.hypot( dx, dy )
      @dx *= power
      @dy *= power
    end
    attr_accessor :x
    attr_accessor :y
    attr_accessor :dx
    attr_accessor :dy
  end # /Vector2

  class Point
    def initialize x, y
      @x = x
      @y = y
    end
    def set_position x, y
      @x = x
      @y = y
    end
    def reset
      @x = nil
      @y = nil
    end
    attr_reader :x
    attr_reader :y
  end # /Point

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
      reset
    end
    def reset
      @x = nil
      @y = nil
      @x2 = nil
      @y2 = nil
      @x3 = nil
      @y3 = nil
    end
    def set_position(x, y)
      if @x2.nil?
        @x3 = nil
        @y3 = nil
      else
        @x3 = @x2
        @y3 = @y2
      end
      if @x.nil?
        @x2 = nil
        @y2 = nil
      else
        @x2 = @x
        @y2 = @y
      end
      @x = x
      @y = y
    end
    attr_accessor :x
    attr_accessor :y
    attr_accessor :x2
    attr_accessor :y2
    attr_accessor :x3
    attr_accessor :y3
  end # /Ball

  class Paddle
    def initialize
      reset
    end
    def set_position( x, y )
      @x = x
      @y = y
    end
    def reset
      @x = nil
      @y = nil
      @target_y = nil
      @avg_target_y = nil
    end    
    def set_target( y )
      # also calculate average from two sets
      if @target_y != nil
        @avg_target_y = (@target_y + y) / 2
      else
        # no previous result available so set average to nil
        @avg_target_y = nil
      end
      @target_y = y
    end
    attr_reader :x
    attr_reader :y
    attr_reader :target_y
    attr_reader :avg_target_y
  end # /class

  class Math

    # Solves collisions from p1 point (Vector2) and returns
    # a new point of the resulting vector
    def solve_collisions x1, y1, x2, y2, config, max_iterations
      # loop while we are simulating
      iterations = 0
      distance = 0
      while iterations < max_iterations
        deltaX = x1-x2
        deltaY = y1-y2

        # check the ball y-velocity and set the collision
        # check line y-coordinate
        if deltaY < 0
          y = config.ballRadius
        else
          y = config.arenaHeight - config.ballRadius - 1
        end

        # calculate what x-coordinate the ball is going to hit
        x = calculate_collision y, x1, y1, x2, y2

        # ball is going to hit the left side
        if x <= config.paddleWidth + config.ballRadius
          # no collision, calculate direct line
          x = config.paddleWidth + config.ballRadius
          y = calculate_collision x, y1, x1, y2, x2
          # add the travelled path to the distances
          distance += ::Math.hypot x-x1, y-y1
          return SolveResult.new x, y, deltaX, deltaY, distance, iterations

        elsif x >= config.arenaWidth - config.paddleWidth - config.ballRadius - 1
          # no collision, calculate direct line
          x = config.arenaWidth - config.paddleWidth - config.ballRadius - 1
          y = calculate_collision x, y1, x1, y2, x2
          # add the travelled path to the distances
          distance += ::Math.hypot x-x1, y-y1
          return SolveResult.new x, y, deltaX, deltaY, distance, iterations

        else
          # add the travelled path to the distances
          distance += ::Math.hypot x-x1, y-y1
          # bounce and continue simulating
          x2 = x - deltaX
          y2 = y + deltaY
          x1 = x
          y1 = y
          # increment iteration count
          iterations+=1
        end #/if        

      end # /while
    end # /solve_collisions


    def angle_to_hit_offset_power a
      a = (a - 90).abs # rotate to ccw 90 degrees and get difference from zero angle
      a -= 15 # no reduction if angle is lower or equal to 15
      # cap angle to 0 to 35
      a = 0 if a < 0
      a = 50 if a > 50
      if a > 25
        return( -(Float(a-25) / 50) )
      else
        return( 1.0 - (Float(a) / 50) )
      end
    end # /angle_to_hit_offset_power

    def is_close_to( a, b, diff = 0.001 )
      return true if ( (a-b).abs < diff )
      return false
    end

    def calculate_collision(y1, x2, y2, x3, y3)
      return (x3 - ((x2 - x3) / (y2 - y3)) * (y3 - y1))
    end

    # create new function to return the correct x1,y1,x2,y2,x3,y3
    # values automatically from input x1,y1,x2,y2,x3,y3
    # note: for case 1, calculate impact position and use
    #       that as the source point for calculating
    #       the exit angle.

    def is_p3_on_the_same_p1p2_line(x1, y1, x2, y2, x3, y3)
      return false if is_close_to(x2, x1)
      return false if is_close_to(y2, y1)
      a = Float(x2-x1)
      b = Float(y2-y1)
      return ((x3-x1)-(a/b)*(y3-y1)).abs<2
    end # /is_p3_on_the_same_p1p2_line

    def is_p1_on_the_same_p2p3_line(x1, y1, x2, y2, x3, y3)
      return false if is_close_to(x2, x3)
      return false if is_close_to(y2, y3)
      a = Float(x2-x3)
      b = Float(y2-y3)
      return ((x1-x3)-(a/b)*(y1-y3)).abs<2
    end # /is_p1_on_the_same_p2p3_line

    def on_the_same_line(x1, y1, x2, y2, x3, y3)
      return true if is_close_to(y1, y2) && is_close_to(y1, y3)
      return true if is_close_to(x1, x2) && is_close_to(x1, x3)
      return false if is_close_to(x2, x3)
      return false if is_close_to(y2, y3)
      a = Float(x2-x3)
      b = Float(y2-y3)
      return ((x3-x1)-(a/b)*(y3-y1)).abs<2
    end # /on_the_same_line

    def radians_to_degree( radians )
      return radians * 180 / ::Math::PI
    end # /radians_to_degree

    def calculate_line_angle( x1, y1, x2, y2 )
      angle = radians_to_degree( ::Math.atan((x2-x1)/(y2-y1)) )
      if x2 > x1
        if y2 < y1
          angle = -angle
        else
          angle = 90 + (90 - angle)
        end
      else
        if y2 < y1
          angle = 270 + (90 - angle)
        else
          angle = 180 - angle
        end
      end
      return angle
    end # /calculate_line_angle

  end

end #/ module