
local tostring, type, next, wipe, select, concat, remove, inf
	= tostring, type, next, wipe, select, table.concat, table.remove, math.inf
local GetNumGroupMembers, GetInspectSpecialization, GetGlyphSocketInfo, GetTalentInfo, GetRaidRosterInfo, GetSpellInfo, GetPlayerInfoByGUID, UnitExists
	= GetNumGroupMembers, GetInspectSpecialization, GetGlyphSocketInfo, GetTalentInfo, GetRaidRosterInfo, GetSpellInfo, GetPlayerInfoByGUID, UnitExists
local GetSpecializationInfo, GetSpecialization, UnitGUID, UnitInRaid, UnitClass, UnitAffectingCombat, UnitIsDeadOrGhost, UnitIsConnected, IsInGroup, IsEncounterInProgress
	= GetSpecializationInfo, GetSpecialization, UnitGUID, UnitInRaid, UnitClass, UnitAffectingCombat, UnitIsDeadOrGhost, UnitIsConnected, IsInGroup, IsEncounterInProgress

local addon = Overseer

local data, consts = addon.data, addon.consts
local classes = consts.classes
local filtersByClass = data.filtersByClass
local filterKeys = consts.filterKeys
local optionalKeys = filterKeys[consts.FILTER_OPTIONAL]
local eventsByFilter = consts.eventsByFilter
local append = addon.TableAppend
local UnitHasFilter = addon.UnitHasFilter
local UnitNeedsInspect = addon.UnitNeedsInspect
local GetUnitFromGUID = addon.GetUnitFromGUID
local UnitClassColoredName, GUIDClassColoredName = addon.UnitClassColoredName, addon.GUIDClassColoredName

local MESSAGES = consts.MESSAGES
local MAX_NUM_TALENTS = MAX_NUM_TALENTS
local NUM_GLYPH_SLOTS = NUM_GLYPH_SLOTS
local CLASS_SCAN_INTERVAL = 5 * 60 -- interval to scan every person of a given class
local TOO_LONG_SINCE_LAST_CLASS_SCAN = 2 * CLASS_SCAN_INTERVAL -- scans become forceable after this amount of time
local SUBGROUP_KEY = "SUBGROUP"
local STATE_KEY = "UNITSTATE"

local RegisterEventsFor, UnregisterEventsFor

-- ------------------------------------------------------------------
-- Group cache
-- ------------------------------------------------------------------
local GroupCache = {
	--[[
	cached group info class
	convenience functions are provided
	--]]
	
	[optionalKeys.SPEC] = { -- last known specIds
		--[[
		[guid] = specId,
		...
		--]]
	},
	
	[optionalKeys.TALENT] = { -- last known talentIds
		--[[
		[guid] = { -- only stores talentIds that guid has
			[talentId] = true, -- guid has talent
			[talentId] = true, -- guid has talent
			...
		},
		...
		--]]
	},
	
	[optionalKeys.GLYPH] = { -- last known glyphs
		--[[
		[guid] = { -- only stores glyphs that guid has
			[glyphId] = true, -- guid has glyph equipped
			[glyphId] = true, -- guid has glyph equipped
			...
		},
		...
		--]]
	},
	
	[optionalKeys.PET] = { -- last known petGUIDs
		--[[
		[petGUID] = [ownerGUID],
		[petGUID] = [ownerGUID],
		...
		--]]
	},
	
	--[[
	[class] = { -- guid by class
		[guid] = true,
		[guid] = true,
		...
	},
	...
	--]]
	
	[SUBGROUP_KEY] = {
		--[[
		[guid] = subGroup,
		[guid] = subGroup,
		...
		--]]
	},
	
	[STATE_KEY] = {
		--[[
		[guid] = {
			dead = bool, -- true if guid is dead
			online = bool, -- true if guid is online
			benched = bool, -- true if guid is benched
		},
		...
		--]]
	},
	
	_GUIDs = {
		--[[
		all cached guids
		
		[guid] = true,
		...
		--]]
	},
}
do -- fill the GroupCache with empty class tables
	for _, class in next, classes do
		if type(class) == "string" then
			GroupCache[class] = GroupCache[class] or {}
		end
	end
