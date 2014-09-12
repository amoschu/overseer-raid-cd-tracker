
local print, type, next, select, tostring, tonumber, error, floor, inf
	= print, type, next, select, tostring, tonumber, error, math.floor, math.huge
local RAID_CLASS_COLORS, UnitClass, UnitName, GetPlayerInfoByGUID
	= RAID_CLASS_COLORS, UnitClass, UnitName, GetPlayerInfoByGUID
	
local addon = Overseer

local UNKNOWN = UNKNOWN
local ME = addon:GetName()
local NAME_COLOR = addon.NAME_COLOR

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
}

local function Print(level, message, ...)
    -- what is the difference between DEFAULT_CHAT_FRAME:AddMessage and print?
    local formattedMsg = message:format(...)
    print( ("|c%s%s|r%s: %s"):format(NAME_COLOR, ME, LEVEL_PREFIX[level] or "", tostring(formattedMsg)) )
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
-- Class colored name
-- ------------------------------------------------------------------
local function StripRealmFromName(name)
	local realmSep = name:find("-")
	if realmSep then
		name = ("%s*"):format(name:sub(0, realmSep-1))
	end
	return name
end

local function GetClassColorStr(class)
	return class and RAID_CLASS_COLORS[class] and RAID_CLASS_COLORS[class].colorStr or "ff999999"
end

local function GetClassColorRGB(class)
	local r, g, b = 0.6, 0.6, 0.6
	if class and RAID_CLASS_COLORS[class] then
		local CLASS_COLOR = RAID_CLASS_COLORS[class]
		r = CLASS_COLOR.r
		g = CLASS_COLOR.g
		b = CLASS_COLOR.b
	end
	return r, g, b, 1
end

local function GetClassColoredName(class, name)
	return ("|c%s%s|r"):format(GetClassColorStr(class), name or UNKNOWN)
end

local MESSAGES
local function BroadcastClassColorChange()
	if not MESSAGES then
		MESSAGES = addon.consts.MESSAGES
	end
	addon:SendMessage(MESSAGES.CLASS_COLORS_CHANGED)
end
function addon:UpdateClassColors()
	-- use custom class colors if they exist
	local CUSTOM_CLASS_COLORS = CUSTOM_CLASS_COLORS
	if CUSTOM_CLASS_COLORS then
		RAID_CLASS_COLORS = CUSTOM_CLASS_COLORS
		CUSTOM_CLASS_COLORS:RegisterCallback(BroadcastClassColorChange)
	end
end

