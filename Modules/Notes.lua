-- Notes: per-player notes, account-wide. Shown as a line in the unit tooltip.
-- /suinote <name> <text>  - set a note
-- /suinote <name>        - remove the note
-- /suinote               - list all notes
local _, ns = ...
local S = ns.S
local L = S.L
local NT = S:NewModule("Notes", "notes")

local function Store()
	S.db.global.playerNotes = S.db.global.playerNotes or {}
	return S.db.global.playerNotes
end

local function FullName(unit)
	if GetUnitName then
		local n = GetUnitName(unit, true)
		if n and n ~= "" then return n end
	end
	local name, realm = UnitName(unit)
	if not name then return end
	if (not realm or realm == "") and GetRealmName then realm = GetRealmName() end
	return realm and realm ~= "" and (name .. "-" .. realm) or name
end

local function TooltipNote(tt)
	if tt ~= GameTooltip or (tt.IsForbidden and tt:IsForbidden()) then return end
	local _, unit = tt:GetUnit()
	if not unit or IsSecret(unit) or not UnitIsPlayer(unit) then return end
	local name = FullName(unit)
	if not name or IsSecret(name) then return end
	local note = Store()[name]
	if note and note ~= "" then
		tt:AddDoubleLine(L["Note"] .. ":", "|cffffd700" .. note .. "|r", 0.6, 0.6, 0.6, 1, 1, 1)
		tt:Show()
	end
end

local function Cmd(msg)
	msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local store = Store()
	if msg == "" then
		local n = 0
		for name, note in pairs(store) do
			n = n + 1
			S:Print(format("|cffffd700%s|r: %s", name, note))
		end
		if n == 0 then S:Print(L["No notes stored"]) end
		return
	end
	local name, text = msg:match("^(%S+)%s*(.*)$")
	if not name then return end
	if text == "" then
		if store[name] then
			store[name] = nil
			S:Print(format(L["Note removed: %s"], name))
		else
			S:Print(format(L["No note for %s"], name))
		end
		return
	end
	store[name] = text
	S:Print(format(L["Note set: %s = %s"], name, text))
end

function NT:Initialize()
	S:RegisterChatCommand("suinote", Cmd)
	S:RegisterChatCommand("note", Cmd)
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit,
			function(tt) S:SafeCall("Notes:Tip", TooltipNote, tt) end)
	elseif GameTooltip then
		GameTooltip:HookScript("OnTooltipSetUnit", function(tt) S:SafeCall("Notes:Tip", TooltipNote, tt) end)
	end
end
