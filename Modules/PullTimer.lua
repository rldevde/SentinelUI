-- PullTimer: /pull <seconds> broadcasts a pull countdown to the group (one
-- chat announcement at start, one at go) and drives a local countdown bar.
-- Party/raid members running SentinelUI get the bar + cancel sync via addon
-- messages; everyone else still sees the chat lines.
local _, ns = ...
local S = ns.S
local L = S.L
local PT = S:NewModule("PullTimer", "pulltimer")

local format, floor = format, math.floor
local CreateFrame = CreateFrame
local PREFIX = "SUIPull"

local function GroupSend(msg)
	local ch = S.GroupChannel()
	if ch then S.SendAddonMessage(PREFIX, msg, ch) end
end

function PT:BuildBar()
	if self.bar then return end
	local f = CreateFrame("Frame", "SentinelUIPullTimer", UIParent)
	f:SetSize(220, 22)
	f:SetPoint("TOP", UIParent, "TOP", 0, -260)
	f:SetFrameStrata("HIGH")
	local bar = S:CreateStatusBar(f)
	bar:SetAllPoints()
	bar:SetStatusBarColor(S.accent.r, S.accent.g, S.accent.b)
	local label = S:FontString(bar.suiTextOverlay, 12, "OUTLINE", S.media.numberFont)
	label:SetPoint("CENTER")
	f.bar, f.label = bar, label
	f:Hide()
	S:CreateMover(f, "PullTimer", L["Pull Timer"], { "TOP", UIParent, "TOP", 0, -260 }, "pulltimer")
	self.frame, self.bar, self.label = f, bar, label
end

function PT:Start(seconds, byName)
	self:BuildBar()
	seconds = floor(tonumber(seconds) or 10)
	if seconds <= 0 then return end
	self.endsAt = GetTime() + seconds
	self.total = seconds
	local f = self.frame
	f.bar:SetMinMaxValues(0, seconds)
	f:Show()
	if byName and byName ~= S.myName then
		f.label:SetFormattedText("%s: %d", byName, seconds)
	end
	if not f:GetScript("OnUpdate") then
		f:SetScript("OnUpdate", function(_, elapsed)
			local left = PT.endsAt - GetTime()
			if left <= 0 then
				PT.frame:SetScript("OnUpdate", nil)
				PT.frame.bar:SetValue(0)
				PT.frame.label:SetText(L["PULL!"])
				C_Timer.After(1.5, function() if PT.frame then PT.frame:Hide() end end)
				if PlaySoundFile then pcall(PlaySoundFile, "Sound\\Interface\\RaidWarning.wav") end
				return
			end
			PT.frame.bar:SetValue(left)
			PT.frame.label:SetFormattedText(L["Pull in %d"], floor(left + 0.5))
		end)
	end
end

function PT:Cancel(byName)
	if not self.frame then return end
	self.frame:SetScript("OnUpdate", nil)
	self.endsAt = nil
	self.frame:Hide()
	if byName and byName ~= S.myName then
		S:Print(format(L["Pull timer cancelled by %s"], byName))
	end
end

function PT:DoPull(arg)
	arg = strtrim(arg or "")
	if arg == "" then arg = tostring(self.db.defaultSeconds or 10) end
	if arg == "cancel" or arg == "0" then
		self:Cancel()
		GroupSend("CANCEL")
		return
	end
	local sec = tonumber(arg)
	if not sec or sec < 1 or sec > 60 then
		S:Print(L["Usage: /pull <1-60> or /pull cancel"])
		return
	end
	self:Start(sec)
	local ch = S.GroupChannel()
	if ch then
		GroupSend(format("PULL:%d", sec))
		if self.db.announce ~= false then
			SendChatMessage(format(L["Pull in %d"], sec), ch)
		end
	end
end

function PT:Initialize()
	self.db = S.db.profile.pulltimer
	S.RegisterAddonPrefix(PREFIX)
	self:RegisterEvent("CHAT_MSG_ADDON", function(_, _, prefix, msg, channel, sender)
		if prefix ~= PREFIX then return end
		local sec = msg:match("^PULL:(%d+)$")
		if sec then PT:Start(tonumber(sec), sender and sender:gsub("%-.*", ""))
		elseif msg == "CANCEL" then PT:Cancel(sender and sender:gsub("%-.*", "")) end
	end)
	-- /pull and /pt
	SLASH_SENTINELPULL1 = "/pull"
	SLASH_SENTINELPULL2 = "/pt"
	SlashCmdList.SENTINELPULL = function(arg) S:SafeCall("PullTimer:Slash", PT.DoPull, PT, arg) end
end

function PT:Update()
	self.db = S.db.profile.pulltimer
end
