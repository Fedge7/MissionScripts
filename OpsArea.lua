--[[
FMS Area of Operations Script
Author: Fedge

Description:
	This script allows a mission designer to setup an "area of operations" in which units/statics may
	be spawned and despawned. Think of an OpsArea as a living "range".

	An OpsArea has a main zone, and any number of "Spawnzones", inside of which groups may be spawned.

Modifications:
	- v0.1    Fedge            Port of Fedge's original script.
	- v0.2    Fedge            Added `NewFromSTM()` function.
	- v0.3    Fedge            Added spawnAllRandomly, respawnAll, spawnRandomGroupInZone.
	- v0.4    Fedge            Groups registered via template can now have descriptive menu names given in a .mnu file.
	- v0.5    Fedge            Main zone is now optional.
	- v1.0    Fedge            Initial implementation complete. Removes custom SPAWNER class. Improves event handling. Adds Auto-respawn. Adds F10 map markers.

TODO:
	- Limit spawns to a particular zone
	- Allow registration of all group templates within a zone
	- Allow group destroy for a particular spawnZone
]]

if FMS == nil then FMS = {} end

FMS.OpsArea = {}
FMS.OpsArea.__index = FMS.OpsArea

FMS.OpsArea.DEBUG = false

function FMS.OpsArea.Init(parentMenu)
	FMS.OpsArea.MainMenu = MENU_MISSION:New("Areas of Operation", parentMenu)
end

function FMS.OpsArea:_New(areaName)
	local obj = {}
	setmetatable(obj, self)
	
	obj:_init(areaName)
	return obj
end

--- Creates a new OpsArea object
-- @param #string areaName The name of the AO, as it will appear in the radio menu
-- @param #string zoneName The name of the zone in the mission editor that constitutes this AO
-- @param #boolean showInMenu_ If true, adds a menu to the "Area of Operations" F10 menu for this AO
-- @return The newly constructed OpsArea object
function FMS.OpsArea:New(areaName, zoneName, showInMenu_, marker_)
	return FMS.OpsArea
		:_New(areaName)
		:_initZone(zoneName, showInMenu_, (marker_ or 0))
end

