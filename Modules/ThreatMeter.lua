-- ThreatMeter: Omen-style threat list for the current target. Shows the top
-- threat holders of the group (players + pets) as class/status-colored bars
-- with their threat percentage against the current tank. Only visible while
-- a hostile target is up and the player is in a group or has a pet out.
local _, ns = ...
local S = ns.S
local L = S.L
local TM = S:NewModule("ThreatMeter", "threatmeter")

local ipairs, pairs, sort, wipe = ipairs, pairs, table.sort, wipe
local floor, min, max = math.floor, math.min, math.max
local format = format
local UnitExists, UnitCanAttack, UnitName, UnitClass = UnitExists, UnitCanAttack, UnitName, UnitClass
local UnitDetailedThreatSituation = UnitDetailedThreatSituation
local IsInGroup, IsInRaid, GetNumGroupMembers = IsInGroup, IsInRaid, GetNumGroupMembers
local GetThreatStatusColor = GetThreatStatusColor
local IsSecret = S.IsSecret

local frame, rows, list = nil, {}, {}
local units = {}

local function CollectUnits()
	wipe(units)
	units[#units + 1] = "player"
	if TM.db.showPets and UnitExists("pet") then units[#units + 1] = "pet" end
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			local u = "raid" .. i
			if u ~= "player" and not UnitIsUnit(u, "player") then units[#units + 1] = u end
			if TM.db.showPets and UnitExists("raidpet" .. i) then units[#units + 1] = "raidpet" .. i end
		end
	elseif IsInGroup() then
		for i = 1, 4 do
			local u = "party" .. i
			if UnitExists(u) then units[#units + 1] = u end
			if TM.db.showPets and UnitExists("partypet" .. i) then units[#units + 1] = "partypet" .. i end
		end
	end
end

local function BuildFrame()
	if frame then return end
	frame = CreateFrame("Frame", "SentinelUIThreatMeter", UIParent)
	frame:SetSize(180, 80)
	S:SetTemplate(frame, "Transparent", "TOP")
	frame.title = S:FontString(frame, 11, "OUTLINE", S.media.unitFont, nil, "LEFT")
	frame.title:SetPoint("TOPLEFT", 6, -4)
	frame.title:SetText(L["Threat"])
	frame.body = CreateFrame("Frame", nil, frame)
	frame.body:SetPoint("TOPLEFT", 4, -18)
	frame.body:SetPoint("BOTTOMRIGHT", -4, 4)
	S:CreateMover(frame, "threatMeter", L["Threat Meter"], { "TOP", UIParent, "TOP", 220, -120 }, "threatmeter")
	frame:Hide()
end

local function GetRow(i)
	local r = rows[i]
	if not r then
		r = S:CreateStatusBar(frame.body, nil, "Default")
		r:SetMinMaxValues(0, 100)
		r.name = S:FontString(r, 10, "OUTLINE", S.media.unitFont, nil, "LEFT")
		r.name:SetPoint("LEFT", 4, 0)
		r.val = S:FontString(r, 10, "OUTLINE", S.media.numberFont, nil, "RIGHT")
		r.val:SetPoint("RIGHT", -4, 0)
		r.name:SetPoint("RIGHT", r.val, "LEFT", -6, 0)
		rows[i] = r
	end
	return r
end

local function Active()
	return UnitExists("target") and UnitCanAttack("player", "target")
		and (IsInGroup() or UnitExists("pet"))
end

function TM:UpdateList()
	if not frame then return end
	if not self.db.enable or not Active() or not UnitDetailedThreatSituation then
		frame:Hide()
		return
	end
	CollectUnits()
	wipe(list)
	for _, u in ipairs(units) do
		local isTanking, status, scaledPct, rawPct = UnitDetailedThreatSituation(u, "target")
		if rawPct and not IsSecret(rawPct) and rawPct > 0 then
			local name = UnitName(u)
			if name and not IsSecret(name) then
				if u:find("pet") then
					-- pet rows get "Petname (Owner)" so hunter/lock pets are
					-- distinguishable in the list
					local o = u:gsub("pet", "")
					local owner = (o ~= "" and UnitName(o)) or UnitName("player")
					if owner and not IsSecret(owner) then name = name .. " (" .. owner .. ")" end
				end
				list[#list + 1] = {
					name = name,
					pct = rawPct, scaled = scaledPct or rawPct,
					status = status or 0, tanking = isTanking,
					class = select(2, UnitClass(u)),
					isMe = UnitIsUnit(u, "player") or (u == "pet"),
				}
			end
		end
	end
	if #list == 0 then frame:Hide() return end
	sort(list, function(a, b) return a.pct > b.pct end)

	local tname = UnitName("target")
	frame.title:SetText(format("%s: %s", L["Threat"], (tname and not IsSecret(tname)) and tname or "?"))

	local maxB = min(self.db.maxBars or 5, #list)
	local h, gap = self.db.barHeight or 14, 2
	local w = self.db.width or 180
	for i = 1, maxB do
		local d, r = list[i], GetRow(i)
		local tag = d.tanking and "|cffff8040*|r " or ""
		r.name:SetText(tag .. (d.isMe and ("|cff7fff9f" .. d.name .. "|r") or d.name))
		r.val:SetFormattedText("%.0f%%", d.pct)
	end
	local need = 0
	for i = 1, maxB do
		local r = rows[i]
		need = max(need, r.name:GetStringWidth() + r.val:GetStringWidth() + 30)
	end
	if need > 0 then w = min(400, max(110, need)) end
	for i = 1, maxB do
		local d, r = list[i], GetRow(i)
		r:SetSize(w - 10, h)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", frame.body, "TOPLEFT", 0, -((i - 1) * (h + gap)))
		r:SetValue(min(100, d.scaled))
		local c
		if self.db.classColors and d.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[d.class] then
			c = RAID_CLASS_COLORS[d.class]
			r:SetStatusBarColor(c.r, c.g, c.b, d.isMe and 1 or 0.75)
		else
			local cr, cg, cb = GetThreatStatusColor(d.status)
			r:SetStatusBarColor(cr, cg, cb, d.isMe and 1 or 0.75)
		end
		r:Show()
	end
	for i = maxB + 1, #rows do rows[i]:Hide() end
	frame:SetWidth(w)
	frame:SetHeight(22 + maxB * (h + gap) + 6)
	frame:Show()
end

function TM:Initialize()
	if not UnitDetailedThreatSituation then return end
	self.db = S.db.profile.threatmeter
	BuildFrame()
	self:RegisterEvent("UNIT_THREAT_LIST_UPDATE", "UpdateList")
	self:RegisterEvent("PLAYER_TARGET_CHANGED", "UpdateList")
	self:RegisterEvent("GROUP_ROSTER_UPDATE", "UpdateList")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "UpdateList")
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "UpdateList")
end

function TM:Update()
	self.db = S.db.profile.threatmeter
	if frame then
		S:SetTemplate(frame, "Transparent", "TOP")
	end
	self:UpdateList()
end
