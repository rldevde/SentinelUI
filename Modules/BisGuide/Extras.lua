-- BisGuide extra windows: consumables, rotation and talent build browser.
local _, ns = ...
local S = ns.S
local L = S.L
local BG = S:GetModule("BisGuide")

local _G = _G
local ipairs, pairs, tinsert = ipairs, pairs, table.insert
local format, floor = string.format, math.floor
local CreateFrame, C_Timer = CreateFrame, C_Timer

local D -- SUIBisData
local ItemIcon -- from main module

local CLASS_FILE = {
	Druid = "DRUID", Hunter = "HUNTER", Mage = "MAGE", Paladin = "PALADIN", Priest = "PRIEST",
	Rogue = "ROGUE", Shaman = "SHAMAN", Warlock = "WARLOCK", Warrior = "WARRIOR",
}

local function SpecDD(parent, name, label, x, onPick)
	local dd = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
	dd:SetPoint("TOPLEFT", x, -30)
	UIDropDownMenu_SetWidth(dd, 120)
	local fs = S:FontString(parent, 10, "OUTLINE")
	fs:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 20, 2)
	fs:SetText(label)
	fs:SetTextColor(S.accent.r, S.accent.g, S.accent.b)
	dd._onPick = onPick
	return dd
end

local function ClassDDInit(dd, get, set)
	UIDropDownMenu_Initialize(dd, function(_, level)
		for ci in ipairs(D.classes or {}) do
			local info = UIDropDownMenu_CreateInfo()
			local f = CLASS_FILE[D.classes[ci]]
			local c = f and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS or {})[f]
			info.text = (f and LOCALIZED_CLASS_NAMES_MALE[f]) or D.classes[ci]
			if c then info.colorCode = format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) end
			info.func = function() set(ci) end
			info.checked = get() == ci
			UIDropDownMenu_AddButton(info, level)
		end
	end)
end

local function SpecDDInit(dd, getCi, get, set)
	UIDropDownMenu_Initialize(dd, function(_, level)
		for si, sn in ipairs((D.specs or {})[getCi()] or {}) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = BG.SpecName(getCi(), si)
			info.func = function() set(si) end
			info.checked = get() == si
			UIDropDownMenu_AddButton(info, level)
		end
	end)
end

local function BaseWindow(name, title, w, h)
	local f = CreateFrame("Frame", name, UIParent, S.BackdropTemplate)
	f:SetSize(w, h)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	S:CreateBackdrop(f, "Default", "TOP")
	S:EnablePixelSnap(f)
	tinsert(UISpecialFrames, name)
	local t = S:FontString(f, 14, "OUTLINE", S.media.unitFont)
	t:SetPoint("TOP", 0, -8)
	t:SetText("|cff66c2ffSentinelUI|r " .. title)
	local sep = f:CreateTexture(nil, "ARTWORK")
	sep:SetPoint("TOPLEFT", 10, -28)
	sep:SetPoint("TOPRIGHT", -10, -28)
	sep:SetHeight(1)
	sep:SetColorTexture(S.accent.r, S.accent.g, S.accent.b, 0.8)
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)
	S:SkinCloseButton(close)
	f:Hide()
	return f
end

local function SmallIcon(parent, size)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size, size)
	b.tex = b:CreateTexture(nil, "ARTWORK")
	b.tex:SetAllPoints()
	b.tex:SetTexCoord(0.06, 0.94, 0.06, 0.94)
	b:EnableMouse(true)
	return b
end

