-- Spell Drawer | spell simulator: casts the enabled spells of the registry at you, one at a time,
-- from a random spot and angle around you. Each one is a stand-in group the real drawing code draws,
-- so it becomes a danger zone like a real spell and Auto Dodge takes over; each is scored dodged or hit.
-- shortcut: casters stand on your floor and spells pass through walls; trace them to make it exact

local U = require("spelldrawer_util")
local SPELLS = require("spelldrawer_spells")
local ui = require("spelldrawer_menu").ui

local CFG, S = U.CFG, U.state
local UPM = CFG.UNITS_PER_M
local cos, sin, sqrt, abs, atan, pi = math.cos, math.sin, math.sqrt, math.abs, math.atan, math.pi

local SIM = {}

local GAP = 1.5         -- seconds from one spell ending to the next cast
local NEAR, FAR = 8, 18 -- meters from you a ranged spell is cast from
local MISS = 1.5        -- meters a spell may be aimed off you, each way
local HERO_R = 20       -- units: your half-width, for whether a spell hit you
local ARC_TIME = 1.0    -- seconds a lob is in the air, for one without a `duration`
local ARC_HEIGHT = 3    -- meters a lob rises above the straight line (not a straight dive)
local LINE_SPEED = 1500 -- units/s, for a line without a `speed` (a dash)
local CONE_TIME = 0.6   -- seconds a cone is up, for one without a `cone_time`
local AURA_TIME = 1.5   -- seconds an aura is up, for one without a `duration`

local score, next_at = { dodged = 0, hit = 0 }, 0

-- a stand-in caster for the drawing code: valid, standing at `pos`, aiming flat at `yaw` (radians)
local function caster(pos, yaw)
    return { valid = function() return true end, get_handle = function() return -1 end,
             get_origin = function() return pos end, m_angEyeAngles = { pitch = 0, yaw = math.deg(yaw) } }
end

local function lerp(a, b, u) return Vector(a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u, a.z + (b.z - a.z) * u) end

-- flat distance from `o` to the segment a-b
local function seg_dist(o, a, b)
    local ex, ey = b.x - a.x, b.y - a.y
    local t = math.max(0, math.min(1, ((o.x - a.x) * ex + (o.y - a.y) * ey) / math.max(1, ex * ex + ey * ey)))
    return sqrt((o.x - a.x - ex * t) ^ 2 + (o.y - a.y - ey * t) ^ 2)
end

-- `spell` cast at you standing at `o`: a group shaped like the one detection builds for it, plus
-- what the simulator needs to move and score it (from, T, reach)
function SIM.cast(o, spell)
    local m, a = spell.motion, math.random() * 2 * pi
    local function around(meters) return Vector(o.x + cos(a) * meters * UPM, o.y + sin(a) * meters * UPM, o.z) end
    local function off() return (math.random() * 2 - 1) * MISS * UPM end
    local aim = Vector(o.x + off(), o.y + off(), o.z)
    local rec = { spell = spell, sim = true, first = S.now, t0 = S.rt }
    if m == "cone" or m == "aura" then
        -- close enough that you are in it: a melee swing or a ring on the caster
        rec.reach = m == "cone" and U.ability_value(nil, spell, spell.range_prop, spell.range or 5)
            or U.ability_value(nil, spell, spell.radius_prop, spell.radius or 1.5)
        rec.from = around(rec.reach / UPM * (0.3 + 0.5 * math.random()))
        rec.yaw = atan(o.y - rec.from.y, o.x - rec.from.x)
        rec.caster, rec.cone_at = caster(rec.from, rec.yaw), S.now
        rec.T = m == "cone" and (spell.cone_time or CONE_TIME)
            or U.ability_number(nil, spell, spell.duration_prop) or spell.duration or AURA_TIME
        return rec
    end
    rec.from = around(NEAR + math.random() * (FAR - NEAR))
    if m == "arc" then
        rec.from = Vector(rec.from.x, rec.from.y, o.z + 2 * UPM)
        rec.land, rec.aim = aim, aim
        rec.reach = U.ability_value(nil, spell, spell.radius_prop, spell.radius or 7)
        rec.T = U.ability_number(nil, spell, spell.duration_prop) or spell.duration or ARC_TIME
        return rec
    end
    -- line: from the caster through where it aimed, for the spell's range, at chest height
    local dx, dy = aim.x - rec.from.x, aim.y - rec.from.y
    local len, range, z = sqrt(dx * dx + dy * dy), U.ability_value(nil, spell, spell.range_prop, spell.range or 30), o.z + CFG.BODY_Z
    rec.path = { Vector(rec.from.x, rec.from.y, z), Vector(rec.from.x + dx / len * range, rec.from.y + dy / len * range, z) }
    rec.land = Vector(rec.path[2].x, rec.path[2].y, o.z) -- where a lane that ends in an area has it
    rec.reach = (spell.width or 0.75) * UPM
    rec.T = range / (spell.speed or LINE_SPEED)
    return rec
