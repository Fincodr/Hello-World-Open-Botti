module Simulation

	MAX_STATES = 3

	class CPaddle
		def initialize y
			@y = y
		end
		attr_accessor :y
	end

	class CBall
	    def initialize x, y
	    	@x = x
	    	@y = y
	    end
    	attr_accessor :x
    	attr_accessor :y
	end

	class CState 
		def initialize bx, by, p1y, p2y
			@ownPaddle = CPaddle.new p1y
			@opponentPaddle = CPaddle.new p2y
			@ball = CBall.new bx, by
		end
	end

	#----------------------------------------------------------
	#
	# Class: Simulation
	#
	# Description: Keeps memory of different simulation states
	# and allows the simulation to be advanced to compensate
	# for lag and also simulate world independently forward
	#
	class CSimulation
		def initialize
			@States = []
		end
		def add_state bx, by, p1y, p2y
			# add new state and remove the oldest state
			if @States.count >= MAX_STATES
				# remove the oldest state
				@States.delete_at(0)
			end
			@States.push CState.new bx, by, p1y, p2y
		end
    	attr_reader :States
	end

end # /Simulation