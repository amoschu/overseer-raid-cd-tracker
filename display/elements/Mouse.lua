
local wipe, next, type, tostring, floor
	= wipe, next, type, tostring, math.floor
local GetSpellInfo
	= GetSpellInfo

local addon = Overseer

local consts = addon.consts
local round = addon.Round
local GUIDClassColoredName = addon.GUIDClassColoredName
local Elements = addon.DisplayElements
local Cooldowns = addon.Cooldowns
local GroupCache = addon.GroupCache

local INDENT = consts.INDENT
local MIN_PER_HR = consts.MIN_PER_HR
local SEC_PER_MIN = consts.SEC_PER_MIN
local ONENTER = "OnEnter"
local ONLEAVE = "OnLeave"
local ONMOUSEDOWN = "OnMouseDown"
local ONMOUSEUP = "OnMouseUp"
local ONMOUSEWHEEL = "OnMouseWheel"
local SCALE = 0.92

local scriptCallbacksByWidget = {
	--[[
	list of callbacks by widget per script
	
	form:
	[widget] = {
		[function] = true,
		...
	},
	...
	--]]
	[ONENTER] = {},
	[ONLEAVE] = {},
	[ONMOUSEDOWN] = {},
	[ONMOUSEUP] = {},
	[ONMOUSEWHEEL] = {},
}
local MouseHandler = {}

local cacheKeyX = "_%s%dX"
local cacheKeyY = "_%s%dY"
local points = {} -- work table to store all the points of the widget between passes
local function Shrink(widget, key)
	-- first pass, grab all previous points
	local numPoints = widget:GetNumPoints()
	for i = 1, numPoints do
		local pt, rel, relPt, x, y = widget:GetPoint(i)
		widget[cacheKeyX:format(key, i)] = x
		widget[cacheKeyY:format(key, i)] = y
		
		local pointNum = 5 * (i - 1)
		points[i + pointNum] = pt
		points[i+1 + pointNum] = rel
		points[i+2 + pointNum] = relPt
		points[i+3 + pointNum] = x
		points[i+4 + pointNum] = y
	end
	
	local width, height = widget:GetSize()
	width = width * (1 - SCALE)
	height = height * (1 - SCALE)
	
	-- second pass, shrink relative to original points
	widget:ClearAllPoints()
	for i = 1, numPoints do
		local pointNum = 5 * (i - 1)
		local pt = points[i + pointNum]
		local rel = points[i+1 + pointNum]
		local relPt = points[i+2 + pointNum]
		local x = points[i+3 + pointNum]
		local y = points[i+4 + pointNum]
		
		if pt:find("LEFT") then
			x = x + width
		elseif pt:find("RIGHT") then
			x = x - width
		end
		if pt:find("TOP") then
			y = y - height
		elseif pt:find("BOTTOM") then
			y = y + height
		end
		widget:SetPoint(pt, rel, relPt, x, y)
	end
	
	wipe(points)
end

local function Unshrink(widget, key)
	-- first pass, grab originals
	local numPoints = widget:GetNumPoints()
	for i = 1, numPoints do
		local pt, rel, relPt = widget:GetPoint(i)
		
		local pointNum = 3 * (i - 1)
		points[i + pointNum] = pt
		points[i+1 + pointNum] = rel
		points[i+2 + pointNum] = relPt
	end
	
	-- second pass, expand
	widget:ClearAllPoints()
	for i = 1, numPoints do
		local pointNum = 3 * (i - 1)
		local pt = points[i + pointNum]
		local rel = points[i+1 + pointNum]
		local relPt = points[i+2 + pointNum]
		local x = widget[cacheKeyX:format(key, i)]
		local y = widget[cacheKeyY:format(key, i)]
		
		widget:SetPoint(pt, rel, relPt, x, y)
		widget[cacheKeyX:format(key, i)] = nil
		widget[cacheKeyY:format(key, i)] = nil
	end
	
	wipe(points)
end

local function TransferCachedPoints(widget, fromKey, toKey)
	local numPoints = widget:GetNumPoints()
	for i = 1, numPoints do
		widget[cacheKeyX:format(toKey, i)] = widget[cacheKeyX:format(fromKey, i)]
		widget[cacheKeyY:format(toKey, i)] = widget[cacheKeyY:format(fromKey, i)]
		widget[cacheKeyX:format(fromKey, i)] = nil
		widget[cacheKeyY:format(fromKey, i)] =  nil
	end
end

local function ModifyHitRect(widget, originalWidth, originalHeight)
	local w, h = widget:GetSize()
	local lr = floor(originalWidth - w) -- left/right insets
	local tb = floor(originalHeight - h) -- top/bottom insets
	
	-- TODO: this may be off by a pixel? (due to rounding)
	widget:SetHitRectInsets(-lr, -lr, -tb, -tb)
end

