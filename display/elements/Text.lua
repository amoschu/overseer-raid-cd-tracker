
local select, type, next, wipe, tonumber, tostring, inf, remove
	= select, type, next, wipe, tonumber, tostring, math.huge, table.remove
local GetTime
	= GetTime

local addon = Overseer
local LSM = LibStub("LibSharedMedia-3.0")

local consts = addon.consts
local append = addon.TableAppend
local GUIDName = addon.GUIDName
local GUIDClassColorStr = addon.GUIDClassColorStr
local GUIDClassColorRGB = addon.GUIDClassColorRGB
local GUIDClassColoredName = addon.GUIDClassColoredName
local GroupCache = addon.GroupCache
local Cooldowns = addon.Cooldowns

local MEDIA_TYPES = LSM.MediaType
local INDENT = consts.INDENT
local BREZ_IDS = consts.BREZ_IDS
local MSG = consts.MESSAGES
local ESC = consts.ESC_SEQUENCES

-- debugging flags
local _DEBUG_PARSING = false
local allowPrint

-- ------------------------------------------------------------------
-- Escape sequence replacement
-- see Constants.lua for an explanation of each escape sequence
-- ------------------------------------------------------------------
local function CacheFontColor(fontString)
	-- cache current color on the fontstring
	-- but don't wipe a cached color if one is already cached
	if not (fontString._r or fontString._g or fontString._b) then
		local r, g, b, a = fontString:GetTextColor()
		fontString._r = r
		fontString._g = g
		fontString._b = b
		fontString._a = a
	end
end

local function ResetFontColor(fontString)
	if fontString._r and fontString._g and fontString._b then
		fontString:SetTextColor(fontString._r, fontString._g, fontString._b, fontString._a)
		fontString._r = nil
		fontString._g = nil
		fontString._b = nil
		fontString._a = nil
	end
end

local function ChangeFontColor(unusable, spellCD, fontString)
	if unusable then
		CacheFontColor(fontString)
		
		local db = addon.db:GetDisplaySettings(spellCD.spellid)
		fontString:SetTextColor(db.font.notUsableR, db.font.notUsableG, db.font.notUsableB)
	else
		ResetFontColor(fontString)
	end
end

local function GetNameFromGUID(guid, useClassColor)
	-- TODO: dead/offl/benched color
	return useClassColor and GUIDClassColoredName(guid) or GUIDName(guid)
end

-- TODO: all these functions do /almost/ the same thing.. is there a way to lessen code duplication?
--		..only way I can see is having a helper function which asks for a callback
--		I think moving these to their own file may be better
local Replace = {}

-- ------------------------------------------------------------------
-- Current number castable
Replace[ESC.NUM_CASTABLE] = function(display, fontString, triggerSpell)
	local result = 0
	for spell in next, display.spells do
		local guid = spell.guid
		local valid = not (GroupCache:IsDead(guid) or GroupCache:IsOffline(guid) or GroupCache:IsBenched(guid))
		if valid then
			result = result + spell:NumReady()
		end
	end
	
	ChangeFontColor(result == 0, triggerSpell, fontString)
	return result, result
end

-- ------------------------------------------------------------------
-- Current number ready
Replace[ESC.NUM_READY] = function(display, fontString, triggerSpell)
	local result = 0
	for spell in next, display.spells do
        if not GroupCache:IsBenched(spell.guid) then
            result = result + spell:NumReady()
        end
	end
	
	ChangeFontColor(result == 0, triggerSpell, fontString)
	return result, result
end

-- ------------------------------------------------------------------
-- Current number NOT ready
Replace[ESC.NUM_NOTREADY] = function(display, fontString, triggerSpell)
	local result = 0
	for spell in next, display.spells do
		if not GroupCache:IsBenched(spell.guid) and spell:NumReady() <= 0 then
			result = result + 1
		end
	end
	
	return result, result
end

-- ------------------------------------------------------------------
-- Number of abilities benched
Replace[ESC.NUM_TOTAL_NOT_BENCHED] = function(display, fontString, triggerSpell)
	local result = 0
	for spell in next, display.spells do
		local guid = spell.guid
		if not GroupCache:IsBenched(guid) then
			result = result + spell:NumCharges()
		end
	end
	
	return result, result
end

-- ------------------------------------------------------------------
-- Total number of abilities currently known
Replace[ESC.NUM_TOTAL] = function(display, fontString, triggerSpell)
	local result = 0
	for spell in next, display.spells do
		result = result + spell:NumCharges()
	end
	
	return result, result
