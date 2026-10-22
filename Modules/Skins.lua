-- Skins: generic restyling of Blizzard windows (also load-on-demand ones) and some third party addons.
local _, ns = ...
local S = ns.S
local L = S.L
local SK = S:NewModule("Skins")

local _G = _G
local pairs, ipairs, type = pairs, ipairs, type
local gsub, strmatch = gsub, strmatch
local max, select, unpack, CreateFrame = math.max, select, unpack, CreateFrame
local hooksecurefunc, C_Timer = hooksecurefunc, C_Timer
local BLANK = [[Interface\Buttons\WHITE8X8]]

-- key = setting, frames = global names, sub = inner frames to strip, addon = load-on-demand addon
local skins = {
	{ key = "character", frames = { "CharacterFrame" }, sub = { "PaperDollFrame", "ReputationFrame", "SkillFrame", "HonorFrame", "PetPaperDollFrame", "TokenFrame", "CharacterFrameInset", "CharacterFrameInsetRight", "PaperDollItemsFrame", "CharacterModelFrame", "CharacterModelScene", "ReputationListScrollFrame", "SkillListScrollFrame", "PaperDollInnerBorderTop" }, slots = true, custom = "Character" },
	{ key = "spellbook", frames = { "SpellBookFrame" }, custom = "SpellBook" },
	{ key = "spellbook", frames = { "PlayerSpellsFrame" }, addon = "Blizzard_PlayerSpells" },
	{ key = "talents", frames = { "PlayerTalentFrame", "TalentFrame" }, addon = "Blizzard_TalentUI", sub = { "PlayerTalentFrameScrollFrame", "TalentFrameScrollFrame" }, custom = "Talents" },
	{ key = "talents", frames = { "ClassTalentFrame" }, addon = "Blizzard_ClassTalentUI" },
	{ key = "quest", frames = { "QuestLogFrame", "QuestFrame", "QuestLogDetailFrame", "QuestTimerFrame" }, sub = { "QuestLogListScrollFrame", "QuestLogDetailScrollFrame", "QuestDetailScrollFrame", "QuestProgressScrollFrame", "QuestRewardScrollFrame", "QuestFrameDetailPanel", "QuestFrameProgressPanel", "QuestFrameRewardPanel", "QuestFrameGreetingPanel", "EmptyQuestLogFrame" }, keepPortrait = true, custom = "Quest" },
	{ key = "gossip", frames = { "GossipFrame", "ItemTextFrame" }, sub = { "GossipFrameGreetingPanel", "GossipGreetingScrollFrame" }, keepPortrait = true, custom = "Gossip" },
	{ key = "friends", frames = { "FriendsFrame", "AddFriendFrame", "FriendsFriendsFrame", "RecruitAFriendFrame", "ChannelFrame", "RaidInfoFrame" }, sub = { "FriendsFrameInset", "WhoFrameListInset", "WhoFrameEditBoxInset", "FriendsListFrame", "WhoFrame", "IgnoreListFrame", "RaidFrame", "FriendsFrameFriendsScrollFrame", "WhoListScrollFrame", "ChannelListScrollFrame", "ChannelRosterScrollFrame" } },
	{ key = "merchant", frames = { "MerchantFrame" }, sub = { "MerchantFrameInset", "MerchantMoneyInset", "MerchantMoneyBg", "MerchantBuyBackItem", "MerchantExtraCurrencyInset", "MerchantExtraCurrencyBg" } },
	{ key = "mail", frames = { "MailFrame", "OpenMailFrame" }, sub = { "InboxFrame", "SendMailFrame", "MailFrameInset", "OpenMailFrameInset", "SendMailScrollFrame", "OpenMailScrollFrame", "SendMailMoneyInset", "SendMailMoneyBg" }, custom = "Mail" },
	{ key = "bank", frames = { "BankFrame" }, custom = "Bank" },
	{ key = "bank", frames = { "GuildBankFrame" }, addon = "Blizzard_GuildBankUI", custom = "GuildBank" },
	{ key = "trade", frames = { "TradeFrame" }, sub = { "TradePlayerItemsInset", "TradeRecipientItemsInset", "TradePlayerEnchantInset", "TradeRecipientEnchantInset", "TradePlayerInputMoneyInset", "TradeRecipientMoneyInset", "TradeRecipientMoneyBg" } },
	{ key = "guild", frames = { "GuildFrame", "GuildRegistrarFrame", "PetitionFrame", "TabardFrame", "GuildInfoFrame", "GuildMemberDetailFrame", "GuildControlPopupFrame" }, sub = { "GuildListScrollFrame", "GuildStatusFrame" } },
	{ key = "guild", frames = { "CommunitiesFrame" }, addon = "Blizzard_Communities" },
	{ key = "guild", frames = { "GuildFrame" }, addon = "Blizzard_GuildUI" },
	{ key = "auctionhouse", frames = { "AuctionFrame" }, addon = "Blizzard_AuctionUI", sub = { "AuctionFrameBrowse", "AuctionFrameBid", "AuctionFrameAuctions", "BrowseScrollFrame", "BidScrollFrame", "AuctionsScrollFrame" } },
	{ key = "auctionhouse", frames = { "AuctionHouseFrame" }, addon = "Blizzard_AuctionHouseUI" },
	{ key = "lfg", frames = { "PVEFrame", "LFGParentFrame", "LFDParentFrame", "LFGListingFrame", "LFGBrowseFrame", "RaidBrowserFrame" }, sub = { "LFDQueueFrame", "LFGListFrame", "RaidFinderFrame", "LFDParentFrameInset", "PVEFrameLeftInset" }, noChildren = true },
	{ key = "lfg", frames = { "LFGListingFrame", "LFGBrowseFrame" }, addon = "Blizzard_GroupFinder_VanillaStyle", noChildren = true },
	{ key = "lfg", frames = { "PVPUIFrame", "PVPFrame", "HonorFrame", "ConquestFrame" }, addon = "Blizzard_PVPUI" },
	{ key = "macro", frames = { "MacroFrame", "MacroPopupFrame" }, addon = "Blizzard_MacroUI", sub = { "MacroFrameInset", "MacroButtonScrollFrame", "MacroFrameTextBackground", "MacroFrameSelectedMacroBackground" } },
	{ key = "keybind", frames = { "KeyBindingFrame" }, addon = "Blizzard_BindingUI" },
	{ key = "options", frames = { "SettingsPanel", "InterfaceOptionsFrame", "VideoOptionsFrame", "AudioOptionsFrame", "ChatConfigFrame", "ColorPickerFrame" } },
	{ key = "gamemenu", frames = { "GameMenuFrame" }, gamemenu = true },
	{ key = "popup", frames = { "StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4", "ReadyCheckFrame", "RolePollPopup", "LFGDungeonReadyDialog", "LFDRoleCheckPopup", "BNToastFrame", "QueueStatusFrame", "LevelUpDisplay", "DropDownList1", "DropDownList2", "ChatMenu", "EmoteMenu", "LanguageMenu" } },
	{ key = "worldmap", frames = { "WorldMapFrame" }, sub = { "WorldMapFrame.BorderFrame", "QuestMapFrame", "WorldMapFrame.ScrollContainer" }, noBackdropReplace = true },
	{ key = "achievements", frames = { "AchievementFrame" }, addon = "Blizzard_AchievementUI" },
	{ key = "collections", frames = { "CollectionsJournal", "WardrobeFrame" }, addon = "Blizzard_Collections" },
	{ key = "tradeskill", frames = { "TradeSkillFrame" }, addon = "Blizzard_TradeSkillUI", sub = { "TradeSkillListScrollFrame", "TradeSkillDetailScrollFrame", "TradeSkillDetailScrollChildFrame" }, custom = "TradeSkill" },
	{ key = "tradeskill", frames = { "CraftFrame" }, addon = "Blizzard_CraftUI", sub = { "CraftListScrollFrame", "CraftDetailScrollFrame" }, custom = "Craft" },
	{ key = "tradeskill", frames = { "ProfessionsFrame" }, addon = "Blizzard_Professions" },
	{ key = "trainer", frames = { "ClassTrainerFrame" }, addon = "Blizzard_TrainerUI", sub = { "ClassTrainerListScrollFrame", "ClassTrainerDetailScrollFrame" } },
	{ key = "inspect", frames = { "InspectFrame" }, addon = "Blizzard_InspectUI", sub = { "InspectPaperDollFrame", "InspectHonorFrame", "InspectTalentFrame", "InspectPVPFrame", "InspectGuildFrame" }, inspectSlots = true },
	{ key = "petstable", frames = { "PetStableFrame" }, sub = { "PetStableFrameInset", "PetStableLeftInset", "PetStableBottomInset" } },
	{ key = "taxi", frames = { "TaxiFrame" }, custom = "Taxi" },
	{ key = "taxi", frames = { "FlightMapFrame" }, addon = "Blizzard_FlightMap" },
	{ key = "addonList", frames = { "AddonList" }, sub = { "AddonListInset", "AddonListScrollFrame" } },
	{ key = "help", frames = { "HelpFrame" } },
	{ key = "timemanager", frames = { "TimeManagerFrame", "StopwatchFrame" }, addon = "Blizzard_TimeManager" },
	{ key = "calendar", frames = { "CalendarFrame" }, addon = "Blizzard_Calendar" },
	{ key = "encounterjournal", frames = { "EncounterJournal" }, addon = "Blizzard_EncounterJournal" },
	{ key = "character", frames = { "DressUpFrame", "SideDressUpFrame" } },
	{ key = "lfg", frames = { "BattlefieldFrame", "WorldStateScoreFrame", "PVPReadyDialog", "ArenaFrame", "PVPTeamDetails", "PVPParentFrame", "ArenaTeamFrame", "BattlefieldMinimap" } },
	{ key = "trade", frames = { "BarberShopFrame" }, addon = "Blizzard_BarbershopUI" },
	{ key = "inspect", frames = { "ItemSocketingFrame" }, addon = "Blizzard_ItemSocketingUI" },
	{ key = "character", frames = { "ItemUpgradeFrame", "ScrappingMachineFrame" }, addon = "Blizzard_ItemUpgradeUI" },
	{ key = "talents", frames = { "GlyphFrame" }, addon = "Blizzard_GlyphUI" },
	{ key = "quest", frames = { "QuestLogPopupDetailFrame", "QuestChoiceFrame" } },
	{ key = "quest", frames = { "WatchFrame", "QuestWatchFrame", "ObjectiveTrackerFrame" }, noBackdropReplace = true, custom = "QuestTracker" },
	{ key = "popup", frames = { "TalkingHeadFrame" }, addon = "Blizzard_TalkingHeadUI", noBackdropReplace = true, custom = "TalkingHead" },
	-- additional popups / dialogs / lazy frames that were still unskinned
	{ key = "popup", frames = { "StackSplitFrame", "CoinPickupFrame", "BasicMessageDialog", "GuildInviteFrame", "ChannelPullout" } },
	{ key = "popup", frames = { "ReportPlayerNameDialog", "ReportCheatingDialog", "ReportFrame", "OpacityFrame", "TimeAlertFrame", "CombatLogQuickButtonFrame_Custom", "PlayerChoiceFrame", "DeathRecapFrame", "LFGListApplicationDialog", "LFGListInviteDialog", "WarGameInvite" } },
	{ key = "character", frames = { "ReputationDetailFrame", "TokenFramePopup", "SkillDetailFrame", "EquipmentFlyoutFrame" } },
	{ key = "bank", frames = { "GuildBankPopupFrame" }, addon = "Blizzard_GuildBankUI" },
	{ key = "macro", frames = { "IconSelectorPopupFrame", "GearManagerDialogPopup" } },
	{ key = "help", frames = { "TutorialFrame", "GMChatFrame" } },
	{ key = "friends", frames = { "RaidParentFrame" }, sub = { "RaidGroup1", "RaidGroup2", "RaidGroup3", "RaidGroup4", "RaidGroup5", "RaidGroup6", "RaidGroup7", "RaidGroup8" } },
	{ key = "options", frames = { "EventTraceFrame", "TableAttributeDisplay" }, addon = "Blizzard_DebugTools" },
}

