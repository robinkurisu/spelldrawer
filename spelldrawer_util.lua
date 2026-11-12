-- Spell Drawer | shared config, runtime state and safe-access helpers

local U = {}

U.SCRIPT = "Evade"

U.CFG = {
    UNITS_PER_M = 39.37,
    HEAD = 70,
    BODY_Z = 36, -- a hero tracked as a projectile is followed this far above his feet
    SCAN_EVERY = 0.25,
    CLEAR_DELAY = 0.5,
    TAIL_GRACE = 0.15, -- seconds a delayed effect's drawn tail keeps going past the moment it fires:
                       -- the scan only sees a modifier every 0.25 s, so a tail cut exactly at the
                       -- effect's duration can end up to that long early
    MERGE_DIST = 250, -- units; a warning this close to a projectile's predicted landing is that projectile's
    MAX_CP = 24,
    VEL_SAMPLE = 0.05, -- seconds between projectile position samples used to measure its velocity
    ARC_DT = 0.02, -- seconds between points of a predicted arc, so a path's length is its flight time
    GRAVITY_FALLBACK = 800,
    WALK_FRAMES = 24, -- frames the walk over every entity on the map is spread over (1: all at once)
    WALK_QUIET = 50,  -- looks in a row with nothing on it before a class is passed over by the walk
    WALK_PROBE = 20,  -- every this many rounds the walk looks at the passed-over classes too
    UNITS_KEEP = 0.25, --seconds the list of units on the map is kept; one that spawns is seen that late
    AB_KEEP = 1, --seconds a hero's ability, once looked up, is kept before it is searched for again
    TRACE = { with = 0x1C1003, exclude = 0, as = 0, object_set = 7, group = 4 },
    -- the items Evade may use, as the Evade Tools card lists them (your hero's own evade abilities
    -- to join them); `name` is the menu item, `ability` the item's ability name
    EVADE_ITEMS = {
        { name = "Counterspell", ability = "upgrade_counterspell",
          image = "panorama/images/items/vitality/counterspell_psd.vtex_c" }, -- m_strShopIconLarge
    },
    DEFAULTS = {
        sp_enable = true,
        sp_boxes = false,
        sp_points = false,
        sp_labels = false,
        sp_land = false,
        sp_arc = false,
        sp_debug = false,
        sp_size = 4,
        sp_dist = 120,
        sp_dodge = true,
        sp_guard = { "Lines", "Circles", "Cones" }, -- Block Movement: area shapes your keys may not walk you into
        sp_fog = false,      -- Visible Only: no spell from a caster never in sight during it
        sp_fov = 180,        -- Dodge Arc: degrees around where you look a caster must be in (360: all)
        sp_collide = false,  -- Unit Collision: a shot's lane ends at the first unit it would stop on
        sp_turrets = { "Guardians", "Walkers", "Patron" }, -- Avoid Turrets: enemy turrets dodges keep out of
        sp_turret_scale = 100, -- Turret Range Scale: % of each enemy turret's own range a dodge keeps out of
        sp_hero_dist = 6,    -- Hero Distance: m from enemy heroes a dodge prefers to end (0: off)
        sp_hazard_rule = 0,  -- Hazard Rule: 0 Prefer (a hazard over a hit), 1 Strict (never into one)
        sp_dodge_debug = false,
        sp_sim = false,
        sp_sim_gap = 1.5,
        sp_sim_cd = false,   -- Simulator: a simulated block puts Counterspell down for its cooldown
        sp_react = 0.15,     -- Tuning: seconds from deciding to the move taking hold
        sp_margin = 1.0,     -- Tuning: meters kept from an area's edge
        sp_parry_lead = 0.25, -- Tuning: seconds before the hit the Counterspell parry is tapped
        sp_dodge_gap = 0.25, -- Tuning: seconds after a dodge ends before Evade starts another
        sp_replan = 0.15,    -- Tuning: seconds between Evade's searches for the way out while you dodge
    },
}

U.OWNER_FIELDS = { "m_hOwnerEntity", "m_hOwner", "m_hCaster", "m_hAbilityOwner", "m_hOwnerPawn", "m_nOwner" }
U.SLOTS = {
    EAbilitySlots_t and EAbilitySlots_t.ESlot_Signature_1 or 0,
    EAbilitySlots_t and EAbilitySlots_t.ESlot_Signature_2 or 1,
    EAbilitySlots_t and EAbilitySlots_t.ESlot_Signature_3 or 2,
    EAbilitySlots_t and EAbilitySlots_t.ESlot_Signature_4 or 3,
}

