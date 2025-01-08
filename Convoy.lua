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
		-- self.menuSpawn = MENU_MISSION_COMMAND:New("Spawn", self.menu, FMS.Convoy.spawn, self)
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

		if startNow_ then
			self:_start(grp)
		end

		local msg = "Convoy '"..self.missionName.."' ready to move.\nCurrent pos: "..grp:GetCoordinate():ToStringMGRS()
		msg = msg.."\nDestination: "..self.endCoord:ToStringMGRS()
		
		MESSAGE:New(msg, 30):ToAll()

		if self.showInMenu then
			self.menuSpawn:Remove()
			
			if not startNow_ then
				self.menuStart = MENU_MISSION_COMMAND:New("Start", self.menu, FMS.Convoy._start, self, grp)
			end

			self.menuHold = MENU_MISSION_COMMAND:New("Hold", self.menu, CONTROLLABLE.RouteStop, grp)
			self.menuResume = MENU_MISSION_COMMAND:New("Resume", self.menu, CONTROLLABLE.RouteResume, grp)
			self.menuHoldFire = MENU_MISSION_COMMAND:New("ROE Hold", self.menu, CONTROLLABLE.OptionROEHoldFire, grp)
			self.menuEngage = MENU_MISSION_COMMAND:New("ROE Free", self.menu, CONTROLLABLE.OptionROEOpenFire, grp)
			self.menuPositionCheck = MENU_MISSION_COMMAND:New("Position Check", self.menu, FMS.Convoy.showPosition, self, grp)
		end

		-- TIMER:New(function()
		-- 	LOG:Log("Convoy")
		-- 	LOG:Log(" - Alive="..tostring(grp:IsAlive()))
		-- 	LOG:Log(" - Life= "..tostring(grp:GetLife()))
		-- end):Start(nil, 10) 

	end)

	if self.startCoord then
		self.spawner:SpawnFromCoordinate(self.startCoord)
	else
		self.spawner:Spawn()
	end
end

function FMS.Convoy:_start(spawnedGroup)
	spawnedGroup:RouteGroundOnRoad(self.endCoord, nil, nil, AI.Task.VehicleFormation.ON_ROAD)
	
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


FMS.Convoy.IEDTriggeringGroups = SET_GROUP:New()
		:FilterCoalitions("blue")
		:FilterAlive()
		:FilterCategories("ground","helicopter")
		:FilterStart()

function FMS.Convoy.MakeIED(iedGroup, radius_)
	if not iedGroup then return end

	LOG:Log("Setting up IED group: "..iedGroup:GetName())

	local name = iedGroup:GetName()
	local zoneName = name.."-"..tostring(math.random(1000,9999))
	local triggerZone = ZONE_GROUP:New(zoneName, iedGroup, (radius_ or 30))
	triggerZone:Trigger(FMS.Convoy.IEDTriggeringGroups)

	local function cleanup()
		LOG:Log("Calling cleanup for IED:"..name)
		triggerZone:__TriggerStop(1)
		iedGroup:UnHandleEvent(EVENTS.Dead)
	end

	local function explode(power_)
		local power = power_ or math.random(500,1000)
		LOG:Log("Calling explode for "..name.." with power "..tostring(power))

		local coord = iedGroup:GetCoordinate()
		if coord then
			coord:Explosion(power)
			FMS.PrettyExplosion(coord)
		end

		cleanup()
	end

	function triggerZone:OnAfterEnteredZone(from, event, to, group)
		if iedGroup:IsAlive() then
			local delay = math.random(1,15)
			LOG:Log("Target group "..group:GetName().." has entered IED zone "..zoneName..". Triggering explosion in "..tostring(delay).." seconds.")
			TIMER:New(explode):Start(delay)
		-- else
		-- 	LOG:Log("Target group has entered an inactive IED zone. Supressing explosion.")
		-- 	cleanup()
		end
	end

	iedGroup:HandleEvent(EVENTS.Dead)

	function iedGroup:OnEventDead( EventData )
		LOG:Log("iedGroup "..name.." onEventDead()")
		if EventData.IniGroup == iedGroup then
			if not EventData.IniGroup:IsAlive() then
				LOG:Log("GROUP DEAD: " .. iedGroup:GetName())
				-- explode() -- At this point, we can't get the group's coordinate.
				cleanup()
			end
		end
	end

end

function FMS.Convoy.MakeIEDSpawnerInZones(iedGroupNames, iedZones, iedChance_)
	return SPAWN:New(iedGroupNames[1])
		:InitRandomizeTemplate(iedGroupNames)
		:InitRandomizeZones(iedZones)
		:InitHeading(0,359)
		:OnSpawnGroup(function(iedGroup)
			local roll = math.random()
			if roll <= (iedChance_ or 1.0) then
				FMS.Convoy.MakeIED(iedGroup)
			end
		end)
end