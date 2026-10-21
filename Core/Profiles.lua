-- Profile import / export. Only differences to the defaults are exported.
-- Format: "SUI1:" .. AceSerializer string (deserializing never executes code).
local _, ns = ...
local S = ns.S
local L = S.L

local Serializer = LibStub("AceSerializer-3.0")
local PREFIX = "SUI1:"

local function Diff(cur, def)
	local out
	for k, v in pairs(cur) do
		local d = type(def) == "table" and def[k] or nil
		if type(v) == "table" then
			local sub = Diff(v, d)
			if sub then out = out or {} out[k] = sub end
		elseif v ~= d then
			out = out or {}
			out[k] = v
		end
	end
	return out
end

local function Merge(target, source)
	for k, v in pairs(source) do
		if type(v) == "table" then
			if type(target[k]) ~= "table" then target[k] = {} end
			Merge(target[k], v)
		else
			target[k] = v
		end
	end
end

function S:ExportProfile()
	local diff = Diff(self.db.profile, self.defaults.profile) or {}
	return PREFIX .. Serializer:Serialize({ addon = "SentinelUI", version = self.version, profile = diff })
end

function S:ImportProfile(text, newName)
	text = strtrim(text or "")
	if text:sub(1, #PREFIX) ~= PREFIX then return false, L["Not a SentinelUI profile string."] end
	local ok, data = Serializer:Deserialize(text:sub(#PREFIX + 1))
	if not ok or type(data) ~= "table" or data.addon ~= "SentinelUI" or type(data.profile) ~= "table" then
		return false, L["The profile string is damaged."]
	end
	if newName and newName ~= "" then
		self.db:SetProfile(newName)
	end
	self.db:ResetProfile(nil, true)
	Merge(self.db.profile, data.profile)
	self:StaticReload(L["Profile imported. Reload the UI to apply it?"])
	return true
end

-- spec profiles: map spec name -> profile name, switch on spec change
function S:CheckSpecProfile()
	local spec = self.GetSpecName and self:GetSpecName()
	if not spec or spec == "" then return end
	if self._lastSpec == spec then return end
	self._lastSpec = spec
	local map = self.db and self.db.global and self.db.global.specProfiles
	local prof = map and map[spec]
	if prof and prof ~= "" and self.db:GetCurrentProfile() ~= prof then
		self.db:SetProfile(prof)
		self:Print(format(L["Profile switched: %s (%s)"], prof, spec))
	end
end

function S:SpecProfileOptions()
	return {
		type = "group", name = L["Spec profiles"], order = 50,
		args = {
			desc = { type = "description", order = 1, name = L["Automatically switch to a profile when the spec changes."] },
			cur = {
				type = "select", order = 2, width = "double",
				name = function() return format(L["Profile for %s (current spec)"], tostring(S.GetSpecName and S:GetSpecName() or "?")) end,
				values = function()
					local t = { [""] = L["None"] }
					for _, p in ipairs(S.db:GetProfiles()) do t[p] = p end
					return t
				end,
				get = function()
					local spec = S.GetSpecName and S:GetSpecName()
					local map = S.db.global.specProfiles
					return spec and map and map[spec] or ""
				end,
				set = function(_, v)
					local spec = S.GetSpecName and S:GetSpecName()
					if not spec then return end
					S.db.global.specProfiles = S.db.global.specProfiles or {}
					S.db.global.specProfiles[spec] = v ~= "" and v or nil
				end,
			},
		},
	}
end

-- Options group (added to the Profiles section by Config.lua)
local exportText, importText, importName = "", "", ""
function S:ProfileIOOptions()
	return {
		type = "group", name = L["Import / Export"], order = 100,
		args = {
			exportBtn = {
				type = "execute", order = 1, name = L["Export current profile"],
				func = function() exportText = S:ExportProfile() LibStub("AceConfigRegistry-3.0"):NotifyChange("SentinelUI") end,
			},
			exportBox = {
				type = "input", order = 2, name = L["Export string (Ctrl+A, Ctrl+C)"], multiline = 8, width = "full",
				get = function() return exportText end, set = function() end,
			},
			header = { type = "header", order = 10, name = L["Import"] },
			importName = {
				type = "input", order = 11, name = L["New profile name (empty = overwrite current profile)"], width = "double",
				get = function() return importName end, set = function(_, v) importName = strtrim(v or "") end,
			},
			importBox = {
				type = "input", order = 12, name = L["Paste profile string"], multiline = 8, width = "full",
				get = function() return importText end, set = function(_, v) importText = v or "" end,
			},
			importBtn = {
				type = "execute", order = 13, name = L["Import"],
				func = function()
					local ok, err = S:ImportProfile(importText, importName)
					if not ok then S:Print("|cffff4444" .. err .. "|r") else importText = "" end
				end,
			},
		},
	}
end
