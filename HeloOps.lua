--[[
FMS Helicopter Operations Script
Author: Fedge

Description:
	This script allows a mission designer to quickly setup a CTLD and CSAR instance.

Modifications:
	- v0.1    Fedge            Port of Fedge's original script.
	- v0.3    Fedge            Added FARP building functionality to CTLD.
	- v0.4    Fedge            Added more robust error handling and reporting.
	- v0.5    Fedge            Logging utilities. Separates FARP configuration out of this file.
	- v0.6    Fedge            Adds support for loading standard troops/vehicles via STM file.
	- v0.7    Fedge            Adds support for CTLD:onTroopsDeployed() function for easier callbacks
	- v1.0    Fedge            Cleanup.

TODO:
	- CSAR random missions
]]

local version = "v1.0"
local logPrefix = "FMS.HeloOps"

env.info("FMS.HeloOps " .. version .. " loading.")

if FMS == nil then FMS = {} end

FMS.HeloOps = {

	-- These parameters are set throughout the initialization of the FMS CTLD instance
	Error = {
		MissingTroops = 0,    -- count of troop templates that weren't found in the mission
		MissingVehicles = 0,  -- count of vehicle templates that weren't found in the mission
		MissingCrates = 0,    -- count of crate static templates that weren't found in the mission
		MissingFARP = 0   -- indicates the group template used to spawn the FARP wasn't found in the mission
	},

	-- Utility logging functions. Call `FMS.HeloOps.Log.info/warning/error`
	Log = {
		logenv =  function(msg, pri, category)
			local _msg = logPrefix
			if category ~= nil then _msg = _msg .. "|" .. category end
			_msg = _msg .. ": " .. msg
			if     0==pri then env.info(_msg)
			elseif 1==pri then env.warning(_msg)
			elseif 2==pri then env.error(_msg)
			end
		end,
		info =    function(msg, category) FMS.HeloOps.Log.logenv(msg, 0, category) end,
		warning = function(msg, category) FMS.HeloOps.Log.logenv(msg, 1, category) end,
		error =   function(msg, category) FMS.HeloOps.Log.logenv(msg, 2, category) end
	} 

}

-- Utility logging methods for CTLD
function CTLD:logINF(msg) FMS.HeloOps.Log.info("("..self.alias..") " .. msg, "CTLD") end
function CTLD:logWAR(msg) FMS.HeloOps.Log.warning("("..self.alias..") " .. msg, "CTLD") end
function CTLD:logERR(msg) FMS.HeloOps.Log.error("("..self.alias..") " .. msg, "CTLD") end
function CSAR:logINF(msg) FMS.HeloOps.Log.info("("..self.alias..") " .. msg, "CSAR") end


--- Creates a new CTLD instance
-- @param #string Coalition Coalition of this CTLD. (i.e. coalition.side.BLUE or coalition.side.RED or coalition.side.NEUTRAL)
-- @param #table prefixes Table of pilot prefixes.
-- @param #string alias Alias of this CTLD for logging.
function FMS.HeloOps.NewCTLD(coalitionSide, prefixes, alias, configFunction_)
	
	local _coalition = coalitionSide or coalition.side.BLUE
	local _prefixes = prefixes or {"Rotary"}
	local _alias = alias or "Rotary Corps"
	
	local _ctld_instance = CTLD:New(_coalition, _prefixes, _alias)
	
	FMS.HeloOps.Log.info("New CTLD instance '" .. _ctld_instance.alias .. "' created.", "CTLD")

	function _ctld_instance:OnAfterTroopsDeployed(_from, _event, _to, _group, _unit, _deployedTroops)
		if self.onTroopsDeployed and type(self.onTroopsDeployed) == "function" then
			self:onTroopsDeployed(_deployedTroops)
		end
	end

	if configFunction_ ~= nil then
		configFunction_(_ctld_instance)
	end

	_ctld_instance:__Start(2)
	return _ctld_instance
end

-- -----------------------------------------------------------------------------
-- CTLD
-- -----------------------------------------------------------------------------

