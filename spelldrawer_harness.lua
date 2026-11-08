-- headless harness: loads all six files, then drives the real detect and draw code with fake
-- heroes, projectiles and particles built from the game's own vdata numbers, so cones, auras,
-- dives, dashes, lobs, bullets and the Debug Mode measurements can be checked without launching
-- the game. Run it from the repo root: lua spelldrawer_harness.lua
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

-- an enemy Celeste whose abilities read as missing casts Light Eater: the cast particle comes with
-- no entity, only a position at her hand, and must still start the fan on her
local eater
for _, s in ipairs(SPELLS) do if s.id == "celeste_light_eater" then eater = s end end
assert(eater, "Light Eater entry missing")
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
local far = pawn(10, function() return Vector(0, 0, 0) end)
S.me = far
entity_list.get_all = function() return { far, celeste } end
entity_list.by_handle = function() return nil end
S.groups, S.events, S.next_scan, S.now, S.rt = {}, {}, 0, 50, 50
X.track_particle({ name = "particles/abilities/unicorn/unicorn_radiant_blast.vpcf", index = 77 })
X.update_particle({ index = 77, control_point = 0, position = Vector(1010, 20, 60) })
local fans = 0
Render.FilledTriangle = function() fans = fans + 1 end
X.scan()
local eg
for _, rec in pairs(S.groups) do if rec.spell == eater then eg = rec end end
assert(eg and eg.owner == celeste and eg.caster == celeste, "Light Eater not pinned on the enemy Celeste")
assert(pcall(D.draw_entity, eg, far) and fans > 0, "no fan drawn for the enemy Celeste")
print("OK: an ownerless Light Eater particle goes to the Celeste standing where it started")

-- timing: the fan runs from the particle's creation for the 0.3 s cast delay, then goes, even
-- though the particle (and so the group) is still around
local function fan_at(t)
    S.now, S.rt, fans = t, t, 0
    X.update_particle({ index = 77, control_point = 0, position = Vector(1010, 20, 60) })
    X.scan()
    for _, rec in pairs(S.groups) do if rec.spell == eater then eg = rec end end
    pcall(D.draw_entity, eg, far)
    return fans > 0
end
assert(eg.cone_at == 50, "fan clock not started at the particle's creation: " .. tostring(eg.cone_at))
assert(fan_at(50.25), "fan missing inside the cast delay")
assert(not fan_at(50.35), "fan still drawn after the blast went off")
print("OK: Light Eater's fan lasts the 0.3 s cast delay and ends when the blast goes off")

-- point-blank: you stand closer to where her cast started than she does. Your abilities read and
-- Light Eater isn't one of them, so the cast still goes to her, not to you (yours would be hidden)
local your_ab = { get_name = function() return "citadel_ability_uppercut" end, get_cooldown = function() return 0 end }
local you = pawn(13, function() return Vector(1015, 25, 30) end, nil, your_ab)
S.me = you
entity_list.get_all = function() return { you, celeste } end
S.groups, S.events, S.next_scan, S.now, S.rt = {}, {}, 0, 60, 60
X.track_particle({ name = "particles/abilities/unicorn/unicorn_radiant_blast.vpcf", index = 78 })
X.update_particle({ index = 78, control_point = 0, position = Vector(1010, 20, 60) })
X.scan()
eg = nil
for _, rec in pairs(S.groups) do if rec.spell == eater then eg = rec end end
assert(eg and eg.owner == celeste, "a point-blank Light Eater was handed to you")
S.me = far
print("OK: a point-blank Light Eater stays with Celeste, not the closer hero who can't cast it")

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