-- clear any cached feedback state the module added to the widget
local function ClearAllFeedback(widget)
	widget._enter = nil
	widget._reEnter = nil
	widget._down = nil
	widget._wheel = nil
	widget._lastUpTime = nil
	
	widget._enterWidth, widget._enterHeight = nil, nil
	widget._downWidth, widget._downHeight = nil, nil
	widget._wheelWidth, widget._wheelHeight = nil, nil
	
	-- TODO: this may leave the widget in a different state if Clear() is somehow called before the corresponding end event is run
	local numPoints = widget:GetNumPoints()
	for i = 1, numPoints do
		widget[cacheKeyX:format(ONENTER, i)] = nil
		widget[cacheKeyY:format(ONENTER, i)] = nil
		
		widget[cacheKeyX:format(ONMOUSEDOWN, i)] = nil
		widget[cacheKeyY:format(ONMOUSEDOWN, i)] = nil
		
		widget[cacheKeyX:format(ONMOUSEWHEEL, i)] = nil
		widget[cacheKeyY:format(ONMOUSEWHEEL, i)] = nil
	end
end

local function DoMouseFeedback(widget)
	local display = widget:GetParent()
	local spellCD = next(display.spells)
	local db = addon.db:GetDisplaySettings(spellCD.spellid)
	return db.mouseFeedback
end

-- ------------------------------------------------------------------
-- OnMouseEnter
-- ------------------------------------------------------------------
MouseHandler[ONENTER] = function(widget, motion)
	-- enter/leave feedback in addition to click/wheel feedback feels like overkill
	--	(commented out in case I change my mind at some point)
	--[[
	if DoMouseFeedback(widget) then
		if widget._down then
			-- left -> re-entered region while mousedown (mousedown can only happen if onenter)
			widget._reEnter = true
		elseif not widget._enter then
			widget._enter = true
			
			widget._enterWidth, widget._enterHeight = widget:GetSize()
			Shrink(widget, ONENTER)
			ModifyHitRect(widget, widget._enterWidth, widget._enterHeight)
		end
	end
	--]]
	
	local callbacks = scriptCallbacksByWidget[ONENTER][widget]
	if callbacks then
		for func in next, callbacks do
			func(ONENTER, widget, motion)
		end
	end
end

-- ------------------------------------------------------------------
-- OnMouseLeave
-- ------------------------------------------------------------------
MouseHandler[ONLEAVE] = function(widget, motion)
	--[[
	if widget._enter and DoMouseFeedback(widget) then
		widget._enter = nil
		
		if widget._down then
			-- mouse left region while button down
			widget._downWidth = widget._enterWidth
			widget._downHeight = widget._enterHeight
			TransferCachedPoints(widget, ONENTER, ONMOUSEDOWN)
		elseif widget._enterWidth > widget:GetWidth() and widget._enterHeight > widget:GetHeight() then
			-- don't ever size down on end events
			Unshrink(widget, ONENTER)
			ModifyHitRect(widget, widget._enterWidth, widget._enterHeight)
		end
		widget._enterWidth = nil
		widget._enterHeight = nil
	end
	--]]
	
	local callbacks = scriptCallbacksByWidget[ONLEAVE][widget]
	if callbacks then
		for func in next, callbacks do
			func(ONLEAVE, widget, motion)
		end
	end
end

-- ------------------------------------------------------------------
-- OnMouseDown
-- ------------------------------------------------------------------
MouseHandler[ONMOUSEDOWN] = function(widget, btn)
	if not widget._down and DoMouseFeedback(widget) then
		widget._down = true
		widget._downWidth, widget._downHeight = widget:GetSize()
		
		Shrink(widget, ONMOUSEDOWN)
		ModifyHitRect(widget, widget._downWidth, widget._downHeight)
	end
	
	local callbacks = scriptCallbacksByWidget[ONMOUSEDOWN][widget]
	if callbacks then
		for func in next, callbacks do
			func(ONMOUSEDOWN, widget, btn)
		end
	end
end

-- ------------------------------------------------------------------
-- OnMouseUp
-- ------------------------------------------------------------------
MouseHandler[ONMOUSEUP] = function(widget, btn)
	if widget._down and DoMouseFeedback(widget) then
		widget._down = nil
		
		if widget._downWidth > widget:GetWidth() and widget._downHeight > widget:GetHeight() then
			-- don't shrink if the widget somehow expanded
			Unshrink(widget, ONMOUSEDOWN)
			ModifyHitRect(widget, widget._downWidth, widget._downHeight)
		end
		widget._downWidth = nil
		widget._downHeight = nil
		
		if widget._reEnter then
			widget._reEnter = nil
			-- the mouse left->reentered the region all while mousedown
			-- fake an OnEnter event
			MouseHandler[ONENTER](widget, true)
		end
	end
	
	if widget:IsMouseOver(2, -2, -2, 2) then
		local callbacks = scriptCallbacksByWidget[ONMOUSEUP][widget]
		if callbacks then
			for func in next, callbacks do
				func(ONMOUSEUP, widget, btn)
			end
		end
	end
end

