
local type, select, wipe, inf
	= type, select, wipe, math.huge
local GetTime, GetInstanceInfo, GetPlayerInfoByGUID, GetSpellInfo, GetNumGroupMembers, GetRaidRosterInfo, IsEncounterInProgress
	= GetTime, GetInstanceInfo, GetPlayerInfoByGUID, GetSpellInfo, GetNumGroupMembers, GetRaidRosterInfo, IsEncounterInProgress
local UnitGUID, UnitIsDeadOrGhost, UnitIsConnected, UnitAffectingCombat, UnitClass, UnitBuff
	= UnitGUID, UnitIsDeadOrGhost, UnitIsConnected, UnitAffectingCombat, UnitClass, UnitBuff

local addon = Overseer

local consts = addon.consts
local classes = consts.classes
local append = addon.TableAppend
local GroupCache = addon.GroupCache
local Cooldowns = addon.Cooldowns
local GetUnitFromGUID = addon.GetUnitFromGUID
local GUIDClassColoredName = addon.GUIDClassColoredName
local UnitClassColoredName = addon.UnitClassColoredName

local ANKH_ID = consts.ANKH_ID
local MESSAGES = consts.MESSAGES
local PENDING_REZ_EXPIRE = 60 + 5 -- pending rez = 60s timer
local PRECAST_SOULSTONE = -9999 -- just a value that cannot be reached on accident
local BREZ_MAX = {
	--[[
	the max number of combat rezzes keyed by instance size
	
	form:
	instanceSize = maxBrezCount,
	...
	--]]
	
    -- TODO: what is the max brez count for LFR, Flex? (I think LFR has no limit?)
    -- TODO: need to include difficulty here somehow
	[0] = inf,
	[10] = 1,
	[15] = 2, -- TODO: no idea what the brez count is for 15man (or if they will ever reintroduce a 15man instance)
	[20] = 3, -- TODO: fix when 6.0 hits
	[25] = 3,
}

local rezzers = {
	--[[
	list of guids that casted a brez on the keyed guid
	the value is the number of times cast by the src (should only ever be nil, 0, or 1)
	
	form:
	[rezeeGuid] = {
		[rezzerGuid] = true,
		[rezzerGuid] = true,
		...
	},
	...
	--]]
}

local pendingRez = {
	--[[
	list of guids that have a combat rez pending accepts
	the value (pendingRez[guid]) indicates the time at which the guid's rez will expire
	(ie, the time at which they can no longer accept the resurrect)
	
	form:
	[guid] = float,
	...
	--]]
}

local dead = {
	--[[
	list of guids that are dead
	this is only used for combat resurrects
	
	form:
	[guid] = true,
	...
	--]]
}

local deadCount = 0
local brezCount = 0 -- the current remaining number of combat resses
local currentBrezMax = BREZ_MAX[0]

-- ------------------------------------------------------------------
-- Resurrection handling
-- ------------------------------------------------------------------
local function ClearBrezCacheFor(guid)
	rezzers[guid] = nil
	pendingRez[guid] = nil
end

local SendChatMessage = SendChatMessage -- TODO: TMP
local GUIDName = addon.GUIDName -- TODO: TMP
local rezSrcMsg = "         %d resurrects used: %s"
local BROADCAST_TYPE = "RAID" -- TODO: TMP
local BROADCAST_BREZ = { -- TODO: TMP
	--[3] = true, -- 10man
	[4] = true, -- 25
	--[5] = true, -- 10 h
	[6] = true, -- 25 h
}
local function AcceptBrezFor(guid)
	brezCount = brezCount - 1
	addon:SendMessage(MESSAGES.BREZ_ACCEPT, brezCount, guid, rezzers[guid])
	
	-- logging output
	local numUsed = 0
	local rezSrc = ""
	local broadcastSrc = "" -- TODO:  TMP
	for src in next, rezzers[guid] do
		local name = GUIDClassColoredName(src)
		rezSrc = rezSrc:len() > 0 and ("%s, %s"):format(name, rezSrc) or name
		
		local justName = GUIDName(src) -- TODO: TMP
		broadcastSrc = broadcastSrc:len() > 0 and ("%s, %s"):format(justName, broadcastSrc) or justName
		
		numUsed = numUsed + 1
	end
	
	if brezCount >= 0 then
		-- TODO: TMP
		local difficulty = select(3, GetInstanceInfo()) or 0
		if BROADCAST_BREZ[difficulty] then
			SendChatMessage(("%s came back to life! (%d remaining)"):format(GUIDName(guid), brezCount), BROADCAST_TYPE)
			if numUsed > 0 then
				SendChatMessage(("%d resurrect%s used: %s"):format(numUsed, numUsed == 1 and "" or "s", broadcastSrc), BROADCAST_TYPE)
			end
		end
		--
		
		addon:Print(("AcceptBrezFor(): %s came back to life! (%d remaining)"):format(GUIDClassColoredName(guid), brezCount))
		addon:Print((rezSrcMsg):format(numUsed, rezSrc))
		if brezCount == 0 then
			addon:SendMessage(MESSAGES.BREZ_OUT, brezCount)
		end
	else
		local msg = "AcceptBrezFor(): %s revived - |cffFF0000brezCount is bad|r (%d remaining)"
		addon:Debug(msg:format(GUIDClassColoredName(guid), brezCount))
		addon:Debug(rezSrcMsg:format(numUsed, rezSrc))
	end
