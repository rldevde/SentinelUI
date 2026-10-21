local addon = RLBetterItem

-- ==================== TBC STAT WEIGHT SCALES ====================
-- Roughly normalized so the best stat ~ 1.0 per scale.
-- Values are TBC-appropriate estimates (hit/expertise valued highly,
-- separate spell-hit/-crit/-haste, +healing as its own stat).

addon.Scales = {
    -- ===== WARRIOR =====
    {
        key = "WarriorArms",
        class = "WARRIOR",
        role = "dd",
        name = "Warrior: Arms",
        nameDE = "Krieger: Waffen",
        weights = {
            Strength = 1.0, AttackPower = 0.45, Agility = 0.65,
            Hit = 0.95, Crit = 0.8, Haste = 0.7, Expertise = 0.85,
            ArmorPen = 0.55, WeaponDPS = 3.8, Stamina = 0.1,
        },
        caps = { Hit = 142, Expertise = 103 },
    },
    {
        key = "WarriorFury",
        class = "WARRIOR",
        role = "dd",
        name = "Warrior: Fury",
        nameDE = "Krieger: Furor",
        weights = {
            Strength = 1.0, AttackPower = 0.45, Agility = 0.7,
            Hit = 0.95, Crit = 0.8, Haste = 0.7, Expertise = 0.85,
            ArmorPen = 0.55, WeaponDPS = 3.8, Stamina = 0.1,
        },
        -- dual-wield: white hit cap 28% = 442 rating (yellow cap stays 142)
        caps = { Hit = 442, Expertise = 103 },
    },
    {
        key = "WarriorProt",
        class = "WARRIOR",
        role = "tank",
        name = "Warrior: Protection",
        nameDE = "Krieger: Schutz",
        weights = {
            Stamina = 1.0, Armor = 0.32, Defense = 0.72, Dodge = 0.62,
            Parry = 0.5, BlockRating = 0.3, BlockValue = 0.4,
            Agility = 0.35, Strength = 0.2, AttackPower = 0.1,
            Hit = 0.4, Expertise = 0.55,
        },
        -- 490 defense skill = crit-immune vs bosses; 221 = parry cap
        caps = { Hit = 142, Expertise = 221, Defense = 490 },
    },

    -- ===== PALADIN =====
    {
        key = "PaladinHoly",
        class = "PALADIN",
        role = "heal",
        name = "Paladin: Holy",
        nameDE = "Paladin: Heilig",
        weights = {
            Healing = 1.0, Intellect = 0.6, SpellCrit = 0.5, MP5 = 0.5,
            SpellPower = 0.35, Stamina = 0.15, SpellHaste = 0.3,
        },
    },
    {
        key = "PaladinProt",
        class = "PALADIN",
        role = "tank",
        name = "Paladin: Protection",
        nameDE = "Paladin: Schutz",
        weights = {
            Stamina = 1.0, Armor = 0.3, Defense = 0.7, Dodge = 0.6,
            Parry = 0.45, BlockRating = 0.35, BlockValue = 0.45,
            SpellPower = 0.5, Agility = 0.3, Hit = 0.35,
            Expertise = 0.45, Strength = 0.15, Intellect = 0.1,
        },
        caps = { Hit = 142, SpellHit = 202, Expertise = 221, Defense = 490 },
    },
    {
        key = "PaladinRet",
        class = "PALADIN",
        role = "dd",
        name = "Paladin: Retribution",
        nameDE = "Paladin: Vergeltung",
        weights = {
            Strength = 1.0, AttackPower = 0.45, Agility = 0.6,
            Hit = 0.95, Crit = 0.75, Expertise = 0.9, Haste = 0.6,
            ArmorPen = 0.45, WeaponDPS = 3.8, Stamina = 0.1,
            Intellect = 0.15, SpellPower = 0.1,
        },
        caps = { Hit = 142, Expertise = 103 },
    },

    -- ===== HUNTER =====
    {
        key = "HunterDPS",
        class = "HUNTER",
        role = "dd",
        name = "Hunter: DPS",
        nameDE = "Jäger: DPS",
        weights = {
            Agility = 1.0, RangedAttackPower = 0.45, AttackPower = 0.4,
            Hit = 0.9, Crit = 0.65, Haste = 0.75, ArmorPen = 0.55,
            Intellect = 0.3, MP5 = 0.2, WeaponDPS = 3.0, Stamina = 0.1,
        },
        caps = { Hit = 142 },
        hitCR = 7, -- CR_HIT_RANGED
    },

    -- ===== ROGUE =====
    {
        key = "RogueDPS",
        class = "ROGUE",
        role = "dd",
        name = "Rogue: DPS",
        nameDE = "Schurke: DPS",
        weights = {
            Agility = 1.0, AttackPower = 0.45, Strength = 0.35,
            Hit = 1.0, Expertise = 0.95, Crit = 0.8, Haste = 0.85,
            ArmorPen = 0.6, WeaponDPS = 4.0, Stamina = 0.1,
        },
        caps = { Hit = 442, Expertise = 103 }, -- dual-wield white cap 28%
    },

    -- ===== PRIEST =====
    {
        key = "PriestHoly",
        class = "PRIEST",
        role = "heal",
        name = "Priest: Holy/Disc",
        nameDE = "Priester: Heilig/Diszi",
        weights = {
            Healing = 1.0, Intellect = 0.5, Spirit = 0.6, MP5 = 0.65,
            SpellCrit = 0.35, SpellPower = 0.35, Stamina = 0.15,
            SpellHaste = 0.3,
        },
    },
    {
        key = "PriestShadow",
        class = "PRIEST",
        role = "dd",
        name = "Priest: Shadow",
        nameDE = "Priester: Schatten",
        weights = {
            SpellPower = 1.0, SpellHit = 1.0, SpellCrit = 0.55,
            SpellHaste = 0.8, Intellect = 0.35, MP5 = 0.4,
            Spirit = 0.2, Stamina = 0.1,
        },
        -- Shadow Focus gives 10% spell hit -> only 6% = 76 rating needed
        caps = { SpellHit = 76 },
    },

    -- ===== SHAMAN =====
    {
        key = "ShamanEle",
        class = "SHAMAN",
        role = "dd",
        name = "Shaman: Elemental",
        nameDE = "Schamane: Elementar",
        weights = {
            SpellPower = 1.0, SpellHit = 0.95, SpellCrit = 0.65,
            SpellHaste = 0.8, Intellect = 0.35, MP5 = 0.3, Stamina = 0.05,
        },
        -- Elemental Precision +3% (typical build) -> 13% = 164 rating
        caps = { SpellHit = 164 },
    },
    {
        key = "ShamanEnh",
        class = "SHAMAN",
        role = "dd",
        name = "Shaman: Enhancement",
        nameDE = "Schamane: Verstärker",
        weights = {
            Agility = 1.0, Strength = 0.55, AttackPower = 0.45,
            Hit = 0.95, Expertise = 0.95, Crit = 0.8, Haste = 0.75,
            ArmorPen = 0.5, Intellect = 0.35, WeaponDPS = 3.5,
            Stamina = 0.1,
        },
        caps = { Hit = 442, Expertise = 103 }, -- dual-wield white cap 28%
    },
    {
        key = "ShamanResto",
        class = "SHAMAN",
        role = "heal",
        name = "Shaman: Restoration",
        nameDE = "Schamane: Wiederherstellung",
        weights = {
            Healing = 1.0, Intellect = 0.55, MP5 = 0.7, SpellCrit = 0.45,
            SpellPower = 0.3, Stamina = 0.15, SpellHaste = 0.4,
        },
    },

    -- ===== MAGE =====
    {
        key = "MageCaster",
        class = "MAGE",
        role = "dd",
        name = "Mage: Caster",
        nameDE = "Magier: Caster",
        weights = {
            SpellPower = 1.0, SpellHit = 1.05, SpellCrit = 0.75,
            SpellHaste = 0.85, Intellect = 0.3, MP5 = 0.25,
            Spirit = 0.1, Stamina = 0.05,
        },
        -- Elemental Precision +3% (standard fire/frost builds) -> 164
        caps = { SpellHit = 164 },
    },

    -- ===== WARLOCK =====
    {
        key = "WarlockCaster",
        class = "WARLOCK",
        role = "dd",
        name = "Warlock: Caster",
        nameDE = "Hexenmeister: Caster",
        weights = {
            SpellPower = 1.0, SpellHit = 1.1, SpellCrit = 0.7,
            SpellHaste = 0.9, Intellect = 0.25, Stamina = 0.15,
            Spirit = 0.05, MP5 = 0.15,
        },
        caps = { SpellHit = 202 },
    },

    -- ===== DRUID =====
    {
        key = "DruidBalance",
        class = "DRUID",
        role = "dd",
        name = "Druid: Balance",
        nameDE = "Druide: Gleichgewicht",
        weights = {
            SpellPower = 1.0, SpellHit = 1.05, SpellCrit = 0.7,
            SpellHaste = 0.8, Intellect = 0.4, Spirit = 0.3,
            MP5 = 0.35, Stamina = 0.05,
        },
        -- Balance of Power +4% spell hit -> only 12% = 152 rating needed
        caps = { SpellHit = 152 },
    },
    {
        key = "DruidCat",
        class = "DRUID",
        role = "dd",
        name = "Druid: Feral (Cat)",
        nameDE = "Druide: Wild (Katze)",
        weights = {
            Agility = 1.0, Strength = 0.7, AttackPower = 0.4,
            FeralAttackPower = 0.4, Hit = 0.9, Expertise = 0.9,
            Crit = 0.75, Haste = 0.6, ArmorPen = 0.5, Stamina = 0.1,
        },
        caps = { Hit = 142, Expertise = 103 },
    },
    {
        key = "DruidBear",
        class = "DRUID",
        role = "tank",
        name = "Druid: Feral (Bear)",
        nameDE = "Druide: Wild (Bär)",
        weights = {
            Stamina = 1.0, Armor = 0.35, Agility = 0.75, Dodge = 0.6,
            Defense = 0.6, Strength = 0.45, FeralAttackPower = 0.35,
            AttackPower = 0.2, Hit = 0.45, Expertise = 0.6,
        },
        -- 415 defense skill with Survival of the Fittest = crit-immune
        caps = { Hit = 142, Expertise = 103, Defense = 415 },
    },
    {
        key = "DruidResto",
        class = "DRUID",
        role = "heal",
        name = "Druid: Restoration",
        nameDE = "Druide: Wiederherstellung",
        weights = {
            Healing = 1.0, Spirit = 0.65, Intellect = 0.5, MP5 = 0.7,
            SpellCrit = 0.3, SpellPower = 0.3, Stamina = 0.15,
            SpellHaste = 0.35,
        },
    },

    -- ===== GENERIC (classes without built-in scales: DK/Monk/DH/Evoker
    -- and anything future clients add) =====
    {
        key = "GenericTank",
        class = "*",
        role = "tank",
        name = "Tank",
        nameDE = "Tank",
        weights = {
            Stamina = 1.0, Armor = 0.4, Dodge = 0.6, Parry = 0.5,
            Defense = 0.6, BlockRating = 0.35, Agility = 0.4,
            Strength = 0.25, Hit = 0.3, Expertise = 0.4,
        },
        caps = { Hit = 142, Defense = 490 },
    },
    {
        key = "GenericHeal",
        class = "*",
        role = "heal",
        name = "Healer",
        nameDE = "Heiler",
        weights = {
            Intellect = 1.0, Healing = 0.9, Spirit = 0.6, MP5 = 0.6,
            SpellCrit = 0.5, SpellPower = 0.5, SpellHaste = 0.6,
            Stamina = 0.15,
        },
    },
    {
        key = "GenericDPS",
        class = "*",
        role = "dd",
        name = "DPS",
        nameDE = "DD",
        weights = {
            Strength = 0.7, Agility = 0.7, AttackPower = 0.45,
            Intellect = 0.5, SpellPower = 0.5, Hit = 0.9,
            SpellHit = 0.7, Crit = 0.8, SpellCrit = 0.7,
            Haste = 0.75, SpellHaste = 0.6, ArmorPen = 0.5,
            WeaponDPS = 3.5, Stamina = 0.1,
        },
        caps = { Hit = 142, SpellHit = 202 },
    },
}

