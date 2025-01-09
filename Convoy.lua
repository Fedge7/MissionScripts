--[[
FMS Convoy Script
Author: Fedge

A simple script for spawning and controlling a "Convoy" group.

]]

if FMS == nil then FMS = {} end

FMS.Convoy = {}
FMS.Convoy.__index = FMS.Convoy

FMS.Convoy.DEBUG = true

function FMS.Convoy.Init(parentMenu)
	FMS.Convoy.MainMenu = MENU_MISSION:New("Convoys", parentMenu)
end

function FMS.Convoy:_New(missionName, showInMenu)
	local obj = {}
	setmetatable(obj, self)
	obj.missionName = missionName or "Convoy Escort"
	obj.showInMenu = showInMenu
	return obj
end

function FMS.Convoy:_init(groupName)
	self.spawner = SPAWN:New(groupName)
	
	if self.showInMenu then
		self.menu = MENU_MISSION:New(self.missionName, FMS.Convoy.MainMenu)
		self.menuSpawn = MENU_MISSION_COMMAND:New("Start", self.menu, FMS.Convoy.spawn, self, true)
	end
end

function FMS.Convoy:New(missionName, groupName, showInMenu_)
	local obj = FMS.Convoy:_New(missionName, showInMenu_)
	
	obj:_init(groupName)

	return obj
end

function FMS.Convoy:setCoords(start, destination)
	self.startCoord = start
	self.endCoord = destination
end

function FMS.Convoy:spawn(startNow_)
	self.spawner:OnSpawnGroup(function(grp)

		local msg = "Convoy '"..self.missionName.."' ready to move.\nCurrent pos: "..grp:GetCoordinate():ToStringMGRS()
		msg = msg.."\nDestination: "..self.endCoord:ToStringMGRS()
		MESSAGE:New(msg, 30):ToAll()

		if startNow_ then
			self:_start(grp)
		end

		if self.showInMenu then
			self.menuSpawn:Remove()
			self:setupControlMenus()
		end

		local cnvy = self

		grp:HandleEvent(EVENTS.Dead)

		function grp:OnEventDead( EventData )
			-- LOG:Log("Convoy Group "..EventData.IniGroup:GetName().." onEventDead()")
			if EventData.IniGroup == grp then
				if not EventData.IniGroup:IsAlive() then
					LOG:Log("CONVOY GROUP DEAD: " .. EventData.IniGroup:GetName())
					grp:UnHandleEvent(EVENTS.Dead)
					cnvy:failure()
				end
			end
		end

	end)

	if self.startCoord then
		self.spawner:SpawnFromCoordinate(self.startCoord)
	else
		self.spawner:Spawn()
	end
end

function FMS.Convoy:setupControlMenus()
	self.menuHold = MENU_MISSION_COMMAND:New("Hold", self.menu, CONTROLLABLE.RouteStop, grp)
	self.menuResume = MENU_MISSION_COMMAND:New("Resume", self.menu, CONTROLLABLE.RouteResume, grp)
	self.menuHoldFire = MENU_MISSION_COMMAND:New("ROE Hold", self.menu, CONTROLLABLE.OptionROEHoldFire, grp)
	self.menuEngage = MENU_MISSION_COMMAND:New("ROE Free", self.menu, CONTROLLABLE.OptionROEOpenFire, grp)
	self.menuPositionCheck = MENU_MISSION_COMMAND:New("Position Check", self.menu, FMS.Convoy.showPosition, self, grp)
end

function FMS.Convoy:resetMenus()
	self.menu:RemoveSubMenus()
	self.menuSpawn = MENU_MISSION_COMMAND:New("Start", self.menu, FMS.Convoy.spawn, self, true)
end



function FMS.Convoy:_start(spawnedGroup)
	spawnedGroup:RouteGroundOnRoad(self.endCoord, nil, nil, AI.Task.VehicleFormation.ON_ROAD, FMS.Convoy.WaypointFunction)
	
	local msg = "Convoy '"..self.missionName.."' rolling."
	MESSAGE:New(msg, 30):ToAll()

	if self.showInMenu then
		if self.menuStart then self.menuStart:Remove() end
	end
end

function FMS.Convoy:startConvoy()
	self:spawn(true)
end

function FMS.Convoy:showPosition(spawnedGroup)
	local str = spawnedGroup:GetCoordinate():ToStringMGRS()
	MESSAGE:New("["..self.missionName.." Conovy] Our position is: "..str, 30):ToAll()
end

function FMS.Convoy.WaypointFunction(controllable, wptIndex, wptCount)
	LOG:Log("Convoy group "..controllable:GetName().." passing waypoint "..tostring(wptIndex).." of "..tostring(wptCount))
	if wptIndex >= wptCount then
		LOG:Log("Convoy group "..controllable:GetName().." has reached its destination.")
	end
end

function FMS.Convoy:success()
	local msg = "Convoy '"..self.missionName.."' has reached its destination."
	MESSAGE:New(msg, 30):ToAll()
	LOG:Log(msg)

	self:resetMenus()
end

function FMS.Convoy:failure()
	local msg = "Convoy '"..self.missionName.."' has failed to reach its destination."
	MESSAGE:New(msg, 30):ToAll()
	LOG:Log(msg)

	self:resetMenus()
end

function FMS.ConvoyHandlerAdapter(sender, handler_, ...)
	FMS.CallHandler(handler_, arg)
