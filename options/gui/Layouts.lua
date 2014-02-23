
local next = next

local addon = Overseer
local options = addon:GetModule(addon.OPTIONS_MODULE)
local AG = LibStub("AceGUI-3.0")

-- ------------------------------------------------------------------
-- Layout consts
-- ------------------------------------------------------------------
options.layouts = {
    NEW = "NEW",
    EDIT = "EDIT",
}
do -- prefix the layout strings
    local me = options:GetName()
    for k, layoutName in next, options.layouts do
        options.layouts[k] = ("%s_%s"):format(me, layoutName)
    end
end

-- ------------------------------------------------------------------
-- Edit tab layout
-- ------------------------------------------------------------------
AG:RegisterLayout(options.layouts.EDIT,
    function(content, children)
    end
)
