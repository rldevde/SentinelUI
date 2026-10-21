-- Player buffs / debuffs / weapon enchants via SecureAuraHeaderTemplate (right click cancels).
local _, ns = ...
local S = ns.S
local L = S.L
local A = S:NewModule("Auras")

local floor, max, min, format = math.floor, math.max, math.min, format
local IsSecret = S.IsSecret

local DEBUFF_COLORS = {
	Magic = { 0.2, 0.6, 1 }, Curse = { 0.6, 0, 1 }, Disease = { 0.6, 0.4, 0 }, Poison = { 0, 0.6, 0 },
}

local function TemplateFor(size)
	size = floor((size or 32) / 2 + 0.5) * 2
	return "SentinelUIAuraTemplate" .. max(16, min(64, size))
end

local function UpdateTimer(btn, elapsed)
	btn.wait = (btn.wait or 0) - elapsed
	if btn.wait > 0 then return end
	if not btn.expiration then btn.time:SetText("") btn.wait = 1 return end
	local remain = btn.expiration - GetTime()
	if remain <= 0 then btn.time:SetText("") btn.wait = 0.5 return end
	local text, nextUpdate = S:FormatTime(remain)
	btn.time:SetText(text)
	local fade = A.db and A.db.fadeThreshold or 6
	if remain <= fade then
		btn.time:SetTextColor(1, 0.3, 0.25)
		btn:SetAlpha(0.55 + 0.45 * math.abs(math.sin(GetTime() * 3)))
		btn.wait = 0.05
	else
		btn.time:SetTextColor(0.95, 0.95, 0.95)
		btn:SetAlpha(1)
		btn.wait = nextUpdate
	end
end

local function OnEnter(btn)
	GameTooltip:SetOwner(btn, "ANCHOR_BOTTOMLEFT", -5, -5)
	local slot = btn:GetAttribute("target-slot")
	if slot then
		GameTooltip:SetInventoryItem("player", slot)
	else
		local index = btn:GetAttribute("index")
		if index then GameTooltip:SetUnitAura(btn.header:GetAttribute("unit") or "player", index, btn.filter) end
	end
	GameTooltip:Show()
end

function A:UpdateAura(btn, index)
	local header = btn.header
	local unit = header:GetAttribute("unit") or "player"
	local aura = S.GetAura(unit, index, btn.filter)
	if not aura then return end
	btn.icon:SetTexture(aura.icon)
	local count = aura.applications
	if IsSecret(count) then
		btn.count:SetText(C_UnitAuras.GetAuraApplicationDisplayCount and aura.auraInstanceID and C_UnitAuras.GetAuraApplicationDisplayCount(unit, aura.auraInstanceID, 2, 999) or "")
	else
		btn.count:SetText(count and count > 1 and count or "")
	end
	local duration, expiration = aura.duration, aura.expirationTime
	if IsSecret(duration) or IsSecret(expiration) then
		btn.expiration = nil
		btn.time:SetText("")
		if C_UnitAuras.GetAuraDuration and btn.cd.SetCooldownFromDurationObject and aura.auraInstanceID then
			local obj = C_UnitAuras.GetAuraDuration(unit, aura.auraInstanceID)
			if obj then btn.cd:SetCooldownFromDurationObject(obj) btn.cd:Show() end
		end
	elseif duration and duration > 0 then
		btn.expiration = expiration
		if self.db.cooldownSwipe then btn.cd:SetCooldown(expiration - duration, duration) btn.cd:Show() else btn.cd:Hide() end
		btn.wait = 0
	else
		btn.expiration = nil
		btn.time:SetText("")
		btn.cd:Hide()
		btn:SetAlpha(1)
	end
	if btn.filter == "HARMFUL" then
		local dtype = aura.dispelName
		local c = (not IsSecret(dtype) and dtype and DEBUFF_COLORS[dtype]) or { 0.8, 0.1, 0.1 }
		btn.suiBackdrop:SetBackdropBorderColor(c[1], c[2], c[3])
	end
end

function A:UpdateWeapon(btn, slot)
	local texture = GetInventoryItemTexture("player", slot)
	btn.icon:SetTexture(texture)
	btn.count:SetText("")
	local hasMain, mainExp, _, _, hasOff, offExp = GetWeaponEnchantInfo()
	local exp = slot == 16 and mainExp or offExp
	if exp then btn.expiration = GetTime() + exp / 1000 btn.wait = 0 else btn.expiration = nil end
	btn.cd:Hide()
	btn.suiBackdrop:SetBackdropBorderColor(0.6, 0.2, 0.9)
end

local function OnAttributeChanged(btn, attr, value)
	if attr == "index" and value then
		S:SafeCall("Auras:Update", A.UpdateAura, A, btn, value)
	elseif attr == "target-slot" and value then
		S:SafeCall("Auras:Weapon", A.UpdateWeapon, A, btn, value)
	end
end

