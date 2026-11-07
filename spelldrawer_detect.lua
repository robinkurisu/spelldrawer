-- Spell Drawer | spell detection: matching, owners, casts, particle events,
-- landing prediction and the periodic scan that builds the draw list

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

local function predict_landing(e, spell)
    local o = try(e, "get_origin")
    local v = try(e, "get_velocity")
    if not o or not v then return nil end
    if sqrt(v.x * v.x + v.y * v.y + v.z * v.z) < 100 then return nil end

    local g = -gravity() * (spell.gravity_scale or 1)
    local dt = 0.02
    local pos = Vector(o.x, o.y, o.z)
    local vel = Vector(v.x, v.y, v.z)
    local path = { pos }

    for _ = 1, 250 do
        local nv = Vector(vel.x, vel.y, vel.z + g * dt)
        local np = Vector(pos.x + vel.x * dt, pos.y + vel.y * dt, pos.z + vel.z * dt + 0.5 * g * dt * dt)
        local tr = trace_line(pos, np, e)
        local frac = tr and field(tr, "fraction")
        if type(frac) == "number" and frac < 1 then
            local hit = Vector(
                pos.x + (np.x - pos.x) * frac,
                pos.y + (np.y - pos.y) * frac,
                pos.z + (np.z - pos.z) * frac + 4)
            return hit, path
        end
        pos, vel = np, nv
        path[#path + 1] = pos
        if pos.z < -12000 then return nil end
    end
    return nil
end

-- matching -------------------------------------------------------------------

local function active_spells()
    local list = {}
    for _, s in ipairs(SPELLS) do
        if s.ui and s.ui:Get() then list[#list + 1] = s end
    end
    return list
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
        if match_text(name, s.particles) and not match_text(name, s.skip or {}) then return s end
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
                    local cd = tonumber(try(ab, "get_cooldown")) or 0
                    local key = h .. ":" .. name
                    local prev = S.cooldowns[key]
                    if prev ~= nil and prev <= 0 and cd > 0 then
                        S.casters[s] = { hero = e, at = S.now }
                        debug("cast detected: %s", s.name)
                    end
                    S.cooldowns[key] = cd
                end
            end
        end
    end
end

local function known_caster(spell)
    local c = S.casters[spell]
    if c and S.now - c.at < 3 then return c.hero end
    return nil
end

-- groups ---------------------------------------------------------------------

-- one group per spell instance (projectile entity, pawn, or loose particle) so simultaneous casts don't share one
local function group_for(groups, spell, owner, inst)
    local key = spell.id .. ":" .. tostring(inst)
    local g = groups[key]
    if not g then
        local old = S.groups[key]
        g = { spell = spell, owner = owner, first = old and old.first or S.now, logged = old and old.logged,
              particles = {}, seen = {} }
        groups[key] = g
    end
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
        and try(e, "get_class_name") ~= "C_CitadelPlayerPawn" then
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
        if not g.landing_ent then
            local best, best_d
            for _, o in pairs(groups) do
                if o.landing_ent and o.spell == g.spell and handle(o.owner) == handle(g.owner) then
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
    local groups = {}
    if #spells == 0 then
        debug("scan skipped: every spell switch is off")
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
                        if not g.logged then
                            g.logged = true
                            if ui.sp_debug:Get() then
                                log("detected %s on %s", spell.name, try(e, "get_class_name") or "?")
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
            local owner = ev.owner or resolve_owner(ev.ent) or known_caster(ev.spell)
            if not owner then
                if ui.sp_debug:Get() then log("event %d has no owner (entity=%s)", idx, ev.ent and "yes" or "no") end
            else
                local g = group_for(groups, ev.spell, owner, valid(ev.ent) and handle(ev.ent) or ("ev" .. idx))
                if #cps > 0 and not g.ent and valid(ev.ent) then g.ent = ev.ent end
                note_particle(g, ev.ent, ev.name, cps, ev.spell)
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
    local want_land = ui.sp_land:Get() or ui.sp_arc:Get()
    for _, g in pairs(groups) do
        if want_land and g.spell.landing and valid(g.landing_ent) then
            local okl, land, path = pcall(predict_landing, g.landing_ent, g.spell)
            g.land, g.path = okl and land or nil, okl and path or nil
        end
    end
    fold_into_projectiles(groups)
    S.groups = groups
    S.list = groups
end

-- particle callbacks ---------------------------------------------------------

function X.track_particle(d)
    if not d or type(d.name) ~= "string" or d.index == nil then return end
    local spell = match_particle(d.name, SPELLS)
    if not spell then return end
    local ent = d.entity or d.entity_for_modifiers
    S.events[d.index] = { name = d.name, ent = ent, spell = spell, first = S.now, last = S.now, cps = {},
        owner = resolve_owner(ent) }
    debug("particle %s", U.short_name(d.name))
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