end

addon.GroupCache = GroupCache

local function UnitIsBenched(unit)
	local isBenched = true
	if unit and addon.benchGroup then
		local unitGroup = GroupCache:UnitSubgroup(unit)
		if unitGroup then
			local benchGroup = addon.benchGroup
			isBenched = unitGroup >= benchGroup
		end
	end
	return isBenched
end

local function GUIDIsBenched(guid)
	local unit = GetUnitFromGUID(guid)
	return UnitIsBenched(unit)
end

-- ------------------------------------------------------------------
-- Group cache convenience functions
-- ------------------------------------------------------------------
local ClearSpec, ClearTalents, ClearGlyphs, ClearPet, ClearState
local oldState = {} -- work table to help keep track of any changes

function GroupCache:Add(guid, group)
	local isNew = false
	if not self._GUIDs[guid] then
		local class = select(2, GetPlayerInfoByGUID(guid))
		local classCache = self[class]
	
		self._GUIDs[guid] = true
		classCache[guid] = true
		classCache._count = (classCache._count or 0) + 1
		if classCache._count == 1 then
			RegisterEventsFor(class)
		end
		isNew = true
	end
	
	local wasBenched = self:IsBenched(guid)
	self[SUBGROUP_KEY][guid] = group
	self:SetState(guid) -- have to set after groups are set so that bench state is accurate
	-- treat as new if the person changed bench state
	return isNew or wasBenched ~= self:IsBenched(guid)
end

local function RemoveFromClassCache(guid)
	local class = select(2, GetPlayerInfoByGUID(guid))
	if not class then
		-- couldn't get the class (probably cross-realm guid left group)
		for _, c in next, classes do
			if type(c) == "string" then
				local classCache = GroupCache[c]
				if classCache[guid] then
					class = c
					break
				end
			end
		end
	end
	
	local classCache = GroupCache[class]
	classCache[guid] = nil
	
	if classCache._count then -- nil means we :Wipe'd before :Remove'd
		classCache._count = classCache._count - 1
		if classCache._count == 0 then
			UnregisterEventsFor(class)
		elseif classCache._count < 0 then
			local msg = "GroupCache:Remove(%s): incorrect %s count = %d"
			addon:Debug(msg:format(GUIDClassColoredName(guid), tostring(class), classCache._count))
		end
	end
end

function GroupCache:Remove(guid)
	if not self._GUIDs[guid] then return end

	local specs = self[optionalKeys.SPEC]
	if specs then specs[guid] = nil end
	
	local talents = self[optionalKeys.TALENT]
	if talents then talents[guid] = nil end
	
	local glyphs = self[optionalKeys.GLYPH]
	if glyphs then glyphs[guid] = nil end
	
	ClearPet(guid)
	
	local groups = self[SUBGROUP_KEY]
	if groups then groups[guid] = nil end
	
	local state = self[STATE_KEY]
	if state then state[guid] = nil end
	
	RemoveFromClassCache(guid)
	
	self._GUIDs[guid] = nil
end

function GroupCache:Wipe()
	local specs = self[optionalKeys.SPEC]
	if specs then wipe(specs) end
	
	local talents = self[optionalKeys.TALENT]
	if talents then wipe(talents) end
	
	local glyphs = self[optionalKeys.GLYPH]
	if glyphs then wipe(glyphs) end
	
	local pets = self[optionalKeys.PET]
	if pets then wipe(pets) end
	
	local groups = self[SUBGROUP_KEY]
	if groups then wipe(groups) end
	
	local state = self[STATE_KEY]
	if state then wipe(state) end
	
	for _, class in next, classes do
		if type(class) == "string" then
			UnregisterEventsFor(class)
			wipe(self[class])
		end
	end
	
	local guids = self._GUIDs
	if guids then wipe(guids) end
end

