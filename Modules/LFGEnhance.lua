local S = SentinelUI
local L = S.L

-- Right-click interactions inside Blizzard's own group finder
-- (Blizzard_GroupFinder_VanillaStyle: LFGListingFrame / LFGBrowseFrame).
-- Right click on a listing row = whisper, shift+right click = invite.

local LE = S:NewModule("LFGEnhance", "lfgenhance")

local hooked = {}

local CONTROL_NAMES = {
	"SendMessageButton", "GroupInviteButton", "RefreshButton", "BackButton",
	"PostButton", "DropDown", "Tab", "CloseButton", "RoleButton", "CheckButton",
	"ExpandOrCollapseButton", "ResetButton", "ScrollBar",
}

local function IsControlName(name)
	if not name or name == "" then return false end
	for _, pat in ipairs(CONTROL_NAMES) do
		if name:find(pat, 1, true) then return true end
	end
	return false
end

local function ValidName(t)
	if type(t) ~= "string" or t == "" then return nil end
	t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
	-- a player name (optionally Name-Realm): no spaces, no digits, sane length
	if t:find("[%s%d]") or #t < 3 or #t > 24 then return nil end
	return t
end

local function TextName(fs)
	return ValidName(fs and fs.GetText and fs:GetText())
end

local FIELD_KEYS = { "name", "playerName", "leaderName", "ownerName", "leader", "player" }
local TABLE_KEYS = { "result", "resultInfo", "entry", "info", "data", "searchResult", "lfgInfo", "applicant" }

local function FieldName(v, depth)
	if type(v) ~= "table" or depth > 2 then return nil end
	for _, k in ipairs(FIELD_KEYS) do
		local n = ValidName(v[k])
		if n then return n end
	end
	return nil
end

local function ResolveName(row)
	local n = FieldName(row, 1)
	if n then return n end
	for _, k in ipairs(TABLE_KEYS) do
		local v = row[k]
		if type(v) == "function" then
			local ok, res = pcall(v, row)
			if ok then n = FieldName(res, 1) end
		else
			n = FieldName(v, 1)
		end
		if n then return n end
	end
	if row.elementData then
		local ed = type(row.elementData) == "function" and row.elementData() or row.elementData
		n = FieldName(ed, 1)
		if n then return n end
	end
	-- fallback: first font string that looks like a name (name is column 1)
	if row.GetRegions then
		for i = 1, select("#", row:GetRegions()) do
			local r = select(i, row:GetRegions())
			if r and r.IsObjectType and r:IsObjectType("FontString") then
				n = TextName(r)
				if n then return n end
			end
		end
		if row.GetChildren then
			for i = 1, select("#", row:GetChildren()) do
				local c = select(i, row:GetChildren())
				if c and c.GetRegions then
					for j = 1, select("#", c:GetRegions()) do
						local r = select(j, c:GetRegions())
						if r and r.IsObjectType and r:IsObjectType("FontString") then
							n = TextName(r)
							if n then return n end
						end
					end
				end
			end
		end
	end
	return nil
end

local function Whisper(name)
	if not name then return end
	if ChatFrame_SendTell then
		ChatFrame_SendTell(name)
	elseif ChatFrame_OpenChat then
		ChatFrame_OpenChat("/w " .. name .. " ")
	end
end

local function Invite(name)
	if not name then return end
	if C_PartyInfo and C_PartyInfo.InviteUnit then
		pcall(C_PartyInfo.InviteUnit, name)
	elseif InviteUnit then
		pcall(InviteUnit, name)
	end
end

local function OnRowClick(row, button)
	if button ~= "RightButton" then return end
	local name = ResolveName(row)
	if not name or name == "" then return end
	if IsShiftKeyDown() then
		Invite(name)
	else
		Whisper(name)
	end
end

local function HookRows(frame, depth)
	depth = depth or 0
	if not frame or depth > 6 or not frame.GetChildren then return end
	if frame.IsForbidden and frame:IsForbidden() then return end
	for i = 1, select("#", frame:GetChildren()) do
		local c = select(i, frame:GetChildren())
		if c and not hooked[c] and (not c.IsForbidden or not c:IsForbidden()) then
			local otype = c.GetObjectType and c:GetObjectType()
			if otype == "Button" and not IsControlName(c:GetName()) and c.GetRegions then
				-- listing rows are anonymous buttons with text regions
				hooked[c] = true
				c:HookScript("OnMouseUp", OnRowClick)
			end
			HookRows(c, depth + 1)
		end
	end
end

function LE:Setup()
	if self.done then return end
	local browse = _G.LFGBrowseFrame
	local listing = _G.LFGListingFrame
	if not browse and not listing then return end
	if browse then HookRows(browse) end
	if listing then HookRows(listing) end
	-- rows can be created lazily after first data
	if browse and not self.rescan then
		self.rescan = true
		browse:HookScript("OnShow", function()
			C_Timer.After(0.3, function() HookRows(_G.LFGBrowseFrame) end)
		end)
	end
	self.done = true
end

function LE:Initialize()
	if not (self.db and self.db.enable) then return end
	if IsAddOnLoaded and IsAddOnLoaded("Blizzard_GroupFinder_VanillaStyle") then
		self:Setup()
	else
		self:RegisterEvent("ADDON_LOADED", function(_, _, addon)
			if addon == "Blizzard_GroupFinder_VanillaStyle" then LE:Setup() end
		end)
	end
	-- parent frame may open before the addon registers as loaded
	if LFGParentFrame then
		LFGParentFrame:HookScript("OnShow", function() LE:Setup() end)
	end
end
