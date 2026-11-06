--[[
    Violet - Umbrella hero assistant
    ---------------------------------
    Ability 1  Living Ink   (ability_artist_homingbrush)
    Ability 2  Flow State   (ability_artist_rollingprojectile)
    Ability 3  Still Life   (ability_artist_tether)
    Ability 4  Abstract Landscape (ability_artist_bamboogrove)

    Combo key: empowers ink, sends a flow-state brush at the target, flicks it,
    then starts and tracks a Still Life sketch. Ult is optional and only fires
    when enough enemies are stacked around you.

    Everything is menu driven. Nothing runs unless the local hero is Violet.
]]

-- ============================================================
-- Constants
-- ============================================================
local VERSION = "1.0.0"
local HERO_ID = 86
local UNIT_METER = 37.7358490566 -- Source 2 units per meter

local ABILITY = {
    INK = "ability_artist_homingbrush",
    FLOW = "ability_artist_rollingprojectile",
    SKETCH = "ability_artist_tether",
    ULT = "ability_artist_bamboogrove",
}

-- Tuning that does not need a menu entry
local FLOW_SPEED_MPS = 20      -- brush travel speed
local FLOW_MIN_FLICK = 0.35    -- never flick before this
local FLOW_MAX_FLICK = 1.6     -- give up steering after this
local INK_RECAST_DELAY = 1.2   -- let the empowered shots leave the barrel
local CHANNEL_GRACE = 0.45     -- keep tracking briefly after a sketch ends
local ACTION_COOLDOWN = 0.18   -- global delay between combo actions

-- ============================================================
-- Menu
-- ============================================================
local menu_combat = Menu.Create("Heroes", "Hero List", "hero_artist", "Violet", "Combat")

local ui_enable = menu_combat:Switch("Enable Script", true)
ui_enable:Icon("\u{f00c}")
ui_enable:ToolTip("Master switch for the Violet assistant")

local ui_key = menu_combat:Bind("Combo Key", Enum.ButtonCode.KEY_MOUSE5)
ui_key:Icon("\u{f084}")
ui_key:ToolTip("Hold (or toggle) to execute the ability combo on the best target")
ui_key:Properties("Violet Combo", nil, true)

local ui_mode = menu_combat:Combo("Trigger Mode", { "Hold Key", "Toggle Key" }, 0)
ui_mode:Icon("\u{f0c9}")
ui_mode:ToolTip("Hold = combo only while the key is down. Toggle = press once to start/stop")

local ui_auto_fire = menu_combat:Switch("Auto Fire", true)
ui_auto_fire:Icon("\u{f1e6}")
ui_auto_fire:ToolTip("Hold the attack button while a valid target is acquired")

local ui_smooth = menu_combat:Slider("Aim Smooth", 1, 20, 6, "%d")
ui_smooth:Icon("\u{f0b0}")
ui_smooth:ToolTip("Lower snaps faster. Only affects aim assist while casting/tracking")

local ui_psilent = menu_combat:Switch("Psilent Aim", true)
ui_psilent:Icon("\u{f06e}")
ui_psilent:ToolTip("Hide camera snap from the server where possible")

local ui_fov = menu_combat:Slider("Target FOV", 5, 90, 35, "%d")
ui_fov:Icon("\u{f06e}")
ui_fov:ToolTip("Maximum crosshair angle to acquire a target")

local ui_range = menu_combat:Slider("Max Range (m)", 5, 50, 25, "%d")
ui_range:Icon("\u{f124}")
ui_range:ToolTip("Maximum engagement distance")

local ui_lock = menu_combat:Switch("Target Lock", true)
ui_lock:Icon("\u{f02d}")
ui_lock:ToolTip("Keep the same target during the combo instead of swapping mid-channel")

-- ------------------------------------------------------------
local menu_ab = Menu.Create("Heroes", "Hero List", "hero_artist", "Violet", "Abilities")

