-- Instance data per expansion (raids + dungeons with player caps).
-- Data only; consumed by Modules/RaidReset.lua.
local _, ns = ...

local InstanceData = {}

InstanceData.CLASSIC = {
	raids = {
		{ name = "Molten Core", maxPlayers = 40, resetType = "weekly" },
		{ name = "Blackwing Lair", maxPlayers = 40, resetType = "weekly" },
		{ name = "Ahn'Qiraj Temple", maxPlayers = 40, resetType = "weekly" },
		{ name = "Ruins of Ahn'Qiraj", maxPlayers = 20, resetType = "weekly" },
		{ name = "Zul'Gurub", maxPlayers = 20, resetType = "weekly" },
		{ name = "Onyxia's Lair", maxPlayers = 40, resetType = "weekly" },
		{ name = "Naxxramas", maxPlayers = 40, resetType = "weekly" },
	},
	dungeons = {
		{ name = "Deadmines", maxPlayers = 5, resetType = "daily" },
		{ name = "Wailing Caverns", maxPlayers = 5, resetType = "daily" },
		{ name = "Shadowfang Keep", maxPlayers = 5, resetType = "daily" },
		{ name = "Blackfathom Deeps", maxPlayers = 5, resetType = "daily" },
		{ name = "Razorfen Kraul", maxPlayers = 5, resetType = "daily" },
		{ name = "Razorfen Downs", maxPlayers = 5, resetType = "daily" },
		{ name = "Uldaman", maxPlayers = 5, resetType = "daily" },
		{ name = "Maraudon", maxPlayers = 5, resetType = "daily" },
		{ name = "Zul'Farrak", maxPlayers = 5, resetType = "daily" },
		{ name = "Temple of Atal'Hakkar", maxPlayers = 5, resetType = "daily" },
		{ name = "Blackrock Depths", maxPlayers = 5, resetType = "daily" },
		{ name = "Blackrock Spire", maxPlayers = 5, resetType = "daily" },
		{ name = "Dire Maul", maxPlayers = 5, resetType = "daily" },
		{ name = "Stratholme", maxPlayers = 5, resetType = "daily" },
		{ name = "Scholomance", maxPlayers = 5, resetType = "daily" },
	},
}

InstanceData.TBC = {
	raids = {
		{ name = "Karazhan", maxPlayers = 10, resetType = "weekly" },
		{ name = "Gruul's Lair", maxPlayers = 25, resetType = "weekly" },
		{ name = "Magtheridon's Lair", maxPlayers = 25, resetType = "weekly" },
		{ name = "Serpentshrine Cavern", maxPlayers = 25, resetType = "weekly" },
		{ name = "The Eye", maxPlayers = 25, resetType = "weekly" },
		{ name = "Hyjal Summit", maxPlayers = 25, resetType = "weekly" },
		{ name = "Black Temple", maxPlayers = 25, resetType = "weekly" },
		{ name = "Sunwell Plateau", maxPlayers = 25, resetType = "weekly" },
		{ name = "Zul'Aman", maxPlayers = 10, resetType = "weekly" },
	},
	dungeons = {
		{ name = "Hellfire Ramparts", maxPlayers = 5, resetType = "daily" },
		{ name = "The Blood Furnace", maxPlayers = 5, resetType = "daily" },
		{ name = "The Shattered Halls", maxPlayers = 5, resetType = "daily" },
		{ name = "Mana-Tombs", maxPlayers = 5, resetType = "daily" },
		{ name = "Auchenai Crypts", maxPlayers = 5, resetType = "daily" },
		{ name = "Sethekk Halls", maxPlayers = 5, resetType = "daily" },
		{ name = "Shadow Labyrinth", maxPlayers = 5, resetType = "daily" },
		{ name = "Slave Pens", maxPlayers = 5, resetType = "daily" },
		{ name = "The Underbog", maxPlayers = 5, resetType = "daily" },
		{ name = "The Steamvault", maxPlayers = 5, resetType = "daily" },
		{ name = "The Mechanar", maxPlayers = 5, resetType = "daily" },
		{ name = "The Botanica", maxPlayers = 5, resetType = "daily" },
		{ name = "The Arcatraz", maxPlayers = 5, resetType = "daily" },
		{ name = "Magisters' Terrace", maxPlayers = 5, resetType = "daily" },
	},
}

