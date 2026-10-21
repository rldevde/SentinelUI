local _, ns = ...
local S = ns.S
local L = S.L
local TT = S:NewModule("Tooltip")

local _G = _G
local format, pairs, ipairs, select, floor = format, pairs, ipairs, select, math.floor
local IsSecret = S.IsSecret
local BLANK = [[Interface\Buttons\WHITE8X8]]

local inspectCache = {}
local INSPECT_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

local function SafeText(line)
	if not line then return end
	local t = line:GetText()
	if IsSecret(t) then return nil end
	return t
end

-- Styling -------------------------------------------------------------------
function TT:StyleTooltip(tt)
	if not tt or tt.suiStyled or (tt.IsForbidden and tt:IsForbidden()) then return end
	tt.suiStyled = true
	if tt.NineSlice then tt.NineSlice:SetAlpha(0) end
	if tt.SetBackdrop and not tt.NineSlice then pcall(tt.SetBackdrop, tt, nil) end
	local bd = CreateFrame("Frame", nil, tt, S.BackdropTemplate)
	bd:SetAllPoints()
	bd:SetFrameLevel(math.max(0, tt:GetFrameLevel() - 1))
	S:SetTemplate(bd, "Transparent", "TOP")
	tt.suiBackdrop = bd
	if tt.HookScript then
		tt:HookScript("OnShow", function(self)
			if self.NineSlice then self.NineSlice:SetAlpha(0) end
			if self.suiBackdrop then self.suiBackdrop:SetBackdropBorderColor(unpack(S.media.borderColor)) end
		end)
	end
	local close = tt.CloseButton or (tt:GetName() and _G[tt:GetName() .. "CloseButton"])
	if close then S:SkinCloseButton(close) end
end

function TT:StyleStatusBar()
	local bar = GameTooltipStatusBar
	if not bar or bar.suiStyled then return end
	bar.suiStyled = true
	bar:SetStatusBarTexture(S.media.statusbar)
	bar:ClearAllPoints()
	bar:SetPoint("BOTTOMLEFT", GameTooltip, "TOPLEFT", S.mult, 3)
	bar:SetPoint("BOTTOMRIGHT", GameTooltip, "TOPRIGHT", -S.mult, 3)
	bar:SetHeight(self.db.healthBarHeight)
	S:CreateBackdrop(bar, "Default")
	bar.text = S:FontString(bar, 10, "OUTLINE", S.media.numberFont)
	bar.text:SetPoint("CENTER", 0, 0)
	if bar.Text then bar.Text:SetAlpha(0) end
	if GameTooltipStatusBarTexture then GameTooltipStatusBarTexture:SetTexture(S.media.statusbar) end
	hooksecurefunc(bar, "Show", function(b)
		if TT.db and not TT.db.healthBar then b:Hide() end
	end)
	bar:HookScript("OnValueChanged", function(b, value)
		if not TT.db.healthText or not value or IsSecret(value) then if b.text then b.text:SetText("") end return end
		local _, mx = b:GetMinMaxValues()
		if IsSecret(mx) then b.text:SetText("") return end
		local _, unit = GameTooltip:GetUnit()
		if unit and not IsSecret(unit) and UnitExists(unit) then
			b.text:SetText(UnitIsDeadOrGhost(unit) and DEAD or (S:Abbrev(UnitHealth(unit)) .. " / " .. S:Abbrev(UnitHealthMax(unit))))
		elseif mx and mx > 0 then
			b.text:SetText(format("%d%%", floor(value / mx * 100)))
		end
	end)
end

-- Positioning ---------------------------------------------------------------
function TT:SetDefaultAnchor(tt, parent)
	if not tt or (tt.IsForbidden and tt:IsForbidden()) then return end
	local db = self.db
	if db.anchor == "CURSOR" then
		tt:SetOwner(parent, "ANCHOR_CURSOR_RIGHT", db.cursorX, db.cursorY)
		return
	end
	if db.anchor == "DEFAULT" then return end
	if tt:GetAnchorType() ~= "ANCHOR_NONE" then return end
	tt:ClearAllPoints()
	local holder = self.holder
	local _, y = holder:GetCenter()
	if y and y > UIParent:GetHeight() / 2 then
		tt:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)
	else
		tt:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
	end
