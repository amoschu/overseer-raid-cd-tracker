
local wipe, next, select, setmetatable, tostring, type, remove, inf
	= wipe, next, select, setmetatable, tostring, type, table.remove, math.huge
local GetTime, CreateFrame, GetSpellInfo, UIParent
	= GetTime, CreateFrame, GetSpellInfo, UIParent

local addon = Overseer

local consts = addon.consts
local append = addon.TableAppend
local tobool = addon.ToBool
local GUIDClassColoredName, UnitClassColoredName = addon.GUIDClassColoredName, addon.UnitClassColoredName
local GroupCache = addon.GroupCache
local Cooldowns = addon.Cooldowns

local MESSAGES = consts.MESSAGES
local FRAME_TYPES = consts.FRAME_TYPES

local OnGUIDStateChange

-- ------------------------------------------------------------------
-- Display storage structures
-- ------------------------------------------------------------------
local deadDisplays = {
	--[[
	pool of displays we are no longer using
	these are exhausted before creating any new displays
	
	form:
	Display,
	Display,
	...
	--]]
}

local Frames = {
	--[[
	active frames
	
	form:
	[spellCD] = frame,
	[spellCD] = frame,
	...
	--]]
}

-- ------------------------------------------------------------------
-- Display message handling
-- ------------------------------------------------------------------
local function GetDisplayKey(spellCD)
	return addon.db:GetConsolidatedKey(spellCD.spellid) or spellCD
end

function addon:SharesDisplay(spellCD, otherSpellCD)
	-- don't match against same spell instance or non spellCDs
	if type(spellCD) ~= "table" or type(otherSpellCD) ~= "table" or spellCD == otherSpellCD then
		return false
	end
	
	local db = addon.db:GetDisplaySettings(spellCD.spellid)
	local key = GetDisplayKey(spellCD)
	local otherKey = GetDisplayKey(otherSpellCD)
	return key == otherKey or (otherSpellCD.spellid == spellCD.spellid and not db.unique)
end

function addon:GetFirstToExpireSpell(display)
	local closest
	local closestExpire
	-- look for the spell whose expiration time is nearest to now (within the set of spells reperesented by this display)
	for spell in next, display.spells do
		local expire = spell:ExpirationTime()
		if expire ~= spell.READY and expire < (closestExpire or inf) then
			closestExpire = expire
			closest = spell
		end
	end
	
	return closest
end

local spellids = {}
function addon:GetMostRecentBuffCastSpell(display)
	--[[
	eg, priest barrier -> amz -> +2s -> amz
		1: show priest barrier buff duration
		2: wipe barrier, show amz duration
		3: 2s into first amz duration, wipe it and show the second amz duration
		4: show priest barrier again (~5s remaining on buff)
	--]]

	-- 1st pass: get all spellids for this display
	wipe(spellids)
	for spell in next, display.spells do
		spellids[spell.spellid] = true
	end
	
	local mostRecent
	local nearestStart
	local now = GetTime()
	-- 2nd pass: examine the most recently cast spell for each spellid
	-- looking for a buff that is still ticking down
	for id in next, spellids do
		local spell = Cooldowns:GetMostRecentCast(id)
		if spell then
			local buffExpire = spell:BuffExpirationTime()
			-- check if this spell even has a buff that is still active
			if buffExpire ~= spell.READY and buffExpire > now then
				local elapsed = now - spell:StartTime()
				if elapsed < (nearestStart or inf) then
					nearestStart = elapsed
					mostRecent = spell
				end
			end
		end
	end
	
	return mostRecent
end

local function ApplySettings(frame, spellCD)
	local db = addon.db:GetDisplaySettings(spellCD.spellid)
	frame:SetAlpha(db.alpha)
	frame:SetScale(db.scale)
	frame:SetFrameStrata(db.strata)
	frame:SetFrameLevel(db.frameLevel)
	
    if not frame.group then -- TODO: only skip positioning if the group is dynamic
        frame:SetPoint(addon.db:LookupPosition(db))
    end
