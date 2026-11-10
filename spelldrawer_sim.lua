-- Spell Drawer | spell simulator: casts the enabled spells of the registry at you, one at a time,
-- `Interval` apart (Debug tab, Simulator card), from a random spot and angle around you. Each one is a stand-in group the real drawing code draws,
-- so it becomes a danger zone like a real spell and Evade takes over; each is scored dodged or hit.
-- A shot with a `windup` aims for that long before it flies, as in the game.
-- shortcut: casters stand on your floor and spells pass through walls; trace them to make it exact

local U = require("spelldrawer_util")
local SPELLS = require("spelldrawer_spells")
local ui = require("spelldrawer_menu").ui

local CFG, S = U.CFG, U.state
local UPM = CFG.UNITS_PER_M
local cos, sin, sqrt, abs, atan, pi = math.cos, math.sin, math.sqrt, math.abs, math.atan, math.pi

local SIM = {}

local NEAR, FAR = 8, 18 -- meters from you a ranged spell is cast from
local MISS = 1.5        -- meters a spell may be aimed off you, each way
local HERO_R = 20       -- units: your half-width, for whether a spell hit you
local ARC_TIME = 1.0    -- seconds a lob is in the air, for one without a `duration`
local ARC_HEIGHT = 3    -- meters a lob rises above the straight line (not a straight dive)
local LINE_SPEED = 1500 -- units/s, for a line without a `speed` (a dash)
local CONE_TIME = 0.6   -- seconds a cone is up, for one without a `cone_time`
local AURA_TIME = 1.5   -- seconds an aura is up, for one without a `duration`
local WALL_TIME = 1.1   -- seconds from a wall laid to its hands popping (Grasping Hands' GroundAuraPopDelay)
local WALL_LEN = 14     -- meters of it (ZombieWallLength)
local RISE, RISE_TIME = 6, 0.4  -- meters and seconds a diver rises before he hovers
local HOVER_MIN, HOVER_MAX = 0.3, 1.5 -- seconds a diver hovers, aiming, before he dives
local DIVE_SPEED = 1500 -- units/s, for a dive without a `dive_speed` (Chimera Mk1's isn't in vdata)

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
    if m == "target" then
        -- cast at you from inside its range, aimed straight at you: it lands `hit_delay` later plus
        -- the flight, wherever you go
        local range = U.ability_value(nil, spell, spell.range_prop, spell.range or 10)
        rec.from = around(range / UPM * (0.4 + 0.5 * math.random()))
        rec.yaw = atan(o.y - rec.from.y, o.x - rec.from.x)
        rec.caster = caster(rec, rec.yaw)
        local d = sqrt((o.x - rec.from.x) ^ 2 + (o.y - rec.from.y) ^ 2)
        rec.T = (spell.hit_delay or 0) + (spell.speed and d / spell.speed or 0)
        return rec
    end
    if m == "wall" then
        -- a line of hands laid across your way from its caster, you on it up to its width off its
        -- middle: it takes you if you are still on it as its hands pop, WALL_TIME on
        local len = WALL_LEN * UPM
        rec.from = around(NEAR + math.random() * (FAR - NEAR))
        local dx, dy = o.x - rec.from.x, o.y - rec.from.y
        local n = sqrt(dx * dx + dy * dy)
        local w = (spell.width or 0.75) * UPM
        local off = (math.random() * 2 - 1) * w
        local c = Vector(o.x + dx / n * off, o.y + dy / n * off, o.z)
        local ux, uy = -dy / n * len / 2, dx / n * len / 2
        rec.wall = { Vector(c.x - ux, c.y - uy, o.z), Vector(c.x + ux, c.y + uy, o.z) }
        -- its hands, 1 m apart, as the game lays them
        local cps, k = {}, math.floor(len / UPM)
        for i = 0, k do cps[#cps + 1] = { origin = lerp(rec.wall[1], rec.wall[2], i / k) } end
        rec.particles = { { name = "sim", control_points = cps } }
        rec.reach, rec.yaw = w, atan(dy, dx)
        rec.caster, rec.T = caster(rec, rec.yaw), WALL_TIME
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
    -- a wide lane (Itani Lo Sahn's 7 m) from at least 3 m past its own width: from 8 m it was on
    -- you the frame it was cast, before it was ever drawn
    local near = math.max(NEAR, (m == "line" and spell.width or 0) + 3)
    rec.from = around(near + math.random() * (FAR - NEAR))
    if m == "arc" and (spell.aim_land or spell.dive_min_speed) and spell.modifier then
        -- a dive (Seismic Impact, Chimera Mk1): he rises, hovers aiming at you, then dives along his
        -- aim at `dive_speed`; nothing is marked while he hovers, only as he dives, timed
        rec.land, rec.aim = aim, aim
        rec.reach = U.ability_value(nil, spell, spell.radius_prop, spell.radius or 7)
        rec.hover = Vector(rec.from.x, rec.from.y, o.z + RISE * UPM)
        rec.up = RISE_TIME + HOVER_MIN + math.random() * (HOVER_MAX - HOVER_MIN)
        local d = sqrt((aim.x - rec.hover.x) ^ 2 + (aim.y - rec.hover.y) ^ 2 + (aim.z - rec.hover.z) ^ 2)
        rec.T = rec.up + d / (spell.dive_speed or DIVE_SPEED)
        return rec
    end
    if m == "arc" then
        rec.from = Vector(rec.from.x, rec.from.y, o.z + 2 * UPM)
        rec.land, rec.aim = aim, aim
        rec.reach = U.ability_value(nil, spell, spell.radius_prop, spell.radius or 7)
        rec.T = U.ability_number(nil, spell, spell.duration_prop) or spell.duration or ARC_TIME
        -- a bomb that arms on landing (`arm`): it flies, lands, and blows that long after
        if spell.arm then rec.fly, rec.T = rec.T, rec.T + spell.arm end
        return rec
    end
    -- line: from the caster through where it aimed, for the spell's range, at chest height
    local dx, dy = aim.x - rec.from.x, aim.y - rec.from.y
    local len, range, z = sqrt(dx * dx + dy * dy), U.line_range(nil, spell), o.z + CFG.BODY_Z
    rec.path = { Vector(rec.from.x, rec.from.y, z), Vector(rec.from.x + dx / len * range, rec.from.y + dy / len * range, z) }
    rec.land = Vector(rec.path[2].x, rec.path[2].y, o.z) -- where a lane that ends in an area has it
    rec.reach, rec.speed = (spell.width or 0.75) * UPM, spell.speed or LINE_SPEED
    rec.windup = spell.windup or 0
    -- a held dash (`charge_max`): charged from when he can first let go to its most, untimed meanwhile
    if spell.charge_max then
        local lo = spell.release_from or spell.release or 0.25
        rec.windup, rec.charge = lo + math.random() * (spell.charge_max - lo), true
    end
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
            rec.mod, rec.pos, rec.charging = true, rec.path[1], rec.charge
            rec.fires_at = not rec.charge and rec.first + rec.windup or nil
            return nil
        end
        rec.mod, rec.fires_at, rec.charging = nil, nil, nil
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
            local d = sqrt((o.x - rec.land.x) ^ 2 + (o.y - rec.land.y) ^ 2) - HERO_R
            if d < rec.reach then return "hit" end
            -- its shockwave (`wave_radius`) rolls out to its edge over `wave_time`: a hit where it passes you
            local wave = spell.wave_radius and U.ability_value(nil, spell, spell.wave_radius_prop, spell.wave_radius)
            if not wave then return "dodged" end
            local u = (el - rec.T) / spell.wave_time
            if d < wave * math.min(1, u) then return "hit" end
            return u >= 1 and "dodged" or nil
        end
        if rec.hover then
            -- up and hovering: nothing yet; then the dive, straight along his aim
            if el < rec.up then
                rec.aim_spot, rec.path = nil, nil
                return nil
            end
            rec.aim_spot, rec.aim_at = rec.land, spell.dive_speed and rec.first + rec.T or nil
            rec.path = {}
            for t = el, rec.T + CFG.ARC_DT / 2, CFG.ARC_DT do
                rec.path[#rec.path + 1] = lerp(rec.hover, rec.land, math.min(1, (t - rec.up) / (rec.T - rec.up)))
            end
            return nil
        end
        -- landed and arming (`arm`): no flight left, its area lies where it landed
        local fly = rec.fly or rec.T
        if el >= fly then
            rec.path, rec.lands_at = nil, rec.first + fly
            return nil
        end
        -- the rest of the flight, a point every ARC_DT as the drawing expects (its length is the time left)
        local h = spell.gravity_scale == 0 and 0 or ARC_HEIGHT * UPM
        rec.path = {}
        for t = el, fly + CFG.ARC_DT / 2, CFG.ARC_DT do
            local u = math.min(1, t / fly)
            local p = lerp(rec.from, rec.land, u)
            rec.path[#rec.path + 1] = Vector(p.x, p.y, p.z + 4 * h * u * (1 - u))
        end
        return nil
    end
    -- cast at you: it hits, unless parried
    if m == "target" then return el >= rec.T and "hit" or nil end
    if m == "wall" then
        if el < rec.T then return nil end
        return seg_dist(o, rec.wall[1], rec.wall[2]) < rec.reach + HERO_R and "hit" or "dodged"
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

-- on_frame: the spells in the air go on (S.sims holds more than one, for when several are cast at
-- once); `Interval` after the last is over, the next is cast
function SIM.update()
    local o = ui.sp_sim:Get() and S.me and U.try(S.me, "get_origin")
    if not o then
        S.sims = {}
        return
    end
    if #S.sims > 0 then
        local left = {}
        for _, rec in ipairs(S.sims) do
            local result = step(rec, o)
            if not result then
                left[#left + 1] = rec
            else
                -- a Counterspell parry the dodge tapped for this spell, open as it lands, blocks it
                local pw = S.parry
                if result == "hit" and pw and pw.from >= rec.first and S.now <= pw.to then
                    result = "countered"
                    -- the game only puts the item down on a real hit, so with Item Cooldowns on the
                    -- block's cooldown is held here; off, every test spell meets a ready Counterspell
                    if ui.sp_sim_cd:Get() then S.counter_until = S.now + (pw.cooldown or 0) end
                end
                score[result] = score[result] + 1
                U.log("sim: %s (%s) from %.1f m: %s. %d dodged, %d countered, %d hit", rec.spell.name, rec.spell.motion,
                    sqrt((rec.from.x - o.x) ^ 2 + (rec.from.y - o.y) ^ 2) / UPM, result, score.dodged, score.countered, score.hit)
            end
        end
        S.sims = left
        if #left == 0 then next_at = S.rt + ui.sp_sim_gap:Get() end
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
    S.sims = { SIM.cast(o, on[math.random(#on)]) }
end

SIM.score = score
return SIM
