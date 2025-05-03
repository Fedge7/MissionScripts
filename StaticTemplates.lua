--[[
FMS StaticTemplates Module
Author: Fedge

Description:
	Common functions for loading and manipulating static templates.

Dependencies:
	- MOOSE
	- FMS.Utilities

]]

if not FMS then FMS = {} end
FMS.StaticTemplates = {}

-------------------------------------------------------------------------------
-- LOGGING
-------------------------------------------------------------------------------
FMS.StaticTemplates.LOG_LEVEL = {ERROR=1, WARNING=2, INFO=3, DEBUG=4, TRACE=5}
FMS.StaticTemplates.THRESHOLD = FMS.StaticTemplates.LOG_LEVEL.INFO
local function _lg(msg, level)
	if (level or FMS.StaticTemplates.LOG_LEVEL.INFO) <= FMS.StaticTemplates.THRESHOLD then env.info("FMS.STM:"..msg) end
end
local function _info(msg)  _lg(msg, FMS.StaticTemplates.LOG_LEVEL.INFO) end
local function _debug(msg) _lg(msg, FMS.StaticTemplates.LOG_LEVEL.DEBUG) end
local function _trace(msg) _lg(msg, FMS.StaticTemplates.LOG_LEVEL.TRACE) end

-------------------------------------------------------------------------------
-- UNIVERSAL FUNCTIONS
-------------------------------------------------------------------------------

function FMS.RegisterSTM(templateName, missionDirPath, groupHandler_, staticHandler_, lateActivation_)
	_info("RegisterSTM(".. (templateName or ("nil")) ..", lateActivation_=" .. dump(lateActivation_) ..")")

	local stmTable = _G[templateName]
	if stmTable then
		_debug("  - Found global variable named "..templateName..". Registering template from memory.")
		-- Register the table in the global namespace named `templateName` into the MOOSE database
		FMS.RegisterSTMTable(stmTable, groupHandler_, staticHandler_, lateActivation_)
	else
		local fullPath = ""
		if missionDirPath then fullPath = missionDirPath .. "\\" end
		FMS.RegisterSTMFile(FMS.PATH(fullPath .. templateName .. ".stm"), groupHandler_, staticHandler_, lateActivation_)
	end
end

function FMS.SpawnSTM(templateName, missionDirPath, spawnedHandler_)
	_info("SpawnSTM(".. (templateName or ("nil")) ..")")
	
	local stmTable = _G[templateName]
	if stmTable then
		_debug("  - Found global variable named "..templateName..". Spawning template from memory.")
		-- Spawn the table in the global namespace named `templateName` into the mission
		FMS.SpawnSTMTable(stmTable, spawnedHandler_)
	else
		local fullPath = ""
		if missionDirPath then fullPath = missionDirPath .. "\\" end
		FMS.SpawnSTMFile(FMS.PATH(fullPath .. templateName .. ".stm"), spawnedHandler_)
	end
end

function FMS.TraverseSTM(templateName, missionDirPath, groupHandler_, staticHandler_)
	_info("TraverseSTM(".. (templateName or ("nil")) ..")")
	
	local stmTable = _G[templateName]
	if stmTable then
		_debug("  - Found global variable named "..templateName..". Traversing template from memory.")
		-- Traverse the table in the global namespace named `templateName`
		FMS._TraverseSTMTable(stmTable, groupHandler_, staticHandler_)
	else
		local fullPath = ""
		if missionDirPath then fullPath = missionDirPath .. "\\" end
		FMS._TraverseSTMFile(FMS.PATH(fullPath .. templateName .. ".stm"), groupHandler_, staticHandler_)
	end
end

function FMS.SpawnSTMAtVec2(templateName, missionDirPath, vec2, spawnedHandler_)
	_info("SpawnSTMAtVec2(".. (templateName or ("nil")) ..")")
	
	local stmTable = _G[templateName]
	if stmTable then
		_debug("  - Found global variable named "..templateName..". Spawning template from memory.")
		-- Spawn the table in the global namespace named `templateName` into the mission
		FMS.SpawnSTMTableAtVec2(stmTable, vec2, spawnedHandler_)
	else
		local fullPath = ""
		if missionDirPath then fullPath = missionDirPath .. "\\" end
		FMS.SpawnSTMFileAtVec2(FMS.PATH(fullPath .. templateName .. ".stm"), vec2, spawnedHandler_)
	end
