--[[
    splash_intro.lua  --  Splash Hub launch cinematic
    "Welcome to Los Santos" from its 18.80s downbeat (89.1 BPM). One shot per bar, every cut lands
    on the bar's kick; credits + feature captions + title card in the GTA V trailer style.
    14 bars: the drop (29.58s) hits the cloud hop, the 40.36s phrase hits the menu, 51.13s the title.
    Also skips BGSI's own intro screen.

    getgenv().SplashIntro        -> { done = bool, skip = fn }
    getgenv().SplashIntroOptions -> optional { audioUrl, startAt (sec), freezeAt (sec), keepGameIntro, silent, skipOnly }
]]

local genv = (getgenv and getgenv()) or _G
if genv._splashIntroCleanup then pcall(genv._splashIntroCleanup) end

local OPT = genv.SplashIntroOptions or {}
local AUDIO_URL  = OPT.audioUrl or "https://raw.githubusercontent.com/fent700/700/refs/heads/splash/splash/intro.mp3"
local AUDIO_FILE = "SplashHub_Configs/splash_intro_theme_v2.mp3"
local AUDIO_MIN_BYTES = 400000
-- feature captions are pre-rendered images of whole phrases set in Pricedown (the GTA V typeface).
-- Only finished lettering ships -- never the font file (Typodermic desktop EULA s2.2). Rects = sheet px.
local CAPTION_URL  = OPT.captionUrl or "https://raw.githubusercontent.com/fent700/700/refs/heads/splash/splash/intro_captions.png"
local CAPTION_FILE = "SplashHub_Configs/splash_intro_captions_v3.png"
local CAPTION_RECTS = {  -- sheet is 793x894: must stay <= 1024px or Roblox rescales it and these rects drift
    ["AUTO GEM FARM"]        = { 0, 0, 603, 102 },
    ["AUTO HATCH"]           = { 0, 132, 470, 102 },
    ["TELEPORTS"]            = { 0, 264, 421, 102 },
    ["AUTO FISH"]            = { 0, 396, 393, 102 },
    ["SKY ISLANDS"]          = { 0, 528, 473, 102 },
    ["ONE HUB. EVERYTHING."] = { 0, 660, 793, 102 },
    ["AUTO MINIGAMES"]       = { 0, 792, 635, 102 },
}
-- Roblox reports Sound.TimePosition ~0.25s before that audio is actually heard (measured from a
-- recording: every cut landed 0.26s ahead of its kick), so the picture runs this far behind it
local AUDIO_LATENCY = 0.24

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

local function remote()
    local ok, r = pcall(function() return RS.Shared.Framework.Network.Remote.RemoteEvent end)
    return ok and r or nil
end

------------------------------------------------------------------------
-- BGSI INTRO SKIP
-- Live build: Play.Button -> finish() (ClickableButton binds .Activated). Older builds opened a
-- High/Low graphics picker whose buttons called finish(). Play is wired LAST, so "Play has Activated
-- connections" = the intro is ready to be dismissed.
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
                for _, c in ipairs(playConns) do fireConn(c) end
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
local conns, spawned, restoreFns, gameRestoreFns = {}, {}, {}, {}
local fxFolder = Instance.new("Folder")
fxFolder.Name = "SplashIntroFX"

local function track(c) conns[#conns + 1] = c return c end
local function onRestore(fn) restoreFns[#restoreFns + 1] = fn end
local function onRestoreGame(fn) gameRestoreFns[#gameRestoreFns + 1] = fn end  -- BGSI module/remote calls: run last
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
local FONT_BODY   = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
local FONT_TITLE  = Font.new("rbxasset://fonts/families/Bangers.json", Enum.FontWeight.Regular)

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

-- z-order: picture < flash (4) < letterbox (5) < text (6-7) < black (9) < loading (10)
local flash  = frame({ Name = "Flash", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 4 })
local barTop = frame({ Name = "BarTop", BackgroundColor3 = Color3.new(), Size = UDim2.new(1, 0, 0, 0), ZIndex = 5 })
local barBot = frame({ Name = "BarBot", BackgroundColor3 = Color3.new(), AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 0), ZIndex = 5 })
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

-- feature caption: bottom right in the letterbox, in the logo's typeface, slides in from the right
local areaHolder = frame({ Name = "AreaHolder", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -44, 1, -22), Size = UDim2.fromScale(0.42, 0.075), ZIndex = 6 })
local area = label({ Parent = areaHolder, Name = "Area", Size = UDim2.fromScale(1, 1), FontFace = FONT_TITLE, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Right, TextTransparency = 1, Text = "", ZIndex = 6 })
local areaStroke = Instance.new("UIStroke", area)
areaStroke.Thickness = 2
areaStroke.Transparency = 1
local areaGrad = Instance.new("UIGradient", area)
areaGrad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(205, 240, 255))
areaGrad.Rotation = 90
-- the Pricedown version (used whenever the caption sheet loaded; the text label above is the fallback)
local areaImg = Instance.new("ImageLabel")
areaImg.Name = "AreaImage"
areaImg.BackgroundTransparency = 1
areaImg.AnchorPoint = Vector2.new(1, 1)
areaImg.ImageTransparency = 1
areaImg.ZIndex = 6
areaImg.Visible = false
areaImg.Parent = gui
local captionAsset = nil

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

