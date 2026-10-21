local addonName, ns = ...
local S = ns.S
local L = S.L
local D = ns.WorldBuffsData
local WB = S:GetModule("WorldBuffs")

local GetServerTime = GetServerTime
local format = string.format
local sort = table.sort
local pairs, ipairs = pairs, ipairs

local BUFF_ORDER = { "rend", "ony", "nef", "zan" }
local BUFF_ICONS = {
	rend = "Interface\\Icons\\spell_arcane_teleportorgrimmar",
	ony = "Interface\\Icons\\inv_misc_head_dragon_01",
	nef = "Interface\\Icons\\inv_misc_head_dragon_01",
	zan = "Interface\\Icons\\ability_creature_poison_05",
	songflower = "Interface\\Icons\\spell_holy_mindvision",
}

local ROW_H = 16

local function FS(parent, size, color)
	return S:FontString(parent, size or 11, nil, S.media.font, color, "LEFT")
end

function WB:CreateWindow()
	local f = CreateFrame("Frame", "SentinelUIBuffWindow", UIParent, "BackdropTemplate")
	tinsert(UISpecialFrames, "SentinelUIBuffWindow")
	f:SetSize(360, 320)
	f:SetPoint("CENTER")
	S:SetTemplate(f)
	S:CreateBackdrop(f, "Default")
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetClampedToScreen(true)
	f:Hide()

	f.title = FS(f, 13)
	f.title:SetPoint("TOPLEFT", 12, -10)
	f.title:SetText(L["World Buffs"])

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)
	S:SkinCloseButton(close)

	f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
	f.scroll:SetPoint("TOPLEFT", 10, -32)
	f.scroll:SetPoint("BOTTOMRIGHT", -28, 10)
	if f.scroll.ScrollBar then S:SkinScrollBar(f.scroll.ScrollBar) end

	f.content = CreateFrame("Frame", nil, f.scroll)
	f.content:SetSize(320, 400)
	f.scroll:SetScrollChild(f.content)

	f.rows = {}
	f.elapsed = 0
	f:SetScript("OnUpdate", function(_, dt)
		f.elapsed = f.elapsed + dt
		if f.elapsed > 1 then
			f.elapsed = 0
			f:Refresh()
		end
	end)

	function f:GetRow(i)
		local r = self.rows[i]
		if not r then
			r = {}
			r.icon = self.content:CreateTexture(nil, "ARTWORK")
			r.icon:SetSize(13, 13)
			r.left = FS(self.content, 11)
			r.right = FS(self.content, 11)
			r.right:SetJustifyH("RIGHT")
			self.rows[i] = r
		end
		return r
	end

	function f:Refresh()
		local y, i = 0, 1
		local function Row(icon, left, right, lr, lg, lb, rr, rg, rb)
			local r = self:GetRow(i)
			if icon then
				r.icon:SetTexture(icon)
				r.icon:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
				r.icon:Show()
				r.left:SetPoint("TOPLEFT", self.content, "TOPLEFT", 18, -y)
			else
				r.icon:Hide()
				r.left:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -y)
			end
			r.left:SetText(left)
			r.left:SetTextColor(lr or 1, lg or 1, lb or 1)
			r.right:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, -y)
			r.right:SetText(right or "")
			r.right:SetTextColor(rr or 1, rg or 1, rb or 1)
			y = y + ROW_H
			i = i + 1
		end

		local layers = WB:Layers()
		local keys = {}
		for k in pairs(layers) do keys[#keys + 1] = k end
		sort(keys)
		local curID = WB:CurrentLayerID()

		if #keys == 0 then
			Row(nil, L["No layers detected yet, target an NPC."], "", 0.6, 0.6, 0.6)
			y = y + 4
		end
		for _, zoneID in ipairs(keys) do
			local e = layers[zoneID]
			if type(e) == "table" then
				local num = WB:LayerNum(zoneID)
				local cur = (zoneID == curID) and (" |cff00ff00(" .. L["current"] .. ")|r") or ""
				Row(nil, format(L["Layer %d"], num > 0 and num or "?") .. cur,
					e.lastSeen and WB:TimeString(GetServerTime() - e.lastSeen) .. " " .. L["ago"] or "",
					1, 0.82, 0, 0.5, 0.5, 0.55)
				for _, kind in ipairs(BUFF_ORDER) do
					local text, r, g, b = WB:BuffStatus(e, kind)
					local extra = ""
					local died = e[kind .. "NpcDied"]
					if died and GetServerTime() - died < 120 then
						extra = format(" |cff888888(%s %ds)|r", L["respawn in"], 120 - (GetServerTime() - died))
					end
					Row(BUFF_ICONS[kind], "  " .. WB:BuffName(kind), text .. extra, 0.9, 0.9, 0.9, r, g, b)
				end
				y = y + 4
			end
		end

		-- songflowers
		local sf = WB:Data().songflowers
		local anyFlower
		for zoneID, flowers in pairs(sf) do
			for idx, ts in pairs(flowers) do
				local rem = D.songflowerRespawn - (GetServerTime() - ts)
				if rem > 0 then
					if not anyFlower then
						Row(nil, L["Songflowers"], "", 1, 0.82, 0)
						anyFlower = true
					end
					local num = WB:LayerNum(zoneID)
					local lstr = zoneID ~= 0 and num > 0 and (" (" .. format(L["Layer %d"], num) .. ")") or ""
					Row(BUFF_ICONS.songflower, "  " .. format(L["Songflower %d"], idx) .. lstr,
						WB:TimeString(rem), 0.9, 0.9, 0.9, 1, 0.6, 0.2)
				end
			end
		end
		if anyFlower then y = y + 4 end

		-- darkmoon faire + sayge
		if WB.db.dmf ~= false then
			local info = WB:DmfInfo()
			if info then
				local loc = " |cff888888(" .. (L[info.loc] or info.loc) .. ")|r"
				if info.status == "active" then
					Row(nil, L["Darkmoon Faire"], L["open now"] .. loc, 0.9, 0.9, 0.9, 0.3, 1, 0.3)
				else
					Row(nil, L["Darkmoon Faire"], L["in"] .. " " .. WB:TimeString(info.secs) .. loc, 0.9, 0.9, 0.9, 1, 0.6, 0.2)
				end
				local sayge = WB:SaygeRemaining()
				if sayge > 0 then
					Row(nil, "  " .. L["Sayge's Dark Fortune"], WB:TimeString(sayge) .. " " .. L["left"], 0.9, 0.9, 0.9, 0.3, 1, 0.3)
				end
				y = y + 4
			end
		end

		-- chronoboon displacers
		if WB.db.chronoboon ~= false then
			local n = WB:ChronoboonCount()
			if n > 0 then
				Row(nil, L["Chronoboon Displacer"], "|cff40ff40" .. n .. "|r", 0.9, 0.9, 0.9)
				y = y + 4
			end
		end

		-- world pvp objectives (towers / beacons)
		if WB.db.worldPvp ~= false then
			local header
			local list = WB:WorldPvpList()
			if list then
				for _, a in ipairs(list) do
					if not header then Row(nil, L["World PvP"], "", 1, 0.82, 0) header = true end
					local right, r, g, b = "", 0.6, 0.6, 0.6
					if a.wait and a.wait > 0 then
						right, r, g, b = WB:TimeString(a.wait), 1, 0.6, 0.2
					elseif a.active then
						right, r, g, b = L["Active"], 0.3, 1, 0.3
					end
					Row(nil, "  " .. a.name, right, 0.9, 0.9, 0.9, r, g, b)
				end
			end
			local rows = WB:WorldStateRows()
			if rows then
				if not header then Row(nil, L["World PvP"], "", 1, 0.82, 0) header = true end
				for _, t in ipairs(rows) do
					Row(nil, "  " .. t, "", 0.7, 0.7, 0.7)
				end
			end
			if header then y = y + 4 end
		end

		-- timer log
		local log = WB:Data().timerLog
		if #log > 0 then
			Row(nil, L["Timer Log"], "", 1, 0.82, 0)
			local shown = 0
			for i2 = #log, 1, -1 do
				local e = log[i2]
				local who = e.who and (" |cff888888(" .. e.who .. ")|r") or ""
				local lstr = e.layer and (" [" .. format(L["Layer %d"], e.layer) .. "]") or ""
				Row(nil, "  " .. date("%H:%M", e.ts) .. " " .. WB:BuffName(e.t) .. lstr .. who,
					WB:TimeString(GetServerTime() - e.ts) .. " " .. L["ago"],
					0.7, 0.7, 0.7, 0.5, 0.5, 0.55)
				shown = shown + 1
				if shown >= 15 then break end
			end
		end

		for j = i, #self.rows do
			self.rows[j].icon:Hide()
			self.rows[j].left:SetText("")
			self.rows[j].right:SetText("")
		end
		self.content:SetHeight(math.max(y + 10, 280))
	end

	self.buffWindow = f
	return f
end
