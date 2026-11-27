-- Spell Drawer | draws known spell particles and spell entities in the world
--
-- Entry point: loads the modules and wires the game callbacks.
--   spelldrawer_spells.lua  spell registry (add new spells here)
--   spelldrawer_util.lua    config, shared state, safe-access helpers
--   spelldrawer_menu.lua    menu controls
--   spelldrawer_detect.lua  detection, particle tracking, landing prediction
--   spelldrawer_draw.lua    world-space drawing
--   spelldrawer_evade.lua   dodge: safe-spot search, path and move input
--   spelldrawer_sim.lua     spell simulator: casts registry spells at you to test the dodge
--   spelldrawer_dispel.lua  Dispel Magic: the debuffs it removes, and when it is pressed

-- bump for each release; build_bytecode.py names the build after it, and auto update compares it
local VERSION = "1.5.0"
local MODULES = { "spelldrawer_util", "spelldrawer_spells", "spelldrawer_menu", "spelldrawer_detect", "spelldrawer_draw",
                  "spelldrawer_evade", "spelldrawer_sim", "spelldrawer_dispel" }
-- require caches modules; without this a script reload would keep the old code and menu handles
for _, name in ipairs(MODULES) do package.loaded[name] = nil end

local U = require("spelldrawer_util")
local SPELLS = require("spelldrawer_spells")
local menu = require("spelldrawer_menu")
menu.build(SPELLS)
local detect = require("spelldrawer_detect")
local draw = require("spelldrawer_draw")
local evade = require("spelldrawer_evade")
local sim = require("spelldrawer_sim")
local dispel = require("spelldrawer_dispel")

local S, ui = U.state, menu.ui
local valid, try, log = U.valid, U.try, U.log

-- Profile (menu): the time each part takes, summed and logged every PROFILE_EVERY of real time.
-- Works with Debug Mode off, whose own logging costs frames
local clock = U.clock
local PROFILE_EVERY = 5
local profiling, prof, prof_t0, prof_frames = false, {}, nil, 0

local function prof_add(name, dt)
    local p = prof[name]
    if not p then p = { name = name, n = 0, sum = 0, max = 0 } prof[name] = p end
    p.n, p.sum, p.max = p.n + 1, p.sum + dt, math.max(p.max, dt)
end

-- pcall, timed under `name` while Profile is on
local function timed(name, fn, ...)
    if not profiling then return pcall(fn, ...) end
    local t0 = clock()
    local ok, err = pcall(fn, ...)
    prof_add(name, clock() - t0)
    return ok, err
end

