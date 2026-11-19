-- Spell Drawer | menu. build() creates the controls; ui holds them by id.

local U = require("spelldrawer_util")

local CFG = U.CFG
local M = { ui = {} }
local ui = M.ui

-- shown in the changelog panel (Changelog switch, General), newest first: add a version's lines here when you bump VERSION
local CHANGELOG = {
    { "1.4.0", {
        "Stunned, knocked down or dragged, Evade presses nothing until it ends. Rooted, it uses Counterspell or a spell that blocks where you stand instead of walking or dashing.",
        "Walks out of a spell count the slows on you, so a slow area like Captivating Read is dashed out of sooner.",
        "Violet's Still Life is parried in time: its stun lands 2.6 s after the buildup on you, with no flight time added.",
        "Graves' Grasping Hands is drawn and dodged at any length: a wall her items grew past 26 m was not.",
        "Lash's Ground Strike follows his aim through the dive, not where he aimed as it began.",
        "Auto Parry taps once, and once more after 0.2 s if it didn't come up: spare taps fired a second, wasted parry. No dash is tapped while a parry holds you.",
    } },
    { "1.3.9", {
        "Dodges pick a safer place to end. Of the ways out of a spell that are about as short, Evade weighs four things: Retreat (back toward your base), Team (near an ally hero or your walker), Cover (out of enemy heroes' sight) and Momentum (the way you were already running).",
        "Retreat counts more at low health and when enemy heroes outnumber your side nearby.",
        "Evade Weights: a slider for each (0 to 1) sets how much it counts. 0 turns one off.",
        "Dodges keep 75% of a turret's range from it, down from 100%, and always 6 m from enemy heroes.",
    } },
    { "1.3.8", {
        "The script updates itself: a new version is downloaded as it loads, and a notification asks you to reload the scripts.",
        "Auto Parry is timed by the slider again, not a fixed 0.25 s. Hit Lead is renamed Hit Buffer: it times Counterspell, Auto Parry and escape spells.",
    } },
    { "1.3.7", {
        "Doorman's Hotel Guest: if you are still in the hotel as its 6.5 s run out, an escape item or spell is used just before the hit. Not used if you get out. The initial cast is too fast to answer.",
        "Mo & Krill's Combo is removed: it holds you the moment he clicks, and an escape item or spell can't be used once held.",
        "Dispel Magic: lesser debuffs are cleansed sooner (fewer needed) at 50% health or less, up from 35%.",
    } },
    { "1.3.6", {
        "Calico's Return to Shadows: only the burst when she comes back is drawn and dodged. The burst on cast hits before anything can react, and dodging it spent Warp Stone too late.",
        "Calico's Gloom Bombs is seen from her throw, before the bomb shows, and its lane is as wide as the blast, so close throws are dodged.",
        "A walk already getting you out is no longer swapped for a dash partway through, so stamina isn't spent on it.",
        "Dynamo's Kinetic Pulse wave reaches its real 16 m from him, not 16 m past where it was first seen, so Counterspell isn't spent on waves that stop short of you.",
    } },
    { "1.3.5", {
        "'Use On' moved to Tuning as Escape Spells, with its Activation Time slider, below Path Refresh. Reset Tuning resets both; your saved choice starts again at Undodgeable.",
        "Escape Spells decides if an escape is used; Hit Lead decides how early it is pressed.",
    } },
    { "1.3.4", {
        "Auto Parry always parries 0.25 s before the hit; Parry Lead is renamed Hit Lead and times only Counterspell and escape spells.",
        "Hit Lead defaults to 0.4 s (was 0.25 s), so Counterspell is up in time.",
    } },
    { "1.3.3", {
        "Escape Spells: Use On, at the bottom of the card. Undodgeable casts them only when no walk or dash gets out; Activation Time casts them first once a hit is within the time you set.",
    } },
    { "1.3.2", {
        "Doorman's Luggage Cart and Haze's Sleep Dagger are seen earlier, from the cast animation.",
    } },
    { "1.3.1", {
        "Block Movement: Walls (Grasping Hands) is its own item, off by default.",
        "Dodges prefer a spot out of enemy heroes' sight, unless Aggressive Dodge is held.",
        "Fixed dashing or walking into walls.",
    } },
    { "1.3.0", {
        "Dispel Magic and Divine Barrier: used by themselves against the debuffs on you; click a picture in Debuff Removal, below Auto Parry, to turn it off.",
        "Used at once against a silence, root, disarm or a mark about to stun you; lesser debuffs only when several are on you (fewer at low health).",
        "A debuff that stacks counts only at max stacks.",
        "Divine Barrier is also cast on allies within 40 m, in sight and inside your Dodge Arc: you come first, then the ally with the most dangerous debuffs.",
    } },
    { "1.2.9", {
        "Auto Parry: an enemy guardian's melee swing and slam are parried, timed from its wind-up.",
        "Parry Heavy Melee is now Auto Parry, below Block Movement: tick Heroes, Guardians or both (both by default).",
    } },
    { "1.2.8", {
        "Unstoppable: used against crowd control (stuns, sleeps, roots, silences, disarms, grabs, lifts, pulls and tethers) of danger 4 and up (3 at low health).",
        "Crowd control tags updated across the spell list.",
        "Haze's Sleep Dagger is danger 4 (was 3).",
        "13 spells with no danger level are now danger 3, among them Bookwyrm, Lightning Ball and Go For The Throat.",
    } },
    { "1.2.7", {
        "A spell that has already hit no longer stops the parry against the next one.",
        "Calico's Leaping Slash ends with her dash, so dodging near her is no longer held off after it.",
        "Mo & Krill's Burrow is no longer parried the moment he goes under.",
        "Billy's Bashdown wave keeps its own danger level.",
        "A second Knockdown right after the first is parried too.",
        "Shots fired down from the air (Pocket's Barrage) are timed over their whole flight.",
        "Lobs followed in flight are timed to their landing, not up to 0.05 s late.",
        "Baba: Granny Long Legs' ground pound is drawn and dodged.",
        "Changelog: the Changelog switch (General) opens it in a panel beside the menu; the Changelog tab is gone.",
    } },
    { "1.2.6", {
        "Parry Heavy Melee keeps to the Dodge Arc: no parry against a melee from behind you.",
        "Max Distance defaults to 60 m (was 120 m); a saved setting keeps its value.",
        "Block Movement counts how fast you run, so you no longer slide into an area.",
        "Baba: Threadsap and Baba's Brew are drawn and dodged.",
        "Parry Lead defaults to 0.25 s (was 0.45 s).",
    } },
    { "1.2.5", {
        "Enemy spells drawn as big as Greater or Mystic Expansion makes them.",
        "Celeste's Light Eater is back: its cone is drawn through the 0.3 s cast.",
    } },
    { "1.2.4", {
        "Parry Heavy Melee: an enemy's heavy melee is parried Parry Lead before his lunge lands.",
        "Changelog tab; the Version label leaves General.",
    } },
    { "1.2.3", {
        "Debug Mode logs about a third fewer lines.",
        "The bundler and harness no longer error when Umbrella loads them.",
    } },
    { "1.2.2", {
        "Parry Lead defaults to 0.45 s, so the parry is up in time.",
        "Drifter's Rend drawn 100 deg wide, and has a danger level.",
    } },
    { "1.2.1", {
        "Max Distance measures a spell where it passes nearest you, not from its caster.",
        "An escape item that stops responding asks you to reload scripts, instead of reloading mid-match.",
    } },
    { "1.2.0", {
        "Counterspell counts as on cooldown for 23 s after a block when its cooldown can't be read.",
        "Lash's Death Slam parried 0.7 s after its lock-on.",
        "An escape item that stops responding reloads the scripts, once a minute at most.",
    } },
    { "1.1.1", {
        "Equal ways out of a spell lean toward your own walker.",
        "Block Movement off for a shape: walking into it yourself no longer triggers a dodge.",
        "Seven's Lightning Ball follows his aim when thrown upward.",
    } },
    { "1.1.0", {
        "Danger levels 1-5 on spells; level 3 counts as dangerous at 35% health or less.",
        "Dodge Only Dangerous keybind.",
        "Escape Spells: Yamato's Shadow Transformation, Vindicta's Flight.",
        "Escape items: Warp Stone, Ethereal Shift, and a Counterspell switch.",
        "Itani Lo Sahn's mark: danger 4, and 5 at 35% health or less.",
    } },
    { "1.0.3", {
        "Escape Spells: Apollo's Riposte, Pocket's Enchanter's Satchel, Dynamo's Quantum Entanglement.",
    } },
    { "1.0.2", {
        "Mina's Rake.",
        "Escape Spells card: Mina's Sanguine Retreat; items moved into Spells.",
    } },
    { "1.0.1", {
        "Block Movement defaults to Lines only.",
    } },
    { "1.0.0", {
        "First versioned release.",
    } },
}

