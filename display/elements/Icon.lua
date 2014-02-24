
local next, select, type, wipe, inf, remove
	= next, select, type, wipe, math.huge, table.remove
local CreateFrame, GetSpellInfo, GetTime, UIParent, SetDesaturation
	= CreateFrame, GetSpellInfo, GetTime, UIParent, SetDesaturation

local addon = Overseer

local consts = addon.consts
local append = addon.TableAppend
local GUIDClassColorRGB = addon.GUIDClassColorRGB
local GUIDClassColoredName = addon.GUIDClassColoredName
local Cooldowns = addon.Cooldowns
local GroupCache = addon.GroupCache

local BREZ_IDS = consts.BREZ_IDS
local MESSAGES = consts.MESSAGES
local FRAME_TYPES = consts.FRAME_TYPES

local _DEBUG_DESAT = false
local _DEBUG_COOLDOWN = true
local _DEBUG_ICON_PREFIX = "|cffFFD27FICON|r"

-- ------------------------------------------------------------------
-- Icon data structures
-- ------------------------------------------------------------------
local deadIcons = {
	--[[
	pool of reusable icons
	
	form:
	frame,
	frame,
	...
	--]]
}

local Icons = {
	--[[
	stores active icon elements
	
	form:
	[display] = IconElement,
	...
	--]]
}

local Elements = addon.DisplayElements
Elements:Register(Icons, 2)

-- ------------------------------------------------------------------
-- Icon helpers
-- ------------------------------------------------------------------
local function SetIconBorderColor(icon, spellCD)
	local db = addon.db:GetDisplaySettings(spellCD.spellid)
	local border = db.icon.border
	if border.shown then
		local r,g,b,a
		if border.useClassColor then
			r, g, b, a = GUIDClassColorRGB(spellCD.guid)
		else
			-- TODO: need color defaults..
			r = border.r or 0.6
			g = border.g or 0.6
			b = border.b or 0.6
			a = border.a or 1
		end
		icon.border.bg:SetTexture(r, g, b, a)
	end
end

local SEC_PER_MIN = consts.SEC_PER_MIN
local function DesaturateIfNoneCastable(icon, display, triggerSpell)
	local db = addon.db:GetDisplaySettings(triggerSpell.spellid)
	if db.icon.desatIfUnusable then
		local numCastable = 0
        if not BREZ_IDS[triggerSpell.spellid] then
            for spell in next, display.spells do
                local guid = spell.guid
                local valid = not (GroupCache:IsDead(guid) or GroupCache:IsOffline(guid) or GroupCache:IsBenched(guid))
                
                if _DEBUG_DESAT then
                    if not valid then
                        local dead = GroupCache:IsDead(guid) and "Dead" or ""
                        local offline = GroupCache:IsOffline(guid) and "Offline" or ""
                        local benched = GroupCache:IsBenched(guid) and "Benched" or ""
                        addon:Debug(("->%s invalid: %s%s%s"):format(tostring(spell), dead, offline, benched))
                    end
                    if spell:NumReady() == 0 then
                        local t = spell:TimeLeft()
                        addon:Debug(("->%s none ready: (%dm %ds)"):format(tostring(spell), t / SEC_PER_MIN, t % SEC_PER_MIN))
                    end
                end
                
                if spell:NumReady() >= 1 and valid then
                    numCastable = numCastable + 1
                    break
                end
            end
        else
            -- any display with brezzes should desat based on the brez count
            numCastable = addon:BrezRemaining()
        end
		
		SetDesaturation(icon.tex, numCastable == 0)
		if db.icon.border.shown then
			if numCastable == 0 then
				-- desat the border
				icon.border.bg:SetTexture(0.6, 0.6, 0.6, 1)
				icon.border.bg.desat = true
			elseif icon.border.bg.desat then
				-- only set a new border color if the border was desaturated
				SetIconBorderColor(icon, triggerSpell)
				icon.border.bg.desat = nil
			end
		end
	end
