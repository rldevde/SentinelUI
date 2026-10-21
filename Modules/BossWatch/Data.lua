-- BossWatch encounter data: spellId -> rule.
--  t      = recast duration in seconds -> timer bar (counted per caster);
--           {min, max} rolls a random duration inside the window each cast
--  warn   = true shows "<spell>!" center-screen; a string overrides the text
--  big    = bigger warning text
--  kind   = bar color bucket (cd/cast/warn/pull/phase/custom)
--  soon   = pre-warning "… soon" when the timer hits 5s remaining
--  sayMe  = "/say <spell> on me!" when the debuff lands on the player
--  track  = lists debuff carriers in the info frame + nameplate icon + arrow
--  mark   = raid target icon (1-8) auto-set on the carrier, cleared on fade
--  rw     = announces "<boss>: <spell>!" to RAID_WARNING/PARTY
--  z      = zone name (groups entries in the /bw rules window)
--  phase  = only active in these phases ("P4" or "P1,P4"); unknown phase = allow
--  setPhase = this event switches the current phase (warns + wipes rule timers)
--  pfirst = when entering `phase`, start the timer immediately with this value
--  Every rule can be disabled individually in /bw rules (db.disabledRules).
local _, ns = ...

ns.BossWatchData = ns.BossWatchData or {}

