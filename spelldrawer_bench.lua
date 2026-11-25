if callback then return end -- Umbrella runs every .lua in this folder: this one is run by hand
-- headless bench: the frame's parts timed over a busy scripted scene, for a perf change's before and
-- after when no in-game Profile capture exists. Eleven heroes cast their registry spells round-robin
-- (particles, particle events, modifiers, wind-ups, projectiles, class carriers) and wear item and
-- pickup modifiers all along, a few thousand other entities fill the walk, the Spell Simulator casts at you so the dodge plans and steers, and
-- each frame runs in the game callbacks' order (spelldrawer.lua): scan, modifiers, projectiles, sim,
-- dodge, then the drawing, then steer at 64 ticks a second.
-- Run it from the repo root: lua spelldrawer_bench.lua [frames]
-- Each part's ms per frame (mean, max) and KB allocated per frame: the collector is stopped while a
-- frame runs and run between frames, untimed, so the times hold no collector pauses and the KB are
-- exact. The fingerprint line counts what was drawn and pressed: a change that only makes a part
-- faster leaves it as it was.
-- os.clock ticks at 1 ms on Windows: set a global chronos with a nanotime() in seconds (as Umbrella
-- has) for exact maxima, e.g. lua -e "chronos=require'hrclock'" spelldrawer_bench.lua
package.path = "./?.lua;" .. package.path
local FRAMES, WARMUP = tonumber(arg and arg[1]) or 3000, 300
local FPS, TICK = 100, 1 / 64
local clock = chronos and chronos.nanotime or os.clock
math.randomseed(1)

-- game API stand-ins ------------------------------------------------------------------------------
local ui = {}
package.loaded["spelldrawer_menu"] = { ui = ui }
local U = require("spelldrawer_util")
local DEF = U.CFG.DEFAULTS
local set = { sp_sim = true, sp_sim_gap = 1.5, sp_profile = false }
local function control(k)
    local v = set[k]
    if v == nil then v = DEF[k] end
    if type(v) == "table" then
        local on = {}
        for _, n in ipairs(v) do on[n] = true end
        return { Get = function(_, n) return n == nil or on[n] == true end, IsDown = function() return false end }
    end
    return { Get = function() return v end, IsDown = function() return false end }
end
setmetatable(ui, { __index = function(t, k) local c = control(k) rawset(t, k, c) return c end })
Enum = { FontCreate = { FONTFLAG_ANTIALIAS = 16 } }

Vector = function(x, y, z) return { x = x, y = y, z = z } end
Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
Vec2 = function(x, y) return { x = x, y = y } end
local prims = { line = 0, tri = 0, circle = 0, text = 0 }
Render = {
    LoadFont = function() return 1 end,
    WorldToScreen = function(v) return Vec2(960 + v.x * 0.1, 540 - v.y * 0.1), true end,
    Line = function() prims.line = prims.line + 1 end,
    FilledTriangle = function() prims.tri = prims.tri + 1 end,
    FilledCircle = function() prims.circle = prims.circle + 1 end,
    Text = function() prims.text = prims.text + 1 end,
}
convar = { sv_gravity = { float = function() return 800 end } }
-- a flat floor at z = 0 with one long wall, solid at x >= 1500
local WALL = 1500
local function nohit() return nil end
trace = { line = function(a, b)
    if a.z ~= b.z then
        if a.x >= WALL then return { fraction = 0, hit_entity = nohit } end
        return { fraction = math.max(0, math.min(1, a.z / (a.z - b.z))), hit_entity = nohit }
    end
    if b.x < WALL then return { fraction = 1, hit_entity = nohit } end
    return { fraction = a.x >= WALL and 0 or (WALL - a.x) / (b.x - a.x), hit_entity = nohit }
end }
utils = { get_camera_angles = function() return { pitch = 0, yaw = 90 } end }

-- entities: one metatable, so a method call is a lookup and a call as in the game; positions,
-- particle and modifier lists come back as new tables each read, as the game's do
local Ent = {}
Ent.__index = Ent
function Ent:valid() return not self.dead end
function Ent:is_alive() return true end
function Ent:is_dormant() return false end
function Ent:is_visible() return true end
function Ent:get_handle() return self.h end
function Ent:get_class_name() return self.cls end
function Ent:get_vdata_class_name() return self.vdata or self.cls end
function Ent:get_origin() return Vector(self.x, self.y, self.z) end
function Ent:get_velocity() return Vector(self.vx or 0, self.vy or 0, 0) end
function Ent:get_angles() local f = self.fwd return { GetForward = function() return Vector(f[1], f[2], 0) end } end
function Ent:get_particles()
    local out = {}
    for i, p in ipairs(self.particles) do out[i] = p end
    return out
