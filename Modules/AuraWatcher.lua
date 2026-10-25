-- AuraWatcher: generic "show me an icon while aura X exists on unit Y"
-- triggers (weakauras-lite). Up to 3 watcher slots, each with its own mover.
-- Spell accepts a name or ID; unit is any unit id (target/player/focus/pet).
local _, ns = ...
local S = ns.S
local L = S.L
local AW = S:NewModule("AuraWatcher", "aurawatcher")

local ipairs, pairs = ipairs, pairs
local floor = math.floor
local UnitAura = S.UnitAura
local IsSecret = S.IsSecret

local watchers = {}

local function Scan(unit, spell, kind)
	-- match by spell id when numeric, otherwise by aura name
	local wantId = tonumber(spell)
	local filter = kind == "debuff" and "HARMFUL" or "HELPFUL"
	for i = 1, 40 do
		local a = S.GetAura(unit, i, filter)
		if not a or not a.name then break end
		if wantId and a.spellId == wantId then return a end
		if not wantId and type(a.name) == "string" and a.name == spell then return a end
	end
	-- try the opposite filter too: users regularly configure the wrong kind
	local other = kind == "debuff" and "HELPFUL" or "HARMFUL"
	for i = 1, 40 do
		local a = S.GetAura(unit, i, other)
		if not a or not a.name then break end
		if wantId and a.spellId == wantId then return a end
		if not wantId and type(a.name) == "string" and a.name == spell then return a end
	end
end

local function BuildWatch(idx)
	local f = CreateFrame("Frame", "SentinelUIAuraWatch" .. idx, UIParent)
	f:SetSize(120, 34)
	S:SetTemplate(f, "Transparent")
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetSize(30, 30)
	f.icon:SetPoint("LEFT", 4, 0)
	f.name = S:FontString(f, 11, "OUTLINE", S.media.unitFont, nil, "LEFT")
	f.name:SetPoint("LEFT", f.icon, "RIGHT", 6, 0)
	f.time = S:FontString(f, 11, "OUTLINE", S.media.numberFont, nil, "RIGHT")
	f.time:SetPoint("RIGHT", -4, 0)
	S:CreateMover(f, "auraWatch" .. idx, L["Aura Watch"] .. " " .. idx,
		{ "CENTER", UIParent, "CENTER", -160 + (idx - 1) * 160, -60 }, "aurawatcher")
	f:Hide()
	return f
end

function AW:UpdateWatch(idx, cfg)
	local w = watchers[idx] or BuildWatch(idx)
	watchers[idx] = w
	if not self.db.enable or not cfg.enable or not cfg.spell or cfg.spell == ""
		or not UnitExists(cfg.unit or "target") then
		w:Hide()
		return
	end
	local a = Scan(cfg.unit or "target", cfg.spell, cfg.kind)
	if not a then w:Hide() return end
	w.icon:SetTexture(a.icon)
	local stacks = a.applications or 0
	w.name:SetText(a.name .. (stacks > 1 and (" x" .. stacks) or ""))
	local remain = (a.expirationTime or 0) - GetTime()
	w.time:SetText(a.duration and a.duration > 0 and floor(remain) .. "s" or "")
	w:Show()
end

function AW:UpdateAll()
	if not self.db then return end
	for i = 1, 3 do
		local cfg = self.db["watch" .. i]
		if cfg then S:SafeCall("AuraWatcher:" .. i, self.UpdateWatch, self, i, cfg) end
		S:DisableMover("auraWatch" .. i, not (self.db.enable and cfg and cfg.enable))
	end
end

function AW:Initialize()
	self.db = S.db.profile.aurawatcher
	local f = CreateFrame("Frame")
	f:RegisterEvent("UNIT_AURA")
	f:RegisterEvent("PLAYER_TARGET_CHANGED")
	f:RegisterEvent("PLAYER_FOCUS_CHANGED")
	f:SetScript("OnEvent", function(_, event, unit)
		if event == "UNIT_AURA" then
			-- only react to units that one of the watches actually looks at
			local hit
			for i = 1, 3 do
				local c = AW.db and AW.db["watch" .. i]
				if c and (c.unit or "target") == unit then hit = true break end
			end
			if not hit then return end
		end
		AW:UpdateAll()
	end)
	-- slow ticker catches aura-less state changes (unit became invalid)
	if C_Timer and C_Timer.NewTicker then
		C_Timer.NewTicker(0.5, function() AW:UpdateAll() end)
	end
end

function AW:Update()
	self.db = S.db.profile.aurawatcher
	self:UpdateAll()
end
