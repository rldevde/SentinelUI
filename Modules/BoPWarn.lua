-- BoPWarn: prints a reminder when a loot roll pops up for a
-- bind-on-pickup item, so a careless Need click does not soulbind it.
local _, ns = ...
local S = ns.S
local L = S.L
local BW = S:NewModule("BoPWarn", "bopwarn")

local format = format
local warned = {}

local function Check()
	-- the event's rollID argument is a secret value on this client and the
	-- API rejects it; the roll frames themselves carry a usable rollID
	for i = 1, (NUM_GROUP_LOOT_FRAMES or 4) do
		local f = _G["GroupLootFrame" .. i]
		if f and f:IsShown() and f.rollID and not warned[f.rollID] and GetLootRollItemInfo then
			local ok, _, _, _, _, bop = pcall(GetLootRollItemInfo, f.rollID)
			if ok and bop then
				warned[f.rollID] = true
				local link = GetLootRollItemLink and GetLootRollItemLink(f.rollID)
				S:Print("|cffffd040" .. format(L["Bind on pickup: %s"], link or "?") .. "|r")
			elseif ok then
				warned[f.rollID] = true -- seen, not BoP
			end
		end
	end
end

local BIND_DIALOGS = { LOOT_BIND = true, EQUIP_BIND = true, USE_BIND = true, AUTOEQUIP_BIND = true }

function BW:Initialize()
	self.db = S.db.profile.bopwarn
	self:RegisterEvent("START_LOOT_ROLL", function()
		if C_Timer and C_Timer.After then C_Timer.After(0.1, Check) else Check() end
	end)
	-- optional auto-confirm for bind dialogs (default OFF — it soulbinds items)
	hooksecurefunc("StaticPopup_Show", function(which)
		if not (BW.db and BW.db.autoConfirm and BIND_DIALOGS[which]) then return end
		for i = 1, 4 do
			local dlg = _G["StaticPopup" .. i]
			if dlg and dlg:IsShown() and dlg.which == which and dlg.button1 then
				dlg.button1:Click()
				return
			end
		end
	end)
end

function BW:Update()
	self.db = S.db.profile.bopwarn
end