local ui_ult = menu_ab:Switch("Auto Abstract Landscape", false)
ui_ult:Icon("\u{f1fc}")
ui_ult:ToolTip("Ultimate when enough enemies are close. Best in team fights")

local ui_ult_min = menu_ab:Slider("Ult Min Enemies", 1, 5, 2, "%d")
ui_ult_min:Icon("\u{f0c0}")
ui_ult_min:ToolTip("Only ult when at least this many enemies are within the grove radius")

local ui_flow = menu_ab:Switch("Use Flow State", true)
ui_flow:Icon("\u{f1d8}")
ui_flow:ToolTip("Send the brush through the target and flick it for the burst")

local ui_sketch = menu_ab:Switch("Use Still Life", true)
ui_sketch:Icon("\u{f03e}")
ui_sketch:ToolTip("Start a sketch and lock the crosshair onto the subject until the stun lands")

local ui_ink = menu_ab:Switch("Use Living Ink", true)
ui_ink:Icon("\u{f1fc}")
ui_ink:ToolTip("Empower the next bullets with steering ink")

local menu_draw = Menu.Create("Heroes", "Hero List", "hero_artist", "Violet", "Draw")

local ui_draw = menu_draw:Switch("Enable Draw Key", true)
ui_draw:Icon("\u{f1fc}")
ui_draw:ToolTip("Hold the draw key to paint a blocking ink stroke in front of you")

local ui_draw_key = menu_draw:Bind("Draw Key", Enum.ButtonCode.KEY_MOUSE4)
ui_draw_key:Icon("\u{f084}")
ui_draw_key:ToolTip("Hold to draw. Uses the normal Living Ink charge pool")
ui_draw_key:Properties("Draw Wall", nil, false)

local ui_draw_aim = menu_draw:Slider("Draw Pitch", -45, 45, 0, "%d")
ui_draw_aim:ToolTip("Vertical adjustment while drawing. 0 keeps your current crosshair")

-- ------------------------------------------------------------
local menu_vis = Menu.Create("Heroes", "Hero List", "hero_artist", "Violet", "Visuals")

local ui_visuals = menu_vis:Switch("Visuals", true)
ui_visuals:Icon("\u{f06e}")
ui_visuals:ToolTip("Draw target information and ability status")

local ui_fov_circle = menu_vis:Switch("FOV Circle", true)
ui_fov_circle:Icon("\u{f111}")
ui_fov_circle:ToolTip("Show the target acquisition cone")

local ui_hud = menu_vis:Switch("Ability HUD", true)
ui_hud:Icon("\u{f0ca}")
ui_hud:ToolTip("Show cooldowns and combo state near the bottom of the screen")

-- ============================================================
-- Resources / state
-- ============================================================
local font = Render.LoadFont("Tahoma", Enum.FontCreate.FONTFLAG_ANTIALIAS, 800)

local icons = {}
local state = {
    target = nil,
    target_handle = nil,
    phase = "idle",     -- idle | flow | channel | settle
    phase_t = 0,
    flow_t = 0,
    flow_dist = 0,
    ink_next = 0,
    last_action = 0,
    channel = nil,
    prev_down = false,
}

local HERO_LIB_OK = HERO_LIB ~= nil

-- ============================================================
-- Small helpers
-- ============================================================
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function method(obj, name, ...)
    if not obj then return nil end
    local ok, value = pcall(obj[name], obj, ...)
    if ok then return value end
    return nil
end

-- HERO_LIB functions are declared with dots, so they do not take a self arg.
local function lib(name, ...)
    if not HERO_LIB_OK then return nil end
    local fn = HERO_LIB[name]
    if not fn then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
    return nil
end

local function valid_ent(ent)
    if not ent then return false end
    local ok, valid = pcall(ent.valid, ent)
    return ok and valid == true
end

local function is_enemy(ent, lp)
    if not valid_ent(ent) then return false end
    if not method(ent, "is_alive") or method(ent, "is_dormant") then return false end
    local team = ent.m_iTeamNum
    return team ~= nil and team ~= lp.m_iTeamNum
