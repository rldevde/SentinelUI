local addon = RLBetterItem

function addon:InitializeDB()
    local defaults = {
        scale = "auto",          -- "auto" or a scale key
        autoDetect = true,
        showScore = true,
        showUpgrade = true,
        showStatDiff = true,
        socketValue = true,
        checkCaps = true,
        showBagIcons = true,
        charSlotArrows = true,
        questMarkers = true,
        upgradeAlert = true,
        showMultiSpec = true,
        charSlotScores = false,
        lootRollHints = true,
        inspectScores = true,
        showStatPanel = true,
        outfits = {},
        outfitBarShow = true,
        outfitBarSel = {},       -- [outfitName] = false hides it from the bar (nil = shown)
        outfitTooltip = true,
        outfitBagMarks = true,
        protectOutfitItems = true,
        autoOutfit = false,
        autoOutfits = {},
        roleScales = {},
        charOutfitPanel = true,
        sellQuality = 0,
        sellButtonShow = false, -- sell button disabled in SentinelUI (auto-vendor covers it)
        upgradeAlertSound = true,
        -- player tooltips
        unitTooltips = true,
        ttClassColor = true,
        ttGuild = true,
        ttTarget = true,
        ttSpec = true,
        ttGearScore = true,
        ttPowerBar = false,
        ttPvPIcon = true,
        ttHideTitles = false,
        ttHideInCombat = false,
        ttInstantFade = false,
        ttMouseAnchor = false,
        charSlotILvl = true,
        charGearText = true,
        gearTextUnlock = false,
        gearTextPos = nil,
        enchantWarn = true,
        itemTipExtra = true,
        deValue = true,
        rollButtonColors = true,
        gemAdvisor = true,
        durabilityWarn = true,
        ammoCounter = true,
        inspectCompare = true,  -- % vs your gear on inspect slots
        charScaleBtn = true,    -- quick scale switch next to the char summary
        upgradeHistory = true,  -- session upgrade list in the Tools tab
        shoppingList = true,    -- missing enchants/gems list in the Tools tab
        sellLog = true,         -- per-item receipt after auto-sell
        setBonusWarn = true,    -- warn when a swap would break a set bonus
        wishlist = {},          -- itemIDs the user flagged as wanted
        charProfile = true,     -- remember scale/outfit per character
        charProfiles = {},      -- [charName-realm] = { scale=..., ... }
        trinketProcValue = 0,   -- flat score bonus for trinket procs/uses
        durabilityAlert = true, -- chat warning for low durability
        offspecWarn = true,     -- warn when equipping another outfit's item
        radar = true,           -- announce own version to other addon users
        versionNotify = true,   -- chat note when a newer version is seen
        outfitMatchBorders = true, -- green/red slot borders vs active outfit
        savedScales = {},
        errorLog = {},          -- captured Lua errors (see ErrorLog.lua)
        customWeights = {},
        customCaps = {},
        minimap = {
            angle = 0,
            hide = false,
        },
        ui = {
            width = 700,
            height = 620,
        },
    }

    if not RLBetterItemDB then
        RLBetterItemDB = {}
    end

    for key, value in pairs(defaults) do
        if RLBetterItemDB[key] == nil then
            RLBetterItemDB[key] = value
        end
    end

    -- one-time migration: the sell button is off in SentinelUI (auto-vendor
    -- covers selling); users who had it on keep it off unless re-enabled
    if not RLBetterItemDB._sellBtnMigrated then
        RLBetterItemDB._sellBtnMigrated = true
        RLBetterItemDB.sellButtonShow = false
    end

    -- one-time migration: only item level stays on char slots; score and
    -- durability overlays get switched off (numbers piled up on the icons).
    -- users can still re-enable them in the options
    if not RLBetterItemDB._charSlotsMig then
        RLBetterItemDB._charSlotsMig = true
        RLBetterItemDB.charSlotScores = false
        RLBetterItemDB.durabilityWarn = false
        RLBetterItemDB.inspectScores = false
    end

    self.db = RLBetterItemDB

    -- per-character profile: scale/outfit/sell-quality are stored per
    -- char so alts don't fight over the shared settings table
    self.charKey = (UnitName("player") or "?") .. "-" ..
        (GetRealmName() or "?")
    if self.db.charProfile then
        local p = self.db.charProfiles[self.charKey]
        if p then
            for _, k in ipairs({ "scale", "activeOutfit", "sellQuality" }) do
                if p[k] ~= nil then self.db[k] = p[k] end
            end
        end
    end

    if not self.db.autoDetect and self.db.scale == "auto" then
        self.db.scale = self:DetectScale() or self.db.scale
    end
end

-- fields that belong to the per-character profile
local PROFILE_KEYS = { "scale", "activeOutfit", "sellQuality" }

function addon:SaveCharProfile()
    if not self.db or not self.db.charProfile or not self.charKey then
        return
    end
    local p = {}
    for _, k in ipairs(PROFILE_KEYS) do
        p[k] = self.db[k]
    end
    self.db.charProfiles[self.charKey] = p
end

local pf = CreateFrame("Frame")
pf:RegisterEvent("PLAYER_LOGOUT")
pf:SetScript("OnEvent", function() addon:SaveCharProfile() end)