end

-------------------------------------------------------------------------------
-- FILE FUNCTIONS
-------------------------------------------------------------------------------

--- Registers the STM file at the specified path in the MOOSE database
-- @param #string absolutePath The full absolute file path to the STM file to be registered.
-- @param #function groupHandler_ A function to be called for every group found in the template file.
-- @param #function staticHandler_ A function to be called for every static found in the template file.
-- NOTE: The group handler function accept the following ordered arguments:
--         1. the lua table defining the group, as defined in the static template
--         2. the group's category
--         3. the group's coalition ID
--         4. the group's country ID
--       The static handler function accepts the following ordered arguments:
--         1. the lua table defining the static, as defined in the static template
--         2. the static's coalition ID
--         3. the static's country ID
function FMS.RegisterSTMFile( absolutePath, groupHandler_, staticHandler_, lateActivation_ )
	_info("RegisterSTMFile <" .. absolutePath .. ">")
	local stmTable = FMS.LoadFileWithResult(absolutePath)
	FMS.RegisterSTMTable(stmTable, groupHandler_, staticHandler_, lateActivation_)
end

--- Spawns the contents of the STM file at the specified path
function FMS.SpawnSTMFile( absolutePath, spawnedHandler_ )
	_info("SpawnSTMFile  <" .. absolutePath .. ">")
	FMS.SpawnSTMTable(FMS.LoadFileWithResult(absolutePath), spawnedHandler_)
end

function FMS.SpawnSTMFileAtVec2( absolutePath, vec2, spawnedHandler_ )
	_info("SpawnSTMFileAtVec2  <" .. absolutePath .. ">")
	FMS.SpawnSTMTableAtVec2(FMS.LoadFileWithResult(absolutePath), vec2, spawnedHandler_)
end

-------------------------------------------------------------------------------
-- TABLE FUNCTIONS
-------------------------------------------------------------------------------

--- Registers the specified group template into the MOOSE database.
function FMS.DBSpawn(template, countryId, categoryId)
	-- The DATABASE:Spawn() method requires the group table to have the following 2 properties defined
	template.CountryID = countryId
	template.CategoryID = categoryId
	local grp = _DATABASE:Spawn(template)
	_debug("_DATABASE:Spawn() '"..grp:GetName().."'  [id_ = "..grp:GetDCSObject()["id_"].."]")
	return grp
end

--- Registers the contents of the specified stmTable in the MOOSE database
function FMS.RegisterSTMTable( stmTable, groupHandler_, staticHandler_, lateActivation_ )
	_debug("RegisterSTMTable(lateActivation_="..tostring(lateActivation_)..")")

	if (not stmTable) or (type(stmTable) ~= "table") then
		env.error("Unable to register STM table.")
		return
	end

	FMS._TraverseSTMTable(stmTable,
		function(vehicleGroupTable, category, coalitionId, countryId)

			-- NOTE: NewTemplate() doesn't actually produce a useable DCS Group object.
			--       It only makes a MOOSE GROUP object. For the purposes of spawning in groups,
			--       or doing anything that requires access to the group's units, we need to call
			--       _DATABASE:Spawn() so that the group is actually realized within the DCS runtime.
			-- GROUP:NewTemplate(vehicleGroupTable, coalitionId, category, countryId)
			
			if lateActivation_ ~= nil then
				-- Setting `.lateActivation` to false will immediately spawn the group in upon the _DATABASE:Spawn() call.
				-- A value of true will set the unit as late activated, as if the checkbox was checked in the ME.
				vehicleGroupTable.lateActivation = lateActivation_
				_trace("RegisterSTMTable() -- setting lateActivation to " .. tostring(lateActivation_))
			end

			-- TODO: Can we nil out the groupId and unitID here? UPDATE: Yes!
			-- We have to set a new groupId here because the id in the STM file may collide with with ids present in the actual mission/miz file
			vehicleGroupTable.groupId = nil --FMS.GetUniqueStaticID()
			for i, unit in pairs(vehicleGroupTable.units) do
				unit.unitId = nil --FMS.GetUniqueStaticID()
			end

			FMS.DBSpawn(vehicleGroupTable, countryId, category)
			FMS.CallHandler(groupHandler_, vehicleGroupTable, category, coalitionId, countryId)
		end,

		function(staticGroupTable, coalitionId, countryId)
			-- We have to set a new unitId here because the id in the STM file may collide with with ids present in the actual mission/miz file
			staticGroupTable.units[1].unitId = FMS.GetUniqueStaticID()
			_DATABASE:_RegisterStaticTemplate(staticGroupTable, coalitionId, category, countryId)
			_debug("_DATABASE:_RegisterStaticTemplate() name=" .. tostring(staticGroupTable.name) .. " with unitId=" .. tostring(staticGroupTable.units[1].unitId))
			FMS.CallHandler(staticHandler_, staticGroupTable, coalitionId, countryId)
		end
	)