-- Called from the XML template OnLoad
function S:InitAuraButton(btn)
	S:SafeCall("Auras:Init", function()
		local header = btn:GetParent()
		btn.header = header
		btn.filter = header:GetAttribute("filter")
		-- the secure cancelaura handler reads unit/filter/index off the BUTTON;
		-- on this client the header does not forward them reliably -> set them
		-- ourselves or CancelUnitBuff silently does nothing.
		-- Up AND Down: the client runs secure clicks on key-down when the
		-- ActionButtonUseKeyDown cvar is set (default on modern classic) - with
		-- only "Up" registered the right click never reaches the handler.
		if not InCombatLockdown() then
			btn:RegisterForClicks("RightButtonUp", "RightButtonDown")
			btn:SetAttribute("unit", header:GetAttribute("unit") or "player")
			btn:SetAttribute("filter", btn.filter)
			btn:SetAttribute("type2", "cancelaura")
		end
		local db = A.db[btn.filter == "HARMFUL" and "debuffs" or "buffs"]
		S:CreateBackdrop(btn, "Default")
		btn.icon = btn:CreateTexture(nil, "ARTWORK")
		S:SetInside(btn.icon, btn, 0, 0)
		btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		btn.cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
		S:SetInside(btn.cd, btn, 0, 0)
		btn.cd:SetReverse(true)
		btn.cd:SetDrawEdge(false)
		btn.cd:SetHideCountdownNumbers(true)
		btn.cd:SetSwipeColor(0, 0, 0, 0.55)
		local textHolder = CreateFrame("Frame", nil, btn)
		textHolder:SetAllPoints()
		textHolder:SetFrameLevel(btn:GetFrameLevel() + 3)
		btn.count = S:FontString(textHolder, A.db.fontSize, "OUTLINE", S.media.numberFont)
		btn.count:SetPoint("BOTTOMRIGHT", -1, 2)
		btn.time = S:FontString(btn, A.db.fontSize, "OUTLINE", S.media.numberFont)
		btn.time:SetPoint("TOP", btn, "BOTTOM", 0, -2)
		btn.time:SetShown(db.showDuration)
		btn:SetScript("OnUpdate", UpdateTimer)
		btn:SetScript("OnEnter", OnEnter)
		btn:SetScript("OnLeave", GameTooltip_Hide)
		btn:HookScript("OnAttributeChanged", OnAttributeChanged)
		local index = btn:GetAttribute("index")
		if index then A:UpdateAura(btn, index) end
	end)
end

function A:ConfigureHeader(header)
	if InCombatLockdown() then return S:RunOutOfCombat(self.ConfigureHeader, self, header) end
	local db = self.db[header.kind]
	local size = floor((db.size or 32) / 2 + 0.5) * 2
	local left = db.growthX == "LEFT"
	local down = db.growthY == "DOWN"
	header:SetAttribute("template", TemplateFor(size))
	if header.kind == "buffs" then
		header:SetAttribute("includeWeapons", 1)
		header:SetAttribute("weaponTemplate", TemplateFor(size))
	end
	header:SetAttribute("point", (down and "TOP" or "BOTTOM") .. (left and "RIGHT" or "LEFT"))
	header:SetAttribute("xOffset", (left and -1 or 1) * (size + db.spacing))
	header:SetAttribute("yOffset", 0)
	header:SetAttribute("wrapAfter", db.perRow)
	header:SetAttribute("wrapXOffset", 0)
	header:SetAttribute("wrapYOffset", (down and -1 or 1) * (size + db.wrapSpacing))
	header:SetAttribute("maxWraps", db.maxWraps)
	header:SetAttribute("minWidth", db.perRow * (size + db.spacing))
	header:SetAttribute("minHeight", (size + db.wrapSpacing) * db.maxWraps)
	header:SetAttribute("sortMethod", db.sortMethod)
	header:SetAttribute("sortDirection", db.sortDir)
	header:SetAttribute("separateOwn", db.separateOwn)
	header:SetSize(db.perRow * (size + db.spacing), (size + db.wrapSpacing) * db.maxWraps)
	for i = 1, 40 do
		local child = header:GetAttribute("child" .. i)
		if not child then break end
		child:SetSize(size, size)
	end
	local anchor = header:GetAttribute("point")
	header:ClearAllPoints()
	header:SetPoint(anchor, header.holder, anchor)
	header.holder:SetSize(header:GetWidth(), header:GetHeight())
end

function A:CreateHeader(kind)
	local filter = kind == "buffs" and "HELPFUL" or "HARMFUL"
	local holder = CreateFrame("Frame", "SentinelUIPlayer" .. (kind == "buffs" and "Buffs" or "Debuffs") .. "Holder", UIParent)
	holder:SetSize(200, 40)
	local header = CreateFrame("Frame", "SentinelUIPlayer" .. (kind == "buffs" and "Buffs" or "Debuffs"), UIParent, "SecureAuraHeaderTemplate")
	header.kind, header.holder = kind, holder
	header:SetClampedToScreen(true)
	header:SetAttribute("unit", "player")
	header:SetAttribute("filter", filter)
	if RegisterAttributeDriver and (S.isRetail or S.isWrath or S.isCata or S.isMists) then
		RegisterAttributeDriver(header, "unit", "[vehicleui] vehicle; player")
	end
	self:ConfigureHeader(header)
	local pos = kind == "buffs" and { "TOPRIGHT", "UIParent", "TOPRIGHT", -(S.db.profile.minimap.size + 18), -6 } or { "TOPRIGHT", "SentinelUIMover_buffs", "BOTTOMRIGHT", 0, -12 }
	S:CreateMover(holder, kind, kind == "buffs" and L["Player Buffs"] or L["Player Debuffs"], pos, "auras")
	self:ConfigureHeader(header)
	header:Show()
	self[kind] = header
end

function A:DisableBlizzard()
	for _, name in ipairs({ "BuffFrame", "DebuffFrame", "TemporaryEnchantFrame" }) do
		local f = _G[name]
		if f then
			f:UnregisterAllEvents()
			f:SetParent(S.hiddenFrame)
			f:Hide()
		end
	end
end

function A:Update()
	if self.buffs then self:ConfigureHeader(self.buffs) end
	if self.debuffs then self:ConfigureHeader(self.debuffs) end
end

function A:Initialize()
	if self.private.disableBlizzard then self:DisableBlizzard() end
	self:CreateHeader("buffs")
	self:CreateHeader("debuffs")
end
