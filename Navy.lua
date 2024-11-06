if not FMS then FMS = {} end
FMS.Navy = {}

--- Configures the carriers' recovery tankers and rescue helicopters
-- @param #string carrierUnitName_ Name of the Carrier unit in the mission editor. (Optional, default is "Carrier")
-- @param #string recoveryTankerGroupName_ Name of the Recovery Tanker group in the mission editor. (Optional, default is "Recovery Tanker")
-- @param #string rescueHeloGroupName_ Name of the Recue Helo group in the mission editor. (Optional, default is nil for no helo.)
function FMS.Navy.SetupNavySupportAircraft(carrierUnitName_, recoveryTankerGroupName_, rescueHeloGroupName_)
	local carrierUnitName = carrierUnitName_ or "Carrier"
	local carrierUnit = UNIT:FindByName(carrierUnitName)

	if not carrierUnit then
		LOG:Log("Unable to find a carrier named '"..(carrierUnitName or 'nil').."'. Skipping initialization of navy support aircraft.", true, LOG.Level.ERROR)
		return false
	end

	local recoveryTankerGroupName = recoveryTankerGroupName_ or "Recovery Tanker"
	local tanker = FMS.Navy.SetupRecoveryTanker(carrierUnit, recoveryTankerGroupName, SPAWN.Takeoff.Air)

	local msg = "Recovery Tanker Initialization ("..recoveryTankerGroupName.."): "
	if tanker then
		LOG:Log(msg.."SUCCESS", true, LOG.Level.INFO)
	else
		LOG:Log(msg.."FAILURE", true, LOG.Level.ERROR)
	end

	if rescueHeloGroupName_ then
		-- must store RESCUEHELO objects in a global (see RESCUEHELO documentation)
		CarrierRescueHelo = FMS.Navy.SetupRescueHelo(carrierUnit, rescueHeloGroupName_, SPAWN.Takeoff.Air)

		local msg = "Rescue Helo Initialization ("..rescueHeloGroupName_.."): "
		if CarrierRescueHelo then
			LOG:Log(msg.."SUCCESS", true, LOG.Level.INFO)
		else
			LOG:Log(msg.."FAILURE", true, LOG.Level.ERROR)
		end
	else
		LOG:Log("Skipping Rescue Helo Initialization", true, LOG.Level.INFO)
	end
end

--- Sets up and spawns a recovery tanker for the given carrier unit
-- @param Wrapper.Unit#UNIT carrierUnit The carrier unit for which to attach a recovery tanker
-- @param #string groupTemplateName The name of the template group defined in the mission editor for the recovery tanker
-- @param #number takeoffType_ Takeoff type. (one of SPAWN.Takeoff.Hot, .Cold, .Air) (Optional, defaults to SPAWN.Takeoff.Air)
function FMS.Navy.SetupRecoveryTanker(carrierUnit, groupTemplateName, takeoffType_)
	local tanker = RECOVERYTANKER:New(carrierUnit, groupTemplateName)
	tanker:SetUnlimitedFuel(true)
	tanker:SetTakeoff(takeoffType_ or SPAWN.Takeoff.Air)

	-- If we spawned in the air, let's respawn in the air
	if takeoffType_ == SPAWN.Takeoff.Air then tanker:SetRespawnInAir() end

	env.info("NAVYGROUP: Starting RECOVERYTANKER: " .. groupTemplateName)
	tanker:__Start(2)
	return tanker
end

--- Sets up and spawns a rescue helicopter for the specified carrier unit
-- @param Wrapper.Unit#UNIT carrierUnit The carrier unit for which to attach a recovery tanker
-- @param #string groupTemplateName The name of the template group defined in the mission editor for the rescue helo
-- @param #number takeoffType_ Takeoff type. (one of SPAWN.Takeoff.Hot, .Cold, .Air) (Optional, defaults to SPAWN.Takeoff.Air)
function FMS.Navy.SetupRescueHelo(carrierUnit, groupTemplateName, takeoffType_) 
	local grp = GROUP:FindByName(groupTemplateName)
	if not grp then
		LOG:Log("Unable to find recovery helicopter group '"..groupTemplateName.."'", false, LOG.Level.WARNING)
		return
	end

	grp:CommandSetUnlimitedFuel(true)

	local helo = RESCUEHELO:New(carrierUnit, groupTemplateName)
	helo:SetTakeoff(takeoffType_ or SPAWN.Takeoff.Air)
	if takeoffType_ == SPAWN.Takeoff.Air then helo:SetRespawnInAir() end

	env.info("NAVYGROUP: Starting RESCUEHELO: " .. groupTemplateName)
	helo:Start()
 
	-- NOTE: it is very important to define the RESCUEHELO object as global variable.
	-- Otherwise, the lua garbage collector will kill the formation for unknown reasons!
	return helo
end