
local tostring, type, floor
	= tostring, type, math.floor
local UIParent
	= UIParent
	
local addon = Overseer

local consts = addon.consts
local MESSAGES = consts.MESSAGES
local CONSOLIDATED_ID = consts.CONSOLIDATED_ID
local GROUP_ID_INVALID = consts.GROUP_ID_INVALID

local db = {
	--[[
	houses convenience database methods
	the actual database is stored in '.Database'
	--]]
}
addon.db = db

-- ------------------------------------------------------------------
-- Init
-- ------------------------------------------------------------------
local defaults = {}
local spellDefaults = {}
do -- setup default table
	local LSM = LibStub("LibSharedMedia-3.0")
	local MediaType = LSM.MediaType
	
	local ESC_SEQUENCES = consts.ESC_SEQUENCES
	local GROUP_TYPES = consts.GROUP_TYPES
	
	spellDefaults = { -- default settings for all spellids
		consolidated = nil, -- index to consolidated display group if the spell
		name = nil, -- displayed name (nil means use spell name)
		shown = true, -- whether the display is shown
		hide = { -- hide events
			dead = false,
			offline = false,
			benched = true,
		},
		unique = false,
		-- position information
		point = "CENTER",
		relFrame = nil,
		relPoint = "LEFT",
		x = 150,
		y = 0,
		--
		-- TODO: hide conditions
		-- frame information
		alpha = 1.0,
		scale = 1.0,
		strata = "BACKGROUND",
		frameLevel = 2, -- min value needs to be 2 (icons use db.frameLevel-1, border frame uses -2)
		--
		mouseFeedback = true,
		font = { -- default font settings
			font = LSM:Fetch(MediaType.FONT, "Friz Quadrata TT"),
			size = 12,
			flags = "OUTLINE",
			r = 1.0,
			g = 1.0,
			b = 1.0,
			notUsableR = 0.6,
			notUsableG = 0.6,
			notUsableB = 0.6, -- TODO: colors for dead/offl/benched/oncd
			shadow = false,
			shadowX = 2,
			shadowY = -2,
			shadowR = 0,
			shadowG = 0,
			shadowB = 0,
			shadowA = 1,
			justifyH = "LEFT",
			justifyV = "CENTER",
			useClassColor = false,
		}, --
		icon = { -- TODO? allow user to turn off icons? displayGroup logic becomes super shitty with bars
			shown = true,
			desatIfUnusable = true, -- TODO: give these more options desat on.. 'X'
			showBuffDuration = true,
			cooldown = false, -- show cooldown sweep
			autoCrop = true, -- try to set the texCoords based on current icon dimension
			width = 32,
			height = 20,
			border = {
				shown = true,
				size = 1,
				r = nil,
				g = nil,
				b = nil,
				a = nil,
				useClassColor = true,
			},
		},
		bar = { -- TODO? allow always-visible bars? I think this requires a non-libcandybar implementation
			shown = true,
			showBuffDuration = true, -- only applies to spells with buff durations defined
			cooldown = true, -- show bar for cooldown duration
			limit = 1, -- limit of bars that can run simultaneously (0 means no limit)
			grow = "LEFT", -- only applies to unique bars
			fill = false,
			texture = LSM:Fetch(MediaType.STATUSBAR, "Hal M"),
			orientation = "VERTICAL",
			fitIcon = true,
			side = "LEFT",
			shrink = 1, -- amount of pixels to shrink the fit dimension (based on 'fitIcon' and 'side')
			width = 5,
			height = 5, -- based on 'fitIcon' and 'side', one of the dimensions will not be considered
			spacing = 3,
			x = -3,
			y = 0,
			iconShown = false,
			bar = {
				useClassColor = true,
				r = 1.0,
				g = 1.0,
				b = 1.0,
				a = 1.0,
				enableBuffColor = true,
				buffR = 0.0,
				buffG = 1.0,
				buffB = 0.0,
				buffA = 1.0,
			},
			bg = {
				useClassColor = false,
				r = 0.5,
				g = 0.5,
				b = 0.5,
				a = 0.7,
			},
			label = {
				shown = false,
				useClassColor = false,
				justifyH = "LEFT",
				justifyV = "BOTTOM",
				x = 0,
				y = 0,
			},
			duration = {
				shown = true,
				showOnlyFirst = true, -- don't show multiple duration texts
				useClassColor = false,
				size = 14,
				justifyH = "CENTER",
				justifyV = "BOTTOM",
				movesWithBar = true,
				x = 1,
				y = 1,
			},
		},
		texts = {
			{ -- number of cooldowns that can be casted
				enabled = true,
				groupText = false,
				point = "BOTTOMRIGHT",
				relPoint = "BOTTOMRIGHT",
				x = 4,
				y = 0,
				-- value = ESC_SEQUENCES.NUM_READY,
				value = ESC_SEQUENCES.NUM_CASTABLE,
				size = 20,
				r = 0.0,
				g = 1.0,
				b = 0.0,
				justifyH = "RIGHT",
				useClassColor = false,
			},
			{ -- list of people who can cast spell or first on cd if none
				enabled = true,
				groupText = false,
				point = "BOTTOMLEFT",
				relPoint = "BOTTOMRIGHT",
				x = 3,
				y = -2,
				-- value = ESC_SEQUENCES.NAMES_READY .. "%{if=0, "..ESC_SEQUENCES.NAMES_FIRST_TO_EXPIRE.."}",
				value = ESC_SEQUENCES.NAMES_USABLE .. "%{if=0, "..ESC_SEQUENCES.NAMES_FIRST_TO_EXPIRE.."}",
				size = 14,
				useClassColor = true,
			},
			{ -- caster of active buff
				enabled = true,
				groupText = false,
				point = "TOPLEFT",
				relPoint = "TOPRIGHT",
				x = 3,
				y = 5,
				value = ESC_SEQUENCES.NAMES_MOST_RECENT_ACTIVE,
				size = 14,
				useClassColor = true,
			},
		},
	}
	
	defaults.profile = {
		-- TODO: hide when out of combat and/or out of boss fight?
		clampedToScreen = true,
		showWelcomeMessage = true,
		minWidth = 18,
		minHeight = 18,
		spells = {
			["**"] = spellDefaults,
			
			-- override ankh text to be more useful
			[20608] = {
				texts = {
					{ -- number of cooldowns ready
						value = ESC_SEQUENCES.NUM_READY,
					},
					{ -- names list
						value = ESC_SEQUENCES.NAMES_READY,
					},
					{ -- first on cd
						enabled = false,
					},
				},
			},
			
			-- merge combat rezzes into a single display
			[61999] = { -- dk raise ally
				consolidated = CONSOLIDATED_ID:format(1),
			},
			[20484] = { -- druid rebirth
				consolidated = CONSOLIDATED_ID:format(1),
			},
			[126393] = { -- hunter quillen eternal guardian
				consolidated = CONSOLIDATED_ID:format(1),
			},
			[113269] = { -- paladin holy symbiosis rebirth
				consolidated = CONSOLIDATED_ID:format(1),
			},
			[20707] = { -- warlock soulstone
				consolidated = CONSOLIDATED_ID:format(1),
			},
		},
	}
	
	defaults.profile.spells.consolidated = {
		--[[
			these define a grouping of spells to be shown under the same display
				note: they are distinct from a positional grouping of spells
			consolidated settings are treated the same as single spells
			single spells point to the group to which they belong
			they otherwise follow the above form
		--]]
		["**"] = defaults.profile.spells["**"],
		[CONSOLIDATED_ID:format(1)] = {
			--[[
			spellids = {
				-- list of all ids encountered which are consolidated into this db
				-- (filled dynamically)
				-- [spellid] = true,
			},
			--]]
			name = "bRez",
			texts = {
				{
					value = ESC_SEQUENCES.NUM_BREZ,
				},
				{
					point = "TOPLEFT",
					relPoint = "TOPRIGHT",
					value = ESC_SEQUENCES.NAMES_USABLE,
				},
				{ -- first on cd
					enabled = false,
				},
			},
		},
	}
	
	local GROUP_ID = consts.GROUP_ID
	defaults.profile.groups = {
		["**"] = {
			--[[
			children = {
				-- children of this group - either other groups or spellids
				[groupId or spellid] = true,
				[groupId or spellid] = true,
				...
			},
			--]]
			id = GROUP_ID_INVALID, -- unique id of the group (needed to avoid spellid clashes and to determine if the db table exists in SV)
			name = nil, --"<Unnamed Group>",
			point = "CENTER",
			relFrame = nil,
			relPoint = "LEFT",
			x = 150,
			y = 0,
			dynamic = {
				-- a non-dynamic group simply keeps relative positional information
				-- vs. a dynamic group which will position its children based on the group's type
				enabled = true,
				-- SIDE, RADIAL, GRID
				type = GROUP_TYPES.SIDE, -- specifies how to arrange displays
				[GROUP_TYPES.SIDE] = {
					-- this is actually just a special case of the "GRID" type where the relevant dimension is infinite
					-- however, not separating the two types may be confusing to the user (or, at least, not apparent how to accomplish)
					grow = "TOP", -- LEFT, RIGHT, TOP, BOTTOM
					spacing = 8,
				},
				[GROUP_TYPES.GRID] = {
					grow = "RIGHT", -- growth direction
					wrap = "TOP", -- wrap direction (if grow is LEFT or RIGHT, then wrap can be TOP or BOTTOM and vice versa)
					spacingX = 5,
					spacingY = 5,
					rows = 3, -- 0 means no limit
					cols = 3, -- based on 'grow', only one dimension is used (eg, if grow="RIGHT" then 'rows' is ignored)
				},
				[GROUP_TYPES.RADIAL] = {
					grow = "CLOCKWISE", -- CLOCKWISE, COUNTERCLOCKWISE
					radius = 10,
					startAngle = 0, -- (rads) starting angle along the circle
					endAngle = 0, -- (rads) ending angle along the circle - if endPt == origin, then the entire circle is used
				},
			},
			texts = {
				-- group text settings
				{
				},
				{
				},
				{
				},
			},
		},
		
		--[[
		default groups
		--]]
		
		[GROUP_ID:format(1)] = { -- raid cds
			id = GROUP_ID:format(1),
			name = "Raid CDs",
			children = {
				[76577] = 1, -- bomb
				[31821] = 2, -- devo
				[97462] = 3, -- rally
				[114203] = 4, -- demo banner
				[62618] = 5, -- barrier
				[98008] = 6, -- link
				[115213] = 7, -- avert harm
				[51052] = 8, -- amz
				[115310] = 9, -- revival
				[64843] = 10, -- divine hymn
				[740] = 11, -- tranq
				[113277] = 12, -- symbiosis tranq (spriest)
				[108280] = 13, -- healing tide
				[108281] = 14, -- ancestral guidance
				[15286] = 15, -- vamp embrace
				[115176] = 16, -- zen med
			},
		},
		[GROUP_ID:format(2)] = { -- external cds
			id = GROUP_ID:format(2),
			name = "External CDs",
            dynamic = {
                type = GROUP_TYPES.GRID,
            },
			children = {
				[33206] = 1, -- pain sup
				[114030] = 2, -- vigi
				[102342] = 3, -- iron bark
				[6940] = 4, -- sac
				[47788] = 5, -- guardian spirit
				[116849] = 6, -- life cocoon
				[114039] = 7, -- purity
				[633] = 8, -- loh
				[1022] = 9, -- bop
				
				-- TODO: TMP
				--[31821] = -1, -- devo
				[85499] = -2, -- speed of light
				--
			},
		},
		[GROUP_ID:format(3)] = { -- movement cds
			id = GROUP_ID:format(3),
			name = "Movement CDs",
			children = {
				[106898] = 1, -- stampeding roar
				[122294] = 2, -- stampeding shout (dps warrior symbiosis)
				[108273] = 3, -- windwalk
				[1044] = 4, -- bof
			},
		},
		[GROUP_ID:format(4)] = { -- dps cds
			id = GROUP_ID:format(4),
			name = "DPS CDs",
			children = {
				[120668] = 1, -- stormlash
				[114207] = 2, -- skull banner
				[64382] = 3, -- shattering throw
			},
		},
		[GROUP_ID:format(5)] = { -- mana cds
			id = GROUP_ID:format(5),
			name = "Mana CDs",
			children = {
				[64901] = 1, -- hymn of hope
				[16190] = 2, -- mana tide
				[29166] = 3, -- innervate
			},
		},
	}
