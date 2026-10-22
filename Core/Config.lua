-- Options window. Most widgets are generated from the defaults table, special keys get custom widgets.
local _, ns = ...
local S = ns.S
local L = S.L

local ACR = LibStub("AceConfigRegistry-3.0")
local ACD = LibStub("AceConfigDialog-3.0")

local pairs, ipairs, type, tostring, sort, format, strtrim = pairs, ipairs, type, tostring, table.sort, format, strtrim

local function IndexOf(t, v)
	for i, x in ipairs(t) do if x == v then return i end end
end

local function Pretty(key)
	local t = rawget(L, key)
	if t then return t end
	local s = tostring(key):gsub("(%l)(%u)", "%1 %2"):gsub("^%l", string.upper)
	return L[s]
end

local OUTLINES = { NONE = L["None"], OUTLINE = L["Outline"], THICKOUTLINE = L["Thick Outline"], MONOCHROMEOUTLINE = L["Monochrome Outline"] }
local POINTS = { TOPLEFT = "TOPLEFT", TOP = "TOP", TOPRIGHT = "TOPRIGHT", LEFT = "LEFT", CENTER = "CENTER", RIGHT = "RIGHT", BOTTOMLEFT = "BOTTOMLEFT", BOTTOM = "BOTTOM", BOTTOMRIGHT = "BOTTOMRIGHT" }
local GROWTH = { DOWN = "DOWN", UP = "UP", RIGHT = "RIGHT", LEFT = "LEFT", RIGHT_DOWN = "RIGHT_DOWN", RIGHT_UP = "RIGHT_UP", LEFT_DOWN = "LEFT_DOWN", LEFT_UP = "LEFT_UP", DOWN_RIGHT = "DOWN_RIGHT", DOWN_LEFT = "DOWN_LEFT", UP_RIGHT = "UP_RIGHT", UP_LEFT = "UP_LEFT" }
local BARTEXT = { NONE = L["None"], PERCENT = L["Percent"], CURMAX = L["Current / Max"], CURPERC = L["Current - Percent"], REMAINING = L["Remaining"], CURVALUE = L["Current"] }
local NP_STYLES = {
	STANDARD = L["Standard (name above)"], INLINE = L["Inline (name inside bar)"], CENTER = L["Centered (name inside bar)"],
	UNDER = L["Name below the bar"], PLATE = L["Plate (big bar, all inside)"], SLIM = L["Slim (thin bar)"], BAR = L["Bar only (no texts)"],
}

local selects = {
	fontOutline = OUTLINES, unitFontOutline = OUTLINES,
	autoRepair = { NONE = L["None"], PLAYER = L["Own gold"], GUILD = L["Guild bank (fallback own gold)"] },
	interruptAnnounce = { NONE = L["None"], SAY = SAY, EMOTE = EMOTE, PARTY = PARTY, RAID = RAID, AUTO = L["Automatic"] },
	channel = { NONE = L["None"], AUTO = L["Automatic"], PARTY = PARTY, RAID = RAID, RAID_WARNING = RAID_WARNING, INSTANCE_CHAT = L["Instance Chat"] },
	dispelAnnounce = { NONE = L["None"], SAY = SAY, EMOTE = EMOTE, PARTY = PARTY, RAID = RAID, AUTO = L["Automatic"] },
	numberFormat = { SHORT = "12.3K", GERMAN = "12.3 Tsd", FULL = "12,345" },
	anchor = function(path)
		if path[1] == "tooltip" then return { SMART = L["Mover (smart)"], CURSOR = L["Cursor"], DEFAULT = L["Blizzard default"] } end
		return { TOPLEFT = "TOPLEFT", TOPRIGHT = "TOPRIGHT", BOTTOMLEFT = "BOTTOMLEFT", BOTTOMRIGHT = "BOTTOMRIGHT", LEFT = "LEFT", RIGHT = "RIGHT", CENTER = "CENTER" }
	end,
	position = POINTS, point = POINTS,
	growthX = { LEFT = L["Left"], RIGHT = L["Right"] }, growthY = { UP = L["Up"], DOWN = L["Down"] },
	growth = GROWTH,
	locationText = { SHOW = L["Always"], MOUSEOVER = L["Mouseover"], HIDE = L["Hide"] },
	collectorExpand = { HOVER = L["Mouseover"], CLICK = L["Click"], ALWAYS = L["Always"] },
	collectorGrowH = { LEFT = L["Left"], RIGHT = L["Right"] },
	collectorGrowV = { UP = L["Up"], DOWN = L["Down"] },
	shape = { ROUND = L["Round (radar)"], SQUARE = L["Square"] },
	classIconSide = { LEFT = L["Left"], RIGHT = L["Right"] },
	side = { LEFT = L["Left"], RIGHT = L["Right"] },
	style = { ["2D"] = L["2D picture (static)"], ["3D"] = L["3D model (animated)"] },
	healthMode = function(path)
		if path[1] == "raidgrid" then return { CLASS = L["Class colored bar"], GRADIENT = L["Health gradient (green to red)"] } end
		return { DARK = L["Dark (class color on edge + name)"], CLASS = L["Class colored bar"] }
	end,

	editboxPosition = { BELOW_CHAT = L["Below chat"], ABOVE_CHAT = L["Above chat"] },
	panelBackdrop = { SHOWBOTH = L["Both"], LEFT = L["Left only"], RIGHT = L["Right only"], HIDEBOTH = L["None"] },
	timestamp = { NONE = L["None"], ["%H:%M"] = "13:37", ["%H:%M:%S"] = "13:37:00", ["%I:%M %p"] = "01:37 PM" },
	text = function(path) if path[1] == "databars" then return BARTEXT end end,
	healthText = function(path) if path[1] == "nameplates" then return { NONE = L["None"], PERCENT = L["Percent"], CURRENT = L["Current"], BOTH = L["Both"] } end end,

	enemyStyle = function(path) if path[1] == "nameplates" then return NP_STYLES end end,
	friendlyStyle = function(path) if path[1] == "nameplates" then return NP_STYLES end end,
	moneyFormat = { SMART = L["Smart"], FULL = L["Full"], SHORT = L["Gold only"] }, goldFormat = { SMART = L["Smart"], FULL = L["Full"], SHORT = L["Gold only"] },
	sortMethod = function(path)
		if path[1] == "unitframes" or path[1] == "raidgrid" then return { INDEX = L["Index"], NAME = L["Name"] } end
		return { TIME = L["Time"], INDEX = L["Index"], NAME = L["Name"] }
	end,
	sortDir = function(path)
		if path[1] == "unitframes" then return { ASC = L["Ascending"], DESC = L["Descending"] } end
		return { ["+"] = L["Ascending"], ["-"] = L["Descending"] }
	end,
	vendorQuality = function()
		local t = {}
		for i = 0, 4 do
			local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[i]
			local n = _G["ITEM_QUALITY" .. i .. "_DESC"] or tostring(i)
			t[i] = ((c and c.hex) or "") .. n .. "|r"
		end
		return t
	end,
	separateOwn = { [1] = L["Own first"], [0] = L["Mixed"], [-1] = L["Own last"] },
	groupBy = { GROUP = GROUP, CLASS = CLASS, ROLE = ROLE or "Role" },
	orientation = { HORIZONTAL = L["Horizontal"], VERTICAL = L["Vertical"] },
	flyoutDirection = { AUTO = L["Automatic"], UP = L["Up"], DOWN = L["Down"], LEFT = L["Left"], RIGHT = L["Right"] },
	hideInCombatModifier = { NONE = L["None"], SHIFT = "SHIFT", CTRL = "CTRL", ALT = "ALT" },
	sort = { TIME = L["Time"], NAME = L["Name"] },
	attachTo = { HEALTH = L["Health Bar"], POWER = L["Power Bar"], FRAME = L["Frame"] },
	mode = function(path)
		if path[1] == "decurse" then return { grid = L["Grid"], onebutton = L["One Button"] } end
	end,
	trackerSort = { log = L["Quest log order"], level = L["Level"], proximity = L["Proximity"] },
	phaseIndex = function()
		local v = {}
		for i, p in ipairs((SUIBisData and SUIBisData.phases) or {}) do v[i] = p end
		return v
	end,
}

local mediaKeys = { font = "LSM30_Font", numberFont = "LSM30_Font", unitFont = "LSM30_Font", statusbar = "LSM30_Statusbar", whisperSound = "LSM30_Sound", keywordSound = "LSM30_Sound", errorSound = "LSM30_Sound" }
local mediaTypes = { LSM30_Font = "font", LSM30_Statusbar = "statusbar", LSM30_Sound = "sound" }

