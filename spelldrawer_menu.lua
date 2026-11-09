-- Spell Drawer | menu. build() creates the controls; ui holds them by id.

local U = require("spelldrawer_util")

local CFG = U.CFG
local M = { ui = {} }
local ui = M.ui

-- runs from the entry file so the menu is created at a known point, not on require
function M.build(spells)
    -- tabs line up, and cards stack, in the order they are made: the Evade tab first (Enable's
    -- card on top), the hero list in its own Spells tab second, as it grows, and Debug always last
    local grp_gen = Menu.Create(U.SCRIPT, "", "Spells", "Evade", "General")
    local tab_main = grp_gen:Parent()
    local tab_root = tab_main:Parent()
    pcall(function() tab_root:Parent():Parent():Icon("\u{f02d}") end)
    local grp_main = Menu.Create(U.SCRIPT, "", "Spells", "Spells", "Spells")

    local shapes, items = {}, {}
    for _, sh in ipairs(CFG.DODGE_SHAPES) do shapes[#shapes + 1] = sh.name end
    for _, it in ipairs(CFG.EVADE_ITEMS) do items[#items + 1] = it.name end

    local function reset_tab()
        for k, v in pairs(CFG.DEFAULTS) do pcall(ui[k].Set, ui[k], v) end
        for _, s in ipairs(spells) do pcall(s.ui.Set, s.ui, s.name, true) end
        pcall(ui.sp_dodge_shapes.Set, ui.sp_dodge_shapes, shapes)
        pcall(ui.sp_evade_items.Set, ui.sp_evade_items, items)
        U.log("[RESET] settings back to the defaults")
    end

    ui.sp_enable = grp_gen:Switch("Enable", CFG.DEFAULTS.sp_enable, "\u{f011}")
    ui.sp_enable:ToolTip("Draws enemy spell particles and spell entities in the world.")

    -- one open list per hero, named and pictured, its ability icons in view: click one to toggle it
    local heroes, order = {}, {}
    for _, s in ipairs(spells) do
        local h = heroes[s.hero]
        if not h then
            h = { image = s.hero_image or "", spells = {} }
            heroes[s.hero], order[#order + 1] = h, s.hero
        end
        h.spells[#h.spells + 1] = s
    end
    for _, name in ipairs(order) do
        local h, abilities = heroes[name], {}
        for _, s in ipairs(h.spells) do abilities[#abilities + 1] = { s.name, s.image, true } end
        local select = grp_main:MultiSelect(name, abilities, true)
        if h.image ~= "" then pcall(select.Image, select, h.image) end
        select:ToolTip("Click an ability to toggle drawing it.")
        for _, s in ipairs(h.spells) do s.ui = select end
    end

    -- beside the heroes: what Evade may use to get you out, items for now (your hero's own evade
    -- abilities to join them); ticked is used when walking and dashing can't make it, unticked never
    local grp_tools = grp_main:Parent():Create("Evade Tools", Enum.GroupSide.Right)
    local list = {}
    for _, it in ipairs(CFG.EVADE_ITEMS) do list[#list + 1] = { it.name, it.image, true } end
    ui.sp_evade_items = grp_tools:MultiSelect("Items", list, true)
    pcall(ui.sp_evade_items.Icon, ui.sp_evade_items, "\u{f290}") -- shopping bag
    ui.sp_evade_items:ToolTip("Items Evade may use when walking and dashing can't get you out. Counterspell: a parry timed to the hit, if you own it and it is off cooldown.")

    local grp_opt = tab_main:Create("Draw", Enum.GroupSide.Right)

    -- what decides the areas themselves: Evade only dodges what is drawn, so these stay out of Debug
    ui.sp_land = grp_opt:Switch("Landing Marker", CFG.DEFAULTS.sp_land, "\u{f3c5}") -- map marker
    ui.sp_land:ToolTip("Predicts where the spell lands or stops, and draws its area or impact point. Evade only dodges what is drawn: off, it ignores landing areas.")
    ui.sp_arc = grp_opt:Switch("Trajectory", CFG.DEFAULTS.sp_arc, "\u{f4d7}") -- route
    ui.sp_arc:ToolTip("Draws the predicted projectile path: the arc of lobbed spells, the lane of straight shots. Evade only dodges what is drawn: off, it ignores shot lanes.")
    ui.sp_dist = grp_opt:Slider("Max Distance", 0, 200, CFG.DEFAULTS.sp_dist, "%d m")
    pcall(ui.sp_dist.Icon, ui.sp_dist, "\u{f547}") -- ruler
    ui.sp_dist:ToolTip("Hides spells further away than this. 0 means no limit. Evade only dodges what is drawn, so this is its range too.")

    local grp_dodge = tab_main:Create("Evade")
    ui.sp_dodge = grp_dodge:Switch("Evade", CFG.DEFAULTS.sp_dodge, "\u{f554}")
    ui.sp_dodge:ToolTip("Takes over your movement while you stand in a drawn enemy spell area: walks you to the nearest safe spot, around walls, if that beats the hit; dashes if only a dash makes it (stamina permitting); failing that, parries it with Counterspell if you own it and it is off cooldown; otherwise leaves you be. While you stand clear, it lets go of any movement key of yours that would walk you into an area still to hit.")
    ui.sp_dodge_shapes = grp_dodge:MultiCombo("Evade Shapes", shapes, shapes)
    pcall(ui.sp_dodge_shapes.Icon, ui.sp_dodge_shapes, "\u{f61f}") -- shapes
    ui.sp_dodge_shapes:ToolTip("Which drawn areas Evade and its guard react to: circles (landing areas, rings on a caster), lanes (shots, dashes) and cones (melee fans). The others are still drawn.")

    -- the Debug tab, made last so it stays last: the simulator, the logging beside it, the debug drawings below
    local grp_sim = Menu.Create(U.SCRIPT, "", "Spells", "Debug", "Simulator")
    ui.sp_sim = grp_sim:Switch("Spell Simulator", CFG.DEFAULTS.sp_sim, "\u{f05b}")
    ui.sp_sim:ToolTip("Casts the spells turned on in the hero rows at you, from random spots and angles around you, drawn like real ones. With Evade on, it takes over; each one is logged as dodged, countered or hit. Simulated spells go through walls.")
    ui.sp_sim_gap = grp_sim:Slider("Interval", 0.5, 5.0, CFG.DEFAULTS.sp_sim_gap, "%.1f s")
    pcall(ui.sp_sim_gap.Icon, ui.sp_sim_gap, "\u{f2f2}") -- stopwatch
    ui.sp_sim_gap:ToolTip("Seconds from one simulated spell being over to the next being cast.")

    local grp_log = grp_sim:Parent():Create("Logging", Enum.GroupSide.Right)
    ui.sp_debug = grp_log:Switch("Debug Mode", CFG.DEFAULTS.sp_debug, "\u{f188}")
    ui.sp_debug:ToolTip("Logs what is detected to the console. Only enemy spells are drawn: test against bots.")

    -- what detection saw and what Evade decided, drawn; none of it changes what Evade dodges
    local grp_vis = grp_sim:Parent():Create("Visuals")
    ui.sp_boxes = grp_vis:Switch("World Pins", CFG.DEFAULTS.sp_boxes, "\u{f08d}") -- thumbtack
    ui.sp_boxes:ToolTip("Draws a world-anchored pin with a ground ring on the spell.")
    ui.sp_points = grp_vis:Switch("Particle Points", CFG.DEFAULTS.sp_points, "\u{f192}") -- dot in a circle
    ui.sp_points:ToolTip("Marks particle control points with world crosses.")
    ui.sp_size = grp_vis:Slider("Marker Size", 1, 12, CFG.DEFAULTS.sp_size, "%d u")
    pcall(ui.sp_size.Icon, ui.sp_size, "\u{f31e}") -- expand arrows
    ui.sp_size:ToolTip("World-space size of the particle crosses.")
    ui.sp_labels = grp_vis:Switch("Labels", CFG.DEFAULTS.sp_labels, "\u{f02b}") -- tag
    ui.sp_labels:ToolTip("Adds text labels. This is the only screen-space part.")
    -- off by default: with Evade off it still runs Evade's search, just to draw it
    ui.sp_dodge_debug = grp_vis:Switch("Evade Visuals", CFG.DEFAULTS.sp_dodge_debug, "\u{f06e}") -- eye
    ui.sp_dodge_debug:ToolTip("Draws Evade's search: every grid cell it looked at (red in danger, grey blocked, green safe), the path, the point it walks to now and the safe spot, coloured by what it chose. Works with Evade off, to preview it.")

    local reset = grp_opt:Button("Reset to defaults", reset_tab)
    pcall(reset.Icon, reset, "\u{f0e2}") -- undo
    reset:ToolTip("Resets the Spell Drawer settings to the defaults.")
end

return M
