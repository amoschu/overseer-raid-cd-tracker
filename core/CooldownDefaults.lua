
local addon = Overseer

local consts = addon.consts
local classes = consts.classes
local specs = consts.specs
local filterKeys = consts.filterKeys

local FILTER_REQUIRED = consts.FILTER_REQUIRED
local FILTER_OPTIONAL = consts.FILTER_OPTIONAL
local optionalKeys = filterKeys[FILTER_OPTIONAL]

-- ------------------------------------------------------------------
-- Default cooldowns
-- ------------------------------------------------------------------
function addon:InitializeDefaultCooldowns()
	self:PrintFunction(":InitializeDefaultCooldowns()")
	
-- TODO: TMP --> roll (has different id for chi torpedo and if talent 'celerity' is selected......)
	addon:AddCooldown(109132, classes.monk, 20, 2, nil, -- roll (TODO: TMP) 
		addon:EncodeRequiredData(optionalKeys.TALENT, -18, optionalKeys.TALENT, -1)
	)
	addon:AddCooldown(115008, classes.monk, 20, 2, nil, -- chi torpedo (TODO: TMP)
		addon:EncodeRequiredData(optionalKeys.TALENT, 18, optionalKeys.TALENT, -1)
	)
	addon:AddCooldown(121827, classes.monk, 15, 3, nil, -- roll ..celerity has diff id (TODO: TMP)
		addon:EncodeRequiredData(optionalKeys.TALENT, -18, optionalKeys.TALENT, 1)
	)
	addon:AddCooldown(121828, classes.monk, 15, 3, nil, -- chi torpedo ..celerity has diff id (TODO: TMP)
		addon:EncodeRequiredData(optionalKeys.TALENT, 18, optionalKeys.TALENT, 1)
	)
	addon:AddCooldownFromTalent(85499, classes.paladin, nil, nil, 8, 1) -- speed of light
--

	-- DEATHKNIGHT
	addon:AddCooldown(61999, classes.dk) -- raise ally
	addon:AddCooldownFromTalent(51052, classes.dk, nil, nil, 3, 5) -- anti magic zone
	-- DRUID
	--addon:AddCooldown(29166, classes.druid, nil, nil, 10) -- innervate
	addon:AddCooldown(20484, classes.druid) -- rebirth
	addon:AddCooldown(106898, classes.druid, nil, nil, 8) -- stampeding roar
	addon:AddCooldownFromSpec(740, classes.druid, 3 * 60, nil, 8, specs[classes.druid]["Restoration"]) -- tranquility
	addon:AddCooldownFromSpec(102342, classes.druid, nil, nil, 12, specs[classes.druid]["Restoration"]) -- iron bark
	-- HUNTER - TODO: localization
	addon:AddCooldown(126393, classes.hunter, nil, nil, nil, -- eternal guardian
		addon:EncodeRequiredData(optionalKeys.SPEC, specs[classes.hunter]["Beast Mastery"], optionalKeys.PET, "Quilen")
	)
	-- MAGE
    addon:AddCooldown(159916, classes.mage, nil, nil, 6) -- amplify magic
	-- MONK
	addon:AddCooldown(115176, classes.monk, nil, nil, 8) -- zen meditation
	addon:AddCooldownFromSpec(116849, classes.monk, nil, nil, 12, specs[classes.monk]["Mistweaver"]) -- life cocoon
	addon:AddCooldownFromSpec(115310, classes.monk, nil, nil, nil, specs[classes.monk]["Mistweaver"]) -- revival
	-- PALADIN
	addon:AddCooldown(1038, classes.paladin, nil, nil, 10, nil, -- salv
		{
			[filterKeys.CHARGES] = addon:EncodeModificationData(2, "=", optionalKeys.TALENT, 12),
		}
	)
	addon:AddCooldown(6940, classes.paladin, nil, nil, 12, nil, -- sac
		{
			[filterKeys.CHARGES] = addon:EncodeModificationData(2, "=", optionalKeys.TALENT, 12),
		}
	)
	addon:AddCooldown(1022, classes.paladin, nil, nil, 10, nil, -- bop
		{
			[filterKeys.CHARGES] = addon:EncodeModificationData(2, "=", optionalKeys.TALENT, 12),
		}
	)
	addon:AddCooldown(1044, classes.paladin, nil, nil, 6, nil, -- freedom
		{
			[filterKeys.CHARGES] = addon:EncodeModificationData(2, "=", optionalKeys.TALENT, 12),
		}
	)
	addon:AddCooldown(633, classes.paladin, nil, nil, nil, nil, -- lay on hands
		{
			[filterKeys.CD] = addon:EncodeModificationData(0.5, "*", optionalKeys.TALENT, 11),
		}
	)
	addon:AddCooldownFromTalent(114039, classes.paladin, nil, nil, 6, 10) -- hand of purity
	addon:AddCooldownFromSpec(31821, classes.paladin, nil, nil, 6, specs[classes.paladin]["Holy"], -- devotion aura
		{
			[filterKeys.CD] = addon:EncodeModificationData(60, "-", optionalKeys.GLYPH, 146955),
		}
	)
	-- PRIEST
	addon:AddCooldownFromSpec(15286, classes.priest, nil, nil, 15, specs[classes.priest]["Shadow"], -- vamp embrace
		{
			[filterKeys.BUFF_DURATION] = addon:EncodeModificationData(5, "-", optionalKeys.GLYPH, 120584),
		}
	)
	addon:AddCooldownFromSpec(47788, classes.priest, nil, nil, 10, specs[classes.priest]["Holy"]) -- guardian spirit
	addon:AddCooldownFromSpec(64843, classes.priest, nil, nil, 8, specs[classes.priest]["Holy"]) -- divine hymn
	addon:AddCooldownFromSpec(33206, classes.priest, nil, nil, 8, specs[classes.priest]["Discipline"]) -- pain suppression
	addon:AddCooldownFromSpec(62618, classes.priest, nil, nil, 10, specs[classes.priest]["Discipline"]) -- power word: barrier
	-- ROGUE
	addon:AddCooldown(76577, classes.rogue, nil, nil, 5, nil, -- smoke bomb
		{
			[filterKeys.BUFF_DURATION] = addon:EncodeModificationData(2, "+", optionalKeys.GLYPH, 56819),
		}
	)
	-- SHAMAN
	addon:AddCooldown(20608, classes.shaman) -- ankh
	addon:AddCooldownFromSpec(108280, classes.shaman, nil, nil, 12, specs[classes.shaman]["Restoration"]) -- healing tide
	addon:AddCooldownFromTalent(108281, classes.shaman, nil, nil, 10, 14) -- ancestral guidance
	addon:AddCooldownFromTalent(108273, classes.shaman, nil, nil, 6, 6) -- windwalk
	--addon:AddCooldownFromSpec(16190, classes.shaman, nil, nil, 16, specs[classes.shaman]["Restoration"]) -- mana tide
	addon:AddCooldownFromSpec(98008, classes.shaman, nil, nil, 6, specs[classes.shaman]["Restoration"]) -- spirit link
	-- WARLOCK
	addon:AddCooldown(20707, classes.warlock) -- soulstone
	-- WARRIOR
	addon:AddCooldown(64382, classes.warrior, nil, nil, 10) -- shattering throw
	addon:AddCooldownFromSpec(97462, classes.warrior, nil, nil, 10, -specs[classes.warrior]["Protection"]) -- rallying cry
	addon:AddCooldownFromTalent(114030, classes.warrior, nil, nil, 12, 15) -- vigilance
	
	-- this should only be called a single time
	addon.InitializeDefaultCooldowns = nil
end
