-- Spell Drawer | shared config, runtime state and safe-access helpers

local U = {}

U.SCRIPT = "Spell Drawer"

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
    TRACE = { with = 0x1C1003, exclude = 0, as = 0, object_set = 7, group = 4 },
    DEFAULTS = {
        sp_enable = true,
        sp_boxes = true,
        sp_points = true,
        sp_labels = false,
        sp_land = true,
        sp_arc = true,
        sp_debug = false,
        sp_size = 4,
        sp_dist = 120,
        sp_dodge = false,
        sp_dodge_debug = true,
        sp_sim = false,
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
    next_scan = 0,
    shot_n = 0,     -- counter for bullet-fired shot group keys
    rt = 0,         -- seconds of frame time; curtime only advances per tick, too coarse to time samples
    last_log = 0,
    zones = {},     -- danger areas drawn this frame, for the dodge (draw.lua fills it)
    dodge = nil,    -- the dodge's current search: cells looked at, safe spot and path
    sim = nil,      -- the Spell Simulator's spell in the air
    parry = nil,    -- the dodge's last Counterspell parry, { from, to, cooldown } in S.now, for the simulator
    counter_until = nil, -- Counterspell held down by the simulator after a simulated block, until this S.now
}

local fmt, sqrt = string.format, math.sqrt
U.fmt = fmt

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

-- a world trace with the shared mask; `ignore` (an entity) is left out of it
function U.trace_line(a, b, ignore)
    local T = U.CFG.TRACE
    return trace.line(a, b, T.with, T.exclude, T.as, T.object_set, T.group, function(ent)
        return U.handle(ent) ~= U.handle(ignore)
    end)
end

function U.valid(e) return e ~= nil and U.try(e, "valid") == true end
function U.handle(e) return e and U.try(e, "get_handle") end

function U.dist_to_me(o)
    local me = U.state.me
    local m = me and U.try(me, "get_origin")
    if not m or not o then return nil end
    local dx, dy, dz = o.x - m.x, o.y - m.y, o.z - m.z
    return sqrt(dx * dx + dy * dy + dz * dz)
end

-- the pawn's ability whose name contains `key`, searched by slot so `key` can be a substring
function U.find_ability(e, key)
    for _, slot in ipairs(U.SLOTS) do
        local ab = U.try(e, "get_ability_by_slot", slot)
        local name = ab and U.try(ab, "get_name")
        if name and name:find(key, 1, true) then return ab end
    end
    -- an enemy's slots can read empty; his full list may still hold it, upgrades and all
    local all = U.try(e, "get_abilities")
    for _, ab in ipairs(type(all) == "table" and all or {}) do
        local name = U.try(ab, "get_name")
        if name and name:find(key, 1, true) then return ab end
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
