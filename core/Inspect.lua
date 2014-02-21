
local hooksecurefunc, next, select, wipe, tostring, ceil, remove, insert
	= hooksecurefunc, next, select, wipe, tostring, math.ceil, table.remove, table.insert
local CanInspect, CheckInteractDistance, ClearInspectPlayer, GetInspectSpecialization, GetTalentInfo, GetGlyphSocketInfo
	= CanInspect, CheckInteractDistance, ClearInspectPlayer, GetInspectSpecialization, GetTalentInfo, GetGlyphSocketInfo
local GetTime, IsEncounterInProgress, IsLoggedIn, UnitGUID, UnitIsDeadOrGhost, UnitIsConnected, UnitClass, UnitIsPlayer, UnitReaction, UnitLevel, UnitIsVisible
	= GetTime, IsEncounterInProgress, IsLoggedIn, UnitGUID, UnitIsDeadOrGhost, UnitIsConnected, UnitClass, UnitIsPlayer, UnitReaction, UnitLevel, UnitIsVisible

local addon = Overseer

local consts = addon.consts
local append = addon.TableAppend
local filterKeys = consts.filterKeys
local optionalKeys = filterKeys[consts.FILTER_OPTIONAL]
local UnitHasFilter = addon.UnitHasFilter
local GroupCache = addon.GroupCache
local GetUnitFromGUID = addon.GetUnitFromGUID
local GUIDClassColoredName = addon.GUIDClassColoredName

local INSPECT_COLOR = "ffFF3399"
local GLYPH_TYPE_MAJOR = GLYPH_TYPE_MAJOR
local CLASS_TALENT_LEVELS = CLASS_TALENT_LEVELS
local GLYPH_LEVEL_UNLOCK = consts.GLYPH_LEVEL_UNLOCK
-- stolen from LibGroupInSpecT
local INSPECT_DELAY = 2 -- delay between scan cycles
local INSPECT_TIMEOUT = 5 * INSPECT_DELAY -- timeout in seconds to stop waiting response from server
local INSPECT_STALE_TIMEOUT = 3 * INSPECT_TIMEOUT -- timeout for people who have exceeded our max attempts
local MAX_ATTEMPTS = 3

-- ------------------------------------------------------------------
-- Inspect hook
-- ------------------------------------------------------------------
local lastServerQuery

local function NotifyInspectHook(unit)
	-- QueueAndStartInspectTimer(unit, true)
	
	-- just cache the time the last query was sent so we don't inadvertently compete and spam the server with another addon
	lastServerQuery = GetTime()
end

local hooked -- shouldn't be needed
if not hooked then
	hooksecurefunc("NotifyInspect", NotifyInspectHook)
	hooked = true
end

-- ------------------------------------------------------------------
-- Inspect queue
-- ------------------------------------------------------------------
-- simple queue of units which need are awaiting inspects
local InspectQueue = {
	--[[
	this logic is mostly stolen from LibGroupInSpecT
	:D
	
	why not just use LibGroupInSpecT, you ask? well, 
		1) it does not handle items for which I would need to write another inspect system
		2) it does not (from what I can tell) handle out-of-range group members - which, again, I would need to write a separate inspect system for
		3) Overseer already has to loop through the group, so why not bake in the join/leave behavior instead of firing up another loop?
			(this third point is most definitely negligible)
	
	3 hiearchal queues (in order of priority):
		1. one-shot queue: queries each element once, if the query times out we move the person to the main queue.
					anecdotally, it seems like if a NotifyInpsect times out once, it is likely to fail completely.
					this ends up hogging the queue, delaying others from being inspected.
					having a single-attempt queue allows the system to query for inspect data on everyone before 
					resorting to blocking-type behavior.
		2. main queue: query the person at the front of the queue MAX_ATTEMPTS times, if we exceed MAX_ATTEMPTS
					the person is moved further down into the stale queue.
		3. stale queue: like the main queue, we query the person at the front MAX_ATTEMPTS times. this queue uses
					a longer timeout interval, however if we exceed MAX_ATTEMPTS, the person is removed and pushed
					into the retryLater list (and queried again on some event - eg, UNIT_PORTRAIT_UPDATE).
					
	the following is for reference
	
	form:
	_oneShotQueue = {
		guid,
		...
	},
	
	_queue = { -- actual LIFO queue part
		guid,
		...
	},
	
	_staleQueue = { -- fallback queue when the regular queue is empty (these are people who have have exceeded max attempts)
		guid,
		guid,
		...
	},
	
	_attemptsByGUID = { -- list of queued units by their guids
		[guid] = numAttempts,
		...
	},
	
	_staleAttempts = { -- attempts for stale guids
		[guid] = numAttempts,
		...
	},
	
	_retryLater = { -- people who we tried to inspect but were out of range (or, for whatever reason, need to be queried again at some later point)
		[guid] = true,
		[guid] = true,
		...
	},
	--]]
	
	_oneShotQueue = {},
	_queue = {},
	_attemptsByGUID = {},
	_staleQueue = {},
	_staleAttempts = {},
	_retryLater = {},
}

