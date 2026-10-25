-- TargetCounter: shows how many visible enemies are currently targeting
-- the player, displayed above the player unit frame (or a movable holder).
-- Enumerates nameplate units plus boss/arena tokens and counts those whose
-- target is the player.
local _, ns = ...
local S = ns.S
local L = S.L
local TC = S:NewModule("TargetCounter", "targetcounter")

local CreateFrame = CreateFrame
local UnitExists, UnitIsUnit, UnitCanAttack = UnitExists, UnitIsUnit, UnitCanAttack

local holder, counter, elapsed
local tokens = {}
for i = 1, 40 do tokens[#tokens + 1] = "nameplate" .. i end
for i = 1, 5 do tokens[#tokens + 1] = "boss" .. i tokens[#tokens + 1] = "arena" .. i end
for i = 1, 5 do tokens[#tokens + 1] = "party" .. i .. "target" end -- party members' hostile targets

local seenGuid = {}
local function Count()
	local n = 0
	wipe(seenGuid)
	for _, u in ipairs(tokens) do
		if UnitExists(u) and UnitCanAttack("player", u) then
			local t = u .. "target"
			if UnitExists(t) and UnitIsUnit(t, "player") then
				-- one enemy can be reachable via nameplate and a party target at once
				local g = UnitGUID(u)
				if g and S.IsSecret and S.IsSecret(g) then g = nil end
				if not g then n = n + 1
				elseif not seenGuid[g] then seenGuid[g] = true n = n + 1 end
			end
		end
	end
	return n
end

local function Ensure()
	if holder then return end
	holder = CreateFrame("Frame", "SentinelUITargetCounter", UIParent)
	holder:SetSize(60, 16)
	S:CreateMover(holder, "targetcounter", L["Target Counter"], { "TOP", UIParent, "TOP", 0, -140 }, "targetcounter")
	counter = S:FontString(holder, 12, "OUTLINE", S.media.numberFont)
	counter:SetPoint("CENTER")
	holder:SetScript("OnUpdate", function(_, el)
		elapsed = (elapsed or 0) + el
		if elapsed < 0.4 then return end
		elapsed = 0
		local n = Count()
		if n > 0 then
			counter:SetFormattedText("%d %s", n, L["targeting you"])
			counter:Show()
		else
			counter:Hide()
		end
	end)
end

function TC:Initialize()
	self.db = S.db.profile.targetcounter
	Ensure()
end

function TC:Update()
	self.db = S.db.profile.targetcounter
	if holder then holder:SetShown(self.db.enable ~= false) end
end