end

local MovableObject = addon.MovableObject -- TODO? don't blindly make all display frames movable
local SizableObject = addon.SizableObject
local function GetFrame(spellCD)
	local frame = remove(deadDisplays)
	if not frame then
		frame = CreateFrame(FRAME_TYPES.FRAME, nil, UIParent)
		frame:SetScale(1.0)
	end
	
	MovableObject:Embed(frame, "Frame")
	SizableObject:Embed(frame)
	
    ApplySettings(frame, spellCD)
	
	frame:Show()
	return frame
end

local function OnNew(msg, spellCD)
	local db = addon.db:GetDisplaySettings(spellCD.spellid)
	if not db.shown then
		-- user does not want a display for this spell
		-- TODO: if not shown, don't process anything for the spell in core
		return nil
	end
	
	local instance = Frames[spellCD]
	if not instance then
		if db.unique then
			-- unique displays for every spell instance
			instance = GetFrame(spellCD)
		else
			-- single display per spellid
			for spell, display in next, Frames do
				if addon:SharesDisplay(spellCD, spell) then
					instance = display
					break
				end
			end
			if not instance then
				-- first display for this spell
				instance = GetFrame(spellCD)
			end
		end
		--
		instance.spells = instance.spells or {}
		instance.spells[spellCD] = true -- keep a reference of all spells this display represents
		Frames[spellCD] = instance
		
		addon:SendMessage(MESSAGES.DISPLAY_CREATE, spellCD, instance)
		-- in case the cd was created for a benched/dead/offline person
		OnGUIDStateChange(msg, spellCD.guid)
	end
end

local function DestroyFrame(spellCD, frame)
	addon:SendMessage(MESSAGES.DISPLAY_DELETE, spellCD, frame)
	
	if frame:IsResizable() then -- TODO: bake into unembed
		frame:LockSizing()
	end
	-- if frame:IsMovable() then -- TODO: check that this is baked in
		-- -- in case the spell instance destroyed while displays are unlocked
		-- frame:LockMoving() -- TODO: still a bug here.. edges still respond to mouseenter events under certain circumstances
	-- end
	
	if frame.spells then
		wipe(frame.spells)
	end

	-- we can't actually destruct frames
	frame:ClearAllPoints()
	frame:Hide()
	-- throw it in the pool of dead frames so we can recycle it later
	append(deadDisplays, frame)
	MovableObject:Unembed(frame, "Frame")
	SizableObject:Unembed(frame)
end

local function SetDisplayVisibility(spellCD, instance, shown)
	shown = tobool(shown)
	local oldShown = tobool(instance:IsShown())
	if oldShown ~= shown then
		instance:SetShown(shown)
		
		local msg = shown and MESSAGES.DISPLAY_SHOW or MESSAGES.DISPLAY_HIDE
		addon:SendMessage(msg, spellCD, instance)
	end
end

local function QueryGroupCacheState(db, display)
    local dead = db.hide.dead
    local offline = db.hide.offline
    local benched = db.hide.benched
    -- check every spell this display represents to set its shown state
    for spell in next, display.spells do
        local spellGUID = spell.guid
        -- all guids for every spell on this display must be in the given state for the display to hide
        -- otherwise the display will hide as soon as ANY guid is in that state
        --[[
            intended functionality:
            eg, Demo Banner displayed for Meallon and Ogriot
                
            Scenario A:
                Ogriot benched, Meallon not benched
                Demo Banner remains shown
                
            Scenario B:
                Ogriot benched, Meallon benched
                Demo Banner hides
        --]]
        dead = dead and GroupCache:IsDead(spellGUID)
        offline = offline and GroupCache:IsOffline(spellGUID)
        benched = benched and GroupCache:IsBenched(spellGUID)
    end
    return dead, offline, benched
end

