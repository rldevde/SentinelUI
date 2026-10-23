# Changelog

All notable changes to SentinelUI are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Note on versions: `## Version` is SentinelUI's own release number. The embedded
BetterItem module reports `## X-BetterItem-Version` and must always equal the
standalone RLBetterItem release.

## [1.4.1]

### Added
- **XP bar: pending quest XP** — completed quests in the quest log now paint a green segment behind the rested fill and the text shows "+X quest XP"; the tooltip lists the pending amount, quest count and whether turning them in levels you up (or how much is still missing)
- **Per-unit frame styles** — every unit frame group (player, target, focus, pet, party, raid, raid40, boss, arena, maintank, …) now has a Style dropdown in its settings: "Sentinel (edge + power rail)", "Edge accent only" or "Classic (stacked bars)". Solo frames default to Sentinel, group frames (party/raid/maintank) default to Classic — the previous look is unchanged
- **Nameplate style "Hidden" for friendly units** — friendlyStyle gains a HIDE option that suppresses friendly nameplates entirely (SentinelUI plate + Blizzard bar pinned at 0 alpha); switch takes effect live, enemy plates unaffected

### Changed
- **Navigation defers to a real TomTom install** — when TomTom is loaded it keeps its own arrow/pins; SentinelUI forwards every waypoint into it (local mirror stays for chain tracking), the own arrow/minimap pin stand down, and a light arrival watcher keeps quest-chain advancing working
- **Navigation module rewritten** — the navigator was rebuilt from scratch with the same surface (arrow with title/distance/ETA, world-map pins + route line, minimap edge pin, quest navigation, corpse waypoint, TomTom facade, `/sway`) but leaner internals: no more conv diagnostics, and the arrow never retargets to stale waypoints on its own
- **Aggro alert off by default** — the module now defaults to disabled (was noisy for tanks); enable via Modules → Aggro Alert
- **Cursor ring off by default** — the mouse-follow ring now defaults to disabled for new profiles

### Fixed
- **Buffs/debuffs never spawned** — `SecureAuraHeader_Update` is file-local in the restricted env on this client (unreachable from addon code), so the refresh was a silent no-op; headers now re-trigger via a benign `filter` attribute re-set which re-enters the template's own update path, and content fill scans real children
- **Empty buff/debuff squares** — removing the insecure `OnAttributeChanged` hook also removed the only code path that filled aura contents (icon/timer/stacks); header refreshes now always run the module-side content pass afterwards
- **Navigation dead with real TomTom installed** — forwarded waypoints never set TomTom's crazy flag (its autoqueue profile default can be off), so the TomTom arrow never reacted; target waypoints now pass `crazy=true`
- **Quest-XP on the XP bar** — client quest-XP APIs don't exist on this flavor; completed-quest XP now resolves through Questie's QuestXP database first, with client-API fallbacks
- **Questie->TomTom RemoveWaypoint crash** — Questie's tracker calls `TomTom:RemoveWaypoint` on uids TomTom already cleared on arrival, which crashes inside TomTom on nil coords; SentinelUI now wraps `TomTom:RemoveWaypoint` with a dead-uid guard when a real TomTom is installed
- **R-key whisper reply crashed** — the REPLY binding calls `ReplyTell` directly on this client, whose internal `UpdateHeader` errors when the chat-type lookup misses; the messenger now hooks `ReplyTell` too so R opens the conversation window instead of erroring
- **Party/raid header combat blocks (final)** — the secure group headers' own OnEvent/OnUpdate scripts kept calling `SecureGroupHeader_Update` mid-combat (`SetPoint` on protected children -> ADDON_ACTION_BLOCKED); the scripts are detached and the module drives roster/pet refreshes itself, deferred to regen when in combat
- **Mana/energy tick bar never showed** — the bar only started on `UNIT_POWER_UPDATE`, which is unreliable on this client; it now also listens on `UNIT_POWER_FREQUENT` and kicks on combat start / entering world
- **BetterItem: overlapping numbers on char/inspect slots** — score, durability-% and compare-% texts piled onto the item icons together with the iLvl; a one-time migration now switches all of them off so only the quality-colored iLvl remains (all can be re-enabled in the options; embedded BetterItem 1.9.5)
- **Aura-header combat block hardened** — the secure aura template's OnEvent/OnUpdate scripts and all its event registrations are now fully detached; the module drives aura updates itself (full update out of combat, contents-only refresh mid-combat)
- **Roll summary announced "Ihr" as the winner** — the German "Ihr gewann %s" line also matched the generic "%s gewann %s" pattern, so your own wins posted as "Ihr gewann ..."; you-win formats are now matched first and a captured localized "You" resolves to your character name
- **Nav arrow retargeted to stale waypoints** — after reaching a waypoint the arrow fell back to the *closest* waypoint in the whole database, which resurrected leftover quest picks, old corpse markers and other-zone points instead of just disappearing. Arrival now only advances to the next pick of the *same* chain; with no continuation the arrow hides. The zone-change auto-retarget is removed too — the arrow only points where you (or a quest) explicitly sent it
- **ADDON_ACTION_BLOCKED on buff/debuff icons in combat** — the secure aura header's internal `UNIT_AURA` handler ran `SecureAuraHeader_Update` mid-combat, calling `ClearAllPoints` on protected aura buttons. The header's own `UNIT_AURA` registration is removed and the module drives updates itself: out of combat the full secure update runs, in combat only the contents of already-mapped buttons refresh and a full update is queued for regen
- **ADDON_ACTION_BLOCKED on group headers in combat** — the visibility state driver sat on the protected secure header, so a state flip mid-combat (member joins, raid size crossing the @raid6 threshold) triggered `SecureGroupHeader_Update` -> `SetPoint` on protected unit buttons and got blocked. The driver now drives the unprotected holder frame that parents each header, so only show/hide happens in combat
- **BetterItem: char/inspect slot numbers unreadable** — the iLvl, score, durability and compare texts on paper-doll slots were 8px with a thin outline and got lost in the item icons; now 9-10px THICKOUTLINE with a black drop shadow so they stay legible on any icon (embedded BetterItem 1.9.5)
- **BetterItem: average item level dragged down by unscorable gear** — items the score table can't value contributed item level 0 to the Ø iLvl on tooltips and char/inspect summary instead of their real level; unscored items now count their actual ilvl. iLvl displays (tooltip line, slot overlay, average) also prefer `GetDetailedItemLevelInfo` when available (embedded BetterItem 1.9.5)
- **Party frames dropped group members** — the party header never set `unitsPerColumn`/`maxColumns`, so the client's fallback could wrap extra members into an invisible second column; both attributes are now set explicitly. `GROUP_ROSTER_UPDATE` also forces the secure headers to reassign units, so members who joined while the header was hidden or mid-combat are no longer left out
- AFK screen: character model no longer loops/restarts its animation while AFK (re-entrant toggle guard)
- AFK screen: yellow "You are AFK" chat message no longer spams permanently — Anti-AFK no longer fights the flag while the screen is shown, the auto-clear is deferred to just before the idle logout
- **Mana tick bar never showed for energy users** — the bar only started on a readable power change, but UNIT_POWER_UPDATE fires with secret values on this client so rogues and cat-form druids never saw the bar; it now starts on any tracked power event. Shapeshifting into a tracked form also starts the bar, and the title switches between "Mana Tick" / "Energy Tick"
- **Threat meter width** — the window was a fixed 180px, so names overlapped or clipped into the percentage. Width now adapts to the widest visible name or the title (110–400px), measured on an unconstrained font string so anchoring cannot skew the read
- **Roll summary showed the dice result as the winner** — roll-result lines also contain the item link and were mistaken for the win line; only lines matching `LOOT_ROLL_WON`/`LOOT_ROLL_YOU_WON` are announced now, and the winner is picked by capture analysis (the non-numeric, non-link capture) so arg order cannot swap name and dice result
- **Event-arg off-by-one in 12 handlers** — anonymous `RegisterEvent` handlers receive `(owner, event, payload…)`, but 12 sites bound the payload to the 2nd parameter, so they got the event name instead of real data. Silently killed: loot-roll summary (`GetLootRollItemLink` usage error), minimap ping names, aggro warning, banish timer, external-buff icons, fishing skill-ups, hunter ammo-on-aura check, nameplate quest refresh, purge icon, session XP/kill tracking, soulstone tracking
- **Quest Items crash on load** — the module file was missing its `ns`/`S` bootstrap lines, so it errored at startup and the whole module never initialized
- **Outfit bar drag error** — dragging the outfit bar while docked to the bottom bar threw "Frame is not movable"; the drag handler now checks movability first
- **Data text slots overlapping** — slot widths were measured on font strings clamped to their slot box, so the read could under-report and texts bled into each other ("Neue Post" over the next slot); widths are now measured on an unconstrained font string

## [1.4.0]

### Fixed
- **Raid check inspect crash** — `INSPECT_READY` called `ShortName` before its local declaration, so every inspect reply errored and enchant/gem data never populated
- **Friends-list notes hook** — falls back to `FriendsFrame_UpdateFriends` on clients where `FriendsList_Update` does not exist
- **Nameplate cast bar overlap** — the "-> target" cast-target text sat on the same right edge as the cast timer, so spell name / timer / target painted on top of each other; the target text now anchors left of the timer and the spell name is clipped before it

