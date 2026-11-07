-- Spell Drawer | world-space drawing of detected spell groups

local U = require("spelldrawer_util")
local ui = require("spelldrawer_menu").ui

local CFG, S = U.CFG, U.state
local try, valid, handle, fmt = U.try, U.valid, U.handle, U.fmt
local cos, sin, pi = math.cos, math.sin, math.pi

local D = {}

local font
do
    local ok, h = pcall(Render.LoadFont, "Tahoma", Enum.FontCreate and Enum.FontCreate.FONTFLAG_ANTIALIAS or 16, 700)
    if ok then font = h end
end

local ENEMY = Color(255, 85, 85)
local ALLY = Color(90, 190, 255)

local function project(o)
    if not o then return nil end
    local s, on_screen = Render.WorldToScreen(o)
    return on_screen and s or nil
end

local function world_ring(center, radius, color, thickness, segments)
    local prev
    for i = 0, segments do
        local a = (i / segments) * pi * 2
        local sp = project(Vector(center.x + cos(a) * radius, center.y + sin(a) * radius, center.z))
        if sp and prev then Render.Line(prev, sp, color, thickness) end
        prev = sp
    end
end

local function world_cross(p, size, color, thickness)
    local axes = { { size, 0, 0 }, { 0, size, 0 }, { 0, 0, size } }
    for _, axis in ipairs(axes) do
        local a = project(Vector(p.x - axis[1], p.y - axis[2], p.z - axis[3]))
        local b = project(Vector(p.x + axis[1], p.y + axis[2], p.z + axis[3]))
        if a and b then Render.Line(a, b, color, thickness or 1) end
    end
end

local function world_pin(o, color)
    local base = project(o)
    if not base then return end
    local top = project(Vector(o.x, o.y, o.z + CFG.HEAD))
    if top then Render.Line(base, top, Color(color.r, color.g, color.b, 200), 1) end
    world_ring(o, 10, Color(color.r, color.g, color.b, 140), 1, 16)
end

local function text(pos, str, color, size)
    if not font or not str then return end
    size = size or 11
    Render.Text(font, size, str, Vec2(pos.x + 1, pos.y + 1), Color(0, 0, 0, 220))
    Render.Text(font, size, str, pos, color)
end

local function spell_radius(owner, spell)
    local ab = try(owner, "get_ability", spell.ability)
    local r = ab and tonumber(try(ab, "get_scaled_property", spell.radius_prop))
    if r and r < 50 then r = r * CFG.UNITS_PER_M end
    return r or (7 * CFG.UNITS_PER_M)
end

local function draw_marker(land, owner, spell, color)
    local radius = spell_radius(owner, spell)
    world_ring(land, radius, Color(color.r, color.g, color.b, 220), 2, 64)
    world_ring(land, radius * 0.5, Color(color.r, color.g, color.b, 90), 1, 48)
    world_cross(land, 20, Color(color.r, color.g, color.b, 240), 2)

    if ui.sp_labels:Get() then
        local center = project(land)
        if center then text(Vec2(center.x + 8, center.y - 8), spell.name .. " landing", color) end
    end
end

local function draw_landing(rec, owner, spell, color)
    if ui.sp_arc:Get() and rec.path then
        local c, prev = Color(color.r, color.g, color.b, 120), nil
        for _, pt in ipairs(rec.path) do
            local sp = project(pt)
            if sp and prev then Render.Line(prev, sp, c, 1) end
            prev = sp
        end
    end

    local land = rec.land or rec.warning
    if land and ui.sp_land:Get() then draw_marker(land, owner, spell, color) end
end

function D.draw_entity(rec, lp)
    local e, owner, spell = rec.ent or rec.caster, rec.owner, rec.spell
    if not valid(owner) or not spell then return end

    local self_cast = handle(owner) == handle(lp)
    local same = self_cast or HERO_LIB.is_same_team(lp, owner) == true
    if self_cast then
        if not ui.sp_local:Get() then return end
    elseif same then
        if not ui.sp_ally:Get() then return end
    elseif not ui.sp_enemy:Get() then
        return
    end

    local o
    if valid(e) then o = try(e, "get_origin") end
    if not o and rec.warning then o = rec.warning end
    if not o then
        local first = rec.particles and rec.particles[1]
        local cp = first and first.control_points and first.control_points[1]
        o = cp and cp.origin
    end
    if not o then return end
    local md = ui.sp_dist:Get() or 0
    if md > 0 then
        local d = U.dist_to_me(o)
        if d and d / CFG.UNITS_PER_M > md then return end
    end

    local color = same and ALLY or ENEMY
    if spell.landing then pcall(draw_landing, rec, owner, spell, color) end
    if ui.sp_boxes:Get() then world_pin(o, color) end
    if ui.sp_labels:Get() then
        local base = project(o)
        if base then text(Vec2(base.x + 8, base.y - 10), fmt("%s %.1fs", spell.name, S.now - rec.first), color) end
    end

    if not ui.sp_points:Get() then return end
    local size = (ui.sp_size:Get() or CFG.DEFAULTS.sp_size) + 2
    local count, labels = 0, 0
    for _, p in ipairs(rec.particles or {}) do
        if count >= CFG.MAX_CP then break end
        local named = false
        for _, cp in ipairs(p.control_points or {}) do
            if count >= CFG.MAX_CP then break end
            count = count + 1
            world_cross(cp.origin, size, Color(color.r, color.g, color.b, 210), 1)
            if ui.sp_labels:Get() and not named and labels < 3 then
                named = true
                labels = labels + 1
                local sp = project(cp.origin)
                if sp then text(Vec2(sp.x + 6, sp.y - 6), U.short_name(p.name), color) end
            end
        end
    end
end

return D
