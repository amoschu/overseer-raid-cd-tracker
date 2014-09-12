
local wipe, next, type, tostring, time, floor
	= wipe, next, type, tostring, time, math.floor
local GetSpellInfo, UnitInParty, UnitInRaid, UnitIsUnit
	= GetSpellInfo, UnitInParty, UnitInRaid, UnitIsUnit
	
local addon = Overseer

local consts = addon.consts
local GetUnitFromGUID = addon.GetUnitFromGUID
local GUIDClassColoredName = addon.GUIDClassColoredName
local Cooldowns -- addon.Cooldowns (which has not been instantiated yet)

local INDENT = consts.INDENT
local CD_DURATION = "CD_DURATION"
local CHARGES = "CHARGES"
local BUFF_DURATION = "BUFF_DURATION"
local CHARGES_ON_CD = "CHARGES_ON_CD"
local START_TIME = "START_TIME"

-- ------------------------------------------------------------------
-- Instantiation
-- ------------------------------------------------------------------
--[[
OverseerSavedState = {
	core saved state: at the moment, just cooldown information
	cannot save guid state/talent/glyph info in case the person has changed anything in the interim
	
	form:
	[guid] = {
		[spellid] = {
			[CD_DURATION] = duration of spell's cooldown,
			[CHARGES] = number of charges,
			[CHARGES_ON_CD] = charges on cooldown,
			[BUFF_DURATION] = buff duration if any,
			[START_TIME] = start time from time(),
		},
		...
	},
	...
}
--]]
local SavedState

