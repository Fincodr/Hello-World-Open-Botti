require_relative 'helpers'

module Simulation

	MAX_STATES = 3

	class CPaddle
		def initialize y
			@y = y
			@dy = nil
		end
		attr_accessor :y
		attr_accessor :dy
	end

	class CBall
	    def initialize x, y
	    	@x = x
	    	@y = y
	    	@dx = nil
	    	@dy = nil
	    end
    	attr_accessor :x
    	attr_accessor :y
    	attr_accessor :dx
    	attr_accessor :dy
	end

	class CState 
		def initialize bx, by, p1y, p2y, time
			@ownPaddle = CPaddle.new p1y
			@opponentPaddle = CPaddle.new p2y
			@ball = CBall.new bx, by
			@time = time
		end
		attr_accessor :ball
		attr_accessor :ownPaddle
		attr_accessor :opponentPaddle
		attr_accessor :time
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
		def initialize config
			@States = []
			@CurrentState = nil
			@ElapsedTime = 0.0
			@semaphore = Mutex.new
			@config = config
			@max_iterations = 10
		end
		def add_state bx, by, p1y, p2y
			@semaphore.lock
			# add new state and remove the oldest state
			if @States.count >= MAX_STATES
				# remove the oldest state
				@States.delete_at(0)
			end
			@States.push CState.new bx, by, p1y, p2y, Time.now.to_f*1000.0
			@ElapsedTime = 0
			@semaphore.unlock
		end
		def update delta_time
			@ElapsedTime += delta_time
			@semaphore.lock
			# if we dont have current state we should
			# copy the last available state and start
			# working from that
			if @CurrentState.nil? and @States.count > 0
				@CurrentState = @States.last.dup
			end
			# update the current state using the
			# last known information about the
			# direction and velocity of objects
			# Now, lets just return the latest state known
			ex1 = @config.paddleWidth + @config.ballRadius
			ex2 = @config.arenaWidth - (@config.paddleWidth + @config.ballRadius) - 1
			ey1 = @config.ballRadius
			ey2 = @config.arenaHeight - @config.ballRadius - 1
			if not @CurrentState.nil? and @States.count > 1
				# Calculate velocies over time
				last = get_last_state
				prev = get_prev_state
				bx_d = last.ball.x - prev.ball.x
				bx_vt = (bx_d) / (last.time - prev.time)
				by_d = last.ball.y - prev.ball.y
				by_vt = (by_d) / (last.time - prev.time)
				p1y_vt = (last.ownPaddle.y - prev.ownPaddle.y) / (last.time - prev.time)
				p2y_vt = (last.opponentPaddle.y - prev.opponentPaddle.y) / (last.time - prev.time)

				@CurrentState.ownPaddle.y = last.ownPaddle.y + p1y_vt * @ElapsedTime
				@CurrentState.opponentPaddle.y = last.opponentPaddle.y + p2y_vt * @ElapsedTime

				bx = last.ball.x + bx_vt * @ElapsedTime
				by = last.ball.y + by_vt * @ElapsedTime

				if bx <= ex1
					# solve collision point
					enter_vector = Helpers::Math::Vector2.new last.ball.x, last.ball.y, last.ball.x - prev.ball.x, last.ball.y - prev.ball.y
					solve_results = Helpers::Math::solve_collisions enter_vector.x, enter_vector.y, enter_vector.x-enter_vector.dx, enter_vector.y-enter_vector.dy, @config, 1
					p = solve_results.point
					Helpers::Log::debug "Collision @ #{p.x}, #{p.y} - Paddle offset = #{p.y-@CurrentState.ownPaddle.y}"
					# calculate exit point
					distance = Math::hypot bx_d, by_d
					distance_to_paddle = Math::hypot last.ball.x-p.x, last.ball.y-p.y
					distance_from_paddle = distance - distance_to_paddle
					power = distance_from_paddle / distance
					prev.ball.x = p.x
					prev.ball.y = p.y
					last.ball.x = p.x - bx_d * power
					last.ball.y = p.y + by_d * power
					bx = last.ball.x
					by = last.ball.y
				end

				if bx >= ex2
					# solve collision point
					enter_vector = Helpers::Math::Vector2.new last.ball.x, last.ball.y, last.ball.x - prev.ball.x, last.ball.y - prev.ball.y
					solve_results = Helpers::Math::solve_collisions enter_vector.x, enter_vector.y, enter_vector.x-enter_vector.dx, enter_vector.y-enter_vector.dy, @config, 1
					p = solve_results.point
					Helpers::Log::debug "Collision @ #{p.x}, #{p.y}"
					# calculate exit point
					distance = Math::hypot bx_d, by_d
					distance_to_paddle = Math::hypot last.ball.x-p.x, last.ball.y-p.y
					distance_from_paddle = distance - distance_to_paddle
					power = distance_from_paddle / distance
					prev.ball.x = p.x
					prev.ball.y = p.y
					last.ball.x = p.x - bx_d * power
					last.ball.y = p.y + by_d * power
					bx = last.ball.x
					by = last.ball.y
				end

				if by <= ey1
					# solve collision point
					enter_vector = Helpers::Math::Vector2.new last.ball.x, last.ball.y, last.ball.x - prev.ball.x, last.ball.y - prev.ball.y
					solve_results = Helpers::Math::solve_collisions enter_vector.x, enter_vector.y, enter_vector.x-enter_vector.dx, enter_vector.y-enter_vector.dy, @config, 1
					p = solve_results.point
					Helpers::Log::debug "Collision @ #{p.x}, #{p.y}"
					# calculate exit point
					distance = Math::hypot bx_d, by_d
					distance_to_paddle = Math::hypot last.ball.x-p.x, last.ball.y-p.y
					distance_from_paddle = distance - distance_to_paddle
					power = distance_from_paddle / distance
					prev.ball.x = p.x
					prev.ball.y = p.y
					last.ball.x = p.x + bx_d * power
					last.ball.y = p.y - by_d * power
					bx = last.ball.x
					by = last.ball.y
				end

				if by >= ey2
					# solve collision point
					enter_vector = Helpers::Math::Vector2.new last.ball.x, last.ball.y, last.ball.x - prev.ball.x, last.ball.y - prev.ball.y
					solve_results = Helpers::Math::solve_collisions enter_vector.x, enter_vector.y, enter_vector.x-enter_vector.dx, enter_vector.y-enter_vector.dy, @config, 1
					p = solve_results.point
					Helpers::Log::debug "Collision @ #{p.x}, #{p.y}"
					# calculate exit point
					distance = Math::hypot bx_d, by_d
					distance_to_paddle = Math::hypot last.ball.x-p.x, last.ball.y-p.y
					distance_from_paddle = distance - distance_to_paddle
					power = distance_from_paddle / distance
					prev.ball.x = p.x
					prev.ball.y = p.y
					last.ball.x = p.x + bx_d * power
					last.ball.y = p.y - by_d * power
					bx = last.ball.x
					by = last.ball.y
				end

				@CurrentState.ball.dx = bx - @CurrentState.ball.x
				@CurrentState.ball.dy = by - @CurrentState.ball.y
				@CurrentState.ball.x = bx
				@CurrentState.ball.y = by
			end
			@semaphore.unlock
		end
		def get_last_state
			return @States.last
		end
		def get_prev_state
			if @States.count > 1
				return @States[@States.count-2]
			else
				return nil
			end
		end
		def clone_current_state
			return_state = nil
			@semaphore.lock
			if not @CurrentState.nil? and @States.count > 1
				return_state = @CurrentState.dup
			end
			@semaphore.unlock
			return return_state
		end
		def count
			@semaphore.lock
			count = @States.count
			@semaphore.unlock
			return count
		end
	end

end # /Simulation