end

-- Unit tooltip --------------------------------------------------------------
local function ItemLevelFromUnit(unit)
	local total, count = 0, 0
	local mh = GetInventoryItemLink(unit, 16)
	for _, slot in ipairs(INSPECT_SLOTS) do
		local link = GetInventoryItemLink(unit, slot)
		-- a 2H in the main hand may also be reported in slot 17 -> count once
		if slot == 17 and link and mh and link == mh then link = nil end
		if link then
			local ilvl = S.GetDetailedItemLevelInfo and S.GetDetailedItemLevelInfo(link)
			if not ilvl then ilvl = select(4, S.GetItemInfo(link)) end
			if ilvl and ilvl > 0 then
				total = total + ilvl
				count = count + 1
			end
		end
	end
	if count == 0 then return nil end
	return floor(total / count)
end

function TT:INSPECT_READY(_, guid)
	if not guid or guid ~= self.inspectGUID then return end
	local unit = self.inspectUnit
	if unit and UnitGUID(unit) == guid then
		local ilvl = ItemLevelFromUnit(unit)
		local spec
		if GetInspectSpecialization then
			local id = GetInspectSpecialization(unit)
			if id and id > 0 and GetSpecializationInfoByID then spec = select(2, GetSpecializationInfoByID(id)) end
		end
		inspectCache[guid] = { ilvl = ilvl, spec = spec, time = GetTime() }
		local _, ttUnit = GameTooltip:GetUnit()
		if ttUnit and not IsSecret(ttUnit) and UnitGUID(ttUnit) == guid and GameTooltip:IsShown() then
			self:AddInspectLine(GameTooltip, guid)
			GameTooltip:Show()
		end
	end
	self.inspectGUID = nil
	self.inspectPendingAt = nil
	if ClearInspectPlayer and not (InspectFrame and InspectFrame:IsShown()) then ClearInspectPlayer() end
end

function TT:AddInspectLine(tt, guid)
	local data = inspectCache[guid]
	if not data or tt.suiInspectAdded then return end
	tt.suiInspectAdded = true
	if data.spec then tt:AddDoubleLine(L["Specialization"] .. ":", data.spec, 0.6, 0.6, 0.6, 1, 1, 1) end
	if data.ilvl then tt:AddDoubleLine(L["Item Level"] .. ":", data.ilvl, 0.6, 0.6, 0.6, S.accent.r, S.accent.g, S.accent.b) end
end

