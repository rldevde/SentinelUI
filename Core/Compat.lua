-- API compatibility layer: one code base for Retail, Classic Era, TBC/Anniversary, Wrath, Mists.
local _, ns = ...
local S = ns.S

local strmatch = strmatch
local project = WOW_PROJECT_ID
S.isRetail = project == WOW_PROJECT_MAINLINE
S.isClassic = project == WOW_PROJECT_CLASSIC
S.isTBC = project == (WOW_PROJECT_BURNING_CRUSADE_CLASSIC or 5)
S.isWrath = project == (WOW_PROJECT_WRATH_CLASSIC or 11)
S.isCata = project == (WOW_PROJECT_CATACLYSM_CLASSIC or 14)
S.isMists = project == (WOW_PROJECT_MISTS_CLASSIC or 19)
S.flavor = S.isRetail and "Retail" or S.isClassic and "Classic" or S.isTBC and "TBC" or S.isWrath and "Wrath" or S.isCata and "Cata" or S.isMists and "Mists" or ("Project" .. tostring(project))

local _, build, _, interface = GetBuildInfo()
S.interface = interface
S.myName = UnitName("player")
S.myRealm = GetRealmName()
S.myClass = select(2, UnitClass("player"))
S.myFaction = UnitFactionGroup("player")
S.myLevel = UnitLevel("player")

S.BackdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil

function S.IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value) or false
end

-- AddOns
S.IsAddOnLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
S.LoadAddOn = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
S.GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata

-- Spells
function S.GetSpellInfo(spell)
	if not spell then return end
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(spell)
		if info then return info.name, nil, info.iconID, info.castTime, info.minRange, info.maxRange, info.spellID end
		return
	end
	if GetSpellInfo then return GetSpellInfo(spell) end
end

function S.GetSpellCooldown(spell)
	if C_Spell and C_Spell.GetSpellCooldown then
		local info = C_Spell.GetSpellCooldown(spell)
		if info then return info.startTime, info.duration, info.isEnabled, info.modRate end
		return
	end
	if GetSpellCooldown then return GetSpellCooldown(spell) end
end

-- Items
S.GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
S.GetItemQualityColor = (C_Item and C_Item.GetItemQualityColor) or GetItemQualityColor
S.GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
S.GetDetailedItemLevelInfo = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo

