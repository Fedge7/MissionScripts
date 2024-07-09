--[[
FMS Air Range Script
Author: Fedge

Description:
	This script allows a mission designer to easily setup an "Air Range" that allows a pilot to spawn a formation of
	enemy air adversaries that will engage the player. Menu entries are added that allow the player to choose the
	number of units in the formation, the formation type, and other parameters.  This script automatically handles
	despawning adversaries that wander out of the defined air range zone.

	Create a new air range using FMS.AirRange:New(), passing the name of the zone that defines the range, the name of
	the zone that defines the spawn point for adversaries, and the name of the zone that specifies the "fly to"
	waypoint for adversaries. Then call addGroupTemplate() to add an adversary to the range.

Modifications:
	- v0.1    Fedge            Port of Fedge's original script.
	- v0.2    Fedge            Waypoint zone name is now optional.
	- v0.3    Fedge            Range can now be automatically drawn on the F10 map.
	- v0.4    Fedge            AirRange can now be constructed from COORDINATEs.
	- v0.5    Fedge            Spawn altitude is now settable through the player menu.

TODO:
	- Autoscan for zones prefixed with `FMSAirRangeSpawn` and `FMSAirRangeWP`

]]

if FMS == nil then FMS = {} end
FMS.AirRange = {}

function FMS.AirRange.Init(parentMenu)
	FMS.AirRange.MainMenu = MENU_MISSION:New("Air-to-Air Ranges", parentMenu)
end

--- Constructs an AirRange from a zones defined in the mission editor
-- @param #string zoneName The name of the zone in the ME that defines the air range.
-- @param #string spawnZoneName The name of the zone in the ME that defines where the adversaries spawn.
-- @param #string waypointZoneName_ The name of the zone in the ME that establishes the adversaries' initial heading. Optional.
-- @param #string menuName_ The name of the range as it will appear in the menu system. Optional, defaults to the zone name.
-- @return The newly constructed AirRange object
function FMS.AirRange:New(zoneName, spawnZoneName, waypointZoneName_, menuName_)
	local obj = {}
	setmetatable(obj, self)
	self.__index = self

	obj:_initWithNames(zoneName, spawnZoneName, waypointZoneName_, menuName_)

	return obj
end

--- Constructs an AirRange from an array of COORDINATE defining the zone
-- @param #string rangeName The name of the range as it will appear in the menu system.
-- @param #COORDINATE rangeCoordinates The COORDINATE object that defines the bounds of the air range.
-- @param #COORDINATE spawnCoordinate The COORDINATE object that defines where the adversaries spawn.
-- @param #COORDINATE waypointCoordinate_ The COORDINATE object that establishes the adversaries' initial heading. Optional.
-- @return The newly constructed AirRange object
function FMS.AirRange:NewFromCoordinates(rangeName, rangeCoordinates, spawnCoordinate, waypointCoordinate_)
	local obj = {}
	setmetatable(obj, self)
	self.__index = self

	obj.name = rangeName
	obj:_initLogging()

	function mapVec2(ctbl)
		local vec2s = {}
		for k,coord in pairs(ctbl) do vec2s[k] = coord:GetVec2() end
		return vec2s
	end

	local zone = ZONE_POLYGON_BASE:New(rangeName, mapVec2(rangeCoordinates))
	local spawnVec2 = spawnCoordinate:GetVec2()
	local waypointVec2 = nil
	if waypointCoordinate_ then waypointVec2 = waypointCoordinate_:GetVec2() end

	obj:_init(zone, spawnVec2, waypointVec2)
	return obj
end

function FMS.AirRange:_initLogging()
	local name = self.name or "no-name"
	-- Setup convenience logging
	self.logObj = LOG:New("AirRange|" .. name)
	function FMS.AirRange:log(msg, lvl) self.logObj:log(msg, lvl) end
	function FMS.AirRange:msg(msg, lvl) self.logObj:msg(msg, lvl) end

	self:log("Initializing Air Range: "..name)
end

function FMS.AirRange:_initWithNames(zoneName, spawnZoneName, waypointZoneName_, menuName_)
	--- The name of the BVR Range
	self.name = menuName_ or zoneName

	self:_initLogging()

	local initFail = false
	function getZoneNamed(_zone_name)
		-- TODO: Should this be ZONE:New, or some sort of ZONE:FindByName?
		local z = ZONE:New(_zone_name)
		if z == nil then
			self:log("Unable to find zone '" .. _zone_name .. "'", LOG.Level.ERROR)
			initFail = true
			return nil
		else return z 
		end
	end

	local zone = getZoneNamed(zoneName)
	local spawnVec2 = getZoneNamed(spawnZoneName):GetVec2()
	local waypointVec2 = getZoneNamed(waypointZoneName_ or zoneName):GetVec2()
	
	if initFail then return end
	
	self:_init(zone, spawnVec2, waypointVec2)
end

