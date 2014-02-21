
local select, wipe, remove, concat
	= select, wipe, table.remove, table.concat
local GetAddOnInfo, IsAddOnLoaded, InCombatLockdown, UnitAffectingCombat, LoadAddOn, SendChatMessage
	= GetAddOnInfo, IsAddOnLoaded, InCombatLockdown, UnitAffectingCombat, LoadAddOn, SendChatMessage
	
local addon = Overseer

local consts = addon.consts
local append = addon.TableAppend

local INDENT = consts.INDENT
local OPTIONS = "OverseerOptions"
local PLAYER_REGEN_ENABLED = "PLAYER_REGEN_ENABLED"

local waitingToLoad -- flag indicating that user attempted to load options while in combat

function addon:LoadOptions()
	if waitingToLoad and not IsAddOnLoaded(OPTIONS) then
		waitingToLoad = nil
	
		local loaded, reason = LoadAddOn(OPTIONS)
		if not loaded then
			local msg = "Failed to load %s: %s."
			addon:Warn(msg:format(OPTIONS, _G["ADDON_" .. reason]))
		else
			-- TODO - needed?
			--[[
			local options = addon:GetModule("Options")
			options:Enable()
			--]]
			
			local msg = "%s loaded!"
			addon:Info(msg:format(OPTIONS))
		end
	end
end

local function TryToLoadOptions()
	if not addon:GetModule("Options", true) then
		local enabled = select(4, GetAddOnInfo(OPTIONS))
		if enabled then
			if InCombatLockdown() or UnitAffectingCombat("player") then
				local msg = "Loading %s after combat ends."
				addon:Info(msg:format(OPTIONS))
				waitingToLoad = true
			else
				addon:LoadOptions()
			end
		else -- TODO: missing logic & msg
			local msg = "Could not load %s because it is not enabled."
			addon:Error(msg:format(OPTIONS))
		end
	end
end