end

local function SetIconTextureAndBorder(icon, spellCD)
	local newTex = select(3, GetSpellInfo(spellCD.spellid)) -- TODO: check db for custom icon
	local currentTex = icon.tex:GetTexture()

	if currentTex ~= newTex then
		SetIconBorderColor(icon, spellCD)
		icon.tex:SetTexture(newTex)
	end
end

local function OnIconSizeChange(icon, width, height)
	-- crop the texture in an attempt to preserve its dimensions relative to frame size
	-- (so that the texture does not appear distorted)
	local widthZoom = 0
	local heightZoom = 0
	local aspectRatio = width / height
	
	if aspectRatio < 1 then
		-- height > width
		widthZoom =  1 - aspectRatio
		widthZoom = 0.5 * widthZoom
	elseif aspectRatio > 1 then
		-- width > height
		heightZoom = 1 - (1 / aspectRatio)
		heightZoom = 0.5 * heightZoom -- half because this specifies both top & bottom offsets
	end
	
	-- http://wowprogramming.com/docs/widgets/Texture/SetTexCoord
	-- :SetTexCoord(left, right, top, bottom)
	--	left, right are relative to the texture's left edge [0-1]
	--	top, bottom are relative to the texture's top edge [0-1]
	icon.tex:SetTexCoord(widthZoom, 1 - widthZoom, heightZoom, 1 - heightZoom)
end

