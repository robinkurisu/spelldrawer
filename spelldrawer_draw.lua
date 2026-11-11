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

local COLOR = Color(255, 85, 85) -- every enemy spell

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
        if a and b then Render.Line(a, b, color, thickness) end
    end
end

local function world_pin(o, color)
    local base = project(o)
    if not base then return end
    local top = project(Vector(o.x, o.y, o.z + CFG.HEAD))
    if top then Render.Line(base, top, rgba(color, 200), 1) end
    world_ring(o, 10 + 3 * sin(S.rt * 4), rgba(color, 150), 1.5, 20) -- breathing base ring
end

local function text(pos, str, color)
    if not font or not str then return end
    Render.Text(font, 11, str, Vec2(pos.x + 1, pos.y + 1), Color(0, 0, 0, 220))
    Render.Text(font, 11, str, pos, color)
end

-- a filled fan from `center` to the `edge` points (no fill without a center), with a glowing edge:
-- a wide faint stroke under a crisp one
local function fan(center, edge, color, fill)
    if center then
        for i = 2, #edge do
            if edge[i - 1] and edge[i] then Render.FilledTriangle({ center, edge[i - 1], edge[i] }, rgba(color, fill)) end
        end
    end
    stroke(edge, rgba(color, 45), 7)
    stroke(edge, rgba(color, 230), 2)
end

local BANDS = 6 -- rings a ground fan is filled in when its centre is off screen

-- a filled ground sector round `center` (world), `radius` out, from angle a0 to a1 in `steps`, drawn
-- as fan() draws it. With the centre off screen (a caster between you and the camera) fan() fills
-- nothing, so it is filled in rings out from the centre instead, each piece where it is on screen.
-- Returns the centre and edge on screen (false where off it)
local function ground_fan(center, radius, a0, a1, steps, color, fill)
    local function arc(r)
        local pts = {}
        for i = 0, steps do pts[i + 1] = ground_point(center, r, a0 + (a1 - a0) * i / steps) or false end
        return pts
    end
    local c, edge = project(center), arc(radius)
    if not c then
        local col, inner = rgba(color, fill), arc(radius / BANDS)
        for k = 2, BANDS do
            local outer = k == BANDS and edge or arc(radius * k / BANDS)
            for i = 2, #edge do
                local p1, p2, p3, p4 = inner[i - 1], outer[i - 1], outer[i], inner[i]
                if p1 and p2 and p3 and p4 then
                    Render.FilledTriangle({ p1, p2, p3 }, col)
                    Render.FilledTriangle({ p1, p3, p4 }, col)
                end
            end
            inner = outer
        end
    end
    fan(c, edge, color, fill)
    return c, edge
end

