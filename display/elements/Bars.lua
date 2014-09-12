
local wipe, select, next, type, insert, remove, inf
	= wipe, select, next, type, table.insert, table.remove, math.huge
local GetSpellInfo, GetTime, UIParent
	= GetSpellInfo, GetTime, UIParent

local addon = Overseer
local LSM = LibStub("LibSharedMedia-3.0")
local LCB = LibStub("LibCandyBar-3.0")

local consts = addon.consts
local append = addon.TableAppend
local Cooldowns = addon.Cooldowns
local GUIDName = addon.GUIDName
local GUIDClassColorRGB = addon.GUIDClassColorRGB
local GUIDClassColoredName = addon.GUIDClassColoredName

local MESSAGES = consts.MESSAGES
local MEDIA_TYPES = LSM.MediaType

local DEFAULTS = {
	-- keys to save default bar data
	-- candybar doesn't actually reset all the things as it claims..
	-- (not doing this can mess with others who use candybar - like bigwigs)
	BAR_ORIENTATION = "BAR_ORIENTATION",
	BAR_ROTATE = "BAR_ROTATE",
	
	LABEL_NUM_POINTS = "LABEL_NUM_POINTS",
	LABEL_POINT = "LABEL_POINT",
	LABEL_RELFRAME = "LABEL_RELFRAME",
	LABEL_RELPOINT = "LABEL_RELPOINT",
	LABEL_XOFF = "LABEL_XOFF",
	LABEL_YOFF = "LABEL_YOFF",
	
	DURATION_NUM_POINTS = "DURATION_NUM_POINTS",
	DURATION_POINT = "DURATION_POINT",
	DURATION_RELFRAME = "DURATION_RELFRAME",
	DURATION_RELPOINT = "DURATION_RELPOINT",
	DURATION_XOFF = "DURATION_XOFF",
	DURATION_YOFF = "DURATION_YOFF",
}

local _DEBUG_BARS = true
local _DEBUG_BARS_PREFIX = "|cff66cc66BARS|r"

local RemoveOnUpdate

-- ------------------------------------------------------------------
-- Bar data structures
-- ------------------------------------------------------------------
local Bars = {
	--[[
	stores active bar elements
	not keyed by spellCD because
		1. separating display elements from core representation makes for a more robust display system
		2. #bars per display lookup becomes negligible
	
	form:
	[display] = { -- sorted by expiration time
		candybar, -- first to expire
		candybar, -- second to expire
		...,
		candybar  -- N-th to expire
	},
	...
	--]]
}

local Elements = addon.DisplayElements
Elements:Register(Bars, 3)

Bars.RegisterMessage = addon.RegisterMessage
Bars.UnregisterMessage = addon.UnregisterMessage
function Bars:Initialize()
    self:RegisterMessage(MESSAGES.OPT_BARS_UPDATE, MESSAGES.OPT_BARS_UPDATE)
end

function Bars:Shutdown()
    self:UnregisterMessage(MESSAGES.OPT_BARS_UPDATE)
end

