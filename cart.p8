pico-8 cartridge // http://www.pico-8.com
version 16
__lua__

--[[
platform channels:
	1:	blocks
]]

-- convenient no-op function that does nothing
function noop() end

local entities
local buttons={}
local button_presses={}

-- a dictionary of entity classes that can be spawned via spawn_entity
-- todo: leap_velocity properly accounts for leaping into an object
local entity_classes={
	slime={
		width=10,
		height=8,
		collision_channel=1, -- blocks
		collision_indent=2,
		input_buffer_amount=3,
		jump_dir=nil,
		airborne_vx=0,
		airborne_vy=0,
		stuck_dir=nil,
		stuck_platform=nil,
		has_double_jump=false,
		jumpable_surface=nil,
		jumpable_surface_dir=nil,
		jumpable_surface_buffer_frames=0,
		jump_disabled_frames=0,
		stick_disabled_frames=0,
		slide_frames=0,
		has_slid_this_frame=false,
		momentum_level=0,
		momentum_dir=nil,
		momentum_reset_frames=0,
		is_bouncing=false,
		bounce_energy=0,
		bounces=0,
		-- sliding_platform=nil,
		init=function(self)
			-- initialize object to keep track of inputs
			self.buffered_presses={}
			local i
			for i=0,5 do
				self.buffered_presses[i]=0
			end
		end,
		update=function(self)
			-- stop bouncing if down is no longer held
			if self.is_bouncing and not buttons[3] and ((self.bounces>0 and self.vy>-1) or self.bounces>6) then
				self.is_bouncing=false
			end
			if decrement_counter_prop(self,"jumpable_surface_buffer_frames") then
				self.jumpable_surface=nil
				self.jumpable_surface_dir=nil
			end
			decrement_counter_prop(self,"jump_disabled_frames")
			decrement_counter_prop(self,"stick_disabled_frames")
			-- maintain momentum so long as the slime doesn't stick to anything for too long
			if not self.stuck_platform then
				self.momentum_reset_frames=7
			elseif decrement_counter_prop(self,"momentum_reset_frames") then
				self.momentum_level=0
				self.momentum_dir=nil
			end
			-- keep track of inputs
			local i
			for i=0,5 do
				self.buffered_presses[i]=decrement_counter(self.buffered_presses[i])
				if button_presses[i] then
					self.buffered_presses[i]=self.input_buffer_amount
				end
			end
			-- gravity accelerates the slime downwards
			if not self.stuck_platform then
				self.vy=min(self.vy+0.25,ternary(self.is_bouncing,5,3.5))
			end
			-- the slime slows to a stop when sliding
			if self.slide_frames>6 and self.has_slid_this_frame then
				local base_vx=self.jumpable_surface and self.jumpable_surface.vx or 0
				self.vx=base_vx+0.92*(self.vx-base_vx)
			end
			-- check for bounce
			if not self.is_bouncing and self.vy>-1 and not self.jumpable_surface and not self.stuck_platform and button_presses[3] then
				self.is_bouncing=true
				self.vy=5 -- self.airborne_vy+5
				self.bounces=0
				self:recalc_bounce_energy()
			end
			-- check for jumps
			if not self.is_bouncing and self.jump_disabled_frames<=0 and (self.jumpable_surface_buffer_frames>0 or self.has_double_jump) then
				-- slide down right surface
				if buttons[1] and self.stuck_dir=="right" then
					self.buffered_presses[1]=0
					self.jump_dir="right"
					self:unstick()
				-- slide down left surface
				elseif buttons[0] and self.stuck_dir=="left" then
					self.buffered_presses[0]=0
					self.jump_dir="left"
					self:unstick()
				-- let go of top surface
				elseif self.buffered_presses[2]>0 and self.stuck_dir=="up" then
					self.buffered_presses[2]=0
					self.jump_dir="up"
					self:unstick()
				-- jump right
				elseif self.buffered_presses[1]>0 and self.stuck_dir!="right" then
					self.buffered_presses[1]=0
					self:jump("right")
				-- jump left
				elseif self.buffered_presses[0]>0 and self.stuck_dir!="left" then
					self.buffered_presses[0]=0
					self:jump("left")
				-- jump up
				elseif self.buffered_presses[2]>0 then
					self.buffered_presses[2]=0
					self:jump("up")
				end
			end
			if self.stuck_platform then
				self.airborne_vx=self.vx
				self.airborne_vy=self.vy
			end
			-- apply the velocity
			self.slide_platform=nil
			self.collision_padding=ternary(self.stick_disabled_frames>0,0,0.5)
			self.has_slid_this_frame=false
			self:apply_velocity(self.is_bouncing)
			-- keep track of slide time
			if self.has_slid_this_frame then
				increment_counter_prop(self,"slide_frames")
			end
			-- the slime sticks if it slows to a stop
			if not self.stuck_platform and self.jumpable_surface_dir=="down" and abs(self.vx-self.jumpable_surface.vx)<0.1 then
				self:stick(self.jumpable_surface,self.jumpable_surface_dir)
			end
		end,
		draw=function(self)
			if self.stuck_platform then
				self:draw_outline(12)
			elseif self.jumpable_surface_buffer_frames>0 then
				self:draw_outline(11)
			else
				self:draw_outline(0)
			end
		end,
		on_collide=function(self,dir,other)
			local vx=self.vx
			self:handle_collision(dir,other)
			-- bounce off of the platform
			if self.is_bouncing then
				self:bounce(other,dir,vx)
			-- slide across the platform
			elseif self.stick_disabled_frames>0 or (self.jump_dir=="left" and buttons[0]) or (self.jump_dir=="right" and buttons[1]) or (self.jump_dir=="up" and buttons[2] and dir!="up") then
				self:slide(other,dir)
				-- todo: update airborne_vx and airborne_vy
			-- stick to the platform
			elseif not self.stuck_platform or other==self.stuck_platform or (dir=="down" and self.stuck_dir!="down") then
				self:stick(other,dir)
			end
		end,
		bounce=function(self,platform,dir,vx)
			increment_counter_prop(self,"bounces")
			local vy=min(5,sqrt(2*(self.bounce_energy-0.25*(128-self.y))))
			if dir=="down" then
				self.has_double_jump=true
				self.vy=platform.vy-vy
				self:recalc_bounce_energy()
			elseif dir=="up" then
				self.vy=platform.vy+vy
				self:recalc_bounce_energy()
			elseif dir=="left" then
				self.vx=max(0,platform.vx-(vx-platform.vx))
			elseif dir=="right" then
				self.vx=min(0,platform.vx-(vx-platform.vx))
			end
		end,
		recalc_bounce_energy=function(self)
			self.bounce_energy=self.vx*self.vx/2+0.25*(128-self.y)
		end,
		slide=function(self,platform,dir)
			if dir=="down" then
				self.has_double_jump=true
				self:set_jumpable_surface(platform,dir)
				self.has_slid_this_frame=true
			end
		end,
		stick=function(self,platform,dir)
			self.jump_dir=nil
			self.has_double_jump=true
			self:set_jumpable_surface(platform,dir)
			self.jump_disabled_frames=0
			self.stuck_dir=dir
			self.stuck_platform=platform
			self.vx=platform.vx
			self.vy=platform.vy
			self.slide_frames=0
		end,
		unstick=function(self)
			self.stuck_dir=nil
			self.stuck_platform=nil
			self.jumpable_surface=nil
			self.jumpable_surface_dir=nil
			self.jumpable_surface_buffer_frames=0
			self.stick_disabled_frames=2
			self.slide_frames=0
		end,
		jump=function(self,dir)
			local momentum_vx=self.momentum_level
			-- jump off of a surface
			if self.jumpable_surface_buffer_frames>0 then
				-- continue gaining momentum
				if dir==self.momentum_dir then
					increment_counter_prop(self,"momentum_level")
				end
				-- stick to it momentarily (in case we were sliding)
				self:stick(self.jumpable_surface,self.jumpable_surface_dir)
				-- switch directions when jumping up off of walls
				if dir=="up" then
					if self.jumpable_surface_dir=="left" then
						increment_counter_prop(self,"momentum_level")
						self.momentum_dir="right"
					elseif self.jumpable_surface_dir=="right" then
						increment_counter_prop(self,"momentum_level")
						self.momentum_dir="left"
					end
				-- begin gaining momentum
				elseif dir!=self.momentum_dir then
					self.momentum_dir=dir
					if self.jumpable_surface_dir=="left" or self.jumpable_surface_dir=="right" then
						increment_counter_prop(self,"momentum_level")
					else
						momentum_vx=0
						self.momentum_level=1
					end
				end
				-- then jump off of the surface
				self.airborne_vx=self.vx--+0.1*momentum_vx*ternary(self.momentum_dir=="left",-1,1)
				self.airborne_vy=self.vy
			-- exhaust double jump to jump in mid-air
			else
				self.has_double_jump=false
				if (dir=="left" or dir=="right") and self.momentum_dir!=dir then
					self.momentum_dir=dir
					self.momentum_level=1
				end
			end
			-- set jump vars
			self.jump_dir=dir
			self.jump_disabled_frames=3
			self.slide_frames=0
			-- change velocity
			if dir=="left" then
				self.vx=self.airborne_vx-2
				if self.jumpable_surface_dir=="up" then
					self.vy=self.airborne_vy
				else
					self.vy=self.airborne_vy-2.5
				end
			elseif dir=="right" then
				self.vx=self.airborne_vx+2
				if self.jumpable_surface_dir=="up" then
					self.vy=self.airborne_vy
				else
					self.vy=self.airborne_vy-2.5
				end
			elseif dir=="up" then
				self.vx=self.airborne_vx
				if self.stuck_dir=="left" then
					self.vx+=0.5
				elseif self.stuck_dir=="right" then
					self.vx-=0.5
				end
				self.vy=self.airborne_vy-3.5
			end
			-- and the slime is no longer stuck to any platforms
			if self.jumpable_surface_buffer_frames>0 then
				self:unstick()
			end
		end,
		set_jumpable_surface=function(self,platform,dir)
			if self.jumpable_surface_buffer_frames<3 or dir=="down" then
				self.jumpable_surface=platform
				self.jumpable_surface_dir=dir
				self.jumpable_surface_buffer_frames=3
			end
		end
	},
	block={
		platform_channel=1, -- blocks
		draw=function(self)
			self:draw_outline(0)
		end
	}
}

