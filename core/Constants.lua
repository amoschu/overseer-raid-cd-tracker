
local select, type, next, tonumber 
	= select, type, next, tonumber

local addon = Overseer
local consts = {}
addon.consts = consts

-- ------------------------------------------------------------------
-- Messages
-- ------------------------------------------------------------------
local MESSAGES = {
	--[[
	message string literals
	mainly, this is the channel through which the core speaks to displays
	the paradigm is core should know nothing about display and display should know as little as possible about core
	--]]
	
	GUID_JOIN = "GUID_JOIN",
	GUID_LEAVE = "GUID_LEAVE",
	GUID_CHANGE_SPEC = "GUID_CHANGE_SPEC",
	GUID_CHANGE_TALENT = "GUID_CHANGE_TALENT",
	GUID_CHANGE_GLYPH = "GUID_CHANGE_GLYPH",
	GUID_CHANGE_PET = "GUID_CHANGE_PET",
	GUID_CHANGE_DEAD = "GUID_CHANGE_DEAD",
	GUID_CHANGE_ONLINE = "GUID_CHANGE_ONLINE",
	GUID_CHANGE_BENCHED = "GUID_CHANGE_BENCHED",

	CD_NEW = "CD_NEW",
	CD_READY = "CD_READY",
	CD_DELETE = "CD_DELETE",
	CD_MODIFIED = "CD_MODIFIED",
	CD_BUFF_EXPIRE = "CD_BUFF_EXPIRE",
	CD_USE = "CD_USE",
	CD_RESET = "CD_RESET",
	
	BOSS_ENGAGE = "BOSS_ENGAGE",
	BOSS_END = "BOSS_END",
	
	BREZ_ACCEPT = "BREZ_ACCEPT",
	BREZ_RESET = "BREZ_RESET",
	BREZ_OUT = "BREZ_OUT", -- TODO: needed?
	
	-- displays send out messages for elements to respond to
	-- the base display frames are invisible which house logic for its constituent elements
	-- displays do not know which elements they control; elements do know the display to which they belong
	-- TODO: this system is somewhat superfluous for displays.. it basically just duplicates every /real/ message
	DISPLAY_CREATE = "DISPLAY_CREATE",
	DISPLAY_CD_LOST = "DISPLAY_CD_LOST",
	DISPLAY_DELETE = "DISPLAY_DELETE",
	DISPLAY_MODIFY = "DISPLAY_MODIFY",
	DISPLAY_BUFF_EXPIRE = "DISPLAY_BUFF_EXPIRE",
	DISPLAY_USE = "DISPLAY_USE",
	DISPLAY_READY = "DISPLAY_READY",
	DISPLAY_RESET = "DISPLAY_RESET",
	DISPLAY_COLOR_UPDATE = "DISPLAY_COLOR_UPDATE",
	DISPLAY_HIDE = "DISPLAY_HIDE",
	DISPLAY_SHOW = "DISPLAY_SHOW",
	
	DISPLAY_GROUP_ADD = "DISPLAY_GROUP_ADD",
	DISPLAY_GROUP_REMOVE = "DISPLAY_GROUP_REMOVE",
	DISPLAY_GROUP_RESIZE = "DISPLAY_GROUP_RESIZE",
	DISPLAY_TEXT_GROUP_ADD = "DISPLAY_TEXT_GROUP_ADD",
	DISPLAY_TEXT_GROUP_REMOVE = "DISPLAY_TEXT_GROUP_REMOVE",
	
	CLASS_COLORS_CHANGED = "CLASS_COLORS_CHANGED",
	PROFILE_UPDATE = "PROFILE_UPDATE",
	OPT_UNIQUE_DISPLAYS = "OPT_UNIQUE_DISPLAYS",
}
consts.MESSAGES = MESSAGES

do -- prefix all messages to avoid any potential message string clashes with other addons
	local prefix = addon:GetName():upper()
	for key, msg in next, MESSAGES do
		MESSAGES[key] = ("%s_%s"):format(prefix, msg)
	end
end

