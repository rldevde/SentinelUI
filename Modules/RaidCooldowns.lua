-- Raid cooldown tracker: watches combat log casts of known raid cooldowns
-- (defensives, utility, battle res) by party/raid members and shows a live
-- bar list with remaining time. Own implementation, oRA3/ExRT style.
local _, ns = ...
local S = ns.S
local L = S.L
local RCD = S:NewModule("RaidCooldowns")

local _G = _G
local pairs, ipairs, sort, wipe = pairs, ipairs, sort, wipe
local tinsert, tremove = tinsert, table.remove
local format, floor, min = format, floor, math.min
local CreateFrame = CreateFrame
local GetTime = GetTime
local strsplit, select, max = strsplit, select, math.max
local IsSecret = S.IsSecret
local bit_band = _G.bit and _G.bit.band
if not bit_band then
	-- pure-Lua fallback for clients without the bit library (values < 2^31)
	bit_band = function(a, b)
		local res, bitv = 0, 1
		while a > 0 and b > 0 do
			local ab, bb = a % 2, b % 2
			if ab == 1 and bb == 1 then res = res + bitv end
			a, b = (a - ab) / 2, (b - bb) / 2
			bitv = bitv * 2
		end
		return res
	end
end

-- group membership flag mask (MINE | PARTY | RAID are non-overlapping bits,
-- so addition equals bitwise-or)
local GROUP_MASK = (COMBATLOG_OBJECT_AFFILIATION_MINE or 1)
	+ (COMBATLOG_OBJECT_AFFILIATION_PARTY or 2) + (COMBATLOG_OBJECT_AFFILIATION_RAID or 4)

-- spellID -> cooldown seconds. Covers TBC ranks and common retail-era CDs;
-- entries that never fire on this client are harmless.
local CDS = {
	-- shaman
	[2825] = 600,   -- Bloodlust
	[32182] = 600,  -- Heroism
	[16190] = 300,  -- Mana Tide Totem
	-- druid
	[29166] = 360,  -- Innervate
	[740] = 480,    -- Tranquility
	[20742] = 1200, [20747] = 1200, [20748] = 1200, [26994] = 1200, [48477] = 1200, -- Rebirth ranks
	-- priest
	[33206] = 180,  -- Pain Suppression
	[10060] = 180,  -- Power Infusion
	[64843] = 480,  -- Divine Hymn
	[724] = 600,    -- Lightwell
	-- paladin
	[633] = 3600,   -- Lay on Hands
	[1022] = 300, [5599] = 300, [10278] = 300, -- Blessing of Protection
	[19752] = 3600, -- Divine Intervention
	[31821] = 180,  -- Aura Mastery (wrath+)
	-- warrior
	[871] = 1800,   -- Shield Wall
	[12975] = 600,  -- Last Stand
	[97462] = 180,  -- Rallying Cry
	-- mage / warlock
	[45438] = 300,  -- Ice Block
	[20707] = 900,  -- Soulstone
	-- hunter
	[34477] = 30,   -- Misdirection
	[5384] = 300,   -- Feign Death
	-- dk / monk / dh / retail raid CDs
	[51052] = 120,  -- Anti-Magic Zone
	[98008] = 180,  -- Spirit Link Totem
	[108280] = 180, -- Healing Tide Totem
	[62618] = 180,  -- Power Word: Barrier
	[265202] = 720, -- Holy Word: Salvation
	[115310] = 180, -- Revival
	[363534] = 240, -- Rewind
	[196718] = 300, -- Darkness
}
-- SPELL_RESURRECT variants that also start a cooldown entry
local REZ_CD = { [20742] = true, [20747] = true, [20748] = true, [26994] = true, [48477] = true }

RCD.active = {} -- { guid, spellID, name, icon, srcName, class, expiry, dur }

local function BarsFrame(rcd)
	if rcd.frame then return rcd.frame end
	local db = rcd.db
	local f = CreateFrame("Frame", "SentinelUIRaidCD", UIParent, S.BackdropTemplate)
	f:SetSize(db.width or 190, 120)
	f:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
	S:SetTemplate(f, "Transparent")
	f.title = S:FontString(f, 11, "OUTLINE", S.media.unitFont, nil, "LEFT")
	f.title:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 2)
	f.title:SetText(L["Raid Cooldowns"])
	f.rows = {}
	f:SetScript("OnUpdate", function(_, e)
		f.el = (f.el or 0) + e
		if f.el < 0.25 then return end
		f.el = 0
		rcd:Layout()
	end)
	rcd.frame = f
	S:CreateMover(f, "raidCDs", L["Raid Cooldowns"], { "CENTER", "UIParent", "CENTER", 340, 0 }, "general")
	return f
end