-- first solid, visible surface below (x, fromY, z); anyVisible also accepts non-collidable props (dice)
local function groundY(x, z, fromY, depth, anyVisible)
    local exclude = { fxFolder }
    if player.Character then exclude[#exclude + 1] = player.Character end
    for _, p in ipairs(Players:GetPlayers()) do if p.Character then exclude[#exclude + 1] = p.Character end end
    local rendered = workspace:FindFirstChild("Rendered")
    if rendered and rendered:FindFirstChild("Pets") then exclude[#exclude + 1] = rendered.Pets end
    for _ = 1, 12 do
        rayParams.FilterDescendantsInstances = exclude
        local hit = workspace:Raycast(V3(x, fromY, z), V3(0, -(depth or 250), 0), rayParams)
        if not hit then return nil end
        if hit.Instance.Transparency < 0.9 and (hit.Instance.CanCollide or anyVisible) then return hit.Position.Y end
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

-- emit one of the game's own particle templates (RS.Assets.Fishing.*) at a point
local function gameBurst(templateName, pos, count)
    local tpl = RS:FindFirstChild("Assets") and RS.Assets:FindFirstChild("Fishing") and RS.Assets.Fishing:FindFirstChild(templateName)
    if not (tpl and tpl:IsA("ParticleEmitter")) then return end
    local holder = fxPart({ Transparency = 1, Size = Vector3.one, CFrame = CF(pos) })
    local pe = tpl:Clone()
    pe.Enabled = false
    pe.Parent = Instance.new("Attachment", holder)
    pe:Emit(count or 20)
    task.delay(2.5, function() holder:Destroy() end)
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

-- a short trail of bubbles popping along the teleport path (reads as motion, never as a glitch line)
local function bubbleTrail(a, b, color)
    local d = (b - a).Magnitude
    if d < 2 then return end
    local n = math.clamp(math.floor(d / 7), 3, 9)
    for i = 1, n do
        local k = i / (n + 1)
        local p = a:Lerp(b, k) + V3(0, math.sin(k * math.pi) * d * 0.08, 0)
        task.delay(k * 0.12, function()
            if not fxFolder.Parent then return end
            local s = 0.7 + math.sin(k * math.pi) * 0.9
            local bub = fxPart({ Shape = Enum.PartType.Ball, Material = Enum.Material.ForceField, Color = color, Size = Vector3.one * s, CFrame = CF(p) })
            tween(bub, 0.35, { Size = Vector3.one * s * 2.2, Transparency = 1 }, Enum.EasingStyle.Quad)
            task.delay(0.45, function() bub:Destroy() end)
        end)
    end
end

------------------------------------------------------------------------
-- CHARACTER CONTROL
------------------------------------------------------------------------
local animTracks = {}
local function animator()
    local _, _, hum = getChar()
    return hum and hum:FindFirstChildOfClass("Animator")
end

-- key = name in the character's Animate script ("run", "fall", "cheer"...) or any Animation instance
local function playAnim(key, speed, looped, animObj)
    local char = getChar()
    if not char then return end
    for n, tr in pairs(animTracks) do
        if n ~= key then pcall(function() tr:Stop(0.12) end) end
    end
    if key == nil then return end
    local tr = animTracks[key]
    if not tr then
        local anim = animObj
        if not anim then
            local animate = char:FindFirstChild("Animate")
            local holder = animate and animate:FindFirstChild(key)
            anim = holder and holder:FindFirstChildWhichIsA("Animation")
        end
        local an = animator()
        if not (anim and an) then return end
        local ok, t = pcall(function() return an:LoadAnimation(anim) end)
        if not ok then return end
        tr = t
        tr.Priority = Enum.AnimationPriority.Action
        animTracks[key] = tr
    end
    tr.Looped = looped ~= false
    if not tr.IsPlaying or looped == false then tr:Play(0.12) end
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

local function blink(cf, color)
    local from = charPos()
    burst(from, color)
    pose(cf)
    burst(cf.Position, color)
    bubbleTrail(from, cf.Position, color)
end

local lightingTarget = nil
local function setClock(h) lightingTarget = h pcall(function() Lighting.ClockTime = h end) end

local grade, blur -- created in takeOver()

-- camera look target that glides to each new spot a beat after the character blinks there
local function glideLook(spots, lt, speed)
    local bi = math.floor(lt / BEAT)
    local frac = (lt - bi * BEAT) / BEAT
    local cur = spots[math.clamp(bi + 1, 1, #spots)].Position
    local prev = spots[math.clamp(bi, 1, #spots)].Position
    return prev:Lerp(cur, bi == 0 and 1 or easeOut(frac * (speed or 1.9)))
end

------------------------------------------------------------------------
-- SHOTS  (bars = length; enter(shot, skippedBeats); beat(shot, i, catchingUp); frame(shot, a, lt) -> camCF, fov)
------------------------------------------------------------------------
local SHOTS = {}
local function shot(def) SHOTS[#SHOTS + 1] = def return def end
local function findShot(name) for _, s in ipairs(SHOTS) do if s.name == name then return s end end end

local PLAZA_Y = 80  -- raycast start height for overworld ground

-- 1. ESTABLISHING -- slow descending aerial over the island, "GUMTEETH PRESENTS"
shot({
    name = "establish", bars = 1, credit = "GUMTEETH  PRESENTS", noChar = true,
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
        s.a, s.b = a, b
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
        local side = fwd:Cross(V3(0, 1, 0))
        local cam = p - side * lerp(16, 12.5, a) + V3(0, lerp(1.4, 2.6, a), 0) + fwd * lerp(7, 3, a)
        return CFrame.lookAt(cam, p + fwd * 4 + V3(0, 1, 0)), 50
    end,
    leave = function() playAnim(nil) end,
})

-- 3. GEM VACUUM -- at the Gem Genie's feet on Zen (night, pink glow); gems pulled in on every beat
shot({
    name = "gems", bars = 1, area = "AUTO GEM FARM",
    prep = function(s)
        local stand = standAt(5, 14, 16060, V3(9, 0, 40))
        assert(stand, "genie spot off ground")
        s.stand = stand
        s.center = stand.Position
        local P = RS:FindFirstChild("Assets") and RS.Assets:FindFirstChild("Pickups")
        assert(P, "no pickup assets")
        local kinds = { "Gem", "Gem", "Gem", "Gem Box", "Gem", "Gem Chest", "Gem", "Gem Safe", "Gem", "Gem" }
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
            gy = math.max(gy, s.center.Y - hrpOffset() - 2)
            local _, size = m:GetBoundingBox()
            s.gems[i] = {
                model = m, home = V3(x, gy + size.Y / 2 + 0.6, z), phase = rng:NextNumber(0, 6.28),
                pull = ((i - 1) % 4) * BEAT + rng:NextNumber(0, 0.22), done = false,
            }
        end
    end,
    enter = function(s)
        setClock(0)
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
                    local p = g.home:Lerp(target, k * k) + V3(0, math.sin(k * math.pi) * 4, 0)
                    g.model:PivotTo(CF(p) * spin)
                else
                    g.done = true
                    g.model.Parent = nil
                    local sp = fxPart({ Transparency = 1, Size = Vector3.one, CFrame = CF(target) })
                    sparkle(sp, Color3.fromRGB(255, 120, 230), 10, 9)
                    task.delay(1, function() sp:Destroy() end)
                end
            end
        end
        -- low hero angle from the front: the genie towers over the character
        local ang = math.rad(lerp(68, 108, easeInOut(a)))
        local r = lerp(21, 17, a)
        local cam = s.center + V3(math.cos(ang) * r, lerp(3.2, 2.4, a), math.sin(ang) * r)
        return CFrame.lookAt(cam, s.center + V3(0, lerp(5.5, 5, a), 0)), 62
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
        local eggs = { V3(-128.6, 0, 9.8), V3(-144.2, 0, -5.0), V3(-150.3, 0, -26.0), V3(-146.0, 0, -47.0), V3(-131.8, 0, -63.3) }
        s.spots = {}
        for i, e in ipairs(eggs) do
            local p = e + flat(s.center - e).Unit * 6.5
            local cf = standAt(p.X, p.Z, PLAZA_Y, s.center)
            assert(cf, "egg spot off ground")
            s.spots[i] = cf
        end
        local gy = groundY(s.center.X, s.center.Z, PLAZA_Y) or 6
        s.camBase = V3(s.center.X - 9, gy + 6, s.center.Z + 2)
    end,
    enter = function(s)
        setClock(14)
        pose(s.spots[1])
        playAnim(nil)
    end,
    beat = function(s, i, catchingUp)
        if i == 0 then return end
        local cf = s.spots[math.min(i + 1, #s.spots)]
        if catchingUp then pose(cf) else blink(cf, Color3.fromRGB(255, 205, 90)) end
    end,
    frame = function(s, a, lt)
        local look = glideLook(s.spots, lt)
        return CFrame.lookAt(s.camBase + V3(0, lerp(0, -1.5, a), 0), look + V3(0, 0.5, 0)), 54
    end,
})

-- 5. CLOUD HOP (the drop) -- camera over the jump column looking down, character blinks cloud-to-cloud
--    spiralling DOWN; beats in bar 1, eighth notes in bar 2. Clouds above the character are hidden so
--    nothing passes between the lens and the character.
shot({
    name = "clouds", bars = 2, cut = "flash", area = "TELEPORTS",
    prep = function(s)
        local stages = workspace:FindFirstChild("Stages")
        assert(stages, "no Stages")
        local axis = V3(5, 0, 85)
        local clouds = {}
        s.occluders = {}
        for _, d in ipairs(stages:GetDescendants()) do
            if d:IsA("BasePart") and d.Position.Y > 900 and d.Position.Y < 1900 then
                s.occluders[#s.occluders + 1] = d
                if d.Name == "Part" and d.Parent and d.Parent.Parent == stages and d.Position.Y > 950 and d.Position.Y < 1700 and d.Size.X >= 11 then
                    local off = flat(d.Position - axis)
                    if off.Magnitude < 52 then
                        clouds[#clouds + 1] = { part = d, ang = math.atan2(off.Z, off.X), top = d.Position.Y + d.Size.Y / 2 }
                    end
                end
            end
        end
        table.sort(clouds, function(x, y) return x.top > y.top end)
        assert(#clouds >= 8, "not enough clouds")
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
        s.times = {}
        for i = 0, 3 do s.times[#s.times + 1] = i * BEAT end
        for i = 0, 7 do s.times[#s.times + 1] = BAR + i * BEAT / 2 end
        while #s.times > #s.path do table.remove(s.times) end
        s.axis = axis
        s.hidden = {}
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
            blink(s.path[s.hop], Color3.fromRGB(150, 220, 255))
        end
        local i = math.max(1, want)
        local prev = s.path[math.max(1, i - 1)].Position
        local k = i == 1 and 1 or smooth((lt - s.times[i]) / 0.32)  -- ease in AND out: no jolt on the first frame
        local follow = prev:Lerp(s.path[i].Position, k)
        local xz = flat(s.axis):Lerp(flat(follow), 0.6)
        local camY = follow.Y + 40
        -- anything between the character's cloud and the lens is cut away (that's the grey slab)
        local floor = math.min(follow.Y, s.path[i].Position.Y) + 4
        for _, p in ipairs(s.occluders) do
            local y = p.Position.Y
            local hide = y > floor and y < camY + 30
            if hide ~= (s.hidden[p] == true) then
                s.hidden[p] = hide or nil
                p.LocalTransparencyModifier = hide and 1 or 0
            end
        end
        return CF(V3(xz.X, camY, xz.Z)) * CFrame.Angles(0, lt * math.rad(24), 0) * CFrame.Angles(math.rad(-82), 0, 0), 78
    end,
    leave = function(s)
        playAnim(nil)
        if s.hl then s.hl:Destroy() end
        for p in pairs(s.hidden) do pcall(function() p.LocalTransparencyModifier = 0 end) end
        s.hidden = {}
    end,
})

-- 6. FISHING -- Fisher's Island pier: cast, bite, a fish leaps out on the last beat. Purely visual:
--    the rod/bobber/fish/animations are the game's own assets, no fishing remotes (no bait spent).
shot({
    name = "fishing", bars = 1, area = "AUTO FISH",
    prep = function(s)
        local stand = standAt(-23652, -160, 60, V3(-23652, 0, -220))
        assert(stand, "pier spot off ground")
        s.stand = stand
        local A = RS.Assets
        local rodName = "Golden Rod"
        pcall(function()
            local LD = require(RS.Client.Framework.Services.LocalData)
            local d = LD:Get()
            if d and d.EquippedRod and A.FishingRods:FindFirstChild(d.EquippedRod) then rodName = d.EquippedRod end
        end)
        s.rodTemplate = A.FishingRods:FindFirstChild(rodName) or A.FishingRods:FindFirstChildWhichIsA("Model")
        assert(s.rodTemplate, "no rod model")
        s.bobberTemplate = A.Bobbers:FindFirstChildWhichIsA("BasePart")
        local fishPick
        for _, n in ipairs({ "Sun Marlin", "Blaze Shark", "Molten Devilfish", "Cod" }) do
            fishPick = fishPick or A.Fish:FindFirstChild(n)
        end
        s.fishTemplate = fishPick or A.Fish:FindFirstChildWhichIsA("Model")
        -- the game's fishing animations live next to its rod component
        s.anims = {}
        local fishing = RS.Client.Gui.Frames:FindFirstChild("Fishing")
        if fishing then
            for _, d in ipairs(fishing:GetDescendants()) do
                if d:IsA("Animation") and not s.anims[d.Name] then s.anims[d.Name] = d end
            end
        end
        -- water point 15 studs out along the pier's line
        local look = stand.LookVector
        local wp = stand.Position + flat(look).Unit * 15
        local wy = groundY(wp.X, wp.Z, 40, 80) or 2.4
        local okWater = false
        rayParams.FilterDescendantsInstances = { fxFolder, player.Character }
        local hit = workspace:Raycast(V3(wp.X, 40, wp.Z), V3(0, -80, 0), rayParams)
        if hit then wy, okWater = hit.Position.Y, true end
        s.water = V3(wp.X, wy + (okWater and 0.15 or 0), wp.Z)
        s.groundAtFeet = stand.Position.Y - hrpOffset()
    end,
    enter = function(s)
        setClock(14)
        pose(s.stand)
        playAnim(nil)
        local char, _, hum = getChar()
        local hand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm"))
        if hand then
            local rod = s.rodTemplate:Clone()
            for _, d in ipairs(rod:GetDescendants()) do
                if d:IsA("BasePart") then d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch, d.Massless = false, false, false, false, true end
            end
            local handle = rod:FindFirstChild("Handle")
            if handle then
                handle.Transparency = 1
                for _, d in ipairs(rod:GetDescendants()) do
                    if d:IsA("BasePart") and d ~= handle then
                        local w = Instance.new("WeldConstraint")
                        w.Part0, w.Part1 = handle, d
                        w.Parent = d
                    end
                end
                local m = Instance.new("Motor6D")
                m.Part0, m.Part1 = hand, handle
                m.C0 = (hum and hum.RigType == Enum.HumanoidRigType.R6) and (CF(0, -1, 0) * CFrame.Angles(-math.pi / 2, 0, 0)) or CFrame.Angles(-math.pi / 2, 0, 0)
                m.Parent = handle
                rod.Parent = char
                s.rod = rod
                local tip = rod:FindFirstChild("Tip", true)
                s.tipAtt = Instance.new("Attachment")
                s.tipAtt.Parent = (tip and tip:IsA("BasePart")) and tip or handle
            end
        end
        local bob = s.bobberTemplate and s.bobberTemplate:Clone() or fxPart({ Shape = Enum.PartType.Ball, Color = Color3.fromRGB(230, 60, 60), Size = Vector3.one * 0.8 })
        bob.Anchored, bob.CanCollide, bob.CanQuery, bob.CanTouch = true, false, false, false
        bob.Transparency = 1
        bob.Parent = fxFolder
        s.bobber = bob
        local bobAtt = Instance.new("Attachment", bob)
        if s.tipAtt then
            local beam = Instance.new("Beam")
            beam.Attachment0, beam.Attachment1 = s.tipAtt, bobAtt
            beam.Width0, beam.Width1 = 0.06, 0.06
            beam.Color = ColorSequence.new(Color3.fromRGB(240, 240, 240))
            beam.LightEmission = 0.4
            beam.FaceCamera = true
            beam.Segments = 16
            beam.Enabled = false
            beam.Parent = bob
            s.line = beam
        end
        local fish = s.fishTemplate:Clone()
        for _, d in ipairs(fish:GetDescendants()) do
            if d:IsA("BasePart") then d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch = true, false, false, false end
        end
        local _, size = fish:GetBoundingBox()
        local longest = math.max(size.X, size.Y, size.Z)
        if longest > 0 then pcall(function() fish:ScaleTo(fish:GetScale() * (5.5 / longest)) end) end
        fish.Parent = nil
        s.fish = fish
        s.fishShown = false
        if s.anims.CastIdle then playAnim("fishIdle", 1, true, s.anims.CastIdle) end
    end,
    beat = function(s, i, catchingUp)
        if i == 0 and s.anims.Cast then playAnim("fishCast", 1, false, s.anims.Cast) end
        if i == 1 and s.anims.CastIdle then playAnim("fishIdle", 1, true, s.anims.CastIdle) end
        if i == 2 then
            if s.anims.FishFound then playAnim("fishFound", 1, false, s.anims.FishFound) end
            if not catchingUp then gameBurst("BobberHooked", s.water, 18) end
        end
        if i == 3 then
            if s.anims.FishCaught then playAnim("fishCaught", 1, false, s.anims.FishCaught) end
            if not catchingUp then gameBurst("BobberSplash", s.water, 30) end
        end
    end,
    frame = function(s, a, lt)
        local tipPos = s.tipAtt and s.tipAtt.WorldPosition or (s.stand.Position + V3(0, 3, 0))
        -- bobber: flies out at 0.2-0.65s, floats, dips on the bite (beat 2), yanked on beat 3
        local cast0, cast1 = 0.2, 0.65
        local bobPos
        if lt < cast0 then
            bobPos = tipPos
        elseif lt < cast1 then
            local k = (lt - cast0) / (cast1 - cast0)
            bobPos = tipPos:Lerp(s.water, k) + V3(0, math.sin(k * math.pi) * 5, 0)
        else
            local dip = (lt > 2 * BEAT and lt < 3 * BEAT) and (0.35 + math.sin(lt * 22) * 0.25) or 0
            bobPos = s.water + V3(0, math.sin(lt * 4) * 0.12 - dip, 0)
            if not s.splashed then
                s.splashed = true
                gameBurst("BobberSplash", s.water, 16)
            end
        end
        if s.bobber then
            s.bobber.CFrame = CF(bobPos)
            s.bobber.Transparency = (lt >= cast0 and lt < 3 * BEAT) and 0 or 1
        end
        if s.line then
            s.line.Enabled = lt >= cast0 and lt < 3 * BEAT + 0.1
            s.line.CurveSize0 = lt < cast1 and 0 or -1.5
        end
        -- the catch: fish leaps out of the water in an arc and spins over the character's head
        local leap0 = 3 * BEAT
        if lt >= leap0 then
            if not s.fishShown then
                s.fishShown = true
                s.fish.Parent = fxFolder
            end
            local k = clamp01((lt - leap0) / 0.5)
            local over = s.stand.Position + V3(0, 1.8, 0) + flat(s.stand.LookVector) * 3.5
            local p = s.water:Lerp(over, easeOut(k)) + V3(0, math.sin(k * math.pi) * 3.2, 0)
            s.fish:PivotTo(CFrame.lookAt(p, p + (over - s.water).Unit) * CFrame.Angles(0, 0, lt * 9) * CFrame.Angles(lt * 6, 0, 0))
            if k >= 1 and not s.starred then
                s.starred = true
                gameBurst("FinishStars", over, 25)
                sparkle(s.bobber or fxPart({ Transparency = 1, Size = Vector3.one, CFrame = CF(over) }), Color3.fromRGB(255, 225, 120), 16, 10)
            end
        end
        -- low side shot along the pier: character left, line arcing out over the ocean
        local side = s.stand.RightVector
        local base = s.stand.Position
        local cam = base + side * lerp(12.5, 11, a) + V3(0, lerp(1.4, 2, a), 0) + s.stand.LookVector * lerp(-3.5, -1.5, a)
        local look = base:Lerp(s.water, 0.42) + V3(0, 2.2, 0)
        return CFrame.lookAt(cam, look), 62
    end,
    leave = function(s)
        playAnim(nil)
        for _, inst in ipairs({ s.rod, s.bobber, s.fish }) do pcall(function() inst:Destroy() end) end
        s.rod, s.bobber, s.fish, s.line, s.tipAtt = nil, nil, nil, nil, nil
        s.splashed, s.starred = false, false
    end,
})

-- 7. TWILIGHT -- night, purple bursts across the neon island
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
            if y and #s.spots < 4 then s.spots[#s.spots + 1] = standCF(V3(p.X, y, p.Z), center + V3(45, 0, 55)) end
        end
        assert(#s.spots >= 3, "twilight surface not found")
        s.center = V3(center.X, s.spots[1].Position.Y, center.Z)
    end,
    enter = function(s)
        setClock(0)
        pose(s.spots[1])
        playAnim(nil)
    end,
    beat = function(s, i, catchingUp)
        if i == 0 then return end
        local cf = s.spots[math.min(i + 1, #s.spots)]
        if catchingUp then pose(cf) else blink(cf, Color3.fromRGB(200, 80, 255)) end
    end,
    frame = function(s, a)
        local ang = math.rad(lerp(35, 70, a))
        local r = lerp(62, 52, a)
        local cam = s.center + V3(math.cos(ang) * r, lerp(30, 38, a), math.sin(ang) * r)
        return CFrame.lookAt(cam, s.center + V3(0, -6, 0)), 55
    end,
})

-- 8. THE MENU (phrase downbeat) -- the Splash Hub window as a floating holo-panel over the plaza; one
--    toggle switches ON per beat while the camera pushes past the character into the screen
local MENU_ROWS = {
    { "Farming",   "Auto Gem Farm" },
    { "Hatching",  "Auto Hatch Best Egg" },
    { "Rifts",     "Auto Rift Hunter" },
    { "Fishing",   "Auto Fish + Sell" },
    { "Quests",    "Auto Season Pass" },
    { "Minigames", "Auto Minigames" },
    { "Shops",     "Smart Shop Buyer" },
    { "Misc",      "Auto Reconnect" },
}
shot({
    name = "menu", bars = 2, cut = "flash", area = "ONE HUB. EVERYTHING.",
    prep = function(s)
        local stand = standAt(40, -28, PLAZA_Y, V3(40, 0, -60))
        assert(stand, "menu spot off ground")
        s.stand = stand
        local feet = stand.Position - V3(0, hrpOffset(), 0)
        s.panelPos = feet + V3(0, 9.5, -19)
        s.accent = Color3.fromRGB(60, 200, 235)
    end,
    build = function(s)
        local W, H, PPS = 22, 13.2, 50
        local panel = fxPart({ Name = "SplashHubPanel", Size = V3(W, H, 0.05), Transparency = 1, CFrame = CFrame.lookAt(s.panelPos, s.stand.Position + V3(0, 2, 0)) })
        local glow = fxPart({ Size = V3(W + 0.6, H + 0.6, 0.02), Material = Enum.Material.Neon, Color = s.accent, Transparency = 0.82, CFrame = panel.CFrame * CF(0, 0, 0.06) })
        local sg = Instance.new("SurfaceGui")
        sg.Face = Enum.NormalId.Front
        sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
        sg.PixelsPerStud = PPS
        sg.LightInfluence = 0
        sg.Brightness = 1.4
        sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        sg.Parent = panel
        local win = Instance.new("Frame")
        win.Size = UDim2.fromScale(1, 1)
        win.BackgroundColor3 = Color3.fromRGB(22, 23, 28)
        win.BackgroundTransparency = 0.04
        win.BorderSizePixel = 0
        win.Parent = sg
        Instance.new("UICorner", win).CornerRadius = UDim.new(0, 26)
        local ws = Instance.new("UIStroke", win)
        ws.Color = s.accent
        ws.Thickness = 3
        ws.Transparency = 0.35
        local function txt(parent, text, x, y, w, h, size, font, color, align)
            local l = Instance.new("TextLabel")
            l.BackgroundTransparency = 1
            l.Position = UDim2.fromOffset(x, y)
            l.Size = UDim2.fromOffset(w, h)
            l.Text = text
            l.TextSize = size
            l.FontFace = font
            l.TextColor3 = color or Color3.fromRGB(235, 238, 245)
            l.TextXAlignment = align or Enum.TextXAlignment.Left
            l.Parent = parent
            return l
        end
        -- title bar
        local dot = Instance.new("Frame")
        dot.Position = UDim2.fromOffset(34, 26)
        dot.Size = UDim2.fromOffset(34, 34)
        dot.BackgroundColor3 = s.accent
        dot.BorderSizePixel = 0
        dot.Parent = win
        Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
        txt(win, "Splash Hub  |  V1", 84, 20, 600, 46, 36, FONT_CREDIT)
        txt(win, "Bubble Gum Simulator INFINITY", 640, 22, 420, 44, 22, FONT_BODY, Color3.fromRGB(140, 150, 165), Enum.TextXAlignment.Right)
        local div = Instance.new("Frame")
        div.Position = UDim2.fromOffset(28, 84)
        div.Size = UDim2.new(1, -56, 0, 2)
        div.BackgroundColor3 = Color3.fromRGB(48, 52, 62)
        div.BorderSizePixel = 0
        div.Parent = win
        -- sidebar tabs + toggle rows
        s.tabs, s.rows = {}, {}
        for i, row in ipairs(MENU_ROWS) do
            local ty = 104 + (i - 1) * 62
            local tab = Instance.new("Frame")
            tab.Position = UDim2.fromOffset(24, ty)
            tab.Size = UDim2.fromOffset(250, 52)
            tab.BackgroundColor3 = s.accent
            tab.BackgroundTransparency = 1
            tab.BorderSizePixel = 0
            tab.Parent = win
            Instance.new("UICorner", tab).CornerRadius = UDim.new(0, 12)
            local tl = txt(tab, row[1], 22, 0, 220, 52, 26, FONT_BODY, Color3.fromRGB(150, 158, 172))
            s.tabs[i] = { frame = tab, label = tl }

            local r = Instance.new("Frame")
            r.Position = UDim2.fromOffset(300, ty)
            r.Size = UDim2.fromOffset(770, 52)
            r.BackgroundColor3 = Color3.fromRGB(34, 36, 44)
            r.BorderSizePixel = 0
            r.Parent = win
            Instance.new("UICorner", r).CornerRadius = UDim.new(0, 12)
            txt(r, row[2], 24, 0, 560, 52, 26, FONT_BODY)
            local track = Instance.new("Frame")
            track.AnchorPoint = Vector2.new(1, 0.5)
            track.Position = UDim2.new(1, -22, 0.5, 0)
            track.Size = UDim2.fromOffset(78, 36)
            track.BackgroundColor3 = Color3.fromRGB(64, 68, 80)
            track.BorderSizePixel = 0
            track.Parent = r
            Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
            local knob = Instance.new("Frame")
            knob.AnchorPoint = Vector2.new(0, 0.5)
            knob.Position = UDim2.new(0, 4, 0.5, 0)
            knob.Size = UDim2.fromOffset(28, 28)
            knob.BackgroundColor3 = Color3.fromRGB(210, 214, 224)
            knob.BorderSizePixel = 0
            knob.Parent = track
            Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
            s.rows[i] = { row = r, track = track, knob = knob, on = false }
        end
        txt(win, "Gumteeth Remote  ●  Connected", 300, 610, 770, 36, 22, FONT_BODY, Color3.fromRGB(95, 220, 140), Enum.TextXAlignment.Right)
        s.panel, s.glow = panel, glow
    end,
    enter = function(s)
        setClock(14)
        pose(s.stand)
        playAnim(nil)
        s.build(s)
    end,
    beat = function(s, i, catchingUp)
        local row = s.rows and s.rows[i + 1]
        if not row then return end
        local t = catchingUp and 0 or 0.22
        row.on = true
        tween(row.track, t, { BackgroundColor3 = s.accent })
        tween(row.knob, t, { Position = UDim2.new(1, -32, 0.5, 0), BackgroundColor3 = Color3.new(1, 1, 1) }, Enum.EasingStyle.Back)
        if not catchingUp then
            row.row.BackgroundColor3 = Color3.fromRGB(60, 120, 145)
            tween(row.row, 0.5, { BackgroundColor3 = Color3.fromRGB(34, 36, 44) })
        end
        for j, tab in ipairs(s.tabs) do
            local active = j == i + 1
            tween(tab.frame, t, { BackgroundTransparency = active and 0.78 or 1 })
            tween(tab.label, t, { TextColor3 = active and Color3.new(1, 1, 1) or Color3.fromRGB(150, 158, 172) })
        end
    end,
    frame = function(s, a, lt)
        -- the panel breathes slightly; camera starts over the character's shoulder, ends face-on
        if s.panel then
            local bob = math.sin(lt * 1.6) * 0.15
            local base = CFrame.lookAt(s.panelPos + V3(0, bob, 0), s.stand.Position + V3(0, 2, 0))
            s.panel.CFrame = base
            s.glow.CFrame = base * CF(0, 0, 0.06)
            s.glow.Transparency = 0.8 + math.sin(lt * 5) * 0.05
        end
        local back = s.stand.LookVector
        local right = s.stand.RightVector
        local e = easeInOut(a)
        local startCam = s.stand.Position - back * 7 + right * 2.4 + V3(0, 1.6, 0)
        -- ends between the character and the panel (the character stands ~19 studs out; its aura must not wrap the lens)
        local endCam = s.panelPos + (s.stand.Position - s.panelPos).Unit * 13.5 + right * 1.2 + V3(0, -0.5, 0)
        local cam = startCam:Lerp(endCam, e)
        local look = (s.stand.Position + V3(0, 2, 0)):Lerp(s.panelPos, math.min(1, 0.55 + e))
        s.focusPoint = s.panelPos  -- keep pets out of the line to the panel, not just to the character
        return CFrame.lookAt(cam, look), lerp(60, 52, e)
    end,
    leave = function(s)
        for _, inst in ipairs({ s.panel, s.glow }) do pcall(function() inst:Destroy() end) end
        s.panel, s.glow, s.rows, s.tabs = nil, nil, nil, nil
    end,
})

-- 9. DICE ISLAND -- Minigame Paradise: the character hops dice-top to dice-top on every beat
shot({
    name = "dice", bars = 1, area = "AUTO MINIGAMES",
    prep = function(s)
        local tops = { V3(9910, 0, 242), V3(9907, 0, 262), V3(9884, 0, 273), V3(9859, 0, 262) }
        local look = V3(9884, 0, 190)
        s.spots = {}
        for _, p in ipairs(tops) do
            local y = groundY(p.X, p.Z, 2932, 60, true)
            if y and y > 2915 then s.spots[#s.spots + 1] = standCF(V3(p.X, y, p.Z), look) end
        end
        assert(#s.spots >= 3, "dice tops not found")
        s.camBase = V3(9890, 2934, 224)
    end,
    enter = function(s)
        setClock(14)
        pose(s.spots[1])
        playAnim(nil)
    end,
    beat = function(s, i, catchingUp)
        if i == 0 then return end
        local cf = s.spots[math.min(i + 1, #s.spots)]
        if catchingUp then pose(cf) else blink(cf, Color3.fromRGB(255, 90, 90)) end
    end,
    frame = function(s, a, lt)
        local look = glideLook(s.spots, lt, 2.2)
        return CFrame.lookAt(s.camBase + V3(lerp(4, -4, a), 0, 0), look + V3(0, 1, 0)), 56
    end,
})

-- 10. SWITCH -- GTA character-switch: over-the-shoulder, then three jumps up into the sky
shot({
    name = "switch", bars = 1,
    prep = function(s)
        local stand = standAt(47, -50, PLAZA_Y, V3(58, 0, -71))
        assert(stand, "switch spot off ground")
        s.stand = stand
        s.p = stand.Position
        s.levels = { 0, 45, 220, 620 }
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
        local h = bi == 0 and 0 or lerp(l0, l1, easeInOut(frac / 0.45))
        local moving = (bi > 0 and frac < 0.45) and math.sin(math.pi * clamp01(frac / 0.45)) or 0
        if blur then blur.Size = moving * 18 end
        if grade then grade.Saturation = lerp(0.18, -0.45, clamp01(h / 620)) end
        local back = s.stand.LookVector
        if h < 1 then
            local cam = s.p - back * 7 + V3(1.6, 2.2, 0) + s.stand.RightVector * 1.5
            return CFrame.lookAt(cam, s.p + back * 10 + V3(0, 1, 0)), 60
        end
        local k = clamp01(h / 620)
        local cam = s.p - back * lerp(14, 40, k) + V3(0, h + 2, 0)
        return CFrame.lookAt(cam, s.p + V3(0, 0, 0.01)), 60 + k * 10
    end,
    leave = function()
        if blur then blur.Size = 0 end
    end,
})

-- 11. TITLE -- from the top of the switch, slow drift over the island, logo slams on the downbeat
shot({
    name = "title", bars = 2, cut = "flash", noChar = true,
    prep = function(s)
        local sw = findShot("switch")
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
        local vpScale = math.max(gui.AbsoluteSize.Y, 300) / 540
        titleScale.Scale = vpScale * lerp(1.3, 1, easeOut(lt / 0.6)) * lerp(1, 1.04, a)
        dim.BackgroundTransparency = lerp(1, 0.72, smooth(lt / 0.6))
        setTitleAlpha(easeOut(lt / 0.45), smooth((lt - 0.9) / 0.6))
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

-- The picture runs on os.clock and is only STEERED by Sound.TimePosition. TimePosition reports in
-- coarse steps and lags after frame hitches (e.g. the cross-world teleport into Twilight); snapping to
-- it made the camera jump backwards = a visible bounce. Now: drift is eased out by at most 25% speed
-- change, a big lag (we stalled) is jumped FORWARD, and time never runs backwards.
local lastSteer = nil
local function songTime()
    if OPT.freezeAt then return OPT.freezeAt end
    if not songClock0 then return 0 end
    local clockNow = os.clock()
    local dt = lastSteer and math.clamp(clockNow - lastSteer, 0, 0.25) or 0
    lastSteer = clockNow
    local now = clockNow - songClock0
    if sound and sound.IsPlaying and sound.TimeLength > 0 then
        local err = sound.TimePosition - now
        if err > 0.3 then
            songClock0 -= err
            now += err
        elseif math.abs(err) > 0.015 then
            local step = math.clamp(err, -dt * 0.25, dt * 0.25)
            songClock0 -= step
            now += step
        end
    end
    return now
end

-- picture time: the song position minus output latency (see AUDIO_LATENCY); monotonic
local lastPicture = 0
local function pictureTime()
    if OPT.freezeAt then return OPT.freezeAt end
    local t = math.max(0, songTime() - (sound and AUDIO_LATENCY or 0))
    if t < lastPicture then t = lastPicture end
    lastPicture = t
    return t
end

local function loadAudio()
    if OPT.silent or OPT.freezeAt then return nil end
    pcall(function() if isfolder and not isfolder("SplashHub_Configs") then makefolder("SplashHub_Configs") end end)
    if not (writefile and getcustomasset) then return nil end
    local have = false
    pcall(function() have = isfile(AUDIO_FILE) and #readfile(AUDIO_FILE) > AUDIO_MIN_BYTES end)
    if not have then
        loadingText.Text = "LOADING MUSIC"
        local ok, body = pcall(function() return game:HttpGet(AUDIO_URL) end)
        if not ok or type(body) ~= "string" or #body < AUDIO_MIN_BYTES then return nil end
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

local function loadCaptions()
    if not (writefile and getcustomasset) then return nil end
    local have = false
    pcall(function() have = isfile(CAPTION_FILE) and #readfile(CAPTION_FILE) > 20000 end)
    if not have then
        local ok, body = pcall(function() return game:HttpGet(CAPTION_URL) end)
        if not ok or type(body) ~= "string" or #body < 20000 or body:sub(2, 4) ~= "PNG" then return nil end
        if not pcall(writefile, CAPTION_FILE, body) then return nil end
    end
    local ok, asset = pcall(getcustomasset, CAPTION_FILE)
    if not ok or not asset then return nil end
    -- give the texture a moment to decode so the first caption doesn't pop in late
    pcall(function() game:GetService("ContentProvider"):PreloadAsync({ asset }) end)
    return asset
end

-- Pets follow the character, and BGSI pets are BIG: any of ours that drifts between the lens and the
-- character (or right up against the lens) is faded out for that frame instead of filling the shot.
local petRender = nil
-- every rendered pet that belongs to a player: { model, mine }. (Owner-less pets are world props.)
local petCache, petCacheAt = {}, 0
local function playerPets()
    if os.clock() - petCacheAt < 0.5 then return petCache end
    petCacheAt = os.clock()
    local list = {}
    if petRender and type(petRender.Pets) == "table" then
        for _, v in pairs(petRender.Pets) do
            if type(v) == "table" and typeof(v.Owner) == "Instance" and typeof(v.Model) == "Instance" and v.Model.Parent then
                list[#list + 1] = { v.Model, v.Owner == player }
            end
        end
    end
    petCache = list
    return list
end

local petInfo = setmetatable({}, { __mode = "k" })

-- true when a sphere (center, r) swallows the lens or sits on the line from the lens to the subject
local function sphereBlocks(center, r, camPos, target)
    if (center - camPos).Magnitude < r + 2.5 then return true end
    if not target then return false end
    local seg = target - camPos
    local len2 = seg:Dot(seg)
    local k = len2 > 0 and math.clamp((center - camPos):Dot(seg) / len2, 0, 1) or 0
    return k < 0.97 and (camPos + seg * k - center).Magnitude < r * 0.75 + 1.5
end

-- gum bubbles (Hide Bubbles is switched off for the intro): ours fades when it blocks the shot,
-- everyone else's stays hidden
local bubbleHidden = {}
local function fadeBubbles(camPos, target)
    local folder = workspace:FindFirstChild("Rendered") and workspace.Rendered:FindFirstChild("Bubbles")
    if not folder then return end
    local char = player.Character
    local head = char and char:FindFirstChild("Head")
    for _, b in ipairs(folder:GetChildren()) do
        if b:IsA("BasePart") then
            local hide = true  -- no gum bubbles in the intro, ours included (BGSI settings are never touched)
            if hide ~= (bubbleHidden[b] == true) then
                bubbleHidden[b] = hide or nil
                b.LocalTransparencyModifier = hide and 1 or 0
            end
        end
    end
end
onRestore(function()
    for b in pairs(bubbleHidden) do pcall(function() b.LocalTransparencyModifier = 0 end) end
end)

-- our pets fade only while they block the shot; other players' pets stay hidden the whole intro
-- (done client-side -- the intro never switches a BGSI "hide" setting ON)
local function fadePets(camPos, target)
    pcall(fadeBubbles, camPos, target)
    for _, entry in ipairs(playerPets()) do
        local m, mine = entry[1], entry[2]
        local info = petInfo[m]
        if not info then
            local parts, emitters = {}, {}
            for _, d in ipairs(m:GetDescendants()) do
                if d:IsA("BasePart") or d:IsA("Decal") then parts[#parts + 1] = d
                elseif d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then emitters[#emitters + 1] = { d, d.Enabled } end
            end
            local ok, _, size = pcall(function() return m:GetBoundingBox() end)
            info = { parts = parts, emitters = emitters, r = ok and size and size.Magnitude / 2 or 3, hidden = false }
            petInfo[m] = info
        end
        local hide = true  -- no pets in the intro, ours included (they're huge and swallow close-ups)
        local _ = mine
        if hide ~= info.hidden then
            info.hidden = hide
            for _, part in ipairs(info.parts) do pcall(function() part.LocalTransparencyModifier = hide and 1 or 0 end) end
            for _, e in ipairs(info.emitters) do pcall(function() e[1].Enabled = (not hide) and e[2] end) end
        end
    end
end
onRestore(function()
    for _, info in pairs(petInfo) do
        if info.hidden then
            for _, part in ipairs(info.parts) do pcall(function() part.LocalTransparencyModifier = 0 end) end
            for _, e in ipairs(info.emitters) do pcall(function() e[1].Enabled = e[2] end) end
        end
    end
end)

-- like Roblox's own camera: fade the character out when the lens gets inside ~4.5 studs of its head
local charFade = 0
local function setCharFade(t)
    if math.abs(t - charFade) < 0.02 and not (t == 0 and charFade ~= 0) then return end
    charFade = t
    local char = player.Character
    if not char then return end
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") or d:IsA("Decal") then d.LocalTransparencyModifier = t end
    end
end
local function fadeCharNear(camPos)
    local char = player.Character
    local head = char and char:FindFirstChild("Head")
    if head then setCharFade(clamp01((4.5 - (head.Position - camPos).Magnitude) / 2)) end
end
onRestore(function() pcall(setCharFade, 0) end)

-- NOTE: the intro never changes BGSI settings (Hide All Pets / Hide Bubbles / ...). Pets and gum
-- bubbles are hidden client-side for its duration by fadePets/fadeBubbles above, and come back untouched.

-- take over the screen the way the game's own cutscenes do, and remember how to give it back
local function takeOver()
    local Music          = gameModule("Client.Music")
    local PlayerRender   = gameModule("Client.PlayerRender")
    local PlayerControls = gameModule("Client.PlayerControls")
    local Activation     = gameModule("Client.Activation")
    local Prompt         = gameModule("Client.Gui.ProximityPrompt")
    petRender            = gameModule("Client.PetRender")

    if Music and Music.SetVolume then
        local v = type(Music.Volume) == "number" and Music.Volume or 0.5
        pcall(function() Music:SetVolume(0) end)
        onRestoreGame(function() Music:SetVolume(v) end)
    end
    if PlayerRender and PlayerRender.SetPlayersVisible then
        pcall(function() PlayerRender:SetPlayersVisible(false) end)
        onRestoreGame(function() PlayerRender:SetPlayersVisible(true) end)
    end
    if PlayerControls and PlayerControls.Disable then
        pcall(function() PlayerControls:Disable() end)
        onRestoreGame(function() PlayerControls:Enable() end)
    end
    -- pads/shops/eggs/fast-travel must not fire while the character is teleported around
    if Activation and Activation.Hide then
        pcall(function() Activation:Hide() end)
        onRestoreGame(function() Activation:Show() end)
    end
    if Prompt and Prompt.Disable then
        pcall(function() Prompt:Disable() end)
        onRestoreGame(function() Prompt:Enable() end)
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
    -- BGSI's depth of field smears anything near the lens (close-ups, the menu panel) -- off for the intro
    for _, fx in ipairs(Lighting:GetChildren()) do
        if fx:IsA("DepthOfFieldEffect") and fx.Enabled then
            fx.Enabled = false
            onRestore(function() fx.Enabled = true end)
        end
    end

    -- every PlayerGui layer + world billboard is held OFF for the whole intro -- including ones the game
    -- tries to switch on mid-intro (transitions, popups); each goes back to its latest wanted state
    local wanted = {}
    local function hold(g)
        if wanted[g] ~= nil or g:IsDescendantOf(fxFolder) then return end
        if not (g:IsA("LayerCollector") or g:IsA("BillboardGui")) then return end
        wanted[g] = g.Enabled
        g.Enabled = false
        track(g:GetPropertyChangedSignal("Enabled"):Connect(function()
            if restored then return end
            if g.Enabled then
                wanted[g] = true
                g.Enabled = false
            end
        end))
    end
    local pg = player:FindFirstChild("PlayerGui")
    if pg then
        for _, g in ipairs(pg:GetChildren()) do hold(g) end
        track(pg.ChildAdded:Connect(function(g) task.defer(hold, g) end))
    end
    for _, d in ipairs(workspace:GetDescendants()) do if d:IsA("BillboardGui") then hold(d) end end
    track(workspace.DescendantAdded:Connect(function(d)
        if d:IsA("BillboardGui") then task.defer(hold, d) end
    end))
    pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)
    local acc = 0
    track(RunService.Heartbeat:Connect(function(dt)
        acc += dt
        if acc > 1 then
            acc = 0
            pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)
        end
    end))
    onRestore(function()
        for g, on in pairs(wanted) do
            if on then pcall(function() g.Enabled = true end) end
        end
        pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true) end)
    end)

    -- any other looping music that slipped through (restored after)
    local muted = {}
    for _, root in ipairs({ SoundService, workspace }) do
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("Sound") and d ~= sound and d.Looped and d.IsPlaying and d.Volume > 0 then
                muted[d] = d.Volume
                d.Volume = 0
            end
        end
    end
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
    end)

    sound = loadAudio()
    captionAsset = loadCaptions()
    if captionAsset then
        areaImg.Image = captionAsset
        areaImg.Visible = true
    end
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
    settle()
    assert(#list > 0, "no usable shots")
    local total = t

    takeOver()
    cam.CameraType = Enum.CameraType.Scriptable

    -- pre-warm: while the screen is still black, point the camera at every location for a few frames so
    -- meshes/textures are uploaded now -- first-time rendering mid-intro caused ~0.2s hitches at cuts
    if not OPT.freezeAt then
        loading.Visible = true
        loadingText.Text = "LOADING WORLD"
        for _, s in ipairs(list) do
            local poi = (s.stand and s.stand.Position) or (s.spots and s.spots[1] and s.spots[1].Position)
                or (s.path and s.path[1] and s.path[1].Position) or s.panelPos or s.center or s.from
            if typeof(poi) == "Vector3" then
                for _, off in ipairs({ V3(28, 14, 28), V3(-28, 20, -20) }) do
                    cam.CFrame = CFrame.lookAt(poi + off, poi)
                    for _ = 1, 3 do RunService.RenderStepped:Wait() end
                end
            end
        end
    end

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
        local now = pictureTime()
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
                local ok, err = pcall(cur.beat, cur, nextBeat, false)
                if not ok then warn("[SplashIntro] beat " .. cur.name .. ": " .. tostring(err)) end
                nextBeat += 1
            end
        end
        local ok, cf, fov = pcall(cur.frame, cur, clamp01(lt / cur.len), lt)
        if OPT.debugLog and ok and cf then
            local log = genv._splashIntroLog or {}
            genv._splashIntroLog = log
            log[#log + 1] = { os.clock(), now, cur.name, cf.Position, sound and sound.TimePosition or -1 }
        end
        if ok and cf then
            cam.CFrame = cf
            if fov then cam.FieldOfView = fov end
            pcall(fadePets, cf.Position, (not cur.noChar) and (cur.focusPoint or (charPos() + V3(0, 1.5, 0))) or nil)
            pcall(fadeCharNear, cf.Position)
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
        local aa = cur.area and textAlpha(lt, cur.len, 0.2, cur.len - 0.25) or 0
        local slide = (1 - easeOut((lt - 0.2) / 0.45)) * 40
        local rect = captionAsset and cur.area and CAPTION_RECTS[cur.area]
        if rect then
            -- Pricedown image, sized off the screen height, sitting in the bottom letterbox bar
            local hPx = math.max(gui.AbsoluteSize.Y, 300) * 0.1
            areaImg.ImageRectOffset = Vector2.new(rect[1], rect[2])
            areaImg.ImageRectSize = Vector2.new(rect[3], rect[4])
            areaImg.Size = UDim2.fromOffset(hPx * rect[3] / rect[4], hPx)
            areaImg.Position = UDim2.new(1, -30 + slide, 1, -8)
            areaImg.ImageTransparency = 1 - aa
            area.TextTransparency, areaStroke.Transparency = 1, 1
        else
            areaImg.ImageTransparency = 1
            area.TextTransparency = 1 - aa
            areaStroke.Transparency = 1 - aa
            area.Position = UDim2.fromOffset(slide, 0)
        end
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