function TT:OnTooltipSetUnit(tt)
	if tt ~= GameTooltip or (tt.IsForbidden and tt:IsForbidden()) then return end
	local _, unit = tt:GetUnit()
	if not unit or IsSecret(unit) then
		local focus = S.GetMouseFocus()
		unit = focus and focus.GetAttribute and focus:GetAttribute("unit")
	end
	if not unit or IsSecret(unit) or not UnitExists(unit) then return end
	local db = self.db
	tt.suiInspectAdded = nil

	if db.hideInCombat and InCombatLockdown() then
		local mod = db.hideInCombatModifier
		local pressed = (mod == "SHIFT" and IsShiftKeyDown()) or (mod == "CTRL" and IsControlKeyDown()) or (mod == "ALT" and IsAltKeyDown())
		if not pressed then tt:Hide() return end
	end

	local isPlayer = UnitIsPlayer(unit)
	local color = S.UnitColor(unit)
	local line1 = _G.GameTooltipTextLeft1
	if isPlayer then
		local name, realm = UnitName(unit)
		if IsSecret(name) then return end
		local title = UnitPVPName and UnitPVPName(unit)
		local text = name
		if db.showRealm and realm and realm ~= "" then text = text .. "-" .. realm end
		if UnitIsAFK(unit) then text = text .. " |cffff9900<AFK>|r" elseif UnitIsDND(unit) then text = text .. " |cffff3333<DND>|r" end
		if db.classColorNames then line1:SetText(S:Hex(color) .. text .. "|r") else line1:SetText(text) end

		local guild, rank = GetGuildInfo(unit)
		local levelLine = 2
		if guild then
			local line2 = _G.GameTooltipTextLeft2
			local myGuild = GetGuildInfo("player")
			local gc = (myGuild == guild) and "|cff40ff40" or ("|cff" .. S.accentHex)
			line2:SetText(gc .. "<" .. guild .. ">|r" .. (db.showGuildRank and rank and (" |cffaaaaaa" .. rank .. "|r") or ""))
			levelLine = 3
		end
		for i = levelLine, tt:NumLines() do
			local l = _G["GameTooltipTextLeft" .. i]
			local t = SafeText(l)
			if t and t:find(LEVEL) then
				local level = UnitLevel(unit)
				local race = UnitRace(unit) or ""
				local className = UnitClass(unit) or ""
				local diff = GetQuestDifficultyColor and GetQuestDifficultyColor(level > 0 and level or 999) or { r = 1, g = 1, b = 1 }
				l:SetText(format("%s%s|r %s %s%s|r", S:Hex(diff), level > 0 and level or "??", race, S:Hex(color), className))
				break
			end
		end
		if db.factionColors then
			local faction = UnitFactionGroup(unit)
			local label = faction == "Alliance" and FACTION_ALLIANCE or faction == "Horde" and FACTION_HORDE
			if label then
				for i = 2, tt:NumLines() do
					local l = _G["GameTooltipTextLeft" .. i]
					if SafeText(l) == label then
						if faction == "Alliance" then l:SetTextColor(0.3, 0.55, 1) else l:SetTextColor(1, 0.25, 0.25) end
						break
					end
				end
			end
		end
		if db.showMount and C_MountJournal and C_MountJournal.GetMountFromSpell and S.GetAura then
			for i = 1, 40 do
				local aura = S.GetAura(unit, i, "HELPFUL")
				if not aura then break end
				local sid = aura.spellId
				if sid and not IsSecret(sid) then
					local mountID = C_MountJournal.GetMountFromSpell(sid)
					if mountID then
						tt:AddDoubleLine(L["Mount"] .. ":", aura.name or "", 0.6, 0.6, 0.6, 1, 1, 1)
						break
					end
				end
			end
		end
		if db.showItemLevel or db.inspect then
			local guid = UnitGUID(unit)
			if UnitIsUnit(unit, "player") then
				inspectCache[guid] = { ilvl = ItemLevelFromUnit("player"), spec = S.GetSpecName(), time = GetTime() }
				self:AddInspectLine(tt, guid)
			elseif inspectCache[guid] and GetTime() - inspectCache[guid].time < 120 then
				self:AddInspectLine(tt, guid)
			elseif db.inspect and CanInspect(unit) and not InCombatLockdown() and not (InspectFrame and InspectFrame:IsShown()) then
				-- only one pending inspect: extra NotifyInspect calls can
				-- swallow the InspectFrame's own query -> empty slots
				if not self.inspectPendingAt or (GetTime() - self.inspectPendingAt) > 3 then
					self.inspectPendingAt = GetTime()
					self.inspectGUID, self.inspectUnit = guid, unit
					NotifyInspect(unit)
				end
			end
		end
	else
		line1:SetTextColor(color.r, color.g, color.b)
		local c = UnitClassification(unit)
		local extra = c == "rare" and " |cffc0c0c0(" .. L["Rare"] .. ")|r" or c == "rareelite" and " |cffc0c0c0(" .. L["Rare Elite"] .. ")|r" or c == "elite" and " |cffffcc00(" .. L["Elite"] .. ")|r" or c == "worldboss" and " |cffff3333(" .. L["Boss"] .. ")|r" or ""
		if extra ~= "" then
			local t = SafeText(line1)
			if t then line1:SetText(t .. extra) end
		end
	end

	if db.showTarget then
		local target = unit .. "target"
		if UnitExists(target) then
			local tname = UnitName(target)
			if not IsSecret(tname) then
				local tc = S.UnitColor(target)
				local txt = UnitIsUnit(target, "player") and ("|cffff3333>> " .. YOU .. " <<|r") or (S:Hex(tc) .. tname .. "|r")
				tt:AddDoubleLine(TARGET .. ":", txt, 0.6, 0.6, 0.6)
			end
		end
	end

	if tt.suiBackdrop then
		if isPlayer and db.classColorNames then
			tt.suiBackdrop:SetBackdropBorderColor(color.r * 0.8, color.g * 0.8, color.b * 0.8)
		else
			tt.suiBackdrop:SetBackdropBorderColor(unpack(S.media.borderColor))
		end
	end
	if GameTooltipStatusBar then
		GameTooltipStatusBar:SetShown(db.healthBar)
		GameTooltipStatusBar:SetStatusBarColor(color.r, color.g, color.b)
	end
