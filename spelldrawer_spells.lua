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
--                 hero while the move is active; the hero himself is tracked instead of a projectile
--   motion        how the projectile (or hero) moves, which sets how it is predicted and drawn:
--                   "arc"  lobbed under gravity; draws the arc and the area where it lands
--                   "line" flies straight; draws its lane up to max range or the first wall it hits;
--                          a `modifier` dash follows the hero's current direction, so it can steer
--                   "aura" a buff on the hero (needs `modifier`); draws a ring around him while on
--                   "cone" a melee cone in front of the hero (needs `aim` or `modifier`); draws a fan
--                          on the ground that turns with his aim, during the wind-up
--
-- "cone" only:
--   range_prop    ability property holding the cone's reach
--   range         reach in meters when range_prop is missing (default 5)
--   angle_prop    ability property holding the cone's full width in degrees
--   angle         full width in degrees when angle_prop is missing (default 60)
--
-- "aura" only:
--   radius_prop   ability property holding the ring radius
--   radius        ring radius in meters when radius_prop is missing (default 1.5)
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
        id = "bebop_hook",
        name = "Grapple Arm",
        hero = "Bebop",
        hero_image = "panorama/images/heroes/bebop_sm_psd.vtex_c",
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
        particles = { "punkgoat_bashdown_bat.vpcf", "punkgoat_sigil_ground.vpcf" },
        projectile = "punkgoat_bashdown_bat.vpcf",    -- m_BatChargingEffect: CP1 follows bat_fx_attach on Billy;
                                                      -- the .vpcf keeps it off _illum and _spikes
        follow_caster = true,                         -- the bat effect sits on Billy, so Billy himself is tracked
        motion = "arc",
        warning = "punkgoat_sigil_ground.vpcf",       -- m_GroundParticle: the sigil at the slam spot, before the
                                                      -- shockwave (ExplodeDelay 0.5 s); the .vpcf keeps it off its children
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
    },
}
