-- QuestAnnounce: posts objective progress to the party while grouped
-- ("Quest: 4/8 Boars slain"). Tracks objective counts between log updates
-- and only fires on actual increases - quiet on completion, wow-style.
local _, ns = ...
local S = ns.S
local L = S.L
local QA = S:NewModule("QuestAnnounce", "questannounce")

local GetNumQuestLogEntries, GetQuestLogTitle = GetNumQuestLogEntries, GetQuestLogTitle
local GetQuestLogLeaderBoard = GetQuestLogLeaderBoard
local SendChatMessage, IsInGroup = SendChatMessage, IsInGroup

local prev = {}

local function Snapshot()
	local map = {}
	if not (GetNumQuestLogEntries and GetQuestLogTitle and GetQuestLogLeaderBoard) then return map end
	for i = 1, GetNumQuestLogEntries() do
		local title, _, _, isHeader = GetQuestLogTitle(i)
		local qid = select(8, GetQuestLogTitle(i))
		if title and not isHeader and (qid or title) then
			local key = qid or title
			local objs = {}
			for j = 1, 30 do
				local text, objType, finished = GetQuestLogLeaderBoard(j, i)
				if not text then break end
				objs[#objs + 1] = { text = text, done = finished }
			end
			map[key] = { title = title, objs = objs }
		end
	end
	return map
end

function QA:Scan()
	if not IsInGroup() or IsInRaid() then prev = Snapshot() return end -- party only; "PARTY" fails inside a raid
	local now = Snapshot()
	for key, q in pairs(now) do
		local old = prev[key]
		if old then
			for j, o in ipairs(q.objs) do
				local was = old.objs[j]
				if was and not was.done and not o.done then
					-- progress: parse "x/y" out of the objective text
					local a, b = o.text:match("(%d+)%s*/%s*(%d+)")
					local oa = was.text and was.text:match("(%d+)%s*/%s*(%d+)")
					if a and oa and tonumber(a) > tonumber(oa) then
						SendChatMessage(q.title .. ": " .. o.text, "PARTY")
					end
				elseif was and not was.done and o.done then
					SendChatMessage(q.title .. ": " .. o.text, "PARTY")
				end
			end
		end
	end
	prev = now
end

function QA:Initialize()
	self.db = S.db.profile.questannounce
	self:RegisterEvent("QUEST_LOG_UPDATE", function()
		S:SafeCall("QuestAnnounce:Scan", QA.Scan, QA)
	end)
	-- seed silently so login does not announce a wall of progress
	prev = Snapshot()
end

function QA:Update()
	self.db = S.db.profile.questannounce
end
