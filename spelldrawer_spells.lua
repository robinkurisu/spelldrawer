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
--   modifier      for dashes and leaps with no projectile: modifier name substring on the hero
--                 while the move is active; the hero himself is tracked instead of a projectile
--   motion        how the projectile (or hero) moves, which sets how it is predicted and drawn:
--                   "arc"  lobbed under gravity; draws the arc and the area where it lands
--                   "line" flies straight; draws its lane up to max range or the first wall it hits;
--                          a `modifier` dash follows the hero's current direction, so it can steer
--
-- "arc" only:
--   warning       particle substring whose CP0 marks the landing spot
--   radius_prop   ability property holding the landing area radius (falls back to 7 m)
--   gravity_scale multiplier on sv_gravity for the arc prediction; 0 for a straight dive
--
-- "line" only:
--   range_prop    ability property holding the max travel distance
--   range         max travel distance in meters when range_prop is missing
--   width         lane half-width in meters, drawn around the flight path
--   bullet        weapon name substring if the game fires it as a bullet (defaults to `ability`);
--                 Debug Mode logs your own bullets that match no spell, to find it
--   speed         projectile speed in units/s; a bullet's lane stays drawn for its flight time
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
}