--- Creates a new OpsArea object from an STM file or STM table
-- @param #string areaName The name of the AO, as it will appear in the radio menu.
-- @param #string templateName: The name of the stm template file, or stm template table (e.g. `SISI_Town`).
-- @param #string relPath_ If the stm file is to be loaded dynamically from disk, the path to the file (e.g. `Static Templates`). Optional.
-- @param #string zoneName_ The name of the zone in the ME that defines this OpsArea. Optional. If not specified, a zone will created for you that contains all the STM's groups. Passing empty string (i.e. `""`) will surpress the automatic creation of a zone.
-- @param #string spawnZonePrefix Will associate any trigger zones defined in the ME with this prefix as part of this OpsArea. Optional.
-- @param #boolean showInMenu_ If true, adds a menu to the "Area of Operations" F10 menu for this AO. Optional, defaults to true.
function FMS.OpsArea:NewFromSTM( areaName, templateName, relPath_, zoneName_, spawnZonePrefix_, showInMenu_, marker_ )
	local ao = FMS.OpsArea:_New(areaName)
	
	-- Check to see if we can find an accompanying menu dictionary file
	local groupNameLookupTable = nil
	-- If relPath_ is nil, there's a good chance we're in a static environment and can't do any disk loads
	if relPath_ then
		local sidecarFilePath = FMS.PATH(relPath_ .. "\\" .. templateName .. ".mnu")
		groupNameLookupTable = FMS.LoadfileWithResult(sidecarFilePath)
	end

	-- We need to traverse the STM file first, to get the positions of all the units so that we can
	-- construct a zone from their positions.
	local positions = {}
	FMS.TraverseSTM(templateName, relPath_,
		function(groupTable)
			-- Store the group's units' positions so we can later compute the centroid of all units
			for _,u in pairs(groupTable.units) do
				table.insert(positions, {x=u.x, y=u.y})
			end
		end,
		function(staticGroupTable)
			-- Store the static's positions so we can later compute the centroid of all units
			local unitTable = staticGroupTable.units[1]
			table.insert(positions, {x=unitTable.x, y=unitTable.y})
		end
	)

	local theZone = nil
	
	-- Get the zone from the mission editor
	if zoneName_ then
		local meZone = ZONE:FindByName(zoneName_)
		if meZone then theZone = meZone end
	end

	-- Compute and construct the zone at the centroid of all the AO's groups
	if not theZone then
		local center, radius = enclosing_circle(positions)
		local centerCoord = COORDINATE:NewFromVec2(center)
		
		if FMS.OpsArea.DEBUG then
			COORDINATE:NewFromVec2(center):CircleToAll(radius, nil, {0, 1, 0})
			COORDINATE:NewFromVec2(centroid(positions)):CircleToAll(radius, nil, {0, 0, 1})
		end

		if (not theZone) and zoneName_ ~= "" then
			local zoneName = "OpsArea-"..((zoneName_ or ao.name) or "nil")
			theZone = ZONE_RADIUS:New(zoneName, center, radius)
			ao.log:log("Creating an enclosing zone named '" .. theZone:GetName() .."' around STM groups.")
		end
	end

	ao:_initZone(theZone, showInMenu_, (marker_ or 0))

	if spawnZonePrefix_ then
		ao:scanForSpawnzones(spawnZonePrefix_)
	end

	FMS.RegisterSTM(templateName, relPath_,
		function(groupTable, category)
			-- Check for a menu entry in the dictionary, and check if we should allow spawning
			local menuName = nil
			if groupNameLookupTable then
				local menuEntry = groupNameLookupTable[groupTable.name]
				if menuEntry then
					menuName = menuEntry.name
					if not menuEntry.spawnable then
						return
					end
				end
			end

			-- Have to pass `force=true` here because GetVec3() is failing on the group
			ao:registerGroupTemplate(groupTable.name, menuName, true)
		end,
		function(staticGroupTable)
			local unitTable = staticGroupTable.units[1]
			if unitTable.type == "big_smoke" then
				ao.log:log("Registering smoke effect named " .. unitTable.name, LOG.Level.DEBUG)
				table.insert(ao._smokeEffects, unitTable)
			else
				ao:registerStaticByName(unitTable.name)
			end
		end
	)

	ao.log:log("Registered "..ao._groupsCount.." group templates.")
	return ao
end

--- Returns a circle guaranteed to enclose all the points within the specified table.
-- *NOT* guaranteed to be the smallest enclosing circle.
function enclosing_circle(xyTables)
	local allX = {}
	local allY = {}
	for _,v in pairs(xyTables) do
		table.insert(allX, v.x);
		table.insert(allY, v.y);
	end
	
	local maxX = math.max(unpack(allX))
	local maxY = math.max(unpack(allY))
	local minX = math.min(unpack(allX))
	local minY = math.min(unpack(allY))
	local midX = (maxX + minX) / 2
	local midY = (maxY + minY) / 2

	local function cartesian_distance(a, b)
		return ( ( b.x - a.x )^2 + ( b.y - a.y )^2 )^0.5
	end

	local dist = cartesian_distance( {x=minX, y=minY}, {x=maxX, y=maxY} )
	local radius = dist / 2

	return {x=midX, y=midY}, radius
end

function centroid(xyTbls)
	local sum_x = 0
	local sum_y = 0
	local count = 0
	for _,v in pairs(xyTbls) do
		sum_x = sum_x + ( v.x * (v.w or 1) )
		sum_y = sum_y + ( v.y * (v.w or 1) )
		count = count + 1
	end
	return {x=(sum_x / count), y=(sum_y / count)}
end

