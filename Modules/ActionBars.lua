local _, ns = ...
local S = ns.S
local L = S.L
local AB = S:NewModule("ActionBars")

local _G = _G
local pairs, ipairs, format, floor, min, max, ceil = pairs, ipairs, format, floor, min, max, ceil
local GetActionTexture, GetActionCount, GetActionText, IsUsableAction, IsActionInRange = GetActionTexture, GetActionCount, GetActionText, IsUsableAction, IsActionInRange
local HasAction, IsCurrentAction, IsAutoRepeatAction, IsEquippedAction, IsConsumableAction, IsStackableAction = HasAction, IsCurrentAction, IsAutoRepeatAction, IsEquippedAction, IsConsumableAction, IsStackableAction
local GetBindingKey = GetBindingKey
local BLANK = [[Interface\Buttons\WHITE8X8]]

AB.bars = {}
AB.buttons = {}
AB.slotButtons = {}

-- bar key -> static page and Blizzard binding command prefix
local barInfo = {
	bar1 = { page = 1, bind = "ACTIONBUTTON%d", title = L["Action Bar 1"] },
	bar2 = { page = 6, bind = "MULTIACTIONBAR1BUTTON%d", title = L["Action Bar 2"] },
	bar3 = { page = 5, bind = "MULTIACTIONBAR2BUTTON%d", title = L["Action Bar 3"] },
	bar4 = { page = 3, bind = "MULTIACTIONBAR3BUTTON%d", title = L["Action Bar 4"] },
	bar5 = { page = 4, bind = "MULTIACTIONBAR4BUTTON%d", title = L["Action Bar 5"] },
	bar6 = { page = 2, title = L["Action Bar 6"] },
	bar7 = { page = 13, bind = "MULTIACTIONBAR5BUTTON%d", title = L["Action Bar 7"], retailOnly = true },
	bar8 = { page = 14, bind = "MULTIACTIONBAR6BUTTON%d", title = L["Action Bar 8"], retailOnly = true },
}
AB.barInfo = barInfo

local defaultPositions = {
	bar1 = { "BOTTOM", "UIParent", "BOTTOM", 0, 32 },
	bar2 = { "BOTTOM", "SentinelUIMover_bar1", "TOP", 0, 3 },
	bar3 = { "BOTTOM", "SentinelUIMover_bar2", "TOP", 0, 3 },
	bar4 = { "RIGHT", "UIParent", "RIGHT", -4, 0 },
	bar5 = { "RIGHT", "SentinelUIMover_bar4", "LEFT", -3, 0 },
	bar6 = { "RIGHT", "SentinelUIMover_bar5", "LEFT", -3, 0 },
	bar7 = { "BOTTOM", "SentinelUIMover_bar3", "TOP", 0, 3 },
	bar8 = { "BOTTOM", "SentinelUIMover_bar7", "TOP", 0, 3 },
	barPet = { "BOTTOM", "SentinelUIMover_bar3", "TOP", 0, 8 },
	barStance = { "BOTTOM", "SentinelUIMover_barPet", "TOP", 0, 4 },
	microbar = { "BOTTOMRIGHT", "SentinelUIMover_bagbar", "TOPRIGHT", 0, 6 },
	bagbar = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -440, 30 },
}

