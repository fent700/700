--[[
    splash_intro.lua  --  Splash Hub launch cinematic
    "Welcome to Los Santos" from its 18.80s downbeat (89.1 BPM). One shot per bar, every cut lands
    on the bar's kick, credits + title card in the GTA V trailer style.
    Also skips BGSI's own intro (loading bar -> Play -> High/Low graphics picker).

    getgenv().SplashIntro        -> { done = bool, skip = fn }
    getgenv().SplashIntroOptions -> optional { audioUrl, startAt (sec), freezeAt (sec), keepGameIntro, silent }
]]

local genv = (getgenv and getgenv()) or _G
if genv._splashIntroCleanup then pcall(genv._splashIntroCleanup) end

local OPT = genv.SplashIntroOptions or {}
local AUDIO_URL  = OPT.audioUrl or "https://raw.githubusercontent.com/fent700/700/refs/heads/splash/splash/intro.mp3"
local AUDIO_FILE = "SplashHub_Configs/splash_intro_theme.mp3"

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local UIS          = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RS           = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local StarterGui   = game:GetService("StarterGui")
local Lighting     = game:GetService("Lighting")

local player = Players.LocalPlayer
local Intro  = { done = false }
genv.SplashIntro = Intro

local BPM  = 89.10
local BEAT = 60 / BPM
local BAR  = BEAT * 4

------------------------------------------------------------------------
-- MATH
------------------------------------------------------------------------
local V3, CF = Vector3.new, CFrame.new
local function lerp(a, b, t) return a + (b - a) * t end
local function clamp01(x) return x < 0 and 0 or (x > 1 and 1 or x) end
local function smooth(x) x = clamp01(x) return x * x * (3 - 2 * x) end
local function easeOut(x) x = clamp01(x) return 1 - (1 - x) ^ 3 end
local function easeInOut(x) x = clamp01(x) return x < 0.5 and 4 * x ^ 3 or 1 - (-2 * x + 2) ^ 3 / 2 end
local function flat(v) return V3(v.X, 0, v.Z) end

local function tween(obj, time, props, style, dir)
    local tw = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
    tw:Play()
    return tw
end

local function getChar()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    return char, hrp, hum
end

local function guiParent()
    local ok, h = pcall(function() return gethui and gethui() end)
    if ok and h then return h end
    local ok2, cg = pcall(function() return game:GetService("CoreGui") end)
    if ok2 and cg then return cg end
    return player:WaitForChild("PlayerGui")
end

-- Calling into a BGSI module drops this thread's capabilities until it next resumes (our gethui
-- overlay then throws "lacking capability Plugin"), so yield once after every batch of game calls.
local function settle()
    task.wait()
    pcall(function() if setthreadidentity then setthreadidentity(8) end end)
end

local function gameModule(path)
    local ok, mod = pcall(function()
        local inst = RS
        for seg in path:gmatch("[^%.]+") do inst = inst:WaitForChild(seg, 3) end
        return require(inst)
    end)
    return ok and type(mod) == "table" and mod or nil
end

------------------------------------------------------------------------
-- BGSI INTRO SKIP
-- The game's intro (ReplicatedStorage.Client.Gui.Animations.Intro) ends through a local finish()
-- bound (via ClickableButton -> .Activated) to the High/Low graphics buttons. The Play button is
-- the LAST thing the intro wires up, so once it has Activated connections the sequence is done and
-- firing the graphics button that matches the player's current detail setting finishes it cleanly.
------------------------------------------------------------------------
local function resolveButton(inst)
    if not inst then return nil end
    if inst:IsA("GuiButton") then return inst end
    return inst:FindFirstChild("Activation") or inst:FindFirstChildWhichIsA("GuiButton")
end

local function activatedConns(btn)
    btn = resolveButton(btn)
    if not (getconnections and btn) then return {} end
    local ok, conns = pcall(getconnections, btn.Activated)
    return (ok and conns) or {}
end

-- run a connection's handler in its own thread: Potassium's conn:Fire() can't yield, and the intro's
-- finish() yields (task.wait) -- a non-yieldable call dies mid-fade and latches finish's "running" flag
local function fireConn(c)
    local fn = c.Function
    if type(fn) == "function" then
        task.spawn(fn)
    else
        task.spawn(function() pcall(function() c:Fire() end) end)
    end
end

local function wantsLowDetail()
    local ok, low = pcall(function() return require(RS.Client.LowDetail).Enabled end)
    if ok and type(low) == "boolean" then return low end
    return UIS.TouchEnabled and not UIS.KeyboardEnabled
end

-- returns true once BGSI's intro is gone (or never showed up)
local function skipGameIntro(timeout)
    local pg = player:WaitForChild("PlayerGui", 30)
    local mod = gameModule("Client.Gui.Animations.Intro")
    local t0 = os.clock()
    local sawIntro = false
    while os.clock() - t0 < timeout do
        local gui = pg and pg:FindFirstChild("Intro")
        if gui then
            sawIntro = true
            local play = gui:FindFirstChild("Play")
            local playConns = activatedConns(play and play:FindFirstChild("Button"))
            if #playConns > 0 then
                -- current build: Play -> finish() (device/detail picked from input mode automatically)
                for _, c in ipairs(playConns) do fireConn(c) end
                -- older build: Play only opens the High/Low graphics picker, whose buttons call finish()
                task.wait(0.4)
                local content = gui.Parent and gui:FindFirstChild("Graphics") and gui.Graphics:FindFirstChild("Content")
                if content then
                    local pick = content:FindFirstChild(wantsLowDetail() and "Low" or "High") or content:FindFirstChildWhichIsA("Frame")
                    local btn = pick and pick:FindFirstChild("Action") and pick.Action:FindFirstChild("Button")
                    for _, c in ipairs(activatedConns(btn)) do fireConn(c) end
                end
                local w0 = os.clock()
                while gui.Parent and os.clock() - w0 < 4 do task.wait(0.1) end
            end
        elseif sawIntro or (mod and mod.IsPlaying == false) then
            return true
        elseif not mod and os.clock() - t0 > 8 then
            return true
        end
        task.wait(0.15)
    end
    return false
end

-- reconnects: no cinematic, just get BGSI's intro out of the way
if OPT.skipOnly then
    task.spawn(function()
        pcall(skipGameIntro, 60)
        Intro.done = true
    end)
    return Intro
end

