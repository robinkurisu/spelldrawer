-- Spell Drawer | Dispel Magic (upgrade_reduce_debuff_duration): "Purge all non-ultimate negative
-- effects currently applied to you. Cannot be used while Stunned or Slept." And Divine Barrier, cast
-- on yourself, when Dispel Magic isn't there or ready (U.DISPEL_ITEMS). Pressed by itself, by what
-- the debuffs on you add up to:
--   level 3  dispelled at once: silences (movement silences too: Slowing Hex), roots, disarms, tethers,
--            and marks that end in a stun or burst
--   level 2  2 points: burns, bleeds, heal cuts, resist shreds, the heavy slows
--   level 1  1 point: plain slows and small shreds
-- Below level 3 it waits for NEED points (two level 2s, a 2 and two 1s, four 1s), NEED_LOW at low
-- health. A debuff that stacks (`stacks`) counts only at its max stacks.
--
-- The debuffs are deadlock.wiki/Dispel_Magic's list (2026-11-15), named as the game names them on
-- you: "<ability>/<modifier path>", from abilities.vdata (GameTracking-Deadlock, 2026-11-11). Stuns,
-- sleeps, lifts and drags are left out: it can't be pressed through them. So are Chimera Mk1 and Stone
-- Form, whose only effect on you is one of those
-- shortcut: no name here was seen in a match; Debug Mode logs each "modifier on you", so a debuff
-- that is never dispelled can be checked against its row

local U = require("spelldrawer_util")
local menu = require("spelldrawer_menu")

local S, ui = U.state, menu.ui
local D = {}

local NEED, NEED_LOW = 4, 2 -- points of level 1 and 2 debuffs it waits for; at LOW_HEALTH or less
local LOW_HEALTH = 0.35     -- as the dodge's own low health
local SCAN_EVERY = 0.1      -- seconds between reads of your modifiers
local PRESS_EVERY = 0.5     -- seconds before it is pressed again, if the press didn't take
local MIN_LEFT = 0.25       -- a debuff with less than this left isn't worth it
local GRACE = 0.5           -- seconds the debuffs may stop calling for it without the wait starting over:
                            -- an area's debuff is put on you again and again, with gaps (Grasping Hands)
local REACT_MIN, REACT_MAX = 0.25, 0.8 -- seconds the debuffs have to call for it before it is pressed: picked
                                       -- anew between these for each dispel, so it isn't instant or always the same