local function OpenConfigWindow()
	-- TODO (this may not need to be it's own function)
end

-- ------------------------------------------------------------------
-- Slash Commands
-- ------------------------------------------------------------------
local slash1 = "/os" -- hope this doesn't collide with any other addons
local slash2 = "/overseer"
SLASH_OVERSEER1 = slash1
SLASH_OVERSEER2 = slash2

local splitString = {}
local function split(str, delim)
	wipe(splitString)	
	if type(str) == "string" then
		delim = delim or "%s+" -- default to whitespace
		local notDelim = ("[^%s]"):format(delim)
		local startIdx = str:find(notDelim)
		local endIdx = str:find(delim, startIdx)
		while startIdx do
			append(splitString, str:sub(startIdx, endIdx and endIdx-1))
			if not endIdx then break end -- so we capture the last element
			startIdx = str:find(notDelim, endIdx+1)
			endIdx = str:find(delim, startIdx)
		end
	end
	return splitString
end

local usage = {
	("Usage: %s"):format(slash1),
	("%s%s: Opens the GUI options (must be enabled in character select screen)."):format(INDENT, slash1),
	("%s%s |cff999999help|r: Displays this help message."):format(INDENT, slash1),
	("%s%s |cff999999help|r |cffCCCCCCcmd|r: Displays the help message for the specified command 'cmd'."):format(INDENT, slash1),
}
local validCmds = {}
local function PrintValidCmds()
	addon:Print(("%sValid commands: %s"):format(INDENT, concat(validCmds, ", ")), true)
end

local commands = {}
local unrecognized = {}
commands["help"] = function(args)
	wipe(unrecognized)
	local printedAtLeastOne
	for i = 1, #args do
		local arg = args[i]
		local help = type(commands[arg]) == "function" and commands[arg]
		if help then
			if not (arg == "h" or arg == "help") then
				help()
				printedAtLeastOne = true
			end
		else
			append(unrecognized, arg)
		end
	end
	
	if #unrecognized > 0 then
		addon:Print(("%sUnrecognized %s: %s"):format(INDENT, #unrecognized == 1 and "command" or "commands", concat(unrecognized, ", ")), true)
		PrintValidCmds()
	elseif not printedAtLeastOne then
		-- print generic usage
		for i = 1, #usage do
			addon:Print(usage[i], true)
		end
		PrintValidCmds()
	end
end

local CHANNELS = {
	["s"] = "SAY",
	["say"] = "SAY",
	["e"] = "EMOTE",
	["me"] = "EMOTE",
	["emote"] = "EMOTE",
	["y"] = "YELL",
	["yell"] = "YELL",
	["p"] = "PARTY",
	["party"] = "PARTY",
	["ra"] = "RAID",
	["raid"] = "RAID",
	["rw"] = "RAID_WARNING",
	["i"] = "INSTANCE_CHAT",
	["instance"] = "INSTANCE_CHAT",
	["g"] = "GUILD",
	["gu"] = "GUILD",
	["guild"] = "GUILD",
	["o"] = "OFFICER",
	["officer"] = "OFFICER",
	["w"] = "WHISPER",
	["whisper"] = "WHISPER",
}
commands["brez"] = function(args)
	if args then
		local channel = args[1] or "ra"
		channel = channel:lower() -- sanitize user input
		local target = args[2] or tonumber(channel) -- playername or channel number (for whisper or custom channel respectively)
		
		-- set the appropriate channel
		channel = type(target) == "number" and "CHANNEL" or CHANNELS[channel] or CHANNELS["ra"]
		if channel == "WHISPER" and target == nil then
			-- bad user input
			addon:Warn(("%s brez %s: Who do you want to whisper? Usage: '%s brez %s name'"):format(slash1, args[1], slash1, args[1]))
		end
		
		-- TODO: are extraneous arguments discarded? eg, what happens if "RAID" is passed as 2nd arg and "playername" as 4th?
		--SendChatMessage(addon:BrezOutputString(), channel, nil, target)
	else
		-- help msg
		local msg = "%s brez [channel]: Outputs current remaining battle resurrections to the specified channel. Has no effect when not fighting a boss. Defaults to raid."
		addon:Print(msg:format(slash1), true)
	end
end

commands["unlock"] = function(args)
	if args then
		local objType = args[1]
		if objType and objType == "f" or objType == "frame" then
			-- TODO: less hacky unlock based on arg[1] (group vs frames)
			addon:UnlockAllMovables("Frame")
		else
			addon:UnlockAllMovables("Group")
		end
	else
		local msg = "%s unlock: Unlocks all active groups, allowing them to be repositioned or resized."
		addon:Print(msg:format(slash1), true)
	end
end

commands["lock"] = function(args)
	if args then
		addon:LockAllMovables()
	else
		local msg = "%s lock: Locks all active displays, preventing any further repositioning or resizing."
		addon:Print(msg:format(slash1), true)
	end
end

commands["config"] = function(args)
	if args then
		addon:Print("[Config mode under construction - check back later]", true)
		--
		local onOff = args[1]
		if onOff == "on" then
			-- switch on
		elseif onOff == "off" then
			-- switch off
		elseif onOff and onOff:len() > 0 then
			local msg = "%s config: Did you want config mode 'on' or 'off'? You typed '%s'."
			addon:Warn(msg:format(slash1, onOff))
		else
			-- TODO: toggle
		end
		--
	else
		local msg = "%s config [on/off]: Toggles config mode on/off if specified, toggles if not specified."
		addon:Print(msg:format(slash1), true)
	end
end

do -- build the valid cmd list (don't include the short aliases)
	for cmd, f in next, commands do
		if type(f) == "function" then
			append(validCmds, ("'%s'"):format(cmd))
		end
	end
end

commands["debug"] = function(args)
	if args then
		local badCmdOrArg
		local cmd = args[1]
		if cmd then
			if cmd == "i" or cmd:match("^inspect") then
				addon:DebugInspects()
			elseif cmd == "g" or cmd:match("^group") then
				addon:DebugGroupCache(args[2])
			elseif cmd == "c" or cmd:match("^cooldown") then
				addon:DebugCooldowns(args[2])
			elseif cmd == "s" or cmd == "ss" or cmd:match("^save") then
				addon:DebugSavedState()
			else
				badCmdOrArg = true
			end
		else
			badCmdOrArg = true
		end
		if badCmdOrArg then
			local msg = "Usage: %s debug [i/g/c/s [unit/key]]"
			addon:Warn(msg:format(slash1))
		end
	end
end
commands["d"] = commands["debug"]

-- TODO: TMP
commands["e"] = function(args) addon:Enable() end

-- shorter aliases
commands["h"] = commands["help"]
commands["u"] = commands["unlock"]
commands["l"] = commands["lock"]
commands["cfg"] = commands["config"]

function SlashCmdList.OVERSEER(msg)
	msg = msg:lower()
	local args = split(msg)
	local cmd = remove(args, 1)
	
	if cmd then
		local exec = type(commands[cmd]) == "function" and commands[cmd] or commands['h']
		exec(args)
	else
		addon:Print("[GUI mode under construction - check back later]", true)
		--[[
		TryToLoadOptions()
		OpenConfigWindow()
		--]]
	end
end
