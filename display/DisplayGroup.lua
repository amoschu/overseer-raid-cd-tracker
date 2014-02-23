
local select, wipe, type, tostring, next, inf, abs, min, max, ceil, floor, remove, sort, concat
	= select, wipe, type, tostring, next, math.huge, math.abs, math.min, math.max, math.ceil, math.floor, table.remove, table.sort, table.concat
local CreateFrame
	= CreateFrame

local addon = Overseer

local consts = addon.consts
local append = addon.TableAppend
local round = addon.Round

local GROUP_ID = consts.GROUP_ID
local GROUP_ID_INVALID = consts.GROUP_ID_INVALID
local CONSOLIDATED_ID = consts.CONSOLIDATED_ID
local GROUP_TYPES = consts.GROUP_TYPES
local MESSAGES = consts.MESSAGES
local FRAME_TYPES = consts.FRAME_TYPES

local deadGroups = {} -- pool of recyclable frames

local _DEBUG_GROUPS = true
local _DEBUG_GROUPS_PREFIX = "|cff370365GROUPS|r"
local _DEBUG_GROUPS_TYPE_COLOR = "FF0000"

-- ------------------------------------------------------------------
-- DisplayGroup initialization
-- ------------------------------------------------------------------
local DisplayGroup = {
	--[[
	active groups
	
	form:
	[GROUP_ID] = frame,
	...
	--]]
}

-- ..not technically a display element, but responds to display messages the same way so:
local Elements = addon.DisplayElements
Elements:Register(DisplayGroup)

-- ------------------------------------------------------------------
-- Dynamic positioning
-- ------------------------------------------------------------------
local Dynamics = {}

local function FindChildRelativePosition(parent, child)
	local position
	local byPosition = parent.children.byPosition
	for i = 1, #byPosition do
		if byPosition[i] == child then
			position = i
			break
		end
	end
	if not position then
		-- somehow not in the .byPosition array ?
		local msg = "FindChildRelativePosition(%s) - child |cffFF0000NOT FOUND|r!!"
		addon:Debug(msg:format(tostring(child)))
	end
	return position
end

-- helper's helper
local function _GetPoint(grow)
	local point = ""
	if grow == "LEFT" then
		point = "RIGHT"
	elseif grow == "RIGHT" then
		point = "LEFT"
	elseif grow == "TOP" then
		point = "BOTTOM"
	elseif grow == "BOTTOM" then
		point = "TOP"
	end
	return point
end

local function GetPoint(grow, wrap)
	local point = _GetPoint(wrap)
	if grow == "LEFT" or grow == "RIGHT" then
		point = ("%s%s"):format(point, _GetPoint(grow))
	elseif grow == "TOP" or grow == "BOTTOM" then
		point = ("%s%s"):format(_GetPoint(grow), point)
	end
	return point
end

