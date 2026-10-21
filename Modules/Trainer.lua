-- Trainer: replaces the Blizzard ClassTrainerFrame (WhatsTraining-style).
-- Lists every service a trainer offers grouped by state: learnable now
-- (green, with cost), too early (grey, with required level) and already
-- learned (dimmed). Live data comes from the trainer API -> works for every
-- class/race automatically. A per-class cache makes the last list viewable
-- away from the trainer (/sui trainer or the options button).
local _, ns = ...
local S = ns.S
local L = S.L
local TR = S:NewModule("Trainer")

local _G = _G
local ipairs, pairs, sort, wipe = ipairs, pairs, sort, wipe
local tinsert, tremove = tinsert, table.remove
local format, floor, max = format, floor, math.max
local select, strmatch, tostring = select, strmatch, tostring
local unpack = unpack
local CreateFrame, GetTime = CreateFrame, GetTime
local GetMoney, UnitLevel, GetSpellInfo = GetMoney, UnitLevel, S.GetSpellInfo
local type = type
local IsSecret = S.IsSecret

local ICON_BOOK = [[Interface\Icons\INV_Misc_Book_09]]
local ICON_TAB = [[Interface\Icons\Spell_Holy_GreaterHeal]] -- bright "teaching" icon
local ROW_H = 24
local MAX_ROWS = 14

TR.services = {} -- live scan result: { state, name, rank, icon, cost, reqLevel, idx, spellID, header }
TR.filter = { available = true, unavailable = true, used = false }
TR.scroll = 0
TR.selected = nil

local function MoneyStr(copper)
	copper = floor(copper or 0)
	local g, s, c = floor(copper / 10000), floor((copper % 10000) / 100), copper % 100
	if g > 0 then return format("%dg %ds %dc", g, s, c) end
	if s > 0 then return format("%ds %dc", s, c) end
	return format("%dc", c)
end

-- class trainer data per class survives reloads so the window can show the
-- last seen list away from any trainer
local function Cache()
	local g = S.db.global
	g.trainerCache = g.trainerCache or {}
	local _, class = UnitClass("player")
	g.trainerCache[class or "UNKNOWN"] = g.trainerCache[class or "UNKNOWN"] or {}
	return g.trainerCache[class or "UNKNOWN"]
end

-- trainer API wrappers (all defensive: some builds lack pieces)
local function NumServices()
	local ok, n = pcall(GetNumTrainerServices)
	return ok and n or 0
end

local function ServiceInfo(i)
	local ok, name, sub, stype, expanded = pcall(GetTrainerServiceInfo, i)
	if not ok then return end
	return name, sub, stype, expanded
end

local function ServiceIcon(i)
	local ok, icon = pcall(GetTrainerServiceIcon, i)
	return ok and icon or nil
end

local function ServiceCost(i)
	local ok, c = pcall(GetTrainerServiceCost, i)
	return ok and c or 0
end

local function ServiceReqLevel(i)
	if not GetTrainerServiceLevelReq then return nil end
	local ok, lvl = pcall(GetTrainerServiceLevelReq, i)
	return ok and lvl or nil
end

local function ServiceLink(i)
	if not GetTrainerServiceItemLink then return nil end
	local ok, link = pcall(GetTrainerServiceItemLink, i)
	return ok and link or nil
end

local function IsLearnable(i)
	if not IsTrainerServiceLearnable then return nil end
	local ok, learnable = pcall(IsTrainerServiceLearnable, i)
	return ok and learnable or nil
end

local function KnownByPlayer(spellID)
	if not spellID or IsSecret(spellID) then return nil end
	if IsPlayerSpell and IsPlayerSpell(spellID) then return true end
	if IsSpellKnown and IsSpellKnown(spellID) then return true end
	return nil
end

-- pet spellbook check (hunter pet abilities, warlock grimoire spells):
-- IsSpellKnown(id, true) queries the summoned pet/demon spellbook
local function KnownByPet(spellID)
	if not spellID or IsSecret(spellID) or not IsSpellKnown then return nil end
	if not HasPetUI or not HasPetUI() then return nil end
	if IsSpellKnown(spellID, true) then return true end
	return nil
end

local function ParseSpellID(link)
	if not link then return nil end
	local id = strmatch(link, "spell:(%d+)") or strmatch(link, "enchant:(%d+)") or strmatch(link, "item:(%d+)")
	return id and tonumber(id) or nil
end

-- expand everything so "used"/"unavailable" rows are part of the scan
local function ExpandAll()
	if not ExpandTrainerSkillLine then return end
	for pass = 1, 3 do
		local changed
		for i = 1, NumServices() do
			local _, _, stype, expanded = ServiceInfo(i)
			if stype == "header" and expanded == false then
				pcall(ExpandTrainerSkillLine, i)
				changed = true
			end
		end
		if not changed then break end
	end