function FMS.OpsArea:_init(areaName)
	-- Setup Logging
	self.log = LOG:New("OpsArea|" .. areaName, LOG.Level.INFO2)
	self.log:log("Initializing AO")
	
	self.menus = {}

	--- The name of the AO
	self.name = areaName

	--- Tracks whether the range has been spawned and is alive
	self.alive = false

	--- Dictionary of zones where groups are allowed to spawn, keyed by the zone name
	self._spawnZones = {}

	--- Dictionary of SPAWN objects, keyed by groupName
	self._spawners = {}

	--- Number of seconds after the entire AO dies that the AO should be respawned. 0 is instantaneous. nil is "do not autorespawn."
	self._autoRespawnDelay = nil

	--- A function containing the last spawn function call. Used for autorespawning whatever was spawned most recently.
	self._lastSpawnCall = nil

	-- Manually track group template count, because lua fucking sucks and can't reliably count table entries
	self._groupsCount = 0

	-- Not in use, for the moment
	-- obj._groupTemplates = {}

	--- List of names of static units that can be spawned into this OpsArea
	self._staticNames = {}
	
	--- List of smoke effect unit tables
	self._smokeEffects = {}

	--- The Core.Zone#ZONE object associated with this OpsArea
	-- Will be set later in _initZone(...)
	self.zone = nil

	--- A marker displayed on the map indicating the position of the OpsArea
	-- Will be set later in _initZone(...)
	self.marker = nil

	return self
end

function FMS.OpsArea:_initZone(zoneOrZoneName, showInMenu_, markerUncertaintyOrVec2_)

	if type(zoneOrZoneName) == 'string' then
		self.log:log("Creating a new zone named '" .. zoneOrZoneName .. "'.")
		self.zone = ZONE:New(zoneOrZoneName)
	elseif type(zoneOrZoneName) == 'table' then
		self.log:log("Setting AO's zone to existing zone '" .. zoneOrZoneName:GetName() .. "'.")
		self.zone = zoneOrZoneName
	end

	if FMS.OpsArea.DEBUG and self.zone then
		self.zone:DrawZone()
	end

	if markerUncertaintyOrVec2_ == nil
		or type(markerUncertaintyOrVec2_) == 'number'
		or type(markerUncertaintyOrVec2_) == 'table'
	then
		self.marker = self:makeMarker(markerUncertaintyOrVec2_)
	else
		self.marker = nil
	end

	-- Construct the menu entry for this AO, if required
	if showInMenu_ or showInMenu_ == nil then
		self:_buildMenus()
	end

	return self
end

function FMS.OpsArea:spawnZonesCount()
	local cnt = 0
	for k,v in pairs(self._spawnZones) do
		cnt = cnt + 1
	end
	return cnt
end

--- Scans for spawnzones and group templates that appear within this AO's main zone
function FMS.OpsArea:autoScan()
	self:scanForSpawnzones()
	self:scanForGroupTemplates()
	return self
end

function FMS.OpsArea:_buildMenus()
	self.log:log("Creating menu entries", LOG.Level.DEBUG)
	
	if not FMS.OpsArea.MainMenu then
		FMS.OpsArea.MainMenu = MENU_MISSION:New("Areas of Operation")
	end

	-- Add a menu for this AO to the main "Area of Operations" menu
	self.menus.aoMenu = MENU_MISSION:New(self.name, FMS.OpsArea.MainMenu)
	self.menus.spawnMenu = MENU_MISSION:New("Spawn", self.menus.aoMenu)

	-- Add a command to spawn all this AO's groups
	MENU_MISSION_COMMAND:New("Spawn All", self.menus.spawnMenu, FMS.OpsArea.spawnAll, self)
	if self.zone then
		-- We need a zone to be able to randomly spawn anything
		MENU_MISSION_COMMAND:New("Spawn All Randomly", self.menus.spawnMenu, FMS.OpsArea.spawnAllRandomly, self)
	end
	MENU_MISSION_COMMAND:New("Respawn All", self.menus.spawnMenu, FMS.OpsArea.respawnAll, self)
	
	--- The submenu for spawning groups
	-- This list will grow with new menus as "More" menus are added to handle overflow
	self.spawnGroupMenus = { MENU_MISSION:New("Spawn Group", self.menus.spawnMenu) }
		
	-- Destroy menu and submenus
	local destroyMenu = MENU_MISSION:New("Destroy", self.menus.aoMenu)
	MENU_MISSION_COMMAND:New("Despawn all RED groups",     destroyMenu, FMS.OpsArea.destroySpawnedGroups, self, coalition.side.RED)
	MENU_MISSION_COMMAND:New("Despawn all BLUE groups",    destroyMenu, FMS.OpsArea.destroySpawnedGroups, self, coalition.side.BLUE)
	MENU_MISSION_COMMAND:New("Despawn all NEUTRAL groups", destroyMenu, FMS.OpsArea.destroySpawnedGroups, self, coalition.side.NEUTRAL)
	MENU_MISSION_COMMAND:New("Despawn all groups",         destroyMenu, FMS.OpsArea.destroySpawnedGroups, self)
	if self.zone then
		-- We need a zone to be able to destroy it (ya know, the zone...)
		MENU_MISSION_COMMAND:New("Destroy entire zone",    destroyMenu, FMS.OpsArea.destroyAllInZone,     self, self.zone)
	end

	--- The submenu for performing zone actions
	self.menus.zonesMenu = MENU_MISSION:New("Zones", self.menus.aoMenu)
	
	--- Dictionary of `MENU_MISSION`, keyed by zoneName, for each zone
	self.menus.zonesSubmenus = {}

	local autoRespawnMenu = MENU_MISSION:New("Auto-Respawn", self.menus.aoMenu)
	MENU_MISSION_COMMAND:New("Auto-Respawn ON",  autoRespawnMenu, FMS.OpsArea.autoRespawnOn,  self, 10)
	MENU_MISSION_COMMAND:New("Auto-Respawn OFF", autoRespawnMenu, FMS.OpsArea.autoRespawnOff, self)

	if self.zone then
		-- There are numerous reports that "removeJunk" is causing crashes on both SP and MP.
		MENU_MISSION_COMMAND:New("Remove Junk (!EXPERIMENTAL!)", self.menus.aoMenu, FMS.OpsArea._removeJunk, self)
	end

