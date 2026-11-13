-- headless harness: loads all eight files, then drives the real detect and draw code with fake
-- heroes, projectiles and particles built from the game's own vdata numbers, so cones, auras,
-- dives, dashes, lobs, bullets and the Debug Mode measurements can be checked without launching
-- the game. Run it from the repo root: lua spelldrawer_harness.lua
package.path = "./?.lua;" .. package.path
local files = { "spelldrawer.lua", "spelldrawer_detect.lua", "spelldrawer_draw.lua",
                "spelldrawer_menu.lua", "spelldrawer_spells.lua", "spelldrawer_util.lua", "spelldrawer_evade.lua",
                "spelldrawer_sim.lua" }
local ok = true
for _, f in ipairs(files) do
    local fn, err = loadfile(f)
    print((fn and "OK   " or "FAIL ") .. f .. (err and ("\n      " .. err) or ""))
    ok = ok and fn ~= nil
end
assert(ok, "load failed")

local ui = {}
local nums, switch_off = { sp_size = 2, sp_dist = 0, sp_sim_gap = 1.5, sp_dodge_gap = 0, sp_fov = 360, sp_hero_dist = 0, sp_turret_scale = 100, sp_hazard_rule = 0 }, { sp_fog = true, sp_collide = true } -- switch_off[k]: that switch reads false
for _, k in ipairs({ "sp_debug", "sp_enable", "sp_land", "sp_arc", "sp_boxes", "sp_labels",
                     "sp_points", "sp_size", "sp_dist", "sp_dodge", "sp_dodge_debug", "sp_sim_gap",
                     "sp_react", "sp_margin", "sp_parry_lead", "sp_sim_cd", "sp_replan", "sp_dodge_gap", "sp_fog", "sp_fov", "sp_collide",
                     "sp_hero_dist", "sp_turret_scale", "sp_hazard_rule" }) do
    ui[k] = { Get = function()
        if nums[k] then return nums[k] end
        return not switch_off[k]
    end }
end
ui.sp_sim = { on = false, Get = function(self) return self.on end }
local turret_off = {} -- turret_off[name]: that Avoid Turrets item unticked
ui.sp_turrets = { Get = function(_, name) return not turret_off[name] end }
ui.sp_aggro = { down = false, IsDown = function(self) return self.down end }
ui.sp_danger_only = { down = false, IsDown = function(self) return self.down end }
local guard_off = {}
ui.sp_guard = { Get = function(_, name) return not guard_off[name] end }
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
-- by exact class name, out of whatever get_all gives at the time
entity_list.by_class_name = function(cls)
    local out = {}
    for _, e in ipairs(entity_list.get_all()) do
        if e.get_class_name and e.get_class_name() == cls then out[#out + 1] = e end
    end
    return out
end
HERO_LIB = {
    is_ability_in_cast_delay = function() return false end,
    is_channeling_ability = function() return false end,
    is_same_team = function() return false end,
    get_hero_id = function(p) return p._hero_id end, -- a fixture hero carries its m_HeroID here
}

local U = require("spelldrawer_util")
local SPELLS = require("spelldrawer_spells")
local X = require("spelldrawer_detect")
local D = require("spelldrawer_draw")
local S = U.state

-- the ability cache: one search per hero and key inside AB_KEEP, found or not, and again after it
do
    local searches, has = 0, false
    local ab = { get_name = function() return "citadel_ability_cached" end }
    local hero = { get_handle = function() return 4242 end,
                   get_ability_by_slot = function() searches = searches + 1 return has and ab or nil end }
    S.now = 10
    assert(U.find_ability(hero, "cached") == nil and U.find_ability(hero, "cached") == nil)
    assert(searches == #U.SLOTS, "ability cache: a miss searched for twice inside AB_KEEP")
    has, S.now = true, 10 + U.CFG.AB_KEEP
    assert(U.find_ability(hero, "cached") == ab, "ability cache: not searched for again after AB_KEEP")
    -- a hit is read again from its slot alone: the ability itself is never kept past the call
    assert(U.find_ability(hero, "cached") == ab and searches == #U.SLOTS + 2, "ability cache: a hit searched for twice")
    has = false
    assert(U.find_ability(hero, "cached") == nil, "ability cache: an ability gone from its slot still given")
    S.now = 0
    print("OK: ability cache")
end
-- the walk over every entity, spread over frames: a class-matched carrier at the end of the list is
-- not seen by the first scan, is found by a later frame's share, and is drawn by the scan after that
do
    local spell
    for _, s in ipairs(SPELLS) do if s.classes and not spell then spell = s end end
    for _, s in ipairs(SPELLS) do s.ui = { Get = function(_, n) return n == nil or n == spell.name end } end
    local function ent(h, cls, extra)
        local e = { valid = function() return true end, get_handle = function() return h end,
                    get_class_name = function() return cls end, get_vdata_class_name = function() return cls end,
                    get_origin = function() return Vector(0, 0, 0) end, get_particles = function() return {} end,
                    get_modifiers = function() return {} end, get_ability_by_slot = function() return nil end }
        for k, v in pairs(extra or {}) do e[k] = v end
        return e
    end
    local hero = ent(501, "C_CitadelPlayerPawn", { _hero_id = spell.hero_id })
    local bomb = ent(502, "c_" .. spell.classes[1])
    S.me = ent(500, "C_CitadelPlayerPawn", { _hero_id = -1 })
    local list = { S.me, hero }
    for i = 1, 9 do list[#list + 1] = ent(510 + i, "prop") end
    list[#list + 1] = bomb
    entity_list.get_all = function() return list end
    local function has() for _, g in pairs(S.groups) do if g.spell == spell then return true end end return false end
    U.CFG.WALK_FRAMES = 4 -- 12 entities: 3 a frame
    S.now, S.next_scan = 100, 0
    X.scan()
    assert(not has(), "walk: the whole list read in the first scan")
    for i = 1, 3 do S.now = 100 + i * 0.01 X.scan() end -- not due: the walk alone, to the end of the list
    assert(S.next_scan == 0, "walk: a new carrier didn't ask for a scan")
    S.now = 100.05
    X.scan()
    assert(has(), "walk: the carrier it found not read by the next scan")
    list[#list] = nil -- gone: dropped by the scan, and no group once the kept one runs out
    bomb.get_class_name = function() return nil end
    S.now = 101
    X.scan()
    S.now = 102
    X.scan()
    assert(not has(), "walk: a carrier that is gone still read")
    -- a class with nothing on it WALK_QUIET looks in a row is passed over (no position read), and
    -- looked at again on a probe round
    local reads = 0
    for i = 3, 11 do list[i].get_origin = function() reads = reads + 1 return Vector(0, 0, 0) end end
    U.CFG.WALK_FRAMES, U.CFG.WALK_QUIET, U.CFG.WALK_PROBE = 1, 5, 4
    local none, all9 = false, false
    for i = 1, 9 do -- a round a call
        reads = 0
        S.now = 110 + i
        X.scan()
        if i > 2 then none, all9 = none or reads == 0, all9 or (none and reads == 9) end
    end
    assert(none, "walk: a quiet class still read every round")
    assert(all9, "walk: a quiet class never looked at again on a probe round")
    U.CFG.WALK_PROBE = 20
    S.now, S.next_scan, S.groups, S.list, S.me = 0, 0, {}, {}, nil
    entity_list.get_all = function() return {} end
    print("OK: the walk over every entity is spread over frames")
end
-- the fixtures below swap abilities and units between clock steps shorter than these, and expect
-- an entity seen by the scan it appears in: uncached, and the whole walk each frame, no class passed over
U.CFG.AB_KEEP, U.CFG.UNITS_KEEP, U.CFG.WALK_FRAMES, U.CFG.WALK_QUIET = 0, 0, 1, math.huge

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
-- the viewer every early fixture draws for: an enemy of the caster, as only enemy spells draw
local foe = { get_handle = function() return 99 end }
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
        local ok, err = pcall(D.draw_entity, g, foe)
        assert(ok, "draw error: " .. tostring(err))
    end
    return g, draws
end

local g = frame(0)
assert(g, "no group from the trigger particle")
assert(g.caster == bebop, "group not pinned to the caster")
assert(g.cone_at == 0, "cone_at not stamped: " .. tostring(g.cone_at))
print("t=0.00 cast frame, fan drawn = " .. tostring(draws > 0))
assert(draws > 0, "fan not drawn on the cast frame: Evade loses the wind-up")
local _, d25 = frame(0.25)
print(("t=0.25 fan drawn = %s"):format(tostring(d25 > 0)))
assert(d25 > 0, "fan not drawn at the punch")
-- geometry at the swing: the fan must reach 6 m (MeleeAttackLength) and span 120 degrees
local pts = {}
local ccw = 0 -- triangles reaching the renderer counter-clockwise on screen: their joins show as lines
Render.FilledTriangle = function(tri)
    pts[#pts + 1] = tri[2]; pts[#pts + 1] = tri[3]
    local a, b, c = tri[1], tri[2], tri[3]
    if (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) < 0 then ccw = ccw + 1 end
end
local g2 = frame(0.27)
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
assert(#pts == 2 * 48, "expected 48 fan triangles: the fan's 24 and its countdown fill's 24")
assert(ccw == 0, ccw .. " fan triangles drawn counter-clockwise")
-- the same swing seen as your own (Debug Mode is on here) and as an ally's: nothing drawn
pts = {}
pcall(D.draw_entity, g2, bebop)
local same_team = HERO_LIB.is_same_team
HERO_LIB.is_same_team = function() return true end
pcall(D.draw_entity, g2, foe)
HERO_LIB.is_same_team = same_team
assert(#pts == 0, "your own or an ally's spell was drawn")
print("OK: only enemy spells draw, Debug Mode or not")

Render.FilledTriangle = function() draws = draws + 1 end
-- the swing particle is still on him at 0.4 s, but the punch has landed: the fan is gone
local _, after = frame(0.4)
print("t=0.40 punch landed, particle still up, fan drawn = " .. tostring(after > 0))
assert(after == 0, "fan still drawn after the punch landed")
local _, late = frame(1.1)
print("t=1.10 past the swing, fan drawn = " .. tostring(late > 0))
assert(late == 0, "fan still drawn after the swing")
print("OK: trigger, 0.2 s delay, ends at the 0.3 s punch, 6 m reach, 120 degree angle")

-- ---- aura tail grace: Return to Shadows' ring must outlive the burst it marks (a 2.8 s channel here) ----
local chain
for _, s in ipairs(SPELLS) do if s.id == "calico_return_to_shadows" then chain = s end end
assert(chain, "Return to Shadows entry missing")
local cprops = { Radius = "7.5", AbilityChannelTime = "2.8" }
local cab = {
    get_name = function() return "ability_nano_shadow_pulse" end,
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
        if billyMod then return { { get_name = function() return "channeling" end } } end
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
        local ok, err = pcall(D.draw_entity, rec, foe)
        assert(ok, "aura draw error: " .. tostring(err))
    end
    return rec, lines
end

-- modifier runs t=0 .. 2.8 (the burst as he returns); sample it like the 0.25 s scan does
for _, t in ipairs({ 0, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75, 2.8 }) do
    aura(t)
end
local before = select(2, aura(1.75))
local shown = select(2, aura(1.85))
print(("t=1.75 (before the last second)    ring drawn = %s"):format(tostring(before > 0)))
print(("t=1.85 (in the last second)        ring drawn = %s"):format(tostring(shown > 0)))
assert(before == 0, "ring drawn before the last second")
assert(shown > 0, "ring not drawn in the tail")
billyMod = false
for _, t in ipairs({ 3.05, 3.1, 3.2 }) do aura(t) end
local at_pull = select(2, aura(2.9))
print(("t=2.90 (0.1 s past the burst)      ring drawn = %s"):format(tostring(at_pull > 0)))
assert(at_pull > 0, "ring vanished the moment the burst landed")
local gone = select(2, aura(3.4))
print(("t=3.40                             ring drawn = %s"):format(tostring(gone > 0)))
assert(gone == 0, "ring never cleared")
print("OK: tail holds 0.15 s past the marked moment and clears after")

-- your own hero aims with the camera, not his lagging eye angles or body; others fall back to the body
S.me = bebop
utils = { get_camera_angles = function() return { pitch = 0, yaw = 90 } end }
local f, src = U.aim_dir(bebop)
assert(src == "camera" and math.abs(f.y - 1) < 1e-6, "own aim not from the camera: " .. tostring(src))
S.me = { get_handle = function() return 99 end }
f, src = U.aim_dir(bebop)
assert(src ~= "camera" and math.abs(f.x - 1) < 1e-6, "another hero's aim read the camera")
utils = nil
print("OK: own aim from the camera, others from their own angles")

-- an enemy Celeste whose abilities read as missing casts Radiant Daggers: the tell comes with no
-- entity, only a position at its target, and must still go to her
local daggers
for _, s in ipairs(SPELLS) do if s.id == "celeste_radiant_daggers" then daggers = s end end
assert(daggers, "Radiant Daggers entry missing")
-- a fake hero. origin: function, so a test can move him; mods: function returning modifier names;
-- ability: what every slot reads (nil: his abilities read as missing, like an enemy's can)
local function pawn(h, origin, mods, ability)
    return {
        valid = function() return true end,
        get_handle = function() return h end,
        get_class_name = function() return "C_CitadelPlayerPawn" end,
        get_origin = origin,
        get_angles = function() return { GetForward = function() return Vector(0, 1, 0) end } end,
        get_ability_by_slot = function() return ability end,
        get_modifiers = function()
            local out = {}
            for i, n in ipairs(mods and mods() or {}) do out[i] = { get_name = function() return n end } end
            return out
        end,
        get_particles = function() return {} end,
    }
end
local celeste = pawn(9, function() return Vector(1000, 0, 0) end)
celeste._hero_id = 81 -- hero_unicorn.m_HeroID
local far = pawn(10, function() return Vector(0, 0, 0) end)
S.me = far
entity_list.get_all = function() return { far, celeste } end
entity_list.by_handle = function() return nil end
local TELL = "particles/abilities/unicorn/unicorn_daggers_target.vpcf"
local function daggers_group()
    for _, rec in pairs(S.groups) do if rec.spell == daggers then return rec end end
end
S.groups, S.events, S.next_scan, S.now, S.rt = {}, {}, 0, 50, 50
X.track_particle({ name = TELL, index = 77 })
X.update_particle({ index = 77, control_point = 0, position = Vector(1010, 20, 60) })
X.scan()
local eg = daggers_group()
assert(eg and eg.owner == celeste, "Radiant Daggers not handed to the enemy Celeste")
print("OK: an ownerless Radiant Daggers tell goes to the hero playing Celeste")

-- point-blank: you stand closer to the tell than she does, but you aren't Celeste, so it still
-- goes to her, not to you (yours would be hidden)
local your_ab = { get_name = function() return "citadel_ability_uppercut" end, get_cooldown = function() return 0 end }
local you = pawn(13, function() return Vector(1015, 25, 30) end, nil, your_ab)
S.me = you
entity_list.get_all = function() return { you, celeste } end
S.groups, S.events, S.next_scan, S.now, S.rt = {}, {}, 0, 60, 60
X.track_particle({ name = TELL, index = 78 })
X.update_particle({ index = 78, control_point = 0, position = Vector(1010, 20, 60) })
X.scan()
eg = daggers_group()
assert(eg and eg.owner == celeste, "a point-blank Radiant Daggers tell was handed to you")
S.me = far
print("OK: a point-blank Radiant Daggers tell stays with Celeste, not the closer hero who isn't her")

-- nobody plays Celeste: an ownerless tell has no caster and is dropped, not guessed
S.me = you
entity_list.get_all = function() return { you, far } end
S.groups, S.events, S.next_scan, S.now, S.rt = {}, {}, 0, 70, 70
X.track_particle({ name = TELL, index = 79 })
X.update_particle({ index = 79, control_point = 0, position = Vector(1010, 20, 60) })
X.scan()
assert(not daggers_group(), "a Radiant Daggers tell with no Celeste out was handed to someone")
S.me = far
for _, s in ipairs(SPELLS) do
    assert(s.hero_id or s.item, s.id .. ": no hero_id") -- an item is any hero's
    -- an enemy's ability often doesn't read; without a fallback the area shrinks to a default
    assert(not s.radius_prop or s.radius, s.id .. ": radius_prop with no radius fallback")
end
print("OK: no Celeste, no owner; every entry knows its hero's m_HeroID")

-- an enemy whose slots read empty but whose full ability list holds it: its radius is read,
-- upgrades included, not the 8 m fallback
local listed = pawn(15, function() return Vector(0, 0, 0) end)
listed.get_abilities = function()
    return { { get_name = function() return "ability_unicorn_luminousstrike" end,
               get_scaled_property = function(_, p) return p == "ExplosionRadius" and "10" or nil end } }
end
local blast_r = U.ability_value(listed, daggers, daggers.radius_prop, daggers.radius) / U.CFG.UNITS_PER_M
assert(math.abs(blast_r - 10) < 1e-6, "an enemy's listed Radiant Daggers radius not read: " .. blast_r)
print(("OK: an enemy's Radiant Daggers radius is read from his ability list: %.0f m"):format(blast_r))

-- the drawing tests below count filled triangles
local fans = 0
Render.FilledTriangle = function() fans = fans + 1 end

-- Seismic Impact: Abrams dives from the air and lands at t=1.0; the crash modifier stays on him
-- until 1.7. The landing marker must show during the dive and be gone once he touches down.
local slam
for _, s in ipairs(SPELLS) do if s.id == "abrams_seismic_impact" then slam = s end end
assert(slam, "Seismic Impact entry missing")
-- hangs at 800 units for 0.2 s, then dives at 1000 u/s and lands at t=1.0
local function abrams_z(t) return t < 0.2 and 800 or math.max(0, 800 - 1000 * (t - 0.2)) end
local abrams = pawn(11, function() return Vector(2000, 0, abrams_z(S.now - 100)) end,
    function() return S.now - 100 <= 1.7 and { slam.modifier } or {} end)
HERO_LIB.is_on_ground = function(e) return e.get_origin().z <= 0 end
trace.line = function(a, b)
    if b.z < 0 then return { fraction = a.z / (a.z - b.z) } end
    return { fraction = 1 }
end
entity_list.get_all = function() return { far, abrams } end
S.groups, S.events, S.next_scan, S.now, S.rt = {}, {}, 0, 100, 100
local function slam_at(t)
    local land
    while S.now < 100 + t - 1e-9 do
        S.now = S.now + 1 / 60
        X.scan()
        X.track_projectiles(1 / 60)
    end
    for _, rec in pairs(S.groups) do if rec.spell == slam then land = rec.land end end
    return land
end
local function slam_drawn()
    fans = 0
    for _, rec in pairs(S.groups) do
        if rec.spell == slam then pcall(D.draw_entity, rec, far) end
    end
    return fans > 0
end
assert(slam_at(0.1) == nil and not slam_drawn(), "a guess made while Abrams hangs before the dive")
local mid = slam_at(0.5)
assert(mid and math.abs(mid.x - 2000) < 1 and mid.z < 10, "no landing predicted under Abrams mid-dive")
assert(not slam_drawn(), "marker drawn 0.5 s before impact, outside the 0.3 s window")
assert(slam_at(0.85) and slam_drawn(), "marker not drawn 0.15 s before impact")
assert(slam_at(1.1) == nil, "landing marker still drawn after the slam landed")
assert(slam_at(1.6) == nil, "landing marker came back while the modifier lingers")
print("OK: Seismic Impact's marker shows during the dive and ends on touchdown, not with the modifier")

-- a modifier spell that starts just after a scan is picked up on the next frame, not a scan later
local charge
for _, s in ipairs(SPELLS) do if s.id == "abrams_shoulder_charge" then charge = s end end
assert(charge, "Shoulder Charge entry missing")
local charging = false
local bull = pawn(12, function() return Vector(-2000, 0, 0) end,
    function() return charging and { charge.modifier } or {} end)
entity_list.get_all = function() return { far, bull } end
S.groups, S.next_scan, S.now = {}, 0, 200
X.scan()                                 -- regular scan at 200.000; the next one is due at 200.25
charging, S.now = true, 200 + 3 / 60     -- the charge starts between scans
X.scan()
local key = "abrams_shoulder_charge:mod" .. tostring(bull.get_handle())
assert(S.groups[key], "Shoulder Charge not picked up until the next regular scan")
local due = S.next_scan
S.now = 200 + 4 / 60
X.scan()
assert(S.next_scan == due, "a modifier that stays on forced another early scan")
print("OK: a modifier spell is picked up the frame it starts, and only that frame scans early")

-- Blood Bomb: lobbed at t=0, lands and goes off at t=1.0, when its entity goes. Its group is
-- kept for CLEAR_DELAY after that, but nothing of it may be drawn past the blast.
local bomb_spell
for _, s in ipairs(SPELLS) do if s.id == "ghost_blood_bomb" then bomb_spell = s end end
assert(bomb_spell, "Blood Bomb entry missing")
local geist = pawn(14, function() return Vector(3000, 0, 0) end)
local function bomb_t() return S.now - 300 end
local bomb = {
    m_hOwnerEntity = 14,
    valid = function() return bomb_t() < 1.0 end,
    get_handle = function() return 15 end,
    get_class_name = function() return "C_Projectile_BloodBomb" end,
    get_origin = function()
        local t = bomb_t()
        return Vector(3000 + 600 * t, 0, 200 + 200 * t - 400 * t * t)
    end,
    get_particles = function()
        return { { name = "particles/abilities/ghost/ghost_blood_bomb_projectile.vpcf", control_points = {} } }
    end,
}
entity_list.get_all = function() return { far, geist, bomb } end
entity_list.by_handle = function(h) if h == 14 then return geist end end
S.groups, S.events, S.next_scan, S.now, S.rt = {}, {}, 0, 300, 300
local function bomb_at(t)
    while S.now < 300 + t - 1e-9 do
        S.now = S.now + 1 / 60
        X.scan()
        X.track_projectiles(1 / 60)
    end
    local rec
    for _, r in pairs(S.groups) do if r.spell == bomb_spell then rec = r end end
    fans = 0
    if rec then pcall(D.draw_entity, rec, far) end
    return rec, fans > 0
end
local rec_fly, drawn_fly = bomb_at(0.5)
assert(rec_fly and rec_fly.land and drawn_fly, "Blood Bomb landing not drawn mid-flight")
local rec_after, drawn_after = bomb_at(1.1)
assert(rec_after, "group already dropped, so this case doesn't test the kept group")
assert(not drawn_after, "Blood Bomb landing still drawn after the blast")
print("OK: Blood Bomb's landing is drawn in flight and gone the moment the bomb goes off")

-- the landing warning's first position scans at once, so the marker comes with the game's ring
X.track_particle({ name = "particles/abilities/ghost/ghost_blood_bomb_warning.vpcf", index = 301 })
S.next_scan = 999
X.update_particle({ index = 301, control_point = 0, position = Vector(3600, 0, 0) })
assert(S.next_scan == 0, "warning's first position didn't trigger a scan")
S.next_scan = 999
X.update_particle({ index = 301, control_point = 0, position = Vector(3600, 0, 0) })
assert(S.next_scan == 999, "every warning update triggers a scan")
print("OK: a landing warning is placed the frame it gets a position")

-- Abrams' Shoulder Charge also carries modifier_shoulder_charge_buff, which Rising Ram's modifier
-- matched while it was a bare "charge", and wiped Shoulder Charge's lane. As "goatflip/charge" it
-- matches neither your own Abrams nor an enemy whose abilities all read as missing.
local sc, ram
for _, s in ipairs(SPELLS) do
    if s.id == "abrams_shoulder_charge" then sc = s end
    if s.id == "billy_rising_ram" then ram = s end
end
local charge_ab = { get_name = function() return "citadel_ability_bull_charge" end,
    get_scaled_property = function() return nil end, get_cooldown = function() return 0 end }
local function charger(h, readable)
    return pawn(h, function() return Vector(-8000 + 700 * (S.now - 600), h * 1000, 0) end,
        function() return { "modifier_citadel_bull_charging", "modifier_shoulder_charge_buff" } end,
        readable and charge_ab or nil)
end
local own, enemy = charger(31, true), charger(32, false)
trace = { line = function() return { fraction = 1 } end }
entity_list.get_all = function() return { far, own, enemy } end
S.groups, S.events, S.next_scan, S.now, S.rt = {}, {}, 0, 600, 600
for i = 1, 30 do
    S.now = 600 + i / 60
    X.scan()
    X.track_projectiles(1 / 60)
end
local function rec_for(spell, pawn)
    return S.groups[spell.id .. ":mod" .. tostring(pawn.get_handle())]
end
assert(not rec_for(ram, own), "Rising Ram matched on your own Abrams")
assert(rec_for(sc, own) and rec_for(sc, own).path, "own Shoulder Charge has no lane")
assert(not rec_for(ram, enemy), "Rising Ram matched an enemy Abrams' modifier_shoulder_charge_buff")
assert(rec_for(sc, enemy) and rec_for(sc, enemy).path, "the enemy's Shoulder Charge has no lane")
print("OK: Shoulder Charge keeps its lane; Rising Ram's modifier doesn't match Abrams' charge buff")

-- Debug Mode measures a projectile particle's real flight when it is destroyed
local logged = {}
local real_print = print
print = function(s) logged[#logged + 1] = tostring(s) end
S.now = 700
X.track_particle({ name = "particles/abilities/unicorn/unicorn_ball_projectile.vpcf", index = 401 })
X.update_particle({ index = 401, control_point = 0, position = Vector(0, 0, 0) })
S.now = 701
X.update_particle({ index = 401, control_point = 0, position = Vector(2000, 0, 0) })
X.destroy_particle({ index = 401 })
print = real_print
local flight
for _, l in ipairs(logged) do if l:find("Shining Wonder flight", 1, true) then flight = l end end
assert(flight and flight:find("50.8 m in 1.00 s", 1, true), "flight not measured: " .. tostring(flight))
print("OK: " .. flight:gsub("^%[.-%] ", ""))

-- Debug Mode places a bullet spell's skipped effects (here the orb's hover) against the last shot
local orb_spell
for _, s in ipairs(SPELLS) do if s.id == "celeste_shining_wonder" then orb_spell = s end end
orb_spell.ui = { Get = function() return true end }
local cel = pawn(41, function() return Vector(0, 0, 0) end)
local hover_log
local real_print2 = print
print = function(s) if tostring(s):find("unicorn_ball_hover", 1, true) then hover_log = tostring(s) end end
S.now = 800
X.track_bullet({ weapon_name = "ability_unicorn_dazzlingorb", shooter = cel, start_pos = Vector(0, 0, 50),
    direction = Vector(1, 0, 0) })
S.now = 801.2
X.track_particle({ name = "particles/abilities/unicorn/unicorn_ball_hover.vpcf", index = 501 })
X.update_particle({ index = 501, control_point = 0, position = Vector(2362.2, 0, 50) })
print = real_print2
assert(hover_log and hover_log:find("60.0 m from the shot, 1.20 s after", 1, true), "hover not measured: " .. tostring(hover_log))
print("OK: " .. hover_log:gsub("^%[.-%] ", ""))

-- a Shining Wonder shot's lane runs as far as the orb flies, 2 s at 2000 u/s (in game it hit from
-- 66.7 m, past the 22.2 m lane this used to be), not the 15 m bounce radius
local orb_lane
for _, r in pairs(S.groups) do if r.shot and r.spell == orb_spell then orb_lane = r end end
assert(orb_lane and orb_lane.land, "no Shining Wonder lane from the bullet")
local reach = math.sqrt(orb_lane.land.x ^ 2 + orb_lane.land.y ^ 2) / U.CFG.UNITS_PER_M
assert(math.abs(reach - 101.6) < 0.05, ("Shining Wonder lane is %.2f m, not 101.6 m"):format(reach))
print(("OK: Shining Wonder's lane reaches %.1f m"):format(reach))
;(function() -- (its own function: the main chunk is at Lua's 200-locals limit)
    -- Max Distance counts a shot's lane by its nearest point, not its far end: this one starts beside
    -- you and ends 101.6 m off, in range at 50 m
    local me = S.me
    S.me, nums.sp_dist, S.zones = far, 50, {}
    D.draw_entity(orb_lane, far)
    S.me, nums.sp_dist = me, 0
    assert(#S.zones > 0, "a Shining Wonder lane beside you dropped for ending past Max Distance")
    -- wherever the shot starts from, well away from her included, its lane is the whole range: taken
    -- for a bounce and cut to 15 m, it left first shots from 24.8 m undrawn
    X.track_bullet({ weapon_name = "ability_unicorn_dazzlingorb", shooter = cel, start_pos = Vector(400, 0, 50),
        direction = Vector(0, 1, 0) })
    local off
    for _, r in pairs(S.groups) do if r.shot and r.spell == orb_spell and r ~= orb_lane then off = r end end
    assert(off and math.abs(off.land.y / U.CFG.UNITS_PER_M - 101.6) < 0.05, "a Shining Wonder shot starting off her cut short")
    S.zones = {}
end)()
-- ---- a dash shorter than a scan: Leaping Slash must be caught frame by frame ----
local dash
for _, s in ipairs(SPELLS) do if s.id == "calico_leaping_slash" then dash = s end end
assert(dash, "Leaping Slash entry missing")

-- the dump's own numbers: AbilityCastRange 9 m at DashSpeed 2400 u/s is 0.147 s of dash, and the
-- 4 m SlashRadius ring rides on her while it runs
local DASH_M, SLASH_M, SPEED = 9, 4, 2400
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

-- the slash ring rides on her: count line ends SlashRadius from where she is this frame (the
-- stub puts world (x, 0) at screen (100 + x, 100))
local ring_n = 0
Render.Line = function(a, b)
    for _, p in ipairs({ a, b }) do
        local d = math.sqrt((p.x - 100 - x) ^ 2 + (p.y - 100) ^ 2) / U.CFG.UNITS_PER_M
        if math.abs(d - SLASH_M) < 0.02 then ring_n = ring_n + 1 end
    end
end

-- one 60 fps frame of the real loop: scan (self-gated to SCAN_EVERY), modifier poll, tracking, draw
local function dash_frame(t, hit, abil)
    S.now, S.rt = t, t
    ring_n = 0
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
    return rec, ring_n
end

local function dash_run(name, use_particle, abil)
    run_n = run_n + 1
    calico.get_modifiers = function() return {} end
    S.groups, S.list, S.next_scan, S.events = {}, {}, 0, {}
    local seen, drawn, printed, next_scan, held, cleared
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
        -- a full 4 m ring is two strokes of 48 segments; the head and pulse rings are other radii
        local ring = d >= 40 and 1 or 0
        if ring > 0 then drawn = drawn or t end
        if t >= end_t + 0.15 and t <= end_t + 0.2 then held = held or ring end
        if t >= end_t + 0.55 then cleared = cleared or ring end
    end
    return { seen = seen, drawn = drawn, held = held, cleared = cleared }
end

local only = dash_run("modifier only", false)
print(("  modifier only: group at %.3f, ring on her at %.3f"):format(only.seen or -1, only.drawn or -1))
assert(only.seen, "the modifier was never seen: the dash fell between two scans")
assert(only.drawn and only.drawn < START_T + DURATION, "no SlashRadius ring on her during the dash")
print(("  0.15 s after the dash: drawn = %s; 0.55 s after: drawn = %s")
    :format(tostring(only.held > 0), tostring(only.cleared > 0)))
assert(only.held > 0, "ring gone the moment the dash ended")
assert(only.cleared == 0, "ring never cleared")

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

-- m_DashModifier is m_bIsHidden: get_modifiers() and the particle both silent, the add-modifier
-- callback alone, tied to the entry by the ability that made it, must start the ring
local function added(abil)
    return { get_name = function() return "modifier_citadel_shiv_dash" end,
             get_ability = function() return { get_name = function() return abil end } end }
end
x = START_X + 100
S.groups, S.list, S.next_scan, S.events = {}, {}, 0, {}
calico.get_modifiers = function() return {} end
shiv.get_modifiers = function() return {} end
S.now, S.rt = 2, 2
X.track_modifier_add(added("citadel_ability_shiv_dash"), shiv)
local shiv_cb = 0
for _, r in pairs(S.groups) do if r.spell == dash then shiv_cb = shiv_cb + 1 end end
assert(shiv_cb == 0, "a modifier from Shiv's own dash started the Calico entry")
X.track_modifier_add(added("citadel_ability_nano_dash"), calico)
local cb_ring = 0
for i = 1, 12 do
    local t = 2 + i / 60
    S.now, S.rt, ring_n = t, t, 0
    X.scan()
    X.track_modifiers()
    X.track_projectiles(1 / 60)
    for _, r in pairs(S.list) do
        if r.spell == dash then assert(pcall(D.draw_entity, r, shiv), "callback dash draw error") end
    end
    if ring_n >= 40 then cb_ring = cb_ring + 1 end
end
print(("  hidden modifier, callback only: ring on her %d of 12 frames"):format(cb_ring))
assert(cb_ring == 12, "the add-modifier callback did not keep the ring on her")
print("OK: dash caught between scans, slash ring on her, clears after, Shiv excluded")

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
    s.wz = v.z
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
    if f < 0 or f > 1 then return { fraction = 1 } end
    return { fraction = f, normal = { x = 0, y = 0, z = 1 } }
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
    get_hero_id = function(p) return p._hero_id end, -- a fixture hero carries its m_HeroID here
}

local function world(spell, caster, extras)
    local w = { spell = spell, caster = caster, all = { caster }, t = 0 }
    caster._hero_id = spell.hero_id -- the caster plays the spell's hero; extras and the viewer don't
    for _, e in ipairs(extras or {}) do w.all[#w.all + 1] = e end
    w.all[#w.all + 1] = viewer
    entity_list.get_all = function() return w.all end
    entity_list.by_handle = function(_, h)
        for _, e in ipairs(w.all) do if e.get_handle() == h then return e end end
    end
    S.me, S.now, S.rt = viewer, 0, 0
    S.groups, S.list, S.events, S.next_scan = {}, {}, {}, 0
    S.holders, S.near = {}, {}
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
    local n, off, rim, keep = 0, false, false, {}
    for _, t in ipairs(REC.tris) do
        if from(t[1], cx) < 0.5 * UPM then
            n = n + 1
            -- the disc's rim is at the radius; its countdown disc is inside it, never past it
            for i = 2, 3 do
                local d = from(t[i], cx) / UPM - radius
                if d > 0.02 then off = true end
                if math.abs(d) <= 0.02 then rim = true end
            end
            keep[#keep + 1] = t[1]
        end
    end
    assert(n >= 16, label .. ": marker not drawn at the expected spot (" .. n .. " triangles)")
    assert(rim and not off, label .. ": marker ring radius is not " .. radius .. " m")
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
    -- the bomb names no owner and comes before every hero in the entity list: the scan must have
    -- listed the heroes first, or it asks who plays Geist with none seen yet and drops it
    table.remove(w.all, 2)
    table.insert(w.all, 1, bomb)
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
            break
        end
        assert(_ < 60, "blood bomb: no landing predicted")
    end

    -- Its fuse starts when it lands (ArmingDuration 0.65 s, PBF_StartDetonateTimeOnHitWorld). In flight
    -- it blows 0.65 s after the landing, not as it lands: timed to the landing, Counterspell went at
    -- once on a blast a walk or dash got out of. Lying there its area is on it and the time holds;
    -- gone as it blows
    local bomb2, _, pos2 = mkproj(206, 1400, 0, 400, "particles/abilities/ghost/ghost_blood_bomb_projectile.vpcf")
    local w2 = world(spell, actor(205, 1000, 0, 0, "ability_blood_bomb", { Radius = 7 }), { bomb2 })
    local x2, z2, vz2, flew, landed, blast = 1400, 400, -400, false, nil, nil
    for i = 1, 90 do
        if z2 > 0 then
            x2, z2, vz2 = x2 + 400 / 60, math.max(0, z2 + vz2 / 60), vz2 - 800 / 60
            if z2 == 0 then landed = i / 60 end
        end
        pos2[1], pos2[3] = x2, z2
        S.zones = {}
        local g = step(w2)
        local zn = S.zones[1]
        if z2 > 0 and g and g.path then
            flew = true
            assert(zn and math.abs(zn.at - (g.lands_at + 0.65)) < 1e-6, "blood bomb: in flight, not timed 0.65 s past its landing")
            assert(math.abs(g.lands_at - 0.63) < 0.06, ("blood bomb: lands at %.2f s, wanted 0.63"):format(g.lands_at))
        elseif landed and i / 60 > landed + 0.15 then
            assert(zn and not g.path, "blood bomb: no area while it lies there armed")
            assert(math.abs(zn.x - x2) < 1 and math.abs(zn.y) < 1, "blood bomb: its area not on the bomb where it lies")
            blast = blast or zn.at
            assert(zn.at == blast, "blood bomb: its blast time moves while it lies there")
        end
    end
    assert(flew and blast and math.abs(blast - (landed + 0.65)) < 0.08,
        ("blood bomb: blast at %s, landed at %s"):format(tostring(blast), tostring(landed)))
    bomb2.valid = function() return false end
    S.zones = {}
    step(w2)
    assert(#S.zones == 0, "blood bomb: its area still up after it blew")
    -- the entry needs an area up at the end: one more bomb in flight
    local bomb3, _, pos3 = mkproj(207, 1400, 0, 400, "particles/abilities/ghost/ghost_blood_bomb_projectile.vpcf")
    local w3 = world(spell, actor(208, 1000, 0, 0, "ability_blood_bomb", { Radius = 7 }), { bomb3 })
    local g3
    for i = 1, 12 do pos3[1], pos3[3] = 1400 + 400 * i / 60, 400 - 400 * i / 60; g3 = step(w3) end
    -- you under its arc: it touches you and its fuse starts there (PBF_StartDetonateTimeOnHitTarget),
    -- so its area is on you, 0.65 s past reaching you, not where it would have landed
    local k = math.floor(#g3.path / 2)
    local p = g3.path[k]
    S.me = mkpawn(209, { p.x, p.y, p.z - 40 }, nil, { mods = {}, particles = {} })
    S.zones = {}
    g3 = step(w3)
    local zn = S.zones[1]
    -- reached where your body (1 m round) begins, up to 40 u, 0.1 s at its 400 u/s, short of the point over you
    assert(zn and math.abs(zn.x - p.x) < 60 and zn.at < g3.lands_at + 0.65 - 0.05
        and math.abs(zn.at - (S.now + (k - 1) * U.CFG.ARC_DT + 0.65)) < 0.15,
        ("blood bomb: not burst on you in its way, its fuse started there (%s)"):format(zn and
        ("%.0f u short, %.2f s off"):format(p.x - zn.x, zn.at - (S.now + (k - 1) * U.CFG.ARC_DT + 0.65)) or "none"))
    S.me = viewer
end

local function blood_bomb_negative(spell)
    local geist = actor(203, 1000, 0, 0, "ability_blood_bomb", { Radius = 7 })
    local preview = mkproj(204, 1400, 0, 400, "particles/abilities/ghost/ghost_blood_bomb_preview.vpcf")
    local w = world(spell, geist, { preview })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "blood bomb: the preview particle detected")

    -- the explode particle (m_ExplodeParticle, :55905) and the pool it leaves (:55910) keep the
    -- entry's bare particle stem: both must be skipped, not just draw nothing
    for i, name in ipairs({ "particles/abilities/ghost/ghost_blood_bomb_explode.vpcf",
                            "particles/abilities/ghost/ghost_blood_bomb_spilled_blood.vpcf" }) do
        local p = mkproj(210 + i, 9000, 0, 40, name)
        local w2 = world(spell, actor(220 + i, 9000, 0, 0, "ability_blood_bomb", {}), { p })
        X.track_particle({ name = name, entity = p, index = 90 + i })
        X.update_particle({ index = 90 + i, control_point = 0, position = Vector(9000, 0, 40) })
        local drew = 0
        for _ = 1, 20 do step(w2); drew = drew + #REC.tris + #REC.lines end
        assert(count_groups(spell) == 0, "blood bomb: " .. name:match("[^/]+$") .. " answered to the key")
        assert(drew == 0, "blood bomb: " .. name:match("[^/]+$") .. " drew " .. drew .. " primitives")
    end
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
    -- timed at his 700 u/s from his first frames, not the crawl he sets off at
    for _ = 1, 3 do S.zones = {}; step(w) end
    local zn
    for _, z in ipairs(S.zones) do if z.kind == "lane" then zn = z end end
    assert(zn and zn.speed == 700, "shoulder charge: not timed at 700 u/s from the start")
    for _ = 1, 20 do pos[1] = pos[1] + 984 / 60; step(w) end -- 25 m/s
    assert_lane(1200, 0, 2.2, 34, 2.5, "shoulder charge", 1.4)
    -- his drag on you: he has you, the lane is still drawn but no danger (no Counterspell after it),
    -- and stays none once the drag is over and you are thrown, for the rest of this charge
    local mods = viewer.get_modifiers
    viewer.get_modifiers = function() return { mod("citadel_ability_bull_charge/modifier_charge_drag_enemy") } end
    S.zones = {}
    step(w)
    viewer.get_modifiers = mods
    assert(#S.zones == 0 and #REC.tris > 0, "shoulder charge: still a danger once it has you")
    for _ = 1, 30 do -- past a scan or two, the drag gone
        pos[1] = pos[1] + 984 / 60
        S.zones = {}
        step(w)
        assert(#S.zones == 0, "shoulder charge: a danger again once the drag was over")
    end
    -- a new charge is a danger again
    local abrams2, st2, pos2 = actor(213, 1200, 0, 0, "citadel_ability_bull_charge", {})
    local w2 = world(spell, abrams2)
    st2.mods = { mod("modifier_citadel_bull_charging") }
    for _ = 1, 5 do pos2[1] = pos2[1] + 984 / 60; step(w2) end
    assert(#S.zones > 0, "shoulder charge: a new charge not a danger after the last one had you")
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

-- Dust Devil: line off modifier_mirage_tornado_aura on Mirage, Radius 4 m as the half-width,
-- AbilityCastRange 20 m at TornadoSpeed 945 u/s
entry("mirage_dust_devil", function(spell)
    local mirage, st, pos = actor(430, 1200, 0, 0, "mirage_tornado", { AbilityCastRange = 20 })
    local w = world(spell, mirage)
    st.mods = { mod("mirage_tornado/modifier_mirage_tornado_aura") } -- as it read in game
    for _ = 1, 20 do pos[1] = pos[1] + 945 / 60; step(w) end
    assert_lane(1200, 0, 4, 20, 2.5, "dust devil", 1.4)
end, function(spell)
    -- the lifted victim wears the aura's copy, and has no tornado of his own
    local victim, vst = actor(431, 1200, 0, 0, nil, {})
    local mirage = actor(432, 1200, 200, 0, "mirage_tornado", {})
    vst.mods = { mod("mirage_tornado/modifier_mirage_tornado_aura_apply") }
    run(world(spell, mirage, { victim }), 0.4)
    assert(count_groups(spell) == 0, "dust devil: a victim's lift taken for the tornado")
end)

-- Seismic Impact: arc off modifier_citadel_bull_leap_boosting_crash (m_CrashModifier,
-- citadel_ability_bull_leap:32581), gravity_scale 0 so the slam is straight down, ImpactRadius 9 m
-- (:32367). land_window 0.3: nothing is drawn until the slam is that close, so the dive runs on
-- until it is.
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
        if g and g.land and g.land.z < 20 and pos[3] < 0.25 * 1000 then break end
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
-- with min_speed 20, lane half-width SlashRadius 1.6 m (:272170), lunge DashSpeed 1100 u/s (:272055).
-- Its reach: AttackDashRange 3 m (:272077), SlashLength 13 m (:272180) from there and the stab's
-- round tip, 1.6 m: 17.6 m. At 13 m it hit from past the lane's end, 10 casts of 19.
local function lunge_positive(spell)
    -- The charge: his dash trail comes as he starts to charge, up to 1.45 s before he lets go. The
    -- lane is drawn along his aim from then with no hit time, and from 0.6 s in, when he can let go
    -- any moment, it is urgent. His own dash on the press, at lunge speed, doesn't end it: taken for
    -- the lunge it took the lane away 0.3 s in. It is still up 1.45 s in: it ran out at 1.2, and the
    -- replay's hit landed in the gap. His attack clip ends it: then the lunge's own lane, timed now;
    -- and after the lunge nothing comes back
    local apollo2, _, pos2 = actor(219, 4000, 0, 0, "ability_fencer_lunge", { SlashLength = 13, SlashRadius = 1.6, AttackDashRange = 3 })
    local w2 = world(spell, apollo2)
    step(w2)
    -- a clip with no name is no tell: this entry has no `charge_anim`, and nil matched nil
    X.track_animation(apollo2, { duration = 1 })
    local nameless = S.groups[spell.id .. ":mod" .. tostring(apollo2:get_handle())]
    assert(not (nameless and nameless.charge_at), "flawless advance: a nameless clip started its charge")
    X.track_particle({ name = "particles/abilities/fencer/fencer_lunge_dash.vpcf", entity = apollo2, index = 9219 })
    local function lane()
        for _, z in ipairs(S.zones) do if z.kind == "lane" then return z end end
    end
    local charged = S.now
    for i = 1, 87 do -- 1.45 s of charging
        if i > 15 and i <= 21 then pos2[1] = pos2[1] + 1100 / 60 end -- his dash on the press
        S.zones = {}
        step(w2)
        local z = lane()
        assert(i < 3 or z, "flawless advance: no lane " .. i .. " frames into the charge")
        assert(not z or not (z.speed or z.delay or z.at), "flawless advance: the charge given a hit time")
        assert(not z or (z.urgent == true) == (S.now >= charged + 0.6),
            ("flawless advance: urgent %s, %.2f s into the charge"):format(tostring(z and z.urgent), S.now - charged))
    end
    assert_lane(pos2[1], 0, 1.6, 17.6, 2.5, "flawless advance charge", 1.6)
    -- He lets go: the stab lands 0.1 s after his attack clip, all along the lane, so the lane stays
    -- on his aim, timed to that and open to Counterspell. The in-air clip that follows as the lunge
    -- lifts him is the same release, and on its own ends the charge too. Once the stab has landed
    -- nothing is left, though he still moves at lunge speed: timed by his speed, that lane had Evade
    -- dash from a stab already over
    local let_go = S.now
    X.track_animation(apollo2, { name = "ability_lunge_attack_n", duration = 1 })
    for _ = 1, 3 do pos2[1] = pos2[1] + 2200 / 60; S.zones = {}; step(w2) end
    X.track_animation(apollo2, { name = "ability_lunge_in_air_attack_n_down", duration = 1 })
    S.zones = {}
    step(w2)
    local zn = lane()
    assert(zn and zn.at and math.abs(zn.at - let_go - 0.1) < 1e-6 and not zn.speed and not zn.urgent,
        "flawless advance: let go, the stab not timed 0.1 s from his clip")
    assert(("ability_lunge_in_air_attack_n_down"):find(spell.release_anim), "flawless advance: his in-air clip ends no charge")
    for _ = 1, 8 do pos2[1] = pos2[1] + 2200 / 60; S.zones = {}; step(w2) end
    assert(not lane(), "flawless advance: a lane left after the stab had landed")
    for _ = 1, 12 do S.zones = {}; step(w2) end
    assert(#REC.tris == 0 and not lane(), "flawless advance: the charge's lane came back after the lunge")

    local apollo, st, pos = actor(215, 2000, 0, 0, "ability_fencer_lunge", { SlashLength = 13, SlashRadius = 1.6, AttackDashRange = 3 })
    local w = world(spell, apollo)
    st.mods = { mod("modifier_base_uirecast") }
    for _ = 1, 20 do pos[1] = pos[1] + 1100 / 60; step(w) end
    assert_lane(2000, 0, 1.6, 17.6, 2.5, "flawless advance", 1.6)
    -- the lunge is over and he stands in the 5 s recast window (RecastTime :272190), modifier still
    -- on: the lane clears within a velocity sample or two, not with the window
    for _ = 1, 9 do step(w) end
    assert(#REC.tris == 0, "flawless advance: the lane stayed drawn after the lunge stopped")

end

local function lunge_negative(spell)
    -- uirecast is also the recast window of Disengaging Sigil, and it covers the walk before the
    -- lunge: at walking speed (8.8 m/s, under the 20 m/s floor) nothing is drawn
    local victim, vst = actor(216, 2000, 200, 0, nil, {})
    vst.mods = { mod("modifier_base_uirecast") }
    local w = world(spell, actor(217, 2000, 0, 0, "ability_fencer_lunge", {}), { victim })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "flawless advance: the victim's modifier detected")

    local apollo, st, pos = actor(218, 2000, 0, 0, "ability_fencer_lunge", { SlashLength = 13, SlashRadius = 1.6, AttackDashRange = 3 })
    local w2 = world(spell, apollo)
    st.mods = { mod("modifier_base_uirecast") }
    for _ = 1, 40 do pos[1] = pos[1] - 8.8 * UPM / 60; step(w2) end
    assert(#REC.tris == 0, "flawless advance: a lane drawn while he walks in the recast window")

    -- the recast window opens with him standing still, facing you 5 m off (he threw his Sigil):
    -- no lane in any frame, the ones before the first velocity sample included, where a timed lane
    -- had Evade spend Counterspell
    local still, sst = actor(321, -200, -600, 0, "ability_fencer_lunge", { SlashLength = 13, SlashRadius = 1.6, AttackDashRange = 3 })
    local w3 = world(spell, still)
    step(w3)
    sst.mods = { mod("modifier_base_uirecast") }
    for _ = 1, 12 do
        S.zones = {}
        step(w3)
        assert(#S.zones == 0, "flawless advance: a lane as he stands in a recast window")
    end
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
    for _ = 1, 15 do step(w) end -- inside the 0.3 s cone_time
    assert_cone(2800, 6, 60, "exploding uppercut")
    -- back-to-back swings: the first swing's particle is still alive (and its event kept) when the
    -- second one starts 1 s later. The second swing gets its own 0.2-0.3 s window
    local bebop2 = actor(223, 3200, 0, 0, "citadel_ability_uppercut", { MeleeAttackLength = 6, MeleeHalfAngle = 60 })
    local w2 = world(spell, bebop2)
    local swing = "particles/abilities/bebop/bebop_uppercut_activate.vpcf"
    local function frame(idx_list)
        for _, i in ipairs(idx_list) do X.update_particle({ index = i, control_point = 0, position = Vector(3200, 0, 0) }) end
        step(w2)
    end
    X.track_particle({ name = swing, entity = bebop2, index = 81 })
    for _ = 1, 60 do frame({ 81 }) end
    X.track_particle({ name = swing, entity = bebop2, index = 82 })
    for _ = 1, 15 do frame({ 81, 82 }) end -- 0.25 s into the second swing
    assert(#REC.tris > 0, "exploding uppercut: a second swing 1 s after the first drew no fan")
    assert_cone(3200, 6, 60, "exploding uppercut, second swing")
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
    -- the slam sits PlaceDistanceInFrontOfCaster 6.2 m (:punkgoat_ult) in front of where he comes
    -- down, along his facing (+x here), not under him
    assert_marker(3600 + 6.2 * UPM, 4, 4, "bashdown")
    -- turned to face +y, the slam goes 6.2 m along +y instead
    local turned, tst, tpos = actor(224, 3600, 0, 600, "ability_punkgoat_ult", { AbilityCastRange = 4 })
    turned.get_angles = function() return { GetForward = function() return Vector(0, 1, 0) end } end
    local wt = world(spell, turned)
    tst.particles = { "particles/abilities/punkgoat/punkgoat_bashdown_bat.vpcf" }
    for _ = 1, 30 do
        tpos[3] = math.max(0, tpos[3] - 1000 / 60)
        step(wt)
    end
    local apex
    for _, t in ipairs(REC.tris) do
        if math.abs(t[1].x - 3600) < 0.5 * UPM and math.abs(t[1].y - 6.2 * UPM) < 0.5 * UPM then apex = t[1] end
    end
    assert(apex, "bashdown: the slam did not follow Billy's facing to +y")
    -- the bat particle with no entity, and his hero id doesn't read: he still owns it, as the one
    -- hero holding ability_punkgoat_ult
    local billy2 = actor(229, 3800, 0, 600, "ability_punkgoat_ult", { AbilityCastRange = 4 })
    local w2 = world(spell, billy2)
    billy2._hero_id = 0
    step(w2) -- the first scan lists who holds what
    X.track_particle({ name = "particles/abilities/punkgoat/punkgoat_bashdown_bat.vpcf", index = 61 })
    X.update_particle({ index = 61, control_point = 0, position = Vector(3800, 0, 600) })
    local g2
    for _ = 1, 3 do g2 = step(w2) or g2 end
    assert(g2 and g2.owner == billy2, "bashdown: an ownerless bat particle lost Billy when his hero id didn't read")
    -- an enemy Billy as the game shows him: every slot reads empty and his hero id doesn't read.
    -- The bat effect on him is his own cast, not an on-hit effect on a victim
    for _, id in ipairs({ 0, 72 }) do
        local est = { mods = {}, particles = { "particles/abilities/punkgoat/punkgoat_bashdown_bat.vpcf" } }
        local epos = { 4000, 0, 600 }
        local enemy = mkpawn(230 + id, epos, nil, est)
        local w3 = world(spell, enemy)
        enemy._hero_id = id
        local g3
        for _ = 1, 30 do
            epos[3] = math.max(0, epos[3] - 1000 / 60)
            g3 = step(w3) or g3
        end
        assert(g3 and g3.owner == enemy, "bashdown: an enemy Billy's own bat effect was dropped (hero id " .. id .. ")")
        assert_marker(4000 + 6.2 * UPM, 4, 4, "bashdown on an enemy Billy (hero id " .. id .. ")")
    end
end

local function bashdown_negative(spell)
    local victim, vst = actor(226, 3600, 0, 600, nil, {})
    local w = world(spell, actor(227, 3600, 200, 0, "ability_punkgoat_ult", {}), { victim })
    vst.particles = { "particles/abilities/punkgoat/punkgoat_bashdown_bat.vpcf" }
    run(w, 0.5)
    assert(count_groups(spell) == 0, "bashdown: the bat effect on a victim detected")
    -- a victim whose abilities read empty, like an enemy's, but whose hero id reads as Abrams (6)
    local est = { mods = {}, particles = { "particles/abilities/punkgoat/punkgoat_bashdown_bat.vpcf" } }
    local abrams = mkpawn(228, { 3600, 0, 600 }, nil, est)
    abrams._hero_id = 6
    local w2 = world(spell, actor(229, 3600, 200, 0, "ability_punkgoat_ult", {}), { abrams })
    run(w2, 0.5)
    assert(count_groups(spell) == 0, "bashdown: the bat effect on an Abrams whose abilities don't read detected")
    -- Billy's own bat effect next to a Lady Geist on-hit effect listed first: the hit effect is
    -- skipped, Bashdown is still found, and Geist's point doesn't join Bashdown's group
    local billy, st = actor(231, 3600, 0, 600, "ability_punkgoat_ult", { AbilityCastRange = 4 })
    local w3 = world(spell, billy)
    st.particles = {
        { name = "particles/abilities/ghost/ghost_blood_bomb_hit.vpcf",
          control_points = { { cp = 0, origin = Vector(3600, 0, 650) } } },
        { name = "particles/abilities/punkgoat/punkgoat_bashdown_bat.vpcf",
          control_points = { { cp = 0, origin = Vector(3600, 0, 600) } } },
    }
    local g3 = step(w3)
    assert(g3 and g3.owner == billy, "bashdown: lost when a Geist hit effect was listed first on Billy")
    for _, p in ipairs(g3.particles) do
        assert(not p.name:find("ghost", 1, true), "bashdown: a Geist hit effect joined Bashdown's group")
    end

    -- Timed by its fuse, 0.5 s from the bat effect, not by his fall (a 0.02 s guess while he stands,
    -- which had Evade give up at the cast). Its wave: an 8 m ring (WaveEndRadius) round the 4 m slam,
    -- at its edge wave_time 0.5 s after it. Then the slam: the bat effect, seen as a particle event
    -- on Billy, is destroyed. The slam's area goes within a scan, not for the 1 s its dead event is
    -- kept plus CLEAR_DELAY; the ring stays where it landed until the wave has passed
    local done, _, dpos = actor(325, 3600, 0, 600, "ability_punkgoat_ult", { AbilityCastRange = 4, WaveEndRadius = 8 })
    local w4 = world(spell, done)
    step(w4)
    X.track_particle({ name = "particles/abilities/punkgoat/punkgoat_bashdown_bat.vpcf", entity = done, index = 70 })
    X.update_particle({ index = 70, control_point = 0, position = Vector(3600, 0, 600) })
    local g4, slam, wave
    for i = 1, 28 do
        dpos[3] = math.max(0, dpos[3] - 1000 / 60)
        S.zones = {}
        g4 = step(w4) or g4
        slam, wave = nil, nil
        for _, z in ipairs(S.zones) do if z.grow then wave = z else slam = z end end
        assert(i < 6 or slam and math.abs(slam.at - (g4.first + 0.5)) < 1e-6, -- its first velocity sample takes 0.05 s
            "bashdown: the slam not timed to its fuse (frame " .. i .. ")")
    end
    assert(slam and wave, "bashdown: no slam area and wave ring from the bat effect's particle event")
    assert(math.abs(slam.r - 4 * UPM) < 1 and math.abs(wave.r - 8 * UPM) < 1, "bashdown: slam 4 m, wave 8 m")
    assert(math.abs(wave.at - slam.at - 0.5) < 1e-6 and wave.x == slam.x and wave.y == slam.y,
        "bashdown: the wave not at its edge 0.5 s after the slam, round the slam")
    X.destroy_particle({ index = 70 })
    for i = 1, 60 do
        S.zones = {}
        step(w4)
        for _, r in pairs(S.list) do if r.spell == spell then D.draw_entity(r, viewer) end end
        for _, z in ipairs(S.zones) do
            assert(i <= 16 or z.grow, "bashdown: its slam area still up " .. i .. " frames after the bat effect ended")
            assert(not z.grow or z.x == wave.x and z.y == wave.y, "bashdown: the wave ring moved after the slam")
        end
        assert(S.now > wave.at or #S.zones > 0, "bashdown: the wave ring gone before the wave was at its edge")
        assert(S.now < wave.at + 0.2 or #S.zones == 0, "bashdown: the wave ring still up after the wave passed")
    end
    -- cast again 1.6 s after the last one began, while its group is still kept (its event 1 s past
    -- the slam, the group CLEAR_DELAY more): the new cast runs its own fuse. On the old start it was
    -- past its fuse from the first frame and never drawn: 3 of 13 casts in game (2026-11-09), the
    -- ones under 2 s after the cast before
    for _ = 1, 6 do step(w4) end
    dpos[3] = 600
    X.track_particle({ name = "particles/abilities/punkgoat/punkgoat_bashdown_bat.vpcf", entity = done, index = 71 })
    X.update_particle({ index = 71, control_point = 0, position = Vector(3600, 0, 600) })
    local recast = S.now
    for _ = 1, 8 do dpos[3] = math.max(0, dpos[3] - 1000 / 60); S.zones = {}; step(w4) end
    slam = nil
    for _, z in ipairs(S.zones) do if not z.grow then slam = z end end
    assert(slam and math.abs(slam.at - (recast + 0.5)) < 1e-6,
        "bashdown: cast again inside the 2 s its last group is kept, not timed from its own start")
end

entry("billy_bashdown", bashdown_positive, bashdown_negative)

-- Rising Ram: line off the "charge" modifier (m_Charging, ability_punkgoat_goatflip:173105) at
-- ChargeSpeed 1200 u/s, ChargeRadius 2.54 m (:172700) half-width, 0.3 s of charge = 9 m
-- (:172588 AbilityDuration).
local function ram_positive(spell)
    local billy, st, pos = actor(228, 4000, 0, 0, "ability_punkgoat_goatflip", { ChargeRadius = 2.54 })
    local w = world(spell, billy)
    st.mods = { mod("ability_punkgoat_goatflip/charge") } -- as it reads in game
    for _ = 1, 20 do pos[1] = pos[1] + 1200 / 60; step(w) end -- 30.5 m/s, over min_speed 25
    assert_lane(4000, 0, 2.54, 9, 2.5, "rising ram", 1.7)

    -- the wind-up: his ram clip starts 0.33 s before he moves (AbilityCastDelay 0.35 s, which an
    -- enemy's client never shows). The lane is drawn along his aim from the clip, timed to the ram
    -- leaving 0.35 s in at ChargeSpeed; another clip starts nothing; then the ram's own lane, timed now
    local billy3, st3, pos3 = actor(233, 4000, 0, 0, "ability_punkgoat_goatflip", { ChargeRadius = 2.54 })
    local w3 = world(spell, billy3)
    step(w3)
    local function lane()
        for _, z in ipairs(S.zones) do if z.kind == "lane" then return z end end
    end
    X.track_animation(billy3, { name = "ability_goat_ram_end", duration = 0.67 })
    S.zones = {}
    step(w3)
    assert(not lane(), "rising ram: a lane from a clip that isn't his wind-up")
    X.track_animation(billy3, { name = "ability_goat_ram_intro", duration = 0.5 })
    local wound = S.now
    for _ = 1, 18 do -- 0.3 s of winding up, standing
        S.zones = {}
        step(w3)
        local z = lane()
        assert(not z or z.delay and math.abs(z.delay - (wound + 0.35 - S.now)) < 1e-6 and z.speed == 1200,
            "rising ram: the wind-up not timed to the ram leaving")
    end
    assert(lane(), "rising ram: no lane while he winds up")
    assert_lane(4000, 0, 2.54, 9, 2.5, "rising ram wind-up", 1.7)
    st3.mods = { mod("ability_punkgoat_goatflip/charge") }
    for _ = 1, 8 do pos3[1] = pos3[1] + 1200 / 60; S.zones = {}; step(w3) end
    local zr = lane()
    assert(zr and zr.speed and (zr.delay or 0) == 0, "rising ram: the ram's own lane not timed now")

    -- mid-ram the lane starts on him every frame, also the two in three between velocity samples
    local billy2, st2, pos2 = actor(232, 4000, 0, 0, "ability_punkgoat_goatflip", { ChargeRadius = 2.54 })
    local w2 = world(spell, billy2)
    st2.mods = { mod("ability_punkgoat_goatflip/charge") }
    for i = 1, 12 do
        pos2[1] = pos2[1] + 1200 / 60
        step(w2)
        if i > 6 then
            local back = math.huge
            for _, t in ipairs(REC.tris) do for k = 1, 3 do back = math.min(back, t[k].x) end end
            assert(math.abs(back - pos2[1]) < 1,
                ("rising ram: lane starts at %.0f, he is at %.0f (frame %d)"):format(back, pos2[1], i))
        end
    end
end

local function ram_negative(spell)
    -- "charge" is a substring of about 20 other modifiers: a pawn without the ability carrying one
    -- is an on-hit victim and must not fill the entry
    local victim, vst = actor(229, 4000, 0, 0, nil, {})
    vst.mods = { mod("modifier_melee_charge") }
    local w = world(spell, actor(230, 4000, 0, 0, "ability_punkgoat_goatflip", {}), { victim })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "rising ram: a victim's melee charge detected")

    -- and under the 25 m/s floor a walk with his charge modifier on him draws nothing
    local billy, st, pos = actor(231, 4000, 0, 0, "ability_punkgoat_goatflip", { ChargeRadius = 2.54 })
    local w2 = world(spell, billy)
    st.mods = { mod("ability_punkgoat_goatflip/charge") }
    for _ = 1, 40 do pos[1] = pos[1] - 8.8 * UPM / 60; step(w2) end
    assert(#REC.tris == 0, "rising ram: a lane drawn while he walks")

    -- nor in the first frames a "charge" modifier is on him standing still (a heavy melee's
    -- modifier_melee_charge), before any speed is measured
    local still, sst = actor(322, -200, -600, 0, "ability_punkgoat_goatflip", { ChargeRadius = 2.54 })
    local w3 = world(spell, still)
    step(w3)
    sst.mods = { mod("modifier_melee_charge") }
    for _ = 1, 12 do
        S.zones = {}
        step(w3)
        assert(#S.zones == 0, "rising ram: a lane as he stands with a melee charge on him")
    end
end

entry("billy_rising_ram", ram_positive, ram_negative)

-- Chain Gang: cast at you while its chain is on you ("ability_punkgoat_tether/tether") and
-- waiting_for_pull on Billy (m_WaitingToPullModifier, ability_punkgoat_tether:172415), timed to the
-- pull AbilityDuration 2.8 s (:171907) after his modifier is first seen. No area: once chained no
-- spot is out of the pull, and Evade walked out of the ring this used to draw and was pulled anyway
local function chain_positive(spell)
    local billy, st = actor(230, 4400, 0, 0, "ability_punkgoat_tether", { AbilityCastRange = 12 })
    local w = world(spell, billy)
    st.mods = { mod("ability_punkgoat_tether/waiting_for_pull") }
    local g = run(w, 0.2) -- its chain is still on its way to you
    assert(g, "chain gang: no group")
    S.zones = {}
    step(w)
    assert(#S.zones == 0, "chain gang: drawn before you are chained")
    local mods = viewer.get_modifiers
    viewer.get_modifiers = function() return { mod("ability_punkgoat_tether/tether") } end
    S.zones = {}
    step(w)
    local z = S.zones[1]
    assert(#S.zones == 1 and z.kind == "target" and math.abs(z.at - (g.first + 2.8)) < 1e-6,
        "chain gang: not cast at you, timed to the pull, while you are chained")
    -- the chain breaks (no line of sight): no longer cast at you; chained again, it is
    viewer.get_modifiers = mods
    S.zones = {}
    step(w)
    assert(#S.zones == 0, "chain gang: still cast at you after the chain broke")
    viewer.get_modifiers = function() return { mod("ability_punkgoat_tether/tether") } end
    step(w)
    viewer.get_modifiers = mods
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
    -- the lane's moving slice sits on the bomb itself, not on a timer from the lane's start
    for _ = 1, 3 do
        pos[1] = pos[1] + 2500 / 60
        step(w)
        local on = 0
        for _, L in ipairs(REC.lines) do
            if math.abs(L[1].x - pos[1]) < 1 and math.abs(L[2].x - pos[1]) < 1 then on = on + 1 end
        end
        assert(on >= 4, ("gloom bombs: no slice on the bomb at %.0f (%d edges)"):format(pos[1], on))
    end
end

local function gloom_negative(spell)
    -- the explosion is a separate particle on the same bomb: it must not start a second group
    local calico = actor(236, 5200, 0, 0, "ability_nano_clustergrenade", {})
    local blast = mkproj(237, 5600, 0, 0, "particles/abilities/nano/nano_cluster_grenade_explosion.vpcf")
    local w = world(spell, calico, { blast })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "gloom bombs: the explosion particle detected")

    -- the bomb flies past you and is gone: its lane goes with it, not kept for CLEAR_DELAY as a
    -- new shot from the lane's start that Evade dodges again
    local thrower = actor(323, -1000, -600, 0, "ability_nano_clustergrenade", {})
    local bomb, _, pos = mkproj(324, -800, -600, 0,
        "particles/abilities/nano/nano_cluster_grenade.vpcf", "citadel_ability_nano_clustergrenade")
    local w2 = world(spell, thrower, { bomb })
    for _ = 1, 18 do S.zones = {}; step(w2); pos[1] = pos[1] + 2500 / 60 end
    assert(#S.zones > 0, "gloom bombs: no lane while the bomb flies")
    bomb.valid = function() return false end
    table.remove(w2.all, 2)
    for _ = 1, 40 do
        S.zones = {}
        step(w2)
        for _, r in pairs(S.list) do if r.spell == spell then D.draw_entity(r, viewer) end end
        assert(#S.zones == 0, "gloom bombs: a lane left after the bomb was gone")
    end
end

entry("calico_gloom_bombs", gloom_positive, gloom_negative)

do -- its own block: the main chunk is at Lua's 200-local limit
-- the zones of one kind this frame
local function zones_of(kind)
    local out = {}
    for _, z in ipairs(S.zones) do if z.kind == kind then out[#out + 1] = z end end
    return out
end

-- Call Bell: line off the thrown bell (ability_doorman_bomb, m_particle doorman_bell_projectile,
-- m_flSpeed 1500, m_flTriggerRadius 30 u), with its Radius 5.5 m blast at the lane's end. He sets it
-- off by shooting it, so the blast is untimed: drawn while the bell flies, sits and until it blows
local function bell_positive(spell)
    local doorman = actor(325, 5200, 0, 60, "ability_doorman_bomb", {})
    local bell, _, pos = mkproj(326, 5400, 0, 60, "particles/abilities/doorman/doorman_bell_projectile.vpcf")
    local w = world(spell, doorman, { bell })
    for _ = 1, 20 do S.zones = {}; step(w); pos[1] = pos[1] + 1500 / 60 end
    assert_lane(5400, 60, 30 / UPM, 47, nil, "call bell")
    assert_marker(5400 + 47 * UPM, 60, 5.5, "call bell")
    local blast = zones_of("circle")
    assert(#blast == 1 and blast[1].at == nil and math.abs(blast[1].r - 5.5 * UPM) < 1e-6,
        "call bell: blast area not drawn untimed at its 5.5 m")
    -- it stops (stuck, or out of drag): its area stays on, untimed, until it blows
    for _ = 1, 60 do S.zones = {}; step(w) end
    blast = zones_of("circle")
    assert(#blast == 1 and blast[1].at == nil, "call bell: area gone or timed while the bell sits")
    -- and it sits on the bell itself, with no lane left: kept at the lane's end, the ring was past
    -- the bell in game
    assert(math.abs(blast[1].x - pos[1]) < 1 and #zones_of("lane") == 0, "call bell: a stuck bell's area not on the bell")
    -- Thrown at the floor 20 deg down: its body (m_flPhysicsRadius 12 u) stops it with its centre
    -- 12 u up, 35 u short of where its line meets the floor. Its area is there from the throw, and
    -- doesn't jump as it sticks
    local thrower = actor(344, 5200, 0, 60, "ability_doorman_bomb", {})
    local bell2, _, pos2 = mkproj(345, 5400, 0, 60, "particles/abilities/doorman/doorman_bell_projectile.vpcf")
    w = world(spell, thrower, { bell2 })
    local dx, dz = 1500 / 60 * math.cos(math.rad(20)), 1500 / 60 * math.sin(math.rad(20))
    for _ = 1, 4 do S.zones = {}; step(w); pos2[1], pos2[3] = pos2[1] + dx, pos2[3] - dz end
    local stick = 5400 + (60 - 12) / math.tan(math.rad(20))
    blast = zones_of("circle")
    assert(#blast == 1 and math.abs(blast[1].x - stick) < 1 and math.abs(blast[1].z - 12) < 1,
        ("call bell: in flight, area at x %.1f z %.1f, sticks at x %.1f z 12"):format(blast[1] and blast[1].x or -1,
            blast[1] and blast[1].z or -1, stick))
    pos2[1], pos2[3] = stick, 12
    for _ = 1, 20 do S.zones = {}; step(w) end
    blast = zones_of("circle")
    assert(#blast == 1 and math.abs(blast[1].x - stick) < 1e-6, "call bell: its area not on it once stuck")
end

local function bell_negative(spell)
    -- the bell has blown: its lane and area go with it
    local thrower = actor(335, 5200, 0, 60, "ability_doorman_bomb", {})
    local bell, _, pos = mkproj(336, 5400, 0, 60, "particles/abilities/doorman/doorman_bell_projectile.vpcf")
    local w = world(spell, thrower, { bell })
    for _ = 1, 20 do S.zones = {}; step(w); pos[1] = pos[1] + 1500 / 60 end
    assert(#S.zones > 0, "call bell: nothing drawn while the bell flies")
    bell.valid = function() return false end
    table.remove(w.all, 2)
    for _ = 1, 40 do
        S.zones = {}
        step(w)
        assert(#S.zones == 0, "call bell: area left after the bell blew")
    end

    -- the blast and the debuff on its victims are their own particles: no bell to draw
    local doorman = actor(327, 5200, 0, 0, "ability_doorman_bomb", {})
    local blast = mkproj(328, 5600, 0, 0, "particles/abilities/doorman/doorman_bell_explode.vpcf")
    local mini = mkproj(329, 5600, 0, 0, "particles/abilities/doorman/doorman_bell_explode_mini.vpcf")
    run(world(spell, doorman, { blast, mini }), 0.4)
    assert(count_groups(spell) == 0, "call bell: its blast particle detected")
end

entry("doorman_call_bell", bell_positive, bell_negative)

-- Luggage Cart: line off the rolled cart (ability_doorman_luggage_cart, m_particle
-- doorman_cart_projectile, m_flSpeed 1000, m_flTriggerRadius 68.4 u), AbilityCastRange 20 m
local function cart_positive(spell)
    local doorman = actor(330, 5200, 0, 15, "ability_doorman_luggage_cart", { AbilityCastRange = 20 })
    local cart, _, pos = mkproj(331, 5400, 0, 15, "particles/abilities/doorman/doorman_cart_projectile.vpcf")
    local w = world(spell, doorman, { cart })
    for _ = 1, 20 do S.zones = {}; step(w); pos[1] = pos[1] + 1000 / 60 end
    assert_lane(5400, 15, 68.4 / UPM, 20, nil, "luggage cart")
    local lane = zones_of("lane")
    assert(#lane == 1 and lane[1].speed == 1000, "luggage cart: lane not timed at its 1000 u/s")
end

local function cart_negative(spell)
    -- an ally's cart trail and the cast flash are not the cart
    local doorman = actor(332, 5200, 0, 0, "ability_doorman_luggage_cart", {})
    local ally = mkproj(333, 5400, 0, 0, "particles/abilities/doorman/doorman_cart_projectile_allied.vpcf")
    local cast = mkproj(334, 5400, 0, 0, "particles/abilities/doorman/doorman_cart_projectile_cast.vpcf")
    run(world(spell, doorman, { ally, cast }), 0.4)
    assert(count_groups(spell) == 0, "luggage cart: an ally's trail or the cast flash detected")
end

entry("doorman_luggage_cart", cart_positive, cart_negative)

-- Rend: cone off m_ChargeParticle (drifter_blood_blast), AbilityCastRange 16 m, TargetingConeAngle 50
local function rend_positive(spell)
    local drifter, st = actor(360, 6000, 0, 0, "drifter_blood_blast", { AbilityCastRange = 16, TargetingConeAngle = 50 })
    local w = world(spell, drifter)
    st.particles = { "particles/abilities/drifter/drifter_claw_channel.vpcf" }
    for _ = 1, 15 do step(w) end -- inside the 0.45 s cone_time
    assert_cone(6000, 16, 25, "rend")
end

local function rend_negative(spell)
    -- a pawn without Rend holding the claws, and the slashes once they've hit, are not the wind-up
    local victim, vst = actor(361, 6000, 0, 0, nil, {})
    local drifter, dst = actor(362, 6000, 300, 0, "drifter_blood_blast", {})
    vst.particles = { "particles/abilities/drifter/drifter_claw_channel.vpcf" }
    dst.particles = { "particles/abilities/drifter/drifter_claw.vpcf" }
    run(world(spell, drifter, { victim }), 0.5)
    assert(count_groups(spell) == 0, "rend: a victim's claws or the landed slashes detected")
end

entry("drifter_rend", rend_positive, rend_negative)

-- Stalker's Mark: line off the bullet (drifter_shadow_mark m_mapWeaponInfos.primary: m_flBulletSpeed
-- 3900, m_flBulletRadius 27 u), no cast range: weapon_info_base's 7000 u
local function mark_positive(spell)
    local drifter = actor(363, 6400, 0, 0, "drifter_shadow_mark", {})
    world(spell, drifter)
    X.track_bullet({ weapon_name = "drifter_shadow_mark", shooter = drifter,
        start_pos = Vector(6400, 0, 100), direction = Vector(1, 0, 0) })
    clear_rec()
    local g
    for _, r in pairs(S.list) do if r.spell == spell then g = r end end
    assert(g, "stalker's mark: the bullet made no shot group")
    D.draw_entity(g, viewer)
    assert_lane(6400, 0, 27 / UPM, 177.8, nil, "stalker's mark")
    local lane = zones_of("lane")
    assert(#lane == 1 and lane[1].speed == 3900, "stalker's mark: lane not timed at its 3900 u/s")

    -- Debug Mode lists what its shooter showed just before the shot: a tell to start the lane sooner
    local d2 = actor(367, 6400, 400, 0, "drifter_shadow_mark", {})
    world(spell, d2)
    X.track_modifier_add(mod("modifier_test_windup"), d2)
    X.track_particle({ name = "particles/abilities/drifter/drifter_test_windup.vpcf", entity = d2, index = 991 })
    local out, real_print = {}, print
    print = function(s) out[#out + 1] = tostring(s) end
    X.track_bullet({ weapon_name = "drifter_shadow_mark", shooter = d2,
        start_pos = Vector(6400, 400, 100), direction = Vector(1, 0, 0) })
    print = real_print
    local line = table.concat(out, "\n")
    assert(line:find("modifier modifier_test_windup -0.00 s", 1, true)
        and line:find("drifter_test_windup -0.00 s", 1, true),
        "stalker's mark: the probe missed what came before the shot:\n" .. line)
end

local function mark_negative(spell)
    -- the impact and the mark on its victim are not the bolt
    local drifter = actor(364, 6400, 0, 0, "drifter_shadow_mark", {})
    local hit = mkproj(365, 6600, 0, 0, "particles/abilities/drifter/drifter_stalkers_mark_impact.vpcf")
    local debuff = mkproj(366, 6600, 0, 0, "particles/abilities/drifter/drifter_stalkers_mark_debuff.vpcf")
    run(world(spell, drifter, { hit, debuff }), 0.4)
    assert(count_groups(spell) == 0, "stalker's mark: its impact or debuff detected")
end

entry("drifter_stalkers_mark", mark_positive, mark_negative)

-- Fire Scarabs: a line off the bullet (m_flBulletSpeed 3000, m_flBulletRadius 50 u), 2 s of flight
entry("mirage_fire_scarabs", function(spell)
    local mirage = actor(433, 6400, 0, 0, "mirage_fire_beetles", {})
    world(spell, mirage)
    X.track_bullet({ weapon_name = "mirage_fire_beetles", shooter = mirage,
        start_pos = Vector(6400, 0, 100), direction = Vector(1, 0, 0) })
    clear_rec()
    local g
    for _, r in pairs(S.list) do if r.spell == spell then g = r end end
    assert(g, "fire scarabs: the bullet made no shot group")
    D.draw_entity(g, viewer)
    assert_lane(6400, 0, 50 / UPM, 152.4, nil, "fire scarabs")
    local lane = zones_of("lane")
    assert(#lane == 1 and lane[1].speed == 3000, "fire scarabs: lane not timed at its 3000 u/s")
end, function(spell)
    -- the burn on its victim is not the scarab
    local mirage = actor(434, 6400, 0, 0, "mirage_fire_beetles", {})
    local debuff = mkproj(435, 6600, 0, 0, "particles/abilities/mirage/mirage_fire_beetles_debuff.vpcf")
    run(world(spell, mirage, { debuff }), 0.4)
    assert(count_groups(spell) == 0, "fire scarabs: its debuff detected")
end)

-- Kinetic Pulse: the wind-up lane from his stomp clip, timed to the wave leaving 0.42 s in at 1600 u/s,
-- then a line off the wave (citadel_ability_stomp m_particle dynamo_gravity_wave), StompRange 16 m,
-- StompWidth 5.5 m each side
local function pulse_positive(spell)
    local dynamo = actor(370, 6800, 0, 0, "citadel_ability_stomp", { StompRange = 16 })
    local w = world(spell, dynamo)
    step(w)
    X.track_animation(dynamo, { name = "ability_stomp_alt", duration = 1.23 })
    local wound = S.now
    local lane
    for _ = 1, 12 do -- 0.2 s of winding up
        S.zones = {}
        step(w)
        lane = zones_of("lane")[1]
    end
    assert(lane and math.abs(lane.delay - (wound + 0.34 - S.now)) < 1e-6 and lane.speed == 1600,
        "kinetic pulse: the wind-up not timed to the wave leaving")
    assert_lane(6800, 0, 5.5, 16, nil, "kinetic pulse wind-up", 1.7)

    local dynamo2 = actor(371, 7400, 0, 0, "citadel_ability_stomp", { StompRange = 16 })
    local wave, _, pos = mkproj(372, 7500, 0, 40, "particles/abilities/dynamo/dynamo_gravity_wave.vpcf")
    local w2 = world(spell, dynamo2, { wave })
    for _ = 1, 20 do S.zones = {}; step(w2); pos[1] = pos[1] + 1600 / 60 end
    assert_lane(7500, 40, 5.5, 16, nil, "kinetic pulse")
    local l = zones_of("lane")
    assert(#l == 1 and l[1].speed == 1600, "kinetic pulse: the wave's lane not timed at its 1600 u/s")
end

local function pulse_negative(spell)
    -- another clip of his starts nothing, and a toss's debuff on you is not the wave
    local dynamo = actor(373, 6800, 0, 0, "citadel_ability_stomp", {})
    local debuff = mkproj(374, 7000, 0, 0, "particles/modifiers/armor_suppressor.vpcf")
    local w = world(spell, dynamo, { debuff })
    X.track_animation(dynamo, { name = "ability_vacuum_alt_start", duration = 1 })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "kinetic pulse: drawn without his stomp clip or wave")
end

entry("dynamo_kinetic_pulse", pulse_positive, pulse_negative)

-- Power Slash: from her charge clip, a lane along her aim, SlashLength 22 m, SlashRadius 1.04 m each side,
-- untimed, urgent from 0.3 s in; her cast clip times it to the slash 0.05 s on; then nothing
entry("yamato_power_slash", function(spell)
    local yamato = actor(470, 6000, 0, 0, "citadel_ability_power_slash", { SlashLength = 22 })
    local w = world(spell, yamato)
    step(w)
    X.track_animation(yamato, { name = "ability_powerslash_charge", duration = 1.2 })
    local charged = S.now
    for i = 1, 60 do -- 1 s of charging
        S.zones = {}
        step(w)
        local z = zones_of("lane")[1]
        assert(i < 3 or z, "power slash: no lane " .. i .. " frames into the charge")
        assert(not z or not (z.speed or z.delay or z.at), "power slash: the charge given a hit time")
        assert(not z or (z.urgent == true) == (S.now >= charged + 0.3),
            ("power slash: urgent %s, %.2f s into the charge"):format(tostring(z and z.urgent), S.now - charged))
    end
    assert_lane(6000, 0, 1.04, 22, nil, "power slash charge", 1.7)
    local let_go = S.now
    X.track_animation(yamato, { name = "ability_powerslash_cast", duration = 0.67 })
    S.zones = {}
    step(w)
    local z = zones_of("lane")[1]
    assert(z and z.at and math.abs(z.at - let_go - 0.05) < 1e-6 and not z.urgent, "power slash: let go, not timed to the slash")
    for _ = 1, 30 do S.zones = {}; step(w) end
    assert(#zones_of("lane") == 0, "power slash: a lane left after the slash")
    -- the entry needs an area up at the end: another charge
    X.track_animation(yamato, { name = "ability_powerslash_charge", duration = 1.2 })
    for _ = 1, 5 do step(w) end
end, function(spell)
    -- her other clips start nothing
    local yamato = actor(471, 6000, 0, 0, "citadel_ability_power_slash", {})
    local w = world(spell, yamato)
    X.track_animation(yamato, { name = "ability_flying_strike", duration = 1 })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "power slash: drawn without her charge clip")
end)

-- Singularity: a 7 m ring (VacuumRadius) on him while m_VacuumAuraModifier is, untimed: it pulls in
-- whoever is inside for the whole channel
local function singularity_positive(spell)
    -- its cast clip starts the ring before the pull, timed to it 0.2 s in; past that it is untimed
    local dynamo2 = actor(378, 8400, 0, 0, "citadel_ability_self_vacuum", { VacuumRadius = 7 })
    local w2 = world(spell, dynamo2)
    step(w2)
    X.track_animation(dynamo2, { name = "ability_vacuum_alt_start", duration = 0.37 })
    local cast = S.now
    S.zones = {}
    step(w2)
    local ring = zones_of("circle")[1]
    assert(ring and ring.at and math.abs(ring.at - (cast + 0.2)) < 1e-6, "singularity: its cast clip drew no ring timed to the pull")
    for _ = 1, 20 do step(w2) end -- 0.35 s in: the clip's window is over
    S.zones = {}
    step(w2)
    assert(not zones_of("circle")[1] or not zones_of("circle")[1].at, "singularity: a hit time kept past the pull")

    -- then his modifier: the ring stays on him through the channel, untimed
    local dynamo, st = actor(375, 7800, 0, 0, "citadel_ability_self_vacuum", { VacuumRadius = 7 })
    local w = world(spell, dynamo)
    st.mods = { mod("citadel_ability_self_vacuum/modifier_vacuumaura") } -- as it reads in game
    for _ = 1, 60 do step(w) end -- 1 s into the channel: still drawn
    local r = aura_hits(7800, 0, 7)
    assert(r >= 40, "singularity: no 7 m ring on him (" .. r .. " points)")
    ring = zones_of("circle")[1]
    assert(ring and not ring.at, "singularity: the ring given a hit time, where it pulls all channel")

    -- lifted (modifier_vacuumaura_target on you): no area to dash out of, it already has you. You play
    -- another hero, as in game: the victim's name holds the caster's, and a hero that can't be told
    -- apart would be taken for a Dynamo casting it
    S.me._hero_id = 58
    local real = S.me.get_modifiers
    S.me.get_modifiers = function()
        return { mod("citadel_ability_self_vacuum/modifier_vacuumaura/modifier_vacuumaura_target") }
    end
    S.zones = {}
    step(w)
    S.me.get_modifiers, S.me._hero_id = real, nil
    assert(#zones_of("circle") == 0, "singularity: an area to dodge while it already holds you")
    S.zones = {}
    step(w) -- let go: the ring is a danger again
    assert(#zones_of("circle") == 1, "singularity: no area once it has let you go")
end

local function singularity_negative(spell)
    -- a victim wears modifier_vacuumaura_target: not a Dynamo casting it
    local victim, vst = actor(376, 7800, 0, 0, nil, {})
    local w = world(spell, actor(377, 7800, 300, 0, "citadel_ability_self_vacuum", {}), { victim })
    vst.mods = { mod("citadel_ability_self_vacuum/modifier_vacuumaura_target") }
    run(w, 0.4)
    assert(count_groups(spell) == 0, "singularity: a victim's pull detected as a cast")
end

entry("dynamo_singularity", singularity_positive, singularity_negative)

-- Burrow: nothing for his first 3 s under ground, then a Radius 5.5 m ring on Mo & Krill timed to
-- the end of his 5 s there, and on, untimed, while he spins
entry("krill_burrow", function(spell)
    local krill, st = actor(436, 7800, 0, 0, "ability_burrow", { Radius = 5.5 })
    local w = world(spell, krill)
    st.mods = { mod("ability_burrow/modifier_burrow") } -- as it read in game
    step(w)
    local t0 = S.now
    while S.now < t0 + 2.9 do
        S.zones = {}
        step(w)
        assert(#zones_of("circle") == 0, ("burrow: a ring %.2f s into his 5 s under ground"):format(S.now - t0))
    end
    while S.now < t0 + 4 do S.zones = {}; step(w) end
    local ring = zones_of("circle")[1]
    assert(ring and ring.at and math.abs(ring.at - (t0 + 5)) < 0.03, "burrow: no ring timed to when he comes up")
    assert(aura_hits(7800, 0, 5.5) >= 40, "burrow: no 5.5 m ring on him before he comes up")
    while S.now < t0 + 5 do step(w) end
    st.mods = { mod("ability_burrow/modifier_spin") }
    while S.now < t0 + 6 do S.zones = {}; step(w) end
    ring = zones_of("circle")[1]
    assert(ring and not ring.at, "burrow: no untimed ring on him as he spins")
end, function(spell)
    -- the spin's slow on its victim is not a Mo & Krill burrowing
    local victim, vst = actor(437, 7800, 0, 0, nil, {})
    vst.mods = { mod("ability_burrow/modifier_spin/modifier_slow") }
    run(world(spell, actor(440, 7800, 300, 0, "ability_burrow", {}), { victim }), 0.4)
    assert(count_groups(spell) == 0, "burrow: a victim's slow detected as a cast")
end)

-- Leech Therapy: lobbed as a bullet (1315 u/s, gravity 1.6); its Radius 6.5 m area where it lands,
-- timed to the landing
entry("nurse_leech_therapy", function(spell)
    local nurse = actor(444, 9000, 0, 0, "ability_nurse_leech_therapy", { Radius = 6.5 })
    local w = world(spell, nurse)
    step(w)
    local n = math.sqrt(1 + 0.04)
    X.track_bullet({ weapon_name = "ability_nurse_leech_therapy", shooter = nurse,
        start_pos = Vector(9000, 0, 100), direction = Vector(1 / n, 0, 0.2 / n) })
    S.zones = {}
    local g = step(w)
    assert(g and g.shot and g.land and g.land.z < 20, "leech therapy: its bullet drew no lob to the ground")
    local zn = zones_of("circle")[1]
    assert(zn and math.abs(zn.r - 6.5 * UPM) < 1 and zn.at and math.abs(zn.at - g.lands_at) < 0.05
        and math.abs(zn.x - g.land.x) < 1, "leech therapy: no 6.5 m area where it lands, timed to the landing")
end, function(spell)
    -- her gun's bullets aren't the jar
    local nurse = actor(445, 9000, 0, 0, "ability_nurse_leech_therapy", {})
    local w = world(spell, nurse)
    X.track_bullet({ weapon_name = "citadel_weapon_nurse_set", shooter = nurse, start_pos = Vector(9000, 0, 100), direction = Vector(1, 0, 0) })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "leech therapy: her gun's bullet taken for the jar")
end)

do -- Paige's, in a block of their own: the main chunk is at Lua's 200 locals

-- Bookwyrm: a line off the dragon (m_particle bookworm_dragonfire, m_flSpeed 500), Radius 4 m a side,
-- DragonTravelRange 20 m; the book she lobs first is a bullet and no lane
entry("paige_bookwyrm", function(spell)
    local paige = actor(446, 5200, 0, 15, "ability_bookworm_dragonfire", { DragonTravelRange = 20 })
    local dragon, _, pos = mkproj(447, 5400, 0, 15, "particles/abilities/bookworm/bookworm_dragonfire.vpcf")
    local w = world(spell, paige, { dragon })
    for _ = 1, 20 do S.zones = {}; step(w); pos[1] = pos[1] + 500 / 60 end
    assert_lane(5400, 15, 4, 20, nil, "bookwyrm")
    local lane = zones_of("lane")
    assert(#lane == 1 and lane[1].speed == 500, "bookwyrm: lane not timed at its 500 u/s")
    -- a dragon that comes out 3 m up and climbs: its lane stays level, on the floor under it
    local up, _, upos = mkproj(456, 5400, 600, 120, "particles/abilities/bookworm/bookworm_dragonfire.vpcf")
    local w2 = world(spell, paige, { up })
    for _ = 1, 20 do S.zones = {}; step(w2); upos[1], upos[3] = upos[1] + 500 / 60, upos[3] + 400 / 60 end
    lane = zones_of("lane")
    assert(#lane == 1 and math.abs(lane[1].z) < 5 and math.abs(lane[1].bz) < 5,
        ("bookwyrm: the lane of a climbing dragon not on the floor (z %.0f to %.0f)"):format(lane[1] and lane[1].z or -1, lane[1] and lane[1].bz or -1))
end, function(spell)
    local paige = actor(448, 5200, 0, 0, "ability_bookworm_dragonfire", {})
    local fire = mkproj(449, 5400, 0, 0, "particles/abilities/bookworm/bookworm_dragonfire_aura.vpcf")
    local w = world(spell, paige, { fire })
    X.track_bullet({ weapon_name = "ability_bookworm_dragonfire", shooter = paige,
        start_pos = Vector(5200, 0, 100), direction = Vector(1, 0, 0) })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "bookwyrm: the book's bullet or the burning ground taken for the dragon")
end)

-- Captivating Read: its tell's control point 0 marks a Radius 7.5 m area, up until DetonationDelay 1.25 s
entry("paige_captivating_read", function(spell)
    local paige = actor(450, 7000, 0, 0, "ability_bookworm_aoemagic", { Radius = 7.5 })
    local w = world(spell, paige)
    -- as in game: CP0 on her, CP1 the area, CP2 a fixed point 44 m off (the furthest, not the area)
    X.track_particle({ name = "particles/abilities/bookworm/bookworm_aoe.vpcf", entity = paige, index = 60 })
    X.update_particle({ index = 60, control_point = 0, position = Vector(7000, 0, 0) })
    X.update_particle({ index = 60, control_point = 1, position = Vector(7600, 0, 0) })
    X.update_particle({ index = 60, control_point = 2, position = Vector(7000, 1730, 0) })
    local g
    for _ = 1, 10 do S.zones = {}; g = step(w) or g end
    assert(g and g.warning and math.abs(g.warning.x - 7600) < 1 and math.abs(g.warning.y) < 1,
        "captivating read: not on its tell's CP1")
    assert_marker(7600, 0, 7.5, "captivating read")
    local zn = zones_of("circle")[1]
    assert(zn and zn.at and math.abs(zn.at - (g.first + 1.25)) < 0.05, "captivating read: not timed 1.25 s from its tell")
end, function(spell)
    local paige = actor(451, 7000, 0, 0, "ability_bookworm_aoemagic", {})
    local w = world(spell, paige)
    X.track_particle({ name = "particles/abilities/bookworm/bookworm_aoe_explode.vpcf", entity = paige, index = 61 })
    X.update_particle({ index = 61, control_point = 0, position = Vector(7200, 0, 0) })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "captivating read: its blast particle detected")
end)

-- Rallying Charge: a lane off each knight (m_particle bookworm_ultimate, m_flSpeed 2000), 0.85 m a side
entry("paige_rallying_charge", function(spell)
    local paige = actor(452, 5200, 0, 15, "ability_bookworm_knightcharge", {})
    local knight, _, pos = mkproj(453, 5400, 0, 15, "particles/abilities/bookworm/bookworm_ultimate.vpcf")
    local w = world(spell, paige, { knight })
    for _ = 1, 20 do S.zones = {}; step(w); pos[1] = pos[1] + 2000 / 60 end
    local lane = zones_of("lane")
    assert(#lane == 1 and lane[1].speed == 2000 and math.abs(lane[1].r - 0.85 * UPM) < 1,
        "rallying charge: no 0.85 m lane off a knight timed at its 2000 u/s")
    -- her wind-up clip draws the whole charge along her aim before a knight is out: 4.5 m a side
    local paige2 = actor(457, 5200, 800, 0, "ability_bookworm_knightcharge", {})
    local w2 = world(spell, paige2)
    step(w2)
    X.track_animation(paige2, { name = "ability_knights_charge", duration = 0.8 })
    S.zones = {}
    for _ = 1, 3 do step(w2) end
    lane = zones_of("lane")
    assert(#lane >= 1 and math.abs(lane[#lane].r - 4.5 * UPM) < 1,
        ("rallying charge: her wind-up drew no 4.5 m lane (%d lanes, %.1f m)"):format(#lane, lane[#lane] and lane[#lane].r / UPM or -1))
end, function(spell)
    local paige = actor(454, 5200, 0, 0, "ability_bookworm_knightcharge", {})
    local cast = mkproj(455, 5400, 0, 0, "particles/abilities/bookworm/bookworm_ultimate_cast.vpcf")
    run(world(spell, paige, { cast }), 0.4)
    assert(count_groups(spell) == 0, "rallying charge: her cast flash taken for a knight")
end)

end

do -- Paradox's, in a block of their own: the main chunk is at Lua's 200 locals

-- Pulse Grenade: lobbed as a bullet (1600 u/s, gravity 1.0); its Radius 5.5 m area where it lands,
-- timed to the landing
entry("paradox_pulse_grenade", function(spell)
    local paradox = actor(458, 9000, 0, 0, "citadel_ability_chrono_pulse_grenade", { Radius = 5.5 })
    local w = world(spell, paradox)
    step(w)
    local n = math.sqrt(1 + 0.04)
    X.track_bullet({ weapon_name = "citadel_ability_chrono_pulse_grenade", shooter = paradox,
        start_pos = Vector(9000, 0, 100), direction = Vector(1 / n, 0, 0.2 / n) })
    S.zones = {}
    local g = step(w)
    assert(g and g.shot and g.land and g.land.z < 20, "pulse grenade: its bullet drew no lob to the ground")
    local zn = zones_of("circle")[1]
    assert(zn and math.abs(zn.r - 5.5 * UPM) < 1 and zn.at and math.abs(zn.at - g.lands_at) < 0.05
        and math.abs(zn.x - g.land.x) < 1, "pulse grenade: no 5.5 m area where it lands, timed to the landing")
end, function(spell)
    -- her gun's bullets aren't the grenade
    local paradox = actor(459, 9000, 0, 0, "citadel_ability_chrono_pulse_grenade", {})
    local w = world(spell, paradox)
    X.track_bullet({ weapon_name = "citadel_weapon_chrono_set", shooter = paradox, start_pos = Vector(9000, 0, 100), direction = Vector(1, 0, 0) })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "pulse grenade: her gun's bullet taken for the grenade")
end)

-- Paradoxical Swap: a line off the bullet (m_flBulletSpeed 3500, m_flBulletRadius 32.4 u), AbilityCastRange 25 m
entry("paradox_swap", function(spell)
    local paradox = actor(460, 6400, 0, 0, "citadel_ability_chrono_swap", { AbilityCastRange = 25 })
    world(spell, paradox)
    X.track_bullet({ weapon_name = "citadel_ability_chrono_swap", shooter = paradox,
        start_pos = Vector(6400, 0, 100), direction = Vector(1, 0, 0) })
    clear_rec()
    local g
    for _, r in pairs(S.list) do if r.spell == spell then g = r end end
    assert(g, "paradoxical swap: the bullet made no shot group")
    D.draw_entity(g, viewer)
    assert_lane(6400, 0, 0.82, 25, nil, "paradoxical swap")
    local lane = zones_of("lane")
    assert(#lane == 1 and lane[1].speed == 3500, "paradoxical swap: lane not timed at its 3500 u/s")
end, function(spell)
    -- the grenade's bullet is not the swap
    local paradox = actor(461, 6400, 0, 0, "citadel_ability_chrono_swap", {})
    local w = world(spell, paradox)
    X.track_bullet({ weapon_name = "citadel_ability_chrono_pulse_grenade", shooter = paradox,
        start_pos = Vector(6400, 0, 100), direction = Vector(1, 0, 0) })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "paradoxical swap: the grenade's bullet taken for the swap")
end)

end

do -- Pocket's, in a block of their own: the main chunk is at Lua's 200 locals

-- Barrage: each missile a bullet (2300 u/s, gravity 0) straight at his crosshair; its Radius 4.5 m
-- burst where it hits, timed to the hit and counting down to it as it flies
entry("pocket_barrage", function(spell)
    local pocket = actor(462, 6400, 0, 0, "synth_barrage", { Radius = 4.5 })
    local w = world(spell, pocket)
    step(w)
    local n = math.sqrt(1 + 0.01)
    X.track_bullet({ weapon_name = "synth_barrage", shooter = pocket,
        start_pos = Vector(6400, 0, 100), direction = Vector(1 / n, 0, -0.1 / n) })
    local fired = S.now
    S.zones = {}
    local g = step(w)
    assert(g and g.shot and g.land and g.land.z < 20 and math.abs(g.land.x - 7400) < 20,
        "barrage: its missile's lane doesn't end on the ground 1000 u on")
    local zn = zones_of("circle")[1]
    local hit = fired - 0.04 + 1000 / 2300 -- BULLET_LAG: it was fired that long before it was seen
    assert(zn and math.abs(zn.r - 4.5 * UPM) < 1 and math.abs(zn.x - g.land.x) < 1 and zn.at
        and math.abs(zn.at - hit) < 0.02, "barrage: no 4.5 m burst where it hits, timed to the hit")
    run(w, 0.2)
    S.zones = {}
    step(w)
    zn = zones_of("circle")[1]
    assert(zn and math.abs(zn.at - hit) < 0.02, "barrage: the burst's time moved off the hit as it flew")
    -- the entry needs an area up at the end: a second missile
    X.track_bullet({ weapon_name = "synth_barrage", shooter = pocket,
        start_pos = Vector(6400, 0, 100), direction = Vector(1 / n, 0, -0.1 / n) })
    step(w)
end, function(spell)
    -- his gun's bullets aren't missiles
    local pocket = actor(463, 6400, 0, 0, "synth_barrage", {})
    local w = world(spell, pocket)
    X.track_bullet({ weapon_name = "citadel_weapon_synth_set", shooter = pocket,
        start_pos = Vector(6400, 0, 100), direction = Vector(1, 0, 0) })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "barrage: his gun's bullet taken for a missile")
end)

-- Affliction: his cast particle starts a 9 m ring on him, timed to the end of his 0.6 s cast delay,
-- a ring to walk or dash out of (not a big area), gone once it has hit
entry("pocket_affliction", function(spell)
    local pocket = actor(464, 9600, 0, 0, "synth_affliction", { Radius = 9 })
    local w = world(spell, pocket)
    step(w)
    X.track_particle({ name = "particles/abilities/pocket/pocket_affliction_cast.vpcf", entity = pocket, index = 1420 })
    local cast = S.now
    S.zones = {}
    step(w)
    local ring = zones_of("circle")[1]
    assert(ring and math.abs(ring.r - 9 * UPM) < 1 and math.abs(ring.x - 9600) < 1, "affliction: no 9 m ring on him")
    assert(ring.at and math.abs(ring.at - (cast + 0.6)) < 1e-6 and not ring.lingers and not ring.big,
        "affliction: the ring not timed to the end of the cast delay as a ring to dodge")
    run(w, 1)
    S.zones = {}
    step(w)
    assert(#zones_of("circle") == 0, "affliction: the ring still up after it hit")
    -- the entry needs an area up at the end: a second cast
    X.track_particle({ name = "particles/abilities/pocket/pocket_affliction_cast.vpcf", entity = pocket, index = 1421 })
    step(w)
end, function(spell)
    -- the area it leaves on its victims is not the cast
    local pocket = actor(465, 9600, 0, 0, "synth_affliction", {})
    local w = world(spell, pocket)
    X.track_particle({ name = "particles/abilities/pocket/pocket_affliction_aoe.vpcf", entity = pocket, index = 1422 })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "affliction: its area taken for the cast")
end)

end

do -- Seven's, in a block of their own: the main chunk is at Lua's 200 locals

-- Lightning Ball: a line off the ball (m_particle gigawatt_lightning_ball, m_flSpeed 1700), ShockRadius
-- 4.25 m each side, 216 m (MaxLifetime 5 s); stuck on a wall, its 4.25 m area on the ball
entry("seven_lightning_ball", function(spell)
    local seven = actor(490, 6400, 0, 0, "citadel_ability_lightning_ball", { ShockRadius = 4.25 })
    local ball, _, pos = mkproj(491, 6600, 0, 60, "particles/abilities/gigawatt/gigawatt_lightning_ball.vpcf")
    local w = world(spell, seven, { ball })
    for _ = 1, 20 do S.zones = {}; step(w); pos[1] = pos[1] + 1700 / 60 end
    assert_lane(6600, 60, 4.25, 216, nil, "lightning ball")
    local lane = zones_of("lane")
    assert(#lane == 1 and lane[1].speed == 1700 and lane[1].around, "lightning ball: lane not timed at its 1700 u/s")
    -- it zaps all around it as it goes: an untimed 4.25 m ring on the ball, besides the lane's timed end
    local ring
    for _, c in ipairs(zones_of("circle")) do if not c.at then ring = c end end
    assert(ring and math.abs(ring.r - 4.25 * UPM) < 1 and math.abs(ring.x - (pos[1] - 1700 / 60)) < 1,
        "lightning ball: no untimed ring on the flying ball")
    -- it sticks: that ring is its area, the only one, untimed (no parry timed to a hit that is on you)
    for _ = 1, 60 do S.zones = {}; step(w) end
    local area = zones_of("circle")
    assert(#area == 1 and not area[1].at and math.abs(area[1].r - 4.25 * UPM) < 1 and math.abs(area[1].x - pos[1]) < 1,
        "lightning ball: a stuck ball's 4.25 m area not on it, alone and untimed")

    -- his throw clip: the lane along his aim at once, its front 0.14 s * 1700 u/s behind him, so it is
    -- timed with the wait. It follows his aim until it leaves (a bot still turns to you as the clip starts),
    -- then stays put; the ball, once seen, takes over
    local seven2 = actor(499, 8000, 0, 0, "citadel_ability_lightning_ball", {})
    local w2 = world(spell, seven2)
    step(w2)
    seven2.m_angEyeAngles = { pitch = 30, yaw = 90 } -- looking down and away as the clip starts
    X.track_animation(seven2, { name = "ability_lightning_ball", duration = 0.73 })
    step(w2)
    seven2.m_angEyeAngles = { pitch = 20, yaw = 0 } -- turned to you before it leaves; level all the same
    for _ = 1, 9 do step(w2) end
    seven2.m_angEyeAngles = { pitch = 30, yaw = 90 } -- and away again once it has left: its lane stays
    S.zones = {}
    clear_rec()
    step(w2)
    lane = zones_of("lane")
    local behind = lane[1] and (lane[1].x - lane[1].px) / 1700
    assert(#lane == 1 and lane[1].speed == 1700 and behind and math.abs(behind - (0.14 - 11 / 60)) < 0.02,
        ("lightning ball: the throw not timed 0.14 s out (front %s s behind him)"):format(tostring(behind)))
    assert_lane(8000, 0, 4.25, 216, nil, "lightning ball thrown along his aim as it left")
    local ball2, _, pos2 = mkproj(500, 8300, 0, 36, "particles/abilities/gigawatt/gigawatt_lightning_ball.vpcf")
    table.insert(w2.all, ball2)
    for _ = 1, 30 do step(w2); pos2[1] = pos2[1] + 1700 / 60 end
    S.zones = {} -- both groups drawn, as the game does: step() draws only one
    for _, r in pairs(S.list) do if r.spell == spell then D.draw_entity(r, viewer) end end
    lane = zones_of("lane")
    assert(#lane == 1 and math.abs(lane[1].px - pos2[1]) < 60, "lightning ball: the thrown lane kept once the ball was seen")

    -- aimed up, the thrown lane climbs with his aim rather than lying level
    local seven3 = actor(501, 9000, 0, 0, "citadel_ability_lightning_ball", {})
    local w3 = world(spell, seven3)
    step(w3)
    seven3.m_angEyeAngles = { pitch = -30, yaw = 0 }
    X.track_animation(seven3, { name = "ability_lightning_ball", duration = 0.73 })
    step(w3)
    local up
    for _, r in pairs(S.list) do if r.thrower == seven3 then up = r end end
    local a, b = up and up.path[1], up and up.land
    assert(a and math.abs((b.z - a.z) / (b.x - a.x) - math.tan(math.rad(30))) < 0.01,
        "lightning ball: thrown up, its lane not along his 30 deg aim")
end, function(spell)
    -- its zap on a victim, the victim's screen and its blast are not the ball
    local seven = actor(492, 6400, 0, 0, "citadel_ability_lightning_ball", {})
    local zap = mkproj(493, 6600, 0, 0, "particles/abilities/gigawatt/gigawatt_lightning_ball_zap.vpcf")
    local screen = mkproj(494, 6600, 0, 0, "particles/abilities/gigawatt/gigawatt_lightning_ball_tgt_screen.vpcf")
    local blast = mkproj(495, 6600, 0, 0, "particles/abilities/gigawatt/gigawatt_lightning_ball_explode_upgraded.vpcf")
    local w = world(spell, seven, { zap, screen, blast })
    X.track_animation(seven, { name = "ability_lightning_ball_end", duration = 0.5 }) -- not his throw clip
    run(w, 0.4)
    assert(count_groups(spell) == 0, "lightning ball: its zap, screen, blast or another clip taken for the ball")
end)

-- Static Charge: cast at you from the moment the charge comes on you, timed ShockDelay 3.5 s on
entry("seven_static_charge", function(spell)
    local seven = actor(496, 3000, 0, 0, "citadel_ability_static_charge", { AbilityCastRange = 15 })
    local w = world(spell, seven)
    step(w)
    local charge = mod("citadel_ability_static_charge/modifier_citadel_staticcharge")
    local mods = viewer.get_modifiers
    viewer.get_modifiers = function() return { charge } end
    X.track_modifier_add(charge, viewer)
    local t0 = S.now
    S.zones = {}
    step(w)
    viewer.get_modifiers = mods
    local z = zones_of("target")[1]
    assert(z and math.abs(z.at - (t0 + 3.5)) < 1e-6, "static charge: not cast at you, timed 3.5 s on, once charged")
end, function(spell)
    -- his charge on another hero is not on you
    local victim = actor(497, 300, -100, 0, nil, {})
    local seven = actor(498, 300, 0, 0, "citadel_ability_static_charge", {})
    local w = world(spell, seven, { victim })
    step(w)
    X.track_modifier_add(mod("citadel_ability_static_charge/modifier_citadel_staticcharge"), victim)
    S.zones = {}
    run(w, 0.4)
    assert(#zones_of("target") == 0, "static charge: cast at you with his charge on someone else")
end)

-- Itani Lo Sahn's mark: cast at you from the moment "cursed" comes on you, its blast timed 1.5 s on
entry("apollo_ultimate_mark", function(spell)
    local apollo = actor(220, 2400, 0, 0, "ability_fencer_ultimate", {})
    local w = world(spell, apollo)
    step(w)
    X.track_modifier_add(mod("ability_fencer_ultimate/cursed"), viewer)
    local t0 = S.now
    S.zones = {}
    step(w)
    local z = zones_of("target")[1]
    assert(z and math.abs(z.at - (t0 + 1.5)) < 1e-6, "itani lo sahn mark: not cast at you, timed 1.5 s on, once marked")
    assert(z.danger == 4 and z.low_danger == 5, "itani lo sahn mark: not danger 4, 5 at low health")
end, function(spell)
    -- his mark on another hero is not on you
    local victim = actor(221, 300, -100, 0, nil, {})
    local w = world(spell, actor(222, 300, 0, 0, "ability_fencer_ultimate", {}), { victim })
    step(w)
    X.track_modifier_add(mod("ability_fencer_ultimate/cursed"), victim)
    S.zones = {}
    run(w, 0.4)
    assert(#zones_of("target") == 0, "itani lo sahn mark: cast at you with his mark on someone else")
end)

end

do -- Rem's, in a block of their own: the main chunk is at Lua's 200 locals

-- Pillow Toss: a lane off the thrown pillow (m_flSpeed 1300, m_flTriggerRadius 35 u); and before it is
-- seen, from his charge clip along his aim, timed to its leaving 0.3 s on and then as far along as it
-- has flown by now
entry("rem_pillow_toss", function(spell)
    local rem = actor(480, 9600, 0, 0, "ability_familiar_ability02", { Radius = 5 })
    local pillow, _, pos = mkproj(481, 9800, 0, 100, "particles/abilities/familiar/familiar_pillow_projectile.vpcf")
    local w = world(spell, rem, { pillow })
    for _ = 1, 12 do S.zones = {}; step(w); pos[1] = pos[1] + 1300 / 60 end
    local lane = zones_of("lane")
    assert(#lane == 1 and lane[1].speed == 1300 and math.abs(lane[1].r - 0.89 * UPM) < 1,
        "pillow toss: no 0.89 m lane off the pillow timed at its 1300 u/s")
    -- his charge clip, aimed at you (you stand at 0, -600; he aims along +x)
    local rem2 = actor(487, -1300, -600, 0, "ability_familiar_ability02", {})
    local w2 = world(spell, rem2)
    step(w2)
    X.track_animation(rem2, { name = "ability_hit_the_sack_charge", duration = 0.5 })
    local t0 = S.now
    local function his() -- the lane from him, not the first pillow's kept group
        for _, z in ipairs(zones_of("lane")) do if z.x < 0 then return z end end
    end
    for _ = 1, 3 do S.zones = {}; step(w2) end
    local z = his()
    assert(z and math.abs(z.r - 0.89 * UPM) < 1 and math.abs(z.delay - (t0 + 0.3 - S.now)) < 1e-6
        and math.abs(z.px + 1300) < 1, "pillow toss: his charge clip drew no lane on him, leaving 0.3 s on")
    -- 0.2 s past its leaving, not seen yet: that far along, no delay
    while S.now < t0 + 0.5 do S.zones = {}; step(w2) end
    z = his()
    local flown = (S.now - t0 - 0.3) * 1300
    assert(z and z.delay == 0 and math.abs(z.px - (-1300 + flown)) < 1,
        ("pillow toss: once let go, its lane not as far along as it has flown (%s, want %.0f)")
            :format(tostring(z and z.px), -1300 + flown))
    -- a guess along his aim puts no burst at its end (it put a 5 m one round you)
    for _, c in ipairs(zones_of("circle")) do
        assert(c.x > 5000, "pillow toss: a burst drawn at the end of his aim's guess") -- the first pillow's are past 9800
    end
    -- his pillow seen: the guess is over, the pillow's own lane alone, before the guess would have run out
    local rem3 = actor(489, -1300, -600, 0, "ability_familiar_ability02", {})
    local p3, _, pos3 = mkproj(488, -1250, -600, 60, "particles/abilities/familiar/familiar_pillow_projectile.vpcf")
    local w3 = world(spell, rem3, { p3 })
    step(w3)
    X.track_animation(rem3, { name = "ability_hit_the_sack_charge", duration = 0.5 })
    -- a few frames after its lane first shows: the guess ends on the next sample of its lane
    local t3, mine, at_pillow, seen = S.now, {}, false, 0
    while seen < 8 and S.now < t3 + 0.6 do
        step(w3)
        pos3[1] = pos3[1] + 1300 / 60
        S.zones = {} -- every group drawn, as the game does (step draws one of them)
        for _, g in pairs(S.list) do D.draw_entity(g, viewer) end
        mine = zones_of("lane")
        at_pillow = false
        for _, l in ipairs(mine) do at_pillow = at_pillow or math.abs(l.px - pos3[1]) < 40 end
        if at_pillow then seen = seen + 1 end
    end
    assert(at_pillow and #mine == 1, ("pillow toss: once the pillow is seen, %d lanes from him, not its own alone (%s)")
        :format(#mine, tostring(at_pillow)))
end, function(spell)
    -- his cast effect is not the pillow
    local rem = actor(482, 9600, 0, 0, "ability_familiar_ability02", {})
    local cast = mkproj(483, 9800, 0, 0, "particles/abilities/familiar/familiar_pillow_cast.vpcf")
    run(world(spell, rem, { cast }), 0.4)
    assert(count_groups(spell) == 0, "pillow toss: his cast effect taken for the pillow")
end)

-- Nap Time: cast at you from the moment his stare comes on you, timed 1.9 s on (his channel), and still
-- once the stare is off, up to the hit
entry("rem_nap_time", function(spell)
    local rem = actor(484, 3000, 0, 0, "ability_familiar_ability01", { Radius = 19 })
    local w = world(spell, rem)
    step(w)
    local stare = mod("ability_familiar_ability01/staring")
    local mods = viewer.get_modifiers
    viewer.get_modifiers = function() return { stare } end
    X.track_modifier_add(stare, viewer)
    local t0 = S.now
    S.zones = {}
    step(w)
    local z = zones_of("target")[1]
    assert(z and math.abs(z.at - (t0 + 1.9)) < 1e-6, "nap time: not cast at you, timed 1.9 s on, once stared at")
    viewer.get_modifiers = mods
    while S.now < t0 + 1.7 do step(w) end
    S.zones = {}
    step(w)
    z = zones_of("target")[1]
    assert(z and math.abs(z.at - (t0 + 1.9)) < 1e-6, "nap time: dropped before its hit")
end, function(spell)
    -- his stare on another hero, or Pillow Toss's channel on you: nothing
    local victim = actor(485, 300, -600, 0, nil, {})
    local rem = actor(486, 300, 0, 0, "ability_familiar_ability01", {})
    local w = world(spell, rem, { victim })
    step(w)
    X.track_modifier_add(mod("ability_familiar_ability01/staring"), victim)
    X.track_modifier_add(mod("ability_familiar_ability02/channeling"), viewer)
    S.zones = {}
    run(w, 0.4)
    assert(#zones_of("target") == 0, "nap time: cast at you with no stare on you")
end)

end

do -- Violet's, in a block of their own: the main chunk is at Lua's 200 locals

-- where a lane drawn from (x, y) to (bx, by) is across at `at_x`
local function lane_y_at(z, at_x) return z.y + (z.by - z.y) * (at_x - z.x) / (z.bx - z.x) end

-- Living Ink: a 0.76 m lane off the stroke at its 1380 u/s, on from where it is toward where she aims,
-- not along the way it has come; turned, the lane turns with her
entry("violet_living_ink", function(spell)
    local violet = actor(510, -2000, 0, 0, "ability_artist_homingbrush", { Radius = 2.5 })
    violet.m_angEyeAngles = { pitch = 0, yaw = 0 } -- along +x: her aim meets no wall 105 m out
    local ink, _, pos = mkproj(511, -1900, 300, 60, "particles/abilities/artist/artist_homingbrush_projectile.vpcf")
    local w = world(spell, violet, { ink })
    for _ = 1, 12 do S.zones = {}; step(w); pos[1] = pos[1] + 1380 / 60 end -- flying parallel to her aim
    local lane = zones_of("lane")
    assert(#lane == 1 and lane[1].speed == 1380 and math.abs(lane[1].r - 0.76 * UPM) < 1,
        "living ink: no 0.76 m lane off the stroke timed at its 1380 u/s")
    local z = lane[1]
    assert(math.abs(z.x - (pos[1] - 1380 / 60)) < 1 and math.abs(z.y - 300) < 1, "living ink: lane not from the stroke")
    local aim_end = -2000 + 105 * UPM
    assert(math.abs(lane_y_at(z, aim_end)) < 20,
        ("living ink: lane not toward her aim (%.0f u off it at its end)"):format(lane_y_at(z, aim_end)))
    -- she turns to +y: the lane swings round with her
    violet.m_angEyeAngles = { pitch = 0, yaw = 90 }
    S.zones = {}; step(w)
    z = zones_of("lane")[1]
    assert(z and z.by - z.y > math.abs(z.bx - z.x), "living ink: the lane did not turn with her aim")
end, function(spell)
    -- the stroke's head, trail and burst are not the stroke
    local violet = actor(512, -2000, 0, 0, "ability_artist_homingbrush", {})
    local head = mkproj(513, -1800, 0, 60, "particles/abilities/artist/artist_homingbrush_projectile_head.vpcf")
    local trail = mkproj(514, -1800, 0, 60, "particles/abilities/artist/artist_homingbrush_projectile_trail.vpcf")
    local burst = mkproj(515, -1800, 0, 60, "particles/abilities/artist/artist_homing_projectile_explode.vpcf")
    run(world(spell, violet, { head, trail, burst }), 0.4)
    assert(count_groups(spell) == 0, "living ink: its head, trail or burst taken for the stroke")
end)

-- Flow State: a 2 m lane along the floor off the rolling brush at 975 u/s, turned by her yaw alone: aimed
-- down at the floor in front of her, it still runs on ahead, level
entry("violet_flow_state", function(spell)
    local violet = actor(516, -2000, 0, 0, "ability_artist_rollingprojectile", {})
    violet.m_angEyeAngles = { pitch = 20, yaw = 0 } -- her aim meets the floor ~5 m out, behind the brush
    local brush, _, pos = mkproj(517, -1600, 200, 8, "particles/abilities/artist/artist_slide_brush.vpcf")
    local w = world(spell, violet, { brush })
    for _ = 1, 12 do S.zones = {}; step(w); pos[1] = pos[1] + 975 / 60 end
    local z = zones_of("lane")[1]
    assert(z and z.speed == 975 and math.abs(z.r - 2 * UPM) < 1, "flow state: no 2 m lane off the brush at 975 u/s")
    assert(z.bx > z.x + 1000 and z.by < z.y and math.abs(z.bz - z.z) < 1,
        ("flow state: lane not on ahead, level, toward her yaw (%.0f, %.0f, %.0f -> %.0f, %.0f, %.0f)")
            :format(z.x, z.y, z.z, z.bx, z.by, z.bz))
end, function(spell)
    -- the fan and helper particles are not the brush
    local violet = actor(518, -2000, 0, 0, "ability_artist_rollingprojectile", {})
    local fan = mkproj(519, -1800, 0, 8, "particles/abilities/artist/artist_slide_brush_fan.vpcf")
    local helper = mkproj(520, -1800, 0, 8, "particles/abilities/artist/artist_slide_brush_helper.vpcf")
    run(world(spell, violet, { fan, helper }), 0.4)
    assert(count_groups(spell) == 0, "flow state: its fan or helper taken for the brush")
end)

-- Still Life: from her channel, cast at you while her buildup is on you, timed 2.6 s on (the channel)
-- plus the stun's flight at 3500 u/s; held to the hit once the channel is over, the buildup or not.
-- Cancelled (her channel gone early), it is off
entry("violet_still_life", function(spell)
    -- she cancels 1 s in (or you walk out of range and it breaks), your buildup still fading: off once her
    -- channel has gone unseen for 1.5 scans
    local violet2, st2 = actor(524, 3000, 0, 0, "ability_artist_tether", {})
    local w2 = world(spell, violet2)
    st2.mods = { mod("ability_artist_tether/self") }
    local mods = viewer.get_modifiers
    viewer.get_modifiers = function() return { mod("ability_artist_tether/buildup") } end
    run(w2, 1)
    S.zones = {}
    step(w2)
    assert(#zones_of("target") == 1, "still life: not cast at you while she channels")
    st2.mods = {}
    run(w2, 0.4)
    for _ = 1, 60 do
        S.zones = {}
        step(w2)
        assert(#zones_of("target") == 0, "still life: still cast at you after she cancelled")
    end
    viewer.get_modifiers = mods

    local violet, st = actor(521, 3000, 0, 0, "ability_artist_tether", { AbilityCastRange = 25 })
    local w = world(spell, violet)
    st.mods = { mod("ability_artist_tether/self") }
    local g = run(w, 0.2)
    assert(g, "still life: no group from her channel")
    S.zones = {}
    step(w)
    assert(#zones_of("target") == 0, "still life: cast at you with no buildup on you")
    viewer.get_modifiers = function() return { mod("ability_artist_tether/buildup") } end
    local at = g.first + 2.6 + math.sqrt(3000 ^ 2 + 600 ^ 2) / 3500
    S.zones = {}
    step(w)
    local z = zones_of("target")[1]
    assert(z and math.abs(z.at - at) < 1e-6, "still life: not cast at you, timed 2.6 s on plus the stun's flight")
    -- the channel ends and she throws: her modifier and your buildup go, the stun still to land
    while S.now < g.first + 2.6 do step(w) end
    st.mods, viewer.get_modifiers = {}, mods
    while S.now < at - 0.1 do step(w) end
    S.zones = {}
    step(w)
    z = zones_of("target")[1]
    assert(z and math.abs(z.at - at) < 1e-6, "still life: dropped while its stun flew")
end, function(spell)
    -- her buildup on another hero, her channel without it on you, or the buildup with no channel: nothing
    local victim = actor(522, 300, -600, 0, nil, {})
    local violet, st = actor(523, 300, 0, 0, "ability_artist_tether", {})
    local w = world(spell, violet, { victim })
    st.mods = { mod("ability_artist_tether/self") }
    step(w)
    X.track_modifier_add(mod("ability_artist_tether/buildup"), victim)
    S.zones = {}
    run(w, 0.4)
    assert(#zones_of("target") == 0, "still life: cast at you with no buildup on you")
    local violet2 = actor(525, 300, 0, 0, "ability_artist_tether", {})
    local w2 = world(spell, violet2)
    local mods = viewer.get_modifiers
    viewer.get_modifiers = function() return { mod("ability_artist_tether/buildup") } end
    X.track_modifier_add(mod("ability_artist_tether/buildup"), viewer)
    S.zones = {}
    run(w2, 0.4)
    viewer.get_modifiers = mods
    assert(#zones_of("target") == 0, "still life: cast at you with no channel of hers")
end)

end

-- Combo: cast at you from the moment his hold comes on you, timed 0.2 s on (its first tick), so a
-- parry goes at once
entry("krill_combo", function(spell)
    local krill = actor(441, 3000, 0, 0, "ability_ult_combo", { AbilityCastRange = 4 })
    local w = world(spell, krill)
    step(w)
    local hold = mod("ability_ult_combo/modifier_ult_combo_target") -- as it read on you in game
    local mods = viewer.get_modifiers
    viewer.get_modifiers = function() return { hold } end
    X.track_modifier_add(hold, viewer)
    local t0 = S.now
    S.zones = {}
    step(w)
    viewer.get_modifiers = mods
    local z = zones_of("target")[1]
    assert(z and math.abs(z.at - (t0 + 0.2)) < 1e-6, "combo: not cast at you, timed 0.2 s on, once he holds you")
end, function(spell)
    -- his hold on another hero is not on you
    local victim = actor(442, 300, -100, 0, nil, {})
    local krill = actor(443, 300, 0, 0, "ability_ult_combo", {})
    local w = world(spell, krill, { victim })
    step(w)
    X.track_modifier_add(mod("ability_ult_combo/modifier_ult_combo_target"), victim)
    S.zones = {}
    run(w, 0.4)
    assert(#zones_of("target") == 0, "combo: cast at you with his hold on someone else")
end)

-- Sand Blast: a 14 m wave along his aim from his cast clip, timed 0.3 s on
entry("krill_sand_blast", function(spell)
    local krill = actor(438, 7800, 0, 0, "ability_throw_sand", { AbilityCastRange = 25 }) -- not read: 14 m by choice
    local w = world(spell, krill)
    step(w)
    X.track_animation(krill, { name = "ability_throw_sand", duration = 0.8 })
    local t0 = S.now
    S.zones = {}
    step(w)
    local z = zones_of("cone")[1]
    -- the wave's shape: 2.5 m a side at him, its sides 28 deg apart, so they meet 10 m behind him
    local back = 2.5 * UPM / math.tan(math.rad(14))
    assert(z and math.abs(z.at - (t0 + 0.3)) < 1e-6 and math.abs(z.r - (14 * UPM + back)) < 1
        and math.abs(z.half - math.rad(14)) < 1e-6 and math.abs(z.near - back) < 1
        and math.abs(math.sqrt((z.x - 7800) ^ 2 + z.y ^ 2) - back) < 1,
        "sand blast: no 14 m wave, 5 m wide at him and 28 deg, timed 0.3 s after his clip")
end, function(spell)
    local krill = actor(439, 7800, 0, 0, "ability_throw_sand", {})
    local w = world(spell, krill)
    step(w)
    X.track_animation(krill, { name = "ability_burrow_start", duration = 1 })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "sand blast: drawn without its clip")
end)

-- Jar of the Dead: an arc off the lobbed jar's tracer (ability_necro_hauntingskull
-- m_szBulletTravelTracerParticle), its skulls going for you inside TargetSearchRadius 7 m, 0.15 s
-- after it lands
local function jar_positive(spell)
    local graves = actor(380, 9000, 0, 0, "ability_necro_hauntingskull", { TargetSearchRadius = 7 })
    local jar, _, pos = mkproj(381, 9400, 0, 400, "particles/abilities/necro/necro_haunting_skull_container_projectile.vpcf")
    local w = world(spell, graves, { jar })
    local x, z, vz = 9400, 400, -400
    for i = 1, 60 do
        x, z, vz = x + 400 / 60, z + vz / 60, vz - 800 / 60
        pos[1], pos[3] = x, z
        S.zones = {}
        local g = step(w)
        if g and g.land and g.land.z < 20 then
            assert_marker(g.land.x, 4, 7, "jar of the dead")
            local zn = zones_of("circle")[1]
            assert(zn and math.abs(zn.at - (g.lands_at + 0.15)) < 1e-6, "jar of the dead: not timed to its skulls, 0.15 s past landing")
            return
        end
        assert(i < 60, "jar of the dead: no landing predicted")
    end
end

local function jar_negative(spell)
    -- the skulls it lets out are not the jar
    local graves = actor(382, 9000, 0, 0, "ability_necro_hauntingskull", {})
    local skull = mkproj(383, 9400, 0, 100, "particles/abilities/necro/necro_haunting_skull_projectile.vpcf")
    run(world(spell, graves, { skull }), 0.4)
    assert(count_groups(spell) == 0, "jar of the dead: a skull taken for the jar")
end

-- and as the game reports it, fired as a bullet: its tracer never reached the client, so its arc is
-- drawn from where it left at 1200 u/s under gravity. From 100 u up, 27 deg up: lands 1.51 s on, 41.1 m out
local function jar_bullet(spell)
    local graves = actor(386, 9000, 0, 0, "ability_necro_hauntingskull", { TargetSearchRadius = 7 })
    local w = world(spell, graves)
    step(w)
    local n = math.sqrt(1 + 0.25)
    X.track_bullet({ weapon_name = "ability_necro_hauntingskull", shooter = graves,
        start_pos = Vector(9000, 0, 100), direction = Vector(1 / n, 0, 0.5 / n) })
    S.zones = {}
    local g = step(w)
    assert(g and g.shot and g.land, "jar of the dead: its bullet drew no lob")
    assert(math.abs(g.land.x - (9000 + 1073.3 * 1.508)) < 20 and g.land.z < 20, "jar of the dead: not landing where the throw does")
    assert(math.abs(g.lands_at - (S.now - 1 / 60 + 1.508)) < 0.05, "jar of the dead: its landing not timed by the throw")
    local zn = zones_of("circle")[1]
    assert(zn and math.abs(zn.r - 7 * UPM) < 1 and math.abs(zn.at - (g.lands_at + 0.15)) < 1e-6,
        "jar of the dead: no 7 m area timed to its skulls")
end

local function jar_positive_all(spell)
    jar_bullet(spell)
    jar_positive(spell)
end

entry("graves_jar_of_the_dead", jar_positive_all, jar_negative)

-- Grasping Hands: drawn where its hands are, control point 0 of each ground particle (the others are
-- no place: one at the map's origin here, as the game's 58 points ran 54.6 m), neighbour to neighbour,
-- AuraRadius 0.75 m each side, untimed. Too few, or longer than a wall can be, and nothing is drawn
local WALL = "particles/abilities/necro/necro_wall.vpcf"
local function hand(i, x, y)
    X.track_particle({ name = WALL, index = 1000 + i })
    X.update_particle({ index = 1000 + i, control_point = 0, position = Vector(x, y, 10) })
    X.update_particle({ index = 1000 + i, control_point = 1, position = Vector(0, 0, 0) })
end
local function hands_world(h)
    local graves = actor(h, 9000, 0, 0, "ability_necro_zombiewall", {})
    local w = world(by_id["graves_grasping_hands"], graves)
    graves._hero_id = 76 -- she plays Graves (the id is on her first entry)
    step(w)
    return w
end
local function hands_positive(spell)
    local w = hands_world(384)
    hand(0, 9000 + 10 * UPM, 0)
    hand(1, 9000 + 11 * UPM, 0)
    for _ = 1, 20 do S.zones = {}; step(w) end
    assert(#zones_of("lane") == 0, "grasping hands: drawn from two spots, a guess")
    -- 16 hands 1 m apart from 10 m out, wavering up to 0.3 m off straight: one lane a pair, on them
    for i = 2, 15 do hand(i, 9000 + (10 + i) * UPM, 0.3 * UPM * math.sin(i)) end
    for _ = 1, 20 do S.zones = {}; step(w) end
    local lanes = zones_of("lane")
    assert(#lanes == 15, "grasping hands: " .. #lanes .. " pieces for 16 hands, want 15")
    for _, l in ipairs(lanes) do
        assert(math.abs(l.r - 0.75 * UPM) < 1e-6 and not l.at and not l.speed, "grasping hands: a piece not 0.75 m each side, untimed")
        for _, x in ipairs({ l.x, l.bx }) do
            assert(x >= 9000 + 10 * UPM - 1 and x <= 9000 + 25 * UPM + 1, "grasping hands: a piece off its hands (the junk point taken)")
        end
    end
    -- 2 m off its middle is clear of every piece
    local function on(x, y)
        for _, l in ipairs(lanes) do
            local ex, ey = l.bx - l.x, l.by - l.y
            local t = math.max(0, math.min(1, ((x - l.x) * ex + (y - l.y) * ey) / (ex * ex + ey * ey)))
            if (x - l.x - ex * t) ^ 2 + (y - l.y - ey * t) ^ 2 <= l.r ^ 2 then return true end
        end
        return false
    end
    assert(on(9000 + 17.5 * UPM, 0) and not on(9000 + 17.5 * UPM, 2 * UPM), "grasping hands: not drawn on its hands alone")
    -- its hands are up AbilityDuration 5 s from the first: their particles play on, the wall doesn't
    local w2 = hands_world(388)
    local t0 = S.now
    local function frame()
        for i = 0, 15 do X.update_particle({ index = 1200 + i, control_point = 0, position = Vector(9000 + (10 + i) * UPM, 0, 10) }) end
        S.zones = {}
        step(w2)
    end
    for i = 0, 15 do X.track_particle({ name = WALL, index = 1200 + i }) end
    while S.now - t0 < 4.9 do frame() end
    assert(#zones_of("lane") == 15, "grasping hands: gone before its 5 s were up")
    while S.now - t0 < 5.1 do frame() end
    assert(#zones_of("lane") == 0, "grasping hands: still drawn past its 5 s, its particles still playing")
    -- the entry needs an area up at the end: a fresh wall
    local w3 = hands_world(389)
    for i = 0, 15 do hand(40 + i, 9000 + (10 + i) * UPM, 0) end
    for _ = 1, 20 do S.zones = {}; step(w3) end
end

local function hands_negative(spell)
    -- her aim preview, the cast beam and the projectiles that lay it are not the wall
    local graves = actor(385, 9000, 0, 0, "ability_necro_zombiewall", {})
    local w = world(spell, graves)
    graves._hero_id = 76
    for i, name in ipairs({ "necro_wall_deploy", "necro_wall_beam", "necro_wall_projectile" }) do
        X.track_particle({ name = "particles/abilities/necro/" .. name .. ".vpcf", index = 1100 + i })
        X.update_particle({ index = 1100 + i, control_point = 0, position = Vector(9400, 0, 10) })
    end
    run(w, 0.4)
    assert(count_groups(spell) == 0, "grasping hands: its preview, beam or projectiles taken for the wall")
    -- spots longer than a wall can be (26 m): not one wall, not drawn
    local w2 = hands_world(387)
    for i = 0, 3 do hand(20 + i, 9000 + (10 + i * 10) * UPM, 0) end
    for _ = 1, 20 do S.zones = {}; step(w2) end
    assert(#zones_of("lane") == 0, "grasping hands: spots 30 m end to end drawn as one wall")
end

entry("graves_grasping_hands", hands_positive, hands_negative)

-- Charged Shot: a lane off its bullet (8000 u/s, m_flBulletRadius 24 u), nothing while he charges
local function charged_positive(spell)
    local talon = actor(390, 9600, 0, 0, "ability_charged_shot", {})
    local w = world(spell, talon)
    X.track_bullet({ weapon_name = "ability_charged_shot", shooter = talon, start_pos = Vector(9600, 0, 100), direction = Vector(1, 0, 0) })
    S.zones = {}
    step(w)
    local g
    for _, r in pairs(S.list) do if r.spell == spell and r.shot then g = r end end
    assert(g, "charged shot: the shot made no lane")
    clear_rec()
    D.draw_entity(g, viewer)
    assert_lane(9600, 0, 24 / UPM, 254, nil, "charged shot")
    local l = zones_of("lane")
    assert(#l >= 1 and l[#l].speed == 8000, "charged shot: its lane not timed at 8000 u/s")
end

local function charged_negative(spell)
    -- his charge draws nothing: only the shot does
    local talon = actor(391, 9600, 0, 0, "ability_charged_shot", {})
    local w = world(spell, talon)
    X.track_particle({ name = "particles/abilities/archer/archer_charged_shot_channel.vpcf", entity = talon, index = 1301 })
    run(w, 0.6)
    assert(count_groups(spell) == 0, "charged shot: drawn while he charges")
end

entry("talon_charged_shot", charged_positive, charged_negative)

-- Sleep Dagger: a lane off its bullet (3500 u/s, m_flBulletRadius 24.5 u), the same way
local function dagger_positive(spell)
    local haze = actor(392, 9600, 0, 0, "ability_sleep_dagger", {})
    local w = world(spell, haze)
    X.track_bullet({ weapon_name = "ability_sleep_dagger", shooter = haze, start_pos = Vector(9600, 0, 100), direction = Vector(1, 0, 0) })
    S.zones = {}
    step(w)
    local g
    for _, r in pairs(S.list) do if r.spell == spell and r.shot then g = r end end
    assert(g, "sleep dagger: the throw made no lane")
    clear_rec()
    D.draw_entity(g, viewer)
    assert_lane(9600, 0, 24.5 / UPM, 266.7, nil, "sleep dagger")
    local l = zones_of("lane")
    assert(#l >= 1 and l[#l].speed == 3500, "sleep dagger: its lane not timed at 3500 u/s")
end

local function dagger_negative(spell)
    -- her gun's bullets aren't the dagger
    local haze = actor(393, 9600, 0, 0, "ability_sleep_dagger", {})
    local w = world(spell, haze)
    X.track_bullet({ weapon_name = "citadel_weapon_haze_set", shooter = haze, start_pos = Vector(9600, 0, 100), direction = Vector(1, 0, 0) })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "sleep dagger: her gun's bullet taken for the dagger")
end

entry("haze_sleep_dagger", dagger_positive, dagger_negative)

-- Spirit Lasso: a lane off its bullet (3500 u/s, m_flBulletRadius 32 u), 20 m long
local function lasso_positive(spell)
    local holliday = actor(398, 9600, 0, 0, "ability_gravity_lasso", { AbilityCastRange = 20 })
    local w = world(spell, holliday)
    X.track_bullet({ weapon_name = "ability_gravity_lasso", shooter = holliday, start_pos = Vector(9600, 0, 100), direction = Vector(1, 0, 0) })
    S.zones = {}
    step(w)
    local g
    for _, r in pairs(S.list) do if r.spell == spell and r.shot then g = r end end
    assert(g, "spirit lasso: the throw made no lane")
    clear_rec()
    D.draw_entity(g, viewer)
    assert_lane(9600, 0, 32 / UPM, 20, nil, "spirit lasso")
    local l = zones_of("lane")
    assert(#l >= 1 and l[#l].speed == 3500, "spirit lasso: its lane not timed at 3500 u/s")
end

local function lasso_negative(spell)
    -- her gun's bullets aren't the lasso
    local holliday = actor(399, 9600, 0, 0, "ability_gravity_lasso", {})
    local w = world(spell, holliday)
    X.track_bullet({ weapon_name = "citadel_weapon_astro_set", shooter = holliday, start_pos = Vector(9600, 0, 100), direction = Vector(1, 0, 0) })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "spirit lasso: her gun's bullet taken for the lasso")
end

entry("holliday_spirit_lasso", lasso_positive, lasso_negative)

-- Concussive Combustion: his charge particle starts a 12 m ring on him, timed to the blast 3.25 s on,
-- that follows him as he walks and is gone once he has blown
local function combustion_positive(spell)
    local inf, _, pos = actor(404, 9600, 0, 0, "ability_fire_bomb", { Radius = 12 })
    local w = world(spell, inf)
    step(w)
    X.track_particle({ name = "particles/abilities/inferno/inferno_fire_bomb_charge.vpcf", entity = inf, index = 1410 })
    local cast = S.now
    for _ = 1, 60 do pos[1] = pos[1] + 300 / 60; step(w) end -- he walks 1 s
    S.zones = {}
    step(w)
    local ring = zones_of("circle")[1]
    assert(ring and math.abs(ring.r - 12 * UPM) < 1, "concussive combustion: no 12 m ring on him")
    assert(math.abs(ring.x - pos[1]) < 1, "concussive combustion: the ring didn't follow him")
    assert(ring.at and math.abs(ring.at - (cast + 3.25)) < 1e-6 and not ring.lingers and ring.big,
        "concussive combustion: the ring not timed to the blast as a big area")
    for _ = 1, 150 do step(w) end -- 3.5 s on: blown
    S.zones = {}
    step(w)
    assert(#zones_of("circle") == 0, "concussive combustion: the ring still up after the blast")
    -- the entry needs an area up at the end: a second cast
    X.track_particle({ name = "particles/abilities/inferno/inferno_fire_bomb_charge.vpcf", entity = inf, index = 1411 })
    step(w)
end

local function combustion_negative(spell)
    -- the blast itself is not a charge
    local inf = actor(405, 9600, 0, 0, "ability_fire_bomb", {})
    local w = world(spell, inf)
    X.track_particle({ name = "particles/abilities/inferno/inferno_fire_bomb_explode.vpcf", entity = inf, index = 1412 })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "concussive combustion: its blast taken for a charge")
end

entry("infernus_concussive_combustion", combustion_positive, combustion_negative)

do -- Ivy's, in a block of their own: the main chunk is at Lua's 200 locals

-- Entangling Thorns: lobbed as a bullet (1800 u/s, gravity 1.5); the 6 m field it leaves is up,
-- untimed, for 4 s past the landing, then gone
local function thorns_positive(spell)
    local ivy = actor(406, 9000, 0, 0, "citadel_ability_tengu_urn", { Radius = 6 })
    local w = world(spell, ivy)
    step(w)
    local n = math.sqrt(1 + 0.04)
    X.track_bullet({ weapon_name = "citadel_ability_tengu_urn", shooter = ivy,
        start_pos = Vector(9000, 0, 100), direction = Vector(1 / n, 0, 0.2 / n) })
    local g = step(w)
    assert(g and g.shot and g.land and g.land.z < 20, "entangling thorns: its bullet drew no lob to the ground")
    local landed = g.lands_at
    while S.now < landed + 3.5 do step(w) end -- lying there 3.5 s on
    S.zones = {}
    step(w)
    local zn = zones_of("circle")[1]
    assert(zn and math.abs(zn.r - 6 * UPM) < 1 and not zn.at, "entangling thorns: no untimed 6 m field 3.5 s after it landed")
    assert(math.abs(zn.x - g.land.x) < 1, "entangling thorns: the field not where it landed")
    while S.now < landed + 4 + U.CFG.CLEAR_DELAY + U.CFG.SCAN_EVERY + 0.05 do step(w) end -- dropped on the next scan
    S.zones = {}
    step(w)
    assert(#zones_of("circle") == 0, "entangling thorns: the field still up past its 4 s")
    -- the entry needs an area up at the end: a second throw
    X.track_bullet({ weapon_name = "citadel_ability_tengu_urn", shooter = ivy,
        start_pos = Vector(9000, 0, 100), direction = Vector(1 / n, 0, 0.2 / n) })
    step(w)
end

local function thorns_negative(spell)
    -- her gun's bullets aren't the urn
    local ivy = actor(407, 9000, 0, 0, "citadel_ability_tengu_urn", {})
    local w = world(spell, ivy)
    X.track_bullet({ weapon_name = "citadel_weapon_tengu_set", shooter = ivy, start_pos = Vector(9000, 0, 100), direction = Vector(1, 0, 0) })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "entangling thorns: her gun's bullet taken for the urn")
    -- but Debug Mode keeps it, by name, for what a big hit lists before it
    local kept = false
    for _, r in ipairs(S.recent or {}) do kept = kept or r.what == "bullet citadel_weapon_tengu_set" end
    assert(kept, "an enemy's unmatched bullet not kept for a big hit's log")
end

entry("ivy_entangling_thorns", thorns_positive, thorns_negative)

-- Frost Grenade: lobbed as a bullet (1600 u/s, gravity 1.0); a 6.5 m burst where it lands, timed to
-- it, or on the first hero its arc meets: you always, another hero with Unit Collision on
local function frost_positive(spell)
    local n = math.sqrt(1 + 0.04)
    local function throw(kelvin)
        X.track_bullet({ weapon_name = "ability_ice_grenade", shooter = kelvin,
            start_pos = Vector(9000, 0, 100), direction = Vector(1 / n, 0, 0.2 / n) })
    end
    local function burst(w)
        S.zones = {}
        step(w)
        return zones_of("circle")[1]
    end
    local you_pos = { 0, -600, 0 }
    local you = mkpawn(417, you_pos, nil, { mods = {}, particles = {} })
    local other_pos = { 0, 3000, 0 }
    local other = mkpawn(418, other_pos, nil, { mods = {}, particles = {} })
    local kelvin = actor(414, 9000, 0, 0, "ability_ice_grenade", { Radius = 6.5 })
    local w = world(spell, kelvin, { other })
    S.me = you
    step(w)
    throw(kelvin)
    local g = step(w)
    assert(g and g.shot and g.land and g.land.z < 20, "frost grenade: its bullet drew no lob to the ground")
    local zn = burst(w)
    assert(zn and math.abs(zn.r - 6.5 * UPM) < 1 and zn.at and math.abs(zn.at - g.lands_at) < 0.05
        and math.abs(zn.x - g.land.x) < 1, "frost grenade: no 6.5 m burst where it lands, timed to it")
    -- the hit time holds as it flies, not its whole flight again from each frame
    for _ = 1, 10 do step(w) end
    zn = burst(w)
    assert(zn and math.abs(zn.at - g.lands_at) < 1e-6, "frost grenade: its hit time moved as it flew")
    -- you stand under its arc, still to come: it bursts on you, as it reaches you
    local i = math.floor(#g.path * 0.7)
    local p = g.path[i]
    you_pos[1], you_pos[2], you_pos[3] = p.x, p.y, p.z - 40
    zn = burst(w)
    assert(zn and math.abs(zn.x - p.x) < 40 and zn.at < g.lands_at - 0.1
        and math.abs(zn.at - (g.first + (i - 1) * U.CFG.ARC_DT)) < 0.05, "frost grenade: no burst on you in its way")
    -- Debug Mode, as it blows: how far its drawn arc passed you, to size a hero's body round it (ARC_BODY)
    local blast_log
    local real_print = print
    print = function(s) if tostring(s):find("kelvin_ice_grenade_explode", 1, true) then blast_log = tostring(s) end end
    X.track_particle({ name = "particles/abilities/kelvin/kelvin_ice_grenade_explode.vpcf", index = 503 })
    X.update_particle({ index = 503, control_point = 0, position = Vector(p.x, p.y, p.z) })
    print = real_print
    assert(blast_log and blast_log:find("went off 0.0 m from you, its drawn arc passed 0.00 m from you, 1.0 m over your feet", 1, true),
        "frost grenade: its pass by you not measured: " .. tostring(blast_log))
    -- as measured in game (2026-11-11): its arc 0.67 m off your middle at 2.3 m up hits your shoulder;
    -- 0.63 m off at 2.45 m up it flies past your head
    you_pos[2], you_pos[3] = p.y + 0.67 * UPM, p.z - 2.3 * UPM
    zn = burst(w)
    assert(zn and math.abs(zn.x - p.x) < 60, "frost grenade: its arc past your shoulder not burst on you")
    you_pos[2], you_pos[3] = p.y + 0.63 * UPM, p.z - 2.45 * UPM
    zn = burst(w)
    assert(zn and math.abs(zn.x - g.land.x) < 1, "frost grenade: its arc past your head burst on you")
    -- a step off its arc: it flies on to the ground
    you_pos[2] = p.y + 3 * UPM
    zn = burst(w)
    assert(zn and math.abs(zn.x - g.land.x) < 1, "frost grenade: still bursting on you once off its arc")
    -- another hero in its way: only with Unit Collision on
    you_pos[1], you_pos[2], you_pos[3] = 0, -600, 0
    other_pos[1], other_pos[2], other_pos[3] = p.x, p.y, p.z - 40
    zn = burst(w)
    assert(zn and math.abs(zn.x - g.land.x) < 1, "frost grenade: Unit Collision off, cut on another hero")
    switch_off.sp_collide = nil
    zn = burst(w)
    switch_off.sp_collide = true
    assert(zn and math.abs(zn.x - p.x) < 40, "frost grenade: Unit Collision on, not cut on a hero in its way")
    other_pos[2] = 3000
    -- once it has burst it is no area: a parry that blocked it, ending, read it as still to come
    while S.now < g.lands_at + U.CFG.TAIL_GRACE + 0.05 do step(w) end
    assert(not burst(w), "frost grenade: its burst still an area after it went off")
    -- the entry needs an area up at the end: a second throw, once the first's group is dropped
    while S.now < g.lands_at + U.CFG.CLEAR_DELAY + U.CFG.SCAN_EVERY + 0.05 do step(w) end
    throw(kelvin)
    step(w)
end

local function frost_negative(spell)
    -- his gun's bullets aren't the grenade
    local kelvin = actor(415, 9000, 0, 0, "ability_ice_grenade", {})
    local w = world(spell, kelvin)
    X.track_bullet({ weapon_name = "citadel_weapon_kelvin_set", shooter = kelvin, start_pos = Vector(9000, 0, 100), direction = Vector(1, 0, 0) })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "frost grenade: his gun's bullet taken for the grenade")
end

entry("kelvin_frost_grenade", frost_positive, frost_negative)

-- (inline, no locals: the main chunk is at Lua's 200-local limit)
-- Ground Strike: a 10 m, 120 deg fan from his clip, where he comes down along his aim kept 60 deg down,
-- facing it, and staying there as he moves: from the ground 0.2 s after his legsmash clip; from 10 m up,
-- 0.2 s after the drop plus the 11.7 m dive at 50 m/s. Gone once it has hit, and not back as the
-- charge ends (it was drawn again 0.69 s after his clip)
entry("lash_ground_strike", function(spell)
    local lash, _, pos = actor(419, 9000, 0, 0, "citadel_ability_lash_down_strike", { Radius = 10 })
    local w = world(spell, lash)
    step(w)
    local up = 10 * UPM
    local dive = (up + 4) / math.sin(math.rad(60)) -- from just over his feet to the floor
    for _, c in ipairs({ { "ability_groundstrike_airdrop_start", up, 0.2 + dive / 1968.5, 9000 + dive / 2 },
                         { "ability_groundstrike_legsmash", 0, 0.2 + 4 / math.sin(math.rad(60)) / 1968.5, 9002.3 } }) do
        pos[1], pos[3] = 9000, c[2]
        X.track_animation(lash, { name = c[1], duration = 1 })
        local t0 = S.now
        pos[1] = 9300 -- he moves on: the fan stays where he lands
        S.zones = {}
        step(w)
        local z = zones_of("cone")[1]
        assert(z and math.abs(z.at - (t0 + c[3])) < 1e-6 and math.abs(z.r - 10 * UPM) < 1
            and math.abs(z.half - math.rad(60)) < 1e-6 and math.abs(z.yaw) < 1e-6 and math.abs(z.x - c[4]) < 1,
            "ground strike: no 10 m, 120 deg fan where he lands, timed " .. c[3] .. " s after " .. c[1])
        X.track_animation(lash, { name = "landing_impact", duration = 0.8 }) -- Debug Mode measures it
        while S.now < t0 + c[3] + 0.02 do step(w) end
        -- the last strike's fan is up at the end, for the entry runner
        while c[2] > 0 and S.now < t0 + 1 do
            S.zones = {}
            step(w)
            assert(#zones_of("cone") == 0, ("ground strike: a fan up %.2f s after his clip, past its hit"):format(S.now - t0))
        end
    end
end, function(spell)
    -- his other clips start nothing
    local lash = actor(420, 9000, 0, 0, "citadel_ability_lash_down_strike", {})
    local w = world(spell, lash)
    step(w)
    X.track_animation(lash, { name = "jump_ground", duration = 0.83 })
    X.track_animation(lash, { name = "ability_deathslam_lift", duration = 1.67 })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "ground strike: drawn without its clip")
end)

-- Death Slam: cast at you from the moment his lock-on mark comes on you, timed 2.1 s on (the grab came
-- 2.32 s on), and still once the mark is off, up to the hit: nothing refreshes its group meanwhile
entry("lash_death_slam", function(spell)
    local lash = actor(421, 3000, 0, 0, "citadel_ability_lash_ultimate", { AbilityCastRange = 20 })
    local w = world(spell, lash)
    step(w)
    local lockon = mod("citadel_ability_lash_ultimate/lockon") -- as it read on you in game
    local mods = viewer.get_modifiers
    viewer.get_modifiers = function() return { lockon } end
    X.track_modifier_add(lockon, viewer)
    local t0 = S.now
    S.zones = {}
    step(w)
    local z = zones_of("target")[1]
    assert(z and math.abs(z.at - (t0 + 2.1)) < 1e-6, "death slam: not cast at you, timed 2.1 s on, once locked on")
    viewer.get_modifiers = mods
    -- 1.9 s on, the mark off: still cast at you, timed as it was (in game it was dropped 0.6 s in)
    while S.now < t0 + 1.9 do step(w) end
    S.zones = {}
    step(w)
    z = zones_of("target")[1]
    assert(z and math.abs(z.at - (t0 + 2.1)) < 1e-6, "death slam: dropped before its hit")
end, function(spell)
    -- in his range and in front of him, but not locked on: nothing (his aim isn't the tell), nor his
    -- mark on another hero
    local victim = actor(422, 300, -600, 0, nil, {})
    local lash = actor(423, 300, 0, 0, "citadel_ability_lash_ultimate", {})
    local w = world(spell, lash, { victim })
    step(w)
    X.track_modifier_add(mod("citadel_ability_lash_ultimate/lockon"), victim)
    S.zones = {}
    run(w, 0.4)
    assert(#zones_of("target") == 0, "death slam: cast at you with no lock on you")
end)

-- Knockdown (an item): cast at you from the moment its mark comes on you, timed 2.0 s on, by the
-- nearest enemy, whether his items read or not
entry("item_knockdown", function(spell)
    local foe = actor(424, 3000, 0, 0, nil, {}) -- he shows no Knockdown
    local w = world(spell, foe)
    step(w)
    X.track_modifier_add(mod("upgrade_target_stun/modifier_citadel_delayed_stun"), viewer) -- as it read in game
    local t0 = S.now
    S.zones = {}
    step(w)
    local z = zones_of("target")[1]
    assert(z and math.abs(z.at - (t0 + 2.0)) < 1e-6, "knockdown: not cast at you, timed 2.0 s on, once marked")
end, function(spell)
    -- its mark on another hero: nothing
    local victim = actor(425, 300, -600, 0, nil, {})
    local foe = actor(426, 300, 0, 0, "upgrade_target_stun", {})
    local w = world(spell, foe, { victim })
    step(w)
    X.track_modifier_add(mod("upgrade_target_stun/modifier_citadel_delayed_stun"), victim)
    S.zones = {}
    run(w, 0.4)
    assert(#zones_of("target") == 0, "knockdown: cast at you with its mark on another hero")
end)

-- Silence Wave (an item): a 4 m lane off its projectile at 2200 u/s, cast by the nearest enemy
entry("item_silence_wave", function(spell)
    local foe = actor(427, -2000, 0, 0, nil, {}) -- he shows no Silence Wave
    local wave, _, pos = mkproj(428, -1600, 0, 40, "particles/upgrades/silence_wave_projectile.vpcf")
    local w = world(spell, foe, { wave })
    for _ = 1, 12 do S.zones = {}; step(w); pos[1] = pos[1] + 2200 / 60 end
    local z = zones_of("lane")[1]
    assert(z and z.speed == 2200 and math.abs(z.r - 4 * UPM) < 1, "silence wave: no 4 m lane off the wave at 2200 u/s")
    -- from close by the scan finds it too late: its lane comes with its caster's two item clips, in the
    -- same frame and the cast first, along his aim, whatever his abilities show
    local near = actor(436, -2000, 0, 0, "citadel_ability_other", {})
    near.m_angEyeAngles = { pitch = 0, yaw = 0 }
    local w2 = world(spell, near)
    step(w2)
    X.track_animation(near, { name = "cast_start", duration = 0.67 })
    X.track_animation(near, { name = "aim_item", duration = 1.67 })
    S.zones = {}
    step(w2)
    z = zones_of("lane")[1]
    assert(z and z.speed == 2200, "silence wave: no lane from its caster's item clips")
end, function(spell)
    -- an aim held, its click 0.4 s on (another item's): no wave
    local other = actor(437, -2000, 0, 0, nil, {})
    local w0 = world(spell, other)
    step(w0)
    X.track_animation(other, { name = "aim_item", duration = 1.67 })
    run(w0, 0.4)
    X.track_animation(other, { name = "cast_start", duration = 0.67 })
    run(w0, 0.2)
    assert(count_groups(spell) == 0, "silence wave: thrown by a held aim's click")
    -- a bot's Decay: both clips at once, as a wave's, but its preview just before them: no wave
    X.track_particle({ name = "particles/upgrades/rupture_projectile_preview.vpcf", index = 9001, entity = other })
    X.track_animation(other, { name = "cast_start", duration = 0.67 })
    X.track_animation(other, { name = "aim_item", duration = 1.67 })
    run(w0, 0.2)
    assert(count_groups(spell) == 0, "silence wave: thrown by clips that came with another item's preview")
    -- its rings and the wave's cone effect are not the projectile
    local rings = mkproj(430, -1800, 0, 40, "particles/upgrades/silence_wave_projectile_rings.vpcf")
    local cone = mkproj(431, -1800, 0, 40, "particles/upgrades/silence_wave.vpcf")
    run(world(spell, other, { rings, cone }), 0.4)
    assert(count_groups(spell) == 0, "silence wave: its rings or cone effect taken for the projectile")
end)

-- Slowing Hex and Spirit Sap (items): cast at you from their caster's clips when his aim began with their
-- preview, timed 0.05 s and the shot's flight; not from another item's preview
;(function() -- a function of its own: the main chunk is at Lua's 200 locals
for id, pv in pairs({ item_slowing_hex = "upgrade_containment_projectile_preview", item_spirit_sap = "spirit_sap_preview" }) do
    entry(id, function(spell)
        local foe = actor(450, 400, -600, 0, nil, {})
        foe.m_angEyeAngles = { pitch = 0, yaw = 180 }
        local w = world(spell, foe)
        step(w)
        X.track_particle({ name = "particles/upgrades/" .. pv .. ".vpcf", index = 9010, entity = foe })
        X.track_animation(foe, { name = "aim_item", duration = 1.67 })
        step(w); step(w)
        X.track_animation(foe, { name = "cast_start", duration = 0.67 })
        local t0 = S.now
        S.zones = {}
        step(w)
        local z = zones_of("target")[1]
        assert(z and math.abs(z.at - (t0 + 0.05 + 400 / spell.speed)) < 0.01, id .. ": not cast at you from its clips, timed by its flight")
    end, function(spell)
        local foe = actor(451, 400, -600, 0, nil, {})
        foe.m_angEyeAngles = { pitch = 0, yaw = 180 }
        local w = world(spell, foe)
        step(w)
        X.track_particle({ name = "particles/upgrades/knock_down_preview.vpcf", index = 9011, entity = foe })
        X.track_animation(foe, { name = "aim_item", duration = 1.67 })
        step(w); step(w)
        X.track_animation(foe, { name = "cast_start", duration = 0.67 })
        S.zones = {}
        run(w, 0.3)
        assert(#zones_of("target") == 0, id .. ": cast at you by another item's aim and click")
    end)
end
end)()

-- Decay (an item): its tracked shot is the tell, cast at you once it closes on you at 800 u/s, timed by
-- its own distance to you, whichever way its caster aims
entry("item_decay", function(spell)
    local foe = actor(432, 3000, -600, 0, nil, {})
    foe.m_angEyeAngles = { pitch = 0, yaw = 90 } -- aiming away from you
    local shot, _, pos = mkproj(433, 800, -600, 60, "particles/upgrades/rupture_projectile.vpcf")
    local w = world(spell, foe, { shot })
    for _ = 1, 12 do S.zones = {}; step(w); pos[1] = pos[1] - 800 / 60 end
    local z = zones_of("target")[1]
    local left = (pos[1] + 800 / 60) / 800 -- its distance as that step saw it
    assert(z and math.abs(z.at - (S.now + left)) < 0.01, "decay: not cast at you off its shot, timed by its distance")
    -- you run from it: it closes at 500 u/s, not its 800, and is still cast at you, timed by its 800 (early
    -- is safe)
    local shot2, _, pos2 = mkproj(438, 800, -600, 60, "particles/upgrades/rupture_projectile.vpcf")
    local w2 = world(spell, foe, { shot2 })
    for _ = 1, 40 do S.zones = {}; step(w2); pos2[1] = pos2[1] - 500 / 60 end -- past a scan or two
    z = zones_of("target")[1]
    assert(z and math.abs(z.at - (S.now + (pos2[1] + 500 / 60) / 800)) < 0.01, "decay: not cast at you, or mistimed, as you run from it")
    -- before the scan finds the shot: from its caster's item clip, 400 u off and aiming at you, timed by
    -- the flight from where he stood, whatever he holds
    local near = actor(439, 400, -600, 0, "citadel_ability_other", {})
    near.m_angEyeAngles = { pitch = 0, yaw = 180 }
    local w3 = world(spell, near)
    step(w3)
    -- he aims it (its preview on him, then his aim clip), and holds his aim: nothing yet
    X.track_particle({ name = "particles/upgrades/rupture_projectile_preview.vpcf", index = 9001, entity = near })
    X.track_animation(near, { name = "aim_item", duration = 1.67 })
    S.zones = {}
    run(w3, 0.4)
    assert(#zones_of("target") == 0, "decay: cast at you while he only aims it")
    assert(count_groups(by_id["item_silence_wave"]) == 0, "decay: its aim threw a Silence Wave")
    -- his click
    X.track_animation(near, { name = "cast_start", duration = 0.67 })
    local t0 = S.now
    S.zones = {}
    step(w3)
    z = zones_of("target")[1]
    assert(z and math.abs(z.at - (t0 + 400 / 800)) < 0.01, "decay: not cast at you from its caster's clip, timed by its flight")
    -- Knockdown's mark comes on you right after those clips: that cast was a Knockdown, and no Decay
    X.track_modifier_add(mod("upgrade_target_stun/modifier_citadel_delayed_stun"), viewer)
    S.zones = {}
    step(w3)
    assert(count_groups(spell) == 0, "decay: kept for a cast that put Knockdown's mark on you")
    X.track_particle({ name = "particles/upgrades/rupture_projectile_preview.vpcf", index = 9001, entity = near })
    X.track_animation(near, { name = "aim_item", duration = 1.67 }) -- and a Decay again, for the checks below
    step(w3); step(w3); step(w3)
    X.track_animation(near, { name = "cast_start", duration = 0.67 })
    S.zones = {}
    step(w3)
end, function(spell)
    -- his clips while he aims away from you: nothing
    local away = actor(440, 400, -600, 0, nil, {})
    away.m_angEyeAngles = { pitch = 0, yaw = 0 }
    local w0 = world(spell, away)
    step(w0)
    X.track_particle({ name = "particles/upgrades/rupture_projectile_preview.vpcf", index = 9001, entity = away })
    X.track_animation(away, { name = "aim_item", duration = 1.67 })
    X.track_animation(away, { name = "cast_start", duration = 0.67 })
    S.zones = {}
    run(w0, 0.4)
    assert(#zones_of("target") == 0, "decay: cast at you by a clip aimed away from you")
    -- an item cast with no aim before it (not an aimed item), by one aiming at you: nothing
    local self = actor(441, 400, -600, 0, nil, {})
    self.m_angEyeAngles = { pitch = 0, yaw = 180 }
    local w1 = world(spell, self)
    step(w1)
    X.track_animation(self, { name = "cast_start", duration = 0.67 })
    S.zones = {}
    run(w1, 0.4)
    assert(#zones_of("target") == 0, "decay: cast at you by a cast clip with no aim before it")
    -- both clips in the same frame, the cast first: an instant cast (Silence Wave), no Decay
    X.track_animation(self, { name = "cast_start", duration = 0.67 })
    X.track_animation(self, { name = "aim_item", duration = 1.67 })
    S.zones = {}
    run(w1, 0.4)
    assert(#zones_of("target") == 0, "decay: cast at you by an instant cast's clips")
    -- another item's aim (Knockdown's preview) and its click, by one aiming at you: no Decay
    X.track_particle({ name = "particles/upgrades/knock_down_preview.vpcf", index = 9002, entity = self })
    X.track_animation(self, { name = "aim_item", duration = 1.67 })
    step(w1); step(w1); step(w1)
    X.track_animation(self, { name = "cast_start", duration = 0.67 })
    S.zones = {}
    run(w1, 0.4)
    assert(#zones_of("target") == 0, "decay: cast at you by a Knockdown's aim and click")
    -- a Decay's preview from a cast 3 s ago, then an instant cast's clips (a Silence Wave): no Decay
    local late = actor(442, 400, -600, 0, nil, {})
    late.m_angEyeAngles = { pitch = 0, yaw = 180 }
    local w4 = world(spell, late)
    step(w4)
    X.track_particle({ name = "particles/upgrades/rupture_projectile_preview.vpcf", index = 9003, entity = late })
    run(w4, 3)
    X.track_animation(late, { name = "cast_start", duration = 0.67 })
    X.track_animation(late, { name = "aim_item", duration = 1.67 })
    S.zones = {}
    run(w4, 0.4)
    assert(#zones_of("target") == 0, "decay: cast at you by clips long after its preview")
    -- a shot flying past you, at someone else: nothing
    local foe = actor(434, 3000, -600, 0, nil, {})
    local shot, _, pos = mkproj(435, 800, -600, 60, "particles/upgrades/rupture_projectile.vpcf")
    local w = world(spell, foe, { shot })
    for _ = 1, 24 do S.zones = {}; step(w); pos[2] = pos[2] + 800 / 60 end
    assert(#zones_of("target") == 0, "decay: cast at you by a shot flying across you")
end)

end

-- Spirit Snare: an arc off the thrown trap, its Radius 6.5 m area left on it where it lies, untimed
local function snare_positive(spell)
    local talon = actor(392, 9600, 0, 0, "ability_immobilize_trap", { Radius = 6.5 })
    local trap, _, pos = mkproj(393, 9800, 0, 200, "particles/abilities/archer/archer_immobilize_trap_projectile.vpcf")
    local w = world(spell, talon, { trap })
    local x, z, vz = 9800, 200, 100
    for _ = 1, 150 do -- 2.5 s: it flies, lands and lies there
        if z > 0 then x, z, vz = x + 1600 / 60, math.max(0, z + vz / 60), vz - 800 / 60 end
        pos[1], pos[3] = x, z
        S.zones = {}
        step(w)
    end
    local zn = zones_of("circle")[1]
    assert(zn and math.abs(zn.r - 6.5 * UPM) < 1 and not zn.at, "spirit snare: no untimed 6.5 m area where it lies")
    assert(math.abs(zn.x - x) < 2 and math.abs(zn.y) < 2, "spirit snare: its area not on the trap")
end

local function snare_negative(spell)
    -- his aim preview is not the trap
    local talon = actor(394, 9600, 0, 0, "ability_immobilize_trap", {})
    local preview = mkproj(395, 9800, 0, 0, "particles/abilities/archer/archer_immobilize_trap_ground_preview.vpcf")
    run(world(spell, talon, { preview }), 0.4)
    assert(count_groups(spell) == 0, "spirit snare: his aim preview taken for the trap")
end

entry("talon_spirit_snare", snare_positive, snare_negative)

end

-- Leaping Slash: aura off modifier_citadel_shiv_dash (m_DashModifier, ability_nano_dash:87111),
-- SlashRadius 4 m (:86958) ringed around her while the dash runs.
local function slash_positive(spell)
    local calico, st, pos = actor(238, 5800, 0, 0, "ability_nano_dash", { AbilityCastRange = 9, SlashRadius = 4 })
    local w = world(spell, calico)
    st.mods = { mod("modifier_citadel_shiv_dash") }
    local g
    -- mid-dash at 2400 u/s: the ring follows her, not where she started
    for _ = 1, 5 do
        pos[1] = pos[1] + 2400 / 60
        g = step(w) or g
    end
    assert(g, "leaping slash: no group")
    local r = aura_hits(pos[1], 0, 4)
    assert(r >= 40, "leaping slash: no 4 m ring on her (" .. r .. " points)")
    -- the lane reaches you at DashSpeed from where she is now, with no wind-up left: the dash was
    -- first seen under way (by its modifier). It used to say "now", so the dodge never tried
    S.zones = {}
    step(w)
    local lane
    for _, z in ipairs(S.zones) do if z.kind == "lane" then lane = z end end
    assert(lane and lane.speed == 2400 and not lane.at and (lane.delay or 0) == 0 and math.abs(lane.px - pos[1]) < 1,
        "leaping slash: dash lane not timed by her speed")
    -- the rest of the dash as a lane riding on her: edges 4 m either side, from 4 m behind where she
    -- is now to 9 m of dash + the slash 1.5 m on + its 4 m past where she started (the first frame
    -- drawn, 40 u into the dash)
    clear_rec()
    step(w)
    local lo, hi = math.huge, -math.huge
    for _, L in ipairs(REC.lines) do
        for _, p in ipairs(L) do
            if math.abs(math.abs(p.y) / UPM - 4) < 0.02 then lo, hi = math.min(lo, p.x), math.max(hi, p.x) end
        end
    end
    assert(math.abs(lo - (pos[1] - 4 * UPM)) < 1 and math.abs(hi - (5840 + 14.5 * UPM)) < 1,
        ("leaping slash: lane %.0f..%.0f, want %.0f..%.0f"):format(lo, hi, pos[1] - 4 * UPM, 5840 + 14.5 * UPM))
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
    -- an enemy Calico whose abilities don't read: still the 7.5 m burst, not the 1.5 m default
    local est = { mods = {}, particles = {} }
    local enemy = mkpawn(244, { 6600, 0, 0 }, nil, est) -- every slot reads empty
    local w2 = world(spell, enemy)
    est.mods = { mod("base_channeling") }
    for _ = 1, 12 do step(w2) end
    local unread = aura_hits(6600, 0, 7.5)
    assert(unread >= 40, "return to shadows: no 7.5 m ring when her ability doesn't read (" .. unread .. " points)")
end

local function shadows_negative(spell)
    local victim, vst = actor(242, 6200, 0, 0, nil, {})
    local w = world(spell, actor(243, 6200, 0, 0, "ability_nano_shadow_pulse", {}), { victim })
    vst.mods = { mod("base_channeling") }
    run(w, 0.4)
    assert(count_groups(spell) == 0, "return to shadows: the victim's modifier detected")
end

entry("calico_return_to_shadows", shadows_positive, shadows_negative)

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
    -- PreExplosionDuration 1.4 s: gone just past the blast, though the tell lives on
    -- PostExplosionDuration 0.8 s more (:289569)
    for _ = 1, 76 do step(w) end -- 86 frames, 1.43 s in: still inside the grace
    assert(#REC.tris > 0, "radiant daggers: cut before the blast")
    for _ = 1, 12 do step(w) end -- 1.63 s in, the tell still alive
    assert(#REC.tris == 0 and #REC.lines == 0, "radiant daggers: still drawn after the blast")
    -- any ground tell: a CP0 floating above the floor draws on the floor under it, and the area
    -- goes with its particle, not 1.5 s later when its kept event and group expire
    local celeste2 = actor(248, 7600, 0, 0, "ability_unicorn_luminousstrike", { ExplosionRadius = 8 })
    local w2 = world(spell, celeste2)
    X.track_particle({ name = "particles/abilities/unicorn/unicorn_daggers_target.vpcf", entity = celeste2, index = 42 })
    X.update_particle({ index = 42, control_point = 0, position = Vector(7800, 0, 102) })
    for _ = 1, 10 do step(w2) end
    assert_marker(7800, 0, 8, "radiant daggers off a floating tell")
    X.destroy_particle({ index = 42 })
    for _ = 1, 2 do step(w2) end
    assert(#REC.tris == 0 and #REC.lines == 0, "radiant daggers: still drawn after its tell was destroyed")
    -- a sandbox bot of your own hero: the tell names no owner, you are listed first, and the cast
    -- still goes to the other Celeste, not to you (whose spells are never drawn)
    local bot = actor(249, 8400, 0, 0, "ability_unicorn_luminousstrike", { ExplosionRadius = 8 })
    local w3 = world(spell, bot)
    table.remove(w3.all)
    table.insert(w3.all, 1, viewer)
    viewer._hero_id = spell.hero_id
    X.track_particle({ name = "particles/abilities/unicorn/unicorn_daggers_target.vpcf", index = 43 })
    X.update_particle({ index = 43, control_point = 0, position = Vector(8600, 0, 0) })
    local g3
    for _ = 1, 10 do g3 = step(w3) or g3 end
    viewer._hero_id = nil
    assert(g3 and g3.owner == bot, "radiant daggers: an unowned tell went to you, not the other Celeste")
    assert_marker(8600, 0, 8, "radiant daggers with you on Celeste too")

    -- a bot casting again as soon as it can: each tell is on her, so both casts share her group,
    -- and the second must still draw, where it fell, while the first's dead tell is still kept
    local spam = actor(250, 9000, 0, 0, "ability_unicorn_luminousstrike", { ExplosionRadius = 8 })
    local w4 = world(spell, spam)
    local tell = "particles/abilities/unicorn/unicorn_daggers_target.vpcf"
    X.track_particle({ name = tell, entity = spam, index = 44 })
    X.update_particle({ index = 44, control_point = 0, position = Vector(9200, 0, 0) })
    for _ = 1, 132 do step(w4) end                     -- 2.2 s: the blast and its 0.8 s linger
    X.destroy_particle({ index = 44 })
    for _ = 1, 12 do step(w4) end                      -- 0.2 s later she casts again
    X.track_particle({ name = tell, entity = spam, index = 45 })
    X.update_particle({ index = 45, control_point = 0, position = Vector(9900, 0, 0) })
    for frame = 1, 30 do                               -- the next 0.5 s, all inside its 1.4 s fuse
        step(w4)
        -- step() draws one group per spell; the game draws them all, the first cast's spent one too
        clear_rec()
        for _, r in pairs(S.list) do if r.spell == spell then D.draw_entity(r, viewer) end end
        if frame > 15 then assert_marker(9900, 0, 8, "radiant daggers, second cast (frame " .. frame .. ")") end
    end

    -- and a second tell that gets the first one's particle index, as the game reuses them: its group
    -- starts anew, not on the first cast's clock with its 1.4 s fuse long over
    local again = actor(326, 11000, 0, 0, "ability_unicorn_luminousstrike", { ExplosionRadius = 8 })
    local w6 = world(spell, again)
    X.track_particle({ name = tell, entity = again, index = 47 })
    X.update_particle({ index = 47, control_point = 0, position = Vector(11200, 0, 0) })
    for _ = 1, 132 do step(w6) end
    X.destroy_particle({ index = 47 })
    for _ = 1, 12 do step(w6) end
    X.track_particle({ name = tell, entity = again, index = 47 })
    X.update_particle({ index = 47, control_point = 0, position = Vector(11900, 0, 0) })
    for frame = 1, 30 do
        step(w6)
        S.zones = {}
        for _, r in pairs(S.list) do if r.spell == spell then D.draw_entity(r, viewer) end end
        local hit = false
        for _, z in ipairs(S.zones) do hit = hit or z.kind == "circle" and math.abs(z.x - 11900) < 1 end
        assert(hit, "radiant daggers: a tell on a reused particle index gave no area (frame " .. frame .. ")")
    end

    -- As in game: the server lets go of the tell's particle index the moment it is made (released, not
    -- destroyed) and the effect plays on; and every cast's tell also shows on one entity that isn't
    -- her (the world), the older ones first. She throws again 2 s on (her charges), the last tell
    -- still up, then once more on the very same spot. Each cast draws alone, at its own spot, on its
    -- own 1.4 s fuse from its own particle. Taken for dead, the tell's own event never drew and the
    -- world's one group did: the first cast 0.26 s late, later ones on the first's start, past their
    -- fuse, so never (4 casts of 5 in game, 2026-11-09)
    local rapid = actor(253, 12400, 0, 0, "ability_unicorn_luminousstrike", { ExplosionRadius = 8 })
    local ground, gst = mkproj(254, 0, 0, 0, nil, "C_World")
    local w7 = world(spell, rapid, { ground })
    table.remove(w7.all, 2)
    table.insert(w7.all, 1, ground) -- the world comes before every hero in the entity list
    step(w7)
    local function cast(index, x)
        X.track_particle({ name = tell, index = index })
        X.update_particle({ index = index, control_point = 0, position = Vector(x, 0, 0), has_position = true })
        X.destroy_particle({ index = index, released = true })
        local made = S.now
        gst.particles[#gst.particles + 1] = { name = tell, control_points = { { cp = 0, origin = Vector(x, 0, 0) } } }
        local zones
        for _ = 1, 20 do -- past the 0.25 s scan that reads the world's own list
            step(w7)
            S.zones = {}
            for _, r in pairs(S.list) do if r.spell == spell then D.draw_entity(r, viewer) end end
            zones = S.zones
        end
        assert(#zones == 1, ("radiant daggers: %d areas for the cast at x %d, wanted its own alone"):format(#zones, x))
        assert(math.abs(zones[1].x - x) < 1, ("radiant daggers: the cast at x %d drawn at x %.0f"):format(x, zones[1].x))
        assert(math.abs(zones[1].at - (made + 1.4)) < 0.03,
            ("radiant daggers: the cast at x %d blows %.2f s after its particle, wanted 1.4"):format(x, zones[1].at - made))
    end
    cast(48, 12600)
    for _ = 1, 100 do step(w7) end
    cast(49, 13300)
    for _ = 1, 100 do step(w7) end
    cast(50, 13300)

    -- a stranger's particle that gets a live tell's released index neither moves nor ends the tell
    for _ = 1, 100 do step(w7) end
    X.track_particle({ name = tell, index = 51 })
    X.update_particle({ index = 51, control_point = 0, position = Vector(14000, 0, 0), has_position = true })
    X.destroy_particle({ index = 51, released = true })
    X.track_particle({ name = "particles/generic/stranger.vpcf", index = 51 })
    X.update_particle({ index = 51, control_point = 0, position = Vector(500, 0, 0), has_position = true })
    X.destroy_particle({ index = 51 })
    for _ = 1, 20 do
        step(w7)
        S.zones = {}
        for _, r in pairs(S.list) do if r.spell == spell then D.draw_entity(r, viewer) end end
    end
    assert(#S.zones == 1 and math.abs(S.zones[1].x - 14000) < 1,
        "radiant daggers: a stranger on the tell's reused particle index moved or ended it")

    -- nor does another tell that gets it, 0.5 s on: both draw, the first still on its own fuse
    for _ = 1, 100 do step(w7) end
    X.track_particle({ name = tell, index = 52 })
    X.update_particle({ index = 52, control_point = 0, position = Vector(15000, 0, 0), has_position = true })
    X.destroy_particle({ index = 52, released = true })
    local made = S.now
    for _ = 1, 30 do step(w7) end
    X.track_particle({ name = tell, index = 52 })
    X.update_particle({ index = 52, control_point = 0, position = Vector(16000, 0, 0), has_position = true })
    X.destroy_particle({ index = 52, released = true })
    for _ = 1, 40 do -- past the 0.5 s a dropped group is kept
        step(w7)
        S.zones = {}
        for _, r in pairs(S.list) do if r.spell == spell then D.draw_entity(r, viewer) end end
    end
    local first, second
    for _, z in ipairs(S.zones) do
        if math.abs(z.x - 15000) < 1 then first = z elseif math.abs(z.x - 16000) < 1 then second = z end
    end
    assert(first and second and #S.zones == 2, ("radiant daggers: a tell whose index another tell got: %d areas, wanted both"):format(#S.zones))
    assert(math.abs(first.at - (made + 1.4)) < 0.03, ("radiant daggers: that tell blows %.2f s after its particle, wanted 1.4"):format(first.at - made))
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
-- m_flBulletRadius 65 u (:288792) half-width; m_flBulletSpeed 2000 and weapon_info_base's 2 s
-- lifetime make its range 101.6 m (BounceRadius 15 m is the seek radius).
local function orb_positive(spell)
    local celeste = actor(248, 7400, 0, 0, "ability_unicorn_dazzlingorb", {})
    local orb, _, pos = mkproj(249, 7500, 0, 100, "particles/abilities/unicorn/unicorn_ball_projectile.vpcf")
    local w = world(spell, celeste, { orb })
    for _ = 1, 20 do step(w); pos[1] = pos[1] + 2000 / 60 end
    assert_lane(7500, 0, 65 / UPM, 101.6, nil, "shining wonder")
end

local function orb_negative(spell)
    local celeste = actor(250, 7400, 0, 0, "ability_unicorn_dazzlingorb", {})
    local charge = mkproj(251, 7400, 0, 40, "particles/abilities/unicorn/unicorn_ball_charge.vpcf")
    local w = world(spell, celeste, { charge })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "shining wonder: the charge particle detected")
end

entry("celeste_shining_wonder", orb_positive, orb_negative)

-- Chimera Mk1: arc off Danny himself while a jetpacking modifier is on (m_JetpackingModifier /
-- m_JetpackingVTOLModifier, ability_deadpack_rocketeer), gravity_scale 0, Radius 8 m. The dive is
-- angled along his aim, so the landing is ahead of him, not below.
local function chimera_positive(spell)
    local danny, st, pos = actor(270, 16000, 0, 800, "ability_deadpack_rocketeer", { Radius = 8 })
    local w = world(spell, danny)
    st.mods = { mod("jetpackingvtol") }
    -- the hover: steering forward at 480 u/s and down at 700 u/s, his fastest descent: nothing drawn
    for _ = 1, 20 do
        pos[1], pos[3] = pos[1] + 480 / 60, pos[3] - 700 / 60
        step(w)
        assert(#REC.tris == 0 and #S.zones == 0, "chimera mk1: drawn while he hovers")
    end
    -- then a 45 degree dive at 1500 u/s each way (2121 u/s), from 567 u up
    local x0, z0, g = pos[1], pos[3], nil
    for _ = 1, 80 do
        pos[1], pos[3] = pos[1] + 1500 / 60, pos[3] - 1500 / 60
        g = step(w) or g
        if g and g.land and #REC.tris > 0 then break end
    end
    assert(g and g.land, "chimera mk1: no landing predicted")
    -- 45 degrees down: he is followed BODY_Z 36 u above his feet, so it lands that much further on
    local lx = x0 + z0 + 36
    assert(math.abs(g.land.x - lx) < 30 and math.abs(g.land.y) < 2, "chimera mk1: dive not landing along his flight")
    assert(pos[3] > 1500 * 0.2, "chimera mk1: drawn only near impact, not as he dives")
    assert_marker(g.land.x, 4, 8, "chimera mk1")

    -- he steers the dive a quarter turn, to +y: the landing goes with him, within 0.15 s
    for _ = 1, 9 do
        pos[2], pos[3] = pos[2] + 1500 / 60, pos[3] - 1500 / 60
        g = step(w) or g
    end
    assert(math.abs(g.land.y - (pos[2] + pos[3] + 36)) < 60 and math.abs(g.land.x - pos[1]) < 60,
        "chimera mk1: landing not following a steered dive")

    -- he sets down on a roof mid-flight, climbs and then dives: the dive is still a danger. The
    -- touchdown that ends Seismic Impact's marker doesn't end a flight whose dive is told by speed
    local d2, st2, pos2 = actor(273, 17000, 0, 0, "ability_deadpack_rocketeer", { Radius = 8 })
    local w2 = world(spell, d2)
    HERO_LIB.is_on_ground = function(e) return e.get_origin().z <= 0 end
    st2.mods = { mod("jetpackingvtol") }
    for _ = 1, 30 do pos2[3] = pos2[3] + 20; step(w2) end               -- up to 600 u
    for _ = 1, 63 do pos2[3] = math.max(0, pos2[3] - 10); step(w2) end  -- down at 600 u/s, 3 frames on the roof
    for _ = 1, 30 do pos2[3] = pos2[3] + 20; step(w2) end               -- up again
    local dived = 0
    for _ = 1, 20 do
        pos2[1], pos2[3] = pos2[1] + 1500 / 60, pos2[3] - 1500 / 60
        S.zones = {}
        step(w2)
        if #S.zones > 0 then dived = dived + 1 end
    end
    HERO_LIB.is_on_ground = nil
    assert(dived > 10 and #S.zones > 0,
        "chimera mk1: no area for a dive after he had touched down mid-flight (" .. dived .. " of 20 frames)")
end

local function chimera_negative(spell)
    local danny, st = actor(271, 18000, 0, 800, "ability_deadpack_rocketeer", { Radius = 8 })
    local victim, vst = actor(272, 18000, 300, 800, nil, {})
    local w = world(spell, danny, { victim })
    st.mods = { mod("citadel_modifier_deadpack_jetpacklockout") } -- the overheat lockout, after the flight
    vst.mods = { mod("jetpacking") }                              -- someone without the ability
    run(w, 0.5)
    assert(count_groups(spell) == 0, "chimera mk1: the lockout or a non-Danny's modifier detected")
end

entry("danny_chimera_mk1", chimera_positive, chimera_negative)

do -- (a block of its own: the main chunk is at Lua's 200-locals limit)
-- targeted spells: the target zone on you, only when it is aimed at you
local function target_zone()
    local zn
    for _, z in ipairs(S.zones) do if z.kind == "target" then zn = z end end
    return zn
end

-- Soul Exchange: her caster tell, you 200 u (5.1 m) in front of her, inside AbilityCastRange 5.5 m
-- and her 90 deg cone: it hits after the 0.1 s cast delay
local CASTER_TELL = "particles/abilities/ghost/ghost_blood_exchange_caster.vpcf"
local function soul_exchange_positive(spell)
    local geist, st = actor(281, -200, -600, 0, "ability_health_swap", { AbilityCastRange = 5.5 })
    local w = world(spell, geist)
    st.particles = { CASTER_TELL }
    step(w)
    local zn = target_zone()
    assert(zn, "soul exchange: no target zone on you")
    assert(math.abs(zn.at - (1 / 60 + 0.1)) < 0.02, "soul exchange: hit time " .. zn.at)
    -- as in game: no caster tell at all, she is behind you, only her screen tell on your client. It
    -- starts the spell by itself, on the hero playing her, 0.1 s from the tell
    geist = actor(282, 200, -600, 0, "ability_health_swap", { AbilityCastRange = 5.5 })
    w = world(spell, geist)
    step(w) -- a scan, so the heroes are listed
    X.track_particle({ name = "particles/abilities/ghost/ghost_blood_exchange_tgt_screen.vpcf", index = 9281 })
    local told = S.now
    S.zones = {}
    step(w)
    zn = target_zone()
    assert(zn and math.abs(zn.at - (told + 0.1)) < 1e-6, "soul exchange: her screen tell alone drew nothing")
    S.targeted = {}
end

-- behind her (she faces +x, you are at -x) or out of her range: it is someone else's
local function soul_exchange_negative(spell)
    local geist, st = actor(283, 200, -600, 0, "ability_health_swap", { AbilityCastRange = 5.5 })
    local w = world(spell, geist)
    st.particles = { CASTER_TELL }
    S.zones = {}
    run(w, 0.3)
    assert(not target_zone(), "soul exchange: aimed at you from behind her")
    geist, st = actor(284, -400, -600, 0, "ability_health_swap", { AbilityCastRange = 5.5 })
    w = world(spell, geist)
    st.particles = { CASTER_TELL }
    run(w, 0.3)
    assert(not target_zone(), "soul exchange: aimed at you from 10 m, out of her 5.5 m")
end

entry("ghost_soul_exchange", soul_exchange_positive, soul_exchange_negative)

-- Close the Deal: his telegraph, you 300 u (7.6 m) in front, inside GrabRange 10 m: timed 0.45 s
-- out, as the grab landed 0.47-0.54 s after the telegraph in game
local function close_deal_positive(spell)
    local danny, st = actor(285, -300, -600, 0, "ability_deadpack_ultimate", { AbilityCastRange = 10 })
    local w = world(spell, danny)
    st.particles = { "particles/abilities/airheart/airheart_ult_telegraph.vpcf" }
    step(w)
    local zn = target_zone()
    assert(zn and math.abs(zn.at - (1 / 60 + 0.45)) < 0.02, "close the deal: no target zone timed to the grab")
    run(w, 0.6) -- still on you after the scans: a target once picked stays picked
    assert(target_zone().at == zn.at, "close the deal: lost you between scans")
end

local function close_deal_negative(spell)
    local danny, st = actor(286, -600, -600, 0, "ability_deadpack_ultimate", { AbilityCastRange = 10 })
    local w = world(spell, danny)
    st.particles = { "particles/abilities/airheart/airheart_ult_telegraph.vpcf" }
    S.zones = {}
    run(w, 0.3)
    assert(not target_zone(), "close the deal: aimed at you from 15 m, out of his 10 m")
end

entry("danny_close_the_deal", close_deal_positive, close_deal_negative)
end

do -- Rat King's, in a block of their own: the main chunk is at Lua's 200 locals
local function circle()
    for _, z in ipairs(S.zones) do if z.kind == "circle" then return z end end
end

-- Scrap Grenade: thrown (gravity 1.85), it lands with a rebound and lies there; each landing's blast
-- comes its own fuse after the first touch (0.8, 0.7, 1.5 s), and after the first two it hops straight
-- up at 1000 u/s and comes down again. Its 8 m area is drawn where it lies, timed to that landing's
-- fuse; the rebound neither restarts the fuse nor counts as a hop. Gone after the third
entry("ratking_scrap_grenade", function(spell)
    local rat = actor(470, 3000, 0, 0, "ability_ratking_scrap_grenade", { ShrapnelSphereRadius = 8 })
    local nade, _, pos = mkproj(471, 3200, 0, 100, "particles/abilities/ratking/ratking_scrap_grenade_projectile.vpcf")
    local w = world(spell, rat, { nade })
    local G, FUSE = 800 * 1.85, { 0.8, 0.7, 1.5 }
    local x, z, vx, vz = 3200, 100, 600, 300
    local n, touched, checked = 1, nil, {}
    for i = 1, 6 * 60 do
        local t = i / 60
        if z > 0 or vz > 0 then
            x, z, vz = x + vx / 60, z + vz / 60 - 0.5 * G / 3600, vz - G / 60
            if z <= 0 then
                touched = touched or t
                -- a rebound off the floor at 0.3 of its fall (m_flBounceVerticalDampening), then it lies
                z, vx, vz = 0, 0, vz < -400 and -vz * 0.3 or 0
                assert(vz < 500, "scrap grenade fixture: its rebound is as fast as a hop")
            end
        elseif touched and t >= touched + FUSE[n] then
            if n == 3 then break end
            n, touched, vz = n + 1, nil, 1000 -- it blows and hops on, straight up: no hero near
        end
        pos[1], pos[3] = x, z
        S.zones = {}
        local g = step(w)
        local zn = circle()
        if touched and z == 0 and vz == 0 and t > touched + 0.3 then
            assert(g and zn and math.abs(zn.x - x) < 1 and math.abs(zn.r - 8 * UPM) < 1,
                "scrap grenade: no 8 m area where it lies, landing " .. n)
            assert(math.abs(zn.at - (touched + FUSE[n])) < 0.08, ("scrap grenade: landing %d timed %.2f s, wanted %.2f")
                :format(n, zn.at, touched + FUSE[n]))
            checked[n] = true
        end
    end
    assert(checked[1] and checked[2] and checked[3], "scrap grenade: not every landing was timed")
    nade.valid = function() return false end
    S.zones = {}
    step(w)
    assert(#S.zones == 0, "scrap grenade: its area still up after its last blast")
    -- the entry needs an area up at the end: one more in flight
    local nade2, _, pos2 = mkproj(473, 3200, 0, 100, "particles/abilities/ratking/ratking_scrap_grenade_projectile.vpcf")
    local w2 = world(spell, actor(474, 3000, 0, 0, "ability_ratking_scrap_grenade", {}), { nade2 })
    for i = 1, 6 do pos2[1], pos2[3] = 3200 + 600 * i / 60, 100 + 100 * i / 60; step(w2) end
end, function(spell)
    -- his own aim preview isn't the grenade
    local rat = actor(475, 3000, 0, 0, "ability_ratking_scrap_grenade", {})
    local preview = mkproj(476, 3200, 0, 100, "particles/abilities/ratking/ratking_scrap_grenade_projectile_preview.vpcf")
    local w = world(spell, rat, { preview })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "scrap grenade: the preview particle detected")
end)

-- Rule, Ratannia!: the slam's anticipation decal (its CP0) marks a Radius 20 m area, timed
-- m_flExplodeTimer 0.25 s from it
entry("ratking_rule_ratannia", function(spell)
    local rat = actor(477, 7000, 0, 0, "ability_ratking_standard_bearer", { Radius = 20 })
    local w = world(spell, rat)
    X.track_particle({ name = "particles/abilities/ratking/ratking_standard_bearer_anticipation.vpcf", index = 63 })
    X.update_particle({ index = 63, control_point = 0, position = Vector(7300, 0, 0) })
    local g
    for _ = 1, 6 do S.zones = {}; g = step(w) or g end
    assert(g and g.warning and math.abs(g.warning.x - 7300) < 1, "rule ratannia: not on its tell's CP0")
    assert_marker(7300, 0, 20, "rule ratannia")
    local zn = circle()
    assert(zn and zn.at and math.abs(zn.at - (g.first + 0.25)) < 0.05, "rule ratannia: not timed 0.25 s from its tell")
end, function(spell)
    -- the blast itself and the charge's cast effect aren't the tell
    local rat = actor(478, 7000, 0, 0, "ability_ratking_standard_bearer", {})
    local w = world(spell, rat)
    for i, name in ipairs({ "particles/abilities/ratking/ratking_standard_bearer_explode.vpcf",
                            "particles/abilities/ratking/ratking_standard_bearer_cast.vpcf" }) do
        X.track_particle({ name = name, entity = rat, index = 63 + i })
        X.update_particle({ index = 63 + i, control_point = 0, position = Vector(7300, 0, 0) })
    end
    run(w, 0.4)
    assert(count_groups(spell) == 0, "rule ratannia: its blast or cast effect taken for the tell")
end)
end

do -- Silver's, in a block of their own: the main chunk is at Lua's 200 locals
local function zones_of(kind)
    local out = {}
    for _, z in ipairs(S.zones) do if z.kind == kind then out[#out + 1] = z end end
    return out
end

-- a leap off her clip, then off her "leaping" modifier: the wind-up lane timed `release` after the clip
-- at the leap's speed, another clip starting nothing, then the leap's own lane from where it began
local function leap_positive(spell, h, clip, modname, speed, release, range, width)
    local wolf = actor(h, 4000, 0, 0, spell.ability, {})
    local w = world(spell, wolf)
    step(w)
    X.track_animation(wolf, { name = "ability_tail_whack", duration = 0.7 })
    S.zones = {}
    step(w)
    assert(#zones_of("lane") == 0, spell.name .. ": a lane from a clip that isn't its wind-up")
    X.track_animation(wolf, { name = clip, duration = 0.6 })
    local wound = S.now
    local lane
    for _ = 1, 12 do
        S.zones = {}
        step(w)
        lane = zones_of("lane")[1]
        assert(not lane or math.abs(lane.delay - (wound + release - S.now)) < 1e-6 and lane.speed == speed,
            spell.name .. ": the wind-up not timed to the leap")
    end
    assert(lane, spell.name .. ": no lane while she winds up")
    assert_lane(4000, 0, width, range, 2.5, spell.name .. " wind-up", 1.7)

    local wolf2, st2, pos2 = actor(h + 1, 4000, 0, 0, spell.ability, {})
    local w2 = world(spell, wolf2)
    st2.mods = { mod(modname) } -- as it read in game
    for _ = 1, 20 do pos2[1] = pos2[1] + speed / 60; S.zones = {}; step(w2) end
    assert_lane(4000, 0, width, range, 2.5, spell.name, 1.7)
    local z = zones_of("lane")[1]
    assert(z and z.speed and (z.delay or 0) == 0, spell.name .. ": the leap's own lane not timed now")
end

-- and neither her other leap's modifier nor a walk with this one on her draws it
local function leap_negative(spell, h, other, modname)
    local wolf, st, pos = actor(h, 4000, 0, 0, spell.ability, {})
    local w = world(spell, wolf)
    st.mods = { mod(other) }
    for _ = 1, 20 do pos[1] = pos[1] + 1300 / 60; step(w) end
    assert(count_groups(spell) == 0, spell.name .. ": her other leap taken for it")
    local wolf2, st2, pos2 = actor(h + 1, 4000, 0, 0, spell.ability, {})
    local w2 = world(spell, wolf2)
    st2.mods = { mod(modname) }
    for _ = 1, 40 do pos2[1] = pos2[1] - 8 * UPM / 60; S.zones = {}; step(w2) end
    assert(#zones_of("lane") == 0, spell.name .. ": a lane while she walks")
end

-- Boot Kick: AbilityCastRange 10.6 m and LeapForwardOffset 2.5 m, LeapRadius 1.7 m, at 1270 u/s
entry("silver_boot_kick", function(spell)
    leap_positive(spell, 480, "ability_boot_kick_start", "ability_werewolf_kickflip/leaping", 1270, 0.25, 13.1, 1.7)
end, function(spell)
    leap_negative(spell, 482, "ability_werewolf_maulingleap/leaping", "ability_werewolf_kickflip/leaping")
end)

-- Mauling Leap: AbilityCastRange 18.1 m and LeapForwardOffset 0.3 m, LeapRadius 2.8 m, at 1300 u/s
entry("silver_mauling_leap", function(spell)
    leap_positive(spell, 484, "ability_mauling_leap_stand_start", "ability_werewolf_maulingleap/leaping", 1300, 0.35, 18.4, 2.8)
end, function(spell)
    leap_negative(spell, 486, "ability_werewolf_kickflip/leaping", "ability_werewolf_maulingleap/leaping")
end)

-- Entangling Bola: a lane off its bullet (3000 u/s, m_flBulletRadius 38 u), and before it, from her
-- throw clip, along her aim timed to the throw 0.24 s on
entry("silver_entangling_bola", function(spell)
    local silver = actor(488, 9600, 0, 0, "ability_werewolf_netshot", {})
    local w = world(spell, silver)
    step(w)
    X.track_animation(silver, { name = "ability_entangling_bola_haspath", duration = 0.5 })
    local wound = S.now
    S.zones = {}
    step(w)
    local lane = zones_of("lane")[1]
    for _ = 1, 6 do S.zones = {}; step(w); lane = zones_of("lane")[1] end
    assert(lane and math.abs(lane.delay - (wound + 0.24 - S.now)) < 1e-6 and lane.speed == 3000,
        "entangling bola: the wind-up not timed to the throw")

    local silver2 = actor(489, 9600, 0, 0, "ability_werewolf_netshot", {})
    local w2 = world(spell, silver2)
    X.track_bullet({ weapon_name = "ability_werewolf_netshot", shooter = silver2, start_pos = Vector(9600, 0, 100), direction = Vector(1, 0, 0) })
    S.zones = {}
    step(w2)
    local g
    for _, r in pairs(S.list) do if r.spell == spell and r.shot then g = r end end
    assert(g, "entangling bola: the throw made no lane")
    clear_rec()
    D.draw_entity(g, viewer)
    assert_lane(9600, 0, 38 / UPM, 152.4, nil, "entangling bola")
    local l = zones_of("lane")
    assert(#l >= 1 and l[#l].speed == 3000, "entangling bola: its lane not timed at 3000 u/s")
end, function(spell)
    -- her rifle's bullets aren't the bola, and her kick's clip starts nothing
    local silver = actor(490, 9600, 0, 0, "ability_werewolf_netshot", {})
    local w = world(spell, silver)
    X.track_bullet({ weapon_name = "citadel_weapon_werewolf_rifle", shooter = silver, start_pos = Vector(9600, 0, 100), direction = Vector(1, 0, 0) })
    X.track_animation(silver, { name = "ability_boot_kick_start", duration = 0.6 })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "entangling bola: her rifle or kick taken for the bola")
end)

-- Rake: a 10 m, 60 deg fan from Mina's rake clip, timed 0.1 s on
entry("mina_rake", function(spell)
    local mina = actor(487, 7800, 0, 0, "ability_vampirebat_steallife", { AbilityCastRange = 10 })
    local w = world(spell, mina)
    step(w)
    X.track_animation(mina, { name = "vampirebat_ability_rake", duration = 0.93 })
    local t0 = S.now
    S.zones = {}
    step(w)
    local z = zones_of("cone")[1]
    assert(z and math.abs(z.at - (t0 + 0.1)) < 1e-6 and math.abs(z.r - 10 * UPM) < 1
        and math.abs(z.half - math.rad(30)) < 1e-6, "rake: no 10 m, 60 deg fan timed 0.1 s after her clip")
end, function(spell)
    local mina = actor(488, 7800, 0, 0, "ability_vampirebat_steallife", {})
    local w = world(spell, mina)
    step(w)
    X.track_animation(mina, { name = "vampirebat_weapon_run_nw", duration = 0.53 })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "rake: drawn without its clip")
end)

-- Go For The Throat: a 7.5 m, 40 deg fan from her bite clip, standing or moving, timed 0.2 s on
entry("silver_go_for_the_throat", function(spell)
    for i, clip in ipairs({ "ability_go_for_the_throat_idle", "ability_go_for_the_throat_haspath" }) do
        local wolf = actor(490 + i, 7800, 0, 0, "ability_werewolf_frenzy", { AbilityCastRange = 7.5 })
        local w = world(spell, wolf)
        step(w)
        X.track_animation(wolf, { name = clip, duration = 0.7 })
        local t0 = S.now
        S.zones = {}
        step(w)
        local z = zones_of("cone")[1]
        assert(z and math.abs(z.at - (t0 + 0.2)) < 1e-6 and math.abs(z.r - 7.5 * UPM) < 1
            and math.abs(z.half - math.rad(20)) < 1e-6, "go for the throat: no 7.5 m, 40 deg fan timed 0.2 s after " .. clip)
    end
end, function(spell)
    local wolf = actor(493, 7800, 0, 0, "ability_werewolf_frenzy", {})
    local w = world(spell, wolf)
    step(w)
    X.track_animation(wolf, { name = "ability_tail_whack", duration = 0.7 })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "go for the throat: drawn without its clip")
end)

-- Tail Whack: her clip starts a SlashRadius 10 m ring on her, timed to the smash 0.15 s on, gone after it
entry("silver_tail_whack", function(spell)
    local wolf = actor(494, 9600, 0, 0, "ability_werewolf_cripplingslash", { SlashRadius = 10 })
    local w = world(spell, wolf)
    step(w)
    X.track_animation(wolf, { name = "ability_tail_whack", duration = 0.7 })
    local cast = S.now
    S.zones = {}
    step(w)
    local ring = zones_of("circle")[1]
    assert(ring and math.abs(ring.r - 10 * UPM) < 1 and math.abs(ring.x - 9600) < 1, "tail whack: no 10 m ring on her")
    assert(ring.at and math.abs(ring.at - (cast + 0.15)) < 1e-6 and not ring.lingers,
        "tail whack: the ring not timed to the smash")
    run(w, 1)
    S.zones = {}
    step(w)
    assert(#zones_of("circle") == 0, "tail whack: the ring still up after the smash")
    -- the entry needs an area up at the end: a second whack
    X.track_animation(wolf, { name = "ability_tail_whack", duration = 0.7 })
    step(w)
end, function(spell)
    local wolf = actor(495, 9600, 0, 0, "ability_werewolf_cripplingslash", {})
    local w = world(spell, wolf)
    step(w)
    X.track_animation(wolf, { name = "ability_go_for_the_throat_idle", duration = 0.7 })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "tail whack: drawn without its clip")
end)
end

do -- Shiv's, in a block of their own: the main chunk is at Lua's 200 locals
-- Serrated Knives: a lane off each knife's bullet (4500 u/s, m_flBulletRadius 23 u)
entry("shiv_serrated_knives", function(spell)
    local shiv = actor(700, 9600, 0, 0, "citadel_ability_shiv_dagger", {})
    local w = world(spell, shiv)
    X.track_bullet({ weapon_name = "citadel_ability_shiv_dagger", shooter = shiv, start_pos = Vector(9600, 0, 100), direction = Vector(1, 0, 0) })
    S.zones = {}
    step(w)
    local g
    for _, r in pairs(S.list) do if r.spell == spell and r.shot then g = r end end
    assert(g, "serrated knives: the throw made no lane")
    clear_rec()
    D.draw_entity(g, viewer)
    assert_lane(9600, 0, 23 / UPM, 254, nil, "serrated knives")
    local lane
    for _, z in ipairs(S.zones) do if z.kind == "lane" then lane = z end end
    assert(lane and lane.speed == 4500, "serrated knives: its lane not timed at 4500 u/s")
end, function(spell)
    -- his gun's bullets aren't the knives
    local shiv = actor(701, 9600, 0, 0, "citadel_ability_shiv_dagger", {})
    local w = world(spell, shiv)
    X.track_bullet({ weapon_name = "citadel_weapon_shiv_set", shooter = shiv, start_pos = Vector(9600, 0, 100), direction = Vector(1, 0, 0) })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "serrated knives: his gun's bullet taken for a knife")
end)

-- Slice and Dice: a lane off his dash modifier, DashRadius 2.5 m each side, DashRange 12 m at 2400 u/s
entry("shiv_slice_and_dice", function(spell)
    local function lanes() -- every group of it drawn: step() draws one, and the dash's hides its echo
        for _, r in pairs(S.list) do if r.spell == spell then D.draw_entity(r, viewer) end end
        local out = {}
        for _, z in ipairs(S.zones) do if z.kind == "lane" then out[#out + 1] = z end end
        return out
    end
    -- the wind-up: his ability_dash_start clip, 0.24 s before he moves. Along his aim, timed to the dash
    local shiv2, st2, pos2 = actor(708, 1200, 0, 0, "citadel_ability_shiv_dash", { DashRange = 12 })
    local w2 = world(spell, shiv2)
    step(w2)
    X.track_animation(shiv2, { name = "ability_dash_start", duration = 0.33 })
    local wound = S.now
    for _ = 1, 12 do step(w2) end
    S.zones = {}
    step(w2)
    local z = lanes()[1]
    assert(z and z.delay and math.abs(z.delay - (wound + 0.24 - S.now)) < 1e-6 and z.speed == 2400,
        "slice and dice: the wind-up not timed to the dash leaving")

    -- the echo: 0.75 s after the dash its particle plays again and it strikes along the dash's path.
    -- Laid from the dash once it is over, timed to leave then; the echo particle starts no dash of its own
    local DASH = "particles/abilities/shiv/shiv_dash_instant.vpcf"
    X.track_particle({ name = DASH, entity = shiv2, index = 7081 })
    local dashed = S.now
    st2.mods = { mod("citadel_ability_shiv_dash/modifier_citadel_shiv_dash") }
    for _ = 1, 12 do pos2[1] = pos2[1] + 2400 / 60; step(w2) end
    st2.mods = {}
    local echo
    for _ = 1, 20 do
        pos2[1] = pos2[1] - 300 / 60 -- he walks back the way he came
        S.zones = {}
        step(w2)
        for _, l in ipairs(lanes()) do if l.delay and l.delay > 0.2 then echo = l end end
    end
    -- to where he was as it was laid, 0.3 s in: the dash's 480 u, less 0.1 s of walking back
    assert(echo and math.abs(echo.x - 1200) < 1 and math.abs(echo.bx - 1650) < 1 and echo.speed == 2400,
        "slice and dice: no echo along the dash's path")
    while S.now < dashed + 0.75 do step(w2) end
    X.track_particle({ name = DASH, entity = shiv2, index = 7082 })
    for _ = 1, 30 do -- past when an echo of it would be laid, from his walk
        pos2[1] = pos2[1] - 300 / 60
        S.zones = {}
        step(w2)
        for _, l in ipairs(lanes()) do
            assert(l.bx > l.x, "slice and dice: the echo particle drawn as a dash the way he walks")
        end
    end

    -- the dash itself, last: its lane is what the run checks Evade gets
    local shiv, st, pos = actor(702, 1200, 0, 0, "citadel_ability_shiv_dash", { DashRange = 12 })
    local w = world(spell, shiv)
    st.mods = { mod("citadel_ability_shiv_dash/modifier_citadel_shiv_dash") } -- as it read in game
    for _ = 1, 8 do pos[1] = pos[1] + 2400 / 60; step(w) end
    assert_lane(1200, 0, 2.5, 12, 2.5, "slice and dice", 1.8)
end, function(spell)
    -- Calico's Leaping Slash wears the same modifier, under her own ability
    local calico, cst = actor(703, 1200, 0, 0, "ability_nano_dash", {})
    local shiv = actor(704, 1200, 300, 0, "citadel_ability_shiv_dash", {})
    cst.mods = { mod("ability_nano_dash/modifier_citadel_shiv_dash") }
    run(world(spell, shiv, { calico }), 0.4)
    assert(count_groups(spell) == 0, "slice and dice: Calico's leap taken for his dash")
end)

-- Killing Blow: his cast particle, you 300 u (7.6 m) in front, inside AbilityCastRange 12 m: timed
-- 0.15 s out, under Parry Lead: the execute landed 0.07-0.41 s after it
local KB_TELL = "particles/abilities/shiv/shiv_killing_blow_cast.vpcf"
local function kb_zone()
    for _, z in ipairs(S.zones) do if z.kind == "target" then return z end end
end
entry("shiv_killing_blow", function(spell)
    local shiv, st = actor(705, -300, -600, 0, "citadel_ability_shiv_killing_blow", { AbilityCastRange = 12 })
    local w = world(spell, shiv)
    st.particles = { KB_TELL }
    S.zones = {}
    step(w)
    local zn = kb_zone()
    assert(zn and math.abs(zn.at - (1 / 60 + 0.15)) < 0.02, "killing blow: no target zone timed 0.15 s out")
end, function(spell)
    -- from 15 m, out of his 12 m; and the icon only he sees over you is not his cast
    local shiv, st = actor(706, -600, -600, 0, "citadel_ability_shiv_killing_blow", { AbilityCastRange = 12 })
    local w = world(spell, shiv)
    st.particles = { KB_TELL }
    S.zones = {}
    run(w, 0.3)
    assert(not kb_zone(), "killing blow: aimed at you from 15 m, out of his 12 m")
    local near, nst = actor(707, -300, -600, 0, "citadel_ability_shiv_killing_blow", { AbilityCastRange = 12 })
    nst.particles = { "particles/abilities/shiv/shiv_killing_blow_cast_tgt_icon.vpcf" }
    S.zones = {}
    run(world(spell, near), 0.3)
    assert(not kb_zone(), "killing blow: his target icon taken for the cast")
end)
end

do -- Vindicta's, in a block of their own: the main chunk is at Lua's 200 locals
local function zones_of(kind)
    local out = {}
    for _, z in ipairs(S.zones) do if z.kind == kind then out[#out + 1] = z end end
    return out
end

-- Stake: lobbed as a bullet (1600 u/s, gravity 0.8); its CaptureRadius 9 m area where it lands, timed
entry("vindicta_stake", function(spell)
    local vindicta = actor(720, 9000, 0, 0, "citadel_ability_hornet_chain", { CaptureRadius = 9 })
    local w = world(spell, vindicta)
    step(w)
    local n = math.sqrt(1 + 0.04)
    X.track_bullet({ weapon_name = "citadel_ability_hornet_chain", shooter = vindicta,
        start_pos = Vector(9000, 0, 100), direction = Vector(1 / n, 0, 0.2 / n) })
    S.zones = {}
    local g = step(w)
    assert(g and g.shot and g.land and g.land.z < 20, "stake: its bullet drew no lob to the ground")
    local zn = zones_of("circle")[1]
    assert(zn and math.abs(zn.r - 9 * UPM) < 1 and zn.at and math.abs(zn.at - g.lands_at) < 0.05
        and math.abs(zn.x - g.land.x) < 1, "stake: no 9 m area where it lands, timed to the landing")
end, function(spell)
    -- her rifle's bullets and her crow aren't the stake
    local vindicta = actor(721, 9000, 0, 0, "citadel_ability_hornet_chain", {})
    local w = world(spell, vindicta)
    for _, wn in ipairs({ "citadel_weapon_hornet_set", "citadel_ability_hornet_sting" }) do
        X.track_bullet({ weapon_name = wn, shooter = vindicta, start_pos = Vector(9000, 0, 100), direction = Vector(1, 0, 0) })
    end
    run(w, 0.4)
    assert(count_groups(spell) == 0, "stake: her rifle or crow taken for the stake")
end)

-- Crow Familiar: a lane off each of its bullets (4250 u/s, m_flBulletRadius 26 u)
entry("vindicta_crow_familiar", function(spell)
    local vindicta = actor(722, 9600, 0, 0, "citadel_ability_hornet_sting", {})
    local w = world(spell, vindicta)
    X.track_bullet({ weapon_name = "citadel_ability_hornet_sting", shooter = vindicta, start_pos = Vector(9600, 0, 100), direction = Vector(1, 0, 0) })
    S.zones = {}
    step(w)
    local g
    for _, r in pairs(S.list) do if r.spell == spell and r.shot and math.abs(r.land.y) < 1 then g = r end end
    assert(g, "crow familiar: the crow made no lane along her aim")
    clear_rec()
    D.draw_entity(g, viewer)
    assert_lane(9600, 0, 26 / UPM, 215.9, nil, "crow familiar")
    local lane = zones_of("lane")[1]
    assert(lane and lane.speed == 4250, "crow familiar: its lane not timed at 4250 u/s")

    -- the volley's 13 bullets all come with her aim: the first lays a lane per offset, fanned out to
    -- 6.5 deg each side, and the other 12 add none
    local crow = actor(724, 9600, 0, 0, "citadel_ability_hornet_sting", {})
    local w2 = world(spell, crow)
    for _ = 1, 13 do
        X.track_bullet({ weapon_name = "citadel_ability_hornet_sting", shooter = crow, start_pos = Vector(9600, 0, 100), direction = Vector(1, 0, 0) })
    end
    step(w2)
    local ends = {}
    for _, r in pairs(S.list) do
        if r.spell == spell and r.shot and r.owner == crow then ends[#ends + 1] = math.deg(math.atan(r.land.y, r.land.x - 9600)) end
    end
    table.sort(ends)
    assert(#ends == #spell.scatter, ("crow familiar: %d lanes for a volley, not %d"):format(#ends, #spell.scatter))
    assert(math.abs(ends[1] + 6.5) < 0.01 and math.abs(ends[#ends] - 6.5) < 0.01, "crow familiar: the fan not 6.5 deg each side")
end, function(spell)
    -- her rifle's bullets and the stake aren't the crow
    local vindicta = actor(723, 9600, 0, 0, "citadel_ability_hornet_sting", {})
    local w = world(spell, vindicta)
    for _, wn in ipairs({ "citadel_weapon_hornet_set", "citadel_ability_hornet_chain" }) do
        X.track_bullet({ weapon_name = wn, shooter = vindicta, start_pos = Vector(9600, 0, 100), direction = Vector(1, 0, 0) })
    end
    run(w, 0.4)
    assert(count_groups(spell) == 0, "crow familiar: her rifle or stake taken for the crow")
end)
end

do -- Warden's, in a block of their own: the main chunk is at Lua's 200 locals
local function zones_of(kind)
    local out = {}
    for _, z in ipairs(S.zones) do if z.kind == kind then out[#out + 1] = z end end
    return out
end

-- Alchemical Flask: thrown (m_flSpeed 980, m_flUpSpeed 385, gravity 1.96) from 100 u up, it lands
-- 0.68 s on, 665 u ahead; its Radius 5.5 m burst is drawn there, timed to the landing
entry("warden_alchemical_flask", function(spell)
    local warden = actor(610, 3000, 0, 0, "ability_warden_crowd_control", { Radius = 5.5 })
    local flask, _, pos = mkproj(611, 3200, 0, 100, "particles/abilities/warden/warden_flask_grenade_projectile.vpcf")
    local w = world(spell, warden, { flask })
    local G = 800 * 1.96
    local T = (385 + math.sqrt(385 ^ 2 + 2 * G * 100)) / G
    local x, z, vz = 3200, 100, 385
    for i = 1, 12 do
        x, z, vz = x + 980 / 60, z + vz / 60 - 0.5 * G / 3600, vz - G / 60
        pos[1], pos[3] = x, z
        S.zones = {}
        step(w)
        if i == 12 then
            local c = zones_of("circle")[1]
            assert(c and math.abs(c.r - 5.5 * UPM) < 1 and math.abs(c.x - (3200 + 980 * T)) < 0.5 * UPM,
                "alchemical flask: no 5.5 m burst where it lands")
            assert(c.at and math.abs(c.at - T) < 0.08, ("alchemical flask: burst timed %s s, wanted %.2f")
                :format(tostring(c.at), T))
        end
    end
end, function(spell)
    -- his cast effect and the burst's own effects are not the flask
    local warden = actor(612, 3000, 0, 0, "ability_warden_crowd_control", {})
    local cast = mkproj(613, 3200, 0, 100, "particles/abilities/warden/warden_flask_grenade.vpcf")
    local aoe = mkproj(614, 3600, 0, 0, "particles/abilities/warden/warden_flask_grenade_aoe.vpcf")
    run(world(spell, warden, { cast, aoe }), 0.4)
    assert(count_groups(spell) == 0, "alchemical flask: his cast or burst effect taken for the flask")
end)

-- Binding Word: cast at you from the moment its debuff comes on you, timed EscapeTime 2.8 s on, and
-- still once the debuff is gone, up to the root
entry("warden_binding_word", function(spell)
    local warden = actor(615, 3000, 0, 0, "ability_warden_lock_down", { AbilityCastRange = 15 })
    local w = world(spell, warden)
    step(w)
    local mark = mod("ability_warden_lock_down/modifier_warden_lockdown_debuff")
    local mods = viewer.get_modifiers
    viewer.get_modifiers = function() return { mark } end
    X.track_modifier_add(mark, viewer)
    local t0 = S.now
    S.zones = {}
    step(w)
    local z = zones_of("target")[1]
    assert(z and math.abs(z.at - (t0 + 2.8)) < 1e-6, "binding word: not cast at you, timed 2.8 s on, once marked")
    viewer.get_modifiers = mods
    while S.now < t0 + 2.6 do step(w) end
    S.zones = {}
    step(w)
    z = zones_of("target")[1]
    assert(z and math.abs(z.at - (t0 + 2.8)) < 1e-6, "binding word: dropped before its root")
end, function(spell)
    -- his mark on another hero, or the root itself on you: nothing
    local victim = actor(616, 300, -600, 0, nil, {})
    local warden = actor(617, 300, 0, 0, "ability_warden_lock_down", {})
    local w = world(spell, warden, { victim })
    step(w)
    X.track_modifier_add(mod("ability_warden_lock_down/modifier_warden_lockdown_debuff"), victim)
    X.track_modifier_add(mod("ability_warden_lock_down/modifier_citadel_root"), viewer)
    S.zones = {}
    run(w, 0.4)
    assert(#zones_of("target") == 0, "binding word: cast at you with no mark on you")
end)
end

do -- Viscous's, in a block of their own: the main chunk is at Lua's 200 locals
local function zone_of(kind)
    for _, z in ipairs(S.zones) do if z.kind == kind then return z end end
end

-- Splatter: thrown at 600 u/s, 300 up under sv_gravity, it bounces off the floor at 0.6 of its fall
-- twice and lies there. Its 5 m area is where each fall comes down, timed to it
entry("viscous_splatter", function(spell)
    local vis = actor(800, 3000, 0, 0, "viscous_goo_grenade", { Radius = 5 })
    local ball, _, pos = mkproj(801, 3200, 0, 100, "particles/abilities/viscous/viscous_sticky_grenade_projectile.vpcf")
    local w = world(spell, vis, { ball })
    local x, z, vx, vz, n, bounced, guess, checked = 3200, 100, 600, 300, 1, 0, nil, {}
    for i = 1, 4 * 60 do
        local t = i / 60
        if n > 3 then break end
        x, z, vz = x + vx / 60, z + vz / 60 - 0.5 * 800 / 3600, vz - 800 / 60
        if z <= 0 then
            -- the guess from 0.15 s or more after the last bounce, a sample in, is this landing
            assert(guess and math.abs(guess.x - x) < 0.5 * UPM and math.abs(guess.at - t) < 0.08,
                ("splatter: landing %d at %.0f, %.2f s; drawn at %s, %s"):format(n, x, t,
                    guess and ("%.0f"):format(guess.x) or "-", guess and ("%.2f s"):format(guess.at) or "-"))
            checked[n], n, bounced, guess, z, vz = true, n + 1, t, nil, 0, -vz * 0.6
        end
        pos[1], pos[3] = x, z
        S.zones = {}
        step(w)
        local zn = zone_of("circle")
        if zn and t > bounced + 0.15 then
            assert(math.abs(zn.r - 5 * UPM) < 1, "splatter: its area isn't 5 m")
            guess = guess or { x = zn.x, at = zn.at } -- the earliest guess this fall
        end
    end
    assert(checked[1] and checked[2] and checked[3], "splatter: not every landing was drawn and timed")
    -- the entry needs an area up at the end: one more in flight
    local ball2, _, pos2 = mkproj(802, 3200, 0, 100, "particles/abilities/viscous/viscous_sticky_grenade_projectile.vpcf")
    local w2 = world(spell, actor(803, 3000, 0, 0, "viscous_goo_grenade", {}), { ball2 })
    for i = 1, 6 do pos2[1], pos2[3] = 3200 + 600 * i / 60, 100 + 250 * i / 60; step(w2) end
end, function(spell)
    -- the slow on a hero it hit isn't the ball
    local vis = actor(804, 3000, 0, 0, "viscous_goo_grenade", {})
    local goo = mkproj(805, 3200, 0, 100, "particles/abilities/viscous/viscous_sticky_grenade_debuff.vpcf")
    run(world(spell, vis, { goo }), 0.4)
    assert(count_groups(spell) == 0, "splatter: its debuff particle detected")
end)
end

do -- Vyper's: each a lane off its bullet, and her gun's bullets are neither
local function bullet_positive(spell, h, radius, range, speed)
    local vyper = actor(h, 9600, 0, 0, spell.ability, {})
    local w = world(spell, vyper)
    X.track_bullet({ weapon_name = spell.ability, shooter = vyper, start_pos = Vector(9600, 0, 100), direction = Vector(1, 0, 0) })
    S.zones = {}
    step(w)
    local g
    for _, r in pairs(S.list) do if r.spell == spell and r.shot then g = r end end
    assert(g, spell.name .. ": the throw made no lane")
    clear_rec()
    D.draw_entity(g, viewer)
    assert_lane(9600, 0, radius / UPM, range, nil, spell.name)
    local lane
    for _, z in ipairs(S.zones) do if z.kind == "lane" then lane = z end end
    assert(lane and lane.speed == speed, spell.name .. ": its lane not timed at " .. speed .. " u/s")
end
local function bullet_negative(spell, h)
    local vyper = actor(h, 9600, 0, 0, spell.ability, {})
    local w = world(spell, vyper)
    X.track_bullet({ weapon_name = "citadel_weapon_viper_set", shooter = vyper, start_pos = Vector(9600, 0, 100), direction = Vector(1, 0, 0) })
    run(w, 0.4)
    assert(count_groups(spell) == 0, spell.name .. ": her gun's bullet taken for it")
end

-- Screwjab Dagger: 4200 u/s, m_flBulletRadius 23 u, its 2 s lifetime 213.4 m
entry("vyper_screwjab_dagger", function(spell) bullet_positive(spell, 810, 23, 213.4, 4200) end,
    function(spell) bullet_negative(spell, 811) end)
-- Petrifying Bola: 2000 u/s, m_flBulletRadius 45 u, its 2 s lifetime 101.6 m
entry("vyper_petrifying_bola", function(spell) bullet_positive(spell, 812, 45, 101.6, 2000) end,
    function(spell) bullet_negative(spell, 813) end)
end

do -- Wraith's, in a block of their own: the main chunk is at Lua's 200 locals
-- Card Trick: a line off each card (its suit's trail), m_flTriggerRadius 15 u, at m_flSpeed 1080 u/s
entry("wraith_card_trick", function(spell)
    local wraith = actor(710, 7400, 0, 0, "citadel_ability_card_toss", {})
    local card, _, pos = mkproj(711, 7500, 0, 40, "particles/abilities/wraith/wraith_card_trick_spade.vpcf")
    local w = world(spell, wraith, { card })
    for _ = 1, 20 do S.zones = {}; step(w); pos[1] = pos[1] + 1080 / 60 end
    assert_lane(7500, 40, 15 / UPM, 100, nil, "card trick")
    local l = {}
    for _, z in ipairs(S.zones) do if z.kind == "lane" then l[#l + 1] = z end end
    assert(#l == 1 and l[1].speed == 1080, "card trick: the card's lane not timed at its 1080 u/s")

    local function lanes()
        S.zones = {}
        for _, r in pairs(S.list) do if r.spell == spell then D.draw_entity(r, viewer) end end
        local out = {}
        for _, z in ipairs(S.zones) do
            assert(z.kind == "lane", "card trick: drawn as a sure hit (" .. z.kind .. "), but a card can miss")
            out[#out + 1] = z
        end
        return out
    end
    -- her throw clip, 800 u off: a lane along her aim at once, from her, the card leaving with the clip
    local wraith2 = actor(717, -800, -600, 0, "citadel_ability_card_toss", {})
    local w2 = world(spell, wraith2)
    step(w2)
    X.track_animation(wraith2, { name = "ability_card_trick", duration = 0.67 })
    step(w2)
    local thrown
    for _, z in ipairs(lanes()) do if math.abs(z.x - (-800)) < 1 then thrown = z end end
    assert(thrown and thrown.speed == 1080 and (thrown.delay or 0) == 0, "card trick: her throw clip drew no lane from her")
    -- a card that curves (it homes): its lane along where it heads now, not the average since first seen
    local wraith3 = actor(718, -900, 0, 0, "citadel_ability_card_toss", {})
    local card3, _, pos3 = mkproj(719, -600, 0, 50, "particles/abilities/wraith/wraith_card_trick_heart.vpcf")
    local w3 = world(spell, wraith3, { card3 })
    for _ = 1, 10 do step(w3); pos3[1] = pos3[1] + 1080 / 60 end -- along +x
    for _ = 1, 6 do step(w3); pos3[2] = pos3[2] - 1080 / 60 end  -- turned toward you, along -y
    step(w3)
    local l3 = lanes()[1]
    local ex, ey = l3.bx - l3.x, l3.by - l3.y
    assert(math.abs(ex) < 0.05 * math.abs(ey) and ey < 0, "card trick: a turning card's lane not along where it heads now")
end, function(spell)
    -- the card summoned over her head is not one thrown
    local wraith = actor(712, 7400, 0, 0, "citadel_ability_card_toss", {})
    local summoned = mkproj(713, 7400, 0, 120, "particles/abilities/wraith/wraith_psychic_card_spawn.vpcf")
    run(world(spell, wraith, { summoned }), 0.4)
    assert(count_groups(spell) == 0, "card trick: the summoned card taken for a thrown one")
end)

-- Telekinesis: m_TargetParticle on you starts it, on the hero playing Wraith, timed AbilityCastDelay
-- 0.45 s out
local TK_TELL = "particles/abilities/wraith/wraith_psychic_lift_cast.vpcf"
local function tk_zone()
    for _, z in ipairs(S.zones) do if z.kind == "target" then return z end end
end
entry("wraith_telekinesis", function(spell)
    local wraith = actor(714, 200, -600, 0, "citadel_ability_psychic_lift", { AbilityCastRange = 10 })
    local w = world(spell, wraith)
    step(w) -- a scan, so the heroes are listed
    X.track_particle({ name = TK_TELL, entity = viewer, index = 7141 })
    local told = S.now
    S.zones = {}
    step(w)
    local zn = tk_zone()
    assert(zn and math.abs(zn.at - (told + 0.45)) < 1e-6, "telekinesis: its tell on you drew nothing")
    S.targeted = {}
end, function(spell)
    -- the same tell on another hero: he is lifted, not you
    local wraith = actor(715, -300, -600, 0, "citadel_ability_psychic_lift", { AbilityCastRange = 10 })
    local ally = actor(716, 0, -400, 0, "citadel_ability_card_toss", {})
    local w = world(spell, wraith, { ally })
    step(w)
    X.track_particle({ name = TK_TELL, entity = ally, index = 7161 })
    S.zones = {}
    run(w, 0.3)
    assert(not tk_zone(), "telekinesis: its tell on another hero taken as aimed at you")
    S.targeted = {}
end)
end

do -- Venator's, in a block of their own: the main chunk is at Lua's 200 locals
local function zones_of(kind)
    local out = {}
    for _, z in ipairs(S.zones) do if z.kind == kind then out[#out + 1] = z end end
    return out
end

-- Consecrating Grenade: thrown low (2100 u/s, 100 up, gravity 0.7), it comes down, bounces on at half its
-- fall with its speed along the ground kept, and blows BounceLifetime 0.5 s after the first touch, in the
-- air, well past it. Its 4.5 m area is drawn where it blows, timed to it, both before the touch and after
entry("venator_consecrating_grenade", function(spell)
    local priest = actor(720, 3000, 0, 0, "ability_priest_flashbang", { Radius = 4.5 })
    local nade, _, pos = mkproj(721, 3000, 0, 150, "particles/abilities/priest/priest_flashbang_proj.vpcf")
    local w = world(spell, priest, { nade })
    local G = 800 * 0.7
    local x, z, vx, vz, touched = 3000, 150, 2100, 100, nil
    local seen = {}
    -- where it really blows: flown on ahead of the frames
    local bx, bt
    do
        local fx, fz, fvz, ft, ftouch = x, z, vz, 0, nil
        while not (ftouch and ft >= ftouch + 0.5) do
            ft = ft + 1 / 60
            fx, fz, fvz = fx + vx / 60, fz + fvz / 60 - 0.5 * G / 3600, fvz - G / 60
            if fz <= 0 then ftouch, fz, fvz = ftouch or ft, 0, -fvz * 0.5 end
        end
        bx, bt = fx, ftouch + 0.5
        assert(bx - (3000 + vx * ftouch) > 15 * UPM, "consecrating grenade fixture: it blows near its first touch")
    end
    for i = 1, 120 do
        local t = i / 60
        if t >= bt - 1e-9 then break end
        x, z, vz = x + vx / 60, z + vz / 60 - 0.5 * G / 3600, vz - G / 60
        if z <= 0 then touched, z, vz = touched or t, 0, -vz * 0.5 end
        pos[1], pos[3] = x, z
        S.zones = {}
        step(w)
        local zn = zones_of("circle")[1]
        if t > 0.15 and zn then
            local phase = touched and (t > touched + 0.1 and "after" or nil) or "before"
            if phase then
                -- 1.5 m: this fixture counts each touch on the frame after it, so its blast is ~1 m long
                assert(math.abs(zn.x - bx) < 1.5 * UPM and math.abs(zn.r - 4.5 * UPM) < 1, ("consecrating grenade: "
                    .. "%s the bounce its area is %.1f m from where it blows"):format(phase, math.abs(zn.x - bx) / UPM))
                assert(math.abs(zn.at - bt) < 0.05, ("consecrating grenade: %s the bounce timed %.2f s, wanted %.2f")
                    :format(phase, zn.at, bt))
                seen[phase] = true
            end
        end
    end
    assert(seen.before and seen.after, "consecrating grenade: not drawn both before and after its bounce")

    -- his throw clip lobs it at once, from his chest along his aim: its area where it blows, timed,
    -- before any grenade is seen; the grenade, once followed, takes over from it
    local priest2 = actor(731, 3000, 0, 0, "ability_priest_flashbang", { Radius = 4.5 })
    local nade2, nst2, pos2 = mkproj(732, 3000, 0, 36, nil)
    local w2 = world(spell, priest2, { nade2 })
    step(w2)
    X.track_animation(priest2, { name = "ability_flashbang_run", duration = 0.5 })
    local t0 = S.now
    S.zones = {}
    step(w2)
    local zn = zones_of("circle")[1]
    -- from 36 u up the same lob comes down 0.58 s on and blows 0.5 s later, 2100 u/s along the ground
    local touch = (100 + math.sqrt(100 * 100 + 2 * G * 36)) / G
    local wx = 3000 + 2100 * (touch + 0.5)
    assert(zn and math.abs(zn.x - wx) < 1 * UPM and math.abs(zn.at - (t0 + touch + 0.5)) < 0.05,
        ("consecrating grenade: his clip's lob not drawn where and when it blows (%.1f m off)")
        :format(zn and math.abs(zn.x - wx) / UPM or -1))
    nst2.particles[1] = "particles/abilities/priest/priest_flashbang_proj.vpcf"
    for i = 1, 12 do pos2[1] = 3000 + 2100 * i / 60; pos2[3] = 36 + 100 * i / 60 - 0.5 * G * (i / 60) ^ 2; S.zones = {}; step(w2) end
    -- every group of it drawn, as the game does: step draws only one
    S.zones = {}
    for _, r in pairs(S.list) do if r.spell == spell then D.draw_entity(r, viewer) end end
    assert(#zones_of("circle") == 1, "consecrating grenade: the lob still drawn beside the grenade it gave way to")

    -- thrown into you: it blows on you as it gets there, no fuse, and its area is where it would touch you,
    -- `contact` 1.5 m round, to step off its way: not its 4.5 m blast, too wide to walk out of in time
    local priest3 = actor(733, -1000, -600, 0, "ability_priest_flashbang", { Radius = 4.5 })
    local w3 = world(spell, priest3)
    step(w3)
    X.track_animation(priest3, { name = "ability_flashbang", duration = 0.4 })
    local t3 = S.now
    -- one throw plays its clips again within 0.3 s: still one grenade, one arc
    step(w3)
    X.track_animation(priest3, { name = "ability_flashbang_run", duration = 0.5 })
    local lobs = 0
    for _, r in pairs(S.groups) do if r.spell == spell and r.shot then lobs = lobs + 1 end end
    assert(lobs == 1, "consecrating grenade: one throw's clips lobbed " .. lobs .. " grenades")
    S.zones = {}
    step(w3)
    zn = zones_of("circle")[1]
    assert(zn and math.abs(zn.x) <= 1.5 * UPM and math.abs(zn.y + 600) < 1 and math.abs(zn.r - 1.5 * UPM) < 1
        and math.abs(zn.at - (t3 + 1000 / 2100)) < 0.03,
        "consecrating grenade: thrown into you, not drawn blowing on you as it gets there")
    -- and the grenade itself, followed with no clip seen
    local priest4 = actor(734, -1000, -600, 0, "ability_priest_flashbang", { Radius = 4.5 })
    local nade4, _, pos4 = mkproj(735, -1000, -600, 36, "particles/abilities/priest/priest_flashbang_proj.vpcf")
    local w4 = world(spell, priest4, { nade4 })
    for i = 1, 9 do
        local t = i / 60
        pos4[1], pos4[3] = -1000 + 2100 * t, 36 + 100 * t - 0.5 * G * t * t
        S.zones = {}
        step(w4)
    end
    zn = zones_of("circle")[1]
    assert(zn and math.abs(zn.x) <= 1.5 * UPM and math.abs(zn.r - 1.5 * UPM) < 1 and math.abs(zn.at - 1000 / 2100) < 0.03,
        "consecrating grenade: followed into you, not drawn blowing on you as it gets there")
end, function(spell)
    -- the grenade's model and its blast aren't the grenade
    local priest = actor(722, 3000, 0, 0, "ability_priest_flashbang", {})
    local model = mkproj(723, 3200, 0, 100, "particles/abilities/priest/priest_flashbang_proj_model.vpcf")
    local blast = mkproj(724, 3200, 0, 100, "particles/abilities/priest/priest_flashbang_explosion.vpcf")
    run(world(spell, priest, { model, blast }), 0.4)
    assert(count_groups(spell) == 0, "consecrating grenade: its model or blast taken for it")
end)

-- Gutshot: a 10 m, 60 deg fan from each of his wind-up clips, timed 0.34 s on
entry("venator_gutshot", function(spell)
    for i, clip in ipairs({ "ability_knockback_start", "ability_knockback_run_start", "ability_knockback_crouch_start",
                            "ability_knockback_crossbow_start", "ability_knockback_crossbow_crouch_start" }) do
        local priest = actor(724 + i, 7800, 0, 0, "ability_priest_knockback", { AbilityCastRange = 10, TargetingConeAngle = 60 })
        local w = world(spell, priest)
        step(w)
        X.track_animation(priest, { name = clip, duration = 0.5 })
        local t0 = S.now
        S.zones = {}
        step(w)
        local z = zones_of("cone")[1]
        assert(z and math.abs(z.at - (t0 + 0.34)) < 1e-6 and math.abs(z.r - 10 * UPM) < 1
            and math.abs(z.half - math.rad(30)) < 1e-6, "gutshot: no 10 m, 60 deg fan timed 0.34 s after " .. clip)
    end
end, function(spell)
    -- the blast's own clip and his grenade throw start nothing
    local priest = actor(730, 7800, 0, 0, "ability_priest_knockback", {})
    local w = world(spell, priest)
    step(w)
    X.track_animation(priest, { name = "ability_knockback", duration = 0.5 })
    X.track_animation(priest, { name = "ability_flashbang", duration = 0.5 })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "gutshot: drawn without its wind-up clip")
end)
end

-- run them ------------------------------------------------------------------------------------

local covered = 0
for _, f in ipairs(FIX) do
    local spell = by_id[f.id]
    S.zones = {}
    local okp, errp = pcall(f.positive, spell)
    assert(okp, f.id .. " positive: " .. tostring(errp))
    assert(#S.zones > 0, f.id .. ": drawn, but no danger area for the dodge") -- what draws is what it dodges
    local okn, errn = pcall(f.negative, spell)
    assert(okn, f.id .. " negative: " .. tostring(errn))
    covered = covered + 1
end
assert(covered == #SPELLS, ("covered %d of %d entries"):format(covered, #SPELLS))
print(("OK: %d entries detect and draw through their motion, and reject their own negative case"):format(covered))

-- Landing Marker and Trajectory only hide the drawing: Evade still gets every area, and with them and
-- the debug visuals off nothing at all is drawn. The positive cases' own asserts expect the drawing,
-- so they may fail here; only the areas and the drawing are checked
local real_line, real_tri, drew = Render.Line, Render.FilledTriangle, false
Render.Line = function(...) drew = true; return real_line(...) end
Render.FilledTriangle = function(...) drew = true; return real_tri(...) end
local quiet = { "sp_land", "sp_arc", "sp_boxes", "sp_points", "sp_labels" }
for _, k in ipairs(quiet) do switch_off[k] = true end
for _, f in ipairs(FIX) do
    S.zones, drew = {}, false
    pcall(f.positive, by_id[f.id])
    assert(#S.zones > 0, f.id .. ": Landing Marker and Trajectory off, and Evade gets no danger area")
    assert(not drew, f.id .. ": drawn with Landing Marker, Trajectory and the debug visuals off")
end
for _, k in ipairs(quiet) do switch_off[k] = nil end
Render.Line, Render.FilledTriangle = real_line, real_tri
print("OK: with the drawing switches off, nothing is drawn and every entry still gives Evade its danger area")

-- Visible Only: no spell from a caster you can't see, the game hiding him (dormant) or a wall between
-- your eyes and him. Once he has been in sight during it, it stays; off, everything is drawn
do
    local cs = by_id["talon_charged_shot"]
    local real_line = trace.line
    local function wall(on)
        trace.line = on and function() return { fraction = 0.5, hit_entity = function() return nil end } end or real_line
    end
    local n = 0
    local function shot()
        n = n + 1
        local talon = actor(500 + n, 9600, 0, 0, "ability_charged_shot", {})
        local w = world(cs, talon)
        w.t = n -- a new moment, so no earlier look at him is reused
        S.now = n
        X.track_bullet({ weapon_name = "ability_charged_shot", shooter = talon, start_pos = Vector(9600, 0, 100), direction = Vector(1, 0, 0) })
        for _, r in pairs(S.list) do if r.spell == cs and r.shot then return r, talon end end
    end
    local function zones(g)
        S.zones = {}
        D.draw_entity(g, viewer)
        return #S.zones
    end
    switch_off.sp_fog = nil
    local g = shot()
    assert(zones(g) > 0, "visible only: a caster in plain sight not drawn")
    local talon
    g, talon = shot()
    talon.is_dormant = function() return true end
    assert(zones(g) == 0, "visible only: drawn from a caster the game hides (dormant)")
    g = shot()
    wall(true)
    assert(zones(g) == 0, "visible only: drawn from a caster behind a wall")
    wall(false)
    g = shot()
    assert(zones(g) > 0, "visible only: the shot under test not drawn")
    wall(true)
    S.now = S.now + 0.5
    assert(zones(g) > 0, "visible only: a shot dropped once its caster stepped out of sight")
    -- the game's own answer (is_visible) when it gives one, over the stand-ins
    g, talon = shot()
    talon.is_visible = function() return false end
    wall(false)
    assert(zones(g) == 0, "visible only: drawn from a caster the game says isn't visible, wall or not")
    g, talon = shot()
    talon.is_visible = function() return true end
    wall(true)
    assert(zones(g) == 0, "visible only: drawn from a caster the game calls visible with a wall between you")
    g, talon = shot()
    talon.is_visible = function() return true end
    wall(false)
    assert(zones(g) > 0, "visible only: a caster visible and in line of sight not drawn")
    switch_off.sp_fog = true
    g = shot()
    assert(zones(g) > 0, "visible only: off, a caster behind a wall not drawn")
    wall(false)
end
print("OK: Visible Only: no spell from a caster you can't see; once seen it stays; off, all are drawn")

-- Dodge Arc: no spell from a caster past this angle of where your camera faces; once cast in view
-- it stays as you turn; 360 answers all around
do
    local cs = by_id["talon_charged_shot"]
    local real_utils = utils
    local function look(yaw) utils = { get_camera_angles = function() return { pitch = 0, yaw = yaw } end } end
    local n = 0
    local function shot(x)
        n = n + 1
        local talon = actor(600 + n, x, -600, 0, "ability_charged_shot", {})
        local w = world(cs, talon)
        w.t, S.now = n, n
        X.track_bullet({ weapon_name = "ability_charged_shot", shooter = talon, start_pos = Vector(x, -600, 100), direction = Vector(-1, 0, 0) })
        for _, r in pairs(S.list) do if r.spell == cs and r.shot then return r end end
    end
    local function zones(g)
        S.zones = {}
        D.draw_entity(g, viewer)
        return #S.zones
    end
    nums.sp_fov = 180
    look(0) -- facing +x; you stand at (0, -600)
    assert(zones(shot(2000)) > 0, "dodge arc: a caster in front not answered at 180")
    assert(zones(shot(-2000)) == 0, "dodge arc: a caster behind answered at 180")
    local g = shot(2000)
    assert(zones(g) > 0, "dodge arc: the shot under test not answered")
    look(180) -- turned round: he is behind you now, his shot cast in view
    assert(zones(g) > 0, "dodge arc: a shot cast in view dropped as you turned")
    -- and so does a spell the scan keeps finding: its group is built anew each scan, a bullet's is not
    local celeste = actor(650, 2000, -600, 0, "ability_unicorn_luminousstrike", { ExplosionRadius = 8 })
    local w = world(by_id["celeste_radiant_daggers"], celeste)
    look(0)
    X.track_particle({ name = "particles/abilities/unicorn/unicorn_daggers_target.vpcf", entity = celeste, index = 61 })
    X.update_particle({ index = 61, control_point = 0, position = Vector(300, -600, 0) })
    S.zones = {}
    step(w)
    assert(#S.zones > 0, "dodge arc: the scanned spell under test not answered")
    look(180)
    for _ = 1, 30 do S.zones = {}; step(w) end -- two scans on
    assert(#S.zones > 0, "dodge arc: a scanned spell cast in view dropped as you turned")
    nums.sp_fov = 360
    assert(zones(shot(2000)) > 0, "dodge arc: at 360, a caster behind not answered")
    utils = real_utils
end
print("OK: Dodge Arc: casters past its angle are ignored; a spell cast in view stays; 360 is all around")

-- Unit Collision: Grapple Arm stops on the first hero of either team, your trooper or a neutral creep
-- in its way; its lane ends there. One beside its lane, one it has passed, or one of Bebop's own
-- troopers doesn't stop it; off, it runs all the way
do
    local hook = by_id["bebop_hook"]
    local function zones_of(kind)
        local out = {}
        for _, z in ipairs(S.zones) do if z.kind == kind then out[#out + 1] = z end end
        return out
    end
    local real_same = HERO_LIB.is_same_team
    local yours = {}
    HERO_LIB.is_same_team = function(_, e) return yours[e.get_handle()] == true end
    local n = 0
    local function unit(x, y, class, mine)
        n = n + 1
        local u = mkpawn(700 + n, { x, y, 0 }, nil, { mods = {}, particles = {} })
        u.get_class_name = function() return class end
        yours[700 + n] = mine
        return u
    end
    local function lane_end(units, fired_ago, later)
        local bebop = actor(690, 0, 0, 0, "citadel_ability_hook", { AbilityCastRange = 30 })
        local w = world(hook, bebop, units)
        w.t, S.now, S.rt = 10 + n, 10 + n, 10 + n
        X.track_bullet({ weapon_name = "citadel_ability_hook", shooter = bebop, start_pos = Vector(0, 0, 40), direction = Vector(1, 0, 0) })
        local g
        for _, r in pairs(S.list) do if r.spell == hook and r.shot then g = r end end
        S.rt = S.rt + (fired_ago or 0)
        S.zones = {}
        D.draw_entity(g, viewer)
        if later then -- a frame after its flight time has carried it this much further
            S.rt, S.zones = S.rt + later, {}
            D.draw_entity(g, viewer)
        end
        local l = zones_of("lane")[1]
        return l and l.bx / UPM
    end
    switch_off.sp_collide = nil
    assert(math.abs(lane_end({}) - 30) < 0.5, "unit collision: the hook's lane not 30 m with nothing in its way")
    assert(math.abs(lane_end({ unit(10 * UPM, 0, "C_NPC_Trooper", true) }) - 10) < 0.5,
        "unit collision: the hook not stopped by your trooper 10 m along")
    assert(math.abs(lane_end({ unit(10 * UPM, 3 * UPM, "C_NPC_Trooper", true) }) - 30) < 0.5,
        "unit collision: stopped by a trooper 3 m beside its lane")
    assert(math.abs(lane_end({ unit(10 * UPM, 0, "C_NPC_Trooper", false) }) - 30) < 0.5,
        "unit collision: stopped by one of Bebop's own troopers")
    assert(math.abs(lane_end({ unit(12 * UPM, 0, "C_CitadelPlayerPawn", false) }) - 12) < 0.5,
        "unit collision: the hook not stopped by a hero of Bebop's in its way")
    assert(math.abs(lane_end({ unit(3 * UPM, 0, "C_NPC_Trooper", true) }, 0.1) - 30) < 0.5,
        "unit collision: stopped by a trooper the hook has already passed")
    -- 0.2 s on it would be 14 m along: it got to the trooper at 10 m and stopped there, the lane stays cut
    assert(math.abs(lane_end({ unit(10 * UPM, 0, "C_NPC_Trooper", true) }, 0, 0.2) - 10) < 0.5,
        "unit collision: the lane came back once the hook's flight time took it past the unit it hit")
    -- it goes through Bebop's own heroes within 7 m of him, and stops on one past that; yours it stops on
    assert(math.abs(lane_end({ unit(6 * UPM, 0, "C_CitadelPlayerPawn", false) }) - 30) < 0.5,
        "unit collision: stopped by one of Bebop's heroes 6 m in front of him")
    assert(math.abs(lane_end({ unit(8 * UPM, 0, "C_CitadelPlayerPawn", false) }) - 8) < 0.5,
        "unit collision: not stopped by one of Bebop's heroes 8 m in front of him")
    assert(math.abs(lane_end({ unit(6 * UPM, 0, "C_CitadelPlayerPawn", true) }) - 6) < 0.5,
        "unit collision: not stopped by your hero 6 m in front of him")
    -- the lane's wall trace sees walls only: a hero it meets 3 m out (the game's trace would stop
    -- on him) is Unit Collision's to judge, and off, the lane runs on past him
    local real_line = trace.line
    trace.line = function(a, b, w, x, as, os, g, keep)
        if keep and keep(unit(3 * UPM, 0, "C_CitadelPlayerPawn", true)) then return { fraction = 0.1 } end
        return { fraction = 1 }
    end
    switch_off.sp_collide = true
    assert(math.abs(lane_end({}) - 30) < 0.5, "unit collision: the lane's wall trace stopped on a hero")
    switch_off.sp_collide = nil
    trace.line = real_line
    switch_off.sp_collide = true
    assert(math.abs(lane_end({ unit(10 * UPM, 0, "C_NPC_Trooper", true) }) - 30) < 0.5,
        "unit collision: off, the hook's lane cut short")
    HERO_LIB.is_same_team = real_same
end
print("OK: Unit Collision: a hook's lane ends at the first unit it stops on; not beside, passed or Bebop's own")


-- ---- dodge: the nearest walkable spot outside the drawn areas, and move input that heads there ----
local E = require("spelldrawer_evade")
local MARGIN, CELL = 40, 40

-- a flat floor at z = 0, solid at x >= 120 (a wall far taller than a step): a down trace that starts
-- in the wall is stuck at once, a flat one that reaches it stops at its face
local WALL = 120
trace = { line = function(a, b)
    if a.z ~= b.z then
        if a.x >= WALL then return { fraction = 0 } end
        return { fraction = math.max(0, math.min(1, a.z / (a.z - b.z))) }
    end
    if b.x < WALL then return { fraction = 1 } end
    return { fraction = a.x >= WALL and 0 or (WALL - a.x) / (b.x - a.x) }
end }

local hero_pos = { 0, 0, 0 }
S.me = mkpawn(950, hero_pos, nil, { mods = {}, particles = {} })

local function dodge(zones)
    S.zones, S.dodge, S.now = zones, nil, 1000
    E.update()
    local p = S.dodge
    assert(p and p.goal, "dodge: no safe spot found")
    for i = 2, #p.path do
        local a, b = p.path[i - 1], p.path[i]
        assert(math.abs(a.i - b.i) <= 1 and math.abs(a.j - b.j) <= 1, "dodge: path skips a cell")
        assert(b.x < WALL, "dodge: path goes through the wall")
    end
    assert(p.path[1].x == hero_pos[1] and p.path[1].y == hero_pos[2], "dodge: path doesn't start on the hero")
    return p.goal, p
end

-- in a 5 m landing marker centred 2.5 m to your -x: the nearest way out is +x, but the wall is there
local traces, line = 0, trace.line
trace.line = function(...) traces = traces + 1 return line(...) end
local g, p = dodge({ { kind = "circle", x = -100, y = 0, z = 0, r = 200 } })
trace.line = line
assert(math.sqrt((g.x + 100) ^ 2 + g.y ^ 2) >= 200 + MARGIN, "dodge: safe spot inside the marker")
-- without the wall it is (160, 0); with it, the nearest spot this side of it, slid along the face
assert(g.x < WALL and math.abs(g.y) >= 150, "dodge: safe spot not beside the wall")
print(("dodge circle: safe spot (%.0f, %.0f) around the wall, %d steps, %d cells, %d traces"):format(
    g.x, g.y, #p.path - 1, #p.cells, traces))

-- no way out within reach: the search runs on the REPLAN timer, not every frame
S.zones, S.dodge, S.now = { { kind = "circle", x = 0, y = 0, z = 0, r = 2000 } }, nil, 2000 -- also runs its debug log
E.update()
local first = S.dodge
assert(first and not first.goal, "dodge: a safe spot inside a 50 m area")
S.now = 2000.05
E.update()
assert(S.dodge == first, "dodge: searched again before REPLAN with no safe spot")

-- in a lane along +x: sideways out of it, not along it
g = dodge({ { kind = "lane", x = -600, y = 0, z = 40, bx = 600, by = 0, bz = 40, r = 30 } })
assert(math.abs(g.y) >= 30 + MARGIN and math.abs(g.y) <= 30 + MARGIN + CELL and math.abs(g.x) <= CELL,
    "dodge lane: not straight out the side")

-- in a 60 degree fan aimed +x from 2.5 m behind: sideways out of the fan, not back to its apex
hero_pos[1] = 0
g = dodge({ { kind = "cone", x = -100, y = 0, z = 0, r = 400, yaw = 0, half = math.rad(30) } })
local off = math.abs(math.atan(g.y, g.x + 100))
assert(off > math.rad(30) and g.x > -100, "dodge cone: safe spot inside the fan or behind its apex")

-- a floor more than HEIGHT above isn't yours: no dodge at all
S.zones, S.dodge = { { kind = "circle", x = 0, y = 0, z = 400, r = 200 } }, nil
E.update()
assert(S.dodge == nil, "dodge: an area on another floor counted")

-- move input: looking +y (yaw 90), a path point at -x is straight to your left
dodge({ { kind = "circle", x = 0, y = 0, z = 0, r = 200 } })
S.dodge.path[2] = { x = -40, y = 0, z = 0 }
S.dodge.k = 2
-- your own hero only moves while a movement key is down (the analog values alone moved only a
-- mimicking bot): the cmd presses the keys every tick and releases the rest. You hold W
local function mkcmd(down)
    local cmd = { viewangles = { yaw = 90 }, forwardmove = 1, leftmove = 0, down = down, calls = {} }
    function cmd:get_buttons_down_mask() return self.down end
    function cmd:press(m) self.down = self.down | m; self.calls[#self.calls + 1] = "press" .. m end
    function cmd:release(m) self.down = self.down & ~m; self.calls[#self.calls + 1] = "release" .. m end
    function cmd:tap(m) self.taps = (self.taps or 0) + 1; self.tapped = m end
    return cmd
end
local function names(mask)
    local out = ""
    for _, k in ipairs({ { 8, "W" }, { 512, "A" }, { 16, "S" }, { 1024, "D" } }) do
        if mask & k[1] ~= 0 then out = out .. k[2] end
    end
    return out
end
local function steer(x, y)
    S.dodge.path[2], S.dodge.k = { x = x, y = y, z = 0 }, 2
    local cmd = mkcmd(8)
    E.steer(cmd)
    return names(cmd.down), cmd.forwardmove, cmd.leftmove, cmd
end
local keys, fm, lm, c = steer(-40, 0)
assert(keys == "A" and fm == 0 and lm == 1, ("dodge steer: %s %s/%s, wanted A 0/1"):format(keys, fm, lm))
assert(c.calls[1] == "release8" and c.calls[2] == "press512" and #c.calls == 2, "dodge steer: not release W, press A")
keys, fm, lm, c = steer(-40, 40) -- 45 degrees: forward and left together, your W kept
assert(keys == "WA" and fm == 1 and lm == 1, ("dodge steer: %s %s/%s, wanted WA 1/1"):format(keys, fm, lm))
assert(c.calls[1] == "press520" and #c.calls == 1, "dodge steer: " .. table.concat(c.calls, " ") .. ", wanted press WA")
keys = steer(-14, 40)          -- 19 degrees off forward: snaps to straight on
assert(keys == "W", "dodge steer: " .. keys .. ", wanted W")
keys = steer(0, -40)           -- behind you: your W is let go
assert(keys == "S", "dodge steer: " .. keys .. ", wanted S")

-- and the debug drawing runs over a real search
hero_pos[1], hero_pos[2] = 0, 0
dodge({ { kind = "circle", x = 0, y = 0, z = 0, r = 200 } })
clear_rec()
D.draw_dodge(S.dodge)
assert(#REC.lines > 0, "dodge visuals: nothing drawn")
print("OK: dodge finds the nearest walkable safe spot for circles, lanes and fans, and steers to it")

-- ---- Spell Simulator: registry spells cast at you, drawn like real ones, dodged by the dodge ----
-- (its own function: the main chunk is at Lua's 200-locals limit)
;(function()
local SIM = require("spelldrawer_sim")
math.randomseed(7)
ui.sp_sim.on = true
hero_pos[1], hero_pos[2] = -3000, 0 -- well clear of the wall at x >= 120
local MOVE = 300 / 60               -- units a frame: a hero's run speed at 60 fps
local DASH, DASH_FRAMES = 5 * UPM / 0.25 / 60, 15 -- units a frame, and the frames, of a 5 m, 0.25 s dash
local dash_frames = 0

-- one 60 fps frame in the game's order: the sim and the dodge plan, the drawing refills the zones,
-- the dodge steers, and with `run` the hero walks where the keys and analog values send him
local function sim_frame(run)
    S.now, S.rt = S.now + 1 / 60, S.rt + 1 / 60
    SIM.update()
    E.update()
    S.zones = {}
    clear_rec()
    for _, r in ipairs(S.sims) do D.draw_sim(r) end
    if not run then return end
    local cmd = mkcmd(0)
    E.steer(cmd)
    if cmd.tapped == 17592186044416 then dash_frames = DASH_FRAMES end -- a dash, at dash speed
    if cmd.down == 0 then return end
    -- looking +y (yaw 90): forward is +y, left is -x
    local mx, my = -cmd.leftmove, cmd.forwardmove
    local len, step = math.sqrt(mx * mx + my * my), dash_frames > 0 and DASH or MOVE
    dash_frames = dash_frames - 1
    hero_pos[1], hero_pos[2] = hero_pos[1] + mx / len * step, hero_pos[2] + my / len * step
end

-- runs `spell` cast at you to the end; whether it ever showed as a danger zone, and the verdict
local function sim_run(spell, run, after)
    local o = S.me:get_origin()
    S.sims, S.dodge = { SIM.cast(o, spell) }, nil
    local before, hits, zoned = SIM.score.dodged + SIM.score.hit, SIM.score.hit, false
    for i = 1, 900 do -- 15 s: a missed Rallying Charge runs its 600 m at 2000 u/s, 12.5 s with the charge
        sim_frame(run)
        zoned = zoned or #S.zones > 0
        if after then after(i) end
        if #S.sims == 0 then break end
    end
    assert(#S.sims == 0, "sim: " .. spell.id .. " never went off")
    assert(SIM.score.dodged + SIM.score.hit == before + 1, "sim: " .. spell.id .. " not scored once")
    return zoned, SIM.score.hit > hits
end

-- every registry spell, standing still: cast, drawn as a danger zone by the real drawing code,
-- gone off and scored
S.now, S.rt = 0, 0
for _, spell in ipairs(SPELLS) do
    local zoned = sim_run(spell)
    assert(zoned, "sim: " .. spell.id .. " cast but never drawn as a danger zone")
end
print(("OK: sim cast all %d spells, each drawn as a danger zone and scored (%d hit standing still)"):format(
    #SPELLS, SIM.score.hit))

-- simulated spells draw even with Landing Marker and Trajectory off: more than the caster pin's
-- 21 lines (its stalk and 20-segment ring)
switch_off.sp_land, switch_off.sp_arc = true, true
for _, spell in ipairs(SPELLS) do
    local drawn = false
    sim_run(spell, false, function() drawn = drawn or #REC.tris > 0 or #REC.lines > 21 end)
    assert(drawn, "sim: " .. spell.id .. " not drawn with Landing Marker and Trajectory off")
end
switch_off.sp_land, switch_off.sp_arc = nil, nil
print("OK: sim spells draw with Landing Marker and Trajectory off")

-- Blood Bomb (7 m) on you standing still is a hit; stepped 20 m away mid-flight it is dodged
local bomb = by_id["ghost_blood_bomb"]
local _, hit = sim_run(bomb)
assert(hit, "sim: a 7 m Blood Bomb on you standing still missed")
_, hit = sim_run(bomb, false, function(i) if i == 20 then hero_pos[2] = hero_pos[2] + 20 * UPM end end)
assert(not hit, "sim: Blood Bomb hit you 20 m away")

-- and the dodge takes over: Bashdown's 4 m slam 0.5 s out and its 8 m wave, at its edge 0.5 s after,
-- escaped on the dodge's own keys. Each by its own time: held to the slam's, no dash is out of the
-- wave's 8 m, and the fixture's 5 m dash ends inside it, so a hero's real one (10 m in 0.68 s)
EStatsType = { EGroundDashDistanceInMeters = 91, EGroundDashDuration = 92 }
S.me.get_scaling_stat = function(_, id) return id == 91 and 10 or id == 92 and 0.68 or nil end
DASH, DASH_FRAMES = 10 * UPM / 0.68 / 60, 41
local start = { hero_pos[1], hero_pos[2] }
-- its own seed: where the slam is aimed is random, and every spell added to the registry moved
-- the sequence on. One landing dead on you has no dash out of the wave (Fire Scarabs' turn found it)
math.randomseed(7)
_, hit = sim_run(by_id["billy_bashdown"], true)
EStatsType, S.me.get_scaling_stat = nil, nil
DASH, DASH_FRAMES = 5 * UPM / 0.25 / 60, 15
local moved = math.sqrt((hero_pos[1] - start[1]) ^ 2 + (hero_pos[2] - start[2]) ^ 2)
assert(not hit and moved > 8 * UPM - 1.5 * UPM, ("sim: the dodge didn't escape Bashdown (moved %.1f m)"):format(moved / UPM))
print(("OK: sim scores hits and dodges; the dodge dashed %.1f m out of Bashdown's slam and wave on its own"):format(moved / UPM))

-- a 3 m blast on a 0.5 s fuse: walking out takes ~0.7 s, so the dodge dashes, once, and makes it
local fuse = { id = "test_fuse", name = "Test Fuse", motion = "arc", radius = 3, duration = 0.5, gravity_scale = 0 }
start = { hero_pos[1], hero_pos[2] }
_, hit = sim_run(fuse, true)
moved = math.sqrt((hero_pos[1] - start[1]) ^ 2 + (hero_pos[2] - start[2]) ^ 2)
assert(not hit and moved > 3 * UPM - 1.5 * UPM, ("sim: the dodge didn't dash out of a 0.5 s fuse (moved %.1f m)"):format(moved / UPM))
print(("OK: sim: a 0.5 s fuse is dashed out of, %.1f m"):format(moved / UPM))

-- a cast comes out already in its first frame: Malice's wind-up delay is there to draw at once
local r = SIM.cast(S.me:get_origin(), by_id["ghost_malice"])
assert(r.mod and r.pos and r.fires_at and math.abs(r.fires_at - S.now - 0.12) < 1e-6, "sim: a cast's first frame drawn without its wind-up")
-- the Interval setting: one spell cast and scored, the next only Interval after it is over
nums.sp_sim_gap = 2
S.sims = {}
S.rt = S.rt + 100 -- past any wait left from before
local scored = SIM.score.dodged + SIM.score.hit + SIM.score.countered
SIM.update()
assert(#S.sims == 1, "sim: cast " .. #S.sims .. " spells, wanted one")
local over
for i = 1, 600 do
    S.now, S.rt = S.now + 1 / 60, S.rt + 1 / 60
    SIM.update()
    if #S.sims == 0 then over = S.rt break end
end
assert(over and SIM.score.dodged + SIM.score.hit + SIM.score.countered == scored + 1, "sim: the spell not scored")
while S.rt < over + 1.9 do
    S.now, S.rt = S.now + 1 / 60, S.rt + 1 / 60
    SIM.update()
    assert(#S.sims == 0, "sim: next spell cast before its 2 s interval")
end
local cast -- seen in any of these frames: a quick one (Soul Exchange, 0.1 s) is over again by the last
for _ = 1, 12 do
    S.now, S.rt = S.now + 1 / 60, S.rt + 1 / 60
    SIM.update()
    cast = cast or #S.sims == 1
end
assert(cast, "sim: next spell not cast after its interval")
S.sims, nums.sp_sim_gap = {}, 1.5
print("OK: sim: the next spell is cast an Interval after the last is over")

-- Shining Wonder winds up 0.75 s before the orb flies: in that time the dodge walks out of its lane
for _ = 1, 3 do
    _, hit = sim_run(by_id["celeste_shining_wonder"], true)
    assert(not hit, "sim: Shining Wonder hit through its 0.75 s wind-up")
end
print("OK: sim: Shining Wonder's wind-up is walked out of before the orb flies")

-- Grasping Hands laid across you: walked off before its hands pop, 1.1 s on
for _ = 1, 3 do
    _, hit = sim_run(by_id["graves_grasping_hands"], true)
    assert(not hit, "sim: Grasping Hands not walked off before its hands popped")
end
print("OK: sim: a wall of Grasping Hands laid on you is walked off before its hands pop")

-- an Uppercut cast from between you and the camera, its caster off screen: the fan is still filled,
-- in rings out from him, not only its rim (fan() fills from the centre, which didn't project)
local cut = SIM.cast(S.me:get_origin(), by_id["bebop_exploding_uppercut"])
local w2s = Render.WorldToScreen
-- off screen behind the camera, as the game gives it: nowhere near the screen (probed 2026-11-11)
local function behind() return Vec2(-3e7, -3e7), false end
Render.WorldToScreen = function(v)
    if (v.x - cut.from.x) ^ 2 + (v.y - cut.from.y) ^ 2 <= 60 ^ 2 then return behind() end
    return w2s(v)
end
S.zones = {}
clear_rec()
D.draw_sim(cut)
Render.WorldToScreen = w2s
assert(#REC.tris > 100, "sim: a cone with its caster off screen not filled (" .. #REC.tris .. " triangles)")
print(("OK: a cone whose caster is off screen is still filled (%d triangles)"):format(#REC.tris))
-- and the other way round: a Sand Blast whose caster is on screen and whose far edge, out past
-- you, is not. It was only outlined: fan() fills between edge points, and it had none
local sand = SIM.cast(S.me:get_origin(), by_id["krill_sand_blast"])
local function far(v) return (v.x - sand.from.x) ^ 2 + (v.y - sand.from.y) ^ 2 >= (10 * UPM) ^ 2 end
Render.WorldToScreen = function(v)
    if far(v) then return behind() end
    return w2s(v)
end
S.zones = {}
clear_rec()
D.draw_sim(sand)
assert(#REC.tris > 100, "sim: a cone with its far edge off screen not filled (" .. #REC.tris .. " triangles)")
print(("OK: a cone whose far edge is off screen is still filled (%d triangles)"):format(#REC.tris))
-- off screen but in front of the camera, a point has a place just past the screen's edge: the pieces
-- that reach it are drawn, for the renderer to clip, where they were dropped and the fan cut short
local cut_short = #REC.tris
Render.WorldToScreen = function(v)
    local s = w2s(v)
    if far(v) then return Vec2(s.x % 4000, s.y % 4000), false end -- within OFF_SCREEN of the screen
    return s, true
end
S.zones = {}
clear_rec()
D.draw_sim(sand)
Render.WorldToScreen = w2s
assert(#REC.tris > cut_short, ("a fan running past the screen's edge still cut short there (%d triangles, %d cut)"):format(#REC.tris, cut_short))
print(("OK: a fan running past the screen's edge is drawn up to it (%d triangles, %d when cut short)"):format(#REC.tris, cut_short))
ui.sp_sim.on = false
end)()

-- ---- walk, dash or nothing, by when the area hits you (walking 7 m/s, a 5 m dash in 0.25 s) ----
;(function()
hero_pos[1], hero_pos[2] = -3000, 0
local stamina = 2
HERO_LIB.get_stamina = function() return stamina end
HERO_LIB.is_on_ground = function() return true end
local function plan(zones)
    S.zones, S.dodge, S.now, S.parry = zones, nil, 5000, nil -- a fresh decision: no parry left up from the last
    E.update()
    return S.dodge
end
local function blast(r, t) return { { kind = "circle", x = -3000, y = 0, z = 0, r = r, at = 5000 + t } } end
local function off(p) return math.sqrt((p.x + 3000) ^ 2 + p.y ^ 2) end

local p = plan(blast(200, 2)) -- 5 m, 2 s out: ~0.9 s of walking does it
assert(p.mode == "walk", "decide: walk, got " .. tostring(p.mode))
-- Dodge Only Dangerous held: that blast, with no danger level, is left alone; one of level 4 is dodged
ui.sp_danger_only.down = true
assert(plan(blast(200, 2)) == nil, "Dodge Only Dangerous: dodged a spell with no danger level")
local dire = blast(200, 2)
dire[1].danger = 4
assert(plan(dire).mode == "walk", "Dodge Only Dangerous: a danger 4 spell not dodged")
-- a danger 3 spell counts as dangerous at 35% health or less
dire[1].danger = 3
HERO_LIB.get_health_percent = function() return 0.5 end
assert(plan(dire) == nil, "low health: a danger 3 spell counted as dangerous at half health")
HERO_LIB.get_health_percent = function() return 0.35 end
assert(plan(dire).mode == "walk", "low health: a danger 3 spell not counted as dangerous at 35% health")
dire[1].danger = 2
assert(plan(dire) == nil, "low health: a danger 2 spell counted as dangerous")
-- a spell's own level for low health (`low_danger`: Itani Lo Sahn's mark) counts then, and only then
dire[1].low_danger = 5
assert(plan(dire).mode == "walk", "low health: a spell's low_danger not counted at 35% health")
HERO_LIB.get_health_percent = function() return 0.5 end
assert(plan(dire) == nil, "low health: a spell's low_danger counted at half health")
HERO_LIB.get_health_percent = nil
ui.sp_danger_only.down = false
-- a Lightning Ball sitting on you (`around`): its lane's hit is not due now, its untimed ring is the
-- danger, so out of it rather than a parry that only holds its zap off 0.8 s
local r = 4.25 * UPM
local ball = { { kind = "lane", x = -3400, y = 0, z = 36, bx = 3000, by = 0, bz = 36, r = r, px = -3000, py = 0,
    speed = 1700, around = true }, { kind = "circle", x = -3000, y = 0, z = 36, r = r } }
p = plan(ball)
assert(p.mode == "walk" or p.mode == "dash", "a ball on you: not walked or dashed out of, got " .. tostring(p.mode))
ball[1].around = nil
p = plan(ball)
assert(p.mode ~= "walk" and p.mode ~= "dash", "a ball on you: the plain lane's hit due now read as left in time")
p = plan(blast(118, 0.45))    -- 3 m, 0.45 s out: walking takes ~0.7 s, a dash 0.35 s
assert(p.mode == "dash" and off(p.dash) >= 118 + 40, "decide: dash clear of a 3 m blast, got " .. tostring(p.mode))
stamina = 0
p = plan(blast(118, 0.45))
assert(p.mode == "none" and p.why:find("no stamina", 1, true), "decide: dashed with no stamina")
stamina = 2
-- Tuning: a 0.3 s Reaction Time makes the same dash too late; a 2 m Safety Margin walks further out
nums.sp_react = 0.3
p = plan(blast(118, 0.45))
assert(p.mode == "none" and p.why:find("gets out in", 1, true), "tuning: Reaction Time not added to the dash")
-- and no lower than 0.1 s, the slider's floor: a setting saved at 0 broke the dodge, and plans as 0.1
nums.sp_react = 0.1
local floor = plan(blast(118, 0.45)).dash.time
nums.sp_react = 0
assert(plan(blast(118, 0.45)).dash.time == floor, "tuning: a Reaction Time of 0 not held to its 0.1 s floor")
nums.sp_react, nums.sp_margin = nil, 2
p = plan(blast(118, 2))
assert(p.mode == "walk" and off(p.goal) >= 118 + 2 * UPM - 20, "tuning: Safety Margin not kept, got " .. off(p.goal))
nums.sp_margin = nil
-- Path Refresh: the walk is searched again after it (0.15 s by default), not before. At 0.5 s, the
-- plan made 0.2 s ago still stands
p = plan(blast(200, 2))
S.now = S.now + 0.2
E.update()
assert(S.dodge ~= p, "path refresh: the walk not searched again 0.2 s on at the default 0.15 s")
nums.sp_replan = 0.5
p = plan(blast(200, 2))
S.now = S.now + 0.2
E.update()
assert(S.dodge == p, "path refresh: the walk searched again 0.2 s on at 0.5 s")
nums.sp_replan = nil
-- Dodge Interval: once a dodge ends, a new one waits it out (0.1 s here); after it, one starts
nums.sp_dodge_gap = 0.1
p = plan(blast(200, 2))
assert(p and p.mode == "walk", "dodge interval: the first dodge not made")
S.zones = {}
E.update() -- clear of it: the dodge ends
assert(S.dodge == nil, "dodge interval: the dodge not ended once clear")
S.zones, S.now = blast(200, 2), S.now + 0.05
E.update()
assert(S.dodge == nil, "dodge interval: a new dodge 0.05 s after the last ended")
S.now = S.now + 0.06
E.update()
assert(S.dodge and S.dodge.mode == "walk", "dodge interval: no new dodge 0.11 s after the last ended")
-- the clock restarts on a new map: a dodge's end and a parry kept from the last one hold nothing off
S.zones = {}
E.update()
local last_map = S.now
S.parry = { from = last_map - 1, to = last_map + 0.6 }
S.zones, S.now = blast(200, 2), 10
E.update()
assert(S.dodge and S.dodge.mode == "walk" and S.parry == nil, "clock restart: the last map's times held the dodge off")
S.now, S.dodge = last_map + 1, nil
nums.sp_dodge_gap = 0
p = plan(blast(118, 0.2))     -- 0.2 s out: even a dash is too slow
assert(p.mode == "none", "decide: tried to beat a 0.2 s blast")
p = plan(blast(276, 0.45))    -- 7 m, 0.45 s: a 5 m dash still ends inside it
assert(p.mode == "none" and p.why:find("ends clear", 1, true), "decide: dashed into the same blast")
-- in the air: the air dash (8 m in 0.47 s), level at your height with no floor under its end, and
-- before a walk, whose speed doesn't hold there; with no stamina the walk is still taken
HERO_LIB.is_on_ground = function() return false end
p = plan(blast(118, 0.45))
assert(p.mode == "dash" and p.dash.air and math.abs(p.dash.dur - 0.47) < 1e-6 and math.abs(off(p.dash) - 8 * UPM) < 1
    and p.dash.z == S.me:get_origin().z, "air: not air-dashed 8 m out of a 3 m blast, got " .. tostring(p.mode))
p = plan(blast(236, 0.6)) -- 6 m: the 8 m air dash ends clear of it and its margin, the fixture's 5 m ground one wouldn't
assert(p.mode == "dash" and p.dash.air, "air: no 8 m air dash out of a 6 m blast, got " .. tostring(p.mode))
HERO_LIB.is_on_ground = function() return true end
assert(plan(blast(236, 0.6)).mode ~= "dash", "air: the 5 m ground dash cleared a 6 m blast, so the case above shows nothing")
HERO_LIB.is_on_ground = function() return false end
p = plan(blast(200, 2))
assert(p.mode == "dash" and p.dash.air, "air: walked in the air where an air dash makes it, got " .. tostring(p.mode))
stamina = 0
p = plan(blast(200, 2))
assert(p.mode == "walk", "air: with no stamina, no walk taken, got " .. tostring(p.mode))
stamina = 2
HERO_LIB.is_on_ground = function() return true end
-- a parry up against an area with no hit time (Singularity's pull, all channel): it takes you as
-- the parry ends, so the way out is planned to beat that, a dash where walking is too slow, and
-- no second parry. Standing still through the parry, 5 of 5 were pulled as it ran out
EStatsType = { EGroundDashDistanceInMeters = 91, EGroundDashDuration = 92 }
S.me.get_scaling_stat = function(_, id) return id == 91 and 10 or id == 92 and 0.68 or nil end
local pull = { kind = "circle", x = -3000, y = 0, z = 0, r = 197 } -- 5 m round you, untimed
S.parry = { from = 5000, to = 5000.6 }
S.zones, S.now = { pull }, 5000
S.dodge = { parried = true, parry_until = 5000.6, at = 4999.7, t = 0.2, mode = "counterspell", targeted = false } -- tapped before the pull
E.update()
p = S.dodge
assert(p.mode == "dash" and p.dash.time <= 0.6, "parry: not dashed out of an area that outlasts it, got " .. tostring(p.mode))
assert(not p.dash.late, "parry: a dash out in time marked late")
-- with too little of it left for any dash to be out in time, the soonest still goes: staying is sure
-- to be caught. 3 of 8 Singularity casts took you after one was called 0.01-0.07 s late, none tried
S.parry = { from = 5000, to = 5000.2 }
S.zones = { { kind = "circle", x = -3000, y = 0, z = 0, r = 197 } }
S.dodge = { parried = true, parry_until = 5000.2, at = 4999.7, t = 0.2, mode = "counterspell" }
E.update()
p = S.dodge
assert(p.mode == "dash" and p.dash.late, "parry: no late dash where staying is sure to be caught, got " .. tostring(p.mode))
-- but what hits while the parry holds is blocked by it, whatever plan stands: the frame between Kinetic
-- Pulse's wind-up and its wave dropped the parry's plan, and each parried wave was then dashed from
S.parry = { from = 5000, to = 5000.6 }
S.zones, S.dodge = blast(118, 0.05), nil
E.update()
assert(S.dodge == nil, "parry: planned against a hit the parry holding blocks, got " .. tostring(S.dodge and S.dodge.mode))
S.parry = nil
p = plan({ { kind = "circle", x = -3000, y = 0, z = 0, r = 197 } }) -- areas are drawn anew each frame
assert(p.mode == "walk", "parry: without one, an untimed area not walked out of, got " .. tostring(p.mode))
-- Block Movement with Circles unticked: a lingering trap (Spirit Snare) that lands on you is still
-- walked out of; one you stood clear of and then walked into yourself is let be
guard_off.Circles = true
local function snare() return { { kind = "circle", x = -3000, y = 600, z = 0, r = 255 } } end
p = plan(snare()) -- a fresh one 15 m off: clear of it
assert(p == nil, "movement guard: a snare 15 m off planned against")
hero_pos[2] = 500 -- walked in, 2.5 m from its middle
p = plan(snare())
assert(p == nil, "movement guard: walked into a snare yourself, still dodged, got " .. tostring(p and p.mode))
hero_pos[2] = 0
p = plan({ { kind = "circle", x = -3000, y = 0, z = 0, r = 255 } }) -- a second one, on you
assert(p and p.mode == "walk", "movement guard: a snare landing on you not walked out of, got " .. tostring(p and p.mode))
p = plan({ { kind = "circle", x = -3000, y = 0, z = 0, r = 255, at = 5002 } })
assert(p and p.mode == "walk", "movement guard: a timed blast with Circles unticked not walked out of")
-- a ring shown well ahead (Burrow's `prepare` 0.75 s): let be until then, dodged from then on
local function burrow(dt) return { { kind = "circle", x = -3000, y = 0, z = 0, r = 216, at = S.now + dt, prep = 0.75 } } end
p = plan(burrow(1.9))
assert(p == nil, "movement guard: Burrow's ring dodged 1.9 s early with Circles unticked, got " .. tostring(p and p.mode))
p = plan(burrow(0.7))
assert(p and p.mode ~= "none", "movement guard: Burrow's ring not dodged 0.7 s before he is up, got " .. tostring(p and p.mode))
guard_off.Circles = nil
p = plan(burrow(1.9))
assert(p and p.mode == "walk", "movement guard: Burrow's ring not walked out of early with Circles ticked")
guard_off.Circles = true
-- a ring too big to walk out of (Concussive Combustion's `big`) with Circles unticked: only parried
-- while you stand in it, never walked from; outside it, nothing
local function combustion(x) return { { kind = "circle", x = x, y = 0, z = 0, r = 12 * UPM, at = 5003.25, big = true } } end
p = plan(combustion(-3000))
assert(p and p.targeted and not p.path, "big area: walked from with Circles unticked, got " .. tostring(p and p.mode))
assert(plan(combustion(-3000 + 30 * UPM)) == nil, "big area: planned against from outside it")
guard_off.Circles = nil
-- with Circles ticked it is an area like any other: walked out of
p = plan(combustion(-3000))
assert(p and p.mode == "walk" and not p.targeted, "big area: not walked out of with Circles ticked, got " .. tostring(p and p.mode))
EStatsType, S.me.get_scaling_stat = nil, nil
-- a shot already past you is no danger; one 20 m off at 1000 u/s (0.8 s) is walked out of sideways
assert(plan({ { kind = "lane", x = -3600, y = 0, z = 40, bx = -2400, by = 0, bz = 40, r = 30,
                px = -2600, py = 0, speed = 3000 } }) == nil, "decide: dodged a shot that went past")
p = plan({ { kind = "lane", x = -3800, y = 0, z = 40, bx = -2200, by = 0, bz = 40, r = 30,
             px = -3787, py = 0, speed = 1000 } })
assert(p.mode == "walk" and math.abs(p.goal.y) >= 70 and math.abs(p.goal.x + 3000) <= 40, "decide: not sideways out of the shot")
-- a shot still winding up: 0.6 s before Shining Wonder leaves, 10 m off at 1820 u/s, is walked out
-- of sideways; the same shot already flying (0.22 s) is beyond walking and dashing both
local orb = { kind = "lane", x = -3394, y = 0, z = 40, bx = -2200, by = 0, bz = 40, r = 65, px = -3394, py = 0, speed = 1820 }
orb.delay = 0.6
p = plan({ orb })
assert(p.mode == "walk", "decide: a winding-up shot not walked out of, got " .. tostring(p.mode))
orb.delay = nil
p = plan({ orb })
assert(p.mode == "none", "decide: a flying shot 0.22 s off taken for escapable, got " .. tostring(p.mode))
-- the guard: standing clear, 2 m from a lane whose shot is still coming (looking +y, yaw 90, so W
-- walks +y into it, W+A half as fast). W is let go; of W+A, A (along the edge) is kept; S, away
-- from it, is left be; a lane whose shot is already past you doesn't stop you
local lane = { kind = "lane", x = -3600, y = 80, z = 40, bx = -2400, by = 80, bz = 40, r = 30, px = -3600, py = 80, speed = 1820 }
assert(plan({ lane }) == nil, "guard: standing clear counted as in danger")
local function guarded(down)
    local c = mkcmd(down)
    c.forwardmove, c.leftmove = 0, 0
    E.steer(c)
    return c
end
local g1 = guarded(8)
assert(g1.down == 0 and g1.forwardmove == 0 and g1.calls[1] == "release8", "guard: W walked you into the lane")
local g2 = guarded(8 | 512)
assert(g2.down == 512 and g2.forwardmove == 0 and g2.leftmove == 1, "guard: W+A not cut to A along the edge")
local g3 = guarded(16)
assert(g3.down == 16 and #g3.calls == 0, "guard: held back S, which walks away from the lane")
guard_off.Lines = true
assert(guarded(8).down == 8, "guard: Lines unticked, a lane still blocked W")
-- and the dodge leaves a lane or cone you walked into yourself be; one turned onto you is still left
assert(plan({ lane }) == nil, "movement guard: standing clear of the lane counted as in danger")
hero_pos[2] = 60
assert(plan({ lane }) == nil, "movement guard: Lines unticked, walked into a lane yourself, still dodged")
hero_pos[2] = 0
plan({ lane })
lane.y, lane.by, lane.py = 0, 0, 0 -- its caster turned it onto you
p = plan({ lane })
assert(p and p.mode ~= nil, "movement guard: Lines unticked, a lane turned onto you not planned against")
lane.y, lane.by, lane.py = 80, 80, 80
guard_off.Lines, guard_off.Cones = nil, true
local function fan() return { { kind = "cone", x = -3400, y = 0, z = 0, r = 300, yaw = 0, half = 0.5, at = 5002 } } end
assert(plan(fan()) == nil, "movement guard: standing clear of a cone counted as in danger")
hero_pos[1] = -3200
assert(plan(fan()) == nil, "movement guard: Cones unticked, walked into a cone yourself, still dodged")
guard_off.Cones = nil
p = plan(fan())
assert(p and p.mode ~= nil, "movement guard: Cones ticked, standing in a cone not planned against")
hero_pos[1] = -3000
plan({}) -- a frame standing clear: where you stood last frame is here again
lane.px = -2500 -- the shot is 5 m past you
assert(guarded(8).down == 8, "guard: a shot already past you still blocked W")
-- no input when there's no escape, one dash tap when there is
p = plan(blast(118, 0.2))
local cmd = mkcmd(0)
E.steer(cmd)
assert(#cmd.calls == 0 and not cmd.taps, "decide: sent input with no escape")
p = plan(blast(118, 0.45))
cmd = mkcmd(0)
E.steer(cmd) -- the direction keys first, so the dash goes their way
assert(not cmd.taps and cmd.down ~= 0, "decide: dash tapped before its direction keys were down")
local aim = cmd.down
cmd = mkcmd(aim)
E.steer(cmd)
assert(cmd.taps == 1 and cmd.tapped == 17592186044416 and cmd.down == aim, "decide: dash not tapped with its direction")
E.update()
assert(S.dodge == p, "decide: replanned mid-dash")
cmd = mkcmd(0)
E.steer(cmd)
assert(not cmd.taps and cmd.down ~= 0, "decide: dash tapped twice")
-- nor is the dash's plan dropped when its area leaves you for a frame (a lane turning with its
-- caster): the plan that came after tapped the dash again
S.zones = {}
E.update()
assert(S.dodge == p, "decide: a dash's plan dropped when its area left you")
-- a lane that turns with its caster replans every frame: the dash still goes on the second command,
-- its direction keys down since the first, though a new plan stands in for the one that aimed it
p = plan(blast(118, 0.45))
cmd = mkcmd(0)
E.steer(cmd)
aim = cmd.down
p = plan(blast(118, 0.45))
cmd = mkcmd(aim)
E.steer(cmd)
assert(cmd.taps == 1 and cmd.down == aim, "decide: a replanned dash never tapped")
-- a dash that didn't go (a parry roots you: 0.0 m, twice) is tapped again once its check finds you
-- not dashing, not waited out for its whole length; one that went is left to run
local real_dashing = HERO_LIB.is_any_dashing
local dashing = true
HERO_LIB.is_any_dashing = function() return dashing end
S.rt = S.rt + 0.16
E.update()
assert(S.dodge == p and p.dashed, "decide: a dash that went was planned again")
p = plan(blast(118, 0.45))
local c1 = mkcmd(0)
E.steer(c1)
cmd = mkcmd(c1.down)
E.steer(cmd)
assert((c1.taps or 0) + (cmd.taps or 0) == 1, "decide: the dash under test not tapped")
dashing = false
S.zones, S.rt = blast(118, 0.45), S.rt + 0.16
E.update()
cmd = mkcmd(cmd.down)
E.steer(cmd)
assert(cmd.taps == 1 and S.dodge.dashed, "decide: a dash that didn't go not tapped again")
HERO_LIB.is_any_dashing = real_dashing
-- an area he can let go on any moment (`urgent`, Apollo's charge once he can release): out the
-- fastest way, a dash, where the same untimed lane is only walked out of; with no stamina, walked
local hold = { kind = "lane", x = -3600, y = 0, z = 40, bx = -2400, by = 0, bz = 40, r = 63 }
p = plan({ hold })
assert(p.mode == "walk", "urgent: an untimed lane not walked out of, got " .. tostring(p.mode))
hold.urgent = true
p = plan({ hold })
assert(p.mode == "dash", "urgent: not dashed out of, got " .. tostring(p.mode))
stamina = 0
p = plan({ hold })
assert(p.mode == "walk", "urgent: not walked out of with no stamina, got " .. tostring(p.mode))
stamina = 2
-- stats as the game reads them: move speed in units/s (~275, not m/s), a 0.72 s dash. A 3 m blast
-- 0.5 s out: walking takes ~0.68 s. A dash at 20 m/s is out in ~0.3 s; with no dash speed read, the
-- dash only averages 5 m / 0.72 s, as slow as walking, and nothing is sent
local stats = { [7] = 275, [91] = 5, [92] = 0.72, [95] = 20 }
EStatsType = { EMaxMoveSpeed = 7, EGroundDashDistanceInMeters = 91, EGroundDashDuration = 92, EDashSpeedInMeters = 95 }
S.me.get_scaling_stat = function(_, id) return stats[id] end
p = plan(blast(118, 0.5))
assert(p.mode == "dash" and p.walk > 0.6 and p.dash.time < 0.4,
    ("decide: in-game stats, got %s (walk %.2f s)"):format(tostring(p.mode), p.walk or -1))
stats[95] = nil
p = plan(blast(118, 0.5))
assert(p.mode == "none" and p.why:find("gets out in", 1, true), "decide: a 0.72 s average dash taken for a fast one")
EStatsType, S.me.get_scaling_stat = nil, nil

-- An evade spell (Mina's Sanguine Retreat, 0.06 s to fly): with no walk or dash out and the hit after
-- its flight starts, it is cast at a clear spot, aimed silently, pressed once and left to run
do
    local retreat = { get_name = function() return "ability_vampirebat_batblink" end }
    local was_ready, was_cast, casts, aimed = HERO_LIB.is_ability_ready, HERO_LIB.cast_ability, 0, nil
    S.me.get_abilities = function() return { retreat } end
    HERO_LIB.is_ability_ready = function() return true end
    HERO_LIB.cast_ability = function(_, _, ab) casts = casts + (ab == retreat and 1 or 0) end
    local function later(t) -- a 7 m blast `t` off, at a time no ability lookup is kept from
        S.zones, S.dodge, S.now, S.parry = { { kind = "circle", x = -3000, y = 0, z = 0, r = 276, at = 5010 + t } }, nil, 5010, nil
        E.update()
        return S.dodge
    end
    stamina = 0
    p = later(0.03)
    assert(p.mode ~= "spell" and p.why:find("flies in", 1, true), "evade spell: cast at a hit due before it flies: " .. tostring(p.why))
    local card = require("spelldrawer_util").EVADE_SPELLS[1]
    card.ui = { Get = function(_, name) return name ~= "Sanguine Retreat" end }
    assert(later(1.0).mode ~= "spell", "evade spell: cast with it unticked in the Escape Spells card")
    card.ui = nil
    card.danger = 4 -- kept for spells of danger 4 or more: this blast has no level
    p = later(1.0)
    assert(p.mode ~= "spell" and p.why:find("kept for danger 4+", 1, true), "evade spell: cast under its danger floor: " .. tostring(p.why))
    S.zones[1].danger = 4
    S.dodge = nil
    E.update()
    assert(S.dodge.mode == "spell", "evade spell: not cast at its danger floor")
    card.danger = nil
    p = later(1.0) -- walking 7 m takes ~1.25 s
    assert(p.mode == "spell" and off(p.spell) > 276 + 40 and off(p.spell) <= 9 * UPM,
        "evade spell: not cast at a clear spot in range, got " .. tostring(p.mode))
    local c = mkcmd(8) -- you hold W
    function c:aim(opt) aimed = opt; opt.on_aimed_callback() return 3 end
    E.steer(c)
    E.steer(c)
    assert(casts == 1 and aimed.ability_ent == retreat and aimed.aim_type == 2 and aimed.aim_pos.x == p.spell.x
        and c.down == 8 and #c.calls == 0, "evade spell: not pressed once, aimed silently at its spot, your keys left alone")
    S.now = S.now + 0.5
    E.update()
    assert(S.dodge == p, "evade spell: replanned during its cast and flight")
    S.now = S.now + 0.5
    E.update()
    assert(S.dodge ~= p, "evade spell: its plan kept after the flight")
    -- a spell cast at you, 2 s off: not pressed until the hit is Parry Lead (0.25 s) into its flight
    S.zones, S.dodge, S.now = { { kind = "target", x = -3000, y = 0, z = 0, r = 40, at = 5022 } }, nil, 5020
    E.update()
    p = S.dodge
    assert(p.targeted and p.mode == "spell" and off(p.spell) > 0, "evade spell: not planned against a spell cast at you, got " .. tostring(p.mode))
    casts = 0
    E.steer(c)
    assert(casts == 0, "evade spell: pressed 2 s before a spell cast at you hits")
    S.now = 5021.6
    E.steer(c)
    assert(casts == 0, "evade spell: pressed 0.4 s before the hit, sooner than Parry Lead into its flight")
    S.now = 5021.75
    E.steer(c)
    E.steer(c)
    assert(casts == 1, "evade spell: not pressed once 0.25 s before a spell cast at you hits")
    -- one that blocks (Apollo's Riposte, a 0.3 s window): stood in, pressed 0.19 s before the hit, not aimed
    local riposte = { get_name = function() return "ability_fencer_riposte" end }
    S.me.get_abilities = function() return { riposte } end
    HERO_LIB.cast_ability = function(_, _, ab) casts = casts + (ab == riposte and 1 or 0) end
    S.zones, S.dodge, S.now, S.parry = { { kind = "circle", x = -3000, y = 0, z = 0, r = 276, at = 5031 } }, nil, 5030, nil
    E.update()
    p = S.dodge
    assert(p.mode == "spell" and p.spell.block and not p.goal, "blocking spell: not planned with no walk or dash out, got " .. tostring(p.mode))
    casts, aimed = 0, nil
    E.steer(c)
    assert(casts == 0, "blocking spell: pressed 1 s before the hit, outside its window")
    S.now = 5030.85
    E.steer(c)
    E.steer(c)
    assert(casts == 1 and not aimed, "blocking spell: not pressed once, unaimed, 0.15 s before the hit")
    -- Dynamo's Quantum Entanglement: a blink whose key is followed by left clicks (IN_ATTACK, 1),
    -- which take only you
    local quantum = { get_name = function() return "citadel_ability_void_sphere" end }
    S.me.get_abilities = function() return { quantum } end
    HERO_LIB.cast_ability = function(_, _, ab) casts = casts + (ab == quantum and 1 or 0) end
    casts = 0
    S.zones, S.dodge, S.now, S.parry = { { kind = "circle", x = -3000, y = 0, z = 0, r = 276, at = 5041 } }, nil, 5040, nil
    E.update()
    E.steer(c)
    assert(S.dodge.mode == "spell" and aimed and aimed.ability_ent == quantum and casts == 1 and #c.calls == 0,
        "evade spell: Quantum Entanglement's key not pressed alone first, got " .. tostring(S.dodge.mode))
    E.steer(c)
    E.steer(c)
    E.steer(c)
    assert(casts == 1 and #c.calls == 2 and c.calls[2] == "press1",
        "evade spell: Quantum Entanglement not confirmed with a left click on every other command")
    -- Yamato's Shadow Transformation: kept for danger 5, and timed to a spell cast at you too
    local shadow = { get_name = function() return "citadel_ability_infinity_slash" end }
    S.me.get_abilities = function() return { shadow } end
    HERO_LIB.cast_ability = function(_, _, ab) casts = casts + (ab == shadow and 1 or 0) end
    local function at_you(danger, now) -- a spell cast at you, 1 s off
        S.zones, S.dodge, S.now, S.parry = { { kind = "target", x = -3000, y = 0, z = 0, r = 40, at = now + 1,
            danger = danger } }, nil, now, nil
        E.update()
        return S.dodge
    end
    assert(at_you(4, 5050).mode ~= "spell", "Shadow Transformation: planned against a danger 4 spell cast at you")
    p = at_you(5, 5060)
    assert(p.mode == "spell" and p.spell.block, "Shadow Transformation: not planned against a danger 5 spell cast at you, got " .. tostring(p.mode))
    casts = 0
    E.steer(c)
    assert(casts == 0, "Shadow Transformation: pressed 1 s before the hit")
    S.now = 5060.7
    E.steer(c)
    E.steer(c)
    assert(casts == 1, "Shadow Transformation: not pressed once 0.3 s before the hit")
    -- Vindicta's Flight: against an area of danger 4 or more whose hit leaves it time to climb
    -- (0.37 s), pressed at once, unaimed; never while it is up or against a spell cast at you
    local flight = { get_name = function() return "citadel_ability_hornet_leap" end }
    S.me.get_abilities = function() return { flight } end
    HERO_LIB.cast_ability = function(_, _, ab) casts = casts + (ab == flight and 1 or 0) end
    local function area(danger, now, t) -- a 7 m blast `t` off
        S.zones, S.dodge, S.now, S.parry = { { kind = "circle", x = -3000, y = 0, z = 0, r = 276, at = now + t,
            danger = danger } }, nil, now, nil
        E.update()
        return S.dodge
    end
    assert(area(3, 5065, 1).mode ~= "spell", "Flight: planned against a danger 3 spell")
    p = area(4, 5070, 0.3)
    assert(p.mode ~= "spell" and p.why:find("too late for Flight", 1, true), "Flight: planned with too little time to climb: " .. tostring(p.why))
    p = area(4, 5075, 0.5)
    assert(p.mode == "spell" and p.spell.up and not p.goal, "Flight: not planned against a danger 4 area 0.5 s off, got " .. tostring(p.mode))
    casts, aimed = 0, nil
    function c:aim(opt) aimed = opt end
    E.steer(c)
    E.steer(c)
    assert(casts == 1 and not aimed, "Flight: not pressed once at once, unaimed")
    S.me.get_modifiers = function() return { { get_name = function() return "citadel_ability_hornet_leap/modifier_hornet_leap" end } } end
    assert(area(5, 5080, 0.5).mode ~= "spell", "Flight: pressed again while it is up, which would end it")
    S.me.get_modifiers = nil
    assert(at_you(5, 5085).mode ~= "spell", "Flight: planned against a spell cast at you")
    -- Warp Stone, an item: tried after your hero's own escape, aimed silently, never against a
    -- spell cast at you
    local stone = { get_name = function() return "upgrade_warp_stone" end }
    S.me.get_abilities = function() return { shadow, stone } end
    HERO_LIB.cast_ability = function(_, _, ab) casts = casts + (ab == stone and 1 or 0) end
    S.zones, S.dodge, S.now, S.parry = { { kind = "circle", x = -3000, y = 0, z = 0, r = 276, at = 5091 } }, nil, 5090, nil
    E.update()
    p = S.dodge
    assert(p.mode == "spell" and p.spell.name == "Warp Stone" and off(p.spell) > 13 * UPM and off(p.spell) <= 13.7 * UPM + 1,
        "Warp Stone: not cast at a clear spot once the hero's escape (kept for danger 5) is ruled out, got " .. tostring(p.mode))
    casts, aimed = 0, nil
    function c:aim(opt) aimed = opt; opt.on_aimed_callback() return 3 end
    E.steer(c)
    assert(casts == 1 and aimed.ability_ent == stone and aimed.aim_type == 2, "Warp Stone: not pressed aimed silently")
    assert(at_you(1, 5100).mode ~= "spell", "Warp Stone: planned against a spell cast at you")
    stamina, HERO_LIB.is_ability_ready, HERO_LIB.cast_ability = 2, was_ready, was_cast
    print("OK: an evade spell is cast silently at a clear spot when no walk or dash gets out")
end

-- Counterspell: when no walk or dash gets you out, an owned, ready Counterspell parries the hit:
-- tapped Parry Lead (0.25 s) before it, once, with a held attack let go so it goes
local cs_ready = true
local counterspell = { get_name = function() return "upgrade_counterspell" end,
                       get_scaled_property = function(_, prop) return prop == "SpellParryDuration" and "0.8" or nil end }
S.me.get_abilities = function() return { counterspell } end
local real_ready = HERO_LIB.is_ability_ready
HERO_LIB.is_ability_ready = function(ab) return ab ~= counterspell or cs_ready end
p = plan(blast(276, 0.9)) -- 7 m, 0.9 s: walking ~1.25 s, a 5 m dash ends inside it
assert(p.mode == "counterspell" and p.goal == nil and p.counterspell.window == 0.8,
    "counterspell: not chosen with no walk or dash out, got " .. tostring(p.mode))
U.COUNTERSPELL.ui = { Get = function() return false end } -- unticked in the Escape Spells card's Items row
assert(plan(blast(276, 0.9)).mode ~= "counterspell", "counterspell: parried with it unticked")
U.COUNTERSPELL.ui = nil
-- Ethereal Shift is kept for after Counterspell: with both, the parry; with the parry down, the shift
local shift = { get_name = function() return "upgrade_self_bubble" end }
S.me.get_abilities = function() return { counterspell, shift } end
S.now = S.now + 2 -- past the time ability lookups are kept
assert(plan(blast(276, 0.9)).mode == "counterspell", "Ethereal Shift: used before Counterspell against an area")
U.COUNTERSPELL.ui = { Get = function() return false end }
assert(plan(blast(276, 0.9)).mode ~= "spell", "Ethereal Shift: used on a spell under danger level 4")
local worst = blast(276, 0.9)
worst[1].danger = 4
p = plan(worst)
assert(p.mode == "spell" and p.spell.name == "Ethereal Shift", "Ethereal Shift: not used on a danger 4 spell with Counterspell out, got " .. tostring(p.mode))
U.COUNTERSPELL.ui = nil
S.me.get_abilities = function() return { counterspell } end
S.now = S.now + 2
p = plan(blast(276, 0.9))
cmd = mkcmd(1) -- you hold attack
E.steer(cmd)
assert(not cmd.taps, "counterspell: parried 0.9 s early, outside its 0.8 s window")
S.now = S.now + 0.6
cmd = mkcmd(1)
E.steer(cmd)
assert(not cmd.taps, "counterspell: parried 0.3 s early with the default 0.25 s Parry Lead")
S.now = S.now + 0.2
cmd = mkcmd(1)
E.steer(cmd)
assert(cmd.taps == 1 and cmd.tapped == 4398046511104 and cmd.calls[1] == "release1",
    "counterspell: parry not tapped 0.1 s before the hit with the attack let go")
E.update()
assert(S.dodge == p, "counterspell: replanned while the parry is up")
-- the parry didn't come up (your own cast held it back): tapped again 0.05 s on, not sooner
cmd = mkcmd(0)
E.steer(cmd)
assert(not cmd.taps, "counterspell: tapped again in the same instant")
S.now = S.now + 0.05
cmd = mkcmd(0)
E.steer(cmd)
assert(cmd.taps == 1, "counterspell: a parry that didn't come up not tapped again")
-- up now: no more taps
local no_mods = S.me.get_modifiers
S.me.get_modifiers = function() return { { get_name = function() return "citadel_ability_melee_parry/modifier_citadel_parry" end } } end
S.now = S.now + 0.05
cmd = mkcmd(0)
E.steer(cmd)
assert(not cmd.taps, "counterspell: parried twice")
S.me.get_modifiers = no_mods
cs_ready = false
p = plan(blast(276, 0.9))
assert(p.mode == "none" and p.why:find("Counterspell on cooldown", 1, true), "counterspell: used on cooldown")
cs_ready = true
-- Tuning: a 0.1 s Parry Lead waits for it, and a 0.3 s Reaction Time doesn't call 0.12 s too late
nums.sp_react, nums.sp_parry_lead = 0.3, 0.1
p = plan(blast(276, 0.4))
cmd = mkcmd(0)
E.steer(cmd)
assert(p.mode == "counterspell" and not cmd.taps, "tuning: parried 0.4 s early with a 0.1 s Parry Lead")
p = plan(blast(276, 0.12))
assert(p.mode == "counterspell", "tuning: 0.12 s called too late to parry under a 0.3 s Reaction Time, got " .. p.mode)
-- a shot seen 0.03 s off (Charged Shot): still parried, as the parry can be up that fast and a miss
-- costs Counterspell nothing
assert(plan(blast(276, 0.03)).mode == "counterspell", "counterspell: not tried 0.03 s before the hit")
-- with Counterspell ready, a dash that gets out at all goes first, however little it has to spare:
-- at Charged Shot's max range 6 of 6 such dashes got out (0.00-0.07 s to spare), and a parry rule for
-- them only stopped dashes that would have worked
local out = plan(blast(118, 0.8)).dash.time
p = plan(blast(118, out + 0.01))
assert(p.mode == "dash", "dash first: parried where a dash gets out with 0.01 s to spare, got " .. tostring(p.mode))
-- and the dash, once tapped, is not called failing as it begins: its reaction time is spent.
-- 0.06 s to spare and checked 0.08 s in, it read as failing with that time counted again, and was parried
p = plan(blast(118, out + 0.06))
assert(p.mode == "dash", "slack: the dash under test not chosen, got " .. tostring(p.mode))
local c1 = mkcmd(0)
E.steer(c1)
E.steer(mkcmd(c1.down))
assert(p.dashed, "slack: the dash under test not tapped")
S.now = S.now + 0.08
E.update()
assert(S.dodge == p and p.mode == "dash", "slack: a dash on its way called failing 0.08 s in and parried")
nums.sp_react, nums.sp_parry_lead = nil, nil
-- in a real game the item's own cooldown says it: HERO_LIB.is_ability_in_cd, or its execute state
local real_in_cd = HERO_LIB.is_ability_in_cd
HERO_LIB.is_ability_in_cd = function(ab) return ab == counterspell end
assert(plan(blast(276, 0.9)).mode == "none", "counterspell: used while is_ability_in_cd says it is down")
HERO_LIB.is_ability_in_cd = real_in_cd
Enum.AbilityExecuteState = { READY = 0, COOLDOWN = 2, PASSIVE = 3 }
counterspell.can_be_executed = function() return 2 end
assert(plan(blast(276, 0.9)).mode == "none", "counterspell: used while its execute state says COOLDOWN")
counterspell.can_be_executed = function() return 3 end -- passive, off cooldown
assert(plan(blast(276, 0.9)).mode == "counterspell", "counterspell: a ready passive item taken for down")
counterspell.can_be_executed, Enum.AbilityExecuteState = nil, nil
-- an area that stays after it hits (`lingers`, Singularity): its parry goes 0.1 s before the hit,
-- not Parry Lead's 0.25, and until then you walk away from it, as the parry roots you after
local ring = blast(276, 0.19)[1]
ring.lingers = true
p = plan({ ring })
assert(p.mode == "counterspell" and p.lead == 0.1 and p.path, "lingers: no walk before a later parry, got " .. tostring(p.mode))
cmd = mkcmd(0)
E.steer(cmd)
assert(not cmd.taps and cmd.down ~= 0, "lingers: parried at once, or not walked away first")
S.now = S.now + 0.1
cmd = mkcmd(cmd.down)
E.steer(cmd)
assert(cmd.taps == 1 and cmd.tapped == 4398046511104, "lingers: parry not tapped 0.1 s before the hit")
-- and no dash is tapped while the parry roots you (0.42 s from its tap); from then it goes
p = plan(blast(118, 0.45))
S.parry = { from = S.now - 0.2, to = S.now + 0.6 }
local taps = 0
for _ = 1, 3 do
    cmd = mkcmd(cmd.down)
    E.steer(cmd)
    taps = taps + (cmd.taps or 0)
end
assert(taps == 0, "rooted: dash tapped 0.2 s into a parry, where none ever went")
S.now = S.now + 0.25
cmd = mkcmd(cmd.down)
E.steer(cmd)
assert(cmd.taps == 1, "rooted: dash not tapped 0.45 s into the parry")
S.parry = nil
-- Apollo lets go of a charge whose lane you stand in: its stab now lands in 0.08 s. The plan made
-- with no hit time doesn't wait out its timer, and with nothing else that fast it is parried at once
local stab = { kind = "lane", x = -3600, y = 0, z = 40, bx = -2400, by = 0, bz = 40, r = 63 }
p = plan({ stab })
assert(p.mode == "walk", "release: the charge's lane not walked out of, got " .. tostring(p.mode))
stab.at = S.now + 0.08
E.update()
p = S.dodge
assert(p.mode == "counterspell", "release: a plan with no hit time waited out its timer, got " .. tostring(p.mode))
cmd = mkcmd(0)
E.steer(cmd)
assert(cmd.taps == 1 and cmd.tapped == 4398046511104, "release: the stab not parried at once")
-- he lets go on you mid-dash: a dash that is out in time runs its course, one that isn't gives way
-- to the parry (it ran on, 0.5 m off his aim, and the stab took 65)
stab.at, stab.urgent = nil, true
p = plan({ stab })
cmd = mkcmd(0)
E.steer(cmd)
cmd = mkcmd(cmd.down)
E.steer(cmd)
assert(p.mode == "dash" and cmd.taps == 1, "release: no dash out of the urgent lane to test with")
stab.at, stab.urgent = S.now + 2, nil
E.update()
assert(S.dodge == p and p.mode == "dash", "release: a dash that is out in time given up")
stab.at = S.now + 0.08
E.update()
cmd = mkcmd(0)
E.steer(cmd)
assert(S.dodge == p and cmd.taps == 1 and cmd.tapped == 4398046511104, "release: not parried mid-dash")

-- and in the simulator: a 6 m blast on a 0.9 s fuse, out of reach of walking and dashing, parried
local SIM = require("spelldrawer_sim")
local blast6 = { id = "test_blast6", name = "Test Blast", motion = "arc", radius = 6.5, duration = 0.9, gravity_scale = 0 }
ui.sp_sim.on = true
local countered = SIM.score.countered
S.sims, S.dodge, S.parry = { SIM.cast(S.me:get_origin(), blast6) }, nil, nil
for _ = 1, 120 do
    S.now, S.rt = S.now + 1 / 60, S.rt + 1 / 60
    SIM.update()
    E.update()
    S.zones = {}
    for _, r in ipairs(S.sims) do D.draw_sim(r) end
    E.steer(mkcmd(0))
    if #S.sims == 0 then break end
end
ui.sp_sim.on = false
assert(SIM.score.countered == countered + 1, "sim: the parried blast not scored countered")
-- the simulated block holds Counterspell down for the item's 23 s, as a real block would
assert(S.counter_until and math.abs(S.counter_until - S.now - 23) < 0.1, "sim: the block didn't put Counterspell on cooldown")
p = plan(blast(276, 0.9))
assert(p.mode == "none" and p.why:find("on cooldown (simulated)", 1, true), "sim: Counterspell used again inside its cooldown")
S.counter_until = nil
-- Exploding Uppercut 0.3 s out: no walk or dash makes it, so it is parried, planned with the whole
-- wind-up to spare (drawn only from the fist's 0.2 s it left 0.07 s)
local cut = by_id["bebop_exploding_uppercut"]
countered = SIM.score.countered
ui.sp_sim.on = true
S.sims, S.dodge, S.parry = { SIM.cast(S.me:get_origin(), cut) }, nil, nil
local warned
for _ = 1, 60 do
    S.now, S.rt = S.now + 1 / 60, S.rt + 1 / 60
    SIM.update()
    E.update()
    warned = warned or S.dodge and S.dodge.t
    S.zones = {}
    for _, r in ipairs(S.sims) do D.draw_sim(r) end
    E.steer(mkcmd(0))
    if #S.sims == 0 then break end
end
ui.sp_sim.on = false
assert(warned and warned > 0.2, "sim: Exploding Uppercut seen " .. tostring(warned) .. " s before the hit, wanted its 0.3 s")
assert(SIM.score.countered == countered + 1, "sim: Exploding Uppercut not parried")
S.counter_until = nil
-- Counterspell is the last resort: a lunge lane 0.6 s out with 1 m to walk out of is walked, ready or not
p = plan({ { kind = "lane", x = -3600, y = 0, z = 40, bx = -2400, by = 0, bz = 40, r = 30, px = -3600, py = 0,
             speed = 2200, delay = 0.33 } })
assert(p.mode == "walk", "last resort: Counterspell before walking, got " .. p.mode)
-- a spell cast at you: never walked or dashed from, parried with Counterspell; with it down, nothing
-- is sent and your own keys stay yours
local cast = { { kind = "target", x = -3000, y = 0, z = 0, r = 20, at = 5000 + 0.6 } }
p = plan(cast)
assert(p.mode == "counterspell" and p.targeted and not p.goal, "target: not parried, got " .. tostring(p.mode))
cs_ready = false
p = plan(cast)
assert(p.mode == "none" and p.why:find("cast at you", 1, true), "target: walked or dashed, got " .. p.mode)
cmd = mkcmd(8)
E.steer(cmd)
assert(cmd.down == 8 and #cmd.calls == 0, "target: your W let go with nothing to escape to")
cs_ready = true
-- an area you stand in that hits before the cast does is escaped first: chained by Chain Gang, 2.8 s
-- from its pull, a 3 m blast is 2 s off. And two areas each by its own time: out of that blast and
-- of an 8 m wave round it that is at its edge 1 s later, where both held to the blast's 0.45 s fail
p = plan({ { kind = "target", x = -3000, y = 0, z = 0, r = 20, at = 5000 + 2.8 }, blast(118, 2)[1] })
assert(p.mode == "walk" and not p.targeted, "target: an area that hits first not escaped, got " .. tostring(p.mode))
-- with nothing to block the cast (Counterspell down), an area you stand in is still left, whether it
-- hits after the cast or has no hit time (a trap): held to the block, Evade stood in it. Ready, the
-- block still comes first
local slam = { kind = "target", x = -3000, y = 0, z = 0, r = 20, at = 5000 + 2.1 }
local trap = { kind = "circle", x = -3000, y = 0, z = 0, r = 118 }
p = plan({ slam, trap })
assert(p.mode == "counterspell" and p.targeted, "target: a block that is ready not kept first, got " .. tostring(p.mode))
cs_ready = false
p = plan({ slam, trap })
assert(p.mode == "walk" and not p.targeted, "target: a trap under an unblockable cast not left, got " .. tostring(p.mode))
p = plan({ slam, blast(118, 2.5)[1] })
assert(p.mode == "walk" and not p.targeted, "target: a later blast under an unblockable cast not left, got " .. tostring(p.mode))
cs_ready = true
local ring ={ kind = "circle", x = -3000, y = 0, z = 0, r = 315, at = 5000 + 1.45, grow = 315 / 1 }
EStatsType = { EGroundDashDistanceInMeters = 91, EGroundDashDuration = 92 }
S.me.get_scaling_stat = function(_, id) return id == 91 and 10 or id == 92 and 0.68 or nil end
p = plan({ blast(118, 0.45)[1], ring })
assert(p.mode == "dash" and off(p.dash) >= 315 + 39, "wave: not dashed out of the blast and its wave, got " .. tostring(p.mode))
ring.grow, ring.at = nil, 5000 + 0.45
p = plan({ blast(118, 0.45)[1], ring })
assert(p.mode ~= "dash" and p.mode ~= "walk", "wave: out of 8 m in 0.45 s, got " .. tostring(p.mode))
EStatsType, S.me.get_scaling_stat = nil, nil
-- and in the simulator: Close the Deal, 0.45 s from his telegraph, parried
countered = SIM.score.countered
ui.sp_sim.on = true
S.sims, S.dodge, S.parry = { SIM.cast(S.me:get_origin(), by_id["danny_close_the_deal"]) }, nil, nil
local told = S.now
for _ = 1, 90 do
    S.now, S.rt = S.now + 1 / 60, S.rt + 1 / 60
    SIM.update()
    E.update()
    S.zones = {}
    for _, r in ipairs(S.sims) do D.draw_sim(r) end
    E.steer(mkcmd(0))
    if #S.sims == 0 then break end
end
ui.sp_sim.on = false
assert(SIM.score.countered == countered + 1, "sim: Close the Deal not parried")
-- up before 0.47 s, the soonest a real grab landed after his telegraph (the parry takes ~0.04 s)
assert(S.parry.from - told < 0.47 - 0.05, ("sim: Close the Deal parried %.2f s after the telegraph"):format(S.parry.from - told))
S.counter_until = nil
-- with Item Cooldowns off, the simulator's block leaves Counterspell ready for the next test spell
switch_off.sp_sim_cd = true
S.sims, S.dodge, S.parry = { SIM.cast(S.me:get_origin(), by_id["ghost_soul_exchange"]) }, nil, nil
ui.sp_sim.on = true
for _ = 1, 30 do
    S.now, S.rt = S.now + 1 / 60, S.rt + 1 / 60
    SIM.update()
    E.update()
    S.zones = {}
    for _, r in ipairs(S.sims) do D.draw_sim(r) end
    E.steer(mkcmd(0))
    if #S.sims == 0 then break end
end
ui.sp_sim.on, switch_off.sp_sim_cd = false, nil
assert(SIM.score.countered == countered + 2 and not S.counter_until,
    "sim: Soul Exchange not parried, or Counterspell held down with Item Cooldowns off")
HERO_LIB.is_ability_ready, S.me.get_abilities = real_ready, nil

-- Evade Path: an enemy guardian by the nearest way out sends you the other way; unticked, it doesn't.
-- Ringed by turret range, Prefer still walks you out of the spell and Strict doesn't. A dash and a
-- walk keep Hero Distance from an enemy hero
hero_pos[1], hero_pos[2] = -3000, 0
local real_all, nt = entity_list.get_all, 0
local function hplan(r, t, units)
    entity_list.get_all = function() return units or {} end
    nt = nt + 1
    S.dodge, S.now, S.parry = nil, 6000 + nt, nil
    S.zones = { { kind = "circle", x = -3000, y = 0, z = 0, r = r, at = S.now + t } }
    E.update()
    return S.dodge
end
local function unit(x, y, class)
    local u = mkpawn(800 + nt, { x, y, 0 }, nil, { mods = {}, particles = {} })
    u.get_class_name = function() return class end
    return u
end
local function from(p, x, y) return math.sqrt((p.x - x) ^ 2 + (p.y - y) ^ 2) / UPM end
local base = hplan(200, 2).goal
local ux, uy = (base.x + 3000) / off(base), base.y / off(base) -- the way it goes with nothing about
local gx, gy = -3000 + ux * 15 * UPM, uy * 15 * UPM          -- a guardian 15 m out that way
-- its 34 m range covers all the search reaches: you are walked to its far side, the least deep in it
p = hplan(200, 2, { unit(gx, gy, "C_NPC_TrooperBoss") })
assert(p.mode == "walk" and from(p.goal, gx, gy) >= 20, ("evade path: walked to %.1f m from a guardian"):format(from(p.goal, gx, gy)))
turret_off.Guardians = true
p = hplan(200, 2, { unit(gx, gy, "C_NPC_TrooperBoss") })
assert(p.mode == "walk" and from(p.goal, gx, gy) < 15, "evade path: an unticked guardian still avoided")
turret_off.Guardians = nil
-- a walker right on you, its 24 m range past the search's reach: Prefer gets out of the spell, Strict
-- stays; at 50% (12 m) Strict walks out of it too
p = hplan(200, 2, { unit(-3000, 0, "C_NPC_Boss_Tier2") })
assert(p.mode == "walk" and off(p.goal) >= 200, "evade path: Prefer didn't walk out of the spell inside a walker's range")
nums.sp_hazard_rule = 1
p = hplan(200, 2, { unit(-3000, 0, "C_NPC_Boss_Tier2") })
assert(p.mode ~= "walk" and not p.goal, "evade path: Strict ended a walk in a walker's range")
nums.sp_turret_scale = 50
p = hplan(200, 2, { unit(-3000, 0, "C_NPC_Boss_Tier2") })
assert(p.goal and off(p.goal) >= 12 * UPM, "evade path: Turret Range Scale at 50% not halving a walker's 24 m")
nums.sp_hazard_rule, nums.sp_turret_scale = 0, 100
-- Hero Distance 4 m: an enemy hero 8 m out the usual way; the walk ends 4 m or more from him
nums.sp_hero_dist = 4
local hx, hy = -3000 + ux * 8 * UPM, uy * 8 * UPM
p = hplan(200, 2, { unit(hx, hy, "C_CitadelPlayerPawn") })
assert(p.mode == "walk" and from(p.goal, hx, hy) >= 4, ("evade path: walked to %.1f m from an enemy hero"):format(from(p.goal, hx, hy)))
-- and the dash: one that would end by him goes another way
local d0 = hplan(118, 0.45).dash
p = hplan(118, 0.45, { unit(d0.x, d0.y, "C_CitadelPlayerPawn") })
assert(p.mode == "dash" and from(p.dash, d0.x, d0.y) >= 4, "evade path: dashed to an enemy hero")
-- Aggressive Dodge: an enemy hero 10 m behind the usual way out, a guardian behind him. Not held, the
-- dodge keeps away from both; held, it ends nearer him than it would, turret or not
local ex, ey = -3000 - ux * 10 * UPM, -uy * 10 * UPM
local foes = function() return { unit(ex, ey, "C_CitadelPlayerPawn"), unit(-3000 - ux * 15 * UPM, -uy * 15 * UPM, "C_NPC_TrooperBoss") } end
p = hplan(200, 2, foes())
local calm = from(p.goal, ex, ey)
ui.sp_aggro.down = true
p = hplan(200, 2, foes())
assert(p.mode == "walk" and from(p.goal, ex, ey) < calm - 5,
    ("aggressive dodge: ends %.1f m from the enemy hero, %.1f m not held"):format(from(p.goal, ex, ey), calm))
assert(from(p.goal, ex, ey) >= 2.5, ("aggressive dodge: ends %.1f m from the enemy hero, on top of him"):format(from(p.goal, ex, ey)))
-- and a dash out goes his way too
local dd = hplan(118, 0.45, foes()).dash
ui.sp_aggro.down = false
local dc = hplan(118, 0.45, foes()).dash
assert(dd and dc and from(dd, ex, ey) < from(dc, ex, ey) - 3,
    ("aggressive dodge: the dash ends %.1f m from the enemy hero, %.1f m not held"):format(from(dd, ex, ey), from(dc, ex, ey)))
-- Toward allies: your hero 10 m behind the usual way out turns the walk and the dash his way, not
-- onto him; your guardian the other side, further off, wins over him
do
    local yours, real_same = {}, HERO_LIB.is_same_team
    HERO_LIB.is_same_team = function(_, e) return yours[e] == true end
    local function friend(x, y, class)
        local u = unit(x, y, class)
        yours[u] = true
        return u
    end
    local ax, ay = -3000 - ux * 10 * UPM, -uy * 10 * UPM
    local tx, ty = -3000 - uy * 20 * UPM, ux * 20 * UPM -- a quarter turn from both
    local alone = from(hplan(200, 2).goal, ax, ay)
    p = hplan(200, 2, { friend(ax, ay, "C_CitadelPlayerPawn") })
    assert(p.mode == "walk" and from(p.goal, ax, ay) < alone - 5 and from(p.goal, ax, ay) >= 2.5,
        ("toward allies: the walk ends %.1f m from your hero, %.1f m without him"):format(from(p.goal, ax, ay), alone))
    local da = hplan(118, 0.45, { friend(ax, ay, "C_CitadelPlayerPawn") }).dash
    -- a 5 m dash at him 10 m off ends 5 m from him; any of the other 7 ends 7.4 m or more
    assert(da and from(da, ax, ay) < 5.5, ("toward allies: the dash ends %.1f m from your hero"):format(da and from(da, ax, ay) or -1))
    local hero_way = from(p.goal, tx, ty)
    p = hplan(200, 2, { friend(ax, ay, "C_CitadelPlayerPawn"), friend(tx, ty, "C_NPC_TrooperBoss") })
    assert(p.mode == "walk" and from(p.goal, tx, ty) < hero_way - 3, "toward allies: your turret didn't win over your nearer hero")
    HERO_LIB.is_same_team = real_same
    print("OK: Toward allies: equal ways out end toward your turret, else your hero")
end
-- the minimap's marker of a trooper is no unit: only the trooper itself is listed
entity_list.get_all = function() return { unit(0, 0, "CCitadelTrooperMinimap"), unit(0, 0, "C_NPC_Trooper") } end
S.now = S.now + 1
local us = U.units()
assert(#us == 1 and us[1].kind == "trooper", "units: a minimap marker taken for a unit")
print("OK: units are asked for by exact class: a minimap marker is no trooper")
nums.sp_hero_dist, entity_list.get_all = 0, real_all
print("OK: Evade Path: round an enemy turret or hero when there's a way; Prefer goes anyway, Strict doesn't")
print("OK: Aggressive Dodge: held, the walk and dash out end toward the nearest enemy hero, turrets or not")

-- Ties go your way: you run 1 m south in 0.12 s, then a blast 1 m south of you: the shortest way out
-- is north, and you still turn back to it. A blast right on you, equal all round: you go the way you
-- run (west), not the first way the search tries (east)
local function running(dx, dy, cy)
    S.zones, S.dodge, S.rt = {}, nil, S.rt + 5
    hero_pos[1], hero_pos[2] = -3000 - dx * UPM, -dy * UPM
    E.update()
    S.rt, hero_pos[1], hero_pos[2] = S.rt + 0.12, -3000, 0
    nt = nt + 1
    S.dodge, S.now, S.parry = nil, 7000 + nt, nil
    S.zones = { { kind = "circle", x = -3000, y = cy * UPM, z = 0, r = 200, at = S.now + 3 } }
    E.update()
    return S.dodge
end
p = running(0, -1, -1)
assert(p.mode == "walk" and p.goal.y > 0, "ties: your run took you the long way out, not the shortest, north")
p = running(-1, 0, 0)
assert(p.mode == "walk" and p.goal.x < -3000 - 100, "ties: an equal tie broken against your run")
print("OK: the shortest way out, an equal tie broken the way you run")

-- a walk under way isn't stopped when the next search reads it as too late (it counts your reaction
-- time again): with no dash to give, the walk goes on rather than "no escape"
stamina = 0
S.zones, S.dodge, S.now, S.parry = { { kind = "circle", x = -3000, y = 0, z = 0, r = 200, at = 7001.1 } }, nil, 7000, nil
E.update()
local walk = S.dodge
assert(walk and walk.mode == "walk", "walk kept on: the first plan isn't a walk, got " .. tostring(walk and walk.mode))
S.now = 7000.2
E.update()
assert(S.dodge == walk and walk.mode == "walk", "walk kept on: a walk under way dropped for no escape")
stamina = 2
print("OK: a walk under way goes on when the next search reads it as too late")

-- A new map: the clock starts over. A parry and a dodge timed on the old clock don't hold the next
-- ones off, and the next scan is due at once
S.me.get_abilities = function() return { counterspell } end
HERO_LIB.is_ability_ready = function() return true end
p = plan(blast(276, 0.9)) -- at 5000
S.now = S.now + 0.8
cmd = mkcmd(0)
E.steer(cmd)
assert(cmd.taps == 1 and S.parry, "map restart: no parry on the old clock to start from")
U.tick(S.now)
S.next_scan, S.targeted = S.now + 1, { old = S.now }
U.tick(1)
assert(S.now == 1 and S.next_scan == 0 and next(S.targeted) == nil, "map restart: the old clock's scan time or marks kept")
S.zones, S.dodge = { { kind = "circle", x = -3000, y = 0, z = 0, r = 200, at = 3 } }, nil
E.update()
assert(S.dodge and S.dodge.mode == "walk" and not S.parry,
    "map restart: no walk on the new clock, got " .. tostring(S.dodge and S.dodge.mode))
S.zones, S.dodge = { { kind = "circle", x = -3000, y = 0, z = 0, r = 276, at = 1.9 } }, nil
E.update()
assert(S.dodge.mode == "counterspell", "map restart: no parry planned on the new clock, got " .. tostring(S.dodge.mode))
S.now = 1.8
cmd = mkcmd(0)
E.steer(cmd)
assert(cmd.taps == 1, "map restart: the parry held off by the old clock")
HERO_LIB.is_ability_ready, S.me.get_abilities, S.parry, S.dodge = real_ready, nil, nil, nil
print("OK: a map restart: scan, walk and parry go on with the clock started over")
print("OK: walk when walking makes it, dash when only a dash does, no input when neither does")
print("OK: Counterspell parries what no walk or dash escapes, 0.25 s before the hit, once, not on cooldown")
print("OK: the guard lets go of your keys that walk you into an area, keeps the half along its edge")
end)()

-- ---- a shot's wind-up: Celeste charging Shining Wonder (AbilityCastDelay 0.75 s) ----
;(function()
local spell = by_id["celeste_shining_wonder"]
-- west of the wall the dodge tests put at x >= 120: a shot's wind-up lane stops at walls
local celeste, st = actor(300, -20000, 0, 0, "ability_unicorn_dazzlingorb", {})
local w = world(spell, celeste)
local function lanes()
    S.zones = {}
    step(w)
    local out = {}
    for _, z in ipairs(S.zones) do if z.kind == "lane" then out[#out + 1] = z end end
    return out
end
-- the cast delay runs 0.75 s; her aim is +x. Half a second in, the lane runs +x from her, stops at
-- the 101.6 m range and says the orb leaves in a quarter second
st.cast = true
local l
for _ = 1, 30 do l = lanes()[1] or l end
assert(l, "wind-up: no lane while Shining Wonder charges")
assert(l.bx > l.x and math.abs(l.by - l.y) < 1 and math.abs((l.bx - l.x) / UPM - 101.6) < 0.1,
    ("wind-up: lane not 101.6 m along her aim (%.1f m)"):format((l.bx - l.x) / UPM))
assert(l.speed == 2000 and l.delay and math.abs(l.delay - 0.25) < 0.05,
    ("wind-up: orb leaves in %s s, wanted 0.25"):format(tostring(l.delay)))
-- once bullets from her have been seen, only those shots draw, but a wind-up has no shot yet
spell.bullet_owners = { [300] = true }
assert(#lanes() == 1, "wind-up: hidden behind her earlier bullets")
spell.bullet_owners = nil
-- the cast delay ends as the orb leaves: the wind-up lane goes with it
for _ = 1, 15 do lanes() end
st.cast = false
local left = lanes()
assert(#left == 0, "wind-up: lane still up after the orb left")
-- aimed at a wall 5 m off, the lane ends at the wall, not 22 m on through it
local near, nst = actor(301, 120 - 5 * UPM, 0, 0, "ability_unicorn_dazzlingorb", {})
w = world(spell, near)
nst.cast = true
l = nil
for _ = 1, 10 do l = lanes()[1] or l end
assert(l and math.abs(l.bx - 120) < 2, ("wind-up: lane ran past the wall to x %.0f"):format(l and l.bx or 0 / 0))
print("OK: a shot's wind-up draws its lane along the aim, timed to when it leaves, ends as it does, stops at walls")
end)()

-- ---- an enemy's wind-up told by a particle: Holliday's Spirit Lasso aim preview (0.5 s) ----
;(function()
local function lanes(w)
    S.zones = {}
    step(w)
    local out = {}
    for _, z in ipairs(S.zones) do if z.kind == "lane" then out[#out + 1] = z end end
    return out
end
-- her cast delay never reads: her aim preview starts the lane along her aim, timed to the throw
local spell = by_id["holliday_spirit_lasso"]
local holliday = actor(302, -20000, 0, 0, "ability_gravity_lasso", { AbilityCastRange = 20 })
local w = world(spell, holliday)
assert(#lanes(w) == 0, "spirit lasso: a lane before her wind-up")
X.track_particle({ name = "particles/abilities/astro/astro_lasso_preview.vpcf", entity = holliday, index = 1400 })
local l
for _ = 1, 6 do l = lanes(w)[1] or l end
assert(l, "spirit lasso: no lane from her aim preview")
assert(l.bx > l.x and math.abs((l.bx - l.x) / UPM - 20) < 0.1, "spirit lasso: wind-up lane not 20 m along her aim")
assert(l.delay and math.abs(l.delay - (0.5 - 6 / 60)) < 0.05, ("spirit lasso: throw in %s s, wanted ~0.4"):format(tostring(l.delay)))
-- past the wind-up it is thrown: its own bullet's lane takes over
for _ = 1, 30 do lanes(w) end
assert(#lanes(w) == 0, "spirit lasso: wind-up lane still up after the throw")
print("OK: an enemy's Spirit Lasso wind-up, told by her aim preview, draws its lane timed to the throw")
end)()

-- ---- Leaping Slash: a wind-up seen (your own Calico's) adds what's left of its 0.1 s; the simulator
-- casts it as the move it is; the animation logger names an enemy's clip once ----
;(function()
local spell = by_id["calico_leaping_slash"]
local calico, st = actor(310, -15000, 0, 0, "ability_nano_dash", { AbilityCastRange = 9, SlashRadius = 4 })
local w = world(spell, calico)
st.cast = true
S.zones = {}
step(w)
S.zones = {}
step(w)
local lane
for _, z in ipairs(S.zones) do if z.kind == "lane" then lane = z end end
assert(lane and lane.delay and math.abs(lane.delay - (0.1 - 1 / 60)) < 0.01,
    ("leaping slash: wind-up left %s s, wanted ~0.083"):format(tostring(lane and lane.delay)))

local SIM = require("spelldrawer_sim")
hero_pos[1], hero_pos[2] = -3000, 0
S.me = mkpawn(950, hero_pos, nil, { mods = {}, particles = {} })
local o = S.me:get_origin()
for _ = 1, 20 do
    local r = SIM.cast(o, spell)
    local go = math.sqrt((r.dash_to.x - r.from.x) ^ 2 + (r.dash_to.y - r.from.y) ^ 2)
    local past = math.sqrt((r.slash.x - r.dash_to.x) ^ 2 + (r.slash.y - r.dash_to.y) ^ 2)
    assert(go <= 9 * UPM + 1 and math.abs(past - 1.5 * UPM) < 1 and math.abs(r.T - (0.1 + go / 2400)) < 1e-6,
        "sim: Leaping Slash not a 0.1 s wind-up, a dash of at most 9 m and a slash 1.5 m past it")
end

local logged, real_print = {}, print
print = function(line) logged[#logged + 1] = tostring(line) end
local enemy = mkpawn(311, { -2800, 0, 0 }, nil, { mods = {}, particles = {} })
X.track_animation(enemy, { name = "nano_dash_windup", duration = 0.3 })
X.track_animation(enemy, { name = "nano_dash_windup", duration = 0.3 })
print = real_print
assert(#logged == 1 and logged[1]:find("started nano_dash_windup, 0.30 s", 1, true),
    "animation log: not one line naming the clip (" .. #logged .. ")")
print("OK: Leaping Slash: timed by her dash, a seen wind-up adds its 0.1 s, simulated as the move; animations logged once")
end)()

-- ---- aimed landings: Seismic Impact comes down where Abrams aims; the spot is marked while the
-- flight is still held back ----
;(function()
HERO_LIB.is_on_ground = function(e) return e:get_origin().z < 1 end
local function circles()
    local out = {}
    for _, z in ipairs(S.zones) do if z.kind == "circle" then out[#out + 1] = z end end
    return out
end
-- Abrams up 600 u aiming 45 deg down along +x. On the leap and hover (his boosting modifier) nothing
-- is drawn; as he crashes (boosting_crash) the spot is where that aim meets the floor, 670 u on
-- from under his eyes: 9 m, reached at his 6000 u/s from where he is
local seismic = by_id["abrams_seismic_impact"]
local abrams, st, pos = actor(320, -20000, 0, 600, "citadel_ability_bull_leap", { ImpactRadius = 9 })
abrams.m_angEyeAngles = { pitch = 45, yaw = 0 }
st.mods = { mod("modifier_citadel_bull_leap_boosting") }
local w = world(seismic, abrams)
S.zones = {}
step(w)
assert(#circles() == 0, "aimed landing: drawn on Abrams' leap, before the crash")
st.mods = { mod("modifier_citadel_bull_leap_boosting_crash") }
w = world(seismic, abrams)
S.zones = {}
step(w)
local c = circles()
local dist = math.sqrt(670 ^ 2 + (600 + 36 - 4) ^ 2) -- from his body (BODY_Z up) to the spot (4 u up)
assert(#c == 1 and math.abs(c[1].x - (-20000 + 670)) < 3 and math.abs(c[1].y) < 1 and c[1].r == 9 * UPM
    and c[1].at and math.abs(c[1].at - S.now - dist / 6000) < 0.01,
    "aimed landing: Abrams' crash not marked where he aims, timed at 6000 u/s")
abrams.m_angEyeAngles.pitch = 10 -- too flat to crash
S.zones = {}
step(w)
assert(#circles() == 0, "aimed landing: marked while he aims too flat to crash")
abrams.m_angEyeAngles.pitch, pos[3] = 45, 0 -- landed
S.zones = {}
step(w)
assert(#circles() == 0, "aimed landing: marked with him on the ground")

print("OK: aimed landings: Abrams' crash marked where he aims and timed, not his leap")

-- the simulator: nothing is drawn or dodged while Danny hovers, only his dive, timed. Abrams isn't
-- marked while he hovers either, only as he crashes, timed
local SIM = require("spelldrawer_sim")
ui.sp_sim.on = true
hero_pos[1], hero_pos[2] = -3000, 0
S.me = mkpawn(950, hero_pos, nil, { mods = {}, particles = {} })
local r = SIM.cast(S.me:get_origin(), seismic)
assert(not r.aim_spot, "sim: Abrams marked while he rises")
S.sims, S.rt = { r }, S.rt + r.up + 0.01 -- just into his crash
SIM.update()
assert(r.aim_spot and r.aim_at and math.abs(r.aim_at - r.first - r.T) < 1e-6, "sim: Abrams' crash not marked and timed")
S.sims, S.rt = {}, S.rt - r.up - 0.01
r = SIM.cast(S.me:get_origin(), by_id["danny_chimera_mk1"])
r.up, r.T = 2.5, r.T - r.up + 2.5 -- a 2.5 s hover
S.sims, S.dodge, S.parry, S.counter_until = { r }, nil, nil, nil
local hovered, timed
for _ = 1, 300 do
    S.now, S.rt = S.now + 1 / 60, S.rt + 1 / 60
    SIM.update()
    E.update()
    S.zones = {}
    for _, z in ipairs(S.sims) do D.draw_sim(z) end
    for _, z in ipairs(S.zones) do
        if S.rt - r.t0 < r.up then hovered = true elseif z.at then timed = true end
    end
    if #S.sims == 0 then break end
end
assert(not hovered and timed, "sim: Danny's Chimera drawn while he hovered, or his dive not timed")
ui.sp_sim.on = false
print("OK: sim: Danny's Chimera drawn only as he dives, timed; Abrams marked only as he crashes")
end)()


-- Still Life from an enemy whose slots don't read (only the scan sees her channel), with the default
-- Dodge Interval: its ring stays up between scans, so the parry goes Parry Lead before the stun. Held off
-- by a 0.1 s modifier check, the ring was off between scans and the parry went as the stun landed (2026-11-11)
;(function()
local spell = by_id["violet_still_life"]
local violet, st = actor(600, -200, -600, 0, nil, {}) -- an enemy's slot: unreadable
local w = world(spell, violet)
local item = { get_name = function() return "upgrade_counterspell" end,
               get_scaled_property = function(_, prop) return prop == "SpellParryDuration" and "0.8" or nil end }
local abilities, ready, mods = viewer.get_abilities, HERO_LIB.is_ability_ready, viewer.get_modifiers
viewer.get_abilities = function() return { item } end
HERO_LIB.is_ability_ready = function() return true end
nums.sp_dodge_gap = 0.25
S.dodge, S.parry, S.counter_until = nil, nil, nil
w.t = 5000
local t0, tapped, at = 5000.5, nil, nil
while w.t < t0 + 3 and not tapped do
    local now = w.t + 1 / 60
    local on = now >= t0 and now < t0 + 2.6
    st.mods = on and { mod("ability_artist_tether/self") } or {}
    viewer.get_modifiers = function() return on and { mod("ability_artist_tether/buildup") } or {} end
    step(w) -- the frame: scan, modifiers, projectiles
    E.update()
    S.zones = {} -- the drawing refills the zones, then the command is steered
    for _, r in pairs(S.list) do D.draw_entity(r, viewer) end
    for _, z in ipairs(S.zones) do if z.kind == "target" then at = z.at end end
    local cmd = mkcmd(0)
    E.steer(cmd)
    if cmd.taps then tapped = S.now end
end
viewer.get_abilities, HERO_LIB.is_ability_ready, viewer.get_modifiers = abilities, ready, mods
nums.sp_dodge_gap = 0
S.dodge, S.parry = nil, nil
assert(tapped and at and at - tapped > 0.2 and at - tapped <= 0.25 + 1e-6,
    ("still life: parried %s s before the stun, want Parry Lead (0.25 s)"):format(tapped and at and at - tapped))
print("OK: Still Life from an enemy whose slots don't read: parried Parry Lead before the stun")
end)()