--- Adds a group template (or multiple templates) to the "Troops" menu
-- `groupTemplateNames` can be a string, or a table of strings
function CTLD:AddTroopGroups(menuName, groupTemplateNames, troopCount, perTroopMassKg, subCategory)
	
	local function groupExists(grpName)
		if GROUP:FindByName(grpName) then return true
		else
			self:logWAR("Unable to add troops '" .. menuName .. "' (" .. grpName .. ")")
			FMS.HeloOps.Error.MissingTroops = FMS.HeloOps.Error.MissingTroops + 1
			return false
		end
	end

	local groupNames = {}

	-- Check that all the group template(s) exist
	if type(groupTemplateNames) == 'table' then
		for _, grpName in pairs(groupTemplateNames) do
			if not groupExists(grpName) then return end
		end
		groupNames = groupTemplateNames
	elseif type(groupTemplateNames) == 'string' then
		if not groupExists(groupTemplateNames) then return end
		groupNames = {groupTemplateNames}
	end

	self:AddTroopsCargo(menuName, groupNames, CTLD_CARGO.Enum.TROOPS, troopCount, perTroopMassKg, nil, subCategory)
	self:logINF("Added troops '" .. menuName .. "'")
end

--- Adds a vehicle group template (or multiple templates) to the "Crates" menu
function CTLD:AddVehicleGroups(menuName, groupTemplateNames, crateCount, perCrateMassKg)

	local function groupExists(grpName)
		if GROUP:FindByName(grpName) then return true
		else
			self:logWAR("Unable to add troops '" .. menuName .. "' (" .. grpName .. ")")
			FMS.HeloOps.Error.MissingTroops = FMS.HeloOps.Error.MissingVehicles + 1
			return false
		end
	end

	local groupNames = {}

	-- Check that all the group template(s) exist
	if type(groupTemplateNames) == 'table' then
		for _, grpName in pairs(groupTemplateNames) do
			if not groupExists(grpName) then return end
		end
		groupNames = groupTemplateNames
	elseif type(groupTemplateNames) == 'string' then
		if not groupExists(groupTemplateNames) then return end
		groupNames = {groupTemplateNames}
	end
	
	self:AddCratesCargo(menuName, groupNames, CTLD_CARGO.Enum.VEHICLE, crateCount, perCrateMassKg)  
	self:logINF("Added crates/cargo '" .. menuName .. "'")
end

function CTLD:AddFARPCrates(menuName, farpGroupTemplateName, crateCount, perCrateMassKg)
	if not GROUP:FindByName(farpGroupTemplateName) then
		self:logWAR("Unable to add FARP '" .. farpGroupTemplateName .. "'")
		FMS.HeloOps.Error.MissingFARP = FMS.HeloOps.Error.MissingFARP + 1
		return
	end

	self:AddCratesCargo(
		menuName or "FARP",
		{farpGroupTemplateName},
		CTLD_CARGO.Enum.FOB,
		crateCount or 2,
		perCrateMassKg or 1500
		)
	self:logINF("Added FARP crates '" .. farpGroupTemplateName .. "'")
end

--- Automatically scans the mission for logistics zones.
-- Zone name prefixes are "Loadzone" and "Movezone"
function CTLD:ScanForZones()

	self:logINF("Scanning for logistics zones.")

	-- Find and add all loadzones starting with "Loadzone" (e.g. "Loadzone-Anapa")
	local loadzones = SET_ZONE:New():FilterPrefixes('Loadzone'):FilterOnce()
	loadzones:ForEachZone(function(_zone) 
		local zoneName = _zone:GetName()
		self:AddCTLDZone(zoneName, CTLD.CargoZoneType.LOAD, SMOKECOLOR.Blue, true, true)
		self:logINF("Added Load Zone '" .. zoneName .. "'")
	end)
	
	local movezones = SET_ZONE:New():FilterPrefixes('Movezone'):FilterOnce()
	movezones:ForEachZone(function(_zone)
		local zoneName = _zone:GetName()
		self:AddCTLDZone(zoneName, CTLD.CargoZoneType.MOVE, SMOKECOLOR.Orange, true, true)
		self:logINF("Added Move Zone '" .. zoneName .. "'")
	end)