end

function FMS.OpsArea:addSpawnZone(zoneName)
	self.log:log("Adding zone named: " .. zoneName)
	
	local zone = ZONE:New(zoneName)
	self._spawnZones[zoneName] = zone

	local zoneMenu = MENU_MISSION:New(zoneName, self.menus.zonesMenu)
	self.menus.zonesSubmenus[zoneName] = zoneMenu

	MENU_MISSION_COMMAND:New("Spawn Random Group",         zoneMenu, FMS.OpsArea.spawnRandomGroupInZone, self, zone)
	MENU_MISSION_COMMAND:New("Destroy all RED groups",     zoneMenu, FMS.OpsArea.destroyAllInZone, self, zone, {"red"})
	MENU_MISSION_COMMAND:New("Destroy all BLUE groups",    zoneMenu, FMS.OpsArea.destroyAllInZone, self, zone, {"blue"})
	MENU_MISSION_COMMAND:New("Destroy all NEUTRAL groups", zoneMenu, FMS.OpsArea.destroyAllInZone, self, zone, {"neutral"})
	MENU_MISSION_COMMAND:New("Destroy all groups",         zoneMenu, FMS.OpsArea.destroyAllInZone, self, zone)
end

--- Looks for zones inside this AO's main zone and registers them as spawnzones
-- @param #string filterPrefix_ A prefix string that will be used to filter which zones are automatically registered. The default value is "Spawnzone". If you wish to disable filtering, pass empty string (i.e. "").
function FMS.OpsArea:scanForSpawnzones(filterPrefix_)
	self.log:log("Auto registering all spawnzones in zone.")
	
	local spawnzones = SET_ZONE:New()
	if filterPrefix_== nil then
		spawnzones:FilterPrefixes("Spawnzone")
	elseif filterPrefix_ ~= "" then
		spawnzones:FilterPrefixes(filterPrefix_)
	end
	spawnzones:FilterOnce()

	spawnzones:ForEachZone(function(_spawnzone)
		if self.zone:IsVec2InZone(_spawnzone:GetVec2()) then
			if _spawnzone:GetName() ~= self.zone:GetName() then
				self:addSpawnZone(_spawnzone:GetName())
			end
		end
	end)
end