### Added
- **XP per hour + level ETA** — the "Experience" data text now tracks gains over the session and appends "(12.3k/h · ~45m)" once a minute of data exists
- **Auto-watch reputation** — the watched-faction bar follows whichever faction gained reputation last (General → autoWatch, on by default)
- **Auto dismount** — casting while mounted drops the mount instead of just showing "You are mounted", so the next press casts (General → autoDismount, on by default)
- **Quest Items bar** — movable strip of clickable buttons for usable quest items found in the bags (secure item buttons, count labels, tooltips; updates on bag/quest changes, combat-safe; module: Quest Items)
- **Reputation data text right-click** — right-clicking the Rep slot now cycles the watched faction to the next one in the faction list
- **Quest progress announce** — posts "Quest: objective (5/8)" to party chat when a quest objective advances (General → questAnnounce, on by default)
- **Auction House background scan** — opening the AH automatically re-runs the getAll scan when the price DB is stale (>15 min) and the query cooldown allows it (auctionhouse.autoScan, on by default)
- **Quest log search** — the search box now also sits in the quest log: non-matching titles and zone headers are dimmed to 15% (module: Spell Search)
- **Anti-AFK** — clears the AFK flag as soon as the server sets it so the 30-minute idle logout never starts (General → antiAFK, on by default)
- **Auto-fill delete confirm** — the required word is typed into the item-delete popup automatically, you only confirm the button (General → autoDelete, on by default)
- **Map reveal on every flavor** — the fog reveal now pulls the zone's art tiles straight from the client via `C_Map.GetMapArtLayerTextures` when available, so unexplored areas reveal on WotLK/Cata/retail maps too; the baked Classic/TBC tile table remains as fallback
- **Castbar pushback marker** — when a cast is delayed by damage a red tick marks the point the bar jumped back to (fades over 0.6s), on top of the existing "+0.4s" delay text
- **AH price lines in item tooltips** — the price tooltip now shows the freshest scanned unit price ("AH" + age) alongside the existing min/avg history, plus the vendor sell price
- **Cursor Ring** — subtle accent-colored ring that follows the mouse cursor so it stays findable during raid clutter (module: Cursor Ring; size/alpha under General → cursorRingSize/cursorRingAlpha)
- **Price history time series** — every scan (browse and getAll) now records a price sample per ~6h window (40 samples, 14-day retention, account-wide SavedVariables); tooltips gain a "Trend Nd" line comparing newest vs. oldest stored price (+x% red / -x% green)
- **Price chart** — `/suiprice [itemlink]` opens a movable bar chart of the item's stored price history (min/max/last labels, latest bar highlighted, ESC closes)
- **Price alerts** — `/suialert [itemlink] <price>` sets a target unit price (e.g. `40g`, `2g50s`); every browse or getAll scan at or below the target prints a chat alert (once per 12h per item), `/suialert` lists, `/suialert [itemlink]` removes
- **Consumables check** — `/suiconsume` scans party/raid for food (Well Fed/Satt) and flask/elixir buffs and lists who is missing what (locale-aware buff matching)
- **Player notes** — `/suinote <name> <text>` stores an account-wide note shown as a gold line in that player's unit tooltip; `/suinote` lists, `/suinote <name>` removes (module: Notes)
- **Alt mail list** — small arrow button next to the mail recipient field opens a dropdown of your own characters (from AltRoster) for one-click recipient fill
- **Notes in friends list** — players with a stored `/suinote` get a gold asterisk and their note text as the status line in the friends list (General → friendsNotes, on by default)
- **Roll summary** — after a group loot roll resolves, "X won [item]" is posted to party/raid chat (General → rollSummary, on by default)
- **Trade gold display** — both sides' offered gold is shown as a prominent line at the bottom of the trade window (General → tradeGold, on by default)
- **Buff expiry warning** — a chat warning + sound fires once when a food/flask/elixir buff drops below 5 minutes remaining (General → buffExpireWarn, on by default; weapon enchant expiry is already covered by Weapon Buff)
- **Bags almost full warning** — toast + sound when free bag space drops to 3 slots or fewer while looting, throttled to once per minute (General → bagFullWarn, on by default)
- **Friend online ding** — plays a join sound when a friend comes online (General → friendDing, on by default)
- **Gold per hour** — the Session data text tooltip now shows the G/h farm rate once ~70 seconds of data exist
- **Unspent talent points reminder** — icon with the open-point count appears while points are unspent; click opens the talent frame, movable via /sui move (General → talentWarn, on by default)
- **Low ammo warning** — hunters get a chat warning + sound when equipped ammo (or thrown count) drops below 100 (General → ammoWarn, on by default)
- **Durability warning** — toast + sound on login and on death when lowest gear durability is below 20% (General → duraWarn, on by default)
- **Time played in tooltip** — the Time data text tooltip now shows playtime at this level and total (requested on login)
- **Heal Grid: custom aura watch** — `auraWatch` accepts comma-separated spell IDs or names (e.g. `6788, 974` for Weakened Soul / Earth Shield); matching auras on any member show as up to 2 icons at the cell's top-left
- **Heal Grid: only-dispellable filter** — `onlyDispellable` hides debuff icons your class cannot remove (per-class type table, Shaman magic dispel only on Wrath+)
- **Heal Grid: HoT duration text** — own HoT icons show remaining time (seconds, `Xm` for minutes) via `hotDuration`, on by default
- **Heal Grid: pets, AFK, visibility** — `showPets` adds raid/party pets in the last column, AFK members get an `<AFK>` tag, and `visibilityMode` (Always / In group or raid / Raid only) auto-hides and auto-shows the grid

## [1.3.0]

