--[[
FMS Mission Operations Script
Author: Fedge

Description:
	A framework for goal-oriented mission scripting

TODO:
	- PROTECT goal:
		* Is VIP still alive after X minutes? Check for all red units dead with VIP still alive?
	- Any goals with targets: add menu option for "where is my target?". Can change accuracy depending on mission narrative.

]]

if (not FMS) or (not FMS.OpsArea) then
	local msg = "OpsMission: Cannot find OpsArea. Be sure to run OpsArea before attempting to load OpsMission."
	env.error(msg)
	trigger.action.outText(msg, 60)
end

FMS.OpsMission = {}
FMS.OpsMission.__index = FMS.OpsMission

FMS.OpsMission.DEBUG = false

FMS.OpsMission.Goal = {
	--- kill all bad guys
	DESTROY_ALL     =  1,
	--- kill these specific bad guys
	DESTROY_TARGETS =  2,
	--- protect good guy
	PROTECT         =  3,
	--- group successfully arrives somewhere
	ESCORT          =  4,
	--- group is prevented from arriving somewhere
	INTERDICT       =  5,
}

function FMS.OpsMission.Init(parentMenu, menuName_)
	FMS.OpsMission.MainMenu = MENU_MISSION:New(menuName_ or "Mission Ops", parentMenu)
	
	--- Returns a random BASE-10 number consisting only of digits 0-7
	local function GetRandomOctal(numDigits)
	  -- numDigits must be non-nil and greater than 1, otherwise it'll be 1
	  local numDigits = math.clamp(numDigits, 1)
	  local ret = 0
	  for i=1,numDigits do ret = ret*10 + math.random(7) end
	  return ret
	end

	local function keyfunc() return GetRandomOctal(3) end

	FMS.OpsMission.Missions = {
		active    = KeyMap:New(tbl, keyfunc),
		completed = KeyMap:New(tbl, keyfunc)
	}
end

-------------------------------------------------------------------------------
-- INITIALIZATION
-------------------------------------------------------------------------------

function FMS.OpsMission:_New()
	local obj = {}
	setmetatable(obj, self)
	
	obj.msncode = FMS.OpsMission.Missions.active:generatekey()
	-- obj.msncode = #(FMS.OpsMission.Missions.active.data) + 1
	
	if not obj.msncode then
		LOG:Log("OpsMssn: Unable to generate mission code")
		return nil
	end

	obj.log = LOG:New("OpsMssn|" .. tostring(obj.msncode), LOG.Level.TRACE2)
	obj.log:log("Initializing OpsMission")

	FMS.OpsMission.Missions.active:insert(obj, obj.msncode)

	if FMS.OpsMission.DEBUG then obj.debug = {} end

	return obj
end

--- Creates a new OpsMission object from the specified zone
-- @return The newly constructed OpsMission object
function FMS.OpsMission:NewWithZone(zoneName, areaName_, hideMenu_, marker_)
	local obj = FMS.OpsMission:_New()

	local menuName = areaName_ or zoneName
	obj._opsArea = FMS.OpsArea:New(menuName, zoneName, FMS.OpsMission.DEBUG, marker_)
	obj._opsArea:scanForGroupTemplates()

	if (not hideMenu_) or FMS.OpsMission.DEBUG then
		obj:_buildMenus()
	end

	return obj
end

--- Creates a new OpsMission object from the specified STM file
-- @return The newly constructed OpsMission object
function FMS.OpsMission:NewFromSTM(areaName, templateName, relPath_, zoneName_, hideMenu_, marker_)
	local obj = FMS.OpsMission:_New()
	obj._opsArea = FMS.OpsArea:NewFromSTM(areaName, templateName, relPath_, zoneName_, nil, FMS.OpsMission.DEBUG, marker_)

	if (not hideMenu_) or FMS.OpsMission.DEBUG then
		obj:_buildMenus()
	end

	return obj
end

