
local select, type, next, wipe, abs, remove, inf
	= select, type, next, wipe, math.abs, table.remove, math.huge
local CreateFrame, UIParent, GetCursorPosition
	= CreateFrame, UIParent, GetCursorPosition

local addon = Overseer

local consts = addon.consts
local append = addon.TableAppend

local POINT = consts.POINT
local MESSAGES = consts.MESSAGES
local FRAME_TYPES = consts.FRAME_TYPES
local MBUTTON = consts.MBUTTON
local OVERLAY_BASE_ALPHA = 0.5
local OVERLAY_HOVER_ALPHA = 0.5
local OVERLAY_CLICK_ALPHA = 0.6
local OVERLAY_BASE_LEVEL_OFFSET = 10
local OVERLAY_EDGE_LEVEL_OFFSET = 20
local OVERLAY_EDGE_SIZE = 3
local OVERLAY_CORNER_SIZE = OVERLAY_EDGE_SIZE + 2
local OVERLAY_EDGE_HIT_OFFSET = 2 -- TODO: may have to use percentages
local OVERLAY_CORNER_HIT_OFFSET = 3

local IS_CORNER = {
	[5] = true,
	[6] = true,
	[7] = true,
	[8] = true,
	[POINT[5]] = true,
	[POINT[6]] = true,
	[POINT[7]] = true,
	[POINT[8]] = true,
}

-- ------------------------------------------------------------------
-- Overlays
-- ------------------------------------------------------------------
local deadOverlays = {
	--[[
	pool reusable of frame overlays
	
	form:
	frame,
	frame,
	...
	--]]
}

local function GetBaseOverlayColor() return 0, 0, 0 end
local function GetActiveOverlayColor() return 0, 1, 0 end
local function GetHighlightOverlayColor() return 0, 1, 1 end

local function GetBaseOverlay(r, g, b)
	base = CreateFrame(FRAME_TYPES.FRAME, nil, UIParent)
	base.bg = base:CreateTexture(nil, "BACKGROUND")
	base.bg:SetTexture(r or 0, g or 0, b or 0) -- note: setting the texture alpha here differs from :SetAlpha
	base.bg:SetAlpha(OVERLAY_BASE_ALPHA)
	base.bg:SetAllPoints()
	return base
end