local queriedGUID -- the guid of the currently queried person

local function GetGUIDFromUnit(unit, funcName)
	local guid = UnitGUID(unit)
	if not guid or guid:len() <= 0 then
		local msg = "InspectQueue:%s(unit) - could not retreive 'guid' from '%s'"
		addon:Debug(msg:format(funcName, tostring(unit)))
	end
	return guid
end

local function UnitIsInspectable(unit)
	local guid = GetGUIDFromUnit(unit, "UnitIsInspectable")
	return guid and not GroupCache:IsBenched(guid)
		and UnitIsVisible(unit) -- I think the client can only inspect units that are visible? I'm not 100%
		and UnitIsConnected(unit)
		and CanInspect(unit) -- when does this ever return false?
end

local function FindIdxInQueue(guid, queue)
	local idx
	for i = 1, #queue do
		if queue[i] == guid then
			idx = i
			break
		end
	end
	return idx
end

local function GUIDIsInAQueue(guid)
	return guid and (InspectQueue:GUIDIsQueued(guid) or InspectQueue:GUIDIsStale(guid) or FindIdxInQueue(guid, InspectQueue._oneShotQueue))
end

local REACTION_FRIENDLY = 5
function InspectQueue:Push(unit, forceToTop)
	local result = false
	
	local guid = GetGUIDFromUnit(unit, "Push")
	if guid and addon.playerGUID == guid then
		-- don't queue the player - there's no point
		GroupCache:SetPlayerInfo()
		addon:TrackCooldownsFor(guid)
		return result
	end
	
	if UnitIsInspectable(unit) then
		if forceToTop then
			-- force the person into the one-shot queue regardless of attempts or their current queue
			self:Remove(guid)
		end
		if not GUIDIsInAQueue(guid) then
			if guid and guid:len() > 0 then
				if self._retryLater[guid] then
					-- this person was uninspectable last we tried
					self._retryLater[guid] = nil
				end
				append(self._oneShotQueue, guid)
				result = true
			end
		end
	elseif UnitIsPlayer(unit) then
		-- move them out of any queues they might have been in
		self:Remove(guid)
		-- UnitReaction returns nil if unit is out of range (different zone/continent/etc)
		if (UnitReaction(unit, "player") or REACTION_FRIENDLY) >= REACTION_FRIENDLY then
			-- we can't inspect this person, cache them in the uninspectable list
			self._retryLater[guid] = true
			
			local msg = "InspectQueue:Push(unit, %s): %s uninspectable"
			addon:Print(msg:format(tostring(forceToTop), GUIDClassColoredName(guid)))
		end
	else
		-- npc?
		-- this should never happen
		local reaction = UnitReaction(unit, "player")
		addon:Debug( ("InspectQueue:Push(%s): uninspectable, isplayer? %s, reaction=%s - |cffFF0000SOMETHING IS FUCKED|r"):format(
			GUIDClassColoredName(guid), tostring(UnitIsPlayer(unit) and true or false), tostring(reaction))
		)
	end
	return result