local function PagingConditions()
	local class = S.myClass
	local c = {}
	if S.isRetail or S.isWrath or S.isCata or S.isMists then
		c[#c + 1] = "[overridebar] possess; [vehicleui][possessbar] possess; [shapeshift] possess"
	else
		c[#c + 1] = "[possessbar] possess"
	end
	c[#c + 1] = "[bonusbar:5] 11"
	c[#c + 1] = "[bar:2] 2; [bar:3] 3; [bar:4] 4; [bar:5] 5; [bar:6] 6"
	if class == "DRUID" then
		c[#c + 1] = (S.isRetail and "[bonusbar:1,stealth] 8; " or "") .. "[bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9; [bonusbar:4] 10"
	elseif class == "ROGUE" then
		c[#c + 1] = "[bonusbar:1] 7; [bonusbar:2] 8"
	elseif class == "WARRIOR" then
		if not S.isRetail then c[#c + 1] = "[bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9" end
	elseif class == "PRIEST" then
		if not S.isRetail then c[#c + 1] = "[bonusbar:1] 7" end
	elseif class == "MONK" and S.isMists then
		c[#c + 1] = "[bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9"
	elseif class == "WARLOCK" and (S.isCata or S.isMists) then
		c[#c + 1] = "[form:1] 7"
	elseif class == "EVOKER" then
		c[#c + 1] = "[bonusbar:1] 7"
	end
	c[#c + 1] = "1"
	return table.concat(c, "; ")
end

local onStatePage = [[
	local page = newstate
	if page == "possess" then
		if HasVehicleActionBar and HasVehicleActionBar() then page = GetVehicleBarIndex()
		elseif HasOverrideActionBar and HasOverrideActionBar() then page = GetOverrideBarIndex()
		elseif HasTempShapeshiftActionBar and HasTempShapeshiftActionBar() then page = GetTempShapeshiftBarIndex()
		elseif HasBonusActionBar and HasBonusActionBar() and GetActionBarPage() == 1 then page = GetBonusBarIndex()
		else page = nil end
		if not page then page = 11 end
	end
	page = tonumber(page) or 1
	self:SetAttribute("actionpage", page)
	control:ChildUpdate("page", page)
]]

local childUpdatePage = [[
	local page = tonumber(message) or 1
	self:SetAttribute("action", (page - 1) * 12 + self:GetAttribute("index"))
]]

-- Hotkey shortening ---------------------------------------------------------
local keyReplace = {
	{ "ALT%-", "A" }, { "CTRL%-", "C" }, { "SHIFT%-", "S" }, { "META%-", "M" },
	{ "MOUSEWHEELUP", "WU" }, { "MOUSEWHEELDOWN", "WD" }, { "MIDDLEMOUSE", "M3" },
	{ "BUTTON(%d+)", "M%1" }, { "NUMPADDECIMAL", "N." }, { "NUMPADPLUS", "N+" }, { "NUMPADMINUS", "N-" },
	{ "NUMPADMULTIPLY", "N*" }, { "NUMPADDIVIDE", "N/" }, { "NUMPAD", "N" }, { "PAGEUP", "PU" }, { "PAGEDOWN", "PD" },
	{ "SPACE", "Spc" }, { "INSERT", "Ins" }, { "DELETE", "Del" }, { "HOME", "Hm" }, { "END", "End" },
	{ "BACKSPACE", "BS" }, { "CAPSLOCK", "Cap" }, { "TAB", "Tab" }, { "ENTER", "Ent" },
}
function AB:ShortKey(key)
	if not key then return "" end
	for _, r in ipairs(keyReplace) do key = key:gsub(r[1], r[2]) end
	return key
end

-- Button visuals ------------------------------------------------------------
local cdWatchFrame -- forward-declared; created with the watcher below
local function GetCooldown(action)
	if C_ActionBar and C_ActionBar.GetActionCooldown then
		local info = C_ActionBar.GetActionCooldown(action)
		if info then return info.startTime, info.duration, info.isEnabled, info.modRate end
		return 0, 0
	end
	return GetActionCooldown(action)
end

local function GetCharges(action)
	if C_ActionBar and C_ActionBar.GetActionCharges then
		local info = C_ActionBar.GetActionCharges(action)
		if info then return info.currentCharges, info.maxCharges end
		return
	end
	if GetActionCharges then return GetActionCharges(action) end
end

function AB:UpdateHotkey(btn)
	local key = btn.bindCommand and GetBindingKey(btn.bindCommand)
	local db = self.db
	if key and db.hotkeyText then
		btn.hotkey:SetText(self:ShortKey(key))
		btn.hotkey:Show()
	else
		btn.hotkey:SetText("")
		btn.hotkey:Hide()
	end
end

function AB:UpdateCount(btn)
	local action = btn.action
	if not self.db.countText then btn.count:SetText("") return end
	if IsConsumableAction(action) or IsStackableAction(action) then
		local count = GetActionCount(action)
		if S.IsSecret(count) then btn.count:SetText(count) return end
		btn.count:SetText((count and count > (IsItemAction and IsItemAction(action) and 0 or 1)) and (count > 999 and "*" or count) or "")
	else
		local charges, maxCharges = GetCharges(action)
		if charges and maxCharges and not S.IsSecret(maxCharges) and maxCharges > 1 then
			btn.count:SetText(charges)
		else
			btn.count:SetText("")
		end
	end
end

function AB:UpdateCooldown(btn)
	local start, duration, enable, modRate = GetCooldown(btn.action)
	if start and duration then
		local ok = pcall(btn.cooldown.SetCooldown, btn.cooldown, start, duration, modRate)
		if not ok then btn.cooldown:Clear() end
	else
		btn.cooldown:Clear()
	end
	if not S.IsSecret(duration) then
		if self.db.desaturateOnCooldown then
			btn.icon:SetDesaturated(duration and duration > 1.5 and start and start > 0 or false)
		end
		-- No reliable event fires when a cooldown ENDS on classic clients; track
		-- the expiry ourselves so desaturation/usable colors get restored.
		if duration and duration > 0 and start and start > 0 then
			btn.cdEndsAt = start + duration
			AB.cdWatch[btn] = true
			cdWatchFrame:Show()
		end
	end
end

function AB:UpdateUsable(btn)
	local action = btn.action
	local db = self.db
	local isUsable, notEnoughMana = IsUsableAction(action)
	local inRange = IsActionInRange(action)
	if S.IsSecret(isUsable) or S.IsSecret(inRange) then
		btn.icon:SetVertexColor(1, 1, 1)
		return
	end
	btn.outOfRange = (inRange == false)
	if db.useRangeColor and btn.outOfRange then
		local c = db.rangeColor
		btn.icon:SetVertexColor(c and c.r or 0.9, c and c.g or 0.2, c and c.b or 0.2)
	elseif isUsable then
		btn.icon:SetVertexColor(1, 1, 1)
	elseif notEnoughMana then
		local c = db.noPowerColor
		btn.icon:SetVertexColor(c and c.r or 0.3, c and c.g or 0.35, c and c.b or 0.75)
	else
		local c = db.unusableColor
		btn.icon:SetVertexColor(c and c.r or 0.4, c and c.g or 0.4, c and c.b or 0.4)
	end
end

function AB:UpdateState(btn)
	local action = btn.action
	local checked = IsCurrentAction(action) or IsAutoRepeatAction(action)
	if S.IsSecret(checked) then return end
	btn:SetChecked(checked and true or false)
end

function AB:UpdateBorder(btn)
	local bd = btn.suiBackdrop
	if not bd then return end
	if self.db.equippedItem and IsEquippedAction(btn.action) then
		local c = self.db.equippedColor
		bd:SetBackdropBorderColor(c and c.r or 0.25, c and c.g or 0.85, c and c.b or 0.35)
	elseif btn.glowing then
		bd:SetBackdropBorderColor(1, 0.85, 0.2)
	else
		bd:SetBackdropBorderColor(unpack(S.media.borderColor))
	end
end

function AB:UpdateGridVisibility(btn)
	local has = HasAction(btn.action)
	btn.hasAction = has
	local show = has or btn.bar.db.showGrid or self.showGrid
	btn:SetAlpha(show and 1 or 0)
end

function AB:UpdateButton(btn)
	local action = btn:GetAttribute("action")
	if not action then return end
	local old = btn.action
	if old and self.slotButtons[old] then self.slotButtons[old][btn] = nil end
	btn.action = action
	self.slotButtons[action] = self.slotButtons[action] or {}
	self.slotButtons[action][btn] = true

	local texture = GetActionTexture(action)
	if texture then
		btn.icon:SetTexture(texture)
		btn.icon:Show()
	else
		btn.icon:Hide()
	end
	self:UpdateGridVisibility(btn)
	if self.db.macroText and not (IsConsumableAction(action) or IsStackableAction(action)) then
		btn.macro:SetText(GetActionText(action) or "")
	else
		btn.macro:SetText("")
	end
	self:UpdateCount(btn)
	self:UpdateCooldown(btn)
	self:UpdateUsable(btn)
	self:UpdateState(btn)
	self:UpdateBorder(btn)
	if btn.glowing and not texture then self:HideGlow(btn) end
end

function AB:ForEachButton(func, ...)
	for _, btn in ipairs(self.buttons) do func(self, btn, ...) end
end

-- Proc glow (own implementation, no Blizzard dependency)
function AB:ShowGlow(btn)
	if not btn.glow then
		local g = CreateFrame("Frame", nil, btn, S.BackdropTemplate)
		S:SetOutside(g, btn, 2, 2)
		g:SetBackdrop({ edgeFile = BLANK, edgeSize = 2 })
		g:SetBackdropBorderColor(1, 0.82, 0.25, 1)
		g:SetFrameLevel(btn:GetFrameLevel() + 4)
		local ag = g:CreateAnimationGroup()
		ag:SetLooping("BOUNCE")
		local a = ag:CreateAnimation("Alpha")
		a:SetFromAlpha(1)
		a:SetToAlpha(0.25)
		a:SetDuration(0.45)
		g.anim = ag
		btn.glow = g
	end
	btn.glowing = true
	btn.glow:Show()
	btn.glow.anim:Play()
end

function AB:HideGlow(btn)
	btn.glowing = nil
	if btn.glow then btn.glow.anim:Stop() btn.glow:Hide() end
end

local function GetActionSpellID(action)
	local actionType, id, subType = GetActionInfo(action)
	if actionType == "spell" then return id end
	if actionType == "macro" then
		if subType == "spell" then return id end
		local spell = GetMacroSpell and GetMacroSpell(id)
		return spell
	end
end

function AB:SPELL_ACTIVATION_OVERLAY_GLOW_SHOW(_, spellID)
	for _, btn in ipairs(self.buttons) do
		if btn.action and GetActionSpellID(btn.action) == spellID then self:ShowGlow(btn) self:UpdateBorder(btn) end
	end
end

function AB:SPELL_ACTIVATION_OVERLAY_GLOW_HIDE(_, spellID)
	for _, btn in ipairs(self.buttons) do
		if btn.action and GetActionSpellID(btn.action) == spellID then self:HideGlow(btn) self:UpdateBorder(btn) end
	end
end

-- Styling shared by action/pet/stance buttons
function AB:StyleButton(btn, isBlizzard)
	local name = btn:GetName()
	local icon = btn.icon or btn.Icon or _G[name .. "Icon"]
	local cooldown = btn.cooldown or btn.Cooldown or _G[name .. "Cooldown"]
	local hotkey = btn.HotKey or _G[name .. "HotKey"]
	local count = btn.Count or _G[name .. "Count"]
	local macro = btn.Name or _G[name .. "Name"]
	local flash = btn.Flash or _G[name .. "Flash"]
	local border = btn.Border or _G[name .. "Border"]
	local normal = btn.GetNormalTexture and btn:GetNormalTexture()
	local normal2 = _G[name .. "NormalTexture2"]

	btn.icon, btn.cooldown, btn.hotkey, btn.count, btn.macro = icon, cooldown, hotkey, count, macro

	if normal then normal:SetAlpha(0) end
	if normal2 then normal2:SetAlpha(0) end
	if btn.SetNormalTexture and not isBlizzard then pcall(btn.SetNormalTexture, btn, S.isRetail and 0 or "") end
	if border then border:SetAlpha(0) end
	for _, k in ipairs({ "IconMask", "SlotBackground", "SlotArt", "RightDivider", "BottomDivider", "FloatingBG", "NewActionTexture", "SpellHighlightTexture", "AutoCastOverlay" }) do
		local obj = btn[k]
		if obj and obj.SetAlpha and k ~= "AutoCastOverlay" then obj:SetAlpha(0) end
		if k == "IconMask" and obj and icon and icon.RemoveMaskTexture then pcall(icon.RemoveMaskTexture, icon, obj) end
	end
	local floating = _G[name .. "FloatingBG"]
	if floating then floating:SetAlpha(0) end

	if icon then
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		S:SetInside(icon, btn, 0, 0)
		icon:SetDrawLayer("BACKGROUND", 7)
	end
	if cooldown then
		S:SetInside(cooldown, btn, 0, 0)
		S:RegisterCooldown(cooldown)
	end
	if flash then
		flash:SetTexture(BLANK)
		flash:SetVertexColor(1, 0.2, 0.2, 0.35)
		S:SetInside(flash, btn)
	end
	S:CreateBackdrop(btn, "Default")

	if btn.SetPushedTexture then
		btn:SetPushedTexture(BLANK)
		local t = btn:GetPushedTexture()
		t:SetVertexColor(1, 1, 1, 0.18)
		S:SetInside(t, btn)
	end
	if btn.SetHighlightTexture then
		btn:SetHighlightTexture(BLANK)
		local t = btn:GetHighlightTexture()
		t:SetVertexColor(1, 1, 1, 0.12)
		S:SetInside(t, btn)
	end
	if btn.SetCheckedTexture then
		btn:SetCheckedTexture(BLANK)
		local t = btn:GetCheckedTexture()
		t:SetVertexColor(S.accent.r, S.accent.g, S.accent.b, 0.35)
		S:SetInside(t, btn)
		S.accentFrames[t] = "texture"
	end

	if hotkey then
		hotkey:ClearAllPoints()
		hotkey:SetPoint("TOPRIGHT", -1, -2)
		hotkey:SetJustifyH("RIGHT")
	end
	if count then
		count:ClearAllPoints()
		count:SetPoint("BOTTOMRIGHT", -1, 2)
	end
	if macro then
		macro:ClearAllPoints()
		macro:SetPoint("BOTTOM", 0, 2)
		macro:SetWidth(btn:GetWidth())
	end
	self:StyleButtonText(btn, btn.bar and btn.bar.db)
end

-- per-bar font face, outline, sizes and text colors (all editable in the options)
function AB:StyleButtonText(btn, db)
	db = db or {}
	local font = db.font and S:Fetch("font", db.font) or S.media.numberFont
	local outline = db.fontOutline or "OUTLINE"
	local function Apply(fs, size, color, fallback)
		if not fs then return end
		S:SetFont(fs, font, size, outline)
		local c = color or fallback
		fs:SetTextColor(c.r, c.g, c.b)
	end
	Apply(btn.hotkey, db.hotkeyFontSize or 11, db.hotkeyColor, { r = 0.9, g = 0.9, b = 0.9 })
	Apply(btn.count, db.countFontSize or 12, db.countColor, { r = 1, g = 1, b = 1 })
	Apply(btn.macro, db.macroFontSize or 10, db.macroColor, { r = 1, g = 0.82, b = 0.5 })
end

-- Action bars ---------------------------------------------------------------
local function ButtonOnAttributeChanged(btn, name)
	if name == "action" then S:SafeCall("ActionBars:Attr", AB.UpdateButton, AB, btn) end
end

local function ButtonPreClick(btn)
	if InCombatLockdown() or not btn.action then return end
	if GetCursorInfo() then
		btn.suiPlaced = true
		btn:SetAttribute("type", nil)
		PlaceAction(btn.action)
	end
end

local function ButtonPostClick(btn)
	if btn.suiPlaced then
		btn.suiPlaced = nil
		if not InCombatLockdown() then pcall(btn.SetAttribute, btn, "type", "action") end
	end
	AB:UpdateState(btn)
end

local function ButtonOnEnter(btn)
	if AB.keybindMode then return AB:KeybindOnEnter(btn) end
	if not btn.action or not HasAction(btn.action) then return end
	if GetCVarBool and not GetCVarBool("UberTooltips") then return end
	GameTooltip_SetDefaultAnchor(GameTooltip, btn)
	if GameTooltip:SetAction(btn.action) then GameTooltip:Show() end
end

local function ButtonOnLeave()
	GameTooltip:Hide()
end

function AB:ClickRegistration()
	-- keyDown option: fire on press instead of release (removes the click latency)
	return (self.db.keyDown or GetCVarBool("ActionButtonUseKeyDown")) and "AnyDown" or "AnyUp"
end

function AB:CreateActionButton(bar, index)
	local name = format("SentinelUI%sButton%d", bar.key:gsub("^%l", string.upper), index)
	-- No Blizzard ActionButtonTemplate: on newer clients it ships Blizzard's full button logic,
	-- which fights with ours. All visuals are created here.
	local btn = CreateFrame("CheckButton", name, bar, "SecureActionButtonTemplate")
	btn.bar = bar
	btn.index = index
	-- the secure template's attribute handler calls Blizzard's UpdateFlyout, which
	-- nil-calls a missing function on classic clients. Shadow it per-button: our
	-- bars draw no flyout arrows anyway.
	btn.UpdateFlyout = function() end
	btn:SetSize(32, 32)
	btn.icon = btn:CreateTexture(name .. "Icon", "BACKGROUND", nil, 7)
	btn.Flash = btn:CreateTexture(name .. "Flash", "ARTWORK")
	btn.Flash:Hide()
	btn.cooldown = CreateFrame("Cooldown", name .. "Cooldown", btn, "CooldownFrameTemplate")
	btn.cooldown:SetFrameLevel(btn:GetFrameLevel() + 1)
	local textFrame = CreateFrame("Frame", nil, btn)
	textFrame:SetAllPoints()
	textFrame:SetFrameLevel(btn:GetFrameLevel() + 4)
	btn.textFrame = textFrame
	btn.HotKey = textFrame:CreateFontString(name .. "HotKey", "OVERLAY")
	btn.Count = textFrame:CreateFontString(name .. "Count", "OVERLAY")
	btn.Name = textFrame:CreateFontString(name .. "Name", "OVERLAY")
	for _, fs in ipairs({ btn.HotKey, btn.Count, btn.Name }) do S:SetFont(fs, S.media.numberFont, 11, "OUTLINE") fs:SetWordWrap(false) end
	btn:SetAttribute("type", "action")
	btn:SetAttribute("index", index)
	-- the secure template's OnAttributeChanged runs Blizzard's UpdateFlyout, which
	-- calls a function missing on classic clients -> nil-call error. The attribute
	-- is stored before the handler fires, so swallowing the error is safe.
	pcall(btn.SetAttribute, btn, "action", (bar.info.page - 1) * 12 + index)
	btn:SetAttribute("checkselfcast", self.db.checkSelfCast)
	btn:SetAttribute("checkfocuscast", self.db.checkFocusCast)
	btn:SetAttribute("checkmouseovercast", true)
	btn:SetAttribute("_childupdate-page", childUpdatePage)
	btn:RegisterForClicks(self:ClickRegistration())
	btn:RegisterForDrag("LeftButton", "RightButton")
	btn.bindCommand = bar.info.bind and format(bar.info.bind, index) or ("CLICK " .. name .. ":LeftButton")

	bar:WrapScript(btn, "OnDragStart", [[
		if self:GetParent():GetAttribute("locked") and not IsModifiedClick("PICKUPACTION") then return false end
		local action = self:GetAttribute("action")
		return "action", action
	]])
	bar:WrapScript(btn, "OnReceiveDrag", [[
		local kind = ...
		return "action", self:GetAttribute("action")
	]])

	btn:HookScript("OnAttributeChanged", ButtonOnAttributeChanged)
	btn:HookScript("PreClick", ButtonPreClick)
	btn:HookScript("PostClick", ButtonPostClick)
	btn:SetScript("OnEnter", ButtonOnEnter)
	btn:SetScript("OnLeave", ButtonOnLeave)

	self:StyleButton(btn)
	self.buttons[#self.buttons + 1] = btn
	return btn
end

function AB:LayoutBar(bar)
	if InCombatLockdown() then return S:RunOutOfCombat(self.LayoutBar, self, bar) end
	local db = bar.db
	local numButtons = min(db.buttons or 12, #bar.buttons)
	if bar.getNumButtons then numButtons = min(numButtons, bar.getNumButtons()) end
	local perRow = max(1, min(db.buttonsPerRow or 12, numButtons))
	local size = db.buttonSize or 32
	local height = (db.buttonHeight and db.buttonHeight > 0) and db.buttonHeight or size
	local spacing = db.spacing or 3
	local pad = db.backdrop and (db.backdropSpacing or 2) or 0
	local rows = ceil(numButtons / perRow)

	for i, btn in ipairs(bar.buttons) do
		btn:ClearAllPoints()
		btn:SetSize(size, height)
		if i <= numButtons then
			local col = (i - 1) % perRow
			local row = floor((i - 1) / perRow)
			btn:SetPoint("TOPLEFT", bar, "TOPLEFT", pad + col * (size + spacing), -(pad + row * (height + spacing)))
			btn:Show()
		else
			btn:Hide()
		end
		if btn.macro then btn.macro:SetWidth(size) end
		if btn.icon and height ~= size then
			local ratio = height / size
			local cut = (1 - ratio) * 0.42
			btn.icon:SetTexCoord(0.08, 0.92, 0.08 + cut, 0.92 - cut)
		elseif btn.icon then
			btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		end
	end
	if numButtons == 0 then
		bar:SetSize(size, height)
	else
		bar:SetSize(pad * 2 + perRow * size + (perRow - 1) * spacing, pad * 2 + rows * height + (rows - 1) * spacing)
	end
	if bar.bg then
		bar.bg:SetShown(db.backdrop)
		local c = db.backdropColor
		if c and bar.bg.SetBackdropColor then bar.bg:SetBackdropColor(c.r, c.g, c.b, c.a or 0.6) end
	end

	local enabled = db.enable ~= false
	local vis = (db.visibility and db.visibility ~= "" and db.visibility ~= "show") and db.visibility or (bar.visDefault or "show")
	RegisterStateDriver(bar, "visibility", enabled and vis or "hide")
	S:DisableMover(bar.key, not enabled)
	self:UpdateFade(bar)
end

function AB:CreateBar(key)
	local info = barInfo[key]
	local db = self.db[key]
	local bar = CreateFrame("Frame", "SentinelUI" .. key:gsub("^%l", string.upper), UIParent, "SecureHandlerStateTemplate")
	bar.key, bar.info, bar.db = key, info, db
	bar.buttons = {}
	bar:SetFrameStrata("LOW")
	bar:SetSize(10, 10)
	bar:SetAttribute("locked", GetCVarBool("lockActionBars") or self.db.lockActionBars)

	local bg = CreateFrame("Frame", nil, bar, S.BackdropTemplate)
	bg:SetAllPoints()
	bg:SetFrameLevel(0)
	S:SetTemplate(bg, "Transparent")
	bar.bg = bg

	for i = 1, 12 do bar.buttons[i] = self:CreateActionButton(bar, i) end

	if db.paging then
		bar:SetAttribute("_onstate-page", onStatePage)
		RegisterStateDriver(bar, "page", PagingConditions())
	end

	S:CreateMover(bar, key, info.title, defaultPositions[key], "actionbars")
	self.bars[key] = bar
	self:LayoutBar(bar)
	return bar
end

-- Mouseover fading
local fadeBars = {}
-- global fade: bars with "inherit global fade" drop to globalFadeAlpha while idle
-- (no combat, no target, not casting, full health); mouseover still reveals them
local function IsIdle()
	if InCombatLockdown() or UnitExists("target") or UnitCastingInfo("player") or UnitChannelInfo("player") then return false end
	local hp, maxHp = UnitHealth("player"), UnitHealthMax("player")
	if S.IsSecret(hp) or S.IsSecret(maxHp) then return true end
	return hp >= maxHp
end

function AB:UpdateFade(bar)
	local db = bar.db
	if db.inheritGlobalFade then
		fadeBars[bar] = true
		bar:SetAlpha(IsIdle() and (self.db.globalFadeAlpha or 0) or (db.alpha or 1))
	elseif db.mouseover then
		fadeBars[bar] = true
		bar:SetAlpha(0)
	else
		fadeBars[bar] = nil
		bar:SetAlpha(db.alpha or 1)
	end
end

local fadeTicker = CreateFrame("Frame")
local fadeElapsed = 0
fadeTicker:SetScript("OnUpdate", function(_, elapsed)
	fadeElapsed = fadeElapsed + elapsed
	if fadeElapsed < 0.1 then return end
	fadeElapsed = 0
	local cursor = GetCursorInfo()
	for bar in pairs(fadeBars) do
		local show = bar:IsMouseOver(4, -4, -4, 4) or cursor or AB.keybindMode or (SpellFlyout and SpellFlyout:IsShown() and SpellFlyout:IsMouseOver())
		local hidden = 0
		if bar.db.inheritGlobalFade then
			if not IsIdle() then show = true end
			hidden = AB.db.globalFadeAlpha or 0
		end
		local target = show and (bar.db.alpha or 1) or hidden
		local current = bar:GetAlpha()
		if math.abs(current - target) > 0.01 then
			bar:SetAlpha(current + (target - current) * 0.5)
		end
	end
end)

-- Cooldown-end watcher: refreshes icon visuals exactly when the swipe finishes
AB.cdWatch = {}
cdWatchFrame = CreateFrame("Frame")
cdWatchFrame:Hide()
cdWatchFrame:SetScript("OnUpdate", function()
	local now = GetTime()
	for btn in pairs(AB.cdWatch) do
		if not btn.cdEndsAt or now >= btn.cdEndsAt then
			AB.cdWatch[btn] = nil
			btn.cdEndsAt = nil
			if btn.hasAction then AB:UpdateCooldown(btn) AB:UpdateUsable(btn) end
		end
	end
	if not next(AB.cdWatch) then cdWatchFrame:Hide() end
end)

-- Range check ticker
local rangeElapsed = 0
local rangeFrame = CreateFrame("Frame")
rangeFrame:SetScript("OnUpdate", function(_, elapsed)
	rangeElapsed = rangeElapsed + elapsed
	if rangeElapsed < 0.2 then return end
	rangeElapsed = 0
	if not AB.db or not AB.db.useRangeColor then return end
	for _, btn in ipairs(AB.buttons) do
		if btn.hasAction and btn:IsVisible() then AB:UpdateUsable(btn) end
	end
end)

-- Pet & stance bars use OUR OWN secure buttons. Blizzard's StanceButton/PetActionButton
-- are protected; re-anchoring them taints Blizzard's UpdateShownButtons() which then gets
-- blocked in combat (ADDON_ACTION_BLOCKED flood). Own buttons = no taint, full styling.
function AB:CreateSpecialButton(bar, i, kind)
	local name = format("SentinelUI%sButton%d", kind == "pet" and "Pet" or "Stance", i)
	local btn = CreateFrame("CheckButton", name, bar, "SecureActionButtonTemplate")
	btn.bar, btn.index, btn.kind = bar, i, kind
	btn:SetSize(32, 32)
	btn.icon = btn:CreateTexture(name .. "Icon", "BACKGROUND", nil, 7)
	btn.cooldown = CreateFrame("Cooldown", name .. "Cooldown", btn, "CooldownFrameTemplate")
	btn.cooldown:SetFrameLevel(btn:GetFrameLevel() + 1)
	local textFrame = CreateFrame("Frame", nil, btn)
	textFrame:SetAllPoints()
	textFrame:SetFrameLevel(btn:GetFrameLevel() + 4)
	btn.HotKey = textFrame:CreateFontString(name .. "HotKey", "OVERLAY")
	btn.Count = textFrame:CreateFontString(name .. "Count", "OVERLAY")
	btn.Name = textFrame:CreateFontString(name .. "Name", "OVERLAY")
	for _, fs in ipairs({ btn.HotKey, btn.Count, btn.Name }) do S:SetFont(fs, S.media.numberFont, 11, "OUTLINE") fs:SetWordWrap(false) end

	if kind == "pet" then
		btn:SetAttribute("type", "pet")
		btn:SetAttribute("action", i)
		btn.bindCommand = "BONUSACTIONBUTTON" .. i
		btn:HookScript("OnClick", function(b, button)
			-- right click toggles autocast (not a protected action, safe from tainted code)
			if button == "RightButton" and TogglePetAutocast then TogglePetAutocast(b.index) end
		end)
	else
		-- a plain spell button can enter a form but cannot leave it on
		-- classic clients; a /cancelform macro toggles the active form off
		btn:SetAttribute("type", "macro")
		btn.bindCommand = "SHAPESHIFTBUTTON" .. i
	end
	btn:RegisterForClicks(self:ClickRegistration())
	btn:SetScript("OnEnter", function(b)
		if AB.keybindMode then return AB:KeybindOnEnter(b) end
		GameTooltip_SetDefaultAnchor(GameTooltip, b)
		if kind == "pet" then
			if not GetPetActionInfo(b.index) then return end
			GameTooltip:SetPetAction(b.index)
		else
			if not GetShapeshiftFormInfo(b.index) then return end
			GameTooltip:SetShapeshift(b.index)
		end
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", ButtonOnLeave)
	self:StyleButton(btn)
	return btn
end

function AB:CreateSpecialButtonBar(key, kind, count, title, getNum)
	local db = self.db[key]
	local bar = CreateFrame("Frame", "SentinelUI" .. key:gsub("^%l", string.upper), UIParent, "SecureHandlerStateTemplate")
	bar.key, bar.db, bar.buttons = key, db, {}
	bar.info = { title = title }
	bar.getNumButtons = getNum
	bar.visDefault = kind == "pet" and "[pet] show; hide" or "show"
	bar:SetFrameStrata("LOW")
	bar:SetSize(10, 10)
	local bg = CreateFrame("Frame", nil, bar, S.BackdropTemplate)
	bg:SetAllPoints()
	bg:SetFrameLevel(0)
	S:SetTemplate(bg, "Transparent")
	bar.bg = bg

	for i = 1, count do
		bar.buttons[i] = self:CreateSpecialButton(bar, i, kind)
	end
	S:CreateMover(bar, key, title, defaultPositions[key], "actionbars")
	self.bars[key] = bar
	self:LayoutBar(bar)
	if kind == "pet" then self:UpdatePetButtons(bar) else self:UpdateStanceButtons(bar) end
	return bar
end

function AB:UpdatePetButtons(bar)
	bar = bar or self.bars.barPet
	if not bar then return end
	local hasBar = (not PetHasActionBar) or PetHasActionBar() or not HasPetUI or HasPetUI()
	for _, btn in ipairs(bar.buttons) do
		local _, tex, isToken, active, allowed, enabled = GetPetActionInfo(btn.index)
		if S.IsSecret(tex) then tex = nil end
		if isToken and type(tex) == "string" then tex = _G[tex] or tex end
		if tex then btn.icon:SetTexture(tex) btn.icon:Show() else btn.icon:Hide() end
		btn:SetAlpha(tex and 1 or ((bar.db.showGrid or self.showGrid) and 1 or 0))
		btn:SetChecked(active and true or false)
		local bd = btn.suiBackdrop
		if bd then
			if enabled then bd:SetBackdropBorderColor(1, 0.8, 0.25)
			else bd:SetBackdropBorderColor(unpack(S.media.borderColor)) end
		end
		if GetPetActionCooldown then
			local start, duration = GetPetActionCooldown(btn.index)
			if start and duration and duration > 0 then
				pcall(btn.cooldown.SetCooldown, btn.cooldown, start, duration)
			else
				pcall(btn.cooldown.Clear, btn.cooldown)
			end
		end
	end
end

function AB:UpdateStanceButtons(bar)
	bar = bar or self.bars.barStance
	if not bar then return end
	local combat = InCombatLockdown()
	for i, btn in ipairs(bar.buttons) do
		if not combat and btn.pendingMacro then
			btn:SetAttribute("macrotext", btn.pendingMacro)
			btn.pendingMacro = nil
		end
		local icon, active, castable, spellID = GetShapeshiftFormInfo(i)
		-- secretAPI client: icon/spellID may arrive as secret values -> try
		-- texture APIs that return plain fileIDs
		if S.IsSecret(icon) then icon = nil end
		if not icon and spellID and not S.IsSecret(spellID) then
			icon = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID))
				or select(3, S.GetSpellInfo(spellID))
			if icon and S.IsSecret(icon) then icon = nil end
		end
		if icon and spellID then
			if btn.spellID ~= spellID then
				btn.spellID = spellID
				-- CastShapeshiftForm (the native toggle) is protected here and
				-- /run is forbidden; a cancelform+cast sequence re-casts right
				-- after the cancel. So: left click casts the form, right click
				-- runs /cancelform — deterministic, no protected calls.
				local name = GetSpellInfo and GetSpellInfo(spellID) or ""
				if type(name) == "table" then name = name.name or "" end
				local macro = format("/cancelform [btn:2]\n/cast [btn:1] %s", name)
				if combat then btn.pendingMacro = macro else btn:SetAttribute("macrotext", macro) end
			end
			btn.icon:SetTexture(icon)
			btn.icon:Show()
			btn:SetChecked(active and true or false)
			btn.icon:SetDesaturated(castable == false)
			btn:SetAlpha(1)
			if GetShapeshiftFormCooldown then
				local start, duration = GetShapeshiftFormCooldown(i)
				if start and duration and duration > 0 then
					pcall(btn.cooldown.SetCooldown, btn.cooldown, start, duration)
				else
					pcall(btn.cooldown.Clear, btn.cooldown)
				end
			end
		else
			btn:SetChecked(false)
			btn.icon:Hide()
			btn:SetAlpha((bar.db.showGrid or self.showGrid) and 1 or 0)
		end
	end
end

function AB:UpdateBlizzardButtonHotkeys(bar)
	for _, btn in ipairs(bar.buttons) do
		if btn.hotkey then
			local key = GetBindingKey(btn.bindCommand)
			btn.hotkey:SetText(key and self.db.hotkeyText and self:ShortKey(key) or "")
		end
	end
end

-- Micro menu & bag bar ------------------------------------------------------
local microNames = { "CharacterMicroButton", "ProfessionMicroButton", "PlayerSpellsMicroButton", "SpellbookMicroButton", "TalentMicroButton", "AchievementMicroButton", "QuestLogMicroButton", "HousingMicroButton", "GuildMicroButton", "SocialsMicroButton", "LFDMicroButton", "LFGMicroButton", "CollectionsMicroButton", "EJMicroButton", "PVPMicroButton", "WorldMapMicroButton", "StoreMicroButton", "MainMenuMicroButton", "HelpMicroButton" }

function AB:SetupMicroBar()
	local db = self.db.microbar
	if not db.enable then return end
	local holder = CreateFrame("Frame", "SentinelUIMicroBar", UIParent)
	holder:SetSize(200, 30)
	holder.db = db
	self.microBar = holder

	local buttons = {}
	for _, n in ipairs(microNames) do
		local b = _G[n]
		if b then buttons[#buttons + 1] = b end
	end
	holder.buttons = buttons

	local function Layout()
		if InCombatLockdown() then return S:RunOutOfCombat(Layout) end
		local size, spacing, perRow = db.buttonSize, db.spacing, db.buttonsPerRow
		local shown = {}
		for _, b in ipairs(buttons) do
			if b:GetParent() ~= holder then b:SetParent(holder) end
			if b:IsShown() or b.suiForceShow then shown[#shown + 1] = b end
		end
		local ratio = 1.35
		for i, b in ipairs(shown) do
			b:ClearAllPoints()
			b:SetSize(size, size * ratio)
			local col, row = (i - 1) % perRow, floor((i - 1) / perRow)
			b:SetPoint("TOPLEFT", holder, "TOPLEFT", col * (size + spacing), -row * (size * ratio + spacing))
		end
		local n = max(1, #shown)
		local cols, rows = min(perRow, n), ceil(n / perRow)
		holder:SetSize(cols * size + (cols - 1) * spacing, rows * size * ratio + (rows - 1) * spacing)
	end
	holder.Layout = Layout

	for _, b in ipairs(buttons) do
		if not b.suiStyled then
			b.suiStyled = true
			S:CreateBackdrop(b, "Default", nil, 2)
			b:HookScript("OnEnter", function() if db.mouseover then holder:SetAlpha(1) end end)
			b:HookScript("OnLeave", function() if db.mouseover and not holder:IsMouseOver() then holder:SetAlpha(0) end end)
		end
	end
	holder:SetScript("OnEnter", function() if db.mouseover then holder:SetAlpha(1) end end)
	holder:SetScript("OnLeave", function() if db.mouseover then holder:SetAlpha(0) end end)
	holder:EnableMouse(true)
	holder:SetAlpha(db.mouseover and 0 or (db.alpha or 1))

	Layout()
	for _, fn in ipairs({ "UpdateMicroButtonsParent", "MoveMicroButtons", "UpdateMicroButtons" }) do
		if _G[fn] then hooksecurefunc(fn, function() S:SafeCall("MicroBar", Layout) end) end
	end
	if MicroMenu and MicroMenu.Layout then
		hooksecurefunc(MicroMenu, "Layout", function() S:SafeCall("MicroBar", Layout) end)
	end
	S:CreateMover(holder, "microbar", L["Micro Menu"], defaultPositions.microbar, "actionbars")
end

function AB:SetupBagBar()
	local db = self.db.bagbar
	if not db.enable then return end
	local holder = CreateFrame("Frame", "SentinelUIBagBar", UIParent)
	holder:SetSize(200, 30)
	local list = { MainMenuBarBackpackButton }
	for i = 0, 3 do list[#list + 1] = _G["CharacterBag" .. i .. "Slot"] end
	list[#list + 1] = _G.CharacterReagentBag0Slot
	list[#list + 1] = _G.KeyRingButton
	-- Blizzard's keyring button OnShow expects its original bar context and errors
	-- when shown from our holder (e.g. when the AFK screen restores UIParent)
	local krb = _G.KeyRingButton
	if krb and not krb.suiSafeShow then
		krb.suiSafeShow = true
		local orig = krb:GetScript("OnShow")
		if orig then krb:SetScript("OnShow", function(...) pcall(orig, ...) end) end
	end
	local n = 0
	for _, b in ipairs(list) do
		if b then
			n = n + 1
			b:SetParent(holder)
			b:ClearAllPoints()
			b:SetSize(db.buttonSize, db.buttonSize)
			b:SetPoint("RIGHT", holder, "RIGHT", -((n - 1) * (db.buttonSize + db.spacing)), 0)
			local icon = b.icon or _G[b:GetName() .. "IconTexture"]
			for _, region in next, { b:GetRegions() } do
				if region:GetObjectType() == "Texture" and region ~= icon then region:Hide() region:SetAlpha(0) end
			end
			if icon then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) S:SetInside(icon, b, 0, 0) end
			local nt = b.GetNormalTexture and b:GetNormalTexture()
			if nt then nt:SetAlpha(0) end
			if b.IconBorder then b.IconBorder:Hide() end
			if b.SlotHighlightTexture then b.SlotHighlightTexture:SetAlpha(0) end
			local stock = b.Stock or _G[b:GetName() .. "Stock"]
			if stock then
				stock:ClearAllPoints()
				stock:SetPoint("BOTTOMRIGHT", -1, 1)
				S:SetFont(stock, S.media.numberFont, 10, "OUTLINE")
			end
			local hl = b.GetHighlightTexture and b:GetHighlightTexture()
			if hl then hl:SetTexture([[Interface\Buttons\WHITE8X8]]) hl:SetVertexColor(1, 1, 1, 0.15) S:SetInside(hl, b) end
			S:CreateBackdrop(b, "Default")
		end
	end
	holder:SetSize(max(1, n) * (db.buttonSize + db.spacing) - db.spacing, db.buttonSize)
	if db.mouseover then
		holder:SetAlpha(0)
		holder:EnableMouse(true)
		holder:SetScript("OnUpdate", function(h) h:SetAlpha(h:IsMouseOver(4, -4, -4, 4) and 1 or 0) end)
	end
	S:CreateMover(holder, "bagbar", L["Bag Bar"], defaultPositions.bagbar, "actionbars")
end

-- Hide Blizzard bars --------------------------------------------------------
function AB:HideBlizzard()
	local hidden = S.hiddenFrame
	local frames = {
		"MainMenuBar", "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft", "MultiBarRight",
		"MultiBar5", "MultiBar6", "MultiBar7", "MainMenuBarArtFrame", "MainMenuBarArtFrameBackground", "OverrideActionBar",
		"PossessActionBar", "PossessBarFrame", "StanceBar", "StanceBarFrame", "PetActionBar", "PetActionBarFrame",
		"MultiCastActionBarFrame", "MainMenuBarVehicleLeaveButton", "VehicleMenuBar", "BonusActionBarFrame",
		"MicroButtonAndBagsBar", "MicroMenuContainer", "MicroMenu",
		"StatusTrackingBarManager", "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer",
		"MainMenuExpBar", "ReputationWatchBar", "MainMenuBarMaxLevelBar", "ShapeshiftBarFrame",
	}
	-- Blizzard's pet/stance frames must NOT keep their events: their UpdateState/SetShown
	-- on protected buttons would get taint-blocked in combat. Our own secure buttons
	-- handle pet/stance actions; the hidden Blizzard buttons stay alive for keybinds.
	local keepEvents = {}
	for _, n in ipairs(frames) do
		local f = _G[n]
		if f and not (n == "MultiCastActionBarFrame" and S.myClass == "SHAMAN" and not S.isRetail) then
			if f.UnregisterAllEvents and not keepEvents[n] then f:UnregisterAllEvents() end
			-- state drivers keep running after UnregisterAllEvents: Blizzard's
			-- StanceBar driver calls protected SetShown on its buttons and gets
			-- taint-blocked once we parked the frame
			if UnregisterStateDriver then
				pcall(UnregisterStateDriver, f, "visibility")
				pcall(UnregisterStateDriver, f, "stance")
				pcall(UnregisterStateDriver, f, "page")
			end
			f:SetParent(hidden)
			if f.SetScript and n ~= "StatusTrackingBarManager" then pcall(f.SetScript, f, "OnShow", nil) end
			f.ignoreFramePositionManager = true
			pcall(f.Hide, f)
		end
	end
	-- Blizzard's own action buttons stay alive (keybind fallback) but invisible.
	for i = 1, 12 do
		for _, p in ipairs({ "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarLeftButton", "MultiBarRightButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button", "OverrideActionBarButton" }) do
			local b = _G[p .. i]
			if b then
				b:SetParent(hidden)
				if b.UnregisterAllEvents then b:UnregisterAllEvents() end
				b:SetAttribute("statehidden", true)
				b:Hide()
			end
		end
	end
	-- micro menu / bag slot buttons: their parent frame differs per client and
	-- MicroButtonAndBagsBar may not exist at all. When our own replacement bars
	-- are disabled, park the raw buttons on the hidden frame so they never show.
	local db = self.db
	if not (db and db.microbar and db.microbar.enable) then
		-- if a container exists it was parked on the hidden frame above: keep its
		-- child buttons inside (pulling them out orphans them and breaks
		-- Blizzard's container Layout -> "attempt to compare nil"). Standalone
		-- buttons not parented to any container still get parked individually.
		local container = _G.MicroMenuContainer or _G.MicroMenu or _G.MicroButtonAndBagsBar
		for _, n in ipairs(microNames) do
			local b = _G[n]
			if b then
				if not container or b:GetParent() ~= container then
					b:SetParent(hidden)
				end
				b:Hide()
			end
		end
	end
	if not (db and db.bagbar and db.bagbar.enable) then
		local bagBtns = { "MainMenuBarBackpackButton", "CharacterReagentBag0Slot", "KeyRingButton" }
		for i = 0, 3 do bagBtns[#bagBtns + 1] = "CharacterBag" .. i .. "Slot" end
		for _, n in ipairs(bagBtns) do
			local b = _G[n]
			if b then b:SetParent(hidden) b:Hide() end
		end
	end
	-- the micro menu addon can load on demand; park its container when it arrives
	if not (_G.MicroMenuContainer or _G.MicroMenu) then
		self:RegisterEvent("ADDON_LOADED", function(_, _, addon)
			if addon == "Blizzard_MicroMenu" or addon == "Blizzard_MicroMenu_VANILLA" then
				local c = _G.MicroMenuContainer or _G.MicroMenu
				if c then
					if c.UnregisterAllEvents then c:UnregisterAllEvents() end
					c:SetParent(hidden)
					c:Hide()
				end
			end
		end)
	end
	if ActionBarController then ActionBarController:UnregisterAllEvents() ActionBarController:RegisterEvent("SETTINGS_LOADED") ActionBarController:RegisterEvent("UPDATE_EXTRA_ACTIONBAR") end
	if ActionBarButtonEventsFrame and S.isRetail then
		ActionBarButtonEventsFrame:UnregisterEvent("ACTIONBAR_SLOT_CHANGED")
		ActionBarButtonEventsFrame:UnregisterEvent("UPDATE_BINDINGS")
	end
	if MainMenuBar and MainMenuBar.SetPositionForStatusBars then
		MainMenuBar.SetPositionForStatusBars = function() end
	end
	-- Retail: talent change / edit mode may try to re-show the bars
	if S.isRetail and Settings and Settings.SetValue then
		-- nothing: edit mode settings stay untouched on purpose
	end
end

-- Vehicle / extra buttons ---------------------------------------------------
function AB:SetupVehicleLeave()
	if not (S.isRetail or S.isWrath or S.isCata or S.isMists) then return end
	local btn = CreateFrame("Button", "SentinelUIVehicleLeave", UIParent, "SecureHandlerClickTemplate, SecureActionButtonTemplate")
	btn:SetSize(32, 32)
	btn:SetAttribute("type", "macro")
	btn:SetAttribute("macrotext", "/leavevehicle")
	btn:RegisterForClicks("AnyUp")
	local tex = btn:CreateTexture(nil, "ARTWORK")
	tex:SetTexture([[Interface\Vehicles\UI-Vehicles-Button-Exit-Up]])
	tex:SetTexCoord(0.14, 0.86, 0.14, 0.86)
	S:SetInside(tex, btn, 0, 0)
	S:CreateBackdrop(btn, "Default")
	S:AddHover(btn)
	RegisterStateDriver(btn, "visibility", "[canexitvehicle] show; hide")
	S:CreateMover(btn, "vehicleLeave", L["Leave Vehicle"], { "BOTTOMLEFT", "SentinelUIMover_bar1", "BOTTOMRIGHT", 46, 0 }, "actionbars")
end

function AB:SetupExtraButtons()
	local container = _G.ExtraAbilityContainer or _G.ExtraActionBarFrame
	if container then
		local holder = CreateFrame("Frame", "SentinelUIExtraHolder", UIParent)
		holder:SetSize(64, 64)
		S:CreateMover(holder, "extraAction", L["Extra Action Button"], { "BOTTOM", "UIParent", "BOTTOM", 0, 230 }, "actionbars")
		container:SetParent(holder)
		container:ClearAllPoints()
		container:SetPoint("CENTER", holder)
		container.ignoreFramePositionManager = true
		hooksecurefunc(container, "SetPoint", function(f, _, rel)
			if rel ~= holder and not InCombatLockdown() then f:ClearAllPoints() f:SetPoint("CENTER", holder) end
		end)
		if UIParentBottomManagedFrameContainer and UIParentBottomManagedFrameContainer.RemoveManagedFrame then
			pcall(UIParentBottomManagedFrameContainer.RemoveManagedFrame, UIParentBottomManagedFrameContainer, container)
		end
	end
	local zone = _G.ZoneAbilityFrame
	if zone and zone ~= container and zone:GetParent() ~= container then
		local holder = CreateFrame("Frame", "SentinelUIZoneHolder", UIParent)
		holder:SetSize(52, 52)
		S:CreateMover(holder, "zoneAbility", L["Zone Ability"], { "BOTTOM", "UIParent", "BOTTOM", -150, 230 }, "actionbars")
		zone:SetParent(holder)
		zone:ClearAllPoints()
		zone:SetPoint("CENTER", holder)
	end
end

-- Keybinds ------------------------------------------------------------------
function AB:ApplyOverrideBindings()
	if InCombatLockdown() then return S:RunOutOfCombat(self.ApplyOverrideBindings, self) end
	for _, bar in pairs(self.bars) do
		if bar.info and bar.info.bind and bar.buttons[1] and bar.buttons[1].bindCommand and bar.buttons[1].bindCommand:sub(1, 5) ~= "CLICK" then
			ClearOverrideBindings(bar)
			for _, btn in ipairs(bar.buttons) do
				if btn.bindCommand then
					for k = 1, select("#", GetBindingKey(btn.bindCommand)) do
						local key = select(k, GetBindingKey(btn.bindCommand))
						if key and key ~= "" then SetOverrideBindingClick(bar, false, key, btn:GetName(), "LeftButton") end
					end
				end
			end
		end
	end
end

local bindFrame
-- binding command for buttons outside the SentinelUI bars (native Blizzard
-- buttons resolve via their name; ours carry bindCommand)
local BLIZZARD_BIND = {
	ActionButton = "ACTIONBUTTON",
	MultiBarBottomLeftButton = "MULTIACTIONBAR1BUTTON",
	MultiBarBottomRightButton = "MULTIACTIONBAR2BUTTON",
	MultiBarRightButton = "MULTIACTIONBAR3BUTTON",
	MultiBarLeftButton = "MULTIACTIONBAR4BUTTON",
	PetActionButton = "BONUSACTIONBUTTON",
	ShapeshiftButton = "SHAPESHIFTBUTTON",
	StanceButton = "SHAPESHIFTBUTTON",
}
local function BindCommand(btn)
	if btn.bindCommand then return btn.bindCommand end
	local name = btn.GetName and btn:GetName()
	local prefix, idx = name and name:match("^(%a+)(%d+)$")
	local cmd = prefix and BLIZZARD_BIND[prefix]
	if cmd then return cmd .. idx end
end
function AB:KeybindOnEnter(btn)
	if not self.keybindMode then return end
	local cmd = BindCommand(btn)
	if not cmd then return end
	bindFrame.button = btn
	bindFrame:ClearAllPoints()
	bindFrame:SetAllPoints(btn)
	bindFrame:Show()
	GameTooltip:SetOwner(bindFrame, "ANCHOR_TOP")
	GameTooltip:AddLine(btn:GetName() or "?", S.accent.r, S.accent.g, S.accent.b)
	local keys = { GetBindingKey(cmd) }
	GameTooltip:AddLine(#keys > 0 and table.concat(keys, ", ") or L["No binding"], 1, 1, 1)
	GameTooltip:AddLine(L["Press a key to bind, ESC to clear."], 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

local function BindKey(key)
	local btn = bindFrame.button
	local cmd = btn and BindCommand(btn)
	if not btn or not cmd then return end
	if key == "ESCAPE" then
		for _, k in ipairs({ GetBindingKey(cmd) }) do SetBinding(k) end
		S:Print(format(L["Bindings cleared for %s"], btn:GetName()))
	else
		if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" or key == "UNKNOWN" or key == "LeftButton" or key == "RightButton" then return end
		if key == "MiddleButton" then key = "BUTTON3" end
		if key:find("^Button%d") then key = key:upper() end
		local mod = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") .. (IsShiftKeyDown() and "SHIFT-" or "") .. (IsMetaKeyDown and IsMetaKeyDown() and "META-" or "")
		SetBinding(mod .. key, cmd)
		S:Print(format(L["%s bound to %s"], mod .. key, btn:GetName()))
	end
	AB:KeybindOnEnter(btn)
end

function AB:ToggleKeybindMode()
	if InCombatLockdown() then S:Print(ERR_NOT_IN_COMBAT) return end
	if not bindFrame then
		bindFrame = CreateFrame("Button", "SentinelUIKeybindFrame", UIParent)
		bindFrame:SetFrameStrata("DIALOG")
		bindFrame:EnableMouse(true)
		bindFrame:EnableKeyboard(true)
		bindFrame:EnableMouseWheel(true)
		bindFrame:RegisterForClicks("AnyUp")
		local t = bindFrame:CreateTexture(nil, "OVERLAY")
		t:SetAllPoints()
		t:SetColorTexture(S.accent.r, S.accent.g, S.accent.b, 0.3)
		bindFrame:SetScript("OnKeyDown", function(_, key) S:SafeCall("Keybind", BindKey, key) end)
		bindFrame:SetScript("OnMouseWheel", function(_, d) S:SafeCall("Keybind", BindKey, d > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN") end)
		bindFrame:SetScript("OnClick", function(_, b) if b ~= "LeftButton" and b ~= "RightButton" then S:SafeCall("Keybind", BindKey, b) end end)
		bindFrame:SetScript("OnLeave", function(f) f:Hide() GameTooltip:Hide() end)
		StaticPopupDialogs["SENTINELUI_KEYBIND"] = {
			text = L["Keybind mode: hover a button and press a key. ESC clears the binding."],
			button1 = SAVE, button2 = CANCEL,
			OnAccept = function() SaveBindings(GetCurrentBindingSet()) AB:ToggleKeybindMode() end,
			OnCancel = function() LoadBindings(GetCurrentBindingSet()) AB:ToggleKeybindMode() end,
			timeout = 0, whileDead = true, hideOnEscape = false,
		}
	end
	self.keybindMode = not self.keybindMode
	if self.keybindMode then
		StaticPopup_Show("SENTINELUI_KEYBIND")
		for bar in pairs(fadeBars) do bar:SetAlpha(1) end
	else
		bindFrame:Hide()
		StaticPopup_Hide("SENTINELUI_KEYBIND")
	end
end

-- Events --------------------------------------------------------------------
function AB:ACTIONBAR_SLOT_CHANGED(_, slot)
	if slot == 0 or not slot then
		self:ForEachButton(self.UpdateButton)
	elseif self.slotButtons[slot] then
		for btn in pairs(self.slotButtons[slot]) do self:UpdateButton(btn) end
	end
end

function AB:UpdateAllStates()
	for _, btn in ipairs(self.buttons) do
		if btn.action then self:UpdateState(btn) self:UpdateUsable(btn) end
	end
end

function AB:UpdateAllCooldowns()
	for _, btn in ipairs(self.buttons) do
		if btn.hasAction then self:UpdateCooldown(btn) self:UpdateCount(btn) end
	end
	if self.bars.barStance then self:UpdateStanceButtons() end
	if self.bars.barPet then self:UpdatePetButtons() end
end

function AB:UPDATE_BINDINGS()
	for _, btn in ipairs(self.buttons) do self:UpdateHotkey(btn) end
	for _, key in ipairs({ "barPet", "barStance" }) do
		if self.bars[key] then self:UpdateBlizzardButtonHotkeys(self.bars[key]) end
	end
	self:ApplyOverrideBindings()
end

function AB:ACTIONBAR_SHOWGRID()
	self.showGrid = true
	self:ForEachButton(self.UpdateGridVisibility)
end

function AB:ACTIONBAR_HIDEGRID()
	self.showGrid = false
	self:ForEachButton(self.UpdateGridVisibility)
end

function AB:PLAYER_ENTERING_WORLD()
	self:ForEachButton(self.UpdateButton)
	self:UPDATE_BINDINGS()
	if self.bars.barStance then self:LayoutBar(self.bars.barStance) self:UpdateStanceButtons() end
	if self.bars.barPet then self:UpdatePetButtons() end
end

function AB:CVAR_UPDATE(_, name)
	if name == "ActionButtonUseKeyDown" or name == "ACTION_BUTTON_USE_KEY_DOWN" then
		S:RunOutOfCombat(function() for _, b in ipairs(AB.buttons) do b:RegisterForClicks(AB:ClickRegistration()) end end)
	elseif name == "lockActionBars" or name == "LOCK_ACTIONBAR" then
		S:RunOutOfCombat(function() for _, bar in pairs(AB.bars) do bar:SetAttribute("locked", GetCVarBool("lockActionBars")) end end)
	end
end

function AB:UpdatePetBar()
	self:UpdatePetButtons()
	self:UpdateStanceButtons()
end

function AB:Update()
	for key, bar in pairs(self.bars) do
		bar.db = self.db[key]
		self:LayoutBar(bar)
		for _, btn in ipairs(bar.buttons) do self:StyleButtonText(btn, bar.db) end
	end
	-- push the key-down CVar so every press (mouse + keybind) fires instantly
	if self.db.keyDown then pcall(SetCVar, "ActionButtonUseKeyDown", "1") end
	S:RunOutOfCombat(function() for _, b in ipairs(AB.buttons) do b:RegisterForClicks(AB:ClickRegistration()) end end)
	self:PLAYER_ENTERING_WORLD()
end

function AB:Initialize()
	-- one-time migrations for the micro/bag bars (before HideBlizzard so the
	-- disabled state already applies when Blizzard frames get hidden)
	if not self.db._microMig then
		self.db._microMig = true
		self.db.microbar.mouseover = false
		self.db.bagbar.mouseover = false
		local mv = S.db.profile.movers
		if mv then mv.microbar = nil mv.bagbar = nil end
	end
	-- user asked for these bars to be gone entirely: disable them once
	if not self.db._microMig2 then
		self.db._microMig2 = true
		self.db.microbar.enable = false
		self.db.bagbar.enable = false
	end
	if self.private.hideBlizzard then self:HideBlizzard() end

	-- Blizzard's global UpdateFlyout nil-calls a missing helper on classic
	-- clients and fires from many code paths; wrap it so the error is swallowed
	if type(_G.UpdateFlyout) == "function" and not _G.suiFlyoutWrapped then
		_G.suiFlyoutWrapped = true
		local orig = _G.UpdateFlyout
		_G.UpdateFlyout = function(...) return S:SafeCall("ActionBars:Flyout", orig, ...) end
	end

	for key, info in pairs(barInfo) do
		if not info.retailOnly or S.isRetail then self:CreateBar(key) end
	end

	self:CreateSpecialButtonBar("barPet", "pet", NUM_PET_ACTION_SLOTS or 10, L["Pet Bar"])
	self:CreateSpecialButtonBar("barStance", "stance", 10, L["Stance Bar"], function() return GetNumShapeshiftForms() or 0 end)
	self:SetupBagBar()
	self:SetupMicroBar()
	self:SetupVehicleLeave()
	if S.isRetail then self:SetupExtraButtons() end

	self:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("UPDATE_BINDINGS")
	self:RegisterEvent("ACTIONBAR_SHOWGRID")
	self:RegisterEvent("ACTIONBAR_HIDEGRID")
	self:RegisterEvent("CVAR_UPDATE")
	for _, e in ipairs({ "ACTIONBAR_UPDATE_STATE", "ACTIONBAR_UPDATE_USABLE", "SPELL_UPDATE_USABLE", "PLAYER_TARGET_CHANGED", "UNIT_INVENTORY_CHANGED", "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL", "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT", "UPDATE_SHAPESHIFT_FORM", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "PET_BAR_UPDATE" }) do
		self:RegisterEvent(e, "UpdateAllStates")
	end
	for _, e in ipairs({ "ACTIONBAR_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "BAG_UPDATE", "LOSS_OF_CONTROL_ADDED", "LOSS_OF_CONTROL_UPDATE" }) do
		self:RegisterEvent(e, "UpdateAllCooldowns")
	end
	self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function() AB:ForEachButton(AB.UpdateBorder) end)
	self:RegisterEvent("UPDATE_SHAPESHIFT_FORMS", function()
		AB:UpdateStanceButtons()
		if AB.bars.barStance then S:SafeCall("ActionBars:Relayout", AB.LayoutBar, AB, AB.bars.barStance) end
	end)
	self:RegisterEvent("UPDATE_SHAPESHIFT_FORM", function() AB:UpdateStanceButtons() end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function() AB:UpdateStanceButtons() end)
	pcall(self.RegisterEvent, self, "UPDATE_SHAPESHIFT_USABLE", function() AB:UpdateStanceButtons() end)
	pcall(self.RegisterEvent, self, "PET_BAR_UPDATE_USABLE", function() AB:UpdatePetButtons() end)
	pcall(self.RegisterEvent, self, "PET_BAR_SHOWGRID", function() AB:UpdatePetButtons() end)
	pcall(self.RegisterEvent, self, "PET_BAR_HIDEGRID", function() AB:UpdatePetButtons() end)
	self:RegisterEvent("PET_BAR_UPDATE", "UpdatePetBar")
	self:RegisterUnitEvent("UNIT_PET", "UpdatePetBar", "player")
	self:RegisterEvent("PET_BAR_UPDATE_COOLDOWN", "UpdatePetBar")
	self:RegisterEvent("UPDATE_MACROS", function() AB:ForEachButton(AB.UpdateButton) end)
	self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
	self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")

	-- keybind mode on native Blizzard buttons too (for users keeping them
	-- visible or using a hybrid setup)
	if not self.blizzKbHooked then
		self.blizzKbHooked = true
		for prefix in pairs(BLIZZARD_BIND) do
			for i = 1, 12 do
				local b = _G[prefix .. i]
				if b then b:HookScript("OnEnter", function(btn) if AB.keybindMode then AB:KeybindOnEnter(btn) end end) end
			end
		end
	end

	self:PLAYER_ENTERING_WORLD()
end