--- Looks for any late-activated group templates within the AO's zone, and registers them as spawnable.
function FMS.OpsArea:scanForGroupTemplates()
	self.log:log("Auto registering all group templates in zone.")
	
	local zoneTemplates = SET_GROUP:New()
		:FilterActive(false)
		--:FilterZones({_zone}) -- this only works on alive units
		:FilterOnce()

	local function _groupAnyLateInZone( Group, Zone )
		-- IsAlive() returns nil for a group that was alive, then died.
		-- So we want to specifically check for: `Group:IsAlive == false`
		if Group:IsAlive() or Group:IsAlive() == nil then return false end
		for UnitID, UnitData in pairs( Group:GetUnits() ) do
			if Zone:IsVec3InZone( UnitData:GetVec3() ) then return true end
		end
		return false
	end
	
	zoneTemplates:ForEachGroup(function(_group)
		if _groupAnyLateInZone(_group, self.zone) then
			self:registerGroupTemplate(_group:GetName()) -- can we parse a name for the menu?
		end
	end)

	self.log:log("Registered "..self._groupsCount.." group templates.")
end

--- Registers a group (by name) as a spawnable group within this OpsArea
-- @param #string groupName The name of the group, as defined in the mission editor
-- @param #string groupMenuAlias_ A descriptive name for this group as it will appear in the menu
-- @param #boolean force_ If true, this OpsArea will bypass the "in zone" check for this group and allow you to register a group that is outsize the AO's main zone
function FMS.OpsArea:registerGroupTemplate(groupName, groupMenuAlias_, force_)

	local force = force_ or false
	
	-- Because the group's menu alias name is only used here, we don't actually have to store it.
	-- It is only used when the radio item is created.

	-- Reject any group templates that have already been added
	if self._spawners[groupName] then
		self.log:log("Ignoring group named " .. groupName .. ". Already registered.", LOG.Level.INFO)
		return
	end

	local group = GROUP:FindByName(groupName)
	
	-- Reject any groups that can't be found
	if not group then
		self.log:log("Can't find group named " .. groupName .. ".", LOG.Level.WARNING)
		return
	end
	
	-- Reject any groups that aren't actually in this AO's zone
	if not force and not self.zone:IsVec3InZone( group:GetVec3() ) then
		self.log:log("Attempting to add group " .. groupName .. " not in zone.", LOG.Level.WARNING)
		return
	end
	
	local groupMenuAlias = groupMenuAlias_ or groupName
	self.log:log("Registering group named " .. groupName .. " (" .. groupMenuAlias .. ")", LOG.Level.DEBUG)
	-- table.insert(self._groupTemplates, groupName)
	
	-- Create a new spawner object for this group template
	local spawner = SPAWN:New(groupName, self.log)
	spawner:OnSpawnGroup(function(_spawnedGroup) self:_afterSpawnGroup(_spawnedGroup) end)

	self._spawners[groupName] = spawner
	self._groupsCount = self._groupsCount + 1
	
	if self.spawnGroupMenus then
	
		-- Handle overflow menus
		local menuCount = #(self.spawnGroupMenus)
		local parentMenu = self.spawnGroupMenus[menuCount]
		local gc = self._groupsCount
		local maxGroupsInMenu = 9
		local menusRequired = 1
		while gc >= maxGroupsInMenu do
			gc = gc - maxGroupsInMenu
			menusRequired = menusRequired + 1
		end
		local newMoreMenu = nil 
		if menusRequired > menuCount then
			self.log:log("Group count is " .. self._groupsCount .. ". Creating 'More' menu.", LOG.Level.TRACE)
			newMoreMenu = MENU_MISSION:New("More groups " .. menusRequired, parentMenu)
			table.insert(self.spawnGroupMenus, newMoreMenu)
		end

		-- Create the actual menu for this group 
		local groupMenu = MENU_MISSION:New(groupMenuAlias, newMoreMenu or parentMenu)
				
		-- Creates a menu item to spawn the group in its original location in the mission editor
		MENU_MISSION_COMMAND:New("Spawn (original loc)", groupMenu, FMS.OpsArea.spawn, self, spawner)

		if self.zone then
			-- Creates a menu item to spawn the group somewhere randomly within the OpsArea's main zone
			MENU_MISSION_COMMAND:New("Spawn (random loc)", groupMenu, FMS.OpsArea.spawnInZone, self, spawner, self.zone)
		end
		
		-- Creates a menu item to spawn the group within a specific spawn zone
		local next = next -- Lua hack that dramatically speeds up the call to `next()`
		if not (next(self._spawnZones) == nil) then
			-- If we have any spawnZones, allow spawning of this group within any of our spawnZones
			
			-- Creates a menu item to spawn this group in a randomly chosen zone
			MENU_MISSION_COMMAND:New("Spawn In Random Zone", groupMenu, FMS.OpsArea.spawnInRandomZone, self, spawner)

			local spawnInZonesMenu = MENU_MISSION:New("Spawn In Named Zone", groupMenu)
			for zoneName, zone in pairs(self._spawnZones) do
				MENU_MISSION_COMMAND:New(zoneName, spawnInZonesMenu, FMS.OpsArea.spawnInZone, self, spawner, self._spawnZones[zoneName])
			end
		end
		
	end

