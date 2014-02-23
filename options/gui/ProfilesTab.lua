
local addon = Overseer
local options = addon:GetModule(addon.OPTIONS_MODULE)
local AG = LibStub("AceGUI-3.0")
local ACR = LibStub("AceConfigRegistry-3.0")
local ACD = LibStub("AceConfigDialog-3.0")
local ADO = LibStub("AceDBOptions-3.0")

local consts = options.consts

-- ------------------------------------------------------------------
-- 'Profiles' tab
-- ------------------------------------------------------------------
local PROFILE = ("%s_Profiles"):format(options:GetName())
options.tab[consts.tabs.PROFILES] = function(container)
    -- let the ace3 wizards do their voodoo magicks
    local profileOptions = ADO:GetOptionsTable(addon.db.Database)
    ACR:RegisterOptionsTable(PROFILE, profileOptions)
    ACD:Open(PROFILE, container)
    container:SetTitle("") -- whenever the user does stuff to the profile, the title is set..
    
    -- TODO? hook/override the 'Reset Profile' button
end
