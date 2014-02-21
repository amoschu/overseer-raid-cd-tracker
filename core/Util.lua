
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
	for k, val in next, LEVEL do
		LEVEL_BY_VAL[val] = k
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

local currentLevel 
do
	-- TOC file changes are (seemingly) only read when client is loaded
	local level = GetAddOnMetadata(ME, "X-Overseer-Log-Level")
	currentLevel = LEVEL[level] or LEVEL.INFO
end

local function Print(level, message)
	-- filter out messages under current level threshold
	if level >= currentLevel then
		-- what is the difference between DEFAULT_CHAT_FRAME:AddMessage and print?
		print( ("|c%s%s|r%s: %s"):format(NAME_COLOR, ME, LEVEL_PREFIX[level] or "", tostring(message)) )
	end
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
-- Current logging level
-- ------------------------------------------------------------------
local levelNames = ""
function addon:SetOutputLevel(level)
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
		self:Debug(msg:format(levelNames))
	end
	
	currentLevel = level or LEVEL.DEBUG
	self:Print(("Output level set to %s=%d"):format(LEVEL_BY_VAL[currentLevel], currentLevel), true)
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
		addon:Debug(msg:format(tostring(value), type(array)))
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
				addon:Debug("filtersByClass["..class.."]: testing '"..filter.."' -> "..tostring(hasFilter))
				for k,v in pairs(classFilters) do
					addon:Debug("    "..k..":"..tostring(v))
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
	if not optionalFilters then
		optionalKeys = addon.consts.filterKeys[ addon.consts.FILTER_OPTIONAL ]
	end
	if not eventsByFilter then
		eventsByFilter = addon.consts.eventsByFilter
	end

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
						addon:Debug(msg:format(addon.UnitClassColoredName(unit), type(events)))
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
		addon:Debug(msg:format(type(unit)))
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
		addon:Debug("GUIDClassColoredName(guid[, stripRealm]) - expected string 'guid'")
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
		addon:Debug("GUIDClassColoredName(guid[, stripRealm]) - expected string 'guid'")
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

-- ------------------------------------------------------------------
-- Logging wrappers
-- ------------------------------------------------------------------
function addon:PrintCLEU(message)
	Print(LEVEL.CLEU, message)
end

function addon:PrintTracking(message)
	Print(LEVEL.TRACKING, message)
end

function addon:PrintCD(message)
	Print(LEVEL.COOLDOWN, message)
end

function addon:PrintFunction(message, force)
	-- this can be a bit spammy and not super duper useful in combat so..
	if force or not self.isFightingBoss then
		Print(LEVEL.FUNCTION, message)
	end
end

function addon:Print(message, force)
	Print(force and inf or LEVEL.PRINT, message)
end

function addon:Debug(message)
	Print(LEVEL.DEBUG, message)
end

function addon:Info(message)
	Print(LEVEL.INFO, message)
end

function addon:Warn(message)
	Print(LEVEL.WARN, message)
end

function addon:Error(message)
	Print(LEVEL.ERROR, message)
end

function addon:Critical(message, level)
	Print(LEVEL.CRITICAL, message)
	error(message, tonumber(level) or 2)
end

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
			self:Print( ("%s items:"):format(GUIDClassColoredName(guid)), true )
			
			local atLeastOne = 0
			for i = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
				local itemLink = GetInventoryItemLink(unit, i)
				if itemLink then
					-- http://wowprogramming.com/docs/api_types#hyperlink
					-- "|Hitem:itemID:enchant:gem1:gem2:gem3:gem4:suffixID:uniqueID:level:reforgeId:upgradeId|h[link text]|h"
					-- regex string from reforgelite
					-- upgrades are mapped to arbitrary(?) numbers
					local id, upgrade = itemLink:match("item:(%d+):%d+:%d+:%d+:%d+:%d+:%-?%d+:%-?%d+:%d+:%d+:(%d+)")
					self:Print( ("%s%s (upgrade: %s)"):format(indent:rep(2), tostring(id), tostring(upgrade)), true )
					self:Print( ("%s%s"):format(indent, itemLink), true )
					atLeastOne = atLeastOne + 1
				end
			end
			
			self:Print( ("%s#items = %s"):format(indent, atLeastOne == 0 and "<NONE>" or tostring(atLeastOne)), true)
		else
			self:Print( (":DebugItemsFor(\"%s\") - could not get guid for unit"):format(tostring(unit)), true )
		end
	else
		self:Print( (":DebugItemsFor(\"%s\") - bad unit argument"):format(tostring(unit)), true )
	end
end

function addon:DebugCooldownsFor(unit)
	if not indent then
		indent = self.consts.INDENT
	end

	if type(unit) == "string" then
		local guid = UnitGUID(unit)
		if type(guid) == "string" then
			self:Print( ("%s tracked cooldowns:"):format(GUIDClassColoredName(guid)), true )
		
			local guidCooldowns = self.Cooldowns:GetSpellIdsFor(guid)
			if guidCooldowns then
				for spellid in next, guidCooldowns do
					self:Print( ("%s%s (%s)"):format(indent, tostring(spellid), GetSpellInfo(spellid) or "???"), true )
				end
			else
				self:Print( ("%s<NONE>"):format(indent), true )
			end
		else
			self:Print( (":DebugCooldownsFor(\"%s\") - could not get guid for unit"):format(tostring(unit)), true )
		end
	else
		self:Print( (":DebugCooldownsFor(\"%s\") - bad unit argument"):format(tostring(unit)), true )
	end
end
