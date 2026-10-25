-- Screenshots: automatic screenshot on level up, achievements and raid-boss
-- kills (with a short delay so the kill feed/ding animation is in the frame).
local _, ns = ...
local S = ns.S
local L = S.L
local SC = S:NewModule("Screenshots", "screenshots")

local CreateFrame = CreateFrame

-- raid/world bosses by NPC id (vanilla + TBC set; easy to extend)
local BOSS_NPC = {
	-- ZG / Ony / MC
	[14517]=1,[14507]=1,[14510]=1,[11382]=1,[15083]=1,[11380]=1,[14834]=1,[15114]=1,
	[10184]=1,[12118]=1,[11982]=1,[12259]=1,[12057]=1,[12056]=1,[12264]=1,[12265]=1,[11988]=1,[12018]=1,[11502]=1,
	-- BWL / AQ
	[12435]=1,[13020]=1,[12017]=1,[11981]=1,[14601]=1,[11983]=1,[14020]=1,[11583]=1,
	[15348]=1,[15341]=1,[15340]=1,[15370]=1,[15369]=1,[15339]=1,
	[15263]=1,[15543]=1,[15544]=1,[15511]=1,[15516]=1,[15510]=1,[15299]=1,[15509]=1,[15275]=1,[15276]=1,[15727]=1,[15517]=1,
	-- Naxx40
	[15956]=1,[15953]=1,[15952]=1,[15954]=1,[15936]=1,[16011]=1,[16028]=1,[15931]=1,[15932]=1,[15928]=1,[16061]=1,[16060]=1,[15989]=1,[15990]=1,
	-- Karazhan
	[16151]=1,[16152]=1,[16457]=1,[15687]=1,[17534]=1,[17533]=1,[17521]=1,[15691]=1,[15688]=1,[16524]=1,[15689]=1,[17225]=1,[15690]=1,
	-- Gruul / Mag
	[18831]=1,[19044]=1,[17257]=1,
	-- SSC
	[21216]=1,[21217]=1,[21215]=1,[21214]=1,[21213]=1,[21212]=1,
	-- TK / Hyjal
	[19514]=1,[19516]=1,[18805]=1,[19622]=1,
	[17767]=1,[17808]=1,[17888]=1,[17842]=1,[17968]=1,
	-- BT
	[22887]=1,[22898]=1,[22871]=1,[22948]=1,[22856]=1,[22947]=1,[22949]=1,[22950]=1,[22951]=1,[22952]=1,[22917]=1,
	-- ZA
	[23574]=1,[23576]=1,[23578]=1,[23577]=1,[24239]=1,[23863]=1,
	-- SWP
	[24850]=1,[24882]=1,[25038]=1,[25166]=1,[25165]=1,[25741]=1,[25315]=1,
	-- Wrath raids (same npc ids where reused)
	[28860]=1,[28859]=1,[31125]=1,[33993]=1,[35013]=1,[38433]=1,
	[33113]=1,[33118]=1,[33186]=1,[33293]=1,[32867]=1,[32927]=1,[32857]=1,[32930]=1,[33515]=1,[32845]=1,[32865]=1,[32906]=1,[33350]=1,[33271]=1,[33288]=1,
	[34796]=1,[34797]=1,[34799]=1,[34780]=1,[34496]=1,[34497]=1,[34564]=1,
	[36612]=1,[36855]=1,[37813]=1,[36626]=1,[36627]=1,[36678]=1,[37970]=1,[37972]=1,[37973]=1,[37955]=1,[36789]=1,[36853]=1,[36597]=1,[39863]=1,
}

local function NpcID(guid)
	if not guid then return end
	local id = guid:match("Creature%-0%-%d+%-%d+%-%d+%-(%d+)%-%d+") or guid:match("Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%d+")
	return id and tonumber(id)
end

function SC:Shoot(what)
	local now = GetTime()
	if self.lastShot and now - self.lastShot < 15 then return end
	self.lastShot = now
	if self.db.chatNote ~= false then
		S:Print(format(L["Screenshot taken (%s)"], what))
	end
	-- small delay: let the kill feed / level-up flare become visible first
	C_Timer.After(self.db.delay or 1.0, function()
		if Screenshot then Screenshot() end
	end)
end

function SC:Initialize()
	self.db = S.db.profile.screenshots
	if self.db.levelUp then
		self:RegisterEvent("PLAYER_LEVEL_UP", function() SC:Shoot(L["level up"]) end)
	end
	if self.db.achievement and (ACHIEVEMENT_EARNED or C_AchievementInfo) then
		self:RegisterEvent("ACHIEVEMENT_EARNED", function() SC:Shoot(L["achievement"]) end)
	end
	if self.db.bossKill then
		self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", function()
			local _, sub, _, _, _, _, _, dguid = CombatLogGetCurrentEventInfo()
			if sub ~= "UNIT_DIED" or not dguid then return end
			-- a dead boss unit frame is the clean signal; npc-id list as fallback
			for i = 1, 8 do
				local u = "boss" .. i
				if UnitExists(u) and UnitGUID(u) == dguid then return SC:Shoot(L["boss kill"]) end
			end
			local id = NpcID(dguid)
			if id and BOSS_NPC[id] and (IsInRaid() or IsInGroup()) then SC:Shoot(L["boss kill"]) end
		end)
	end
end

function SC:Update()
	self.db = S.db.profile.screenshots
end
