-- ClickCast: Clique-style click bindings on the unit frames. Modifier+button
-- combos (shift/ctrl/alt × left/right/middle) cast a configured spell on the
-- frame's unit instead of targeting. Plain clicks still target, so normal
-- play is untouched. Spell names or IDs, per character.
local _, ns = ...
local S = ns.S
local L = S.L
local CC = S:NewModule("ClickCast", "clickcast")

local ipairs, pairs = ipairs, pairs
local InCombatLockdown = InCombatLockdown

-- { optionKey, attributePrefix, buttonIndex }
local COMBOS = {
	{ "shift1", "shift-", 1 }, { "shift2", "shift-", 2 }, { "shift3", "shift-", 3 },
	{ "ctrl1", "ctrl-", 1 }, { "ctrl2", "ctrl-", 2 }, { "ctrl3", "ctrl-", 3 },
	{ "alt1", "alt-", 1 }, { "alt2", "alt-", 2 }, { "alt3", "alt-", 3 },
}

function CC:ApplyTo(btn)
	if not btn or not btn.SetAttribute then return end
	for _, c in ipairs(COMBOS) do
		local typeAttr = c[2] .. "-type" .. c[3]
		local spellAttr = c[2] .. "-spell" .. c[3]
		local spell = self.db[c[1]]
		if spell and spell ~= "" then
			-- numbers are spell IDs, everything else is a spell name
			btn:SetAttribute(typeAttr, "spell")
			btn:SetAttribute(spellAttr, tonumber(spell) or spell)
		else
			btn:SetAttribute(typeAttr, nil)
			btn:SetAttribute(spellAttr, nil)
		end
	end
end

function CC:ApplyAll()
	if InCombatLockdown() then self.deferred = true return end
	self.deferred = nil
	local UF = S:GetModule("UnitFrames")
	local n = 0
	for _, f in pairs(UF and UF.units or {}) do
		self:ApplyTo(f)
		n = n + 1
	end
	-- party/raid group header children are spawned by the secure header;
	-- only already-created children can take attributes (out of combat)
	for _, h in pairs(UF and UF.headers or {}) do
		if h.GetChildren then
			for i = 1, h:GetNumChildren() do
				self:ApplyTo((select(i, h:GetChildren())))
				n = n + 1
			end
		end
	end
end

function CC:Initialize()
	self.db = S.db.profile.clickcast
	if not self.db.enable then return end
	-- frames may not exist yet at load; apply on world entry + roster changes
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "ApplyAll")
	self:RegisterEvent("GROUP_ROSTER_UPDATE", "ApplyAll")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		if self.deferred then self:ApplyAll() end
	end)
	-- first frames arrive during other modules' init: apply shortly after load
	if C_Timer and C_Timer.After then C_Timer.After(2, function() CC:ApplyAll() end) end
end

function CC:Update()
	self.db = S.db.profile.clickcast
	self:ApplyAll()
end
