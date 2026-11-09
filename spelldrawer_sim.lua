-- Spell Drawer | spell simulator: casts the enabled spells of the registry at you, one at a time,
-- from a random spot and angle around you. Each one is a stand-in group the real drawing code draws,
-- so it becomes a danger zone like a real spell and Auto Dodge takes over; each is scored dodged or hit.
-- A shot with a `windup` aims for that long before it flies, as in the game.
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

local score, next_at = { dodged = 0, hit = 0, countered = 0 }, 0

-- a stand-in caster for the drawing code: valid, standing where `rec` has it now (`cur`, else
-- `from`: a dash moves it), aiming flat at `yaw` (radians)
local function caster(rec, yaw)
    return { valid = function() return true end, get_handle = function() return -1 end,
             get_origin = function() return rec.cur or rec.from end, m_angEyeAngles = { pitch = 0, yaw = math.deg(yaw) } }
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
local function shape(o, spell)
    local m, a = spell.motion, math.random() * 2 * pi
    local function around(meters) return Vector(o.x + cos(a) * meters * UPM, o.y + sin(a) * meters * UPM, o.z) end
    local function off() return (math.random() * 2 - 1) * MISS * UPM end
    local aim = Vector(o.x + off(), o.y + off(), o.z)
    local rec = { spell = spell, sim = true, first = S.now, t0 = S.rt }
    if m == "aura" and (spell.dash_range or spell.dash_range_prop) then
        -- a dash at you (Leaping Slash): she winds up, dashes at where she aimed (you, up to MISS
        -- off), stopping short at her range, and slashes a ring `land_offset` past where she stops.
        -- Cast from up to past her range, so some fall short
        local range = U.ability_value(nil, spell, spell.dash_range_prop, spell.dash_range)
        rec.reach = U.ability_value(nil, spell, spell.radius_prop, spell.radius or 1.5)
        rec.from = around(range / UPM * (0.5 + 0.7 * math.random()))
        local dx, dy = aim.x - rec.from.x, aim.y - rec.from.y
        local len = sqrt(dx * dx + dy * dy)
        local go, past = math.min(len, range), (spell.land_offset or 0) * UPM
        rec.dash_to = Vector(rec.from.x + dx / len * go, rec.from.y + dy / len * go, o.z)
        rec.slash = Vector(rec.dash_to.x + dx / len * past, rec.dash_to.y + dy / len * past, o.z)
        rec.yaw, rec.windup = atan(dy, dx), spell.windup or 0
        rec.T = rec.windup + go / (spell.dash_speed or LINE_SPEED)
        rec.caster = caster(rec, rec.yaw)
        return rec
    end
    if m == "cone" or m == "aura" then
        -- close enough that you are in it: a melee swing or a ring on the caster
        rec.reach = m == "cone" and U.ability_value(nil, spell, spell.range_prop, spell.range or 5)
            or U.ability_value(nil, spell, spell.radius_prop, spell.radius or 1.5)
        rec.from = around(rec.reach / UPM * (0.3 + 0.5 * math.random()))
        rec.yaw = atan(o.y - rec.from.y, o.x - rec.from.x)
        rec.caster, rec.cone_at = caster(rec, rec.yaw), S.now
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
    rec.reach, rec.speed = (spell.width or 0.75) * UPM, spell.speed or LINE_SPEED
    rec.windup = spell.windup or 0
    rec.T = rec.windup + range / rec.speed
    return rec
end

-- one frame of `rec` against you at `o`: moves it on, and once it has gone off says "hit" or "dodged"
local function step(rec, o)
    local spell, el = rec.spell, S.rt - rec.t0
    local m = spell.motion
    if m == "line" then
        -- a wind-up first: the caster aims and the lane is drawn from him, as detection's wind-up
        -- group is (`mod`, the shot leaving at `fires_at`); then the shot flies
        local fly = el - rec.windup
        if fly < 0 then
            rec.mod, rec.pos, rec.fires_at = true, rec.path[1], rec.first + rec.windup
            return nil
        end
        rec.mod, rec.fires_at = nil, nil
        local p = lerp(rec.path[1], rec.path[2], math.min(1, fly / (rec.T - rec.windup)))
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
    if rec.dash_to then
        -- the wind-up (its end is when she leaves), then the dash; the slash only where it ends
        local fly = el - rec.windup
        rec.fires_at = fly < 0 and rec.first + rec.windup or nil
        if fly >= 0 then rec.cur = lerp(rec.from, rec.dash_to, math.min(1, fly / math.max(1e-3, rec.T - rec.windup))) end
        if el < rec.T then return nil end
        return sqrt((o.x - rec.slash.x) ^ 2 + (o.y - rec.slash.y) ^ 2) < rec.reach + HERO_R and "hit" or "dodged"
    end
    if el < rec.T then return nil end
    local dx, dy = o.x - rec.from.x, o.y - rec.from.y
    local d = sqrt(dx * dx + dy * dy)
    if d >= rec.reach + HERO_R then return "dodged" end
    if m == "aura" or d < HERO_R then return "hit" end
    local half = math.rad((U.ability_number(nil, spell, spell.angle_prop) or spell.angle or 60) / 2)
    return abs((atan(dy, dx) - rec.yaw + pi) % (2 * pi) - pi) <= half + HERO_R / d and "hit" or "dodged"
end

-- `spell` cast at you standing at `o`, run for its first frame so the frame it is cast already draws
-- whole: drawn unstepped, a shot's wind-up had no delay yet, the dodge planned on the bare flight and
-- dashed where walking would have done
function SIM.cast(o, spell)
    local rec = shape(o, spell)
    step(rec, o)
    return rec
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
        -- a Counterspell parry the dodge tapped for this spell, open as it lands, blocks it
        local pw = S.parry
        if result == "hit" and pw and pw.from >= rec.first and S.now <= pw.to then
            -- the game only puts the item down on a real hit, so the block's cooldown is held here
            result, S.counter_until = "countered", S.now + (pw.cooldown or 0)
        end
        score[result] = score[result] + 1
        U.log("sim: %s (%s) from %.1f m: %s. %d dodged, %d countered, %d hit", rec.spell.name, rec.spell.motion,
            sqrt((rec.from.x - o.x) ^ 2 + (rec.from.y - o.y) ^ 2) / UPM, result, score.dodged, score.countered, score.hit)
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
