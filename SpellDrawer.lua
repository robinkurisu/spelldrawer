-- Spell Drawer | draws known spell particles and spell entities in the world
--
-- Spells are detected individually. Each registry entry owns:
--   id       unique menu id
--   name     display name
--   ability  runtime ability name for cast detection
--   classes  class / vdata class substrings for the spell entity
--   particles particle name substrings spawned by the spell
--
-- Only particles and entities matched by an enabled entry are drawn.

local SCRIPT = "Spell Drawer"

local CFG = {
    UNITS_PER_M = 39.37,
    HEAD = 70,
    SCAN_EVERY = 0.25,
    CLEAR_DELAY = 0.5,
    MAX_CP = 24,
    GRAVITY_FALLBACK = 800,
    TRACE = { with = 0x1C1003, exclude = 0, as = 0, object_set = 7, group = 4 },
    DEFAULTS = {
        sp_enable = true,
        sp_enemy = true,
        sp_ally = false,
        sp_local = true,
        sp_boxes = true,
        sp_points = true,
        sp_labels = false,
        sp_land = true,
        sp_arc = true,
        sp_debug = true,
        sp_size = 4,
        sp_dist = 120,
    },
}

local SPELLS = {
    {
        id = "ghost_blood_bomb",
        name = "Lady Geist: Blood Bomb",
        image = "panorama/images/hud/abilities/spectre/blood_bomb_psd.vtex_c",
        ability = "ability_blood_bomb",
        classes = { "blood_bomb" },
        particles = { "ghost_blood_bomb" },
        landing = true,
        projectile = "ghost_blood_bomb_projectile",
        warning = "ghost_blood_bomb_warning",
        skip = { "ghost_blood_bomb_preview" },
        radius_prop = "Radius",
        gravity_scale = 1.0,
    },
}

local OWNER_FIELDS = { "m_hOwnerEntity", "m_hOwner", "m_hCaster", "m_hAbilityOwner", "m_hOwnerPawn", "m_nOwner" }
local SLOTS = {
    EAbilitySlots_t and EAbilitySlots_t.ESlot_Signature_1 or 0,
    EAbilitySlots_t and EAbilitySlots_t.ESlot_Signature_2 or 1,
    EAbilitySlots_t and EAbilitySlots_t.ESlot_Signature_3 or 2,
    EAbilitySlots_t and EAbilitySlots_t.ESlot_Signature_4 or 3,
}

local fmt, sqrt = string.format, math.sqrt
local cos, sin, pi = math.cos, math.sin, math.pi
local now = 0

local function log(f, ...) print(fmt("[%s %.2f] ", SCRIPT, now) .. fmt(f, ...)) end
local function call(obj, method, ...) return obj[method](obj, ...) end
local function index(obj, name) return obj[name] end

local function try(obj, method, ...)
    if obj == nil then return nil end
    local ok, v = pcall(call, obj, method, ...)
    if ok then return v end
    return nil
end

local function field(obj, name)
    if obj == nil then return nil end
    local ok, v = pcall(index, obj, name)
    if ok then return v end
    return nil
end

local function valid(e) return e ~= nil and try(e, "valid") == true end
local function handle(e) return e and try(e, "get_handle") end

local ui = {}
local grp_main = Menu.Create(SCRIPT, "", "Spells", "Drawer", "Spells")
local tab_main = grp_main:Parent()
local tab_root = tab_main:Parent()
pcall(function() tab_root:Parent():Parent():Icon("\u{f02d}") end)

local function reset_tab()
    for k, v in pairs(CFG.DEFAULTS) do pcall(ui[k].Set, ui[k], v) end
    for _, s in ipairs(SPELLS) do pcall(s.ui.Set, s.ui, true) end
    log("[RESET] settings back to the defaults")
end

ui.sp_enable = grp_main:Switch("Enable", CFG.DEFAULTS.sp_enable)
ui.sp_enable:ToolTip("Draws detected spell particles and spell entities in the world.")
ui.sp_enemy = grp_main:Switch("Enemy Spells", CFG.DEFAULTS.sp_enemy)
ui.sp_enemy:ToolTip("Draws spells owned by enemies.")
ui.sp_ally = grp_main:Switch("Ally Spells (debug)", CFG.DEFAULTS.sp_ally)
ui.sp_ally:ToolTip("Draws spells owned by allies too. Useful for debugging.")
ui.sp_local = grp_main:Switch("Local Spells", CFG.DEFAULTS.sp_local)
ui.sp_local:ToolTip("Draws spells you cast yourself. Useful for testing.")
for _, s in ipairs(SPELLS) do
    s.ui = grp_main:Switch(s.name, true)
    s.ui:ToolTip("Draw " .. s.name .. ".")
