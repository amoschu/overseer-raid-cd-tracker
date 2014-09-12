
local type, select
	= type, select
local GetTime, GetSpellInfo, UnitBuff, UnitClass, UnitGUID, UnitCreatureFamily, GetPlayerInfoByGUID
	= GetTime, GetSpellInfo, UnitBuff, UnitClass, UnitGUID, UnitCreatureFamily, GetPlayerInfoByGUID

local addon = Overseer

local consts = addon.consts
local filterKeys = consts.filterKeys
local GUIDClassColorStr = addon.GUIDClassColorStr
local GetUnitFromGUID = addon.GetUnitFromGUID
local GUIDClassColoredName = addon.GUIDClassColoredName

local INDENT = consts.INDENT
local FILTER_OPTIONAL = consts.FILTER_OPTIONAL
local FILTER_REQUIRED = consts.FILTER_REQUIRED
local FILTER_MOD_VALUE = consts.FILTER_MOD_VALUE
local FILTER_MOD_OP = consts.FILTER_MOD_OP
local optionalKeys = filterKeys[FILTER_OPTIONAL]

local GroupCache

-- ------------------------------------------------------------------
-- Tracking validation
-- ------------------------------------------------------------------
local validateFilter = {
	--[[
	validates the keyed filter for tracking
	
	return true if valid (ie, filter passed)
	return false/nil if not valid (ie, filter failed)
	--]]
}

-- expects (+)data to represent equality
--         (-)data to represent negation
local function IsValid(data, valid) -- TODO: negation didn't work for spec.. need to double check it works for the others
	if data >= 0 then
		return valid
	else
		return not valid
	end
end

local function IsOrIsNotString(data, has) -- logging helper
	local is = not has and "is" or "has"
	return tonumber(data) and data < 0 and ("%s not"):format(is) or ("%s"):format(is)
end

local function PrintTracking(key, guid, data, valid, has)
	addon:TRACKING("%s[%s]%s: %s |c%s%s|r? %s",
		INDENT, GUIDClassColoredName(guid), tostring(key),
		IsOrIsNotString(data, has),
		GUIDClassColorStr(guid), tostring(data),
		tostring(valid)
	)
end

-- spec
validateFilter[optionalKeys.SPEC] = function(data, guid)
	local valid = true
	if data then
		local spec = GroupCache:Spec(guid)
		if type(data) == "table" then
			for i = 1, #data do
				local specData = data[i]
				if specData < 0 then
					valid = spec ~= -specData
				else
					valid = spec == specData
				end
				--valid = IsValid(specData, GroupCache:Spec(guid) == specData)
				
				PrintTracking(optionalKeys.SPEC, guid, specData, valid)
				if not valid then break end
			end
		else
			local spec = GroupCache:Spec(guid)
			if data < 0 then
				valid = spec ~= -data
			else
				valid = spec == data
			end
			--valid = IsValid(data, GroupCache:Spec(guid) == data)
			PrintTracking(optionalKeys.SPEC, guid, data, valid)
		end
	end
	return valid
end

-- talent
validateFilter[optionalKeys.TALENT] = function(data, guid)
	local valid = true
	if data then
		if type(data) == "table" then
			for i = 1, #data do
				local talentData = data[i]
				valid = IsValid(talentData, GroupCache:HasTalent(guid, talentData) or GroupCache:HasTalent(guid, -talentData))
				
				PrintTracking(optionalKeys.TALENT, guid, talentData, valid, true)
				if not valid then break end
			end
		else
			valid = IsValid(data, GroupCache:HasTalent(guid, data) or GroupCache:HasTalent(guid, -data))
			PrintTracking(optionalKeys.TALENT, guid, data, valid, true)
		end
	end
	return valid
end

-- glyph
validateFilter[optionalKeys.GLYPH] = function(data, guid)
	local valid = true
	if data then
		if type(data) == "table" then
			for i = 1, #data do
				local glyphData = data[i]
				valid = IsValid(glyphData, GroupCache:HasGlyph(guid, glyphData) or GroupCache:HasGlyph(guid, -glyphData))
				
				PrintTracking(optionalKeys.GLYPH, guid, glyphData, valid, true)
				if not valid then break end
			end
		else
			valid = IsValid(data, GroupCache:HasGlyph(guid, data) or GroupCache:HasGlyph(guid, -data))
			PrintTracking(optionalKeys.GLYPH, guid, data, valid, true)
		end
	end
	return valid
end