-- ------------------------------------------------------------------
-- SIDE - single-growth direction
Dynamics[GROUP_TYPES.SIDE] = function(child, parent, settings, add) -- this is a special case of the "GRID" type
	local grow = settings.grow
	local spacing = settings.spacing
	
	local byPosition = parent.children.byPosition
	local position = FindChildRelativePosition(parent, child)
	
	if _DEBUG_GROUPS then
		local absPos = parent.children.byChild[child]
		addon:Debug(("%s> |cff%s%s|r: abs=|cffFF00FF%d|r, pos=[|cffFF00FF%d|r]"):format(_DEBUG_GROUPS_PREFIX, _DEBUG_GROUPS_TYPE_COLOR, GROUP_TYPES.SIDE, absPos, position))
	end
	
	if add then
		-- determine where to place this child (looping in case children vary in size)
		local x, y = 0, 0
		for i = 1, position-1 do
			local sibling = byPosition[i]
			local width, height = sibling:GetSize()
			x = x + width
			y = y + height
		end
		
		-- position the child
		local pt = GetPoint(grow)
		if grow == "LEFT" then
			x = -x - ((position-1) * spacing)
			y = 0
		elseif grow == "RIGHT" then
			x = x + ((position-1) * spacing)
			y = 0
		elseif grow == "TOP" then
			x = 0
			y = y + ((position-1) * spacing)
		elseif grow == "BOTTOM" then
			x = 0
			y = -y - ((position-1) * spacing)
		end
		child:ClearAllPoints()
		child:SetPoint(pt, parent, pt, x, y)
		
		if _DEBUG_GROUPS then
			addon:Print(("%s> child:SetPoint(%s, |cff00FF00%s|r, |cff00FF00%s|r)"):format(_DEBUG_GROUPS_PREFIX, pt, round(x), round(y)))
		end
	end
	
	-- reposition other children in case this child shifted their positioning
	local childWidth, childHeight = child:GetSize()
	for i = position+1, #byPosition do
		local sibling = byPosition[i]
		local pt, rel, relPt, x, y = sibling:GetPoint()
		local shiftX, shiftY = 0, 0
		if grow == "LEFT" then
			shiftX = childWidth + spacing
			shiftX = add and -shiftX or shiftX
		elseif grow == "RIGHT" then
			shiftX = childWidth + spacing
			shiftX = add and shiftX or -shiftX
		elseif grow == "TOP" then
			shiftY = childHeight + spacing
			shiftY = add and shiftY or -shiftY
		elseif grow == "BOTTOM" then
			shiftY = childHeight + spacing
			shiftY = add and -shiftY or shiftY
		end
		sibling:ClearAllPoints()
		sibling:SetPoint(pt, parent, relPt, x + shiftX, y + shiftY)
		
		if _DEBUG_GROUPS then
			addon:Print(("%s> =>sibling[|cffFF00FF%d|r]:SetPoint(%s, |cff00FF00%s|r, |cff00FF00%s|r)"):format(_DEBUG_GROUPS_PREFIX, i, pt, round(x), round(y)))
		end
	end
end

-- ------------------------------------------------------------------
-- GRID - rectangular positioning
local function GetChildRowCol(grow, position, maxRow, maxCol)
	local row, col
	if grow == "LEFT" or grow == "RIGHT" then
		if maxCol == 0 then -- infinite growth in that direction
			row = 1
			col = position
		else
			row = ceil(position / maxCol)
			col = ((position-1) % maxCol) + 1
		end
	elseif grow == "TOP" or grow == "BOTTOM" then
		if maxRow == 0 then
			row = position
			col = 1
		else
			row = ((position-1) % maxRow) + 1
			col = ceil(position / maxRow)
		end
	end
	return row, col
end

-- returns the magnitude as a signed vector indicating direction as it corresponds to screen coordinates
-- or ±1 if 'magnitude' is nil
--[[
                 +1 up
    -1 left               +1 right
                 -1 down
--]]
local function ApplyDirection(grow, magnitude)
	magnitude = magnitude or 1
	if grow == "LEFT" or grow == "BOTTOM" then
		magnitude = -magnitude
	-- elseif grow == "RIGHT" or grow == "TOP" then
		-- magnitude = magnitude
	end
	return magnitude
end

