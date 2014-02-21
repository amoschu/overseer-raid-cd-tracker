
local select, wipe, setmetatable, tostring, next, type, remove
	= select, wipe, setmetatable, tostring, next, type, table.remove
local GetSpellInfo, GetNumTalents, GetSpellBaseCooldown, UnitClass
	= GetSpellInfo, GetNumTalents, GetSpellBaseCooldown, UnitClass

local addon = Overseer
addon.data = {}

local data, consts = addon.data, addon.consts
local classes, specs = consts.classes, consts.specs
local filterKeys, filterMods = consts.filterKeys, consts.filterMods
local append = addon.TableAppend

local MAX_NUM_TALENTS = MAX_NUM_TALENTS
local MSEC_PER_SEC = consts.MSEC_PER_SEC
local FILTER_REQUIRED = consts.FILTER_REQUIRED
local FILTER_OPTIONAL = consts.FILTER_OPTIONAL
local FILTER_MOD_VALUE = consts.FILTER_MOD_VALUE
local FILTER_MOD_OP = consts.FILTER_MOD_OP
local EVENT_DELIM = consts.EVENT_DELIM
local EVENT_PREFIX_CLEU = consts.EVENT_PREFIX_CLEU
local optionalKeys = filterKeys[FILTER_OPTIONAL]
local NUM_FILTERS = "NUM_FILTERS"

local filtersByClass = {
	--[[
	cache of all active filters per class - filled dynamically
	
	form:
	[class] = {
		filter = true,
	},
	...
	--]]
}
data.filtersByClass = filtersByClass

local spellidsByClass = {
	--[[
	cache of cooldown spellids per class
	
	form:
	[class] = {
		[spellid] = true,
		...
	},
	...
	--]]
}

local buffSpellIdsByClass = {
	--[[
	cache of buff spellids per class
	ie, the buff spellids are relevant to the keyed class for tracking (eg, symbiosis)
	
	form:
	[class] = {
		[buffSpellId] = true,
		...
	},
	...
	--]]
}

local trackedData = {
	--[[
	encoded cache of tracked cooldowns
	
	filters are optional (see 'filterKeys' for list of filters)
	
	form:
	[class] = {
		[spellid] = { -- aka trackedCD
			cd = baseCdDuration, -- in seconds
			charges = nil or numCharges,
			buffDuration = nil or duration, -- in seconds (optional), specifies the duration of the spellid if any
			
			[FILTER_REQUIRED] = nil or {
				-- at least one filter
				filter = filterValue,
				...
			},
			
			[FILTER_OPTIONAL] = nil or {
				modification = {
					modValue = value, -- eg, modifiedCdDuration or numCharges,
					modOp = operation, -- the operation to apply to the base
											trackedCD[modification] is the value to modify
					
					[FILTER_REQUIRED] = {
						-- at least one filter
						filter = filterValue,
						...
					},
				},
				...
			},
		},
		...
	},
	...
	--]]
}

local modOperations = {
	--[[
	list of operations which specify how a modification value is applied to the base value
	eg. base.cd '=' mod.cd -> the modified cd will replace the base cd
	--]]
	
	-- mod value should never be nil
	
	-- replace
	["="] = function(base, mod)
		return mod
	end,

	-- add
	["+"] = function(base, mod)
		return (base or 0) + mod
	end,
	
	-- subtract
	["-"] = function(base, mod)
		-- mod should never be > base
		-- TODO: need to abs this just in case?
		return base - mod
	end,
	
	-- mult
	-- for use with cd reduction percentages in mind
	-- eg, base.cd = 2 * 60, mod.cd = 0.75 (ie, 25% cd reduction)
	["*"] = function(base, mod) -- TODO: I don't think this works for multiple mods (order of operations)
		-- a missing base value does not really make sense here
		-- neither does a default base value
		-- eg, base.charges '*' mod.charges -> doesn't make sense (moreso if base.charges is nil)
		return base * mod
	end,
	
	-- div
	-- "cooldown recovery rate"
	-- eg, AoC -> http://www.wowhead.com/item=102292/assurance-of-consequence#comments
	["/"] = function(base, mod) -- TODO: I don't think this works for multiple mods (order of operations)
		return base / mod
	end,
}