-- talent tab index -> candidate scale keys (auto detection).
-- TBC has free talent trees, so one tab can map to multiple specs
-- (druid feral = cat AND bear) and hybrid builds are common.
local SPEC_SCALE = {
    WARRIOR = { { "WarriorArms" }, { "WarriorFury" }, { "WarriorProt" } },
    PALADIN = { { "PaladinHoly" }, { "PaladinProt" }, { "PaladinRet" } },
    HUNTER  = { { "HunterDPS" }, { "HunterDPS" }, { "HunterDPS" } },
    ROGUE   = { { "RogueDPS" }, { "RogueDPS" }, { "RogueDPS" } },
    PRIEST  = { { "PriestHoly" }, { "PriestHoly" }, { "PriestShadow" } },
    SHAMAN  = { { "ShamanEle" }, { "ShamanEnh" }, { "ShamanResto" } },
    MAGE    = { { "MageCaster" }, { "MageCaster" }, { "MageCaster" } },
    WARLOCK = { { "WarlockCaster" }, { "WarlockCaster" }, { "WarlockCaster" } },
    DRUID   = { { "DruidBalance" }, { "DruidCat", "DruidBear" }, { "DruidResto" } },
}

-- talent tab used when no points are spent yet.
-- TBC: first point at level 10 -> levels 1-9 always hit this fallback,
-- so the default is the typical leveling spec per class
local DEFAULT_TAB = {
    WARRIOR = 1, -- Arms
    PALADIN = 3, -- Retribution
    HUNTER  = 2, -- Beast Mastery
    ROGUE   = 2, -- Combat
    PRIEST  = 3, -- Shadow
    SHAMAN  = 2, -- Enhancement
    MAGE    = 3, -- Frost
    WARLOCK = 2, -- Demonology
    DRUID   = 2, -- Feral
}

