local addon = RLBetterItem

-- ASCII-only lowercase: string.lower is locale-dependent and can corrupt UTF-8
local function LowerASCII(s)
    return (string.gsub(s, "[A-Z]", function(c)
        return string.char(string.byte(c) + 32)
    end))
end

-- ==================== HIDDEN SCAN TOOLTIP ====================
-- Fallback parser: reads stats directly from the item tooltip text.
-- Used when GetItemStats is missing or returns nothing.
local scanTip = CreateFrame("GameTooltip", "RLBetterItemScanTooltip", nil, "GameTooltipTemplate")
scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")

local STAT_NAME_MAP = nil   -- localized stat name (lowercase) -> internal stat
local STAT_NAME_ORDER = nil -- names sorted longest-first

-- Ordered substring rules (first match wins) - covers equip lines whose
-- wording doesn't equal the ITEM_MOD_* names, plus spell-vs-melee disambiguation.
local SPECIAL_PATTERNS = {
    { "spell hit", "SpellHit" },       { "zaubertreffer", "SpellHit" },
    { "spell crit", "SpellCrit" },     { "kritische zaubertreffer", "SpellCrit" }, { "zauberkrit", "SpellCrit" },
    { "spell haste", "SpellHaste" },   { "zaubertempo", "SpellHaste" },
    { "spell penetration", "SpellPen" }, { "zauberdurchschlag", "SpellPen" },
    { "spell power", "SpellPower" },   { "zaubermacht", "SpellPower" },
    { "damage and healing", "SpellPower" }, { "schaden und heilung", "SpellPower" },
    { "ranged attack power", "RangedAttackPower" }, { "distanzangriffskraft", "RangedAttackPower" },
    { "feral attack power", "FeralAttackPower" },
    { "in cat, bear", "FeralAttackPower" }, { "katzen-, bären", "FeralAttackPower" }, { "tiergestalt", "FeralAttackPower" },
    { "block rating", "BlockRating" }, { "blockwertung", "BlockRating" },
    { "block value", "BlockValue" },   { "blockwert", "BlockValue" },
    { "armor penetration", "ArmorPen" }, { "rüstungsdurchschlag", "ArmorPen" },
    { "damage per second", "WeaponDPS" }, { "schaden pro sekunde", "WeaponDPS" },
    { "mana per 5", "MP5" },           { "mana alle 5", "MP5" },
    { "health per 5", "HP5" },         { "gesundheit alle 5", "HP5" },
    { "healing done by", "Healing" },  { "heilung", "Healing" },
    { "resilience", "Resilience" },    { "abhärtung", "Resilience" },
    { "expertise", "Expertise" },      { "waffenkunde", "Expertise" },
    { "defense", "Defense" },          { "verteidigung", "Defense" },
    { "dodge", "Dodge" },              { "ausweich", "Dodge" },
    { "parry", "Parry" },              { "parier", "Parry" },
    { "attack power", "AttackPower" }, { "angriffskraft", "AttackPower" },
    { "haste rating", "Haste" },       { "tempowertung", "Haste" },
    { "crit", "Crit" },                { "krit", "Crit" },
    { "hit rating", "Hit" },           { "trefferwertung", "Hit" },
    { "strength", "Strength" },        { "stärke", "Strength" },
    { "agility", "Agility" },          { "beweglichkeit", "Agility" },
    { "stamina", "Stamina" },          { "ausdauer", "Stamina" },
    { "intellect", "Intellect" },      { "intelligenz", "Intellect" },
    { "spirit", "Spirit" },            { "willenskraft", "Spirit" },
}

-- lines that must NOT be parsed as stats
local SKIP_LINE_PATTERNS = {
    "bonus",          -- "Socket Bonus: +4 Strength"
    "sockelbonus",
    "chance",         -- proc lines
    "auslös",
    "use:",           -- "Use:" effects
    "benutzen",
    "made by",        -- crafted-by lines
}