end

-- Items / spells ------------------------------------------------------------
function TT:OnTooltipSetItem(tt, data)
	if not tt or (tt.IsForbidden and tt:IsForbidden()) then return end
	local db = self.db
	local _, link = tt:GetItem()
	if not link or IsSecret(link) then return end
	local id = tonumber(link:match("item:(%d+)"))
	if not id then return end
	if db.showItemCount then
		local GetCount = (C_Item and C_Item.GetItemCount) or GetItemCount
		local bags = GetCount(id) or 0
		local total = GetCount(id, true) or 0
		if total > 0 then
			tt:AddDoubleLine(L["Count"] .. ":", format("%d |cffaaaaaa(%s %d)|r", total, L["Bank"], total - bags), 0.6, 0.6, 0.6, 1, 1, 1)
		end
	end
	if db.showIDs then tt:AddDoubleLine(L["Item ID"] .. ":", id, 0.6, 0.6, 0.6, 1, 1, 1) end
	if tt.suiBackdrop then
		local quality = select(3, S.GetItemInfo(link))
		if quality and quality > 1 then
			local r, g, b = S.GetItemQualityColor(quality)
			tt.suiBackdrop:SetBackdropBorderColor(r, g, b)
		else
			tt.suiBackdrop:SetBackdropBorderColor(unpack(S.media.borderColor))
		end
	end
end

function TT:AddSpellID(tt, id)
	if not self.db.showIDs or not id or IsSecret(id) then return end
	for i = tt:NumLines(), math.max(1, tt:NumLines() - 3), -1 do
		local t = SafeText(_G[tt:GetName() .. "TextLeft" .. i])
		if t and t:find(L["Spell ID"], 1, true) then return end
	end
	tt:AddDoubleLine(L["Spell ID"] .. ":", id, 0.6, 0.6, 0.6, 1, 1, 1)
	tt:Show()
end

function TT:OnTooltipSetSpell(tt)
	if not tt or (tt.IsForbidden and tt:IsForbidden()) or not tt.GetSpell then return end
	local _, id = tt:GetSpell()
	self:AddSpellID(tt, id)
end

