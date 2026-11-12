-- Spell Drawer | spell registry. Add a spell by adding an entry here.
--
-- Each entry owns:
--   id            unique id
--   name          ability display name, also its id in the hero's menu
--   hero          hero name; spells with the same hero share one menu row
--   hero_image    image on the hero's menu row (only the first entry per hero is used)
--   hero_id       the hero's m_HeroID in heroes.vdata, on his first entry like hero_image; a
--                 particle or entity that names no owner belongs to the one hero with this id
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
--                   "target" cast at one hero, not at a spot: draws a line from the caster to you
--                          and a ring on you while it is aimed at you, timed to the hit. No spot
--                          is out of it, so Evade only parries it (Counterspell)
--                   "wall" a line laid on the ground (Grasping Hands): drawn where its ground
--                          particles are (control point 0), neighbour to neighbour, `width` each side.
--                          Not drawn with fewer than 3 or longer than `wall_max` m. No hit time: a
--                          danger while it is up, never walked across
--
-- "target" only:
--   particles     the caster's own tell through the cast (what starts it, as for any spell)
--   target_particles  particle substrings only the target's client makes (a screen effect): seen,
--                 it is aimed at you whatever the caster's aim reads as, and it starts the spell
--                 itself, timed from it, on the hero playing the spell's hero
--   range_prop    ability property holding the cast range; `range` in meters when it is missing
--   angle         full width in degrees of the cone in front of the caster that the target is
--                 picked in (default 90): you are the target if you stand in range and in it
--                 through the cast delay
--   hit_delay     seconds from the tell to the hit (the cast delay, plus a charge's time)
--   speed         units/s of the projectile that then flies to you, if any: its flight is added
--   mark_modifier modifier substring (lower case) the spell puts on you while you are its target
--                 (Chain Gang's chain): you are the target while you wear it, whatever the caster's
--                 aim and range say, and no longer once it is gone. The tell is then the caster's
--                 `modifier`, or, with none, the mark itself as it comes on you (Death Slam's lock-on);
--                 that one holds you as its target until the hit, mark or not
--
-- "cone" only:
--   range_prop    ability property holding the cone's reach
--   range         reach in meters when range_prop is missing (default 5)
--   angle_prop    ability property holding the cone's full width in degrees
--   angle         full width in degrees when angle_prop is missing (default 60)
--   base          meters a side the cone is already wide at the hero (Sand Blast's wave): its sides,
--                 `angle` apart, then meet behind him, and it is drawn and dodged from him on
--   sweep_from    seconds into the cast the drawn sweep leaves the hero (default 0): it is at the
--                 cone's end as it hits
--   charge_width  "line": half-width in meters of the wind-up's lane (`charge_anim`), where one cast
--                 sends several shots abreast (Rallying Charge); each shot's own lane keeps `width`
--   flat          "line": true for a flyer that burns the ground under it (Bookwyrm): its lane runs
--                 level along the floor below it, whatever its own height and climb
--   warning_cp    control point number of the `warning` particle that marks the area (default: its first)
--   cone_particle particle substring the swing spawns on the hero; it starts the fan where the
--                 ability has neither a cast delay nor a wind-up modifier (an instant melee)
--   cone_time     seconds after the trigger when the fan ends (default: when the trigger is gone),
--                 for a particle that lingers past the moment the spell goes off
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
--   dash_range_prop  for a dash drawn as an aura: ability property holding how far it goes; also
--                 draws the whole dash as a lane as wide as the ring, from where it began
--   dash_range    that distance in meters when dash_range_prop is missing
--   dash_speed    the dash's speed in units/s (vdata DashSpeed): when its lane reaches you
--   land_offset   meters past the dash's end that the slash ring is centred (SlashForwardOffset)
--   prepare       for a ring shown well before it goes off (`show_last`): with Circles unticked in
--                 Block Movement, Evade leaves it be until this many seconds before it does
--   lingers       false when a ring timed by `release` is over once it goes off (a blast), not still
--                 there after it as Singularity's pull is: the parry then goes at Parry Lead
--   big_area      true for a ring too big to walk out of while its hero follows you (Concussive
--                 Combustion): with its shape unticked in Block Movement, Evade never walks or dashes
--                 you out of it, and only Counterspell answers its hit, while you stand in it
--
-- "arc" only:
--   warning       particle substring whose CP0 marks the landing spot
--   radius_prop   ability property holding the landing area radius
--   radius        landing area radius in meters when radius_prop is missing (default 7). An
--                 enemy's ability often doesn't read, so every radius_prop wants its vdata value here
--   gravity_scale multiplier on sv_gravity for the arc prediction; 0 for a straight dive, which
--                 marks the ground straight below until the projectile heads down
--   follow_caster true when the `projectile` particle sits on the casting hero: the hero is tracked
--   duration_prop for a delayed blast whose particle outlives it: ability property holding the
--                 seconds from first sighting to the blast, or `duration` when that is missing; the
--                 area is drawn only until then, plus CFG.TAIL_GRACE. It is also when it hits, ahead
--                 of the flight's own guess (Bashdown's slam, a fixed time after its tell)
--   ahead_prop    ability property holding how far in front of the caster the ability places its
--                 area, or `ahead` in meters when that is missing; the marker moves that far along
--                 his flattened aim from where he comes down
--   land_window   draw the path and marker only when the predicted impact is this many seconds away
--                 or less, for a move whose early predictions miss; a straight dive (gravity_scale 0)
--                 then gets no guess at all until it is heading down
--   aim_land      meters: it comes down where its caster aims at the ground, up to this far. While the
--                 flight is held back by land_window, that spot is marked instead: for a dive (the
--                 hero tracked by `modifier`) while he is in the air aiming at least 30 deg down
--                 (vdata m_flMinAimAngle), timed by `dive_speed` or else with no hit time (he can
--                 come down any moment)
--   dive_speed    a dive's speed in units/s (Seismic Impact's m_flCrashSpeed). With it, `modifier` is
--                 the dive itself, so its aimed spot is timed by his distance at this speed
--   dive_min_speed  for a flight whose `modifier` is on through the whole of it, the dive told apart
--                 from the hover by his own movement: drawn only while he heads down at least this
--                 fast (units/s) and 20 deg below level, along that straight line to the ground,
--                 timed by his speed. Needs gravity_scale 0
--   arm_prop      for a bomb whose fuse starts when it lands (Blood Bomb): ability property holding
--                 the seconds from the landing to the blast, or `arm` when that is missing. It hits
--                 that long after it lands, and its area stays on it, timed, while it lies there.
--                 A rebound off the floor doesn't restart the fuse: it runs from the first touch
--   arm           as a list, for a grenade that blows and hops on (Scrap Grenade): the fuse of each
--                 landing in turn, the last one for every landing past the list. A hop is it climbing
--                 off at 500 u/s or faster from where it lay; its next landing takes the next fuse
--   wave_radius_prop  for a landing that sends a shockwave rolling out (Bashdown): ability property
--                 holding how far it reaches, or `wave_radius` in meters when that is missing. Drawn
--                 as an outer ring, and a danger until the wave is at its edge, past the landing's own
--                 tell. Needs the landing's time (`duration`)
--   wave_time     seconds the wave takes from the landing to that edge
--
-- "line" only:
--   range_prop    ability property holding the max travel distance
--   range         max travel distance in meters when range_prop is missing
--   width         lane half-width in meters, drawn around the flight path
--   lunge_prop    for a stab he dashes into (Flawless Advance): ability property holding that dash's
--                 length, or `lunge` in meters when it is missing. The stab's `range` counts from
--                 where the dash ends and its round tip is a `width` past that: the lane is his
--                 dash, the range and the tip
--   charge_particle  particle substring that appears as the hero starts charging a held dash
--                 (Apollo's Flawless Advance): from it the lane is drawn along his aim, untimed (no
--                 telling when he lets go), for up to `charge_max` seconds or until he dashes, so
--                 Evade walks out of it through the charge
--   charge_anim   the same, started by an animation clip of his (its exact name): a fixed wind-up
--                 with no particle of its own (Rising Ram's cast delay). On a "cone" it may be a table
--                 of clip names to the seconds from each to the hit (Ground Strike's two clips): the
--                 fan is up from the clip until then. With `dive_speed` (units/s), `dive_pitch` (deg)
--                 and `aim_land` (m) it is a dive: the fan stays where he lands, along his aim at the
--                 clip kept `dive_pitch` down, and the dive's time is added to the clip's
--   charge_max    seconds a charge can last, from its particle or clip to the dash
--   release       seconds into a charge (`charge_max`) it is timed to let go: the lane, untimed
--                 without it, is then timed to that (never sooner than now) plus the dash to you
--   release_from  for a charge held as long as he likes (Flawless Advance): seconds into it from
--                 which he can let go any moment. Until then its untimed lane is only walked out
--                 of; from then on Evade leaves it the fastest way, a dash first
--   release_anim  Lua pattern for the animation clip he lets go with: it ends the charge, and his
--                 speed then does not (a dash of his own as he starts to charge)
--   strike        seconds from that clip to the hit, all along the lane at once: the lane stays on
--                 his aim until then, timed to it (so Counterspell can answer it), and is gone after
--   hit_modifier  modifier substring the spell puts on you once it has hit (a charge's drag): while
--                 you wear it, its lane is no danger, so no Counterspell is spent on it
--   dash_particle particle substring the dash spawns on the hero; it starts the track on him the
--                 instant he moves, which a scan can miss entirely on a short dash (any `modifier`
--                 spell, "aura" included)
--   radius_prop   ability property holding the radius of the area the move ends in (a slash where
--                 it lands); drawn centred on the end of the lane, or on a projectile that has
--                 stopped (Call Bell, stuck where it hit)
--   body          units a projectile's own body keeps its centre off what it hits
--                 (m_flPhysicsRadius): its lane ends that far off the surface, not where its line
--                 meets it
--   land_offset   meters past that end the area sits, for a radius vdata measures from the move's
--                 own reach rather than from a projectile (SlashForwardOffset)
--   untimed       true when that area has no hit time: it sits there until its caster sets it off
--                 (Call Bell, blown when he shoots it), so it is a danger for as long as it is drawn.
--                 On an "arc" too: a trap that lies where it lands (Spirit Snare)
--   stays         an "arc" lobbed as a bullet (`speed`): seconds the field it leaves lies where it
--                 landed (Entangling Thorns), drawn until then; else its area goes as it lands
--   throw_anim    the exact name of the caster's clip that throws it, for a projectile the client sees
--                 too late (Lightning Ball's): from the clip its lane runs along his aim from his chest,
--                 its front leaving `throw_delay` seconds later at `speed`, timed like a bullet's. The
--                 projectile itself, once seen, takes over
--   around        true for a shot that hurts everything within `radius` of it as it goes (Lightning Ball's
--                 zap): an untimed ring on it wherever it is, which Evade walks out of; its lane stops
--                 counting as a hit once it is on you, and stuck, the ring is its area
--   bullet        weapon name substring if the game fires it as a bullet (defaults to `ability`);
--                 Debug Mode logs your own bullets that match no spell, to find it
--   speed         projectile speed in units/s; a bullet's lane stays drawn for its flight time
--   blocked_by    with Unit Collision on, the units that stop it before you (its vdata target types,
--                 as seen from you): "hero" any but its caster and you, "trooper" yours, "neutral"
--                 the neutral creeps. Its lane ends at the
--                 first in its way. None for a shot that pierces (m_flPenetrationPercent 100).
--                 On an "arc" lobbed as a bullet (Frost Grenade): it bursts on the first hero its arc
--                 meets, you always (it goes off on you), the others with Unit Collision on
--   ally_pass     meters: with `blocked_by`, its caster's own heroes nearer him than this don't stop it
--   min_speed     a hero's dash lane (`modifier`): only drawn while he moves faster than this, in m/s;
--                 for a modifier that lasts longer than the dash itself
--   height        a hero's dash lane (`modifier` or `aim`): box height above his feet in meters
--                 (default 2.5); the box also reaches 0.5 m under his feet
--   aim           true for a wind-up: drawn while the ability is in its cast delay or channel
--                 (or while `modifier` is on), pointing where the hero aims (up and down too)
--   windup        a shot's or dash's cast delay in seconds (vdata AbilityCastDelay): while the caster
--                 winds it up, before the shot exists, its lane is drawn along his aim and stops at
--                 walls, and the dodge counts the wind-up left plus the flight to you. The channel
--                 after it isn't a wind-up (a shot's channel is its flight). Caveat: an enemy's cast
--                 delay may not reach the client (it didn't for Leaping Slash, commit 149cf6a)
--                 With `charge_particle` or `charge_anim`, that tell starts the wind-up instead, and
--                 the shot leaves `windup` after it (Spirit Lasso's aim preview)
--
-- Only particles and entities matched by an enabled entry are drawn.

return {
    {
        id = "abrams_shoulder_charge",
        name = "Shoulder Charge",
        hero = "Abrams",
        hero_image = "panorama/images/heroes/bull_sm_psd.vtex_c",
        hero_id = 6,                                  -- hero_atlas.m_HeroID
        image = "panorama/images/hud/abilities/bull_charge_psd.vtex_c",
        ability = "citadel_ability_bull_charge",
        modifier = "modifier_citadel_bull_charging", -- on Abrams while he charges
        motion = "line",
        -- no distance property: 1.4 s duration at the ramp's average speed
        -- (18.75 -> 30 m/s) is about 34 m
        range = 34,
        width = 2.2, -- ChargeRadius
        -- In game (2026-11-09) he ran 690-700 u/s once up to speed, from 100-300 u/s as he set off:
        -- timed by that measured start, the lane said the hit was seconds off or had no time, Evade
        -- walked, he steered back onto you, and the next look had 0.01-0.03 s left
        speed = 700,
        -- on you once he has you: Evade parried 0.2 s after it, "in the air", four times
        hit_modifier = "modifier_charge_drag_enemy",
    },
    {
        id = "abrams_seismic_impact",
        name = "Seismic Impact",
        hero = "Abrams",
        image = "panorama/images/hud/abilities/bull_jump_psd.vtex_c",
        ability = "citadel_ability_bull_leap",
        -- the crash only (m_CrashModifier): drawn as he dives, not on the leap or the hover (up to
        -- m_flHoverTime 3 s) before it. He crashes at m_flCrashSpeed 6000 u/s along his aim, at least
        -- m_flMinAimAngle 30 down, so the spot he aims at marks it before the flight's own guess can
        modifier = "modifier_citadel_bull_leap_boosting_crash",
        motion = "arc",
        radius_prop = "ImpactRadius", -- impact radius, 9 m in vdata
        radius = 9,                   -- when an enemy's ability doesn't read
        gravity_scale = 0,            -- the slam is a straight dive, not a lob
        land_window = 0.3,            -- drawn only in the last 0.3 s of the dive: earlier guesses miss
        aim_land = 40,                -- meters he can aim the crash
        dive_speed = 6000,            -- m_flCrashSpeed
    },

    -- Apollo is hero_fencer internally (heroes.vdata, build 6860). His first ability, Disengaging
    -- Sigil (ability_fencer_throwblade), is left out on purpose: in game m_MarkParticle's CP0 sat on
    -- Apollo in one cast and on his target in another, and vdata gives the blast no fuse, so no
    -- spot or timing drawn from it was reliable (replays 2026-11-07 21-00 and 21-05).
    {
        id = "apollo_sword_charge",
        name = "Flawless Advance",
        hero = "Apollo",
        hero_image = "panorama/images/heroes/fencer_sm_psd.vtex_c",
        hero_id = 77,                                 -- hero_fencer.m_HeroID
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
        -- A held charge, then the lunge. On the press he may dash where he is moving ("lunges in any
        -- direction": DashSpeed 1100 u/s, DashRange 5 m); when he lets go he stabs: AttackDashRange 3 m
        -- at AttackingDashSpeed, piercing SlashLength ahead, so it lands all along the lane within
        -- ~0.05 s. m_DashTrailEffect appears as he starts to charge: the lane is drawn from it.
        charge_particle = "fencer_lunge_dash.vpcf",
        -- In game (2026-11-09, 20 casts) he let go 0.9-1.45 s after it, 0.66-1.39 s in an earlier test:
        -- AbilityCastDelay 0.1 + HoldDurationMin 0.25 + up to HoldDurationMax 1.1. At the 1.2 this had,
        -- the lane ran out before 6 of the 20, and the replay's hit (16-09-47) landed 0.3 s after it
        charge_max = 1.6,
        -- His attack clips (ability_lunge_attack_*, ability_lunge_in_air_attack_*) start as he lets go
        -- and end the charge. His speed does not: the dash on the press was taken for the lunge
        release_anim = "lunge.*attack",
        -- The stab lands 0.09-0.11 s after that clip (11 hits, 2026-11-09). He can turn the lane with
        -- his aim all through the charge, so a dodge only gets you out of where he aimed then: he
        -- followed a dash and hit from 0.5 m off. From his clip on it is timed, and parried
        strike = 0.1,
        -- The lunge itself is seen 0.00-0.04 s before it hits, too late for anything, so Evade works on
        -- the charge. Until he can let go it only walks out of the lane, which turns with his aim; from
        -- then on it leaves it the fastest way, a dash first. Timed to one likely release (0.65 s), it
        -- dashed before he could let go, then gave up once the guess had passed
        release_from = 0.6,                           -- just under the soonest he has let go, 0.66 s
        motion = "line",
        -- Counterspell blocks it when the parry is up in time: off his clip (`strike`) it goes
        -- 0.07-0.09 s before the stab, and none of 6 got through, 4 of them aimed within 1 m of you.
        -- Off the lunge's own lane, 0.00-0.04 s before it, 13 parries were up as it hit and none
        -- blocked (replay 2026-11-09 11-46: its sphere up, 286 to 243). A lock-on half-circle and his
        -- whole reach were tried instead of the lane, and did no better (2026-11-09 11-55)
        -- The stab starts where his dash ends and pierces SlashLength from there, round-tipped: the
        -- lane is all three, 17.6 m. Drawn at SlashLength alone, 10 of 19 casts hit from past its end
        -- (2026-11-09), one from 18.9 m, most after Evade had walked you out of it the short way,
        -- backwards over its end
        range_prop = "SlashLength",                   -- strike range, 13 m in vdata
        range = 13,
        lunge_prop = "AttackDashRange",               -- 3 m in vdata; he closed 3.6 m in game
        lunge = 3,
        width = 1.6,                                  -- SlashRadius
        speed = 2200,                                 -- AttackingDashSpeed u/s, his lunge at a target (logged
                                                      -- 1500-2200 u/s in game): when it reaches you. DashSpeed
                                                      -- 1100 is the untargeted lunge; timed at that, Evade
                                                      -- saw the hit twice as far off and parried late
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
        hero_id = 15,                                 -- hero_bebop.m_HeroID
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
        -- Drawn from the particle on, not from the fist's 0.2 s: Evade only reacts to what is drawn,
        -- and that 0.1 s was too short even to parry
        cone_time = 0.3,                               -- the punch lands ~0.27 s in; the particle runs on
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
        -- m_nTargetTypes HERO | TROOPER_ENEMY | NEUTRAL: it grabs the first hero of either team, your
        -- trooper or a neutral creep in its way
        blocked_by = { "hero", "trooper", "neutral" },
        -- but it goes through his own teammates near him: through one 2.2-6.0 m in front, caught at
        -- 8.0-10.1 m (8 throws, 2026-11-10)
        ally_pass = 7,
        windup = 0.1,                                 -- AbilityCastDelay (citadel_ability_hook)
    },

    -- Billy is hero_punkgoat internally (heroes.vdata, build 6860)
    {
        id = "billy_bashdown",
        name = "Bashdown",
        hero = "Billy",
        hero_image = "panorama/images/heroes/punkgoat_sm_psd.vtex_c",
        hero_id = 72,                                 -- hero_punkgoat.m_HeroID
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
        -- the slam isn't where Billy comes down: the ability places it this far in front of him
        ahead_prop = "PlaceDistanceInFrontOfCaster",  -- 6.2 m in vdata
        ahead = 6.2,
        radius_prop = "AbilityCastRange",             -- 4 m slam radius in vdata, +2 m with the second upgrade
        radius = 4,                                   -- when an enemy's ability doesn't read
        gravity_scale = 0,                            -- a driven dive, not a fall: m_TimeToReachGroundByHeight lands
                                                      -- 448 u in 0.22 s and 1000 u in 0.2 s
        -- The slam lands a fixed time after the bat effect appears, hop and all: 0.51-0.58 s over 40
        -- casts in game (2026-11-09). Timed by his fall, which is a guess straight down from his
        -- waist until he hops, Evade read "hits in 0.01 s" at the cast and never moved
        duration = 0.5,
        -- "The slam creates a shockwave that deals Spirit Damage and applies Knock Up" (the tooltip,
        -- whose header is this Wave Radius): it tossed you up to 0.50 s after the slam, from well
        -- outside the 4 m that was all this drew
        wave_radius_prop = "WaveEndRadius",           -- 8 m in vdata, scales with spirit range
        wave_radius = 8,
        wave_time = 0.5,                              -- ExplodeDelay
    },
    {
        id = "billy_rising_ram",
        name = "Rising Ram",
        hero = "Billy",
        image = "panorama/images/hud/abilities/punkgoat/goat_risingram_psd.vtex_c",
        ability = "ability_punkgoat_goatflip",
        modifier = "goatflip/charge",                 -- m_Charging._my_subclass_name (_class modifier_citadel_goat_charging),
                                                      -- on Billy while he rams: it reads
                                                      -- "ability_punkgoat_goatflip/charge" in game. Bare "charge"
                                                      -- is in about 20 other modifiers (modifier_melee_charge, ...)
        min_speed = 25,                               -- m/s, under the ram's ChargeSpeed 1200 u/s / 39.37 = 30.5 m/s:
                                                      -- the wind-up's lane holds until he moves at ram speed
        -- AbilityCastDelay 0.35 s winds it up first, and an enemy's cast delay doesn't reach the client.
        -- In game (2026-11-09) the lane, drawn off the modifier, came 0.08-0.16 s before the ram hit;
        -- his wind-up clip started 0.33 s before he moved. So the lane is drawn along his aim from the
        -- clip, timed to the ram leaving
        charge_anim = "ability_goat_ram_intro",
        charge_max = 0.5,                             -- the clip's length
        release = 0.35,                               -- AbilityCastDelay
        speed = 1200,                                 -- ChargeSpeed u/s (ran 1094-1113 over its first sample)
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
        -- then yanks them in after AbilityDuration 2.8 s. Once you are chained no spot is out of the
        -- pull: in game (2026-11-09) Evade walked 4.3 m out of the 12 m ring this used to draw around
        -- him and was pulled all the same. So it is cast at you for as long as you wear the chain,
        -- and only parried. Counterspell blocks the pull: parried 0.24 s before it, its
        -- modifier_active came on as the pull was due and no pull modifier followed (2026-11-09)
        modifier = "waiting_for_pull",                -- m_WaitingToPullModifier._my_subclass_name (_class
                                                      -- modifier_punkgoat_tether_waiting): on Billy until the pull
        mark_modifier = "punkgoat_tether/tether",     -- "Chained to Billy" (_class modifier_punkgoat_tether): on
                                                      -- you while chained, gone when the chain breaks (no line
                                                      -- of sight for RopeSnapNoLOSDuration 0.5 s)
        motion = "target",
        range_prop = "AbilityCastRange",              -- 12 m grab radius in vdata, +5 m with the third upgrade
        range = 12,
        -- shortcut: AbilityDuration as vdata has it; a Billy with duration items pulls later, still inside
        -- Counterspell's 0.8 s block up to +0.55 s. Read it off his ability if one ever pulls past that
        hit_delay = 2.8,                              -- the pull landed 2.81 s after his modifier was seen
    },

    -- Calico is hero_nano internally (citadel_gc_hero_names_english.txt: "hero_nano:n" "Calico";
    -- heroes.vdata hero_nano.m_mapBoundAbilities). His slots are ability_nano_clustergrenade,
    -- _nano_dash, _nano_catform and _nano_shadow_pulse (build 6860).
    {
        id = "calico_gloom_bombs",
        name = "Gloom Bombs",
        hero = "Calico",
        hero_image = "panorama/images/heroes/nano_sm_psd.vtex_c",
        hero_id = 16,                                 -- hero_nano.m_HeroID
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
        windup = 0.15,                                -- AbilityCastDelay (ability_nano_clustergrenade)
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
        -- Shiv dash doesn't fill this entry. In game it is a wind-up and a leap, not the flat
        -- 0.147 s dash a lane predicts: the lane and landing never resolved and only the pin drew
        -- (replay 2026-11-07). So the slash circle rides on him, like Chain Gang's ring on Billy.
        dash_particle = "nano_dash_instant.vpcf",     -- m_DashLineEffect, on him for the dash
        modifier = "modifier_citadel_shiv_dash",
        motion = "aura",
        radius_prop = "SlashRadius",                  -- 4 m slash circle
        radius = 4,
        dash_range_prop = "AbilityCastRange",         -- 9 m: the whole dash drawn as a lane from where it began
        dash_range = 9,
        -- The slash is one hit of SlashRadius 4 m centred SlashForwardOffset 1.5 m past where the dash
        -- stops, after the 0.1 s cast delay and up to 9 m at DashSpeed 2400 u/s: at most ~0.25 s by
        -- vdata. The replay's wind-up and leap may be slower; Debug Mode logs her real dash
        dash_speed = 2400,
        land_offset = 1.5,
        windup = 0.1,                                 -- AbilityCastDelay; only your own reaches the client
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
        radius = 7.5,                                 -- when an enemy's ability doesn't read
        duration_prop = "AbilityChannelTime",         -- 3 s until he returns
        duration = 3,
        show_first = 0.5,                             -- the burst on cast
        show_last = 1,                                -- and the burst when he comes back
    },

    -- Celeste is hero_unicorn internally (citadel_gc_hero_names_english.txt "hero_unicorn:n" "Celeste";
    -- heroes.vdata hero_unicorn.m_mapBoundAbilities), build 6860
    {
        id = "celeste_radiant_daggers",
        name = "Radiant Daggers",
        hero = "Celeste",
        hero_image = "panorama/images/heroes/unicorn_sm_psd.vtex_c",
        hero_id = 81,                                 -- hero_unicorn.m_HeroID
        image = "panorama/images/hud/abilities/unicorn/unicorn_luminousflux_psd.vtex_c",
        ability = "ability_unicorn_luminousstrike",
        -- Ground-targeted circle (LOCATION_GROUND, SHAPE_CIRCLE): a beam falls from ClimbHeight 50 m and
        -- explodes after PreExplosionDuration 1.4 s. The beam is a world-origin particle at the target,
        -- so nothing flies to follow; the game's own tell (m_TellParticle) marks the blast area instead.
        -- Up to 3 charges (AbilityCharges 1, +2 with the first upgrade) 2 s apart
        -- (AbilityCooldownBetweenCharge), so one cast's tell is still up when the next comes.
        particles = { "unicorn_daggers_target.vpcf" },
        warning = "unicorn_daggers_target.vpcf",      -- its CP0 is the impact point
        motion = "arc",
        radius_prop = "ExplosionRadius",              -- 8 m blast radius in vdata
        radius = 8,                                   -- when an enemy's ability doesn't read
        gravity_scale = 0,                            -- the beam drives straight down, no lob
        -- the tell lives on PostExplosionDuration 0.8 s past the blast, so it can't end the drawing
        duration_prop = "PreExplosionDuration",       -- 1.4 s from the tell to the blast
        duration = 1.4,
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
        -- The orb flies until it hits something. In game (Debug Mode, 16 shots that missed, 2026-11-09)
        -- it went 13.5 to 66.7 m at a steady 2000 u/s, each ending on a wall. Its weapon info sets no
        -- range or lifetime of its own, so it has weapon_info_base's: m_flBulletLifetime 2 s, 101.6 m
        -- at its speed (m_flRange 7000 u is further still). The 22.2 m this had was one of those
        -- walls, and the orb hit from past the end of its lane. The lane still stops at the first wall.
        -- BounceRadius 15 m is how far the orb looks for its next target, not how far it flies. Each
        -- bounce is said to be a new bullet from the hit; it then draws this whole range too. Telling
        -- one by where it starts was tried and went: the first shot itself starts 3.2-3.7 m from her,
        -- was taken for a bounce, and two from 24.8 m went undrawn
        range = 101.6,
        width = 1.65,                                   -- m_flBulletRadius 65 u / 39.37 u per meter
        speed = 2000,                                   -- m_flBulletSpeed, and what those shots flew at.
                                                        -- At the 1820 this had, hits came ~0.05 s
                                                        -- before Evade's time
        windup = 0.75,                                  -- AbilityCastDelay (the charge); the orb homes,
                                                        -- so her aim is a guess until it is out
        -- An enemy's cast delay never reaches the client, so on an enemy the lane comes with the
        -- bullet, 0.12-0.25 s before it hits. Her charge particle (m_ChargeParticle, 0.78-0.86 s before
        -- the bullet) could start it sooner, and did for a test; it is left out on purpose: nothing is
        -- drawn while she charges, only once the orb is out
    },

    -- Deadman Danny is hero_deadpack internally (heroes.vdata, build 6860). His slots are
    -- ability_deadpack_chargeblast, _rocketeer, _flamethrower and _ultimate; his particles live
    -- under particles/abilities/airheart/, which no other ability uses.
    {
        id = "danny_close_the_deal",
        name = "Close the Deal",
        hero = "Deadman Danny",
        hero_image = "panorama/images/heroes/deadpack_sm_psd.vtex_c",
        hero_id = 78,                                 -- hero_deadpack.m_HeroID
        image = "panorama/images/hud/abilities/deadpack/deadpack_flight_psd.vtex_c", -- m_strAbilityImage
        ability = "ability_deadpack_ultimate",
        -- Unit-targeted (an enemy hero within GrabRange 10 m, picked in a cone in front of him):
        -- AbilityCastDelay 0.5 s, then he charges for m_flChargeTime 0.25 s, grabs the target and flies
        -- up with him to slam down. Through the cast delay his m_AutoCastDelayModifier ("castdelay")
        -- wears airheart_ult_telegraph. vdata gives no cone width for him: 90 deg, as Soul Exchange's
        particles = { "airheart_ult_telegraph.vpcf" },
        motion = "target",
        range_prop = "AbilityCastRange",              -- 10 m in vdata (GrabRange)
        range = 10,
        angle = 90,
        -- not the cast delay plus the charge (0.75 s): in game (2026-11-09, four ults from 3-6 m) the
        -- grab landed 0.47-0.54 s after the telegraph was seen, and a parry timed to 0.75 s was tapped
        -- as he grabbed. Early, the 0.8 s parry still covers a longer charge
        hit_delay = 0.45,
    },
    {
        id = "danny_chimera_mk1",
        name = "Chimera Mk1",
        hero = "Deadman Danny",
        image = "panorama/images/hud/abilities/deadpack/deadpack_chimera_psd.vtex_c",
        ability = "ability_deadpack_rocketeer",
        -- A jetpack: AbilityCastDelay 0.7 s, then up to AbilityChannelTime 5 s of flight that builds
        -- heat, ending in a dive into the ground that explodes (m_VTOLImpactOnGroundFX
        -- airheart_chimera_mark_impact.vpcf, which only spawns after the hit). Danny himself is
        -- tracked, like Abrams' slam (replay 2026-11-08 13-59: a fast angled dive, cracks and a ring).
        modifier = "jetpacking",                      -- m_JetpackingModifier._my_subclass_name; also matches
                                                      -- m_JetpackingVTOLModifier "jetpackingvtol", not
                                                      -- "jetpacklockout". On through the hover too: in game
                                                      -- (2026-11-09) it came and went with his every thrust
        motion = "arc",
        radius_prop = "Radius",                       -- 8 m explosion radius in vdata
        radius = 8,
        gravity_scale = 0,                            -- a thrust dive along his aim, not a fall: a straight line
        -- the dive alone, told by his speed: the hover's own steering (m_IntentSpace*Velocity) tops out
        -- near 1000 u/s even down. Unmeasured: Debug Mode logs his speed while he flies
        dive_min_speed = 1200,
    },

    -- Doorman is hero_doorman internally (heroes.vdata, build 6860). His slots are ability_doorman_bomb
    -- (Call Bell), _doorway, _luggage_cart and _hotel. Hotel Guest (_hotel) is left out: it lands the
    -- tick it is cast and freezes you, so only a parry sent as he readies it blocks it
    {
        id = "doorman_call_bell",
        name = "Call Bell",
        hero = "Doorman",
        hero_image = "panorama/images/heroes/doorman_sm_psd.vtex_c",
        hero_id = 69,                                 -- hero_doorman.m_HeroID
        image = "panorama/images/hud/abilities/doorman/doorman_bell_psd.vtex_c",
        ability = "ability_doorman_bomb",
        -- A thrown bell entity (m_mapProjectileInfos.primary, _class doorman_bomb_projectile): straight
        -- along his aim at m_flSpeed 1500 u/s, m_flGravityScale 0, slowed by m_ProjectileDragCurve, and
        -- stuck where it hits (PBF_StickToWorld). It blows ProjectileFuse 3 s after the throw
        -- (PBF_DetonateOnLifetimeExpire), or as soon as he shoots it: in the replay (2026-11-09 18-08,
        -- a sandbox Doorman bot) every bell blew 0.58-0.68 s after the cast, for 55 (ExplosionDamage)
        particles = { "doorman_bell_projectile.vpcf" }, -- m_particle; the .vpcf keeps it off its children
        projectile = "doorman_bell_projectile.vpcf",
        motion = "line",
        -- shortcut: the drag curve read as a per-tick speed factor stops it ~47 m out, in the air if it
        -- hits nothing first; unmeasured, Debug Mode logs how far it flew when it blows
        range = 47,
        width = 0.76,                                 -- m_flTriggerRadius 30 u / 39.37: the impact hit
        -- It sticks with its centre this far off the ground, short of where its line meets it: 0.7 m
        -- short thrown from 4 m, more the flatter the throw. The ring sat that far past the bell
        body = 12,                                    -- m_flPhysicsRadius, units
        -- no `speed`: it slows down, so its lane is timed by its measured speed
        radius_prop = "Radius",                       -- 5.5 m blast (and slow aura), +4.5 m with the third upgrade
        radius = 5.5,
        -- the blast comes when he shoots it, any moment once it sits there: no hit time to parry to
        untimed = true,
    },
    {
        id = "doorman_luggage_cart",
        name = "Luggage Cart",
        hero = "Doorman",
        image = "panorama/images/hud/abilities/doorman/doorman_luggagetrolley_psd.vtex_c",
        ability = "ability_doorman_luggage_cart",
        -- A cart entity (m_mapProjectileInfos.primary, _class projectile_doorman_cart_projectile) rolled
        -- along the ground (m_flDistanceAboveGround 15 u, pitch held to 25 deg) at m_flSpeed 1000 u/s;
        -- it scoops up the first enemy hero it touches and carries him on
        particles = { "doorman_cart_projectile.vpcf" }, -- m_particle; the .vpcf keeps it off _allied and _cast
        projectile = "doorman_cart_projectile.vpcf",
        motion = "line",
        range_prop = "AbilityCastRange",              -- 20 m in vdata, +25 m with the second upgrade
        range = 20,
        width = 1.74,                                 -- m_flTriggerRadius 68.4 u / 39.37
        speed = 1000,
        blocked_by = { "hero" },                      -- m_nTargetTypes HERO: the first hero of either team
        windup = 0.25,                                -- AbilityCastDelay
    },

    -- Drifter is hero_drifter internally (heroes.vdata, build 6860). His slots are drifter_blood_blast
    -- (Rend), drifter_shadow_mark (Stalker's Mark), ability_drifter_hunger and drifter_darkness
    {
        id = "drifter_rend",
        name = "Rend",
        hero = "Drifter",
        hero_image = "panorama/images/heroes/drifter_sm_psd.vtex_c",
        hero_id = 64,                                 -- hero_drifter.m_HeroID
        image = "panorama/images/hud/abilities/drifter/drifter_claw_psd.vtex_c",
        ability = "drifter_blood_blast",
        -- Instant cast (TARGETING_SHAPE_CONE) with AbilityCastDelay 0.4 s, then a sweep of claw bullets
        -- (m_flBulletSpeed 10000) through the cone. An enemy's cast delay doesn't reach the client, so
        -- the fan starts off m_ChargeParticle, the glowing claws on him through the wind-up (replay
        -- 2026-11-09 23-39). m_AreaParticle drifter_claw.vpcf only shows the slashes once they hit
        particles = { "drifter_claw_channel.vpcf" },
        cone_particle = "drifter_claw_channel.vpcf",
        cone_time = 0.45,                             -- cast delay 0.4 + 16 m at 10000 u/s
        motion = "cone",
        range_prop = "AbilityCastRange",              -- 16 m in vdata, scales with spirit range
        range = 16,
        -- shortcut: read as the full width, like Soul Exchange's m_flTargetingConeAngle; if he hits from
        -- outside the fan in game, it is the half angle (100 deg). ExtraSweepConeAngle 60 over
        -- ExtraSweepRange 3 m at his feet is left out
        angle_prop = "TargetingConeAngle",
        angle = 50,
    },
    {
        id = "drifter_stalkers_mark",
        name = "Stalker's Mark",
        hero = "Drifter",
        image = "panorama/images/hud/abilities/drifter/drifter_stalkersmark_psd.vtex_c",
        ability = "drifter_shadow_mark",
        -- Flies as a bullet (m_mapWeaponInfos.primary, m_flBulletGravityScale 0), so there are no
        -- `classes`: on_bullet_create matches it by `ability` and its tracer is followed like Malice's
        particles = { "drifter_stalkers_mark_projectile.vpcf" }, -- m_szBulletTravelTracerParticle
        projectile = "drifter_stalkers_mark_projectile.vpcf",    -- the .vpcf keeps it off _impact/_debuff/_teleport
        motion = "line",
        -- No cast range (AbilityCastRange 0) or lifetime of its own: weapon_info_base's m_flRange 7000 u
        -- (2 s m_flBulletLifetime at its speed is further). The lane stops at the first wall anyway
        range = 177.8,
        width = 0.69,                                 -- m_flBulletRadius 27 u / 39.37
        speed = 3900,                                 -- m_flBulletSpeed
        windup = 0.15,                                -- AbilityCastDelay
    },

    -- Dynamo is hero_dynamo internally (heroes.vdata, build 6860), "sumo" in his art paths. His slots
    -- are citadel_ability_stomp (Kinetic Pulse), _void_sphere, _nikuman and _self_vacuum (Singularity)
    {
        id = "dynamo_kinetic_pulse",
        name = "Kinetic Pulse",
        hero = "Dynamo",
        hero_image = "panorama/images/heroes/sumo_sm_psd.vtex_c",
        hero_id = 11,                                 -- hero_dynamo.m_HeroID
        image = "panorama/images/hud/abilities/sumo/sumo_stomp_psd.vtex_c",
        ability = "citadel_ability_stomp",
        -- A wave rolled along the ground (TARGETING_SHAPE_LINE; m_mapProjectileInfos.primary, _class
        -- projectile_stomp_projectile, DistanceAboveGround 1 m) at m_flSpeed 1600 u/s, after
        -- AbilityCastDelay 0.42 s; it tosses up every enemy it passes (modifier_citadel_tossup)
        particles = { "dynamo_gravity_wave.vpcf" },   -- m_particle
        projectile = "dynamo_gravity_wave.vpcf",
        motion = "line",
        -- An enemy's cast delay doesn't reach the client, but his stomp clip does: in game (2026-11-10)
        -- it started 0.06 s after the cast, and the toss landed 0.66 s after it from 13.9 m. The lane
        -- is drawn along his aim from it, timed to the wave leaving at the cast delay.
        -- shortcut: one clip name seen; if a cast draws nothing until the wave, Debug Mode's anim log
        -- names the other
        charge_anim = "ability_stomp_alt",
        charge_max = 0.45,                            -- the cast delay, then the wave's own lane
        -- AbilityCastDelay is 0.42 s from the cast, and the clip is seen ~0.06 s into it: all 6 tosses in
        -- game (2026-11-10) landed 0.02-0.12 s before a lane timed at 0.42 from the clip said
        release = 0.34,
        -- he doesn't dash: over his run (EMaxMoveSpeed ~7 m/s), so the lane on him is the wind-up's
        -- alone and is never taken for a dash of his
        min_speed = 20,
        speed = 1600,                                 -- m_flSpeed
        range_prop = "StompRange",                    -- 16 m in vdata, scales with spirit range
        range = 16,
        -- StompWidth is each side of its middle: 11 tosses in game (2026-11-10) found you 1.0-7.0 m off
        -- it, 7 of them past the 2.75 m this had (the full width halved), his aim turning 0-11 deg
        width = 5.5,
    },
    {
        id = "dynamo_singularity",
        name = "Singularity",
        hero = "Dynamo",
        image = "panorama/images/hud/abilities/sumo/sumo_vacuum_psd.vtex_c",
        ability = "citadel_ability_self_vacuum",
        -- Channelled ultimate: after AbilityCastDelay 0.2 s m_VacuumAuraModifier sits on him for
        -- AbilityChannelTime 2.75 s, lifting and pulling in every enemy inside VacuumRadius. It read
        -- "citadel_ability_self_vacuum/modifier_vacuumaura" on you as you cast it (2026-11-10).
        -- shortcut: it is m_bIsHidden; if an enemy's never shows to the poll, `aim` (his channel) still
        -- draws the ring. Untested on an enemy Dynamo
        modifier = "modifier_vacuumaura",             -- its victims' modifier_vacuumaura_target too: a pawn
                                                      -- without the ability is a victim and doesn't match
        aim = true,
        motion = "aura",
        radius_prop = "VacuumRadius",                 -- 7 m in vdata, +2 m with the first upgrade
        radius = 7,
        -- In game (2026-11-10) the ring came only from his channel (`aim`), as the pull had you: 0.30 s
        -- after the cast. His m_strCastAnimSequenceName clip reached the client 0.07 s after it, so
        -- the ring starts there, timed to the pull, for a dash out of its edge or a parry
        charge_anim = "ability_vacuum_alt_start",
        charge_max = 0.25,                            -- then untimed: anyone inside is pulled all channel
        release = 0.2,                                -- AbilityCastDelay; the pull came 0.23 s after the clip
        -- the lift on you (a stun): no dash goes, so none is spent on it. 13 were, all "dashing false"
        hit_modifier = "modifier_vacuumaura_target",
    },

    -- Graves is hero_necro internally (heroes.vdata, build 6860). Her slots are
    -- ability_necro_hauntingskull (Jar of the Dead), _zombiewall (Grasping Hands), _fear, _gravestone
    {
        id = "graves_jar_of_the_dead",
        name = "Jar of the Dead",
        hero = "Graves",
        hero_image = "panorama/images/heroes/necro_sm_psd.vtex_c",
        hero_id = 76,                                 -- hero_necro.m_HeroID
        image = "panorama/images/hud/abilities/necro/necro_skull_psd.vtex_c",
        ability = "ability_necro_hauntingskull",
        -- A jar lobbed as a bullet (PROJECTILE_FIRED_AS_BULLET; m_mapWeaponInfos.primary: m_flBulletSpeed
        -- 1200, m_flBulletGravityScale 1.0) after AbilityCastDelay 0.15 s. Where it lands it lets out
        -- SkullCount 4 skulls (within SpawnRadius 2 m) that go for enemies inside TargetSearchRadius 7 m,
        -- TargetSearchInitialDelayMin 0.15 s after. Its tracer never reached the client (2026-11-10: only
        -- "detected on C_CitadelPlayerPawn", nothing drawn), so the arc comes from its bullet as fired.
        -- shortcut: bullet gravity taken as sv_gravity x the scale; Debug Mode logs how far from the
        -- drawn landing its first skull comes out
        particles = { "necro_haunting_skull_container_projectile.vpcf" }, -- m_szBulletTravelTracerParticle
        projectile = "necro_haunting_skull_container_projectile.vpcf",
        skip = { "necro_haunting_skull_projectile" }, -- m_particle of the skulls: where it really landed
        motion = "arc",
        speed = 1200,                                 -- m_flBulletSpeed
        gravity_scale = 1.0,                          -- m_flBulletGravityScale
        radius_prop = "TargetSearchRadius",           -- 7 m in vdata, scales with spirit range
        radius = 7,
        arm = 0.15,                                   -- TargetSearchInitialDelayMin: the skulls go for you then
    },
    {
        id = "graves_grasping_hands",
        name = "Grasping Hands",
        hero = "Graves",
        image = "panorama/images/hud/abilities/necro/necro_hands_psd.vtex_c",
        ability = "ability_necro_zombiewall",
        -- A wall of hands placed on the ground (TARGETING_LOCATION_DEPLOYED_OBJECT, up to AbilityCastRange
        -- 24 m), across her aim in the replay (2026-11-10 14-29): ground auras of AuraRadius 0.75 m every
        -- GroundAuraSpacing 1 m along ZombieWallLength 14 m, for AbilityDuration 5 s. Crossing it roots
        -- you for ImmobilizeDuration 1 s and hurts. Drawn where its hands are, so you don't walk over it.
        -- In game (2026-11-10) its ~16 ground particles (one a hand) gave ~58 points, 54.6 m end to end:
        -- only control point 0 is a hand's spot. Its cast beam and the two projectiles that lay it turned
        -- the line the wrong way before the hands were down, and are left out
        particles = { "necro_wall.vpcf" },            -- m_GroundParticle; the .vpcf keeps it off _beam,
                                                      -- _projectile and _deploy (her aim preview)
        motion = "wall",
        -- its hands are up this long, from the first seen: 5.1 s in the replay, and its particles
        -- linger ~1.25 s after them
        duration_prop = "AbilityDuration",            -- 5 s in vdata, +2 s with the first upgrade
        duration = 5,
        wall_max = 26,                                -- ZombieWallLength 14 m, +10 m with the second upgrade
        width = 0.75,                                 -- AuraRadius, each side of its middle
    },

    -- Grey Talon is hero_orion internally (heroes.vdata, build 6860), "archer" in his art paths. His
    -- slots are ability_charged_shot, _power_jump (Rain of Arrows), _immobilize_trap (Spirit Snare)
    -- and _guided_arrow (Guided Owl). Guided Owl is left out: he steers it, so where it goes can't be told
    {
        id = "talon_charged_shot",
        name = "Charged Shot",
        hero = "Grey Talon",
        hero_image = "panorama/images/heroes/archer_sm_psd.vtex_c",
        hero_id = 17,                                 -- hero_orion.m_HeroID
        image = "panorama/images/hud/abilities/archer/archer_charged_shot_psd.vtex_c",
        ability = "ability_charged_shot",
        -- Held (AbilityCastDelay 0.5 s, then he lets go when he likes), then an arrow flies as a bullet:
        -- on_bullet_create matches it by `ability`. Only the shot is drawn, not his charge: from range a
        -- dash gets out of it, and Counterspell blocks it
        motion = "line",
        range = 254,                                  -- m_flRange 10000 u; the lane stops at the first wall
        width = 0.61,                                 -- m_flBulletRadius 24 u
        speed = 8000,                                 -- m_flBulletSpeed
    },
    {
        id = "talon_spirit_snare",
        name = "Spirit Snare",
        hero = "Grey Talon",
        image = "panorama/images/hud/abilities/archer/imobolize_trap_psd.vtex_c",
        ability = "ability_immobilize_trap",
        -- A trap thrown (m_mapProjectileInfos.primary, _class immobilize_trap_projectile: m_flSpeed 1600,
        -- m_flUpSpeed 100) that lies where it lands for Lifetime 22 s, armed after ArmTime 2 s, and
        -- tethers whoever comes inside Radius 6.5 m. No hit time: ground not to walk onto
        particles = { "archer_immobilize_trap_projectile.vpcf" }, -- m_particle
        projectile = "archer_immobilize_trap_projectile.vpcf",
        skip = { "archer_immobilize_trap_preview", "archer_immobilize_trap_ground_preview" }, -- his own aim
        motion = "arc",
        gravity_scale = 1.0,                          -- shortcut: unset in vdata, the base's taken as 1
        radius_prop = "Radius",                       -- 6.5 m
        radius = 6.5,
        untimed = true,
    },

    {
        id = "ghost_blood_bomb",
        name = "Blood Bomb",
        hero = "Lady Geist",
        hero_image = "panorama/images/heroes/spectre_sm_psd.vtex_c",
        hero_id = 4,                                  -- hero_ghost.m_HeroID (heroes.vdata)
        image = "panorama/images/hud/abilities/spectre/blood_bomb_psd.vtex_c",
        ability = "ability_blood_bomb",
        classes = { "blood_bomb" },
        particles = { "ghost_blood_bomb" },
        projectile = "ghost_blood_bomb_projectile",
        motion = "arc",
        warning = "ghost_blood_bomb_warning",
        -- the particle key is the bare stem, so every child of the bomb still answers to it: all
        -- three fire after the throw and each would leave its own group behind if let through
        skip = {
            "ghost_blood_bomb_preview",        -- m_previewParticle (:55864): the throw preview
            "ghost_blood_bomb_explode",        -- m_ExplodeParticle (:55905)
            "ghost_blood_bomb_spilled_blood",  -- m_SpilledBloodParticle (:55910): the pool it leaves
        },
        radius_prop = "Radius",
        radius = 7,                                   -- Radius 7 m in vdata, when an enemy's ability doesn't read
        gravity_scale = 1.0,
        -- "deals damage after a brief arm time": its timer starts when it hits something
        -- (PBF_StartDetonateTimeOnHitWorld | OnHitTarget), so it blows ArmingDuration after it lands.
        -- Timed to the landing itself, Evade read "hits in 0.05-0.15 s" and spent Counterspell at
        -- once on 6 bombs of 13 (2026-11-09); the one it then blocked blew 0.65 s after it landed
        arm_prop = "ArmingDuration",
        arm = 0.65,
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
        windup = 0.12,                                -- AbilityCastDelay (ability_blood_shards)
    },
    {
        id = "ghost_soul_exchange",
        name = "Soul Exchange",
        hero = "Lady Geist",
        image = "panorama/images/hud/abilities/spectre/blood_exchange_psd.vtex_c", -- m_strAbilityImage
        ability = "ability_health_swap",              -- hero_ghost ESlot_Signature_4 (heroes.vdata)
        -- Unit-targeted (TARGETING_LOCATION_UNIT, an enemy hero, picked in the 90 deg cone in front of
        -- her, m_flTargetingConeAngle): AbilityCastDelay 0.1 s, then a tracked projectile at 1200 u/s
        -- (m_mapProjectileInfos.primary, no warning particle) swaps the health. Through the cast delay
        -- m_PreCastModifier puts ghost_blood_exchange_caster on her, and on the target's screen alone
        -- ghost_blood_exchange_tgt_screen (abilities.vdata ability_health_swap, build 6860)
        particles = { "ghost_blood_exchange_caster.vpcf" },
        target_particles = { "ghost_blood_exchange_tgt_screen" },
        motion = "target",
        range_prop = "AbilityCastRange",              -- 5.5 m in vdata
        range = 5.5,
        angle = 90,
        -- In game (2026-11-09, three casts at 5 m) her caster tell never reached the client; the screen
        -- tell did, and the swap's modifier_health_swap_debuff landed on you 0.10-0.11 s after it: the
        -- cast delay, with no flight after it to add
        hit_delay = 0.1,                              -- AbilityCastDelay
    },

    -- Haze is hero_haze (heroes.vdata, build 6860); ability_sleep_dagger is her ESlot_Signature_1
    {
        id = "haze_sleep_dagger",
        name = "Sleep Dagger",
        hero = "Haze",
        hero_image = "panorama/images/heroes/haze_sm_psd.vtex_c",
        hero_id = 13,                                 -- hero_haze.m_HeroID
        image = "panorama/images/hud/abilities/haze/haze_sleep_dagger_psd.vtex_c",
        ability = "ability_sleep_dagger",
        -- A dagger thrown as a bullet (m_mapWeaponInfos.primary): on_bullet_create matches it by `ability`
        -- (the weapon reads "ability_sleep_dagger", 2026-11-10). It puts you to sleep for 2.75 s
        motion = "line",
        -- shortcut: m_flBulletGravityScale 0.2 drops it ~0.2 m over 50 m, drawn straight; Malice's 3 s
        -- bullet lifetime taken for its range, as vdata gives none
        range = 266.7,
        width = 0.62,                                 -- m_flBulletRadius 24.5 u
        speed = 3500,                                 -- m_flBulletSpeed
        windup = 0.2,                                 -- AbilityCastDelay
    },

    -- Holliday is hero_astro (heroes.vdata, build 6860), "astro" in her art paths. Spirit Lasso is
    -- ability_gravity_lasso (ESlot_Signature_4)
    {
        id = "holliday_spirit_lasso",
        name = "Spirit Lasso",
        hero = "Holliday",
        hero_image = "panorama/images/heroes/astro_sm_psd.vtex_c",
        hero_id = 14,                                 -- hero_astro.m_HeroID
        image = "panorama/images/hud/abilities/astro/holliday_spirit_lasso_psd.vtex_c",
        ability = "ability_gravity_lasso",
        -- A lasso thrown as a bullet (m_mapWeaponInfos.primary): on_bullet_create matches it by `ability`
        -- (the weapon reads "ability_gravity_lasso", 2026-11-10). It lifts the first enemy hero it
        -- catches and drags him after her
        motion = "line",
        -- shortcut: the bullet's own m_flRange is 10000 u; the 20 m cast range taken as how far it
        -- reaches, unmeasured. Debug Mode's "passes" line shows a lasso that catches from further
        range_prop = "AbilityCastRange",              -- 20 m in vdata
        range = 20,
        width = 0.81,                                 -- m_flBulletRadius 32 u
        speed = 3500,                                 -- m_flBulletSpeed
        windup = 0.5,                                 -- AbilityCastDelay
        -- An enemy's cast delay never read, nor did her ability as channeling: the lane came with the
        -- throw, 0.03-0.14 s out, too late to walk or dash (10 throws, 2026-11-10). Her aim preview
        -- (m_previewParticle) came 0.53-0.56 s before each throw, the lasso_idle clip 0.51-0.52 s: the
        -- preview starts the lane along her aim, timed to the throw `windup` after it
        charge_particle = "astro_lasso_preview",
        charge_max = 0.6,                             -- the wind-up and a little past the throw
    },

    -- Infernus is hero_inferno (heroes.vdata, build 6860); ability_fire_bomb is his ESlot_Signature_4
    {
        id = "infernus_concussive_combustion",
        name = "Concussive Combustion",
        hero = "Infernus",
        hero_image = "panorama/images/heroes/inferno_sm_psd.vtex_c",
        hero_id = 1,                                  -- hero_inferno.m_HeroID
        image = "panorama/images/hud/abilities/inferno_bomb_psd.vtex_c",
        ability = "ability_fire_bomb",
        -- Cast on himself (instant): m_FireBombModifier (modifier_firebomb) charges on him for
        -- ExplodeDelay 3.25 s, then he blows for 125 and a 1.25 s stun to all in Radius. The modifier is
        -- m_bIsHidden, as Singularity's was, which never showed on an enemy; its m_ChargeParticle starts
        -- the ring on him, timed to the blast. In the replay (2026-11-10 22-20) the stun came 3.3 s after
        -- the cast, the ring followed him as he walked
        motion = "aura",
        charge_particle = "inferno_fire_bomb_charge.vpcf",
        charge_max = 3.3,                             -- the charge, to just past the blast
        release = 3.25,                               -- ExplodeDelay
        lingers = false,                              -- over once it blows
        radius_prop = "Radius",                       -- 12 m in vdata, +10 m with the third upgrade
        radius = 12,
        big_area = true,
    },

    -- Ivy is hero_tengu (heroes.vdata, build 6860), "tengu" in her art paths. Entangling Thorns is
    -- citadel_ability_tengu_urn (ESlot_Signature_1). Air Drop (_4, citadel_ability_tengu_airlift) is
    -- left out: its hit is the ally she drops, and nothing short of following him tells it
    {
        id = "ivy_entangling_thorns",
        name = "Entangling Thorns",
        hero = "Ivy",
        hero_image = "panorama/images/heroes/tengu_sm_psd.vtex_c",
        hero_id = 20,                                 -- hero_tengu.m_HeroID
        image = "panorama/images/hud/abilities/tengu/tengu_storm_flask_psd.vtex_c",
        ability = "citadel_ability_tengu_urn",
        -- An urn lobbed as a bullet (m_mapWeaponInfos.primary: m_flBulletSpeed 1800, m_flBulletGravityScale
        -- 1.5) after AbilityCastDelay 0.2 s: the weapon reads "citadel_ability_tengu_urn" (2026-11-10).
        -- Where it lands thorns lie for AbilityDuration 4 s, Radius 6 m: DPS 40, a 28% slow, and a root
        -- for whoever stays in them. No hit time: ground not to walk onto, as Spirit Snare's
        motion = "arc",
        speed = 1800,                                 -- m_flBulletSpeed
        gravity_scale = 1.5,                          -- m_flBulletGravityScale
        radius_prop = "Radius",                       -- 6 m
        radius = 6,
        untimed = true,
        stays = 4,                                    -- AbilityDuration
    },

    -- Kelvin is hero_kelvin (heroes.vdata, build 6860); ability_ice_grenade is his ESlot_Signature_1
    {
        id = "kelvin_frost_grenade",
        name = "Frost Grenade",
        hero = "Kelvin",
        hero_image = "panorama/images/heroes/kelvin_sm_psd.vtex_c",
        hero_id = 12,                                 -- hero_kelvin.m_HeroID
        image = "panorama/images/hud/abilities/kelvin/freezing_grenade_psd.vtex_c",
        ability = "ability_ice_grenade",
        -- A grenade lobbed as a bullet (m_mapWeaponInfos.primary: m_flBulletSpeed 1600,
        -- m_flBulletGravityScale 1.0) after AbilityCastDelay 0.1 s: the weapon reads "ability_ice_grenade"
        -- (2026-11-10). It bursts where it lands, or on the first hero it meets on the way (in the replay
        -- of 2026-11-10 23-10 it burst on you in the air), for Damage 60 and a 32% slow within Radius 6.5 m.
        -- His aim preview isn't where it lands: it sat 26-31 m from it, on him
        motion = "arc",
        speed = 1600,                                 -- m_flBulletSpeed
        gravity_scale = 1.0,                          -- m_flBulletGravityScale
        radius_prop = "Radius",                       -- 6.5 m, +2 m with the third upgrade
        radius = 6.5,
        blocked_by = { "hero" },                      -- m_nAbilityTargetTypes ALL: any hero bursts it
        -- m_ExplodeParticle: Debug Mode logs how far from the drawn burst it really went off
        skip = { "kelvin_ice_grenade_explode" },
    },

    -- Lash is hero_lash (heroes.vdata, build 6860). Grapple (citadel_ability_lash) only moves him and
    -- Flog (ability_lash_flog) is left out. None of his particles reached the client in the replay
    -- (2026-11-10 23-24), only his clips and the mark his ultimate puts on you
    {
        id = "lash_ground_strike",
        name = "Ground Strike",
        hero = "Lash",
        hero_image = "panorama/images/heroes/lash_sm_psd.vtex_c",
        hero_id = 31,                                 -- hero_lash.m_HeroID
        image = "panorama/images/hud/abilities/lash/lash_death_slam_psd.vtex_c", -- m_strAbilityImage, as vdata names it
        ability = "citadel_ability_lash_down_strike",
        -- He drives down from the air (StrikeVelocity 50 m/s), or smashes from where he stands, after
        -- AbilityCastDelay 0.15 s, and a wave runs out in front of him at m_flDamageWaveSpeed 4000 u/s.
        -- His clip starts the fan, where he will come down: from his feet along his aim, kept
        -- MinAimAngle 60 deg down at least, to the ground, facing his aim then. It stays there, and hits
        -- the clip's time below plus that dive at StrikeVelocity. On the ground that dive is nothing: it
        -- hit you 0.20-0.24 s after his legsmash clip, 6 hits (2026-11-10). From the air: at 0.08 s
        -- (the cast delay left after his clip) he landed 0.11-0.14 s after the drawn hit, 8 dives of 8
        -- (replay 23-46), so 0.2.
        -- shortcut: the dive taken as straight along his clamped aim; he landed 2.4-3.3 m from the drawn
        -- spot. Debug Mode logs how far along and across his aim, and how long after its hit (his
        -- landing_impact clip)
        charge_anim = {
            ability_groundstrike_legsmash = 0.2,
            ability_groundstrike_airdrop_start = 0.2,
        },
        charge_max = 0.5,                             -- at least; a longer dive keeps it up to its hit
        dive_speed = 1968.5,                          -- StrikeVelocity 50 m/s, in u/s
        dive_pitch = 60,                              -- MinAimAngle
        aim_land = 40,                                -- meters his dive is traced for the ground
        cone_time = 0.2,                              -- the simulator's: the smash from the ground
        motion = "cone",
        range_prop = "Radius",                        -- 10 m in vdata
        range = 12,
        -- shortcut: m_flDamageFrustumAngle read as the full width; a hit from beside the fan says it is half
        angle = 120,
    },
    {
        id = "lash_death_slam",
        name = "Death Slam",
        hero = "Lash",
        image = "panorama/images/hud/abilities/lash/lash_counter_lash_psd.vtex_c", -- m_strAbilityImage
        ability = "citadel_ability_lash_ultimate",
        -- Instant cast: after AbilityCastDelay 0.3 s every enemy hero in his LockonConeAngle 40 deg within
        -- AbilityCastRange 20 m is locked on (m_TargetModifier "lockon"), then he grabs them, lifts and
        -- slams them (ImpactDamage 105, a 40% slow). As Chain Gang's chain, the mark is the tell: no spot
        -- is out of it once you wear it, so only Counterspell answers it. In the replay (2026-11-10 23-24)
        -- "citadel_ability_lash_ultimate/lockon" came on you 0.29 s after his ability_deathslam_lift
        -- clip, from 16.5 m; a cast from 24 m put none on you
        mark_modifier = "lash_ultimate/lockon",
        motion = "target",
        range_prop = "AbilityCastRange",              -- 20 m
        range = 20,
        angle = 40,                                   -- LockonConeAngle
        -- The grab (modifier_lash_grapple_enemy_debuff on you) came 2.32-2.33 s after the mark, 3 slams of
        -- 3 (2026-11-10): his 2.3 s AbilityChannelTime run out. The slam itself, 110 damage, came 1.32 s
        -- after that, too late to block. Counterspell blocks the grab: tapped by hand 1.47-1.86 s after the
        -- mark, 3 of 3 blocked it (2026-11-10, replay 23-36). Timed 0.2 s before the grab, the parry
        -- (Parry Lead before it) comes in that window
        -- shortcut: a sandbox bot holds the whole channel; a Lash who lets go sooner grabs before the
        -- parry. Debug Mode's "modifier on you" lines time the grab against the mark
        hit_delay = 2.1,
    },

    -- Mirage is hero_mirage (heroes.vdata, build 6860); mirage_tornado is his ESlot_Signature_2
    {
        id = "mirage_dust_devil",
        name = "Dust Devil",
        hero = "Mirage",
        hero_image = "panorama/images/heroes/mirage_sm_psd.vtex_c",
        hero_id = 52,                                 -- hero_mirage.m_HeroID
        image = "panorama/images/hud/abilities/mirage/mirage_tornado_psd.vtex_c", -- m_strAbilityImage
        ability = "mirage_tornado",
        -- He turns into the tornado and rides it himself, like Abrams' charge: AbilityCastDelay 0.1 s,
        -- then AbilityCastRange 20 m at TornadoSpeed, lifting every enemy within Radius. The aura sits
        -- on him for the ride: 0.85-0.86 s in game (2026-11-11), which is 20 m at 24 m/s. The copy it
        -- gives its victims is "..._aura_apply", on pawns without the ability
        modifier = "modifier_mirage_tornado_aura",
        motion = "line",
        range_prop = "AbilityCastRange",              -- 20 m in vdata, scales with spirit range
        range = 20,
        width = 4,                                    -- Radius
        speed = 945,                                  -- TornadoSpeed 24 m/s, in u/s
    },
    {
        id = "mirage_fire_scarabs",
        name = "Fire Scarabs",
        hero = "Mirage",
        image = "panorama/images/hud/abilities/mirage/mirage_fire_beetles_psd.vtex_c", -- m_strAbilityImage
        ability = "mirage_fire_beetles",              -- his ESlot_Signature_1
        -- Flies as a bullet (m_mapWeaponInfos.primary; "bullet from mirage_fire_beetles" in game,
        -- 2026-11-11), so there are no `classes`: on_bullet_create matches it by `ability` and its
        -- tracer is followed like Stalker's Mark's. AbilityCharges 2, 1 s apart: each is its own bullet
        particles = { "mirage_flying_beetle_projectile.vpcf" }, -- m_szBulletTravelTracerParticle
        projectile = "mirage_flying_beetle_projectile.vpcf",
        motion = "line",
        -- No cast range (AbilityCastRange 0) or lifetime of its own: weapon_info_base's 2 s
        -- m_flBulletLifetime at its speed, 6000 u. The lane stops at the first wall anyway.
        -- shortcut: m_flBulletGravityScale 0.4 left out, the lane is straight; over 30 m (0.39 s) it
        -- drops ~0.6 m, inside its radius. An arc if a long shot ever hits from under its lane
        range = 152.4,
        width = 1.27,                                 -- m_flBulletRadius 50 u / 39.37
        speed = 3000,                                 -- m_flBulletSpeed
        windup = 0.05,                                -- AbilityCastDelay
    },

    -- Mo & Krill is hero_krill (heroes.vdata, build 6860), "digger" in his particles and clips and
    -- "grappler" in his ability icons. ability_burrow is his ESlot_Signature_2 and ability_throw_sand
    -- (Sand Blast) his ESlot_Signature_3
    {
        id = "krill_burrow",
        name = "Burrow",
        hero = "Mo & Krill",
        hero_image = "panorama/images/heroes/digger_sm_psd.vtex_c",
        hero_id = 18,                                 -- hero_krill.m_HeroID
        image = "panorama/images/hud/abilities/grappler/grappler_spin_psd.vtex_c", -- m_strAbilityImage
        ability = "ability_burrow",
        -- He goes under (m_BurrowModifier, AbilityChannelTime 5 s), then shoots up, tossing everyone in
        -- Radius, and spins (m_SpinModifier: DPS in Radius for SpinDuration 1.5 s). The toss lands as
        -- he breaks the ground: modifier_citadel_tossup came on you 0.01 s before his spin was seen,
        -- and its slow 0.10 s after, so a ring drawn from the spin dodged nothing (2026-11-11). But he
        -- is under for the whole channel, every time: the spin read 5.02 s after the burrow, 5 burrows
        -- of 5, pressed again or not. So the ring rides on him through the last of his time under,
        -- timed to its end, and stays on, untimed, while he spins.
        -- shortcut: AbilityChannelTime as vdata has it (scale_duration); one with duration items is up
        -- later than drawn. Read it off his modifier if a toss ever lands after the ring's time
        modifier = "ability_burrow/modifier_",        -- "..._burrow", then "..._spin": one ring through both.
                                                      -- Its victims' "modifier_spin/modifier_slow" too: a
                                                      -- pawn without the ability doesn't match
        motion = "aura",
        radius_prop = "Radius",                       -- 5.5 m in vdata, scales with spirit range
        radius = 5.5,
        duration_prop = "AbilityChannelTime",         -- 5 s under ground
        duration = 5,
        show_last = 2,                                -- he moves under ground (BonusMoveSpeed): where he
                                                      -- comes up is only known near the end
        -- With Circles ticked in Block Movement the ring is walked out of as it appears and kept out
        -- of. Unticked, your keys are yours until this long before he is up: then a walk or a dash
        -- (in game the dashes were out in 0.16-0.24 s, the walks in 0.31-0.48 s)
        prepare = 0.75,
    },
    {
        id = "krill_sand_blast",
        name = "Sand Blast",
        hero = "Mo & Krill",
        image = "panorama/images/hud/abilities/grappler/grappler_throw_sand_psd.vtex_c", -- m_strAbilityImage
        ability = "ability_throw_sand",
        -- A wave of sand thrown along his aim (m_mapProjectileInfos.primary, modifier_cone_wave_projectile)
        -- at m_flSpeed 3500 u/s after AbilityCastDelay 0.15 s: InitialWidth 5 m wide at him, GrowthPerMeter
        -- 0.5 m wider each meter, so 17.5 m wide at its 25 m. Drawn as a fan from his cast clip
        -- (m_strAG2CastingAction mo_krill_throw_sand; the clip file is ability_throw_sand), timed to the
        -- sand 15 m out: 0.15 + 0.17 s. In game (2026-11-11) the clip came with the cast and the hit
        -- 0.18 s after it from 7.6 m. His cast particle (digger_throw_sand_cast, 0.14 s after the clip)
        -- is left out: it stays on him ~0.8 s, and as a second trigger it drew the fan again 0.9 s after
        -- every cast, "hits in 0.14 s", for a Counterspell that was on cooldown from the real one
        charge_anim = { ability_throw_sand = 0.3 },
        charge_max = 0.3,
        cone_time = 0.3,                              -- the simulator's
        motion = "cone",
        -- 14 m by choice (2026-11-11), against AbilityCastRange 25 m in vdata: drawn at 25 it
        -- covered far more ground than the sand is seen to, and 11 of 25 casts from past 14 m missed.
        -- No `range_prop`: a caster's ability that did read would put the 25 m back
        range = 14,
        -- The wave's own shape: InitialWidth 5 m at him (`base`, a side), 0.25 m wider a side each meter,
        -- so its sides are 2 * atan(0.25) apart and meet 10 m behind him. As the 60 deg fan from his
        -- feet this was, it was 29 m wide at its end against the wave's 17.5 (replay 2026-11-11 12-07)
        base = 2.5,
        angle = 28,
        -- It does reach past that: of 47 casts with where you stood logged (2026-11-11) it hit 27 times, from
        -- 9.2 to 16.3 m and once from 24.2 m, with him aiming 9 to 20 deg down. Cut where his aim met
        -- the ground, as its PBF_OnlyTouchWorld projectile suggested, the wave ended 5-7 m out and
        -- every one of those hits came from past it: it runs along the ground whatever his pitch. The
        -- dust it shows is shorter than what it hits. Across his aim it hit from up to 4.3 m at 14 m
        -- and missed from 4.6 and 5.6 m, against the 6.0 m drawn there: a little wide, on one edge.
        -- The other 18 misses were from inside it, 5 in a row from one spot 12.1 m out: unexplained,
        -- perhaps something in its way (it stops on the world), and not its reach
        sweep_from = 0.1,                             -- the drawn sweep leaves him as the sand does: your
                                                      -- health went 0.21 s after the clip from 9 m,
                                                      -- 0.26 from 13, 0.28 from 16, 0.35 from 24
        -- shortcut: the simulator scores it as a plain 28 deg fan from his feet, narrower than this
        -- beside him; it only ever casts it straight at you
    },
    {
        id = "krill_combo",
        name = "Combo",
        hero = "Mo & Krill",
        image = "panorama/images/hud/abilities/grappler/grappler_combo_psd.vtex_c", -- m_strAbilityImage
        ability = "ability_ult_combo",                -- his ESlot_Signature_4
        -- Cast at one enemy hero within AbilityCastRange 4 m, in a cone in front of him
        -- (m_flTargetingConeAngle 120), with no cast delay: he holds you for AbilityChannelTime 2.4 s,
        -- stunned, at DPS 35. Nothing comes before it: m_TargetModifier read on you 0.04 s before his
        -- ability_combo_ground_start clip was even seen (2026-11-11). So the mark is the tell, as Death
        -- Slam's lock-on is, and only a parry answers it.
        -- A parry tapped as it lands still gets you out: tapped by hand up to 0.09 s after the mark, the
        -- parry was up 0.05 s later and no damage followed, 9 casts of 9; the 5 left alone ticked 12
        -- times each, the first 0.23-0.27 s after the mark. Timed just ahead of that first tick, under
        -- Parry Lead, Evade taps at once.
        -- shortcut: seen with Counterspell bought, and its block never read in the log: whether the
        -- item or the bare parry broke the hold is not known. Evade only parries with the item
        mark_modifier = "ult_combo/modifier_ult_combo_target",
        motion = "target",
        range_prop = "AbilityCastRange",              -- 4 m in vdata
        range = 4,
        angle = 120,                                  -- m_flTargetingConeAngle
        hit_delay = 0.2,
    },

    -- Nurse Hallow is hero_nurse (heroes.vdata, build 6860); ability_nurse_leech_therapy is her
    -- ESlot_Signature_1
    {
        id = "nurse_leech_therapy",
        name = "Leech Therapy",
        hero = "Nurse Hallow",
        hero_image = "panorama/images/heroes/nurse_sm_psd.vtex_c",
        hero_id = 87,                                 -- hero_nurse.m_HeroID
        image = "panorama/images/hud/abilities/nurse/leech_psd.vtex_c", -- m_strAbilityImage
        ability = "ability_nurse_leech_therapy",
        -- A jar of leeches lobbed as a bullet (m_mapWeaponInfos.primary: m_flBulletSpeed 1315,
        -- m_flBulletGravityScale 1.6) after AbilityCastDelay 0.1 s: the weapon reads
        -- "ability_nurse_leech_therapy" (2026-11-11). Where it breaks, enemies within Radius 6.5 m get
        -- its leeches (DPS 23 for AbilityDuration 5 s). Drawn as Frost Grenade is: the lob and the area
        -- it lands in, timed to the landing, gone as it lands.
        -- shortcut: the LeechCount 4 leeches it leaves crawl and lunge at enemies near them for
        -- LeechHuntLifetime 9 s (LeechCrawlRadius 8 m); nothing is drawn for those
        motion = "arc",
        speed = 1315,                                 -- m_flBulletSpeed
        gravity_scale = 1.6,                          -- m_flBulletGravityScale
        radius_prop = "Radius",                       -- 6.5 m in vdata
        radius = 6.5,
        -- shortcut: taken to break on the first hero in its way, as Frost Grenade does
        -- (m_nAbilityTargetTypes ALL_ENEMY); unseen
        blocked_by = { "hero" },
        skip = { "nurse_jar_explosion" },             -- m_ExplodeParticle and m_MissedJarImpactParticle
    },

    -- Paige is hero_bookworm (heroes.vdata, build 6860). Her slots are ability_bookworm_dragonfire,
    -- _knightbarrier (a shield on an ally, left out), _aoemagic and _knightcharge
    {
        id = "paige_bookwyrm",
        name = "Bookwyrm",
        hero = "Paige",
        hero_image = "panorama/images/heroes/bookworm_sm_psd.vtex_c",
        hero_id = 67,                                 -- hero_bookworm.m_HeroID
        image = "panorama/images/hud/abilities/bookworm/bookworm_dragon_psd.vtex_c", -- m_strAbilityImage
        ability = "ability_bookworm_dragonfire",
        -- She lobs a book (a bullet: m_flBulletSpeed 1000, gravity 1.0); where it lands a dragon comes
        -- out after StartupDelay 0.3 s (m_mapProjectileInfos.primary, _class bookwormdragon_projectile)
        -- and flies on along the ground for DragonTravelRange at m_flSpeed 500 u/s, breathing fire:
        -- DPS 30 within Radius of its path, the ground left burning GroundFlameDuration 3 s. The dragon
        -- is what is drawn, a lane from it to the end of its flight.
        -- shortcut: the book's lob and landing are not drawn.
        -- In game (2026-11-11) the dragon is CProjectile_BookwormDragon_Projectile, seen ~0.8 s after
        -- her throw clip, and its Damage 60 landed 0.1-1.1 s after that. It climbs as it comes out
        -- (DragonUpwardSpeed 400) and its lane, along its own flight, went up into the air: you stood
        -- under it 2.5 m off its middle and burned, 8 casts of 8. The fire is on the ground: `flat`
        flat = true,
        particles = { "bookworm_dragonfire.vpcf" },   -- m_particle; the .vpcf keeps it off _projectile (the
                                                      -- book), _cast, _spawn, _aura, _debuff and _impact
        projectile = "bookworm_dragonfire.vpcf",
        bullet = "!",                                 -- no weapon reads this: the book is a bullet named for
                                                      -- the ability, and would be drawn as the dragon's lane
        motion = "line",
        range_prop = "DragonTravelRange",             -- 20 m in vdata, scales with spirit range
        range = 20,
        width = 4,                                    -- Radius
        speed = 500,                                  -- m_flSpeed, DragonRangePerSecond
    },
    {
        id = "paige_captivating_read",
        name = "Captivating Read",
        hero = "Paige",
        image = "panorama/images/hud/abilities/bookworm/bookworm_blindinglight_psd.vtex_c", -- m_strAbilityImage
        ability = "ability_bookworm_aoemagic",
        -- Ground-targeted circle (LOCATION_GROUND, SHAPE_CIRCLE) within AbilityCastRange 30 m, after
        -- AbilityCastDelay 0.15 s: it goes off DetonationDelay 1.25 s on for Damage 90 and a root
        -- (ImmobilizeDuration 1 s) within Radius. Nothing flies: the area's own tell
        -- (m_AreaModifier.m_AreaWarningEffect) marks it, as Radiant Daggers' does.
        -- In game (2026-11-11) the tell reaches an enemy's client 0.13 s after her
        -- ability_excalibur_cast clip, but its first control point is on Paige: every area was drawn
        -- on her (replay 12-56-39), not where it fell. Logged in game (2026-11-11): CP0 0 m from her
        -- at the cast, CP1 5-6 m and nearing as she walked to it, CP2 a fixed point 40-47 m off
        -- (beyond her 30 m range; the furthest point drew there). The area is CP1.
        warning_cp = 1,
        particles = { "bookworm_aoe.vpcf" },          -- the .vpcf keeps it off _explode, _cast and _slow
        warning = "bookworm_aoe.vpcf",
        motion = "arc",
        radius_prop = "Radius",                       -- 7.5 m in vdata, scales with spirit range
        radius = 7.5,
        gravity_scale = 0,
        duration_prop = "DetonationDelay",            -- 1.25 s from the tell to the blast
        duration = 1.25,
    },
    {
        id = "paige_rallying_charge",
        name = "Rallying Charge",
        hero = "Paige",
        image = "panorama/images/hud/abilities/bookworm/bookworm_charge_psd.vtex_c", -- m_strAbilityImage
        ability = "ability_bookworm_knightcharge",
        -- After AbilityChannelTime 0.7 s, KnightCount 5 knights abreast (KnightPositionSpread 1.8 m
        -- apart), in WaveCount 2 waves, charge across the map along the ground at m_flSpeed 2000 u/s
        -- (m_mapProjectileInfos: knightcharge_projectile and knightchargeleading_projectile, one
        -- particle): Damage 125 and StunDuration 1 s to each enemy they run down. Each knight is its
        -- own lane, KnightChargeWidth across.
        -- shortcut: a straight lane to the first wall; the knights follow the ground and go round or
        -- over what is in their way (KnightNavSearchDistance, KnightMaxJumpHeight).
        -- In game (2026-11-11) the knights (C_Projectile_KnightCharge_Projectile, four, and one
        -- CProjectile_KnightChargeLeading_Projectile) were first seen 0.17-0.34 s before they hit, once
        -- after: 6 hits of 125+ in 10 casts, none dodged. But her ability_knights_charge clip starts
        -- with the cast, 0.7 s before ability_knights_charge_cast sends them, and the hit came
        -- 1.1-1.5 s after the key. So the lane is drawn along her aim from that clip, as wide as the
        -- five of them, timed to their leaving
        charge_anim = "ability_knights_charge",
        charge_max = 1.0,                             -- the channel and a little past: then the knights' own
        release = 0.7,                                -- AbilityChannelTime
        charge_width = 4.5,                           -- five abreast: 4 * KnightPositionSpread 1.8 m, and half
                                                      -- a knight each end
        min_speed = 20,                               -- she doesn't dash: the lane on her is the wind-up's alone
        particles = { "bookworm_ultimate.vpcf" },     -- m_particle; the .vpcf keeps it off _cast and
                                                      -- _channel_cast
        projectile = "bookworm_ultimate.vpcf",
        motion = "line",
        range_prop = "AbilityCastRange",              -- 600 m in vdata: the whole map
        range = 600,
        width = 0.85,                                 -- KnightChargeWidth 1.7 m, halved
        speed = 2000,
    },

    -- Paradox is hero_chrono (heroes.vdata, build 6860). Her slots are citadel_ability_chrono_pulse_grenade,
    -- _time_wall, _kinetic_carbine (a buff on her own gun, left out) and _swap
    {
        id = "paradox_pulse_grenade",
        name = "Pulse Grenade",
        hero = "Paradox",
        hero_image = "panorama/images/heroes/chrono_sm_psd.vtex_c",
        hero_id = 10,                                 -- hero_chrono.m_HeroID
        image = "panorama/images/hud/abilities/chrono/chrono_time_bomb_psd.vtex_c", -- m_strAbilityImage
        ability = "citadel_ability_chrono_pulse_grenade",
        -- A grenade lobbed as a bullet (m_mapWeaponInfos.primary: m_flBulletSpeed 1600,
        -- m_flBulletGravityScale 1.0) after AbilityCastDelay 0.2 s: the weapon reads
        -- "citadel_ability_chrono_pulse_grenade" (2026-11-11). Where it lands it pulses every
        -- PulseInterval 0.8 s for AbilityDuration 3.2 s, PulseDamage 35 within Radius 5.5 m, and
        -- RadiusIncreasePerPulse 1 m wider each time. Drawn as Leech Therapy is: the lob and its first
        -- pulse's area, timed to the landing.
        -- shortcut: the pulses after the first, each 1 m wider, are not drawn; draw the field while it
        -- is up if standing next to it gets you hit
        motion = "arc",
        speed = 1600,                                 -- m_flBulletSpeed
        gravity_scale = 1.0,                          -- m_flBulletGravityScale
        radius_prop = "Radius",                       -- 5.5 m in vdata, scales with spirit range
        radius = 5.5,
        -- shortcut: taken to break on the first hero in its way, as Frost Grenade does
        -- (m_nAbilityTargetTypes ALL_ENEMY); unseen
        blocked_by = { "hero" },
        skip = { "chrono_time_bomb" },                -- m_AreaEffect, _preview and the tracer: the bullet
                                                      -- alone draws it
    },
    {
        id = "paradox_swap",
        name = "Paradoxical Swap",
        hero = "Paradox",
        image = "panorama/images/hud/abilities/chrono/chrono_swap_psd.vtex_c", -- m_strAbilityImage
        ability = "citadel_ability_chrono_swap",
        -- A bolt fired as a bullet (m_flBulletSpeed 3500, gravity 0, m_flBulletRadius 32.4 u) after
        -- AbilityCastDelay 0.15 s: the weapon reads "citadel_ability_chrono_swap" (2026-11-11). The
        -- first enemy hero it hits trades places with her and takes SwapDamage 150.
        -- shortcut: the lane runs AbilityCastRange 25 m; the bullet's own m_flRange is 254 m. Not
        -- measured in game: a swap from past 25 m means the range is the bullet's
        skip = { "chrono_swap" },                     -- the tracer and the swap's effects: the bullet draws it
        motion = "line",
        range_prop = "AbilityCastRange",              -- 25 m in vdata, scales with spirit range
        range = 25,
        width = 0.82,                                 -- m_flBulletRadius 32.4 u / 39.37 u per meter
        speed = 3500,                                 -- m_flBulletSpeed
    },

    -- Pocket is hero_synth (heroes.vdata, build 6860). His slots are synth_barrage, _plasma_flux (Flying
    -- Cloak), _pulse (Enchanter's Satchel) and _affliction; the cloak and the satchel are left out
    {
        id = "pocket_barrage",
        name = "Barrage",
        hero = "Pocket",
        hero_image = "panorama/images/heroes/synth_sm_psd.vtex_c",
        hero_id = 50,                                 -- hero_synth.m_HeroID
        image = "panorama/images/hud/abilities/synth/synth_barrage_psd.vtex_c", -- m_strAbilityImage
        ability = "synth_barrage",
        -- After AbilityCastDelay 0.3 s he channels AbilityChannelTime 2 s, firing ProjectileAmount 4
        -- missiles m_flAttackInterval 0.5 s apart, each a bullet (m_flBulletSpeed 2300, gravity 0,
        -- m_flBulletRadius 10 u) straight at his crosshair: the weapon reads "synth_barrage"
        -- (2026-11-11). Each bursts where it hits for DamagePerProjectile 32 and a 24% slow within
        -- Radius 4.5 m. Drawn per missile: its lane and the burst at its end, timed to the hit
        motion = "line",
        range = 254,                                  -- m_flRange 10000 u; AbilityCastRange is 0
        width = 0.25,                                 -- m_flBulletRadius 10 u
        speed = 2300,                                 -- m_flBulletSpeed
        radius_prop = "Radius",                       -- 4.5 m in vdata, +3 m with the third upgrade
        radius = 4.5,
        blocked_by = { "hero" },                      -- m_nAbilityTargetTypes ALL_ENEMY, no penetration
    },
    {
        id = "pocket_affliction",
        name = "Affliction",
        hero = "Pocket",
        image = "panorama/images/hud/abilities/synth/synth_affliction_psd.vtex_c", -- m_strAbilityImage
        ability = "synth_affliction",
        -- Cast on himself (no target): AbilityCastDelay 0.6 s, then every enemy within Radius 9 m takes
        -- the debuff (DPS 32 for DebuffDuration 10 s). Its m_CastParticle starts the ring on him, timed
        -- to the cast delay's end, so a dash out of its edge or a parry beats it.
        -- shortcut: the cast particle reaching an enemy's client is unseen (you only played him
        -- yourself, 2026-11-11); if no ring shows on an enemy Pocket, Debug Mode's "anim" lines name his
        -- cast clip for `charge_anim`
        motion = "aura",
        charge_particle = "pocket_affliction_cast",
        charge_max = 0.65,                            -- the cast delay, to just past the hit
        release = 0.6,                                -- AbilityCastDelay
        lingers = false,                              -- over once it hits
        radius_prop = "Radius",                       -- 9 m in vdata, scales with spirit range
        radius = 9,
    },

    -- Rat King is hero_ratking (heroes.vdata, build 6860). His slots are ability_ratking_scrap_grenade,
    -- _ratnibble, _ratarmor (a buff on him, left out) and _standard_bearer, the ultimate
    {
        id = "ratking_scrap_grenade",
        name = "Scrap Grenade",
        hero = "Rat King",
        hero_image = "panorama/images/heroes/ratking_sm_psd.vtex_c",
        hero_id = 84,                                 -- hero_ratking.m_HeroID
        image = "panorama/images/hud/abilities/ratking/ratking_grenade_psd.vtex_c", -- m_strAbilityImage
        ability = "ability_ratking_scrap_grenade",
        -- A grenade thrown as a projectile entity (m_mapProjectileInfos.primary: m_flSpeed 1300,
        -- m_flUpSpeed 300, m_flGravityScale 1.85); none of his casts logged a bullet (2026-11-11). It
        -- lands, blows Detonations 3 times, shrapnel at all within ShrapnelSphereRadius 8 m, and after
        -- each blast but the last hops on (BounceGrenadeSpeed 1200) towards a hero within 30 m
        -- (m_flBounceTargetDistanceCheck 1200 u), straight up with none. Followed hop to hop, its area
        -- drawn where each hop comes down. In the replay (2026-11-11 15-14-26) it blew 0.7-0.75 s after
        -- it landed, then rose out of sight
        particles = { "ratking_scrap_grenade_projectile.vpcf" }, -- m_particle; the .vpcf keeps it off
        projectile = "ratking_scrap_grenade_projectile.vpcf",    -- _preview, _trail, _model and _halo
        motion = "arc",
        gravity_scale = 1.85,                         -- m_flGravityScale
        radius_prop = "ShrapnelSphereRadius",         -- 8 m in vdata, scales with spirit range
        radius = 8,
        -- FirstBounceDetonateTimer 0.8, AdditionalBounceDetonateTimer 0.7, FinalBounceDetonateTimer 1.5
        -- shortcut: the third upgrade's 4th detonation (0.8, 0.7, 0.7, 1.5) is timed 1.5 on its third
        -- landing; read Detonations if that one hits early
        arm = { 0.8, 0.7, 1.5 },
    },
    {
        id = "ratking_rule_ratannia",
        name = "Rule, Ratannia!",
        hero = "Rat King",
        image = "panorama/images/hud/abilities/ratking/ratking_flag_psd.vtex_c", -- m_strAbilityImage
        ability = "ability_ratking_standard_bearer",
        -- The slam only: he charges with his flag (not drawn), leaps (m_flPlantLeapRiseDuration 0.6 s,
        -- m_flPlantLeapHoverDuration 0.1 s) and slams it down at m_flPlantLeapSlamSpeed 1500 u/s; it blows
        -- m_flExplodeTimer 0.25 s later for Damage 200 within Radius 20 m. Its m_AnticipationParticle is a
        -- ground decal (C_OP_RenderProjected) at its CP0, whose rays emit for 0.25 s: in the replay
        -- (2026-11-11 15-14-26) they shot out 0.25 s before the blast, as he came down
        -- shortcut: timed 0.25 s from that tell; if it reaches the client earlier (at the leap, ~1 s
        -- before), Debug Mode's "particle ...anticipation" against the hit says so: set `duration` to it
        particles = { "ratking_standard_bearer_anticipation.vpcf" }, -- the .vpcf keeps it off its children
        warning = "ratking_standard_bearer_anticipation.vpcf",
        motion = "arc",
        radius_prop = "Radius",                       -- 20 m in vdata, +8 m with the second upgrade
        radius = 20,
        gravity_scale = 0,
        duration = 0.25,                              -- m_flExplodeTimer
    },

    -- Seven is hero_gigawatt (heroes.vdata, build 6860). His slots are citadel_ability_lightning_ball,
    -- _static_charge, ability_power_surge and citadel_ability_storm_cloud
    {
        id = "seven_lightning_ball",
        name = "Lightning Ball",
        hero = "Seven",
        hero_image = "panorama/images/heroes/gigawatt_sm_psd.vtex_c",
        hero_id = 2,                                  -- hero_gigawatt.m_HeroID
        image = "panorama/images/hud/abilities/giga_ball_psd.vtex_c", -- m_strAbilityImage
        ability = "citadel_ability_lightning_ball",
        -- A ball thrown straight (m_mapProjectileInfos.primary: m_flSpeed 1700, gravity 0) after
        -- AbilityCastDelay 0.2 s that zaps every enemy within ShockRadius 4.25 m as it goes, for
        -- MaxLifetime 5 s. It sticks to the first wall (PBF_StickToWorld) and keeps zapping there, and it
        -- slows to m_flHitSpeed 2 m/s while on a hero (m_flNonHeroHitSpeed 3.5 m/s on a trooper).
        -- shortcut: the lane runs on at full speed past a hero it slows on, so a hit behind him is timed
        -- early; time it to the slowdown if Evade dodges a ball that never reached you
        particles = { "gigawatt_lightning_ball.vpcf" }, -- m_particle; the .vpcf keeps it off _zap/_explode
        projectile = "gigawatt_lightning_ball.vpcf",
        -- The ball reaches the client late: in game (2026-11-11, every cast of a replay from ~15-20 m) it was
        -- first seen within 0.26 s of its zap coming on you, before or after, too late for anything but
        -- Counterspell. His clip
        -- comes first: from 15.3 m, "ability_lightning_ball" was seen 0.06 s after the cast, and the zap
        -- came on you 0.46 s after the clip. That is the ball leaving 0.14 s after the clip (the 0.2 s cast
        -- delay, less the clip's 0.06) and its 4.25 m edge covering the other 11 m at 1700 u/s in 0.26 s.
        -- shortcut: one clip timed; if a thrown lane is late or early, Debug Mode's "thrown by" and
        -- "modifier on you: ...lightningball" lines time it
        throw_anim = "ability_lightning_ball",
        throw_delay = 0.14,
        -- Once on you it zaps every TickRate 0.1 s for as long as you stay in it, and Counterspell only
        -- holds it off 0.8 s (2026-11-11): walk out of it instead
        around = true,
        motion = "line",
        range = 216,                                  -- MaxLifetime 5 s at 1700 u/s; the first wall ends it sooner
        width = 4.25,                                 -- ShockRadius: the zap reaches that far off the ball
        speed = 1700,                                 -- m_flSpeed
        -- stuck on a wall, it zaps all around it until it runs out: the lane's end, or the ball once stopped
        radius_prop = "ShockRadius",                  -- 4.25 m in vdata, scales with spirit range
        radius = 4.25,
    },
    {
        id = "seven_static_charge",
        name = "Static Charge",
        hero = "Seven",
        image = "panorama/images/hud/abilities/giga_static_psd.vtex_c", -- m_strAbilityImage
        ability = "citadel_ability_static_charge",
        -- Cast at one enemy hero within AbilityCastRange 15 m, in m_flTargetingConeAngle 20 deg in front of
        -- him, after AbilityCastDelay 0.2 s: m_StaticChargeModifier (modifier_citadel_staticcharge) sits
        -- on the target for ShockDelay 3.5 s (m_bDurationReducible false), then stuns him and every
        -- enemy within ShockRadius 5 m for StunDuration 0.9 s. As Death Slam's lock-on, the charge is the
        -- tell: no spot is out of it once you wear it, so only Counterspell answers it.
        -- shortcut: hit_delay is ShockDelay as vdata has it, not timed in game, and a charge on an ally
        -- near you (its 5 m stun reaches you too) is not drawn. Debug Mode's "modifier on you" lines
        -- give the real name and time if it parries early or late
        mark_modifier = "staticcharge",
        motion = "target",
        range_prop = "AbilityCastRange",              -- 15 m in vdata, +5 m with the second upgrade
        range = 15,
        angle = 20,                                   -- m_flTargetingConeAngle
        hit_delay = 3.5,                              -- ShockDelay
    },

    -- Rem is hero_familiar (heroes.vdata, build 6860). Pillow Toss is ability_familiar_ability02 (his
    -- ESlot_Signature_1) and Nap Time ability_familiar_ability01 (ESlot_Signature_4)
    {
        id = "rem_pillow_toss",
        name = "Pillow Toss",
        hero = "Rem",
        hero_image = "panorama/images/heroes/familiar_sm_psd.vtex_c",
        hero_id = 79,                                 -- hero_familiar.m_HeroID
        image = "panorama/images/hud/abilities/familiar/familiar_pillow_psd.vtex_c", -- m_strAbilityImage
        ability = "ability_familiar_ability02",
        -- A pillow thrown (m_mapProjectileInfos.primary, citadel_projectile: m_flSpeed 1300, m_flUpSpeed
        -- 120, m_flGravityScale 0.5) after AbilityCastDelay 0.3 s. It bursts on the first enemy or wall
        -- it hits (PBF_DetonateOnHitTarget | OnHitWorld): Damage 75, a toss and a fading slow within
        -- Radius 5 m. Near flat (it drops under 1 m over 25 m), so drawn as a lane, as Rallying Charge is.
        -- In game (2026-11-11) the pillow raised no particle event: the entity walk found it 0.26 s after
        -- his toss clip, hits came 0.01-0.1 s after that up close, and 0.31 s before its hit from 25 m.
        -- His ability_hit_the_sack_charge clip came 0.07-0.1 s after the key and his _toss clip 0.30 s
        -- after it, as the pillow left. So the lane is drawn along his aim from the charge clip, timed
        -- to its leaving; the pillow's own lane takes over once it is found
        charge_anim = "ability_hit_the_sack_charge",
        release = 0.3,                                -- AbilityCastDelay: his toss clip
        charge_max = 0.65,                            -- and the 0.26 s until the pillow is seen, with some to spare
        min_speed = 20,                               -- he doesn't dash: the lane on him is the wind-up's alone
        particles = { "familiar_pillow_projectile.vpcf" }, -- m_particle; the .vpcf keeps it off _cast and _explode
        projectile = "familiar_pillow_projectile.vpcf",
        motion = "line",
        range_prop = "AbilityCastRange",              -- 40 m in vdata (hidden): about where a flat throw comes down
        range = 40,
        width = 0.89,                                 -- m_flTriggerRadius 35 u
        speed = 1300,                                 -- m_flSpeed
        radius_prop = "Radius",                       -- the burst where it hits a wall: 5 m, +2 m with the second upgrade
        radius = 5,
        blocked_by = { "hero" },                      -- m_nAbilityTargetTypes ALL_ENEMY, PBF_DetonateOnHitTarget
    },
    {
        id = "rem_nap_time",
        name = "Nap Time",
        hero = "Rem",
        image = "panorama/images/hud/abilities/familiar/familiar_sleep_psd.vtex_c", -- m_strAbilityImage
        ability = "ability_familiar_ability01",
        -- Instant cast: after AbilityCastDelay 0.18 s he floats up and channels for AbilityChannelTime
        -- 1.9 s (m_flStatScale 0: duration items don't stretch it; CANNOT_CANCEL_DURING_CHANNEL), staring
        -- at every enemy hero in his view within Radius 19 m (m_StaringModifier "staring", a 20% slow);
        -- as it ends they fall asleep for SleepDuration 4 s. As Death Slam's lock-on, the stare on you is
        -- the tell: no spot is out of it once you wear it, so only Counterspell answers it.
        -- shortcut: unseen from an enemy's side. Taken from vdata: the stare as a hidden modifier on you
        -- from the channel's start, the sleep 1.9 s on. A stare that comes on late (you walked into his
        -- view mid-channel) is timed late. Debug Mode's "modifier on you" lines time the sleep
        -- ("..._ability01/effect") against the stare
        mark_modifier = "familiar_ability01/staring",
        motion = "target",
        range_prop = "Radius",                        -- 19 m in vdata, +3 m with the second upgrade
        range = 19,
        angle = 35,                                   -- m_flTargetingConeAngle, his preview's cone (the sim's)
        hit_delay = 1.9,                              -- AbilityChannelTime
    },

    -- Silver is hero_werewolf (heroes.vdata, build 6860). Her slots are ability_werewolf_unloadgun (Slam
    -- Fire, a buff on her gun, left out), _kickflip (Boot Kick), _netshot (Entangling Bola) and
    -- _transformation (Lycan Curse), which swaps in her wolf form's _frenzy (Go For The Throat),
    -- _maulingleap (Mauling Leap) and _cripplingslash (Tail Whack). Both forms are the one hero 80.
    -- Each wind-up is told by her own clip (models/heroes_wip/werewolf/clips and transform/clips), as an
    -- enemy's cast delay never reaches the client.
    -- shortcut: every clip's lead on the hit is vdata's cast delay, unmeasured on an enemy Silver; Debug
    -- Mode's "anim" and "you lost health" lines time them
    {
        id = "silver_boot_kick",
        name = "Boot Kick",
        hero = "Silver",
        hero_image = "panorama/images/heroes/werewolf_sm_psd.vtex_c",
        hero_id = 80,                                 -- hero_werewolf.m_HeroID
        image = "panorama/images/hud/abilities/werewolf/werewolf_jumpback_psd.vtex_c", -- m_strAbilityImage
        ability = "ability_werewolf_kickflip",
        -- After AbilityCastDelay 0.25 s she dashes forward through AbilityChannelTime 0.35 s and kicks the
        -- first enemy hero she meets, then flips back off him. m_LeapingModifier sits on her for the dash:
        -- it read "ability_werewolf_kickflip/leaping" on you 0.31 s after the key (2026-11-11). Mauling
        -- Leap's is the same class, "ability_werewolf_maulingleap/leaping"
        modifier = "kickflip/leaping",
        min_speed = 20,                               -- m/s, under the dash's ~30: her run is ~8
        charge_anim = "ability_boot_kick_start",
        charge_max = 0.35,                            -- the cast delay, then the dash's own lane
        release = 0.25,                               -- AbilityCastDelay
        motion = "line",
        -- AbilityCastRange 10.6 m in the 0.35 s channel: 1190 u/s on average, ~1270 at the top of
        -- m_LeapingSpeedCurve, which is flat from 5% to 88% of it
        speed = 1270,
        -- the kick is LeapRadius 1.7 m around LeapForwardOffset 2.5 m ahead of her: 10.6 + 2.5 m. No
        -- `range_prop`, as AbilityCastRange alone would cut the reach short
        range = 13.1,
        width = 1.7,                                  -- LeapRadius
    },
    {
        id = "silver_entangling_bola",
        name = "Entangling Bola",
        hero = "Silver",
        image = "panorama/images/hud/abilities/werewolf/werewolf_bola_psd.vtex_c", -- m_strAbilityImage
        ability = "ability_werewolf_netshot",
        -- Thrown as a bullet (m_mapWeaponInfos.primary): "bullet from ability_werewolf_netshot" in game
        -- (2026-11-11), so on_bullet_create matches it by `ability`. It slows and locks out movement
        -- abilities and stamina for DebuffDuration 1.5 s.
        -- shortcut: m_flBulletGravityScale 0.2 drops it ~0.3 m over 30 m, drawn straight, as Sleep Dagger
        motion = "line",
        -- no cast range (AbilityCastRange 0) or lifetime of its own: weapon_info_base's 2 s at its speed
        range = 152.4,
        width = 0.97,                                 -- m_flBulletRadius 38 u / 39.37
        speed = 3000,                                 -- m_flBulletSpeed
        -- no `blocked_by`: it hits only her enemies (HERO_ENEMY), and "hero" would also end it on her allies
        -- Her throw clip (standing or moving) starts the lane along her aim, timed to the throw
        charge_anim = { ability_entangling_bola_idle = 0.24, ability_entangling_bola_haspath = 0.24 },
        charge_max = 0.3,
        release = 0.24,                               -- AbilityCastDelay
        min_speed = 20,                               -- she doesn't dash: the lane on her is the wind-up's alone
    },
    {
        id = "silver_go_for_the_throat",
        name = "Go For The Throat",
        hero = "Silver",
        image = "panorama/images/hud/abilities/werewolf/werewolf_bite_psd.vtex_c", -- m_strAbilityImage
        ability = "ability_werewolf_frenzy",
        -- Wolf form. A bite at every enemy in a cone in front of her (TARGETING_SHAPE_CONE) after
        -- AbilityCastDelay 0.2 s, more the lower their health. Drawn as a fan from her bite clip
        charge_anim = { ability_go_for_the_throat_idle = 0.2, ability_go_for_the_throat_haspath = 0.2 },
        charge_max = 0.3,
        cone_time = 0.2,                              -- the simulator's
        motion = "cone",
        range_prop = "AbilityCastRange",              -- 7.5 m in vdata
        range = 7.5,
        -- shortcut: read as the full width, like Rend's; a bite from beside the fan says it is the half
        angle_prop = "TargetingConeAngle",
        angle = 40,
    },
    {
        id = "silver_mauling_leap",
        name = "Mauling Leap",
        hero = "Silver",
        image = "panorama/images/hud/abilities/werewolf/werewolf_wolfforward_psd.vtex_c", -- m_strAbilityImage
        ability = "ability_werewolf_maulingleap",
        -- Wolf form. After AbilityCastDelay 0.35 s she leaps forward through AbilityChannelTime 0.55 s and
        -- mauls the first enemy she meets: "ability_werewolf_maulingleap/leaping" read on you 0.39-0.41 s
        -- after the key (2026-11-11). As Boot Kick: her clip, then her dash
        modifier = "maulingleap/leaping",
        min_speed = 20,
        charge_anim = "ability_mauling_leap_stand_start",
        charge_max = 0.45,
        release = 0.35,                               -- AbilityCastDelay
        motion = "line",
        speed = 1300,                                 -- AbilityCastRange 18.1 m over the 0.55 s channel
        range = 18.4,                                 -- 18.1 m and LeapForwardOffset 0.3 m
        width = 2.8,                                  -- LeapRadius
    },
    {
        id = "silver_tail_whack",
        name = "Tail Whack",
        hero = "Silver",
        image = "panorama/images/hud/abilities/werewolf/werewolf_tailwhack_psd.vtex_c", -- m_strAbilityImage
        ability = "ability_werewolf_cripplingslash",
        -- Wolf form. Cast on herself: after AbilityCastDelay 0.15 s she smashes every enemy within SlashRadius
        -- 10 m (SlashHeight 3 m) for Damage 45, a 2 s disarm and a slow. Her clip starts the ring on her,
        -- timed to the smash: too soon to walk out of, so mostly a parry
        charge_anim = "ability_tail_whack",
        charge_max = 0.25,
        release = 0.15,                               -- AbilityCastDelay
        lingers = false,                              -- over once it hits
        motion = "aura",
        radius_prop = "SlashRadius",                  -- 10 m in vdata
        radius = 10,
    },
}