local function Resolve(path)
	local obj = _G
	for part in path:gmatch("[^%.]+") do obj = obj and obj[part] end
	return type(obj) == "table" and obj or nil
end

local slotNames = { "Head", "Neck", "Shoulder", "Back", "Chest", "Shirt", "Tabard", "Wrist", "Hands", "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand", "Ranged", "Ammo" }

local function SkinItemSlot(slot)
	if not slot or slot.suiSkinned then return end
	slot.suiSkinned = true
	local name = slot:GetName()
	local icon = slot.icon or slot.Icon or (name and _G[name .. "IconTexture"])
	local normal = slot.GetNormalTexture and slot:GetNormalTexture()
	-- on some clients the item icon IS the NormalTexture: never hide it
	if normal and normal ~= icon then normal:SetAlpha(0) end
	if slot.IconBorder then slot.IconBorder:SetAlpha(0) end
	local frame = name and _G[name .. "Frame"]
	if frame and frame.SetAlpha and not (icon and icon.GetParent and icon:GetParent() == frame) then frame:SetAlpha(0) end
	if icon then
		icon:SetAlpha(1)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		S:SetInside(icon, slot, 0, 0)
		if not slot.suiIconHooked then
			slot.suiIconHooked = true
			-- Blizzard re-uses the same texture for empty-slot silhouettes and
			-- item icons; if anything alphas it out, the slot stays "empty"
			hooksecurefunc(icon, "SetAlpha", function(tex, a)
				if a == 0 then tex:SetAlpha(1) end
			end)
		end
	end
	S:CreateBackdrop(slot, "Default")
	if not slot.suiIlvl then
		slot.suiIlvl = S:FontString(slot, 11, "OUTLINE")
		slot.suiIlvl:SetPoint("BOTTOM", slot, "BOTTOM", 0, 2)
	end
	local hl = slot.GetHighlightTexture and slot:GetHighlightTexture()
	if hl then hl:SetTexture([[Interface\Buttons\WHITE8X8]]) hl:SetVertexColor(1, 1, 1, 0.12) S:SetInside(hl, slot) end
	if slot.IconBorder then
		hooksecurefunc(slot.IconBorder, "SetVertexColor", function(_, r, g, b)
			if slot.suiBackdrop then slot.suiBackdrop:SetBackdropBorderColor(r, g, b) end
		end)
		hooksecurefunc(slot.IconBorder, "Hide", function()
			if slot.suiBackdrop then slot.suiBackdrop:SetBackdropBorderColor(unpack(S.media.borderColor)) end
		end)
	end
end

local function UpdateSlotQuality(slot, unit, id)
	if not slot or not slot.suiBackdrop then return end
	local link = GetInventoryItemLink(unit, id)
	local q = link and select(3, S.GetItemInfo(link))
	if q and q > 1 then
		local r, g, b = S.GetItemQualityColor(q)
		slot.suiBackdrop:SetBackdropBorderColor(r, g, b)
	else
		slot.suiBackdrop:SetBackdropBorderColor(unpack(S.media.borderColor))
	end
	-- item level readout on the slot
	if slot.suiIlvl then
		local ilvl
		if link then
			local _, _, _, base = S.GetItemInfo(link)
			ilvl = (S.GetDetailedItemLevelInfo and S.GetDetailedItemLevelInfo(link)) or base
		end
		if ilvl and ilvl > 1 then
			local r, g, b = S.GetItemQualityColor(q or 1)
			slot.suiIlvl:SetText(ilvl)
			slot.suiIlvl:SetTextColor(r, g, b)
		else
			slot.suiIlvl:SetText("")
		end
	end
end

function SK:SkinSlots(prefix, unit)
	for _, n in ipairs(slotNames) do
		local slot = _G[prefix .. n .. "Slot"]
		if slot then
			SkinItemSlot(slot)
			UpdateSlotQuality(slot, unit, slot:GetID())
		end
	end
end

function SK:SkinTabs(frame)
	local name = frame:GetName()
	if name then
		for i = 1, 12 do
			local tab = _G[name .. "Tab" .. i]
			if tab then S:SkinTab(tab) end
		end
	end
	if frame.Tabs then for _, tab in ipairs(frame.Tabs) do S:SkinTab(tab) end end
	if frame.TabSystem and frame.TabSystem.tabs then for _, tab in ipairs(frame.TabSystem.tabs) do S:SkinTab(tab) end end
end

