-- EnemyRadar (Spy-style): watches the combat log for hostile player actions
-- and raises a warning with name, class and level — plus an optional sound.
-- Each enemy only re-announces after a cooldown, recent enemies are listed
-- in /sui spy or the minimap-tooltip.
local _, ns = ...
local S = ns.S
local L = S.L
local ER = S:NewModule("EnemyRadar", "enemyradar")

local format, floor = format, math.floor
local CreateFrame = CreateFrame
local REACTION_HOSTILE = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x40
local TYPE_PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER or 0x400
local REPEAT_SECONDS = 120

local function bitfield(v, mask) return bit.band(v, mask) == mask end

function ER:Hostile(guid, name, flags)
	if not name or not flags then return end
	if not bitfield(flags, TYPE_PLAYER) or not bitfield(flags, REACTION_HOSTILE) then return end
	local now = GetTime()
	self.seen = self.seen or {}
	if self.seen[name] and now - self.seen[name].t < REPEAT_SECONDS then return end
	local class, level
	if GetPlayerInfoByGUID then
		local _, c, _, _, _, _, lvl = GetPlayerInfoByGUID(guid)
		class = c
		level = tonumber(lvl) -- some clients return a realm string here, not a level
	end
	self.seen[name] = { t = now, class = class, level = level }
	local cls = class and (LOCALIZED_CLASS_NAMES_MALE and (LOCALIZED_CLASS_NAMES_MALE[class] or LOCALIZED_CLASS_NAMES_FEMALE[class])) or nil
	local desc = name .. (cls and (" - " .. cls) or "") .. (level and level > 0 and (" " .. level) or "")
	if self.db.chatWarn ~= false then
		S:Print("|cffff4040" .. format(L["Enemy detected: %s"], desc) .. "|r")
	end
	if self.db.sound ~= false and PlaySoundFile then
		pcall(PlaySoundFile, "Sound\\Interface\\AlarmClockWarning3.wav")
	end
	self:Flash()
end

function ER:Flash()
	if not self.flash then
		local t = UIParent:CreateTexture(nil, "OVERLAY")
		t:SetAllPoints()
		t:SetTexture("Interface\\Buttons\\WHITE8x8")
		t:SetVertexColor(1, 0.05, 0.05)
		self.flash = t
	end
	self.flash:SetAlpha(0.35)
	UIFrameFadeOut(self.flash, 0.6, 0.35, 0)
end

function ER:Initialize()
	self.db = S.db.profile.enemyradar
	if not (CombatLogGetCurrentEventInfo and COMBATLOG_OBJECT_TYPE_PLAYER) then return end
	self.seen = {}
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", function()
		local _, sub, _, guid, name, flags, _, _, dname = CombatLogGetCurrentEventInfo()
		if sub == "UNIT_DIED" then
			if dname then ER.seen[dname] = nil end
			return
		end
		if name then ER:Hostile(guid, name, flags) end
	end)
end

function ER:Update()
	self.db = S.db.profile.enemyradar
end
