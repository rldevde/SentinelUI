-- Makes every Blizzard window draggable and remembers its position.
-- Blizzard's panel manager re-anchors panels whenever one opens/closes, so the
-- saved position is re-applied after UpdateUIPanelPositions and on every OnShow.
-- Drag: left mouse on the window (or its title strip). Reset: Shift+Right-click
-- the title strip, or /sui resetwindows.
local _, ns = ...
local S = ns.S
local L = S.L
local WM = S:NewModule("WindowMover")

local _G = _G
local ipairs, pairs = ipairs, pairs

local windows = {
	"CharacterFrame", "SpellBookFrame", "PlayerTalentFrame", "TalentFrame", "QuestLogFrame", "QuestFrame", "QuestLogDetailFrame",
	"GossipFrame", "ItemTextFrame", "FriendsFrame", "MerchantFrame", "MailFrame", "OpenMailFrame", "BankFrame", "GuildBankFrame",
	"TradeFrame", "GuildFrame", "GuildRegistrarFrame", "PetitionFrame", "TabardFrame", "GuildControlPopupFrame", "GuildInfoFrame",
	"GuildMemberDetailFrame", "CommunitiesFrame", "AuctionFrame", "AuctionHouseFrame", "PVEFrame", "LFGParentFrame", "LFDParentFrame",
	"LFGListingFrame", "LFGBrowseFrame", "RaidBrowserFrame", "PVPFrame", "PVPUIFrame", "PVPParentFrame", "BattlefieldFrame",
	"WorldStateScoreFrame", "ArenaFrame", "ArenaTeamFrame", "MacroFrame", "KeyBindingFrame", "ChatConfigFrame", "AchievementFrame",
	"CollectionsJournal", "TradeSkillFrame", "CraftFrame", "ProfessionsFrame", "ClassTrainerFrame", "InspectFrame", "PetStableFrame",
	"TaxiFrame", "AddonList", "HelpFrame", "TimeManagerFrame", "CalendarFrame", "EncounterJournal", "DressUpFrame",
	"ItemSocketingFrame", "GlyphFrame", "LootFrame", "RaidParentFrame", "BarberShopFrame", "ChannelFrame", "RaidInfoFrame",
	"VideoOptionsFrame", "InterfaceOptionsFrame", "SettingsPanel", "AudioOptionsFrame", "GameMenuFrame", "WorldMapFrame",
	"LootHistoryFrame", "ReadyCheckFrame", "TabardFrame", "ItemUpgradeFrame", "QuestLogPopupDetailFrame", "StopwatchFrame",
}

function WM:Positions()
	S.db.global.windowPositions = S.db.global.windowPositions or {}
	return S.db.global.windowPositions
end

function WM:Apply(frame)
	local pos = frame and self:Positions()[frame:GetName() or ""]
	if not pos or frame.suiMoving then return end
	if frame.IsProtected and frame:IsProtected() and InCombatLockdown() then return end
	frame.suiApplying = true
	frame:ClearAllPoints()
	frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	frame.suiApplying = nil
end

function WM:Save(frame)
	local name = frame:GetName()
	if not name then return end
	local point, _, relPoint, x, y = frame:GetPoint(1)
	if point then self:Positions()[name] = { point, relPoint or point, x or 0, y or 0 } end
end

local function StartDrag(frame)
	if InCombatLockdown() and frame:IsProtected() then return end
	frame.suiMoving = true
	frame:StartMoving()
end

local function StopDrag(frame)
	if not frame.suiMoving then return end
	frame:StopMovingOrSizing()
	frame.suiMoving = nil
	WM:Save(frame)
end

function WM:Attach(frame)
	if not frame or frame.suiWindowMover or not frame.SetMovable then return end
	if frame.IsForbidden and frame:IsForbidden() then return end
	if frame:IsProtected() and InCombatLockdown() then return end
	frame.suiWindowMover = true
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:HookScript("OnDragStart", StartDrag)
	frame:HookScript("OnDragStop", StopDrag)
	frame:HookScript("OnHide", StopDrag)
	frame:HookScript("OnShow", function(f) S:SafeCall("WindowMover:Show", WM.Apply, WM, f) end)

	-- title strip: child insets often cover the frame body, so give every window a
	-- dedicated grab area along the top edge (left of the close button)
	local grip = CreateFrame("Frame", nil, frame)
	grip:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	grip:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -30, 0)
	grip:SetHeight(22)
	grip:SetFrameLevel(frame:GetFrameLevel() + 1)
	grip:EnableMouse(true)
	grip:RegisterForDrag("LeftButton")
	grip:SetScript("OnDragStart", function() StartDrag(frame) end)
	grip:SetScript("OnDragStop", function() StopDrag(frame) end)
	grip:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" and IsShiftKeyDown() then
			WM:Positions()[frame:GetName() or ""] = nil
			if UpdateUIPanelPositions then pcall(UpdateUIPanelPositions, frame) end
		end
	end)
	frame.suiGrip = grip
	self:Apply(frame)
end

function WM:Scan()
	for _, name in ipairs(windows) do
		local f = _G[name]
		if f then S:SafeCall("WindowMover:" .. name, self.Attach, self, f) end
	end
end

function WM:ReapplyAll()
	for _, name in ipairs(windows) do
		local f = _G[name]
		if f and f.suiWindowMover and f:IsShown() then self:Apply(f) end
	end
end

function WM:Reset()
	wipe(self:Positions())
	if UpdateUIPanelPositions then pcall(UpdateUIPanelPositions) end
	S:Print(L["Window positions reset."])
end

function WM:Initialize()
	self:Scan()
	if UpdateUIPanelPositions then
		hooksecurefunc("UpdateUIPanelPositions", function() S:SafeCall("WindowMover:Panels", WM.ReapplyAll, WM) end)
	end
	if ShowUIPanel then
		hooksecurefunc("ShowUIPanel", function() S:SafeCall("WindowMover:ShowPanel", WM.ReapplyAll, WM) end)
	end
	self:RegisterEvent("ADDON_LOADED", function() C_Timer.After(0, function() S:SafeCall("WindowMover:Scan", WM.Scan, WM) end) end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function() S:SafeCall("WindowMover:Scan", WM.Scan, WM) end)
end