function SK:SkinWindow(frame, info)
	if not frame or frame.suiWindowSkinned or (frame.IsForbidden and frame:IsForbidden()) then return end
	frame.suiWindowSkinned = true
	if info.keepPortrait then frame.suiKeepPortrait = true end
	if info.noBackdropReplace then
		if frame.BorderFrame then S:StripTextures(frame.BorderFrame) S:CreateBackdrop(frame.BorderFrame, "Transparent", "TOP") end
		local close = frame.CloseButton or (frame.BorderFrame and frame.BorderFrame.CloseButton)
		if close then S:SkinCloseButton(close) end
	else
		S:SkinFrame(frame)
	end
	if info.sub then
		for _, path in ipairs(info.sub) do
			local sub = Resolve(path)
			if sub and sub.GetObjectType then
				if sub:IsObjectType("Texture") then sub:SetAlpha(0) else S:StripTextures(sub) end
			end
		end
	end
	self:SkinTabs(frame)
	-- noChildren: Blizzard's group finder (LFGListing/LFGBrowse) breaks when its
	-- controls are restyled - the activity-view scrollbar is even documented
	-- to taint on this client. Keep the window skin only.
	if not info.noChildren then S:SkinChildren(frame) end
	if info.slots then
		self:SkinSlots("Character", "player")
		self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function()
			for _, n in ipairs(slotNames) do
				local slot = _G["Character" .. n .. "Slot"]
				if slot then UpdateSlotQuality(slot, "player", slot:GetID()) end
			end
		end)
	end
	if info.inspectSlots then
		self:SkinSlots("Inspect", "target")
		if InspectFrame then
			local function UpdateInspect()
				local unit = InspectFrame.unit or "target"
				for _, n in ipairs(slotNames) do
					local slot = _G["Inspect" .. n .. "Slot"]
					if slot then UpdateSlotQuality(slot, unit, slot:GetID()) end
				end
			end
			InspectFrame:HookScript("OnShow", function()
				UpdateInspect()
				-- a competing NotifyInspect (tooltip ilvl hover, gear score)
				-- can swallow the frame's pending request: if every slot is
				-- still empty shortly after open, ask for the data again -
				-- that is also what feeds the talent tab
				C_Timer.After(0.6, function()
					if not InspectFrame:IsShown() then return end
					local u = InspectFrame.unit
					if not (u and CanInspect and CanInspect(u)) then return end
					for _, sn in ipairs(slotNames) do
						local sid = GetInventorySlotInfo and GetInventorySlotInfo(sn .. "Slot")
						if sid and GetInventoryItemLink(u, sid) then return end
					end
					NotifyInspect(u)
				end)
			end)
			-- gear arrives after INSPECT_READY; OnShow alone is too early
			self:RegisterEvent("INSPECT_READY", function()
				if InspectFrame:IsShown() then UpdateInspect() end
			end)
			-- one-shot diagnostic: figure out why items/talents don't render
			local dumped
			InspectFrame:HookScript("OnShow", function()
				if dumped then return end
				dumped = true
				C_Timer.After(0.8, function()
					local p = { "unit=" .. tostring(InspectFrame.unit), "talentFrame=" .. tostring(InspectTalentFrame ~= nil) }
					local tabs = {}
					for i = 1, 6 do
						local t = _G["InspectFrameTab" .. i]
						if t then tabs[#tabs + 1] = i .. ":" .. tostring(t:GetText()) .. (t:IsShown() and "" or ":hid") end
					end
					p[#p + 1] = "tabs={" .. table.concat(tabs, ",") .. "}"
					p[#p + 1] = "subs={" .. table.concat(_G.INSPECTFRAME_SUBFRAMES or {}, ",") .. "}"
					for _, n in ipairs({ "Head", "Chest", "MainHand" }) do
						local slot = _G["Inspect" .. n .. "Slot"]
						if slot then
							local sname = slot:GetName()
							local icon = slot.icon or slot.Icon or _G[sname .. "IconTexture"]
							local normal = slot.GetNormalTexture and slot:GetNormalTexture()
							p[#p + 1] = sname .. "{icon=" .. tostring(icon ~= nil)
								.. ",isNormal=" .. tostring(normal == icon)
								.. ",shown=" .. tostring(icon and icon.IsShown and icon:IsShown())
								.. ",a=" .. tostring(icon and icon.GetAlpha and icon:GetAlpha())
								.. ",tex=" .. tostring(icon and icon.GetTexture and icon:GetTexture()) .. "}"
							local kids = {}
							for i = 1, select("#", slot:GetChildren()) do
								local c = select(i, slot:GetChildren())
								kids[#kids + 1] = tostring(c:GetName() or "?") .. ":" .. c:GetObjectType()
							end
							p[#p + 1] = sname .. "kids={" .. table.concat(kids, "|") .. "}"
						end
					end
					if InspectTalentFrame then
						local nc = select("#", InspectTalentFrame:GetChildren())
						local nr = select("#", InspectTalentFrame:GetRegions())
						local kids = {}
						for i = 1, math.min(nc, 5) do
							local c = select(i, InspectTalentFrame:GetChildren())
							kids[#kids + 1] = tostring(c:GetName() or "?") .. ":" .. c:GetObjectType() .. (c:IsShown() and "" or ":hid")
						end
						p[#p + 1] = "talent{kids=" .. nc .. ",regs=" .. nr .. ",first={" .. table.concat(kids, "|") .. "}}"
					end
					S:LogInfo("inspect", table.concat(p, " "))
				end)
			end)
		end
	end
	if info.keepPortrait then
		local name = frame:GetName()
		local portrait = frame.portrait or frame.Portrait or (name and _G[name .. "Portrait"]) or (frame.PortraitContainer and frame.PortraitContainer.portrait)
		if portrait and portrait.SetAlpha then portrait:SetAlpha(1) end
	end
	if info.custom then
		S:SafeCall("Skins:" .. info.custom, self["Skin" .. info.custom], self, frame)
	end
end

-- Classic SpellBook (TBC/Era): spell buttons, skill line tabs, page arrows, title.
-- spell highlight -> clean white overlay instead of the golden parchment glow
local function SpellHighlightSetTexture(texture, tex)
	if tex == [[Interface\Buttons\ButtonHilight-Square]] or tex == [[Interface\Buttons\UI-PassiveHighlight]] then
		texture:SetColorTexture(1, 1, 1, 0.3)
	end
end

-- keep names readable after Blizzard refreshes the buttons
local function UpdateSpellButton()
	if _G.SpellBookFrame and _G.SpellBookFrame.bookType == _G.BOOKTYPE_PROFESSION then return end
	for i = 1, (_G.SPELLS_PER_PAGE or 12) do
		local button = _G["SpellButton" .. i]
		if not button then break end
		local shown = button.SpellName and button.SpellName:IsShown()
		if button.suiRow then button.suiRow:SetShown(shown) end
		if button.suiIconBd then button.suiIconBd:SetShown(shown) end
		if button.SpellSubName then button.SpellSubName:SetTextColor(0.6, 0.6, 0.6) end
		if button.SpellName then
			local r = button.SpellName:GetTextColor()
			if r and r < 0.8 then button.SpellName:SetTextColor(0.8, 0.8, 0.8)
			elseif r ~= 1 then button.SpellName:SetTextColor(1, 1, 1) end
		end
	end
end

function SK:SkinSpellBook(frame)
	-- parchment containers
	for _, n in ipairs({ "SpellBookSpellIconsFrame", "SpellBookSideTabsFrame", "SpellBookPageNavigationFrame" }) do
		local f = _G[n]
		if f then S:StripTextures(f) end
	end
	-- inset: backdrop stops 32px short of the right edge so the skill-line
	-- tabs stick out like real book tabs, and extends 76px below for the foot tabs
	local bd = frame.suiBackdrop
	if bd then
		bd:ClearAllPoints()
		bd:SetPoint("TOPLEFT", frame, "TOPLEFT", 11, -12)
		bd:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -32, 76)
	end
	local showAllRanks = _G.ShowAllSpellRanksCheckbox
	if showAllRanks and showAllRanks.SetPoint then
		S:SkinCheckBox(showAllRanks)
		showAllRanks:ClearAllPoints()
		showAllRanks:SetPoint("TOPLEFT", 20, -20)
	end
	local title = _G.SpellBookTitleText
	if title then
		title:ClearAllPoints()
		title:SetPoint("TOP", -10, -17)
		S:SetFont(title, nil, 15, "OUTLINE")
		title:SetTextColor(1, 1, 1)
	end
	local pageText = _G.SpellBookPageText
	if pageText then
		S:SetFont(pageText, nil, 12)
		pageText:SetTextColor(1, 1, 1)
		pageText:ClearAllPoints()
		pageText:SetPoint("BOTTOM", -10, 87)
	end
	local close = _G.SpellBookCloseButton
	if close then S:SkinCloseButton(close) end
	for i = 1, 3 do
		local t = _G["SpellBookFrameTabButton" .. i]
		if t and t.GetNormalTexture then
			local nt = t:GetNormalTexture() if nt then nt:SetTexture(nil) end
			local dt = t.GetDisabledTexture and t:GetDisabledTexture() if dt then dt:SetTexture(nil) end
			S:SkinTab(t)
			if t.suiBackdrop then
				t.suiBackdrop:ClearAllPoints()
				t.suiBackdrop:SetPoint("TOPLEFT", 14, -14)
				t.suiBackdrop:SetPoint("BOTTOMRIGHT", -14, 22)
			end
		end
	end
	-- foot tabs sit on the extended bottom backdrop
	local tb1 = _G.SpellBookFrameTabButton1
	if tb1 then
		tb1:ClearAllPoints()
		tb1:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", -3, 89)
		for i = 2, 3 do
			local t = _G["SpellBookFrameTabButton" .. i]
			local prev = _G["SpellBookFrameTabButton" .. (i - 1)]
			if t and prev then t:ClearAllPoints() t:SetPoint("TOPLEFT", prev, "TOPRIGHT", -27, 0) end
		end
	end
	local prevB, nextB = _G.SpellBookPrevPageButton, _G.SpellBookNextPageButton
	if prevB then S.SkinArrowButton(nil, prevB, "left") prevB:SetSize(24, 24) end
	if nextB then S.SkinArrowButton(nil, nextB, "right") nextB:SetSize(24, 24) end
	if prevB and nextB then
		prevB:ClearAllPoints()
		prevB:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -73, 87)
		nextB:ClearAllPoints()
		nextB:SetPoint("TOPLEFT", prevB, "TOPLEFT", 30, 0)
	end
	-- spell rows: dark row backdrop + framed icon + readable text
	for i = 1, (_G.SPELLS_PER_PAGE or 12) do
		local button = _G["SpellButton" .. i]
		if not button then break end
		if not button.suiSkinned then
			button.suiSkinned = true
			local name = button:GetName()
			local icon = _G[name .. "IconTexture"]
			local highlight = _G[name .. "Highlight"]
			-- clear parchment button regions (keep the flyout arrow texture)
			for j = 1, select("#", button:GetRegions()) do
				local region = select(j, button:GetRegions())
				if region:IsObjectType("Texture") and region:GetTexture() ~= [[Interface\Buttons\ActionBarFlyoutButton]] then
					region:SetTexture(nil)
				end
			end
			local cd = _G[name .. "Cooldown"]
			if cd then S:RegisterCooldown(cd) end
			-- frame the icon only (the button itself spans the whole text row)
			if icon then
				icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				local ib = CreateFrame("Frame", nil, button)
				S:SetTemplate(ib, "Default")
				S:SetOutside(ib, icon)
				ib:SetFrameLevel(max(0, (button:GetFrameLevel() or 1) - 1))
				button.suiIconBd = ib
			end
			-- transparent dark row behind the whole spell entry (stock buttons are
			-- already full-width rows; just pad them slightly)
			if not button.suiRow then
				local row = CreateFrame("Frame", nil, button)
				button.suiRow = row
				S:SetTemplate(row, "Transparent")
				row:SetPoint("TOPLEFT", button, "TOPLEFT", -4, 4)
				row:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 6, -4)
				row:SetFrameLevel(max(0, (button:GetFrameLevel() or 1) - 1))
			end
			if highlight then
				highlight:SetAllPoints()
				hooksecurefunc(highlight, "SetTexture", SpellHighlightSetTexture)
			end
			for _, k in ipairs({ "SpellName", "SubSpellName", "RequiredLevelString", "SeeTrainString" }) do
				local fs = _G[name .. k] or button[k]
				if fs and fs.SetFont then S:SetFont(fs, nil, 11) end
			end
			hooksecurefunc(button, "UpdateButton", UpdateSpellButton)
		end
	end
	-- keep Blizzard's button layout: the row backdrops are anchored to the buttons
	-- and follow them automatically; forcing reposition offsets would clip the
	-- right column inside the stock-sized window
	-- skill line tabs on the side: strip the backdrop but KEEP the tab icon
	-- (the icon is the button's NormalTexture - StripTextures would zero it too)
	-- skill line tabs: square icon buttons hanging off the right edge of the
	-- backdrop like book tabs (template + inset icon, tight column)
	for i = 1, (_G.MAX_SKILLLINE_TABS or 8) do
		local tab = _G["SpellBookSkillLineTab" .. i]
		if tab and not tab.suiSkinned then
			tab.suiSkinned = true
			local nt = tab.GetNormalTexture and tab:GetNormalTexture()
			local dt = tab.GetDisabledTexture and tab:GetDisabledTexture()
			S:StripTextures(tab)
			tab:SetSize(30, 30)
			local tbd = S:CreateBackdrop(tab, "Default")
			tbd:ClearAllPoints()
			tbd:SetPoint("TOPLEFT", -2, 2)
			tbd:SetPoint("BOTTOMRIGHT", 2, -2)
			S:AddHover(tab)
			if nt then
				nt:SetAlpha(1)
				nt:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				nt:ClearAllPoints()
				nt:SetPoint("TOPLEFT", 2, -2)
				nt:SetPoint("BOTTOMRIGHT", -2, 2)
				-- Blizzard re-assigns the icon via SetNormalTexture; keep alpha pinned
				hooksecurefunc(tab, "SetNormalTexture", function()
					local cur = tab:GetNormalTexture()
					if cur then cur:SetAlpha(1) end
				end)
			end
			if dt then dt:SetAlpha(1) dt:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
			local hl = tab.GetHighlightTexture and tab:GetHighlightTexture()
			if hl then
				hl:SetTexture(BLANK)
				hl:SetVertexColor(1, 1, 1, 0.15)
				hl:ClearAllPoints()
				hl:SetAllPoints()
			end
			local flash = _G["SpellBookSkillLineTab" .. i .. "Flash"]
			if flash then S:Kill(flash) end
			tab:ClearAllPoints()
			if i == 1 then
				-- hangs just outside the (shrunken) right edge of the backdrop
				tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", -33, -72)
			else
				local prev = _G["SpellBookSkillLineTab" .. (i - 1)]
				if prev then tab:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -6) end
			end
		end
	end
	UpdateSpellButton()
end

-- Classic TaxiFrame: the route map is a texture region of the frame, so the
-- generic strip hides it. Bring the map back and keep the window styled.
function SK:SkinTaxi()
	for _, n in ipairs({ "TaxiRouteMap", "TaxiMap" }) do
		local t = _G[n]
		if t and t.SetAlpha then t:SetAlpha(1) end
	end
	for _, n in ipairs({ "TaxiMerchant", "TaxiFrameTitleText" }) do
		local fs = _G[n]
		if fs and fs.SetFont then S:SetFont(fs, nil, 14, "OUTLINE") fs:SetTextColor(1, 0.8, 0.1) end
	end
	local close = _G.TaxiCloseButton
	if close then S:SkinCloseButton(close) end
end

-- Classic CharacterFrame: strip painted borders on collapsible skill/reputation headers.
function SK:SkinCharacter()
	for i = 1, 30 do
		for _, prefix in ipairs({ "SkillTypeLabel", "ReputationHeader" }) do
			local h = _G[prefix .. i]
			if h and h.GetObjectType and not h.suiSkinned then
				h.suiSkinned = true
				for _, k in ipairs({ "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive", "LeftHighlight", "MiddleHighlight", "RightHighlight" }) do
					local t = h[k] or _G[prefix .. i .. k]
					if t and t.SetAlpha then t:SetAlpha(0) end
				end
				if h:IsObjectType("Button") then
					S:CreateBackdrop(h, "Transparent")
					local fs = h.GetFontString and h:GetFontString()
					if fs then S:SetFont(fs, nil, 12) end
					S:AddHover(h)
				end
			end
		end
	end
	for i = 1, 20 do
		local bar = _G["ReputationBar" .. i]
		if bar and not bar.suiSkinned then
			bar.suiSkinned = true
			local name = bar:GetName()
			local fill = _G[name .. "ReputationBar"] or bar.ReputationBar
			if fill and fill.SetStatusBarTexture then
				fill:SetStatusBarTexture(S.media.statusbar)
			end
			for _, k in ipairs({ "Background", "LeftLine", "BottomLine", "ReputationBarLeft", "ReputationBarRight" }) do
				local t = _G[name .. k]
				if t and t.SetAlpha then t:SetAlpha(0) end
			end
		end
	end
	-- skill rows: the rank sub-frames keep their blue Blizzard bar + border art,
	-- which is unreadable on the dark backdrop -> restyle or strip them
	local function RestyleRankFrame(rf)
		if not rf or rf.suiSkinned then return end
		rf.suiSkinned = true
		for j = 1, select("#", rf:GetRegions()) do
			local r = select(j, rf:GetRegions())
			if r:IsObjectType("Texture") then
				r:SetAlpha(0)
			elseif r:IsObjectType("FontString") then
				r:SetTextColor(1, 1, 1)
			end
		end
		for j = 1, select("#", rf:GetChildren()) do
			local c = select(j, rf:GetChildren())
			if c:IsObjectType("StatusBar") then
				c:SetStatusBarTexture(S.media.statusbar)
				S:CreateBackdrop(c, "Default")
				for k = 1, select("#", c:GetRegions()) do
					local r = select(k, c:GetRegions())
					if r:IsObjectType("Texture") and r ~= c:GetStatusBarTexture() then r:SetAlpha(0) end
				end
			end
		end
	end
	for i = 1, 30 do
		local lbl = _G["SkillTypeLabel" .. i]
		if lbl and lbl.GetObjectType then
			RestyleRankFrame(_G["SkillTypeLabel" .. i .. "Rank"])
			RestyleRankFrame(_G["SkillRankFrame" .. i])
			if lbl.GetChildren then
				for j = 1, select("#", lbl:GetChildren()) do
					local c = select(j, lbl:GetChildren())
					if c and c.GetObjectType and not c:IsObjectType("Button") then RestyleRankFrame(c) end
				end
			end
		end
	end
	-- skills-tab layout repair: after stripping, Blizzard's corner controls can
	-- end up half outside the frame or floating over rows
	local list = _G.SkillListScrollFrame
	if list then
		-- the expand/collapse-all toggle: strip the tab chrome, then put the
		-- "Alle" caption back inside the skinned button (the stock anchor left
		-- it floating above the box)
		local expandFrame = _G.SkillFrameExpandButtonFrame
		if expandFrame then
			S:StripTextures(expandFrame)
			local collapse = _G.SkillFrameCollapseAllButton
			if collapse and collapse.IsObjectType and collapse:IsObjectType("Button") then
				S:SkinButton(collapse)
				local cap = (collapse.GetFontString and collapse:GetFontString())
					or collapse.text or (collapse:GetName() and _G[collapse:GetName() .. "Text"])
				if cap and cap.ClearAllPoints then
					cap:ClearAllPoints()
					cap:SetPoint("CENTER", collapse, "CENTER", 0, 0)
					cap:SetJustifyH("CENTER")
					local w = cap.GetStringWidth and cap:GetStringWidth()
					if w and w > 0 then collapse:SetWidth(w + 12) end
				end
			end
		end
		local cancel = _G.SkillFrameCancelButton
		if cancel then
			if cancel.IsObjectType and cancel:IsObjectType("Button") then S:SkinButton(cancel) end
			cancel:ClearAllPoints()
			cancel:SetPoint("TOPRIGHT", list, "BOTTOMRIGHT", 0, -10)
		end
	end
	-- scrollbars of the skill/reputation lists still carry original art
	for _, n in ipairs({ "SkillListScrollFrameScrollBar", "ReputationListScrollFrameScrollBar" }) do
		local sb = _G[n]
		if sb and sb.IsObjectType and sb:IsObjectType("Slider") then S:SkinScrollBar(sb) end
	end
end

-- Parchment remover: dark parchment text is unreadable on our dark backdrops.
-- Recolor it: titles gold, body text white, gossip options white.
local parchmentTextColors = { ["000000"] = "ffffff", ["414141"] = "7b8489" }
local TITLE_COLOR, TEXT_COLOR, DIM_COLOR = { 1, 0.80, 0.10 }, { 1, 1, 1 }, { 0.6, 0.6, 0.6 }

local function ReplaceParchmentColor(color)
	return "|cFF" .. (parchmentTextColors[color] or color)
end

local function ForceTextColor(fs, r, g, b)
	if r ~= 1 or g ~= 1 or b ~= 1 then fs:SetTextColor(1, 1, 1) end
end

-- book/letter pages are SimpleHTML widgets: SetTextColor takes (tag, r, g, b)
local function ForceHTMLColor(fs, tag, r, g, b)
	if r ~= 1 or g ~= 1 or b ~= 1 then fs:SetTextColor(tag, 1, 1, 1) end
end

-- a gossip/quest title button gets: white base color + embedded dark color codes replaced
local function SkinParchmentButton(button)
	if not button or button.suiParchment then return end
	button.suiParchment = true
	local fs = button.GetFontString and button:GetFontString()
	if fs then
		fs:SetTextColor(1, 1, 1)
		hooksecurefunc(fs, "SetTextColor", ForceTextColor)
	end
	local function FixText(b, text, skip)
		if skip or not text or text == "" then return end
		local newText, n = gsub(text, "|c[fF][fF](%x%x%x%x%x%x)", ReplaceParchmentColor)
		if n > 0 then b:SetFormattedText("%s", newText, true) end
	end
	hooksecurefunc(button, "SetText", FixText)
	hooksecurefunc(button, "SetFormattedText", function(b, fmt, ...)
		if not fmt or b.suiFixText then return end
		local newFmt, n = gsub(fmt, "|c[fF][fF](%x%x%x%x%x%x)", ReplaceParchmentColor)
		if n > 0 then
			-- re-entry guard: the replacement colors still match the gsub
			-- pattern, so a recursive call here would loop forever
			b.suiFixText = true
			b:SetFormattedText(newFmt, ...)
			b.suiFixText = nil
		end
	end)
	local cur = button.GetText and button:GetText()
	if cur then FixText(button, cur) end
end

-- Blizzard recolors readable-item and mail text with dark parchment colors on
-- every open. Hook the recolor so it always comes out readable on our backdrop.
local function SkinReadableText(widget)
	if not widget or widget.suiParchment then return end
	if widget.IsObjectType and widget:IsObjectType("Button") then
		SkinParchmentButton(widget)
		return
	end
	if not widget.SetTextColor then return end
	widget.suiParchment = true
	if widget.IsObjectType and widget:IsObjectType("SimpleHTML") then
		for _, tag in ipairs({ "P", "H1", "H2", "H3" }) do
			widget:SetTextColor(tag, 1, 1, 1)
		end
		hooksecurefunc(widget, "SetTextColor", ForceHTMLColor)
	else
		widget:SetTextColor(1, 1, 1)
		hooksecurefunc(widget, "SetTextColor", ForceTextColor)
	end
end

-- gold for book/letter titles (house style), same recolor-proof pattern
local function SkinReadableTitle(fs)
	if not fs or fs.suiParchment or not fs.SetTextColor then return end
	fs.suiParchment = true
	fs:SetTextColor(unpack(TITLE_COLOR))
	hooksecurefunc(fs, "SetTextColor", function(w, r, g, b)
		if r ~= 1 or g ~= 0.8 or b ~= 0.1 then w:SetTextColor(1, 0.8, 0.1) end
	end)
end

local function SetTextColorSafe(name, color)
	local fs = _G[name]
	if fs and fs.SetTextColor then fs:SetTextColor(unpack(color)) end
end

local function RecolorQuestInfo()
	for _, n in ipairs({ "QuestInfoTitleHeader", "QuestInfoDescriptionHeader", "QuestInfoObjectivesHeader", "QuestInfoRewardsFrameHeaderText" }) do
		SetTextColorSafe(n, TITLE_COLOR)
	end
	local rf = _G.QuestInfoRewardsFrame
	if rf and rf.Header and rf.Header.SetTextColor then rf.Header:SetTextColor(unpack(TITLE_COLOR)) end
	for _, n in ipairs({ "QuestInfoDescriptionText", "QuestInfoObjectivesText", "QuestInfoGroupSize", "QuestInfoRewardText", "QuestInfoSpellLearnText", "QuestInfoPlayerTitleText", "QuestInfoXPFrameReceiveText", "QuestInfoItemChooseText", "QuestInfoItemReceiveText" }) do
		SetTextColorSafe(n, TEXT_COLOR)
	end
	if rf then
		SetTextColorSafe("QuestInfoRewardsFrameItemChooseText", TEXT_COLOR)
		if rf.ItemChooseText then rf.ItemChooseText:SetTextColor(unpack(TEXT_COLOR)) end
		if rf.ItemReceiveText then rf.ItemReceiveText:SetTextColor(unpack(TEXT_COLOR)) end
		if rf.PlayerTitleText then rf.PlayerTitleText:SetTextColor(unpack(TEXT_COLOR)) end
		if rf.XPFrame and rf.XPFrame.ReceiveText then rf.XPFrame.ReceiveText:SetTextColor(unpack(TEXT_COLOR)) end
	end
	local money = GetQuestLogRequiredMoney and GetQuestLogRequiredMoney() or 0
	if money > 0 then
		SetTextColorSafe("QuestInfoRequiredMoneyText", money > GetMoney() and DIM_COLOR or TITLE_COLOR)
	end
end

local function RecolorQuestLog()
	for _, n in ipairs({ "QuestLogDescriptionTitle", "QuestLogRewardTitleText", "QuestLogQuestTitle" }) do
		SetTextColorSafe(n, TITLE_COLOR)
	end
	for _, n in ipairs({ "QuestLogItemChooseText", "QuestLogItemReceiveText", "QuestLogObjectivesText", "QuestLogQuestDescription", "QuestLogSpellLearnText" }) do
		SetTextColorSafe(n, TEXT_COLOR)
	end
	local money = GetQuestLogRequiredMoney and GetQuestLogRequiredMoney() or 0
	if money > 0 then
		SetTextColorSafe("QuestLogRequiredMoneyText", money > GetMoney() and DIM_COLOR or TITLE_COLOR)
	end
	-- objectives: finished = gold, unfinished = red
	local numObjectives = GetNumQuestLeaderBoards and GetNumQuestLeaderBoards() or 0
	local visible = 0
	for i = 1, numObjectives do
		local _, objType, finished = GetQuestLogLeaderBoard(i)
		if objType ~= "spell" then
			visible = visible + 1
			local obj = _G["QuestLogObjective" .. visible]
			if obj then obj:SetTextColor(unpack(finished and TITLE_COLOR or { 0.63, 0.09, 0.09 })) end
		end
	end
end

local function RecolorQuestProgress()
	SetTextColorSafe("QuestProgressTitleText", TITLE_COLOR)
	SetTextColorSafe("QuestProgressText", TEXT_COLOR)
	SetTextColorSafe("QuestProgressRequiredItemsText", TITLE_COLOR)
	local money = GetQuestMoneyToGet and GetQuestMoneyToGet() or 0
	if money > 0 then
		SetTextColorSafe("QuestProgressRequiredMoneyText", money > GetMoney() and DIM_COLOR or TITLE_COLOR)
	end
end

-- quest greeting panel: available = gold, already-on = dimmed
local function RecolorQuestGreeting()
	SetTextColorSafe("GreetingText", TEXT_COLOR)
	SetTextColorSafe("CurrentQuestsText", TITLE_COLOR)
	SetTextColorSafe("AvailableQuestsText", TITLE_COLOR)
	local i = 1
	local title = _G["QuestTitleButton" .. i]
	while title do
		SkinParchmentButton(title)
		local fs = title.GetFontString and title:GetFontString()
		if fs then fs:SetTextColor(unpack(title.isActive == 1 and DIM_COLOR or TITLE_COLOR)) end
		i = i + 1
		title = _G["QuestTitleButton" .. i]
	end
end

-- classic talent frame: style talent squares, keep icons/tree art visible
function SK:SkinTalents(frame)
	if not frame or frame.suiTalentDone then return end
	frame.suiTalentDone = true
	local name = frame:GetName() or "PlayerTalentFrame"
	-- inset: backdrop stops 32px short of the right edge and extends 76px
	-- below, where the spec/pet tabs and the Learn/Reset buttons sit
	local bd = frame.suiBackdrop
	if bd then
		bd:ClearAllPoints()
		bd:SetPoint("TOPLEFT", frame, "TOPLEFT", 11, -12)
		bd:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -32, 76)
	end
	-- bottom tabs (Talenten/Spezialisierung/etc.) onto the extended backdrop
	local tab1 = _G.PlayerTalentFrameTab1
	for i = 1, 4 do
		local t = _G["PlayerTalentFrameTab" .. i]
		if t then S:SkinTab(t) end
	end
	if tab1 then
		tab1:ClearAllPoints()
		tab1:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 1, 76)
		for i = 2, 4 do
			local t = _G["PlayerTalentFrameTab" .. i]
			local prev = _G["PlayerTalentFrameTab" .. (i - 1)]
			if t and prev then t:ClearAllPoints() t:SetPoint("TOPLEFT", prev, "TOPRIGHT", -19, 0) end
		end
	end
	-- flat inspect-style grid: the tree's branch/arrow art can live on the
	-- frame, the talent panels or the scroll child - hide all of it and keep
	-- hiding it, because TalentFrame_Update re-paints branches every refresh
	local function HideBranches(f, depth)
		if not f or not f.GetRegions or (depth or 0) > 3 then return end
		for i = 1, select("#", f:GetRegions()) do
			local r = select(i, f:GetRegions())
			if r:IsObjectType("Texture") then
				local rn = r.GetName and r:GetName() or ""
				local tp = r.GetTexture and r:GetTexture()
				if rn:find("Branch") or rn:find("Arrow") or (type(tp) == "string" and tp:lower():find("branch")) then
					r:SetAlpha(0)
					r:Hide()
				end
			end
		end
		if f.GetChildren then
			for i = 1, select("#", f:GetChildren()) do
				HideBranches(select(i, f:GetChildren()), (depth or 0) + 1)
			end
		end
	end
	HideBranches(frame)
	local sc = _G.PlayerTalentFrameScrollFrame or frame.ScrollFrame
	if sc then HideBranches(sc) end
	for _, fn in ipairs({ "TalentFrame_Update", "PlayerTalentFrame_Update", "PlayerTalentFrame_UpdateSpecs" }) do
		if type(_G[fn]) == "function" then
			hooksecurefunc(fn, function()
				HideBranches(frame)
				if sc then HideBranches(sc) end
			end)
		end
	end
	-- talent buttons: dark square + framed icon + rank font; icon alpha is pinned
	-- because Blizzard re-assigns the texture on every update
	for i = 1, (_G.MAX_NUM_TALENTS or 40) do
		local talent = _G[name .. "Talent" .. i] or _G["PlayerTalentFrameTalent" .. i]
		if talent and not talent.suiSkinned then
			talent.suiSkinned = true
			local tname = talent:GetName()
			local icon = talent.icon or talent.IconTexture or (tname and _G[tname .. "IconTexture"])
			local rank = talent.Rank or (tname and _G[tname .. "Rank"])
			for j = 1, select("#", talent:GetRegions()) do
				local r = select(j, talent:GetRegions())
				if r:IsObjectType("Texture") and r ~= icon then r:SetAlpha(0) end
			end
			S:CreateBackdrop(talent, "Default")
			S:AddHover(talent)
			if icon then
				icon:SetAlpha(1)
				icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				S:SetInside(icon, talent, 2, 2)
				if icon.SetDrawLayer then icon:SetDrawLayer("ARTWORK") end
				hooksecurefunc(talent, "SetNormalTexture", function(t)
					local ic = t.icon or t.IconTexture or (tname and _G[tname .. "IconTexture"])
					if ic then ic:SetAlpha(1) end
				end)
			end
			if rank and rank.SetFont then S:SetFont(rank, S.media.numberFont, 12, "OUTLINE") end
		end
	end
	-- spec tabs: square icon buttons hanging off the left edge like book tabs
	for i = 1, (_G.MAX_TALENT_TABS or 3) do
		local tab = _G["PlayerSpecTab" .. i]
		if tab and not tab.suiSkinned then
			tab.suiSkinned = true
			local nt = tab.GetNormalTexture and tab:GetNormalTexture()
			S:StripTextures(tab)
			tab:SetSize(30, 30)
			local tbd = S:CreateBackdrop(tab, "Default")
			tbd:ClearAllPoints()
			tbd:SetPoint("TOPLEFT", -2, 2)
			tbd:SetPoint("BOTTOMRIGHT", 2, -2)
			S:AddHover(tab)
			if nt then
				nt:SetAlpha(1)
				nt:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				nt:ClearAllPoints()
				nt:SetPoint("TOPLEFT", 2, -2)
				nt:SetPoint("BOTTOMRIGHT", -2, 2)
				hooksecurefunc(tab, "SetNormalTexture", function()
					local cur = tab:GetNormalTexture()
					if cur then cur:SetAlpha(1) end
				end)
			end
			local hl = tab.GetHighlightTexture and tab:GetHighlightTexture()
			if hl then
				hl:SetTexture(BLANK)
				hl:SetVertexColor(1, 1, 1, 0.15)
				hl:ClearAllPoints()
				hl:SetAllPoints()
			end
			tab:ClearAllPoints()
			if i == 1 then
				tab:SetPoint("TOPRIGHT", frame, "TOPLEFT", 2, -60)
			else
				local prev = _G["PlayerSpecTab" .. (i - 1)]
				if prev then tab:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -6) end
			end
		end
	end
	-- activate / learn / reset buttons, status + preview bars, scrollbar
	local activate = _G.PlayerTalentFrameActivateButton
	if activate then S:SkinButton(activate) end
	local learn = _G.PlayerTalentFrameLearnButton
	local reset = _G.PlayerTalentFrameResetButton
	-- all stock bottom buttons park right-aligned on the backdrop row, chained
	-- right-to-left, so none of them can overlap the spent-points text
	-- the bottom "Schließen" button is redundant (the frame's top-right X
	-- already closes it): hide it, keep every other stock button parked
	local parkedRight
	for _, b in ipairs({
		_G.PlayerTalentFrameCancelButton,
		_G.PlayerTalentFrameOkayButton, _G.PlayerTalentFrameConfirmButton,
		_G.PlayerTalentFrameDoneButton, reset, learn }) do
		if b and b.IsObjectType and b:IsObjectType("Button") then
			local isClose
			if b.GetText then isClose = (b:GetText() == CLOSE) end
			if not isClose and b.GetFontString then
				local fs = b:GetFontString()
				isClose = fs and fs.GetText and fs:GetText() == CLOSE
			end
			if isClose then
				pcall(function() b:Hide() end)
			else
				S:SkinButton(b)
				b:ClearAllPoints()
				if parkedRight then
					b:SetPoint("RIGHT", parkedRight, "LEFT", -6, 0)
				else
					b:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -38, 80)
				end
				parkedRight = b
			end
		end
	end
	for _, n in ipairs({ "PlayerTalentFrameStatusFrame", "PlayerTalentFramePreviewBar", "PlayerTalentFramePreviewBarFiller", "PlayerTalentFramePointsBar" }) do
		local f = _G[n]
		if f then S:StripTextures(f) end
	end
	local sf = _G.PlayerTalentFrameScrollFrame
	if sf then
		S:CreateBackdrop(sf, "Transparent")
		-- make sure wheel scrolling works even if the template's own handler
		-- is missing (single-point scrollbar reanchors used to collapse it)
		sf:EnableMouseWheel(true)
		if not sf:GetScript("OnMouseWheel") then
			sf:SetScript("OnMouseWheel", function(s, d)
				s:SetVerticalScroll((s:GetVerticalScroll() or 0) - d * 40)
			end)
		end
	end
	local sb = _G.PlayerTalentFrameScrollFrameScrollBar
	if sb then
		S:SkinScrollBar(sb)
		if sf then
			sb:ClearAllPoints()
			sb:SetPoint("TOPLEFT", sf, "TOPRIGHT", 10, -16)
			sb:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 10, 16)
		end
	end
	-- points bar like the inspect view: "Für X-Talente verteilte Punkte: N"
	-- left, "Talentpunkte: N" right. SpentPointsText lives inside the hidden
	-- StatusFrame on some clients - re-home it into the visible bar
	local spent = _G.PlayerTalentFrameSpentPointsText
	local points = _G.PlayerTalentFrameTalentPointsText
	local pb = _G.PlayerTalentFramePointsBar
	if pb then
		pb:Show()
		if not pb.suiBackdrop then S:CreateBackdrop(pb, "Default") end
		if spent then
			if spent.SetParent then spent:SetParent(pb) end
			if spent.SetDrawLayer then spent:SetDrawLayer("ARTWORK") end
			S:SetFont(spent, S.media.numberFont, 11)
			spent:ClearAllPoints()
			-- use the full row width, not just the narrow PointsBar
			spent:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 82)
			spent:SetJustifyH("LEFT")
			spent:Show()
			-- Blizzard only formats it during certain control updates; fill it
			-- ourselves every refresh so it always shows the full localized text
			local function FillSpent()
				local tab = PlayerTalentFrame and PlayerTalentFrame.selectedTab or 1
				local name, pts
				if GetTalentTabInfo then
					-- TBC: name, icon, pointsSpent | newer: id, name, desc, icon, pointsSpent
					local a, b, c, d, e = GetTalentTabInfo(tab)
					if type(a) == "number" then name, pts = b, e else name, pts = a, c end
				end
				if not name and C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
					local _, n, _, _, _, _, p = C_SpecializationInfo.GetSpecializationInfo(tab, false, false, nil, nil, PlayerTalentFrame and PlayerTalentFrame.talentGroup)
					name, pts = n, p
				end
				if name then
					spent:SetFormattedText(MASTERY_POINTS_SPENT or "%s: %d", name, tonumber(pts) or 0)
				end
			end
			C_Timer.After(0, FillSpent)
			if type(_G.TalentFrame_Update) == "function" then hooksecurefunc("TalentFrame_Update", FillSpent) end
			if type(_G.PlayerTalentFrame_Update) == "function" then hooksecurefunc("PlayerTalentFrame_Update", FillSpent) end
		end
		if points then
			S:SetFont(points, S.media.numberFont, 11)
			points:ClearAllPoints()
			if parkedRight and parkedRight:IsShown() then
				points:SetPoint("RIGHT", parkedRight, "LEFT", -10, 0)
			else
				-- pb is narrower than the row: pin to the frame's right edge on
				-- the same line the parked buttons sit on
				points:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -38, 82)
			end
			points:SetJustifyH("RIGHT")
			points:Show()
		end
	end
