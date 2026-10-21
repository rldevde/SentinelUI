-- Daily dungeon quest data (TBC Shattrath "WANTED" quests).
-- Data only; consumed by Modules/RaidReset.lua.
local _, ns = ...

local QuestData = {}

QuestData.TBC = {
	normal = {
		{ id = 11364, name = "WANTED: Nazan's Riding Crop",          dungeon = "Hellfire Ramparts" },
		{ id = 11354, name = "WANTED: Keli'dan's Feathered Stave",   dungeon = "The Blood Furnace" },
		{ id = 11371, name = "WANTED: Coilfang Myrmidons",           dungeon = "The Steamvault" },
		{ id = 11376, name = "WANTED: Shattered Hand Centurions",    dungeon = "Shadow Labyrinth" },
		{ id = 11382, name = "WANTED: The Epoch Hunter's Head",      dungeon = "Old Hillsbrad Foothills" },
		{ id = 11383, name = "WANTED: Rift Lords",                   dungeon = "Black Morass" },
		{ id = 11384, name = "WANTED: A Black Stalker Egg",          dungeon = "The Underbog" },
		{ id = 11385, name = "WANTED: A Warp Stalker Specimen",      dungeon = "The Botanica" },
		{ id = 11386, name = "WANTED: The Scroll of Skyriss",        dungeon = "The Arcatraz" },
		{ id = 11387, name = "WANTED: Sisters of Torment",           dungeon = "The Botanica" },
		{ id = 11388, name = "WANTED: Arcatraz Sentinels",           dungeon = "The Arcatraz" },
		{ id = 11362, name = "WANTED: The Warlord's Treatise",       dungeon = "The Shattered Halls" },
	},
	heroic = {
		{ id = 11389, name = "WANTED: Nazan's Riding Crop (H)",          dungeon = "Hellfire Ramparts" },
		{ id = 11390, name = "WANTED: Keli'dan's Feathered Stave (H)",   dungeon = "The Blood Furnace" },
		{ id = 11391, name = "WANTED: Coilfang Myrmidons (H)",           dungeon = "The Steamvault" },
		{ id = 11392, name = "WANTED: Shattered Hand Centurions (H)",    dungeon = "Shadow Labyrinth" },
		{ id = 11393, name = "WANTED: The Epoch Hunter's Head (H)",      dungeon = "Old Hillsbrad Foothills" },
		{ id = 11394, name = "WANTED: Rift Lords (H)",                   dungeon = "Black Morass" },
		{ id = 11395, name = "WANTED: A Black Stalker Egg (H)",          dungeon = "The Underbog" },
		{ id = 11396, name = "WANTED: A Warp Stalker Specimen (H)",      dungeon = "The Botanica" },
		{ id = 11397, name = "WANTED: The Scroll of Skyriss (H)",        dungeon = "The Arcatraz" },
		{ id = 11398, name = "WANTED: Sisters of Torment (H)",           dungeon = "The Botanica" },
		{ id = 11399, name = "WANTED: Arcatraz Sentinels (H)",           dungeon = "The Arcatraz" },
		{ id = 11400, name = "WANTED: The Warlord's Treatise (H)",       dungeon = "The Shattered Halls" },
	},
}

function QuestData.GetCurrentVersionQuests()
	local _, _, _, toc = GetBuildInfo()
	-- only TBC/Anniversary-era clients have the Shattrath daily quest givers
	if toc < 30000 then return QuestData.TBC end
	return nil
end

ns.RDResetQuestData = QuestData
