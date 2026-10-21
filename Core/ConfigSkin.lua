-- Sentinel look for the options window: walks the AceGUI widget tree of our
-- config frame and restyles every widget (tree sidebar, tabs, checkboxes, sliders,
-- dropdowns, edit boxes, buttons, headings, inline groups).
local _, ns = ...
local S = ns.S

local BLANK = [[Interface\Buttons\WHITE8X8]]
local ipairs, pairs, floor = ipairs, pairs, math.floor

local function Accent(a) return S.accent.r, S.accent.g, S.accent.b, a or 1 end

local function HideTex(...)
	for i = 1, select("#", ...) do
		local t = select(i, ...)
		if t and t.SetAlpha then t:SetAlpha(0) end
	end
end

local function Plate(frame, template)
	if not frame then return end
	if frame.SetBackdrop then
		S:SetTemplate(frame, template or "Transparent")
	else
		S:CreateBackdrop(frame, template or "Transparent")
	end
end

-- tree sidebar buttons: flat rows, accent bar + tint on the selected entry
local function StyleTreeButton(btn)
	if btn.suiCfg then return end
	btn.suiCfg = true
	local hl = btn:GetHighlightTexture()
	if hl then
		hl:SetTexture(BLANK)
		hl:SetVertexColor(Accent(0.14))
		hl:ClearAllPoints()
		hl:SetPoint("TOPLEFT", 0, 0)
		hl:SetPoint("BOTTOMRIGHT", 0, 1)
	end
	local bar = btn:CreateTexture(nil, "OVERLAY")
	bar:SetTexture(BLANK)
	bar:SetWidth(2)
	bar:SetPoint("TOPLEFT", 0, 0)
	bar:SetPoint("BOTTOMLEFT", 0, 1)
	bar:SetVertexColor(Accent())
	bar:Hide()
	btn.suiBar = bar
	hooksecurefunc(btn, "LockHighlight", function(b) b.suiBar:Show() if b.text then b.text:SetTextColor(Accent()) end end)
	hooksecurefunc(btn, "UnlockHighlight", function(b) b.suiBar:Hide() if b.text then b.text:SetTextColor(0.85, 0.85, 0.88) end end)
	if btn.toggle then
		HideTex(btn.toggle:GetNormalTexture(), btn.toggle:GetPushedTexture(), btn.toggle:GetHighlightTexture())
		local sign = S:FontString(btn.toggle, 12, "OUTLINE")
		sign:SetPoint("CENTER")
		btn.toggle.suiSign = sign
		local function Upd(t, tex)
			HideTex(t:GetNormalTexture(), t:GetPushedTexture(), t:GetHighlightTexture())
			local minus = tex == 130821 or tostring(tex or ""):find("Minus")
			t.suiSign:SetText(minus and "-" or "+")
		end
		hooksecurefunc(btn.toggle, "SetNormalTexture", Upd)
		Upd(btn.toggle)
		S:RegisterAccent(sign, "text")
	end
end

local function StyleTab(tab)
	if tab.suiCfg then return end
	tab.suiCfg = true
	S:StripTextures(tab)
	local bd = S:CreateBackdrop(tab, "Default")
	bd:ClearAllPoints()
	bd:SetPoint("TOPLEFT", 3, -4)
	bd:SetPoint("BOTTOMRIGHT", -3, 0)
	local line = tab:CreateTexture(nil, "OVERLAY")
	line:SetTexture(BLANK)
	line:SetHeight(2)
	line:SetPoint("BOTTOMLEFT", bd, "BOTTOMLEFT", 1, 1)
	line:SetPoint("BOTTOMRIGHT", bd, "BOTTOMRIGHT", -1, 1)
	line:SetVertexColor(Accent())
	line:Hide()
	tab.suiLine = line
	if tab.SetSelected then
		hooksecurefunc(tab, "SetSelected", function(t, selected)
			t.suiLine:SetShown(selected)
			if t.text then if selected then t.text:SetTextColor(1, 1, 1) else t.text:SetTextColor(0.6, 0.6, 0.65) end end
		end)
	end
	S:AddHover(tab)
end

local function StyleCheck(obj)
	local cb = obj.frame
	if not obj.suiBox then
		local box = CreateFrame("Frame", nil, cb, S.BackdropTemplate)
		box:SetFrameLevel(cb:GetFrameLevel())
		S:SetTemplate(box, "Default")
		obj.suiBox = box
	end
	local box = obj.suiBox
	box:ClearAllPoints()
	box:SetPoint("TOPLEFT", obj.checkbg, "TOPLEFT", 5, -5)
	box:SetPoint("BOTTOMRIGHT", obj.checkbg, "BOTTOMRIGHT", -5, 5)
	obj.checkbg:SetAlpha(0)
	if obj.highlight then obj.highlight:SetTexture(BLANK) obj.highlight:SetVertexColor(Accent(0.15)) S:SetInside(obj.highlight, box, 1, 1) end
	obj.check:SetTexture(BLANK)
	obj.check:SetVertexColor(Accent())
	S:SetInside(obj.check, box, 3, 3)
