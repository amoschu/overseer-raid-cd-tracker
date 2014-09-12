
local tostring
	= tostring
local GetTime, CanInspect, IsInGroup, UnitClass, UnitGUID, UnitIsConnected, UnitIsDeadOrGhost, GetInstanceInfo, GetRealZoneText, GetNumGroupMembers, GetRaidRosterInfo, IsEncounterInProgress
	= GetTime, CanInspect, IsInGroup, UnitClass, UnitGUID, UnitIsConnected, UnitIsDeadOrGhost, GetInstanceInfo, GetRealZoneText, GetNumGroupMembers, GetRaidRosterInfo, IsEncounterInProgress

local addon = Overseer

local data, consts = addon.data, addon.consts
local filterKeys = consts.filterKeys
local optionalKeys = filterKeys[consts.FILTER_OPTIONAL]
local filtersByClass = data.filtersByClass
local GroupCache = addon.GroupCache
local UnitHasFilter = addon.UnitHasFilter
local UnitNeedsInspect = addon.UnitNeedsInspect
local UnitClassColorStr = addon.UnitClassColorStr
local GUIDClassColoredName, UnitClassColoredName = addon.GUIDClassColoredName, addon.UnitClassColoredName
local InspectUnitAfterDelay -- fwd declare

local MESSAGES = consts.MESSAGES
--[[ not used, kept just in case it is ever need
local IS_RESURRECT = {
	-- all resurrect spellids - this is to try to catch people returning to life outside of combat
	[8342] = true, -- jumper cables
	[22999] = true, -- jumper cables xl
	[54732] = true, -- gnomish army knife
	[83968] = true, -- mass res
	
	[2006] = true, -- priest
	[2008] = true, -- shaman
	[7328] = true, -- paladin
	[50769] = true, -- druid
	[115178] = true, -- monk
	
	-- combat res.. just in case
	[61999] = true, -- dk
	[20484] = true, -- druid
	[20707] = true, -- warlock
	[126393] = true, -- hunter (quillen)
	[113269] = true, -- paladin (holy symbiosis)
}
--]]

-- ------------------------------------------------------------------
-- GROUP
-- fired when people release?
-- ------------------------------------------------------------------
function addon:GROUP_ROSTER_UPDATE()
	self:FUNCTION("GROUP_ROSTER_UPDATE")

	if not IsInGroup() then
		self:Disable()
	else
		-- update the cache since this event gives us no useful information
		self:ScanGroup()
	end
end

-- ------------------------------------------------------------------
-- PLAYER_
-- ------------------------------------------------------------------
function addon:PLAYER_LOGIN(event)
	self:FUNCTION(event)
	
	addon:UpdateClassColors()
	-- start processing the inspect queue if there are any queued
	-- (not sure how this would happen - /reload in group, perhaps?)
	self:ProcessInspects()
end

function addon:PLAYER_REGEN_ENABLED(event)
	self:FUNCTION(event)
	
	if not self.isFightingBoss then
		self:LoadOptions() -- try to load the options in case the user tried to load it in combat
	
		if self.groupScanDelayed then
			self.groupScanDelayed = nil
			self:ScanGroup()
		end
	end
end

--[[
	catches:
		player changing specs (by dual-spec activation or respeccing)
		player changing talents (fires on unlearn & learning new)
		player changing glyphs (fires on glyph removal and socket)
		..also fires randomly (like when player zones in/out of instance)
	unsure how reliable this event is for other people
--]]
function addon:PLAYER_SPECIALIZATION_CHANGED(event, unit)
	self:FUNCTION("%s(%s)", event, UnitClassColoredName(unit))
	
	if unit then -- fires with nil when it responds to a non-spec change..
		local guid = UnitGUID(unit)
		if guid then
			if self.playerGUID == guid then -- handle the player
				-- update the cached state of the player
				GroupCache:SetPlayerInfo()
				self:TrackCooldownsFor(self.playerGUID)
			end
		end
	end
end

