-- Spell Drawer | spell registry. Add a spell by adding an entry here.
--
-- Each entry owns:
--   id            unique id
--   name          ability display name, also its id in the hero's menu
--   hero          hero name; spells with the same hero share one menu row
--   hero_image    image on the hero's menu row (only the first entry per hero is used)
--   image         ability icon, clicked in the hero's menu to toggle the spell
--   ability       runtime ability name substring, for cast detection and ability properties
--   classes       class / vdata class substrings for the spell entity
--   particles     particle name substrings spawned by the spell
--   skip          particle name substrings to ignore (previews etc.)
--   projectile    particle substring on the flying projectile; it is tracked to predict the path
--   modifier      for dashes, leaps and buffs with no projectile: modifier name substring on the
--                 hero while the move is active; the hero himself is tracked instead of a projectile.
--                 It is read every frame on the heroes that own the ability, not only on the scan,
--                 because a dash can be shorter than one (0.15 s against 0.25 s); a pawn without
--                 the ability in that slot is an on-hit victim and does not match, and so is a
--                 hero whose own spell reuses the same modifier name
--   motion        how the projectile (or hero) moves, which sets how it is predicted and drawn:
--                   "arc"  lobbed under gravity; draws the arc and the area where it lands. Needs
--                          something to follow: `projectile`, `warning`, or `modifier`/a
--                          `follow_caster` projectile that makes the hero himself the projectile
--                   "line" flies straight; draws its lane up to max range or the first wall it hits;
--                          a `modifier` dash follows the hero's current direction, so it can steer
--                   "aura" a buff on the hero (needs `modifier`); draws a ring around him while on
--                   "cone" a melee cone in front of the hero (needs `aim`, `modifier` or
--                          `cone_particle`); draws a fan on the ground that turns with his aim,
--                          while the swing is up
--
-- "cone" only:
--   range_prop    ability property holding the cone's reach
--   range         reach in meters when range_prop is missing (default 5)
--   angle_prop    ability property holding the cone's full width in degrees
--   angle         full width in degrees when angle_prop is missing (default 60)
--   cone_particle particle substring the swing spawns on the hero; it starts the fan where the
--                 ability has neither a cast delay nor a wind-up modifier (an instant melee)
--   cone_delay    seconds after cone_particle before the fan is drawn (default 0), for a swing
--                 whose reach lands later than the particle that starts it
--
-- "aura" only:
--   radius_prop   ability property holding the ring radius
--   radius        ring radius in meters when radius_prop is missing (default 1.5)
--   show_last     for a delayed effect: draw only the last this many seconds of the modifier's
--                 duration, read from duration_prop (seconds) or `duration` when that is missing.
--                 The drawn tail runs CFG.TAIL_GRACE (0.15 s) past that, so it still shows when
--                 the effect fires: detection only sees a modifier every 0.25 s, and a tail cut
--                 at the effect itself can end that long early
--   show_first    for an effect that lands on cast and again later: draw its first this many
--                 seconds too, so both ends show and the middle of the wait stays clean
--
-- "arc" only:
--   warning       particle substring whose CP0 marks the landing spot
--   radius_prop   ability property holding the landing area radius (falls back to 7 m)
--   gravity_scale multiplier on sv_gravity for the arc prediction; 0 for a straight dive, which
--                 marks the ground straight below until the projectile heads down
--   follow_caster true when the `projectile` particle sits on the casting hero: the hero is tracked
--
-- "line" only:
--   range_prop    ability property holding the max travel distance
--   range         max travel distance in meters when range_prop is missing
--   width         lane half-width in meters, drawn around the flight path
--   dash_particle particle substring the dash spawns on the hero; it starts the track on him the
--                 instant he moves, which a scan can miss entirely on a short dash
--   radius_prop   ability property holding the radius of the area the move ends in (a slash where
--                 it lands); drawn centred on the end of the lane
--   land_offset   meters past that end the area sits, for a radius vdata measures from the move's
--                 own reach rather than from a projectile (SlashForwardOffset)
--   bullet        weapon name substring if the game fires it as a bullet (defaults to `ability`);
--                 Debug Mode logs your own bullets that match no spell, to find it
--   speed         projectile speed in units/s; a bullet's lane stays drawn for its flight time
--   min_speed     a hero's dash lane (`modifier`): only drawn while he moves faster than this, in m/s;
--                 for a modifier that lasts longer than the dash itself
--   height        a hero's dash lane (`modifier` or `aim`): box height above his feet in meters
--                 (default 2.5); the box also reaches 0.5 m under his feet
--   aim           true for a wind-up: drawn while the ability is in its cast delay or channel
--                 (or while `modifier` is on), pointing where the hero aims (up and down too)
--
-- Only particles and entities matched by an enabled entry are drawn.

