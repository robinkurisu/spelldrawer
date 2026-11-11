-- Spell Drawer | dodge: while you stand in a drawn danger area (S.zones, which draw.lua fills each
-- frame), searches a grid around you for the nearest spot outside every area that you can walk to.
-- If walking there leaves each area before it hits, it walks you; if only a dash gets you clear in
-- time, it dashes; failing that, with Counterspell, it parries the hit; if nothing works, it sends nothing

local U = require("spelldrawer_util")
local ui = require("spelldrawer_menu").ui

local CFG, S = U.CFG, U.state
local abs, atan, sqrt, pi = math.abs, math.atan, math.sqrt, math.pi

local E = {}

local CELL = 40        -- grid step, units (about a metre)
local REACH = 14       -- cells searched each way, so a safe spot at most ~14 m off
-- MARGIN, REACT and COUNTER_LEAD are the Tuning card's (Evade tab), read once a frame by E.update
local MARGIN = CFG.DEFAULTS.sp_margin * CFG.UNITS_PER_M -- units kept from an area's edge: your half-width and some slack
local HEIGHT = 150     -- an area further than this above or below your feet is on another floor
local DANGER_COST = 5  -- a step into an area costs this many safe steps: the path leaves danger the quickest way
local STEP_UP = 30     -- tallest step walked up; taller is a wall
local DROP = 120       -- deepest step walked down; deeper is a ledge the search won't take
local KNEE = 40        -- wall traces run this far above the floor, over steps and curbs
local REPLAN = CFG.DEFAULTS.sp_replan -- seconds between searches while dodging, as the areas move (Path Refresh)
local ARRIVE = 20      -- units from a path point that count as having reached it
local REACT = CFG.DEFAULTS.sp_react -- seconds from deciding to the move taking hold: a tick or two of input
local MIN_REACT = 0.1 -- Reaction Time's floor (its slider's minimum)
local DODGE_GAP = CFG.DEFAULTS.sp_dodge_gap -- seconds after a dodge ends before another starts (Dodge Interval)
local dodge_ended = -math.huge -- S.now the last dodge ended
local WALK_SPEED = 7   -- m/s, when your hero's EMaxMoveSpeed doesn't read
local DASH_DIST, DASH_TIME = 5, 0.25 -- meters and seconds of a ground dash, when its stats don't read
local AIR_DASH_DIST, AIR_DASH_TIME = 8, 0.47 -- an air dash's, hero_base EAirDashDistanceInMeters / EAirDashDuration

local IN = InputBitMask_t or { IN_FORWARD = 8, IN_BACK = 16, IN_MOVELEFT = 512, IN_MOVERIGHT = 1024,
                               IN_INNATE_1 = 17592186044416, IN_ABILITY_HELD = 4398046511104, IN_ATTACK = 1,
                               IN_ATTACK2 = 2048, IN_RELOAD = 8192, IN_ABILITY1 = 8589934592,
                               IN_ABILITY2 = 17179869184, IN_ABILITY3 = 34359738368, IN_ABILITY4 = 68719476736 }
-- Deadlock's dash: Shift sends IN_INNATE_1 (seen in game with Debug Mode, which names every key you
-- press yourself), not IN_SPEED
local DASH_KEY = IN.IN_INNATE_1
-- the parry (F), the bit Better parry sends; Debug Mode names your own press of it to check. A
-- parry won't go while attacking, reloading or casting, so those are let go for it
local PARRY_KEY = IN.IN_ABILITY_HELD
local PARRY_CONFLICT = IN.IN_ATTACK | IN.IN_ATTACK2 | IN.IN_RELOAD | IN.IN_ABILITY1 | IN.IN_ABILITY2
    | IN.IN_ABILITY3 | IN.IN_ABILITY4
local COUNTER_LEAD = CFG.DEFAULTS.sp_parry_lead -- seconds before the hit the parry is tapped: inside its window
local PARRY_LAG = 0.05     -- seconds from the parry tap to its modifier on you (0.03-0.05 s in game)
local COUNTER_WINDOW = 0.8 -- seconds a Counterspell parry blocks (vdata SpellParryDuration), if the item doesn't say
local COUNTER_COOLDOWN = 23 -- seconds Counterspell is down after a block (vdata AbilityCooldown), if the item doesn't say

-- S.zones split once a frame by E.update: the drawn areas, and apart from them the spells cast at
-- you ("target"). No spot is out of those, so the search, the dash and the guard leave them be
local zones, targets = {}, {}

