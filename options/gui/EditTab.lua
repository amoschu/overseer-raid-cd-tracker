
local strsplit, wipe, next, tonumber, tostring, type, insert
    = strsplit, wipe, next, tonumber, tostring, type, table.insert
local GetSpellInfo, UIParent
    = GetSpellInfo, UIParent

local addon = Overseer
local options = addon:GetModule(addon.OPTIONS_MODULE)
local AG = LibStub("AceGUI-3.0")
local ACR = LibStub("AceConfigRegistry-3.0")
local ACD = LibStub("AceConfigDialog-3.0")

local consts = options.consts
local append = addon.TableAppend

local GROUP_ID = addon.consts.GROUP_ID
local CONSOLIDATED_ID = addon.consts.CONSOLIDATED_ID

local valueToText = {
    --[[
    flat table pairing values to their displayed text in the tree
    
    form:
    [value] = "text",
    ...
    --]]
}

-- ------------------------------------------------------------------
-- Tree group construction
-- ------------------------------------------------------------------
--[[
    the tree should take the following form:
    {
        { -- group
            value = groupId,
            text = groupName,
            --icon = ?
            children = {
                {
                    value = spellid,
                    text = spellname,
                    icon = iconPath, (string)
                },
                ...
            },
        },
        ...
        
        { -- merged display
        },
        ...
        
        { -- floater display
            value = spellid,
            text = spellname,
            icon = iconPath,
        },
        ...
    }
--]]
local text = "%s (%d)"
local function CreateSpellEntry(spellid)
    local spellEntry
    local spellname, _, icon = GetSpellInfo(spellid)
    if spellname and icon then
        local db = addon.db:GetSpellSettings(spellid)
        spellEntry = {}
        spellEntry.value = spellid
        spellEntry.text = text:format(db.name or spellname, spellid)
        spellEntry.icon = icon
        
        valueToText[tostring(spellEntry.value)] = spellEntry.text
    end
    return spellEntry
end

local DEFAULT_KEY = addon.db.DEFAULT_KEY
local function CreateDefaultsEntry()
    -- add a special entry for the defaults
    local defaults = {}
    defaults.value = DEFAULT_KEY
    defaults.text = "Default Settings" -- TODO: localization
    --defaults.icon -- TODO: a generic icon for this
    valueToText[defaults.value] = defaults.text
    return defaults
end

