-- Unit frame layouts: single units, boss/arena stacks and secure group headers.
local _, ns = ...
local S = ns.S
local L = S.L
local UF = S:GetModule("UnitFrames")

local _G = _G
local pairs, ipairs, format, max, ceil = pairs, ipairs, format, math.max, math.ceil

local singles = {
	{ key = "player", unit = "player", title = L["Player"], pos = { "BOTTOMRIGHT", "UIParent", "BOTTOM", -150, 245 } },
	{ key = "target", unit = "target", title = L["Target"], pos = { "BOTTOMLEFT", "UIParent", "BOTTOM", 150, 245 } },
	{ key = "targettarget", unit = "targettarget", title = L["Target of Target"], pos = { "BOTTOMLEFT", "SentinelUIMover_target", "BOTTOMRIGHT", 8, 0 }, poll = true },
	{ key = "focus", unit = "focus", title = L["Focus"], pos = { "BOTTOMRIGHT", "SentinelUIMover_player", "TOPLEFT", -40, 60 }, noClassic = true },
	{ key = "focustarget", unit = "focustarget", title = L["Focus Target"], pos = { "TOPLEFT", "SentinelUIMover_focus", "BOTTOMLEFT", 0, -36 }, poll = true, noClassic = true },
	{ key = "pet", unit = "pet", title = L["Pet"], pos = { "BOTTOMRIGHT", "SentinelUIMover_player", "BOTTOMLEFT", -8, 0 } },
	{ key = "pettarget", unit = "pettarget", title = L["Pet Target"], pos = { "TOPRIGHT", "SentinelUIMover_pet", "BOTTOMRIGHT", 0, -8 }, poll = true },
}

function UF:CreateSingle(info)
	local db = self.db.units[info.key]
	local f = CreateFrame("Button", "SentinelUI_" .. info.key:gsub("^%l", string.upper), UIParent, "SecureUnitButtonTemplate")
	f:SetAttribute("unit", info.unit)
	if info.unit == "player" then f:SetAttribute("toggleForVehicle", true) end
	f.title = info.title
	self:BuildFrame(f, info.key)
	f:SetSize(db.width, db.height)
	self:SetFrameUnit(f, info.unit)
	S:CreateMover(f, info.key, info.title, info.pos, "unitframes")
	self:ConfigureFrame(f)
	if info.poll then self:AddPolling(f) end
	self.units[info.key] = f
	self:SetSingleEnabled(f, db.enable)
	return f
end

function UF:SetSingleEnabled(f, enabled)
	if InCombatLockdown() then return S:RunOutOfCombat(self.SetSingleEnabled, self, f, enabled) end
	if enabled then
		if f.unit == "player" then
			UnregisterUnitWatch(f)
			RegisterStateDriver(f, "visibility", "[petbattle] hide; show")
		else
			RegisterUnitWatch(f)
		end
	else
		UnregisterUnitWatch(f)
		RegisterStateDriver(f, "visibility", "hide")
	end
	S:DisableMover(f.key, not enabled)
end

-- Boss / arena stacks
function UF:CreateStack(key, prefix, count, title, pos)
	local db = self.db.units[key]
	local holder = CreateFrame("Frame", "SentinelUI_" .. key:gsub("^%l", string.upper) .. "Holder", UIParent)
	holder.frames = {}
	for i = 1, count do
		local f = CreateFrame("Button", "SentinelUI_" .. key:gsub("^%l", string.upper) .. i, holder, "SecureUnitButtonTemplate")
		f:SetAttribute("unit", prefix .. i)
		f.title = title .. " " .. i
		self:BuildFrame(f, key)
		self:SetFrameUnit(f, prefix .. i)
		self:ConfigureFrame(f)
		if db.enable then RegisterUnitWatch(f) else RegisterStateDriver(f, "visibility", "hide") end
		holder.frames[i] = f
		self.units[key .. i] = f
	end
	holder.Layout = function()
		if InCombatLockdown() then return S:RunOutOfCombat(holder.Layout) end
		local d = self.db.units[key]
		for i, f in ipairs(holder.frames) do
			f:ClearAllPoints()
			f:SetSize(d.width, d.height)
			f:SetPoint("TOP", holder, "TOP", 0, -(i - 1) * (d.height + d.spacing))
		end
		holder:SetSize(d.width, count * d.height + (count - 1) * d.spacing)
	end
	holder.Layout()
	S:CreateMover(holder, key, title, pos, "unitframes")
	S:DisableMover(key, not db.enable)
	self.headers[key] = holder
	return holder