-- ------------------------------------------------------------------
-- ENCOUNTER
-- ------------------------------------------------------------------
local watchCLEUForEncounter
function addon:EngageBoss()
	if IsEncounterInProgress() and not self.isFightingBoss then
		self.isFightingBoss = true
		self:EnableBrezScan()
		self:HaltOoCResScan() -- in case a boss is pulled while someone is still dead
		if watchCLEUForEncounter then
			watchCLEUForEncounter = nil
			-- for the purposes of detecting a boss encounter, we no longer need these
			self:UnsubscribeCLEUEvent("SWING_DAMAGE")
			self:UnsubscribeCLEUEvent("RANGE_DAMAGE")
			self:UnsubscribeCLEUEvent("SPELL_DAMAGE")
			self:UnsubscribeCLEUEvent("SPELL_PERIODIC_DAMAGE")
		end
		
		self:SendMessage(MESSAGES.BOSS_ENGAGE) -- TODO? need to send args? don't think so..
	end
end

function addon:ENCOUNTER_START(event, encounterID, encounterName, difficultyId, raidSize)
	if event then
		self:FUNCTION(true, "ENCOUNTER_START(eId=%s, eName=%s, difficulty=%s, raidSize=%s): IsEncounterInProgress()? %s", 
			tostring(encounterID), tostring(encounterName), tostring(difficultyId), tostring(raidSize), tostring(IsEncounterInProgress())
		)
	else
		self:FUNCTION(true, "FAKE ENCOUNTER_START(): IsEncounterInProgress()? %s", tostring(IsEncounterInProgress()))
	end
	
	if IsEncounterInProgress() then
		self:EngageBoss()
	elseif not watchCLEUForEncounter then
		watchCLEUForEncounter = true
		-- the boss may not actually be engaged
		-- this sometimes fires when wiping (with no paired _END event when the actual wipe happens)
		-- moreover, no additional _START event is fired for the next pull
		-- so, let's watch for some relevant CLEUs that may indicate that we actually engaged a boss
        -- I believe this happens when a priest SOR is hanging around when the boss despawns (_END event is thrown)
		self:SubscribeCLEUEvent("SWING_DAMAGE")
		self:SubscribeCLEUEvent("RANGE_DAMAGE")
		self:SubscribeCLEUEvent("SPELL_DAMAGE")
		self:SubscribeCLEUEvent("SPELL_PERIODIC_DAMAGE")
	end
end

local function DisengageBoss(isWipe)
	-- note: cannot check IsEncounterInProgress b/c the _END event is sometimes thrown before the api call yields false
	if addon.isFightingBoss then
		addon.isFightingBoss = nil
		addon:DisableBrezScan()
		addon.Cooldowns:ResetCooldowns()
		addon:StartOoCResScan() -- will scan once if none dead
		
		addon:SendMessage(MESSAGES.BOSS_END, isWipe)
	end
end

function addon:ENCOUNTER_END(event, encounterID, encounterName, difficultyId, raidSize, win)
	self:FUNCTION(true, "ENCOUNTER_END(eId=%s, eName=%s, difficulty=%s, raidSize=%s, win=%s)", 
		tostring(encounterID), tostring(encounterName), tostring(difficultyId), tostring(raidSize), tostring(win)
	)
	
	-- this should catch any relevant group member swaps
	self:SetPlayerZone()
	
	DisengageBoss((win or 0) == 0)
	self:ProcessInspects() -- start up queued inspects since we are out of combat with a boss
end

function addon:CHALLENGE_MODE_COMPLETED(event, ...)
	addon:FUNCTION(true, "%s(%s)", event)
	
	self.Cooldowns:ResetCooldowns()
end

-- ------------------------------------------------------------------
-- SPELLCAST
-- ------------------------------------------------------------------
local delayInspectTimers = {} -- by guid
local DELAY_BEFORE_INSPECT = 5 -- a long-ish delay to hopefully catch all talent/glyph changes before making an attempt to query the server
		-- TODO: this may cause the tracked state to be incorrect if someone changes spec/talent/glyphs within 'DELAY' seconds of pulling a boss
--[[local]] function InspectUnitAfterDelay(unit)
	local guid = UnitGUID(unit)
	if guid and guid:len() > 0 then
		-- no need to inspect the player - we can use the PLAYER_* specific events for that
		if addon.playerGUID ~= guid then
			local timerId = delayInspectTimers[guid]
			-- cancel existing
			if timerId and addon:TimeLeft(timerId) > 0 then
				-- this could mean guid changed their active spec more than once before we inspected
				-- or s/he changed talents/glyphs
				-- whatever the case, we don't want to queue an additional inspect
				addon:CancelTimer(timerId)
			end
			
			-- fire an inspect after delay
			-- may have to wait even longer depending on queue status
			delayInspectTimers[guid] = addon:ScheduleTimer("Inspect", DELAY_BEFORE_INSPECT, unit)
			addon:FUNCTION(true, "InspectUnitAfterDelay(%s)", UnitClassColoredName(unit))
		end
	else
		local msg = "InspectUnitAfterDelay(%s) - could not retreive 'guid' from '%s'"
		addon:DEBUG(msg, UnitClassColoredName(unit), tostring(unit))
	end