-- ------------------------------------------------------------------
-- Custom text escape sequences
-- ------------------------------------------------------------------
local ESC_SEQUENCES = { -- TODO: change to better escape sequences
	NUM_CASTABLE = "%q", -- number currently castable (alive, online, not benched, off cd) - includes charges
	NUM_READY = "%r", -- number off cooldown
	NUM_NOTREADY = "%R", -- number on cooldown
	NUM_TOTAL_NOT_BENCHED = "%t", -- total number tracked in the instance
	NUM_TOTAL = "%T", -- total number tracked in raid
	NUM_BREZ = "%z", -- number of combat resurrections remaining
	
	NAMES_MOST_RECENT_ACTIVE = "%a", -- name of the person who most recently casted the ability (that is still active)
	NAMES_USABLE = "%u", -- names of players who can currently cast the cd (alive, online, not benched, off cd)
	NAMES_READY = "%n", -- off cooldown
	NAMES_ALL = "%N", -- all tracked names
	NAMES_FIRST_TO_EXPIRE = "%f", -- name of person who owns the first ability to expire
	NAMES_ONCD = "%c", -- list of people who are on cooldown
	NAMES_DEAD = "%d", -- tracked players who are dead
	NAMES_OFFLINE = "%o", -- tracked players who are offline
	NAMES_BENCHED = "%b", -- players that are benched
}
consts.ESC_SEQUENCES = ESC_SEQUENCES

-- ------------------------------------------------------------------
-- Frame widget types
-- ------------------------------------------------------------------
local FRAME_TYPES = {
	-- casing consistent with :GetObjectType()
	FRAME = "Frame",
	BUTTON = "Button",
	COOLDOWN = "Cooldown",
}
consts.FRAME_TYPES = FRAME_TYPES

-- ------------------------------------------------------------------
-- Display constants
-- ------------------------------------------------------------------
local POINT = { -- not named so that these can be looped over with 'for i = 1, #POINT do ... end'
	"TOP",
	"BOTTOM",
	"LEFT",
	"RIGHT",
	"TOPLEFT",
	"TOPRIGHT",
	"BOTTOMLEFT",
	"BOTTOMRIGHT",
}
consts.POINT = POINT

local MBUTTON = { -- mouse buttons
	LEFT = "LeftButton",
	RIGHT = "RightButton",
	MIDDLE = "MiddleButton",
	BUTTON4 = "Button4",
	BUTTON5 = "Button5",
}
consts.MBUTTON = MBUTTON

local GROUP_TYPES = { -- display group types
	SIDE = "SIDE",
	GRID = "GRID",
	RADIAL = "RADIAL",
}
consts.GROUP_TYPES = GROUP_TYPES

consts.CONSOLIDATED_ID = "C_%d"
consts.GROUP_ID = "G_%d"
consts.GROUP_ID_INVALID = consts.GROUP_ID:format(0) -- uninitialized group id
consts.TEXT_ELEMENT_KEY = "textElement_%d"

-- ------------------------------------------------------------------
-- Tracking data constants
-- ------------------------------------------------------------------
consts.FILTER_REQUIRED = "FILTER_REQUIRED"
consts.FILTER_OPTIONAL = "FILTER_OPTIONAL"
consts.FILTER_MOD_VALUE = "FILTER_MOD_VALUE"
consts.FILTER_MOD_OP = "FILTER_MOD_OP" -- modification operator

local filterKeys = {
	CD = "COOLDOWN",
	CHARGES = "CHARGES",
	BUFF_DURATION = "BUFF_DURATION",
	
	[consts.FILTER_OPTIONAL] = {
		SPEC = "SPEC",
		TALENT = "TALENT",
		GLYPH = "GLYPH",
		BUFF = "BUFF",
		ITEM = "ITEM", -- TODO: not used.. yet
		PET = "PET",
	},
}
consts.filterKeys = filterKeys

local itemKeys = { -- TODO: not used.. yet
	HEAD = "HEAD",
	NECK = "NECK",
	SHOULDERS = "SHOULDERS",
	SHIRT = "SHIRT",
	CHEST = "CHEST",
	WAIST = "WAIST",
	LEGS = "LEGS",
	FEET = "FEET",
	WRIST = "WRIST",
	HANDS = "HANDS",
	RINGS = "RINGS",
	TRINKETS = "TRINKETS",
	BACK = "BACK",
	WEAPON = "WEAPON",
	TABARD = "TABARD",
}
consts.itemKeys = itemKeys