local ranges = {
	fontSize = { 6, 32, 1 }, tabFontSize = { 6, 24, 1 }, headerFontSize = { 8, 32, 1 }, locationFontSize = { 6, 24, 1 },
	mapPinSize = { 8, 32, 1 }, miniMaxDist = { 50, 1000, 10 }, miniViewDist = { 60, 400, 10 }, miniPool = { 10, 150, 1 },
	trackerWidth = { 150, 400, 5 }, trackerFontSize = { 8, 20, 1 }, trackerMaxHeight = { 150, 1200, 10 },
	hotkeyFontSize = { 6, 24, 1 }, countFontSize = { 6, 24, 1 }, macroFontSize = { 6, 24, 1 },
	width = { 10, 1200, 1 }, height = { 1, 400, 1 }, size = { 6, 400, 1 }, buttonSize = { 10, 80, 1 }, buttonHeight = { 0, 80, 1 },
	spacing = { -5, 60, 1 }, backdropSpacing = { 0, 20, 1 }, wrapSpacing = { 0, 60, 1 },
	alpha = { 0, 1, 0.05 }, rangeAlpha = { 0, 1, 0.05 }, nonTargetAlpha = { 0, 1, 0.05 }, globalFadeAlpha = { 0, 1, 0.05 }, darkTint = { 0, 1, 0.05 },
	targetScale = { 0.8, 2, 0.05 }, uiScale = { 0.4, 1.15, 0.01 },
	xOffset = { -300, 300, 1 }, yOffset = { -300, 300, 1 }, cursorX = { -200, 200, 1 }, cursorY = { -200, 200, 1 },
	buttons = { 1, 12, 1 }, buttonsPerRow = { 1, 12, 1 }, perRow = { 1, 40, 1 }, maxRows = { 1, 10, 1 }, maxWraps = { 1, 10, 1 },
	fadeTime = { 1, 300, 1 }, maxLines = { 100, 5000, 50 }, decimals = { 0, 3, 1 }, cooldownThreshold = { 0, 60, 1 }, cooldownMinSize = { 8, 60, 1 },
	bagColumns = { 4, 30, 1 }, bankColumns = { 4, 30, 1 }, bagSize = { 20, 60, 1 }, bankSize = { 20, 60, 1 },
	maxLength = { 0, 40, 1 }, unitsPerColumn = { 1, 40, 1 }, maxColumns = { 1, 8, 1 }, fadeThreshold = { 0, 60, 1 },
	panelWidth = { 150, 1000, 1 }, panelHeight = { 60, 700, 1 }, healthBarHeight = { 0, 30, 1 }, collectorPerRow = { 1, 20, 1 },
	collectorSize = { 12, 48, 1 }, collectorSpacing = { 0, 12, 1 },
	debuffSize = { 8, 60, 1 }, maxDebuffs = { 0, 12, 1 }, castbarHeight = { 2, 40, 1 }, itemLevelThreshold = { 0, 5, 1 },
	scale = { 0.4, 2, 0.05 }, barW = { 24, 200, 1 }, barH = { 12, 80, 1 }, groupSpacing = { 0, 40, 1 },
	historySize = { 0, 500, 10 }, throttle = { 0, 120, 1 }, unitSize = { 10, 50, 1 }, inactiveDays = { 7, 365, 1 },
}

local skipKeys = { movers = true, customPanels = true, panels = true, paging = true, point = true, filters = true, customTexts = true, clickCast = true, bindings = true, buttonIgnore = true, mapPos = true }

selects.customFilter = function()
	local v = { NONE = L["None"] }
	for name in pairs(S.db.profile.unitframes.filters) do v[name] = name end
	return v
end
ranges.minDuration = { 0, 3600, 1 }
ranges.duration = { 0.5, 5, 0.1 }
ranges.distance = { 20, 400, 5 }
ranges.critSize = { 8, 60, 1 }
ranges.minAmount = { 0, 50000, 50 }
ranges.roleIconSize = { 8, 32, 1 }
ranges.winCount = { 1, 3, 1 }
ranges.barHeight = { 4, 40, 1 }
ranges.maxBars = { 1, 25, 1 }
ranges.arrowSize = { 24, 160, 4 }
ranges.pinSize = { 6, 40, 1 }
ranges.arrowAlpha = { 0, 1, 0.05 }
ranges.pinAlpha = { 0, 1, 0.05 }
ranges.mapScale = { 0.2, 3, 0.05 }
ranges.pinScale = { 0.5, 2, 0.05 }
ranges.arrival = { 2, 100, 1 }
selects.reportChannel = { AUTO = L["Automatic"], SAY = SAY, PARTY = PARTY, RAID = RAID, GUILD = GUILD }
selects.timeStringType = { short = L["Short"], medium = L["Medium"], long = L["Long"] }
selects.timeStampFormat = { [12] = "12h", [24] = "24h" }
selects.dateFormat = { de = "31.12.2024", us = "12/31/2024", iso = "2024-12-31" }
selects.instanceStatsOutputWhere = { self = L["Self"], group = L["Group"], say = L["Say"], party = L["Party"], raid = L["Raid"], guild = L["Guild"], officer = L["Officer"], yell = L["Yell"] }
local meterModes = { damage = L["Damage"], dps = "DPS", healing = L["Healing"], hps = "HPS", taken = L["Damage Taken"], overheal = L["Overheal"], interrupts = L["Interrupts"], dispels = L["Dispels"], deaths = L["Deaths"], healtaken = L["Healing Taken"], ccbreak = L["CC Breaks"], ffire = L["Friendly Fire"], aurauptime = L["Aura Uptime"], threat = L["Threat"] }
for i = 1, 5 do selects["win" .. i .. "Mode"] = meterModes end
ranges.maxDuration = { 0, 3600, 1 }
ranges.arrival = { 1, 100, 1 }
ranges.arrowSize = { 24, 128, 2 }
ranges.arrowAlpha = { 0, 1, 0.05 }
ranges.pinSize = { 8, 32, 1 }
ranges.pinAlpha = { 0.1, 1, 0.05 }
ranges.maxBars = { 1, 20, 1 }
ranges.barHeight = { 6, 40, 1 }
selects.createModifier = { CTRL = "CTRL", ALT = "ALT", SHIFT = "SHIFT", NONE = L["None"] }
ranges.defaultSeconds = { 1, 60, 1 }
ranges.delay = { 0, 3, 0.1 }
ranges.threshold = { 0.05, 0.9, 0.05 }
ranges.minCooldown = { 5, 120, 1 }

-- power-bar text presets: friendly dropdown that writes the matching tag string
local POWER_TEXT_FORMATS = {
	[""] = L["None"],
	["[perpp]"] = L["Percent"],
	["[curpp]"] = L["Current"],
	["[curpp] / [maxpp]"] = L["Current"] .. " / " .. L["Max"],
	["[power:current-percent]"] = L["Current - Percent"],
	["[missingpp]"] = L["Deficit"],
	__custom = L["Custom"],
}
local POWER_TEXT_SORTING = { "", "[perpp]", "[curpp]", "[curpp] / [maxpp]", "[power:current-percent]", "[missingpp]", "__custom" }

local function SpellLabel(key)
	if type(key) == "number" then
		local name, _, icon = S.GetSpellInfo(key)
		return format("|T%s:14:14:0:0:64:64:5:59:5:59|t %s |cffaaaaaa(%d)|r", icon or 134400, name or "?", key)
	end
	return key
end