local function GetSpellBaseCooldownSeconds(spellid)
	local cdDuration = GetSpellBaseCooldown(spellid)
	return cdDuration and (cdDuration / MSEC_PER_SEC)
end
addon.GetSpellBaseCooldownSeconds = GetSpellBaseCooldownSeconds

local function IsValidClassId(class)
	return type(class) == "string" and classes[class]
end

-- checks if a spellid may be valid
local function IsValidSpellId(spellid)
	return type(spellid) == "number" and GetSpellInfo(spellid) ~= nil
end

-- checks if a talent may be a valid talent index
local function IsValidTalent(talent)
	return type(talent) == "number" and 0 < talent and talent <= MAX_NUM_TALENTS
end

local IsFilterOk = {}
IsFilterOk[optionalKeys.SPEC] = function(spec)
	return spec == nil or (type(spec) == "number" and (specs[spec] ~= nil or specs[-spec] ~= nil))
end
IsFilterOk[optionalKeys.TALENT] = function(talent)
	return talent == nil or IsValidTalent(talent) or IsValidTalent(-talent)
end
IsFilterOk[optionalKeys.GLYPH] = function(glyph)
	return glyph == nil or IsValidSpellId(glyph) or IsValidSpellId(-glyph)
end
IsFilterOk[optionalKeys.BUFF] = function(buff)
	return buff == nil or IsValidSpellId(buff) or IsValidSpellId(-buff)
end
IsFilterOk[optionalKeys.PET] = function(pet)
	return pet == nil or type(pet) == "string"
end

local function ValidateFilters(data)
	if data == nil then
		return true -- filters are optional so receiving nothing here is ok
	elseif type(data) ~= "table" then
		return false -- if we receive a non-table, however, the data is not clean
	end

	local ok = true
	local atLeastOne = false
	
	-- try to verify that filters are of a valid form
	for key in next, data do
		local validateFilterData = IsFilterOk[key]
		if type(validateFilterData) == "function" then
			local filter = data[key]
			atLeastOne = atLeastOne or (filter and true)
			if type(filter) == "table" then
				for i = 1, filter[NUM_FILTERS] do
					ok = validateFilterData(filter[i])
					if not ok then break end
				end
			else
				ok = validateFilterData(filter)
			end
		else
			local msg = "ValidateFilters(): no validation function defined for '%s'!"
			addon:Debug(msg:format(key))
			break
		end
		
		if not ok then break end -- TODO: don't break; store all that fail
	end
	
	--[[
	if ok then -- spec
		local spec = data[optionalKeys.SPEC]
		atLeastOne = atLeastOne or (spec and true)
		if type(spec) == "table" then
			for i = 1, #spec do
				ok = IsSpecOk(spec[i])
				if not ok then break end
			end
		else
			ok = IsSpecOk(spec)
		end
	end
	if ok then -- talent
		local talent = data[optionalKeys.TALENT]
		atLeastOne = atLeastOne or (talent and true)
		if type(talent) == "table" then
			for i = 1, #talent do
				ok = IsTalentOk(talent[i])
				if not ok then break end
			end
		else
			ok = IsTalentOk(talent)
		end
	end
	if ok then -- glyph
		local glyph = data[optionalKeys.GLYPH]
		atLeastOne = atLeastOne or (glyph and true)
		if type(glyph) == "table" then
			for i = 1, #glyph do
				ok = IsGlyphOk(glyph[i])
				if not ok then break end
			end
		else
			ok = IsGlyphOk(glyph)
		end
	end
	if ok then -- buff
		local buff = data[optionalKeys.BUFF]
		atLeastOne = atLeastOne or (buff and true)
		ok = 
	end
	if ok then -- pet
		local pet = data[optionalKeys.PET]
		atLeastOne = atLeastOne or (pet and true)
		ok = 
	end
	--]]
	
	return ok and atLeastOne