local itemToSlot = { -- TODO: not used.. yet
	[itemKeys.HEAD] 		= INVSLOT_HEAD,
	[itemKeys.NECK] 		= INVSLOT_NECK,
	[itemKeys.SHOULDERS] 	= INVSLOT_SHOULDER,
	[itemKeys.SHIRT] 		= INVSLOT_BODY,
	[itemKeys.CHEST] 		= INVSLOT_CHEST,
	[itemKeys.WAIST] 		= INVSLOT_WAIST,
	[itemKeys.LEGS] 		= INVSLOT_LEGS,
	[itemKeys.FEET] 		= INVSLOT_FEET,
	[itemKeys.WRIST]		= INVSLOT_WRIST,
	[itemKeys.HANDS] 		= INVSLOT_HAND,
	[itemKeys.RINGS] 		= { INVSLOT_FINGER1, INVSLOT_FINGER2, },
	[itemKeys.TRINKETS] 	= { INVSLOT_TRINKET1, INVSLOT_TRINKET1, }, -- chances are these are the only items we ever care about
	[itemKeys.BACK] 		= INVSLOT_BACK,
	[itemKeys.WEAPON] 		= { INVSLOT_MAINHAND, INVSLOT_OFFHAND, INVSLOT_RANGED, },
	[itemKeys.TABARD]		= INVSLOT_TABARD,
}
consts.itemToSlot = itemToSlot

consts.EVENT_DELIM = ":"
consts.EVENT_PREFIX_BUCKET = "BUCKET"
consts.EVENT_PREFIX_CLEU = "CLEU"

function addon:EncodeCLEUEvent(event)
	return ("%s%s%s"):format(consts.EVENT_PREFIX_CLEU, consts.EVENT_DELIM, event)
end

function addon:EncodeBucketEvent(event, interval)
	interval = tonumber(interval) or 1
	return ("%s%s%s%s%d"):format(
		consts.EVENT_PREFIX_BUCKET, consts.EVENT_DELIM, event,
		consts.EVENT_DELIM, interval
	)
end

function consts:DecodeEvent(encodedEvent)
	-- encodedEvent should be of the form: "prefix:suffix"
	local delim = encodedEvent:find(self.EVENT_DELIM)
	local prefix = delim and encodedEvent:sub(0, delim-1)
	local suffix = delim and encodedEvent:sub(delim+1)
	
	if prefix == self.EVENT_PREFIX_BUCKET then
		-- special case bucket events to return the interval as the final return
		delim = suffix:find(self.EVENT_DELIM)
		local interval = delim and tonumber(suffix:sub(delim+1))
		suffix = delim and suffix:sub(0, delim-1) or suffix
		
		return prefix, suffix, interval
	end
	
	return prefix, suffix
end