Dynamics[GROUP_TYPES.GRID] = function(child, parent, settings, add)
	local grow = settings.grow
	local wrap = settings.wrap
	local spacingX = settings.spacingX
	local spacingY = settings.spacingY
	local rows = settings.rows
	local cols = settings.cols
	
	local byPosition = parent.children.byPosition
	local position = FindChildRelativePosition(parent, child)
	
	if _DEBUG_GROUPS then
		local absPos = parent.children.byChild[child]
		addon:Debug(("%s> |cff%s%s|r[%d, %d]: abs=|cffFF00FF%d|r, pos=[|cffFF00FF%d|r]"):format(_DEBUG_GROUPS_PREFIX, _DEBUG_GROUPS_TYPE_COLOR, GROUP_TYPES.GRID, rows, cols, absPos, position))
	end
	
	if add then
		local curRow, curCol = GetChildRowCol(grow, position, rows, cols)
		local x, y = 0, 0
		-- determine where to place this child (looping in case children vary in size)
		for i = 1, position-1 do
			local iRow, iCol = GetChildRowCol(grow, i, rows, cols)
			local sibling = byPosition[i]
			-- only other children on either the same row or column affect this child
			-- TODO: is this true for children of varying size?
			if iRow == curRow then
				x = x + sibling:GetWidth()
			elseif iCol == curCol then
				y = y + sibling:GetHeight()
			end
		end
		
		if _DEBUG_GROUPS then
			addon:Print(("%s> [|cffFF00FF%d|r] @ row=|cff00FF00%d|r, col=|cff00FF00%d|r"):format(_DEBUG_GROUPS_PREFIX, position, curRow, curCol))
		end
	
		-- position the child
		local pt = GetPoint(grow, wrap)
		local totalSpacingX = (curCol-1) * spacingX
		local totalSpacingY = (curRow-1) * spacingY
		if grow == "LEFT" or grow == "RIGHT" then
			x = ApplyDirection(grow, x) + ApplyDirection(grow, totalSpacingX)
			y = ApplyDirection(wrap, y) + ApplyDirection(wrap, totalSpacingY)
		elseif grow == "TOP" or grow == "BOTTOM" then
			x = ApplyDirection(wrap, x) + ApplyDirection(wrap, totalSpacingX)
			y = ApplyDirection(grow, y) + ApplyDirection(grow, totalSpacingY)
		end
		child:ClearAllPoints()
		child:SetPoint(pt, parent, pt, x, y)
		
		if _DEBUG_GROUPS then
			addon:Print(("%s> child:SetPoint(%s, |cff00FF00%s|r, |cff00FF00%s|r)"):format(_DEBUG_GROUPS_PREFIX, pt, round(x), round(y)))
		end
	end
	
	-- my god, it's full of vars..
	local childWidth, childHeight = child:GetSize()
	local childX, childY = select(4, child:GetPoint())
	local firstWidth, firstHeight = byPosition[1]:GetSize() -- wrapped-child positioning - TODO: I think I'm making too many assumptions here (may need to cache the height of every element in the first col)
	local lastWrappedWidth, lastWrappedHeight = childWidth, childHeight -- the most recently wrapped child's size
	local lastX, lastY = childX, childY -- the previous iteration's x, y offset after it has been repositioned
	local lastWidth, lastHeight = 0, 0 -- the previous iteration's width, height (depending on growth direction)
	-- reposition other children in case this child shifted their positioning
	for i = position+1, #byPosition do
		local oldPosition = add and i - 1 or i
		local curPosition = add and i or i - 1
		local oldRow, oldCol = GetChildRowCol(grow, oldPosition, rows, cols)
		local curRow, curCol = GetChildRowCol(grow, curPosition, rows, cols)
		-- determine how the added/removed child affected this one
		-- the growth-direction dimension should be ±1 if not wrapping or ±(maxDim-1) if wrapping
		-- the wrap-direction dimension should only ever be ±1 when wrapping (0 otherwise)
		local diffRow = curRow - oldRow -- curRow
		local diffCol = curCol - oldCol -- curCol
		
		local sibling = byPosition[i]
		local pt, rel, relPt, xOff, yOff = sibling:GetPoint()
		if grow == "LEFT" or grow == "RIGHT" then
			if diffRow ~= 0 then -- this sibling wrapped
				-- if lastWidth == 0, then lastX should already have the spacing baked in
				-- this specifically means that 'child' is being removed and that this sibling is wrapping to 'child's old position
				-- ie, this is the first sibling encountered in the loop
				local spacing = (lastWidth == 0) and 0 or spacingX
				-- diffRow > 0 means the sibling wrapped due to 'child' add
				-- diffRow < 0 means the sibling wrapped due to 'child' removal
				xOff = (diffRow > 0) and 0 or lastX + ApplyDirection(grow, lastWidth + spacing)
				lastWrappedWidth = sibling:GetWidth() -- this sibling's width will affect all children on its new row
				
				-- set this sibling's new y offset
				yOff = yOff + ApplyDirection(wrap, diffRow * (firstHeight + spacingY))
			else
				-- diffCol==(+)1 is in the growth direction (child added)
				-- diffCol==(-)1 is opposite (child removed)
				xOff = xOff + ApplyDirection(grow, diffCol * (lastWrappedWidth + spacingX))
				lastX = xOff -- cache this calculation in case the next sibling wraps to the end-most column
				lastWidth = sibling:GetWidth()
			end
			
		elseif grow == "TOP" or grow == "BOTTOM" then
			if diffCol ~= 0 then
				local spacing = (lastHeight == 0) and 0 or spacingY
				yOff = (diffCol > 0) and 0 or lastY + ApplyDirection(grow, lastHeight + spacing)
				lastWrappedHeight = sibling:GetHeight()
				
				xOff = xOff + ApplyDirection(wrap, diffCol * (firstWidth + spacingX))
			else
				yOff = yOff + ApplyDirection(grow, diffRow * (lastWrappedHeight + spacingY))
				lastY = yOff
				lastHeight = sibling:GetHeight()
			end
		end
		sibling:ClearAllPoints()
		sibling:SetPoint(pt, parent, relPt, xOff, yOff)
		
		if _DEBUG_GROUPS then
			local coloredIdx = ("|cffFF00FF%d|r"):format(i)
			addon:Print(("%s> =>sibling[%s]: curRow=|cff00FF00%d|r, curCol=|cff00FF00%d|r"):format(_DEBUG_GROUPS_PREFIX, coloredIdx, curRow, curCol))
			addon:Print(("%s> =>sibling[%s]: oldRow=|cff00FF00%d|r, oldCol=|cff00FF00%d|r"):format(_DEBUG_GROUPS_PREFIX, coloredIdx, oldRow, oldCol))
			addon:Print(("%s> =>sibling[%s]: diffRow=|cff00FF00%d|r, diffCol=|cff00FF00%d|r"):format(_DEBUG_GROUPS_PREFIX, coloredIdx, diffRow, diffCol))
			addon:Print(("%s> sibling[%s] :SetPoint(%s, |cff00FF00%s|r, |cff00FF00%s|r)"):format(_DEBUG_GROUPS_PREFIX, coloredIdx, pt, round(xOff), round(yOff)))
		end
	end
