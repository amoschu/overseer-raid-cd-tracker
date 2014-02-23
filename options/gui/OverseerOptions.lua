
local addon = Overseer
local options = addon:NewModule(addon.OPTIONS_MODULE)
local ME = addon:GetName()
local AG = LibStub("AceGUI-3.0")

-- ------------------------------------------------------------------
-- Option structures
-- ------------------------------------------------------------------
options.consts = {
    tabs = {
        NEW = "NEW",
        EDIT = "EDIT",
        MISC = "MISC",
        PROFILES = "PROFILES",
    },
}

options.tab = {
    --[[
    tab selection handling
    
    form:
    [consts.tabs.ID] = function,
    ...
    --]]
}

-- ------------------------------------------------------------------
-- Window
-- ------------------------------------------------------------------
local function TabSelect(container, event, tab)
    container:PauseLayout()
    container:ReleaseChildren()
    options.tab[tab](container)
    container:ResumeLayout()
    container:DoLayout()
end

local function OnSizeChanged(frame, width, height)
    -- TODO: save size
    addon:Print(width..", "..height)
end

local window
local windowTabs = {
    {
        text = "New", -- TODO: localization
        value = options.consts.tabs.NEW,
    },
    {
        text = "Edit", -- TODO: localization, a better name
        value = options.consts.tabs.EDIT,
    },
    {
        text = "Misc", -- TODO: localization
        value = options.consts.tabs.MISC,
    },
    {
        text = "Profiles", -- TODO: localization
        value = options.consts.tabs.PROFILES,
    },
}
local registered
function options:OpenWindow()
    -- TODO: hook GameMenuFrame Show => Hide window if open
    
    if not window then
        window = AG:Create("Window")
        window:SetTitle(("|c%s%s|r"):format(addon.NAME_COLOR, ME))
        window:SetLayout("Fill")
        window:SetCallback("OnClose", 
            function(widget)
                local frame = widget.frame
                local numPts = frame:GetNumPoints()
                local pt, rel, relPt, x, y = frame:GetPoint()
                addon:Print(("|cff00FF00%d|r: %s, %s, %s, %.1f, %.1f"):format(numPts, pt, tostring(rel), relPt, x, y))
                -- TODO: save point(s)
                frame:SetScript("OnSizeChanged", nil)
                AG:Release(widget)
                
                window = nil
            end
        )
        
        local tabGroup = AG:Create("TabGroup")
        tabGroup:SetFullWidth(true)
        tabGroup:SetFullHeight(true)
        tabGroup:SetLayout("Fill")
        tabGroup:SetTabs(windowTabs)
        tabGroup:SetCallback("OnGroupSelected", TabSelect)
        tabGroup:SelectTab(options.consts.tabs.NEW) -- TODO: read from db
        window:AddChild(tabGroup)
        
        -- if there is no .frame, AceGUI changed its internal structure
        window.frame:SetScript("OnSizeChanged", OnSizeChanged)
    end
end

addon:ScheduleTimer(options.OpenWindow, 10, options) -- TODO: TMP
