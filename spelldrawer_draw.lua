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

local COLOR = Color(255, 85, 85) -- every spell, ally or enemy

local function project(o)
    if not o then return nil end
    local s, on_screen = Render.WorldToScreen(o)
    return on_screen and s or nil
end

local function rgba(c, a)
    return Color(c.r, c.g, c.b, math.floor(math.max(0, math.min(255, a))))
end

local function ground_point(center, radius, a)
    return project(Vector(center.x + cos(a) * radius, center.y + sin(a) * radius, center.z))
end

-- screen points around a ground circle; off-screen points are false so strokes break there
local function ring_pts(center, radius, segments, rot)
    local pts = {}
    for i = 0, segments do pts[i + 1] = ground_point(center, radius, (rot or 0) + i / segments * pi * 2) or false end
    return pts
end

local function stroke(pts, color, thickness)
    for i = 2, #pts do
        local a, b = pts[i - 1], pts[i]
        if a and b then Render.Line(a, b, color, thickness) end
    end
end

local function world_ring(center, radius, color, thickness, segments)
    stroke(ring_pts(center, radius, segments), color, thickness)
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
    if top then Render.Line(base, top, rgba(color, 200), 1) end
    world_ring(o, 10 + 3 * sin(S.rt * 4), rgba(color, 150), 1.5, 20) -- breathing base ring
end

local function text(pos, str, color, size)
    if not font or not str then return end
    size = size or 11
    Render.Text(font, size, str, Vec2(pos.x + 1, pos.y + 1), Color(0, 0, 0, 220))
    Render.Text(font, size, str, pos, color)
end

local PULSE_PERIOD = 1.2 -- seconds per shockwave
local SWEEP_SPEED = 2.5  -- radar sweep, radians per second
local SWEEP_SPAN = 0.9   -- radar sweep trail width, radians
local FLOW_SPEED = 0.8   -- arc dots, path lengths per second
local FLOW_DOTS = 3

local function draw_marker(land, owner, spell, color)
    local t, radius, center = S.rt, U.ability_value(owner, spell, spell.radius_prop, 7), project(land)
    local edge = ring_pts(land, radius, 64)

    -- tinted ground disc
    if center then
        for i = 2, #edge do
            if edge[i - 1] and edge[i] then Render.FilledTriangle({ center, edge[i - 1], edge[i] }, rgba(color, 28)) end
        end
    end

    -- glowing edge: wide faint stroke under a crisp one
    stroke(edge, rgba(color, 45), 7)
    stroke(edge, rgba(color, 230), 2)

    -- shockwave rolling out from the centre, fading as it reaches the edge
    local p = (t / PULSE_PERIOD) % 1
    stroke(ring_pts(land, radius * p, 48), rgba(color, 210 * (1 - p)), 2)

    -- radar sweep: a wedge that brightens toward its leading edge
    if center then
        local lead, steps = t * SWEEP_SPEED, 12
        local prev = ground_point(land, radius, lead - SWEEP_SPAN)
        for i = 1, steps do
            local cur = ground_point(land, radius, lead - SWEEP_SPAN + SWEEP_SPAN * i / steps)
            if prev and cur then Render.FilledTriangle({ center, prev, cur }, rgba(color, 75 * i / steps)) end
            prev = cur
        end
        if prev then Render.Line(center, prev, rgba(color, 220), 2) end

        -- pulsing core
        Render.FilledCircle(center, 7 + 2 * sin(t * 6), rgba(color, 60))
        Render.FilledCircle(center, 3, rgba(color, 255))
    end

    if ui.sp_labels:Get() and center then
        text(Vec2(center.x + 8, center.y - 8), spell.name .. " landing", color)
    end
end

local BOX_STEPS = 16  -- segments per box edge, so edges still draw when one end is off screen
local BOX_HALF_HEIGHT = 40 -- units; a projectile's box is at most this far above and below its path
local HERO_BOX_BELOW = 0.5 -- meters; a hero's lane reaches this far under his feet, like his hitbox
local HERO_BOX_HEIGHT = 2.5 -- meters above his feet, for spells without a `height`
local SCAN_SPEED = 0.7 -- box scan slice, box lengths per second, for spells without a `speed`

