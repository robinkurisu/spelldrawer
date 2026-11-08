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

local function trace_line(a, b, ignore)
    local T = CFG.TRACE
    return trace.line(a, b, T.with, T.exclude, T.as, T.object_set, T.group, function(ent)
        return handle(ent) ~= handle(ignore)
    end)
end

-- "arc" motion. o / v: projectile world position and velocity; ignore: the projectile entity, if any
local function predict_arc(o, v, spell, ignore)
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

local LINE_STEPS = 24 -- the lane is split up so a partly off-screen lane still draws its visible part

-- "line" motion: straight on from o until the range left after travelling from start, or a wall.
-- The lane is drawn from `from` (default start); `through` skips the wall check.
local function predict_line(o, v, ignore, start, range, from, through)
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
    if not (ui.sp_land:Get() or ui.sp_arc:Get()) then return end
    local seen = {}
    for _, g in pairs(S.list) do
        local spell = g.spell
        local key = (spell.motion == "arc" or spell.motion == "line") and proj_key(g)
        local p = key and projectile_pos(g)
        g.pos = p -- this frame's position, for the drawing: the path only moves on a velocity sample
        local s0 = p and g.mod and spell.motion == "arc" and samples[key]
        if s0 then
            -- a leap is over once he has been in the air and touches down again, even with the
            -- modifier still on him: Seismic Impact's stays ~0.7 s past the slam
            local okg, ground = pcall(HERO_LIB.is_on_ground, g.landing_ent)
            if okg and ground == false then s0.airborne = true end
            if okg and ground == true and s0.airborne then s0.landed = true end
        end
        if s0 and s0.landed then
            seen[key] = true -- keep the sample, so the landing sticks for the rest of the modifier
            s0.land, s0.path, g.land, g.path = nil, nil, nil, nil
        elseif p and g.mod and S.now - g.mod_at > CFG.SCAN_EVERY * 1.5 then
            g.land, g.path = nil, nil -- the modifier is gone: the dash or slam is over
        elseif p then
            seen[key] = true
            local s = samples[key]
            if not s then
                samples[key] = { pos = p, t = S.rt, start = p, t0 = S.rt }
            elseif g.mod and spell.aim then
                -- a wind-up: the hero stands still, so the lane points where he aims, up and down
                -- included. Full length with no wall check: the dash isn't stopped by props like
                -- parked cars. Range counts from where the wind-up began, so once the dash runs the
                -- lane's end stays put.
                local f, src = U.aim_dir(g.landing_ent)
                if f then
                    local range = U.ability_value(g.owner, spell, spell.range_prop, spell.range or 30)
                    local v = Vector(f.x * 1000, f.y * 1000, f.z * 1000)
                    local ok, land, path = pcall(predict_line, p, v, g.landing_ent, s.start, range, p, true)
                    if ok then s.land, s.path = land, path end
                    if not s.logged and ui.sp_debug:Get() then
                        s.logged = true
                        log("%s lane: %.1f m, aimed by %s", spell.name, range / CFG.UNITS_PER_M, src)
                    end
                end
            elseif spell.motion == "line" and not g.mod then
                -- straight flight: the average velocity since first seen is exact, and is ready
                -- from the next frame, which fast shots need; no waiting for VEL_SAMPLE
                local el = S.rt - s.t0
                if el > 0 then
                    local v = Vector((p.x - s.start.x) / el, (p.y - s.start.y) / el, (p.z - s.start.z) / el)
                    local range = U.ability_value(g.owner, spell, spell.range_prop, spell.range or 30)
                    local ok, land, path = pcall(predict_line, p, v, g.landing_ent, s.start, range)
                    -- keep the last lane once the shot stops moving (it hit), so it stays drawn
                    if ok and land then s.land, s.path = land, path end
                end
            elseif g.mod and spell.motion == "line" and S.rt - s.t0 < CFG.VEL_SAMPLE then
                -- the first frames of a dash, before there is movement to measure: aim flat from
                -- where it started (a targeted dash goes at its target, so that is its direction)
                -- and let the measured velocity take over as soon as there is one
                local f = U.aim_dir(g.landing_ent)
                local flat = f and sqrt(f.x * f.x + f.y * f.y)
                if flat and flat > 0.01 then
                    local range = U.ability_value(g.owner, spell, spell.range_prop, spell.range or 30)
                    local v = Vector(f.x / flat * 1000, f.y / flat * 1000, 0)
                    local ok, land, path = pcall(predict_line, s.start, v, g.landing_ent, s.start, range, s.start)
                    if ok and land then s.land, s.path = land, path end
                end
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
                    if spell.min_speed and speed < spell.min_speed * CFG.UNITS_PER_M then
                        -- the modifier outlasts the dash itself: draw only while he moves at dash
                        -- speed. The lane goes with it, or Apollo's lunge stayed drawn for the whole
                        -- 5 s recast window he stood in after it
                        s.dash_from, s.land, s.path = nil, nil, nil
                    else
                        -- a dash can steer: latest velocity, the lane runs on from where the hero is
                        -- now, and its range counts from where this dash began
                        s.dash_from = s.dash_from or prev
                        local range = U.ability_value(g.owner, spell, spell.range_prop, spell.range or 30)
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
                end
                -- a dash that has covered its range has arrived: keep the landing it was heading
                -- for instead of blanking it on the frame the range runs out
                if ok and land then
                    s.land, s.path = land, path
                elseif not g.mod then
                    s.land, s.path = nil, nil
                end
            end
            g.land, g.path = samples[key].land, samples[key].path
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
local DASH_SPELLS = {}
for _, s in ipairs(SPELLS) do if s.dash_particle then DASH_SPELLS[#DASH_SPELLS + 1] = s end end

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

-- the hero's ability for `s` is in its cast delay or channel
local function in_cast(e, s)
    local ab = s.ability and U.find_ability(e, s.ability)
    return ab ~= nil and (HERO_LIB.is_ability_in_cast_delay(ab) or HERO_LIB.is_channeling_ability(ab)) == true
end

-- A cone's trigger particle (`cone_particle`) starts the fan on the hero that spawned it. The burst's
-- first sighting is kept, not the latest, so `cone_delay` counts from the swing and a sighting later
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
local hit_effect = lacks_ability

local function who(p)
    if handle(p) == handle(S.me) then return "you" end
    return HERO_LIB and HERO_LIB.is_same_team(S.me, p) == true and "an ally" or "an enemy"
end

-- Who cast `spell`, for particles and entities that don't say: the hero playing the spell's hero,
-- else the hero whose abilities show the spell. A match has each hero at most once, so neither is
-- a guess. A sandbox can spawn a second one; the first listed then gets it.
local function known_caster(spell)
    local dbg = ui.sp_debug:Get()
    local ids = {}
    for _, p in ipairs(S.pawns or {}) do
        local ok, id = pcall(HERO_LIB.get_hero_id, p)
        if ok and valid(p) and tonumber(id) == spell.hero_id then return p end
        if dbg then ids[#ids + 1] = ok and tostring(id) or "error" end
    end
    local holder = (S.holders[spell] or {})[1]
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
              dash_from = old and old.dash_from }
        groups[key] = g
    end
    return g
end

-- The group for a modifier spell on one hero, whichever of the dash particle, the frame poll or a
-- scan renews it: they share the key, so the group and its start time survive between them.
local function modifier_group(groups, spell, pawn, now)
    local g = group_for(groups, spell, pawn, "mod" .. tostring(handle(pawn)))
    g.caster, g.landing_ent, g.mod, g.mod_at, g.last = pawn, pawn, true, now, now
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
            for _, n in ipairs(names) do
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
        if s.modifier then
            s.modifier_low = s.modifier_low or s.modifier:lower() -- modifier_started runs every frame
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

    for _, e in ipairs(all) do
        if valid(e) then
            local is_pawn = try(e, "get_class_name") == "C_CitadelPlayerPawn"
            if is_pawn then
                note_holders(e, spells)
                S.pawns[#S.pawns + 1] = e
            end
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
                    if s and not (is_pawn and hit_effect(e, s)) then
                        spell = spell or s
                        if s == spell then matched[#matched + 1] = p end
                    end
                end
                if not spell then spell = match_class(e, spells) end
                if not spell and is_pawn then spell = casting_spell(e, spells) end
                if spell and is_pawn and hit_effect(e, spell) then spell = nil end

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
                        if (s.modifier and has_modifier(e, s.modifier) or s.aim and in_cast(e, s))
                            and not lacks_ability(e, s) then
                            local g = modifier_group(groups, s, e, now)
                            if not g.logged and ui.sp_debug:Get() then
                                g.logged = true
                                log("%s %s on %s", s.name, s.aim and "wind-up" or "modifier", who(e))
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
            if valid(ev.ent) and try(ev.ent, "get_class_name") == "C_CitadelPlayerPawn" and hit_effect(ev.ent, ev.spell) then
                -- on-hit effect on a victim: not drawn, and not worth a "no owner" log
            elseif not owner then
                if ui.sp_debug:Get() then log("event %d has no owner (entity=%s)", idx, ev.ent and "yes" or "no") end
            else
                local g = group_for(groups, ev.spell, owner, valid(ev.ent) and handle(ev.ent) or ("ev" .. idx))
                if #cps > 0 and not g.ent and valid(ev.ent) then g.ent = ev.ent end
                note_particle(g, ev.ent, ev.name, cps, ev.spell)
                -- a ground tell's own particle: the area is drawn while it lives (see projectile_gone)
                if ev.spell.warning and ev.name:lower():find(ev.spell.warning, 1, true) then g.warning_ev = idx end
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
    if not (ui.sp_land:Get() or ui.sp_arc:Get()) then return end
    for _, s in ipairs(S.mod_spells or {}) do -- the last scan's active spells with a modifier
        for _, e in ipairs(S.holders[s] or {}) do
            -- `aim`: the cast delay too, which is shorter than a scan (Leaping Slash's 0.1 s)
            if valid(e) and S.near[handle(e)] and (has_modifier(e, s.modifier) or s.aim and in_cast(e, s)) then
                modifier_group(S.groups, s, e, S.now)
            end
        end
    end
end

-- Leaping Slash's m_DashModifier is m_bIsHidden, and the poll above can miss it in game. The
-- add-modifier callback names the ability that made the modifier, which ties it to the entry
-- whatever the modifier reads as. Kept to `dash_particle` entries, the dashes shorter than a scan.
function X.track_modifier_add(mod, target)
    if not mod or not valid(target) or try(target, "get_class_name") ~= "C_CitadelPlayerPawn" then return end
    local ab = try(mod, "get_ability")
    local abil = ab and try(ab, "get_name") or ""
    local mine = handle(target) == handle(S.me)
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

-- particle callbacks ---------------------------------------------------------

-- Debug Mode: a bullet spell's skipped effects (an orb's hover where it stops, its impact) are
-- placed against the last shot, to measure how far and long the shot really flew
local probes = {}

function X.track_particle(d)
    if not d or type(d.name) ~= "string" or d.index == nil then return end
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
    local spell = match_particle(d.name, SPELLS)
    if not spell then return end
    local ent = d.entity or d.entity_for_modifiers
    S.events[d.index] = { name = d.name, ent = ent, spell = spell, first = S.now, last = S.now, cps = {},
        owner = resolve_owner(ent) }
    -- a projectile can be gone before the next 0.25s scan; scan on the next frame instead
    -- a modifier spell's particle means the move just started: look for the modifier now too;
    -- a cone's swing particle opens a window shorter than a scan, so place it now as well
    if spell.modifier or spell.projectile and low:find(spell.projectile, 1, true)
        or spell.cone_particle and low:find(spell.cone_particle, 1, true) then
        S.next_scan = 0
    end
    debug("particle %s", U.short_name(d.name))
end

-- Line spells fired as bullets: the game hands over the exact start and direction at the moment
-- of firing, so the lane is known before the first frame of flight and needs no tracking.
local unmatched_bullets = {}
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
    local range = U.ability_value(owner, spell, spell.range_prop, spell.range or 30)
    -- ignore the shooter so the wall trace doesn't stop on their own hitbox at the muzzle
    local land, path = predict_line(o, Vector(dir.x * 1000, dir.y * 1000, dir.z * 1000), owner, o, range)
    if not land then return end

    -- the shot's group lives for its flight time, then CLEAR_DELAY like any other group
    local flight = spell.speed and sqrt((land.x - o.x) ^ 2 + (land.y - o.y) ^ 2 + (land.z - o.z) ^ 2) / spell.speed or 0
    S.shot_n = S.shot_n + 1
    S.groups["shot" .. S.shot_n] = { spell = spell, owner = owner, first = S.now, last = S.now + flight,
        logged = true, particles = {}, seen = {}, land = land, path = path, shot = true, rt0 = S.rt }
    spell.bullet_owners = spell.bullet_owners or {}
    spell.bullet_owners[handle(owner)] = true
    S.list = S.groups
    if ui.sp_debug:Get() then log("bullet %s -> %s", d.weapon_name, spell.name) end
end

function X.update_particle(d)
    local pr = d and probes[d.index]
    if pr and d.position and d.control_point == 0 then
        probes[d.index] = nil
        local a, b = pr.shot.from, d.position
        log("%s: %s %.1f m from the shot, %.2f s after", pr.shot.spell.name, U.short_name(pr.name),
            sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2 + (b.z - a.z) ^ 2) / CFG.UNITS_PER_M, S.now - pr.shot.t)
    end
    local r = d and S.events[d.index]
    if not r then return end
    r.last = S.now
    if d.position then
        -- a landing warning's first position is the game's own landing ring: draw it this frame
        if next(r.cps) == nil and r.spell.warning and r.name:lower():find(r.spell.warning, 1, true) then
            S.next_scan = 0
        end
        if d.control_point == 0 and not r.from then r.from, r.from_t = d.position, S.now end
        r.cps[d.control_point] = { cp = d.control_point, origin = d.position }
    end
end

function X.destroy_particle(d)
    if d then probes[d.index] = nil end -- indexes are reused: a stale probe would log a stranger
    local ev = d and S.events[d.index]
    if ev then ev.dead = S.now end
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
