local _, ns = ...
local S = ns.S
local L = S.L
local DT = S:NewModule("DataTexts")

local _G = _G
local pairs, ipairs, format, floor, max, min, select, tinsert, sort = pairs, ipairs, format, math.floor, math.max, math.min, select, tinsert, table.sort

DT.registry = {}
DT.panels = {}
DT.slots = {}

local function Value(text) return "|cff" .. S.accentHex .. text .. "|r" end
local function Label(text) return DT.db.noLabel and "" or (text .. ": ") end

function DT:Register(name, def)
	def.name = name
	self.registry[name] = def
end

function DT:Tooltip(slot)
	GameTooltip:SetOwner(slot, "ANCHOR_NONE")
	local _, y = slot:GetCenter()
	if y and y < UIParent:GetHeight() / 2 then
		GameTooltip:SetPoint("BOTTOM", slot, "TOP", 0, 6)
	else
		GameTooltip:SetPoint("TOP", slot, "BOTTOM", 0, -6)
	end
	GameTooltip:ClearLines()
	return GameTooltip
end

-- Data texts ----------------------------------------------------------------
DT:Register("Time", {
	interval = 1,
	update = function(slot)
		local h, m
		if DT.db.localTime then h, m = tonumber(date("%H")), tonumber(date("%M")) else h, m = GetGameTime() end
		if DT.db.timeFormat24 then
			slot.text:SetText(Value(format("%02d:%02d", h, m)))
		else
			local ampm = h >= 12 and "PM" or "AM"
			h = h % 12
			if h == 0 then h = 12 end
			slot.text:SetText(Value(format("%d:%02d", h, m)) .. " " .. ampm)
		end
	end,
	enter = function(slot)
		local tt = DT:Tooltip(slot)
		tt:AddLine(TIMEMANAGER_TITLE or "Time", S.accent.r, S.accent.g, S.accent.b)
		local sh, sm = GetGameTime()
		tt:AddDoubleLine(L["Local Time"], date("%H:%M"), 1, 1, 1, 1, 1, 1)
		tt:AddDoubleLine(L["Realm Time"], format("%02d:%02d", sh, sm), 1, 1, 1, 1, 1, 1)
		if GetNumSavedInstances then
			local any
			for i = 1, GetNumSavedInstances() do
				local name, _, reset, _, locked, extended, _, _, _, diffName = GetSavedInstanceInfo(i)
				if locked or extended then
					if not any then tt:AddLine(" ") tt:AddLine(L["Saved Raids"], S.accent.r, S.accent.g, S.accent.b) any = true end
					tt:AddDoubleLine(name .. " |cffaaaaaa(" .. (diffName or "") .. ")|r", SecondsToTime(reset, true), 1, 1, 1, 0.8, 0.8, 0.8)
				end
			end
		end
		tt:AddLine(" ")
		tt:AddLine(L["Click: Calendar / Stopwatch"], 0.7, 0.7, 0.7)
		tt:Show()
	end,
	click = function(_, button)
		if button == "RightButton" or not ToggleCalendar then
			if not TimeManager_Toggle then S.LoadAddOn("Blizzard_TimeManager") end
			if TimeManager_Toggle then TimeManager_Toggle() end
		else
			ToggleCalendar()
		end
	end,
})

