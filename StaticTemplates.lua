--[[
FMS StaticTemplates Module
Author: Fedge

Description:
	Common functions for loading and manipulating static templates.

Dependencies:
	- MOOSE

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

function FMS.RegisterSTM(templateName, missionDirPath, groupHandler_, staticHandler_)
	_info("RegisterSTM(".. (templateName or ("nil")) ..")")
	
	local stmTable = _G[templateName]
	if stmTable then
		_debug("  - Found global variable named "..templateName..". Registering template from memory.")
		-- Register the table in the global namespace named `templateName` into the MOOSE database
		FMS.RegisterSTMTable(stmTable, groupHandler_, staticHandler_)
	else
		local fullPath = ""
		if missionDirPath then fullPath = missionDirPath .. "\\" end
		FMS.RegisterSTMFile(FMS.PATH(fullPath .. templateName .. ".stm"), groupHandler_, staticHandler_)
	end
end

function FMS.SpawnSTM(templateName, missionDirPath)
	_info("SpawnSTM(".. (templateName or ("nil")) ..")")
	
	local stmTable = _G[templateName]
	if stmTable then
		_debug("  - Found global variable named "..templateName..". Spawning template from memory.")
		-- Spawn the table in the global namespace named `templateName` into the mission
		FMS.SpawnSTMTable(stmTable)
	else
		local fullPath = ""
		if missionDirPath then fullPath = missionDirPath .. "\\" end
		FMS.SpawnSTMFile(FMS.PATH(fullPath .. templateName .. ".stm"))
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
function FMS.RegisterSTMFile( absolutePath, groupHandler_, staticHandler_ )
	FMS._UsingLoadedSTMFile(absolutePath, function()
		FMS.RegisterSTMTable(staticTemplate, groupHandler_, staticHandler_)
	end)
end

--- Spawns the contents of the STM file at the specified path
function FMS.SpawnSTMFile( absolutePath )
	_info("SpawnSTMFile <" .. absolutePath .. ">")

	FMS._UsingLoadedSTMFile(absolutePath, function()
		FMS.SpawnSTMTable(staticTemplate)
	end)
end

-------------------------------------------------------------------------------
-- TABLE FUNCTIONS
-------------------------------------------------------------------------------

--- Registers the contents of the specified stmTable in the MOOSE database
function FMS.RegisterSTMTable( stmTable, groupHandler_, staticHandler_ )
	_debug("RegisterSTMTable()")

	if (not stmTable) or (type(stmTable) ~= "table") then
		env.error("Unable to register STM table.")
		return
	end

	FMS._TraverseSTMTable(stmTable,
		function(vehicleGroupTable, category, coalitionId, countryId)
			-- TODO: Do we need to reset the groupId or unitId here?

			-- NOTE: NewTemplate() doesn't actually produce a useable DCS Group object.
			--       It only makes a MOOSE GROUP object. For the purposes of spawning in groups,
			--       or doing anything that requires access to the group's units, we need to call
			--       _DATABASE:Spawn() so that the group is actually realized within the DCS runtime.
			-- GROUP:NewTemplate(vehicleGroupTable, coalitionId, category, countryId)
			
			-- The DATABASE:Spawn() method requires the group table to have the following 2 properties defined
			vehicleGroupTable.CountryID = countryId
			vehicleGroupTable.CategoryID = category

			-- We'll set lateActivation to true here, just in case the template itself "forgot" to set it.
			-- This inherently assumes the user doesn't want to immediately spawn the template.
			vehicleGroupTable.lateActivation = true

			local grp = _DATABASE:Spawn(vehicleGroupTable)
			_trace("_DATABASE:Spawn() '"..grp:GetName().."'  [id_ = "..grp:GetDCSObject()["id_"].."]")
			if groupHandler_ then groupHandler_(vehicleGroupTable, category, coalitionId, countryId) end
		end,

		function(staticGroupTable, coalitionId, countryId)
			-- We have to set a new unitId here because the id in the STM file may collide with with ids present in the actual mission/miz file
			staticGroupTable.units[1].unitId = FMS.GetUniqueStaticID()
			_DATABASE:_RegisterStaticTemplate(staticGroupTable, coalitionId, category, countryId)
			if staticHandler_ then staticHandler_(staticGroupTable, coalitionId, countryId) end
		end
	)
end

--- Registers the contents of the specified stmTable in the MOOSE database
function FMS.RegisterSTMTableLateActivated( stmTable, groupHandler_, staticHandler_ )
	_debug("RegisterSTMTableLateActivated()")

	if (not stmTable) or (type(stmTable) ~= "table") then
		env.error("Unable to register STM table.")
		return
	end

	FMS._TraverseSTMTable(stmTable,
		function(vehicleGroupTable, category, coalitionId, countryId)
			vehicleGroupTable.lateActivated = true
			-- The DATABASE:Spawn() method requires the group table to have the following 2 properties defined
			vehicleGroupTable.CountryID = countryId
			vehicleGroupTable.CategoryID = category

			local grp = _DATABASE:Spawn(vehicleGroupTable)
			_trace("_DATABASE:Spawn() '"..grp:GetName().."'  [id_ = "..grp:GetDCSObject()["id_"].."]")
			if groupHandler_ then groupHandler_(vehicleGroupTable, category, coalitionId, countryId) end
		end,

		function(staticGroupTable, coalitionId, countryId)
			-- We have to set a new unitId here because the id in the STM file may collide with with ids present in the actual mission/miz file
			staticGroupTable.units[1].unitId = FMS.GetUniqueStaticID()
			_DATABASE:_RegisterStaticTemplate(staticGroupTable, coalitionId, category, countryId)
			if staticHandler_ then staticHandler_(staticGroupTable, coalitionId, countryId) end
		end
	)
end

--- Spawns the contents of the specified STM lua table.
function FMS.SpawnSTMTable( stmTable )
	_info("SpawnSTMTable()")

	if (not stmTable) or (type(stmTable) ~= "table") then
		env.error("Unable to spawn STM table.")
		return
	end

	FMS._TraverseSTMTable(stmTable,
		function(vehicleGroupTable, category, coalitionId, countryId)
			-- _DATABASE:_RegisterGroupTemplate(vehicleGroupTable, coalitionId, category, countryId)
			GROUP:NewTemplate(vehicleGroupTable, coalitionId, category, countryId)
			SPAWN:New(vehicleGroupTable.name):Spawn()
		end,

		function(staticGroupTable, coalitionId, countryId)
			local unitTable = staticGroupTable.units[1]

			-- We have to set a new unitId here because the id in the STM file may collide with with ids present in the actual mission/miz file
			unitTable.unitId = FMS.GetUniqueStaticID()
			local spwn = SPAWNSTATIC:NewFromTemplate(unitTable)
			spwn:Spawn()
		end
	)
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
	FMS._UsingLoadedSTMFile(absolutePath, function()
		FMS._TraverseSTMTable(staticTemplate, groupHandler_, staticHandler_)
	end)
end

--- Traverses the specified STM lua table
function FMS._TraverseSTMTable( stmTable, groupHandler_, staticHandler_ )

	if (not stmTable) or (type(stmTable) ~= "table") then
		env.error("FMS._TraverseSTMTable() cannot find a valid lua table.")
		return
	end

	for coalitionName, coalitionTable in pairs(stmTable.coalition) do
		_debug("STMPARSE: Processing coalition '"..coalitionName.."'")
		local coalitionId = FMS.StaticTemplates.CoalitionIdForString(coalitionName)
		
		if type(coalitionTable) == 'table' and coalitionTable.country then
			for _,countryTable in pairs(coalitionTable.country) do
				_debug("STMPARSE: Processing country '" .. countryTable.name .. "'")

				if type(countryTable) == 'table' then
					local countryId = countryTable.id or country.id.USA
					local countryName = countryTable.name or "USA"
					for countryTableProperty, countryTableTable in pairs(countryTable) do
						_debug("STMPARSE: countryTableProperty=" .. countryTableProperty)
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
								_debug("STMPARSE: groupTemplate.name=" .. groupTemplate.name)
								if groupTemplate and groupTemplate.units and type(groupTemplate.units) == 'table' then

									if categoryName ~= "static" then
										if groupHandler_ and type(groupHandler_) == "function" then
											groupHandler_(groupTemplate, category, coalitionId, countryId)
										end
									else
										if staticHandler_ and type(staticHandler_) == "function" then
											staticHandler_(groupTemplate, coalitionId, countryId)
										end
									end -- if static

								end -- if groupTemplate and groupTemplate.units then
							end -- for groupTemplate in categoryTable

						end -- if (group and group and group and group)
					end -- for countryTableTable in countryTable
				end -- if type(countryTable)
			end -- for countryTable in coalitionTable.country
		end -- if type(coalitionTable)
	end -- for coalitionName in staticTemplate.coalition

end -- FMS.RegisterSTMFile()

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
function FMS._UsingLoadedSTMFile( absolutePath, handler )
	_debug('_UsingLoadedSTMFile("'..absolutePath..'")')
	assert(loadfile(absolutePath))()
	if not staticTemplate then return end
	
	handler()

	-- cleanse the global namespace
	staticTemplate = nil
end

FMS.STATIC_ID = 1000000
function FMS.GetUniqueStaticID()
	FMS.STATIC_ID = FMS.STATIC_ID + 1
	return FMS.STATIC_ID
end