-- mutable runtime state shared by every module
U.state = {
    now = 0,
    prev_now = 0,
    me = nil,
    list = {},      -- groups to draw this frame
    events = {},    -- particles seen through the particle callbacks, by index
    groups = {},    -- last scan's groups, kept for CLEAR_DELAY
    holders = {},   -- pawns that have each spell, refreshed every scan
    near = {},      -- pawn handle -> whether the last scan had it in range
    pawn_ids = {},  -- pawn handle -> its hero id, once read; dropped every scan
    next_scan = 0,
    shot_n = 0,     -- counter for bullet-fired shot group keys
    rt = 0,         -- seconds of frame time; curtime only advances per tick, too coarse to time samples
    last_log = 0,
    zones = {},     -- danger areas drawn this frame, for the dodge (draw.lua fills it)
    dodge = nil,    -- the dodge's current search: cells looked at, safe spot and path
    sims = {},      -- the Spell Simulator's spells in the air
    parry = nil,    -- the dodge's last Counterspell parry, { from, to, cooldown } in S.now, for the simulator
    counter_until = nil, -- Counterspell held down by the simulator after a simulated block, until this S.now
    targeted = {},  -- spell id -> S.now its `target_particles` tell was last seen: it is aimed at you
}

local fmt, sqrt = string.format, math.sqrt
U.fmt = fmt
-- Profile's clock, in seconds; U.state.prof_add(name, seconds) is set while Profile is on
U.clock = chronos and chronos.nanotime or os and os.clock

function U.log(f, ...) print(fmt("[%s %.2f] ", U.SCRIPT, U.state.now) .. fmt(f, ...)) end

local function call(obj, method, ...) return obj[method](obj, ...) end
local function index(obj, name) return obj[name] end
U.call = call

function U.try(obj, method, ...)
    if obj == nil then return nil end
    local ok, v = pcall(call, obj, method, ...)
    if ok then return v end
    return nil
end

function U.field(obj, name)
    if obj == nil then return nil end
    local ok, v = pcall(index, obj, name)
    if ok then return v end
    return nil
end

