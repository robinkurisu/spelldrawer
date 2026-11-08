-- Spell Drawer | menu. build() creates the controls; ui holds them by id.

local U = require("spelldrawer_util")

local CFG = U.CFG
local M = { ui = {} }
local ui = M.ui

-- runs from the entry file so the menu is created at a known point, not on require
function M.build(spells)
    local grp_main = Menu.Create(U.SCRIPT, "", "Spells", "Drawer", "Spells")
    local tab_main = grp_main:Parent()
    local tab_root = tab_main:Parent()
    pcall(function() tab_root:Parent():Parent():Icon("\u{f02d}") end)

    local function reset_tab()
        for k, v in pairs(CFG.DEFAULTS) do pcall(ui[k].Set, ui[k], v) end
        for _, s in ipairs(spells) do pcall(s.ui.Set, s.ui, s.name, true) end
        U.log("[RESET] settings back to the defaults")
    end

    ui.sp_enable = grp_main:Switch("Enable", CFG.DEFAULTS.sp_enable, "\u{f011}")
    ui.sp_enable:ToolTip("Draws enemy spell particles and spell entities in the world.")

    -- one row per hero; its ≡ menu holds that hero's ability icons, click one to toggle it
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
        local h, items = heroes[name], {}
        for _, s in ipairs(h.spells) do items[#items + 1] = { s.name, s.image, true } end
        local row = grp_main:Label(name, h.image)
        local select = row:Gear(name .. " Spells", "\u{f0c9}"):MultiSelect("Spells", items, true)
        select:ToolTip("Click an ability to toggle drawing it.")
        for _, s in ipairs(h.spells) do s.ui = select end
    end

    local grp_opt = tab_main:Create("Draw", Enum.GroupSide.Right)

    ui.sp_boxes = grp_opt:Switch("World Pins", CFG.DEFAULTS.sp_boxes)
    ui.sp_boxes:ToolTip("Draws a world-anchored pin with a ground ring on the spell.")
    ui.sp_points = grp_opt:Switch("Particle Points", CFG.DEFAULTS.sp_points)
    ui.sp_points:ToolTip("Marks particle control points with world crosses.")
    ui.sp_land = grp_opt:Switch("Landing Marker", CFG.DEFAULTS.sp_land)
    ui.sp_land:ToolTip("Predicts where the spell lands or stops, and draws its area or impact point.")
    ui.sp_arc = grp_opt:Switch("Trajectory", CFG.DEFAULTS.sp_arc)
    ui.sp_arc:ToolTip("Draws the predicted projectile path: the arc of lobbed spells, the lane of straight shots.")
    ui.sp_labels = grp_opt:Switch("Labels", CFG.DEFAULTS.sp_labels)
    ui.sp_labels:ToolTip("Adds text labels. This is the only screen-space part.")
    ui.sp_size = grp_opt:Slider("Marker Size", 1, 12, CFG.DEFAULTS.sp_size, "%d u")
    ui.sp_size:ToolTip("World-space size of the particle crosses.")
    ui.sp_dist = grp_opt:Slider("Max Distance", 0, 200, CFG.DEFAULTS.sp_dist, "%d m")
    ui.sp_dist:ToolTip("Hides spells further away than this. 0 means no limit.")

    local grp_dbg = tab_main:Create("Debug")
    ui.sp_debug = grp_dbg:Switch("Debug Mode", CFG.DEFAULTS.sp_debug, "\u{f188}")
    ui.sp_debug:ToolTip("Logs what is detected to the console. Only enemy spells are drawn: test against bots.")

    grp_opt:Button("Reset to defaults", reset_tab):ToolTip("Resets the Spell Drawer settings to the defaults.")
end

return M