-- two trees this close together are treated as a hybrid build and
-- decided by the equipped gear instead (0/49/12 prot-ret pala etc.)
local HYBRID_GAP = 8

-- modern clients (MoP/Legion/retail/WoW "Forever"): specID -> our scale.
-- classes not covered here fall back through SPECID_ROLE -> role scale.
local SPECID_SCALE = {
    -- warrior
    [71] = "WarriorArms", [72] = "WarriorFury", [73] = "WarriorProt",
    -- paladin
    [65] = "PaladinHoly", [66] = "PaladinProt", [70] = "PaladinRet",
    -- hunter
    [253] = "HunterDPS", [254] = "HunterDPS", [255] = "HunterDPS",
    -- rogue
    [259] = "RogueDPS", [260] = "RogueDPS", [261] = "RogueDPS",
    -- priest
    [256] = "PriestHoly", [257] = "PriestHoly", [258] = "PriestShadow",
    -- shaman
    [262] = "ShamanEle", [263] = "ShamanEnh", [264] = "ShamanResto",
    -- mage
    [62] = "MageCaster", [63] = "MageCaster", [64] = "MageCaster",
    -- warlock
    [265] = "WarlockCaster", [266] = "WarlockCaster", [267] = "WarlockCaster",
    -- druid
    [102] = "DruidBalance", [103] = "DruidCat", [104] = "DruidBear",
    [105] = "DruidResto",
}