-- ------------------------------------------------------------------
-- Spec
-- ------------------------------------------------------------------
function ClearSpec(guid)
	GroupCache[optionalKeys.SPEC][guid] = nil
end

function GroupCache:SetSpec(guid)
	local result = false
	local isPlayer = guid == addon.playerGUID
	local unit = GetUnitFromGUID(guid)
	local specId
	if isPlayer then
		specId = GetSpecializationInfo(GetSpecialization())
	else
		specId = unit and GetInspectSpecialization(unit)
	end
	
	if specId and consts.specs[specId] then
		-- send out messages if there is a change
		wipe(oldState)
		oldState.spec = self[optionalKeys.SPEC][guid] or false
		if oldState.spec ~= specId then
			addon:SendMessage(MESSAGES.GUID_CHANGE_SPEC, guid)
		end
		
		self[optionalKeys.SPEC][guid] = specId
		result = true
	else
		-- this is probably means we tried to get the person's spec too early
		-- TODO: do nothing instead?
		ClearSpec(guid)
	end
	return result
end

-- ------------------------------------------------------------------
-- Talents
-- ------------------------------------------------------------------
function ClearTalents(guid)
	local guidTalents = GroupCache[optionalKeys.TALENT][guid]
	if guidTalents then
		wipe(guidTalents)
	end
end

function GroupCache:SetTalents(guid)
	local result = false
	local isPlayer = guid == addon.playerGUID
	local unit = GetUnitFromGUID(guid)
	if unit then
		local classId = select(3, UnitClass(unit))
		if classId then
			local guidTalents = self[optionalKeys.TALENT][guid]
			if not guidTalents then
				guidTalents = {}
				self[optionalKeys.TALENT][guid] = guidTalents
			end
			
			-- cache previous talents temporarily
			wipe(oldState)
			for talent in next, guidTalents do
				oldState[talent] = true
			end
			ClearTalents(guid)
			-- set new talents
			for i = 1, MAX_NUM_TALENTS do
				local hasTalent = isPlayer and select(5, GetTalentInfo(i)) or select(5, GetTalentInfo(i, true, nil, unit, classId))
				if hasTalent then
					guidTalents[i] = true
				end
			end
			-- broadcast changes
			local diffCount = 0
			for talent in next, oldState do
				local hasTalent
				for _ in next, guidTalents do -- check through all current talents for the old talent
					if guidTalents[talent] then
						hasTalent = true
						break
					end
				end
				diffCount = hasTalent and diffCount or diffCount + 1
			end
			if diffCount > 0 then
				addon:SendMessage(MESSAGES.GUID_CHANGE_TALENT, guid, diffCount)
			end
			result = true
		end
	end
	return result
end

-- ------------------------------------------------------------------
-- Glyphs
-- ------------------------------------------------------------------
function ClearGlyphs(guid)
	local guidGlyphs = GroupCache[optionalKeys.GLYPH][guid]
	if guidGlyphs then
		wipe(guidGlyphs)
	end
end

function GroupCache:SetGlyphs(guid)
	local result = false
	local isPlayer = guid == addon.playerGUID
	local unit = GetUnitFromGUID(guid)
	if unit then
		local guidGlyphs = self[optionalKeys.GLYPH][guid]
		if not guidGlyphs then
			guidGlyphs = {}
			self[optionalKeys.GLYPH][guid] = guidGlyphs
		end
	
		-- cache previous glyphs temporarily
		wipe(oldState)
		for glyph in next, guidGlyphs do
			oldState[glyph] = true
		end
		ClearGlyphs(guid)
		-- set glyphs
		for i = 1, NUM_GLYPH_SLOTS do
			local glyphType, glyphSpellId, _
			if isPlayer then
				glyphType, _, glyphSpellId = select(2, GetGlyphSocketInfo(i))
			else
				glyphType, _, glyphSpellId = select(2, GetGlyphSocketInfo(i, nil, true, unit))
			end
			if glyphType and glyphSpellId then -- glyph socket may be empty
				guidGlyphs[glyphSpellId] = glyphType
			end
		end
		-- broadcast changes
		local diffCount = 0
		for glyph in next, oldState do
			local hasGlyph
			for _ in next, guidGlyphs do -- check through all current glyphs for the old glyph
				if guidGlyphs[glyph] then
					hasGlyph = true
					break
				end
			end
			diffCount = hasGlyph and diffCount or diffCount + 1
		end
		if diffCount > 0 then
			addon:SendMessage(MESSAGES.GUID_CHANGE_GLYPH, guid, diffCount)
		end
		result = true
	end
	return result
