local addon = RLBetterItem

-- ==================== PLAYER TOOLTIPS (self-built) ==================
-- class-colored name, guild+rank, target line, spec + GearScore/iLvl
-- of any hovered player (via inspect data), all toggleable in settings

local unitCache = {}   -- guid -> { ilvl, score, specKey, pts, t }
local inspected = {}   -- guid -> last NotifyInspect time
local CACHE_TTL = 120
-- the server rate-limits inspect requests; a tight hover throttle would make
-- the real inspect window (manually opened) starve -> empty paperdoll
local INSPECT_THROTTLE = 15

-- gear summary of a unit: avg item level + GearScore (see GearScore.lua),
-- the detected spec and the talent point distribution. items/class are kept
-- so uncached entries can be recomputed later without a fresh inspect
function addon:ComputeUnitGear(unit)
    local specKey, pts = self:DetectUnitScale(unit)
    local gs, ilvl, ready, links, class = self:GearScoreForUnit(unit)
    return {
        ilvl = ilvl,
        score = gs,
        ready = ready,
        items = links,
        class = class,
        specKey = specKey,
        pts = pts,
        t = GetTime(),
    }
end

local function ClassColor(unit)
    local _, class = UnitClass(unit)
    local c = class and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
    if not c then return "|cffffffff" end
    return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end

local function TargetName(unit)
    local t = unit .. "target"
    local name = UnitName(t)
    if not name then
        return "|cff808080—|r"
    end
    if UnitIsUnit(t, "player") then
        return "|cffffff00" .. addon:L("TT_YOU") .. "|r"
    elseif UnitIsUnit(t, unit) then
        return "|cffffffff" .. addon:L("TT_SELF") .. "|r"
    elseif UnitIsPlayer(t) then
        return ClassColor(t) .. name .. "|r"
    elseif UnitIsOtherPlayersPet and (UnitIsUnit(t, "pet") or UnitIsOtherPlayersPet(t)) then
        return "|cffffffff" .. name .. " (" .. addon:L("TT_PET") .. ")|r"
    end
    return "|cffffffff" .. name .. "|r"
end

local function RequestInspect(unit)
    -- CheckInteractDistance is protected in combat -> ADDON_ACTION_BLOCKED
    if InCombatLockdown and InCombatLockdown() then return end
    local guid = UnitGUID(unit)
    if not guid then return end
    if not CanInspect or not CanInspect(unit) then return end
    -- distIndex 1 = inspect range (~30 yd): skip instead of letting
    -- NotifyInspect spam "too far away" into UIErrorsFrame on every hover
    if CheckInteractDistance and not CheckInteractDistance(unit, 1) then return end
    -- never compete with a real inspect window: a hover request could replace
    -- the pending inspect the InspectFrame just asked for -> empty slots
    if InspectFrame and InspectFrame:IsShown() then return end
    local now = GetTime()
    if inspected[guid] and (now - inspected[guid]) < INSPECT_THROTTLE then return end
    inspected[guid] = now
    NotifyInspect(unit)
end

local function AddUnitLines(tip, unit)
    local db = addon.db
    if db.ttHideInCombat and InCombatLockdown and InCombatLockdown() then
        return
    end
    local tipName = tip.GetName and tip:GetName()

    -- first line: hide titles, class color, pvp icon (all optional)
    if tipName then
        local fs = _G[tipName .. "TextLeft1"]
        local txt = fs and fs:GetText()
        local name = UnitName(unit)
        if txt and name then
            local changed = false
            local new = txt
            if db.ttHideTitles then
                new = name -- strip "Name, Title" down to the bare name
                changed = true
            end
            if db.ttClassColor and not new:find("|c") then
                new = ClassColor(unit) .. new .. "|r"
                changed = true
            end
            if db.ttPvPIcon and UnitIsPVP and UnitIsPVP(unit)
                and not new:find("BattleMasterGossipIcon") then
                new = new .. "  |TInterface\\GossipFrame\\BattleMasterGossipIcon:0|t"
                changed = true
            end
            if changed then
                fs:SetText(new)
            end
        end
    end

    -- guild + rank: the default tooltip already prints the guild, so
    -- only append the rank to that line instead of adding a duplicate
    if db.ttGuild then
        local guild, rank = GetGuildInfo(unit)
        if guild and tipName and tip.NumLines then
            local found = false
            for i = 2, tip:NumLines() do
                local fs = _G[tipName .. "TextLeft" .. i]
                local txt = fs and fs:GetText()
                if txt and txt:find(guild, 1, true) then
                    found = true
                    if rank and rank ~= "" and not txt:find(rank, 1, true) then
                        fs:SetText(txt .. "  |cff888888" .. rank .. "|r")
                    end
                    break
                end
            end
            if not found then
                tip:AddLine("|cff00ff00<" .. guild .. ">|r" ..
                    ((rank and rank ~= "") and ("  |cff888888" .. rank .. "|r") or ""))
            end
        end
    end

    -- what the player is targeting
    if db.ttTarget and UnitIsConnected(unit) then
        tip:AddLine("|cff888888" .. addon:L("TT_TARGET") .. ":|r " .. TargetName(unit))
    end

    -- spec + gear score via inspect data
    if not (db.ttSpec or db.ttGearScore) then return end
    local guid = UnitGUID(unit)
    local info = guid and unitCache[guid]
    if UnitIsUnit(unit, "player") then
        info = addon:ComputeUnitGear(unit)
        if guid then unitCache[guid] = info end
    elseif not info or (GetTime() - info.t) > CACHE_TTL then
        RequestInspect(unit)
        return
    elseif info.ready == false then
        -- gear captured, item data still loading: recompute from the stored
        -- links (requests missing data again) instead of re-inspecting
        if info.items then
            local gs, ilvl, ready = addon:GearScoreForLinks(info.items, info.class)
            info.score, info.ilvl, info.ready = gs, ilvl, ready
            info.t = GetTime()
        end
        if info.ready == false then return end
    end
    if not info then return end

    if db.ttSpec and info.specKey then
        local specName = addon:GetScaleName(addon:GetScale(info.specKey))
        if specName then
            local dist = ""
            if info.pts then
                dist = string.format(" |cff888888(%d/%d/%d)|r",
                    info.pts[1], info.pts[2], info.pts[3])
            end
            tip:AddLine("|cffffd700" .. addon:L("TT_SPEC") .. ":|r " ..
                ClassColor(unit) .. specName .. "|r" .. dist)
        end
    end
    if db.ttGearScore and info.ilvl > 0 then
        local r, g, b = addon:GSQualityColor(info.score)
        tip:AddLine("|cffffd700" .. addon:L("TT_GEAR") .. ":|r " ..
            string.format("|cffffffffiLvl %.0f|r  ·  |cff%02x%02x%02xGS %.0f|r",
                info.ilvl, r * 255, g * 255, b * 255, info.score))
    end
