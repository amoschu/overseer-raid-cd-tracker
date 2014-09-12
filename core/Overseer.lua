
local hooksecurefunc, select, wipe, type, tostring, ceil
	= hooksecurefunc, select, wipe, type, tostring, math.ceil
local CreateFrame, IsInGroup, UnitGUID, NotifyInspect, IsEncounterInProgress, GetRealZoneText
	= CreateFrame, IsInGroup, UnitGUID, NotifyInspect, IsEncounterInProgress, GetRealZoneText
	
local addon = Overseer

local consts = addon.consts
local classes = consts.classes
local eventsByFilter = consts.eventsByFilter
local GUIDClassColoredName, UnitClassColoredName = addon.GUIDClassColoredName, addon.UnitClassColoredName

local NUM_MAX_GROUPS = consts.NUM_MAX_GROUPS
local EVENT_PREFIX_BUCKET = consts.EVENT_PREFIX_BUCKET
local EVENT_PREFIX_CLEU = consts.EVENT_PREFIX_CLEU
local SCAN_CLASS_INTERVAL = consts.SCAN_CLASS_INTERVAL

-- ------------------------------------------------------------------
-- Addon-level members
-- ------------------------------------------------------------------
addon.isFightingBoss = nil
addon.benchGroup = NUM_MAX_GROUPS + 1

do -- helper frame
	local frame = CreateFrame(consts.FRAME_TYPES.FRAME)
	frame:Hide()
	addon._helperFrame = frame
end

-- ------------------------------------------------------------------
-- Event/message registration
-- ------------------------------------------------------------------
local buckets = {
	--[[
	dictionary of bucket handles keyed by their event/message
	used for unregistering
	
	form:
	[event] = bucketHandle,
	...
	--]]
}
function addon:RegisterCustomEventOrWOWEvent(event)
	local funcName = (":|c%sRegisterCustomEventOrWOWEvent|r"):format(self.REGISTER_COLOR)
	local eventName = ("|cff999999%s|r"):format(event)
	
	if type(event) == "string" then
		local prefix, suffix, interval = consts:DecodeEvent(event)
		if prefix and suffix then
			self:FUNCTION("%s(%s) -> %s, %s, %s", funcName, eventName, tostring(prefix), tostring(suffix), tostring(interval))
			-- one of our encoded filter events (see consts)
			if prefix == EVENT_PREFIX_BUCKET then
				buckets[suffix] = self:RegisterBucketEvent(suffix, interval or 1)
			elseif prefix == EVENT_PREFIX_CLEU then
				self:SubscribeCLEUEvent(suffix)
			else
				local msg = "%s(%s) - Unexpected event or message"
				self:DEBUG(msg, funcName, eventName)
			end
		else
			-- wow event
			self:RegisterEvent(event)
		end
	else
		local msg = "%s(%s) - Expected string argument"
		self:DEBUG(msg, funcName, eventName)
	end
end

function addon:UnregisterCustomEventOrWOWEvent(event)
	local funcName = (":|c%sUnregisterCustomEventOrWOWEvent|r"):format(self.REGISTER_COLOR)
	local eventName = ("|cff999999%s|r"):format(event)
	
	if type(event) == "string" then
		local prefix, suffix = consts:DecodeEvent(event)
		if prefix and suffix then
			self:FUNCTION("%s(%s) -> %s, %s", funcName, eventName, tostring(prefix), tostring(suffix))
			-- one of our encoded filter events (see consts)
			if prefix == EVENT_PREFIX_BUCKET then
				self:UnregisterBucket(buckets[suffix])
			elseif prefix == EVENT_PREFIX_CLEU then
				self:UnsubscribeCLEUEvent(suffix)
			else
				local msg = "%s(%s) - Unexpected event or message"
				self:DEBUG(msg, funcName, eventName)
			end
		else
			-- wow event
			self:UnregisterEvent(event)
		end
	else
		local msg = "%s(%s) - Expected string argument"
		self:DEBUG(msg, funcName, eventName)
	end