end

local function ValidateCooldownData(spellid, class, cooldownData, modData) -- TODO: need to return what failed
	-- not bulletproof by any means, but better than nothing

	local field
	local ok = true

	if ok then -- spellid
		ok = IsValidSpellId(spellid)
	end
	if ok then -- class
		ok = IsValidClassId(class)
	end
	
	if type(cooldownData) == "table" then
		if ok then -- cooldown
			local cd = cooldownData[filterKeys.CD]
			-- allow missing cd (fill in with GetSpellBaseCooldown)
			ok = cd == nil or (type(cd) == "number" and cd >= 0) -- TODO: check GetSpellBaseCooldown returns something
		end
		if ok then -- charges
			local charges = cooldownData[filterKeys.CHARGES]
			-- missing charges == 1 charge
			ok = charges == nil or (type(charges) == "number" and charges > 0)
		end
		if ok then
			local buffDuration = cooldownData[filterKeys.BUFF_DURATION]
			ok = charges == nil or (type(buffDuration) == "number" and buffDuration > 0)
		end
		if ok then
			ok = ValidateFilters(cooldownData[FILTER_REQUIRED])
		end
	end
	
	if ok then
		if type(modData) == "table" then
			-- check modification filters
			for modKey, mod in next, modData do
				local modValue = mod[FILTER_MOD_VALUE]
				ok = type(modValue) == "number" and modValue > 0
				
				if not ok then break end
				
				local modOp = mod[FILTER_MOD_OP]
				ok = type(modOp) == "string" and type(modOperations[modOp]) == "function"
				
				if not ok then break end
				
				ok = ValidateFilters(mod[FILTER_REQUIRED])
				
				if not ok then break end
			end
		end
	end
	
	return ok
end

local function CopyFilterData(target, filterData)
	if filterData then
		for filterKey, filterValue in next, filterData do
			target[FILTER_REQUIRED] = target[FILTER_REQUIRED] or {}
			
			if type(filterValue) == "table" then
				for i = 1, filterValue[NUM_FILTERS] do
					local value = filterValue[i]
					if value ~= nil then -- don't fill our internal data with holes
						target[FILTER_REQUIRED][filterKey] = target[FILTER_REQUIRED][filterKey] or {}
						append(target[FILTER_REQUIRED][filterKey], value)
					end
				end
			else
				target[FILTER_REQUIRED][filterKey] = filterValue
			end
		end
	end
end

local function CacheClassRelevantBuffs(class, buffSpellId)
	if buffSpellId < 0 then
		buffSpellId = -buffSpellId
	end
	if IsValidSpellId(buffSpellId) then
		
		buffSpellIdsByClass[class] = buffSpellIdsByClass[class] or {}
		buffSpellIdsByClass[class][buffSpellId] = true
	end
end