------------------------------------------------------------------------
-- STATE + RESTORE
------------------------------------------------------------------------
local STEP_NAME = "SplashIntroCam_" .. tostring(math.random(1, 1e9))
local conns, spawned, restoreFns = {}, {}, {}
local fxFolder = Instance.new("Folder")
fxFolder.Name = "SplashIntroFX"

local gameRestoreFns = {}
local function track(c) conns[#conns + 1] = c return c end
local function onRestore(fn) restoreFns[#restoreFns + 1] = fn end
local function onRestoreGame(fn) gameRestoreFns[#gameRestoreFns + 1] = fn end  -- BGSI module calls: run last
local function own(inst) spawned[#spawned + 1] = inst return inst end

local restored = false
local function restoreAll()
    if restored then return end
    restored = true
    pcall(function() RunService:UnbindFromRenderStep(STEP_NAME) end)
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    for i = #restoreFns, 1, -1 do pcall(restoreFns[i]) end
    for _, inst in ipairs(spawned) do pcall(function() inst:Destroy() end) end
    pcall(function() fxFolder:Destroy() end)
    -- game-module calls taint the calling thread, so they go last and in their own thread
    task.spawn(function()
        for i = #gameRestoreFns, 1, -1 do pcall(gameRestoreFns[i]) end
    end)
end

------------------------------------------------------------------------
-- OVERLAY GUI
------------------------------------------------------------------------
local FONT_CREDIT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
local FONT_TITLE  = Font.new("rbxasset://fonts/families/Bangers.json", Enum.FontWeight.Regular)
local FONT_AREA   = Font.new("rbxasset://fonts/families/PermanentMarker.json", Enum.FontWeight.Regular)

local gui = Instance.new("ScreenGui")  -- destroyed last, after the fade back to the game
gui.Name = "SplashIntro"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 99999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
gui.Parent = guiParent()

local function frame(props)
    local f = Instance.new("Frame")
    f.BorderSizePixel = 0
    for k, v in pairs(props) do if k ~= "Parent" then f[k] = v end end
    f.Parent = props.Parent or gui
    return f
end

local function label(props)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.TextColor3 = Color3.new(1, 1, 1)
    for k, v in pairs(props) do if k ~= "Parent" then l[k] = v end end
    l.Parent = props.Parent or gui
    return l
end

local barTop = frame({ Name = "BarTop", BackgroundColor3 = Color3.new(), Size = UDim2.new(1, 0, 0, 0), ZIndex = 5 })
local barBot = frame({ Name = "BarBot", BackgroundColor3 = Color3.new(), AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 0), ZIndex = 5 })
local flash  = frame({ Name = "Flash", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 8 })
local black  = frame({ Name = "Black", BackgroundColor3 = Color3.new(), BackgroundTransparency = 0, Size = UDim2.fromScale(1, 1), ZIndex = 9 })

-- GTA-style loading spinner (bottom right) while the game + audio get ready
local loading = frame({ Name = "Loading", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -40, 1, -36), Size = UDim2.fromOffset(240, 28), ZIndex = 10 })
local spinner = frame({ Parent = loading, BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(20, 20), ZIndex = 10 })
do
    Instance.new("UICorner", spinner).CornerRadius = UDim.new(1, 0)
    local st = Instance.new("UIStroke", spinner)
    st.Thickness = 3
    st.Color = Color3.new(1, 1, 1)
    local gr = Instance.new("UIGradient", st)
    gr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.6, 0), NumberSequenceKeypoint.new(0.61, 1), NumberSequenceKeypoint.new(1, 1) })
    track(RunService.RenderStepped:Connect(function(dt) gr.Rotation = (gr.Rotation + dt * 320) % 360 end))
end
local loadingText = label({ Parent = loading, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -32, 0.5, 0), Size = UDim2.new(1, -32, 1, 0), FontFace = FONT_CREDIT, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Right, Text = "LOADING", ZIndex = 10 })

-- credits: small spaced caps, like the trailer's "ROCKSTAR GAMES PRESENTS"
local credit = label({ Name = "Credit", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.7, 0.5), Size = UDim2.fromScale(0.46, 0.05), FontFace = FONT_CREDIT, TextScaled = true, TextTransparency = 1, Text = "", ZIndex = 6 })
do
    local c = Instance.new("UITextSizeConstraint", credit)
    c.MaxTextSize = 24
    c.MinTextSize = 11
    local s = Instance.new("UIStroke", credit)
    s.Thickness = 1
    s.Transparency = 0.6
end

-- feature caption: bottom right, like GTA's neighbourhood names
local area = label({ Name = "Area", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -46, 1, -30), Size = UDim2.fromScale(0.4, 0.07), FontFace = FONT_AREA, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Right, TextTransparency = 1, Text = "", ZIndex = 6 })
local areaStroke = Instance.new("UIStroke", area)
areaStroke.Thickness = 2.5
areaStroke.Transparency = 1

-- title card: stacked "splash / hub" + V1 badge. Text tops out at 100px, so the block is laid out in
-- fixed pixels (designed for a 540px-tall screen) and blown up with a UIScale every frame.
local dim = frame({ Name = "Dim", BackgroundColor3 = Color3.new(), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 6 })
local title = frame({ Name = "Title", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.47), Size = UDim2.fromOffset(330, 210), ZIndex = 7 })
local titleScale = Instance.new("UIScale", title)
local titleLines = {}
for i, def in ipairs({ { "splash", 0, 0, 330, 108 }, { "hub", 58, 92, 190, 108 } }) do
    local l = label({ Parent = title, Position = UDim2.fromOffset(def[2], def[3]), Size = UDim2.fromOffset(def[4], def[5]), FontFace = FONT_TITLE, TextSize = 100, TextXAlignment = Enum.TextXAlignment.Left, Text = def[1], TextTransparency = 1, ZIndex = 7 })
    local s = Instance.new("UIStroke", l)
    s.Thickness = 3.5
    s.Transparency = 1
    titleLines[i] = { label = l, stroke = s }
