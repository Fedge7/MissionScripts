--[[
FMS Helicopter Operations Script
Author: Fedge

Description:
	This script allows a mission designer to quickly setup a CTLD and CSAR instance.

Dependencies:
	- MOOSE
	For STM functions:
	- FMS.Utilities
	- FMS.StaticTemplates

Modifications:
	- v0.1    Fedge            Port of Fedge's original script.
	- v0.3    Fedge            Added FARP building functionality to CTLD.
	- v0.4    Fedge            Added more robust error handling and reporting.
	- v0.5    Fedge            Logging utilities. Separates FARP configuration out of this file.
	- v0.6    Fedge            Adds support for loading standard troops/vehicles via STM file.
	- v0.7    Fedge            Adds support for CTLD:onTroopsDeployed() function for easier callbacks
	- v1.0    Fedge            Cleanup.
	- v2.0    Fedge            Combines HeloOps and HeloOpsConfig scripts.
	- v2.1    Fedge            Bugfix for FARPs. Adds SpawnAndFillSTMFARPAtVec2().

TODO:
	- CSAR random missions
]]

local version = "v2.1"
local logPrefix = "FMS.HeloOps"

env.info("FMS.HeloOps " .. version .. " loading.")

if FMS == nil then FMS = {} end

FMS.HeloOps = {

	-- These parameters are set throughout the initialization of the FMS CTLD instance
	Error = {
		MissingTroops = 0,    -- count of troop templates that weren't found in the mission
		MissingVehicles = 0,  -- count of vehicle templates that weren't found in the mission
		MissingCrates = 0,    -- count of crate static templates that weren't found in the mission
		MissingFARP = 0,      -- indicates the group template used to spawn the FARP wasn't found in the mission
		InitFailure = false,  -- indicates some error occured while initializing CTLD
	},

	-- Utility logging functions. Call `FMS.HeloOps.Log.info/warning/error`
	Log = {
		logenv = function(msg, pri, category)
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
function CTLD:logINF(msg) FMS.HeloOps.Log.info("("..self.alias..") "    .. msg, "CTLD") end
function CTLD:logWAR(msg) FMS.HeloOps.Log.warning("("..self.alias..") " .. msg, "CTLD") end
function CTLD:logERR(msg) FMS.HeloOps.Log.error("("..self.alias..") "   .. msg, "CTLD") end
function CSAR:logINF(msg) FMS.HeloOps.Log.info("("..self.alias..") "    .. msg, "CSAR") end


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
	else
		_ctld_instance:ApplyDefaultConfiguration()
	end

	FMS.DBSpawn(FMS.HeloOps.DownedPilotTemplate, country.id.USA, Group.Category.GROUND)

	_ctld_instance:__Start(2)
	return _ctld_instance
end

-- -----------------------------------------------------------------------------
-- CTLD
-- -----------------------------------------------------------------------------

--- Applies the default configuration options to a CTLD instance
function CTLD:ApplyDefaultConfiguration()
	
	-- Set CTLD config options
	self.useprefix = false                 -- enables *all* coalition choppers to use CTLD. Must be set before Start()
	self.nobuildinloadzones = false        -- forbid players to build stuff in LOAD zones if set to `true`
	self.movecratesbeforebuild = false     -- crates must be moved once before they can be build. Set to false for direct builds.
	self.forcehoverload = false            -- Crates (not: troops) can **only** be loaded while hovering.
	self.maximumHoverHeight = 50           -- Hover max this high to load.
	self.minimumHoverHeight = 5            -- Hover min this low to load. NOTE FROM FEDGE: This must be at least a few meters > 0 for MOOSE to properly detect that a unit is grounded.
	self.dropcratesanywhere = true
	self.cratecountry = country.id.CJTF_BLUE
	self.repairtime = 60                   -- Number of seconds it takes to repair a unit.
	self.buildtime = 60                    -- Number of seconds it takes to build a unit. Set to zero or nil to build instantly.
	self.movetroopstowpzone = true         -- Troops and vehicles will move to the nearest MOVE zone...
	self.movetroopsdistance = 2000         -- .. but only if this far away (in meters)
	self.troopdropzoneradius = 5
	self.usesubcats = false
	--self.pilotmustopendoors = true
	
	-- Set unit capabilities for all helo units
	--                       Airframe          crates troops crates# troops# length maxwt
	self:SetUnitCapabilities("AH-64D_BLK_II",  false, false, 0,       0,     20,     200)
	self:SetUnitCapabilities("UH-60L",          true,  true, 1,      14,     25,    5000)
	self:SetUnitCapabilities("UH-1H",           true,  true, 1,       8,     20,    2000)
	self:SetUnitCapabilities("Mi-8MT",          true,  true, 2,      24,     30,   10000)
	self:SetUnitCapabilities("Mi-8MTV2",        true,  true, 2,      24,     30,   10000)
	self:SetUnitCapabilities("CH-47F",          true,  true, 2,      33,     30,   15000)
	-- Tweaked the max weights to allow for realistic overloading
	
	self:logINF("FMS default CTLD configuration and parameters applied.")
end

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
function CTLD:AddVehicleGroups(menuName, groupTemplateNames, crateCount, perCrateMassKg, subCategory_)

	local function groupExists(grpName)
		if GROUP:FindByName(grpName) then return true
		else
			self:logWAR("Unable to add vehicle '" .. menuName .. "' (" .. grpName .. ")")
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
	
	self:AddCratesCargo(menuName, groupNames, CTLD_CARGO.Enum.VEHICLE, crateCount, perCrateMassKg, nil, subCategory_)  
	self:logINF("Added crates/cargo '" .. menuName .. "' to submenu '"..(subCategory_ or "nil").."'")
end

function CTLD:AddFARPCrates(menuName, farpGroupTemplateName, crateCount_, perCrateMassKg_, subCategory_)
	if not GROUP:FindByName(farpGroupTemplateName) then
		self:logWAR("Unable to add FARP '" .. farpGroupTemplateName .. "'")
		FMS.HeloOps.Error.MissingFARP = FMS.HeloOps.Error.MissingFARP + 1
		return
	end

	self:AddCratesCargo(
		menuName or "FARP",
		{farpGroupTemplateName},
		CTLD_CARGO.Enum.FOB,
		crateCount_ or 2,
		perCrateMassKg_ or 1500,
		nil,
		subCategory_ or nil
		)
	self:logINF("Added FARP crates '" .. farpGroupTemplateName .. "'")
end

function CTLD:AddStandardFARPCrates()
	FMS.DBSpawn(FMS.HeloOps.Hummer, country.id.USA, Group.Category.GROUND)
	self:AddFARPCrates("Standard FARP", FMS.HeloOps.Hummer.name, 2, 1500)
	self:ConfigureFARP(FMS.HeloOps.Hummer.name)
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
		_zone:DrawZone(
			-1,         -- coalition, -1=ALL
			{0, 0.8, 0},    -- Color
			1,          -- Alpha
			{0, 1.0, 0},    -- FillColor
			0.1,        -- FillAlpha
			3           -- LineType, 3=Dotted
		)
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
		[ 1]="London",
		[ 2]="Dallas",
		[ 3]="Paris",
		[ 4]="Moscow",
		[ 5]="Berlin",
		[ 6]="Rome",
		[ 7]="Madrid",
		[ 8]="Warsaw",
		[ 9]="Dublin",
		[10]="Perth",
	},

	-- The index of the next FARP clearname that will be used
	NameIdx = 1, -- numbers 1..10

	-- Monotonically increasing count of spawned FARPs
	Count = 1,
	
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

-- CustomFARP table params:
-- FarpPadStaticName,        -- the name of the actual FARP static (should be an invisible FARP, FARP T, FARP Helipad, etc)
-- FarpTemplateGroupsNames,  -- the names of any additional groups that should be spawned at the FARP
-- FarpStaticsNames,         -- the names of any additional statics that should be spawned at the FARP
-- LayoutHandler             -- a function that overrides the default layout of the FARP
function CTLD:ConfigureFARP(
	FARPTemplateGroupName    -- the name of the group that acts as a placeholder group for FARPs spawned in via the CTLD F10 radio menu
	-- CustomFARP_				  -- a table containing the required elements for a custom FARP.
	)

	if CustomFARP_ then
		if STATIC:FindByName(CustomFARP_.FarpPadStaticName, false) then
			self:logINF("Found FARP static heliport '" .. CustomFARP_.FarpPadStaticName .. "'")
		else
			local msg = "Unable to find custom FARP static '" .. (CustomFARP_.FarpPadStaticName or "_FarpPadStaticName_") .. "'. Building default FARP."
			self:logERR(msg)
		end

		-- Check that all the group templates exist
		for _,groupName in pairs(CustomFARP_.FarpTemplateGroupsNames or {}) do
			if GROUP:FindByName(groupName) then
				self:logINF("Found FARP template group '" .. groupName .. "'")
			else
				self:logWAR("Unable to find FARP template group '" .. groupName .. "'")
				FMS.HeloOps.Error.MissingFARP = FMS.HeloOps.Error.MissingFARP + 1
			end
		end

		for _, static in pairs(CustomFARP_.FarpStaticsNames or {}) do
			if STATIC:FindByName(static, false) then
				self:logINF("Found FARP static '" .. static .. "'")
			else
				self:logWAR("Unable to find FARP static '" .. static .. "'")
				FMS.HeloOps.Error.MissingFARP = FMS.HeloOps.Error.MissingFARP + 1
			end
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

		if CustomFARP_.LayoutHandler ~= nil then
			self:logINF("Calling custom FARP layout handler")
			CustomFARP_.LayoutHandler(coord, farpTemplateGroupsNames, farpStaticsNames)
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
	function ctld_instance:OnAfterCratesBuild(From, Event, To, groupThatBuiltCrates, unitThatBuiltCrates, placeholderGroup)
		-- Handle FARPs/FOBs
		if string.find(placeholderGroup:GetName(), FARPTemplateGroupName or "FARP", 1, true) then
			local coord = placeholderGroup:GetCoordinate()
			placeholderGroup:Destroy(false) -- Remove the group that was "built" from the crate(s)

			-- TODO: Disable custom FARP spawning as a hotfix for DCS FARP Warehouse/Storage changes
			-- BuildAFARP(coord)

			-- Spawn the default MOOSE FARP.
			local newFarpName = "FARP-"..tostring(FMS.HeloOps.FARP.Count)
			local spawnedFarpObjects, adfName = FMS.HeloOps.SpawnFARP({
				Name = newFarpName,
				Coordinate = coord,
				FARPType = ENUMS.FARPType.INVISIBLE,
				DynamicSpawns = true,
				HotStart = true
			})

			local spawnedFarpName = spawnedFarpObjects[1].StaticName
			FMS.HeloOps.FARP.Count = FMS.HeloOps.FARP.Count + 1

			-- Notify everybody
			local unitName = unitThatBuiltCrates:GetName() or "Aircraft"
			local msg = unitName .. ' has deployed "'..spawnedFarpName..'" at '..coord:ToStringMGRS()
			self:logINF(msg)
			MESSAGE:New(msg, 30):ToAll()

			-- FMS.HeloOps.FillFARP(spawnedFarpName)

			-- TODO: Do we need to make a loadzone?
		end
	end

end

function FMS.HeloOps.SpawnFARP(paramsTable)
	return UTILS.SpawnFARPAndFunctionalStatics(
		paramsTable.Name,
		paramsTable.Coordinate,
		paramsTable.FARPType or ENUMS.FARPType.INVISIBLE,
		paramsTable.Coalition,
		paramsTable.Country,
		paramsTable.CallSign,
		paramsTable.Frequency,
		paramsTable.Modulation,
		paramsTable.ADF,
		paramsTable.SpawnRadius,
		paramsTable.VehicleTemplate,
		paramsTable.Liquids,
		paramsTable.Equipment,
		paramsTable.Airframes,
		paramsTable.F10Text,
		paramsTable.DynamicSpawns,
		paramsTable.HotStart, -- assume hotstart if dynamicSpawn was given
		paramsTable.NumberPads,
		paramsTable.SpacingX,
		paramsTable.SpacingY
	)
end

-- PRIVATE INTERFACE -----------------------------------------------------------

function CTLD:_CTLDAddStaticsCargo(groupTemplateName, massKg, submenu)
	if not STATIC:FindByName(groupTemplateName, false) then
		self:logWAR("Unable to add static cargo '" .. groupTemplateName .. "'")
		return
	end
	
	self:AddStaticsCargo(groupTemplateName, massKg, nil, submenu)
	self:logINF("Added crates/static '" .. groupTemplateName .. "' to submenu '"..(submenu or "nil").."'")
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
	local _coalition = coalitionSide_ or coalition.side.BLUE
	local _alias = alias_ or "CSAR Corps"
	local _downedPilotGroupTemplateName = downedPilotGroupTemplateName_
	
	if not GROUP:FindByName(_downedPilotGroupTemplateName) then
		env.info(logPrefix .. "|CSAR: No downed pilot template called \"" .. (_downedPilotGroupTemplateName or "nil") .. "\" found in mission. Using default template.")
		FMS.DBSpawn(FMS.HeloOps.DownedPilotTemplate, country.id.USA, Group.Category.GROUND)
		_downedPilotGroupTemplateName = FMS.HeloOps.DownedPilotTemplate.name
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
	else
		_csar_instance:ApplyDefaultConfiguration()
	end

	_csar_instance:__Start(4)
		
	return _csar_instance
end

function CSAR:ApplyDefaultConfiguration()
	-- self.useprefix = false -- Handled by the OA.HeloOps:NewCSAR() function

	self.csarOncrash = true -- If set to true, will generate a downed pilot when a plane crashes as well.
	self.enableForAI = true
	self.allowDownedPilotCAcontrol = true
	self.coordtype = 2 -- MGRS
	self.extractDistance = 200
	self.loadDistance = 5
	self.approachdist_far = 2000
	self.approachdist_near = 1000
	self.pilotmustopendoors = false
	self.rescuehoverheight = 30
	self.rescuehoverdistance = 10

	self.suppressmessages = false -- false by default
	self.immortalcrew = true -- true by default
	self.invisiblecrew = false -- false by default
	self.autosmoke = false  -- false by default
	self.max_units = 6 -- 6 is default
	self.allowFARPRescue = true -- true by default
	
	self:logINF("Default Configuration applied.")
end


function CSAR:SpawnDownedPilotInZone(zoneName, pilotName_)
	local _name = pilotName_
	
	if not _name then
		_name = FMS.HeloOps.RandomNames[ math.random( #FMS.HeloOps.RandomNames ) ]
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
	local function errMsg(msg)
		errorFuse = true
		MESSAGE:New(msg, 20, logPrefix):ToAll()
	end
	
	if FMS.HeloOps.Error.MissingTroops > 0 then
		errMsg("Missing " .. FMS.HeloOps.Error.MissingTroops .. " troop group templates")
	end
	if FMS.HeloOps.Error.MissingVehicles > 0 then
		errMsg("Missing " .. FMS.HeloOps.Error.MissingVehicles .. " vehicle group templates")
	end
	if FMS.HeloOps.Error.MissingCrates > 0 then
		errMsg("Missing " .. FMS.HeloOps.Error.MissingCrates .. " crate static templates")
	end
	if FMS.HeloOps.Error.MissingFARP > 0 then
		errMsg("Missing " .. FMS.HeloOps.Error.MissingFARP .. " FARP templates")
	end
	if FMS.HeloOps.Error.InitFailure then
		errMsg("An error occurred when trying to initialize CTLD.")
	end

	local msg = "FMS HeloOps ".. version .." CTLD BIT: " .. (errorFuse and "FAILURE" or "SUCCESS")
	MESSAGE:New(msg, 30):ToAll()
	if errorFuse then FMS.HeloOps.Log.error(msg)
	else FMS.HeloOps.Log.info(msg) end
end

function FMS.HeloOps.FillFARP(farpName, liquids_, items_)
	local ab = AIRBASE:FindByName(farpName)
	if ab == nil then
		FMS.HeloOps.Log.error("FillFARP: Cannot find airbase named '"..farpName.."'.")
		return
	end
	
	local wh = ab:GetStorage()
	FMS.HeloOps._SetFARPLiquids(wh, liquids_ or 100)
	FMS.HeloOps._SetFARPItems(wh, items_ or 1000)

	FMS.HeloOps.Log.info("FillFARP: FARP '"..farpName.."' has been supplied.")
end

function FMS.HeloOps._SetFARPLiquids(wh, tons)
	local kgs = (tons or 100) * 1000
	-- FMS.HeloOps.Log.info("  - FARP set_liquids("..farpName..", "..tostring(kgs).." kgs)")
	wh:SetLiquid(STORAGE.Liquid.DIESEL, kgs) -- kgs to tons
	wh:SetLiquid(STORAGE.Liquid.GASOLINE, kgs)
	wh:SetLiquid(STORAGE.Liquid.JETFUEL, kgs)
	wh:SetLiquid(STORAGE.Liquid.MW50, kgs)
end

function FMS.HeloOps._SetFARPItems(wh, count)
	local count = count or 100
	-- FMS.HeloOps.Log.info("  - FARP set_items("..farpName..", "..tostring(count).." qty)")
	for cat,nitem in pairs(ENUMS.Storage.weapons) do
		-- FMS.HeloOps.Log.info("    - cat: "..cat)
		for name,item in pairs(nitem) do
			-- FMS.HeloOps.Log.info("      - name: "..name)
			wh:SetItem(item, count)
		end
	end
end

FMS.HeloOps.RandomNames = {
	"Pete Mitchell", "Tom Kazansky", "Nick Bradshaw", "Mike Metcalf", "Marcus Williams", "Tom Jardian", "Rick Hieatherly", "Ron Kerner", "Rick Neven", "Bill Cortell", "Henry Ruth", "Sam Wells",
	"Beau Simpson", "Jake Seresin", "Chester Cain", "Robert Floyd", "Solomon Bates", "Bernie Coleman", "Reuben Fitch", "Mickey Garcia",
	"Jake Preston", "Brad Little",
	"Charles Sinclair", "Doug Masters",
	"Ted Striker", "Clarence Oveur"
}

FMS.HeloOps.DownedPilotTemplate = {
	lateActivation = true,
	tasks = {},
	uncontrollable = false,
	task = "Ground Nothing",
	hiddenOnMFD = true,
	hidden = false,
	units = {
		[1] = {
			name = "Downed Pilot",
			type = "Soldier M4 GRG",
			x=0, y=0,	
		},
	},
	x=0, y=0,
	name = "Downed Pilot",
	hiddenOnPlanner = true
}

FMS.HeloOps.Hummer = {
	lateActivation = true,
	tasks = {},
	uncontrollable = false,
	task = "Ground Nothing",
	hiddenOnMFD = true,
	hidden = false,
	units = {
		[1] = {
			name = "FMS Hummer",
			type = "Hummer",
			livery_id = "desert",
			x=0, y=0,
		},
	},
	x=0, y=0,
	name = "FMS Hummer",
	hiddenOnPlanner = true
}

-- -----------------------------------------------------------------------------
-- HeloOps STM Operations
-- Dependencies:
--   - FMS.Utilities
--   - FMS.StaticTemplates
-- -----------------------------------------------------------------------------

--- Spawns the STM file at the specified path at the specified vec2.
function FMS.HeloOps.SpawnAndFillSTMFARPAtVec2(templateName, missionDirPath, vec2, spawnedHandler_)
	FMS.SpawnSTMAtVec2(templateName, missionDirPath, vec2, function(spawned)
		FMS.HeloOps.FillSpawnIfFARP(spawned)
		FMS.CallHandler(spawnedHandler_, spawned)
	end)
end

--- If the specified Wrapper group/static is a FARP type, fill it with supplies.
function FMS.HeloOps.FillSpawnIfFARP(spawned)
	local farpTypeNames = {"Invisible FARP"}
	for _, farpTypeName in ipairs(farpTypeNames) do
		if farpTypeName == spawned:GetTypeName() then
			FMS.HeloOps.FillFARP(spawned:GetName())
		end
	end
end

--- Adds troops found in the specified static template to the CTLD troops menu.
-- A "sidecar" lua file may be created that describes the groups in more detail (e.g. provide weight, submenu names, etc.).
-- The format of this sidecar file should be a simple lua script that returns a table, where each key in the table
-- is the name of the template group (in the ME), and each key is a table with `name`, `qty` and `wt` values that
-- specify the CTLD group's "menu name", "unit count", and "unit weight", respectively.
function CTLD:AddTroopGroupsFromSTM( templateName, missionDirPath, sidecarAbsolutePath_, restrictToOnlySidecar_ )
	self:_AddGroupsFromSTM(false, templateName, missionDirPath, sidecarAbsolutePath_, restrictToOnlySidecar_)
end

--- Adds vehicles found in the specified static template to the CTLD crates menu.
-- A "sidecar" lua file may be created that describes the groups in more detail (e.g. provide weight, submenu names, etc.).
-- The format of this sidecar file should be a simple lua script that returns a table, where each key in the table
-- is the name of the template group (in the ME), and each key is a table with `name`, `qty` and `wt` values that
-- specify the CTLD group's "menu name", "crate count", and "unit weight", respectively.
function CTLD:AddVehicleGroupsFromSTM( templateName, missionDirPath, sidecarAbsolutePath_, restrictToOnlySidecar_ )
	self:_AddGroupsFromSTM(true, templateName, missionDirPath, sidecarAbsolutePath_, restrictToOnlySidecar_)
end

function CTLD:_AddGroupsFromSTM( isCrated, templateName, missionDirPath, sidecarAbsolutePath_, restrictToOnlySidecar_ )
	self:logINF("Adding groups from template: "..templateName)

	if not FMS.PATH then
		self:logERR("Unable to call CTLD:_AddGroupsFromSTM(). Did you call FMS.Init()?")
		FMS.HeloOps.Error.InitFailure = true
		return
	elseif not FMS.Utilities then
		self:logERR("Unable to call CTLD:_AddGroupsFromSTM(). Cannot find FMS.Utilities.")
		FMS.HeloOps.Error.InitFailure = true
		return
	elseif not FMS.StaticTemplates then
		self:logERR("Unable to call CTLD:_AddGroupsFromSTM(). Cannot find FMS.StaticTemplates.")
		FMS.HeloOps.Error.InitFailure = true
		return
	end

	-- Attempt to load a sidecar file with menu names, weights, counts, etc
	local sidecarFilePath = sidecarAbsolutePath_ or FMS.PATH(missionDirPath .. "\\" .. templateName .. ".lua")
	local troopsLookup = FMS.LoadFileWithResult(sidecarFilePath)

	local templateFilePath = FMS.PATH(missionDirPath .. "\\" .. templateName .. ".stm")
	FMS.RegisterSTMFile(templateFilePath,
		function(vehicleGroup, category)
			if category == Group.Category.GROUND then
				local groupName = vehicleGroup.name
				if restrictToOnlySidecar_ and troopsLookup and (not troopsLookup[groupName]) then
					self:logINF("Skipping group '"..groupName.."' not found in sidecar")
				else
					local sidecarTable = {}
					if troopsLookup then sidecarTable = troopsLookup[groupName] or {} end
					local menuName   = sidecarTable.name or groupName
					local unitCount  = sidecarTable.qty or sidecarTable.count or #(vehicleGroup.units)
					local unitWeight = sidecarTable.wt or sidecarTable.weight or 80
					local submenu    = sidecarTable.submenu
					if isCrated then
						self:AddVehicleGroups(menuName, {groupName}, unitCount, unitWeight, submenu)
					else
						self:AddTroopGroups(menuName, {groupName}, unitCount, unitWeight, submenu)
					end
				end
			end
		end,
		nil, true
	)
end

function CTLD:registerSTMFARP( stmTable, oa_path, FARPTemplatePlaceholderGroupName_, cratesCount_, perCrateMassKg_ )
	
	local _FARPTemplateGroupName = FARPTemplatePlaceholderGroupName_ or "FARP"
	local cratesCount = cratesCount_ or 2
	local perCrateMassKg = perCrateMassKg_ or 2000
	local _heliportStaticName = nil
	local groupNames = {}
	local staticNames = {}

	FMS.RegisterSTM(stmTable, oa_path,
		function(vehicleGroupTable, category)
			if vehicleGroupTable.name ~= _FARPTemplateGroupName then
				table.insert(groupNames, vehicleGroupTable.name)
			end
		end,

		function(staticGroupTable)
			local unitTable = staticGroupTable.units[1]
			-- We assume that there will be *one and only one* heliport in this STM template file
			if unitTable.category == "Heliports" then
				_heliportStaticName = unitTable.name
			else
				table.insert(staticNames, unitTable.name)
			end
		end,

		true
	)

	self:AddFARPCrates("FARP", _FARPTemplateGroupName, cratesCount, perCrateMassKg)
	self:ConfigureFARP(_FARPTemplateGroupName, _heliportStaticName, groupNames, staticNames, nil)

end

-- Since FMS.DBSpawn lives in `StaticTemplates.lua`, I'm going to reimplement a terse copy here.
if not FMS.DBSpawn then
	env.warning("FMS.HeloOps: Defining my own DBSpawn method!")
	function FMS.DBSpawn(template, countryId, categoryId)
		template.CountryID = countryId
		template.CategoryID = categoryId
		_DATABASE:Spawn(template)
	end
end