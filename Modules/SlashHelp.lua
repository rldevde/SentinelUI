-- SlashHelp: /suicmd prints every SentinelUI slash command with a hint.
local _, ns = ...
local S = ns.S
local L = S.L

local CMDS = {
	{ "/sui", L["Open the options window"] },
	{ "/sway", L["Set a navigation waypoint"] },
	{ "/way", L["Same as /sway"] },
	{ "/suiann", L["Announcer config"] },
	{ "/suibis", L["BiS guide"] },
	{ "/suibless", L["Blessings overview"] },
	{ "/suimage", L["Mage tools"] },
	{ "/suihp", L["Healer protection settings"] },
	{ "/suirc", L["Raid check"] },
	{ "/suirg", L["Raid grid"] },
	{ "/suiloot", L["Loot window"] },
	{ "/suilootlog", L["Loot history"] },
	{ "/suiqs", L["QuestScope"] },
	{ "/suitf", L["Totem forge"] },
	{ "/sbug", L["Bug report folder"] },
	{ "/isync", L["ItemSync"] },
	{ "/pull", L["Pull timer"] },
	{ "/bw", L["Boss watch"] },
	{ "/sw", L["Stopwatch"] },
	{ "/timer", L["Generic timer"] },
	{ "/rlbi", L["BetterItem reload"] },
	{ "/rlrdr", L["Raid/dungeon reset"] },
	{ "/rlrep", L["Reputation tools"] },
	{ "/smt Name", L["Assign main tank"] },
	{ "/sot Name", L["Assign off/assist tank"] },
	{ "/suicmd", L["This command list"] },
	{ "/suim", L["Toggle frame movers"] },
	{ "/sui log", L["Error/diagnostic log"] },
}

SLASH_SENTINELCMDS1 = "/suicmd"
SlashCmdList.SENTINELCMDS = function()
	S:Print(L["Commands:"] or "Commands:")
	for _, c in ipairs(CMDS) do
		DEFAULT_CHAT_FRAME:AddMessage("|cff18a8ff" .. c[1] .. "|r  " .. (c[2] or ""))
	end
end