end

local styler = {}

styler.CheckBox = function(obj)
	StyleCheck(obj)
	if not obj.suiHooked then
		obj.suiHooked = true
		hooksecurefunc(obj, "SetType", StyleCheck)
		hooksecurefunc(obj, "SetValue", function(o)
			local v = o:GetValue()
			if v == nil then o.check:SetVertexColor(0.5, 0.5, 0.5) else o.check:SetVertexColor(Accent()) end
		end)
	end
end

styler.Button = function(obj)
	-- S:SkinButton mirrors the caption on a child-frame label that renders
	-- above every region/backdrop - nothing else needed here
	S:SkinButton(obj.frame)
end
styler.EditBox = function(obj) S:SkinEditBox(obj.editbox) if obj.button then S:SkinButton(obj.button) end end
styler.MultiLineEditBox = function(obj)
	if obj.scrollBG then Plate(obj.scrollBG, "Default") end
	if obj.button then S:SkinButton(obj.button) end
	if obj.scrollBar then S:SkinScrollBar(obj.scrollBar) end
end
styler.Slider = function(obj)
	S:SkinSlider(obj.slider)
	if obj.editbox then
		HideTex(obj.editbox:GetRegions())
		Plate(obj.editbox, "Default")
	end
end
styler.Dropdown = function(obj)
	S:SkinDropDown(obj.dropdown)
end
local function LSM(obj)
	local f = obj.frame
	HideTex(f.DLeft, f.DMiddle, f.DRight)
	if not f.suiPlate then
		local p = CreateFrame("Frame", nil, f, S.BackdropTemplate)
		p:SetPoint("TOPLEFT", f.DLeft, "TOPLEFT", 20, -21)
		p:SetPoint("BOTTOMRIGHT", f.DRight, "BOTTOMRIGHT", -20, 23)
		p:SetFrameLevel(f:GetFrameLevel())
		S:SetTemplate(p, "Default")
		f.suiPlate = p
	end
	if f.dropButton then
		f.dropButton:ClearAllPoints()
		f.dropButton:SetPoint("RIGHT", f.suiPlate, "RIGHT", -2, 0)
		f.dropButton:SetSize(16, 16)
	end
end
styler.LSM30_Font, styler.LSM30_Statusbar, styler.LSM30_Sound, styler.LSM30_Background, styler.LSM30_Border = LSM, LSM, LSM, LSM, LSM

styler.Heading = function(obj)
	for _, t in ipairs({ obj.left, obj.right }) do
		if t then t:SetTexture(BLANK) t:SetHeight(1) t:SetVertexColor(Accent(0.45)) end
	end
	if obj.label then obj.label:SetTextColor(Accent()) end
end

styler.InlineGroup = function(obj)
	local border = obj.content and obj.content:GetParent()
	if border then Plate(border, "Transparent") end
	if obj.titletext then obj.titletext:SetTextColor(Accent()) end
end

styler.TabGroup = function(obj)
	Plate(obj.border, "Transparent")
	for _, tab in ipairs(obj.tabs or {}) do StyleTab(tab) end
	if not obj.suiHooked then
		obj.suiHooked = true
		hooksecurefunc(obj, "BuildTabs", function(o) for _, tab in ipairs(o.tabs) do StyleTab(tab) end end)
	end
end

styler.TreeGroup = function(obj)
	Plate(obj.treeframe, "Default")
	Plate(obj.border, "Transparent")
	if obj.scrollbar then S:SkinScrollBar(obj.scrollbar) end
	if obj.dragger and obj.dragger.SetBackdrop then obj.dragger:SetBackdrop(nil) end
	for _, b in ipairs(obj.buttons or {}) do StyleTreeButton(b) end
	if not obj.suiHooked then
		obj.suiHooked = true
		hooksecurefunc(obj, "RefreshTree", function(o) for _, b in ipairs(o.buttons) do StyleTreeButton(b) end end)
	end
end

styler.ScrollFrame = function(obj)
	if obj.scrollbar then S:SkinScrollBar(obj.scrollbar) end
end

