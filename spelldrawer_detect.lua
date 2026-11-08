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
    -- a straight dive that isn't heading down yet (the hop or hang before it): it lands straight below
    if g == 0 and v.z > -100 then v = Vector(0, 0, -1000) end
    if sqrt(v.x * v.x + v.y * v.y + v.z * v.z) < 100 then return nil end

    local dt = 0.02
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
        if p and g.mod and S.now - g.mod_at > CFG.SCAN_EVERY * 1.5 then
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
                local f, from_eyes = U.aim_dir(g.landing_ent)
                if f then
                    local range = U.ability_value(g.owner, spell, spell.range_prop, spell.range or 30)
                    local v = Vector(f.x * 1000, f.y * 1000, f.z * 1000)
                    local ok, land, path = pcall(predict_line, p, v, g.landing_ent, s.start, range, p, true)
                    if ok then s.land, s.path = land, path end
                    if not s.logged and ui.sp_debug:Get() then
                        s.logged = true
                        log("%s lane: %.1f m, aimed by %s", spell.name, range / CFG.UNITS_PER_M,
                            from_eyes and "eye angles" or "body facing (no up/down)")
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
            elseif g.mod and S.rt - s.t0 < CFG.VEL_SAMPLE then
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
                        -- the modifier outlasts the dash itself: draw only while he moves at dash speed
                        s.dash_from = nil
                    else
                        -- a dash can steer: latest velocity, the lane runs on from where the hero is
                        -- now, and its range counts from where this dash began
                        s.dash_from = s.dash_from or prev
                        local range = U.ability_value(g.owner, spell, spell.range_prop, spell.range or 30)
                        ok, land, path = pcall(predict_line, p, v, g.landing_ent, s.dash_from, range, p)
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
    local names = { try(e, "get_class_name") or "", try(e, "get_vdata_class_name") or "" }
    for _, s in ipairs(spells) do
        for _, key in ipairs(s.classes or {}) do
            for _, n in ipairs(names) do
                if n ~= "" and n:lower():find(key, 1, true) then return s end
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

local function note_casts(e, spells)
    local h = handle(e)
    if not h then return end
    for _, slot in ipairs(U.SLOTS) do
        local ab = try(e, "get_ability_by_slot", slot)
        local name = ab and try(ab, "get_name")
        if name then
            for _, s in ipairs(spells) do
                if s.ability and name:find(s.ability, 1, true) then
                    S.holders[s] = S.holders[s] or {}
                    table.insert(S.holders[s], e)
                    local cd = tonumber(try(ab, "get_cooldown")) or 0
                    local key = h .. ":" .. name
                    local prev = S.cooldowns[key]
                    if prev ~= nil and prev <= 0 and cd > 0 then
                        S.casters[s] = S.casters[s] or {}
                        S.casters[s][h] = { hero = e, at = S.now }
                        debug("cast detected: %s", s.name)
                    end
                    S.cooldowns[key] = cd
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

-- A cone's trigger starts the fan on the hero that spawned it. The burst's first sighting is kept,
-- not the latest, so `cone_delay` counts from the swing and a sighting later in the same burst
-- doesn't push the fan back; a gap means a new burst and a new clock. The trigger is the
-- `cone_particle` on the hero, or any live particle of a cone spell: a blast that flies as a bullet
-- (Light Eater's tracer) keeps the fan up, on his aim, for as long as the projectile is in the air.
local function note_cone(g, hero, now)
    if not g.cone_at or now - (g.cone_seen or 0) > CFG.SCAN_EVERY * 1.5 then g.cone_at = now end
    g.cone_seen, g.caster = now, hero
end

local function hit_effect(pawn, spell)
    return spell.ability ~= nil and U.find_ability(pawn, spell.ability) == nil
end

-- Who cast `spell`, for particles that don't say. With `pos` (where a projectile was first seen,
-- i.e. at its thrower's hand): the nearest hero who has the spell. Cast detection can't decide this,
-- as other heroes' cooldowns don't always show a cast. Without `pos`: the most recent detected cast.
local function known_caster(spell, pos)
    local best, best_d
    if pos then
        for _, p in ipairs(S.holders[spell] or {}) do
            local o = valid(p) and try(p, "get_origin")
            local d = o and (o.x - pos.x) ^ 2 + (o.y - pos.y) ^ 2 + (o.z - pos.z) ^ 2
            if d and (not best_d or d < best_d) then best, best_d = p, d end
        end
        if best then return best end
    end
    for _, c in pairs(S.casters[spell] or {}) do
        if S.now - c.at < 3 and valid(c.hero) and (not best_d or S.now - c.at < best_d) then
            best, best_d = c.hero, S.now - c.at
        end
    end
    return best
end

local function who(p)
    if handle(p) == handle(S.me) then return "you" end
    return HERO_LIB and HERO_LIB.is_same_team(S.me, p) == true and "an ally" or "an enemy"
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
              particles = {}, seen = {}, cone_at = old and old.cone_at, cone_seen = old and old.cone_seen }
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