local function SavedDataIsOld(now, chargesOnCD, start, cd)
	return chargesOnCD == 0 -- somehow an ability with 0 charges on cooldown was saved.. (shouldn't happen)
		or now - start > chargesOnCD * cd -- all charges' cds have expired since the SavedState was updated last
end

local function PruneSavedState()
	SavedState = SavedState or OverseerSavedState
	if SavedState then
		local now = time()
		for guid, spells in next, SavedState do
			for spellid, cdInfo in next, spells do
				local cd = cdInfo[CD_DURATION]
				local start = cdInfo[START_TIME]
				local chargesOnCD = cdInfo[CHARGES_ON_CD]
				
				-- prune individual cd data if the table is empty or if the data is old
				if not next(cdInfo) or SavedDataIsOld(now, chargesOnCD, start, cd) then
					spells[spellid] = nil
				end
			end
			
			-- prune an entire person's saved state if there is no more data for him/her
			if not next(spells) then
				SavedState[guid] = nil
			end
		end
	end
end

function addon:PLAYER_LOGOUT(event)
	PruneSavedState()
end

-- ------------------------------------------------------------------
-- Debugging
-- ------------------------------------------------------------------
local IsGUIDPlayer
local function SpitSavedState(t, depth)
	IsGUIDPlayer = IsGUIDPlayer or addon.IsGUIDPlayer

	depth = depth or 1
	local indent = INDENT:rep(depth)
	for k,v in next, t do
		if type(v) == "table" then
			local key = IsGUIDPlayer(k) and GUIDClassColoredName(k) or (GetSpellInfo(k) or k)
			addon:PRINT(true, "%s|cffFF00FF>|r%s:", indent, tostring(key))
			SpitSavedState(v, depth + 1)
		else
			addon:PRINT(true, "%s%s=%s", indent, tostring(k), tostring(v))
		end
	end
end

function addon:DebugSavedState()
	SavedState = SavedState or OverseerSavedState
	if SavedState then
		self:PRINT(true, "OverseerSavedState =======")
		SpitSavedState(SavedState)
	end
end

-- ------------------------------------------------------------------
-- Load saved state
-- ------------------------------------------------------------------
local lastGUID -- 'next' state
local lastSpellid
local function Load(self, elapsed)
	-- load one cooldown per update tick to ensure GetTime has been updated
	-- otherwise, cooldown information will lag behind if trying to load within a single update (sometimes on the order of seconds)
	local guid, spells = next(SavedState, lastGUID)
	if guid and spells then
		local spellid, cdInfo = next(spells, lastSpellid)
		if spellid and cdInfo then
			local cd = cdInfo[CD_DURATION]
			local charges = cdInfo[CHARGES]
			local buffDuration = cdInfo[BUFF_DURATION]
			local chargesOnCD = cdInfo[CHARGES_ON_CD]
			local start = cdInfo[START_TIME]
					
			addon:PRINT("%s%s->'%s' (cd=%s, charges=%s, buff=%s, chargesOnCD=%s, start=%s)", INDENT, GUIDClassColoredName(guid), GetSpellInfo(spellid), cd, charges, tostring(buffDuration), chargesOnCD, start)
			
			local elapsed = time() - start
			-- check if any charges finished their cooldowns between sessions
			if elapsed >= cd then
				-- figure out how many charges finished
				chargesOnCD = chargesOnCD - floor(elapsed / cd)
				elapsed = elapsed % cd
			end
			
			--[[
				TODO: the elapsed time between actual cd and perceived cd widens(?) as the cooldown duration becomes smaller..
					I think this has to do with GetTime caching (if :Enable happens within the same update tick as Initialize, GetTime's lag may be on the order of seconds)
					..except longer cooldowns never seem to run into this issue
					-> I've observed cooldowns being _ahead_ of the actual cooldown duration, meaning the elapsed period between client time() and server time() differs?
			--]]
			if chargesOnCD > 0 then
				-- there are still some charges on cooldown
				local unit = GetUnitFromGUID(guid)
				if unit and (UnitInRaid(unit) or UnitInParty(unit) or UnitIsUnit(unit, "player")) then
					-- only add if the cooldown is applicable
					local spellCD = Cooldowns:Add(spellid, guid, cd, charges, buffDuration)
					addon:COOLDOWN("(%s):Use() elapsed=%s, chargesOnCD=%s", tostring(spellCD), elapsed, chargesOnCD)
					spellCD:Use(elapsed, chargesOnCD)
				end
			else
				-- all charges finished since the previous session
				addon:WipeSavedCooldownState(guid, spellid)
			end
			
			-- finished loading this cooldown, cache the key so that 'next' can retreive the next cd to process
			lastSpellid = spellid
		else
			-- done loading this guid, move onto the next
			lastGUID = guid
			-- clear whatever the 'next' state was
			-- if this is left untouched for the next iteration, 'next' will potentially throw an 'invalid key' error
			-- since the next spells table may not contain such a key
			lastSpellid = nil
		end
	else
		-- load process finished, kill the onUpdate
		self:SetScript("OnUpdate", nil)
		self:Hide()
		-- reset 'next' state
		lastSpellid = nil
		lastGUID = nil
	end
end

function addon:LoadSavedState()
	self:FUNCTION(":LoadSavedState()")
	
	SavedState = OverseerSavedState
	if SavedState then
		Cooldowns = self.Cooldowns
		if Cooldowns then
			local onUpdate = self._helperFrame:GetScript("OnUpdate")
			if onUpdate ~= Load then -- TODO: this needs review if/when the frame is used for anything other than loading
				local frame = self._helperFrame
				frame:SetScript("onUpdate", Load)
				frame:Show()
			end
		else
			local msg = ":LoadSavedState(): Failed! Cooldowns structure missing!"
			self:DEBUG(msg)
		end
	end
end

-- ------------------------------------------------------------------
-- Save state information
-- ------------------------------------------------------------------
function addon:WipeSavedCooldownState(guid, spellid)
	self:FUNCTION(":WipeSavedCooldownState(%s): %s", GUIDClassColoredName(guid), GetSpellInfo(spellid))
	
	SavedState = SavedState or OverseerSavedState
	if SavedState and SavedState[guid] and SavedState[guid][spellid] then
		-- don't throw away the tables in case the spellCD is Use()d again later
		-- this should cause less memory churn, for whatever that's worth
		wipe(SavedState[guid][spellid])
	end
end

function addon:SaveCooldownState(spellCD, start)
	self:FUNCTION(":SaveCooldownState(%s): cd=%s, charges=%s, buff=%s, chargesOnCD=%s, start=%s", tostring(spellCD), spellCD.duration, spellCD.charges, tostring(spellCD.buffDuration), spellCD.chargesOnCD, tostring(start))
	
	SavedState = SavedState or OverseerSavedState
	-- save the cooldown's state in case of reloads or disconnects
	local guid = spellCD.guid
	local spellid = spellCD.spellid
	local cd = spellCD.duration
	local charges = spellCD.charges
	local buffDuration = spellCD.buffDuration
	local chargesOnCD = spellCD.chargesOnCD
	
	SavedState[guid] = SavedState[guid] or {}

	local cdInfo = SavedState[guid][spellid] or {}
	cdInfo[CD_DURATION] = cd
	cdInfo[CHARGES] = charges
	cdInfo[BUFF_DURATION] = buffDuration
	cdInfo[CHARGES_ON_CD] = chargesOnCD
	cdInfo[START_TIME] = start
	
	SavedState[guid][spellid] = cdInfo
	
	--self:DebugSavedState()
end
