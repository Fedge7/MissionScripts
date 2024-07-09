--[[
FMS Common Utilities
Author: Fedge

Description:
	This script contains many utility and convenience functions that may be useful in various missions

Dependencies:
	- MOOSE

]]


if not FMS then FMS = {} end -- FMS Namespace
FMS.Utilities = {}          -- FMS Module Name

--- Searches for and removes static objects from the mission with names prefixed by `BLOCKER`.
-- Designed to be used for blocking certain spawn locations on the supercarrier.
-- @param DCS#coalition.side coalition_ The coalition side for which to remove blocker statics.
function FMS.RemoveBlockerStatics(coalition_)
	local statObj = coalition.getStaticObjects(coalition_ or coalition.side.BLUE)
	for i, static in pairs(statObj) do
		local staticName = static:getName()
		if string.match(staticName, "BLOCKER.*") then
			static:destroy()
		end
	end
end

function FMS.CallHandler(handler, ...)
	if handler then
		local f = function() handler( unpack(arg) ) end
		local status, result = pcall(f)
		if not status then
			env.error("FMS|Error calling handler: "..tostring(result or "nil"))
		end
	end
end

-----------------------------------------------------------------------------------------------------------------------
--[[ MOOSE GROUP EXTENSIONS ]]-----------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

--- Orders this group to move towards the nearest enemy
-- @param #GROUP self
-- @param #number maximumEnemyRange_ The maximum range (in meters) inside of which this group will attempt to move. (Optional, default is 2000 meters)
function GROUP:moveToNearestEnemy(maximumEnemyRange_)

	local detectionRangeInMeters = maximumEnemyRange_ or 2000
	
	local groupZone = ZONE_GROUP:New("Zone-" .. self:GetName(), self, detectionRangeInMeters)

	local enemiesSet = SET_GROUP:New()
		:FilterZones({groupZone})
		:FilterActive(true)
		:FilterCoalitions("red")
		:FilterOnce()

	env.info("Found " .. tostring(enemiesSet:Count()) .. " enemies.")

	-- TODO: Check for enemy count

	local enemies = {}
	enemiesSet:ForEachGroup(function(_enemy)
		env.info("  - Found Enemy: " .. _enemy:GetName())
		local tgtDist = self:GetCoordinate():Get2DDistance(_enemy:GetCoordinate())
		table.insert(enemies, {group = _enemy, distance = tgtDist})
		-- env.info("      distance: " .. tostring(tgtDist))
	end)

	table.sort(enemies, function(a,b) return a.distance < b.distance end)

	local closestEnemy = enemies[1].group
	if closestEnemy then
		local coordinate = closestEnemy:GetVec2()
		self:SetAIOn()
		self:OptionAlarmStateAuto()
		self:OptionDisperseOnAttack(30)
		self:OptionROEOpenFirePossible()
		self:RouteToVec2(coordinate,5)
	end

end

-----------------------------------------------------------------------------------------------------------------------
--[[ MOOSE SPAWN EXTENSIONS ]]-----------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------

--- Performs the specified handler function for each alive group spawned by this SPAWN object.
-- @param #SPAWN self
-- @param #function handler The function to be called for each group. Must accept a #GROUP object.
function SPAWN:ForEachAliveGroup(handler)
	local group, index = self:GetFirstAliveGroup()
	while group ~= nil do
		handler(group)
		group, index = self:GetNextAliveGroup(index)
	end
end

--- Returns a SET_GROUP containing each alive group spawned by this SPAWN object.
-- @param #SPAWN self
function SPAWN:GetAliveGroupSet()
	local set = SET_GROUP:New()
	self:ForEachAliveGroup(function(grp) set:AddGroup(grp) end)
	return set
end

--- Destroys every alive group spawned by this SPAWN object.
-- @param #SPAWN self
-- @param #boolean generateEvent_ If true, a crash [AIR] or dead [GROUND] event for each unit is generated. If false, if no event is triggered. If nil, a RemoveUnit event is triggered.
-- @param #number delay_ Delay in seconds before despawning the group.
function SPAWN:DestroyAllGroups(generateEvent_, delay_)
	self:ForEachAliveGroup(function(grp) grp:Destroy(generateEvent_, delay_) end)
end

--- Checks if this SPAWN object has spawned any groups that are currently alive
-- @return true if there is at least one group alive, otherwise false.
function SPAWN:HasAliveGroups()
	local group, index = self:GetFirstAliveGroup()
	return (index ~= nil and index > 0)
end

function SPAWN:GetGroupName()
	return self.SpawnTemplate.name
end