-- every known specID -> role (for generic-scale classes and fallbacks)
local SPECID_ROLE = {
    [71] = "dd", [72] = "dd", [73] = "tank",          -- warrior
    [65] = "heal", [66] = "tank", [70] = "dd",        -- paladin
    [253] = "dd", [254] = "dd", [255] = "dd",         -- hunter
    [259] = "dd", [260] = "dd", [261] = "dd",         -- rogue
    [256] = "heal", [257] = "heal", [258] = "dd",     -- priest
    [250] = "tank", [251] = "dd", [252] = "dd",       -- death knight
    [262] = "dd", [263] = "dd", [264] = "heal",       -- shaman
    [62] = "dd", [63] = "dd", [64] = "dd",            -- mage
    [265] = "dd", [266] = "dd", [267] = "dd",         -- warlock
    [268] = "tank", [269] = "dd", [270] = "heal",     -- monk
    [102] = "dd", [103] = "dd", [104] = "tank", [105] = "heal", -- druid
    [577] = "dd", [581] = "tank",                     -- demon hunter
    [1467] = "dd", [1468] = "heal", [1473] = "dd",    -- evoker
}

addon.scaleByKey = {}
for _, scale in ipairs(addon.Scales) do
    addon.scaleByKey[scale.key] = scale
end

function addon:GetScale(key)
    if self.scaleByKey[key] then return self.scaleByKey[key] end
    if self.db and self.db.savedScales then
        return self.db.savedScales[key]
    end
    return nil
end

function addon:GetScaleName(scale)
    if not scale then return "?" end
    if self.locale == "deDE" and scale.nameDE then
        return scale.nameDE
    end
    return scale.name
end

function addon:GetScalesForClass(class)
    local list = {}
    for _, scale in ipairs(self.Scales) do
        if scale.class == class then
            table.insert(list, scale)
        end
    end
    if self.db and self.db.savedScales then
        for _, scale in pairs(self.db.savedScales) do
            if scale.class == class then
                table.insert(list, scale)
            end
        end
    end
    -- classes without built-in scales (DK/Monk/DH/Evoker/future):
    -- fall back to the generic role scales
    if #list == 0 then
        for _, scale in ipairs(self.Scales) do
            if scale.class == "*" then
                table.insert(list, scale)
            end
        end
    end
    return list
end

-- save the current effective weights+caps of a scale as a named custom scale
function addon:SaveScaleLibrary(name)
    if not name or name == "" or not self.db then return nil end
    local scaleKey = self:GetActiveScaleKey()
    local scale = self:GetScale(scaleKey)
    if not scale then return nil end

    local key = "Custom_" .. name:gsub("[^%w]", "")
    local weights = {}
    for _, stat in ipairs(self.StatOrder) do
        local w = self:GetWeight(scaleKey, stat)
        if w ~= 0 then weights[stat] = w end
    end
    local caps = {}
    if self.db.customCaps and self.db.customCaps[scaleKey] then
        for stat, v in pairs(self.db.customCaps[scaleKey]) do caps[stat] = v end
    end
    if scale.caps then
        for stat, v in pairs(scale.caps) do
            if caps[stat] == nil then caps[stat] = v end
        end
    end

    self.db.savedScales[key] = {
        key = key, class = select(2, UnitClass("player")),
        name = name, nameDE = name, weights = weights,
        caps = (next(caps) and caps) or nil,
    }
    return key
end

function addon:DeleteScaleLibrary(key)
    if self.db and self.db.savedScales then
        self.db.savedScales[key] = nil
        if self.db.scale == key then self.db.scale = "auto" end
    end
end

function addon:GetWeight(scaleKey, stat)
    if self.db and self.db.customWeights and self.db.customWeights[scaleKey]
        and self.db.customWeights[scaleKey][stat] ~= nil then
        return self.db.customWeights[scaleKey][stat]
    end
    local scale = self:GetScale(scaleKey)
    return (scale and scale.weights[stat]) or 0
end

function addon:SetCustomWeight(scaleKey, stat, value)
    if not self.db.customWeights then self.db.customWeights = {} end
    if not self.db.customWeights[scaleKey] then self.db.customWeights[scaleKey] = {} end
    self.db.customWeights[scaleKey][stat] = value
    if self.ClearUpgradeCache then self:ClearUpgradeCache() end
end

function addon:ResetCustomWeights(scaleKey)
    if self.db.customWeights then
        self.db.customWeights[scaleKey] = nil
    end
    if self.db.customCaps then
        self.db.customCaps[scaleKey] = nil
    end
    if self.ClearUpgradeCache then self:ClearUpgradeCache() end
end

-- ==================== RATING CAPS ====================
local CR_HIT_MELEE  = CR_HIT_MELEE  or 6
local CR_HIT_RANGED = CR_HIT_RANGED or 7
local CR_HIT_SPELL  = CR_HIT_SPELL  or 8
local CR_EXPERTISE  = CR_EXPERTISE  or 24

