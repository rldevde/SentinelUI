-- GuildHubWidgets: the single set of UI building blocks used by every GuildHub
-- tab (buttons, checkboxes, edit boxes, list rows, small helpers). Buttons and
-- list rows are pooled across re-renders so clicking around does not pile up
-- frames, and stale scripts can never survive a re-use.
local _, ns = ...
local S = ns.S
local L = S.L
local GH = S:GetModule("GuildHub")

local CreateFrame, UIParent = CreateFrame, UIParent
local ipairs, pairs, tremove, type, unpack = ipairs, pairs, table.remove, type, unpack
local format, upper, floor, time = string.format, string.upper, math.floor, time

local W = {}
GH.W = W

local ACC = S.accentHex or "ffcc00"
local BLANK = "Interface\\Buttons\\WHITE8X8"
local SCRIPTS = { "OnClick", "OnDoubleClick", "OnEnter", "OnLeave", "OnMouseDown", "OnMouseUp" }

local btnPool, btnUsed, rowPool, rowUsed = {}, {}, {}, {}

local function Reset(f)
	f:Hide()
	f:ClearAllPoints()
	for _, ev in ipairs(SCRIPTS) do f:SetScript(ev, nil) end
	f:SetParent(UIParent)
end

-- called by GH:RenderTab before a page is rebuilt
function W.ReleaseAll()
	for i = #btnUsed, 1, -1 do
		Reset(btnUsed[i])
		btnPool[#btnPool + 1] = btnUsed[i]
		btnUsed[i] = nil
	end
	for i = #rowUsed, 1, -1 do
		local r = rowUsed[i]
		Reset(r)
		rowPool[#rowPool + 1] = r
		rowUsed[i] = nil
	end
end

local function Setup(b, parent, w, h, label)
	b:ClearAllPoints()
	b:SetSize(w, h)
	b:SetFrameLevel(parent:GetFrameLevel() + 2)
	if b.suiBackdrop then
		b.suiBackdrop:SetFrameLevel(b:GetFrameLevel() - 1)
		b.suiBackdrop:SetBackdropBorderColor(unpack(S.media.borderColor or { 0.2, 0.2, 0.2, 1 }))
	end
	b.fs:SetText(label)
	b.fs:SetTextColor(1, 1, 1)
	b:Enable()
end

local function NewBtn(parent)
	local b = CreateFrame("Button", nil, parent)
	b:RegisterForClicks("AnyUp")
	S:CreateBackdrop(b, "Default")
	b.fs = S:FontString(b, 11, nil, S.media.font, nil, "CENTER")
	b.fs:SetPoint("CENTER")
	S:AddHover(b)
	return b
end

-- pooled: released automatically on the next tab render
function W.Btn(parent, w, h, label)
	local b = tremove(btnPool)
	if b then
		b:SetParent(parent)
		b:Show()
	else
		b = NewBtn(parent)
	end
	Setup(b, parent, w, h, label)
	btnUsed[#btnUsed + 1] = b
	return b
end

-- not pooled: for dialogs that outlive a tab render
function W.StaticBtn(parent, w, h, label)
	local b = NewBtn(parent)
	Setup(b, parent, w, h, label)
	return b
end

-- mark a selector button as the active one (accent text + border, kept after hover)
function W.SelBtn(b, on)
	if not on then return end
	b.fs:SetTextColor(S.accent.r, S.accent.g, S.accent.b)
	if b.suiBackdrop then b.suiBackdrop:SetBackdropBorderColor(S.accent.r, S.accent.g, S.accent.b, 0.9) end
	if not b.suiSelHook then
		b.suiSelHook = true
		b:HookScript("OnLeave", function()
			if b.suiBackdrop and b.fs:GetTextColor() == S.accent.r then
				b.suiBackdrop:SetBackdropBorderColor(S.accent.r, S.accent.g, S.accent.b, 0.9)
			end
		end)
	end
end

function W.Checkbox(parent, label, checked, onClick)
	local cb = CreateFrame("CheckButton", nil, parent)
	cb:SetSize(16, 16)
	S:CreateBackdrop(cb, "Default", nil, 0)
	cb:SetCheckedTexture(BLANK)
	local tick = cb:GetCheckedTexture()
	tick:ClearAllPoints()
	tick:SetPoint("TOPLEFT", 3, -3)
	tick:SetPoint("BOTTOMRIGHT", -3, 3)
	tick:SetVertexColor(S.accent.r, S.accent.g, S.accent.b)
	cb:SetDisabledCheckedTexture(BLANK)
	local dtick = cb:GetDisabledCheckedTexture()
	if dtick then
		dtick:ClearAllPoints()
		dtick:SetPoint("TOPLEFT", 3, -3)
		dtick:SetPoint("BOTTOMRIGHT", -3, 3)
		dtick:SetVertexColor(0.4, 0.4, 0.4)
	end
	S:AddHover(cb)
	cb:SetChecked(checked and true or false)
	cb.fs = S:FontString(cb, 11, nil, S.media.font, nil, "LEFT")
	cb.fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
	cb.fs:SetText(label)
	cb:SetScript("OnClick", function(c) onClick(c:GetChecked() and true or false) end)
	-- the label is a plain region on the backdrop, so a transparent button over
	-- box + label makes the whole thing clickable (and toggles the check itself)
	local hit = CreateFrame("Button", nil, parent)
	hit:SetPoint("TOPLEFT", cb) hit:SetPoint("BOTTOMLEFT", cb)
	hit:SetWidth(16 + (cb.fs:GetStringWidth() or 0) + 6)
	hit:SetFrameLevel(cb:GetFrameLevel() + 2)
	hit:SetScript("OnClick", function()
		if cb.IsEnabled and not cb:IsEnabled() then return end
		cb:SetChecked(not cb:GetChecked())
		local oc = cb:GetScript("OnClick")
		if oc then oc(cb) end
	end)
	cb.hit = hit
	return cb
end

function W.Edit(parent, w, h, placeholder)
	local e = CreateFrame("EditBox", nil, parent)
	e:SetSize(w, h)
	e:SetAutoFocus(false)
	e:SetFontObject("GameFontHighlight")
	S:SkinEditBox(e, h)
	if placeholder then
		e.ph = S:FontString(e, 11, nil, S.media.font, nil, "LEFT")
		e.ph:SetPoint("LEFT", 6, 0)
		e.ph:SetText("|cff777777" .. placeholder .. "|r")
		e.phKey = placeholder
		e:SetScript("OnTextChanged", function(s) s.ph:SetShown(s:GetText() == "") end)
		-- a search box re-renders its tab on every keystroke; give focus back to the fresh one
		if W.refocus == placeholder then
			W.refocus = nil
			C_Timer.After(0, function()
				if e:IsVisible() then
					e:SetFocus()
					e:SetCursorPosition(#(e:GetText() or ""))
				end
			end)
		end
	end
	e:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
	return e
end

-- live-typing handler: fires only for real keystrokes, keeps placeholder state
function W.OnType(e, fn)
	e:SetScript("OnTextChanged", function(s, user)
		if s.ph then s.ph:SetShown(s:GetText() == "") end
		if not user then return end
		W.refocus = s.phKey
		fn(s)
	end)
end

function W.Header(parent, text)
	local fs = S:FontString(parent, 12, "OUTLINE", S.media.font, nil, "LEFT")
	fs:SetText("|cff" .. ACC .. upper(text) .. "|r")
	return fs
end

function W.ClassColor(name)
	local e = GH._Roster()[name]
	local c = e and e.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class]
	if c then return format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, name) end
	return name
end

function W.Ago(t)
	if not t then return "?" end
	local d = time() - t
	if d < 60 then return L["just now"] end
	if d < 3600 then return format(L["%d min ago"], floor(d / 60)) end
	if d < 86400 then return format(L["%d h ago"], floor(d / 3600)) end
	return format(L["%d d ago"], floor(d / 86400))
end

function W.SendWhisper(text, who)
	if SendChatMessage then SendChatMessage(text, "WHISPER", nil, who) end
end

function W.Whisper(name)
	if ChatFrame_OpenChat then ChatFrame_OpenChat("/w " .. name .. " ") end
end

function W.Invite(name)
	if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(name) elseif InviteUnit then InviteUnit(name) end
end

function W.ListRows(page, topY, rowH, n, fill)
	local rows = {}
	for i = 1, n do
		local r = tremove(rowPool)
		if r then
			r:SetParent(page)
		else
			r = CreateFrame("Button", nil, page)
			r:RegisterForClicks("AnyUp")
			r.bg = r:CreateTexture(nil, "BACKGROUND")
			r.bg:SetAllPoints()
			r.fss = {}
		end
		r:SetFrameLevel(page:GetFrameLevel() + 1)
		r:SetHeight(rowH)
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", 0, topY - (i - 1) * rowH)
		r:SetPoint("TOPRIGHT", 0, topY - (i - 1) * rowH)
		r.bg:SetColorTexture(1, 1, 1, (i % 2 == 1) and 0.03 or 0)
		for _, fs in pairs(r.fss) do fs:Hide() end
		for _, ch in ipairs({ r:GetChildren() }) do ch:Hide() end
		for _, ev in ipairs(SCRIPTS) do r:SetScript(ev, nil) end
		rowUsed[#rowUsed + 1] = r
		rows[i] = r
		fill(r, i)
		r:Show()
	end
	return rows
end

function W.RowFS(r, key, x, size, justify)
	if type(size) == "string" then size, justify = nil, size end
	local fs = r.fss[key]
	if not fs then
		fs = S:FontString(r, size or 11, nil, S.media.font, nil, justify or "LEFT")
		r.fss[key] = fs
	end
	fs:ClearAllPoints()
	if justify == "RIGHT" then fs:SetPoint("RIGHT", r, "RIGHT", x, 0)
	else fs:SetPoint("LEFT", r, "LEFT", x, 0) end
	fs:SetJustifyH(justify or "LEFT")
	fs:Show()
	return fs
end