end

function FMS.OpsArea:registerStaticByName( staticUnitName )
	self.log:log("Registering static named " .. staticUnitName, LOG.Level.DEBUG)
	table.insert(self._staticNames, staticUnitName)
end

function FMS.OpsArea:makeMarker(uncertaintyOrVec2_)
	
	local uncertainty = nil
	local coord = nil

	if (uncertaintyOrVec2_ == nil) then
		uncertainty = 0
	elseif type(uncertaintyOrVec2_) == 'number' then
		uncertainty = uncertaintyOrVec2_
		uncertainty = uncertainty < 1 and uncertainty or 1
		uncertainty = uncertainty > 0 and uncertainty or 0
	elseif type(uncertaintyOrVec2_) == 'table' and uncertaintyOrVec2_.x and uncertaintyOrVec2_.y then
		coord = COORDINATE:NewFromVec2(uncertaintyOrVec2_)
	else
		return nil
	end

	if uncertainty and self.zone then
		self.log:log("Creating marker from zone " .. self.zone:GetName(), LOG.Level.DEBUG)
		local radius = self.zone:GetRadius() * uncertainty
		coord = COORDINATE:NewFromVec2(self.zone:GetCoordinate():GetRandomVec2InRadius(radius))
		if FMS.OpsArea.DEBUG then self.zone:GetCoordinate():CircleToAll(radius, nil, {1,1,0}, nil, nil, nil, 2) end
	end

	if not coord then return nil end

	-- Create the map marker
	return MARKER:New(coord, "AO: "..self.name)
end

function FMS.OpsArea:showMapMarker(uncertaintyOrVec2_)
	if not self.marker then
		self.marker = self:makeMarker(uncertaintyOrVec2_)
	end
	self.marker:ToAll()
end

function FMS.OpsArea:removeMapMarker()
	if self.marker then
		self.marker:Remove()
	end
end

--- Spawns all groups and all statics in their original locations.
-- Does *not* check to see a group is currently alive so it is possible to end up with duplicate/overlapping groups.
function FMS.OpsArea:spawnAll()
	self.log:log("Spawning all groups in " .. self.name, LOG.Level.INFO)

	local spawnedGroups = {}
	
	for groupName, spawner in pairs(self._spawners) do
		local group = self:spawn(spawner)
		table.insert(spawnedGroups, group)
		-- TODO: is the spawnedGroups table necessary?
	end
	
	for _,staticName in ipairs(self._staticNames) do
		self.log:log("Spawning static " .. staticName, LOG.Level.DEBUG)
		SPAWNSTATIC:NewFromStatic(staticName):Spawn()
	end

	for _,smoke in ipairs(self._smokeEffects) do
		self.log:log("Spawning smoke at " .. smoke.x .. ", " .. smoke.y, LOG.Level.DEBUG)
		COORDINATE:NewFromVec2({x=smoke.x, y=smoke.y})
			:BigSmokeAndFire(smoke.effectPreset, smoke.effectTransparency, smoke.name)
	end

	self:showMapMarker()

	self._lastSpawnCall = function() self:spawnAll() end
	return spawnedGroups
end

--- Spawns all groups in a random location within the main zone.
-- Does *not* spawn any statics.
function FMS.OpsArea:spawnAllRandomly()
	self.log:log("Spawning all groups RANDOMLY in " .. self.name, LOG.Level.INFO)
	for groupName, spawner in pairs(self._spawners) do
		self:spawnInZone(spawner, self.zone)
	end

	self:showMapMarker()

	self._lastSpawnCall = function() self:spawnAllRandomly() end
