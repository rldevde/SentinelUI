-- ProfCooldowns: tracks long profession cooldowns (transmute, primal cloth,
-- salt shaker, void sphere, icy prism...) per character. A small window
-- (/suipcd, minimap "PC") lists them with remaining time; a chat note fires
-- when a cooldown becomes ready.
local _, ns = ...
local S = ns.S
local L = S.L
local PC = S:NewModule("ProfCooldowns", "profcds")

local format, floor, sort = format, math.floor, table.sort
local CreateFrame = CreateFrame
local GetSpellCooldown = GetSpellCooldown or (C_Spell and C_Spell.GetSpellCooldown)
local GetItemCooldown = GetItemCooldown or (C_Item and C_Item.GetItemCooldown)
local IsSpellKnown = S.IsSpellKnown

-- spellId -> shown name (shared cooldowns collapse to one entry via `key`)
local SPELLS = {
	-- alchemy transmutes share one cooldown
	[28566]="Transmute", [28567]="Transmute", [28568]="Transmute", [28580]="Transmute", [28581]="Transmute",
	[28582]="Transmute", [28583]="Transmute", [28584]="Transmute", [28585]="Transmute", [28586]="Transmute",
	[28587]="Transmute", [28588]="Transmute", [28589]="Transmute", [28590]="Transmute", [28591]="Transmute",
	[29688]="Transmute", [32765]="Transmute", [32766]="Transmute", [42613]="Transmute", [42615]="Transmute",
	-- wrath transmutes
	[53771]="Transmute", [53773]="Transmute", [53774]="Transmute", [53775]="Transmute", [53776]="Transmute",
	[53777]="Transmute", [53779]="Transmute", [53780]="Transmute", [53781]="Transmute", [53782]="Transmute",
	[53783]="Transmute", [53784]="Transmute", [54020]="Transmute", [60346]="Transmute", [60348]="Transmute",
	[60349]="Transmute", [60350]="Transmute", [60354]="Transmute", [60355]="Transmute", [60356]="Transmute",
	[60357]="Transmute", [60365]="Transmute", [60396]="Transmute",
	-- tailoring
	[31371]="Spellcloth", [31372]="Shadowcloth", [31373]="Primal Mooncloth",
	[56001]="Moonshroud", [56002]="Spellweave", [56003]="Ebonweave",
	-- jewelcrafting
	[28028]="Void Sphere", [62242]="Icy Prism", [47280]="Brilliant Glass",
	-- blacksmithing / misc
	[55208]="Titansteel", [16991]="Enchanted Leather", [17187]="Transmute: Arcanite",
}
local ITEMS = {
	[15846] = "Salt Shaker", -- GetItemCooldown works while it sits in the bags
}

local function Store()
	S.private.profcds = S.private.profcds or {}
	S.private.profcds.cds = S.private.profcds.cds or {}
	return S.private.profcds.cds
end

local function TimeLeft(expires)
	local left = (expires or 0) - time()
	if left <= 0 then return nil end
	local d = floor(left / 86400)
	local h = floor((left % 86400) / 3600)
	local m = floor((left % 3600) / 60)
	if d > 0 then return format("%dd %dh", d, h) end
	if h > 0 then return format("%dh %dm", h, m) end
	return format("%dm", math.max(1, m))
end

function PC:Scan(force)
	local nowT = GetTime()
	if not force and self.lastScan and nowT - self.lastScan < 2 then return end
	self.lastScan = nowT
	local cds = Store()
	for id, key in pairs(SPELLS) do
		if IsSpellKnown and IsSpellKnown(id) then
			local start, dur
			if C_Spell and C_Spell.GetSpellCooldown then
				local info = C_Spell.GetSpellCooldown(id)
				if info then start, dur = info.startTime, info.duration end
			elseif GetSpellCooldown then
				start, dur = GetSpellCooldown(id)
			end
			if start and dur and dur > 3600 then
				-- start/dur are GetTime() based; convert the expiry to epoch
				-- so it survives relogs
				local exp = floor(time() + (start + dur) - GetTime() + 0.5)
				if exp > time() then
					local e = cds[key]
					if not e or (e.expires or 0) < exp then
						cds[key] = { expires = exp, spell = id }
					end
					cds[key].ready = nil
				end
			end
		end
	end
	for id, key in pairs(ITEMS) do
		if GetItemCooldown then
			local ok, start, dur = pcall(GetItemCooldown, id)
			if ok and start and dur and dur > 3600 then
				local exp = floor(time() + (start + dur) - GetTime() + 0.5)
				if exp > time() then cds[key] = { expires = exp, item = id } cds[key].ready = nil end
			end
		end
	end
	self:CheckReady()
	if self.frame and self.frame:IsShown() then self:FillRows() end
end