end

-- ------------------------------------------------------------------
-- RADIAL - circular positioning
Dynamics[GROUP_TYPES.RADIAL] = function(child, parent, settings, add)
	local grow = settings.grow
	local radius = settings.radius
	local startAngle = settings.startAngle
	local endAngle = settings.endAngle
	
	local byPosition = parent.children.byPosition
	local position = FindChildRelativePosition(parent, child)
	
	if _DEBUG_GROUPS then
		local absPos = parent.children.byChild[child]
		addon:Debug(("%s> |cff%s%s|r[r=%d, %.1f, %.1f]: abs=|cffFF00FF%d|r, pos=[|cffFF00FF%d|r]"):format(_DEBUG_GROUPS_PREFIX, _DEBUG_GROUPS_TYPE_COLOR, GROUP_TYPES.RADIAL, radius, startAngle, endAngle, absPos, position))
	end

	-- position this child
	
	-- shift other children if needed
end

-- ------------------------------------------------------------------
-- Dynamic settings dispatcher
-- 'child' can either be a SpellDisplay or a DisplayGroup
-- 'parent' can only be a DisplayGroup
-- 'add' is a bool indicating whether the child is being added to (true) or removed from (false) the parent
local function HandleDynamicSettings(child, parent, groupOptions, add)
	local dynamic = groupOptions.dynamic
	if dynamic.enabled then
		local dynamicHandler = dynamic.type and Dynamics[dynamic.type]
		if type(dynamicHandler) == "function" then
			local settings = dynamic[dynamic.type]
			dynamicHandler(child, parent, settings, add)

			local pt = GetPoint(settings.grow)
			local parentPt, rel, relPt, parentX, parentY = parent:GetPoint()
			if parentPt ~= pt then
				-- set the parent's point so that adding/removing children does not alter position
				parent:ClearAllPoints()
				addon:Print(("%s -> :SetPoint(%s, %s, %s, %.1f, %.1f)"):format(parent.groupId, pt, tostring(rel), relPt, parentX, parentY))
				parent:SetPoint(pt, rel, relPt, parentX, parentY)
			end
		else
			local msg = "HandleDynamicSettings() - |cffFF0000missing|r handler for type '%s'"
			addon:Debug(msg:format(tostring(dynamic.type)))
		end
	end