end

-- ------------------------------------------------------------------
-- Current number of combat ressurections remaining
-- -1 if n/a
Replace[ESC.NUM_BREZ] = function(display, fontString, triggerSpell)
	local result = addon:BrezRemaining()
	if result == inf then
		result = "" -- just pass back an empty string if brezzes aren't applicable
	end
	
	ChangeFontColor(result == "" or result == 0, triggerSpell, fontString)
	-- special case the 2nd return for 'if' statement parsing (-1 if no limit on brez)
	return result, (result == "") and -1 or result
end

-- ------------------------------------------------------------------
-- The most recent person to activate the ability
-- This only applies to spellCDs with a :BuffDuration()
-- note: returns an empty string if no buff is currently active for the given spellCD
Replace[ESC.NAMES_MOST_RECENT_ACTIVE] = function(display, fontString, triggerSpell)
	local result = ""
	
	-- TODO: all NAMES_ need to respond to db.unique (otherwise they will show too many names)
	local mostRecent = addon:GetMostRecentBuffCastSpell(display)
	if mostRecent then
		if allowPrint then
			-- this is not actually a problem if someone overrode this spell's buff (eg, Healbot casts salv -> +2s -> Jabbabot casts salv)
			-- however, it is an error if mostRecent == triggerSpell
			-- UNLESS the spell has multiple charges and the person used those charges within the buff duration
			--		eg, Healbot casts salv -> +2s -> Healbot casts salv (again)
			local msg = "[TEXT] %s expired -> showing %s as active (%.6fs remaining)"
			addon:ERROR(msg, tostring(triggerSpell), tostring(mostRecent), (mostRecent:BuffExpirationTime() - GetTime()))
			allowPrint = nil
		end
	
		result = GetNameFromGUID(mostRecent.guid, fontString.useClassColor)
	end
	
	return result, result:len() > 0 and 1 or 0
end

-- ------------------------------------------------------------------
local SEPARATOR = "|cffFFFFFF,|r " -- TODO: option to change & color(need to map r,g,b to 6-digit hex)
						-- TODO: separator gets colored when using :SetTextColor !!

-- List of people who can currently cast the spell
-- re: not dead, not offline, not benched
Replace[ESC.NAMES_USABLE] = function(display, fontString, triggerSpell)
	local numResult = 0
	local result = ""
	local useClassColor = fontString.useClassColor
	for spell in next, display.spells do
		local guid = spell.guid
		local valid = not (GroupCache:IsDead(guid) or GroupCache:IsOffline(guid) or GroupCache:IsBenched(guid))
		if spell:NumReady() >= 1 and valid then
			local name = GetNameFromGUID(guid, useClassColor)
			result = result:len() > 0 and ("%s%s%s"):format(name, SEPARATOR, result) or name
			numResult = numResult + 1
		end
	end
	
	return result, numResult
end

-- ------------------------------------------------------------------
-- List of people for who the ability is off cooldown
Replace[ESC.NAMES_READY] = function(display, fontString, triggerSpell)
	local numResult = 0
	local result = ""
	local useClassColor = fontString.useClassColor
	for spell in next, display.spells do
		if not GroupCache:IsBenched(spell.guid) and spell:NumReady() >= 1 then
			local name = GetNameFromGUID(spell.guid, useClassColor)
			result = result:len() > 0 and ("%s%s%s"):format(name, SEPARATOR, result) or name
			numResult = numResult + 1
		end
	end
	
	return result, numResult
end

-- ------------------------------------------------------------------
-- List of all known people who have the spell in group
Replace[ESC.NAMES_ALL] = function(display, fontString, triggerSpell)
	local numResult = 0
	local result = ""
	local useClassColor = fontString.useClassColor
	for spell in next, display.spells do
		local name = GetNameFromGUID(spell.guid, useClassColor)
		result = result:len() > 0 and ("%s%s%s"):format(name, SEPARATOR, result) or name
		numResult = numResult + 1
	end
	
	return result, numResult
end