end

-- ------------------------------------------------------------------
-- OnInitialize
-- ------------------------------------------------------------------
local RegisterHooks = {}
local registerMsg = ":|c" .. addon.REGISTER_COLOR .. "%s|r(|cff999999%s|r)"
local function HookRegistration(methodName)
	if type(methodName) == "string" then
		if not RegisterHooks[methodName] and type(addon[methodName]) == "function" then
			RegisterHooks[methodName] = true
			hooksecurefunc(addon, methodName, 
				function(self, event)
					-- does this create a new closure every time any hooked function is called?
					-- or is it just once when we call hooksecurefunc?
					-- ..this stuff should be negligible either way
					addon:FUNCTION(registerMsg, methodName, tostring(event))
				end)
		end
	end
end

function addon:OnInitialize()
	self:FUNCTION(":OnInitialize")
	
	self:InitializeDefaultCooldowns()
	self:InitializeDatabase()

	if IsInGroup() then
		-- try to enable immediately in case of /reload in group
		self:Enable()
	else
		-- otherwise we need to wait for the first relevant group event
		self:RegisterEvent("GROUP_JOINED")
	end
	
	HookRegistration("RegisterEvent")
	HookRegistration("UnregisterEvent")
	HookRegistration("RegisterMessage")
	HookRegistration("UnregisterMessage")
	HookRegistration("RegisterBucketEvent")
	HookRegistration("UnregisterBucket")
	HookRegistration("UnregisterAllBuckets")
	
	OverseerSavedState = OverseerSavedState or {}
	addon:RegisterEvent("PLAYER_LOGIN") -- in init to catch CUSTOM_CLASS_COLORS
	addon:RegisterEvent("PLAYER_LOGOUT") -- state saving between sessions
	
	-- this should only run once
	self.OnInitialize = nil
end

-- ------------------------------------------------------------------
-- OnEnable
-- ------------------------------------------------------------------
function addon:GROUP_JOINED()
	-- I don't think a check is needed
	-- the player may not be considered in group at this moment anyway
	-- (ie, IsInGroup may return false for some dumb reason)
	self:Enable()
end

local function Welcome()
	local db = addon.db:GetProfile()
	if db.showWelcomeMessage then
		local slash1 = SLASH_OVERSEER1
		local slash2 = SLASH_OVERSEER2
		addon:PRINT(true, "Type '%s' or '%s' for options. For help, type '%s h'.", slash1, slash2, slash1)
	end
end

