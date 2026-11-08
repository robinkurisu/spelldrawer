-- headless harness: loads all six files, then drives the real detect and draw code with the
-- dump's own uppercut numbers, so the cone trigger, its delay, its geometry and the delayed-tail
-- grace can be checked without launching the game. Run it from the repo root: lua spelldrawer_harness.lua
-- headless exercise of the cone path with the game's own vdata values (no game running)
package.path = "./?.lua;" .. package.path
local files = { "spelldrawer.lua", "spelldrawer_detect.lua", "spelldrawer_draw.lua",
                "spelldrawer_menu.lua", "spelldrawer_spells.lua", "spelldrawer_util.lua" }
local ok = true
for _, f in ipairs(files) do
    local fn, err = loadfile(f)
    print((fn and "OK   " or "FAIL ") .. f .. (err and ("\n      " .. err) or ""))
    ok = ok and fn ~= nil
end
assert(ok, "load failed")

local ui = {}
local nums = { sp_size = 2, sp_dist = 0 }
for _, k in ipairs({ "sp_debug", "sp_enable", "sp_land", "sp_arc", "sp_boxes", "sp_labels",
                     "sp_points", "sp_size", "sp_dist" }) do
    ui[k] = { Get = function()
        if nums[k] then return nums[k] end
        return true
    end }
end
Enum = { FontCreate = { FONTFLAG_ANTIALIAS = 16 } }
package.loaded["spelldrawer_menu"] = { ui = ui }

local draws, last_z = 0, 0
Vector = function(x, y, z) return { x = x, y = y, z = z } end
Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
Vec2 = function(x, y) return { x = x, y = y } end
Render = {
    LoadFont = function() return 1 end,
    WorldToScreen = function(v)
        -- 1 screen px per world unit, so the captured points carry exact world offsets
        last_z = v.z
        local s = Vec2(100 + (v.x or 0), 100 - (v.y or 0))
        return s, true
    end,
    Line = function() end,
    Text = function() end,
    FilledCircle = function() end,
    FilledTriangle = function() draws = draws + 1 end,
}
convar = { sv_gravity = { float = function() return 800 end } }
trace = { line = function() return { fraction = 1 } end }
entity_list = { get_all = function() return {} end, by_handle = function() return nil end }
HERO_LIB = {
    is_ability_in_cast_delay = function() return false end,
    is_channeling_ability = function() return false end,
    is_same_team = function() return false end,
}

local U = require("spelldrawer_util")
local SPELLS = require("spelldrawer_spells")
local X = require("spelldrawer_detect")
local D = require("spelldrawer_draw")
local S = U.state

for _, s in ipairs(SPELLS) do s.ui = { Get = function() return true end } end
local spell
for _, s in ipairs(SPELLS) do if s.id == "bebop_exploding_uppercut" then spell = s end end
assert(spell, "entry missing")

-- the values draw.lua reads, exactly as the dump has them: MeleeAttackLength 6 m, MeleeHalfAngle 60
local props = { MeleeAttackLength = "6", MeleeHalfAngle = "60" }
local ability = {
    get_name = function() return "citadel_ability_uppercut" end,
    get_scaled_property = function(_, p) return props[p] end,
    get_cooldown = function() return 0 end,
}
local bebop = {
    valid = function() return true end,
    get_handle = function() return 7 end,
    get_class_name = function() return "C_CitadelPlayerPawn" end,
    get_vdata_class_name = function() return "C_CitadelPlayerPawn" end,
    get_origin = function() return Vector(0, 0, 0) end,
    get_angles = function() return { GetForward = function() return Vector(1, 0, 0) end } end,
    get_ability_by_slot = function() return ability end,
    get_modifiers = function() return {} end,
    get_particles = function() return {} end,
}
S.me = bebop
entity_list.get_all = function() return { bebop } end
entity_list.by_handle = function() return bebop end

-- the swing: m_MeleeActivateParticle is on him from t=0 until t=0.5
local SWING = 0.5
bebop.get_particles = function()
    if S.now <= SWING then
        return { { name = "particles/abilities/bebop/bebop_uppercut_activate.vpcf", control_points = {} } }
    end
    return {}
end

local function frame(t)
    S.now, S.rt = t, t
    draws = 0
    X.scan()
    local g
    for _, rec in pairs(S.groups) do if rec.spell == spell then g = rec end end
    if g then
        local ok, err = pcall(D.draw_entity, g, bebop)
        assert(ok, "draw error: " .. tostring(err))
    end
    return g, draws
end

local g = frame(0)
assert(g, "no group from the trigger particle")
assert(g.caster == bebop, "group not pinned to the caster")
assert(g.cone_at == 0, "cone_at not stamped: " .. tostring(g.cone_at))
print("t=0.00 cast frame, fan drawn = " .. tostring(draws > 0))
assert(draws == 0, "fan drawn on the cast frame, before the wind-up")
for _, t in ipairs({ 0.25, 0.5 }) do
    local _, d = frame(t)
    print(("t=%.2f fan drawn = %s"):format(t, tostring(d > 0)))
    assert(d > 0, "fan not drawn at " .. t)
