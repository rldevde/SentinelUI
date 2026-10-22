-- SessionStats: per-session counters exposed through the "Session" data
-- text. Tracks kills (party kill credit), gold earned/spent, deaths, XP
-- gained and session time. Tooltip lists the details; click resets.
local _, ns = ...
local S = ns.S
local L = S.L
local SS = S:NewModule("SessionStats", "sessionstats")

local floor, format = math.floor, format
local GetMoney, GetTime = GetMoney, GetTime

local st = { t0 = 0, kills = 0, deaths = 0, xp = 0, gold0 = 0, money0 = 0 }

local function MoneyDelta()
	local cur = GetMoney()
	return (cur or 0) - (st.money0 or 0)
end

local function Dur()
	local d = floor(GetTime() - st.t0)
	return format("%d:%02d", floor(d / 3600), floor(d / 60) % 60)
end

function SS:Initialize()
	self.db = S.db.profile.sessionstats
	st.t0, st.money0 = GetTime(), GetMoney()
	local DT = S:GetModule("DataTexts")
	if not (DT and DT.Register) then return end
	DT:Register("Session", {
		name = "Session",
		update = function(slot)
			local gold = MoneyDelta()
			slot.text:SetFormattedText("%s  |cff888888%s|r  |cffffd700%s|r  |cffff4040%d|r",
				Dur(), format(L["%d kills"], st.kills),
				gold >= 0 and ("+" .. (S.FormatMoney and S.FormatMoney(gold) or gold)) or (S.FormatMoney and S.FormatMoney(gold) or gold),
				st.deaths)
		end,
		interval = 30,
		enter = function(slot)
			GameTooltip:SetOwner(slot, "ANCHOR_TOP")
			GameTooltip:AddLine(L["Session"])
			GameTooltip:AddDoubleLine(L["Time"], Dur(), 1, 1, 1, 1, 1, 1)
			GameTooltip:AddDoubleLine(L["Kills"], st.kills, 1, 1, 1, 1, 1, 1)
			GameTooltip:AddDoubleLine(L["Deaths"], st.deaths, 1, 1, 1, 1, 1, 1)
			GameTooltip:AddDoubleLine(L["Gold earned"], S.FormatMoney and S.FormatMoney(MoneyDelta()) or MoneyDelta(), 1, 1, 1, 1, 1, 1)
			local hours = (GetTime() - st.t0) / 3600
			if hours > 0.02 then
				GameTooltip:AddDoubleLine("G/h", S.FormatMoney and S.FormatMoney(MoneyDelta() / hours) or 0, 1, 1, 1, 1, 1, 1)
			end
			GameTooltip:AddDoubleLine(L["XP gained"], st.xp, 1, 1, 1, 1, 1, 1)
			GameTooltip:AddLine(L["Click: reset session"], 0.7, 0.7, 0.7)
			GameTooltip:Show()
		end,
		click = function()
			st.t0, st.money0 = GetTime(), GetMoney()
			st.kills, st.deaths, st.xp = 0, 0, 0
		end,
	})

	-- XP gain amount only exists inside the localized combat text
	-- ("You gain 320 experience." / "Ihr erhaltet 320 Erfahrung.")
	self:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN", function(_, _, msg)
		if type(msg) ~= "string" or (S.IsSecret and S.IsSecret(msg)) then return end
		local n = tonumber(msg:match("(%d[%d%.]*)"))
		if n then st.xp = st.xp + n end
	end)
	self:RegisterEvent("PARTY_KILL", function(_, _, unit)
		-- PARTY_KILL fires for every group member; count kill-blow credit only
		if not unit then st.kills = st.kills + 1 return end
		if UnitIsUnit and (UnitIsUnit(unit, "player") or unit == "player") then st.kills = st.kills + 1 end
	end)
	self:RegisterEvent("PLAYER_DEAD", function() st.deaths = st.deaths + 1 end)
end

function SS:Update()
	self.db = S.db.profile.sessionstats
end
