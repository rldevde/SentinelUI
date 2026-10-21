RLBetterItem = {}
local addon = RLBetterItem
local _, ns = ...

-- reported version must match the newest standalone RLBetterItem release:
-- the Nearby radar broadcasts "Version:x.y.z" to other addon users, so a
-- lower number here makes standalone clients nag SentinelUI users as outdated.
-- Kept in sync via ## X-BetterItem-Version in SentinelUI.toc.
local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
addon.version = (getMeta and getMeta("SentinelUI", "X-BetterItem-Version"))
	or (getMeta and getMeta("SentinelUI", "Version")) or "0.0.0"
addon.player = UnitName("player")
addon.locale = GetLocale()

addon.initialized = false
addon.debugMode = false

function addon:Print(msg)
    print("|cffFFD700[SentinelUI]|r " .. tostring(msg))
end

function addon:Debug(msg)
    if self.debugMode then
        self:Print("|cff888888DEBUG:|r " .. tostring(msg))
    end
end

function addon:L(key)
    local locales = RLBetterItem_Locales
    if locales and locales[key] then
        return locales[key]
    end
    return key
end

local GetItemStats = GetItemStats or (C_Item and C_Item.GetItemStats)
addon.GetItemStats = GetItemStats

-- ==================== STAT KEY MAPPING ====================
-- Internal stat id -> possible GetItemStats keys (multiple variants for client compatibility)
addon.StatKeys = {
    Strength            = { "ITEM_MOD_STRENGTH_SHORT" },
    Agility             = { "ITEM_MOD_AGILITY_SHORT" },
    Stamina             = { "ITEM_MOD_STAMINA_SHORT" },
    Intellect           = { "ITEM_MOD_INTELLECT_SHORT" },
    Spirit              = { "ITEM_MOD_SPIRIT_SHORT" },
    AttackPower         = { "ITEM_MOD_ATTACK_POWER_SHORT" },
    RangedAttackPower   = { "ITEM_MOD_RANGED_ATTACK_POWER_SHORT" },
    FeralAttackPower    = { "ITEM_MOD_FERAL_ATTACK_POWER_SHORT" },
    SpellPower          = { "ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT" },
    Healing             = { "ITEM_MOD_SPELL_HEALING_DONE_SHORT", "ITEM_MOD_SPELL_HEALING_SHORT", "ITEM_MOD_HEALING_SHORT" },
    Hit                 = { "ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_HIT_MELEE_RATING_SHORT", "ITEM_MOD_HIT_RANGED_RATING_SHORT", "ITEM_MOD_CR_HIT_MELEE_SHORT", "ITEM_MOD_CR_HIT_RANGED_SHORT" },
    SpellHit            = { "ITEM_MOD_HIT_SPELL_RATING_SHORT", "ITEM_MOD_SPELL_HIT_RATING_SHORT", "ITEM_MOD_CR_HIT_SPELL_SHORT" },
    Crit                = { "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_CRIT_MELEE_RATING_SHORT", "ITEM_MOD_CRIT_RANGED_RATING_SHORT" },
    SpellCrit           = { "ITEM_MOD_CRIT_SPELL_RATING_SHORT", "ITEM_MOD_SPELL_CRIT_RATING_SHORT" },
    Haste               = { "ITEM_MOD_HASTE_RATING_SHORT", "ITEM_MOD_HASTE_MELEE_RATING_SHORT", "ITEM_MOD_HASTE_RANGED_RATING_SHORT" },
    SpellHaste          = { "ITEM_MOD_SPELL_HASTE_RATING_SHORT", "ITEM_MOD_HASTE_SPELL_RATING_SHORT" },
    ArmorPen            = { "ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT" },
    Expertise           = { "ITEM_MOD_EXPERTISE_RATING_SHORT" },
    Defense             = { "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT", "ITEM_MOD_DEFENSE_RATING_SHORT" },
    Dodge               = { "ITEM_MOD_DODGE_RATING_SHORT" },
    Parry               = { "ITEM_MOD_PARRY_RATING_SHORT" },
    BlockRating         = { "ITEM_MOD_BLOCK_RATING_SHORT" },
    BlockValue          = { "ITEM_MOD_BLOCK_VALUE_SHORT", "ITEM_MOD_BLOCK_VALUE_RATING_SHORT" },
    Resilience          = { "ITEM_MOD_RESILIENCE_RATING_SHORT", "ITEM_MOD_CRIT_TAKEN_RATING_SHORT" },
    SpellPen            = { "ITEM_MOD_SPELL_PENETRATION_SHORT" },
    MP5                 = { "ITEM_MOD_MANA_REGENERATION_SHORT", "ITEM_MOD_MANA_REGEN_SHORT", "ITEM_MOD_POWER_REGEN5_SHORT" },
    HP5                 = { "ITEM_MOD_HEALTH_REGENERATION_SHORT", "ITEM_MOD_HEALTH_REGEN_SHORT", "ITEM_MOD_POWER_REGEN0_SHORT" },
    Armor               = { "ITEM_MOD_ARMOR_SHORT", "ITEM_MOD_BONUS_ARMOR_SHORT" },
    WeaponDPS           = { "ITEM_MOD_DAMAGE_PER_SECOND_SHORT", "ITEM_MOD_WEAPON_DPS" },
}