end
local badge = frame({ Parent = title, Name = "Badge", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(278, 150), Size = UDim2.fromOffset(92, 92), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, Rotation = -8, ZIndex = 7 })
Instance.new("UICorner", badge).CornerRadius = UDim.new(1, 0)
local badgeStroke = Instance.new("UIStroke", badge)
badgeStroke.Thickness = 3.5
badgeStroke.Transparency = 1
local badgeGrad = Instance.new("UIGradient", badge)
badgeGrad.Color = ColorSequence.new(Color3.fromRGB(120, 240, 255), Color3.fromRGB(20, 105, 205))
badgeGrad.Rotation = 90
local badgeText = label({ Parent = badge, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.54), Size = UDim2.fromScale(0.9, 0.8), FontFace = FONT_TITLE, TextSize = 58, Text = "V1", TextTransparency = 1, ZIndex = 8 })
local badgeTextStroke = Instance.new("UIStroke", badgeText)
badgeTextStroke.Thickness = 2.5
badgeTextStroke.Transparency = 1
local subtitle = label({ Name = "Subtitle", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.75), Size = UDim2.fromScale(0.5, 0.032), FontFace = FONT_CREDIT, TextScaled = true, Text = "B U B B L E   G U M   S I M U L A T O R   I N F I N I T Y", TextTransparency = 1, ZIndex = 7 })
local subStroke = Instance.new("UIStroke", subtitle)
subStroke.Thickness = 1
subStroke.Transparency = 1

local function setTitleAlpha(a, subA)
    local tr = 1 - a
    for _, l in ipairs(titleLines) do
        l.label.TextTransparency = tr
        l.stroke.Transparency = tr
    end
    badge.BackgroundTransparency = tr
    badgeStroke.Transparency = tr
    badgeText.TextTransparency = tr
    badgeTextStroke.Transparency = tr
    subtitle.TextTransparency = 1 - (subA or 0)
    subStroke.Transparency = 1 - (subA or 0) * 0.5
end

local skipHint = label({ Name = "SkipHint", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 28, 1, -12), Size = UDim2.fromOffset(260, 18), FontFace = FONT_CREDIT, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextTransparency = 1, Text = UIS.TouchEnabled and "DOUBLE-TAP TO SKIP" or "PRESS SPACE TO SKIP", ZIndex = 10 })

local function letterbox(alpha)
    local vp = gui.AbsoluteSize
    if vp.X < 1 then return end
    local h = math.max((vp.Y - vp.X / 2.39) / 2, vp.Y * 0.085)
    barTop.Size = UDim2.new(1, 0, 0, h * alpha)
    barBot.Size = UDim2.new(1, 0, 0, h * alpha)
end

local function textAlpha(lt, len, inAt, outAt)
    outAt = outAt or (len - 0.35)
    return smooth((lt - inAt) / 0.35) * (1 - smooth((lt - outAt) / 0.3))
end