function FMS.OpsMission:_buildMenus()
	local menuName = "["..self.msncode.."] "..self._opsArea.name
	self.menu = MENU_MISSION:New(menuName, FMS.OpsMission.MainMenu)
	self.startMenu = MENU_MISSION_COMMAND:New("Start", self.menu, self.start, self)

	if FMS.OpsMission.DEBUG then
		self.debug.menu = MENU_MISSION:New("[DBG] DEBUG", self.menu)
	end
end

-------------------------------------------------------------------------------
-- GFMSLS AND OBJECTIVES
-------------------------------------------------------------------------------

function FMS.OpsMission:setGoalDestroyAll()
	self.goal = FMS.OpsMission.Goal.DESTROY_ALL

	local msn = self
	self._opsArea:onAfterAllDead(function(ao)
		msn:success()
	end)
end

function FMS.OpsMission:setGoalDestroyGroup(groupNamePrefix)
	self.goal = FMS.OpsMission.Goal.DESTROY_TARGETS

	local msn = self
	self._opsArea:onAfterGroupDead(function(ao, grp)
		if grp:GetName():startswith(groupNamePrefix) then
			msn:success()
		end
	end)
end

--- Configures the mission profile to INTERDICT the specified group from reaching its destination
-- @param #string groupNamePrefix The name of the group
-- @param #multi destination Either the name of a destination zone, or a COORDINATE object
-- @param #number radius_ The radius of the "endzone". Optional, defaults to 100m.
-- @param #number timeLimit_ The total length of time (in seconds) the trigger zone should watched (i.e. the "runtime"). Optional, defaults to 3600.
function FMS.OpsMission:setGoalInterdict(groupNamePrefix, destination, radius_, timeLimit_)
	self.goal = FMS.OpsMission.Goal.INTERDICT
	local endzone = self:_makeZone(destination, radius_)
	self.log:log("GOAL interdict group '".. groupNamePrefix .. "' from reaching zone: '" .. endzone:GetName() .."'")
	self:_watchEndzone(groupNamePrefix, endzone, false, timeLimit_)
end

function FMS.OpsMission:setGoalEscort(groupNamePrefix, destination, radius_, timeLimit_)
	self.goal = FMS.OpsMission.Goal.ESCORT
	local endzone = self:_makeZone(destination, radius_)
	self.log:log("GOAL escort group '".. groupNamePrefix .. "' to zone: '" .. endzone:GetName() .."'")
	self:_watchEndzone(groupNamePrefix, endzone, true, timeLimit_)
end

function FMS.OpsMission:_makeZone(zoneNameOrCoord, radius_)
	if type(zoneNameOrCoord) == 'string' then
		return ZONE:New(zoneNameOrCoord)

	elseif
		type(zoneNameOrCoord) == 'table'
			and zoneNameOrCoord.GetClassName
			and zoneNameOrCoord:GetClassName() == 'COORDINATE' then

		local zoneName = "endzone-"..tostring(self.msncode)
		return ZONE_RADIUS:New(zoneName, zoneNameOrCoord:GetVec2(), radius_ or 100)

	else
		self.log:log("Cannot create endzone with construction param '" ..(zoneNameOrCoord or "nil").."'", LOG.Level.ERROR)
		return nil
	end
end