-- ability -> { modifier, level, stacks }: the modifier is the end of its path under that ability;
-- `stacks`: counts only at max stacks, the modifier's own max if it reads, else this number
-- (true: no number known)
local DEBUFFS = {
    -- Abrams
    -- Shoulder Charge: its drag at level 3 on trial (you, 2026-11-15), as Luggage Cart's can be dispelled
    citadel_ability_bull_charge = { { "wall_slam_slow", 1 }, { "modifier_charge_drag_enemy", 3 } },
    -- Apollo
    ability_fencer_throwblade = { { "fencer_sigil_slow", 1 }, { "upgrade_greater_withering_whip_debuff", 3 } }, -- Disengaging Sigil
    ability_fencer_riposte = { { "modifier_fencer_riposte_attack_debuff", 2 }, { "modifier_fencer_riposte_immobilize", 3 } },
    -- Baba
    ability_baba_bubbling_brew = { { "modifier_baba_bubbling_brew_debuff", 1 }, { "modifier_baba_thread_pull", 2 } }, -- Threadsap
    ability_baba_hexing_brew = { { "modifier_baba_brew_fire", 2 }, { "modifier_baba_brew_silence", 3 } },             -- Baba's Brew
    -- Bebop
    citadel_ability_uppercut = { { "uppercut_debuff", 1 } },                          -- Exploding Uppercut
    citadel_ability_sticky_bomb = { { "modifier_citadel_sticky_bomb_attached", 3 } },
    ability_bebop_stickybomb2 = { { "slow", 1 } },
    citadel_ability_hook = { { "modifier_slow_bases", 3 }, { "modifier_bebop_hook_bullet_amp", 2 } }, -- Grapple Arm
    -- Billy
    ability_punkgoat_ult = { { "slow", 1 }, { "slam_firerate_slow", 1 } },            -- Bashdown
    ability_punkgoat_blasted = { { "blastedshred", 1 } },
    -- Calico
    ability_nano_clustergrenade = { { "modifier_nano_cluster_grenade_debuff", 1 } },  -- Gloom Bombs
    -- Celeste
    ability_unicorn_radiantblast = { { "unicorn_radiantblast_debuff", 2 } },          -- Light Eater
    ability_unicorn_prismaticguard = { { "modifier_unicorn_prismatic_guard_debuff", 3 } }, -- Dazzling Trick
    -- Deadman Danny
    ability_deadpack_flamethrower = { { "debuff", 1 }, { "resist_reduction", 2 } },   -- Jettison Fuel
    -- Drifter
    drifter_blood_blast = { { "debuff", 3 } },                                        -- Rend's silence
    drifter_shadow_mark = { { "modifier_drifter_shadow_mark_target", 2 } },           -- Stalker's Mark
    -- Dynamo
    citadel_ability_stomp = { { "debuff_modifier", 1 }, { "modifier_stomp_debuff", 2 } }, -- Kinetic Pulse
    -- Graves
    ability_necro_hauntingskull = { { "debuff", 2, true }, { "slow", 1 } },           -- Jar of Dead
    -- Grasping Hands: in a match (2026-11-15) its debuff and tether came on you with each grab, ~2 s apart,
    -- the tether read for ~0.1 s of each, and no "immobilize" was seen
    ability_necro_zombiewall = { { "debuff", 3 }, { "immobilize", 3 }, { "tether", 3 } },
    ability_necro_fear = { { "debuff", 2 } },                                         -- Essence Theft
    -- Grey Talon
    ability_power_jump = { { "modifier_slow_base", 1 } },                             -- Rain of Arrows
    ability_immobilize_trap = { { "modifier_glitch_debuff", 3 }, { "modifier_immobilize_trap_debuff", 3 } }, -- Spirit Snare
    -- Haze
    ability_sleep_dagger = { { "modifier_postsleep", 1 }, { "modifier_no_stam_recovery", 1 }, { "modifier_bullet_shred_postsleep", 2 } },
    ability_stacking_damage = { { "modifier_passive_haze_stacking_damage", 2, 40 }, { "slow", 1 } }, -- Fixation
    -- Holliday
    ability_explosive_barrel = { { "barrel_burn", 2 } },                              -- Powder Keg
    ability_crackshot = { { "slow", 1 }, { "bullet_resist_reduction", 2 } },
    -- Infernus
    ability_incendiary_projectile = { { "modifier_incendiary_debuff", 2 }, { "slow", 1 } }, -- Napalm
    ability_flame_dash = { { "modifier_flamedash_burn", 2 }, { "modifier_flamedash_debuff", 1 } },
    ability_afterburn = { { "modifier_afterburn_dot", 2 } },                          -- the burn, not its buildup
    -- Ivy
    citadel_ability_tengu_urn = { { "immobilize", 3 }, { "modifier_urn_debuff", 1 } }, -- Entangling Thorns
    -- Kelvin
    ability_ice_grenade = { { "kelvin_ice_grenade_slow", 1 }, { "chill", 1 } },       -- Frost Grenade
    ability_icebeam = { { "modifier_icebeam_stacking_slow", 2 } },                    -- Arctic Beam
    -- Lady Geist
    ability_life_drain = { { "modifier_life_drain", 2 }, { "modifier_life_drain_silence", 3 } },
    ability_blood_shards = { { "modifier_blood_shard_debuff", 2, 5 } },               -- Malice
    -- Lash
    citadel_ability_lash_down_strike = { { "modifier_slow_base", 1 } },               -- Ground Strike
    ability_lash_flog = { { "modifier_lash_flog_debuff", 1 } },
    -- McGinnis
    citadel_ability_fissure_wall = { { "slow", 1 }, { "modifier_bonus_damage_percent", 2 } }, -- Spectral Wall
    -- Mina
    ability_vampirebat_lovebites = { { "lovebites_proc", 2 }, { "slowsf", 1 } },      -- the proc, not its buildup
    -- Mirage
    mirage_fire_beetles = { { "modifier_mirage_fire_scarabs_health_loss", 2 } },      -- Fire Scarabs
    mirage_tornado = { { "slow", 1 } },                                               -- Dust Devil, once it drops you
    mirage_sand_phantom = { { "modifier_mirage_sand_phantom_passive_victim", 2, 4 }, { "mirage_djinns_mark_slow", 1 } }, -- Djinn's Mark
    -- Mo & Krill
    ability_intimidate = { { "modifier_intimidate_debuff", 2 } },                     -- Scorn
    ability_burrow = { { "modifier_slow", 1 } },
    ability_throw_sand = { { "modifier_citadel_throw_sand_debuff", 3 } },             -- Sand Blast's disarm
    -- Paige
    ability_bookworm_dragonfire = { { "groundaura_burn", 2 } },                       -- Bookwyrm
    ability_bookworm_aoemagic = { { "root", 3 }, { "slowmodifier", 1 }, { "debuff", 2 } }, -- Captivating Read
    -- Paradox
    citadel_ability_chrono_pulse_grenade = { { "modifier_chrono_pulse_grenade_debuff", 2 }, { "slow", 1 } },
    citadel_ability_chrono_time_wall = { { "modifier_citadel_silenced", 3 } },        -- the silence, not the time stop
    citadel_ability_chrono_kinetic_carbine = { { "modifier_chrono_kinetic_carbine_slow", 2 } },
    -- Pocket
    synth_barrage = { { "modifier_synth_barrage_debuff", 1 } },
    synth_pulse = { { "debuff", 1 } },                                                -- Enchanter's Satchel
    -- Rat King
    ability_ratking_scrap_grenade = { { "ratking_scrap_grenade_slow", 1 }, { "ratking_scrap_grenade_big_slow", 2 } },
    ability_ratking_ratnibble = { { "ratking_nibble_enemy", 2 }, { "ratking_nibble_enemy_linger", 1 } }, -- Rat Swarm
    -- Rem
    ability_familiar_ability02 = { { "slow", 1 } },                                   -- Pillow Toss
    -- Seven
    citadel_ability_lightning_ball = { { "gigagwatt_lightningball_slow", 1 } },
    citadel_ability_static_charge = { { "modifier_citadel_staticcharge", 3 } },       -- before its stun
    citadel_ability_static_charge_v2 = { { "modifier_citadel_staticcharge", 3 } },
    ability_power_surge = { { "modifier_power_surge_debuff", 1 } },
    -- Shiv
    citadel_ability_shiv_dagger = { { "modifier_shiv_thrown_shiv_damage_debuff", 2 }, { "modifier_shiv_thrown_shiv_slow_debuff", 1 } }, -- Serrated Knives
    citadel_ability_shiv_dash = { { "modifier_shiv_dash_debuff", 1 } },               -- Slice and Dice
    -- Silver
    ability_werewolf_kickflip = { { "disarm", 3 }, { "enemysuccess", 3 }, { "debuff", 1 } }, -- Boot Kick
    ability_werewolf_netshot = { { "debuff", 3 }, { "root", 3 }, { "bonusdebuff", 1 } },     -- Entangling Bola
    ability_werewolf_maulingleap = { { "shred", 2 } },
    ability_werewolf_cripplingslash = { { "debuff", 1 }, { "disarm", 3 }, { "slow", 1 } },   -- Tail Whack
    -- Sinclair
    ability_magician_magicbolt = { { "magician_magicbolt_debuff", 2 } },              -- Vexing Bolt
    -- Solomon
    ability_chessmaster_throwbishop = { { "stack", 2, true }, { "slow", 1 }, { "dimslow", 1 } }, -- Setup Bishop
    ability_chessmaster_forkpiece = { { "debuff", 1 }, { "slow", 1 }, { "hex", 3 } }, -- Rook Battery
    -- The Doorman
    ability_doorman_bomb = { { "slow_aura_modifier", 1 }, { "debuff", 2 } },          -- Call Bell
    -- Luggage Cart: its drag can be dispelled (you, 2026-11-15). It was on you 0.78 s: of 9, the 3 whose
    -- wait was drawn under 0.5 s were dispelled and the rest ran out first, so the wait ends early for
    -- a level 3 about to run out (`go_by`)
    ability_doorman_luggage_cart = { { "drag", 3 } },
    -- Venator
    ability_priest_flashbang = { { "burn", 2 } },                                     -- Consecrating Grenade
    ability_priest_beartrap = { { "debuff", 2 }, { "immobilize", 3 }, { "tether", 2 } }, -- Hex-Lined Snap Trap
    -- Victor
    ability_frank_shocktarget2 = { { "zap_slow", 1 }, { "shock", 2 } },               -- Pain Battery
    ability_frank_painaura = { { "painauradebuff", 2 } },                             -- Aura of Suffering
    -- Vindicta
    citadel_ability_hornet_chain = { { "modifier_citadel_disarmed", 3 }, { "modifier_citadel_hornet_chain_connection", 3 } }, -- Stake
    citadel_ability_hornet_sting = { { "modifier_citadel_hornet_sting_debuff", 2 } }, -- Crow Familiar
    -- Violet
    ability_artist_rollingprojectile = { { "slow", 1 }, { "debuff", 2 } },            -- Flow State
    ability_artist_tether = { { "buildup", 3 }, { "slow", 1 } },                      -- Still Life, before its stun
    -- Viscous
    viscous_goo_grenade = { { "modifier_viscous_goo_grenade_debuff", 1 }, { "puddle_slow", 1 } }, -- Splatter
    viscous_telepunch = { { "viscous_telepunch_movement_slow", 1 }, { "viscous_punch_roll_slow", 1 } },
    -- Vyper
    ability_viper_debuffdagger = { { "debuff", 2, 3 }, { "debuffdagger_debuff", 1 } }, -- Screwjab Dagger
    ability_viper_venom = { { "viper_venom_modifier_subclass", 3 } },                 -- Lethal Venom, before its burst
    -- Warden
    ability_warden_crowd_control = { { "slow", 1 }, { "modifier_warden_crowd_control_debuff", 2 } }, -- Alchemical Flask
    ability_warden_lock_down = { { "modifier_warden_lockdown_debuff", 3 }, { "modifier_citadel_root", 3 }, -- Binding Word
        { "modifier_citadel_silenced", 3 }, { "modifier_lockdown_bullet_resist", 2 } },
    -- Wraith
    citadel_ability_card_toss = { { "diamond_card_debuff", 2 }, { "club_debuff", 1 } }, -- Card Trick
    -- Yamato
    citadel_ability_power_slash = { { "slow", 1 } },
    citadel_ability_flying_strike = { { "slow", 1 } },
    citadel_ability_healing_slash = { { "debuff", 1 } },                              -- Crimson Slash

    -- weapon items
    upgrade_weapon_backstabber = { { "modifier_backstabber_debuff", 2 } },            -- Stalker
    upgrade_slowing_bullets = { { "slowing_bullets_debuff", 1 } },
    upgrade_tech_defense_shredders = { { "modifier_tech_defense_shredders_debuff", 1 } }, -- Spirit Shredder Bullets
    upgrade_headshot_booster2 = { { "modifier_headshot_damage_debuff", 1 } },         -- Weakening Headshot
    upgrade_hollow_point_rounds = { { "modifier_bullet_armor_shredder", 1 } },
    upgrade_close_quarter_combat = { { "modifier_slow_base", 1 } },                   -- Point Blank
    upgrade_spellslinger_headshots = { { "modifier_spellslinger_headshots_debuff", 2, 4 }, { "modifier_tech_defense_shredders_debuff", 1 } }, -- Spirit Rend
    upgrade_toxic_bullets = { { "modifier_item_bleeding_bullets_damageovertime", 2 } }, -- the bleed, not its buildup
    upgrade_capacitor = { { "modifier_weapon_capacitor_slow", 3 } },                 -- silences movement
    upgrade_banshee_slugs = { { "modifier_headshot_damage_debuff", 2 } },             -- Crippling Headshot
    upgrade_crushing_fists = { { "modifier_crushing_fists_debuff", 2, 6 } },
    upgrade_proc_silence = { { "modifier_citadel_silence_proc_debuff", 3 }, { "modifier_citadel_silenced", 3 }, -- Silencer
        { "modifier_citadel_silence_proc_tech_damage_reduction", 1 } },
    upgrade_silencer = { { "modifier_citadel_active_silenced", 3 } },
    -- vitality items
    upgrade_healbane = { { "modifier_healbane_debuff", 2 } },
    upgrade_boxing_glove = { { "modifier_slow_base", 1 } },                           -- Lifestrike
    upgrade_inhibitor = { { "debuff", 2 } },
    upgrade_siphon_bullets = { { "modifier_siphon_bullets_health_loss", 2 } },
    upgrade_phantom_strike = { { "modifier_slow_base", 3 }, { "modifier_citadel_pulldown_to_ground", 1 } }, -- its slow disarms
    -- spirit items
    upgrade_withering_whip = { { "modifier_withering_whip_debuff", 2 } },             -- Rusted Barrel
    upgrade_acolytes_glove = { { "modifier_acolytes_glove_debuff", 1 } },             -- Spirit Strike
    upgrade_bullet_resist_shredder = { { "modifier_bullet_armor_shredder", 1 } },
    upgrade_cold_front = { { "modifier_slow_base", 1 } },
    upgrade_magic_slow = { { "mystic_slow_debuff", 1 } },                             -- Mystic Slow
    upgrade_containment = { { "modifier_slow_base", 3 } },                            -- Slowing Hex: silences movement
    upgrade_spirit_sap = { { "modifier_spirit_sap_debuff", 2 } },
    upgrade_suppressor = { { "debuff_modifier", 1 } },
    upgrade_rupture = { { "modifier_rupture", 3 } },                                  -- Decay
    upgrade_greater_withering_whip = { { "upgrade_greater_withering_whip_debuff", 3 } }, -- Disarming Hex
    upgrade_target_stun = { { "modifier_citadel_delayed_stun", 3 } },                 -- Knockdown, before its stun
    upgrade_targeted_silence = { { "modifier_citadel_silenced", 3 } },                -- Silence Wave
    upgrade_spirit_snatch = { { "modifier_upgrade_spirit_snatch_debuff", 2 } },
    upgrade_arctic_blast = { { "modifier_slow_base", 2 } },                           -- the slow, not the freeze
    upgrade_escalating_exposure = { { "modifier_debuff", 2, 12 } },
    upgrade_focus_lens = { { "modifier_citadel_silenced", 3 }, { "modifier_focus_lens_damage", 2 }, { "modifier_spirit_sap_debuff", 2 } },
    upgrade_ultimate_burst = { { "modifier_ultimate_burst_delayed_effect", 3 }, { "slow_sf", 1 }, { "mystic_slow_debuff", 1 } }, -- Lightning Scroll
    upgrade_mystic_reverb = { { "modifier_mystic_reverb_explosion", 2 }, { "mystic_reverb_slow", 1 } },
    upgrade_spirit_burn = { { "modifier_spirit_burn_dot", 2 } },
    upgrade_aoe_root = { { "modifier_citadel_containment_victim", 3 }, { "modifier_slow_base", 3 } }, -- Vortex Web
}

