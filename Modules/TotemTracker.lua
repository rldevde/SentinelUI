-- Totem bar: independent totem tracker replacing the Blizzard TotemFrame (shamans).
local _, ns = ...
local S = ns.S
local L = S.L
local TT = S:NewModule("TotemTracker")

local _G = _G
local ipairs = ipairs
local GetTotemInfo = GetTotemInfo
local MAX_TOTEMS = MAX_TOTEMS or 4

-- classic clients report totems in a different visual order than their slot ids
local CLASSIC_ORDER = { 2, 1, 3, 4 }

function TT:UpdateButton(button, slot)
	if not button then return end
	local haveTotem, _, startTime, duration, icon = GetTotemInfo(slot)
	if haveTotem and icon then
		button.icon:SetTexture(icon)
		if duration and duration > 0 then
			button.cooldown:SetCooldown(startTime, duration)
		else
			button.cooldown:Clear()
		end
		button:Show()
	else
		button.cooldown:Clear()
		button:Hide()
	end
end

function TT:Refresh()
	if not self.bar then return end
	if S.isRetail then
		local tf = _G.TotemFrame
		for _, button in ipairs(self.bar.buttons) do button:Hide() end
		if tf and tf.totemPool then
			for totem in tf.totemPool:EnumerateActive() do
				local prio = _G.STANDARD_TOTEM_PRIORITIES or { 1, 2, 3, 4 }
				local button = self.bar.buttons[prio[totem.layoutIndex] or totem.layoutIndex]
				if button and totem.slot then self:UpdateButton(button, totem.slot) end
			end
		end
	else
		for i = 1, MAX_TOTEMS do
			local prio = (_G.STANDARD_TOTEM_PRIORITIES or CLASSIC_ORDER)[i] or i
			self:UpdateButton(self.bar.buttons[prio], i)
		end
	end
end

function TT:Layout()
	local db = self.db
	local size, spacing = db.size or 26, db.spacing or 3
	for i, button in ipairs(self.bar.buttons) do
		button:SetSize(size, size)
		button:ClearAllPoints()
		if i == 1 then
			button:SetPoint("LEFT", self.bar, "LEFT", spacing, 0)
		else
			button:SetPoint("LEFT", self.bar.buttons[i - 1], "RIGHT", spacing, 0)
		end
	end
	self.bar:SetSize((size + spacing) * MAX_TOTEMS + spacing, size + spacing * 2)
	if S.movers.totemTracker then S.movers.totemTracker:SetSize(self.bar:GetSize()) end
	self:Refresh()
end

-- options changed: re-read settings and relayout
function TT:Update()
	self.db = S.db.profile.general.totemTracker
	if self.bar then self:Layout() end
end

function TT:Create()
	local bar = CreateFrame("Frame", "SentinelUITotemTracker", UIParent)
	bar.buttons = {}
	for i = 1, MAX_TOTEMS do
		local button = CreateFrame("Button", "SentinelUITotem" .. i, bar)
		button:SetID(i)
		button:Hide()
		S:SetTemplate(button, "Default")
		button.icon = button:CreateTexture(nil, "ARTWORK")
		button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		S:SetInside(button.icon, button, 2, 2)
		button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
		button.cooldown:SetAllPoints(button.icon)
		bar.buttons[i] = button
	end
	self.bar = bar
	S:CreateMover(bar, "totemTracker", L["Totem Bar"], { "BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 490, 30 }, "general")
	self:Layout()

	-- Blizzard TotemFrame is replaced by this bar
	local tf = _G.TotemFrame
	if tf then
		tf:UnregisterAllEvents()
		tf:SetParent(S.hiddenFrame)
	end
end

function TT:Initialize()
	self.db = S.db.profile.general and S.db.profile.general.totemTracker or { size = 26, spacing = 3 }
	if self.db.enable == false then return end
	-- only meaningful for shamans on classic; harmless elsewhere
	if S.myClass ~= "SHAMAN" and not S.isRetail then return end
	self:Create()
	self:RegisterEvent("PLAYER_TOTEM_UPDATE", function() TT:Refresh() end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function() TT:Refresh() end)
	self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function() TT:Refresh() end)
	self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", function() TT:Refresh() end)
end