end

FMS.HeloOps.FARP = {
	-- An array of FARP names
	Clearnames = {
		[1]="London",
		[2]="Dallas",
		[3]="Paris",
		[4]="Moscow",
		[5]="Berlin",
		[6]="Rome",
		[7]="Madrid",
		[8]="Warsaw",
		[9]="Dublin",
		[10]="Perth",
	},

	-- The index of the next FARP clearname that will be used
	NameIdx = 1, -- numbers 1..10
	
	-- FARP Radio. First one has 130AM, next 131 and for forth
	Frequency = 130,

	-- Function that gets the "next" FARP in the list
	Next = function()
		local ret = {
			idx=FMS.HeloOps.FARP.NameIdx,
			name=FMS.HeloOps.FARP.Clearnames[FMS.HeloOps.FARP.NameIdx],
			freq=FMS.HeloOps.FARP.Frequency
		}
		FMS.HeloOps.FARP.Frequency = FMS.HeloOps.FARP.Frequency + 1
		FMS.HeloOps.FARP.NameIdx = (FMS.HeloOps.FARP.NameIdx % 10) + 1
		return ret
	end
}

function CTLD:ConfigureFARP(
	FARPTemplateGroupName,    -- the name of the group that acts as a template for FARPs spawned in via the CTLD F10 radio menu
	FarpPadStaticName,        -- the name of the actual FARP static (should be an invisible FARP, FARP T, FARP Helipad, etc)
	FarpTemplateGroupsNames,  -- the names of any additional groups that should be spawned at the FARP
	FarpStaticsNames,         -- the names of any additional statics that should be spawned at the FARP
	LayoutHandler             -- a function that overrides the default layout of the FARP
	)
	
	if STATIC:FindByName(FarpPadStaticName, false) then
		self:logINF("Found FARP static heliport '" .. FarpPadStaticName .. "'")
	else
		local msg = "Unable to find FARP static '" .. (FarpPadStaticName or "_FarpPadStaticName_") .. "'. FARP cannot be constructed."
		self:logERR(msg)
		MESSAGE:New(msg, 15, "HeloOps"):ToAll()
		return
	end

	-- Check that all the group templates exist
	for _,groupName in pairs(FarpTemplateGroupsNames or {}) do
		if GROUP:FindByName(groupName) then
			self:logINF("Found FARP template group '" .. groupName .. "'")
		else
			self:logWAR("Unable to find FARP template group '" .. groupName .. "'")
			FMS.HeloOps.Error.MissingFARP = FMS.HeloOps.Error.MissingFARP + 1
		end
	end

	for _, static in pairs(FarpStaticsNames or {}) do
		if STATIC:FindByName(static, false) then
			self:logINF("Found FARP static '" .. static .. "'")
		else
			self:logWAR("Unable to find FARP static '" .. static .. "'")
			FMS.HeloOps.Error.MissingFARP = FMS.HeloOps.Error.MissingFARP + 1
		end
	end

	local ctld_instance = self

	function BuildAFARP(Coordinate)
		local coord = Coordinate -- Core.Point#COORDINATE

		-- The name of the FARP helipad (needs to be an actual FARP pad)
		local farpPadStaticName = FarpPadStaticName or "Static Invisible FARP-1"

		-- An array of template group names that will be spawned around the FARP
		local farpTemplateGroupsNames = FarpTemplateGroupsNames or {}

		-- A list of statics that will be spawned around the FARP
		local farpStaticsNames = FarpStaticsNames or {"Static FARP Command Post-1"}

		-- Get the parameters for the next available FARP
		local farp = FMS.HeloOps.FARP.Next()

		-- Create a zone for the FARP to spawn within
		local zoneSpawn = ZONE_RADIUS:New("FARP " .. farp.name, Coordinate:GetVec2(), 160, false)
		local Heading = 0

		-- Create a SPAWNSTATIC object from a template static FARP object.
		if not STATIC:FindByName(farpPadStaticName, false) then
			ctld_instance:logERR("Unable to find FARP static '" .. farpPadStaticName .. "'. FARP cannot be constructed.")
			return
		end
		local invisibleFarpSpawn = SPAWNSTATIC:NewFromStatic(farpPadStaticName, country.id.USA)

		-- Spawning FARPs is special in DCS. We need to specify that this is a FARP. We also set the callsign and frequency.
		invisibleFarpSpawn:InitFARP(farp.idx, farp.freq, 0)
		invisibleFarpSpawn:InitDead(false)

		-- Spawn the actual FARP static
		local farpStaticWrapper = invisibleFarpSpawn:SpawnFromZone(zoneSpawn, Heading, "FARP "..farp.name)

		if LayoutHandler ~= nil then
			self:logINF("Calling custom FARP layout handler")
			LayoutHandler(coord, farpTemplateGroupsNames, farpStaticsNames)
		else
			local delta = 360 / (#farpTemplateGroupsNames + #farpStaticsNames) --degrees
			local base = 360 --degrees
			local radius = 80 --meters

			-- Spawn the groups in the first segment of the circle
			for _,groupName in pairs(farpTemplateGroupsNames) do
				if GROUP:FindByName(groupName) then
					local farpVehiclesSpawn = SPAWN:New(groupName)
					-- farpVehiclesSpawn:InitHeading(180)
					farpVehiclesSpawn:SpawnFromCoordinate(coord:Translate(radius, base))
					base = base - delta
				else
					ctld_instance:logWAR("Unable spawn FARP group '" .. groupName .. "'")
				end
			end

			-- Spawn the statics in the second segment of the circle
			for i, static in pairs(farpStaticsNames) do
				if STATIC:FindByName(static, false) then
					local spawn = SPAWNSTATIC:NewFromStatic(static, country.id.USA)
					spawn:SpawnFromCoordinate(coord:Translate(radius, base), Heading)
					base = base - delta
				else
					ctld_instance:logWAR("Unable spawn FARP static '" .. static .. "'")
				end
			end
		end

		-- add a loadzone to CTLD
		ctld_instance:AddCTLDZone("FARP "..farp.name,CTLD.CargoZoneType.LOAD,SMOKECOLOR.Blue,true,true)
		MESSAGE:New(string.format("FARP %s in operation on %d MHz!", farp.name, farp.freq), 15, "HeloOps"):ToBlue()
	end

	-- TODO: This will conflict with any other attempts to respond to `OnAfterCratesBuild`
	function ctld_instance:OnAfterCratesBuild(From, Event, To, Group, Unit, Vehicle)
		local name = Vehicle:GetName()

		-- Handle FARPs/FOBs
		if string.find(name, FARPTemplateGroupName or "FARP", 1, true) then
			local coord = Vehicle:GetCoordinate()
			Vehicle:Destroy(false) -- Remove the group that was "built" from the crate(s)

			-- TODO: Disable custom FARP spawning as a hotfix for DCS FARP Warehouse/Storage changes
			-- BuildAFARP(coord)

			UTILS.SpawnFARPAndFunctionalStatics(FarpPadStaticName, coord, ENUMS.FARPType.INVISIBLE)
			self:logINF("Spawning FARP and Functional Statics. name: '" .. FarpPadStaticName .. "'")
			
			-- TODO: Do we need to make a loadzone?
		end
	end

end

-- PRIVATE INTERFACE -----------------------------------------------------------

function CTLD:_CTLDAddStaticsCargo(groupTemplateName, massKg)
	if not STATIC:FindByName(groupTemplateName, false) then
		self:logWAR("Unable to add static cargo '" .. groupTemplateName .. "'")
		return
	end
	
	self:AddStaticsCargo(groupTemplateName, massKg)
	self:logINF("Added crates/static '" .. groupTemplateName .. "'")
end

-- TODO
function CTLD:ConfigureJTACs()
	function self:OnAfterTroopsDeployed(_from, _event, _to, _group, _unit, _cargoTroops)
		env.info(logPrefix .. ": (" .. self.alias .. "): Dropped Troops")
		env.info("  - Group:" .. _group:GetName())
		env.info("  - Unit: " .. _unit:GetName())
		env.info("  - Troop:" .. _cargoTroops:GetName())
		
		local droppedGroupName = _cargoTroops:GetName()
		if droppedGroupName and string.match(droppedGroupName,"JTAC") then
			-- JTACAutoLase(droppedGroupName, 1688)
			self:logWAR("FMS.HeloOps JTAC functionality not yet available")
		end
	end
end


-- -----------------------------------------------------------------------------
-- CSAR
-- -----------------------------------------------------------------------------

function FMS.HeloOps.NewCSAR(coalitionSide_, alias_, prefixes_, downedPilotGroupTemplateName_, configFunction_)
	--TODO: Use "Carrier LSO 6" as downed pilot model
	
	local _coalition = coalitionSide_ or coalition.side.BLUE
	local _alias = alias_ or "CSAR Corps"
	local _downedPilotGroupTemplateName = downedPilotGroupTemplateName_ or "Downed Pilot"
	
	if not GROUP:FindByName(_downedPilotGroupTemplateName) then
		env.warning(logPrefix .. "|CSAR: cannot initialize CSAR. No group template called \"" .. _downedPilotGroupTemplateName .. "\" found in mission.")
		return
	end
	
	local _csar_instance = CSAR:New(_coalition, _downedPilotGroupTemplateName, _alias)
	env.info(logPrefix .. "|CSAR: New CSAR instance '" .. _csar_instance.alias .. "' created.")

	if prefixes_ then
		_csar_instance:logINF("Restricting " .. _csar_instance.alias .. " to groups named like:")

		_csar_instance.useprefix = true

		if type(prefixes_) == "table" then
			_csar_instance.csarPrefix = prefixes_
		elseif type(prefixes_) == "string" then
			_csar_instance.csarPrefix = {prefixes_}
		end

		for _,pfx in ipairs(_csar_instance.csarPrefix) do _csar_instance:logINF("  - " .. pfx) end
	else
		_csar_instance.useprefix = false
	end

	function _csar_instance:OnAfterPilotDown(from, event, to, spawnedgroup, frequency, groupname, coordinates_text)
		--TODO: Check that this is actually a UH-60 ;)
		USERSOUND:New( "CSAR.ogg" ):ToCoalition( coalition.side.BLUE )
		self:logINF("Spawned downed pilot: " .. groupname)
	end

	if configFunction_ ~= nil then
		configFunction_(_csar_instance)
	end

	_csar_instance:__Start(4)
		
	return _csar_instance