-- Order used for the weights editor
addon.StatOrder = {
    "Strength", "Agility", "Stamina", "Intellect", "Spirit",
    "AttackPower", "RangedAttackPower", "FeralAttackPower",
    "SpellPower", "Healing",
    "Hit", "SpellHit", "Crit", "SpellCrit",
    "Haste", "SpellHaste", "ArmorPen", "Expertise",
    "Defense", "Dodge", "Parry", "BlockRating", "BlockValue",
    "Resilience", "SpellPen", "MP5", "HP5", "Armor", "WeaponDPS",
}

-- equip location -> inventory slot ids
addon.SlotMap = {
    INVTYPE_HEAD            = { 1 },
    INVTYPE_NECK            = { 2 },
    INVTYPE_SHOULDER        = { 3 },
    INVTYPE_BODY            = { 4 },
    INVTYPE_CHEST           = { 5 },
    INVTYPE_ROBE            = { 5 },
    INVTYPE_WAIST           = { 6 },
    INVTYPE_LEGS            = { 7 },
    INVTYPE_FEET            = { 8 },
    INVTYPE_WRIST           = { 9 },
    INVTYPE_HAND            = { 10 },
    INVTYPE_FINGER          = { 11, 12 },
    INVTYPE_TRINKET         = { 13, 14 },
    INVTYPE_CLOAK           = { 15 },
    INVTYPE_WEAPON          = { 16, 17 },
    INVTYPE_2HWEAPON        = { 16, 17 },
    INVTYPE_WEAPONMAINHAND  = { 16 },
    INVTYPE_WEAPONOFFHAND   = { 17 },
    INVTYPE_SHIELD          = { 17 },
    INVTYPE_HOLDABLE        = { 17 },
    INVTYPE_RANGED          = { 18 },
    INVTYPE_RANGEDRIGHT     = { 18 },
    INVTYPE_THROWN          = { 18 },
    INVTYPE_RELIC           = { 18 },
    INVTYPE_TABARD          = { 19 },
}

-- ==================== SCORE CALCULATION ====================
local function SumStats(stats, keys)
    local total = 0
    if stats then
        for _, k in ipairs(keys) do
            total = total + (stats[k] or 0)
        end
    end
    return total
end
addon.SumStats = SumStats

function addon:MergeStats(a, b)
    local out = {}
    if a then for k, v in pairs(a) do out[k] = v end end
    if b then for k, v in pairs(b) do out[k] = (out[k] or 0) + v end end
    return out
end

function addon:MaxWeight(scaleKey)
    local scale = self:GetScale(scaleKey)
    if not scale then return 1 end
    local best = 1
    for stat, w in pairs(scale.weights) do
        if stat ~= "WeaponDPS" and w > best then
            best = w
        end
    end
    return best
end