end

function InspectQueue:Remove(guid)
	local result = false
	if self:GUIDIsQueued(guid) then
		local idx = FindIdxInQueue(guid, self._queue)
		if idx then
			remove(self._queue, idx)
		end
		self._attemptsByGUID[guid] = nil
		result = true
	elseif self:GUIDIsStale(guid) then
		local idx = FindIdxInQueue(guid, self._staleQueue)
		if idx then
			remove(self._staleQueue, idx)
		end
		self._staleAttempts[guid] = nil
		result = true
	else
		-- try the one-shot queue
		local idx = FindIdxInQueue(guid, self._oneShotQueue)
		if idx then
			remove(self._oneShotQueue, idx)
		end
		-- just blindly remove from the uninspectable list
		self._retryLater[guid] = nil
	end
	return result
end

function InspectQueue:UnitIsQueued(unit) -- main queue
	local guid = GetGUIDFromUnit(unit, "UnitIsQueued")
	return self:GUIDIsQueued(guid)
end

function InspectQueue:UnitIsStale(unit) -- stale queue
	local guid = GetGUIDFromUnit(unit, "UnitIsStale")
	return self:GUIDIsStale(guid)
end

-- this actually returns the number of attempts made for guid
function InspectQueue:GUIDIsQueued(guid)
	return guid and self._attemptsByGUID[guid]
end

function InspectQueue:GUIDIsStale(guid)
	return guid and self._staleAttempts[guid]
end

-- get the number of attempts for the current inspect
function InspectQueue:GetAttempts()
	local attempts
	if queriedGUID then
		if queriedGUID == self._queue[1] then
			attempts = self._attemptsByGUID[queriedGUID]
		elseif queriedGUID == self._staleQueue[1] then
			attempts = self._staleAttempts[queriedGUID]
		end
	end
	return attempts or 0
end

function InspectQueue:IsEmpty()
	return #self._oneShotQueue == 0 and #self._queue == 0 and #self._staleQueue == 0
end

-- return 'guid', queueLevel
local function GetNextGUID()
	if #InspectQueue._oneShotQueue > 0 then
		return InspectQueue._oneShotQueue[1], 1
	elseif #InspectQueue._queue > 0 then
		return InspectQueue._queue[1], 2
	elseif #InspectQueue._staleQueue > 0 then
		return InspectQueue._staleQueue[1], 3
	end
end

local function GetNumAttempts(guid)
	return InspectQueue._attemptsByGUID[guid] or InspectQueue._staleAttempts[guid]
end

local function ShiftToNextQueue(guid, queueLevel)
	InspectQueue:Remove(guid)
	if queueLevel == 1 then
		-- 1st -> 2nd (move to main queue)
		append(InspectQueue._queue, guid)
		InspectQueue._attemptsByGUID[guid] = 0
	elseif queueLevel == 2 then
		-- 2nd -> 3rd (move to stale queue)
		append(InspectQueue._staleQueue, guid)
		InspectQueue._staleAttempts[guid] = 0
	elseif queueLevel == 3 then
		-- 3rd -> give up, try again later
		-- TODO: would it be better to just give up completely?
		InspectQueue._retryLater[guid] = true
	end
end