end

-- one frame of `rec` against you at `o`: moves it on, and once it has gone off says "hit" or "dodged"
local function step(rec, o)
    local spell, el = rec.spell, S.rt - rec.t0
    local m = spell.motion
    if m == "line" then
        local p = lerp(rec.path[1], rec.path[2], math.min(1, el / rec.T))
        -- swept since last frame, so a fast shot can't skip past you
        if seg_dist(o, rec.pos or rec.path[1], p) < rec.reach + HERO_R then return "hit" end
        rec.pos = p
        if el < rec.T then return nil end
        if not spell.radius_prop then return "dodged" end
        local at = U.ahead(rec.land, rec.path, spell.land_offset)
        local r = U.ability_value(nil, spell, spell.radius_prop, spell.radius or 7)
        return sqrt((o.x - at.x) ^ 2 + (o.y - at.y) ^ 2) < r + HERO_R and "hit" or "dodged"
    end
    if m == "arc" then
        if el >= rec.T then
            return sqrt((o.x - rec.land.x) ^ 2 + (o.y - rec.land.y) ^ 2) < rec.reach + HERO_R and "hit" or "dodged"
        end
        -- the rest of the flight, a point every ARC_DT as the drawing expects (its length is the time left)
        local h = spell.gravity_scale == 0 and 0 or ARC_HEIGHT * UPM
        rec.path = {}
        for t = el, rec.T + CFG.ARC_DT / 2, CFG.ARC_DT do
            local u = math.min(1, t / rec.T)
            local p = lerp(rec.from, rec.land, u)
            rec.path[#rec.path + 1] = Vector(p.x, p.y, p.z + 4 * h * u * (1 - u))
        end
        return nil
    end
    -- cone and aura: seen this frame, as the drawing hides a trigger that hasn't been seen lately
    rec.cone_seen, rec.mod_at = S.now, S.now
    if el < rec.T then return nil end
    local dx, dy = o.x - rec.from.x, o.y - rec.from.y
    local d = sqrt(dx * dx + dy * dy)
    if d >= rec.reach + HERO_R then return "dodged" end
    if m == "aura" or d < HERO_R then return "hit" end
    local half = math.rad((U.ability_number(nil, spell, spell.angle_prop) or spell.angle or 60) / 2)
    return abs((atan(dy, dx) - rec.yaw + pi) % (2 * pi) - pi) <= half + HERO_R / d and "hit" or "dodged"
end

-- on_frame: the spell in the air goes on; GAP after it is over, the next one is cast
function SIM.update()
    local o = ui.sp_sim:Get() and S.me and U.try(S.me, "get_origin")
    if not o then
        S.sim = nil
        return
    end
    local rec = S.sim
    if rec then
        local result = step(rec, o)
        if not result then return end
        score[result] = score[result] + 1
        U.log("sim: %s (%s) from %.1f m: %s. %d dodged, %d hit", rec.spell.name, rec.spell.motion,
            sqrt((rec.from.x - o.x) ^ 2 + (rec.from.y - o.y) ^ 2) / UPM, result, score.dodged, score.hit)
        S.sim, next_at = nil, S.rt + GAP
        return
    end
    if S.rt < next_at then return end
    local on = {}
    for _, s in ipairs(SPELLS) do
        if s.motion and s.ui and s.ui:Get(s.name) then on[#on + 1] = s end
    end
    if #on == 0 then
        next_at = S.rt + 5
        U.log("sim: no spell enabled to cast; turn some on in the hero rows")
        return
    end
    S.sim = SIM.cast(o, on[math.random(#on)])
end

SIM.score = score
return SIM
