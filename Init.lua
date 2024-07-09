--[[
FMS Mission Environment Initialization
Author: Fedge

Description:
	Initializes the required scripts and globals for using FMS.
]]

FMS = {}

FMS.MODULES = {
	AirRange        = {name="AirRange",        path="FMS\\AirRange.lua"},
	HeloOps         = {name="HeloOps",         path="FMS\\HeloOps.lua"},
	Log             = {name="Log",             path="FMS\\Log.lua"},
	OpsArea         = {name="OpsArea",         path="FMS\\OpsArea.lua"},
	OpsMission      = {name="OpsMission",      path="FMS\\OpsMission.lua"},
	StaticTemplates = {name="StaticTemplates", path="FMS\\StaticTemplates.lua"},
	Utilities       = {name="Utilities",       path="FMS\\Utilities.lua"},
}

FMS._init = {
	RequiredModules = {
		FMS.MODULES.Log,
		FMS.MODULES.Utilities,
		FMS.MODULES.StaticTemplates,
	}
}

function FMS.INIT(missionDirectory, fmsDirectory)

	if not missionDirectory then
		FMS.error("Cannot initialize FMS without a `missionDirectory`. Halting initialization.")
		return
	end

	FMS.MISSION_DIR = missionDirectory

	FMS.info("Initializing Fedge Mission Scripts (FMS).")

	-- Attempt to load MOOSE, if not already loaded.
	if FMS._init.CheckForMOOSE() then
		env.info("FMS: MOOSE already loaded.")
	else
		function _loadMOOSE()
			FMS.info("FMS: Loading MOOSE.")
			FMS.LOAD("MOOSE_INCLUDE\\Moose_Include_Static\\Moose.lua") 
		end
		if not pcall(_loadMOOSE) then
			FMS.error("FMS: Failed to dynamically load MOOSE. Aborting mission load.")
			return false
		end
	end

	function _configureMOOSE()
		env.info("FMS: Configuring MOOSE.")
		_SETTINGS:SetPlayerMenuOff()
		_SETTINGS:SetMGRS_Accuracy( 4 )
		if false then -- debug logging
			BASE:TraceAll(true)
			BASE:TraceOn()
		end
	end
	
	_configureMOOSE()

	local initialized = true

	FMS.info("FMS: Loading Required FMS Modules.")
	for _, mod in pairs(FMS._init.RequiredModules) do
		local moduleLoaded = FMS.LoadModule(mod.name)
		if not moduleLoaded then
			FMS.error("FMS: Failed to load module ["..mod.name.."] from path: "..mod.path)
		end
		initialized = initialized and moduleLoaded
	end
	
	local msg = "FMS: Fedge Mission Scripts Initialization "
	msg = msg .. (initialized and "SUCCESS" or "FAILURE")

	if initialized then
		FMS.info(msg)
	else
		FMS.error(msg)
	end

	FMS.INITIALIZED = initialized
	return initialized
end

function FMS.LoadModule(fmsModuleOrModuleName, forceReload_)
	local mod = nil
	if type(fmsModuleOrModuleName) == 'string' then
		mod = FMS.MODULES[fmsModuleOrModuleName]
	elseif type(fmsModuleOrModuleName) == 'table' and fmsModuleOrModuleName.name and fmsModuleOrModuleName.path then
		mod = fmsModuleOrModuleName
	end
	
	if not mod then
		FMS.error("FMS: Cannot find FMS module.")
		return false
	end

	if FMS[mod.name] ~= nil then
		FMS.info("FMS: Module ["..mod.name.."] is already loaded.", true)
		if not forceReload_ then
			return true
		else
			FMS.info("FMS: Force-Reloading Module ["..mod.name.."].")
		end
	end

	FMS.info("FMS: Loading Module ["..mod.name.."].", true)
	FMS.LOAD(mod.path)
	return FMS[mod.name] ~= nil
end

--- Returns an absolute path string for the given relativePath, relative to the FMS.MISSION_DIR.
function FMS.PATH(relativePath)
	return FMS.MISSION_DIR .. "\\" .. relativePath
end

--- Runs a lua file at the given relative path, relative to the FMS.MISSION_DIR.
function FMS.LOAD(relativePath)
	local filePath = FMS.PATH(relativePath)
	env.info("FMS.LOAD<" .. filePath .. ">")
	local status, result = assert(loadfile(filePath))()
	return status, result
end

function FMS._init.CheckForMOOSE()
	return MOOSE_DEVELOPMENT_FOLDER ~= nil
end

function FMS._init.AssertMOOSE()
	if not FMS.CheckForMOOSE() then
		FMS.error("Unable to find MOOSE. Be sure to load Moose.lua in a 'Do Script File' trigger.")
		return false
	end
	return true
end

function FMS.error(msg)   trigger.action.outText(msg, 60); env.error(msg)   end

function FMS.warning(msg) trigger.action.outText(msg, 30); env.warning(msg) end

function FMS.info(msg, hide)
	if not hide then trigger.action.outText(msg, 20) end
	env.info(msg)
end

function FMS.debug(msg) env.info(msg) end