DT:Register("System", {
	interval = 1,
	update = function(slot)
		local fps = floor(GetFramerate())
		local _, _, home, world = GetNetStats()
		local ms = max(home or 0, world or 0)
		local fc = fps >= 50 and "|cff40ff40" or fps >= 25 and "|cffffcc00" or "|cffff4040"
		local mc = ms <= 100 and "|cff40ff40" or ms <= 250 and "|cffffcc00" or "|cffff4040"
		slot.text:SetText(fc .. fps .. "|r fps  " .. mc .. ms .. "|r ms")
	end,
	enter = function(slot)
		local tt = DT:Tooltip(slot)
		local _, _, home, world = GetNetStats()
		tt:AddLine(L["System"], S.accent.r, S.accent.g, S.accent.b)
		tt:AddDoubleLine(L["Home Latency"], home .. " ms", 1, 1, 1, 1, 1, 1)
		tt:AddDoubleLine(L["World Latency"], world .. " ms", 1, 1, 1, 1, 1, 1)
		tt:AddLine(" ")
		if UpdateAddOnMemoryUsage then UpdateAddOnMemoryUsage() end
		local list, total = {}, 0
		local GetNum = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
		local GetInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
		-- CPU profiling needs scriptProfile=1 (client restart); memory always works
		local cpuOn = GetCVarBool and GetCVarBool("scriptProfile") and UpdateAddOnCPUUsage and GetAddOnCPUUsage
		if cpuOn then UpdateAddOnCPUUsage() end
		for i = 1, GetNum() do
			local mem = GetAddOnMemoryUsage and GetAddOnMemoryUsage(i) or 0
			local cpu = cpuOn and GetAddOnCPUUsage(i) or 0
			if mem > 0 or cpu > 0 then
				local name = GetInfo(i)
				tinsert(list, { name, mem, cpu })
				total = total + mem
			end
		end
		sort(list, function(a, b) return (a[3] > 0 or b[3] > 0) and a[3] > b[3] or a[2] > b[2] end)
		local function fmt(kb) return kb > 1024 and format("%.2f MB", kb / 1024) or format("%.0f KB", kb) end
		tt:AddDoubleLine(L["Total Memory"], fmt(total), 1, 1, 1, S.accent.r, S.accent.g, S.accent.b)
		for i = 1, min(#list, IsShiftKeyDown() and 60 or 15) do
			local right = cpuOn and format("%s | %.0f ms", fmt(list[i][2]), list[i][3]) or fmt(list[i][2])
			tt:AddDoubleLine(list[i][1], right, 0.9, 0.9, 0.9, 0.8, 0.8, 0.8)
		end
		tt:AddLine(" ")
		if not cpuOn and GetCVarBool then
			tt:AddLine(L["CPU: /console scriptProfile 1 + reload to enable"], 0.7, 0.7, 0.7)
		end
		tt:AddLine(L["Shift: show all | Click: collect garbage"], 0.7, 0.7, 0.7)
		tt:Show()
	end,
	click = function() local before = collectgarbage("count") collectgarbage("collect") S:Print(format(L["Freed %.1f MB"], (before - collectgarbage("count")) / 1024)) end,
})

local slotNames = { [1] = HEADSLOT, [3] = SHOULDERSLOT, [5] = CHESTSLOT, [6] = WAISTSLOT, [7] = LEGSSLOT, [8] = FEETSLOT, [9] = WRISTSLOT, [10] = HANDSSLOT, [16] = MAINHANDSLOT, [17] = SECONDARYHANDSLOT, [18] = RANGEDSLOT }
DT:Register("Durability", {
	events = { "UPDATE_INVENTORY_DURABILITY", "MERCHANT_SHOW", "PLAYER_ENTERING_WORLD" },
	update = function(slot)
		local p = S.GetDurabilityPercent()
		local c = p > 50 and "|cff40ff40" or p > 20 and "|cffffcc00" or "|cffff4040"
		slot.text:SetText(Label(DURABILITY) .. c .. floor(p) .. "%|r")
	end,
	enter = function(slot)
		local tt = DT:Tooltip(slot)
		tt:AddLine(DURABILITY, S.accent.r, S.accent.g, S.accent.b)
		for id, name in pairs(slotNames) do
			local cur, mx = GetInventoryItemDurability(id)
			if cur and mx and mx > 0 then
				local p = cur / mx * 100
				tt:AddDoubleLine(name or ("Slot " .. id), format("%d%%", p), 1, 1, 1, 1 - p / 100, p / 100, 0)
			end
		end
		tt:Show()
	end,
	click = function() ToggleCharacter("PaperDollFrame") end,
})

-- Gold (tracks all characters of the realm + earnings history per day)
local sessionStart, lastMoney
local function GoldRecord()
	local g = S.db.global
	g.gold = g.gold or {}
	g.gold[S.myRealm] = g.gold[S.myRealm] or {}
	local rec = g.gold[S.myRealm][S.myName]
	if type(rec) ~= "table" then rec = {} end
	g.gold[S.myRealm][S.myName] = rec
	rec.earned = rec.earned or {}
	return rec
end
local function GoldEarned(rec, prefix)
	local sum = 0
	for day, v in pairs(rec.earned) do
		if not prefix or strsub(day, 1, #prefix) == prefix then sum = sum + v end
	end
	return sum
end
local function SignedMoney(v)
	return (v >= 0 and "|cff40ff40+|r" or "|cffff4040-|r") .. S:FormatMoney(math.abs(v), "SHORT")
end
function DT:GoldTooltip(anchor)
	local tt = self:Tooltip(anchor)
	local g = S.db.global
	g.gold = g.gold or {}
	local realm = g.gold[S.myRealm] or {}
	local total = 0
	tt:AddLine(L["Gold"], S.accent.r, S.accent.g, S.accent.b)
	local change = GetMoney() - (sessionStart or GetMoney())
	tt:AddDoubleLine(L["Session"], SignedMoney(change), 1, 1, 1)
	local rec = GoldRecord()
	tt:AddDoubleLine(L["Today"], SignedMoney(GoldEarned(rec, date("%Y-%m-%d"))), 1, 1, 1)
	tt:AddDoubleLine(L["This month"], SignedMoney(GoldEarned(rec, date("%Y-%m"))), 1, 1, 1)
	tt:AddDoubleLine(L["Total earned"], SignedMoney(GoldEarned(rec)), 1, 1, 1)
	tt:AddLine(" ")
	local list = {}
	for name, data in pairs(realm) do tinsert(list, { name, data.money or 0, data.class }) end
	sort(list, function(a, b) return a[2] > b[2] end)
	for _, d in ipairs(list) do
		local c = S.ClassColor(d[3])
		tt:AddDoubleLine(d[1], S:FormatMoney(d[2], DT.db.goldFormat), c.r, c.g, c.b, 1, 1, 1)
		total = total + d[2]
	end
	tt:AddLine(" ")
	tt:AddDoubleLine(L["Total"], S:FormatMoney(total, DT.db.goldFormat), 1, 1, 1, 1, 1, 1)
	if C_WowTokenPublic and C_WowTokenPublic.GetCurrentMarketPrice then
		local price = C_WowTokenPublic.GetCurrentMarketPrice()
		if price then tt:AddDoubleLine(L["WoW Token"], S:FormatMoney(price, "SHORT"), 1, 1, 1, 1, 1, 1) end
	end
	tt:Show()
end

DT:Register("Gold", {
	events = { "PLAYER_MONEY", "PLAYER_ENTERING_WORLD", "SEND_MAIL_MONEY_CHANGED", "SEND_MAIL_COD_CHANGED", "PLAYER_TRADE_MONEY", "TRADE_MONEY_CHANGED" },
	interval = 5,
	update = function(slot)
		local money = GetMoney()
		sessionStart = sessionStart or money
		local rec = GoldRecord()
		if lastMoney and money > lastMoney then
			local day = date("%Y-%m-%d")
			rec.earned[day] = (rec.earned[day] or 0) + (money - lastMoney)
		end
		lastMoney = money
		rec.money, rec.class = money, S.myClass
		-- rotating display: current -> session -> month (option "goldRotate")
		local phase = DT.db.goldRotate and (floor(GetTime() / 5) % 3) or 0
		if phase == 1 then
			slot.text:SetText(Label(L["Session"]) .. SignedMoney(money - sessionStart))
		elseif phase == 2 then
			slot.text:SetText(Label(L["This month"]) .. SignedMoney(GoldEarned(rec, date("%Y-%m"))))
		else
			slot.text:SetText(S:FormatMoney(money, DT.db.goldFormat, DT.db.goldCoins))
		end
	end,
	enter = function(slot) DT:GoldTooltip(slot) end,
	click = function() if ToggleAllBags then ToggleAllBags() end end,
})

-- Honor (current points, earned today / this session, HKs, arena points)
local honorStart
local function HonorRecord()
	local g = S.db.global
	g.honor = g.honor or {}
	g.honor[S.myRealm] = g.honor[S.myRealm] or {}
	local rec = g.honor[S.myRealm][S.myName]
	if type(rec) ~= "table" then rec = {} end
	g.honor[S.myRealm][S.myName] = rec
	rec.days = rec.days or {}
	return rec
end
DT:Register("Honor", {
	events = { "PLAYER_ENTERING_WORLD", "HONOR_CURRENCY_UPDATE", "CHAT_MSG_COMBAT_HONOR_GAIN", "PLAYER_PVP_KILLS_CHANGED", "UPDATE_PVP_STATS" },
	interval = 20,
	update = function(slot)
		local honor = (GetHonorCurrency and GetHonorCurrency()) or 0
		if S.IsSecret(honor) then slot.text:SetText(Label(L["Honor"])) return end
		honorStart = honorStart or honor
		local rec = HonorRecord()
		local day = date("%Y-%m-%d")
		if rec.current and honor > rec.current then
			rec.days[day] = (rec.days[day] or 0) + (honor - rec.current)
		end
		rec.current = honor
		slot.honorToday = rec.days[day] or 0
		slot.text:SetText(Label(L["Honor"]) .. Value(format("%d |cff888888(+%d)|r", honor, slot.honorToday)))
	end,
	enter = function(slot)
		local tt = DT:Tooltip(slot)
		tt:AddLine(L["Honor"], S.accent.r, S.accent.g, S.accent.b)
		local honor = (GetHonorCurrency and GetHonorCurrency()) or 0
		local mx = GetMaxHonorCurrency and GetMaxHonorCurrency()
		tt:AddDoubleLine(L["Honor"], mx and format("%d / %d", honor, mx) or tostring(honor), 1, 1, 1, 1, 1, 1)
		tt:AddDoubleLine(L["Today"], format("+%d", slot.honorToday or 0), 1, 1, 1, 0.4, 1, 0.4)
		if honorStart then tt:AddDoubleLine(L["Session"], format("%+d", honor - honorStart), 1, 1, 1, 1, 1, 1) end
		if GetPVPSessionStats then
			local hk = GetPVPSessionStats()
			if hk then tt:AddDoubleLine(L["Honorable kills"], tostring(hk), 1, 1, 1, 1, 1, 1) end
		end
		if GetArenaCurrency then tt:AddDoubleLine(L["Arena points"], tostring(GetArenaCurrency()), 1, 1, 1, 1, 1, 1) end
		if GetLifetimeHonorableKills then
			tt:AddLine(" ")
			tt:AddDoubleLine(L["Lifetime honorable kills"], tostring(GetLifetimeHonorableKills()), 1, 1, 1, 0.8, 0.8, 0.8)
		end
		tt:Show()
	end,
	click = function()
		if TogglePVPFrame then TogglePVPFrame()
		elseif ToggleCharacter then ToggleCharacter("HonorFrame") end
	end,
})

DT:Register("Bags", {
	events = { "BAG_UPDATE", "PLAYER_ENTERING_WORLD" },
	update = function(slot)
		local free, total = 0, 0
		for bag = 0, S.NUM_BAG_SLOTS do
			local f, family = S.GetContainerNumFreeSlots(bag)
			if (family or 0) == 0 then
				free = free + (f or 0)
				total = total + (S.GetContainerNumSlots(bag) or 0)
			end
		end
		local c = free > 10 and "|cff40ff40" or free > 3 and "|cffffcc00" or "|cffff4040"
		slot.text:SetText(Label(L["Bags"]) .. c .. (total - free) .. "/" .. total .. "|r")
	end,
	click = function() if ToggleAllBags then ToggleAllBags() end end,
})

-- Friends
local function FriendsOnline()
	local wow = S.GetNumOnlineFriends()
	local bn = 0
	if BNGetNumFriends then
		local _, online = BNGetNumFriends()
		bn = online or 0
	end
	return wow, bn
end

DT:Register("Friends", {
	events = { "FRIENDLIST_UPDATE", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE", "BN_FRIEND_INFO_CHANGED", "PLAYER_ENTERING_WORLD" },
	update = function(slot)
		local wow, bn = FriendsOnline()
		slot.text:SetText(Label(FRIENDS) .. Value(wow + bn))
	end,
	enter = function(slot)
		local tt = DT:Tooltip(slot)
		tt:AddLine(FRIENDS, S.accent.r, S.accent.g, S.accent.b)
		local num = C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetNumFriends() or GetNumFriends()
		for i = 1, num or 0 do
			local name, level, class, area, connected
			if C_FriendList and C_FriendList.GetFriendInfoByIndex then
				local info = C_FriendList.GetFriendInfoByIndex(i)
				if info then name, level, class, area, connected = info.name, info.level, info.className, info.area, info.connected end
			else
				name, level, class, area, connected = GetFriendInfo(i)
			end
			if connected and name then
				local token
				for k, v in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do if v == class then token = k end end
				local c = S.ClassColor(token)
				tt:AddDoubleLine(format("%s |cffaaaaaa%s|r", name, level or ""), area or "", c.r, c.g, c.b, 0.8, 0.8, 0.8)
			end
		end
		if BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
			local total = BNGetNumFriends()
			local header
			for i = 1, total do
				local info = C_BattleNet.GetFriendAccountInfo(i)
				local game = info and info.gameAccountInfo
				if game and game.isOnline then
					if not header then tt:AddLine(" ") tt:AddLine("Battle.net", 0.3, 0.7, 1) header = true end
					local label = info.accountName or info.battleTag or "?"
					local right = game.clientProgram == BNET_CLIENT_WOW and (game.characterName or "") .. (game.areaName and (" - " .. game.areaName) or "") or (game.richPresence or game.clientProgram or "")
					tt:AddDoubleLine(label, right, 0.3, 0.7, 1, 0.8, 0.8, 0.8)
				end
			end
		end
		tt:AddLine(" ")
		tt:AddLine(L["Click: open friends list"], 0.7, 0.7, 0.7)
		tt:Show()
	end,
	click = function() ToggleFriendsFrame(1) end,
})

DT:Register("Guild", {
	events = { "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE", "PLAYER_ENTERING_WORLD" },
	interval = 30,
	update = function(slot)
		if not IsInGuild() then slot.text:SetText(Label(GUILD) .. "|cffaaaaaa-|r") return end
		local _, online = GetNumGuildMembers()
		slot.text:SetText(Label(GUILD) .. Value(online or 0))
	end,
	enter = function(slot)
		if not IsInGuild() then return end
		S.GuildRoster()
		local tt = DT:Tooltip(slot)
		local guild, rank = GetGuildInfo("player")
		tt:AddDoubleLine(guild or GUILD, rank or "", S.accent.r, S.accent.g, S.accent.b, 0.8, 0.8, 0.8)
		local motd = GetGuildRosterMOTD and GetGuildRosterMOTD()
		if motd and motd ~= "" then tt:AddLine(motd, 1, 0.9, 0.5, true) end
		tt:AddLine(" ")
		local total = GetNumGuildMembers()
		local shown = 0
		for i = 1, total do
			local name, rankName, _, level, _, zone, note, _, online, status, class = GetGuildRosterInfo(i)
			if online and shown < 40 then
				shown = shown + 1
				local c = S.ClassColor(class)
				local st = status == 1 and " |cffff9900AFK|r" or status == 2 and " |cffff3333DND|r" or ""
				tt:AddDoubleLine(format("%s |cffaaaaaa%d|r%s", Ambiguate(name or "", "guild"), level or 0, st), zone or "", c.r, c.g, c.b, 0.8, 0.8, 0.8)
			end
		end
		tt:AddLine(" ")
		tt:AddLine(L["Click: open guild"], 0.7, 0.7, 0.7)
		tt:Show()
	end,
	click = function() if ToggleGuildFrame then ToggleGuildFrame() elseif ToggleFriendsFrame then ToggleFriendsFrame(3) end end,
})

local function PlayerCoords()
	local map = C_Map.GetBestMapForUnit("player")
	if not map then return end
	local pos = C_Map.GetPlayerMapPosition(map, "player")
	if not pos then return end
	local x, y = pos:GetXY()
	if S.IsSecret(x) then return end
	return x * 100, y * 100
end
DT.PlayerCoords = PlayerCoords

DT:Register("Coords", {
	interval = 0.2,
	update = function(slot)
		local x, y = PlayerCoords()
		slot.text:SetText(x and Value(format("%.1f, %.1f", x, y)) or "-")
	end,
	click = function() ToggleWorldMap() end,
})

DT:Register("Location", {
	events = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" },
	update = function(slot)
		local sub = GetSubZoneText()
		slot.text:SetText(Value(sub ~= "" and sub or GetZoneText()))
	end,
	click = function() ToggleWorldMap() end,
})

DT:Register("Specialization", {
	events = { "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED", "CHARACTER_POINTS_CHANGED", "PLAYER_ENTERING_WORLD" },
	update = function(slot) slot.text:SetText(Label(L["Spec"]) .. Value(S.GetSpecName() or NONE)) end,
	click = function()
		if PlayerSpellsUtil and PlayerSpellsUtil.ToggleClassTalentOrSpecFrame then PlayerSpellsUtil.ToggleClassTalentOrSpecFrame()
		elseif ToggleTalentFrame then ToggleTalentFrame() end
	end,
})

local function AvgItemLevel()
	if GetAverageItemLevel then
		local _, equipped = GetAverageItemLevel()
		if equipped and equipped > 0 then return equipped end
	end
	local total, count = 0, 0
	for slot = 1, 18 do
		if slot ~= 4 then
			local link = GetInventoryItemLink("player", slot)
			if link then
				local ilvl = S.GetDetailedItemLevelInfo and S.GetDetailedItemLevelInfo(link) or select(4, S.GetItemInfo(link))
				if ilvl then total, count = total + ilvl, count + 1 end
			end
		end
	end
	return count > 0 and total / count or 0
end

DT:Register("ItemLevel", {
	events = { "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_AVG_ITEM_LEVEL_UPDATE" },
	update = function(slot) slot.text:SetText(Label(L["iLvl"]) .. Value(format("%.1f", AvgItemLevel()))) end,
	click = function() ToggleCharacter("PaperDollFrame") end,
})

local function StatText(label, value) return Label(label) .. Value(value) end
DT:Register("Crit", {
	events = { "UNIT_STATS", "COMBAT_RATING_UPDATE", "PLAYER_EQUIPMENT_CHANGED", "UNIT_AURA" }, unit = true,
	update = function(slot)
		local melee = GetCritChance and GetCritChance() or 0
		local spell = GetSpellCritChance and GetSpellCritChance(2) or 0
		local ranged = GetRangedCritChance and GetRangedCritChance() or 0
		slot.text:SetText(StatText(L["Crit"], format("%.2f%%", max(melee, spell, ranged))))
	end,
})
DT:Register("Haste", {
	events = { "UNIT_STATS", "COMBAT_RATING_UPDATE", "UNIT_AURA", "UNIT_ATTACK_SPEED", "UNIT_SPELL_HASTE" }, unit = true,
	update = function(slot)
		local haste = GetHaste and GetHaste() or (GetCombatRatingBonus and CR_HASTE_SPELL and GetCombatRatingBonus(CR_HASTE_SPELL)) or 0
		slot.text:SetText(StatText(L["Haste"], format("%.2f%%", haste)))
	end,
})
DT:Register("Hit", {
	events = { "UNIT_STATS", "COMBAT_RATING_UPDATE", "PLAYER_EQUIPMENT_CHANGED" }, unit = true,
	update = function(slot)
		local melee = (GetHitModifier and GetHitModifier() or 0) + (GetCombatRatingBonus and CR_HIT_MELEE and GetCombatRatingBonus(CR_HIT_MELEE) or 0)
		local spell = (GetSpellHitModifier and GetSpellHitModifier() or 0) + (GetCombatRatingBonus and CR_HIT_SPELL and GetCombatRatingBonus(CR_HIT_SPELL) or 0)
		slot.text:SetText(StatText(L["Hit"], format("%.2f%%", max(melee, spell))))
	end,
})
DT:Register("Mastery", {
	events = { "UNIT_STATS", "COMBAT_RATING_UPDATE", "MASTERY_UPDATE" }, unit = true,
	update = function(slot) slot.text:SetText(StatText(L["Mastery"], format("%.2f%%", GetMasteryEffect and GetMasteryEffect() or 0))) end,
})
DT:Register("AttackPower", {
	events = { "UNIT_ATTACK_POWER", "UNIT_RANGED_ATTACK_POWER", "UNIT_AURA", "PLAYER_EQUIPMENT_CHANGED" }, unit = true,
	update = function(slot)
		local base, pos, neg = UnitAttackPower("player")
		local rb, rp, rn = UnitRangedAttackPower("player")
		local ap = (base or 0) + (pos or 0) + (neg or 0)
		local rap = (rb or 0) + (rp or 0) + (rn or 0)
		slot.text:SetText(StatText(L["AP"], max(ap, rap)))
	end,
})
DT:Register("SpellPower", {
	events = { "UNIT_STATS", "UNIT_AURA", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_DAMAGE_DONE_MODS" }, unit = true,
	update = function(slot)
		local sp = 0
		if GetSpellBonusDamage then for i = 2, 7 do sp = max(sp, GetSpellBonusDamage(i)) end end
		local heal = GetSpellBonusHealing and GetSpellBonusHealing() or 0
		slot.text:SetText(StatText(L["SP"], max(sp, heal)))
	end,
})
DT:Register("Armor", {
	events = { "UNIT_ARMOR", "UNIT_RESISTANCES", "PLAYER_EQUIPMENT_CHANGED", "UNIT_AURA" }, unit = true,
	update = function(slot) local _, eff = UnitArmor("player") slot.text:SetText(StatText(ARMOR, eff or 0)) end,
})
DT:Register("Speed", {
	interval = 0.5,
	update = function(slot)
		local speed = GetUnitSpeed("player") or 0
		slot.text:SetText(StatText(L["Speed"], format("%d%%", speed / 7 * 100 + 0.5)))
	end,
})

local combatStart
DT:Register("Combat", {
	events = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" },
	interval = 0.5,
	update = function(slot, event)
		if event == "PLAYER_REGEN_DISABLED" then combatStart = GetTime() elseif event == "PLAYER_REGEN_ENABLED" then slot.lastCombat = combatStart and (GetTime() - combatStart) combatStart = nil end
		local t = combatStart and (GetTime() - combatStart) or slot.lastCombat or 0
		slot.text:SetText(Label(L["Combat"]) .. (combatStart and "|cffff4040" or "|cff" .. S.accentHex) .. format("%d:%02d", floor(t / 60), t % 60) .. "|r")
	end,
})

local xpT0, xpGained, lastXP, lastMax
DT:Register("Experience", {
	events = { "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "PLAYER_ENTERING_WORLD" },
	update = function(slot)
		local maxLevel = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or MAX_PLAYER_LEVEL or 60
		if UnitLevel("player") >= maxLevel then slot.text:SetText(Label(L["XP"]) .. Value(L["Max"])) return end
		local cur, mx = UnitXP("player"), UnitXPMax("player")
		if not lastXP then lastXP, lastMax, xpT0, xpGained = cur, mx, GetTime(), 0 end
		if cur ~= lastXP or mx ~= lastMax then
			xpGained = xpGained + ((mx == lastMax and cur >= lastXP) and (cur - lastXP) or max(0, lastMax - lastXP + cur))
			lastXP, lastMax = cur, mx
		end
		local txt = Label(L["XP"]) .. Value(format("%.1f%%", cur / max(1, mx) * 100))
		local elapsed = GetTime() - xpT0
		if xpGained > 0 and elapsed >= 60 then
			local rate = xpGained / elapsed * 3600
			local eta = (mx - cur) / (xpGained / elapsed)
			local rateTxt = rate >= 10000 and format("%.0fk", rate / 1000) or rate >= 1000 and format("%.1fk", rate / 1000) or format("%d", rate)
			txt = txt .. " |cff888888(|r" .. Value(rateTxt .. "/h") .. " |cff888888·|r " .. Value("~" .. S:FormatTime(eta)) .. "|cff888888)|r"
		end
		local rested = GetXPExhaustion() or 0
		slot.text:SetText(txt .. (rested > 0 and format(" |cff8060ff(+%.0f%%)|r", rested / max(1, mx) * 100) or ""))
	end,
})

DT:Register("Layer", {
	events = { "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED", "GROUP_JOINED", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" },
	update = function(slot)
		local it = S:GetModule("InstanceTracker", true)
		local num = it and it.CurrentLayer and it:CurrentLayer()
		if num and num > 0 then
			slot.text:SetText(Label(L["Layer"]) .. Value(tostring(num)))
		else
			slot.text:SetText(Label(L["Layer"]) .. "|cffaaaaaa?|r")
		end
	end,
	enter = function(slot)
		local it = S:GetModule("InstanceTracker", true)
		local tt = DT:Tooltip(slot)
		tt:AddLine(L["Instance Tracker"], S.accent.r, S.accent.g, S.accent.b)
		local num = it and it.CurrentLayer and it:CurrentLayer()
		tt:AddLine(num and format(L["You are currently on layer %d."], num) or L["No layer detected yet, target an NPC."], 0.9, 0.9, 0.95)
		if it and it.Data then
			local keys = {}
			for k in pairs(it:Data().layers or {}) do keys[#keys + 1] = k end
			sort(keys)
			for i, k in ipairs(keys) do
				local cur = (it.currentLayerID == k) and (" |cff00ff00(" .. L["current"] .. ")|r") or ""
				tt:AddLine(format(L["Layer %d"] .. " |cff888888(ID %s)|r%s", i, tostring(k), cur))
			end
			if it.friendLayers then
				for id, fid in pairs(it.friendLayers) do
					local n = it:LayerNum(fid)
					tt:AddLine(format(L["%s is on layer %s"], id, n > 0 and n or "?"), 0.6, 0.6, 0.65)
				end
			end
		end
		tt:AddLine(" ")
		tt:AddLine(L["Left-click: buff timers | Right-click: layer frame"], 0.6, 0.6, 0.65)
		tt:Show()
	end,
	click = function(_, button)
		if button == "RightButton" then
			local it = S:GetModule("InstanceTracker", true)
			if it and it.layerFrame then
				it.db.layerFrame = not it.layerFrame:IsShown()
				it.layerFrame:SetShown(it.db.layerFrame)
			end
			return
		end
		local wb = S:GetModule("WorldBuffs", true)
		if wb and wb.ToggleWindow then wb:ToggleWindow() end
	end,
})

DT:Register("Mail", {
	events = { "UPDATE_PENDING_MAIL", "MAIL_INBOX_UPDATE", "PLAYER_ENTERING_WORLD", "MAIL_CLOSED" },
	update = function(slot) slot.text:SetText(HasNewMail() and ("|cff40ff40" .. L["New Mail"] .. "|r") or ("|cffaaaaaa" .. L["No Mail"] .. "|r")) end,
	enter = function(slot)
		if not HasNewMail() then return end
		local tt = DT:Tooltip(slot)
		tt:AddLine(HAVE_MAIL_FROM or L["New Mail"], S.accent.r, S.accent.g, S.accent.b)
		for _, sender in ipairs({ GetLatestThreeSenders() }) do tt:AddLine(sender, 1, 1, 1) end
		tt:Show()
	end,
})

DT:Register("Ammo", {
	events = { "UNIT_INVENTORY_CHANGED", "BAG_UPDATE", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD" },
	update = function(slot)
		local count = GetInventoryItemCount("player", 0)
		local link = GetInventoryItemLink("player", 0)
		if not link or (count or 0) == 0 then
			local ranged = GetInventoryItemLink("player", 18)
			local equipLoc = ranged and select(9, S.GetItemInfo(ranged))
			if equipLoc == "INVTYPE_THROWN" then count = GetInventoryItemCount("player", 18) end
		end
		local c = (count or 0) > 200 and "|cff40ff40" or (count or 0) > 50 and "|cffffcc00" or "|cffff4040"
		slot.text:SetText(Label(L["Ammo"]) .. c .. (count or 0) .. "|r")
	end,
})

-- Additional stat / system data texts -------------------------------------------
local statEvents = { "UNIT_STATS", "COMBAT_RATING_UPDATE", "PLAYER_EQUIPMENT_CHANGED", "UNIT_AURA", "PLAYER_ENTERING_WORLD" }

local function RatingBonus(cr)
	return GetCombatRatingBonus and cr and (GetCombatRatingBonus(cr) or 0) or 0
end

DT:Register("Dodge", { events = statEvents, unit = true,
	update = function(slot) slot.text:SetText(StatText(L["Dodge"], format("%.2f%%", GetDodgeChance and GetDodgeChance() or 0))) end })
DT:Register("Parry", { events = statEvents, unit = true,
	update = function(slot) slot.text:SetText(StatText(L["Parry"], format("%.2f%%", GetParryChance and GetParryChance() or 0))) end })
DT:Register("Block", { events = statEvents, unit = true,
	update = function(slot) slot.text:SetText(StatText(L["Block"], format("%.2f%%", GetBlockChance and GetBlockChance() or 0))) end })
DT:Register("Defense", { events = statEvents, unit = true,
	update = function(slot)
		local base, mod = UnitDefense("player")
		slot.text:SetText(StatText(L["Defense"], (base or 0) + (mod or 0)))
	end })
DT:Register("Expertise", { events = statEvents, unit = true,
	update = function(slot)
		local exp = (GetExpertise and GetExpertise() or 0) + RatingBonus(CR_EXPERTISE or 23)
		slot.text:SetText(StatText(L["Expertise"], format("%.0f", exp)))
	end })
DT:Register("Resilience", { events = statEvents, unit = true,
	update = function(slot)
		local res = RatingBonus(CR_RESILIENCE_CRIT_TAKEN or CR_RESILIENCE_PLAYER_DAMAGE_TAKEN or 15)
		slot.text:SetText(StatText(L["Resilience"], format("%.2f%%", res)))
	end })
DT:Register("ArmorPen", { events = statEvents, unit = true,
	update = function(slot)
		local ap = RatingBonus(CR_ARMOR_PENETRATION or 34)
		slot.text:SetText(StatText(L["Armor Pen"], format("%.2f%%", ap)))
	end })
DT:Register("SpellCrit", { events = statEvents, unit = true,
	update = function(slot)
		local c = 0
		if GetSpellCritChance then for i = 2, 7 do c = max(c, GetSpellCritChance(i) or 0) end end
		slot.text:SetText(StatText(L["Spell Crit"], format("%.2f%%", c)))
	end })
DT:Register("SpellHit", { events = statEvents, unit = true,
	update = function(slot)
		local hit = (GetSpellHitModifier and GetSpellHitModifier() or 0) + RatingBonus(CR_HIT_SPELL or 8)
		slot.text:SetText(StatText(L["Spell Hit"], format("%.2f%%", hit)))
	end })
DT:Register("SpellHaste", { events = statEvents, unit = true,
	update = function(slot) slot.text:SetText(StatText(L["Spell Haste"], format("%.2f%%", RatingBonus(CR_HASTE_SPELL or 18)))) end })
DT:Register("HealPower", { events = statEvents, unit = true,
	update = function(slot) slot.text:SetText(StatText(L["Healing"], format("%d", GetSpellBonusHealing and GetSpellBonusHealing() or 0))) end })
DT:Register("ManaRegen", { events = statEvents, unit = true,
	update = function(slot)
		local base, casting = GetManaRegen and GetManaRegen()
		slot.text:SetText(StatText(L["Mana Regen"], format("%d / %d", (base or 0) * 5, (casting or 0) * 5)))
	end })
DT:Register("EnergyRegen", { events = statEvents, unit = true,
	update = function(slot)
		local r = GetPowerRegen and select(2, GetPowerRegen()) or 0
		slot.text:SetText(StatText(L["Energy Regen"], format("%d", r or 0)))
	end })

local function PrimaryStat(i)
	local _, eff = UnitStat("player", i)
	return eff or 0
end
DT:Register("Strength", { events = statEvents, unit = true, update = function(slot) slot.text:SetText(StatText(L["Strength"], PrimaryStat(1))) end })
DT:Register("Agility", { events = statEvents, unit = true, update = function(slot) slot.text:SetText(StatText(L["Agility"], PrimaryStat(2))) end })
DT:Register("Stamina", { events = statEvents, unit = true, update = function(slot) slot.text:SetText(StatText(L["Stamina"], PrimaryStat(3))) end })
DT:Register("Intellect", { events = statEvents, unit = true, update = function(slot) slot.text:SetText(StatText(L["Intellect"], PrimaryStat(4))) end })
DT:Register("Spirit", { events = statEvents, unit = true, update = function(slot) slot.text:SetText(StatText(L["Spirit"], PrimaryStat(5))) end })

DT:Register("Reputation", {
	events = { "UPDATE_FACTION", "PLAYER_ENTERING_WORLD", "CHAT_MSG_COMBAT_FACTION_CHANGE" },
	update = function(slot)
		local name, standing, mn, mx, cur = GetWatchedFactionInfo and GetWatchedFactionInfo()
		if not name then slot.text:SetText(Label(L["Reputation"]) .. "|cffaaaaaa" .. L["None Watched"] .. "|r") return end
		local pct = (mx - mn) > 0 and (cur - mn) / (mx - mn) * 100 or 0
		slot.text:SetText(Label(L["Rep"]) .. Value(format("%s %.1f%%", name, pct)))
	end,
	enter = function(slot)
		local name, standing, mn, mx, cur = GetWatchedFactionInfo and GetWatchedFactionInfo()
		if not name then return end
		local tt = DT:Tooltip(slot)
		tt:AddLine(name, S.accent.r, S.accent.g, S.accent.b)
		local standingText = _G["FACTION_STANDING_LABEL" .. standing] or tostring(standing)
		tt:AddDoubleLine(standingText, format("%d / %d (%.1f%%)", cur - mn, mx - mn, (mx - mn) > 0 and (cur - mn) / (mx - mn) * 100 or 0), 1, 1, 1, 1, 1, 1)
		tt:Show()
	end,
	click = function() ToggleCharacter("ReputationFrame") end,
})

DT:Register("Quests", {
	events = { "QUEST_LOG_UPDATE", "PLAYER_ENTERING_WORLD", "QUEST_ACCEPTED", "QUEST_REMOVED" },
	update = function(slot)
		local shown = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and select(1, C_QuestLog.GetNumQuestLogEntries()))
			or (GetNumQuestLogEntries and GetNumQuestLogEntries()) or 0
		slot.text:SetText(StatText(L["Quests"], format("%d / %d", shown, MAX_QUESTS or 25)))
	end,
	click = function() ToggleQuestLog() end,
})

DT:Register("Date", {
	interval = 30,
	update = function(slot) slot.text:SetText(Value(date("%d.%m.%Y"))) end,
})

DT:Register("Volume", {
	events = { "PLAYER_ENTERING_WORLD" },
	update = function(slot)
		local v = tonumber(GetCVar and GetCVar("Sound_MasterVolume") or 0) or 0
		slot.text:SetText(StatText(L["Volume"], format("%d%%", v * 100 + 0.5)))
	end,
	enter = function(slot)
		local tt = DT:Tooltip(slot)
		tt:AddLine(L["Volume"], S.accent.r, S.accent.g, S.accent.b)
		for _, cvar in ipairs({ "Sound_MasterVolume", "Sound_MusicVolume", "Sound_SFXVolume" }) do
			tt:AddDoubleLine(cvar:gsub("Sound_", ""):gsub("Volume", ""), format("%d%%", (tonumber(GetCVar(cvar)) or 0) * 100 + 0.5), 1, 1, 1, 1, 1, 1)
		end
		tt:Show()
	end,
})

DT:Register("DualSpec", {
	events = { "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_TALENT_UPDATE", "PLAYER_ENTERING_WORLD" },
	update = function(slot)
		local active = GetActiveTalentGroup and GetActiveTalentGroup() or 1
		local n = GetNumTalentGroups and GetNumTalentGroups() or 1
		slot.text:SetText(StatText(L["Spec"], format("%d / %d", active, n)))
	end,
	click = function()
		if GetActiveTalentGroup and GetNumTalentGroups and SetActiveTalentGroup and GetNumTalentGroups() > 1 then
			SetActiveTalentGroup(3 - GetActiveTalentGroup())
		end
	end,
})

DT:Register("Currencies", {
	events = { "CURRENCY_DISPLAY_UPDATE", "PLAYER_MONEY", "PLAYER_ENTERING_WORLD", "CHAT_MSG_CURRENCY" },
	update = function(slot)
		local parts = {}
		local n = GetCurrencyListSize and GetCurrencyListSize() or 0
		for i = 1, n do
			local name, isHeader, _, _, _, count = GetCurrencyListInfo(i)
			if name and not isHeader and (count or 0) > 0 and #parts < 2 then
				tinsert(parts, format("%s: %d", name, count))
			end
		end
		slot.text:SetText(Label(L["Currency"]) .. (#parts > 0 and Value(table.concat(parts, "  ")) or "|cffaaaaaa-|r"))
	end,
	enter = function(slot)
		local tt = DT:Tooltip(slot)
		tt:AddLine(L["Currencies"], S.accent.r, S.accent.g, S.accent.b)
		local n = GetCurrencyListSize and GetCurrencyListSize() or 0
		for i = 1, n do
			local name, isHeader, _, _, _, count, icon = GetCurrencyListInfo(i)
			if name and not isHeader then tt:AddDoubleLine(name, count or 0, 1, 1, 1, 1, 1, 1) end
		end
		tt:Show()
	end,
	click = function() ToggleCharacter("TokenFrame") end,
})

DT:Register("MovementSpeed", {
	interval = 0.5,
	update = function(slot)
		local _, runSpeed = GetUnitSpeed("player")
		slot.text:SetText(StatText(L["Move Speed"], format("%d%%", (runSpeed or 7) / 7 * 100 + 0.5)))
	end,
})

-- own damage / healing meters (simple rolling combat tracker)
local dpsMeter = { damage = 0, healing = 0, start = nil, lastDps = 0, lastHps = 0 }
if CombatLogGetCurrentEventInfo then
	local f = CreateFrame("Frame")
	f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	f:RegisterEvent("PLAYER_REGEN_DISABLED")
	f:RegisterEvent("PLAYER_REGEN_ENABLED")
	f:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_DISABLED" then
			dpsMeter.damage, dpsMeter.healing, dpsMeter.start = 0, 0, GetTime()
		elseif event == "PLAYER_REGEN_ENABLED" then
			local dur = dpsMeter.start and (GetTime() - dpsMeter.start) or 0
			if dur > 0 then
				dpsMeter.lastDps = dpsMeter.damage / dur
				dpsMeter.lastHps = dpsMeter.healing / dur
			end
			dpsMeter.start = nil
		elseif event == "COMBAT_LOG_EVENT_UNFILTERED" and dpsMeter.start then
			local _, subevent, _, sourceGUID = CombatLogGetCurrentEventInfo()
			if sourceGUID == UnitGUID("player") and subevent then
				-- SWING_* events carry the amount at arg 12, spell events at arg 15
				local isSwing = subevent:sub(1, 6) == "SWING_"
				local amount = select(isSwing and 12 or 15, CombatLogGetCurrentEventInfo())
				if subevent:find("_DAMAGE") and type(amount) == "number" then
					dpsMeter.damage = dpsMeter.damage + amount
				elseif subevent:find("_HEAL") and type(amount) == "number" then
					dpsMeter.healing = dpsMeter.healing + amount
				end
			end
		end
	end)
end
DT:Register("DPS", {
	interval = 1,
	update = function(slot)
		local d = dpsMeter.start and (dpsMeter.damage / max(1, GetTime() - dpsMeter.start)) or dpsMeter.lastDps
		slot.text:SetText(StatText(L["DPS"], format("%d", d + 0.5)))
	end,
})
DT:Register("HPS", {
	interval = 1,
	update = function(slot)
		local h = dpsMeter.start and (dpsMeter.healing / max(1, GetTime() - dpsMeter.start)) or dpsMeter.lastHps
		slot.text:SetText(StatText(L["HPS"], format("%d", h + 0.5)))
	end,
})

DT:Register("Avoidance", { events = statEvents, unit = true,
	update = function(slot)
		local av = (GetDodgeChance and GetDodgeChance() or 0) + (GetParryChance and GetParryChance() or 0) + (GetBlockChance and GetBlockChance() or 0) + 5
		slot.text:SetText(StatText(L["Avoidance"], format("%.2f%%", av)))
	end })

DT:Register("CombatIndicator", {
	events = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" },
	update = function(slot, event)
		slot.text:SetText(InCombatLockdown() and "|cffff4040" .. L["In Combat"] .. "|r" or "|cffaaaaaa" .. L["Out of Combat"] .. "|r")
	end })

DT:Register("Difficulty", {
	events = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "INSTANCE_GROUP_SIZE_CHANGED" },
	update = function(slot)
		local _, instType, diff, diffName = GetInstanceInfo()
		slot.text:SetText(StatText(L["Difficulty"], instType ~= "none" and (diffName or tostring(diff)) or (GetMinimapZoneText and GetMinimapZoneText() or "")))
	end })

DT:Register("Battlegrounds", {
	events = { "PLAYER_ENTERING_WORLD", "UPDATE_BATTLEFIELD_SCORE", "UPDATE_BATTLEFIELD_STATUS" },
	update = function(slot)
		local inBG = GetBattlefieldInstanceRunTime and (GetBattlefieldInstanceRunTime() or 0) > 0
		if not inBG then
			local status
			for i = 1, (GetMaxBattlefieldID and GetMaxBattlefieldID() or 3) do
				local s = GetBattlefieldStatus and select(1, GetBattlefieldStatus(i))
				if s == "queued" then status = L["Queued"] break elseif s == "confirm" then status = "|cffff4040" .. L["Ready!"] .. "|r" end
			end
			slot.text:SetText(StatText(L["BG"], status or "-"))
			return
		end
		local kb, hk, deaths
		local n = GetNumBattlefieldScores and GetNumBattlefieldScores() or 0
		for i = 1, n do
			local name, kb_, hk_, d_ = GetBattlefieldScore(i)
			if name == S.myName then kb, hk, deaths = kb_, hk_, d_ break end
		end
		slot.text:SetText(StatText(L["BG"], format("%d KB / %d HK / %d T", kb or 0, hk or 0, deaths or 0)))
	end })

-- your class' primary stat (auto-detected)
local PRIMARY_BY_CLASS = {
	WARRIOR = 1, PALADIN = 1, DEATHKNIGHT = 1,
	HUNTER = 2, ROGUE = 2, SHAMAN = 2, MONK = 2, DEMONHUNTER = 2, DRUID = 2, EVOKER = 2,
	MAGE = 4, WARLOCK = 4, PRIEST = 4,
}
local PRIMARY_NAME = { [1] = L["Strength"], [2] = L["Agility"], [4] = L["Intellect"] }
DT:Register("PrimaryStat", { events = statEvents, unit = true,
	update = function(slot)
		local idx = PRIMARY_BY_CLASS[S.myClass] or 1
		slot.text:SetText(StatText(PRIMARY_NAME[idx] or L["Primary"], PrimaryStat(idx)))
	end })

DT:Register("CustomCurrency", {
	events = { "CURRENCY_DISPLAY_UPDATE", "CHAT_MSG_CURRENCY", "PLAYER_ENTERING_WORLD" },
	update = function(slot)
		local id = DT.db.customCurrencyID or 0
		local name, count, icon
		if GetCurrencyInfo and id > 0 then
			local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id)
			if info then name, count, icon = info.name, info.quantity, info.iconFileID
			else name, count, icon = GetCurrencyInfo(id) end
		end
		if not name then
			slot.text:SetText(StatText(L["Custom Currency"], L["set in options"]))
		else
			slot.text:SetText(Label(name) .. Value(tostring(count or 0)))
		end
	end,
	enter = function(slot)
		local tt = DT:Tooltip(slot)
		tt:AddLine(L["Custom Currency"], S.accent.r, S.accent.g, S.accent.b)
		tt:AddLine(L["Set datatexts.customCurrencyID in options"], 0.7, 0.7, 0.7)
		tt:Show()
	end,
})

DT:Register("MicroBar", {
	update = function(slot)
		slot.text:SetText("")
		-- embed the existing micro bar holder (built by the ActionBars module)
		local ab = S:GetModule("ActionBars")
		local holder = ab and ab.microBar
		if holder and slot.suiMicro ~= holder then
			slot.suiMicro = holder
			holder:SetParent(slot)
			holder:ClearAllPoints()
			holder:SetPoint("CENTER", slot)
			holder:SetFrameStrata("LOW")
		end
	end,
	enter = function(slot)
		local tt = DT:Tooltip(slot)
		tt:AddLine(L["Micro Menu"], S.accent.r, S.accent.g, S.accent.b)
		tt:Show()
	end,
})

DT:Register("EquipmentSets", {
	events = { "EQUIPMENT_SETS_CHANGED", "EQUIPMENT_SWAP_FINISHED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD" },
	update = function(slot)
		if not C_EquipmentSet or not C_EquipmentSet.GetNumEquipmentSets then
			slot.text:SetText(StatText(L["Sets"], "-"))
			return
		end
		local cur
		for i = 0, (C_EquipmentSet.GetNumEquipmentSets() - 1) do
			local name, _, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(i)
			if isEquipped then cur = name break end
		end
		slot.text:SetText(StatText(L["Set"], cur or L["None"]))
	end,
	enter = function(slot)
		if not C_EquipmentSet or not C_EquipmentSet.GetNumEquipmentSets then return end
		local tt = DT:Tooltip(slot)
		tt:AddLine(L["Equipment Sets"], S.accent.r, S.accent.g, S.accent.b)
		for i = 0, (C_EquipmentSet.GetNumEquipmentSets() - 1) do
			local name, icon, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(i)
			if name then tt:AddDoubleLine((isEquipped and "|cff40ff40" or "") .. name .. "|r", "", 1, 1, 1) end
		end
		tt:AddLine(L["Click set name to equip (via chat command /equipset)"], 0.6, 0.6, 0.6)
		tt:Show()
	end,
	click = function()
		if PaperDollFrame and ToggleCharacter then ToggleCharacter("PaperDollFrame") end
	end,
})

DT:Register("SentinelUI", {
	update = function(slot) slot.text:SetText("|cff00d2f0Sentinel|r|cffffffffUI|r") end,
	enter = function(slot)
		local tt = DT:Tooltip(slot)
		tt:AddLine("SentinelUI " .. (S.version or ""), S.accent.r, S.accent.g, S.accent.b)
		tt:AddLine(L["Click: Options"], 0.7, 0.7, 0.7)
		tt:AddLine(L["RightClick: Move UI"], 0.7, 0.7, 0.7)
		tt:Show()
	end,
	click = function(_, button)
		if button == "RightButton" then S:ToggleMovers() else S:ToggleConfig() end
	end,
})

DT:Register("None", { update = function(slot) slot.text:SetText("") end })

-- Panels --------------------------------------------------------------------
local function SlotOnEnter(slot)
	local def = slot.def
	if def and def.enter then S:SafeCall("DataTexts:" .. def.name .. ":Enter", def.enter, slot) end
end

local function SlotOnClick(slot, button)
	local def = slot.def
	if def and def.click then S:SafeCall("DataTexts:" .. def.name .. ":Click", def.click, slot, button) end
end

local function SlotOnUpdate(slot, elapsed)
	slot.elapsed = (slot.elapsed or 0) + elapsed
	if slot.elapsed < slot.def.interval then return end
	slot.elapsed = 0
	S:SafeCall("DataTexts:" .. slot.def.name, slot.def.update, slot)
end

function DT:AssignSlot(slot, name)
	local def = self.registry[name] or self.registry.None
	if slot.eventFrame then slot.eventFrame:UnregisterAllEvents() end
	slot.def = def
	slot:SetScript("OnUpdate", def.interval and SlotOnUpdate or nil)
	if def.events then
		slot.eventFrame = slot.eventFrame or CreateFrame("Frame", nil, slot)
		for _, e in ipairs(def.events) do
			if def.unit and slot.eventFrame.RegisterUnitEvent and e:find("^UNIT_") then
				pcall(slot.eventFrame.RegisterUnitEvent, slot.eventFrame, e, "player")
			else
				pcall(slot.eventFrame.RegisterEvent, slot.eventFrame, e)
			end
		end
		slot.eventFrame:SetScript("OnEvent", function(_, event) S:SafeCall("DataTexts:" .. def.name .. ":" .. event, def.update, slot, event) end)
	end
	S:SafeCall("DataTexts:" .. def.name, def.update, slot)
	-- text width changed (e.g. localized labels, rotated values): re-balance
	-- the slot widths so long texts are not clipped to "..." while short ones
	-- keep unused space
	if slot.panel and not slot.panel.layouting then
		local w = (slot.text:GetStringWidth() or 0) + 6
		if not slot.lastNeed or math.abs(w - slot.lastNeed) > 3 then
			DT:LayoutPanel(slot.panel)
		end
	end
end

function DT:CreatePanel(name, anchorFunc, numSlots)
	local db = self.db
	local panel = CreateFrame("Frame", "SentinelUI" .. name .. "DataPanel", UIParent)
	panel:SetFrameStrata("BACKGROUND")
	panel:SetHeight(db.panelHeight)
	S:SetTemplate(panel, db.panelTransparency and "Transparent" or "Default")
	anchorFunc(panel)
	panel.slots = {}
	for i = 1, numSlots do
		local slot = CreateFrame("Button", nil, panel)
		slot:RegisterForClicks("AnyUp")
		slot.text = S:FontString(slot, db.fontSize, "NONE", S.media.font)
		slot.text:SetAllPoints()
		slot:SetScript("OnEnter", SlotOnEnter)
		slot:SetScript("OnLeave", GameTooltip_Hide)
		slot:SetScript("OnClick", SlotOnClick)
		slot.panel, slot.index = panel, i
		panel.slots[i] = slot
	end
	panel.key = name
	self.panels[name] = panel
	panel:HookScript("OnSizeChanged", function(p) S:SafeCall("DataTexts:Layout", DT.LayoutPanel, DT, p) end)
	self:LayoutPanel(panel)
	return panel
end

-- Custom user panels (created/deleted from the options)
function DT:CreateCustomPanel(name)
	local info = self.db.customPanels[name]
	if not info or self.panels[name] then return end
	self.db.panels[name] = self.db.panels[name] or {}
	local panel = self:CreatePanel(name, function(p)
		p:SetSize(info.width or 300, self.db.panelHeight)
		S:CreateMover(p, "dtCustom:" .. name, name, info.point or { "BOTTOM", "UIParent", "BOTTOM", 0, 320 }, "datatexts")
	end, info.numSlots or 3)
	panel.suiCustom = true
	return panel
end

function DT:DeleteCustomPanel(name)
	local panel = self.panels[name]
	if not panel then return end
	for _, slot in ipairs(panel.slots) do
		if slot.eventFrame then
			slot.eventFrame:UnregisterAllEvents()
			slot.eventFrame:SetScript("OnEvent", nil)
		end
		slot:SetScript("OnUpdate", nil)
		slot:Hide()
	end
	S:RemoveMover("dtCustom:" .. name)
	S:Kill(panel)
	self.panels[name] = nil
end

function DT:LayoutPanel(panel)
	local n = #panel.slots
	local width = panel:GetWidth() - (panel.suiDockW or 0)
	if width <= 0 then width = 300 end
	local list = self.db.panels[panel.key] or {}
	-- battleground panel: left data panel shows BG score / DPS / HPS while in a battleground
	if self.inBattleground and self.db.battlePanel and panel.key == "LeftChat" then list = { "Battlegrounds", "DPS", "HPS", "Honor" } end
	panel.layouting = true
	-- first pass: font + datatext so each slot knows its real text width
	for i, slot in ipairs(panel.slots) do
		S:SetFont(slot.text, self.db.font and S:Fetch("font", self.db.font) or S.media.font, self.db.fontSize, self.db.fontOutline or "NONE")
		slot.text:SetWordWrap(self.db.wordWrap and true or false)
		local c = self.db.textColor
		if c then slot.text:SetTextColor(c.r, c.g, c.b) end
		self:AssignSlot(slot, list[i] or "None")
	end
	-- second pass: width per slot follows its text; leftover space is shared
	-- evenly, overflow shrinks everyone proportionally
	local gap = 6
	local total = 0
	local need = {}
	for i, slot in ipairs(panel.slots) do
		need[i] = (slot.text:GetStringWidth() or 0) + gap
		slot.lastNeed = need[i]
		total = total + need[i]
	end
	local shrink = total > width and (width / total) or 1
	local slack = total > width and 0 or (width - total) / n
	local x = 0
	for i, slot in ipairs(panel.slots) do
		-- floor at text width + gap: slots may overflow the panel edge but
		-- must never collapse into each other (min spacing between items)
		local w = math.max(need[i] * shrink + slack, need[i])
		slot:ClearAllPoints()
		slot:SetPoint("TOPLEFT", panel, "TOPLEFT", x, 0)
		slot:SetSize(w, panel:GetHeight())
		x = x + w
	end
	panel.layouting = nil
end

function DT:Update()
	if self.dock then self.dock:SetHeight(self.db.panelHeight + 2) end
	local round = S.db.profile.minimap.shape ~= "SQUARE"
	for _, panel in pairs(self.panels) do
		panel:SetHeight(self.db.panelHeight)
		local bare = panel.suiDocked or (panel.key == "Minimap" and round)
		S:SetTemplate(panel, bare and "NoBackdrop" or (self.db.panelTransparency and "Transparent" or "Default"))
		self:LayoutPanel(panel)
	end
end

-- Sentinel dock: one full-width strip along the bottom edge that carries the left
-- and right data panels (instead of two separate boxes under the chat windows)
function DT:CreateDock()
	local dock = CreateFrame("Frame", "SentinelUIDock", UIParent)
	dock:SetFrameStrata("BACKGROUND")
	dock:SetFrameLevel(0)
	dock:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -1, -1)
	dock:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 1, -1)
	dock:SetHeight(self.db.panelHeight + 2)
	S:SetTemplate(dock, "Transparent", "TOP")
	local brand = S:FontString(dock, 10, "OUTLINE")
	brand:SetPoint("CENTER", dock, "CENTER", 0, 0)
	brand:SetText("S E N T I N E L")
	brand:SetAlpha(0.35)
	S:RegisterAccent(brand, "text")
	dock.brand = brand
	self.dock = dock
	return dock
end

function DT:Initialize()
	local chat = S:GetModule("Chat")
	local leftParent = (chat and chat.leftPanel) or nil
	local rightParent = (chat and chat.rightPanel) or nil
	-- one-time migration: slot the Honor text in behind Gold on existing profiles
	local lc = self.db.panels.LeftChat
	if lc and not self.db._honorSlot then
		self.db._honorSlot = true
		local has = false
		for _, v in ipairs(lc) do if v == "Honor" then has = true end end
		if not has then
			for i, v in ipairs(lc) do
				if v == "Gold" then tinsert(lc, i + 1, "Honor") has = true break end
			end
			if not has then lc[#lc + 1] = "Honor" end
		end
	end
	local dock = self.db.dock ~= false and self:CreateDock()
	local function AttachBelow(parentFunc, fallback)
		return function(panel)
			local parent = parentFunc()
			if dock then
				local side = fallback[1] == "Left" and "LEFT" or "RIGHT"
				panel:SetPoint("BOTTOM" .. side, dock, "BOTTOM" .. side, side == "LEFT" and 1 or -1, 1)
				panel:SetWidth(parent and parent:GetWidth() or 400)
				if parent then parent:HookScript("OnSizeChanged", function(p) panel:SetWidth(p:GetWidth()) end) end
			elseif parent then
				panel:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, -3)
				panel:SetPoint("TOPRIGHT", parent, "BOTTOMRIGHT", 0, -3)
			else
				panel:SetSize(430, DT.db.panelHeight)
				S:CreateMover(panel, "dt" .. fallback[1], fallback[2], fallback[3], "datatexts")
			end
		end
	end
	self:CreatePanel("LeftChat", AttachBelow(function() return leftParent end, { "Left", L["Left Data Panel"], { "BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 6, 6 } }), max(#(self.db.panels.LeftChat or {}), 3))
	self:CreatePanel("RightChat", AttachBelow(function() return rightParent end, { "Right", L["Right Data Panel"], { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -6, 6 } }), max(#(self.db.panels.RightChat or {}), 3))
	if dock then
		for _, k in ipairs({ "LeftChat", "RightChat" }) do
			local p = self.panels[k]
			p.suiDocked = true
			S:SetTemplate(p, "NoBackdrop")
		end
	end
	if rightParent then
		self.panels.RightChat:SetShown(rightParent:IsShown())
		rightParent:HookScript("OnShow", function() DT.panels.RightChat:Show() end)
		rightParent:HookScript("OnHide", function() DT.panels.RightChat:Hide() end)
	end
	local mm = _G.SentinelUIMinimapHolder
	self:CreatePanel("Minimap", function(panel)
		if mm then
			panel:SetPoint("TOPLEFT", mm, "BOTTOMLEFT", 0, -3)
			panel:SetPoint("TOPRIGHT", mm, "BOTTOMRIGHT", 0, -3)
		else
			panel:SetSize(190, DT.db.panelHeight)
			S:CreateMover(panel, "dtMinimap", L["Minimap Data Panel"], { "TOPRIGHT", "UIParent", "TOPRIGHT", -6, -200 }, "datatexts")
		end
	end, 2)
	if S.db.profile.minimap.shape ~= "SQUARE" then S:SetTemplate(self.panels.Minimap, "NoBackdrop") end
	for name in pairs(self.db.customPanels) do
		S:SafeCall("DataTexts:CustomPanel", self.CreateCustomPanel, self, name)
	end
	local function CheckBG()
		local _, instanceType = IsInInstance()
		local inBG = instanceType == "pvp"
		if inBG ~= DT.inBattleground then
			DT.inBattleground = inBG
			if DT.panels.LeftChat then DT:LayoutPanel(DT.panels.LeftChat) end
		end
	end
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", CheckBG)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
		CheckBG()
		if IsInGuild() then S.GuildRoster() end
		if C_FriendList and C_FriendList.ShowFriends then C_FriendList.ShowFriends() elseif ShowFriends then ShowFriends() end
	end)
	if chat and chat.PositionEditBox then
		for i = 1, NUM_CHAT_WINDOWS do
			local f = _G["ChatFrame" .. i]
			if f then chat:PositionEditBox(f) end
		end
	end
end

-- LFG status: queued groups/bulletin entry count at a glance
DT:Register("LFG", {
	interval = 5,
	update = function(slot)
		local n = 0
		local g = S.db.global.groupBulletin
		if g then for _ in pairs(g) do n = n + 1 end end
		slot.text:SetText(Label("LFG") .. Value(tostring(n)))
	end,
	click = function()
		local gb = S:GetModule("GroupBulletin")
		if gb and gb.Toggle then gb:Toggle() end
	end,
})

-- XP per hour + time-to-level (resets each session)
local xpStart, xpStartXP, xpStartLvl
DT:Register("XP Rate", {
	interval = 10,
	update = function(slot)
		local lvl, cur, max = UnitLevel("player"), UnitXP("player"), UnitXPMax("player")
		if lvl >= MAX_PLAYER_LEVEL or max <= 0 then
			slot.text:SetText(Label("XP") .. Value("max"))
			return
		end
		if not xpStart or lvl ~= xpStartLvl then xpStart, xpStartXP, xpStartLvl = time(), cur, lvl end
		local elapsed = max(1, time() - xpStart)
		local rate = floor((cur - xpStartXP) / elapsed * 3600)
		local ttl = rate > 0 and SecondsToTime((max - cur) / rate * 3600, true) or "-"
		slot.text:SetText(Label("XP") .. Value(S:Abbrev(rate) .. "/h"))
		slot._xpTTL, slot._xpRate, slot._xpPct = ttl, rate, floor(cur / max * 100)
	end,
	enter = function(slot)
		local tt = DT:Tooltip(slot)
		tt:AddLine(L["Experience"], S.accent.r, S.accent.g, S.accent.b)
		local cur, max = UnitXP("player"), UnitXPMax("player")
		tt:AddDoubleLine(L["Progress"], format("%s / %s (%d%%)", S:Abbrev(cur), S:Abbrev(max), max > 0 and floor(cur / max * 100) or 0), 1, 1, 1, 1, 1, 1)
		tt:AddDoubleLine(L["Rested"], S:Abbrev(GetXPExhaustion and GetXPExhaustion() or 0), 1, 1, 1, 0.5, 0.8, 1)
		if slot._xpRate then tt:AddDoubleLine("XP/h", S:Abbrev(slot._xpRate), 1, 1, 1, 1, 1, 1) end
		if slot._xpTTL then tt:AddDoubleLine(L["Time to level"], slot._xpTTL, 1, 1, 1, 1, 1, 1) end
		tt:Show()
	end,
})

-- BG queue: queued battleground + ETA, click opens the PvP frame
DT:Register("BG Queue", {
	interval = 5,
	update = function(slot)
		local txt = "-"
		if GetBattlefieldStatus then
			for i = 1, MAX_BATTLEFIELD_QUEUES or 3 do
				local status, map, _, _, _, _, _, _, _, _, _, estTime = GetBattlefieldStatus(i)
				if status == "queued" or status == "confirm" then
					txt = format("%s %s", map or "?", estTime and estTime > 0 and SecondsToTime(estTime, true) or status)
					break
				end
			end
		end
		slot.text:SetText(Label("BG") .. Value(txt))
	end,
	click = function()
		if TogglePVPFrame then pcall(TogglePVPFrame)
		elseif PVPParentFrame then pcall(ShowUIPanel, PVPParentFrame) end
	end,
})