end
function Ent:get_modifiers()
    local out = {}
    for i, m in ipairs(self.mods) do out[i] = m end
    return out
end
function Ent:get_ability_by_slot(slot) return self.slots and self.slots[slot + 1] end
function Ent:get_abilities() return self.slots or {} end
function Ent:has_item_by_id() return false end

local Ab = {}
Ab.__index = Ab
function Ab:get_name() return self.name end
function Ab:get_scaled_property() return nil end
function Ab:get_cooldown() return 0 end
function Ab:can_be_executed() return 0 end

local all, by_h, by_cls, next_h = {}, {}, {}, 1
local function spawn(e)
    setmetatable(e, Ent)
    e.h, next_h = next_h, next_h + 1
    e.particles, e.mods, e.fwd = e.particles or {}, e.mods or {}, e.fwd or { 1, 0 }
    all[#all + 1], by_h[e.h] = e, e
    by_cls[e.cls] = by_cls[e.cls] or {}
    table.insert(by_cls[e.cls], e)
    return e
end
local function despawn(e)
    e.dead, by_h[e.h] = true, nil
    for i = #all, 1, -1 do if all[i] == e then table.remove(all, i) break end end
    local l = by_cls[e.cls]
    for i = #l, 1, -1 do if l[i] == e then table.remove(l, i) break end end
end
local function copy(l) local out = {} for i, e in ipairs(l) do out[i] = e end return out end
entity_list = {
    get_all = function() return copy(all) end,
    by_class_name = function(cls) return copy(by_cls[cls] or {}) end,
    by_handle = function(h) return by_h[h] end,
}
HERO_LIB = {
    is_same_team = function(a, b) return a ~= nil and b ~= nil and a.team == b.team end,
    get_hero_id = function(p) return p.hero_id end,
    is_ability_in_cast_delay = function(ab) return ab ~= nil and ab.cast_until ~= nil and U.state.now < ab.cast_until end,
    is_channeling_ability = function() return false end,
    is_channeling_any_ability = function() return false end,
    is_ability_ready = function() return true end,
    is_ability_in_cd = function() return false end,
    is_on_ground = function() return true end,
    is_any_dashing = function() return false end,
    get_stamina = function() return 3 end,
    get_health = function() return 1000 end,
    get_health_percent = function() return 100 end,
    cast_ability = function() end,
}

local SPELLS = require("spelldrawer_spells")
for _, s in ipairs(SPELLS) do s.ui = { Get = function() return true end } end
local X = require("spelldrawer_detect")
local D = require("spelldrawer_draw")
local E = require("spelldrawer_evade")
local SIM = require("spelldrawer_sim")
local S = U.state
local UPM = U.CFG.UNITS_PER_M

-- the scene ---------------------------------------------------------------------------------------
local me = spawn({ cls = "C_CitadelPlayerPawn", team = 2, hero_id = 1, x = 0, y = 0, z = 0, m_iTeamNum = 2 })
-- each hero with spells in the registry, his spells in registry order
local heroes, by_hero = {}, {}
for _, s in ipairs(SPELLS) do
    if s.hero_id and s.hero_id ~= me.hero_id then
        if not by_hero[s.hero_id] then by_hero[s.hero_id] = {} heroes[#heroes + 1] = s.hero_id end
        table.insert(by_hero[s.hero_id], s)
    end
end
table.sort(heroes)
-- what each hero wears all match long, besides his spells': item and pickup modifiers, by names
-- seen on enemies in a match's Debug Mode log. One that names a registry modifier is left out
local WORN = {}
for _, n in ipairs({ "hp_permanent_pickup_lv3/modifier_permanent_pickup", "firerate_permanent_pickup_lv3/modifier_permanent_pickup",
    "wp_permanent_pickup_lv3/modifier_permanent_pickup", "spirit_permanent_pickup_lv3/modifier_permanent_pickup",
    "cd_permanent_pickup_lv3/modifier_permanent_pickup", "bulletresist_permanent_pickup_lv3/modifier_permanent_pickup",
    "spiritresist_permanent_pickup_lv3/modifier_permanent_pickup", "ammo_permanent_pickup_lv3/modifier_permanent_pickup",
    "upgrade_bullet_armor_reduction_aura/modifier_bullet_armor_reduction_aura", "upgrade_tech_overflow/modifier_tech_overflow_proc_watcher",
    "upgrade_weapon_backstabber/modifier_backstabber_watcher", "upgrade_magic_shock/modifier_tech_burst_proc",
    "npc_boss_tier2_weak/stat_tracker_aura/modifier_tier2_stat_tracker", "modifier_near_climbable_rope",
    "citadel_ability_zip_line/modifier_zipline_knockdown_immune", "ability_stacking_damage/modifier_passive_haze_stacking_damage",
    "upgrade_acolytes_glove/modifier_acolytes_glove", "upgrade_boxing_glove/modifier_boxing_glove",
    "medic_trooper_aoe_health_pickup_amber/regen", "modifier_citadel_uihudmessage" }) do
    local hit = false
    for _, s in ipairs(SPELLS) do
        if s.modifier and n:lower():find(s.modifier:lower(), 1, true) then hit = true end
    end
    if not hit then WORN[#WORN + 1] = { get_name = function() return n end } end
end
local casters = {}
for i = 1, 11 do
    local id = heroes[1 + (i - 1) * math.floor(#heroes / 11)]
    local slots = {}
    for k, s in ipairs(by_hero[id]) do
        if k <= 4 and s.ability then slots[#slots + 1] = setmetatable({ name = s.ability }, Ab) end
    end
    local a = i * 2 * math.pi / 11
    local d = (8 + (i % 4) * 6) * UPM
    local c = spawn({ cls = "C_CitadelPlayerPawn", team = i <= 6 and 3 or 2, hero_id = id, slots = slots,
                      x = math.cos(a) * d, y = math.sin(a) * d, z = 0, a = a, d = d, m_iTeamNum = i <= 6 and 3 or 2,
                      spells = by_hero[id], next_cast = 0.3 * i, k = 0 })
    for _, m in ipairs(WORN) do table.insert(c.mods, m) end
    casters[#casters + 1] = c
end
-- the rest of the map: props, lights and triggers by the thousand, troopers, turrets
local rnd = math.random
for i = 1, 3600 do
    spawn({ cls = ("C_Prop_%02d"):format(i % 48), x = rnd(-9000, 9000), y = rnd(-9000, 9000), z = rnd(0, 300) })
end
local troopers = {}
for i = 1, 160 do
    local tr = spawn({ cls = "C_NPC_Trooper", team = i % 2 + 2, m_iTeamNum = i % 2 + 2,
                       x = rnd(-6000, 6000), y = rnd(-6000, 6000), z = 0, vx = rnd(-150, 150), vy = rnd(-150, 150) })
    troopers[#troopers + 1] = tr
end
for _ = 1, 24 do spawn({ cls = "C_NPC_TrooperNeutral", team = 4, m_iTeamNum = 4, x = rnd(-7000, 7000), y = rnd(-7000, 7000), z = 0 }) end
for i = 1, 12 do spawn({ cls = "C_NPC_TrooperBoss", team = i % 2 + 2, m_iTeamNum = i % 2 + 2, x = rnd(-8000, 8000), y = rnd(-8000, 8000), z = 0 }) end
for i = 1, 4 do spawn({ cls = "C_NPC_Boss_Tier2", team = i % 2 + 2, m_iTeamNum = i % 2 + 2, x = rnd(-8000, 8000), y = rnd(-8000, 8000), z = 0 }) end

-- each part's time and allocation, while measuring; S.prof_add takes the scan's own steps
local parts, order = {}, {}
local function add(name, dt, kb)
    local p = parts[name]
    if not p then p = { sum = 0, max = 0, kb = 0, n = 0, each = {} } parts[name] = p order[#order + 1] = name end
    p.sum, p.max, p.kb, p.n = p.sum + dt, math.max(p.max, dt), p.kb + kb, p.n + 1
    p.each[p.n] = dt
end
local measuring = false
local function timed(name, fn, ...)
    local m0, t0 = collectgarbage("count"), clock()
    local ok, err = pcall(fn, ...)
    local dt, kb = clock() - t0, collectgarbage("count") - m0
    if measuring then add(name, dt, kb) end
    if not ok then error(name .. ": " .. tostring(err), 0) end
end
S.prof_add = function(name, dt) if measuring then add(name, dt, 0) end end

-- casts: a hero's next spell every 2 to 4 s: its wind-up, its particle on him and as an event, its
-- modifier, and a flying entity for a projectile or a class carrier; each gone 1.2 s on
local live, pindex, events = {}, 0, {}
local function pname(key) return "particles/abilities/bench/" .. key end
local function cast(c, now)
    c.k = c.k % #c.spells + 1
    local s = c.spells[c.k]
    local fx, fy = (me.x - c.x), (me.y - c.y)
    local n = math.sqrt(fx * fx + fy * fy)
    fx, fy = fx / n, fy / n
    c.fwd = { fx, fy }
    for _, ab in ipairs(c.slots) do if ab.name == s.ability then ab.cast_until = now + 0.3 end end
    local key = s.particles and s.particles[1]
    local p = key and { name = pname(key), control_points = { { origin = Vector(c.x, c.y, c.z) } } }
    if p then table.insert(c.particles, p) end
    local mod = s.modifier and { get_name = function() return s.modifier end }
    if mod then table.insert(c.mods, mod) end
    local fly
    if s.projectile or s.classes then
        local speed = s.speed or 1500
        fly = spawn({ cls = s.classes and ("C_" .. s.classes[1]) or "C_CitadelProjectile", x = c.x, y = c.y, z = 40,
                      vx = fx * speed, vy = fy * speed, m_hOwnerEntity = c.h, team = c.team,
                      particles = s.projectile and { { name = pname(s.projectile), control_points = {} } } or {} })
    end
    local evs = {}
    if key then
        pindex = pindex + 1
        evs[#evs + 1] = { index = pindex, name = pname(key), entity = c }
    end
    if fly and s.projectile then
        pindex = pindex + 1
        evs[#evs + 1] = { index = pindex, name = pname(s.projectile), entity = fly }
    end
    for _, ev in ipairs(evs) do
        timed("particle create", X.track_particle, ev)
        events[#events + 1] = ev
    end
    live[#live + 1] = { c = c, p = p, mod = mod, fly = fly, evs = evs, til = now + 1.2 }
end
local function expire(now)
    for i = #live, 1, -1 do
        local l = live[i]
        if now >= l.til then
            for k, v in ipairs(l.c.particles) do if v == l.p then table.remove(l.c.particles, k) break end end
            for k, v in ipairs(l.c.mods) do if v == l.mod then table.remove(l.c.mods, k) break end end
            if l.fly then despawn(l.fly) end
            for _, ev in ipairs(l.evs) do
                timed("particle destroy", X.destroy_particle, { index = ev.index })
                for k, v in ipairs(events) do if v == ev then table.remove(events, k) break end end
            end
            table.remove(live, i)
        end
    end
end

-- one frame ---------------------------------------------------------------------------------------
local function mkcmd()
    local cmd = { viewangles = { yaw = 90 }, forwardmove = 0, leftmove = 0, down = 0 }
    function cmd:get_buttons_down_mask() return self.down end
    function cmd:get_orig_buttons_down_mask() return self.down end
    function cmd:press(m) self.down = self.down | m end
    function cmd:release(m) self.down = self.down & ~m end
    function cmd:tap(m) self.tapped = m end
    function cmd:clear_button_all_states() end
    return cmd
end

local fp = { keys = 0, moves = 0, zones = 0, groups = 0, plans = 0 }
local t, tick_acc = 100, 0
local function frame()
    local dt = 1 / FPS
    t = t + dt
    U.tick(t)
    S.rt = S.rt + dt
    S.me = me
    for _, c in ipairs(casters) do
        c.a = c.a + 0.3 * dt
        c.x, c.y = me.x + math.cos(c.a) * c.d, me.y + math.sin(c.a) * c.d
        if t >= c.next_cast + 100 then
            cast(c, t)
            c.next_cast = c.next_cast + 2 + (c.h % 3)
        end
    end
    for _, tr in ipairs(troopers) do tr.x, tr.y = tr.x + tr.vx * dt, tr.y + tr.vy * dt end
    for _, l in ipairs(live) do
        local f = l.fly
        if f then f.x, f.y = f.x + f.vx * dt, f.y + f.vy * dt end
    end
    expire(t)
    for _, ev in ipairs(events) do
        local e = ev.entity
        timed("particle update", X.update_particle, { index = ev.index, control_point = 0, has_position = true,
            position = Vector(e.x, e.y, e.z) })
    end
    timed("scan", X.scan)
    timed("modifiers", X.track_modifiers)
    timed("projectiles", X.track_projectiles, dt)
    timed("sim", SIM.update)
    timed("dodge", E.update)
    S.zones = {}
    timed("draw entity", function() for _, rec in pairs(S.list) do D.draw_entity(rec, me) end end)
    timed("draw sim", function() for _, rec in ipairs(S.sims) do D.draw_sim(rec) end end)
    if measuring then
        fp.zones, fp.plans = fp.zones + #S.zones, fp.plans + (S.dodge and 1 or 0)
        for _ in pairs(S.list) do fp.groups = fp.groups + 1 end
    end
    tick_acc = tick_acc + dt
    while tick_acc >= TICK do
        tick_acc = tick_acc - TICK
        local cmd = mkcmd()
        timed("steer", E.steer, cmd)
        if cmd.down ~= 0 then
            local mx, my = -cmd.leftmove, cmd.forwardmove
            local len = math.sqrt(mx * mx + my * my)
            if len > 0 then me.x, me.y = me.x + mx / len * 300 * TICK, me.y + my / len * 300 * TICK end
            if measuring then fp.moves = fp.moves + 1 end
        end
        if measuring then fp.keys = (fp.keys * 31 + cmd.down) % 1000000007 end
    end
end

-- the run -----------------------------------------------------------------------------------------
collectgarbage("collect")
collectgarbage("stop")
local wall0 = clock()
local frame_ms, frame_kb = {}, {}
for i = 1, WARMUP + FRAMES do
    measuring = i > WARMUP
    if i == WARMUP + 1 then for k in pairs(prims) do prims[k] = 0 end end
    local m0, t0 = collectgarbage("count"), clock()
    frame()
    if measuring then frame_ms[#frame_ms + 1], frame_kb[#frame_kb + 1] = (clock() - t0) * 1000, collectgarbage("count") - m0 end
    if i % 20 == 0 then collectgarbage("collect") collectgarbage("stop") end
end
collectgarbage("restart")

print(("bench: %d frames at %d fps of scene time (%d warm-up), %d entities, %d heroes, clock %s, %.1f s"):format(
    FRAMES, FPS, WARMUP, #all, #casters + 1, chronos and "chronos.nanotime" or "os.clock", clock() - wall0))
-- p99: the slowest 1% of a part's calls start there; steadier than the max, which a desktop's
-- other work can land on
print(("%-26s %9s %9s %9s %9s %9s"):format("part", "ms/frame", "max ms", "p99 ms", "KB/frame", "calls"))
table.sort(order, function(a, b) return parts[a].sum > parts[b].sum end)
for _, name in ipairs(order) do
    local p = parts[name]
    table.sort(p.each)
    print(("%-26s %9.3f %9.3f %9.3f %9.2f %9d"):format(name, p.sum * 1000 / FRAMES, p.max * 1000,
        p.each[math.ceil(p.n * 0.99)] * 1000, p.kb / FRAMES, p.n))
end
table.sort(frame_ms)
local sum, kb = 0, 0
for i = 1, #frame_ms do sum, kb = sum + frame_ms[i], kb + frame_kb[i] end
print(("%-26s %9.3f %9.3f %9.3f %9.2f"):format("whole frame", sum / FRAMES, frame_ms[#frame_ms],
    frame_ms[math.ceil(#frame_ms * 0.99)], kb / FRAMES))
print(("fingerprint: groups %d, zones %d, plans %d, moves %d, keys %d, lines %d, tris %d, circles %d, text %d, sims %d/%d"):format(
    fp.groups, fp.zones, fp.plans, fp.moves, fp.keys, prims.line, prims.tri, prims.circle, prims.text,
    SIM.score.dodged, SIM.score.hit))
