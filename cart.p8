pico-8 cartridge // http://www.pico-8.com
version 16
__lua__

-- convenient no-op function that does nothing
function noop() end

local entities

-- an dictionary of entity classes that can be spawned via spawn_entity
local entity_classes={
	slime={
		width=15,
		height=12,
		draw=function(self)
			self:draw_outline(0)
		end
	},
	block={
		draw=function(self)
			self:draw_outline(0)
		end
	}
}

function _init()
	entities={}
	-- spawn initial entities
	spawn_entity("slime",50,50)
	spawn_entity("block",50,80)
end

function _update()
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
		width=8,
		height=8,
		update=noop,
		draw=noop,
		draw_outline=function(self,color)
			rect(self.x,self.y,self.x+self.width-0.5,self.y+self.height-0.5,color)
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
