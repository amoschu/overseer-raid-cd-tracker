
local strsplit, wipe, next, tostring, type, insert
    = strsplit, wipe, next, tostring, type, table.insert
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
local STRATA = {
    PARENT = "INHERITED",
    BACKGROUND = "BACKGROUND",
    LOW = "LOW",
    MEDIUM = "MEDIUM",
    HIGH = "HIGH",
    DIALOG = "DIALOG",
    FULLSCREEN = "FULLSCREEN",
    FULLSCREEN_DIALOG = "FULLSCREEN_DIALOG",
    TOOLTIP = "TOOLTIP",
}
local POINT = {
    LEFT = "LEFT",
    RIGHT = "RIGHT",
    TOP = "TOP",
    BOTTOM = "BOTTOM",
    CENTER = "CENTER",
    BOTTOMLEFT = "BOTTOMLEFT",
    BOTTOMRIGHT = "BOTTOMRIGHT",
    TOPLEFT = "TOPLEFT",
    TOPRIGHT = "TOPRIGHT",
}
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

local bySpellId = {} -- work table for quicker lookups
local byConsolidatedId = {} -- another work table
local function PopulateTree()
    --[[
    TODO: this causes a decent amount of unnecessary memory + cpu churn whenever the user changes tabs
        if the user is only switching tabs, chances are this is unneeded except for the initial populate
        instead, update the structure after the initial populate whenever it changes
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
            valueToText[defaults.value] = defaults.text
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
local OPTIONS_APP_NAME = options:GetName() .. "_%s"
local DISPLAY_TAB = "DISPLAY"
local ICON_TAB = "ICON"
local BARS_TAB = "BARS"
local TEXTS_TAB = "TEXTS"
local BAD_ID_VALUE = "???"
-- tab definitions - TODO: localization of 'text' fields
local DisplayTab    = { text = "Display", value = DISPLAY_TAB } -- TODO: ..may be able to just replace with options table
local IconTab       = { text = "Icon", value = ICON_TAB }
local BarsTab       = { text = "Bars", value = BARS_TAB }
local TextsTab      = { text = "Texts", value = TEXTS_TAB }

local DrawSelection = {}

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

-- spell selection
DrawSelection["spell"] = function(id, container)
    local db = addon.db:GetSpellSettings(id)
    addon:Print(("%s is a spell!"):format(id))
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
local bar = {} -- TODO: TMP - replace w/ options db
DrawSelection["defaults"] = function(id, container)
    addon:Print(("%s is the default settings!"):format(id))
    local appName = OPTIONS_APP_NAME:format(id)
    if not ACR:GetOptionsTable(appName) then
        ACR:RegisterOptionsTable(appName,
            function(uiType, uiName, app)
                local db = addon.db:GetDefaultSettings()
                -- TODO: this is messing with the edit tab's saved status (maybe fixed when other selections are fleshed out?)
                local opts = { -- TODO: every set here needs to set all existing saved data..
                    type = "group",
                    childGroups = "tab",
                    args = {
                        header = {
                            name = valueToText[id] or BAD_ID_VALUE,
                            type = "header",
                        },
                        display = {
                            name = "Display", -- TODO: better name/localization
                            type = "group",
                            order = 0,
                            set = function(info, val)
                                local element = info[#info]
                                db[element] = val
                                -- TODO: broadcast a message or something so that active display elements update
                            end,
                            get = function(info)
                                local element = info[#info]
                                return db[element]
                            end,
                            args = {
                                shown = {
                                    name = "Enable", -- TODO: localization
                                    desc = "Enable/disable display",
                                    type = "toggle",
                                    width = "normal",
                                    order = 0,
                                },
                                unique = {
                                    name = "Unique", -- TODO: localization
                                    desc = "Spawn a unique display for every person who can cast this spell",
                                    type = "toggle",
                                    width = "normal",
                                    order = 1,
                                },
                                hide = {
                                    name = "Hide display",
                                    desc = "Hide the display when all casters are...",
                                    type = "multiselect",
                                    width = "full",
                                    order = 2,
                                    values = {
                                        dead = "Dead",
                                        offline = "Offline",
                                        benched = "Benched",
                                    },
                                    set = function(info, key, val)
                                        db.hide[key] = val
                                    end,
                                    get = function(info, key)
                                        return db.hide[key]
                                    end,
                                },
                                
                                visibility = {
                                    name = "Visbility",
                                    type = "header",
                                    order = 3,
                                },
                                alpha = {
                                    name = "Alpha",
                                    desc = "Set the display's alpha transparency level",
                                    type = "range",
                                    min = 0.0,
                                    max = 1.0,
                                    bigStep = 0.05,
                                    isPercent = true,
                                    width = "full",
                                    order = 4,
                                },
                                scale = {
                                    name = "Scale",
                                    desc = "Set the display's scale factor",
                                    type = "range",
                                    softMin = 0.5,
                                    softMax = 10.0,
                                    bigStep = 0.05,
                                    width = "full",
                                    order = 5,
                                },
                                strata = {
                                    name = "Frame Strata",
                                    desc = "Set the frame's strata",
                                    type = "select",
                                    values = STRATA,
                                    width = "normal",
                                    order = 6,
                                },
                                frameLevel = {
                                    name = "Frame Level",
                                    desc = "Set the frame's level",
                                    type = "range",
                                    min = 2, -- icons need 2 levels
                                    max = 108, -- moving/sizing overlays need 20 levels
                                    bigStep = 1,
                                    width = "normal",
                                    order = 7,
                                },
                                
                                positioning = {
                                    name = "Positioning",
                                    type = "header",
                                    order = 8,
                                },
                                x = {
                                    name = "X",
                                    desc = "Set the display's x position",
                                    type = "range",
                                    min = 0,
                                    max = UIParent:GetWidth(),
                                    bigStep = 1,
                                    width = "normal",
                                    order = 9,
                                },
                                y = {
                                    name = "Y",
                                    desc = "Set the display's y position",
                                    type = "range",
                                    min = 0,
                                    max = UIParent:GetHeight(),
                                    bigStep = 1,
                                    width = "normal",
                                    order = 10,
                                },
                                point = {
                                    name = "Point",
                                    desc = "Set the display's anchor point",
                                    type = "select",
                                    values = POINT,
                                    width = "normal",
                                    order = 11,
                                },
                                relPoint = {
                                    name = "Relative Point",
                                    desc = "Set the anchor point of the display's relative frame (ie, anchor frame)",
                                    type = "select",
                                    values = POINT,
                                    width = "normal",
                                    order = 12,
                                },
                                relFrame = {
                                    name = "Anchor Frame",
                                    desc = "Set the display's relative anchor frame (string)",
                                    type = "input",
                                    width = "full",
                                    order = 13,
                                    validate = function(info, input) -- TODO: allow group/consolidated/(spell?) string ids(?) names(?) and any frame found in the _G table
                                        -- treat input:len() == 0 as nil
                                        print("validate", info[#info], tostring(input).."[len="..input:len().."]")
                                        --return true -- true => valid (false/nil/no return => invalid)
                                    end,
                                    set = function(...)
                                        print("set", ...)
                                    end,
                                    get = function(...)
                                        print("get", ...)
                                    end,
                                },
                            },
                        },
                        icon = {
                            name = "Icon", -- TODO: localization
                            type = "group",
                            order = 1,
                            args = {
                            },
                        },
                        bars = {
                            name = "Bars", -- TODO: localization
                            type = "group",
                            order = 2,
                            args = {
                            },
                        },
                        texts = {
                            name = "Texts", -- TODO: localization
                            type = "group",
                            order = 3,
                            args = {
                            },
                        },
                    },
                }
                return opts
            end
        )
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
    
    -- -- a superfluous header
    -- local header = AG:Create("Heading")
    -- header:SetText(valueToText[id] or BAD_ID_VALUE)
    -- header:SetFullWidth(true)
    -- container:AddChild(header)
    
    -- local simpleGroup = AG:Create("SimpleGroup")
    -- simpleGroup:SetFullWidth(true)
    -- simpleGroup:SetFullHeight(true)
    -- simpleGroup:SetLayout("Fill")
    -- container:AddChild(simpleGroup)
    
    if type(id) == "string" then -- should be an unnecessary check
        if id:match("^%d+$") then -- spell entry
            DrawSelection["spell"](id, container)
        elseif id:match(GROUP_ID) then -- group
            DrawSelection["group"](id, container)
        elseif id:match(CONSOLIDATED_ID) then -- merged display
            DrawSelection["consolidated"](id, container)
        elseif id == "**" then -- defaults entry
            DrawSelection["defaults"](id, container)
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