local function CacheClassData(spellid, class, cooldownData, modData)
	local classFilters = filtersByClass[class]
	if not classFilters then
		classFilters = {
			--[[
			flags filterKeys that exist for this class
			flat table keyed by filterKeys
			
			form:
			filterKey = true,
			...
			--]]
		}
		filtersByClass[class] = classFilters
	end
	-- flag any required filters that exist
	local requiredFilters = cooldownData and cooldownData[FILTER_REQUIRED]
	if requiredFilters then
		for _, key in next, optionalKeys do
			local keyExists = requiredFilters[key] ~= nil
			classFilters[key] = classFilters[key] or keyExists
			
			-- cache any buff ids encountered
			if keyExists and key == optionalKeys.BUFF then
				if type(requiredFilters[key]) == "table" then
					for i = 1, requiredFilters[key][NUM_FILTERS] do
						local buffSpellId = requiredFilters[key][i]
						CacheClassRelevantBuffs(class, buffSpellId)
					end
				else
					CacheClassRelevantBuffs(class, requiredFilters[key])
				end
			end
		end
	end
	-- flag any modification filters that exist
	if modData then
		for _, key in next, optionalKeys do
			for modKey, mod in next, modData do -- modKey == "CD", "CHARGES"
				local modFilters = mod[FILTER_REQUIRED]
				local keyExists = modFilters[key] ~= nil
				classFilters[key] = classFilters[key] or keyExists
				
				if keyExists and key == optionalKeys.BUFF then
					if type(modFilters[key]) == "table" then
						for i = 1, modFilters[key][NUM_FILTERS] do
							local buffSpellId = modFilters[key][i]
							CacheClassRelevantBuffs(class, buffSpellId)
						end
					else
						CacheClassRelevantBuffs(class, modFilters[key])
					end
				end
			end
		end
	end
	
	-- cache the spellid for quicker lookups
	spellidsByClass[class] = spellidsByClass[class] or {}
	spellidsByClass[class][spellid] = true
end

local indent = consts.INDENT
local function DebugUsageAddCooldown(spellid, cooldownData, modData) -- TODO: I don't think this works properly
	local msg = "Failed to add cooldown data. Please verify the data for %s(%s):\n%s%s:\n%s"
	local data, optional = "", ""
	if type(cooldownData) == "table" then
		for k, v in next, cooldownData do
			if k == FILTER_REQUIRED and type(v) == "table" then
				data = ("%s%s%s:\n"):format(data, indent, tostring(k))
				for filterKey, filterVal in next, v do
					data = ("%s%s%s=%s\n"):format(data, indent:rep(2), tostring(filterKey), tostring(filterVal))
				end
			else
				data = ("%s%s%s=%s\n"):format(data, indent, tostring(k), tostring(v))
			end
		end
	else
		data = indent .. "<cdData: type '" .. type(cooldownData) .. "'>"
	end
	
	if type(modData) == "table" then
		for modKey, mod in next, modData do
			optional = ("%s%s%s:\n"):format(optional, indent:rep(2), tostring(modKey))
			
			if type(mod) == "table" then
				for k, v in next, mod do
					if k == FILTER_REQUIRED and type(v) == "table" then
						optional = ("%s%s%s:\n"):format(optional, indent, tostring(k))
						for filterKey, filterVal in next, v do
							optional = ("%s%s%s=%s\n"):format(optional, indent:rep(2), tostring(filterKey), tostring(filterVal))
						end
					else
						optional = ("%s%s%s=%s\n"):format(optional, indent:rep(2), tostring(k), tostring(v))
					end
				end
			else
				optional = indent .. "<mod: type'" .. type(mod) .. "'>"
			end
		end
	else
		optional = indent .. "<modData: type '" .. type(modData) .. "'>"
	end
	
	addon:Debug(msg:format(tostring(GetSpellInfo(spellid)), tostring(spellid), data, FILTER_OPTIONAL, optional))
end