end
function GROUP:routeToZone(zone, handler_)
	local startpoint = self:GetCoordinate()
	local roadpoint = startpoint:GetClosestPointToRoad()
	local endpoint = zone:GetRandomCoordinate(inner, outer,{land.SurfaceType.LAND, land.SurfaceType.ROAD})

	local nextWaypointTask = self:TaskFunction("FMS.ConvoyHandlerAdapter", handler_)

	local route = {}
	local startwpt = startpoint:WaypointGround(30,AI.Task.VehicleFormation.OFF_ROAD)
	local roadwpt = roadpoint:WaypointGround(30,AI.Task.VehicleFormation.ON_ROAD)
	local endwpt = endpoint:WaypointGround(30,AI.Task.VehicleFormation.ON_ROAD, {nextWaypointTask})

	route[#route+1] = startwpt
	route[#route+1] = roadwpt
	route[#route+1] = endwpt
	self:Route(route)
end







FMS.IED = {
	TriggeringGroups = nil,
	Count = 1
}
FMS.IED.__index = FMS.IED

function FMS.IED.NewSpawnInZones(iedGroupNames, iedZones)
	local alias = "ied_"..tostring(FMS.IED.Count)
	FMS.IED.Count=FMS.IED.Count+1
	return SPAWN:NewWithAlias(iedGroupNames[1], alias)
		:InitRandomizeTemplate(iedGroupNames)
		:InitRandomizeZones(iedZones)
		:InitHeading(0,359)
		:OnSpawnGroup(function(iedGroup) FMS.IED:New(iedGroup) end)
end

function FMS.IED:New(iedGroup, radius_)

	if not FMS.IED.TriggeringGroups then
		FMS.IED.TriggeringGroups = SET_GROUP:New()
			:FilterCoalitions("blue")
			:FilterAlive()
			-- :FilterCategories("ground","helicopter")
			:FilterStart()
	end

	local obj = {}
	setmetatable(obj, self)
	obj:_init(iedGroup, radius_)
	return obj
end

function FMS.IED:_init(iedGroup, radius_)
	if not iedGroup then return end

	LOG:Log("Setting up IED group: "..iedGroup:GetName())

	self.iedGroup = iedGroup
	self.name = iedGroup:GetName()
	self.radius = radius_ or 30

	self.zoneName = self.name.."-"..tostring(math.random(1000,9999))
	self.triggerZone = ZONE_GROUP:New(self.zoneName, self.iedGroup, self.radius)
	self.triggerZone:Trigger(FMS.IED.TriggeringGroups)
	
	self:_setupEvents()
end

function FMS.IED:_setupEvents()

	local _self = self
	function _self.triggerZone:OnAfterEnteredZone(from, event, to, group)
		LOG:Log("Something entered trigger zone")
		if _self.iedGroup:IsAlive() then
			local gname = group:GetName()
			local zname = _self.zoneName
			if group:IsGround() then
				local delay = math.random(1,15)
				LOG:Log("Target group "..gname.." has entered IED zone "..zname..". Triggering explosion in "..tostring(delay).." seconds.")
				TIMER:New(FMS.IED.explode, _self):Start(delay)
			elseif group:IsAir() then
				LOG:Log("Target group "..gname.." has entered IED zone "..zname..". Performing inspection.")
				_self:inspect()
			else
				LOG:Log("Target group "..gname.." has entered IED zone "..zname..". Unknown category.")
			end			
		-- else
		-- 	LOG:Log("Target group has entered an inactive IED zone. Supressing explosion.")
		-- 	_self:cleanup()
		end
	end

	_self.iedGroup:HandleEvent(EVENTS.Dead)

	function _self.iedGroup:OnEventDead( EventData )
		LOG:Log("iedGroup ".._self.name.." onEventDead()")
		if EventData.IniGroup == _self.iedGroup then
			if not EventData.IniGroup:IsAlive() then
				LOG:Log("GROUP DEAD: " .. iedGroup:GetName())
				-- explode() -- At this point, we can't get the group's coordinate.
				_self:cleanup()
			end
		end
	end
end

function FMS.IED:radioMessage(txt, sound)
	MESSAGE:New(txt, 30):ToAll()
end

function FMS.IED:inspect(iedChance_)
	LOG:Log("Calling IED.INSPECT for "..self.name)

	self:radioMessage("Close inspection of suspected IED initiated.")

	local roll = math.random()
	if roll <= (iedChance_ or 0.5) then
		local observationDelay = math.random(10,30)
		TIMER:New(function()
			self:radioMessage("Explosives detected! Clear the area!")
			TIMER:New(explode):Start(10)
		end):Start(observationDelay)
	else
		TIMER:New(function()
			self:radioMessage("No threats observed.")
			cleanup()
		end):Start(30)
	end
	
end

function FMS.IED:explode(power_)
	local power = power_ or math.random(500,1000)
	LOG:Log("Calling IED.EXPLODE for "..self.name.." with power "..tostring(power))

	local coord = self.iedGroup:GetCoordinate()
	if coord then
		coord:Explosion(power)
		FMS.PrettyExplosion(coord)
		self:radioMessage("... freakin' hit!...MSR...need CASEVAC...")
	end

	self:cleanup()
end

function FMS.IED:cleanup()
	LOG:Log("Calling IED.CLEANUP for "..self.name)
	self.triggerZone:__TriggerStop(1)
	self.iedGroup:UnHandleEvent(EVENTS.Dead)
end