-- racial cap adjustments (TBC):
--   draenei Heroic Presence  -> +1% melee/ranged/spell hit for self
--   human Sword/Mace Spec    -> +5 expertise with swords/maces
--   orc Axe/Fist Spec        -> +5 expertise with axes/fists
-- 5 expertise ~ 20 rating, 1% melee hit ~ 16 rating, 1% spell hit ~ 13
local RACE_WEAPONS = {
    Human = { "sword", "schwert", "mace", "streitkolben" },
    Orc   = { "axe", "axt", "\195\164xt", "fist", "faust" }, -- äxt utf8
}
local function RacialCapMod(stat)
    local _, race = UnitRace("player")
    if stat == "Hit" and race == "Draenei" then return -16 end
    if stat == "SpellHit" and race == "Draenei" then return -13 end
    if stat ~= "Expertise" then return 0 end
    local patterns = race and RACE_WEAPONS[race]
    if not patterns then return 0 end
    local link = GetInventoryItemLink("player", 16)
    if not link then return 0 end
    local sub = link and select(7, GetItemInfo(link))
    if not sub then return 0 end
    sub = string.lower(sub)
    for _, p in ipairs(patterns) do
        if string.find(sub, p, 1, true) then return -20 end
    end
    return 0
end

function addon:GetCap(scaleKey, stat)
    if self.db and self.db.customCaps and self.db.customCaps[scaleKey]
        and self.db.customCaps[scaleKey][stat] ~= nil then
        return self.db.customCaps[scaleKey][stat]
    end
    local scale = self:GetScale(scaleKey)
    local cap = (scale and scale.caps) and scale.caps[stat] or nil
    if cap then
        cap = math.max(0, cap + RacialCapMod(stat))
    end
    return cap
end

-- ==================== ROLES (tank / healer / dd) ====================
-- the role is a quick-switch layer over scales: choosing a role picks
-- the class scale matching it (remembered per role in db.roleScales)
function addon:GetScalesForRole(class, role)
    local list = {}
    for _, scale in ipairs(self:GetScalesForClass(class)) do
        if (scale.role or "dd") == role then
            table.insert(list, scale)
        end
    end
    if #list == 0 then
        -- no class scale for this role -> generic role scale
        for _, scale in ipairs(self.Scales) do
            if scale.class == "*" and scale.role == role then
                table.insert(list, scale)
            end
        end
    end
    return list
end

-- pick the scale key matching a role for the class (generic fallback)
function addon:ScaleKeyForRole(class, role)
    local list = self:GetScalesForRole(class, role)
    return list[1] and list[1].key or nil
end

function addon:GetRolesForClass(class)
    local roles, seen = {}, {}
    for _, scale in ipairs(self:GetScalesForClass(class)) do
        local r = scale.role or "dd"
        if not seen[r] then
            seen[r] = true
            table.insert(roles, r)
        end
    end
    local order = { tank = 1, heal = 2, dd = 3 }
    table.sort(roles, function(a, b) return order[a] < order[b] end)
    return roles
end

function addon:GetScaleRole(scaleKey)
    local scale = self:GetScale(scaleKey)
    return (scale and scale.role) or "dd"
end

-- switch role: "auto" resumes talent detection, otherwise picks the
-- remembered/first class scale of that role
function addon:SetRole(role)
    local _, class = UnitClass("player")
    if not class then return end
    if role == "auto" then
        self.db.scale = "auto"
    else
        self.db.roleScales = self.db.roleScales or {}
        self.db.roleScales[class] = self.db.roleScales[class] or {}
        local saved = self.db.roleScales[class][role]
        local valid = saved and self:GetScale(saved)
            and self:GetScaleRole(saved) == role
        if not valid then
            local list = self:GetScalesForRole(class, role)
            saved = list[1] and list[1].key
        end
        if saved then self.db.scale = saved end
    end
    if self.ClearUpgradeCache then self:ClearUpgradeCache() end
    if self.RefreshSettings then self:RefreshSettings() end
    if self.UpdateStatsPanel then self:UpdateStatsPanel() end
end

-- remember which scale belongs to a role when the user picks manually
function addon:NoteScalePicked(scaleKey)
    local _, class = UnitClass("player")
    local scale = self:GetScale(scaleKey)
    if not (class and scale and scale.class == class and self.db) then return end
    local role = scale.role or "dd"
    self.db.roleScales = self.db.roleScales or {}
    self.db.roleScales[class] = self.db.roleScales[class] or {}
    self.db.roleScales[class][role] = scaleKey
end

function addon:SetCustomCap(scaleKey, stat, value)
    if not self.db.customCaps then self.db.customCaps = {} end
    if not self.db.customCaps[scaleKey] then self.db.customCaps[scaleKey] = {} end
    self.db.customCaps[scaleKey][stat] = value
    if self.ClearUpgradeCache then self:ClearUpgradeCache() end
end

function addon:HasCaps(scaleKey)
    local scale = self:GetScale(scaleKey)
    return (scale and scale.caps) ~= nil
        or (self.db.customCaps and self.db.customCaps[scaleKey]) ~= nil
end

-- player's current rating for a capped stat (from gear + buffs)
function addon:GetPlayerRating(scaleKey, stat)
    if stat == "Defense" then
        -- defense cap is a SKILL value (490/415), not a rating
        if not UnitDefense then return 0 end
        local base, mod = UnitDefense("player")
        return (base or 0) + (mod or 0)
    end
    if not GetCombatRating then return 0 end
    if stat == "Hit" then
        local scale = self:GetScale(scaleKey)
        local cr = (scale and scale.hitCR) or CR_HIT_MELEE
        return GetCombatRating(cr) or 0
    elseif stat == "SpellHit" then
        return GetCombatRating(CR_HIT_SPELL) or 0
    elseif stat == "Expertise" then
        return GetCombatRating(CR_EXPERTISE) or 0
    end
    return 0
