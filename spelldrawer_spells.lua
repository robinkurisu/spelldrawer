-- Spell Drawer | spell registry. Add a spell by adding an entry here.
--
-- Each entry owns:
--   id            unique menu id
--   name          display name
--   ability       runtime ability name for cast detection
--   classes       class / vdata class substrings for the spell entity
--   particles     particle name substrings spawned by the spell
--   skip          particle name substrings to ignore (previews etc.)
--   landing       predict and draw where the spell lands
--   projectile    particle substring on the flying projectile entity
--   warning       particle substring whose CP0 marks the landing spot
--   radius_prop   ability property holding the area radius
--   gravity_scale multiplier on sv_gravity for the arc prediction
--
-- Only particles and entities matched by an enabled entry are drawn.

return {
    {
        id = "ghost_blood_bomb",
        name = "Lady Geist: Blood Bomb",
        image = "panorama/images/hud/abilities/spectre/blood_bomb_psd.vtex_c",
        ability = "ability_blood_bomb",
        classes = { "blood_bomb" },
        particles = { "ghost_blood_bomb" },
        landing = true,
        projectile = "ghost_blood_bomb_projectile",
        warning = "ghost_blood_bomb_warning",
        skip = { "ghost_blood_bomb_preview" },
        radius_prop = "Radius",
        gravity_scale = 1.0,
    },
}
