
local addon = LibStub("AceAddon-3.0"):NewAddon("Overseer", "AceBucket-3.0", "AceEvent-3.0", "AceTimer-3.0")
-- disable by default until we know the player is grouped
addon:SetEnabledState(false)
addon:SetDefaultModuleState(false)

addon.NAME_COLOR = "ffED2939"
addon.REGISTER_COLOR = "ff6699FF"

addon.OPTIONS_MODULE = "Options"

-- ------------------------------------------------------------------
-- Set public globals
-- ------------------------------------------------------------------
Overseer = addon
