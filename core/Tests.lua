
local tostring, type, random, next
    = tostring, type, random, next
local GetSpellInfo, UnitName
    = GetSpellInfo, UnitName

local addon = Overseer

local consts = addon.consts
local Cooldowns = addon.Cooldowns
local GroupCache = addon.GroupCache
local filterKeys = consts.filterKeys
local SecondsToString = addon.SecondsToString

local MESSAGES = consts.MESSAGES
local BREZ_IDS = consts.BREZ_IDS


local Testing = {
    --[[
    testing namespace
    --]]
}
addon.Testing = Testing

-- ------------------------------------------------------------------
-- Spell testing
-- ------------------------------------------------------------------
local function CastSpell(spellCD)
    addon:TEST("Casting %s", tostring(spellCD))
    local spellid = spellCD.spellid
    local spellname = GetSpellInfo(spellCD.spellid)
    addon:UNIT_SPELLCAST_SUCCEEDED(nil, "player", spellname, _, _, spellid)
    -- TODO: skip save state
end
Testing.CastSpell = CastSpell

function Testing:SpawnSpell(spellid, cast)
    local class = addon:GetSpellIdClass(spellid)
    local spellData = addon:GetCooldownDataFor(class, spellid)
    local cdDuration = spellData[filterKeys.CD]
    local charges = spellData[filterKeys.CHARGES]
    local buffDuration = spellData[filterKeys.BUFF_DURATION]

    -- don't worry about any talent/glyph/etc modifications for testing purposes
    local spellCD = Cooldowns:Add(spellid, addon.playerGUID, cdDuration, charges, buffDuration)
    addon:TEST("Spawning %s...", tostring(spellCD))
    
    if type(cast) == "number" then
        addon:ScheduleTimer(CastSpell, cast, spellCD)
    end
    
    return spellCD
end

function Testing:ResetSpell(spellid)
    if not spellid then
        addon:TEST("Resetting all spell cooldowns")
        Cooldowns:ResetCooldowns(true)
    else
        -- reset single spell
        local spellCD = Cooldowns[spellid] and Cooldowns[spellid][addon.playerGUID]
        if spellCD then
            addon:TEST("Resetting cooldown for %s", tostring(spellCD))
            spellCD:Reset(true)
        end
    end
end

-- if spellid is nil, this will remove all spawned spells
function Testing:DestroySpell(spellid)
    local spellCD = Cooldowns[spellid] and Cooldowns[spellid][addon.playerGUID]
    if spellCD then
        addon:TEST("Destroying %s...", tostring(spellCD))
        Cooldowns:Remove(addon.playerGUID, spellid)
    end
end

-- ------------------------------------------------------------------
-- Brez testing
-- this is only useful for dev/debugging, but I don't think there is a reason to hide it in release
-- ------------------------------------------------------------------
local function SpawnBrezSpells()
    local i = 1
    local r = random(4) -- roll which spell to cast - TODO: programmatically determine #BREZ_IDS
    
    local spellCD -- spell to cast
    for spellid in next, BREZ_IDS do
        -- TODO: check if spawning is required; alternately, don't spawn if a brez exists?
        --      ..maybe follow testing mode flow? (cache->spawn->test)
        local spawnedSpell = Testing:SpawnSpell(spellid)
        if i == r then
            spellCD = spawnedSpell
        else
            i = i + 1
        end
    end
    return spellCD
end

local fakeBrezTimer
local BREZ_RECHARGE_DURATION = 15
local function FakeBrezAccept()
    addon:TEST("brez test go!")
    local playerGUID = addon.playerGUID
    -- fake a death
    addon:AddToDeadList(playerGUID)
    -- fake a brez
    addon:CastBrezOn(playerGUID, playerGUID)
    -- fake an accept
    addon:AcceptBrezFor(playerGUID)
    addon:PauseBrezScan()
    
    -- schedule another in N seconds
    local delay = random(1 + BREZ_RECHARGE_DURATION, 3 * BREZ_RECHARGE_DURATION)
    addon:TEST("Next brez test in %s", SecondsToString(delay))
    fakeBrezTimer = addon:ScheduleTimer(FakeBrezAccept, delay)
end

local function GroupSizePerRecharge(duration)
    return 90 / (duration / 60)
end

local cachedInstanceGroupSize = 5
local BREZ_CAST_DELAY = 2.5
function Testing:StartBrez(nonBoss, groupSize)
    local bRezToCast = SpawnBrezSpells()
    addon:ScheduleTimer(CastSpell, BREZ_CAST_DELAY, bRezToCast)
    
    -- TODO: skip desat and stuff -> turn off option temporarily
    
    if not nonBoss then
        -- fake instance group size
        cachedInstanceGroupSize = addon.instanceGroupSize
        addon.instanceGroupSize = groupSize or GroupSizePerRecharge(BREZ_RECHARGE_DURATION)
        -- fake an encounter
        addon.isFightingBoss = true
        addon:EnableBrezScan()
        addon:ScheduleTimer(FakeBrezAccept, BREZ_CAST_DELAY + 0.1)
    end
end

function Testing:FinishBrez()
    for spellid in next, BREZ_IDS do
        self:DestroySpell(spellid)
    end
    addon:CancelTimer(fakeBrezTimer)
    fakeBrezTimer = nil
    addon.isFightingBoss = nil
    addon.instanceGroupSize = cachedInstanceGroupSize
    -- TODO: revert to brez cached state
end

-- ------------------------------------------------------------------
-- Spell testing mode
-- ------------------------------------------------------------------
function Testing:Start()
--[[ TODO: testing mode
        - cache current state: Cooldowns, GroupCache, SavedState (more?)
        - set bench group
        - pause inspects
        - possibly unregister relevant events (or maybe delay them)
--]]
end

function Testing:Finish()
--[[
    - drop testing state
    - pop cached state
--]]
end