-- a world trace with the shared mask; `ignore` (an entity) is left out of it, every unit too with `world`
local function hit_none() return false end
local function hit_all() return true end
function U.trace_line(a, b, ignore, world)
    local T = U.CFG.TRACE
    -- the filter runs for each unit a trace meets: the handle to leave out is read once, and with
    -- none to leave out no handle is read at all (the dodge's search traces a thousand times a plan)
    local filter = world and hit_none or hit_all
    if ignore and not world then
        local skip = U.handle(ignore)
        filter = function(ent) return U.handle(ent) ~= skip end
    end
    return trace.line(a, b, T.with, T.exclude, T.as, T.object_set, T.group, filter)
end

function U.valid(e) return e ~= nil and U.try(e, "valid") == true end
function U.handle(e) return e and U.try(e, "get_handle") end

-- Whether `hero` can be seen, all three agreeing: the game calls him visible (player_pawn:is_visible,
-- when it answers), he is still sent (not dormant: out of your team's sight it stops), and no wall
-- stands between your eyes and his chest or head. The game's flag can say visible with a wall
-- between you two (behind one in a test, 2026-11-10). Asked once a frame per hero; with `debug`, each
-- change of the three is logged side by side, to learn which matches what you see.
-- shortcut: a mirror of fog hides him from your eyes alone: behind one he stayed visible to the game,
-- not dormant or obscured, no modifier on him, and nothing on any of 64 collision layers in the way
-- (2026-11-10), and the game's own cone search said "blocked" in plain view too. Spells cast from
-- behind one are drawn
local sight, sight_logged = {}, {}

-- the wall trace alone: true when your eyes reach his chest or head past the world
local function clear_line(me, hero, h)
    local a, b = me and U.try(me, "get_origin"), U.try(hero, "get_origin")
    if not (a and b) then return nil end
    local eye = Vector(a.x, a.y, a.z + U.CFG.HEAD)
    local T = U.CFG.TRACE
    for _, z in ipairs({ U.CFG.BODY_Z, U.CFG.HEAD }) do
        -- the world, and of everything else him alone: a trooper in the way doesn't hide him
        local tr = trace.line(eye, Vector(b.x, b.y, b.z + z), T.with, T.exclude, T.as, T.object_set, T.group,
            function(ent) return U.handle(ent) == h end)
        local f = tr and U.field(tr, "fraction")
        local hit = tr and U.try(tr, "hit_entity")
        if type(f) ~= "number" or f >= 1 or hit and U.handle(hit) == h then return true end
    end
    return false
end

function U.in_sight(hero, debug)
    local me, now = U.state.me, U.state.now
    local h = U.handle(hero)
    local c = h and sight[h]
    if c and c.t == now then return c.seen end
    local vis, dormant = U.try(hero, "is_visible"), U.try(hero, "is_dormant") == true
    local line -- nil: not traced (dormant: he isn't where he reads)
    if not dormant then line = clear_line(me, hero, h) end
    local seen = vis ~= false and not dormant and line ~= false
    if h then sight[h] = { t = now, seen = seen } end
    if debug and h then
        local key = ("%s/%s/%s"):format(tostring(vis), tostring(dormant), tostring(line))
        if sight_logged[h] ~= key then
            sight_logged[h] = key
            local okid, id = pcall(HERO_LIB.get_hero_id, hero)
            U.log("visible only: hero %s %s (is_visible %s, dormant %s, wall trace %s)",
                okid and tostring(id) or "?", seen and "seen" or "hidden", tostring(vis), tostring(dormant),
                line == nil and "n/a" or line and "clear" or "blocked")
        end
    end
    return seen
end

function U.dist_to_me(o)
    local me = U.state.me
    local m = me and U.try(me, "get_origin")
    if not m or not o then return nil end
    local dx, dy, dz = o.x - m.x, o.y - m.y, o.z - m.z
    return sqrt(dx * dx + dy * dy + dz * dz)
end

-- the pawn's ability whose name contains `key`, searched by slot so `key` can be a substring
local find_ability
-- Kept a second per hero and key, found or not: the search is 8 protected calls or more, and the
-- drawing and the cast poll each asked several times per spell, every frame
-- shortcut: an ability or item a hero gains or loses is seen up to AB_KEEP late; lower it if a
-- just-bought Counterspell must count at once
-- Its place is kept (the slot, or its index in the full list), never the ability itself: read anew
-- each call and checked by name. The ability kept past its frame stopped answering as one in a
-- match, and HERO_LIB failed on it every frame: no scan finished from then on (2026-11-11)
local ab_cache = {} -- hero handle -> key -> { t, slot or idx; neither: not found }
function U.find_ability(e, key)
    local h, now = U.handle(e), U.state.now
    if not h then return (find_ability(e, key)) end
    local per = ab_cache[h]
    if not per then per = {} ab_cache[h] = per end
    local c = per[key]
    -- abs: curtime restarts on each map
    if c and math.abs(now - c.t) < U.CFG.AB_KEEP then
        if not (c.slot or c.idx) then return nil end
        local ab
        if c.slot then
            ab = U.try(e, "get_ability_by_slot", c.slot)
        else
            local all = U.try(e, "get_abilities")
            ab = type(all) == "table" and all[c.idx] or nil
        end
        local name = ab and U.try(ab, "get_name")
        if name and name:find(key, 1, true) then return ab end
    end
    local ab, slot, idx = find_ability(e, key)
    per[key] = { t = now, slot = slot, idx = idx }
    return ab
end

-- the ability, and where it was found: its slot, or its index in the full list
function find_ability(e, key)
    for _, slot in ipairs(U.SLOTS) do
        local ab = U.try(e, "get_ability_by_slot", slot)
        local name = ab and U.try(ab, "get_name")
        if name and name:find(key, 1, true) then return ab, slot end
    end
    -- an enemy's slots can read empty; his full list may still hold it, upgrades and all
    local all = U.try(e, "get_abilities")
    for i, ab in ipairs(type(all) == "table" and all or {}) do
        local name = U.try(ab, "get_name")
        if name and name:find(key, 1, true) then return ab, nil, i end
    end
    return nil
end

-- a spell's ability property in world units, or default_m meters; values under 50 are taken as meters
-- a spell's ability property as a plain number, or nil when missing (a misspelled one reads as 0)
function U.ability_number(owner, spell, prop)
    local ab = prop and spell.ability and U.find_ability(owner, spell.ability)
    local v = ab and tonumber(U.try(ab, "get_scaled_property", prop))
    if v and v <= 0 then return nil end
    return v
end

function U.ability_value(owner, spell, prop, default_m)
    local v = U.ability_number(owner, spell, prop)
    if v and v < 50 then v = v * U.CFG.UNITS_PER_M end
    return v or default_m * U.CFG.UNITS_PER_M
end

-- How far a line spell's lane reaches, in units: its `range`; for a stab he dashes into (`lunge`),
-- from where that dash ends, and on to the stab's round tip, a `width` past its range
function U.line_range(owner, spell)
    local r = U.ability_value(owner, spell, spell.range_prop, spell.range or 30)
    if not spell.lunge then return r end
    return r + U.ability_value(owner, spell, spell.lunge_prop, spell.lunge) + (spell.width or 0) * U.CFG.UNITS_PER_M
end

-- Unit vector where a hero aims, and what it was read from. Your own hero aims with the camera:
-- his eye angles on the client lag it and drew Celeste's fan up to 60+ deg off her crosshair.
-- Others use their eye angles, which carry up and down too; get_angles is the body, which only
-- turns left and right and trails the aim, so it is the flattened last resort.
function U.aim_dir(e)
    local me = U.state.me
    local a, src
    if me and utils and U.handle(e) == U.handle(me) then
        local ok, cam = pcall(utils.get_camera_angles)
        if ok and cam then a, src = cam, "camera" end
    end
    if not a then a, src = U.field(e, "m_angEyeAngles"), "eye angles" end
    local pitch = a and tonumber(U.field(a, "pitch") or U.field(a, "x"))
    local yaw = a and tonumber(U.field(a, "yaw") or U.field(a, "y"))
    if pitch and yaw then
        local pr, yr = math.rad(pitch), math.rad(yaw)
        -- Source angles: positive pitch looks down
        return Vector(math.cos(pr) * math.cos(yr), math.cos(pr) * math.sin(yr), -math.sin(pr)), src
    end
    local ang = U.try(e, "get_angles")
    local f = ang and U.try(ang, "GetForward")
    local len = f and math.sqrt(f.x * f.x + f.y * f.y)
    if not len or len < 0.01 then return nil end
    return Vector(f.x / len, f.y / len, 0), "body facing (no up/down)"
end

-- The units on the map, sorted once a frame by class: the player pawn a "hero", the three turrets
-- by tier ("guardian", "walker", "patron"), any other "Trooper" class a "trooper" (a "neutral" when
-- it says so); `mine` on your team. Debug Mode logs each class it sorts once.
-- shortcut: which turret class is which tier is a guess from their names (no Boss_Tier1 is seen, so
-- the trooper boss is taken for the guardian); the class log confirms it walking past each
local TURRETS = { C_NPC_TrooperBoss = "guardian", C_NPC_Boss_Tier2 = "walker", C_NPC_Boss_Tier3 = "patron" }
local unit_list, unit_t, kinds_logged = {}, nil, {}
local UNITS_CHECK, units_checked = 5, -math.huge
local UNIT_CLASSES = { "C_CitadelPlayerPawn", "C_NPC_Trooper", "C_NPC_TrooperNeutral", "C_NPC_TrooperBoss",
    "C_NPC_Boss_Tier2", "C_NPC_Boss_Tier3" } -- every unit class the log has shown (2026-11-11)
local function unit_kind(cls)
    if cls == "C_CitadelPlayerPawn" then return "hero" end
    if TURRETS[cls] then return TURRETS[cls] end
    if cls:find("Trooper", 1, true) then return cls:find("Neutral", 1, true) and "neutral" or "trooper" end
end
function U.units(debug)
    local me, now = U.state.me, U.state.now
    -- kept UNITS_KEEP: listing them walks every entity on the map, and Unit Collision asks each frame
    if unit_t ~= now and (not unit_t or math.abs(now - unit_t) >= U.CFG.UNITS_KEEP) then
        unit_t, unit_list = now, {}
        local prof, t0 = U.state.prof_add, U.clock and U.clock()
        local all, of_kind, seen = entity_list.get_all() or {}, 0, {} -- seen: units per class, for the check
        for _, e in ipairs(all) do
            local cls = U.valid(e) and U.try(e, "get_class_name")
            local kind = type(cls) == "string" and unit_kind(cls)
            if kind then of_kind, seen[cls] = of_kind + 1, (seen[cls] or 0) + 1 end
            if kind and U.try(e, "is_alive") ~= false and U.try(e, "is_dormant") ~= true then
                unit_list[#unit_list + 1] = { e = e, kind = kind, h = U.handle(e), -- read once, not per asker
                    mine = me and HERO_LIB.is_same_team(me, e) == true }
                if debug and not kinds_logged[cls] then
                    kinds_logged[cls] = true
                    U.log("units: class %s taken for a %s", cls, kind)
                end
            end
        end
        -- Profile: what the walk costs, and every UNITS_CHECK s whether asking by class would find the
        -- same units (it then needs no walk)
        if prof and t0 then
            local dt = U.clock() - t0
            prof("units", dt)
            if math.abs(now - units_checked) >= UNITS_CHECK then
                units_checked = now
                -- each class where the two differ, as "class walk/by_class_name"; one the list lacks has no second
                local by, off = 0, {}
                for _, cls in ipairs(UNIT_CLASSES) do
                    local ok, l = pcall(entity_list.by_class_name, cls)
                    local n = ok and type(l) == "table" and #l
                    by = by + (n or 0)
                    if n ~= (seen[cls] or 0) then off[#off + 1] = ("%s %d/%s"):format(cls, seen[cls] or 0, n or "failed") end
                    seen[cls] = nil
                end
                for cls, n in pairs(seen) do off[#off + 1] = ("%s %d/not listed"):format(cls, n) end
                U.log("profile: units walk read %d entities in %.2f ms, %d of them units; by_class_name gives %d%s",
                    #all, dt * 1000, of_kind, by, #off > 0 and (", differing: " .. table.concat(off, ", ")) or "")
            end
        end
    end
    return unit_list
end

-- Unit Collision: the units that would stop a shot of `caster`'s with `blocked_by` (its entry's
-- list), as seen from you: "hero" any but him and you, "trooper" yours, "neutral" the neutral creeps
function U.blockers(caster, blocked_by, debug)
    local me = U.state.me
    local want, out = {}, {}
    for _, k in ipairs(blocked_by or {}) do want[k] = true end
    local me_h, caster_h = U.handle(me), U.handle(caster)
    for _, u in ipairs(U.units(debug)) do
        if u.h ~= me_h and u.h ~= caster_h then
            if want[u.kind] and (u.kind ~= "trooper" or u.mine) then
                out[#out + 1] = u
            end
        end
    end
    return out
end

-- Whether `e` stands within `fov` degrees (all of it, centred) of where your camera faces, on the
-- flat: true when that can't be told
function U.in_view(e, fov)
    local me = U.state.me
    local a, b = me and U.try(me, "get_origin"), U.try(e, "get_origin")
    local f = me and U.aim_dir(me)
    if not (a and b and f) then return true end
    local dx, dy = b.x - a.x, b.y - a.y
    if dx * dx + dy * dy < 1 or f.x * f.x + f.y * f.y < 1e-4 then return true end
    local off = math.abs((math.atan(dy, dx) - math.atan(f.y, f.x) + math.pi) % (2 * math.pi) - math.pi)
    return math.deg(off) <= fov / 2
end

-- `p` this many meters further along the way `path` was going (a landing area that vdata measures
-- from the move's own reach), keeping p's height
function U.ahead(p, path, meters)
    if not meters or meters == 0 or not path or #path < 2 then return p end
    local a, b = path[#path - 1], path[#path]
    local dx, dy = b.x - a.x, b.y - a.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return p end
    local k = meters * U.CFG.UNITS_PER_M / len
    return Vector(p.x + dx * k, p.y + dy * k, p.z)
end

function U.short_name(s)
    s = tostring(s or "?")
    s = s:gsub("^particles/", ""):gsub("%.vpcf$", "")
    if #s > 34 then s = s:sub(#s - 33) end
    return s
end

return U