-- Containers
local C = C_Container
S.GetContainerNumSlots = (C and C.GetContainerNumSlots) or GetContainerNumSlots
S.GetContainerNumFreeSlots = (C and C.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
S.GetContainerItemLink = (C and C.GetContainerItemLink) or GetContainerItemLink
S.PickupContainerItem = (C and C.PickupContainerItem) or PickupContainerItem
S.SplitContainerItem = (C and C.SplitContainerItem) or SplitContainerItem
S.UseContainerItem = (C and C.UseContainerItem) or UseContainerItem
S.GetContainerItemCooldown = (C and C.GetContainerItemCooldown) or GetContainerItemCooldown
S.SortBags = (C and C.SortBags) or SortBags
S.SortBankBags = (C and C.SortBankBags) or SortBankBags
S.ContainerIDToInventoryID = (C and C.ContainerIDToInventoryID) or ContainerIDToInventoryID

function S.GetContainerItemInfo(bag, slot)
	if C and C.GetContainerItemInfo then
		return C.GetContainerItemInfo(bag, slot)
	end
	if not GetContainerItemInfo then return nil end
	local icon, count, locked, quality, readable, lootable, link, filtered, noValue, itemID = GetContainerItemInfo(bag, slot)
	if not icon then return nil end
	return { iconFileID = icon, stackCount = count, isLocked = locked, quality = quality, isReadable = readable, hasLoot = lootable, hyperlink = link, isFiltered = filtered, hasNoValue = noValue, itemID = itemID }
end

S.NUM_BAG_SLOTS = NUM_BAG_SLOTS or 4
S.NUM_BANKBAGSLOTS = NUM_BANKBAGSLOTS or 7
-- First bank bag container id: 6 on Retail (after the reagent bag), 5 on Classic.
S.BANK_BAG_FIRST = (Enum and Enum.BagIndex and Enum.BagIndex.Bankbag_1) or (S.NUM_BAG_SLOTS + 1)
S.BANK_CONTAINER = BANK_CONTAINER or -1
S.BACKPACK_CONTAINER = BACKPACK_CONTAINER or 0
-- Keyring only exists on Classic flavors (keys were removed on Retail).
S.KEYRING_CONTAINER = (not S.isRetail) and (KEYRING_CONTAINER or -2) or nil
-- Reagent bag only exists on Retail. On Classic its index (5) collides with the first
-- bank bag, which would show bank items inside the inventory (duplicate items).
S.REAGENTBAG_CONTAINER = S.isRetail and (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or nil

-- Auras: always returns a table similar to C_UnitAuras AuraData
local auraCache = {}
function S.GetAura(unit, index, filter)
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		local a = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
		-- modern API can return nil where classic UnitAura still has data on
		-- some clients (e.g. hostile NPCs) - fall through to UnitAura then
		if a then return a end
	end
	if UnitAura then
		local name, icon, count, debuffType, duration, expirationTime, source, isStealable, _, spellId = UnitAura(unit, index, filter)
		if not name then return nil end
		local a = auraCache
		a.name, a.icon, a.applications, a.dispelName, a.duration, a.expirationTime = name, icon, count, debuffType, duration, expirationTime
		a.sourceUnit, a.isStealable, a.spellId, a.auraInstanceID = source, isStealable, spellId, nil
		a.isHelpful = filter and filter:find("HELPFUL") and true or false
		return a
	end
end

-- legacy-tuple drop-in for modules written against the old UnitAura() API
-- (the global is gone on modern clients; C_UnitAuras returns a table)
function S.UnitAura(unit, index, filter)
	local a = S.GetAura(unit, index, filter)
	if not a then return end
	return a.name, a.icon, a.applications or 0, a.dispelName,
		a.duration or 0, a.expirationTime or 0, a.sourceUnit,
		a.nameplateShowPersonal, a.nameplateShowAll, a.spellId,
		a.canApplyAura, a.isBossAura, a.isFromPlayerOrPlayerPet,
		a.nameplateShowPersonal, a.points and a.points[1]
end

-- Mouse focus
S.GetMouseFoci = GetMouseFoci
function S.GetMouseFocus()
	if GetMouseFoci then
		local foci = GetMouseFoci()
		if foci and foci[1] then return foci[1] end
	end
	if GetMouseFocus then return GetMouseFocus() end
end

-- Specialization / talents
function S.GetSpecName()
	if GetSpecialization and GetSpecializationInfo then
		local spec = GetSpecialization()
		if spec then return select(2, GetSpecializationInfo(spec)) end
	end
	if GetTalentTabInfo then
		local best, bestName = -1, nil
		for i = 1, (GetNumTalentTabs and GetNumTalentTabs() or 3) do
			local r1, r2, r3, r4, r5 = GetTalentTabInfo(i)
			-- Classic returns (name, icon, points, ...) / later (id, name, desc, icon, points)
			local name, points
			if type(r1) == "number" and type(r2) == "string" then name, points = r2, r5 else name, points = r1, r3 end
			if type(points) == "number" and points > best then best, bestName = points, name end
		end
		return bestName
	end
end

-- Group communication
-- Chat channel matching the current group (instance group > raid > party).
function S.GroupChannel()
	if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
	if IsInRaid and IsInRaid() then return "RAID" end
	if IsInGroup and IsInGroup() then return "PARTY" end
end

S.RegisterAddonPrefix = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix

function S.SendAddonMessage(prefix, msg, channel, target)
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		pcall(C_ChatInfo.SendAddonMessage, prefix, msg, channel, target)
	elseif SendAddonMessage then
		pcall(SendAddonMessage, prefix, msg, channel, target)
	end
end

S.IsSpellKnown = (C_Spell and C_Spell.IsSpellKnown) or IsSpellKnown

-- Durability
function S.GetDurabilityPercent()
	local lowest = 1
	for slot = 1, 18 do
		local cur, max = GetInventoryItemDurability(slot)
		if cur and max and max > 0 then lowest = math.min(lowest, cur / max) end
	end
	return lowest * 100
end

-- Friends / guild
function S.GetNumOnlineFriends()
	if C_FriendList and C_FriendList.GetNumOnlineFriends then
		return C_FriendList.GetNumOnlineFriends() or 0, C_FriendList.GetNumFriends() or 0
	end
	if not GetNumFriends then return 0, 0 end
	local total, online = GetNumFriends()
	return online or 0, total or 0
end

local guildRosterT = 0
function S.GuildRoster(force)
	-- the server throttles roster queries. Several modules fire this on
	-- login bursts and on every guild system message; the spam starves
	-- Blizzard's own request when the GuildFrame opens -> "0 members".
	-- Coalesce to one real request per few seconds unless forced.
	local now = GetTime()
	if not force and now - guildRosterT < 4 then return end
	guildRosterT = now
	if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() elseif GuildRoster then GuildRoster() end
end

-- Unit colors
function S.ClassColor(class)
	local c = class and ((CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or RAID_CLASS_COLORS[class])
	return c or { r = 1, g = 1, b = 1 }
end

function S.UnitColor(unit)
	if UnitIsPlayer(unit) then
		return S.ClassColor(select(2, UnitClass(unit)))
	end
	if UnitIsTapDenied and UnitIsTapDenied(unit) then return { r = 0.55, g = 0.55, b = 0.55 } end
	local reaction = UnitReaction(unit, "player")
	local c = reaction and FACTION_BAR_COLORS[reaction]
	return c or { r = 0.8, g = 0.8, b = 0.2 }
end

-- Range check for Mists/Retail/Classic
function S.UnitInRange(unit)
	if UnitIsUnit(unit, "player") then return true end
	local inRange, checked = UnitInRange(unit)
	if S.IsSecret(inRange) then return true end
	if checked and not inRange then return false end
	if not checked and CheckInteractDistance and not UnitIsConnected(unit) then return false end
	return true
end

-- Blizzard bug fix: Blizzard_UnitPopup's GetFullPlayerName concatenates
-- name.."-"..server and errors when the target's realm is missing from
-- contextData (e.g. connected-realm players). Fill the server before it runs.
local function PatchUnitPopup()
	local myRealm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName()
	local function Wrap(fn)
		return function(...)
			for i = 1, select("#", ...) do
				local a = select(i, ...)
				if type(a) == "table" and a.name ~= nil and a.server == nil then
					local nameRealm = strmatch(a.name, "%-(.+)$")
					local unitRealm
					if a.unit then
						local ok, _, r = pcall(UnitName, a.unit)
						if ok and r and r ~= "" then unitRealm = r end
					end
					a.server = nameRealm or unitRealm or myRealm
				end
			end
			return fn(...)
		end
	end
	if type(_G.GetFullPlayerName) == "function" then
		_G.GetFullPlayerName = Wrap(_G.GetFullPlayerName)
	end
	local util = _G.UnitPopupSharedUtil
	if type(util) == "table" and type(util.GetFullPlayerName) == "function" then
		util.GetFullPlayerName = Wrap(util.GetFullPlayerName)
	end
end
local suiPopFix = CreateFrame("Frame")
suiPopFix:RegisterEvent("ADDON_LOADED")
suiPopFix:SetScript("OnEvent", function(_, _, addon)
	if addon == "Blizzard_UnitPopup" then pcall(PatchUnitPopup) end
end)
if S.IsAddOnLoaded and S.IsAddOnLoaded("Blizzard_UnitPopup") then pcall(PatchUnitPopup) end