-- master cooldown encoding function
local function AddCooldown(spellid, class, cooldownData, modData)
	if ValidateCooldownData(spellid, class, cooldownData, modData) then
		local trackedClass = trackedData[class]
		if not trackedClass then
			trackedClass = {}
			trackedData[class] = trackedClass
		end
	
		local trackedCD = trackedClass[spellid]
		if not trackedCD then
			trackedCD = {}
			trackedClass[spellid] = trackedCD
		else
			local msg = "Duplicate cooldown data found for spellid=%d (%s) - overwriting"
			addon:Warn( msg:format(spellid, (GetSpellInfo(spellid))) )
			
			wipe(trackedCD)
		end
		
		-- store the cooldown duration data
		trackedCD[filterKeys.CD] = cooldownData and cooldownData[filterKeys.CD] or GetSpellBaseCooldownSeconds(spellid)
		if not trackedCD[filterKeys.CD] then
			-- we failed to get any cd duration info
			-- TODO: return error? :SendMessage(CD_MISSING_DURATION_ERROR)?
			local msg = "AddCooldown(): %s (%s) has no cooldown!"
			addon:Critical(msg:format(tostring(spellid), tostring(GetSpellInfo(spellid))), 3)
		end
		
		-- store the cooldown charges data
		trackedCD[filterKeys.CHARGES] = cooldownData and cooldownData[filterKeys.CHARGES]
		
		-- store buff duration if any
		trackedCD[filterKeys.BUFF_DURATION] = cooldownData and cooldownData[filterKeys.BUFF_DURATION]
		
		-- store the required filters
		if cooldownData then
			CopyFilterData(trackedCD, cooldownData[FILTER_REQUIRED])
		end
		
		-- store the modifications
		if modData then
			trackedCD[FILTER_OPTIONAL] = trackedCD[FILTER_OPTIONAL] or {}
			for modKey, mod in next, modData do
				local modification = {}
				trackedCD[FILTER_OPTIONAL][modKey] = modification
				
				for k, v in next, mod do
					if k == FILTER_REQUIRED and type(v) == "table" then
						-- the modification's filters
						CopyFilterData(modification, v)
					else
						modification[k] = v
					end
				end
			end
		end
		
		-- cache data keyed by class
		CacheClassData(spellid, class, cooldownData, modData)
	else
		DebugUsageAddCooldown(spellid, cooldownData, modData)
	end
end

-- ------------------------------------------------------------------
-- Utility functions
-- ------------------------------------------------------------------
-- applies the modification and returns the result
function addon:ApplyModification(op, base, mod)
	if type(op) == "string" then
		local operation = modOperations[op]
		if type(operation) == "function" then
			return operation(base, mod)
		end
	end
end

function addon:GetCooldownDataFor(class, spellid)
	return type(class) == "string" and classes[class] and type(spellid) == "number" and trackedData[class][spellid]
end

--[[
returns table
	{
		[spellid] = true,
		...,
	}
for all data belonging to this class
--]]
function addon:GetClassSpellIdsFromData(class)
	return class and spellidsByClass[class]
end

--[[
	{
		[spellid] = true,
		...
	}
--]]
function addon:GetClassBuffIdsFromData(class)
	return class and buffSpellIdsByClass[class]
end

local filteredCooldowns = {}
local function FilterOutCooldown(spellid, filterValue, queryValue)
	local added = false
	if filterValue ~= nil and filterValue == queryValue then
		filteredCooldowns[spellid] = true
		added = true
	end
	
	return added
end

-- returns table { [spellid] = true, ... } for all spells that match the query
function addon:GetAllCooldownDataForFilter(class, filterKey, filterValue)
	wipe(filteredCooldowns)
	
	if filterKey and filterValue then
		local classData = trackedData[class]
	
		if classData then
			for spellid, data in next, classData do
				local added = false
			
				-- check required filters
				local dataFilterValue = data[FILTER_REQUIRED] and data[FILTER_REQUIRED][filterKey]
				added = FilterOutCooldown(spellid, dataFilterValue, filterValue)
				
				-- check mod filters
				if not added then
					local optionalFilters = data[FILTER_OPTIONAL]
					if optionalFilters then
						for modKey, modData in next, optionalFilters do
							dataFilterValue = modData[FILTER_REQUIRED] and modData[FILTER_REQUIRED][filterKey]
							added = FilterOutCooldown(spellid, dataFilterValue, filterValue)
							
							if added then break end
						end
					end
				end
			end
		end
	end
	
	return filteredCooldowns
end

-- ------------------------------------------------------------------
-- Cooldown encoding functions
-- ------------------------------------------------------------------
local cdData = {} -- work table
local reqFilters = {}

local function debugUsage(callFuncName, missingArgName)
	local msg = ":%s() missing %s argument. Did you mean to use :AddCooldown() instead?"
	addon:Debug(msg:format(callFuncName, missingArgName))