function _init()
	entities={}
	-- spawn initial entities
	spawn_entity("slime",30,85)
	spawn_entity("block",1,20,{ height=60 })
	spawn_entity("block",119,20,{ height=60 })
	spawn_entity("block",1,90,{ width=126 })
	spawn_entity("block",30,68,{ width=60 })
end

-- local skip_frames=0
function _update()
	-- skip_frames+=1
	-- if skip_frames%10>0 and not btn(5) then return end
	-- keep better track of button presses
	--  (because btnp repeats presses when holding)
	local i
	for i=0,5 do
		button_presses[i]=btn(i) and not buttons[i]
		buttons[i]=btn(i)
	end
	-- update all the entities
	local entity
	for entity in all(entities) do
		entity:update()
	end
end

function _draw()
	-- clear the screen to yellow
	cls(10)
	-- draw all the entities
	local entity
	for entity in all(entities) do
		entity:draw()
	end
end

-- spawns an entity that's an instance of the given class
function spawn_entity(class_name,x,y,args)
	local class_def=entity_classes[class_name]
	-- create a default entity
	local entity={
		class_name=class_name,
		x=x,
		y=y,
		vx=0,
		vy=0,
		width=8,
		height=8,
		collision_indent=2,
		collision_padding=0,
		platform_channel=0,
		collision_channel=0,
		init=noop,
		update=function(self)
			self:apply_velocity()
		end,
		apply_velocity=function(self,stop_after_collision)
			-- move in discrete steps
			local max_move_x=min(self.collision_indent,self.width-2*self.collision_indent)-0.1
			local max_move_y=min(self.collision_indent,self.height-2*self.collision_indent)-0.1
			local steps=max(1,ceil(max(abs(self.vx/max_move_x),abs(self.vy/max_move_y))))
			local i
			for i=1,steps do
				-- apply velocity
				self.x+=self.vx/steps
				self.y+=self.vy/steps
				-- check for collisions
				if self:check_for_collisions() and stop_after_collision then
					return
				end
			end
		end,
		-- collision functions
		check_for_collisions=function(self)
			local found_collision=false
			-- check each other entity
			local entity
			for entity in all(entities) do
				-- check if they have matching collision channels
				if entity!=self and band(self.collision_channel,entity.platform_channel)>0 then
					local collision_dir=objects_colliding(self,entity)
					if collision_dir then
						-- they are colliding!
						self:on_collide(collision_dir,entity)
						found_collision=true
					end
				end
			end
			return found_collision
		end,
		on_collide=function(self,dir,other)
			-- just handle the collision by default
			self:handle_collision(dir,other)
		end,
		handle_collision=function(self,dir,other)
			-- reposition this entity and adjust the velocity
			if dir=="left" then
				self.x=other.x+other.width
				self.vx=max(self.vx,other.vx)
			elseif dir=="right" then
				self.x=other.x-self.width
				self.vx=min(self.vx,other.vx)
			elseif dir=="up" then
				self.y=other.y+other.height
				self.vy=max(self.vy,other.vy)
			elseif dir=="down" then
				self.y=other.y-self.height
				self.vy=min(self.vy,other.vy)
			end
		end,
		-- draw functions
		draw=noop,
		draw_outline=function(self,color)
			rect(self.x+0.5,self.y+0.5,self.x+self.width-0.5,self.y+self.height-0.5,color)
		end
	}
	-- add class-specific properties
	local key,value
	for key,value in pairs(class_def) do
		entity[key]=value
	end
	-- override with passed-in arguments
	for key,value in pairs(args or {}) do
		entity[key]=value
	end
	-- add it to the list of entities
	add(entities,entity)
	-- initialize the entitiy
	entity:init()
	-- return the new entity
	return entity
