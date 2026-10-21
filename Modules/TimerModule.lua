-- TimerModule: classic clients have no built-in timer/stopwatch. Adds
-- /suitimer mm[:ss] countdown with an alarm, and /suisw stopwatch. If the
-- client lacks Blizzard's /timer and /sw, those are registered too.
local _, ns = ...
local S = ns.S
local L = S.L
local TM = S:NewModule("TimerModule", "timermodule")

local floor = math.floor
local CreateFrame = CreateFrame

local function ParseTime(arg)
	local m, s = tostring(arg or ""):match("^(%d+):?(%d*)$")
	if not m then return end
	return tonumber(m) * 60 + (tonumber(s) or 0)
end

function TM:Build()
	if self.frame then return end
	local f = CreateFrame("Frame", "SentinelUITimer", UIParent)
	f:SetSize(180, 20)
	f:SetPoint("TOP", UIParent, "TOP", 0, -220)
	f:SetFrameStrata("MEDIUM")
	local bar = S:CreateStatusBar(f)
	bar:SetAllPoints()
	bar:SetStatusBarColor(S.accent.r, S.accent.g, S.accent.b)
	local label = S:FontString(bar.suiTextOverlay, 11, "OUTLINE", S.media.numberFont)
	label:SetPoint("CENTER")
	local title = S:FontString(f, 9, "OUTLINE", S.media.unitFont)
	title:SetPoint("BOTTOM", f, "TOP", 0, 1)
	title:SetText(L["Timer"])
	title:SetTextColor(0.7, 0.7, 0.7)
	f.bar, f.label, f.title = bar, label, title
	f:Hide()
	S:CreateMover(f, "Timer", L["Timer"], { "TOP", UIParent, "TOP", 0, -220 }, "timermodule")
	self.frame, self.bar, self.label = f, bar, label
end

function TM:Countdown(seconds)
	if not seconds or seconds <= 0 then
		S:Print(L["Usage: /suitimer mm:ss or /suitimer stop"])
		return
	end
	self:Build()
	self.mode = "down"
	self.total = seconds
	self.endsAt = GetTime() + seconds
	self.frame:Show()
	self:Drive()
end

function TM:Stopwatch()
	self:Build()
	self.mode = "up"
	self.startsAt = GetTime()
	self.frame:Show()
	self:Drive()
end

function TM:Stop()
	self.mode = nil
	if self.frame then self.frame:SetScript("OnUpdate", nil) self.frame:Hide() end
end

function TM:Drive()
	local f = self.frame
	f:SetScript("OnUpdate", function()
		if TM.mode == "down" then
			local left = TM.endsAt - GetTime()
			if left <= 0 then
				TM:Stop()
				S:Print(L["Timer done!"])
				if PlaySoundFile then pcall(PlaySoundFile, "Sound\\Interface\\AlarmClockWarning3.wav") end
				return
			end
			TM.bar:SetMinMaxValues(0, TM.total)
			TM.bar:SetValue(left)
			TM.label:SetFormattedText("%d:%02d", floor(left / 60), left % 60)
		else
			local el = GetTime() - TM.startsAt
			TM.bar:SetMinMaxValues(0, 1)
			TM.bar:SetValue(1)
			TM.label:SetFormattedText("%d:%02d", floor(el / 60), el % 60)
		end
	end)
end

function TM:Slash(arg)
	arg = strtrim(arg or "")
	if arg == "stop" or arg == "cancel" then self:Stop() return end
	local sec = ParseTime(arg)
	if sec then self:Countdown(sec)
	else S:Print(L["Usage: /suitimer mm:ss or /suitimer stop"]) end
end

function TM:Initialize()
	self.db = S.db.profile.timermodule
	S:RegisterChatCommand("suitimer", function(a) TM:Slash(a) end)
	S:RegisterChatCommand("suisw", function() TM:Stopwatch() end)
	-- only shadow Blizzard's commands when the client lacks them
	if not SlashCmdList.STOPWATCH then
		SLASH_SUITIMER1 = "/timer"
		SlashCmdList.SUITIMER = function(a) TM:Slash(a) end
		SLASH_SUISW1 = "/sw"
		SlashCmdList.SUISW = function() TM:Stopwatch() end
	end
end

function TM:Update()
	self.db = S.db.profile.timermodule
end
