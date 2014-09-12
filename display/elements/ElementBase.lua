
local insert, remove
	= table.insert, table.remove

local addon = Overseer

local consts = addon.consts
local append = addon.TableAppend

local MESSAGES = consts.MESSAGES

-- ------------------------------------------------------------------
-- Element message handling
-- ------------------------------------------------------------------
local Elements = {
	--[[
	display element registry
	handles the boilerplate for all display elements
	elements are expected to be a table with appropriate message callbacks
	
	form:
	_registry = {
		[element] = true,
		[element] = true,
		...
	},
	[1] = element, -- array for order-sensitive message handling
	[2] = element,
	...
	--]]
	_registry = {},
}
addon.DisplayElements = Elements

local function ElementDisplayHandler(self, msg, spellCD, display)
	for i = 1, #self do
		local element = self[i]
		if type(element) == "table" and type(element[msg]) == "function" then
			element[msg](element, msg, spellCD, display)
		end
	end
end
local function ElementDisplayGroupHandler(self, msg, child, group)
	for i = 1, #self do
		local element = self[i]
		if type(element) == "table" and type(element[msg]) == "function" then
			element[msg](element, msg, child, group)
		end
	end
end
local function ElementTextBehaviorHandler(self, msg, child, onEnter, onLeave, onMouseDown, onMouseUp, onMouseWheel)
	for i = 1, #self do
		local element = self[i]
		if type(element) == "table" and type(element[msg]) == "function" then
			addon:FUNCTION("%s(enter=%s, leave=%s, down=%s, up=%s, wheel=%s)", msg, tostring(onEnter), tostring(onLeave), tostring(onMouseDown), tostring(onMouseUp), tostring(onMouseWheel))
			element[msg](element, msg, child, onEnter, onLeave, onMouseDown, onMouseUp, onMouseWheel)
		end
	end
end
local function ElementGUIDUpdateHandler(self, msg, guid, ...)
	for i = 1, #self do
		local element = self[i]
		if type(element) == "table" and type(element[msg]) == "function" then
			element[msg](element, msg, guid, ...)
		end
	end
end
local function ElementBrezHandler(self, msg, brezCount, ...)
	for i = 1, #self do
		local element = self[i]
		if type(element) == "table" and type(element[msg]) == "function" then
			element[msg](element, msg, brezCount, ...)
		end
	end
end
Elements[MESSAGES.DISPLAY_CREATE] 		= ElementDisplayHandler
Elements[MESSAGES.DISPLAY_CD_LOST]		= ElementDisplayHandler
Elements[MESSAGES.DISPLAY_DELETE] 		= ElementDisplayHandler
Elements[MESSAGES.DISPLAY_MODIFY] 		= ElementDisplayHandler
Elements[MESSAGES.DISPLAY_BUFF_EXPIRE] 	= ElementDisplayHandler
Elements[MESSAGES.DISPLAY_USE] 			= ElementDisplayHandler
Elements[MESSAGES.DISPLAY_READY] 		= ElementDisplayHandler
Elements[MESSAGES.DISPLAY_RESET] 		= ElementDisplayHandler
Elements[MESSAGES.DISPLAY_SHOW] 		= ElementDisplayHandler
Elements[MESSAGES.DISPLAY_HIDE] 		= ElementDisplayHandler
Elements[MESSAGES.DISPLAY_COLOR_UPDATE] = ElementDisplayHandler

Elements[MESSAGES.DISPLAY_GROUP_ADD]	= ElementDisplayGroupHandler
Elements[MESSAGES.DISPLAY_GROUP_REMOVE]	= ElementDisplayGroupHandler
Elements[MESSAGES.DISPLAY_GROUP_RESIZE]	= ElementDisplayGroupHandler

Elements[MESSAGES.DISPLAY_TEXT_GROUP_ADD]		= ElementTextBehaviorHandler
Elements[MESSAGES.DISPLAY_TEXT_GROUP_REMOVE]	= ElementTextBehaviorHandler

Elements[MESSAGES.GUID_JOIN]			= ElementGUIDUpdateHandler
Elements[MESSAGES.GUID_LEAVE]			= ElementGUIDUpdateHandler
Elements[MESSAGES.GUID_CHANGE_SPEC] 	= ElementGUIDUpdateHandler
Elements[MESSAGES.GUID_CHANGE_TALENT] 	= ElementGUIDUpdateHandler
Elements[MESSAGES.GUID_CHANGE_GLYPH] 	= ElementGUIDUpdateHandler
Elements[MESSAGES.GUID_CHANGE_PET] 		= ElementGUIDUpdateHandler
Elements[MESSAGES.GUID_CHANGE_DEAD] 	= ElementGUIDUpdateHandler
Elements[MESSAGES.GUID_CHANGE_ONLINE] 	= ElementGUIDUpdateHandler
Elements[MESSAGES.GUID_CHANGE_BENCHED] 	= ElementGUIDUpdateHandler

Elements[MESSAGES.BREZ_ACCEPT]			= ElementBrezHandler
Elements[MESSAGES.BREZ_RESET]			= ElementBrezHandler
Elements[MESSAGES.BREZ_OUT]				= ElementBrezHandler

do 
	Elements.RegisterMessage = addon.RegisterMessage
	Elements.UnregisterMessage = addon.UnregisterMessage
end

-- register element with a specific priority (lower is higher)
function Elements:Register(element, priority)
	if not self._registry[element] and type(element) == "table" then
		priority = priority or #self -- default to lowest priority
		insert(self, priority, element)
		self._registry[element] = true
	end
end