end

local grp_opt = tab_main:Create("Draw", Enum.GroupSide.Right)

ui.sp_boxes = grp_opt:Switch("World Pins", CFG.DEFAULTS.sp_boxes)
ui.sp_boxes:ToolTip("Draws a world-anchored pin with a ground ring on the spell.")
ui.sp_points = grp_opt:Switch("Particle Points", CFG.DEFAULTS.sp_points)
ui.sp_points:ToolTip("Marks particle control points with world crosses.")
ui.sp_labels = grp_opt:Switch("Labels", CFG.DEFAULTS.sp_labels)
ui.sp_labels:ToolTip("Adds text labels. This is the only screen-space part.")
ui.sp_land = grp_opt:Switch("Landing Marker", CFG.DEFAULTS.sp_land)
ui.sp_land:ToolTip("Predicts where the spell will land and draws its area.")
ui.sp_arc = grp_opt:Switch("Trajectory", CFG.DEFAULTS.sp_arc)
ui.sp_arc:ToolTip("Draws the predicted projectile path.")
ui.sp_debug = grp_opt:Switch("Debug Log", CFG.DEFAULTS.sp_debug)
ui.sp_debug:ToolTip("Logs what is detected to the console.")
ui.sp_size = grp_opt:Slider("Marker Size", 1, 12, CFG.DEFAULTS.sp_size, "%d u")
ui.sp_size:ToolTip("World-space size of the particle crosses.")
ui.sp_dist = grp_opt:Slider("Max Distance", 0, 200, CFG.DEFAULTS.sp_dist, "%d m")
ui.sp_dist:ToolTip("Hides spells further away than this. 0 means no limit.")
grp_opt:Button("Reset to defaults", reset_tab):ToolTip("Resets the Spell Drawer settings to the defaults.")

local S = { me = nil }
local LIST = {}
local EVENTS = {}
local next_scan = 0
local last_log = 0
local last_draw_n = -1
local last_state = ""
local font
do
    local ok, h = pcall(Render.LoadFont, "Tahoma", Enum.FontCreate and Enum.FontCreate.FONTFLAG_ANTIALIAS or 16, 700)
    if ok then font = h end
end

local ENEMY = Color(255, 85, 85)
local ALLY = Color(90, 190, 255)

local function my_origin() return S.me and try(S.me, "get_origin") end

local function dist_to_me(o)
    local m = my_origin()
    if not m or not o then return nil end
    local dx, dy, dz = o.x - m.x, o.y - m.y, o.z - m.z
    return sqrt(dx * dx + dy * dy + dz * dz)
end

local function project(o)
    if not o then return nil end
    local s, on_screen = Render.WorldToScreen(o)
    return on_screen and s or nil
end