end

local function LoadUserDefaults()
	-- override the hard-coded defaults with user specified defaults
	-- note: this prevents any change to the hard-coded defaults from being reflected in-game (if there are saved changes to the defaults)
	local userDefaults = db:GetProfile().spells["**"]
	if userDefaults then
		defaults.profile.spells["**"] = userDefaults
		db.Database:RegisterDefaults(defaults)
	end
end

local function RestoreHardCodedDefaults()
	defaults.profile.spells["**"] = spellDefaults
	db.Database:RegisterDefaults(defaults)
end

function addon:InitializeDatabase()
	if not db.Database then
		db.Database = LibStub("AceDB-3.0"):New("OverseerDB", defaults, true)
		
if false then -- TODO: DELETE ..when the time is right!! (this is probably going to be one of those comments that made me laugh when I wrote it but when I re-read it makes me go 'wtf is this')
		LoadUserDefaults()
		-- TODO: prune the database of any group tables where .id==GROUP_ID_INVALID
end --
		
		local function OnProfileUpdate()
			LoadUserDefaults()
			addon:SendMessage(MESSAGES.PROFILE_UPDATE)
		end
		db.Database.RegisterCallback(self, "OnProfileChanged", OnProfileUpdate)
		db.Database.RegisterCallback(self, "OnProfileCopied", OnProfileUpdate)
		db.Database.RegisterCallback(self, "OnProfileReset", OnProfileUpdate)
		
		GetDefaults = nil
	end
