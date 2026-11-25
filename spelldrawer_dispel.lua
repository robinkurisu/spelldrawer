-- Spell Drawer | Dispel Magic (upgrade_reduce_debuff_duration): "Purge all non-ultimate negative
-- effects currently applied to you. Cannot be used while Stunned or Slept." And Divine Barrier, cast
-- on yourself when Dispel Magic isn't there or ready, or on an ally (U.DISPEL_ITEMS). Pressed by
-- itself, by what the debuffs on you, or on him, add up to:
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
local LOW_HEALTH = 0.5      -- the dodge's own low health is 35%
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

-- how dangerous a hero's debuffs (their `levels`) are, to pick between allies: the worst level
-- first, then their points
function D.score(levels)
    local points, top = 0, 0
    for _, l in ipairs(levels) do
        top = math.max(top, l)
        points = points + (l >= 2 and 2 or 1)
    end
    return top * 100 + points
end

local stack_logged = {}

-- the debuffs on `ent` (you, or an ally) now: their levels, their names for the log, and the least
-- time a level 3 has left
local function read(ent)
    local levels, names, seen, short = {}, {}, {}, nil
    local mods = U.try(ent, "get_modifiers")
    for _, m in ipairs(type(mods) == "table" and mods or {}) do
        local name = U.try(m, "get_name")
        local row = name and not seen[name] and D.find(name)
        -- a hero's own modifier of that name isn't a debuff (Haze's own Fixation watcher)
        if row and row.key and row.key:sub(1, 8) ~= "upgrade_" and U.find_ability(ent, row.key) then row = nil end
        if row then
            local left = tonumber(U.try(m, "get_remaining_duration")) or 0 -- 0: no end, or not read
            local ok = left == 0 or left >= MIN_LEFT
            if ok and row[3] then
                local n, max = tonumber(U.field(m, "m_iStackCount")), tonumber(U.field(m, "m_iMaxStackCount"))
                ok = D.maxed(n, max, row[3])
                if ent == S.me and ui.sp_debug:Get() and stack_logged[name] ~= n then -- yours only: allies' would flood it
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

-- `ent`'s health as a share, 0 to 1, or nil
local function health(ent)
    local okh, hp = pcall(HERO_LIB.get_health_percent, ent)
    hp = okh and tonumber(hp) or nil
    if hp and hp > 1 then hp = hp / 100 end -- as the dodge reads it
    return hp
end

local scanned_at, held_logged = -math.huge, nil
local ally_item_logged -- Debug Mode: whether an item for allies was last said to be ready
-- Two dispels can be under way at once, each with its own wait: yours (ME) and an ally's (ALLY), when
-- one item is ready for you and another for him (Dispel Magic and Divine Barrier). Of each:
--   go      the debuffs call for it, as of the last read         why   those debuffs, for the log
--   since   S.now they first did; last: S.now they last did      react this dispel's wait
--   by      S.now a level 3 debuff is about to run out: pressed by then, the wait up or not (never
--           under REACT_MIN)
--   low     the last read had the hero at low health              ent, h  ALLY's hero and his handle
--   pressed_at  S.now it was last pressed
local ME, ALLY = { go = false, pressed_at = -math.huge }, { go = false, pressed_at = -math.huge }
local told, told_at -- what Debug Mode last said of a dispel held back, and when: said once a second at most
-- (said once for good, 4 Luggage Carts of 14 went by with no line to say why, 2026-11-15)

-- The first of U.DISPEL_ITEMS you own, with its picture on in the Debuff Removal row (one that
-- doesn't read counts as on), that is ready: the item and its row; with `for_ally`, only one that
-- can be cast on someone else (`self` rows); never the row `skip`. With none ready, nil and the
-- name of the first you own, or nil with none owned
local function pick(for_ally, skip)
    local owned
    for _, it in ipairs(U.DISPEL_ITEMS) do
        local item = it ~= skip and (it.self or not for_ally) and U.try(ui.sp_dispel, "Get", it.name) ~= false
            and U.find_ability(S.me, it.key)
        if item then
            owned = owned or it.name
            local okr, ready = pcall(HERO_LIB.is_ability_ready, item)
            if okr and ready == true then return item, it end
        end
    end
    return nil, owned
end

-- The allies Divine Barrier can be cast on: within its Cast Range 40 m (5% short of it), inside the
-- Dodge Arc of where your camera faces (360: all round; it is aimed silently), and in your sight
-- shortcut: the range Greater Expansion adds isn't used
local ALLY_RANGE = 40 * 0.95 * U.CFG.UNITS_PER_M

-- no wall between your eyes and an ally's chest. Not U.in_sight, which is for enemies: 4 allies in
-- range and in the arc all read "not in sight" with it (2026-11-15)
local function clear_to(ent)
    local a, b = U.try(S.me, "get_origin"), U.try(ent, "get_origin")
    if not (a and b) then return false end
    local tr = U.trace_line(Vector(a.x, a.y, a.z + U.CFG.HEAD), Vector(b.x, b.y, b.z + U.CFG.BODY_Z), nil, true)
    local f = tr and U.field(tr, "fraction")
    return type(f) ~= "number" or f >= 0.99
end
local allies_logged, ally_logged = nil, {}
local function allies()
    local out, me_h = {}, U.handle(S.me)
    local fov = ui.sp_fov and ui.sp_fov:Get()
    local heroes, mine, near, arc = 0, 0, 0, 0 -- Debug Mode: how many pass each test, said when it changes
    for _, u in ipairs(U.units()) do
        if u.kind == "hero" and u.h ~= me_h then
            heroes = heroes + 1
            if u.mine then
                mine = mine + 1
                local d = U.dist_to_me(U.try(u.e, "get_origin"))
                if d and d <= ALLY_RANGE then
                    near = near + 1
                    if not fov or fov >= 360 or U.in_view(u.e, fov) then
                        arc = arc + 1
                        if clear_to(u.e) then out[#out + 1] = u.e end
                    end
                end
            end
        end
    end
    local said = ("%d other heroes, %d on your team, %d within 38 m, %d in the Dodge Arc, %d in sight"):format(heroes, mine, near, arc, #out)
    if ui.sp_debug:Get() and said ~= allies_logged then U.log("dispel: allies: %s", said) end
    allies_logged = said
    return out
end

-- An item pressed at an ally only brings up its targeting cone: in a replay (2026-11-15) the cone came
-- up and nothing was cast, 2 of 2. So it is confirmed with left clicks, as Dynamo's Quantum
-- Entanglement is (evade.lua): aimed at him on through CONFIRM, until its buff is on him (`buff`, in
-- its modifier's name), a click on every other command until the cast is taken
local CONFIRM = 0.4
local CLICK_FOR = 0.15 -- its buff came 0.26-0.34 s after the press, 9 of 9: less its 0.2 s cast delay, taken by 0.14 s
local CLICK_KEY = InputBitMask_t and InputBitMask_t.IN_ATTACK or 1
local confirm -- { ally, item key, name, buff, at, n }: the cast being confirmed

-- the silent aim at an ally's chest (the command looks there, your camera doesn't); `on_aimed` runs
-- when the aim is on him. Gives the aim's status, or nil with no ally to aim at
local function aim_at(cmd, ally, item, on_aimed)
    local o = U.try(ally, "get_origin")
    if not o then return nil end
    return cmd:aim({ aim_pos = Vector(o.x, o.y, o.z + U.CFG.BODY_Z), target_ent = ally, ability_ent = item,
        aim_type = aim and aim.type.SILENT or 2, on_aimed_callback = on_aimed })
end

-- whether `ally` wears a modifier with `buff` in its name
local function wears(ally, buff)
    local mods = U.try(ally, "get_modifiers")
    for _, m in ipairs(type(mods) == "table" and mods or {}) do
        local n = U.try(m, "get_name")
        if n and n:find(buff, 1, true) then return true end
    end
    return false
end

-- whether the cast being confirmed still is: clicks while it is
local function confirming(cmd)
    local c = confirm
    if not c then return false end
    local item = U.valid(c.ally) and U.find_ability(S.me, c.key)
    -- a buff he wore before the press (`had`: another's item, or his own) tells nothing: it read as
    -- landed at once, no click was sent and nothing was cast. Then the cast delay or CONFIRM ends it
    local landed = item and not c.had and wears(c.ally, c.buff) or false
    -- abs: curtime restarts on each map
    if not item or landed or math.abs(S.now - c.at) > CONFIRM then
        confirm = nil
        if ui.sp_debug:Get() then
            U.log("dispel: %s %s, %d click(s) in %.2f s, cast delay seen %s", c.name,
                landed and "is on the ally" or "did not go on the ally", (c.n + 1) // 2, -- a click on every other aimed command
                math.abs(S.now - c.at), c.taken and ("%.2f s after the press"):format(c.taken) or "never")
        end
        return false
    end
    -- Clicked only until the cast is taken (the item goes into its 0.2 s cast delay), and CLICK_FOR at
    -- most: clicked until its buff showed, a click after the cast fired your gun at the ally, once in
    -- 5 casts twice over, 0.24 s after the press (2026-11-15). "Selected" didn't tell: it read true
    -- all the way (7-8 clicks a cast). The aim stays on him meanwhile
    local okd, delay = pcall(HERO_LIB.is_ability_in_cast_delay, item)
    if okd and delay == true and not c.taken then c.taken = math.abs(S.now - c.at) end
    local clicking = not c.taken and math.abs(S.now - c.at) <= CLICK_FOR
    aim_at(cmd, c.ally, item, function()
        if not clicking then return end
        c.n = c.n + 1
        if c.n % 2 == 1 then cmd:press(CLICK_KEY) end -- held this command only: a fresh click each time
    end)
    return true
end

-- the last read's verdict for a track: `best` { ent, why, short, low }, or nil for none
local function set(t, best)
    if not best then t.go = false return end
    local h = best.ent and U.handle(best.ent) or nil
    if h ~= t.h then t.since, t.last = nil, nil end -- another hero: his own wait
    t.go, t.why, t.ent, t.h, t.low = true, best.why, best.ent, h, best.low
    t.by = best.short and S.now + best.short - MIN_LEFT - SCAN_EVERY or nil -- a read before it would stop counting
end

-- reads you, and your allies with an item ready for them, and sets ME and ALLY
local function scan()
    ME.go, ALLY.go = false, false
    local item, it = pick()
    if not (item or it) then return end -- none owned
    local mine
    local levels, names, short = read(S.me)
    -- abs: curtime restarts on each map. Just pressed for you: its purge may not show yet
    if #levels > 0 and math.abs(S.now - ME.pressed_at) >= PRESS_EVERY then
        local hp = health(S.me)
        local low = hp ~= nil and hp <= LOW_HEALTH
        local ok, why = D.decide(levels, low)
        local on = table.concat(names, ", ")
        local same = on:gsub(", [%d.]+ s left", "") -- without the times: said once, not every read
        if not ok and ui.sp_debug:Get() and same ~= held_logged then U.log("dispel: held, not enough yet: %s", on) end
        held_logged = same
        if ok and item then
            mine = { why = why .. ": " .. on, short = short, low = low }
        elseif ok and ui.sp_debug:Get() and (told ~= "cd" .. same or math.abs(S.now - told_at) > 1) then
            U.log("dispel: wanted, but %s isn't ready, %s: %s", it, why, on)
            told, told_at = "cd" .. same, S.now
        end
    end
    -- Allies, by the same levels, only with an item ready that can be cast on them: theirs aren't
    -- read otherwise. You come first (you, 2026-11-15: a Luggage Cart that takes you and an ally is
    -- yours): the item your own debuffs call for is kept for you, so an ally is looked at only with
    -- another ready for him (Dispel Magic on you, Divine Barrier on him, both under way at once).
    -- Among allies, the one with the most dangerous debuffs comes first (D.score); of two alike, the
    -- one lower on health
    local for_ally = pick(true, mine and it or nil)
    if ui.sp_debug:Get() and (for_ally ~= nil) ~= ally_item_logged then
        ally_item_logged = for_ally ~= nil
        U.log("dispel: an item to cast on allies is %s", for_ally and "ready: reading their debuffs" or "not ready: allies not read")
    end
    local best
    for _, a in ipairs(for_ally and allies() or {}) do
        local al, an, ashort = read(a)
        if ui.sp_debug:Get() then -- each ally's debuffs, said when they change
            local h, on = U.handle(a) or 0, table.concat(an, ", "):gsub(", [%d.]+ s left", "")
            if ally_logged[h] ~= on then
                ally_logged[h] = on
                U.log("dispel: ally %s has %s", tostring(h), on ~= "" and on or "no debuffs it knows")
            end
        end
        local score = #al > 0 and D.score(al)
        local hp = score and (health(a) or 1)
        if score and (not best or score > best.score or score == best.score and hp < best.hp) then
            local low = hp <= LOW_HEALTH
            local ok, why = D.decide(al, low)
            if ok then
                best = { ent = a, score = score, hp = hp, short = ashort, low = low,
                         why = ("%s, on an ally at %d%% health: %s"):format(why, math.floor(hp * 100 + 0.5), table.concat(an, ", ")) }
            end
        end
    end
    set(ME, mine)
    set(ALLY, best)
end

-- whether a track's wait is up: how long it waited and a note for the log, or nil
local function due(t)
    -- abs: curtime restarts on each map
    if not t.go then
        if t.last and math.abs(S.now - t.last) > GRACE then t.since, t.last = nil, nil end
        return nil
    end
    if not t.since then t.since, t.react = S.now, REACT_MIN + math.random() * (REACT_MAX - REACT_MIN) end
    t.last = S.now
    local waited = math.abs(S.now - t.since)
    local last_call = t.by ~= nil and S.now >= t.by and waited >= REACT_MIN
    if waited < t.react and not last_call or math.abs(S.now - t.pressed_at) < PRESS_EVERY then return nil end
    return waited, waited < t.react and " (a level 3 was running out)" or ""
end

-- on_createmove: presses a debuff removal item when the debuffs on you, or on an ally, call for it
function D.steer(cmd)
    if not S.me then return end
    if confirming(cmd) then return end
    -- abs: curtime restarts on each map
    if math.abs(S.now - scanned_at) >= SCAN_EVERY then
        scanned_at = S.now
        scan()
    end
    local waited, early = due(ME)
    local a_waited, a_early = due(ALLY)
    if not (waited or a_waited) then return end
    -- "Cannot be used while Stunned or Slept": the press would be lost
    local st = EModifierState
    if st and U.try(S.me, "has_any_modifier_state", st.MODIFIER_STATE_STUNNED, st.MODIFIER_STATE_IS_ASLEEP) == true then
        local since = ME.since or ALLY.since
        if ui.sp_debug:Get() and told ~= since then
            U.log("dispel: wanted, but you are stunned or asleep, %s", waited and ME.why or ALLY.why)
        end
        told = since
        return
    end
    if waited then
        local item, it = pick()
        if not item then return end
        -- read again: the last read is up to SCAN_EVERY old, and a Luggage Cart drag that ended 0.05 s
        -- before (at a wall) was still pressed on, for nothing (2026-11-15)
        if not D.decide(read(S.me), ME.low) then ME.go = false return end
        ME.pressed_at, ME.go, ME.since, ME.last = S.now, false, nil, nil
        HERO_LIB.cast_ability(cmd, S.me, item, it.self) -- `self`: the alternate cast, on yourself
        if ui.sp_debug:Get() then U.log("dispel: %s pressed after %.2f s%s, %s", it.name, waited, early, ME.why) end
        return -- one press a command: an ally's is next
    end
    -- An ally's, never before yours: while yours is still waiting, his waits too
    if ME.go then return end
    local item, it = pick(true)
    if not item then return end
    local ally, why = ALLY.ent, ALLY.why
    if not U.valid(ally) or not D.decide(read(ally), ALLY.low) then ALLY.go = false return end
    -- Aimed at him every command until the aim is on him, then pressed plainly and confirmed with
    -- clicks (`confirming`): it goes to whom you aim at
    -- shortcut: with another ally near that line the game may pick him; not seen in a match
    local status = aim_at(cmd, ally, item, function()
        if math.abs(S.now - ALLY.pressed_at) < PRESS_EVERY then return end
        ALLY.pressed_at, ALLY.go, ALLY.since, ALLY.last = S.now, false, nil, nil
        HERO_LIB.cast_ability(cmd, S.me, item)
        confirm = { ally = ally, key = it.key, name = it.name, buff = it.buff, at = S.now, n = 0, had = wears(ally, it.buff) }
        if ui.sp_debug:Get() then U.log("dispel: %s pressed at an ally after %.2f s%s, %s", it.name, a_waited, a_early, why) end
    end)
    if not status then ALLY.go = false return end
    if ui.sp_debug:Get() and told ~= "aim" .. tostring(status) .. tostring(ALLY.since) then
        told = "aim" .. tostring(status) .. tostring(ALLY.since)
        U.log("dispel: aiming %s at an ally, aim status %s", it.name, tostring(status))
    end
end

return D