local visitedSpellIds = {} -- list of all spellids that have been populated into the tree
local bySpellId = {} -- work table for quicker lookups
local byConsolidatedId = {} -- another work table
local RAID_CLASS_COLORS  = RAID_CLASS_COLORS  -- list of classes
local function PopulateTree()
    --[[
    TODO: this causes a decent amount of unnecessary memory + cpu churn whenever the user changes tabs
        if the user is only switching tabs, chances are this is unneeded except for the initial populate
        instead, update the structure after the initial populate whenever it changes
    --]]
    
    local tree = {}
    local profile = addon.db:GetProfile()
    
    wipe(visitedSpellIds)
    wipe(bySpellId) -- this should already be empty..
    wipe(byConsolidatedId) -- ^
    
    -- populate with spells that already exist in the db
    for spellid, settings in next, profile.spells do
        if type(spellid) == "number" then
            local spellEntry = CreateSpellEntry(spellid)
            if spellEntry then
                if not settings.consolidated then
                    bySpellId[spellid] = spellEntry
                else
                    -- key by spellEntry since the consolidated id will be identical
                    -- first-pass, 'byConsolidatedId' holds [spellEntry table] = consolidatedId pairs
                    byConsolidatedId[spellEntry] = settings.consolidated
                end
            end
            visitedSpellIds[spellid] = true
        elseif spellid == DEFAULT_KEY then
            tree[1] = CreateDefaultsEntry()
        end
    end
    
    -- populate missing spells from data
    for class in next, RAID_CLASS_COLORS do
        local classSpells = addon:GetClassSpellIdsFromData(class)
        if classSpells then
            for spellid in next, classSpells do
                if not visitedSpellIds[spellid] then
                    -- these were missing from the db - they cannot be consolidated
                    bySpellId[spellid] = CreateSpellEntry(spellid)
                    --visitedSpellIds[spellid] = true -- this table is only used to populate spells that are missing from the db (so this assignment is not needed)
                end
            end
        end
    end
    
    if not tree[1] or tree[1].value ~= DEFAULT_KEY then
        -- defaults entry did not exist in the db, manually spawn it now
        tree[1] = CreateDefaultsEntry()
    end
    
    -- populate merged data
    -- run this before groups in case any consolidated displays are grouped
    for consolidatedId, consolidatedData in next, profile.consolidated do
        local consolidatedEntry = {}
        consolidatedEntry.value = consolidatedId
        consolidatedEntry.text = consolidatedData.name
        valueToText[consolidatedEntry.value] = consolidatedEntry.text
        consolidatedEntry.children = {}
        for spellEntry, id in next, byConsolidatedId do
            if consolidatedId == id then
                append(consolidatedEntry.children, spellEntry)
                byConsolidatedId[spellEntry] = nil -- removing while iterating feels wrong
            end
        end
        local numChildren = #consolidatedEntry.children
        if numChildren == 0 then
            -- this means there was no data for this consolidated id
            -- TODO: prune the id from the db?
            addon:Debug(("PopulateTree(): consolidated id='%s' found no spells!"):format(consolidatedId))
        end
        -- don't throw the entry into the tree just yet - it may be part of a group
        -- second-pass, 'byConsolidatedId' holds consolidatedId = [consolidatedEntry table] pairs
        byConsolidatedId[consolidatedId] = consolidatedEntry
    end
    -- validate all of the consolidated data
    for id in next, byConsolidatedId do
        if type(id) == "table" then
            -- no consolidated data found for this spellEntry, but the spell data said it is part of a consolidated display..
            -- not sure the best way to handle this.. throwing it into the 'bySpellId' pool for now
            local spellEntry = id
            bySpellId[spellEntry.value] = spellEntry
            byConsolidatedId[id] = nil
        end
    end
    
    -- populate group data
    for groupId, group in next, profile.groups do
        local groupEntry = {}
        groupEntry.value = groupId
        groupEntry.text = group.name
        valueToText[groupEntry.value] = groupEntry.text
        groupEntry.children = {}
        for id, pos in next, group.children do
            local childEntry
            -- check for existing data
            if bySpellId[id] then
                -- spellid with data
                childEntry = bySpellId[id]
                bySpellId[id] = nil
            elseif byConsolidatedId[id] then
                -- a consolidated id
                childEntry = byConsolidatedId[id]
                byConsolidatedId[id] = nil
            else
                if type(id) == "number" then
                    -- no data exists for this spellid
                    childEntry = CreateSpellEntry(id)
                --else
                    -- potentially a consolidated id with no data or another group - TODO: recursive
                end
            end
            
            if childEntry then
                groupEntry.children[pos] = childEntry
            else
                addon:Debug(("PopulateTree(): group id='%s' missing entry for pos=%d!"):format(groupId, pos))
            end
        end
        append(tree, groupEntry) -- TODO: subgroups
    end
    
    -- populate the tree with free floating (ie: non-grouped) entries
    for id, spellEntry in next, byConsolidatedId do
        append(tree, spellEntry)
        byConsolidatedId[id] = nil
    end
    for id, spellEntry in next, bySpellId do
        append(tree, spellEntry)
        bySpellId[id] = nil
    end
    
    return tree
end

-- ------------------------------------------------------------------
-- Tab select
-- ------------------------------------------------------------------
local OPTIONS_APP_NAME = consts.OPTIONS_APP_NAME
local DrawSelection = {}

--[[
local bar = {} -- TODO: TMP - replace w/ options db
local function DrawTabSelectBaseArea(container)
    container:ReleaseChildren()

    -- this group is needed for re-sizing
    -- without it, the scrollframe acts like a fool
    local simpleGroup = AG:Create("SimpleGroup")
    simpleGroup:SetFullWidth(true)
    simpleGroup:SetFullHeight(true)
    simpleGroup:SetLayout("Fill")
    container:AddChild(simpleGroup)
    
    -- populate the container based on the selected group from the tree
    local scrollFrame = AG:Create("ScrollFrame")
    scrollFrame:SetFullWidth(true)
    scrollFrame:SetFullHeight(true)
    scrollFrame:SetLayout("List")  -- TODO: custom layout
    scrollFrame:SetStatusTable(bar)
    simpleGroup:AddChild(scrollFrame)
    
    return scrollFrame
end
--]]

