local _, ns = ...
local S = ns.S
local L = S.L
local DB = S:NewModule("DataBars")

local format, floor, max, min = format, math.floor, math.max, math.min

DB.bars = {}

local function MaxLevel()
	return (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or (GetMaxPlayerLevel and GetMaxPlayerLevel()) or MAX_PLAYER_LEVEL or 60
end

local function FormatText(mode, cur, mx, extra)
	if mode == "NONE" then return "" end
	local pct = mx > 0 and cur / mx * 100 or 0
	if mode == "PERCENT" then return format("%.1f%%", pct) .. (extra or "")
	elseif mode == "CURMAX" then return S:Abbrev(cur) .. " / " .. S:Abbrev(mx) .. (extra or "")
	elseif mode == "CURPERC" then return format("%s - %.1f%%", S:Abbrev(cur), pct) .. (extra or "")
	elseif mode == "REMAINING" then return S:Abbrev(mx - cur) .. (extra or "")
	elseif mode == "CURVALUE" then return S:Abbrev(cur) .. (extra or "") end
	return format("%.1f%%", pct)
end

function DB:CreateBar(key, title, pos)
	local db = self.db[key]
	local bar = S:CreateStatusBar(UIParent, "SentinelUI" .. key:gsub("^%l", string.upper) .. "Bar", "Transparent")
	bar.key = key
	bar:SetSize(db.width, db.height)
	bar:SetFrameStrata("LOW")
	bar.text = S:FontString(bar, 11, "OUTLINE", S.media.numberFont)
	bar.text:SetPoint("CENTER")
	bar:EnableMouse(true)
	bar:SetScript("OnEnter", function(b)
		if b.db.mouseover then b:SetAlpha(1) end
		if DB["Tooltip_" .. key] then S:SafeCall("DataBars:Tooltip", DB["Tooltip_" .. key], DB, b) end
	end)
	bar:SetScript("OnLeave", function(b) if b.db.mouseover then b:SetAlpha(0) end GameTooltip:Hide() end)
	bar.db = db
	S:CreateMover(bar, key .. "Bar", title, pos, "databars")
	self.bars[key] = bar
	return bar
end

function DB:ApplyBarSettings(bar)
	local db = self.db[bar.key]
	bar.db = db
	bar:SetSize(db.width, db.height)
	bar:SetOrientation(db.orientation or "HORIZONTAL")
	bar:SetAlpha(db.mouseover and 0 or 1)
	local size = (db.fontSize and db.fontSize > 0) and db.fontSize or max(8, min(12, db.height + 1))
	S:SetFont(bar.text, db.font and S:Fetch("font", db.font) or S.media.numberFont, size, db.fontOutline or "OUTLINE")
	if db.textColor then bar.text:SetTextColor(db.textColor.r, db.textColor.g, db.textColor.b) end
	bar.text:SetShown(db.height >= 8 and db.text ~= "NONE")
end

-- Experience
function DB:UpdateExperience()
	local bar = self.bars.experience
	if not bar then return end
	local db = self.db.experience
	local atMax = UnitLevel("player") >= MaxLevel() or (IsXPUserDisabled and IsXPUserDisabled())
	if not db.enable or (db.hideAtMaxLevel and atMax) then bar:Hide() S:DisableMover("experienceBar", true) return end
	S:DisableMover("experienceBar", false)
	bar:Show()
	local cur, mx = UnitXP("player"), max(1, UnitXPMax("player"))
	local rested = GetXPExhaustion() or 0
	bar:SetMinMaxValues(0, mx)
	bar:SetValue(cur)
	bar:SetStatusBarColor(db.color.r, db.color.g, db.color.b)
	if not bar.rested then
		bar.rested = CreateFrame("StatusBar", nil, bar)
		bar.rested:SetAllPoints()
		bar.rested:SetStatusBarTexture(S.media.statusbar)
		bar.rested:SetFrameLevel(bar:GetFrameLevel())
		bar:SetFrameLevel(bar.rested:GetFrameLevel() + 1)
		bar.bg:SetParent(bar.rested)
	end
	bar.rested:SetMinMaxValues(0, mx)
	bar.rested:SetValue(min(mx, cur + rested))
	bar.rested:SetStatusBarColor(db.rested.r, db.rested.g, db.rested.b, db.rested.a)
	bar.rested:SetOrientation(db.orientation or "HORIZONTAL")
	bar.text:SetText(FormatText(db.text, cur, mx, rested > 0 and format(" |cffb080ff(R %.0f%%)|r", rested / mx * 100) or nil))
end

function DB:Tooltip_experience(bar)
	local cur, mx = UnitXP("player"), max(1, UnitXPMax("player"))
	local rested = GetXPExhaustion() or 0
	GameTooltip:SetOwner(bar, "ANCHOR_TOP", 0, 4)
	GameTooltip:AddLine(L["Experience"], S.accent.r, S.accent.g, S.accent.b)
	GameTooltip:AddDoubleLine(LEVEL, UnitLevel("player"), 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine(L["XP"], format("%s / %s (%.1f%%)", BreakUpLargeNumbers(cur), BreakUpLargeNumbers(mx), cur / mx * 100), 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine(L["Remaining"], format("%s (%.1f%%)", BreakUpLargeNumbers(mx - cur), (mx - cur) / mx * 100), 1, 1, 1, 1, 1, 1)
	if rested > 0 then GameTooltip:AddDoubleLine(L["Rested"], format("%s (%.1f%%)", BreakUpLargeNumbers(rested), rested / mx * 100), 1, 1, 1, 0.7, 0.5, 1) end
	GameTooltip:Show()
end

-- Reputation
local function GetWatched()
	if C_Reputation and C_Reputation.GetWatchedFactionData then
		local data = C_Reputation.GetWatchedFactionData()
		if not data or not data.name then return end
		local name, standing, minV, maxV, value, factionID = data.name, data.reaction, data.currentReactionThreshold, data.nextReactionThreshold, data.currentStanding, data.factionID
		local label = _G["FACTION_STANDING_LABEL" .. standing]
		if C_GossipInfo and C_GossipInfo.GetFriendshipReputation and factionID then
			local friend = C_GossipInfo.GetFriendshipReputation(factionID)
			if friend and friend.friendshipFactionID and friend.friendshipFactionID > 0 then
				label = friend.reaction
				minV, maxV, value = friend.reactionThreshold or 0, friend.nextThreshold or friend.standing or 1, friend.standing or 0
			end
		end
		if C_Reputation.IsMajorFaction and factionID and C_Reputation.IsMajorFaction(factionID) and C_MajorFactions then
			local info = C_MajorFactions.GetMajorFactionData(factionID)
			if info then
				minV, maxV, value = 0, info.renownLevelThreshold, info.renownReputationEarned or 0
				label = (RENOWN_LEVEL_LABEL or "Renown %d"):format(info.renownLevel)
				standing = 10
			end
		end
		if C_Reputation.IsFactionParagon and factionID and C_Reputation.IsFactionParagon(factionID) then
			local cur, threshold = C_Reputation.GetFactionParagonInfo(factionID)
			if cur and threshold then minV, maxV, value = 0, threshold, cur % threshold label = L["Paragon"] standing = 9 end
		end
		return name, standing, minV, maxV, value, label
	end
	local name, standing, minV, maxV, value = GetWatchedFactionInfo()
	if not name then return end
	return name, standing, minV, maxV, value, _G["FACTION_STANDING_LABEL" .. standing]
end

function DB:UpdateReputation()
	local bar = self.bars.reputation
	if not bar then return end
	local db = self.db.reputation
	local name, standing, minV, maxV, value, label = GetWatched()
	if not db.enable or not name then bar:Hide() S:DisableMover("reputationBar", not db.enable) return end
	S:DisableMover("reputationBar", false)
	bar:Show()
	local cur, mx = value - minV, max(1, maxV - minV)
	bar:SetMinMaxValues(0, mx)
	bar:SetValue(cur)
	local c = (standing == 9 and { r = 0, g = 0.5, b = 0.9 }) or (standing == 10 and { r = 0, g = 0.75, b = 0.95 }) or FACTION_BAR_COLORS[standing] or { r = 0, g = 0.6, b = 0.1 }
	bar:SetStatusBarColor(c.r, c.g, c.b)
	bar.text:SetText(name .. ": " .. FormatText(db.text, cur, mx) .. " [" .. (label or "") .. "]")
end

function DB:Tooltip_reputation(bar)
	local name, standing, minV, maxV, value, label = GetWatched()
	if not name then return end
	GameTooltip:SetOwner(bar, "ANCHOR_TOP", 0, 4)
	GameTooltip:AddLine(name, S.accent.r, S.accent.g, S.accent.b)
	GameTooltip:AddDoubleLine(L["Standing"], label or "", 1, 1, 1, 1, 1, 1)
	GameTooltip:AddDoubleLine(REPUTATION, format("%s / %s", BreakUpLargeNumbers(value - minV), BreakUpLargeNumbers(maxV - minV)), 1, 1, 1, 1, 1, 1)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(L["Click: open reputation"], 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

-- Honor (retail)
function DB:UpdateHonor()
	local bar = self.bars.honor
	if not bar then return end
	local db = self.db.honor
	if not db.enable or not UnitHonor then bar:Hide() S:DisableMover("honorBar", true) return end
	S:DisableMover("honorBar", false)
	local cur, mx = UnitHonor("player") or 0, max(1, UnitHonorMax("player") or 1)
	bar:SetMinMaxValues(0, mx)
	bar:SetValue(cur)
	local hc = db.color or { r = 0.94, g = 0.45, b = 0.25 }
	bar:SetStatusBarColor(hc.r, hc.g, hc.b)
	bar.text:SetText(FormatText(db.text, cur, mx, " (" .. (UnitHonorLevel and UnitHonorLevel("player") or "") .. ")"))
	bar:Show()
end

-- Threat
function DB:UpdateThreat()
	local bar = self.bars.threat
	if not bar then return end
	local db = self.db.threat
	if not db.enable or not UnitExists("target") or not UnitCanAttack("player", "target") or not (IsInGroup() or UnitExists("pet")) then bar:Hide() return end
	local isTanking, status, pct = UnitDetailedThreatSituation("player", "target")
	if not pct or S.IsSecret(pct) then bar:Hide() return end
	bar:SetMinMaxValues(0, 100)
	bar:SetValue(pct)
	local r, g, b = GetThreatStatusColor(status or 0)
	bar:SetStatusBarColor(r, g, b)
	bar.text:SetText(format("%s: %.0f%%", L["Threat"], pct))
	bar:Show()
end

function DB:Update()
	for _, bar in pairs(self.bars) do self:ApplyBarSettings(bar) end
	self:UpdateExperience()
	self:UpdateReputation()
	self:UpdateHonor()
	self:UpdateThreat()
end

function DB:Initialize()
	self:CreateBar("experience", L["Experience Bar"], { "BOTTOMLEFT", "SentinelUIMover_leftChat", "TOPLEFT", 0, 4 })
	self:CreateBar("reputation", L["Reputation Bar"], { "BOTTOMRIGHT", "SentinelUIMover_rightChat", "TOPRIGHT", 0, 4 })
	if UnitHonor then self:CreateBar("honor", L["Honor Bar"], { "BOTTOMRIGHT", "SentinelUIMover_reputationBar", "TOPRIGHT", 0, 4 }) end
	self:CreateBar("threat", L["Threat Bar"], { "TOP", "UIParent", "TOP", 0, -8 })
	self.bars.reputation:SetScript("OnMouseUp", function() ToggleCharacter("ReputationFrame") end)
	self:Update()

	for _, e in ipairs({ "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "DISABLE_XP_GAIN", "ENABLE_XP_GAIN" }) do self:RegisterEvent(e, "UpdateExperience") end
	for _, e in ipairs({ "UPDATE_FACTION", "COMBAT_TEXT_UPDATE", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED" }) do self:RegisterEvent(e, "UpdateReputation") end
	if UnitHonor then
		self:RegisterEvent("HONOR_XP_UPDATE", "UpdateHonor")
		self:RegisterEvent("HONOR_LEVEL_UPDATE", "UpdateHonor")
	end
	for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "UNIT_THREAT_LIST_UPDATE", "GROUP_ROSTER_UPDATE", "UNIT_PET", "PLAYER_REGEN_ENABLED" }) do self:RegisterEvent(e, "UpdateThreat") end
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "Update")
end
