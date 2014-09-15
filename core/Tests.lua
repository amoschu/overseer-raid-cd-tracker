
local tostring, type, random, next, wipe
    = tostring, type, random, next, wipe
local GetSpellInfo
    = GetSpellInfo

local addon = Overseer

local consts = addon.consts
local classes = consts.classes
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
local Spawned = {
    --[[
    all spawned spellids
    
    form:
    [spellid] = true,
    ...
    --]]
}
Testing.Spawned = Spawned

local function CastSpell(spellCD)
    addon:TEST("Casting %s", tostring(spellCD))
    local spellid = spellCD.spellid
    local spellname = GetSpellInfo(spellCD.spellid)
    addon:UNIT_SPELLCAST_SUCCEEDED(nil, "player", spellname, _, _, spellid)
    -- TODO: skip save state
end

function Testing:CastSpell(spellid, cast)
    if Spawned[spellid] then
        local spellCD = Cooldowns[spellid] and Cooldowns[spellid][addon.playerGUID]
        if spellCD then
            if type(cast) == "number" then
                addon:ScheduleTimer(CastSpell, cast, spellCD)
            else
                CastSpell(spellCD)
            end
        end
    end
end

function Testing:SpawnSpell(spellid)
    local playerGUID = addon.playerGUID
    if Cooldowns[spellid] and Cooldowns[spellid][playerGUID] then
        -- don't potentially squash a real spell with a test one
        return
    end
    
    local class = addon:GetSpellIdClass(spellid)
    local spellData = addon:GetCooldownDataFor(class, spellid)
    local cdDuration = spellData[filterKeys.CD]
    local charges = spellData[filterKeys.CHARGES]
    local buffDuration = spellData[filterKeys.BUFF_DURATION]

    -- don't worry about any talent/glyph/etc modifications for testing purposes
    local spellCD = Cooldowns:Add(spellid, addon.playerGUID, cdDuration, charges, buffDuration)
    
    -- flag that this is a spawned spell
    Spawned[spellid] = true
    
    return spellCD
end

local function ResetSpell(spellid, guid)
    local spellCD = Cooldowns[spellid] and Cooldowns[spellid][guid]
    if spellCD then
        addon:TEST("Resetting cooldown for %s", tostring(spellCD))
        spellCD:Reset(true)
    end
end

function Testing:ResetSpell(spellid)
    local playerGUID = addon.playerGUID
    if not spellid then
        for spellid in next, Spawned do
            ResetSpell(spellid, playerGUID)
        end
    else
        if Spawned[spellid] then
            ResetSpell(spellid, playerGUID)
        end
    end
end

local function DestroySpell(spellid, guid)
    local spellCD = Cooldowns[spellid] and Cooldowns[spellid][guid]
    if spellCD then
        addon:TEST("Destroying %s...", tostring(spellCD))
        Cooldowns:Remove(guid, spellid)
        Spawned[spellid] = nil
    end
end

-- ommitting spellid will destroy all spawned spells
function Testing:DestroySpell(spellid)
    local playerGUID = addon.playerGUID
    if not spellid then
        for spellid in next, Spawned do
            DestroySpell(spellid, playerGUID)
        end
        wipe(Spawned)
    else
        if not Spawned[spellid] then
            addon:TEST("Attempted to remove non test-spawned spell, %s (%d)", GetSpellInfo(spellid), spellid)
            return
        end
        DestroySpell(spellid, playerGUID)
    end
end

-- ------------------------------------------------------------------
-- Spell testing mode - TODO: REMOVE?
-- ------------------------------------------------------------------
local CachedCooldowns = {
    --[[
    copy of Cooldowns table before starting testing mode
    --]]
}

local CopyTable(tbl, cpy)
    cpy = cpy or {}
    for k, v in next, tbl do
        if type(v) == "table" then
            cpy[k] = CopyTable(v)
        else
            cpy[k] = v
        end
    end
    return cpy
