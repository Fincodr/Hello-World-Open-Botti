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

  class Math

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

end # /module