-- buff
validateFilter[optionalKeys.BUFF] = function(data, guid)
	local valid = true
	if data then
		if type(data) == "table" then
			for i = 1, #data do
				local buffData = data[i]
				local buffName = GetSpellInfo(buffData) or GetSpellInfo(-buffData)
				local unit = GetUnitFromGUID(guid)
				valid = IsValid(data, (unit and buffName) and UnitBuff(unit, buffName) ~= nil or false)
				
				PrintTracking(optionalKeys.BUFF, guid, buffName, valid, true)
				if not valid then break end
			end
		else
			local buffName = GetSpellInfo(data) or GetSpellInfo(-data)
			local unit = GetUnitFromGUID(guid)
			valid = IsValid(data, (unit and buffName) and UnitBuff(unit, buffName) ~= nil or false)
			PrintTracking(optionalKeys.BUFF, guid, buffName, valid, true)
		end
	end
	return valid
end

--[[ TODO: including items considerably raises the complexity of the code
			> first, all item-related inspects need to inspect twice (items are not guaranteed to be available on first INSPECT_READY)
			> need to figure out how to cache item info
			> need to possibly reorganize data  (maybe not)
		(the following is half-implemented at best)
--]]
-- item
local itemsToCheckByGUID = {
	--[[
	cache of itemIds we need to check keyed by guid
	this is so we don't have to scrape through data looking for itemIds
	
	TODO: store by slot
	
	form:
	[guid] = {
		[itemId] = true,
		[itemId] = true,
		...
	},
	...
	--]]
	
	Add = function(self, guid, item)
		self[guid] = self[guid] or {}
		self[guid][item] = true
	end,
	
	Remove = function(self, guid, item)
		-- not sure if useful
		local guidItems = self[guid]
		
		if guidItems then
			guidItems[item] = nil
		end
	end,
}

local function CheckEquipmentChange(unit, item)
	addon:FUNCTION("CheckEquipmentChange(%s): %s", tostring(unit), UnitClassColoredName(unit))
	
	for i = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
		--local item = GetInventoryItemID(unit, slot)
		-- http://wowprogramming.com/docs/api/GetItemInfo -> may need timeout..
		--local ilvl = select(4, GetItemInfo(itemLink))
		--local isEquipped = IsEquippedItem(itemLink)
		--[[
			match -> valid
		--]]
	end
end

local itemInspectPending = {
	--[[
	list of people queued for item inspects
	value is a counter to keep track of how many times we have inspected this person
		item information is not guaranteed to be completely available on the first response from server
		so we queue up again on the first response and await the second to actually retreive item information
	
	form:
	[guid] = numInspectsHandled,
	...
	--]]
}
addon.itemInspectPending = itemInspectPending

-- sends off an inspect notification and flags that we want to look up the person's items
local function UnitInspectItems(unit)
	local guid = type(unit) == "string" and UnitGUID(unit)
	if guid then
		if not itemInspectPending[guid] then -- don't queue up another inspect for this person
			itemInspectPending[guid] = 0
			addon:Inspect(unit)
		end
	else
		local msg = "UnitInspectItems(\"%s\") - could not retreive 'guid' from 'unit'"
		addon:DEBUG(msg, tostring(unit))
	end
end

validateFilter[optionalKeys.ITEM] = nil -- TODO: implement

local OLD_ITEM_IMPL = function(data, guid)
	local valid = true
	if data then
		itemsToCheckByGUID:Add(guid, data)
	
		local unit = GetUnitFromGUID(guid)
		
		-- cache the item data we wish to test
		
		
		-- we cannot test yet (lib does not handle for us)
		UnitInspectItems(unit) -- tell the server we want some info
		valid = false -- never passes here
		
		--addon:TRACKING("   [%s] ITEM: wearing %s? %s", GUIDClassColoredName(guid), tostring(buffName), tostring(valid))
		addon:TRACKING("%s[%s]ITEM: |c%suhh|r", INDENT, GUIDClassColoredName(guid), GUIDClassColorStr(guid))
	end
	return valid
end

-- pet
validateFilter[optionalKeys.PET] = function(data, guid)
	local valid = true
	if data then
		if type(data) == "table" then
			for i = 1, #data do
				local petData = data[i]
				local unit = GetUnitFromGUID(guid) or "INVALID_UNIT_ID"
				local unitPet = ("%spet"):format(unit)
				local namePet = ("%s-pet"):format(unit)
				local petFamily = UnitCreatureFamily(unitPet) or UnitCreatureFamily(namePet)
				local negated = petData:sub(1, 1) == "-" and true
				if negated then petData = petData:sub(2) end
				valid = IsValid(negated and -1 or 1, petData == petFamily)
				
				PrintTracking(optionalKeys.PET, guid, petData, valid, true)
				if not valid then break end
			end
		else
			local unit = GetUnitFromGUID(guid) or "INVALID_UNIT_ID"
			local unitPet = ("%spet"):format(unit)
			local namePet = ("%s-pet"):format(unit)
			local petFamily = UnitCreatureFamily(unitPet) or UnitCreatureFamily(namePet)
			local negated = data:sub(1, 1) == "-" and true
			if negated then data = data:sub(2) end
			valid = IsValid(negated and -1 or 1, data == petFamily)
			PrintTracking(optionalKeys.PET, guid, data, valid, true)
		end
	end
	return valid