-- returns {InternalStat=amount, SocketRed=n, ...} or nil
-- uses GetItemStats, falls back to tooltip scanning (ScanStats in Tooltip.lua)
function addon:GetStatAmounts(link)
    if not link then return nil end
    if not self.statCache then self.statCache = {} end
    local cached = self.statCache[link]
    if cached ~= nil then
        return cached or nil
    end

    local out = {}
    if GetItemStats then
        local ok, stats = pcall(GetItemStats, link)
        if ok and stats then
            for stat, keys in pairs(self.StatKeys) do
                local amt = SumStats(stats, keys)
                if amt ~= 0 then out[stat] = amt end
            end
            local r = stats.EMPTY_SOCKET_RED    or 0
            local y = stats.EMPTY_SOCKET_YELLOW or 0
            local b = stats.EMPTY_SOCKET_BLUE   or 0
            local m = stats.EMPTY_SOCKET_META   or 0
            local a = stats.EMPTY_SOCKET or stats.EMPTY_SOCKET_NO_COLOR or 0
            if r > 0 then out.SocketRed = r end
            if y > 0 then out.SocketYellow = y end
            if b > 0 then out.SocketBlue = b end
            if m > 0 then out.SocketMeta = m end
            if a > 0 then out.SocketAny = a end
        end
    end

    -- fallback: tooltip text scan (works without GetItemStats).
    -- also runs when sockets are missing — some clients don't report EMPTY_SOCKET_*
    local needScan = next(out) == nil
    if not needScan and self.db and self.db.socketValue and self.ScanStats then
        local s = (out.SocketRed or 0) + (out.SocketYellow or 0) + (out.SocketBlue or 0)
                + (out.SocketMeta or 0) + (out.SocketAny or 0)
        needScan = (s == 0)
    end
    if needScan and self.ScanStats then
        local scanned = self:ScanStats(link)
        if scanned then
            for k, v in pairs(scanned) do
                if (out[k] or 0) == 0 then out[k] = v end
            end
        end
    end

    if next(out) == nil then out = false end
    self.statCache[link] = out
    return out or nil
end

-- returns score, internal stat amounts
-- replacedStats: internal stat amounts of the item(s) being replaced (for cap math)
function addon:GetItemScore(link, scaleKey, replacedStats)
    if not link or not scaleKey then return 0 end

    local amounts = self:GetStatAmounts(link)
    if not amounts then return 0 end

    local checkCaps = self.db and self.db.checkCaps and (GetCombatRating ~= nil)

    -- caps tracked in skill units instead of rating units
    -- (items always report rating; 1 defense skill ~= 2.365 rating)
    local CAP_TO_UNIT = { Defense = 1 / 2.365 }

    local score = 0
    for stat, _ in pairs(self.StatKeys) do
        local amount = amounts[stat] or 0
        if amount ~= 0 then
            local w = self:GetWeight(scaleKey, stat)
            if w ~= 0 then
                local eff = amount
                if checkCaps then
                    local cap = self:GetCap(scaleKey, stat)
                    if cap and cap > 0 then
                        local conv = CAP_TO_UNIT[stat] or 1
                        -- rating the player would have without the replaced item
                        local replacedAmt = ((replacedStats and replacedStats[stat]) or 0) * conv
                        local base = math.max(0, self:GetPlayerRating(scaleKey, stat) - replacedAmt)
                        eff = math.max(0, math.min(cap, base + amount * conv)
                            - math.min(cap, base)) / conv
                    end
                end
                score = score + eff * w
            end
        end
    end

    -- Socket value: count sockets, value each as a "best stat" gem
    local socketScore = 0
    if self.db and self.db.socketValue then
        local red    = amounts.SocketRed    or 0
        local yellow = amounts.SocketYellow or 0
        local blue   = amounts.SocketBlue   or 0
        local meta   = amounts.SocketMeta   or 0
        local any    = amounts.SocketAny    or 0

        if (red + yellow + blue + meta + any) > 0 then
            local bestW = self:MaxWeight(scaleKey)
            socketScore = (red + yellow + blue + any) * bestW * 8
                        + meta * bestW * 16
            score = score + socketScore
        end
    end

    -- flat trinket bonus: user-configured value for proc/on-use
    -- effects our stat math can't see. Applies to BOTH sides of a
    -- comparison, so trinket-vs-trinket stays fair
    local procVal = self.db and self.db.trinketProcValue or 0
    if procVal ~= 0 then
        local loc = GetItemInfo and select(9, GetItemInfo(link))
        if loc == "INVTYPE_TRINKET" then
            score = score + procVal
        end
    end

    return score, amounts, socketScore
end

function addon:GetEquippedScore(slotId, scaleKey)
    local link = GetInventoryItemLink("player", slotId)
    if not link then return 0, nil, nil end
    local stats = GetItemStats and GetItemStats(link)
    return self:GetItemScore(link, scaleKey, stats), link, stats
end