end

-- objective tracker (right side): unify fonts, skin its expand/collapse and
-- quest-item buttons without turning the tracker into a window
function SK:SkinQuestTracker(frame)
	if not frame or frame.suiTrackerDone then return end
	frame.suiTrackerDone = true
	local function Style(f, depth)
		if not f.GetRegions or (depth or 0) > 4 then return end
		for i = 1, select("#", f:GetRegions()) do
			local r = select(i, f:GetRegions())
			if r:IsObjectType("FontString") and r.SetFont then S:SetFont(r, S.media.font, 12) end
		end
		if f.GetChildren then
			for i = 1, select("#", f:GetChildren()) do
				local c = select(i, f:GetChildren())
				if c:IsObjectType("Button") then
					local n = c:GetName() or ""
					if n:find("Item") then
						-- quest item button: framed icon
						if not c.suiSkinned then
							c.suiSkinned = true
							S:CreateBackdrop(c, "Default")
							local icon = c.icon or c.Icon or (n ~= "" and _G[n .. "IconTexture"])
							if icon then
								icon:SetAlpha(1)
								icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
								S:SetInside(icon, c, 2, 2)
							end
						end
					elseif not c.suiSkinned and (c.GetNormalTexture and c:GetNormalTexture()) then
						c.suiSkinned = true
						pcall(S.SkinButton, S, c)
					end
				end
				Style(c, (depth or 0) + 1)
			end
		end
	end
	Style(frame)
	-- tracker rows get created on updates: restyle after each layout pass
	for _, fn in ipairs({ "WatchFrame_Update", "ObjectiveTracker_Update", "QuestWatch_Update" }) do
		if type(_G[fn]) == "function" then
			hooksecurefunc(fn, function() S:SafeCall("Skins:TrackerRefresh", Style, frame) end)
		end
	end
