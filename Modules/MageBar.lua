-- MageBar: compact utility bar for mages - teleports/portals, conjured
-- food/water/gems and mage buffs. Secure spell buttons (usable in combat),
-- flyout menus above the bar, movable, highest learned rank only.
local _, ns = ...
local S = ns.S
local L = S.L
local MB = S:NewModule("MageBar", "magebar")

local _G = _G
local ipairs, tinsert, wipe = ipairs, table.insert, wipe
local GetSpellInfo = GetSpellInfo
local IsSpellKnown = IsSpellKnown
local IsPlayerSpell = IsPlayerSpell
local InCombatLockdown = InCombatLockdown
local IsAltKeyDown = IsAltKeyDown
local GameTooltip = GameTooltip

local SIZE, SPACING, SUB_SIZE = 30, 4, 25

-- spell ids, highest rank first (TBC/Classic era)
local TELEPORTS = {
	3561, 3562, 3565, 32271, 33690, 49359, -- alliance
	3567, 3563, 3566, 32272, 35715, 49358, -- horde
}
local PORTALS = {
	10059, 11416, 11419, 32266, 33691, 49360,
	11417, 11418, 11420, 32267, 35717, 49361,
}
local CONJURE = {
	water = { 27090, 37420, 10140, 10139, 10138, 3742, 1015, 1014, 1013, 5504 },
	food = { 33717, 28612, 27089, 10145, 10144, 8401, 1016, 1017, 1113, 1114 },
	table = { 43987, 34061 },
	gem = { 27101, 10054, 10053, 759, 3552 },
}
local BUFFS = {
	{ 27080, 10157, 10156, 1461, 1460, 1459, 1458 },          -- arcane intellect
	{ 27126, 23028 },                                          -- arcane brilliance
	{ 30482 },                                                 -- molten armor
	{ 27125, 22783, 22782, 6117 },                             -- mage armor
	{ 27124, 10220, 10219, 7320, 7302, 7301, 7300, 168 },      -- ice/frost armor
	{ 33944, 10174, 10173, 8451, 8450, 604 },                  -- dampen magic
	{ 33946, 27130, 10170, 10169, 8455, 1008 },                -- amplify magic
	{ 27128, 10225, 10223, 8458, 8457, 543 },                  -- fire ward
	{ 32796, 28609, 10177, 8462, 8461, 6143 },                 -- frost ward
}

local function Known(id)
	return IsSpellKnown(id) or IsPlayerSpell(id)
end

local function BestOf(ids)
	for _, id in ipairs(ids) do if Known(id) then return id end end
end

local function SetupSpellButton(btn, spellID)
	local name, _, icon = GetSpellInfo(spellID)
	if not name then return false end
	-- per-button attributes (type1 = left click) + AnyDown: the reliable path
	-- for secure spell casts on this client, same as the decurse buttons
	btn:SetAttribute("type1", "spell")
	btn:SetAttribute("spell1", name)
	btn:SetAttribute("type2", "spell")
	btn:SetAttribute("spell2", name)
	btn.spellID = spellID
	btn.icon:SetTexture(icon)
	return true
end

local function AddTooltip(btn)
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local ok = pcall(GameTooltip.SetSpellByID, GameTooltip, self.spellID)
		if not ok then GameTooltip:SetText(GetSpellInfo(self.spellID) or "") end
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- flyout button factory (secure)
local function FlyoutButton(parent, i)
	local btn = CreateFrame("Button", "SentinelUIMageFly" .. parent.kind .. i, parent, "SecureActionButtonTemplate")
	btn:SetSize(SUB_SIZE, SUB_SIZE)
	S:SetTemplate(btn, "Default")
	btn.icon = btn:CreateTexture(nil, "ARTWORK")
	btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	S:SetInside(btn.icon, btn, 1, 1)
	btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
	btn:RegisterForClicks("AnyDown")
	AddTooltip(btn)
	-- alt+rightclick hides the spell (PostClick so the secure cast is untouched)
	btn:SetScript("PostClick", function(self, button)
		if button == "RightButton" and IsAltKeyDown() and self.spellID then
			MB.db.hidden[self.spellID] = true
			self:Hide()
		end
	end)
	return btn
end

function MB:FillFlyout(flyout, ids)
	for _, b in ipairs(flyout.buttons) do b:Hide() b:ClearAllPoints() end
	local n = 0
	for _, id in ipairs(ids) do
		if id and not (self.db.hidden and self.db.hidden[id]) then
			n = n + 1
			local btn = flyout.buttons[n]
			if not btn then
				btn = FlyoutButton(flyout, n)
				flyout.buttons[n] = btn
			end
			if SetupSpellButton(btn, id) then
				btn:ClearAllPoints()
				btn:SetPoint("BOTTOM", flyout, "BOTTOM", 0, 5 + (n - 1) * (SUB_SIZE + SPACING))
				btn:Show()
			else n = n - 1 end
		end
	end
	flyout:SetHeight(n > 0 and (n * (SUB_SIZE + SPACING) + 5) or 1)