end

--- Spawns the contents of the specified STM lua table.
function FMS.SpawnSTMTable( stmTable, spawnedHandler_ )
	_info("SpawnSTMTable()")

	if (not stmTable) or (type(stmTable) ~= "table") then
		env.error("Unable to spawn STM table.")
		return
	end

	FMS._TraverseSTMTable(stmTable,
		function(vehicleGroupTable, category, coalitionId, countryId)
			-- _DATABASE:_RegisterGroupTemplate(vehicleGroupTable, coalitionId, category, countryId)
			GROUP:NewTemplate(vehicleGroupTable, coalitionId, category, countryId)
			local spawned = SPAWN:New(vehicleGroupTable.name):Spawn()
			FMS.CallHandler(spawnedHandler_, spawned)
		end,

		function(staticGroupTable, coalitionId, countryId)
			local spawned = FMS.StaticTemplates._SpawnStatic(staticGroupTable, coalitionId, countryId)
			FMS.CallHandler(spawnedHandler_, spawned)
		end
	)
end

function FMS.SpawnSTMTableAtVec2( stmTable, vec2, spawnedHandler_ )
	_info("SpawnSTMTableAtVec2()")

	if (not stmTable) or (type(stmTable) ~= "table") then
		env.error("Unable to spawn STM table.")
		return
	end

	-- Get the first group in the stm table, so we can use its coordinate as our reference point.
	local firstGroup = FMS._GetFirstGroupOrStaticInSTMTable(stmTable, "blue", "vehicle")

	local firstVec2 = {x = firstGroup.x, y = firstGroup.y}
	local offset = {
		x = vec2.x - firstVec2.x,
		y = vec2.y - firstVec2.y
	}

	FMS._TraverseSTMTable(stmTable,
		function(vehicleGroupTable, category, coalitionId, countryId)
			local groupVec2 = {
				x = vehicleGroupTable.x + offset.x,
				y = vehicleGroupTable.y + offset.y
			}
			-- _DATABASE:_RegisterGroupTemplate(vehicleGroupTable, coalitionId, category, countryId)
			GROUP:NewTemplate(vehicleGroupTable, coalitionId, category, countryId)
			local spawned = SPAWN:New(vehicleGroupTable.name):SpawnFromVec2(groupVec2)
			FMS.CallHandler(spawnedHandler_, spawned)
		end,

		function(staticGroupTable, coalitionId, countryId)
			local groupVec2 = {
				x = staticGroupTable.x + offset.x,
				y = staticGroupTable.y + offset.y
			}

			-- Rotate the entire STM table, using the firstVec2 as a pivot
			-- local rotatedVec2 = UTILS.RotatePointAroundPivot(groupVec2, firstVec2, 90)
			-- local newCoord = COORDINATE:NewFromVec2(rotatedVec2)

			local newCoord = COORDINATE:NewFromVec2(groupVec2)

			-- Since we don't have handle on the SPAWNSTATIC objects created from any previous attempts to spawn
			-- these statics, we need to guarantee that they have a unique name, otherwise they'll despawn the
			-- previously spawned static object. So we'll just append a monotonically-increasing counter to the name.
			-- This is lazy. And performant.
			local newName = staticGroupTable.name .. "_" .. tostring(FMS.StaticTemplates._GetUniqueCounter())

			local spawned = FMS.StaticTemplates._SpawnStatic(staticGroupTable, coalitionId, countryId, newName, newCoord)
			FMS.CallHandler(spawnedHandler_, spawned)
		end
	)
