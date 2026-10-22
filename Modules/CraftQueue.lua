-- CraftQueue: "Mats" button on the tradeskill frame. Opens a list of the
-- selected recipe's reagents with have/need counts — missing materials turn
-- red so you know what to buy before you queue crafts.
local _, ns = ...
local S = ns.S
local L = S.L
local CQ = S:NewModule("CraftQueue", "craftqueue")

local CreateFrame = CreateFrame
local GetItemCount = GetItemCount or (C_Item and C_Item.GetItemCount)
local NUM_ROWS = 10

local function TradeAPI()
	if C_TradeSkillUI then
		return {
			selected = function() return C_TradeSkillUI.GetSelectedRecipeID and C_TradeSkillUI.GetSelectedRecipeID() end,
			reagents = function(id)
				local out = {}
				if C_TradeSkillUI.GetRecipeReagentInfo then
					local n = C_TradeSkillUI.GetRecipeNumReagents(id) or 0
					for i = 1, n do
						local name, _, count = C_TradeSkillUI.GetRecipeReagentInfo(id, i)
						local link = C_TradeSkillUI.GetRecipeReagentItemLink and C_TradeSkillUI.GetRecipeReagentItemLink(id, i)
						out[#out + 1] = { name = name, count = count or 1, link = link }
					end
				end
				return out
			end,
			product = function(id)
				return C_TradeSkillUI.GetRecipeItemLink and C_TradeSkillUI.GetRecipeItemLink(id),
					C_TradeSkillUI.GetRecipeNumItemsProduced and C_TradeSkillUI.GetRecipeNumItemsProduced(id) or 1
			end,
		}
	elseif GetTradeSkillSelectionIndex then
		return {
			selected = function() return GetTradeSkillSelectionIndex() end,
			reagents = function(idx)
				local out = {}
				local n = GetTradeSkillNumReagents(idx) or 0
				for i = 1, n do
					local name, _, count = GetTradeSkillReagentInfo(idx, i)
					local link = GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(idx, i)
					out[#out + 1] = { name = name, count = count or 1, link = link }
				end
				return out
			end,
			product = function(idx)
				return GetTradeSkillItemLink and GetTradeSkillItemLink(idx),
					GetTradeSkillNumMade and GetTradeSkillNumMade(idx) or 1
			end,
		}
	end
end

-- crafting cost line under the tradeskill frame: sums reagent prices from
-- the AH price DB against the product's price so margin is visible at a glance
local function ItemIDOf(link)
	if not link then return end
	if GetItemInfoInstant then return GetItemInfoInstant(link) end
	return tonumber(link:match("item:(%d+)"))
end

local function Gold(c)
	if S.FormatMoney then return S.FormatMoney(c) end
	return format("%dg %ds %dc", floor(c / 10000), floor(c / 100) % 100, c % 100)
end

function CQ:UpdateCost()
	local host = TradeSkillFrame or ProfessionsFrame
	if not host then return end
	if not self.costText then
		self.costText = S:FontString(host, 11, "OUTLINE", S.media.numberFont)
		self.costText:SetPoint("BOTTOM", host, "BOTTOM", -20, 12)
	end
	local f = self.costText
	local api = TradeAPI()
	local ah = S:GetModule("AuctionHouse")
	local idx = api and api.selected and api.selected()
	if not (self.db.showCost ~= false and host:IsShown() and idx and api.reagents and api.product
		and ah and ah.PriceFor) then f:Hide() return end
	local cost, missing = 0, 0
	for _, rg in ipairs(api.reagents(idx)) do
		local p = rg.link and ah:PriceFor(ItemIDOf(rg.link))
		if p then cost = cost + p * (rg.count or 1) else missing = missing + 1 end
	end
	local plink, made = api.product(idx)
	local sale = plink and ah:PriceFor(ItemIDOf(plink))
	if sale and (made or 1) > 1 then sale = sale * made end
	if cost == 0 and not sale then f:Hide() return end
	local txt = "|cff8ab4f8" .. (L["Mats"] or "Mats") .. ":|r " .. (cost > 0 and ("~" .. Gold(cost)) or "|cff777777?|r")
	if missing > 0 then txt = txt .. " |cff777777(" .. missing .. " ?)|r" end
	txt = txt .. "  |cff8ab4f8" .. (L["Sale"] or "Sale") .. ":|r " .. (sale and ("~" .. Gold(sale)) or "|cff777777?|r")
	if sale and cost > 0 then
		local diff = sale - cost
		txt = txt .. "  " .. (diff >= 0 and "|cff80ff80+" or "|cffff4040") .. Gold(abs(diff)) .. "|r"
	end
	f:SetText(txt)
	f:Show()
end

local WIN_W, ROW_H = 280, 22
function CQ:BuildFrame(anchor)
	if self.frame then return end
	local f = CreateFrame("Frame", "SentinelUICraftQueue", UIParent)
	tinsert(UISpecialFrames, "SentinelUICraftQueue")
	f:SetSize(WIN_W, 60 + NUM_ROWS * ROW_H)
	f:SetPoint("TOPLEFT", anchor or UIParent, "TOPRIGHT", 10, 0)
	f:SetFrameStrata("DIALOG")
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	S:CreateBackdrop(f, "Default")
	f.title = S:FontString(f, 12, "OUTLINE", S.media.unitFont)
	f.title:SetPoint("TOP", 0, -8)
	f.title:SetText(L["Materials needed"])
	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)
	if S.SkinCloseButton then S:SkinCloseButton(close) end
	f.rows = {}
	for i = 1, NUM_ROWS do
		local r = CreateFrame("Frame", nil, f)
		r:SetSize(WIN_W - 16, ROW_H)
		r:SetPoint("TOPLEFT", 8, -34 - (i - 1) * ROW_H)
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(16, 16)
		r.icon:SetPoint("LEFT", 0, 0)
		r.name = S:FontString(r, 10, nil, S.media.unitFont)
		r.name:SetPoint("LEFT", 20, 0)
		r.count = S:FontString(r, 10, "OUTLINE", S.media.numberFont)
		r.count:SetPoint("RIGHT", -4, 0)
		r:Hide()
		f.rows[i] = r
	end
	f:Hide()
	self.frame = f
end

function CQ:Fill(anchor)
	local api = TradeAPI()
	if not api then return false end
	local sel = api.selected()
	if not sel or sel == 0 then return false end
	self:BuildFrame(anchor)
	local reagents = api.reagents(sel)
	for i, row in ipairs(self.frame.rows) do
		local rg = reagents[i]
		if rg then
			local id = rg.link and tonumber(rg.link:match("item:(%d+)"))
			local have = id and GetItemCount and (GetItemCount(id) or 0) or 0
			local need = rg.count or 1
			row.icon:SetTexture(id and ((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or select(10, S.GetItemInfo(id))) or 134400)
			row.name:SetText(rg.name or "?")
			row.count:SetFormattedText("%d/%d", have, need)
			row.count:SetTextColor(have >= need and 0.4 or 1, have >= need and 0.9 or 0.3, 0.3)
			row:Show()
		else
			row:Hide()
		end
	end
	return true
end

function CQ:Toggle()
	local anchor = TradeSkillFrame or ProfessionsFrame or ProfessionsBookFrame
	if self.frame and self.frame:IsShown() then self.frame:Hide() return end
	if self:Fill(anchor) then self.frame:Show() else S:Print(L["Select a recipe first"]) end
end

function CQ:BuildButton()
	if self.btn then self.btn:SetShown(self.db.showButton ~= false) return end
	if self.db.showButton == false then return end
	local host = TradeSkillFrame or ProfessionsFrame
	if not host then return end
	local b = CreateFrame("Button", nil, host, "UIPanelButtonTemplate")
	b:SetSize(60, 20)
	b:SetPoint("TOPRIGHT", host, "TOPRIGHT", -40, -32)
	b:SetText(L["Mats"])
	S:SkinButton(b)
	b:SetScript("OnClick", function() CQ:Toggle() end)
	self.btn = b
end

function CQ:Initialize()
	self.db = S.db.profile.craftqueue
	if TradeSkillFrame or ProfessionsFrame then self:BuildButton() end
	self:RegisterEvent("TRADE_SKILL_SHOW", function() CQ:BuildButton() CQ:UpdateCost() end)
	self:RegisterEvent("TRADE_SKILL_UPDATE", function()
		if CQ.frame and CQ.frame:IsShown() then CQ:Fill() end
		CQ:UpdateCost()
	end)
	self:RegisterEvent("TRADE_SKILL_CLOSE", function() if CQ.costText then CQ.costText:Hide() end end)
end

function CQ:Update()
	self.db = S.db.profile.craftqueue
	if self.db.showButton == false then
		if self.btn then self.btn:Hide() end
	else
		self:BuildButton()
	end
	self:UpdateCost()
end