local function BuildStatNameMap()
    if STAT_NAME_ORDER then return end
    local map, order = {}, {}
    for stat, keys in pairs(addon.StatKeys) do
        for _, k in ipairs(keys) do
            local g = _G[k]
            if type(g) == "string" and #g > 0 then
                local lower = LowerASCII(g)
                if not map[lower] then
                    map[lower] = stat
                    table.insert(order, lower)
                end
            end
        end
    end
    table.sort(order, function(a, b) return #a > #b end)
    STAT_NAME_MAP = map
    STAT_NAME_ORDER = order
end

local function IsSocketLine(lower)
    return string.find(lower, "socket") or string.find(lower, "sockel") or string.find(lower, "fassung")
end

-- "1,234" (en) / "1.234" (de) = thousands; "41.8" (en) / "41,8" (de) = decimal
local function CleanNumber(s)
    if addon.locale == "deDE" then
        s = string.gsub(s, "%.", "")
        s = string.gsub(s, ",", ".")
    else
        s = string.gsub(s, ",", "")
    end
    return tonumber(s)
end

-- localized stat name lookup for a free-text line (shared by the
-- socket-bonus evaluator); returns the internal stat key or nil
local function StatFromText(t)
    BuildStatNameMap()
    local lower = LowerASCII(t)
    for _, sp in ipairs(SPECIAL_PATTERNS) do
        if string.find(lower, sp[1], 1, true) then return sp[2] end
    end
    for _, nm in ipairs(STAT_NAME_ORDER) do
        if string.find(lower, nm, 1, true) then
            return STAT_NAME_MAP[nm]
        end
    end
    return nil
end

-- "+4 Intellect" / "+4 Intelligenz" -> amount, stat
local function ParseBonusStat(text)
    local stat = StatFromText(text)
    local nums = {}
    for nn in string.gmatch(text, "%d[%d%.,]*") do
        table.insert(nums, CleanNumber(nn) or 0)
    end
    local amount = nums[#nums]
    if stat == "MP5" or stat == "HP5" then amount = nums[1] end
    return amount, stat
end

function addon:ScanStats(link)
    BuildStatNameMap()

    scanTip:ClearLines()
    -- malformed/uncached links can throw inside SetHyperlink
    local ok = pcall(function() scanTip:SetHyperlink(link) end)
    if not ok then return nil end
    local numLines = scanTip:NumLines() or 0

    local armorWord = (self.locale == "deDE") and "rüstung" or "armor"
    local out = {}

    for i = 1, numLines do
        local fs = _G["RLBetterItemScanTooltipTextLeft" .. i]
        local text = fs and fs:GetText()
        if text then
            local lower = LowerASCII(text)

            local skip = false
            for _, p in ipairs(SKIP_LINE_PATTERNS) do
                if string.find(lower, p, 1, true) then skip = true break end
            end

            if not skip then
                if IsSocketLine(lower) then
                    if string.find(lower, "meta") then
                        out.SocketMeta = (out.SocketMeta or 0) + 1
                    elseif string.find(lower, "red") or string.find(lower, "rot") then
                        out.SocketRed = (out.SocketRed or 0) + 1
                    elseif string.find(lower, "yellow") or string.find(lower, "gelb") then
                        out.SocketYellow = (out.SocketYellow or 0) + 1
                    elseif string.find(lower, "blue") or string.find(lower, "blau") then
                        out.SocketBlue = (out.SocketBlue or 0) + 1
                    else
                        out.SocketAny = (out.SocketAny or 0) + 1
                    end
                else
                    -- base armor line: "<number> Armor/Rüstung"
                    local num, rest = string.match(text, "^([%d%.,]+)%s+(.+)$")
                    if num and rest and string.find(LowerASCII(rest), armorWord, 1, true) then
                        out.Armor = CleanNumber(num) or 0
                    else
                        -- which stat does this line talk about?
                        local stat
                        for _, sp in ipairs(SPECIAL_PATTERNS) do
                            if string.find(lower, sp[1], 1, true) then
                                stat = sp[2]
                                break
                            end
                        end
                        if not stat then
                            for _, name in ipairs(STAT_NAME_ORDER) do
                                if string.find(lower, name, 1, true) then
                                    stat = STAT_NAME_MAP[name]
                                    break
                                end
                            end
                        end
                        if stat then
                            -- amount: last number in the line (ratings end with "by X."/"um X."),
                            -- except regen stats where the first number is the amount
                            local nums = {}
                            for nn in string.gmatch(text, "%d[%d%.,]*") do
                                table.insert(nums, CleanNumber(nn) or 0)
                            end
                            local amount = nums[#nums]
                            if stat == "MP5" or stat == "HP5" then
                                amount = nums[1]
                            end
                            if amount and amount > 0 then
                                out[stat] = (out[stat] or 0) + amount
                            end
                        end
                    end
                end
            end
        end
    end

    if next(out) == nil then return nil end
    return out
end

-- ==================== TOOLTIP COMPARISON ====================
local function ItemName(link)
    if not link then return "?" end
    local name, _, quality = GetItemInfo(link)
    if not name then return link end
    local hex = "ffffffff"
    if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
        hex = ITEM_QUALITY_COLORS[quality].hex or hex
    end
    return hex .. name .. "|r"
end

-- ==================== ICONS ====================
local function Tex(path, size)
    return "|T" .. path .. ":" .. (size or 13) .. "|t"
end

local ICON_UP   = "Interface\\COMMON\\Indicator-Green"
local ICON_DOWN = "Interface\\COMMON\\Indicator-Red"
local ICON_SAME = "Interface\\COMMON\\Indicator-Gray"
local ICON_SOCKET = "Interface\\ItemSocketingFrame\\UI-EmptySocket"
local ICON_BRAND  = "Interface\\Icons\\INV_Sword_27"

local function ItemIcon(link)
    if GetItemInfoInstant and link then
        local icon = select(5, GetItemInfoInstant(link))
        if icon then return Tex(icon) .. " " end
    end
    return ""
end

local function GetEquippedItemID(slotId)
    if GetInventoryItemID then
        return GetInventoryItemID("player", slotId)
    end
    local link = GetInventoryItemLink("player", slotId)
    return link and tonumber(string.match(link, "item:(%d+)")) or nil
end

local function GetEquipLoc(link)
    if GetItemInfoInstant then
        local _, _, _, loc = GetItemInfoInstant(link)
        return loc
    end
    local _, _, _, _, _, _, _, _, loc = GetItemInfo(link)
    return loc
end

local function GetSlotStats(slotId)
    local link = GetInventoryItemLink("player", slotId)
    if not link then return nil, link end
    return addon:GetStatAmounts(link), link
end

local function IsEquipped2H()
    local mh = GetInventoryItemLink("player", 16)
    if not mh then return false end
    local _, _, _, _, _, _, _, _, mhLoc = GetItemInfo(mh)
    return mhLoc == "INVTYPE_2HWEAPON"
end

-- ==================== STAT DIFF ====================
-- localized display name for an internal stat (from ITEM_MOD_* globals)
local STAT_NAME_CACHE = {}
local function StatName(stat)
    local n = STAT_NAME_CACHE[stat]
    if n then return n end
    n = stat
    local keys = addon.StatKeys[stat]
    if keys then
        for _, k in ipairs(keys) do
            local g = _G[k]
            if type(g) == "string" and #g > 0 then n = g break end
        end
    end
    STAT_NAME_CACHE[stat] = n
    return n
end
addon.StatName = StatName -- used by slash commands (caps/weakest output)

local function SocketCount(t)
    if not t then return 0 end
    return (t.SocketRed or 0) + (t.SocketYellow or 0) + (t.SocketBlue or 0)
         + (t.SocketMeta or 0) + (t.SocketAny or 0)
end

-- ==================== DISENCHANT PREVIEW ============================
-- TBC disenchant outcomes; material names resolved via GetItemInfo so
-- they come out localized for free
local function MatName(itemID)
    return (GetItemInfo and GetItemInfo(itemID)) or ("#" .. itemID)
end

local function DisenchantResult(quality, ilvl, isWeapon)
    if quality == 2 then
        -- uncommon: weapons give essences, armor gives dust
        if ilvl >= 65 then
            return isWeapon and ("1-2× " .. MatName(22446))
                or ("2-3× " .. MatName(22445))
        elseif ilvl >= 56 then
            return isWeapon and ("1-2× " .. MatName(22447)) or ("1-2× " .. MatName(22445))
        elseif ilvl >= 51 then
            return isWeapon and ("1-2× " .. MatName(16202)) or ("1-2× " .. MatName(16204))
        elseif ilvl >= 41 then
            return isWeapon and (MatName(11174) .. " / " .. MatName(11175))
                or ("1-2× " .. MatName(11176))
        elseif ilvl >= 31 then
            return isWeapon and (MatName(11134) .. " / " .. MatName(11135))
                or ("1-2× " .. MatName(11137))
        elseif ilvl >= 21 then
            return isWeapon and ("1-2× " .. MatName(11082)) or ("1-2× " .. MatName(11083))
        else
            return "1-2× " .. MatName(10940)
        end
    elseif quality == 3 then
        if ilvl >= 65 then return "1× " .. MatName(22449) end
        if ilvl >= 51 then return "1× " .. MatName(22448) end
        return "1× " .. MatName(14344)
    elseif quality >= 4 then
        return ilvl >= 76 and ("1-2× " .. MatName(22450)) or ("1× " .. MatName(20725))
    end
    return nil
end

-- public helper: disenchant preview text for a link (roll advisor etc.)
function addon:DisenchantPreview(link)
    local _, _, quality, ilvl, _, _, _, _, _, _, _, classID = GetItemInfo(link)
    if quality and quality >= 2 and (classID == 2 or classID == 4) then
        return DisenchantResult(quality, ilvl or 0, classID == 2)
    end
    return nil
end

-- ==================== SET-BONUS DETECTION ==========================
-- hidden scan tooltip; set headers look like "Setname (2/8)" in every
-- locale, so a trailing (x/y) marks an equipped item as a set piece
local scanTip
local setCache = {}
local function IsSetPiece(link)
    if not link then return false end
    if setCache[link] ~= nil then return setCache[link] end
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "RLBIScanTip", UIParent,
            "GameTooltipTemplate")
        scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    scanTip:ClearLines()
    local ok = pcall(function() scanTip:SetHyperlink(link) end)
    local found = false
    if ok then
        for i = 1, scanTip:NumLines() or 0 do
            local t = _G["RLBIScanTipTextLeft" .. i]
            local s = t and t:GetText()
            if s and s:match("%(%d+/%d+%)%s*$") then
                found = true
                break
            end
        end
    end
    setCache[link] = found
    return found
end

local function FormatDelta(n)
    if n == math.floor(n) then return tostring(math.floor(n)) end
    return string.format("%.1f", n)
end

-- stacked stat diff: each change on its own line, sorted by weighted impact
local function AddDiffLines(tooltip, hoverStats, eqStats, scaleKey)
    if not addon.db.showStatDiff then return end

    local diffs = {}
    for stat, v in pairs(hoverStats or {}) do
        if not string.find(stat, "^Socket") then
            local d = v - ((eqStats and eqStats[stat]) or 0)
            if d ~= 0 then table.insert(diffs, { stat = stat, d = d }) end
        end
    end
    for stat, v in pairs(eqStats or {}) do
        if not string.find(stat, "^Socket") and (not hoverStats or not hoverStats[stat]) then
            table.insert(diffs, { stat = stat, d = -v })
        end
    end
    local sd = SocketCount(hoverStats) - SocketCount(eqStats)
    if sd ~= 0 then table.insert(diffs, { stat = "Socket", d = sd }) end

    -- flag stats that would (partially) exceed their cap
    if addon.db.checkCaps then
        for _, e in ipairs(diffs) do
            if e.stat ~= "Socket" and e.d > 0 then
                local cap = addon:GetCap(scaleKey, e.stat)
                if cap and cap > 0 then
                    local conv = (e.stat == "Defense") and (1 / 2.365) or 1
                    local replaced = ((eqStats and eqStats[e.stat]) or 0) * conv
                    local base = math.max(0, addon:GetPlayerRating(scaleKey, e.stat) - replaced)
                    local eff = math.max(0, math.min(cap, base + e.d * conv) - math.min(cap, base))
                    if eff < e.d * conv - 0.01 then e.capped = true end
                end
            end
        end
    end

    table.sort(diffs, function(a, b)
        local wa = math.abs((addon:GetWeight(scaleKey, a.stat) or 0.5) * a.d)
        local wb = math.abs((addon:GetWeight(scaleKey, b.stat) or 0.5) * b.d)
        return wa > wb
    end)

    local shown = math.min(#diffs, 8)
    for i = 1, shown do
        local e = diffs[i]
        local name = (e.stat == "Socket") and (Tex(ICON_SOCKET, 11) .. " " .. addon:L("STAT_SOCKET"))
            or StatName(e.stat)
        local color = e.d > 0 and "|cff00ff00" or "|cffff4040"
        local sign = e.d > 0 and "+" or ""
        local capTag = e.capped and " |cffff8800" .. addon:L("CAP_MARKER") .. "|r" or ""
        tooltip:AddLine("      " .. color .. sign .. FormatDelta(e.d) ..
            " |cffbbbbbb" .. name .. "|r" .. capTag)
    end
    if #diffs > shown then
        tooltip:AddLine("      |cff888888+" .. (#diffs - shown) .. " …|r")
    end
end

-- returns: score, baseline (lowest equipped score in the matching slots), equipLoc
function addon:GetUpgradeInfo(link)
    local scaleKey = self:GetActiveScaleKey()
    if not scaleKey then return nil end

    local equipLoc = GetEquipLoc(link)
    local slots = self.SlotMap[equipLoc]
    if not slots then return nil end

    local score, baseline
    if equipLoc == "INVTYPE_2HWEAPON" or (equipLoc == "INVTYPE_WEAPON" and IsEquipped2H()) then
        local s16 = GetSlotStats(16)
        local s17 = GetSlotStats(17)
        local merged = self:MergeStats(s16, s17)
        score = self:GetItemScore(link, scaleKey, merged)
        baseline = (self:GetItemScore(GetInventoryItemLink("player", 16), scaleKey, merged) or 0)
                 + (self:GetItemScore(GetInventoryItemLink("player", 17), scaleKey, merged) or 0)
    else
        local primaryStats = GetSlotStats(slots[1])
        score = self:GetItemScore(link, scaleKey, primaryStats)
        baseline = math.huge
        for _, slotId in ipairs(slots) do
            local eqStats, eqLink = GetSlotStats(slotId)
            local eqScore = eqLink and self:GetItemScore(eqLink, scaleKey, eqStats) or 0
            if eqScore < baseline then baseline = eqScore end
        end
        if baseline == math.huge then baseline = 0 end
    end

    if score <= 0 then return nil end
    return score, baseline, equipLoc
end

-- returns the inventory slot id this item would upgrade, or nil
function addon:GetBestUpgradeSlot(link)
    local scaleKey = self:GetActiveScaleKey()
    if not scaleKey then return nil end

    local equipLoc = GetEquipLoc(link)
    local slots = self.SlotMap[equipLoc]
    if not slots then return nil end

    if equipLoc == "INVTYPE_2HWEAPON" or (equipLoc == "INVTYPE_WEAPON" and IsEquipped2H()) then
        local merged = self:MergeStats(GetSlotStats(16), GetSlotStats(17))
        local score = self:GetItemScore(link, scaleKey, merged)
        local base = (self:GetItemScore(GetInventoryItemLink("player", 16), scaleKey, merged) or 0)
                   + (self:GetItemScore(GetInventoryItemLink("player", 17), scaleKey, merged) or 0)
        return (score > 0 and score > base) and 16 or nil
    end

    -- the slot with the weakest equipped item is the one that gets replaced
    local worstSlot, worstStats, worst = nil, nil, math.huge
    for _, slotId in ipairs(slots) do
        local eqStats, eqLink = GetSlotStats(slotId)
        local eqScore = eqLink and self:GetItemScore(eqLink, scaleKey, eqStats) or 0
        if eqScore < worst then
            worst, worstSlot, worstStats = eqScore, slotId, eqStats
        end
    end
    if not worstSlot then return nil end
    local score = self:GetItemScore(link, scaleKey, worstStats)
    return (score > 0 and score > worst) and worstSlot or nil
end

-- best bag/bank item that fits a given equip slot (upgrade finder)
function addon:BestBagItemForSlot(slotId)
    local scaleKey = self:GetActiveScaleKey()
    if not scaleKey then return nil end
    local best, bestScore
    self:ForEachBagItemLink(function(link)
        local slots = self.SlotMap[GetEquipLoc(link)]
        if slots then
            for _, s in ipairs(slots) do
                if s == slotId then
                    local sc = self:GetItemScore(link, scaleKey) or 0
                    if not bestScore or sc > bestScore then
                        best, bestScore = link, sc
                    end
                    break
                end
            end
        end
    end, true) -- include the bank while it is open
    return best, bestScore
end

-- score and baseline of a link under a different scale (for multi-spec display)
local function ScaleCompare(scaleKey, link, equipLoc, slots)
    if not slots then return 0, 0 end
    if equipLoc == "INVTYPE_2HWEAPON" or (equipLoc == "INVTYPE_WEAPON" and IsEquipped2H()) then
        local merged = addon:MergeStats(GetSlotStats(16), GetSlotStats(17))
        local score = addon:GetItemScore(link, scaleKey, merged)
        local base = (addon:GetItemScore(GetInventoryItemLink("player", 16), scaleKey, merged) or 0)
                   + (addon:GetItemScore(GetInventoryItemLink("player", 17), scaleKey, merged) or 0)
        return score, base
    end
    local worstStats, worst = nil, math.huge
    for _, slotId in ipairs(slots) do
        local eqStats, eqLink = GetSlotStats(slotId)
        local eqScore = eqLink and addon:GetItemScore(eqLink, scaleKey, eqStats) or 0
        if eqScore < worst then
            worst, worstStats = eqScore, eqStats
        end
    end
    if worst == math.huge then worst = 0 end
    return addon:GetItemScore(link, scaleKey, worstStats), worst
end

-- "other specs: Ret +12%, Prot -4%" lines for hybrid classes.
-- specs the item can't serve (no weighted stats) are marked red
local function AddMultiSpecLine(tooltip, link, equipLoc, slots, activeScaleKey)
    if not addon.db.showMultiSpec or not slots then return end
    local _, class = UnitClass("player")
    if not class then return end

    local amounts = addon:GetStatAmounts(link) or {}

    -- the item only counts for a spec if it carries at least one stat
    -- that spec actually weights (sockets don't count - too generic)
    local function Useful(scale)
        for stat, w in pairs(scale.weights or {}) do
            if w > 0 and (amounts[stat] or 0) > 0
                and not string.find(stat, "^Socket") then
                return true
            end
        end
        return false
    end

    local lines = {}
    for _, scale in ipairs(addon:GetScalesForClass(class)) do
        if scale.key ~= activeScaleKey then
            local name = addon:GetScaleName(scale)
            local short = string.match(name, ":%s*(.+)$") or name
            local sc, base = ScaleCompare(scale.key, link, equipLoc, slots)
            if not Useful(scale) or not sc or sc <= 0 then
                table.insert(lines, "|cffbbbbbb" .. short .. "|r  " ..
                    Tex(ICON_DOWN, 10) .. " |cffff4040" ..
                    addon:L("TT_UNFIT") .. "|r")
            elseif base <= 0 then
                table.insert(lines, "|cffbbbbbb" .. short .. "|r  " .. Tex(ICON_UP, 10) ..
                    " |cff00ff00" .. addon:L("TT_UPGRADE") .. "|r")
            else
                local pct = (sc - base) / base * 100
                local color = pct >= 0 and "|cff00ff00" or "|cffff4040"
                local icon = pct >= 0 and ICON_UP or ICON_DOWN
                local sign = pct >= 0 and "+" or ""
                table.insert(lines, "|cffbbbbbb" .. short .. "|r  " .. Tex(icon, 10) ..
                    " " .. color .. sign .. string.format("%.1f", pct) .. "%|r")
            end
        end
    end
    if #lines > 0 then
        tooltip:AddLine("  |cff888888" .. addon:L("TT_OTHER_SPECS") .. ":|r")
        for _, l in ipairs(lines) do
            tooltip:AddLine("      " .. l)
        end
    end
end

function addon:AddUpgradeLines(tooltip, link)
    if not self.db or not self.db.showScore then return end

    local scaleKey = self:GetActiveScaleKey()
    if not scaleKey then return end

    local equipLoc = GetEquipLoc(link)
    local slots = self.SlotMap[equipLoc]

    -- special case: two-handed weapon (or 1H while wearing 2H) vs MH+OH combined
    local combined2H = (equipLoc == "INVTYPE_2HWEAPON")
        or (equipLoc == "INVTYPE_WEAPON" and IsEquipped2H())

    -- stats of the item(s) this would replace (needed for cap math)
    local primaryReplaced
    if combined2H then
        primaryReplaced = self:MergeStats(GetSlotStats(16), GetSlotStats(17))
    elseif slots then
        primaryReplaced = GetSlotStats(slots[1])
    end

    local score, hoverStats, socketScore = self:GetItemScore(link, scaleKey, primaryReplaced)
    -- always show the score line for equippable items (even 0, so users can
    -- see the addon is working); skip only non-equippable junk
    if score <= 0 and not slots then return end

    local scaleName = self:GetScaleName(self:GetScale(scaleKey))

    -- compact Pawn-style: score header, then one line per comparison
    tooltip:AddLine(Tex(ICON_BRAND, 14) .. " |cffffd700RL|r BetterItem  |cffffffff" ..
        string.format("%.1f", score) .. "|r  |cff888888(" .. scaleName .. ")|r" ..
        ((socketScore and socketScore > 0)
            and (" |cff888888(+" .. string.format("%.1f", socketScore) .. " " ..
                self:L("STAT_SOCKET") .. ")|r") or ""))

    -- wishlist star
    local wID = GetItemInfoInstant and GetItemInfoInstant(link)
        or tonumber(string.match(link, "item:(%d+)") or "")
    if wID and self.db.wishlist and self.db.wishlist[wID] then
        tooltip:AddLine("  |cffffd700★ " .. self:L("TT_WISHLIST") .. "|r")
    end

    -- item details: level, id, vendor price (one gray line)
    if self.db.itemTipExtra then
        local ilvl = self.ItemLevelOf and self.ItemLevelOf(link)
            or select(4, GetItemInfo(link))
        local sellPrice = select(11, GetItemInfo(link))
        local id = (GetItemInfoInstant and GetItemInfoInstant(link))
            or tonumber(string.match(link, "item:(%d+)") or "")
        local parts = {}
        if ilvl and ilvl > 0 then
            parts[#parts + 1] = "iLvl " .. ilvl
        end
        if id then
            parts[#parts + 1] = "ID " .. id
        end
        if sellPrice and sellPrice > 0 then
            local g = math.floor(sellPrice / 10000)
            local s = math.floor((sellPrice % 10000) / 100)
            local c = sellPrice % 100
            if g > 0 then
                parts[#parts + 1] = string.format("%dg %ds", g, s)
            elseif s > 0 then
                parts[#parts + 1] = string.format("%ds %dc", s, c)
            else
                parts[#parts + 1] = c .. "c"
            end
        end
        if #parts > 0 then
            tooltip:AddLine("  |cff888888" .. table.concat(parts, "  ·  ") .. "|r")
        end
    end

    -- per-item gear score; HunterScore shows for melee/ranged
    -- weapons when the player (or the inspected unit) is a hunter, or when a
    -- modifier key is held
    if self.GearScoreForItem then
        local gs, _, gr, gg, gb = self:GearScoreForItem(link)
        if gs and gs > 1 then
            tooltip:AddLine(string.format("  GearScore: |cff%02x%02x%02x%d|r",
                gr * 255, gg * 255, gb * 255, gs))
            local melee = equipLoc == "INVTYPE_2HWEAPON"
                or equipLoc == "INVTYPE_WEAPONMAINHAND"
                or equipLoc == "INVTYPE_WEAPONOFFHAND"
                or equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_HOLDABLE"
            local ranged = equipLoc == "INVTYPE_RANGEDRIGHT"
                or equipLoc == "INVTYPE_RANGED"
            if melee or ranged then
                local _, pclass = UnitClass("player")
                local showHS = pclass == "HUNTER" or IsModifierKeyDown()
                    or (InspectFrame and InspectFrame:IsShown()
                        and InspectFrame.unit
                        and select(2, UnitClass(InspectFrame.unit)) == "HUNTER")
                if showHS then
                    local hs = math.floor(gs * (melee and 0.3164 or 5.3224))
                    tooltip:AddLine(string.format("  HunterScore: |cff%02x%02x%02x%d|r",
                        gr * 255, gg * 255, gb * 255, hs))
                end
            end
        end
    end

    -- disenchant preview for uncommon+ weapons/armor
    if self.db.deValue then
        local _, _, quality, ilvl, _, _, _, _, _, _, _, classID = GetItemInfo(link)
        if quality and quality >= 2 and (classID == 2 or classID == 4) then
            local de = DisenchantResult(quality, ilvl or 0, classID == 2)
            if de then
                tooltip:AddLine("  |cffb67fff" .. self:L("TT_DE") .. " " .. de .. "|r")
            end
        end
    end

    -- gem hint: best stat per socket color, one compact line
    if hoverStats and self.db.socketValue then
        local gemParts = {}
        for _, sk in ipairs({ "SocketRed", "SocketYellow", "SocketBlue", "SocketMeta", "SocketAny" }) do
            if (hoverStats[sk] or 0) > 0 then
                local colorTex = "Interface\\ItemSocketingFrame\\UI-EmptySocket-" ..
                    string.gsub(sk, "Socket", "")
                if sk == "SocketAny" then
                    colorTex = "Interface\\ItemSocketingFrame\\UI-EmptySocket"
                end
                -- concrete gem name when resolvable, else the stat
                local gemID, stat = self:GetBestGemID(sk, scaleKey)
                local label = (gemID and GetItemInfo and
                    (GetItemInfo(gemID))) or (stat and StatName(stat))
                if label then
                    table.insert(gemParts, Tex(colorTex, 11) .. " " .. label)
                else
                    table.insert(gemParts, Tex(colorTex, 11))
                end
            end
        end
        if #gemParts > 0 then
            tooltip:AddLine("  |cff888888" .. self:L("TT_GEMS") .. ":|r " ..
                table.concat(gemParts, "  "))
        end

        -- socket bonus evaluation: worth matching colors or better off
        -- stuffing best-color gems? bonus value vs. per-socket stat loss
        local tname = tooltip.GetName and tooltip:GetName()
        local bonusText
        if tname and tooltip.NumLines then
            for i = 1, tooltip:NumLines() or 0 do
                local lfs = _G[tname .. "TextLeft" .. i]
                local lt = lfs and lfs:GetText()
                local low = lt and LowerASCII(lt)
                if low and (string.find(low, "socket bonus", 1, true)
                    or string.find(low, "sockelbonus", 1, true)) then
                    bonusText = lt
                    break
                end
            end
        end
        if bonusText then
            local rest = string.match(bonusText, ":%s*(.+)%s*$") or bonusText
            local amount, bStat = ParseBonusStat(rest)
            if amount and bStat then
                local bonusScore = amount * (self:GetWeight(scaleKey, bStat) or 0)
                local bestW = self:MaxWeight(scaleKey) or 0
                local loss = 0
                for _, sk in ipairs({ "SocketRed", "SocketYellow", "SocketBlue" }) do
                    for _ = 1, (hoverStats[sk] or 0) do
                        local gstat = self:GetBestGemStat(sk, scaleKey)
                        local cw = gstat and self:GetWeight(scaleKey, gstat) or 0
                        loss = loss + math.max(0, bestW - cw) * 8
                    end
                end
                local verdict = bonusScore > loss
                tooltip:AddLine("  |cff888888" .. self:L("TT_SOCKBONUS") .. ":|r " ..
                    rest .. "  " .. (verdict and
                        ("|cff00ff00" .. self:L("TT_SOCKBONUS_WORTH") .. "|r") or
                        ("|cffff8800" .. self:L("TT_SOCKBONUS_SKIP") .. "|r")))
            end
        end
    end

    if not self.db.showUpgrade or not slots then
        tooltip:Show()
        return
    end

    local hoveredID = GetItemInfoInstant and GetItemInfoInstant(link)
        or tonumber(string.match(link, "item:(%d+)") or "")

    -- result line only: "▲ +15,2%" / "▼ -3,1%" / "▲ Verbesserung"
    local function ResultText(pct, baseScore, slotScore)
        if baseScore <= 0 then
            if slotScore > 0 then
                return Tex(ICON_UP, 12) .. " |cff00ff00" .. self:L("TT_UPGRADE") .. "|r"
            end
            return nil
        end
        if pct >= 0 then
            return Tex(ICON_UP, 12) .. " |cff00ff00+" .. string.format("%.1f", pct) .. "%|r"
        end
        return Tex(ICON_DOWN, 12) .. " |cffff4040" .. string.format("%.1f", pct) .. "%|r"
    end

    local function TargetLine(eqLink)
        local text = eqLink and (ItemIcon(eqLink) .. ItemName(eqLink))
            or "|cff666666(" .. self:L("TT_EMPTY_SLOT") .. ")|r"
        tooltip:AddLine("      |cff888888" .. self:L("TT_INSTEAD_OF") .. ":|r " .. text)
    end

    if combined2H then
        local mhScore = self:GetItemScore(GetInventoryItemLink("player", 16), scaleKey, primaryReplaced) or 0
        local ohScore = self:GetItemScore(GetInventoryItemLink("player", 17), scaleKey, primaryReplaced) or 0
        local base = mhScore + ohScore
        local pct = base > 0 and ((score - base) / base * 100) or 0

        local result = ResultText(pct, base, score)
        if result then
            tooltip:AddLine("  " .. result)
            local mhLink = GetInventoryItemLink("player", 16)
            local ohLink = GetInventoryItemLink("player", 17)
            TargetLine(mhLink)
            TargetLine(ohLink)
            if self.db.setBonusWarn
                and (IsSetPiece(mhLink) or IsSetPiece(ohLink)) then
                tooltip:AddLine("      |cffff8800⚠ " .. self:L("TT_SETWARN") .. "|r")
            end
        end
        AddDiffLines(tooltip, hoverStats, primaryReplaced, scaleKey)
        AddMultiSpecLine(tooltip, link, equipLoc, slots, scaleKey)
        tooltip:Show()
        return
    end

    local isEquippedItem = false
    for _, slotId in ipairs(slots) do
        local equippedID = GetEquippedItemID(slotId)
        -- skip the slot if the hovered item is the one currently equipped there
        if equippedID and hoveredID and equippedID == hoveredID then
            isEquippedItem = true
        else
            local eqStats, eqLink = GetSlotStats(slotId)
            -- score of the hovered item in context of replacing THIS slot's item
            local slotScore = self:GetItemScore(link, scaleKey, eqStats)
            local baseScore = eqLink and self:GetItemScore(eqLink, scaleKey, eqStats) or 0
            local pct = baseScore > 0 and ((slotScore - baseScore) / baseScore * 100) or 0

            local result = ResultText(pct, baseScore, slotScore)
            if result then
                tooltip:AddLine("  " .. result)
                TargetLine(eqLink)
                if self.db.setBonusWarn and IsSetPiece(eqLink) then
                    tooltip:AddLine("      |cffff8800⚠ " .. self:L("TT_SETWARN") .. "|r")
                end
                AddDiffLines(tooltip, hoverStats, eqStats, scaleKey)
            end
        end
    end

    -- "best in slot" star: the hovered item beats EVERY equipped item
    -- it could replace (not just the weakest one)
    if not isEquippedItem and score > 0 then
        local best = 0
        for _, slotId in ipairs(slots) do
            local eqStats, eqLink = GetSlotStats(slotId)
            local s = eqLink and self:GetItemScore(eqLink, scaleKey, eqStats) or 0
            if s > best then best = s end
        end
        if best > 0 and score > best then
            tooltip:AddLine("  |cffffd700★ " .. self:L("TT_BESTSLOT") .. "|r")
        end
    end

    -- hovering an equipped item: check the bags for a better replacement
    if isEquippedItem and self.db.showUpgrade then
        local bestLink, bestPct = nil, nil
        self:ForEachBagItemLink(function(bagLink)
            if GetEquipLoc(bagLink) == equipLoc then
                local sc, base = self:GetUpgradeInfo(bagLink)
                if sc and base and base > 0 and sc > base then
                    local pct = (sc - base) / base * 100
                    if not bestPct or pct > bestPct then
                        bestLink, bestPct = bagLink, pct
                    end
                end
            end
        end, true) -- include the bank while it is open
        if bestLink then
            tooltip:AddLine("  " .. Tex(ICON_UP, 12) .. " |cff00ff00" ..
                self:L("TT_BETTER_IN_BAGS") .. ":|r +" ..
                string.format("%.1f", bestPct) .. "%")
            tooltip:AddLine("      " .. ItemIcon(bestLink) .. ItemName(bestLink))
        else
            tooltip:AddLine("  " .. Tex(ICON_UP, 12) .. " |cff00ff00" ..
                self:L("TT_BEST_EQUIPPED") .. "|r")
        end
    end

    AddMultiSpecLine(tooltip, link, equipLoc, slots, scaleKey)
    if self.AddOutfitLine then self:AddOutfitLine(tooltip, link) end
    tooltip:Show()
end

-- ==================== TOOLTIP HOOKS ====================
-- dedupe: skip if our score line is already on this tooltip (both hook paths
-- may fire on clients that have the modern tooltip pipeline)
local function AlreadyProcessed(tooltip)
    local name = tooltip.GetName and tooltip:GetName()
    if not name or not tooltip.NumLines then return false end
    local n = tooltip:NumLines() or 0
    for i = math.max(1, n - 8), n do
        local fs = _G[name .. "TextLeft" .. i]
        local t = fs and fs:GetText()
        if t and string.find(t, "RL|r BetterItem", 1, true) then return true end
    end
    return false
end

local function OnItemTooltip(tooltip, link)
    if not addon.initialized or not tooltip or not link then return end
    if AlreadyProcessed(tooltip) then return end
    addon:Debug("tooltip item: " .. tostring(link))
    -- item links come in many shapes (uncached, spell-like, odd
    -- strings); never let one bad item spam Lua errors
    local ok, err = pcall(addon.AddUpgradeLines, addon, tooltip, link)
    if not ok then
        addon:Debug("tooltip error on " .. tostring(link) .. ": " ..
            tostring(err))
    end
end

-- modern clients (new tooltip pipeline): covers every item tooltip
-- regardless of how it was populated (bags, inventory, links, ...)
local usedTDP = false
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
    and Enum and Enum.TooltipDataType then
    local ok = pcall(function()
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item,
            function(tooltip, data)
                local link
                if data then
                    link = data.hyperlink or data.link
                    if not link and data.id then
                        local _, l = GetItemInfo(data.id)
                        link = l
                    end
                end
                if not link then
                    local _, l = tooltip:GetItem()
                    link = l
                end
                OnItemTooltip(tooltip, link)
            end)
    end)
    usedTDP = ok
end

-- classic fallback: OnTooltipSetItem script hooks
local function HookTooltip(tooltip)
    if not tooltip then return end
    tooltip:HookScript("OnTooltipSetItem", function(self)
        local _, link = self:GetItem()
        OnItemTooltip(self, link)
    end)
end

HookTooltip(GameTooltip)
HookTooltip(ItemRefTooltip)
-- comparison tooltips shown next to the main tooltip while shopping
HookTooltip(ShoppingTooltip1)
HookTooltip(ShoppingTooltip2)
if ItemRefShoppingTooltip1 then HookTooltip(ItemRefShoppingTooltip1) end
if ItemRefShoppingTooltip2 then HookTooltip(ItemRefShoppingTooltip2) end

addon.usedTooltipDataProcessor = usedTDP