end

function MB:HideFlyouts()
	for _, fly in pairs(self.flyouts) do fly:Hide() end
end

function MB:BuildBar()
	local bar = CreateFrame("Frame", "SentinelUIMageBar", UIParent)
	bar:SetSize(3 * (SIZE + SPACING) + SPACING, SIZE + SPACING * 2)
	S:SetTemplate(bar, "Transparent")
	self.bar = bar
	self.flyouts = {}
	self.anchors = {}

	local defs = {
		{ key = "portals", icon = "Interface\\Icons\\Spell_Arcane_PortalIronforge",
		  tip = L["Portals"] .. " / " .. L["Teleports"], collect = function()
			local out = {}
			if self.db.showTeleports then for _, id in ipairs(TELEPORTS) do if Known(id) then tinsert(out, id) end end end
			if self.db.showPortals then for _, id in ipairs(PORTALS) do if Known(id) then tinsert(out, id) end end end
			return out
		end },
		{ key = "food", icon = "Interface\\Icons\\Inv_Drink_18", tip = L["Conjured"], collect = function()
			local out = {}
			if self.db.showFood then
				for _, k in ipairs({ "water", "food", "table", "gem" }) do
					local id = BestOf(CONJURE[k])
					if id then tinsert(out, id) end
				end
			end
			return out
		end },
		{ key = "buffs", icon = "Interface\\Icons\\Spell_Magic_MageArmor", tip = L["Buffs"], collect = function()
			local out = {}
			if self.db.showBuffs then
				for _, ids in ipairs(BUFFS) do
					local id = BestOf(ids)
					if id then tinsert(out, id) end
				end
			end
			return out
		end },
	}

	for i, d in ipairs(defs) do
		local a = CreateFrame("Button", "SentinelUIMageAnchor" .. d.key, bar)
		a:SetSize(SIZE, SIZE)
		a:SetPoint("LEFT", bar, "LEFT", SPACING + (i - 1) * (SIZE + SPACING), 0)
		S:SetTemplate(a, "Default")
		a.icon = a:CreateTexture(nil, "ARTWORK")
		a.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		a.icon:SetTexture(d.icon)
		S:SetInside(a.icon, a, 1, 1)
		a:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		a.tip = d.tip

		local fly = CreateFrame("Frame", "SentinelUIMageFlyout" .. d.key, a)
		fly.kind = d.key
		fly:SetSize(SIZE + 10, 1)
		fly:SetPoint("BOTTOM", a, "TOP", 0, 4)
		fly.buttons = {}
		S:SetTemplate(fly, "Default")
		fly:Hide()
		self.flyouts[d.key] = fly

		a:SetScript("OnClick", function(_, btn)
			if btn == "RightButton" and IsAltKeyDown() then
				wipe(MB.db.hidden) -- alt+right on anchor: unhide all
				S:Print(L["Hidden spells reset."])
				return
			end
			if InCombatLockdown() then return end
			local wasShown = fly:IsShown()
			MB:HideFlyouts()
			if not wasShown then
				MB:FillFlyout(fly, d.collect())
				fly:Show()
			end
		end)
		a:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(self.tip)
			GameTooltip:AddLine(L["Alt+Right-click: hide spell"], 0.6, 0.6, 0.6)
			GameTooltip:Show()
		end)
		a:SetScript("OnLeave", function() GameTooltip:Hide() end)
		self.anchors[d.key] = a
	end

	S:CreateMover(bar, "mageBar", L["Mage Bar"], { "BOTTOM", "UIParent", "BOTTOM", 0, 220 }, "magebar")
	-- the bar background itself drags the mover - no move mode needed
	S:AttachMoverDrag(bar, "mageBar")
end

function MB:Update()
	self.db = S.db.profile.magebar
	self.db.hidden = self.db.hidden or {}
	if self.bar then self.bar:SetShown(self.db.enable ~= false) end
end

function MB:Initialize()
	if S.myClass ~= "MAGE" then return end
	self.db = S.db.profile.magebar
	self.db.hidden = self.db.hidden or {}
	if self.db.enable == false then return end
	self:BuildBar()
	self:RegisterEvent("SPELLS_CHANGED", function()
		for _, fly in pairs(MB.flyouts or {}) do if fly:IsShown() then fly:Hide() end end
	end)
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function() MB:HideFlyouts() end)
	SlashCmdList.SENTINELUIMAGE = function()
		if InCombatLockdown() then return end
		MB.bar:SetShown(not MB.bar:IsShown())
	end
	SLASH_SENTINELUIMAGE1 = "/suimage"
	SLASH_SENTINELUIMAGE2 = "/smage"
end