local function Row(f, i)
	local r = f.rows[i]
	if not r then
		r = CreateFrame("StatusBar", nil, f)
		r:SetStatusBarTexture(S:Fetch("statusbar", S.db.profile.general.statusbar, "Sentinel"))
		r.bg = r:CreateTexture(nil, "BACKGROUND")
		r.bg:SetAllPoints()
		r.bg:SetTexture(S:Fetch("statusbar", S.db.profile.general.statusbar, "Sentinel"))
		r.bg:SetVertexColor(0, 0, 0, 0.45)
		r.icon = r:CreateTexture(nil, "OVERLAY")
		r.name = S:FontString(r, 10, "OUTLINE", S.media.unitFont, nil, "LEFT")
		r.time = S:FontString(r, 10, "OUTLINE", S.media.numberFont, nil, "RIGHT")
		f.rows[i] = r
	end
	return r
end

function RCD:Track(guid, srcName, srcFlags, spellID, cd)
	if not spellID or IsSecret(spellID) then return end
	-- one entry per player+spell: a recast refreshes the bar
	local name, _, icon = S.GetSpellInfo(spellID)
	local class
	if GetPlayerInfoByGUID then
		local ok, cls = pcall(function() return select(2, GetPlayerInfoByGUID(guid)) end)
		if ok then class = cls end
	end
	local now = GetTime()
	for _, a in ipairs(self.active) do
		if a.guid == guid and a.spellID == spellID then
			a.expiry, a.dur = now + cd, cd
			return
		end
	end
	self.active[#self.active + 1] = {
		guid = guid, spellID = spellID, cd = cd, expiry = now + cd,
		name = name or "?", icon = icon,
		srcName = srcName and select(1, strsplit("-", srcName)) or "?",
		class = class,
	}
	self:Layout()
end

function RCD:OnCombatLog()
	local _, sub, _, srcGUID, srcName, srcFlags, _, _, _, _, _, spellID = CombatLogGetCurrentEventInfo()
	if IsSecret(srcGUID) or IsSecret(spellID) then return end
	if sub ~= "SPELL_CAST_SUCCESS" and sub ~= "SPELL_RESURRECT" then return end
	if bit_band(srcFlags or 0, GROUP_MASK) == 0 then return end
	local cd = CDS[spellID]
	if cd then self:Track(srcGUID, srcName, srcFlags, spellID, cd) end
end

local tmp = {}
function RCD:Layout()
	local f, db = self.frame, self.db
	if not f then return end
	local now = GetTime()
	-- drop expired
	for i = #self.active, 1, -1 do
		if self.active[i].expiry <= now then tremove(self.active, i) end
	end
	sort(self.active, function(a, b) return a.expiry < b.expiry end)
	local bh, sp = db.barHeight or 18, db.spacing or 2
	local shown = 0
	for i, a in ipairs(self.active) do
		if shown >= (db.maxBars or 10) then break end
		shown = shown + 1
		local r = Row(f, shown)
		local rem = a.expiry - now
		r:SetMinMaxValues(0, a.cd)
		r:SetValue(rem)
		local c = db.classColor ~= false and a.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[a.class]
		if c then r:SetStatusBarColor(c.r, c.g, c.b) else r:SetStatusBarColor(S.accent.r, S.accent.g, S.accent.b) end
		r.icon:SetSize(bh, bh)
		r.icon:SetTexture(a.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
		r.icon:SetShown(db.showIcon ~= false)
		local xo = db.showIcon ~= false and bh + 3 or 4
		r.name:ClearAllPoints()
		r.name:SetPoint("LEFT", xo, 0)
		r.name:SetPoint("RIGHT", r.time, "LEFT", -4, 0)
		r.name:SetText(format("%s — %s", a.srcName, a.name))
		r.time:ClearAllPoints()
		r.time:SetPoint("RIGHT", -4, 0)
		r.time:SetText(format("%d:%02d", floor(rem / 60), floor(rem % 60)))
		r:ClearAllPoints()
		local y = -((shown - 1) * (bh + sp))
		if db.growth == "DOWN" then
			r:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
			r:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, y)
		else
			r:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, -y)
			r:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, -y)
		end
		r:SetSize(f:GetWidth(), bh)
		r:Show()
	end
	for i = shown + 1, #f.rows do f.rows[i]:Hide() end
	f:SetSize(db.width or 190, max(1, shown) * (bh + sp))
	-- empty container stays fully hidden (incl. title); only movers reveal it
	local idle = shown == 0 and not S.moversUnlocked
	f:SetAlpha(idle and 0 or (shown > 0 and 1 or 0.4))
	f.title:SetShown(not idle)
	f:EnableMouse(not idle)
end

function RCD:Update()
	self.db = S.db.profile.raidcd
	local f = BarsFrame(self)
	f:SetSize(self.db.width or 190, 120)
	if self.db.enable == false then f:Hide() else f:Show() end
	self:Layout()
end

function RCD:Initialize()
	self.db = S.db.profile.raidcd
	if not CombatLogGetCurrentEventInfo then return end
	BarsFrame(self)
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", "OnCombatLog")
end