InstanceData.WOTLK = {
	raids = {
		{ name = "Naxxramas", maxPlayers = 25, resetType = "weekly" },
		{ name = "Obsidian Sanctum", maxPlayers = 25, resetType = "weekly" },
		{ name = "Eye of Eternity", maxPlayers = 25, resetType = "weekly" },
		{ name = "Ulduar", maxPlayers = 25, resetType = "weekly" },
		{ name = "Trial of the Crusader", maxPlayers = 25, resetType = "weekly" },
		{ name = "Icecrown Citadel", maxPlayers = 25, resetType = "weekly" },
		{ name = "Vault of Archavon", maxPlayers = 25, resetType = "weekly" },
		{ name = "Onyxia's Lair", maxPlayers = 25, resetType = "weekly" },
		{ name = "Ruby Sanctum", maxPlayers = 25, resetType = "weekly" },
	},
	dungeons = {
		{ name = "Utgarde Keep", maxPlayers = 5, resetType = "daily" },
		{ name = "The Nexus", maxPlayers = 5, resetType = "daily" },
		{ name = "Azjol-Nerub", maxPlayers = 5, resetType = "daily" },
		{ name = "Ahn'kahet: The Old Kingdom", maxPlayers = 5, resetType = "daily" },
		{ name = "Drak'Tharon Keep", maxPlayers = 5, resetType = "daily" },
		{ name = "Violet Hold", maxPlayers = 5, resetType = "daily" },
		{ name = "Gundrak", maxPlayers = 5, resetType = "daily" },
		{ name = "Halls of Stone", maxPlayers = 5, resetType = "daily" },
		{ name = "Halls of Lightning", maxPlayers = 5, resetType = "daily" },
		{ name = "The Culling of Stratholme", maxPlayers = 5, resetType = "daily" },
		{ name = "Trial of the Champion", maxPlayers = 5, resetType = "daily" },
		{ name = "Forge of Souls", maxPlayers = 5, resetType = "daily" },
		{ name = "Pit of Saron", maxPlayers = 5, resetType = "daily" },
		{ name = "Halls of Reflection", maxPlayers = 5, resetType = "daily" },
	},
}

InstanceData.CATA = {
	raids = {
		{ name = "Blackwing Descent", maxPlayers = 25, resetType = "weekly" },
		{ name = "Bastion of Twilight", maxPlayers = 25, resetType = "weekly" },
		{ name = "Throne of the Four Winds", maxPlayers = 25, resetType = "weekly" },
		{ name = "Firelands", maxPlayers = 25, resetType = "weekly" },
		{ name = "Dragon Soul", maxPlayers = 25, resetType = "weekly" },
		{ name = "Baradin Hold", maxPlayers = 25, resetType = "weekly" },
	},
	dungeons = {
		{ name = "Blackrock Caverns", maxPlayers = 5, resetType = "daily" },
		{ name = "Throne of the Tides", maxPlayers = 5, resetType = "daily" },
		{ name = "Vortex Pinnacle", maxPlayers = 5, resetType = "daily" },
		{ name = "The Stonecore", maxPlayers = 5, resetType = "daily" },
		{ name = "Lost City of the Tol'vir", maxPlayers = 5, resetType = "daily" },
		{ name = "Halls of Origination", maxPlayers = 5, resetType = "daily" },
		{ name = "Grim Batol", maxPlayers = 5, resetType = "daily" },
		{ name = "Deadmines", maxPlayers = 5, resetType = "daily" },
		{ name = "Shadowfang Keep", maxPlayers = 5, resetType = "daily" },
		{ name = "Zul'Aman", maxPlayers = 5, resetType = "daily" },
		{ name = "Zul'Gurub", maxPlayers = 5, resetType = "daily" },
		{ name = "Well of Eternity", maxPlayers = 5, resetType = "daily" },
		{ name = "Hour of Twilight", maxPlayers = 5, resetType = "daily" },
		{ name = "End Time", maxPlayers = 5, resetType = "daily" },
	},
}

InstanceData.MOP = {
	raids = {
		{ name = "Mogu'shan Vaults", maxPlayers = 25, resetType = "weekly" },
		{ name = "Heart of Fear", maxPlayers = 25, resetType = "weekly" },
		{ name = "Terrace of Endless Spring", maxPlayers = 25, resetType = "weekly" },
		{ name = "Throne of Thunder", maxPlayers = 25, resetType = "weekly" },
		{ name = "Siege of Orgrimmar", maxPlayers = 25, resetType = "weekly" },
	},
	dungeons = {
		{ name = "Temple of the Jade Serpent", maxPlayers = 5, resetType = "daily" },
		{ name = "Stormstout Brewery", maxPlayers = 5, resetType = "daily" },
		{ name = "Gate of the Setting Sun", maxPlayers = 5, resetType = "daily" },
		{ name = "Shado-Pan Monastery", maxPlayers = 5, resetType = "daily" },
		{ name = "Siege of Niuzao Temple", maxPlayers = 5, resetType = "daily" },
		{ name = "Mogu'shan Palace", maxPlayers = 5, resetType = "daily" },
		{ name = "Scholomance", maxPlayers = 5, resetType = "daily" },
		{ name = "Scarlet Halls", maxPlayers = 5, resetType = "daily" },
		{ name = "Scarlet Monastery", maxPlayers = 5, resetType = "daily" },
	},
}

