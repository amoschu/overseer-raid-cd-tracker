
local addon = Overseer
local options = addon:GetModule(addon.OPTIONS_MODULE)
local AG = LibStub("AceGUI-3.0")

local consts = options.consts

-- ------------------------------------------------------------------
-- 'Create' tab
-- ------------------------------------------------------------------
options.tab[consts.tabs.NEW] = function(container)
    -- local scrollFrame = AG:Create("ScrollFrame")
    -- scrollFrame:SetFullWidth(true)
    -- scrollFrame:SetFullHeight(true)
    -- scrollFrame:SetLayout("List")
    
    container:SetLayout("List")
    
    local topSpacing = AG:Create("SimpleGroup")
    --topSpacing:SetFullWidth(true)
    --topSpacing:SetFullHeight(true)
    topSpacing:SetLayout("Fill")
    container:AddChild(topSpacing)
    
    -- local displayHeader = AG:Create("Heading")
    -- displayHeader:SetText("Track a new spell")
    -- displayHeader:SetFullWidth(true)
    -- scrollFrame:AddChild(displayHeader)
    
    local display = AG:Create("Button")
    display:SetText("Track a new spell")
    display:SetFullWidth(true)
    display:SetCallback("OnClick", function() print("TRACK SPELL FLOW") end)
    container:AddChild(display)
    
    -- local groupHeader = AG:Create("Heading")
    -- groupHeader:SetText("Create a new group")
    -- groupHeader:SetFullWidth(true)
    -- scrollFrame:AddChild(groupHeader)
    
    local spacer = AG:Create("Heading")
    spacer:SetFullWidth(true)
    container:AddChild(spacer)
    
    local group = AG:Create("Button")
    group:SetText("Create a new group")
    group:SetFullWidth(true)
    group:SetCallback("OnClick", function() print("CREATE NEW GROUP FLOW") end)
    container:AddChild(group)
end
