
local select, wipe, tonumber, tostring, type, inf
	= select, wipe, tonumber, tostring, type, math.huge
local GetTime, IsInGroup, UnitIsDeadOrGhost, UnitClass, UnitBuff, UnitIsFeignDeath, UnitCreatureFamily, IsEncounterInProgress, GetSpellInfo
	= GetTime, IsInGroup, UnitIsDeadOrGhost, UnitClass, UnitBuff, UnitIsFeignDeath, UnitCreatureFamily, IsEncounterInProgress, GetSpellInfo

local addon = Overseer

local data, consts = addon.data, addon.consts
local filtersByClass = data.filtersByClass
local filterKeys = consts.filterKeys
local optionalKeys = filterKeys[consts.FILTER_OPTIONAL]
local Cooldowns = addon.Cooldowns
local GroupCache = addon.GroupCache
local GUIDClassColoredName = addon.GUIDClassColoredName
local GetGUIDType = addon.GetGUIDType

-- ------------------------------------------------------------------
-- CLEU message registration
-- ------------------------------------------------------------------
local messageSubscribers = {
	-- a simple counting system to enable/disable any given CLEU message
	-- unhandled or invalid messages are ignored
	--
	-- form:
	--		[message] = uint
	
	_total = 0, -- the total number of subscribtions
}

local REGISTER_COLOR = addon.REGISTER_COLOR
function addon:SubscribeCLEUEvent(message)
	local numSubs = messageSubscribers[message] or 0
	messageSubscribers[message] = numSubs + 1
	
	local total = messageSubscribers._total
	total = total + 1
	if total == 1 then
		self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	end
	messageSubscribers._total = total
	
	self:FUNCTION(":|c%sSubscribeCLEUEvent|r(|cff999999%s|r): |cff00FF00%s|r (total=|cff00FF00%s|r)", REGISTER_COLOR, message, tostring(messageSubscribers[message]), tostring(total))
end

function addon:UnsubscribeCLEUEvent(message)
	local numSubs = messageSubscribers[message]
	if type(numSubs) == "number" then
		numSubs = numSubs - 1
		messageSubscribers[message] = numSubs
		
		if numSubs < 0 then
			-- TODO: this check is unneeded, but may be helpful for debugging
			local msg = ":UnsubscribeCLEUEvent(%s) - number of Unregister calls exceeded Register calls for given message (numSubs=|cffFF0000%d|r)"
			self:DEBUG(msg, tostring(message), numSubs)
		elseif numSubs == 0 then
			messageSubscribers[message] = nil
		end
		
		local total = messageSubscribers._total
		total = total - 1
		if total == 0 then
			self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
		elseif total < 0 then
			-- this could just mean we :UnregisterAll'd
			local msg = ":UnsubscribeCLEUEvent(%s): total unsubs exceeds initial subs (total=|cffFF0000%s|r)"
			self:DEBUG(msg, message, tostring(total))
		end
		messageSubscribers._total = total
		
		self:FUNCTION(":|c%sUnsubscribeCLEUEvent|r(|cff999999%s|r): |cff00FF00%s|r (total=|cff00FF00%s|r)", REGISTER_COLOR, message, tostring(messageSubscribers[message]), tostring(total))
	else
		-- this may mean :UnregisterAllCLEUMessages was called prior to this
		local msg = ":UnsubscribeCLEUEvent(%s) - has no subs!!"
		self:DEBUG(msg, tostring(message))
	end
end

function addon:UnregisterAllCLEUMessages()
	wipe(messageSubscribers)
	messageSubscribers._total = 0
	
	self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end

-- ------------------------------------------------------------------
-- CLEU message handlers
-- ------------------------------------------------------------------
local cleu = {}

local function TestForEncounterEngage()
	if IsEncounterInProgress() then
		addon:EngageBoss()
	end
end

cleu["SWING_DAMAGE"] = TestForEncounterEngage
cleu["RANGE_DAMAGE"] = TestForEncounterEngage
cleu["SPELL_DAMAGE"] = TestForEncounterEngage
cleu["SPELL_PERIODIC_DAMAGE"] = TestForEncounterEngage

--[[ TODO: OLD - moved to UNIT_SPELLCAST_SUCCEEDED
cleu["SPELL_CAST_SUCCESS"] = -- handle when tracked cds are cast
	function(spellid, spellname, srcInGroup, destInGroup, srcGUID, srcName, destGUID, destName)
		if srcInGroup and Cooldowns[spellid] then
			local cd = srcGUID and srcGUID:len() > 0 and Cooldowns[spellid][srcGUID]
			if cd then
				local msg = "%s casted %s (%s) on %s"
				addon:CLEU(msg, GUIDClassColoredName(srcGUID), tostring(spellid), tostring(spellname), GUIDClassColoredName(destGUID))
				cd:Use()
			else
				-- inspection data has not come back
				-- ie, we are not tracking this spellid for this person yet
				local msg = "MISSED TRACKING: %s casted %s (%s) on %s"
				addon:CLEU(msg, GUIDClassColoredName(srcGUID), tostring(spellid), tostring(spellname), GUIDClassColoredName(destGUID))
			end
		end
	end
--]]

local function UnitHasFilterForBuff(unit, buffSpellId)
	local class = select(2, UnitClass(unit))
	local classBuffIds = addon:GetClassBuffIdsFromData(class)
	return classBuffIds and classBuffIds[buffSpellId]
end

