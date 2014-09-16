
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
    spellCD:Use(0) -- passing 0 should skip saving the state
end

local function GetSpellCD(spellid, guid)
    return Cooldowns[spellid] and Cooldowns[spellid][guid]
end

function Testing:CastSpell(spellid, cast)
    local playerGUID = addon.playerGUID
    if Spawned[spellid] then
        local spellCD = GetSpellCD(spellid, playerGUID)
        if spellCD then
            if type(cast) == "number" then
                addon:TEST("Casting %s in %s...", tostring(spellCD), SecondsToString(cast))
                addon:ScheduleTimer(CastSpell, cast, spellCD)
            else
                CastSpell(spellCD)
            end
        end
    elseif GetSpellCD(spellid, playerGUID) then
        addon:TEST("Attempted to cast non test-spawned spell, %s (%d)", GetSpellInfo(spellid), spellid)
    else
        addon:TEST("No such spell, %s (%d), to cast!", GetSpellInfo(spellid), spellid)
    end
end

function Testing:SpawnSpell(spellid)
    local playerGUID = addon.playerGUID
    if GetSpellCD(spellid, playerGUID) then
        -- don't potentially squash a real spell with a test one
        return Spawned[spellid] and true or false
    end
    
    local class = addon:GetSpellIdClass(spellid)
    local spellData = addon:GetCooldownDataFor(class, spellid)
    if not spellData then
        addon:TEST("Attempted to spawn spell with no data, %s (%d)", GetSpellInfo(spellid), spellid)
        return
    end
    
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
    local spellCD = GetSpellCD(spellid, guid)
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
        elseif GetSpellCD(spellid, playerGUID) then
            addon:TEST("Attempted to reset non test-spawned spell, %s (%d)", GetSpellInfo(spellid), spellid)
        else
            addon:TEST("No such spell, %s (%d), to reset!", GetSpellInfo(spellid), spellid)
        end
    end
end

local function DestroySpell(spellid, guid)
    local spellCD = GetSpellCD(spellid, guid)
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
        if Spawned[spellid] then
            DestroySpell(spellid, playerGUID)
        elseif GetSpellCD(spellid, playerGUID) then
            addon:TEST("Attempted to remove non test-spawned spell, %s (%d)", GetSpellInfo(spellid), spellid)
        else
            addon:TEST("No such spell, %s (%d), to remove!", GetSpellInfo(spellid), spellid)
        end
    end
end

-- ------------------------------------------------------------------
-- Brez testing
-- this is only useful for dev/debugging, but I don't think there is a reason to hide it in release
-- ------------------------------------------------------------------
local function SpawnBrezSpells()
    addon:TEST("Spawning brez spells...")
    local spellToCast
    for spellid in next, BREZ_IDS do
        local spellCD = Testing:SpawnSpell(spellid)
        spellToCast = type(spellCD) == "table" and spellCD or spellToCast
    end
    return spellToCast
end

local fakeBrezTimer
local BREZ_RECHARGE_DURATION = 15
local rechargeDuration = 1
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
    local delay = random(1 + rechargeDuration, 1.5 * rechargeDuration)
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
            addon:DisableBrezSaveState()
            -- fake instance group size
            cachedInstanceGroupSize = addon.instanceGroupSize
            rechargeDuration = groupSize and GroupSizePerRecharge(groupSize) or BREZ_RECHARGE_DURATION
            addon.instanceGroupSize = groupSize or GroupSizePerRecharge(rechargeDuration)
        
            addon:TEST("Testing brez: groupSize=%d (recharge=%s)", addon.instanceGroupSize, SecondsToString(rechargeDuration))
            
            -- fake an encounter
            wasFightingBoss = addon.isFightingBoss
            addon.isFightingBoss = true
            addon:EnableBrezScan()
            fakeBrezTimer = addon:ScheduleTimer(FakeBrezAccept, BREZ_CAST_DELAY + 0.1)
        end
    end
end

function Testing:FinishBrez()
    addon:DisableBrezScan()
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
    -- TODO: revert to brez cached state (just brezCount?)
    addon:EnableBrezSaveState()
end
