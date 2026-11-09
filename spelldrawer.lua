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

local MODULES = { "spelldrawer_util", "spelldrawer_spells", "spelldrawer_menu", "spelldrawer_detect", "spelldrawer_draw",
                  "spelldrawer_evade", "spelldrawer_sim" }
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

local S, ui = U.state, menu.ui
local valid, try, log = U.valid, U.try, U.log

callback.on_frame:set(function()
    S.now = global_vars.curtime()
    -- curtime restarts on each map; drop timers keyed to the old clock
    if S.now < S.prev_now then S.next_scan, S.last_log = 0, 0 end
    S.prev_now = S.now
    local lp = entity_list.local_pawn()
    S.me = (valid(lp) and try(lp, "is_alive") == true) and lp or nil
    if ui.sp_enable:Get() and S.me and HERO_LIB then
        local ok, err = pcall(detect.scan)
        if not ok then log("scan error: %s", err) end
        ok, err = pcall(detect.track_modifiers)
        if not ok then log("modifier error: %s", err) end
        ok, err = pcall(detect.track_projectiles, global_vars.absoluteframetime())
        if not ok then log("trajectory error: %s", err) end
        ok, err = pcall(sim.update)
        if not ok then log("sim error: %s", err) end
        ok, err = pcall(evade.update)
        if not ok then log("dodge error: %s", err) end
    else
        S.list = {}
        S.events = {}
        S.dodge, S.sims = nil, {}
        if ui.sp_debug:Get() and S.now - S.last_log > 1 then
            S.last_log = S.now
            log("not scanning: enabled=%s local_pawn_alive=%s hero_lib=%s",
                tostring(ui.sp_enable:Get()), tostring(S.me ~= nil), tostring(HERO_LIB ~= nil))
        end
    end
end)

callback.on_draw:set(function()
    S.zones = {} -- the drawing below fills it again; the dodge plans on it next frame
    if not ui.sp_enable:Get() or not HERO_LIB then return end
    local lp = S.me
    if not valid(lp) then return end
    for _, rec in pairs(S.list) do draw.report(pcall(draw.draw_entity, rec, lp)) end
    for _, rec in ipairs(S.sims) do draw.report(pcall(draw.draw_sim, rec)) end
    if S.dodge and ui.sp_dodge_debug:Get() then draw.report(pcall(draw.draw_dodge, S.dodge)) end
end)

callback.on_createmove:set(function(cmd)
    if not ui.sp_enable:Get() or not HERO_LIB then return end
    local ok, err = pcall(evade.steer, cmd)
    if not ok then log("dodge error: %s", err) end
end)

-- same guard as the callbacks below: the detect code calls HERO_LIB, and off means off
local function guarded(fn)
    return function(d)
        if not ui.sp_enable:Get() or not HERO_LIB then return end
        local ok, err = pcall(fn, d)
        if not ok then log("particle error: %s", err) end
    end
end
callback.on_particle_create:set(guarded(detect.track_particle))
callback.on_particle_update:set(guarded(detect.update_particle))
callback.on_particle_update_transform:set(guarded(detect.update_particle))
callback.on_particle_destroy:set(guarded(detect.destroy_particle))
callback.on_add_modifier:set(function(mod, target)
    if not ui.sp_enable:Get() or not HERO_LIB then return end
    local ok, err = pcall(detect.track_modifier_add, mod, target)
    if not ok then log("modifier error: %s", err) end
end)
callback.on_bullet_create:set(function(d)
    if not ui.sp_enable:Get() or not HERO_LIB then return end
    local ok, err = pcall(detect.track_bullet, d)
    if not ok then log("bullet error: %s", err) end
end)
if callback.on_animation_start then -- Debug Mode only: logs enemy heroes' animation clips
    callback.on_animation_start:set(function(ent, clip)
        if not ui.sp_enable:Get() or not HERO_LIB then return end
        local ok, err = pcall(detect.track_animation, ent, clip)
        if not ok then log("animation error: %s", err) end
    end)
end

log("loaded with %d registered spell(s)", #SPELLS)