end

-- talking head popup: unify the text font, keep the portrait frame shape
function SK:SkinTalkingHead(frame)
	if not frame or frame.suiTalkDone then return end
	frame.suiTalkDone = true
	for i = 1, select("#", frame:GetRegions()) do
		local r = select(i, frame:GetRegions())
		if r:IsObjectType("FontString") and r.SetFont then S:SetFont(r, S.media.font, 13) end
	end
	if frame.GetChildren then
		for i = 1, select("#", frame:GetChildren()) do
			local c = select(i, frame:GetChildren())
			for j = 1, select("#", c:GetRegions()) do
				local r = select(j, c:GetRegions())
				if r:IsObjectType("FontString") and r.SetFont then S:SetFont(r, S.media.font, 13) end
			end
		end
	end
end

-- quest log list: fonts, highlight, colors by state, styled controls
local function StyleQuestLog()
	if not _G.QuestLogFrame then return end
	for _, n in ipairs({ "QuestLogTitleText", "QuestLogQuestCount", "QuestLogTitle1" }) do
		local fs = _G[n]
		if fs and fs.SetFont then S:SetFont(fs, S.media.font, 13, "OUTLINE") end
		if fs and fs.SetTextColor then fs:SetTextColor(unpack(TITLE_COLOR)) end
	end
	for _, n in ipairs({ "EmptyQuestLogFrameText", "QuestLogNoQuestsText", "QuestLogDummyText" }) do
		local fs = _G[n]
		if fs and fs.SetFont then S:SetFont(fs, S.media.font, 12) end
		if fs and fs.SetTextColor then fs:SetTextColor(unpack(TEXT_COLOR)) end
	end
	for i = 1, 30 do
		local b = _G["QuestLogTitleButton" .. i]
		if not b then break end
		local name = b:GetName()
		local normal = b.GetNormalFontObject and b:GetNormalFontObject() or _G[name .. "NormalText"]
		local hl = _G[name .. "Highlight"]
		local tag = _G[name .. "Tag"]
		if normal then S:SetFont(normal, S.media.font, 12, "OUTLINE") end
		if tag then S:SetFont(tag, S.media.font, 11, "OUTLINE") end
		if hl then
			hl:SetTexture(BLANK)
			hl:SetVertexColor(S.accent.r, S.accent.g, S.accent.b, 0.14)
		end
	end
	-- controls: track checkbox, abandon/share buttons, expand-all, count
	local track = _G.QuestLogTrack
	if track then S:SkinCheckBox(track) end
	local trackLabel = _G["QuestLogTrackTracking"] or _G.QuestLogTrackTracking
	if trackLabel and trackLabel.SetFont then S:SetFont(trackLabel, S.media.font, 12, "OUTLINE") end
	for _, n in ipairs({ "QuestLogFrameAbandonButton", "QuestLogPushQuestButton", "QuestLogFrameTrackButton" }) do
		local b = _G[n]
		if b and b.IsObjectType and b:IsObjectType("Button") then S:SkinButton(b) end
	end
	local expand = _G.QuestLogExpandButtonFrame
	if expand then
		local collapse = _G.QuestLogCollapseAllButton
		if collapse then
			S:SkinButton(collapse)
			local tex = collapse.GetNormalTexture and collapse:GetNormalTexture()
			if tex then tex:SetAlpha(0) end
			if collapse.SetText then
				collapse:SetText("+/-")
				local cfs = collapse.GetFontString and collapse:GetFontString()
				if cfs then cfs:SetTextColor(unpack(TITLE_COLOR)) end
			end
		end
	end