end

local function hero_id(lp)
    if HERO_LIB_OK then
        local ok, id = pcall(HERO_LIB.get_hero_id, lp)
        if ok and id then return id end
    end
    -- Fallback: ability name detection
    local ok, ab = pcall(lp.get_ability, lp, ABILITY.INK)
    if ok and ab then return HERO_ID end
    return -1
end

local function is_violet(lp)
    if not lp then return false end
    return hero_id(lp) == HERO_ID
end

local function ability(name)
    local lp = HERO_LIB_OK and HERO_LIB.lp or entity_list.local_pawn()
    if not lp or not valid_ent(lp) then return nil end
    local ok, ab = pcall(lp.get_ability, lp, name)
    if ok and ab and valid_ent(ab) then return ab end
    return nil
end

local function ready(ab, allow_casting)
    if not ab or not valid_ent(ab) then return false end
    if HERO_LIB_OK then
        local ok, res = pcall(HERO_LIB.is_ability_ready, ab, allow_casting)
        return ok and res == true
    end
    local ok, res = pcall(function() return ab:can_be_executed() end)
    return ok and res == 0
end

local function channeling(ab)
    if not ab or not valid_ent(ab) then return false end
    if HERO_LIB_OK then
        local ok, res = pcall(HERO_LIB.is_channeling_ability, ab)
        if ok and res then return true end
    end
    local raw = ab.m_bChanneling
    return raw == true
end

local function cooldown(ab)
    if not ab or not valid_ent(ab) then return 0 end
    local cd = method(ab, "get_cooldown")
    return tonumber(cd) or 0
end

local function icon_for(ab, key)
    if icons[key] or not ab then return icons[key] end
    local path = lib("get_ability_icon", ab)
    if path then
        local img = Render.LoadImage(path)
        if img then icons[key] = img end
    end
    return icons[key]
end

local function target_pos(target)
    local pos = lib("get_target_pos", target)
    if pos then return pos end
    pos = method(target, "get_bone_pos", "Spine_2") or method(target, "get_origin")
    return pos
end

local function camera_pos(cmd)
    return cmd.orig_vec_camera_position or utils.get_camera_pos()
end

local function dist_to(lp, target)
    local a = method(lp, "get_origin")
    local b = target_pos(target)
    if not a or not b then return 999999 end
    return (b - a):Length()
end

local function can_see(cmd, lp, target, pos)
    if HERO_LIB_OK then
        local ok, res = pcall(HERO_LIB.no_obs_to_pos, pos, camera_pos(cmd), lp, target)
        if ok then return res == true end
    end
    return true
end

-- ============================================================
-- Aiming
-- ============================================================
local function aim_at(cmd, target, pos)
    if not pos or not target then return end

    local smooth = clamp(ui_smooth:Get(), 1, 20)
    local psilent = ui_psilent:Get()
    local cam = camera_pos(cmd)
    if not cam then return end

    local ang = utils.calc_angle(cam, pos)
    if not ang then return end

    if HERO_LIB_OK then
        pcall(HERO_LIB.aim_psilent_default, cmd, smooth, pos, target, 5.0, psilent, 1.0)
    end

    -- Carry the exact direction in the usercmd so the server validates the
    -- cast / channel against the target even if psilent was unavailable.
    cmd.viewangles = ang
    if not psilent then
        pcall(cmd.smooth_aim, cmd, ang, smooth)
        utils.set_camera_angles(ang)
    end
end

local function cast(cmd, lp, ab, with_alt, with_attack)
    if not ab then return false end
    if HERO_LIB_OK then
        local ok = pcall(HERO_LIB.cast_ability, cmd, lp, ab, with_alt, with_attack)
        return ok
    end
    local mask = lib("get_ability_input_mask", ab)
    if not mask then return false end
    cmd:add_buttonstate1(mask)
    if with_alt then cmd:add_buttonstate1(InputBitMask_t.IN_ALT_CAST) end
    if with_attack then cmd:add_buttonstate1(InputBitMask_t.IN_ATTACK) end
    return true
