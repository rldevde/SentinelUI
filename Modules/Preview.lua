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

local pool, groupShown = {}, {}
local holder
local function Holder()
	if not holder then
		holder = CreateFrame("Frame", "SentinelUIPreviewHolder", UIParent)
		holder:SetAllPoints(UIParent)
		holder:SetFrameStrata("DIALOG")
	end
	return holder
end

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

-- mover frames always exist with real positions, even when the header
-- itself is hidden or its children were never laid out
local GROUPS = {
	{ mover = "party", n = 5, cols = 1, w = 190, h = 44 },
	{ mover = "raid", n = 10, cols = 5, w = 90, h = 36 },
	{ mover = "maintank", n = 2, cols = 1, w = 160, h = 44 },
}

local START = { party = 1, raid = 6, maintank = 16 }

function PV:Toggle(which)
	Holder()
	for _, g in ipairs(GROUPS) do
		if which ~= "all" and g.mover ~= which then
			if groupShown[g.mover] then
				for i = START[g.mover], START[g.mover] + g.n - 1 do
					if pool[i] then pool[i]:Show() end
				end
			end
		else
			groupShown[g.mover] = not groupShown[g.mover]
			local anchor = S.movers and S.movers[g.mover]
			if groupShown[g.mover] and anchor then
				for i = 1, g.n do
					local d = Dummy(UIParent, START[g.mover] + i - 1)
					local col, row = (i - 1) % g.cols, math.floor((i - 1) / g.cols)
					d:ClearAllPoints()
					d:SetPoint("TOPLEFT", anchor, "TOPLEFT", col * (g.w + 3), -(row * (g.h + 3)))
					Fill(d, START[g.mover] + i - 1, g.w, g.h)
				end
			else
				for i = START[g.mover], START[g.mover] + g.n - 1 do
					if pool[i] then pool[i]:Hide() end
				end
			end
		end
	end
	S:Print(L["preview: /suidummy party|raid|maintank|all"] or "preview: /suidummy party|raid|maintank|all")
end

function PV:Initialize()
	SLASH_SUIDUMMY1 = "/suidummy"
	SlashCmdList.SUIDUMMY = function(msg) S:SafeCall("Preview:Toggle", PV.Toggle, PV, (msg or ""):gsub("^%s*(.-)%s*$", "%1") ~= "" and msg or "all") end
end
