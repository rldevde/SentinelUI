-- Combined bags & bank with search, sorting, item level, quality borders, junk/quest markers.
local _, ns = ...
local S = ns.S
local L = S.L
local B = S:NewModule("Bags")

local _G = _G
local pairs, ipairs, tinsert, sort, format, floor, max, min, ceil = pairs, ipairs, tinsert, table.sort, format, math.floor, math.max, math.min, math.ceil
local strmatch = strmatch or string.match
local BLANK = [[Interface\Buttons\WHITE8X8]]

B.frames = {}

-- keyring capacity: the modern C_Container API cannot see container -2 on
-- several classic builds, so fall back through the legacy functions
local function KeyRingCapacity()
	if GetKeyRingSize then
		local n = GetKeyRingSize()
		if n and n > 0 then return n end
	end
	if GetContainerNumSlots then
		local n = GetContainerNumSlots(S.KEYRING_CONTAINER or -2)
		if n and n > 0 then return n end
	end
	return S.GetContainerNumSlots(S.KEYRING_CONTAINER or -2) or 0
end

local function IsKeyRingShownOrEnabled()
	if not S.KEYRING_CONTAINER then return false end
	if IsKeyRingEnabled and IsKeyRingEnabled() == false then return false end
	return KeyRingCapacity() > 0
end

local function BagList(isBank)
	local list = {}
	if isBank then
		tinsert(list, S.BANK_CONTAINER)
		for i = S.BANK_BAG_FIRST, S.BANK_BAG_FIRST + S.NUM_BANKBAGSLOTS - 1 do tinsert(list, i) end
	else
		-- inventory = backpack (0) + the four bag slots; reagent bag handled separately (Retail only)
		for i = 0, 4 do tinsert(list, i) end
		if S.REAGENTBAG_CONTAINER then tinsert(list, S.REAGENTBAG_CONTAINER) end
		-- keyring integrated into the inventory (Classic only)
		if S.KEYRING_CONTAINER and IsKeyRingShownOrEnabled() then tinsert(list, S.KEYRING_CONTAINER) end
	end
	return list
end

-- Normalize container item info across client builds (incl. legacy fallback for the keyring)
local function ItemInfo(bag, slot)
	local info
	if bag == (S.KEYRING_CONTAINER or -2) and GetContainerItemInfo then
		-- C_Container cannot read the keyring on some builds; legacy API first
		local icon, count, locked, quality, readable, lootable, link, filtered, noValue, itemID = GetContainerItemInfo(bag, slot)
		if icon then
			info = { iconFileID = icon, stackCount = count, isLocked = locked, quality = quality,
				isReadable = readable, hasLoot = lootable, hyperlink = link, isFiltered = filtered,
				hasNoValue = noValue, itemID = itemID }
		end
	end
	info = info or S.GetContainerItemInfo(bag, slot)
	if not info and GetContainerItemInfo then
		-- some containers (keyring -2) are only readable via the legacy API on TBC builds
		local icon, count, locked, quality, readable, lootable, link, filtered, noValue, itemID = GetContainerItemInfo(bag, slot)
		if icon then
			info = { iconFileID = icon, stackCount = count, isLocked = locked, quality = quality,
				isReadable = readable, hasLoot = lootable, hyperlink = link, isFiltered = filtered,
				hasNoValue = noValue, itemID = itemID }
		end
	end
	if info then
		info.iconFileID = info.iconFileID or info.icon
		info.hyperlink = info.hyperlink or info.link or info.itemLink
		info.stackCount = info.stackCount or info.count or 1
		info.isLocked = info.isLocked or info.locked or false
	end
	return info
end

local function GetQuestInfo(bag, slot)
	if C_Container and C_Container.GetContainerItemQuestInfo then
		local info = C_Container.GetContainerItemQuestInfo(bag, slot)
		if info then return info.isQuestItem, info.questID, info.isActive end
		return
	end
	if GetContainerItemQuestInfo then return GetContainerItemQuestInfo(bag, slot) end
end

-- Slot buttons --------------------------------------------------------------
function B:CreateSlot(frame, bagFrame, bag, slot)
	local name = format("SentinelUI%sBag%dSlot%d", frame.isBank and "Bank" or "", bag + 10, slot)
	local btn = _G[name]
	if not btn then
		local ok, created = pcall(CreateFrame, "ItemButton", name, bagFrame, "ContainerFrameItemButtonTemplate")
		btn = ok and created or CreateFrame("Button", name, bagFrame, "ContainerFrameItemButtonTemplate")
	end
	btn:SetID(slot)
	if btn.SetBagID then btn:SetBagID(bag) end
	btn:EnableMouse(true)
	btn.bag, btn.slot = bag, slot
	if bag == S.KEYRING_CONTAINER then
		-- the stock template click path goes through C_Container which cannot
		-- reach the keyring (-2); drive it with the legacy API instead
		btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		btn:SetScript("OnClick", function(b, button)
			if button == "LeftButton" then
				PickupContainerItem(-2, b.slot)
			end
		end)
		btn:SetScript("OnReceiveDrag", function(b)
			if CursorHasItem() then PickupContainerItem(-2, b.slot) end
		end)
	end
	if not btn.suiStyled then
		btn.suiStyled = true
		btn.icon = btn.icon or _G[name .. "IconTexture"]
		btn.countText = btn.Count or _G[name .. "Count"]
		btn.cooldown = btn.Cooldown or _G[name .. "Cooldown"]
		local normal = btn.GetNormalTexture and btn:GetNormalTexture()
		if normal then normal:SetAlpha(0) end
		for _, k in ipairs({ "IconBorder", "IconOverlay", "IconOverlay2", "NewItemTexture", "BattlepayItemTexture", "ExtendedSlot", "ItemContextOverlay", "searchOverlay", "JunkIcon", "UpgradeIcon", "flash", "IconQuestTexture" }) do
			if btn[k] and btn[k].SetAlpha then btn[k]:SetAlpha(0) end
		end
		local qt = _G[name .. "IconQuestTexture"]
		if qt then qt:SetAlpha(0) end
		if btn.icon then
			btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			S:SetInside(btn.icon, btn, 1.5, 1.5)
		end
		if btn.cooldown then S:SetInside(btn.cooldown, btn, 0, 0) S:RegisterCooldown(btn.cooldown) end
		S:CreateBackdrop(btn, "Default")
		if btn.SetPushedTexture then
			btn:SetPushedTexture(BLANK)
			btn:GetPushedTexture():SetVertexColor(1, 1, 1, 0.2)
			S:SetInside(btn:GetPushedTexture(), btn)
		end
		local hl = btn.GetHighlightTexture and btn:GetHighlightTexture()
		if hl then hl:SetTexture(BLANK) hl:SetVertexColor(1, 1, 1, 0.12) S:SetInside(hl, btn) end
		if btn.countText then
			btn.countText:ClearAllPoints()
			btn.countText:SetPoint("BOTTOMRIGHT", -1, 2)
			S:SetFont(btn.countText, S.media.numberFont, self.db.countFontSize, "OUTLINE")
		end
		local holder = CreateFrame("Frame", nil, btn)
		holder:SetAllPoints()
		holder:SetFrameLevel(btn:GetFrameLevel() + 4)
		btn.ilvl = S:FontString(holder, 11, "OUTLINE", S.media.numberFont)
		btn.ilvl:SetPoint("TOPLEFT", 1, -2)
		btn.bind = S:FontString(holder, 9, "OUTLINE", S.media.font)
		btn.bind:SetPoint("BOTTOMLEFT", 1, 2)
		-- own count text on the holder so it renders above icon/cooldown on every client
		btn.count = S:FontString(holder, self.db.countFontSize or 12, "OUTLINE", S.media.numberFont)
		btn.count:SetPoint("BOTTOMRIGHT", -1, 2)
		btn.junk = holder:CreateTexture(nil, "OVERLAY")
		btn.junk:SetTexture([[Interface\Buttons\UI-GroupLoot-Coin-Up]])
		btn.junk:SetSize(14, 14)
		btn.junk:SetPoint("TOPLEFT", 1, -1)
		btn.junk:Hide()
		btn.quest = holder:CreateTexture(nil, "OVERLAY")
		btn.quest:SetTexture([[Interface\GossipFrame\AvailableQuestIcon]])
		btn.quest:SetSize(14, 14)
		btn.quest:SetPoint("TOPRIGHT", -1, -1)
		btn.quest:Hide()
		btn.newGlow = holder:CreateTexture(nil, "OVERLAY")
		btn.newGlow:SetTexture(BLANK)
		btn.newGlow:SetVertexColor(S.accent.r, S.accent.g, S.accent.b, 0.25)
		S:SetInside(btn.newGlow, btn)
		btn.newGlow:Hide()
		-- own tooltip: the stock template path never resolves bag -1 (bank) or
		-- -2 (keyring) on this client. Install it BOTH as the OnEnter script and
		-- as the button's UpdateTooltip method so whichever code path handles the
		-- hover ends up in the same place.
		local function ShowItemTip(b)
			if not (b.bag and b.slot) then return end
			S.HoverEnter(b)
			GameTooltip:SetOwner(b, frame.isBank and "ANCHOR_RIGHT" or "ANCHOR_LEFT")
			local link = S.GetContainerItemLink and S.GetContainerItemLink(b.bag, b.slot)
			local info
			if not link then
				info = ItemInfo(b.bag, b.slot)
				link = info and (info.hyperlink or (info.itemID and ("item:" .. info.itemID)))
			end
			if link then
				GameTooltip:SetHyperlink(link)
			elseif info and info.itemID and GameTooltip.SetItemByID then
				GameTooltip:SetItemByID(info.itemID)
			end
			GameTooltip:Show()
			-- bag -1/-2 can throw inside C_NewItems on some builds; keep it last
			-- and protected so it can never kill the tooltip
			if C_NewItems and C_NewItems.RemoveNewItem then
				pcall(C_NewItems.RemoveNewItem, b.bag, b.slot)
				b.newGlow:Hide()
			end
		end
		btn:SetScript("OnEnter", ShowItemTip)
		btn.UpdateTooltip = ShowItemTip
		btn:SetScript("OnLeave", function(b)
			S.HoverLeave(b)
			GameTooltip:Hide()
		end)
	end
	btn:SetParent(bagFrame)
	return btn