end

-- ------------------------------------------------------------------
-- OnCreate
-- ------------------------------------------------------------------
-- creates a group frame
local MovableObject = addon.MovableObject
local function CreateGroup(groupId)
	-- group not yet created, need to make a new one
	local group = remove(deadGroups)
	if not group then
		group = CreateFrame(FRAME_TYPES.FRAME)
		group.children = {
			--[[
			key by both the child reference and by the child's position (the latter is for sorting)
			--]]
			
			byChild = {
				--[[
				form:
				[child] = pos,
				[child] = pos,
				...
				--]]
			},
			byPosition = {
				--[[
				form:
				child, -- child at position 1
				child, -- child at position 2
				...,
				child, -- at position N
				--]]
			},
		}
		group.numChildren = 0
		DisplayGroup[groupId] = group
	end
	MovableObject:Embed(group, "Group")
	group.groupId = groupId -- flag the group id on the frame (mostly for saving)
	group:SetSize(1, 1) -- hack to ensure group sizing works (:GetLeft, etc return nil if this is not set)
	-- set the position of the group
	group:SetPoint(addon.db:LookupPosition(groupId))
	
	group:Show()
	return group
end

local function CompareChildren(byChild, childA, childB)
	local posA = byChild[childA]
	local posB = byChild[childB]
	return posA < posB
end

local function AddChild(parent, child, position)
	local added = false
	local byChild = parent.children.byChild
	if not byChild[child] then
		child.group = parent
		parent.numChildren = (parent.numChildren or 0) + 1
		byChild[child] = position
		
		-- sort the children by position for dynamic positioning
		local byPosition = parent.children.byPosition
		append(byPosition, child)
		-- ideally, no throw-away closure would be created, but that would require caching the parent on every child which is unnecessary
		sort(byPosition, function(a, b) return CompareChildren(byChild, a, b) end)
		
		addon:SendMessage(MESSAGES.DISPLAY_GROUP_ADD, child, parent)
		added = true
	end
	return added
end

local function ResizeParent(parent)
	local width, height
	local byPosition = parent.children.byPosition
	local left, right, top, bottom = inf, -inf, -inf, inf
	-- get the left-most, right-most, top-most, and bottom-most coordinates
	for i = 1, #byPosition do
		local child = byPosition[i]
		if child:IsVisible() then -- hidden frames should not affect the size
			local effScale = child:GetEffectiveScale()
			
			local cLeft = child:GetLeft() * effScale
			if cLeft < left then left = cLeft end
			
			local cRight = child:GetRight() * effScale
			if cRight > right then right = cRight end
			
			local cTop = child:GetTop() * effScale
			if cTop > top then top = cTop end
			
			local cBottom = child:GetBottom() * effScale
			if cBottom < bottom then bottom = cBottom end
			
			addon:SendMessage(MESSAGES.DISPLAY_GROUP_RESIZE, child, parent)
		end
	end
	if left == inf or right == -inf then
		-- no children visible
		width = 0
	else
		width = right - left
	end
	if top == -inf or bottom == inf then
		height = 0
	else
		height = top - bottom
	end	
	parent:SetSize(width, height)

	if _DEBUG_GROUPS then
		addon:Debug(("%s> parent:SetSize(|cff00FF00%.1f|r, |cff00FF00%.1f|r)"):format(_DEBUG_GROUPS_PREFIX, width, height))
	end