end

-- dedupe flag is cleared when the tooltip wipes
GameTooltip:HookScript("OnTooltipCleared", function(tip)
    tip._rlUnitDone = nil
end)

GameTooltip:HookScript("OnTooltipSetUnit", function(tip)
    if not addon.db or not addon.db.unitTooltips then return end
    local _, unit = tip:GetUnit()
    if not unit or not UnitIsPlayer(unit) then return end
    -- per-guid dedupe: moving the mouse between players re-fires this
    -- without a clear, so only skip the SAME unit being re-rendered
    local guid = UnitGUID(unit)
    if guid and tip._rlUnitDone == guid then return end
    tip._rlUnitDone = guid or true
    AddUnitLines(tip, unit)
end)

-- when inspect data arrives: cache it and refresh the tooltip if the
-- player is still being hovered
local f = CreateFrame("Frame")
f:RegisterEvent("INSPECT_READY")
f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
f:SetScript("OnEvent", function(_, event, a1)
    -- item data we requested via RequestLoadItemDataByID arrived: refresh a
    -- unit tooltip that was drawn with missing data
    if event == "GET_ITEM_INFO_RECEIVED" then
        -- recompute every stale cache entry from its stored links - no new
        -- inspect needed, the gear table was captured at INSPECT_READY
        for _, info in pairs(unitCache) do
            if info.ready == false and info.items then
                local gs, ilvl, ready = addon:GearScoreForLinks(info.items, info.class)
                info.score, info.ilvl, info.ready = gs, ilvl, ready
            end
        end
        local _, unit = GameTooltip:GetUnit()
        if unit and UnitIsPlayer(unit) and addon.db and addon.db.unitTooltips then
            local g = UnitGUID(unit)
            if g and unitCache[g] then
                GameTooltip._rlUnitDone = nil
                GameTooltip:SetUnit(unit)
            end
        end
        return
    end
    local guid = a1
    if not guid then return end
    local _, unit = GameTooltip:GetUnit()
    local src
    if unit and UnitGUID(unit) == guid then
        src = unit
    elseif InspectFrame and InspectFrame.unit and UnitGUID(InspectFrame.unit) == guid then
        src = InspectFrame.unit
    elseif UnitGUID("target") == guid then
        src = "target"
    elseif UnitGUID("mouseover") == guid then
        src = "mouseover"
    end
    if src then
        unitCache[guid] = addon:ComputeUnitGear(src)
        -- refresh the open tooltip so the new lines appear
        if unit and UnitGUID(unit) == guid and addon.db and addon.db.unitTooltips then
            GameTooltip._rlUnitDone = nil
            GameTooltip:SetUnit(unit)
        end
    end
    if ClearInspectPlayer and not (InspectFrame and InspectFrame:IsShown()) then
        ClearInspectPlayer()
    end
end)

-- power bar under the tooltip (mana/rage/energy in power color)
local powerBar
local function UpdatePowerBar()
    if not (addon.db and addon.db.ttPowerBar) then
        if powerBar then powerBar:Hide() end
        return
    end
    local _, unit = GameTooltip:GetUnit()
    if not (GameTooltip:IsShown() and unit and UnitIsPlayer(unit)) then
        if powerBar then powerBar:Hide() end
        return
    end
    if not powerBar then
        powerBar = CreateFrame("StatusBar", nil, GameTooltip)
        powerBar:SetHeight(6)
        powerBar:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 2, -2)
        powerBar:SetPoint("TOPRIGHT", GameTooltip, "BOTTOMRIGHT", -2, -2)
        powerBar:SetStatusBarTexture(
            "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill")
    end
    local _, ptype = UnitPowerType(unit)
    local c = PowerBarColor and PowerBarColor[ptype]
    if c then
        powerBar:SetStatusBarColor(c.r, c.g, c.b)
    else
        powerBar:SetStatusBarColor(0, 0, 1)
    end
    powerBar:SetMinMaxValues(0, math.max(1, UnitPowerMax(unit)))
    powerBar:SetValue(UnitPower(unit))
    powerBar:Show()
end
if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(0.2, UpdatePowerBar)
end

-- instant fade: kill the fade-out animation entirely
hooksecurefunc(GameTooltip, "FadeOut", function(tip)
    if addon.db and addon.db.ttInstantFade then
        tip:Hide()
    end
end)

-- mouse anchor: tooltips appear at the cursor instead of bottom-right
if GameTooltip_SetDefaultAnchor then
    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tip, parent)
        if addon.db and addon.db.ttMouseAnchor and tip == GameTooltip then
            tip:SetOwner(parent, "ANCHOR_CURSOR")
        end
    end)
end
