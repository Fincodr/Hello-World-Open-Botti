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
      reset
    end
    def set_position( x, y )
      @x = x
      @y = y
    end
    def reset
      @x = 0
      @y = 0
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

    def angle_to_hit_offset_power a
      a = (a - 90).abs # rotate to ccw 90 degrees and get difference from zero angle
      a -= 25 # no reduction if angle is lower or equal to 25
      # cap angle to 30 max
      a = 0 if a < 0
      a = 30 if a > 30
      return( 1.0 - (Float(a) / 100) )
    end

    def is_close_to( a, b, diff = 0.001 )
      return true if ( (a-b).abs < diff )
      return false
    end

    def calculate_collision(y1, x2, y2, x3, y3)
      x1 = x3 - ((x2 - x3) / (y2 - y3)) * (y3 - y1)
      return x1
    end

    def on_the_same_line(x1, y1, x2, y2, x3, y3)
      begin
        return true if is_close_to(y1, y2) && is_close_to(y1, y3)
        return true if is_close_to(x1, x2) && is_close_to(x1, x3)
        amount = ((x3-x1).abs - ((x2 - x3).abs / (y2 - y3).abs) * (y3 - y1).abs).abs
        if amount < 1
          return true
        else
          return false
        end
      rescue
        # division by zero
        return false
      end
    end

    def radians_to_degree( radians )
      return radians * 180 / ::Math::PI
    end #/ radians_to_degree

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
    end

  end

end # /module