local function pick_zones()
    zones, targets = {}, {}
    for _, zn in ipairs(S.zones) do
        local list = zn.kind == "target" and targets or zones
        list[#list + 1] = zn
    end
end

-- whether (x, y) with feet at h is inside an area, widened by MARGIN
local function inside(zn, x, y, h)
    local r, zz = zn.r + MARGIN, zn.z
    local dx, dy = x - zn.x, y - zn.y
    if zn.kind == "lane" then -- distance to the lane's centre line
        local ex, ey = zn.bx - zn.x, zn.by - zn.y
        local t = math.max(0, math.min(1, (dx * ex + dy * ey) / math.max(1, ex * ex + ey * ey)))
        dx, dy, zz = dx - ex * t, dy - ey * t, zz + (zn.bz - zz) * t
    end
    if abs(h - zz) > HEIGHT then return false end
    local d2 = dx * dx + dy * dy
    if d2 >= r * r then return false end
    if zn.kind ~= "cone" or d2 < MARGIN * MARGIN then return true end
    -- inside the fan's angle, widened so the margin holds at this distance too
    local off = abs((atan(dy, dx) - zn.yaw + pi) % (2 * pi) - pi)
    return off <= zn.half + MARGIN / sqrt(d2)
end

local function danger(x, y, h)
    for _, zn in ipairs(zones) do
        if inside(zn, x, y, h) then return true end
    end
    return false
end

local function fraction(a, b)
    local tr = U.trace_line(a, b)
    local f = tr and U.field(tr, "fraction")
    return type(f) == "number" and f or 0 -- a failed trace counts as blocked
end

-- the floor under (x, y) within a step up or a drop down from height z; nil for a wall (the trace
-- starts in it or lands on top of it) or a ledge (nothing below)
local function floor_at(x, y, z)
    local f = fraction(Vector(x, y, z + KNEE), Vector(x, y, z - DROP))
    if f >= 1 then return nil end
    local fz = z + KNEE - (KNEE + DROP) * f
    if fz > z + STEP_UP then return nil end
    return fz
end

-- nothing in the way between two cells, at knee height so steps aren't walls
local function clear(a, b)
    return fraction(Vector(a.x, a.y, a.z + KNEE), Vector(b.x, b.y, b.z + KNEE)) >= 1
end

-- binary heap of cells by path cost, cheapest on top; a cell is pushed again when its cost drops,
-- and its stale copies are skipped when popped
local function push(h, c)
    local i = #h + 1
    h[i] = c
    while i > 1 do
        local p = math.floor(i / 2)
        if h[p].g <= c.g then break end
        h[i], h[p], i = h[p], c, p
    end
end

local function pop(h)
    local top, last, n = h[1], h[#h], #h - 1
    h[#h] = nil
    if n == 0 then return top end
    local i = 1
    while true do
        local l = 2 * i
        if l > n then break end
        if l < n and h[l + 1].g < h[l].g then l = l + 1 end
        if h[l].g >= last.g then break end
        h[i], i = h[l], l
    end
    h[i] = last
    return top
end

local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

-- uniform-cost search out from `o`: the first cell outside every area to come off the heap is the
-- cheapest to reach, so it is both the safe spot and the end of the path there. Each cell's floor
-- is traced once, when first reached; a wall between two cells only when that step would be taken.
local function search(o)
    local W = 2 * REACH + 1
    local start = { i = 0, j = 0, x = o.x, y = o.y, z = o.z, g = 0, hot = true }
    local cells, heap, goal = { [REACH * W + REACH] = start }, { start }, nil
    while #heap > 0 do
        local c = pop(heap)
        if not c.done then
            c.done = true
            if not c.hot then goal = c break end
            for _, d in ipairs(DIRS) do
                local i, j = c.i + d[1], c.j + d[2]
                if abs(i) <= REACH and abs(j) <= REACH then
                    local key = (i + REACH) * W + j + REACH
                    local n = cells[key]
                    if not n then
                        local x, y = o.x + i * CELL, o.y + j * CELL
                        local z = floor_at(x, y, c.z)
                        n = { i = i, j = j, x = x, y = y, z = z or c.z, g = math.huge, blocked = not z }
                        n.hot = z ~= nil and danger(x, y, z)
                        cells[key] = n
                    end
                    local g = c.g + (d[1] ~= 0 and d[2] ~= 0 and 1.414 or 1) * (n.hot and DANGER_COST or 1)
                    if not n.blocked and not n.done and g < n.g and n.z - c.z <= STEP_UP and clear(c, n) then
                        n.g, n.from = g, c
                        push(heap, n)
                    end
                end
            end
        end
    end
    local plan = { cells = {}, goal = goal, k = 2, at = S.now, from = start }
    for _, c in pairs(cells) do plan.cells[#plan.cells + 1] = c end
    if goal then
        plan.path = {}
        local c = goal
        while c do table.insert(plan.path, 1, c) c = c.from end
    end
    return plan
end

local logged_at, logged_mode, stats_logged = -math.huge, nil, false
local DASH_CHECK = 0.15 -- seconds after a dash tap that Debug Mode checks it went
-- the same check sooner while a parry roots you, to tap again close to when it lets go: a tap
-- 0.27-0.29 s into a parry never went, one 0.43-0.45 s in always did (8 Singularity casts, 2026-11-10)
local DASH_RETRY = 0.04
-- no dash goes before this far into a parry (from its tap): 0.42 s in failed, 0.45 s in went, so
-- it is tapped from here, not wasted earlier (7 Singularity casts, 2026-11-10)
local PARRY_ROOT = 0.42
-- the parry against an area that outlasts it (`lingers`) goes this long before the hit, not Parry
-- Lead: the time before it is walked away from the caster, as the parry roots you, and a dash out
-- has ~0.4 s of the parry left whenever it is tapped. 7 m of Singularity took 0.46-0.54 s to dash
-- out of; those were caught, and those under 0.44 s got out
local LINGER_LEAD = 0.1
local shielded          -- while a parry holds: when it lets an area with no hit time of its own take you
local GUARD_LOOK = 0.15 -- seconds of walking ahead the guard checks: about how far you take to stop
local last_dash         -- where the last dash was tapped from and to, until it is checked
local held              -- the direction keys the last command held for the dodge
local last_hp           -- your health last frame, for Debug Mode's "you lost" line
local last_area         -- Debug Mode: the last cone or lane seen and where it first pointed, for a hit in it

local function camera_yaw(cmd)
    local ok, cam = pcall(function() return utils.get_camera_angles() end)
    local a = ok and cam or (cmd and U.field(cmd, "viewangles"))
    local yaw = a and tonumber(U.field(a, "yaw"))
    return yaw, ok and cam and "camera" or "viewangles"
end

-- one of your hero's stats (an EStatsType name), or `default` when it doesn't read
local function stat(name, default)
    local id = EStatsType and EStatsType[name]
    local v = id and tonumber(U.try(S.me, "get_scaling_stat", id))
    if not v or v <= 0 then v = id and tonumber(U.try(S.me, "get_starting_stat", id)) end
    return v and v > 0 and v or default
end

-- a speed stat in units/s, or `default_mps` m/s when it doesn't read. Hero speeds read in units/s
-- (EMaxMoveSpeed ~275 in game, taken as m/s it made walking look 39x too fast); one under 50 is m/s
local function speed_stat(name, default_mps)
    local v = stat(name, nil)
    if not v then return default_mps * CFG.UNITS_PER_M end
    return v < 50 and v * CFG.UNITS_PER_M or v
end

-- seconds until area `zn` hits you at `o`: nil when it doesn't say (a danger for as long as it is
-- drawn), false when its shot has already gone past you
local function time_left(zn, o)
    if zn.at then
        -- a wave rolling out (`grow`, units/s) passes where you stand before it is at its edge
        local early = zn.grow and (zn.r - sqrt((o.x - zn.x) ^ 2 + (o.y - zn.y) ^ 2)) / zn.grow or 0
        return zn.at - S.now - math.max(0, early)
    end
    if not (zn.speed and zn.px) then return nil end
    local ex, ey = zn.bx - zn.x, zn.by - zn.y
    local d = ((o.x - zn.px) * ex + (o.y - zn.py) * ey) / math.max(1, sqrt(ex * ex + ey * ey)) -- shot to you
    if d < -(zn.r + MARGIN) then return false end
    -- its front reaches you `r` before its centre does; a wind-up's shot leaves after `delay`
    return (zn.delay or 0) + math.max(0, d - zn.r) / zn.speed
end

-- whether an area still threatens you at `o`, and the seconds until the soonest one hits (nil: none says)
local function threat(o)
    local hot, soonest, first, urgent = false, nil, nil, false
    for _, zn in ipairs(zones) do
        local t = inside(zn, o.x, o.y, o.z) and time_left(zn, o)
        if t ~= false then
            hot, urgent = true, urgent or zn.urgent == true
            if t and (not soonest or t < soonest) then soonest, first = t, zn end
        end
    end
    return hot, soonest, first, urgent
end

local function path_length(path)
    local len = 0
    for i = 2, #path do len = len + sqrt((path[i].x - path[i - 1].x) ^ 2 + (path[i].y - path[i - 1].y) ^ 2) end
    return len
end

-- Moving from `o` along `pts` (o first) at `v` units/s, REACT from now: the seconds until you are
-- out of every area for good, and whether each one is left before it hits. Each by its own time,
-- not the soonest: Bashdown's wave is at its edge 0.5 s after the slam, and held to the slam no
-- dash made it out. A wave (`grow`) is left by the time it is at its edge
local function way_out(o, pts, v)
    local out, gain, fail = REACT, false, false
    for _, zn in ipairs(zones) do
        local t = time_left(zn, o)
        local d, exit, pending = 0, 0, false -- path length so far, and to the first point past the last one in `zn`
        for i, p in ipairs(pts) do
            if i > 1 then d = d + sqrt((p.x - pts[i - 1].x) ^ 2 + (p.y - pts[i - 1].y) ^ 2) end
            if inside(zn, p.x, p.y, p.z) then pending = true elseif pending then exit, pending = d, false end
        end
        if pending then exit = d end
        if exit > 0 and t ~= false then -- false: a shot already past you
            local time = REACT + exit / v
            out = math.max(out, time)
            if zn.grow then t = zn.at - S.now end
            -- one that has gone off already (t < 0) is no deadline left to meet, nor one to move for:
            -- the slam's area lingers a moment under its wave, which is still worth leaving
            if not t or t >= 0 and time <= t then gain = true elseif t >= 0 then fail = true end
        end
    end
    return out, gain and not fail
end

-- the way from `o` straight to (x, y) in 5 unit steps, counted back from its end: half-cell ones
-- rounded the way out up to 0.5 m long, 0.03 s on a 0.3 s Uppercut
local function straight(o, x, y)
    local dx, dy = x - o.x, y - o.y
    local len = sqrt(dx * dx + dy * dy)
    local pts = { o }
    if len < 1 then return pts end
    for s = len % 5, len + 0.01, 5 do pts[#pts + 1] = { x = o.x + dx / len * s, y = o.y + dy / len * s, z = o.z } end
    return pts
end

local function airborne()
    local ok, ground = pcall(HERO_LIB.is_on_ground, S.me)
    return ok and ground == false
end

-- a dash that gets you clear in time: one of the 8 key directions around the camera, cut short at a
-- wall, ending outside every area and crossing out of each before it hits at dash speed, the one
-- ending nearest the walk goal; else nil and why not. On the ground it ends on floor; in the air it
-- is the air dash, level at your height (it holds you up while it lasts)
local function dash_out(o, _, goal)
    local ok, stamina = pcall(HERO_LIB.get_stamina, S.me)
    if ok and tonumber(stamina) and tonumber(stamina) < 1 then return nil, "no stamina" end
    local air = airborne()
    local dist = (air and stat("EAirDashDistanceInMeters", AIR_DASH_DIST)
        or stat("EGroundDashDistanceInMeters", DASH_DIST)) * CFG.UNITS_PER_M
    local dur = air and stat("EAirDashDuration", AIR_DASH_TIME) or stat("EGroundDashDuration", DASH_TIME)
    -- the whole dash lasts `dur` (~0.7 s in game), but you are out as soon as you cross the edge
    local v = stat("EDashSpeedInMeters", nil) and speed_stat("EDashSpeedInMeters", 0) or dist / dur
    local yaw = math.rad(camera_yaw() or 0)
    local best, best_d, late, late_best
    for k = 0, 7 do
        local a = yaw + k * pi / 4
        local ux, uy = math.cos(a), math.sin(a)
        local f = fraction(Vector(o.x, o.y, o.z + KNEE), Vector(o.x + ux * dist, o.y + uy * dist, o.z + KNEE))
        local len = f >= 1 and dist or math.max(0, f * dist - CELL / 2) -- stopped short of a wall
        local x, y = o.x + ux * len, o.y + uy * len
        local z = air and o.z or floor_at(x, y, o.z)
        if z and not danger(x, y, z) then
            local time, ok = way_out(o, straight(o, x, y), v)
            local d = goal and (x - goal.x) ^ 2 + (y - goal.y) ^ 2 or -len
            if not ok then
                if not late or time < late then
                    late, late_best = time, { x = x, y = y, z = z, time = time, dur = dur, v = v, air = air, late = true }
                end
            elseif not best_d or d < best_d then
                best, best_d = { x = x, y = y, z = z, time = time, dur = dur, v = v, air = air }, d
            end
        end
    end
    if best then return best end
    -- A parry holding off an area that will take you when it ends: the soonest dash out goes even if
    -- it may be late, as standing there is sure to be. Singularity took you 3 times of 8, each after
    -- the dash out was called 0.01-0.07 s late and none was tried
    if late_best and shielded then return late_best end
    local kind = air and "air dash" or "dash"
    if late then return nil, ("a%s %s gets out in %.2f s at the soonest"):format(air and "n" or "", kind, late) end
    return nil, ("no %.1f m %s ends clear of it"):format(dist / CFG.UNITS_PER_M, kind)
end

-- whether Counterspell is on its cooldown, and what the item says, for Debug Mode. Any of three
-- readings counts: HERO_LIB.is_ability_in_cd, can_be_executed's COOLDOWN, or is_ability_ready
-- saying no (it means "ready to use", which for a passive item may never track the cooldown).
-- get_cooldown is only logged: whether it is the time left or the full 23 s isn't documented
local function counter_down(item)
    local okc, in_cd = pcall(HERO_LIB.is_ability_in_cd, item)
    local okr, ready = pcall(HERO_LIB.is_ability_ready, item)
    local state = U.try(item, "can_be_executed")
    local states = Enum and Enum.AbilityExecuteState
    local down = okc and in_cd == true or states and state == states.COOLDOWN or okr and ready == false
    return down, ("in_cd %s, can_be_executed %s, ready %s, get_cooldown %s"):format(okc and tostring(in_cd) or "?",
        tostring(state), okr and tostring(ready) or "?", tostring(U.try(item, "get_cooldown")))
end

local counter_was -- Counterspell's last state as logged: "down", "ready" or "none"

-- Debug Mode: Counterspell's cooldown as it changes, with every reading, so one real block in a
-- real match shows which of them tracks it (a sandbox has no cooldowns)
local function log_counter()
    local item = ui.sp_debug:Get() and S.me and U.find_ability(S.me, "upgrade_counterspell")
    local down, detail = false, nil
    if item then down, detail = counter_down(item) end
    local now = not item and "none" or down and "down" or "ready"
    if not ui.sp_debug:Get() or now == counter_was then return end
    counter_was = now
    if item then U.log("dodge: Counterspell %s (%s)", down and "on cooldown" or "ready", detail) end
end

-- whether an item is ticked in the Evade Tools card (CFG.EVADE_ITEMS); an unreadable setting counts as on
local function item_on(name)
    local ok, on = pcall(function() return ui.sp_evade_items:Get(name) end)
    return not ok or on ~= false
end

-- Counterspell (upgrade_counterspell) is passive: "your next parry protects you from the damage and
-- effects of enemy abilities and items" for SpellParryDuration. So a parry timed to the hit: only
-- with the item off cooldown and a hit time to aim at; else nil and why not
local function counterspell(_, t, _, zn)
    -- `unblockable` (the spell's): Counterspell's sphere was up as Apollo's lunge hit, and it went through
    if zn and zn.unblockable then return nil, "Counterspell doesn't block it" end
    if not item_on("Counterspell") then return nil, "Counterspell turned off" end
    local item = U.find_ability(S.me, "upgrade_counterspell")
    if not item then return nil, "no Counterspell" end
    if counter_down(item) then return nil, "Counterspell on cooldown" end
    -- a simulated block puts it down as a real one would: the item itself only goes down on a real hit
    if S.counter_until and S.now < S.counter_until then return nil, "Counterspell on cooldown (simulated)" end
    if S.parry and S.now < S.parry.to then return nil, "its parry is already up" end
    if not t then return nil, "no hit time to parry at" end
    -- Tried until the hit itself, not held to the parry's own lag: Charged Shot is seen 0.03-0.11 s
    -- before it lands, and the parry was up 0.02-0.05 s after its tap. Of 10 with Counterspell, 3 seen
    -- 0.03-0.05 s off were called too late and hit; 6 of 7 tried were blocked (2026-11-10). A parry
    -- that blocks nothing costs the parry's ~1 s cooldown, not Counterspell's
    if t < 0 then return nil, "too late to parry" end
    return { item = item,
             window = tonumber(U.try(item, "get_scaled_property", "SpellParryDuration")) or COUNTER_WINDOW,
             cooldown = tonumber(U.try(item, "get_scaled_property", "AbilityCooldown")) or COUNTER_COOLDOWN }
end

-- the ways out once walking is too slow, tried in turn, cheapest first: each gets (o, t, goal) and
-- gives a plan or nil and why not. A hero's own evade ability goes in here
local ESCAPES = {
    { mode = "dash", try = dash_out },
    { mode = "counterspell", try = counterspell },
}

local function secs(t) return t and ("%.2f s"):format(t) or "no hit time" end

-- a spell cast at you, `t` from hitting: no walk or dash gets out of it, so only what blocks it is
-- tried (Counterspell; a hero's own block would join it), else nothing is sent. Planned again on
-- the REPLAN timer, and kept while its parry is up
local function plan_block(o, t)
    local p = S.dodge
    if p and p.targeted and (p.parried and S.now < p.parry_until or S.now - p.at < REPLAN) then return end
    local cs, why = counterspell(o, t)
    p = { targeted = true, t = t, at = S.now, from = o, cells = {}, counterspell = cs,
          mode = cs and "counterspell" or "none", why = why and ("cast at you, " .. why) }
    S.dodge = p
    if ui.sp_debug:Get() and (S.now - logged_at > 0.5 or p.mode ~= logged_mode) then
        logged_at, logged_mode = S.now, p.mode
        U.log("dodge: %s, cast at you, hits in %s", cs and "counterspell" or ("no escape (" .. why .. ")"), secs(t))
    end
end

-- a Tuning slider's value, or `default` when it doesn't read
local function tuned(k, default)
    local ok, v = pcall(function() return ui[k]:Get() end)
    return ok and tonumber(v) or default
end

-- on_frame: plan while you stand in danger, using the areas drawn last frame. Walk if the path gets
-- you out of each area before it hits; else dash if one does; else nothing (mode "none"): an
-- input that can't save you is wasted
function E.update()
    local def = CFG.DEFAULTS
    -- Reaction Time no lower than its slider's 0.1 s: a setting saved at 0 broke the dodge
    REACT = math.max(MIN_REACT, tuned("sp_react", def.sp_react))
    COUNTER_LEAD = tuned("sp_parry_lead", def.sp_parry_lead)
    REPLAN = tuned("sp_replan", def.sp_replan)
    DODGE_GAP = tuned("sp_dodge_gap", def.sp_dodge_gap)
    MARGIN = tuned("sp_margin", def.sp_margin) * CFG.UNITS_PER_M
    pick_zones()
    log_counter()
    -- A Counterspell parry that is up: an area with no hit time of its own takes you as the parry
    -- ends, so that is its hit time while it lasts. Singularity's pull lasts its whole 2.75 s
    -- channel: 5 of 5 parries blocked it, and it took you 0.85-0.95 s later as each ran out. Its
    -- window counts from when it is up, PARRY_LAG after the tap: the pull came 0.85-0.86 s after it
    local shield = S.parry and S.now < S.parry.to + PARRY_LAG and S.parry.to + PARRY_LAG
    shielded = shield
    if shield then
        for _, zn in ipairs(zones) do if not zn.at and not zn.speed then zn.at = shield end end
    end
    for _, zn in ipairs(zones) do
        if zn.kind == "cone" or zn.kind == "lane" then
            local yaw = zn.kind == "cone" and zn.yaw or atan(zn.by - zn.y, zn.bx - zn.x)
            local fresh = not last_area or last_area.zn.kind ~= zn.kind or S.rt - last_area.rt > 0.3
            last_area = { zn = zn, rt = S.rt, yaw = yaw, yaw0 = fresh and yaw or last_area.yaw0 }
        end
    end
    local o = S.me and (ui.sp_dodge:Get() or ui.sp_dodge_debug:Get()) and U.try(S.me, "get_origin")
    -- Debug Mode, once per dash, DASH_CHECK after the tap: whether it went, how fast and which way.
    -- From origins: get_velocity reads in local space, so it can't give the direction
    if last_dash and o and S.rt - last_dash.rt >= (shielded and DASH_RETRY or DASH_CHECK) then
        local d = last_dash
        last_dash = nil
        local okd, dashing = pcall(HERO_LIB.is_any_dashing, S.me)
        -- A dash that didn't go is tapped again, not waited out for its whole length: a parry roots
        -- you, and the one dash tapped 0.2 s into each Singularity parry moved you 0.0 m, then nothing
        -- was tried until the pull had you (2 of 2, 2026-11-10)
        local p = S.dodge
        if okd and dashing == false and p and p.dashed then p.dashed, p.dash_until, p.at = nil, nil, -math.huge end
        if ui.sp_debug:Get() then
            local dx, dy = o.x - d.x, o.y - d.y
            local moved, el = sqrt(dx * dx + dy * dy), S.rt - d.rt
            local off = moved > 1 and math.deg(abs((atan(dy, dx) - atan(d.to.y - d.y, d.to.x - d.x) + pi) % (2 * pi) - pi))
            -- how far into a parry it was tapped: when a parry lets you dash again
            local parry = S.parry and d.t - S.parry.from < S.parry.to - S.parry.from + 0.5
                and (", tapped %.2f s into a parry"):format(d.t - S.parry.from) or ""
            U.log("dodge: dash check after %.2f s: moved %.1f m (%.1f m/s, walking is %.1f), %s off its way, dashing %s%s",
                el, moved / CFG.UNITS_PER_M, moved / el / CFG.UNITS_PER_M, speed_stat("EMaxMoveSpeed", WALK_SPEED)
                / CFG.UNITS_PER_M, off and ("%.0f deg"):format(off) or "?", okd and tostring(dashing) or "?", parry)
        end
    end
    -- a spell cast at you comes first: only a block helps against it
    local tt
    for _, zn in ipairs(o and targets or {}) do
        local left = zn.at and zn.at - S.now
        if left and (not tt or left < tt) then tt = left end
    end
    -- Debug Mode: each loss of health, so the log alone says what got through
    local hp = ui.sp_debug:Get() and S.me and tonumber((select(2, pcall(HERO_LIB.get_health, S.me))))
    if hp and last_hp and hp < last_hp - 0.5 then
        U.log("you lost %.0f health, %.0f left", last_hp - hp, hp)
        -- in a cone or lane that was just up: how deep in it you stood, and whether its caster turned it
        local c = o and last_area and S.rt - last_area.rt < 0.3 and last_area
        if c then
            local zn, m = c.zn, CFG.UNITS_PER_M
            local dx, dy = o.x - zn.x, o.y - zn.y
            local function deg(a) return math.deg(abs((a + pi) % (2 * pi) - pi)) end
            if zn.kind == "cone" then
                U.log("  cone: you %.1f m from its caster (reach %.1f), %.0f deg off its aim (half %.0f); it turned %.0f deg since first seen",
                    sqrt(dx * dx + dy * dy) / m, zn.r / m, deg(atan(dy, dx) - zn.yaw), math.deg(zn.half), deg(c.yaw - c.yaw0))
            else
                local ex, ey = zn.bx - zn.x, zn.by - zn.y
                local len = math.max(1, sqrt(ex * ex + ey * ey))
                U.log("  lane: you %.1f m off its middle (half-width %.1f), %.1f m along it of %.1f; it turned %.0f deg since first seen",
                    abs(dx * ey - dy * ex) / len / m, zn.r / m, (dx * ex + dy * ey) / len / m, len / m, deg(c.yaw - c.yaw0))
            end
        end
    end
    last_hp = hp
    local hot, t, urgent = false, nil, false
    local tz -- the area that hits soonest, for what may answer it
    if o then hot, t, tz, urgent = threat(o) end
    -- unless an area you stand in hits sooner: Chain Gang's pull is 2.8 s off, and he slams you meanwhile
    -- Dodge Interval: once a dodge has ended, a new one waits this long
    if not S.dodge and S.now - dodge_ended < DODGE_GAP then return end
    if tt and not (hot and t and t < tt) then return plan_block(o, tt) end
    local p = S.dodge
    -- A dash under way runs its course, in an area or not: Apollo's lane left you for a frame as he
    -- turned, and the plan that came after tapped the dash again 0.03-0.06 s later (2 dashes of 5)
    if p and p.dashed and S.now < p.dash_until then
        -- Unless an area hits before the dash is out of it: then a block, if there is one. Apollo let
        -- go on you mid-dash, 0.5 m off his aim; the dash ran its course and the stab took 65
        -- Its reaction time is spent once it is tapped: counted again, every dash planned with less than
        -- that to spare read as failing as it began, and was parried, the parry stopping it (3 of 3
        -- Charged Shots). Let run, such dashes got out: 6 of 6 with 0.00-0.07 s to spare (2026-11-10)
        local react = REACT
        REACT = math.max(0, REACT - (S.now - (p.dashed_at or S.now)))
        local made = select(2, way_out(o, straight(o, p.dash.x, p.dash.y), p.dash.v))
        REACT = react
        local cs = hot and t and not p.parried and not made and counterspell(o, t, nil, tz)
        if cs then
            p.mode, p.counterspell, p.t, p.at = "counterspell", cs, t, S.now
            if ui.sp_debug:Get() then U.log("dodge: counterspell mid-dash, hits in %s", secs(t)) end
        end
        return
    end
    if not hot then
        if S.dodge then dodge_ended = S.now end
        S.dodge = nil
        return
    end
    -- Debug Mode, once: your hero's stats as read, raw, for the walk and dash times
    if ui.sp_debug:Get() and not stats_logged then
        stats_logged = true
        local ok, stamina = pcall(HERO_LIB.get_stamina, S.me)
        U.log("dodge stats (raw): EMaxMoveSpeed %s, EGroundDashDistanceInMeters %s, EGroundDashDuration %s, "
            .. "EAirDashDistanceInMeters %s, EAirDashDuration %s, EDashSpeedInMeters %s, stamina %s",
            tostring(stat("EMaxMoveSpeed")), tostring(stat("EGroundDashDistanceInMeters")),
            tostring(stat("EGroundDashDuration")), tostring(stat("EAirDashDistanceInMeters")),
            tostring(stat("EAirDashDuration")),
            tostring(stat("EDashSpeedInMeters")), ok and tostring(stamina) or "?")
    end
    -- So does a Counterspell parry, whatever plan stands: what hits while it holds is blocked. Only
    -- an area that outlasts it is left the way out of while it holds (Evade stood still through 5
    -- Singularity parries, and was taken each time). Held to the parry plan alone, the frame between
    -- Kinetic Pulse's wind-up and its wave dropped that plan, and 4 parried waves were then dashed
    -- from, "late", 4 to 5 taps each (2026-11-10)
    if shield and not (hot and t and t >= shield - S.now - 1e-6) then return end
    -- search again on a timer, as the areas move, or at once if the spot it heads for turned unsafe
    -- (a plan for a spell cast at you isn't one for this area: search now), or if a plan made with no
    -- hit time now has one: Apollo's stab lands 0.1 s after he lets go, inside the timer
    if p and not p.targeted and S.now - p.at < REPLAN and (p.t or not t)
        and not (p.goal and danger(p.goal.x, p.goal.y, p.goal.z)) then return end
    p = search(o)
    p.t = t
    local walk_speed = speed_stat("EMaxMoveSpeed", WALK_SPEED)
    p.walk = p.goal and path_length(p.path) / walk_speed + REACT
    local walk_ok = p.goal and select(2, way_out(o, p.path, walk_speed))
    -- An `urgent` area (a charge he can let go of any moment, with no hit time to hold it to) is left
    -- the fastest way there is: a dash before a walk. Timed to one guessed release, Apollo's lane read
    -- as too late for anything once the guess had passed, and you stood in it for the rest of the charge
    -- So is one you are in the air over: your walking speed doesn't hold there, and the air dash does.
    -- shortcut: air strafing is never planned for itself, only walked when no dash or parry answers
    if walk_ok and not urgent and not airborne() then
        p.mode = "walk"
    else
        local whys = {}
        for _, e in ipairs(ESCAPES) do
            local d, why = e.try(o, t, p.goal, tz)
            if d then
                p.mode, p[e.mode] = e.mode, d
                break
            end
            whys[#whys + 1] = why
        end
        p.why = table.concat(whys, ", ")
        if p.mode == "dash" then
            p.goal, p.path = p.dash, { { x = o.x, y = o.y, z = o.z }, p.dash }
        elseif p.mode == "counterspell" then
            if tz and tz.lingers then
                p.lead = math.min(COUNTER_LEAD, LINGER_LEAD) -- walked out along the path until the parry
            else
                p.goal, p.path = nil, nil -- it is blocked where you stand: no walking
            end
        else
            p.mode = walk_ok and "walk" or "none" -- an urgent area with no dash to give: walked
        end
    end
    S.dodge = p
    if ui.sp_debug:Get() and (S.now - logged_at > 0.5 or p.mode ~= logged_mode) then
        logged_at, logged_mode = S.now, p.mode
        local walk = p.walk and ("walking takes " .. secs(p.walk)) or ("no walkable safe spot within " .. REACH .. " cells")
        if p.mode == "walk" then
            U.log("dodge: walk %.1f m, %s, hits in %s", path_length(p.path) / CFG.UNITS_PER_M, walk, secs(t))
        elseif p.mode == "dash" then
            U.log("dodge: %s %.1f m, out in %s, hits in %s (%s)%s", p.dash.air and "air dash" or "dash",
                sqrt((p.dash.x - o.x) ^ 2 + (p.dash.y - o.y) ^ 2)
                / CFG.UNITS_PER_M, secs(p.dash.time), secs(t), walk,
                p.dash.late and ", late, but staying is sure to be caught as the parry ends" or "")
        elseif p.mode == "counterspell" then
            U.log("dodge: counterspell, parry %s before the hit%s, hits in %s (%s, %s)", secs(p.lead or COUNTER_LEAD),
                p.path and ", walking away until then" or "", secs(t), walk, p.why)
        else
            U.log("dodge: no escape, hits in %s: %s, %s", secs(t), walk, p.why)
        end
    end
end

local MOVE_KEYS = IN.IN_FORWARD | IN.IN_BACK | IN.IN_MOVELEFT | IN.IN_MOVERIGHT
local steer_logged_at = -math.huge

local function key_names(mask)
    return (mask & IN.IN_FORWARD ~= 0 and "W" or "") .. (mask & IN.IN_MOVELEFT ~= 0 and "A" or "")
        .. (mask & IN.IN_BACK ~= 0 and "S" or "") .. (mask & IN.IN_MOVERIGHT ~= 0 and "D" or "")
end

local seen_down = 0

-- Debug Mode: names each key you press yourself (other than moving), to tell which InputBitMask_t
-- bit a game action sends; the dash is DASH_KEY
local function log_presses(cmd)
    if not ui.sp_debug:Get() or not InputBitMask_t then return end
    local down = math.tointeger(U.try(cmd, "get_orig_buttons_down_mask")) or 0
    local new = down & ~seen_down & ~MOVE_KEYS
    seen_down = down
    if new == 0 then return end
    local names = {}
    for name, bit in pairs(InputBitMask_t) do
        bit = math.tointeger(bit)
        if bit and bit > 0 and new & bit == bit then names[#names + 1] = name end
    end
    table.sort(names)
    U.log("you pressed %s (0x%x)", table.concat(names, " "), new)
end

-- inside an area that is still to hit someone at (x, y): a shot already past there doesn't count
local function threatened(x, y, h)
    for _, zn in ipairs(zones) do
        if inside(zn, x, y, h) and time_left(zn, { x = x, y = y }) ~= false then return true end
    end
    return false
end

local guard_logged_at = -math.huge

-- Evade (the menu switch), while you stand clear: your own movement keys may not walk you into an area that is
-- still to hit, or the dodge walks you out and your keys walk you straight back in (a Shining Wonder
-- hit). Keys that lead in within GUARD_LOOK of walking are let go; of a diagonal, the half that stays
-- out is kept, so you slide along the edge; any other way is yours
local function guard(cmd)
    local down = math.tointeger(cmd:get_buttons_down_mask()) or 0
    down = down & MOVE_KEYS
    local o = down ~= 0 and U.try(S.me, "get_origin")
    local yaw = o and camera_yaw(cmd)
    if not yaw then return end
    yaw = math.rad(yaw)
    local ahead = speed_stat("EMaxMoveSpeed", WALK_SPEED) * GUARD_LOOK
    local function axes(keys)
        return (keys & IN.IN_FORWARD ~= 0 and 1 or 0) - (keys & IN.IN_BACK ~= 0 and 1 or 0),
            (keys & IN.IN_MOVELEFT ~= 0 and 1 or 0) - (keys & IN.IN_MOVERIGHT ~= 0 and 1 or 0)
    end
    -- whether walking on `keys` (relative to the camera, +y left of +x) leads into an area
    local function into(keys)
        local f, l = axes(keys)
        if f == 0 and l == 0 then return false end
        local n = ahead / sqrt(f * f + l * l)
        local dx = (f * math.cos(yaw) - l * math.sin(yaw)) * n
        local dy = (f * math.sin(yaw) + l * math.cos(yaw)) * n
        return threatened(o.x + dx, o.y + dy, o.z)
    end
    if not into(down) then return end
    local fb, lr = down & (IN.IN_FORWARD | IN.IN_BACK), down & (IN.IN_MOVELEFT | IN.IN_MOVERIGHT)
    local keep = 0
    if fb ~= 0 and lr ~= 0 then keep = not into(fb) and fb or not into(lr) and lr or 0 end
    cmd:release(down & ~keep)
    cmd.forwardmove, cmd.leftmove = axes(keep)
    if ui.sp_debug:Get() and S.now - guard_logged_at > 0.5 then
        guard_logged_at = S.now
        U.log("dodge guard: let go of %s (it walks you into an area)%s", key_names(down & ~keep),
            keep ~= 0 and (", kept " .. key_names(keep)) or "")
    end
end

-- a Counterspell plan: the parry is tapped once, COUNTER_LEAD before the hit, with whatever would
-- stop it let go; the plan is then kept for the window, and the simulator told when it ran
local function parry(cmd, p)
    if p.parried or p.t - (S.now - p.at) > (p.lead or COUNTER_LEAD) then return end
    local busy = (math.tointeger(cmd:get_buttons_down_mask()) or 0) & PARRY_CONFLICT
    if busy ~= 0 then cmd:release(busy) end
    cmd:tap(PARRY_KEY)
    p.parried, p.parry_until = true, S.now + p.counterspell.window
    S.parry = { from = S.now, to = p.parry_until, cooldown = p.counterspell.cooldown }
    if ui.sp_debug:Get() then
        -- what the item says of its own cooldown, to learn whether a real block puts it down
        local _, detail = counter_down(p.counterspell.item)
        U.log("dodge: Counterspell parry tapped, %s before the hit, blocks for %s (item: %s)",
            secs(p.t - (S.now - p.at)), secs(p.counterspell.window), detail)
    end
end

-- on_createmove, the button methods' context: walk the path, one cell centre after another,
-- whatever way you are looking. Your hero only moves while a movement key is down (the analog
-- values alone only steer), so the keys are held for it: press holds for this tick, so it is
-- called every tick, and every other movement key is let go, yours included. A dash plan taps the
-- dash key once along with them; a Counterspell plan only parries; a plan that can't escape sends
-- nothing. With no plan (you stand clear), the guard keeps your own keys from walking you in
function E.steer(cmd)
    log_presses(cmd)
    local was_held = held
    held = nil -- the direction keys this command holds for the dodge, if it gets to hold any
    local p = S.dodge
    -- also while a spell cast at you waits for its parry: Chain Gang's is 2.8 s of walking about
    if (not p or p.targeted) and ui.sp_dodge:Get() then guard(cmd) end
    if not p then return end
    if p.mode == "counterspell" and ui.sp_dodge:Get() then
        parry(cmd, p)
        if p.parried or not p.path then return end -- else walk away until it is tapped (`lingers`)
    end
    local o = p and p.path and p.mode ~= "none" and ui.sp_dodge:Get() and U.try(S.me, "get_origin")
    if not o then return end
    local path = p.path
    while p.k < #path and (path[p.k].x - o.x) ^ 2 + (path[p.k].y - o.y) ^ 2 < ARRIVE * ARRIVE do p.k = p.k + 1 end
    local n = path[p.k]
    local dx, dy = n.x - o.x, n.y - o.y
    -- the keys move you relative to the camera; forward along it, left across it (+y is left of +x)
    local yaw, yaw_src = camera_yaw(cmd)
    if dx * dx + dy * dy < 1 or not yaw then return end
    yaw = math.rad(yaw)
    local f = dx * math.cos(yaw) + dy * math.sin(yaw)
    local l = dy * math.cos(yaw) - dx * math.sin(yaw)
    -- snapped to the 8 key directions (a key is held when its axis is within 22.5 deg of the way to
    -- go): the keys, and the analog values as a keyboard sends them
    local m = math.max(abs(f), abs(l))
    local function key(v) return v > 0.414 * m and 1 or v < -0.414 * m and -1 or 0 end
    f, l = key(f), key(l)
    local keys = (f > 0 and IN.IN_FORWARD or f < 0 and IN.IN_BACK or 0)
        | (l > 0 and IN.IN_MOVELEFT or l < 0 and IN.IN_MOVERIGHT or 0)
    local yours = cmd:get_buttons_down_mask() & MOVE_KEYS & ~keys
    if yours ~= 0 then cmd:release(yours) end
    cmd:press(keys)
    cmd.forwardmove, cmd.leftmove = f, l
    if p.mode == "dash" and not p.dashed then
        -- the direction keys go down a command before the dash, so it goes the way they point; tap
        -- then holds the dash for two commands and lets go by itself; the plan is kept until it is
        -- done. Down the command before, whichever plan held them: a lane that turns with its caster
        -- replans every frame, and a dash each new plan had to aim again never went (3 of 24)
        local rooted = S.parry and S.now - S.parry.from < PARRY_ROOT and S.now < S.parry.to + PARRY_LAG
        if was_held == keys and not rooted then
            cmd:tap(DASH_KEY)
            p.dashed, p.dashed_at, p.dash_until = true, S.now, S.now + p.dash.dur + REACT
            last_dash = { x = o.x, y = o.y, to = p.dash, rt = S.rt, t = S.now }
            if ui.sp_debug:Get() then U.log("dodge: dash tapped, holding %s", key_names(keys)) end
        end
    end
    held = keys
    -- Debug Mode, twice a second: what went out, and whether you are actually moving
    if ui.sp_debug:Get() and S.now - steer_logged_at > 0.5 then
        steer_logged_at = S.now
        local v = U.try(S.me, "get_velocity")
        U.log("dodge move: hold %s%s, fwd %d left %d, yaw %.0f from %s, speed %.0f u/s", key_names(keys),
            yours ~= 0 and (", let go of " .. key_names(yours)) or "", f, l, math.deg(yaw), yaw_src,
            v and sqrt(v.x * v.x + v.y * v.y) or -1)
    end
end

return E
