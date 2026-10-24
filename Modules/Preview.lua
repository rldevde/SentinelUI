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

local HEADERS = { "SentinelUI_PartyHeader", "SentinelUI_RaidHeader", "SentinelUI_MaintankHeader" }

local function HeaderChildren(header)
	-- real unit buttons inside the header, in order
	local out = {}
	local n = header:GetName()
	for i = 1, 40 do
		local c = header:GetAttribute("child" .. i) or _G[n .. "UnitButton" .. i]
		if c then out[#out + 1] = c end
	end
	if #out == 0 then
		for _, c in ipairs({ header:GetChildren() }) do out[#out + 1] = c end
	end
	return out
end

function PV:Toggle()
	shown = not shown
	local idx = 1
	for _, h in ipairs(HEADERS) do
		local anchor = _G[h]
		if anchor then
			for i, child in ipairs(HeaderChildren(anchor)) do
				local d = Dummy(UIParent, idx)
				d:ClearAllPoints()
				d:SetAllPoints(child) -- exactly over the real unit slot
				local w, hgt = child:GetSize()
				Fill(d, idx, w > 0 and w or 120, hgt > 0 and hgt or 30)
				idx = idx + 1
				if idx > 40 then break end
			end
		end
	end
	for i = idx, #pool do pool[i]:Hide() end
	if shown and idx == 1 then
		-- solo/no group: headers may hold zero children - show a fallback row
		for i = 1, 5 do
			local d = Dummy(UIParent, i)
			d:ClearAllPoints()
			d:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 70, -280 - (i - 1) * 46)
			Fill(d, i, 180, 42)
		end
		idx = 6
	end
	S:Print(shown and (L["Dummy preview on - /suidummy to hide"] or "Dummy preview on")
		or (L["Dummy preview off"] or "Dummy preview off"))
end

function PV:Initialize()
	SLASH_SUIDUMMY1 = "/suidummy"
	SlashCmdList.SUIDUMMY = function() PV:Toggle() end
end