local function OnDelete(msg, spellCD)
	local instance = Frames[spellCD]
	if instance then
		-- dispatch message to elements that this specific cooldown is no longer being tracked
		instance.spells[spellCD] = nil
		addon:SendMessage(MESSAGES.DISPLAY_CD_LOST, spellCD, instance)
		
		local db = addon.db:GetDisplaySettings(spellCD.spellid)
		if db.unique then
			DestroyFrame(spellCD, instance)
		else
			local isLastSpell = true
			for spell, display in next, Frames do
				-- check if anyone else is still using this display
				if addon:SharesDisplay(spellCD, spell) or (spellCD ~= spell and display == instance) then
					isLastSpell = false
					break
				end
			end
			if isLastSpell then
				-- this display is no longer showing any other spells
				DestroyFrame(spellCD, instance)
			end
		end
        
		-- recheck visibility in case this was the last person keeping the display from hiding
        local dead, offline, benched = QueryGroupCacheState(db, instance)
        SetDisplayVisibility(spellCD, instance, not (dead or offline or benched))
        
		Frames[spellCD] = nil
	end
end

local function OnModify(msg, spellCD)
	local instance = Frames[spellCD]
	if instance then
		addon:SendMessage(MESSAGES.DISPLAY_MODIFY, spellCD, instance)
	end
end

local function OnBuffExpire(msg, spellCD)
	local instance = Frames[spellCD]
	if instance then
		addon:SendMessage(MESSAGES.DISPLAY_BUFF_EXPIRE, spellCD, instance)
	end
end

local function OnUse(msg, spellCD)
	local instance = Frames[spellCD]
	if instance then
		addon:SendMessage(MESSAGES.DISPLAY_USE, spellCD, instance)
	end
end

local function OnReady(msg, spellCD)
	local instance = Frames[spellCD]
	if instance then
		addon:SendMessage(MESSAGES.DISPLAY_READY, spellCD, instance)
	end
end

local function OnReset(msg, spellCD)
	local instance = Frames[spellCD]
	if instance then
		addon:SendMessage(MESSAGES.DISPLAY_RESET, spellCD, instance)
	end
end

local function OnClassColorUpdate(msg)
	for spellCD, instance in next, Frames do
		addon:SendMessage(MESSAGES.DISPLAY_COLOR_UPDATE, spellCD, instance)
	end
end

--[[local]] function OnGUIDStateChange(msg, guid)
	local spellids = Cooldowns:GetSpellIdsFor(guid)
	if spellids then
		for id in next, spellids do
			local spellCD = Cooldowns[id][guid]
			local display = Frames[spellCD]
			if display and display.spells then -- unnecessary check
				local db = addon.db:GetDisplaySettings(id)
                local dead, offline, benched = QueryGroupCacheState(db, display)
                
				-- local dead = db.hide.dead
				-- local offline = db.hide.offline
				-- local benched = db.hide.benched
				-- -- check every spell this display represents to set its shown state
				-- for spell in next, display.spells do
					-- local spellGUID = spell.guid
					-- -- all guids for every spell on this display must be in the given state for the display to hide
					-- -- otherwise the display will hide as soon as ANY guid is in that state
					-- --[[
						-- intended functionality:
						-- eg, Demo Banner displayed for Meallon and Ogriot
							
						-- Scenario A:
							-- Ogriot benched, Meallon not benched
							-- Demo Banner remains shown
							
						-- Scenario B:
							-- Ogriot benched, Meallon benched
							-- Demo Banner hides
					-- --]]
					-- dead = dead and GroupCache:IsDead(spellGUID)
					-- offline = offline and GroupCache:IsOffline(spellGUID)
					-- benched = benched and GroupCache:IsBenched(spellGUID)
				-- end
				--addon:Debug(("Display %s: all dead? %s, all offline? %s, all benched? %s"):format(GUIDClassColoredName(guid), tostring(dead), tostring(offline), tostring(benched)))
				SetDisplayVisibility(spellCD, display, not (dead or offline or benched))
			end
		end
	end