end

-- Group headers
local growthMap = {
	RIGHT_DOWN = { point = "LEFT", x = 1, y = 0, column = "TOP", anchor = "TOPLEFT" },
	RIGHT_UP = { point = "LEFT", x = 1, y = 0, column = "BOTTOM", anchor = "BOTTOMLEFT" },
	LEFT_DOWN = { point = "RIGHT", x = -1, y = 0, column = "TOP", anchor = "TOPRIGHT" },
	LEFT_UP = { point = "RIGHT", x = -1, y = 0, column = "BOTTOM", anchor = "BOTTOMRIGHT" },
	DOWN_RIGHT = { point = "TOP", x = 0, y = -1, column = "LEFT", anchor = "TOPLEFT" },
	DOWN_LEFT = { point = "TOP", x = 0, y = -1, column = "RIGHT", anchor = "TOPRIGHT" },
	UP_RIGHT = { point = "BOTTOM", x = 0, y = 1, column = "LEFT", anchor = "BOTTOMLEFT" },
	UP_LEFT = { point = "BOTTOM", x = 0, y = 1, column = "RIGHT", anchor = "BOTTOMRIGHT" },
	DOWN = { point = "TOP", x = 0, y = -1, column = "LEFT", anchor = "TOPLEFT" },
	UP = { point = "BOTTOM", x = 0, y = 1, column = "LEFT", anchor = "BOTTOMLEFT" },
	RIGHT = { point = "LEFT", x = 1, y = 0, column = "TOP", anchor = "TOPLEFT" },
	LEFT = { point = "RIGHT", x = -1, y = 0, column = "TOP", anchor = "TOPRIGHT" },
}

local initialConfig = [[
	local header = self:GetParent()
	self:SetWidth(header:GetAttribute("suiWidth"))
	self:SetHeight(header:GetAttribute("suiHeight"))
	self:SetAttribute("*type1", "target")
	self:SetAttribute("*type2", "togglemenu")
	self:SetAttribute("toggleForVehicle", true)
	header:CallMethod("InitChild", self:GetName())
]]

local function ChildOnAttributeChanged(child, name, value)
	if name == "unit" then
		S:SafeCall("UnitFrames:ChildUnit", UF.SetFrameUnit, UF, child, value)
	end
end

function UF:InitGroupChild(header, child)
	if not child or child.suiInit then return end
	child.suiInit = true
	child.isGroup = true
	child.title = header.title
	self:BuildFrame(child, header.key)
	child:HookScript("OnAttributeChanged", ChildOnAttributeChanged)
	child:HookScript("OnShow", function(c) if c.unit then S:SafeCall("UnitFrames:ChildShow", UF.UpdateFrame, UF, c) end end)
	self:ConfigureFrame(child)
	self:SetFrameUnit(child, child:GetAttribute("unit"))
	if self.ApplyClickCastTo then self:ApplyClickCastTo(child) end
end

