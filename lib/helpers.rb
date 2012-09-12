module Helpers

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

end # /module