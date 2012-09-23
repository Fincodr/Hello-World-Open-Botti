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
      @dx = dx
      @dy = dy
    end
    def scale sz
      @dx *= sz
      @dy *= sz
    end
    def normalize
      power = Math.hypot( dx, dy )
      @dx /= power
      @dy /= power
    end 
    def rotate degrees
      ca = ::Math.cos(-degrees*(::Math::PI/180))
      sa = ::Math.sin(-degrees*(::Math::PI/180))
      rx = @dx*ca-@dy*sa
      ry = @dx*sa+@dy*ca
      @dx = rx
      @dy = ry
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
      if @y2.nil?
        @y3 = nil
      else
        @y3 = @y2
      end
      if @y.nil?
        @y2 = nil
        @dy = nil
      else
        @y2 = @y
        @dy = @y-y
      end
      if not @y.nil? and not @dy.nil?
        @avg_dy = (@dy+(@y-y)) / 2
      else
        @avg_dy = nil
      end
      @x = x
      @y = y
    end
    def reset
      @x = nil
      @y = nil
      @y2 = nil
      @y3 = nil
      @dy = nil
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
    attr_reader :y2
    attr_reader :y3
    attr_reader :target_y
    attr_reader :avg_target_y
    attr_reader :dy
    attr_reader :avg_dy
  end # /class

  class Math

    # Returns top secret formula results
    def top_secret_formula offset
      a = Float(offset)
      return 0 if is_close_to a, 0
      #return (0.57125*y) = pretty darn good :)
      #return (0,6-(y.abs/1500))*y = good too
      # from excel: =(0,57-(LOG(ITSEISARVO(B2)/500))/2000)*B2 = closest?
      #return (0.6-(a.abs/1500))*a
      #return (0.6*a)
      # trendiviivan mukaan testi :-)
      #return 0.5945*a + 0.0588
      #return 0.5509*a + 0.2178
      return (0.57 - (::Math.log10(a.abs/500.0)/2000.0))*a
    end    

    # Solves collisions from p1 point (Vector2) and returns
    # a new point of the resulting vector
    def solve_collisions x1, y1, x2, y2, config, max_iterations
      # loop while we are simulating
      x = 0
      y = 0
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

      # can't solve, return last position
      return SolveResult.new x, y, deltaX, deltaY, distance, iterations

    end # /solve_collisions

    # We need to limit the usable offset range
    # for up or down paddle depending on what
    # angle the ball is going to hit the paddle.
    #
    # If the ball is going to hit in <= 90
    # degree angle we are going to return minus
    # value that indicates of how many pixels
    # should be cut from the bottom paddle
    # offset.
    # And if the ball is going to hit in >90
    # degree ange we are going to return plus
    # value that indicates of how many pixels
    # should be cut from the top paddle
    # offset.
    # The value is calculated using the
    # second parameter that is usually the
    # paddle width (10 pixels for example)
    def angle_to_hit_offset_cut a, b
      if a < 90
        return -(::Math.cos((::Math::PI/180)*a))*b-3
      else
        return -(::Math.cos((::Math::PI/180)*a))*b+3
      end
    end # /angle_to_hit_offset_cut

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