local function Walk(widget)
	if not widget then return end
	local fn = styler[widget.type]
	if fn and not widget.suiStyled then
		widget.suiStyled = true
		S:SafeCall("ConfigSkin:" .. widget.type, fn, widget)
	end
	if widget.children then
		for _, child in ipairs(widget.children) do Walk(child) end
	end
end

-- main window: Sentinel chrome - accent top edge, brand header band with logo
-- and wordmark, darker sidebar plate, footer strip. Deliberately its own look.
function S:StyleConfigWindow(widget)
	local frame = widget and widget.frame
	if not frame then return end
	if not frame.suiCfgMain then
		frame.suiCfgMain = true
		S:StripTextures(frame)
		S:SetTemplate(frame, "Default")
		frame:SetSize(860, 560)
		frame:SetClampedToScreen(true)
		HideTex(widget.titlebg)
		for _, r in ipairs({ frame:GetRegions() }) do
			if r:IsObjectType("Texture") and r:GetTexture() == 131080 then r:SetAlpha(0) end
		end

		-- accent edge on the very top of the window
		local edge = frame:CreateTexture(nil, "OVERLAY")
		edge:SetTexture(BLANK)
		edge:SetHeight(2)
		edge:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
		edge:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
		edge:SetVertexColor(Accent())
		S:RegisterAccent(edge, "texture")

		-- header band: logo + accent wordmark + version
		local band = CreateFrame("Frame", nil, frame, S.BackdropTemplate)
		band:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -6)
		band:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -6)
		band:SetHeight(34)
		band:SetFrameLevel(frame:GetFrameLevel() + 1)
		S:SetTemplate(band, "Transparent")
		local logo = band:CreateTexture(nil, "OVERLAY")
		logo:SetTexture(S.media.logo)
		logo:SetSize(22, 22)
		logo:SetPoint("LEFT", band, "LEFT", 10, 0)
		if widget.titletext then
			local title = widget.titletext
			title:SetParent(band)
			title:ClearAllPoints()
			title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
			S:SetFont(title, S.media.font, 15, "OUTLINE")
			title:SetTextColor(Accent())
			S:RegisterAccent(title, "text")
		end
		local ver = S:FontString(band, 10)
		ver:SetPoint("RIGHT", band, "RIGHT", -36, 0)
		ver:SetText("v" .. tostring(S.version))
		ver:SetTextColor(0.5, 0.5, 0.55)

		-- make room for the header band and footer strip
		if widget.content then
			widget.content:ClearAllPoints()
			widget.content:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -46)
			widget.content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 32)
		end

		-- footer strip behind the status text
		local foot = CreateFrame("Frame", nil, frame, S.BackdropTemplate)
		foot:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 4, 4)
		foot:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
		foot:SetHeight(24)
		S:SetTemplate(foot, "Transparent")
		if widget.statustext then
			local bg = widget.statustext:GetParent()
			if bg then
				bg:SetParent(foot)
				bg:ClearAllPoints()
				bg:SetPoint("LEFT", foot, "LEFT", 10, 0)
				bg:SetPoint("RIGHT", foot, "RIGHT", -110, 0)
				if bg.SetBackdrop then bg:SetBackdrop(nil) end
			end
			S:SetFont(widget.statustext, S.media.font, 11)
			widget.statustext:SetTextColor(0.6, 0.6, 0.65)
		end

		-- close button: our own small x
		for _, child in ipairs({ frame:GetChildren() }) do
			if child:IsObjectType("Button") then
				if child.GetText and child:GetText() and child:GetText() ~= "" then
					S:SkinButton(child)
					if child:GetText() == CLOSE then
						-- AceConfig anchors "Close" to the bare frame edge,
						-- half below our footer: dock it inside the strip
						child:ClearAllPoints()
						child:SetPoint("RIGHT", foot, "RIGHT", -8, 0)
						child:SetSize(90, 18)
					end
				elseif child.GetNormalTexture and child:GetNormalTexture() then
					S:StripTextures(child)
					S:CreateBackdrop(child, "Default", nil, 0)
					local x = S:FontString(child, 12, "OUTLINE")
					x:SetPoint("CENTER")
					x:SetText("x")
					x:SetTextColor(Accent())
					S:RegisterAccent(x, "text")
					S:AddHover(child)
				end
			end
		end
		-- keep restyling while open (widgets are created lazily when groups change)
		local acc = 0
		local ACD = LibStub("AceConfigDialog-3.0")
		frame:HookScript("OnUpdate", function(_, e)
			acc = acc + e
			if acc < 0.2 then return end
			acc = 0
			-- the Frame widget is pooled: only walk while it hosts our options
			if ACD.OpenFrames.SentinelUI == widget then Walk(widget) end
		end)
	end
	Walk(widget)
end