local function ItemBtnTip(b, iid)
	ItemIcon(iid, function(t) b.tex:SetTexture(t) end)
	b:SetScript("OnEnter", function()
		GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink("item:" .. iid)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:SetScript("OnClick", function()
		if IsShiftKeyDown and IsShiftKeyDown() then
			local _, link = GetItemInfo(iid)
			if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
		end
	end)
end

local function SpellBtnTip(b, sid)
	local tex = GetSpellTexture and GetSpellTexture(sid)
	b.tex:SetTexture(tex or 134400)
	b:SetScript("OnEnter", function()
		GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
		GameTooltip:SetSpellByID(sid)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:SetScript("OnClick", function()
		if IsShiftKeyDown and IsShiftKeyDown() then
			local l = GetSpellLink and GetSpellLink(sid)
			if l and ChatEdit_InsertLink then ChatEdit_InsertLink(l) end
		end
	end)
end

-- ===========================================================================
-- consumables
-- ===========================================================================
local CF
local CONS_CATS = {
	{ "bestFood", "Food" }, { "food", "Food (alt)" }, { "bestFlask", "Flask" },
	{ "flask", "Flask (alt)" }, { "bestPotion", "Potion" }, { "potion", "Potion (alt)" },
}

local function RefreshConsumes()
	if not CF or not CF:IsShown() then return end
	local cd = ((D.consumes or {})[CF.ci] or {})[CF.si]
	local f = CLASS_FILE[D.classes[CF.ci] or ""]
	UIDropDownMenu_SetText(CF.classDD, (f and LOCALIZED_CLASS_NAMES_MALE[f]) or D.classes[CF.ci] or "?")
	UIDropDownMenu_SetText(CF.specDD, BG.SpecName(CF.ci, CF.si))
	local y = -8
	for _, row in ipairs(CF.rows) do row:Hide() end
	for i, cat in ipairs(CONS_CATS) do
		local ids = cd and cd[cat[1]]
		local r = CF.rows[i]
		if not r then
			r = CreateFrame("Frame", nil, CF)
			r:SetSize(360, 30)
			r.label = S:FontString(r, 11, "OUTLINE")
			r.label:SetPoint("LEFT", 0, 0)
			r.label:SetWidth(80)
			r.label:SetJustifyH("LEFT")
			r.label:SetTextColor(0.95, 0.8, 0.35)
			r.icons = {}
			for j = 1, 6 do
				local ic = SmallIcon(r, 26)
				ic:SetPoint("LEFT", 84 + (j - 1) * 30, 0)
				r.icons[j] = ic
				ic:Hide()
			end
			CF.rows[i] = r
		end
		r:SetPoint("TOPLEFT", 14, y)
		y = y - 36
		r.label:SetText(L[cat[2]] or cat[2])
		for j = 1, 6 do
			local ic, iid = r.icons[j], ids and ids[j]
			if iid then ItemBtnTip(ic, iid) ic:Show() else ic:Hide() end
		end
		r:Show()
	end
end

local function GetConsumesFrame()
	if CF then return CF end
	CF = BaseWindow("SentinelUIBisConsumes", L["Consumables"] or "Consumables", 340, 300)
	CF.rows = {}
	CF.classDD = SpecDD(CF, "SentinelUIBisConsClassDD", L["Class"] or "Class", -6)
	CF.specDD = SpecDD(CF, "SentinelUIBisConsSpecDD", L["Spec"] or "Spec", 160)
	ClassDDInit(CF.classDD, function() return CF.ci end, function(v)
		CF.ci = v CF.si = 1 RefreshConsumes()
	end)
	SpecDDInit(CF.specDD, function() return CF.ci end, function() return CF.si end, function(v)
		CF.si = v RefreshConsumes()
	end)
	return CF
end

-- ===========================================================================
-- rotation
-- ===========================================================================
local RF

local function SegsToText(segs)
	local out = {}
	for _, sg in ipairs(segs or {}) do
		if sg.t == "header" then
			tinsert(out, "|cffffd100— " .. (sg.v or "") .. " —|r")
		elseif sg.t == "s" then
			tinsert(out, "|cff66ccff[" .. (sg.v or "?") .. "]|r")
		else
			tinsert(out, sg.v or "")
		end
	end
	return table.concat(out)
end

local function RefreshRotation()
	if not RF or not RF:IsShown() then return end
	local rd = ((D.rot or {})[RF.ci] or {})[RF.si]
	local rf = CLASS_FILE[D.classes[RF.ci] or ""]
	UIDropDownMenu_SetText(RF.classDD, (rf and LOCALIZED_CLASS_NAMES_MALE[rf]) or D.classes[RF.ci] or "?")
	UIDropDownMenu_SetText(RF.specDD, BG.SpecName(RF.ci, RF.si))
	for i = 1, #RF.pool do RF.pool[i]:Hide() end
	for _, ic in ipairs(RF.icons) do ic:Hide() end
	local use = 0
	local function nextFS(size, outline)
		use = use + 1
		local fs = RF.pool[use]
		if not fs then
			fs = S:FontString(RF.content, size or 11, outline or "")
			fs:SetWidth(430)
			fs:SetJustifyH("LEFT")
			RF.pool[use] = fs
		end
		fs:Show()
		return fs
	end
	local iconUse = 0
	local function nextIcon()
		iconUse = iconUse + 1
		local ic = RF.icons[iconUse]
		if not ic then
			ic = SmallIcon(RF.content, 16)
			RF.icons[iconUse] = ic
		end
		ic:Show()
		return ic
	end
	local y2 = 0
	local function render(list, head)
		if not list or #list == 0 then return end
		if head then
			local h = nextFS(12, "OUTLINE")
			h:ClearAllPoints()
			h:SetPoint("TOPLEFT", 0, y2)
			h:SetText("|cff" .. format("%02x%02x%02x", S.accent.r * 255, S.accent.g * 255, S.accent.b * 255) .. head .. "|r")
			y2 = y2 - 22
		end
		for _, segs in ipairs(list) do
			local fs = nextFS(11)
			fs:ClearAllPoints()
			if segs.t == "header" then
				fs:SetPoint("TOPLEFT", 0, y2)
				fs:SetText("|cffffd100— " .. (segs.v or "") .. " —|r")
			else
				local sid
				for _, sg in ipairs(segs) do if sg.t == "s" then sid = sg.id break end end
				if sid then
					local ic = nextIcon()
					ic:ClearAllPoints()
					ic:SetPoint("TOPLEFT", 8, y2 - 1)
					SpellBtnTip(ic, sid)
					fs:SetPoint("TOPLEFT", 30, y2)
				else
					fs:SetPoint("TOPLEFT", 14, y2)
				end
				fs:SetText("• " .. SegsToText(segs))
			end
			y2 = y2 - (fs:GetStringHeight() + 6)
		end
	end
	render(rd and rd.steps, L["Single Target"] or "Single Target")
	y2 = y2 - 8
	render(rd and rd.aoe, L["AoE"] or "AoE")
	RF.content:SetHeight(math.max(10, -y2 + 10))
end

local function GetRotationFrame()
	if RF then return RF end
	RF = BaseWindow("SentinelUIBisRotation", L["Rotation"] or "Rotation", 480, 460)
	RF.pool, RF.icons = {}, {}
	RF.classDD = SpecDD(RF, "SentinelUIBisRotClassDD", L["Class"] or "Class", -6)
	RF.specDD = SpecDD(RF, "SentinelUIBisRotSpecDD", L["Spec"] or "Spec", 160)
	ClassDDInit(RF.classDD, function() return RF.ci end, function(v)
		RF.ci = v RF.si = 1 RefreshRotation()
	end)
	SpecDDInit(RF.specDD, function() return RF.ci end, function() return RF.si end, function(v)
		RF.si = v RefreshRotation()
	end)
	RF.scroll = CreateFrame("ScrollFrame", "SentinelUIBisRotScroll", RF, "UIPanelScrollFrameTemplate")
	RF.scroll:SetPoint("TOPLEFT", 12, -60)
	RF.scroll:SetPoint("BOTTOMRIGHT", -32, 8)
	RF.content = CreateFrame("Frame", nil, RF.scroll)
	RF.content:SetSize(430, 10)
	RF.scroll:SetScrollChild(RF.content)
	if RF.scroll.ScrollBar then S:SkinScrollBar(RF.scroll.ScrollBar) end
	return RF
end

-- ===========================================================================
-- talent builds
-- ===========================================================================
local TF
local TAL_OFFX, TAL_OFFY = 37, 37

local function RefreshTalents()
	if not TF or not TF:IsShown() then return end
	local tf = CLASS_FILE[D.classes[TF.ci] or ""]
	UIDropDownMenu_SetText(TF.classDD, (tf and LOCALIZED_CLASS_NAMES_MALE[tf]) or D.classes[TF.ci] or "?")
	local trees = D.tal[TF.ci] or {}
	local specName = (D.specs[TF.ci] or {})[TF.si] -- english key into D.builds
	UIDropDownMenu_SetText(TF.specDD, BG.SpecName(TF.ci, TF.si))
	local builds = (D.builds[TF.ci] or {})[specName] or {}
	local build = builds[TF.bi] or builds[1]
	UIDropDownMenu_SetText(TF.buildDD, build and build.n or "-")

	for ti = 1, 3 do
		local tf = TF.trees[ti]
		local td = trees[ti]
		if not td then if tf then tf:Hide() end
		else
			tf:Show()
			local base = "Interface\\TalentFrame\\" .. (td.bg or "") .. "-"
			if tf.tl then tf.tl:SetTexture(base .. "TopLeft") end
			if tf.tr then tf.tr:SetTexture(base .. "TopRight") end
			if tf.bl then tf.bl:SetTexture(base .. "BottomLeft") end
			if tf.br then tf.br:SetTexture(base .. "BottomRight") end
			tf.label:SetText("|cFFFFFF00" .. (td.tree or "") .. "|r")
			local pts = build and build.t and build.t[ti]
			local sum = 0
			if pts then for _, v in pairs(pts) do sum = sum + v end end
			tf.pts:SetText(sum > 0 and "|cFF9CD6DE(" .. sum .. ")|r" or "")
			for i, btn in ipairs(tf.btns) do
				local t = td.tal and td.tal[i]
				if t then
					btn:ClearAllPoints()
					btn:SetPoint("TOPLEFT", (t.col or 0) * TAL_OFFX, -((t.row or 0) * TAL_OFFY))
					btn.tex:SetTexture(t.i)
					local r = pts and (pts[i - 1] or pts[i])
					if r and r > 0 then
						btn.tex:SetDesaturated(false)
						btn.pts:SetText(r)
						btn.edge:SetColorTexture(1, 0.84, 0, 0.9)
					else
						btn.tex:SetDesaturated(true)
						btn.pts:SetText("")
						btn.edge:SetColorTexture(0, 0, 0, 0)
					end
					btn:Show()
				else
					btn:Hide()
				end
			end
		end
	end
end

local function GetTalentsFrame()
	if TF then return TF end
	TF = BaseWindow("SentinelUIBisTalents", L["BiS Talents"] or "BiS Talents", 560, 400)
	TF.classDD = SpecDD(TF, "SentinelUIBisTalClassDD", L["Class"] or "Class", -6)
	TF.specDD = SpecDD(TF, "SentinelUIBisTalSpecDD", L["Spec"] or "Spec", 160)
	TF.buildDD = SpecDD(TF, "SentinelUIBisTalBuildDD", L["Build"] or "Build", 326)
	ClassDDInit(TF.classDD, function() return TF.ci end, function(v)
		TF.ci = v TF.si = 1 TF.bi = 1 RefreshTalents()
	end)
	SpecDDInit(TF.specDD, function() return TF.ci end, function() return TF.si end, function(v)
		TF.si = v TF.bi = 1 RefreshTalents()
	end)
	UIDropDownMenu_Initialize(TF.buildDD, function(_, level)
		local specName = (D.specs[TF.ci] or {})[TF.si]
		for bi, b in ipairs((D.builds[TF.ci] or {})[specName] or {}) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = b.n
			info.func = function() TF.bi = bi RefreshTalents() end
			info.checked = TF.bi == bi
			UIDropDownMenu_AddButton(info, level)
		end
	end)

	TF.trees = {}
	for ti = 1, 3 do
		local tf = CreateFrame("Frame", nil, TF)
		tf:SetSize(4 * TAL_OFFX + 10, 7 * TAL_OFFY + 30)
		tf:SetPoint("TOPLEFT", 16 + (ti - 1) * 180, -64)
		local function bgTex(point)
			local t = tf:CreateTexture(nil, "BACKGROUND")
			t:SetDrawLayer("BACKGROUND", ti - 4)
			t:SetPoint(point)
			t:SetSize(128, 128)
			return t
		end
		tf.tl = bgTex("TOPLEFT")
		tf.tr = bgTex("TOPRIGHT")
		tf.bl = bgTex("BOTTOMLEFT")
		tf.br = bgTex("BOTTOMRIGHT")
		tf.label = S:FontString(tf, 11, "OUTLINE")
		tf.label:SetPoint("TOP", 0, 6)
		tf.pts = S:FontString(tf, 10, "OUTLINE")
		tf.pts:SetPoint("TOP", 0, -8)
		tf.btns = {}
		for i = 1, 42 do
			local b = CreateFrame("Button", nil, tf)
			b:SetSize(28, 28)
			b.tex = b:CreateTexture(nil, "ARTWORK")
			b.tex:SetAllPoints()
			b.tex:SetTexCoord(0.06, 0.94, 0.06, 0.94)
			b.edge = b:CreateTexture(nil, "OVERLAY")
			b.edge:SetPoint("TOPLEFT", -2, 2)
			b.edge:SetPoint("BOTTOMRIGHT", 2, -2)
			b.edge:SetDrawLayer("OVERLAY", 7)
			b.edge:SetColorTexture(0, 0, 0, 0)
			b.pts = S:FontString(b, 10, "OUTLINE")
			b.pts:SetPoint("BOTTOMRIGHT", 2, -2)
			b.pts:SetTextColor(1, 1, 1)
			tf.btns[i] = b
			b:Hide()
		end
		TF.trees[ti] = tf
	end
	return TF
end

-- ===========================================================================
-- public: window toggle
-- ===========================================================================
function BG:ToggleWindow(kind)
	D = D or SUIBisData
	if not D then return end
	ItemIcon = ItemIcon or self.ItemIcon
	local ci = self:PlayerClassIndex() or 1
	local si = self:GetPlayerSpec() or 1
	if kind == "consumes" then
		local f = GetConsumesFrame()
		f.ci = f.ci or ci f.si = f.si or si
		f:SetShown(not f:IsShown())
		if f:IsShown() then RefreshConsumes() end
	elseif kind == "rotation" then
		local f = GetRotationFrame()
		f.ci = f.ci or ci f.si = f.si or si
		f:SetShown(not f:IsShown())
		if f:IsShown() then RefreshRotation() end
	elseif kind == "talents" then
		local f = GetTalentsFrame()
		f.ci = f.ci or ci f.si = f.si or si f.bi = f.bi or 1
		f:SetShown(not f:IsShown())
		if f:IsShown() then RefreshTalents() end
	end
end
