-- Spell Drawer | shared config, runtime state and safe-access helpers

local U = {}

U.SCRIPT = "Spell Drawer"

U.CFG = {
    UNITS_PER_M = 39.37,
    HEAD = 70,
    SCAN_EVERY = 0.25,
    CLEAR_DELAY = 0.5,
    MERGE_DIST = 250, -- units; a warning this close to a projectile's predicted landing is that projectile's
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
        sp_debug = false,
        sp_size = 4,
        sp_dist = 120,
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
    casters = {},
    cooldowns = {},
    next_scan = 0,
    last_log = 0,
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

function U.valid(e) return e ~= nil and U.try(e, "valid") == true end
function U.handle(e) return e and U.try(e, "get_handle") end

function U.dist_to_me(o)
    local me = U.state.me
    local m = me and U.try(me, "get_origin")
    if not m or not o then return nil end
    local dx, dy, dz = o.x - m.x, o.y - m.y, o.z - m.z
    return sqrt(dx * dx + dy * dy + dz * dz)
end

function U.short_name(s)
    s = tostring(s or "?")
    s = s:gsub("^particles/", ""):gsub("%.vpcf$", "")
    if #s > 34 then s = s:sub(#s - 33) end
    return s
end

return U