end

FMS.HeloOps.randomNames = {
	"Pete Mitchell", "Tom Kazansky", "Nick Bradshaw", "Mike Metcalf", "Marcus Williams", "Tom Jardian", "Rick Hieatherly", "Ron Kerner", "Rick Neven", "Bill Cortell", "Henry Ruth", "Sam Wells",
	"Beau Simpson", "Jake Seresin", "Chester Cain", "Robert Floyd", "Solomon Bates", "Bernie Coleman", "Reuben Fitch", "Mickey Garcia",
	"Jake Preston", "Brad Little",
	"Charles Sinclair", "Doug Masters",
	"Ted Striker", "Clarence Oveur"
}

function CSAR:SpawnDownedPilotInZone(zoneName, pilotName_)
	local _name = pilotName_
	
	if not _name then
		_name = FMS.HeloOps.randomNames[ math.random( #FMS.HeloOps.randomNames ) ]
	end
	
	self:logINF("Preparing to spawn downed pilot: " .. _name)
	
	self:SpawnCSARAtZone(zoneName, coalition.side.BLUE, _name, true, false, _name, "Aircraft")
end


function CSAR:csarMenuCommand(menuText, zoneName, parentMenu_)
	MENU_MISSION_COMMAND:New(menuText, parentMenu_, CSAR.SpawnDownedPilotInZone, self, zoneName)
end

function CSAR:csarHotLZMenuCommand(menuText, zoneName, parentMenu_)
	MENU_MISSION_COMMAND:New(menuText, parentMenu_, function()
		-- This is a hacky solution that will probably break if csar missions are spawned too close together in time
		self.hotLZ = true
		self:SpawnDownedPilotInZone(zoneName)
	end)
end

function CSAR:casevacMenuCommand(menuText, zoneName, parentMenu_)
	
	function _spawnMedevacInZone(zoneName)
		local coord = COORDINATE:NewFromVec3(ZONE:New(zoneName):GetRandomPointVec3())	
		self:SpawnCASEVAC(coord, coalition.side.BLUE, nil, true)
	end
	
	-- TODO: This is a MENU_MISSION. it should probably be a coalition/group menu.
	MENU_MISSION_COMMAND:New(menuText, parentMenu_, _spawnMedevacInZone, zoneName)

end

function CSAR:initiateRecurringCsarMissionsInZone(zoneName, missionsLimit_, seconds_)
	local dynamicCsarMissionsInZoneLimit = missionsLimit_ or 2
	local timeBetweenSpawns = seconds_ or 3600
	local tmr = TIMER:New(function()
		if self:_CountActiveDownedPilots() < dynamicCsarMissionsInZoneLimit then
			self:SpawnDownedPilotInZone(zoneName)
		end
	end)
	tmr:Start(timeBetweenSpawns, timeBetweenSpawns)
end

function CSAR:handleHotLZ(csarGroup, groupTemplateName)
	self.hotLZ = false

	local pilotBubble = ZONE_GROUP:New("CSAR Hot LZ Zone", csarGroup, 500)
	local enemyGroup = SPAWN:New(groupTemplateName):InitAIOff():SpawnInZone(pilotBubble, true)

	local clients = SET_CLIENT:New():FilterStart()
	local kabukiZone = ZONE_GROUP:New("CSAR Kabuki Zone", csarGroup, 6000)
	kabukiZone:Trigger(clients)
	kabukiZone:__TriggerStop(600)

	function kabukiZone:OnAfterEnteredZone(from, event, to, group)
		env.warning("Activating kabuki theatre for hot LZ mission")
		enemyGroup:SetAIOn()
		kabukiZone:TriggerStop()
		clients:FilterStop()
		clients = nil
	end
end

function FMS.HeloOps.RunBuiltInTest()
	local errorFuse = false
	if FMS.HeloOps.Error.MissingTroops > 0 then
		errorFuse = true
		MESSAGE:New("Missing " .. FMS.HeloOps.Error.MissingTroops .. " troop group templates", 20, "HeloOps|CTLD"):ToAll()
	end
	if FMS.HeloOps.Error.MissingVehicles > 0 then
		errorFuse = true
		MESSAGE:New("Missing " .. FMS.HeloOps.Error.MissingVehicles .. " vehicle group templates", 20, "HeloOps|CTLD"):ToAll()
	end
	if FMS.HeloOps.Error.MissingCrates > 0 then
		errorFuse = true
		MESSAGE:New("Missing " .. FMS.HeloOps.Error.MissingCrates .. " crate static templates", 20, "HeloOps|CTLD"):ToAll()
	end
	if FMS.HeloOps.Error.MissingFARP > 0 then
		errorFuse = true
		MESSAGE:New("Missing " .. FMS.HeloOps.Error.MissingFARP .. " FARP templates", 20, "HeloOps|CTLD"):ToAll()
	end

	if errorFuse then
		env.error("FMS HeloOps CTLD initialization: FAILURE")
	else
		local msg = "FMS HeloOps CTLD initialization: SUCCESS"
		env.info(msg)
		MESSAGE:New(msg):ToAll()
	end
end