-- debuffs the game names with no ability in front (modifiers.vdata)
local GLOBAL = {
    modifier_escalating_exposure_tech_armor_debuff = { "modifier_escalating_exposure_tech_armor_debuff", 1 }, -- Mystic Vulnerability
}

-- the row of a modifier named `name` (as the game names it on you), or nil; kept per name
local rows = {}
function D.find(name)
    local row = rows[name]
    if row ~= nil then return row or nil end
    local low = name:lower()
    row = GLOBAL[low]
    local key, rest = low:match("^([^/]+)/(.+)$")
    for _, r in ipairs(key and DEBUFFS[key] or {}) do
        if rest == r[1] or rest:sub(-#r[1] - 1) == "/" .. r[1] then row = { r[1], r[2], r[3], key = key } break end
    end
    rows[name] = row or false
    return row
end

-- whether a stacking debuff is at its max: `n` its stacks, `max` its own max (both as read, or nil),
-- `known` the table's (a number, or true for none known). Unreadable counts as not there yet
function D.maxed(n, max, known)
    local need = max and max > 1 and max or type(known) == "number" and known or nil
    return n ~= nil and need ~= nil and n >= need
end

-- whether to dispel `levels` (the level of each debuff on you): true and why, or false
function D.decide(levels, low_health)
    local points, top = 0, 0
    for _, l in ipairs(levels) do
        top = math.max(top, l)
        points = points + (l >= 2 and 2 or 1)
    end
    if top >= 3 then return true, "a level 3 debuff" end
    local need = low_health and NEED_LOW or NEED
    if points >= need then return true, ("%d points of %d"):format(points, need) end
    return false
end

local stack_logged = {}

-- the debuffs on you now: their levels, their names for the log, and the least time a level 3 has left
local function read()
    local levels, names, seen, short = {}, {}, {}, nil
    local mods = U.try(S.me, "get_modifiers")
    for _, m in ipairs(type(mods) == "table" and mods or {}) do
        local name = U.try(m, "get_name")
        local row = name and not seen[name] and D.find(name)
        -- your own hero's modifier of that name isn't a debuff (Haze's own Fixation watcher)
        if row and row.key and row.key:sub(1, 8) ~= "upgrade_" and U.find_ability(S.me, row.key) then row = nil end
        if row then
            local left = tonumber(U.try(m, "get_remaining_duration")) or 0 -- 0: no end, or not read
            local ok = left == 0 or left >= MIN_LEFT
            if ok and row[3] then
                local n, max = tonumber(U.field(m, "m_iStackCount")), tonumber(U.field(m, "m_iMaxStackCount"))
                ok = D.maxed(n, max, row[3])
                if ui.sp_debug:Get() and stack_logged[name] ~= n then
                    stack_logged[name] = n
                    U.log("dispel: %s at %s of %s stacks", name, tostring(n), tostring(max and max > 1 and max or row[3]))
                end
            end
            if ok then
                seen[name] = true
                if row[2] >= 3 and left > 0 and (not short or left < short) then short = left end
                levels[#levels + 1], names[#names + 1] = row[2], ("%s (%d, %.1f s left)"):format(name, row[2], left)
            end
        end
    end
    return levels, names, short
end

local scanned_at, pressed_at, go, go_why, held_logged = -math.huge, -math.huge, false, nil, nil
local go_since, go_last -- S.now the debuffs first called for it, and last did
local react = REACT_MIN -- this dispel's wait
local low_hp = false -- the last read had you at low health
local go_by -- S.now a level 3 debuff is about to run out: pressed by then, the wait up or not (never under REACT_MIN)
local told, told_at -- what Debug Mode last said of a dispel held back, and when: said once a second at most
-- (said once for good, 4 Luggage Carts of 14 went by with no line to say why, 2026-11-15)

-- The first of U.DISPEL_ITEMS you own, with its picture on in the Debuff Removal row (one that
-- doesn't read counts as on), that is ready: the item and its row. With none ready, nil and the
-- name of the first you own, or nil with none owned
local function pick()
    local owned
    for _, it in ipairs(U.DISPEL_ITEMS) do
        local item = U.try(ui.sp_dispel, "Get", it.name) ~= false and U.find_ability(S.me, it.key)
        if item then
            owned = owned or it.name
            local okr, ready = pcall(HERO_LIB.is_ability_ready, item)
            if okr and ready == true then return item, it end
        end
    end
    return nil, owned
end

-- on_createmove: presses a debuff removal item when the debuffs on you call for it
function D.steer(cmd)
    if not S.me then return end
    -- abs: curtime restarts on each map
    if math.abs(S.now - scanned_at) >= SCAN_EVERY then
        scanned_at, go = S.now, false
        local item, owned = pick()
        if not (item or owned) then return end
        local levels, names, short = read()
        if #levels == 0 then return end
        local okh, hp = pcall(HERO_LIB.get_health_percent, S.me)
        hp = okh and tonumber(hp) or nil
        if hp and hp > 1 then hp = hp / 100 end -- as the dodge reads it
        low_hp = hp ~= nil and hp <= LOW_HEALTH
        go, go_why = D.decide(levels, low_hp)
        local on = table.concat(names, ", ")
        local same = on:gsub(", [%d.]+ s left", "") -- without the times: said once, not every read
        if not go and ui.sp_debug:Get() and same ~= held_logged then U.log("dispel: held, not enough yet: %s", on) end
        held_logged = same
        go_by = short and S.now + short - MIN_LEFT - SCAN_EVERY or nil -- a read before it would stop counting
        if go then
            go_why = go_why .. ": " .. on
            if not item then
                go = false
                if ui.sp_debug:Get() and (told ~= "cd" .. same or math.abs(S.now - told_at) > 1) then
                    U.log("dispel: wanted, but %s isn't ready, %s", owned, go_why)
                    told, told_at = "cd" .. same, S.now
                end
            end
        end
    end
    if not go then
        if go_last and math.abs(S.now - go_last) > GRACE then go_since, go_last = nil, nil end
        return
    end
    if not go_since then go_since, react = S.now, REACT_MIN + math.random() * (REACT_MAX - REACT_MIN) end
    go_last = S.now
    -- abs: curtime restarts on each map
    local waited = math.abs(S.now - go_since)
    local last_call = go_by ~= nil and S.now >= go_by and waited >= REACT_MIN
    if waited < react and not last_call or math.abs(S.now - pressed_at) < PRESS_EVERY then return end
    -- "Cannot be used while Stunned or Slept": the press would be lost
    local st = EModifierState
    if st and U.try(S.me, "has_any_modifier_state", st.MODIFIER_STATE_STUNNED, st.MODIFIER_STATE_IS_ASLEEP) == true then
        if ui.sp_debug:Get() and told ~= go_since then U.log("dispel: wanted, but you are stunned or asleep, %s", go_why) end
        told = go_since
        return
    end
    local item, it = pick()
    if not item then return end
    -- read again: the last read is up to SCAN_EVERY old, and a Luggage Cart drag that ended 0.05 s
    -- before (at a wall) was still pressed on, for nothing (2026-11-15)
    if not D.decide(read(), low_hp) then go = false return end
    pressed_at, go, go_since, go_last = S.now, false, nil, nil
    HERO_LIB.cast_ability(cmd, S.me, item, it.self) -- `self`: the alternate cast, on yourself
    if ui.sp_debug:Get() then U.log("dispel: " .. it.name .. " pressed after %.2f s%s, %s", waited, waited < react and " (a level 3 was running out)" or "", go_why) end
end

return D