local SOULSTONE_ID = consts.SOULSTONE_ID
cleu["SPELL_AURA_APPLIED"] = -- handle buffs gained
	function(spellid, spellname, srcInGroup, destInGroup, srcGUID, srcName, destGUID, destName)
		if destInGroup and destName then
			-- account for pre-cast soulstone for brezzes
			if spellid == SOULSTONE_ID and not UnitIsDeadOrGhost(destName) then
				addon:CastBrezOn(destGUID, srcGUID, true)
			elseif UnitHasFilterForBuff(destName, spellid) then
				addon:TrackCooldownsFor(destGUID)
				
				local msg = "%s gained buff %s (%s)"
				addon:CLEU(msg, GUIDClassColoredName(destGUID), tostring(spellid), tostring(spellname))
			end
		end
	end

cleu["SPELL_AURA_REMOVED"] = -- handle buffs lost
	function(spellid, spellname, srcInGroup, destInGroup, srcGUID, srcName, destGUID, destName)
		if destInGroup and destName then
			if UnitHasFilterForBuff(destName, spellid) then
				addon:TrackCooldownsFor(destGUID)
				
				local msg = "%s lost buff %s (%s)"
				addon:CLEU(msg, GUIDClassColoredName(destGUID), tostring(spellid), tostring(spellname))
			end
		end
	end

local PLAYER = consts.GUID_TYPES.PLAYER
local PET = consts.GUID_TYPES.PET
local SpiritOfRedemption = GetSpellInfo(20711)
local FeignDeath = GetSpellInfo(5384)
cleu["UNIT_DIED"] = -- handle deaths
	function(spellid, spellname, srcInGroup, destInGroup, srcGUID, srcName, destGUID, destName)
		if destGUID == nil then return end -- may happen if pet despawns
		
		-- http://wowpedia.org/API_UnitGUID
		-- x % 8 has the same effect as x & 0x7 for x <= 0xf
		-- this magic math masks the unit type out of the guid
		local unitType = GetGUIDType(destGUID)
		if unitType == PLAYER and destInGroup then
			local isSOR = UnitBuff(destName, SpiritOfRedemption)
			local isFD = UnitBuff(destName, FeignDeath)
			-- be extra super sure that the person died for real
			if not (UnitIsFeignDeath(destName) or isSOR or isFD) then
				-- cannot check IsEncounterInProgress because ENCOUNTER_START sometimes fires immediately after _END
				-- if someone dies after a false ENCOUNTER_START (eg. Spirit of Redemption), 
				-- then IsEncounterInProgress yield true which will spin up the brez scanner
				if addon.isFightingBoss then
					-- handle brez state
					local rezExpire = addon:GUIDPendingRezExpireTime(destGUID)
					if rezExpire then
						if rezExpire < 0 then
							-- precast soulstone => give them a pending rez expiry timer
							addon:CastBrezOn(destGUID)
						else
							-- we missed this person resurrecting (they rezzed -> died within our scan interval)
							addon:AcceptBrezFor(destGUID)
						end
					end
					addon:AddToDeadList(destGUID)
				else
					-- boot up out-of-combat res scanner
					addon:StartOoCResScan()
				end
			end
			GroupCache:SetState(destGUID)
			-- potential pet owner death - next pet they summon will have a new guid
			GroupCache:SetPet(destGUID)
			
			addon:CLEU("%s died", GUIDClassColoredName(destGUID))
		elseif unitType == PET then
			-- a pet died - find its owner & see if we need to stop tracking anything
			local ownerGUID = GroupCache:PetOwnerGUID(destGUID)
			if ownerGUID then
				GroupCache:SetPet(ownerGUID)
				
				-- there's no guarantee that the person resummons the same pet or any pet at all
				-- re-check all their cooldowns (removing ones that this pet provided - if any)
				addon:TrackCooldownsFor(ownerGUID)
			end
		end
	end

cleu["SPELL_RESURRECT"] = -- handle resurrects (combat and non-combat)
	function(spellid, spellname, srcInGroup, destInGroup, srcGUID, srcName, destGUID, destName)
		if addon.isFightingBoss and destInGroup then
			-- add the person to the pending rez table
			-- if the same person is rezzed multiple times while dead, we want to keep refreshing the expire time
			-- because fuck communication
			if UnitIsDeadOrGhost(destName) then
				addon:CastBrezOn(destGUID, srcGUID)
			end
		end
	end

-- ------------------------------------------------------------------
-- CLEU Event handler
-- ------------------------------------------------------------------
local bit = bit
local OR, AND = bit.bor, bit.band
local GROUP_MASK = OR(COMBATLOG_OBJECT_AFFILIATION_MINE, COMBATLOG_OBJECT_AFFILIATION_PARTY, COMBATLOG_OBJECT_AFFILIATION_RAID)

local function weCareAboutThisCLEU(message, srcGUID, destGUID)
	local srcIsBenched = srcGUID and GroupCache:IsBenched(srcGUID)
	local dstIsBenched = destGUID and GroupCache:IsBenched(destGUID)
	return message and (messageSubscribers[message] or 0) > 0
		and type(cleu[message]) == "function"
		and not srcIsBenched -- note: this works because GroupCache:IsBenched defaults to false if 
		and not dstIsBenched -- 	the passed-in guid is not found
end

function addon:COMBAT_LOG_EVENT_UNFILTERED(event, timestamp, message, hideCaster, srcGUID, srcName, srcFlags, srcRaidFlags, destGUID, destName, destFlags, destRaidFlags, spellid, spellname)
    if IsInGroup() then
        if weCareAboutThisCLEU(message, srcGUID, destGUID) then
			local srcInGroup = (srcGUID or ""):len() > 0 and AND(srcFlags or 0, GROUP_MASK) > 0
			local destInGroup = (destGUID or ""):len() > 0 and AND(destFlags or 0, GROUP_MASK) > 0
			
			cleu[message](spellid, spellname, srcInGroup, destInGroup, srcGUID, srcName, destGUID, destName)
        end
    end
end
