
local select, wipe, next, time, type, tonumber, tostring, setmetatable, insert, remove, inf
	= select, wipe, next, time, type, tonumber, tostring, setmetatable, table.insert, table.remove, math.huge
local GetTime, GetNetStats, GetPlayerInfoByGUID, GetSpellInfo, UnitIsConnected, UnitIsDeadOrGhost, IsInGroup
	= GetTime, GetNetStats, GetPlayerInfoByGUID, GetSpellInfo, UnitIsConnected, UnitIsDeadOrGhost, IsInGroup

local addon = Overseer
local OverseerSavedState = OverseerSavedState

local consts = addon.consts
local append = addon.TableAppend
local GetSpellBaseCooldownSeconds = addon.GetSpellBaseCooldownSeconds
local GUIDClassColoredName = addon.GUIDClassColoredName
local GUIDClassColorStr = addon.GUIDClassColorStr

local ANKH_ID = consts.ANKH_ID
local MESSAGES = consts.MESSAGES
local MSEC_PER_SEC = consts.MSEC_PER_SEC
local SEC_PER_MIN = consts.SEC_PER_MIN

local GroupCache
local SpellCooldown

-- ------------------------------------------------------------------
-- Cooldown storage structures
-- ------------------------------------------------------------------
local deadCooldowns = {
	--[[
	pool of SpellCooldowns which are no longer in use
	these are exhausted before spawning new instances of SpellCooldown
	TODO: there's really no reason to recycle these
	
	form:
	SpellCooldown,
	SpellCooldown,
	...
	--]]
}

local SortedCooldowns = {
	--[[
	sorted lists of spells by time remaining on their cooldowns in ascending order
	essentially, a queue
	
	form:
	[spellid] = {
		spellCD, -- first on cooldown (will be the first to finish)
		spellCD, -- second
		...
		spellCD, -- most recently used (last to finish)
	},
	...
	--]]
}

