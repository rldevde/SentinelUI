local addon = RLBetterItem

-- ==================== STATS PANEL ====================
-- Small movable stats frame next to the character window (RLPalaTankHelper
-- style) that shows the stats that matter for the active scale.

local BOSS_LEVEL = 73
local BASE_DEFENSE = 350
local ARMOR_K = 467.5 * BOSS_LEVEL - 22167.5 -- TBC boss armor constant

local CR_HASTE_MELEE  = CR_HASTE_MELEE  or 18
local CR_HASTE_RANGED = CR_HASTE_RANGED or 19
local CR_HASTE_SPELL  = CR_HASTE_SPELL  or 20
local CR_ARMOR_PEN    = 25

-- classify the active scale into a panel layout
local function ScaleRole(scaleKey)
    local scale = addon:GetScale(scaleKey)
    local w = scale and scale.weights
    if not w then return "melee" end
    if (w.Healing or 0) >= 0.9 then return "healer" end
    if w.RangedAttackPower then return "hunter" end
    if (w.SpellHit or w.SpellCrit) and (w.SpellPower or 0) > 0 then return "caster" end
    if (w.Defense or 0) > 0 and (w.Stamina or 0) >= 0.9 then return "tank" end
    return "melee"
end

-- ---------- value helpers (all guarded) ----------
local function Rating(stat)
    return addon:GetPlayerRating(addon:GetActiveScaleKey(), stat) or 0
end
local function CRB(cr)
    return (GetCombatRatingBonus and GetCombatRatingBonus(cr)) or 0
end
local function DefenseSkill()
    if not UnitDefense then return 0 end
    local b, m = UnitDefense("player")
    return (b or 0) + (m or 0)
end
local function MeleeAP()
    if not UnitAttackPower then return 0 end
    local b, p, n = UnitAttackPower("player")
    return (b or 0) + (p or 0) + (n or 0)
end
local function RangedAP()
    if not UnitRangedAttackPower then return 0 end
    local b, p, n = UnitRangedAttackPower("player")
    return (b or 0) + (p or 0) + (n or 0)
end
local function BestSpellPower()
    if not GetSpellBonusDamage then return 0 end
    local best = 0
    for school = 2, 7 do
        local v = GetSpellBonusDamage(school) or 0
        if v > best then best = v end
    end
    return best
end
local function BestSpellCrit()
    if not GetSpellCritChance then return 0 end
    local best = 0
    for school = 2, 7 do
        local v = GetSpellCritChance(school) or 0
        if v > best then best = v end
    end
    return best
end
local function MP5()
    if not GetManaRegen then return 0 end
    local _, casting = GetManaRegen()
    return (casting or 0) * 5
end
local function Stat(i)
    local _, v = UnitStat("player", i)
    return v or 0
end

-- ---------- frame ----------
local panel
local MAX_ROWS = 14

local function CreatePanel()
    panel = CreateFrame("Frame", "RLBetterItemStatsPanel", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    panel:SetSize(190, 250)
    panel:SetFrameStrata("HIGH")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    panel:SetBackdropColor(0, 0, 0, 0.85)
    panel:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    panel:Hide()

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.title:SetPoint("TOPLEFT", 12, -12)
    panel.title:SetText("|cffffd100SentinelUI|r")

    panel.rows = {}
    for i = 1, MAX_ROWS do
        local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetJustifyH("LEFT")
        fs:SetPoint("TOPLEFT", 12, -34 - i * 14)
        panel.rows[i] = fs
    end

    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, relTo, relPoint, x, y = self:GetPoint()
        addon.db.panelPos = {
            point = point,
            relTo = relTo and relTo:GetName() or "UIParent",
            relPoint = relPoint, x = x, y = y,
        }
    end)

    panel:SetScript("OnEvent", function()
        if panel:IsShown() then addon:UpdateStatsPanel() end
    end)
    panel:RegisterEvent("UNIT_STATS")
    panel:RegisterEvent("UNIT_DEFENSE")
    panel:RegisterEvent("UNIT_RESISTANCES")
    panel:RegisterEvent("UNIT_AURA")
    panel:RegisterEvent("COMBAT_RATING_UPDATE")
    panel:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    panel:RegisterEvent("PLAYER_TALENT_UPDATE")
    panel:RegisterEvent("UPDATE_SHAPESHIFT_FORM")

    local elapsed = 0
    panel:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.5 then
            elapsed = 0
            addon:UpdateStatsPanel()
        end
    end)