end

local function IsEquipment(equipLoc, classID)
	return (equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_BAG" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" and equipLoc ~= "INVTYPE_AMMO" and equipLoc ~= "INVTYPE_QUIVER") or classID == 2 or classID == 4
end

function B:UpdateSlot(btn)
	local bag, slot = btn.bag, btn.slot
	local info = ItemInfo(bag, slot)
	local db = self.db
	local bd = btn.suiBackdrop
	btn.ilvl:SetText("")
	btn.bind:SetText("")
	btn.junk:Hide()
	btn.quest:Hide()
	btn.newGlow:Hide()
	-- tolerate both field name variants (iconFileID/hyperlink vs icon/link on older builds)
	local icon = info and (info.iconFileID or info.icon)
	if info and icon then
		if btn.icon then
			btn.icon:SetTexture(icon)
			-- Blizzard resets stock icon points/coords when container frames update
			btn.icon:ClearAllPoints()
			S:SetInside(btn.icon, btn, 1.5, 1.5)
			btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			btn.icon:Show()
		end
		local count = info.stackCount or info.stackCount2 or info.count or 1
		local ct = btn.count or btn.countText
		if ct then ct:SetText(count > 1 and (count > 9999 and "*" or count) or "") end
		btn.icon:SetDesaturated(info.isLocked and true or false)
		btn.hasItem = true
		btn.link = info.hyperlink or info.link
		local quality = info.quality
		local link = btn.link
		local _, _, _, itemLevel, _, _, _, _, equipLoc, _, sellPrice, classID, _, bindType = S.GetItemInfo(link or info.itemID or 0)
		if db.showBindType and info.isBound == false and (bindType == 2 or bindType == 3) then
			btn.bind:SetText(bindType == 2 and "BoE" or "BoU")
			btn.bind:SetTextColor(0.4, 0.8, 1)
		end
		if db.qualityBorders and quality and quality > 1 then
			local r, g, b = S.GetItemQualityColor(quality)
			bd:SetBackdropBorderColor(r, g, b)
		else
			bd:SetBackdropBorderColor(unpack(S.media.borderColor))
		end
		local isQuest, questID, isActive = GetQuestInfo(bag, slot)
		if db.questIcon and (isQuest or questID) then
			bd:SetBackdropBorderColor(1, 0.85, 0.1)
			btn.quest:SetTexture(questID and not isActive
				and [[Interface\GossipFrame\AvailableQuestIcon]]
				or [[Interface\GossipFrame\ActiveQuestIcon]])
			btn.quest:Show()
		end
		if db.junkIcon and quality == 0 and not info.hasNoValue and (sellPrice or 1) > 0 then btn.junk:Show() end
		if db.showItemLevel and link and IsEquipment(equipLoc, classID) and (quality or 0) >= (db.itemLevelThreshold or 1) then
			local ilvl = S.GetDetailedItemLevelInfo and S.GetDetailedItemLevelInfo(link) or itemLevel
			if ilvl and ilvl > 1 then
				btn.ilvl:SetText(ilvl)
				local r, g, b = S.GetItemQualityColor(quality or 1)
				btn.ilvl:SetTextColor(r, g, b)
			end
		end
		if db.newItemGlow and C_NewItems and C_NewItems.IsNewItem and C_NewItems.IsNewItem(bag, slot) then btn.newGlow:Show() end
		if self.searchText and self.searchText ~= "" then
			local name = S.GetItemInfo(link or info.itemID or 0)
			local match = name and name:lower():find(self.searchText, 1, true)
			btn:SetAlpha(match and 1 or 0.2)
		else
			btn:SetAlpha(1)
		end
		local ok, start, duration, enable = pcall(S.GetContainerItemCooldown, bag, slot)
		if btn.cooldown and ok and start then CooldownFrame_Set(btn.cooldown, start, duration, enable) end
	else
		if btn.icon then btn.icon:SetTexture(nil) btn.icon:Hide() end
		if btn.count then btn.count:SetText("") end
		if btn.countText then btn.countText:SetText("") end
		btn.hasItem = nil
		btn.link = nil
		bd:SetBackdropBorderColor(unpack(S.media.borderColor))
		btn:SetAlpha(self.searchText and self.searchText ~= "" and 0.2 or 1)
		if btn.cooldown then btn.cooldown:Hide() end
	end
	-- BetterItem integration: upgrade arrow + outfit mark on our own bag buttons
	if RLBetterItem and RLBetterItem.db then
		if RLBetterItem.db.showBagIcons then
			RLBetterItem:SetUpgradeIcon(btn, btn.link and RLBetterItem:IsBagUpgrade(btn.link))
		elseif btn.rlUpgradeIcon then
			btn.rlUpgradeIcon:Hide()
		end
		if RLBetterItem.db.outfitBagMarks and RLBetterItem.UpdateOutfitMark then
			RLBetterItem.UpdateOutfitMark(btn, btn.link)
		end
	end
end

-- Rendered slot count for a container; the keyring shows the occupied slots plus
-- one spare row so there is always room to drop a key onto
local function SlotCount(bag)
	if bag == S.KEYRING_CONTAINER then
		local n = KeyRingCapacity()
		if n <= 0 then return 0 end
		local last = 0
		for s = 1, n do if ItemInfo(bag, s) then last = s end end
		return max(last + 4, min(n, 12))
	end
	return S.GetContainerNumSlots(bag) or 0
end

-- Frames --------------------------------------------------------------------
function B:LayoutFrame(frame)
	local db = self.db
	local size = frame.isBank and db.bankSize or db.bagSize
	local columns = frame.isBank and db.bankColumns or db.bagColumns
	local spacing = db.spacing
	local index = 0
	local pad = 8
	local top = 34
	for _, bag in ipairs(frame.bags) do
		local bagFrame = frame.bagFrames[bag]
		local numSlots = SlotCount(bag)
		bagFrame.numSlots = numSlots
		if bag == S.KEYRING_CONTAINER and frame.keyringShown == false then
			for _, btn in ipairs(bagFrame.slots) do btn:Hide() end
			if frame.keyDivider then frame.keyDivider:Hide() end
		else
			if bag == S.KEYRING_CONTAINER and index > 0 then
				-- the keyring docks as its own separated block under the bag slots
				if index % columns ~= 0 then index = ceil(index / columns) * columns end
				index = index + columns -- one empty row as the gap
				if frame.keyDivider then
					frame.keyDivider:ClearAllPoints()
					frame.keyDivider:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -(top + (index / columns - 1) * (size + spacing) + 4))
					frame.keyDivider:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pad, -(top + (index / columns - 1) * (size + spacing) + 4))
					frame.keyDivider:Show()
				end
			elseif db.splitBags and index > 0 and index % columns ~= 0 then
				index = ceil(index / columns) * columns
			end
			for s = 1, numSlots do
				local slot = db.reverseSlots and (numSlots - s + 1) or s
				local btn = bagFrame.slots[slot] or self:CreateSlot(frame, bagFrame, bag, slot)
				if btn then
					bagFrame.slots[slot] = btn
					btn:SetSize(size, size)
					btn:ClearAllPoints()
					local col, row = index % columns, floor(index / columns)
					btn:SetPoint("TOPLEFT", frame, "TOPLEFT", pad + col * (size + spacing), -(top + row * (size + spacing)))
					btn:Show()
					index = index + 1
				end
			end
			for slot = numSlots + 1, #bagFrame.slots do bagFrame.slots[slot]:Hide() end
		end
	end
	local rows = max(1, ceil(index / columns))
	local barH = (frame.bagBar and frame.bagBar.slotSize) or db.bagSize
	local bottom = 30 + (frame.bagBarShown and (barH + 8) or 0)
	frame:SetSize(pad * 2 + columns * (size + spacing) - spacing, top + rows * (size + spacing) - spacing + bottom)
	frame.totalSlots = index