InstanceData.WOD = {
	raids = {
		{ name = "Highmaul", maxPlayers = 30, resetType = "weekly" },
		{ name = "Blackrock Foundry", maxPlayers = 30, resetType = "weekly" },
		{ name = "Hellfire Citadel", maxPlayers = 30, resetType = "weekly" },
	},
	dungeons = {
		{ name = "Bloodmaul Slag Mines", maxPlayers = 5, resetType = "daily" },
		{ name = "Shadowmoon Burial Grounds", maxPlayers = 5, resetType = "daily" },
		{ name = "Auchindoun", maxPlayers = 5, resetType = "daily" },
		{ name = "Skyreach", maxPlayers = 5, resetType = "daily" },
		{ name = "Grimrail Depot", maxPlayers = 5, resetType = "daily" },
		{ name = "Upper Blackrock Spire", maxPlayers = 5, resetType = "daily" },
		{ name = "Iron Docks", maxPlayers = 5, resetType = "daily" },
		{ name = "The Everbloom", maxPlayers = 5, resetType = "daily" },
	},
}

InstanceData.LEGION = {
	raids = {
		{ name = "Emerald Nightmare", maxPlayers = 30, resetType = "weekly" },
		{ name = "Trial of Valor", maxPlayers = 30, resetType = "weekly" },
		{ name = "Nighthold", maxPlayers = 30, resetType = "weekly" },
		{ name = "Tomb of Sargeras", maxPlayers = 30, resetType = "weekly" },
		{ name = "Antorus, the Burning Throne", maxPlayers = 30, resetType = "weekly" },
	},
	dungeons = {
		{ name = "Eye of Azshara", maxPlayers = 5, resetType = "daily" },
		{ name = "Darkheart Thicket", maxPlayers = 5, resetType = "daily" },
		{ name = "Black Rook Hold", maxPlayers = 5, resetType = "daily" },
		{ name = "Halls of Valor", maxPlayers = 5, resetType = "daily" },
		{ name = "Neltharion's Lair", maxPlayers = 5, resetType = "daily" },
		{ name = "Vault of the Wardens", maxPlayers = 5, resetType = "daily" },
		{ name = "Maw of Souls", maxPlayers = 5, resetType = "daily" },
		{ name = "The Arcway", maxPlayers = 5, resetType = "daily" },
		{ name = "Court of Stars", maxPlayers = 5, resetType = "daily" },
		{ name = "Cathedral of Eternal Night", maxPlayers = 5, resetType = "daily" },
		{ name = "Seat of the Triumvirate", maxPlayers = 5, resetType = "daily" },
	},
}

InstanceData.BFA = {
	raids = {
		{ name = "Uldir", maxPlayers = 30, resetType = "weekly" },
		{ name = "Battle of Dazar'alor", maxPlayers = 30, resetType = "weekly" },
		{ name = "Crucible of Storms", maxPlayers = 30, resetType = "weekly" },
		{ name = "The Eternal Palace", maxPlayers = 30, resetType = "weekly" },
		{ name = "Ny'alotha, the Waking City", maxPlayers = 30, resetType = "weekly" },
	},
	dungeons = {
		{ name = "Atal'Dazar", maxPlayers = 5, resetType = "daily" },
		{ name = "Freehold", maxPlayers = 5, resetType = "daily" },
		{ name = "Tol Dagor", maxPlayers = 5, resetType = "daily" },
		{ name = "The MOTHERLODE!!", maxPlayers = 5, resetType = "daily" },
		{ name = "Waycrest Manor", maxPlayers = 5, resetType = "daily" },
		{ name = "The Underrot", maxPlayers = 5, resetType = "daily" },
		{ name = "Shrine of the Storm", maxPlayers = 5, resetType = "daily" },
		{ name = "Kings' Rest", maxPlayers = 5, resetType = "daily" },
		{ name = "Siege of Boralus", maxPlayers = 5, resetType = "daily" },
		{ name = "Temple of Sethraliss", maxPlayers = 5, resetType = "daily" },
	},
}

InstanceData.SHADOWLANDS = {
	raids = {
		{ name = "Castle Nathria", maxPlayers = 30, resetType = "weekly" },
		{ name = "Sanctum of Domination", maxPlayers = 30, resetType = "weekly" },
		{ name = "Sepulcher of the First Ones", maxPlayers = 30, resetType = "weekly" },
	},
	dungeons = {
		{ name = "The Necrotic Wake", maxPlayers = 5, resetType = "daily" },
		{ name = "Plaguefall", maxPlayers = 5, resetType = "daily" },
		{ name = "Mists of Tirna Scithe", maxPlayers = 5, resetType = "daily" },
		{ name = "Halls of Atonement", maxPlayers = 5, resetType = "daily" },
		{ name = "Spires of Ascension", maxPlayers = 5, resetType = "daily" },
		{ name = "Theater of Pain", maxPlayers = 5, resetType = "daily" },
		{ name = "Sanguine Depths", maxPlayers = 5, resetType = "daily" },
		{ name = "De Other Side", maxPlayers = 5, resetType = "daily" },
		{ name = "Tazavesh: The Veiled Market", maxPlayers = 5, resetType = "daily" },
	},
}