end

--- Respawns any groups that are no longer alive in their original locations, as defined in the template.
function FMS.OpsArea:respawnAll()
	self.log:log("Respawning all dead groups in " .. self.name, LOG.Level.INFO)
	for groupName, spawner in pairs(self._spawners) do
		if spawner:HasAliveGroups() then
			self.log:log("Skipping respawn for alive group " .. groupName)
		else
			self:spawn(spawner)
		end
	end
end

--- Performs a single spawn of the specified SPAWN object
function FMS.OpsArea:spawn(spawner)
	self.log:log("Spawning " .. spawner:GetGroupName(), LOG.Level.DEBUG)
	self._lastSpawnCall = function() self:spawn(spawner) end
	return spawner:Spawn()
end

--- Performs a single spawn of the specified SPAWN object in the specified `zone`.
function FMS.OpsArea:spawnInZone(spawner, zone)
	if zone then
		self.log:log("Spawning " .. spawner:GetGroupName() .. " in zone: " .. zone:GetName(), LOG.Level.DEBUG)
		self._lastSpawnCall = function() self:spawnInZone(spawner, zone) end
		return spawner:SpawnInZone(zone, true)
	end
end

function FMS.OpsArea:autoRespawnOn(delay_)
	self._autoRespawnDelay = delay_ or 0
	self.log:log("Setting Auto-Respawn to ON with delay="..tostring(self._autoRespawnDelay), LOG.Level.DEBUG)
end

function FMS.OpsArea:autoRespawnOff()
	self._autoRespawnDelay = nil
	self.log:log("Setting Auto-Respawn to OFF", LOG.Level.DEBUG)
end

function FMS.OpsArea:spawnInRandomZone(spawner)
	self:spawnInZone(spawner, table.randelement(self._spawnZones))
	self._lastSpawnCall = function() self:spawnInRandomZone(spawner) end
end

function FMS.OpsArea:spawnRandomGroupInZone(zone)
	self:spawnInZone(table.randelement(self._spawners), zone)
	self._lastSpawnCall = function() self:spawnRandomGroupInZone(zone) end
end

function FMS.OpsArea:spawnRandomGroupInRandomZone()
	local randomGroup = table.randelement(self._spawners)
	local randomZone = table.randelement(self._spawnZones)
	self:spawnInZone(randomGroup, randomZone)
	self._lastSpawnCall = function() self:spawnRandomGroupInRandomZone() end
end

--- Destroys all units within the specified `zone`.
function FMS.OpsArea:destroyAllInZone( zone, coalitions_ )
	self.log:log("Destroying all units in zone.", LOG.Level.INFO)
	local coals = coalitions_ or {"red", "blue", "neutral"}

	SET_GROUP:New()
		:FilterZones({zone})
		:FilterCoalitions(coals)
		:FilterActive(true)
		:FilterOnce()
		:ForEachGroup(function(_grp) _grp:Destroy(false) end)

	SET_STATIC:New()
		:FilterZones({zone})
		:FilterCoalitions(coals)
		:FilterOnce()
		:ForEachStatic(function(_stc) _stc:Destroy(false) end)
end

--- Destroys all alive groups that have been spawned in by one of this AO's spawners.
-- coalition_ is an optional param of type `coalition.side` (e.g. coalition.side.RED)
function FMS.OpsArea:destroySpawnedGroups(coalition_)
	if coalition_ then
		self.log:log("Destroying all alive spawned groups in coalition " .. coalition_)
	else
		self.log:log("Destroying all alive spawned groups")
	end

	for groupName, spawner in pairs(self._spawners) do
		spawner:ForEachAliveGroup(function(group)
			if coalition_ then
				if group:GetCoalition() == coalition_ then
					group:Destroy(false)
				end
			else
				group:Destroy(false)
			end
		end)
	end
end

function FMS.OpsArea:isAlive()
	for groupName, spawner in pairs(self._spawners) do
		if spawner:HasAliveGroups() then
			return true
		end
	end
	return false
end

