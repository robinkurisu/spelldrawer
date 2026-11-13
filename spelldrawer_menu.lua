-- Spell Drawer | menu. build() creates the controls; ui holds them by id.

local U = require("spelldrawer_util")

local CFG = U.CFG
local M = { ui = {} }
local ui = M.ui

-- shown in the Changelog tab, newest first: add a version's lines here when you bump VERSION
local CHANGELOG = {
    { "1.2.5", {
        "Enemy spells drawn as big as Greater or Mystic Expansion makes them",
        "Celeste's Light Eater is back: its cone is drawn through the 0.3 s cast",
    } },
    { "1.2.4", {
        "Parry Heavy Melee: an enemy's heavy melee is parried Parry Lead before his lunge lands",
        "Changelog tab; the Version label leaves General",
    } },
    { "1.2.3", {
        "Debug Mode logs about a third fewer lines",
        "The bundler and harness no longer error when Umbrella loads them",
    } },
    { "1.2.2", {
        "Parry Lead defaults to 0.45 s, so the parry is up in time",
        "Drifter's Rend drawn 100 deg wide, and has a danger level",
    } },
    { "1.2.1", {
        "Max Distance measures a spell where it passes nearest you, not from its caster",
        "An escape item that stops responding asks you to reload scripts, instead of reloading mid-match",
    } },
    { "1.2.0", {
        "Counterspell counts as on cooldown for 23 s after a block when its cooldown can't be read",
        "Lash's Death Slam parried 0.7 s after its lock-on",
        "An escape item that stops responding reloads the scripts, once a minute at most",
    } },
    { "1.1.1", {
        "Equal ways out of a spell lean toward your own walker",
        "Block Movement off for a shape: walking into it yourself no longer triggers a dodge",
        "Seven's Lightning Ball follows his aim when thrown upward",
    } },
    { "1.1.0", {
        "Danger levels 1-5 on spells; level 3 counts as dangerous at 35% health or less",
        "Dodge Only Dangerous keybind",
        "Escape Spells: Yamato's Shadow Transformation, Vindicta's Flight",
        "Escape items: Warp Stone, Ethereal Shift, and a Counterspell switch",
        "Itani Lo Sahn's mark: danger 4, and 5 at 35% health or less",
    } },
    { "1.0.3", {
        "Escape Spells: Apollo's Riposte, Pocket's Enchanter's Satchel, Dynamo's Quantum Entanglement",
    } },
    { "1.0.2", {
        "Mina's Rake",
        "Escape Spells card: Mina's Sanguine Retreat; items moved into Spells",
    } },
    { "1.0.1", {
        "Block Movement defaults to Lines only",
    } },
    { "1.0.0", {
        "First versioned release",
    } },
}