end

-- check to see if two rectangles are overlapping
function rects_overlapping(x1,y1,w1,h1,x2,y2,w2,h2)
	return x1<x2+w2 and x2<x1+w1 and y1<y2+h2 and y2<y1+h1
end

-- check to see if obj1 is overlapping with obj2
function objects_hitting(obj1,obj2)
	return rects_overlapping(obj1.x,obj1.y,obj1.width,obj1.height,obj2.x,obj2.y,obj2.width,obj2.height)
end

-- check to see if obj1 is colliding into obj2, and if so in which direction
function objects_colliding(obj1,obj2)
	local x1,y1,w1,h1,i,p=obj1.x,obj1.y,obj1.width,obj1.height,obj1.collision_indent,obj1.collision_padding
	local x2,y2,w2,h2=obj2.x,obj2.y,obj2.width,obj2.height
	-- check hitboxes
	if rects_overlapping(x1+i,y1+h1/2,w1-2*i,h1/2+p,x2,y2,w2,h2) and obj1.vy>=obj2.vy then
		return "down"
	elseif rects_overlapping(x1+w1/2,y1+i,w1/2+p,h1-2*i,x2,y2,w2,h2) and obj1.vx>=obj2.vx then
		return "right"
	elseif rects_overlapping(x1-p,y1+i,w1/2+p,h1-2*i,x2,y2,w2,h2) and obj1.vx<=obj2.vx then
		return "left"
	elseif rects_overlapping(x1+i,y1-p,w1-2*i,h1/2+p,x2,y2,w2,h2) and obj1.vy<=obj2.vy then
		return "up"
	end
end

-- returns the second argument if condition is truthy, otherwise returns the third argument
function ternary(condition,if_true,if_false)
	return condition and if_true or if_false
end

function increment_counter(n)
	return ternary(n>32000,2000,n+1)
end

function increment_counter_prop(obj,key)
	obj[key]=increment_counter(obj[key])
end

function decrement_counter(n)
	return max(0,n-1)
end

function decrement_counter_prop(obj,key)
	local initial_value=obj[key]
	obj[key]=decrement_counter(initial_value)
	return initial_value>0 and initial_value<=1
end
