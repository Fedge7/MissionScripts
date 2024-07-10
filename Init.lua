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
	HeloOpsConfig   = {name="HeloOpsConfig",   path="FMS\\HeloOpsConfig.lua"},
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
	},
	RequiredScripts = {
		fedgelib        = {name="fedgelib",        path="FMS\\fedgelib\\fedgelib.lua"},
		KeyMap          = {name="KeyMap",          path="FMS\\fedgelib\\KeyMap.lua"},
	}
}

function FMS.INIT(missionDirectory, pathToFMS_, pathToMOOSE_)

	if not missionDirectory then
		FMS.error("Cannot initialize FMS without a `missionDirectory`. Aborting FMS Initialization.")
		return false
	end

	FMS.MISSION_DIR = missionDirectory

	FMS.info("Initializing Fedge Mission Scripts (FMS).")

	local initialized = true

	-- Attempt to load MOOSE, if not already loaded.
	if FMS._init.CheckForMOOSE() then
		FMS.info("FMS: MOOSE already loaded.", true)
	else
		local moosepath = pathToMOOSE_ or "MOOSE_INCLUDE\\Moose_Include_Static\\Moose.lua"
		FMS.info("FMS: Loading MOOSE from " .. moosepath, true)
		if FMS.LOAD(moosepath) then
			initialized = initialized and true
		else
			FMS.error("FMS: Failed to dynamically load MOOSE. Aborting FMS Initialization.")
			return false
		end
	end

	FMS._init.ConfigureMOOSE()

	FMS.info("FMS: Loading Required FMS Modules.", true)
	for _, mod in pairs(FMS._init.RequiredModules) do
		local moduleLoaded = FMS.LoadModule(mod.name)
		if not moduleLoaded then
			FMS.error("FMS: Failed to load module ["..mod.name.."] from path: "..mod.path)
		end
		initialized = initialized and moduleLoaded
	end

	FMS.info("FMS: Loading Required FMS Scripts.", true)
	for _, mod in pairs(FMS._init.RequiredScripts) do
		local scriptLoaded = FMS.LOAD(mod.path)
		initialized = initialized and scriptLoaded
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

function FMS.INIT_STATIC()
	FMS.info("Initializing Fedge Mission Scripts (FMS) STATICALLY.")

	local initialized = true

	-- Attempt to load MOOSE, if not already loaded.
	if not FMS._init.CheckForMOOSE() then
		FMS.info("FMS: MOOSE not found. Include it as a 'Do Script File' action in the ME.", true)
	end

	FMS._init.ConfigureMOOSE()

	FMS.info("FMS: Checking Required FMS Modules.", true)
	for _, mod in pairs(FMS._init.RequiredModules) do
		local moduleLoaded = FMS.CheckForModule(mod.name)
		if not moduleLoaded then
			FMS.error("FMS: Failed to locate module ["..mod.name.."]")
		end
		initialized = initialized and moduleLoaded
	end

	FMS.info("FMS: Checking Required FMS Scripts.", true)
	for _, mod in pairs(FMS._init.RequiredScripts) do
		-- local status, result = FMS.LOAD(mod.path)
		-- initialized = initialized and status
		env.info("FMS: Required script ["..mod.name.."] expected to be included in MIZ.")
	end
	
	local msg = "FMS: Fedge Mission Scripts Initialization: STATIC "
	msg = msg .. (initialized and "SUCCESS" or "FAILURE")

	if initialized then
		FMS.info(msg)
	else
		FMS.error(msg)
	end

	FMS.INITIALIZED = initialized
	return initialized
end

function FMS.CheckForModule(fmsModuleOrModuleName)
	if type(fmsModuleOrModuleName) == 'string' then
		return FMS[fmsModuleOrModuleName] ~= nil
	elseif type(fmsModuleOrModuleName) == 'table' and fmsModuleOrModuleName.name and fmsModuleOrModuleName.path then
		return FMS[fmsModuleOrModuleName.name] ~= nil
	end
end

--- Returns an absolute path string for the given relativePath, relative to the FMS.MISSION_DIR.
function FMS.PATH(relativePath)
	return FMS.MISSION_DIR .. "\\" .. relativePath
end

--- Runs a lua file at the given relative path, relative to the FMS.MISSION_DIR.
function FMS.LOAD(relativePath)
	local filePath = FMS.PATH(relativePath)
	env.info("FMS.LOAD<" .. filePath .. ">")

	local f, error = loadfile(filePath)
	if f then
		f()
		return true
	else
		env.error("FMS.LOAD ERROR -- " .. tostring(error))
		return false
	end
end

function FMS._init.CheckForMOOSE()
	return MOOSE_DEVELOPMENT_FOLDER ~= nil
end

function FMS._init.ConfigureMOOSE()
	FMS.info("FMS: Configuring MOOSE.", true)
	_SETTINGS:SetPlayerMenuOff()
	_SETTINGS:SetMGRS_Accuracy( 4 )
	if false then -- debug logging
		BASE:TraceAll(true)
		BASE:TraceOn()
	end
end

-- LOGGING --------------------------------------------------------------------

function FMS.error(msg)   trigger.action.outText(msg, 60); env.error(msg)   end

function FMS.warning(msg) trigger.action.outText(msg, 30); env.warning(msg) end

function FMS.info(msg, hide)
	if not hide then trigger.action.outText(msg, 20) end
	env.info(msg)
end

function FMS.debug(msg) env.info(msg) end