local function FilterOptions()
	local edit = S.filterEdit or { selected = "Blacklist" }
	S.filterEdit = edit
	local filters = S.db.profile.unitframes.filters
	local function Current() return filters[edit.selected] end
	local function Changed() S:SafeCall("Config:Refresh", S.RefreshAll, S) ACR:NotifyChange("SentinelUI") end
	return {
		desc = { type = "description", order = 0, name = L["Filters decide which auras are shown on unit frames. Blacklist hides auras, Whitelist shows only listed auras (when enabled on the frame). Custom filters can be selected per frame under Buffs / Debuffs."] },
		new = {
			type = "input", order = 1, name = L["Create new filter"],
			set = function(_, v)
				v = strtrim(v or "")
				if v ~= "" and not filters[v] then filters[v] = { type = "Blacklist", spells = {} } edit.selected = v Changed() end
			end,
			get = function() return "" end,
		},
		selected = {
			type = "select", order = 2, name = L["Filter"],
			values = function() local t = {} for k in pairs(filters) do t[k] = k end return t end,
			get = function() return edit.selected end,
			set = function(_, v) edit.selected = v ACR:NotifyChange("SentinelUI") end,
		},
		ftype = {
			type = "select", order = 3, name = L["Type"], values = { Whitelist = L["Whitelist"], Blacklist = L["Blacklist"] },
			disabled = function() return edit.selected == "Blacklist" or edit.selected == "Whitelist" end,
			get = function() return Current() and Current().type end,
			set = function(_, v) if Current() then Current().type = v Changed() end end,
		},
		delete = {
			type = "execute", order = 4, name = L["Delete filter"],
			disabled = function() return edit.selected == "Blacklist" or edit.selected == "Whitelist" end,
			func = function() filters[edit.selected] = nil edit.selected = "Blacklist" Changed() end,
		},
		add = {
			type = "input", order = 10, name = L["Add spell (ID or name)"], width = "double",
			get = function() return "" end,
			set = function(_, v)
				v = strtrim(v or "")
				if v == "" or not Current() then return end
				local key = tonumber(v) or v:lower()
				Current().spells[key] = true
				Changed()
			end,
		},
		remove = {
			type = "select", order = 11, name = L["Remove spell"], width = "double",
			values = function()
				local t = {}
				if Current() then for k, on in pairs(Current().spells) do if on then t[k] = SpellLabel(k) end end end
				return t
			end,
			get = function() return nil end,
			set = function(_, k) if Current() then Current().spells[k] = false Changed() end end,
		},
		list = {
			type = "description", order = 20, fontSize = "medium",
			name = function()
				local lines = {}
				if Current() then for k, on in pairs(Current().spells) do if on then lines[#lines + 1] = SpellLabel(k) end end end
				table.sort(lines)
				return #lines > 0 and table.concat(lines, "\n") or ("|cffaaaaaa" .. L["(empty)"] .. "|r")
			end,
		},
	}
end

local function GetDB(path)
	local t = S.db.profile
	for i = 1, #path - 1 do t = t[path[i]] end
	return t, path[#path]
end

local function Refresh()
	S:SafeCall("Config:Refresh", S.RefreshAll, S)
end

-- settings that are only read when the UI is built: changing them asks for a reload
local reloadKeys = {
	["general.bubbles"] = true, ["general.loot"] = true, ["general.lootRoll"] = true, ["general.vehicleSeat"] = true,
	["general.raidUtility"] = true, ["general.cooldownText"] = true, ["general.hideErrorFrame"] = true,
	["general.totemTracker.enable"] = true, ["general.afk"] = false,
	["chat.classColorMentions"] = true, ["chat.stickyChat"] = true, ["chat.copyButton"] = true, ["chat.scrollDownButton"] = true,
	["minimap.buttonCollector"] = true, ["minimap.minimapButton"] = false,
	["bags.showBagBar"] = true, ["bags.splitBags"] = true, ["datatexts.dock"] = true,
}
local function NeedsReload(p)
	if p[1] == "skins" then return true end
	return reloadKeys[table.concat(p, ".")] and true or false
end
local function Changed(p)
	-- a hand-picked scale wins over auto scale, and both apply live
	if p and p[1] == "general" and (p[#p] == "uiScale" or p[#p] == "autoScale") then
		if p[#p] == "uiScale" then S.db.profile.general.autoScale = false end
		S:SafeCall("UIScale", S.SetUIScale, S)
	end
	Refresh()
	if NeedsReload(p) then S:StaticReload() end
end

local function BuildGroup(tbl, defaults, path, order)
	local args = {}
	local keys = {}
	for k in pairs(defaults) do keys[#keys + 1] = k end
	sort(keys, function(a, b)
		local ta, tb = type(defaults[a]), type(defaults[b])
		local ga = ta == "table" and not defaults[a].r
		local gb = tb == "table" and not defaults[b].r
		if ga ~= gb then return gb end
		if (a == "enable") ~= (b == "enable") then return a == "enable" end
		return tostring(a) < tostring(b)
	end)
	local idx = 0
	for _, key in ipairs(keys) do
		local def = defaults[key]
		local p = {}
		for i, v in ipairs(path) do p[i] = v end
		p[#p + 1] = key
		idx = idx + 1
		local name = Pretty(key)
		local t = type(def)
		if skipKeys[key] then
			-- handled elsewhere
		elseif t == "boolean" then
			args[tostring(key)] = {
				type = "toggle", name = name, order = idx, desc = NeedsReload(p) and ("|cffff8800" .. L["Requires a UI reload"] .. "|r") or nil,
				get = function() local db, k = GetDB(p) return db[k] end,
				set = function(_, v) local db, k = GetDB(p) db[k] = v Changed(p) end,
			}
		elseif t == "number" and selects[key] then
			local vals = type(selects[key]) == "function" and selects[key](p) or selects[key]
			args[tostring(key)] = {
				type = "select", name = name, order = idx, values = vals,
				get = function() local db, k = GetDB(p) return db[k] end,
				set = function(_, v) local db, k = GetDB(p) db[k] = v Changed(p) end,
			}
		elseif t == "number" then
			local r = ranges[key] or { -500, 500, 1 }
			args[tostring(key)] = {
				type = "range", name = name, order = idx, min = r[1], max = r[2], step = r[3], bigStep = r[3] < 1 and 0.05 or nil,
				get = function() local db, k = GetDB(p) return db[k] end,
				set = function(_, v) local db, k = GetDB(p) db[k] = v Changed(p) end,
			}
		elseif t == "string" then
			local vals = selects[key]
			if type(vals) == "function" then vals = vals(p) end
			if mediaKeys[key] then
				args[tostring(key)] = {
					type = "select", name = name, order = idx, dialogControl = mediaKeys[key],
					values = function() local lists = AceGUIWidgetLSMlists or {} local v = lists[mediaTypes[mediaKeys[key]]] or {} if mediaKeys[key] == "LSM30_Sound" then v.None = v.None or "None" end return v end,
					get = function() local db, k = GetDB(p) return db[k] end,
					set = function(_, v) local db, k = GetDB(p) db[k] = v Changed(p) end,
				}
			elseif vals then
				args[tostring(key)] = {
					type = "select", name = name, order = idx, values = vals,
					get = function() local db, k = GetDB(p) return db[k] end,
					set = function(_, v) local db, k = GetDB(p) db[k] = v Changed(p) end,
				}
			else
				local isTag = key == "text" and p[#p - 1] ~= nil
				args[tostring(key)] = {
					type = "input", name = name, order = idx, width = (key == "visibility" or isTag) and "full" or nil,
					desc = isTag and L["Tags: [name] [level] [current] [max] [percent] [deficit] [curmax] [curpp] [maxpp] [perpp] [status] [classification] [group] [afk]"] or (key == "visibility" and L["Macro conditionals, e.g. [combat] show; hide"]) or nil,
					get = function() local db, k = GetDB(p) return db[k] end,
					set = function(_, v) local db, k = GetDB(p) db[k] = v Changed(p) end,
				}
			end
		elseif t == "table" and def.r and def.g and def.b then
			args[tostring(key)] = {
				type = "color", name = name, order = idx, hasAlpha = def.a ~= nil,
				get = function() local db, k = GetDB(p) local c = db[k] return c.r, c.g, c.b, c.a end,
				set = function(_, r, g, b, a) local db, k = GetDB(p) local c = db[k] c.r, c.g, c.b = r, g, b if def.a ~= nil then c.a = a end Changed(p) end,
			}
		elseif t == "table" then
			args[tostring(key)] = BuildGroup(nil, def, p, idx)
			args[tostring(key)].name = name
			args[tostring(key)].order = 100 + idx
			local inline = true
			for _, v in pairs(def) do if type(v) == "table" and not v.r then inline = false end end
			args[tostring(key)].inline = inline and #path > 0 and path[1] ~= "unitframes" or (inline and #path >= 3)
		end
	end
	return { type = "group", name = "", order = order or 0, args = args, childGroups = #path == 0 and "tree" or "tab" }
end

local function PrivateToggle(module, key, label, order)
	return {
		type = "toggle", name = label, order = order, width = "full",
		get = function() return S.private[module][key] end,
		set = function(_, v)
			S.private[module][key] = v
			if module == "nameplates" and key == "enable" then S.private.nameplates.userSet = true end
			S:StaticReload()
		end,
	}
end

local newPanelName = ""
local function DataTextOptions()
	local dt = S:GetModule("DataTexts")
	local names = {}
	for name in pairs(dt.registry) do names[name] = L[name] end
	local args = {}
	local order = 1
	local function PanelGroup(panel, count, title, extra)
		local g = { type = "group", inline = true, name = title or L[panel .. " Panel"], order = order, args = {} }
		order = order + 1
		for i = 1, count do
			g.args["slot" .. i] = {
				type = "select", name = format(L["Slot %d"], i), order = i, values = names,
				get = function() return S.db.profile.datatexts.panels[panel] and S.db.profile.datatexts.panels[panel][i] or "None" end,
				set = function(_, v) S.db.profile.datatexts.panels[panel] = S.db.profile.datatexts.panels[panel] or {} S.db.profile.datatexts.panels[panel][i] = v Refresh() end,
			}
		end
		if extra then for k, v in pairs(extra) do g.args[k] = v end end
		args["panel_" .. panel] = g
	end
	PanelGroup("LeftChat", 3)
	PanelGroup("RightChat", 3)
	PanelGroup("Minimap", 2)
	for name, info in pairs(S.db.profile.datatexts.customPanels) do
		local pname = name
		PanelGroup(name, info.numSlots or 3, name, {
			numSlots = {
				type = "range", name = L["Slots"], order = 90, min = 1, max = 10, step = 1,
				get = function() return S.db.profile.datatexts.customPanels[pname].numSlots or 3 end,
				set = function(_, v)
					S.db.profile.datatexts.customPanels[pname].numSlots = v
					dt:DeleteCustomPanel(pname) dt:CreateCustomPanel(pname)
				end,
			},
			width = {
				type = "range", name = L["Width"], order = 91, min = 60, max = 1600, step = 4,
				get = function() return S.db.profile.datatexts.customPanels[pname].width or 300 end,
				set = function(_, v)
					S.db.profile.datatexts.customPanels[pname].width = v
					if dt.panels[pname] then dt.panels[pname]:SetWidth(v) end
				end,
			},
			delete = {
				type = "execute", name = L["Delete Panel"], order = 99,
				func = function()
					dt:DeleteCustomPanel(pname)
					S.db.profile.datatexts.customPanels[pname] = nil
					S.db.profile.datatexts.panels[pname] = nil
					S.options = S:BuildOptions() ACR:NotifyChange("SentinelUI")
				end,
			},
		})
	end
	args.newHeader = { type = "header", name = L["New Panel"], order = 100 }
	args.newName = {
		type = "input", name = L["Panel name"], order = 101,
		get = function() return newPanelName end, set = function(_, v) newPanelName = strtrim(v or "") end,
	}
	args.newBtn = {
		type = "execute", name = L["Create Panel"], order = 102,
		func = function()
			local name = newPanelName:match("^%s*(.-)%s*$")
			if name == "" or not name:match("^[%w]+$") or S.db.profile.datatexts.panels[name] then
				S:Print("|cffff4444" .. L["Invalid or duplicate panel name."] .. "|r") return
			end
			S.db.profile.datatexts.customPanels[name] = { numSlots = 3, width = 300 }
			dt:CreateCustomPanel(name)
			newPanelName = ""
			S.options = S:BuildOptions() ACR:NotifyChange("SentinelUI")
			S:Print(format(L["Panel '%s' created. Move it with /sui move."], name))
		end,
	}
	return args
end

-- free tag text fields per unit ---------------------------------------------------
local newCTName = ""
local function CustomTextOptions(unitKey, dbAcc)
	local acc = dbAcc or function() return S.db.profile.unitframes.units[unitKey] end
	local function Texts()
		local udb = acc()
		if not udb.customTexts then udb.customTexts = {} end
		return udb.customTexts
	end
	local args = {
		desc = {
			type = "description", order = 0, fontSize = "medium",
			name = L["Free text fields: any [Tag] combination at any position on the frame. Available tags are listed under 'Tags'."],
		},
		newName = {
			type = "input", order = 1, name = L["New text name"],
			get = function() return newCTName end, set = function(_, v) newCTName = strtrim(v or "") end,
		},
		newBtn = {
			type = "execute", order = 2, name = L["Create Text"],
			func = function()
				local name = strtrim(newCTName or "")
				if name == "" or Texts()[name] then return end
				Texts()[name] = { text = "[name]", attachTo = "HEALTH", position = "CENTER", xOffset = 0, yOffset = 0, fontSize = 12, colorClass = false }
				newCTName = ""
				Refresh()
				S.options = S:BuildOptions() ACR:NotifyChange("SentinelUI")
			end,
		},
	}
	local order = 10
	for name, ct in pairs(Texts()) do
		local ctn = name
		local function CT() return Texts()[ctn] end
		args["ct_" .. ctn] = {
			type = "group", inline = true, order = order, name = ctn,
			args = {
				text = {
					type = "input", order = 1, name = L["Text"], width = "double",
					get = function() return CT().text end,
					set = function(_, v) CT().text = strtrim(v or "") Refresh() end,
				},
				attachTo = {
					type = "select", order = 2, name = L["Attach To"], values = selects.attachTo,
					get = function() return CT().attachTo or "HEALTH" end,
					set = function(_, v) CT().attachTo = v Refresh() end,
				},
				position = {
					type = "select", order = 3, name = L["Position"], values = POINTS,
					get = function() return CT().position or "CENTER" end,
					set = function(_, v) CT().position = v Refresh() end,
				},
				fontSize = {
					type = "range", order = 4, name = L["Font Size"], min = 6, max = 32, step = 1,
					get = function() return CT().fontSize or 12 end,
					set = function(_, v) CT().fontSize = v Refresh() end,
				},
				xOffset = {
					type = "range", order = 5, name = L["X Offset"], min = -300, max = 300, step = 1,
					get = function() return CT().xOffset or 0 end,
					set = function(_, v) CT().xOffset = v Refresh() end,
				},
				yOffset = {
					type = "range", order = 6, name = L["Y Offset"], min = -300, max = 300, step = 1,
					get = function() return CT().yOffset or 0 end,
					set = function(_, v) CT().yOffset = v Refresh() end,
				},
				colorClass = {
					type = "toggle", order = 7, name = L["Class Color"],
					get = function() return CT().colorClass end,
					set = function(_, v) CT().colorClass = v Refresh() end,
				},
				delete = {
					type = "execute", order = 8, name = L["Delete Text"],
					func = function()
						Texts()[ctn] = nil
						Refresh()
						S.options = S:BuildOptions() ACR:NotifyChange("SentinelUI")
					end,
				},
			},
		}
		order = order + 1
	end
	return args
end

-- click-cast bindings on unit frames ----------------------------------------
local CC_BUTTONS = { ["1"] = L["Left Button"], ["2"] = L["Right Button"], ["3"] = L["Middle Button"], ["4"] = L["Button 4"], ["5"] = L["Button 5"] }
local CC_MODS = { none = L["None"], shift = "Shift", ctrl = "Ctrl", alt = "Alt" }
local CC_TYPES = { spell = L["Cast Spell"], macro = L["Run Macro"], item = L["Use Item"], target = L["Target Unit"], togglemenu = L["Toggle Menu"], focus = L["Set Focus"] }
local function ClickCastOptions(getCC)
	local function CC()
		local cc = getCC and getCC() or S.db.profile.unitframes.clickCast
		if not cc then cc = { enable = false, bindings = {} } end
		if not cc.bindings then cc.bindings = {} end
		return cc
	end
	local args = {
		desc = {
			type = "description", order = 0, fontSize = "medium",
			name = L["Cast spells/macros by clicking on unit frames. Bindings with a modifier never block normal clicks; an unmodified binding REPLACES the default click (left = target, right = menu)."],
		},
		enable = {
			type = "toggle", order = 1, name = L["Enable Click Casting"],
			get = function() return CC().enable end, set = function(_, v) CC().enable = v Refresh() end,
		},
		add = {
			type = "execute", order = 2, name = L["Add Binding"],
			func = function()
				CC().bindings[#CC().bindings + 1] = { button = "1", mod = "none", type = "spell", value = "" }
				S.options = S:BuildOptions() ACR:NotifyChange("SentinelUI")
			end,
		},
	}
	for i, b in ipairs(CC().bindings) do
		local idx = i
		local function B() return CC().bindings[idx] end
		args["b" .. idx] = {
			type = "group", inline = true, order = 10 + idx,
			name = format("%s %d", L["Binding"], idx),
			args = {
				mod = {
					type = "select", order = 1, name = L["Modifier"], values = CC_MODS,
					get = function() return B().mod or "none" end, set = function(_, v) B().mod = v Refresh() end,
				},
				button = {
					type = "select", order = 2, name = L["Button"], values = CC_BUTTONS,
					get = function() return B().button or "1" end, set = function(_, v) B().button = v Refresh() end,
				},
				type = {
					type = "select", order = 3, name = L["Action"], values = CC_TYPES,
					get = function() return B().type or "spell" end, set = function(_, v) B().type = v Refresh() end,
				},
				value = {
					type = "input", order = 4, name = L["Spell / Macro / Item name"], width = "double",
					get = function() return B().value or "" end, set = function(_, v) B().value = strtrim(v or "") Refresh() end,
				},
				del = {
					type = "execute", order = 5, name = L["Delete Binding"],
					func = function()
						tremove(CC().bindings, idx)
						S.options = S:BuildOptions() ACR:NotifyChange("SentinelUI")
					end,
				},
			},
		}
	end
	return args
end

local selBarIdx = 1
local function ButtonBarOptions()
	local BB = S:GetModule("ButtonBars")
	local function DB() return S.db.profile.buttonBars end
	local function Bar() local b = DB().bars return b[selBarIdx] or b[1] end
	local function Touch()
		if BB then BB:Update() end
	end
	local function BarNames()
		local t = {}
		for i, b in ipairs(DB().bars) do t[i] = (b.hidden and "|cff777777" or "") .. (b.name or ("Bar " .. i)) .. "|r" end
		return t
	end

	local args = {
		enabled = { type = "toggle", order = 1, name = L["Enable"], width = "full",
			get = function() return DB().enabled end,
			set = function(_, v) DB().enabled = v S:StaticReload() end },
		general = { type = "group", order = 2, name = L["General"], inline = true, args = {
			grabMinimap = { type = "toggle", order = 1, name = L["Collect minimap buttons"], get = function() return DB().grabMinimap end, set = function(_, v) DB().grabMinimap = v Touch() end },
			collectSUI = { type = "toggle", order = 2, name = L["Collect SentinelUI buttons"], get = function() return DB().collectSUI end, set = function(_, v) DB().collectSUI = v Touch() end },
			grabLDB = { type = "toggle", order = 3, name = L["Create LDB launcher buttons"], get = function() return DB().grabLDB end, set = function(_, v) DB().grabLDB = v Touch() end },
			ldbAny = { type = "toggle", order = 4, name = L["LDB: any type with icon"], get = function() return DB().ldbAny end, set = function(_, v) DB().ldbAny = v Touch() end },
			grabBlizzard = { type = "toggle", order = 5, name = L["Collect Blizzard buttons"], desc = L["Tracking, mail, queue, zoom, world map, calendar"], get = function() return DB().grabBlizzard end, set = function(_, v) DB().grabBlizzard = v Touch() end },
			interceptTooltip = { type = "toggle", order = 6, name = L["Anchor tooltips to the bar"], get = function() return DB().interceptTooltip end, set = function(_, v) DB().interceptTooltip = v end },
			petBattleHide = { type = "toggle", order = 7, name = L["Hide in pet battles"], get = function() return DB().petBattleHide end, set = function(_, v) DB().petBattleHide = v Touch() end },
			customGrab = { type = "input", order = 8, name = L["Grab frames (comma separated)"], width = "double", get = function() return DB().customGrab end, set = function(_, v) DB().customGrab = v Touch() end },
			ignorePatterns = { type = "input", order = 9, name = L["Ignore patterns (Lua, comma separated)"], width = "double", get = function() return DB().ignorePatterns end, set = function(_, v) DB().ignorePatterns = v Touch() end },
		} },
		barPick = { type = "group", order = 3, name = L["Bars"], inline = true, args = {
			sel = { type = "select", order = 1, name = L["Bar"], values = BarNames,
				get = function() return selBarIdx end, set = function(_, v) selBarIdx = v end },
			barName = { type = "input", order = 2, name = L["Name"],
				get = function() return Bar().name end, set = function(_, v) Bar().name = v Touch() end },
			addBar = { type = "execute", order = 3, name = L["New Bar"], func = function()
				local b = DB().bars
				b[#b + 1] = {
					name = L["Bar"] .. " " .. (#b + 1), mode = "EDGE", anchor = "top", expand = 2,
					position = 0, secondPosition = 0, orientation = "AUTO", dirV = "AUTO", dirH = "AUTO",
					showHandler = "HOVER", hideHandler = "LEAVE", showDelay = 0, hideDelay = 0.6,
					fade = true, fadeOpacity = 0.4, size = 8, buttonSize = 26, spacing = 3, offset = 5,
					lineWidth = 6, gap = 2, strata = 1, bgAlpha = 0.75, border = true,
					lock = false, hidden = false, ombDistance = 6, omb = {},
				}
				selBarIdx = #b
				if BB then BB:RebuildBars() end
			end },
			delBar = { type = "execute", order = 4, name = L["Delete Bar"], disabled = function() return #DB().bars <= 1 end,
				func = function()
					tremove(DB().bars, min(selBarIdx, #DB().bars))
					selBarIdx = 1
					if BB then BB:RebuildBars() end
				end },
		} },
		barCfg = { type = "group", order = 4, name = L["Bar Settings"], args = {
			hidden = { type = "toggle", order = 1, name = L["Hide bar"], get = function() return Bar().hidden end, set = function(_, v) Bar().hidden = v Touch() end },
			lock = { type = "toggle", order = 2, name = L["Lock"], desc = L["Alt+Right click on the handle toggles this too"], get = function() return Bar().lock end, set = function(_, v) Bar().lock = v Touch() end },
			mode = { type = "select", order = 3, name = L["Handle"],
				values = { EDGE = L["Screen edge + drag line"], MINIMAP = L["Own minimap button"], DOCK = L["Docked in data strip"] },
				get = function() return Bar().mode end, set = function(_, v) Bar().mode = v if BB then BB:RebuildBars() end end },
			panel = { type = "select", order = 3.5, name = L["Data strip"], hidden = function() return Bar().mode ~= "DOCK" end,
				values = function()
					local t = {}
					local DT = S:GetModule("DataTexts")
					if DT and DT.panels then
						for k in pairs(DT.panels) do t[k] = k end
					end
					if not t.LeftChat then t.LeftChat = "LeftChat" end
					return t
				end,
				get = function() return Bar().panel or "LeftChat" end, set = function(_, v) Bar().panel = v if BB then BB:RebuildBars() end end },
			dockReset = { type = "execute", order = 3.6, name = L["Reset dock button"], hidden = function() return Bar().mode ~= "DOCK" or not Bar().dockPos end,
				func = function() Bar().dockPos = nil if BB then BB:RebuildBars() end end },
			dockGrow = { type = "select", order = 3.7, name = L["Expand direction"], hidden = function() return Bar().mode ~= "DOCK" end,
				values = { AUTO = L["Auto"], UP = L["Up"], DOWN = L["Down"], LEFT = L["Left"], RIGHT = L["Right"] },
				get = function() return Bar().dockGrow or "AUTO" end, set = function(_, v) Bar().dockGrow = v Touch() end },
			anchor = { type = "select", order = 4, name = L["Screen edge"], hidden = function() return Bar().mode ~= "EDGE" end,
				values = { left = L["Left"], right = L["Right"], top = L["Top"], bottom = L["Bottom"] },
				get = function() return Bar().anchor end, set = function(_, v) Bar().anchor = v Touch() end },
			expand = { type = "select", order = 5, name = L["Anchor point"], hidden = function() return Bar().mode ~= "EDGE" end,
				values = function()
					local a = Bar().anchor
					if a == "left" or a == "right" then return { [0] = L["Below"], [1] = L["Above"], [2] = L["Centered"] } end
					return { [0] = L["Right"], [1] = L["Left"], [2] = L["Centered"] }
				end,
				get = function() return Bar().expand end, set = function(_, v) Bar().expand = v Touch() end },
			orientation = { type = "select", order = 6, name = L["Orientation"],
				values = { AUTO = L["Auto"], HORIZONTAL = L["Horizontal"], VERTICAL = L["Vertical"] },
				get = function() return Bar().orientation end, set = function(_, v) Bar().orientation = v Touch() end },
			dirH = { type = "select", order = 7, name = L["Horizontal growth"],
				values = { AUTO = L["Auto"], LEFT = L["Left"], RIGHT = L["Right"] },
				get = function() return Bar().dirH end, set = function(_, v) Bar().dirH = v Touch() end },
			dirV = { type = "select", order = 8, name = L["Vertical growth"],
				values = { AUTO = L["Auto"], TOP = L["Down"], BOTTOM = L["Up"] },
				get = function() return Bar().dirV end, set = function(_, v) Bar().dirV = v Touch() end },
			size = { type = "range", order = 10, name = L["Buttons per row"], min = 1, max = 40, step = 1,
				get = function() return Bar().size end, set = function(_, v) Bar().size = v Touch() end },
			buttonSize = { type = "range", order = 11, name = L["Button size"], min = 12, max = 48, step = 1,
				get = function() return Bar().buttonSize end, set = function(_, v) Bar().buttonSize = v Touch() end },
			spacing = { type = "range", order = 12, name = L["Spacing"], min = 0, max = 20, step = 1,
				get = function() return Bar().spacing end, set = function(_, v) Bar().spacing = v Touch() end },
			offset = { type = "range", order = 13, name = L["Padding"], min = 0, max = 20, step = 1,
				get = function() return Bar().offset end, set = function(_, v) Bar().offset = v Touch() end },
			lineWidth = { type = "range", order = 14, name = L["Handle width"], hidden = function() return Bar().mode ~= "EDGE" end, min = 2, max = 20, step = 1,
				get = function() return Bar().lineWidth end, set = function(_, v) Bar().lineWidth = v Touch() end },
			gap = { type = "range", order = 15, name = L["Handle gap"], hidden = function() return Bar().mode ~= "EDGE" end, min = 0, max = 20, step = 1,
				get = function() return Bar().gap end, set = function(_, v) Bar().gap = v Touch() end },
			ombDistance = { type = "range", order = 16, name = L["Distance to button"], hidden = function() return Bar().mode == "EDGE" end, min = 0, max = 60, step = 1,
				get = function() return Bar().ombDistance end, set = function(_, v) Bar().ombDistance = v Touch() end },
			strata = { type = "select", order = 17, name = L["Frame Strata"],
				values = { [1] = "MEDIUM", [2] = "HIGH", [3] = "DIALOG", [4] = "FULLSCREEN", [5] = "FULLSCREEN_DIALOG" },
				get = function() return Bar().strata end, set = function(_, v) Bar().strata = v Touch() end },
			bgAlpha = { type = "range", order = 18, name = L["Background opacity"], min = 0, max = 1, step = 0.05,
				get = function() return Bar().bgAlpha end, set = function(_, v) Bar().bgAlpha = v Touch() end },
			border = { type = "toggle", order = 19, name = L["Border"], get = function() return Bar().border end, set = function(_, v) Bar().border = v Touch() end },
			showHandler = { type = "select", order = 20, name = L["Open on"],
				values = { HOVER = L["Mouseover"], CLICK = L["Click"], ALWAYS = L["Always visible"] },
				get = function() return Bar().showHandler end, set = function(_, v) Bar().showHandler = v Touch() end },
			hideHandler = { type = "select", order = 21, name = L["Close on"], hidden = function() return Bar().showHandler == "ALWAYS" end,
				values = { LEAVE = L["Mouse leave"], CLICKOUT = L["Click outside"], BOTH = L["Both"], NEVER = L["Only via handle"] },
				get = function() return Bar().hideHandler end, set = function(_, v) Bar().hideHandler = v Touch() end },
			showDelay = { type = "range", order = 22, name = L["Open delay"], hidden = function() return Bar().showHandler ~= "HOVER" end, min = 0, max = 3, step = 0.05,
				get = function() return Bar().showDelay end, set = function(_, v) Bar().showDelay = v end },
			hideDelay = { type = "range", order = 23, name = L["Close delay"], min = 0, max = 5, step = 0.05,
				get = function() return Bar().hideDelay end, set = function(_, v) Bar().hideDelay = v end },
			fade = { type = "toggle", order = 24, name = L["Fade when idle"], get = function() return Bar().fade end, set = function(_, v) Bar().fade = v Touch() end },
			fadeOpacity = { type = "range", order = 25, name = L["Fade opacity"], min = 0, max = 1, step = 0.05,
				get = function() return Bar().fadeOpacity end, set = function(_, v) Bar().fadeOpacity = v Touch() end },
		} },
		buttons = { type = "group", order = 5, name = L["Collected Buttons"], args = (function()
			local bArgs = {}
			if not BB then return bArgs end
			local names = {}
			for _, btn in ipairs(BB.buttons) do
				local p = BB.grabbed[btn]
				if p and p.name then names[#names + 1] = p.name end
			end
			sort(names)
			for i, n in ipairs(names) do
				bArgs["b" .. i] = { type = "group", order = i, name = n, inline = true, args = {
					collect = { type = "toggle", order = 1, name = L["Collect"],
						get = function() local c = BB:BtnCfg(n) return not c.ignore end,
						set = function(_, v) BB:BtnCfg(n).ignore = not v BB:ApplyButtonSettings() end },
					off = { type = "toggle", order = 2, name = L["Hidden in bar"],
						get = function() return BB:BtnCfg(n).off and true or false end,
						set = function(_, v) BB:BtnCfg(n).off = v Touch() end },
					auto = { type = "toggle", order = 3, name = L["Auto show/hide"], desc = L["Follows the original addon's visibility (e.g. mail icon only when mail waits)"],
						get = function() return BB:BtnCfg(n).auto ~= false end,
						set = function(_, v) BB:BtnCfg(n).auto = v Touch() end },
					order = { type = "range", order = 4, name = L["Order"], min = 0, max = 99, step = 1,
						get = function() return BB:BtnCfg(n).order or 0 end,
						set = function(_, v) BB:BtnCfg(n).order = v > 0 and v or nil Touch() end },
					bar = { type = "select", order = 5, name = L["Bar"], values = BarNames,
						get = function() return BB:BtnCfg(n).bar or 1 end,
						set = function(_, v) BB:BtnCfg(n).bar = v Touch() end },
				} }
			end
			if #names == 0 then
				bArgs.empty = { type = "description", order = 1, name = L["No buttons collected yet."] }
			end
			return bArgs
		end)() },
	}
	return args
end

function S:BuildOptions()
	local root = BuildGroup(nil, self.defaults.profile, {}, 0)
	root.name = self.title .. " |cffaaaaaav" .. self.version .. "|r"
	root.args.movers = nil

	local titles = {
		general = L["General"], actionbars = L["Action Bars"], unitframes = L["Unit Frames"], nameplates = L["Nameplates"],
		auras = L["Auras"], tooltip = L["Tooltip"], bags = L["Bags"], chat = L["Chat"], datatexts = L["Data Texts"],
		databars = L["Data Bars"], minimap = L["Minimap"], skins = L["Skins"], navigation = L["Navigation"],
		damagemeter = L["Damage Meter"], raidcd = L["Raid Cooldowns"], dottracker = L["DoT Tracker"],
	itemsync = L["Item Sync"], bugfolder = L["BugFolder"], worldmap = L["World Map"], instancetracker = L["Instance Tracker"],
	worldbuffs = L["World Buffs"], guildchronicle = L["Guild Chronicle"],
		interruptalert = L["Interrupt Alert"], healerprot = L["Healer Protection"], blessings = L["Blessings"], raidcheck = L["Raid Check"], raidgrid = L["Heal Grid"],
		totemforge = L["Totem Forge"], bosswatch = L["Boss Watch"], questscope = L["Quest Scope"], bisguide = L["BiS Guide"],
		lootbrowser = L["Loot Browser"], pulltimer = L["Pull Timer"], screenshots = L["Screenshots"],
		manatick = L["Mana Tick"], swingtimer = L["Swing Timer"], summonhelper = L["Summon Helper"],
		profcds = L["Profession Cooldowns"], zeptimer = L["Ship Timer"], raidmarker = L["Raid Marker"],
		mailgetall = L["Mail Get All"], counters = L["Counters"], executealert = L["Execute Alert"],
		rangedisplay = L["Range Display"], pethappiness = L["Pet Happiness"], enemyradar = L["Enemy Radar"],
		gathernotes = L["Gather Notes"], cooldowntracker = L["Cooldown Tracker"], diminishing = L["Diminishing Returns"],
		potionreminder = L["Potion Reminder"], combatlog = L["Combat Log"],
		foodreminder = L["Food Reminder"], weaponskill = L["Weapon Skills"], spellsearch = L["Spell Search"],
		questitems = L["Quest Items"], cursorring = L["Cursor Ring"],
		groupbulletin = L["Group Bulletin"], trinkettracker = L["Trinket Tracker"],
		timermodule = L["Timer"], autoaccept = L["Auto Accept"],
		disenchant = L["Disenchant Info"], craftqueue = L["Craft Queue"],
		bgtools = L["BG Tools"], mapinfo = L["Map Info"],
		fastloot = L["Fast Loot"], deathrecap = L["Death Recap"], procalert = L["Proc Alert"],
		weaponbuff = L["Weapon Buff"], spamfilter = L["Spam Filter"],
		interrupttracker = L["Interrupt Tracker"], altroster = L["Characters"],
		lootfilter = L["Loot Filter"], rezannouncer = L["Rez Announcer"], fearward = L["Fear Ward"],
		selfbuffs = L["Self Buffs"], keywordinvite = L["Keyword Invite"], huntertools = L["Hunter Tools"],
		ccbreak = L["CC Break"], tauntresist = L["Taunt Resist"], aggroalert = L["Aggro Alert"], threatmeter = L["Threat Meter"],
		purgealert = L["Purge Alert"], soulstonetracker = L["Soulstones"], targetcounter = L["Target Counter"],
		enemycastannounce = L["Enemy Cast Announce"], bopwarn = L["BoP Warning"], banishtimer = L["Banish Timer"],
		externalbuffs = L["External Buffs"], flighttimer = L["Flight Timer"],
		lfgenhance = L["LFG Enhance"], clickcast = L["Click Cast"], aurawatcher = L["Aura Watch"],
		pricehistory = L["Price History"], loothistory = L["Loot History"], speedrun = L["Instance Timer"],
		rankreminder = L["Rank Reminder"], sessionstats = L["Session Stats"], fishinghelper = L["Fishing"],
		auctionhouse = L["Auction House"],
	}
	local order = { "general", "actionbars", "unitframes", "nameplates", "auras", "tooltip", "bags", "chat", "datatexts", "databars", "minimap", "navigation", "damagemeter", "raidcd", "dottracker", "skins", "itemsync", "bugfolder", "worldmap", "instancetracker", "worldbuffs", "guildchronicle", "interruptalert", "healerprot", "blessings", "raidcheck", "raidgrid", "totemforge", "bosswatch", "questscope", "bisguide", "lootbrowser", "pulltimer", "screenshots", "manatick", "swingtimer", "summonhelper", "profcds", "zeptimer", "raidmarker", "mailgetall", "counters", "executealert", "rangedisplay", "pethappiness", "enemyradar", "gathernotes", "cooldowntracker", "diminishing", "potionreminder", "combatlog", "groupbulletin", "trinkettracker", "timermodule", "autoaccept", "disenchant", "craftqueue",
		"bgtools", "mapinfo", "fastloot", "deathrecap", "procalert", "weaponbuff",
		"spamfilter", "interrupttracker", "altroster", "lootfilter", "rezannouncer", "fearward",
		"selfbuffs", "keywordinvite", "huntertools",
		"ccbreak", "tauntresist", "aggroalert", "threatmeter", "purgealert", "soulstonetracker",
		"targetcounter", "enemycastannounce", "bopwarn", "banishtimer",
		"externalbuffs", "flighttimer", "lfgenhance",
		"clickcast", "aurawatcher", "pricehistory", "loothistory",
		"speedrun", "rankreminder", "sessionstats", "fishinghelper", "auctionhouse",
		"foodreminder", "weaponskill", "spellsearch", "questitems", "cursorring" }
	for i, k in ipairs(order) do
		if root.args[k] then
			root.args[k].name = titles[k]
			root.args[k].order = 10 + i
			root.args[k].inline = false
			root.args[k].childGroups = "tab"
		end
	end
	local unitOrder = { "player", "target", "targettarget", "focus", "focustarget", "pet", "pettarget", "party", "partypet", "raid", "raid40", "maintank", "boss", "arena" }
	local unitTitles = {
		player = L["Player"], target = L["Target"], targettarget = L["Target of Target"], focus = L["Focus"], focustarget = L["Focus Target"],
		pet = L["Pet"], pettarget = L["Pet Target"], party = L["Party"], partypet = L["Party Pets"], raid = L["Raid"], raid40 = L["Raid 40"], maintank = L["Main Tanks"],
		boss = L["Boss"], arena = L["Arena"],
	}
	if root.args.unitframes then root.args.unitframes.childGroups = "tree" end
	if root.args.nameplates then
		root.args.nameplates.args.customTexts = {
			type = "group", name = L["Custom Texts"], order = 50,
			args = CustomTextOptions(nil, function() return S.db.profile.nameplates end),
		}
	end
	if root.args.unitframes and root.args.unitframes.args.units then
		local units = root.args.unitframes.args.units
		units.childGroups = "tree"
		units.name = L["Units"]
		units.order = 1
		for k, g in pairs(units.args) do
			g.childGroups = "tab"
			g.inline = false
			g.name = unitTitles[k] or g.name
			g.order = IndexOf(unitOrder, k) or 50
			if (k == "focus" or k == "focustarget") and self.isClassic then g.hidden = true end
			if (k == "boss") and (self.isClassic or self.isTBC) then g.hidden = true end
			if k == "arena" and self.isClassic then g.hidden = true end
			g.args.customTexts = { type = "group", name = L["Custom Texts"], order = 50, args = CustomTextOptions(k) }
			-- convenience picker for the power-bar text: presets or a custom tag string
			local pa = g.args.power and g.args.power.args
			if pa then
				pa.textFormat = {
					type = "select", order = 0, name = L["Text Format"], width = "double",
					values = POWER_TEXT_FORMATS, sorting = POWER_TEXT_SORTING,
					get = function()
						local t = S.db.profile.unitframes.units[k].power.text or ""
						return POWER_TEXT_FORMATS[t] and t or "__custom"
					end,
					set = function(_, v)
						if v == "__custom" then return end
						S.db.profile.unitframes.units[k].power.text = v
						Refresh()
					end,
				}
			end
		end
		if root.args.unitframes.args.colors then root.args.unitframes.args.colors.name = L["Colors"] root.args.unitframes.args.colors.order = 2 end
		root.args.unitframes.args.filters = { type = "group", name = L["Aura Filters"], order = 3, args = FilterOptions() }
		root.args.unitframes.args.tags = { type = "group", name = L["Tags"], order = 4, args = { help = { type = "description", fontSize = "medium", name = function() return S:GetModule("UnitFrames"):TagHelp() end } } }
		root.args.unitframes.args.clickcast = { type = "group", name = L["Click Cast"], order = 5, args = ClickCastOptions() }
	end
	if root.args.raidgrid then
		root.args.raidgrid.args.openCfg = { type = "execute", order = 20, width = "double",
			name = L["Open Heal Grid Settings"],
			func = function() S:GetModule("RaidGrid"):ToggleConfig() end }
		root.args.raidgrid.args.ccHelp = { type = "description", order = 21, width = "full",
			name = L["Spell assignment, click-casting and layout live in the dedicated Heal Grid options window (right-click the HG minimap button or the small anchor above the grid). Tip: 'heal'/'dispel' auto-cast your class spells."] }
	end
	if root.args.actionbars then
		local barOrder = { "bar1", "bar2", "bar3", "bar4", "bar5", "bar6", "bar7", "bar8", "barPet", "barStance", "microbar", "bagbar" }
		local barTitles = {
			bar1 = L["Action Bar 1"], bar2 = L["Action Bar 2"], bar3 = L["Action Bar 3"], bar4 = L["Action Bar 4"], bar5 = L["Action Bar 5"],
			bar6 = L["Action Bar 6"], bar7 = L["Action Bar 7"], bar8 = L["Action Bar 8"], barPet = L["Pet Bar"], barStance = L["Stance Bar"],
			microbar = L["Micro Menu"], bagbar = L["Bag Bar"],
		}
		local general = { type = "group", name = L["General"], order = 1, args = {} }
		for k, g in pairs(root.args.actionbars.args) do
			if g.type == "group" then
				g.inline = false
				g.name = barTitles[k] or g.name
				g.order = 10 + (IndexOf(barOrder, k) or 50)
				if (k == "bar7" or k == "bar8") and not self.isRetail then g.hidden = true end
			else
				general.args[k] = g
				root.args.actionbars.args[k] = nil
			end
		end
		root.args.actionbars.args.general = general
	end
	if root.args.datatexts then
		root.args.datatexts.args.panelsGroup = { type = "group", name = L["Panels"], order = 1, args = DataTextOptions() }
	end

	root.args.buttonBars = { type = "group", name = L["Button Bars"], order = 23, childGroups = "tab", args = ButtonBarOptions() }

	-- integrated RL BetterItem module: full settings live in its own window
	root.args.betteritem = {
		type = "group", name = "BetterItem", order = 24, childGroups = "tab",
		args = {
			intro = { type = "description", order = 1, fontSize = "medium",
				name = L["BetterItem shows item scores, upgrade comparisons, stat weights, outfits and more. It is fully integrated - the standalone addon is not needed."] },
			open = { type = "execute", order = 2, width = "double", name = L["Open BetterItem Settings"],
				func = function()
					if RLBetterItem then
						if not RLBetterItem.mainFrame and RLBetterItem.CreateMainFrame then RLBetterItem:CreateMainFrame() end
						if RLBetterItem.mainFrame then RLBetterItem.mainFrame:Show() end
					end
				end },
			minimapBtn = { type = "toggle", order = 3, name = L["Minimap Button"],
				get = function() return not (RLBetterItem and RLBetterItem.db and RLBetterItem.db.minimap and RLBetterItem.db.minimap.hide) end,
				set = function(_, v)
					if RLBetterItem and RLBetterItem.db then
						RLBetterItem.db.minimap.hide = not v
						if RLBetterItem.minimapButton then RLBetterItem.minimapButton:SetShown(v) end
					end
				end },
		},
	}

	-- BugFolder / ItemSync: full option pages (action buttons + labelled
	-- settings) on top of the auto-generated toggles
	if root.args.bugfolder and root.args.bugfolder.args then
		local a = root.args.bugfolder.args
		a.intro = { type = "description", order = 0, fontSize = "medium",
			name = L["BugFolder captures every Lua error from all addons (BugGrabber + BugSack replacement). Errors land in the sack window with stack trace and locals."] }
		a.open = { type = "execute", order = 0.5, width = "normal", name = L["Open sack"],
			func = function() local m = S:GetModule("BugFolder") if m then m:OpenSack() end end }
		a.export = { type = "execute", order = 0.6, width = "normal", name = L["Export"],
			func = function() local m = S:GetModule("BugFolder") if m then m:OpenExport() end end }
		a.wipe = { type = "execute", order = 0.7, width = "normal", name = L["Wipe bugs"], confirm = true,
			func = function() local m = S:GetModule("BugFolder") if m then m:Wipe() end end }
		local N = {
			auto = { L["Auto popup"], L["Opens the sack automatically when an error occurs (not in combat)."] },
			chatframe = { L["Chat output"], L["Prints a reminder to the chat when an error is captured."] },
			mute = { L["Mute"], L["No sound when an error is detected."] },
			minimapIcon = { L["Minimap icon"], L["Shows the BugFolder icon around the minimap."] },
			fontSize = { L["Font size"], nil },
			altwipe = { L["Minimap icon alt-click wipe"], L["Alt-click on the minimap icon wipes all stored bugs."] },
			useMaster = { L["Use 'Master' sound channel"], L["Play the error sound over the 'Master' channel instead of the default one."] },
			saveErrors = { L["Save errors"], L["Persists bugs across sessions. Off = session only."] },
			throttle = { L["Throttle at excessive amount"], L["Limits capture when addons spam hundreds of errors per second."] },
			filterAddonMistakes = { L["Filter addon mistakes"], L["Ignore ADDON_ACTION_BLOCKED / _FORBIDDEN events."] },
			errorSound = { L["Sound"], L["'None' plays the built-in error sound."] },
		}
		for k, v in pairs(N) do if a[k] then a[k].name = v[1] a[k].desc = v[2] end end
	end
	if root.args.itemsync and root.args.itemsync.args then
		local a = root.args.itemsync.args
		a.intro = { type = "description", order = 0, fontSize = "medium",
			name = L["ItemSync tracks item counts per character across bags, bank, mail, equipment and the guild bank (BagSync replacement) and shows them in item tooltips."] }
		a.openSearch = { type = "execute", order = 0.5, width = "normal", name = L["Open item search"],
			func = function() local m = S:GetModule("ItemSync") if m then m:OpenSearch() end end }
		a.wipe = { type = "execute", order = 0.6, width = "normal", name = L["Wipe item data"], confirm = true,
			func = function() local m = S:GetModule("ItemSync") if m then wipe(S.db.global.itemSync or {}) S:Print("ItemSync wiped.") end end }
		local N = {
			countCurrent = { L["Count current character"], L["Also show counts for the logged-in character in tooltips."] },
			countBags = { L["Bags"], L["Show bag counts in tooltips."] },
			countBank = { L["Bank"], L["Show bank counts in tooltips."] },
			countEquip = { L["Equipped"], L["Show equipped counts in tooltips."] },
			countMail = { L["Mail"], L["Show mailbox counts in tooltips."] },
			countGuild = { L["Guild bank"], L["Show guild bank counts in tooltips."] },
		}
		for k, v in pairs(N) do if a[k] then a[k].name = v[1] a[k].desc = v[2] end end
	end

	root.args.info = {
		type = "group", name = L["Start"], order = 1,
		args = {
			logo = { type = "description", name = "", image = self.media.logo, imageWidth = 96, imageHeight = 96, order = 1, width = 0.6 },
			intro = { type = "description", name = "|cffffffff" .. L["SentinelUI is a complete interface replacement. Use the buttons below or the tree on the left to configure everything."] .. "|r\n\n" .. format(L["Client: %s  |  Interface: %s"], self.flavor, tostring(self.interface)) .. "\n" .. L["Website"] .. ": |cff" .. self.accentHex .. "https://xrl-dev.de/|r", order = 2, fontSize = "medium", width = 2.4 },
			movers = { type = "execute", name = L["Toggle Movers"], order = 10, func = function() S:ToggleMovers() end },
			keybind = { type = "execute", name = L["Keybind Mode"], order = 11, func = function() local ab = S:GetModule("ActionBars") if ab and ab.initialized then ab:ToggleKeybindMode() end end },
			install = { type = "execute", name = L["Installation"], order = 12, func = function() S:ShowInstall() end },
			log = { type = "execute", name = L["Error Log"], order = 13, func = function() S:ShowLog() end },
			reload = { type = "execute", name = L["Reload UI"], order = 14, func = ReloadUI },
			resetMovers = { type = "execute", name = L["Reset Positions"], order = 15, func = function() StaticPopup_Show("SENTINELUI_RESET_MOVERS") end },
			resetWindows = { type = "execute", name = L["Reset Window Positions"], order = 15.5, func = function() local wm = S:GetModule("WindowMover") if wm and wm.Reset then wm:Reset() end end },
			bugReport = { type = "execute", name = L["Report a Bug"], order = 16, func = function() S:ShowBugtracker() end },
			logInfo = { type = "description", order = 20, name = "\n" .. L["All SentinelUI errors are saved to WTF\\Account\\<Account>\\SavedVariables\\SentinelUI.lua (written on /reload or logout)."] },
			bugHeader = { type = "header", order = 30, name = L["Bugtracker"] },
			bugDesc = { type = "description", order = 31, fontSize = "medium", name = L["Found a bug? Please report it with the error log (/sui log -> Select all) at:"] },
			bugLink = { type = "input", order = 32, width = "double", name = "", get = function() return S.bugtracker end, set = function() end },
		},
	}

	local m = { type = "group", name = L["Modules"], order = 2, args = {} }
	local mods = {
		{ "actionbars", L["Action Bars"] }, { "unitframes", L["Unit Frames"] }, { "nameplates", L["Nameplates"] }, { "auras", L["Auras"] },
		{ "tooltip", L["Tooltip"] }, { "bags", L["Bags"] }, { "chat", L["Chat"] }, { "datatexts", L["Data Texts"] }, { "databars", L["Data Bars"] },
		{ "minimap", L["Minimap"] }, { "misc", L["Misc"] }, { "afk", L["AFK Screen"] }, { "skins", L["Skins"] }, { "windowmover", L["Window Mover"] },
		{ "raidcd", L["Raid Cooldowns"] }, { "dottracker", L["DoT Tracker"] }, { "trainer", L["Trainer"] }, { "raidreset", L["Instance Resets"] }, { "decurse", L["Decurse"] },
		{ "rep", L["Reputation"] }, { "itemsync", L["Item Sync"] }, { "bugfolder", L["BugFolder"] }, { "messenger", L["Messenger"] }, { "seelast", L["SeeLast"] },
		{ "buttonbars", L["Button Bars"] }, { "announcer", L["Announcer"] }, { "magebar", L["Mage Bar"] }, { "navigation", L["Navigation"] }, { "damagemeter", L["Damage Meter"] },
		{ "worldmap", L["World Map"] }, { "instancetracker", L["Instance Tracker"] }, { "worldbuffs", L["World Buffs"] },
		{ "guildchronicle", L["Guild Chronicle"] },
		{ "interruptalert", L["Interrupt Alert"] }, { "healerprot", L["Healer Protection"] }, { "blessings", L["Blessings"] },
		{ "raidcheck", L["Raid Check"] }, { "raidgrid", L["Heal Grid"] }, { "totemforge", L["Totem Forge"] },
		{ "bosswatch", L["Boss Watch"] }, { "questscope", L["Quest Scope"] }, { "bisguide", L["BiS Guide"] },
		{ "lootbrowser", L["Loot Browser"] },
		{ "pulltimer", L["Pull Timer"] }, { "screenshots", L["Screenshots"] }, { "manatick", L["Mana Tick"] },
		{ "swingtimer", L["Swing Timer"] }, { "summonhelper", L["Summon Helper"] }, { "profcds", L["Profession Cooldowns"] },
		{ "zeptimer", L["Ship Timer"] }, { "raidmarker", L["Raid Marker"] }, { "mailgetall", L["Mail Get All"] },
		{ "counters", L["Counters"] }, { "executealert", L["Execute Alert"] },
		{ "rangedisplay", L["Range Display"] }, { "pethappiness", L["Pet Happiness"] },
		{ "enemyradar", L["Enemy Radar"] }, { "gathernotes", L["Gather Notes"] },
		{ "cooldowntracker", L["Cooldown Tracker"] }, { "diminishing", L["Diminishing Returns"] },
		{ "potionreminder", L["Potion Reminder"] }, { "combatlog", L["Combat Log"] },
		{ "groupbulletin", L["Group Bulletin"] }, { "trinkettracker", L["Trinket Tracker"] },
		{ "timermodule", L["Timer"] }, { "autoaccept", L["Auto Accept"] },
		{ "disenchant", L["Disenchant Info"] }, { "craftqueue", L["Craft Queue"] },
		{ "bgtools", L["BG Tools"] }, { "mapinfo", L["Map Info"] },
		{ "fastloot", L["Fast Loot"] }, { "deathrecap", L["Death Recap"] },
		{ "procalert", L["Proc Alert"] }, { "weaponbuff", L["Weapon Buff"] },
		{ "spamfilter", L["Spam Filter"] }, { "interrupttracker", L["Interrupt Tracker"] },
		{ "altroster", L["Characters"] }, { "lootfilter", L["Loot Filter"] },
		{ "rezannouncer", L["Rez Announcer"] }, { "fearward", L["Fear Ward"] },
		{ "selfbuffs", L["Self Buffs"] }, { "keywordinvite", L["Keyword Invite"] },
		{ "huntertools", L["Hunter Tools"] }, { "ccbreak", L["CC Break"] },
		{ "tauntresist", L["Taunt Resist"] }, { "aggroalert", L["Aggro Alert"] }, { "threatmeter", L["Threat Meter"] },
		{ "purgealert", L["Purge Alert"] }, { "soulstonetracker", L["Soulstones"] },
		{ "targetcounter", L["Target Counter"] }, { "enemycastannounce", L["Enemy Cast Announce"] },
		{ "bopwarn", L["BoP Warning"] }, { "banishtimer", L["Banish Timer"] },
		{ "externalbuffs", L["External Buffs"] }, { "flighttimer", L["Flight Timer"] },
		{ "lfgenhance", L["LFG Enhance"] }, { "clickcast", L["Click Cast"] },
		{ "aurawatcher", L["Aura Watch"] }, { "pricehistory", L["Price History"] },
		{ "loothistory", L["Loot History"] }, { "speedrun", L["Instance Timer"] },
		{ "rankreminder", L["Rank Reminder"] }, { "sessionstats", L["Session Stats"] },
		{ "fishinghelper", L["Fishing"] }, { "auctionhouse", L["Auction House"] },
		{ "foodreminder", L["Food Reminder"] }, { "weaponskill", L["Weapon Skills"] }, { "spellsearch", L["Spell Search"] },
		{ "questitems", L["Quest Items"] }, { "cursorring", L["Cursor Ring"] },
	}
	m.args.desc = { type = "description", name = L["Enabling or disabling a module requires a reload. These settings are per character."], order = 0 }
	for i, info in ipairs(mods) do
		m.args[info[1]] = PrivateToggle(info[1], "enable", info[2], i)
	end
	m.args.blizz = { type = "header", name = L["Blizzard frames"], order = 50 }
	local bl = {
		{ "unitframes", "disableBlizzardPlayer", L["Hide Blizzard player frame"] }, { "unitframes", "disableBlizzardTarget", L["Hide Blizzard target frame"] },
		{ "unitframes", "disableBlizzardFocus", L["Hide Blizzard focus frame"] }, { "unitframes", "disableBlizzardParty", L["Hide Blizzard party frames"] },
		{ "unitframes", "disableBlizzardRaid", L["Hide Blizzard raid frames"] }, { "unitframes", "disableBlizzardBoss", L["Hide Blizzard boss frames"] },
		{ "actionbars", "hideBlizzard", L["Hide Blizzard action bars"] }, { "auras", "disableBlizzard", L["Hide Blizzard buffs"] }, { "bags", "bank", L["Use SentinelUI bank (Classic)"] },
	}
	for i, info in ipairs(bl) do m.args[info[1] .. info[2]] = PrivateToggle(info[1], info[2], info[3], 50 + i) end
	root.args.modules = m

	root.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
	root.args.profiles.order = 99
	root.args.profiles.childGroups = "tab"
	root.args.profiles.args.io = self:ProfileIOOptions()
	root.args.profiles.args.spec = self:SpecProfileOptions()

	-- search: filter the whole option tree, results jump to the option
	root.args.search = {
		type = "group", name = L["Search"], order = 0,
		args = {
			box = { type = "input", order = 1, width = "full", name = "",
				get = function() return self.searchQuery or "" end,
				set = function(_, v) self.searchQuery = v self:UpdateSearchResults() end },
		},
	}
	self:UpdateSearchResults(root)
	return root
end

local function OptName(arg)
	local name = arg.name
	if type(name) == "function" then
		local ok, v = pcall(name)
		name = ok and v or ""
	end
	if type(name) ~= "string" then return "" end
	return (name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("\n", " "))
end

local function OptHidden(arg)
	local h = arg.hidden
	if type(h) == "function" then local ok, v = pcall(h) return ok and v or false end
	return h and true or false
end

local function SearchScan(args, path, trail, q, out, cap)
	if #out >= cap then return end
	local keys = {}
	for k in pairs(args) do keys[#keys + 1] = k end
	sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	for _, key in ipairs(keys) do
		local arg = args[key]
		if type(arg) == "table" and key ~= "search" and not OptHidden(arg) then
			local name = OptName(arg)
			if arg.type == "group" then
				local p2, t2 = {}, trail
				for i, v in ipairs(path) do p2[i] = v end
				p2[#p2 + 1] = key
				if name ~= "" then t2 = (t2 == "") and name or (t2 .. "  |cff888888›|r  " .. name) end
				SearchScan(arg.args, p2, t2, q, out, cap)
			elseif arg.type ~= "header" and arg.type ~= "description" then
				local hay = name:lower()
				local ok, desc = pcall(function()
					return type(arg.desc) == "function" and arg.desc() or arg.desc
				end)
				if ok and type(desc) == "string" then hay = hay .. " " .. desc:lower() end
				if name ~= "" and hay:find(q, 1, true) then
					local p2 = {}
					for i, v in ipairs(path) do p2[i] = v end
					p2[#p2 + 1] = key
					out[#out + 1] = {
						path = p2,
						label = (trail ~= "" and (trail .. "  |cff888888›|r  ") or "") .. name,
					}
					if #out >= cap then return end
				end
			end
		end
	end
end

function S:UpdateSearchResults(root)
	root = root or self.options
	local args = root and root.args and root.args.search and root.args.search.args
	if not args then return end
	for k in pairs(args) do if k ~= "box" then args[k] = nil end end
	local q = (self.searchQuery or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if #q < 2 then
		args.hint = { type = "description", order = 2, name = L["Type at least 2 characters to search all settings. Click a result to jump to it."] }
		ACR:NotifyChange("SentinelUI")
		return
	end
	local results = {}
	SearchScan(root.args, {}, "", q, results, 40)
	args.count = { type = "description", order = 2, name = format(L["%d result(s)"], #results) }
	for i, r in ipairs(results) do
		local path = r.path
		args["res" .. i] = {
			type = "execute", order = 10 + i, width = "full",
			name = r.label,
			func = function() self:ToggleConfig(path) end,
		}
	end
	ACR:NotifyChange("SentinelUI")
end

function S:ToggleConfig(section)
	if InCombatLockdown() then self:Print(ERR_NOT_IN_COMBAT) return end
	if not self.optionsRegistered then
		LibStub("AceConfig-3.0"):RegisterOptionsTable("SentinelUI", function() return S.options end)
		ACD:SetDefaultSize("SentinelUI", 980, 700)
		self.optionsRegistered = true
	end
	self.options = self:BuildOptions()
	ACR:NotifyChange("SentinelUI")
	if ACD.OpenFrames.SentinelUI and not section then
		ACD:Close("SentinelUI")
		return
	end
	ACD:Open("SentinelUI")
	if section then
		if type(section) == "table" then
			ACD:SelectGroup("SentinelUI", unpack(section))
		else
			ACD:SelectGroup("SentinelUI", section)
		end
	end
	local widget = ACD.OpenFrames.SentinelUI
	if widget then
		S:SafeCall("Config:Style", S.StyleConfigWindow, S, widget)
		local frame = widget.frame
		if frame and not frame.suiMovableCfg then
			frame.suiMovableCfg = true
			frame:SetClampedToScreen(true)
		end
	end
end

-- Blizzard Settings entry with a button that opens our window
local panel = CreateFrame("Frame")
panel.name = "SentinelUI"
local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
btn:SetSize(200, 26)
btn:SetPoint("TOPLEFT", 16, -16)
btn:SetText(L["Open SentinelUI Options"])
btn:SetScript("OnClick", function()
	if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
	if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then HideUIPanel(InterfaceOptionsFrame) end
	if GameMenuFrame and GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame) end
	S:ToggleConfig()
end)
if Settings and Settings.RegisterCanvasLayoutCategory then
	local category = Settings.RegisterCanvasLayoutCategory(panel, "SentinelUI")
	Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
	InterfaceOptions_AddCategory(panel)
end