end

function B:UpdateFrame(frame)
	if not frame:IsShown() then frame.dirty = true return end
	frame.dirty = nil
	local needLayout = false
	for _, bag in ipairs(frame.bags) do
		local bf = frame.bagFrames[bag]
		-- also re-layout when slots are missing for the remembered count
		-- (a failed/interrupted layout used to poison numSlots permanently)
		if SlotCount(bag) ~= (bf.numSlots or -1) or (bf.numSlots or 0) > #bf.slots then needLayout = true end
	end
	if needLayout then self:LayoutFrame(frame) end
	for _, bag in ipairs(frame.bags) do
		local bf = frame.bagFrames[bag]
		for slot = 1, bf.numSlots or 0 do
			if bf.slots[slot] then self:UpdateSlot(bf.slots[slot]) end
		end
	end
	self:UpdateInfo(frame)
end

function B:UpdateBag(bag)
	for _, frame in pairs(self.frames) do
		local bf = frame.bagFrames[bag]
		if bf and frame:IsShown() then
			if SlotCount(bag) ~= (bf.numSlots or -1) then self:LayoutFrame(frame) end
			for slot = 1, bf.numSlots or 0 do
				if bf.slots[slot] then self:UpdateSlot(bf.slots[slot]) end
			end
		elseif bf then
			frame.dirty = true
		end
	end
end

function B:UpdateInfo(frame)
	local free, total = 0, 0
	for _, bag in ipairs(frame.bags) do
		if bag == S.KEYRING_CONTAINER then
			-- only count occupied keyring slots (capacity is fixed but meaningless)
			local n = KeyRingCapacity()
			for s = 1, n do if ItemInfo(bag, s) then total = total + 1 end end
		else
			local n = S.GetContainerNumSlots(bag) or 0
			local f = S.GetContainerNumFreeSlots(bag)
			total = total + n
			free = free + (f or 0)
		end
	end
	frame.slotsText:SetFormattedText("%d/%d", total - free, total)
	if frame.money then
		frame.money:SetText(S:FormatMoney(GetMoney(), self.db.moneyFormat))
		frame.money:SetShown(self.db.showGoldOnBag ~= false)
	end
	self:UpdateVendorControls(frame)
	if frame.bagBar and frame.bagBar:IsShown() then
		for _, b in ipairs(frame.bagBar.buttons) do
			S:SafeCall("Bags:BagBarBtn", self.UpdateBagBarButton, self, b)
		end
	end
end