-- spell selection
DrawSelection["spell"] = function(id, container)
    local db = addon.db:GetSpellSettings(tonumber(id))
    addon:Print(("%s is a spell!"):format(id))
    
    if db.consolidated then
    else
    end
    --[[
        TODO: check if this is part of a consolidated display
            if so, only create a button to unmerge from display
    --]]
end

-- group selection
DrawSelection["group"] = function(id, container)
    local db = addon.db:GetGroupOptions(id)
    addon:Print(("%s is a group!"):format(id))
end

-- consolidated display selection
DrawSelection["consolidated"] = function(id, container)
    local db = addon.db:GetConsolidatedSettings(id)
    addon:Print(("%s is a merged display!"):format(id))
end

-- defaults selection
DrawSelection["defaults"] = function(id, container)
    addon:Print(("%s is the default settings!"):format(id))
    local appName = OPTIONS_APP_NAME:format(id)
    if not ACR:GetOptionsTable(appName) then
        ACR:RegisterOptionsTable(appName, options.DefaultsTable)
    end
    ACD:Open(appName, container)
end

local delim = "\001" -- AceGUI TreeGroup widget subgroup delimiter
local function OnTreeSelect(container, event, group)
    container:ReleaseChildren()
    
    print("VALUE:", strsplit(delim, group))
    print("STATUS.SELECTED:", strsplit(delim, container.status.selected))
    print("FOO.SELECTED:", strsplit(delim, foo.selected))
    print(foo, container.status, container.localstatus)
    
    local badId
    -- figure out which group was selected
    local groupStructure = { strsplit(delim, group) }
    local id = groupStructure[#groupStructure]
    
    -- a superfluous header
    local header = AG:Create("Heading")
    header:SetText(valueToText[id] or BAD_ID_VALUE)
    header:SetFullWidth(true)
    container:AddChild(header)
    
    local simpleGroup = AG:Create("SimpleGroup")
    simpleGroup:SetFullWidth(true)
    simpleGroup:SetFullHeight(true)
    simpleGroup:SetLayout("Fill")
    container:AddChild(simpleGroup)
    
    if type(id) == "string" then -- should be an unnecessary check
        if id:match("^%d+$") then -- spell entry
            DrawSelection["spell"](id, simpleGroup)
        elseif id:match(GROUP_ID) then -- group
            DrawSelection["group"](id, simpleGroup)
        elseif id:match(CONSOLIDATED_ID) then -- merged display
            DrawSelection["consolidated"](id, simpleGroup)
        elseif id == addon.db.DEFAULT_KEY then -- defaults entry
            DrawSelection["defaults"](id, simpleGroup)
        else
            badId = true
        end
    else
        badId = true
    end
    
    if badId then
        -- a wild id appears!
        addon:Debug(("'%s' tab encountered an unexpected id='%s'"):format(consts.tabs.EDIT, id))
    end
end

-- ------------------------------------------------------------------
-- Edit tab
-- ------------------------------------------------------------------
foo = {} -- TODO: TMP - replace w/ options db
options.tab[consts.tabs.EDIT] = function(container)
    local treeGroup = AG:Create("TreeGroup")
    treeGroup:SetLayout("Flow")
    treeGroup:SetTree(PopulateTree())
    treeGroup:SetCallback("OnGroupSelected", OnTreeSelect)
    
    treeGroup:SetStatusTable(foo)
    if foo.selected then
        -- draw the selected group
        -- print(strsplit(delim, foo.selected))
        treeGroup:Select(foo.selected)
    end
    
    --[[ TODO: figure out how to add expand all & collapse all buttons
    local expandAll = AG:Create("Button")
    expandAll:SetText("Expand all")
    expandAll:SetRelativeWidth(0.5)
    expandAll:SetCallback("OnClick", function() print("EXPAND ALL") end)
    
    local collapseAll = AG:Create("Button")
    collapseAll:SetText("Collapse all")
    collapseAll:SetRelativeWidth(0.5)
    collapseAll:SetCallback("OnClick", function() print("COLLAPSE ALL") end)
    container:AddChildren(expandAll, collapseAll)
    --]]
    
    container:SetLayout("Fill")
    container:AddChild(treeGroup)
end