local Resize = {} -- resize mouse down handlers
local function GetEdgeOverlay(overlay, point)
	local edge = GetBaseOverlay(GetActiveOverlayColor())
	edge:SetScript("OnMouseDown", Resize[point])
	
	if point == POINT[1] then -- top
		edge:SetPoint("TOPLEFT", overlay, "TOPLEFT", OVERLAY_CORNER_SIZE, 0)
		edge:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", -OVERLAY_CORNER_SIZE, 0)
		edge:SetHeight(OVERLAY_EDGE_SIZE)
		edge:SetHitRectInsets(0, 0, 0, -OVERLAY_EDGE_HIT_OFFSET) -- l, r, t, b
		
	elseif point == POINT[2] then -- bottom
		edge:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", OVERLAY_CORNER_SIZE, 0)
		edge:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", -OVERLAY_CORNER_SIZE, 0)
		edge:SetHeight(OVERLAY_EDGE_SIZE)
		edge:SetHitRectInsets(0, 0, -OVERLAY_EDGE_HIT_OFFSET, 0)
		
	elseif point == POINT[3] then -- left
		edge:SetPoint("TOPLEFT", overlay, "TOPLEFT", 0, -OVERLAY_CORNER_SIZE)
		edge:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 0, OVERLAY_CORNER_SIZE)
		edge:SetWidth(OVERLAY_EDGE_SIZE)
		edge:SetHitRectInsets(0, -OVERLAY_EDGE_HIT_OFFSET, 0, 0)
		
	elseif point == POINT[4] then -- right
		edge:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", 0, -OVERLAY_CORNER_SIZE)
		edge:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 0, OVERLAY_CORNER_SIZE)
		edge:SetWidth(OVERLAY_EDGE_SIZE)
		edge:SetHitRectInsets(-OVERLAY_EDGE_HIT_OFFSET, 0, 0, 0)
		
	-- corners
	elseif point == POINT[5] then -- topleft
		edge:SetPoint("TOPLEFT", overlay, "TOPLEFT")
		edge:SetSize(OVERLAY_CORNER_SIZE, OVERLAY_CORNER_SIZE)
		edge:SetHitRectInsets(0, -OVERLAY_CORNER_HIT_OFFSET, 0, -OVERLAY_CORNER_HIT_OFFSET)
		
	elseif point == POINT[6] then -- topright
		edge:SetPoint("TOPRIGHT", overlay, "TOPRIGHT")
		edge:SetSize(OVERLAY_CORNER_SIZE, OVERLAY_CORNER_SIZE)
		edge:SetHitRectInsets(-OVERLAY_CORNER_HIT_OFFSET, 0, 0, -OVERLAY_CORNER_HIT_OFFSET)
		
	elseif point == POINT[7] then -- bottomleft
		edge:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT")
		edge:SetSize(OVERLAY_CORNER_SIZE, OVERLAY_CORNER_SIZE)
		edge:SetHitRectInsets(0, -OVERLAY_CORNER_HIT_OFFSET, -OVERLAY_CORNER_HIT_OFFSET, 0)
		
	elseif point == POINT[8] then -- bottomright
		edge:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT")
		edge:SetSize(OVERLAY_CORNER_SIZE, OVERLAY_CORNER_SIZE)
		edge:SetHitRectInsets(-OVERLAY_CORNER_HIT_OFFSET, 0, -OVERLAY_CORNER_HIT_OFFSET, 0)
	end
	
	return edge
end

local TEXT_OFFSET_Y = 12
local OnMoveMouseEnter, OnMoveMouseLeave, OnMoveMouseDown, OnMoveMouseUp
local OnResizeMouseEnter, OnResizeMouseLeave, OnResizeMouseUp
local function GetOverlay(anchor)
	local overlay = remove(deadOverlays)
	if not overlay then
		overlay = GetBaseOverlay(GetBaseOverlayColor())
		local edges = {}
		for i = 1, #POINT do
			local edge = GetEdgeOverlay(overlay, POINT[i])
			edge:Hide()
			edge:SetParent(overlay)
			append(edges, edge)
		end
		overlay.edges = edges
		overlay.text = overlay:CreateFontString(nil, nil, "GameFontHighlight")
		overlay.text:SetVertexColor(1, 0.5, 0)
		overlay.text:SetJustifyH("CENTER")
		overlay.text:ClearAllPoints()
		overlay.text:SetPoint("TOP", 0, TEXT_OFFSET_Y)
		overlay.text:SetSize(100, overlay.text:GetHeight())
	end
	
	overlay:Show()
	overlay:EnableMouse(true)
	overlay:SetAllPoints(anchor)
	overlay:SetFrameStrata(anchor:GetFrameStrata())
	overlay:SetFrameLevel(anchor:GetFrameLevel() + OVERLAY_BASE_LEVEL_OFFSET)
	overlay.text:SetText("")
	
	if anchor:IsMovable() then
		overlay:SetScript("OnEnter", OnMoveMouseEnter)
		overlay:SetScript("OnLeave", OnMoveMouseLeave)
		overlay:SetScript("OnMouseDown", OnMoveMouseDown)
		overlay:SetScript("OnMouseUp", OnMoveMouseUp)
	end
	if anchor:IsResizable() then
		for i = 1, #overlay.edges do
			local edge = overlay.edges[i]
			edge.anchor = anchor
			
			edge:Show()
			edge:EnableMouse(true)
			edge:SetAlpha(0.0)
			edge:SetFrameLevel(anchor:GetFrameLevel() + OVERLAY_EDGE_LEVEL_OFFSET)
			edge:SetScript("OnEnter", OnResizeMouseEnter)
			edge:SetScript("OnLeave", OnResizeMouseLeave)
			edge:SetScript("OnMouseUp", OnResizeMouseUp)
		end
	end
	
	return overlay
