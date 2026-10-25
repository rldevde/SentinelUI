-- ConfigShare: /suiexport and /suiimport. Serializes the current AceDB
-- profile into a copyable string (and back), so a config can be moved
-- between characters, accounts or machines.
local _, ns = ...
local S = ns.S
local L = S.L
local CS = S:NewModule("ConfigShare", "configshare")

local ser = LibStub("AceSerializer-3.0")

StaticPopupDialogs.SENTINELUI_EXPORT = {
	text = (L["Copy your config string"]) or "Copy your config string",
	button1 = CLOSE,
	hasEditBox = true,
	editBoxWidth = 340,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
	maxLetters = 0,
	OnShow = function(d)
		local eb = d.editBox or d.EditBox
		if not eb then return end
		eb:SetMaxLetters(0)
		eb:SetText(CS.exportString or "")
		eb:HighlightText()
		eb:SetFocus()
	end,
	EditBoxOnEscapePressed = function(b) b:GetParent():Hide() end,
}

StaticPopupDialogs.SENTINELUI_IMPORT = {
	text = (L["Paste a config string"]) or "Paste a config string",
	button1 = L["Import"] or "Import",
	button2 = CANCEL,
	hasEditBox = true,
	editBoxWidth = 340,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
	maxLetters = 0,
	OnShow = function(d)
		local eb = d.editBox or d.EditBox
		if eb then eb:SetMaxLetters(0) eb:SetText("") eb:SetFocus() end
	end,
	OnAccept = function(d)
		local eb = d.editBox or d.EditBox
		CS:Import(eb and eb:GetText())
	end,
	EditBoxOnEscapePressed = function(b) b:GetParent():Hide() end,
}

function CS:Export()
	if not (S.db and S.db.profile) then
		S:Print(L["No profile loaded"] or "No profile loaded")
		return
	end
	self.exportString = ser:Serialize(S.db.profile)
	StaticPopup_Show("SENTINELUI_EXPORT")
end

local function deepCopy(src, dst)
	wipe(dst)
	for k, v in pairs(src) do
		if type(v) == "table" then
			dst[k] = {}
			deepCopy(v, dst[k])
		else
			dst[k] = v
		end
	end
end

function CS:Import(str)
	if not str or str == "" then
		S:Print(L["Nothing to import"] or "Nothing to import")
		return
	end
	local ok, data = ser:Deserialize(str)
	if not ok or type(data) ~= "table" then
		S:Print(L["Invalid config string"] or "Invalid config string")
		return
	end
	deepCopy(data, S.db.profile)
	S:Print(L["Config imported - reloading UI"] or "Config imported - reloading UI")
	C_Timer.After(1, ReloadUI)
end

function CS:Initialize()
	SLASH_SUIEXPORT1 = "/suiexport"
	SlashCmdList.SUIEXPORT = function() CS:Export() end
	SLASH_SUIIMPORT1 = "/suiimport"
	SlashCmdList.SUIIMPORT = function() StaticPopup_Show("SENTINELUI_IMPORT") end
end
