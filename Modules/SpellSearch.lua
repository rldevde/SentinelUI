-- SpellSearch: search field inside the spellbook - spells whose name does
-- not match are dimmed instead of hidden, so button positions and the
-- secure cast attributes stay untouched (no taint, works in combat).
local _, ns = ...
local S = ns.S
local L = S.L
local SS = S:NewModule("SpellSearch", "spellsearch")

local CreateFrame = CreateFrame
local query = ""

local function Apply()
	local q = query:lower()
	local n = _G.SPELLS_PER_PAGE or 12
	for i = 1, n do
		local btn = _G["SpellButton" .. i]
		if not btn then break end
		local name = btn.SpellName and btn.SpellName:GetText()
		if q == "" or not name or name == "" then
			btn:SetAlpha(1)
		else
			btn:SetAlpha(name:lower():find(q, 1, true) and 1 or 0.15)
		end
	end
	-- page arrows stay useful while filtered: untouched on purpose
end

local function Build()
	if SS.frame or not _G.SpellBookFrame then return end
	local host = _G.SpellBookFrame
	local eb = CreateFrame("EditBox", "SentinelUISpellSearch", host, "InputBoxTemplate")
	eb:SetSize(150, 20)
	eb:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 24, 14)
	eb:SetAutoFocus(false)
	eb:SetMaxLetters(40)
	eb.placeholder = S:FontString(eb, 10, "OUTLINE", S.media.unitFont)
	eb.placeholder:SetPoint("LEFT", 4, 0)
	eb.placeholder:SetText("|cff888888" .. (L["Search..."] or "Search...") .. "|r")
	eb:SetScript("OnTextChanged", function(self)
		query = self:GetText() or ""
		eb.placeholder:SetShown(query == "")
		Apply()
	end)
	eb:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
	eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	SS.frame = eb
	-- re-apply when pages or tabs flip the button contents
	if type(_G.SpellBookFrame_Update) == "function" then
		hooksecurefunc("SpellBookFrame_Update", Apply)
	end
	if type(_G.SpellBook_UpdateSpells) == "function" then
		hooksecurefunc("SpellBook_UpdateSpells", Apply)
	end
	host:HookScript("OnShow", Apply)
	for i = 1, (_G.SPELLS_PER_PAGE or 12) do
		local btn = _G["SpellButton" .. i]
		if btn and btn.UpdateButton then hooksecurefunc(btn, "UpdateButton", Apply) end
	end
end

-- Quest log: same dim-filter on QuestLogTitle buttons ----------------------
local queryQ = ""

local function ApplyQuest()
	local q = queryQ:lower()
	for i = 1, 40 do
		local btn = _G["QuestLogTitle" .. i]
		if not btn then break end
		if q == "" then
			btn:SetAlpha(1)
		else
			local idx = btn.questLogIndex or (btn.GetID and btn:GetID()) or i
			local name = GetQuestLogTitle and GetQuestLogTitle(idx)
			local match = name and name:lower():find(q, 1, true)
			btn:SetAlpha(match and 1 or 0.15)
		end
	end
end

local function BuildQuest()
	if SS.questBox or not _G.QuestLogFrame then return end
	local host = _G.QuestLogFrame
	local eb = CreateFrame("EditBox", "SentinelUIQuestSearch", host, "InputBoxTemplate")
	eb:SetSize(150, 20)
	eb:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 30, 30)
	eb:SetAutoFocus(false)
	eb:SetMaxLetters(40)
	eb.placeholder = S:FontString(eb, 10, "OUTLINE", S.media.unitFont)
	eb.placeholder:SetPoint("LEFT", 4, 0)
	eb.placeholder:SetText("|cff888888" .. (L["Search..."] or "Search...") .. "|r")
	eb:SetScript("OnTextChanged", function(self)
		queryQ = self:GetText() or ""
		eb.placeholder:SetShown(queryQ == "")
		ApplyQuest()
	end)
	eb:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
	eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	SS.questBox = eb
	if type(_G.QuestLog_Update) == "function" then hooksecurefunc("QuestLog_Update", ApplyQuest) end
	host:HookScript("OnShow", ApplyQuest)
end

function SS:Initialize()
	self.db = S.db.profile.spellsearch or {}
	if self.db.enable == false then return end
	Build()
	BuildQuest()
	-- spellbook frame can be replaced/recreated by UI reloads mid-session
	self:RegisterEvent("ADDON_LOADED", function(_, _, addon)
		if (addon == "Blizzard_PlayerSpells" or addon == "Blizzard_SpellBook") and not SS.frame then Build() end
		if (addon == "Blizzard_QuestLog" or addon == "Blizzard_UIPanels_Game") and not SS.questBox then BuildQuest() end
	end)
end

function SS:Update()
	self.db = S.db.profile.spellsearch or {}
	if self.frame then self.frame:SetShown(self.db.enable ~= false) end
	if self.questBox then self.questBox:SetShown(self.db.enable ~= false) end
end