end

local toRemove = {}
local function ClearAllDeadAndPending()
	wipe(toRemove)
	for guid in next, pendingRez do
		append(toRemove, guid)
	end
	for i = 1, #toRemove do
		local guid = toRemove[i]
		ClearBrezCacheFor(guid)
	end
	
	wipe(dead)
	deadCount = 0
end

local function PruneExpiredPending()
	local now = GetTime()
	wipe(toRemove)
	for guid, expireTime in next, pendingRez do
		if now >= expireTime then
			append(toRemove, guid)
		end
	end
	for i = 1, #toRemove do
		local guid = toRemove[i]
		ClearBrezCacheFor(guid)
	end
end

-- this seems super CPU intensive for something which, in most cases, does not need to be updated instantly
-- the only case for which this really matters is trying to catch someone resurrecting and dying immediately (which it still may not catch?)
function addon:UNIT_HEALTH_FREQUENT(event, unit)
	PruneExpiredPending()
	-- check if unit came back to life
	local guid = UnitGUID(unit)
	if guid and dead[guid] then
		if unit and not UnitIsDeadOrGhost(unit) and UnitAffectingCombat(unit) then
			-- unit came back to life!
			if pendingRez[guid] then
				self:AcceptBrezFor(guid)
			else
				-- either the brez cast was missed
				-- or this is a shaman ankh
				local class = select(2, UnitClass(unit))
				if class == classes.shaman then
					-- possible shaman reincarnate
					-- I don't think a shaman can ankh if they were combat rezzed
					-- TODO: does this work if we miss shaman reincarnating and dying instantly?
					-- TODO: this misses non-boss combat ankhs
					local ankh = Cooldowns[ANKH_ID] and Cooldowns[ANKH_ID][guid]
					if ankh and ankh:NumReady() > 0 then
						ankh:Use()
					end
					
					self:Print(("%s ankh'd! maybe? possibly?"):format(GUIDClassColoredName(guid)))
				else
					self:Debug(("|cffFF0000MISSED PENDING REZ|r: %s came back to life"):format(GUIDClassColoredName(guid)))
				end
			end
			GroupCache:SetState(guid)
			
			ClearBrezCacheFor(guid)
			dead[guid] = nil
			deadCount = deadCount - 1
			
			if deadCount < 0 then
				local msg = "UNIT_HEALTH_FREQUENT(%s): miscounted number of dead = %d"
				self:Debug(msg:format(UnitClassColoredName(unit), deadCount))
			end
		end
	end
	
	if deadCount == 0 then
		self:PauseBrezScan()
	end
end