function FMS.OpsArea:_removeJunk()
	self.log:log("Calling `world.removeJunk()`")
	
	if not self.zone then return end

	local radius = self.zone:GetRadius()
	local vec3 = self.zone:GetVec3()
	local volS = {
		id = world.VolumeType.SPHERE,
		params = {point = vec3, radius = radius}
	}
	local n = world.removeJunk(volS)
	self.log:log("removeJunk - removed objects count: ".. n)
end

-- Designed to be called as a SPAWN object's OnGroupSpawn handler
function FMS.OpsArea:_afterSpawnGroup(_spawnedGroup)
	-- TODO: A more robust system for tracking whether the range is alive/hot/etc
	self.alive = true

	self.log:log("Spawned " .. _spawnedGroup:GetName(), LOG.Level.TRACE)

	-- TODO: There has got to be a better way to determine if an entire group is dead!
	local ao = self
	_spawnedGroup:HandleEvent(EVENTS.Dead)
	function _spawnedGroup:OnEventDead( EventData )
		if EventData.IniGroup == _spawnedGroup then
			ao.log:log("Death in group: " .. _spawnedGroup:GetName() .. " (" .. _spawnedGroup:CountAliveUnits() .. " alive units)", LOG.Level.TRACE)
			ao.log:log("  - Unit: " .. EventData.IniUnit:GetName(), LOG.Level.TRACE)
			
			if not EventData.IniGroup:IsAlive() then
				-- Unhandle the event, so we don't keep getting notified everytime a unit dies.
				_spawnedGroup:UnHandleEvent(EVENTS.Dead)

				ao.log:log("GROUP DEAD: " .. _spawnedGroup:GetName(), LOG.Level.DEBUG)
				FMS.CallHandler(ao._onAfterGroupDeadHandler, ao, _spawnedGroup)

				if ao.alive and ( not ao:isAlive() ) then
					ao:_handleAfterRangeDead()
				end
			end
		end
	end

	FMS.CallHandler(self._onAfterGroupSpawnedHandler, self, _spawnedGroup)
end

function FMS.OpsArea:_handleAfterRangeDead()
	self.alive = false
	self.log:log("All groups dead.", LOG.Level.DEBUG)
	FMS.CallHandler(self._onAfterAllDeadHandler, self)

	self:removeMapMarker()

	-- Handle Autorespawn
	if self._autoRespawnDelay then
		self.log:log("Auto-respawning range in " .. tostring(self._autoRespawnDelay) .. " seconds.")

		local function doRespawn()
			self.log:log("Auto-respawning range now.")
			if self._lastSpawnCall then self._lastSpawnCall() end
		end

		if self._autoRespawnDelay > 0 then
			TIMER:New(doRespawn):Start(self._autoRespawnDelay or 10)
		else
			doRespawn()
		end
	end
end

-------------------------------------------------------------------------------
-- EVENT HANDLERS
-------------------------------------------------------------------------------

--- A handler that is called after a group is spawned.
-- First parameter is this OpsArea.
-- Second parameter is the spawned group.
function FMS.OpsArea:onAfterGroupSpawned(afterGroupSpawnFunction)
	self._onAfterGroupSpawnedHandler = afterGroupSpawnFunction
end

--- A handler that is called after a group dies.
-- First parameter is this OpsArea.
-- Second parameter is the dead group.
function FMS.OpsArea:onAfterGroupDead(afterGroupDeadFunction)
	self._onAfterGroupDeadHandler = afterGroupDeadFunction
end

--- A handler that is called after every group in this OpsArea dies.
-- First parameter is this OpsArea.
function FMS.OpsArea:onAfterAllDead(afterAllDeadFunction)
	self._onAfterAllDeadHandler = afterAllDeadFunction
end






local function BuildAliveGroupMenu(parentMenu, group)
	if not group then return end
	
	local groupMenu = MENU_MISSION:New(group:GetName(), parentMenu)
	
	MENU_MISSION_COMMAND:New("Destroy", groupMenu, function()
		group:Destroy()
		groupMenu:Remove()

		MESSAGE:New("Destroyed Group: " .. group:GetName(), 5):ToAll()
	end)
	
	MENU_MISSION_COMMAND:New("Explode", groupMenu, function()
		group:Explode(100, 0)
		MESSAGE:New("Exploding Group: " .. group:GetName(), 5):ToAll()
	end)
	
	return groupMenu
end
