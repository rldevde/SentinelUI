local addon = RLBetterItem

-- ==================== UPGRADE LOOT ALERT ====================
-- chat message when a newly looted item is an upgrade over equipped
-- gear; every detected upgrade also lands in the session history
-- (shown in the Tools tab)
local known = nil -- set of item links currently in bags; nil until first scan

addon.UpgradeHistory = {} -- newest first, max 20

local function RecordUpgrade(link, pct)
    table.insert(addon.UpgradeHistory, 1, { link = link, pct = pct, t = time() })
    while #addon.UpgradeHistory > 20 do
        table.remove(addon.UpgradeHistory)
    end
end

local function Snapshot()
    local current = {}
    addon:ForEachBagItemLink(function(link)
        current[link] = true
        if known and not known[link] and addon:IsBagUpgrade(link) then
            local score, baseline = addon:GetUpgradeInfo(link)
            local pct = (score and baseline and baseline > 0)
                and ((score - baseline) / baseline * 100) or nil
            if addon.db.upgradeHistory ~= false then
                RecordUpgrade(link, pct)
            end
            if addon.db.upgradeAlert then
                local extra = pct and (" |cff00ff00+" ..
                    string.format("%.1f", pct) .. "%|r") or ""
                addon:Print("|TInterface\\COMMON\\Indicator-Green:12|t " ..
                    addon:L("MSG_UPGRADE_LOOTED") .. ": " .. link .. extra)
                if addon.db.upgradeAlertSound and PlaySound then
                    PlaySound(8959) -- RAID_WARNING
                end
            end
        end
    end)
    known = current
end

local f = CreateFrame("Frame")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:SetScript("OnEvent", function()
    -- always snapshot: keeps the history current and the known-set
    -- fresh so toggling the chat alert later doesn't spam
    if not addon.initialized or not addon.db then return end
    Snapshot()
end)
