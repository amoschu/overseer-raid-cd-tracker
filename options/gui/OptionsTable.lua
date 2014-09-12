
local next = next

local addon = Overseer
local options = addon:GetModule(addon.OPTIONS_MODULE)
local AG = LibStub("AceGUI-3.0")
local LSM = LibStub("LibSharedMedia-3.0")
local MediaType = LSM.MediaType

local consts = options.consts
local MESSAGES = addon.consts.MESSAGES
local OPTIONS_APP_NAME = consts.OPTIONS_APP_NAME

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
local JUSTIFYH = {
    CENTER = "CENTER",
    LEFT = "LEFT",
    RIGHT = "RIGHT",
}
local JUSTIFYV = {
    BOTTOM = "BOTTOM",
    MIDDLE = "MIDDLE",
    TOP = "TOP",
}
local FONTFLAGS = {
    NONE = "NONE",
    MONOCHROME = "MONOCHROME",
    OUTLINE = "OUTLINE",
    THICKOUTLINE = "THICKOUTLINE",
}

local ESC_CUSTOM = "CUSTOM"
local ESC_SEQ = { [ESC_CUSTOM] = ESC_CUSTOM, }
do -- fill the values options table with the escape sequences
    local ESC_SEQUENCES = addon.consts.ESC_SEQUENCES
    for escKey, escVal in next, ESC_SEQUENCES do
        ESC_SEQ[escVal] = escKey -- TODO: add user-readable names in Constants.lua instead of using the keys
    end
end

local ON_CONFIG_CHANGE = "ConfigTableChange"

