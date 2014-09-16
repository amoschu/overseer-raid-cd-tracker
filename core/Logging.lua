
local tostring, tonumber, time, next, print, error, inf
    = tostring, tonumber, time, next, print, error, math.huge
local insert, AND, OR
    = table.insert, bit.band, bit.bor

local addon = Overseer

local COMBATLOG_OBJECT_TYPE_NPC = COMBATLOG_OBJECT_TYPE_NPC
local COMBATLOG_OBJECT_REACTION_HOSTILE = COMBATLOG_OBJECT_REACTION_HOSTILE
local COMBATLOG_OBJECT_REACTION_NEUTRAL = COMBATLOG_OBJECT_REACTION_NEUTRAL
local ME = addon:GetName()
local NAME_COLOR = addon.NAME_COLOR
local ID = "ID"
local TIMESTAMP = "TIMESTAMP"
local ACTIVE_IDX = "ACTIVE_IDX"

local activeLogIdx -- index of currently active log table
local Log
--[[
    OverseerLog = {
        { -- [1]
            -- all output in order
            [1] = "output",
            [2] = "output",
            ...
            [CLEU] = {
                [1] = "cleu-level output",
                ...
            },
            [DEBUG] = {
                -- debug-level output
            },
            ...
            [ID] = "boss/mob name",
            [TIMESTAMP] = time(),
        },
        ...
        [ACTIVE_IDX] = activeLogIdx
    }
--]]

local GUI = {}
do
    local AceEvent = LibStub:GetLibrary("AceEvent-3.0")
    AceEvent:Embed(GUI)
end

function addon:InitializeLogging()
    Log = OverseerLog or {}
    OverseerLog = Log
    activeLogIdx = (Log[ACTIVE_IDX] or 0) + 1
    
    GUI:RegisterEvent("PLAYER_REGEN_ENABLED")
    GUI:RegisterEvent("PLAYER_REGEN_DISABLED")
end

function addon:SaveLoggingInfo()
    Log[ACTIVE_IDX] = activeLogIdx
end

function addon:WipeLogRecord() -- TODO: save activeLogIdx as nil? 0?
    wipe(Log)
    activeLogIdx = 1
end

-- ------------------------------------------------------------------
-- Logging
-- ------------------------------------------------------------------
local LEVEL = {
	CLEU = -100,
	TRACKING = -75,
	COOLDOWN = -50,
	
	FUNCTION = -1,
	PRINT 	 = 0,
	
	DEBUG 	 = 10,
	INFO 	 = 20,
	WARN 	 = 30,
	ERROR 	 = 40,
	CRITICAL = 100,
    TEST     = 1000,
}
local LEVEL_BY_VAL = {}
do
	for lvl, val in next, LEVEL do
		LEVEL_BY_VAL[val] = lvl
	end
end

local LEVEL_PREFIX = {
	[LEVEL.CLEU] 	 = " |cff999999CLEU|r",
	[LEVEL.TRACKING] = " |cff999999TRACKING|r",
	[LEVEL.COOLDOWN] = " |cff999999CD|r",
	
	[LEVEL.PRINT] 	 = "$",
	[LEVEL.DEBUG] 	 = " |cff00FF00Debug|r",
	[LEVEL.INFO] 	 = "",
	[LEVEL.WARN] 	 = " |cffFFA500Warning|r",
	[LEVEL.ERROR] 	 = " |cffFF0000Error|r",
	[LEVEL.CRITICAL] = " |cffFF00FFCritical|r",
    [LEVEL.TEST]     = " |cff229ED3Test|r --",
}

local function Print(level, message, ...)
    -- what is the difference between DEFAULT_CHAT_FRAME:AddMessage and print?
    local formattedMsg = message:format(...)
    local output = ("|c%s%s|r%s: %s"):format(NAME_COLOR, ME, LEVEL_PREFIX[level] or "", tostring(formattedMsg))
    
    local activeLog = Log[activeLogIdx] or {}
    Log[activeLogIdx] = activeLog
    local levelName = LEVEL_BY_VAL[level]
    activeLog[levelName] = activeLog[levelName] or {}
    insert(activeLog, output) -- cache the output into the general log
    insert(activeLog[levelName], output) -- cache into the level-specific log
    
    -- TODO: read flag for whether logging should be spit out into chat
    print(output)
end

local function NoOp() end

