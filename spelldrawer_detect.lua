-- Spell Drawer | spell detection: matching, owners, casts, particle events (cone and dash triggers
-- included), landing prediction, the per-frame modifier poll for dashes and the periodic scan that
-- builds the draw list

local U = require("spelldrawer_util")
local SPELLS = require("spelldrawer_spells")
local ui = require("spelldrawer_menu").ui

local CFG, S = U.CFG, U.state
local try, field, valid, handle, log = U.try, U.field, U.valid, U.handle, U.log
local sqrt = math.sqrt

local X = {}

local function debug(msg, ...)
    if not ui.sp_debug:Get() or S.now - S.last_log < 0.5 then return end
    S.last_log = S.now
    log(msg, ...)
end

-- landing prediction ---------------------------------------------------------

local function gravity()
    local ok, g = pcall(function() return convar.sv_gravity:float() end)
    if ok and type(g) == "number" and g > 0 then return g end
    return CFG.GRAVITY_FALLBACK
end

local trace_line = U.trace_line

local DIVE_DOWN = math.sin(math.rad(20)) -- a dive heads at least 20 deg down (vdata m_flMinAimAngle 30, less some)

-- whether velocity `v` is a `dive_min_speed` spell's dive: fast and headed down
local function diving(v, spell)
    local speed = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    return speed >= spell.dive_min_speed and -v.z >= speed * DIVE_DOWN, speed
end