-- a danger area as drawn, for the dodge: "circle" (x, y, z, radius r), "lane" (centre line from
-- x, y, z to bx, by, bz, half-width r) or "cone" (from x, y, z, reach r, aim yaw, half angle half).
-- When it hits, where known: `at`, the S.now it goes off, or for a lane the shot's position now
-- (px, py), its `speed` in units/s and, for a wind-up, the `delay` before it leaves. Neither: it is a
-- danger for as long as it is drawn, and `urgent` when that can be any moment now. A circle with
-- `grow` (units/s) is a wave rolling out from its centre, at its edge at `at`
local function zone(z) S.zones[#S.zones + 1] = z end

local sim = false -- drawing a simulated spell: shown whatever Landing Marker and Trajectory say

-- what the two Draw switches show. Each only hides the drawing: the danger area is still handed to
-- Evade first. Areas on the ground (landings, rings, cones, the ring on you) are Landing Marker's;
-- paths (lobs, lanes, a dash's lane, the line from a caster to you) are Trajectory's
local function areas() return sim or ui.sp_land:Get() end
local function paths() return sim or ui.sp_arc:Get() end

local err_at = -math.huge
-- drawing runs every frame: log a failure in Debug Mode, at most once a second
function D.report(ok, err)
    if ok or not ui.sp_debug:Get() or S.rt - err_at < 1 then return end
    err_at = S.rt
    U.log("draw error: %s", err)
end

local PULSE_PERIOD = 1.2 -- seconds per shockwave
local SWEEP_SPEED = 2.5  -- radar sweep, radians per second
local SWEEP_SPAN = 0.9   -- radar sweep trail width, radians
local FLOW_SPEED = 0.8   -- arc dots, path lengths per second
local FLOW_DOTS = 3

-- `at`: the S.now the area goes off, when known
local function draw_marker(land, owner, spell, color, at)
    local t, radius, center = S.rt, U.ability_value(owner, spell, spell.radius_prop, spell.radius or 7), project(land)
    zone({ kind = "circle", x = land.x, y = land.y, z = land.z, r = radius, at = at })
    if not areas() then return end -- hidden, but Evade still dodges it
    ground_fan(land, radius, 0, 2 * pi, 64, color, 28) -- tinted ground disc

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
-- whether you wear a modifier whose name contains `key`
local function on_me(key)
    local mods = S.me and try(S.me, "get_modifiers")
    for _, m in ipairs(type(mods) == "table" and mods or {}) do
        local n = try(m, "get_name")
        if n and n:lower():find(key, 1, true) then return true end
    end
    return false
end

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
    -- how far along the lane the projectile or hero is this frame (the path moves only on a sample)
    local live, along = not rec.shot and rec.pos, nil
    if live then
        local ex, ey, ez = b.x - a.x, b.y - a.y, b.z - a.z
        along = ((live.x - a.x) * ex + (live.y - a.y) * ey + (live.z - a.z) * ez) / math.max(1, ex * ex + ey * ey + ez * ez)
        -- a hero's dash starts on him now, not where the last sample saw him up to 0.05 s back
        if rec.mod and along < 1 then a = live end
    end
    local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return end
    local len3 = math.sqrt(dx * dx + dy * dy + dz * dz)
    -- a bullet shot fades out over CLEAR_DELAY once it has landed (rec.last is its landing time)
    local fade = rec.shot and math.max(0, math.min(1, (rec.last + CFG.CLEAR_DELAY - S.now) / CFG.CLEAR_DELAY)) or 1
    if fade <= 0 then return end
    -- a shot fading out has already landed: drawn, but no longer a danger
    if fade >= 1 then
        -- where the shot is now: a bullet by its speed since firing, else where it was seen; a
        -- hero's dash lane starts on him
        local p = live or a
        if rec.rt0 and spell.speed then
            local u = math.min(1, (S.rt - rec.rt0) * spell.speed / len3)
            p = Vector(a.x + dx * u, a.y + dy * u, a.z + dz * u)
        end
        -- a shot still winding up leaves `delay` from now, from the caster; a dash still being charged
        -- (`charge_max`) leaves at its `release` into the charge, never sooner than now, or without
        -- one has no hit time: a danger for as long as it is drawn, and `urgent` from `release_from`
        -- into the charge, when he can let go any moment
        local delay = rec.fires_at and math.max(0, rec.fires_at - S.now)
        if rec.charging and spell.release then
            delay = math.max(0, (rec.charge_at or rec.first) + spell.release - S.now)
        end
        -- `hit_modifier` on you: it already has you (Abrams' drag), nothing left to dodge or parry, for
        -- the rest of this cast: the drag ends before the charge does, and Evade parried you "in the
        -- air" 0.45 s after it began
        if spell.hit_modifier and not rec.had_you and on_me(spell.hit_modifier) then rec.had_you = true end
        if not rec.had_you then
            zone({ kind = "lane", x = a.x, y = a.y, z = a.z, bx = b.x, by = b.y, bz = b.z, r = w,
                   px = p.x, py = p.y, speed = (not rec.charging or spell.release) and (spell.speed or rec.speed) or nil,
                   delay = delay,
                   -- he has let go (`strike`): it lands all along the lane then, no longer any moment
                   at = rec.charging and rec.strike_at or nil,
                   urgent = rec.charging and spell.release_from and not rec.strike_at
                       and S.now >= (rec.charge_at or rec.first) + spell.release_from or nil })
        end
    end
    if not (body or cap) then return end -- hidden, but Evade still dodges it
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
        -- one slice riding with the projectile: where it is, or for a bullet its speed since firing;
        -- a hero's dash, whose lane starts on him, loops it
        local t
        if rec.rt0 and spell.speed then
            t = (S.rt - rec.rt0) * spell.speed / len3
        elseif along and not rec.mod then
            t = along
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
    stroke(e, col(240), 2)
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

local DASH_STEPS = 16 -- segments per lane edge, so edges still draw when one end is off screen

-- an "aura" dash (`dash_range`): the rest of the dash on the floor, a lane as wide as the ring that
-- rides on him like a line dash's lane, from just behind him to a ring's radius past where it ends;
-- the range counts from where the dash began, so the far end stays put while he travels
local function draw_dash_lane(rec, o, owner, spell, r, color)
    rec.dash_from = rec.dash_from or Vector(o.x, o.y, o.z)
    rec.dash_t0 = rec.dash_t0 or S.now
    local from = rec.dash_from
    -- once he has moved, the way he went; until then where he aims (a targeted dash goes at its target)
    local dx, dy = o.x - from.x, o.y - from.y
    if dx * dx + dy * dy < CFG.UNITS_PER_M ^ 2 then
        local f = U.aim_dir(rec.caster)
        if not f then return end
        dx, dy = f.x, f.y
    end
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then return end
    dx, dy = dx / len, dy / len
    local range = U.ability_value(owner, spell, spell.dash_range_prop, spell.dash_range)
    -- still to go, to where the slash is centred `land_offset` past the dash's end
    local togo = math.max(0, range - ((o.x - from.x) * dx + (o.y - from.y) * dy))
        + (spell.land_offset or 0) * CFG.UNITS_PER_M
    -- the slash is carried along the rest of the dash, so the danger is the lane, reaching you at her
    -- dash speed after any wind-up left. Without a speed: no time to get out of its way
    local speed = spell.dash_speed
    zone({ kind = "lane", x = o.x, y = o.y, z = o.z, bx = o.x + dx * togo, by = o.y + dy * togo, bz = o.z, r = r,
           px = o.x, py = o.y, speed = speed, at = not speed and S.now or nil,
           delay = rec.fires_at and math.max(0, rec.fires_at - S.now) })
    -- Debug Mode: how far and how fast the dash really goes, against its vdata speed
    if ui.sp_debug:Get() and S.now - (rec.dash_log or -1) >= 0.1 then
        rec.dash_log = S.now
        local moved = math.sqrt((o.x - from.x) ^ 2 + (o.y - from.y) ^ 2) / CFG.UNITS_PER_M
        U.log("%s dash: %.1f m from where first seen, %.2f s on%s", spell.name, moved, S.now - rec.dash_t0,
            speed and fmt(" (DashSpeed covers that in %.2f s)", moved * CFG.UNITS_PER_M / speed) or "")
    end
    if not paths() then return end -- hidden, but Evade still dodges it
    local left, right = {}, {}
    for i = 0, DASH_STEPS do
        local d = -r + (togo + 2 * r) * i / DASH_STEPS
        local x, y = o.x + dx * d, o.y + dy * d
        left[i + 1] = project(Vector(x - dy * r, y + dx * r, o.z + 4)) or false
        right[i + 1] = project(Vector(x + dy * r, y - dx * r, o.z + 4)) or false
    end
    for i = 2, DASH_STEPS + 1 do quad(left[i - 1], left[i], right[i], right[i - 1], rgba(color, 22)) end
    for _, edge in ipairs({ left, right }) do
        stroke(edge, rgba(color, 45), 7)
        stroke(edge, rgba(color, 230), 2)
    end
    stroke({ left[1], right[1] }, rgba(color, 230), 2)
    local n = DASH_STEPS + 1
    stroke({ left[n], right[n] }, rgba(color, 230), 2)
end

-- "aura" spells: a self buff, drawn as a pulsing double ring around the hero while its modifier is on
local function draw_aura(rec, owner, spell, color)
    -- buff is over. Widened past SCAN_EVERY * 1.5 so it cannot clip TAIL_GRACE: a modifier sighting
    -- is up to SCAN_EVERY stale, and CLEAR_DELAY (0.5) drops the group at about the same moment
    if S.now - (rec.mod_at or -math.huge) > CFG.SCAN_EVERY * 2 then return end
    local fires -- a delayed effect goes off at its end, or now in its first window
    if spell.show_first or spell.show_last then
        -- a delayed effect: only its ends, counted from when the modifier was first seen; the
        -- freshness check above keeps the tail up past the moment it marks
        local dur = U.ability_number(owner, spell, spell.duration_prop) or spell.duration or math.huge
        local elapsed = S.now - rec.first
        if elapsed > (spell.show_first or 0) and elapsed < dur - (spell.show_last or 0) then return end
        fires = elapsed <= (spell.show_first or 0) and S.now or rec.first + dur
    end
    fires = fires or rec.fires_at -- a dash's ring, seen winding up: it goes off when she leaves
    -- a wind-up seen by its clip (`charge_anim`): it goes off `release` into it, then has no hit time
    local lingers -- it goes off at `release`, and is still there after: a parry outlasted (Singularity)
    if not fires and spell.release then
        if rec.charge_until and S.now < rec.charge_until then
            fires, lingers = (rec.charge_at or rec.first) + spell.release, spell.lingers ~= false
        elseif spell.lingers == false then
            return -- a blast (Concussive Combustion): nothing left once it has gone off
        end
    end
    local o = valid(rec.caster) and try(rec.caster, "get_origin")
    if not o then return end
    local r = U.ability_value(owner, spell, spell.radius_prop, spell.radius or 1.5)
    if spell.dash_range_prop or spell.dash_range then draw_dash_lane(rec, o, owner, spell, r, color) end
    -- `hit_modifier` on you: it already has you (Singularity's lift), no dash or walk gets you out
    if not (spell.hit_modifier and on_me(spell.hit_modifier)) then
        zone({ kind = "circle", x = o.x, y = o.y, z = o.z, r = r, at = fires, lingers = lingers, big = spell.big_area })
    end
    if not areas() then return end -- hidden, but Evade still dodges it
    local p = (S.rt / PULSE_PERIOD) % 1
    fan(nil, ring_pts(o, r, 48), color)
    world_ring(Vector(o.x, o.y, o.z + CFG.HEAD), r * 0.8, rgba(color, 160), 1.5, 40)
    world_ring(o, r * (1 + 0.4 * p), rgba(color, 200 * (1 - p)), 2, 48)
    local c = project(o)
    if ui.sp_labels:Get() and c then text(Vec2(c.x + r * 0.2 + 8, c.y + 4), spell.name, color) end
end

local CONE_STEPS = 24
local cone_logged_at = -math.huge

-- "cone" spells: a fan on the ground in front of the hero, turning with his aim, while he winds up
local function draw_cone(rec, owner, spell, color)
    -- the fan runs while the trigger (swing particle, modifier or cast delay) is still being seen,
    -- then not past the next scans
    -- or started by his clip (`charge_anim`), up until it hits, that clip's time after it
    local charged = rec.charge_until and S.now < rec.charge_until
    -- and over with it: the poll keeps its mod_at fresh through it, and read as a new swing past its end
    -- it drew Ground Strike a second time, 0.69 s after his clip
    if not charged and rec.charge_at then return end
    if not charged and S.now - (rec.cone_seen or rec.mod_at or -math.huge) > CFG.SCAN_EVERY * 1.5 then return end
    local since = S.now - (charged and rec.charge_at or rec.cone_at or rec.mod_at or -math.huge)
    -- the swing particle outlives the hit; `cone_time` ends the fan when the spell goes off
    local hit = charged and rec.hit_in or spell.cone_time
    if hit and since > hit then return end
    local hero = rec.caster
    -- a dive's fan (Ground Strike) stays where he will land, facing his aim at the clip
    local dive = charged and rec.dive
    local o = dive and dive.o or valid(hero) and try(hero, "get_origin")
    if not o then return end
    local f, src = U.aim_dir(hero)
    if dive then f, src = Vector(math.cos(dive.yaw), math.sin(dive.yaw), 0), "his aim at the clip" end
    if not f then return end
    local r = U.ability_value(owner, spell, spell.range_prop, spell.range or 5)
    if ui.sp_debug:Get() and S.now - cone_logged_at > 1 then
        cone_logged_at = S.now
        -- "default" means the caster's ability didn't read, so no upgrade is in the reach
        U.log("%s cone aimed by %s, %.1f m (%s)", spell.name, src, r / CFG.UNITS_PER_M,
            U.ability_number(owner, spell, spell.range_prop) and "read" or "default")
    end
    o = Vector(o.x, o.y, o.z + 4) -- just above the floor so it doesn't flicker into it
    local half = math.rad((U.ability_number(owner, spell, spell.angle_prop) or spell.angle or 60) / 2)
    local yaw = math.atan(f.y, f.x) -- flat: a ground fan turns with his aim but doesn't tilt
    zone({ kind = "cone", x = o.x, y = o.y, z = o.z, r = r, yaw = yaw, half = half,
           at = hit and S.now - since + hit })
    if not areas() then return end -- hidden, but Evade still dodges it
    local function arc(radius)
        local pts = {}
        for i = 0, CONE_STEPS do pts[i + 1] = ground_point(o, radius, yaw - half + 2 * half * i / CONE_STEPS) or false end
        return pts
    end

    local c = ground_fan(o, r, yaw - half, yaw + half, CONE_STEPS, color, 30)
    -- its two sides, in pieces, so they show with the caster off screen too
    for _, a in ipairs({ yaw - half, yaw + half }) do
        local side = {}
        for k = 0, BANDS do side[k + 1] = ground_point(o, r * k / BANDS, a) or false end
        stroke(side, rgba(color, 220), 2)
    end
    -- a wave rolling out from the hero to the cone's reach
    local p = (S.rt / PULSE_PERIOD) % 1
    stroke(arc(r * p), rgba(color, 210 * (1 - p)), 2)
    if ui.sp_labels:Get() and c then text(Vec2(c.x + 8, c.y - 8), spell.name, color) end
end

-- Unit Collision: a shot that stops on the first unit in its way (`blocked_by`: Grapple Arm on a
-- hero, your troopers or a neutral creep) ends at the first one ahead of it on its lane, within its
-- width and the unit's body. Behind that unit you are safe from it. The lane drawn and dodged is
-- the original's up to there (a stand-in that reads the rest from it); nil when nothing is in the way
local UNIT_R = 20 -- units: a unit's half-width
local function blocked_lane(rec, owner, spell, w)
    local path = rec.path
    local a, b = path[1], path[#path]
    local ex, ey, ez = b.x - a.x, b.y - a.y, b.z - a.z
    local len2 = ex * ex + ey * ey
    if len2 < 1 then return nil end
    -- from where the shot is now: a unit it has already passed didn't stop it
    local t0 = 0
    if rec.pos and not rec.shot then
        t0 = ((rec.pos.x - a.x) * ex + (rec.pos.y - a.y) * ey) / len2
    elseif rec.shot and rec.rt0 and spell.speed then
        t0 = (S.rt - rec.rt0) * spell.speed / math.sqrt(len2 + ez * ez)
    end
    -- a shot that got to the unit it was cut at stopped there for good. Reckoned from its flight time
    -- it would fly on, past that unit, and the whole lane came back: Counterspell went off on a hook
    -- that had caught a Bebop 8 m in front of you (2026-11-10)
    if rec.cut_t and t0 >= rec.cut_t then rec.stopped = rec.stopped or rec.cut_t end
    -- his own heroes (not yours: you only see enemies' shots) nearer him than `ally_pass` it goes through
    local so = spell.ally_pass and try(owner, "get_origin")
    local pass2 = so and (spell.ally_pass * CFG.UNITS_PER_M) ^ 2
    local best, by = rec.stopped, nil
    for _, u in ipairs(rec.stopped and {} or U.blockers(owner, spell.blocked_by, ui.sp_debug:Get())) do
        local q = try(u.e, "get_origin")
        if q and pass2 and u.kind == "hero" and not u.mine and (q.x - so.x) ^ 2 + (q.y - so.y) ^ 2 < pass2 then q = nil end
        local t = q and ((q.x - a.x) * ex + (q.y - a.y) * ey) / len2
        if t and t > t0 and t < 1 and (not best or t < best) then
            local px, py = a.x + ex * t - q.x, a.y + ey * t - q.y
            if px * px + py * py <= (w + UNIT_R) ^ 2 then best, by = t, u end
        end
    end
    rec.cut_t = best
    if not best then return nil end
    if by and ui.sp_debug:Get() and rec.blocked_by ~= by.e then
        rec.blocked_by = by.e
        U.log("%s stopped by a %s %.1f m along its lane", spell.name, by.kind, best * math.sqrt(len2) / CFG.UNITS_PER_M)
    end
    local cut = setmetatable({}, { __index = rec })
    cut.path = { a, Vector(a.x + ex * best, a.y + ey * best, a.z + ez * best) }
    return cut
end

-- A lob that bursts on the first hero it meets (`blocked_by` on an "arc" shot: Frost Grenade): from
-- path point k on (what is still to fly), the first stretch of its arc that passes through a hero's
-- body, you always, the others with Unit Collision on. Read each frame, where the heroes stand now:
-- step off its arc and it flies on to the ground. Returns that point's index and the hero's feet
-- under where it meets him, or nil when it reaches the ground
local function arc_cut(rec, owner, spell, k)
    local feet = {}
    local me_at = S.me and try(S.me, "get_origin")
    if me_at then feet[1] = me_at end
    if not sim and ui.sp_collide and ui.sp_collide:Get() then
        for _, u in ipairs(U.blockers(owner, spell.blocked_by, ui.sp_debug:Get())) do
            feet[#feet + 1] = try(u.e, "get_origin")
        end
    end
    local path = rec.path
    for i = k + 1, #path do
        local a, b = path[i - 1], path[i]
        local ex, ey = b.x - a.x, b.y - a.y
        local len2 = ex * ex + ey * ey
        for _, q in ipairs(feet) do
            local t = len2 > 0 and math.max(0, math.min(1, ((q.x - a.x) * ex + (q.y - a.y) * ey) / len2)) or 0
            local px, py, pz = a.x + ex * t, a.y + ey * t, a.z + (b.z - a.z) * t
            -- shortcut: a hero's body taken as UNIT_R round, from his feet to UNIT_R over his head
            if (px - q.x) ^ 2 + (py - q.y) ^ 2 <= UNIT_R * UNIT_R and pz >= q.z and pz <= q.z + CFG.HEAD + UNIT_R then
                return i, Vector(px, py, q.z)
            end
        end
    end
end

-- "wall" spells: a line laid on the ground (Grasping Hands), drawn where its hands are: its ground
-- particles' own spots (control point 0; the others are not places, and stretched one to 54.6 m),
-- joined neighbour to neighbour along it, `width` each side, so it follows the wall as it lies. What
-- isn't a wall (fewer than WALL_MIN spots, or longer than `wall_max` m) is not drawn: a wrong line
-- would keep you from walking where you may. No hit time: a danger for as long as it is up, and the
-- guard keeps your keys from walking you over it
local WALL_MIN = 3   -- spots before a wall is drawn
local WALL_GAP = 3   -- meters between neighbouring spots that are still one wall (hands are 1 m apart)
local wall_drawn = {} -- spell id .. caster: the S.now its wall was last drawn
local function draw_wall(rec, owner, spell, color)
    -- each particle that names no owner is a group of its own: the wall is all of the caster's,
    -- drawn once a frame
    local groups = { rec } -- a simulated wall is its own
    if not rec.sim then
        local key = spell.id .. tostring(handle(owner))
        if wall_drawn[key] == S.now then return end
        wall_drawn[key] = S.now
        groups = {}
        for _, g in pairs(S.list) do
            if g.spell == spell and handle(g.owner) == handle(owner) then groups[#groups + 1] = g end
        end
    end
    local pts, first = {}, math.huge
    for _, g in ipairs(groups) do
        first = math.min(first, g.first or S.now)
        for _, p in ipairs(g.particles or {}) do
            for _, cp in ipairs(p.control_points or {}) do
                if (cp.cp or 0) == 0 then pts[#pts + 1] = cp.origin end
            end
        end
    end
    -- only for as long as its hands are up (`duration_prop`, from the first one seen): its particles
    -- fade out after, and it was drawn ~1.25 s past the hands in the replay (2026-11-10 14-45)
    local dur = (spell.duration_prop or spell.duration)
        and (U.ability_number(owner, spell, spell.duration_prop) or spell.duration)
    if dur and not rec.sim and S.now - first > dur then return end
    -- its axis: the two spots furthest apart; the spots in order along it
    local a, b, span = pts[1], pts[1], 0
    for i = 1, #pts do
        for j = i + 1, #pts do
            local d = (pts[i].x - pts[j].x) ^ 2 + (pts[i].y - pts[j].y) ^ 2
            if d > span then a, b, span = pts[i], pts[j], d end
        end
    end
    span = math.sqrt(span)
    local M = CFG.UNITS_PER_M
    local ok = #pts >= WALL_MIN and span <= (spell.wall_max or 26) * M
    local ux, uy = ok and (b.x - a.x) / math.max(1, span) or 0, ok and (b.y - a.y) / math.max(1, span) or 0
    table.sort(pts, function(p, q) return (p.x - a.x) * ux + (p.y - a.y) * uy < (q.x - a.x) * ux + (q.y - a.y) * uy end)
    local off = 0 -- how far its spots stray from a straight line, for Debug Mode
    for _, p in ipairs(pts) do off = math.max(off, math.abs((p.x - a.x) * uy - (p.y - a.y) * ux)) end
    if ui.sp_debug:Get() and S.now - (rec.wall_log or -math.huge) > 1 then
        rec.wall_log = S.now
        U.log("%s wall: %d spots, %.1f m end to end, up to %.1f m off a straight line%s", spell.name, #pts,
            span / M, off / M, ok and "" or (#pts < WALL_MIN and ", too few to draw" or ", too long to be one: not drawn"))
    end
    if not ok then return end
    local w = (spell.width or 0.75) * M
    local segs = {}
    for i = 2, #pts do
        local p, q = pts[i - 1], pts[i]
        if (q.x - p.x) ^ 2 + (q.y - p.y) ^ 2 <= (WALL_GAP * M) ^ 2 then
            segs[#segs + 1] = { p, q }
            zone({ kind = "lane", x = p.x, y = p.y, z = p.z, bx = q.x, by = q.y, bz = q.z, r = w })
        end
    end
    if not areas() then return end -- hidden, but Evade still dodges it
    local nx, ny = -uy * w, ux * w
    for _, sg in ipairs(segs) do
        local p, q = sg[1], sg[2]
        local l1, l2 = project(Vector(p.x + nx, p.y + ny, p.z + 4)), project(Vector(q.x + nx, q.y + ny, q.z + 4))
        local r1, r2 = project(Vector(p.x - nx, p.y - ny, p.z + 4)), project(Vector(q.x - nx, q.y - ny, q.z + 4))
        quad(l1, l2, r2, r1, rgba(color, 40))
        stroke({ l1 or false, l2 or false }, rgba(color, 220), 2)
        stroke({ r1 or false, r2 or false }, rgba(color, 220), 2)
    end
    local c = project(pts[math.ceil(#pts / 2)])
    if ui.sp_labels:Get() and c then text(Vec2(c.x + 8, c.y - 8), spell.name, color) end
end

local HERO_R = 20 -- units: a hero's half-width

-- "target" spells: cast at one hero. While its tell is up and it is aimed at you, a line from the
-- caster to you and a ring closing in on you, timed to the hit: `hit_delay` after the tell, plus the
-- flight at `speed`. Aimed at you: its `target_particles` seen on your client, or you in its range
-- and in its targeting cone during the cast delay; a target once picked stays picked
local function draw_target(rec, owner, spell, color)
    local hero = rec.caster or owner
    local o, me = valid(hero) and try(hero, "get_origin"), S.me and try(S.me, "get_origin")
    if not (o and me) then return end
    local dx, dy = me.x - o.x, me.y - o.y
    local d = math.sqrt(dx * dx + dy * dy)
    local marked = S.now - (S.targeted[spell.id] or -math.huge) < 1
    if spell.mark_modifier then
        -- you are its target for as long as you wear its mark: a chain can break before the pull. A mark
        -- that is its own tell (Death Slam's lock-on, no caster `modifier`) holds until the hit
        rec.at_me = sim or on_me(spell.mark_modifier) or not spell.modifier and rec.at_me
    elseif not rec.at_me and (marked or S.now <= rec.first + (spell.hit_delay or 0) + 0.05) then
        local f = U.aim_dir(hero)
        local range = U.ability_value(owner, spell, spell.range_prop, spell.range or 10)
        local off = f and math.abs((math.atan(dy, dx) - math.atan(f.y, f.x) + pi) % (2 * pi) - pi)
        rec.at_me = marked or d <= range + HERO_R and off ~= nil and off <= math.rad((spell.angle or 90) / 2)
    end
    if not rec.at_me then return end
    local at = rec.first + (spell.hit_delay or 0) + (spell.speed and d / spell.speed or 0)
    if S.now > at + CFG.TAIL_GRACE then return end
    zone({ kind = "target", x = me.x, y = me.y, z = me.z, r = HERO_R, at = at })
    -- the line, in pieces so it shows with either end off screen
    if paths() then
        local pts = {}
        for k = 0, BANDS do
            local u = k / BANDS
            pts[k + 1] = project(Vector(o.x + dx * u, o.y + dy * u, o.z + CFG.BODY_Z + (me.z - o.z) * u)) or false
        end
        stroke(pts, rgba(color, 45), 7)
        stroke(pts, rgba(color, 230), 2)
    end
    if not areas() then return end -- hidden, but Evade still parries it
    local left = math.max(0, at - S.now)
    world_ring(me, 30, rgba(color, 230), 2, 32)
    world_ring(me, 30 + 60 * math.min(1, left / math.max(0.1, spell.hit_delay or 0.5)), rgba(color, 160), 2, 32)
    local c = project(me)
    if ui.sp_labels:Get() and c then text(Vec2(c.x + 8, c.y - 8), fmt("%s on you, %.2f s", spell.name, left), color) end
end

-- A shockwave rolling out from where it landed (`wave_radius`), at its edge `wave_time` after the
-- landing: an outer ring round `rec.wave` (where it lands and when it is at its edge), kept up
-- after the landing's own tell is gone. `grow`, units/s: it passes you before it gets to the edge
local function draw_wave(rec, owner, spell, color)
    local w = rec.wave
    if not w or S.now > w.at + CFG.TAIL_GRACE then return end
    local r = U.ability_value(owner, spell, spell.wave_radius_prop, spell.wave_radius)
    zone({ kind = "circle", x = w.x, y = w.y, z = w.z, r = r, at = w.at, grow = r / spell.wave_time })
    if areas() then world_ring(w, r, rgba(color, 200), 2, 64) end
end

local function draw_motion(rec, owner, spell, color)
    if spell.motion == "target" then return draw_target(rec, owner, spell, color) end
    if spell.motion == "aura" then return draw_aura(rec, owner, spell, color) end
    if spell.motion == "cone" then return draw_cone(rec, owner, spell, color) end
    if spell.motion == "wall" then return draw_wall(rec, owner, spell, color) end
    if spell.motion == "line" then
        if rec.path then
            local w = (spell.width or 0.75) * CFG.UNITS_PER_M
            local cut = spell.blocked_by and not sim and ui.sp_collide and ui.sp_collide:Get() and blocked_lane(rec, owner, spell, w)
            draw_box(cut or rec, w, color, paths(), areas(), spell)
        end
        -- a lane can also end in an area (a dash that slashes where it lands); `land_offset` puts
        -- it where vdata measures it from the reach rather than at his feet
        if rec.land and spell.radius_prop then
            local at = U.ahead(rec.land, rec.path, spell.land_offset)
            -- a hero's lane runs BODY_Z above his feet; the area is on the floor under it
            if rec.mod then at = Vector(at.x, at.y, at.z - CFG.BODY_Z) end
            -- it goes off when the shot or hero reaches the end of the lane
            local from, speed = rec.pos or (rec.path and rec.path[1]), spell.speed or rec.speed
            local fires = from and speed and S.now + math.sqrt((rec.land.x - from.x) ^ 2 + (rec.land.y - from.y) ^ 2) / speed
            draw_marker(at, owner, spell, color, not spell.untimed and fires or nil)
        end
        return
    end
    -- a flight drawn only as he dives: nothing without the dive's path (the simulator knows where
    -- it lands from the start)
    if spell.dive_min_speed and not rec.path then return end
    -- only the last moments before impact, when the dive's direction is settled; a path point is
    -- ARC_DT of flight, so the path's length is the time left
    if spell.land_window and (not rec.path or (#rec.path - 1) * CFG.ARC_DT > spell.land_window) then
        -- held back, as the flight's own guess misses this early; but it comes down where the caster
        -- aims at the ground (`aim_land`), so that spot is marked meanwhile, timed if known
        if rec.aim_spot then draw_marker(rec.aim_spot, owner, spell, color, rec.aim_at) end
        return
    end
    -- a delayed blast whose tell outlives it: only until it goes off, plus the usual grace
    local dur = (spell.duration_prop or spell.duration)
        and (U.ability_number(owner, spell, spell.duration_prop) or spell.duration)
    if dur and S.now - rec.first > dur + CFG.TAIL_GRACE then return draw_wave(rec, owner, spell, color) end
    local path, land, lands_at = rec.path, rec.land or rec.warning, rec.lands_at
    -- a lob fired as a bullet keeps its whole arc: only what is still to fly, a point every ARC_DT
    if rec.shot and path then
        local k = math.min(#path, math.floor((S.now - rec.first) / CFG.ARC_DT) + 1)
        -- one that bursts on a hero in its way ends there, then: under him, as it reaches him
        local i, at = nil, nil
        if spell.blocked_by then i, at = arc_cut(rec, owner, spell, k) end
        if i then land, lands_at = at, rec.first + (i - 1) * CFG.ARC_DT end
        path = { table.unpack(path, k, i or #path) }
    end
    if paths() and path then draw_path(path, color) end
    -- an area the ability places in front of him, not where he comes down: flat along his aim
    local hero = rec.caster or rec.landing_ent
    local f = land and (spell.ahead_prop or spell.ahead) and valid(hero) and U.aim_dir(hero)
    local flat = f and math.sqrt(f.x * f.x + f.y * f.y)
    if flat and flat > 0.01 then
        local d = U.ability_value(owner, spell, spell.ahead_prop, spell.ahead or 0)
        -- shortcut: keeps the floor height under him, so a curb or ramp ahead is off by its height
        land = Vector(land.x + f.x / flat * d, land.y + f.y / flat * d, land.z)
    end
    -- it blows `dur` after first seen, when it has a fuse, else lands at the end of its path (a point
    -- every ARC_DT of flight). The fuse first: Bashdown's path is a guess straight down from Billy's
    -- waist, 0.02 s long, and Evade gave up on a slam that was 0.5 s off
    -- A lob fired as a bullet keeps its whole arc, so it lands when its throw said, not that whole
    -- flight again from now: Frost Grenade's burst would stay as far off as at the throw
    local fires = dur and rec.first + dur or rec.shot and lands_at
        or rec.path and S.now + (#rec.path - 1) * CFG.ARC_DT
    -- a bomb that arms on landing (`arm`) blows that long after it lands, not as it lands: Blood Bomb
    -- read as hitting in 0.07 s, and Counterspell went at once on a blast 0.7 s off
    local arm = (spell.arm_prop or spell.arm) and (U.ability_number(owner, spell, spell.arm_prop) or spell.arm)
    local lands = lands_at or fires
    if arm and lands then fires = lands + arm end
    if spell.untimed then fires = nil end -- a trap that lies there (Spirit Snare): no hit time, a place
    -- and once it has gone off it is no area, though its group is kept a while (CLEAR_DELAY)
    if rec.shot and fires and S.now > fires + CFG.TAIL_GRACE then return end
    if not land then return end
    draw_marker(land, owner, spell, color, fires)
    if fires and (spell.wave_radius_prop or spell.wave_radius) then
        rec.wave = { x = land.x, y = land.y, z = land.z, at = fires + spell.wave_time }
        draw_wave(rec, owner, spell, color)
    end
end

-- a thrown projectile (not a hero) that has gone: it has landed and gone off. Its group is still
-- kept for CLEAR_DELAY, which drew Blood Bomb's landing ~0.6 s past the blast.
local function projectile_gone(rec)
    if rec.mod then return false end
    if rec.landing_ent then return not valid(rec.landing_ent) end
    -- a projectile's own particle, else a ground tell with nothing flying (Disengaging Sigil): gone
    -- with its particle, not 1.5 s later when its kept event and group expire
    local idx = rec.landing_ev or rec.warning_ev
    if idx then
        local ev = S.events[idx]
        return not ev or ev.dead ~= nil
    end
    return false
end

function D.draw_entity(rec, lp)
    local e, owner, spell = rec.ent or rec.caster, rec.owner, rec.spell
    if not valid(owner) or not spell then return end
    if spell.motion == "arc" and projectile_gone(rec) then
        -- its tell is gone; its shockwave may still be rolling out (only ever set for an enemy's)
        if rec.wave then D.report(pcall(draw_wave, rec, owner, spell, COLOR)) end
        return
    end

    -- enemy spells only, Debug Mode too: test against sandbox bots. Allies are still detected, so
    -- their casts aren't pinned on a nearby enemy, just never drawn
    if handle(owner) == handle(lp) or HERO_LIB.is_same_team(lp, owner) == true then return end
    -- Visible Only: not from a caster you can't see. Once he has been in sight during it, it stays: a
    -- jar thrown in view still lands after he steps behind cover
    if ui.sp_fog and ui.sp_fog:Get() then
        rec.in_sight = rec.in_sight or U.in_sight(owner, ui.sp_debug:Get())
        if not rec.in_sight then return end
    elseif ui.sp_debug:Get() then
        U.in_sight(owner, true) -- off, the three are still logged, to see what they say
    end
    -- Dodge Arc: not from a caster behind or beside you, past this angle of where you look. Once
    -- cast in view it stays, so a dodge under way isn't dropped as you turn
    local fov = ui.sp_fov and ui.sp_fov:Get()
    if fov and fov < 360 then
        rec.in_view = rec.in_view or U.in_view(owner, fov)
        if not rec.in_view then return end
    end
    -- once an owner's shots of a line spell arrive as bullets, draw only those exact shots;
    -- the particle-tracked copy of the same projectile would draw a second, rougher box. A wind-up
    -- (`mod`) has no shot yet, so it still draws. Nor its tracer on the hero it caught: a second Bebop,
    -- hooked by the first, read as casting one at you from there (2026-11-10)
    if spell.bullet_owners and (spell.bullet_owners[handle(owner)] or next(spell.bullet_owners) and rec.caster)
        and not rec.shot and not rec.mod then return end

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
        -- a shot's lane (`o` is its far end) counts by its nearest point: one 100 m long starts beside
        -- you and ends out of range
        for _, pt in ipairs(rec.shot and rec.path or {}) do
            d = math.min(d or math.huge, U.dist_to_me(pt) or math.huge)
        end
        if d and d / CFG.UNITS_PER_M > md then return end
    end

    local color = COLOR
    if spell.motion then D.report(pcall(draw_motion, rec, owner, spell, color)) end
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
            world_cross(cp.origin, size, rgba(color, 210), 1)
            if ui.sp_labels:Get() and not named and labels < 3 then
                named = true
                labels = labels + 1
                local sp = project(cp.origin)
                if sp then text(Vec2(sp.x + 6, sp.y - 6), U.short_name(p.name), color) end
            end
        end
    end
end

-- Spell Simulator: a simulated spell, drawn by the same code as a real one (so it is a danger zone
-- like one), with a pin where its caster stands; always shown, whatever Landing Marker and Trajectory say
function D.draw_sim(rec)
    sim = true
    local ok, err = pcall(draw_motion, rec, nil, rec.spell, COLOR)
    sim = false -- even on an error, or real spells would next draw past the switches
    if not ok then error(err, 0) end
    world_pin(rec.from, COLOR)
end

local SAFE = Color(90, 230, 130) -- the dodge's safe spot and path
local BLOCKED = Color(160, 160, 160, 110)
local DASH = Color(90, 190, 255) -- a dash, where walking is too slow
local COUNTER = Color(190, 120, 255) -- a Counterspell parry, where no move gets you out

-- Evade Path: every cell the search looked at (red in danger, grey where you can't stand or
-- step, green safe; expanded cells bigger), the path, the point it walks to now, the safe spot,
-- and what it decided: walk, dash or nothing, with the times
function D.draw_dodge(plan)
    for _, c in ipairs(plan.cells) do
        local p = project(Vector(c.x, c.y, c.z + 4))
        if p then
            Render.FilledCircle(p, c.done and 3 or 2, c.blocked and BLOCKED or rgba(c.hot and COLOR or SAFE, 120))
        end
    end
    -- green to walk, blue to dash, purple to parry with Counterspell, red when nothing works and
    -- nothing is sent
    local col = plan.mode == "dash" and DASH or plan.mode == "counterspell" and COUNTER
        or plan.mode == "none" and COLOR or SAFE
    local function secs(t) return t and fmt("%.2f s", t) or "?" end
    local label = plan.mode == "dash" and fmt("dash, hits in %s", secs(plan.t))
        or plan.mode == "counterspell" and fmt("%s, hits in %s", plan.parried and "parried" or "Counterspell", secs(plan.t))
        or plan.mode == "none" and fmt("no escape, hits in %s: %s", secs(plan.t), plan.why or "?")
        or fmt("walk %s, hits in %s", secs(plan.walk), secs(plan.t))
    local goal = plan.goal
    if goal then
        local pts = {}
        for i, n in ipairs(plan.path) do pts[i] = project(Vector(n.x, n.y, n.z + 4)) or false end
        stroke(pts, rgba(col, 50), 7)
        stroke(pts, rgba(col, 230), 2)
        local aim = plan.path[plan.k]
        if aim then world_ring(Vector(aim.x, aim.y, aim.z + 4), 12, rgba(col, 255), 2, 16) end
        local at, p = Vector(goal.x, goal.y, goal.z + 4), (S.rt / PULSE_PERIOD) % 1
        world_ring(at, 24, rgba(col, 230), 2, 32)
        world_ring(at, 24 + 24 * p, rgba(col, 200 * (1 - p)), 2, 32)
        world_pin(at, col)
    end
    local spot = goal or plan.from
    local c = spot and project(Vector(spot.x, spot.y, spot.z + 4))
    if c then text(Vec2(c.x + 8, c.y - 8), label, col) end
end

return D
