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
--                 `modifier`
--
-- "cone" only:
--   range_prop    ability property holding the cone's reach
--   range         reach in meters when range_prop is missing (default 5)
--   angle_prop    ability property holding the cone's full width in degrees
--   angle         full width in degrees when angle_prop is missing (default 60)
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
--                 that long after it lands, and its area stays on it, timed, while it lies there
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
--                 with no particle of its own (Rising Ram's cast delay)
--   charge_max    seconds a charge can last, from its particle or clip to the dash
--   unblockable   true when Counterspell doesn't block it: Evade never spends it on its lane
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
--                 (Call Bell, blown when he shoots it), so it is a danger for as long as it is drawn
--   bullet        weapon name substring if the game fires it as a bullet (defaults to `ability`);
--                 Debug Mode logs your own bullets that match no spell, to find it
--   speed         projectile speed in units/s; a bullet's lane stays drawn for its flight time
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
        windup = 0.25,                                -- AbilityCastDelay
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
}
