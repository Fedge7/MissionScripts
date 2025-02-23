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
	local radius = 50
	self.endZone = ZONE_RADIUS:New(self.missionName.."_goalzone", destination:GetVec2(), radius)
end

function FMS.Convoy:setZones(startZone, endZone)
	self.startCoord = startZone:GetCoordinate()
	self.endCoord = endZone:GetCoordinate()
	self.endZone = endZone
end

function FMS.Convoy:setCSAR(csar)
	self.csar = csar
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
			self:setupControlMenusForGroup(grp)
		end

		local _self = self

		self.endZone:SetCheckTime(30)
		self.endZone:Trigger(grp)
		function _self.endZone:OnAfterEnteredZone(from, event, to, group)
			-- TODO: is group == grp
			_self:success()
		end	

		grp:HandleEvent(EVENTS.Dead)

		function grp:OnEventDead( EventData )
			-- LOG:Log("Convoy Group "..EventData.IniGroup:GetName().." onEventDead()")
			if EventData.IniGroup == grp then
				if _self.csar then
					-- TODO: Play radio sound
					local crd = EventData.IniUnit:GetCoordinate()
					_self.csar:SpawnCASEVAC(crd or grp:GetCoordinate(), coalition.side.BLUE, "Convoy Hit!", false, _self.missionName) 
				end
				FMS.CallHandler(_self._onDeathHandler, self, EventData)
				if not EventData.IniGroup:IsAlive() then
					LOG:Log("CONVOY GROUP DEAD: " .. EventData.IniGroup:GetName())
					grp:UnHandleEvent(EVENTS.Dead)
					_self:failure()
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

function FMS.Convoy:setupControlMenusForGroup(grp)
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
	spawnedGroup:RouteGroundOnRoad(self.endCoord, nil, nil, AI.Task.VehicleFormation.ON_ROAD, FMS.Convoy.WaypointFunction, {self})
	
	self.endZone:DrawZone()

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

function FMS.Convoy.WaypointFunction(controllable, wptIndex, wptCount, convoy)
	LOG:Log("Convoy group "..controllable:GetName().." passing waypoint "..tostring(wptIndex).." of "..tostring(wptCount))
	-- if wptIndex >= wptCount and convoy then
	-- 	convoy:success()
	-- end
end

function FMS.Convoy:success()
	local msg = "Convoy '"..self.missionName.."' has reached its destination."
	MESSAGE:New(msg, 30):ToAll()
	LOG:Log(msg)

	self:cleanup()

	FMS.CallHandler(self._onSuccessHandler, self)
end

function FMS.Convoy:failure()
	local msg = "Convoy '"..self.missionName.."' has failed to reach its destination."
	MESSAGE:New(msg, 30):ToAll()
	LOG:Log(msg)

	self:cleanup()

	FMS.CallHandler(self._onFailureHandler, self)	
end

function FMS.Convoy:cleanup()
	-- TODO: Despawn group?
	self:resetMenus()
	self.endZone:__TriggerStop(5)
	self.endZone:UndrawZone()
end

function FMS.Convoy:onDeath(handler)
	self._onDeathHandler = handler
end

function FMS.Convoy:onSuccess(handler)
	self._onSuccessHandler = handler
end

function FMS.Convoy:onFailure(handler)
	self._onFailureHandler = handler
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

function FMS.IED.NewSpawnInZones(iedGroupNames, iedZones, chance_)
	local alias = "ied_"..tostring(FMS.IED.Count)
	FMS.IED.Count=FMS.IED.Count+1
	return SPAWN:NewWithAlias(iedGroupNames[1], alias)
		:InitRandomizeTemplate(iedGroupNames)
		:InitRandomizeZones(iedZones)
		:InitHeading(0,359)
		:OnSpawnGroup(function(iedGroup) FMS.IED:New(iedGroup, nil, chance_) end)
end

function FMS.IED:New(iedGroup, radius_, chance_)

	-- if not FMS.IED.TriggeringGroups then
	-- 	LOG:Log("Constructing FMS.IED.TriggeringGroups")
	-- 	FMS.IED.TriggeringGroups = SET_GROUP:New()
	-- 		:FilterCoalitions("blue")
	-- 		:FilterAlive()
	-- 		-- :FilterCategories("ground","helicopter")
	-- 		:FilterStart()
	-- end

	local obj = {}
	setmetatable(obj, self)
	obj:_init(iedGroup, radius_, chance_)
	return obj
