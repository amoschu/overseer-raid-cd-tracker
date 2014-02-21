

--[[ Extremely squirly snap-to-nearest implementation.. not worth it imo
local EPSILON = 25
local MIN_SNAP_DIST = 75
local currentSnap
local mouseSnapX, mouseSnapY
local function MouseMovedTooFar()
	local result = false
	local mouseX, mouseY = GetCurrentMousePosition()
	if mouseSnapX then 
		result = abs(mouseSnapX - mouseX) > MIN_SNAP_DIST + EPSILON
	end
	if not result and mouseSnapY then
		result = abs(mouseSnapY - mouseY) > MIN_SNAP_DIST + EPSILON
	end
	return result
end

local function SuperShittySnapToNearestImplementation()
	-- check for nearby frames to snap to
	-- TODO: optimize? I think there will ever only be, at most, ~50 displays so any optimizing here would be negligible
	if not currentSnap then
		local nearestX, nearestY
		local prevNearestDistX, prevNearestDistY
		local w, h = overlay.anchor:GetSize()
		for movable in next, Movables do
			if type(movable) == "table" and movable ~= overlay.anchor then
				--local movableScale = movable:GetEffectiveScale()
				local x2, y2 = movable:GetCenter()
				--x2 = x2 * movableScale
				--y2 = y2 * movableScale
				local dx = x2 - x
				local dy = y2 - y
				if dx*dx + dy*dy <= MIN_SNAP_DIST*MIN_SNAP_DIST then
					-- addon:Print("dx="..dx..", dy="..dy)
					-- local w2, h2 = movable:GetSize()
					-- local distX = dx - (0.5*w2 - 0.5*w) --(x2 - 0.5*w2) - (x - 0.5*w)
					-- local distY = dy - (0.5*h2 - 0.5*h) --(y2 - 0.5*h2) - (y - 0.5*h)
					if abs(dy) <= MIN_SNAP_DIST then
						if (prevNearestDistX or inf) > dy then
							nearestX = movable
							prevNearestDistX = dx
						end
					end
					if abs(dy) <= MIN_SNAP_DIST then
						if (prevNearestDistY or inf) > dy then
							nearestY = movable
							prevNearestDistY = dy
						end
					end
				end
			end
		end
		if nearestX or nearestY then
			local point, relative, x, y
			if prevNearestDistX and prevNearestDistY then
				if abs(prevNearestDistX) < abs(prevNearestDistY) then
					if prevNearestDistX < 0 then
						point = "LEFT"
						relative = "RIGHT"
						x = 2
					elseif prevNearestDistX > 0 then
						point = "RIGHT"
						relative = "LEFT"
						x = -2
					end
				elseif abs(prevNearestDistY) < abs(prevNearestDistX) then
					if prevNearestDistY < 0 then
						point = "BOTTOM"
						relative = "TOP"
						y = 2 -- TODO: read from db
					elseif prevNearestDistY > 0 then
						point = "TOP"
						relative = "BOTTOM"
						y = -2
					end
				end
			elseif prevNearestDistX then
				if prevNearestDistX < 0 then
					point = "LEFT"
					relative = "RIGHT"
					x = 2 -- TODO: read from db
				elseif prevNearestDistX > 0 then
					point = "RIGHT"
					relative = "LEFT"
					x = -2
				end
			elseif prevNearestDistY then
				if prevNearestDistY < 0 then
					point = "BOTTOM"
					relative = "TOP"
					y = 2 -- TODO: read from db
				elseif prevNearestDistY > 0 then
					point = "TOP"
					relative = "BOTTOM"
					y = -2
				end
			end
			if x then
				currentSnap = nearestX
			elseif y then
				currentSnap = nearestY
			end
			if point and relative then
				overlay.anchor:ClearAllPoints()
				overlay.anchor:SetPoint(point, currentSnap, relative, x or 0, y or 0)
				overlay.anchor:StopMovingOrSizing()
				
				mouseSnapX, mouseSnapY = GetCurrentMousePosition()
			end
		end
	elseif MouseMovedTooFar() then
		currentSnap = nil
		mouseSnapX = nil
		mouseSnapY = nil
		
		local mouseX, mouseY = GetCurrentMousePosition()
		overlay.anchor:ClearAllPoints()
		overlay.anchor:SetPoint("BOTTOMLEFT", mouseX, mouseY)
		overlay.anchor:StartMoving()
	end
end
--]]