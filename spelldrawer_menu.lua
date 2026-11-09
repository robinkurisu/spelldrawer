-- Spell Drawer | menu. build() creates the controls; ui holds them by id.

local U = require("spelldrawer_util")

local CFG = U.CFG
local M = { ui = {} }
local ui = M.ui

-- runs from the entry file so the menu is created at a known point, not on require
function M.build(spells)
    -- tabs line up, and cards stack, in the order they are made: the Evade tab first (General, with
    -- Enable and the Evade switch, on top), the hero list in its own Spells tab second, as it grows,
    -- and Debug always last
    local grp_gen = Menu.Create(U.SCRIPT, "", "Evade", "Evade", "General")
    local tab_main = grp_gen:Parent()
    local tab_root = tab_main:Parent()
    pcall(function() tab_root:Parent():Parent():Icon("\u{f02d}") end)
    local grp_main = Menu.Create(U.SCRIPT, "", "Evade", "Spells", "Spells")

    ui.sp_enable = grp_gen:Switch("Enable", CFG.DEFAULTS.sp_enable, "\u{f011}")
    ui.sp_enable:ToolTip("Draw enemy spells.")
    ui.sp_dodge = grp_gen:Switch("Evade", CFG.DEFAULTS.sp_dodge, "\u{f554}")
    ui.sp_dodge:ToolTip("Auto walk, dash or parry out of spells.")

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
        select:ToolTip("Click an ability to toggle it.")
        for _, s in ipairs(h.spells) do s.ui = select end
    end

    -- beside the heroes: what Evade may use to get you out, items for now (your hero's own evade
    -- abilities to join them); ticked is used when walking and dashing can't make it, unticked never
    local grp_tools = grp_main:Parent():Create("Evade Tools", Enum.GroupSide.Right)
    local list = {}
    for _, it in ipairs(CFG.EVADE_ITEMS) do list[#list + 1] = { it.name, it.image, true } end
    ui.sp_evade_items = grp_tools:MultiSelect("Items", list, true)
    pcall(ui.sp_evade_items.Icon, ui.sp_evade_items, "\u{f290}") -- shopping bag
    ui.sp_evade_items:ToolTip("Used when walk and dash can't escape.")

    local grp_opt = tab_main:Create("Draw", Enum.GroupSide.Right)

    -- these two only hide the drawing: Evade dodges the areas either way
    ui.sp_land = grp_opt:Switch("Landing Marker", CFG.DEFAULTS.sp_land, "\u{f3c5}") -- map marker
    ui.sp_land:ToolTip("Draw landing areas.")
    ui.sp_arc = grp_opt:Switch("Trajectory", CFG.DEFAULTS.sp_arc, "\u{f4d7}") -- route
    ui.sp_arc:ToolTip("Draw shot paths.")
    ui.sp_dist = grp_opt:Slider("Max Distance", 0, 200, CFG.DEFAULTS.sp_dist, "%d m")
    pcall(ui.sp_dist.Icon, ui.sp_dist, "\u{f547}") -- ruler
    ui.sp_dist:ToolTip("Draw and Evade range. 0 = no limit.")
    local reset = grp_opt:Button("Reset Draws", function()
        for _, k in ipairs({ "sp_land", "sp_arc", "sp_dist" }) do
            pcall(ui[k].Set, ui[k], CFG.DEFAULTS[k])
        end
        U.log("[RESET] draw settings back to the defaults")
    end)
    reset:ToolTip("Reset all drawing settings.")

    -- under General: the timings and room Evade plans with, to tinker with
    local grp_tune = tab_main:Create("Tuning")
    ui.sp_react = grp_tune:Slider("Reaction Time", 0.0, 0.3, CFG.DEFAULTS.sp_react, "%.2f s")
    pcall(ui.sp_react.Icon, ui.sp_react, "\u{f0e7}") -- bolt
    ui.sp_react:ToolTip("Delay added to every walk and dash. Lower dashes more, but may cut it short.")
    ui.sp_margin = grp_tune:Slider("Safety Margin", 0.25, 3.0, CFG.DEFAULTS.sp_margin, "%.2f m")
    pcall(ui.sp_margin.Icon, ui.sp_margin, "\u{f3ed}") -- shield
    ui.sp_margin:ToolTip("Room kept past an area's edge.")
    ui.sp_parry_lead = grp_tune:Slider("Parry Lead", 0.05, 0.75, CFG.DEFAULTS.sp_parry_lead, "%.2f s")
    pcall(ui.sp_parry_lead.Icon, ui.sp_parry_lead, "\u{f252}") -- hourglass
    ui.sp_parry_lead:ToolTip("Counterspell parry this long before the hit. It blocks for 0.8 s.")
    local reset_tune = grp_tune:Button("Reset Tuning", function()
        for _, k in ipairs({ "sp_react", "sp_margin", "sp_parry_lead" }) do
            pcall(ui[k].Set, ui[k], CFG.DEFAULTS[k])
        end
        U.log("[RESET] tuning back to the defaults")
    end)
    reset_tune:ToolTip("Reset all tuning settings.")

    -- the Debug tab, made last so it stays last: the simulator, the logging beside it, the debug drawings below
    local grp_sim = Menu.Create(U.SCRIPT, "", "Evade", "Debug", "Simulator")
    ui.sp_sim = grp_sim:Switch("Spell Simulator", CFG.DEFAULTS.sp_sim, "\u{f05b}")
    ui.sp_sim:ToolTip("Cast test spells at you.")
    ui.sp_sim_gap = grp_sim:Slider("Interval", 0.5, 5.0, CFG.DEFAULTS.sp_sim_gap, "%.1f s")
    pcall(ui.sp_sim_gap.Icon, ui.sp_sim_gap, "\u{f2f2}") -- stopwatch
    ui.sp_sim_gap:ToolTip("Seconds between test spells.")
    ui.sp_sim_cd = grp_sim:Switch("Item Cooldowns", CFG.DEFAULTS.sp_sim_cd, "\u{f253}") -- hourglass end
    ui.sp_sim_cd:ToolTip("Counterspell goes on its 23 s cooldown after a test block, as in a real match.")

    local grp_log = grp_sim:Parent():Create("Logging", Enum.GroupSide.Right)
    ui.sp_debug = grp_log:Switch("Debug Mode", CFG.DEFAULTS.sp_debug, "\u{f188}")
    ui.sp_debug:ToolTip("Log detections to the console.")

    -- what detection saw and what Evade decided, drawn; none of it changes what Evade dodges
    local grp_vis = grp_sim:Parent():Create("Visuals")
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
        for _, k in ipairs({ "sp_dodge_debug", "sp_boxes", "sp_points", "sp_size", "sp_labels" }) do
            pcall(ui[k].Set, ui[k], CFG.DEFAULTS[k])
        end
        U.log("[RESET] visuals back to the defaults")
    end)
    reset_vis:ToolTip("Reset all visual settings.")
end

return M