end

function FMS.IED:_init(iedGroup, radius_, chance_)
	if not iedGroup then return end

	self.iedGroup = iedGroup
	self.name = iedGroup:GetName()
	self.radius = radius_ or 30
	self.armed = math.random() <= (chance_ or 0.5)
	self.inspectionAltitudeLimit = 50

	-- How long an inspection takes
	self.minimumInspectionTime = 10
	self.maximumInspectionTime = 30

	-- How long the explosion delay is when inspecting
	self.minimumExplosionDelay = 5
	self.maximumExplosionDelay = 15

	self.zoneName = self.name.."-"..tostring(math.random(1000,9999))
	self.triggerZone = ZONE_GROUP:New(self.zoneName, self.iedGroup, self.radius)
	-- self.triggerZone:Trigger(FMS.IED.TriggeringGroups)
	
	local armStatus = self.armed and "ARMED" or "safed"
	local mgrsCoord = self.triggerZone:GetCoordinate():ToStringMGRS()
	LOG:Log("IED group '"..iedGroup:GetName().."'  "..mgrsCoord.."  "..armStatus.."  "..iedGroup:GetTypeName())

	self:_setupEvents()
	self:_startScanningForTriggeringUnits()
end

function FMS.IED:_setupEvents()

	local _self = self
	-- function _self.triggerZone:OnAfterEnteredZone(from, event, to, group)
	-- 	_self:targetInZone(group)
	-- end

	_self.iedGroup:HandleEvent(EVENTS.Dead)

	function _self.iedGroup:OnEventDead( EventData )
		LOG:Log("iedGroup ".._self.name.." onEventDead()")
		if EventData.IniGroup == _self.iedGroup then
			if not EventData.IniGroup:IsAlive() then
				LOG:Log("GROUP DEAD: " .. _self.iedGroup:GetName())
				-- explode() -- At this point, we can't get the group's coordinate.
				_self:cleanup()
			end
		end
	end

	_self.iedGroup:HandleEvent(EVENTS.Hit)

	function _self.iedGroup:OnEventHit( EventData )
		LOG:Log("iedGroup "..EventData.IniGroup:GetName().." onEventHit()")
		if _self.armed then
			_self:explode()
		else
			-- _self:radioMessage("CEASE FIRE! You've engaged a non-hostile!")
			_self.iedGroup:UnHandleEvent(EVENTS.Hit)
		end
	end
end

function FMS.IED:_startScanningForTriggeringUnits()
	local triggeringCategories = { Unit.Category.HELICOPTER, Unit.Category.GROUND_UNIT }
	
	self.triggerTimer = TIMER:New(function()
		self.triggerZone:Scan(Object.Category.UNIT, triggeringCategories)
		local inZone = self.triggerZone:IsSomeInZoneOfCoalition(coalition.side.BLUE)
		if inZone then
			LOG:Log(self.zoneName.." - blue coalition in zone.")

			local inTriggerZoneSetBlue = self.triggerZone:GetScannedSetUnit()
				:FilterCoalitions("blue")
				:FilterZones({self.triggerZone})
				:FilterOnce()

			-- LOG:Log("Unit Count = "..tostring(inTriggerZoneSetBlue:Count()))

			-- inTriggerZoneSetBlue:ForEachUnit(function(unit)
			-- 	LOG:Log("Unit="..unit:GetName())
			-- 	LOG:Log("     "..unit:GetCoalitionName())
			-- end)

			-- inTriggerZoneSetBlue:ForEachUnitCompletelyInZone(self.triggerZone, function(unit)
			-- 	LOG:Log("UnitInZone="..unit:GetName())
			-- 	LOG:Log("           "..unit:GetCoalitionName())
			-- end)

			local triggeringUnit = inTriggerZoneSetBlue:GetFirst()
			-- LOG:Log("triggeringUnit="..tostring(triggeringUnit))

			if triggeringUnit then self:targetInZone(triggeringUnit) end
		end
	end)

	-- Stagger the start times so they don't all poll at exactly the same time.
	local startTime = math.random(5,25)--seconds
	local pollingTime = 10--seconds
	self.triggerTimer:Start(startTime, pollingTime)
end