local function CreateIconButton(parent, texture, tooltip, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(20, 20)
	S:CreateBackdrop(b, "Default", nil, 0)
	local t = b:CreateTexture(nil, "ARTWORK")
	t:SetTexture(texture)
	t:SetTexCoord(0.04, 0.96, 0.04, 0.96)
	S:SetInside(t, b, 2, 2)
	b.tex = t
	b:SetScript("OnClick", onClick)
	b:SetScript("OnEnter", function(self)
		S.HoverEnter(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(tooltip, 1, 1, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function(self) S.HoverLeave(self) GameTooltip:Hide() end)
	return b
end

function B:CreateFrame(isBank)
	local name = isBank and "SentinelUIBank" or "SentinelUIBags"
	local frame = CreateFrame("Frame", name, UIParent)
	frame.isBank = isBank
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
	frame:Hide()
	S:SetTemplate(frame, "Transparent", "TOP")
	tinsert(UISpecialFrames, name)

	frame.bags = BagList(isBank)
	frame.keyringShown = true
	if not isBank and S.KEYRING_CONTAINER then
		local kc = S.KEYRING_CONTAINER
		local en = IsKeyRingEnabled and IsKeyRingEnabled()
		local gs = GetKeyRingSize and GetKeyRingSize()
		local ls = GetContainerNumSlots and GetContainerNumSlots(kc)
		local ms = S.GetContainerNumSlots(kc)
		local inList = false
		for _, b in ipairs(frame.bags) do if b == kc then inList = true break end end
		S:LogInfo("bags", format("keyring: inBagList=%s enabled=%s keyRingSize=%s legacySlots=%s modernSlots=%s rendered=%d", tostring(inList), tostring(en), tostring(gs), tostring(ls), tostring(ms), inList and SlotCount(kc) or 0))
	end
	if not isBank then
		local div = frame:CreateTexture(nil, "BORDER")
		div:SetColorTexture(unpack(S.media.borderColor))
		div:SetHeight(1)
		div:Hide()
		frame.keyDivider = div
	end
	frame.bagFrames = {}
	for _, bag in ipairs(frame.bags) do
		local bf = CreateFrame("Frame", nil, frame)
		bf:SetID(bag)
		bf:SetAllPoints()
		bf.slots = {}
		frame.bagFrames[bag] = bf
	end

	local drag = CreateFrame("Frame", nil, frame)
	drag:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
	drag:SetHeight(32)
	frame.dragStrip = drag

	local title = S:FontString(frame, 14, "OUTLINE", S.media.font, nil, "LEFT")
	title:SetPoint("TOPLEFT", 10, -10)
	title:SetText(isBank and BANK or (S.myName .. " - " .. INVENTORY_TOOLTIP))
	S:RegisterAccent(title, "text")

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	S:SkinCloseButton(close)
	close:SetPoint("TOPRIGHT", -6, -6)
	frame.closeBtn = close
	close:SetScript("OnClick", function()
		if isBank then if CloseBankFrame then CloseBankFrame() end frame:Hide() else B:CloseBags() end
	end)

	frame.slotsText = S:FontString(frame, 12, "OUTLINE", S.media.numberFont, nil, "RIGHT")
	frame.slotsText:SetPoint("BOTTOMRIGHT", -10, 10)

	if not isBank then
		frame.money = S:FontString(frame, 12, "OUTLINE", S.media.numberFont, nil, "LEFT")
		frame.money:SetPoint("BOTTOMLEFT", 10, 10)
		local moneyHit = CreateFrame("Frame", nil, frame)
		moneyHit:SetAllPoints(frame.money)
		moneyHit:EnableMouse(true)
		moneyHit:SetScript("OnEnter", function(self) local dt = S:GetModule("DataTexts") if dt and dt.GoldTooltip then dt:GoldTooltip(self) end end)
		moneyHit:SetScript("OnLeave", GameTooltip_Hide)

		-- vendor controls: auto-sell toggle + quality picker, right in the footer
		local auto = CreateFrame("CheckButton", name .. "VendorAuto", frame, "UICheckButtonTemplate")
		auto:SetSize(18, 18)
		S:SkinCheckBox(auto)
		auto:SetPoint("LEFT", frame.money, "RIGHT", 14, 0)
		if auto.Text then
			auto.Text:SetFontObject(GameFontHighlightSmall)
			auto.Text:SetText(L["Auto-sell"])
		end
		auto:SetScript("OnClick", function(self)
			B.db.autoVendor = self:GetChecked() and true or false
			B:UpdateVendorControls(frame)
		end)
		auto:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(L["Auto-sell junk at merchants"], 1, 1, 1)
			GameTooltip:Show()
		end)
		auto:SetScript("OnLeave", GameTooltip_Hide)
		frame.vendorAuto = auto

		local qb = CreateFrame("Button", name .. "VendorQuality", frame)
		qb:SetSize(130, 16)
		qb:SetPoint("LEFT", auto.Text or auto, "RIGHT", auto.Text and 8 or 14, 0)
		qb.fs = S:FontString(qb, 11, "OUTLINE", nil, nil, "LEFT")
		qb.fs:SetAllPoints(qb)
		qb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		qb:SetScript("OnClick", function(_, btn)
			local q = B.db.vendorQuality or 0
			q = q + (btn == "RightButton" and -1 or 1)
			if q < 0 then q = B.MAX_VENDOR_QUALITY elseif q > B.MAX_VENDOR_QUALITY then q = 0 end
			B.db.vendorQuality = q
			B:UpdateVendorControls(frame)
		end)
		qb:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(L["Max quality to sell"], 1, 1, 1)
			GameTooltip:AddLine(L["Click: next quality |nRight-click: previous"], 0.7, 0.7, 0.7)
			GameTooltip:Show()
		end)
		qb:SetScript("OnLeave", GameTooltip_Hide)
		frame.vendorQuality = qb
	end

	local search = CreateFrame("EditBox", name .. "Search", frame, "SearchBoxTemplate")
	search:SetSize(150, 18)
	search:SetPoint("TOPRIGHT", close, "TOPLEFT", -90, -1)
	search:SetAutoFocus(false)
	S:SkinEditBox(search)
	search:HookScript("OnTextChanged", function(self)
		B.searchText = (self:GetText() or ""):lower()
		for _, f in pairs(B.frames) do if f:IsShown() then B:UpdateFrame(f) end end
	end)
	frame.search = search

	local sortBtn = CreateIconButton(frame, S.media.iconSort, L["Sort"], function()
		if isBank then B:SortBank() else B:SortBags() end
	end)
	sortBtn:SetPoint("TOPRIGHT", close, "TOPLEFT", -6, -1)
	frame.sortBtn = sortBtn

	if not isBank then
		local bagToggle = CreateIconButton(frame, S.media.iconBag, L["Toggle bag slots"], function()
			frame.bagBarShown = not frame.bagBarShown
			B:ShowBagBar(frame, frame.bagBarShown)
		end)
		bagToggle:SetPoint("RIGHT", sortBtn, "LEFT", -4, 0)
		local vendor = CreateIconButton(frame, S.media.iconVendor, L["Sell junk"], function() B:SellJunk(true) end)
		vendor:SetPoint("RIGHT", bagToggle, "LEFT", -4, 0)
		frame.vendorBtn = vendor
		search:ClearAllPoints()
		search:SetPoint("RIGHT", vendor, "LEFT", -8, 0)
	else
		search:ClearAllPoints()
		search:SetPoint("RIGHT", sortBtn, "LEFT", -8, 0)
		if PurchaseSlot or GetNumBankSlots then
			local buy = CreateIconButton(frame, S.media.iconBuy, L["Purchase bank slot"], function()
				local _, full = GetNumBankSlots and GetNumBankSlots() or 0
				if full then S:Print(L["All bank slots purchased."]) return end
				StaticPopup_Show("CONFIRM_BUY_BANK_SLOT")
			end)
			buy:SetPoint("BOTTOMLEFT", 10, 6)
			frame.buyBtn = buy
		end
	end

	frame:SetScript("OnShow", function(self) S:SafeCall("Bags:Show", B.UpdateFrame, B, self) end)
	frame:SetScript("OnHide", function(self)
		if B.db.clearSearchOnClose then self.search:SetText("") self.search:ClearFocus() end
		if isBank and CloseBankFrame then CloseBankFrame() end
	end)

	local holder = CreateFrame("Frame", name .. "Holder", UIParent)
	holder:SetSize(400, 300)
	if isBank then
		S:CreateMover(holder, "bank", L["Bank"], { "BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 6, 240 }, "bags")
		drag:SetPoint("RIGHT", frame.search, "LEFT", -6, 0)
	else
		S:CreateMover(holder, "bags", L["Bags"], { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -6, 240 }, "bags")
		drag:SetPoint("RIGHT", frame.search, "LEFT", -6, 0)
	end
	S:AttachMoverDrag(drag, isBank and "bank" or "bags")
	frame:SetPoint(isBank and "BOTTOMLEFT" or "BOTTOMRIGHT", holder, isBank and "BOTTOMLEFT" or "BOTTOMRIGHT")
	frame:HookScript("OnSizeChanged", function(_, w, h) holder:SetSize(w, h) end)

	self.frames[isBank and "bank" or "bags"] = frame
	-- the bank bag slot bar is core bank functionality (buy/equip vault slots),
	-- it stays even when the inventory bag bar is toggled off
	if isBank or self.db.showBagBar ~= false then
		frame.bagBarShown = true
		self:ShowBagBar(frame, true)
	end
	self:LayoutFrame(frame)
	return frame
end

function B:UpdateBagBarButton(b)
	if b.isBankSlot then
		-- slots beyond the purchased count are shown dimmed and buy the next
		-- slot when clicked (Blizzard always sells the next slot in order)
		local bought = GetNumBankSlots and GetNumBankSlots() or 0
		b.unpurchased = b.bagIndex > bought
		if b.unpurchased then
			b.icon:SetTexture([[Interface\PaperDoll\UI-PaperDoll-Slot-Bag]])
			b.icon:SetVertexColor(1, 0.3, 0.3)
			b.icon:SetDesaturated(true)
			b.count:SetText("")
			return
		end
		b.icon:SetVertexColor(1, 1, 1)
	end
	if b.isKeyring then
		-- occupied keyring slots out of the real keyring capacity
		local n = KeyRingCapacity()
		local used = 0
		for s = 1, n do if ItemInfo(S.KEYRING_CONTAINER, s) then used = used + 1 end end
		b.count:SetText(used > 0 and used or "")
		return
	end
	local tex = b.invID and GetInventoryItemTexture("player", b.invID)
	b.icon:SetTexture(tex or [[Interface\PaperDoll\UI-PaperDoll-Slot-Bag]])
	b.icon:SetDesaturated(not tex)
	if tex then
		local free = S.GetContainerNumFreeSlots(b.bagID or b.bagIndex) or 0
		b.count:SetText(free > 0 and free or "")
	else
		b.count:SetText("")
	end
end

function B:ShowBagBar(frame, show)
	local db = self.db
	local isBank = frame.isBank
	if not frame.bagBar then
		-- the bag/key strip is a compact row of small icons, not full item slots
		local barSize = math.floor(db.bagSize * 0.55 + 0.5)
		local bar = CreateFrame("Frame", nil, frame)
		bar.slotSize = barSize
		bar:SetPoint("BOTTOMLEFT", 8, 30)
		bar.buttons = {}
		local x = 0
		local function SlotButton(i)
			-- inv slots 20..23 hold bags 1..4 on classic; use the API when it exists
			local invID
			if isBank then
				-- bank bag slots live in their own inventory range (67+ on classic);
				-- the API name/signature differs between builds -> always guarded
				if BankButtonIDToInvSlotID then
					local ok, id = pcall(BankButtonIDToInvSlotID, i)
					if ok and type(id) == "number" then invID = id end
				end
				invID = invID or (66 + i)
			else
				invID = (S.ContainerIDToInventoryID and S.ContainerIDToInventoryID(i)) or (19 + i)
			end
			local b = CreateFrame("Button", frame:GetName() .. "BagBtn" .. i, bar)
			b:SetSize(barSize, barSize)
			b:SetPoint("LEFT", bar, "LEFT", x, 0)
			x = x + barSize + db.spacing
			-- container id differs from the button index on the bank bar
			-- (bank bags live at BANK_BAG_FIRST.., not 1..NUM_BANKBAGSLOTS)
			b.bagID = isBank and (S.BANK_BAG_FIRST + i - 1) or i
			b.invID, b.bagIndex, b.isBankSlot = invID, i, isBank or nil
			S:CreateBackdrop(b, "Default")
			b.icon = b:CreateTexture(nil, "ARTWORK")
			b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			S:SetInside(b.icon, b, 1, 1)
			b.count = S:FontString(b, 11, "OUTLINE", S.media.numberFont)
			b.count:SetPoint("BOTTOMRIGHT", -1, 2)
			b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			b:SetScript("OnClick", function()
				if b.unpurchased then
					StaticPopup_Show("CONFIRM_BUY_BANK_SLOT")
					return
				end
				if not b.invID then return end
				if CursorHasItem() then
					PutItemInBag(b.invID)
				elseif GetInventoryItemTexture("player", b.invID) then
					PickupBagFromSlot(b.invID)
				end
			end)
			b:SetScript("OnReceiveDrag", function()
				if b.invID and CursorHasItem() then PutItemInBag(b.invID) end
			end)
			b:SetScript("OnEnter", function(self)
				S.HoverEnter(self)
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				if self.unpurchased then
					GameTooltip:AddLine(L["Empty bag slot"], 1, 1, 1)
					local cost = GetBankSlotCost and GetBankSlotCost(self.bagIndex)
					if cost then
						GameTooltip:AddLine(format(L["Purchase this slot for %s"], S:FormatMoney(cost)), 0.9, 0.8, 0.3)
					end
					GameTooltip:AddLine(L["Click to purchase."], 0.7, 0.7, 0.7)
				elseif self.invID and GetInventoryItemTexture("player", self.invID) then
					GameTooltip:SetInventoryItem("player", self.invID)
				else
					GameTooltip:AddLine(L["Empty bag slot"], 1, 1, 1)
					GameTooltip:AddLine(L["Drag a bag here to equip it."], 0.7, 0.7, 0.7)
				end
				GameTooltip:Show()
			end)
			b:SetScript("OnLeave", function(self) S.HoverLeave(self) GameTooltip:Hide() end)
			bar.buttons[i] = b
		end
		local numSlots = isBank and S.NUM_BANKBAGSLOTS or S.NUM_BAG_SLOTS
		for i = 1, numSlots do
			local ok, err = pcall(SlotButton, i)
			if not ok then S:LogWarn("bags", "bag bar slot " .. i .. " failed: " .. tostring(err)) end
		end
		if not isBank and not S.isRetail then
			-- keyring indicator (keys render inside the combined view)
			local k = CreateFrame("Button", frame:GetName() .. "KeyBtn", bar)
			k:SetSize(barSize, barSize)
			k:SetPoint("LEFT", bar, "LEFT", x, 0)
			x = x + barSize + db.spacing
			S:CreateBackdrop(k, "Default")
			k.icon = k:CreateTexture(nil, "ARTWORK")
			k.icon:SetTexture([[Interface\Icons\INV_Misc_Key_13]])
			k.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			S:SetInside(k.icon, k, 1, 1)
			k.count = S:FontString(k, 11, "OUTLINE", S.media.numberFont)
			k.count:SetPoint("BOTTOMRIGHT", -1, 2)
			k.isKeyring = true
			k:SetScript("OnShow", function() B:UpdateBagBarButton(k) end)
			k:SetScript("OnClick", function()
				frame.keyringShown = not frame.keyringShown
				k.icon:SetDesaturated(not frame.keyringShown)
				B:LayoutFrame(frame)
			end)
			-- dropping a key on the button puts it into the keyring
			k:SetScript("OnReceiveDrag", function() if PutKeyInKeyRing then PutKeyInKeyRing() end end)
			k:SetScript("OnEnter", function(self)
				S.HoverEnter(self)
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				GameTooltip:AddLine(KEYRING or L["Keyring"], 1, 1, 1)
				GameTooltip:AddLine(L["Click to show/hide the keyring."], 0.7, 0.7, 0.7)
				GameTooltip:Show()
			end)
			k:SetScript("OnLeave", function(self) S.HoverLeave(self) GameTooltip:Hide() end)
			bar.buttons[#bar.buttons + 1] = k
		end
		bar:SetSize(max(1, x - db.spacing), barSize)
		frame.bagBar = bar
	end
	for _, b in ipairs(frame.bagBar.buttons) do
		S:SafeCall("Bags:BagBarBtn", self.UpdateBagBarButton, self, b)
	end
	frame.bagBar:SetShown(show)
	self:LayoutFrame(frame)
end

-- Open / close --------------------------------------------------------------
-- Blizzard toggle paths (B key = ToggleAllBags, backpack = ToggleBackpack,
-- bag buttons = ToggleBag) funnel through Open*/Close* globals internally.
-- Our Open/Close hooks then already synced the window - a same-tick Toggle
-- would instantly undo it, so Toggle* handlers are skipped while _bagSynced
-- is set (cleared next frame).
local function Synced(self)
	self._bagSynced = true
	C_Timer.After(0, function() self._bagSynced = nil end)
end

function B:OpenBags()
	Synced(self)
	local f = self.frames.bags
	if f and not f:IsShown() then f:Show() end
end

function B:CloseBags()
	Synced(self)
	local f = self.frames.bags
	if f then f:Hide() end
end

function B:ToggleBags()
	if self._bagSynced then return end
	local f = self.frames.bags
	if not f then return end
	if f:IsShown() then f:Hide() else f:Show() end
end

function B:HideBlizzard()
	-- only inventory containers are replaced by our window. Bank bag windows
	-- (container ids past NUM_BAG_SLOTS, opened from the native bank's bag
	-- slots) stay visible - the blizzard bank needs them for bag contents.
	local function Suppress(cf)
		if not cf or cf.suiContainerHook then return end
		cf.suiContainerHook = true
		local function OnShow(self)
			local id = self.GetID and self:GetID()
			if id and ((id >= 0 and id <= S.NUM_BAG_SLOTS) or id == S.KEYRING_CONTAINER) then
				self:Hide()
			elseif id then
				-- bank bag window: keep native behaviour, add the sentinel look
				S:SafeCall("Bags:SkinBankBag", S.SkinFrame, S, self, "Default")
			end
		end
		cf:HookScript("OnShow", OnShow)
		OnShow(cf)
	end
	for i = 1, (NUM_CONTAINER_FRAMES or 13) do Suppress(_G["ContainerFrame" .. i]) end
	-- some builds create container frames on demand
	if ContainerFrame_GenerateFrame then
		hooksecurefunc("ContainerFrame_GenerateFrame", function(frame)
			S:SafeCall("Bags:SuppressCF", Suppress, frame)
		end)
	end
	if ContainerFrameCombinedBags then ContainerFrameCombinedBags:SetParent(S.hiddenFrame) end
	-- the standalone keyring window is NOT one of the numbered container frames;
	-- our keyring block lives inside the inventory instead
	for _, n in ipairs({ "KeyRingContainer", "KeyRingContainerFrame", "KeyRingFrame", "KeyRing" }) do
		local kf = _G[n]
		if kf then kf:SetParent(S.hiddenFrame) end
	end
	-- catch lazily created / unknown-named keyring windows by title text
	local function HideKeyRingWindows()
		local f = EnumerateFrames()
		while f do
			if f ~= S.hiddenFrame and f.GetName and f.GetParent then
				local n = f:GetName()
				if n and (n:find("KeyRing") or n:find("Keyring")) and n ~= "KeyRingButton" and not (f.IsObjectType and f:IsObjectType("Button")) and f:GetParent() ~= S.hiddenFrame then
					f:SetParent(S.hiddenFrame)
				end
			end
			f = EnumerateFrames(f)
		end
	end
	S:SafeCall("Bags:HideKeyRing", HideKeyRingWindows)
	-- some builds open it on demand: hide again whenever it appears
	if ToggleKeyRing then
		hooksecurefunc("ToggleKeyRing", function()
			C_Timer.After(0, function() S:SafeCall("Bags:HideKeyRing", HideKeyRingWindows) end)
		end)
	end
end

-- Bank ----------------------------------------------------------------------
function B:BANKFRAME_OPENED()
	self:OpenBags()
	if not self.frames.bank then
		-- classic: the (skinned) blizzard bank is used - undo any stale hiding
		-- left by the old custom-frame code path
		if BankFrame then
			BankFrame:SetScale(1)
			BankFrame:SetAlpha(1)
			BankFrame:EnableMouse(true)
		end
		return
	end
	if BankFrame then
		BankFrame:SetScale(0.0001)
		BankFrame:SetAlpha(0)
		BankFrame:EnableMouse(false)
	end
	self.frames.bank:Show()
	-- bank contents stream in after the event on some builds; the first layout
	-- can run against zero slots and PLAYERBANKSLOTS_CHANGED is unreliable, so
	-- force a re-layout+refresh once the data has landed
	for _, delay in ipairs({ 0, 0.25, 0.75 }) do
		C_Timer.After(delay, function()
			local f = B.frames.bank
			if f and f:IsShown() then
				S:SafeCall("Bags:BankRefresh", function()
					B:LayoutFrame(f)
					B:UpdateFrame(f)
				end)
			end
		end)
	end
end

function B:BANKFRAME_CLOSED()
	if self.frames.bank then self.frames.bank:Hide() end
	if BankFrame then BankFrame:SetScale(1) BankFrame:SetAlpha(1) end
end

-- Junk selling --------------------------------------------------------------
local QUALITY_HEX = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000" }
local function QualityName(q)
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
	local name = _G["ITEM_QUALITY" .. q .. "_DESC"] or ("Quality " .. q)
	return ((c and c.hex) or ("|cff" .. (QUALITY_HEX[q] or "ffffff"))) .. name .. "|r"
end
B.QualityName = QualityName
B.MAX_VENDOR_QUALITY = 4

function B:UpdateVendorControls(frame)
	if not frame.vendorAuto then return end
	frame.vendorAuto:SetChecked(self.db.autoVendor ~= false)
	if frame.vendorQuality then
		frame.vendorQuality.fs:SetText(L["Max quality"] .. ": " .. QualityName(self.db.vendorQuality or 0))
	end
	if frame.vendorBtn then
		frame.vendorBtn.tex:SetDesaturated(self.db.autoVendor == false)
	end
end

function B:CanSellJunk(info)
	local q = info.quality or 0
	if q > (self.db.vendorQuality or 0) or info.hasNoValue or info.isLocked or not info.hyperlink then
		return false
	end
	-- BetterItem integration: never vendor items saved in an equipment outfit
	if RLBetterItem and RLBetterItem.db and RLBetterItem.db.protectOutfitItems and RLBetterItem.GetOutfitsForItemID then
		local id = GetItemInfoInstant and GetItemInfoInstant(info.hyperlink)
		if id and #RLBetterItem:GetOutfitsForItemID(id) > 0 then
			return false
		end
	end
	-- safety net: never vendor equippable BoE/BoU items that are still tradeable
	if q > 0 and self.db.vendorKeepBoe ~= false then
		local equipLoc = select(9, S.GetItemInfo(info.hyperlink))
		if equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" then
			local bindType = select(14, S.GetItemInfo(info.hyperlink))
			if (bindType == 2 or bindType == 3) and info.isBound ~= true then
				return false
			end
		end
	end
	return true
end

function B:SellJunk(manual)
	if not MerchantFrame or not MerchantFrame:IsShown() then
		if manual then S:Print(L["Open a merchant first."]) end
		return
	end
	if InCombatLockdown() then
		if manual then S:Print(ERR_NOT_IN_COMBAT) end
		return
	end
	local total, count, blocked = 0, 0, false
	for _, bag in ipairs(BagList(false)) do
		for slot = 1, S.GetContainerNumSlots(bag) or 0 do
			local info = ItemInfo(bag, slot)
			if info and B:CanSellJunk(info) then
				local price = select(11, S.GetItemInfo(info.hyperlink)) or 0
				if price > 0 then
					local ok = pcall(S.UseContainerItem, bag, slot)
					if ok then
						total = total + price * (info.stackCount or 1)
						count = count + 1
					else
						blocked = true
					end
					if count >= 12 or blocked then
						if count >= 12 then C_Timer.After(0.6, function() S:SafeCall("Bags:SellJunk", B.SellJunk, B, false) end) end
						if blocked then S:Print(L["Selling was blocked by the client."]) end
						if total > 0 then S:Print(format(L["Sold junk for %s"], S:FormatMoney(total))) end
						return
					end
				end
			end
		end
	end
	if total > 0 then
		S:Print(format(L["Sold junk for %s"], S:FormatMoney(total)))
	elseif manual then
		S:Print(L["Nothing to sell."])
	end
end

-- Sorting -------------------------------------------------------------------
-- sort pipeline: scan a virtual state, plan every move against it, then
-- execute one move per tick and verify the client actually applied each move.
local sorter = CreateFrame("Frame")
sorter:Hide()

local vID, vCount, vMax, vQuality, vLocked = {}, {}, {}, {}, {}
local moves, moveTracker = {}, {}
local moveRetries, lastMove, lastDest, lastItemID, lockStop, failStreak, lastFailReason = 0, nil, nil, nil, nil, 0, nil
local MOVE_WAIT, MAX_MOVE_TIME = 0.09, 1.25

local function Enc(bag, slot) return bag * 100 + slot end
local function Dec(v) return floor(v * 0.01), v % 100 end
local function EncMove(s, t) return s * 10000 + t end
local function DecMove(m)
	local s, t = floor(m * 0.0001), m % 10000
	if t > 9000 then s, t = s + 1, t - 10000 end
	return s, t
end

local function SlotItemID(bag, slot)
	local info = ItemInfo(bag, slot)
	if not info then return end
	if info.itemID then return info.itemID end
	return info.hyperlink and tonumber(strmatch(info.hyperlink, "item:(%d+)"))
end

local function ScanBags(bags)
	wipe(vID) wipe(vCount) wipe(vMax) wipe(vQuality) wipe(vLocked)
	for _, bag in ipairs(bags) do
		for slot = 1, S.GetContainerNumSlots(bag) or 0 do
			local id = SlotItemID(bag, slot)
			local enc = Enc(bag, slot)
			local info = ItemInfo(bag, slot)
			if info and info.isLocked then vLocked[enc] = true end
			if id then
				vID[enc], vCount[enc] = id, info.stackCount or 1
				vQuality[enc] = info.quality or 0
				vMax[enc] = select(8, S.GetItemInfo(info.hyperlink or id)) or 1
			end
		end
	end
end

-- apply a planned move to the virtual state (merge onto a partial stack or swap)
local function UpdateLocation(from, to)
	if vID[from] == vID[to] and vCount[to] < vMax[to] then
		local stackSize = vMax[to]
		if vCount[to] + vCount[from] > stackSize then
			vCount[from] = vCount[from] - (stackSize - vCount[to])
			vCount[to] = stackSize
		else
			vCount[to] = vCount[to] + vCount[from]
			vCount[from], vID[from], vQuality[from], vMax[from] = nil, nil, nil, nil
		end
	else
		vID[from], vID[to] = vID[to], vID[from]
		vQuality[from], vQuality[to] = vQuality[to], vQuality[from]
		vCount[from], vCount[to] = vCount[to], vCount[from]
		vMax[from], vMax[to] = vMax[to], vMax[from]
	end
end

local function AddMove(source, dest)
	UpdateLocation(source, dest)
	tinsert(moves, 1, EncMove(source, dest))
end

-- merge partial stacks of the same item (sources iterated backwards)
local function PlanStack(bags)
	local items, targets, used = {}, {}, {}
	for _, bag in ipairs(bags) do
		for slot = 1, S.GetContainerNumSlots(bag) or 0 do
			local enc = Enc(bag, slot)
			if vID[enc] and not vLocked[enc] and vCount[enc] ~= vMax[enc] then
				items[vID[enc]] = (items[vID[enc]] or 0) + 1
				tinsert(targets, enc)
			end
		end
	end
	for bi = #bags, 1, -1 do
		local bag = bags[bi]
		for slot = (S.GetContainerNumSlots(bag) or 0), 1, -1 do
			local src = Enc(bag, slot)
			local id = vID[src]
			if id and not vLocked[src] and items[id] and vCount[src] < vMax[src] then
				for i = #targets, 1, -1 do
					local t = targets[i]
					if vID[t] == id and t ~= src and vCount[t] < vMax[t] and not used[t] then
						AddMove(src, t)
						used[src] = true
						if vCount[t] == vMax[t] then items[id] = (items[id] > 1) and items[id] - 1 or nil end
						if not vCount[src] then items[id] = (items[id] or 0) > 1 and items[id] - 1 or nil break end
						if not items[id] then break end
					end
				end
			end
		end
	end
end

local function SortCompare(a, b)
	local aID, bID = vID[a], vID[b]
	if not aID or not bID then return not not aID end
	if aID == bID then
		if vCount[a] ~= vCount[b] then return vCount[a] < vCount[b] end
		return a < b
	end
	local aQ, bQ = vQuality[a] or 0, vQuality[b] or 0
	if aQ ~= bQ then return aQ > bQ end
	local aName, _, _, aLvl, _, _, _, _, _, _, aPrice, aClass, aSub = S.GetItemInfo(aID)
	local bName, _, _, bLvl, _, _, _, _, _, _, bPrice, bClass, bSub = S.GetItemInfo(bID)
	aClass, bClass = aClass or 99, bClass or 99
	if aClass ~= bClass then return aClass < bClass end
	aSub, bSub = aSub or 99, bSub or 99
	if aSub ~= bSub then return aSub < bSub end
	if (aLvl or 0) ~= (bLvl or 0) then return (aLvl or 0) > (bLvl or 0) end
	if (aPrice or 0) ~= (bPrice or 0) then return (aPrice or 0) > (bPrice or 0) end
	if aName and bName and aName ~= bName then return aName < bName end
	return aID < bID
end

local function ShouldMove(source, dest)
	local sourceID = source and vID[source]
	if not sourceID or dest == source then return end
	if sourceID == vID[dest] and vCount[source] == vCount[dest] then return end
	return true
end

local function UpdateSorted(sorted, source, dest)
	for i, s in pairs(sorted) do
		if s == source then sorted[i] = dest elseif s == dest then sorted[i] = source end
	end
end

local function PlanSort(bags, inverted)
	-- locked slots are immovable anchors: excluded from both the item list
	-- and the destination list, so the sort packs around them
	local sorted, dests = {}, {}
	for _, bag in ipairs(bags) do
		for slot = 1, S.GetContainerNumSlots(bag) or 0 do
			local enc = Enc(bag, slot)
			if vLocked[enc] then
				-- anchored: keeps its item and position
			elseif vID[enc] then
				tinsert(sorted, enc)
				tinsert(dests, enc)
			else
				tinsert(dests, enc)
			end
		end
	end
	sort(sorted, function(a, b)
		if inverted then a, b = b, a end
		return SortCompare(a, b) and true or false
	end)
	local locked = {}
	local passNeeded = true
	while passNeeded do
		passNeeded = false
		for i = 1, #sorted do
			local dest, source = dests[i], sorted[i]
			if ShouldMove(source, dest) then
				if not (locked[source] or locked[dest]) then
					AddMove(source, dest)
					UpdateSorted(sorted, source, dest)
					locked[source], locked[dest] = true, true
				else
					passNeeded = true
				end
			end
		end
		wipe(locked)
	end
end

local function StopSort(msg)
	wipe(moves) wipe(moveTracker)
	moveRetries, lastMove, lastDest, lastItemID, lockStop, failStreak, lastFailReason = 0, nil, nil, nil, nil, 0, nil
	sorter:Hide()
	S:LogInfo("sort", "stopped" .. (msg and (": " .. msg) or ""))
	if msg then S:Print(msg) end
	for _, f in pairs(B.frames) do if f:IsShown() then B:UpdateFrame(f) end end
end

-- execute one planned move against the real containers (returns ok, srcID, src, dstID, dst)
local function DoMove(move)
	if GetCursorInfo() == "item" then return false, nil, nil, nil, nil, nil, "cursor has item" end
	local s, t = DecMove(move)
	local sBag, sSlot = Dec(s)
	local tBag, tSlot = Dec(t)
	local sInfo, tInfo = ItemInfo(sBag, sSlot), ItemInfo(tBag, tSlot)
	if (sInfo and sInfo.isLocked) or (tInfo and tInfo.isLocked) then
		lastFailReason = format("locked bag=%d slot=%d -> bag=%d slot=%d (s=%s t=%s)", sBag, sSlot, tBag, tSlot, tostring(sInfo and sInfo.isLocked), tostring(tInfo and tInfo.isLocked))
		return false
	end
	local sID = sInfo and (sInfo.itemID or (sInfo.hyperlink and tonumber(strmatch(sInfo.hyperlink, "item:(%d+)"))))
	if not sID then
		if moveTracker[s] then return false end
		return StopSort(L["Confused.. Try Again!"])
	end
	local tID = tInfo and (tInfo.itemID or (tInfo.hyperlink and tonumber(strmatch(tInfo.hyperlink, "item:(%d+)"))))
	local maxStack = select(8, S.GetItemInfo(sID)) or 1
	local isMerge = sID == tID
	if isMerge and tInfo.stackCount ~= maxStack and (tInfo.stackCount + (sInfo.stackCount or 1)) > maxStack then
		-- overflow: only top the target stack off, the rest stays at the source
		S.SplitContainerItem(sBag, sSlot, maxStack - tInfo.stackCount)
	else
		S.PickupContainerItem(sBag, sSlot)
	end
	if GetCursorInfo() == "item" then S.PickupContainerItem(tBag, tSlot) end
	-- expected item at the source after the move: swaps keep the old target id,
	-- full merges leave it empty, partial merges keep the same id
	local srcExpected = tID
	if isMerge then
		srcExpected = ((tInfo.stackCount or 0) + (sInfo.stackCount or 1) > maxStack) and sID or nil
	end
	return true, sID, s, tID, t, srcExpected
end

sorter:SetScript("OnUpdate", function(self, elapsed)
	self.wait = (self.wait or 0) + elapsed
	if self.wait < MOVE_WAIT then return end
	self.wait = 0
	if InCombatLockdown() then return StopSort(ERR_NOT_IN_COMBAT) end

	local now = GetTime()
	local cursorType, cursorItemID = GetCursorInfo()
	if cursorType == "item" and cursorItemID then
		-- a previous drop did not land: retry placing it at the last target
		if lastItemID ~= cursorItemID or not lastDest then return StopSort(L["Confused.. Try Again!"]) end
		if moveRetries < 100 then
			local tBag, tSlot = Dec(lastDest)
			local tInfo = ItemInfo(tBag, tSlot)
			if not (tInfo and tInfo.isLocked) then
				S.PickupContainerItem(tBag, tSlot)
				lockStop = now
				moveRetries = moveRetries + 1
			end
		end
		return
	end

	if lockStop then
		-- verify pending moves actually landed; wait up to MAX_MOVE_TIME, then retry
		for slot, itemID in pairs(moveTracker) do
			if SlotItemID(Dec(slot)) ~= itemID then
				if (now - lockStop) > MAX_MOVE_TIME then
					if lastMove and moveRetries < 100 then
						local ok, sID, src, tID, tgt, srcExp = DoMove(lastMove)
						if not ok then lockStop = now moveRetries = moveRetries + 1 return end
						if srcExp then moveTracker[src] = srcExp else moveTracker[src] = nil end
						moveTracker[tgt] = sID
						lastDest, lastItemID = tgt, sID
						return
					end
					S:LogWarn("sort", "move verification timed out")
					return StopSort(L["Sorting was blocked by the client."])
				end
				return
			end
			moveTracker[slot] = nil
		end
	end

	lastItemID, lockStop, lastDest, lastMove = nil, nil, nil, nil
	wipe(moveTracker)

	for i = #moves, 1, -1 do
		local ok, sID, src, tID, tgt, srcExp = DoMove(moves[i])
		if not ok then
			lockStop = now
			failStreak = failStreak + 1
			if failStreak > 60 then
				S:LogWarn("sort", "move keeps failing, aborting: " .. (lastFailReason or "unknown"))
				return StopSort(L["Sorting was blocked by the client."])
			end
			return
		end
		failStreak = 0
		if srcExp then moveTracker[src] = srcExp else moveTracker[src] = nil end
		moveTracker[tgt] = sID
		lastDest, lastMove, lastItemID = tgt, moves[i], sID
		tremove(moves, i)
		if moves[i - 1] then return end
	end

	StopSort(L["Sorting finished."])
end)

function B:StartCustomSort(bags)
	if sorter:IsShown() then return end
	local sortBags = {}
	for _, bag in ipairs(bags) do
		local _, family = S.GetContainerNumFreeSlots(bag)
		-- inventory bags and the bank core get sorted; keyring and special bags never
		if (bag >= 0 or bag == S.BANK_CONTAINER) and (family or 0) == 0 then
			tinsert(sortBags, bag)
		end
	end
	ScanBags(sortBags)
	wipe(moves) wipe(moveTracker)
	moveRetries, lastMove, lastDest, lastItemID, lockStop = 0, nil, nil, nil, nil
	PlanStack(sortBags)
	PlanSort(sortBags, B.db.sortInverted)
	S:LogInfo("sort", format("planned %d moves across %d bags", #moves, #sortBags))
	if #moves == 0 then
		S:Print(L["Sorting finished."])
		return
	end
	sorter.wait = 0
	sorter:Show()
end


function B:SortBags()
	if InCombatLockdown() then S:Print(ERR_NOT_IN_COMBAT) return end
	-- always use our own sorter: Blizzard's SortBags on this client only touches
	-- a subset of containers and never merges partial stacks
	self:StartCustomSort(BagList(false))
end

function B:SortBank()
	if InCombatLockdown() then S:Print(ERR_NOT_IN_COMBAT) return end
	self:StartCustomSort(BagList(true))
end

-- Events --------------------------------------------------------------------
local function FlushPending()
	if not B.pendingBags then return end
	for bag in pairs(B.pendingBags) do B:UpdateBag(bag) end
	wipe(B.pendingBags)
	for _, f in pairs(B.frames) do if f:IsShown() then B:UpdateInfo(f) end end
end

function B:BAG_UPDATE(_, bag)
	self.pendingBags = self.pendingBags or {}
	self.pendingBags[bag] = true
	-- BAG_UPDATE_DELAYED does not fire on all clients; flush on a timer instead
	if not self.flushQueued then
		self.flushQueued = true
		C_Timer.After(0.05, function()
			B.flushQueued = nil
			S:SafeCall("Bags:Flush", FlushPending)
		end)
	end
end

function B:BAG_UPDATE_DELAYED()
	FlushPending()
end

function B:ITEM_LOCK_CHANGED(_, bag, slot)
	if not bag or not slot then return end
	for _, frame in pairs(self.frames) do
		local bf = frame.bagFrames[bag]
		if bf and bf.slots[slot] and frame:IsShown() then self:UpdateSlot(bf.slots[slot]) end
	end
end

function B:PLAYERBANKSLOTS_CHANGED()
	self:UpdateBag(S.BANK_CONTAINER)
end

function B:Update()
	for _, f in pairs(self.frames) do
		self:LayoutFrame(f)
		if f:IsShown() then self:UpdateFrame(f) end
	end
end

function B:Initialize()
	self:HideBlizzard()
	self:CreateFrame(false)
	-- the custom bank replacement is retail-only; on classic the (skinned)
	-- blizzard bank is used so vault slots / purchase / tooltips just work
	if self.private.bank and S.isRetail then self:CreateFrame(true) end

	self:SecureHook("OpenAllBags", "OpenBags")
	self:SecureHook("CloseAllBags", "CloseBags")
	if OpenBackpack then self:SecureHook("OpenBackpack", "OpenBags") end
	if CloseBackpack then self:SecureHook("CloseBackpack", "CloseBags") end
	if OpenBag then
		self:SecureHook("OpenBag", function(_, id)
			if not id or (id >= 0 and id <= S.NUM_BAG_SLOTS) then B:OpenBags() end
		end)
	end
	if CloseBag then
		self:SecureHook("CloseBag", function(_, id)
			if not id or (id >= 0 and id <= S.NUM_BAG_SLOTS) then B:CloseBags() end
		end)
	end
	-- Blizzard decides open/close from its own container frames - which we
	-- suppress, so its toggles would only ever open and never close. The
	-- combined window owns the real state: the toggle entry points are
	-- replaced by thin wrappers that flip on OUR window state.
	-- IMPORTANT: never call OpenBackpack/OpenAllBags/OpenBag/CloseBag from
	-- inside these overrides - Blizzard's C functions bounce back into the
	-- Lua globals (ContainerFrame_Shared calls ToggleBackpack internally)
	-- which caused a C stack overflow.
	local function BagsShown()
		local f = B.frames.bags
		return f and f:IsShown()
	end
	-- Blizzard's C OpenBackpack bounces back into the Lua ToggleBackpack
	-- global inside ContainerFrame code; without a guard that loops forever
	local flipping = false
	local function FlipBags()
		if flipping then return end
		flipping = true
		if BagsShown() then B:CloseBags() else B:OpenBags() end
		flipping = false
	end
	if ToggleAllBags then _G.ToggleAllBags = FlipBags end
	if ToggleBackpack then _G.ToggleBackpack = FlipBags end
	local origToggleBag = _G.ToggleBag
	if origToggleBag then
		_G.ToggleBag = function(id)
			-- bank bag clicks (ids past the inventory) keep native handling
			if id and (id < 0 or id > S.NUM_BAG_SLOTS) then return origToggleBag(id) end
			FlipBags()
		end
	end
	-- the blizzard keyring button/keybind calls ToggleKeyRing, which would open a
	-- hidden ContainerFrame. Route it to the keyring section inside our bags.
	if ToggleKeyRing then
		self:SecureHook("ToggleKeyRing", function()
			local f = B.frames.bags
			if not f then return end
			if not f:IsShown() then
				f.keyringShown = true
				f:Show()
			else
				f.keyringShown = not f.keyringShown
				B:LayoutFrame(f)
				B:UpdateFrame(f)
			end
		end)
	end

	self:RegisterEvent("BAG_UPDATE")
	self:RegisterEvent("BAG_UPDATE_DELAYED")
	self:RegisterEvent("ITEM_LOCK_CHANGED")
	self:RegisterEvent("BAG_UPDATE_COOLDOWN", function() for _, f in pairs(B.frames) do if f:IsShown() then B:UpdateFrame(f) end end end)
	self:RegisterEvent("PLAYER_MONEY", function() if B.frames.bags:IsShown() then B:UpdateInfo(B.frames.bags) end end)
	self:RegisterEvent("QUEST_ACCEPTED", function() for _, f in pairs(B.frames) do f.dirty = true if f:IsShown() then B:UpdateFrame(f) end end end)
	self:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
		if B.itemInfoTimer then return end
		B.itemInfoTimer = true
		C_Timer.After(0.3, function() B.itemInfoTimer = nil for _, f in pairs(B.frames) do if f:IsShown() then B:UpdateFrame(f) end end end)
	end)
	self:RegisterEvent("BANKFRAME_OPENED")
	self:RegisterEvent("BANKFRAME_CLOSED")
	if self.frames.bank then
		self:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
		self:RegisterEvent("PLAYERBANKBAGSLOTS_CHANGED", function() if B.frames.bank:IsShown() then B:LayoutFrame(B.frames.bank) B:UpdateFrame(B.frames.bank) end end)
	end
	self:RegisterEvent("MERCHANT_SHOW", function()
		B:OpenBags()
		B.merchantOpen = true
		-- merchant items can stream in after MERCHANT_SHOW; make sure the window
		-- is really up and repopulated already on the first interaction
		for _, delay in ipairs({ 0, 0.3 }) do
			C_Timer.After(delay, function()
				if not B.merchantOpen then return end
				local mf = _G.MerchantFrame
				if not mf then return end
				S:SafeCall("Bags:MerchantRefresh", function()
					if not mf:IsShown() then pcall(ShowUIPanel, mf) end
					if MerchantFrame_Update then MerchantFrame_Update() end
				end)
			end)
		end
		if B.db.autoVendor ~= false then C_Timer.After(0.2, function() S:SafeCall("Bags:SellJunk", B.SellJunk, B, false) end) end
	end)
	self:RegisterEvent("MERCHANT_CLOSED", function() B.merchantOpen = nil B:CloseBags() end)
	self:RegisterEvent("MAIL_SHOW", function() B:OpenBags() end)
	self:RegisterEvent("MAIL_CLOSED", function() B:CloseBags() end)
	self:RegisterEvent("TRADE_SHOW", function() B:OpenBags() end)
	self:RegisterEvent("AUCTION_HOUSE_SHOW", function() B:OpenBags() end)

	-- /suibank: dump the native bank + container state (classic path uses the
	-- skinned blizzard bank; bank bag contents open as container windows)
	S:RegisterChatCommand("suibank", function()
		local bf = _G.BankFrame
		S:Print("BankFrame:", bf and (bf:IsShown() and "shown" or "hidden") or "NIL",
			"scale:", bf and bf:GetScale(), "slots:", GetNumBankSlots and GetNumBankSlots())
		for i = 1, 7 do
			local b = _G["BankFrameBag" .. i] or _G["BankItemButtonBag" .. i]
			if b then
				local inv = BankButtonIDToInvSlotID and BankButtonIDToInvSlotID(i)
				local tex = inv and GetInventoryItemTexture("player", inv)
				S:Print("  BankBag" .. i, "shown:", b:IsShown(), "inv:", inv,
					"hasBag:", tex and "YES" or "no", "w:", floor((b:GetWidth() or 0) + 0.5))
			else
				S:Print("  BankBag" .. i, "= NIL")
			end
		end
		local n = 0
		while _G["BankFrameItem" .. (n + 1)] or _G["BankItem" .. (n + 1)] do n = n + 1 end
		S:Print("BankItems:", n, "generic:", NUM_BANKGENERIC_SLOTS)
		for i = 1, NUM_CONTAINER_FRAMES or 13 do
			local cf = _G["ContainerFrame" .. i]
			if cf then
				S:Print("  CF" .. i, "id:", cf:GetID(), "bag:", cf.bag or cf.bagID,
					"shown:", cf:IsShown(),
					"parent:", (cf:GetParent() and (cf:GetParent():GetName() or "unnamed")) or "nil")
			end
		end
	end)
end