function UF:ApplyHeaderAttributes(header)
	if InCombatLockdown() then return S:RunOutOfCombat(self.ApplyHeaderAttributes, self, header) end
	local db = self.db.units[header.key]
	local growth = growthMap[db.growth or "DOWN"] or growthMap.DOWN
	local spacing = db.spacing or 3
	header:SetAttribute("suiWidth", db.width)
	header:SetAttribute("suiHeight", db.height)
	header:SetAttribute("point", growth.point)
	header:SetAttribute("xOffset", growth.x * spacing)
	header:SetAttribute("yOffset", growth.y * spacing)
	header:SetAttribute("columnAnchorPoint", growth.column)
	header:SetAttribute("columnSpacing", spacing)
	header:SetAttribute("showPlayer", db.showPlayer ~= false)
	header:SetAttribute("sortMethod", db.sortMethod == "NAME" and "NAME" or "INDEX")
	header:SetAttribute("sortDir", db.sortDir == "DESC" and "DESC" or "ASC")
	-- always set the grid layout: when unitsPerColumn/maxColumns are missing the
	-- client's fallback can wrap extra members into an invisible second column
	if header.isRaid then
		header:SetAttribute("maxColumns", db.maxColumns or 8)
		header:SetAttribute("unitsPerColumn", db.unitsPerColumn or 5)
		header:SetAttribute("groupBy", db.groupBy == "CLASS" and "CLASS" or db.groupBy == "ROLE" and "ASSIGNEDROLE" or "GROUP")
		header:SetAttribute("groupingOrder", db.groupBy == "CLASS" and "WARRIOR,PALADIN,DEATHKNIGHT,DEMONHUNTER,ROGUE,MONK,DRUID,HUNTER,SHAMAN,MAGE,WARLOCK,PRIEST,EVOKER" or db.groupBy == "ROLE" and "TANK,HEALER,DAMAGER,NONE" or "1,2,3,4,5,6,7,8")
		header:SetAttribute("raidWideSorting", db.raidWideSorting and true or false)
		header:SetAttribute("startFromCenter", db.startFromCenter and true or false)
	else
		header:SetAttribute("maxColumns", db.maxColumns or 1)
		header:SetAttribute("unitsPerColumn", db.unitsPerColumn or 5)
	end
	if header.isRaid or header.groupFilter then
		local gf = db.groupFilter
		if type(gf) ~= "string" or gf == "" then gf = header.groupFilter or "1,2,3,4,5,6,7,8" end
		header:SetAttribute("groupFilter", gf)
	end
	for i = 1, 40 do
		local child = header:GetAttribute("child" .. i) or _G[header:GetName() .. "UnitButton" .. i]
		if not child then break end
		child:SetSize(db.width, db.height)
		child.db = db
		if child.suiInit then self:ConfigureFrame(child) end
	end

	local holder = header.holder
	local maxUnits, perColumn, columns
	if header.isRaid then
		perColumn, columns = db.unitsPerColumn or 5, db.maxColumns or 8
	else
		perColumn, columns = 5, 1
	end
	local horizontal = growth.y == 0
	local w, h
	if horizontal then
		w = perColumn * db.width + (perColumn - 1) * spacing
		h = columns * db.height + (columns - 1) * spacing
	else
		w = columns * db.width + (columns - 1) * spacing
		h = perColumn * db.height + (perColumn - 1) * spacing
	end
	holder:SetSize(w, h)
	header:ClearAllPoints()
	header:SetPoint(growth.anchor, holder, growth.anchor)

	local visibility
	if header.key == "party" then
		visibility = db.showSolo and "[petbattle] hide; [@raid6,exists] hide; show" or "[petbattle] hide; [@raid6,exists] hide; [group] show; hide"
	elseif header.key == "partypet" then
		visibility = "[petbattle] hide; [group] show; hide"
	elseif header.key == "raid" then
		visibility = "[petbattle] hide; [@raid26,exists] hide; [@raid6,exists] show; hide"
	elseif header.key == "raid40" then
		visibility = "[petbattle] hide; [@raid26,exists] show; hide"
	else
		visibility = "[petbattle] hide; [group:raid] show; hide"
	end
	if type(db.visibility) == "string" and db.visibility ~= "" then visibility = db.visibility end
	if not db.enable then visibility = "hide" end
	RegisterStateDriver(header.holder, "visibility", visibility)
	S:DisableMover(header.key, not db.enable)
end