-- out-of-combat res scanner
-- scan all group members in case we miss a UNIT_DIED event
local invalidGUIDs = {}
local function OutOfCombatResScan()
	if addon.isFightingBoss then
		-- in case somoene pulled with people still dead
		addon:HaltOoCResScan()
	end
	
	wipe(invalidGUIDs)
	local allAlive = true
	local NUM_GROUP_MEMBERS = GetNumGroupMembers()
	for i = 1, NUM_GROUP_MEMBERS do
		local name = GetRaidRosterInfo(i) -- TODO: this returns 'isDead' as 9th return val - is it true if unit is ghost?
		if name then -- sometimes nil.. for x-realm groups only, I think
			local guid = UnitGUID(name)
			if guid then
				-- do not consider benched units here - they should be caught in GROUP_ROSTER_UPDATE
				if not GroupCache:IsBenched(guid) then
					GroupCache:SetState(guid)
					if GroupCache:IsDead(guid) then
						allAlive = false
					end
				end
			else
				-- happens if the unit is offline?
				append(invalidGUIDs, name)
			end
		end
	end
	if #invalidGUIDs > 0 then
		local namesList = ""
		for i = 1, #invalidGUIDs do
			local name = UnitClassColoredName(invalidGUIDs[i])
			namesList = namesList:len() > 0 and ("%s, %s"):format(name, namesList) or name
		end
		local msg = "|cff00FFFFOutOfCombatResScan|r() - %d invalid GUIDs: %s"
		addon:Debug(msg:format(#invalidGUIDs, namesList))
	end
	if allAlive then
		addon:HaltOoCResScan()
	end
end

-- ------------------------------------------------------------------
-- Public functions
-- ------------------------------------------------------------------
function addon:BrezRemaining()
	return brezCount
end

-- returns nil if no rez
-- 		   a negative value if precast soulstone
-- 		   a positive value if a resurrect is pending (the expiration time)
function addon:GUIDPendingRezExpireTime(guid)
	return pendingRez[guid]
end

function addon:AcceptBrezFor(guid)
	AcceptBrezFor(guid)
	ClearBrezCacheFor(guid)
end

function addon:CastBrezOn(destGUID, srcGUID, isPrecastSoulstone)
	local msg = ":CastBrezOn(): %s -> %s (%s)"
	self:PrintFunction(msg:format(GUIDClassColoredName(srcGUID), GUIDClassColoredName(destGUID), isPrecastSoulstone and "ss" or "not ss"), true)
	
	if srcGUID then
		rezzers[destGUID] = rezzers[destGUID] or {}
		rezzers[destGUID][srcGUID] = true
	end
	
	if not isPrecastSoulstone then
		-- wipe away whatever previous value was stored because fuck communication
		pendingRez[destGUID] = GetTime() + PENDING_REZ_EXPIRE
	else
		pendingRez[destGUID] = PRECAST_SOULSTONE
	end
end

function addon:ResetBrezCount()
	self:PrintFunction(":ResetBrezCount()")
	brezCount = currentBrezMax
	addon:SendMessage(MESSAGES.BREZ_RESET, brezCount)
end

function addon:ValidateBrezCount()
	local maxPlayers = select(5, GetInstanceInfo()) or 0
	currentBrezMax = BREZ_MAX[maxPlayers]
	if not currentBrezMax then
		local msg = ":ValidateBrezCount(): No max brez count set for instance size=%s, defaulting to infinite."
		self:Debug(msg:format(tostring(maxPlayers)))
		
		currentBrezMax = BREZ_MAX[0]
	end
	
	brezCount = currentBrezMax
	addon:SendMessage(MESSAGES.BREZ_RESET, brezCount)
	self:PrintFunction((":ValidateBrezCount(%s): max=%d"):format(tostring(maxPlayers), tostring(currentBrezMax)))
end

local brezScanTimer
local SCAN_INTERVAL = 0.5 -- if someone resurrects and dies within half a second..
function addon:AddToDeadList(guid) -- the dead list is only used for brez
	if self.isFightingBoss then
		self:PrintFunction((":AddToDeadList(%s)"):format(GUIDClassColoredName(guid)), true)
		if type(guid) == "string" and guid:len() > 0 and not dead[guid] then
			dead[guid] = true
			deadCount = deadCount + 1
			
			if not brezScanTimer then
				-- first person dead
				self:PrintFunction(">> starting |cffFFA500brez|r scan", true)
				self:RegisterEvent("UNIT_HEALTH_FREQUENT")
				brezScanTimer = true
				--brezScanTimer = self:ScheduleRepeatingTimer(BrezScan, SCAN_INTERVAL)
			end
		end
	end
end

function addon:PauseBrezScan()
	self:PrintFunction(":PauseBrezScan()")
	if brezScanTimer then
		self:PrintFunction(">> stopping |cffFFA500brez|r scan", true)
		self:UnregisterEvent("UNIT_HEALTH_FREQUENT")
		--self:CancelTimer(brezScanTimer)
		brezScanTimer = nil
	end
end

-- ------------------------------------------------------------------
-- Public interface
-- ------------------------------------------------------------------
local Soulstone = GetSpellInfo(consts.SOULSTONE_ID)
function addon:EnableBrezScan()
	self:PrintFunction(":EnableBrezScan()")

	-- watch the CLEU events relevant to combat rezzes
	self:SubscribeCLEUEvent("SPELL_AURA_APPLIED") -- soulstone buff
	self:SubscribeCLEUEvent("UNIT_DIED")
	self:SubscribeCLEUEvent("SPELL_RESURRECT")
	
	-- scan the group to see if anyone has a soulstone
	local NUM_GROUP_MEMBERS = GetNumGroupMembers()
	for i = 1, NUM_GROUP_MEMBERS do
		local name = GetRaidRosterInfo(i)
		local srcUnit = name and select(8, UnitBuff(name, Soulstone))
		if srcUnit then
			-- this person has a soulstone buff
			local srcGUID = UnitGUID(srcUnit)
			local destGUID = UnitGUID(name)
			
			self:CastBrezOn(destGUID, srcGUID, true)
		end
	end
end

function addon:DisableBrezScan()
	self:PrintFunction(":DisableBrezScan()")
	-- if we're disabling, we should no longer care about any state we were maintaining
	ClearAllDeadAndPending()
	self:PauseBrezScan()
	-- stop watching the CLEU events relevant to combat rezzes
	self:UnsubscribeCLEUEvent("SPELL_AURA_APPLIED")
	self:UnsubscribeCLEUEvent("UNIT_DIED")
	self:UnsubscribeCLEUEvent("SPELL_RESURRECT")
end

local resScanTimer
local RES_SCAN_INTERVAL = 2.5
function addon:StartOoCResScan()
	self:PrintFunction(":StartOoCResScan()")
	if not resScanTimer then
		self:PrintFunction(">> starting |cff00FFFFout-of-combat res|r scanner", true)
		resScanTimer = self:ScheduleRepeatingTimer(OutOfCombatResScan, RES_SCAN_INTERVAL)
	end
end

function addon:HaltOoCResScan()
	self:PrintFunction(":HaltOoCResScan()")
	if resScanTimer then
		self:PrintFunction(">> stopping |cff00FFFFout-of-combat res|r scanner", true)
		self:CancelTimer(resScanTimer)
		resScanTimer = nil
	end
end