end

local additionalFilters = {}
local function PackAdditionalFilters(...)
	wipe(additionalFilters)
	local numArgs = select('#', ...)
	for i = 1, numArgs do
		local element = select(i, ...)
		additionalFilters[i] = element
	end
	return additionalFilters, numArgs
end

local function IsOptionalFilter(filter)
	local result
	for _, key in next, optionalKeys do
		if filter == key then
			result = true
			break
		end
	end
	return result
end

local function PackMultipleFilter(requiredTable, key, value)
	local filterTable = requiredTable[key]
	if type(filterTable) ~= "table" then
		filterTable = { requiredTable[key] }
		filterTable[NUM_FILTERS] = 1
		requiredTable[key] = filterTable
	end
	append(filterTable, value)
	filterTable[NUM_FILTERS] = filterTable[NUM_FILTERS] + 1
end

-- package required data to be shipped to AddCooldown()
-- this does no verification
-- '...' should be filterKey, filterValue pairs (so an even number of varargs)
-- 		see :EncodeModificationData() for more info
function addon:EncodeRequiredData(...)
	wipe(cdData)
	wipe(reqFilters)
	
	local filters, numArgs = PackAdditionalFilters(...)
	if numArgs % 2 == 0 then
		local atLeastOne
		for i = 1, numArgs, 2 do
			local key = filters[i]
			local value = filters[i+1]
			if IsOptionalFilter(key) then
				if reqFilters[key] ~= nil then
					-- multiple data for same filter (eg, chi torpedo & celerity)
					PackMultipleFilter(reqFilters, key, value)
				else
					reqFilters[key] = value
				end
				atLeastOne = true
			else
				cdData[key] = value
			end
		end
		if atLeastOne then -- we need not provide the table if there are no filters
			cdData[FILTER_REQUIRED] = reqFilters
		end
	else
		local msg = ":EncodeRequiredData(...) - received an odd number of varargs, expected an even number of 'filter' & 'filterValue' pairs"
		self:Debug(msg)
	end
	
	return cdData
end

-- package modification data to be shipped to AddCooldown()
-- this does no verification
-- '...' should be filterKey, filterValue pairs (so, only an even number should be passed)
--[[
	eg, :EncodeModificationData(2, '=', SPEC, 72, TALENT, 1, BUFF, 1234)
		specifies a modification with a value of 2 applied with the '=' modifier
		requiring spec==72, talent==1, and buff==1234
--]]
function addon:EncodeModificationData(value, op, filterKey, filterValue, ...)
	local modification = {
		[FILTER_MOD_VALUE] = value,
		[FILTER_MOD_OP] = op,
		[FILTER_REQUIRED] = {}, -- required filters to apply the modification
	}
	
	local required = modification[FILTER_REQUIRED]
	if filterKey and filterValue then
		required[filterKey] = filterValue		
		local additionalFilters = PackAdditionalFilters(...)
		if #additionalFilters % 2 == 0 then
			for i = 1, #additionalFilters, 2 do
				local key = additionalFilters[i]
				local value = additionalFilters[i+1]
				if required[key] ~= nil then
					PackMultipleFilter(required, key, value)
				else
					required[key] = value
				end
			end
		else
			local msg = ":EncodeModificationData(%s, %s, %s, %s, ...) - failed to encode additional filters (varargs is an odd number)"
			self:Debug(msg:format(tostring(value), tostring(op), tostring(filterKey), tostring(filterValue)))
		end
	else
		local msg = ":EncodeModificationData(%s, %s, filter, value, ...) - must specify at least one 'filter' & 'value' pair"
		self:Debug(msg:format(tostring(value), tostring(op)))
	end
	
	return modification
end

