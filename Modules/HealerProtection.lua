-- Healer protection: warns the group when the healer runs out of mana,
-- takes aggro under fire, or receives Innervate. Announcements go to the
-- channel matching the current group size (party / raid / instance).
local _, ns = ...
local S = ns.S
local L = S.L
local HP = S:NewModule("HealerProtection", "healerprot")

local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local SendChatMessage = SendChatMessage
local UnitPower, UnitPowerMax, UnitPowerType = UnitPower, UnitPowerMax, UnitPowerType
local UnitGUID, UnitThreatSituation = UnitGUID, UnitThreatSituation
local IsInGroup, IsInRaid = IsInGroup, IsInRaid
local GetTime = GetTime
local format = string.format

local INNERVATE = 29166
local lastTier, lastAggro = nil, 0

local function GroupChat() return S.GroupChannel() end

local function ManaTier(ratio)
	if ratio <= 0 then return 0, L["I am completely out of mana."]
	elseif ratio <= 0.10 then return 10, L["My mana is almost gone."]
	elseif ratio <= 0.20 then return 20, L["My mana is getting low."]
	end
end

function HP:CheckMana()
	local db = self.db
	if not db or db.enable == false or not db.manaWarning or not IsInGroup() then return end
	if IsInRaid() and not db.manaInRaid then return end
	if UnitPowerType("player") ~= 0 then return end
	local max = UnitPowerMax("player", 0)
	if not max or max <= 0 then return end
	local ratio = UnitPower("player", 0) / max
	if ratio > 0.20 then lastTier = nil return end
	local tier, text = ManaTier(ratio)
	if not tier or (lastTier and tier >= lastTier) then return end
	lastTier = tier
	local ch = GroupChat()
	if ch then SendChatMessage(text, ch) end
end

function HP:COMBAT_LOG_EVENT_UNFILTERED()
	local db = self.db
	if not db or db.enable == false or not IsInGroup() then return end
	local _, sub, _, _, _, _, _, destGUID, destName, _, _, spellId, spellName = CombatLogGetCurrentEventInfo()
	if db.innervateWarning and sub == "SPELL_AURA_APPLIED" and (spellId == INNERVATE or spellName == "Innervate") then
		local ch = GroupChat()
		if ch then
			if destGUID == UnitGUID("player") then
				SendChatMessage(L["I received Innervate!"], ch)
			else
				SendChatMessage(format(L["Innervate on %s!"], destName or "?"), ch)
			end
		end
		return
	end
	-- healer aggro: taking damage while holding threat
	if not db.aggroWarning or destGUID ~= UnitGUID("player") then return end
	if sub ~= "SWING_DAMAGE" and sub ~= "SPELL_DAMAGE" and sub ~= "RANGE_DAMAGE" and sub ~= "ENVIRONMENTAL_DAMAGE" then return end
	if UnitThreatSituation and UnitThreatSituation("player") and UnitThreatSituation("player") < 2 then return end
	local now = GetTime()
	if now - lastAggro < (db.aggroCooldown or 15) then return end
	lastAggro = now
	local ch = GroupChat()
	if ch then SendChatMessage(L["I have aggro and I am taking damage."], ch) end
end

function HP:UNIT_POWER_UPDATE(event, unit, powerType)
	if unit ~= "player" then return end
	if powerType and powerType ~= "MANA" then return end
	self:CheckMana()
end

function HP:Initialize()
	self.db = S.db.profile.healerprot
	if self.db.enable == false then return end
	self.private = self.private or {}
	self.private.minimap = self.private.minimap or {}
	self.minimapBtn = S:CreateMinimapButton({
		name = "healerprot", glyph = "HP",
		store = self.private.minimap, angle = 250,
		onLeft = function() S:ToggleConfig("healerprot") end,
		onRight = function() HP.db.enable = not HP.db.enable S:Print(HP.db.enable and L["Healer Protection: on"] or L["Healer Protection: off"]) end,
		tooltip = function()
			GameTooltip:AddLine("SentinelUI " .. L["Healer Protection"])
			GameTooltip:AddLine(L["Left-click: options  |  Right-click: toggle  |  Drag: move"], 1, 1, 1)
		end,
	})
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	self:RegisterUnitEvent("UNIT_POWER_UPDATE", "UNIT_POWER_UPDATE", "player")
	SlashCmdList.SENTINELUIHEALERPROT = function() S:ToggleConfig("healerprot") end
	SLASH_SENTINELUIHEALERPROT1 = "/suihp"
end