end

-- tracking
local function DebugMissedTracking(unit, spellid, spellname)
	local msg = "|cffFF0000MISSED|r: %s casted |c%s%s|r(%s)"
	addon:DEBUG(msg, UnitClassColoredName(unit), UnitClassColorStr(unit), tostring(spellname), tostring(spellid))
end

local function UnitCastSpell(unit, spellid, spellname)
	-- check if we're tracking this spell
	local spellCooldowns = addon.Cooldowns[spellid]
	
	-- in theory, could start tracking here if the spell is not currently tracked for the person
	--[[
		problem(s):
			- how to handle modifications? eg, glyph modifies cd by N minutes - track ability with or without glyph?
				> solved by forcing an inspect; however, there is no telling when the info comes back..
				
			for now, just going to leave untracked and let normal flow handle
	--]]
	
	if spellCooldowns then
		local guid = UnitGUID(unit)
		if guid and guid:len() > 0 then
			local cd = spellCooldowns[guid]
			if not cd then
				-- a pet may have casted the spell
				-- (keep guid the same as to not fuck up any logging if no owner found)
				guid = GroupCache:PetOwnerGUID(guid) or guid
				cd = spellCooldowns[guid]
			end
			
			if cd then
				local msg = "%s casted %s (%s)"
				addon:CLEU(msg, GUIDClassColoredName(guid), tostring(spellid), tostring(spellname))
				
				cd:Use()
			else
				-- a spell we care about was casted by someone who we are not tracking the spell for
				-- possible reason: inspection data has not come back yet
				DebugMissedTracking(unit, spellid, spellname)
			end
		else
			-- invalid unit somehow
			local msg = "UNIT_SPELLCAST_SUCCEEDED(%s, %s, %s) - could not retreive 'guid' from 'unit', \"%s\""
			addon:DEBUG(msg, UnitClassColoredName(unit), tostring(spellname), tostring(spellid), tostring(unit))
		end
	else
		-- check data for this spell
		local class = select(2, UnitClass(unit))
		local classSpells = addon:GetClassSpellIdsFromData(class)
		if classSpells and classSpells[spellid] then
			-- this person casted a spell which we have data for,
			-- yet we are tracking no one for this spell (the Cooldowns[spellid] was not created)
			DebugMissedTracking(unit, spellid, spellname)
		end
	end
end

local specActivation = {}
do
	local TALENT_ACTIVATION_SPELLS = TALENT_ACTIVATION_SPELLS
	for i = 1, #TALENT_ACTIVATION_SPELLS do
		local spellid = TALENT_ACTIVATION_SPELLS[i]
		specActivation[spellid] = true
	end
end

local function DebugGetHasFilterColor(hasFilter)
	return hasFilter and "00FF00" or "FF0000"
end

local function IsSpecActivation(unit, spellid)
	local result = false
	if specActivation[spellid] then
		result = UnitHasFilter(unit, optionalKeys.SPEC)
		addon:DEBUG("|cffFF0000IsSpecActivation|r(): %s changed specs! (hasFilter? |cff%s%s|r)", UnitClassColoredName(unit), DebugGetHasFilterColor(result), tostring(result))
	end
	
	return result
end

local TALENT_REMOVE_ID = 113873 -- spellname = Remove Talent
local function IsTalentChange(unit, spellid)
	local result = false
	if spellid == TALENT_REMOVE_ID then
		result = UnitHasFilter(unit, optionalKeys.TALENT)
		addon:DEBUG("|cffFF0000IsTalentChange|r(): %s changed talents! (hasFilter? |cff%s%s|r)", UnitClassColoredName(unit), DebugGetHasFilterColor(result), tostring(result))
	end
	
	return result 
end