------------------------------------------------------------------------
-- WORLD HELPERS + FX
------------------------------------------------------------------------
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- first solid, visible surface below (x, fromY, z)
local function groundY(x, z, fromY, depth)
    local exclude = { fxFolder }
    if player.Character then exclude[#exclude + 1] = player.Character end
    for _, p in ipairs(Players:GetPlayers()) do if p.Character then exclude[#exclude + 1] = p.Character end end
    local rendered = workspace:FindFirstChild("Rendered")
    if rendered and rendered:FindFirstChild("Pets") then exclude[#exclude + 1] = rendered.Pets end
    for _ = 1, 10 do
        rayParams.FilterDescendantsInstances = exclude
        local hit = workspace:Raycast(V3(x, fromY, z), V3(0, -(depth or 250), 0), rayParams)
        if not hit then return nil end
        if hit.Instance.Transparency < 0.9 and hit.Instance.CanCollide then return hit.Position.Y end
        exclude[#exclude + 1] = hit.Instance
    end
    return nil
end

local function hrpOffset()
    local _, hrp, hum = getChar()
    if hum and hum.RigType == Enum.HumanoidRigType.R6 then return 3 end
    return (hum and hum.HipHeight or 2) + (hrp and hrp.Size.Y / 2 or 1)
end

-- CFrame for the HRP standing on `ground` (a surface point) facing `lookAt`
local function standCF(ground, lookAt)
    local p = ground + V3(0, hrpOffset(), 0)
    local dir = flat(lookAt - p)
    if dir.Magnitude < 0.01 then dir = V3(0, 0, -1) end
    return CFrame.lookAt(p, p + dir)
end

local function standAt(x, z, fromY, lookAt)
    local y = groundY(x, z, fromY or 60)
    if not y then return nil end
    return standCF(V3(x, y, z), lookAt or V3(x, y, z - 1))
end

local function fxPart(props)
    local p = Instance.new("Part")
    p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
    for k, v in pairs(props) do p[k] = v end
    p.Parent = fxFolder
    return p
end

local function sparkle(parent, color, count, speed)
    local att = Instance.new("Attachment", parent)
    local pe = Instance.new("ParticleEmitter")
    pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    pe.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
    pe.LightEmission = 1
    pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.3), NumberSequenceKeypoint.new(1, 0) })
    pe.Lifetime = NumberRange.new(0.35, 0.75)
    pe.Speed = NumberRange.new(speed or 14, (speed or 14) * 1.8)
    pe.SpreadAngle = Vector2.new(180, 180)
    pe.Drag = 4
    pe.Enabled = false
    pe.Parent = att
    pe:Emit(count or 24)
end

-- bubble-pop teleport burst
local function burst(pos, color, size)
    color = color or Color3.fromRGB(255, 120, 220)
    size = size or 9
    local ball = fxPart({ Shape = Enum.PartType.Ball, Material = Enum.Material.ForceField, Color = color, Size = Vector3.one, CFrame = CF(pos) })
    local ring = fxPart({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = color, Size = V3(0.15, 1, 1), CFrame = CF(pos) * CFrame.Angles(0, 0, math.rad(90)), Transparency = 0.1 })
    sparkle(ball, color, 26)
    tween(ball, 0.45, { Size = Vector3.one * size, Transparency = 1 }, Enum.EasingStyle.Quart)
    tween(ring, 0.5, { Size = V3(0.15, size * 1.7, size * 1.7), Transparency = 1 }, Enum.EasingStyle.Quart)
    task.delay(1.2, function() ball:Destroy() ring:Destroy() end)
end

-- neon streak between two blink points
local function streak(a, b, color)
    local d = (b - a).Magnitude
    if d < 1 then return end
    local s = fxPart({ Material = Enum.Material.Neon, Color = color or Color3.fromRGB(255, 160, 235), Size = V3(0.5, 0.5, d), CFrame = CFrame.lookAt((a + b) / 2, b) })
    tween(s, 0.4, { Size = V3(0.05, 0.05, d), Transparency = 1 }, Enum.EasingStyle.Quad)
    task.delay(0.5, function() s:Destroy() end)
end

------------------------------------------------------------------------
-- CHARACTER CONTROL
------------------------------------------------------------------------
local animTracks = {}
local function playAnim(name, speed, looped)
    local char, _, hum = getChar()
    if not (char and hum) then return end
    for n, tr in pairs(animTracks) do
        if n ~= name then pcall(function() tr:Stop(0.12) end) end
    end
    if name == nil then return end
    local tr = animTracks[name]
    if not tr then
        local animate = char:FindFirstChild("Animate")
        local holder = animate and animate:FindFirstChild(name)
        local anim = holder and holder:FindFirstChildWhichIsA("Animation")
        local animator = hum:FindFirstChildOfClass("Animator")
        if not (anim and animator) then return end
        local ok, t = pcall(function() return animator:LoadAnimation(anim) end)
        if not ok then return end
        tr = t
        tr.Priority = Enum.AnimationPriority.Action
        animTracks[name] = tr
    end
    tr.Looped = looped ~= false
    if not tr.IsPlaying then tr:Play(0.12) end
    tr:AdjustSpeed(speed or 1)
end

local function pose(cf)
    local _, hrp = getChar()
    if not hrp then return end
    hrp.Anchored = true
    hrp.CFrame = cf
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
end

local function charPos()
    local _, hrp = getChar()
    return hrp and hrp.Position or Vector3.zero
end

local function blink(cf, color, withStreak)
    local from = charPos()
    burst(from, color)
    pose(cf)
    burst(cf.Position, color)
    if withStreak then streak(from, cf.Position, color) end
end

local lightingTarget = nil
local function setClock(h) lightingTarget = h pcall(function() Lighting.ClockTime = h end) end

local grade, blur -- created in run()

------------------------------------------------------------------------
-- SHOTS  (bars = length; enter(shot, skippedBeats); beat(shot, i, catchingUp); frame(shot, a, lt) -> camCF, fov)
------------------------------------------------------------------------
local SHOTS = {}
local function shot(def) SHOTS[#SHOTS + 1] = def return def end

local PLAZA_Y = 80  -- raycast start height for overworld ground

-- 1. ESTABLISHING -- slow descending aerial over the island, "GUMTEETH PRESENTS"
shot({
    name = "establish", bars = 1, credit = "GUMTEETH  PRESENTS",
    prep = function(s)
        s.from = V3(335, 190, -335)
        s.to   = V3(185, 96, -200)
    end,
    enter = function(s) setClock(14) end,
    frame = function(s, a)
        local e = smooth(a * 0.85 + 0.15)
        local pos = s.from:Lerp(s.to, e)
        local look = V3(lerp(0, 8, a), lerp(45, 32, a), lerp(-15, -30, a))
        return CFrame.lookAt(pos, look), 52
    end,
})

-- 2. RUN -- side tracking shot across the plaza, "A SPLASH HUB PRODUCTION"
shot({
    name = "run", bars = 1, credit = "A  SPLASH  HUB  PRODUCTION", creditPos = UDim2.fromScale(0.29, 0.4),
    prep = function(s)
        local a = standAt(16, -30, PLAZA_Y, V3(62, 0, -36))
        local b = standAt(62, -36, PLAZA_Y, V3(110, 0, -42))
        assert(a and b, "run path off ground")
        s.a, s.b = a, CFrame.lookAt(b.Position, b.Position + (b.Position - a.Position).Unit * V3(1, 0, 1))
    end,
    enter = function(s)
        setClock(14)
        pose(s.a)
        playAnim("run", 1.35)
    end,
    frame = function(s, a)
        local p = s.a.Position:Lerp(s.b.Position, a)
        local fwd = flat(s.b.Position - s.a.Position).Unit
        pose(CFrame.lookAt(p, p + fwd))
        local side = fwd:Cross(V3(0, 1, 0))  -- right of travel
        local cam = p - side * lerp(16, 12.5, a) + V3(0, lerp(1.4, 2.6, a), 0) + fwd * lerp(7, 3, a)
        return CFrame.lookAt(cam, p + fwd * 4 + V3(0, 1, 0)), 50
    end,
    leave = function() playAnim(nil) end,
})

-- 3. GEM VACUUM -- gems scattered round the character get pulled in on every beat
shot({
    name = "gems", bars = 1, area = "AUTO GEM FARM",
    prep = function(s)
        local stand = standAt(62, -36, PLAZA_Y, V3(40, 0, -34))  -- faces the camera's orbit arc
        assert(stand, "gem spot off ground")
        s.stand = stand
        s.center = stand.Position
        local P = RS:FindFirstChild("Assets") and RS.Assets:FindFirstChild("Pickups")
        assert(P, "no pickup assets")
        local kinds = { "Gem", "Gem", "Gem", "Gem Box", "Gem", "Gem Chest", "Gem", "Gem Safe", "Coin Pile", "Gem" }
        s.gems = {}
        local rng = Random.new(700)
        for i = 1, 30 do
            local src = P:FindFirstChild(kinds[(i - 1) % #kinds + 1]) or P:FindFirstChild("Gem")
            local m = src:Clone()
            for _, d in ipairs(m:GetDescendants()) do
                if d:IsA("BasePart") then d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch = true, false, false, false end
            end
            pcall(function() m:ScaleTo(src.Name == "Gem" and 0.5 or 0.42) end)
            local ang = (i / 30) * math.pi * 2 + rng:NextNumber(-0.15, 0.15)
            local r = rng:NextNumber(5.5, 12)
            local x, z = s.center.X + math.cos(ang) * r, s.center.Z + math.sin(ang) * r
            local gy = groundY(x, z, s.center.Y + 20, 60) or (s.center.Y - hrpOffset())
            local _, size = m:GetBoundingBox()
            s.gems[i] = {
                model = m, home = V3(x, gy + size.Y / 2 + 0.6, z), phase = rng:NextNumber(0, 6.28),
                pull = ((i - 1) % 4) * BEAT + rng:NextNumber(0, 0.22), done = false,
            }
        end
    end,
    enter = function(s)
        setClock(14)
        pose(s.stand)
        playAnim(nil)
        for _, g in ipairs(s.gems) do g.model.Parent = fxFolder end
    end,
    beat = function(s, i, catchingUp)
        if i == 3 and not catchingUp then task.delay(0.25, function() playAnim("cheer", 1, false) end) end
    end,
    frame = function(s, a, lt)
        local target = s.center + V3(0, 0.8, 0)
        for _, g in ipairs(s.gems) do
            if not g.done then
                local k = (lt - g.pull) / 0.42
                local spin = CFrame.Angles(0, lt * 2.2 + g.phase, 0)
                if k <= 0 then
                    g.model:PivotTo(CF(g.home + V3(0, math.sin(lt * 3 + g.phase) * 0.35, 0)) * spin)
                elseif k < 1 then
                    local e = k * k
                    local p = g.home:Lerp(target, e) + V3(0, math.sin(k * math.pi) * 4, 0)
                    g.model:PivotTo(CF(p) * spin)
                else
                    g.done = true
                    g.model.Parent = nil
                    local sp = fxPart({ Transparency = 1, Size = Vector3.one, CFrame = CF(target) })
                    sparkle(sp, Color3.fromRGB(120, 220, 255), 10, 9)
                    task.delay(1, function() sp:Destroy() end)
                end
            end
        end
        local ang = math.rad(lerp(200, 150, easeInOut(a)))
        local r = lerp(22, 18, a)
        local cam = s.center + V3(math.cos(ang) * r, lerp(6, 4, a), math.sin(ang) * r)
        return CFrame.lookAt(cam, s.center + V3(0, 1.2, 0)), 58
    end,
    leave = function(s)
        playAnim(nil)
        for _, g in ipairs(s.gems) do g.model:Destroy() end
    end,
})

-- 4. EGG ARC -- blink egg-to-egg on every beat, camera pans from the Infinity Egg
shot({
    name = "eggs", bars = 1, area = "AUTO HATCH",
    prep = function(s)
        s.center = V3(-105.5, 0, -27)
        local eggs = {
            V3(-128.6, 0, 9.8), V3(-144.2, 0, -5.0), V3(-150.3, 0, -26.0), V3(-146.0, 0, -47.0), V3(-131.8, 0, -63.3),
        }
        s.spots = {}
        for i, e in ipairs(eggs) do
            local inward = flat(s.center - e).Unit
            local p = e + inward * 6.5
            local cf = standAt(p.X, p.Z, PLAZA_Y, s.center)
            assert(cf, "egg spot off ground")
            s.spots[i] = cf
        end
        local gy = groundY(s.center.X, s.center.Z, PLAZA_Y) or 6
        s.camBase = V3(s.center.X - 9, gy + 6, s.center.Z + 2)
    end,
    enter = function(s, skipped)
        setClock(14)
        s.idx = 1
        pose(s.spots[1])
        playAnim(nil)
    end,
    beat = function(s, i, catchingUp)
        if i == 0 then return end
        s.idx = math.min(i + 1, #s.spots)
        if catchingUp then pose(s.spots[s.idx]) else blink(s.spots[s.idx], Color3.fromRGB(255, 205, 90), true) end
    end,
    frame = function(s, a, lt)
        -- look target glides to the newest egg spot a little after each blink (camera operator catching up)
        local bi = math.floor(lt / BEAT)
        local frac = (lt - bi * BEAT) / BEAT
        local cur = s.spots[math.clamp(bi + 1, 1, #s.spots)].Position
        local prev = s.spots[math.clamp(bi, 1, #s.spots)].Position
        local look = prev:Lerp(cur, bi == 0 and 1 or easeOut(frac * 1.9))
        local cam = s.camBase + V3(0, lerp(0, -1.5, a), 0)
        return CFrame.lookAt(cam, look + V3(0, 0.5, 0)), 54
    end,
})

-- 5. CLOUD HOP (the drop) -- camera on the jump column's axis looking straight down, character
--    blinks cloud-to-cloud spiralling DOWN through the clouds; beats in bar 1, eighth notes in bar 2
shot({
    name = "clouds", bars = 2, cut = "flash", area = "TELEPORTS",
    prep = function(s)
        local stages = workspace:FindFirstChild("Stages")
        assert(stages, "no Stages")
        local axis = V3(5, 0, 85)
        local clouds = {}
        for _, st in ipairs(stages:GetChildren()) do
            for _, p in ipairs(st:GetChildren()) do
                if p:IsA("BasePart") and p.Name == "Part" and p.Position.Y > 950 and p.Position.Y < 1700 and p.Size.X >= 11 then
                    local off = flat(p.Position - axis)
                    if off.Magnitude < 52 then
                        clouds[#clouds + 1] = { part = p, ang = math.atan2(off.Z, off.X), r = off.Magnitude, top = p.Position.Y + p.Size.Y / 2 }
                    end
                end
            end
        end
        table.sort(clouds, function(x, y) return x.top > y.top end)
        assert(#clouds >= 8, "not enough clouds")
        -- greedy spiral: each hop goes down 18-90 studs and as close as possible to +115 degrees around
        local path = { clouds[1] }
        local used = { [clouds[1]] = true }
        while #path < 12 do
            local last = path[#path]
            local want = last.ang + math.rad(115)
            local best, bestScore
            for _, c in ipairs(clouds) do
                local dy = last.top - c.top
                if not used[c] and dy > 18 and dy < 90 then
                    local da = math.abs(math.atan2(math.sin(c.ang - want), math.cos(c.ang - want)))
                    local score = da + dy / 120
                    if not bestScore or score < bestScore then best, bestScore = c, score end
                end
            end
            if not best then break end
            used[best] = true
            path[#path + 1] = best
        end
        assert(#path >= 8, "cloud path too short")
        s.path = {}
        for i, c in ipairs(path) do
            local p = c.part.Position
            local spot = V3(p.X, c.top, p.Z)
            s.path[i] = standCF(spot, spot + V3(math.cos(c.ang + 1.6), 0, math.sin(c.ang + 1.6)))
        end
        -- hop times: beats 0-3 of bar 1, then eighth notes through bar 2
        s.times = {}
        for i = 0, 3 do s.times[#s.times + 1] = i * BEAT end
        for i = 0, 7 do s.times[#s.times + 1] = BAR + i * BEAT / 2 end
        while #s.times > #s.path do table.remove(s.times) end
        s.axis = axis
        s.topY = s.path[1].Position.Y
        s.botY = s.path[#s.path].Position.Y
    end,
    enter = function(s)
        setClock(13)
        s.hop = 1
        pose(s.path[1])
        playAnim("fall", 1)
        local char = player.Character
        if char then
            local hl = Instance.new("Highlight")
            hl.FillTransparency = 1
            hl.OutlineColor = Color3.new(1, 1, 1)
            hl.OutlineTransparency = 0.15
            hl.DepthMode = Enum.HighlightDepthMode.Occluded
            hl.Parent = char
            s.hl = hl
        end
    end,
    frame = function(s, a, lt)
        local want = 1
        for i, tt in ipairs(s.times) do if lt >= tt then want = i end end
        while s.hop < want do
            s.hop += 1
            blink(s.path[s.hop], Color3.fromRGB(150, 220, 255), true)
        end
        -- the camera glides after each landing (0.3s ease) and stays 60% of the way from the axis to
        -- the character: the tunnel stays centred-ish while the character stays big in frame
        local i = math.max(1, want)
        local prev = s.path[math.max(1, i - 1)].Position
        local curP = s.path[i].Position
        local k = i == 1 and 1 or easeOut((lt - s.times[i]) / 0.3)
        local follow = prev:Lerp(curP, k)
        local xz = flat(s.axis):Lerp(flat(follow), 0.6)
        local yaw = lt * math.rad(24)
        local pos = V3(xz.X, follow.Y + 40, xz.Z)
        return CF(pos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(-82), 0, 0), 78
    end,
    leave = function(s)
        playAnim(nil)
        if s.hl then s.hl:Destroy() end
    end,
})

-- 6. TWILIGHT -- night, low hero angle, purple bursts across the neon island
shot({
    name = "twilight", bars = 1, area = "SKY ISLANDS",
    prep = function(s)
        local isl = workspace.Worlds:FindFirstChild("The Overworld") and workspace.Worlds["The Overworld"].Islands:FindFirstChild("Twilight")
        assert(isl, "no Twilight")
        local center = V3(-55, 0, 83)
        local tries = { V3(-72, 0, 62), V3(-38, 0, 66), V3(-30, 0, 100), V3(-66, 0, 104), V3(-52, 0, 82), V3(-82, 0, 86), V3(-46, 0, 116) }
        s.spots = {}
        for _, p in ipairs(tries) do
            local y = groundY(p.X, p.Z, 6930, 120)
            -- face the camera's side of the island (it orbits around +X/+Z)
            if y and #s.spots < 4 then s.spots[#s.spots + 1] = standCF(V3(p.X, y, p.Z), center + V3(45, 0, 55)) end
        end
        assert(#s.spots >= 3, "twilight surface not found")
        s.center = V3(center.X, s.spots[1].Position.Y, center.Z)
    end,
    enter = function(s)
        setClock(0)
        s.idx = 1
        pose(s.spots[1])
        playAnim(nil)
    end,
    beat = function(s, i, catchingUp)
        if i == 0 then return end
        s.idx = math.min(i + 1, #s.spots)
        if catchingUp then pose(s.spots[s.idx]) else blink(s.spots[s.idx], Color3.fromRGB(200, 80, 255), true) end
    end,
    frame = function(s, a)
        local ang = math.rad(lerp(35, 70, a))
        local r = lerp(62, 52, a)
        local cam = s.center + V3(math.cos(ang) * r, lerp(30, 38, a), math.sin(ang) * r)
        return CFrame.lookAt(cam, s.center + V3(0, -6, 0)), 55
    end,
})

-- 7. SWITCH -- GTA character-switch: over-the-shoulder, then three jumps up into the sky
shot({
    name = "switch", bars = 1,
    prep = function(s)
        local stand = standAt(47, -50, PLAZA_Y, V3(58, 0, -71))
        assert(stand, "switch spot off ground")
        s.stand = stand
        local p = stand.Position
        s.levels = { 0, 34, 190, 620 }
        s.p = p
    end,
    enter = function(s)
        setClock(14)
        pose(s.stand)
        playAnim(nil)
    end,
    frame = function(s, a, lt)
        local bi = math.floor(lt / BEAT)
        local frac = (lt - bi * BEAT) / BEAT
        local l0 = s.levels[math.clamp(bi, 1, 4)] or 0
        local l1 = s.levels[math.clamp(bi + 1, 1, 4)]
        local k = bi == 0 and 0 or easeInOut(frac / 0.45)
        local h = lerp(bi == 0 and 0 or l0, l1, k)
        if bi == 0 then h = 0 end
        -- blur + desaturate while moving between levels (the switch "whoosh")
        local moving = (bi > 0 and frac < 0.45) and math.sin(math.pi * clamp01(frac / 0.45)) or 0
        if blur then blur.Size = moving * 18 end
        if grade then grade.Saturation = lerp(0.18, -0.45, clamp01(h / 620)) end
        local back = s.stand.LookVector
        if h < 1 then
            local cam = s.p - back * 7 + V3(1.6, 2.2, 0) + s.stand.RightVector * 1.5
            return CFrame.lookAt(cam, s.p + back * 10 + V3(0, 1, 0)), 60
        end
        local cam = s.p - back * lerp(7, 40, clamp01(h / 620)) + V3(0, h + 2, 0)
        return CFrame.lookAt(cam, s.p + V3(0, 0, 0.01)), 60 + clamp01(h / 620) * 10
    end,
    leave = function()
        if blur then blur.Size = 0 end
    end,
})

-- 8. TITLE -- from the top of the switch, slow drift over the island, logo slams on the downbeat
shot({
    name = "title", bars = 2, cut = "flash",
    prep = function(s)
        local sw
        for _, x in ipairs(SHOTS) do if x.name == "switch" then sw = x end end
        s.p = sw and sw.p or V3(52, 10, -60)
        s.back = sw and sw.stand.LookVector or V3(0, 0, -1)
    end,
    enter = function(s) setClock(14) end,
    frame = function(s, a, lt)
        if grade then grade.Saturation = lerp(-0.45, 0.12, smooth(lt / 0.9)) end
        local h = lerp(620, 540, easeOut(a))
        local yaw = CFrame.Angles(0, math.rad(lerp(0, 14, a)), 0)
        local offset = yaw:VectorToWorldSpace(-s.back * lerp(40, 70, a))
        local cam = s.p + offset + V3(0, h + 2, 0)
        local alpha = easeOut(lt / 0.45)
        local vpScale = math.max(gui.AbsoluteSize.Y, 300) / 540
        titleScale.Scale = vpScale * lerp(1.3, 1, easeOut(lt / 0.6)) * lerp(1, 1.04, a)
        dim.BackgroundTransparency = lerp(1, 0.72, smooth(lt / 0.6))
        setTitleAlpha(alpha, smooth((lt - 0.9) / 0.6))
        return CFrame.lookAt(cam, s.p + V3(0, 0, 0.01)), lerp(70, 64, a)
    end,
})

------------------------------------------------------------------------
-- SESSION
------------------------------------------------------------------------
local sound
local songClock0 = nil
local finishing = false
local wantSkip = false

local function songTime()
    if OPT.freezeAt then return OPT.freezeAt end
    if not songClock0 then return 0 end
    local now = os.clock() - songClock0
    if sound and sound.IsPlaying and sound.TimeLength > 0 then
        local tp = sound.TimePosition
        if math.abs(tp - now) > 0.09 then
            songClock0 = os.clock() - tp
            now = tp
        end
    end
    return now
end

local function loadAudio()
    if OPT.silent or OPT.freezeAt then return nil end
    pcall(function() if isfolder and not isfolder("SplashHub_Configs") then makefolder("SplashHub_Configs") end end)
    if not (writefile and getcustomasset) then return nil end
    local have = false
    pcall(function() have = isfile(AUDIO_FILE) and #readfile(AUDIO_FILE) > 100000 end)
    if not have then
        loadingText.Text = "LOADING MUSIC"
        local ok, body = pcall(function() return game:HttpGet(AUDIO_URL) end)
        if not ok or type(body) ~= "string" or #body < 100000 then return nil end
        if not pcall(writefile, AUDIO_FILE, body) then return nil end
    end
    local ok, asset = pcall(getcustomasset, AUDIO_FILE)
    if not ok or not asset then return nil end
    local s = own(Instance.new("Sound"))
    s.Name = "SplashIntroTheme"
    s.SoundId = asset
    s.Volume = 0.85
    s.Parent = SoundService
    local t0 = os.clock()
    while not s.IsLoaded and os.clock() - t0 < 10 do task.wait(0.05) end
    return s.IsLoaded and s or nil
end

-- take over the screen the way the game's own egg cutscenes do, and remember how to give it back
local function takeOver()
    local Music          = gameModule("Client.Music")
    local PlayerRender   = gameModule("Client.PlayerRender")
    local PetRender      = gameModule("Client.PetRender")
    local PlayerControls = gameModule("Client.PlayerControls")

    if Music and Music.SetVolume then
        local v = type(Music.Volume) == "number" and Music.Volume or 0.5
        pcall(function() Music:SetVolume(0) end)
        onRestoreGame(function() Music:SetVolume(v) end)
    end
    if PlayerRender and PlayerRender.SetPlayersVisible then
        pcall(function() PlayerRender:SetPlayersVisible(false) end)
        onRestoreGame(function() PlayerRender:SetPlayersVisible(true) end)
    end
    if PetRender and PetRender.SetVisible then
        pcall(function() PetRender:SetVisible(false) end)
        onRestoreGame(function() PetRender:SetVisible(true) end)
    end
    if PlayerControls and PlayerControls.Disable then
        pcall(function() PlayerControls:Disable() end)
        onRestoreGame(function() PlayerControls:Enable() end)
    end
    settle()

    -- lighting: stop the height-driven sky so each shot can pick its own time of day
    local dyn, clock = Lighting:GetAttribute("DynamicSky"), Lighting.ClockTime
    Lighting:SetAttribute("DynamicSky", false)
    track(Lighting:GetPropertyChangedSignal("ClockTime"):Connect(function()
        if lightingTarget and math.abs(Lighting.ClockTime - lightingTarget) > 0.01 then Lighting.ClockTime = lightingTarget end
    end))
    onRestore(function()
        Lighting:SetAttribute("DynamicSky", dyn)
        Lighting.ClockTime = clock
    end)

    -- every PlayerGui layer (HUD, prompts, popups) + our own overhead tag
    local hidden = {}
    local function hide(g)
        if (g:IsA("LayerCollector")) and g.Enabled and hidden[g] == nil then
            hidden[g] = true
            g.Enabled = false
        end
    end
    local pg = player:FindFirstChild("PlayerGui")
    if pg then
        for _, g in ipairs(pg:GetChildren()) do hide(g) end
        track(pg.ChildAdded:Connect(function(g) task.defer(hide, g) end))
    end
    -- world billboards too (event timers, NPC labels, egg prompts) -- including ones streamed in mid-intro
    for _, d in ipairs(workspace:GetDescendants()) do if d:IsA("BillboardGui") then hide(d) end end
    track(workspace.DescendantAdded:Connect(function(d)
        if d:IsA("BillboardGui") then task.defer(hide, d) end
    end))
    pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)
    onRestore(function()
        for g in pairs(hidden) do pcall(function() g.Enabled = true end) end
        pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true) end)
    end)

    -- any other looping music that slipped through (restored after)
    local muted = {}
    local function sweep()
        for _, root in ipairs({ SoundService, workspace }) do
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA("Sound") and d ~= sound and d.Looped and d.IsPlaying and d.Volume > 0 and not muted[d] then
                    muted[d] = d.Volume
                    d.Volume = 0
                end
            end
        end
    end
    pcall(sweep)
    onRestore(function() for s, v in pairs(muted) do pcall(function() s.Volume = v end) end end)

    -- post: warm grade + bloom + blur (under the camera, so the game's own Lighting effects stay untouched)
    local cam = workspace.CurrentCamera
    grade = own(Instance.new("ColorCorrectionEffect"))
    grade.Name = "SplashIntroGrade"
    grade.Contrast = 0.1
    grade.Saturation = 0.18
    grade.TintColor = Color3.fromRGB(255, 240, 222)
    grade.Parent = cam
    local bloom = own(Instance.new("BloomEffect"))
    bloom.Intensity = 0.5
    bloom.Size = 28
    bloom.Threshold = 1.7
    bloom.Parent = cam
    blur = own(Instance.new("BlurEffect"))
    blur.Size = 0
    blur.Parent = cam
    settle()
end

local function finish(fast)
    if finishing then return end
    finishing = true
    tween(black, fast and 0.35 or 0.9, { BackgroundTransparency = 0 }, Enum.EasingStyle.Sine)
    if sound then tween(sound, fast and 0.5 or 1.4, { Volume = 0 }, Enum.EasingStyle.Sine) end
    task.wait(fast and 0.45 or 1.0)
    restoreAll()
end

local function run()
    if not OPT.keepGameIntro then skipGameIntro(60) end
    settle()

    local _, hrp, hum
    local t0 = os.clock()
    repeat
        _, hrp, hum = getChar()
        if not (hrp and hum) then task.wait(0.1) end
    until (hrp and hum) or os.clock() - t0 > 20
    assert(hrp and hum, "no character")

    local cam = workspace.CurrentCamera
    local saved = { cf = hrp.CFrame, anchored = hrp.Anchored, fov = cam.FieldOfView }
    onRestore(function()
        local _, r, h = getChar()
        if r then
            r.CFrame = saved.cf
            r.AssemblyLinearVelocity = Vector3.zero
            r.Anchored = saved.anchored
        end
        playAnim(nil)
        local c = workspace.CurrentCamera
        c.FieldOfView = saved.fov
        -- hand back a normal third-person view behind the character (the camera module adopts it)
        local back = saved.cf.LookVector
        c.CFrame = CFrame.lookAt(saved.cf.Position - back * 14 + V3(0, 6, 0), saved.cf.Position + V3(0, 1.5, 0))
        c.CameraType = Enum.CameraType.Custom
        if h then c.CameraSubject = h end
        c.FieldOfView = saved.fov
    end)

    sound = loadAudio()
    loadingText.Text = "LOADING"
    fxFolder.Parent = workspace

    local list, t = {}, 0
    for _, s in ipairs(SHOTS) do
        local ok, err = pcall(s.prep, s)
        if ok then
            s.t0, s.len = t, s.bars * BAR
            t += s.len
            list[#list + 1] = s
        else
            warn("[SplashIntro] shot '" .. s.name .. "' skipped: " .. tostring(err))
        end
    end
    assert(#list > 0, "no usable shots")
    local total = t

    takeOver()
    cam.CameraType = Enum.CameraType.Scriptable

    track(UIS.InputBegan:Connect(function(input)
        local k = input.KeyCode
        if k == Enum.KeyCode.Space or k == Enum.KeyCode.Return or k == Enum.KeyCode.ButtonB then wantSkip = true end
    end))
    local lastTap = 0
    track(UIS.TouchStarted:Connect(function()
        if os.clock() - lastTap < 0.35 then wantSkip = true end
        lastTap = os.clock()
    end))

    loading.Visible = false
    local startAt = OPT.startAt or 0
    if sound then
        sound.TimePosition = startAt
        sound:Play()
    end
    songClock0 = os.clock() - startAt

    local cur, curIdx, nextBeat = nil, 0, 0
    local revealed = false

    RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value + 1, function()
        if finishing then return end
        local now = songTime()
        local idx = math.max(curIdx, 1)
        while list[idx + 1] and now >= list[idx + 1].t0 do idx += 1 end
        if idx ~= curIdx then
            if cur and cur.leave then pcall(cur.leave, cur) end
            cur, curIdx = list[idx], idx
            local skipped = math.max(0, math.floor((now - cur.t0) / BEAT + 1e-4))
            if cur.enter then
                local ok, err = pcall(cur.enter, cur, skipped)
                if not ok then warn("[SplashIntro] enter " .. cur.name .. ": " .. tostring(err)) end
            end
            if cur.cut == "flash" and skipped == 0 then
                flash.BackgroundTransparency = 0
                tween(flash, 0.6, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
            end
            if cur.beat then
                for b = 0, skipped - 1 do pcall(cur.beat, cur, b, true) end
            end
            nextBeat = skipped
            credit.Text = cur.credit or ""
            credit.Position = cur.creditPos or UDim2.fromScale(0.7, 0.5)
            area.Text = cur.area or ""
        end
        local lt = now - cur.t0
        if cur.beat then
            while nextBeat < cur.bars * 4 and lt >= nextBeat * BEAT do
                pcall(cur.beat, cur, nextBeat, false)
                nextBeat += 1
            end
        end
        local ok, cf, fov = pcall(cur.frame, cur, clamp01(lt / cur.len), lt)
        if ok and cf then
            cam.CFrame = cf
            if fov then cam.FieldOfView = fov end
        elseif not ok then
            warn("[SplashIntro] frame " .. cur.name .. ": " .. tostring(cf))
        end
        if not revealed then
            revealed = true
            if OPT.freezeAt then black.BackgroundTransparency = 1 else tween(black, 0.2, { BackgroundTransparency = 1 }) end
        end
        letterbox(1)
        local ca = cur.credit and textAlpha(lt, cur.len, 0.3) or 0
        credit.TextTransparency = 1 - ca
        local aa = cur.area and textAlpha(lt, cur.len, 0.25, cur.len - 0.25) or 0
        area.TextTransparency = 1 - aa
        areaStroke.Transparency = 1 - aa
        skipHint.TextTransparency = (OPT.freezeAt or now > BAR * 2) and 1 or lerp(0.45, 1, smooth((now - BAR * 1.5) / (BAR * 0.5)))
        if not OPT.freezeAt and (now >= total or wantSkip) then task.spawn(finish, wantSkip) end
    end)

    while not finishing do task.wait(0.1) end
    while not restored do task.wait(0.05) end
end

local function destroyGuiSoon()
    -- a fresh thread has full capabilities even if ours was tainted by a game-module call
    task.spawn(function()
        task.wait()
        pcall(function() gui:Destroy() end)
    end)
end

local function cleanup()
    finishing = true
    pcall(function() gui.Enabled = false end)
    restoreAll()
    destroyGuiSoon()
    Intro.done = true
end
genv._splashIntroCleanup = cleanup
Intro.skip = function() wantSkip = true end

task.spawn(function()
    local ok, err = xpcall(run, function(e) return tostring(e) .. "\n" .. debug.traceback() end)
    if not ok then warn("[SplashIntro] " .. tostring(err)) end
    restoreAll()
    settle()
    pcall(function()
        credit.TextTransparency, area.TextTransparency = 1, 1
        setTitleAlpha(0, 0)
    end)
    tween(black, 0.7, { BackgroundTransparency = 1 }, Enum.EasingStyle.Sine)
    task.wait(0.75)
    destroyGuiSoon()
    Intro.done = true
    if genv._splashIntroCleanup == cleanup then genv._splashIntroCleanup = nil end
end)

return Intro