function InspectQueue:Query()
	local result = false
	local guid, queueLevel, unit
	-- queue hierarchy maintenance
	while not (guid or self:IsEmpty()) do
		guid, queueLevel = GetNextGUID()
		if guid then -- should never be nil
			unit = GetUnitFromGUID(guid)
			local maxAttempts = queueLevel and (1 < queueLevel and queueLevel <= 3) and MAX_ATTEMPTS or 1
			local attempts = GetNumAttempts(guid)
			if not attempts then
				-- we're querying from the one-shot queue
				attempts = queriedGUID == guid and 1 or 0
			end
			
			if not UnitIsInspectable(unit) then
				-- person is not inspectable, push them into the uninspectable list
				local msg = "|c%sInspectQueue|r:Query(): %s uninspectable"
				addon:Print(msg:format(INSPECT_COLOR, GUIDClassColoredName(guid)))
				
				self:Remove(guid)
				self._retryLater[guid] = true
				guid = nil
			elseif attempts >= maxAttempts then
				ShiftToNextQueue(guid, queueLevel)
				guid = nil
			end
		end
	end
	
	if guid and not self:IsEmpty() then
		-- increment attempts count
		if queueLevel == 2 then
			self._attemptsByGUID[guid] = (self._attemptsByGUID[guid] or 0) + 1
		elseif queueLevel == 3 then
			self._staleAttempts[guid] = (self._staleAttempts[guid] or 0) + 1
		end
		NotifyInspect(unit)
		queriedGUID = guid
		
		local msg = "|c%sInspectQueue|r:Query(): querying %s (attempt #%d)"
		addon:Print(msg:format(INSPECT_COLOR, GUIDClassColoredName(guid), GetNumAttempts(guid) or 1))
		result = true
	end
	
	return result
end

function InspectQueue:Wipe()
	wipe(self._oneShotQueue)
	wipe(self._queue)
	wipe(self._attemptsByGUID)
	wipe(self._staleQueue)
	wipe(self._staleAttempts)
	wipe(self._retryLater)
	
	queriedGUID = nil -- shoul no longer care if wiping
	ClearInspectPlayer() -- TODO: needed?
end

-- ------------------------------------------------------------------
-- Debugging
-- ------------------------------------------------------------------
do
	local indent = consts.INDENT
	local empty = consts.EMPTY
	function InspectQueue:Debug()
		addon:Print(("|c%sInspect|r 1st: ==============="):format(INSPECT_COLOR), true)
		if #self._oneShotQueue == 0 then
			addon:Print(("%s%s"):format(indent, empty), true)
		else
			for i = 1, #self._oneShotQueue do -- one-shot queue
				local guid = self._oneShotQueue[i]
				addon:Print(("%s%d: %s"):format(indent, i, GUIDClassColoredName(guid)), true)
			end
		end
		addon:Print(("|c%sInspect|r Queue: ============"):format(INSPECT_COLOR), true)
		if #self._queue == 0 then
			addon:Print(("%s%s"):format(indent, empty), true)
		else
			for i = 1, #self._queue do -- main queue
				local guid = self._queue[i]
				local attempts = self._attemptsByGUID[guid]
				addon:Print(("%s%d: %s (%s)"):format(indent, i, GUIDClassColoredName(guid), tostring(attempts)), true)
			end
		end
		addon:Print(("|c%sInspect|r Stale: ============"):format(INSPECT_COLOR), true)
		if #self._staleQueue == 0 then
			addon:Print(("%s%s"):format(indent, empty), true)
		else
			for i = 1, #self._staleQueue do -- stale queue
				local guid = self._staleQueue[i]
				local attempts = self._staleAttempts[guid]
				addon:Print(("%s%d: %s (%s)"):format(indent, i, GUIDClassColoredName(guid), tostring(attempts)), true)
			end
		end
		addon:Print(("|c%sInspects|r Retrying later: ====="):format(INSPECT_COLOR), true)
		local isEmpty = true
		for guid in next, self._retryLater do -- flagged for retry (uninspectable, missing talents/glyphs)
			isEmpty = false
			addon:Print(("%s%s"):format(indent, GUIDClassColoredName(guid)), true)
		end
		if isEmpty then
			addon:Print(("%s%s"):format(indent, empty), true)
		end
	end

	function addon:DebugInspects() InspectQueue:Debug() end
end

-- ------------------------------------------------------------------
-- Processing
-- ------------------------------------------------------------------
local InspectTimer
local QueryNextInspect

local function IsTimedOut() -- TODO: LFR/X-realm may need a longer timeout
	local timeout = INSPECT_TIMEOUT
	if queriedGUID and queriedGUID == InspectQueue._staleQueue[1] then
		timeout = INSPECT_STALE_TIMEOUT
	end
	return GetTime() - (lastServerQuery or 0) >= timeout
end

