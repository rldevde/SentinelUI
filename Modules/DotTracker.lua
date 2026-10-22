-- Multi-DoT tracker: your harmful auras on every hostile unit we can resolve
-- (target, focus, mouseover, boss/arena/nameplate tokens). Shows icon, spell,
-- target name, stacks and remaining time in a movable bar list.
local _, ns = ...
local S = ns.S
local L = S.L
local DT = S:NewModule("DotTracker")

local _G = _G
local pairs, ipairs, sort, wipe = pairs, ipairs, sort, wipe
local tinsert = tinsert
local format, floor, min, max = format, floor, math.min, math.max
local strsplit, select = strsplit, select
local CreateFrame = CreateFrame
local GetTime = GetTime
local IsSecret = S.IsSecret
local UnitGUID, UnitExists, UnitName = UnitGUID, UnitExists, UnitName

DT.tracked = {} -- guid -> { name = target name, auras = { spellKey -> {icon,name,expiry,stacks} } }

local function ScanUnits()
	local list = { "target", "focus", "mouseover" }
	for i = 1, 5 do list[#list + 1] = "boss" .. i list[#list + 1] = "arena" .. i end
	for i = 1, 40 do list[#list + 1] = "nameplate" .. i end
	return list
end
local unitList = ScanUnits()

function DT:Scan()
	local now = GetTime()
	local seen = {}
	for _, unit in ipairs(unitList) do
		if UnitExists(unit) then
			local guid = UnitGUID(unit)
			if guid and not IsSecret(guid) then
				-- dead mobs keep reporting auras for a while -> drop the entry
				-- immediately instead of letting timers tick on a corpse
				if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then
					self.tracked[guid] = nil
				else
				local entry = self.tracked[guid]
				for i = 1, 40 do
					local a = S.GetAura(unit, i, "HARMFUL|PLAYER")
					if not a then break end
					local key = a.spellId and not IsSecret(a.spellId) and a.spellId or a.name
					if key then
						if not entry then
							local tname = UnitName(unit)
							entry = { name = tname and select(1, strsplit("-", tname)) or "?", auras = {} }
							self.tracked[guid] = entry
						end
						local exp = a.expirationTime
						if IsSecret(exp) or not exp or exp == 0 then exp = nil end
						entry.auras[key] = {
							icon = a.icon, name = a.name or "?",
							expiry = exp, stacks = (not IsSecret(a.applications) and a.applications) or 0,
							seen = now,
						}
						seen[guid] = true
					end
				end
				end
			end
		end
	end
	-- expire ghosts: drop auras that were last seen >2s ago and have no expiry,
	-- and entries whose every aura expired
	for guid, entry in pairs(self.tracked) do
		local empty = true
		for key, a in pairs(entry.auras) do
			if (a.expiry and a.expiry <= now) or (not a.expiry and a.seen and now - a.seen > 2) then
				entry.auras[key] = nil
			else
				empty = false
			end
		end
		if empty then self.tracked[guid] = nil end
	end
end

local function Frame(dt)
	if dt.frame then return dt.frame end
	local db = dt.db
	local f = CreateFrame("Frame", "SentinelUIDotTracker", UIParent, S.BackdropTemplate)
	f:SetSize(db.width or 200, 100)
	f:SetPoint("CENTER", UIParent, "CENTER", -300, 0)
	S:SetTemplate(f, "Transparent")
	f.title = S:FontString(f, 11, "OUTLINE", S.media.unitFont, nil, "LEFT")
	f.title:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 2)
	f.title:SetText(L["DoT Tracker"])
	f.rows = {}
	f:SetScript("OnUpdate", function(_, e)
		f.el = (f.el or 0) + e
		if f.el < 0.25 then return end
		f.el = 0
		dt:Scan()
		dt:Layout()
	end)
	dt.frame = f
	S:CreateMover(f, "dotTracker", L["DoT Tracker"], { "CENTER", "UIParent", "CENTER", -340, 0 }, "general")
	return f
end

local function Row(f, i)
	local r = f.rows[i]
	if not r then
		r = CreateFrame("StatusBar", nil, f)
		r:SetStatusBarTexture(S:Fetch("statusbar", S.db.profile.general.statusbar, "Sentinel"))
		r:SetStatusBarColor(S.accent.r, S.accent.g, S.accent.b)
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

local tmp = {}
function DT:Layout()
	local f, db = self.frame, self.db
	if not f then return end
	local now = GetTime()
	wipe(tmp)
	for guid, entry in pairs(self.tracked) do
		for _, a in pairs(entry.auras) do
			tmp[#tmp + 1] = { tname = entry.name, a = a }
		end
	end
	sort(tmp, function(x, y) return (x.a.expiry or math.huge) < (y.a.expiry or math.huge) end)
	local bh, sp = db.barHeight or 16, db.spacing or 2
	local shown = 0
	for _, it in ipairs(tmp) do
		if shown >= (db.maxBars or 12) then break end
		shown = shown + 1
		local r = Row(f, shown)
		local rem = it.a.expiry and (it.a.expiry - now) or 0
		if it.a.expiry then
			r:SetMinMaxValues(0, 60)
			r:SetValue(min(rem, 60))
		else
			r:SetMinMaxValues(0, 1)
			r:SetValue(1)
		end
		r.icon:SetSize(bh, bh)
		r.icon:SetTexture(it.a.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
		r.icon:SetShown(db.showIcon ~= false)
		local xo = db.showIcon ~= false and bh + 3 or 4
		r.name:ClearAllPoints()
		r.name:SetPoint("LEFT", xo, 0)
		r.name:SetPoint("RIGHT", r.time, "LEFT", -4, 0)
		local stacks = it.a.stacks and it.a.stacks > 1 and format(" (%d)", it.a.stacks) or ""
		r.name:SetText(format("%s%s — %s", it.a.name, stacks, it.tname))
		r.time:ClearAllPoints()
		r.time:SetPoint("RIGHT", -4, 0)
		r.time:SetText(it.a.expiry and format("%.0f", rem) or "")
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
	f:SetSize(db.width or 200, max(1, shown) * (bh + sp))
	-- empty container stays fully hidden (incl. title); only movers reveal it
	local idle = shown == 0 and not S.moversUnlocked
	f:SetAlpha(idle and 0 or (shown > 0 and 1 or 0.4))
	f.title:SetShown(not idle)
	f:EnableMouse(not idle)
end

function DT:Update()
	self.db = S.db.profile.dottracker
	local f = Frame(self)
	if self.db.enable == false then f:Hide() else f:Show() end
	self:Layout()
end

function DT:Initialize()
	self.db = S.db.profile.dottracker
	Frame(self)
end
