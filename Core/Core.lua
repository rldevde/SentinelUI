local _, ns = ...
local S = ns.S
local L = S.L

function S:SetUIScale()
	if InCombatLockdown() then return self:RunOutOfCombat(self.SetUIScale, self) end
	local g = self.db.profile.general
	if g.autoScale then
		local _, height = GetPhysicalScreenSize()
		if height and height > 0 then
			local scale = 768 / height
			while scale < 0.4 do scale = scale * 2 end
			g.uiScale = scale
		end
	end
	local scale = math.max(0.4, math.min(1.15, g.uiScale or 0.71))
	self.appliedScale = scale
	if math.abs(UIParent:GetScale() - scale) > 0.0001 then
		UIParent:SetScale(scale)
	end
	self:UpdatePixelScale()
end

local function OnScaleEvent(_, event)
	-- windowed-mode / resolution changes go through a transition where the
	-- client reports intermediate scales; settle a bit longer for those
	local delay = event == "DISPLAY_SIZE_CHANGED" and 0.5 or 0.1
	C_Timer.After(delay, function()
		S:SafeCall("UIScale", function()
			local g = S.db.profile.general
			local cur = UIParent:GetScale()
			-- someone else changed the scale (Blizzard options, other addon):
			-- adopt it instead of fighting - but only once the value is
			-- stable; fullscreen/window toggles report transient scales that
			-- must never overwrite the user's scale (that stranded the whole
			-- UI at a mid-transition size -> "verschiebt sich querbeet")
			if event == "UI_SCALE_CHANGED" and S.appliedScale
			and math.abs(cur - S.appliedScale) > 0.0001 then
				C_Timer.After(0.4, function()
					local settled = UIParent:GetScale()
					if not settled or math.abs(settled - cur) > 0.001 then
						-- still transitioning: re-apply ours instead of adopting
						S:SetUIScale()
						S:UpdateTemplates()
						if S.RefreshMovers then S:RefreshMovers() end
						return
					end
					g.autoScale = false
					g.uiScale = math.max(0.4, math.min(1.15, cur))
					S.appliedScale = g.uiScale
					S:UpdatePixelScale()
					S:UpdateTemplates()
					if S.RefreshMovers then S:RefreshMovers() end
				end)
				return
			end
			S:SetUIScale()
			S:UpdateTemplates()
			if S.RefreshMovers then S:RefreshMovers() end
		end)
	end)
end

function S:StaticReload(text)
	StaticPopupDialogs["SENTINELUI_RELOAD"] = StaticPopupDialogs["SENTINELUI_RELOAD"] or {
		button1 = ACCEPT, button2 = CANCEL, OnAccept = ReloadUI, timeout = 0, whileDead = true, hideOnEscape = true,
	}
	StaticPopupDialogs["SENTINELUI_RELOAD"].text = text or L["One or more changes require a UI reload."]
	StaticPopup_Show("SENTINELUI_RELOAD")
end

function S:OnProfileChanged()
	self.private = self.charDB.profile
	self:StaticReload(L["Profile changed. Reload the UI to apply it completely?"])
	self:UpdateMedia()
	self:UpdateTemplates()
	self:RefreshMovers()
	self:UpdateModules()
end

function S:RefreshAll()
	self:UpdateMedia()
	self:UpdateTemplates()
	self:UpdateStatusBars()
	self:UpdateModules()
end

