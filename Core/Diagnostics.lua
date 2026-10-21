-- Diagnostics: snapshot of the UI state written to SentinelUILog.diag (saved on /reload or logout).
-- Lets the developer see what actually happens in game without screenshots. /sui diag refreshes it.
local _, ns = ...
local S = ns.S

local function R(v) return v and floor(v * 10 + 0.5) / 10 or nil end

local function FrameInfo(f)
	if not f then return "missing" end
	local info = {
		shown = f:IsShown() or nil, visible = f:IsVisible() or nil,
		w = R(f:GetWidth()), h = R(f:GetHeight()), alpha = R(f:GetEffectiveAlpha()),
		strata = f:GetFrameStrata(), level = f:GetFrameLevel(),
	}
	local l, b = f:GetLeft(), f:GetBottom()
	info.left, info.bottom = R(l), R(b)
	local p = f:GetParent()
	info.parent = p and (p:GetName() or tostring(p)) or nil
	if f.IsProtected then info.protected = f:IsProtected() or nil end
	local onScreen = l and b and l < UIParent:GetRight() and b < UIParent:GetTop() and (l + f:GetWidth()) > 0 and (b + f:GetHeight()) > 0
	info.onScreen = onScreen or false
	return info
end

function S:RunDiagnostics(reason)
	if type(_G.SentinelUILog) ~= "table" then return end
	local d = {
		time = date("%Y-%m-%d %H:%M:%S"), reason = reason, flavor = self.flavor, interface = self.interface,
		uiScale = R(UIParent:GetScale()), mult = self.mult, screen = { R(UIParent:GetWidth()), R(UIParent:GetHeight()) },
		combat = InCombatLockdown() or nil,
		modules = {}, movers = {}, blizzard = {}, cvars = {},
	}
	for _, mod in ipairs(self.moduleOrder) do
		d.modules[mod.name] = { initialized = mod.initialized or false, disabled = (mod.private and mod.private.enable == false) or nil }
	end
	for _, m in ipairs(self.moverOrder) do
		local parent = m.parent
		d.movers[m.name] = { mover = { left = R(m:GetLeft()), bottom = R(m:GetBottom()), w = R(m:GetWidth()), h = R(m:GetHeight()) }, frame = FrameInfo(parent), disabled = m.disabled }
	end

	local ab = self:GetModule("ActionBars")
	if ab and ab.initialized then
		d.actionbars = {}
		for key, bar in pairs(ab.bars) do
			local bi = { frame = FrameInfo(bar), page = bar:GetAttribute("actionpage"), buttons = {} }
			for i, btn in ipairs(bar.buttons) do
				if i <= 12 then
					local action = btn.GetAttribute and btn:GetAttribute("action")
					bi.buttons[i] = format("%s|type=%s|has=%s|shown=%s|vis=%s|alpha=%.1f|icon=%s|key=%s",
						tostring(action), tostring(btn:GetAttribute("type")), tostring(action and HasAction(action) or false),
						tostring(btn:IsShown()), tostring(btn:IsVisible()), btn:GetAlpha(),
						tostring(btn.icon and btn.icon:IsShown()), tostring(btn.bindCommand and GetBindingKey(btn.bindCommand)))
				end
			end
			d.actionbars[key] = bi
		end
	end

	local uf = self:GetModule("UnitFrames")
	if uf and uf.initialized then
		d.unitframes = {}
		for key, f in pairs(uf.units) do
			local fi = FrameInfo(f)
			fi.unit = f.unit
			fi.exists = f.unit and UnitExists(f.unit) or false
			fi.health = f.Health and R(f.Health:GetValue())
			fi.healthText = f.HealthText and f.HealthText:GetText()
			fi.name = f.NameText and f.NameText:GetText()
			d.unitframes[key] = fi
		end
		d.headers = {}
		for key, h in pairs(uf.headers) do
			local hi = FrameInfo(h)
			local children = 0
			for i = 1, 40 do if h:GetAttribute("child" .. i) then children = i end end
			hi.children = children
			d.headers[key] = hi
		end
	end

	for _, n in ipairs({ "PlayerFrame", "TargetFrame", "MainMenuBar", "MainActionBar", "MultiBarBottomLeft", "MultiBarRight", "BuffFrame", "ChatFrame1", "Minimap", "MinimapCluster", "ContainerFrame1", "PartyMemberFrame1", "CompactRaidFrameContainer", "PetActionBarFrame", "StanceBarFrame", "CastingBarFrame", "GameTooltip" }) do
		local f = _G[n]
		d.blizzard[n] = f and FrameInfo(f) or "missing"
	end
	for _, c in ipairs({ "ActionButtonUseKeyDown", "lockActionBars", "uiScale", "useUiScale", "autoLootDefault",
		"UnitNameOwn", "UnitNameNPC", "UnitNamePlayerGuild", "UnitNameGuildTitle", "UnitNameFriendlyPlayerNames",
		"UnitNameFriendlyMinionNames", "UnitNameEnemyPlayerNames", "nameplateShowSelf", "nameplateShowFriends" }) do
		d.cvars[c] = GetCVar(c)
	end

	-- stray scan: every visible text/region near screen center (catches misplaced labels)
	d.strays = {}
	local cw, ch = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
	local f = EnumerateFrames()
	local count = 0
	while f and count < 60 do
		local ok, vis = pcall(f.IsVisible, f)
		if ok and vis and f.GetRegions then
			local fname = f.GetName and f:GetName() or "unnamed"
			for i = 1, select("#", f:GetRegions()) do
				local r = select(i, f:GetRegions())
				if r and r.GetObjectType and r:GetObjectType() == "FontString" then
					local okt, text = pcall(r.GetText, r)
					if okt and text and text ~= "" then
						local okc, x, y = pcall(r.GetCenter, r)
						if okc and x and y and math.abs(x - cw) < 300 and math.abs(y - ch) < 250 then
							count = count + 1
							d.strays[count] = format("%s @ %.0f,%.0f :: %s", fname, x, y, strsub(text, 1, 60))
						elseif not okc and fname:find("NamePlate") then
							-- restricted nameplate region (Plater etc.): can't measure, but text is visible
							count = count + 1
							d.strays[count] = format("%s @ nameplate :: %s", fname, strsub(text, 1, 60))
						end
						if count >= 60 then break end
					end
				end
			end
			if count >= 60 then break end
		end
		f = EnumerateFrames(f)
	end
	local cf = ChatFrame1
	if cf then
		local p, rel, rp, x, y = cf:GetPoint(1)
		d.chatPoint = format("%s %s %s %.0f %.0f", tostring(p), rel and (rel:GetName() or "?") or "nil", tostring(rp), x or 0, y or 0)
	end
	_G.SentinelUILog.diag = d
	return d
end

local diag = { name = "Diagnostics" }
S.RegisterEvent(diag, "PLAYER_ENTERING_WORLD", function()
	C_Timer.After(6, function() S:SafeCall("Diagnostics", S.RunDiagnostics, S, "login") end)
end)
-- refresh right before the SavedVariables are written, so /reload always captures the current state
S.RegisterEvent(diag, "PLAYER_LOGOUT", function() S:SafeCall("Diagnostics", S.RunDiagnostics, S, "reload/logout") end)