function StartInspects()
	addon:PrintFunction("StartInspects()")
	-- shouldn't need to re-register, but I don't think registering multiple times matters
	
	if not (InspectQueue:IsEmpty() or InspectTimer) then
		addon:PrintFunction((">> starting |c%sinspect|r timer"):format(INSPECT_COLOR), true)
		
		addon:RegisterEvent("INSPECT_READY")
		QueryNextInspect() -- fire immediately
		InspectTimer = addon:ScheduleRepeatingTimer(QueryNextInspect, INSPECT_DELAY)
	elseif InspectTimer and addon:TimeLeft(InspectTimer) == 0 then
		-- timer died somehow..
		-- not sure if this can happen
		addon:CancelTimer(InspectTimer)
		addon:RegisterEvent("INSPECT_READY")
		
		addon:PrintFunction((">> restarting |c%sinspect|r timer (it was invalidated somehow..)"):format(INSPECT_COLOR), true)
		QueryNextInspect()
		InspectTimer = addon:ScheduleRepeatingTimer(QueryNextInspect, INSPECT_DELAY)
	end
end

function StopInspects()
	addon:PrintFunction("StopInspects()")
	if InspectTimer then
		addon:PrintFunction((">> stopping |c%sinspect|r timer"):format(INSPECT_COLOR))
		addon:CancelTimer(InspectTimer)
		InspectTimer = nil
		
		addon:UnregisterEvent("INSPECT_READY")
	end
end

local InspectFrame -- upval to improve efficiency (which, in all likelihood, ends up being negligible)
local InspectFrameHooked
--[[local]] function QueryNextInspect()
	if addon.isFightingBoss or UnitIsDeadOrGhost("player") or not IsLoggedIn() then
		-- stop the timer if we are in a state where inspects should not be happening
		StopInspects()
		return
	end
	
	if not InspectFrame then
		InspectFrame = _G.InspectFrame
	end
	
	-- don't fuck with the UI
	if InspectFrame and InspectFrame:IsShown() then
		if not InspectFrameHooked then
			InspectFrameHooked = true
			InspectFrame:HookScript("OnHide", StartInspects)
		end
		
		StopInspects()
		return
	end
	
	if InspectQueue:IsEmpty() then
		StopInspects()
	elseif IsTimedOut() then
		InspectQueue:Query()
	end
end

-- ------------------------------------------------------------------
-- INSPECT_READY
-- ------------------------------------------------------------------
-- returns true if all caching was successful since not all information is guaranteed to be available
local function CacheInfo(guid)
	--[[
	TODO: gather item information here - only cache what we need
		it doesn't seem like item information is available first time through..
		need to query another inspect if we don't get all item info (num items < 15?)
	--]]
	
	return GroupCache:SetSpec(guid) and GroupCache:SetTalents(guid) and GroupCache:SetGlyphs(guid)
end