local GLYPH_CHANGE_ID = 111621 -- spellname = Tome of the Clear Mind (seems to only fire for glyphs)
local function IsGlyphChange(unit, spellid)
	local result = false
	if spellid == GLYPH_CHANGE_ID then
		result = UnitHasFilter(unit, optionalKeys.GLYPH)
		addon:DEBUG("|cffFF0000IsGlyphChange|r(): %s changed glyphs! (hasFilter? |cff%s%s|r)", UnitClassColoredName(unit), DebugGetHasFilterColor(result), tostring(result))
	end
	
	return result
end

-- randomly fires twice sometimes? ..blah
function addon:UNIT_SPELLCAST_SUCCEEDED(event, unit, spellname, _, _, spellid)
	if not self.isFightingBoss then
        if IsSpecActivation(unit, spellid) or IsTalentChange(unit, spellid) or IsGlyphChange(unit, spellid) then
            InspectUnitAfterDelay(unit)
        elseif self:InspectNeedsRetry(unit) then
            self:FUNCTION("UNIT_SPELLCAST_SUCCEEDED(%s): needs retry so: trying |cffFF00FFinspect|r again..", UnitClassColoredName(unit))
            self:Inspect(unit, true)
        end
	end
    
    UnitCastSpell(unit, spellid, spellname)
end

-- ------------------------------------------------------------------
-- ZONE_CHANGED_NEW_AREA
--[[
 need to keep track of when the player releases into ghost form (and subsequently zones out)
 and then runs back into the instance (ie, zoning in) and recovering his/her body
--]]
-- ------------------------------------------------------------------
local NUM_MAX_GROUPS = consts.NUM_MAX_GROUPS
local NUM_PLAYERS_PER_GROUP = consts.NUM_PLAYERS_PER_GROUP

function addon:SetPlayerZone()
	self:FUNCTION(":SetPlayerZone()")
	
	local playerZone = GetRealZoneText()
	
	if playerZone then
		self.playerZone = playerZone
	
		-- flag people who are out of range that we need to inspect
		local NUM_GROUP_MEMBERS = GetNumGroupMembers()
		for i = 1, NUM_GROUP_MEMBERS do
			local name, _, _, _, _, _, zone = GetRaidRosterInfo(i)
			if UnitNeedsInspect(name) and playerZone ~= zone then
				-- this person needs to be inspected when/if they come into range
				-- so, throw them into the inspect system and let it handle that junk
				self:Inspect(name)
			end
		end
	else
		local msg = ":SetPlayerZone() - failed to retreive player zone"
		self:DEBUG(msg)
	end
end

function addon:ValidateBenchGroup()
	-- set the first subgroup number that is considered to be benched
	-- ie, anyone in any subgroup >= bench is not someone whose cooldowns we care about
	local instanceGroupSize = select(9, GetInstanceInfo()) or 0
	local benchGroup = ceil(instanceGroupSize / NUM_PLAYERS_PER_GROUP)
	benchGroup = (benchGroup == 0) and NUM_MAX_GROUPS + 1 or benchGroup + 1
	if benchGroup ~= self.benchGroup then
		-- benched group changed
		self.benchGroup = benchGroup
		GroupCache:SetState()
		
		self:FUNCTION(":ValidateBenchGroup(%s): new bench group=%d", tostring(instanceGroupSize), benchGroup)
	end
end

local playerDied -- flag player death
local playerReleasedTime -- cache time player released
-- spending too much time outside the instance may void our tracking state
-- technically, any time the client spends outside of event range is too much time
-- but, forcing a full re-inspect of all group members every time the player releases is probably too often
local GHOST_FORM_TOO_LONG = 10
local function PlayerReleased()
	return playerDied
end

-- in case the player releases and goes afk
local function PlayerInGhostFormTooLong()
	local elapsed = playerReleasedTime and (GetTime() - playerReleasedTime) or 0
	return elapsed >= GHOST_FORM_TOO_LONG
end

local function PlayerGhostFormUpkeep()
	local isDead = UnitIsDeadOrGhost("player")
	local msg = "PlayerGhostFormUpkeep(): |cff00FF00releaseTime|r=%s, isDeadOrGhost? %s"
	addon:FUNCTION(msg, tostring(playerReleasedTime), tostring(isDead))
	if PlayerReleased() and not isDead then
		-- player zoned in as a ghost (recovered body) or was resurrrected
		playerDied = nil
		
		addon:UnregisterEvent("PLAYER_ALIVE")
		addon:UnregisterEvent("PLAYER_UNGHOST")
		
		-- restart processing the inspect queue 
		addon:ProcessInspects()
	end
