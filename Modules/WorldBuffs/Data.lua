local addonName, ns = ...
local D = {}
ns.WorldBuffsData = D

-- cooldown between buff hand-ins (seconds)
D.cooldowns = { rend = 10800, ony = 21600, nef = 28800, zan = 28800 }

-- seconds between the first npc yell and the buff actually landing
D.dropDelay = { rend = 6, ony = 14, nef = 15, zan = 30 }

-- buff spell ids -> internal type (ony/nef share the same aura)
D.spellIDs = {
	[16609] = "rend", [355366] = "rend",
	[22888] = "dragon", [355363] = "dragon", -- rallying cry, ony and nef share this
	[24425] = "zan", [355365] = "zan",
}
D.songflowerSpell = 15366 -- songflower serenade
D.dmfSpells = { -- sayge's dark fortunes
	[23735] = true, [23766] = true, [23767] = true, [23768] = true,
	[23769] = true, [23736] = true, [23737] = true, [23738] = true,
}

-- npc ids of the hand-in npcs (despawn after a drop, respawn ~2min later)
D.buffNpcs = {
	[14392] = "ony", -- overlord runthak (horde)
	[14394] = "ony", -- major mattingly (alliance)
	[14720] = "nef", -- high overlord saurfang (horde)
	[14721] = "nef", -- field marshal afrasiabi (alliance)
	[173758] = "dragon", -- hidden hand-in npc (horde)
	[173754] = "dragon", -- hidden hand-in npc (alliance)
}

-- songflower spawn points in felwood (map 1448), north to south
D.songflowers = {
	{ x = 0.639, y = 0.061 }, { x = 0.558, y = 0.104 }, { x = 0.506, y = 0.139 },
	{ x = 0.633, y = 0.226 }, { x = 0.401, y = 0.444 }, { x = 0.343, y = 0.522 },
	{ x = 0.401, y = 0.565 }, { x = 0.483, y = 0.757 }, { x = 0.459, y = 0.852 },
	{ x = 0.529, y = 0.878 },
}
D.songflowerRespawn = 1500 -- 25 minutes
D.felwoodMapID = 1448

-- chronoboon displacer (stores a copy of your world buffs)
D.chronoboonID = 184937

-- sayge's dark fortunes last 2 hours
D.saygeDuration = 7200

-- darkmoon faire: setup begins the first friday of each month, the faire
-- stays open for a week. locations rotate Elwynn -> Mulgore -> Terokkar.
D.dmfLocations = { "Elwynn Forest", "Mulgore", "Terokkar Forest" }
D.dmfAnchorMonth = 2005 * 12 + 1 -- months since epoch of a known elwynn faire

-- yell detection tables per client locale.
-- each entry: names = set of localized npc names, frags = localized yell
-- substrings that identify the event; loose = accept any yell from names.
D.yells = {
	enUS = {
		rend = {
			names = { ["Thrall"] = true, ["Herald of Thrall"] = true },
			frags = { "Rend Blackhand, has fallen" },
		},
		rend2 = {
			names = { ["Thrall"] = true, ["Herald of Thrall"] = true },
			frags = { "Battle for the glory of the Horde" },
		},
		ony = {
			names = { ["Overlord Runthak"] = true, ["Major Mattingly"] = true },
			frags = { "Onyxia, has been slain", "history has been made" },
		},
		ony2 = {
			names = { ["Overlord Runthak"] = true, ["Major Mattingly"] = true },
			frags = { "Be lifted by the rallying cry", "Onyxia, hangs from the arches" },
		},
		nef = {
			names = { ["High Overlord Saurfang"] = true, ["Field Marshal Afrasiabi"] = true, ["Field Marshal Stonebridge"] = true },
			frags = { "NEFARIAN IS SLAIN", "the Lord of Blackrock is slain" },
		},
		nef2 = {
			names = { ["High Overlord Saurfang"] = true, ["Field Marshal Afrasiabi"] = true, ["Field Marshal Stonebridge"] = true },
			frags = { "Revel in his rallying cry", "Revel in the rallying cry" },
		},
		zan = {
			names = { ["Molthor"] = true, ["Zandalarian Emissary"] = true },
			frags = { "Begin the ritual", "The Blood God" },
		},
		zan2 = {
			names = { ["Molthor"] = true, ["Zandalarian Emissary"] = true },
			frags = { "slayer of Hakkar" },
		},
		hellfire = {
			names = { ["Nazgrel"] = true, ["Force Commander Danath Trollbane"] = true },
			frags = { "Hellfire Citadel is ours", "The feast of corruption is no more" },
		},
	},
	deDE = {
		rend = {
			names = { ["Thrall"] = true, ["Herold von Thrall"] = true },
			frags = { "Rend Blackhand, der falsche" },
		},
		rend2 = {
			names = { ["Thrall"] = true, ["Herold von Thrall"] = true },
			frags = { "Badet in meiner Macht" },
		},
		ony = {
			names = { ["Oberanführer Runthak"] = true, ["Major Mattingly"] = true },
			frags = { "Die Brutmutter Onyxia wurde getötet", "ist Geschichte geschrieben worden" },
		},
		ony2 = {
			names = { ["Oberanführer Runthak"] = true, ["Major Mattingly"] = true },
			frags = { "Siegesschrei der Drachentöter eure Herzen höher schlagen", "Onyxia baumelt leblos" },
		},
		nef = {
			names = { ["Hochfürst Saurfang"] = true, ["Feldmarschall Afrasiabi"] = true, ["Feldmarschall Steinsteg"] = true },
			frags = { "NEFARIAN IST TOT", "NAFARIAN IST TOT", "Herrscher des Blackrocks wurde besiegt" },
		},
		nef2 = {
			names = { ["Hochfürst Saurfang"] = true, ["Feldmarschall Afrasiabi"] = true, ["Feldmarschall Steinsteg"] = true },
			frags = { "Siegesschrei eure Herzen höher schlagen", "Siegesschrei des Drachentöters eure Herzen höher schlagen" },
		},
		zan = {
			names = { ["Molthor"] = true, ["Abgesandter der Zandalarianer"] = true },
			frags = { "Beginnt mit dem Ritual", "Der Blutgott" },
		},
		zan2 = {
			names = { ["Molthor"] = true, ["Abgesandter der Zandalarianer"] = true },
			frags = { "Besieger von Hakkar" },
		},
		hellfire = {
			names = { ["Nazgrel"] = true, ["Danath Trollbann"] = true, ["Force Commander Danath Trollbane"] = true },
			frags = { "Die Zitadelle des Höllenfeuers gehört uns", "Das Festmahl der Verderbnis ist vorüber", "Hellfire Citadel is ours", "The feast of corruption is no more" },
		},
	},
}
