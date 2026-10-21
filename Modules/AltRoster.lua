-- AltRoster: account-wide character overview. On login each character saves
-- level, class, gold and guild; /suiroster (or the minimap button) lists all
-- of them with class-colored names.
local _, ns = ...
local S = ns.S
local L = S.L
local AR = S:NewModule("AltRoster", "altroster")

local CreateFrame = CreateFrame
local MAX_ROWS = 14

local function Roster()
	S.db.global.altroster = S.db.global.altroster or {}
	return S.db.global.altroster
end

function AR:Save()
	local r = Roster()
	r[S.myName] = {
		class = S.myClass, level = UnitLevel("player"),
		money = GetMoney and GetMoney() or 0,
		guild = GetGuildInfo and select(1, GetGuildInfo("player")) or nil,
		faction = UnitFactionGroup and UnitFactionGroup("player") or nil,
		seen = time(),
	}
end

function AR:BuildFrame()
	if self.frame then return end
	local f = CreateFrame("Frame", "SentinelUIAltRoster", UIParent)
	tinsert(UISpecialFrames, "SentinelUIAltRoster")
	f:SetSize(300, 40 + MAX_ROWS * 18)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	S:CreateBackdrop(f, "Default")
	f.title = S:FontString(f, 13, "OUTLINE", S.media.unitFont)
	f.title:SetPoint("TOP", 0, -8)
	f.title:SetText(L["Characters"])
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)
	if S.SkinCloseButton then S:SkinCloseButton(close) end
	f.rows = {}
	for i = 1, MAX_ROWS do
		local t = S:FontString(f, 10, nil, S.media.unitFont)
		t:SetPoint("TOPLEFT", 14, -30 - (i - 1) * 18)
		t:SetJustifyH("LEFT")
		f.rows[i] = t
	end
	f:Hide()
	self.frame = f
end

function AR:Fill()
	local list = {}
	for name, d in pairs(Roster()) do
		list[#list + 1] = { name = name, d = d }
	end
	table.sort(list, function(a, b) return (a.d.level or 0) > (b.d.level or 0) end)
	for i, t in ipairs(self.frame.rows) do
		local e = list[i]
		if e then
			local d = e.d
			local c = d.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[d.class]
			local nm = c and format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, e.name) or e.name
			t:SetFormattedText("%s  |cffffcc00%d|r  %s  |cff888888%s|r",
				nm, d.level or 0, S:FormatMoney(d.money or 0), d.guild or "")
		else
			t:SetText("")
		end
	end
end

function AR:Toggle()
	self:BuildFrame()
	self:Fill()
	self.frame:SetShown(not self.frame:IsShown())
end

function AR:Initialize()
	self.db = S.db.profile.altroster
	self:Save()
	self:RegisterEvent("PLAYER_MONEY", function() AR:Save() end)
	self:RegisterEvent("PLAYER_LEVEL_UP", function() AR:Save() end)
	S:RegisterChatCommand("suiroster", function() AR:Toggle() end)
	S.private.altroster = S.private.altroster or {}
	S.private.altroster.minimap = S.private.altroster.minimap or {}
	self.minimapBtn = S:CreateMinimapButton({
		name = "altroster", glyph = "AR", store = S.private.altroster.minimap,
		onLeft = function() AR:Toggle() end,
		tooltip = function(b)
			GameTooltip:AddLine("SentinelUI " .. L["Characters"], S.accent.r, S.accent.g, S.accent.b)
			for name, d in pairs(Roster()) do
				local c = d.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[d.class]
				GameTooltip:AddDoubleLine(name, (d.level or 0) .. " " .. S:FormatMoney(d.money or 0), c and c.r or 1, c and c.g or 1, c and c.b or 1, 0.8, 0.8, 0.8)
			end
		end,
	})
end

function AR:Update()
	self.db = S.db.profile.altroster
end