end

local function DestroyOverlay(overlay)
	overlay.anchor = nil
	overlay:ClearAllPoints()
	overlay.bg:SetTexture(GetBaseOverlayColor())
	
	overlay:Hide()
	overlay:EnableMouse(false)
	overlay:SetFrameStrata("BACKGROUND")
	overlay:SetFrameLevel(0)
	overlay:SetScript("OnEnter", nil)
	overlay:SetScript("OnLeave", nil)
	overlay:SetScript("OnMouseDown", nil)
	overlay:SetScript("OnMouseUp", nil)
	overlay:SetScript("OnUpdate", nil)
	for i = 1, #overlay.edges do
		local edge = overlay.edges[i]
		
		edge:Hide()
		edge:EnableMouse(false)
		edge:SetScript("OnEnter", nil)
		edge:SetScript("OnLeave", nil)
		edge:SetScript("OnMouseUp", nil)
	end
	
	-- throw it in the pool to recycle later
	append(deadOverlays, overlay)
end

-- ------------------------------------------------------------------
-- Storage for all movables
-- ------------------------------------------------------------------
local Movables = {
	--[[
	form:
	[frame] = true,
	...
	--]]
}
do -- embed message registration
	Movables.RegisterMessage = addon.RegisterMessage
	Movables.UnregisterMessage = addon.UnregisterMessage
end

Movables[MESSAGES.BOSS_ENGAGE] = function(self, msg)
	if addon:AreMovablesUnlocked() then
		-- TODO: start a timer and lock if none have been moved within N interval
		--  ..unlock after boss ends?
	end
end

function Movables:Add(movable, objType)
	local added
	self[objType] = self[objType] or {}
	if not self[objType][movable] then
		self[objType][movable] = true
		added = true
		
		self:RegisterMessage(MESSAGES.BOSS_ENGAGE)
	end
	return added
end

function Movables:Remove(movable, objType)
	if type(self[objType]) == "table" then
		if type(self[objType][movable]) == "table" then
			self[objType][movable]:LockMoving()
		end
		self[objType][movable] = nil
	
		local lastMovable = true
		for movable in next, self do
			if type(movable) == "table" then
				lastMovable = false
				break
			end
		end
		if lastMovable then
			self:UnregisterMessage(MESSAGES.BOSS_ENGAGE)
		end
	end
end

local function UnlockMovables(movableObjects)
	if type(movableObjects) == "table" then
		for movable in next, movableObjects do
			if type(movable) == "table" then
				movable:UnlockMoving()
			end
		end
	end
end

local movablesUnlocked -- TODO: differentiate between 'all' and 'any'
function addon:UnlockAllMovables(objType)
	addon:PrintFunction((":UnlockAllMovables(%s)"):format(tostring(objType)))
	
	if objType then
		UnlockMovables(Movables[objType])
	else
		for objType, objs in next, Movables do
			UnlockMovables(objs)
		end
	end
	movablesUnlocked = true
end

function addon:LockAllMovables()
	addon:PrintFunction(":LockAllMovables()")
	for objType, objs in next, Movables do
		if type(objs) == "table" then
			for movable in next, objs do
				if type(movable) == "table" then
					movable:LockMoving()
				end
			end
		end
	end
	movablesUnlocked = nil
end

function addon:AreMovablesUnlocked()
	return movablesUnlocked
end

-- ------------------------------------------------------------------
-- Movable prototype
-- ------------------------------------------------------------------
local MovableObject = {}
addon.MovableObject = MovableObject
MovableObject.__index = MovableObject

--[[local]] function OnMoveMouseEnter(overlay, motion)
	if motion then
		overlay.bg:SetAlpha(OVERLAY_HOVER_ALPHA)
		overlay.bg:SetTexture(GetActiveOverlayColor())
	end
	if overlay.anchor then
		if overlay.anchor:IsResizable() then
			overlay.anchor:UnlockSizing()
		end
	end