local function quad(p1, p2, p3, p4, color)
    if p1 and p2 and p3 and p4 then
        Render.FilledTriangle({ p1, p2, p3 }, color)
        Render.FilledTriangle({ p1, p3, p4 }, color)
    end
end

-- "line" spells: the flight lane as a 3D box with half-size w around the straight path;
-- `body` draws the box, `cap` highlights the end where the projectile stops
local function draw_box(rec, w, color, body, cap, spell)
    local path = rec.path
    local a, b = path[1], path[#path]
    local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return end
    local len3 = math.sqrt(dx * dx + dy * dy + dz * dz)
    -- a bullet shot fades out over CLEAR_DELAY once it has landed (rec.last is its landing time)
    local fade = rec.shot and math.max(0, math.min(1, (rec.last + CFG.CLEAR_DELAY - S.now) / CFG.CLEAR_DELAY)) or 1
    if fade <= 0 then return end
    local function col(alpha) return rgba(color, alpha * fade) end
    local px, py = -dy / len * w, dx / len * w -- horizontal perpendicular to the flight direction
    -- cross-section corners: bottom left, bottom right, top right, top left
    -- height doesn't grow with the width, so a wide lane doesn't sink underground
    local lo, hi = -math.min(w, BOX_HALF_HEIGHT), math.min(w, BOX_HALF_HEIGHT)
    if rec.mod then -- a hero's dash: from just under his feet (his path runs at BODY_Z) to `height`
        lo = -CFG.BODY_Z - HERO_BOX_BELOW * CFG.UNITS_PER_M
        hi = (spell.height or HERO_BOX_HEIGHT) * CFG.UNITS_PER_M - CFG.BODY_Z
    end
    local corners = { { px, py, lo }, { -px, -py, lo }, { -px, -py, hi }, { px, py, hi } }
    local function slice(t)
        local pts = {}
        for k, c in ipairs(corners) do
            pts[k] = project(Vector(a.x + dx * t + c[1], a.y + dy * t + c[2], a.z + dz * t + c[3])) or false
        end
        pts[5] = pts[1]
        return pts
    end

    if body then
        local rails = { {}, {}, {}, {} } -- rails[k][i]: corner k at step i
        for i = 0, BOX_STEPS do
            local s = slice(i / BOX_STEPS)
            for k = 1, 4 do rails[k][i + 1] = s[k] end
        end
        for i = 2, BOX_STEPS + 1 do
            -- fades in over the first quarter, so a box starting at your own camera doesn't fill the screen
            local ramp = math.min(1, (i - 1) / BOX_STEPS * 4)
            for k = 1, 4 do
                local r1, r2 = rails[k], rails[k % 4 + 1]
                quad(r1[i - 1], r1[i], r2[i], r2[i - 1], col(18 * ramp))
                if r1[i - 1] and r1[i] then Render.Line(r1[i - 1], r1[i], col(200 * ramp), 1.5) end
            end
        end
        -- one slice riding with the projectile at its speed; spells without a fire time or speed loop it
        local t
        if rec.rt0 and spell.speed then
            t = (S.rt - rec.rt0) * spell.speed / len3
        else
            t = (S.rt * (spell.speed and spell.speed / len3 or SCAN_SPEED)) % 1
        end
        if t <= 1 then stroke(slice(t), col(230), 2) end
    end

    local e = slice(1)
    if cap then
        quad(e[1], e[2], e[3], e[4], col(60 + 40 * sin(S.rt * 6)))
        stroke(e, col(45), 7)
        if ui.sp_labels:Get() and e[1] then text(Vec2(e[1].x + 8, e[1].y - 8), spell.name .. " hit", col(255)) end
    end
    if body or cap then stroke(e, col(240), 2) end
end

-- glowing flight path that strengthens toward the end, with dots flowing along it
local function draw_path(path, color)
    local pts, n = {}, #path
    for i, pt in ipairs(path) do pts[i] = project(pt) or false end
    for i = 2, n do
        local a, b = pts[i - 1], pts[i]
        if a and b then
            local k = i / n
            Render.Line(a, b, rgba(color, 50 * k), 7)
            Render.Line(a, b, rgba(color, 90 + 140 * k), 2)
        end
    end
    for j = 0, FLOW_DOTS - 1 do
        local u = ((S.rt * FLOW_SPEED + j / FLOW_DOTS) % 1) * (n - 1)
        local i, f = math.floor(u) + 1, u % 1
        local a, b = pts[i], pts[i + 1]
        -- interpolated between path points so dots glide even along a lane with few points
        local sp = a and b and Vec2(a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f) or a
        if sp then
            Render.FilledCircle(sp, 6, rgba(color, 70))
            Render.FilledCircle(sp, 2.5, rgba(color, 255))
        end
    end
end

-- "aura" spells: a self buff, drawn as a pulsing double ring around the hero while its modifier is on
local function draw_aura(rec, owner, spell, color)
    if S.now - (rec.mod_at or -math.huge) > CFG.SCAN_EVERY * 1.5 then return end -- buff is over
    local o = valid(rec.caster) and try(rec.caster, "get_origin")
    if not o then return end
    local r = U.ability_value(owner, spell, spell.radius_prop, spell.radius or 1.5)
    local p = (S.rt / PULSE_PERIOD) % 1
    stroke(ring_pts(o, r, 48), rgba(color, 45), 7)
    stroke(ring_pts(o, r, 48), rgba(color, 230), 2)
    world_ring(Vector(o.x, o.y, o.z + CFG.HEAD), r * 0.8, rgba(color, 160), 1.5, 40)
    world_ring(o, r * (1 + 0.4 * p), rgba(color, 200 * (1 - p)), 2, 48)
    local c = project(o)
    if ui.sp_labels:Get() and c then text(Vec2(c.x + r * 0.2 + 8, c.y + 4), spell.name, color) end
end

local function draw_motion(rec, owner, spell, color)
    if spell.motion == "aura" then return draw_aura(rec, owner, spell, color) end
    if spell.motion == "line" then
        if rec.path then
            draw_box(rec, (spell.width or 0.75) * CFG.UNITS_PER_M, color, ui.sp_arc:Get(), ui.sp_land:Get(), spell)
        end
        return
    end
    if ui.sp_arc:Get() and rec.path then draw_path(rec.path, color) end
    local land = rec.land or rec.warning
    if ui.sp_land:Get() and land then draw_marker(land, owner, spell, color) end
end

function D.draw_entity(rec, lp)
    local e, owner, spell = rec.ent or rec.caster, rec.owner, rec.spell
    if not valid(owner) or not spell then return end

    -- enemy spells always draw; ally spells (your own included) only in Debug Mode
    local same = handle(owner) == handle(lp) or HERO_LIB.is_same_team(lp, owner) == true
    if same and not ui.sp_debug:Get() then return end
    -- once an owner's shots of a line spell arrive as bullets, draw only those exact shots;
    -- the particle-tracked copy of the same projectile would draw a second, rougher box
    if spell.bullet_owners and spell.bullet_owners[handle(owner)] and not rec.shot then return end

    local o
    if valid(e) then o = try(e, "get_origin") end
    if not o and rec.warning then o = rec.warning end
    if not o then
        local first = rec.particles and rec.particles[1]
        local cp = first and first.control_points and first.control_points[1]
        o = cp and cp.origin
    end
    if not o then o = rec.land end -- bullet shots have no entity or particles, only their lane
    if not o then return end
    local md = ui.sp_dist:Get() or 0
    if md > 0 then
        local d = U.dist_to_me(o)
        if d and d / CFG.UNITS_PER_M > md then return end
    end

    local color = COLOR
    if spell.motion then pcall(draw_motion, rec, owner, spell, color) end
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