function UF:CreateHeader(key, title, pos, opts)
	local db = self.db.units[key]
	local name = "SentinelUI_" .. key:gsub("^%l", string.upper) .. "Header"
	local holder = CreateFrame("Frame", name .. "Holder", UIParent)
	holder:SetSize(db.width, db.height)
	-- header is parented to the holder: the visibility state driver goes on the
	-- unprotected holder, so a state flip in combat only hides/shows the holder
	-- instead of running SecureGroupHeader_Update (SetPoint on protected
	-- children -> ADDON_ACTION_BLOCKED)
	local header = CreateFrame("Frame", name, holder, opts.template or "SecureGroupHeaderTemplate")
	header.key, header.title, header.holder = key, title, holder
	header.isRaid = opts.raid
	header.groupFilter = opts.groupFilter
	header.InitChild = function(h, childName)
		S:SafeCall("UnitFrames:InitChild", UF.InitGroupChild, UF, h, _G[childName])
	end
	-- the template's own OnEvent/OnUpdate scripts run SecureGroupHeader_Update
	-- even mid-combat -> SetPoint on protected children -> ADDON_ACTION_BLOCKED.
	-- Detach them; the module drives refreshes itself (GROUP_ROSTER_UPDATE,
	-- UNIT_PET) and defers combat updates to regen
	header:SetScript("OnEvent", nil)
	header:SetScript("OnUpdate", nil)
	header:UnregisterAllEvents()
	header:SetAttribute("template", "SecureUnitButtonTemplate")
	header:SetAttribute("initialConfigFunction", initialConfig)
	header:SetAttribute("showParty", opts.party or false)
	header:SetAttribute("showRaid", opts.raidUnits or false)
	header:SetAttribute("showSolo", opts.solo or false)
	if opts.groupFilter then header:SetAttribute("groupFilter", opts.groupFilter) end

	S:CreateMover(holder, key, title, pos, "unitframes")
	self:ApplyHeaderAttributes(header)

	-- pre-create all buttons out of combat so nothing protected happens later
	local total = opts.raid and ((db.unitsPerColumn or 5) * (db.maxColumns or 8)) or 5
	UnregisterStateDriver(holder, "visibility")
	holder:Show()
	header:Show()
	header:SetAttribute("startingIndex", -total + 1)
	header:SetAttribute("startingIndex", 1)
	self:ApplyHeaderAttributes(header)
	self.headers[key] = header
	return header
end

function UF:UpdateHeaders()
	for _, header in pairs(self.headers) do
		if header.Layout then
			header.Layout()
		elseif header.holder then
			self:ApplyHeaderAttributes(header)
		end
	end
	for key, f in pairs(self.units) do
		if f.key == key and not f.isGroup and f:GetParent() == UIParent then
			self:SetSingleEnabled(f, self.db.units[key].enable)
		end
	end
end

function UF:CreateUnits()
	for _, info in ipairs(singles) do
		if not (info.noClassic and S.isClassic) then self:CreateSingle(info) end
	end
	if not S.isClassic then
		self:CreateStack("boss", "boss", MAX_BOSS_FRAMES or 5, L["Boss"], { "RIGHT", "UIParent", "RIGHT", -100, 80 })
	end
	if not S.isClassic then
		self:CreateStack("arena", "arena", 5, L["Arena"], { "RIGHT", "UIParent", "RIGHT", -100, 80 })
	end
	self:CreateHeader("party", L["Party"], { "TOPLEFT", "UIParent", "TOPLEFT", 70, -280 }, { party = true, raidUnits = true })
	-- group pet frames (SecureGroupPetHeaderTemplate = Blizzard pet header);
	-- pcall-guarded in case a client lacks the template
	if self.db.units.partypet then
		local ok = pcall(self.CreateHeader, self, "partypet", L["Party Pets"], { "TOPLEFT", "UIParent", "TOPLEFT", 70, -560 }, { party = true, raid = true, raidUnits = true, template = "SecureGroupPetHeaderTemplate" })
		if not ok then S:LogInfo("unitframes", "partypet header: SecureGroupPetHeaderTemplate unavailable") end
	end
	self:CreateHeader("raid", L["Raid"], { "BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 6, 240 }, { raid = true, raidUnits = true })
	self:CreateHeader("raid40", L["Raid 40"], { "BOTTOMLEFT", "UIParent", "BOTTOMLEFT", 6, 240 }, { raid = true, raidUnits = true })
	self:CreateHeader("maintank", L["Main Tanks"], { "TOPLEFT", "UIParent", "TOPLEFT", 6, -200 }, { raidUnits = true, groupFilter = "MAINTANK" })

	-- shaman totems (Blizzard frame, just repositioned)
	if TotemFrame and self.private.disableBlizzardPlayer then
		local holder = CreateFrame("Frame", "SentinelUITotemHolder", UIParent)
		holder:SetSize(140, 36)
		S:CreateMover(holder, "totems", L["Totems"], { "BOTTOMLEFT", "SentinelUIMover_player", "TOPLEFT", 0, 30 }, "unitframes")
		TotemFrame:SetParent(holder)
		TotemFrame:ClearAllPoints()
		TotemFrame:SetPoint("CENTER", holder)
		hooksecurefunc(TotemFrame, "SetPoint", function(f, _, rel)
			if rel ~= holder and not InCombatLockdown() then f:ClearAllPoints() f:SetPoint("CENTER", holder) end
		end)
		if TotemFrame_Update then pcall(TotemFrame_Update) end
	end
end
