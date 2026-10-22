-- Misc: auto repair, invites, duels, error filter, interrupt announce, raid utility, chat bubbles,
-- loot frames, mirror timers and movers for various Blizzard frames.
local _, ns = ...
local S = ns.S
local L = S.L
local M = S:NewModule("Misc")

local _G = _G
local format, pairs, ipairs, math = format, pairs, ipairs, math
local CreateFrame = CreateFrame
local GetTime = GetTime
local IsSecret = S.IsSecret
local BLANK = [[Interface\Buttons\WHITE8X8]]

-- Repair ----------------------------------------------------------------------
function M:MERCHANT_SHOW()
	-- auto-sell poor quality items
	if self.db.autoSell then
		local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
		local itemInfo = (C_Container and C_Container.GetContainerItemInfo) or GetContainerItemInfo
		local sell = (C_Container and C_Container.UseContainerItem) or UseContainerItem
		if numSlots and itemInfo and sell then
			local gain = 0
			for bag = 0, 4 do
				for slot = 1, numSlots(bag) or 0 do
					local info = itemInfo(bag, slot)
					local link, count
					if type(info) == "table" then
						link = info.hyperlink or info.link
						count = info.stackCount or 0
					elseif info then -- legacy API: icon, count, locked, quality, readable, lootable, link
						count = select(2, GetContainerItemInfo(bag, slot)) or 0
						link = select(7, GetContainerItemInfo(bag, slot))
					end
					if link then
						local price = select(11, S.GetItemInfo(link))
						local quality = select(3, S.GetItemInfo(link))
						if quality == 0 and price and price > 0 and count > 0 then
							sell(bag, slot)
							gain = gain + price * count
						end
					end
				end
			end
			if gain > 0 then self:Print(format(L["Sold junk for %s"], S:FormatMoney(gain))) end
		end
	end
	local mode = self.db.autoRepair
	if mode == "NONE" or not CanMerchantRepair or not CanMerchantRepair() then return end
	local cost, canRepair = GetRepairAllCost()
	if not canRepair or cost <= 0 then return end
	if mode == "GUILD" and IsInGuild() and CanGuildBankRepair and CanGuildBankRepair() then
		local limit = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney() or 0
		local bank = GetGuildBankMoney and GetGuildBankMoney() or 0
		if (limit == -1 or limit >= cost) and bank >= cost then
			RepairAllItems(true)
			self:Print(format(L["Repaired with guild funds for %s"], S:FormatMoney(cost)))
			return
		end
	end
	if GetMoney() >= cost then
		RepairAllItems()
		self:Print(format(L["Repaired for %s"], S:FormatMoney(cost)))
	else
		self:Print(L["Not enough money to repair."])
	end
end

-- Invites / duels -------------------------------------------------------------
local function IsFriend(name)
	if not name then return false end
	name = Ambiguate(name, "none")
	if C_FriendList and C_FriendList.IsFriend then
		local info = C_FriendList.GetFriendInfo and C_FriendList.GetFriendInfo(name)
		if info then return true end
	elseif GetNumFriends then
		for i = 1, GetNumFriends() do
			if GetFriendInfo(i) == name then return true end
		end
	end
	if IsInGuild() then
		for i = 1, GetNumGuildMembers() do
			local gname = GetGuildRosterInfo(i)
			if gname and Ambiguate(gname, "none") == name then return true end
		end
	end
	if BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
		for i = 1, BNGetNumFriends() do
			local info = C_BattleNet.GetFriendAccountInfo(i)
			local game = info and info.gameAccountInfo
			if game and game.characterName == name then return true end
		end
	end
	return false
end

function M:PARTY_INVITE_REQUEST(_, name)
	if not self.db.autoAcceptInvite or IsSecret(name) then return end
	if IsFriend(name) then
		AcceptGroup()
		StaticPopup_Hide("PARTY_INVITE")
		self:Print(format(L["Accepted invite from %s"], name))
	end
end

function M:DUEL_REQUESTED(_, name)
	if not self.db.declineDuels then return end
	CancelDuel()
	StaticPopup_Hide("DUEL_REQUESTED")
	self:Print(format(L["Declined duel from %s"], name or "?"))
end

-- Error frame -----------------------------------------------------------------
function M:PLAYER_REGEN_DISABLED()
	if self.db.hideErrorFrame and UIErrorsFrame then UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE") end
	if self.buffReminder then self:UpdateBuffReminder() end
end

function M:PLAYER_REGEN_ENABLED()
	if UIErrorsFrame then UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE") end
	if self.buffReminder then self:UpdateBuffReminder() end
end

-- Auto dismount ---------------------------------------------------------------
-- casting while mounted only raises ERR_MOUNTED; just drop the mount so the
-- next button press already casts
function M:UI_ERROR_MESSAGE(_, errArg, errArg2)
	if not self.db.autoDismount then return end
	local msg = errArg2 or errArg
	if msg == ERR_MOUNTED and IsMounted and IsMounted() and Dismount then Dismount() end
end

-- Quest progress announce -----------------------------------------------------
-- posts objective progress to party chat when a quest objective advances
local objCache, objReady = {}, false
local function ScanQuestObjectives()
	local out, n = {}, 0
	if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
		n = select(1, C_QuestLog.GetNumQuestLogEntries()) or 0
	elseif GetNumQuestLogEntries then
		n = GetNumQuestLogEntries() or 0
	end
	for i = 1, n do
		local qid, title, isHeader
		if C_QuestLog and C_QuestLog.GetInfo then
			local info = C_QuestLog.GetInfo(i)
			if info then qid, title, isHeader = info.questID, info.title, info.isHeader end
		elseif GetQuestLogTitle then
			local t, _, _, ih = GetQuestLogTitle(i)
			qid, title, isHeader = select(9, GetQuestLogTitle(i)), t, ih
		end
		if qid and title and not isHeader then
			local objs = C_QuestLog and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(qid)
			if objs then
				for j, o in ipairs(objs) do
					if o.text and o.numFulfilled and o.numRequired and o.numRequired > 0 then
						out[qid .. ":" .. j] = { q = title, text = o.text, cur = o.numFulfilled, max = o.numRequired, done = o.finished }
					end
				end
			elseif GetQuestLogLeaderBoard and GetNumQuestLeaderBoards then
				for j = 1, GetNumQuestLeaderBoards(i) or 0 do
					local text, _, finished = GetQuestLogLeaderBoard(j, i)
					local cur, mx = text and text:match("(%d+)%s*/%s*(%d+)")
					if cur then
						out[qid .. ":" .. j] = { q = title, text = text:gsub("%s*:%s*%d+%s*/%s*%d+%s*$", ""), cur = tonumber(cur), max = tonumber(mx), done = finished }
					end
				end
			end
		end
	end
	return out
end

-- Anti-AFK -------------------------------------------------------------------
-- clears the AFK flag the moment it appears so the idle logout never starts
function M:PLAYER_FLAGS_CHANGED()
	if self.db.antiAFK == false or not UnitIsAFK or not SendChatMessage then return end
	if UnitIsAFK("player") then SendChatMessage("", "AFK") end -- toggles the flag off
end

-- Auto-fill delete confirm ----------------------------------------------------
-- types the required word into the item-delete popup's editbox automatically
local function FillDelete(popup)
	if M.db and M.db.autoDelete == false then return end
	local eb = popup and (popup.editBox or _G[popup:GetName() .. "EditBox"])
	if eb and eb:IsShown() then eb:SetText(DELETE_ITEM_CONFIRM_STRING or "DELETE") end
end
local deleteHooked
local function HookDeletePopup()
	if deleteHooked or not StaticPopup_Show then return end
	deleteHooked = true
	hooksecurefunc("StaticPopup_Show", function(which)
		if not which or not which:find("DELETE_") then return end
		for i = 1, 4 do
			local popup = _G["StaticPopup" .. i]
			if popup and popup.which == which and popup:IsShown() then FillDelete(popup) break end
		end
	end)
	-- editboxes can be created lazily: fill on their OnShow too
	for i = 1, 4 do
		local popup = _G["StaticPopup" .. i]
		if popup then popup:HookScript("OnShow", function(f) if f.which and f.which:find("DELETE_") then FillDelete(f) end end) end
	end
end