end

local function CheckFilters(filterData, guid)
	local result = true
	if not GroupCache then
		GroupCache = addon.GroupCache
	end
	
	if filterData then
		for filterKey, filterValue in next, filterData do
			local testFilter = validateFilter[filterKey]
			if type(testFilter) == "function" then
				result = testFilter(filterValue, guid)
				
				-- we do not care about other filters if any filter fails
				-- ie, every filter that exists must pass
				if not result then break end
			end
		end
	end
	return result
end

-- ------------------------------------------------------------------
-- Tracking
-- ------------------------------------------------------------------
local MIN_TIME_BETWEEN_TRACKING = 1 -- number of seconds before tracking is allowed again per person
local lastTrackTime = {
	--[[
	the last time at which :TrackCooldownsFor ran per guid; used for throttling
	(mainly for UNIT_PET which fires in bursts of ~8 and ace-bucket does not seem to actually bucket)
	
	form:
	[guid] = time,
	...
	--]]
}
local cachedData = {} -- work table

-- test if we should track a cooldown modified/given by spec, talents, glyphs, buffs
function addon:TrackCooldownsFor(guid)
	local now = GetTime()
	if now - (lastTrackTime[guid] or 0) >= MIN_TIME_BETWEEN_TRACKING then
		lastTrackTime[guid] = now

		local classColorStr = GUIDClassColorStr(guid)
		local classColoredName = GUIDClassColoredName(guid)
		self:FUNCTION(":TrackCooldownsFor(%s)", classColoredName)
		
		local class = select(2, GetPlayerInfoByGUID(guid))
		if class then
			local classSpells = self:GetClassSpellIdsFromData(class)
			if classSpells then
				for spellid in next, classSpells do
					local spellname = GetSpellInfo(spellid)
					local data = self:GetCooldownDataFor(class, spellid)
					
					self:TRACKING("[%s] Testing data for |c%s%s|r(%s)", classColoredName, classColorStr, tostring(spellname), tostring(spellid))
					-- check the required filters	
					local meetsRequired = CheckFilters(data[FILTER_REQUIRED], guid)
					if meetsRequired then
						-- get the modifiable ability info
						wipe(cachedData)
						cachedData[filterKeys.CD] = data[filterKeys.CD]
						cachedData[filterKeys.CHARGES] = data[filterKeys.CHARGES]
						cachedData[filterKeys.BUFF_DURATION] = data[filterKeys.BUFF_DURATION]
						
						self:TRACKING("%s|c%s%s|r meets required!!!", INDENT:rep(2), classColorStr, tostring(spellname))
						-- check the optional filters
						local optionalFilters = data[FILTER_OPTIONAL]
						if optionalFilters then
							self:TRACKING("%schecking optional filters..", INDENT:rep(2))
							for modKey, modData in next, optionalFilters do
								local applyMod = CheckFilters(modData[FILTER_REQUIRED], guid)
								if applyMod then
									-- apply the modification
									local baseValue = data[modKey]
									local modValue = modData[FILTER_MOD_VALUE]
									local result = self:ApplyModification(modData[FILTER_MOD_OP], baseValue, modValue)
									
									self:TRACKING("%s|c%s%s|r applying modification on %s: %s -> \"%s\"%s -> %s", 
										INDENT:rep(2), classColorStr, spellname, tostring(modKey), tostring(baseValue), tostring(modData[FILTER_MOD_OP]), tostring(modValue), tostring(result)
									)
									if result then
										-- cache the result of the applied modification
										cachedData[modKey] = result
									else
										local msg = ":TrackCooldownsFor(guid): Failed to apply modification \"%s\" to %s (%s) for %s (no op for \"%s\")"
										self:DEBUG(msg, modKey, spellid, tostring(spellname), classColoredName, tostring(modData[FILTER_MOD_OP]))
									end
								end
							end
						end
						
						local duration = cachedData[filterKeys.CD]
						local charges = cachedData[filterKeys.CHARGES]
						local buffDuration = cachedData[filterKeys.BUFF_DURATION]
						self.Cooldowns:Add(spellid, guid, duration, charges, buffDuration)
					else
						-- always try to remove if the person doesn't meet the requirements in case it was added before
						self.Cooldowns:Remove(guid, spellid)
					end
				end
			end
		end
	end
end