-- "arc" motion. o / v: projectile world position and velocity; ignore: the projectile entity, if any
local function predict_arc(o, v, spell, ignore)
    -- a flight drawn only as he dives (`dive_min_speed`): no guess while he hovers or hops
    if spell.dive_min_speed and not diving(v, spell) then return nil end
    local g = -gravity() * (spell.gravity_scale or 1)
    -- a straight dive that isn't heading down yet (the hop or hang before it): it lands straight
    -- below, unless the spell draws only near impact, where that guess is just a misplaced marker
    if g == 0 and v.z > -100 then
        if spell.land_window then return nil end
        v = Vector(0, 0, -1000)
    end
    if sqrt(v.x * v.x + v.y * v.y + v.z * v.z) < 100 then return nil end

    local dt = CFG.ARC_DT
    local pos = Vector(o.x, o.y, o.z)
    local vel = Vector(v.x, v.y, v.z)
    local path = { pos }

    for _ = 1, 250 do
        local nv = Vector(vel.x, vel.y, vel.z + g * dt)
        local np = Vector(pos.x + vel.x * dt, pos.y + vel.y * dt, pos.z + vel.z * dt + 0.5 * g * dt * dt)
        local tr = trace_line(pos, np, ignore)
        local frac = tr and field(tr, "fraction")
        if type(frac) == "number" and frac < 1 then
            local hit = Vector(
                pos.x + (np.x - pos.x) * frac,
                pos.y + (np.y - pos.y) * frac,
                pos.z + (np.z - pos.z) * frac + 4)
            path[#path + 1] = hit -- so the arc meets the landing marker
            return hit, path
        end
        pos, vel = np, nv
        path[#path + 1] = pos
        if pos.z < -12000 then return nil end
    end
    return nil
end

local DIVE_MIN_PITCH = 30 -- degrees down a hero must aim to dive (vdata m_flMinAimAngle)

-- where `hero` aims at the ground, within `aim_land` meters of his eyes: nil when his aim finds no
-- ground in reach, or, with `dive`, when he aims less than DIVE_MIN_PITCH down and can't dive yet
local function aim_spot(hero, spell, dive)
    local f = U.aim_dir(hero)
    local o = f and try(hero, "get_origin")
    if not o or dive and f.z > -math.sin(math.rad(DIVE_MIN_PITCH)) then return nil end
    local eye, reach = Vector(o.x, o.y, o.z + CFG.HEAD), spell.aim_land * CFG.UNITS_PER_M
    local to = Vector(eye.x + f.x * reach, eye.y + f.y * reach, eye.z + f.z * reach)
    local tr = trace_line(eye, to, hero)
    local frac = tr and field(tr, "fraction")
    if type(frac) ~= "number" or frac >= 1 then return nil end
    return Vector(eye.x + (to.x - eye.x) * frac, eye.y + (to.y - eye.y) * frac, eye.z + (to.z - eye.z) * frac + 4)
end

local LINE_STEPS = 24 -- the lane is split up so a partly off-screen lane still draws its visible part

-- "line" motion: straight on from o until the range left after travelling from start, or a wall.
-- The lane is drawn from `from` (default start); `through` skips the wall check.
local function predict_line(o, v, ignore, start, range, from, through, body)
    from = from or start
    local speed = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if speed < 100 then return nil end
    local left = range - sqrt((o.x - start.x) ^ 2 + (o.y - start.y) ^ 2 + (o.z - start.z) ^ 2)
    if left <= 0 then return nil end

    local k = left / speed
    local e = Vector(o.x + v.x * k, o.y + v.y * k, o.z + v.z * k)
    local tr = not through and trace_line(o, e, ignore)
    local frac = tr and field(tr, "fraction")
    if type(frac) == "number" and frac < 1 then
        -- a shot with a body (`body`, units) stops with its centre that far off the surface it hits:
        -- short of where its line meets it, by more the flatter it comes in, and never behind itself
        local n = body and field(tr, "normal")
        local cos = n and math.abs(n.x * v.x + n.y * v.y + n.z * v.z) / speed
        frac = frac - (cos and math.min(body / cos, left * frac) / left or 0)
        e = Vector(o.x + (e.x - o.x) * frac, o.y + (e.y - o.y) * frac, o.z + (e.z - o.z) * frac)
    end
    -- the lane runs from where the shot was fired, so a fast shot still shows its whole line
    local path = {}
    for i = 0, LINE_STEPS do
        local f = i / LINE_STEPS
        path[i + 1] = Vector(from.x + (e.x - from.x) * f, from.y + (e.y - from.y) * f, from.z + (e.z - from.z) * f)
    end
    return e, path
end

-- Projectile velocity comes from its movement between samples: entity:get_velocity() is local,
-- not world, velocity, so it can't seed the prediction. Samples are keyed by projectile source.
local samples = {}

local function proj_key(g)
    -- a hero tracked by a modifier gets a sample per spell: a loose match (Rising Ram's "charge"
    -- on Abrams) shared his sample and its min_speed wiped Shoulder Charge's lane
    if g.landing_ent and g.mod then return g.spell.id .. ":" .. tostring(handle(g.landing_ent)) end
    if g.landing_ent then return handle(g.landing_ent) end
    return g.landing_ev and ("ev" .. g.landing_ev)
end

local BODY_Z = CFG.BODY_Z -- a hero tracked by `modifier` is followed at mid-body, not at the feet

-- the projectile entity's origin, or for an entity-less projectile particle its moving CP0
local function projectile_pos(g)
    if valid(g.landing_ent) then
        local o = try(g.landing_ent, "get_origin")
        if o and g.mod then o = Vector(o.x, o.y, o.z + BODY_Z) end
        return o
    end
    local ev = g.landing_ev and S.events[g.landing_ev]
    local cp = ev and not ev.dead and ev.cps[0]
    return cp and cp.origin
end


-- runs every frame so the arc follows the projectile instead of the 0.25s scan
function X.track_projectiles(frame_time)
    S.rt = S.rt + (frame_time or 0)
    local seen = {}
    for _, g in pairs(S.list) do
        local spell = g.spell
        local key = (spell.motion == "arc" or spell.motion == "line") and proj_key(g)
        local p = key and projectile_pos(g)
        g.pos = p -- this frame's position, for the drawing: the path only moves on a velocity sample
        g.aim_spot, g.aim_at = nil, nil
        -- a line projectile that is gone takes its lane along: kept, it was drawn as a new shot
        -- from the lane's start, and Evade dodged a Gloom Bomb that had already gone off
        if key and not p and spell.motion == "line" then g.land, g.path = nil, nil end
        local s0 = p and g.mod and spell.motion == "arc" and not spell.dive_min_speed and samples[key]
        if s0 then
            -- a leap is over once he has been in the air and touches down again, even with the
            -- modifier still on him: Seismic Impact's stays ~0.7 s past the slam. Not for a
            -- `dive_min_speed` flight, whose speed tells the dive: one touch of a roof ended it
            local okg, ground = pcall(HERO_LIB.is_on_ground, g.landing_ent)
            if okg and ground == false then s0.airborne = true end
            if okg and ground == true and s0.airborne then s0.landed = true end
        end
        if s0 and s0.landed then
            seen[key] = true -- keep the sample, so the landing sticks for the rest of the modifier
            s0.land, s0.path, g.land, g.path = nil, nil, nil, nil
        elseif p and g.mod and (S.now - g.mod_at > CFG.SCAN_EVERY * 1.5 or spell.windup and S.now > g.fires_at) then
            g.land, g.path = nil, nil -- the modifier is gone (the dash or slam is over) or the shot is out
        elseif p then
            seen[key] = true
            local s = samples[key]
            if not s then
                samples[key] = { pos = p, t = S.rt, start = p, t0 = S.rt }
            elseif g.mod and (spell.aim or spell.windup) then
                -- a wind-up: the hero stands still, so the lane points where he aims, up and down
                -- included. A dash's runs full length with no wall check: it isn't stopped by props
                -- like parked cars; a shot's (`windup`) stops at the first wall. Range counts from
                -- where the wind-up began, so once the dash runs the lane's end stays put.
                local f, src = U.aim_dir(g.landing_ent)
                if f then
                    local range = U.line_range(g.owner, spell)
                    local v = Vector(f.x * 1000, f.y * 1000, f.z * 1000)
                    local ok, land, path = pcall(predict_line, p, v, g.landing_ent, s.start, range, p, not spell.windup)
                    if ok then s.land, s.path = land, path end
                    if not s.logged and ui.sp_debug:Get() then
                        s.logged = true
                        log("%s lane: %.1f m, aimed by %s", spell.name, range / CFG.UNITS_PER_M, src)
                    end
                end
            elseif spell.motion == "line" and not g.mod then
                -- where it has been since it last moved a unit: its origin only changes on a tick
                if not s.spot or (p.x - s.spot.x) ^ 2 + (p.y - s.spot.y) ^ 2 + (p.z - s.spot.z) ^ 2 > 1 then
                    s.spot, s.spot_t = p, S.rt
                end
                -- straight flight: the average velocity since first seen is exact, and is ready
                -- from the next frame, which fast shots need; no waiting for VEL_SAMPLE
                local el = S.rt - s.t0
                if spell.radius_prop and S.rt - s.spot_t >= CFG.VEL_SAMPLE then
                    -- A shot that ends in an area and hasn't moved for a sample is stuck, and its area is
                    -- on it, with no lane left. Kept at the lane's end, where its line went on to meet
                    -- the ground, Call Bell's ring sat past the bell (replay 2026-11-09 21-15)
                    if not s.stuck and s.land and ui.sp_debug:Get() then
                        log("%s stuck %.2f m from its lane's end", spell.name, sqrt((p.x - s.land.x) ^ 2
                            + (p.y - s.land.y) ^ 2 + (p.z - s.land.z) ^ 2) / CFG.UNITS_PER_M)
                    end
                    s.stuck, s.land, s.path = true, p, nil
                elseif el > 0 then
                    local v = Vector((p.x - s.start.x) / el, (p.y - s.start.y) / el, (p.z - s.start.z) / el)
                    local range = U.line_range(g.owner, spell)
                    local ok, land, path = pcall(predict_line, p, v, g.landing_ent, s.start, range, nil, nil, spell.body)
                    -- keep the last lane once the shot stops moving (it hit), so it stays drawn
                    if ok and land then s.land, s.path, s.speed = land, path, sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
                end
            elseif g.mod and spell.motion == "line" and S.rt - s.t0 < CFG.VEL_SAMPLE
                and (not spell.min_speed or g.charge_until and S.now < g.charge_until) then
                -- the first frames of a dash, before there is movement to measure: aim flat from
                -- where it started (a targeted dash goes at its target, so that is its direction)
                -- and let the measured velocity take over as soon as there is one. Not for a
                -- `min_speed` spell unless he charges: its modifier is no proof of a dash (Apollo's
                -- comes on for his Sigil too), and this lane, timed, had Evade spend Counterspell on it
                local f = U.aim_dir(g.landing_ent)
                local flat = f and sqrt(f.x * f.x + f.y * f.y)
                if flat and flat > 0.01 then
                    local range = U.line_range(g.owner, spell)
                    local v = Vector(f.x / flat * 1000, f.y / flat * 1000, 0)
                    local ok, land, path = pcall(predict_line, s.start, v, g.landing_ent, s.start, range, s.start)
                    if ok and land then s.land, s.path = land, path end
                end
                -- a charge just begun (`charge_max`) has no hit time yet: timed, this lane had Evade
                -- spend Counterspell on Apollo's wind-up, 0.02 s into it
                s.charging = g.charge_until ~= nil and S.now < g.charge_until or nil
            elseif S.rt - s.t >= CFG.VEL_SAMPLE then
                local dt = S.rt - s.t
                local line = spell.motion == "line"
                local gz = line and 0 or -gravity() * (spell.gravity_scale or 1)
                -- the difference is the velocity half a sample ago; add that half sample of gravity
                local v = Vector((p.x - s.pos.x) / dt, (p.y - s.pos.y) / dt, (p.z - s.pos.z) / dt + gz * dt / 2)
                local prev = s.pos
                s.pos, s.t = p, S.rt
                local ok, land, path
                if line then
                    local speed = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
                    -- A charge that its own clip ends (`release_anim`) is not ended by his speed: Apollo
                    -- dashes at lunge speed as he starts to charge, and taken for the lunge it took the
                    -- lane with it 0.3 s in, 11 casts of 20, until the real one came, too late
                    local held = spell.release_anim and g.charge_until and S.now < g.charge_until
                    -- Nor is a stab timed from his clip (`strike`) drawn again by the lunge that carries
                    -- it, 0.5 s at most: timed by his speed, that lane was up after the stab had landed,
                    -- and Evade dashed from it
                    local struck = g.strike_at and S.now < g.strike_at + 0.5
                    if spell.min_speed and (held or struck or speed < spell.min_speed * CFG.UNITS_PER_M) then
                        -- the modifier outlasts the dash itself: draw only while he moves at dash
                        -- speed. The lane goes with it, or Apollo's lunge stayed drawn for the whole
                        -- 5 s recast window he stood in after it
                        s.dash_from, s.land, s.path, s.charging = nil, nil, nil, nil
                        -- still charging it (`charge_max`): the lane flat along his aim, from him, untimed
                        local f = g.charge_until and S.now < g.charge_until and U.aim_dir(g.landing_ent)
                        local flat = f and sqrt(f.x * f.x + f.y * f.y)
                        if flat and flat > 0.01 then
                            local range = U.line_range(g.owner, spell)
                            ok, land, path = pcall(predict_line, p, Vector(f.x / flat * 1000, f.y / flat * 1000, 0),
                                g.landing_ent, p, range, p, true)
                            s.charging = ok and land ~= nil
                        end
                    else
                        g.charge_until, s.charging = nil, nil -- he lunges: the measured lane, timed, from here
                        -- a dash can steer: latest velocity, the lane runs on from where the hero is
                        -- now, and its range counts from where this dash began
                        s.dash_from, s.speed = s.dash_from or prev, speed
                        local range = U.line_range(g.owner, spell)
                        ok, land, path = pcall(predict_line, p, v, g.landing_ent, s.dash_from, range, p)
                        -- Debug Mode, twice a second per dash: why its lane is or isn't there
                        if g.mod and ui.sp_debug:Get() and S.rt - (s.dash_log or -1) > 0.5 then
                            s.dash_log = S.rt
                            local moved = sqrt((p.x - s.dash_from.x) ^ 2 + (p.y - s.dash_from.y) ^ 2 + (p.z - s.dash_from.z) ^ 2)
                            local lane = ok and land and sqrt((land.x - p.x) ^ 2 + (land.y - p.y) ^ 2) or 0
                            log("%s dash: %.0f u/s, %.1f of %.1f m used, lane %.1f m ahead%s", spell.name, speed,
                                moved / CFG.UNITS_PER_M, range / CFG.UNITS_PER_M, lane / CFG.UNITS_PER_M,
                                ok and "" or (" (error: " .. tostring(land) .. ")"))
                        end
                    end
                else
                    ok, land, path = pcall(predict_arc, p, v, spell, g.landing_ent)
                    -- Debug Mode: his speed while he flies, to see the dive against the hover
                    if spell.dive_min_speed and ui.sp_debug:Get() then
                        local dive, speed = diving(v, spell)
                        if dive ~= s.was_diving or S.rt - (s.fly_log or -1) > 0.5 then
                            s.fly_log, s.was_diving = S.rt, dive
                            log("%s: flying %.0f u/s, %.0f deg down%s", spell.name, speed,
                                math.deg(math.asin(math.max(-1, math.min(1, -v.z / math.max(1, speed))))),
                                dive and ", diving" or "")
                        end
                    end
                end
                -- a dash that has covered its range has arrived: keep the landing it was heading
                -- for instead of blanking it on the frame the range runs out
                if ok and land then
                    s.land, s.path = land, path
                    if not line then s.lands_at = S.now + (#path - 1) * CFG.ARC_DT end -- a point is ARC_DT of flight
                elseif spell.arm and not g.mod and v.x * v.x + v.y * v.y + v.z * v.z < 100 * 100 then
                    -- a bomb that arms where it lands (`arm`) has stopped: it has landed. Its area is on
                    -- it, and its fuse runs from when it got there (when first seen, if never seen flying)
                    s.land, s.path, s.lands_at = p, nil, s.lands_at or S.now
                elseif not g.mod or spell.dive_min_speed then
                    s.land, s.path = nil, nil -- a dive pulled out of is no longer coming down
                end
            end
            -- the measured speed of a line, for when it reaches you (the dodge)
            g.land, g.path, g.speed, g.charging = samples[key].land, samples[key].path, samples[key].speed, samples[key].charging
            g.lands_at = samples[key].lands_at
            -- `aim_land`: where a dive comes down, before its own flight tells: where he aims now,
            -- while he is up
            if spell.aim_land and g.mod then
                local okg, ground = pcall(HERO_LIB.is_on_ground, g.landing_ent)
                if okg and ground == false then g.aim_spot = aim_spot(g.landing_ent, spell, true) end
                -- a dive under way (its modifier is the dive): it gets there at `dive_speed`
                local a = g.aim_spot
                if a and spell.dive_speed then
                    g.aim_at = S.now + math.sqrt((a.x - p.x) ^ 2 + (a.y - p.y) ^ 2 + (a.z - p.z) ^ 2) / spell.dive_speed
                end
            end
        end
    end
    for key in pairs(samples) do
        if not seen[key] then samples[key] = nil end
    end
end

-- matching -------------------------------------------------------------------

local function active_spells()
    local list = {}
    for _, s in ipairs(SPELLS) do
        if s.ui and s.ui:Get(s.name) then list[#list + 1] = s end
    end
    return list
end

-- entries a particle starts a dash track for; the registry is static, so this list is too
local DASH_SPELLS, CHARGE_SPELLS = {}, {}
for _, s in ipairs(SPELLS) do
    if s.dash_particle then DASH_SPELLS[#DASH_SPELLS + 1] = s end
    if s.charge_particle or s.charge_anim then CHARGE_SPELLS[#CHARGE_SPELLS + 1] = s end
end

-- `hero_id` sits on each hero's first entry; his other entries share it
local hero_ids = {}
for _, s in ipairs(SPELLS) do
    hero_ids[s.hero] = hero_ids[s.hero] or s.hero_id
    s.hero_id = hero_ids[s.hero]
end

local function match_text(str, keys)
    if not str or str == "" then return nil end
    str = str:lower()
    for _, key in ipairs(keys) do
        if str:find(key, 1, true) then return true end
    end
    return nil
end

local function match_particle(name, spells)
    for _, s in ipairs(spells) do
        if match_text(name, s.particles or {}) and not match_text(name, s.skip or {}) then return s end
    end
    return nil
end

local function match_class(e, spells)
    local names = { (try(e, "get_class_name") or ""):lower(), (try(e, "get_vdata_class_name") or ""):lower() }
    for _, s in ipairs(spells) do
        for _, key in ipairs(s.classes or {}) do
            for _, n in ipairs(names) do
                if n ~= "" and n:find(key, 1, true) then return s end
            end
        end
    end
    return nil
end

local function casting_spell(e, spells)
    for _, slot in ipairs(U.SLOTS) do
        local ab = try(e, "get_ability_by_slot", slot)
        if ab then
            local name = try(ab, "get_name") or ""
            for _, s in ipairs(spells) do
                if s.ability and name:find(s.ability, 1, true)
                    and (HERO_LIB.is_ability_in_cast_delay(ab) or HERO_LIB.is_channeling_ability(ab)) then
                    return s
                end
            end
        end
    end
    return nil
end

-- owners and casts -----------------------------------------------------------

local function resolve_owner(e)
    for _ = 1, 8 do
        if not e then return nil end
        if try(e, "get_class_name") == "C_CitadelPlayerPawn" then return e end
        local next_e
        for _, f in ipairs(U.OWNER_FIELDS) do
            local h = field(e, f)
            if type(h) == "table" then h = field(h, "m_Value") end
            h = tonumber(h)
            if h and h ~= 0 and h ~= 0xFFFFFFFF then
                local o = entity_list.by_handle(h)
                if valid(o) then next_e = o break end
            end
        end
        e = next_e
    end
    return nil
end

-- the pawns whose readable slots hold each spell, for the per-frame modifier poll
local function note_holders(e, spells)
    for _, slot in ipairs(U.SLOTS) do
        local ab = try(e, "get_ability_by_slot", slot)
        local name = ab and try(ab, "get_name")
        if name then
            for _, s in ipairs(spells) do
                if s.ability and name:find(s.ability, 1, true) then
                    S.holders[s] = S.holders[s] or {}
                    table.insert(S.holders[s], e)
                end
            end
        end
    end
end

-- spell particles on a pawn that lacks the ability are on-hit effects on a victim, not a cast
local function has_modifier(e, key)
    local mods = try(e, "get_modifiers")
    for _, m in ipairs(type(mods) == "table" and mods or {}) do
        local name = try(m, "get_name")
        if name and name:lower():find(key:lower(), 1, true) then return true end
    end
    return false
end

-- the hero's ability for `s` is in its cast delay or channel; for a `windup` shot only the cast
-- delay, as its channel is the shot's own flight
local function in_cast(e, s)
    local ab = s.ability and U.find_ability(e, s.ability)
    if not ab then return false end
    if HERO_LIB.is_ability_in_cast_delay(ab) == true then return true end
    return not s.windup and HERO_LIB.is_channeling_ability(ab) == true
end

-- A cone's trigger particle (`cone_particle`) starts the fan on the hero that spawned it. The burst's
-- first sighting is kept, not the latest, so `cone_time` counts from the swing and a sighting later
-- in the same burst doesn't push the fan back; a gap means a new burst and a new clock. So does a
-- swing particle created well after the one that started it: the last swing's particle lives on
-- (its event too, 1 s past death), so back-to-back uppercuts never showed a gap and only every
-- now and again drew.
local function note_cone(g, hero, now, at)
    -- `at`: when the particle was created, if known, so the fan's clock isn't a scan late
    if not g.cone_at or now - (g.cone_seen or 0) > CFG.SCAN_EVERY * 1.5
        or at and at > g.cone_at + CFG.SCAN_EVERY then
        g.cone_at = at or now
    end
    g.cone_seen, g.caster = now, hero
end

-- The pawn is known not to be the spell's caster, so its particle is an on-hit effect on a victim.
-- His hero id decides when it reads (a match has each hero once). Else his abilities do, but an
-- enemy's can all read as missing, so a hero with no readable ability at all isn't ruled out: an
-- enemy Billy's own Bashdown bat effect, on him, was dropped as a hit on a victim.
local function lacks_ability(pawn, spell)
    local ok, raw = pcall(HERO_LIB.get_hero_id, pawn)
    local id = ok and tonumber(raw) or 0
    if id > 0 and spell.hero_id then return id ~= spell.hero_id end
    if not spell.ability or U.find_ability(pawn, spell.ability) ~= nil then return false end
    for _, slot in ipairs(U.SLOTS) do
        if try(pawn, "get_ability_by_slot", slot) ~= nil then return true end
    end
    return false
end

local function who(p)
    if handle(p) == handle(S.me) then return "you" end
    return HERO_LIB and HERO_LIB.is_same_team(S.me, p) == true and "an ally" or "an enemy"
end

-- Who cast `spell`, for particles and entities that don't say: the hero playing the spell's hero,
-- else the hero whose abilities show the spell. A match has each hero at most once, so neither is
-- a guess. A sandbox can spawn a second one: then anyone but you gets it, as a bot of your own hero
-- was handed its own Radiant Daggers tell as yours, and yours are never drawn.
-- shortcut: with your hero on both sides, your own unowned tells draw as the other's; a real match has each hero once
local function known_caster(spell)
    local dbg = ui.sp_debug:Get()
    local ids, mine = {}, nil
    for _, p in ipairs(S.pawns or {}) do
        local ok, id = pcall(HERO_LIB.get_hero_id, p)
        if ok and valid(p) and tonumber(id) == spell.hero_id then
            if handle(p) ~= handle(S.me) then return p end
            mine = p
        end
        if dbg then ids[#ids + 1] = ok and tostring(id) or "error" end
    end
    if mine then return mine end
    local holder
    for _, p in ipairs(S.holders[spell] or {}) do
        if not holder or handle(holder) == handle(S.me) then holder = p end
    end
    -- Debug Mode: what the hero ids read as, when none is the spell's
    if dbg then
        debug("%s: no hero has id %s (ids: %s), %s", spell.name, tostring(spell.hero_id),
            table.concat(ids, " "), holder and ("holder " .. who(holder)) or "no holder either")
    end
    return valid(holder) and holder or nil
end

-- groups ---------------------------------------------------------------------

-- one group per spell instance (projectile entity, pawn, or loose particle) so simultaneous casts don't share one
local function group_for(groups, spell, owner, inst)
    local key = spell.id .. ":" .. tostring(inst)
    local g = groups[key]
    if not g then
        local old = S.groups[key]
        -- an instance keeps its first owner, so a later guess can't recolour it
        owner = old and valid(old.owner) and old.owner or owner
        g = { spell = spell, owner = owner, first = old and old.first or S.now, logged = old and old.logged,
              particles = {}, seen = {}, cone_at = old and old.cone_at, cone_seen = old and old.cone_seen,
              dash_from = old and old.dash_from, at_me = old and old.at_me,
              charge_until = old and old.charge_until, charge_at = old and old.charge_at,
              strike_at = old and old.strike_at,
              had_you = old and old.had_you, wave = old and old.wave }
        groups[key] = g
    end
    return g
end

-- The group for a modifier spell on one hero, whichever of the dash particle, the frame poll or a
-- scan renews it: they share the key, so the group and its start time survive between them.
-- `casting`: it was seen in its cast delay, not already under way
local function modifier_group(groups, spell, pawn, now, casting)
    local g = group_for(groups, spell, pawn, "mod" .. tostring(handle(pawn)))
    g.caster, g.landing_ent, g.mod, g.mod_at, g.last = pawn, pawn, true, now, now
    -- a wind-up: the shot or dash leaves `windup` after it was first seen winding up (the frame poll
    -- keeps that a frame late at most); first seen already under way (Leaping Slash by its dash
    -- particle or modifier), it has left
    if spell.windup then g.fires_at = g.fires_at or (casting and g.first + spell.windup or now) end
    return g
end

local function add_particle(g, name, cps)
    local out = {}
    for _, cp in ipairs(cps or {}) do
        local o = cp.origin
        local key = U.fmt("%s:%.0f:%.0f:%.0f", tostring(name), o.x, o.y, o.z)
        if not g.seen[key] then
            g.seen[key] = true
            out[#out + 1] = cp
        end
    end
    if #out > 0 then g.particles[#g.particles + 1] = { name = name, control_points = out } end
end

-- A tell's CP0 can float: Disengaging Sigil's sits at Apollo's waist, so its ring hung in the air.
-- The area is on the floor under it, as the ability itself traces (TraceToGroundDistance 1000 u).
local function ground_below(p, ignore)
    local top = Vector(p.x, p.y, p.z + 10)
    local ok, tr = pcall(trace_line, top, Vector(p.x, p.y, p.z - 1000), ignore)
    local frac = ok and tr and field(tr, "fraction")
    if type(frac) ~= "number" or frac >= 1 then return p end
    return Vector(p.x, p.y, top.z - 1010 * frac)
end

local function note_particle(g, e, name, cps, spell)
    add_particle(g, name, cps)
    local low = (name or ""):lower()
    if spell.projectile and not g.landing_ent and valid(e) and low:find(spell.projectile, 1, true)
        and (spell.follow_caster or try(e, "get_class_name") ~= "C_CitadelPlayerPawn") then
        g.landing_ent = e
    end
    if spell.warning and low:find(spell.warning, 1, true) and not g.warning then
        local cp = cps and cps[1]
        if cp then g.warning = ground_below(cp.origin, g.owner) end
    end
end

-- Caster-pawn groups and loose warning groups belong to a projectile of the same spell and owner:
-- fold each into the projectile whose predicted landing is nearest its warning, so one bomb draws once.
local function fold_into_projectiles(groups)
    for key, g in pairs(groups) do
        if not (g.landing_ent or g.landing_ev or g.shot) then
            local best, best_d
            for _, o in pairs(groups) do
                -- a warning matches by landing spot alone: its owner is often only a guess,
                -- and the projectile it merges into keeps the projectile's owner
                if (o.landing_ent or o.landing_ev) and o.spell == g.spell
                    and (g.warning or handle(o.owner) == handle(g.owner)) then
                    local d = 0
                    if g.warning then
                        local w, l = g.warning, o.land
                        d = l and sqrt((w.x - l.x) ^ 2 + (w.y - l.y) ^ 2 + (w.z - l.z) ^ 2) or math.huge
                    end
                    if d < CFG.MERGE_DIST and (not best_d or d < best_d) then best, best_d = o, d end
                end
            end
            if best then
                best.warning = best.warning or g.warning
                best.caster = best.caster or g.caster
                for _, p in ipairs(g.particles) do add_particle(best, p.name, p.control_points) end
                groups[key] = nil -- clearing an existing key during pairs is allowed
            end
        end
    end
end

-- scan -----------------------------------------------------------------------

-- Between scans, every frame: has a modifier spell just started on a hero? A dash or slam would
-- otherwise be drawn up to a whole scan (0.25 s) late. Only the moment a modifier appears counts,
-- so a hero the scan skips (out of range) can't force a scan every frame.
local mod_on = {}
local function modifier_started()
    local started = false
    for _, e in ipairs(S.pawns or {}) do
        local mods = valid(e) and try(e, "get_modifiers")
        local names = {}
        for _, m in ipairs(type(mods) == "table" and mods or {}) do names[#names + 1] = (try(m, "get_name") or ""):lower() end
        for _, s in ipairs(S.mod_spells or {}) do
            local key, on = s.id .. ":" .. tostring(handle(e)), false
            for _, n in ipairs(s.modifier_low and names or {}) do
                if n:find(s.modifier_low, 1, true) then on = true break end
            end
            if on and not mod_on[key] then started = true end
            mod_on[key] = on
        end
    end
    return started
end

function X.scan()
    local now = S.now
    local started = modifier_started()
    if now < S.next_scan and not started then return end
    S.next_scan = now + CFG.SCAN_EVERY

    local spells = active_spells()
    S.mod_spells = {}
    for _, s in ipairs(spells) do
        if s.modifier or s.windup then
            s.modifier_low = s.modifier and (s.modifier_low or s.modifier:lower()) -- modifier_started runs every frame
            S.mod_spells[#S.mod_spells + 1] = s
        end
    end
    S.holders, S.pawns = {}, {}
    S.near = {} -- pawn handles the per-frame modifier poll may look at
    local groups = {}
    if #spells == 0 then
        debug("scan skipped: every ability is toggled off in the hero menus")
        S.list = groups
        return
    end

    local md = ui.sp_dist:Get() or 0
    local ok, all = pcall(entity_list.get_all)
    if not ok or type(all) ~= "table" then
        debug("scan skipped: entity_list.get_all failed (%s)", tostring(all))
        S.list = groups
        return
    end

    -- every hero first: known_caster reads them, and an ownerless entity carrying a tell can come
    -- before them all in the list (Radiant Daggers went undrawn with "ids: " empty)
    for _, e in ipairs(all) do
        if valid(e) and try(e, "get_class_name") == "C_CitadelPlayerPawn" then
            note_holders(e, spells)
            S.pawns[#S.pawns + 1] = e
        end
    end

    for _, e in ipairs(all) do
        if valid(e) then
            local is_pawn = try(e, "get_class_name") == "C_CitadelPlayerPawn"
            local o = try(e, "get_origin")
            local near = true
            if o and md > 0 then
                local d = U.dist_to_me(o)
                near = not d or d / CFG.UNITS_PER_M <= md + 20
            end
            if is_pawn then S.near[handle(e)] = near end
            if near then
                local okp, particles = pcall(U.call, e, "get_particles")
                particles = okp and type(particles) == "table" and particles or nil

                -- a hero can carry another hero's on-hit effect next to his own cast: skip the
                -- effect, and keep only the chosen spell's particles so none land in the wrong group
                local spell, matched = nil, {}
                for _, p in ipairs(particles or {}) do
                    local s = match_particle(p.name, spells)
                    -- A ground tell on something that isn't its caster (the world carries every cast's)
                    -- is its own event's to draw, each cast apart. As this entity's one group every
                    -- cast shared the first one's start and spot: Radiant Daggers thrown inside ~3 s of
                    -- the last (her charges are 2 s apart) was past its fuse and never drew
                    local tell = s and not is_pawn and s.warning and match_text(p.name, { s.warning })
                    if s and not tell and not (is_pawn and lacks_ability(e, s)) then
                        spell = spell or s
                        if s == spell then matched[#matched + 1] = p end
                    end
                end
                if not spell then spell = match_class(e, spells) end
                if not spell and is_pawn then spell = casting_spell(e, spells) end
                if spell and is_pawn and lacks_ability(e, spell) then spell = nil end

                if spell then
                    local owner = resolve_owner(e) or known_caster(spell)
                    if owner then
                        local g = group_for(groups, spell, owner, handle(e))
                        if is_pawn then g.caster = g.caster or e end
                        if #matched > 0 then
                            if not g.ent and not is_pawn then g.ent = e end
                            for _, p in ipairs(matched) do
                                note_particle(g, e, p.name, p.control_points, spell)
                            end
                        end
                        -- a cone's trigger particle on the hero starts the fan on him: instant melee
                        -- has no cast delay and no modifier, and the swing particle is all there is
                        if is_pawn and spell.cone_particle then
                            for _, p in ipairs(matched) do
                                if match_text(p.name, { spell.cone_particle }) then
                                    note_cone(g, e, now)
                                    break
                                end
                            end
                        end
                        if not g.logged then
                            g.logged = true
                            if ui.sp_debug:Get() then
                                log("detected %s on %s", spell.name, try(e, "get_class_name") or "?")
                            end
                        end
                    end
                end

                -- dashes, leaps, wind-ups and self buffs: while the spell's modifier is on a hero
                -- (or, for `aim` spells, while he is winding it up), the hero is the projectile
                if is_pawn then
                    for _, s in ipairs(spells) do
                        local casting = (s.aim or s.windup) and in_cast(e, s)
                        if (s.modifier and has_modifier(e, s.modifier) or casting) and not lacks_ability(e, s) then
                            local g = modifier_group(groups, s, e, now, casting)
                            if not g.logged and ui.sp_debug:Get() then
                                g.logged = true
                                log("%s %s on %s", s.name, (s.aim or s.windup) and "wind-up" or "modifier", who(e))
                            end
                        end
                    end
                end
            end
        end
    end

    local active = {}
    for _, s in ipairs(spells) do active[s] = true end
    for idx, ev in pairs(S.events) do
        local age = now - (ev.last or ev.first)
        if age > 15 or (ev.dead and now - ev.dead > 1) or not active[ev.spell] then
            S.events[idx] = nil
        else
            local cps = {}
            for _, cp in pairs(ev.cps) do cps[#cps + 1] = cp end
            table.sort(cps, function(a, b) return a.cp < b.cp end) -- pairs order is random; CP0 first
            local owner = ev.owner or resolve_owner(ev.ent)
            if not owner then
                -- no owner on the particle: the hero who plays the spell's hero
                owner = known_caster(ev.spell)
                ev.owner = owner
                if owner and ui.sp_debug:Get() then log("event %d owner by hero: %s", idx, who(owner)) end
            end
            if valid(ev.ent) and try(ev.ent, "get_class_name") == "C_CitadelPlayerPawn" and lacks_ability(ev.ent, ev.spell) then
                -- on-hit effect on a victim: not drawn, and not worth a "no owner" log
            elseif not owner then
                -- what its entity reads as: an enemy Billy's pawn once didn't read as a hero for a whole
                -- test (2026-11-09, never seen again), and "entity=yes" couldn't say what it read as
                if ui.sp_debug:Get() then
                    log("event %d has no owner: on %s, valid %s", idx, tostring(try(ev.ent, "get_class_name")),
                        tostring(valid(ev.ent)))
                end
            else
                -- a ground tell is its own instance: on its caster, every cast of hers shared one
                -- group whose start stayed on the first, so a bot's later Radiant Daggers were all
                -- past their 1.4 s fuse before they appeared
                local tell = ev.spell.warning and ev.name:lower():find(ev.spell.warning, 1, true)
                local inst = (tell or not valid(ev.ent)) and ("ev" .. idx) or handle(ev.ent)
                local g = group_for(groups, ev.spell, owner, inst)
                -- and a group starts with its newest live projectile particle: Bashdown cast again inside
                -- the ~2 s his last group is kept came out past its fuse, and 3 casts in 13 never drew
                if not ev.dead and ev.first > (g.started or -math.huge) and ev.spell.projectile
                    and ev.name:lower():find(ev.spell.projectile, 1, true) then
                    g.started, g.first = ev.first, ev.first
                end
                if #cps > 0 and not g.ent and valid(ev.ent) then g.ent = ev.ent end
                -- a dead particle names nothing to follow: Bashdown's kept Billy as its projectile,
                -- and its area on him, for the 1 s its event is kept after the slam
                note_particle(g, not ev.dead and ev.ent or nil, ev.name, cps, ev.spell)
                -- a ground tell's own particle: the area is drawn while it lives (see projectile_gone)
                if tell then g.warning_ev = idx end
                -- a cone's trigger particle: the fan starts on the hero it was spawned on, whether
                -- the game reports it on him or on a child entity that resolves back to him
                if ev.spell.cone_particle and ev.name:lower():find(ev.spell.cone_particle, 1, true)
                    and valid(owner) and try(owner, "get_class_name") == "C_CitadelPlayerPawn" then
                    note_cone(g, owner, now, ev.first)
                end
                -- projectile particle with no projectile entity: follow the particle itself
                if ev.spell.projectile and not g.landing_ent and not g.landing_ev
                    and ev.name:lower():find(ev.spell.projectile, 1, true) then
                    g.landing_ev = idx
                end
                if not ev.merged then
                    ev.merged = true
                    if ui.sp_debug:Get() then log("event %d merged: %s", idx, ev.spell.name) end
                end
            end
        end
    end

    -- stamp only fresh groups; kept groups keep their old `last` so they expire after CLEAR_DELAY
    for _, g in pairs(groups) do g.last = now end
    for key, g in pairs(S.groups) do
        if not groups[key] and now - (g.last or g.first) < CFG.CLEAR_DELAY then groups[key] = g end
    end
    -- fresh groups pick up the latest prediction now; fold needs it to match warnings to projectiles
    for _, g in pairs(groups) do
        local s = samples[proj_key(g) or false]
        if s then g.land, g.path = s.land, s.path end
    end
    fold_into_projectiles(groups)
    S.groups = groups
    S.list = groups
end

-- dash modifier poll ---------------------------------------------------------

-- A dash's modifier can be up for less than one scan: Leaping Slash crosses its 9 m at DashSpeed
-- 2400 u/s in 0.147 s, and its 0.1 s cast delay is under SCAN_EVERY on its own, so two scans can
-- straddle it and it is never seen. The scan already lists the pawns that own each spell, so those
-- are re-read every frame instead.
function X.track_modifiers()
    -- a charge (`charge_max`) keeps its hero's group going while it lasts: no modifier covers it
    for _, g in pairs(S.groups) do
        if g.charge_until and S.now < g.charge_until and valid(g.caster) then g.mod_at, g.last = S.now, S.now end
    end
    for _, s in ipairs(S.mod_spells or {}) do -- the last scan's active spells with a modifier
        for _, e in ipairs(S.holders[s] or {}) do
            local h = valid(e) and handle(e)
            if h and S.near[h] then
                -- `aim`: the cast delay too, which is shorter than a scan (Leaping Slash's 0.1 s)
                local casting = (s.aim or s.windup) and in_cast(e, s)
                -- mod_on: what modifier_started read this frame (X.scan runs first), not a second read
                if mod_on[s.id .. ":" .. tostring(h)] or casting then
                    modifier_group(S.groups, s, e, S.now, casting)
                end
            end
        end
    end
end

-- Debug Mode: what enemy heroes did lately (particles, modifiers, clips), so a bullet spell's shot
-- lists what came before it from its shooter: a tell earlier than the shot itself. Stalker's Mark
-- is seen 0.06-0.13 s before it hits, too late to dash; its 0.15 s cast delay shows nothing known
local PROBE_SPAN = 0.6 -- seconds kept
local recent = {}
local function note_recent(ent, what)
    if not ui.sp_debug:Get() then return end
    local h = valid(ent) and handle(ent) or nil -- nil: a particle no hero owns, kept as it may be his
    if h and (h == handle(S.me) or HERO_LIB.is_same_team(S.me, ent) == true) then return end
    while recent[1] and (math.abs(S.now - recent[1].t) > PROBE_SPAN or #recent > 300) do table.remove(recent, 1) end
    recent[#recent + 1] = { t = S.now, h = h, what = what }
end

-- Leaping Slash's m_DashModifier is m_bIsHidden, and the poll above can miss it in game. The
-- add-modifier callback names the ability that made the modifier, which ties it to the entry
-- whatever the modifier reads as. Kept to `dash_particle` entries, the dashes shorter than a scan.
-- A targeted spell is on you now (`why`): its group starts on its caster, timed from this moment,
-- whatever his aim reads as
local function cast_at_me(s, why)
    S.targeted[s.id] = S.now
    local caster = known_caster(s)
    if caster then
        local g = group_for(S.groups, s, caster, handle(caster))
        g.caster, g.at_me, g.last = caster, true, S.now
        S.list = S.groups
    end
    if ui.sp_debug:Get() then
        log("%s is aimed at you (%s), cast by %s", s.name, why, caster and who(caster) or "no one known")
    end
end

function X.track_modifier_add(mod, target)
    if not mod or not valid(target) or try(target, "get_class_name") ~= "C_CitadelPlayerPawn" then return end
    local ab = try(mod, "get_ability")
    local abil = ab and try(ab, "get_name") or ""
    local mine = handle(target) == handle(S.me)
    if not mine then note_recent(target, "modifier " .. tostring(try(mod, "get_name"))) end
    if mine and ui.sp_debug:Get() then
        log("modifier on you: %s / %s (ability %s)", tostring(try(mod, "get_name")),
            tostring(try(mod, "get_vdata_class_name")), abil)
    end
    for _, s in ipairs(DASH_SPELLS) do
        if s.ui and s.ui:Get(s.name) and abil:find(s.ability, 1, true) and not lacks_ability(target, s) then
            modifier_group(S.groups, s, target, S.now)
            S.next_scan = 0
            if ui.sp_debug:Get() then log("%s started by its modifier on %s", s.name, who(target)) end
            return
        end
    end
end

-- a held or wound-up dash begins (`charge_particle`, `charge_anim`): his lane along his aim until he
-- lunges, for `charge_max` at most
local function start_charge(s, pawn)
    local g = modifier_group(S.groups, s, pawn, S.now)
    g.charge_at, g.charge_until, g.strike_at = S.now, S.now + s.charge_max, nil
    S.next_scan, S.list = 0, S.groups
    if ui.sp_debug:Get() then log("%s charging on %s", s.name, who(pawn)) end
end

-- animations ----------------------------------------------------------------

local ANIM_NEAR = 40 -- meters: enemy heroes this close have their animations logged
local anim_seen = {} -- hero handle .. clip name, so each clip is logged once per hero

-- Debug Mode: the animation clips an enemy hero near you starts, each once per hero, with its
-- length. An enemy's cast delay doesn't reach the client, so a cast animation may be the earliest
-- tell of a spell (Leaping Slash's wind-up before the leap, a shot's wind-up before it flies)
function X.track_animation(ent, clip)
    if not valid(ent) or try(ent, "get_class_name") ~= "C_CitadelPlayerPawn" then return end
    local name = field(clip, "name")
    -- a wind-up's own clip (`charge_anim`) starts its charge: an enemy's cast delay doesn't reach the client
    for _, s in ipairs(CHARGE_SPELLS) do
        if s.charge_anim == name and s.ui and s.ui:Get(s.name) and not lacks_ability(ent, s) then start_charge(s, ent) end
        -- and the clip he lets go with (`release_anim`) ends it: the first one, as Apollo's in-air clip
        -- follows his ground one 0.05 s on, when the lunge lifts him
        local g = s.release_anim and name and name:find(s.release_anim)
            and S.groups[s.id .. ":mod" .. tostring(handle(ent))]
        if g and g.charge_until and not g.strike_at then
            if ui.sp_debug:Get() then
                -- with where you stand against his aim: a hit taken from outside the lane says the lane is wrong
                local o, f, me = try(ent, "get_origin"), U.aim_dir(ent), S.me and try(S.me, "get_origin")
                local n = o and f and me and sqrt(f.x * f.x + f.y * f.y) * CFG.UNITS_PER_M or 0
                local dx, dy = n > 0 and me.x - o.x or 0, n > 0 and me.y - o.y or 0
                log("%s let go %.2f s into the charge: you are %.1f m along his aim, %.1f m off it, %.1f m above him",
                    s.name, S.now - (g.charge_at or S.now), n > 0 and (dx * f.x + dy * f.y) / n or -1,
                    n > 0 and math.abs(dx * f.y - dy * f.x) / n or -1, n > 0 and (me.z - o.z) / CFG.UNITS_PER_M or 0)
            end
            -- with a `strike` time the lane stays on his aim until the stab lands, timed to it
            g.strike_at = s.strike and S.now + s.strike
            g.charge_until = g.strike_at
        end
    end
    if not ui.sp_debug:Get() then return end
    if handle(ent) == handle(S.me) or HERO_LIB.is_same_team(S.me, ent) == true then return end
    note_recent(ent, "anim " .. tostring(name))
    local d = U.dist_to_me(try(ent, "get_origin"))
    if not name or not d or d > ANIM_NEAR * CFG.UNITS_PER_M then return end
    local key = tostring(handle(ent)) .. ":" .. tostring(name)
    if anim_seen[key] then return end
    anim_seen[key] = true
    log("anim: %s (hero %s, %.1f m off) started %s, %.2f s", who(ent), tostring(HERO_LIB.get_hero_id(ent)),
        d / CFG.UNITS_PER_M, tostring(name), tonumber(field(clip, "duration")) or -1)
end

-- particle callbacks ---------------------------------------------------------

-- Debug Mode: a bullet spell's skipped effects (an orb's hover where it stops, its impact) are
-- placed against the last shot, to measure how far and long the shot really flew
local probes = {}

function X.track_particle(d)
    if not d or type(d.name) ~= "string" or d.index == nil then return end
    if ui.sp_debug:Get() then note_recent(resolve_owner(d.entity or d.entity_for_modifiers), "particle " .. U.short_name(d.name)) end
    local shot = S.last_shot
    if shot and ui.sp_debug:Get() and S.now - shot.t < 6 and match_text(d.name, shot.spell.skip or {}) then
        probes[d.index] = { shot = shot, name = d.name }
    end
    local low = d.name:lower()
    -- a dash's own particle starts its track on the hero at the instant the dash does, which for a
    -- dash shorter than a scan is the one moment a scan can step over; the modifier poll then
    -- carries the group while he moves. The hero is the projectile, so it returns here.
    for _, s in ipairs(DASH_SPELLS) do
        if s.ui and s.ui:Get(s.name) and low:find(s.dash_particle, 1, true) then
            local pawn = resolve_owner(d.entity or d.entity_for_modifiers)
            if valid(pawn) and try(pawn, "get_class_name") == "C_CitadelPlayerPawn" and not lacks_ability(pawn, s) then
                modifier_group(S.groups, s, pawn, S.now)
                S.next_scan = 0 -- lists his abilities and starts the sample now, not next scan
                if ui.sp_debug:Get() then log("%s started by its dash particle on %s", s.name, who(pawn)) end
            end
            return
        end
    end
    -- a targeted spell's tell made on its target's client alone (Soul Exchange's screen effect):
    -- it is aimed at you, whatever its caster's aim reads as. It starts the spell itself, timed from
    -- now: the caster's own tell may never reach you (Soul Exchange's didn't, and the swap landed
    -- 0.1 s after the screen tell, too soon to wait for a scan)
    for _, s in ipairs(SPELLS) do
        if s.target_particles and s.ui and s.ui:Get(s.name) and match_text(d.name, s.target_particles) then
            cast_at_me(s, U.short_name(d.name))
        end
    end
    -- a held dash's charge (`charge_particle`): his lane along his aim, untimed, until he lunges
    for _, s in ipairs(CHARGE_SPELLS) do
        if s.charge_particle and s.ui and s.ui:Get(s.name) and low:find(s.charge_particle, 1, true) then
            local pawn = resolve_owner(d.entity or d.entity_for_modifiers) or known_caster(s)
            if valid(pawn) and try(pawn, "get_class_name") == "C_CitadelPlayerPawn" and not lacks_ability(pawn, s) then
                start_charge(s, pawn)
            end
            return
        end
    end
    local spell = match_particle(d.name, SPELLS)
    if not spell then return end
    local ent = d.entity or d.entity_for_modifiers
    -- indexes are reused: the last particle's group under this one would hand on its start time
    S.groups[spell.id .. ":ev" .. d.index] = nil
    S.events[d.index] = { name = d.name, ent = ent, spell = spell, first = S.now, last = S.now, cps = {},
        owner = resolve_owner(ent) }
    -- a projectile can be gone before the next 0.25s scan; scan on the next frame instead
    -- a modifier spell's particle means the move just started: look for the modifier now too;
    -- a cone's swing particle opens a window shorter than a scan, so place it now as well
    -- a targeted spell's tell too: Soul Exchange hits 0.2-0.3 s after it, about a scan
    if spell.modifier or spell.projectile and low:find(spell.projectile, 1, true)
        or spell.cone_particle and low:find(spell.cone_particle, 1, true) or spell.motion == "target" then
        S.next_scan = 0
    end
    debug("particle %s", U.short_name(d.name))
end

-- Line spells fired as bullets: the game hands over the exact start and direction at the moment
-- of firing, so the lane is known before the first frame of flight and needs no tracking.
local unmatched_bullets = {}
-- A bullet is seen this long after it left: counted from its event, hits came 0.03-0.05 s early
-- (Shining Wonder 5 times, Grapple Arm twice, Malice once, 2026-11-09)
local BULLET_LAG = 0.04
function X.track_bullet(d)
    if not d or type(d.weapon_name) ~= "string" or not d.start_pos or not d.direction then return end
    local wname = d.weapon_name:lower()
    local spell
    for _, s in ipairs(SPELLS) do
        local key = s.bullet or s.ability
        if s.motion == "line" and key and s.ui and s.ui:Get(s.name) and wname:find(key:lower(), 1, true) then
            spell = s
            break
        end
    end
    if not spell then
        -- Debug Mode: name each of your own unmatched bullet weapons once, to fill in `bullet`
        if ui.sp_debug:Get() and S.me and handle(d.shooter) == handle(S.me) and not unmatched_bullets[wname] then
            unmatched_bullets[wname] = true
            log("bullet from %s matches no line spell", d.weapon_name)
        end
        return
    end

    local owner = resolve_owner(d.shooter) or d.shooter
    if not valid(owner) then return end
    local o, dir = d.start_pos, d.direction
    S.last_shot = { spell = spell, from = o, t = S.now }
    local range = U.line_range(owner, spell)
    -- ignore the shooter so the wall trace doesn't stop on their own hitbox at the muzzle
    local land, path = predict_line(o, Vector(dir.x * 1000, dir.y * 1000, dir.z * 1000), owner, o, range)
    if not land then return end

    -- the shot's group lives for its flight time, then CLEAR_DELAY like any other group
    local flight = spell.speed and sqrt((land.x - o.x) ^ 2 + (land.y - o.y) ^ 2 + (land.z - o.z) ^ 2) / spell.speed or 0
    S.shot_n = S.shot_n + 1
    S.groups["shot" .. S.shot_n] = { spell = spell, owner = owner, first = S.now, last = S.now + flight,
        logged = true, particles = {}, seen = {}, land = land, path = path, shot = true, rt0 = S.rt - BULLET_LAG }
    spell.bullet_owners = spell.bullet_owners or {}
    spell.bullet_owners[handle(owner)] = true
    S.list = S.groups
    if ui.sp_debug:Get() then
        -- how long its lane is, how far from its shooter it starts and how close it passes you: a shot
        -- that hits you from well outside its lane isn't flying along it
        local so, me = try(owner, "get_origin"), S.me and try(S.me, "get_origin")
        local ex, ey = land.x - o.x, land.y - o.y
        local t = me and math.max(0, math.min(1, ((me.x - o.x) * ex + (me.y - o.y) * ey) / math.max(1, ex * ex + ey * ey)))
        log("bullet %s -> %s: lane %.1f m, starts %.1f m from its shooter, passes %.1f m from you", d.weapon_name,
            spell.name, sqrt(ex * ex + ey * ey + (land.z - o.z) ^ 2) / CFG.UNITS_PER_M,
            so and sqrt((o.x - so.x) ^ 2 + (o.y - so.y) ^ 2 + (o.z - so.z) ^ 2) / CFG.UNITS_PER_M or -1,
            me and sqrt((me.x - o.x - ex * t) ^ 2 + (me.y - o.y - ey * t) ^ 2) / CFG.UNITS_PER_M or -1)
        -- and what its shooter, or no one, showed in the moments before: a tell to start it sooner
        if handle(owner) ~= handle(S.me) then
            local seen = {}
            for _, r in ipairs(recent) do
                local age = S.now - r.t
                if (not r.h or r.h == handle(owner)) and age >= 0 and age <= PROBE_SPAN then
                    seen[#seen + 1] = ("%s -%.2f s"):format(r.what, age)
                end
            end
            log("%s fired; before it: %s", spell.name, #seen > 0 and table.concat(seen, ", ") or "nothing")
        end
    end
end

function X.update_particle(d)
    -- a control point that follows an entity comes with no position of its own (has_position false)
    -- and reads as the map's origin: Shining Wonder's impact logged "52 m from the shot" every cast
    local pos = d and d.has_position ~= false and d.position
    local pr = d and probes[d.index]
    if pr and pos and d.control_point == 0 then
        probes[d.index] = nil
        local a, b = pr.shot.from, pos
        log("%s: %s %.1f m from the shot, %.2f s after", pr.shot.spell.name, U.short_name(pr.name),
            sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2 + (b.z - a.z) ^ 2) / CFG.UNITS_PER_M, S.now - pr.shot.t)
    end
    local r = d and S.events[d.index]
    if not r then return end
    r.last = S.now
    if pos then
        -- a landing warning's first position is the game's own landing ring: draw it this frame
        if next(r.cps) == nil and r.spell.warning and r.name:lower():find(r.spell.warning, 1, true) then
            S.next_scan = 0
        end
        if d.control_point == 0 and not r.from then r.from, r.from_t = pos, S.now end
        r.cps[d.control_point] = { cp = d.control_point, origin = pos }
    end
end

function X.destroy_particle(d)
    if d then probes[d.index] = nil end -- indexes are reused: a stale probe would log a stranger
    local ev = d and S.events[d.index]
    -- A released index is not a destroyed particle: the effect plays on, the server has only let go of
    -- it. Radiant Daggers' tell is let go of the moment it is made (every cast, 2026-11-09): taken for
    -- dead it never drew, and the world's shared group drew in its place, 0.26 s late or not at all.
    -- A ground tell with a fuse plays it out, and the fuse ends its drawing; any other release still
    -- ends what it ends now
    local plays_on = ev and d.released and (ev.spell.duration or ev.spell.duration_prop)
        and ev.spell.warning and ev.name:lower():find(ev.spell.warning, 1, true)
    if ev and not plays_on then ev.dead = S.now end
    -- Debug Mode: how far and how long a projectile particle really flew, to set `range` and `speed`
    local to = ev and ev.cps[0] and ev.cps[0].origin
    if to and ev.from and ui.sp_debug:Get() and ev.spell.projectile
        and ev.name:lower():find(ev.spell.projectile, 1, true) then
        local dist = sqrt((to.x - ev.from.x) ^ 2 + (to.y - ev.from.y) ^ 2 + (to.z - ev.from.z) ^ 2)
        local t = S.now - ev.from_t
        log("%s flight: %.1f m in %.2f s (%.0f u/s average)", ev.spell.name, dist / CFG.UNITS_PER_M, t,
            t > 0 and dist / t or 0)
    end
end

return X