-- Mail alt dropdown -----------------------------------------------------------
-- small arrow next to the recipient field listing your own characters
local function BuildMailAltList()
	if M.mailAltBtn or not _G.SendMailNameEditBox then return end
	local eb = _G.SendMailNameEditBox
	local btn = CreateFrame("Button", "SentinelUIMailAlt", eb:GetParent())
	btn:SetSize(18, 18)
	btn:SetPoint("LEFT", eb, "RIGHT", 5, 0)
	btn:SetNormalTexture([[Interface\ChatFrame\UI-ChatIcon-ScrollDown-Up]])
	btn:SetHighlightTexture([[Interface\Buttons\UI-Common-MouseHilight]], "ADD")
	btn:SetScript("OnClick", function()
		if not UIDropDownMenu_Initialize or not ToggleDropDownMenu then return end
		local dd = M.mailAltDD or CreateFrame("Frame", "SentinelUIMailAltDD", btn, "UIDropDownMenuTemplate")
		M.mailAltDD = dd
		UIDropDownMenu_Initialize(dd, function()
			local names = {}
			for name in pairs(S.db.global.altroster or {}) do
				if name ~= S.myName then names[#names + 1] = name end
			end
			table.sort(names)
			for _, name in ipairs(names) do
				local info = UIDropDownMenu_CreateInfo()
				info.text = name
				info.func = function() eb:SetText(name) end
				UIDropDownMenu_AddButton(info)
			end
			if #names == 0 then
				local info = UIDropDownMenu_CreateInfo()
				info.text = L["No alts recorded"]
				info.disabled = true
				UIDropDownMenu_AddButton(info)
			end
		end)
		ToggleDropDownMenu(1, nil, dd, btn, 0, 0)
	end)
	M.mailAltBtn = btn
end

-- Notes in friends list -------------------------------------------------------
local friendsHooked
local function HookFriendsNotes()
	if friendsHooked or not FriendsList_Update then return end
	friendsHooked = true
	hooksecurefunc("FriendsList_Update", function()
		if M.db.friendsNotes == false then return end
		local store = S.db.global.playerNotes
		if not store then return end
		for i = 1, 20 do
			local b = _G["FriendsFrameFriendButton" .. i] or _G["FriendsFrameFriendsScrollFrameButton" .. i]
			if not b then break end
			local id = b.id or (b.GetID and b:GetID())
			local fname = id and GetFriendInfo and GetFriendInfo(id)
			local note = fname and store[fname]
			if note and b.name then
				local t = b.name:GetText() or ""
				if not t:find("%*|r$") then b.name:SetText(t .. " |cffffd700*|r") end
				if b.info then b.info:SetText("|cffffd700" .. note .. "|r") end
			end
		end
	end)
end

-- Roll summary ----------------------------------------------------------------
-- announces won rolls in group chat (best-effort: uses the roll-won chat line)
local pendingRolls = {}
local rollWonPat
local function RollPattern()
	if rollWonPat ~= nil then return rollWonPat end
	local fmt = _G.LOOT_ROLL_WON
	if not fmt then rollWonPat = false return end
	-- "%s won: %s" -> "^(.-) won: (.+)$"
	local pat = fmt:gsub("([%^%$%(%)%%%.%[%]%+%-%?])", "%%%1"):gsub("%%%%s", "(.-)"):gsub("%%%%d", "(%%d+)")
	rollWonPat = "^" .. pat .. "$"
	return rollWonPat
end
function M:TrackRoll(rollID)
	local link = GetLootRollItemLink and GetLootRollItemLink(rollID)
	if link then pendingRolls[link] = GetTime() end
end
function M:CHAT_MSG_LOOT(_, msg)
	if self.db.rollSummary == false or not IsInGroup() then return end
	if not msg or next(pendingRolls) == nil then return end
	local now = GetTime()
	for link, t in pairs(pendingRolls) do
		if now - t > 130 then pendingRolls[link] = nil
		elseif msg:find(link, 1, true) then
			local pat = RollPattern()
			local name = pat and msg:match(pat)
			if not name then name = msg:match("^(%S+)") end
			if name == YOU then name = S.myName end
			if name then
				local ch = IsInRaid() and "RAID" or "PARTY"
				SendChatMessage(format(L["%s won %s"], name, link), ch)
			end
			pendingRolls[link] = nil
		end
	end
end

local FOOD_PAT = GetLocale() == "deDE" and "Satt" or "Well Fed|Satt|Bien nourri|Saciado"
local FLASK_PAT = GetLocale() == "deDE" and "Fläschchen|Elixier" or "Flask|Elixir|Fläschchen|Elixier"

-- Buff expiry warning ---------------------------------------------------------
-- warns once per aura when a food/flask/elixir buff drops below 5 minutes
local buffWarned = {}
local function BuffExpireScan()
	if M.db.buffExpireWarn == false or not S.UnitAura then return end
	local now = GetTime()
	for i = 1, 40 do
		local name, _, _, _, duration, exp = S.UnitAura("player", i, "HELPFUL")
		if not name then break end
		if duration and exp and duration > 0 and type(name) == "string" then
			local rem = exp - now
			if rem > 0 and rem < 300 and (name:find(FOOD_PAT) or name:find(FLASK_PAT)) then
				local key = name .. "|" .. exp
				if not buffWarned[key] then
					buffWarned[key] = true
					S:Print(format(L["%s expires in less than 5 min"], name))
					if PlaySound then PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959) end
				end
			end
		end
	end
end

-- Bag full warning ------------------------------------------------------------
-- one-shot toast when free bag space drops to <= 3 slots (60s throttle)
local lastBagWarn, lastFree = 0, 99
function M:BAG_UPDATE()
	if self.db.bagFullWarn == false or not S.GetContainerNumFreeSlots then return end
	local free = 0
	for bag = 0, 4 do free = free + (S.GetContainerNumFreeSlots(bag) or 0) end
	if free <= 3 and free < lastFree and GetTime() - lastBagWarn > 60 then
		lastBagWarn = GetTime()
		S:Print(format(L["Bags almost full: %d free slots"], free))
		if PlaySound then PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPEN or 856) end
	end
	lastFree = free
end

-- Friend online ding ----------------------------------------------------------
local friendOnlinePat
local function FriendOnlinePattern()
	if friendOnlinePat ~= nil then return friendOnlinePat end
	local fmt = _G.ERR_FRIEND_ONLINE_SS
	if not fmt then friendOnlinePat = false return end
	friendOnlinePat = fmt:gsub("([%^%$%(%)%%%.%[%]%+%-%?])", "%%%1"):gsub("%%%%s", "(.-)"):gsub("%%%%d", "(%%d+)")
	return friendOnlinePat
end
function M:CHAT_MSG_SYSTEM(_, msg)
	if self.db.friendDing == false or not msg then return end
	local pat = FriendOnlinePattern()
	if pat and msg:find(pat) then
		if PlaySound then PlaySound(SOUNDKIT and SOUNDKIT.FRIEND_JOIN_GAME or 33329) end
	end
end

-- Trade gold display ----------------------------------------------------------
local tradeGoldText
local function UpdateTradeGold()
	local f = _G.TradeFrame
	if not f then return end
	if not tradeGoldText then
		tradeGoldText = S:FontString(f, 11, "OUTLINE", S.media.numberFont)
		tradeGoldText:SetPoint("BOTTOM", f, "BOTTOM", 0, 18)
	end
	if M.db.tradeGold == false then tradeGoldText:SetText("") return end
	local mine = GetPlayerTradeMoney and GetPlayerTradeMoney() or 0
	local theirs = GetTargetTradeMoney and GetTargetTradeMoney() or 0
	tradeGoldText:SetFormattedText("%s: %s  |  %s: %s",
		YOU or L["You"], S:FormatMoney(mine),
		TARGET or L["Target"], S:FormatMoney(theirs))
end

-- Raid consumables check ------------------------------------------------------
-- /suiconsume: lists who is missing food and flask/elixir buffs