-- ------------------------------------------------------------------
-- Public util functions 
-- note the '.', no implicit 'self' arg - this allows us to alias these functions without needing to pass 'addon'
-- eg. local UnitClassColoredName = addon.UnitClassColoredName
--	   print(UnitClassColoredName("player"))
-- ------------------------------------------------------------------
function addon.TableAppend(array, value) -- this is actually the same as table.insert(t, value).. woops
	if type(array) ~= "table" then
		local msg = "Failed to append \"%s\" to non-table type (type=%s)"
		addon:DEBUG(msg, tostring(value), type(array))
		return
	end
	
	array[#array+1] = value
	return array -- not useful in most cases, but it's here if you need it!!
end

function addon.Round(n)
	return floor(n + 0.5)
end

function addon.ToBool(value)
	return value and true or false
end

function addon.SecondsToString(seconds)
    local minutes = seconds / 60
    local hours = minutes / 60
    if seconds < 60 then
        return ("%ds"):format(seconds)
    elseif hours > 1 then
        return ("%d:%02d:%02d"):format(floor(hours), minutes % 60, seconds % 60)
    elseif minutes > 1 then
        return ("%d:%02d"):format(floor(minutes), seconds % 60)
    end
end

function addon.GetUnitFromGUID(guid)
	return type(guid) == "string" and guid:len() > 0 and select(6, GetPlayerInfoByGUID(guid))
end

local filtersByClass
local _DEBUG_UNIT_HAS_FILTER = false
function addon.UnitHasFilter(unit, filter)
	if not filtersByClass then
		filtersByClass = addon.data.filtersByClass
	end

	local hasFilter = false
	if unit and filter then
		local class = select(2, UnitClass(unit))
		hasFilter = class and filtersByClass[class] and filtersByClass[class][filter]
		
		-- debugging.. shouldn't ever need again
		if _DEBUG_UNIT_HAS_FILTER then
			local classFilters = filtersByClass[class]
			if classFilters then
				addon:DEBUG("filtersByClass["..class.."]: testing '"..filter.."' -> "..tostring(hasFilter))
				for k,v in pairs(classFilters) do
					addon:DEBUG("    "..k..":"..tostring(v))
				end
			end
		end
	end
	return hasFilter
end

local optionalKeys
local eventsByFilter
local INSPECT_EVENT = "INSPECT_READY"
function addon.UnitNeedsInspect(unit)
    optionalKeys = optionalKeys or addon.consts.filterKeys[ addon.consts.FILTER_OPTIONAL ]
    eventsByFilter = eventsByFilter or addon.consts.eventsByFilter

	local result = false
	if unit then
		-- search through all filters for this unit
		for _, filter in next, optionalKeys do
			if addon.UnitHasFilter(unit, filter) then
				local events = eventsByFilter[filter]
				if events then
					if type(events) == "table" then
						for _, e in next, events do
							result = e:match(INSPECT_EVENT) and true
							if result then break end
						end
					elseif type(events) == "string" then
						result = events:match(INSPECT_EVENT) and true
					else
						local msg = "UnitNeedsInspect(%s) - encountered unexpected type, '%s', in 'eventsByFilter' table"
						addon:DEBUG(msg, addon.UnitClassColoredName(unit), type(events))
					end
				end
				
				if result then break end
			end
		end
	end
	return result
end

function addon.UnitClassColorRGB(unit)
	local class = unit and select(2, UnitClass(unit))
	return GetClassColorRGB(class)
end

function addon.GUIDClassColorRGB(guid)
	local class = guid and guid:len() > 0 and select(2, GetPlayerInfoByGUID(guid))
	return GetClassColorRGB(class)
end

function addon.UnitClassColorStr(unit)
	local class = unit and select(2, UnitClass(unit))
	return GetClassColorStr(class)
end

function addon.GUIDClassColorStr(guid)
	local class = guid and guid:len() > 0 and select(2, GetPlayerInfoByGUID(guid))
	return GetClassColorStr(class)
end

function addon.UnitClassColoredName(unit, stripRealm)
	if type(unit) ~= "string" then
		--[[
		local msg = "UnitClassColoredName(unit[, stripRealm]) - expected string 'unit', received '%s'"
		addon:DEBUG(msg, type(unit))
		--]]
		return GetClassColoredName(nil, UNKNOWN)
	end

	stripRealm = stripRealm ~= false and true or false -- default to true
	local name, realm = UnitName(unit)
	local class = select(2, UnitClass(unit))
	if realm and realm:len() > 0 then
		name = stripRealm and ("%s*"):format(name) or ("%s-%s"):format(name, realm)
	end
	
	return GetClassColoredName(class, name)
end

function addon.GUIDClassColoredName(guid, stripRealm)
	if type(guid) ~= "string" then
		--[[
		addon:DEBUG("GUIDClassColoredName(guid[, stripRealm]) - expected string 'guid'")
		--]]
		return GetClassColoredName(nil, UNKNOWN)
	end
	
	stripRealm = stripRealm ~= false and true or false -- default to true
	local coloredName
	if guid:len() > 0 then -- CLEU sometimes passes ..an empty string? not sure
		local _, class, _, _, _, name, realm = GetPlayerInfoByGUID(guid)
		if realm and realm:len() > 0 then
			name = stripRealm and ("%s*"):format(name) or ("%s-%s"):format(name, realm)
		end
		coloredName = GetClassColoredName(class, name)
	else
		coloredName = GetClassColoredName(nil, UNKNOWN)
	end
	
	return coloredName
end

function addon.GUIDName(guid, stripRealm)
	if type(guid) ~= "string" then
		--[[
		addon:DEBUG("GUIDClassColoredName(guid[, stripRealm]) - expected string 'guid'")
		--]]
		return GetClassColoredName(nil, UNKNOWN)
	end
	
	local name, realm
	stripRealm = stripRealm ~= false and true or false -- default to true
	if guid:len() > 0 then
		name, realm = select(6, GetPlayerInfoByGUID(guid))
		if realm and realm:len() > 0 then
			name = stripRealm and ("%s*"):format(name) or ("%s-%s"):format(name, realm)
		end
	else
		name = UNKNOWN
	end
	
	return name
end

function addon.GetGUIDType(guid)
    if type(guid) ~= "string" then
        return
    end
    
    -- 6.0 GUIDs are of the form [UnitType]:[more:stuff:...]
    --  eg. players => Player:971:000F5773
    --      pets =>    Pet:0:971:1:67:510:020009EA4B
    -- http://wowpedia.org/Patch_6.0.2/API_changes#Changes
    local i = guid:find(":")
    return i and guid:sub(1, i-1)
end

--@do-not-package@
--------------------------------------------------------- TODO: TMP
local indent
local GUIDClassColoredName = addon.GUIDClassColoredName
local UnitGUID, GetSpellInfo 
	= UnitGUID, GetSpellInfo
local INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED, GetInventoryItemLink
	= INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED, GetInventoryItemLink
function addon:DebugItemsFor(unit)
	if not indent then
		indent = self.consts.INDENT
	end

	if type(unit) == "string" then
		local guid = UnitGUID(unit)
		if type(guid) == "string" then
			self:PRINT(true, "%s items:", GUIDClassColoredName(guid))
			
			local atLeastOne = 0
			for i = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
				local itemLink = GetInventoryItemLink(unit, i)
				if itemLink then
					-- http://wowprogramming.com/docs/api_types#hyperlink
					-- "|Hitem:itemID:enchant:gem1:gem2:gem3:gem4:suffixID:uniqueID:level:reforgeId:upgradeId|h[link text]|h"
					-- regex string from reforgelite
					-- upgrades are mapped to arbitrary(?) numbers
					local id, upgrade = itemLink:match("item:(%d+):%d+:%d+:%d+:%d+:%d+:%-?%d+:%-?%d+:%d+:%d+:(%d+)")
					self:PRINT(true, "%s%s (upgrade: %s)", indent:rep(2), tostring(id), tostring(upgrade))
					self:PRINT(true, "%s%s", indent, itemLink)
					atLeastOne = atLeastOne + 1
				end
			end
			
			self:PRINT(true, "%s#items = %s", indent, atLeastOne == 0 and "<NONE>" or tostring(atLeastOne))
		else
			self:PRINT(true, ":DebugItemsFor(\"%s\") - could not get guid for unit", tostring(unit))
		end
	else
		self:PRINT(true, ":DebugItemsFor(\"%s\") - bad unit argument", tostring(unit))
	end
end

function addon:DebugCooldownsFor(unit)
	if not indent then
		indent = self.consts.INDENT
	end

	if type(unit) == "string" then
		local guid = UnitGUID(unit)
		if type(guid) == "string" then
			self:PRINT(true, "%s tracked cooldowns:", GUIDClassColoredName(guid))
		
			local guidCooldowns = self.Cooldowns:GetSpellIdsFor(guid)
			if guidCooldowns then
				for spellid in next, guidCooldowns do
					self:PRINT(true, "%s%s (%s)", indent, tostring(spellid), GetSpellInfo(spellid) or "???")
				end
			else
				self:PRINT(true, "%s<NONE>", indent)
			end
		else
			self:PRINT(true, ":DebugCooldownsFor(\"%s\") - could not get guid for unit", tostring(unit))
		end
	else
		self:PRINT(true, ":DebugCooldownsFor(\"%s\") - bad unit argument", tostring(unit))
	end
end
--@end-do-not-package@