local function world_ring(center, radius, color, thickness, segments)
    local pts = {}
    for i = 0, segments do
        local a = (i / segments) * pi * 2
        local sp = project(Vector(center.x + cos(a) * radius, center.y + sin(a) * radius, center.z))
        if sp then pts[#pts + 1] = sp end
    end
    if #pts > 2 then Render.PolyLine(pts, color, thickness) end
end

local function world_cross(p, size, color, thickness)
    local axes = { { size, 0, 0 }, { 0, size, 0 }, { 0, 0, size } }
    for _, axis in ipairs(axes) do
        local a = project(Vector(p.x - axis[1], p.y - axis[2], p.z - axis[3]))
        local b = project(Vector(p.x + axis[1], p.y + axis[2], p.z + axis[3]))
        if a and b then Render.Line(a, b, color, thickness or 1) end
    end
end

local function world_pin(o, color)
    local base = project(o)
    if not base then return end
    local top = project(Vector(o.x, o.y, o.z + CFG.HEAD))
    if top then Render.Line(base, top, Color(color.r, color.g, color.b, 200), 1) end
    world_ring(o, 10, Color(color.r, color.g, color.b, 140), 1, 16)
end

local function text(pos, str, color, size)
    if not font or not str then return end
    size = size or 11
    Render.Text(font, size, str, Vec2(pos.x + 1, pos.y + 1), Color(0, 0, 0, 220))
    Render.Text(font, size, str, pos, color)
end

local function short_name(s)
    s = tostring(s or "?")
    s = s:gsub("^particles/", ""):gsub("%.vpcf$", "")
    if #s > 34 then s = s:sub(#s - 33) end
    return s
end

local function debug(msg, ...)
    if not ui.sp_debug:Get() or now - last_log < 0.5 then return end
    last_log = now
    log(msg, ...)
end

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

local function spell_radius(owner, spell)
    local ab = try(owner, "get_ability", spell.ability)
    local r = ab and tonumber(try(ab, "get_scaled_property", spell.radius_prop))
    if r and r < 50 then r = r * CFG.UNITS_PER_M end
    return r or 7 * CFG.UNITS_PER_M
end

local function draw_marker(land, owner, spell, color)
    local radius = spell_radius(owner, spell)
    world_ring(land, radius, Color(color.r, color.g, color.b, 220), 2, 64)
    world_ring(land, radius * 0.5, Color(color.r, color.g, color.b, 90), 1, 48)
    world_cross(land, 20, Color(color.r, color.g, color.b, 240), 2)

    if ui.sp_labels:Get() then
        local center = project(land)
        if center then text(Vec2(center.x + 8, center.y - 8), spell.name .. " landing", color) end
    end
end

local function draw_landing(e, owner, spell, color)
    local land, path = predict_landing(e, spell)

    if ui.sp_arc:Get() and path then
        local prev
        for _, pt in ipairs(path) do
            local sp = project(pt)
            if sp and prev then Render.Line(prev, sp, Color(color.r, color.g, color.b, 120), 1) end
            prev = sp
        end
    end

    if land and ui.sp_land:Get() then draw_marker(land, owner, spell, color) end
end

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
        if match_text(name, s.particles) then return s end
    end
    return nil
end

local seen_hero = {}

local function log_hero(e)
    local h = handle(e)
    if not h or seen_hero[h] then return end
    seen_hero[h] = true
    local names = {}
    for _, slot in ipairs(SLOTS) do
        local ab = try(e, "get_ability_by_slot", slot)
        local n = ab and try(ab, "get_name")
        if n then names[#names + 1] = n end
    end
    log("hero %s abilities: %s", try(e, "get_name") or "?", table.concat(names, ", "))
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
    for _, slot in ipairs(SLOTS) do
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

local function resolve_owner(e)
    for _ = 1, 8 do
        if not e then return nil end
        if try(e, "get_class_name") == "C_CitadelPlayerPawn" then return e end
        local next_e
        for _, f in ipairs(OWNER_FIELDS) do
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

local CASTERS = {}
local COOLDOWNS = {}

local function note_casts(e, spells)
    local h = handle(e)
    if not h then return end
    for _, slot in ipairs(SLOTS) do
        local ab = try(e, "get_ability_by_slot", slot)
        local name = ab and try(ab, "get_name")
        if name then
            for _, s in ipairs(spells) do
                if s.ability and name:find(s.ability, 1, true) then
                    local cd = tonumber(try(ab, "get_cooldown")) or 0
                    local key = h .. ":" .. name
                    local prev = COOLDOWNS[key]
                    if prev ~= nil and prev <= 0 and cd > 0 then
                        CASTERS[s] = { hero = e, at = now }
                        debug("cast detected: %s", s.name)
                    end
                    COOLDOWNS[key] = cd
                end
            end
        end
    end
end

local function known_caster(spell)
    local c = CASTERS[spell]
    if c and now - c.at < 3 then return c.hero end
    return nil
end

local function nearest_hero(o)
    if not o then return nil end
    local ok, list = pcall(HERO_LIB.get_all_heroes, S.me, true, true, false)
    local best, best_d
    for _, h in ipairs(ok and list or {}) do
        local ho = try(h, "get_origin")
        if ho then
            local d = sqrt((ho.x - o.x) ^ 2 + (ho.y - o.y) ^ 2 + (ho.z - o.z) ^ 2)
            if not best_d or d < best_d then best_d, best = d, h end
        end
    end
    if best_d and best_d < 1500 then return best end
    return nil
end

local GROUPS = {}

local function is_skip(name, spell)
    return match_text(name, spell.skip or {})
end

local function group_for(groups, spell, owner)
    local key = spell.id .. ":" .. tostring(handle(owner))
    local g = groups[key]
    if not g then
        local old = GROUPS[key]
        g = { spell = spell, owner = owner, first = old and old.first or now, logged = old and old.logged,
              particles = {}, seen = {} }
        groups[key] = g
    end
    return g
end

local function add_particle(g, name, cps)
    if is_skip(name, g.spell) then return end
    local out = {}
    for _, cp in ipairs(cps or {}) do
        local o = cp.origin
        local key = fmt("%s:%.0f:%.0f:%.0f", tostring(name), o.x, o.y, o.z)
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
    if spell.projectile and low:find(spell.projectile, 1, true) then g.landing_ent = e end
    if spell.warning and low:find(spell.warning, 1, true) and not g.warning then
        local cp = cps and cps[1]
        if cp then g.warning = cp.origin end
    end
end

local function scan()
    if now < next_scan then return end
    next_scan = now + CFG.SCAN_EVERY

    local spells = active_spells()
    local groups = {}
    if #spells == 0 then
        log("no spell selected")
        LIST = groups
        return
    end
    local event_count = 0
    for _ in pairs(EVENTS) do event_count = event_count + 1 end
    log("scan: active=%d events=%d", #spells, event_count)

    local md = ui.sp_dist:Get() or 0
    local ok, all = pcall(entity_list.get_all)
    if not ok or type(all) ~= "table" then LIST = groups return end

    for _, e in ipairs(all) do
        if valid(e) then
            local is_pawn = try(e, "get_class_name") == "C_CitadelPlayerPawn"
            if is_pawn then
                if ui.sp_debug:Get() then log_hero(e) end
                note_casts(e, spells)
            end
            local o = try(e, "get_origin")
            local near = true
            if o and md > 0 then
                local d = dist_to_me(o)
                near = not d or d / CFG.UNITS_PER_M <= md + 20
            end
            if near then
                local okp, particles = pcall(call, e, "get_particles")
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
                        local g = group_for(groups, spell, owner)
                        if is_pawn then g.caster = g.caster or e end
                        if #matched > 0 then
                            if not g.ent and not is_pawn then g.ent = e end
                            for _, p in ipairs(matched) do
                                note_particle(g, e, p.name, p.control_points, spell)
                            end
                        end
                        if not g.logged then
                            g.logged = true
                            log("detected %s on %s", spell.name, try(e, "get_class_name") or "?")
                        end
                    end
                end
            end
        end
    end

    local active = {}
    for _, s in ipairs(spells) do active[s] = true end
    for idx, ev in pairs(EVENTS) do
        local age = now - (ev.last or ev.first)
        if age > 15 or (ev.dead and now - ev.dead > 1) or not active[ev.spell] then
            EVENTS[idx] = nil
        else
            local cps = {}
            for _, cp in pairs(ev.cps) do cps[#cps + 1] = cp end
            local owner = ev.owner or resolve_owner(ev.ent) or known_caster(ev.spell) or ev.near
            if not owner then
                if ui.sp_debug:Get() then log("event %d has no owner (entity=%s)", idx, ev.ent and "yes" or "no") end
            else
                local g = group_for(groups, ev.spell, owner)
                if #cps > 0 and not g.ent and valid(ev.ent) then g.ent = ev.ent end
                note_particle(g, ev.ent, ev.name, cps, ev.spell)
                if not ev.merged then
                    ev.merged = true
                    log("event %d merged: %s", idx, ev.spell.name)
                end
            end
        end
    end

    for key, g in pairs(GROUPS) do
        if not groups[key] and now - (g.last or g.first) < CFG.CLEAR_DELAY then groups[key] = g end
    end
    for _, g in pairs(groups) do g.last = now end
    GROUPS = groups
    LIST = groups
end

local function draw_entity(rec, lp)
    local e, owner, spell = rec.ent or rec.caster, rec.owner, rec.spell
    if not valid(owner) or not spell then return end

    local self_cast = handle(owner) == handle(lp)
    local same = self_cast or HERO_LIB.is_same_team(lp, owner) == true
    if self_cast then
        if not ui.sp_local:Get() then return end
    elseif same then
        if not ui.sp_ally:Get() then return end
    elseif not ui.sp_enemy:Get() then
        return
    end

    local o
    if valid(e) then o = try(e, "get_origin") end
    if not o and rec.warning then o = rec.warning end
    if not o then
        local first = rec.particles and rec.particles[1]
        local cp = first and first.control_points and first.control_points[1]
        o = cp and cp.origin or rec.origin
    end
    if not o then return end
    local md = ui.sp_dist:Get() or 0
    if md > 0 then
        local d = dist_to_me(o)
        if d and d / CFG.UNITS_PER_M > md then return end
    end

    local color = same and ALLY or ENEMY
    if spell.landing and (ui.sp_land:Get() or ui.sp_arc:Get()) then
        if valid(rec.landing_ent) and try(rec.landing_ent, "get_class_name") ~= "C_CitadelPlayerPawn" then
            pcall(draw_landing, rec.landing_ent, owner, spell, color)
        elseif rec.warning and ui.sp_land:Get() then
            pcall(draw_marker, rec.warning, owner, spell, color)
        end
    end
    if ui.sp_boxes:Get() then world_pin(o, color) end
    if ui.sp_labels:Get() then
        local base = project(o)
        if base then text(Vec2(base.x + 8, base.y - 10), fmt("%s %.1fs", spell.name, now - rec.first), color) end
    end

    if not ui.sp_points:Get() then return end
    local size = (ui.sp_size:Get() or CFG.DEFAULTS.sp_size) + 2
    local count, labels = 0, 0
    for _, p in ipairs(rec.particles or {}) do
        if count >= CFG.MAX_CP then break end
        local named = false
        for _, cp in ipairs(p.control_points or {}) do
            if count >= CFG.MAX_CP then break end
            count = count + 1
            world_cross(cp.origin, size, Color(color.r, color.g, color.b, 210), 1)
            if ui.sp_labels:Get() and not named and labels < 3 then
                named = true
                labels = labels + 1
                local sp = project(cp.origin)
                if sp then text(Vec2(sp.x + 6, sp.y - 6), short_name(p.name), color) end
            end
        end
    end
end

callback.on_frame:set(function()
    now = global_vars.curtime()
    local lp = entity_list.local_pawn()
    S.me = (valid(lp) and try(lp, "is_alive") == true) and lp or nil
    local state = tostring(ui.sp_enable:Get()) .. "/" .. tostring(S.me ~= nil) .. "/" .. tostring(HERO_LIB ~= nil)
    if state ~= last_state then
        last_state = state
        log("state enable/me/hero=%s", state)
    end
    if ui.sp_enable:Get() and S.me and HERO_LIB then
        local ok, err = pcall(scan)
        if not ok then log("scan error: %s", err) end
    else
        LIST = {}
        EVENTS = {}
    end
end)

callback.on_draw:set(function()
    if not ui.sp_enable:Get() or not HERO_LIB then return end
    local lp = S.me
    if not valid(lp) then return end
    local n = 0
    for _, rec in pairs(LIST) do pcall(draw_entity, rec, lp); n = n + 1 end
    if n ~= last_draw_n then
        last_draw_n = n
        log("drawing %d records", n)
    end
end)

local function track_particle(d)
    if not d or type(d.name) ~= "string" or d.index == nil then return end
    local spells = SPELLS
    if ui.sp_debug:Get() then
        local low = d.name:lower()
        if low:find("bomb", 1, true) or low:find("ghost", 1, true) or low:find("blood", 1, true) then
            log("particle event: %s", d.name)
            log("track -> %s (active %d, index=%s)", (match_particle(d.name, spells) or {}).id or "nil",
                #spells, tostring(d.index))
        end
    end
    local spell = match_particle(d.name, spells)
    if not spell then return end
    local ent = d.entity or d.entity_for_modifiers
    EVENTS[d.index] = { name = d.name, ent = ent, spell = spell, first = now, last = now, cps = {},
        owner = resolve_owner(ent) }
    debug("particle %s", short_name(d.name))
end

local function update_particle(d)
    local r = d and EVENTS[d.index]
    if not r then return end
    r.last = now
    if d.position then
        r.cps[d.control_point] = { cp = d.control_point, origin = d.position }
        r.near = r.near or nearest_hero(d.position)
    end
end

callback.on_particle_create:set(track_particle)
callback.on_particle_update:set(update_particle)
callback.on_particle_update_transform:set(update_particle)
callback.on_particle_destroy:set(function(d)
    local ev = d and EVENTS[d.index]
    if ev then ev.dead = now end
end)

log(fmt("loaded with %d registered spell(s)", #SPELLS))