local function GroupUnits()
	local units = {}
	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
	elseif IsInGroup() then
		units[#units + 1] = "player"
		for i = 1, GetNumGroupMembers() - 1 do units[#units + 1] = "party" .. i end
	else
		units[#units + 1] = "player"
	end
	return units
end

local function ConsumeCheck()
	local missFood, missFlask = {}, {}
	for _, unit in ipairs(GroupUnits()) do
		if UnitExists(unit) and not UnitIsDeadOrGhost(unit) then
			local food, flask
			for i = 1, 40 do
				local name = S.UnitAura(unit, i, "HELPFUL")
				if not name then break end
				if not (S.IsSecret and S.IsSecret(name)) then
					if name:find(FOOD_PAT) then food = true end
					if name:find(FLASK_PAT) then flask = true end
				end
			end
			local n = UnitName(unit) or unit
			if not food then missFood[#missFood + 1] = n end
			if not flask then missFlask[#missFlask + 1] = n end
		end
	end
	S:Print("|cff" .. S.accentHex .. L["Consumables check"] .. "|r")
	if #missFood == 0 and #missFlask == 0 then
		S:Print(L["Everyone has food + flask"])
	else
		if #missFood > 0 then S:Print(format("|cffff8040" .. L["No food buff (%d):"] .. "|r %s", #missFood, table.concat(missFood, ", "))) end
		if #missFlask > 0 then S:Print(format("|cffff8040" .. L["No flask/elixir (%d):"] .. "|r %s", #missFlask, table.concat(missFlask, ", "))) end
	end
end

function M:QUEST_LOG_UPDATE()
	local fresh = ScanQuestObjectives()
	if objReady and self.db.questAnnounce and IsInGroup() then
		for k, o in pairs(fresh) do
			local old = objCache[k]
			if old and o.cur and old.cur and o.cur > old.cur and not (S.IsSecret and (S.IsSecret(o.text) or S.IsSecret(o.q))) then
				SendChatMessage(format("%s: %s (%d/%d)", o.q, o.text, o.cur, o.max), "PARTY")
			end
		end
	end
	objCache = fresh
	objReady = true
end

-- Auto-watch reputation -------------------------------------------------------
-- the watched-faction bar follows whichever faction gained rep last
local repCache
function M:UPDATE_FACTION()
	if not self.db.autoWatch or not (GetNumFactions and GetFactionInfo and SetWatchedFactionIndex) then return end
	repCache = repCache or {}
	local gained
	for i = 1, GetNumFactions() do
		local name, _, _, _, _, value, _, _, isHeader = GetFactionInfo(i)
		if name and not isHeader and value then
			if repCache[name] and value > repCache[name] then gained = i end
			repCache[name] = value
		end
	end
	if gained and not self._watchLock then
		self._watchLock = true
		SetWatchedFactionIndex(gained)
		self._watchLock = nil
	end
end

-- Interrupt / dispel / steal announce ------------------------------------------
local function Announce(channel, msg)
	if channel == "SAY" or channel == "YELL" or channel == "EMOTE" then
		if IsInInstance() then SendChatMessage(msg, channel) end
	elseif channel == "AUTO" then
		local ch = IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or IsInRaid() and "RAID" or IsInGroup() and "PARTY"
		if ch then SendChatMessage(msg, ch) end
	elseif channel == "PARTY" and IsInGroup() then SendChatMessage(msg, "PARTY")
	elseif channel == "RAID" and IsInRaid() then SendChatMessage(msg, "RAID") end
end

function M:COMBAT_LOG_EVENT_UNFILTERED()
	local ich, dch = self.db.interruptAnnounce, self.db.dispelAnnounce
	if ich == "NONE" and dch == "NONE" then return end
	local _, sub, _, sourceGUID, _, _, _, _, destName, _, _, _, spellName, _, extraSpellID, extraSpellName = CombatLogGetCurrentEventInfo()
	if sourceGUID ~= UnitGUID("player") and sourceGUID ~= UnitGUID("pet") then return end
	if sub == "SPELL_INTERRUPT" and ich ~= "NONE" then
		Announce(ich, format(L["Interrupted %s's %s"], destName or "?", extraSpellName or spellName or "?"))
	elseif (sub == "SPELL_DISPEL" or sub == "SPELL_STOLEN") and dch ~= "NONE" then
		local verb = sub == "SPELL_STOLEN" and L["Stole %s's %s"] or L["Dispelled %s's %s"]
		Announce(dch, format(verb, destName or "?", extraSpellName or "?"))
	end
end

-- Chat bubbles ----------------------------------------------------------------
local function SkinBubble(bubble)
	if bubble.suiSkinned or (bubble.IsForbidden and bubble:IsForbidden()) then return end
	local frame = bubble:GetChildren()
	if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
	bubble.suiSkinned = true
	if frame.Center then
		for _, k in ipairs({ "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner", "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center", "Tail" }) do
			if frame[k] then frame[k]:SetAlpha(0) end
		end
	else
		for _, region in ipairs({ frame:GetRegions() }) do
			if region:IsObjectType("Texture") then region:SetAlpha(0) end
		end
	end
	local bd = CreateFrame("Frame", nil, frame, S.BackdropTemplate)
	bd:SetPoint("TOPLEFT", 6, -6)
	bd:SetPoint("BOTTOMRIGHT", -6, 6)
	bd:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
	S:SetTemplate(bd, "Transparent", "TOP")
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:IsObjectType("FontString") then S:SetFont(region, S.media.font, 12, "NONE") end
	end
end

function M:SetupBubbles()
	if not C_ChatBubbles or not self.db.bubbles then return end
	local elapsed = 0
	local f = CreateFrame("Frame")
	f:SetScript("OnUpdate", function(_, e)
		elapsed = elapsed + e
		if elapsed < 0.1 then return end
		elapsed = 0
		for _, bubble in pairs(C_ChatBubbles.GetAllChatBubbles(false)) do
			S:SafeCall("Misc:Bubble", SkinBubble, bubble)
		end
	end)
end

-- Raid utility ------------------------------------------------------------------
function M:CreateRaidUtility()
	if not self.db.raidUtility then return end
	local panel = CreateFrame("Frame", "SentinelUIRaidUtility", UIParent, "SecureHandlerStateTemplate")
	panel:SetSize(192, 120)
	S:SetTemplate(panel, "Transparent", "TOP")
	panel:Hide()
	local toggle = CreateFrame("Button", "SentinelUIRaidUtilityToggle", UIParent, "SecureHandlerClickTemplate")
	toggle:SetSize(110, 18)
	S:CreateBackdrop(toggle, "Transparent", "BOTTOM", 0)
	S:AddHover(toggle)
	local t = S:FontString(toggle, 11, "OUTLINE")
	t:SetPoint("CENTER")
	t:SetText(L["Raid Utility"])
	S:RegisterAccent(t, "text")
	toggle:SetFrameRef("panel", panel)
	toggle:SetAttribute("_onclick", [[ local p = self:GetFrameRef("panel") if p:IsShown() then p:Hide() else p:Show() end ]])
	S:CreateMover(toggle, "raidUtility", L["Raid Utility"], { "TOP", "UIParent", "TOP", -300, -2 }, "general")
	panel:SetPoint("TOP", toggle, "BOTTOM", 0, -2)
	RegisterStateDriver(toggle, "visibility", "[group] show; hide")

	-- raid target marker row (star/circle/... on the current target)
	local markerRow = CreateFrame("Frame", nil, panel)
	markerRow:SetSize(178, 18)
	markerRow:SetPoint("TOP", 0, -4)
	local mLabel = S:FontString(markerRow, 9, "OUTLINE", S.media.numberFont, nil, "LEFT")
	mLabel:SetPoint("LEFT", 0, 0)
	mLabel:SetText(L["Target"] or "Target")
	local markerIcons = { 1, 2, 3, 4, 5, 6, 7, 8 }
	local clearBtn
	for idx, mark in ipairs(markerIcons) do
		local mb = CreateFrame("Button", nil, markerRow)
		mb:SetSize(15, 15)
		mb:SetPoint("LEFT", 30 + (idx - 1) * 16, 0)
		local tex = mb:CreateTexture(nil, "ARTWORK")
		tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. mark)
		tex:SetAllPoints()
		mb:SetScript("OnClick", function()
			if SetRaidTarget then SetRaidTarget("target", mark) end
		end)
		mb:SetScript("OnEnter", function(self)
			self:SetAlpha(0.7)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(L["Mark target"] or "Mark target")
			GameTooltip:Show()
		end)
		mb:SetScript("OnLeave", function(self) self:SetAlpha(1) GameTooltip:Hide() end)
		markerRow["mark" .. mark] = mb
	end
	clearBtn = CreateFrame("Button", nil, markerRow)
	clearBtn:SetSize(15, 15)
	clearBtn:SetPoint("LEFT", 30 + 8 * 16, 0)
	local ct = clearBtn:CreateTexture(nil, "ARTWORK")
	ct:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
	ct:SetAllPoints()
	clearBtn:SetScript("OnClick", function() if SetRaidTarget then SetRaidTarget("target", 0) end end)
	clearBtn:SetScript("OnEnter", function(self)
		self:SetAlpha(0.7)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(L["Clear mark"] or "Clear mark")
		GameTooltip:Show()
	end)
	clearBtn:SetScript("OnLeave", function(self) self:SetAlpha(1) GameTooltip:Hide() end)

	local y = -27
	-- world markers (ground flares) - only where the client exposes the API
	if PlaceRaidMarker then
		local wmRow = CreateFrame("Frame", nil, panel)
		wmRow:SetSize(178, 18)
		wmRow:SetPoint("TOP", 0, y)
		local wLabel = S:FontString(wmRow, 9, "OUTLINE", S.media.numberFont, nil, "LEFT")
		wLabel:SetPoint("LEFT", 0, 0)
		wLabel:SetText(L["World"] or "World")
		for idx, mark in ipairs(markerIcons) do
			local wb = CreateFrame("Button", nil, wmRow)
			wb:SetSize(15, 15)
			wb:SetPoint("LEFT", 30 + (idx - 1) * 16, 0)
			local tex = wb:CreateTexture(nil, "ARTWORK")
			tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. mark)
			tex:SetAllPoints()
			tex:SetAlpha(0.65)
			wb:SetScript("OnClick", function()
				if not (IsInRaid() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player"))) and IsInRaid() then return end
				S:SafeCall("WorldMarker", PlaceRaidMarker, mark)
			end)
			wb:SetScript("OnEnter", function(self)
				self:SetAlpha(0.7)
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				GameTooltip:SetText(L["Place world marker"] or "Place world marker")
				GameTooltip:Show()
			end)
			wb:SetScript("OnLeave", function(self) self:SetAlpha(1) GameTooltip:Hide() end)
		end
		local wmClear = CreateFrame("Button", nil, wmRow)
		wmClear:SetSize(15, 15)
		wmClear:SetPoint("LEFT", 30 + 8 * 16, 0)
		local wt = wmClear:CreateTexture(nil, "ARTWORK")
		wt:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
		wt:SetAllPoints()
		wmClear:SetScript("OnClick", function() if ClearRaidMarker then S:SafeCall("WorldMarker", ClearRaidMarker) end end)
		wmClear:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
		wmClear:SetScript("OnLeave", function(self) self:SetAlpha(1) end)
		y = y - 22
	end

	local buttons = {
		{ READY_CHECK, function() DoReadyCheck() end },
		{ ROLE_POLL or L["Role Check"], function() if InitiateRolePoll then InitiateRolePoll() end end, InitiateRolePoll ~= nil },
		{ L["Convert Group"], function() if IsInRaid() then (C_PartyInfo and C_PartyInfo.ConvertToParty or ConvertToParty)() else (C_PartyInfo and C_PartyInfo.ConvertToRaid or ConvertToRaid)() end end },
		{ L["Countdown 10s"], function() if C_PartyInfo and C_PartyInfo.DoCountdown then C_PartyInfo.DoCountdown(10) elseif SlashCmdList.DEADLYBOSSMODS then SlashCmdList.DEADLYBOSSMODS("pull 10") end end },
		{ L["Everyone Assist"], function() if SetEveryoneIsAssistant then SetEveryoneIsAssistant(not IsEveryoneAssistant()) end end, SetEveryoneIsAssistant ~= nil },
	}
	for _, info in ipairs(buttons) do
		if info[3] ~= false then
			local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
			b:SetSize(178, 20)
			b:SetPoint("TOP", 0, y)
			b:SetText(info[1])
			b:SetScript("OnClick", function() S:SafeCall("RaidUtility", info[2]) end)
			S:SkinButton(b)
			y = y - 23
		end
	end
	panel:SetHeight(-y + 8)
end

-- Loot / roll frames ------------------------------------------------------------
local B_LOOT_ICON_LOGGED
local function SkinLootButton(btn)
	if not btn then return end
	if not btn.suiLootSkinned then
		btn.suiLootSkinned = true
		local name = btn:GetName()
		-- resolve the icon BEFORE stripping: StripTextures alpha-0s every texture
		-- region. Try every common field name (icon/Icon/IconTexture/iconTexture,
		-- global names, IconFrame child) so the icon cannot stay invisible.
		local icon = btn.icon or btn.Icon or btn.IconTexture or btn.iconTexture
			or (name and (_G[name .. "IconTexture"] or _G[name .. "Icon"]))
			or (btn.IconFrame and btn.IconFrame.Icon)
		-- last resort: find a non-font region that is not the name frame
		if not icon then
			local nf = name and _G[name .. "NameFrame"]
			for i = 1, select("#", btn:GetRegions()) do
				local r = select(i, btn:GetRegions())
				if r:IsObjectType("Texture") and r ~= nf and r ~= btn.IconBorder then icon = r break end
			end
		end
		local nf = name and _G[name .. "NameFrame"]
		if nf then nf:Hide() end
		local tex = icon and icon.GetTexture and icon:GetTexture()
		S:StripTextures(btn)
		S:CreateBackdrop(btn, "Default")
		btn.suiIcon = icon
		if icon then
			icon:SetAlpha(1)
			icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			-- lift the icon onto the backdrop so nothing can cover it
			icon:SetParent(btn.suiBackdrop)
			if tex then icon:SetTexture(tex) end
		end
		-- quality border: recolor our backdrop instead of the Blizzard ring
		local border = btn.IconBorder or (name and _G[name .. "IconBorder"])
		if border then
			border:SetAlpha(0)
			hooksecurefunc(border, "SetVertexColor", function(_, r, g, b)
				S:SafeCall("Loot:Border", function()
					if btn.suiBackdrop then btn.suiBackdrop:SetBackdropBorderColor(r, g, b) end
				end)
			end)
			hooksecurefunc(border, "Hide", function()
				S:SafeCall("Loot:Border", function()
					if btn.suiBackdrop then btn.suiBackdrop:SetBackdropBorderColor(unpack(S.media.borderColor)) end
				end)
			end)
		end
		if icon then
			hooksecurefunc(icon, "SetAlpha", function(ic, a)
				if a == 0 then S:SafeCall("Loot:IconAlpha", ic.SetAlpha, ic, 1) end
			end)
		end
		if S.LogInfo and not B_LOOT_ICON_LOGGED then
			B_LOOT_ICON_LOGGED = true
			S:LogInfo("loot", format("button=%s icon=%s iconField=%s", tostring(name), tostring(icon ~= nil), tostring(btn.IconTexture ~= nil)))
		end
	end
	-- re-assert on every update: Blizzard re-fades regions when loot changes
	if btn.suiIcon then btn.suiIcon:SetAlpha(1) end
end

local function SkinRollFrame(f)
	if not f or f.suiRollSkinned then return end
	f.suiRollSkinned = true
	S:StripTextures(f)
	S:CreateBackdrop(f, "Transparent", "TOP")
	local timer = f.Timer or (f:GetName() and _G[f:GetName() .. "Timer"])
	if timer then
		if timer.GetObjectType and timer:IsObjectType("StatusBar") then
			S:SkinStatusBar(timer)
		elseif timer.GetObjectType and timer:IsObjectType("Texture") then
			-- StripTextures hid it; on some clients the countdown is a plain texture
			timer:SetAlpha(1)
		end
	end
	local icon = f.IconFrame and f.IconFrame.Icon or (f:GetName() and (_G[f:GetName() .. "IconFrameIcon"] or _G[f:GetName() .. "Icon"]))
	if icon then
		local bd = S:SkinIcon(icon, true)
		if bd then S:SafeCall("Loot:RollQuality", function()
			local q
			local link = f.rollID and GetLootRollItemLink and GetLootRollItemLink(f.rollID)
			if link then q = select(3, GetItemInfo(link)) end
			if q and q > 1 then
				local r, g, b = GetItemQualityColor(q)
				if r then bd:SetBackdropBorderColor(r, g, b) end
			end
		end) end
	end
	-- need/greed/disenchant/pass buttons get a hover border
	for _, key in ipairs({ "NeedButton", "GreedButton", "DisenchantButton", "PassButton", "CoinButton" }) do
		local b = f[key]
		if b and b.IsObjectType and b:IsObjectType("Button") then S:AddHover(b) end
	end
end

local function SkinLootHistoryRow(frame)
	if not frame or frame.suiHistSkinned then return end
	frame.suiHistSkinned = true
	if frame.Icon then
		local tex = frame.Icon:GetTexture()
		S:StripTextures(frame)
		frame.Icon:SetTexture(tex)
		frame.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		S:CreateBackdrop(frame, "Default")
		S:SetOutside(frame.suiBackdrop, frame.Icon)
	end
end

local function UpdateLootHistory()
	local lhf = _G.LootHistoryFrame
	if not lhf then return end
	-- TBC/modern: itemFrames pool; older builds: individual frames
	if lhf.itemFrames then
		for i = 1, #lhf.itemFrames do SkinLootHistoryRow(lhf.itemFrames[i]) end
	end
end

function M:SkinLoot()
	if not self.db.loot then return end
	if LootFrame then
		S:SkinFrame(LootFrame)
		S:SkinChildren(LootFrame)
		-- ButtonFrameTemplateMinimizable adds a minimize button; the field name varies
		-- between clients, so hide it by name lookup AND a recursive child scan that
		-- matches "Minimize"/"Maximize"/"Collapse" in the name or the button texture.
		local function HideMinimizeOf(parent, depth)
			depth = depth or 0
			if depth > 3 or not parent or not parent.GetChildren then return end
			for _, key in ipairs({ "MinimizeButton", "minimizeButton", "MaximizeMinimizeFrame", "CollapseButton", "ToggleCollapseButton" }) do
				local o = parent[key]
				if o and o.Hide then o:Hide() end
			end
			local pname = parent.GetName and parent:GetName()
			for _, key in ipairs({ "MinimizeButton", "Minimize", "MaximizeMinimizeFrame", "CollapseButton" }) do
				local o = pname and _G[pname .. key]
				if o and o.Hide then o:Hide() end
			end
			for i = 1, select("#", parent:GetChildren()) do
				local c = select(i, parent:GetChildren())
				local n = c.GetName and c:GetName() or ""
				if n:find("Minimi") or n:find("Maximi") or n:find("Collapse") or n:find("collapse") then
					if c.Hide then c:Hide() end
				else
					local tp = c.GetNormalTexture and c:GetNormalTexture()
					if type(tp) == "string" and (tp:find("Minimi") or tp:find("Collapse")) then
						c:Hide()
					elseif c.GetChildren then
						HideMinimizeOf(c, depth + 1)
					end
				end
			end
		end
		M._hideMinimize = HideMinimizeOf
		S:SafeCall("Loot:HideMinimize", HideMinimizeOf, LootFrame)
		-- log the actual child names once so /sui save reveals the real field name
		do
			local names = {}
			for i = 1, select("#", LootFrame:GetChildren()) do
				local c = select(i, LootFrame:GetChildren())
				names[#names + 1] = (c.GetName and c:GetName()) or ("<unnamed " .. (c.GetObjectType and c:GetObjectType() or "?") .. ">")
			end
			S:LogInfo("loot", "LootFrame children: " .. table.concat(names, ", "))
		end
		LootFrame:HookScript("OnShow", function() S:SafeCall("Loot:HideMinimize", HideMinimizeOf, LootFrame) end)
		local pov = _G.LootFramePortraitOverlay or (LootFrame.PortraitContainer and LootFrame.PortraitContainer.overlay)
		if pov then pov:SetAlpha(0) end
		for i = 1, (LOOTFRAME_NUMBUTTONS or 4) do
			SkinLootButton(_G["LootButton" .. i])
		end
		-- re-assert icons on every loot refresh; also catches late-created buttons.
		-- Modern clients use the mixin method instead of the global function.
		if _G.LootFrame_UpdateButton then
			hooksecurefunc("LootFrame_UpdateButton", function(index)
				S:SafeCall("Loot:UpdateButton", SkinLootButton, _G["LootButton" .. index])
			end)
		end
		if LootFrame.UpdateButton then
			hooksecurefunc(LootFrame, "UpdateButton", function(_, index)
				S:SafeCall("Loot:UpdateButton", SkinLootButton, _G["LootButton" .. index])
			end)
		end
		self:RegisterEvent("LOOT_SLOT_CHANGED", function(_, _, slot)
			slot = tonumber(slot)
			local idx = slot and ((slot - 1) % (LOOTFRAME_NUMBUTTONS or 4) + 1)
			if idx then SkinLootButton(_G["LootButton" .. idx]) end
		end)
		self:RegisterEvent("LOOT_OPENED", function()
			for i = 1, (LOOTFRAME_NUMBUTTONS or 8) do SkinLootButton(_G["LootButton" .. i]) end
			HideMinimizeOf(LootFrame)
		end)
		-- page arrows get proper arrow styling instead of Blizzard chrome
		local down = _G.LootFrameDownButton
		local up = _G.LootFrameUpButton
		if down then S:SkinArrowButton(down, "down") down:SetSize(18, 18) end
		if up then S:SkinArrowButton(up, "up") up:SetSize(18, 18) end
	end
	-- party loot feed (who looted what) - was completely unskinned
	local lhf = _G.LootHistoryFrame
	if lhf then
		S:StripTextures(lhf)
		S:SetTemplate(lhf, "Transparent", "TOP")
		-- same minimize/maximize chrome as the loot window
		if M._hideMinimize then S:SafeCall("Loot:HistoryMinimize", M._hideMinimize, lhf) end
		do
			local names = {}
			for i = 1, select("#", lhf:GetChildren()) do
				local c = select(i, lhf:GetChildren())
				names[#names + 1] = (c.GetName and c:GetName()) or ("<unnamed " .. (c.GetObjectType and c:GetObjectType() or "?") .. ">")
			end
			S:LogInfo("loot", "LootHistoryFrame children: " .. table.concat(names, ", "))
		end
		lhf:HookScript("OnShow", function(f) if M._hideMinimize then S:SafeCall("Loot:HistoryMinimize", M._hideMinimize, f) end end)
		if lhf.CloseButton then S:SkinCloseButton(lhf.CloseButton) end
		if lhf.ResizeButton then
			S:StripTextures(lhf.ResizeButton)
			S:CreateBackdrop(lhf.ResizeButton, "Default")
		end
		local lsf = _G.LootHistoryFrameScrollFrame
		if lsf then
			S:StripTextures(lsf)
			local sb = lsf.ScrollBar or _G.LootHistoryFrameScrollFrameScrollBar
			if sb then S:SkinScrollBar(sb) end
		end
		if _G.LootHistoryFrame_FullUpdate then
			hooksecurefunc("LootHistoryFrame_FullUpdate", function() S:SafeCall("Loot:History", UpdateLootHistory) end)
		end
		if lhf.FullUpdate then hooksecurefunc(lhf, "FullUpdate", function() S:SafeCall("Loot:History", UpdateLootHistory) end) end
		UpdateLootHistory()
	end
	-- master looter popup
	local ml = _G.MasterLooterFrame
	if ml and ml.NineSlice then
		S:StripTextures(ml)
		S:SetTemplate(ml, "Transparent", "TOP")
	end
	if self.db.lootRoll then
		for i = 1, (NUM_GROUP_LOOT_FRAMES or 4) do
			SkinRollFrame(_G["GroupLootFrame" .. i])
		end
		if GroupLootContainer then
			local holder = CreateFrame("Frame", "SentinelUILootRollHolder", UIParent)
			holder:SetSize(280, 60)
			S:CreateMover(holder, "lootRoll", L["Loot Rolls"], { "TOP", "UIParent", "TOP", 0, -200 }, "general")
			GroupLootContainer:ClearAllPoints()
			GroupLootContainer:SetPoint("TOP", holder, "TOP")
			GroupLootContainer.ignoreFramePositionManager = true
			hooksecurefunc(GroupLootContainer, "SetPoint", function(f, _, rel)
				if rel ~= holder then S:SafeCall("Loot:Anchor", function() f:ClearAllPoints() f:SetPoint("TOP", holder, "TOP") end) end
			end)
		end
		-- roll frames are created lazily - skin them when the first roll arrives
		self:RegisterEvent("START_LOOT_ROLL", function(_, rollID)
			M:TrackRoll(rollID)
			C_Timer.After(0.1, function()
				for i = 1, (NUM_GROUP_LOOT_FRAMES or 4) do
					SkinRollFrame(_G["GroupLootFrame" .. i])
				end
				if GroupLootContainer then
					for i = 1, select("#", GroupLootContainer:GetChildren()) do
						SkinRollFrame(select(i, GroupLootContainer:GetChildren()))
					end
				end
				-- container may not have existed at login: anchor it late
				if GroupLootContainer and S.movers.lootRoll then
					local holder = _G.SentinelUILootRollHolder
					if holder then
						GroupLootContainer:ClearAllPoints()
						GroupLootContainer:SetPoint("TOP", holder, "TOP")
						GroupLootContainer.ignoreFramePositionManager = true
					end
				end
			end)
		end)
	end
	S:LogInfo("misc", "loot skinned: LootFrame=" .. tostring(LootFrame ~= nil) .. " history=" .. tostring(_G.LootHistoryFrame ~= nil) .. " rollContainer=" .. tostring(GroupLootContainer ~= nil))
end

-- Movers for Blizzard frames ----------------------------------------------------
local function MoveBlizzardFrame(frame, key, title, default, point)
	if not frame then return end
	point = point or "CENTER"
	local holder = CreateFrame("Frame", "SentinelUI" .. key .. "Holder", UIParent)
	local w, h = frame:GetSize()
	holder:SetSize(math.max(w or 0, 40), math.max(h or 0, 20))
	S:CreateMover(holder, key, title, default, "general")
	local function Place(f)
		if InCombatLockdown() and f.IsProtected and f:IsProtected() then
			-- unanchored frames render at screen center; queue instead of skipping
			S:RunOutOfCombat(Place, f)
			return
		end
		f.suiPlacing = true
		f:ClearAllPoints()
		f:SetPoint(point, holder, point)
		f.suiPlacing = nil
	end
	frame.ignoreFramePositionManager = true
	if frame.SetMovable then frame:SetMovable(true) frame:SetUserPlaced(true) end
	Place(frame)
	hooksecurefunc(frame, "SetPoint", function(f) if not f.suiPlacing then Place(f) end end)
end

-- Extra Blizzard elements -----------------------------------------------------
-- toast/alerts (achievement, loot won, currency gained, ...)
local function SkinAlertFrame(f)
	if not f or f.suiAlertSkinned or (f.IsForbidden and f:IsForbidden()) then return end
	f.suiAlertSkinned = true
	local icon = f.Icon or f.icon or f.IconTexture or (f.GetName and _G[f:GetName() .. "IconTexture"]) or (f.IconFrame and f.IconFrame.Icon)
	for i = 1, select("#", f:GetRegions()) do
		local r = select(i, f:GetRegions())
		if r:IsObjectType("Texture") and r ~= icon then r:SetAlpha(0) end
	end
	if icon and icon.SetTexCoord then
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		-- framed icon: dark backdrop + border around the icon
		if icon.IsObjectType and icon:IsObjectType("Texture") then
			local bd = CreateFrame("Frame", nil, f, S.BackdropTemplate)
			bd:SetFrameLevel(max(0, f:GetFrameLevel()))
			S:SetOutside(bd, icon)
			S:SetTemplate(bd, "Default")
			icon:SetParent(bd)
		end
	end
	S:CreateBackdrop(f, "Transparent", "TOP")
	for i = 1, select("#", f:GetRegions()) do
		local r = select(i, f:GetRegions())
		if r:IsObjectType("FontString") then S:SetFont(r, nil, 12, "OUTLINE") end
	end
end

local function SkinAllAlerts()
	local af = _G.AlertFrame
	if not af then return end
	for i = 1, select("#", af:GetChildren()) do
		SkinAlertFrame(select(i, af:GetChildren()))
	end
end

function M:SkinAlerts()
	-- EventToastManager shows big toasts (level up, scenarios) on modern clients
	local et = _G.EventToastManagerFrame
	if et then
		MoveBlizzardFrame(et, "eventToasts", L["Event Toasts"], { "TOP", "UIParent", "TOP", 0, -160 }, "TOP")
		if et.DisplayToast then
			hooksecurefunc(et, "DisplayToast", function()
				C_Timer.After(0, function()
					for i = 1, select("#", et:GetChildren()) do SkinAlertFrame(select(i, et:GetChildren())) end
				end)
			end)
		end
	end
	local af = _G.AlertFrame
	if not af then return end
	MoveBlizzardFrame(af, "alerts", L["Alerts"], { "TOP", "UIParent", "TOP", 0, -50 }, "TOP")
	if af.AddAlertFrame then hooksecurefunc(af, "AddAlertFrame", function() C_Timer.After(0, SkinAllAlerts) end) end
	for _, systems in ipairs({ af.alertFrameSubSystems, af.alertSubSystems }) do
		if systems then
			for _, system in pairs(systems) do
				if system and system.AddAlertFrame then
					hooksecurefunc(system, "AddAlertFrame", function() C_Timer.After(0, SkinAllAlerts) end)
				end
			end
		end
	end
	SkinAllAlerts()
end

-- floating text frames: zone announcements, raid warnings, boss emotes, errors
function M:SkinFloatingText()
	for _, n in ipairs({ "ZoneTextString", "PVPTextString", "SubZoneTextString", "AutoFollowStatusText" }) do
		local fs = _G[n]
		if fs then S:SetFont(fs, S.media.font, n == "SubZoneTextString" and 24 or 30, "OUTLINE") end
	end
	for _, n in ipairs({ "RaidWarningFrameSlot1", "RaidWarningFrameSlot2", "RaidBossEmoteFrameSlot1", "RaidBossEmoteFrameSlot2" }) do
		local fs = _G[n]
		if fs then S:SetFont(fs, S.media.font, 20, "OUTLINE") end
	end
	if _G.UIErrorsFrame then
		S:SetFont(_G.UIErrorsFrame, S.media.font, 14, "OUTLINE")
	end
	-- raid warning / boss emote / error positions get stacked below the top edge
	MoveBlizzardFrame(_G.RaidWarningFrame, "raidWarning", L["Raid Warnings"], { "TOP", "UIParent", "TOP", 0, -140 }, "TOP")
	MoveBlizzardFrame(_G.RaidBossEmoteFrame, "bossEmote", L["Boss Emotes"], { "TOP", "UIParent", "TOP", 0, -110 }, "TOP")
	MoveBlizzardFrame(_G.UIErrorsFrame, "uiErrors", L["Error Text"], { "TOP", "UIParent", "TOP", 0, -170 }, "TOP")
	MoveBlizzardFrame(_G.ZoneTextFrame, "zoneText", L["Zone Text"], { "TOP", "UIParent", "TOP", 0, -140 }, "TOP")
end

-- quest item buttons: usable items of watched quests, clickable (secure item buttons)
local questItemTmp = {}
function M:SetupQuestItems()
	if not GetQuestLogSpecialItemInfo or not GetNumQuestWatches or not GetQuestIndexForWatch then
		S:LogInfo("misc", "quest items: API not available on this client")
		return
	end
	local f = CreateFrame("Frame", "SentinelUIQuestItems", UIParent)
	f:SetSize(30, 30)
	f.btns = {}
	self.questItems = f
	S:CreateMover(f, "questItems", L["Quest Items"], { "TOPRIGHT", "SentinelUIMover_minimap", "BOTTOMRIGHT", -40, -400 }, "general")

	local function Refresh()
		if InCombatLockdown() then return S:RunOutOfCombat(Refresh) end
		wipe(questItemTmp)
		for i = 1, GetNumQuestWatches() do
			local qi = GetQuestIndexForWatch(i)
			if qi then
				local link, icon, charges = GetQuestLogSpecialItemInfo(qi)
				if link then questItemTmp[#questItemTmp + 1] = { link = link, icon = icon, charges = charges } end
			end
		end
		for i, it in ipairs(questItemTmp) do
			local b = f.btns[i]
			if not b then
				b = CreateFrame("Button", "SentinelUIQuestItem" .. i, f, "SecureActionButtonTemplate")
				b:SetSize(28, 28)
				b:RegisterForClicks("AnyUp", "AnyDown")
				b:SetAttribute("type", "item")
				b.icon = b:CreateTexture(nil, "ARTWORK")
				b.icon:SetAllPoints()
				b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
				S:CreateBackdrop(b, "Default")
				b.count = S:FontString(b, 10, "OUTLINE", S.media.numberFont)
				b.count:SetPoint("BOTTOMRIGHT", 1, -1)
				b:SetScript("OnEnter", function(s2)
					GameTooltip:SetOwner(s2, "ANCHOR_LEFT")
					if s2.link then GameTooltip:SetHyperlink(s2.link) end
					GameTooltip:Show()
				end)
				b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
				f.btns[i] = b
			end
			b.link = it.link
			b:SetAttribute("item", it.link)
			if not it.icon then it.icon = select(10, GetItemInfo(it.link) or "") end
			b.icon:SetTexture(it.icon)
			b.count:SetText(it.charges and it.charges > 1 and it.charges or "")
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -((i - 1) * 31))
			b:Show()
		end
		for i = #questItemTmp + 1, #f.btns do f.btns[i]:Hide() end
		f:SetHeight(math.max(1, #questItemTmp) * 31)
	end
	self.questItemRefresh = Refresh
	self:RegisterEvent("QUEST_LOG_UPDATE", Refresh)
	self:RegisterEvent("QUEST_WATCH_UPDATE", Refresh)
	self:RegisterEvent("BAG_UPDATE", Refresh)
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", Refresh)
	Refresh()
end

-- quest tracker lines: gold headers, styled fonts
function M:SkinObjectiveTracker()
	local qw = _G.QuestWatchFrame or _G.WatchFrame or _G.ObjectiveTrackerFrame
	if not qw then return end
	for i = 1, select("#", qw:GetRegions()) do
		local r = select(i, qw:GetRegions())
		if r:IsObjectType("FontString") then S:SetFont(r, S.media.font, 12, "OUTLINE") end
	end
	-- classic lines are named fontstrings
	for i = 1, 50 do
		local line = _G["QuestWatchLine" .. i] or _G["WatchFrameLine" .. i]
		if not line then break end
		S:SetFont(line, S.media.font, 12, "OUTLINE")
	end
	-- modern tracker: strip the module header chrome
	local ot = _G.ObjectiveTrackerFrame
	if ot then
		if ot.Header then S:StripTextures(ot.Header) end
		if ot.NineSlice then ot.NineSlice:SetAlpha(0) end
	end
end

-- misc one-off frames that show Blizzard chrome
function M:SkinStandalone()
	local ghost = _G.GhostFrame
	if ghost then
		S:StripTextures(ghost)
		local c = _G.GhostFrameContentsFrame
		if c then
			S:StripTextures(c)
			if c:IsObjectType("Button") then S:SkinButton(c) else S:CreateBackdrop(ghost, "Default") end
		else
			S:CreateBackdrop(ghost, "Default")
		end
	end
	local ac = _G.AutoCompleteBox
	if ac then
		S:StripTextures(ac)
		S:SetTemplate(ac, "Transparent", "TOP")
	end
	local br = _G.BonusRollFrame
	if br then
		S:StripTextures(br)
		S:CreateBackdrop(br, "Transparent", "TOP")
		MoveBlizzardFrame(br, "bonusRoll", L["Bonus Roll"], { "BOTTOM", "UIParent", "BOTTOM", 0, 330 }, "BOTTOM")
	end
	local loc = _G.LossOfControlFrame
	if loc then
		MoveBlizzardFrame(loc, "lossOfControl", L["Loss of Control"], { "CENTER", "UIParent", "CENTER", 0, 30 }, "CENTER")
		for i = 1, select("#", loc:GetRegions()) do
			local r = select(i, loc:GetRegions())
			if r:IsObjectType("FontString") then S:SetFont(r, S.media.font, 16, "OUTLINE") end
		end
	end
	-- alt power is handled by M:CreateAltPower (own Sentinel bar, Blizzard's hidden)
	local wsu = _G.WorldStateAlwaysUpFrame
	if wsu then
		MoveBlizzardFrame(wsu, "worldState", L["World State"], { "TOP", "UIParent", "TOP", 0, -40 }, "TOP")
	end
	-- TimerTracker bars (quest timers, BG start countdown) - created lazily
	if _G.TimerTracker then
		local function SkinTimerBar(bar)
			if not bar or bar.suiSkinned then return end
			bar.suiSkinned = true
			local status = bar.Bar or _G[bar:GetName() and (bar:GetName() .. "Bar") or ""]
			S:StripTextures(bar)
			if status and status.SetStatusBarTexture then
				status:SetStatusBarTexture(S.media.statusbar)
				S:CreateBackdrop(status, "Default")
				for i = 1, select("#", status:GetRegions()) do
					local r = select(i, status:GetRegions())
					if r:IsObjectType("FontString") then S:SetFont(r, S.media.font, 12, "OUTLINE") end
				end
			end
		end
		local function SkinTimerBars()
			local tt = _G.TimerTracker
			if tt and tt.barList then
				for _, bar in ipairs(tt.barList) do SkinTimerBar(bar) end
			end
			for i = 1, 6 do SkinTimerBar(_G["TimerTrackerTimerBar" .. i]) end
		end
		if TimerTracker_Update then hooksecurefunc("TimerTracker_Update", SkinTimerBars) end
		SkinTimerBars()
		MoveBlizzardFrame(_G.TimerTracker, "timerTracker", L["Timer Bars"], { "TOP", "UIParent", "TOP", 0, -160 }, "TOP")
	end
	-- ready check listener window is created on demand
	self:RegisterEvent("READY_CHECK", function()
		local rc = _G.ReadyCheckListenerFrame
		if rc and not rc.suiWindowSkinned then
			rc.suiWindowSkinned = true
			S:StripTextures(rc)
			S:CreateBackdrop(rc, "Transparent", "TOP")
			S:SkinChildren(rc)
		end
	end)
	-- BG capture bars (flag captures, tower ticks) - restyle + anchor to a mover
	local capHolder = CreateFrame("Frame", "SentinelUICaptureBarHolder", UIParent)
	capHolder:SetSize(200, 20)
	S:CreateMover(capHolder, "captureBar", L["Capture Bar"], { "TOP", "UIParent", "TOP", 0, -190 }, "general")
	local function UpdateCaptureBars()
		local prev
		for i = 1, (NUM_EXTENDED_UI_FRAMES or 3) do
			local bar = _G["WorldStateCaptureBar" .. i]
			if bar and bar:IsVisible() then
				bar:ClearAllPoints()
				if prev then bar:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -6) else bar:SetPoint("TOPLEFT", capHolder, "TOPLEFT") end
				prev = bar
				if not bar.suiSkinned then
					bar.suiSkinned = true
					for j = 1, select("#", bar:GetChildren()) do
						local child = select(j, bar:GetChildren())
						if child and child:IsObjectType("StatusBar") then
							child:SetStatusBarTexture(S.media.statusbar)
							S:CreateBackdrop(child, "Default")
						end
					end
					for j = 1, select("#", bar:GetRegions()) do
						local r = select(j, bar:GetRegions())
						if r:IsObjectType("FontString") then S:SetFont(r, S.media.font, 12, "OUTLINE") end
					end
				end
			end
		end
	end
	if _G.ManageFramePositions then hooksecurefunc("ManageFramePositions", UpdateCaptureBars)
	elseif _G.UIParent_ManageFramePositions then hooksecurefunc("UIParent_ManageFramePositions", UpdateCaptureBars) end
	self:RegisterEvent("UPDATE_WORLD_STATES", UpdateCaptureBars)
	UpdateCaptureBars()
	-- LFG/BG queue status: waiting-time counter attached to the queue eye button
	local qsb = _G.QueueStatusButton or _G.QueueStatusMinimapButton
	if qsb then
		MoveBlizzardFrame(qsb, "queueStatus", L["Queue Status"], { "TOPRIGHT", "SentinelUIMover_minimap", "BOTTOMRIGHT", -40, -6 }, "TOPRIGHT")
		if not M.queueText then
			M.queueText = S:FontString(qsb, 11, "OUTLINE")
			M.queueText:SetPoint("TOP", qsb, "BOTTOM", 0, -2)
			local ticker = CreateFrame("Frame", nil, qsb)
			local elapsed = 0
			ticker:SetScript("OnUpdate", function(_, e)
				elapsed = elapsed - e
				if elapsed > 0 then return end
				elapsed = 0.5
				local t = _G.QueueStatusButton and _G.QueueStatusButton.queuedTime
				if not t and _G.QueueStatusFrame then
					local e0 = _G.QueueStatusFrame.Entries
					local entry = e0 and (e0[1] or e0.entries and e0.entries[1])
					t = entry and entry.queuedTime
				end
				local secs = t and (GetTime() - t) or nil
				if secs and secs > 0 then
					local m = math.floor(secs / 60)
					M.queueText:SetText(m > 0 and format("%dm", m) or format("%ds", math.floor(secs)))
				else
					M.queueText:SetText("")
				end
			end)
		end
	end
	-- durability doll: replace the figure look with a colored text readout
	local dur = _G.DurabilityFrame
	if dur then
		S:StripTextures(dur)
		if not dur.suiText then
			dur.suiText = S:FontString(dur, 12, "OUTLINE")
			dur.suiText:SetPoint("CENTER")
			local function UpdateDur()
				local worst = 100
				for i = 1, 18 do
					local cur, max = GetInventoryItemDurability(i)
					if cur and max and max > 0 then worst = math.min(worst, cur / max * 100) end
				end
				if worst > 99.5 then dur.suiText:SetText("") return end
				local r, g, b = 1, 0.2, 0.2
				if worst > 50 then r, g, b = 1, 0.8, 0.2 elseif worst > 25 then r, g, b = 1, 0.4, 0.2 end
				dur.suiText:SetFormattedText("|cff%02x%02x%02x%d%%|r", r * 255, g * 255, b * 255, math.floor(worst))
			end
			hooksecurefunc(dur, "Show", UpdateDur)
			UpdateDur()
		end
	end
end

function M:SetupMovers()
	MoveBlizzardFrame(_G.DurabilityFrame, "durability", L["Durability Figure"], { "TOPRIGHT", "SentinelUIMover_minimap", "BOTTOMLEFT", -20, -40 }, "TOPRIGHT")
	MoveBlizzardFrame(_G.VehicleSeatIndicator, "vehicleSeat", L["Vehicle Seat"], { "TOPRIGHT", "SentinelUIMover_minimap", "BOTTOMLEFT", -20, -140 }, "TOPRIGHT")
	MoveBlizzardFrame(_G.UIWidgetTopCenterContainerFrame, "widgetTop", L["Top Widgets"], { "TOP", "UIParent", "TOP", 0, -30 }, "TOP")
	MoveBlizzardFrame(_G.UIWidgetBelowMinimapContainerFrame, "widgetBelowMinimap", L["Minimap Widgets"], { "TOPRIGHT", "SentinelUIMover_minimap", "BOTTOMRIGHT", 0, -40 }, "TOPRIGHT")
	MoveBlizzardFrame(_G.TicketStatusFrame, "gmTicket", L["GM Ticket"], { "TOPLEFT", "UIParent", "TOPLEFT", 260, -6 }, "TOPLEFT")
	if not S.isRetail then
		MoveBlizzardFrame(_G.QuestWatchFrame or _G.WatchFrame, "questWatch", L["Quest Tracker"], { "TOPRIGHT", "SentinelUIMover_minimap", "BOTTOMRIGHT", -40, -60 }, "TOPRIGHT")
		local qw = _G.QuestWatchFrame or _G.WatchFrame
		if qw and S.movers.questWatch then S.movers.questWatch:SetSize(220, 300) end
	end
	-- mirror timers (breath / fatigue)
	for i = 1, (MIRRORTIMER_NUMTIMERS or 3) do
		local timer = _G["MirrorTimer" .. i]
		if timer then
			local bar = _G["MirrorTimer" .. i .. "StatusBar"] or timer.StatusBar
			S:StripTextures(timer)
			if bar then
				bar:SetStatusBarTexture(S.media.statusbar)
				S:CreateBackdrop(bar, "Default")
				bar:ClearAllPoints()
				bar:SetAllPoints(timer)
			end
			local text = _G["MirrorTimer" .. i .. "Text"] or timer.Text
			if text then S:SetFont(text, S.media.font, 12, "OUTLINE") text:ClearAllPoints() text:SetPoint("CENTER", timer) end
			timer:SetSize(220, 16)
		end
	end
	MoveBlizzardFrame(_G.MirrorTimerContainer or _G.MirrorTimer1, "mirrorTimer", L["Breath Timer"], { "TOP", "UIParent", "TOP", 0, -120 }, "TOP")
end

-- Buff reminder ---------------------------------------------------------------
-- per-class self buffs; each inner list is satisfied when ANY of its auras is up.
-- spell ids are resolved to localized names at runtime, so this works on every client locale.
local classBuffs = {
	MAGE = { { 1459, 23028 }, { 168, 7302, 7300, 7301, 6117, 22782, 22783, 30482 } },
	PRIEST = { { 1243, 21562, 21564 }, { 588, 602, 1006, 7128, 10951, 10952 }, { 976, 10957, 10958 } },
	DRUID = { { 1126, 5232, 6756, 5234, 8907, 9884, 9885, 26990, 26991 }, { 467, 782, 1075, 8914, 9756, 9910, 26992 } },
	WARRIOR = { { 6673, 5242, 6192, 11549, 11550, 11551, 25289 }, { 469, 47439, 47440 } },
	WARLOCK = { { 706, 1086, 11733, 11734, 11735, 27260, 28176, 28189 }, { 5697, 5698 } },
	-- mutually exclusive buffs must live in ONE group (any member = satisfied):
	-- a hunter runs one aspect, a paladin one blessing, a shaman one shield
	HUNTER = { { 13165, 14318, 14319, 14320, 14321, 14322, 25296, 27044, 13163, 13161, 13159, 5118, 20043, 20190, 27045, 34074 } },
	PALADIN = { { 19740, 19834, 19835, 19836, 19837, 19838, 25291, 27140, 25894, 19742, 19850, 19852, 19853, 19854, 25290, 27142, 27143, 25898, 20217, 25899, 1038, 25895, 20911, 20912, 20913, 20914, 27168, 27169, 19979, 19980, 27144, 27145 } },
	SHAMAN = { { 324, 325, 905, 945, 8134, 10431, 10432, 25469, 25472, 24398, 33736, 52127, 52129, 52131, 52133, 52134, 52136, 52138 } },
	ROGUE = {},
}
local reminderNames

-- texture paths always resolve if the art exists; fileIDs returned by the
-- client can point at assets missing on this build (renders as "?")
local groupIconPath = {
	[1459] = [[Interface\Icons\Spell_Holy_MagicalSentry]],   -- arcane intellect
	[168] = [[Interface\Icons\Spell_MageArmor]],           -- mage armor
	[1243] = [[Interface\Icons\Spell_Holy_WordFortitude]], -- fortitude
	[588] = [[Interface\Icons\Spell_Holy_InnerFire]],      -- inner fire
	[976] = [[Interface\Icons\Spell_Shadow_AntiShadow]],   -- shadow protection
	[1126] = [[Interface\Icons\Spell_Nature_Regeneration]], -- mark of the wild
	[467] = [[Interface\Icons\Spell_Nature_Thorns]],       -- thorns
	[6673] = [[Interface\Icons\Ability_Warrior_BattleShout]],
	[469] = [[Interface\Icons\Ability_Warrior_CommandingShout]],
	[706] = [[Interface\Icons\Spell_Shadow_RagingScream]], -- demon armor
	[5697] = [[Interface\Icons\Spell_Shadow_DemonBreath]], -- unending breath
	[13165] = [[Interface\Icons\Spell_Nature_RavenForm]],  -- aspect of the hawk
	[19740] = [[Interface\Icons\Spell_Holy_FistOfJustice]], -- blessing of might
	[324] = [[Interface\Icons\Spell_Nature_LightningShield]],
}

local function ReminderMissing(nameList)
	for i = 1, 40 do
		local aura = S.GetAura("player", i, "HELPFUL")
		if not aura then break end
		local an, aid = aura.name, aura.spellId
		for _, entry in ipairs(nameList) do
			if aid and not IsSecret(aid) and entry == aid then return false end
			if an and not IsSecret(an) and entry == an then return false end
		end
	end
	return true
end

function M:UpdateBuffReminder()
	local holder = self.buffReminder
	if not holder then return end
	local db = self.db.buffReminder
	if not (db and db.enable) or not reminderNames then holder:Hide() return end
	if db.inCombatOnly and not UnitAffectingCombat("player") then holder:Hide() return end
	local shown = 0
	for gi, group in ipairs(reminderNames) do
		if ReminderMissing(group) then
			shown = shown + 1
			local b = holder[shown]
			if not b then
				b = CreateFrame("Frame", nil, holder)
				S:CreateBackdrop(b, "Default")
				b.tex = b:CreateTexture(nil, "ARTWORK")
				b.tex:SetPoint("TOPLEFT", 1, -1)
				b.tex:SetPoint("BOTTOMRIGHT", -1, 1)
				b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
				b:SetScript("OnEnter", function(self) if self.spellName then GameTooltip:SetOwner(self, "ANCHOR_BOTTOM") GameTooltip:SetText(format(L["Missing: %s"], self.spellName)) GameTooltip:Show() end end)
				b:SetScript("OnLeave", function() GameTooltip:Hide() end)
				holder[shown] = b
			end
			local size = db.size or 32
			b:SetSize(size, size)
			b:ClearAllPoints()
			b:SetPoint("LEFT", holder, "LEFT", (shown - 1) * (size + 4), 0)
			-- icon can be unresolved at init (GetSpellInfo not ready) or arrive as
			-- a secret value on this client: retry lazily across every icon API
			local icon = group.icon
			if (not icon or IsSecret(icon) or icon == 136116) and group.iconId then
				local _, _, ic = S.GetSpellInfo(group.iconId)
				if (not ic or IsSecret(ic)) and C_Spell and C_Spell.GetSpellTexture then
					ic = C_Spell.GetSpellTexture(group.iconId)
				end
				if (not ic or IsSecret(ic)) and GetSpellInfo then
					ic = select(3, GetSpellInfo(group.iconId))
				end
				if ic and not IsSecret(ic) then
					group.icon, icon = ic, ic
					if not group.iconDiag then
						group.iconDiag = true
						S:LogInfo("buffreminder", format("icon resolved: id=%s icon=%s (%s)",
							tostring(group.iconId), tostring(ic), type(ic)))
					end
				elseif not group.iconDiag then
					group.iconDiag = true
					local _, _, a = S.GetSpellInfo(group.iconId)
					local bt = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(group.iconId)
					local ct = GetSpellInfo and select(3, GetSpellInfo(group.iconId))
					S:LogInfo("buffreminder", format("icon unresolved: id=%s a=%s(%s) tex=%s(%s) legacy=%s(%s)",
						tostring(group.iconId), tostring(a), tostring(IsSecret(a)),
						tostring(bt), tostring(IsSecret(bt)), tostring(ct), tostring(IsSecret(ct))))
				end
			end
			b.tex:SetTexture(icon or 136116)
			b.tex:SetDesaturated(true)
			b.spellName = group.label
			b:Show()
		end
	end
	for i = shown + 1, #holder do holder[i]:Hide() end
	holder:SetShown(shown > 0)
	if shown > 0 and db.sound and not holder.warned then
		holder.warned = true
		if PlaySound then pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959) end
	elseif shown == 0 then
		holder.warned = nil
	end
end

function M:CreateBuffReminder()
	local db = self.db.buffReminder
	if not (db and db.enable) then return end
	local _, class = UnitClass("player")
	local groups = classBuffs[class]
	if not groups or #groups == 0 then return end
	if not reminderNames then
		reminderNames = {}
		for gi, ids in ipairs(groups) do
			local names, label, icon = {}, nil, nil
			for _, id in ipairs(ids) do
				local nm, _, ic = S.GetSpellInfo(id)
				if nm and not IsSecret(nm) then
					names[#names + 1] = nm
					names[#names + 1] = id
					if not label then label = nm end
					if not icon then icon = ic end
					if not names.iconId then names.iconId = id end
				end
			end
			if #names > 0 then
				names.icon, names.label = groupIconPath[ids[1]] or ((icon and not IsSecret(icon)) and icon or 136116), label
				reminderNames[#reminderNames + 1] = names
			end
		end
	end
	if not reminderNames or #reminderNames == 0 then return end
	local holder = CreateFrame("Frame", "SentinelUIBuffReminder", UIParent)
	holder:SetSize((db.size or 32) * #reminderNames, db.size or 32)
	self.buffReminder = holder
	S:CreateMover(holder, "buffReminder", L["Buff Reminder"], { "TOPRIGHT", "UIParent", "TOPRIGHT", -195, -215 }, "general")
	self:RegisterUnitEvent("UNIT_AURA", function() M:UpdateBuffReminder() end, "player")
	self:RegisterEvent("SPELLS_CHANGED", function() M:UpdateBuffReminder() end)
	self:UpdateBuffReminder()
end

-- Alternative power bar --------------------------------------------------------
function M:UpdateAltPower()
	local bar = self.altPower
	if not bar then return end
	local pt = ALT_POWER_BAR_POWER_TYPE or ALTERNATE_POWER_INDEX
	if not pt then bar:Hide() return end
	local cur, mx = UnitPower("player", pt), UnitPowerMax("player", pt)
	if IsSecret(mx) or not mx or mx <= 0 then bar:Hide() return end
	bar:SetMinMaxValues(0, mx)
	bar:SetValue(cur)
	if bar.Text then
		local name = ""
		if GetUnitPowerBarInfo then
			local info = GetUnitPowerBarInfo("player")
			if info and info.name then name = info.name end
		end
		bar.Text:SetText(format("%s  %d/%d", name, cur, mx))
	end
	bar:Show()
end

function M:CreateAltPower()
	if not UnitPower then return end
	local bar = S:CreateStatusBar(UIParent, "SentinelUIAltPower", "Default")
	bar:SetSize(220, 18)
	bar.Text = S:FontString(bar, 12, "OUTLINE", S.media.numberFont, nil, "CENTER")
	bar:SetStatusBarColor(S.accent.r, S.accent.g, S.accent.b)
	bar:Hide()
	self.altPower = bar
	S:CreateMover(bar, "altPower", L["Alternative Power"], { "TOP", "UIParent", "TOP", 0, -80 }, "general")
	-- Blizzard's own bar would show the same data on top of ours
	local ppb = _G.PlayerPowerBarAlt
	if ppb and self.db.altPowerBar ~= false then
		ppb:UnregisterAllEvents()
		ppb:Hide()
	end
	self:RegisterUnitEvent("UNIT_POWER_UPDATE", function() M:UpdateAltPower() end, "player")
	self:RegisterUnitEvent("UNIT_MAXPOWER", function() M:UpdateAltPower() end, "player")
	pcall(self.RegisterEvent, self, "UNIT_POWER_BAR_SHOW", function() M:UpdateAltPower() end)
	pcall(self.RegisterEvent, self, "UNIT_POWER_BAR_HIDE", function() M:UpdateAltPower() end)
	self:UpdateAltPower()
end

function M:Update()
	self.db = S.db.profile.general
	if self.buffReminder then self:UpdateBuffReminder() end
	if self.altPower then self:UpdateAltPower() end
end

function M:Initialize()
	self.db = S.db.profile.general
	-- Blizzard renders "<Name> / <Guild>" above the own character; SentinelUI UI keeps it clean
	pcall(SetCVar, "UnitNameOwn", "0")
	-- keep max camera distance applied every login/reload (Install sets it too,
	-- but settings-reset or edited configs should not silently lose it)
	if self.db.maxCamera ~= false then
		pcall(SetCVar, "cameraDistanceMaxZoomFactor", S.isRetail and 2.6 or 4)
	end
	self:RegisterEvent("MERCHANT_SHOW")
	self:RegisterEvent("PARTY_INVITE_REQUEST")
	self:RegisterEvent("DUEL_REQUESTED")
	self:RegisterEvent("PLAYER_REGEN_DISABLED")
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	self:RegisterEvent("UI_ERROR_MESSAGE")
	self:RegisterEvent("UPDATE_FACTION")
	self:RegisterEvent("QUEST_LOG_UPDATE")
	self:RegisterEvent("PLAYER_FLAGS_CHANGED")
	HookDeletePopup()
	S:RegisterChatCommand("suiconsume", ConsumeCheck)
	S:RegisterChatCommand("consume", ConsumeCheck)
	self:RegisterEvent("CHAT_MSG_LOOT")
	self:RegisterEvent("TRADE_MONEY_CHANGED", UpdateTradeGold)
	self:RegisterEvent("TRADE_SHOW", UpdateTradeGold)
	self:RegisterEvent("MAIL_SHOW", BuildMailAltList)
	self:RegisterEvent("MAIL_SEND_INFO_UPDATE", BuildMailAltList)
	self:RegisterEvent("BAG_UPDATE")
	self:RegisterEvent("CHAT_MSG_SYSTEM")
	HookFriendsNotes()
	-- buff expiry scan: light 10s poller (expirations fire no events)
	self._buffPoll = self._buffPoll or CreateFrame("Frame")
	self._buffPoll:SetScript("OnUpdate", function(_, el)
		M._bt = (M._bt or 0) + el
		if M._bt < 10 then return end
		M._bt = 0
		BuffExpireScan()
	end)
	self:RegisterEvent("MINIMAP_PING", function(_, unit)
		if not M.db.pingAlert then return end
		local name = UnitName(unit)
		if name and not IsSecret(name) then
			S:Print(format("|cffffd700%s|r " .. L["pinged the minimap"], name))
		end
	end)
	if CombatLogGetCurrentEventInfo then
		pcall(self.RegisterEvent, self, "COMBAT_LOG_EVENT_UNFILTERED")
	end
	-- TalkingHeadFrame exists on modern clients only; skin + move it, or hide when disabled
	local function SkinTalkingHead()
		local th = _G.TalkingHeadFrame
		if not th then return end
		if not th.suiPlayHook then
			th.suiPlayHook = true
			hooksecurefunc(th, "PlayCurrent", function(f) if M.db.talkingHead == false then f:CloseImmediately() end end)
		end
		if th.suiSkinned then return end
		th.suiSkinned = true
		for _, key in ipairs({ "MainFrame", "PortraitFrame", "BackgroundFrame" }) do
			local sub = th[key]
			if sub then
				for j = 1, select("#", sub:GetRegions()) do
					local r = select(j, sub:GetRegions())
					if r:IsObjectType("Texture") then
						local layer = r:GetDrawLayer()
						if layer == "BACKGROUND" or layer == "BORDER" then r:SetAlpha(0) end
					elseif r:IsObjectType("FontString") then S:SetFont(r, S.media.font, 14, "OUTLINE") end
				end
			end
		end
		local tf = th.TextFrame and th.TextFrame.Text
		if tf then S:SetFont(tf, S.media.font, 13) end
		MoveBlizzardFrame(th, "talkingHead", L["Talking Head"], { "TOP", "UIParent", "TOP", 0, -40 }, "TOP")
	end
	if _G.TalkingHeadFrame then
		SkinTalkingHead()
	else
		self:RegisterEvent("ADDON_LOADED", function(_, _, addon)
			if addon == "Blizzard_TalkingHeadUI" then SkinTalkingHead() end
		end)
	end
	-- Blizzard guild news bug (TBC/Anniversary client): GuildUtil.lua formats
	-- dungeon-encounter news with GUILD_NEWS_DUNGEON_ENCOUNTER_* strings the
	-- client never defines -> "attempt to index local 'formatString'" for
	-- every such row in the Communities guild news list. Provide fallbacks
	-- and guard the renderer so any other missing GUILD_NEWS_FORMATn also
	-- degrades to plain text instead of throwing.
	local function FixGuildNews()
		if M.guildNewsPatched or not _G.GuildNewsButton_SetNews then return end
		M.guildNewsPatched = true
		_G.GUILD_NEWS_DUNGEON_ENCOUNTER_NORMAL = _G.GUILD_NEWS_DUNGEON_ENCOUNTER_NORMAL or "%s"
		_G.GUILD_NEWS_DUNGEON_ENCOUNTER_HEROIC = _G.GUILD_NEWS_DUNGEON_ENCOUNTER_HEROIC or _G.GUILD_NEWS_DUNGEON_ENCOUNTER_NORMAL
		_G.GUILD_NEWS_DUNGEON_ENCOUNTER_MYTHIC = _G.GUILD_NEWS_DUNGEON_ENCOUNTER_MYTHIC or _G.GUILD_NEWS_DUNGEON_ENCOUNTER_NORMAL
		local orig = _G.GuildNewsButton_SetNews
		_G.GuildNewsButton_SetNews = function(button, newsID)
			if pcall(orig, button, newsID) then return end
			button.index, button.newsType = nil, nil
			local info = C_GuildInfo and C_GuildInfo.GetGuildNewsInfo and C_GuildInfo.GetGuildNewsInfo(newsID)
			if info and button.text then
				button.text:SetText((((info.whoText or "") .. " " .. (info.whatText or "")):gsub("^%s+", "")))
			end
		end
	end
	FixGuildNews()
	if not _G.GuildNewsButton_SetNews then
		self:RegisterEvent("ADDON_LOADED", function(_, _, addon)
			if addon == "Blizzard_FrameXML" then FixGuildNews() end
		end)
	end
	if S.isRetail then
		self:RegisterEvent("ACHIEVEMENT_EARNED", function() if M.db.screenshotAchievement then C_Timer.After(1, Screenshot) end end)
	end
	self:SetupBubbles()
	self:CreateRaidUtility()
	self:CreateBuffReminder()
	self:CreateAltPower()
	self:SkinLoot()
	self:SetupMovers()
	self:SkinAlerts()
	self:SkinFloatingText()
	self:SkinObjectiveTracker()
	self:SkinStandalone()
	self:SetupQuestItems()
end
