local addon = RLBetterItem

-- ==================== ADDON RADAR ==============================
-- Detects other RLBetterItem users via addon messages - the same
-- invisible data channels other addons use for their version checks:
-- GUILD, PARTY, RAID, INSTANCE_CHAT and direct WHISPER replies.
-- Addon messages NEVER appear as chat text; nothing is sent on
-- SAY/YELL or any public channel.

local PREFIX = "RLBetterItem"
local radarUsers = {}          -- sender -> {ver, verNum, channel, last}
local repliedTo = {}           -- sender -> last whisper-reply time
local notifiedFor = {}         -- sender -> highest verNum we already printed
local detectedNewer = false    -- update notice printed once
local newestSeenVer = nil      -- highest version spotted so far
local lastAnnounce = 0

local function ParseVersion(v)
    local parts = {strsplit(".", tostring(v or ""))}
    local result = 0
    for i = 1, math.min(#parts, 4) do
        result = result * 100 + (tonumber(parts[i]) or 0)
    end
    return result
end
addon.ParseVersion = ParseVersion

local function Send(msg, channel, target)
    if not addon.db or addon.db.radar == false then return end
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, channel, target)
    elseif SendAddonMessage then
        pcall(SendAddonMessage, PREFIX, msg, channel, target)
    end
end

local function Announce()
    local now = GetTime()
    if now - lastAnnounce < 5 then return end -- burst guard
    lastAnnounce = now
    local msg = "Version:" .. tostring(addon.version)
    if IsInGuild and IsInGuild() then Send(msg, "GUILD") end
    if IsInGroup and IsInGroup() then
        Send(msg, (IsInRaid and IsInRaid()) and "RAID" or "PARTY")
    end
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup
        and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        Send(msg, "INSTANCE_CHAT")
    end
end

-- manual refresh from the players tab
function addon:RefreshRadar()
    lastAnnounce = 0
    Announce()
end

function addon:GetRadarUsers()
    local out = {}
    local my = ParseVersion(addon.version)
    for name, e in pairs(radarUsers) do
        out[#out + 1] = {
            name = name,
            ver = e.ver,
            rel = e.verNum > my and 1 or (e.verNum < my and -1 or 0),
            channel = e.channel,
            ago = math.floor(GetTime() - e.last),
        }
    end
    table.sort(out, function(a, b)
        if a.rel ~= b.rel then return a.rel > b.rel end -- newer first
        return a.name < b.name
    end)
    return out
end

-- highest version spotted that is newer than ours (nil = up to date)
function addon:GetNewestSeenVersion()
    return newestSeenVer
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
        elseif RegisterAddonMessagePrefix then
            pcall(RegisterAddonMessagePrefix, PREFIX)
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(5, function() Announce() end)
        end

    elseif event == "PLAYER_ENTERING_WORLD"
        or event == "GROUP_ROSTER_UPDATE" then
        -- announce after a short delay so roster/API state settles
        if C_Timer and C_Timer.After then
            C_Timer.After(3, function() Announce() end)
        end

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        if prefix ~= PREFIX or type(msg) ~= "string" then return end
        local ver = string.match(msg, "^Version:(.+)$")
        if not ver or not sender or sender == UnitName("player") then
            return
        end
        sender = string.match(sender, "^[^-]+") or sender -- short name
        local verNum = ParseVersion(ver)
        local first = not radarUsers[sender]
        radarUsers[sender] = {
            ver = ver, verNum = verNum,
            channel = channel, last = GetTime(),
        }
        if addon.RefreshRadarList then addon:RefreshRadarList() end

        -- newest version spotted anywhere (drives the tab banner)
        if verNum > ParseVersion(addon.version)
            and (not newestSeenVer
                or verNum > ParseVersion(newestSeenVer)) then
            newestSeenVer = ver
        end

        -- newer version seen -> one-shot update notice + per-player line,
        -- printed once per sender AND version per session (no spam)
        if verNum > ParseVersion(addon.version) then
            if addon.db and addon.db.versionNotify ~= false
                and (notifiedFor[sender] or 0) < verNum then
                notifiedFor[sender] = verNum
                addon:Print(string.format(addon:L("MSG_RADAR_NEWER"),
                    sender, ver, tostring(addon.version)))
            end
            if not detectedNewer then
                detectedNewer = true
                print("|cffFFD700[SentinelUI]|r " .. string.format(addon:L("MSG_NEWER_AVAILABLE"), sender, ver))
            end
        end

        -- answer once per sender so they can see us too
        if first and channel ~= "WHISPER" then
            local now = GetTime()
            if (repliedTo[sender] or 0) < now - 600 then
                repliedTo[sender] = now
                Send("Version:" .. tostring(addon.version), "WHISPER",
                    sender)
            end
        end
    end
end)
