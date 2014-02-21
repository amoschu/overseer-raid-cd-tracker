
local addon = Overseer

local SPELL_COLOR = "ff71D5FF"
-- |cff71d5ff|Hspell:46584|h[Raise Dead]|h|r

local function GetSpellLinkStr(spellid) -- TODO: TMP (move to Output.lua)
	return ("|cff71d5ff|Hspell:%s|h[%s]|h|r"):format(spellid, GetSpellInfo(spellid))
end

local function PrintCooldownState(spellid, skipHeader)
	local spellCooldowns = Cooldowns[spellid]
	if spellCooldowns then
		if not skipHeader then
			addon:Print(("%s -------"):format(GetSpellLinkStr(spellid)), true)
		end
		for guid, spellCD in next, spellCooldowns do
			local t = spellCD:TimeLeft()
			local outputTimeLeft = ""
			if t ~= spellCD.READY then
				local hr = t / (MIN_PER_HR * SEC_PER_MIN)
				local min = t / SEC_PER_MIN
				local sec = t % SEC_PER_MIN
				if round(hr) > 0 then
					outputTimeLeft = ("(%dh)"):format(round(hr))
				elseif round(min) >= 5 then
					outputTimeLeft = ("(%dm)"):format(round(min))
				elseif 0 < floor(min) and min < 5 then
					outputTimeLeft = ("(%dm %ds)"):format(min, sec)
				elseif floor(min) == 0 then
					outputTimeLeft = ("(%0.1fs)"):format(sec)
				end
			end
			
			local numReady = spellCD:NumReady()
			local outputReady = ""
			if numReady > 0 then
				outputReady = ("%d ready "):format(numReady)
			end
			
			local output = "%s%s: %s%s"
			addon:Print(output:format(INDENT, GUIDClassColoredName(guid), outputReady, outputTimeLeft), true)
		end	
	end
end
--