function S:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("SentinelUIDB", self.defaults, true)
	self.charDB = LibStub("AceDB-3.0"):New("SentinelUICharDB", self.privateDefaults, true)
	self.private = self.charDB.profile
	self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
	self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
	self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
	self.db.global.gridSize = self.db.global.gridSize or 64

	if self.IsAddOnLoaded("Plater") or self.IsAddOnLoaded("Kui_Nameplates") or self.IsAddOnLoaded("TidyPlates_ThreatPlates") then
		if self.private.nameplates.enable and not self.private.nameplates.userSet then
			self.private.nameplates.enable = false
		end
	end

	-- VuhDo/Grid2/Cell replace our group frames: disable ours once (user can re-enable in options).
	if (self.IsAddOnLoaded("VuhDo") or self.IsAddOnLoaded("Grid2") or self.IsAddOnLoaded("Cell") or self.IsAddOnLoaded("Grid")) and not self.private.healerFramesDetected then
		self.private.healerFramesDetected = true
		for _, k in ipairs({ "party", "raid", "raid40", "maintank" }) do
			if self.db.profile.unitframes.units[k] then self.db.profile.unitframes.units[k].enable = false end
		end
	end

	-- one-time theme migration: v2 applies the Sentinel amber/slate palette
	if (self.private.themeVersion or 0) < 2 then
		self.private.themeVersion = 2
		local g = self.db.profile.general
		g.accentColor = { r = 0.92, g = 0.68, b = 0.20 }
		g.backdropColor = { r = 0.06, g = 0.065, b = 0.09 }
		g.backdropFadeColor = { r = 0.045, g = 0.05, b = 0.075, a = 0.85 }
		self.db.profile.unitframes.colors.castbar = { r = 0.9, g = 0.55, b = 0.15 }
	end
	-- v3: new scrolling combat text (scroll areas instead of unit-frame numbers)
	if (self.private.themeVersion or 0) < 3 then
		self.private.themeVersion = 3
		local ct = self.db.profile.general.combatText
		ct.distance, ct.duration, ct.fontSize, ct.critSize = 130, 1.6, 18, 28
		ct.yOffset, ct.jitter, ct.mode = nil, nil, nil
		self.db.profile.general.borderColor = { r = 0.17, g = 0.18, b = 0.23 }
	end
	-- v4: square minimap is the default again (round radar stays optional)
	if (self.private.themeVersion or 0) < 4 then
		self.private.themeVersion = 4
		self.db.profile.minimap.shape = "SQUARE"
	end
	-- v5: dark health bars are the Sentinel default (class color on edge + name)
	if (self.private.themeVersion or 0) < 5 then
		self.private.themeVersion = 5
		local c = self.db.profile.unitframes.colors
		if c then c.healthMode = "DARK" end
	end
	-- v6: general.autoSellJunk moved to bags.autoVendor; honour the old setting
	if (self.private.themeVersion or 0) < 6 then
		self.private.themeVersion = 6
		local g = self.db.profile.general
		if g and g.autoSellJunk == false then self.db.profile.bags.autoVendor = false end
		if g then g.autoSellJunk = nil end
	end
	-- v7: a single skin - the CLASSIC frame style is gone, Sentinel is the only look
	if (self.private.themeVersion or 0) < 7 then
		self.private.themeVersion = 7
		self.db.profile.unitframes.style = nil
	end

	self:UpdateMedia()
	self:UpdatePixelScale()

	self:RegisterChatCommand("sui", "ChatCommand")
	self:RegisterChatCommand("sentinel", "ChatCommand")
	self:RegisterChatCommand("sentinelui", "ChatCommand")
	self:RegisterChatCommand("rl", function() ReloadUI() end)
end

function S:OnEnable()
	self:SafeCall("UIScale", self.SetUIScale, self)
	self:InitializeModules()
	self:SafeCall("Movers", self.RefreshMovers, self)

	self:RegisterEvent("UI_SCALE_CHANGED", OnScaleEvent)
	self:RegisterEvent("DISPLAY_SIZE_CHANGED", OnScaleEvent)
	-- spec profiles: switch profile when the spec changes (retail + classic dual spec)
	self:RegisterEvent("PLAYER_TALENT_UPDATE", function() S:SafeCall("SpecProfile", S.CheckSpecProfile, S) end)
	self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function() S:SafeCall("SpecProfile", S.CheckSpecProfile, S) end)
	self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", function() S:SafeCall("SpecProfile", S.CheckSpecProfile, S) end)
	C_Timer.After(5, function() S:SafeCall("SpecProfile", S.CheckSpecProfile, S) end)

	self:LogInfo("Login", format("%s %s on %s (%s), interface %s", S.name, S.version, S.flavor, (GetBuildInfo()), tostring(S.interface)))

	if not self.private.install_complete then
		C_Timer.After(1.5, function() S:SafeCall("Install", S.ShowInstall, S) end)
	else
		self:Print(format(L["v%s loaded. |cff%s/sui|r for options, |cff%s/sui move|r to move elements."], self.version, self.accentHex, self.accentHex))
	end
end

local function Help()
	S:Print(L["Commands:"])
	print("  /sui - " .. L["open options"])
	print("  /sui move - " .. L["unlock / lock movers"])
	print("  /sui kb - " .. L["keybind mode"])
	print("  /sui log - " .. L["show error log"] .. "  (/sui log clear)")
	print("  /sui install - " .. L["run installation"])
	print("  /sui scale - " .. L["re-apply UI scale"])
	print("  /sui reset - " .. L["reset all positions"])
	print("  /sui stack / /sui find <text> - " .. L["identify elements"])
	print("  /sui farm - " .. L["toggle farm mode map"])
	print("  /sui trainer - " .. L["open trainer list"])
	print("  /sui resets - " .. L["open instance resets"])
	print("  /sui rep - " .. L["open reputation list"])
	print("  /sui bug - " .. L["report a bug"] .. "  (" .. S.bugtracker .. ")")
	print("  /rl - " .. L["reload UI"])