end

--[[local]] function OnMoveMouseLeave(overlay, motion)
	overlay.bg:SetAlpha(OVERLAY_BASE_ALPHA)
	overlay.bg:SetTexture(GetBaseOverlayColor())
	if overlay.anchor then
		if overlay.anchor:IsResizable() then
			overlay.anchor:LockSizing()
		end
	end
end

local function GetCurrentMousePosition()
	local mouseX, mouseY = GetCursorPosition()
	--local effectiveScale = UIParent:GetEffectiveScale() -- can this change?
	--return mouseX / effectiveScale, mouseY / effectiveScale
	return mouseX, mouseY
end

local e = 0
local MIN_UPDATE_TIME = 0.25
local origMouseX, origMouseY
local lockedX, lockedY
local function OnMoveUpdate(overlay, elapsed)
	if overlay then
		e = e + elapsed
		if e > MIN_UPDATE_TIME then
			if overlay.isMoving then
				-- set the overlay color/alpha in case the mouse moves off of the overlay while dragging
				overlay.bg:SetAlpha(OVERLAY_CLICK_ALPHA)
				overlay.bg:SetTexture(GetActiveOverlayColor())
				
				-- calculate the new anchor position
				local mouseX, mouseY = GetCurrentMousePosition()
				local effScale = overlay.anchor:GetEffectiveScale() -- apply the object's effective scale to the change in mouse position
				local offsetX = (mouseX - origMouseX) / effScale
                local offsetY = (mouseY - origMouseY) / effScale
				local pt, rel, relPt, anchorX, anchorY = overlay.anchor:GetPoint()
				local x = lockedX or anchorX + offsetX
                local y = lockedY or anchorY + offsetY
				
				-- set the new anchor position and give feedback as to the new coordinates
				overlay.anchor:ClearAllPoints()
				overlay.anchor:SetPoint(pt, rel, relPt, x, y)
				overlay.text:SetText(("%.1f, %.1f"):format(x, y))
				
				-- cache the new mouse position for the next pass
				origMouseX = mouseX
				origMouseY = mouseY
			end
		end
	end
end

--[[local]] function OnMoveMouseDown(overlay, btn)
	if overlay.anchor then
		local beginMoving
        local effScale = 1--overlay.anchor:GetEffectiveScale()
		local x, y = select(4, overlay.anchor:GetPoint())
        x = x * effScale
        y = y * effScale
        
		if btn == MBUTTON.LEFT then
			beginMoving = true
			lockedY = y
		elseif btn == MBUTTON.RIGHT then
			beginMoving = true
			lockedX = x
		elseif btn == MBUTTON.MIDDLE then
			beginMoving = true
		end
		
		if beginMoving then
			origMouseX, origMouseY = GetCurrentMousePosition()
			overlay.bg:SetAlpha(OVERLAY_CLICK_ALPHA)
			overlay.bg:SetTexture(GetActiveOverlayColor())
			if overlay.anchor then
				--overlay.anchor:StartMoving()
				overlay:SetScript("OnUpdate", OnMoveUpdate)
				overlay.isMoving = true
			end
		end
	end
end

--[[local]] function OnMoveMouseUp(overlay, btn)
	if overlay.anchor then
		local stopMoving
		if btn == MBUTTON.LEFT then
			stopMoving = true
			lockedY = nil
		elseif btn == MBUTTON.RIGHT then
			stopMoving = true
			lockedX = nil
		elseif btn == MBUTTON.MIDDLE then
			stopMoving = true
		end
		
		if stopMoving then
			origMouseX, origMouseY = nil, nil
			overlay.bg:SetAlpha(OVERLAY_HOVER_ALPHA)
			if overlay.anchor:IsMouseOver() then
				overlay.bg:SetTexture(GetActiveOverlayColor())
			else
				overlay.bg:SetTexture(GetBaseOverlayColor())
			end
			--overlay.anchor:StopMovingOrSizing()
			overlay:SetScript("OnUpdate", nil)
			overlay.text:SetText("")
			overlay.isMoving = nil
			
			-- save the new position
			local key
			if overlay.anchor.spells then
				-- display position
				local spellCD = next(overlay.anchor.spells)
				key = spellCD.spellid
			else
				-- group position
				key = overlay.anchor.groupId
			end
			
			if key then
				addon.db:SavePosition(key, overlay.anchor)
			else
				-- how?
				local msg = "MovableObject:OnMoveMouseUp() - failed to save position of %s"
				addon:Debug(msg:format(tostring(overlay.anchor))) -- this will probably not be a very useful debugging message
			end
		end
	end