-- just a wrapper
-- requiredData, modData should be a table (only keys in filterKeys[FILTER_OPTIONAL] are used)
-- 		both are optional arguments
--[[
	ie, requiredData - the required filters (use :EncodeRequiredData())
    modData - should have the form:
		{
			filterKey = addon:EncodeModificationData(...),
			...
		}
--]]
function addon:AddCooldown(spellid, class, cd, charges, buffDuration, requiredData, modData)
	if requiredData == nil then
		requiredData = self:EncodeRequiredData(filterKeys.CD, cd, filterKeys.CHARGES, charges, filterKeys.BUFF_DURATION, buffDuration)
	else
		-- requiredData is expected to be correct
		if requiredData[filterKeys.CHARGES] == nil then
			requiredData[filterKeys.CHARGES] = charges
		end
		if requiredData[filterKeys.CD] == nil then
			requiredData[filterKeys.CD] = cd
		end
		if requiredData[filterKeys.BUFF_DURATION] == nil then
			requiredData[filterKeys.BUFF_DURATION] = buffDuration
		end
	end
	AddCooldown(spellid, class, requiredData, modData)
end

function addon:AddCooldownFromSpec(spellid, class, cd, charges, buffDuration, spec, modData)
	if spec ~= nil then
		local cdData = self:EncodeRequiredData(filterKeys.CD, cd, filterKeys.CHARGES, charges, filterKeys.BUFF_DURATION, buffDuration, optionalKeys.SPEC, spec)
		AddCooldown(spellid, class, cdData, modData)
	else
		debugUsage("AddCooldownFromSpec", "spec")
	end
end

function addon:AddCooldownFromTalent(spellid, class, cd, charges, buffDuration, talent, modData)
	if talent ~= nil then
		local cdData = self:EncodeRequiredData(filterKeys.CD, cd, filterKeys.CHARGES, charges, filterKeys.BUFF_DURATION, buffDuration, optionalKeys.TALENT, talent)
		AddCooldown(spellid, class, cdData, modData)
	else
		debugUsage("AddCooldownFromTalent", "talent")
	end
end

function addon:AddCooldownFromGlyph(spellid, class, cd, charges, buffDuration, glyph, modData)
	if glyph ~= nil then
		local cdData = self:EncodeRequiredData(filterKeys.CD, cd, filterKeys.CHARGES, charges, filterKeys.BUFF_DURATION, buffDuration, optionalKeys.GLYPH, glyph)
		AddCooldown(spellid, class, cdData, modData)
	else
		debugUsage("AddCooldownFromGlyph", "glyph")
	end
end

function addon:AddCooldownFromBuff(spellid, class, cd, charges, buffDuration, buff, modData)
	if buff ~= nil then
		local cdData = self:EncodeRequiredData(filterKeys.CD, cd, filterKeys.CHARGES, charges, filterKeys.BUFF_DURATION, buffDuration, optionalKeys.BUFF, buff)
		AddCooldown(spellid, class, cdData, modData)
	else
		debugUsage("AddCooldownFromBuff", "buff")
	end
end

function addon:AddCooldownFromPet(spellid, class, cd, charges, buffDuration, pet, modData)
	if pet ~= nil then
		local cdData = self:EncodeRequiredData(filterKeys.CD, cd, filterKeys.CHARGES, charges, filterKeys.BUFF_DURATION, buffDuration, optionalKeys.PET, pet)
		AddCooldown(spellid, class, cdData, modData)
	else
		debugUsage("AddCooldownFromPet", "pet")
	end
end

function addon:AddSymbiosisCooldown(spellid, class, cd, charges, buffDuration, spec, buff, modData)
	if spec ~= nil and buff ~= nil then
		local cdData = self:EncodeRequiredData(filterKeys.CD, cd, filterKeys.CHARGES, charges, filterKeys.BUFF_DURATION, buffDuration, optionalKeys.SPEC, spec, optionalKeys.BUFF, buff)
		AddCooldown(spellid, class, cdData, modData)
	else
		debugUsage("AddSymbiosisCooldown", "spec and/or buff")
	end
end
