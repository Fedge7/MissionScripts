--[[

	A simple lua logging framework for DCS
	Author: Fedge

]]

if FMS == nil then FMS = {} end
FMS.Log = {}

LOG = {
	Level = {
		PRI = 0,
		ERROR = 1,
		WARNING = 2,
		INFO = 3, INFO2 = 4,
		DEBUG = 5, DEBUG2 = 6,
		TRACE = 7, TRACE2 = 8
	}
}

LOG.Threshold = LOG.Level.TRACE2

function LOG:Log(message, showOnScreen_, level_, time_)
	local onScreen = showOnScreen_ or false
	local level = level_ or LOG.Level.INFO  
	local time = time_ or 10
	
	if level > LOG.Threshold then return end
	
	-- local timestamp = os.date("!%Y-%m-%dT%TZ")
	local timestamp = timer.getTime()
	outputMsg = string.format("LOG: %s | %d | %s", timestamp, level, message)
	
	if level == LOG.Level.ERROR then
		env.error(outputMsg, false)
	elseif level == LOG.Level.WARNING then
		env.warning(outputMsg, false)
	else
		env.info(outputMsg, false)
	end
	
	if onScreen then
		trigger.action.outText(message, time)
	end
end

function LOG:SetThreshold(threshold)
	LOG.Threshold = threshold
end

function LOG:New(logName, loggingThreshold)
	local obj = {}
	setmetatable(obj, self)
	self.__index = self
	
	-- Set local properties
	obj.name = logName or "Log"
	obj.threshold = loggingThreshold or LOG.Level.TRACE2

	return obj
end

-- Instance Methods

function LOG:log(message, level, showOnScreen)
	self:_logToEnv(message, level, showOnScreen)
end

function LOG:msg(message, level)
	self:_logToEnv(message, level, true)
end

function LOG:_logToEnv(message, level, showOnScreen)
	local level = level or LOG.Level.INFO 
	local onScreen = showOnScreen or false
	
	if level > self.threshold then return end
	
	local timestamp = timer.getTime()
	outputMsg = string.format("LOG: %s | %d | %s | %s", timestamp, level, self.name, message)
	
	if level == LOG.Level.ERROR then
		env.error(outputMsg, false)
	elseif level == LOG.Level.WARNING then
		env.warning(outputMsg, false)
	else
		env.info(outputMsg, false)
	end
	
	if onScreen then
		trigger.action.outText(message, 10)
	end
end

function dump(o, spaces)
	local spaces = spaces or ""
	if type(o) == 'table' then
			local s = '{\n'
			for k,v in pairs(o) do
				if type(k) ~= 'number' then k = '"'..k..'"' end
				s = s .. spaces .. '['..k..'] = ' .. dump(v, spaces .. "  ") .. ',\n'
			end
			return s .. spaces .. '} '
	else
		return tostring(o)
	end
end