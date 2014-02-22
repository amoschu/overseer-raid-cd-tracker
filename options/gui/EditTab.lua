
local strsplit, wipe, next, type, insert
    = strsplit, wipe, next, type, table.insert
local GetSpellInfo = GetSpellInfo

local addon = Overseer
local options = addon:GetModule(addon.OPTIONS_MODULE)
local AG = LibStub("AceGUI-3.0")

local consts = options.consts
local append = addon.TableAppend

local GROUP_ID = addon.consts.GROUP_ID
local CONSOLIDATED_ID = addon.consts.CONSOLIDATED_ID

-- ------------------------------------------------------------------
-- Edit tab
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
        spellEntry = {}
        spellEntry.value = spellid
        spellEntry.text = text:format(spellname, spellid)
        spellEntry.icon = icon
    end
    return spellEntry
end

local bySpellId = {} -- work table for quicker lookups
local byConsolidatedId = {} -- another work table
local function PopulateTree()
    --[[
    TODO: this causes a decent amount of unnecessary memory + cpu churn whenever the user changes tabs
        if the user is only switching tabs, chances are this is unneeded except for the initial populate
        so, need to be notified of display setting change that affects this structure to update it
    --]]
    
    local tree = {}
    local profile = addon.db:GetProfile()
    
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
                    byConsolidatedId[spellEntry] = settings.consolidated
                end
            end
        elseif spellid == "**" then
            -- add a special entry for the defaults
            local defaults = {}
            defaults.value = spellid
            defaults.text = "Default Settings" -- TODO: localization
            --defaults.icon -- TODO: a generic icon for this
            tree[1] = defaults
        end
    end
    
    -- populate merged data
    -- run this before groups in case any consolidated displays are grouped
    for consolidatedId, consolidatedData in next, profile.consolidated do
        local consolidatedEntry = {}
        consolidatedEntry.value = consolidatedId
        consolidatedEntry.text = consolidatedData.name
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
        byConsolidatedId[consolidatedId] = consolidatedEntry
    end
    -- validate that all of the consolidated data
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

local delim = "\001" -- AceGUI TreeGroup widget subgroup delimiter
local function OnGroupSelected(container, event, group)
    container:ReleaseChildren()
    
    -- populate the container based on the selected group from the tree
    local scrollFrame = AG:Create("ScrollFrame")
    scrollFrame:SetFullWidth(true)
    scrollFrame:SetFullHeight(true)
    scrollFrame:SetLayout("List")
    container:AddChild(scrollFrame)
    
    local badId
    -- figure out which group was selected
    local groupStructure = { strsplit(delim, group) }
    local id = groupStructure[#groupStructure]
    if type(id) == "string" then -- should be an unnecessary check
        if id:match("^%d+$") then
            -- spell entry
            local db = addon.db:GetSpellSettings(id)
            --[[
                TODO: check if this is part of a consolidated display
                    if so, only create a button to unmerge from display
            --]]
            addon:Print(("%s is a spell!"):format(id))
        elseif id:match(GROUP_ID) then
            -- group
            local db = addon.db:GetGroupOptions(id)
            addon:Print(("%s is a group!"):format(id))
        elseif id:match(CONSOLIDATED_ID) then
            -- merged display
            local db = addon.db:GetConsolidatedSettings(id)
            addon:Print(("%s is a merged display!"):format(id))
        elseif id == "**" then
            -- defaults entry
            local db = addon.db:GetDefaultSettings()
            addon:Print(("%s is the default settings!"):format(id))
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
    
    for i = 1, 20 do
        local button = AG:Create("Button")
        button:SetText("CLICK")
        button:SetWidth(100)
        button:SetCallback("OnClick", function() print(groupStructure[#groupStructure]) end)
        scrollFrame:AddChild(button)
    end
end

options.tab[consts.tabs.EDIT] = function(container)
    local treeGroup = AG:Create("TreeGroup")
    treeGroup:SetLayout("Fill")
    treeGroup:SetTree(PopulateTree())
    treeGroup:SetCallback("OnGroupSelected", OnGroupSelected)
    --[[
    local status = { -- TODO: the structure needs to match the tree structure (keys must match as well) - true indicates that the branch is expanded
        groups = {
            ["1"] = true,
            ["2"] = true,
            ["3"] = true,
            ["4"] = true,
        },
    }
    treeGroup:SetStatusTable(status)
    treeGroup:RefreshTree() -- to expand entries / scroll to appropriate positions etc
    --]]
    
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