end

-- recolor quest titles: headers = accent, complete = gold, failed = red
local function RecolorQuestTitles()
	if not (GetNumQuestLogEntries and GetQuestLogTitle) then return end
	local entries = GetNumQuestLogEntries()
	for i = 1, 30 do
		local b = _G["QuestLogTitleButton" .. i]
		if not b then break end
		local idx = b.questLogIndex or (b.GetID and b:GetID()) or 0
		if idx >= 1 and idx <= entries and b:IsShown() then
			local isHeader, isComplete
			local ok, info = pcall(GetQuestLogTitle, idx)
			if ok then
				if type(info) == "table" then
					isHeader = info.isHeader or info.header
					isComplete = info.isComplete
				else
					-- classic returns: title, level, suggestedGroup, isHeader, isCollapsed, isComplete
					isHeader = select(4, GetQuestLogTitle(idx))
					isComplete = select(6, GetQuestLogTitle(idx))
				end
			end
			local fs = b.GetNormalFontObject and _G[b:GetName() .. "NormalText"]
			if fs then
				if isHeader then fs:SetTextColor(unpack({ S.accent.r, S.accent.g, S.accent.b }))
				elseif isComplete == -1 then fs:SetTextColor(0.7, 0.3, 0.3)
				elseif isComplete == 1 then fs:SetTextColor(unpack(TITLE_COLOR))
				else fs:SetTextColor(1, 1, 1) end
			end
		end
	end
end

function SK:SkinQuest(frame)
	if self.suiQuestSkinned then return end
	self.suiQuestSkinned = true
	if QuestInfo_Display then hooksecurefunc("QuestInfo_Display", RecolorQuestInfo) end
	if QuestFrameItems_Update then hooksecurefunc("QuestFrameItems_Update", RecolorQuestLog) end
	if QuestFrameProgressItems_Update then hooksecurefunc("QuestFrameProgressItems_Update", RecolorQuestProgress) end
	if QuestFrameGreetingPanel_OnShow then hooksecurefunc("QuestFrameGreetingPanel_OnShow", RecolorQuestGreeting) end
	local gp = _G.QuestFrameGreetingPanel
	if gp then gp:HookScript("OnShow", RecolorQuestGreeting) end
	S:SafeCall("Skins:QuestLog", StyleQuestLog)
	if QuestLog_Update then
		hooksecurefunc("QuestLog_Update", function() S:SafeCall("Skins:QuestLogColors", RecolorQuestTitles) end)
		S:SafeCall("Skins:QuestLogColors", RecolorQuestTitles)
	end
end

