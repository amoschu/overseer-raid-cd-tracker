
local strsplit, wipe, next, tonumber, tostring, type, insert
    = strsplit, wipe, next, tonumber, tostring, type, table.insert
local GetSpellInfo, UIParent
    = GetSpellInfo, UIParent

local addon = Overseer
local options = addon:GetModule(addon.OPTIONS_MODULE)
local AG = LibStub("AceGUI-3.0")
local ACR = LibStub("AceConfigRegistry-3.0")
local ACD = LibStub("AceConfigDialog-3.0")
local LSM = LibStub("LibSharedMedia-3.0") -- TODO: move to OptionsTable
local MediaType = LSM.MediaType -- TODO: move to OptionsTable

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
local CARDINAL_POINT = {
    LEFT = "LEFT",
    RIGHT = "RIGHT",
    TOP = "TOP",
    BOTTOM = "BOTTOM",
}
local DIRECTION = {
    LEFT = "LEFT",
    RIGHT = "RIGHT",
    TOP = "UP",
    BOTTOM = "DOWN",
}
local ORIENTATION = {
    VERTICAL = "VERTICAL",
    HORIZONTAL = "HORIZONTAL",
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
        elseif spellid == DEFAULT_KEY then
            tree[1] = CreateDefaultsEntry()
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

-- spell selection
DrawSelection["spell"] = function(id, container)
    local db = addon.db:GetSpellSettings(tonumber(id))
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
                    width = "full",
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
                                local oldVal = db[element]
                                db[element] = val
                                
                                addon.db:SaveDefaultSetting(element, oldVal, val)
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
                                    disabled = function(info)
                                        return not db.shown
                                    end,
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
                                    disabled = function(info)
                                        return not db.shown
                                    end,
                                    set = function(info, key, val)
                                        local oldVal = db.hide[key]
                                        db.hide[key] = val
                                        
                                        addon.db:SaveDefaultSetting(key, oldVal, val, "hide")
                                        -- TODO: broadcast
                                    end,
                                    get = function(info, key)
                                        return db.hide[key]
                                    end,
                                },
                                
                                visibility = {
                                    name = "", --"Visbility",
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
                                    disabled = function(info)
                                        return not db.shown
                                    end,
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
                                    disabled = function(info)
                                        return not db.shown
                                    end,
                                },
                                strata = {
                                    name = "Frame Strata",
                                    desc = "Set the frame's strata",
                                    type = "select",
                                    values = STRATA,
                                    width = "normal",
                                    order = 6,
                                    disabled = function(info)
                                        return not db.shown
                                    end,
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
                                    disabled = function(info)
                                        return not db.shown
                                    end,
                                },
                                
                                positioning = {
                                    name = "", --"Positioning",
                                    type = "header",
                                    order = 8,
                                },
                                x = {
                                    name = "X",
                                    desc = "Set the display's x position",
                                    type = "range",
                                    softMin = 0,
                                    softMax = UIParent:GetWidth(), -- TODO: update based on relative point (& anchor frame?)
                                    bigStep = 1,
                                    width = "normal",
                                    order = 9,
                                    disabled = function(info)
                                        return not db.shown
                                    end,
                                },
                                y = {
                                    name = "Y",
                                    desc = "Set the display's y position",
                                    type = "range",
                                    softMin = 0,
                                    softMax = UIParent:GetHeight(), -- TODO: update based on relative point (& anchor frame?)
                                    bigStep = 1,
                                    width = "normal",
                                    order = 10,
                                    disabled = function(info)
                                        return not db.shown
                                    end,
                                },
                                point = {
                                    name = "Point",
                                    desc = "Set the display's anchor point",
                                    type = "select",
                                    values = POINT,
                                    width = "normal",
                                    order = 11,
                                    disabled = function(info)
                                        return not db.shown
                                    end,
                                },
                                relPoint = {
                                    name = "Relative Point",
                                    desc = "Set the anchor point of the display's relative frame (ie, anchor frame)",
                                    type = "select",
                                    values = POINT,
                                    width = "normal",
                                    order = 12,
                                    disabled = function(info)
                                        return not db.shown
                                    end,
                                },
                                relFrame = {
                                    name = "Anchor Frame",
                                    desc = "Set the display's anchor frame (string)",
                                    type = "input",
                                    width = "full",
                                    order = 13,
                                    validate = function(info, input) -- TODO: allow group/consolidated/(spell?) string ids(?) names(?) and any frame found in the _G table
                                        -- treat input:len() == 0 as nil
                                        print("validate", info[#info], tostring(input).."[len="..input:len().."]")
                                        --return true -- true => valid (false/nil/no return => invalid)
                                    end,
                                    disabled = function(info)
                                        return not db.shown
                                    end,
                                    --[[
                                        TODO: type="execute"
                                        
                                        -- fstack macro:
                                        /run local e,m,n,f=EnumerateFrames,MouseIsOver;ChatFrame1:AddMessage("The mouse is over the following frames:")f=e()while f do n=f:GetName()if n and f:IsVisible()and m(f)then    ChatFrame1:AddMessage("   - "..n)end;f=e(f)end
                                        
                                        local e,m,n,f=EnumerateFrames,MouseIsOver
                                        ChatFrame1:AddMessage("The mouse is over the following frames:")
                                        f = EnumerateFrames()
                                        while f do -- prints all frame names (like /fstack but in macro form)
                                            n = f:GetName()
                                            if n and f:IsVisible() and m(f) then
                                                ChatFrame1:AddMessage("   - "..n)
                                            end
                                            f = EnumerateFrames(f)
                                        end
                                    --]]
                                    validate = function(info, input)
                                        -- TODO: allow other spellDisplay frames?
                                        -- TODO: (display problem) how to handle if anchor frame does not exist?
                                        local valid = input:len() == 0 or input:match(GROUP_ID) or input:match(CONSOLIDATED_ID) or _G[input]
                                        if not valid then
                                            -- TODO: what about frames that have not been loaded yet?
                                            addon:Error(("Could not find a frame named '%s'"):format(input))
                                        end
                                        return valid
                                    end,
                                    set = function(info, input)
                                        local element = "relFrame"
                                        local oldVal = db[element]
                                        local newVal = input:len() > 0 and input or nil
                                        db[element] = newVal
                                        
                                        addon.db:SaveDefaultSetting(element, oldVal, newVal)
                                    end,
                                },
                            },
                        },
                        icon = {
                            name = "Icon", -- TODO: localization
                            type = "group",
                            order = 1,
                            disabled = function(info)
                                return not db.shown
                            end,
                            set = function(info, val)
                                local element = info[#info]
                                local oldVal = db.icon[element]
                                db.icon[element] = val
                                
                                addon.db:SaveDefaultSetting(element, oldVal, val, "icon")
                                -- TODO: broadcast a message or something so that active display elements update
                            end,
                            get = function(info)
                                local element = info[#info]
                                return db.icon[element]
                            end,
                            args = {
                                shown = {
                                    name = "Show",
                                    desc = "Shows/hides the icon display element",
                                    type = "toggle",
                                    width = "full",
                                    order = 0,
                                },
                                cooldown = {
                                    name = "Cooldown",
                                    desc = "Display the spell's cooldown on the icon",
                                    type = "toggle",
                                    width = "normal",
                                    order = 1,
                                    hidden = function() return not db.icon.shown end,
                                },
                                showBuffDuration = {
                                    name = "Buff Duration",
                                    desc = "Display the spell's buff duration on the icon",
                                    type = "toggle",
                                    width = "normal",
                                    order = 2,
                                    hidden = function() return not db.icon.shown end,
                                },
                                desatIfUnusable = {
                                    name = "Desaturate if unusable",
                                    desc = "Desaturate the icon if no one can cast the spell",
                                    type = "toggle",
                                    width = "normal",
                                    order = 3,
                                    hidden = function() return not db.icon.shown end,
                                },
                                autoCrop = {
                                    name = "Auto-crop",
                                    desc = "Crop the icon to preserve its aspect ratio",
                                    type = "toggle",
                                    width = "normal",
                                    order = 4,
                                    hidden = function() return not db.icon.shown end,
                                },
                                
                                sizing = {
                                    name = "", --"Sizing",
                                    type = "header",
                                    order = 5,
                                    hidden = function() return not db.icon.shown end,
                                },
                                width = {
                                    name = "Width",
                                    desc = "Set the icon's width",
                                    type = "range",
                                    min = addon.db:GetProfile().minWidth, -- TODO: update on db changes
                                    softMax = 64,
                                    bigStep = 1,
                                    width = "full",
                                    order = 6,
                                    hidden = function() return not db.icon.shown end,
                                },
                                height = {
                                    name = "Height",
                                    desc = "Set the icon's height",
                                    type = "range",
                                    min = addon.db:GetProfile().minHeight, -- TODO: update on db changes
                                    softMax = 64,
                                    bigStep = 1,
                                    width = "full",
                                    order = 7,
                                    hidden = function() return not db.icon.shown end,
                                },
                                
                                borderHeader = {
                                    name = "", --"Border",
                                    type = "header",
                                    order = 8,
                                    hidden = function() return not db.icon.shown end,
                                },
                                borderShown = {
                                    name = "Show Border",
                                    desc = "Shows/hides the icon's border",
                                    type = "toggle",
                                    width = "full",
                                    order = 9,
                                    hidden = function() return not db.icon.shown end,
                                    set = function(info, val)
                                        local element = "shown"
                                        local oldVal = db.icon.border[element]
                                        db.icon.border[element] = val
                                        
                                        addon.db:SaveDefaultSetting(element, oldVal, val, "icon", "border")
                                        -- TODO: broadcast a message or something so that active display elements update
                                    end,
                                    get = function(info)
                                        local element = "shown"
                                        return db.icon.border[element]
                                    end,
                                },
                                borderSize = {
                                    name = "Border Size",
                                    desc = "Set the icon border size (px)",
                                    type = "range",
                                    min = 1,
                                    softMax = 16,
                                    bigStep = 1,
                                    width = "full",
                                    order = 10,
                                    hidden = function() return not db.icon.shown end,
                                    set = function(info, val)
                                        local element = "size"
                                        local oldVal = db.icon.border[element]
                                        db.icon.border[element] = val
                                        
                                        addon.db:SaveDefaultSetting(element, oldVal, val, "icon", "border")
                                        -- TODO: broadcast a message or something so that active display elements update
                                    end,
                                    get = function(info)
                                        local element = "size"
                                        return db.icon.border[element]
                                    end,
                                },
                                borderUseClassColor = {
                                    name = "Use Class Color",
                                    desc = "Color the icon's border with the caster's class color (this overrides any manually set border color)",
                                    type = "toggle",
                                    width = "normal",
                                    order = 11,
                                    hidden = function() return not db.icon.shown end,
                                    set = function(info, val)
                                        local element = "useClassColor"
                                        local oldVal = db.icon.border[element]
                                        db.icon.border[element] = val
                                        
                                        addon.db:SaveDefaultSetting(element, oldVal, val, "icon", "border")
                                        -- TODO: broadcast a message or something so that active display elements update
                                    end,
                                    get = function(info)
                                        local element = "useClassColor"
                                        return db.icon.border[element]
                                    end,
                                },
                                borderRGBA = {
                                    name = "Border Color",
                                    desc = "Set the icon border color & alpha",
                                    type = "color",
                                    hasAlpha = true,
                                    width = "normal",
                                    order = 12,
                                    hidden = function() return not db.icon.shown end,
                                    disabled = function(info)
                                        return db.icon.border.useClassColor
                                    end,
                                    set = function(info, r, g, b, a)
                                        local borderDB = db.icon.border
                                        local oldR = borderDB.r
                                        local oldG = borderDB.g
                                        local oldB = borderDB.b
                                        local oldA = borderDB.a
                                        
                                        borderDB.r = r -- TODO: create a Database wrapper to set color/alpha
                                        borderDB.g = g
                                        borderDB.b = b
                                        borderDB.a = a
                                        
                                        addon.db:SaveDefaultSetting("r", oldR, r, "icon", "border")
                                        addon.db:SaveDefaultSetting("g", oldG, g, "icon", "border")
                                        addon.db:SaveDefaultSetting("b", oldB, b, "icon", "border")
                                        addon.db:SaveDefaultSetting("a", oldA, a, "icon", "border")
                                        -- TODO: broadcast a message or something so that active display elements update
                                    end,
                                    get = function(info)
                                        local borderDB = db.icon.border
                                        return borderDB.r, borderDB.g, borderDB.b, borderDB.a
                                    end,
                                },
                            },
                        },
                        bars = {
                            name = "Bars", -- TODO: localization
                            type = "group",
                            order = 2,
                            disabled = function(info)
                                return not db.shown
                            end,
                            set = function(info, val)
                                local element = info[#info]
                                local oldVal = db.bar[element]
                                db.bar[element] = val
                                
                                addon.db:SaveDefaultSetting(element, oldVal, val, "bar")
                                -- TODO: broadcast a message or something so that active display elements update
                            end,
                            get = function(info)
                                local element = info[#info]
                                return db.bar[element]
                            end,
                            args = {
                                shown = {
                                    name = "Show",
                                    desc = "Shows/hides bar display elements",
                                    type = "toggle",
                                    width = "full",
                                    order = 0,
                                },
                                cooldown = {
                                    name = "Cooldown",
                                    desc = "Use bars to display the spell's cooldown",
                                    type = "toggle",
                                    width = "normal",
                                    order = 1,
                                    hidden = function() return not db.bar.shown end,
                                },
                                showBuffDuration = {
                                    name = "Buff Duration",
                                    desc = "Use bars to display the spell's buff duration",
                                    type = "toggle",
                                    width = "normal",
                                    order = 2,
                                    hidden = function() return not db.bar.shown end,
                                },
                                iconShown = {
                                    name = "Show Icon",
                                    desc = "Show an icon on the bar",
                                    type = "toggle",
                                    width = "normal",
                                    order = 3,
                                    hidden = function() return not db.bar.shown end,
                                },
                                fill = {
                                    name = "Fill",
                                    desc = "Set whether bars should fill or drain",
                                    type = "toggle",
                                    width = "normal",
                                    order = 4,
                                    hidden = function() return not db.bar.shown end,
                                },
                                limit = {
                                    name = "Max bars",
                                    desc = "Max number of active bars (0 = no limit)",
                                    type = "range",
                                    min = 0,
                                    softMax = 5,
                                    bigStep = 1,
                                    width = "full",
                                    order = 5,
                                    hidden = function() return not db.bar.shown end,
                                },
                                grow = {
                                    name = "Growth",
                                    desc = "Set the growth direction of new bars",
                                    type = "select",
                                    values = DIRECTION,
                                    width = "normal",
                                    order = 6,
                                    hidden = function() return not db.bar.shown end,
                                    disabled = function(info)
                                        return db.bar.limit == 1
                                    end,
                                },
                                orientation = {
                                    name = "Orientation",
                                    desc = "Set the bars' orientation",
                                    type = "select",
                                    values = ORIENTATION,
                                    width = "normal",
                                    order = 7,
                                    hidden = function() return not db.bar.shown end,
                                },
                                texture = {
                                    name = "Texture",
                                    desc = "Set the bars' texture",
                                    type = "select",
                                    dialogControl = "LSM30_Statusbar",
                                    values = LSM:HashTable(MediaType.STATUSBAR),
                                    width = "double",
                                    order = 8,
                                    hidden = function() return not db.bar.shown end,
                                },
                                
                                barPositioning = {
                                    name = "",
                                    type = "header",
                                    order = 9,
                                    hidden = function() return not db.bar.shown end,
                                },
                                fitIcon = {
                                    name = "Fit icon size", -- TODO: more wording better
                                    desc = "Force bars to fit the display icon's size based on the side to which they are anchored",
                                    type = "toggle",
                                    width = "normal",
                                    order = 10,
                                    hidden = function() return not db.bar.shown end,
                                    disabled = function(info)
                                        return not db.icon.shown
                                    end,
                                },
                                side = {
                                    name = "Icon side", -- TODO: more wording better
                                    desc = "Set the side to which bars are anchored (relative to the display icon)",
                                    type = "select",
                                    values = CARDINAL_POINT,
                                    width = "normal",
                                    order = 11,
                                    hidden = function() return not db.bar.shown end,
                                    disabled = function(info)
                                        return not db.icon.shown or not db.bar.fitIcon
                                    end,
                                },
                                adjust = {
                                    name = "Adjust fit-size", -- TODO: more wording better
                                    desc = "Adjust the bars' fit dimension based on the anchor side",
                                    type = "range",
                                    softMin = -0.5 * db.icon.height, -- TODO: update based on side
                                    softMax = 0.5 * db.icon.height, -- TODO: ^
                                    bigStep = 1,
                                    width = "normal",
                                    order = 12,
                                    hidden = function() return not db.bar.shown end,
                                    disabled = function(info)
                                        return not db.icon.shown or not db.bar.fitIcon
                                    end,
                                },
                                spacing = {
                                    name = "Spacing",
                                    desc = "Set the spacing between bars",
                                    type = "range",
                                    softMin = 0,
                                    softMax = 10,
                                    bigStep = 1,
                                    width = "normal",
                                    order = 13,
                                    hidden = function() return not db.bar.shown end,
                                    disabled = function(info)
                                        return not db.icon.shown or db.bar.limit == 1
                                    end,
                                },
                                width = {
                                    name = "Width",
                                    desc = "Set the bars' width",
                                    type = "range",
                                    min = 1,
                                    softMax = 16,
                                    bigStep = 1,
                                    width = "normal",
                                    order = 14,
                                    hidden = function() return not db.bar.shown end,
                                    disabled = function(info)
                                        local barDB = db.bar
                                        local side = barDB.side
                                        return not db.icon.shown or (barDB.fitIcon and (side == "TOP" or side == "BOTTOM"))
                                    end,
                                },
                                height = {
                                    name = "Height",
                                    desc = "Set the bars' height",
                                    type = "range",
                                    min = 1,
                                    softMax = 16,
                                    bigStep = 1,
                                    width = "normal",
                                    order = 15,
                                    hidden = function() return not db.bar.shown end,
                                    disabled = function(info)
                                        local barDB = db.bar
                                        local side = barDB.side
                                        return not db.icon.shown or (barDB.fitIcon and (side == "LEFT" or side == "RIGHT"))
                                    end,
                                },
                                x = {
                                    name = "X Offset",
                                    desc = "Set the bars' x offsets relative to their parent frame",
                                    type = "range",
                                    softMin = -16, -- super arbitrary
                                    softMax = 16,
                                    bigStep = 1,
                                    width = "normal",
                                    order = 16,
                                    hidden = function() return not db.bar.shown end,
                                },
                                y = {
                                    name = "Y Offset",
                                    desc = "Set the bars' y offsets relative to their parent frame",
                                    type = "range",
                                    softMin = -16,
                                    softMax = 16,
                                    bigStep = 1,
                                    width = "normal",
                                    order = 17,
                                    hidden = function() return not db.bar.shown end,
                                },
                                
                                barColoring = {
                                    name = "",
                                    type = "header",
                                    order = 18,
                                    hidden = function() return not db.bar.shown end,
                                },
                                barUseClassColor = {
                                    name = "Use Class Color",
                                    desc = "Color the bar with the caster's class color (this overrides any manually set bar color)",
                                    type = "toggle",
                                    width = "normal",
                                    order = 19,
                                    hidden = function() return not db.bar.shown end,
                                    set = function(info, val)
                                        local element = "useClassColor"
                                        local barDB = db.bar.bar
                                        local oldVal = barDB[element]
                                        barDB[element] = val
                                        
                                        addon.db:SaveDefaultSetting(element, oldVal, val, "bar", "bar")
                                        -- TODO: broadcast a message or something so that active display elements update
                                    end,
                                    get = function(info)
                                        local element = "useClassColor"
                                        return db.bar.bar[element]
                                    end,
                                },
                                barColor = {
                                    name = "Bar Color",
                                    desc = "Set the bars' color & alpha",
                                    type = "color",
                                    hasAlpha = true,
                                    width = "normal",
                                    order = 20,
                                    hidden = function() return not db.bar.shown end,
                                    disabled = function(info)
                                        return db.bar.bar.useClassColor
                                    end,
                                    set = function(info, r, g, b, a)
                                        local barDB = db.bar.bar
                                        local oldR = barDB.r
                                        local oldG = barDB.g
                                        local oldB = barDB.b
                                        local oldA = barDB.a
                                        
                                        barDB.r = r -- TODO: create a Database wrapper to set color/alpha
                                        barDB.g = g
                                        barDB.b = b
                                        barDB.a = a
                                        
                                        addon.db:SaveDefaultSetting("r", oldR, r, "bar", "bar")
                                        addon.db:SaveDefaultSetting("g", oldG, g, "bar", "bar")
                                        addon.db:SaveDefaultSetting("b", oldB, b, "bar", "bar")
                                        addon.db:SaveDefaultSetting("a", oldA, a, "bar", "bar")
                                        -- TODO: broadcast a message or something so that active display elements update
                                    end,
                                    get = function(info)
                                        local barDB = db.bar.bar
                                        return barDB.r, barDB.g, barDB.b, barDB.a
                                    end,
                                },
                                barBGUseClassColor = {
                                    name = "Background Use Class Color",
                                    desc = "Color the bars' background with the caster's class color (this overrides any manually set bar bg color)",
                                    type = "toggle",
                                    width = "normal",
                                    order = 21,
                                    hidden = function() return not db.bar.shown end,
                                    set = function(info, val)
                                        local element = "useClassColor"
                                        local bgDB = db.bar.bg
                                        local oldVal = bgDB[element]
                                        bgDB[element] = val
                                        
                                        addon.db:SaveDefaultSetting(element, oldVal, val, "bar", "bg")
                                        -- TODO: broadcast a message or something so that active display elements update
                                    end,
                                    get = function(info)
                                        local element = "useClassColor"
                                        return db.bar.bg[element]
                                    end,
                                },
                                barBGColor = {
                                    name = "Bar Background Color",
                                    desc = "Set the bars' background color & alpha",
                                    type = "color",
                                    hasAlpha = true,
                                    width = "normal",
                                    order = 22,
                                    hidden = function() return not db.bar.shown end,
                                    disabled = function(info)
                                        return db.bar.bg.useClassColor
                                    end,
                                    set = function(info, r, g, b, a)
                                        local bgDB = db.bar.bg
                                        local oldR = bgDB.r
                                        local oldG = bgDB.g
                                        local oldB = bgDB.b
                                        local oldA = bgDB.a
                                        
                                        bgDB.r = r -- TODO: create a Database wrapper to set color/alpha
                                        bgDB.g = g
                                        bgDB.b = b
                                        bgDB.a = a
                                        
                                        addon.db:SaveDefaultSetting("r", oldR, r, "bar", "bg")
                                        addon.db:SaveDefaultSetting("g", oldG, g, "bar", "bg")
                                        addon.db:SaveDefaultSetting("b", oldB, b, "bar", "bg")
                                        addon.db:SaveDefaultSetting("a", oldA, a, "bar", "bg")
                                        -- TODO: broadcast a message or something so that active display elements update
                                    end,
                                    get = function(info)
                                        local bgDB = db.bar.bg
                                        return bgDB.r, bgDB.g, bgDB.b, bgDB.a
                                    end,
                                },
                                barEnableBuffColor = {
                                    name = "Disable Buff Color",
                                    desc = "Do not use a separate color for bars displaying a buff duration",
                                    type = "toggle",
                                    width = "normal",
                                    order = 23,
                                    hidden = function() return not db.bar.shown end,
                                    set = function(info, val)
                                        local element = "enableBuffColor"
                                        local barDB = db.bar.bar
                                        local oldVal = barDB[element]
                                        barDB[element] = not val
                                        
                                        addon.db:SaveDefaultSetting(element, oldVal, not val, "bar", "bar")
                                        -- TODO: broadcast a message or something so that active display elements update
                                    end,
                                    get = function(info)
                                        local element = "enableBuffColor"
                                        return not db.bar.bar[element]
                                    end,
                                },
                                barBuffColor = {
                                    name = "Buff Color",
                                    desc = "Set the bars' buff color & alpha",
                                    type = "color",
                                    hasAlpha = true,
                                    width = "normal",
                                    order = 24,
                                    hidden = function() return not db.bar.shown end,
                                    disabled = function(info)
                                        return not db.bar.bar.enableBuffColor
                                    end,
                                    set = function(info, r, g, b, a)
                                        local barDB = db.bar.bar
                                        local oldR = barDB.buffR
                                        local oldG = barDB.buffG
                                        local oldB = barDB.buffB
                                        local oldA = barDB.buffA
                                        
                                        barDB.buffR = r -- TODO: create a Database wrapper to set color/alpha
                                        barDB.buffG = g
                                        barDB.buffB = b
                                        barDB.buffA = a
                                        
                                        addon.db:SaveDefaultSetting("buffR", oldR, r, "bar", "bar")
                                        addon.db:SaveDefaultSetting("buffG", oldG, g, "bar", "bar")
                                        addon.db:SaveDefaultSetting("buffB", oldB, b, "bar", "bar")
                                        addon.db:SaveDefaultSetting("buffA", oldA, a, "bar", "bar")
                                        -- TODO: broadcast a message or something so that active display elements update
                                    end,
                                    get = function(info)
                                        local barDB = db.bar.bar
                                        return barDB.buffR, barDB.buffG, barDB.buffB, barDB.buffA
                                    end,
                                },
                                
                                --[[
                                TODO: label & duration
                                        - hide if no icon
                                      custom texts
                                        -> show if no icon
                                        -> need to implement in display (along with static bars => need to build custom bar class)
                                --]]
                            },
                        },
                        texts = {
                            name = "Texts", -- TODO: localization
                            type = "group",
                            childGroups = "select",
                            order = 3,
                            disabled = function(info)
                                return not db.shown
                            end,
                            args = {
                                -- TODO: font stuff
                                header = {
                                    name = "",
                                    type = "header",
                                    order = 50,
                                },
                                create = {
                                    name = "New Text",
                                    desc = "Create a new text element",
                                    type = "execute",
                                    width = "full",
                                    func = function(info, btn)
                                        -- TODO: spawn a new text, commit to db, select in options window
                                        print(info[#info], btn)
                                    end,
                                },
                                -- dynamically filled with groups 1:1 with text elements
                            },
                        },
                    },
                }
                
                local textElements = opts.args.texts.args
                -- fill the texts options table with individual text element options
                for i = 1, #db.texts do
                    local textData = db.texts[i]
                    local name = textData.name
                    
                    local textOptions = {
                        name = name,
                        type = "group",
                        set = function(info, val)
                            local element = info[#info]
                            textData[element] = val
                            
                            addon.db:SaveDefaultSetting(element, oldVal, val, "texts", i)
                        end,
                        get = function(info)
                            local element = info[#info]
                            return textData[element]
                        end,
                        args = {
                            enabled = {
                                name = "Enable",
                                desc = "Enable/disable '"..name.."'",
                                type = "toggle",
                                width = "double",
                                order = 0,
                            },
                            groupText = {
                                name = "[Something about groups and hiding and mouse events]",
                                desc = "[TODO]",
                                type = "toggle",
                                width = "double",
                                order = 1,
                                disabled = function() return not textData.enabled end,
                            },
                            
                            delete = {
                                name = "Delete",
                                type = "execute",
                                width = "full",
                                confirm = true,
                                confirmText = "Delete text '"..name.."'?",
                                func = function()
                                    print("DELETE '"..name.."'")
                                end,
                            },
                        },
                    }
                    textElements[("text%d"):format(i)] = textOptions
                end
                
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
        elseif id == addon.db.DEFAULT_KEY then -- defaults entry
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