end

function FMS.StaticTemplates._SpawnStatic(staticGroupTable, coalitionId, countryId, newName_, coordinate_)
	_debug("FMS.StaticTemplates._SpawnStatic()")
	local unitTable = staticGroupTable.units[1]

	-- We have to set a new unitId here because the id in the STM file may collide with with ids present in the actual mission/miz file
	unitTable.unitId = FMS.GetUniqueStaticID()
	local spwn = SPAWNSTATIC:NewFromTemplate(unitTable, countryId)
	local spawnedStatic = nil
	if coordinate_ then
		spawnedStatic = spwn:SpawnFromCoordinate(coordinate_, nil, newName_)
	else
		spawnedStatic = spwn:Spawn(nil, newName_)
	end

	if spawnedStatic then
		_debug("  - Spawned STATIC: " .. tostring(spawnedStatic:GetName()))
		return spawnedStatic
	elseif staticGroupTable and staticGroupTable.name then
		_lg("  -  Couldn't find spawnedStatic for static table named '"..staticGroupTable.name.."'", FMS.StaticTemplates.LOG_LEVEL.ERROR)
	else
		_lg("  -  Couldn't find spawnedStatic", FMS.StaticTemplates.LOG_LEVEL.ERROR)
	end
end

-------------------------------------------------------------------------------
-- LATEST staticTemplate FUNCTIONS
-------------------------------------------------------------------------------

--- Registers the contents of the global `staticTemplate` variable in the MOOSE database
function FMS.RegisterLatestStaticTemplate( groupHandler_, staticHandler_ )
	if not staticTemplate then return end
	
	FMS.RegisterSTMTable(staticTemplate, groupHandler_, staticHandler_)

	-- cleanse the global namespace
	staticTemplate = nil
end

--- Registers the contents of the global `staticTemplate` variable in the MOOSE database
function FMS.SpawnLatestStaticTemplate( groupHandler_, staticHandler_ )
	if not staticTemplate then return end
	
	FMS.SpawnSTMTable(staticTemplate, groupHandler_, staticHandler_)

	-- cleanse the global namespace
	staticTemplate = nil
end

-------------------------------------------------------------------------------
-- TRAVERSAL FUNCTIONS
-------------------------------------------------------------------------------

--- Traverses the STM file at the specified path.
function FMS._TraverseSTMFile( absolutePath, groupHandler_, staticHandler_ )
	_info("_TraverseSTMFile <" .. absolutePath .. ">")
	local stmTable = FMS.LoadFileWithResult(absolutePath, true)
	FMS._TraverseSTMTable(stmTable, groupHandler_, staticHandler_)
end

--- Traverses the specified STM lua table and calls a specific handler for each group or static.
function FMS._TraverseSTMTable( stmTable, groupHandler_, staticHandler_ )
	_info("_TraverseSTMTable()")
	FMS._TraverseSTMGroups( stmTable,
		function(groupTemplate, category, coalitionId, countryId)
			if groupTemplate and groupTemplate.units and type(groupTemplate.units) == 'table' then
				if category ~= Unit.Category.STRUCTURE then
					if groupHandler_ and type(groupHandler_) == "function" then
						return groupHandler_(groupTemplate, category, coalitionId, countryId)
					end
				else
					if staticHandler_ and type(staticHandler_) == "function" then
						return staticHandler_(groupTemplate, coalitionId, countryId)
					end
				end
			end
		end
	)
end -- FMS._TraverseSTMTable()