function FMS.OpsMission:_watchEndzone(groupNamePrefix, endzone, endWithSuccess, timeLimit_)

	self.log:log("GOAL watch group '".. groupNamePrefix .. "' for reaching zone: '" .. endzone:GetName() .."'", LOG.Level.DEBUG)

	local msn = self
	
	-- Since we won't have the exact GROUP object until it spawns in, we'll search for the target group via the onAfterGroupSpawned() callback
	msn._opsArea:onAfterGroupSpawned(function(ao, grp)
		if grp:GetName():startswith(groupNamePrefix) then
			msn.log:log("Found target group = " .. grp:GetName(), LOG.Level.DEBUG)
			endzone:Trigger(grp)
			endzone:__TriggerStop(timeLimit_ or 3600) -- stop watching after 1hr
			function endzone:OnAfterEnteredZone(from, event, to, group)
				local msg = "Target group has reached endzone."
				if endWithSuccess then
					msn.log:log(msg.." Mission success.")
					msn:success()
				else
					msn.log:log(msg.." Mission failure.")
					msn:failure()
				end
			end	

			-- Handle timelimit
			function endzone:OnAfterTriggerStop()
				local msg = "Timelimit expired. " ..groupNamePrefix.." never reached endzone."
				if endWithSuccess then
					msn.log:log(msg.." Mission failure.")
					msn:failure()
				else
					msn.log:log(msg.." Mission success.")
					msn:success()
				end
			end
		end
	end)

	-- If the target group is destroyed, handle mission success or failure.
	msn._opsArea:onAfterGroupDead(function(ao, grp)
		if grp:GetName():startswith(groupNamePrefix) then
			local msg = "Target group has been destroyed before reaching endzone."
			if endWithSuccess then
				msn.log:log(msg.." Mission failure.")
				msn:failure()
			else
				msn.log:log(msg.." Mission success.")
				msn:success()
			end
		end
	end)
end

-------------------------------------------------------------------------------
-- EVENT HANDLERS
-------------------------------------------------------------------------------

function FMS.OpsMission:onStart(onStartFunction)
	self._onStartHandler = onStartFunction
end

function FMS.OpsMission:onEnd(onEndFunction)
	self._onEndHandler = onEndFunction
end

function FMS.OpsMission:onSuccess(onSuccessFunction)
	self._onSuccessHandler = onSuccessFunction
end

function FMS.OpsMission:onFailure(onFailureFunction)
	self._onFailureHandler = onFailureFunction
end

-------------------------------------------------------------------------------
-- EVENTS
-------------------------------------------------------------------------------

function FMS.OpsMission:start()
	self.log:log("Starting mission.", LOG.Level.INFO, FMS.OpsMission.DEBUG)

	if not self.goal then
		self.log:log("No mission goal defined, defaulting to DESTROY_ALL.", LOG.Level.WARNING)
		self:setGoalDestroyAll()
	end

	if self.startMenu then self.startMenu:Remove() end

	local groups = self._opsArea:spawnAll()

	if FMS.OpsMission.DEBUG then
		MENU_MISSION_COMMAND:New("Despawn All", self.debug.menu, self._opsArea.destroySpawnedGroups, self._opsArea)
		MENU_MISSION_COMMAND:New("Finish", self.debug.menu, self.finish, self)
		MENU_MISSION_COMMAND:New("Despawn All and Finish", self.debug.menu, function() self._opsArea:destroySpawnedGroups(); self:finish() end)
		MENU_MISSION_COMMAND:New("Explode All Groups", self.debug.menu, function()
			for groupName, spawner in pairs(self._opsArea._spawners) do
				spawner:ForEachAliveGroup(function(grp)
					grp:GetCoordinate():Explosion( 500 )
				end)
			end
		end)
	end

	-- Call the mission start handler      
	FMS.CallHandler(self._onStartHandler, self)
end

function FMS.OpsMission:finish()
	FMS.CallHandler(self._onEndHandler, self)
end

function FMS.OpsMission:success(delay_)
	local function withDelay()
		FMS.CallHandler(self._onSuccessHandler, self)
		self:finish()
	end

	-- Add a bit of delay, so that any success messages don't happen the *instant* the mission ends.
	local delay = 10 --seconds
	TIMER:New(withDelay):Start(delay_ or 10)
end

function FMS.OpsMission:failure(delay_)
	local function withDelay()
		FMS.CallHandler(self._onFailureHandler, self)
		self:finish()
	end

	TIMER:New(withDelay):Start(delay_ or 10)
end

-------------------------------------------------------------------------------
-- ACTIONS
-------------------------------------------------------------------------------

function FMS.OpsMission:despawnAllGroups()
	self._opsArea:destroySpawnedGroups()
end