end

local DEFAULT_KEY = addon.db.DEFAULT_KEY
local function UpdateDisplay(msg, id)
    if id == DEFAULT_KEY then
        -- update all displays
        for spellCD, frame in next, Frames do
            ApplySettings(frame, spellCD)
            -- TODO: .shown, .unique
        end
        for guid in GroupCache:IterateGUIDs() do -- TODO: this seems super expensive, may cause frame stutter
            OnGUIDStateChange(msg, guid)
        end
    else
        local applied
        -- look for the specific display to update
        for spellCD, display in next, Frames do
            local consolidatedId = addon.db:GetConsolidatedKey(spellCD.spellid)
            if id == spellCD.spellid or id == consolidatedId then
                ApplySettings(display, spellCD)
                OnGUIDStateChange(msg, spellCD.guid)
                applied = true
                break
            end
        end
        
        if not applied then
            local debugMsg = "UpdateDisplay(%s): No such display for id='%s'"
            addon:Debug(debugMsg:format(msg, id))
        end
    end
end

-- ------------------------------------------------------------------
-- Public
-- ------------------------------------------------------------------
local SpellDisplay = {
	--[[
	display message handler
	acts as the bridge between core and display
	--]]
}
addon.SpellDisplay = SpellDisplay

do 
	SpellDisplay.RegisterMessage = addon.RegisterMessage
	SpellDisplay.UnregisterMessage = addon.UnregisterMessage
end

local Elements -- TODO: get rid of this class.. merge into Display
function SpellDisplay:Initialize()
	addon:PrintFunction("SpellDisplay:Initialize()")
	-- TODO: check if user has any displays shown (from db)
	self:RegisterMessage(MESSAGES.CD_NEW, OnNew)
	self:RegisterMessage(MESSAGES.CD_DELETE, OnDelete)
	self:RegisterMessage(MESSAGES.CD_MODIFIED, OnModify)
	self:RegisterMessage(MESSAGES.CD_BUFF_EXPIRE, OnBuffExpire)
	self:RegisterMessage(MESSAGES.CD_USE, OnUse)
	self:RegisterMessage(MESSAGES.CD_READY, OnReady)
	self:RegisterMessage(MESSAGES.CD_RESET, OnReset)
	self:RegisterMessage(MESSAGES.CLASS_COLORS_CHANGED, OnClassColorUpdate)
	self:RegisterMessage(MESSAGES.GUID_CHANGE_DEAD, OnGUIDStateChange)
	self:RegisterMessage(MESSAGES.GUID_CHANGE_ONLINE, OnGUIDStateChange)
	self:RegisterMessage(MESSAGES.GUID_CHANGE_BENCHED, OnGUIDStateChange)
    
    self:RegisterMessage(MESSAGES.OPT_DISPLAY_UPDATE, UpdateDisplay)
    
	if not Elements then
		Elements = addon.DisplayElements
	end
	Elements:Initialize()
end

function SpellDisplay:Shutdown()
	addon:PrintFunction("SpellDisplay:Shutdown()")
	if not Elements then
		Elements = addon.DisplayElements
	end
	Elements:Shutdown()
	self:UnregisterMessage(MESSAGES.CD_NEW)
	self:UnregisterMessage(MESSAGES.CD_DELETE)
	self:UnregisterMessage(MESSAGES.CD_MODIFIED)
	self:UnregisterMessage(MESSAGES.CD_BUFF_EXPIRE)
	self:UnregisterMessage(MESSAGES.CD_USE)
	self:UnregisterMessage(MESSAGES.CD_READY)
	self:UnregisterMessage(MESSAGES.CD_RESET)
	self:UnregisterMessage(MESSAGES.CLASS_COLORS_CHANGED)
    self:UnregisterMessage(MESSAGES.OPT_DISPLAY_UPDATE)
end
