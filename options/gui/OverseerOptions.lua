
local addon = Overseer
local options = addon:NewModule(addon.OPTIONS_MODULE)
local ME = addon:GetName()
local ACR = LibStub("AceConfigRegistry-3.0") -- need?
local ACD = LibStub("AceConfigDialog-3.0") -- need?
local AG = LibStub("AceGUI-3.0")
local ADO = LibStub("AceDBOptions-3.0") -- need?

-- ------------------------------------------------------------------
-- Option structures
-- ------------------------------------------------------------------
options.consts = {
    tabs = {
        NEW = "NEW",
        EDIT = "EDIT",
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
    container:ReleaseChildren()
    options.tab[tab](container)
end

local function OnSizeChanged(frame, width, height)
    -- TODO: save size
    addon:Print(width..", "..height)
end

local window
function options:OpenWindow()
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
        tabGroup:SetLayout("Flow")
        tabGroup:SetTabs({
            {
                text = "New",
                value = options.consts.tabs.NEW,
            },
            {
                text = "Edit", -- TODO: a better name
                value = options.consts.tabs.EDIT,
            },
            --[[
            {
                text = "Misc", ? -- some kind of meta type stuff (clamped, show alerts, etc)
            },
            {
                text = "Profiles",
            },
            --]]
        })
        tabGroup:SetCallback("OnGroupSelected", TabSelect)
        tabGroup:SelectTab(options.consts.tabs.NEW) -- TODO: read from db
        window:AddChild(tabGroup)
        
        -- if there is no .frame, AceGUI changed its internal structure
        window.frame:SetScript("OnSizeChanged", OnSizeChanged)
    end
end

addon:ScheduleTimer(options.OpenWindow, 10, options) -- TODO: TMP