InstanceData.DRAGONFLIGHT = {
	raids = {
		{ name = "Vault of the Incarnates", maxPlayers = 30, resetType = "weekly" },
		{ name = "Aberrus, the Shadowed Crucible", maxPlayers = 30, resetType = "weekly" },
		{ name = "Amirdrassil, the Dream's Hope", maxPlayers = 30, resetType = "weekly" },
	},
	dungeons = {
		{ name = "The Azure Vault", maxPlayers = 5, resetType = "daily" },
		{ name = "The Nokhud Offensive", maxPlayers = 5, resetType = "daily" },
		{ name = "Algeth'ar Academy", maxPlayers = 5, resetType = "daily" },
		{ name = "Ruby Life Pools", maxPlayers = 5, resetType = "daily" },
		{ name = "Brackenhide Hollow", maxPlayers = 5, resetType = "daily" },
		{ name = "Halls of Infusion", maxPlayers = 5, resetType = "daily" },
		{ name = "Neltharus", maxPlayers = 5, resetType = "daily" },
		{ name = "Uldaman: Legacy of Tyr", maxPlayers = 5, resetType = "daily" },
		{ name = "The Dawnbreaker", maxPlayers = 5, resetType = "daily" },
		{ name = "The Everbloom", maxPlayers = 5, resetType = "daily" },
		{ name = "Ara-Kara, City of Echoes", maxPlayers = 5, resetType = "daily" },
		{ name = "City of Threads", maxPlayers = 5, resetType = "daily" },
		{ name = "The Stonevault", maxPlayers = 5, resetType = "daily" },
		{ name = "Priory of the Sacred Flame", maxPlayers = 5, resetType = "daily" },
		{ name = "Darkflame Cleft", maxPlayers = 5, resetType = "daily" },
	},
}

InstanceData.WAR_WITHIN = {
	raids = {
		{ name = "Nerub-ar Palace", maxPlayers = 30, resetType = "weekly" },
		{ name = "Liberation of Undermine", maxPlayers = 30, resetType = "weekly" },
		{ name = "Manaforge Omega", maxPlayers = 30, resetType = "weekly" },
	},
	dungeons = {
		{ name = "Ara-Kara, City of Echoes", maxPlayers = 5, resetType = "daily" },
		{ name = "City of Threads", maxPlayers = 5, resetType = "daily" },
		{ name = "The Stonevault", maxPlayers = 5, resetType = "daily" },
		{ name = "Priory of the Sacred Flame", maxPlayers = 5, resetType = "daily" },
		{ name = "Darkflame Cleft", maxPlayers = 5, resetType = "daily" },
		{ name = "The Dawnbreaker", maxPlayers = 5, resetType = "daily" },
		{ name = "The Rookery", maxPlayers = 5, resetType = "daily" },
		{ name = "Cinderbrew Meadery", maxPlayers = 5, resetType = "daily" },
		{ name = "Operation: Floodgate", maxPlayers = 5, resetType = "daily" },
		{ name = "Eco-Dome Al'dani", maxPlayers = 5, resetType = "daily" },
		{ name = "Halls of Atonement", maxPlayers = 5, resetType = "daily" },
	},
}

function InstanceData.GetCurrentVersionData()
	local _, _, _, toc = GetBuildInfo()
	if toc >= 110000 then return InstanceData.WAR_WITHIN, "WAR_WITHIN" end
	if toc >= 100000 then return InstanceData.DRAGONFLIGHT, "DRAGONFLIGHT" end
	if toc >= 90000 then return InstanceData.SHADOWLANDS, "SHADOWLANDS" end
	if toc >= 80000 then return InstanceData.BFA, "BFA" end
	if toc >= 70000 then return InstanceData.LEGION, "LEGION" end
	if toc >= 60000 then return InstanceData.WOD, "WOD" end
	if toc >= 50000 then return InstanceData.MOP, "MOP" end
	if toc >= 40000 then return InstanceData.CATA, "CATA" end
	if toc >= 30000 then return InstanceData.WOTLK, "WOTLK" end
	if toc >= 20000 then return InstanceData.TBC, "TBC" end
	return InstanceData.CLASSIC, "CLASSIC"
end

ns.RDResetInstanceData = InstanceData