-- classic tradeskill/craft windows (TBC): strip parchment chrome, style the
-- skill list, rank bar, reagent slots and controls in the Sentinel look
local function StyleTradeSkillBase(prefix, frame)
	local g = function(n) return _G[prefix .. n] end
	-- kill every leftover texture region except skill/reagent icons
	for i = 1, select("#", frame:GetRegions()) do
		local r = select(i, frame:GetRegions())
		if r:IsObjectType("Texture") and r ~= g("SkillIcon") then
			local layer = r:GetDrawLayer()
			if layer == "BACKGROUND" or layer == "BORDER" or layer == "OVERLAY" then r:SetAlpha(0) end
		end
	end
	for _, n in ipairs({ "TitleText", "SkillLineName", "SkillName", "Description", "RequirementLabel", "ReagentLabel", "RequiredTools", "Cooldown", "SkillDescription", "RequirementText" }) do
		local fs = g(n)
		if fs and fs.SetFont then S:SetFont(fs, S.media.font, 12, "OUTLINE") end
	end
	-- skill list buttons (TBC: TradeSkillSkill1..8 / Craft1..8)
	for i = 1, 12 do
		local b = g("Skill" .. i) or g(i)
		if not b then break end
		local name = b:GetName()
		if name then
			local normal = _G[name .. "Text"] or _G[name .. "NormalText"]
			if normal and normal.SetFont then S:SetFont(normal, S.media.font, 12, "OUTLINE") end
			local hl = _G[name .. "Highlight"]
			if hl then hl:SetTexture(BLANK) hl:SetVertexColor(S.accent.r, S.accent.g, S.accent.b, 0.12) end
			-- collapse/expand arrow -> flat square
			local exp = _G[name .. "Collapse"] or b.collapseButton
			if exp and exp.IsObjectType and exp:IsObjectType("Button") then S:SkinButton(exp) end
		end
	end
	-- rank bar -> sentinel statusbar
	local rank = g("RankFrame")
	if rank then
		S:StripTextures(rank)
		if rank.SetStatusBarTexture then rank:SetStatusBarTexture(S.media.statusbar) end
		S:CreateBackdrop(rank, "Default")
		local rankTxt = g("RankFrameSkillRank") or g("RankFrameSkillLine")
		if rankTxt then S:SetFont(rankTxt, S.media.numberFont, 11, "OUTLINE") rankTxt:SetTextColor(1, 1, 1) end
	end
	-- highlight glow behind the selected skill icon -> subtle accent frame
	local hlFrame = g("HighlightFrame") or g("Highlight")
	if hlFrame then S:StripTextures(hlFrame) end
	-- reagent + output icons: framed slots
	for i = 1, 12 do
		local slot = g("Reagent" .. i)
		if slot then
			local name = slot:GetName()
			local icon = name and _G[name .. "IconTexture"]
			if icon then
				if not slot.suiSlotBd then
					S:StripTextures(slot)
					slot.suiSlotBd = S:CreateBackdrop(slot, "Default")
					slot.suiSlotBd:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
					slot.suiSlotBd:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
				end
				icon:SetAlpha(1)
				icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			end
			local cnt = name and (_G[name .. "Count"] or _G[name .. "Name"])
			if cnt and cnt.SetFont then S:SetFont(cnt, S.media.numberFont, 11, "OUTLINE") end
		end
	end
	local big = g("SkillIcon") or g("Icon")
	if big and big.SetTexCoord then
		big:SetAlpha(1)
		big:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		if not big.suiSlotBd then big.suiSlotBd = S:CreateBackdrop(big, "Default") end
	end
	-- dropdowns (slot/subclass filters), create/create-all/cancel buttons,
	-- count editbox, expand-all button, scrollbars
	for _, n in ipairs({ "InvSlotDropDown", "InvSlotDropdown", "SubClassDropDown", "SubClassDropdown" }) do
		local dd = g(n)
		if dd then
			local nm = dd:GetName()
			if S.LogInfo and not dd.suiDumped then
				dd.suiDumped = true
				local parts = {}
				for j = 1, select("#", dd:GetRegions()) do
					local r = select(j, dd:GetRegions())
					parts[#parts + 1] = (r:GetName() or "?") .. ":" .. r:GetObjectType()
				end
				for j = 1, select("#", dd:GetChildren()) do
					local c = select(j, dd:GetChildren())
					parts[#parts + 1] = "child:" .. (c:GetName() or "?")
				end
				S:LogInfo("skins", "dd-dump " .. (nm or "?") .. " = " .. table.concat(parts, ", "))
			end
			S:SkinDropDown(dd)
			-- normalize text + arrow so the selection sits inside the dark box
			local txt = dd.Text or (nm and _G[nm .. "Text"])
			if txt and txt.SetFont then
				S:SetFont(txt, S.media.font, 11, "OUTLINE")
				txt:SetTextColor(1, 1, 1)
				txt:ClearAllPoints()
				txt:SetPoint("LEFT", dd, "LEFT", 8, 2)
				txt:SetPoint("RIGHT", dd, "RIGHT", -22, 2)
				txt:SetJustifyH("LEFT")
			end
			local btn = dd.Button or (nm and _G[nm .. "Button"])
			if btn and btn.ClearAllPoints then
				btn:ClearAllPoints()
				btn:SetPoint("RIGHT", dd, "RIGHT", -3, 2)
			end
			local lbl = nm and _G[nm .. "Label"]
			if lbl and lbl.SetFont then S:SetFont(lbl, S.media.font, 11, "OUTLINE") end
		end
	end
	-- the two filter dropdowns overlap on the default layout - split them:
	-- InvSlot stays anchored, SubClass docks to its left
	local inv = g("InvSlotDropDown") or g("InvSlotDropdown")
	local sub = g("SubClassDropDown") or g("SubClassDropdown")
	if inv and sub and inv ~= sub then
		pcall(function()
			if inv.SetWidth then inv:SetWidth(112) end
			if sub.SetWidth then sub:SetWidth(140) end
		end)
		local depends
		for p = 1, inv:GetNumPoints() do
			local _, relTo = inv:GetPoint(p)
			if relTo == sub then depends = true end
		end
		if depends then
			inv:ClearAllPoints()
			inv:SetPoint("TOPRIGHT", sub, "TOPLEFT", -8, 0)
		else
			sub:ClearAllPoints()
			sub:SetPoint("TOPRIGHT", inv, "TOPLEFT", -8, 0)
		end
	end
	for _, n in ipairs({ "CreateButton", "CreateAllButton", "CancelButton", "DecrementButton", "IncrementButton" }) do
		local b = g(n)
		if b and b.IsObjectType and b:IsObjectType("Button") then S:SkinButton(b) end
	end
	local box = g("CreateInputBox") or g("InputBox") or g("CountInputBox")
	if box and box.IsObjectType and box:IsObjectType("EditBox") then S:SkinEditBox(box) end
	local expandAll = g("CollapseAllButton") or g("ExpandAllButton")
	if expandAll and expandAll.IsObjectType and expandAll:IsObjectType("Button") then S:SkinButton(expandAll) end
	-- the expand/collapse "All" tab loses its chrome when the frame textures
	-- are stripped: give it a real plate and dock it into the filter row,
	-- left of the dropdowns - at its stock spot it read as floating text
	local expandFrame = g("ExpandButtonFrame")
	if expandFrame then
		S:StripTextures(expandFrame)
		if not expandFrame.suiBackdrop then S:CreateBackdrop(expandFrame, "Default") end
		local subDD = g("SubClassDropDown") or g("SubClassDropdown")
		if subDD then
			expandFrame:ClearAllPoints()
			expandFrame:SetPoint("RIGHT", subDD, "LEFT", -6, 2)
			expandFrame:SetSize(56, 24)
		end
		if expandAll then
			expandAll:ClearAllPoints()
			expandAll:SetPoint("CENTER", expandFrame, "CENTER")
			expandAll:SetSize(50, 20)
			-- the template caption keeps its stock anchor (relative to the
			-- stripped tab/icon) - pin it onto the button itself
			local cap = (expandAll.GetFontString and expandAll:GetFontString())
				or expandAll.text or (expandAll.GetName and expandAll:GetName() and _G[expandAll:GetName() .. "Text"])
			if cap and cap.ClearAllPoints then
				cap:ClearAllPoints()
				cap:SetPoint("CENTER", expandAll, "CENTER", 0, 0)
				if cap.SetJustifyH then cap:SetJustifyH("CENTER") end
				if cap.SetWidth then cap:SetWidth(46) end
			end
		end
	end
	-- scrollbars inside the list/detail scroll frames
	for _, n in ipairs({ "ListScrollFrameScrollBar", "DetailScrollFrameScrollBar", "ListScrollFrame", "DetailScrollFrame" }) do
		local sc = g(n)
		if sc then
			if sc:IsObjectType("Slider") then S:SkinScrollBar(sc) else S:SkinChildren(sc) end
		end
	end
	-- the parchment lives inside the scroll child frames - strip them too
	for _, n in ipairs({ "ListScrollFrame", "DetailScrollFrame", "DetailScrollChildFrame" }) do
		local sf = g(n)
		if sf then
			S:StripTextures(sf)
			for i = 1, select("#", sf:GetChildren()) do
				local c = select(i, sf:GetChildren())
				if c and c.GetRegions then
					for j = 1, select("#", c:GetRegions()) do
						local r = select(j, c:GetRegions())
						local rn = r.GetName and r:GetName() or ""
						if r:IsObjectType("Texture") and not rn:find("IconTexture") and not rn:find("ItemIcon")
							and (r:GetDrawLayer() == "BACKGROUND" or r:GetDrawLayer() == "BORDER") then
							r:SetAlpha(0)
						end
					end
				end
			end
		end
	end
	S:SkinChildren(frame)
	if S.LogInfo then S:LogInfo("skins", prefix .. " styled") end
end

function SK:SkinTradeSkill(frame)
	if not frame then return end
	StyleTradeSkillBase("TradeSkill", frame)
end

function SK:SkinCraft(frame)
	if not frame then return end
	StyleTradeSkillBase("Craft", frame)
end

-- guild bank: per-slot item level + quality border + count font
-- Blizzard bank restyle (all clients): keeps the native layout - vault slots,
-- purchase button, bank contents - but in the Sentinel look plus a sort button.
function SK:SkinBank(frame)
	if not frame then return end
	local name = frame:GetName() or "BankFrame"
	local title = frame.TitleText or frame.Title or _G[name .. "TitleText"]
	if title then
		S:SetFont(title, nil, 14, "OUTLINE")
		title:SetTextColor(1, 1, 1)
	end
	local close = frame.CloseButton or _G.BankCloseButton or _G.BankFrameCloseButton or _G[name .. "CloseButton"]
	if close then S:SkinCloseButton(close) end
	local purchase = _G.BankFramePurchaseButton
	if purchase then S:SkinButton(purchase) end
	local purchaseInfo = _G.BankFramePurchaseInfo
	if purchaseInfo then
		S:StripTextures(purchaseInfo)
		S:CreateBackdrop(purchaseInfo, "Transparent")
	end

	local function SkinSlot(b)
		if not b or b.suiBankSkinned then return end
		b.suiBankSkinned = true
		local bn = b:GetName()
		local icon = b.icon or b.Icon or (bn and _G[bn .. "IconTexture"])
		local normal = b.GetNormalTexture and b:GetNormalTexture()
		if normal then normal:SetAlpha(0) end
		if icon then
			icon:SetAlpha(1)
			icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			S:SetInside(icon, b, 0, 0)
		end
		S:CreateBackdrop(b, "Default")
		local count = bn and (_G[bn .. "Count"] or _G[bn .. "CountText"])
		if count then S:SetFont(count, S.media.numberFont, 12, "OUTLINE") end
		local hl = b.GetHighlightTexture and b:GetHighlightTexture()
		if hl then
			hl:SetTexture(BLANK)
			hl:SetVertexColor(1, 1, 1, 0.12)
			S:SetInside(hl, b)
		end
	end
	local function SkinAll()
		-- main bank slots; button names differ between builds
		for i = 1, 40 do
			local b = _G["BankFrameItem" .. i] or _G["BankItem" .. i]
			if not b then break end
			SkinSlot(b)
		end
		-- equipped bank bags (the "vault" row)
		for i = 1, 12 do
			local b = _G["BankFrameBag" .. i] or _G["BankItemButtonBag" .. i] or _G["BankItemBag" .. i]
			if not b then break end
			SkinSlot(b)
		end
		-- fallback for builds with unnamed children
		local host = _G.BankSlotsFrame or frame
		for i = 1, select("#", host:GetChildren()) do
			local c = select(i, host:GetChildren())
			if c.IsObjectType and c:IsObjectType("Button") then SkinSlot(c) end
		end
	end

	-- Sentinel sort button next to the close button; sorts our bank containers
	-- (works with the blizzard display because it refreshes on BAG_UPDATE)
	if not frame.suiSortBtn then
		local Bags = S:GetModule("Bags")
		local btn = CreateFrame("Button", "SentinelUIBankSort", frame)
		btn:SetSize(20, 20)
		S:CreateBackdrop(btn, "Default")
		local tex = btn:CreateTexture(nil, "ARTWORK")
		tex:SetTexture(S.media.iconSort)
		tex:SetTexCoord(0.04, 0.96, 0.04, 0.96)
		S:SetInside(tex, btn, 2, 2)
		if close then
			btn:SetPoint("RIGHT", close, "LEFT", -6, 0)
		else
			btn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -32, -4)
		end
		btn:SetScript("OnClick", function()
			if Bags and Bags.SortBank then Bags:SortBank() end
		end)
		btn:SetScript("OnEnter", function(self)
			S.HoverEnter(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(L["Sort"], 1, 1, 1)
			GameTooltip:Show()
		end)
		btn:SetScript("OnLeave", function(self) S.HoverLeave(self) GameTooltip:Hide() end)
		frame.suiSortBtn = btn
	end

	-- slots are shown/hidden by the native bank update; re-skin lazily
	frame:HookScript("OnShow", function() C_Timer.After(0, SkinAll) end)
	if _G.BankFrame_Update then hooksecurefunc("BankFrame_Update", SkinAll) end
	SkinAll()
end

function SK:SkinGuildBank(frame)
	if not frame then return end
	local NUM_COLS, SLOTS_PER_COL = 7, 14
	local function UpdateSlot(button)
		if not button then return end
		if not button.suiGBSkinned then
			button.suiGBSkinned = true
			local name = button:GetName()
			local icon = button.icon or button.Icon or (name and _G[name .. "IconTexture"])
			local tex = icon and icon.GetTexture and icon:GetTexture()
			S:StripTextures(button)
			S:CreateBackdrop(button, "Default")
			button.suiGBIcon = icon
			if icon then
				icon:SetAlpha(1)
				icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				S:SetInside(icon, button, 1, 1)
				if tex then icon:SetTexture(tex) end
			end
			button.suiGBIlvl = S:FontString(button, 11, "OUTLINE")
			button.suiGBIlvl:SetPoint("BOTTOM", button, "BOTTOM", 0, 2)
			local count = button.Count or (name and _G[name .. "Count"])
			if count then
				S:SetFont(count, S.media.numberFont, 12, "OUTLINE")
				count:ClearAllPoints()
				count:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
			end
		end
		local link = GetCurrentGuildBankTab and GetGuildBankItemLink and GetGuildBankItemLink(GetCurrentGuildBankTab(), button:GetID())
		local icon = button.suiGBIcon
		if link then
			local _, _, q, _, _, _, _, _, _, _, _, classID = S.GetItemInfo(link)
			local ilvl = S.GetDetailedItemLevelInfo and S.GetDetailedItemLevelInfo(link)
			if q and q > 1 then
				local r, g, b = S.GetItemQualityColor(q)
				button.suiBackdrop:SetBackdropBorderColor(r, g, b)
			else
				button.suiBackdrop:SetBackdropBorderColor(unpack(S.media.borderColor))
			end
			if ilvl and ilvl > 1 and (classID == 2 or classID == 4) then
				local r, g, b = S.GetItemQualityColor(q or 1)
				button.suiGBIlvl:SetText(ilvl)
				button.suiGBIlvl:SetTextColor(r, g, b)
			else
				button.suiGBIlvl:SetText("")
			end
			if icon then icon:SetAlpha(1) end
		else
			button.suiGBIlvl:SetText("")
			button.suiBackdrop:SetBackdropBorderColor(unpack(S.media.borderColor))
		end
	end
	local function UpdateAll()
		-- retail names columns ColumnN, classic/TBC names them GuildBankColumnN
		for c = 1, NUM_COLS + 1 do
			local col = frame["Column" .. c] or frame["GuildBankColumn" .. c] or _G["GuildBankColumn" .. c]
			if col then
				for s = 1, SLOTS_PER_COL do
					local btn = col["Button" .. s] or col["GuildBankButton" .. s] or _G["GuildBankColumn" .. c .. "Button" .. s]
					if btn then UpdateSlot(btn) end
				end
			end
		end
	end
	if frame.Update then
		hooksecurefunc(frame, "Update", UpdateAll)
	elseif GuildBankFrame_Update then
		hooksecurefunc("GuildBankFrame_Update", UpdateAll)
	end
	UpdateAll()
end

function SK:SkinGossip(frame)
	if self.suiGossipSkinned then return end
	self.suiGossipSkinned = true

	local gf = _G.GossipFrame
	local classicButtons, found = 0, {}
	SetTextColorSafe("GossipGreetingText", TEXT_COLOR)
	found.GreetingText = _G.GossipGreetingText and true or false
	while _G["GossipTitleButton" .. (classicButtons + 1)] do
		classicButtons = classicButtons + 1
		SkinParchmentButton(_G["GossipTitleButton" .. classicButtons])
	end
	found.titleButtons = classicButtons

	-- modern client: GreetingPanel with ScrollBox holding greeting text + option buttons
	local gp = gf and (gf.GreetingPanel or _G.GossipFrameGreetingPanel)
	found.greetingPanel = gp and true or false
	if gp then
		S:StripTextures(gp)
		for _, childName in ipairs({ "ScrollBox", "GoodbyeButton", "GoodbyeGossipButton", "ScrollBar" }) do
			local child = gp[childName]
			if child then found[childName] = true end
		end
		if gp.ScrollBox and gp.ScrollBox.ForEachFrame then
			local function RecolorBox(sb)
				sb:ForEachFrame(function(f)
					if f:IsObjectType("Button") then
						SkinParchmentButton(f)
					elseif f:IsObjectType("Frame") then
						for j = 1, select("#", f:GetRegions()) do
							local region = select(j, f:GetRegions())
							if region:IsObjectType("FontString") then
								region:SetTextColor(1, 1, 1)
								if not region.suiParchment then
									region.suiParchment = true
									hooksecurefunc(region, "SetTextColor", ForceTextColor)
								end
							end
						end
					end
				end)
			end
			hooksecurefunc(gp.ScrollBox, "Update", RecolorBox)
			RecolorBox(gp.ScrollBox)
		end
		local bye = gp.GoodbyeButton or gp.GoodbyeGossipButton
		if bye and bye.GetFontString then
			local fs = bye:GetFontString()
			if fs then fs:SetTextColor(1, 1, 1) end
		end
		-- parchment behind the scroll area -> transparent backdrop
		if gp.ScrollBox and not gp.suiBg then
			local bd = CreateFrame("Frame", nil, gp, S.BackdropTemplate)
			bd:SetFrameLevel(math.max(0, gp:GetFrameLevel() - 1))
			S:SetOutside(bd, gp.ScrollBox, 4, 4)
			S:SetTemplate(bd, "Transparent")
			gp.suiBg = bd
		end
	end
	local i2 = 1
	while _G["GossipGreetingOptionButton" .. i2] do
		SkinParchmentButton(_G["GossipGreetingOptionButton" .. i2])
		i2 = i2 + 1
	end

	-- re-apply whenever the dialog (re)opens - Blizzard recolors on every show
	if gf and not gf.suiGossipHook then
		gf.suiGossipHook = true
		gf:HookScript("OnShow", function()
			SetTextColorSafe("GossipGreetingText", TEXT_COLOR)
			if gf.GreetingPanel and gf.GreetingPanel.ScrollBox and gf.GreetingPanel.ScrollBox.ForEachFrame then
				gf.GreetingPanel.ScrollBox:ForEachFrame(function(f)
					if f:IsObjectType("Button") then SkinParchmentButton(f) end
				end)
			end
		end)
	end

	-- books/item letters: Blizzard recolors on every open -> persistent hooks
	SkinReadableText(_G.ItemTextPageText)
	SkinReadableText(_G.ItemTextStatusText)
	SkinReadableTitle(_G.ItemTextTitleText)
	S:LogInfo("skins", "gossip skinned: panel=" .. tostring(found.greetingPanel) .. " greeting=" .. tostring(found.GreetingText) .. " titleBtns=" .. classicButtons .. " scrollBox=" .. tostring(found.ScrollBox or false))
end

function SK:SkinMail()
	-- open-mail text is dark parchment color -> same recolor-proof treatment
	SkinReadableText(_G.OpenMailBodyText)
	SkinReadableText(_G.OpenMailSubject)
	SkinReadableText(_G.OpenMailSender)
	SkinReadableTitle(_G.OpenMailTitleText)
	-- inbox rows use the same dark parchment font colors for sender, subject and
	-- days-left; the paper background is stripped by the skin, so the text
	-- renders dark-on-dark. Blizzard re-applies its colors on every inbox
	-- update -> re-apply ours via a hook instead of a one-shot recolor.
	local function LightInbox()
		for i = 1, (INBOXITEMS_TO_DISPLAY or 7) do
			local item = _G["MailItem" .. i] or _G["InboxItem" .. i]
			if item then
				for _, key in ipairs({ "Sender", "Subject", "ExpireTime", "COD", "sender", "subject", "expireTime" }) do
					local fs = item[key] or _G["MailItem" .. i .. key] or _G["InboxItem" .. i .. key]
					if fs and fs.SetTextColor then fs:SetTextColor(0.92, 0.92, 0.95) end
				end
			end
		end
		local page = _G.InboxCurrentPage
		if page and page.SetTextColor then page:SetTextColor(0.92, 0.92, 0.95) end
	end
	LightInbox()
	if not self.inboxLightHooked then
		self.inboxLightHooked = true
		for _, fn in ipairs({ "InboxFrame_Update", "MailFrame_Update", "InboxUpdateItems" }) do
			if _G[fn] then hooksecurefunc(fn, LightInbox) end
		end
	end
	-- one-shot diagnostic: if the inbox still looks empty we need to know what
	-- the frame actually contains (item rows hidden? no data? text invisible?)
	self:RegisterEvent("MAIL_SHOW", function()
		if self.inboxDiagDone then return end
		self.inboxDiagDone = true
		C_Timer.After(0.5, function()
			local parts = { "num=" .. tostring(GetInboxNumItems and GetInboxNumItems() or -1) }
			for i = 1, 3 do
				local item = _G["MailItem" .. i] or _G["InboxItem" .. i]
				if item then
					local s = _G["MailItem" .. i .. "Subject"] or _G["InboxItem" .. i .. "Subject"] or item.subject or item.Subject
					local r, g, b
					if s and s.GetTextColor then r, g, b = s:GetTextColor() end
					parts[#parts + 1] = "i" .. i .. "{shown=" .. tostring(item:IsShown())
						.. ",subj=" .. tostring(s and s.GetText and s:GetText())
						.. ",c=" .. tostring(r and format("%.2f,%.2f,%.2f", r, g, b)) .. "}"
				else
					parts[#parts + 1] = "i" .. i .. "=nil"
				end
			end
			S:LogInfo("mail", table.concat(parts, " "))
		end)
	end)
end

function SK:SkinGameMenu()
	local f = GameMenuFrame
	if not f or f.suiWindowSkinned then return end
	f.suiWindowSkinned = true
	S:SkinFrame(f)
	if f.Header then S:StripTextures(f.Header) end
	local header = _G.GameMenuFrameHeader
	if header then header:SetAlpha(0) end
	S:SkinChildren(f)
	if f.buttonPool then
		hooksecurefunc(f, "InitButtons", function(menu)
			for button in menu.buttonPool:EnumerateActive() do S:SkinButton(button) end
		end)
		for button in f.buttonPool:EnumerateActive() do S:SkinButton(button) end
	end
	-- Shortcut button inside the button list (inserted above Logout/Quit/Continue)
	if not f.suiButton then
		local b = CreateFrame("Button", "GameMenuButtonSentinelUI", f, "UIPanelButtonTemplate")
		b:SetText(S.title)
		b:SetScript("OnClick", function()
			HideUIPanel(GameMenuFrame)
			S:ToggleConfig()
		end)
		S:SkinButton(b)
		local anchorBtn = GameMenuButtonLogout or GameMenuButtonQuit or GameMenuButtonContinue
		if anchorBtn and anchorBtn.GetPoint and anchorBtn:GetPoint(1) then
			local point, rel, relPoint, x, y = anchorBtn:GetPoint(1)
			local w, h = anchorBtn:GetSize()
			b:SetSize(w > 0 and w or 144, h > 0 and h or 22)
			b:ClearAllPoints()
			b:SetPoint(point, rel, relPoint, x or 0, y or 0)
			anchorBtn:ClearAllPoints()
			anchorBtn:SetPoint("TOP", b, "BOTTOM", 0, -1)
			f:SetHeight(f:GetHeight() + b:GetHeight() + 2)
		else
			b:SetSize(144, 22)
			b:SetPoint("BOTTOM", f, "TOP", 0, 4)
		end
		f.suiButton = b
	end
end

function SK:SkinBlizzard(addonName)
	local db = self.db
	if not db.blizzard then return end
	for _, info in ipairs(skins) do
		if db[info.key] ~= false and (info.addon == addonName) and (not info.retailOnly or S.isRetail) then
			if info.gamemenu then
				S:SafeCall("Skins:GameMenu", self.SkinGameMenu, self)
			else
				for _, n in ipairs(info.frames) do
					local frame = Resolve(n)
					if frame then S:SafeCall("Skins:" .. n, self.SkinWindow, self, frame, info) end
				end
			end
		end
	end
end

-- Third party addons ----------------------------------------------------------
function SK:SkinAddOns(addonName)
	local db = self.db
	if not db.addons then return end
	if addonName == "DBM-Core" and db.bossMod and DBT then
		local function SkinBar(bar)
			local frame = bar.frame
			if not frame or frame.suiSkinned then return end
			frame.suiSkinned = true
			local name = frame:GetName()
			local sb = _G[name .. "Bar"]
			local icon1, icon2 = _G[name .. "BarIcon1"], _G[name .. "BarIcon2"]
			local text, timer = _G[name .. "BarName"], _G[name .. "BarTimer"]
			if sb then
				sb:SetStatusBarTexture(S.media.statusbar)
				S:CreateBackdrop(sb, "Default")
				local bg = _G[name .. "BarBackground"]
				if bg then bg:SetAlpha(0) end
				local spark = _G[name .. "BarSpark"]
				if spark then spark:SetAlpha(0) end
			end
			if icon1 then S:SkinIcon(icon1, true) end
			if icon2 then S:SkinIcon(icon2, true) end
			if text then S:SetFont(text, S.media.font, 12, "OUTLINE") end
			if timer then S:SetFont(timer, S.media.numberFont, 12, "OUTLINE") end
		end
		if DBT.CreateBar then hooksecurefunc(DBT, "CreateBar", function(_, ...) C_Timer.After(0, function() if DBT.bars then for bar in pairs(DBT.bars) do S:SafeCall("Skins:BossMod", SkinBar, bar) end end end) end) end
	elseif addonName == "Details" and db.meter and Details then
		-- it has its own skin engine; we only align the window background to our colors.
		C_Timer.After(2, function()
			S:SafeCall("Skins:Meter", function()
				for i = 1, (Details.GetNumInstances and Details:GetNumInstances() or 0) do
					local inst = Details:GetInstance(i)
					if inst and inst.baseframe and inst:IsEnabled() then
						S:CreateBackdrop(inst.baseframe, "Transparent", "TOP")
					end
				end
			end)
		end)
	end
end

function SK:ADDON_LOADED(_, addonName)
	self:SkinBlizzard(addonName)
	self:SkinAddOns(addonName)
end

-- GossipFrame/QuestFrame can be created lazily; re-check on first open
function SK:GOSSIP_SHOW()
	local gf = _G.GossipFrame
	if gf and not gf.suiWindowSkinned then
		for _, info in ipairs(skins) do
			if info.key == "gossip" then S:SafeCall("Skins:GossipFrame", self.SkinWindow, self, gf, info) break end
		end
	end
end

function SK:QUEST_DETAIL()
	local qf = _G.QuestFrame
	if qf and not qf.suiWindowSkinned then
		for _, info in ipairs(skins) do
			if info.key == "quest" then S:SafeCall("Skins:QuestFrame", self.SkinWindow, self, qf, info) break end
		end
	end
end

function SK:Initialize()
	-- migrate renamed option keys from older profiles
	if self.db.dbm ~= nil then self.db.bossMod = self.db.dbm self.db.dbm = nil end
	if self.db.details ~= nil then self.db.meter = self.db.details self.db.details = nil end
	self:SkinBlizzard(nil)
	for _, info in ipairs(skins) do
		if info.addon and S.IsAddOnLoaded(info.addon) then self:SkinBlizzard(info.addon) end
	end
	-- some frames carry an addon marker for retail but are core UI on classic
	-- (TradeSkillFrame/CraftFrame on TBC): skin them when they already exist
	for _, info in ipairs(skins) do
		if info.addon and not S.IsAddOnLoaded(info.addon) and self.db[info.key] ~= false and (not info.retailOnly or S.isRetail) then
			for _, n in ipairs(info.frames) do
				local frame = Resolve(n)
				if frame then
					S:SafeCall("Skins:" .. n, self.SkinWindow, self, frame, info)
					if S.LogInfo then S:LogInfo("skins", "core-frame skin: " .. n .. " skinned=" .. tostring(frame.suiWindowSkinned == true)) end
					break
				end
			end
		end
	end
	for _, a in ipairs({ "DBM-Core", "Details" }) do
		if S.IsAddOnLoaded(a) then self:SkinAddOns(a) end
	end
	self:RegisterEvent("ADDON_LOADED")
	self:RegisterEvent("GOSSIP_SHOW")
	self:RegisterEvent("QUEST_DETAIL")
	-- classic trade windows may only exist after first open
	pcall(self.RegisterEvent, self, "TRADE_SKILL_SHOW", function()
		for _, info in ipairs(skins) do
			if info.key == "tradeskill" and _G.TradeSkillFrame and not _G.TradeSkillFrame.suiWindowSkinned then
				S:SafeCall("Skins:TradeSkill", self.SkinWindow, self, _G.TradeSkillFrame, info)
			end
		end
	end)
	pcall(self.RegisterEvent, self, "CRAFT_SHOW", function()
		for _, info in ipairs(skins) do
			if info.key == "tradeskill" and _G.CraftFrame and not _G.CraftFrame.suiWindowSkinned then
				S:SafeCall("Skins:CraftFrame", self.SkinWindow, self, _G.CraftFrame, info)
			end
		end
	end)
	S:LogInfo("skins", "init: GossipFrame=" .. tostring(_G.GossipFrame ~= nil) .. " QuestFrame=" .. tostring(_G.QuestFrame ~= nil))
end