ns.BossWatchData.rules = {
	-- ==================== Karazhan ====================
	[29511] = { t = { 30, 36 }, warn = true, big = true, z = "Karazhan" },             -- Maiden: Repentance
	[29522] = { sayMe = true, z = "Karazhan" },                                 -- Maiden: Holy Fire
	[29448] = { t = { 30, 38 }, warn = true, z = "Karazhan" },                  -- Moroes: Vanish
	[37066] = { t = { 28, 36 }, warn = true, track = true, z = "Karazhan" },    -- Moroes: Garrote
	[34694] = { warn = true, z = "Karazhan" },                                  -- Moroes: Blind
	[30225] = { warn = true, z = "Karazhan" },                                  -- Curator: Evocation
	[29946] = { t = { 28, 32 }, warn = true, big = true, soon = true, z = "Karazhan" }, -- Aran: Flame Wreath
	[29951] = { t = { 30, 36 }, warn = true, big = true, z = "Karazhan" },      -- Aran: Blizzard
	[29973] = { t = 20, warn = "Arcane Explosion! Slow!", big = true, z = "Karazhan" }, -- Aran
	[29962] = { warn = true, z = "Karazhan" },                                  -- Aran: Summon Water Elementals
	[30115] = { warn = true, sayMe = true, z = "Karazhan" },                    -- Illhoof: Sacrifice (chains)
	[36922] = { t = { 38, 46 }, warn = true, z = "Karazhan" },                  -- Nightbane: Bellowing Roar
	[37098] = { warn = true, z = "Karazhan" },                                  -- Nightbane: Rain of Bones
	[30834] = { t = { 40, 50 }, warn = true, big = true, z = "Karazhan" },      -- Malchezaar: Summon Infernal
	[30843] = { t = { 28, 34 }, warn = true, big = true, soon = true, z = "Karazhan" }, -- Malchezaar: Enfeeblement
	[30852] = { t = { 20, 28 }, warn = true, z = "Karazhan" },                  -- Malchezaar: Shadow Nova
	-- ==================== Gruul's Lair ====================
	[33238] = { t = 15, warn = true, z = "Gruul's Lair" },                      -- Maulgar: Whirlwind/Blast Wave
	[33173] = { warn = true, z = "Gruul's Lair" },                              -- Krosh/Olm: Polymorph
	[33525] = { t = { 35, 45 }, warn = true, big = true, soon = true, z = "Gruul's Lair" }, -- Gruul: Ground Slam
	[33572] = { warn = true, z = "Gruul's Lair" },                              -- Gruul: Gronn Lord's Grip
	[36240] = { warn = true, sayMe = true, z = "Gruul's Lair" },                -- Gruul: Cave In
	[36300] = { warn = "Grow!", z = "Gruul's Lair" },                           -- Gruul: Grow stack
	[33813] = { t = 20, z = "Gruul's Lair" },                                   -- Gruul: Hurtful Strike
	-- ==================== Magtheridon ====================
	[30616] = { t = { 50, 60 }, warn = true, big = true, soon = true, z = "Magtheridon" }, -- Blast Nova
	[30571] = { t = 50, z = "Magtheridon" },                                    -- Quake
	-- ==================== Serpentshrine Cavern ====================
	[38235] = { warn = true, sayMe = true, z = "Serpentshrine Cavern" },        -- Hydross: Water Tomb
	[37433] = { t = 46, warn = true, big = true, soon = true, z = "Serpentshrine Cavern" }, -- Lurker: Spout
	[37363] = { t = 21, warn = true, z = "Serpentshrine Cavern" },              -- Lurker: Whirl
	[38441] = { warn = true, z = "Serpentshrine Cavern" },                      -- Karathress: Cataclysmic Bolt
	[38049] = { warn = true, sayMe = true, track = true, z = "Serpentshrine Cavern" }, -- Morogrim: Watery Grave
	[37640] = { t = { 18, 30 }, warn = true, z = "Serpentshrine Cavern" },              -- Leotheras: Whirlwind
	[37676] = { warn = "Inner Demon!", sayMe = true, big = true, z = "Serpentshrine Cavern" }, -- Leotheras
	[38280] = { t = { 25, 35 }, warn = true, sayMe = true, track = true, mark = 7, z = "Serpentshrine Cavern" }, -- Vashj: Static Charge
	[38509] = { warn = true, sayMe = true, z = "Serpentshrine Cavern" },        -- Vashj: Shock Blast
	-- ==================== Tempest Keep ====================
	[37470] = { t = 50, warn = true, z = "Tempest Keep" },                      -- Al'ar: Meteor
	[35364] = { warn = true, sayMe = true, z = "Tempest Keep" },                -- Al'ar: Dive Bomb
	[34162] = { t = 13, warn = true, z = "Tempest Keep" },                      -- Void Reaver: Pounding
	[34172] = { warn = true, z = "Tempest Keep" },                              -- Void Reaver: Arcane Orb
	[42783] = { warn = true, sayMe = true, track = true, z = "Tempest Keep" },  -- Solarian: Wrath of the Astromancer
	[36735] = { t = { 40, 50 }, warn = true, z = "Tempest Keep" },                      -- Kael'thas: Flame Strike
	[36819] = { warn = "Pyroblast! Kick!", big = true, phase = "P4,P5", z = "Tempest Keep" }, -- Kael'thas: Pyroblast
	[36797] = { warn = true, phase = "P4,P5", z = "Tempest Keep" },             -- Kael'thas: Mind Control
	[35941] = { setPhase = "P5", warn = "Phase 5: Gravity Lapse!", big = true, phase = "P5", z = "Tempest Keep" }, -- Kael'thas P5
	-- ==================== Zul'Aman ====================
	[42398] = { warn = true, z = "Zul'Aman" },                                  -- Nalorakk: Deafening Roar
	[43648] = { warn = true, big = true, z = "Zul'Aman" },                      -- Akil'zon: Electrical Storm
	[42630] = { warn = true, z = "Zul'Aman" },                                  -- Jan'alai: Fire Bombs
	[43139] = { warn = true, z = "Zul'Aman" },                                  -- Halazzi: Frenzy (tranq!)
	[43383] = { t = 30, warn = true, z = "Zul'Aman" },                          -- Hex Lord: Spirit Bolts
	[43093] = { warn = true, track = true, z = "Zul'Aman" },                    -- Zul'jin: Grievous Throw
	[43095] = { warn = true, z = "Zul'Aman" },                                  -- Zul'jin: Creeping Paralysis
	-- ==================== Hyjal ====================
	[31249] = { warn = true, sayMe = true, z = "Hyjal" },                       -- Rage: Icebolt
	[31258] = { warn = true, z = "Hyjal" },                                     -- Rage: Death & Decay
	[38306] = { t = 25, warn = true, z = "Hyjal" },                             -- Anetheron: Carrion Swarm
	[31447] = { warn = true, z = "Hyjal" },                                     -- Kaz'rogal: Mark of Kaz'rogal
	[31347] = { warn = true, sayMe = true, track = true, mark = 8, big = true, z = "Hyjal" }, -- Azgalor: Doom
	[31344] = { warn = true, z = "Hyjal" },                                     -- Azgalor: Howl (silence)
	[32014] = { warn = true, z = "Hyjal" },                                     -- Archimonde: Air Burst
	[31945] = { warn = true, sayMe = true, track = true, z = "Hyjal" },         -- Archimonde: Doomfire
	[31970] = { t = 40, warn = true, z = "Hyjal" },                             -- Archimonde: Fear
	-- ==================== Black Temple ====================
	[39837] = { warn = true, sayMe = true, track = true, z = "Black Temple" },  -- Naj'entus: Impaling Spine
	[39872] = { warn = "Tidal Shield! Stop DPS / break!", big = true, z = "Black Temple" }, -- Naj'entus
	[40251] = { warn = true, sayMe = true, big = true, z = "Black Temple" },    -- Gorefiend: Shadow of Death
	[42005] = { track = true, z = "Black Temple" },                             -- Bloodboil: Bloodboil
	[40604] = { warn = true, sayMe = true, track = true, z = "Black Temple" },  -- Bloodboil: Fel Rage
	[41426] = { warn = "Spirit Shock! Kick!", z = "Black Temple" },             -- RoS: Spirit Shock (interrupt)
	[41431] = { warn = "Runed Shield! Dispel!", z = "Black Temple" },           -- RoS: Runed Shield
	[41001] = { warn = "Fatal Attraction! Move apart!", sayMe = true, track = true, mark = 6, big = true, z = "Black Temple" }, -- Mother
	[41455] = { warn = "Circle of Healing! Kick!", z = "Black Temple" },        -- Council: Malande heal
	[41475] = { warn = "Reflective Shield! Stop casts!", z = "Black Temple" },  -- Council: Malande reflect
	[40832] = { t = 40, warn = true, phase = "P1,P4,P5", z = "Black Temple" },  -- Illidan: Flame Crash
	[41917] = { warn = true, sayMe = true, track = true, phase = "P4,P5", z = "Black Temple" }, -- Illidan: Parasitic Shadowfiend
	[40585] = { warn = true, sayMe = true, track = true, phase = "P2,P4", z = "Black Temple" }, -- Illidan: Dark Barrage
	[40904] = { t = 30, warn = true, phase = "P4", z = "Black Temple" },        -- Illidan: Draw Soul
	[41117] = { setPhase = "P4", warn = "Phase 4: Shadow Demons!", big = true, z = "Black Temple" }, -- Illidan P4 trigger
	[40683] = { setPhase = "P5", warn = "Phase 5: Enrage!", big = true, z = "Black Temple" },       -- Illidan P5 trigger
	-- ==================== Sunwell ====================
	[44869] = { warn = true, sayMe = true, big = true, z = "Sunwell" },         -- Kalecgos: Spectral Blast
	[46394] = { t = 20, warn = true, sayMe = true, track = true, z = "Sunwell" }, -- Brutallus: Burn
	[45185] = { t = 30, warn = true, z = "Sunwell" },                           -- Brutallus: Stomp
	[45661] = { warn = "Encapsulate! Run out!", sayMe = true, mark = 8, big = true, z = "Sunwell" }, -- Felmyst
	[45855] = { t = 23, warn = true, z = "Sunwell" },                           -- Felmyst: Gas Nova
	[45342] = { warn = "Conflagration! Run out!", sayMe = true, track = true, mark = 8, big = true, z = "Sunwell" }, -- Twins
	[45256] = { warn = true, z = "Sunwell" },                                   -- Twins: Confounding Blow
	[45641] = { warn = true, sayMe = true, track = true, z = "Sunwell" },       -- Kil'jaeden: Fire Bloom
	[45664] = { warn = true, sayMe = true, z = "Sunwell" },                     -- Kil'jaeden: Legion Lightning
	[45737] = { t = 15, warn = true, z = "Sunwell" },                           -- Kil'jaeden: Flame Dart
	-- ==================== Molten Core ====================
	[19703] = { t = 20, warn = true, z = "Molten Core" },                       -- Lucifron's Curse (decurse)
	[19716] = { warn = true, z = "Molten Core" },                               -- Gehennas' Curse (decurse)
	[19451] = { warn = "Frenzy! Tranq!", z = "Molten Core" },                   -- Magmadar: Frenzy
	[20475] = { warn = "Living Bomb! Run out!", sayMe = true, track = true, mark = 8, big = true, z = "Molten Core" }, -- Geddon
	[19659] = { warn = true, z = "Molten Core" },                               -- Geddon: Ignite Mana (dispel)
	[19714] = { warn = true, z = "Molten Core" },                               -- Shazzrah: Deaden Magic (dispel)
	[20566] = { t = 27, warn = true, z = "Molten Core" },                       -- Ragnaros: Wrath of Ragnaros
	-- ==================== Blackwing Lair ====================
	[18173] = { warn = true, sayMe = true, track = true, mark = 8, z = "Blackwing Lair" },-- Vael: Burning Adrenaline
	[23461] = { t = 20, warn = true, z = "Blackwing Lair" },                    -- Vael: Flame Breath
	[23331] = { t = 15, warn = true, z = "Blackwing Lair" },                    -- Broodlord: Blast Wave
	[23339] = { t = 30, warn = true, z = "Blackwing Lair" },                    -- Dragons: Wing Buffet
	[22539] = { warn = "Shadow Flame! Cloak!", big = true, z = "Blackwing Lair" }, -- Shadow Flame
	[23310] = { warn = true, z = "Blackwing Lair" },                            -- Chromaggus: Time Lapse
	[22686] = { t = 30, warn = true, z = "Blackwing Lair" },                    -- Nefarian: Bellowing Roar
	-- ==================== Ahn'Qiraj ====================
	[26527] = { warn = true, sayMe = true, z = "Ahn'Qiraj" },                   -- Skeram: True Fulfillment (MC)
	[26180] = { warn = true, z = "Ahn'Qiraj" },                                 -- Huhuran: Wyvern Sting
	[26102] = { t = 22, warn = true, z = "Ahn'Qiraj" },                         -- Ouro: Sand Blast
	-- ==================== Naxxramas ====================
	[28783] = { t = 12, warn = true, z = "Naxxramas" },                         -- Anub'Rekhan: Impale
	[28785] = { t = 90, warn = true, big = true, z = "Naxxramas" },             -- Anub'Rekhan: Locust Swarm
	[28798] = { t = 60, warn = "Frenzy! Tranq!", z = "Naxxramas" },             -- Faerlina: Frenzy
	[29484] = { t = 40, warn = true, z = "Naxxramas" },                         -- Maexxna: Web Spray
	[28622] = { warn = true, track = true, z = "Naxxramas" },                   -- Maexxna: Web Wrap
	[29213] = { t = 55, warn = true, z = "Naxxramas" },                         -- Noth: Curse (decurse)
	[28169] = { warn = true, sayMe = true, track = true, z = "Naxxramas" },     -- Grobbulus: Mutating Injection
	[28157] = { t = 30, warn = true, z = "Naxxramas" },                         -- Grobbulus: Slime Spray
	[28371] = { t = 105, warn = true, big = true, z = "Naxxramas" },            -- Gluth: Decimate
	[28089] = { t = 30, warn = "Polarity Shift!", big = true, z = "Naxxramas" },-- Thaddius
	[29107] = { t = 15, warn = true, z = "Naxxramas" },                         -- Razuvious: Disrupting Shout
	[28832] = { warn = true, z = "Naxxramas" },                                 -- Horsemen: Mark of Korth'azz
	[28833] = { warn = true, z = "Naxxramas" },                                 -- Horsemen: Mark of Blaumeux
	[28834] = { warn = true, z = "Naxxramas" },                                 -- Horsemen: Mark of Mograine
	[28835] = { warn = true, z = "Naxxramas" },                                 -- Horsemen: Mark of Zeliek
	[28542] = { t = 24, warn = true, z = "Naxxramas" },                         -- Sapphiron: Life Drain
	[29879] = { t = 30, warn = true, sayMe = true, track = true, mark = 8, z = "Naxxramas" }, -- KT: Frost Blast
	[28410] = { warn = true, big = true, z = "Naxxramas" },                     -- KT: Chains (MC)
	[27819] = { warn = true, sayMe = true, z = "Naxxramas" },                   -- KT: Mana Detonation
	-- ==================== TBC Dungeons (best-effort ids) ====================
	[38794] = { warn = "Murmur's Touch! Run out!", sayMe = true, track = true, big = true, z = "Shadow Labyrinth" }, -- Murmur
	[38797] = { warn = "Sonic Boom! Move!", big = true, z = "Shadow Labyrinth" }, -- Murmur
	[33676] = { warn = "Incite Chaos! Stop damage!", big = true, z = "Shadow Labyrinth" }, -- Blackheart
	[38194] = { warn = true, z = "Sethekk Halls" },                             -- Ikiss: Arcane Explosion
	[38245] = { warn = true, z = "Sethekk Halls" },                             -- Ikiss: Polymorph
	[25033] = { warn = "Lightning Cloud! Move!", z = "The Steamvault" },        -- Thespia
	[30739] = { warn = "Blade Dance!", big = true, z = "Shattered Halls" },     -- Kargath
	[30580] = { warn = true, z = "The Blood Furnace" },                         -- Keli'dan: Shadow Bolt Volley
	[32421] = { warn = true, z = "Auchenai Crypts" },                           -- Maladaar: Soul Scream
	[36123] = { warn = true, sayMe = true, track = true, z = "Arcatraz" },      -- Zereketh: Seed of Corruption
	[36142] = { warn = true, z = "Arcatraz" },                                  -- Dalliah: Whirlwind
	[37162] = { warn = true, sayMe = true, z = "Arcatraz" },                    -- Skyriss: Domination
	[34661] = { warn = true, sayMe = true, track = true, z = "The Botanica" },  -- Thorngrin: Sacrifice
	[35280] = { warn = true, z = "The Mechanar" },                              -- Pathaleon: Domination
	[31422] = { warn = "Time Stop!", big = true, z = "The Black Morass" },      -- Aeonus
	[31458] = { warn = "Hasten! Dispel!", z = "The Black Morass" },             -- Temporus
	[31715] = { warn = true, sayMe = true, z = "The Underbog" },                -- Black Stalker: Static Charge
	-- ==================== WotLK (Wrath classic / anniversary path) ====================
	[59128] = { warn = "Flame Tsunami! Sidestep!", big = true, z = "Obsidian Sanctum" }, -- Sartharion
	[56105] = { warn = "Vortex!", big = true, z = "Eye of Eternity" },          -- Malygos
	[62680] = { t = 25, warn = true, z = "Ulduar" },                            -- Ignis: Flame Jets
	[64704] = { warn = true, sayMe = true, z = "Ulduar" },                      -- Razorscale: Devouring Flame
	[62776] = { t = 60, warn = "Tympanic Tantrum!", big = true, z = "Ulduar" }, -- XT-002
	[63024] = { warn = true, sayMe = true, track = true, z = "Ulduar" },        -- XT-002: Gravity Bomb
	[63018] = { warn = true, sayMe = true, z = "Ulduar" },                      -- XT-002: Light Bomb
	[63489] = { warn = "Overload! Spread!", big = true, z = "Ulduar" },         -- Steelbreaker
	[61903] = { warn = true, z = "Ulduar" },                                    -- Steelbreaker: Fusion Punch
	[62269] = { warn = "Rune of Death! Move!", z = "Ulduar" },                  -- Runemaster
	[63346] = { warn = "Eyebeam! Move!", sayMe = true, big = true, z = "Ulduar" }, -- Kologarn
	[64290] = { warn = true, track = true, z = "Ulduar" },                      -- Kologarn: Stone Grip
	[64389] = { warn = "Sentinel Blast! Kick!", z = "Ulduar" },                 -- Auriaya
	[64386] = { t = 35, warn = true, z = "Ulduar" },                            -- Auriaya: Terrifying Screech
	[61968] = { warn = "Flash Freeze! Get inside!", big = true, z = "Ulduar" }, -- Hodir
	[62279] = { t = 15, warn = true, z = "Ulduar" },                            -- Thorim: Lightning Charge
	[62859] = { warn = true, z = "Ulduar" },                                    -- Freya: Ground Tremor
	[62589] = { warn = true, sayMe = true, z = "Ulduar" },                      -- Freya: Nature's Fury
	[63631] = { warn = "Shock Blast! Run!", big = true, z = "Ulduar" },         -- Mimiron P1
	[63666] = { warn = true, sayMe = true, z = "Ulduar" },                      -- Mimiron: Napalm Shell
	[62660] = { warn = true, sayMe = true, z = "Ulduar" },                      -- Vezax: Shadow Crash
	[63276] = { warn = true, sayMe = true, z = "Ulduar" },                      -- Vezax: Mark of the Faceless
	[62661] = { warn = "Searing Flames! Kick!", z = "Ulduar" },                 -- Vezax
	[64163] = { warn = "Lunatic Gaze! Look away!", big = true, z = "Ulduar" },  -- Yogg
	[64584] = { warn = "Big Bang!", big = true, z = "Ulduar" },                 -- Algalon
	[66331] = { track = true, z = "Trial of the Crusader" },                    -- Gormok: Impale stacks
	[66532] = { warn = true, z = "Trial of the Crusader" },                     -- Jarraxus: Fel Fireball
	[66197] = { warn = true, sayMe = true, track = true, z = "Trial of the Crusader" }, -- Jarraxus: Legion Flame
	[66118] = { warn = "Leeching Swarm! Phase 3!", big = true, setPhase = "P3", z = "Trial of the Crusader" }, -- Anub
	[67574] = { warn = true, sayMe = true, track = true, z = "Trial of the Crusader" }, -- Anub: Pursued
	[68510] = { warn = true, track = true, z = "Trial of the Crusader" },       -- Anub: Penetrating Cold
	[69076] = { warn = "Bonestorm!", big = true, z = "Icecrown Citadel" },      -- Marrowgar
	[69057] = { warn = true, track = true, z = "Icecrown Citadel" },            -- Marrowgar: Bone Spike
	[71001] = { warn = true, z = "Icecrown Citadel" },                          -- Lady D: Death & Decay
	[71289] = { warn = true, sayMe = true, track = true, z = "Icecrown Citadel" }, -- Lady D: Dominate Mind
	[72293] = { warn = true, track = true, z = "Icecrown Citadel" },            -- Saurfang: Mark of the Fallen Champion
	[69279] = { warn = "Gas Spore! Stack up!", sayMe = true, track = true, big = true, z = "Icecrown Citadel" }, -- Festergut
	[69674] = { warn = "Mutated Infection! To offtank!", sayMe = true, track = true, big = true, z = "Icecrown Citadel" }, -- Rotface
	[72295] = { warn = true, sayMe = true, track = true, z = "Icecrown Citadel" }, -- Putricide: Malleable Goo
	[71340] = { warn = "Pact of the Darkfallen! Stay close!", sayMe = true, track = true, z = "Icecrown Citadel" }, -- Blood Queen
	[70126] = { warn = "Frost Beacon! Get tombed!", sayMe = true, track = true, mark = 7, big = true, z = "Icecrown Citadel" }, -- Sindragosa
	[69762] = { warn = "Unchained Magic! Stop casting!", sayMe = true, z = "Icecrown Citadel" }, -- Sindragosa
	[70123] = { warn = "Blistering Cold! Pull in!", big = true, z = "Icecrown Citadel" }, -- Sindragosa
	[72762] = { warn = "DEFILE! Move!", sayMe = true, track = true, big = true, z = "Icecrown Citadel" }, -- LK: Defile
	[70541] = { warn = "Infest! Top raid!", big = true, z = "Icecrown Citadel" }, -- LK: Infest
	[70337] = { warn = true, track = true, z = "Icecrown Citadel" },            -- LK: Necrotic Plague
	[69037] = { warn = "Val'kyr incoming!", big = true, z = "Icecrown Citadel" }, -- LK P2
	[74562] = { warn = "Fiery Combustion! Run out!", sayMe = true, track = true, big = true, z = "Ruby Sanctum" }, -- Halion
	[74648] = { warn = "Meteor Strike!", big = true, z = "Ruby Sanctum" },      -- Halion
}