end

-- ============================================================
-- Targeting
-- ============================================================
local function acquire_target(cmd, lp)
    local cam = camera_pos(cmd)
    if not cam then return nil end

    local best, best_fov = nil, 999999
    local max_range = ui_range:Get() * UNIT_METER
    local max_fov = ui_fov:Get()

    for _, e in ipairs(entity_list.by_class_name("C_CitadelPlayerPawn")) do
        if is_enemy(e, lp) then
            local pos = target_pos(e)
            if pos then
                local dist = (pos - cam):Length()
                if dist <= max_range then
                    local fov = lib("get_fov_to_pos", cam, pos, nil, true, cmd)
                    fov = fov or 999999
                    if fov <= max_fov and fov < best_fov and can_see(cmd, lp, e, pos) then
                        best, best_fov = e, fov
                    end
                end
            end
        end
    end
    return best
end

local function keep_target(cmd, lp)
    if ui_lock:Get() and state.target and valid_ent(state.target) and is_enemy(state.target, lp) then
        if dist_to(lp, state.target) <= ui_range:Get() * UNIT_METER then
            return state.target
        end
    end
    return acquire_target(cmd, lp)
end

local function count_near(lp, radius)
    local n = 0
    local origin = method(lp, "get_origin")
    if not origin then return 0 end
    for _, e in ipairs(entity_list.by_class_name("C_CitadelPlayerPawn")) do
        if is_enemy(e, lp) then
            local p = method(e, "get_origin")
            if p and (p - origin):Length() <= radius then n = n + 1 end
        end
    end
    return n
end

-- ============================================================
-- Combo
-- ============================================================
local function reset_state()
    state.target = nil
    state.phase = "idle"
    state.channel = nil
    state.phase_t = 0
    state.flow_t = 0
end

local function begin_flow(cmd, lp, target, pos, now, flow)
    state.phase = "flow"
    state.phase_t = now
    state.flow_t = now
    state.flow_dist = dist_to(lp, target)
    aim_at(cmd, target, pos)
    cast(cmd, lp, flow, false, false)
    state.last_action = now
end