-- ------------------------------------------------------------------
-- Defaults
-- ------------------------------------------------------------------
function options.DefaultsTable(uiType, uiName, app)
    local id = app:match("_%p+$") -- appname is assumed to have the form 'ADDON_MODULE_id'
    id = id and id:sub(2)
    addon:DEBUG("DefaultsTable(%s, %s, %s): id='%s'", uiType, uiName, app, tostring(id))
    
    local db = addon.db:GetDefaultSettings()
    -- TODO: this is messing with the edit tab's saved status (maybe fixed when other selections are fleshed out?)
    local opts = {
        type = "group",
        childGroups = "tab",
        width = "full",
        args = {
            --[[
            header = {
                name = valueToText[id] or BAD_ID_VALUE,
                type = "header",
            },
            --]]
            display = {
                name = "Display", -- TODO: better name/localization
                type = "group",
                order = 0,
                set = function(info, val)
                    local element = info[#info]
                    local oldVal = db[element]
                    db[element] = val
                    
                    addon.db:SaveDefaultSetting(element, oldVal, val)
                    if id then
                        addon:SendMessage(MESSAGES.OPT_DISPLAY_UPDATE, id)
                    end
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
                            if id then
                                addon:SendMessage(MESSAGES.OPT_DISPLAY_UPDATE, id)
                            end
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
                                addon:ERROR("Could not find a frame named '%s'", input)
                            end
                            return valid
                        end,
                        set = function(info, input)
                            local element = "relFrame"
                            local oldVal = db[element]
                            local newVal = input:len() > 0 and input or nil
                            db[element] = newVal
                            
                            addon.db:SaveDefaultSetting(element, oldVal, newVal)
                            if id then
                                addon:SendMessage(MESSAGES.OPT_DISPLAY_UPDATE, id)
                            end
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
                    if id then
                        addon:SendMessage(MESSAGES.OPT_ICON_UPDATE, id)
                    end
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
                            if id then
                                addon:SendMessage(MESSAGES.OPT_ICON_UPDATE, id)
                            end
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
                            if id then
                                addon:SendMessage(MESSAGES.OPT_ICON_UPDATE, id)
                            end
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
                            if id then
                                addon:SendMessage(MESSAGES.OPT_ICON_UPDATE, id)
                            end
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
                            if id then
                                addon:SendMessage(MESSAGES.OPT_ICON_UPDATE, id)
                            end
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
            font = {
                name = "Font", -- TODO: localization
                type = "group",
                order = 3,
                disabled = function(info)
                    return not db.shown
                end,
                confirm = function(info)
                    local doConfirm = true -- TODO: only for the default spells & if db.confirmFontSettings or something
                    return doConfirm and ("Override all other '%s' font settings?"):format(info[#info]) -- TODO: this message may not be clear to the user
                end,
                set = function(info, val)
                    local element = info[#info]
                    local fontDB = db.font
                    local oldVal = fontDB[element]
                    fontDB[element]= val
                    
                    addon.db:SaveDefaultSetting(element, oldVal, val, "font")
                    -- TODO: set every font.element to nil
                end,
                get = function(info)
                    local element = info[#info]
                    return db.font[element]
                end,
                args = {
                    disclaimer = {
                        name = "These settings will override font options set elsewhere!",
                        type = "header",
                        order = 0,
                    },
                    font = {
                        name = "Default Font",
                        desc = "Set the default font",
                        type = "select",
                        dialogControl = "LSM30_Font",
                        values = LSM:HashTable(MediaType.FONT),
                        width = "normal",
                        order = 1,
                    },
                    shadow = {
                        name = "Font Shadow",
                        desc = "Enable/disable font shadow",
                        type = "toggle",
                        width = "normal",
                        order = 2,
                    },
                    size = {
                        name = "Default Font Size",
                        desc = "Set the default font size",
                        type = "range",
                        min = 1,
                        softMax = 24,
                        bigStep = 1,
                        width = "normal",
                        order = 3,
                    },
                    flags = {
                        name = "Default Font Flags",
                        desc = "Set the default font flags",
                        type = "select",
                        values = FONTFLAGS,
                        width = "normal",
                        order = 4,
                    },
                    justifyH = {
                        name = "Horizontal Alignment",
                        desc = "Set the default horizontal text alignment",
                        type = "select",
                        values = JUSTIFYH,
                        width = "normal",
                        order = 5,
                    },
                    justifyV = {
                        name = "Vertical Alignment",
                        desc = "Set the default vertical text alignment",
                        type = "select",
                        values = JUSTIFYV,
                        width = "normal",
                        order = 6,
                    },
                    useClassColor = {
                        name = "Use Class Color",
                        desc = "Color the text with the caster's class color (this overrides any manually set text color)",
                        type = "toggle",
                        width = "normal",
                        order = 7,
                    },
                    textColor = {
                        name = "Text Color",
                        desc = "Set the default text color",
                        type = "color",
                        width = "normal",
                        order = 8,
                        disabled = function(info)
                            return db.font.useClassColor
                        end,
                        set = function(info, r, g, b)
                            local fontDB = db.font
                            local oldR = fontDB.r
                            local oldG = fontDB.g
                            local oldB = fontDB.b
                            
                            fontDB.r = r -- TODO: create a Database wrapper to set color/alpha
                            fontDB.g = g
                            fontDB.b = b
                            
                            addon.db:SaveDefaultSetting("r", oldR, r, "font")
                            addon.db:SaveDefaultSetting("g", oldG, g, "font")
                            addon.db:SaveDefaultSetting("b", oldB, b, "font")
                            -- TODO: broadcast a message or something so that active display elements update
                        end,
                        get = function(info)
                            local fontDB = db.font
                            return fontDB.r, fontDB.g, fontDB.b
                        end,
                    },
                    
                    -- TODO: dead/offl/oncd colors
                },
            },
            texts = {
                name = "Texts", -- TODO: localization
                type = "group",
                childGroups = "select",
                order = 4,
                disabled = function(info)
                    return not db.shown
                end,
                args = {
                    create = {
                        name = "New Text",
                        desc = "Create a new text element",
                        type = "execute",
                        width = "normal",
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
            name = name, -- TODO: renaming
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
                valueSimple = {
                    name = "Text",
                    desc = "Set what this text element should display",
                    type = "select",
                    values = ESC_SEQ,
                    width = "full",
                    order = 2,
                    disabled = function() return not textData.enabled end,
                    set = function(info, val)
                        local isCustom = val == ESC_CUSTOM
                        textData.isCustom = isCustom
                        textData.value = not isCustom and val or ""
                    end,
                    get = function(info)
                        return textData.isCustom and ESC_CUSTOM or textData.value
                    end,
                },
                valueCustom = {
                    name = "Custom Text",
                    desc = "[TODO]", -- TODO: explain if statements and stuff.. include all esc sequences?
                    type = "input",
                    width = "full",
                    order = 3,
                    disabled = function() return not textData.enabled end,
                    hidden = function() return not textData.isCustom end,
                    -- TODO: some kind of validation ? only need to validate if a '%' sign is present I think
                    set = function(info, val)
                        textData.value = val
                    end,
                    get = function(info)
                        return textData.value
                    end,
                },
                
                positioning = {
                    name = "",
                    type = "header",
                    order = 4,
                },
                x = {
                    name = "X Offset",
                    desc = "Set the text's x offset relative to its anchor frame",
                    type = "range",
                    softMin = -16,
                    softMax = 16,
                    bigStep = 1,
                    width = "normal",
                    order = 5,
                    disabled = function() return not textData.enabled end,
                },
                y = {
                    name = "Y Offset",
                    desc = "Set the text's y offset relative to its anchor frame",
                    type = "range",
                    softMin = -16,
                    softMax = 16,
                    bigStep = 1,
                    width = "normal",
                    order = 6,
                    disabled = function() return not textData.enabled end,
                },
                point = {
                    name = "Point",
                    desc = "Set the text's anchor point",
                    type = "select",
                    values = POINT,
                    width = "normal",
                    order = 7,
                    disabled = function() return not textData.enabled end,
                },
                relPoint = {
                    name = "Relative Point",
                    desc = "Set the text's anchor point to its parent frame",
                    type = "select",
                    values = POINT,
                    width = "normal",
                    order = 8,
                    disabled = function() return not textData.enabled end,
                },
                
                fontSettings = {
                    name = "",
                    type = "header",
                    order = 9,
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

-- ------------------------------------------------------------------
-- 
-- ------------------------------------------------------------------