end

-- ------------------------------------------------------------------
-- Pet
-- ------------------------------------------------------------------
local PET_CLASSES = { -- TODO? change to UnitHasFilter(unit, optionalKeys.PET).. maybe?
	[classes.hunter] = true,
	[classes.warlock] = true,
	[classes.mage] = true,
}
local function FindPetGUIDByOwnerGUID(ownerGUID)
	local petGUID
	local pets = GroupCache[optionalKeys.PET]
	if pets then
		for pet, owner in next, pets do
			if owner == ownerGUID then
				petGUID = pet
				break
			end
		end
	end
	return petGUID
end

function ClearPet(guid, pet)
	local class = select(2, GetPlayerInfoByGUID(guid))
	if PET_CLASSES[class] then
		local pets = GroupCache[optionalKeys.PET]
		if pets then
			-- try to remove the pet entry for this person
			local petGUID = pet or FindPetGUIDByOwnerGUID(guid)
			if petGUID then
				pets[petGUID] = nil
			end
		end
	end
end

function GroupCache:SetPet(guid)
	local result = false
	local class, _, _, _, name = select(2, GetPlayerInfoByGUID(guid))
	-- try to get the guid's pet guid
	if class and name and PET_CLASSES[class] then
		local petGUID = UnitGUID( ("%s-pet"):format(name) )
		local oldPetGUID = FindPetGUIDByOwnerGUID(guid)
		-- no petGUID either means we cannot see their pet or they do not have one
		-- or it could mean the person is not in our group somehow (see http://wowprogramming.com/docs/api_types#unitID)
		if petGUID then
			self[optionalKeys.PET][petGUID] = guid
		else
			-- pet despawned for some reason, their next pet will receive a new guid
			ClearPet(guid, oldPetGUID)
		end
		-- broadcast pet change (this may not actually mean anything since even the 'same' pet can have different GUIDs)
		-- the only information this conveys is some de/spawning event happened to guid's pet
		if petGUID ~= oldPetGUID and UnitHasFilter(name, optionalKeys.PET) then
			-- TODO: do listeners handle this immediatley or are they sent the message at a later time?
			addon:SendMessage(MESSAGES.GUID_CHANGE_PET, guid, petGUID)
		end
		result = true
	end
	return result
end

-- ------------------------------------------------------------------
-- State (dead/online/benched)
-- ------------------------------------------------------------------
function ClearState(guid)
	local guidState = GroupCache[STATE_KEY][guid]
	if guidState then
		wipe(guidState)
	end
end

function GroupCache:SetState(guid)
	local result = false
	if type(guid) == "string" and guid:len() > 0 then
		local unit = GetUnitFromGUID(guid)
		if unit then
			local guidState = self[STATE_KEY][guid]
			if not guidState then
				guidState = {}
				self[STATE_KEY][guid] = guidState
			end
			-- temporarily store guid's previous state
			wipe(oldState)
			oldState.dead = guidState.dead or false
			oldState.online = guidState.online or false
			oldState.benched = guidState.benched or false
			-- explicitly store false
			guidState.dead = UnitIsDeadOrGhost(unit) or false
			guidState.online = UnitIsConnected(unit) or false
			guidState.benched = UnitIsBenched(unit) or false
			-- send out messages for any state changes
			if oldState.dead ~= guidState.dead then
				addon:SendMessage(MESSAGES.GUID_CHANGE_DEAD, guid)
			end
			if oldState.online ~= guidState.online then
				addon:SendMessage(MESSAGES.GUID_CHANGE_ONLINE, guid)
			end
			if oldState.benched ~= guidState.benched then
				addon:SendMessage(MESSAGES.GUID_CHANGE_BENCHED, guid)
			end
			result = true
		end
	else
		-- set states for all known guids
		local states = self[STATE_KEY]
		if states then
			for guid in next, states do
				if type(guid) == "string" and guid:len() > 0 then -- just in case.. don't want a stack overflow
					self:SetState(guid)
				end
			end
		end
	end
	return result
end

-- ------------------------------------------------------------------
-- Getters
-- ------------------------------------------------------------------
function GroupCache:Spec(guid)
	return self[optionalKeys.SPEC] and self[optionalKeys.SPEC][guid]
end

function GroupCache:NumTalents(guid)
	local numTalents = 0
	local guidTalents = self[optionalKeys.TALENT] and self[optionalKeys.TALENT][guid]
	if guidTalents then
		for _ in next, guidTalents do
			numTalents = numTalents + 1
		end
	end
	return numTalents
end

function GroupCache:NumGlyphs(guid, type)
	local numGlyphs = 0
	local guidGlyphs = self[optionalKeys.GLYPH] and self[optionalKeys.GLYPH][guid]
	if guidGlyphs then
		for _, glyphType in next, guidGlyphs do
			if not type or type == glyphType then
				numGlyphs = numGlyphs + 1
			end
		end
	end
	return numGlyphs
end

function GroupCache:HasTalent(guid, talent)
	local guidTalents = self[optionalKeys.TALENT] and self[optionalKeys.TALENT][guid]
	return guidTalents and guidTalents[talent]
end

function GroupCache:HasGlyph(guid, glyph)
	local guidGlyphs = self[optionalKeys.GLYPH] and self[optionalKeys.GLYPH][guid]
	return guidGlyphs and guidGlyphs[glyph]
end

function GroupCache:PetOwnerGUID(petGUID)
	return self[optionalKeys.PET] and self[optionalKeys.PET][petGUID]
end

function GroupCache:Subgroup(guid)
	return self[SUBGROUP_KEY][guid]
end

function GroupCache:UnitSubgroup(unit)
	local guid = UnitGUID(unit)
	if guid and guid:len() > 0 then
		return self:Subgroup(guid)
	end
end

function GroupCache:IsDead(guid)
	local guidState = guid and self[STATE_KEY] and self[STATE_KEY][guid]
	return guidState and guidState.dead
end

function GroupCache:IsOffline(guid)
	local guidState = guid and self[STATE_KEY] and self[STATE_KEY][guid]
	return guidState and not guidState.online
end

function GroupCache:IsBenched(guid)
	local guidState = guid and self[STATE_KEY] and self[STATE_KEY][guid]
	return guidState and guidState.benched
end

function GroupCache:SetPlayerInfo()
	local playerGUID = addon.playerGUID
	if not playerGUID then
		local msg = "GroupCache:SetPlayerInfo(): Player GUID not set yet! Setting now.."
		addon:Debug(msg)
		
		playerGUID = UnitGUID("player")
		addon.playerGUID = playerGUID
	end
	
	if playerGUID then
		self:SetSpec(playerGUID)
		self:SetTalents(playerGUID)
		self:SetGlyphs(playerGUID)
		self:SetPet(playerGUID)
		self:SetState(playerGUID)
	else
		local msg = "GroupCache:SetPlayerInfo(): |cffFF0000Could not retreive player GUID!|r"
		addon:Debug(msg)
	end
end

-- ------------------------------------------------------------------
-- Debugging
-- ------------------------------------------------------------------
do
	-- http://wowprogramming.com/docs/api_types#guid
	local AND = bit.band
	local GUID_TYPE_PLAYER = 0
	local GUID_TYPE_PET = 4
	local function IsGUIDPlayer(guid)
		-- eg, "0xF530007EAC083004"
		-- not perfect, but should be good enough
		local result = false
		if type(guid) == "string" then
			local isGUID = guid:len() == 18
			local maskedUnitType = (tonumber(guid:sub(5,5), 16) or -1) % 8
			result = isGUID and maskedUnitType == GUID_TYPE_PLAYER
		end
		return result
	end
	addon.IsGUIDPlayer = IsGUIDPlayer

	local indent = consts.INDENT
	local empty = consts.EMPTY
	local function debugHeader(header, indentLevel)
		indentLevel = indentLevel or 0
		addon:Print(("%s|cffFF00FF>|r%s"):format(indent:rep(indentLevel), header), true)
	end

	local function debugEmpty(indentLevel)
		indentLevel = indentLevel or 1
		addon:Print(("%s%s"):format(indent:rep(indentLevel), empty), true)
	end

	local function debugCache(cache, indentLevel)
		local printedSomething
		indentLevel = indentLevel or 1
		for k, v in next, cache do
			printedSomething = true
			if IsGUIDPlayer(k) then
				k = GUIDClassColoredName(k)
			end
			
			if type(v) == "table" then
				debugHeader(k, indentLevel)
				if not debugCache(v, indentLevel+1) then
					-- v is an empty table
					debugEmpty(indentLevel+1)
				end
			else
				-- leaf
				if IsGUIDPlayer(v) then
					v = GUIDClassColoredName(v)
				end
				
				addon:Print(("%s%s=%s"):format(indent:rep(indentLevel), tostring(k), tostring(v)), true)
			end
		end
		return printedSomething
	end

	local validGroupCacheKeys = {}
	function GroupCache:Debug(key)
		addon:Print("GroupCache: ===============", true)
		if type(key) == "string" then
			key = key:upper()
			local cache = self[key]
			if type(cache) == "table" then
				debugHeader(key)
				if not debugCache(cache) then
					debugEmpty()
				end
			else
				if #validGroupCacheKeys == 0 then
					for k, v in next, self do
						if type(v) == "table" then
							append(validGroupCacheKeys, tostring(k))
						end
					end
				end
				addon:Print( ("%sNo such key='%s'. Valid keys={%s}"):format(indent, key, concat(validGroupCacheKeys, ", ")), true )
			end
		else
			-- print all
			for k, cache in next, self do
				if type(cache) == "table" then
					debugHeader(k)
					if not debugCache(cache) then
						debugEmpty()
					end
				end
			end
		end
	end

	function GroupCache:UnitDebug(guid)
		local input = guid
		if UnitExists(guid) then
			guid = UnitGUID(guid) -- allow unitId input
		end
		
		if IsGUIDPlayer(guid) then
			addon:Print(("GroupCache[%s]:"):format(GUIDClassColoredName(guid)), true)
			for k, cache in next, self do
				if type(cache) == "table" then
					-- special case pet (not keyed by unit guid)
					if k ~= optionalKeys.PET then
						if cache[guid] then
							debugHeader(k)
							if type(cache[guid]) == "table" then
								if not debugCache(cache[guid]) then
									debugEmpty()
								end
							else
								addon:Print(("%s%s=%s"):format(indent, GUIDClassColoredName(guid), tostring(cache[guid])), true)
							end
						end
					else
						for pet, owner in next, cache do
							if owner == guid then
								debugHeader(k)
								addon:Print(("%s%s=%s"):format(indent, tostring(pet), GUIDClassColoredName(owner)), true)
								break
							end
						end
					end
				end
			end
		else
			addon:Print(("GroupCache:UnitDebug() - could not get guid from '%s'"):format(tostring(input)), true)
		end
	end

	local unitKeys = {
		["player"] = true,
		["raid"] = true,
		["party"] = true,
		["target"] = true,
		["focus"] = true,
	}
	local function IsPossibleUnitId(input)
		local result = false
		for unit in next, unitKeys do
			result = input:match(unit) and true
			if result then break end
		end
		return result
	end

	-- convenience wrapper (syntax conforms to other debug functions)
	function addon:DebugGroupCache(key)
		if type(key) == "string" and (UnitExists(key) or IsPossibleUnitId(key:lower())) then
			GroupCache:UnitDebug(key)
		else
			-- assume the user wanted an actual key into the group cache
			GroupCache:Debug(key)
		end
	end
end

-- ------------------------------------------------------------------
-- Class registration
-- ------------------------------------------------------------------
-- listen to events that we may not have needed before
function RegisterEventsFor(class)
	-- register events for the filters pertaining to this class
	local filtersForClass = filtersByClass[class]
	if filtersForClass then
		for filter in next, filtersForClass do
			local event = eventsByFilter[filter]
			if type(event) == "table" then
				-- we need to handle multiple events
				for i = 1, #event do
					addon:RegisterCustomEventOrWOWEvent(event[i])
				end
			elseif type(event) == "string" then
				-- just a single event
				addon:RegisterCustomEventOrWOWEvent(event)
			end
		end
	end
end

function UnregisterEventsFor(class)
	-- unregister
	local filtersForClass = filtersByClass[class]
	if filtersForClass then
		for filter in next, filtersForClass do
			local event = eventsByFilter[filter]
			if type(event) == "table" then
				-- we need to handle multiple events
				for i = 1, #event do
					addon:UnregisterCustomEventOrWOWEvent(event[i])
				end
			elseif type(event) == "string" then
				-- just a single event
				addon:UnregisterCustomEventOrWOWEvent(event)
			end
		end
	end
end

-- ------------------------------------------------------------------
-- Group scan
-- ------------------------------------------------------------------
local invalidGUIDs
local currentMembers = {}
local removedMembers = {}

local function GroupMemberJoin(guid)
	local unit = GetUnitFromGUID(guid)
	-- try to track immediately in case there are cooldowns we don't need inspect data for
	addon:TrackCooldownsFor(guid)
	if UnitNeedsInspect(unit) then
		addon:Inspect(unit)
	end
	addon:SendMessage(MESSAGES.GUID_JOIN, guid)
end

local function GroupMemberLeave(guid)
	addon:SendMessage(MESSAGES.GUID_LEAVE, guid)
	addon:CancelInspect(guid)
	addon.Cooldowns:Remove(guid)
	GroupCache:Remove(guid)
end

function addon:ScanGroup(force)
	if not force and self.isFightingBoss then
		-- don't scan if we're fighting a boss
		-- this is a problem if a raid member leaves the group while a boss encounter is in progress
		-- ie, we will continue to show the tracked spell for the person even though they left the group
		--		which itself is not a problem if the person has not left the instance
		-- 		honestly, this situation probably indicates an imminent wipe anyway
		self.groupScanDelayed = true
		return
	elseif not IsInGroup() then
		return
	end
	self:PrintFunction(":ScanGroup()")

	invalidGUIDs = 0
	wipe(currentMembers)
	wipe(removedMembers)
	
	-- scan the group for subgroup changes
	-- TODO: lfr/x-realm group members aren't always tracked? (something is broken between here & display messages firing)
	local NUM_GROUP_MEMBERS = GetNumGroupMembers()
	for i = 1, NUM_GROUP_MEMBERS do
		local name, _, group, _, _, class = GetRaidRosterInfo(i)
		if name then
			local guid = UnitGUID(name)
			if guid and guid:len() > 0 then
				-- cache available info for guid
				local isNew = GroupCache:Add(guid, group)
				if isNew then
					GroupMemberJoin(guid)
				end
				
				-- keep track of current members
				currentMembers[guid] = true
			else
				invalidGUIDs = invalidGUIDs + 1
			end
		end
	end
	
	-- check for group members who have left or been kicked
	-- we need two loops because we are modifying the object we are looping through
	local groupGUIDs = GroupCache._GUIDs
	if groupGUIDs then
		for guid in next, groupGUIDs do
			if not currentMembers[guid] then
				removedMembers[guid] = true
			end
		end
	end
	for guid in next, removedMembers do
		GroupMemberLeave(guid)
	end
	
	if invalidGUIDs > 0 then
		local msg = ":ScanGroup() %d GUIDs were invalid"
		self:Debug(msg:format(invalidGUIDs))
	end
end