end

function MovableObject:UnlockMoving()
	if not self.overlay then
		local overlay = GetOverlay(self)
		overlay.anchor = self
		self.overlay = overlay
		
		-- TODO: OnUpdate & manually :ClearPoint and :SetPoint
		
		movablesUnlocked = true -- TODO: differentiate between 'all unlocked' vs 'at least one unlocked'
	end
end

function MovableObject:LockMoving()
	if self.overlay then
		DestroyOverlay(self.overlay)
		self.overlay = nil
	end
	
	-- check if there are any more movables unlocked
	local isLastLock = true
	for movable in next, Movables do
		if type(movable) == "table" then
			if movable.overlay then
				isLastLock = false
				break
			end
		end
	end
	if isLastLock then
		movablesUnlocked = nil
	end
end

-- ------------------------------------------------------------------
-- Sizable prototype
-- ------------------------------------------------------------------
local SizableObject = {}
addon.SizableObject = SizableObject
SizableObject.__index = SizableObject

--[[local]] function OnResizeMouseEnter(edge, motion)
	if edge.anchor then
		if edge.anchor.IsResizable and edge.anchor:IsResizable() then
			edge.bg:SetAlpha(OVERLAY_HOVER_ALPHA)
			edge:SetAlpha(1.0)
			edge.anchor:UnlockSizing()
		end
	end
end

--[[local]] function OnResizeMouseLeave(edge, motion)
	edge:SetAlpha(0.0)
	if edge.anchor and not edge.anchor:IsMouseOver() then
		edge.anchor.overlay.bg:SetTexture(GetBaseOverlayColor())
		edge.anchor.overlay.text:SetText("")
		edge.anchor:LockSizing()
	end
end

local lastMouseX, lastMouseY
local function OnResizeUpdate(self, elapsed)
	if self then
		e = e + elapsed
		if e > MIN_UPDATE_TIME then
			local mouseX, mouseY = GetCurrentMousePosition()
			local diffX = abs((lastMouseX or mouseX) - mouseX)
			local diffY = abs((lastMouseY or mouseY) - mouseY)
			local dim
			if diffX > diffY then
				dim = self:GetWidth()
			else
				dim = self:GetHeight()
			end
			
			self:SetSize(dim, dim) -- note: can produce a slight jitter in position
			lastMouseX, lastMouseY = mouseX, mouseY
		end
	end
end

local function OnResizeMouseDown(edge, btn, point)
	if btn == MBUTTON.LEFT then
		edge.bg:SetAlpha(OVERLAY_CLICK_ALPHA)
		if edge.anchor then
			local w, h = edge.anchor:GetSize()
			edge.anchor.overlay.text:SetText(("%d, %d"):format(w, h))
			edge.anchor:StartSizing(point)
			if IS_CORNER[point] then
				edge.anchor:SetScript("OnUpdate", OnResizeUpdate)
			end
		end
	end
end
do -- fill the Resize function map
	for i = 1, #POINT do
		local point = POINT[i]
		Resize[point] = function(edge, btn) OnResizeMouseDown(edge, btn, point) end
	end
end