local function note_particle(g, e, name, cps, spell)
    add_particle(g, name, cps)
    local low = (name or ""):lower()
    if spell.projectile and not g.landing_ent and valid(e) and low:find(spell.projectile, 1, true)
        and (spell.follow_caster or try(e, "get_class_name") ~= "C_CitadelPlayerPawn") then
        g.landing_ent = e
    end
    if spell.warning and low:find(spell.warning, 1, true) and not g.warning then
        local cp = cps and cps[1]
        if cp then g.warning = cp.origin end
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

function X.scan()
    local now = S.now
    if now < S.next_scan then return end
    S.next_scan = now + CFG.SCAN_EVERY

    local spells = active_spells()
    S.holders = {}
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
            if is_pawn then note_casts(e, spells) end
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

                local spell, matched = nil, {}
                for _, p in ipairs(particles or {}) do
                    local s = match_particle(p.name, spells)
                    if s then
                        spell = spell or s
                        matched[#matched + 1] = p
                    end
                end
                if not spell then spell = match_class(e, spells) end
                if not spell and is_pawn then spell = casting_spell(e, spells) end
                if spell and is_pawn and hit_effect(e, spell) then spell = nil end

                if spell then
                    local owner = resolve_owner(e) or known_caster(spell, o)
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
                        -- a pawn without the ability carrying the modifier is an on-hit victim, and
                        -- this modifier's name is shared with the hero whose dash class it is
                        if s.modifier and has_modifier(e, s.modifier) and not hit_effect(e, s)
                            or s.aim and in_cast(e, s) then
                            modifier_group(groups, s, e, now)
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
                -- no owner on the particle: guess once and keep it, since a later guess sees the
                -- projectile away from its thrower. A warning sits at the landing spot and gets
                -- its colour from the projectile it folds into.
                local proj = ev.spell.projectile and ev.name:lower():find(ev.spell.projectile, 1, true)
                local at = cps[1] and cps[1].origin
                if proj and not at and now - ev.first < 0.5 then
                    S.next_scan = 0 -- no position yet to find the thrower by; look again next frame
                else
                    owner = known_caster(ev.spell, proj and at or nil)
                    ev.owner = owner
                    if owner and ui.sp_debug:Get() then log("event %d owner guessed: %s", idx, who(owner)) end
                end
            end
            if valid(ev.ent) and try(ev.ent, "get_class_name") == "C_CitadelPlayerPawn" and hit_effect(ev.ent, ev.spell) then
                -- on-hit effect on a victim: not drawn, and not worth a "no owner" log
            elseif not owner then
                if ui.sp_debug:Get() then log("event %d has no owner (entity=%s)", idx, ev.ent and "yes" or "no") end
            else
                local g = group_for(groups, ev.spell, owner, valid(ev.ent) and handle(ev.ent) or ("ev" .. idx))
                if #cps > 0 and not g.ent and valid(ev.ent) then g.ent = ev.ent end
                note_particle(g, ev.ent, ev.name, cps, ev.spell)
                -- a cone's trigger: the fan runs while any particle of the spell is live, since an
                -- event only exists for a matched, non-skipped one. It starts on the hero the
                -- particle was spawned on, whether the game reports it on him, on a child entity or
                -- on the blast's own projectile (a cone whose blast flies as a bullet, e.g. Light
                -- Eater's tracer, keeps its fan up for the flight); a dead one stops renewing it
                if ev.spell.motion == "cone" and not ev.dead
                    and valid(owner) and try(owner, "get_class_name") == "C_CitadelPlayerPawn" then
                    note_cone(g, owner, now)
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
    for _, s in ipairs(active_spells()) do
        local holders = s.modifier and S.holders[s]
        for _, e in ipairs(holders or {}) do
            if valid(e) and S.near[handle(e)] and has_modifier(e, s.modifier) then
                modifier_group(S.groups, s, e, S.now)
            end
        end
    end
end

-- particle callbacks ---------------------------------------------------------

function X.track_particle(d)
    if not d or type(d.name) ~= "string" or d.index == nil then return end
    local low = d.name:lower()
    -- a dash's own particle starts its track on the hero at the instant the dash does, which for a
    -- dash shorter than a scan is the one moment a scan can step over; the modifier poll then
    -- carries the group while he moves. The hero is the projectile, so it returns here.
    for _, s in ipairs(DASH_SPELLS) do
        if low:find(s.dash_particle, 1, true) then
            local pawn = resolve_owner(d.entity or d.entity_for_modifiers)
            if valid(pawn) and try(pawn, "get_class_name") == "C_CitadelPlayerPawn" and not hit_effect(pawn, s) then
                modifier_group(S.groups, s, pawn, S.now)
                S.next_scan = 0 -- lists his abilities and starts the sample now, not next scan
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
    -- a modifier spell's particle means the move just started: look for the modifier now too
    if spell.modifier or spell.projectile and d.name:lower():find(spell.projectile, 1, true) then
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
    local r = d and S.events[d.index]
    if not r then return end
    r.last = S.now
    if d.position then
        r.cps[d.control_point] = { cp = d.control_point, origin = d.position }
    end
end

function X.destroy_particle(d)
    local ev = d and S.events[d.index]
    if ev then ev.dead = S.now end
end

return X