local cdFrameCounter = 0
local COOLDOWN_FRAME_NAME = "Overseer_Cooldown_%d"
local function GetIcon(spellCD, parent)
	local db = addon.db:GetDisplaySettings(spellCD.spellid)
	local icon = remove(deadIcons)
	if not icon then
		icon = CreateFrame(FRAME_TYPES.FRAME)
		
		-- this should catch initial sizing as well
		if db.icon.autoCrop then
			icon:SetScript("OnSizeChanged", OnIconSizeChange)
		end
		
		-- note: the border is actually another frame that sits behind the icon that is 'borderSize' larger
		local borderSize = db.icon.border.size or 1
		cdFrameCounter = cdFrameCounter + 1 -- TODO: TMP - testing if this helps OmniCC see these
		icon.border = CreateFrame(FRAME_TYPES.FRAME, COOLDOWN_FRAME_NAME:format(cdFrameCounter), icon)
		icon.border:ClearAllPoints()
		icon.border:SetPoint("TOPLEFT", -borderSize, borderSize)
		icon.border:SetPoint("BOTTOMRIGHT", borderSize, -borderSize)
		icon.border.bg = icon.border:CreateTexture(nil, "BACKGROUND", nil, -8)
		icon.border.bg:SetAllPoints()
		
		icon.cd = CreateFrame(FRAME_TYPES.COOLDOWN, nil, icon)
		icon.cd:SetAllPoints()
		icon.tex = icon:CreateTexture(nil, "BACKGROUND", nil, -8)
		icon.tex:SetNonBlocking(true) -- allow asynchronous texture loading (shouldn't matter in most? all? cases)
		--icon.tex:SetTexCoord(0.25, 0.75, 0.25, 0.75) -- zoom = (z, 1-z, z, 1-z), where z = zoom %
		--icon.tex:SetTexCoord(.07, 1-.07, .23, 1-.23)
		icon.tex:SetAllPoints()
	end
	icon:SetParent(parent) -- must be set before frame strata is applied otherwise z-order is set arbitrarily
	icon:SetFrameStrata(db.strata)
	icon:SetFrameLevel(db.frameLevel - 1)
	icon.border:SetFrameStrata(db.strata)
	icon.border:SetFrameLevel(db.frameLevel - 2)
	
	icon.border:SetShown(db.icon.border.shown)
	icon:Show()
	return icon
end

-- ------------------------------------------------------------------
-- OnCreate
-- ------------------------------------------------------------------
Icons[MESSAGES.DISPLAY_CREATE] = function(self, msg, spellCD, display)
	local db = addon.db:GetDisplaySettings(spellCD.spellid)
	if db.icon.shown then
		--addon:PrintFunction(("Icons:%s(%s)"):format(msg, tostring(spellCD)))
		
		local icon = self[display]
		if not icon then
			icon = GetIcon(spellCD, display)
			icon:ClearAllPoints()
			icon:SetAllPoints(display)
			self[display] = icon
			
			-- TODO: TMP
			--addon:ScheduleTimer(function() icon:Hide() end, 5)
			-- Elements:RegisterMouse(icon, "OnEnter", spellCD)
			-- Elements:RegisterMouse(icon, "OnLeave", spellCD)
			-- Elements:RegisterMouse(icon, "OnMouseDown", spellCD)
			-- Elements:RegisterMouse(icon, "OnMouseUp", spellCD)
			-- Elements:RegisterMouse(icon, "OnMouseWheel", spellCD)
			--
		end
		-- update the icon's texture/border with a potentially new icon
		-- this only matters for displays which represent more than one spellid (and/or class)
		SetIconTextureAndBorder(icon, spellCD)
		DesaturateIfNoneCastable(icon, display, spellCD)
	end
end

-- ------------------------------------------------------------------
-- OnDelete
-- ------------------------------------------------------------------
local function StopCooldown(icon, spellCD, display)
	if (icon.cd.expire or 0) > 0 then
		icon.cd:SetCooldown(0, 0)
		icon.cd.start = nil
		icon.cd.expire = nil
	end
	icon.cd.buffExpire = nil
	icon.cd:SetReverse(false)
	DesaturateIfNoneCastable(icon, display, spellCD) -- potential re-saturate
end

Icons[MESSAGES.DISPLAY_DELETE] = function(self, msg, spellCD, display)
	local icon = self[display]
	if icon then
		--addon:PrintFunction(("Icons:%s(%s)"):format(msg, tostring(spellCD)))
		
		icon:Hide()
		StopCooldown(icon, spellCD, display)
		icon:ClearAllPoints()
		icon:SetParent(nil)
		
		self[display] = nil
		
		append(deadIcons, icon)
	end
end

-- ------------------------------------------------------------------
-- OnModify
-- ------------------------------------------------------------------
Icons[MESSAGES.DISPLAY_MODIFY] = function(self, msg, spellCD, display)
	local icon = self[display]
	if icon then
		SetIconTextureAndBorder(icon, spellCD)
	end
end

-- ------------------------------------------------------------------
-- OnBuffExpire
-- ------------------------------------------------------------------
local function StartBuffDurationCountdown(icon, spellCD)
	local db = addon.db:GetDisplaySettings(spellCD.spellid)
	if db.icon.showBuffDuration then
		local now = GetTime()
		local startTime = spellCD:StartTime()
		local elapsed = now - startTime
		local buffDuration = spellCD:BuffDuration()
		
		-- I don't think this check is actually necessary
		if buffDuration > elapsed then
			icon.cd:SetReverse(true)
			icon.cd:SetCooldown(startTime, buffDuration)
			icon.cd.buffExpire = startTime + buffDuration
			
			DesaturateIfNoneCastable(icon, icon:GetParent(), spellCD)
		end
	end
end

local function StartCooldown(icon, spellCD)
	local db = addon.db:GetDisplaySettings(spellCD.spellid)
	if db.icon.cooldown then
		icon.cd:SetReverse(false)
		if spellCD:TimeLeft() ~= spellCD.READY then
			-- start a fresh cooldown sweep
			local startTime = spellCD:StartTime()
			icon.cd:SetCooldown(startTime, spellCD.duration)
			
			icon.cd.start = startTime
			icon.cd.expire = spellCD:ExpirationTime()
			
			if _DEBUG_COOLDOWN then
				addon:Warn(("%s> Starting CD for %s.."):format(_DEBUG_ICON_PREFIX, tostring(spellCD)))
			end
		end
	end
	SetIconTextureAndBorder(icon, spellCD)
	DesaturateIfNoneCastable(icon, icon:GetParent(), spellCD)
end

local function StartNextCooldown(icon, display, spellCD)
	local spell = addon:GetFirstToExpireSpell(display)
	if spell then
		StartCooldown(icon, spell)
	end
end

Icons[MESSAGES.DISPLAY_BUFF_EXPIRE] = function(self, msg, spellCD, display)
	local icon = self[display]
	if icon then
		-- make sure there isn't already another buff duration shown
		if (icon.cd.buffExpire or 0) < GetTime() then
			local spell = addon:GetMostRecentBuffCastSpell(display)
			
			if _DEBUG_COOLDOWN then
				addon:Print(("%s> %s -> closest = %s"):format(_DEBUG_ICON_PREFIX, msg, tostring(spell)))
			end
			
			if spell then
				StartBuffDurationCountdown(icon, spell)
			else
				StopCooldown(icon, spellCD, display)
				-- otherwise, try to show an active cooldown duration
				-- note: the cooldown displayed may not correspond to _this_ spellCD
				StartNextCooldown(icon, display, spellCD)
			end
		end
		--else: the buff which just expired was overridden by the one currently displayed (so, no display change)
	end
end

-- ------------------------------------------------------------------
-- OnUse
-- ------------------------------------------------------------------
local function ShowNewCooldown(icon, spellCD)
	local expire = icon.cd.expire or 0
	local noCDShown = expire < GetTime()
	local currentExpiresAfter = spellCD:ExpirationTime() < expire
	
	-- show if there is no buff duration shown and there is either no currently running cd or the currently shown cd will expire after the new one
	return not icon.cd.buffExpire and (noCDShown or currentExpiresAfter)
end

Icons[MESSAGES.DISPLAY_USE] = function(self, msg, spellCD, display)
	local icon = self[display]
	if icon then
		-- try to show a buff duration for this spell
		-- showing buff durations takes precedence over normal cooldowns and previously cast buff durations
		if spellCD:BuffExpirationTime() > GetTime() then
			StartBuffDurationCountdown(icon, spellCD)
		end
		
		if ShowNewCooldown(icon, spellCD) then
			StopCooldown(icon, spellCD, display)
			StartCooldown(icon, spellCD)
		end
        
        DesaturateIfNoneCastable(icon, display, spellCD)
	end
end

-- ------------------------------------------------------------------
-- OnReady/OnReset
-- ------------------------------------------------------------------
Icons[MESSAGES.DISPLAY_READY] = function(self, msg, spellCD, display)
	local icon = self[display]
	if icon then
		StopCooldown(icon, spellCD, display)
		StartNextCooldown(icon, display, spellCD)
	end
end

-- _RESET is the same as _READY in case the display represents some cds which _do_ reset and some which _do not_
Icons[MESSAGES.DISPLAY_RESET] = Icons[MESSAGES.DISPLAY_READY]

-- ------------------------------------------------------------------
-- OnShow
-- ------------------------------------------------------------------
Icons[MESSAGES.DISPLAY_SHOW] = function(self, msg, spellCD, display)
	local icon = self[display]
	if icon then
		-- TODO: may not need to do anything.. for now, update the icon/border just in case something changed, I guess
		SetIconTextureAndBorder(icon, spellCD)
	end
end

-- ------------------------------------------------------------------
-- handle spellCD:Delete() - Display dispatches its _DELETE message only when the display is dying
-- ------------------------------------------------------------------
Icons[MESSAGES.DISPLAY_CD_LOST] = function(self, msg, spellCD, display)
	local icon = self[display]
	if icon then
		if display.spells then
			-- update the icon so it is not displaying the spellid that was just lost
			local spell = next(display.spells)
			if spell and spell.spellid then
				SetIconTextureAndBorder(icon, spell)
			end
		end
	end
end

-- ------------------------------------------------------------------
-- Custom class color update
-- ------------------------------------------------------------------
Icons[MESSAGES.DISPLAY_COLOR_UPDATE] = function(self, msg, spellCD, display)
	local icon = self[display]
	if icon then
		SetIconTextureAndBorder(icon, spellCD)
	end
end

-- ------------------------------------------------------------------
-- Brez handling
-- ------------------------------------------------------------------
local function IsIcon(display, icon)
	return type(display) == "table" and display.spells and type(icon) == "table"
end

local function IconBrezHandler(self, msg, brezCount)
	for display, icon in next, self do
		if IsIcon(display, icon) then
			for id in next, BREZ_IDS do
				local spellCooldowns = Cooldowns[id]
				if spellCooldowns then
					for _, spellCD in next, spellCooldowns do
						if display.spells[spellCD] then
							-- TODO: read user option on when/how to desat
							DesaturateIfNoneCastable(icon, display, spellCD)
							break
						end
					end
				end
			end
            -- don't break from looping through all displays in case the user has multiple brez displays
		end
	end
end
Icons[MESSAGES.BREZ_OUT] = 		IconBrezHandler
Icons[MESSAGES.BREZ_RESET] = 	IconBrezHandler

-- ------------------------------------------------------------------
-- GUID state handling
-- ------------------------------------------------------------------
local function IconGUIDStateHandler(self, msg, guid)
	local spellids = Cooldowns:GetSpellIdsFor(guid)
	if spellids then
		for display, icon in next, self do
			if IsIcon(display, icon) then
				for id in next, spellids do
					if not BREZ_IDS[id] then -- guid state change should have no effect on any brez displays
						local spellCD = Cooldowns[id][guid]
						if display.spells[spellCD] then
							DesaturateIfNoneCastable(icon, display, spellCD)
						end
					end
				end
			end
		end
	end
end
Icons[MESSAGES.GUID_CHANGE_DEAD] 	= IconGUIDStateHandler
Icons[MESSAGES.GUID_CHANGE_ONLINE]  = IconGUIDStateHandler
Icons[MESSAGES.GUID_CHANGE_BENCHED] = IconGUIDStateHandler

-- ------------------------------------------------------------------
-- Display group handling
-- ------------------------------------------------------------------
Icons[MESSAGES.DISPLAY_TEXT_GROUP_ADD] = function(self, msg, child, OnEnter, OnLeave, OnMouseDown, OnMouseUp, OnMouseWheel)
	local icon = self[child]
	if icon then
		if OnEnter then Elements:RegisterMouse(icon, "OnEnter", OnEnter) end
		if OnLeave then Elements:RegisterMouse(icon, "OnLeave", OnLeave) end
		if OnMouseDown then Elements:RegisterMouse(icon, "OnMouseDown", OnMouseDown) end
		if OnMouseUp then Elements:RegisterMouse(icon, "OnMouseUp", OnMouseUp) end
		if OnMouseWheel then Elements:RegisterMouse(icon, "OnMouseWheel", OnMouseWheel) end
	end
end

Icons[MESSAGES.DISPLAY_TEXT_GROUP_REMOVE] = function(self, msg, child, OnEnter, OnLeave, OnMouseDown, OnMouseUp, OnMouseWheel)
	local icon = self[child]
	if icon then
		Elements:UnregisterMouse(icon, "OnEnter", OnEnter)
		Elements:UnregisterMouse(icon, "OnLeave", OnLeave)
		Elements:UnregisterMouse(icon, "OnMouseDown", OnMouseDown)
		Elements:UnregisterMouse(icon, "OnMouseUp", OnMouseUp)
		Elements:UnregisterMouse(icon, "OnMouseWheel", OnMouseWheel)
	end
end