end

-- ==================== WEIGHT IMPORT / EXPORT ====================
local STAT_ALIASES = {
    ap = "AttackPower", attackpower = "AttackPower",
    rap = "RangedAttackPower", rangedattackpower = "RangedAttackPower",
    feralap = "FeralAttackPower", feralattackpower = "FeralAttackPower",
    spellpower = "SpellPower", spelldamage = "SpellPower",
    healing = "Healing", healingpower = "Healing",
    hit = "Hit", hitrating = "Hit", meleehit = "Hit",
    spellhit = "SpellHit", spellhitrating = "SpellHit",
    crit = "Crit", critrating = "Crit", criticalstrike = "Crit",
    spellcrit = "SpellCrit", spellcritrating = "SpellCrit",
    haste = "Haste", hasterating = "Haste",
    spellhaste = "SpellHaste", spellhasterating = "SpellHaste",
    armorpen = "ArmorPen", armorpenetration = "ArmorPen",
    expertise = "Expertise", expertiserating = "Expertise",
    defense = "Defense", defenserating = "Defense",
    dodge = "Dodge", dodgerating = "Dodge",
    parry = "Parry", parryrating = "Parry",
    block = "BlockRating", blockrating = "BlockRating",
    blockvalue = "BlockValue",
    resilience = "Resilience", resil = "Resilience",
    spellpen = "SpellPen", spellpenetration = "SpellPen",
    mp5 = "MP5", manaper5 = "MP5",
    hp5 = "HP5",
    armor = "Armor",
    dps = "WeaponDPS", weapondps = "WeaponDPS",
    str = "Strength", strength = "Strength",
    agi = "Agility", agility = "Agility",
    sta = "Stamina", stamina = "Stamina",
    int = "Intellect", intellect = "Intellect",
    spi = "Spirit", spirit = "Spirit",
}
-- internal names map to themselves (case-insensitive)
for _, stat in ipairs(addon.StatOrder) do
    STAT_ALIASES[string.lower(stat)] = stat
end

function addon:ImportWeights(text)
    local scaleKey = self:GetActiveScaleKey()
    if not scaleKey or not text or text == "" then return 0 end

    local count = 0
    for k, v in string.gmatch(text, "([%a_]+)%s*=%s*([%d%.%-]+)") do
        local stat = STAT_ALIASES[string.lower(k)]
        local n = tonumber(v)
        if stat and n then
            self:SetCustomWeight(scaleKey, stat, n)
            count = count + 1
        end
    end
    return count
end

function addon:ExportWeights()
    local scaleKey = self:GetActiveScaleKey()
    local scale = self:GetScale(scaleKey)
    if not scale then return "" end

    local parts = {}
    for _, stat in ipairs(self.StatOrder) do
        local w = self:GetWeight(scaleKey, stat)
        if w and w ~= 0 then
            table.insert(parts, stat .. "=" .. w)
        end
    end
    return 'SentinelUI "' .. self:GetScaleName(scale) .. '": ' .. table.concat(parts, ", ")
end

-- Helper: GetTabPoints (handles API variations between clients)
local function GetTabPoints(tabIndex, isInspect)
    if not GetTalentTabInfo then return 0 end
    local t1, t2, t3, t4, t5 = GetTalentTabInfo(tabIndex, isInspect)
    if type(t1) == "number" then
        return tonumber(t5) or 0
    else
        return tonumber(t3) or 0
    end
end

-- total score of the equipped gear under one scale — used to resolve
-- ambiguous specs (hybrid talent builds, feral cat vs. bear)
local function GearMatchScore(scaleKey, unit)
    local total = 0
    unit = unit or "player"
    for slot = 1, 18 do
        if slot ~= 4 and slot ~= 19 then
            local link = GetInventoryItemLink(unit, slot)
            if link then
                total = total + (addon:GetItemScore(link, scaleKey) or 0)
            end
        end
    end
    return total
end

-- shared free-tree logic: pick a scale from a point distribution for
-- any unit ("player" or an inspected target). returns key, bestTab
local function PickScaleFromPts(class, pts, unit)
    local mapping = SPEC_SCALE[class]
    if not mapping then
        return addon:ScaleKeyForRole(class, "dd"), nil
    end
    local totalPoints = pts[1] + pts[2] + pts[3]
    local order = { 1, 2, 3 }
    table.sort(order, function(a, b) return pts[a] > pts[b] end)
    local bestTab = order[1]
    if totalPoints <= 0 then
        bestTab = DEFAULT_TAB[class] or 1
    end
    local candidates = {}
    local function AddTab(tab)
        for _, k in ipairs(mapping[tab] or {}) do
            table.insert(candidates, k)
        end
    end
    AddTab(bestTab)
    if totalPoints > 0 then
        for i = 2, 3 do
            local tab = order[i]
            if pts[tab] > 0 and (pts[bestTab] - pts[tab]) <= HYBRID_GAP then
                AddTab(tab)
            end
        end
    end
    local key
    if #candidates == 1 then
        key = candidates[1]
    elseif class == "DRUID" then
        local power = UnitPowerType and UnitPowerType(unit or "player")
        if power == 1 then
            key = "DruidBear"
        elseif power == 3 then
            key = "DruidCat"
        end
    end
    if not key then
        local bestScore = -1
        for _, k in ipairs(candidates) do
            local s = GearMatchScore(k, unit)
            if s > bestScore then
                bestScore, key = s, k
            end
        end
        key = key or candidates[1]
    end
    return key or (mapping[bestTab] and mapping[bestTab][1]) or mapping[1][1], bestTab