### Added
- **Options search** — new "Search" group at the top of `/sui`: type 2+ characters to filter every setting in the tree, results show their full path and jump straight to the option on click
- **Quest progress on nameplates** — enemy plates show the unfinished kill/collect counter ("3/8") under the bar when the unit's name appears in a quest objective (Nameplates → quest)
- **World map fog reveal** — unexplored tiles are drawn back onto the zone map at low alpha instead of staying black (World Map → mapReveal, tint color + alpha configurable)
- **Nameplate cast target** — enemy castbars now show who the spell lands on ("-> Name", class-colored for players; Nameplates → castTarget)
- **Nameplate custom texts** — free tag texts ([name], [level], [health:short], ...) on nameplates with the same editor as unit frames (Nameplates → Custom Texts)
- **Quest marker on nameplates** — a "!" icon sits next to the progress counter on plates of mobs needed for a quest objective
- **Food Reminder** — pulsing fork/knife icon when out of combat with mana below the threshold and no eat/drink aura (optionally only with food in bags; movable)
- **Weapon Skills** — lists weapon skills below the level cap (detected by max rank, works in every locale; optional Defense display; movable)
- **Spell Search** — search box inside the spellbook dims non-matching spell buttons; zero taint, re-applies on page/tab flips
- **Turn-in waypoints match the "?"** — completed quests now navigate to Blizzard's own turn-in POI position instead of spawn-database coords that could sit meters away from the real NPC
- **Craft Queue button optional** — the "Mats" button on profession windows is now off by default and can be re-enabled via Craft Queue → Show Button
- **Reminder frame spacing** — Food Reminder and Weapon Skills now sit right of the center stack so they no longer overlap the mana-tick, swing-timer and potion-reminder frames
- **Character sheet gear overlay** — item level per slot (quality colored), red "!" on enchantable slots without an enchant, gem icons — same overlay the inspect window already had
- **Cutaway health bars** — recently lost health lingers as a fading red slice on unit frames (Unitframes → Cutaway)
- **Party frame buffs on by default** — party members now show their own buffs above the frame (18px, up to 4), like the target frame already did
- **Crafting cost line** — profession windows show mats cost vs. expected sale price vs. profit from the AH price DB (Craft Queue → Show Cost)
- **Weapon Skills module now opt-in** — disabled by default (Modules → Weapon Skills to re-enable); its frame layout was reworked so text lines can no longer render outside the box
- **Click Cast** — Clique-style click bindings on the unit frames: each shift/ctrl/alt + left/right/middle combo can run a configured spell (name or ID) on the frame's unit while plain clicks still target. Attributes are applied out of combat to every unit frame and existing group-header child; roster changes re-apply them
- **Aura Watch** — generic weakauras-lite: up to 3 movable watcher frames, each configured with spell (name or ID), unit (target/player/focus/pet) and kind (buff/debuff); shows icon, name, stack count and remaining duration while the aura is up (module: Aura Watch)
- **Price History** — passive auction tracking: every browse-list update records each item's lowest per-unit buyout account-wide; item tooltips show "AH min" + age and running "AH avg". Entries older than 14 days are pruned
- **Loot History** (`/suilootlog`, `/lh`) — scrollable raid/party loot log window: every loot message carrying an item link is stored timestamped, newest first; hovering a row shows the item tooltip
- **Instance Timer** — movable elapsed-time bar that starts on dungeon/raid entry; on leaving it reports the run and stores your **best time per instance** account-wide (chat note on new records)
- **Rank Reminder** — compares every spell on the action bars against the spellbook's max rank per spell and warns once per session per spell when an outdated rank is placed (resets on level up)
- **Minimap ping alert** — chat line "X hat die Minikarte gepingt" when a group member pings (option: General → pingAlert)
- **Session Stats** — new "Session" data text: session time, kills (kill-blow credit), gold earned, deaths; tooltip with details, click resets the session
- **Fishing data text** — "Fishing" slot: current fishing skill (rank/max) plus remaining lure time on the weapon (temporary enchant); tooltip tracks skill-ups this session
- **Auction House suite** (`Modules/AuctionHouse/`, module disabled by default — opt-in via Modules) — Auctionator-style "S-AH" tab on the Blizzard auction house with three sub-tabs: **Shopping** (named shopping lists stored account-wide, sequential list searches at AH query pace, merged results sorted by unit price, item tooltips, buy with stale-entry verification), **Selling** (bag item list, competition query on selection, undercut-aware price suggestion from lowest competitor or scan DB, duration 12/24/48h, deposit via `GetAuctionDeposit`, **multisell stack size/count** via `PostAuction(bid, stackBuyout, dur, stackSize, numStacks)` — verified against Auctionator's legacy-AH selling path, posting history shown as "last posted" hint), **Cancelling** (own auctions with bid/buyout/time-left, undercut marker, sold flag, verified cancel, **live undercut check** button that queries each owned item sequentially, **mass-cancel button** that chains through all undercut rows until none remain) — plus a **Full Scan** button that digests the entire AH in chunks (no freeze) into a per-realm/faction price DB that also feeds the PriceHistory tooltip. **Auctionator-compatible import/export** (`ListName^item^item` per line, both directions) via a shared multi-line text dialog, and a **recent-searches strip** in the Shopping tab (click to re-run)

### Fixed
- **ADDON_ACTION_BLOCKED on movers in combat** — mover frames anchored to secure bars (e.g. action-bar movers) inherit protected status, so `RefreshMovers`/`PositionMover` calls from scale events during combat threw `SentinelUIMover_bar3:ClearAllPoints()` errors; protected movers are now deferred to the next out-of-combat tick
- **Enemy Radar now off by default** — the "Enemy detected" chat alerts annoyed more than they helped; enable via Modules if wanted
- **Raid Marker bar now off by default** — enable via Modules if wanted
- **Navigator follows the quest chain after arrival** — reaching a multi-spawn pick now activates the NEXT pick of the same chain in order instead of jumping to whatever waypoint is closest globally (old behaviour sent players on detours to unrelated waypoints)
- **Dead aura calls across 10 modules** — the global `UnitAura` is removed on this client; SelfBuffs (the one logged error), AuraWatcher, HunterTools, BGTools, PurgeAlert, BanishTimer, ExternalBuffs, FearWard, ProcAlert and SoulstoneTracker all called it and silently failed. New `S.UnitAura` compat returns the legacy tuple shape on top of `S.GetAura`/`C_UnitAuras`, all call sites converted
- **LootBrowser crash on boss level** — boss data stores level as a list (`{15,24,32}`), the title compared it as a number (`attempt to compare number with table`); now takes the first list entry
- **Announcer window couldn't be closed** — the X button never got an OnClick handler (skinning is visuals only) and editboxes swallowed ESC; X now hides the window and ESC clears editbox focus before closing. Same audit: CraftQueue, DeathRecap, Loot History, ProfCooldowns, AltRoster, GroupBulletin and the WorldBuffs window were missing ESC support — all registered in `UISpecialFrames` now
- **Announcer channel selection was undiscoverable** — the channel button only cycled through built-in types on click and public channels were unreachable; it now opens a real dropdown listing Say/Party/Raid/RW/Guild/Yell **plus every channel the player has joined** (General, Trade, World, customs), with "Custom..." keeping the free-text fallback; labels localized
- **Guild window showed "0 members"** — roster queries were fired from multiple modules on login bursts and every guild system message; the server throttled them and Blizzard's own request on frame open got eaten. `S.GuildRoster` is now coalesced (4s window, `force` escape hatch), GuildChronicle no longer flips the offline filter while the frame is open, and an empty roster on `GuildFrame` show triggers a forced refresh
- **Nav arrow kept resetting to the focused quest's target** — every quest-log refresh re-added the pick waypoints (distance-sorted key changed while moving), stacking stale duplicates that hijacked the arrow; the nav set is now tracked by reference, only re-installed once consumed, and dropped on unfocus/quest removal
- **R-key whisper reply dead with Messenger intercept** — the whisper filter suppressed the event before Blizzard could register the last teller, so the native reply had no target; incoming whispers now call `ChatEdit_SetLastTellTarget` themselves, the reply hook covers more entry points, and R focuses the messenger reply box even when the window is already open
- **Flight Timer never ended on classic taxi rides** — `PLAYER_CONTROL_GAINED` does not fire on legacy flights and the `UNIT_FLAGS` fallback bound the wrong argument, so the bar stayed up after landing; the tracker now polls `UnitOnTaxi` once airborne
- **More combat-safety on movers** — shift-click hide and handle-drag now respect protected movers (unit frames, secure bars) instead of throwing ADDON_ACTION_BLOCKED mid-combat
- **UI scattered after fullscreen/windowed switch** — the client reports transient `UIParent` scales during display-mode transitions; the scale event handler adopted them as the user's permanent scale (autoScale off, uiScale = mid-transition value), leaving every element wrongly positioned until manual fix. External scales are now only adopted once stable (0.4 s settle re-check) and `DISPLAY_SIZE_CHANGED` waits longer before re-applying
- **Audit: nil-API captures across modules** — `local X = X` snapshots of globals removed on this client (GetSpellInfo, IsSpellKnown, GetItemInfoInstant, UnitAura, UnitDebuff, UnitThreatSituation) made whole modules crash or silently dead: Decurse, MageBar, ProcAlert, Trainer, RaidCheck now bind the `S.*` compat variants; BossWatch range radar, RaidGrid aggro dot, UnitFrames threat glow and Nameplates threat coloring guard the calls; `S.GetAura`/`S.GetMouseFocus`/`S.GetContainerItemInfo`/`S.GetNumOnlineFriends` fallbacks are now nil-safe when both APIs are gone
- **Navigation audit** — removing the active waypoint via pin right-click left the arrow tracking a deleted "ghost" waypoint; `RemoveWaypoint`/`ClearWaypoints` now drop the arrow too. Corpse waypoints piled up on every death — previous corpse markers are replaced now. Unguarded `C_Map`/`wmf:GetMapID` calls nil-safe. Load-on-demand safety: the world-map/quest-log hooks retry on `ADDON_LOADED` (Blizzard_WorldMap/Blizzard_QuestLog) so pins/coords/route/click-create work even when the frames load late. Leftover arrow-math debug prints removed from chat

## [1.2.0]

### Added
- **Outfit bar docked into the bottom dock** — BetterItem outfit icons now sit directly inside the SentinelUI bottom bar (right of the left data panel): click an icon to equip the set; the bar auto-extends sideways per outfit, the active set stays saturated while others are desaturated, and it hides itself when no outfit is selected/exists. Falls back to the old free-floating draggable bar whenever the dock does not exist
- **Per-outfit bar selection** — each row in the character-frame outfit panel carries a checkbox ("Outfit-Leiste anzeigen"); unchecked outfits are hidden from the bar (`db.outfitBarSel`), default = shown, applies to already-saved outfits
- **Threat Meter** (module toggle, movable) — Omen-style threat list for the current target: top threat holders of the group (players + pets, shown as "Pet (Owner)") as class-colored or threat-status-colored bars with raw threat %, the tank marked with `*`, your own row highlighted. Auto-hides without a hostile target or group/pet. Options: max bars, width, bar height, pets, class colors
- **Inspect enchants/gems overlay** — the inspect paperdoll now marks every enchantable slot that has no enchant with a red `!` and shows tiny gem icons for every socketed gem (parsed straight from the inspected unit's item links, refreshed on `INSPECT_READY`)

### Fixed
- **DataTexts minimum spacing** — slots can no longer shrink below text width + gap; long panels overflow sideways instead of collapsing items into each other
- **Group Bulletin rows invisible** — the real cause: row frames were children of the FauxScrollFrame, which `FauxScrollFrame_Update` hides whenever the list fits on one page (7 ≤ 10 → all rows hidden while the pager still counted "7 Einträge"). Rows are now siblings of the scroll frame like Blizzard's own lists, a scroll child is set so >10 entries can't break the fill, and a 30 s ticker prunes expired entries while the board stays open
- **Navigator distances** — HereBeDragons-2.0 is embedded as a standalone library (its own map transform data, no Questie dependency); distances are real yards again instead of mixed coordinate-space fantasy values, and bearings are verified against world coordinates
- **Navigator arrow direction** — `GetPlayerFacing` on this client counts counter-clockwise (verified via HereBeDragons-Pins math): the arrow uses `bearing + facing` again (conv=1), stale test settings are migrated once
- **Waypoint hops across picks** — QuestScope's silent queue candidates (spawn cluster 2/n, 3/n…) no longer steal the arrow; only the primary/nearest pick activates, queued points wait their turn
- **Navigator pins/route on mismatched map IDs** — stored waypoint map IDs are translated onto the currently displayed map via `TranslateZoneCoordinates` (e.g. DB map 1436 vs. shown 1453), so SentinelUI pins and the dashed cyan route render on zone and continent maps; the route falls back to a bearing projection when the target lies off-map
- **Self-buff reminder icons** — `SpellName` returned only the name, so the icon was always `?`; spell info now resolves name+icon (modern + legacy API) with fixed texture-path fallbacks per buff group — and the fix landed in the correct module (`SelfBuffs.lua`)

## [1.1.0]

### Changed
- **Quest data merged into the addon** — `SentinelUI_QuestData` is no longer a separate addon: all per-client quest databases (`Modules/QuestScope/Data_<flavor>.lua`, interface-guarded so only the matching client builds its dataset) ship inside SentinelUI itself. QuestScope is now **off by default** (per-character module toggle); turn it on under Module → Quest Scope
- **Loot data merged into the addon** — `SentinelUI_LootData` is no longer required: all loot tables (`Modules/LootData/`: Vanilla, TBC, Wrath, SoD + sources + deDE/esES/frFR/ruRU locales) ship inside SentinelUI, so the LootBrowser works even if the data addon was never enabled
- **Loot browser layout/robustness fixes** — source-index handles alias/multi-source/profession entries, version dropdown syncs with the actually loaded dataset and filters to client-relevant expansions, price tokens resolve to localized currency/item names, minimap glyph is `LB`
- **Button Bars now collect SentinelUI's own minimap buttons by default** — `collectSUI` defaults to true on every profile, so module buttons (Q, LB, B, I…) sit in the hide menu consistently across all characters and accounts (option: Button Bars → collect SentinelUI buttons)

### Added
- **Navigator route lines** — a cyan direction line runs from the player to the active waypoint: on the world map (live-tracked while the map stays open, active pin highlighted larger/cyan) and on the minimap (center → edge pin, respects `rotateMinimap`)
- **QuestScope data (in-addon)** — per-client quest databases generated offline by `SentinelUI-Tools/gen_quest_data.py` — Vanilla/Era (4.2k quests), TBC (6.6k), Wrath (9.1k), Cata (15k), MoP (17.6k) and Forever — including localized quest/NPC/item/object names in **deDE, frFR, esES and ruRU** plus per-flavor zone/sub-zone maps and **126–130 dungeon entrances** per client (with alt/floor-area mapping and faction-gated entrances)
- **QuestScope Journey** (`/suiqs journey`) — quest browser window: all quests of the client database browsable by zone with per-zone counts, live search, level/difficulty display, completion (✓) and in-log (◆) markers, quest-text tooltip, click = waypoint to the quest giver. Opens on the player's current zone
- **QuestScope side tracker** — own quest tracker (replaces the Blizzard watch frame, toggleable): all quest-log quests zone-grouped with collapsible zone headers, difficulty-colored titles, live objective progress, "ready for turn-in" state, secure quest-item buttons, optional distance display behind quest names, sortable (quest log / level / proximity), scrollable with a max-height limit. Right-click sets a **focus quest** — its nearest objective pin becomes the auto-waypoint and follows objective progress. Movable via the mover system, width/font configurable
- **Dungeon quest pins** — objectives and quest givers inside instances now pin the dungeon entrance on the parent outdoor zone (incl. multi-floor instances via alt-area resolution and Horde/Alliance-specific entrances)
- **Quest completion announce** — chat line + sound when an objective finishes and when a quest completes (option: Quest Scope → Announce)
- **Item tooltips: drop source** — quest-relevant items list up to 3 NPC names that drop them (localized)
- **Auto accept / turn-in** — quests are accepted and completed automatically: quest-detail, greeting and gossip dialogs all handled, rewards auto-collected only when there is no choice to make. Hold **Shift** to bypass for one dialog; both toggles under Quest Scope → Auto Accept / Auto Turn In
- **World-map pin clustering** — markers within ~2.5% radius merge into one pin with a count badge (Questie-style); the tooltip lists every quest in the cluster, the icon shows the most relevant type
- **Dungeon entrance markers** — standalone portal icons on the world map for all 126–130 instances per client (faction-filtered, named via GetAreaInfo)
- **Quest chains in Journey** — quest tooltips show *Requires:* (green = done, red = open prerequisites) and *Continues with:* from the chain data; a live **Quest Log** pseudo-zone on top lists active quests
- **Journey detail pane** — clicking a quest selects it and opens a detail column on the right: difficulty-colored title, zone, status (completed/in log), objective text, live objective progress for log quests, *Given by:* / *Turn in at:* (NPCs, objects, starter items — localized), chain requirements and continuation. *Waypoint* button navigates to the quest giver, *Track* focuses the quest in the tracker
- **Quest levels in NPC dialogs** — gossip and quest-greeting lists show `[level]` in front of quest names (matched against the DB by localized or english name); quest detail/progress/complete frame titles get the level prefix too
- **Questie users marked in party progress** — objective tooltip lines now prefix progress coming over the Questie protocol with a small gray `Q`, so SentinelUI-synced and Questie-synced group members are distinguishable
- **Chain warning on quest abandon** — when the abandon confirmation pops up for a quest that has prerequisites or a continuation, a chat warning shows the next quest in the chain before you confirm
- **BiS markers on quest rewards** — reward buttons in the quest-complete picker and quest log detail get a gold star when the reward item is listed as best-in-slot for the player's own class and spec (any phase), hooked into `QuestInfo_Display`/`QUEST_ITEM_UPDATE`
- **Loot Browser** (`/suiloot`, minimap "LB" button) — standalone AtlasLoot-style loot browser powered by the new **SentinelUI_LootData** companion addon (generated offline by `SentinelUI-Tools/gen_loot_data.py`, no runtime dependency on any other addon). Browse every dungeon, raid, faction, PvP set, profession, collection, vendor and world-event loot table across Classic/SoD/TBC/Wrath — 295 contents and ~43k item entries for TBC alone, including all TBC phase/BiS modules. Per-boss difficulty tabs (Normal/Heroic/phase/gear-type), item grid with live-cached icons and quality-colored names, drop chances (npc→item%), vendor prices, Alliance/Horde variants, search filter, pagination, Shift-click to link / Ctrl-click dress-up. Instance names resolve via `C_Map.GetAreaInfo` (auto-localized), boss/category/item names via the generated deDE/frFR/esES/ruRU locale tables
- **Item tooltips: loot source** — any item tooltip now shows where it drops ("Karazhan - Prince Malchezaar (14.2%)") or which profession crafts it, from the generated source database (~13.5k items). Toggle: Loot Browser → Tooltip Source
- **Druid mana bar in shapeshift forms** — a slim mana strip sits under the player-frame power bar and appears only while in bear/cat form (rage/energy shown, mana hidden otherwise) — relevant for powershifting and mid-fight healing
- **Power-bar text on unit frames** — the mana/rage/energy bar can now display its value in a selectable format. New *Text Format* dropdown per unit (Unit Frames → &lt;unit&gt; → Power): None / Percent / Current / Current / Max / **Current - Percent** / Deficit / Custom (free tag string, all `[…]` tags still work). Defaults: player & target show *Current - Percent* ("3500 - 75%"), focus/pet/party/boss/arena show *Percent*; raid frames stay text-free. Existing profiles inherit the new default unless a custom text was already set
- **Pull timer** (`/pull <1-60>`, `/pt`, `/pull cancel`) — countdown bar with mover plus one group chat line at start; party/raid members running SentinelUI get the bar and cancel state synced via addon messages, everyone else still sees the chat line (option: Pull Timer → default seconds / chat announce)
- **Automatic screenshots** — delayed `Screenshot()` on level up, achievement earned and raid/world boss kills (~180 boss NPC ids across Vanilla–Wrath raids plus a live `bossN` unit check as fallback), so the ding/kill moment is actually in the frame (per-trigger toggles + delay under Screenshots)
- **Mana tick bar** (healer QoL) — five-second-rule countdown after spending mana (red), then the 2 s spirit-tick cycle synced to observed regen events (blue), with an optional moving spark. Auto-hidden on pure rage/energy classes and while shapeshifted (the druid mana strip covers that case); movable via the mover system
- **Swing timer** — auto-attack countdown for main-hand melee and hunter ranged; for hunters the last 0.5 s of the bar is tinted red as the hard-cast clip window (Aimed/Steady would push the auto shot). Height and text toggle under Swing Timer, movable via mover
- **Summon helper** (warlock) — Ritual of Summoning announcements to party/raid: who is being summoned, clicks needed, "stone is up" on completion and an interrupted-cast notice (RAID_WARNING in raids optional)
- **Profession cooldown tracker** (`/suipcd`, `/pcd`, `PC` minimap button) — tracks long per-character profession cooldowns: alchemy transmutes (TBC + Wrath ids), primal/moonshroud/spellweave/ebonweave cloth, Void Sphere, Icy Prism, Brilliant Glass, Titansteel, Arcanite transmute and the Salt Shaker item cooldown. Window lists remaining times (ready entries in green), chat note when a cooldown expires, stored per character
- **Zeppelin/ship ETA** — boarding is detected via the vessel name shown as zone text (all Vanilla/Wrath-era boats and zeppelins, en+de names); every completed trip stores its duration per vessel account-wide, so the next crossing shows an ETA countdown bar (movable), chat note on each recorded trip
- **Keybind mode now covers Blizzard bars too** — `/sui kb` already drove the SUI action buttons; native `ActionButton`/`MultiBar`/`BonusActionButton` frames now get the same hover-bind behavior, and binding always resolves the live `bindCommand` instead of a stale field
- **Raid marker bar** — movable strip with all 8 raid target icons plus a clear button; click marks the current target. Shown in groups (option to always show); works with `SetRaidTarget`/`SetRaidTargetIcon` on every client
- **Mail "Open All"** — button on the inbox collects money + attachments top-down with server-friendly pacing; COD mails and plain letters are skipped, collected gold is summarized in chat. On clients that already ship a native Open-All button, that button is skinned and reused instead of stacking a duplicate
- **Class counters** — movable icon+count strip for class consumables: hunter ammo (incl. thrown), warlock soul shards, mage arcane powder/teleport/portal runes, priest candles, paladin symbols, druid quillvine/thornroot/ironwood, shaman ankh. Counts turn red below a per-item low threshold
- **Execute alert** — pulsing red border on the target frame (plus optional sound) when the target enters execute range: warrior/paladin 20% everywhere; hunter Kill Shot, warlock Drain Soul and priest SW:Death bonus on Wrath+ only
- **Energy tick on the mana-tick bar** — rogues and cat-form druids get the same 2 s tick countdown in energy-yellow (mana rules still apply for mana users); the bar auto-switches by active power type and now hides itself when the resource is full out of combat (10 s parked = OnUpdate fully stopped)
- **Range display** — estimated distance text under the target frame ("0-10 yd" … "40+"): friendly units via `CheckInteractDistance`/`UnitInRange` bands, hostiles via a per-class baseline spell reach
- **Pet happiness** (hunter) — color-tinted icon next to the pet frame (red/yellow/green) with a tooltip showing the damage modifier (75/100/125%)
- **Enemy radar** — Spy-style combat-log watch for hostile player actions: name, class and level in chat plus an optional sound and a brief red screen flash; per-enemy repeat cooldown, cleared when the enemy dies
- **Gather notes** — herb/ore/skinning node positions are recorded on every successful gather cast (account-wide, merged within ~2 % map distance) and drawn as small icons on the world map
- **Cooldown tracker** — movable icon row listing the player's known major cooldowns (per-class spell sets, talents included); icons only appear while actually on cooldown, with swipe + countdown text
- **Diminishing returns tracker** — CC auras on the target render as icon row under the target frame with color-coded potency (green 100% → red IMMUNE) across the TBC DR categories (fear/horror, stun, disorient, root, banish, cyclone, disarm, sleep), 15 s window
- **Potion reminder** — below a configurable health threshold a flashing, click-to-use secure button appears whenever a healing potion or healthstone sits in the bags and is off cooldown (mover + threshold slider)
- **Automatic combat logging** — `LoggingCombat` turns on inside raid instances (optionally 5-mans) so logs land in `Logs/` for upload tools; turns back off when leaving, only touching logging it started itself
- **Group bulletin** (`/suilfg`, `GF` minimap button) — "LFG Group Bulletin Board"-style window: parses the LookingForGroup/SucheNachGruppe channel (and optionally LFM/LFG-looking messages elsewhere) into a browsable, paged list with name, message, channel and age; click whispers the poster, entries expire after 10 min
- **PvP trinket tracker** — enemy players using their PvP trinket (42292, plus Every Man/Will of the Forsaken on newer clients) get a 120 s cooldown icon docked above the matching target/focus/arena frame
- **Timer & stopwatch** — `/suitimer mm:ss` (alias `/timer` where the client lacks it) shows a movable countdown bar ending in an alarm sound; `/suisw` (alias `/sw`) is the stopwatch
- **Auto accept** — resurrections and summon dialogs from party/raid/guild members are accepted automatically (per-type toggles, out-of-combat only, group-invite auto-accept off by default); a chat note names who got auto-accepted
- **Disenchant info** — item tooltips show the likely disenchant result based on item level, quality and weapon-vs-armor weighting: dusts/essences/shards for greens, shards for blues, Nexus/Void crystals for epics (TBC-era result tables, deDE names included)
- **Craft queue** — "Mats" button on the professions/tradeskill frame opens a reagent list for the selected recipe with have/need counts from your bags; missing materials show red. Works with both `GetTradeSkill*` and `C_TradeSkillUI` APIs
- **Vendor restock reminder** — the class counters module now prints a note when you open a merchant while a tracked reagent (candles, symbols, ankh, shards…) is below its low threshold
- **BG tools** — Warsong Gulch flag carrier tracking: a movable frame lists who holds each flag (class-colored names via nameplate/raid aura scanning, locale-independent), pickups announced in chat; only visible inside battlegrounds
- **Map info** — the world map now shows the recommended level range and minimum fishing skill of the viewed zone (Kalimdor, Eastern Kingdoms, TBC starter zones and Outland)
- **Auto-sell junk** — Misc gained an optional `autoSell` toggle (off by default): all poor-quality items are sold on merchant open with a chat note of the earnings
- **Reputation auto-watch** — the XP/reputation bar now automatically tracks whichever faction last gained reputation (Reputation options, `autoWatch`)
- **Persistent max camera** — `cameraDistanceMaxZoomFactor` is now applied by Misc on every login, not only during the install wizard
- **Bar captions** — the mid-screen combat bars (swing timer, mana/energy tick, timer) now carry a small title above the bar so anonymous countdowns are identifiable at a glance; the potion reminder icon got a caption as well

### Fixed

- **Quest Navigator distance/direction** — the client lacks `C_Map.GetMapPosFromWorldPos`/`GetMapWorldSize`, so every previous path fell back to mixing `UnitPosition` with `GetWorldPosFromMapPos` (different coordinate spaces → fantasy yards and wrong bearings). The navigator now uses vendored **HereBeDragons-2.0** (BSD-licensed standalone lib, no Questie runtime dependency) whose mapData transforms provide proven yard-accurate vectors across zones and sub-maps; the old math remains only as fallback
- **Potion reminder combat taint** — neither the secure button nor a holder containing it may be hidden in combat (`ADDON_ACTION_BLOCKED`); the reminder now stays permanently shown and emulates visibility via alpha (unrestricted) plus a mouse-enabled cover frame that eats stray clicks while logically hidden, and the item attribute is only re-assigned out of combat
- **Localization gaps** — profession cooldown names are now resolved through the client's own spell/item APIs (localized names instead of hardcoded English); `5SR`, the bulletin age suffix and nine loose strings went through `L[]`/deDE. Full audit: every `L[...]` key outside BetterItem now has a deDE entry
- **Range display garbled text** — stale fontstrings could stack on a rebuilt unit frame and render overlapping glyphs ("130+±ydd"); stale texts are now cleared before creating a new one, and the hostile spell range check falls back to the localized spell name for clients that don't accept ids
- **Range display toggle** — the module gained a real `enable` switch plus the existing target/focus show toggles; disabling now actually stops the update loop and clears the texts instead of just hiding them silently
- **Fast loot** — loots all slots the instant `LOOT_READY` fires, before the loot window renders; honors the autoloot modifier unless `always` is enabled
- **Death recap** — ring buffer of the last damage events on the player; on death a small window shows "what killed me" plus a report-to-group button
- **Proc alert** — flashing icon when proc buffs appear (Clearcasting, Omen of Clarity, Shadow Trance, Surge of Light, Killing Machine…) or proc-usable spells light up (Overpower, Revenge, Riposte, Kill Command), per-class tables, movable
- **Weapon buff reminder** — flashing icon when a melee/shaman/rogue weapon lacks its temporary enchant (poisons/imbues/oils), warns when it expires within 5 minutes; `allClasses` option
- **Spam filter** — blocks gold-seller/advertising patterns in whispers and public channels via `ChatFrame_AddMessageEventFilter`; friends, guild and group members always pass, optional chat note
- **Interrupt tracker** — enemy player interrupt casts (Kick, Pummel, Counterspell, Earth Shock, Spell Lock, Silence, Mind Freeze…) appear as cooldown icons on a movable row
- **Alt roster** — `/suiroster` or `AR` minimap button lists every character on the account with class-colored name, level, gold and guild; saved automatically per login
- **Hunter feed reminder** — unhappy pets now flash the happiness icon and print one "feed it" note per mood drop
- **Reagent auto-buy** — the counters module can optionally buy tracked reagents back up to target amount at vendors (`autoBuy`, off by default)
- **LFG + XP rate datatexts** — new `LFG` text shows live group-bulletin entries (click opens the bulletin); `XP Rate` shows XP/hour with progress, rested and time-to-level in the tooltip
- **Loot filter** — chat loot spam reducer: hides item loot messages below a configurable quality threshold and can hide coin-only messages too
- **Rez announcer** — announces your own resurrections to party/raid ("Resurrecting X") and notes who rezzed you; covers priest/paladin/shaman/druid rez spell ids across expansions
- **Fear Ward tracker** (priest) — icon + remaining duration next to the target frame whenever Fear Ward sits on your target/focus/party member
- **Cooldown tracker trinkets** — equipped trinkets with a use-effect now appear in the tracker row while on cooldown (`trinkets` option)
- **BG queue datatext** — new `BG Queue` text shows the queued battleground and ETA, click opens the PvP frame
- **Self-buff reminders** — desaturated icon row warns about missing class self-buffs: mage armors, Inner Fire, demon/fel armor, lightning/water shield, thorns (paladins/rogues covered by Blessings/WeaponBuff)
- **Keyword invite** — guild/friends whispering "inv"/"invite"/"einladen" (configurable list) get auto-invited, others get an optional polite denial
- **Hunter tools** — low-ammo warning (throttled chat + sound, configurable threshold) and an Aspect of the Cheetah/Pack warning when entering combat
- **Group bulletin board rework** — replaced paging with a real scrollbar (10 rows, taller window), names resolve class colors via guild/friends/group plus a throttled /who lookup, right-click invites, and seller/shop spam (WTS/WTB/vk/shop/boost/gdkp…) is filtered out entirely
- **CC break announcer** — reports who broke sheep/trap/sap/hibernate/repentance/seduce/gouge/wyvern/scatter, attributed from the last damage event before the aura dropped (self or party channel)
- **Taunt resist warning** — chat + sound when a taunt/mock ability misses (all warrior/druid/paladin/DK taunt ranks across expansions)
- **Aggro alert** — screen flash + sound + chat when you gain aggro (threat status 3), for dps and healers
- **Purge alert** — magic buffs on the enemy target shown as highlighted icons (mage/priest/shaman/warlock/hunter)
- **Soulstone tracker** — movable list of raid members carrying a soulstone buff (Wrath+); on TBC where stones are items, it announces stone consumption from the combat log
- **Target counter** — "N targeting you" counter above the player frame, counted over nameplate/boss/arena/party-target units
- **Enemy cast announce** — prints when a hostile unit starts a CC spell or heal (dedup per caster), self-chat only
- **BoP warning** — reminder when a loot roll offers a bind-on-pickup item
- **Banish timer** (warlock) — icon + remaining duration while your Banish sits on target/focus
- **External buffs tracker** — movable list of group members carrying Misdirection, Power Infusion, Earth Shield, paladin hands (Sacrifice/Freedom/Protection/Salvation), Pain Suppression, Guardian Spirit or Innervate, with class-colored names and remaining time
- **Flight timer** — movable ETA bar while on taxi; learns per-route durations (global store), first ride on a route shows elapsed time
- **BoP auto-confirm** — optional auto-accept of bind-on-pickup/equip/use dialogs (`autoConfirm`, default OFF — it soulbinds items!)
- **Interrupt tracker nameplate anchoring** — interrupt cooldown icons can attach directly above the caster's nameplate (`anchorPlates`, default on)
- **LFG browser right-click** — inside Blizzard's own group finder (`Blizzard_GroupFinder_VanillaStyle`): right click a listing row whispers that player, shift+right click invites them (module: LFG Enhance)

### Fixed
- **LFG browser controls broke under the skin** — Blizzard's group finder (`LFGListingFrame`/`LFGBrowseFrame`) was deep-skinned like every other window; its activity-view scrollbar is documented to taint on this client, which silently killed category/tab/role buttons. LFG frames now get the window skin only (`noChildren`) and keep Blizzard's native controls
- **Group bulletin could render empty** — a single bad row (secret name/class values or stale pre-rework entries) killed the whole fill loop while the "N entries" counter stayed stale; rows now fill in isolation, secret values render uncolored, `FauxScrollFrame_GetOffset` is guarded
- **Buff reminder kept showing the question-mark icon** — the resolved `iconID` arrives as a secret value on this client and was rejected; icon resolution now retries every update across `C_Spell.GetSpellTexture` and classic `GetSpellInfo`, with secret-guards on both the stored and the init path
- **Navigation distance AND bearing were wrong** — the arrow computed yards from `UnitPosition` vs `GetWorldPosFromMapPos`, which do not share a coordinate space on every client (inflated values and a wrong-way arrow). The arrow now converts the player's world position into the waypoint's own map (`C_Map.GetMapPosFromWorldPos`) and measures in that map's units × `GetMapWorldSize` — one consistent space for same-zone and cross-zone waypoints; old paths remain only as fallbacks
- **BiS browser showed question marks for uncached items** — `GetItemInfoInstant` only serves the local item cache; the single 0.5 s retry missed nearly every server fetch. Icons now try every cache API (`GetItemInfoInstant`, `C_Item.GetItemIconByID`, classic `GetItemIcon`), fetch via the modern `Item:CreateFromItemID:ContinueOnItemLoad` mixin (classic fallback: `GetItemInfo` + `GET_ITEM_INFO_RECEIVED` watcher) and poll up to 5 s per item
- **BiS header buttons overlapped the phase dropdown** — Talents/Rotation/Consumables are right-anchored and collided with the phase picker; they now sit on their own row below the dropdowns. Same spacing fix applied to the dropdowns themselves (main browser + all three extras windows; consumes window widened to fit)
- **Spec detection broken on non-english clients** — `TreeToSpec` compared localized talent tab names ("Heilig", "Vergeltung") against english spec labels, so own-spec detection always fell back to index 1 (wrong spec shown, wrong BiS reward stars). Specs now match against english and localized names; all 22 spec labels translate (deDE: Heilig, Schutz, Vergeltung, …) in browser, extras windows, tooltips and the stats-cap header
- **Tracker context menu** — right-click a quest for a Questie-style menu: Focus + waypoint / open quest log / untrack
- **`/suiqs debug`** — diagnostic line showing which quest-log API the client exposes, log enumeration counts, data hits and pin counts
- **Party progress sync** — objective progress is broadcast to party/raid members running SentinelUI and shown in NPC and item tooltips ("<name>: 3/10"); roster changes prune stale members (option: Quest Scope → Party Sync)
- **Minimap pin clustering** — pins landing on the same spot merge into one marker with a count badge; the tooltip lists up to 5 contained objectives (option: Quest Scope → Cluster Minimap)
- **Journey global search** — typing in the search box searches the entire quest database across all zones (Questie advanced search style), matching localized and English names; dungeon entrances now also render on the minimap
- **Visual polish** — tracker gets hover highlights, a transparent backdrop (toggleable), accent divider lines and a skinned scroll bar; Journey gets a skinned search box, skinned scroll bars, selected-zone highlight, hover highlights, difficulty-colored level brackets and a title divider; the tracker context menu shows the quest title with hover-highlighted entries
- **Multi-waypoint navigation** — quest clicks now place up to 3 numbered waypoints (nearest first, current zone preferred); the nav arrow advances automatically on arrival. Option: Quest Scope → Multi Waypoints
- **NPC tooltips: exact objective progress** — hovering any NPC now lists every log quest it contributes to with live progress text ("Murloc Fin: 4/8"): direct monster kills, kill-credit NPCs (per-objective credit lists), item drop objectives and quest turn-in markers (`[?]` green when ready); multiple quests/objectives per NPC all show
- **Map pin progress** — hovering objective pins on the world map and minimap now shows the live objective progress line ("Wolf Pelt: 3/8") including party members' progress, filtered to the objective that specific pin stands for; clustered pins annotate each member
- **Item tooltip sources** — quest-relevant items now show *Sold by:* (vendor NPCs) and *Contained in:* (game objects) alongside *Drops from:*, and items that start quests display a `[!] Quest [level]` marker even before the quest is in the log. Shift-clicked items (ItemRefTooltip) get the same annotations
- **Object tooltips** — hovering quest game objects (crates, statues, wanted posters, herbs/ore nodes tied to quests) shows the same progress lines as NPC tooltips: interact objectives, item drops from objects, `!` for quests the object offers and `[?]` for turn-ins. Name resolution works in the client locale and English; hover-deduped via the tooltip's update hook
- **Questie interop** (`QuestieCompat`) — standalone implementation of the Questie addon-channel wire format (tagged-object stream, "1short" + "b89" encodings, AceComm multipart framing): objective progress syncs **both ways** between SentinelUI and Questie users in the same party/raid — their progress appears in our tooltips, ours appears in theirs (update/remove/full-log and log-request packets, whisper replies, roster-change rebroadcast). Roundtrip-verified byte-compatible against the reference implementation. Gated by the Party Sync option; degrades gracefully without Questie present
- **BiS Guide** (`/suibis`, `/bisguide`) — own best-in-slot database and guide, fully self-contained: data ships as generated ID-based tables (`Modules/BisGuide/Data_*.lua`, produced by `SentinelUI-Tools/gen_bis_data.py` from public game data; ~16.8k item entries). Features:
  - **Item tooltip annotations** — BiS rank per phase per spec, grouped by class with class colors and icons; your own spec is marked with `»`, the active phase highlighted; source and drop-chance line for the best entry. Tier tokens and crafting recipes resolve to the items they produce. Alt inverts the "own spec only" filter
  - **BiS browser** (`/suibis`) — class/spec/phase dropdowns, slot rows with the rank-1 enchant and gem icons plus up to 6 ranked item icons (#rank labels, tooltips on hover, Shift-click inserts links); green border = equipped by you, blue border = worn by the inspected player
  - **Consumables window** (`/suibis conso`) — best/alternative food, flasks and potions per spec
  - **Rotation window** (`/suibis rot`) — single-target and AoE priority lists with clickable spell icons
  - **BiS talents** (`/suibis tal`) — the three talent trees with named build suggestions rendered on the icons
  - **Inspect integration** — "BiS List" button on the inspect frame: detects the target's class/spec from talent points, opens the matching list and marks worn items
  - **Stats Cap panel** — side panel on the browser showing the relevant caps per spec role (spell/melee/ranged hit, expertise, defense, avoidance) plus your current values from gear, talents and racials
  - **Talent frame button** — "BiS Talents" button docked above the Blizzard talent frame
  - Options under `/sui` → BiS Guide (tooltip lines, source display, own-spec filter, inspect button, active phase)

### Changed
- **Classic quest-log compatibility** — enumeration, click index resolution, completion checks and objective state now fall back to `GetQuestLogTitle`/`GetQuestLogLeaderBoard`/`IsQuestComplete` when the `C_QuestLog` namespace is absent or partial (TBC Anniversary and older clients); modern `numRequired`/`objectID` field names are normalized
- **Tracker navigation** — clicking a quest now resolves waypoints through a fallback chain (live objective pins → finisher → starter, incl. item-drop starters), so every log quest can navigate even without built pins; auto-focus waypoints never re-set an identical target (kills the chat spam)
- **Tracker visuals** — Questie-like look: accent-colored collapsible zone headers, difficulty-colored `[level]` + white title, dimmed `- objective` lines, green ready state, gold `»` focus marker, scrollable with max-height and sort (log/level/proximity)
- **QuestScope pin icons** — removed the gray backing boxes; objectives now use distinct icons per type (skull = kill, bag = loot, gear = interact, bubble = other) next to the existing !/? markers
- **QuestScope data lookup** — sub-zone spawn data (caves, cities, starting areas) now resolves through the parent-zone chain instead of being dropped, so far more spawn points get markers
- Quest data moved out of the main addon into `SentinelUI_QuestData` (per-flavor files, interface-guarded fallback for exotic clients); each table is emitted in chunks under the Lua constant limit so every dataset compiles even on strict 5.1 parsers
- **Minimap button fix** — the `Q` button now registers with the standard onLeft/onRight/tooltip handlers (it was created with the wrong option keys and never appeared)
- **Minimap pin pool** — default raised to 80, configurable up to 150

### Fixed
- **Readable items & mail unreadable** — book/letter pages (readable books, quest-start letters) and open-mail text rendered black on the dark skin: Blizzard recolors `ItemTextPageText`/`OpenMailBodyText` (SimpleHTML/FontString) with dark parchment colors on every open, so the old one-time recolor never stuck. Now hooked per-widget — body text forced white, titles gold — surviving every reopen
- **Waypoint arrow pointed the wrong direction** — `UnitPosition` returns `posY` (west axis) first, `posX` (north) second, but Navigation/QuestScope read them as north/west: bearings came out axis-mirrored. Both modules now swap the returns correctly
- **QuestScope waypoint sorting compared wrong instance ids** — `PlayerWorld` returned the Z coordinate where callers expected the instance id, so every candidate measured as a foreign continent
- **Tracker click opened the wrong quest** — the stored quest-log index goes stale whenever the log changes; the index is now resolved fresh from the quest ID at click time
- **Waypoint picked the wrong zone** — navigation now prefers pins in the player's current zone; identical waypoint requests within 3 s are deduplicated
- Removed four stale pre-standalone data files left inside `Modules/QuestScope/` (~52 MB dead weight, unchunked and uncompilable — never loaded, now deleted)
- **Kill-credit objectives read the wrong data field** — pin building and NPC tooltips treated `objs[5]` as a flat npc list while it is actually `{objectiveIndex = {creditList, targetNpc, ...}}`; credit NPCs like multi-mob ambush quests now resolve to the right spawn points and tooltip matches
- **Quest tracker combat taint (second wave)** — a single `SecureActionButtonTemplate` quest-item button anchor-restricts the entire tracker hierarchy, so *every* `Show`/`Hide`/`SetPoint`/`SetSize` on rows, zone headers, the scroll child and the tracker frame itself was blocked in combat. `UpdateTracker` now refreshes only FontString texts during combat (rows keep their last layout, progress still updates live) and rebuilds on `PLAYER_REGEN_ENABLED`
- **BiS Guide: spec detection compared number with string** — `GetTalentTabInfo` points are coerced to numbers, fixing the error when opening the browser from the new minimap button
- **Race-gated quests shown for the wrong races** — QuestScope's availability check intersected the quest's race mask with *every race of the player's faction*, so e.g. a night elf saw human-only and draenei-only quests. The player's own race bit (`UnitRace` → `2^(raceID-1)`, faction mask only as fallback) is now used; class-gating stays `2^(classID-1)` — verified against the generated data layout
- **Loot browser offered the opposing faction's categories** — the generated `Alliance`/`Horde` categories (Honor Hold/Kurenai vs. Thrallmar/Mag'har/Tranquillien on TBC, same on Wrath) are now filtered by `S.myFaction`, and a stale selection is moved to the first visible category
- **Loot browser init crash** — the version-resolution helper ran before the `sel` local existed and wrote into WoW's global `sel` string, aborting `Initialize` (no minimap button); declaration order fixed, `ContinueOnItemLoad` guarded
- **Decurse: disease marked dispellable without a cure on TBC** — spell 526 is "Cure Toxins" (poison+disease) on Classic Era/SoD but plain "Cure Poison" on TBC+; its debuff-type mask is now client-gated
- **Buff reminder nagged permanently on paladin/shaman/hunter** — mutually exclusive buffs (one blessing, one shield, one aspect at a time) were split into separate required groups, so one group always reported "missing". They are merged into one group each; the hunter list also contained a shaman spell id and is completed (Cheetah/Pack/Beast/Wild/Viper, greater blessings, Sanctuary)
- **Trainer race filter only checked two entries** — `races` lists are now scanned completely instead of only index 1–2
- **RaidGrid dispel binding pointed at a mage spell** — `DISPEL_SPELLS.DRUID` listed 475 (mage Remove Curse); a druid who had not learned Cure Poison yet got no dispel click. Fixed to 2782 (druid Remove Curse), and shaman gained 51886 (Cleanse Spirit) for Wrath clients
- **Loot skinning crashed on every loot** — the `LOOT_SLOT_CHANGED` handler read its first parameter as the slot, but module event handlers are invoked as `(module, event, args…)`, so `slot` held the event-name string; signature corrected and the payload still coerced with `tonumber` as a safety net
- **Dead addon-channel + whisper handlers** — the same `(module, event, args…)` off-by-one silently killed three more handlers: BossWatch's busy-whisper reply and its DBM/BigWigs pull-timer interop, and QuestScope's whole party progress sync (SUI↔SUI *and* the Questie wire bridge never fired, since `prefix` compared against the event name). All signatures corrected — party sync and the Questie bridge are live now
- **Slider and scrollbar thumbs invisible everywhere** — `SkinSlider`/`SkinScrollBar` strip all template regions (`SetAlpha(0)`), which also killed the thumb texture; the recolor never restored it. Thumbs now get `SetAlpha(1)` — every slider in options and every skinned scrollbar shows its handle again
- **Inbox rows looked empty** — mail list sender/subject/days fonts use parchment-dark colors meant for the paper background the skin removes; they are now recolored to the light text color and re-applied on every `InboxFrame_Update`/`MailFrame_Update`/`InboxUpdateItems` (covers both `MailItemN` and `InboxItemN` naming). Added a one-shot `mail` diagnostic line on first MAIL_SHOW logging row visibility, subject text and font color
- **Duplicate module icons on the minimap rim** — `S:CreateMinimapButton` was not idempotent: modules that created their launcher again (re-init, option toggles) stacked a second identical frame on the rim. The factory now reuses the existing button and refreshes its handlers/store/glyph — a second call can never produce a twin. `LayoutMinimapButtons`/`UpdatePosition` also skip buttons that were collected into a ButtonBars bar, so collected entries no longer occupy rim angles
- **Identical minimap button monograms** — several modules shared one letter and looked like duplicates. All module glyphs are now two-letter and unique: `QS` QuestScope, `LB` LootBrowser, `BG` BisGuide, `BF` BugFolder, `BI` BetterItem, `IT` InstanceTracker, `SL` SeeLast, `HP` HealerProtection, `RE` Reputation, `RR` RaidReset, `RC` RaidCheck, `HG` Heal Grid, `MS` Messenger, `GC` Guild Chronicle, `AN` Announcer, `DC` Decurse, `SG` Blessings, `BW` Boss Watch

## [1.0.9]

### Added
- **QuestScope** (`/suiqs`, `/questscope` + `Q` minimap button) — quest helper in SentinelUI's own style, **fully self-contained**: the quest/NPC/object/item database ships inside SentinelUI as generated data tables (`Modules/QuestScope/*.lua`, produced by an offline generator in SentinelUI-Tools from public game data). No other addon is needed or referenced:
  - Available-quest markers on the world map + minimap: gold `!` (normal), gray `!` (trivial), blue `!` (repeatable), with level/race/class/faction/pre-quest filtering and completion checks
  - Quest-log objective markers (kill/item/object targets resolved to spawn coordinates, with objective text)
  - Turn-in (?) markers at the finisher for completed quests
  - Minimap projection with zone shapes (round/square edge clamping), distance fade and configurable view range
  - Tooltips: NPC tooltips show started quests + per-objective progress for that mob; item tooltips show which log quests need the item (with x/y progress)
  - Click a pin to drop a SentinelUI waypoint (Navigation integration)
  - Options under `/sui` → Quest Scope (map/minimap pins, trivial quests, turn-ins, tooltips, pin size, minimap distances/pool)

### Fixed
- **Bags stack overflow** — Blizzard's C `OpenBackpack` bounces back into the Lua `ToggleBackpack` global; the wrapper is now reentrancy-guarded (was a hard C stack overflow)
- **ButtonBars dock drag** — `StartMoving` can throw "Frame is not movable" under taint; wrapped in pcall
- **UnitFrames aura layout error** — `holder.spacing` fallback to `db.spacing`

## [1.0.8]

### Added
- **Objective tracker skin** — the quest tracker (`WatchFrame`/`QuestWatchFrame`/`ObjectiveTrackerFrame`) gets unified fonts, framed quest-item buttons and restyles itself after every Blizzard layout pass
- **Talking Head skin** — unified fonts on `TalkingHeadFrame` (load-on-demand `Blizzard_TalkingHeadUI`)
- **Nameplate target name** — every enemy plate shows who the mob is currently attacking: class-colored name under the health bar, updates on `UNIT_TARGET` and threat events (option `targetName`, on by default); pairs with the existing threat bar colors (tank: green = yours, DPS: red = yours)
- **BossWatch timer variance** — `t` accepts `{min, max}` and rolls a duration inside the window on every cast; converted the well-known variable cooldowns (Maiden Repentance, Moroes Vanish/Garrote, Aran Wreath/Blizzard, Nightbane Roar, Malchezaar ×3, Gruul Ground Slam, Mag Blast Nova, Leotheras WW, Vashj Static Charge, Kael Flame Strike)

### Fixed
- **Inspect talents never appeared** — the `ADDON_LOADED` handler read the event name instead of the addon name (SentinelUI handlers get `(owner, event, …)`), so the load-on-demand hook could never match; inspect talents and the player-talent setup now actually run
- **Player talents unusable** — the compact overlay is removed entirely: the player talent frame is native Blizzard again (branches, original buttons, spending points works), still styled by Skins
- **Talent frame bottom bar overlaps** — the bottom "Schließen" button is hidden (frame X closes), all stock buttons park right-aligned chained, the spent-points text uses the full row width and the full localized "Für X-Talente verteilte Punkte: N" format
- **Talent text showed "383: 0"** — `GetTalentTabInfo` returns `id` first on this client; the signature is now detected by type (also fixes the tab labels in the inspect talent view)
- **Talent bar crash** — `SetFormattedText` got a string points value (`tonumber` guard) and `SetFontObject` got a font path instead of a font object (now `S:SetFont`)
- **ActionButton `UpdateFlyout` nil-call spam** — Blizzard's global `UpdateFlyout` calls a missing helper on classic clients and fires from many paths; it is wrapped in `S:SafeCall` so the error is swallowed once
- **Inspect module font crash** killed its own setup mid-way, silently leaving hooks uninstalled

### Changed
- **Player talent frame stays native** — no more custom overlay on `PlayerTalentFrame`; the compact single-tree view remains for *inspect* only, where clicking is not needed

### Added
- **HealGrid** — healer-oriented group/raid grid (formerly RaidGrid): class-colored cells, mana bar, debuff icons with dispel-type border, HoT icons, ready-check, rez marker, role badge, raid target icon, aggro dot, range fade, buff watch, solo/party/raid mode, growth/sort/health-mode options, own draggable anchor instead of a title bar
- **HealGrid dedicated options window** (`/suirg options`, `/suihg`, right-click on minimap button or anchor) — all display toggles, size sliders (cell width/height, spacing, group spacing, scale), growth direction, sorting, health color mode, and the full click-cast editor; everything persists in `SentinelUIDB`
- **HealGrid click-casting** — unlimited bindings (modifier + mouse button + spell/macro/item/target/focus/menu); `heal` auto-resolves the class main heal, `dispel` the class dispel; per-binding spell picker lists every learned healing spell for all WoW healer classes (Priest, Paladin, Druid, Shaman, Monk, Evoker); defaults: left = target, right = heal
- **HealGrid incoming-heal preview** — green segment at the health edge for real heals, right-edge wedge at full HP showing the overheal amount; absorb shield as golden wedge
- **HealGrid rez-on-dead** — while a unit is dead every spell binding becomes the class resurrection (option `rezOnDead`); the dead-state swap re-applies secure attributes out of combat; `rez` is also a picker token
- **TotemForge** — full shaman totem suite: four element slots with element-colored borders on a movable bar, hover flyouts listing every known totem (click = cast & select, right-click = reorder), active totem icon + duration sweep + countdown, Totemic Call button, named totem sets (`/suitf save|apply|delete`), persistent order/selection/sets
- **Inspect talents** — redesigned to a compact single-tree view: tree tabs with spent points on top, scrollable tier×column icon grid, defaults to the most-spent tree
- **HealerProtection, Blessings, RaidCheck** modules carried over from the previous cycle
- **BossWatch** (`/bw`, `/bosswatch`) — encounter timers & warnings with an extensible combat-log rules engine (`Modules/BossWatch/Data.lua`): recast timer bars (movable stack, kind-colored, spell icon, counted casts), center-screen warnings with sound, pull & break timers (`/bw pull 10`, `/bw break 300`, `/bw timer 60 Name`, `/bw test`); pull timers interop with DBM via the `D4` prefix — ours are broadcast, theirs accepted; ships with a TBC raid dataset (Karazhan, Gruul, Magtheridon, SSC, TK, ZA highlights)
- **BossWatch fight tracking** — boss engage detection (boss units, raid targets, ENCOUNTER events on retail), kill/wipe announcements with fight duration and boss HP on wipe, persistent kill stats per boss (`/bw stats`)
- **BossWatch range radar** — `/bw range <yards>` lists group members in range (10/28/40y via interact/heal checks), `/bw range` toggles off
- **BossWatch whisper auto-reply** — replies "[SentinelUI] busy fighting <boss>" while a boss fight is running (option `autoReply`)
- **BossWatch rule flags** — `soon` ("X soon" pre-warning at 5s), `sayMe` ("/say <spell> on me!"), `track` (debuff carriers listed in the info frame)
- **BossWatch GTFO** — big "Move!" warning on environmental fire/lava damage (throttled, option `gtfo`)
- **BossWatch full raid dataset** — ~120 rules across Karazhan, Gruul, Magtheridon, SSC, TK, Zul'Aman, Hyjal, Black Temple, Sunwell, Molten Core, BWL, AQ40 and Naxxramas, each tagged with its zone
- **BossWatch per-rule options** (`/bw rules`) — scrollable window listing every known boss spell grouped by zone with an on/off checkbox per rule (`disabledRules` persists per profile)
- **BossWatch countdown audio** — pull/break timers beep on each of the last 5 seconds (option `countdownSounds`)
- **BossWatch nameplate icons + arrow** — tracked debuff carriers get the spell icon above their nameplate, and a rotating on-screen arrow points to the nearest carrier (options `nameplateIcons`, `arrow`)
- **BossWatch auto raid marks** — rules with `mark` set a raid target icon on debuff carriers and clear it when the aura fades (option `marks`); Living Bomb, Doom, Static Charge, Fatal Attraction, Frost Blast, Encapsulate, Conflagration mark by default
- **BossWatch raid-warning announces** — rules with `rw` broadcast "<boss>: <spell>!" to RAID_WARNING/PARTY
- **BossWatch screen flash** — `big` warnings flash the screen edges (option `flash`); `/pull` alias + BigWigs pull-timer interop (incoming "P^Pull^N" accepted, ours broadcast)
- **BossWatch SentinelUI sync** — own `SUIBW` addon prefix: pull timers and `/bw timer` shares propagate to other SentinelUI users in the group (DBM/BigWigs users via D4/BigWigs prefixes)
- **BossWatch bar announce** — shift-click a timer bar to post its remaining time to RAID_WARNING/PARTY
- **BossWatch warn throttle** — the same spell warns at most once every 3s, so multi-target aura hits can't flood the screen
- **BossWatch minimap button + own settings window** — `BW` monogram button (left = settings, right = boss rules), dedicated window with all toggles/sliders plus Rules & Test buttons; also reachable via `/bw` and the SentinelUI minimap submenu
- **BossWatch `/bw ver`** — version check: lists SentinelUI users in the group and their addon version (3s reply window, `SUIBW` prefix)
- **BossWatch boss-mod handshake** — announces itself as a boss mod via `D4` hello + BigWigs presence ping on group join, and answers DBM (`V`→`VE`) / BigWigs version checks so we show up in their "has boss mod" lists; incoming DBM `BT` and BigWigs `B^Break` break timers are accepted and `/bw break` is broadcast back
- **BossWatch phase engine** — rules can switch phases (`setPhase`), gate on phases (`phase = "P2"` or `"P1,P4"`) and auto-start timers on phase entry (`pfirst`); phase change clears active rule timers, resets cast counts and announces "Phase N"; wired for Illidan (P4 Shadow Demons, P5 Enrage), Kael'thas (P5 Gravity Lapse) and Anub'arak (P3 Leeching Swarm)
- **BossWatch WotLK dataset** — ~50 more rules for the Wrath path: Sartharion, Malygos, full Ulduar (Ignis…Algalon), ToC and the complete ICC wing (Marrowgar→Lich King incl. Defile/Infest/Frost Beacon) plus Halion
- **BossWatch dungeon dataset** — TBC heroic bosses added (Shadow Labyrinth, Sethekk, Steamvault, Shattered Halls, Blood Furnace, Auchenai Crypts, Arcatraz, Botanica, Mechanar, Black Morass, Underbog)

### Fixed
- **HealGrid heal preview could overflow the cell** — the preview is now a StatusBar anchored to both cell edges (no `SetSize` math), so it is structurally impossible to render outside the cell; secret values (12.x clients) are skipped entirely
- **Tooltip health bar reappearing** — Blizzard re-shows `GameTooltipStatusBar` after our unit hook; a `Show` hook now pins it hidden while `tooltip.healthBar` is off (default off)
- **HealGrid size sliders unusable** — `scale`/`barW`/`barH` had no slider range and fell back to `-500..500`
- **HealGrid errors invisible** — ticker/toggle are wrapped in `pcall` + `S:LogError`, cells show before painting
- **GuildChronicle `invalid capture index`** in the professions pattern, "Alle" filter button floating outside the professions bar
- **ActionBars click delay** — improved AnyDown/KeyDown responsiveness
- **Minimap buttons** — unified SentinelUI monogram/accent styling across all module buttons
- **Mail indicator** — now sits in the top-right corner next to the hamburger menu button instead of below the map

### Changed
- **RaidGrid renamed to HealGrid** (internal key `raidgrid` kept so saved settings survive); decursing is opt-in only — the dedicated Decurse module stays the primary decurse tool
- **Nameplates** — selectable style presets; **Gold datatext** — session/month/total earned + honor per day
- **AGENTS.md moved out of the addon folder** to `D:\WoW\` so no dev notes ship inside the Interface directory

## [1.0.6]

### Fixed
- **BetterItem: "too far away" error spam on hover** — `RequestInspect` now gates `NotifyInspect` behind `CheckInteractDistance(unit, 1)`; distant players are skipped until they're in inspect range; BetterItem 1.9.3

## [1.0.5]

### Fixed
- **BetterItem: inspected GearScore near-zero** — `GetInventoryItemLink` doesn't resolve for inspected units (needs locally-cached item data), so most slots counted as empty. Inspect gear is now captured as link *or* item ID (`GetInventoryItemID`); BetterItem 1.9.2

## [1.0.4]

### Changed
- **BetterItem: inspect cache instead of re-inspect** — inspected gear (slot→link table + class) is captured once at `INSPECT_READY`; stale entries recompute from the stored links instead of another `NotifyInspect`
- **BetterItem version source** — now read from `## X-BetterItem-Version` in the TOC so it always matches standalone RLBetterItem (currently 1.9.1)

## [1.0.3]

### Added
- **BetterItem: per-item GearScore in item tooltips** — `GearScore: N` in quality color, plus `HunterScore: N` for melee/ranged weapons for hunters (or with a modifier key / while inspecting a hunter)

### Fixed
- **BetterItem: missing item data is actively requested** — uncached gear now calls `C_Item.RequestLoadItemDataByID` and `GET_ITEM_INFO_RECEIVED` repaints the open unit tooltip once data arrives

## [1.0.2]

### Added
- **BetterItem: classic GearScore display** — unit tooltips and the char/inspect summary show the real GearScore (ilvl × rarity × slot modifier, quality-colored); hunters score ranged weapons high and melee low

### Fixed
- **BetterItem: iLvl average no longer sinks on uncached data** — slots whose `GetItemInfo` hasn't loaded are skipped and flagged `ready = false` for recomputation
- **BetterItem: two-handed weapons counted twice** — clients reporting the same 2H link in the off-hand slot counted it once for ilvl and once for score
- **BetterItem: Titan's Grip logic** — halving applies only with *two* 2H weapons; a single 2H keeps its full 2.0 slot modifier

## [1.0.1]

### Fixed
- **BetterItem: "bad self" spam from `UIParent` children** — `GetName()`/`IsShown()` probe for the vendor button's bag-frame host is wrapped in `pcall`; non-frame children (animation groups/regions) are skipped
- **BetterItem: settings import on newer clients** — `loadstring` is gone in Lua 5.3+; falls back to `load` so `RLBISET1` strings import again

## [1.0.0]

First public release — full UI replacement: action bars, unit frames, chat,
bags, minimap, data texts, maps, tooltips, auras, nameplates and more,
including the embedded **BetterItem** module (item scoring, gear summary,
vendor tools) ported from the standalone RLBetterItem addon.
