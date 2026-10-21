-- SpeedRun: instance timer bar. Starts when you enter a dungeon/raid,
-- shows elapsed time (movable, pauses while dead-released to ghost? no -
-- real time), and on leaving stores your best run per instance name.
local _, ns = ...
local S = ns.S
local L = S.L
local SR = S:NewModule("SpeedRun", "speedrun")

local floor, format = math.floor, format
local GetInstanceInfo, IsInInstance = GetInstanceInfo, IsInInstance

local frame, startedAt, instName

local function Times()
	S.db.global.instanceTimes = S.db.global.instanceTimes or {}
	return S.db.global.instanceTimes
end

local function UpdateText()
	local e = GetTime() - (startedAt or 0)
	local m, s = floor(e / 60), floor(e % 60)
	frame.text:SetFormattedText("%s  |cff888888%d:%02d|r", instName or L["Instance"], m, s)
end

local function Stop(record)
	if frame then frame:Hide() frame:SetScript("OnUpdate", nil) end
	if record and instName and startedAt then
		local e = floor(GetTime() - startedAt)
		local t = Times()
		if not t[instName] or e < t[instName] then
			t[instName] = e
			S:Print(format(L["New best time for %s: %d:%02d"], instName, floor(e / 60), e % 60))
		else
			S:Print(format(L["Run %s: %d:%02d (best %d:%02d)"], instName,
				floor(e / 60), e % 60, floor(t[instName] / 60), t[instName] % 60))
		end
	end
	startedAt, instName = nil, nil
end

local function Check()
	if not SR.db.enable then Stop(false) return end
	local inInst, itype = IsInInstance()
	local name = inInst and GetInstanceInfo and GetInstanceInfo()
	if inInst and (itype == "party" or itype == "raid") and name then
		if not startedAt then
			startedAt, instName = GetTime(), name
			if not frame then
				frame = CreateFrame("Frame", "SentinelUISpeedRun", UIParent)
				frame:SetSize(240, 22)
				S:SetTemplate(frame, "Transparent")
				frame.text = S:FontString(frame, 11, "OUTLINE", S.media.numberFont)
				frame.text:SetPoint("CENTER")
				S:CreateMover(frame, "speedRun", L["Instance Timer"], { "TOP", UIParent, "TOP", 0, -40 }, "speedrun")
			end
			local best = Times()[name]
			frame:Show()
			frame:SetScript("OnUpdate", function(self2, dt)
				self2.t = (self2.t or 0) + dt
				if self2.t >= 1 then self2.t = 0 UpdateText() end
			end)
			UpdateText()
			if best then S:Print(format(L["Best time %s: %d:%02d"], name, floor(best / 60), best % 60)) end
		end
	elseif startedAt then
		Stop(true)
	end
end

function SR:Initialize()
	self.db = S.db.profile.speedrun
	self:RegisterEvent("PLAYER_ENTERING_WORLD", Check)
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", Check)
end

function SR:Update()
	self.db = S.db.profile.speedrun
	Check()
end