local function run_combo(cmd, lp, now)
    local target = keep_target(cmd, lp)
    if not target then
        if state.phase ~= "channel" then reset_state() end
        return
    end

    state.target = target
    local pos = target_pos(target)
    if not pos then return end

    local dist = dist_to(lp, target)

    -- --------------------------------------------------------
    -- 1. Stay glued to an in-progress sketch. This is what makes
    --    Still Life actually complete instead of breaking.
    -- --------------------------------------------------------
    local sketch = ability(ABILITY.SKETCH)
    if state.phase == "channel" then
        if channeling(sketch) then
            aim_at(cmd, target, pos)
            state.channel = now
            return
        end
        -- Channel ended (finished or interrupted). Track briefly, then resume.
        if now - (state.channel or 0) < CHANNEL_GRACE then
            aim_at(cmd, target, pos)
            return
        end
        state.phase = "idle"
        state.channel = nil
    end

    -- --------------------------------------------------------
    -- 2. Flow State steering / flick
    -- --------------------------------------------------------
    local flow = ability(ABILITY.FLOW)
    if state.phase == "flow" then
        if channeling(sketch) then
            state.phase = "channel"
            state.channel = now
            aim_at(cmd, target, pos)
            return
        end
        if state.flow_dist > 40 * UNIT_METER then state.flow_dist = 40 * UNIT_METER end
        local flick_at = clamp(state.flow_dist / (FLOW_SPEED_MPS * UNIT_METER), FLOW_MIN_FLICK, FLOW_MAX_FLICK)
        if now - state.flow_t >= flick_at then
            -- Flick: aim at the target and press the ability again.
            aim_at(cmd, target, pos)
            if ready(flow, true) then
                cast(cmd, lp, flow, false, false)
                state.last_action = now
                state.phase = "idle"
            elseif now - state.flow_t > 2.5 then
                state.phase = "idle"
            end
        else
            -- Steer the brush through the target while it travels.
            aim_at(cmd, target, pos)
        end
        return
    end

    -- --------------------------------------------------------
    -- 3. New actions are throttled so one tick can't fire everything
    -- --------------------------------------------------------
    if now - state.last_action < ACTION_COOLDOWN then return end

    -- --------------------------------------------------------
    -- 4. Ultimate on stacked enemies
    -- --------------------------------------------------------
    local ult = ability(ABILITY.ULT)
    if ui_ult:Get() and ready(ult) and count_near(lp, 18 * UNIT_METER) >= ui_ult_min:Get() then
        cast(cmd, lp, ult, false, false)
        state.last_action = now
        return
    end

    -- --------------------------------------------------------
    -- 5. Ink empower (opener)
    -- --------------------------------------------------------
    local ink = ability(ABILITY.INK)
    if ui_ink:Get() and ready(ink) and now >= state.ink_next and dist <= 45 * UNIT_METER then
        -- Empower is a self buff; it keeps the gun ready for steered shots.
        if cast(cmd, lp, ink, false, true) then
            state.ink_next = now + INK_RECAST_DELAY
            state.last_action = now
            return
        end
    end

    -- --------------------------------------------------------
    -- 6. Flow State trail + flick (burst)
    -- --------------------------------------------------------
    if ui_flow:Get() and ready(flow) and dist <= ui_range:Get() * UNIT_METER then
        begin_flow(cmd, lp, target, pos, now, flow)
        return
    end

    -- --------------------------------------------------------
    -- 7. Sketch the locked target (stun)
    -- --------------------------------------------------------
    if ui_sketch:Get() and ready(sketch) then
        local cast_range = method(sketch, "get_cast_range")
        local limit = cast_range and cast_range > 0 and cast_range or (25 * UNIT_METER)
        limit = math.min(limit, 25 * UNIT_METER)

        if dist <= limit and can_see(cmd, lp, target, pos) then
            aim_at(cmd, target, pos)
            if cast(cmd, lp, sketch, false, false) then
                state.phase = "channel"
                state.channel = now
                state.last_action = now
                return
            end
        end
    end

    -- --------------------------------------------------------
    -- 8. Auto fire
    -- --------------------------------------------------------
    if ui_auto_fire:Get() then
        cmd:add_buttonstate1(InputBitMask_t.IN_ATTACK)
    end
end

-- ============================================================
-- Draw mode
-- ============================================================
local function handle_draw(cmd, lp)
    if not ui_draw:Get() or not ui_draw_key:IsDown() then return end
    local ink = ability(ABILITY.INK)
    if not ready(ink, true) then return end

    local pitch = ui_draw_aim:Get()
    if pitch ~= 0 then
        local ang = cmd.viewangles
        if ang then
            cmd.viewangles = Angle(ang.pitch + pitch, ang.yaw, ang.roll)
            utils.set_camera_angles(cmd.viewangles)
        end
    end

    -- Repeated alt presses keep the stroke going while the key is held.
    cast(cmd, lp, ink, true, false)
end