-- splits text into lines no wider than width, at spaces; a longer word gets a line of its own.
-- measure(str) gives a string's width; characters if left out
function M.wrap(text, width, measure)
    measure = measure or function(str) return #str end
    local out, cur = {}, ""
    for word in text:gmatch("%S+") do
        if cur ~= "" and measure(cur .. " " .. word) > width then
            out[#out + 1], cur = cur, word
        else
            cur = cur == "" and word or cur .. " " .. word
        end
    end
    if cur ~= "" then out[#out + 1] = cur end
    return out
end

-- runs from the entry file so the menu is created at a known point, not on require
function M.build(spells)
    -- tabs line up, and cards stack, in the order they are made: the Evade tab first (General, with
    -- Enable and the Evade switch, on top), the hero list in its own Spells tab second, as it grows,
    -- then Debug last
    local grp_gen = Menu.Create(U.SCRIPT, "", "Evade", "Evade", "General")
    local tab_main = grp_gen:Parent()
    local tab_root = tab_main:Parent()
    pcall(function() tab_root:Parent():Parent():Icon("\u{f70c}") end) -- running person
    local grp_main = Menu.Create(U.SCRIPT, "", "Evade", "Spells", "Spells")

    ui.sp_enable = grp_gen:Switch("Enable", CFG.DEFAULTS.sp_enable, "\u{f011}")
    ui.sp_enable:ToolTip("Master switch for Evade. If off, no spell is dodged or drawn.")
    ui.sp_dodge = grp_gen:Switch("Enable Dodging", CFG.DEFAULTS.sp_dodge, "\u{f554}")
    ui.sp_dodge:ToolTip("Turns dodging on or off. If off, spells can still be drawn.")
    ui.sp_guard = grp_gen:MultiCombo("Block Movement", { "Lines", "Circles", "Cones", "Walls" }, CFG.DEFAULTS.sp_guard)
    pcall(ui.sp_guard.Icon, ui.sp_guard, "\u{f3ed}") -- shield
    ui.sp_guard:ToolTip("Too boxed in by a big trap? Untick its shape.\n"
        .. "Ticked shapes: your keys stop at their edge.\n"
        .. "Unticked: you walk in freely, but anything that lands on you is still dodged.")
    -- a new name, not "Parry Heavy Melee": that one saved a switch's true or false (2026-11-15)
    ui.sp_melee = grp_gen:MultiCombo("Auto Parry", { "Heroes", "Guardians" }, CFG.DEFAULTS.sp_melee)
    pcall(ui.sp_melee.Icon, ui.sp_melee, "\u{f255}") -- hand-rock (fist); f6de is Aggressive Dodge's
    ui.sp_melee:ToolTip("Parries an enemy's melee, for those ticked.\n"
        .. "Heroes: a heavy melee, timed from his wind-up and lunge.\n"
        .. "Guardians: its swing or slam, timed from its wind-up.\n"
        .. "Adjust Hit Buffer (Tuning) before the hit.")
    -- pictured items, clicked on and off as in the Spells lists. A new name, not "Dispel Magic": that
    -- one saved a switch's true or false (2026-11-15)
    local dispel_list, dispel_tips = {}, {}
    for i, it in ipairs(U.DISPEL_ITEMS) do
        dispel_list[i] = { it.name, it.image, true }
        -- short, one or two lines each: when they are used is the row's own tooltip
        dispel_tips[it.name] = it.name .. (it.self and ": removes debuffs from you, or from an ally in your Dodge Arc.\n"
            .. "You come first. Warning: uses silent aim on allies." or ": removes debuffs from you.")
    end
    ui.sp_dispel = grp_gen:MultiSelect("Debuff Removal", dispel_list, true)
    pcall(ui.sp_dispel.Icon, ui.sp_dispel, "\u{f0c4}") -- scissors
    ui.sp_dispel:ToolTip("Items used by themselves to remove debuffs. Click one to turn it on or off.\n"
        .. "Used at once on a silence, root or disarm.\n"
        .. "Lesser debuffs: only when several are on you (fewer at low health).")
    pcall(ui.sp_dispel.UpdateToolTips, ui.sp_dispel, dispel_tips)
    ui.sp_aggro = grp_gen:Bind("Aggressive Dodge", Enum.ButtonCode.KEY_NONE, "\u{f6de}") -- raised fist
    ui.sp_aggro:ToolTip("Hold to dodge toward the nearest enemy hero.\n"
        .. "Ignores turrets, the room kept from enemy heroes and the Evade Weights.\n"
        .. "Recommended to pair with your combo key.")
    ui.sp_danger_only = grp_gen:Bind("Dodge Only Dangerous", Enum.ButtonCode.KEY_NONE, "\u{f54c}") -- skull
    ui.sp_danger_only:ToolTip("Hold to dodge only the most dangerous spells.\n"
        .. "Every other spell is left alone while the key is down.\n"
        .. "Use in late game when minor spells dont matter.")
    -- the panel M.draw_changelog draws beside the menu (the menu only lays out widgets, too narrow for it)
    ui.sp_changelog = grp_gen:Switch("Changelog", false, "\u{f15c}") -- file lines
    ui.sp_changelog:ToolTip("Opens the changelog beside the menu. Scroll it with the mouse wheel.\n"
        .. "It closes with the menu.")
    local reset_gen = grp_gen:Button("Reset General", function()
        for _, k in ipairs({ "sp_enable", "sp_dodge", "sp_melee", "sp_dispel", "sp_guard" }) do
            pcall(ui[k].Set, ui[k], CFG.DEFAULTS[k])
        end
        U.log("[RESET] general settings back to the defaults")
    end)
    reset_gen:ToolTip("Reset all general settings.")

    -- under General: which spells count at all, for drawing and dodging alike
    local grp_filter = tab_main:Create("Filters")
    ui.sp_fog = grp_filter:Switch("Visible Only", CFG.DEFAULTS.sp_fog, "\u{f070}") -- eye slash
    ui.sp_fog:ToolTip("Ignore spells from enemies you can't see: behind a wall, or hidden in fog.\n"
        .. "On: a spell is drawn and dodged only once its caster has been in sight.\n"
        .. "Off: every spell is drawn and dodged, seen or not.")
    ui.sp_fov = grp_filter:Slider("Dodge Arc", 90, 360, CFG.DEFAULTS.sp_fov, "%d deg")
    pcall(ui.sp_fov.Icon, ui.sp_fov, "\u{f14e}") -- compass
    ui.sp_fov:ToolTip("Only spells cast from within this angle of where your camera faces are\n"
        .. "drawn and dodged, and heavy melees parried.\n"
        .. "Lower: ignores casters to your sides too.\n"
        .. "Higher: also answers casters behind you.\n"
        .. "A spell cast in view stays answered if you turn away.")
    ui.sp_dist = grp_filter:Slider("Max Distance", 0, 200, CFG.DEFAULTS.sp_dist, "%d m")
    pcall(ui.sp_dist.Icon, ui.sp_dist, "\u{f547}") -- ruler
    ui.sp_dist:ToolTip("Spells further from you than this are not drawn or dodged. 0 = no limit.")
    ui.sp_collide = grp_filter:Switch("Unit Collision (Beta)", CFG.DEFAULTS.sp_collide, "\u{f0c0}") -- users
    ui.sp_collide:ToolTip("Shots that stop on the first unit they touch (Bebop's hook, Doorman's cart)\n"
        .. "end at a hero, trooper or creep standing between you and the caster.\n"
        .. "On: no dodge when someone else will take the hit. Units move, so it can be wrong.\n"
        .. "Off: every shot is drawn and dodged all the way to you.")
    local reset_filter = grp_filter:Button("Reset Filters", function()
        for _, k in ipairs({ "sp_fog", "sp_fov", "sp_dist", "sp_collide" }) do
            pcall(ui[k].Set, ui[k], CFG.DEFAULTS[k])
        end
        U.log("[RESET] filters back to the defaults")
    end)
    reset_filter:ToolTip("Reset all filter settings.")

    -- one open list per hero, named and pictured, its ability icons in view: click one to toggle it
    local heroes, order, items = {}, {}, {}
    for _, s in ipairs(spells) do
        local h = heroes[s.hero]
        if not h and not s.item then
            h = { image = s.hero_image or "", spells = {} }
            heroes[s.hero], order[#order + 1] = h, s.hero
        end
        local row = s.item and items or h.spells -- an item goes in the Items list, not under a hero
        row[#row + 1] = s
    end
    table.sort(order)
    -- on top, above the heroes: the enemy items Evade answers (`item` entries), whoever bought them
    local list, item_tips = {}, {}
    for _, s in ipairs(items) do
        list[#list + 1] = { s.name, s.image, true }
        item_tips[s.name] = s.name -- each icon names its item
    end
    local sel = grp_main:MultiSelect("Items", list, true)
    pcall(sel.Icon, sel, "\u{f290}") -- shopping bag
    pcall(sel.UpdateToolTips, sel, item_tips)
    for _, s in ipairs(items) do s.ui = sel end
    for _, name in ipairs(order) do
        local h, abilities, tips = heroes[name], {}, {}
        for _, s in ipairs(h.spells) do
            abilities[#abilities + 1] = { s.name, s.image, true }
            tips[s.name] = s.name -- each icon names its spell
        end
        local select = grp_main:MultiSelect(name, abilities, true)
        if h.image ~= "" then pcall(select.Image, select, h.image) end
        pcall(select.UpdateToolTips, select, tips)
        for _, s in ipairs(h.spells) do s.ui = select end
    end

    -- beside the heroes: your own hero's evade spell (U.EVADE_SPELLS), one list per hero as on the
    -- left; unticked, Evade never casts it
    local grp_evade = grp_main:Parent():Create("Escape Spells", Enum.GroupSide.Right)
    -- on top, as on the left: one Items list, the items you can escape with (`item`) and Counterspell
    -- each one's tooltip: when it is cast, its danger floor, and a warning on those aimed silently
    -- (all but the ones that block where you stand)
    local function tip(e)
        return e.name .. ": cast when no walk or dash gets out in time"
            .. (e.danger and "\nOnly used on the most dangerous spells." or "")
            .. (e.block and "" or "\nWarning: uses silent aim.")
    end
    local own, own_tips = { U.COUNTERSPELL }, { [U.COUNTERSPELL.name] = "Counterspell: parried just before a spell hits" }
    for _, s in ipairs(U.EVADE_SPELLS) do
        if s.item then
            table.insert(own, #own, s) -- before Counterspell
            own_tips[s.name] = tip(s)
        end
    end
    local own_list = {}
    for i, s in ipairs(own) do own_list[i] = { s.name, s.image, true } end
    local own_sel = grp_evade:MultiSelect("Items", own_list, true)
    pcall(own_sel.Icon, own_sel, "\u{f290}") -- shopping bag
    pcall(own_sel.UpdateToolTips, own_sel, own_tips)
    for _, s in ipairs(own) do s.ui = own_sel end
    -- then the heroes by name, as on the left (a copy is sorted: the table's order is the order tried)
    local by_hero = {}
    for _, s in ipairs(U.EVADE_SPELLS) do
        if not s.item then by_hero[#by_hero + 1] = s end
    end
    table.sort(by_hero, function(x, y) return x.hero < y.hero end)
    for _, s in ipairs(by_hero) do
        local select = grp_evade:MultiSelect(s.hero, { { s.name, s.image, true } }, true)
        pcall(select.Image, select, s.hero_image)
        pcall(select.UpdateToolTips, select, { [s.name] = tip(s) })
        s.ui = select
    end

    -- under Evade Tools: what a dodge weighs when several ways out of a spell are about as short
    -- (evade.lua's spot_score)
    local grp_path = tab_main:Create("Evade Weights", Enum.GroupSide.Right)
    ui.sp_turrets = grp_path:MultiCombo("Avoid Turrets", { "Guardians", "Walkers", "Patron" }, CFG.DEFAULTS.sp_turrets)
    pcall(ui.sp_turrets.Icon, ui.sp_turrets, "\u{f447}") -- chess rook
    ui.sp_turrets:ToolTip("Enemy turrets a dodge keeps away from.\n"
        .. "Evade goes round them when there is a way; if every way out of a spell\n"
        .. "ends near one, it goes to the least bad spot.")
    ui.sp_momentum = grp_path:Slider("Momentum", 0.0, 1.0, CFG.DEFAULTS.sp_momentum, "%.2f")
    pcall(ui.sp_momentum.Icon, ui.sp_momentum, "\u{f70c}") -- running person
    ui.sp_momentum:ToolTip("How much a dodge favours ending the way you were already running.\n"
        .. "Higher: beats the other weights more often. 0 = off.")
    ui.sp_retreat = grp_path:Slider("Retreat", 0.0, 1.0, CFG.DEFAULTS.sp_retreat, "%.2f")
    pcall(ui.sp_retreat.Icon, ui.sp_retreat, "\u{f3e5}") -- reply arrow
    ui.sp_retreat:ToolTip("How much a dodge favours ending back toward your base: your nearest\n"
        .. "guardian or walker behind you, else your Patron.\n"
        .. "Counts more at low health and when enemy heroes outnumber your side nearby.\n"
        .. "Higher: beats the other weights more often. 0 = off.")
    ui.sp_team = grp_path:Slider("Team", 0.0, 1.0, CFG.DEFAULTS.sp_team, "%.2f")
    pcall(ui.sp_team.Icon, ui.sp_team, "\u{f0c0}") -- users
    ui.sp_team:ToolTip("How much a dodge favours ending near an ally hero or your walker.\n"
        .. "Never closer than 5 m to an ally hero, so one spell doesn't hit you both.\n"
        .. "Higher: beats the other weights more often. 0 = off.")
    ui.sp_cover = grp_path:Slider("Cover", 0.0, 1.0, CFG.DEFAULTS.sp_cover, "%.2f")
    pcall(ui.sp_cover.Icon, ui.sp_cover, "\u{f070}") -- eye slash
    ui.sp_cover:ToolTip("How much a dodge favours ending where enemy heroes can't see you.\n"
        .. "Each enemy without sight of the spot counts.\n"
        .. "Higher: goes for cover more often. 0 = off.")
    local reset_path = grp_path:Button("Reset Evade Weights", function()
        for _, k in ipairs({ "sp_turrets", "sp_momentum", "sp_retreat", "sp_team", "sp_cover" }) do
            pcall(ui[k].Set, ui[k], CFG.DEFAULTS[k])
        end
        U.log("[RESET] evade weights back to the defaults")
    end)
    reset_path:ToolTip("Reset all evade weights settings.")

    -- under Filters: the timings and room Evade plans with, to tinker with
    local grp_tune = tab_main:Create("Tuning")
    ui.sp_react = grp_tune:Slider("Reaction Time", 0.1, 0.3, CFG.DEFAULTS.sp_react, "%.2f s")
    pcall(ui.sp_react.Icon, ui.sp_react, "\u{f0e7}") -- bolt
    ui.sp_react:ToolTip("Time Evade allows for your hero to start moving once it decides.\n"
        .. "Higher: leaves more room, so it gives up on close calls and parries instead.\n"
        .. "Lower: takes closer calls, but a walk or dash may start too late.")
    ui.sp_dodge_gap = grp_tune:Slider("Dodge Interval", 0.0, 1.0, CFG.DEFAULTS.sp_dodge_gap, "%.2f s")
    pcall(ui.sp_dodge_gap.Icon, ui.sp_dodge_gap, "\u{f2f2}") -- stopwatch
    ui.sp_dodge_gap:ToolTip("Pause after a dodge (walk, dash or parry) ends before Evade starts another.\n"
        .. "Higher: fewer back-to-back dodges and less stamina spent on areas that\n"
        .. "only flicker over you, but a second spell right after waits this long.\n"
        .. "Lower: reacts to the next spell at once. 0 = no pause.")
    ui.sp_margin = grp_tune:Slider("Safety Margin", 0.25, 3.0, CFG.DEFAULTS.sp_margin, "%.2f m")
    pcall(ui.sp_margin.Icon, ui.sp_margin, "\u{f3ed}") -- shield
    ui.sp_margin:ToolTip("Extra room Evade keeps past a spell's edge.\n"
        .. "Higher: steps further clear, safer if a spell is a bit wider than drawn,\n"
        .. "but moves take longer, so fewer spells are escaped in time.\n"
        .. "Lower: shorter moves escape more spells, but the edge may clip you.")
    ui.sp_parry_lead = grp_tune:Slider("Hit Buffer", 0.05, 0.75, CFG.DEFAULTS.sp_parry_lead, "%.2f s")
    pcall(ui.sp_parry_lead.Icon, ui.sp_parry_lead, "\u{f252}") -- hourglass
    ui.sp_parry_lead:ToolTip("Seconds before a hit that Evade parries or escapes.\n"
        .. "Higher: if you're hit before it reacts.\n"
        .. "Lower: if it reacts, then you're hit anyway.")
    ui.sp_replan = grp_tune:Slider("Path Refresh", 0.05, 0.5, CFG.DEFAULTS.sp_replan, "%.2f s")
    pcall(ui.sp_replan.Icon, ui.sp_replan, "\u{f021}") -- arrows rotate
    ui.sp_replan:ToolTip("How often Evade looks again for the way out while you dodge.\n"
        .. "Lower: follows spells that turn or move more closely.\nHigher: walks a steadier line.")
    -- last, above the reset: when the Escape Spells card's spells and items are cast
    ui.sp_escape_mode = grp_tune:Combo("Escape Spells", { "Undodgeable", "Activation Time" }, CFG.DEFAULTS.sp_escape_mode)
    pcall(ui.sp_escape_mode.Icon, ui.sp_escape_mode, "\u{f6e2}") -- ghost
    ui.sp_escape_mode:ToolTip("When Evade picks an escape spell or item instead of a walk or dash.\n"
        .. "Undodgeable: only when no walk or dash gets out in time.\n"
        .. "Activation Time: also once a hit is close, even if a walk or dash would make it.\n"
        .. "Not the same as Hit Buffer: this decides if an escape is used,\n"
        .. "Hit Buffer decides how early it is pressed.")
    ui.sp_escape_time = grp_tune:Slider("Activation Time", 0.1, 3.0, CFG.DEFAULTS.sp_escape_time, "%.2f s")
    pcall(ui.sp_escape_time.Icon, ui.sp_escape_time, "\u{f2f2}") -- stopwatch
    ui.sp_escape_time:ToolTip("A spell that hits you within this time gets an escape spell first,\n"
        .. "even if a walk or dash would make it.\n"
        .. "Higher: escapes used more often. Lower: kept for the closest calls.\n"
        .. "Escapes that block where you stand are still pressed at Hit Buffer.")
    -- the slider shows only under Activation Time
    pcall(ui.sp_escape_mode.SetCallback, ui.sp_escape_mode, function()
        pcall(ui.sp_escape_time.Visible, ui.sp_escape_time, ui.sp_escape_mode:Get() == 1)
    end, true)
    local reset_tune = grp_tune:Button("Reset Tuning", function()
        for _, k in ipairs({ "sp_react", "sp_dodge_gap", "sp_margin", "sp_parry_lead", "sp_escape_mode", "sp_escape_time", "sp_replan" }) do
            pcall(ui[k].Set, ui[k], CFG.DEFAULTS[k])
        end
        U.log("[RESET] tuning back to the defaults")
    end)
    reset_tune:ToolTip("Reset all tuning settings.")

    -- the Debug tab: the simulator, the logging beside it, the debug drawings below
    local grp_sim = Menu.Create(U.SCRIPT, "", "Evade", "Debug", "Simulator")
    ui.sp_sim = grp_sim:Switch("Spell Simulator", CFG.DEFAULTS.sp_sim, "\u{f05b}")
    ui.sp_sim:ToolTip("Cast test spells at you.")
    ui.sp_sim_gap = grp_sim:Slider("Interval", 0.5, 5.0, CFG.DEFAULTS.sp_sim_gap, "%.1f s")
    pcall(ui.sp_sim_gap.Icon, ui.sp_sim_gap, "\u{f2f2}") -- stopwatch
    ui.sp_sim_gap:ToolTip("Seconds between test spells.")
    ui.sp_sim_cd = grp_sim:Switch("Item Cooldowns", CFG.DEFAULTS.sp_sim_cd, "\u{f253}") -- hourglass end
    ui.sp_sim_cd:ToolTip("Counterspell goes on its 23 s cooldown after a test block,\nas in a real match.")

    local grp_log = grp_sim:Parent():Create("Logging", Enum.GroupSide.Right)
    ui.sp_debug = grp_log:Switch("Debug Mode", CFG.DEFAULTS.sp_debug, "\u{f188}")
    ui.sp_debug:ToolTip("Log detections to the console.")
    ui.sp_profile = grp_log:Switch("Profile", false, "\u{f2f2}") -- stopwatch
    ui.sp_profile:ToolTip("Log the time each part of the script takes, every 5 s.")

    -- what detection saw and what Evade decided, drawn; none of it changes what Evade dodges
    local grp_vis = grp_sim:Parent():Create("Visuals")
    -- these two only hide the drawing: Evade dodges the areas either way
    ui.sp_land = grp_vis:Switch("Landing Marker", CFG.DEFAULTS.sp_land, "\u{f3c5}") -- map marker
    ui.sp_land:ToolTip("Draw spell areas: landings, rings, cones.")
    ui.sp_arc = grp_vis:Switch("Trajectory", CFG.DEFAULTS.sp_arc, "\u{f4d7}") -- route
    ui.sp_arc:ToolTip("Draw shot and dash paths.")
    -- off by default: with Evade off it still runs Evade's search, just to draw it
    ui.sp_dodge_debug = grp_vis:Switch("Evade Path", CFG.DEFAULTS.sp_dodge_debug, "\u{f06e}") -- eye
    ui.sp_dodge_debug:ToolTip("Show Evade's grid, path and safe spot.")
    ui.sp_boxes = grp_vis:Switch("World Pins", CFG.DEFAULTS.sp_boxes, "\u{f08d}") -- thumbtack
    ui.sp_boxes:ToolTip("Pin and ring on each spell.")
    ui.sp_points = grp_vis:Switch("Particle Points", CFG.DEFAULTS.sp_points, "\u{f192}") -- dot in a circle
    ui.sp_points:ToolTip("Cross on each particle point.")
    ui.sp_size = grp_vis:Slider("Marker Size", 1, 12, CFG.DEFAULTS.sp_size, "%d u")
    pcall(ui.sp_size.Icon, ui.sp_size, "\u{f31e}") -- expand arrows
    ui.sp_size:ToolTip("Size of the particle crosses.")
    ui.sp_labels = grp_vis:Switch("Labels", CFG.DEFAULTS.sp_labels, "\u{f02b}") -- tag
    ui.sp_labels:ToolTip("Text labels on spells.")
    local reset_vis = grp_vis:Button("Reset Visuals", function()
        for _, k in ipairs({ "sp_land", "sp_arc", "sp_dodge_debug", "sp_boxes", "sp_points", "sp_size", "sp_labels" }) do
            pcall(ui[k].Set, ui[k], CFG.DEFAULTS[k])
        end
        U.log("[RESET] visuals back to the defaults")
    end)
    reset_vis:ToolTip("Reset all visual settings.")

end

-- the changelog panel, drawn beside the menu while the Changelog switch is on and the menu is open
local log_font, log_bold
do
    local flag = Enum and Enum.FontCreate and Enum.FontCreate.FONTFLAG_ANTIALIAS or 16
    local ok, h = pcall(Render.LoadFont, "Tahoma", flag, 400)
    if ok then log_font = h end
    ok, h = pcall(Render.LoadFont, "Tahoma", flag, 700)
    if ok then log_bold = h end
end
local log_scroll, log_rows, log_rows_w = 0, nil, nil

-- every row of the panel at text width w: { text, font, size, color, x offset, y, height }, and the total height
local function log_layout(w, s, accent, text)
    local rows, y = {}, 0
    for i, entry in ipairs(CHANGELOG) do
        if i > 1 then y = y + 14 * s end -- room between versions
        local size = 15 * s
        rows[#rows + 1] = { "v" .. entry[1], log_bold, size, accent, 0, y }
        y = y + size * 1.5
        size = 13 * s
        local indent = 14 * s -- the bullet's column
        for _, line in ipairs(entry[2]) do
            local pieces = M.wrap(line, w - indent, function(str) return Render.TextSize(log_font, size, str).x end)
            for k, piece in ipairs(pieces) do
                if k == 1 then rows[#rows + 1] = { "\u{2022}", log_font, size, accent, 2 * s, y } end
                rows[#rows + 1] = { piece, log_font, size, text, indent, y }
                y = y + size * 1.35
            end
            y = y + 3 * s -- a little room between changes
        end
    end
    return rows, y
end

function M.draw_changelog()
    local sw = ui.sp_changelog
    if not sw or not sw:Get() then return end
    if not Menu.Opened() then sw:Set(false) return end -- closes with the menu, so it doesn't pop up next time
    if not log_font then return end
    local s = (Menu.Scale() or 100) / 100
    local a = Menu.Alpha() or 1
    if a > 1 then a = a / 255 end -- shortcut: Alpha's range isn't documented, 0-1 or 0-255 both work
    local function col(r, g, b, al) return Color(r, g, b, math.floor(al * a)) end
    local accent, text = col(255, 85, 85, 255), col(220, 220, 225, 255)

    -- beside the menu on the right, or on the left if the screen ends first; as tall as the menu
    local mp, ms = Menu.Pos(), Menu.Size()
    local w, pad, gap = 420 * s, 16 * s, 10 * s
    local x = mp.x + ms.x + gap
    if x + w > Render.ScreenSize().x then x = mp.x - gap - w end
    local y, h = mp.y, ms.y
    Render.FilledRect(Vec2(x, y), Vec2(x + w, y + h), col(18, 18, 22, 240), 8 * s)
    Render.Rect(Vec2(x, y), Vec2(x + w, y + h), col(255, 255, 255, 25), 8 * s)

    -- the title and a close cross
    Render.Text(log_bold, 18 * s, "Evade Changelog", Vec2(x + pad, y + pad), col(255, 255, 255, 255))
    local cx, cy, cr = x + w - pad - 6 * s, y + pad + 9 * s, 6 * s
    local over_x = input.cursor_in_bounds(Vec2(cx - cr - 4 * s, cy - cr - 4 * s), Vec2(cx + cr + 4 * s, cy + cr + 4 * s))
    local xc = over_x and accent or col(160, 160, 170, 255)
    Render.Line(Vec2(cx - cr, cy - cr), Vec2(cx + cr, cy + cr), xc, 2 * s)
    Render.Line(Vec2(cx - cr, cy + cr), Vec2(cx + cr, cy - cr), xc, 2 * s)
    if over_x and input.is_pressed(Enum.ButtonCode.KEY_MOUSE1) then sw:Set(false) return end
    local top = y + pad + 34 * s
    Render.Line(Vec2(x + pad, top - 10 * s), Vec2(x + w - pad, top - 10 * s), col(255, 255, 255, 25), 1)

    -- the rows, laid out again only when the width changes (menu scale), scrolled and clipped
    local tw = w - 2 * pad - 8 * s -- room for the scrollbar
    if log_rows_w ~= tw then log_rows, log_rows_w = { log_layout(tw, s, accent, text) }, tw end
    local rows, total = log_rows[1], log_rows[2]
    local view = y + h - pad - top
    local over = input.cursor_in_bounds(Vec2(x, y), Vec2(x + w, y + h))
    if over and input.is_pressed(Enum.ButtonCode.KEY_MWHEELUP) then log_scroll = log_scroll - 60 * s end
    if over and input.is_pressed(Enum.ButtonCode.KEY_MWHEELDOWN) then log_scroll = log_scroll + 60 * s end
    log_scroll = math.max(0, math.min(log_scroll, math.max(0, total - view)))
    Render.PushClip(Vec2(x, top), Vec2(x + w, top + view))
    for _, r in ipairs(rows) do
        local ry = top + r[6] - log_scroll
        if ry + r[3] * 2 > top and ry < top + view then
            -- colors were made at layout time: tint again so the menu's fade reaches them
            Render.Text(r[2], r[3], r[1], Vec2(x + pad + r[5], ry), col(r[4].r, r[4].g, r[4].b, 255))
        end
    end
    Render.PopClip()
    if total > view then -- the scrollbar
        local bx, bh = x + w - pad + 2 * s, view * view / total
        local by = top + (view - bh) * log_scroll / (total - view)
        Render.FilledRect(Vec2(bx, by), Vec2(bx + 3 * s, by + bh), col(255, 255, 255, 60), 2 * s)
    end
end

return M
