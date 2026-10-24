-- Preview: /suidummy shows example unit frames at the real positions so you
-- can move and style things while solo. Party, raid, maintank and boss
-- dummies anchor to the real headers; single frames anchor to their movers.
local _, ns = ...
local S = ns.S
local L = S.L
local PV = S:NewModule("Preview", "preview")

local CreateFrame = CreateFrame
local CLASSES = { "WARRIOR", "PRIEST", "MAGE", "ROGUE", "DRUID", "HUNTER", "PALADIN", "SHAMAN", "WARLOCK" }
local NAMES = { "Thorin", "Mira", "Kael", "Sylva", "Grom", "Nia", "Durn", "Ela", "Vex", "Rulf",
	"Anja", "Bor", "Ciri", "Dain", "Effi", "Falrik", "Gwen", "Hald", "Iris", "Jorin" }

local pool, shown = {}, false

local function Dummy(parent, i)
	local f = pool[i]
	if not f then
		f = CreateFrame("Frame", "SentinelUIPreview" .. i, parent or UIParent)
		S:SetTemplate(f, "Default")
		f.health = f:CreateTexture(nil, "ARTWORK")
		f.health:SetPoint("TOPLEFT", 2, -2)
		f.health:SetPoint("BOTTOMRIGHT", -2, 6)
		f.health:SetTexture(S.media.statusbar or "Interface/Buttons/WHITE8x8")
		f.power = f:CreateTexture(nil, "ARTWORK")
		f.power:SetPoint("BOTTOMLEFT", 2, 2)
		f.power:SetPoint("BOTTOMRIGHT", -2, 2)
		f.power:SetHeight(4)
		f.power:SetTexture(S.media.statusbar or "Interface/Buttons/WHITE8x8")
		f.name = S:FontString(f, 10, "OUTLINE", S.media.unitFont)
		f.name:SetPoint("CENTER", f.health, "CENTER")
		f.pct = S:FontString(f, 10, "OUTLINE", S.media.numberFont)
		f.pct:SetPoint("RIGHT", f.health, "RIGHT", -3, 0)
		pool[i] = f
	end
	return f
end

local function Fill(f, i, w, h)
	f:SetSize(w, h)
	local cls = CLASSES[(i % #CLASSES) + 1]
	local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
	local r, g, b = c and c.r or 0.4, c and c.g or 0.4, c and c.b or 0.4
	local hp = 0.4 + (i % 6) * 0.11
	f.health:SetVertexColor(r, g, b)
	f.health:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 6)
	f.health:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -(h - 6) * (1 - hp) - 2)
	f.power:SetVertexColor(0.2, 0.4, 0.9)
	f.name:SetText(NAMES[(i % #NAMES) + 1] .. "-" .. cls:sub(1, 4))
	f.pct:SetText((math.floor(hp * 100)) .. "%")
	f:Show()
end

local function AnchorTo(f, anchor, i, cols, w, h, gap)
	-- lay dummies in a grid starting at the anchor frame's top-left
	local col = (i - 1) % cols
	local row = math.floor((i - 1) / cols)
	f:ClearAllPoints()
	if anchor then
		f:SetPoint("TOPLEFT", anchor, "TOPLEFT", col * (w + gap), -(row * (h + gap)))
	else
		f:SetPoint("CENTER", UIParent, "CENTER", col * (w + gap), 100 - row * (h + gap))
	end
end

local GROUPS = {
	{ header = "SentinelUI_PartyHeader", n = 5, cols = 1, w = 190, h = 44 },
	{ header = "SentinelUI_RaidHeader", n = 10, cols = 5, w = 90, h = 36 },
	{ header = "SentinelUI_Raid40Header", n = 0, cols = 8, w = 70, h = 30 },
	{ header = "SentinelUI_MaintankHeader", n = 2, cols = 1, w = 160, h = 44 },
	{ header = "SentinelUI_BossHolder", n = 0, cols = 1, w = 150, h = 40 },
}

function PV:Toggle()
	self.db = self.db or S.db.profile.preview
	shown = not shown
	local idx = 1
	for _, g in ipairs(GROUPS) do
		local anchor = _G[g.header]
		if anchor and g.n > 0 then
			for i = 1, g.n do
				local d = Dummy(UIParent, idx)
				AnchorTo(d, anchor, i, g.cols, g.w, g.h, 3)
				Fill(d, idx, g.w, g.h)
				idx = idx + 1
			end
		end
	end
	for i = idx, #pool do pool[i]:Hide() end
	S:Print(shown and (L["Dummy preview on - /suidummy to hide"] or "Dummy preview on")
		or (L["Dummy preview off"] or "Dummy preview off"))
end

function PV:Initialize()
	SLASH_SUIDUMMY1 = "/suidummy"
	SlashCmdList.SUIDUMMY = function() PV:Toggle() end
end