function FMS.AirRange:_init(rangeZone, spawnVec2, waypointVec2_)
	
	self.zone = rangeZone
	self.spawnVec2 = spawnVec2
	self.waypointVec2 = (waypointVec2_ or rangeZone:GetVec2())
	self.spawns = {}

	-- Indicates that the BVR range is active/hot
	self.active = false

	if not FMS.AirRange.MainMenu then
		FMS.AirRange.Init()
	end

	self.rangeMenu = MENU_MISSION:New(self.name, FMS.AirRange.MainMenu)
	self.spawnMenu = MENU_MISSION:New("Spawn Group", self.rangeMenu)
	
	local confirmDestroy = MENU_MISSION:New("Destroy all adversaries", self.rangeMenu)
	MENU_MISSION_COMMAND:New("Nevermind", confirmDestroy)
	MENU_MISSION_COMMAND:New("Confirm Destroy All", confirmDestroy, FMS.AirRange.destroyAllAdversaries, self)

	local altMenu = MENU_MISSION:New("Set Altitude", self.rangeMenu)

	function setAltitudeFt(alt_ft) self.spawnAltitude = alt_ft * 0.3048 end
	MENU_MISSION_COMMAND:New( "5,000 ft", altMenu, setAltitudeFt,  5000)
	MENU_MISSION_COMMAND:New("10,000 ft", altMenu, setAltitudeFt, 10000)
	MENU_MISSION_COMMAND:New("15,000 ft", altMenu, setAltitudeFt, 15000)
	MENU_MISSION_COMMAND:New("20,000 ft", altMenu, setAltitudeFt, 20000)
	MENU_MISSION_COMMAND:New("25,000 ft", altMenu, setAltitudeFt, 25000)
	MENU_MISSION_COMMAND:New("30,000 ft", altMenu, setAltitudeFt, 30000)
	setAltitudeFt(15000)

	-- Look for and destroy leakers periodically
	SCHEDULER:New(self, FMS.AirRange._destroyAllLeakers, {}, 60, 60)
	
	self:drawOnMap()

	self:log("Air Range initialization complete: "..self.name)
end

--- Draws the bounds of this AirRange as a box on the F10 map.
function FMS.AirRange:drawOnMap()
	local coa = -1
	local red = {1,0,0}
	local white = {1,1,1}
	local alpha = 0.10
	local linetype = 2
	local coord = self.zone:GetCoordinate()
	local fontSize = 12

	self.zone:DrawZone(coa, red, 1, red, alpha, linetype)
	coord:TextToAll(self.name, coa, red, 1, white, 0.3, fontSize)
end

--- Adds a group template the list of spawnable aircraft for this AirRange.
-- @param #string groupTemplateName The name of the group, as defined in the ME.
-- @param #string menuName_ The name of the group as it will appear in the menu. Optional, defaults to the group name.
function FMS.AirRange:addGroupTemplate(groupTemplateName, menuName_)
	if not GROUP:FindByName(groupTemplateName) then
		self:log("Could not find group template named '" .. groupTemplateName or "nil" .. "'", LOG.Level.WARNING)
		return
	end
	
	self:log("Adding group template '" .. groupTemplateName .. "'", LOG.Level.DEBUG)
	
	local spawnObj = SPAWN:New(groupTemplateName)
	table.insert(self.spawns, spawnObj)
	
	local _menuName = menuName_ or groupTemplateName
	local groupMenu = MENU_MISSION:New(_menuName, self.spawnMenu)
	for i=1,4 do
		MENU_MISSION_COMMAND:New("Spawn " .. _menuName .. " x" .. i, groupMenu, FMS.AirRange._spawn, self, spawnObj, i)
	end
end

function FMS.AirRange:destroyAllAdversaries()
	for i,spawnObj in pairs(self.spawns) do    
		local group, index = spawnObj:GetFirstAliveGroup()
		while group ~= nil do
			self:log("Destroying group '" .. group:GetName() .. "'")
			group:Destroy(true)

			group, index = spawnObj:GetNextAliveGroup(index)
		end
	end
	
	-- Range is cold until the next spawn
	self.active = false
end

function FMS.AirRange:_destroyAllLeakers()

	if not self.active then return end

	for i,spawnObj in pairs(self.spawns) do    
		local group, index = spawnObj:GetFirstAliveGroup()
		while group ~= nil do
		
			if group:IsNotInZone(self.zone) then
				self:log("Destroying leaker group '" .. group:GetName() .. "'")
				group:Destroy(true)
			end

			group, index = spawnObj:GetNextAliveGroup(index)
		end
	end
end

--- Helper function that does the actual spawning
function FMS.AirRange:_spawn(spawnObj, unitCount)

	-- spawned group's altitude and speed
	local spawnAltitude = self.spawnAltitude or 4000 --meters
	local speed = 650  --km/hr
	local engageRadius = 90000 --meters
	local capOrbitAltitude = spawnAltitude / 0.3048 --feet

	-- Do the math for adversary's spawn location and initial heading
	local spawnCoord = COORDINATE:NewFromVec2(self.spawnVec2)
	local wpCoord = COORDINATE:NewFromVec2(self.waypointVec2)
	spawnCoord.y = spawnAltitude
	wpCoord.y = spawnAltitude
	local heading = COORDINATE:GetAngleDegrees(spawnCoord:GetDirectionVec3(wpCoord))
	

	-- Configure the spawner
	spawnObj:InitGrouping(unitCount)
	spawnObj:InitHeading(heading)
	spawnObj:OnSpawnGroup(
		function(_spawnedGroup)
			self:msg("BVR Adversary '" .. _spawnedGroup:GetName() .."' spawned")

			-- Set the group's formation
			-- _spawnedGroup:SetOption(AI.Option.Air.id.FORMATION, 196610)
			
			FLIGHTGROUP:New(_spawnedGroup)
				:AddMission(AUFTRAG:NewCAP(self.zone, capOrbitAltitude, speed))
			
		end
	)
	
	spawnObj:SpawnFromCoordinate(spawnCoord)
	
	-- Range is hot
	self.active = true
	
end