-- ------------------------------------------------------------------
-- First person whose ability will come off cooldown
-- (this name will match the cooldown displayed by the icon cooldown frame or unique bar)
Replace[ESC.NAMES_FIRST_TO_EXPIRE] = function(display, fontString, triggerSpell)
	local result = ""
	local useClassColor = fontString.useClassColor
	
	local firstToExpire = addon:GetFirstToExpireSpell(display)
	if firstToExpire then
		local guid = firstToExpire.guid
		result = GUIDName(guid)
		
		local r,g,b
		local db = addon.db:GetDisplaySettings(firstToExpire.spellid)
		if true --[[db.font.useUnusableColor ..or something]] then -- TODO: :SetTextColor vs GUIDClassColoredName (|cff...|r takes precedence over :SetTextColor)
			r = db.font.notUsableR
			g = db.font.notUsableG
			b = db.font.notUsableB
		elseif useClassColor then -- TODO: dead/offl/benched
			r, g, b = GUIDClassColorRGB(guid)
		end
		
		CacheFontColor(fontString)
		fontString:SetTextColor(r, g, b)
	end
	return result, result:len() > 0 and 1 or 0
end

-- ------------------------------------------------------------------
-- List of all people with the ability on cooldown
-- TODO: in ascending/descending order
Replace[ESC.NAMES_ONCD] = function(display, fontString, triggerSpell)
	local numResult = 0
	local result = ""
	local useClassColor = fontString.useClassColor
	for spell in next, display.spells do
		if spell:NumReady() < spell:NumCharges() then -- TODO? sort by timeleft (& add options for sorting: ascending, descending, ..more?)
			local name = GetNameFromGUID(spell.guid, useClassColor)
			result = result:len() > 0 and ("%s%s%s"):format(name, SEPARATOR, result) or name
			numResult = numResult + 1
		end
	end
	
	return result, numResult
end

-- ------------------------------------------------------------------
-- List of all dead people with the tracked spell
Replace[ESC.NAMES_DEAD] = function(display, fontString, triggerSpell)
	local numResult = 0
	local result = ""
	local useClassColor = fontString.useClassColor
	for spell in next, display.spells do
		local guid = spell.guid
		if GroupCache:IsDead(guid) then
			local name = GetNameFromGUID(guid, useClassColor)
			result = result:len() > 0 and ("%s%s%s"):format(name, SEPARATOR, result) or name
			numResult = numResult + 1
		end
	end
	
	return result, numResult
end

-- ------------------------------------------------------------------
-- List of all offline people with the tracked spell
Replace[ESC.NAMES_OFFLINE] = function(display, fontString, triggerSpell)
	local numResult = 0
	local result = ""
	local useClassColor = fontString.useClassColor
	for spell in next, display.spells do
		local guid = spell.guid
		if GroupCache:IsOffline(guid) then
			local name = GetNameFromGUID(guid, useClassColor)
			result = result:len() > 0 and ("%s%s%s"):format(name, SEPARATOR, result) or name
			numResult = numResult + 1
		end
	end
	
	return result, numResult
end

-- ------------------------------------------------------------------
-- List of all benched people with the tracked spell
Replace[ESC.NAMES_BENCHED] = function(display, fontString, triggerSpell)
	local numResult = 0
	local result = ""
	local useClassColor = fontString.useClassColor
	for spell in next, display.spells do
		local guid = spell.guid
		if GroupCache:IsBenched(guid) then
			local name = GetNameFromGUID(guid, useClassColor)
			result = result:len() > 0 and ("%s%s%s"):format(name, SEPARATOR, result) or name
			numResult = numResult + 1
		end
	end
	
	return result, numResult
end

-- ------------------------------------------------------------------
-- Parser helpers
-- ------------------------------------------------------------------
local CMP = {} -- comparison map
CMP['<'] = function(numParsed, condition)
	condition = tonumber(condition)
	return condition and numParsed < condition
end
CMP['>'] = function(numParsed, condition)
	condition = tonumber(condition)
	return condition and numParsed > condition
end
CMP['<='] = function(numParsed, condition)
	condition = tonumber(condition)
	return condition and numParsed <= condition
end
CMP['>='] = function(numParsed, condition)
	condition = tonumber(condition)
	return condition and numParsed >= condition
end
CMP['=='] = function(numParsed, condition)
	condition = tonumber(condition)
	return condition and numParsed == condition
end
CMP['='] = CMP['==']

local function DebugParsing(msg)
	if _DEBUG_PARSING then
		addon:DEBUG(msg)
	end
end