return {
    {
        id = "ghost_blood_bomb",
        name = "Blood Bomb",
        hero = "Lady Geist",
        hero_image = "panorama/images/heroes/spectre_sm_psd.vtex_c",
        image = "panorama/images/hud/abilities/spectre/blood_bomb_psd.vtex_c",
        ability = "ability_blood_bomb",
        classes = { "blood_bomb" },
        particles = { "ghost_blood_bomb" },
        projectile = "ghost_blood_bomb_projectile",
        motion = "arc",
        warning = "ghost_blood_bomb_warning",
        skip = { "ghost_blood_bomb_preview" },
        radius_prop = "Radius",
        gravity_scale = 1.0,
    },
    {
        id = "ghost_malice",
        name = "Malice",
        hero = "Lady Geist",
        image = "panorama/images/hud/abilities/spectre/geist_dagger_psd.vtex_c",
        ability = "ability_blood_shards",
        classes = { "blood_shard_dagger" },
        particles = { "ghost_blood_shard_dagger.vpcf" },
        projectile = "ghost_blood_shard_dagger.vpcf",
        motion = "line",
        skip = {
            "ghost_blood_shard_dagger_impact",
            "ghost_blood_shard_dagger_debuff",
            "ghost_blood_shard_dagger_self_dmg",
        },
        -- 3500 u/s muzzle speed * 3 s bullet lifetime / 39.37 u per meter
        range = 266.7,
        speed = 3500,
        width = 0.75,
    },

    {
        id = "abrams_shoulder_charge",
        name = "Shoulder Charge",
        hero = "Abrams",
        hero_image = "panorama/images/heroes/bull_sm_psd.vtex_c",
        image = "panorama/images/hud/abilities/bull_charge_psd.vtex_c",
        ability = "citadel_ability_bull_charge",
        modifier = "modifier_citadel_bull_charging", -- on Abrams while he charges
        motion = "line",
        -- no distance property: 1.4 s duration at the ramp's average speed
        -- (18.75 -> 30 m/s) is about 34 m
        range = 34,
        width = 2.2, -- ChargeRadius
    },
    {
        id = "abrams_seismic_impact",
        name = "Seismic Impact",
        hero = "Abrams",
        image = "panorama/images/hud/abilities/bull_jump_psd.vtex_c",
        ability = "citadel_ability_bull_leap",
        modifier = "modifier_citadel_bull_leap_boosting_crash", -- on Abrams during the dive only
        motion = "arc",
        radius_prop = "ImpactRadius", -- impact radius; falls back to 7 m
        gravity_scale = 0,            -- the slam is a straight dive, not a lob
    },

    -- Apollo is hero_fencer internally (heroes.vdata, build 6860)
    {
        id = "apollo_sword_charge",
        name = "Flawless Advance",
        hero = "Apollo",
        hero_image = "panorama/images/heroes/fencer_sm_psd.vtex_c",
        image = "panorama/images/hud/abilities/fencer/fencer_lungingstab_psd.vtex_c",
        ability = "ability_fencer_lunge",
        -- Apollo himself is tracked, like Abrams' charge. No modifier covers just the lunge
        -- (m_DashBuffModifier needs an upgrade), so the recast-window modifier is used, and
        -- `min_speed` keeps the lane to the moments he actually moves at dash speed.
        modifier = "uirecast",                        -- m_UIRecastModifier._my_subclass_name (_class modifier_base),
                                                      -- on Apollo during the recast window. Same name as
                                                      -- ability_fencer_throwblade's m_UIRecastModifier, so it
                                                      -- also shows for Disengaging Sigil's recast window
        min_speed = 20,                               -- m/s, between his movement and the lunge (hero_fencer):
                                                      --   run EMaxMoveSpeed 7.2 + ESprintSpeed 1.6 = 8.8 m/s
                                                      --   stamina dash 10 m / 0.68 s = 14.7 (air 8 / 0.47 = 17.0)
                                                      --   lunge DashSpeed 1100 u/s / 39.37 = 27.9 m/s
                                                      --   (AttackingDashSpeed 2200 / 39.37 = 55.9)
        particles = { "fencer_lunge_dash.vpcf" },     -- m_DashTrailEffect: only speeds up detection
        motion = "line",
        range_prop = "SlashLength",                   -- strike range, 13 m in vdata
        range = 13,
        width = 1.6,                                  -- SlashRadius
    },
    {
        id = "apollo_ultimate",
        name = "Itani Lo Sahn",
        hero = "Apollo",
        image = "panorama/images/hud/abilities/fencer/fencer_ult_psd.vtex_c",
        ability = "ability_fencer_ultimate",
        modifier = "fencer_ult_cast_delay",           -- m_AutoCastDelayModifier: on Apollo for the 1.5 s
                                                      -- wind-up (AbilityCastDelay)
        aim = true,                                   -- also covers the hold-to-delay channel after it
        motion = "line",
        range_prop = "DashRange",                     -- 27 m in vdata, +8 m with the first upgrade
        range = 27,
        width = 7, -- dash radius
        height = 7.5,
    },

    -- Bebop is hero_bebop internally (heroes.vdata, build 6860)
    {
        id = "bebop_exploding_uppercut",
        name = "Exploding Uppercut",
        hero = "Bebop",
        hero_image = "panorama/images/heroes/bebop_sm_psd.vtex_c",
        image = "panorama/images/hud/abilities/bebop/bebop_uppercut_psd.vtex_c", -- m_strAbilityImage
        ability = "citadel_ability_uppercut",          -- hero_bebop ESlot_Signature_1 (heroes.vdata:27463)
        -- Instant cast (m_eAbilityActivation CITADEL_ABILITY_ACTIVATION_INSTANT_CAST, abilities.vdata:34453),
        -- AbilityCastDelay 0 (:34525), AbilityChannelTime 0 (:34532), and no modifier on Bebop: the
        -- ability's modifiers are m_UppercutModifier on the victim and m_BuffModifier/m_ClipModifier
        -- once it lands. So `aim` never arms and the swing particle is the only signal there is.
        particles = { "bebop_uppercut_activate.vpcf" }, -- m_UppercutAttackData.m_MeleeActivateParticle (:34991):
                                                        -- the .vpcf keeps it off the _light/_model/_smoke/
                                                        -- _streak children, the _impact and _perk effects
        cone_particle = "bebop_uppercut_activate.vpcf",
        -- The wind-up lives in that particle's children, not in a cast delay: bebop_uppercut_swing_arc.vpcf
        -- (the arc the fist draws) has m_flDelay 0.2 and the light 0.25 (bebop_uppercut_activate.vpcf:222,
        -- :202; model, ground and smoke 0.2). The attack data agrees: m_MovementSpeedCurve
        -- (abilities.vdata:34930) drops to 0 speed at 0.456761 of its 0.6 s domain (:34989), so the lunge
        -- stops and the punch lands around 0.27 s after the cast.
        cone_delay = 0.2,
        motion = "cone",
        range_prop = "MeleeAttackLength",              -- 6 m (:34469), scales with melee range (EMeleeRange)
        range = 6,
        angle = 120,                                   -- MeleeHalfAngle 60 (:34465) is a HALF angle and
                                                       -- angle_prop is read as the full width: 2 * 60
    },
    {
        id = "bebop_hook",
        name = "Grapple Arm",
        hero = "Bebop",
        image = "panorama/images/hud/abilities/bebop/bebop_hook_psd.vtex_c",
        ability = "citadel_ability_hook",
        -- The hook flies as a bullet (m_mapWeaponInfos.primary), not an entity, so there are no `classes`:
        -- on_bullet_create matches it by `ability`, and its tracer particle is followed like Malice's.
        particles = { "bebop_hook_bullet.vpcf" },     -- m_szBulletTravelTracerParticle
        projectile = "bebop_hook_bullet.vpcf",        -- the .vpcf keeps it off bebop_hook_bullet_chain.vpcf
        skip = {
            "bebop_hook_bullet_chain",                -- m_szBulletLinkParticle: the chain rope
            "bebop_hook.vpcf",                        -- m_HookOutParticle: hook model and chain children
            "bebop_hook_precast",                     -- m_PrecastHookParticle: during the 0.1 s cast delay
            "bebop_hook_retrieve",                    -- m_HookRetrieveParticle and m_LinkEffect (_chain): the pull
        },
        motion = "line",
        range_prop = "AbilityCastRange",              -- 30 m in vdata, +30 m with the second upgrade
        range = 30,
        width = 0.84,                                 -- m_flBulletRadius 33 u / 39.37 = 0.84 m
        speed = 2850,                                 -- m_flBulletSpeed u/s; 2850 * 3 s lifetime / 39.37 = 217 m,
                                                      -- so AbilityCastRange is what stops it
    },

    -- Billy is hero_punkgoat internally (heroes.vdata, build 6860)
    {
        id = "billy_bashdown",
        name = "Bashdown",
        hero = "Billy",
        hero_image = "panorama/images/heroes/punkgoat_sm_psd.vtex_c",
        image = "panorama/images/hud/abilities/punkgoat/goat_sigilslam_psd.vtex_c",
        ability = "ability_punkgoat_ult",
        -- No modifier sits on Billy during the hop and slam (the block's modifiers all go on enemies
        -- or the ground sigil, and server.dll has only modifier_punkgoat_sigil_aura for it), so the
        -- bat effect on him is followed instead, like Flawless Advance's dash trail.
        -- punkgoat_sigil_ground.vpcf (m_GroundParticle) is left out: it only spawns once the slam has
        -- landed, so it would draw a second marker after the fact
        particles = { "punkgoat_bashdown_bat.vpcf" },
        projectile = "punkgoat_bashdown_bat.vpcf",    -- m_BatChargingEffect: CP1 follows bat_fx_attach on Billy;
                                                      -- the .vpcf keeps it off _illum and _spikes
        follow_caster = true,                         -- the bat effect sits on Billy, so Billy himself is tracked
        motion = "arc",
        radius_prop = "AbilityCastRange",             -- 4 m slam radius in vdata, +2 m with the second upgrade
                                                      -- (WaveEndRadius 8 m is the later shockwave)
        gravity_scale = 0,                            -- a driven dive, not a fall: m_TimeToReachGroundByHeight lands
                                                      -- 448 u in 0.22 s and 1000 u in 0.2 s
    },
    {
        id = "billy_rising_ram",
        name = "Rising Ram",
        hero = "Billy",
        image = "panorama/images/hud/abilities/punkgoat/goat_risingram_psd.vtex_c",
        ability = "ability_punkgoat_goatflip",
        modifier = "charge",                          -- m_Charging._my_subclass_name (_class modifier_citadel_goat_charging):
                                                      -- on Billy while he rams
        -- "charge" is also a substring of about 20 other modifiers (modifier_melee_charge from the
        -- melee-charge items, modifier_charge_drag_enemy on Abrams', Lash's, Tengu's and Bashdown's
        -- victims, modifier_shoulder_charge_buff, ...), so min_speed keeps the lane to dash speed:
        min_speed = 25,                               -- m/s, under the ram's ChargeSpeed 1200 u/s / 39.37 = 30.5 m/s
        motion = "line",
        -- no distance property: AbilityDuration 0.3 s * ChargeSpeed 1200 u/s / 39.37 = 9.1 m; the
        -- speed curve reaches full speed by 3% of the charge, so about 9 m (+0.4 s with the second
        -- upgrade: 0.7 * 1200 / 39.37 = 21 m)
        range = 9,
        width = 2.54,                                 -- ChargeRadius (ChargeMultiHitRadius 1.5 m is the hit range)
    },
    {
        id = "billy_chain_gang",
        name = "Chain Gang",
        hero = "Billy",
        image = "panorama/images/hud/abilities/punkgoat/goat_chaingang_psd.vtex_c",
        ability = "ability_punkgoat_tether",
        -- Instant cast that chains every enemy hero in range to Billy (punkgoat_tether_projectile),
        -- then yanks them in after AbilityDuration 2.8 s: drawn as a ring around him meanwhile.
        modifier = "waiting_for_pull",                -- m_WaitingToPullModifier._my_subclass_name (_class
                                                      -- modifier_punkgoat_tether_waiting): on Billy until the pull
        motion = "aura",
        radius_prop = "AbilityCastRange",             -- 12 m grab radius in vdata, +5 m with the third upgrade
        radius = 12,
        duration_prop = "AbilityDuration",            -- 2.8 s until the pull
        duration = 2.8,
        show_last = 1,                                -- only the last second before the pull is drawn
    },

    -- Calico is hero_nano internally (citadel_gc_hero_names_english.txt: "hero_nano:n" "Calico";
    -- heroes.vdata hero_nano.m_mapBoundAbilities). His slots are ability_nano_clustergrenade,
    -- _nano_dash, _nano_catform and _nano_shadow_pulse (build 6860).
    {
        id = "calico_gloom_bombs",
        name = "Gloom Bombs",
        hero = "Calico",
        hero_image = "panorama/images/heroes/nano_sm_psd.vtex_c",
        image = "panorama/images/hud/abilities/nano/nano_clustergrenade_psd.vtex_c",
        ability = "ability_nano_clustergrenade",
        -- A thrown grenade entity (m_mapProjectileInfos.primary). Its vdata class is the shared
        -- citadel_projectile, so the particle is what identifies it and `classes` names the
        -- ability class instead (server.dll registers citadel_ability_nano_clustergrenade).
        classes = { "citadel_ability_nano_clustergrenade" },
        particles = { "nano_cluster_grenade.vpcf" },   -- m_mapProjectileInfos.primary.m_particle
        projectile = "nano_cluster_grenade.vpcf",      -- the .vpcf suffix keeps it off its variants
        motion = "line",
        skip = {
            "nano_cluster_grenade_explosion",          -- m_ExplodeParticle and its child parts
            "nano_cluster_grenade_model",
            "nano_cluster_grenade_arming",             -- arming pulse and rays on a stuck bomb
            "nano_cluster_grenade_backdrop",
            "nano_cluster_grenade_trail",              -- trail and _erode, spawned by the bomb itself
            "nano_cat_bomb",                           -- m_ExplodeEnemyParticle / _FriendlyParticle
            "nano_cat_detonation",                     -- m_ExplodeBaseParticle
            "armor_suppressor",                        -- m_DebuffModifier.m_strParticleEffect, on victims
        },
        -- 2500 u/s m_flSpeed * 0.75 s Lifetime / 39.37 u per meter. Kept as a straight lane like
        -- Malice's, though vdata gives it m_flGravityScale 1.0 and m_flUpSpeed 200 and lets it
        -- bounce and stick (m_flFriction 3.0, PBF_StickToTarget | PBF_StickToWorld); the TossSpeed
        -- 400 property is the toss and is not what the projectile flies at
        range = 47.6,
        speed = 2500,
        width = 0.05,                                 -- m_flPhysicsRadius 2.0 u / 39.37
    },
    {
        id = "calico_leaping_slash",
        name = "Leaping Slash",
        hero = "Calico",
        image = "panorama/images/hud/abilities/nano/nano_dash_psd.vtex_c",
        ability = "ability_nano_dash",
        -- A targeted dash: AbilityCastRange 9 m at DashSpeed 2400 u/s is 0.147 s of flight, and
        -- AbilityCastDelay 0.1 s is under a scan on its own, so the 0.25 s scan steps over it.
        -- m_DashLineEffect starts the track the moment he moves and the modifier poll carries it
        -- while he does. m_DashModifier is modifier_citadel_shiv_dash, Shiv's dash class reused
        -- whole (same _my_subclass_name) and hidden: he has to own ability_nano_dash for it, so a
        -- Shiv dash doesn't fill this entry. He is the projectile, not a lob, so it is a lane and
        -- the slash circle sits where the lane ends.
        dash_particle = "nano_dash_instant.vpcf",     -- m_DashLineEffect, on him for the dash
        modifier = "modifier_citadel_shiv_dash",
        motion = "line",
        range_prop = "AbilityCastRange",              -- 9 m to the target, where he stops
        range = 9,
        width = 2.0,                                  -- DashRadius 2.0 m, the dash's own reach
        radius_prop = "SlashRadius",                  -- 4 m slash circle
        land_offset = 1.5,                            -- SlashForwardOffset 1.5 m: the slash lands
                                                      -- this far in front of him, not at his feet
    },
    {
        id = "calico_return_to_shadows",
        name = "Return to Shadows",
        hero = "Calico",
        image = "panorama/images/hud/abilities/nano/nano_shadow_pulse_psd.vtex_c",
        ability = "ability_nano_shadow_pulse",
        classes = { "shadow_pulse" },                 -- the ability's own class (server.dll)
        -- Channeled ultimate: he turns to shadows for AbilityChannelTime 3 s, burning every enemy
        -- in Radius on the way in and again on the way out. m_AutoChannelModifier._my_subclass_name
        -- (_class modifier_base) sits on him for the channel. That name is shared with Familiar's
        -- two channels and Werewolf's unload, so `aim`, which checks Calico's own channel, matches too.
        modifier = "channeling",
        aim = true,
        motion = "aura",
        radius_prop = "Radius",                       -- 7.5 m burst around him, same on both hits
        duration_prop = "AbilityChannelTime",         -- 3 s until he returns
        duration = 3,
        show_first = 0.5,                             -- the burst on cast
        show_last = 1,                                -- and the burst when he comes back
    },

    -- Celeste is hero_unicorn internally (citadel_gc_hero_names_english.txt "hero_unicorn:n" "Celeste";
    -- heroes.vdata hero_unicorn.m_mapBoundAbilities), build 6860
    {
        id = "celeste_light_eater",
        name = "Light Eater",
        hero = "Celeste",
        hero_image = "panorama/images/heroes/unicorn_sm_psd.vtex_c",
        image = "panorama/images/hud/abilities/unicorn/unicorn_flare_psd.vtex_c",
        ability = "ability_unicorn_radiantblast",
        particles = { "unicorn_radiant_blast.vpcf" }, -- m_CastParticle; the .vpcf keeps it off the _beam_pnt child
        skip = {
            "unicorn_radiant_blast_impact",           -- m_HitParticle, also the debuff's m_DamageFX
            "unicorn_radiant_blast_debuff",           -- m_DebuffModifier.m_strParticleEffect: on the victims
        },
        motion = "cone",
        -- INSTANT_CAST, targeting shape CONE, AbilityCastDelay 0.3 s: the fan is drawn for that wind-up.
        -- No modifier sits on Celeste, so `aim` is the trigger.
        aim = true,
        range_prop = "AbilityCastRange",              -- 10 m in vdata, +3 m with the second upgrade
        range = 10,
        angle_prop = "TargetingConeAngle",            -- 70 deg in vdata. m_flHitConeAngleExtra 30 deg widens hit
                                                      -- detection only; ExtraSweepRadius 2 m reaches past the fan
        angle = 70,
    },
    {
        id = "celeste_radiant_daggers",
        name = "Radiant Daggers",
        hero = "Celeste",
        image = "panorama/images/hud/abilities/unicorn/unicorn_luminousflux_psd.vtex_c",
        ability = "ability_unicorn_luminousstrike",
        -- Ground-targeted circle (LOCATION_GROUND, SHAPE_CIRCLE): a beam falls from ClimbHeight 50 m and
        -- explodes after PreExplosionDuration 1.4 s. The beam is a world-origin particle at the target,
        -- so nothing flies to follow; the game's own tell (m_TellParticle) marks the blast area instead.
        particles = { "unicorn_daggers_target.vpcf" },
        warning = "unicorn_daggers_target.vpcf",      -- its CP0 is the impact point
        motion = "arc",
        radius_prop = "ExplosionRadius",              -- 8 m blast radius in vdata
        gravity_scale = 0,                            -- the beam drives straight down, no lob
        skip = {
            "unicorn_daggers_target_dagger",          -- the daggers falling in the beam
            "unicorn_daggers_target_enemy_aoe_model", -- the ring model on the ground
        },
    },
    {
        id = "celeste_shining_wonder",
        name = "Shining Wonder",
        hero = "Celeste",
        image = "panorama/images/hud/abilities/unicorn/unicorn_orb_psd.vtex_c",
        ability = "ability_unicorn_dazzlingorb",
        -- The orb flies as a bullet (m_mapWeaponInfos.primary, m_flBulletSpeed 2000) and homes, so there
        -- are no `classes`: on_bullet_create matches it by `ability` and its tracer is followed like
        -- Malice's knife or the hook.
        particles = { "unicorn_ball_projectile.vpcf" }, -- m_szBulletTravelTracerParticle
        projectile = "unicorn_ball_projectile.vpcf",    -- the .vpcf keeps it off the _core and _trail children
        skip = {
            "unicorn_ball_charge",                      -- m_ChargeParticle: on Celeste while charging
            "unicorn_ball_impact",                      -- m_OrbWatcherModifier.m_ExplodeParticle
            "unicorn_ball_hover",                       -- m_GraceParticle: the linger when nothing is in range
            "unicorn_ball_bounce",                      -- m_BounceParticle
            "unicorn_ball_next_target_debuff",          -- m_NextTargetModifier.m_NextTargetParticle: on the target
        },
        motion = "line",
        range_prop = "BounceRadius",                    -- 15 m seek radius in vdata: the orb only flies to a target
                                                        -- inside it (MaxBounces 8, +6 with the third upgrade, is
                                                        -- beyond what one lane can show)
        range = 15,
        width = 1.65,                                   -- m_flBulletRadius 65 u / 39.37 u per meter
        speed = 1175,                                   -- m_OrbWatcherModifier.m_ProjectileSpeedCurve tops out at 1175 u/s;
                                                        -- m_flBulletSpeed 2000 is the weapon-info base it ramps from
    },
}
