-- Counters: class-relevant consumable/reagent counts as icon + number near
-- the player area. Warlock soul shards, hunter ammo, mage portal/teleport
-- runes and arcane powder, priest candles, paladin symbols, druid seeds,
-- shaman ankh. Turns red below a per-item low threshold.
local _, ns = ...
local S = ns.S
local L = S.L
local CT = S:NewModule("Counters", "counters")

local format = format
local CreateFrame = CreateFrame
local GetItemCount = GetItemCount or (C_Item and C_Item.GetItemCount)

-- itemId -> low threshold; per class list of what to watch
local ITEMS = {
	WARLOCK = { { 6265, 5 } },                                          -- Soul Shard
	HUNTER = { { "ammo", 200 } },                                       -- equipped ammo pouch slot
	MAGE = { { 17020, 20 }, { 17031, 3 }, { 17032, 3 } },               -- Arcane Powder, Teleport, Portal
	PRIEST = { { 17029, 20 }, { 44615, 20 }, { 17028, 20 } },           -- Sacred/Devout/Holy Candle
	PALADIN = { { 21177, 10 }, { 17033, 1 } },                          -- Symbol of Kings, Divinity
	DRUID = { { 22147, 20 }, { 17026, 20 }, { 17038, 2 } },             -- Quillvine, Thornroot, Ironwood
	SHAMAN = { { 17030, 1 } },                                          -- Ankh
}

local function Icon(id)
	if type(id) == "number" then
		if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
		local info = S.GetItemInfo and { S.GetItemInfo(id) }
		if info and info[10] then return info[10] end
	end
	return 134337 -- generic bullet pouch icon as fallback
end

local function Count(id)
	if id == "ammo" then
		local c = GetInventoryItemCount("player", 0)
		if (c or 0) == 0 then
			local ranged = GetInventoryItemLink("player", 18)
			local equipLoc = ranged and select(9, S.GetItemInfo(ranged))
			if equipLoc == "INVTYPE_THROWN" then c = GetInventoryItemCount("player", 18) end
		end
		return c or 0
	end
	return GetItemCount and (GetItemCount(id) or 0) or 0
end

function CT:BuildFrame()
	if self.frame then return end
	local f = CreateFrame("Frame", "SentinelUICounters", UIParent)
	f:SetSize(150, 24)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, -220)
	f:SetFrameStrata("LOW")
	f.slots = {}
	for i = 1, 4 do
		local s = CreateFrame("Frame", nil, f)
		s:SetSize(40, 24)
		s.icon = s:CreateTexture(nil, "ARTWORK")
		s.icon:SetSize(18, 18)
		s.icon:SetPoint("LEFT", 0, 0)
		s.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		s.text = S:FontString(s, 11, "OUTLINE", S.media.numberFont)
		s.text:SetPoint("LEFT", s.icon, "RIGHT", 2, 0)
		s:Hide()
		f.slots[i] = s
	end
	f:Hide()
	S:CreateMover(f, "Counters", L["Counters"], { "CENTER", UIParent, "CENTER", 0, -220 }, "counters")
	self.frame = f
end

function CT:Refresh()
	local list = ITEMS[S.myClass]
	if not list or self.db.enable == false then
		if self.frame then self.frame:Hide() end
		return
	end
	self:BuildFrame()
	local x, used = 0, 0
	for i, def in ipairs(list) do
		local slot = self.frame.slots[i]
		if slot then
			local id, low = def[1], def[2]
			local c = Count(id)
			if id ~= "ammo" and c <= 0 then
				slot:Hide()
			else
				slot.icon:SetTexture(Icon(id == "ammo" and 30611 or id))
				slot.text:SetText(c)
				slot.text:SetTextColor(c <= low and 1 or 0.85, c <= low and 0.25 or 0.85, c <= low and 0.25 or 0.85)
				slot:ClearAllPoints()
				slot:SetPoint("LEFT", self.frame, "LEFT", x, 0)
				slot:Show()
				x = x + slot:GetWidth()
				used = used + 1
			end
		end
	end
	if used > 0 then
		self.frame:SetWidth(math.max(x, 40))
		self.frame:Show()
	else
		self.frame:Hide()
	end
end

function CT:Initialize()
	self.db = S.db.profile.counters
	if not ITEMS[S.myClass] then return end
	self:BuildFrame()
	self:RegisterEvent("BAG_UPDATE", function() CT:Refresh() end)
	self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function() CT:Refresh() end)
	self:RegisterEvent("UNIT_INVENTORY_CHANGED", function(_, _, unit) if unit == "player" then CT:Refresh() end end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function() CT:Refresh() end)
	-- merchant reminder: tracked reagents running low -> chat note to restock,
	-- or buy up to the target amount when autoBuy is enabled
	self:RegisterEvent("MERCHANT_SHOW", function()
		for _, def in ipairs(ITEMS[S.myClass] or {}) do
			local id, low = def[1], def[2]
			if type(id) == "number" then
				local c = Count(id)
				if c <= low then
					local name, link = S.GetItemInfo and S.GetItemInfo(id)
					if not name and C_Item and C_Item.RequestLoadItemDataByID then
						C_Item.RequestLoadItemDataByID(id)
					end
					local label = link or ("|cffffffff|Hitem:" .. id .. "|h[item:" .. id .. "]|h|r")
					local bought = 0
					if CT.db.autoBuy and GetMerchantNumItems then
						local want = (def[3] or low * 2) - c
						for mi = 1, GetMerchantNumItems() do
							local link = GetMerchantItemLink and GetMerchantItemLink(mi)
							if link and tonumber(link:match("item:(%d+)")) == id then
								local stack = select(8, S.GetItemInfo(link)) or 20
								want = math.min(want, stack * 4)
								if want > 0 and BuyMerchantItem then
									BuyMerchantItem(mi, want)
									bought = want
								end
								break
							end
						end
					end
					if bought > 0 then
						S:Print(format(L["Bought %dx %s"], bought, label))
					elseif CT.db.restockNote ~= false then
						S:Print(format(L["Low on %s (%d) - restock at vendor"], label, c))
					end
				end
			end
		end
	end)
	self:Refresh()
end

function CT:Update()
	self.db = S.db.profile.counters
	self:Refresh()
end
