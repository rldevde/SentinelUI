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

local LEVELS = { 21, 24, 27, 31, 33, 40 }

local function Fill(f, i, w, h)
	f:SetSize(w, h)
	local cls = CLASSES[(i % #CLASSES) + 1]
	local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
	local r, g, b = c and c.r or 0.4, c and c.g or 0.4, c and c.b or 0.4
	local hp = 0.4 + (i % 6) * 0.11
	local lvl = LEVELS[(i % #LEVELS) + 1]
	local name = NAMES[(i % #NAMES) + 1]
	-- real UF look: name left in white, hp% right, level on power bar
	f.health:SetVertexColor(r, g, b)
	f.health:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 6)
	f.health:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -(h - 6) * (1 - hp) - 2)
	f.power:SetVertexColor(0.15, 0.35, 0.85)
	f.name:ClearAllPoints()
	f.name:SetPoint("LEFT", f, "LEFT", 5, 0)
	f.name:SetText(name)
	f.pct:ClearAllPoints()
	f.pct:SetPoint("RIGHT", f, "RIGHT", -4, 0)
	f.pct:SetText((math.floor(hp * 100)) .. "%")
	f.lvl:SetText("|cffcc9999" .. lvl .. "|r")
	-- interactive like a real frame: tooltip + click feedback
	f:EnableMouse(true)
	f:SetScript("OnEnter", function()
		GameTooltip:SetOwner(f, "ANCHOR_TOP")
		GameTooltip:AddLine(name, r, g, b)
		GameTooltip:AddLine("Level " .. lvl .. "  " .. cls, 0.6, 0.6, 0.6)
		GameTooltip:AddLine("HP " .. math.floor(hp * 100) .. "%", 0.4, 0.9, 0.4)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f:SetScript("OnMouseDown", function()
		S:SetTemplate(f, "Transparent") -- border flash on click
	end)
	f:SetScript("OnMouseUp", function()
		S:SetTemplate(f, "Default")
	end)
	f:Show()
end

-- mover frames always exist with real positions, even when the header
-- itself is hidden or its children were never laid out
local GROUPS = {
	{ mover = "party", header = "SentinelUI_PartyHeader", n = 5, cols = 1, w = 190, h = 44 },
	{ mover = "raid", key = "raid", header = "SentinelUI_RaidHeader", n = 10, cols = 5, w = 90, h = 36 },
	{ mover = "raid", key = "raid25", header = "SentinelUI_RaidHeader", n = 25, cols = 5, w = 80, h = 32 },
	{ mover = "raid40", header = "SentinelUI_Raid40Header", n = 40, cols = 8, w = 70, h = 28 },
	{ mover = "maintank", header = "SentinelUI_MaintankHeader", n = 2, cols = 1, w = 160, h = 44 },
}

local START = { party = 1, raid = 6, raid25 = 16, raid40 = 41, maintank = 81 }

function PV:Toggle(which)
	Holder()
	for gi, g in ipairs(GROUPS) do
		local key = g.key or g.mover
		if which ~= "all" and key ~= which then
			if groupShown[key] then
				for i = START[key], START[key] + g.n - 1 do
					if pool[i] then pool[i]:Show() end
				end
			end
		else
			groupShown[key] = not groupShown[key]
			local anchor = _G["SentinelUIMover_" .. g.mover] or (S.movers and S.movers[g.mover]) or _G[g.header]
			if groupShown[key] then
				S:Print(key .. ": " .. (anchor and ("@" .. (anchor:GetName() or "?")) or "NO MOVER"))
			end
			if groupShown[key] then
				for i = 1, g.n do
					local d = Dummy(UIParent, START[key] + i - 1)
					local col, row = (i - 1) % g.cols, math.floor((i - 1) / g.cols)
					d:ClearAllPoints()
					if anchor then
						d:SetPoint("TOPLEFT", anchor, "TOPLEFT", col * (g.w + 3), -(row * (g.h + 3)))
					else
						-- no mover found: fixed visible spot near center so the
						-- dummies are never silently offscreen
						d:SetPoint("CENTER", UIParent, "CENTER", (col - g.cols / 2) * (g.w + 3), 200 - row * (g.h + 3))
					end
					Fill(d, START[key] + i - 1, g.w, g.h)
				end
			else
				for i = START[key], START[key] + g.n - 1 do
					if pool[i] then pool[i]:Hide() end
				end
			end
		end
	end
	S:Print(L["preview: /suidummy party|raid|raid25|raid40|maintank|all"] or "preview: /suidummy party|raid|raid25|raid40|maintank|all")
end

function PV:Initialize()
	SLASH_SUIDUMMY1 = "/suidummy"
	SlashCmdList.SUIDUMMY = function(msg)
		local m = (msg or ""):lower():gsub("^%s*(.-)%s*$", "%1")
		S:SafeCall("Preview:Toggle", PV.Toggle, PV, m ~= "" and m or "all")
	end
end