end

local function RestorePosition()
    local p = addon.db.panelPos
    panel:ClearAllPoints()
    if p then
        local relTo = _G[p.relTo] or UIParent
        panel:SetPoint(p.point or "TOPLEFT", relTo, p.relPoint or "TOPRIGHT",
            p.x or -2, p.y or -50)
    else
        panel:SetPoint("TOPLEFT", CharacterFrame or UIParent, "TOPRIGHT", -2, -50)
    end
end

-- ---------- row rendering ----------
local function RowFmt(label, cur, cap, isPct, decimals)
    local v
    if isPct then
        v = string.format("%." .. (decimals or 2) .. "f%%", cur)
        cap = cap and string.format("%%.%df%%%%", decimals or 1):format(cap)
    else
        v = string.format("%d", math.floor(cur + 0.5))
        cap = cap and tostring(cap)
    end
    if cap then
        local ok = cur >= (tonumber(cap) or 0)
        local c = ok and "|cff00ff00" or "|cffff5050"
        return string.format("%s%s:|r %s%s / %s", c, label, c, v, cap)
    end
    return string.format("|cff00ff00%s:|r %s", label, v)
end

local function BuildRows()
    local key = addon:GetActiveScaleKey()
    if not key then return {} end
    local role = ScaleRole(key)
    local L = function(k) return addon:L(k) end
    local rows = {}

    local function CapRow(stat, label)
        local cap = addon:GetCap(key, stat)
        table.insert(rows, RowFmt(label, Rating(stat), cap))
    end

    if role == "tank" then
        local def = DefenseSkill()
        local dodge = (GetDodgeChance and GetDodgeChance()) or 0
        local parry = (GetParryChance and GetParryChance()) or 0
        local block = (GetBlockChance and GetBlockChance()) or 0
        local miss = 5 + (def - BASE_DEFENSE) * 0.04
        local avoid = miss + dodge + parry
        -- crit immunity: war/paladin need 5.6%, druid 2.6% (Survival of the Fittest)
        local critNeed = (select(2, UnitClass("player")) == "DRUID") and 2.6 or 5.6
        local critRed = (def - BASE_DEFENSE) * 0.04
        local uncrush = avoid + block

        table.insert(rows, RowFmt(L("PANEL_DEFENSE"), def, addon:GetCap(key, "Defense")))
        table.insert(rows, RowFmt(L("PANEL_DODGE"), dodge, nil, true))
        table.insert(rows, RowFmt(L("PANEL_PARRY"), parry, nil, true))
        table.insert(rows, RowFmt(L("PANEL_BLOCK"), block, nil, true))
        table.insert(rows, RowFmt(L("PANEL_MISS"), miss, nil, true))
        table.insert(rows, RowFmt(L("PANEL_AVOID"), avoid, nil, true))
        table.insert(rows, RowFmt(L("PANEL_CRITRED"), critRed, critNeed, true, 2))
        table.insert(rows, RowFmt(L("PANEL_UNCRUSH"), uncrush, 102.4, true, 1))
        local _, armor = UnitArmor("player")
        armor = armor or 0
        table.insert(rows, RowFmt(L("STAT_Armor"), armor))
        local dr = armor > 0 and armor / (armor + ARMOR_K) or 0
        table.insert(rows, RowFmt(L("PANEL_DR"), dr * 100, nil, true))
        local hp = UnitHealthMax("player") or 0
        local ehp = dr < 1 and math.floor(hp / (1 - dr)) or hp
        table.insert(rows, "|cffffff00" .. L("PANEL_EHP") .. ":|r " .. ehp .. "/" .. hp)
        CapRow("Hit", L("STAT_Hit"))
        CapRow("Expertise", L("STAT_Expertise"))

    elseif role == "hunter" then
        CapRow("Hit", L("STAT_Hit"))
        table.insert(rows, RowFmt(L("PANEL_RAP"), RangedAP()))
        table.insert(rows, RowFmt(L("PANEL_CRIT"),
            (GetRangedCritChance and GetRangedCritChance()) or 0, nil, true))
        table.insert(rows, RowFmt(L("STAT_Agility"), Stat(2)))
        table.insert(rows, RowFmt(L("PANEL_HASTE"), CRB(CR_HASTE_RANGED), nil, true))

    elseif role == "caster" then
        CapRow("SpellHit", L("STAT_SpellHit"))
        table.insert(rows, RowFmt(L("STAT_SpellPower"), BestSpellPower()))
        table.insert(rows, RowFmt(L("PANEL_SPELLCRIT"), BestSpellCrit(), nil, true))
        table.insert(rows, RowFmt(L("PANEL_SPELLHASTE"), CRB(CR_HASTE_SPELL), nil, true))
        table.insert(rows, RowFmt(L("STAT_MP5"), MP5()))
        table.insert(rows, RowFmt(L("STAT_Intellect"), Stat(4)))

    elseif role == "healer" then
        table.insert(rows, RowFmt(L("STAT_Healing"),
            (GetSpellBonusHealing and GetSpellBonusHealing()) or 0))
        table.insert(rows, RowFmt(L("STAT_MP5"), MP5()))
        table.insert(rows, RowFmt(L("PANEL_SPELLCRIT"), BestSpellCrit(), nil, true))
        table.insert(rows, RowFmt(L("STAT_Intellect"), Stat(4)))
        table.insert(rows, RowFmt(L("STAT_Spirit"), Stat(5)))
        table.insert(rows, RowFmt(L("PANEL_SPELLHASTE"), CRB(CR_HASTE_SPELL), nil, true))

    else -- melee
        CapRow("Hit", L("STAT_Hit"))
        CapRow("Expertise", L("STAT_Expertise"))
        table.insert(rows, RowFmt(L("PANEL_CRIT"),
            (GetCritChance and GetCritChance()) or 0, nil, true))
        table.insert(rows, RowFmt(L("PANEL_AP"), MeleeAP()))
        table.insert(rows, RowFmt(L("PANEL_HASTE"), CRB(CR_HASTE_MELEE), nil, true))
        local arp = (GetCombatRating and GetCombatRating(CR_ARMOR_PEN)) or 0
        if arp > 0 then
            table.insert(rows, RowFmt(L("STAT_ArmorPen"), arp))
        end
    end

    -- total gear score across all equipped items
    local total = 0
    for slot = 1, 18 do
        if slot ~= 4 then
            local link = GetInventoryItemLink("player", slot)
            if link then
                total = total + (addon:GetItemScore(link, key) or 0)
            end
        end
    end
    table.insert(rows, "|cffffd700" .. L("PANEL_TOTAL") .. ":|r " ..
        string.format("%.0f", total))

    return rows