function Elements:Unregister(element)
	if self._registry[element] then
		local idx
		for i = 1, #self do
			if self[i] == element then
				idx = i
				break
			end
		end
		remove(self, idx)
		self._registry[element] = nil
	end
end

function Elements:Initialize()
	addon:FUNCTION("Elements:Initialize()")
	
	-- TODO? just register all messages in MESSAGES or maybe MESSAGES.DISPLAY
	self:RegisterMessage(MESSAGES.DISPLAY_CREATE)
	self:RegisterMessage(MESSAGES.DISPLAY_CD_LOST)
	self:RegisterMessage(MESSAGES.DISPLAY_DELETE)
	self:RegisterMessage(MESSAGES.DISPLAY_MODIFY)
	self:RegisterMessage(MESSAGES.DISPLAY_BUFF_EXPIRE)
	self:RegisterMessage(MESSAGES.DISPLAY_USE)
	self:RegisterMessage(MESSAGES.DISPLAY_READY)
	self:RegisterMessage(MESSAGES.DISPLAY_RESET)
	self:RegisterMessage(MESSAGES.DISPLAY_SHOW)
	self:RegisterMessage(MESSAGES.DISPLAY_HIDE)
	self:RegisterMessage(MESSAGES.DISPLAY_COLOR_UPDATE)
	self:RegisterMessage(MESSAGES.DISPLAY_GROUP_ADD)
	self:RegisterMessage(MESSAGES.DISPLAY_GROUP_REMOVE)
	self:RegisterMessage(MESSAGES.DISPLAY_GROUP_RESIZE)
	
	self:RegisterMessage(MESSAGES.DISPLAY_TEXT_GROUP_ADD)
	self:RegisterMessage(MESSAGES.DISPLAY_TEXT_GROUP_REMOVE)
	
	-- probably don't need most these
	self:RegisterMessage(MESSAGES.GUID_JOIN)
	self:RegisterMessage(MESSAGES.GUID_LEAVE)
	self:RegisterMessage(MESSAGES.GUID_CHANGE_SPEC)
	self:RegisterMessage(MESSAGES.GUID_CHANGE_TALENT)
	self:RegisterMessage(MESSAGES.GUID_CHANGE_GLYPH)
	self:RegisterMessage(MESSAGES.GUID_CHANGE_PET)
	self:RegisterMessage(MESSAGES.GUID_CHANGE_DEAD)
	self:RegisterMessage(MESSAGES.GUID_CHANGE_ONLINE)
	self:RegisterMessage(MESSAGES.GUID_CHANGE_BENCHED)
	--
	
	self:RegisterMessage(MESSAGES.BREZ_ACCEPT)
	self:RegisterMessage(MESSAGES.BREZ_RESET)
	self:RegisterMessage(MESSAGES.BREZ_OUT)
    
    -- run any element-specific initialization
	for i = 1, #self do
		local element = self[i]
		if type(element) == "table" and type(element.Initialize) == "function" then
			element:Initialize()
		end
	end
end

function Elements:Shutdown()
	addon:FUNCTION("Elements:Shutdown()")
	
	self:UnregisterMessage(MESSAGES.DISPLAY_CREATE)
	self:UnregisterMessage(MESSAGES.DISPLAY_CD_LOST)
	self:UnregisterMessage(MESSAGES.DISPLAY_DELETE)
	self:UnregisterMessage(MESSAGES.DISPLAY_MODIFY)
	self:UnregisterMessage(MESSAGES.DISPLAY_BUFF_EXPIRE)
	self:UnregisterMessage(MESSAGES.DISPLAY_USE)
	self:UnregisterMessage(MESSAGES.DISPLAY_READY)
	self:UnregisterMessage(MESSAGES.DISPLAY_RESET)
	self:UnregisterMessage(MESSAGES.DISPLAY_SHOW)
	self:UnregisterMessage(MESSAGES.DISPLAY_HIDE)
	self:UnregisterMessage(MESSAGES.DISPLAY_COLOR_UPDATE)
	self:UnregisterMessage(MESSAGES.DISPLAY_GROUP_ADD)
	self:UnregisterMessage(MESSAGES.DISPLAY_GROUP_REMOVE)
	self:UnregisterMessage(MESSAGES.DISPLAY_GROUP_RESIZE)
	
	self:UnregisterMessage(MESSAGES.DISPLAY_TEXT_GROUP_ADD)
	self:UnregisterMessage(MESSAGES.DISPLAY_TEXT_GROUP_REMOVE)
	
	self:UnregisterMessage(MESSAGES.GUID_JOIN)
	self:UnregisterMessage(MESSAGES.GUID_LEAVE)
	self:UnregisterMessage(MESSAGES.GUID_CHANGE_SPEC)
	self:UnregisterMessage(MESSAGES.GUID_CHANGE_TALENT)
	self:UnregisterMessage(MESSAGES.GUID_CHANGE_GLYPH)
	self:UnregisterMessage(MESSAGES.GUID_CHANGE_PET)
	self:UnregisterMessage(MESSAGES.GUID_CHANGE_DEAD)
	self:UnregisterMessage(MESSAGES.GUID_CHANGE_ONLINE)
	self:UnregisterMessage(MESSAGES.GUID_CHANGE_BENCHED)
	
	self:UnregisterMessage(MESSAGES.BREZ_ACCEPT)
	self:UnregisterMessage(MESSAGES.BREZ_RESET)
	self:UnregisterMessage(MESSAGES.BREZ_OUT)
    
    -- run any element-specific shutdown
	for i = 1, #self do
		local element = self[i]
		if type(element) == "table" and type(element.Initialize) == "function" then
			element:Shutdown()
		end
	end
end