end

local CacheCooldownState()
    wipe(CachedCooldowns)
    for spellid, spells in next, Cooldowns do
        if type(spells) == "table" then
            for guid, spellCD in next, spells do
                CachedCooldowns[spellid] = CachedCooldowns[spellid] or {}
                CachedCooldowns[spellid][guid] = CopyTable(spellCD)
            end
        end
    end
end

function Testing:Start()
--[[ TODO: testing mode
        - cache current state: Cooldowns, GroupCache?, SavedState? (more?)
        - set bench group (need?)
        - pause inspects
        - delay all relevant events until testing mode finished
            may need to stagger firing these delayed events
--]]

    -- delay relevant events -> does this work? GetTime() won't be accurate..
    --[[
        -> what is this point of this?
        how is this useful?
        only practical use for spawning is to spawn a spell that does not currently have a display
        (mostly for unlocking..)
    --]]

    -- cache the cooldown state
    CacheCooldownState()
    Cooldowns:Wipe()
    
    -- spawn some spells
    addon:TEST("Spawning spells...")
    for _, class in next, classes do
        local ids = addon:GetClassSpellIdsFromData(class)
        if type(ids) == "table" then
            for spellid in next, ids do
                if not self:SpawnSpell(spellid) then
                    addon:TEST("> Failed to spawn %s (it already exists)", GetSpellInfo(spellid))
                end
            end
        end
    end
    
    -- start casting at random
end

function Testing:Finish()
--[[
    - drop testing state
    - pop cached state
--]]
end

-- ------------------------------------------------------------------
-- Brez testing
-- this is only useful for dev/debugging, but I don't think there is a reason to hide it in release
-- ------------------------------------------------------------------
local function SpawnBrezSpells()
    addon:TEST("Spawning brez spells...")
    local spellToCast
    for spellid in next, BREZ_IDS do
        spellToCast = Testing:SpawnSpell(spellid) or spellToCast
    end
    return spellToCast
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
    local delay = random(1 + BREZ_RECHARGE_DURATION, 1.5 * BREZ_RECHARGE_DURATION)
    addon:TEST("Next brez test in %s", SecondsToString(delay))
    fakeBrezTimer = addon:ScheduleTimer(FakeBrezAccept, delay)
end

local function GroupSizePerRecharge(duration)
    return 60 * 90 / duration -- TODO: read this from Resurrects.lua in case the charge regen formula changes
end

local cachedInstanceGroupSize
local wasFightingBoss -- TODO: I don't think this is needed?
local BREZ_CAST_DELAY = 2.5
function Testing:StartBrez(boss, groupSize)
    local brezToCast = SpawnBrezSpells()
    if not brezToCast then
        addon:TEST("Failed to spawn any brez spells!")
    else
        addon:ScheduleTimer(CastSpell, BREZ_CAST_DELAY, brezToCast)
        
        if boss or boss == nil then
            -- fake instance group size
            cachedInstanceGroupSize = addon.instanceGroupSize
            addon.instanceGroupSize = groupSize or GroupSizePerRecharge(BREZ_RECHARGE_DURATION)
            -- fake an encounter
            wasFightingBoss = addon.isFightingBoss
            addon.isFightingBoss = true
            addon:EnableBrezScan()
            addon:ScheduleTimer(FakeBrezAccept, BREZ_CAST_DELAY + 0.1)
        end
    end
end

function Testing:FinishBrez()
    for spellid in next, BREZ_IDS do
        self:DestroySpell(spellid)
    end
    addon:CancelTimer(fakeBrezTimer)
    fakeBrezTimer = nil
    addon.isFightingBoss = wasFightingBoss
    wasFightingBoss = nil
    if cachedInstanceGroupSize then
        addon.instanceGroupSize = cachedInstanceGroupSize
    end
    -- TODO: revert to brez cached state
    self:WipeSavedBrezState()
end
