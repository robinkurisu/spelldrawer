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

local draws = 0
Vector = function(x, y, z) return { x = x, y = y, z = z } end
Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
Vec2 = function(x, y) return { x = x, y = y } end
Render = {
    LoadFont = function() return 1 end,
    WorldToScreen = function(v)
        -- 1 screen px per world unit, so the captured points carry exact world offsets
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