function TT:HookAuras()
	local function AddAura(tt, unit, index, filter)
		if not tt or (tt.IsForbidden and tt:IsForbidden()) then return end
		local aura = S.GetAura(unit, index, filter)
		if not aura then return end
		local caster = aura.sourceUnit
		if caster and not IsSecret(caster) and UnitExists(caster) then
			local c = S.UnitColor(caster)
			tt:AddDoubleLine(L["Caster"] .. ":", S:Hex(c) .. (UnitName(caster) or "") .. "|r", 0.6, 0.6, 0.6)
		end
		TT:AddSpellID(tt, aura.spellId)
	end
	hooksecurefunc(GameTooltip, "SetUnitAura", function(tt, unit, index, filter) S:SafeCall("Tooltip:Aura", AddAura, tt, unit, index, filter) end)
	if GameTooltip.SetUnitBuff then hooksecurefunc(GameTooltip, "SetUnitBuff", function(tt, unit, index, filter) S:SafeCall("Tooltip:Aura", AddAura, tt, unit, index, (filter and filter ~= "" and filter or "HELPFUL")) end) end
	if GameTooltip.SetUnitDebuff then hooksecurefunc(GameTooltip, "SetUnitDebuff", function(tt, unit, index, filter) S:SafeCall("Tooltip:Aura", AddAura, tt, unit, index, (filter and filter ~= "" and filter or "HARMFUL")) end) end
end

function TT:Update()
	if GameTooltipStatusBar then GameTooltipStatusBar:SetHeight(self.db.healthBarHeight) end
	local font = self.db.font and S:Fetch("font", self.db.font) or S.media.font
	if GameTooltipHeaderText then GameTooltipHeaderText:SetFont(font, self.db.headerFontSize, "") end
	if GameTooltipText then GameTooltipText:SetFont(font, self.db.fontSize, "") end
	if GameTooltipTextSmall then GameTooltipTextSmall:SetFont(font, self.db.fontSize - 1, "") end
end

function TT:Initialize()
	local holder = CreateFrame("Frame", "SentinelUITooltipHolder", UIParent)
	holder:SetSize(220, 60)
	S:CreateMover(holder, "tooltip", L["Tooltip"], { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -6, 240 }, "tooltip")
	self.holder = holder

	for _, name in ipairs({ "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2", "WorldMapTooltip", "WorldMapCompareTooltip1", "WorldMapCompareTooltip2", "EmbeddedItemTooltip", "FriendsTooltip", "QuestScrollFrame.StoryTooltip", "SmallTextTooltip", "ReputationParagonTooltip", "QuickKeybindTooltip", "GameNoHeaderTooltip", "NamePlateTooltip", "LibDBIconTooltip", "SettingsTooltip", "DropDownList1MenuBackdrop", "DropDownList2MenuBackdrop" }) do
		self:StyleTooltip(_G[name])
	end
	self:StyleStatusBar()
	self:Update()

	if SharedTooltip_SetBackdropStyle then
		hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tt)
			if tt and tt.NineSlice and tt.suiStyled then tt.NineSlice:SetAlpha(0) end
		end)
	end
	if GameTooltip_SetBackdropStyle then
		hooksecurefunc("GameTooltip_SetBackdropStyle", function(tt)
			if tt and tt.NineSlice and tt.suiStyled then tt.NineSlice:SetAlpha(0) end
		end)
	end

	self:SecureHook("GameTooltip_SetDefaultAnchor", "SetDefaultAnchor")

	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt) S:SafeCall("Tooltip:Unit", TT.OnTooltipSetUnit, TT, tt) end)
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data) S:SafeCall("Tooltip:Item", TT.OnTooltipSetItem, TT, tt, data) end)
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tt) S:SafeCall("Tooltip:Spell", TT.OnTooltipSetSpell, TT, tt) end)
	else
		self:HookScript(GameTooltip, "OnTooltipSetUnit", "OnTooltipSetUnit")
		for _, t in ipairs({ GameTooltip, ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2 }) do
			if t then
				self:HookScript(t, "OnTooltipSetItem", "OnTooltipSetItem")
				self:HookScript(t, "OnTooltipSetSpell", "OnTooltipSetSpell")
			end
		end
	end
	self:HookAuras()
	self:RegisterEvent("INSPECT_READY")
	self:RegisterEvent("MODIFIER_STATE_CHANGED", function()
		if GameTooltip:IsShown() and GameTooltip:GetUnit() then
			local _, unit = GameTooltip:GetUnit()
			if unit and not IsSecret(unit) then GameTooltip:SetUnit(unit) end
		end
	end)
end
