--[[
FMS Helicopter Operations Configuration
Author: Fedge

Description:
	This script contains many convenience functions for automatically configuring CTLD and CSAR instances,
	including the ability to register CTLD troops and vehicles from a template (stm) file.
]]

if (not FMS) or (not FMS.HeloOps) then
	local msg = "HeloOpsConfig: Cannot find FMS.HeloOps module."
	env.error(msg)
	trigger.action.outText(msg, 60)
end

FMS.HeloOpsConfig = {}

--- Applies the default configuration options to a CTLD instance
function CTLD:applyDefaultConfiguration()
	
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
	self.usesubcats = true
	--self.pilotmustopendoors = true
	
	-- Set unit capabilities for all helo units
	--                       Airframe          crates troops crates# troops# length maxwt
	self:SetUnitCapabilities("AH-64D_BLK_II",  false, false, 0,       0,     20,     200)
	self:SetUnitCapabilities("UH-60L",          true,  true, 1,      14,     25,    5000)
	
	self:SetUnitCapabilities("UH-1H",           true,  true, 1,       8,     20,    2000)
	self:SetUnitCapabilities("Mi-8MT",          true,  true, 2,      24,     30,   10000)
	self:SetUnitCapabilities("Mi-8MTV2",        true,  true, 2,      24,     30,   10000)
	-- Tweaked the max weights to allow for realistic overloading
	
	self:logINF("FMS default CTLD configuration and parameters applied.")
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

	-- Attempt to load a sidecar file with menu names, weights, counts, etc
	local sidecarFilePath = sidecarAbsolutePath_ or FMS.PATH(missionDirPath .. "\\" .. templateName .. ".lua")
	local troopsLookup = FMS.LoadfileWithResult(sidecarFilePath)

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
		end
	)
end

function CTLD:registerSTMFARP( stmTable, oa_path, FARPTemplateGroupName_ )
	
	local _FARPTemplateGroupName = FARPTemplateGroupName_ or "FARP"
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
		end
	)

	self:AddFARPCrates("FARP", _FARPTemplateGroupName, 2, 1500)
	self:ConfigureFARP(_FARPTemplateGroupName, _heliportStaticName, groupNames, staticNames, nil)

end

-- -----------------------------------------------------------------------------
-- CSAR
-- -----------------------------------------------------------------------------

function CSAR:applyDefaultConfiguration()
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