local CooldownsByGUID = {
	--[[
	stores all cooldowns being tracked for the keyed guid
	
	form: 
	[guid] = { -- table of tracked spell ids for this person (the values don't matter)
		[id] = true, 
		[id] = true, 
		...
	},
	...
	--]]
}

local Cooldowns = {
	--[[
	stores all tracked cooldowns keyed by their spell ids
	
	form:
	[id] = {
		[guid] = CooldownBase, -- stores the state of the person's cooldown
		...
	},
	...
	--]]
}
addon.Cooldowns = Cooldowns
	
-- returns table of keyed spellids tracked for the specified guid
function Cooldowns:GetSpellIdsFor(guid)
	return type(guid) == "string" and guid:len() > 0 and CooldownsByGUID[guid]
end

-- returns the first spellCD instance that will become ready
function Cooldowns:GetFirstOnCD(spellid)
	return SortedCooldowns[spellid] and SortedCooldowns[spellid][1]
end

-- returns the most recently used spellCD instance
function Cooldowns:GetMostRecentCast(spellid)
	local sorted = SortedCooldowns[spellid]
	return sorted and sorted[#sorted]
end

function Cooldowns:Add(spellid, guid, cd, charges, buffDuration)
	-- key the tracked spell by the person's guid
	local spells = self:GetSpellIdsFor(guid)
	if not spells then
		spells = {} -- all spells for this guid
		CooldownsByGUID[guid] = spells
	end
	spells[spellid] = true
	
	-- track the spell for this person
	local trackedSpell = self[spellid]
	if not trackedSpell then
		trackedSpell = {} -- list of guids for this spell
		self[spellid] = trackedSpell
	end
	
	local spellCD = trackedSpell[guid]
	if not spellCD then
		-- construct the spell
		spellCD = SpellCooldown(spellid, guid, cd, charges, buffDuration)
		trackedSpell[guid] = spellCD
		
		-- broadcast that a new spell cd instance has been constructed
		addon:SendMessage(MESSAGES.CD_NEW, trackedSpell[guid])
	else
		-- modify with potentially new data
		spellCD:Modify(spellid, guid, cd, charges, buffDuration)
	end
	return spellCD
end

local function RemoveTrackedSpell(spellid, guid)
	local spellCD = Cooldowns[spellid] and Cooldowns[spellid][guid]
	if spellCD then
		-- update the reference first so that anyone responding to a :Delete message can lookup accurate information
		Cooldowns[spellid][guid] = nil
        CooldownsByGUID[guid][spellid] = nil
		
		spellCD:Delete()
		append(deadCooldowns, spellCD) -- TODO: these are just tables, not sure if recycling them is necessary or wise
	end
end

-- removes tracking for the specified guid
-- if spellid is nil, removes all spellids tracked for guid
-- if spellid is specified, removes the single tracked spellid for guid
function Cooldowns:Remove(guid, spellid)
	if spellid then
		-- remove a single spellid (eg, guid spec change)
		local spells = self:GetSpellIdsFor(guid)
		if spells then
			spells[spellid] = nil
		end
		
		RemoveTrackedSpell(spellid, guid)
	else
		-- completely remove guid (eg, guid left group)
		local spells = self:GetSpellIdsFor(guid)
		if spells then
			for spellid in next, spells do
				RemoveTrackedSpell(spellid, guid)
			end
			
			wipe(spells)
		end
	end
end
	
-- resets all resettable cooldowns (ie, cds >= 5m)
function Cooldowns:ResetCooldowns()
	for spellid, spells in next, self do
		if type(spells) == "table" then -- skip these functions
			for guid, cd in next, spells do
				cd:Reset()
			end
		end
	end
end

function Cooldowns:Initialize()
	SpellCooldown:Initialize()
	addon:LoadSavedState()
end
	
-- clears all tracking information
function Cooldowns:Wipe()
	-- doing wipe(Cooldowns) will destroy all these functions
	-- so, let's avoid that
	
	-- exhaust all spellids for all guids we have stored and manually clean up
	for guid in next, CooldownsByGUID do
		self:Remove(guid)
	end
	
	-- clear our other state tables
	wipe(CooldownsByGUID)
	wipe(SortedCooldowns)
	
	SpellCooldown:Shutdown()
end
-- ------------------------------------------------------------------
-- Debug
-- ------------------------------------------------------------------
do -- debug (do block for folding)
	local UnitGUID = UnitGUID
	local indent = consts.INDENT
	local empty = consts.EMPTY

	function Cooldowns:Debug(guid)
		local printNumTracked = true
		if type(guid) == "string" then
			-- list the state of all tracked cds for this guid
			local input = guid
			local guidSpells = CooldownsByGUID[guid]
			if not guidSpells then
				guid = UnitGUID(guid) -- allow the user to specify a unitId
				guidSpells = CooldownsByGUID[guid]
			end
			
			if guidSpells then
				local printedSomething
				local classColor = GUIDClassColorStr(guid)
				addon:Print(("Cooldowns [%s]:"):format(GUIDClassColoredName(guid)), true)
				addon:Print(("Now: %s"):format(GetTime()), true)
				for spellid in next, guidSpells do
					local cd = self[spellid][guid]
					if cd then
						addon:Print(("%s|c%s%s|r(%s) ->"):format(indent, classColor, GetSpellInfo(spellid), tostring(spellid)), true)
						addon:Print(("%sready = %d"):format(indent:rep(2), cd:NumReady()), true)
						addon:Print(("%scharges = %d"):format(indent:rep(2), cd:NumCharges()), true)
						local t = cd:TimeLeft()
						addon:Print(("%sexpiration = %d (remaining = %dmin %dsec)"):format(
							indent:rep(2), cd:ExpirationTime(), t / SEC_PER_MIN, t % SEC_PER_MIN), true)
						printedSomething = true
					end
				end
				
				if not printedSomething then
					-- this should never happen
					addon:Print(("%s%s"):format(indent, empty), true)
				end
				printNumTracked = false
			else
				-- either we're not tracking anything for this person or the user passed bad input
				addon:Print(("%sCould not retreive any tracked spells for '%s'. Is it a proper guid or unitId?"):format(indent, tostring(input)), true)
				--printNumTracked = true
			end
		end
		
		if printNumTracked then
			-- list number of cds for all guids we are tracking
			local printedSomething
			addon:Print("#Cooldowns Per Person: ====", true)
			for guid, spells in next, CooldownsByGUID do
				local numSpells = 0
				-- iterate through all the spells and count how many there are..
				-- kind of shitty, but it's a manually called function -> worst case, ~400 iterations
				for _ in next, spells do
					numSpells = numSpells + 1
				end
				addon:Print(("%s%s: %d"):format(indent, GUIDClassColoredName(guid), numSpells), true)
				printedSomething = true
			end
			
			if not printedSomething then
				addon:Print(("%s%s"):format(indent, empty), true)
			end
		end
	end

	function addon:DebugCooldowns(guid) Cooldowns:Debug(guid) end
end

-- ------------------------------------------------------------------
-- Spell cooldown class
-- ------------------------------------------------------------------
local READY = 0
SpellCooldown = {} -- local, fwd declared at the top
SpellCooldown.READY = READY
SpellCooldown.__index = SpellCooldown
SpellCooldown.__tostring = function(spellCD)
	local result = "<|cff999999dead spellCD|r>"
	if spellCD.guid and spellCD.spellid then
		local name = GUIDClassColoredName(spellCD.guid)
		local classColorStr = GUIDClassColorStr(spellCD.guid)
		local spellname = GetSpellInfo(spellCD.spellid)
		result = ("%s's |c%s%s|r"):format(name, classColorStr, spellname)
	end
	return result
end

local buffUseTimes = {
	--[[
	spells whose buff durations are currently ticking down.
	
	this system is used instead of AceTimer because GetTime is a cached value,
	which can lead to slight differences depending on when :ScheduleTimer is called 
	relative to the difference between GetTime's cached value and the actual time.
	essentially, anything happening in an AceTimer's OnFinish callback will be +/- some
	offset relative to the next GetTime update.
	thus, any time-sensitive functionality depending on GetTime cannot reliably use AceTimers.
	
	(the old system was calling :ScheduleTimer on :Use, however displays handling the CD_BUFF_EXPIRE
	message were either too fast or too slow by an epsilon amount - too slow being the preferred case.
	this would cause texts to not update with correct information.. sometimes.
	the largest epsilon I observed was 0.1, but I'm pretty sure that is based on cpu/framerate which can
	fluctuate widly between systems and even within a single system.)
	
	form:
	[spellCD] = true,
	...
	--]]
}

local onCooldown = {
	--[[
	spells on cooldowns (for updating)
	
	form:
	[spellCD] = true,
	[spellCD] = true,
	...
	--]]
}
local StartCooldown, StartUpdateTimer, StopUpdateTimer
local updateTimer
local latencyTimer
local LATENCY_UPDATE_INTERVAL = 30

local function CacheLatency(self)
	self.latency = (select(4, GetNetStats()) or 0) / MSEC_PER_SEC -- world latency in seconds
end

function SpellCooldown:Initialize()
	addon:PrintFunction("SpellCooldown:Initialize()")
	if not latencyTimer then
		addon:PrintFunction(">> starting |cff999999latency cache|r timer")
		-- cache immediately
		CacheLatency(self)
		-- cache the client's world latency every time it updates
		latencyTimer = addon:ScheduleRepeatingTimer(CacheLatency, LATENCY_UPDATE_INTERVAL, self)
	end
end

function SpellCooldown:Shutdown()
	addon:PrintFunction("SpellCooldown:Shutdown()")
	if latencyTimer then
		addon:PrintFunction(">> stopping |cff999999latency cache|r timer")
		addon:CancelTimer(latencyTimer)
	end
	StopUpdateTimer()
end

local function KillCooldown(spell)
	if spell.start and spell.start ~= READY then
		spell.start = READY
		spell.expire = READY
		onCooldown[spell] = nil
		
		-- update the sorted list of cooldowns
		local idx
		local sorted = SortedCooldowns[spell.spellid]
		for i = 1, #sorted do
			local spellCD = sorted[i]
			if spell == spellCD then
				idx = i
				break
			end
		end
		if idx then
			-- in most cases, this should remove the first element
			remove(sorted, idx)
		end
	end
end

local function OnFinish(spell)
	KillCooldown(spell)
	spell.chargesOnCD = spell.chargesOnCD - 1
	if spell.chargesOnCD > 0 then
		-- there are still more charges on cooldown, boot up another timer
		StartCooldown(spell)
	elseif spell.chargesOnCD == 0 then
		-- saved info no longer applicable, discard it
		addon:WipeSavedCooldownState(spell.guid, spell.spellid)
	elseif spell.chargesOnCD < 0 then
		-- this may mean we somehow used too many charges (from what? lag?)
		-- thus firing too many 'OnFinished' callbacks
		local msg = "OnFinish(): attempted to finish cd of %s(%s), but all charges were ready"
		addon:Debug(msg:format(tostring(spell), tostring(spell.spellid)))
	end
	
	addon:PrintCD(("%s(%s) is ready!"):format(tostring(spell), tostring(spell.spellid)))
	addon:SendMessage(MESSAGES.CD_READY, spell)
end

local function BuffExpired(spell)
	-- don't bother firing this if the person lost the cd (either left group or lost requirement)
	if spell.guid and spell.spellid then
		addon:PrintCD(("BuffExpired(%s): |c%s%s|r(%s)"):format(GUIDClassColoredName(spell.guid), GUIDClassColorStr(spell.guid), tostring(GetSpellInfo(spell.spellid)), tostring(spell.spellid)))
		addon:SendMessage(MESSAGES.CD_BUFF_EXPIRE, spell)
		remove(spell.uses, 1) -- remove the cached use time after the broadcast in case anyone needs that information
		
		if #spell.uses == 0 then buffUseTimes[spell] = nil end -- note: it IS ok to remove table keys while iterating through the table in lua
	end
end

local function OnUpdate()
	local now = GetTime()
	
	-- update buff durations
	for spellCD in next, buffUseTimes do
		if spellCD:BuffExpirationTime() < now then
			BuffExpired(spellCD)
		end
	end
	
	-- update cooldown durations
	for spellCD in next, onCooldown do
		if spellCD:ExpirationTime() < now then
			OnFinish(spellCD)
		end
	end
	
	-- check if we still need to do update ticks
	if not (next(onCooldown) or next(buffUseTimes)) then
		StopUpdateTimer()
	end
end

local COOLDOWN_UPDATE_INTERVAL = 0.125 -- 8 fps
--[[local]] function StartUpdateTimer()
	if not updateTimer then
		addon:PrintFunction(">> starting |cff999999CD update|r timer", true)
		-- TODO? switch to an OnUpdate script to ensure GetTime has changed?
		updateTimer = addon:ScheduleRepeatingTimer(OnUpdate, COOLDOWN_UPDATE_INTERVAL)
	end
end

--[[local]] function StopUpdateTimer()
	if updateTimer then
		addon:PrintFunction(">> stopping |cff999999CD update|r timer", true)
		addon:CancelTimer(updateTimer)
		updateTimer = nil
	end
end

function SpellCooldown:New(spellid, guid, cd, charges, buffDuration)
	local instance = remove(deadCooldowns) or setmetatable({}, self)
	instance.duration = cd or GetSpellBaseCooldownSeconds(spellid) -- duration of the cooldown
	instance.guid = guid -- the guid to which this cooldown belongs
	instance.spellid = spellid -- the spellid this cooldown represents
	-- note: this buff tracking system is extremely rudimentary
	-- it does not take haste into consideration and only tracks based on use (ie, SPELL_CAST_SUCCESS)
	-- eg, hymn of hope duration will almost always be wrong (due to haste)
	--     tricks of the trade buff will be wrong (buff duration not based on use - nor cd for that matter)
	--	   life cocoon will be wrong as well (buff fades = no more duration)
	instance.buffDuration = buffDuration -- the duration of the buff provided by spellid when used
	instance.uses = instance.uses or {} -- use times from earliest -> most recent (for buff duration tracking)
	instance.charges = charges or 1 -- total number of charges (default to single charge - ie, a normal spell cooldown)
	instance.chargesOnCD = 0 -- number of charges currently on cooldown, cannot exceed 'instance.charges' (0 means all charges are ready)
	instance.start = READY -- current cooldown start time
	instance.expire = READY
	
	--[[
		as of 5.4, charges work as follows:
			Spell X has 3 charges. Its cooldown is 30s.
			X is used at time t0. X goes on cooldown for 30s. It now has 1 charge on cooldown and 2 remaining.
			At t0+15s, X is used again. It loses one charge (2 charges on cooldown, 1 remaining).
			At t0+30s, X's cooldown finishes and it gains 1 active charge (1 charge on cooldown, 2 remaining).
			Its cooldown starts anew and will finish at t0+60s.
			At t0+60s, X regains all charges (3 charges remaining).
			
			So, regardless of when a charge is used, the cooldown duration remains the same and starts
			when the current cooldown timer finishes - NOT when the charge itself is used.
			That is, the time at which a charge is used has no effect on the cooldown duration.
	--]]
	
	-- note: cannot broadcast _NEW message just yet.. needs to be done up a level in Cooldowns (so that others can access data on it)
	addon:PrintCD((":New(%s): +|c%s%s|r(%s)"):format(GUIDClassColoredName(guid), GUIDClassColorStr(guid), tostring(GetSpellInfo(spellid)), tostring(spellid)))
	return instance
end

function SpellCooldown:Delete()
	addon:PrintCD((":Delete(%s): -|c%s%s|r(%s)"):format(GUIDClassColoredName(self.guid), GUIDClassColorStr(self.guid), tostring(GetSpellInfo(self.spellid)), tostring(self.spellid)))
	addon:SendMessage(MESSAGES.CD_DELETE, self)
	
	wipe(self.uses)
	buffUseTimes[self] = nil
	
	KillCooldown(self)
	self.duration = nil
	self.guid = nil
	self.spellid = nil
	self.buffDuration = nil
	self.chargesOnCD = nil
	self.charges = nil
end
	
local function NeedToModify(old, spellid, guid, cd, charges, buffDuration)
	return old.spellid ~= spellid -- can this happen?
		or old.guid ~= guid -- can this happen?
		or old.duration ~= cd
		or old.buffDuration ~= buffDuration -- don't use the getter: READY ~= nil
		or old.charges ~= charges
end
	
function SpellCooldown:Modify(spellid, guid, cd, charges, buffDuration)
	cd = cd or GetSpellBaseCooldownSeconds(spellid)
	charges = charges or 1
	if not NeedToModify(self, spellid, guid, cd, charges, buffDuration) then
		return
	end
	
	self.duration = cd
	self.guid = guid
	self.spellid = spellid
	self.buffDuration = buffDuration
	self.charges = charges
	
	if self.chargesOnCD > charges then
		-- the spell lost charges while it was on cd somehow
		-- ensure consistent state (ie, don't let .chargesOnCD become negative)
		-- though, I don't think this can happen
		self.chargesOnCD = charges
	end
	
	local name = GUIDClassColoredName(guid)
	local classColorStr = GUIDClassColorStr(guid)
	local spellname = tostring(GetSpellInfo(spellid))
	if self.start ~= READY then
		local t = self:TimeLeft()
		local msg = "SpellCooldown:Modify(%s): |c%s%s|r(%s) was modified while still on cooldown!! (%dm %.1fs left)"
		addon:Debug(msg:format(name, classColorStr, spellname, tostring(spellid), t / SEC_PER_MIN, t % SEC_PER_MIN))
		-- don't modify the cooldown if one is ticking down
	end
	
	addon:PrintCD((":Modify(%s): |c%s%s|r(%s)"):format(name, classColorStr, spellname, tostring(spellid)))
	addon:SendMessage(MESSAGES.CD_MODIFIED, self)
end

local function GetCastTime(offset)
	-- shorten the cd duration by the client's latency
	-- subtract because the client received the event from the server which should have taken roughly 'latency' amount of time
	-- so, in theory, the spell was actually casted in the past 'latency' seconds ago
	-- ..maybe it's (latency / 2) seconds?
	return GetTime() - (SpellCooldown.latency or 0) - (offset or 0)
end

--[[local]] function StartCooldown(spell, offset)
	if spell.start == READY then -- only a single cooldown can be ticking down at a time per spell per person
		spell.start = GetCastTime(offset)
		spell.expire = spell.start + spell.duration -- explicitly store the expiration time in case the duration changes
		onCooldown[spell] = true
		StartUpdateTimer()
		
		-- update the sorted cooldowns list
		local spellid = spell.spellid
		SortedCooldowns[spellid] = SortedCooldowns[spellid] or {}
		append(SortedCooldowns[spellid], spell)
	end
	
	-- update the saved cooldown info
	if not offset then
		addon:SaveCooldownState(spell, time())
	end
end

local function Use(spell, offset)
	-- inform the people when the buff expires (if any)
	local buffDuration = spell:BuffDuration()
	if buffDuration ~= READY then
		-- check if this Use is loading from a previous session
		-- if so, don't bother with this if the buff duration has already expired
		local useTime = GetCastTime(offset)
		if GetCastTime() - useTime < buffDuration then
			addon:Debug(("%s buff should expire in %d seconds.."):format(tostring(spell), buffDuration))
			append(spell.uses, useTime)
			buffUseTimes[spell] = true -- flag for updates
		end
	end

	StartCooldown(spell, offset)
	addon:PrintCD((":Use(%s): |c%s%s|r(%s)"):format(GUIDClassColoredName(spell.guid), GUIDClassColorStr(spell.guid), tostring(GetSpellInfo(spell.spellid)), tostring(spell.spellid)))
	addon:SendMessage(MESSAGES.CD_USE, spell)
end

local EPSILON = 0.1 -- 100 ms
-- the parameters are for loading from file
function SpellCooldown:Use(offset, chargesOnCD)
	local timeSinceLastCast = GetCastTime() - self.start
	if timeSinceLastCast < EPSILON then -- TODO? change to an even smaller value?
		-- outside of abilities off gcd, this should be an error
		-- the only valid situation this can happen is a spell off gcd with charges used multiple times within this timeframe.. highly unlikely
		-- this seems to happen when UNIT_SPELLCAST_SUCCEEDED fires randomly twice for the same spellcast
		-- TODO: why does this happen?
		local msg = "> %s was used within %.6f seconds of itself.. Surely an |cffFF0000error|r, right?" -- TODO: I think this will always be 0 since GetTime is cached..
		addon:Debug(msg:format(tostring(self), timeSinceLastCast))
		return
	end

	-- this block is mostly to catch potential bugs or possibly improper :Use() calls
	if IsInGroup() and self.spellid ~= ANKH_ID then
		if not GroupCache then
			GroupCache = addon.GroupCache
		end
		
		local dead = GroupCache:IsDead(self.guid)
		local offline = GroupCache:IsOffline(self.guid)
		local benched = GroupCache:IsBenched(self.guid)
		if dead or offline or benched then
			-- group cache holds incorrect state information
			local state = ""
			local name = GUIDClassColoredName(self.guid)
			local msg = "SpellCooldown:Use(): |cffFF0000%s|r - %s casted |c%s%s|r(%s).. issuing :SetState(%s) to fix."
			if dead then state = "DEAD" end
			if offline then state = state:len() > 0 and ("%s,OFFLINE"):format(state) or "OFFLINE" end
			if benched then state = state:len() > 0 and ("%s,BENCHED"):format(state) or "BENCHED" end
			addon:Debug(msg:format(state, name, GUIDClassColorStr(self.guid), tostring(GetSpellInfo(self.spellid)), tostring(self.spellid), name))
			-- failsafe for improper group cache state
			-- ideally, the state would be set as the relevant events happen rather than waiting for a spellcast to do so..
			GroupCache:SetState(self.guid)
		end
	end
	
	if self:NumReady() > 0 then
		-- adjust the active charge counter
		self.chargesOnCD = chargesOnCD or (self.chargesOnCD + 1)
		Use(self, offset)
	elseif self:TimeLeft() <= self.latency + EPSILON then
		-- the spell was used with all charges on cooldown but within the client's latency window
		-- ie, someone casted this spell but our state says it is still unusable
		local t = self:TimeLeft()
		local msg = ":Use(%s): |c%s%s|r(%s) was casted with none ready (first charge ready in %0.4fs)"
		addon:PrintCD(msg:format(GUIDClassColoredName(self.guid), GUIDClassColorStr(self.guid), tostring(GetSpellInfo(self.spellid)), tostring(self.spellid), t))
		
		KillCooldown(self)
		addon:SendMessage(MESSAGES.CD_READY, self) -- this skips the normal _READY flow, so force a _READY broadcast
		Use(self)
	end
end

local DOES_NOT_RESET = { -- list of spellids that do not reset
	[ANKH_ID] = true,
	-- is ankh the only spell that doesn't reset?
}
local DOES_RESET = {
	-- list of spellids which reset even though their cd is less than the minimum time
	-- ..I wish there was better documentation on how this system works or that it even exists in the first place
	[123904] = true, -- xuen
}
local MIN_DURATION_FOR_RESET = 5 * 60 -- minumum cooldown duration in seconds for a cooldown to reset (on encounter end)
function SpellCooldown:Reset()
	if DOES_NOT_RESET[self.spellid] then return end

	if self.duration >= MIN_DURATION_FOR_RESET or DOES_RESET[self.spellid] then
		KillCooldown(self)
		self.chargesOnCD = 0
		addon:WipeSavedCooldownState(self.guid, self.spellid)
		
		addon:PrintCD((":Reset(%s): |c%s%s|r(%s)"):format(GUIDClassColoredName(self.guid), GUIDClassColorStr(self.guid), tostring(GetSpellInfo(self.spellid)), tostring(self.spellid)))
		addon:SendMessage(MESSAGES.CD_RESET, self)
	end
end

function SpellCooldown:BuffExpirationTime()
	local buffExpire = READY
	local useTime = self.uses[1]
	if useTime and self.buffDuration then
		buffExpire = useTime + self.buffDuration
	end
	return buffExpire
end

function SpellCooldown:BuffDuration()
	return self.buffDuration or READY
end
	
function SpellCooldown:NumReady()
	return self:NumCharges() - self.chargesOnCD
end

function SpellCooldown:NumCharges()
	return self.charges
end

-- returns the time at which the cooldown began or SpellCooldown.READY if not on cooldown
function SpellCooldown:StartTime()
	return self.start
end

-- returns the time at which the cooldown will expire or SpellCooldown.READY if not on cooldown
function SpellCooldown:ExpirationTime()
	return self.expire
end

-- returns the timeleft on the cooldown or SpellCooldown.READY if not on cooldown
function SpellCooldown:TimeLeft()
	return self.start == READY and READY or self:ExpirationTime() - GetTime()
end

-- allow SpellCooldown() constructor notation
setmetatable(SpellCooldown, { __call = SpellCooldown.New })
