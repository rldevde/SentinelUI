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

-- blizzard's finder has no delist button on this client; try every API the
-- various flavors expose to leave your own listing
local function Delist()
	local tries = {
		function() return C_LFGList and C_LFGList.RemoveListing and C_LFGList.RemoveListing() end,
		function() return C_LFGList and C_LFGList.ClearActiveGroupFinderActivity and C_LFGList.ClearActiveGroupFinderActivity() end,
		function() return LFGRemoveListing and LFGRemoveListing() end,
		function() return LFGListRemoveListing and LFGListRemoveListing() end,
		function() return LeaveLFGQueue and LeaveLFGQueue() end,
	}
	for _, fn in ipairs(tries) do
		local ok, r = pcall(fn)
		if ok and r ~= false then return true end
	end
end

-- is the player currently listed in the finder? different clients expose
-- different APIs, try them all
local function IsListed()
	if C_LFGList then
		if C_LFGList.HasActiveEntryInfo then
			local ok, r = pcall(C_LFGList.HasActiveEntryInfo)
			if ok then return not not r end
		end
		if C_LFGList.GetActiveEntryInfo then
			local ok, r = pcall(C_LFGList.GetActiveEntryInfo)
			if ok then return r ~= nil and r ~= false end
		end
	end
	if LFGHasListing then
		local ok, r = pcall(LFGHasListing)
		if ok then return not not r end
	end
	if GetLFGMode then
		local ok, r = pcall(GetLFGMode)
		if ok and r and r ~= "none" and r ~= "idle" then return true end
	end
	-- fallback: blizzard shows "Your listings" entries on the browse frame
	local f = _G.LFGBrowseFrame or _G.LFGListFrame
	if f and f.numEntries and f.numEntries > 0 then return true end
	return false
end

local function AddDelistButton(parent)
	if not parent or parent.suiDelist then return end
	local btn = CreateFrame("Button", "SentinelUILFGDelist", parent)
	btn:SetSize(90, 20)
	btn:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 8, 6)
	if S.SkinButton then S:SkinButton(btn) else S:SetTemplate(btn, "Default") end
	local fs = S:FontString(btn, 11, "OUTLINE")
	fs:SetAllPoints()
	fs:SetText(L["Unlist"] or "Unlist")
	btn:SetScript("OnClick", function()
		if Delist() then
			S:Print(L["Listing removed"] or "Listing removed")
		else
			S:Print(L["No delist API on this client"] or "No delist API on this client")
		end
	end)
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(L["Remove your own group listing"] or "Remove your own group listing")
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	-- only usable while actually listed — poll cheaply on a throttle
	btn.t = 0
	btn:SetScript("OnUpdate", function(self, dt)
		self.t = self.t + dt
		if self.t < 0.5 then return end
		self.t = 0
		self:SetEnabled(IsListed())
		fs:SetAlpha(IsListed() and 1 or 0.4)
	end)
	parent.suiDelist = btn
end

function LE:Setup()
	if self.done then return end
	-- frame names differ across clients: TBC group finder uses
	-- LFGBrowseFrame/LFGListingFrame, Era's LFG tool uses LFGListFrame and
	-- friends — hook whatever exists
	local browse = _G.LFGBrowseFrame or _G.LFGListFrame
	local listing = _G.LFGListingFrame or _G.LFGListFrame
	if not browse and not listing then return end
	if browse then HookRows(browse) AddDelistButton(browse) end
	if listing then HookRows(listing) AddDelistButton(listing) end
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
	local FINDER_ADDONS = {
		"Blizzard_GroupFinder_VanillaStyle", "Blizzard_LFGVanilla",
		"Blizzard_GroupFinder", "Blizzard_LFGTool",
	}
	for _, addon in ipairs(FINDER_ADDONS) do
		if IsAddOnLoaded and IsAddOnLoaded(addon) then self:Setup() break end
	end
	self:RegisterEvent("ADDON_LOADED", function(_, _, addon)
		for _, name in ipairs(FINDER_ADDONS) do
			if addon == name then LE:Setup() break end
		end
	end)
	-- parent frame may open before the addon registers as loaded
	if LFGParentFrame then
		LFGParentFrame:HookScript("OnShow", function() LE:Setup() end)
	end
end