end

function addon:DetectScale()
    local _, class = UnitClass("player")
    if not class then return nil end

    -- ===== modern clients (MoP/Legion/retail/"Forever"): real spec ids
    if GetSpecialization and GetSpecializationInfo then
        local idx = GetSpecialization()
        local specID = idx and select(1, GetSpecializationInfo(idx))
        local key = specID and SPECID_SCALE[specID]
        if not key and specID then
            local role = SPECID_ROLE[specID]
            if not role and GetSpecializationRole then
                local r = GetSpecializationRole(idx)
                role = (r == "TANK") and "tank" or (r == "HEALER") and "heal" or "dd"
            end
            role = role or "dd"
            key = self:ScaleKeyForRole(class, role)
        end
        key = key or self:ScaleKeyForRole(class, "dd")
        self.detectedScale = key
        self.detectedTab = idx
        self.detectedPts = nil
        return key
    end

    local mapping = SPEC_SCALE[class]
    if not mapping then
        -- class without tree mapping (new classes on old clients can't
        -- happen, but stay safe): generic dps
        local key = self:ScaleKeyForRole(class, "dd")
        self.detectedScale = key
        return key
    end

    -- ===== Cata: spec is fixed by GetPrimaryTalentTree but the free
    -- talent points inside the trees still exist
    if GetPrimaryTalentTree and not GetSpecialization then
        local pts = { 0, 0, 0 }
        for i = 1, 3 do pts[i] = GetTabPoints(i) end
        local tab = GetPrimaryTalentTree()
        local key
        if tab and mapping[tab] then
            key = mapping[tab][1]
            -- druid feral shares the tree: gear decides cat vs bear
            if #mapping[tab] > 1 then
                local bestScore = -1
                for _, k in ipairs(mapping[tab]) do
                    local s = GearMatchScore(k)
                    if s > bestScore then bestScore, key = s, k end
                end
            end
        end
        if not key then
            -- no points spent yet -> dominant tree by points, else default
            local order = { 1, 2, 3 }
            table.sort(order, function(a, b) return pts[a] > pts[b] end)
            local bt = (pts[order[1]] > 0) and order[1] or (DEFAULT_TAB[class] or 1)
            key = mapping[bt] and mapping[bt][1]
        end
        key = key or self:ScaleKeyForRole(class, "dd")
        self.detectedScale = key
        self.detectedTab = tab
        self.detectedPts = pts
        return key
    end

    -- ===== Era / TBC / WotLK: free 3-tree talent system

    -- TBC free talent trees: 1 point per level starting at level 10.
    -- below that (and on unspecced characters) every tree reads 0.
    local pts = { 0, 0, 0 }
    if (UnitLevel("player") or 1) >= 10 then
        for i = 1, 3 do
            pts[i] = GetTabPoints(i)
        end
    end

    local key, bestTab = PickScaleFromPts(class, pts, "player")
    self.detectedScale = key
    self.detectedTab = bestTab
    self.detectedPts = pts
    return key
end

-- spec of any other unit (inspected targets): same free-tree logic as
-- DetectScale, reading the target's talents via the inspect flag.
-- for the own player the regular (non-inspect) reading must be used
function addon:DetectUnitScale(unit)
    local _, class = UnitClass(unit)
    if not class then return nil end
    if UnitIsUnit(unit, "player") then
        return self:GetActiveScaleKey(), self.detectedPts
    end
    local pts = { 0, 0, 0 }
    for i = 1, 3 do
        pts[i] = GetTabPoints(i, true)
    end
    local key = PickScaleFromPts(class, pts, unit)
    return key, pts
end

function addon:GetActiveScaleKey()
    if self.db and self.db.scale and self.db.scale ~= "auto" then
        return self.db.scale
    end
    if not self.detectedScale then
        return self:DetectScale()
    end
    return self.detectedScale
end

function addon:SetScale(key)
    self.db.scale = key
end

-- ==================== GEM RECOMMENDATION ====================
-- which stats a socket color can provide -> pick highest weighted
local GEM_COLOR_STATS = {
    SocketRed    = { "Strength", "Agility", "Intellect", "AttackPower", "SpellPower", "Healing", "Parry", "Dodge" },
    SocketYellow = { "Crit", "SpellCrit", "Hit", "SpellHit", "Haste", "SpellHaste", "Defense", "Resilience", "Intellect" },
    SocketBlue   = { "Stamina", "Spirit", "MP5", "SpellPen" },
}