local optionalKeys = filterKeys[consts.FILTER_OPTIONAL]
local eventsByFilter = {
	--[[
	events that are relevant to the keyed filter
	multiple events can be specified per filter as an array
	this table is used to dynamically register & unregister events as needed based on group composition
	
	form:
	WoW events are simply strings (see http://wowprogramming.com/docs/events)
	Bucket events have the form "BUCKET:event:interval" (see the helper above)
	CLEU messages have the form "CLEU:message" (see the helper above)
	--]]
	
	[optionalKeys.SPEC] = "INSPECT_READY",
	[optionalKeys.TALENT] = "INSPECT_READY",
	[optionalKeys.GLYPH] = "INSPECT_READY",
	[optionalKeys.ITEM] = "INSPECT_READY",

	[optionalKeys.BUFF] = {
		addon:EncodeCLEUEvent("SPELL_AURA_APPLIED"),
		addon:EncodeCLEUEvent("SPELL_AURA_REMOVED"),
	},
	
	[optionalKeys.PET] = {
		addon:EncodeBucketEvent("UNIT_PET", 1.5), -- bucket or not, this seems to just fire in bursts
		addon:EncodeCLEUEvent("UNIT_DIED"),
	},
}
consts.eventsByFilter = eventsByFilter

-- ------------------------------------------------------------------
-- Class/Spec
-- ------------------------------------------------------------------
consts.classes = {
	dk = "DEATHKNIGHT",
	druid = "DRUID",
	hunter = "HUNTER",
	mage = "MAGE",
	monk = "MONK",
	paladin = "PALADIN",
	priest = "PRIEST",
	rogue = "ROGUE",
	shaman = "SHAMAN",
	warlock = "WARLOCK",
	warrior = "WARRIOR",
}

local classes = consts.classes
-- http://wowprogramming.com/docs/api_types#specID
consts.specs = {
	[classes.dk] = {
		["Blood"] = 250,
		["Frost"] = 251,
		["Unholy"] = 252,
	},
	[classes.druid] = {
		["Balance"] = 102,
		["Feral"] = 103,
		["Guardian"] = 104,
		["Restoration"] = 105,
	},
	[classes.hunter] = {
		["Beast Mastery"] = 253,
		["Marksmanship"] = 254,
		["Survival"] = 255,
	},
	[classes.mage] = {
		["Arcane"] = 62,
		["Fire"] = 63,
		["Frost"] = 64,
	},
	[classes.monk] = {
		["Brewmaster"] = 268,
		["Windwalker"] = 269,
		["Mistweaver"] = 270,
	},
	[classes.paladin] = {
		["Holy"] = 65,
		["Protection"] = 66,
		["Retribution"] = 70,
	},
	[classes.priest] = {
		["Discipline"] = 256,
		["Holy"] = 257,
		["Shadow"] = 258,
	},
	[classes.rogue] = {
		["Assassination"] = 259,
		["Combat"] = 260,
		["Subtlety"] = 261,
	},
	[classes.shaman] = {
		["Elemental"] = 262,
		["Enhancement"] = 263,
		["Restoration"] = 264,
	},
	[classes.warlock] = {
		["Affliction"] = 265,
		["Demonology"] = 266,
		["Destruction"] = 267,
	},
	[classes.warrior] = {
		["Arms"] = 71,
		["Fury"] = 72,
		["Protection"] = 73,
	},
}

do
	local append = addon.TableAppend
	local toAdd = {}

	-- key the values as true in the class table for easier class string verification
	for _, classId in next, classes do
		append(toAdd, classId)
	end
	for i = 1, #toAdd do
		classes[ toAdd[i] ] = true
	end
	wipe(toAdd)
	
	-- similarly, key the spec ids into the spec table
	local specs = consts.specs
	for _, specsForClass in next, specs do
		for _, specId in next, specsForClass do
			append(toAdd, specId)
		end
	end
	for i = 1, #toAdd do
		specs[ toAdd[i] ] = true
	end
end

-- ------------------------------------------------------------------
-- WoW constants
-- ------------------------------------------------------------------
consts.GLYPH_LEVEL_UNLOCK = { 25, 50, 75 }
consts.TALENTS_PER_ROW = 3

consts.NUM_MAX_GROUPS = 8
consts.NUM_PLAYERS_PER_GROUP = 5

consts.ANKH_ID = 20608
consts.SOULSTONE_ID = 20707

local BREZ_IDS = {
	[61999] = true, --dk
	[20484] = true, --druid
	[126393] = true, --hunter
	[113269] = true, --hpal symbiosis
	[20707] = true, --lock
}
consts.BREZ_IDS = BREZ_IDS

-- ------------------------------------------------------------------
-- Misc.
-- ------------------------------------------------------------------
consts.INDENT = "   "
consts.EMPTY = "<|cff999999empty|r>"

consts.MSEC_PER_SEC = 1000
consts.SEC_PER_MIN = 60
consts.MIN_PER_HR = 60
consts.HR_PER_DAY = 24
consts.DAY_IN_SECONDS = consts.SEC_PER_MIN * consts.MIN_PER_HR * consts.HR_PER_DAY