-- once a frame: reads the switch (the callbacks don't, each call) and logs when the time is up
local function prof_frame()
    local on = clock ~= nil and ui.sp_profile ~= nil and ui.sp_profile:Get() == true
    if on ~= profiling then profiling, prof, prof_t0, prof_frames = on, {}, on and clock() or nil, 0 end
    S.prof_add = on and prof_add or nil -- for the steps a module times itself (the scan's)
    if not on then return end
    prof_frames = prof_frames + 1
    local el = clock() - prof_t0
    if el < PROFILE_EVERY then return end
    local rows, out = {}, {}
    for _, p in pairs(prof) do rows[#rows + 1] = p end
    table.sort(rows, function(a, b) return a.sum > b.sum end)
    for i, p in ipairs(rows) do
        out[i] = ("%s %.2f ms/frame (max %.2f ms, %d calls)"):format(p.name, p.sum * 1000 / prof_frames, p.max * 1000, p.n)
    end
    log("profile, %d frames in %.1f s (%.0f fps): %s", prof_frames, el, prof_frames / el, table.concat(out, "; "))
    prof, prof_t0, prof_frames = {}, clock(), 0
end

local update_tick -- auto update's check every UPDATE_EVERY, set at the end of this file (shipped build only)

callback.on_frame:set(function()
    prof_frame()
    if update_tick then update_tick() end
    U.tick(global_vars.curtime())
    local lp = entity_list.local_pawn()
    S.me = (valid(lp) and try(lp, "is_alive") == true) and lp or nil
    if ui.sp_enable:Get() and S.me and HERO_LIB then
        local ok, err = timed("scan", detect.scan)
        if not ok then log("scan error: %s", err) end
        ok, err = timed("modifiers", detect.track_modifiers)
        if not ok then log("modifier error: %s", err) end
        ok, err = timed("projectiles", detect.track_projectiles, global_vars.absoluteframetime())
        if not ok then log("trajectory error: %s", err) end
        ok, err = timed("sim", sim.update)
        if not ok then log("sim error: %s", err) end
        ok, err = timed("dodge", evade.update)
        if not ok then log("dodge error: %s", err) end
        ok, err = timed("guardian probe", detect.probe_guardians) -- Debug Mode only
        if not ok then log("guardian probe error: %s", err) end
    else
        S.list = {}
        S.events = {}
        S.dodge, S.sims = nil, {}
    end
end)

callback.on_draw:set(function()
    S.zones = {} -- the drawing below fills it again; the dodge plans on it next frame
    draw.report(pcall(menu.draw_changelog)) -- before the returns: the menu is open outside a match too
    if not ui.sp_enable:Get() or not HERO_LIB then return end
    local lp = S.me
    if not valid(lp) then return end
    local t0 = profiling and clock()
    for _, rec in pairs(S.list) do draw.report(pcall(draw.draw_entity, rec, lp)) end
    for _, rec in ipairs(S.sims) do draw.report(pcall(draw.draw_sim, rec)) end
    if S.dodge and ui.sp_dodge_debug:Get() then draw.report(pcall(draw.draw_dodge, S.dodge)) end
    if t0 then prof_add("draw", clock() - t0) end
end)

callback.on_createmove:set(function(cmd)
    if not ui.sp_enable:Get() or not HERO_LIB then return end
    local ok, err = timed("steer", evade.steer, cmd)
    if not ok then log("dodge error: %s", err) end
    ok, err = timed("dispel", dispel.steer, cmd)
    if not ok then log("dispel error: %s", err) end
end)

-- same guard as the callbacks below: the detect code calls HERO_LIB, and off means off
local function guarded(name, fn)
    return function(d)
        if not ui.sp_enable:Get() or not HERO_LIB then return end
        local ok, err = timed(name, fn, d)
        if not ok then log("particle error: %s", err) end
    end
end
callback.on_particle_create:set(guarded("particle create", detect.track_particle))
callback.on_particle_update:set(guarded("particle update", detect.update_particle))
callback.on_particle_update_transform:set(guarded("particle update", detect.update_particle))
callback.on_particle_destroy:set(guarded("particle destroy", detect.destroy_particle))
callback.on_add_modifier:set(function(mod, target)
    if not ui.sp_enable:Get() or not HERO_LIB then return end
    local ok, err = timed("modifier add", detect.track_modifier_add, mod, target)
    if not ok then log("modifier error: %s", err) end
end)
callback.on_bullet_create:set(function(d)
    if not ui.sp_enable:Get() or not HERO_LIB then return end
    local ok, err = timed("bullet", detect.track_bullet, d)
    if not ok then log("bullet error: %s", err) end
end)
if callback.on_start_sound then -- a guardian's melee wind-up, for Auto Parry; Debug Mode logs its sounds
    callback.on_start_sound:set(guarded("sound", detect.track_sound))
end
if callback.on_animation_start then -- a wind-up's clip (`charge_anim`); Debug Mode logs enemy heroes' clips
    callback.on_animation_start:set(function(ent, clip)
        if not ui.sp_enable:Get() or not HERO_LIB then return end
        local ok, err = timed("animation", detect.track_animation, ent, clip)
        if not ok then log("animation error: %s", err) end
    end)
end

log("v%s loaded with %d registered spell(s)", VERSION, #SPELLS)

-- Auto update, the shipped bytecode only (build_bytecode.py flips SHIPPED; the sources never
-- overwrite themselves). version.txt is "<version> <bytes of evade.lua>", both written to release/
-- by build_bytecode.py and read from this repo's main branch: pushing them ships them. A newer
-- evade.lua replaces this file and a notification asks for a reload: reloading by itself stalls
-- the game (see notify_stale in the evade module).
-- Read from GitHub, not the FTP server 1.5.0 and older update from: only a push here ships code.
-- Checked as the script loads, then every UPDATE_EVERY of real time while frames run
local SHIPPED = false
local UPDATE_URL = "https://raw.githubusercontent.com/robinkurisu/spelldrawer/main/release/"
local UPDATE_EVERY = 15 * 60
if SHIPPED and http and io then
    -- this folder, from the path `require` searches: Umbrella's folder in AppData is named
    -- differently on every machine (probed 2026-11-17: package.path holds <it>\deadlock_scripts\?.lua)
    local dir = package.path:match("([^;]*deadlock_scripts[/\\])%?%.lua")
    if not dir then log("update: no deadlock_scripts in package.path, not checked: %s", package.path) end
    local have = VERSION -- the version in the file on disk: a later check doesn't download it again
    local function check() http.request(UPDATE_URL .. "version.txt"):send(function(_, body, ok)
        local ver, size = (body or ""):match("^([%d.]+) (%d+)")
        if not ok or not ver or not U.newer(ver, have) then return end
        http.request(UPDATE_URL .. "evade.lua"):timeout(60):send(function(_, code, got)
            -- a cut-off or mangled download must never replace a script that works
            if not got or #code ~= tonumber(size) or code:sub(1, 4) ~= "\27Lua" then
                return log("update: v%s downloaded wrong (%d bytes, %s expected); kept v%s", ver, #(code or ""), size, VERSION)
            end
            -- shortcut: written in place, not to a temp file and renamed; a crash mid-write leaves a broken file, reinstall by hand then
            local f, err = io.open(dir .. "evade.lua", "wb")
            if not f then return log("update: can't write %sevade.lua: %s", dir, tostring(err)) end
            f:write(code)
            f:close()
            have = ver
            log("update: v%s written over v%s; reload the scripts", ver, VERSION)
            if Notification then
                pcall(Notification, { primary_text = "Evade updated to v" .. ver .. ".",
                    secondary_text = "Reload scripts to use it.", duration = 10,
                    -- the game's own warning icon, as notify_stale's badge (evade module): known to draw
                    primary_image = "panorama/images/hud/icon_warning_png.vtex_c" })
            end
        end)
    end) end
    if dir then
        check()
        local checked = clock and clock()
        update_tick = checked and function()
            if clock() - checked < UPDATE_EVERY then return end
            checked = clock()
            check()
        end or nil
    end
end