-- ------------------------------------------------------------------
-- Candybar default restoration
-- ------------------------------------------------------------------
local function Set(bar, key, data)
	-- bar:Set sometimes fails..? libcandybar proving less useful than expected
	-- TODO? maybe a custom bar class would be better.. (wouldn't have to worry about saving/restoring defaults)
	if bar and not bar[key] then
		bar[key] = data
	end
end

local function Get(bar, key) -- TODO? custom bars
	local data
	if bar and bar[key] then
		data = bar[key]
		bar[key] = nil
	end
	return data
end

local function CacheDefaultBarSettings(bar)
	if bar and not bar.defaultsCached then
		bar.defaultsCached = true
	
		local statusbar = bar.candyBarBar
		local label = bar.candyBarLabel
		local duration = bar.candyBarDuration

		Set(bar, DEFAULTS.BAR_ORIENTATION, statusbar:GetOrientation())
		Set(bar, DEFAULTS.BAR_ROTATE, statusbar:GetRotatesTexture())
		
		Set(bar, DEFAULTS.LABEL_NUM_POINTS, label:GetNumPoints())
		Set(bar, DEFAULTS.DURATION_NUM_POINTS, duration:GetNumPoints())
		for i = 1, label:GetNumPoints() do
			local point, relFrame, relPoint, xOff, yOff = label:GetPoint(i)
			Set(bar, ("%s%d"):format(DEFAULTS.LABEL_POINT, i), point)
			Set(bar, ("%s%d"):format(DEFAULTS.LABEL_RELFRAME, i), relFrame)
			Set(bar, ("%s%d"):format(DEFAULTS.LABEL_RELPOINT, i), relPoint)
			Set(bar, ("%s%d"):format(DEFAULTS.LABEL_XOFF, i), xOff)
			Set(bar, ("%s%d"):format(DEFAULTS.LABEL_YOFF, i), yOff)
		end
		for i = 1, duration:GetNumPoints() do
			local point, relFrame, relPoint, xOff, yOff = duration:GetPoint(i)
			Set(bar, ("%s%d"):format(DEFAULTS.DURATION_POINT, i), point)
			Set(bar, ("%s%d"):format(DEFAULTS.DURATION_RELFRAME, i), relFrame)
			Set(bar, ("%s%d"):format(DEFAULTS.DURATION_RELPOINT, i), relPoint)
			Set(bar, ("%s%d"):format(DEFAULTS.DURATION_XOFF, i), xOff)
			Set(bar, ("%s%d"):format(DEFAULTS.DURATION_YOFF, i), yOff)
		end
	end
end

local function RestoreDefaultBarSettings(bar)
	if bar and bar.defaultsCached then
		bar.defaultsCached = nil
	
		local numPoints
		local statusbar = bar.candyBarBar
		local label = bar.candyBarLabel
		local duration = bar.candyBarDuration

		statusbar:SetOrientation(Get(bar, DEFAULTS.BAR_ORIENTATION))
		statusbar:SetRotatesTexture(Get(bar, DEFAULTS.BAR_ROTATE))
		
		label:ClearAllPoints()
		numPoints = Get(bar, DEFAULTS.LABEL_NUM_POINTS)
		for i = 1, numPoints do
			local point = Get(bar, ("%s%d"):format(DEFAULTS.LABEL_POINT, i))
			local relFrame = Get(bar, ("%s%d"):format(DEFAULTS.LABEL_RELFRAME, i))
			local relPoint = Get(bar, ("%s%d"):format(DEFAULTS.LABEL_RELPOINT, i))
			local xOff = Get(bar, ("%s%d"):format(DEFAULTS.LABEL_XOFF, i))
			local yOff = Get(bar, ("%s%d"):format(DEFAULTS.LABEL_YOFF, i))
			label:SetPoint(point, relFrame, relPoint, xOff, yOff)
		end
		
		duration:ClearAllPoints()
		numPoints = Get(bar, DEFAULTS.DURATION_NUM_POINTS)
		for i = 1, numPoints do
			local point = Get(bar, ("%s%d"):format(DEFAULTS.DURATION_POINT, i))
			local relFrame = Get(bar, ("%s%d"):format(DEFAULTS.DURATION_RELFRAME, i))
			local relPoint = Get(bar, ("%s%d"):format(DEFAULTS.DURATION_RELPOINT, i))
			local xOff = Get(bar, ("%s%d"):format(DEFAULTS.DURATION_XOFF, i))
			local yOff = Get(bar, ("%s%d"):format(DEFAULTS.DURATION_YOFF, i))
			duration:SetPoint(point, relFrame, relPoint, xOff, yOff)
		end
	end
end

-- ------------------------------------------------------------------
-- OnDelete
-- ------------------------------------------------------------------
local points = {}
local function ShiftBars(db, display, against, startPos)
	-- shift all bars either with or against the specified growth direction
	local displayBars = Bars[display]
	if displayBars then
		local xShift, yShift = 0, 0
		local xOffset, yOffset = db.bar.x, db.bar.y
		local horizontal = db.bar.width + db.bar.spacing
		local vertical = db.bar.height + db.bar.spacing
		local grow = db.bar.grow
		
		-- left = (-), right = (+), up = (+), down = (-)
		if grow == "LEFT" then
			xShift = against and horizontal or -horizontal
		elseif grow == "RIGHT" then
			xShift = against and -horizontal or horizontal
		elseif grow == "TOP" then
			yShift = against and -vertical or vertical
		elseif grow == "BOTTOM" then
			yShift = against and vertical or -vertical
		end
		
		startPos = startPos or 1 -- optionally, start the 'startPos'-th bar for the display
		for i = startPos, #displayBars do
			local candy = displayBars[i]
			
			wipe(points)
			-- 1st pass: cache all the current points for this bar
			local numPoints = candy:GetNumPoints()
			for i = 1, numPoints do
				local pt, rel, relPt, xOff, yOff = candy:GetPoint(i)
				append(points, pt)
				append(points, rel)
				append(points, relPt)
				append(points, xOff)
				append(points, yOff)
			end
			
			-- 2nd pass: shift the bar in the appropriate direction
			candy:ClearAllPoints()
			for i = 1, #points, 5 do
				local pt = points[i]
				local rel = points[i+1]
				local relPt = points[i+2]
				local xOff = points[i+3]
				local yOff = points[i+4]
				
				xOff = xOff + xShift + xOffset
				yOff = yOff + yShift + yOffset
				candy:SetPoint(pt, rel, relPt, xOff, yOff)
			end
		end
	end
end

local LCB_STOP_MSG = "LibCandyBar_Stop"
Bars[LCB_STOP_MSG] = function(self, msg, bar)
	local spellCD, display = bar.currentSpellCD, bar.display
	if spellCD and display then
		local idx -- find the index to remove
		if Bars[display] then
			for i = 1, #Bars[display] do
				if bar == Bars[display][i] then
					idx = i
					break
				end
			end
		end
		
		if idx then
			if _DEBUG_BARS then
				addon:DEBUG("%s> Handling bar:Stop() for %s", _DEBUG_BARS_PREFIX, tostring(spellCD))
			end
		
			remove(Bars[display], idx)
			bar.display = nil
			bar.currentSpellCD = nil
			
			RestoreDefaultBarSettings(bar)
			bar:ClearAllPoints()
			bar:SetParent(UIParent)
			
			-- reposition any remaining bars for this display
			local db = addon.db:GetDisplaySettings(spellCD.spellid)
			if db.bar.limit ~= 1 then -- shortcut out if the display can only has a single bar
				local shortestCD
				local durationShown = db.bar.duration.shown
				local showOnlyFirst = db.bar.duration.showOnlyFirst
				
				-- shift the bars against the growth direction
				ShiftBars(db, display, true)
				
				local displayBars = Bars[display]
				for i = 1, #displayBars do
					local candy = displayBars[i]
					
					-- get the shortest cd to see if we need to show the duration
					-- note: the set of displayed spellids and the set of cooldowns considered by Cooldowns:GetFirstOnCD(spellid) may differ
					-- 		(depending on whether the display reprents multiple spellids or not)
					if durationShown and showOnlyFirst then
						local candyBar = candy.candyBarBar
						local candyValue = candyBar:GetValue()
						local shortestBar = shortestCD and shortestCD.candyBarBar
						local shortestValue = shortestBar and shortestBar:GetValue() or (candy.fill and 0 or select(2, candyBar:GetMinMaxValues()))
						if candy.fill then
							shortestCD = candyValue > shortestValue and candy or shortestCD
						else
							shortestCD = candyValue < shortestValue and candy or shortestCD
						end
					end
				end
				
				-- unless all bars are dying for some reason, the bar that was just stopped _should_ be the one that was first on cd
				if durationShown and showOnlyFirst and shortestCD then
					-- we only need to flip the visibility on if it wasn't before
					-- so the 'not showOnlyFirst' case does not need to be considered here -- it was handled when the bar was started
					shortestCD:SetTimeVisibility(true)
				end
			end
		else
			if _DEBUG_BARS then
				addon:DEBUG("%s> FAILED TO HANDLE :Stop(%s) - Could not find index!", _DEBUG_BARS_PREFIX, tostring(spellCD))
				if Bars[display] then
					addon:DEBUG("-- Bars for this display:")
					for i = 1, #Bars[display] do
						local bar = Bars[display][i]
						if bar.currentSpellCD then
							addon:DEBUG("   >%s", tostring(bar.currentSpellCD))
						end
					end
					addon:DEBUG("--======================")
				end
			end
		end
	end
end
do -- register against libcandybar's :Stop message (must be done after the handler is defined)
	LCB.RegisterCallback(Bars, LCB_STOP_MSG)
end

local function FindBar(spellCD, display)
	local bar, idx
	local displayBars = Bars[display]
	if displayBars then
		for i = 1, #displayBars do
			local candy = displayBars[i]
			if spellCD == candy.currentSpellCD then
				idx = i
				bar = candy
				break
			end
		end
	end
	return bar, idx
end

Bars[MESSAGES.DISPLAY_DELETE] = function(self, msg, spellCD, display)
	local bar = FindBar(spellCD, display)
	if bar then
		bar:Stop()
	end
end

-- ------------------------------------------------------------------
-- OnModify
-- ------------------------------------------------------------------
--[[ OLD.. TODO? update colors?
Bars[MESSAGES.DISPLAY_MODIFY] = function(self, msg, spellCD, display)
	local bar = FindBar(spellCD, display)
	if bar then
		bar:Stop()
	end
end
--]]

-- ------------------------------------------------------------------
-- Bar creation (ie, bar:Start())
-- ------------------------------------------------------------------
local function GetColorFromDB(colorDB, spellCD)
	local r,g,b,a
	if colorDB.useClassColor then
		r, g, b, a = GUIDClassColorRGB(spellCD.guid)
	else
		-- TODO: this is sloppy (this function is not solely for fonts, yet it defaults to font settings)
		r = addon.db:LookupFont(colorDB, spellCD.spellid, "r")
		g = addon.db:LookupFont(colorDB, spellCD.spellid, "g")
		b = addon.db:LookupFont(colorDB, spellCD.spellid, "b")
		a = addon.db:LookupFont(colorDB, spellCD.spellid, "a")
	end
	return r, g, b, a
end

local function GetFontShadowColorFromDB(shadowDB, spellCD)
	local r, g, b, a = 0, 0, 0, 0
	if addon.db:LookupFont(shadowDB, spellCD.spellid, "shadow") then
		r = addon.db:LookupFont(shadowDB, spellCD.spellid, "shadowR")
		g = addon.db:LookupFont(shadowDB, spellCD.spellid, "shadowG")
		b = addon.db:LookupFont(shadowDB, spellCD.spellid, "shadowB")
		a = addon.db:LookupFont(shadowDB, spellCD.spellid, "shadowA")
	end
	return r, g, b, a
end

local function OnBarUpdate(bar)
	local spellCD = bar.currentSpellCD
	if spellCD then
		local statusbar = bar.candyBarBar
		local orientation = statusbar:GetOrientation()
		local duration = bar.candyBarDuration
		local cur = statusbar:GetValue()
		local max = select(2, statusbar:GetMinMaxValues())
		local percentDone = cur / max
		
		-- move the duration text with the current value of the bar
		local db = addon.db:GetDisplaySettings(spellCD.spellid)
		local point, rel, relPoint, xOff, yOff = duration:GetPoint()
		duration:ClearAllPoints()
		if orientation == "VERTICAL" then
			local height = statusbar:GetHeight()
			yOff = (percentDone * height) + db.bar.duration.y
			relPoint = "BOTTOM"
		else
			local width = statusbar:GetWidth()
			xOff = (percentDone * width) + db.bar.duration.x
			relPoint = "LEFT"
		end
		duration:SetPoint(point, rel, relPoint, xOff, yOff)
		
		-- TODO: text emphasis (size/color) - smooth gradient & (or?) snap to size/color
	else
		local msg = "OnBarUpdate(%s) - bar is missing cached spell.."
		addon:ERROR(msg, tostring(spellCD)) -- TODO: change to :DEBUG
		
		-- kill this onUpdate func to avoid spamming further
		-- TODO? TMP?
        RemoveOnUpdate(bar)
	end
end

--[[local]] function RemoveOnUpdate(bar)
    if bar.funcs then
        local idx
        for i = 1, #bar.funcs do
            local updateFunc = bar.funcs[i] 
            if updateFunc == OnBarUpdate then
                idx = i
                break
            end
        end
        if idx then
            remove(bar.funcs, idx)
        end
    end
end

local function GetNumBarsRunning(display)
	local displayBars = Bars[display]
	return type(displayBars) == "table" and #displayBars or 0
end

local function SetIcon(bar, spellCD)
	local db = addon.db:GetDisplaySettings(spellCD.spellid)
	if db.bar.iconShown then
		local oldIcon = bar.candyBarIconFrame.icon
		local newIcon = select(3, GetSpellInfo(spellCD.spellid))
		if oldIcon ~= newIcon then
			bar:SetIcon(newIcon)
		end
	end
end

local function ApplySettings(bar, spellCD)
	local db = addon.db:GetDisplaySettings(spellCD.spellid)
    
	local barDB = db.bar
	local texture = LSM:Fetch(MEDIA_TYPES.STATUSBAR, barDB.texture)
	local width = barDB.width
	local height = barDB.height
	local orientation = barDB.orientation
	local statusbar = bar.candyBarBar
	local label = bar.candyBarLabel
	local duration = bar.candyBarDuration
    
    bar.width = width -- TODO: change this when switching away from libCandyBar
    bar.height = height -- TODO: ^ (these only exist because they are flagged in libCandyBar)
    bar:SetSize(width, height)
	
	-- modify the statusbar
	statusbar:SetStatusBarTexture(texture)
	statusbar:SetOrientation(orientation)
	statusbar:SetRotatesTexture(orientation == "VERTICAL" and true or false)
	
    -- modify the background
    local r,g,b,a = GetColorFromDB(barDB.bg, spellCD)
    a = a == 1 and 0.5 or a
    local background = bar.candyBarBackground
	background:SetTexture(texture)
	background:SetVertexColor(r, g, b, a)
	
	-- modify the fonts
	local point, relPoint
	if barDB.label.shown then
		local labelDB = barDB.label
		local labelFont = addon.db:LookupFont(labelDB, spellCD.spellid, "font")
		local labelSize = addon.db:LookupFont(labelDB, spellCD.spellid, "size")
		local labelFlags = addon.db:LookupFont(labelDB, spellCD.spellid, "flags")
		
		label:SetFont(LSM:Fetch(MEDIA_TYPES.FONT, labelFont), labelSize, labelFlags)
		label:SetTextColor(GetColorFromDB(labelDB, spellCD))
		label:SetJustifyH(addon.db:LookupFont(labelDB, spellCD.spellid, "justifyH"))
		label:SetJustifyV(addon.db:LookupFont(labelDB, spellCD.spellid, "justifyV"))
        local sa = addon.db:LookupFont(labelDB, spellCD.spellid, "shadow") and 1 or 0
        label:SetShadowColor(0, 0, 0, sa)
        label:SetShadowOffset(1, -1)
		if orientation == "VERTICAL" then
			point = labelDB.point or "LEFT"
			relPoint = labelDB.relPoint or "CENTER"
		else
			point = labelDB.point or "BOTTOMLEFT"
			relPoint = labelDB.relPoint or "TOPLEFT"
		end
		label:ClearAllPoints()
		label:SetPoint(point, statusbar, relPoint, labelDB.x, labelDB.y)
        
        -- show label
		local useClassColor = barDB.label.useClassColor
		-- TODO: parse text? show spellname instead? ..the user needs to be able to set this text
        local spellCD = bar.currentSpellCD
		bar:SetLabel(useClassColor and GUIDClassColoredName(spellCD.guid) or GUIDName(spellCD.guid))
    else
        bar:SetLabel()
	end
    
	if barDB.duration.shown then
		local durationDB = barDB.duration
		local durationFont = addon.db:LookupFont(durationDB, spellCD.spellid, "font")
		local durationSize = addon.db:LookupFont(durationDB, spellCD.spellid, "size")
		local durationFlags = addon.db:LookupFont(durationDB, spellCD.spellid, "flags")
		
		duration:SetFont(LSM:Fetch(MEDIA_TYPES.FONT, durationFont), durationSize, durationFlags)
		duration:SetTextColor(GetColorFromDB(durationDB, spellCD))
		duration:SetJustifyH(addon.db:LookupFont(durationDB, spellCD.spellid, "justifyH"))
		duration:SetJustifyH(addon.db:LookupFont(durationDB, spellCD.spellid, "justifyV"))
        local sa = addon.db:LookupFont(durationDB, spellCD.spellid, "shadow") and 1 or 0
        duration:SetShadowColor(0, 0, 0, sa)
        duration:SetShadowOffset(1, -1)
		if orientation == "VERTICAL" then
			point = durationDB.point or "CENTER"
			relPoint = durationDB.relPoint or "TOP"
		else
			point = durationDB.point or "LEFT"
			relPoint = durationDB.relPoint or "RIGHT"
		end
		duration:ClearAllPoints()
		duration:SetPoint(point, statusbar, relPoint, durationDB.x, durationDB.y)
		if durationDB.movesWithBar then
			bar:AddUpdateFunction(OnBarUpdate)
		end
	end
    if not barDB.duration.movesWithBar then
        RemoveOnUpdate(bar)
    end
    
	-- show/hide duration
	local numBarsRunning = GetNumBarsRunning(bar.display)
	local showOnlyFirst = barDB.duration.showOnlyFirst
	local showDuration = barDB.duration.shown and (not showOnlyFirst or (showOnlyFirst and numBarsRunning == 1))
	bar:SetTimeVisibility(showDuration)
    
    SetIcon(bar, spellCD)
end

--[[
    TODO: always shown bars can probably GetBar => :Show() and call :Start() when needed 
            the :Stop() handler needs to re - GetBar() => :Show()
--]]
local function GetBar(spellCD, display)
	local db = addon.db:GetDisplaySettings(spellCD.spellid)
	local numBarsRunning = GetNumBarsRunning(display)
	if db.bar.limit > 0 and numBarsRunning + 1 > db.bar.limit then
		-- spawning a new bar would exceed the alotted number of concurrent bars
		if _DEBUG_BARS then
			addon:DEBUG("%s> GetBar(%s): No empty bar slot!", _DEBUG_BARS_PREFIX, tostring(spellCD))
		end
		return nil
	end
	
	local barDB = db.bar
	local texture = barDB.texture
	local width = barDB.width
	local height = barDB.height
	local bar = LCB:New(LSM:Fetch(MEDIA_TYPES.STATUSBAR, texture), width, height) -- TODO: these are all set again in 'ApplySettings'..
	
	-- store some extra state on the bar
	bar.display = display
	bar.currentSpellCD = spellCD
	-- keep a reference to the bar keyed by its parent display
	Bars[display] = Bars[display] or {}
	local idx
	for i = #Bars[display], 1, -1 do -- keep the list sorted by expiration time
		local candy = Bars[display][i]
		local spell = candy.currentSpellCD
		if spellCD:ExpirationTime() < spell:ExpirationTime() then
			-- find the position at which to insert
			idx = i
		else
			-- found it
			break
		end
	end
	if idx then
		insert(Bars[display], idx, bar)
	else
		insert(Bars[display], bar)
	end
    
	-- apply settings to the bar (must happen after inserting into the 'Bars' table so that 'GetNumBarsRunning' returns the correct value)
	CacheDefaultBarSettings(bar)
    ApplySettings(bar, spellCD)
    
	return bar
end

local function SetPosition(bar, display, posIdx)
    local db = addon.db:GetDisplaySettings(bar.currentSpellCD)
	local adjust = (db.icon.shown and db.bar.fitIcon) and db.bar.adjust or 0
	
	-- determine where to place the bar
	local numBarsRunning = posIdx or GetNumBarsRunning(display)
	xOff = db.bar.x
	yOff = db.bar.y
	if numBarsRunning > 1 then
		local grow = db.bar.grow
		if grow == "LEFT" then
			xOff = xOff - (numBarsRunning * (db.bar.width + db.bar.spacing))
		elseif grow == "RIGHT" then
			xOff = xOff + (numBarsRunning * (db.bar.width + db.bar.spacing))
		elseif grow == "TOP" then
			yOff = yOff + (numBarsRunning * (db.bar.height + db.bar.spacing))
		elseif grow == "BOTTOM" then
			yOff = yOff - (numBarsRunning * (db.bar.height + db.bar.spacing))
		end
	end
	
	-- TODO? animate ?
	local side = db.bar.side -- only really applies when 'fitIcon' is true, but should work regardless
	if side == "LEFT" then
		bar:SetPoint("TOPRIGHT", display, "TOPLEFT", xOff, yOff + adjust)
		bar:SetPoint("BOTTOMRIGHT", display, "BOTTOMLEFT", xOff, yOff - adjust)
	elseif side == "RIGHT" then
		bar:SetPoint("TOPLEFT", display, "TOPRIGHT", xOff, yOff + adjust)
		bar:SetPoint("BOTTOMLEFT", display, "BOTTOMRIGHT", xOff, yOff - adjust)
	elseif side == "TOP" then
		bar:SetPoint("BOTTOMLEFT", display, "TOPLEFT", xOff - adjust, yOff)
		bar:SetPoint("BOTTOMRIGHT", display, "TOPRIGHT", xOff + adjust, yOff)
	elseif side == "BOTTOM" then
		bar:SetPoint("TOPLEFT", display, "BOTTOMLEFT", xOff - adjust, yOff)
		bar:SetPoint("TOPRIGHT", display, "BOTTOMRIGHT", xOff + adjust, yOff)
	end
end

local function StartBar(bar, spellCD, display, duration, expire, posIdx)
	-- positioning
	bar:SetParent(display)
	bar:ClearAllPoints()
	SetPosition(bar, display, posIdx)
	
	-- set default values if not provided
	duration = duration or spellCD.duration
	expire = expire or spellCD:ExpirationTime()
	
	SetIcon(bar, spellCD)
	bar:SetDuration(duration)
	bar:Start()
	-- manually adjust the bar to fake as though it were always running
	-- (in case this bar is starting midway through its duration)
	local now = GetTime()
	local remaining = expire - now
	bar.start = bar.fill and expire - duration or remaining
	bar.exp = expire
	
	if _DEBUG_BARS then
        local numBarsRunning = GetNumBarsRunning(display)
		posIdx = posIdx or numBarsRunning
		addon:DEBUG("StartBar(%s): duration=%s, pos=%s, #running=%s", tostring(spellCD), duration, posIdx, numBarsRunning)
	end
end

local function StartCooldown(spellCD, display)
    local db = addon.db:GetDisplaySettings(spellCD.spellid)
    if db.bar.shown and db.bar.cooldown then
        local bar = GetBar(spellCD, display)
        if bar then
            local db = addon.db:GetDisplaySettings(spellCD.spellid)
            bar:SetColor(GetColorFromDB(db.bar.bar, spellCD))
            bar:SetFill(db.bar.fill)
            StartBar(bar, spellCD, display)
        end
	end
end

local function StartNextCooldown(display)
	local spell = addon:GetFirstToExpireSpell(display)
	if spell then
		StartCooldown(spell, display)
	end
end

local function StartBuffDurationCountdown(spellCD, display)
	local result -- true if a buff duration bar is started
	local db = addon.db:GetDisplaySettings(spellCD.spellid)
	if db.bar.shown and db.bar.showBuffDuration then
		local now = GetTime()
		local buffExpire = spellCD:BuffExpirationTime()
		
		if buffExpire > now then
			-- need to show a buff duration
			if _DEBUG_BARS then
				addon:DEBUG("%s> StartBuffDurationCountdown(%s)", _DEBUG_BARS_PREFIX, tostring(spellCD))
			end
			
			local bar = FindBar(spellCD, display)
			local numBarsRunning = GetNumBarsRunning(display)
			-- determine if an already running bar needs to be replaced
			if bar then
				-- stop an already existing bar for this spellCD instance (if there is one)
				bar:Stop()
			elseif db.bar.limit > 0 and numBarsRunning + 1 > db.bar.limit then
				-- about to spawn one-too-many bars
				-- stop the bar that is expiring last
				local displayBars = Bars[display]
				if displayBars then -- this check should not be necessary
					local lastBar = displayBars[#displayBars]
					lastBar:Stop()
				end
			end
		
			-- spawn a bar for the buff duration
			bar = GetBar(spellCD, display)
			if bar then
				-- push all other bars away from the icon (ie, toward the specified growth direction)
				-- bars should always be ordered as follows:
				-- 	1. active buff duration (this should only ever be a single bar)
				--	2. first to expire -> last to expire
				ShiftBars(db, display, false, 2)
				
				-- determine if buff bars use a different color
				local barColors = db.bar.bar
				local r,g,b,a
				if db.bar.bar.enableBuffColor then
					r, g, b, a = barColors.buffR, barColors.buffG, barColors.buffB, barColors.buffA
				else
					r, g, b, a = GetColorFromDB(barColors, spellCD)
				end
				if db.bar.duration.shown then
					-- TODO: option to set this color
					bar.candyBarDuration:SetTextColor(r, g, b, a)
				end
				bar:SetColor(r, g, b, a)
				bar:SetFill(not db.bar.fill) -- for the duration of the buff, make the bar go the opposite way
				StartBar(bar, spellCD, display, spellCD:BuffDuration(), buffExpire, 1)
				
				result = true
			elseif _DEBUG_BARS then
				-- this should never happen
				local msg = "%s> |cffFF0000FAILED|r to start a buff bar for %s!"
				addon:ERROR(msg, _DEBUG_BARS_PREFIX, tostring(spellCD)) -- TODO: change to :DEBUG
			end
		end
	end
	return result
end

-- ------------------------------------------------------------------
-- OnBuffExpire
-- ------------------------------------------------------------------
Bars[MESSAGES.DISPLAY_BUFF_EXPIRE] = function(self, msg, spellCD, display)
	local db = addon.db:GetDisplaySettings(spellCD.spellid)
	if db.bar.shown then
		-- it should be safe to :Stop any bar that exists for this spellCD instance
		-- if one DOES NOT exist, however, it may mean either:
		-- 1. the _BUFF_EXPIRE message fired _after_ the bar duration ended or
		-- 2. the triggering spellCD was overridden by another buff bar
		--[[
			eg, if Healing Tide Totem has a buff duration of 12s:
				0s,		Sabbie casts Healing Tide Totem
					=> start a buff bar with a duration of 12s
				+2s,	Becore casts HTT
					=> cancel the previous buff bar (with 10s remaining)
					=> show a new one (starting at 0s with a duration of 12s)
				+12s,	Sabbie's HTT triggers _BUFF_EXPIRE
					=> no display change should occur from this message
				+14s,	Becore's HTT expires throwing out another _BUFF_EXPIRE
					=> the currently displayed buff bar should either be ending or have already ended
					=> start a new bar displaying Sabbie's HTT cooldown
		--]]
		
		local bar = FindBar(spellCD, display)
		if bar then
			-- trust what core says over whatever display happens to be doing
			-- (core says the buff is expired, so update the display to reflect)
			if _DEBUG_BARS then
				addon:WARN("Bars[|cff999999EXPIRE|r](%s): |cffFF0000Bar found|r! Stopping.. (%.6fs remaining)", tostring(spellCD), bar.remaining)
			end
			bar:Stop()
		end
		
		-- TODO? shift remaining bars? not sure if it's needed any more (:Stop() msg handler should automatically handle it)
		
		local spell = addon:GetMostRecentBuffCastSpell(display)
		if spell then
			if _DEBUG_BARS then
				addon:WARN("Bars[|cff999999EXPIRE|r](%s): mostRecent=%s", tostring(spellCD), tostring(spell))
			end

			local mostRecentBar = FindBar(spell, display)
			if mostRecentBar then
				-- a bar is already displayed for the spell about to be shown..
                -- this can happen if the current bar overrode the spellCD whose buff just expired
				local msg = "%s> Attempting to start another buff bar for %s.."
				addon:ERROR(msg, _DEBUG_BARS_PREFIX, tostring(spell)) -- TODO: change to :DEBUG
			end
			
			-- boot up another buff duration bar (show an overridden buff bar that is still ticking)
			StartBuffDurationCountdown(spell, display)
		else
			-- otherwise, show the first queued spell
			if _DEBUG_BARS then
				addon:WARN("Bars[|cff999999EXPIRE|r](%s): starting first queued..", tostring(spellCD))
			end
			StartNextCooldown(display)
		end
	end
end

-- ------------------------------------------------------------------
-- OnUse
-- ------------------------------------------------------------------
Bars[MESSAGES.DISPLAY_USE] = function(self, msg, spellCD, display)
    addon:PRINT("%s: %s", msg, tostring(spellCD))
    -- try to start a buff duration bar
    if not StartBuffDurationCountdown(spellCD, display) then
        -- try to start a cooldown bar for this spellCD use
        local bar = FindBar(spellCD, display)
        if not bar then
            StartCooldown(spellCD, display)
            -- if a bar exists, another charge was used for this specific spellCD instance while a bar was actively running for it
            -- a spellCD instance can only have one cooldown running at a time, so showing another bar for it would
            -- be conveying the same cooldown information twice
        end
    end
end

-- ------------------------------------------------------------------
-- OnReady/Reset
-- ------------------------------------------------------------------
Bars[MESSAGES.DISPLAY_READY] = function(self, msg, spellCD, display)
	local bar = FindBar(spellCD, display)
	if bar then
		bar:Stop()
	end
	StartNextCooldown(display)
end

Bars[MESSAGES.DISPLAY_RESET] = Bars[MESSAGES.DISPLAY_READY]

-- ------------------------------------------------------------------
-- Handle when a specific spellCD is dropped from tracking
-- eg, disc priest respecs to shadow (loses pain sup, barrier)
-- ------------------------------------------------------------------
Bars[MESSAGES.DISPLAY_CD_LOST] = function(self, msg, spellCD, display)
	local bar = FindBar(spellCD, display)
	if bar then
		bar:Stop()
		StartNextCooldown(display)
	end
end

-- ------------------------------------------------------------------
-- Custom class color update
-- ------------------------------------------------------------------
Bars[MESSAGES.DISPLAY_COLOR_UPDATE] = function(self, msg, spellCD, display)
	local bar = FindBar(spellCD, display)
	if bar then
		local db = addon.db:GetDisplaySettings(spellCD.spellid)
		local barDB = db.bar
		
		bar:SetColor(GetColorFromDB(barDB.bar, spellCD))
        local r,g,b,a = GetColorFromDB(barDB.bg, spellCD)
        a = a == 1 and 0.5 or a
		bar.candyBarBackground:SetVertexColor(r, g, b, a)
		bar.candyBarLabel:SetTextColor(GetColorFromDB(barDB.label, spellCD))
		bar.candyBarDuration:SetTextColor(GetColorFromDB(barDB.duration, spellCD))
	end
end

-- TODO: show/hide bars of uncastable, etc?

-- ------------------------------------------------------------------
-- Options handling
-- ------------------------------------------------------------------
local DEFAULT_KEY = addon.db.DEFAULT_KEY
local function IsSetOfBars(display, displayBars)
    return type(display) == "table" and display.spells and type(displayBars) == "table"
end

Bars[MESSAGES.OPT_BARS_UPDATE] = function(self, msg, id)
    if id == DEFAULT_KEY then
        -- update all bars for all displays
        for display, displayBars in next, self do
            if IsSetOfBars(display, displayBars) then
                local spellCD = next(display.spells) -- spells which share a display should all have the same settings
                for i = 1, #displayBars do
                    local bar = displayBars[i]
                    ApplySettings(bar, spellCD)
                    -- TODO: .limit, .shown, .cooldown, .showBuffDuration, positioning/sizing (ie: 'SetPosition')
                end
            end
        end
    else
        local applied
        -- look for the specific display to update
        for display, displayBars in next, self do
            if IsSetOfBars(display, displayBars) then
                for spellCD in next, display.spells do
                    local consolidatedId = addon.db:GetConsolidatedKey(spellCD.spellid)
                    if id == spellCD.spellid or id == consolidatedId then
                        for i = 1, #displayBars do
                            local bar = displayBars[i]
                            ApplySettings(bar, spellCD)
                        end
                        
                        applied = true
                        break
                    end
                end
            end
            
            if applied then break end
        end
        
        if not applied then
            local debugMsg = "Icons:%s: No such icon for id='%s'"
            addon:DEBUG(debugMsg, msg, id)
        end
    end
end