--[[local]] function OnResizeMouseUp(edge, btn)
	if btn == MBUTTON.LEFT then
		edge.bg:SetAlpha(OVERLAY_HOVER_ALPHA)
		if edge.anchor then
			edge.anchor:StopMovingOrSizing()
			edge.anchor.overlay.text:SetText("")
			
			lastMouseX, lastMouseY = nil, nil
			edge.anchor:SetScript("OnUpdate", nil)
			
			if edge.anchor.spells then
				local spellCD = next(edge.anchor.spells)
				local key = spellCD.spellid
				local width = edge.anchor:GetWidth()
				local height = edge.anchor:GetHeight()
				addon.db:SaveIconSize(key, width, height)
			end
		end
	end
end

local function OnSizeChanged(self, width, height)
	local overlay = self.overlay
	if overlay and overlay.text then
		overlay.text:SetText(("%d, %d"):format(width, height))
	end
end

function SizableObject:UnlockSizing()
	local overlay = self.overlay
	if overlay and not overlay.sizingUnlocked then
		for i = 1, #overlay.edges do
			local edge = overlay.edges[i]
			edge:EnableMouse(true)
			edge.bg:SetAlpha(OVERLAY_BASE_ALPHA)
		end
		self:SetScript("OnSizeChanged", OnSizeChanged)
		overlay.sizingUnlocked = true
	end
end

function SizableObject:LockSizing()
	local overlay = self.overlay
	if overlay and overlay.sizingUnlocked then
		for i = 1, #overlay.edges do
			local edge = overlay.edges[i]
			edge:EnableMouse(false)
			edge:SetAlpha(0.0)
			edge.bg:SetAlpha(OVERLAY_BASE_ALPHA)
		end
		self:SetScript("OnSizeChanged", nil)
		overlay.sizingUnlocked = nil
	end
end

-- ------------------------------------------------------------------
-- Embeds
-- ------------------------------------------------------------------
local function IsFrame(target)
	return type(target) == "table" and type(target.GetObjectType) == "function" and target:GetObjectType() == FRAME_TYPES.FRAME
end

function MovableObject:Embed(targetFrame, objType)
	-- copies a reference of every method into the target table
	-- since we are copying refs, 'self' refers to the target object
	if IsFrame(targetFrame) then
		if Movables:Add(targetFrame, objType) then -- no need to embed again
			for k, f in next, self do
				if type(f) == "function" and k ~= "Embed" then
					targetFrame[k] = f
				end
			end
			local db = addon.db:GetProfile()
			targetFrame:SetMovable(true)
			targetFrame:SetClampedToScreen(db.clampedToScreen)
			
			if addon:AreMovablesUnlocked() then -- TODO: need to differentiate between different objTypes and ('any' and 'all') - I think unlocked state needs to be kept per objType
				targetFrame:UnlockMoving()
			end
		end
	end
end

function MovableObject:Unembed(targetFrame, objType)
	if Movables[objType] and Movables[objType][targetFrame] then
		Movables:Remove(targetFrame, objType)
		
		for k, f in next, self do
			-- remove all embedded movable functions
			if type(f) == "function" and k ~= "Embed" then
				if targetFrame[k] and type(targetFrame[k]) == "function" then
					targetFrame[k] = nil
				end
			end
		end
		targetFrame:SetMovable(false)
	end
end

function SizableObject:Embed(targetFrame)
	-- copies a reference of every method into the target table
	-- since we are copying refs, 'self' refers to the target object
	if IsFrame(targetFrame) then
		for k, f in next, self do
			if type(f) == "function" and k ~= "Embed" then
				targetFrame[k] = f
			end
		end
		local db = addon.db:GetProfile()
		targetFrame:SetResizable(true)
		targetFrame:SetMinResize(db.minWidth, db.minHeight)
	end
end

function SizableObject:Unembed(targetFrame)
	if IsFrame(targetFrame) then
		for k, f in next, self do
			if type(f) == "function" and k ~= "Embed" then
				if targetFrame[k] and type(targetFrame[k]) == "function" then
					targetFrame[k] = nil
				end
			end
		end
		targetFrame:SetResizable(false)
	end
end