end

local function AlreadyVisited(visited, childId)
    local result
    for i = 1, #visited do
        if visited[i] == childId then
            result = true
            break
        end
    end
    return result
end

-- spawns a group's parents up to the root parent
--[[
-- eg: spell spawns E -> spawns C -> spawns A -> ...
				A
			  /   \
			 B     C
			/     / \
		   D     E   F

		eg: 
		{ -- 'groupDB'
			[A] = { -- group A
				children = {
					[B],
					[C],
				},
			},
			[B] = { -- group B
				children = {
					[D],
				},
			},
			[C] = {
				children = {
					[E],
					[F],
				},
			},
			[D] = ...
			[E] = ...
			[F] = ...
		}
--]]
local function SpawnGroups(childId, child, visited)
    visited = visited or {}
    if AlreadyVisited(visited, childId) then
        addon:Debug(("SpawnGroups(%s): Cyclic reference detected! (%s)"):format(childId, concat(visited, "->")))
        return
    end
    append(visited, childId)

	local groupDB = addon.db:GetGroupOptions()
	for groupId, groupOptions in next, groupDB do
		-- no need to check if a group is a parent of itself
		-- the invalid check is to prevent somehow looping over an uninitialized SV group entry..
		if groupId ~= childId and groupId ~= GROUP_ID_INVALID then
			local position = groupOptions.children[childId]
			if position then
				local parentGroup = DisplayGroup[groupId]
				-- don't recurse infinitely
				if not parentGroup then
					parentGroup = CreateGroup(groupId)
				-- else
					-- -- I'm pretty sure this is not an error
					-- -- can (and should) happen for any group with multiple children
					-- local msg = "SpawnGroups(%s): Halting recursion, parent=%s already exists!"
					-- addon:Debug(msg:format(childId, groupId))
				end
				
				if _DEBUG_GROUPS then
					addon:Debug(("%s> :|cff999999AddChild|r(): adding child id '%s' to parent '%s'"):format(_DEBUG_GROUPS_PREFIX, tostring(childId), groupId))
				end
				
				-- only apply settings if this is the first time this child has been added
				if AddChild(parentGroup, child, position) then
					--addon:Debug(">> Group: Add successful!!")
					HandleDynamicSettings(child, parentGroup, groupOptions, true)
					-- resize the parent based on its children's positioning
					ResizeParent(parentGroup)
					-- spawn the parent's parents (if any)
					SpawnGroups(groupId, parentGroup, visited)
				end
				
				-- a display can only be a child of a single group
				-- a group can only be a subgroup of a one other group
				break
			end
		end
	end
end

DisplayGroup[MESSAGES.DISPLAY_CREATE] = function(self, msg, spellCD, display)
	SpawnGroups(spellCD.spellid, display)
end

-- ------------------------------------------------------------------
-- OnDelete
-- ------------------------------------------------------------------
local function DestroyGroup(groupId)
	local group = DisplayGroup[groupId]
	if group then
		group:Hide()
		
		if group:IsMovable() then -- TODO: bake into :Unembed
			group:LockMoving()
		end
		MovableObject:Unembed(group)
		
		append(deadGroups, group)
		DisplayGroup[groupId] = nil
		
		if _DEBUG_GROUPS then
			addon:Debug(("%s> :|cff999999DestroyGroup|r(%s)"):format(_DEBUG_GROUPS_PREFIX, groupId))
		end
	end