-- runs from the entry file so the menu is created at a known point, not on require
function M.build(spells)
    -- tabs line up, and cards stack, in the order they are made: the Evade tab first (General, with
    -- Enable and the Evade switch, on top), the hero list in its own Spells tab second, as it grows,
    -- and Debug always last
    local grp_gen = Menu.Create(U.SCRIPT, "", "Evade", "Evade", "General")
    local tab_main = grp_gen:Parent()
    local tab_root = tab_main:Parent()
    pcall(function() tab_root:Parent():Parent():Icon("\u{f70c}") end) -- running person
    local grp_main = Menu.Create(U.SCRIPT, "", "Evade", "Spells", "Spells")

    ui.sp_enable = grp_gen:Switch("Enable", CFG.DEFAULTS.sp_enable, "\u{f011}")
    ui.sp_enable:ToolTip("Master switch for Evade. If off, no spell is dodged or drawn.")
    ui.sp_dodge = grp_gen:Switch("Enable Dodging", CFG.DEFAULTS.sp_dodge, "\u{f554}")
    ui.sp_dodge:ToolTip("Turns dodging on or off. If off, spells can still be drawn.")
    ui.sp_melee = grp_gen:Switch("Parry Heavy Melee", CFG.DEFAULTS.sp_melee, "\u{f132}") -- shield
    ui.sp_melee:ToolTip("Parries an enemy's heavy melee, timed from his wind-up and lunge.\n"
        .. "Adjust Parry Lead (Tuning) before the hit.")
    ui.sp_guard = grp_gen:MultiCombo("Block Movement", { "Lines", "Circles", "Cones" }, CFG.DEFAULTS.sp_guard)
    pcall(ui.sp_guard.Icon, ui.sp_guard, "\u{f3ed}") -- shield
    ui.sp_guard:ToolTip("Too boxed in by a big trap like Spirit Snare? Untick its shape.\n"
        .. "Ticked shapes: your keys stop at their edge.\n"
        .. "Unticked: you walk in freely, but anything that lands on you is still dodged.")
    local reset_gen = grp_gen:Button("Reset General", function()
        for _, k in ipairs({ "sp_enable", "sp_dodge", "sp_melee", "sp_guard" }) do
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
        .. "drawn and dodged. 180 = in front of you, out to either side. 360 = all around you.\n"
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

    -- under Evade Tools: where a dodge may end, besides out of the spell
    local grp_path = tab_main:Create("Evade Path", Enum.GroupSide.Right)
    ui.sp_turrets = grp_path:MultiCombo("Avoid Turrets", { "Guardians", "Walkers", "Patron" }, CFG.DEFAULTS.sp_turrets)
    pcall(ui.sp_turrets.Icon, ui.sp_turrets, "\u{f447}") -- chess rook
    ui.sp_turrets:ToolTip("Enemy turrets whose range a dodge keeps out of.\n"
        .. "Evade goes round them, and won't end a dodge where they can shoot you.")
    ui.sp_turret_scale = grp_path:Slider("Turret Range Scale", 25, 150, CFG.DEFAULTS.sp_turret_scale, "%d%%")
    pcall(ui.sp_turret_scale.Icon, ui.sp_turret_scale, "\u{f140}") -- bullseye
    ui.sp_turret_scale:ToolTip("Share of each turret's attack range a dodge keeps out of.\n"
        .. "At 100%: Guardians 34 m, Walkers 24 m, Patron 34 m. At 50%: half that.\n"
        .. "Higher: keeps well clear, but leaves fewer places to dodge to near one.\n"
        .. "Lower: dodges closer to turrets.")
    ui.sp_hero_dist = grp_path:Slider("Hero Distance", 0, 10, CFG.DEFAULTS.sp_hero_dist, "%d m")
    pcall(ui.sp_hero_dist.Icon, ui.sp_hero_dist, "\u{f968}") -- people arrows
    ui.sp_hero_dist:ToolTip("Room a dodge keeps from enemy heroes, so it doesn't end in melee range.\n"
        .. "Higher: ends further from them. 0 = off.")
    ui.sp_hazard_rule = grp_path:Combo("Hazard Rule", { "Prefer", "Strict" }, CFG.DEFAULTS.sp_hazard_rule)
    pcall(ui.sp_hazard_rule.Icon, ui.sp_hazard_rule, "\u{f24e}") -- scale
    ui.sp_hazard_rule:ToolTip("When every way out of a spell ends near a turret or enemy hero.\n"
        .. "Prefer: go anyway, to the least bad spot. A spell's hit is sure, a turret's isn't.\n"
        .. "Strict: never end there. Parry or take the hit instead.")
    ui.sp_aggro = grp_path:Bind("Aggressive Dodge", Enum.ButtonCode.KEY_NONE, "\u{f6de}") -- raised fist
    ui.sp_aggro:ToolTip("Hold to dodge toward the nearest enemy hero.\n"
        .. "Ignores turrets and Hero Distance. If that's too slow, dodges the nearest way.")
    ui.sp_danger_only = grp_path:Bind("Dodge Only Dangerous", Enum.ButtonCode.KEY_NONE, "\u{f54c}") -- skull
    ui.sp_danger_only:ToolTip("Hold to dodge only the most dangerous spells.\n"
        .. "Every other spell is left alone while the key is down.")
    local reset_path = grp_path:Button("Reset Evade Path", function()
        for _, k in ipairs({ "sp_turrets", "sp_turret_scale", "sp_hero_dist", "sp_hazard_rule" }) do
            pcall(ui[k].Set, ui[k], CFG.DEFAULTS[k])
        end
        U.log("[RESET] evade path back to the defaults")
    end)
    reset_path:ToolTip("Reset all evade path settings.")

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
    ui.sp_parry_lead = grp_tune:Slider("Parry Lead", 0.05, 0.75, CFG.DEFAULTS.sp_parry_lead, "%.2f s")
    pcall(ui.sp_parry_lead.Icon, ui.sp_parry_lead, "\u{f252}") -- hourglass
    ui.sp_parry_lead:ToolTip("How long before a hit Evade parries it: a spell (with Counterspell)\n"
        .. "or a heavy melee.\n"
        .. "The parry blocks for 0.8 s, so the hit has to land inside that.\n"
        .. "Higher: parries earlier, safer if a hit comes sooner than expected.\n"
        .. "Lower: parries later, safer if a hit comes later than expected.")
    ui.sp_replan = grp_tune:Slider("Path Refresh", 0.05, 0.5, CFG.DEFAULTS.sp_replan, "%.2f s")
    pcall(ui.sp_replan.Icon, ui.sp_replan, "\u{f021}") -- arrows rotate
    ui.sp_replan:ToolTip("How often Evade looks again for the way out while you dodge.\n"
        .. "Lower: follows spells that turn or move more closely.\nHigher: walks a steadier line.")
    local reset_tune = grp_tune:Button("Reset Tuning", function()
        for _, k in ipairs({ "sp_react", "sp_dodge_gap", "sp_margin", "sp_parry_lead", "sp_replan" }) do
            pcall(ui[k].Set, ui[k], CFG.DEFAULTS[k])
        end
        U.log("[RESET] tuning back to the defaults")
    end)
    reset_tune:ToolTip("Reset all tuning settings.")

    -- the Changelog tab, before Debug: one card, each version's heading over its lines, newest on top
    local grp_log_card = Menu.Create(U.SCRIPT, "", "Evade", "Changelog", "Changelog")
    for _, entry in ipairs(CHANGELOG) do
        grp_log_card:Label("v" .. entry[1], "\u{f02b}") -- tag
        for _, line in ipairs(entry[2]) do
            grp_log_card:Label("\u{2022} " .. line:lower()) -- bullet in the text: the icon slot's dot is too big
        end
    end

    -- the Debug tab, made last so it stays last: the simulator, the logging beside it, the debug drawings below
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

return M