function FMS.IED:targetInZone(group)
	LOG:Log("Something entered trigger zone "..self.zoneName)
	
	self.triggerTimer:Stop()

	if self.iedGroup:IsAlive() then
		local gname = group:GetName()
		local zname = self.zoneName
		
		local closeElevation = math.abs(self.iedGroup:GetHeight() - group:GetHeight()) < self.inspectionAltitudeLimit
		local canInspect = group:IsAir() or group:IsPlayer()

		if closeElevation and canInspect then
			LOG:Log("Target inspecting group '"..gname.."'' has entered IED zone "..zname..". Performing inspection.")
			self:inspect()
		elseif group:IsGround() then
			if self.armed then
				local delay = math.random(1,15)
				local explPower = math.random(200,800)
				LOG:Log("Target ground group '"..gname.."'' has entered IED zone "..zname..". Triggering explosion in "..tostring(delay).." seconds.")
				TIMER:New(FMS.IED.explode, self, explPower):Start(delay)
			else
				LOG:Log("Target ground group '"..gname.."'' has entered an uninspected, unarmed IED zone: "..zname..".")	
			end
		else
			LOG:Log("Target group '"..gname.."'' has entered IED zone "..zname..". Not a ground unit. CloseElevation?="..tostring(closeElevation)..".  CanInspect?="..tostring(canInspect))
		end			
	-- else
	-- 	LOG:Log("Target group has entered an inactive IED zone. Supressing explosion.")
	-- 	self:cleanup()
	end
end

function FMS.IED:radioMessage(txt, sound)
	MESSAGE:New(txt, 30):ToAll()
	if sound then
		USERSOUND:New(sound):ToAll()
	end
end

function FMS.IED:inspect()
	LOG:Log("Calling IED.INSPECT for "..self.name)

	local yellow = {1,1,0}
	self.triggerZone:DrawZone(nil, yellow, 1.0, yellow, 0.3, 5)
	self:radioMessage("Close inspection of suspected IED initiated.", "ied_inspect.ogg")

	if self.armed then
		self:inspectArmed()
	else
		TIMER:New(FMS.IED.noThreat, self):Start(self.maximumInspectionTime)
	end
	
end

function FMS.IED:inspectArmed()
	-- local observeChance = 0.5
	-- local canObserve = math.random() <= observeChance
	-- if canObserve then
		local observationDelay = math.random(self.minimumInspectionTime, self.maximumInspectionTime)
		TIMER:New(FMS.IED.threatDetected, self):Start(observationDelay)
	-- else
	-- 	TIMER:New(FMS.IED.threatUndetermined, self):Start(self.maximumInspectionTime)
	-- end
end

function FMS.IED:threatDetected()
	local red = {1,0,0}
	self.triggerZone:UndrawZone()
	self.triggerZone:DrawZone(nil, red, 1.0, red, 0.5, 6)

	local explDelay = math.random(self.minimumExplosionDelay, self.maximumExplosionDelay)
	local explPower = math.random(100,400)
	self:radioMessage("IED Confirmed! Get the hell outta here!", "ied_confirmed.ogg")
	TIMER:New(FMS.IED.explode, self, explPower):Start(explDelay)
end

function FMS.IED:threatUndetermined()
	self:radioMessage("Unable to determine IED threat. Use extreme caution.")
end

function FMS.IED:noThreat()
	self:radioMessage("Area's clear. Continue Mission.", "ied_area_clear.ogg")

	local green = {0,1,0}
	self.triggerZone:UndrawZone()
	self.triggerZone:DrawZone(nil, green, 1.0, green, 0.3, 1)
	
	self:cleanup()
end

function FMS.IED:explode(power_)
	local power = power_ or math.random(100,500)
	LOG:Log("Calling IED.EXPLODE for "..self.name.." with power "..tostring(power))

	local coord = self.iedGroup:GetCoordinate()
	if coord then
		coord:Explosion(power)
		FMS.PrettyExplosion(coord)
	end

	self:cleanup()
end

function FMS.IED:cleanup()
	LOG:Log("Calling IED.CLEANUP for "..self.name)
	-- self.triggerZone:__TriggerStop(1)
	-- self.triggerTimer:Stop() -- handled in targetInZone()
	self.iedGroup:UnHandleEvent(EVENTS.Dead)
	self.iedGroup:UnHandleEvent(EVENTS.Hit)
end
