-- FoodReminder: a soft "eat/drink" hint out of combat while the player's
-- mana pool is below the threshold and they are not already eating. Optional
-- bag check so the reminder only nags when supplies actually exist.
local _, ns = ...
local S = ns.S
local L = S.L
local FR = S:NewModule("FoodReminder", "foodreminder")

local CreateFrame = CreateFrame
local UnitPower, UnitPowerMax = UnitPower, UnitPowerMax
local UnitIsDeadOrGhost, InCombatLockdown = UnitIsDeadOrGhost, InCombatLockdown
local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local GetContainerNumSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
local GetContainerItemID = C_Container and C_Container.GetContainerItemID or GetContainerItemID
local GetItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant

-- food/drink aura names per locale (client globals where they exist)
local REST_NAMES = {}
for _, g in ipairs({ "DRINK", "FOOD", "REFRESHMENT" }) do
	local v = _G[g]
	if type(v) == "string" and v ~= "" then REST_NAMES[v:lower()] = true end
end
for _, v in ipairs({ "drink", "food", "refreshment", "trinken", "essen", "erfrischung",
	"boisson", "nourriture", "beber", "comer", "питье", "еда" }) do
	REST_NAMES[v] = true
end

local function IsResting()
	for i = 1, 40 do
		local a = S.GetAura and S.GetAura("player", i, "HELPFUL")
		if not a then break end
		if a.name and REST_NAMES[a.name:lower()] then return true end
	end
end

local function HasSupplies()
	if not (GetContainerNumSlots and GetContainerItemID and GetItemInfoInstant) then return true end
	for bag = 0, 4 do
		for slot = 1, (GetContainerNumSlots(bag) or 0) do
			local id = GetContainerItemID(bag, slot)
			if id then
				local _, _, _, _, _, classID, subID = GetItemInfoInstant(id)
				if classID == 0 and subID == 5 then return true end -- consumable > food & drink
			end
		end
	end
end

function FR:BuildFrame()
	if self.frame then return end
	local f = CreateFrame("Frame", "SentinelUIFoodReminder", UIParent)
	f:SetSize(46, 46)
	f:SetPoint("CENTER", UIParent, "CENTER", 210, -160)
	S:CreateBackdrop(f, "Default")
	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetAllPoints()
	f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	f.tex:SetTexture("Interface\\Icons\\Inv_Misc_Fork&Knife")
	f.cap = S:FontString(f, 9, "OUTLINE", S.media.unitFont)
	f.cap:SetPoint("TOP", f, "BOTTOM", 0, -2)
	f.cap:SetText(L["Eat / Drink"])
	f.cap:SetTextColor(1, 0.72, 0.25)
	f:SetScript("OnUpdate", function(self, el)
		self.t = (self.t or 0) + el
		self:SetAlpha(0.45 + 0.55 * math.abs(math.sin(self.t * 4)))
	end)
	f:SetAlpha(0)
	f:Hide()
	S:CreateMover(f, "foodReminder", L["Food Reminder"], { "CENTER", UIParent, "CENTER", 210, -160 }, "general")
	self.frame = f
end

function FR:Refresh()
	local f = self.frame
	if not f then return end
	local db = self.db
	local on = db.enable ~= false
		and not InCombatLockdown()
		and not UnitIsDeadOrGhost("player")
		and (UnitPowerMax("player", MANA) or 0) > 0
		and (UnitPower("player", MANA) / UnitPowerMax("player", MANA)) < (db.threshold or 0.4)
		and not IsResting()
		and (db.needsItem == false or HasSupplies())
	f:SetShown(on)
	if not on then f:SetAlpha(0) end
end

function FR:Initialize()
	self.db = S.db.profile.foodreminder
	self:BuildFrame()
	for _, ev in ipairs({ "UNIT_POWER_UPDATE", "UNIT_AURA", "BAG_UPDATE",
		"PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD" }) do
		self:RegisterEvent(ev, function(_, _, unit)
			if type(unit) ~= "string" or unit == "player" then FR:Refresh() end
		end)
	end
	self:Refresh()
end

function FR:Update()
	self.db = S.db.profile.foodreminder
	self:Refresh()
end