end

function S:ChatCommand(input)
	local cmd, rest = self:GetArgs(input or "", 2)
	cmd = cmd and cmd:lower() or ""
	if cmd == "" or cmd == "config" or cmd == "options" then
		self:ToggleConfig()
	elseif cmd == "move" or cmd == "unlock" or cmd == "moveui" then
		self:ToggleMovers()
	elseif cmd == "lock" then
		self:ToggleMovers(false)
	elseif cmd == "log" or cmd == "errors" then
		if rest == "clear" then self:ClearLog() else self:ShowLog() end
	elseif cmd == "install" then
		self:ShowInstall()
	elseif cmd == "scale" then
		self:SetUIScale()
		self:UpdateTemplates()
	elseif cmd == "reset" then
		StaticPopup_Show("SENTINELUI_RESET_MOVERS")
	elseif cmd == "kb" or cmd == "keybind" then
		local ab = self:GetModule("ActionBars")
		if ab and ab.ToggleKeybindMode then ab:ToggleKeybindMode() end
	elseif cmd == "sct" then
		local ct = self:GetModule("CombatText")
		if ct and ct.initialized then ct:Test() end
	elseif cmd == "trainer" then
		local tr = self:GetModule("Trainer")
		if tr and tr.Open then tr:Open(false) end
	elseif cmd == "resets" or cmd == "raidreset" or cmd == "instances" then
		local rr = self:GetModule("RaidReset")
		if rr and rr.Toggle then rr:Toggle() end
	elseif cmd == "rep" or cmd == "reputation" then
		local rp = self:GetModule("Reputation")
		if rp and rp.Toggle then rp:Toggle() end
	elseif cmd == "bug" or cmd == "bugs" or cmd == "bugtracker" then
		self:ShowBugtracker()
	elseif cmd == "resetwindows" then
		local wm = self:GetModule("WindowMover")
		if wm and wm.Reset then wm:Reset() end
	elseif cmd == "farm" then
		local mm = self:GetModule("Minimap")
		if mm and mm.ToggleFarmMode then mm:ToggleFarmMode() end
	elseif cmd == "reload" or cmd == "rl" or cmd == "save" then
		if cmd == "save" then self:Print("Log & SavedVariables werden auf Disk geschrieben...") end
		ReloadUI()
	elseif cmd == "diag" then
		self:RunDiagnostics("manual")
		self:Print("Diagnose gespeichert – /reload schreibt sie in die SavedVariables.")
	elseif cmd == "find" and rest and rest ~= "" then
		-- locate every FontString (anywhere on screen) whose text contains <rest>
		local needle = rest:lower()
		local f, found = EnumerateFrames(), 0
		local lines = {}
		local function out(s) lines[#lines + 1] = s self:Print(s) end
		while f and found < 60 do
			if f.GetRegions then
				local okv, vis = pcall(f.IsVisible, f)
				local fname = (f.GetName and f:GetName()) or "unnamed"
				for i = 1, select("#", f:GetRegions()) do
					local r = select(i, f:GetRegions())
					if r and r.GetObjectType and r:GetObjectType() == "FontString" then
						local okt, text = pcall(r.GetText, r)
						if okt and text and text:lower():find(needle, 1, true) then
							local okc, x, y = pcall(r.GetCenter, r)
							found = found + 1
							out(("  %s :: %q @ %.0f,%.0f vis=%s"):format(fname, strsub(text, 1, 60), okc and x or -1, okc and y or -1, tostring(vis)))
							if found >= 60 then break end
						end
					end
				end
			end
			f = EnumerateFrames(f)
		end
		out(("find %q: %d Treffer"):format(rest, found))
		for _, l in ipairs(lines) do self:LogInfo("find", l) end
	elseif cmd == "stack" or cmd == "whatshere" then
		-- print all frames under the mouse cursor + near center (identify stray UI elements)
		local lines = {}
		local function out(s) lines[#lines + 1] = s self:Print(s) end
		local foci = S.GetMouseFoci and S.GetMouseFoci() or { self.GetMouseFocus and self.GetMouseFocus() or GetMouseFocus() }
		if not foci or #foci == 0 then foci = { GetMouseFocus and GetMouseFocus() } end
		out("--- Frames under cursor ---")
		for _, f in ipairs(foci or {}) do
			local cur = f
			for depth = 1, 4 do
				if not cur then break end
				local n = cur.GetName and cur:GetName() or "?"
				out(("  %s%s (%s, %.0fx%.0f, lvl %s)"):format(string.rep(">", depth - 1), n, cur:GetObjectType(), cur:GetWidth() or 0, cur:GetHeight() or 0, tostring(cur:GetFrameLevel())))
				cur = cur:GetParent()
			end
		end
		out("--- Frames near screen center ---")
		local cw, ch = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
		local found = 0
		local f = EnumerateFrames()
		while f and found < 40 do
			local okv, vis = pcall(f.IsVisible, f)
			if okv and vis and f.GetName and f:GetName() then
				local okc, x, y = pcall(f.GetCenter, f)
				if okc and x and math.abs(x - cw) < 300 and math.abs(y - ch) < 220 then
					local n = f:GetName()
					if n ~= "UIParent" and n ~= "WorldFrame" then
						found = found + 1
						out(("  %s (%s, %.0fx%.0f @ %.0f,%.0f)"):format(n, f:GetObjectType(), f:GetWidth(), f:GetHeight(), x, y))
					end
				end
			end
			f = EnumerateFrames(f)
		end
		out("--- Visible texts near center ---")
		found = 0
		f = EnumerateFrames()
		while f and found < 40 do
			local okv, vis = pcall(f.IsVisible, f)
			if okv and vis and f.GetRegions then
				local fname = (f.GetName and f:GetName()) or "unnamed"
				for i = 1, select("#", f:GetRegions()) do
					local r = select(i, f:GetRegions())
					if r and r.GetObjectType and r:GetObjectType() == "FontString" then
						local ok, text, x, y = pcall(function() return r:GetText(), r:GetCenter() end)
						if ok and text and text ~= "" and x and math.abs(x - cw) < 400 and math.abs(y - ch) < 300 then
							found = found + 1
							out(("  %s :: %q @ %.0f,%.0f"):format(fname, strsub(text, 1, 50), x, y))
							if found >= 40 then break end
						end
					end
				end
			end
			f = EnumerateFrames(f)
		end
		for _, l in ipairs(lines) do self:LogInfo("stack", l) end
		self:Print("In Log geschrieben – /sui save speichert auf Disk.")
	elseif cmd == "bagdebug" or cmd == "bags" then
		-- dump raw container info + bag frame state into chat and the persistent log
		local lines = {}
		local function out(s) lines[#lines + 1] = s self:Print(s) end
		out(("=== Bags debug | interface %s ==="):format(tostring(S.interface)))
		out(("inventory bags: 0-4 | keyring=%s reagent=%s | bank first=%s count=%s"):format(
			tostring(S.KEYRING_CONTAINER), tostring(S.REAGENTBAG_CONTAINER),
			tostring(S.BANK_BAG_FIRST), tostring(S.NUM_BANKBAGSLOTS)))
		local bags = self:GetModule("Bags")
		local bf = bags and bags.frames and bags.frames.bags
		out(("SentinelUIBags frame: %s shown=%s"):format(bf and "exists" or "MISSING", bf and tostring(bf:IsShown())))
		if bf then out(("  bags in frame: %s"):format(table.concat(bf.bags, ","))) end
		for i = 1, 13 do
			local cf = _G["ContainerFrame" .. i]
			if cf and i <= 3 then out(("  ContainerFrame%d parent=%s shown=%s"):format(i, cf:GetParent() and (cf:GetParent():GetName() or "unnamed") or "none", tostring(cf:IsShown()))) end
		end
		-- raw field dump of first 3 occupied slots
		local n = 0
		for bag = 0, 4 do
			for slot = 1, (S.GetContainerNumSlots(bag) or 0) do
				if n < 4 then
					local raw = S.GetContainerItemInfo(bag, slot)
					if raw then
						n = n + 1
						local keys = {}
						for k in pairs(raw) do keys[#keys + 1] = k end
						out(("  bag %d slot %d: iconFileID=%s stackCount=%s itemID=%s | fields: %s"):format(
							bag, slot, tostring(raw.iconFileID), tostring(raw.stackCount), tostring(raw.itemID), table.concat(keys, " ")))
					end
				end
			end
		end
		for _, l in ipairs(lines) do self:LogInfo("bagdebug", l) end
		self:Print("Bag-Debug ins Log geschrieben (/sui log).")
	elseif cmd == "debug" then
		self.debug = not self.debug
		self:Print("Debug", self.debug and "ON" or "OFF")
	else
		Help()
	end
end

function S:Debug(...)
	if self.debug then self:Print("|cffaaaaaa[debug]|r", ...) end
end
