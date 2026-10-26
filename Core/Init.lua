local addonName, ns = ...

local S = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceTimer-3.0", "AceHook-3.0")
ns.S = S
_G.SentinelUI = S

S.name = addonName
S.title = "|cffebad33Sentinel|r|cffffffffUI|r"
S.bugtracker = "https://xrl-dev.de/bugtracker"
S.version = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(addonName, "Version") or "dev"
S.accent = { r = 0.92, g = 0.68, b = 0.20 }
S.accentHex = "ebad33"
S.media = {}
S.modules = {}
S.moduleOrder = {}
S.hiddenFrame = CreateFrame("Frame", "SentinelUIHiddenParent", UIParent)
S.hiddenFrame:Hide()

local pcall, xpcall, type, select, pairs, ipairs, tinsert = pcall, xpcall, type, select, pairs, ipairs, tinsert

function S:Print(...)
	print(format("|cff%s[SentinelUI]|r", S.accentHex), ...)
end

function S:Hex(r, g, b)
	if type(r) == "table" then r, g, b = r.r, r.g, r.b end
	return format("|cff%02x%02x%02x", (r or 1) * 255, (g or 1) * 255, (b or 1) * 255)
end

-- Every piece of SentinelUI code runs through SafeCall so that errors are captured
-- in the persistent log (see Logger.lua) instead of breaking the whole UI.
local currentContext
local function errorHandler(err)
	if S.LogError then S:LogError(err, currentContext, debugstack(2)) end
	return err
end

local function SafeCallDone(prev, ok, ...)
	currentContext = prev
	if ok then return ... end -- varargs keep nil holes, unlike {...} + unpack
end

function S:SafeCall(context, func, ...)
	if type(func) ~= "function" then return end
	local prev = currentContext
	currentContext = context
	return SafeCallDone(prev, xpcall(func, errorHandler, ...))
end

function S:Wrap(context, func)
	return function(...) return S:SafeCall(context, func, ...) end
end

-- Lightweight event system. All handlers are protected by SafeCall.
local eventFrame = CreateFrame("Frame")
local registry = {}
S.eventRegistry = registry

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local handlers = registry[event]
	if not handlers then return end
	for owner, handler in pairs(handlers) do
		local func = type(handler) == "string" and owner[handler] or handler
		S:SafeCall((owner.name or "Core") .. ":" .. event, func, owner, event, ...)
	end
end)

local function RegisterEvent(owner, event, handler)
	handler = handler or event
	registry[event] = registry[event] or {}
	registry[event][owner] = handler
	pcall(eventFrame.RegisterEvent, eventFrame, event)
end

local function UnregisterEvent(owner, event)
	local handlers = registry[event]
	if not handlers then return end
	handlers[owner] = nil
	if not next(handlers) then
		registry[event] = nil
		eventFrame:UnregisterEvent(event)
	end
end

local function UnregisterAllEvents(owner)
	for event in pairs(registry) do UnregisterEvent(owner, event) end
end

-- Per-unit events need their own frame so RegisterUnitEvent filters stay isolated.
local function RegisterUnitEvent(owner, event, handler, ...)
	owner.unitEventFrames = owner.unitEventFrames or {}
	local f = owner.unitEventFrames[event]
	if not f then
		f = CreateFrame("Frame")
		owner.unitEventFrames[event] = f
	end
	local func = handler or event
	f:SetScript("OnEvent", function(_, ev, ...)
		local fn = type(func) == "string" and owner[func] or func
		S:SafeCall((owner.name or "Core") .. ":" .. ev, fn, owner, ev, ...)
	end)
	if f.RegisterUnitEvent then
		f:RegisterUnitEvent(event, ...)
	else
		f:RegisterEvent(event)
	end
end

S.RegisterEvent = RegisterEvent
S.UnregisterEvent = UnregisterEvent
S.UnregisterAllEvents = UnregisterAllEvents
S.RegisterUnitEvent = RegisterUnitEvent

-- Module system
local Module = {}
Module.RegisterEvent = RegisterEvent
Module.UnregisterEvent = UnregisterEvent
Module.UnregisterAllEvents = UnregisterAllEvents
Module.RegisterUnitEvent = RegisterUnitEvent

function Module:Print(...) S:Print("|cffffffff" .. self.name .. ":|r", ...) end

function Module:Delay(seconds, func, ...)
	local args, n = { ... }, select("#", ...)
	C_Timer.After(seconds, function()
		S:SafeCall(self.name .. ":Delay", func, unpack(args, 1, n))
	end)
end

function Module:SecureHook(target, method, func)
	local name = self.name
	if type(target) == "string" then
		target, method, func = _G, target, method
	end
	if type(func) == "string" then func = self[func] end
	local wrapped = function(...) S:SafeCall(name .. ":Hook", func, self, ...) end
	if target == _G then
		if type(_G[method]) == "function" then hooksecurefunc(method, wrapped) return true end
	elseif target and target[method] then
		hooksecurefunc(target, method, wrapped)
		return true
	end
end

function Module:HookScript(frame, script, func)
	if not frame or not frame.HookScript then return end
	local name = self.name
	if type(func) == "string" then func = self[func] end
	frame:HookScript(script, function(...) S:SafeCall(name .. ":" .. script, func, self, ...) end)
end

function Module:IsEnabled()
	return self.initialized and not (self.private and self.private.enable == false)
end

function S:NewModule(name, dbKey)
	local mod = setmetatable({ name = name, dbKey = dbKey or name:lower() }, { __index = Module })
	self.modules[name] = mod
	tinsert(self.moduleOrder, mod)
	return mod
end

function S:GetModule(name)
	return self.modules[name]
end

function S:InitializeModules()
	for _, mod in ipairs(self.moduleOrder) do
		mod.db = self.db.profile[mod.dbKey]
		mod.private = self.private and self.private[mod.dbKey]
		local enabled = not (mod.private and mod.private.enable == false)
		if enabled and mod.Initialize then
			self:SafeCall(mod.name .. ":Initialize", mod.Initialize, mod)
			mod.initialized = true
		end
	end
end

function S:UpdateModules()
	for _, mod in ipairs(self.moduleOrder) do
		-- modules whose settings live elsewhere (e.g. general.totemTracker) keep their own db
		if self.db.profile[mod.dbKey] ~= nil then mod.db = self.db.profile[mod.dbKey] end
		if mod.initialized and mod.Update then
			self:SafeCall(mod.name .. ":Update", mod.Update, mod)
		end
	end
end

-- Run something as soon as we leave combat (protected frame manipulation).
local combatQueue = {}
local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function()
	for i = 1, #combatQueue do
		local job = combatQueue[i]
		S:SafeCall("CombatQueue", job.func, unpack(job.args, 1, job.n))
	end
	wipe(combatQueue)
end)

function S:RunOutOfCombat(func, ...)
	if InCombatLockdown() then
		local a1, a2 = ...
		for _, job in ipairs(combatQueue) do
			if job.func == func and job.args[1] == a1 and job.args[2] == a2 then return end
		end
		tinsert(combatQueue, { func = func, args = { ... }, n = select("#", ...) })
	else
		self:SafeCall("RunOutOfCombat", func, ...)
	end
end
