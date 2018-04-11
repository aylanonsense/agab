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
local entity_classes={
	slime={
		width=15,
		height=12,
		collision_channel=1, -- blocks
		leap_dir=nil,
		stuck_dir=nil,
		stuck_platform=nil,
		sliding_platform=nil,
		update=function(self)
			-- leap left
			if (button_presses[0] and self.stuck_platform and self.stuck_dir!="left") or (buttons[0] and self.sliding_platform and self.leap_dir!="left") then
				self:stick(self.sliding_platform or self.stuck_platform)
				self:leap("left")
			end
			-- leap right
			if (button_presses[1] and self.stuck_platform and self.stuck_dir!="right") or (buttons[1] and self.sliding_platform and self.leap_dir!="right") then
				self:stick(self.sliding_platform or self.stuck_platform)
				self:leap("right")
			end
			if self.stuck_platform then
				self.vx=self.stuck_platform.vx
				self.vy=self.stuck_platform.vy
			else
				-- apply gravity
				self.vy+=0.25
				if self.sliding_platform then
					self.vx*=0.95 -- todo slide based on platform's velocity
				end
			end
			-- apply the velocity
			self.sliding_platform=nil
			self:apply_velocity()
		end,
		draw=function(self)
			self:draw_outline(0)
			-- print(self.stuck_dir,self.x+0.5,self.y-5.5,0)
		end,
		on_collide=function(self,dir,other)
			self:handle_collision(dir,other)
			-- stick to the platform
			if not self.leap_dir or dir=="left" or dir=="right" or (self.leap_dir=="left" and not buttons[0]) or (self.leap_dir=="right" and not buttons[1]) then
				self:stick(other,dir)
			elseif dir=="down" then
				self.sliding_platform=other
				-- self.leap_dir=nil
			end
		end,
		stick=function(self,platform,dir)
			self.leap_dir=nil
			self.stuck_dir=dir
			self.stuck_platform=platform
			self.vx=platform.vx
			self.vy=platform.vy
		end,
		leap=function(self,dir)
			self.vx+=ternary(dir=="left",-2,2)
			self.vy-=3
			self.leap_dir=dir
			self.stuck_dir=nil
			self.stuck_platform=nil
			self.sliding_platform=nil
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
	spawn_entity("slime",50,65)
	spawn_entity("block",1,80)
	spawn_entity("block",119,80)
	spawn_entity("block",1,90,{
		width=126
	})
end

function _update()
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
		physics_indent=1,
		platform_channel=0,
		collision_channel=0,
		update=function(self)
			self:apply_velocity()
		end,
		apply_velocity=function(self)
			-- move in discrete steps
			local max_move=self.physics_indent-0.1
			local steps=max(1,max(abs(self.vx/max_move),abs(self.vy/max_move)))
			local i
			for i=1,steps do
				-- apply velocity
				self.x+=self.vx/steps
				self.y+=self.vy/steps
				-- check for collisions
				self:check_for_collisions()
			end
		end,
		-- collision functions
		check_for_collisions=function(self)
			-- check each other entity
			local entity
			for entity in all(entities) do
				-- check if they have matching collision channels
				if entity!=self and band(self.collision_channel,entity.platform_channel)>0 then
					local collision_dir=objects_colliding(self,entity)
					if collision_dir then
						-- they are colliding!
						self:on_collide(collision_dir,entity)
					end
				end
			end
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
	local x1,y1,w1,h1,p1=obj1.x,obj1.y,obj1.width,obj1.height,obj1.physics_indent
	local x2,y2,w2,h2,p2=obj2.x,obj2.y,obj2.width,obj2.height,obj2.physics_indent
	-- check hitboxes
	if rects_overlapping(x1+p1,y1+h1/2,w1-2*p1,h1/2,x2,y2,w2,h2) then
		return "down"
	elseif rects_overlapping(x1+w1/2,y1+p1,w1/2,h1-2*p1,x2,y2,w2,h2) then
		return "right"
	elseif rects_overlapping(x1,y1+p1,w1/2,h1-2*p1,x2,y2,w2,h2) then
		return "left"
	elseif rects_overlapping(x1+p1,y1,w1-2*p1,h1/2,x2,y2,w2,h2) then
		return "up"
	end
end

-- returns the second argument if condition is truthy, otherwise returns the third argument
function ternary(condition,if_true,if_false)
	return condition and if_true or if_false
end