end

function TR:Scan(caching)
	wipe(self.services)
	-- unfiltered view: Blizzard defaults hide "used" entries on some trainers
	if SetTrainerServiceTypeFilter then
		pcall(SetTrainerServiceTypeFilter, "available", 1)
		pcall(SetTrainerServiceTypeFilter, "unavailable", 1)
		pcall(SetTrainerServiceTypeFilter, "used", 1)
	end
	ExpandAll()
	local n = NumServices()
	for i = 1, n do
		local name, sub, stype = ServiceInfo(i)
		if not name then break end
		if stype == "header" then
			self.services[#self.services + 1] = { header = true, name = name }
		else
			local learnable = IsLearnable(i)
			-- IsTrainerServiceLearnable is the authoritative "can buy now"
			-- signal; trust it over the type string, which differs between
			-- client builds
			local state
			if stype == "used" then state = "used"
			elseif stype == "available" or learnable == true then state = "available"
			else state = "unavailable" end
			self.services[#self.services + 1] = {
				idx = i, state = state,
				name = name, rank = sub,
				icon = ServiceIcon(i), cost = ServiceCost(i),
				reqLevel = ServiceReqLevel(i),
				spellID = ParseSpellID(ServiceLink(i)),
				learnable = learnable,
			}
		end
	end
	if caching ~= false then
		local c = Cache()
		c.at = time()
		c.list = self.services
		if GetTrainerGreetingText then c.greeting = GetTrainerGreetingText() end
	end
end

-- Static class data (WhatsTraining-style): the full spell list for the
-- player's class, including spells nobody ever visited a trainer for.
-- Known state is re-checked live; overridden rank chains mark lower ranks
-- learned when a higher rank is known.
local knownCache = {}
local function DataKnown(id)
	if knownCache[id] == nil then
		knownCache[id] = KnownByPlayer(id) == true
	end
	return knownCache[id]
end

local function OverriddenKnown(spellID)
	local data = ns.WTData
	local chain = data and data.overriddenSpellsMap and data.overriddenSpellsMap[spellID]
	if not chain then return false end
	local mine, highest = 0, 0
	for i, other in ipairs(chain) do
		if other == spellID then mine = i end
		if DataKnown(other) then highest = i end
	end
	return mine > 0 and mine <= highest
end

function TR:StaticServices()
	local data = ns.WTData
	if not data then return {} end
	wipe(knownCache)
	local playerLevel = UnitLevel("player") or 0
	local out = {}

	local function addSpell(sp, level, tome)
		local spellID = tome and sp.taughtSpell or sp.id
		if type(spellID) ~= "number" then return end
		local okInfo, name, rank, icon = pcall(GetSpellInfo, spellID)
		if not okInfo or not name then return end
		local isPet = tome or (data.PetAbilityIds and data.PetAbilityIds[spellID]) or nil
		local learned = DataKnown(spellID) or OverriddenKnown(spellID)
			or (isPet and KnownByPet(spellID) == true)
		local prereqs = true
		if sp.requiredIds then
			for _, req in ipairs(sp.requiredIds) do
				if not (DataKnown(req) or OverriddenKnown(req)) then
					prereqs = false
					break
				end
			end
		end
		if sp.requiredTalentId and not DataKnown(sp.requiredTalentId) then
			prereqs = false
		end
		out[#out + 1] = {
			spellID = spellID,
			name = name,
			rank = rank,
			icon = (tome and sp.altIcon) or icon,
			cost = sp.cost or 0,
			reqLevel = level or 0,
			state = learned and "used" or ((level or 0) <= playerLevel and "available" or "unavailable"),
			learnable = prereqs,
			tome = tome or nil,
			pet = isPet,
		}
	end

	for level, spells in pairs(data.SpellsByLevel or {}) do
		for _, sp in ipairs(spells) do
			addSpell(sp, level, false)
		end
	end
	for level, tomes in pairs(data.TomesByLevel or {}) do
		for _, t in ipairs(tomes) do
			addSpell(t, level, true)
		end
	end
	sort(out, function(a, b)
		if (a.reqLevel or 0) ~= (b.reqLevel or 0) then return (a.reqLevel or 0) < (b.reqLevel or 0) end
		if (a.name or "") == (b.name or "") then return (a.rank or "") < (b.rank or "") end
		return (a.name or "") < (b.name or "")
	end)
	return out
end

-- Merge live trainer data into the static list (by spellID): real costs and
-- the trainer's own availability state win when we are at a trainer.
local function MergeLive(staticList)
	local live = {}
	for _, svc in ipairs(TR.services) do
		if not svc.header and svc.spellID then live[svc.spellID] = svc end
	end
	for _, svc in ipairs(staticList) do
		local l = svc.spellID and live[svc.spellID]
		if l then
			if l.state == "used" then
				svc.state = "used"
			elseif svc.state ~= "used" then
				svc.state = l.state
				if l.cost and l.cost > 0 then svc.cost = l.cost end
				if l.learnable ~= nil then svc.learnable = l.learnable end
			end
		end
	end
	return staticList
end

-- the styled border lives on the suiBackdrop child frame, not on the row itself
local function SetRowBorder(r, ...)
	local bd = r.suiBackdrop or r
	if bd.SetBackdropBorderColor then bd:SetBackdropBorderColor(...) end
end

-- view ----------------------------------------------------------------
local function RowBtn(f, i)
	local r = f.rows[i]
	if not r then
		r = CreateFrame("Button", nil, f.list)
		r:SetHeight(ROW_H)
		S:CreateBackdrop(r, "Default")
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(18, 18)
		r.icon:SetPoint("LEFT", 5, 0)
		r.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
		r.name = S:FontString(r, 11, "OUTLINE", S.media.unitFont, nil, "LEFT")
		r.name:SetPoint("LEFT", r.icon, "RIGHT", 7, 0)
		r.right = S:FontString(r, 10, "OUTLINE", S.media.numberFont, nil, "RIGHT")
		r.right:SetPoint("RIGHT", -6, 0)
		r:SetScript("OnEnter", function(s2)
			SetRowBorder(s2, S.accent.r, S.accent.g, S.accent.b, 1)
			local svc = s2.svc
			if svc and svc.spellID and GameTooltip then
				GameTooltip:SetOwner(s2, "ANCHOR_RIGHT")
				local ok = pcall(GameTooltip.SetSpellByID, GameTooltip, svc.spellID)
				if not ok then GameTooltip:SetText(svc.name) end
				GameTooltip:Show()
			end
		end)
		r:SetScript("OnLeave", function(s2)
			SetRowBorder(s2, unpack(S.media.borderColor))
			if GameTooltip then GameTooltip:Hide() end
		end)
		r:SetScript("OnClick", function(s2)
			if s2.svc and not s2.svc.header then TR:Select(s2.svc) end
		end)
		f.rows[i] = r
	end
	return r
end

local function StateColor(svc)
	if svc.state == "available" then
		local afford = (svc.cost or 0) <= (GetMoney() or 0)
		if svc.learnable == false or not afford then return 0.9, 0.5, 0.1 end -- orange: learnable but broke
		return 0.25, 0.85, 0.4 -- green: trainable now
	end
	if svc.state == "used" then return 0.45, 0.45, 0.5 end
	return 0.65, 0.65, 0.7 -- unavailable
end

function TR:Select(svc)
	self.selected = svc
	local f = self.frame
	if not f then return end
	f.detailName:SetText(svc.name .. (svc.rank and svc.rank ~= "" and ("  |cff888888(" .. svc.rank .. ")|r") or ""))
	local bits = {}
	if svc.reqLevel then bits[#bits + 1] = format(L["Requires level %d"], svc.reqLevel) end
	if svc.cost and svc.cost > 0 then bits[#bits + 1] = L["Cost"] .. ": " .. MoneyStr(svc.cost) end
	if svc.state == "used" then bits[#bits + 1] = L["Already learned"] end
	f.detailInfo:SetText(#bits > 0 and table.concat(bits, "   |   ") or "")
	-- a live service index only exists during a real trainer session;
	-- don't trust the atTrainer flag (it can desync when the window was
	-- opened offline or the session flag was lost)
	local canBuy = svc.idx and (svc.state == "available" or svc.learnable == true) and NumServices() > 0
	f.learnBtn:SetEnabled(canBuy and true or false)
	f.learnBtn:SetAlpha(canBuy and 1 or 0.4)
	self:Layout()
end

function TR:Layout()
	local f = self.frame
	if not f or not f:IsShown() then return end
	local vis = {}
	for _, svc in ipairs(self.services) do
		if svc.header or self.filter[svc.state] then vis[#vis + 1] = svc end
	end
	local nVis = #vis
	if nVis == 0 and self.atTrainer then
		f.status:SetText("|cffff8060" .. L["No data yet - visit a trainer first"] .. "|r")
	elseif self.atTrainer then
		f.status:SetText("")
	end
	local maxOff = max(0, nVis - MAX_ROWS)
	if self.scroll > maxOff then self.scroll = maxOff end
	if self.scroll < 0 then self.scroll = 0 end
	for i = 1, MAX_ROWS do
		local svc = vis[i + self.scroll]
		local r = RowBtn(f, i)
		if svc then
			r.svc = svc
			if svc.header then
				r.icon:SetTexture(nil)
				r.name:SetText("|cff" .. S.accentHex .. svc.name .. "|r")
				r.right:SetText("")
				r:EnableMouse(false)
			else
				r.icon:SetTexture(svc.icon or ICON_BOOK)
				local label = svc.name
				if svc.rank and svc.rank ~= "" then label = label .. "  |cff7f7f8a" .. svc.rank .. "|r" end
				local cr, cg, cb = StateColor(svc)
				-- offline view: recheck learned state via the spellbook
				if not self.atTrainer and svc.spellID and KnownByPlayer(svc.spellID) == true then
					cr, cg, cb = 0.45, 0.45, 0.5
					svc.state = "used"
				end
				r.name:SetText(label)
				r.name:SetTextColor(cr, cg, cb)
				local rt = ""
				if svc.state == "available" then
					rt = svc.cost and svc.cost > 0 and MoneyStr(svc.cost) or L["Free"]
				elseif svc.state == "unavailable" and svc.reqLevel then
					rt = format(L["Lvl %d"], svc.reqLevel)
				elseif svc.state == "used" then
					rt = "|cff55aa55✓|r"
				end
				r.right:SetText(rt)
				r:EnableMouse(true)
			end
			if svc == self.selected then
				SetRowBorder(r, S.accent.r, S.accent.g, S.accent.b, 1)
			else
				SetRowBorder(r, unpack(S.media.borderColor))
			end
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", f.list, "TOPLEFT", 0, -((i - 1) * (ROW_H + 2)))
			r:SetPoint("RIGHT", f.list, "RIGHT", 0, 0)
			r:Show()
		else
			r:Hide()
			r.svc = nil
		end
	end
	-- summary + train-all button
	local avail, cost, early = 0, 0, {}
	for _, svc in ipairs(self.services) do
		if svc.state == "available" or svc.learnable == true then
			avail = avail + 1
			cost = cost + (svc.cost or 0)
		elseif svc.state == "unavailable" and svc.reqLevel then
			early[#early + 1] = svc.reqLevel
		end
	end
	if #early > 0 then
		sort(early)
		f.summary:SetText(format(L["%d available (%s)  —  next unlock: level %d"], avail, MoneyStr(cost), early[1]))
	else
		f.summary:SetText(format(L["%d available (%s)"], avail, MoneyStr(cost)))
	end
	local canAll = NumServices() > 0 and avail > 0 and cost <= (GetMoney() or 0)
	f.learnAllBtn:SetEnabled(canAll and true or false)
	f.learnAllBtn:SetAlpha(canAll and 1 or 0.4)
	f.learnAllBtn.label:SetText(L["Train all"] .. " (" .. MoneyStr(cost) .. ")")
end

local function MakeCheck(parent, label, key)
	local cb = CreateFrame("CheckButton", nil, parent)
	cb:SetSize(16, 16)
	S:CreateBackdrop(cb, "Default")
	cb.check = cb:CreateTexture(nil, "OVERLAY")
	cb.check:SetTexture(S.media.blank)
	cb.check:SetVertexColor(S.accent.r, S.accent.g, S.accent.b)
	cb.check:SetPoint("TOPLEFT", 3, -3)
	cb.check:SetPoint("BOTTOMRIGHT", -3, 3)
	cb.fs = S:FontString(cb, 10, "OUTLINE", S.media.unitFont, nil, "LEFT")
	cb.fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
	cb.fs:SetText(label)
	cb:SetScript("OnClick", function(s2)
		TR.filter[key] = not TR.filter[key]
		s2.check:SetShown(TR.filter[key])
		TR:Layout()
	end)
	cb.check:SetShown(TR.filter[key])
	return cb
end

function TR:BuildFrame()
	if self.frame then return self.frame end
	local f = CreateFrame("Frame", "SentinelUITrainer", UIParent)
	f:SetSize(340, 470)
	f:SetPoint("CENTER", UIParent, "CENTER", 180, 40)
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	S:SetTemplate(f, "Transparent", "TOP")
	f:Hide()

	f.logo = f:CreateTexture(nil, "OVERLAY")
	f.logo:SetSize(16, 16)
	f.logo:SetPoint("TOPLEFT", 8, -6)
	f.logo:SetTexture(ICON_BOOK)
	f.logo:SetVertexColor(S.accent.r, S.accent.g, S.accent.b)

	f.title = S:FontString(f, 12, "OUTLINE", S.media.unitFont, nil, "LEFT")
	f.title:SetPoint("LEFT", f.logo, "RIGHT", 6, 0)
	f.title:SetText(L["Trainer"])
	S:RegisterAccent(f.title, "text")

	f.close = CreateFrame("Button", nil, f)
	f.close:SetSize(16, 16)
	f.close:SetPoint("TOPRIGHT", -7, -6)
	S:CreateBackdrop(f.close, "Default")
	f.close.fs = S:FontString(f.close, 12, "OUTLINE", S.media.numberFont, nil, "CENTER")
	f.close.fs:SetPoint("CENTER")
	f.close.fs:SetText("x")
	f.close:SetScript("OnClick", function() TR:Close() end)

	-- greeting line
	f.greeting = S:FontString(f, 10, "OUTLINE", S.media.font, nil, "LEFT")
	f.greeting:SetPoint("TOPLEFT", 10, -28)
	f.greeting:SetPoint("RIGHT", -10, 0)
	f.greeting:SetTextColor(0.7, 0.7, 0.75)

	-- filter row
	local cb1 = MakeCheck(f, L["Available"], "available")
	cb1:SetPoint("TOPLEFT", 10, -46)
	local cb2 = MakeCheck(f, L["Unavailable"], "unavailable")
	cb2:SetPoint("TOPLEFT", 120, -46)
	local cb3 = MakeCheck(f, L["Learned"], "used")
	cb3:SetPoint("TOPLEFT", 235, -46)

	-- list
	f.list = CreateFrame("Frame", nil, f)
	f.list:SetPoint("TOPLEFT", 8, -68)
	f.list:SetPoint("BOTTOMRIGHT", -8, 66)
	f.list:EnableMouse(true)
	f.list:EnableMouseWheel(true)
	f.list:SetScript("OnMouseWheel", function(_, delta)
		TR.scroll = TR.scroll - delta
		TR:Layout()
	end)
	f.rows = {}

	-- detail footer
	f.detailName = S:FontString(f, 11, "OUTLINE", S.media.unitFont, nil, "LEFT")
	f.detailName:SetPoint("BOTTOMLEFT", 10, 42)
	f.detailName:SetPoint("RIGHT", -170, 0)
	f.detailInfo = S:FontString(f, 10, "OUTLINE", S.media.numberFont, nil, "LEFT")
	f.detailInfo:SetPoint("BOTTOMLEFT", 10, 26)
	f.detailInfo:SetPoint("RIGHT", -170, 0)
	f.detailInfo:SetTextColor(0.65, 0.65, 0.7)

	local function FootBtn(w, label, onClick)
		local b = CreateFrame("Button", nil, f)
		b:SetSize(w, 20)
		S:SkinButton(b)
		b.label = S:FontString(b, 10, "OUTLINE", S.media.numberFont, nil, "CENTER")
		b.label:SetPoint("CENTER")
		b.label:SetText(label)
		b:SetScript("OnClick", onClick)
		return b
	end
	f.learnBtn = FootBtn(70, L["Train"], function()
		local svc = TR.selected
		if svc and svc.idx then
			S:SafeCall("Trainer:Buy", BuyTrainerService, svc.idx)
			C_Timer.After(0.2, function() TR:Scan() TR:Layout() end)
		end
	end)
	f.learnBtn:SetPoint("BOTTOMRIGHT", -8, 34)
	f.learnAllBtn = FootBtn(140, L["Train all"], function()
		S:SafeCall("Trainer:BuyAll", function()
			for _, svc in ipairs(TR.services) do
				if (svc.state == "available" or svc.learnable == true) and svc.idx then pcall(BuyTrainerService, svc.idx) end
			end
		end)
		C_Timer.After(0.3, function() TR:Scan() TR:Layout() end)
	end)
	f.learnAllBtn:SetPoint("BOTTOMRIGHT", -8, 10)

	f.summary = S:FontString(f, 10, "OUTLINE", S.media.numberFont, nil, "LEFT")
	f.summary:SetPoint("BOTTOMLEFT", 10, 10)
	f.summary:SetPoint("RIGHT", f.learnAllBtn, "LEFT", -6, 0)
	f.summary:SetTextColor(0.65, 0.65, 0.7)

	f.status = S:FontString(f, 9, "OUTLINE", S.media.font, nil, "RIGHT")
	f.status:SetPoint("BOTTOMRIGHT", f.list, "TOPRIGHT", 0, 2)
	f.status:SetTextColor(0.5, 0.5, 0.55)

	self.frame = f
	tinsert(UISpecialFrames, "SentinelUITrainer")
	return f
end

function TR:Open(atTrainer)
	self.atTrainer = atTrainer
	local f = self:BuildFrame()
	if atTrainer then
		f.greeting:SetText((GetTrainerGreetingText and GetTrainerGreetingText()) or "")
		f.status:SetText("")
	else
		-- static class data always fills the list; the trainer cache only adds
		-- the "last visit" line and is the fallback if data is missing
		self.services = self:StaticServices()
		local c = Cache()
		if #self.services == 0 then self.services = c.list or {} end
		f.greeting:SetText(c.greeting or "")
		f.status:SetText(c.at and (L["Last trainer visit"] .. ": " .. date("%d.%m %H:%M", c.at)) or "")
		self.selected = nil
	end
	f:Show()
	self:Layout()
end

function TR:Close()
	if self.frame then self.frame:Hide() end
	-- the Blizzard trainer owns the live session now; closing our overview
	-- window must not kill it
end

-- Blizzard's trainer stays in charge of learning (already reskinned via
-- Modules/Skins.lua) — we only snapshot the session for the spellbook
-- overview and the /sui trainer offline list
function TR:OnShow()
	if self.db and self.db.enable == false then return end
	self.atTrainer = true
	S:SafeCall("Trainer:Scan", function() self:Scan() end)
	-- the service list can still be empty at TRAINER_SHOW on some builds;
	-- rescan once the session data has settled
	C_Timer.After(0.1, function()
		if TR.atTrainer and #TR.services == 0 then
			S:SafeCall("Trainer:Rescan", function() TR:Scan(false) end)
		end
	end)
	-- first interaction can fire before the Blizzard trainer window is fully
	-- up; make sure it is actually shown and populated on the first click
	for _, delay in ipairs({ 0, 0.3 }) do
		C_Timer.After(delay, function()
			if not TR.atTrainer then return end
			local ctf = _G.ClassTrainerFrame
			if not ctf then return end
			S:SafeCall("Trainer:EnsureShown", function()
				if not ctf:IsShown() then pcall(ShowUIPanel, ctf) end
				if ClassTrainerFrame_Update then pcall(ClassTrainerFrame_Update) end
			end)
		end)
	end
	S:LogInfo("trainer", format("seen: api=%d live=%d static=%d", NumServices(), #self.services, #self:StaticServices()))
end

function TR:OnUpdate()
	if self.atTrainer then
		self:Scan(false) -- keep the spellbook/cache snapshot fresh
		if self.frame and self.frame:IsShown() then self:Layout() end
	end
end

function TR:OnClosed()
	self.atTrainer = false
	if self.frame then self.frame:Hide() end
end

function TR:Update()
	self.db = S.db.profile.trainer
end

-- WhatsTraining-style spellbook integration: a side tab on the right edge
-- (like the class/skill tabs) that swaps the book content to an overlay page
-- listing every trainer spell grouped by required level.
local BOOK_ROWS = 14
local BOOK_ROW_H = 21

local function BookRow(ov, i)
	local r = ov.rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, ov)
	r:SetHeight(BOOK_ROW_H)
	-- no per-row frame: rows sit flat on the page like native spell entries,
	-- feedback comes from a highlight texture instead of a box border
	local hl = r:CreateTexture(nil, "HIGHLIGHT")
	hl:SetTexture([[Interface\Buttons\ButtonHilight-Square]])
	hl:SetBlendMode("ADD")
	hl:SetAllPoints()
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(16, 16)
	r.icon:SetPoint("LEFT", 5, 0)
	r.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
	r.name = S:FontString(r, 10, "OUTLINE", S.media.unitFont, nil, "LEFT")
	r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
	r.name:SetPoint("RIGHT", r, "RIGHT", -70, 0)
	r.name:SetWordWrap(false)
	r.right = S:FontString(r, 9, "OUTLINE", S.media.numberFont, nil, "RIGHT")
	r.right:SetPoint("RIGHT", -5, 0)
	-- real check icon: the font has no ✓ glyph (renders as tofu boxes)
	r.check = r:CreateTexture(nil, "ARTWORK")
	r.check:SetSize(11, 11)
	r.check:SetPoint("RIGHT", -5, 0)
	r.check:SetTexture([[Interface\RaidFrame\ReadyCheck-Ready]])
	r.check:Hide()
	r:SetScript("OnEnter", function(s2)
		local svc = s2.svc
		if svc and svc.spellID and GameTooltip then
			GameTooltip:SetOwner(s2, "ANCHOR_LEFT")
			local ok = pcall(GameTooltip.SetSpellByID, GameTooltip, svc.spellID)
			if not ok then GameTooltip:SetText(svc.name) end
			GameTooltip:Show()
		end
	end)
	r:SetScript("OnLeave", function()
		if GameTooltip then GameTooltip:Hide() end
	end)
	ov.rows[i] = r
	return r
end

-- overlay content: available first, then per-level groups, learned last
local function BookLayout(ov)
	local list = ov.list or {}
	wipe(list)
	-- static class data is the base; live trainer state is merged on top
	local src = MergeLive(TR:StaticServices())
	if #src == 0 then src = TR.atTrainer and TR.services or (Cache().list or {}) end
	local avail, byLevel, learned = {}, {}, {}
	for _, svc in ipairs(src) do
		if not svc.header then
			if svc.state == "available" then avail[#avail + 1] = svc
			elseif svc.state == "used" then learned[#learned + 1] = svc
			else
				local lvl = svc.reqLevel or 0
				byLevel[lvl] = byLevel[lvl] or {}
				tinsert(byLevel[lvl], svc)
			end
		end
	end
	if #avail > 0 then
		tinsert(list, { header = L["Available now"], acc = true })
		for _, s2 in ipairs(avail) do tinsert(list, s2) end
	end
	local lvls = {}
	for lvl in pairs(byLevel) do lvls[#lvls + 1] = lvl end
	sort(lvls)
	for _, lvl in ipairs(lvls) do
		tinsert(list, { header = format(L["Level %d"], lvl) })
		for _, s2 in ipairs(byLevel[lvl]) do tinsert(list, s2) end
	end
	if #learned > 0 then
		tinsert(list, { header = L["Already learned"], dim = true })
		for _, s2 in ipairs(learned) do tinsert(list, s2) end
	end
	ov.list = list
	local n = #list
	if ov.scroll > n - BOOK_ROWS then ov.scroll = max(0, n - BOOK_ROWS) end
	if ov.scroll < 0 then ov.scroll = 0 end
	for i = 1, BOOK_ROWS do
		local svc = list[i + ov.scroll]
		local r = BookRow(ov, i)
		if svc then
			r.svc = svc.header and nil or svc
			if svc.header then
				r.icon:SetTexture(nil)
				r.name:SetText(svc.header)
				if svc.acc then r.name:SetTextColor(S.accent.r, S.accent.g, S.accent.b)
				elseif svc.dim then r.name:SetTextColor(0.45, 0.45, 0.5)
				else r.name:SetTextColor(1, 0.85, 0.3) end
				r.right:SetText("")
				r.check:Hide()
				r:EnableMouse(false)
			else
				r.icon:SetTexture(svc.icon or ICON_BOOK)
				local nm = svc.name .. (svc.rank and svc.rank ~= "" and ("  |cff7f7f8a" .. svc.rank .. "|r") or "")
				if svc.pet then nm = nm .. "  |cff88bbdd[" .. L["Pet"] .. "]|r" end
				r.name:SetText(nm)
				local st = svc.state
				if st == "available" then r.name:SetTextColor(0.25, 0.85, 0.4)
				elseif st == "used" then r.name:SetTextColor(0.5, 0.5, 0.55)
				else r.name:SetTextColor(0.75, 0.75, 0.8) end
				local rt = ""
				if st ~= "used" then
					if svc.cost and svc.cost > 0 then
						rt = MoneyStr(svc.cost)
					elseif st == "available" then
						rt = L["Free"]
					end
				end
				r.right:SetText(rt)
				if st == "unavailable" then r.right:SetTextColor(0.55, 0.55, 0.6)
				else r.right:SetTextColor(1, 0.82, 0.2) end
				r.check:SetShown(st == "used")
				r:EnableMouse(true)
			end
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", ov.listArea, "TOPLEFT", 0, -((i - 1) * (BOOK_ROW_H + 2)))
			r:SetPoint("RIGHT", ov.listArea, "RIGHT", 0, 0)
			r:Show()
		else
			r:Hide()
			r.svc = nil
		end
	end
	ov.empty:SetShown(n == 0)
end

local function HookSpellBook()
	local sb = _G.SpellBookFrame
	if not sb or sb.suiTrainerTab then return end

	-- in-book overlay page: covers the spell area but stays borderless so it
	-- reads as book content, not a window inside a window
	local ov = CreateFrame("Frame", "SentinelUITrainerBook", sb)
	ov:SetPoint("TOPLEFT", sb, "TOPLEFT", 30, -26)
	ov:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", -2, 88)
	local ovb = S:CreateBackdrop(ov, "Default", nil, 0)
	if ovb and ovb.SetBackdropBorderColor then ovb:SetBackdropBorderColor(0, 0, 0, 0) end
	ov:SetFrameLevel(sb:GetFrameLevel() + 8)
	ov:EnableMouse(true)
	ov.scroll = 0
	ov.rows = {}
	ov:Hide()
	sb.suiTrainerOverlay = ov

	ov.head = S:FontString(ov, 11, "OUTLINE", S.media.unitFont, nil, "LEFT")
	ov.head:SetPoint("TOPLEFT", 8, -6)
	ov.head:SetText(L["Trainer"])
	S:RegisterAccent(ov.head, "text")
	ov.refresh = S:FontString(ov, 9, "OUTLINE", S.media.font, nil, "RIGHT")
	ov.refresh:SetPoint("TOPRIGHT", -8, -7)
	ov.refresh:SetTextColor(0.5, 0.5, 0.55)

	ov.listArea = CreateFrame("Frame", nil, ov)
	ov.listArea:SetPoint("TOPLEFT", 6, -24)
	ov.listArea:SetPoint("BOTTOMRIGHT", -6, 6)
	ov.listArea:EnableMouseWheel(true)
	ov.listArea:SetScript("OnMouseWheel", function(_, delta)
		ov.scroll = ov.scroll - delta * 3
		BookLayout(ov)
	end)

	ov.empty = S:FontString(ov, 10, "OUTLINE", S.media.font, nil, "CENTER")
	ov.empty:SetPoint("CENTER", ov.listArea, "CENTER")
	ov.empty:SetText(L["No data yet - visit a trainer first"])
	ov.empty:SetTextColor(0.55, 0.55, 0.6)

	ov:SetScript("OnShow", function()
		if TR.atTrainer then TR:Scan() end
		local c = Cache()
		ov.refresh:SetText(c.at and (L["Last trainer visit"] .. ": " .. date("%d.%m %H:%M", c.at)) or "")
		BookLayout(ov)
	end)
	ov:SetScript("OnHide", function()
		if sb.suiTrainerTab then sb.suiTrainerTab:SetChecked(false) end
	end)

	-- side tab: sits on the right edge with the other skill-line tabs.
	-- Same look as Blizzard skill tabs: the icon IS the button (normal texture),
	-- a checked glow when the overlay is open.
	local tab = CreateFrame("CheckButton", "SentinelUITrainerBookTab", sb)
	tab:SetSize(32, 32)
	local lastTab
	for i = 1, 16 do
		local t = _G["SpellBookSkillLineTab" .. i]
		if t then lastTab = t end
	end
	if lastTab then
		tab:SetPoint("TOPLEFT", lastTab, "BOTTOMLEFT", 0, -17)
	else
		tab:SetPoint("TOPRIGHT", sb, "TOPRIGHT", 30, -150)
	end
	tab:SetFrameLevel(sb:GetFrameLevel() + 9)
	tab:SetNormalTexture(ICON_TAB)
	tab:SetHighlightTexture([[Interface\Buttons\ButtonHilight-Square]], "ADD")
	local chk = tab:CreateTexture(nil, "OVERLAY")
	chk:SetTexture([[Interface\Buttons\CheckButtonHilight]])
	chk:SetBlendMode("ADD")
	chk:SetAllPoints()
	tab:SetCheckedTexture(chk)
	tab:SetScript("OnEnter", function(s2)
		if not GameTooltip then return end
		GameTooltip:SetOwner(s2, "ANCHOR_LEFT")
		GameTooltip:AddLine(L["Trainer"])
		GameTooltip:AddLine(L["Shows the spells your class trainer teaches"], 1, 1, 1)
		GameTooltip:Show()
	end)
	tab:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	tab:SetScript("OnClick", function(s2)
		if ov:IsShown() then
			ov:Hide()
			s2:SetChecked(false)
		else
			ov:Show()
			s2:SetChecked(true)
		end
	end)
	sb.suiTrainerTab = tab

	-- make the spellbook draggable by its title strip (book isn't movable by
	-- default and a fixed overlay page feels stuck without this)
	if not sb.suiTrainerDrag then
		sb:SetMovable(true)
		sb:SetClampedToScreen(true)
		local drag = CreateFrame("Frame", nil, sb)
		drag:SetPoint("TOPLEFT", sb, "TOPLEFT", 8, -2)
		drag:SetPoint("TOPRIGHT", sb, "TOPRIGHT", -34, -2)
		drag:SetHeight(26)
		drag:SetFrameLevel(sb:GetFrameLevel() + 12)
		drag:EnableMouse(true)
		drag:RegisterForDrag("LeftButton")
		drag:SetScript("OnDragStart", function() sb:StartMoving() end)
		drag:SetScript("OnDragStop", function() sb:StopMovingOrSizing() end)
		sb.suiTrainerDrag = drag
	end
end

function TR:Initialize()
	self.db = S.db.profile.trainer
	self:RegisterEvent("TRAINER_SHOW", "OnShow")
	self:RegisterEvent("TRAINER_UPDATE", "OnUpdate")
	self:RegisterEvent("TRAINER_CLOSED", "OnClosed")
	S:RegisterChatCommand("trainer", function() TR:Open(false) end)
	-- SpellBookFrame is part of the base UI on classic; hook again on show in
	-- case something re-parents or the frame loads late
	HookSpellBook()
	if _G.SpellBookFrame then
		self:HookScript(_G.SpellBookFrame, "OnShow", HookSpellBook)
	end
	S:LogInfo("trainer", format("init: static=%d class=%s", #self:StaticServices(), tostring((ns.WTData or {}).currentClass)))
end
