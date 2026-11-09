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
local nums, switch_off = { sp_size = 2, sp_dist = 0, sp_sim_gap = 1.5 }, {} -- switch_off[k]: that switch reads false
for _, k in ipairs({ "sp_debug", "sp_enable", "sp_land", "sp_arc", "sp_boxes", "sp_labels",
                     "sp_points", "sp_size", "sp_dist", "sp_dodge", "sp_dodge_debug", "sp_sim_gap",
                     "sp_react", "sp_margin", "sp_parry_lead" }) do
    ui[k] = { Get = function()
        if nums[k] then return nums[k] end
        return not switch_off[k]
    end }
end
ui.sp_sim = { on = false, Get = function(self) return self.on end }
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
    get_hero_id = function(p) return p._hero_id end, -- a fixture hero carries its m_HeroID here
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
Render.FilledTriangle = function(tri) pts[#pts + 1] = tri[2]; pts[#pts + 1] = tri[3] end
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
assert(#pts == 2 * 24, "expected 24 fan triangles")
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
        local ok, err = pcall(D.draw_entity, rec, foe)
        assert(ok, "aura draw error: " .. tostring(err))
    end
    return rec, lines
end

-- modifier runs t=0 .. 2.8 (the pull); sample it like the 0.25 s scan does
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
print(("t=2.90 (0.1 s past the pull)       ring drawn = %s"):format(tostring(at_pull > 0)))
assert(at_pull > 0, "ring vanished the moment the pull landed")
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
    assert(s.hero_id, s.id .. ": no hero_id")
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

-- Abrams' Shoulder Charge also carries modifier_shoulder_charge_buff, which Rising Ram's loose
-- "charge" matches. That match must not wipe Shoulder Charge's lane: not on your own Abrams (his
-- abilities read, so Rising Ram isn't his) and not on an enemy whose abilities all read as missing.
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
assert(rec_for(ram, enemy), "enemy case no longer has the stray Rising Ram group it should survive")
assert(rec_for(sc, enemy) and rec_for(sc, enemy).path, "a stray Rising Ram match wiped the enemy's Shoulder Charge lane")
print("OK: Shoulder Charge keeps its lane with Rising Ram's loose \"charge\" match on Abrams")

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

-- a Shining Wonder shot's lane runs the measured 22.2 m, not the 15 m bounce radius
local orb_lane
for _, r in pairs(S.groups) do if r.shot and r.spell == orb_spell then orb_lane = r end end
assert(orb_lane and orb_lane.land, "no Shining Wonder lane from the bullet")
local reach = math.sqrt(orb_lane.land.x ^ 2 + orb_lane.land.y ^ 2) / U.CFG.UNITS_PER_M
assert(math.abs(reach - 22.2) < 0.05, ("Shining Wonder lane is %.2f m, not 22.2 m"):format(reach))
print(("OK: Shining Wonder's lane reaches %.1f m"):format(reach))
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
-- with min_speed 20, lane half-width SlashRadius 1.6 m (:272170), reach SlashLength 13 m (:272180),
-- lunge DashSpeed 1100 u/s (:272055).
local function lunge_positive(spell)
    local apollo, st, pos = actor(215, 2000, 0, 0, "ability_fencer_lunge", { SlashLength = 13, SlashRadius = 1.6 })
    local w = world(spell, apollo)
    st.mods = { mod("modifier_base_uirecast") }
    for _ = 1, 20 do pos[1] = pos[1] + 1100 / 60; step(w) end
    assert_lane(2000, 0, 1.6, 13, 2.5, "flawless advance", 1.6)
    -- the lunge is over and he stands in the 5 s recast window (RecastTime :272190), modifier still
    -- on: the lane clears within a velocity sample or two, not with the window
    for _ = 1, 9 do step(w) end
    assert(#REC.tris == 0, "flawless advance: the lane stayed drawn after the lunge stopped")
end

local function lunge_negative(spell)
    -- uirecast is also the recast window of Disengaging Sigil, and it covers the walk before the
    -- lunge: at walking speed (8.8 m/s, under the 20 m/s floor) nothing is drawn once the first
    -- velocity sample is in
    local victim, vst = actor(216, 2000, 200, 0, nil, {})
    vst.mods = { mod("modifier_base_uirecast") }
    local w = world(spell, actor(217, 2000, 0, 0, "ability_fencer_lunge", {}), { victim })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "flawless advance: the victim's modifier detected")

    local apollo, st, pos = actor(218, 2000, 0, 0, "ability_fencer_lunge", { SlashLength = 13, SlashRadius = 1.6 })
    local w2 = world(spell, apollo)
    st.mods = { mod("modifier_base_uirecast") }
    for _ = 1, 40 do pos[1] = pos[1] - 8.8 * UPM / 60; step(w2) end
    assert(#REC.tris == 0, "flawless advance: a lane drawn while he walks in the recast window")
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

    -- mid-ram the lane starts on him every frame, also the two in three between velocity samples
    local billy2, st2, pos2 = actor(232, 4000, 0, 0, "ability_punkgoat_goatflip", { ChargeRadius = 2.54 })
    local w2 = world(spell, billy2)
    st2.mods = { mod("charge") }
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

    -- and under the 25 m/s floor a walk with a "charge" modifier on him draws nothing
    local billy, st, pos = actor(231, 4000, 0, 0, "ability_punkgoat_goatflip", { ChargeRadius = 2.54 })
    local w2 = world(spell, billy)
    st.mods = { mod("charge") }
    for _ = 1, 40 do pos[1] = pos[1] - 8.8 * UPM / 60; step(w2) end
    assert(#REC.tris == 0, "rising ram: a lane drawn while he walks")
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
    for _ = 1, 120 do g = step(w) or g end -- 2.0 s in: inside the last second
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
end

entry("calico_gloom_bombs", gloom_positive, gloom_negative)

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

    -- in game the tell rode an entity that names no owner and came before every hero in the entity
    -- list: the scan asked who plays Celeste before it had seen any hero ("ids: " empty) and
    -- dropped it, and the tell's own event never got a position to draw at
    local enemy = actor(251, 10400, 0, 0, "ability_unicorn_luminousstrike", { ExplosionRadius = 8 })
    local carrier = mkproj(252, 10600, 0, 0, { name = tell,
        control_points = { { cp = 0, origin = Vector(10600, 0, 0) } } }, "C_ParticleSystem")
    local w5 = world(spell, enemy, { carrier })
    table.remove(w5.all, 2)
    table.insert(w5.all, 1, carrier)
    X.track_particle({ name = tell, index = 46 }) -- no update_particle: no CP0 on the event
    for _ = 1, 20 do step(w5) end
    clear_rec()
    for _, r in pairs(S.list) do if r.spell == spell then D.draw_entity(r, viewer) end end
    assert_marker(10600, 0, 8, "radiant daggers on a carrier listed before the heroes")
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
-- m_flBulletRadius 65 u (:288792) half-width; range 22.2 m and 1820 u/s are measured in game (the
-- vdata has neither; BounceRadius 15 m is the seek radius).
local function orb_positive(spell)
    local celeste = actor(248, 7400, 0, 0, "ability_unicorn_dazzlingorb", {})
    local orb, _, pos = mkproj(249, 7500, 0, 100, "particles/abilities/unicorn/unicorn_ball_projectile.vpcf")
    local w = world(spell, celeste, { orb })
    for _ = 1, 20 do step(w); pos[1] = pos[1] + 1820 / 60 end
    assert_lane(7500, 0, 65 / UPM, 22.2, nil, "shining wonder")
end

local function orb_negative(spell)
    local celeste = actor(250, 7400, 0, 0, "ability_unicorn_dazzlingorb", {})
    local charge = mkproj(251, 7400, 0, 40, "particles/abilities/unicorn/unicorn_ball_charge.vpcf")
    local w = world(spell, celeste, { charge })
    run(w, 0.4)
    assert(count_groups(spell) == 0, "shining wonder: the charge particle detected")
end

entry("celeste_shining_wonder", orb_positive, orb_negative)

-- Strix Salvo: arc off each missile (m_mapProjectileInfos.primary, ability_deadpack_chargeblast:
-- m_flGravityScale 0.75, m_particle airheart_missile.vpcf), ExplosionRadius 3.5 m. land_window 0.3
-- hides the float over his head; a missile that sticks is a mine its aura particle marks.
local function salvo_positive(spell)
    local MISSILE = "particles/abilities/airheart/airheart_missile.vpcf"
    local danny = actor(260, 10000, 0, 0, "ability_deadpack_chargeblast", { ExplosionRadius = 3.5 })
    local missile, _, pos = mkproj(261, 10000, 0, 250, MISSILE)
    local w = world(spell, danny, { missile })
    -- rising over his head at 300 u/s: impact is over a second off, nothing is drawn
    for _ = 1, 12 do
        pos[3] = pos[3] + 300 / 60
        step(w)
        assert(#REC.tris == 0 and #REC.lines == 0, "strix salvo: drawn while floating over his head")
    end
    -- the dive in: v = (2000, -1000) from 300 u up under 0.75 * 800 u/s^2 lands 0.277 s and 554 u on
    local dive
    dive, _, pos = mkproj(266, 10300, 0, 300, MISSILE)
    w = world(spell, danny, { dive })
    local vx, vz, g = 2000, -1000, nil
    for _ = 1, 16 do
        pos[1], pos[3], vz = pos[1] + vx / 60, pos[3] + vz / 60, vz - 600 / 60
        g = step(w) or g
        if g and g.land and #REC.tris > 0 then break end
    end
    assert(g and g.land, "strix salvo: no landing predicted on the way in")
    assert(math.abs((g.land.x - 10854) / UPM) < 0.25, "strix salvo: landing not where the missile lands")
    assert_marker(g.land.x, 4, 3.5, "strix salvo")

    -- a missile stuck in the ground: its mine aura draws the area while it lives, landing_window or not
    local danny2 = actor(262, 12000, 0, 0, "ability_deadpack_chargeblast", { ExplosionRadius = 3.5 })
    local stuck = mkproj(263, 12400, 0, 0, MISSILE)
    local w2 = world(spell, danny2, { stuck })
    X.track_particle({ name = "particles/abilities/airheart/airheart_mine_aoe.vpcf", entity = stuck, index = 60 })
    X.update_particle({ index = 60, control_point = 0, position = Vector(12400, 0, 0) })
    -- the stuck missile and the mine's particle are two groups: draw them all, as the game does
    local function draw_all()
        step(w2)
        clear_rec()
        for _, r in pairs(S.list) do if r.spell == spell then D.draw_entity(r, viewer) end end
    end
    for _ = 1, 10 do draw_all() end
    assert_marker(12400, 0, 3.5, "strix salvo mine")
    X.destroy_particle({ index = 60 }) -- the mine goes off
    for _ = 1, 2 do draw_all() end
    assert(#REC.tris == 0 and #REC.lines == 0, "strix salvo: mine still drawn after it went off")
end

local function salvo_negative(spell)
    local danny = actor(264, 14000, 0, 0, "ability_deadpack_chargeblast", {})
    for i, name in ipairs({ "particles/abilities/airheart/airheart_missile_explosion.vpcf",       -- m_strWeaponImpactEffect
                            "particles/abilities/airheart/airheart_missile_range_preview_path.vpcf" }) do -- m_RangeIndicatorParticle
        local p = mkproj(264 + i, 14200, 0, 40, name)
        run(world(spell, danny, { p }), 0.4)
        assert(count_groups(spell) == 0, "strix salvo: " .. name:match("[^/]+$") .. " detected")
    end
end

entry("danny_strix_salvo", salvo_positive, salvo_negative)

-- Chimera Mk1: arc off Danny himself while a jetpacking modifier is on (m_JetpackingModifier /
-- m_JetpackingVTOLModifier, ability_deadpack_rocketeer), gravity_scale 0, Radius 8 m. The dive is
-- angled along his aim, so the landing is ahead of him, not below.
local function chimera_positive(spell)
    local danny, st, pos = actor(270, 16000, 0, 800, "ability_deadpack_rocketeer", { Radius = 8 })
    local w = world(spell, danny)
    st.mods = { mod("jetpackingvtol") }
    local i, v, g = 0, 0, nil
    for _ = 1, 80 do
        i = i + 1
        if i > 6 then v = 1500 end -- the hover, then a 45 degree dive
        pos[1], pos[3] = pos[1] + v / 60, pos[3] - v / 60
        g = step(w) or g
        if g and g.land and #REC.tris > 0 then break end
    end
    assert(g and g.land, "chimera mk1: no landing predicted")
    -- 45 degrees down from 800 u up: he is followed BODY_Z 36 u above his feet, so it lands
    -- 836 u on from where the dive began
    assert(math.abs(g.land.x - 16836) < 2 and math.abs(g.land.y) < 2, "chimera mk1: dive not landing along his aim")
    assert(pos[3] < 1500 * 0.3 + 1, "chimera mk1: drawn before the last 0.3 s")
    assert_marker(16836, 4, 8, "chimera mk1")
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

-- Landing Marker and Trajectory only hide the drawing: Evade still gets every area. The positive
-- cases' own asserts expect the drawing, so they may fail here; only the areas are checked
switch_off.sp_land, switch_off.sp_arc = true, true
for _, f in ipairs(FIX) do
    S.zones = {}
    pcall(f.positive, by_id[f.id])
    assert(#S.zones > 0, f.id .. ": Landing Marker and Trajectory off, and Evade gets no danger area")
end
switch_off.sp_land, switch_off.sp_arc = nil, nil
print("OK: with Landing Marker and Trajectory off, every entry still gives Evade its danger area")


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
local DASH = 5 * UPM / 0.25 / 60    -- units a frame of a 5 m, 0.25 s dash
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
    if cmd.tapped == 17592186044416 then dash_frames = 15 end -- a dash: 0.25 s at dash speed
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
    for i = 1, 600 do
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

-- and the dodge takes over: Bashdown's 4 m slam, 1 s out, escaped on the dodge's own keys
local start = { hero_pos[1], hero_pos[2] }
_, hit = sim_run(by_id["billy_bashdown"], true)
local moved = math.sqrt((hero_pos[1] - start[1]) ^ 2 + (hero_pos[2] - start[2]) ^ 2)
assert(not hit and moved > 4 * UPM - 1.5 * UPM, ("sim: the dodge didn't escape Bashdown (moved %.1f m)"):format(moved / UPM))
print(("OK: sim scores hits and dodges; the dodge walked %.1f m out of Bashdown on its own"):format(moved / UPM))

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
for _ = 1, 12 do
    S.now, S.rt = S.now + 1 / 60, S.rt + 1 / 60
    SIM.update()
end
assert(#S.sims == 1, "sim: next spell not cast after its interval")
S.sims, nums.sp_sim_gap = {}, 1.5
print("OK: sim: the next spell is cast an Interval after the last is over")

-- Shining Wonder winds up 0.75 s before the orb flies: in that time the dodge walks out of its lane
for _ = 1, 3 do
    _, hit = sim_run(by_id["celeste_shining_wonder"], true)
    assert(not hit, "sim: Shining Wonder hit through its 0.75 s wind-up")
end
print("OK: sim: Shining Wonder's wind-up is walked out of before the orb flies")

-- an Uppercut cast from between you and the camera, its caster off screen: the fan is still filled,
-- in rings out from him, not only its rim (fan() fills from the centre, which didn't project)
local cut = SIM.cast(S.me:get_origin(), by_id["bebop_exploding_uppercut"])
local w2s = Render.WorldToScreen
Render.WorldToScreen = function(v)
    local s = w2s(v)
    return s, (v.x - cut.from.x) ^ 2 + (v.y - cut.from.y) ^ 2 > 60 ^ 2
end
S.zones = {}
clear_rec()
D.draw_sim(cut)
Render.WorldToScreen = w2s
assert(#REC.tris > 100, "sim: a cone with its caster off screen not filled (" .. #REC.tris .. " triangles)")
print(("OK: a cone whose caster is off screen is still filled (%d triangles)"):format(#REC.tris))
ui.sp_sim.on = false
end)()

-- ---- walk, dash or nothing, by when the area hits you (walking 7 m/s, a 5 m dash in 0.25 s) ----
;(function()
hero_pos[1], hero_pos[2] = -3000, 0
local stamina = 2
HERO_LIB.get_stamina = function() return stamina end
HERO_LIB.is_on_ground = function() return true end
local function plan(zones)
    S.zones, S.dodge, S.now = zones, nil, 5000
    E.update()
    return S.dodge
end
local function blast(r, t) return { { kind = "circle", x = -3000, y = 0, z = 0, r = r, at = 5000 + t } } end
local function off(p) return math.sqrt((p.x + 3000) ^ 2 + p.y ^ 2) end

local p = plan(blast(200, 2)) -- 5 m, 2 s out: ~0.9 s of walking does it
assert(p.mode == "walk", "decide: walk, got " .. tostring(p.mode))
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
nums.sp_react, nums.sp_margin = nil, 2
p = plan(blast(118, 2))
assert(p.mode == "walk" and off(p.goal) >= 118 + 2 * UPM - 20, "tuning: Safety Margin not kept, got " .. off(p.goal))
nums.sp_margin = nil
p = plan(blast(118, 0.2))     -- 0.2 s out: even a dash is too slow
assert(p.mode == "none", "decide: tried to beat a 0.2 s blast")
p = plan(blast(276, 0.45))    -- 7 m, 0.45 s: a 5 m dash still ends inside it
assert(p.mode == "none" and p.why:find("ends clear", 1, true), "decide: dashed into the same blast")
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
lane.px = -2500 -- the shot is 5 m past you
assert(guarded(8).down == 8, "guard: a shot already past you still blocked W")
-- Evade Shapes: with circles off, a blast on you is left alone (still drawn); a lane is still dodged
local shapes_on = { ["Circular Spells"] = false, ["Linear Spells"] = true, ["Cone Spells"] = true }
ui.sp_dodge_shapes = { Get = function(_, name) return shapes_on[name] end }
assert(plan(blast(200, 2)) == nil, "shapes: dodged a circle with Circular Spells off")
orb.delay = 0.6
p = plan({ orb })
assert(p and p.mode == "walk", "shapes: a lane not dodged with only circles off")
orb.delay = nil
ui.sp_dodge_shapes = nil
assert(plan(blast(200, 2)).mode == "walk", "shapes: unreadable setting not taken as on")
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
cmd = mkcmd(0)
E.steer(cmd)
assert(not cmd.taps, "counterspell: parried twice")
cs_ready = false
p = plan(blast(276, 0.9))
assert(p.mode == "none" and p.why:find("Counterspell on cooldown", 1, true), "counterspell: used on cooldown")
cs_ready = true
-- unticked in the Evade Tools card, it is never used, ready or not
ui.sp_evade_items = { Get = function(_, name) return name ~= "Counterspell" end }
p = plan(blast(276, 0.9))
assert(p.mode == "none" and p.why:find("Counterspell turned off", 1, true), "counterspell: used while turned off")
ui.sp_evade_items = nil
assert(plan(blast(276, 0.9)).mode == "counterspell", "counterspell: unreadable Evade Tools setting not taken as on")
-- Tuning: a 0.1 s Parry Lead waits for it, and a 0.3 s Reaction Time doesn't call 0.12 s too late
nums.sp_react, nums.sp_parry_lead = 0.3, 0.1
p = plan(blast(276, 0.4))
cmd = mkcmd(0)
E.steer(cmd)
assert(p.mode == "counterspell" and not cmd.taps, "tuning: parried 0.4 s early with a 0.1 s Parry Lead")
p = plan(blast(276, 0.12))
assert(p.mode == "counterspell", "tuning: 0.12 s called too late to parry under a 0.3 s Reaction Time, got " .. p.mode)
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
HERO_LIB.is_ability_ready, S.me.get_abilities = real_ready, nil
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
-- the 22.2 m range and says the orb leaves in a quarter second
st.cast = true
local l
for _ = 1, 30 do l = lanes()[1] or l end
assert(l, "wind-up: no lane while Shining Wonder charges")
assert(l.bx > l.x and math.abs(l.by - l.y) < 1 and math.abs((l.bx - l.x) / UPM - 22.2) < 0.1,
    ("wind-up: lane not 22.2 m along her aim (%.1f m)"):format((l.bx - l.x) / UPM))
assert(l.speed == 1820 and l.delay and math.abs(l.delay - 0.25) < 0.05,
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

-- ---- aimed landings: Seismic Impact and Chimera Mk1 come down where the hero aims, Strix Salvo
-- where Danny aimed it; the spot is marked while the flight is still held back ----
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

-- Strix Salvo: a missile first seen over Danny, who aims 20 deg down along +x: it lands where that
-- aim meets the floor (70 u eye height / tan 20 = 192 u on), timed at the missile's 3000 u/s
local salvo = by_id["danny_strix_salvo"]
local danny = actor(321, -20000, 0, 0, "ability_deadpack_chargeblast", { ExplosionRadius = 3.5 })
danny.m_angEyeAngles = { pitch = 20, yaw = 0 }
local missile, _, mpos = mkproj(322, -20000, 0, 250, "particles/abilities/airheart/airheart_missile.vpcf")
w = world(salvo, danny, { missile })
S.zones = {}
for _ = 1, 3 do
    mpos[3] = mpos[3] + 300 / 60
    S.zones = {}
    step(w)
end
c = circles()
local spot = -20000 + 70 / math.tan(math.rad(20))
assert(#c == 1 and math.abs(c[1].x - spot) < 3 and c[1].at and math.abs(c[1].at - S.now - (spot + 20000) / 3000) < 0.06,
    "aimed landing: Strix Salvo not marked where Danny aimed, timed at 3000 u/s")
danny.m_angEyeAngles.pitch = 50 -- he turns his aim once it is out: the missile keeps its spot
S.zones = {}
step(w)
c = circles()
assert(#c == 1 and math.abs(c[1].x - spot) < 3, "aimed landing: Strix Salvo followed his aim after launch")
print("OK: aimed landings: Abrams' crash marked where he aims and timed, not his leap; Strix where it was aimed")

-- the simulator: during Danny's Chimera hover the dodge sees an area with no hit time and walks; a
-- long hover is escaped. Abrams isn't marked while he hovers, only as he crashes, timed. A Strix
-- salvo is marked from launch
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
local walked, hit
for _ = 1, 300 do
    S.now, S.rt = S.now + 1 / 60, S.rt + 1 / 60
    local before = SIM.score.hit
    SIM.update()
    hit = hit or SIM.score.hit > before
    E.update()
    walked = walked or (S.dodge and S.dodge.mode == "walk" and not S.dodge.t)
    S.zones = {}
    for _, r in ipairs(S.sims) do D.draw_sim(r) end
    local cmd = mkcmd(0)
    E.steer(cmd)
    if cmd.down ~= 0 then
        local mx, my = -cmd.leftmove, cmd.forwardmove
        local n = math.sqrt(mx * mx + my * my)
        hero_pos[1], hero_pos[2] = hero_pos[1] + mx / n * 5, hero_pos[2] + my / n * 5
    end
    if #S.sims == 0 then break end
end
assert(walked and not hit, "sim: Danny's 2.5 s Chimera hover not walked out of")
r = SIM.cast(S.me:get_origin(), salvo)
assert(r.aim_spot and r.aim_at and math.abs(r.aim_at - S.now - r.T) < 1e-6, "sim: Strix Salvo not marked from launch")
ui.sp_sim.on = false
print("OK: sim: walked out from under Danny's hover, Abrams marked only as he crashes, Strix from its launch")
end)()