local function HasAllTalentsForLevel(guid)
	local result = true
	local unit = GetUnitFromGUID(guid)
	if unit and UnitHasFilter(unit, optionalKeys.TALENT) then
		local class = select(2, UnitClass(unit))
		local level = UnitLevel(unit)
		local talentTier = 0
		local classTalentLevels = CLASS_TALENT_LEVELS[class] or CLASS_TALENT_LEVELS["DEFAULT"]
		if #classTalentLevels < 1 then -- don't bother checking nil - I want that to throw a lua error to ease debugging (if/when blizzard removes the CLASS_TALENT_LEVELS constant)
			-- blizzard either changed the way this constant is structured
			-- ..or the way talents work has changed completely (again)
			local msg = "Expected CLASS_TALENT_LEVELS[%s] to contain at least 1 element! (it has %d elements)"
			addon:Error(msg:format(class, #classTalentLevels))
		end
		for i = #classTalentLevels, 1, -1 do -- assumption: the CLASS_TALENT_LEVELS table is ordered from lowest -> highest level
			-- figure out the max talent tier this person can have
			local tierLevel = classTalentLevels[i]
			if level >= tierLevel then
				talentTier = i
				break -- if the above assumption is incorrect, remove this line
			end
		end
		result = GroupCache:NumTalents(guid) == talentTier
	end
	return result
end

local function HasAllMajorGlyphsForLevel(guid)
	local result = true
	local unit = GetUnitFromGUID(guid)
	if unit and UnitHasFilter(unit, optionalKeys.GLYPH) then
		local class = select(2, UnitClass(unit))
		local level = UnitLevel(unit)
		local numMajorGlyphsEnabled = 0
		for i = #GLYPH_LEVEL_UNLOCK, 1, -1 do
			local glyphLevel = GLYPH_LEVEL_UNLOCK[i]
			if level >= glyphLevel then
				numMajorGlyphsEnabled = i
				break
			end
		end
		result = GroupCache:NumGlyphs(guid, GLYPH_TYPE_MAJOR) == numMajorGlyphsEnabled
	end
	return result
end

function addon:INSPECT_READY(event, guid)
	self:PrintFunction(("|c%sINSPECT_READY|r(%s): queried=%s"):format(
		INSPECT_COLOR,
		type(guid) == "string" and GUIDClassColoredName(guid) or tostring(guid),
		queriedGUID and GUIDClassColoredName(queriedGUID) or "<|cff999999none|r>")
	)
	
	-- if the queue is empty, 
	-- either an outside source triggered our handler or we dropped the guid from the queue
	if not InspectQueue:IsEmpty() then
		-- if the first-queued guid does not match, an outside source triggered our handler
		if queriedGUID and queriedGUID == guid then
			-- otherwise, handle our last query
			queriedGUID = nil
			if CacheInfo(guid) then
				self:TrackCooldownsFor(guid)
				-- we're done inspecting this person
				InspectQueue:Remove(guid)
				ClearInspectPlayer() -- I don't fully understand what this does
				
				-- make sure the person has every talent/glyph slot filled appropriate for their level
				-- if not, flag that this person needs to be inspected again at some later time
				local hasAllTalents = HasAllTalentsForLevel(guid)
				local hasAllMajorGlyphs = HasAllMajorGlyphsForLevel(guid)
				if not (hasAllTalents and hasAllMajorGlyphs) then
					local missing = not hasAllTalents and "talents" or ""
					missing = not hasAllMajorGlyphs and (missing.."/glyphs") or missing
					local msg = "|c%sINSPECT_READY|r: %s is missing some %s!! Retrying later!"
					self:Print(msg:format(INSPECT_COLOR, GUIDClassColoredName(guid), missing))
					-- TODO: this will constantly retry people who purposefully have a glyph slot empty or a talent tier unselected
					-- (eg, unselecting a CC tier for a raid encounter with mind controls)
					InspectQueue._retryLater[guid] = true
				end
				
				InspectQueue:Query() -- query next in line
			else
				-- we were unable to cache everything we wanted
				-- this could indicate a problem with some constant
				local msg = "|c%sINSPECT_READY|r: some information not yet available for %s!!"
				self:Print(msg:format(INSPECT_COLOR, GUIDClassColoredName(guid)))
			end
		end
	end
end

-- ------------------------------------------------------------------
-- Public interface
-- ------------------------------------------------------------------
function addon:Inspect(unit, forceToTop)
	forceToTop = forceToTop and true
	-- queue the unit
	if InspectQueue:Push(unit, forceToTop) then
		-- start up the timer to process the queue if we actually queued the unit
		-- note: this will not do anything if the timer is already running
		StartInspects()
	end
end

-- returns true if the unit was out of range the last time an :Inspect was called on it
-- ..or if the person was missing any talents/glyphs appropriate for their level
function addon:InspectNeedsRetry(unit)
	local guid = UnitGUID(unit)
	return guid and guid:len() > 0 and InspectQueue._retryLater[guid]
end

function addon:ProcessInspects()
	StartInspects()
end

-- completely drops the guid from the inspect system
function addon:CancelInspect(guid)
	InspectQueue:Remove(guid)
end

function addon:ClearAllInspects()
	InspectQueue:Wipe()
end