-- ============================================================
-- Callbacks
-- ============================================================
local function on_createmove(cmd)
    if not ui_enable:Get() then return end
    if Menu.Opened() or cmd.in_shop then return end

    local lp = HERO_LIB_OK and HERO_LIB.lp or entity_list.local_pawn()
    if not lp or not valid_ent(lp) or not method(lp, "is_alive") then return end
    if not is_violet(lp) then return end

    -- Silence / hard stun / other action: still aim during a sketch channel
    local sketch = ability(ABILITY.SKETCH)
    local is_channel = channeling(sketch)
    if not is_channel then
        if method(lp, "has_modifier_state", EModifierState.MODIFIER_STATE_STUNNED)
            or method(lp, "has_modifier_state", EModifierState.MODIFIER_STATE_SILENCED)
            or method(lp, "has_modifier_state", EModifierState.MODIFIER_STATE_BUSY_WITH_ACTION) then
            reset_state()
            return
        end
    end

    handle_draw(cmd, lp)

    local now = game_rules.game_time()
    local want = (ui_mode:Get() == 1) and ui_key:IsToggled() or ui_key:IsDown()

    if not want then
        if state.prev_down then reset_state() end
        state.prev_down = false
        return
    end

    if ui_mode:Get() == 1 and not state.prev_down then reset_state() end
    state.prev_down = true

    run_combo(cmd, lp, now)
end

local function ability_line(x, y, ab, label, key)
    local cd = cooldown(ab)
    local is_ready = ready(ab)
    local color = is_ready and Color(120, 220, 150, 235) or Color(255, 120, 120, 235)
    local text = string.format("%-7s %s", label, is_ready and "READY" or string.format("%.1fs", cd))

    Render.Text(font, 12, text, Vec2(x, y), color)
    local img = icon_for(ab, key)
    if img then
        Render.Image(img, Vec2(x + 132, y - 3), Vec2(16, 16), Color(255, 255, 255, 220))
    end
end

local function on_draw()
    if not ui_enable:Get() or not ui_visuals:Get() then return end
    if Menu.Opened() then return end

    local lp = entity_list.local_pawn()
    if not lp or not valid_ent(lp) or not is_violet(lp) then return end

    if ui_fov_circle:Get() then
        local r = utils.fov_to_pixel_radius(ui_fov:Get())
        local center = Render.ScreenSize() * 0.5
        Render.Circle(center, r, Color(180, 130, 255, 45), 1.0)
    end

    local target = state.target
    if target and valid_ent(target) and method(target, "is_alive") then
        local pos = target_pos(target)
        if pos then
            local screen, visible = Render.WorldToScreen(pos)
            if visible then
                local lp_o = lp:get_origin()
                local name = method(target, "get_name") or "?"
                local meters = lp_o and math.floor((pos - lp_o):Length() / UNIT_METER) or 0

                Render.Text(font, 13, string.format("%s [%dm]", name, meters),
                    screen + Vec2(12, -18), Color(220, 200, 255, 255))

                if state.phase == "channel" then
                    Render.Text(font, 12, "SKETCHING", screen + Vec2(12, 0), Color(255, 220, 120, 255))
                elseif state.phase == "flow" then
                    Render.Text(font, 12, "STEERING", screen + Vec2(12, 0), Color(120, 220, 255, 255))
                end
            end
        end
    end

    if ui_hud:Get() then
        local size = Render.ScreenSize()
        local x = size.x * 0.5 - 110
        local y = size.y - 108

        Render.FilledRect(Vec2(x - 14, y - 12), Vec2(x + 230, y + 74), Color(16, 12, 24, 190), 6)
        Render.Rect(Vec2(x - 14, y - 12), Vec2(x + 230, y + 74), Color(120, 90, 180, 140), 6)

        local ink = ability(ABILITY.INK)
        local flow = ability(ABILITY.FLOW)
        local sketch = ability(ABILITY.SKETCH)
        local ult = ability(ABILITY.ULT)

        ability_line(x, y, ink, "INK", "ink")
        ability_line(x, y + 20, flow, "FLOW", "flow")
        ability_line(x, y + 40, sketch, "SKETCH", "sketch")
        ability_line(x, y + 60, ult, "ULT", "ult")

        local phase = state.phase:upper()
        Render.Text(font, 11, phase, Vec2(x + 176, y), Color(200, 200, 200, 200))
    end
end

callback.on_createmove:set(on_createmove)
callback.on_draw:set(on_draw)

print(string.format("[Violet] v%s loaded", VERSION))