end
-- geometry at the swing: the fan must reach 6 m (MeleeAttackLength) and span 120 degrees
local pts = {}
Render.FilledTriangle = function(tri) pts[#pts + 1] = tri[2]; pts[#pts + 1] = tri[3] end
local g2 = frame(0.5)
assert(g2, "group gone before the geometry check")
local maxx, miny, maxy = -math.huge, math.huge, -math.huge
for _, p in ipairs(pts) do
    maxx = math.max(maxx, p.x)
    miny, maxy = math.min(miny, p.y), math.max(maxy, p.y)
end
local reach_m = (maxx - 100) / U.CFG.UNITS_PER_M
-- screen y is the fan's lateral direction for this flat aim; half-width is 6 * tan(60 deg)
local lateral_m = math.max(math.abs(maxy - 100), math.abs(miny - 100)) / U.CFG.UNITS_PER_M
print(("reach = %.2f m, lateral extent = %.2f m, 6 * sin 60 = %.2f, triangles = %d")
    :format(reach_m, lateral_m, 6 * math.sin(math.rad(60)), #pts / 2))
assert(math.abs(reach_m - 6) < 0.01, "reach is not 6 m: " .. reach_m)
assert(math.abs(lateral_m - 6 * math.sin(math.rad(60))) < 0.01, "angle is not 120 degrees: " .. lateral_m)
assert(#pts == 2 * 24, "expected 24 fan triangles")

Render.FilledTriangle = function() draws = draws + 1 end
local _, late = frame(1.1)
print("t=1.10 past the swing, fan drawn = " .. tostring(late > 0))
assert(late == 0, "fan still drawn after the swing")
print("OK: trigger, 0.2 s delay, 6 m reach, 120 degree angle")

-- ---- aura tail grace: Chain Gang's ring must outlive the pull it marks ----
local chain
for _, s in ipairs(SPELLS) do if s.id == "billy_chain_gang" then chain = s end end
assert(chain, "Chain Gang entry missing")
local cprops = { AbilityCastRange = "12", AbilityDuration = "2.8" }
local cab = {
    get_name = function() return "ability_punkgoat_tether" end,
    get_scaled_property = function(_, p) return cprops[p] end,
    get_cooldown = function() return 0 end,
}
local billyMod = true
local billy = {
    valid = function() return true end,
    get_handle = function() return 8 end,
    get_class_name = function() return "C_CitadelPlayerPawn" end,
    get_vdata_class_name = function() return "C_CitadelPlayerPawn" end,
    get_origin = function() return Vector(0, 0, 0) end,
    get_angles = function() return { GetForward = function() return Vector(1, 0, 0) end } end,
    get_ability_by_slot = function() return cab end,
    get_modifiers = function()
        if billyMod then return { { get_name = function() return "waiting_for_pull" end } } end
        return {}
    end,
    get_particles = function() return {} end,
}
entity_list.get_all = function() return { billy } end
entity_list.by_handle = function() return billy end
ui.sp_boxes.Get = function() return false end
ui.sp_points.Get = function() return false end
ui.sp_labels.Get = function() return false end
local lines = 0
Render.Line = function() lines = lines + 1 end
S.groups = {}
S.next_scan = 0

local function aura(t)
    S.now, S.rt = t, t
    lines = 0
    X.scan()
    local rec
    local keys = 0
    for k, r in pairs(S.groups) do
        keys = keys + 1
        if r.spell == chain then rec = r end
    end
    print(("  aura t=%.2f groups=%d rec=%s mod_at=%s caster=%s first=%s")
        :format(t, keys, tostring(rec ~= nil), tostring(rec and rec.mod_at), tostring(rec and rec.caster ~= nil), tostring(rec and rec.first)))
    if rec then
        local ok, err = pcall(D.draw_entity, rec, billy)
        assert(ok, "aura draw error: " .. tostring(err))
    end
    return rec, lines
end

-- modifier runs t=0 .. 2.8 (the pull); sample it like the 0.25 s scan does
for _, t in ipairs({ 0, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75, 2.8 }) do
    aura(t)
end
local before = select(2, aura(1.85))
local shown = select(2, aura(2.0))
print(("t=1.85 (tail - grace, %.2f s in) ring drawn = %s"):format(1.85, tostring(before > 0)))
print(("t=2.00 (tail + grace)              ring drawn = %s"):format(tostring(shown > 0)))
assert(before == 0, "ring drawn before the grace window opened")
assert(shown > 0, "ring not drawn in the tail")
billyMod = false
for _, t in ipairs({ 3.05, 3.1, 3.2 }) do aura(t) end
local at_pull = select(2, aura(2.9))
print(("t=2.90 (0.1 s past the pull)       ring drawn = %s"):format(tostring(at_pull > 0)))
assert(at_pull > 0, "ring vanished the moment the pull landed")
local gone = select(2, aura(3.4))
print(("t=3.40                             ring drawn = %s"):format(tostring(gone > 0)))
assert(gone == 0, "ring never cleared")
print("OK: tail holds 0.15 s past the marked moment and clears after")
-- ---- a dash shorter than a scan: Leaping Slash must be caught frame by frame ----
local dash
for _, s in ipairs(SPELLS) do if s.id == "calico_leaping_slash" then dash = s end end
assert(dash, "Leaping Slash entry missing")

-- the dump's own numbers: AbilityCastRange 9 m at DashSpeed 2400 u/s is 0.147 s of dash, and the
-- 4 m SlashRadius sits SlashForwardOffset 1.5 m past where it stops
local DASH_M, SLASH_M, OFFSET_M, SPEED = 9, 4, 1.5, 2400
local props = { AbilityCastRange = "9", SlashRadius = "4" }
local START_X, START_T = 1000, 0.06
local DURATION = DASH_M * U.CFG.UNITS_PER_M / SPEED

local function hero(h, abil_name, pos)
    local abil = {
        get_name = function() return abil_name end,
        get_scaled_property = function(_, p) return props[p] end,
        get_cooldown = function() return 0 end,
    }
    return {
        valid = function() return true end,
        get_handle = function() return h end,
        get_class_name = function() return "C_CitadelPlayerPawn" end,
        get_vdata_class_name = function() return "C_CitadelPlayerPawn" end,
        get_origin = function() return Vector(pos(), 0, 0) end,
        get_angles = function() return { GetForward = function() return Vector(1, 0, 0) end } end,
        get_ability_by_slot = function(_, slot) return slot == 1 and abil or nil end,
        get_modifiers = function() return {} end,
        get_particles = function() return {} end,
    }
end

-- the dash runs +x from START_X at DashSpeed; the viewer is neither hero, so both are enemies
local x, run_n = START_X, 0
local calico = hero(60, "ability_nano_dash", function() return x end)
local shiv = hero(70, "citadel_ability_shiv_dash", function() return x end)
S.me = shiv
entity_list.get_all = function() return { calico, shiv } end
entity_list.by_handle = function(_, h) return h == 60 and calico or shiv end

-- the mark's ring triangles carry the centre as their apex and touch the ring in y; a box quad
-- reaches only the dash's 2 m half-width, so 3 m in y tells them apart
local ring_centre, ring_reach
Render.FilledTriangle = function(tri)
    draws = draws + 1
    for _, p in ipairs({ tri[2], tri[3] }) do
        if p and math.abs(p.y - 100) > 3 * U.CFG.UNITS_PER_M then
            ring_centre = tri[1].x
            ring_reach = math.max(ring_reach or 0, math.abs(p.y - 100))
        end
    end
end

-- one 60 fps frame of the real loop: scan (self-gated to SCAN_EVERY), modifier poll, tracking, draw
local function dash_frame(t, hit, abil)
    S.now, S.rt = t, t
    draws = 0
    ring_centre, ring_reach = nil, nil
    if hit then
        X.track_particle({ name = "particles/abilities/nano/nano_dash_instant.vpcf", entity = calico, index = 9 })
    else
        calico.get_modifiers = function()
            if t < START_T or t >= START_T + DURATION then return {} end
            return { { get_name = function() return abil or "modifier_citadel_shiv_dash" end } }
        end
    end
    X.scan()
    X.track_modifiers()
    X.track_projectiles(1 / 60)
    local rec
    for _, r in pairs(S.list) do if r.spell == dash then rec = r end end
    if rec then
        local ok, err = pcall(D.draw_entity, rec, shiv)
        assert(ok, "dash draw error: " .. tostring(err))
    end
    return rec, draws
end

local function dash_run(name, use_particle, abil)
    run_n = run_n + 1
    calico.get_modifiers = function() return {} end
    S.groups, S.list, S.next_scan, S.events = {}, {}, 0, {}
    local seen, drawn, ahead, printed, next_scan, centre, reach, height, held, cleared
    local end_t = START_T + DURATION
    for i = 0, math.floor((end_t + 0.6) * 60) do
        local t = i / 60
        x = START_X + math.max(0, math.min(t - START_T, DURATION)) * SPEED
        if t >= START_T and not printed then
            printed = true
            next_scan = S.next_scan -- what the last frame left: the next scan's time
            print(("  %s: next scan %.3f, dash ends %.3f, ends before it = %s")
                :format(name, next_scan, end_t, tostring(end_t < next_scan)))
        end
        local rec, d = dash_frame(t, use_particle and math.abs(t - START_T) < 0.5 / 60, abil)
        if rec then seen = seen or t end
        if d > 0 then
            drawn = drawn or t
            if ring_centre and ring_centre - (100 + x) > 0 then ahead = (ahead or 0) + 1 end
            if t >= end_t - 1 / 60 and t <= end_t then
                centre, reach, height = ring_centre, ring_reach, last_z
            end
        end
        if t >= end_t + 0.15 and t <= end_t + 0.2 then held = held or d end
        if t >= end_t + 0.55 then cleared = cleared or d end
    end
    return { seen = seen, drawn = drawn, ahead = ahead, centre = centre, reach = reach,
             height = height, held = held, cleared = cleared }
end

local only = dash_run("modifier only", false)
print(("  modifier only: group at %.3f, circle drawn at %.3f"):format(only.seen or -1, only.drawn or -1))
assert(only.seen, "the modifier was never seen: the dash fell between two scans")
assert(only.drawn, "no circle drawn for the dash")
local centre_m = ((only.centre or 0) - 100 - START_X) / U.CFG.UNITS_PER_M
local radius_m = (only.reach or 0) / U.CFG.UNITS_PER_M
print(("  circle centre %.2f m from the dash start (%.1f + %.1f), radius %.2f m, %d frames ahead")
    :format(centre_m, DASH_M, OFFSET_M, radius_m, only.ahead or 0))
-- range counts from where the dash was first seen, so the mark can sit one frame of dash
-- travel (2400 / 60 / 39.37 = 1.02 m) past the true start; anything further is a wrong spot
assert(math.abs(centre_m - (DASH_M + OFFSET_M)) < 1.2, "circle not at the landing spot: " .. centre_m)
assert(math.abs(radius_m - SLASH_M) < 0.05, "circle radius is not SlashRadius: " .. radius_m)
-- the lane runs BODY_Z above his feet; the slash area belongs on the floor under it
print(("  circle height %.1f units above the floor (want 0)"):format(only.height or -1))
assert(math.abs(only.height or 999) < 1, "circle not on the ground: " .. tostring(only.height))
assert((only.ahead or 0) > 0, "circle never sat ahead of the hero")
print(("  0.15 s after the dash: drawn = %s; 0.55 s after: drawn = %s")
    :format(tostring(only.held > 0), tostring(only.cleared > 0)))
assert(only.held > 0, "circle gone the moment the dash ended")
assert(only.cleared == 0, "circle never cleared")

local fired = dash_run("particle", true)
print(("  particle: group at %.3f (dash starts %.3f), drawn = %s")
    :format(fired.seen or -1, START_T, tostring(fired.drawn ~= nil)))
assert(fired.seen and fired.seen <= START_T + 1 / 60, "the dash particle did not start the track at once")
assert(fired.drawn, "particle track never drew")

-- Shiv's own dash carries the same modifier: the Calico entry must not fire for him
x = START_X
S.groups, S.list, S.next_scan = {}, {}, 0
calico.get_modifiers = function() return {} end
shiv.get_modifiers = function()
    if x > START_X + 9 * 39.37 then return {} end
    return { { get_name = function() return "modifier_citadel_shiv_dash" end } }
end
local shiv_groups = 0
for i = 0, 24 do
    local t = (i + 1) / 60
    S.now, S.rt = t, t
    if i > 0 and i < 9 then x = START_X + i * 40 end
    X.scan()
    X.track_modifiers()
    X.track_projectiles(1 / 60)
    for _, r in pairs(S.list) do if r.spell == dash then shiv_groups = shiv_groups + 1 break end end
end
print(("  Shiv's own dash (same modifier): Calico groups = %d"):format(shiv_groups))
assert(shiv_groups == 0, "the Calico entry fired on Shiv's dash")
print("OK: dash caught between scans, circle at the landing, clears after, Shiv excluded")

-- ============================================================================
-- full registry coverage. One fixture per entry that must detect and draw the right primitives for
-- its `motion`, and one that must not. Every number comes from the dump (build 6860,
-- %TEMP%\deadlock_dump\data\abilities.vdata, the block and line named beside each entry); world maps
-- to screen 1:1, so each geometry check is made in world units over UNITS_PER_M.
-- ============================================================================

local UPM = U.CFG.UNITS_PER_M
local SPB = 100 -- the screen offset the stub WorldToScreen adds

local REC = { lines = {}, tris = {} }
local function clear_rec() REC.lines, REC.tris = {}, {} end

local function wp(s) return { x = s.x - SPB, y = SPB - s.y, z = s.wz } end
Render.WorldToScreen = function(v)
    local s = Vec2(SPB + (v.x or 0), SPB - (v.y or 0))
    last_z, s.wz = v.z, v.z
    return s, true
end
Render.Line = function(a, b) REC.lines[#REC.lines + 1] = { wp(a), wp(b) } end
Render.FilledTriangle = function(t) REC.tris[#REC.tris + 1] = { wp(t[1]), wp(t[2]), wp(t[3]) } end
Render.FilledCircle = function() end
Render.Text = function() end

-- the world floor: a segment that crosses z = 0 stops on it, like terrain under a lob
trace = { line = function(a, b)
    if a.z == b.z then return { fraction = 1 } end
    local f = a.z / (a.z - b.z)
    return { fraction = (f >= 0 and f <= 1) and f or 1 }
end }

-- the player: a pawn with no abilities of its own, so every fixture caster reads as an enemy
local function mkpawn(h, pos, ab, state)
    return {
        valid = function() return true end,
        get_handle = function() return h end,
        get_class_name = function() return "C_CitadelPlayerPawn" end,
        get_vdata_class_name = function() return "C_CitadelPlayerPawn" end,
        get_origin = function() return Vector(pos[1], pos[2], pos[3]) end,
        get_angles = function() return { GetForward = function() return Vector(1, 0, 0) end } end,
        get_ability_by_slot = function(_, slot) return (ab and slot == 1) and ab or nil end,
        get_modifiers = function() return state.mods end,
        get_particles = function()
            local out = {}
            for i, v in ipairs(state.particles) do
                out[i] = type(v) == "table" and v or { name = v, control_points = {} }
            end
            return out
        end,
    }
end

-- a hero with one ability in slot 1 and the dump's properties; `props` are plain numbers the way
-- get_scaled_property returns them, and pos is mutable so a dash can move
local function actor(h, x, y, z, name, props)
    local state = { mods = {}, particles = {}, cast = false }
    local pos = { x, y, z }
    local ab = {
        _state = state,
        get_name = function() return name end,
        get_scaled_property = function(_, p) local v = props[p]; return v and tostring(v) or nil end,
        get_cooldown = function() return 0 end,
    }
    return mkpawn(h, pos, ab, state), state, pos
end

local function mkproj(h, x, y, z, particle, class)
    local state = { mods = {}, particles = {} }
    local pos = { x, y, z }
    local p = mkpawn(h, pos, nil, state)
    p.get_class_name = function() return class or "C_CitadelProjectile" end
    p.get_vdata_class_name = p.get_class_name
    if particle then state.particles[1] = particle end
    return p, state, pos
end

local function mod(name) return { get_name = function() return name end } end

local viewer = mkpawn(900, { 0, -600, 0 }, nil, { mods = {}, particles = {} })

HERO_LIB = {
    is_ability_in_cast_delay = function(ab) return ab ~= nil and ab._state ~= nil and ab._state.cast end,
    is_channeling_ability = function() return false end,
    is_same_team = function() return false end,
}

local function world(spell, caster, extras)
    local w = { spell = spell, caster = caster, all = { caster }, t = 0 }
    for _, e in ipairs(extras or {}) do w.all[#w.all + 1] = e end
    w.all[#w.all + 1] = viewer
    entity_list.get_all = function() return w.all end
    entity_list.by_handle = function(_, h)
        for _, e in ipairs(w.all) do if e.get_handle() == h then return e end end
    end
    S.me, S.now, S.rt = viewer, 0, 0
    S.groups, S.list, S.events, S.next_scan = {}, {}, {}, 0
    S.holders, S.near, S.casters, S.cooldowns = {}, {}, {}, {}
    return w
end

local function count_groups(spell)
    local n = 0
    for _, r in pairs(S.list) do if r.spell == spell then n = n + 1 end end
    return n
end

local function step(w)
    w.t = w.t + 1 / 60
    S.now, S.rt = w.t, w.t
    clear_rec()
    X.scan()
    X.track_modifiers()
    X.track_projectiles(1 / 60)
    local g
    for _, r in pairs(S.list) do if r.spell == w.spell then g = r end end
    if g then
        local ok, err = pcall(D.draw_entity, g, viewer)
        assert(ok, w.spell.id .. " draw error: " .. tostring(err))
    end
    return g
end

local function run(w, seconds)
    local g
    for _ = 1, math.floor(seconds * 60 + 0.5) do g = step(w) or g end
    return g
end

-- geometry readers ---------------------------------------------------------------------------
-- every fixture runs its lane along +x at y = 0, so a lane point's distance across the lane is its
-- y and its progress along it is its x; a marker's apex sits on the lane, its rim at the radius

local function across(p) return math.abs(p.y) end
local function from(p, cx) return math.sqrt((p.x - cx) ^ 2 + p.y ^ 2) end

local function assert_marker(cx, ground, radius, label)
    local n, off, keep = 0, false, {}
    for _, t in ipairs(REC.tris) do
        if from(t[1], cx) < 0.5 * UPM then
            n = n + 1
            for i = 2, 3 do
                if math.abs(from(t[i], cx) / UPM - radius) > 0.02 then off = true end
            end
            keep[#keep + 1] = t[1]
        end
    end
    assert(n >= 16, label .. ": marker not drawn at the expected spot (" .. n .. " triangles)")
    assert(not off, label .. ": marker ring radius is not " .. radius .. " m")
    for _, p in ipairs(keep) do
        assert(math.abs(p.z - ground) < 1, label .. ": marker is not on the floor (z " .. p.z .. ")")
    end
end

local function assert_lane(sx, ground, width, range, height, label, slack)
    local pmin, pmax, amax, n = math.huge, 0, 0, 0
    local minz, maxz = math.huge, -math.huge
    for _, t in ipairs(REC.tris) do
        local box = true
        for i = 1, 3 do if across(t[i]) < 1 then box = false end end
        if box then
            n = n + 1
            for i = 1, 3 do
                local p = across(t[i]) / UPM
                pmin, pmax = math.min(pmin, p), math.max(pmax, p)
                amax = math.max(amax, (t[i].x - sx) / UPM)
                minz, maxz = math.min(minz, t[i].z), math.max(maxz, t[i].z)
            end
        end
    end
    assert(n > 20, label .. ": lane box not drawn (" .. n .. " quads)")
    assert(math.abs(pmin - width) < 0.02 and math.abs(pmax - width) < 0.02,
        ("%s: lane half-width %s/%s m, want %s"):format(label, pmin, pmax, width))
    -- range counts from where the sample started, which on a dash is a sample interval in
    local sp = slack or 0.2
    assert(amax > range - 0.2 and amax < range + sp,
        ("%s: lane length %s m, want %s"):format(label, amax, range))
    if height then
        local top, bottom = (maxz - ground) / UPM, (ground - minz) / UPM
        assert(math.abs(top - height) < 0.02, ("%s: box top %s m above the feet, want %s"):format(label, top, height))
        assert(math.abs(bottom - 0.5) < 0.02, ("%s: box bottom %s m under the feet, want 0.5"):format(label, bottom))
    end
end

-- the aura's own ring: its endpoints all sit on the radius, where the head ring sits at 0.8 and the
-- pulse ring wanders out to 1.4, so counting hits at the radius identifies it exactly
local function aura_hits(cx, cy, radius)
    local n = 0
    for _, L in ipairs(REC.lines) do
        for _, p in ipairs(L) do
            if math.abs(math.sqrt((p.x - cx) ^ 2 + (p.y - cy) ^ 2) / UPM - radius) < 0.02 then
                n = n + 1
            end
        end
    end
    return n
end

local function assert_cone(sx, reach, half_deg, label)
    local maxx, lateral, n = -math.huge, 0, 0
    for _, t in ipairs(REC.tris) do
        n = n + 1
        for i = 1, 3 do
            maxx = math.max(maxx, (t[i].x - sx) / UPM)
            lateral = math.max(lateral, across(t[i]) / UPM)
        end
    end
    assert(n > 20, label .. ": fan not drawn")
    assert(math.abs(maxx - reach) < 0.02, ("%s: reach %s m, want %s"):format(label, maxx, reach))
    local want = reach * math.sin(math.rad(half_deg))
    assert(math.abs(lateral - want) < 0.02, ("%s: lateral %s m, want %s"):format(label, lateral, want))
end

-- fixtures ------------------------------------------------------------------------------------

local by_id = {}
for _, s in ipairs(SPELLS) do by_id[s.id] = s end

local FIX = {}

local function entry(id, positive, negative)
    assert(by_id[id], "entry missing: " .. id)
    FIX[#FIX + 1] = { id = id, positive = positive, negative = negative }
end

-- Blood Bomb: arc off the thrown bomb (m_mapProjectileInfos.primary: ability_blood_bomb:55851-55854:
-- m_flSpeed 2000, m_flUpSpeed 0, the projectile particle and its warning particle). Radius 7 m
-- (:55760). The warning's CP0 is the landing spot.
local function blood_bomb_positive(spell)
    local geist = actor(201, 1000, 0, 0, "ability_blood_bomb", { Radius = 7 })
    local bomb, _, pos = mkproj(202, 1400, 0, 400, "particles/abilities/ghost/ghost_blood_bomb_projectile.vpcf")
    local w = world(spell, geist, { bomb })
    local x, z, vz = 1400, 400, -400
    for _ = 1, 60 do
        x, z, vz = x + 400 / 60, z + vz / 60, vz - 800 / 60
        pos[1], pos[3] = x, z
        local g = step(w)
        if g and g.land and g.land.z < 20 then
            -- analytic landing for v = (400, -400) from 400 u under 800 u/s^2: 0.618 s in, 247 u on;
            -- the prediction steps 0.02 s at a time; measured error is under 0.1 m, so 0.25 m is the bar
            assert(math.abs((g.land.x - 1400 - 247.2) / UPM) < 0.25, "arc landing not where the throw lands")
            assert(math.abs(g.land.z - 4) < 1, "arc landing is not on the floor")
            assert_marker(g.land.x, 4, 7, "blood bomb")
            assert(#REC.lines > 40, "arc path not drawn")
            return
        end
    end
    assert(false, "blood bomb: no landing predicted")
end

local function blood_bomb_negative(spell)
    local geist = actor(203, 1000, 0, 0, "ability_blood_bomb", { Radius = 7 })
    local preview = mkproj(204, 1400, 0, 400, "particles/abilities/ghost/ghost_blood_bomb_preview.vpcf")
    local w = world(spell, geist, { preview })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "blood bomb: the preview particle detected")

    -- the explode particle (m_ExplodeParticle, :293) is not in `skip` and its name keeps the
    -- entry's particle stem, so it does start a group; it has no path and draws nothing
    local blast = mkproj(205, 9000, 0, 40, "particles/abilities/ghost/ghost_blood_bomb_explode.vpcf")
    local w2 = world(spell, actor(206, 9000, 0, 0, "ability_blood_bomb", {}), { blast })
    X.track_particle({ name = "particles/abilities/ghost/ghost_blood_bomb_explode.vpcf", entity = blast, index = 90 })
    X.update_particle({ index = 90, control_point = 0, position = Vector(9000, 0, 40) })
    local drew = 0
    for _ = 1, 20 do step(w2); drew = drew + #REC.tris + #REC.lines end
    assert(drew == 0, "blood bomb: the explode particle drew " .. drew .. " primitives")
end

entry("ghost_blood_bomb", blood_bomb_positive, blood_bomb_negative)

-- Malice: line off the knife (m_szBulletTravelTracerParticle, ability_blood_shards:56180), 3500 u/s
-- muzzle speed and 3 s lifetime (:56174-56176), m_flBulletRadius 30 u (:56178) as the half-width.
local function malice_positive(spell)
    local geist = actor(205, 1000, 0, 0, "ability_blood_shards", {})
    local knife, _, pos = mkproj(206, 1200, 0, 100, "particles/abilities/ghost/ghost_blood_shard_dagger.vpcf")
    local w = world(spell, geist, { knife })
    for _ = 1, 20 do step(w); pos[1] = pos[1] + 3500 / 60 end
    assert_lane(1200, 0, 30 / UPM, 266.7, nil, "malice")
end

local function malice_negative(spell)
    local geist = actor(207, 1000, 0, 0, "ability_blood_shards", {})
    local hit = mkproj(208, 1200, 0, 100, "particles/abilities/ghost/ghost_blood_shard_dagger_impact.vpcf")
    local w = world(spell, geist, { hit })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "malice: the impact particle detected")
end

entry("ghost_malice", malice_positive, malice_negative)

-- Shoulder Charge: line off modifier_citadel_bull_charging (m_ModifierBullCharging,
-- citadel_ability_bull_charge:31807), ChargeRadius 2.2 m (:31607) as the half-width.
local function charge_positive(spell)
    local abrams, st, pos = actor(209, 1200, 0, 0, "citadel_ability_bull_charge", {})
    local w = world(spell, abrams)
    st.mods = { mod("modifier_citadel_bull_charging") }
    for _ = 1, 20 do pos[1] = pos[1] + 984 / 60; step(w) end -- 25 m/s
    assert_lane(1200, 0, 2.2, 34, 2.5, "shoulder charge", 1.4)
end

local function charge_negative(spell)
    local victim, vst = actor(210, 1200, 0, 0, nil, {})
    local abrams, st = actor(211, 1200, 200, 0, "citadel_ability_bull_charge", {})
    local w = world(spell, abrams, { victim })
    st.mods = { mod("modifier_citadel_bull_charging") }
    vst.mods = { mod("modifier_citadel_bull_charging") } -- the victim carries it but not the ability
    for _ = 1, 10 do step(w) end
    local n = 0
    for _, r in pairs(S.list) do if r.spell == spell then n = n + 1 end end
    assert(n == 1, "shoulder charge: the victim's copy made its own group (" .. n .. ")")
end

entry("abrams_shoulder_charge", charge_positive, charge_negative)

-- Seismic Impact: arc off modifier_citadel_bull_leap_boosting_crash (m_CrashModifier,
-- citadel_ability_bull_leap:32581), gravity_scale 0 so the slam is straight down, ImpactRadius 9 m
-- (:32367).
local function leap_positive(spell)
    local abrams, st, pos = actor(212, 1600, 0, 800, "citadel_ability_bull_leap", { ImpactRadius = 9 })
    local w = world(spell, abrams)
    st.mods = { mod("modifier_citadel_bull_leap_boosting_crash") }
    local i, vz, g = 0, 0, nil
    for _ = 1, 80 do
        i = i + 1
        if i > 6 then vz = -1000 end -- the hover before the slam
        pos[3] = pos[3] + vz / 60
        g = step(w) or g
        if g and g.land and g.land.z < 20 then break end
    end
    assert(g and g.land, "seismic impact: no landing predicted")
    assert(math.abs(g.land.x - 1600) < 2 and math.abs(g.land.y) < 2, "the dive did not land straight below")
    assert_marker(1600, 4, 9, "seismic impact")
end

local function leap_negative(spell)
    local abrams = actor(213, 1600, 0, 800, "citadel_ability_bull_leap", { ImpactRadius = 9 })
    local victim, vst = actor(214, 1600, 200, 0, nil, {})
    local w = world(spell, abrams, { victim })
    vst.mods = { mod("modifier_citadel_bull_leap_boosting_crash") }
    run(w, 0.5)
    assert(count_groups(spell) == 0, "seismic impact: the victim's modifier detected")
end

entry("abrams_seismic_impact", leap_positive, leap_negative)

-- Flawless Advance: line off the recast modifier (m_UIRecastModifier, ability_fencer_lunge:272515)
-- with min_speed 20, lane half-width SlashRadius 1.6 m (:272170), reach SlashLength 13 m (:272180),
-- lunge DashSpeed 1100 u/s (:272055).
local function lunge_positive(spell)
    local apollo, st, pos = actor(215, 2000, 0, 0, "ability_fencer_lunge", { SlashLength = 13, SlashRadius = 1.6 })
    local w = world(spell, apollo)
    st.mods = { mod("modifier_base_uirecast") }
    for _ = 1, 20 do pos[1] = pos[1] + 1100 / 60; step(w) end
    assert_lane(2000, 0, 1.6, 13, 2.5, "flawless advance", 1.6)
end

local function lunge_negative(spell)
    -- uirecast is also the recast window of Disengaging Sigil, and it covers the walk before the
    -- lunge: at walking speed (8.8 m/s, under the 20 m/s floor) the flat-aim guess draws the first
    -- frames, but the lane must stop at SlashLength instead of stretching along with him
    local victim, vst = actor(216, 2000, 200, 0, nil, {})
    vst.mods = { mod("modifier_base_uirecast") }
    local w = world(spell, actor(217, 2000, 0, 0, "ability_fencer_lunge", {}), { victim })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "flawless advance: the victim's modifier detected")

    local apollo, st, pos = actor(218, 2000, 0, 0, "ability_fencer_lunge", { SlashLength = 13, SlashRadius = 1.6 })
    local w2 = world(spell, apollo)
    st.mods = { mod("modifier_base_uirecast") }
    -- walking backwards, so a lane that follows the measured velocity would point the other way:
    -- the guard drops the sample and the lane stays on the first, aimed guess
    for _ = 1, 40 do pos[1] = pos[1] - 8.8 * UPM / 60; step(w2) end
    assert_lane(2000, 0, 1.6, 13, 2.5, "flawless advance at walking speed", 0.4)
end

entry("apollo_sword_charge", lunge_positive, lunge_negative)

-- Itani Lo Sahn: line while the 1.5 s wind-up (AbilityCastDelay, ability_fencer_ultimate:272574,
-- with m_AutoCastDelayModifier :273066) is up, aimed where he looks; DashRange 27 m (:272670),
-- height 7.5 m.
local function fencer_ult_positive(spell)
    local apollo, st = actor(217, 2400, 0, 0, "ability_fencer_ultimate", { DashRange = 27 })
    local w = world(spell, apollo)
    st.mods = { mod("fencer_ult_cast_delay") }
    for _ = 1, 20 do step(w) end
    assert_lane(2400, 0, 7, 27, 7.5, "itani lo sahn")
end

local function fencer_ult_negative(spell)
    local victim, vst = actor(218, 2400, 200, 0, nil, {})
    local w = world(spell, actor(219, 2400, 0, 0, "ability_fencer_ultimate", {}), { victim })
    vst.mods = { mod("fencer_ult_cast_delay") }
    run(w, 0.4)
    assert(count_groups(spell) == 0, "itani lo sahn: the victim's modifier detected")
end

entry("apollo_ultimate", fencer_ult_positive, fencer_ult_negative)

-- Exploding Uppercut: cone off m_MeleeActivateParticle (citadel_ability_uppercut:34991).
-- MeleeAttackLength 6 m (:34469), MeleeHalfAngle 60 (:34465) is half of the 120 degree fan.
local function uppercut_positive(spell)
    local bebop, st = actor(220, 2800, 0, 0, "citadel_ability_uppercut",
        { MeleeAttackLength = 6, MeleeHalfAngle = 60 })
    local w = world(spell, bebop)
    st.particles = { "particles/abilities/bebop/bebop_uppercut_activate.vpcf" }
    for _ = 1, 24 do step(w) end -- past the 0.2 s swing delay
    assert_cone(2800, 6, 60, "exploding uppercut")
end

local function uppercut_negative(spell)
    local victim, vst = actor(221, 2800, 0, 0, nil, {})
    local w = world(spell, actor(222, 2800, 200, 0, "citadel_ability_uppercut", {}), { victim })
    vst.particles = { "particles/abilities/bebop/bebop_uppercut_activate.vpcf" } -- a pawn without it
    run(w, 0.5)
    assert(count_groups(spell) == 0, "exploding uppercut: a victim holding the swing particle detected")
end

entry("bebop_exploding_uppercut", uppercut_positive, uppercut_negative)

-- Grapple Arm: line off the bullet (m_szBulletTravelTracerParticle, citadel_ability_hook:36243),
-- m_flBulletRadius 33 u (:36241) half-width, AbilityCastRange 30 m (:36057).
local function hook_positive(spell)
    local bebop = actor(223, 3200, 0, 0, "citadel_ability_hook", { AbilityCastRange = 30 })
    local w = world(spell, bebop)
    X.track_bullet({ weapon_name = "citadel_ability_hook", shooter = bebop,
        start_pos = Vector(3200, 0, 100), direction = Vector(1, 0, 0) })
    clear_rec()
    local g
    for _, r in pairs(S.list) do if r.spell == spell then g = r end end
    assert(g, "grapple arm: the bullet made no shot group")
    D.draw_entity(g, viewer)
    assert_lane(3200, 0, 33 / UPM, 30, nil, "grapple arm")
end

local function hook_negative(spell)
    local bebop = actor(224, 3200, 0, 0, "citadel_ability_hook", {})
    local w = world(spell, bebop)
    bebop.get_particles = function()
        return { { name = "particles/abilities/bebop/bebop_hook_precast.vpcf", control_points = {} } }
    end
    run(w, 0.4)
    assert(count_groups(spell) == 0, "grapple arm: the precast particle detected")
end

entry("bebop_hook", hook_positive, hook_negative)

-- Bashdown: arc off m_BatChargingEffect on Billy (ability_punkgoat_ult:173713, follow_caster),
-- gravity_scale 0 for the driven dive, AbilityCastRange 4 m (:173241).
local function bashdown_positive(spell)
    local billy, st, pos = actor(225, 3600, 0, 600, "ability_punkgoat_ult", { AbilityCastRange = 4 })
    local w = world(spell, billy)
    st.particles = { "particles/abilities/punkgoat/punkgoat_bashdown_bat.vpcf" }
    local i, vz, g = 0, 0, nil
    for _ = 1, 80 do
        i = i + 1
        if i > 6 then vz = -1000 end
        pos[3] = pos[3] + vz / 60
        g = step(w) or g
        if g and g.land and g.land.z < 20 then break end
    end
    assert(g and g.land, "bashdown: no landing predicted")
    assert(math.abs(g.land.x - 3600) < 2, "the dive did not land straight below Billy")
    assert_marker(3600, 4, 4, "bashdown")
end

local function bashdown_negative(spell)
    local victim, vst = actor(226, 3600, 0, 600, nil, {})
    local w = world(spell, actor(227, 3600, 200, 0, "ability_punkgoat_ult", {}), { victim })
    vst.particles = { "particles/abilities/punkgoat/punkgoat_bashdown_bat.vpcf" }
    run(w, 0.5)
    assert(count_groups(spell) == 0, "bashdown: the bat effect on a victim detected")
end

entry("billy_bashdown", bashdown_positive, bashdown_negative)

-- Rising Ram: line off the "charge" modifier (m_Charging, ability_punkgoat_goatflip:173105) at
-- ChargeSpeed 1200 u/s, ChargeRadius 2.54 m (:172700) half-width, 0.3 s of charge = 9 m
-- (:172588 AbilityDuration).
local function ram_positive(spell)
    local billy, st, pos = actor(228, 4000, 0, 0, "ability_punkgoat_goatflip", { ChargeRadius = 2.54 })
    local w = world(spell, billy)
    st.mods = { mod("charge") }
    for _ = 1, 20 do pos[1] = pos[1] + 1200 / 60; step(w) end -- 30.5 m/s, over min_speed 25
    assert_lane(4000, 0, 2.54, 9, 2.5, "rising ram", 1.7)
end

local function ram_negative(spell)
    -- "charge" is a substring of about 20 other modifiers: a pawn without the ability carrying one
    -- is an on-hit victim and must not fill the entry
    local victim, vst = actor(229, 4000, 0, 0, nil, {})
    vst.mods = { mod("modifier_melee_charge") }
    local w = world(spell, actor(230, 4000, 0, 0, "ability_punkgoat_goatflip", {}), { victim })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "rising ram: a victim's melee charge detected")

    -- and under the 25 m/s floor a walk must not stretch the lane past ChargeSpeed's 9 m
    local billy, st, pos = actor(231, 4000, 0, 0, "ability_punkgoat_goatflip", { ChargeRadius = 2.54 })
    local w2 = world(spell, billy)
    st.mods = { mod("charge") }
    for _ = 1, 40 do pos[1] = pos[1] - 8.8 * UPM / 60; step(w2) end
    assert_lane(4000, 0, 2.54, 9, 2.5, "rising ram at walking speed", 0.4)
end

entry("billy_rising_ram", ram_positive, ram_negative)

-- Chain Gang: aura while waiting_for_pull is on Billy (m_WaitingToPullModifier,
-- ability_punkgoat_tether:172415), AbilityCastRange 12 m (:171921), drawn only in the last second
-- of AbilityDuration 2.8 s (:171907).
local function chain_positive(spell)
    local billy, st = actor(230, 4400, 0, 0, "ability_punkgoat_tether", { AbilityCastRange = 12, AbilityDuration = 2.8 })
    local w = world(spell, billy)
    st.mods = { mod("waiting_for_pull") }
    local g
    for _ = 1, 120 do g = step(w) or g end -- 2.0 s in: inside the last second plus the grace
    assert(g, "chain gang: no group")
    local r = aura_hits(4400, 0, 12)
    assert(r >= 40, "chain gang: no 12 m ring (" .. r .. " points)")
    -- 0.5 s in the middle of the wait (2.8 - 1 = 1.8 s of it): clean
    local billy2, st2 = actor(231, 4800, 0, 0, "ability_punkgoat_tether", { AbilityCastRange = 12, AbilityDuration = 2.8 })
    local w2 = world(spell, billy2)
    st2.mods = { mod("waiting_for_pull") }
    for _ = 1, 48 do step(w2) end
    local mid = aura_hits(4800, 0, 12)
    assert(mid == 0, "chain gang: the ring is drawn in the middle of the wait too (" .. mid .. " points)")
end

local function chain_negative(spell)
    local victim, vst = actor(232, 4400, 0, 0, nil, {})
    local w = world(spell, actor(233, 4400, 0, 0, "ability_punkgoat_tether", {}), { victim })
    vst.mods = { mod("waiting_for_pull") }
    run(w, 0.5)
    assert(count_groups(spell) == 0, "chain gang: the victim's modifier detected")
end

entry("billy_chain_gang", chain_positive, chain_negative)

-- Gloom Bombs: line off the thrown bomb entity (ability_nano_clustergrenade, m_particle :86270),
-- m_flSpeed 2500 and 0.75 s lifetime, m_flPhysicsRadius 2 u (:86273).
local function gloom_positive(spell)
    local calico = actor(234, 5200, 0, 0, "ability_nano_clustergrenade", {})
    local bomb, _, pos = mkproj(235, 5400, 0, 300,
        "particles/abilities/nano/nano_cluster_grenade.vpcf", "citadel_ability_nano_clustergrenade")
    local w = world(spell, calico, { bomb })
    for _ = 1, 20 do step(w); pos[1] = pos[1] + 2500 / 60 end
    assert_lane(5400, 0, 2 / UPM, 47.6, nil, "gloom bombs")
end

local function gloom_negative(spell)
    -- the explosion is a separate particle on the same bomb: it must not start a second group
    local calico = actor(236, 5200, 0, 0, "ability_nano_clustergrenade", {})
    local blast = mkproj(237, 5600, 0, 0, "particles/abilities/nano/nano_cluster_grenade_explosion.vpcf")
    local w = world(spell, calico, { blast })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "gloom bombs: the explosion particle detected")
end

entry("calico_gloom_bombs", gloom_positive, gloom_negative)

-- Leaping Slash: line off modifier_citadel_shiv_dash (m_DashModifier, ability_nano_dash:87111),
-- DashRadius 2.0 m (:86921) half-width, reach AbilityCastRange 9 m (:86813), SlashRadius 4 m
-- (:86958) placed SlashForwardOffset 1.5 m (:86994) past where the dash stops.
local function slash_positive(spell)
    local calico, st, pos = actor(238, 5800, 0, 0, "ability_nano_dash", { AbilityCastRange = 9, SlashRadius = 4 })
    local w = world(spell, calico)
    local end_x = 5800 + 9 * UPM
    -- the dash is 8.9 frames at 2400 u/s; keep the last frame within the 0.375 s the prediction
    -- is held for after the modifier drops
    local g
    for _ = 1, 15 do
        if pos[1] < end_x then pos[1] = math.min(end_x, pos[1] + 2400 / 60) end
        st.mods = pos[1] < end_x and { mod("modifier_citadel_shiv_dash") } or {}
        g = step(w) or g
    end
    assert(g, "leaping slash: no group")
    assert_lane(5800, 0, 2.0, 9, 2.5, "leaping slash lane", 3.2)
    local land = g.land or g.path and g.path[#g.path]
    assert(land, "leaping slash: no landing")
    -- the circle sits SlashForwardOffset 1.5 m past where the lane ends, on the floor
    assert_marker(land.x + 1.5 * UPM, 0, 4, "leaping slash circle")
end

local function slash_negative(spell)
    local calico = actor(239, 5800, 0, 0, "ability_nano_dash", {})
    local victim, vst = actor(240, 5800, 300, 0, nil, {})
    local w = world(spell, calico, { victim })
    calico.get_modifiers = function() return {} end
    vst.mods = { mod("modifier_citadel_shiv_dash") }
    run(w, 0.4)
    assert(count_groups(spell) == 0, "leaping slash: Shiv's modifier on a pawn without the ability detected")
end

entry("calico_leaping_slash", slash_positive, slash_negative)

-- Return to Shadows: aura while the "channeling" modifier is on him (m_AutoChannelModifier,
-- ability_nano_shadow_pulse:86760), Radius 7.5 m (:86533), the burst on cast and again on return
-- (AbilityChannelTime 3 s, :86456).
local function shadows_positive(spell)
    local calico, st = actor(241, 6200, 0, 0, "ability_nano_shadow_pulse", { Radius = 7.5, AbilityChannelTime = 3 })
    local w = world(spell, calico)
    st.mods = { mod("base_channeling") }
    local g
    for _ = 1, 12 do g = step(w) or g end -- 0.2 s in: the burst on cast
    assert(g, "return to shadows: no group")
    local r = aura_hits(6200, 0, 7.5)
    assert(r >= 40, "return to shadows: no 7.5 m ring (" .. r .. " points)")
    for _ = 1, 78 do step(w) end -- 1.5 s in: the middle of the channel stays clean
    local mid = aura_hits(6200, 0, 7.5)
    assert(mid == 0, "return to shadows: the ring is drawn mid-channel too (" .. mid .. " points)")
    for _ = 1, 60 do step(w) end -- 2.7 s in: the burst on return
    local back = aura_hits(6200, 0, 7.5)
    assert(back >= 40, "return to shadows: no ring for the return burst (" .. back .. " points)")
end

local function shadows_negative(spell)
    local victim, vst = actor(242, 6200, 0, 0, nil, {})
    local w = world(spell, actor(243, 6200, 0, 0, "ability_nano_shadow_pulse", {}), { victim })
    vst.mods = { mod("base_channeling") }
    run(w, 0.4)
    assert(count_groups(spell) == 0, "return to shadows: the victim's modifier detected")
end

entry("calico_return_to_shadows", shadows_positive, shadows_negative)

-- Light Eater: cone off AbilityCastDelay 0.3 s (ability_unicorn_radiantblast:287769), reach
-- AbilityCastRange 10 m
-- (ability_unicorn_radiantblast:287751), full width TargetingConeAngle 70 (:287878).
local function light_eater_positive(spell)
    local celeste, st = actor(244, 6600, 0, 0, "ability_unicorn_radiantblast",
        { AbilityCastRange = 10, TargetingConeAngle = 70 })
    local w = world(spell, celeste)
    st.cast = true
    for _ = 1, 8 do step(w) end
    assert_cone(6600, 10, 35, "light eater")
end

local function light_eater_negative(spell)
    local celeste, st = actor(245, 6600, 0, 0, "ability_unicorn_radiantblast", {})
    local w = world(spell, celeste)
    st.cast = false -- no cast delay: nothing to draw
    run(w, 0.4)
    assert(#REC.tris == 0, "light eater: a fan was drawn with no cast delay")
end

entry("celeste_light_eater", light_eater_positive, light_eater_negative)

-- Radiant Daggers: arc off m_TellParticle (ability_unicorn_luminousstrike:289569) landing on the
-- targeted ground; ExplosionRadius 8 m (:289310).
local function daggers_positive(spell)
    local celeste = actor(246, 7000, 0, 0, "ability_unicorn_luminousstrike", { ExplosionRadius = 8 })
    local w = world(spell, celeste)
    local at = Vector(7200, 0, 0)
    X.track_particle({ name = "particles/abilities/unicorn/unicorn_daggers_target.vpcf", entity = celeste, index = 40 })
    X.update_particle({ index = 40, control_point = 0, position = at })
    local g
    for _ = 1, 10 do g = step(w) or g end
    assert(g, "radiant daggers: no group")
    assert(math.abs(g.warning.x - 7200) < 1 and math.abs(g.warning.y) < 1, "warning not where it fell")
    assert_marker(7200, 0, 8, "radiant daggers")
end

local function daggers_negative(spell)
    local celeste = actor(247, 7000, 0, 0, "ability_unicorn_luminousstrike", {})
    local w = world(spell, celeste)
    X.track_particle({ name = "particles/abilities/unicorn/unicorn_daggers_target_dagger.vpcf", entity = celeste, index = 41 })
    X.update_particle({ index = 41, control_point = 0, position = Vector(7200, 0, 0) })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "radiant daggers: the falling dagger particle detected")
end

entry("celeste_radiant_daggers", daggers_positive, daggers_negative)

-- Shining Wonder: line off the orb (m_szBulletTravelTracerParticle :288785, m_particle :288924),
-- m_flBulletRadius 65 u (:288792) half-width, BounceRadius 15 m (:288750) reach, 1175 u/s.
local function orb_positive(spell)
    local celeste = actor(248, 7400, 0, 0, "ability_unicorn_dazzlingorb", { BounceRadius = 15 })
    local orb, _, pos = mkproj(249, 7500, 0, 100, "particles/abilities/unicorn/unicorn_ball_projectile.vpcf")
    local w = world(spell, celeste, { orb })
    for _ = 1, 20 do step(w); pos[1] = pos[1] + 1175 / 60 end
    assert_lane(7500, 0, 65 / UPM, 15, nil, "shining wonder")
end

local function orb_negative(spell)
    local celeste = actor(250, 7400, 0, 0, "ability_unicorn_dazzlingorb", {})
    local charge = mkproj(251, 7400, 0, 40, "particles/abilities/unicorn/unicorn_ball_charge.vpcf")
    local w = world(spell, celeste, { charge })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "shining wonder: the charge particle detected")
end

entry("celeste_shining_wonder", orb_positive, orb_negative)

-- run them ------------------------------------------------------------------------------------

local covered = 0
for _, f in ipairs(FIX) do
    local spell = by_id[f.id]
    local okp, errp = pcall(f.positive, spell)
    assert(okp, f.id .. " positive: " .. tostring(errp))
    local okn, errn = pcall(f.negative, spell)
    assert(okn, f.id .. " negative: " .. tostring(errn))
    covered = covered + 1
end
assert(covered == #SPELLS, ("covered %d of %d entries"):format(covered, #SPELLS))
print(("OK: %d entries detect and draw through their motion, and reject their own negative case"):format(covered))