end

function addon:ZONE_CHANGED_NEW_AREA(event)
	self:FUNCTION(event)
	
	DisengageBoss() -- in case the player zones out while in combat with a boss
	if IsInGroup() then
		self:ValidateBenchGroup()
		PlayerGhostFormUpkeep()
		
		if not PlayerReleased() then
			-- player (should be) alive, set his/her zone
			self:SetPlayerZone() -- TODO: I think this will flag people who are in ghost form outside the instance running back in
			
			-- ensure we're in an instance
			-- non-instance ZONE_CHANGED events should indicate that the player is moving around world zones which have no impact on our state
			local maxPlayers = select(5, GetInstanceInfo())
			if maxPlayers > 0 then
                self:ScanGroup()
            end
            if PlayerInGhostFormTooLong() then
				-- this is kind of shitty, but we need to make sure that our tracked state is ok
                -- there is a possibility that someone changed their spec/talents/glyphs while the client was in ghost form (ie, out of range)
                -- which potentially invalidates whatever the Cooldown state is - the problem is there is no telling who, if anyone, changed something
				self:PRINT("%s: |cffFF00FFreinspecting|r entire group..", event)
                local NUM_GROUP_MEMBERS = GetNumGroupMembers()
                for i = 1, NUM_GROUP_MEMBERS do
                    local name = GetRaidRosterInfo(i)
                    if name and UnitNeedsInspect(name) then
                        self:Inspect(name)
                    end
                end
			end
			playerReleasedTime = nil -- player zoned in alive, we no longer need to keep the time s/he released
		elseif not playerReleasedTime then
			-- player released into ghost form
			playerReleasedTime = GetTime()
		end
	end
end

function addon:PLAYER_ALIVE(event)
	self:FUNCTION(event)
	PlayerGhostFormUpkeep()
end

function addon:PLAYER_UNGHOST(event)
	self:FUNCTION(event)
	PlayerGhostFormUpkeep()
end

function addon:PLAYER_DEAD(event)
	self:FUNCTION(event)
	
	playerDied = true
	self:RegisterEvent("PLAYER_ALIVE") -- this seems to be attached to zoning..
	self:RegisterEvent("PLAYER_UNGHOST") -- need in case player is resurrected w/o zoning
end

-- ------------------------------------------------------------------
-- INSTANCE_GROUP_SIZE_CHANGED
-- ------------------------------------------------------------------
function addon:INSTANCE_GROUP_SIZE_CHANGED(event)
    self:FUNCTION(event)

    local instanceGroupSize = select(9, GetInstanceInfo()) or 0
    -- TODO: is there a lower bound for brez purposes? .. instanceGroupSize = min(10, instanceGroupSize)
    if addon.instanceGroupSize ~= instanceGroupSize then
        -- cache the new instance group size for brez charge timing
        addon.instanceGroupSize = instanceGroupSize
        -- TODO: does the brez timer update mid-fight?
        --   if so, update the brez charge timer immediately if EncounterInProgress
    end
end

-- ------------------------------------------------------------------
-- UNIT_PORTRAIT_UPDATE
-- fires on 3d portrait changes (item changes, shapeshift, comes into range, ghost form->alive)
-- ..fires when someone un/sheathes weapons?
-- ..for pet summons? (seems to fire a lot for hunters)
-- ------------------------------------------------------------------
local function UnitPortraitChange(unit)
	if addon:InspectNeedsRetry(unit) then
		addon:FUNCTION("UnitPortraitChange(%s): needs retry so: trying |cffFF00FFinspect|r again..", UnitClassColoredName(unit))
		addon:Inspect(unit, true)
	end
	local guid = UnitGUID(unit)
	if guid and guid:len() > 0 then
		GroupCache:SetState(guid)
		-- try to blindly set the pet
		-- I don't think UNIT_PET fires if we /reload in range of a pet owning class
		-- whereas UNIT_PORTRAIT_UPDATE will fire (it seems to fire randomly though as well - for hunters in particular)
		GroupCache:SetPet(guid)
	end
end

