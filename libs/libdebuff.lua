-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

--[[ libdebuff ]]--
-- A pfUI library that detects and saves all ongoing debuffs of players, NPCs and enemies.
-- The functions UnitDebuff is exposed to the modules which allows to query debuffs like you
-- would on later expansions.
--
--  libdebuff:UnitDebuff(unit, id)
--    Returns debuff informations on the given effect of the specified unit.
--    name, rank, texture, stacks, dtype, duration, timeleft

-- return instantly if we're not on a vanilla client
if pfUI.client > 11200 then
	return
end

-- return instantly when another libdebuff is already active
if pfUI.api.libdebuff then
	return
end

-- fix a typo (missing $) in ruRU capture index
if GetLocale() == "ruRU" then
	SPELLREFLECTSELFOTHER = gsub(SPELLREFLECTSELFOTHER, "%%2s", "%%2%$s")
end

local libdebuff = CreateFrame("Frame", "pfdebuffsScanner", UIParent)
local scanner = libtipscan:GetScanner("libdebuff")
local _, class = UnitClass("player")

libdebuff.objects = {}

libdebuff:RegisterEvent("UNIT_CASTEVENT")
libdebuff:RegisterEvent("PLAYER_REGEN_ENABLED")

function libdebuff:GetDuration(effect, rank)
	if L["debuffs"][effect] then
		local rank = rank and tonumber((string.gsub(rank, RANK, ""))) or 0
		rank = L["debuffs"][effect][rank] and rank or libdebuff:GetMaxRank(effect)
		local duration = L["debuffs"][effect][rank]

		if effect == L["dyndebuffs"]["Rupture"] then
			-- Rupture: +2 sec per combo point
			duration = duration + GetComboPoints() * 2
		elseif effect == L["dyndebuffs"]["Kidney Shot"] then
			-- Kidney Shot: +1 sec per combo point
			duration = duration + GetComboPoints() * 1
		elseif effect == L["dyndebuffs"]["Demoralizing Shout"] then
			-- Booming Voice: 10% per talent
			local _, _, _, _, count = GetTalentInfo(2, 1)
			if count and count > 0 then
				duration = duration + (duration / 100 * (count * 10))
			end
		elseif effect == L["dyndebuffs"]["Shadow Word: Pain"] then
			-- Improved Shadow Word: Pain: +3s per talent
			local _, _, _, _, count = GetTalentInfo(3, 4)
			if count and count > 0 then
				duration = duration + count * 3
			end
		elseif effect == L["dyndebuffs"]["Frostbolt"] then
			-- Permafrost: +1s per talent
			local _, _, _, _, count = GetTalentInfo(3, 7)
			if count and count > 0 then
				duration = duration + count
			end
		elseif effect == L["dyndebuffs"]["Gouge"] then
			-- Improved Gouge: +.5s per talent
			local _, _, _, _, count = GetTalentInfo(2, 1)
			if count and count > 0 then
				duration = duration + (count * .5)
			end
		end
		return duration
	else
		return 0
	end
end

function libdebuff:GetMaxRank(effect)
	local max = 0
	for id in pairs(L["debuffs"][effect]) do
		if id > max then
			max = id
		end
	end
	return max
end

function libdebuff:AddEffect(guid, effect, duration)
	if not guid or not effect or guid == "0x0000000000000000" then
		return
	end

	guid = string.lower(guid)

	effect = string.gsub(effect, " %(%d+%)", "") -- remove stack indication from effect name in order to display correct expiration time for things like Fire Vulnerability
	if not libdebuff.objects[guid] then
		libdebuff.objects[guid] = {}
	end
	if not libdebuff.objects[guid][effect] then
		libdebuff.objects[guid][effect] = {}
	end

	libdebuff.objects[guid][effect].effect = effect
	libdebuff.objects[guid][effect].start_old = libdebuff.objects[guid][effect].start
	libdebuff.objects[guid][effect].start = GetTime()
	libdebuff.objects[guid][effect].duration = duration or libdebuff:GetDuration(effect)

	if pfUI.uf and pfUI.uf.target then
		pfUI.uf:RefreshUnit(pfUI.uf.target, "aura")
	end
end

-- Added "UNIT_CASTEVENT" event that tracks units cast starts, finishes, interrupts, channels, and swings (differentiates mainhand & offhand) arg1: casterGUID. arg2: targetGUID. arg3: event type ("START", "CAST", "FAIL", "CHANNEL", "MAINHAND", "OFFHAND"). arg4: spell id. arg5: cast duration.
libdebuff:SetScript("OnEvent", function()
	if event == "UNIT_CASTEVENT" then
		local casterGUID, targetGUID, eventType, spellID, castDuration = arg1, arg2, arg3, arg4, arg5
		if eventType == "CAST" and targetGUID and string.len(targetGUID) > 0 then
			local effect, rank, _ = SpellInfo(spellID, BOOKTYPE_SPELL)
			if effect then
				local duration = libdebuff:GetDuration(effect, rank)
				libdebuff:AddEffect(targetGUID, effect, duration)
			end
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		libdebuff.objects = {} -- clear all debuffs
	end
end)

function libdebuff:UnitDebuff(unitstr, id)
	if unitstr == "0x0000000000000000" then
		return
	end

	local texture, stacks, dtype = UnitDebuff(unitstr, id) -- this corrupts guid

	local duration, timeleft = nil, -1
	local rank = nil -- no backport
	local effect

	if texture then
		scanner:SetUnitDebuff(unitstr, id)
		effect = scanner:Line(1)

		if effect then
			local guid = string.lower(unitstr)
			if string.sub(unitstr, 1, 2) ~= "0x" then
				_, guid = UnitExists(unitstr) -- get guid
				guid = string.lower(guid)
			end

			if libdebuff.objects[guid] and libdebuff.objects[guid][effect] then
				duration = libdebuff.objects[guid][effect].duration
				timeleft = duration + libdebuff.objects[guid][effect].start - GetTime()
				if timeleft < 0 then
					timeleft = nil
				end
			else
				-- add debuff timer (could have been from aoe spell that didn't have a target)
				duration = libdebuff:GetDuration(effect)
				timeleft = duration
				libdebuff:AddEffect(guid, effect, duration)
			end
		end
	end

	return effect, rank, texture, stacks, dtype, duration, timeleft
end

-- add libdebuff to pfUI API
pfUI.api.libdebuff = libdebuff