-- ------------------------------------------------------------------
-- Logging wrappers
-- ------------------------------------------------------------------

 --[[
    globally accessible print methods are stored at the addon-table level
    the function names match the keys of the LEVEL table
    eg, addon:PRINT(...) or addon:CLEU(...), etc
--]]
local PRINT_WRAPPER = {}
do
    for lvl, val in next, LEVEL do
        -- propogate generic wrapper methods
        -- eg, PRINT_WRAPPER:CLEU(msg, ...)
        PRINT_WRAPPER[lvl] = function(self, message, ...)
            Print(val, message, ...)
        end
        
        -- map the print methods to their wrappers
        addon[lvl] = PRINT_WRAPPER[lvl]
    end
    
    -- override some specific functionality
    
    PRINT_WRAPPER.FUNCTION = function(self, force, message, ...)
        if type(force) == "string" then
            PRINT_WRAPPER.FUNCTION(self, nil, force, message, ...)
        else
            -- this can be a bit spammy and not super duper useful in combat so..
            if force or not addon.isFightingBoss then
                Print(LEVEL.FUNCTION, message, ...)
            end
        end
    end
    addon.FUNCTION = PRINT_WRAPPER.FUNCTION
    
    PRINT_WRAPPER.PRINT = function(self, force, message, ...)
        if type(force) == "string" then
            PRINT_WRAPPER.PRINT(self, nil, force, message, ...)
        else
            Print(force and inf or LEVEL.PRINT, message, ...)
        end
    end
    addon.PRINT = PRINT_WRAPPER.PRINT
    
    PRINT_WRAPPER.CRITICAL = function(self, message, level, ...)
        Print(LEVEL.CRITICAL, message, ...)
        error(message:format(...), tonumber(level) or 2)
    end
    addon.CRITICAL = PRINT_WRAPPER.CRITICAL
end

-- ------------------------------------------------------------------
-- Current logging level
-- ------------------------------------------------------------------
local currentLevel -- current output level
local levelNames = ""
local function SetLevel(level)
	if not level then
		level = LEVEL.INFO
	elseif type(level) == "string" then
		level = LEVEL[level]
	end
	
	if type(level) ~= "number" then
		if levelNames:len() == 0 then
			for k in next, LEVEL do
				local levelName = ("|cff00FF00%s|r"):format(k)
				levelNames = levelNames:len() > 0 and ("%s, %s"):format(levelName, levelNames) or levelName
			end
		end
		
		msg = "Failed to set output level, defaulting to DEBUG. Usage: :SetOutputLevel(level) - level = {%s}"
		addon:DEBUG(msg:format(levelNames))
	end
	
	currentLevel = level or LEVEL.DEBUG
    -- re-map the print methods to either print or no op
    -- eg, addon:DEBUG(...), etc
    for lvl, val in next, LEVEL do
        addon[lvl] = (val >= currentLevel) and PRINT_WRAPPER[lvl] or NoOp
    end
end

function addon:SetOutputLevel(level)
    SetLevel(level)
	self:PRINT(true, "Output level set to %s=%d", LEVEL_BY_VAL[currentLevel], currentLevel)
end

do -- set the initial output level
	-- TOC file changes are (seemingly) only read when client is loaded
	local level = GetAddOnMetadata(ME, "X-Overseer-Log-Level")
    SetLevel(LEVEL[level])
end

-- ------------------------------------------------------------------
-- GUI session handling
-- ------------------------------------------------------------------
local function CreateNewActiveLog()
    activeLogIdx = activeLogIdx + 1
    Log[activeLogIdx] = {
        [TIMESTAMP] = time()
    }
    return Log[activeLogIdx]
end

function GUI:PLAYER_REGEN_ENABLED(event)
    local activeLog = CreateNewActiveLog()
    activeLog[ID] = "-combat" -- TODO: a better id for dropping combat?
end

function GUI:PLAYER_REGEN_DISABLED(event)
    local activeLog = CreateNewActiveLog()
    if addon.encounter then
        activeLog[ID] = addon.encounter
    else
        -- scrape CLEU for something to ID this combat session by
        GUI:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end
end

local function AssignLogId(name)
    local activeLog = Log[activeLogIdx]
    activeLog[ID] = name
    GUI:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end

local relevantFlags = OR(COMBATLOG_OBJECT_TYPE_NPC, COMBATLOG_OBJECT_REACTION_HOSTILE, COMBATLOG_OBJECT_REACTION_NEUTRAL)
function GUI:COMBAT_LOG_EVENT_UNFILTERED(event, timestamp, message, hideCaster, srcGUID, srcName, srcFlags, srcRaidFlags, destGUID, destName, destFlags, destRaidFlags, spellid, spellname)
    if AND(relevantFlags, srcFlags or 0) > 0 then
        AssignLogId(srcName)
    elseif AND(relevantFlags, destFlags or 0) > 0 then
        AssignLogId(destName)
    end
end

-- ------------------------------------------------------------------
-- GUI display
-- ------------------------------------------------------------------

