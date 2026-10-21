-- LootHistory: raid/party loot log. Every loot system message (self and
-- group members) is recorded with a timestamp and shown in a scrollable
-- window, newest first. Item links stay clickable. /suilootlog
local _, ns = ...
local S = ns.S
local L = S.L
local LH = S:NewModule("LootHistory", "loothistory")

local ipairs, pairs = ipairs, pairs
local format = format
local MAX = 200
local ROWS, ROW_H = 14, 18

local frame, rows

local function Entries()
	S.db.global.lootHistory = S.db.global.lootHistory or {}
	return S.db.global.lootHistory
end

function LH:BuildFrame()
	if frame then return end
	frame = CreateFrame("Frame", "SentinelUILootHistory", UIParent)
	tinsert(UISpecialFrames, "SentinelUILootHistory")
	frame:SetSize(460, 300)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	S:CreateBackdrop(frame, "Default")
	local title = S:FontString(frame, 13, "OUTLINE", S.media.unitFont)
	title:SetPoint("TOP", 0, -10)
	title:SetText(L["Loot History"])
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)
	if S.SkinCloseButton then S:SkinCloseButton(close) end
	rows = {}
	for i = 1, ROWS do
		local r = CreateFrame("Button", nil, frame)
		r:SetSize(430, ROW_H)
		r:SetPoint("TOPLEFT", 12, -34 - (i - 1) * ROW_H)
		r.text = S:FontString(r, 10, nil, S.media.unitFont, nil, "LEFT")
		r.text:SetPoint("LEFT", 4, 0)
		r.text:SetWidth(420)
		r.hl = r:CreateTexture(nil, "HIGHLIGHT")
		r.hl:SetAllPoints()
		r.hl:SetColorTexture(0.3, 0.3, 0.4, 0.4)
		r:SetScript("OnEnter", function(self2)
			-- hover shows the raw line's item tooltip when it contains a link
			local link = self2.link
			if link then
				GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
				GameTooltip:SetHyperlink(link)
				GameTooltip:Show()
			end
		end)
		r:SetScript("OnLeave", function() GameTooltip:Hide() end)
		rows[i] = r
	end
	frame:Hide()
end

function LH:Fill()
	if not frame then return end
	local e = Entries()
	for i, row in ipairs(rows) do
		local d = e[i]
		if d then
			row.text:SetText(format("|cff888888%s|r %s",
				date("%H:%M", d.t or 0), d.msg or ""))
			row.link = d.link
			row:Show()
		else
			row:Hide()
		end
	end
end

function LH:Add(msg)
	local e = Entries()
	-- keep the first item hyperlink so rows can show its tooltip on hover
	local link = msg:match("(|Hitem:.-|h%[.-%]|h)")
	tinsert(e, 1, { t = time(), msg = msg, link = link })
	if #e > MAX then e[MAX + 1] = nil end
	if frame and frame:IsShown() then self:Fill() end
end

function LH:Toggle()
	self:BuildFrame()
	if frame:IsShown() then frame:Hide() else self:Fill() frame:Show() end
end

function LH:Initialize()
	self.db = S.db.profile.loothistory
	SLASH_SUILOOTHISTORY1 = "/suilootlog"
	SLASH_SUILOOTHISTORY2 = "/lh"
	SlashCmdList.SUILOOTHISTORY = function() LH:Toggle() end
	if not self.db.enable then return end
	self:RegisterEvent("CHAT_MSG_LOOT", function(_, msg, sender)
		-- only loot messages carrying an item link are worth storing
		if type(msg) ~= "string" or not msg:find("Hitem") then return end
		if S.IsSecret and S.IsSecret(msg) then return end
		LH:Add(msg)
	end)
end

function LH:Update()
	self.db = S.db.profile.loothistory
end