local UnitAffectingCombat = UnitAffectingCombat -- TODO: TMP
function addon:OnEnable()
	self:FUNCTION(true, ":OnEnable")
	
	-- TODO: TMP (trying to figure out best way to handle 'Script ran too long errors')
	-- > if this does return true here on a fresh login then instead of doing the normal thing,
	--	 :Register "PLAYER_REGEN_ENABLED" and boot up everything there
	--	 ..what about client dc during boss fight? (the above sln would mean Overseer won't load when coming back from a dc..)
	if UnitAffectingCombat("player") then
		addon:ERROR("|cffFF0000HEY HEY HEY HEY HEY HEY HEY HEY")
		addon:ERROR("|cffFF0000HEY HEY HEY HEY HEY HEY HEY HEY")
		addon:ERROR(">> |cff00FF00the client is in combat|r <<")
		addon:ERROR("|cffFF0000HEY HEY HEY HEY HEY HEY HEY HEY")
		addon:ERROR("|cffFF0000HEY HEY HEY HEY HEY HEY HEY HEY")
	end
	--
	
	-- TODO: only show if enabled in options
	self:ScheduleTimer(Welcome, 7)
	
	-- we don't care to watch these while we're enabled
	self:UnregisterEvent("GROUP_JOINED")
	
	self.playerGUID = UnitGUID("player")
	if not self.playerGUID or self.playerGUID:len() <= 0 then
		local msg = ":OnEnable() - failed to retreive player guid"
		self:DEBUG(msg)
	end
	
	-- intialization
	self.SpellDisplay:Initialize() -- boot up the display
	self.Cooldowns:Initialize()
	
	-- cache player info
	self:SetPlayerZone()
	self:Inspect("player")
	self:ScanGroup(true) -- in case of client disconnect or reload
	self:ValidateBrezCount()
	self:ValidateBenchGroup()
	
	self:RegisterBucketEvent("GROUP_ROSTER_UPDATE", 0.5)
	self:RegisterBucketEvent("UNIT_NAME_UPDATE", 2)
	self:RegisterBucketEvent("UNIT_PORTRAIT_UPDATE", 2)
	
    self:RegisterEvent("UI_SCALE_CHANGED") -- it seems this fires some time after the loading process (a /reload in group can cause display groups to be sized incorrectly)
	self:RegisterEvent("PLAYER_REGEN_ENABLED") -- player exits combat (death, combat ends)
	self:RegisterEvent("ENCOUNTER_START") -- boss engage
	self:RegisterEvent("ENCOUNTER_END")
	self:RegisterEvent("CHALLENGE_MODE_COMPLETED") -- TODO: does this fire on any cmode reset? ie: does it include failed cmode?
	self:RegisterEvent("UNIT_CONNECTION") -- unit online/offline
	self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED") -- catch cd usage & group members changing specs/talents/glyphs (note: CLEU version does not catch the latter)
	self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED") -- player changing specs (seems to sometimes fire for other players as well)
	self:RegisterEvent("PLAYER_DEAD")
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA") -- zoning into/out of instance
	
	-- catch non-encounter deaths/resses
	self:SubscribeCLEUEvent("UNIT_DIED") -- TODO: is there a non-CLEU version of this? catching all CLEUs for a single message sucks
	self:StartOoCResScan() -- in case the client loads the ui while a group member is dead
	
	if IsEncounterInProgress() then
		-- high probability that the player reloaded or dc'd while in combat with a boss
		-- fake an ENCOUNTER_START event
		self:ENCOUNTER_START()
	end
end

-- ------------------------------------------------------------------
-- OnDisable
-- ------------------------------------------------------------------
function addon:OnDisable()
	self:FUNCTION(":OnDisable")
	
	-- reset back to initial state
	
	self:ClearAllInspects()
	self.GroupCache:Wipe()
	self.Cooldowns:Wipe()
	self.SpellDisplay:Shutdown()
	
	-- fake a LOG_OUT to ensure the saved state is cleaned up properly
	self:PLAYER_LOGOUT()
	
	self:UnregisterAllBuckets()
	self:UnregisterAllCLEUMessages()
	
	-- blindly unregister every relevant event
	self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    self:UnregisterEvent("UI_SCALE_CHANGED")
	self:UnregisterEvent("PLAYER_LOGIN")
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	self:UnregisterEvent("INSPECT_READY")
	self:UnregisterEvent("ENCOUNTER_START")
	self:UnregisterEvent("ENCOUNTER_END")
	self:UnregisterEvent("CHALLENGE_MODE_COMPLETED")
	self:UnregisterEvent("UNIT_CONNECTION")
	self:UnregisterEvent("UNIT_HEALTH_FREQUENT")
	self:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	self:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED")
	self:UnregisterEvent("PLAYER_DEAD")
	self:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
	
	self:UnsubscribeCLEUEvent("UNIT_DIED")
	
	-- unregister all events from filters (this should in theory do nothing)
	for filter, event in next, eventsByFilter do
		if type(event) == "table" then
			for i = 1, #event do
				self:UnregisterCustomEventOrWOWEvent(event[i])
			end
		elseif type(event) == "string" then
			self:UnregisterCustomEventOrWOWEvent(event)
		end
	end
	
	-- stop all timers
	self:DisableBrezScan()
	self:HaltOoCResScan()
	
	-- await re-enable event
	self:RegisterEvent("GROUP_JOINED")
end