-- TBC blue-quality gem itemIDs per stat & gem color; the table also
-- serves hybrid gems (purple=red+blue, orange=red+yellow,
-- green=yellow+blue). Only verified IDs — missing entries fall back
-- to the stat name.
local GEM_ID = {
    Strength    = { red = 24027, purple = 24054 }, -- Bold Living Ruby / Sovereign Nightseye
    Agility     = { red = 24028, purple = 24055 }, -- Delicate Living Ruby / Shifting Nightseye
    AttackPower = { red = 24031 },                 -- Bright Living Ruby
    SpellPower  = { red = 24030, purple = 24056 }, -- Runed Living Ruby / Glowing Nightseye
    Healing     = { red = 24029 },                 -- Teardrop Living Ruby
    Dodge       = { red = 24032 },                 -- Subtle Living Ruby
    Stamina     = { blue = 24033 },                -- Solid Star of Elune
    MP5         = { blue = 24037 },                -- Lustrous Star of Elune
    Spirit      = { blue = 24038 },                -- Sparkling Star of Elune
    SpellPen    = { blue = 24039 },                -- Stormy Star of Elune
    Intellect   = { yellow = 24047 },              -- Brilliant Dawnstone
    Crit        = { yellow = 24048 },              -- Smooth Dawnstone
    SpellHit    = { yellow = 24049 },              -- Great Dawnstone
    SpellCrit   = { yellow = 24050 },              -- Gleaming Dawnstone
    Hit         = { yellow = 24051 },              -- Rigid Dawnstone
    Defense     = { yellow = 24052 },              -- Thick Dawnstone
    Resilience  = { yellow = 24053 },              -- Mystic Dawnstone
}

-- which gem columns may fill a socket key
local SOCK_COLS = {
    SocketRed    = { "red", "purple", "orange" },
    SocketYellow = { "yellow", "orange", "green" },
    SocketBlue   = { "blue", "purple", "green" },
    SocketAny    = { "red", "yellow", "blue", "purple", "orange", "green" },
}

-- meta gems by role; caster dps override to Chaotic Skyfire
local META_ID = {
    dd     = 32409, -- Relentless Earthstorm Diamond (+12 agi, +3% crit dmg)
    tank   = 32410, -- Tenacious Earthstorm Diamond (+12 defense)
    healer = 25897, -- Bracing Earthstorm Diamond (+healing, -threat)
}
local META_CASTER = 34220 -- Chaotic Skyfire Diamond

-- returns gem itemID (or nil) plus the winning stat for a socket
function addon:GetBestGemID(socketKey, scaleKey)
    if socketKey == "SocketMeta" then
        local scale = self:GetScale(scaleKey)
        local w = scale and scale.weights or {}
        if (w.SpellPower or 0) + (w.Healing or 0) >= 0.5
            and self:GetScaleRole(scaleKey) == "dd" then
            return META_CASTER, nil
        end
        return META_ID[self:GetScaleRole(scaleKey)] or META_ID.dd, nil
    end
    local stat = self:GetBestGemStat(socketKey, scaleKey)
    if not stat then return nil end
    local g = GEM_ID[stat]
    if g then
        for _, col in ipairs(SOCK_COLS[socketKey] or {}) do
            if g[col] then return g[col], stat end
        end
    end
    return nil, stat
end

function addon:GetBestGemStat(socketKey, scaleKey)
    local candidates = GEM_COLOR_STATS[socketKey]
    if not candidates then
        if socketKey == "SocketAny" then
            candidates = {}
            for _, list in pairs(GEM_COLOR_STATS) do
                for _, s in ipairs(list) do table.insert(candidates, s) end
            end
        else
            return nil
        end
    end
    local best, bestW
    for _, stat in ipairs(candidates) do
        local w = self:GetWeight(scaleKey, stat)
        if bestW == nil or w > bestW then
            best, bestW = stat, w
        end
    end
    return best
end

-- ==================== FULL SETTINGS EXPORT / IMPORT ================
-- serializes the whole config (weights, caps, outfits, wishlist,
-- toggles) into one string; char profiles stay per-character
local EXPORT_TABLE_KEYS = {
    "roleScales", "autoOutfits", "savedScales", "customWeights",
    "customCaps", "wishlist", "outfits",
}

local function Serialize(v)
    local t = type(v)
    if t == "number" or t == "boolean" then return tostring(v) end
    if t == "string" then return string.format("%q", v) end
    if t == "table" then
        local parts = {}
        for k, x in pairs(v) do
            parts[#parts + 1] = "[" .. Serialize(k) .. "]=" .. Serialize(x)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "nil"
end

function addon:ExportSettings()
    local out = {}
    for k, v in pairs(self.db or {}) do
        if type(v) == "boolean" or type(v) == "number" then
            out[k] = v
        end
    end
    for _, k in ipairs(EXPORT_TABLE_KEYS) do
        if self.db[k] ~= nil then out[k] = self.db[k] end
    end
    return "RLBISET1" .. Serialize(out)
end

function addon:ImportSettings(text)
    if not text or not text:find("RLBISET1") then return 0 end
    local body = text:match("RLBISET1(.+)")
    local ldr = loadstring or _G.load -- newer clients only ship load()
    local fn = ldr and ldr("return " .. body)
    if not fn then return 0 end
    local ok, tbl = pcall(fn)
    if not ok or type(tbl) ~= "table" then return 0 end
    local n = 0
    for k, v in pairs(tbl) do
        self.db[k] = v
        n = n + 1
    end
    if self.ClearUpgradeCache then self:ClearUpgradeCache() end
    if self.RefreshSettings then self:RefreshSettings() end
    if self.RefreshTools then self:RefreshTools() end
    if self.RefreshOutfitList then self:RefreshOutfitList() end
    if self.UpdateStatsPanel then self:UpdateStatsPanel() end
    return n
end