local function ParseText(display, fontString, triggerSpell)
	local text = fontString.db.value
	if text then
		-- regex-fu
		local regex = "[.]*(%%%a)[^%%]*%%{%s*[iI][fF]%s*([<>=][=]?)%s*(%d+)%s*,%s*([%%]?[<>!-/%[-%`|~%w]*)%s*}[.]*"
		--[[
			[.]* = zero or more anything
			(%%%a) = capture escape sequence (the test for the if-condition)
				- '%%%a' matches any escape sequence '%<letter>'
			[^%%]* = zero or more not percent sign (so, whatever as long as there's no '%')
						-- TODO? figure out a way to allow percent signs (but still not match another escape seq)
			%% 	= '%' sign
			{  	= open squigly, duh
			%s* = zero or more whitespace chars
			[iI][fF] = 'if', 'If', 'iF', 'IF'
			%s* = whitespace
			([<>=][=]?) = capture comparison operator
				- '<' '<=' '>' '>=' '=' '=='
			%s* = whitespace
			(%d+) = capture one or more numbers - so only allow if=#
			%s* = whitespace
			, 	= ',' - using as 'then'
			%s* = whitespace
			([%%]?[<>!-/%[-%`|~%w]*) = capture the 'then' part of the if statement
				- this captures (I think) any string containing zero or more punctuation (excluding '{','}') or letters or numbers
				- [%%]? = optionally allow a leading '%' sign (so match an escape sequence)
				- [<>!-/%[-%`|~%w]* = allow any string that does not contain '{' or '}'.. I think
			%s* = whitespace
			} 	= close if
			[.]* = anything
		--]]
		
		DebugParsing(("-Parsing %s-"):format(tostring(triggerSpell)))
		DebugParsing(("%s'|cff999999%s|r'"):format(INDENT, text))
	
		-- 2 passes - 
		-- 1st pass: replace if blocks
		local first, compare, condition, second = text:match(regex)
		while first and compare and condition do
			second = second or "" -- allow an empty 'then' statement
			
			DebugParsing(("'%s' '%s' '%s' '%s'"):format(first, compare, condition, second))
			
			local numParsed = inf
			local parsed = first
			-- eg, "%A %{if<0, %B}"
			--		first = '%A'		compare = '<'		condition = '0'			second = '%B'
			-- get the replacement method (if one exists - possibly bad input if it doesn't, but maybe not)
			local replFunc = type(Replace[first]) == "function" and Replace[first]
			if replFunc then
				-- parse the first part of the if (eg, %A)
				-- numParsed is expected to be the parsed value as an integer
				-- ie, same as parsed for NUM_* esc sequences, number of names parsed for NAMES_* esc sequences
				parsed, numParsed = replFunc(display, fontString, triggerSpell)
				DebugParsing(("%s'%s': '%s'"):format(INDENT, first, parsed))
			end
			
			-- check if the condition is true
			local cmpFunc = type(CMP[compare]) == "function" and CMP[compare]
			if cmpFunc then
				if cmpFunc(numParsed, condition) then -- actually do the comparison
					-- parse the 'then' part of the if-statement (or just use the input if no replacement method found)
					-- eg, this is parsing %B
					replFunc = type(Replace[second]) == "function" and Replace[second]
					if replFunc then
						parsed = replFunc(display, fontString, triggerSpell)
						DebugParsing(("%s'%s': '%s'"):format(INDENT:rep(2), second, parsed))
					else
						parsed = second
					end
				end
			else
				-- this shouldn't happen
				-- it indicates that the regex is matching too much (matched an unexpected comparator)
				local msg = "ParseText('%s') - failed to locate compare function for '%s' (first='%s', cond='%s', second='%s')"
				addon:DEBUG(msg, fontString.db.value, compare, first, condition, second)
			end
			
			DebugParsing(("=> '%s'"):format(parsed))
			
			-- replace the escape sequence block with the freshly parsed text
			text = text:gsub(regex, parsed, 1)
			-- continue eating through if statements until they are all exhausted
			first, compare, condition, second = text:match(regex)
		end
		
		-- 2nd pass: eat up any more escape sequences
		local escPtn = "%%%s" -- all escape sequences should be of the form '%<letter>'
		for _, escSeq in next, ESC do
			-- note: not consuming escape sequences with a while :match(esc) because if a bad escape sequence is matched
			-- the loop will never halt unless the escPtn regex is modified to exclude every bad escape sequence encountered
			local esc = escPtn:format(escSeq) -- eg, '%r' => '%%r'
			if text:match(esc) then
				local replFunc = type(Replace[escSeq]) == "function" and Replace[escSeq]
				if replFunc then
					-- I think it's safe to just replace all instances of 'esc' in the text..
					-- why someone would have multiple instances of the same escape sequence is beyond me
					local parsed = replFunc(display, fontString, triggerSpell)
					if parsed then
						DebugParsing(("%s'%s': '%s'"):format(INDENT, escSeq, tostring(parsed)))
						text = text:gsub(esc, parsed)
					else
						local msg = "[%s] Parsing encountered a problem. '%s' -> %s"
						addon:WARN(msg, tostring(triggerSpell), escSeq, tostring(parsed))
					end
				else
					-- warn
					local msg = "Bad escape sequence '%s' found while parsing text for %s: '%s'"
					addon:WARN(escSeq, tostring(triggerSpell), fontString.db.value)
				end
			end
		end
	end
	return text
end

local function ParseAndSetText(display, fontString, triggerSpell)
	fontString:SetText(ParseText(display, fontString, triggerSpell))
	--addon:Untruncate(fontString) -- TODO: needed?
end

function addon:Untruncate(fontString) -- TODO: is this even needed?
	if fontString:IsTruncated() then
		local text = fontString:GetText()
		local fontSize = select(2, fontString:GetFont())
		fontString:SetSize(text:len() * fontSize, fontSize) -- won't work for vertical text (does WoW even support vertical text?)
	end
end

-- ------------------------------------------------------------------
-- Text message handlers
-- ------------------------------------------------------------------
local Texts = {
	--[[
	active text elements (fontstrings)
	
	form:
	[display] = { -- aka 'textCluster'
		fontString,
		fontString,
		...
	},
	...
	--]]
}

local Elements = addon.DisplayElements
Elements:Register(Texts, 1)

Texts.RegisterMessage = addon.RegisterMessage
Texts.UnregisterMessage = addon.UnregisterMessage
function Texts:Initialize()
    self:RegisterMessage(MSG.OPT_TEXTS_UPDATE, MSG.OPT_TEXTS_UPDATE)
end

function Texts:Shutdown()
    self:UnregisterMessage(MSG.OPT_TEXTS_UPDATE)
end

local function ApplySettings(fontString, spellCD)
	local spellid = spellCD.spellid
    local textData = fontString.db
    
    local useClassColor = addon.db:LookupFont(textData, spellid, "useClassColor")
    local fontR, fontG, fontB
    local font = addon.db:LookupFont(textData, spellid, "font")
    local fontSize = addon.db:LookupFont(textData, spellid, "size")
    local fontFlags = addon.db:LookupFont(textData, spellid, "flags")
    local justifyH = addon.db:LookupFont(textData, spellid, "justifyH")
    local justifyV = addon.db:LookupFont(textData, spellid, "justifyV")
    
    -- TODO: TMP
    fontString.useClassColor = useClassColor
    --
    
    if useClassColor then
        -- may not make much sense for consolidated displays (will use the spellCD that spawned the display's class color)
        fontR, fontG, fontB = GUIDClassColorRGB(spellCD.guid)
    else
        fontR = addon.db:LookupFont(textData, spellid, "r")
        fontG = addon.db:LookupFont(textData, spellid, "g")
        fontB = addon.db:LookupFont(textData, spellid, "b")
    end
    fontString:ClearAllPoints()
    fontString:SetPoint(textData.point, fontString:GetParent(), textData.relPoint, textData.x, textData.y)
    fontString:SetFont(LSM:Fetch(MEDIA_TYPES.FONT, font), fontSize, fontFlags) -- will not set the size > 24
    fontString:SetTextHeight(fontSize) -- this will scale the drawn text if > 24
    fontString:SetJustifyH(justifyH)
    fontString:SetJustifyV(justifyV)
    fontString:SetTextColor(fontR, fontG, fontB, 1)
    local sa = addon.db:LookupFont(textData, spellid, "shadow") and 1 or 0
    fontString:SetShadowColor(0, 0, 0, sa)
    fontString:SetShadowOffset(1, -1)
end

local TEXT_ELEMENT_KEY = consts.TEXT_ELEMENT_KEY
local function GetTexts(spellCD, parent)
	local spellid = spellCD.spellid
	local db = addon.db:GetDisplaySettings(spellid)
	if db.texts then
		local textCluster
        --[[
            TODO: this system needs to be re-examined
                if two spellids share a display but have a different amount of texts (or their text options differ / are in a different order)
                then the spellid which most recently calls 'GetTexts' will be the one to have its text displayed while the other's text settings are discarded
                
                1. does this matter? ie, can the user get into this state through the GUI?
                2. possible fix: key by .value in the db
        --]]
		for i = 1, #db.texts do
			local textData = db.texts[i]
			if textData.enabled and textData.value then -- don't create a fontstring for disabled texts or if no value is supplied (an empty fontstring)
				textCluster = textCluster or {}
				
				local textElement = parent[TEXT_ELEMENT_KEY:format(i)]
				if not textElement then
					--addon:DEBUG("%s: creating fontstring.. '|cff999999%s|r'", tostring(spellCD), textData.value)
					
					-- instantiate a new fontstring
					-- it doesn't seem like fontstrings can be passed around and recycled (unless they're given a global name?)
					-- this has the potential of littering displays with a lot of dead fontstrings if there are any displays that
					-- require more than the average amount of text elements (ultimately, it shouldn't be that big of a deal)
					textElement = parent:CreateFontString()--(nil, "OVERLAY")
					textElement:SetDrawLayer("OVERLAY", 7)
					parent[TEXT_ELEMENT_KEY:format(i)] = textElement
				end
                textElement.db = textData -- cache the db entry on the fontstring
                ApplySettings(textElement, spellCD)
				ParseAndSetText(parent, textElement, spellCD)
                
				append(textCluster, textElement)
				textElement:Show()
			end
		end
		return textCluster
	else
		local msg = "Could not instantiate text instances for key=%s - no data!"
		addon:DEBUG(msg, tostring(spellid))
	end
end

local function Reparse(spellCD, display)
	local textCluster = Texts[display]
	if type(textCluster) == "table" then
		for i = 1, #textCluster do
			local fontString = textCluster[i]
			ParseAndSetText(display, fontString, spellCD)
		end
	end
end

-- ------------------------------------------------------------------
-- OnCreate
-- ------------------------------------------------------------------
Texts[MSG.DISPLAY_CREATE] = function(self, msg, spellCD, display)
	--addon:FUNCTION("Texts:%s(%s)", msg, tostring(spellCD))
		
	local textCluster = self[display]
	if not textCluster then
		textCluster = GetTexts(spellCD, display)
		self[display] = textCluster
	else
		-- update the existing text cluster
		for i = 1, #textCluster do
			local fontString = textCluster[i]
			fontString:Show()
		end
		Reparse(spellCD, display)
	end
end

-- ------------------------------------------------------------------
-- OnDelete
-- ------------------------------------------------------------------
local toRemove = {}
Texts[MSG.DISPLAY_DELETE] = function(self, msg, spellCD, display)
	local textCluster = self[display]
	if textCluster then
		--addon:FUNCTION("Texts:%s(%s)", msg, tostring(spellCD))
		
		while #textCluster > 0 do
			local fontString = remove(textCluster)
			
			-- fontStrings don't seem to be recyclable like frames are (reparenting doesn't seem to work as I would expect)
			-- so, just reset their states and reuse if they are needed if/when the display is recycled
			fontString:Hide()
			fontString:ClearAllPoints()
			fontString:SetText("")
            -- TODO? restore color?
            fontString.db = nil
		end
		self[display] = nil
	end
end

-- ------------------------------------------------------------------
-- Display message handling
-- ..just reparse every text on the display (it's a bit more cpu-work, but less of a headache to maintain)
-- ------------------------------------------------------------------
local function UpdateTexts(self, msg, spellCD, display)
	allowPrint = msg == MSG.DISPLAY_BUFF_EXPIRE
	Reparse(spellCD, display)
end
Texts[MSG.DISPLAY_MODIFY] = 		UpdateTexts
Texts[MSG.DISPLAY_BUFF_EXPIRE] = 	UpdateTexts
Texts[MSG.DISPLAY_USE] = 			UpdateTexts
Texts[MSG.DISPLAY_READY] = 			UpdateTexts
Texts[MSG.DISPLAY_CD_LOST] =		UpdateTexts
Texts[MSG.DISPLAY_RESET] = 			UpdateTexts
Texts[MSG.DISPLAY_SHOW] = 			UpdateTexts -- TODO: does this need to reparse? I guess catch a potential change while the display was hidden?
Texts[MSG.DISPLAY_COLOR_UPDATE] = 	UpdateTexts

-- ------------------------------------------------------------------
-- Brez handling
-- ------------------------------------------------------------------
local function IsTextCluster(display, textCluster)
	-- this is to skip the message handlers in loops on the 'Texts' struct
	return type(display) == "table" and display.spells and type(textCluster) == "table"
end

local function TextBrezHandler(self)
	-- holy loops, batman
	for display, textCluster in next, self do -- look through the displays..
		if IsTextCluster(display, textCluster) then
			for id in next, BREZ_IDS do
				local spellCooldowns = Cooldowns[id]
				if spellCooldowns then
					for _, spellCD in next, spellCooldowns do
						if display.spells[spellCD] then -- ..to see if any represent a brez
							-- this display is showing brez information, reparse its text
							Reparse(spellCD, display)
						end
					end
				end
			end
		end
	end
end
Texts[MSG.BREZ_ACCEPT]    = TextBrezHandler
Texts[MSG.BREZ_RESET]     = TextBrezHandler
Texts[MSG.BREZ_CHARGING]  = TextBrezHandler
Texts[MSG.BREZ_RECHARGED] = TextBrezHandler
Texts[MSG.BREZ_STOP_CHARGING] = TextBrezHandler -- TODO: is this necessary?

-- ------------------------------------------------------------------
-- GUID State handling
-- ------------------------------------------------------------------
local function TextGUIDStateHandler(self, msg, guid)
	local spellids = Cooldowns:GetSpellIdsFor(guid)
	if spellids then
		for display, textCluster in next, self do -- look through the displays..
			if IsTextCluster(display, textCluster) then
				for id in next, spellids do
					local spellCD = Cooldowns[id][guid]
					if spellCD then
						if display.spells[spellCD] then -- ..for one that represents a spell for this person (guid)
							Reparse(spellCD, display)
						end
					else
						 -- this should never happen (and if it does, it would be better to catch it in core)
						 -- indicates a mismatch between the 'Cooldowns' and 'CooldownsByGUID' tables
						 local msg = "Texts:%s(%s): Cooldown state mismatch! No such spell='%s' tracked for 'guid'"
						 addon:DEBUG(msg, msg, GUIDClassColoredName(guid), tostring(id))
					end
				end
			end
		end
	end
end
Texts[MSG.GUID_CHANGE_DEAD] 	= TextGUIDStateHandler
Texts[MSG.GUID_CHANGE_ONLINE]   = TextGUIDStateHandler
Texts[MSG.GUID_CHANGE_BENCHED]  = TextGUIDStateHandler

-- ------------------------------------------------------------------
-- Display group handling
-- ------------------------------------------------------------------
local ORIG_PT = "ORIG_PT"
local ORIG_REL = "ORIG_REL"
local ORIG_RELPT = "ORIG_RELPT"
local ORIG_X = "ORIG_X"
local ORIG_Y = "ORIG_Y"
local function CacheOriginalPoint(fontString)
	if not fontString[ORIG_PT] then
		local pt, rel, relPt, x, y = fontString:GetPoint()
		fontString[ORIG_PT] = pt
		fontString[ORIG_REL] = rel
		fontString[ORIG_RELPT] = relPt
		fontString[ORIG_X] = x
		fontString[ORIG_Y] = y
	end
end

local function RestoreOriginalPoint(fontString)
	if fontString[ORIG_PT] then
		local pt = fontString[ORIG_PT]
		local rel = fontString[ORIG_REL]
		local relPt = fontString[ORIG_RELPT]
		local x = fontString[ORIG_X]
		local y = fontString[ORIG_Y]
		fontString:ClearAllPoints()
		fontString:SetPoint(pt, rel, relPt, x, y)
		
		fontString[ORIG_PT] = nil
		fontString[ORIG_REL] = nil
		fontString[ORIG_RELPT] = nil
		fontString[ORIG_X] = nil
		fontString[ORIG_Y] = nil
	end
end

local stickyTexts = { -- TODO: save these out
	--[[
	the display whose textCluster is stickied per group
	a stickied textCluster will be shown when the user is not mousing over any display within the group
	
	form:
	[group] = display,
	...
	--]]
}
local function OnEnter(msg, widget, motion)
	local display = widget:GetParent()
	if display and display.spells then
		local sticky = stickyTexts[display.group]
		local textCluster = Texts[display]
		if sticky ~= display and textCluster then
			if sticky then
				-- hide the stickied text cluster
				local stickiedText = Texts[sticky]
				for i = 1, #stickiedText do
					local fontString = stickiedText[i]
					if fontString.db.groupText then
						fontString:Hide()
					end
				end
			end
			for i = 1, #textCluster do
				-- show the texts relevant to the mouse-over
				local fontString = textCluster[i]
				if fontString.db.groupText then
					fontString:Show()
				end
			end
		end
	end
end

local function OnLeave(msg, widget, motion)
	local display = widget:GetParent()
	if display and display.spells then
		local sticky = stickyTexts[display.group]
		local textCluster = Texts[display]
		if sticky ~= display and textCluster then
			for i = 1, #textCluster do
				-- hide the texts which were shown from mouse-over
				local fontString = textCluster[i]
				if fontString.db.groupText then
					fontString:Hide()
				end
			end
			if sticky then
				-- hide the stickied text cluster
				local stickiedText = Texts[sticky]
				for i = 1, #stickiedText do
					local fontString = stickiedText[i]
					if fontString.db.groupText then
						fontString:Show()
					end
				end
			end
		end
	end
end

local MBUTTON = consts.MBUTTON
local function OnMouseDown(msg, widget, btn)
	-- TODO: TMP? empty function for feedback
end

local function OnMouseUp(msg, widget, btn)
	local display = widget:GetParent()
	if display and display.spells then
		if btn == MBUTTON.LEFT then -- TODO: option to assign the button
			stickyTexts[display.group] = display
		elseif btn == MBUTTON.RIGHT then
			stickyTexts[display.group] = nil
		end
	end
end

Texts[MSG.DISPLAY_GROUP_ADD] = function(self, msg, child, group)
	local textCluster = self[child]
	if textCluster then
		local broadcastBehaviorChange = false
		for i = 1, #textCluster do
			local fontString = textCluster[i]
			if fontString:IsVisible() and fontString.db.groupText then
				fontString:Hide()
				CacheOriginalPoint(fontString)
				-- set new point based on group settings
				local pt, _, relPt, x, y = fontString:GetPoint()
				fontString:ClearAllPoints()
				fontString:SetPoint(pt, group, relPt, x, y)
				broadcastBehaviorChange = true
			end
		end
		
		if broadcastBehaviorChange then
			addon:SendMessage(MSG.DISPLAY_TEXT_GROUP_ADD, child, OnEnter, OnLeave, OnMouseDown, OnMouseUp)
		end
	end
end

Texts[MSG.DISPLAY_GROUP_REMOVE] = function(self, msg, child, group)
	local textCluster = self[child]
	if textCluster then
		local sticky = stickyTexts[group]
		if sticky == child then
			-- maintain the state of the stickied text for the group
			-- otherwise, the mouse-event system may elicit strange text behavior (..who speaks like this?)
			stickyTexts[group] = nil
		end
		
		local broadcastBehaviorChange = false
		for i = 1, #textCluster do
			local fontString = textCluster[i]
			if fontString.db.groupText then
				fontString:Show()
				RestoreOriginalPoint(fontString)
				broadcastBehaviorChange = true
			end
		end
		
		if broadcastBehaviorChange then
			addon:SendMessage(MSG.DISPLAY_TEXT_GROUP_REMOVE, child, OnEnter, OnLeave, nil, onMouseUp)
		end
	end
end

-- ------------------------------------------------------------------
-- Options handling
-- ------------------------------------------------------------------
local DEFAULT_KEY = addon.db.DEFAULT_KEY
local function IsSetOfBars(display, displayBars)
    return type(display) == "table" and display.spells and type(displayBars) == "table"
end

Texts[MSG.OPT_TEXTS_UPDATE] = function(self, msg, id)
    if id == DEFAULT_KEY then
        -- update all fontstrings for all displays
		for display, textCluster in next, self do
            if IsTextCluster(display, textCluster) then
                local spellCD = next(display.spells) -- spells which share a display should all have the same settings
                for i = 1, #textCluster do
                    local fontString = textCluster[i]
                    ApplySettings(fontString, spellCD)
                    -- TODO: text delete, text create, profile changes (just delete all and repopulate?)
                end
                Reparse(spellCD, display)
            end
        end
    else
        local applied
        -- look for the specific display to update
		for display, textCluster in next, self do
            if IsTextCluster(display, textCluster) then
                for spellCD in next, display.spells do
                    local consolidatedId = addon.db:GetConsolidatedKey(spellCD.spellid)
                    if id == spellCD.spellid or id == consolidatedId then
                        for i = 1, #textCluster do
                            local fontString = textCluster[i]
                            ApplySettings(fontString, spellCD)
                            -- TODO
                        end
                        Reparse(spellCD, display)
                        
                        applied = true
                        break
                    end
                end
            end
            
            if applied then break end
        end
        
        if not applied then
            local debugMsg = "Texts:%s: No such icon for id='%s'"
            addon:DEBUG(debugMsg, msg, id)
        end
    end
end