end

local function RemoveChild(parent, child)
	local removed = false
	local byChild = parent.children.byChild
	if byChild[child] then
		addon:SendMessage(MESSAGES.DISPLAY_GROUP_REMOVE, child, parent)
	
		child.group = nil
		parent.numChildren = parent.numChildren - 1
		byChild[child] = nil
		
		local idx = FindChildRelativePosition(parent, child)
		if idx then
			remove(parent.children.byPosition, idx)
		end
		removed = true
	end
	return removed
end

-- reverse of SpawnGroups
local function DespawnGroups(childId, child, visited)
    visited = visited or {}
    if AlreadyVisited(visited, childId) then
        addon:Debug(("DespawnGroups(%s): Cyclic reference detected! (%s)"):format(childId, concat(visited, "->")))
        return
    end
    append(visited, childId)
    
	local groupDB = addon.db:GetGroupOptions()
	for groupId, groupOptions in next, groupDB do
		if groupId ~= childId and groupId ~= GROUP_ID_INVALID then
			if groupOptions.children[childId] then
				local parentGroup = DisplayGroup[groupId]
				-- the display may not have been part of a group
				if parentGroup then
					if _DEBUG_GROUPS then
						addon:Debug(("%s> |cff999999RemoveChild|r(%s): parent.numChildren=|cffFF00FF%s|r"):format(_DEBUG_GROUPS_PREFIX, tostring(childId), parentGroup.numChildren - 1))
					end
					
					HandleDynamicSettings(child, parentGroup, groupOptions)
					if RemoveChild(parentGroup, child) then
						ResizeParent(parentGroup)
						if parentGroup.numChildren == 0 then
							-- parent is now empty
							DestroyGroup(groupId)
							-- check if grandparent is empty
							DespawnGroups(groupId, parentGroup, visited)
						end
					end
					
					break
				end
			end
		end
	end
end

DisplayGroup[MESSAGES.DISPLAY_DELETE] = function(self, msg, spellCD, display)
	DespawnGroups(spellCD.spellid, display)
end

-- ------------------------------------------------------------------
-- OnDisplay Show/Hide
-- from a group perspective, this is no different than _CREATE/_DELETE
-- ------------------------------------------------------------------
DisplayGroup[MESSAGES.DISPLAY_SHOW] = function(self, msg, spellCD, display)
	addon:PrintFunction(("Group -> showing %s"):format(tostring(spellCD)))
	SpawnGroups(spellCD.spellid, display)
end

DisplayGroup[MESSAGES.DISPLAY_HIDE] = function(self, msg, spellCD, display)
	addon:PrintFunction(("Group -> hiding %s"):format(tostring(spellCD)))
	DespawnGroups(spellCD.spellid, display)
end

-- ------------------------------------------------------------------
-- OnDisplayUse - to catch positioning for displays which only show bars
-- ------------------------------------------------------------------
DisplayGroup[MESSAGES.DISPLAY_USE] = function(self, msg, spellCD, display)
	local db = addon.db:GetDisplaySettings(spellCD.spellid)
	if not db.icon.shown then
		-- TODO
	end
end

-- ------------------------------------------------------------------
-- OnDisplayReady - to catch positioning for displays which only show bars
-- ------------------------------------------------------------------
DisplayGroup[MESSAGES.DISPLAY_READY] = function(self, msg, spellCD, display)
	local db = addon.db:GetDisplaySettings(spellCD.spellid)
	if not db.icon.shown then
		-- TODO
	end
end

-- ------------------------------------------------------------------
-- OnDisplayReset - to catch positioning for displays which only show bars
-- ------------------------------------------------------------------
DisplayGroup[MESSAGES.DISPLAY_RESET] = function(self, msg, spellCD, display)
	local db = addon.db:GetDisplaySettings(spellCD.spellid)
	if not db.icon.shown then
		-- TODO
	end
end