-- localized display name for a stored cooldown entry: the client knows the
-- real spell/item names, use them instead of the english table keys
local function CDName(e, key)
	if e.spell then
		local n = S.GetSpellInfo(e.spell)
		if n then return n end
	end
	if e.item then
		local n = S.GetItemInfo(e.item)
		if n then return n end
	end
	return L[key] or key
end

function PC:CheckReady()
	local cds = Store()
	for key, e in pairs(cds) do
		if e.expires and e.expires <= time() and not e.ready then
			e.ready = true
			S:Print(format(L["%s is ready!"], CDName(e, key)))
		end
	end
end

-- window ----------------------------------------------------------------------
local WIN_W, WIN_H, ROW_H = 300, 260, 24
function PC:BuildFrame()
	if self.frame then return end
	local f = CreateFrame("Frame", "SentinelUIProfCDs", UIParent)
	tinsert(UISpecialFrames, "SentinelUIProfCDs")
	f:SetSize(WIN_W, WIN_H)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	S:CreateBackdrop(f, "Default")
	local title = S:FontString(f, 13, "OUTLINE", S.media.unitFont)
	title:SetPoint("TOP", 0, -10)
	title:SetText(L["Profession Cooldowns"])
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)
	if S.SkinCloseButton then S:SkinCloseButton(close) end
	f.rows = {}
	for i = 1, 8 do
		local r = CreateFrame("Frame", nil, f)
		r:SetSize(WIN_W - 20, ROW_H)
		r:SetPoint("TOP", 0, -34 - (i - 1) * ROW_H)
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(16, 16)
		r.icon:SetPoint("LEFT", 2, 0)
		r.name = S:FontString(r, 11, "OUTLINE", S.media.unitFont)
		r.name:SetPoint("LEFT", 24, 0)
		r.time = S:FontString(r, 11, "OUTLINE", S.media.numberFont)
		r.time:SetPoint("RIGHT", -4, 0)
		f.rows[i] = r
	end
	f:Hide()
	self.frame = f
end

function PC:FillRows()
	local cds = Store()
	local list = {}
	for key, e in pairs(cds) do
		list[#list + 1] = { key = key, e = e }
	end
	sort(list, function(a, b)
		local ar = a.e.ready or (a.e.expires or 0) <= time()
		local br = b.e.ready or (b.e.expires or 0) <= time()
		if ar ~= br then return not ar end -- active cooldowns first
		return (a.e.expires or 0) < (b.e.expires or 0)
	end)
	for i, row in ipairs(self.frame.rows) do
		local d = list[i]
		if d then
			local e, key = d.e, d.key
			local icon
			if e.spell then icon = select(3, S.GetSpellInfo(e.spell)) end
			if e.item and C_Item and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(e.item) or icon end
			row.icon:SetTexture(icon or 134400)
			row.name:SetText(CDName(e, key))
			local tl = TimeLeft(e.expires)
			if tl then
				row.time:SetText(tl)
				row.time:SetTextColor(1, 0.82, 0)
			else
				row.time:SetText(L["Ready"])
				row.time:SetTextColor(0.3, 0.9, 0.3)
			end
			row:Show()
		else
			row:Hide()
		end
	end
end

function PC:Toggle()
	self:BuildFrame()
	if self.frame:IsShown() then self.frame:Hide() else self:Scan(true) self.frame:Show() end
end

function PC:UpdateMinimap()
	if not self.minimapBtn then
		self.private = self.private or {}
		self.private.minimap = self.private.minimap or {}
		self.minimapBtn = S:CreateMinimapButton({
			name = "profcds", glyph = "PC", store = self.private.minimap,
			onLeft = function() PC:Toggle() end,
			tooltip = function(b)
				GameTooltip:AddLine("SentinelUI " .. (L["Profession Cooldowns"] or "Profession Cooldowns"), S.accent.r, S.accent.g, S.accent.b)
				local cds = Store()
				for key, e in pairs(cds) do
					GameTooltip:AddLine(CDName(e, key) .. ": " .. (TimeLeft(e.expires) or ("|cff40d040" .. L["Ready"] .. "|r")), 1, 1, 1)
				end
				GameTooltip:AddLine(L["Left click: open"], 0.7, 0.7, 0.7)
			end,
		})
	end
	self.minimapBtn:SetShown(self.db.minimapIcon ~= false)
	self.minimapBtn:UpdatePosition()
end

function PC:Initialize()
	self.db = S.db.profile.profcds
	self.private = S.private.profcds or {}
	self:RegisterEvent("SPELL_UPDATE_COOLDOWN", function() PC:Scan() end)
	self:RegisterEvent("BAG_UPDATE_COOLDOWN", function() PC:Scan() end)
	C_Timer.After(3, function() PC:Scan(true) end)
	self:UpdateMinimap()
	S:RegisterChatCommand("suipcd", function() PC:Toggle() end)
	S:RegisterChatCommand("pcd", function() PC:Toggle() end)
end

function PC:Update()
	self.db = S.db.profile.profcds
	self:UpdateMinimap()
end