--- Traverses the specified STM lua table and calls a handler for each group found
function FMS._TraverseSTMGroups( stmTable, groupHandler_ )

	if (not stmTable) or (type(stmTable) ~= "table") then
		env.error("FMS._TraverseSTMGroups() cannot find a valid lua table.")
		return
	end

	local continue = true

	for coalitionName, coalitionTable in pairs(stmTable.coalition) do
		_trace("STMPARSE: Processing coalition '"..coalitionName.."'")
		local coalitionId = FMS.StaticTemplates.CoalitionIdForString(coalitionName)
		
		if type(coalitionTable) == 'table' and coalitionTable.country then
			for _,countryTable in pairs(coalitionTable.country) do
				_trace("STMPARSE: Processing country '" .. countryTable.name .. "'")

				if type(countryTable) == 'table' then
					local countryId = countryTable.id or country.id.USA
					local countryName = countryTable.name or "USA"
					for countryTableProperty, countryTableTable in pairs(countryTable) do
						_trace("STMPARSE: countryTableProperty=" .. countryTableProperty)
						if (
							(type(countryTableTable) == 'table')
							and countryTableTable.group
							and (type(countryTableTable.group) == 'table')
							and (#countryTableTable.group > 0)
							) then

							local categoryName = countryTableProperty
							local categoryTable = countryTableTable.group
							local category = FMS.StaticTemplates.UnitCategories[string.lower(categoryName)]

							for _,groupTemplate in pairs(categoryTable) do
								if groupTemplate  then
									_debug("STMPARSE: groupTemplate.name=" .. groupTemplate.name)
									continue = groupHandler_(groupTemplate, category, coalitionId, countryId)
									if continue == false then return end
								end -- if groupTemplate
							end -- for groupTemplate in categoryTable

						end -- if (group and group and group and group)
					end -- for countryTableTable in countryTable
				end -- if type(countryTable)
			end -- for countryTable in coalitionTable.country
		end -- if type(coalitionTable)
	end -- for coalitionName in staticTemplate.coalition

end -- FMS._TraverseSTMGroups()

function FMS._GetFirstGroupOrStaticInSTMTable(stmTable, coalition_, categoryName_)
	local coalition = coalition_ or "blue"
	local firstCountryTable = stmTable.coalition[coalition].country[1]
	local categoryTable = firstCountryTable[categoryName_]
	
	if not categoryTable then
		local categoryPrecedence = {"plane", "helicopter", "ship", "vehicle", "static"}
		for _,category in ipairs(categoryPrecedence) do
			if firstCountryTable[category] ~= nil then
				categoryTable = firstCountryTable[category]
				break
			end
		end
	end

	if not categoryTable then return nil end
	
	local groups = categoryTable.group
	return groups[1]
end

-------------------------------------------------------------------------------
-- HELPER FUNCTIONS
-------------------------------------------------------------------------------

--- Returns the DCS#coalition.side for the specified coalitionName
-- @param #string coalitionName The name of the coalition (i.e. "red" or "blue")
-- @return DCS#coalition.side The coalition side for the specified coalition string
function FMS.StaticTemplates.CoalitionIdForString(coalitionName)
	local _coalitionName = string.lower(coalitionName)
	if _coalitionName == "red" then return coalition.side.RED
	elseif _coalitionName == "blue" then return coalition.side.BLUE
	else return coalition.side.NEUTRAL
	end
end

--- A dictionary mapping unit category strings/names to the DCS#Unit.Category values
FMS.StaticTemplates.UnitCategories = {
	["plane"] = Unit.Category.AIRPLANE,
	["helicopter"] = Unit.Category.HELICOPTER,
	["vehicle"] = Unit.Category.GROUND_UNIT,
	["ship"] = Unit.Category.SHIP,
	["static"] = Unit.Category.STRUCTURE,
}

--- Loads a static template file (.stm), calls the specified handler, and finally sets the global `staticTemplate` variable to nil.
-- @param #string absolutePath The full absolute file path to the STM file to be loaded.
-- @param #function handler A function to be called after the static template file is loaded in the `staticTemplate` global variable.
-- @note This function has been deprecated in favor of FMS.LoadFileWithResult()
function FMS._UsingLoadedSTMFile( absolutePath, handler )
	_debug('_UsingLoadedSTMFile("'..absolutePath..'")')
	assert(loadfile(absolutePath))()
	if not staticTemplate then return end
	
	handler()

	-- cleanse the global namespace
	staticTemplate = nil
end

FMS.STATIC_ID = 2000000
function FMS.GetUniqueStaticID()
	FMS.STATIC_ID = FMS.STATIC_ID + 1
	return FMS.STATIC_ID
end

FMS.StaticTemplates.UniqueCounter = 1
function FMS.StaticTemplates._GetUniqueCounter()
	FMS.StaticTemplates.UniqueCounter = FMS.StaticTemplates.UniqueCounter + 1
	return FMS.StaticTemplates.UniqueCounter
end