function addon:UNIT_PORTRAIT_UPDATE(event, unit)
	if not self.isFightingBoss then
		if type(event) == "table" and not unit then
			-- bucketed event
			local units = event
			local processedUnits = ""
			for u, occurances in next, units do
				-- bucket events actually catch nil and store them as string keys..
				if u and u ~= "nil" then
					UnitPortraitChange(u)
					-- logging
					local name = ("%s(%d)"):format(UnitClassColoredName(u), occurances)
					processedUnits = processedUnits:len() > 0 and ("%s, %s"):format(name, processedUnits) or name
				end
			end
			self:FUNCTION("UNIT_PORTRAIT_UPDATE: %s", processedUnits)
		else
			-- regular wow event
			self:FUNCTION("%s: %s", event, UnitClassColoredName(unit))
			UnitPortraitChange(unit)
		end
	end
end

-- ------------------------------------------------------------------
-- UNIT_PET
-- seems to fire twice per actual event (eg, pet despawn -> 2x UNIT_PET; pet summoned -> 2x UNIT_PET)
-- ..fires for every pet when hunters call their zoo?
-- ------------------------------------------------------------------
local function TrackUnitPet(unit)
	if UnitHasFilter(unit, optionalKeys.PET) then
		local guid = UnitGUID(unit)
		
		if guid and guid:len() > 0 then
			GroupCache:SetPet(guid)
			addon:TrackCooldownsFor(guid)
		else
			local msg = "TrackUnitPet(%s) - could not retreive 'guid' from '%s'"
			addon:DEBUG(msg, UnitClassColoredName(unit), tostring(unit))
		end
	end
end

function addon:UNIT_PET(event, unit)
	if type(event) == "table" and not unit then
		-- bucket event
		local units = event
		local processedUnits = ""
		
		for u, occurances in next, units do
			TrackUnitPet(u)
			
			-- logging
			local name = ("%s(%d)"):format(UnitClassColoredName(u), tonumber(occurances) or 0) -- not sure how occurances is ever nil..
			processedUnits = processedUnits:len() > 0 and ("%s, %s"):format(name, processedUnits) or name
		end
		
		-- buckets don't seem to help with UNIT_PET spam..
		--self:FUNCTION("UNIT_PET: %s", processedUnits)
	else
		-- single event
		--self:FUNCTION("%s: %s", tostring(event), UnitClassColoredName(unit))
		TrackUnitPet(unit)
	end
end

-- ------------------------------------------------------------------
-- UNIT_CONNECTION
-- ------------------------------------------------------------------
function addon:UNIT_CONNECTION(event, unit)
	self:FUNCTION("%s(%s)", event, UnitClassColoredName(unit))
	
	if not self.isFightingBoss and UnitIsConnected(unit) then
		-- try rebooting the out-of-combat res scanner
		-- in case someone disconnects while dead (I don't think GetNumGroupMembers counts offline group members)
		self:StartOoCResScan()
	end

	local guid = UnitGUID(unit)
	if guid and guid:len() > 0 then
		GroupCache:SetState(guid)
	else
		local msg = "%s(%s) - could not retreive 'guid' from '%s'"
		self:DEBUG(msg, tostring(event), UnitClassColoredName(unit), tostring(unit))
	end
end

-- ------------------------------------------------------------------
-- UNIT_NAME_UPDATE
-- seems to fire constantly in lfr..
-- ------------------------------------------------------------------
local function UnitNameUpdate(unit)
	if not addon.isFightingBoss and addon:InspectNeedsRetry(unit) then
		addon:FUNCTION("UnitNameUpdate(%s): needs retry so: trying |cffFF00FFinspect|r again..", UnitClassColoredName(unit))
		addon:Inspect(unit, true)
	end
end

function addon:UNIT_NAME_UPDATE(event, unit)
	if type(event) == "table" and not unit then
		-- bucket event
		local units = event
		local processedUnits = ""
		
		for u, occurances in next, units do
			UnitNameUpdate(u)
			
			-- logging
			local name = ("%s(%d)"):format(UnitClassColoredName(u), tonumber(occurances) or 0) -- not sure how occurances is ever nil..
			processedUnits = processedUnits:len() > 0 and ("%s, %s"):format(name, processedUnits) or name
		end
		self:FUNCTION(true, "UNIT_NAME_UPDATE: %s", processedUnits)
	else
		self:FUNCTION(true, "%s(%s)", event, UnitClassColoredName(unit))
		UnitNameUpdate(unit)
	end
end