end

function addon:UpdateStatsPanel()
    if not panel or not panel:IsShown() then return end
    local rows = BuildRows()
    for i = 1, MAX_ROWS do
        panel.rows[i]:SetText(rows[i] or "")
    end
    local h = 40 + math.max(#rows, 1) * 14 + 14
    panel:SetHeight(math.max(80, h))
end

function addon:UpdateStatsPanelVisibility()
    if not panel then return end
    if self.db and self.db.showStatPanel and CharacterFrame
        and CharacterFrame:IsShown() then
        if not panel:GetPoint() then RestorePosition() end
        panel:Show()
        self:UpdateStatsPanel()
    else
        panel:Hide()
    end
end

local hookedCharFrame = false
local function HookCharFrame()
    if hookedCharFrame or not CharacterFrame then return end
    hookedCharFrame = true
    CharacterFrame:HookScript("OnShow", function()
        addon:UpdateStatsPanelVisibility()
    end)
    CharacterFrame:HookScript("OnHide", function()
        if panel then panel:Hide() end
    end)
    if PaperDollFrame then
        PaperDollFrame:HookScript("OnShow", function()
            addon:UpdateStatsPanelVisibility()
        end)
    end
    if hooksecurefunc and CharacterFrame_ShowSubFrame then
        hooksecurefunc("CharacterFrame_ShowSubFrame", function()
            addon:UpdateStatsPanelVisibility()
        end)
    end
end

function addon:InitStatsPanel()
    if not self.db then return end
    if not panel then
        CreatePanel()
        RestorePosition()
    end
    HookCharFrame()

    -- character UI may be load-on-demand on some clients
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("ADDON_LOADED")
    watcher:SetScript("OnEvent", function(_, event, name)
        if name == "Blizzard_CharacterUI"
            or name == "Blizzard_UIPanels_Game" then
            HookCharFrame()
        end
    end)
end

-- deferred init: addon.db only exists after ADDON_LOADED
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(self)
    addon:InitStatsPanel()
    self:UnregisterAllEvents()
end)
