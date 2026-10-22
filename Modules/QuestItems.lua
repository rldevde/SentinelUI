-- QuestItems: clickable button bar for usable quest items in the bags.
-- Quest-class items (GetItemInfoInstant class 12) with a use effect get a
-- secure item button so they can be clicked straight from the bar.
local _, ns = ...
local S = ns.S
local L = S.L
local QI = S:NewModule("QuestItems", "questitems")

local SIZE, SPACING, MAX = 34, 4, 8
local f
local buttons = {}
local pending = false

local function ContainerInfo(bag, slot)
	if C_Container and C_Container.GetContainerItemInfo then
		local info = C_Container.GetContainerItemInfo(bag, slot)
		if info then return info.iconFileID, info.stackCount, info.itemID, info.hyperlink end
	else
		local icon, count, _, _, _, _, link = GetContainerItemInfo(bag, slot)
		if link then return icon, count, GetItemInfoInstant(link), link end
	end
end

local function Collect()
	local out, seen = {}, {}
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		local slots = C_Container and C_Container.GetContainerNumSlots(bag) or GetContainerNumSlots(bag)
		for slot = 1, slots or 0 do
			local icon, count, itemID, link = ContainerInfo(bag, slot)
			if itemID and not seen[itemID] then
				local _, _, _, _, _, classID = GetItemInfoInstant(itemID)
				local spell = GetItemSpell and GetItemSpell(itemID)
				local usable = C_Item and C_Item.IsUsableItem and C_Item.IsUsableItem(itemID) or IsUsableItem and IsUsableItem(itemID)
				if classID == 12 and spell and usable then
					seen[itemID] = true
					out[#out + 1] = { id = itemID, icon = icon, count = count or 1 }
				end
			end
		end
	end
	return out
end

local function NewButton(i)
	local btn = CreateFrame("Button", "SentinelUIQuestItem" .. i, f, "SecureActionButtonTemplate")
	btn:SetSize(SIZE, SIZE)
	btn:RegisterForClicks("AnyUp", "AnyDown")
	btn:SetAttribute("type", "item")
	btn.icon = btn:CreateTexture(nil, "BACKGROUND")
	btn.icon:SetAllPoints()
	S:SkinIcon(btn.icon, true, btn)
	btn.count = S:FontString(btn, 11, "OUTLINE", S.media.numberFont)
	btn.count:SetPoint("BOTTOMRIGHT", -1, 1)
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.itemID) end
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return btn
end

function QI:Rebuild()
	if not f then return end
	if InCombatLockdown() then pending = true return end
	pending = false
	local items = Collect()
	for i = 1, MAX do
		local btn = buttons[i] or NewButton(i)
		buttons[i] = btn
		local it = items[i]
		if it then
			btn.itemID = it.id
			btn:SetAttribute("item", "item:" .. it.id)
			btn.icon:SetTexture(it.icon)
			btn.count:SetText(it.count > 1 and it.count or "")
			btn:SetPoint("LEFT", f, "LEFT", (i - 1) * (SIZE + SPACING), 0)
			btn:Show()
		else
			btn:SetAttribute("item", nil)
			btn:Hide()
		end
	end
	local n = min(#items, MAX)
	f:SetSize(n > 0 and (n * SIZE + (n - 1) * SPACING) or SIZE, SIZE)
	f:SetShown(n > 0)
end

function QI:PLAYER_REGEN_ENABLED()
	if pending then self:Rebuild() end
end

function QI:Initialize()
	f = CreateFrame("Frame", "SentinelUIQuestItems", UIParent)
	f:SetSize(SIZE, SIZE)
	f:SetFrameStrata("LOW")
	S:CreateMover(f, "questItems", L["Quest Items"], { "TOPRIGHT", UIParent, "TOPRIGHT", -235, -260 }, "general")
	self:RegisterEvent("BAG_UPDATE", function() QI:Rebuild() end)
	self:RegisterEvent("BAG_UPDATE_DELAYED", function() QI:Rebuild() end)
	self:RegisterEvent("QUEST_LOG_UPDATE", function() QI:Rebuild() end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	self:Rebuild()
end