end

-- ------------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------------
local function GetDatabase()
	return addon.db.Database
end

-- ------------------------------------------------------------------
-- Lookup
-- ------------------------------------------------------------------
function db:GetProfile()
	return GetDatabase().profile
end

function db:GetGroupOptions(key)
	local groupDB = self:GetProfile().groups
	return key and groupDB[key] or groupDB
end

function db:GetConsolidatedKey(key)
	local profile = self:GetProfile()
	local options = profile.spells[key]
	return options and options.consolidated
end

-- get the corresponding settings table for the given display key
function db:GetDisplaySettings(key)
	local profile = self:GetProfile()
	local options = profile.spells[key]
	local consolidated = options.consolidated and profile.spells.consolidated[options.consolidated]
	if consolidated then
		-- TODO: this does not need to be saved to file..
		-- also, this misses spellids that have not been encountered (which should not matter.. at least not yet)
		consolidated.spellids = consolidated.spellids or {}
		consolidated.spellids[key] = true
	end
	
	-- look for consolidated settings first; fallback to single-spell settings
	return consolidated or options
end

function db:LookupPosition(key)
	local settings
	if type(key) == "number" then
		settings = self:GetDisplaySettings(key)
	else
		settings = self:GetGroupOptions(key)
	end
	
	if settings then
		local point = settings.point
		local relFrame = settings.relFrame and _G[settings.relFrame]
		local relPoint = settings.relPoint
		local x, y = settings.x, settings.y
		
		return point, relFrame, relPoint, x, y
	else
		local msg = "db:LookupPosition(%s) - failed to retreive settings.."
		addon:Debug(msg:format(tostring(key)))
		
		return "CENTER", 0, 0
	end
end

function db:LookupFont(fontDB, key, fontKey) -- for "convenience", but not actually all that convenient
	local result = fontDB[fontKey]
	if result == nil then
		local fonts = GetDatabase().profile.spells[key].font
		result = fonts[fontKey]
	end
	return result
end

-- ------------------------------------------------------------------
-- Save
-- ------------------------------------------------------------------
function db:SavePosition(key, frame)
	local settings
	if type(key) == "number" then
		settings = self:GetDisplaySettings(key)
	else
		settings = self:GetGroupOptions(key)
	end
	
	if settings then
		local point, relFrame, relPoint, x, y = frame:GetPoint()
		settings.point = point
		settings.relFrame = relFrame and relFrame.GetName and relFrame:GetName()
		settings.relPoint = relPoint
		settings.x = x
		settings.y = y
	else
		local msg = "db:SavePosition(%s) - failed to retreive settings table.."
		addon:Debug(msg:format(tostring(key)))
	end
	
	-- TODO: this can fail..? (lookup position can spit out nils or possibly junk?)
end

function db:SaveIconSize(key, width, height)
	local icon = GetDatabase().profile.spells[key].icon
	icon.width = width
	icon.height = height
end