-- ------------------------------------------------------------------
-- OnMouseWheel
-- ------------------------------------------------------------------
local function UndoMWheelFeedback(widget)
	if widget._wheel and DoMouseFeedback(widget) then
		widget._wheel = nil
		
		if widget._wheelWidth > widget:GetWidth() and widget._wheelHeight > widget:GetHeight() then
			Unshrink(widget, ONMOUSEWHEEL)
			ModifyHitRect(widget, widget._wheelWidth, widget._wheelHeight)
		end
		widget._wheelWidth = nil
		widget._wheelHeight = nil
	end
end

local MWHEEL_SCALE = 0.84
local MWHEEL_FEEDBACK_INTERVAL = 0.12
MouseHandler[ONMOUSEWHEEL] = function(widget, delta)
	if not widget._wheel and DoMouseFeedback(widget) then
		widget._wheel = true
		widget._wheelWidth, widget._wheelHeight = widget:GetSize()
		
		Shrink(widget, ONMOUSEWHEEL)
		ModifyHitRect(widget, widget._wheelWidth, widget._wheelHeight)
		addon:ScheduleTimer(UndoMWheelFeedback, MWHEEL_FEEDBACK_INTERVAL, widget)
	end
	
	local callbacks = scriptCallbacksByWidget[ONMOUSEWHEEL][widget]
	if callbacks then
		for func in next, callbacks do
			func(ONMOUSEWHEEL, widget, delta)
		end
	end
end

-- ------------------------------------------------------------------
-- Un/register
-- ------------------------------------------------------------------
local numMouseScripts = {
	--[[
	keeps track of the number of distinct mouse events that have been registered for the keyed widget
	
	form:
	[widget] = uint,
	[widget] = uint,
	...
	--]]
}

local function IsValidWidget(widget)
	return type(widget) == "table" and type(widget.EnableMouse) == "function" and type(widget.GetScript) == "function"
end

function Elements:RegisterMouse(widget, script, scriptCallback)
	if IsValidWidget(widget) then
		if type(scriptCallback) == "function" then
			if not widget:GetScript(script) then
				if type(MouseHandler[script]) == "function" then
					local num = numMouseScripts[widget] or 0
					numMouseScripts[widget] = num + 1
                    -- TODO? ensure the corresponding start/end script is registered for feedback purposes?
					widget:SetScript(script, MouseHandler[script])
				else
					local msg = "Elements:RegisterMouse(%s): no handler for script '%s'"
					addon:Debug(msg:format(tostring(script)))
				end
			end
			local callbacks = scriptCallbacksByWidget[script]
			callbacks[widget] = callbacks[widget] or {}
			callbacks[widget][scriptCallback] = true
		else
			local msg = "Elements:RegisterMouse(%s) - 'scriptCallback' must be a function (type=%s)"
			addon:Debug(msg:format(tostring(script), type(scriptCallback)))
		end
	else
		local msg = "Elements:RegisterMouse(%s) - 'widget' cannot be registered for mouse scripts (type=%s)"
		addon:Debug(msg:format(tostring(script), type(widget)))
	end
end

function Elements:UnregisterMouse(widget, script, scriptCallback)
	if IsValidWidget(widget) then
		if widget:GetScript(script) then
			if type(MouseHandler[script]) == "function" then
				numMouseScripts[widget] = numMouseScripts[widget] - 1
				if numMouseScripts[widget] == 0 then
					widget:EnableMouse(false)
					ClearAllFeedback(widget)
				end
				if script == ONMOUSEWHEEL then
					widget:EnableMouseWheel(false)
				end
				widget:SetScript(script, nil)
			else
				local msg = "Elements:UnregisterMouse(%s): no handler for script '%s'"
				addon:Debug(msg:format(tostring(script)))
			end
			
			local callbacks = scriptCallbacksByWidget[script]
			if scriptCallback then
				callbacks[widget][scriptCallback] = nil
			else
				-- clear all callbacks for this script for this widget
				wipe(callbacks[widget])
			end
		end
	else
		local msg = "Elements:UnregisterMouse(%s) - 'widget' cannot unregister mouse scripts (type=%s)"
		addon:Debug(msg:format(tostring(script), type(widget)))
	end
end

function Elements:UnregisterAllMouse(widget)
	if IsValidWidget(widget) then
		numMouseScripts[widget] = 0
		
		widget:EnableMouse(false)
		widget:EnableMouseWheel(false)
		widget.spellCD = nil
		ClearAllFeedback(widget)
		
		widget:SetScript(ONENTER, nil)
		widget:SetScript(ONLEAVE, nil)
		widget:SetScript(ONMOUSEDOWN, nil)
		widget:SetScript(ONMOUSEUP, nil)
		widget:SetScript(ONMOUSEWHEEL, nil)
	else
		local msg = "Elements:UnregisterAllMouse() - 'widget' is not a valid mouse widget (type=%s)"
		addon:Debug(msg:format(tostring(script), type(widget)))
	end
end
