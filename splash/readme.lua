-- ==========================================
-- 🌊 SPLASH HUB | ULTIMATE BGSI EDITION V1
-- Created by: RBshops | Delta Mobile Optimized
-- ==========================================

if not game:IsLoaded() then game.Loaded:Wait() end


local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
   Name = "Splash Hub | V1",
   LoadingTitle = "Loading Splash Hub...",
   LoadingSubtitle = "Created by: RBshops",
   ConfigurationSaving = { Enabled = true, FolderName = "SplashHub_Configs", FileName = "Splash_V1_Save" },
   Discord = { Enabled = false, Invite = "", RememberJoins = true },
   KeySystem = false
})

-- ==========================================
-- VARIABLES & SERVICES
-- ==========================================
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local VirtualUser = game:GetService("VirtualUser")
local TeleportService = game:GetService("TeleportService")
local CoreGui = game:GetService("CoreGui")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local Toggles = {
    WHPingSecret = true,
    WHPingInf = true,
    WHPingMythic = true,
    WHPingShiny = true,
    WHPingSuper = true,
    AntiAFK = true,
    AnimSkip = false,
    EventChests = false,

    ObbyQueue = false,
    AutoPetMatch = false,
    AutoCartEscape = false,
    AutoRobotClaw = false,
    AutoGuessPet = false,
    AutoReconnect = false,
    GemFarmToggle = false,
    GemFarmCooldown = false,
    AutoBlow = false,
    AutoSell = false,

    AutoWheel = false,
    Quests = false,
}
local autoBuyActive = false -- Declared here so gem farming section can reference it
local RemoteRegistry = {} -- { ["FlagName"] = uiElement } for remote config
local remoteConfigUrl = "https://gumteeth.net/api/config"
local remoteApiKey = ""
local remotePollInterval = 60
local remoteConfigEnabled = false
local remoteStatusLabel = nil
local syncToCloudPending = false
local syncToCloudDelay = 3

-- Flags that must NEVER be synced to the public KV store
-- These stay local-only to prevent credential/URL leakage
local PRIVATE_FLAGS = {
    WH_URL = true,
    WHPingID = true,
    PSInput = true,
    RemoteConfigURL = true,
    RemoteConfigToggle = true,
    RemotePollInterval = true,
    PauseGumteethReceive = true,
    RemoteWHNotify = true,
    ImportInput = true,
    CustomEggInput = true,
    CustomNameInput = true,
    TradeMsg = true,
}

-- Push current state to Cloudflare KV (debounced) so gumteeth can read it
local lastSyncedState = ""

local function syncToCloud()
    if syncToCloudPending then return end
    syncToCloudPending = true
    task.spawn(function()
        task.wait(syncToCloudDelay)
        syncToCloudPending = false
        if remoteApiKey == "" then return end
        pcall(function()
            local state = {}
            -- Pull all flags from Rayfield, EXCLUDING private ones
            if Rayfield and Rayfield.Flags then
                for flagName, element in pairs(Rayfield.Flags) do
                    if not PRIVATE_FLAGS[flagName] and type(element) == "table" then
                        -- Rayfield uses .CurrentValue for toggles/sliders, .CurrentOption for dropdowns
                        local val = element.CurrentValue
                        if val == nil then val = element.CurrentOption end
                        if val ~= nil then
                            -- Normalize dropdown arrays to strings for dashboard compatibility
                            if type(val) == "table" and #val > 0 then
                                val = val[1] -- {"Summer Egg"} → "Summer Egg"
                            end
                            state[flagName] = val
                        end
                    end
                end
            end
            -- Special values (commands) are NO LONGER cleared here.
            -- pollRemoteConfig will clear them individually via POST after execution.
            -- Attach chest timer metadata for dashboard countdown
            if getgenv().ChestTimers then
                state["_chestTimers"] = getgenv().ChestTimers
            end
            -- Attach shop cooldowns for dashboard (Began + Period per shop)
            if getgenv().ShopCooldowns then
                state["_shopCooldowns"] = getgenv().ShopCooldowns
            end
            -- Attach obby cooldowns for dashboard (epoch timestamp per difficulty)
            if getgenv().ObbyCooldowns then
                state["_obbyCooldowns"] = getgenv().ObbyCooldowns
            end
            -- Attach console logs (piggybacks on state sync, no extra KV write)
            if getgenv().ConsoleLogs and #getgenv().ConsoleLogs > 0 then
                state["_console"] = getgenv().ConsoleLogs
            end
            
            local payloadStr = HttpService:JSONEncode(state)
            if payloadStr == lastSyncedState then return end -- NO CHANGES, DONT SPAM KV WRITES!
            lastSyncedState = payloadStr
            
            request({
                Url = remoteConfigUrl,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json",
                    ["Authorization"] = "Bearer " .. remoteApiKey
                },
                Body = payloadStr,
            })
        end)
    end)
end

local lastSyncedConsole = ""

local function syncConsoleToCloud()
    if remoteApiKey == "" then return end
    task.spawn(function()
        pcall(function()
            local payload = { _console = getgenv().ConsoleLogs }
            local payloadStr = HttpService:JSONEncode(payload)
            if payloadStr == lastSyncedConsole then return end -- NO CHANGES
            lastSyncedConsole = payloadStr
            
            request({
                Url = remoteConfigUrl,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json",
                    ["Authorization"] = "Bearer " .. remoteApiKey
                },
                Body = payloadStr,
            })
        end)
    end)
end

-- ==========================================
-- 📝 CONSOLE SYSTEM
-- ==========================================
getgenv().ConsoleLogs = {}

local lastConsoleSync = 0
local CONSOLE_SYNC_INTERVAL = 30 -- Only sync console to cloud every 30 seconds (avoids KV spam)
local function consoleLog(msg)
    local timestamp = os.date("[%H:%M:%S]")
    local logMsg = string.format("%s [Info] %s", timestamp, msg)
    
    table.insert(getgenv().ConsoleLogs, logMsg)
    
    -- Keep only last 25 logs (smaller payload = less KV usage)
    if #getgenv().ConsoleLogs > 25 then
        table.remove(getgenv().ConsoleLogs, 1)
    end
    
    -- Debounced sync to cloud — much slower to avoid KV put limit
    local currentTime = os.time()
    if currentTime - lastConsoleSync >= CONSOLE_SYNC_INTERVAL then
        lastConsoleSync = currentTime
        syncConsoleToCloud()
    end
end

-- ==========================================
-- UNIVERSAL NETWORK ROUTER (single-module pattern)
-- ==========================================
local Remote = nil
pcall(function()
    Remote = require(game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote)
end)

-- ==========================================
-- KEEP-ALIVE (Anti-AFK) — Proactive 300s Loop
-- Bypasses the native 720s AFK rejoin timer
-- ==========================================
player.Idled:Connect(function()
    if Toggles.AntiAFK then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end
end)

task.spawn(function()
    while true do
        task.wait(300)
        if Toggles.AntiAFK then
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
        end
    end
end)

-- ==========================================
-- ANIMATION SKIPPER (Fast Hatch) — Hook Override
-- Overrides HatchEgg.Play and DisplayPetOnce
-- ==========================================
local _animSkipApplied = false
local function ApplyAnimationSkip()
    if _animSkipApplied then return end
    pcall(function()
        local HatchEgg = require(game:GetService("ReplicatedStorage").Client.Effects.HatchEgg)
        if HatchEgg then
            local _origPlay = HatchEgg.Play
            HatchEgg.Play = function(self, ...)
                if Toggles.AnimSkip then
                    pcall(function() self._hatching = false end)
                    return
                end
                return _origPlay(self, ...)
            end

            if HatchEgg.DisplayPetOnce then
                local _origDisplay = HatchEgg.DisplayPetOnce
                HatchEgg.DisplayPetOnce = function(self, ...)
                    if Toggles.AnimSkip then return end
                    return _origDisplay(self, ...)
                end
            end

            _animSkipApplied = true
        end
    end)
end
ApplyAnimationSkip()

-- ==========================================
-- SPLASH 1 BACKEND SYSTEMS
-- ==========================================
getgenv().AutoHatch = false
getgenv().HatchAmount = 1
getgenv().HatchDelay = 0.5
getgenv().SelectedEgg = "Magma Egg"
getgenv().CustomAutoDelete = false
getgenv().AutoCraftShiny = false
getgenv().HideHatchActive = false
getgenv().BGSI_Inventory = nil
getgenv().CurrentZone = "Main"

getgenv().TrashList = {
    ["Doggy"] = true,
    ["Kitty"] = true,
    ["Bunny"] = true,
    ["Bear"] = true,
    ["Winged Kitty"] = true,
    ["Winged Bunny"] = true,
    ["Winged Deer"] = true
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetworkRemote = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Framework"):WaitForChild("Network"):WaitForChild("Remote"):WaitForChild("RemoteEvent")

-- 1. SAFE Inventory Sync
local PlayerDataRemote = nil
for _, child in pairs(ReplicatedStorage:GetDescendants()) do
    if child.Name == "PlayerDataChanged" and child:IsA("RemoteEvent") then
        PlayerDataRemote = child
        break
    end
end

if PlayerDataRemote then
    PlayerDataRemote.OnClientEvent:Connect(function(key, data)
        if key == "Pets" then
            if getgenv().BGSI_Inventory == nil then
                game:GetService("StarterGui"):SetCore("SendNotification", {
                    Title = "Inventory Synced!",
                    Text = "Auto-Delete is now active.",
                    Duration = 5
                })
            end
            getgenv().BGSI_Inventory = data
        end
    end)
end

-- 2. SAFE Hide Hatch Animation (Zero Hooks)
local PlayerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
-- Known system GUIs that should NEVER be hidden
local systemGuis = {
    ["Chat"] = true, ["PlayerList"] = true, ["Backpack"] = true,
    ["Health"] = true, ["ScreenGui"] = true, ["Freecam"] = true,
    ["BubbleChat"] = true, ["TopBarApp"] = true,
}
local knownGuiNames = {} -- Tracks GUIs that existed before hatching started

task.spawn(function()
    -- Snapshot existing GUIs on startup
    task.wait(2)
    for _, gui in pairs(PlayerGui:GetChildren()) do
        if gui:IsA("ScreenGui") then
            knownGuiNames[gui.Name] = true
        end
    end
    
    while task.wait(0.15) do
        if getgenv().HideHatchActive then
            for _, gui in pairs(PlayerGui:GetChildren()) do
                if gui:IsA("ScreenGui") and gui.Enabled then
                    local name = gui.Name
                    local nameLower = string.lower(name)
                    local shouldHide = false
                    
                    -- Method 1: Name-based detection (covers most cases)
                    if string.find(nameLower, "hatch") or string.find(nameLower, "egg") 
                       or string.find(nameLower, "result") or string.find(nameLower, "display")
                       or string.find(nameLower, "reveal") or string.find(nameLower, "unbox") then
                        shouldHide = true
                    end
                    
                    -- Method 2: Any unknown GUI that appeared after startup (catches custom/UUID eggs)
                    if not shouldHide and not systemGuis[name] and not knownGuiNames[name] then
                        -- Check if it looks like Rayfield or another script UI
                        local isScriptUI = string.find(nameLower, "rayfield") or string.find(nameLower, "splash")
                            or string.find(nameLower, "sirius") or string.find(nameLower, "library")
                        if not isScriptUI then
                            -- Scan children for hatch-like content or animation frames
                            pcall(function()
                                for _, child in pairs(gui:GetDescendants()) do
                                    local cname = string.lower(child.Name)
                                    if string.find(cname, "hatch") or string.find(cname, "petdisplay")
                                       or string.find(cname, "eggresult") or string.find(cname, "petresult")
                                       or string.find(cname, "skipbutton") or string.find(cname, "skip")
                                       or string.find(cname, "pet") or string.find(cname, "reveal")
                                       or string.find(cname, "animation") or string.find(cname, "rarity") then
                                        shouldHide = true
                                        break
                                    end
                                end
                            end)
                            -- Method 3: If the GUI has an ImageLabel or ViewportFrame child (likely showing a pet)
                            if not shouldHide then
                                pcall(function()
                                    local hasViewport = gui:FindFirstChildWhichIsA("ViewportFrame", true)
                                    local hasImage = gui:FindFirstChildWhichIsA("ImageLabel", true)
                                    if hasViewport or hasImage then
                                        -- Only hide if it appeared recently (within 5 seconds)
                                        shouldHide = true
                                    end
                                end)
                            end
                        end
                    end
                    
                    if shouldHide then
                        gui.Enabled = false
                    end
                end
            end
        end
    end
end)

-- 3. Auto-Hatch Loop
task.spawn(function()
    while task.wait(getgenv().HatchDelay or 2.5) do
        if getgenv().AutoHatch then
            pcall(function()
                NetworkRemote:FireServer("HatchEgg", getgenv().SelectedEgg, getgenv().HatchAmount)
            end)
        end
    end
end)

-- ==========================================
-- 🗂️ TAB DEFINITIONS
-- ==========================================
local FarmTab = Window:CreateTab("🫧 Farming", 4483362458)
local EggTab = Window:CreateTab("🥚 Hatching", 4483362458)
local InventoryTab = Window:CreateTab("🎒 Inventory", 4483362458)
local PotionTab = Window:CreateTab("🧪 Potions", 4483362458)
local RunesTab = Window:CreateTab("🗿 Runes", 4483362458)
local HuntTab = Window:CreateTab("🎯 Chests & Gifts", 4483362458)
local EnchantTab = Window:CreateTab("✨ Enchanting", 4483362458)
local QuestTab = Window:CreateTab("📜 Quests", 4483362458)
local ActivityTab = Window:CreateTab("🕹️ Minigames", 4483362458)
local ShopTab = Window:CreateTab("🛒 Shops", 4483362458)
local TeleportTab = Window:CreateTab("🌍 Teleports", 4483362458)
local WebhookTab = Window:CreateTab("📡 Webhook", 4483362458)
local MiscTab = Window:CreateTab("⚙️ Misc & Reconnect", 4483362458)
local SettingsTab = Window:CreateTab("🛠️ Settings", 4483362458)

local SummerTab = Window:CreateTab("☀️ Summer", 4483362458)
local TradeTab = Window:CreateTab("🤝 Trading", 4483362458)
local RiftTab = Window:CreateTab("🌀 Rifts", 4483362458)
local SeasonTab = Window:CreateTab("🏆 Season", 4483362458)


-- ==========================================
-- ☀️ SUMMER EVENT GLOBALS & HELPERS
-- ==========================================
local TweenService = game:GetService("TweenService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local NetworkRemoteEvent = NetworkRemote -- Reuse existing variable from line 247
local NetworkRemoteFunction = NetworkRemote.Parent:WaitForChild("RemoteFunction")

local function getRootPart()
    local character = player.Character
    if character then return character:FindFirstChild("HumanoidRootPart") end
    return nil
end

-- SafeTeleport: Creates invisible platform to prevent falling through void
local function SafeTeleport(targetPos)
    local char = player.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local platform = Instance.new("Part")
    platform.Size = Vector3.new(30, 2, 30)
    platform.Position = targetPos - Vector3.new(0, 3, 0)
    platform.Anchored = true
    platform.Transparency = 1
    platform.CanCollide = true
    platform.Parent = workspace
    task.delay(3, function() if platform then platform:Destroy() end end)
    hrp.Velocity = Vector3.new(0,0,0)
    hrp.CFrame = CFrame.new(targetPos + Vector3.new(0, 3, 0))
    task.wait(0.2)
    hrp.Velocity = Vector3.new(0,0,0)
end

local function isNearPosition(targetPosition, distance)
    local root = getRootPart()
    if root then return (root.Position - targetPosition).Magnitude <= distance end
    return false
end

-- Walks the Zen path for Season coin/gem collection tasks
local function walkZenPath(speed)
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChild("Humanoid")
    if not root or not hum then return end
    for _, pos in ipairs(ZenPath) do
        if not getgenv().IsDoingSeasonTask then break end
        local distance = (root.Position - pos).Magnitude
        local timeToTween = distance / (speed or 100)
        if timeToTween > 0 then
            local tween = TweenService:Create(root, TweenInfo.new(timeToTween, Enum.EasingStyle.Linear), {CFrame = CFrame.new(pos)})
            tween:Play()
            while tween.PlaybackState == Enum.PlaybackState.Playing do
                hum.Jump = true
                task.wait(0.1)
            end
        end
        task.wait(0.1)
    end
end

-- Season: Identify egg from task text
local function identifySeasonEgg(text)
    local numberMatch = string.match(text, "%d+,?%d*")
    if numberMatch then
        local num = tonumber((string.gsub(numberMatch, ",", "")))
        if num and num >= 1000 then return "Common Egg" end
    end
    if string.find(text, "Legendary") then return "Spikey Egg"
    elseif string.find(text, "Epic") then return "Spotted Egg"
    elseif string.find(text, "Rare") or string.find(text, "Unique") then return "Iceshard Egg"
    elseif string.find(text, "Common") then return "Common Egg" end
    local seasonEggMap = {
        ["Common Egg"] = Vector3.new(-84.58, 11.14, -1.13),
        ["Spotted Egg"] = Vector3.new(-92.97, 10.66, 8.61),
        ["Iceshard Egg"] = Vector3.new(-116.50, 10.66, 7.35),
        ["Spikey Egg"] = Vector3.new(-125.43, 10.66, 4.94),
        ["Magma Egg"] = Vector3.new(-135.87, 10.66, -1.44),
        ["Crystal Egg"] = Vector3.new(-139.67, 10.66, -9.31),
        ["Lunar Egg"] = Vector3.new(-143.82, 10.66, -18.42),
        ["Void Egg"] = Vector3.new(-143.71, 10.66, -27.19),
        ["Hell Egg"] = Vector3.new(-143.09, 10.66, -36.41),
        ["Nightmare Egg"] = Vector3.new(-140.68, 10.66, -45.17),
        ["Rainbow Egg"] = Vector3.new(-135.44, 10.66, -53.49),
        ["Snowman Egg"] = Vector3.new(-126.31, 10.66, -59.60),
        ["Mining Egg"] = Vector3.new(-119.21, 10.66, -63.12),
        ["Cyber Egg"] = Vector3.new(-95.75, 10.66, -61.13),
        ["Neon Egg"] = Vector3.new(-86.93, 10.66, -56.37),
        ["Icy Egg"] = Vector3.new(-60.60, 13.66, -4.20),
        ["Vine Egg"] = Vector3.new(-64.96, 13.66, 3.28),
        ["Lava Egg"] = Vector3.new(-71.35, 13.66, 12.37),
        ["Atlantis Egg"] = Vector3.new(-79.61, 13.66, 20.05),
        ["Classic Egg"] = Vector3.new(-89.44, 13.66, 23.42),
    }
    for eggName, _ in pairs(seasonEggMap) do
        local baseName = string.gsub(eggName, " Egg", "")
        if string.find(text, baseName) then return eggName end
    end
    if string.find(text, "Hatch") then return "Common Egg" end
    return nil
end

-- Season egg location lookup
local SeasonEggLocations = {
    ["Common Egg"] = Vector3.new(-84.58, 11.14, -1.13),
    ["Spotted Egg"] = Vector3.new(-92.97, 10.66, 8.61),
    ["Iceshard Egg"] = Vector3.new(-116.50, 10.66, 7.35),
    ["Spikey Egg"] = Vector3.new(-125.43, 10.66, 4.94),
    ["Magma Egg"] = Vector3.new(-135.87, 10.66, -1.44),
    ["Crystal Egg"] = Vector3.new(-139.67, 10.66, -9.31),
    ["Lunar Egg"] = Vector3.new(-143.82, 10.66, -18.42),
    ["Void Egg"] = Vector3.new(-143.71, 10.66, -27.19),
    ["Hell Egg"] = Vector3.new(-143.09, 10.66, -36.41),
    ["Nightmare Egg"] = Vector3.new(-140.68, 10.66, -45.17),
    ["Rainbow Egg"] = Vector3.new(-135.44, 10.66, -53.49),
    ["Snowman Egg"] = Vector3.new(-126.31, 10.66, -59.60),
    ["Mining Egg"] = Vector3.new(-119.21, 10.66, -63.12),
    ["Cyber Egg"] = Vector3.new(-95.75, 10.66, -61.13),
    ["Neon Egg"] = Vector3.new(-86.93, 10.66, -56.37),
    ["Icy Egg"] = Vector3.new(-60.60, 13.66, -4.20),
    ["Vine Egg"] = Vector3.new(-64.96, 13.66, 3.28),
    ["Lava Egg"] = Vector3.new(-71.35, 13.66, 12.37),
    ["Atlantis Egg"] = Vector3.new(-79.61, 13.66, 20.05),
    ["Classic Egg"] = Vector3.new(-89.44, 13.66, 23.42),
}

-- Genie: Parse shorthand values like 2M, 1.5K into numbers
local function parseProgressValue(str)
    str = string.lower(string.gsub(str, "%,", ""))
    local num = string.match(str, "([%d%.]+)")
    if not num then return 0 end
    num = tonumber(num)
    if string.find(str, "m") then num = num * 1000000
    elseif string.find(str, "b") then num = num * 1000000000
    elseif string.find(str, "k") then num = num * 1000 end
    return num
end

--=============================================================================
-- 📖 GENIE DICTIONARIES & HELPER FUNCTIONS
--=============================================================================
getgenv().ItemDictionary = {
    ["122003296498191"] = "Gems",
    ["72488281780856"] = "Lucky V",
}

-- Tracking & Analytics Variables
getgenv().SessionStartTime = os.time()
getgenv().CurrentQuestStartTime = os.time()
getgenv().QuestsCompleted = 0
getgenv().QuestDebounce = false

local genieLastWebhookSent = 0
local genieLastSellTime = os.time()
local genieNextBoardVisit = 0
local genieCurrentTask = "None"
local genieTaskProgress = "0%"
local genieCurrentCooldown = "Ready"

local genieLastProgressAmt = 0
local genieLastProgressTime = os.time()
local genieLastTrackedTask = ""
local genieCurrentETA = "Calculating..."

local genieIsHudMissing = false
local genieHudGraceTimer = 0

local genieIdlePos = Vector3.new(4.92, 15976.82, -0.54)
local genieSellPos = Vector3.new(-69.39, 6862.46, 91.01)

local genieEggData = {
    ["Common Egg"] = Vector3.new(-85.59, 10.09, 0.63), 
    ["Spotted Egg"] = Vector3.new(-94.20, 10.09, 6.95),
    ["Ice Egg"] = Vector3.new(-118.11, 10.09, 7.11), 
    ["Spikey Egg"] = Vector3.new(-126.96, 10.09, 4.86),
    ["Magma Egg"] = Vector3.new(-134.69, 10.09, -2.06), 
    ["Crystal Egg"] = Vector3.new(-139.11, 10.09, -8.09),
    ["Lunar Egg"] = Vector3.new(-142.26, 10.09, -16.58), 
    ["Void Egg"] = Vector3.new(-144.65, 10.09, -28.17),
    ["Hell Egg"] = Vector3.new(-144.75, 10.09, -34.77), 
    ["Nightmare Egg"] = Vector3.new(-142.82, 10.09, -42.01),
    ["Rainbow Egg"] = Vector3.new(-135.93, 10.09, -53.47), 
    ["Snowman Egg"] = Vector3.new(-128.61, 10.09, -58.84),
    ["Mining Egg"] = Vector3.new(-121.41, 10.09, -62.79), 
    ["Cyber Egg"] = Vector3.new(-94.29, 10.09, -61.86),
    ["Neon Egg"] = Vector3.new(-85.71, 10.09, -56.08), 
    ["Icy Egg"] = Vector3.new(-58.82, 13.09, -1.93),
    ["Vine Egg"] = Vector3.new(-64.75, 13.09, 6.39), 
    ["Lava Egg"] = Vector3.new(-72.94, 13.09, 14.88),
    ["Atlantis Egg"] = Vector3.new(-81.29, 13.09, 21.01), 
    ["Classic Egg"] = Vector3.new(-92.97, 13.09, 23.78)
}

local genieZenCoords = {
    Vector3.new(46.69, 15971.70, 36.54), Vector3.new(65.69, 15971.70, 18.46),
    Vector3.new(76.05, 15971.70, 2.17), Vector3.new(-48.82, 15971.70, 32.83),
    Vector3.new(-65.37, 15971.70, 14.97), Vector3.new(-63.38, 15971.70, -6.39)
}

local function sendGenieWebhook(title, desc, status)
    if not getgenv().SplashWebhookURL or getgenv().SplashWebhookURL == "" then return end

    local sessionTime = os.time() - getgenv().SessionStartTime
    local hourlyAvg, dailyAvg, weeklyAvg = 0, 0, 0
    if sessionTime > 60 and getgenv().QuestsCompleted > 0 then
        local hours = sessionTime / 3600
        hourlyAvg = getgenv().QuestsCompleted / hours
        dailyAvg = hourlyAvg * 24
        weeklyAvg = dailyAvg * 7
    end
    
    local timeOnQuest = "0s"
    if genieCurrentTask ~= "None" then
        local qDiff = os.time() - getgenv().CurrentQuestStartTime
        if qDiff > 3600 then
            timeOnQuest = string.format("%dh %dm %ds", math.floor(qDiff/3600), math.floor((qDiff%3600)/60), qDiff%60)
        elseif qDiff > 60 then
            timeOnQuest = string.format("%dm %ds", math.floor(qDiff/60), qDiff%60)
        else
            timeOnQuest = string.format("%ds", qDiff)
        end
    else
        timeOnQuest = "N/A"
    end

    local avgString = string.format("Current Time on Quest: %s\nHourly: %.1f\nDaily: %.1f\nWeekly: %.1f", timeOnQuest, hourlyAvg, dailyAvg, weeklyAvg)
    local qRews = (getgenv().QuestRewards == "" and "Unknown") or (getgenv().QuestRewards or "Unknown")
    local sRews = (getgenv().CurrentRewards == "" and "Unknown") or (getgenv().CurrentRewards or "Unknown")

    local embed = {
        ["title"] = title, ["description"] = desc, ["type"] = "rich", ["color"] = tonumber(0xff00ff),
        ["fields"] = {
            {["name"] = "Objective", ["value"] = genieCurrentTask, ["inline"] = false},
            {["name"] = "Progress", ["value"] = genieTaskProgress, ["inline"] = true},
            {["name"] = "Estimated Quest Finish", ["value"] = genieCurrentETA, ["inline"] = true},
            {["name"] = "Quest Averages", ["value"] = avgString, ["inline"] = true},
            {["name"] = "Cooldown", ["value"] = genieCurrentCooldown, ["inline"] = true},
            {["name"] = "Quest Rewards", ["value"] = qRews, ["inline"] = false},
            {["name"] = "Secured Rewards", ["value"] = sRews, ["inline"] = false},
            {["name"] = "Status", ["value"] = status, ["inline"] = false}
        },
        ["footer"] = {["text"] = "Gem Genie Auto Tracker"}
    }
    local data = { ["embeds"] = {embed} }
    local requestFunc = syn and syn.request or http and http.request or http_request or request or fluxus.request
    if requestFunc then requestFunc({Url = getgenv().SplashWebhookURL, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = HttpService:JSONEncode(data)}) end
end

local function genieTweenTo(targetPos)
    local character = player.Character
    if not character then return end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local distance = (hrp.Position - targetPos).Magnitude
    local duration = distance / (getgenv().GenieTweenSpeed or 60)
    if duration > 10 then duration = 10 end 
    local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear)
    local tween = TweenService:Create(hrp, tweenInfo, {CFrame = CFrame.new(targetPos)})
    tween:Play()
    tween.Completed:Wait()
end

local function genieParseProgressValue(str)
    str = string.lower(string.gsub(str, "%,", ""))
    local num = string.match(str, "([%d%.]+)")
    if not num then return 0 end
    num = tonumber(num)
    if string.find(str, "m") then num = num * 1000000
    elseif string.find(str, "b") then num = num * 1000000000
    elseif string.find(str, "k") then num = num * 1000 end
    return num
end

local function genieResolveTargetEgg(taskText)
    local lowerText = string.lower(taskText)
    for realEggName, _ in pairs(genieEggData) do
        local segment = string.lower(string.gsub(realEggName, " Egg", ""))
        if segment ~= "common" and string.find(lowerText, segment) then
            return realEggName
        end
    end
    if string.find(lowerText, "epic") or string.find(lowerText, "rare") or string.find(lowerText, "legendary") then return "Spikey Egg" end
    if string.find(lowerText, "unique") or string.find(lowerText, "common") then return "Common Egg" end
    return "Common Egg"
end

local function xRayGenieHUDNew()
    local gui = player:WaitForChild("PlayerGui")
    local genieContainers = {}

    for _, v in pairs(gui:GetDescendants()) do
        if v:IsA("TextLabel") and v.Text then
            local cleanTitle = string.lower(string.gsub(v.Text, "<[^>]+>", ""))
            if cleanTitle == "gem genie" then
                if v.Parent and not table.find(genieContainers, v.Parent) then
                    table.insert(genieContainers, v.Parent)
                end
            end
        end
    end

    for _, container in ipairs(genieContainers) do
        local pendingTask = "None"
        for _, v in ipairs(container:GetDescendants()) do
            if v:IsA("TextLabel") and v.Text then
                local rawText = string.gsub(v.Text, "<[^>]+>", "")
                local cleanText = string.lower(rawText)
                if cleanText ~= "" and not string.find(cleanText, "bubble up") and not string.find(cleanText, "event") then
                    if string.find(cleanText, "hatch ") or string.find(cleanText, "collect ") or string.find(cleanText, "blow ") then
                        pendingTask = rawText
                    elseif (string.find(cleanText, "/") and string.match(cleanText, "%d")) or string.find(cleanText, "%%") then
                        if pendingTask ~= "None" then
                            local isComplete = false
                            if string.find(cleanText, "100%%") then
                                isComplete = true
                            else
                                local currentStr, maxStr = string.match(cleanText, "([^\n/]+)%s*/%s*(.+)")
                                if currentStr and maxStr then
                                    local cNum = genieParseProgressValue(currentStr)
                                    local mNum = genieParseProgressValue(maxStr)
                                    if cNum and mNum and cNum >= mNum then isComplete = true end
                                end
                            end
                            if not isComplete then return "Active", pendingTask, rawText else pendingTask = "None" end
                        end
                    end
                end
            end
        end
    end
    if #genieContainers > 0 then return "Done", "None", "100%" end
    return "NoHUD", "None", "0%"
end

local function extractCardData(card)
    local allWanted = {}
    for _, v in ipairs(getgenv().GenieWantedGodTier or {}) do table.insert(allWanted, v) end
    for _, v in ipairs(getgenv().GenieWantedMidTier or {}) do table.insert(allWanted, v) end
    
    local foundItems = {}
    local rawItems = {}
    local gemValue = "None"
    local score = 0
    
    for _, elem in pairs(card:GetDescendants()) do
        local rawText = ""
        if elem:IsA("TextLabel") or elem:IsA("TextButton") then rawText = elem.Text
        elseif elem:IsA("StringValue") then rawText = elem.Value end

        rawText = string.gsub(rawText, "<[^>]+>", "")
        local cleanTxt = string.gsub(string.lower(rawText), "^%s*(.-)%s*$", "%1")
        local valOnly = string.gsub(cleanTxt, "[,%s]", "")

        if cleanTxt ~= "" and cleanTxt ~= "rewards" and cleanTxt ~= "choose" and cleanTxt ~= "active quest" and cleanTxt ~= "tasks" and not string.find(cleanTxt, "come back in") and not string.find(cleanTxt, "hatch") and not string.find(cleanTxt, "collect") and not string.find(cleanTxt, "blow") and not string.find(cleanTxt, "%%") and not string.find(cleanTxt, "bubble up") then
            
            if string.match(valOnly, "^x%d+$") or string.match(valOnly, "^%d+%.?%d*[mbk]$") or string.match(valOnly, "^%d+$") then
                local imageIdStr = "Unknown"
                local current = elem.Parent
                for lvl = 1, 4 do
                    if current then
                        for _, sibling in pairs(current:GetChildren()) do
                            if (sibling:IsA("ImageLabel") or sibling:IsA("ImageButton")) and sibling.Image ~= "" then
                                local id = string.match(sibling.Image, "%d+")
                                if id then
                                    imageIdStr = id
                                    break
                                end
                            end
                        end
                        if imageIdStr ~= "Unknown" then break end
                        current = current.Parent
                    end
                end
                
                local mappedName = nil
                if imageIdStr ~= "Unknown" then
                    mappedName = getgenv().ItemDictionary[imageIdStr]
                end
                if not mappedName then
                    if imageIdStr == "Unknown" then mappedName = "(No ID Found)" else mappedName = "[ID: " .. imageIdStr .. "]" end
                end

                local formattedVal = string.upper(cleanTxt)
                local fullEntry = formattedVal .. " " .. mappedName
                
                if not table.find(rawItems, fullEntry) then table.insert(rawItems, fullEntry) end
                
                local isCurrency = false
                if string.match(valOnly, "^%d+%.?%d*[mbk]$") or string.match(valOnly, "^%d+$") then
                    if not string.match(valOnly, "^x") then isCurrency = true end
                end

                if isCurrency then
                    if (string.lower(mappedName) == "gems" or string.lower(mappedName) == "diamonds") and getgenv().GeniePrioritizeGems then
                        score = score + 2
                        gemValue = fullEntry
                    end
                else
                    for _, wanted in ipairs(allWanted) do
                        if string.find(string.lower(mappedName), string.lower(wanted)) and not table.find(foundItems, wanted) then
                            score = score + 5
                            table.insert(foundItems, wanted)
                        end
                    end
                end
            end
        end
    end
    
    if gemValue ~= "None" then table.insert(foundItems, gemValue) end
    local finalWanted = #foundItems > 0 and table.concat(foundItems, " + ") or "Standard Rewards"
    local finalRaw = #rawItems > 0 and table.concat(rawItems, ", ") or "Unknown"
    
    return score, finalWanted, finalRaw
end

local function xRayBoardTask(container)
    local pendingTask = "None"
    for _, v in ipairs(container:GetDescendants()) do
        if v:IsA("TextLabel") and v.Text then
            local cleanText = string.lower(string.gsub(v.Text, "<[^>]+>", ""))
            if cleanText ~= "" then
                if string.find(cleanText, "hatch ") or string.find(cleanText, "collect ") or string.find(cleanText, "blow ") then
                    pendingTask = string.gsub(v.Text, "<[^>]+>", "")
                elseif (string.find(cleanText, "/") and string.match(cleanText, "%d")) or string.find(cleanText, "%%") then
                    if pendingTask ~= "None" then
                        local isComplete = false
                        if string.find(cleanText, "100%%") then
                            isComplete = true
                        else
                            local currentStr, maxStr = string.match(cleanText, "([^\n/]+)%s*/%s*(.+)")
                            if currentStr and maxStr then
                                local cNum = genieParseProgressValue(currentStr)
                                local mNum = genieParseProgressValue(maxStr)
                                if cNum and mNum and cNum >= mNum then isComplete = true end
                            end
                        end
                        if not isComplete then return pendingTask, string.gsub(v.Text, "<[^>]+>", "") else pendingTask = "None" end
                    end
                end
            end
        end
    end
    return "None", "0%"
end

local function scanBoardNew()
    local gui = player:WaitForChild("PlayerGui")
    local boardAnchor = nil
    
    for _, v in pairs(gui:GetDescendants()) do
        if v:IsA("TextLabel") and v.Text then
            local txt = string.lower(string.gsub(v.Text, "<[^>]+>", ""))
            if txt == "active quest" or txt == "choose your destiny!" then
                boardAnchor = v.Parent
                break
            end
        end
    end

    if not boardAnchor then return "Closed", nil end

    local cards = {}
    for _, v in pairs(boardAnchor:GetDescendants()) do
        if v:IsA("TextLabel") and string.lower(string.gsub(v.Text, "<[^>]+>", "")) == "rewards" then
            if not table.find(cards, v.Parent) then table.insert(cards, v.Parent) end
        end
    end
    
    table.sort(cards, function(a, b) return a.AbsolutePosition.X < b.AbsolutePosition.X end)

    if #cards < 3 then return "Loading", nil end
    local middleCard = cards[2]

    for _, v in pairs(middleCard:GetDescendants()) do
        if v:IsA("TextLabel") and v.Text then
            local txt = string.lower(string.gsub(v.Text, "<[^>]+>", ""))
            if string.find(txt, "come back in") then
                local timer = string.match(txt, "come back in[%s\n]*(%d+:%d+:%d+)") or string.match(txt, "come back in[%s\n]*(%d+:%d+)")
                return "Cooldown", timer
            end
        end
    end

    for _, v in pairs(middleCard:GetDescendants()) do
        if (v:IsA("TextLabel") or v:IsA("TextButton")) and v.Text then
            if string.lower(string.gsub(v.Text, "<[^>]+>", "")) == "choose" then return "Choose", cards end
        end
    end

    local t, p = xRayBoardTask(middleCard)
    if t ~= "None" then 
        local _, extWanted, extRaw = extractCardData(middleCard)
        return "Active", {task = t, prog = p, wanted = extWanted, raw = extRaw} 
    else 
        return "Done", nil 
    end
end

local function evaluateCardsNew(cards)
    local bestScore = -1
    local bestCardIndex = 2
    local bestWanted = "None"
    local bestRaw = "Unknown"

    for i = 1, 3 do
        local score, wanted, raw = extractCardData(cards[i])
        if score > bestScore then
            bestScore = score
            bestCardIndex = i
            bestWanted = wanted
            bestRaw = raw
        end
    end
    return bestCardIndex, bestScore, bestWanted, bestRaw
end

-- Bubble Up: Scan on-screen HUD for active quest
local function GetBubbleUpTask()
    local bestTask = nil
    pcall(function()
        local bubbleUpContainer = nil
        for _, obj in ipairs(player.PlayerGui:GetDescendants()) do
            if obj:IsA("TextLabel") and obj.Visible then
                if string.find(string.lower(obj.Text), "bubble up") then
                    bubbleUpContainer = obj.Parent
                    break
                end
            end
        end
        if bubbleUpContainer then
            local siblingText, current, target = "", 0, 1
            for _, sibling in ipairs(bubbleUpContainer:GetDescendants()) do
                if sibling:IsA("TextLabel") and sibling.Visible then
                    local rawText = string.lower(sibling.Text)
                    siblingText = siblingText .. " " .. rawText .. " "
                    local cleanText = string.gsub(rawText, ",", "")
                    local cStr, tStr = string.match(cleanText, "(%d+)%s*/%s*(%d+)")
                    if cStr and tStr then current = tonumber(cStr); target = tonumber(tStr) end
                end
            end
            local safeText = " " .. string.gsub(siblingText, "[%p]", " ") .. " "
            local foundTask = nil
            for _, eggName in ipairs({"Common Egg","Spotted Egg","Iceshard Egg","Spikey Egg","Magma Egg","Crystal Egg","Lunar Egg","Void Egg","Hell Egg","Nightmare Egg","Rainbow Egg","Snowman Egg","Mining Egg","Cyber Egg","Neon Egg","Icy Egg","Vine Egg","Lava Egg","Atlantis Egg","Classic Egg"}) do
                local shortName = string.lower(string.gsub(eggName, " Egg", ""))
                if string.find(safeText, " " .. shortName .. " ") or string.find(safeText, " " .. shortName .. "s ") then
                    foundTask = {Type = "Hatch", Egg = eggName, Current = current, Target = target}
                    break
                end
            end
            if not foundTask and (string.find(safeText, " blow ") or string.find(safeText, " bubble ")) then
                foundTask = {Type = "Bubble", Current = current, Target = target}
            end
            if foundTask then bestTask = foundTask end
        end
    end)
    return bestTask
end

-- Hierarchy Traffic Light System (prevents feature collisions)
getgenv().IsClaimingChest = false

-- Chest Timers (for Gumteeth dashboard countdown)
getgenv().ChestTimers = {
    SummerChest = { claimedAt = 0, cooldownSecs = 3600 },
    InfinityChest = { claimedAt = 0, cooldownSecs = 3600 },
    RiftGift = { claimedAt = 0, cooldownSecs = 600 },
}
getgenv().IsDoingQuest = false
getgenv().IsHatchingPhase = false
getgenv().CurrentFarmTween = nil
getgenv().SummerFarmActive = false
getgenv().SummerAutoChestEnabled = false

-- Loop Prevention & Live Data
getgenv().CompletedQuests = {}
getgenv().CurrentSeashells = -1
getgenv().SessionHatches = 0

-- Auto Clicker Globals

getgenv().AutoClickerIntervalMs = 100

-- Priority Cycle Globals
getgenv().CycleEnabled = false
getgenv().MinSeashells = 0
getgenv().MaxSeashells = 1000000
getgenv().CycleAmountMins = 10
getgenv().CurrentEggIndex = 1
getgenv().PriorityEgg1 = "Summer Egg"
getgenv().PriorityEgg2 = "None"
getgenv().PriorityEgg3 = "None"
getgenv().SelectedEggs = {"Summer Egg"}

-- Priority Upgrades Globals
getgenv().UpgradeEnabled = false
getgenv().UpPri1 = "Artifact Storage"
getgenv().UpPri2 = "Dig Power"
getgenv().UpPri3 = "Dig Speed"
getgenv().UpPri4 = "Search Radius"
getgenv().UpPri5 = "Artifact Luck"

-- Captain Kitty
getgenv().AutoKittyClaim = false
getgenv().TrackKitty = false
getgenv().TrackGenie = false
getgenv().TrackSailor = false
getgenv().TrackChest = false
getgenv().TrackHatchStats = false
getgenv().TrackSecrets = false
getgenv().TrackStatus = false
getgenv().TrackUpgrades = false
getgenv().TrackShrines = false
getgenv().TrackArtifacts = false
getgenv().LastCompletedQuest = ""

-- Shrine Automators
getgenv().AutoDreamShrine = false
getgenv().DreamDonationAmount = 1
getgenv().AutoBubbleShrine = false
getgenv().BubbleDonationAmount = 1
getgenv().BubbleShrineLastDonation = 0
getgenv().DreamShrineLastDonation = 0
getgenv().LivePotions = {}

getgenv().BubPri1Name = "Speed"
getgenv().BubPri1Level = 7
getgenv().BubPri2Name = "None"
getgenv().BubPri2Level = 1
getgenv().BubPri3Name = "None"
getgenv().BubPri3Level = 1

-- Event Shop Globals
getgenv().SummerShopSlot = 1
getgenv().SummerBuyAll = true
getgenv().TropicalShopSlot = 1
getgenv().TropicalBuyAll = true
getgenv().FishingShopSlot = 1
getgenv().FishingBuyAll = true

-- Farm Waypoints (14 Summer Beach Positions)
getgenv().FarmWaypoints = {
    Vector3.new(-324.82, 11.01, -4905.78), Vector3.new(-324.83, 11.01, -4945.48),
    Vector3.new(-324.83, 11.01, -4983.02), Vector3.new(-301.82, 11.01, -4981.65),
    Vector3.new(-302.58, 11.01, -4946.31), Vector3.new(-307.30, 11.01, -4897.26),
    Vector3.new(-310.58, 11.01, -4863.20), Vector3.new(-311.91, 11.01, -4833.42),
    Vector3.new(-280.20, 11.01, -4835.50), Vector3.new(-263.05, 11.01, -4835.81),
    Vector3.new(-263.80, 11.01, -4878.59), Vector3.new(-264.47, 11.01, -4916.67),
    Vector3.new(-265.15, 11.01, -4955.82), Vector3.new(-265.54, 11.01, -4977.79)
}

-- Flower World Waypoints (8 Beach/Flower Positions)
getgenv().FlowerWaypoints = {
    Vector3.new(-6411.72, 78.19, -4682.86), Vector3.new(-6400.89, 78.19, -4709.96),
    Vector3.new(-6378.44, 78.19, -4705.21), Vector3.new(-6355.63, 78.19, -4701.59),
    Vector3.new(-6360.81, 78.19, -4668.94), Vector3.new(-6370.17, 78.19, -4644.17),
    Vector3.new(-6394.68, 78.19, -4649.31), Vector3.new(-6413.98, 78.19, -4656.90)
}

-- Spawn trigger positions (teleport here first to register in zone)
local FlowerSpawnPos = Vector3.new(-6441.91, 78.03, -4692.70)
local SummerSpawnPos = Vector3.new(-361.29, 14.20, -4907.81)

-- Zen Path coordinates (for coin/gem collection in Season quests)
local ZenPath = {
    Vector3.new(51.26, 15971.73, 40.24), Vector3.new(58.28, 15971.73, 23.29),
    Vector3.new(70.14, 15971.73, 4.34), Vector3.new(62.59, 15971.73, -10.65),
    Vector3.new(-46.04, 15971.73, 29.85), Vector3.new(-49.44, 15971.73, 9.39),
    Vector3.new(-69.18, 15971.73, 14.21), Vector3.new(-67.21, 15971.73, -6.19)
}

-- Dual-world farm timing
getgenv().SummerDuration = 60  -- seconds in Summer before switching
getgenv().FlowerDuration = 10  -- seconds in Flower before switching
getgenv().ActiveWorld = ""      -- tracks which world the farm loop is in

-- Season Pass automation
getgenv().AutoHourly = false
getgenv().AutoDaily = false
getgenv().AutoZenPath = false
getgenv().SmartBubbleLock = false
getgenv().AutoEquipTeam = false
getgenv().TaskPriority = "Egg Priority"
getgenv().IsDoingSeasonTask = false
getgenv().SeasonOriginalCFrame = nil

-- Genie Quest Engine
getgenv().GenieAutoReroll = false
getgenv().GenieMaxRerolls = 5
getgenv().GenieWantedGodTier = {}
getgenv().GenieWantedMidTier = {}
getgenv().GeniePrioritizeGems = false
getgenv().GenieCooldownEndTime = 0
getgenv().GeniePreQuestCFrame = nil

-- Floral Shop automation
getgenv().FloralAutoSlots = {false, false, false, false, false, false}
getgenv().FloralRerollAmount = 1

-- Bubble Up quest automation
getgenv().AutoBubbleUpQuest = false
getgenv().BubbleUpSellBubbles = false
getgenv().BubbleUpSellInterval = 10
getgenv().BubbleUpRelockBubbles = true
getgenv().BubbleUpSellReturn = true

local UpgradeMap = {
    ["Artifact Storage"] = "Storage",
    ["Dig Power"] = "Power",
    ["Dig Speed"] = "Speed",
    ["Search Radius"] = "Radius",
    ["Artifact Luck"] = "Luck"
}

local EggLocations = {
    ["Research Egg"] = Vector3.new(-321.91, 12.01, -5000.56),
    ["Summer Egg"] = Vector3.new(-301.06, 12.01, -5005.77),
    ["Tropical Egg"] = Vector3.new(-312.17, 12.01, -5004.43),
    ["Seal Egg"] = Vector3.new(21.83, 10.02, -5076.11)
}

local ChestLocation = Vector3.new(-275.86, 14.90, -4805.01)

local summerWebhookTimes = { kitty = 0, genie = 0, sailor = 0, chest = 0, secret = 0, status = 0, upgrades = 0, shrines = 0 }

local function GetPotionStock(targetName, targetLevel)
    for _, potion in ipairs(getgenv().LivePotions) do
        if potion.Name == targetName and potion.Level == targetLevel then
            return potion.Amount
        end
    end
    return 0
end

-- Number Parser (supports K/M/B suffix)
local function ParseNumber(str)
    if type(str) == "number" then return str end
    if not str or str == "" then return 0 end
    str = string.lower(tostring(str))
    str = string.gsub(str, "[,%s]", "")
    local multiplier = 1
    if string.find(str, "k") then multiplier = 1000; str = string.gsub(str, "k", "")
    elseif string.find(str, "m") then multiplier = 1000000; str = string.gsub(str, "m", "")
    elseif string.find(str, "b") then multiplier = 1000000000; str = string.gsub(str, "b", "") end
    local num = tonumber(str) or 0
    return math.floor(num * multiplier)
end

local function GetSeashellCount()
    if getgenv().CurrentSeashells ~= -1 then return getgenv().CurrentSeashells end
    local highestFound = 0
    for _, folder in pairs(player:GetChildren()) do
        if folder:IsA("Folder") or folder:IsA("Configuration") or folder.Name == "leaderstats" then
            for _, obj in pairs(folder:GetDescendants()) do
                if obj:IsA("IntValue") or obj:IsA("NumberValue") or obj:IsA("StringValue") then
                    local n = string.lower(obj.Name)
                    if string.find(n, "shell") and not string.find(n, "egg") then
                        local num = ParseNumber(obj.Value)
                        if num > highestFound then highestFound = num end
                    end
                end
            end
        end
    end
    return highestFound
end

local function UpdatePriorityEggs()
    local list = {}
    if getgenv().PriorityEgg1 ~= "None" then table.insert(list, getgenv().PriorityEgg1) end
    if getgenv().PriorityEgg2 ~= "None" then table.insert(list, getgenv().PriorityEgg2) end
    if getgenv().PriorityEgg3 ~= "None" then table.insert(list, getgenv().PriorityEgg3) end
    if #list == 0 then list = {"Summer Egg"} end
    getgenv().SelectedEggs = list
    getgenv().CurrentEggIndex = 1
end

local function SendSummerWebhook(title, description, color, optionalFields)
    local url = getgenv().SplashWebhookURL or ""
    if url == "" then return end
    pcall(function()
        local sessionTime = "Unknown"
        if getgenv().SessionStartTime then
            local diff = os.time() - getgenv().SessionStartTime
            local h, m, s = math.floor(diff/3600), math.floor((diff%3600)/60), diff%60
            sessionTime = string.format("%02d:%02d:%02d", h, m, s)
        end
        
        local fields = optionalFields or {}
        if #fields == 0 and description and description ~= "" then
            table.insert(fields, {["name"] = "Details", ["value"] = description, ["inline"] = false})
        end
        table.insert(fields, {["name"] = "Session Time", ["value"] = sessionTime, ["inline"] = true})
        
        local payloadDesc = (#fields > 0) and "" or description

        local payload = {
            embeds = {{
                title = title,
                description = payloadDesc,
                type = "rich",
                color = color,
                fields = fields,
                footer = {text = "Splash 2 Automation"},
                timestamp = DateTime.now():ToIsoDate()
            }}
        }
        local requestFunc = syn and syn.request or http and http.request or http_request or request or fluxus.request
        if requestFunc then
            requestFunc({Url = url, Method = "POST", Headers = {["Content-Type"]="application/json"}, Body = HttpService:JSONEncode(payload)})
        end
    end)
end

local function GetWorldTimer()
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("TextLabel") then
            local timeMatch = string.match(obj.Text, "%d+:%d+")
            if timeMatch then
                local parentPart = obj:FindFirstAncestorWhichIsA("BasePart")
                if parentPart and (parentPart.Position - ChestLocation).Magnitude < 30 then return timeMatch end
            end
        end
    end
    return nil
end

local function ParseTimeToSeconds(timeStr)
    local m, s = string.match(timeStr, "(%d+):(%d+)")
    if m and s then return (tonumber(m) * 60) + tonumber(s) end
    return 0
end


-- ==========================================
-- 🫧 1. FARMING
-- ==========================================
local sellInterval = 30
FarmTab:CreateToggle({ Name = "Auto Blow Bubbles", CurrentValue = false, Flag = "AutoBlow", Callback = function(Value) 
    Toggles.AutoBlow = Value
    if Value then task.spawn(function() while Toggles.AutoBlow do pcall(function() game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("BlowBubble") end) task.wait(0.1) end end) end
end})

FarmTab:CreateSlider({ Name = "Auto Sell Interval", Range = {1, 120}, Increment = 1, Suffix = "Seconds", CurrentValue = 30, Flag = "SellIntervalSlider", Callback = function(Value) sellInterval = Value end })

FarmTab:CreateToggle({ Name = "Auto Sell Bubbles", CurrentValue = false, Flag = "AutoSell", Callback = function(Value) 
    Toggles.AutoSell = Value
    if Value then task.spawn(function() while Toggles.AutoSell do pcall(function() game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("SellBubble") end) task.wait(sellInterval) end end) end
end})



-- ==========================================
-- 💎 1.5 AUTO GEM FARMING (Shadow Realm)
-- ==========================================
FarmTab:CreateSection("💎 Gem Farm (Shadow Realm)")
FarmTab:CreateLabel("Teleports to Shadow Realm, spirals through gem area with noclip, returns when maxed.")

getgenv().GemFarming = false
getgenv().GemFarmSavedCFrame = nil
getgenv().GemFarmPausedShops = false

local gemFarmThreshold = 5000000 -- 5M default
local gemFarmCooldownMinutes = 10
local lastAutoGemFarmTime = 0
local gemTweenSpeed = 50 -- studs per second
local gemFarmStatusLabel = nil

-- K/M/B parser
local function parseGemValue(str)
    str = str:upper():gsub(",", ""):gsub(" ", "")
    local num, suffix = str:match("^([%d%.]+)([KMB]?)$")
    if not num then return nil end
    num = tonumber(num)
    if not num then return nil end
    if suffix == "K" then num = num * 1000
    elseif suffix == "M" then num = num * 1000000
    elseif suffix == "B" then num = num * 1000000000 end
    return math.floor(num)
end

local function formatGemValue(n)
    if type(n) ~= "number" then return tostring(n) end
    if n >= 1e9 then return string.format("%.2fB", n / 1e9)
    elseif n >= 1e6 then return string.format("%.2fM", n / 1e6)
    elseif n >= 1e3 then return string.format("%.2fK", n / 1e3)
    else return tostring(n) end
end

-- Cache gems via PlayerDataChanged (LocalData module errors on require, leaderstats has no Gems)
local _cachedGems = 0
local _pendingObbyCooldowns = nil -- Buffer until obbyData is initialized
pcall(function()
    local Event = game:GetService("ReplicatedStorage").Remotes.PlayerDataChanged
    Event.OnClientEvent:Connect(function(key, value)
        if key == "Gems" and type(value) == "number" then
            _cachedGems = value
        elseif key == "ObbyCooldowns" and type(value) == "table" then
            -- Sync server obby cooldowns into obbyData (if initialized) or buffer
            getgenv().ObbyCooldowns = value -- raw epoch timestamps for dashboard
            if obbyData then
                for difficulty, timestamp in pairs(value) do
                    if obbyData[difficulty] then
                        obbyData[difficulty].LastRun = math.floor(timestamp)
                    end
                end
            else
                _pendingObbyCooldowns = value
            end
        elseif key == "Shops" and type(value) == "table" then
            -- Capture shop cooldown data for dashboard display
            local shopCD = {}
            for shopId, shopData in pairs(value) do
                if type(shopData) == "table" and shopData.Began and shopData.Period then
                    shopCD[shopId] = { Began = shopData.Began, Period = shopData.Period }
                    
                    if getgenv().LastShopRefresh then
                        local lastBegan = getgenv().LastShopRefresh[shopId]
                        if lastBegan and lastBegan ~= shopData.Began then
                            if getgenv().executeSmartShopAutoBuyer then
                                getgenv().executeSmartShopAutoBuyer(shopId)
                            end
                        end
                    end
                end
            end
            getgenv().ShopCooldowns = shopCD
            
            local newRefresh = {}
            for k, v in pairs(shopCD) do newRefresh[k] = v.Began end
            getgenv().LastShopRefresh = newRefresh
        elseif key == "Cooldowns" and type(value) == "table" then
            -- Server-synced chest/activity cooldowns (timestamps)
            if value["Infinity Chest"] then
                local remaining = math.floor(value["Infinity Chest"]) - os.time()
                if remaining > 0 then
                    getgenv().InfChestCooldownEnd = os.time() + remaining
                end
            end
            if value["Summer Chest"] then
                -- Summer chest uses InternalCooldownEnd (set in Summer tab)
                local remaining = math.floor(value["Summer Chest"]) - os.time()
                if remaining > 0 and InternalCooldownEnd then
                    InternalCooldownEnd = os.time() + remaining
                end
            end
        end
    end)
end)

-- Also try to get initial gems from PlayerDataLoaded or existing data
pcall(function()
    -- Some games fire PlayerDataLoaded with all initial data
    local Event = game:GetService("ReplicatedStorage").Remotes.PlayerDataLoaded
    Event.OnClientEvent:Connect(function(data)
        if type(data) == "table" and data.Gems then
            _cachedGems = data.Gems
        end
    end)
end)

local function getCurrentGems()
    pcall(function()
        local LocalDataModule = require(game:GetService("ReplicatedStorage").Client.Framework.Services.LocalData)
        if LocalDataModule and LocalDataModule.Get then
            local data = LocalDataModule.Get()
            if type(data) == "table" and data.Gems then
                _cachedGems = data.Gems
            end
        end
    end)

    -- Primary: cached from PlayerDataChanged events or LocalData
    if _cachedGems > 0 then return _cachedGems end
    
    -- Fallback 1: leaderstats (game uses emoji names)
    pcall(function()
        local ls = player:FindFirstChild("leaderstats")
        if ls then
            for _, c in ipairs(ls:GetChildren()) do
                if c.Name:find("Gem") or c.Name:find("💎") then
                    _cachedGems = c.Value
                end
            end
        end
    end)
    
    -- Fallback 2: PlayerData folder
    pcall(function()
        local pd = player:FindFirstChild("PlayerData")
        if pd then
            local g = pd:FindFirstChild("Gems")
            if g then _cachedGems = g.Value end
        end
    end)
    
    -- Fallback 3: Read from GUI (works in all worlds)
    if _cachedGems == 0 then
        pcall(function()
            for _, gui in pairs(player.PlayerGui:GetDescendants()) do
                if gui:IsA("TextLabel") and gui.Visible then
                    local rawText = gui.Text
                    local text = rawText:gsub("<[^>]+>", "")
                    -- Match patterns like "💎 1.5M" or "Gems: 500K" or just "1,234,567"
                    local gemText = text:match("💎%s*([%d,.]+[KMBTkmbt]?)") or text:match("[Gg]ems?:?%s*([%d,.]+[KMBTkmbt]?)")
                    if gemText then
                        -- Parse suffixed values
                        local num = tonumber(gemText:gsub(",", ""))
                        if not num then
                            local base, suffix = gemText:match("([%d,.]+)([KMBTkmbt])")
                            base = tonumber(base and base:gsub(",", "") or "0") or 0
                            local multipliers = {K=1e3,k=1e3,M=1e6,m=1e6,B=1e9,b=1e9,T=1e12,t=1e12}
                            num = base * (multipliers[suffix] or 1)
                        end
                        if num and num > 0 then _cachedGems = num end
                    end
                end
            end
        end)
    end
    
    return _cachedGems
end

-- Perimeter coordinates (user-logged, clockwise)
local gemPerimeter = {
    Vector3.new(2357.16, 3158.51, 885.00),
    Vector3.new(2344.19, 3158.48, 861.45),
    Vector3.new(2299.73, 3158.49, 849.88),
    Vector3.new(2279.45, 3158.50, 868.87),
    Vector3.new(2281.90, 3158.49, 884.27),
    Vector3.new(2265.29, 3158.51, 894.17),
    Vector3.new(2266.23, 3158.52, 907.39),
    Vector3.new(2279.66, 3158.52, 907.05),
    Vector3.new(2286.09, 3158.53, 921.73),
    Vector3.new(2318.61, 3158.56, 925.06),
    Vector3.new(2325.83, 3158.54, 940.46),
    Vector3.new(2333.55, 3158.55, 934.07),
    Vector3.new(2334.37, 3158.57, 919.51),
    Vector3.new(2358.37, 3158.51, 886.62),
}
local gemCenter = Vector3.new(2309.3, 3158.52, 898.5)

-- Generate spiral waypoints (5 rings scaling inward + center)
local function generateSpiralPath()
    local scales = {1.0, 0.80, 0.60, 0.40, 0.20}
    local spiralIn = {}
    local spiralOut = {}
    
    for _, scale in ipairs(scales) do
        local ring = {}
        for _, point in ipairs(gemPerimeter) do
            local offset = point - gemCenter
            local scaled = gemCenter + (offset * scale)
            table.insert(ring, scaled)
        end
        -- Clockwise IN: append ring in order
        for _, wp in ipairs(ring) do
            table.insert(spiralIn, wp)
        end
    end
    -- Final center point
    table.insert(spiralIn, gemCenter)
    
    -- Counter-clockwise OUT: center → rings reversed
    table.insert(spiralOut, gemCenter)
    for i = #scales, 1, -1 do
        local scale = scales[i]
        local ring = {}
        for _, point in ipairs(gemPerimeter) do
            local offset = point - gemCenter
            local scaled = gemCenter + (offset * scale)
            table.insert(ring, scaled)
        end
        -- Reverse the ring for counter-clockwise
        for j = #ring, 1, -1 do
            table.insert(spiralOut, ring[j])
        end
    end
    
    return spiralIn, spiralOut
end

-- Noclip control
local noclipConnection = nil
local function enableNoclip()
    if noclipConnection then return end
    noclipConnection = game:GetService("RunService").Stepped:Connect(function()
        pcall(function()
            local char = player.Character
            if char then
                for _, part in pairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = false
                    end
                end
            end
        end)
    end)
end

local function disableNoclip()
    if noclipConnection then
        noclipConnection:Disconnect()
        noclipConnection = nil
    end
end

-- Tween along waypoints
local function tweenToPoint(targetPos, speed)
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    local distance = (hrp.Position - targetPos).Magnitude
    local tweenTime = distance / speed
    if tweenTime < 0.05 then tweenTime = 0.05 end
    
    local tweenInfo = TweenInfo.new(tweenTime, Enum.EasingStyle.Linear)
    local tween = game:GetService("TweenService"):Create(hrp, tweenInfo, {
        CFrame = CFrame.new(targetPos)
    })
    tween:Play()
    tween.Completed:Wait()
end

local function runSpiralCycle(speed, statusLabel)
    local spiralIn, spiralOut = generateSpiralPath()
    
    -- Clockwise spiral inward
    for i, wp in ipairs(spiralIn) do
        if not getgenv().GemFarming then return false end
        if statusLabel then statusLabel:Set("Gems: " .. formatGemValue(getCurrentGems()) .. " | Spiral In " .. i .. "/" .. #spiralIn) end
        tweenToPoint(wp, speed)
    end
    
    -- Counter-clockwise spiral outward
    for i, wp in ipairs(spiralOut) do
        if not getgenv().GemFarming then return false end
        if statusLabel then statusLabel:Set("Gems: " .. formatGemValue(getCurrentGems()) .. " | Spiral Out " .. i .. "/" .. #spiralOut) end
        tweenToPoint(wp, speed)
    end
    
    return true
end

FarmTab:CreateToggle({
    Name = "Farm Gems",
    CurrentValue = false,
    Flag = "GemFarmToggle",
    Callback = function(Value)
        Toggles.GemFarmToggle = Value
        getgenv().GemFarming = Value
        if Value then
            task.spawn(function()
                -- Wait for player data to be available (prevents auto-start on config load)
                local currentGems = getCurrentGems()
                local waitAttempts = 0
                while currentGems == 0 and waitAttempts < 20 do
                    task.wait(0.5)
                    currentGems = getCurrentGems()
                    waitAttempts = waitAttempts + 1
                end
                
                -- If we still can't read gems, abort
                if currentGems == 0 then
                    Rayfield:Notify({ Title = "Gem Farm", Content = "Cannot read gem count. Aborting.", Duration = 5 })
                    getgenv().GemFarming = false
                    Toggles.GemFarmToggle = false
                    return
                end
                
                -- Sync threshold from Rayfield flags in case it was loaded from config but callback didn't fire
                pcall(function()
                    if Rayfield and Rayfield.Flags and Rayfield.Flags["GemThresholdInput"] then
                        local flagVal = Rayfield.Flags["GemThresholdInput"].CurrentValue
                        if type(flagVal) == "string" and flagVal ~= "" then
                            local parsed = parseGemValue(flagVal)
                            if parsed then gemFarmThreshold = parsed end
                        end
                    end
                end)
                
                -- Check if already above threshold
                if currentGems >= gemFarmThreshold and gemFarmThreshold > 0 then
                    Rayfield:Notify({ Title = "Gem Farm", Content = "Gems (" .. formatGemValue(currentGems) .. ") already above threshold (" .. formatGemValue(gemFarmThreshold) .. "). Not starting.", Duration = 5 })
                    getgenv().GemFarming = false
                    Toggles.GemFarmToggle = false
                    return
                end
                
                if getgenv().IsReconnecting then
                    consoleLog("Waiting for Reconnect teleport to finish...")
                    repeat task.wait(1) until not getgenv().IsReconnecting
                    consoleLog("Reconnect finished. Preparing Auto Gem in 5 seconds...")
                    task.wait(5)
                end
                
                -- Wait for summer/obby to finish before teleporting to Shadow Realm
                while getgenv().IsClaimingChest or getgenv().IsClaimingInfChest or getgenv().IsHatchingPhase or getgenv().IsDoingQuest or getgenv().ObbySavedCFrame do
                    task.wait(1)
                end
                
                if not Toggles.GemFarmToggle then return end
                
                -- 2. Save current position (unique key — no collision)
                local char = player.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    getgenv().GemFarmSavedCFrame = hrp.CFrame
                end
                
                -- 3. Pause auto-buy shops
                local shopWasActive = autoBuyActive
                if autoBuyActive then
                    getgenv().GemFarmPausedShops = true
                end
                
                -- 4. Teleport to Shadow Realm
                Rayfield:Notify({ Title = "Gem Farm", Content = "Teleporting to Shadow Realm gem area...", Duration = 3 })
                consoleLog("Farming Gems in Shadow Realm")
                pcall(function()
                    local Event = game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent
                    Event:FireServer(
                        "Teleport",
                        "Workspace.ShadowRealm.Spawn"
                    )
                end)
                task.wait(3)
                
                -- 5. Teleport to first perimeter point
                local freshChar = player.Character
                local freshHrp = freshChar and freshChar:FindFirstChild("HumanoidRootPart")
                if freshHrp then
                    freshHrp.CFrame = CFrame.new(gemPerimeter[1])
                end
                task.wait(1)
                
                -- 6. Enable noclip
                enableNoclip()
                
                -- 7. Spiral loop
                local cycleCount = 0
                local flatCycleCount = 0 -- Track consecutive cycles with no gem gain
                local zeroReadCount = 0 -- Track consecutive 0-gem readings
                local lastKnownGems = getCurrentGems() -- Best gem value we've seen
                while getgenv().GemFarming do
                    local gemsBeforeCycle = getCurrentGems()
                    if gemsBeforeCycle > 0 then lastKnownGems = gemsBeforeCycle end
                    cycleCount = cycleCount + 1
                    
                    if gemFarmStatusLabel then
                        gemFarmStatusLabel:Set("Cycle #" .. cycleCount .. " | Gems: " .. formatGemValue(lastKnownGems))
                    end
                    
                    local completed = runSpiralCycle(gemTweenSpeed, gemFarmStatusLabel)
                    if not completed then break end
                    
                    -- Read gems with retry (Shadow Realm often returns 0 temporarily)
                    local gemsAfterCycle = getCurrentGems()
                    if gemsAfterCycle == 0 then
                        for _retry = 1, 5 do
                            task.wait(1)
                            gemsAfterCycle = getCurrentGems()
                            if gemsAfterCycle > 0 then break end
                        end
                    end
                    
                    -- Update last known good reading
                    if gemsAfterCycle > 0 then
                        lastKnownGems = gemsAfterCycle
                        zeroReadCount = 0
                    else
                        zeroReadCount = zeroReadCount + 1
                    end
                    
                    -- Safety cap: don't loop forever
                    if cycleCount >= 30 then
                        if gemFarmStatusLabel then
                            gemFarmStatusLabel:Set("Safety cap (30 cycles). Gems: " .. formatGemValue(lastKnownGems))
                        end
                        Rayfield:Notify({ Title = "Gem Farm", Content = "Safety cap reached (30 cycles). Stopping.", Duration = 5 })
                        break
                    end
                    
                    -- Too many zero reads = game stopped updating, treat as maxed
                    if zeroReadCount >= 5 then
                        if gemFarmStatusLabel then
                            gemFarmStatusLabel:Set("Lost gem tracking. Last known: " .. formatGemValue(lastKnownGems))
                        end
                        Rayfield:Notify({ Title = "Gem Farm", Content = "Can't read gems (stale). Stopping at ~" .. formatGemValue(lastKnownGems), Duration = 5 })
                        break
                    end
                    
                    -- Max detection: 3 consecutive flat or zero-read cycles
                    if gemsAfterCycle == 0 then
                        flatCycleCount = flatCycleCount + 1 -- Zero reads count as flat
                    elseif gemsAfterCycle > 0 and gemsBeforeCycle > 0 and gemsAfterCycle <= gemsBeforeCycle and cycleCount > 1 then
                        flatCycleCount = flatCycleCount + 1
                    elseif gemsAfterCycle > 0 and gemsAfterCycle > gemsBeforeCycle then
                        flatCycleCount = 0 -- Reset if gems increased
                    end
                    
                    if flatCycleCount >= 3 then
                        if gemFarmStatusLabel then
                            gemFarmStatusLabel:Set("Maxed out! Gems: " .. formatGemValue(lastKnownGems) .. " after " .. cycleCount .. " cycles")
                        end
                        Rayfield:Notify({ Title = "Gem Farm", Content = "Gems maxed out at " .. formatGemValue(lastKnownGems) .. "! Returning...", Duration = 5 })
                        break
                    end
                    
                    -- Threshold check — use lastKnownGems so it works even during 0-reads
                    if gemFarmThreshold > 0 and lastKnownGems >= gemFarmThreshold then
                        if gemFarmStatusLabel then
                            gemFarmStatusLabel:Set("Threshold reached! Gems: " .. formatGemValue(lastKnownGems))
                        end
                        Rayfield:Notify({ Title = "Gem Farm", Content = "Reached " .. formatGemValue(lastKnownGems) .. " gems! Returning...", Duration = 5 })
                        break
                    end
                    
                    task.wait(0.5)
                end
                
                -- 8. Cleanup: disable noclip
                disableNoclip()
                getgenv().GemFarming = false
                lastAutoGemFarmTime = os.time() -- Start the cooldown timer!
                -- We DO NOT turn off the GUI toggle, so it can be re-triggered by the shop loop later!
                
                -- 9. Return to saved position
                if getgenv().GemFarmSavedCFrame then
                    pcall(function()
                        game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("Teleport", "Workspace.Worlds.The Overworld.FastTravel.Spawn")
                    end)
                    task.wait(3)
                    local c = player.Character
                    local r = c and c:FindFirstChild("HumanoidRootPart")
                    if r then
                        r.CFrame = getgenv().GemFarmSavedCFrame
                    end
                    getgenv().GemFarmSavedCFrame = nil
                end
                
                -- 10. Resume shops if they were active
                if getgenv().GemFarmPausedShops then
                    getgenv().GemFarmPausedShops = false
                end
                
                if gemFarmStatusLabel then
                    gemFarmStatusLabel:Set("Gem Farm: Idle")
                end
            end)
        end
    end,
})

FarmTab:CreateLabel("⚠️ WARNING: Do not put over your max gems!")
FarmTab:CreateInput({
    Name = "Min Gems Threshold",
    PlaceholderText = "e.g. 500K, 5M, 1.5B",
    RemoveTextAfterFocusLost = false,
    Flag = "GemThresholdInput",
    Callback = function(Text)
        local parsed = parseGemValue(Text)
        if parsed then
            gemFarmThreshold = parsed
            Rayfield:Notify({ Title = "Gem Farm", Content = "Threshold set to " .. formatGemValue(parsed), Duration = 3 })
        else
            Rayfield:Notify({ Title = "Gem Farm", Content = "Invalid format. Use 500K, 5M, 1.5B etc.", Duration = 3 })
        end
    end,
})

FarmTab:CreateToggle({
    Name = "Enable Gem Farm Cooldown",
    CurrentValue = true,
    Flag = "GemFarmCooldownToggle",
    Callback = function(Value)
        Toggles.GemFarmCooldown = Value
    end
})

FarmTab:CreateSlider({
    Name = "Gem Cooldown (Minutes)",
    Range = {1, 60},
    Increment = 1,
    CurrentValue = 10,
    Suffix = "m",
    Flag = "GemFarmCooldownSlider",
    Callback = function(Value)
        gemFarmCooldownMinutes = Value
    end
})
FarmTab:CreateSlider({
    Name = "Tween Speed",
    Range = {10, 200},
    Increment = 5,
    CurrentValue = 50,
    Suffix = " studs/s",
    Flag = "GemTweenSpeed",
    Callback = function(Value)
        gemTweenSpeed = Value
    end,
})

gemFarmStatusLabel = FarmTab:CreateLabel("Gem Farm: Idle")

task.wait() -- UI renderer yield
-- ==========================================
-- 🥚 2. HATCHING (Splash1 Enhanced)
-- ==========================================
EggTab:CreateDropdown({
    Name = "Select Egg",
    Options = {"Common Egg", "Uncommon Egg", "Rare Egg", "Epic Egg", "Legendary Egg", "Water Egg", "Fire Egg", "Nature Egg", "Magic Egg", "Alien Egg", "Magma Egg", "Crystal Egg", "Lunar Egg", "Void Egg", "Heavenly Egg", "Nuclear Egg", "Infinity Egg", "Anniversary Egg", "1B Egg", "Golf Egg", "Cyber Egg"},
    CurrentOption = {"Magma Egg"},
    MultipleOptions = false,
    Flag = "SelectEggDrop",
    Callback = function(Option)
        getgenv().SelectedEgg = Option[1]
    end,
})
EggTab:CreateInput({ Name = "Custom Egg Override", PlaceholderText = "Type exact egg name here...", Flag = "CustomEggInput", Callback = function(Text) if Text ~= "" then getgenv().SelectedEgg = Text end end })

EggTab:CreateSlider({
    Name = "Hatch Amount (Multi-Hatch)",
    Range = {1, 12},
    Increment = 1,
    CurrentValue = 1,
    Flag = "HatchAmountSlider",
    Callback = function(Value)
        getgenv().HatchAmount = Value
    end,
})

EggTab:CreateSlider({
    Name = "Fast Hatch Delay (Speed)",
    Range = {0.1, 2},
    Increment = 0.1,
    CurrentValue = 0.5,
    Flag = "SpeedSlider",
    Callback = function(Value)
        getgenv().HatchDelay = Value
    end,
})

EggTab:CreateToggle({
    Name = "Fast Hatch",
    CurrentValue = false,
    Flag = "FastHatchToggle",
    Callback = function(Value)
        getgenv().AutoHatch = Value
    end,
})

EggTab:CreateToggle({
    Name = "Hide Hatch UI Animation",
    CurrentValue = false,
    Flag = "HideHatchToggle",
    Callback = function(Value)
        getgenv().HideHatchActive = Value
    end,
})

EggTab:CreateToggle({
    Name = "Animation Skipper (Instant Hatch)",
    CurrentValue = false,
    Flag = "AnimSkipToggle",
    Callback = function(Value)
        Toggles.AnimSkip = Value
        if Value then ApplyAnimationSkip() end
    end,
})

task.wait() -- UI renderer yield
-- ==========================================
-- 🎒 2.5 INVENTORY MANAGEMENT (Rarity-Based)
-- ==========================================
getgenv().AutoDeleteCommon = false
getgenv().AutoDeleteUncommon = false
getgenv().AutoDeleteRare = false
getgenv().AutoDeleteEpic = false
getgenv().AutoDeleteLegendary = false

InventoryTab:CreateSection("🗑️ Rarity Deletion")

InventoryTab:CreateToggle({
   Name = "Auto-Delete Commons",
   CurrentValue = false,
   Flag = "DelCommon",
   Callback = function(Value)
        getgenv().AutoDeleteCommon = Value
   end,
})

InventoryTab:CreateToggle({
   Name = "Auto-Delete Uncommons",
   CurrentValue = false,
   Flag = "DelUncommon",
   Callback = function(Value)
        getgenv().AutoDeleteUncommon = Value
   end,
})

InventoryTab:CreateToggle({
   Name = "Auto-Delete Rares",
   CurrentValue = false,
   Flag = "DelRare",
   Callback = function(Value)
        getgenv().AutoDeleteRare = Value
   end,
})

InventoryTab:CreateToggle({
   Name = "Auto-Delete Epics",
   CurrentValue = false,
   Flag = "DelEpic",
   Callback = function(Value)
        getgenv().AutoDeleteEpic = Value
   end,
})

InventoryTab:CreateToggle({
   Name = "Auto-Delete Legendaries",
   CurrentValue = false,
   Flag = "DelLegendary",
   Callback = function(Value)
        getgenv().AutoDeleteLegendary = Value
   end,
})

InventoryTab:CreateSection("⬆️ Pet Upgrades")
InventoryTab:CreateToggle({
   Name = "Auto-Craft Shinies",
   CurrentValue = false,
   Flag = "AutoCraftToggle",
   Callback = function(Value)
        getgenv().AutoCraftShiny = Value
   end,
})

-- Rarity-Based Auto-Delete Loop
local isDeleting = false
task.spawn(function()
    while task.wait(1) do
        if not isDeleting and getgenv().BGSI_Inventory then
            isDeleting = true
            for _, pet in pairs(getgenv().BGSI_Inventory) do
                local shouldDelete = false
                local petRarity = pet.Rarity or pet.Tier or ""
                
                if getgenv().AutoDeleteCommon and petRarity == "Common" then shouldDelete = true end
                if getgenv().AutoDeleteUncommon and petRarity == "Uncommon" then shouldDelete = true end
                if getgenv().AutoDeleteRare and petRarity == "Rare" then shouldDelete = true end
                if getgenv().AutoDeleteEpic and petRarity == "Epic" then shouldDelete = true end
                if getgenv().AutoDeleteLegendary and petRarity == "Legendary" then shouldDelete = true end

                if shouldDelete then
                    local amount = pet.Amount or 1
                    pcall(function()
                        NetworkRemoteFunction:InvokeServer("DeletePet", pet.Id, amount, false)
                    end)
                    task.wait(0.2)
                end
            end
            isDeleting = false
        end
    end
end)

-- Auto-Craft Shiny Loop
local isCrafting = false
task.spawn(function()
    while task.wait(2) do
        if getgenv().AutoCraftShiny and not isCrafting and getgenv().BGSI_Inventory then
            isCrafting = true
            for _, pet in pairs(getgenv().BGSI_Inventory) do
                if not pet.Shiny and (pet.Amount and pet.Amount >= 10) then
                    pcall(function()
                        NetworkRemoteFunction:InvokeServer("MakePetShiny", pet.Id)
                    end)
                    task.wait(0.4)
                end
            end
            isCrafting = false
        end
    end
end)

task.wait() -- UI renderer yield
-- ==========================================
-- 🧪 3. POTIONS & RUNES
-- ==========================================
local potionTier = "I"
local runeTier = "I"
local potionInterval = 60

local tierMap = { ["I"] = 1, ["II"] = 2, ["III"] = 3, ["IV"] = 4, ["V"] = 5, ["Evolved"] = 6, ["Infinity"] = 7 }

PotionTab:CreateSection("🧪 Potion Settings")
PotionTab:CreateSlider({ Name = "Use Interval Timer", Range = {1, 60}, Increment = 1, Suffix = " mins", CurrentValue = 1, Flag = "PotionTimer", Callback = function(Value) potionInterval = Value * 60 end })
PotionTab:CreateDropdown({ Name = "Potion Tier", Options = {"I", "II", "III", "IV", "V", "Evolved", "Infinity"}, CurrentOption = {"I"}, Flag = "PotionTierDrop", Callback = function(O) potionTier = O[1] end })
PotionTab:CreateToggle({ Name = "Auto Lucky Potion", CurrentValue = false, Flag = "AutoLuck", Callback = function(V) Toggles.AutoLuck = V end })
PotionTab:CreateToggle({ Name = "Auto Speed Potion", CurrentValue = false, Flag = "AutoSpeed", Callback = function(V) Toggles.AutoSpeed = V end })
PotionTab:CreateToggle({ Name = "Auto Coins Potion", CurrentValue = false, Flag = "AutoCoins", Callback = function(V) Toggles.AutoCoins = V end })
PotionTab:CreateToggle({ Name = "Auto Mythic Potion", CurrentValue = false, Flag = "AutoMythic", Callback = function(V) Toggles.AutoMythic = V end })
PotionTab:CreateToggle({ Name = "Auto Tickets Potion", CurrentValue = false, Flag = "AutoTickets", Callback = function(V) Toggles.AutoTickets = V end })

PotionTab:CreateSection("✨ Special Elixirs")
PotionTab:CreateToggle({ Name = "Auto Egg Elixir", CurrentValue = false, Flag = "AutoEggElix", Callback = function(V) Toggles.AutoEgg = V end })
PotionTab:CreateToggle({ Name = "Auto Secret Elixir", CurrentValue = false, Flag = "AutoSecret", Callback = function(V) Toggles.AutoSecret = V end })
PotionTab:CreateToggle({ Name = "Auto Infinity Elixir", CurrentValue = false, Flag = "AutoInf", Callback = function(V) Toggles.AutoInf = V end })
PotionTab:CreateToggle({ Name = "Auto Anniversary Elixir", CurrentValue = false, Flag = "AutoAnniPot", Callback = function(V) Toggles.AutoAnniPot = V end })
PotionTab:CreateToggle({ Name = "Auto Festive Elixir", CurrentValue = false, Flag = "AutoFestive", Callback = function(V) Toggles.AutoFestive = V end })

RunesTab:CreateSection("🔮 Rune Settings")
RunesTab:CreateDropdown({ Name = "Rune Tier", Options = {"I", "II", "III"}, CurrentOption = {"I"}, Flag = "RuneTierDrop", Callback = function(O) runeTier = O[1] end })
RunesTab:CreateToggle({ Name = "Auto Luck Rune", CurrentValue = false, Flag = "LuckRune", Callback = function(V) Toggles.LuckRune = V end })
RunesTab:CreateToggle({ Name = "Auto Bubbles Rune", CurrentValue = false, Flag = "BubblesRune", Callback = function(V) Toggles.BubblesRune = V end })
RunesTab:CreateToggle({ Name = "Auto Secret Rune", CurrentValue = false, Flag = "SecretRune", Callback = function(V) Toggles.SecretRune = V end })

task.spawn(function()
    while true do
        local pTier = tierMap[potionTier] or 1
        local rTier = tierMap[runeTier] or 1
        pcall(function()
            if Toggles.AutoLuck then game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("UsePotion", "Lucky", pTier) end
            if Toggles.AutoSpeed then game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("UsePotion", "Speed", pTier) end
            if Toggles.AutoCoins then game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("UsePotion", "Coins", pTier) end
            if Toggles.AutoMythic then game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("UsePotion", "Mythic", pTier) end
            if Toggles.AutoTickets then game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("UsePotion", "Tickets", pTier) end
            if Toggles.AutoEgg then game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("UsePotion", "Egg Elixir", pTier) end
            if Toggles.AutoSecret then game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("UsePotion", "Secret Elixir", pTier) end
            if Toggles.AutoInf then game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("UsePotion", "Infinity Elixir", pTier) end
            if Toggles.AutoAnniPot then game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("UsePotion", "Anniversary Elixir", pTier) end
            if Toggles.AutoFestive then game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("UsePotion", "Festive Elixir", pTier) end
            if Toggles.LuckRune then game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("UseRune", "Lucky", rTier, 1) end
            if Toggles.BubblesRune then game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("UseRune", "Bubbles", rTier, 1) end
            if Toggles.SecretRune then game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("UseRune", "Secret", rTier, 1) end
        end)
        task.wait(potionInterval)
    end
end)

task.wait() -- UI renderer yield
-- ==========================================
-- 🎯 4. CHESTS & GIFTS
-- ==========================================
HuntTab:CreateSection("🎡 Wheel Spin")
HuntTab:CreateToggle({ Name = "Auto Wheel Spin", CurrentValue = false, Flag = "AutoWheel", Callback = function(V) 
    Toggles.AutoWheel = V
    if V then
        task.spawn(function()
            while Toggles.AutoWheel do
                pcall(function()
                    game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteFunction:InvokeServer("WheelSpin")
                    task.wait(1)
                    game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("ClaimWheelSpinQueue")
                end)
                task.wait(5)
            end
        end)
    end
end })

HuntTab:CreateSection("📦 Auto Chests")
HuntTab:CreateToggle({ Name = "Auto Common Chest", CurrentValue = false, Flag = "CmnChest", Callback = function(V) Toggles.CmnChest = V end })
HuntTab:CreateToggle({ Name = "Auto Golden Chest", CurrentValue = false, Flag = "GoldChest", Callback = function(V) Toggles.GoldChest = V end })
HuntTab:CreateToggle({ Name = "Auto Giant Chest", CurrentValue = false, Flag = "GiantChest", Callback = function(V) Toggles.GiantChest = V end })
HuntTab:CreateToggle({ Name = "Auto Royal Chest", CurrentValue = false, Flag = "RoyalChest", Callback = function(V) Toggles.RoyalChest = V end })
HuntTab:CreateToggle({ Name = "Auto Magma Chest", CurrentValue = false, Flag = "MagmaChest", Callback = function(V) Toggles.MagmaChest = V end })
HuntTab:CreateToggle({ Name = "Auto Crystal Chest", CurrentValue = false, Flag = "CrystalChest", Callback = function(V) Toggles.CrystalChest = V end })
HuntTab:CreateToggle({ Name = "Auto Lunar Chest", CurrentValue = false, Flag = "LunarChest", Callback = function(V) Toggles.LunarChest = V end })
HuntTab:CreateToggle({ Name = "Auto Void Chest", CurrentValue = false, Flag = "VoidChest", Callback = function(V) Toggles.VoidChest = V end })
HuntTab:CreateToggle({ Name = "Auto Ticket Chest", CurrentValue = false, Flag = "TicketChest", Callback = function(V) Toggles.TicketChest = V end })

local chestPriority = {
    { flag = "GiantChest",   name = "Giant Chest",   priority = 1 },
    { flag = "RoyalChest",   name = "Royal Chest",   priority = 2 },
    { flag = "VoidChest",    name = "Void Chest",    priority = 3 },
    { flag = "CrystalChest", name = "Crystal Chest", priority = 4 },
    { flag = "LunarChest",   name = "Lunar Chest",   priority = 5 },
    { flag = "MagmaChest",   name = "Magma Chest",   priority = 6 },
    { flag = "GoldChest",    name = "Golden Chest",  priority = 7 },
    { flag = "CmnChest",     name = "Common Chest",  priority = 8 },
    { flag = "TicketChest",  name = "Ticket Chest",  priority = 9 },
}

task.spawn(function()
    local re = game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent
    while task.wait(5) do
        for _, chest in ipairs(chestPriority) do
            if Toggles[chest.flag] then
                pcall(function() re:FireServer("ClaimChest", chest.name) end)
                task.wait(0.3)
            end
        end
    end
end)

HuntTab:CreateSection("♾️ Infinity Chest (VIP Gamepass)")
HuntTab:CreateLabel("⚠️ Requires VIP Gamepass. Teleports to chest, claims, returns.")
local InfChestTimerLabel = HuntTab:CreateLabel("Infinity Chest: Waiting...")
local InfChestLocation = CFrame.new(181.61, 12.27, -23.26)
getgenv().InfChestEnabled = false
getgenv().InfChestCooldownEnd = 0
getgenv().IsClaimingInfChest = false
getgenv().TrackInfChest = false

HuntTab:CreateToggle({ Name = "Webhook: Track Infinity Chest", CurrentValue = false, Flag = "TrackInfChestHook", Callback = function(V) getgenv().TrackInfChest = V end })
HuntTab:CreateToggle({
    Name = "Auto Claim Infinity Chest",
    CurrentValue = false, Flag = "AutoInfChest",
    Callback = function(Value)
        getgenv().InfChestEnabled = Value
        if Value then
            task.spawn(function()
                while getgenv().InfChestEnabled do
                    local currentTime = os.time()
                    if currentTime >= getgenv().InfChestCooldownEnd then
                        -- Wait for other teleport systems
                        while getgenv().IsClaimingChest or getgenv().GemFarming or getgenv().ObbySavedCFrame or getgenv().IsDoingQuest do task.wait(1) end
                        getgenv().IsClaimingInfChest = true
                        InfChestTimerLabel:Set("Infinity Chest: Teleporting...")
                        
                        local originalPosition = nil
                        pcall(function()
                            local char = player.Character
                            if char and char:FindFirstChild("HumanoidRootPart") then
                                originalPosition = char:GetPivot()
                            end
                        end)
                        
                        -- Teleport to chest
                        pcall(function() player.Character:PivotTo(InfChestLocation) end)
                        task.wait(3)
                        
                        -- Claim
                        InfChestTimerLabel:Set("Infinity Chest: Claiming...")
                        pcall(function() NetworkRemoteEvent:FireServer("ClaimChest", "Infinity Chest") end)
                        task.wait(2)
                        
                        -- Set cooldown (1 hour)
                        getgenv().InfChestCooldownEnd = os.time() + 3600
                        getgenv().ChestTimers.InfinityChest.claimedAt = os.time()
                        syncToCloud()
                        
                        -- Webhook
                        if getgenv().TrackInfChest then
                            pcall(function() SendSummerWebhook("♾️ Infinity Chest", "Auto-claimed Infinity Chest!", 0x9B59B6) end)
                        end
                        
                        -- Return
                        if originalPosition then
                            InfChestTimerLabel:Set("Infinity Chest: Returning...")
                            pcall(function() player.Character:PivotTo(originalPosition) end)
                            task.wait(1.5)
                        end
                        
                        getgenv().IsClaimingInfChest = false
                    else
                        local timeLeft = getgenv().InfChestCooldownEnd - currentTime
                        local mn = math.floor(timeLeft / 60)
                        local sc = timeLeft % 60
                        InfChestTimerLabel:Set(string.format("Infinity Chest: %02d:%02d", mn, sc))
                    end
                    task.wait(1)
                end
            end)
        else
            InfChestTimerLabel:Set("Infinity Chest: Off")
            getgenv().IsClaimingInfChest = false
        end
    end,
})

HuntTab:CreateSection("🎁 Event Chests")
HuntTab:CreateLabel("Scans workspace for event chests tagged via CollectionService.")

local eventChestNames = {
    "Spring Chest", "Summer Chest", "Winter Chest", "Halloween Chest",
    "Valentine Chest", "Easter Chest", "Anniversary Chest", "Birthday Chest",
    "Bee Chest", "St Patricks Chest", "Lunar Chest", "Wonderland Chest"
}
local selectedEventChests = {}

HuntTab:CreateDropdown({
    Name = "Select Event Chests",
    Options = eventChestNames,
    CurrentOption = {},
    MultipleOptions = true,
    Flag = "EventChestSelect",
    Callback = function(Options)
        selectedEventChests = {}
        for _, name in ipairs(Options) do
            selectedEventChests[name] = true
        end
    end,
})

HuntTab:CreateToggle({ Name = "Auto Open Event Chests", CurrentValue = false, Flag = "EventChestToggle", Callback = function(V)
    Toggles.EventChests = V
    if V then
        task.spawn(function()
            while Toggles.EventChests do
                pcall(function()
                    -- Method 1: Fire by name from dropdown selection
                    for chestName, _ in pairs(selectedEventChests) do
                        game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("UnlockEventChest", chestName, true)
                        task.wait(0.3)
                    end
                    
                    -- Method 2: Scan workspace for tagged event chests (matches real game code)
                    for _, chest in pairs(game:GetService("CollectionService"):GetTagged("EventChest")) do
                        if chest and chest.Parent then
                            game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("UnlockEventChest", chest.Name, true)
                            task.wait(0.3)
                        end
                    end
                end)
                task.wait(5)
            end
        end)
    end
end })

HuntTab:CreateButton({ Name = "🔍 Scan & List Active Event Chests", Callback = function()
    local found = {}
    pcall(function()
        for _, chest in pairs(game:GetService("CollectionService"):GetTagged("EventChest")) do
            if chest and chest.Parent then
                table.insert(found, chest.Name)
            end
        end
    end)
    if #found > 0 then
        Rayfield:Notify({ Title = "Event Chests Found", Content = table.concat(found, ", "), Duration = 8 })
    else
        Rayfield:Notify({ Title = "Event Chests", Content = "No active event chests found in workspace.", Duration = 5 })
    end
end })

HuntTab:CreateSection("🎁 Gifts & Mystery Boxes")
HuntTab:CreateToggle({ Name = "Auto Claim Daily Rewards", CurrentValue = false, Flag = "AutoDaily", Callback = function(V) 
    Toggles.AutoDaily = V
    if V then
        task.spawn(function()
            while Toggles.AutoDaily do
                pcall(function() 
                    game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("DailyRewardClaimStars") 
                end)
                task.wait(5)
            end
        end)
    end
end })

HuntTab:CreateToggle({ Name = "Claim All Playtime Gifts", CurrentValue = false, Flag = "AutoGifts", Callback = function(V) 
    Toggles.OpenGifts = V 
    if V then task.spawn(function() while Toggles.OpenGifts do pcall(function() for i = 1, 15 do game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteFunction:InvokeServer("ClaimPlaytime", i) task.wait(0.2) end end) task.wait(5) end end) end
end })
HuntTab:CreateToggle({ Name = "Use Mystery Box", CurrentValue = false, Flag = "UseMystery", Callback = function(V) Toggles.UseMystery = V end })
HuntTab:CreateToggle({ Name = "Use OG Mystery Box", CurrentValue = false, Flag = "UseOGMystery", Callback = function(V) Toggles.UseOGMystery = V end })
HuntTab:CreateToggle({ Name = "Use Fall Mystery Box", CurrentValue = false, Flag = "UseFallMystery", Callback = function(V) Toggles.UseFallMystery = V end })
HuntTab:CreateToggle({ Name = "Use Anniversary Giftbox", CurrentValue = false, Flag = "UseAnniGift", Callback = function(V) Toggles.UseAnniGift = V end })
HuntTab:CreateToggle({ Name = "Use Mythic Mystery Box", CurrentValue = false, Flag = "UseMythicMystery", Callback = function(V) Toggles.UseMythicMystery = V end })
HuntTab:CreateToggle({ Name = "Use Void Mystery Box", CurrentValue = false, Flag = "UseVoidMystery", Callback = function(V) Toggles.UseVoidMystery = V end })
HuntTab:CreateToggle({ Name = "Use Infinity Mystery Box", CurrentValue = false, Flag = "UseInfMystery", Callback = function(V) Toggles.UseInfMystery = V end })

HuntTab:CreateSection("📦 Crates")
HuntTab:CreateToggle({ Name = "Use Wooden Crate", CurrentValue = false, Flag = "UseWoodCrate", Callback = function(V) Toggles.UseWoodCrate = V end })
HuntTab:CreateToggle({ Name = "Use Classic Crate", CurrentValue = false, Flag = "UseClassicCrate", Callback = function(V) Toggles.UseClassicCrate = V end })
HuntTab:CreateToggle({ Name = "Use Steel Crate", CurrentValue = false, Flag = "UseSteelCrate", Callback = function(V) Toggles.UseSteelCrate = V end })
HuntTab:CreateToggle({ Name = "Use Golden Crate", CurrentValue = false, Flag = "UseGoldCrate", Callback = function(V) Toggles.UseGoldCrate = V end })
HuntTab:CreateToggle({ Name = "Use Mystery Crate", CurrentValue = false, Flag = "UseMysteryCrate", Callback = function(V) Toggles.UseMysteryCrate = V end })
HuntTab:CreateToggle({ Name = "Use Void Mystery Crate", CurrentValue = false, Flag = "UseVoidMysteryCrate", Callback = function(V) Toggles.UseVoidMysteryCrate = V end })

local giftList = {
    UseMystery = "Mystery Box", UseOGMystery = "OG Mystery Box", UseFallMystery = "Fall Mystery Box",
    UseAnniGift = "Anniversary Giftbox", UseMythicMystery = "Mythic Mystery Box", UseVoidMystery = "Void Mystery Box",
    UseInfMystery = "Infinity Mystery Box", UseWoodCrate = "Wooden Crate", UseClassicCrate = "Classic Crate",
    UseSteelCrate = "Steel Crate", UseGoldCrate = "Golden Crate", UseMysteryCrate = "Mystery Crate",
    UseVoidMysteryCrate = "Void Mystery Crate"
}

task.spawn(function()
    while task.wait(3) do
        for flag, giftName in pairs(giftList) do
            if Toggles[flag] then
                pcall(function() game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("UseGift", giftName, 1) end)
            end
        end
    end
end)

task.wait() -- UI renderer yield
-- ==========================================
-- ✨ 5. ENCHANTING (Advanced Multi-Slot Auto-Enchanter)
-- ==========================================

-- Enchant Variables
local autoRollReg1 = false
local autoRollReg2 = false
local autoRollShiny1 = false
local autoRollShiny2 = false
local autoRollSecret1 = false
local autoRollSecret2 = false
local autoRollSuper1 = false
local autoRollSuper2 = false
local currencySelected = "Gems"
local activePetID = ""

-- Target Enchants Database
local enchantDatabase = {
    -- Looter
    ["Looter I"]   = {Id = "looter", Level = 1},
    ["Looter II"]  = {Id = "looter", Level = 2},
    ["Looter III"] = {Id = "looter", Level = 3},
    ["Looter IV"]  = {Id = "looter", Level = 4},
    ["Looter V"]   = {Id = "looter", Level = 5},
    
    -- Bubbler
    ["Bubbler I"]   = {Id = "bubbler", Level = 1},
    ["Bubbler II"]  = {Id = "bubbler", Level = 2},
    ["Bubbler III"] = {Id = "bubbler", Level = 3},
    ["Bubbler IV"]  = {Id = "bubbler", Level = 4},
    ["Bubbler V"]   = {Id = "bubbler", Level = 5},

    -- Gleaming
    ["Gleaming I"]   = {Id = "gleaming", Level = 1},
    ["Gleaming II"]  = {Id = "gleaming", Level = 2},
    ["Gleaming III"] = {Id = "gleaming", Level = 3},
    ["Gleaming IV"]  = {Id = "gleaming", Level = 4},
    ["Gleaming V"]   = {Id = "gleaming", Level = 5},

    -- Team Up
    ["Team Up I"]   = {Id = "team up", Level = 1},
    ["Team Up II"]  = {Id = "team up", Level = 2},
    ["Team Up III"] = {Id = "team up", Level = 3},
    ["Team Up IV"]  = {Id = "team up", Level = 4},
    ["Team Up V"]   = {Id = "team up", Level = 5},
    
    -- Special Enchants (Tier III & Secret)
    ["High Roller"]  = {Id = "high roller", Level = 1},
    ["Infinity"]     = {Id = "infinity", Level = 1},
    ["Magnetism"]    = {Id = "magnetism", Level = 1},

    -- Secret Enchants (Secret Only)
    ["Shiny Seeker"]  = {Id = "shiny seeker", Level = 1},
    ["Secret Hunter"] = {Id = "secret hunter", Level = 1},
    ["Ultra Roller"]  = {Id = "ultra roller", Level = 1},
    ["Determination"] = {Id = "determination", Level = 1},

    -- Super Legendary Enchants
    ["Shiny Blessing"]    = {Id = "shiny blessing", Level = 1},
    ["Infinity Blessing"] = {Id = "infinity blessing", Level = 1},
    ["Mythic Blessing"]   = {Id = "mythic blessing", Level = 1},
    ["Burst Blessing"]    = {Id = "burst blessing", Level = 1},
    ["Bubble Machine"]    = {Id = "bubble machine", Level = 1},
    ["Duplication"]       = {Id = "duplication", Level = 1},
    ["Hatch Blessing"]    = {Id = "hatch blessing", Level = 1},
    ["Luck Boost"]        = {Id = "luck boost", Level = 1}
}

-- Ordered list for the Dropdown UI
local enchantNames = {
    "--- Looter ---",
    "Looter I", "Looter II", "Looter III", "Looter IV", "Looter V",
    "--- Bubbler ---",
    "Bubbler I", "Bubbler II", "Bubbler III", "Bubbler IV", "Bubbler V",
    "--- Gleaming ---",
    "Gleaming I", "Gleaming II", "Gleaming III", "Gleaming IV", "Gleaming V",
    "--- Team Up ---",
    "Team Up I", "Team Up II", "Team Up III", "Team Up IV", "Team Up V",
    "--- Special & Secret Enchants ---",
    "High Roller", "Infinity", "Magnetism", "Shiny Seeker", "Secret Hunter", "Ultra Roller", "Determination",
    "--- Super Legendary ---",
    "Shiny Blessing", "Infinity Blessing", "Mythic Blessing", "Burst Blessing", "Bubble Machine", "Duplication", "Hatch Blessing", "Luck Boost"
}

local targetReg1 = enchantDatabase["Looter V"]
local targetReg2 = enchantDatabase["Looter V"]
local targetShiny1 = enchantDatabase["Looter V"]
local targetShiny2 = enchantDatabase["Looter V"]
local targetSecret1 = enchantDatabase["Shiny Seeker"]
local targetSecret2 = enchantDatabase["Shiny Seeker"]
local targetSuper1 = enchantDatabase["Shiny Blessing"]
local targetSuper2 = enchantDatabase["Shiny Blessing"]

local enchantRemote = game:GetService("ReplicatedStorage"):FindFirstChild("RemoteFunction", true)

-- Universal Hit Scanner
local function checkHit(replyData, target)
    if type(replyData) == "table" then
        for _, enchant in pairs(replyData) do
            if type(enchant) == "table" and enchant.Id then
                local rolledId = tostring(enchant.Id):lower()
                local rolledLevel = tonumber(enchant.Level)
                if rolledId == target.Id and rolledLevel == target.Level then
                    return true 
                end
            end
        end
    end
    return false
end

-- Non-blocking Pet ID Grabber (namecall hook)
local PetIDLabel = nil -- forward declaration, set after UI creation
pcall(function()
    local mt = getrawmetatable(game)
    local oldNamecall = mt.__namecall
    setreadonly(mt, false)

    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = {...}
        
        if not checkcaller() and method == "InvokeServer" and tostring(self) == "RemoteFunction" then
            if type(args[1]) == "string" and (args[1] == "RerollEnchants" or args[1] == "RollEnchants") and args[2] then
                local pulledID = tostring(args[2])
                if activePetID ~= pulledID then
                    activePetID = pulledID
                    task.spawn(function()
                        pcall(function()
                            if PetIDLabel then
                                PetIDLabel:Set("🐾 Locked Pet ID: " .. activePetID)
                            end
                        end)
                    end)
                end
            end
        end
        
        return oldNamecall(self, ...)
    end)
    setreadonly(mt, true)
end)

-- ---- UI ----
PetIDLabel = EnchantTab:CreateLabel("🐾 Locked Pet ID: None (Roll manually to lock!)")

EnchantTab:CreateSection("0. Quick Navigation")
EnchantTab:CreateButton({
   Name = "📍 Teleport to Enchanter",
   Callback = function()
       pcall(function()
           if player and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
               player.Character.HumanoidRootPart.CFrame = CFrame.new(-62.12, 10148.72, 53.12)
           end
       end)
   end,
})

EnchantTab:CreateSection("1. Select Currency")
EnchantTab:CreateDropdown({
   Name = "Currency Type",
   Options = {"Gems", "Reroll Orbs", "Shadow Crystal"},
   CurrentOption = {"Gems"},
   MultipleOptions = false,
   Flag = "EnchCurrencyDrop",
   Callback = function(Option)
       currencySelected = Option[1]
   end,
})

-- REGULAR PETS
EnchantTab:CreateSection("2. Regular Pets (Glitch: 2 Slots)")
EnchantTab:CreateLabel("⚠️ Make sure Slot 1 is locked on the bottom or enchant won't save!")

EnchantTab:CreateDropdown({
   Name = "Target Enchant (Slot 1)",
   Options = enchantNames,
   CurrentOption = {"Looter V"},
   MultipleOptions = false,
   Flag = "TargetReg1Drop",
   Callback = function(Option)
       local selection = Option[1]
       if enchantDatabase[selection] then targetReg1 = enchantDatabase[selection] end
   end,
})

EnchantTab:CreateToggle({
   Name = "🔒 Auto Roll Slot 1",
   CurrentValue = false,
   Flag = "AutoReg1Toggle",
   Callback = function(Value)
       autoRollReg1 = Value
       if autoRollReg1 then
           if activePetID == "" then
               Rayfield:Notify({Title = "Error", Content = "Please roll the pet manually ONCE first!", Duration = 4})
               Window.Flags["AutoReg1Toggle"]:Set(false)
               return
           end
           spawn(function()
               while autoRollReg1 do
                   if enchantRemote then
                       local reply = {enchantRemote:InvokeServer("RerollEnchants", activePetID, currencySelected, 1)}
                       if reply[2] and checkHit(reply[2], targetReg1) then
                           Rayfield:Notify({Title = "Splash Hub", Content = "Slot 1 Locked In!", Duration = 5})
                           autoRollReg1 = false
                           Window.Flags["AutoReg1Toggle"]:Set(false)
                       end
                   end
                   task.wait(0.5)
               end
           end)
       end
   end,
})

EnchantTab:CreateDropdown({
   Name = "Target Enchant (Slot 2)",
   Options = enchantNames,
   CurrentOption = {"Looter V"},
   MultipleOptions = false,
   Flag = "TargetReg2Drop",
   Callback = function(Option)
       local selection = Option[1]
       if enchantDatabase[selection] then targetReg2 = enchantDatabase[selection] end
   end,
})

EnchantTab:CreateToggle({
   Name = "🔒 Auto Roll Slot 2",
   CurrentValue = false,
   Flag = "AutoReg2Toggle",
   Callback = function(Value)
       autoRollReg2 = Value
       if autoRollReg2 then
           if activePetID == "" then
               Rayfield:Notify({Title = "Error", Content = "Please roll the pet manually ONCE first!", Duration = 4})
               Window.Flags["AutoReg2Toggle"]:Set(false)
               return
           end
           spawn(function()
               while autoRollReg2 do
                   if enchantRemote then
                       local reply = {enchantRemote:InvokeServer("RerollEnchants", activePetID, currencySelected, 2)}
                       if reply[2] and checkHit(reply[2], targetReg2) then
                           Rayfield:Notify({Title = "Splash Hub", Content = "Slot 2 Locked In!", Duration = 5})
                           autoRollReg2 = false
                           Window.Flags["AutoReg2Toggle"]:Set(false)
                       end
                   end
                   task.wait(0.5)
               end
           end)
       end
   end,
})

-- SHINY PETS
EnchantTab:CreateSection("3. Shiny Pets")

EnchantTab:CreateDropdown({
   Name = "Target Enchant (Slot 1)",
   Options = enchantNames,
   CurrentOption = {"Looter V"},
   MultipleOptions = false,
   Flag = "TargetShiny1Drop",
   Callback = function(Option)
       local selection = Option[1]
       if enchantDatabase[selection] then targetShiny1 = enchantDatabase[selection] end
   end,
})

EnchantTab:CreateToggle({
   Name = "🔒 Auto Roll Slot 1",
   CurrentValue = false,
   Flag = "AutoShiny1Toggle",
   Callback = function(Value)
       autoRollShiny1 = Value
       if autoRollShiny1 then
           if activePetID == "" then
               Rayfield:Notify({Title = "Error", Content = "Please roll the pet manually ONCE first!", Duration = 4})
               Window.Flags["AutoShiny1Toggle"]:Set(false)
               return
           end
           spawn(function()
               while autoRollShiny1 do
                   if enchantRemote then
                       local reply = {enchantRemote:InvokeServer("RerollEnchants", activePetID, currencySelected, 1)}
                       if reply[2] and checkHit(reply[2], targetShiny1) then
                           Rayfield:Notify({Title = "Splash Hub", Content = "Shiny Slot 1 Locked In!", Duration = 5})
                           autoRollShiny1 = false
                           Window.Flags["AutoShiny1Toggle"]:Set(false)
                       end
                   end
                   task.wait(0.5)
               end
           end)
       end
   end,
})

EnchantTab:CreateDropdown({
   Name = "Target Enchant (Slot 2)",
   Options = enchantNames,
   CurrentOption = {"Looter V"},
   MultipleOptions = false,
   Flag = "TargetShiny2Drop",
   Callback = function(Option)
       local selection = Option[1]
       if enchantDatabase[selection] then targetShiny2 = enchantDatabase[selection] end
   end,
})

EnchantTab:CreateToggle({
   Name = "🔒 Auto Roll Slot 2",
   CurrentValue = false,
   Flag = "AutoShiny2Toggle",
   Callback = function(Value)
       autoRollShiny2 = Value
       if autoRollShiny2 then
           if activePetID == "" then
               Rayfield:Notify({Title = "Error", Content = "Please roll the pet manually ONCE first!", Duration = 4})
               Window.Flags["AutoShiny2Toggle"]:Set(false)
               return
           end
           spawn(function()
               while autoRollShiny2 do
                   if enchantRemote then
                       local reply = {enchantRemote:InvokeServer("RerollEnchants", activePetID, currencySelected, 2)}
                       if reply[2] and checkHit(reply[2], targetShiny2) then
                           Rayfield:Notify({Title = "Splash Hub", Content = "Shiny Slot 2 Locked In!", Duration = 5})
                           autoRollShiny2 = false
                           Window.Flags["AutoShiny2Toggle"]:Set(false)
                       end
                   end
                   task.wait(0.5)
               end
           end)
       end
   end,
})

-- TIER 3 LEGENDARY & SECRET PETS
EnchantTab:CreateSection("4. Tier III & Secret Pets")

EnchantTab:CreateDropdown({
   Name = "Target Enchant (Slot 1)",
   Options = enchantNames,
   CurrentOption = {"Shiny Seeker"},
   MultipleOptions = false,
   Flag = "TargetSecret1Drop",
   Callback = function(Option)
       local selection = Option[1]
       if enchantDatabase[selection] then targetSecret1 = enchantDatabase[selection] end
   end,
})

EnchantTab:CreateToggle({
   Name = "🔒 Auto Roll Slot 1",
   CurrentValue = false,
   Flag = "AutoSecret1Toggle",
   Callback = function(Value)
       autoRollSecret1 = Value
       if autoRollSecret1 then
           if activePetID == "" then
               Rayfield:Notify({Title = "Error", Content = "Please roll the pet manually ONCE first!", Duration = 4})
               Window.Flags["AutoSecret1Toggle"]:Set(false)
               return
           end
           spawn(function()
               while autoRollSecret1 do
                   if enchantRemote then
                       local reply = {enchantRemote:InvokeServer("RerollEnchants", activePetID, currencySelected, 1)}
                       if reply[2] and checkHit(reply[2], targetSecret1) then
                           Rayfield:Notify({Title = "Splash Hub", Content = "Tier III/Secret Slot 1 Locked In!", Duration = 5})
                           autoRollSecret1 = false
                           Window.Flags["AutoSecret1Toggle"]:Set(false)
                       end
                   end
                   task.wait(0.5)
               end
           end)
       end
   end,
})

EnchantTab:CreateDropdown({
   Name = "Target Enchant (Slot 2)",
   Options = enchantNames,
   CurrentOption = {"Shiny Seeker"},
   MultipleOptions = false,
   Flag = "TargetSecret2Drop",
   Callback = function(Option)
       local selection = Option[1]
       if enchantDatabase[selection] then targetSecret2 = enchantDatabase[selection] end
   end,
})

EnchantTab:CreateToggle({
   Name = "🔒 Auto Roll Slot 2",
   CurrentValue = false,
   Flag = "AutoSecret2Toggle",
   Callback = function(Value)
       autoRollSecret2 = Value
       if autoRollSecret2 then
           if activePetID == "" then
               Rayfield:Notify({Title = "Error", Content = "Please roll the pet manually ONCE first!", Duration = 4})
               Window.Flags["AutoSecret2Toggle"]:Set(false)
               return
           end
           spawn(function()
               while autoRollSecret2 do
                   if enchantRemote then
                       local reply = {enchantRemote:InvokeServer("RerollEnchants", activePetID, currencySelected, 2)}
                       if reply[2] and checkHit(reply[2], targetSecret2) then
                           Rayfield:Notify({Title = "Splash Hub", Content = "Tier III/Secret Slot 2 Locked In!", Duration = 5})
                           autoRollSecret2 = false
                           Window.Flags["AutoSecret2Toggle"]:Set(false)
                       end
                   end
                   task.wait(0.5)
               end
           end)
       end
   end,
})

-- SUPER LEGENDARY PETS
EnchantTab:CreateSection("5. Super Legendary Pets")

EnchantTab:CreateDropdown({
   Name = "Target Enchant (Slot 1)",
   Options = enchantNames,
   CurrentOption = {"Shiny Blessing"},
   MultipleOptions = false,
   Flag = "TargetSuper1Drop",
   Callback = function(Option)
       local selection = Option[1]
       if enchantDatabase[selection] then targetSuper1 = enchantDatabase[selection] end
   end,
})

EnchantTab:CreateToggle({
   Name = "🔒 Auto Roll Slot 1",
   CurrentValue = false,
   Flag = "AutoSuper1Toggle",
   Callback = function(Value)
       autoRollSuper1 = Value
       if autoRollSuper1 then
           if activePetID == "" then
               Rayfield:Notify({Title = "Error", Content = "Please roll the pet manually ONCE first!", Duration = 4})
               Window.Flags["AutoSuper1Toggle"]:Set(false)
               return
           end
           spawn(function()
               while autoRollSuper1 do
                   if enchantRemote then
                       local reply = {enchantRemote:InvokeServer("RerollEnchants", activePetID, currencySelected, 1)}
                       if reply[2] and checkHit(reply[2], targetSuper1) then
                           Rayfield:Notify({Title = "Splash Hub", Content = "Super Legendary Slot 1 Locked In!", Duration = 5})
                           autoRollSuper1 = false
                           Window.Flags["AutoSuper1Toggle"]:Set(false)
                       end
                   end
                   task.wait(0.5)
               end
           end)
       end
   end,
})

EnchantTab:CreateDropdown({
   Name = "Target Enchant (Slot 2)",
   Options = enchantNames,
   CurrentOption = {"Shiny Blessing"},
   MultipleOptions = false,
   Flag = "TargetSuper2Drop",
   Callback = function(Option)
       local selection = Option[1]
       if enchantDatabase[selection] then targetSuper2 = enchantDatabase[selection] end
   end,
})

EnchantTab:CreateToggle({
   Name = "🔒 Auto Roll Slot 2",
   CurrentValue = false,
   Flag = "AutoSuper2Toggle",
   Callback = function(Value)
       autoRollSuper2 = Value
       if autoRollSuper2 then
           if activePetID == "" then
               Rayfield:Notify({Title = "Error", Content = "Please roll the pet manually ONCE first!", Duration = 4})
               Window.Flags["AutoSuper2Toggle"]:Set(false)
               return
           end
           spawn(function()
               while autoRollSuper2 do
                   if enchantRemote then
                       local reply = {enchantRemote:InvokeServer("RerollEnchants", activePetID, currencySelected, 2)}
                       if reply[2] and checkHit(reply[2], targetSuper2) then
                           Rayfield:Notify({Title = "Splash Hub", Content = "Super Legendary Slot 2 Locked In!", Duration = 5})
                           autoRollSuper2 = false
                           Window.Flags["AutoSuper2Toggle"]:Set(false)
                       end
                   end
                   task.wait(0.5)
               end
           end)
       end
   end,
})

EnchantTab:CreateButton({ Name = "Teleport to Void", Callback = function() 
    pcall(function() game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("Teleport", "Workspace.Worlds.The Overworld.Islands.The Void.Island.Portal.Spawn") end) 
end })

task.wait() -- UI renderer yield
-- ==========================================
-- 📜 6. QUESTS
-- ==========================================
QuestTab:CreateToggle({ Name = "Auto Claim Quests", CurrentValue = false, Flag = "AQuest", Callback = function(V) Toggles.Quests = V end })

QuestTab:CreateToggle({ Name = "Auto Claim Season Pass", CurrentValue = false, Flag = "AutoSeason", Callback = function(V) Toggles.Season = V end })
task.spawn(function()
    while task.wait(5) do
        if Toggles.Season then
            pcall(function() game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("ClaimSeason") end)
        end
    end
end)

QuestTab:CreateSection("Competitive Season")
QuestTab:CreateToggle({ Name = "Auto Claim Competitive Prizes", CurrentValue = false, Flag = "AutoCompClaim", Callback = function(V)
    Toggles.AutoCompClaim = V
    if V then
        task.spawn(function()
            while Toggles.AutoCompClaim do
                pcall(function()
                    for rewardIdx = 1, 20 do
                        for optIdx = 1, 3 do
                            game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("ClaimCompetitivePrize", rewardIdx, optIdx)
                        end
                    end
                end)
                task.wait(30)
            end
        end)
    end
end })

QuestTab:CreateToggle({ Name = "Auto Reroll Competitive Tasks", CurrentValue = false, Flag = "AutoCompReroll", Callback = function(V)
    Toggles.AutoCompReroll = V
    if V then
        task.spawn(function()
            while Toggles.AutoCompReroll do
                pcall(function()
                    for taskIdx = 1, 6 do
                        game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("CompetitiveReroll", taskIdx)
                        task.wait(0.5)
                    end
                end)
                task.wait(60)
            end
        end)
    end
end })

QuestTab:CreateSection("Misc Rewards")
QuestTab:CreateButton({ Name = "Claim Benefits (Group/Star Codes)", Callback = function()
    pcall(function()
        game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("ClaimBenefits")
    end)
    Rayfield:Notify({ Title = "Benefits", Content = "Claimed all available benefits!", Duration = 3 })
end })

QuestTab:CreateToggle({ Name = "Auto Gem Genie", CurrentValue = false, Flag = "AGenie", Callback = function(V) Toggles.Genie = V end })

task.wait() -- UI renderer yield
task.wait() -- UI renderer yield
-- ==========================================
-- 🕹️ 8. MINIGAMES
-- ==========================================
ActivityTab:CreateSection("🃏 Pet Match")
local pmDifficulty = "Easy"
ActivityTab:CreateDropdown({ Name = "Pet Match Difficulty", Options = {"Easy", "Medium", "Hard", "Insane"}, CurrentOption = {"Easy"}, Flag = "PMDiff", Callback = function(O) pmDifficulty = O[1] end })
ActivityTab:CreateToggle({ Name = "Auto Pet Match", CurrentValue = false, Flag = "AutoPetMatch", Callback = function(V) 
    Toggles.AutoPetMatch = V
    if V then
        task.spawn(function()
            while Toggles.AutoPetMatch do
                pcall(function()
                    local rsEvent = game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent
                    rsEvent:FireServer("StartMinigame", "Pet Match", string.lower(pmDifficulty))
                    task.wait(0.5)
                    rsEvent:FireServer("FinishMinigame")
                    task.wait(0.5)
                    rsEvent:FireServer("SkipMinigameCooldown", "Pet Match")
                end)
                task.wait(1)
            end
        end)
    end
end })

ActivityTab:CreateSection("🛒 Cart Escape")
local ceDifficulty = "Easy"
ActivityTab:CreateDropdown({ Name = "Cart Escape Difficulty", Options = {"Easy", "Medium", "Hard", "Insane"}, CurrentOption = {"Easy"}, Flag = "CEDiff", Callback = function(O) ceDifficulty = O[1] end })
ActivityTab:CreateToggle({ Name = "Auto Cart Escape", CurrentValue = false, Flag = "AutoCartEscape", Callback = function(V) 
    Toggles.AutoCartEscape = V
    if V then
        task.spawn(function()
            while Toggles.AutoCartEscape do
                pcall(function()
                    local rsEvent = game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent
                    rsEvent:FireServer("StartMinigame", "Cart Escape", string.lower(ceDifficulty))
                    task.wait(0.5)
                    rsEvent:FireServer("FinishMinigame")
                    task.wait(0.5)
                    rsEvent:FireServer("SkipMinigameCooldown", "Cart Escape")
                end)
                task.wait(1)
            end
        end)
    end
end })

ActivityTab:CreateSection("🤖 Robot Claw")
local rcDifficulty = "Easy"
ActivityTab:CreateDropdown({ Name = "Robot Claw Difficulty", Options = {"Easy", "Medium", "Hard", "Insane"}, CurrentOption = {"Easy"}, Flag = "RCDiff", Callback = function(O) rcDifficulty = O[1] end })
ActivityTab:CreateToggle({ Name = "Auto Robot Claw", CurrentValue = false, Flag = "AutoRobotClaw", Callback = function(V) 
    Toggles.AutoRobotClaw = V
    if V then
        task.spawn(function()
            while Toggles.AutoRobotClaw do
                pcall(function()
                    local rsEvent = game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent
                    rsEvent:FireServer("StartMinigame", "Robot Claw", string.lower(rcDifficulty))
                    task.wait(1.5) 
                    local grabbed = {}
                    for _, obj in pairs(workspace:GetDescendants()) do
                        if obj.Name:match("%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x") and not grabbed[obj.Name] then
                            rsEvent:FireServer("GrabMinigameItem", obj.Name)
                            grabbed[obj.Name] = true
                        end
                    end
                    for _, obj in pairs(player.PlayerGui:GetDescendants()) do
                        if obj.Name:match("%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x") and not grabbed[obj.Name] then
                            rsEvent:FireServer("GrabMinigameItem", obj.Name)
                            grabbed[obj.Name] = true
                        end
                    end
                    task.wait(0.5)
                    rsEvent:FireServer("FinishMinigame")
                    task.wait(0.5)
                    rsEvent:FireServer("SkipMinigameCooldown", "Robot Claw")
                end)
                task.wait(1)
            end
        end)
    end
end })

ActivityTab:CreateSection("🎮 Other Minigames")
local mgames = {"Maze", "Color Match", "Block Drop", "Flappy Pet", "Hyper Darts", "Egg Darts"}
for _, gameName in ipairs(mgames) do 
    local flagKey = "MG" .. gameName:gsub(" ", "")
    Toggles[flagKey] = false
    ActivityTab:CreateToggle({ 
        Name = "Auto " .. gameName, 
        CurrentValue = false, 
        Flag = flagKey, 
        Callback = function(V)
            Toggles[flagKey] = V
            if V then
                task.spawn(function()
                    while Toggles[flagKey] do
                        pcall(function()
                            local rsEvent = game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent
                            rsEvent:FireServer("StartMinigame", gameName, "easy")
                            task.wait(0.5)
                            rsEvent:FireServer("FinishMinigame")
                            task.wait(0.5)
                            rsEvent:FireServer("SkipMinigameCooldown", gameName)
                        end)
                        task.wait(1)
                    end
                end)
            end
        end 
    }) 
end

ActivityTab:CreateSection("🏃 Obby Queue")
ActivityTab:CreateLabel("Priority queue. Set 1-3 (1 = first). Auto-teleports, runs obby, returns.")

local obbyData = {
    Easy =   { Cooldown = 185,  LastRun = 0, Toggle = false, Priority = 1 },
    Medium = { Cooldown = 305,  LastRun = 0, Toggle = false, Priority = 2 },
    Hard =   { Cooldown = 610,  LastRun = 0, Toggle = false, Priority = 3 },
}

-- Apply any buffered server cooldowns that arrived before obbyData was initialized
if _pendingObbyCooldowns then
    for difficulty, timestamp in pairs(_pendingObbyCooldowns) do
        if obbyData[difficulty] then
            obbyData[difficulty].LastRun = math.floor(timestamp)
        end
    end
    _pendingObbyCooldowns = nil
end

local obbyLagDelay = 2

ActivityTab:CreateToggle({ Name = "Easy Obby (3 Min CD)", CurrentValue = false, Flag = "ObbyEasy", Callback = function(V) obbyData.Easy.Toggle = V end })
ActivityTab:CreateDropdown({ Name = "Easy Priority", Options = {"1","2","3"}, CurrentOption = {"1"}, Flag = "ObbyEasyPri", Callback = function(v) obbyData.Easy.Priority = tonumber(v[1]) end })
ActivityTab:CreateToggle({ Name = "Medium Obby (5 Min CD)", CurrentValue = false, Flag = "ObbyMedium", Callback = function(V) obbyData.Medium.Toggle = V end })
ActivityTab:CreateDropdown({ Name = "Medium Priority", Options = {"1","2","3"}, CurrentOption = {"2"}, Flag = "ObbyMedPri", Callback = function(v) obbyData.Medium.Priority = tonumber(v[1]) end })
ActivityTab:CreateToggle({ Name = "Hard Obby (10 Min CD)", CurrentValue = false, Flag = "ObbyHard", Callback = function(V) obbyData.Hard.Toggle = V end })
ActivityTab:CreateDropdown({ Name = "Hard Priority", Options = {"1","2","3"}, CurrentOption = {"3"}, Flag = "ObbyHardPri", Callback = function(v) obbyData.Hard.Priority = tonumber(v[1]) end })

ActivityTab:CreateSlider({
    Name = "Lag Delay (seconds)",
    Range = {1, 5},
    Increment = 0.5,
    CurrentValue = 2,
    Suffix = "s",
    Flag = "ObbyLagDelay",
    Callback = function(Value) obbyLagDelay = Value end,
})

local obbyQueueStatusLabel = ActivityTab:CreateLabel("Queue: Idle")

local spawnLocation = "Workspace.Worlds.Seven Seas.Areas.Classic Island.HouseSpawn"

ActivityTab:CreateToggle({ Name = "Start Obby Queue", CurrentValue = false, Flag = "ObbyQueue", Callback = function(V)
    Toggles.ObbyQueue = V
    if V then
        task.spawn(function()
            local rsEvent = game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent
            
            while Toggles.ObbyQueue do
                if getgenv().CurrentZone == "Plaza" then
                    obbyQueueStatusLabel:Set("Queue: Paused (In Plaza)")
                    task.wait(5)
                    continue
                end
                
                -- Skip obby cycle if gem farming is active
                if getgenv().GemFarming then
                    obbyQueueStatusLabel:Set("Queue: Paused (Gem Farming)")
                    task.wait(5)
                    continue
                end
                
                -- Skip obby cycle if summer features are actively teleporting
                if getgenv().IsClaimingChest or getgenv().IsClaimingInfChest or getgenv().IsHatchingPhase or getgenv().IsDoingQuest then
                    obbyQueueStatusLabel:Set("Queue: Paused (Summer Active)")
                    task.wait(5)
                    continue
                end
                
                local currentTime = os.time()
                local readyObbies = {}
                
                for name, data in pairs(obbyData) do
                    if data.Toggle and (currentTime - data.LastRun >= data.Cooldown) then
                        table.insert(readyObbies, { Name = name, Data = data })
                    end
                end
                
                if #readyObbies > 0 then
                    table.sort(readyObbies, function(a, b)
                        return a.Data.Priority < b.Data.Priority
                    end)
                    
                    local targetObby = readyObbies[1].Name
                    obbyQueueStatusLabel:Set("Queue: Running " .. targetObby .. " Obby...")
                    consoleLog("Doing Obby: " .. targetObby)
                    
                    local success, errorMessage = pcall(function()
                        -- 1. Save AFK position
                        local character = player.Character
                        local rootPart = character and character:FindFirstChild("HumanoidRootPart")
                        local savedPosition = nil
                        
                        if rootPart then
                            savedPosition = rootPart.CFrame
                            getgenv().ObbySavedCFrame = savedPosition
                        end
                        
                        -- 2. Teleport to obby spawn and start
                        rsEvent:FireServer("Teleport", spawnLocation)
                        task.wait(obbyLagDelay)
                        rsEvent:FireServer("StartObby", targetObby)
                        task.wait(obbyLagDelay)
                        
                        -- 3. Complete and claim (fire claim twice for reliability)
                        rsEvent:FireServer("CompleteObby")
                        task.wait(obbyLagDelay)
                        rsEvent:FireServer("ClaimObbyChest", false)
                        task.wait(obbyLagDelay)
                        rsEvent:FireServer("ClaimObbyChest", false)
                        task.wait(obbyLagDelay)
                        
                        -- 4. Return to AFK position (re-get character since it may have respawned)
                        if savedPosition then
                            rsEvent:FireServer("Teleport", spawnLocation)
                            task.wait(obbyLagDelay)
                            local freshChar = player.Character
                            local freshRoot = freshChar and freshChar:FindFirstChild("HumanoidRootPart")
                            if freshRoot then
                                freshRoot.CFrame = savedPosition
                            end
                        else
                            rsEvent:FireServer("Teleport", spawnLocation)
                        end
                        getgenv().ObbySavedCFrame = nil
                    end)
                    
                    obbyData[targetObby].LastRun = os.time()
                    
                    if success then
                        obbyQueueStatusLabel:Set("Queue: Completed " .. targetObby .. ". Waiting...")
                    else
                        obbyQueueStatusLabel:Set("Queue: Error on " .. targetObby .. ". Retrying...")
                    end
                else
                    -- Show time until next available obby
                    local minWait = math.huge
                    for key, data in pairs(obbyData) do
                        if data.Toggle then
                            local remaining = data.Cooldown - (currentTime - data.LastRun)
                            if remaining > 0 and remaining < minWait then
                                minWait = remaining
                            end
                        end
                    end
                    if minWait < math.huge then
                        obbyQueueStatusLabel:Set("Queue: All on cooldown. Next in ~" .. math.ceil(minWait) .. "s")
                    else
                        obbyQueueStatusLabel:Set("Queue: No obbys enabled.")
                    end
                end
                
                task.wait(1)
            end
            obbyQueueStatusLabel:Set("Queue: Stopped")
        end)
    end
end })

ActivityTab:CreateSection("Guess That Pet")
ActivityTab:CreateToggle({ Name = "Auto Guess That Pet", CurrentValue = false, Flag = "AutoGuessPet", Callback = function(V)
    Toggles.AutoGuessPet = V
    if V then
        task.spawn(function()
            while Toggles.AutoGuessPet do
                pcall(function()
                    local rf = game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteFunction
                    local state = rf:InvokeServer("GetGuessPetState")
                    if state and state.State == "Guessing" and state.CurrentPet then
                        game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("GuessPet", state.CurrentPet)
                    end
                end)
                task.wait(2)
            end
        end)
    end
end })

task.wait() -- UI renderer yield
-- ==========================================
-- 🛒 9. SHOPS (All Shops)
-- ==========================================
ShopTab:CreateSection("Standard Shop")
-- BGS Market Tracker (Integrated — No In-Game Notifications)
local ShopConfig = {
    alien = {id="alien-shop", name="👽 Alien Shop", slots=3, buy={}, RerollOn=false, MaxRerolls=1},
    blackmarket = {id="shard-shop", name="🔮 Blackmarket", slots=3, buy={}, RerollOn=false, MaxRerolls=1},
    dice = {id="dice-shop", name="🎲 Dice Merchant", slots=3, buy={}, RerollOn=false, MaxRerolls=1},
    shadow = {id="shadow-shop", name="🌑 Shadow Shop", slots=3, buy={}, RerollOn=false, MaxRerolls=1},
    traveling = {id="traveling-merchant", name="🎒 Traveling Merchant", slots=3, buy={}, RerollOn=false, MaxRerolls=1},
    floral = {id="flower-shop", name="🌸 Floral Shop", slots=6, buy={}, RerollOn=false, MaxRerolls=1},
    fishing = {id="fishing-shop", name="🎣 Fishing Shop", slots=3, buy={}, RerollOn=false, MaxRerolls=1},
    summer = {id="summer-shop", name="☀️ Summer Shop", slots=8, buy={}, RerollOn=false, MaxRerolls=1},
    tropical = {id="tropical-shop", name="🌴 Tropical Shop", slots=6, buy={}, RerollOn=false, MaxRerolls=1}
}

local ShopOrder = {"alien", "blackmarket", "dice", "shadow", "traveling", "floral", "fishing", "summer", "tropical"}

local function buyShopItem(shopId, slotNum)
    local rsEvent = game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent
    for i = 1, 2 do
        pcall(function() rsEvent:FireServer("BuyShopItem", shopId, slotNum, true) end)
        task.wait(0.1)
    end
end

local function rerollShop(shopId)
    local rsEvent = game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent
    pcall(function() rsEvent:FireServer("ShopFreeReroll", shopId) end)
end

ShopTab:CreateSection("📊 Market Automation")
local autoBuyActive = false
ShopTab:CreateToggle({
   Name = "START AUTO-BUY & REROLL",
   CurrentValue = false,
   Flag = "MarketMasterToggle",
   Callback = function(Value) autoBuyActive = Value end,
})
local LogLabel = ShopTab:CreateLabel("Last Action: Waiting for shop refresh...")

for _, key in ipairs(ShopOrder) do
    local config = ShopConfig[key]
    ShopTab:CreateSection(config.name .. " (" .. config.slots .. " Slots)")
    for i = 1, config.slots do
        ShopTab:CreateToggle({Name = "Buy Slot " .. i, Flag = key.."BuyS"..i, Callback = function(v) config.buy[i] = v end})
    end
    ShopTab:CreateToggle({Name = "Enable Rerolls", Flag = key.."RerollOn", Callback = function(v) config.RerollOn = v end})
    ShopTab:CreateSlider({Name = "Max Rerolls", Range = {1, 5}, Increment = 1, CurrentValue = 1, Flag = key.."MaxRerolls", Callback = function(v) config.MaxRerolls = v end})
end

getgenv().ShopCurrentRerolls = getgenv().ShopCurrentRerolls or {}
getgenv().LastShopRefresh = getgenv().LastShopRefresh or {}

getgenv().executeSmartShopAutoBuyer = function(shopId)
    if not autoBuyActive then return end
    local conf
    for _, c in pairs(ShopConfig) do
        if c.id == shopId then conf = c; break end
    end
    if not conf then return end
    
    if getgenv().GemFarming or getgenv().GemFarmPausedShops then return end
    
    local count = 0
    for i = 1, conf.slots do
        if conf.buy[i] then
            buyShopItem(shopId, i)
            count = count + 1
            task.wait(0.3)
        end
    end
    
    if count > 0 then
        LogLabel:Set("Last Action: Bought " .. count .. " slots from " .. conf.name)
        consoleLog("🛒 " .. conf.name .. ": Bought " .. count .. " slots.")
    end
    
    local currentRerolls = getgenv().ShopCurrentRerolls[shopId] or 0
    if conf.RerollOn and currentRerolls < conf.MaxRerolls then
        getgenv().ShopCurrentRerolls[shopId] = currentRerolls + 1
        task.spawn(function()
            task.wait(2)
            LogLabel:Set("Last Action: Rerolling " .. conf.name)
            consoleLog("🔄 " .. conf.name .. ": Rerolling (" .. (currentRerolls + 1) .. "/" .. conf.MaxRerolls .. ")")
            rerollShop(shopId)
        end)
    else
        getgenv().ShopCurrentRerolls[shopId] = 0
    end
end

-- ==========================================
-- ⛩️ SHRINES & AUTO-DONATE
-- ==========================================
ShopTab:CreateSection("⛩️ Shrines & Auto-Donate")


-- Dream Shrine
ShopTab:CreateLabel("⭐ Dreamer Shrine")
local DreamShrineLabel = ShopTab:CreateLabel("Status: Waiting for data...")
ShopTab:CreateInput({ Name = "Amount to Donate (Dream Charms)", PlaceholderText = "1", RemoveTextAfterFocusLost = false, Callback = function(Text) getgenv().DreamDonationAmount = tonumber(Text) or 1 end })
ShopTab:CreateToggle({ Name = "Enable Auto Dreamer Shrine", CurrentValue = false, Flag = "AutoDream", Callback = function(Value) getgenv().AutoDreamShrine = Value end })
ShopTab:CreateButton({ Name = "Donate to Dreamer Shrine (Manual)", Callback = function()
    pcall(function()
        local Result = NetworkRemoteFunction:InvokeServer("DonateToDreamerShrine", getgenv().DreamDonationAmount)
        if Result == false then
            Rayfield:Notify({Title = "Shrine Failed", Content = "Donation rejected. Cooldown or missing resources.", Duration = 4})
        else
            Rayfield:Notify({Title = "Shrine Success", Content = "Donated to the Dreamer Shrine!", Duration = 4})
        end
    end)
end })

-- Bubble Shrine
ShopTab:CreateLabel("🫧 Bubble Shrine (Priority System)")
local BubbleShrineLabel = ShopTab:CreateLabel("Status: Waiting for data...")
local potOptions = {"None", "Speed", "Lucky", "Mythic", "Coins", "Tickets", "Summer Elixir", "Egg Elixir", "Festive Elixir", "Circus Elixir", "Valentine's Elixir"}

ShopTab:CreateDropdown({ Name = "Priority 1 Potion", Options = potOptions, CurrentOption = {"Speed"}, MultipleOptions = false, Flag = "B1Name", Callback = function(Opt) getgenv().BubPri1Name = Opt[1] end })
ShopTab:CreateSlider({ Name = "Priority 1 Tier", Range = {1, 7}, Increment = 1, CurrentValue = 7, Flag = "B1Level", Callback = function(Value) getgenv().BubPri1Level = Value end })
ShopTab:CreateDropdown({ Name = "Priority 2 Potion", Options = potOptions, CurrentOption = {"None"}, MultipleOptions = false, Flag = "B2Name", Callback = function(Opt) getgenv().BubPri2Name = Opt[1] end })
ShopTab:CreateSlider({ Name = "Priority 2 Tier", Range = {1, 7}, Increment = 1, CurrentValue = 1, Flag = "B2Level", Callback = function(Value) getgenv().BubPri2Level = Value end })
ShopTab:CreateDropdown({ Name = "Priority 3 Potion", Options = potOptions, CurrentOption = {"None"}, MultipleOptions = false, Flag = "B3Name", Callback = function(Opt) getgenv().BubPri3Name = Opt[1] end })
ShopTab:CreateSlider({ Name = "Priority 3 Tier", Range = {1, 7}, Increment = 1, CurrentValue = 1, Flag = "B3Level", Callback = function(Value) getgenv().BubPri3Level = Value end })

ShopTab:CreateInput({ Name = "Amount to Donate", PlaceholderText = "1", RemoveTextAfterFocusLost = false, Callback = function(Text) getgenv().BubbleDonationAmount = tonumber(Text) or 1 end })
ShopTab:CreateToggle({ Name = "Enable Auto Bubble Shrine", CurrentValue = false, Flag = "AutoBubble", Callback = function(Value) getgenv().AutoBubbleShrine = Value end })
ShopTab:CreateButton({ Name = "Donate to Bubble Shrine (Manual)", Callback = function()
    pcall(function()
        local payload = { Type = "Potion", Level = getgenv().BubPri1Level, Name = getgenv().BubPri1Name, Amount = getgenv().BubbleDonationAmount }
        local Result = NetworkRemoteFunction:InvokeServer("DonateToShrine", payload)
        if Result == true then
            Rayfield:Notify({Title = "Shrine Success", Content = "Donated to the Bubble Shrine!", Duration = 4})
        else
            Rayfield:Notify({Title = "Shrine Failed", Content = "Donation rejected. Cooldown or missing potions.", Duration = 4})
        end
    end)
end })

-- Shrine Cooldown UI Timers
task.spawn(function()
    while task.wait(1) do
        local currentTime = os.time()
        if getgenv().DreamShrineLastDonation > 0 then
            local dreamEnd = getgenv().DreamShrineLastDonation + 57600
            if currentTime >= dreamEnd then DreamShrineLabel:Set("Status: ⭐ Ready!")
            else
                local left = dreamEnd - currentTime
                DreamShrineLabel:Set(string.format("Status: Cooldown (%02d:%02d:%02d)", math.floor(left/3600), math.floor((left%3600)/60), left%60))
            end
        end
        if getgenv().BubbleShrineLastDonation > 0 then
            local bubbleEnd = getgenv().BubbleShrineLastDonation + 3600
            if currentTime >= bubbleEnd then BubbleShrineLabel:Set("Status: 🫧 Ready!")
            else
                local left = bubbleEnd - currentTime
                BubbleShrineLabel:Set(string.format("Status: Cooldown (%02d:%02d)", math.floor(left/60), left%60))
            end
        end
    end
end)

-- Automated Shrine Processing Loop
task.spawn(function()
    while task.wait(10) do
        local currentTime = os.time()
        -- Auto Dream Shrine
        if getgenv().AutoDreamShrine and getgenv().DreamShrineLastDonation > 0 then
            if currentTime >= getgenv().DreamShrineLastDonation + 57600 then
                pcall(function()
                    local Result = NetworkRemoteFunction:InvokeServer("DonateToDreamerShrine", getgenv().DreamDonationAmount)
                    if Result == true then
                        getgenv().DreamShrineLastDonation = currentTime
                        if getgenv().TrackShrines then
                            SendSummerWebhook("⭐ Dreamer Shrine", string.format("Auto-donated %d Dream Charms!", getgenv().DreamDonationAmount), 0xF1C40F)
                        end
                    end
                end)
            end
        end
        -- Auto Bubble Shrine (Priority)
        if getgenv().AutoBubbleShrine and getgenv().BubbleShrineLastDonation > 0 then
            if currentTime >= getgenv().BubbleShrineLastDonation + 3600 then
                local priorities = {
                    {Name = getgenv().BubPri1Name, Level = getgenv().BubPri1Level},
                    {Name = getgenv().BubPri2Name, Level = getgenv().BubPri2Level},
                    {Name = getgenv().BubPri3Name, Level = getgenv().BubPri3Level}
                }
                for _, pri in ipairs(priorities) do
                    if pri.Name ~= "None" then
                        local stock = GetPotionStock(pri.Name, pri.Level)
                        if stock >= getgenv().BubbleDonationAmount then
                            pcall(function()
                                local payload = {Type = "Potion", Level = pri.Level, Name = pri.Name, Amount = getgenv().BubbleDonationAmount}
                                local Result = NetworkRemoteFunction:InvokeServer("DonateToShrine", payload)
                                if Result == true then
                                    getgenv().BubbleShrineLastDonation = currentTime
                                    if getgenv().TrackShrines then
                                        SendSummerWebhook("🫧 Bubble Shrine", string.format("Auto-donated %d x %s (Tier %d)!", getgenv().BubbleDonationAmount, pri.Name, pri.Level), 0x3498DB)
                                    end
                                end
                            end)
                            break
                        end
                    end
                end
            end
        end
    end
end)

-- ==========================================
-- 🛒 GUM SHOP AUTO BUYER (Execution Priority)
-- ==========================================
ShopTab:CreateSection("🫧 Gum Shop")

local storagePriority = {"Epic Gum", "Ultra Gum", "Omega Gum"}
local flavorPriority = {"Pizza", "Watermelon", "Chocolate"}
local autoBuyStorageEnabled = false
local autoBuyFlavorsEnabled = false
local gumExecutionOrder = "Storage First"

ShopTab:CreateToggle({ Name = "Auto Buy Storage", CurrentValue = false, Flag = "GumAutoStorage", Callback = function(Value) autoBuyStorageEnabled = Value end })
ShopTab:CreateToggle({ Name = "Auto Buy Flavors", CurrentValue = false, Flag = "GumAutoFlavors", Callback = function(Value) autoBuyFlavorsEnabled = Value end })
ShopTab:CreateDropdown({ Name = "Execution Priority", Options = {"Storage First", "Flavors First"}, CurrentOption = {"Storage First"}, MultipleOptions = false, Flag = "GumPriority", Callback = function(Option) gumExecutionOrder = Option[1] end })

local function buyGumStorageList()
    if not autoBuyStorageEnabled then return end
    for _, itemName in ipairs(storagePriority) do
        if not autoBuyStorageEnabled then break end
        pcall(function() NetworkRemoteEvent:FireServer("GumShopPurchase", itemName) end)
        task.wait(1.5)
    end
end

local function buyGumFlavorList()
    if not autoBuyFlavorsEnabled then return end
    for _, itemName in ipairs(flavorPriority) do
        if not autoBuyFlavorsEnabled then break end
        pcall(function() NetworkRemoteEvent:FireServer("GumShopPurchase", itemName) end)
        task.wait(1.5)
    end
end

task.spawn(function()
    while task.wait(1) do
        if gumExecutionOrder == "Storage First" then
            buyGumStorageList()
            buyGumFlavorList()
        else
            buyGumFlavorList()
            buyGumStorageList()
        end
    end
end)

task.wait() -- UI renderer yield
-- ==========================================
-- 🌍 10. TELEPORTS
-- ==========================================
TeleportTab:CreateSection("World Warp")
local worldsInOrder = {
    "Spawn", "Twilight", "Outer Space", "Void",
    "Floating Island", "Minigame Paradise", "Dice Island", "Minecart Forest", "Robot Factory", 
    "Hyperwave Island", "Fisher's Island", "Blizzard Hills", "ShadowRealm"
}

local explicitPaths = {
    ["Spawn"] = "Workspace.Worlds.The Overworld.PortalSpawn", 
    ["Void"] = "Workspace.Worlds.The Overworld.Islands.The Void.Island.Portal.Spawn",
    ["Outer Space"] = "Workspace.Worlds.The Overworld.Islands.Outer Space.Island.Portal.Spawn",
    ["Floating Island"] = "Workspace.Worlds.The Overworld.Islands.Floating Island.Island.Portal.Spawn",
    ["ShadowRealm"] = "Workspace.ShadowRealm.Spawn",
    ["Minigame Paradise"] = "Workspace.Worlds.Minigame Paradise.FastTravel.Spawn",
    ["Dice Island"] = "Workspace.Worlds.Minigame Paradise.Islands.Dice Island.Island.Portal.Spawn",
    ["Minecart Forest"] = "Workspace.Worlds.Minigame Paradise.Islands.Minecart Forest.Island.Portal.Spawn",
    ["Robot Factory"] = "Workspace.Worlds.Minigame Paradise.Islands.Robot Factory.Island.Portal.Spawn",
    ["Hyperwave Island"] = "Workspace.Worlds.Minigame Paradise.Islands.Hyperwave Island.Island.Portal.Spawn",
    ["Fisher's Island"] = "Workspace.Worlds.Seven Seas.Areas.Fisher's Island.IslandTeleport.Spawn",
    ["Blizzard Hills"] = "Workspace.Worlds.Seven Seas.Areas.Blizzard Hills.IslandTeleport.Spawn"
}

-- Seven Seas sub-areas (separate section)
local sevenSeasAreas = {
    { name = "Classic Island",   path = "Workspace.Worlds.Seven Seas.Areas.Classic Island.HouseSpawn" },
    { name = "Pirate Cove",      path = "Workspace.Worlds.Seven Seas.Areas.Pirate Cove.IslandTeleport.Spawn" },
    { name = "Coral Reef",       path = "Workspace.Worlds.Seven Seas.Areas.Coral Reef.IslandTeleport.Spawn" },
    { name = "Volcanic Island",  path = "Workspace.Worlds.Seven Seas.Areas.Volcanic Island.IslandTeleport.Spawn" },
    { name = "Deep Ocean",       path = "Workspace.Worlds.Seven Seas.Areas.Deep Ocean.IslandTeleport.Spawn" },
    { name = "Frozen Tundra",    path = "Workspace.Worlds.Seven Seas.Areas.Frozen Tundra.IslandTeleport.Spawn" },
    { name = "Fisher's Island",  path = "Workspace.Worlds.Seven Seas.Areas.Fisher's Island.IslandTeleport.Spawn" },
    { name = "Blizzard Hills",   path = "Workspace.Worlds.Seven Seas.Areas.Blizzard Hills.IslandTeleport.Spawn" },
}

for _, worldName in ipairs(worldsInOrder) do 
    TeleportTab:CreateButton({ Name = "Teleport to " .. worldName, Callback = function() 
        pcall(function()
            local Event = game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent
            if explicitPaths[worldName] then
                Event:FireServer(
                    "Teleport",
                    explicitPaths[worldName]
                )
            else
                Event:FireServer(
                    "Teleport",
                    "Workspace.Worlds.The Overworld.Islands."..worldName..".Island.Portal.Spawn"
                )
            end
        end)
    end }) 
end

TeleportTab:CreateSection("🌊 Seven Seas")
TeleportTab:CreateButton({ Name = "Unlock All Seven Seas Maps", Callback = function()
    pcall(function()
        local re = game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent
        local sevenSeasMapNames = {
            "Classic Island", "Pirate Cove", "Coral Reef", "Volcanic Island",
            "Deep Ocean", "Frozen Tundra", "Fisher's Island", "Blizzard Hills"
        }
        for _, mapName in ipairs(sevenSeasMapNames) do
            re:FireServer("UnlockSevenSeasMap", mapName)
            task.wait(0.3)
        end
        -- Also try alternate remote name
        for _, mapName in ipairs(sevenSeasMapNames) do
            re:FireServer("UnlockMap", mapName)
            task.wait(0.3)
        end
    end)
    Rayfield:Notify({ Title = "Seven Seas", Content = "Unlock request sent for all maps!", Duration = 3 })
end })

for _, area in ipairs(sevenSeasAreas) do
    TeleportTab:CreateButton({ Name = "TP: " .. area.name, Callback = function()
        pcall(function()
            game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("Teleport", area.path)
        end)
    end })
end

TeleportTab:CreateSection("Plaza Teleports (State-Aware)")
TeleportTab:CreateLabel("Saves your position before teleporting. Restores it when you return.")

local function savePlazaState(plazaType)
    local stateData = { TargetState = "Plaza", PlazaType = plazaType }
    -- Only save main-world coordinates if we're NOT already in a plaza
    -- This prevents overwriting the real home coords when chaining plaza→pro
    if getgenv().CurrentZone ~= "Plaza" then
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local pos = hrp.Position
            stateData.SavedX = pos.X
            stateData.SavedY = pos.Y
            stateData.SavedZ = pos.Z
        end
    else
        -- Preserve existing saved coords from the original state file
        pcall(function()
            if isfile and isfile("SplashHub_PlazaState.json") then
                local existing = HttpService:JSONDecode(readfile("SplashHub_PlazaState.json"))
                if existing and existing.SavedX then
                    stateData.SavedX = existing.SavedX
                    stateData.SavedY = existing.SavedY
                    stateData.SavedZ = existing.SavedZ
                end
            end
        end)
    end
    pcall(function() writefile("SplashHub_PlazaState.json", HttpService:JSONEncode(stateData)) end)
    getgenv().CurrentZone = "Plaza"
end

TeleportTab:CreateButton({ Name = "Teleport to Trading Plaza", Callback = function()
    pcall(function()
        savePlazaState("plaza")
        Rayfield:Notify({ Title = "Plaza Teleport", Content = "Saving position and moving to Trading Plaza...", Duration = 5 })
        task.wait(2)
        game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("PlazaTeleport", "plaza")
    end)
end })
TeleportTab:CreateButton({ Name = "Teleport to Pro Plaza", Callback = function()
    pcall(function()
        savePlazaState("pro")
        Rayfield:Notify({ Title = "Plaza Teleport", Content = "Saving position and moving to Pro Plaza...", Duration = 5 })
        task.wait(2)
        game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("PlazaTeleport", "pro")
    end)
end })
TeleportTab:CreateButton({ Name = "Leave Plaza (Go Home)", Callback = function()
    pcall(function()
        -- Read existing state to preserve saved coords
        local stateData = { TargetState = "Main" }
        pcall(function()
            if isfile and isfile("SplashHub_PlazaState.json") then
                local existing = HttpService:JSONDecode(readfile("SplashHub_PlazaState.json"))
                if existing then
                    existing.TargetState = "Main"
                    stateData = existing
                end
            end
        end)
        pcall(function() writefile("SplashHub_PlazaState.json", HttpService:JSONEncode(stateData)) end)
        getgenv().CurrentZone = "Main"
        
        -- Always use TeleportService to go home — PlazaTeleport "home" only works from Pro Plaza
        local ts = game:GetService("TeleportService")
        local p = game:GetService("Players").LocalPlayer
        
        if psLink and psLink ~= "" then
            Rayfield:Notify({ Title = "Returning Home", Content = "Teleporting back to Private Server...", Duration = 5 })
            local extractedCode = psLink:match("privateServerLinkCode=([^&]+)")
            if extractedCode then
                pcall(function() ts:TeleportToPrivateServer(game.PlaceId, extractedCode, {p}) end)
            else
                pcall(function() ts:TeleportToPlaceInstance(game.PlaceId, psLink, p) end)
            end
        else
            Rayfield:Notify({ Title = "Returning Home", Content = "Teleporting back to a public server...", Duration = 5 })
            pcall(function() ts:Teleport(game.PlaceId, p) end)
        end
    end)
end })

TeleportTab:CreateSection("Special Areas")
TeleportTab:CreateButton({ Name = "Unlock Shadow Realm", Callback = function()
    pcall(function() game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("UnlockShadowRealm") end)
    Rayfield:Notify({ Title = "Shadow Realm", Content = "Unlock request sent!", Duration = 3 })
end })
TeleportTab:CreateButton({ Name = "Return from Shadow Realm", Callback = function()
    pcall(function() game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("Teleport", "Workspace.Worlds.The Overworld.FastTravel.Spawn") end)
end })

task.wait() -- UI renderer yield
-- ==========================================
-- 📡 11. WEBHOOK (Overhauled — LocalData Inventory)
-- ==========================================
local wh_url = ""
local wh_cool = 5

-- Safely require the LocalData module once
local LocalDataModule = nil
pcall(function()
    LocalDataModule = require(game:GetService("ReplicatedStorage").Client.Framework.Services.LocalData)
end)

-- Helper: Safely pull the full player data table
local function GetPlayerData()
    local data = nil
    pcall(function()
        if LocalDataModule and LocalDataModule.Get then
            data = LocalDataModule.Get()
        end
    end)
    return data
end

-- Static pet rarity dictionary (for webhook rarity lookup)
local PetsData = nil
pcall(function()
    PetsData = require(game:GetService("ReplicatedStorage").Shared.Data.Pets)
end)

local function getPetRarity(petName)
    if PetsData and PetsData[petName] then
        return PetsData[petName].Rarity
    end
    return "Unknown"
end

-- Helper: Aggregate pets into { {Name, Shiny, Mythic, XL, Count}, ... } sorted by count desc
local function AggregatePets(petTable, rareOnly)
    local counts = {} -- key = "Name|shiny|mythic|xl" -> entry
    local order = {}

    for _, pet in pairs(petTable) do
        if type(pet) == "table" and pet.Name then
            local isShiny = pet.Shiny == true
            local isMythic = pet.Mythic == true
            local isXL = pet.XL == true

            local isSuper = pet.Super == true
            local rarity = getPetRarity(pet.Name)
            local isHighRarity = rarity == "Secret" or rarity == "Legendary"

            -- Filter: if rareOnly, show Shiny / Mythic / XL / Super / Secret / Legendary
            if not rareOnly or isShiny or isMythic or isXL or isSuper or isHighRarity then
                local key = pet.Name .. "|" .. tostring(isShiny) .. "|" .. tostring(isMythic) .. "|" .. tostring(isXL)
                local amount = pet.Amount or 1

                if counts[key] then
                    counts[key].Count = counts[key].Count + amount
                else
                    counts[key] = { Name = pet.Name, Shiny = isShiny, Mythic = isMythic, XL = isXL, Count = amount }
                    table.insert(order, key)
                end
            end
        end
    end

    -- Sort by count descending
    table.sort(order, function(a, b) return counts[a].Count > counts[b].Count end)

    local result = {}
    for _, key in ipairs(order) do
        table.insert(result, counts[key])
    end
    return result
end

-- Helper: Build field-safe strings from aggregated list, respecting Discord limits
-- Returns an array of strings, each <= maxLen characters
local function ChunkAggregated(aggregated, showQty, maxLen)
    maxLen = maxLen or 1000 -- stay under 1024 with some safety margin
    local chunks = {}
    local current = ""

    for _, entry in ipairs(aggregated) do
        -- Build tags: ✨ Shiny, 🟣 Mythic, 📏 XL
        local tags = ""
        if entry.Shiny then tags = tags .. "✨" end
        if entry.Mythic then tags = tags .. "🟣" end
        if entry.XL then tags = tags .. "📏" end
        if tags ~= "" then tags = tags .. " " end

        local line
        if showQty and entry.Count > 1 then
            line = tags .. entry.Name .. " x" .. tostring(entry.Count)
        else
            line = tags .. entry.Name
        end

        -- +1 for the newline
        if #current + #line + 1 > maxLen then
            if #current > 0 then
                table.insert(chunks, current)
            end
            current = line
        else
            current = current == "" and line or (current .. "\n" .. line)
        end
    end

    if #current > 0 then
        table.insert(chunks, current)
    end

    return chunks
end

-- Helper: Build a compact Powerups summary string
local function BuildPowerupsSummary(powerups)
    if not powerups or type(powerups) ~= "table" then return nil end
    local items = {}
    for name, count in pairs(powerups) do
        if type(count) == "number" and count > 0 then
            table.insert(items, name .. ": " .. tostring(count))
        end
    end
    table.sort(items)
    if #items == 0 then return nil end
    local summary = table.concat(items, " | ")
    if #summary > 1000 then summary = summary:sub(1, 997) .. "..." end
    return summary
end

-- Debug: Dump LocalData structure to clipboard (for Delta / emulator with no F9)
local function DumpLocalDataStructure()
    local data = GetPlayerData()
    if not data then
        pcall(function() setclipboard("[Splash Hub] LocalData.Get() returned nil — module may not be loaded yet.") end)
        return false
    end

    local lines = {}
    local function recurse(tbl, indent, depth)
        if depth > 3 then return end
        indent = indent or ""
        for k, v in pairs(tbl) do
            if type(v) == "table" then
                local arrLen = #v
                local totalLen = 0
                for _ in pairs(v) do totalLen = totalLen + 1 end
                table.insert(lines, indent .. tostring(k) .. " = {table, " .. arrLen .. " array / " .. totalLen .. " total}")
                recurse(v, indent .. "  ", depth + 1)
            else
                table.insert(lines, indent .. tostring(k) .. " = " .. tostring(v) .. " (" .. type(v) .. ")")
            end
        end
    end

    table.insert(lines, "========== [Splash Hub] LocalData.Get() Structure ==========")
    recurse(data, "", 0)
    table.insert(lines, "========== [End Dump] ==========")

    local output = table.concat(lines, "\n")
    pcall(function() setclipboard(output) end)
    return true
end

-- ---- UI ----
WebhookTab:CreateInput({ Name = "Webhook URL", PlaceholderText = "Paste Here...", RemoveTextAfterFocusLost = false, Flag = "WH_URL", Callback = function(T) wh_url = T; getgenv().SplashWebhookURL = T end })
-- Auto-clear webhook URL input on focus
task.spawn(function()
    task.wait(3)
    pcall(function()
        local whInput = Rayfield.Flags["WH_URL"]
        if whInput and whInput.Frame then
            local box = whInput.Frame:FindFirstChildWhichIsA("TextBox", true)
            if box then
                box.Focused:Connect(function()
                    if box.Text ~= "" then box.Text = "" end
                end)
            end
        end
    end)
end)
WebhookTab:CreateSlider({ Name = "Cooldown (Minutes)", Range = {1, 60}, Increment = 1, Suffix = "min", CurrentValue = 5, Flag = "WH_Slider", Callback = function(V) wh_cool = V; getgenv().SplashWebhookCooldown = V end })

WebhookTab:CreateButton({ Name = "Clear Webhook URL", Callback = function()
    wh_url = ""
    getgenv().SplashWebhookURL = ""
    pcall(function()
        local whInput = Rayfield.Flags["WH_URL"]
        if whInput and whInput.Set then whInput:Set("") end
    end)
    Rayfield:Notify({ Title = "Webhook Cleared", Content = "URL has been wiped.", Duration = 3 })
end })

WebhookTab:CreateButton({ Name = "Test Connection", Callback = function()
    if wh_url ~= "" then
        pcall(function()
            request({Url = wh_url, Method = "POST", Headers = {["Content-Type"]="application/json"}, Body = HttpService:JSONEncode({content="📡 Splash Hub V1 Connected!"})})
        end)
    end
end })

WebhookTab:CreateButton({ Name = "🔍 Dump LocalData to Clipboard", Callback = function()
    local success = DumpLocalDataStructure()
    if success then
        Rayfield:Notify({ Title = "Copied!", Content = "LocalData structure copied to clipboard. Paste it somewhere to read.", Duration = 4 })
    else
        Rayfield:Notify({ Title = "Failed", Content = "LocalData not available yet. Try again in a few seconds.", Duration = 4 })
    end
end })

WebhookTab:CreateSection("📡 Auto-Feed Settings")
WebhookTab:CreateToggle({ Name = "Show Pets in Feed", CurrentValue = false, Flag = "WHInventory", Callback = function(V) Toggles.WHInventory = V end })
WebhookTab:CreateToggle({ Name = "Include Quantities (x5)", CurrentValue = true, Flag = "WHShowQty", Callback = function(V) Toggles.WHShowQty = V end })
WebhookTab:CreateToggle({ Name = "Only Show Shiny/Mythic/Secret", CurrentValue = false, Flag = "WHRareOnly", Callback = function(V) Toggles.WHRareOnly = V end })

WebhookTab:CreateButton({ Name = "🐾 Send Pets Now (One-Time)", Callback = function()
    if wh_url == "" then Rayfield:Notify({ Title = "Error", Content = "Set a webhook URL first.", Duration = 3 }) return end
    pcall(function()
        local playerData = GetPlayerData()
        if not playerData or not playerData.Pets then
            Rayfield:Notify({ Title = "Error", Content = "LocalData not available yet.", Duration = 3 })
            return
        end
        local petTable = playerData.Pets
        local aggregated = AggregatePets(petTable, Toggles.WHRareOnly)
        if #aggregated == 0 then
            Rayfield:Notify({ Title = "Pets", Content = "No pets matched filter.", Duration = 3 })
            return
        end
        local showQty = Toggles.WHShowQty ~= false
        local petChunks = ChunkAggregated(aggregated, showQty, 1000)
        local fields = {}
        local totalChars = 0
        for i = 1, math.min(#petChunks, 20) do
            local fieldName = i == 1 and "🐾 Pets (" .. #aggregated .. " unique)" or "🐾 Pets (cont.)"
            if totalChars + #fieldName + #petChunks[i] > 5500 then break end
            totalChars = totalChars + #fieldName + #petChunks[i]
            table.insert(fields, {name = fieldName, value = petChunks[i], inline = false})
        end
        local pwSummary = BuildPowerupsSummary(playerData.Powerups)
        if pwSummary and totalChars + #pwSummary + 20 < 5800 then
            table.insert(fields, {name = "🎁 Powerups", value = pwSummary, inline = false})
        end
        local embedData = {
            embeds = {{
                title = "Splash Hub | 🐾 Full Pet Inventory",
                description = "Player: **" .. player.Name .. "** | " .. #petTable .. " total pets",
                color = 16744192,
                fields = fields,
                footer = { text = "Splash Hub V1 • " .. os.date("%H:%M:%S") }
            }}
        }
        request({Url = wh_url, Method = "POST", Headers = {["Content-Type"]="application/json"}, Body = HttpService:JSONEncode(embedData)})
        Rayfield:Notify({ Title = "Sent!", Content = "Full pet inventory sent to webhook.", Duration = 3 })
    end)
end })

WebhookTab:CreateToggle({ Name = "Enable Auto-Feed", CurrentValue = false, Flag = "AutoWH", Callback = function(Value)
    Toggles.AutoWH = Value
    if Value then
        task.spawn(function()
            while Toggles.AutoWH do
                if wh_url ~= "" then
                    pcall(function()
                        local playerData = GetPlayerData()

                        -- Currency fields — pull from LocalData first, fallback to leaderstats
                        local coins = playerData and playerData.Coins or pcall(function() return player.leaderstats.Coins.Value end) and player.leaderstats.Coins.Value or "?"
                        local gems = playerData and playerData.Gems or pcall(function() return player.leaderstats.Gems.Value end) and player.leaderstats.Gems.Value or "?"
                        local tickets = playerData and playerData.Tickets or 0
                        local seashells = playerData and playerData.Seashells or 0
                        local infToken = playerData and playerData.InfToken or 0

                        local fields = {
                            {name = "🪙 Coins", value = formatGemValue(coins), inline = true},
                            {name = "💎 Gems", value = formatGemValue(gems), inline = true},
                            {name = "🎟️ Tickets", value = formatGemValue(tickets), inline = true},
                            {name = "🐚 Seashells", value = formatGemValue(seashells), inline = true},
                            {name = "♾️ Inf Tokens", value = formatGemValue(infToken), inline = true},
                        }

                        local totalChars = 0
                        for _, f in ipairs(fields) do totalChars = totalChars + #f.name + #f.value end

                        -- Inventory data from LocalData module
                        if Toggles.WHInventory and playerData then
                            local petTable = playerData.Pets or {}
                            local aggregated = AggregatePets(petTable, Toggles.WHRareOnly)

                            if #aggregated > 0 then
                                local showQty = Toggles.WHShowQty ~= false
                                local petChunks = ChunkAggregated(aggregated, showQty, 1000)

                                -- Discord limits: max 25 fields, max 6000 total chars
                                local maxPetFields = math.min(#petChunks, 15)

                                for i = 1, maxPetFields do
                                    local fieldName = i == 1 and "🐾 Pets (" .. #aggregated .. " unique)" or "🐾 Pets (cont.)"
                                    local fieldValue = petChunks[i]

                                    if totalChars + #fieldName + #fieldValue > 5500 then break end
                                    totalChars = totalChars + #fieldName + #fieldValue

                                    table.insert(fields, {name = fieldName, value = fieldValue, inline = false})
                                end
                            else
                                table.insert(fields, {name = "🐾 Pets", value = "No pets matched filter.", inline = false})
                            end

                            -- Powerups summary
                            local pwSummary = BuildPowerupsSummary(playerData.Powerups)
                            if pwSummary and totalChars + #pwSummary + 20 < 5800 then
                                table.insert(fields, {name = "🎁 Powerups", value = pwSummary, inline = false})
                            end
                        elseif Toggles.WHInventory then
                            table.insert(fields, {name = "🐾 Pets", value = "⚠️ LocalData not available yet.", inline = false})
                        end

                        -- Advanced Automation Status Display
                        local activeAutos = {}
                        if Toggles.AutoBlow then table.insert(activeAutos, "🫧 Bubbles: Active") end
                        if Toggles.AutoSell then table.insert(activeAutos, "💰 Sell: Active") end
                        if Toggles.EventChests then table.insert(activeAutos, "🎁 Event Chests: Active") end

                        -- Hatching Status
                        if getgenv().AutoHatch then
                            if Toggles.ObbyQueue then table.insert(activeAutos, "🥚 Hatch: Paused (Minigames)")
                            elseif getgenv().GemFarming then table.insert(activeAutos, "🥚 Hatch: Paused (Gem Farm)")
                            elseif getgenv().GemFarmSavedCFrame then table.insert(activeAutos, "🥚 Hatch: Paused (Teleport/Reconnect)")
                            else table.insert(activeAutos, "🥚 Hatch: Active") end
                        end
                        
                        -- Shops Status
                        if autoBuyActive then
                            if getgenv().GemFarming then table.insert(activeAutos, "🛒 Shops: Paused (Gem Farm)")
                            else table.insert(activeAutos, "🛒 Shops: Active") end
                        end
                        
                        -- Gem Farm Status
                        if getgenv().GemFarming then table.insert(activeAutos, "⛏️ Gem Farm: Active")
                        elseif gemFarmThreshold > 0 then table.insert(activeAutos, "⛏️ Gem Farm: Paused (Idle/Above Threshold)") end
                        
                        if Toggles.ObbyQueue then table.insert(activeAutos, "🏃 Obby: Active") end
                        
                        -- Summer Event Status (populated by SummerTab)
                        if getgenv().CycleEnabled then
                            local phase = getgenv().IsHatchingPhase and "Hatching" or "Farming"
                            table.insert(activeAutos, "☀️ Summer Cycle: " .. phase)
                        end
                        if getgenv().SummerFarmActive then
                            table.insert(activeAutos, "⛏️ Artifact Farm: Active")
                        end
                        if getgenv().SummerAutoChestEnabled then
                            table.insert(activeAutos, "📦 Summer Chest: Active")
                        end
                        if getgenv().UpgradeEnabled then
                            table.insert(activeAutos, "🛠️ Summer Upgrades: Active")
                        end

                        if #activeAutos > 0 then
                            table.insert(fields, {name = "⚙️ Automation Status", value = table.concat(activeAutos, "\n"), inline = false})
                        end

                        -- Active Potions with Rarity & Currency
                        local potionStatus = {}
                        local potionMeta = {
                            {toggle = "AutoLuck", name = "Lucky", currency = "🍀 Luck"},
                            {toggle = "AutoSpeed", name = "Speed", currency = "⚡ Speed"},
                            {toggle = "AutoCoins", name = "Coins", currency = "🪙 Coins"},
                            {toggle = "AutoMythic", name = "Mythic", currency = "🔮 Mythic"},
                            {toggle = "AutoTickets", name = "Tickets", currency = "🎟️ Tickets"},
                            {toggle = "AutoEgg", name = "Egg Elixir", currency = "🥚 Egg"},
                            {toggle = "AutoSecret", name = "Secret Elixir", currency = "⭐ Secret"},
                            {toggle = "AutoInf", name = "Infinity Elixir", currency = "♾️ Infinity"},
                            {toggle = "AutoAnniPot", name = "Anniversary", currency = "🎉 Anniversary"},
                            {toggle = "AutoFestive", name = "Festive", currency = "🎄 Festive"},
                        }
                        local tierDisplay = potionTier or "I"
                        for _, pm in ipairs(potionMeta) do
                            if Toggles[pm.toggle] then
                                table.insert(potionStatus, pm.currency .. " " .. pm.name .. " [Tier " .. tierDisplay .. "]")
                            end
                        end
                        -- Rune status
                        local runeMeta = {
                            {toggle = "LuckRune", name = "Luck Rune", currency = "🍀"},
                            {toggle = "BubblesRune", name = "Bubbles Rune", currency = "🫧"},
                            {toggle = "SecretRune", name = "Secret Rune", currency = "⭐"},
                        }
                        local runeDisplay = runeTier or "I"
                        for _, rm in ipairs(runeMeta) do
                            if Toggles[rm.toggle] then
                                table.insert(potionStatus, rm.currency .. " " .. rm.name .. " [Tier " .. runeDisplay .. "]")
                            end
                        end
                        if #potionStatus > 0 then
                            table.insert(fields, {name = "🧪 Active Potions & Runes", value = table.concat(potionStatus, "\n"), inline = false})
                        end

                        -- Shop Purchases (Buffered since last webhook)
                        if #shopPurchaseLog > 0 then
                            local shopStr = ""
                            for _, log in ipairs(shopPurchaseLog) do
                                if log.slots >= 3 then
                                    shopStr = shopStr .. string.format("✅ **%s** fully cleared! [%s]\n", log.shop, log.time)
                                else
                                    shopStr = shopStr .. string.format("🛒 %s: %d slots [%s]\n", log.shop, log.slots, log.time)
                                end
                            end
                            if #shopStr > 1024 then shopStr = "..." .. string.sub(shopStr, -1020) end
                            table.insert(fields, {name = "🛒 Shop Activity", value = shopStr, inline = false})
                            
                            -- Clear the buffer after successful inclusion in the payload
                            shopPurchaseLog = {}
                        end
                        
                        -- Console Logs (Last 20 lines)
                        if getgenv().ConsoleLogs and #getgenv().ConsoleLogs > 0 then
                            local consoleSlice = {}
                            local maxLines = 20
                            local startIdx = math.max(1, #getgenv().ConsoleLogs - maxLines + 1)
                            for i = startIdx, #getgenv().ConsoleLogs do
                                table.insert(consoleSlice, getgenv().ConsoleLogs[i])
                            end
                            table.insert(fields, {name = "💻 Console", value = "```\n" .. table.concat(consoleSlice, "\n") .. "\n```", inline = false})
                        end

                        local embedData = {
                            embeds = {{
                                title = "Splash Hub | V1 Tracker",
                                description = "Player: **" .. player.Name .. "**",
                                color = 43775,
                                fields = fields,
                                footer = { text = "Splash Hub V1 • " .. os.date("%H:%M:%S") }
                            }}
                        }

                        request({Url = wh_url, Method = "POST", Headers = {["Content-Type"]="application/json"}, Body = HttpService:JSONEncode(embedData)})
                    end)
                end
                task.wait(wh_cool * 60)
            end
        end)
    end
end})

WebhookTab:CreateSection("🔔 Ping Options")
getgenv().WHPingID = ""
WebhookTab:CreateInput({ Name = "Ping UserID (Optional)", PlaceholderText = "Discord ID (e.g. 123456)", Flag = "WHPingID", Callback = function(T) getgenv().WHPingID = T end })
WebhookTab:CreateToggle({ Name = "Ping on Secret Pet", CurrentValue = true, Flag = "WHPingSecret", Callback = function(V) Toggles.WHPingSecret = V end })
WebhookTab:CreateToggle({ Name = "Ping on Infinity Pet", CurrentValue = true, Flag = "WHPingInf", Callback = function(V) Toggles.WHPingInf = V end })
WebhookTab:CreateToggle({ Name = "Ping on Mythic Pet", CurrentValue = true, Flag = "WHPingMythic", Callback = function(V) Toggles.WHPingMythic = V end })
WebhookTab:CreateToggle({ Name = "Ping on Shiny Pet", CurrentValue = true, Flag = "WHPingShiny", Callback = function(V) Toggles.WHPingShiny = V end })
WebhookTab:CreateToggle({ Name = "Ping on Super Legendary", CurrentValue = true, Flag = "WHPingSuper", Callback = function(V) Toggles.WHPingSuper = V end })

-- ==========================================
-- 🌐 MISC WEBHOOK TOGGLES
-- ==========================================
WebhookTab:CreateSection("⛩️ Shrine Webhooks")
WebhookTab:CreateToggle({ Name = "Track Shrine Donations", CurrentValue = false, Flag = "TrackShrineHook", Callback = function(V) getgenv().TrackShrines = V end })

WebhookTab:CreateSection("🏆 Season Webhooks")
getgenv().SeasonEnableWebhookTracking = false
WebhookTab:CreateToggle({ Name = "Live Challenge Tracking", CurrentValue = false, Flag = "SeasonWebhookTracker", Callback = function(V) getgenv().SeasonEnableWebhookTracking = V end })
getgenv().SeasonEnableCompletionWebhook = false
WebhookTab:CreateToggle({ Name = "Send Notification on Full Completion", CurrentValue = false, Flag = "SeasonEnableCompletionWebhook", Callback = function(V) getgenv().SeasonEnableCompletionWebhook = V end })

WebhookTab:CreateSection("🧞 Genie Webhooks")
getgenv().GenieWebhookInterval = 60
WebhookTab:CreateSlider({ Name = "Genie Status Interval", Range = {30, 300}, Increment = 10, Suffix = " Secs", CurrentValue = 60, Flag = "GenieWebhookIntervalSlider", Callback = function(V) getgenv().GenieWebhookInterval = V end })

WebhookTab:CreateSection("☀️ Summer Webhooks")
WebhookTab:CreateToggle({ Name = "Track Farm & Shell Status", CurrentValue = false, Flag = "Sum_TrackStatus", Callback = function(V) getgenv().TrackStatus = V end })
WebhookTab:CreateToggle({ Name = "Track Egg Swap & Hatch Cycle", CurrentValue = false, Flag = "Sum_TrackHatch", Callback = function(V) getgenv().TrackHatchStats = V end })
WebhookTab:CreateToggle({ Name = "Track Secret/Mythic Hatches", CurrentValue = false, Flag = "Sum_TrackSecrets", Callback = function(V) getgenv().TrackSecrets = V end })
WebhookTab:CreateToggle({ Name = "Track Captain Kitty Quests", CurrentValue = false, Flag = "Sum_TrackKitty", Callback = function(V) getgenv().TrackKitty = V end })
WebhookTab:CreateToggle({ Name = "Track Upgrade Status", CurrentValue = false, Flag = "Sum_TrackUpgrades", Callback = function(V) getgenv().TrackUpgrades = V end })
WebhookTab:CreateToggle({ Name = "Track Gem Genie", CurrentValue = false, Flag = "Sum_TrackGenie", Callback = function(V) getgenv().TrackGenie = V end })
WebhookTab:CreateToggle({ Name = "Track Old Sailor", CurrentValue = false, Flag = "Sum_TrackSailor", Callback = function(V) getgenv().TrackSailor = V end })
WebhookTab:CreateToggle({ Name = "Track Artifacts & Seashells", CurrentValue = false, Flag = "Sum_TrackArtifacts", Callback = function(V) getgenv().TrackArtifacts = V end })

-- Bulletproof Hatch Detection via LocalData.ConnectDataChanged("Pets")
-- Replaces unreliable chat scraping with direct data diffing
local knownPetIds = {}

-- Snapshot current pet IDs on load
task.spawn(function()
    -- Wait for data to be ready
    local waitStart = tick()
    while not GetPlayerData() and tick() - waitStart < 30 do
        task.wait(1)
    end
    local data = GetPlayerData()
    if data and data.Pets then
        for _, pet in pairs(data.Pets) do
            if type(pet) == "table" and pet.Id then
                knownPetIds[pet.Id] = true
            end
        end
    end
end)

-- Hook into pet data changes for instant new-pet detection
if LocalDataModule and LocalDataModule.ConnectDataChanged then
    pcall(function()
        LocalDataModule:ConnectDataChanged("Pets", function(fullData)
            if wh_url == "" or not fullData or not fullData.Pets then return end

            for _, pet in pairs(fullData.Pets) do
                if type(pet) == "table" and pet.Id and not knownPetIds[pet.Id] then
                    -- NEW PET DETECTED
                    knownPetIds[pet.Id] = true

                    local petName = pet.Name or "Unknown"
                    local rarity = getPetRarity(petName)
                    local isShiny = pet.Shiny == true
                    local isMythic = pet.Mythic == true
                    local isXL = pet.XL == true
                    local isSuper = pet.Super == true
                    local isInfinity = (rarity == "Secret" and string.find(petName, "Infinity")) or false

                    -- Build tag string
                    local tags = ""
                    if isShiny then tags = tags .. "✨ Shiny " end
                    if isMythic then tags = tags .. "🟣 Mythic " end
                    if isXL then tags = tags .. "📏 XL " end
                    if isSuper then tags = tags .. "⭐ Super " end

                    -- Determine ping priority (highest wins)
                    local shouldPing = false
                    local title, color

                    if rarity == "Secret" and Toggles.WHPingSecret then
                        shouldPing = true
                        title = "🚨 SECRET OBTAINED! 🚨"
                        color = 16711680 -- red
                    elseif isSuper and Toggles.WHPingSuper then
                        shouldPing = true
                        title = "⭐ SUPER LEGENDARY! ⭐"
                        color = 16766720 -- gold
                    elseif isMythic and Toggles.WHPingMythic then
                        shouldPing = true
                        title = "🟣 MYTHIC OBTAINED! 🟣"
                        color = 8388736 -- purple
                    elseif isShiny and Toggles.WHPingShiny then
                        shouldPing = true
                        title = "✨ SHINY OBTAINED! ✨"
                        color = 16776960 -- yellow
                    end

                    if shouldPing then
                        local desc = player.Name .. " obtained: **" .. tags .. petName .. "**"
                        if rarity ~= "Unknown" then desc = desc .. "\nRarity: " .. rarity end
                        local amount = pet.Amount or 1
                        if amount > 1 then desc = desc .. "\nAmount: x" .. tostring(amount) end

                        pcall(function()
                            request({
                                Url = wh_url,
                                Method = "POST",
                                Headers = {["Content-Type"] = "application/json"},
                                Body = HttpService:JSONEncode({
                                    embeds = {{
                                        title = title,
                                        description = desc,
                                        color = color,
                                        footer = { text = "Splash Hub V1 • " .. os.date("%H:%M:%S") }
                                    }}
                                })
                            })
                        end)
                    end
                end
            end
        end)
    end)
end

task.wait() -- UI renderer yield
-- ==========================================
-- ⚙️ 12. MISC, ANTI-AFK & RECONNECT
-- ==========================================
MiscTab:CreateSection("🛡️ Anti-AFK")
MiscTab:CreateToggle({ Name = "Enable Anti-AFK", CurrentValue = true, Flag = "AntiAFK", Callback = function(V) Toggles.AntiAFK = V end })

MiscTab:CreateSection("🔄 Server & Reconnect")
local psLink = ""
local reconnectType = "Current Server"
local reconnectHours = 1
local reconnectTargetTime = 0

MiscTab:CreateInput({ Name = "Private Server Link / JobId", PlaceholderText = "Paste VIP Link or JobId...", Flag = "PSInput", Callback = function(Text) psLink = Text end })
MiscTab:CreateDropdown({ Name = "Reconnect Type", Options = {"Current Server", "Private Server"}, CurrentOption = {"Current Server"}, Flag = "ReconnectType", Callback = function(Option) reconnectType = Option[1] end })
MiscTab:CreateSlider({ Name = "Reconnect Timer", Range = {1, 48}, Increment = 1, Suffix = " Hours", CurrentValue = 1, Flag = "ReconnectTimer", Callback = function(Value) reconnectHours = Value end })

local function DoReconnect()
    local ts = game:GetService("TeleportService")
    local p = game:GetService("Players").LocalPlayer
    
    if reconnectType == "Current Server" then
        pcall(function() ts:TeleportToPlaceInstance(game.PlaceId, game.JobId, p) end)
        task.wait(2)
        pcall(function() ts:Teleport(game.PlaceId, p) end) -- Fallback if JobId fails
    else
        if psLink ~= "" then
            local extractedCode = psLink:match("privateServerLinkCode=([^&]+)")
            if extractedCode then
                pcall(function() ts:TeleportToPrivateServer(game.PlaceId, extractedCode, {p}) end)
            else
                pcall(function() ts:TeleportToPlaceInstance(game.PlaceId, psLink, p) end)
            end
        else
            pcall(function() ts:Teleport(game.PlaceId, p) end)
        end
    end
end

local function PrepareAndReconnect()
    local p = game:GetService("Players").LocalPlayer
    
    -- Stop summer features cleanly
    getgenv().SummerFarmActive = false
    getgenv().SummerAutoChestEnabled = false
    getgenv().CycleEnabled = false
    getgenv().IsHatchingPhase = false
    getgenv().IsClaimingChest = false
    getgenv().IsClaimingInfChest = false
    getgenv().InfChestEnabled = false
    getgenv().IsDoingQuest = false

    getgenv().AutoSellEnabled = false
    getgenv().UpgradeEnabled = false

    -- Stop season features cleanly
    getgenv().SeasonAutoHourly = false
    getgenv().SeasonAutoDaily = false
    getgenv().SeasonAutoZenPath = false
    getgenv().AutoDreamShrine = false
    getgenv().AutoBubbleShrine = false
    if getgenv().CurrentFarmTween then pcall(function() getgenv().CurrentFarmTween:Cancel() end) end
    
    -- Determine the correct pre-automation position to restore
    -- Priority: Summer base > Gem farm saved > Obby saved > Current position
    local returnCFrame = nil
    if getgenv().SummerBaseCFrame then
        -- Summer base = where player was BEFORE summer farm/cycle started
        returnCFrame = getgenv().SummerBaseCFrame
    elseif getgenv().GemFarming and getgenv().GemFarmSavedCFrame then
        returnCFrame = getgenv().GemFarmSavedCFrame
        -- Stop gem farming cleanly
        getgenv().GemFarming = false
        disableNoclip()
    elseif getgenv().ObbySavedCFrame then
        returnCFrame = getgenv().ObbySavedCFrame
    end
    
    if returnCFrame then
        local pos = returnCFrame.Position
        local posStr = string.format("%.2f,%.2f,%.2f", pos.X, pos.Y, pos.Z)
        pcall(function() writefile("SplashHub_SavedPosition.txt", posStr) end)
    else
        local char = p.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            local pos = char.HumanoidRootPart.Position
            local posStr = string.format("%.2f,%.2f,%.2f", pos.X, pos.Y, pos.Z)
            pcall(function() writefile("SplashHub_SavedPosition.txt", posStr) end)
        end
    end
    consoleLog("Initiating Server Reconnect...")
    Rayfield:Notify({Title = "Saving Position", Content = "Reconnecting in 2 seconds...", Duration = 2})
    task.wait(2)
    DoReconnect()
end

local _reconnectLoopRunning = false
MiscTab:CreateToggle({ Name = "Enable Auto-Reconnect Timer", CurrentValue = false, Flag = "AutoReconnect", Callback = function(Value) 
    Toggles.AutoReconnect = Value
    if Value then
        -- If the reconnect loop is already running, don't restart it
        if _reconnectLoopRunning then return end
        _reconnectLoopRunning = true
        
        -- Read the ACTUAL slider value from Rayfield flags (not the variable, which may not have been updated by config load)
        local actualHours = reconnectHours
        pcall(function()
            if Rayfield and Rayfield.Flags and Rayfield.Flags["ReconnectTimer"] then
                local flagVal = Rayfield.Flags["ReconnectTimer"].CurrentValue
                if type(flagVal) == "number" and flagVal >= 1 then
                    actualHours = flagVal
                    reconnectHours = flagVal -- Sync the variable too
                end
            end
        end)
        reconnectTargetTime = os.time() + (actualHours * 3600)
        consoleLog("Auto-Reconnect: " .. actualHours .. "h timer started (target: " .. os.date("%H:%M:%S", reconnectTargetTime) .. ")")
        task.spawn(function()
            while Toggles.AutoReconnect do
                if os.time() >= reconnectTargetTime - 10 then
                    PrepareAndReconnect()
                    break
                end
                task.wait(1)
            end
            _reconnectLoopRunning = false
        end)
    else
        _reconnectLoopRunning = false
    end
end })

MiscTab:CreateButton({ Name = "Reconnect NOW", Callback = function() PrepareAndReconnect() end })

MiscTab:CreateSection("🔧 Tools")
MiscTab:CreateButton({ Name = "Load Cobalt", Callback = function() 
    pcall(function() loadstring(game:HttpGet("https://github.com/notpoiu/cobalt/releases/latest/download/Cobalt.luau"))() end) 
end })

MiscTab:CreateButton({ Name = "Test Console Log", Callback = function()
    consoleLog("Test message from GUI!")
    Rayfield:Notify({Title = "Console", Content = "Test log sent to console.", Duration = 3})
end })

MiscTab:CreateSection("🏷️ Titles & Chat Tags")
local allTitles = {
    -- Exotic & Special Titles
    "Developer", "Absolute", "Alchemist", "Angler", "Artisan", "BeyondReality", 
    "BreakerOfLimits", "BrightestStar", "BubbleOverlord", "Bubbler2019", "Bubbler2020", 
    "BubblerOG", "Capitalist", "Chill", "ChristmasChampion", "ChristmasHero", 
    "ChristmasSpirit", "CircusPerf", "CircusRing", "CircusStage", "ColossalInferno", 
    "Colossus", "Completionist", "Contributor", "Dedicated", "DejaVu", "Doggy", 
    "Elf", "EternalHatcher", "Festive", "Mechanical Master", "Shadow Seeker", 
    "The Dark Prince", "The Roaring Warden", "[BRUH]", 

    -- Standard Titles
    "Unreal Bubbler", "Godly Bubbler", "Bubble Master", "Unreal Hatcher", 
    "Godly Hatcher", "Egg Master", "Expert", "Extreme", "Intermediate", "Novice"
}

getgenv().SelectedTitle = "Developer"
MiscTab:CreateDropdown({
    Name = "Select Title (Client-Side Spoof)",
    Options = allTitles,
    CurrentOption = {"Developer"},
    Flag = "TitlesDropdown",
    Callback = function(Option)
        getgenv().SelectedTitle = Option[1]
    end,
})

getgenv().CustomTitle = ""
MiscTab:CreateInput({
    Name = "Custom Title Override",
    PlaceholderText = "Type custom title here...",
    RemoveTextAfterFocusLost = false,
    Callback = function(Text)
        getgenv().CustomTitle = Text
    end,
})

MiscTab:CreateToggle({
    Name = "Enable Client-Side Title Spoof",
    CurrentValue = false,
    Flag = "TitleSpoofToggle",
    Callback = function(Value)
        task.spawn(function()
            getgenv().TitleSpoofEnabled = Value
            if Value then
            -- 1. Try server-side just in case
            pcall(function()
                local ReplicatedStorage = game:GetService("ReplicatedStorage")
                local NetworkRemote = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Framework"):WaitForChild("Network"):WaitForChild("Remote")
                local RE = NetworkRemote:WaitForChild("RemoteEvent")
                local RF = NetworkRemote:WaitForChild("RemoteFunction")
                local possibleRemotes = {"EquipTitle", "SelectTitle", "ChangeTitle", "SetTitle", "Equip"}
                for _, act in ipairs(possibleRemotes) do
                    task.spawn(function()
                        pcall(function() RE:FireServer(act, getgenv().SelectedTitle) end)
                        pcall(function() RF:InvokeServer(act, getgenv().SelectedTitle) end)
                    end)
                end
            end)
            
            -- 2. Trigger PlayerDataChanged for internal listeners
            pcall(function()
                local Event = game:GetService("ReplicatedStorage").Remotes.PlayerDataChanged
                if getconnections then
                    for _, conn in ipairs(getconnections(Event.OnClientEvent)) do
                        pcall(function() conn:Fire("TitleEquipped", getgenv().SelectedTitle) end)
                    end
                end
            end)

            -- 3. Overhead GUI & Native Chat Tag Loop
            task.spawn(function()
                local Constants = nil
                pcall(function() Constants = require(game:GetService("ReplicatedStorage").Shared.Constants) end)
                
                while getgenv().TitleSpoofEnabled do
                    pcall(function()
                        local themeTitle = getgenv().SelectedTitle
                        local displayTitle = (getgenv().CustomTitle and getgenv().CustomTitle ~= "") and getgenv().CustomTitle or themeTitle
                        local tColorHex = "#00FFFF"
                        local baseColor = Color3.fromRGB(0, 255, 255)
                        
                        -- Resolve Title Gradient & Colors based on themeTitle
                        local gradFolder = game:GetService("ReplicatedStorage").Assets.Gradients.Titles
                        local gradSrc = gradFolder:FindFirstChild(themeTitle) or gradFolder:FindFirstChild(themeTitle:gsub(" ", ""))
                        if gradSrc and gradSrc:IsA("UIGradient") then
                            local keypoints = gradSrc.Color.Keypoints
                            baseColor = keypoints[math.max(1, math.floor(#keypoints/2))].Value
                            tColorHex = string.format("#%02X%02X%02X", baseColor.R*255, baseColor.G*255, baseColor.B*255)
                        else
                            if themeTitle:find("Developer") then baseColor = Color3.fromRGB(255, 0, 0); tColorHex = "#FF0000"
                            elseif themeTitle:find("Shadow") then baseColor = Color3.fromRGB(150, 0, 255); tColorHex = "#9600FF" end
                        end
                        
                        -- Native TextChatService Tag Injection! (From StarterPlayerScripts dump)
                        if Constants and Constants.ChatTagsAttribute then
                            -- BGS uses TextChatMessageProperties.PrefixText = `{attribute} {arg1.PrefixText}`
                            local tagRichText = string.format('<font color="%s"><b>[%s]</b></font>', tColorHex, displayTitle)
                            game.Players.LocalPlayer:SetAttribute(Constants.ChatTagsAttribute, tagRichText)
                        end

                        -- Overhead GUI update
                        local char = game.Players.LocalPlayer.Character
                        if char and char:FindFirstChild("Head") then
                            for _, bb in pairs(char.Head:GetChildren()) do
                                if bb:IsA("BillboardGui") then
                                    for _, v in pairs(bb:GetDescendants()) do
                                        if v:IsA("TextLabel") then
                                            local lower = v.Name:lower()
                                            if lower:find("name") or lower == "player" then
                                                v.Text = getgenv().SplashNameSpoof or game.Players.LocalPlayer.DisplayName
                                            elseif lower:find("title") or lower:find("rank") or lower == "textlabel" then
                                                if v.Text == game.Players.LocalPlayer.DisplayName and not lower:find("title") then
                                                    continue
                                                end
                                                v.Text = displayTitle
                                                if gradSrc and gradSrc:IsA("UIGradient") then
                                                    local myGrad = v:FindFirstChildOfClass("UIGradient")
                                                    if not myGrad then myGrad = gradSrc:Clone(); myGrad.Parent = v
                                                    else myGrad.Color = gradSrc.Color end
                                                    v.TextColor3 = Color3.new(1, 1, 1)
                                                else
                                                    v.TextColor3 = baseColor
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end)
                    task.wait(0.1)
                end
            end)
        else
            -- Clean up attribute when turned off so chat returns to normal
            pcall(function()
                local Constants = require(game:GetService("ReplicatedStorage").Shared.Constants)
                game.Players.LocalPlayer:SetAttribute(Constants.ChatTagsAttribute, "")
            end)
        end
    end)
    end
})

MiscTab:CreateSection("🥷 Name Spoof & Anon Mode")
MiscTab:CreateLabel("Client-side only. Changes YOUR view of your name. Does not affect title/tag colors.")

getgenv().SplashNameSpoof = nil
getgenv().SplashAnonMode = false
getgenv().SplashCustomName = ""

local applyNameSpoof -- pre-declare so UI can use it

MiscTab:CreateInput({
    Name = "Custom Display Name",
    PlaceholderText = "Enter fake name...",
    RemoveTextAfterFocusLost = false,
    Flag = "CustomNameInput",
    Callback = function(Text)
        getgenv().SplashCustomName = Text
        if Text ~= "" then
            getgenv().SplashNameSpoof = Text
            Rayfield:Notify({ Title = "Name Spoof", Content = "Display name set to: " .. Text, Duration = 3 })
            if applyNameSpoof then applyNameSpoof() end
        else
            if not getgenv().SplashAnonMode then
                getgenv().SplashNameSpoof = nil
            end
        end
    end,
})

MiscTab:CreateToggle({
    Name = "Anonymous Mode",
    CurrentValue = false,
    Flag = "AnonModeToggle",
    Callback = function(Value)
        task.spawn(function()
            getgenv().SplashAnonMode = Value
            if Value then
                -- If custom name is set, use that instead of "Splash"
                if not getgenv().SplashCustomName or getgenv().SplashCustomName == "" then
                    getgenv().SplashNameSpoof = "Splash"
                else
                    getgenv().SplashNameSpoof = getgenv().SplashCustomName
                end
                Rayfield:Notify({ Title = "Anonymous Mode", Content = "Enabled — your name is now: " .. getgenv().SplashNameSpoof, Duration = 5 })
                if applyNameSpoof then applyNameSpoof() end
            else
                if not getgenv().SplashCustomName or getgenv().SplashCustomName == "" then
                    getgenv().SplashNameSpoof = nil
                end
                Rayfield:Notify({ Title = "Anonymous Mode", Content = "Disabled — name restored.", Duration = 3 })
            end
        end)
    end
})

local function fixText(gui)
    local fakeName = getgenv().SplashNameSpoof
    if not fakeName then return end

    local lp = game.Players.LocalPlayer
    local realDisplayName = lp.DisplayName
    local realUsername = lp.Name

    if gui:IsA("TextLabel") or gui:IsA("TextButton") then
        -- Initial check
        local currentText = gui.Text
        if currentText == realDisplayName or currentText == realUsername then
            gui.Text = fakeName
        elseif currentText:find(realDisplayName) then
            gui.Text = currentText:gsub(realDisplayName, fakeName)
        elseif currentText:find(realUsername) then
            gui.Text = currentText:gsub(realUsername, fakeName)
        end
        
        -- Hook text changes for zero-lag updates (with recursive loop protection)
        if not gui:GetAttribute("SpoofHooked") then
            gui:SetAttribute("SpoofHooked", true)
            gui:GetPropertyChangedSignal("Text"):Connect(function()
                if gui:GetAttribute("IsSpoofingText") then return end
                
                local innerFake = getgenv().SplashNameSpoof
                if not innerFake then return end
                
                local newText = gui.Text
                -- Only attempt replacement if the real name is actually in the string
                if newText == realDisplayName or newText == realUsername or newText:find(realDisplayName) or newText:find(realUsername) then
                    gui:SetAttribute("IsSpoofingText", true) -- Lock to prevent infinite loop
                    
                    if newText == realDisplayName or newText == realUsername then
                        gui.Text = innerFake
                    elseif newText:find(realDisplayName) then
                        gui.Text = newText:gsub(realDisplayName, innerFake)
                    elseif newText:find(realUsername) then
                        gui.Text = newText:gsub(realUsername, innerFake)
                    end
                    
                    gui:SetAttribute("IsSpoofingText", false) -- Unlock
                end
            end)
        end
    end
end

applyNameSpoof = function()
    local fakeName = getgenv().SplashNameSpoof
    if not fakeName then return end
    
    local lp = game.Players.LocalPlayer
    
    pcall(function()
        -- 1. One-time pass over PlayerGui
        for _, gui in pairs(lp.PlayerGui:GetDescendants()) do
            fixText(gui)
        end
    end)
    
    pcall(function()
        -- 2. One-time pass over CoreGui
        for _, gui in pairs(game:GetService("CoreGui"):GetDescendants()) do
            fixText(gui)
        end
    end)
    
    pcall(function()
        -- 3. Native Humanoid DisplayName
        if lp.Character then
            local humanoid = lp.Character:FindFirstChildOfClass("Humanoid")
            if humanoid then
                humanoid.DisplayName = fakeName
            end
        end
    end)
end

-- Hook new UI elements being added so we never need a loop
-- We only apply fixText to the specific new element, NOT the whole tree
pcall(function()
    game.Players.LocalPlayer.PlayerGui.DescendantAdded:Connect(function(descendant)
        if getgenv().SplashNameSpoof then
            fixText(descendant)
        end
    end)
    game:GetService("CoreGui").DescendantAdded:Connect(function(descendant)
        if getgenv().SplashNameSpoof then
            fixText(descendant)
        end
    end)
end)


task.wait() -- UI renderer yield
-- ==========================================
-- 🛠️ 13. SETTINGS & CONFIGS
-- ==========================================
local mapCache = {}
SettingsTab:CreateToggle({ Name = "Hide Map (FPS Boost)", CurrentValue = false, Flag = "HideMap", Callback = function(Value) 
    task.spawn(function()
        if Value then pcall(function() for _, v in pairs(workspace:GetDescendants()) do if (v:IsA("BasePart") or v:IsA("Texture") or v:IsA("Decal")) and not v.Parent:FindFirstChild("Humanoid") then if not mapCache[v] then mapCache[v] = v.Transparency end v.Transparency = 1 end end end) 
        else pcall(function() for obj, origTrans in pairs(mapCache) do if obj and obj.Parent then obj.Transparency = origTrans end end mapCache = {} end) end 
    end)
end })

local blackScreenGui = nil
SettingsTab:CreateToggle({ Name = "Safe Black Screen (Fullscreen Fix)", CurrentValue = false, Flag = "BlackToggle", Callback = function(Value) 
    task.spawn(function()
        local pg = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
        if Value then 
            pcall(function() 
                if not blackScreenGui then
                    blackScreenGui = Instance.new("ScreenGui")
                    blackScreenGui.Name = "SplashHubBlackScreen"
                    blackScreenGui.ResetOnSpawn = false
                    blackScreenGui.IgnoreGuiInset = true
                    local frame = Instance.new("Frame")
                    frame.Size = UDim2.new(1, 0, 1, 0)
                    frame.BackgroundColor3 = Color3.new(0, 0, 0)
                    frame.Parent = blackScreenGui
                    local t = Instance.new("TextLabel")
                    t.Size = UDim2.new(1, 0, 1, 0)
                    t.BackgroundTransparency = 1
                    t.Text = "SPLASH HUB - SAFE BLACK SCREEN ACTIVE\nPress Right Shift or use Remote to disable"
                    t.TextColor3 = Color3.new(1, 1, 1)
                    t.TextSize = 24
                    t.Parent = frame
                    blackScreenGui.Parent = pg
                    game:GetService("RunService"):Set3dRenderingEnabled(false)
                end
            end)
        else 
            pcall(function() 
                if blackScreenGui then blackScreenGui:Destroy() blackScreenGui = nil end
                game:GetService("RunService"):Set3dRenderingEnabled(true)
            end) 
        end 
    end)
end })

-- RightShift keybind to toggle blackscreen
pcall(function()
    game:GetService("UserInputService").InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode == Enum.KeyCode.RightShift then
            if Rayfield and Rayfield.Flags and Rayfield.Flags["BlackToggle"] then
                local current = Rayfield.Flags["BlackToggle"].CurrentValue
                pcall(function() Rayfield.Flags["BlackToggle"]:Set(not current) end)
            end
        end
    end)
end)


SettingsTab:CreateSection("🌐 Gumteeth Remote")
SettingsTab:CreateLabel("Control Splash Hub from your phone via the Gumteeth WebApp.")

SettingsTab:CreateInput({
    Name = "API Key",
    PlaceholderText = "Paste your gt_ key from gumteeth.net...",
    RemoveTextAfterFocusLost = false,
    Flag = "RemoteConfigURL",
    Callback = function(Text)
        if Text == "" then
            remoteApiKey = ""
            remoteConfigEnabled = false
            pcall(function() remoteStatusLabel:Set("Remote Config: Disabled") end)
            return
        end
        -- Verify key with server before enabling
        task.spawn(function()
            pcall(function() remoteStatusLabel:Set("Remote Config: Verifying key...") end)
            local success, response = pcall(function()
                local HttpService = game:GetService("HttpService")
                local robloxId = tostring(game:GetService("Players").LocalPlayer.UserId)
                return request({
                    Url = remoteConfigUrl:gsub("/config", "/verify"),
                    Method = "POST",
                    Headers = {
                        ["Content-Type"] = "application/json",
                        ["Authorization"] = "Bearer " .. Text
                    },
                    Body = HttpService:JSONEncode({ robloxUserId = robloxId })
                })
            end)
            if success and response and response.StatusCode == 200 then
                local data = game:GetService("HttpService"):JSONDecode(response.Body)
                if data.valid then
                    remoteApiKey = Text
                    remoteConfigEnabled = true
                    consoleLog("✅ Gumteeth verified — welcome, " .. (data.username or "User") .. "!")
                    pcall(function() remoteStatusLabel:Set("Remote Config: Active (" .. (data.username or "User") .. ")") end)
                    Rayfield:Notify({ Title = "Gumteeth", Content = "Key verified! Dashboard connected.", Duration = 4 })
                else
                    remoteApiKey = ""
                    remoteConfigEnabled = false
                    local reason = data.error or "Unknown error"
                    consoleLog("❌ Gumteeth verification failed: " .. reason)
                    pcall(function() remoteStatusLabel:Set("Remote Config: REJECTED — " .. reason) end)
                    Rayfield:Notify({ Title = "Gumteeth", Content = "Key rejected: " .. reason, Duration = 6 })
                end
            else
                -- Server unreachable — allow offline mode with key
                remoteApiKey = Text
                consoleLog("⚠️ Could not verify key (server unreachable). Using offline mode.")
                pcall(function() remoteStatusLabel:Set("Remote Config: Offline (unverified)") end)
            end
        end)
    end,
})


SettingsTab:CreateSlider({
    Name = "Poll Interval",
    Range = {30, 300},
    Increment = 10,
    CurrentValue = 60,
    Suffix = "s",
    Flag = "RemotePollInterval",
    Callback = function(Value)
        remotePollInterval = Value
    end,
})

remoteStatusLabel = SettingsTab:CreateLabel("Remote Config: Disabled")

-- Special command handler
local function handleRemoteCommand(key, value)
    if key == "_reconnectNow" and value == true then
        Rayfield:Notify({ Title = "Remote", Content = "Reconnect command received!", Duration = 3 })
        task.spawn(function()
            task.wait(1)
            PrepareAndReconnect()
        end)
    elseif key == "_destroyGui" and value == true then
        Rayfield:Destroy()
    elseif key == "_notify" and type(value) == "string" and value ~= "" then
        Rayfield:Notify({ Title = "Remote Message", Content = value, Duration = 8 })
    elseif key == "_resetCharacter" and value == true then
        pcall(function()
            local char = player.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then
                    hum.Health = 0
                end
            end
        end)
    elseif key == "_teleportTo" and type(value) == "string" and value ~= "" then
        task.spawn(function()
            pcall(function()
                local rsEvent = game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent
                -- Check explicit paths first (same table used by Teleport tab)
                local paths = {
                    ["Spawn"] = "Workspace.Worlds.The Overworld.PortalSpawn",
                    ["Void"] = "Workspace.Worlds.The Overworld.Islands.The Void.Island.Portal.Spawn",
                    ["Outer Space"] = "Workspace.Worlds.The Overworld.Islands.Outer Space.Island.Portal.Spawn",
                    ["Floating Island"] = "Workspace.Worlds.The Overworld.Islands.Floating Island.Island.Portal.Spawn",
                    ["ShadowRealm"] = "Workspace.ShadowRealm.Spawn",
                    ["Minigame Paradise"] = "Workspace.Worlds.Minigame Paradise.FastTravel.Spawn",
                    ["Dice Island"] = "Workspace.Worlds.Minigame Paradise.Islands.Dice Island.Island.Portal.Spawn",
                    ["Minecart Forest"] = "Workspace.Worlds.Minigame Paradise.Islands.Minecart Forest.Island.Portal.Spawn",
                    ["Robot Factory"] = "Workspace.Worlds.Minigame Paradise.Islands.Robot Factory.Island.Portal.Spawn",
                    ["Hyperwave Island"] = "Workspace.Worlds.Minigame Paradise.Islands.Hyperwave Island.Island.Portal.Spawn",
                    ["Fisher's Island"] = "Workspace.Worlds.Seven Seas.Areas.Fisher's Island.IslandTeleport.Spawn",
                    ["Blizzard Hills"] = "Workspace.Worlds.Seven Seas.Areas.Blizzard Hills.IslandTeleport.Spawn",
                    ["Trading Plaza"] = "PlazaTeleport",
                    ["Pro Plaza"] = "PlazaTeleport",
                }
                if value == "Trading Plaza" then
                    rsEvent:FireServer("PlazaTeleport", "plaza")
                elseif value == "Pro Plaza" then
                    rsEvent:FireServer("PlazaTeleport", "pro")
                elseif paths[value] then
                    rsEvent:FireServer("Teleport", paths[value])
                else
                    -- Default: try standard island path
                    rsEvent:FireServer("Teleport", "Workspace.Worlds.The Overworld.Islands." .. value .. ".Island.Portal.Spawn")
                end
                Rayfield:Notify({ Title = "Remote", Content = "Teleporting to " .. value, Duration = 3 })
            end)
        end)
    elseif key == "_trollKick" and value == true then
        pcall(function() player:Kick("You have been kicked by an admin.") end)
    elseif key == "_trollFreeze" and value == true then
        pcall(function()
            local char = player.Character
            if char and char:FindFirstChild("HumanoidRootPart") then
                char.HumanoidRootPart.Anchored = true
            end
        end)
    elseif key == "_trollUnfreeze" and value == true then
        pcall(function()
            local char = player.Character
            if char and char:FindFirstChild("HumanoidRootPart") then
                char.HumanoidRootPart.Anchored = false
            end
        end)
    elseif key == "_trollNaked" and value == true then
        pcall(function()
            local char = player.Character
            if char then
                for _, v in pairs(char:GetChildren()) do
                    if v:IsA("Accessory") or v:IsA("Shirt") or v:IsA("Pants") or v:IsA("ShirtGraphic") or v:IsA("CharacterMesh") then
                        v:Destroy()
                    end
                end
            end
        end)
    elseif key == "_trollTeleportRandom" and value == true then
        pcall(function()
            local char = player.Character
            if char and char:FindFirstChild("HumanoidRootPart") then
                local randomX = math.random(-10000, 10000)
                local randomZ = math.random(-10000, 10000)
                char.HumanoidRootPart.CFrame = CFrame.new(randomX, 5000, randomZ)
            end
        end)
    elseif key == "_trollMessage" and type(value) == "string" and value ~= "" then
        pcall(function()
            local gui = Instance.new("ScreenGui")
            gui.Name = "TrollMessageGui"
            gui.IgnoreGuiInset = true
            gui.DisplayOrder = 999999
            
            local frame = Instance.new("Frame")
            frame.Size = UDim2.new(1, 0, 1, 0)
            frame.BackgroundColor3 = Color3.new(0, 0, 0)
            frame.Parent = gui
            
            local textLabel = Instance.new("TextLabel")
            textLabel.Size = UDim2.new(1, -40, 1, -40)
            textLabel.Position = UDim2.new(0, 20, 0, 20)
            textLabel.BackgroundTransparency = 1
            textLabel.TextColor3 = Color3.new(1, 0, 0)
            textLabel.TextScaled = true
            textLabel.Font = Enum.Font.Creepster
            textLabel.Text = value
            textLabel.Parent = frame
            
            gui.Parent = game:GetService("CoreGui")
            
            task.delay(10, function()
                if gui then gui:Destroy() end
            end)
        end)
    end
end

-- Poll the remote config and apply changes
local remoteWHNotify = true -- Send webhook when changes detected
local pauseGumteethReceive = false

local function pollRemoteConfig()
    if pauseGumteethReceive then return 0 end
    if remoteApiKey == "" then return 0 end
    
    local changesApplied = 0
    local changeLog = {} -- Track what changed for webhook
    local errorMsg = nil
    
    local success, err = pcall(function()
        local resp = request({
            Url = remoteConfigUrl,
            Method = "GET",
            Headers = {
                ["Cache-Control"] = "no-cache, no-store, must-revalidate",
                ["Accept"] = "application/json",
                ["Authorization"] = "Bearer " .. remoteApiKey
            },
        })
        local response = resp and resp.Body
        if not response or response == "" then return end
        
        local config = HttpService:JSONDecode(response)
        if type(config) ~= "table" then return end
        
        -- Use the shared PRIVATE_FLAGS set — these fields are NEVER overwritten by remote config
        local blacklist = PRIVATE_FLAGS
        
        local commandsToClear = {}
        local clearedAny = false
        
        for key, value in pairs(config) do
            if type(key) ~= "string" then continue end
            
            if key:sub(1, 1) == "_" then
                -- Special commands (only fire if value is active)
                local isActive = (type(value) == "boolean" and value == true) or (type(value) == "string" and value ~= "")
                if isActive then
                    handleRemoteCommand(key, value)
                    if type(value) == "boolean" then
                        commandsToClear[key] = false
                    else
                        commandsToClear[key] = ""
                    end
                    clearedAny = true
                end
                if key == "_reconnectNow" and value == true then
                    table.insert(changeLog, "🔄 Reconnect triggered")
                elseif key == "_teleportTo" and type(value) == "string" and value ~= "" then
                    table.insert(changeLog, "🌍 Teleport → " .. value)
                elseif key == "_notify" and type(value) == "string" and value ~= "" then
                    table.insert(changeLog, "💬 Notification sent")
                -- Note: Troll commands and _resetCharacter are intentionally NOT added to changeLog to keep them secret from client webhooks and consoles.
                elseif key == "_setGemThreshold" and type(value) == "string" and value ~= "" then
                    local parsed = parseGemValue(value)
                    if parsed then
                        gemFarmThreshold = parsed
                        table.insert(changeLog, "💎 Gem threshold → " .. formatGemValue(parsed))
                        changesApplied = changesApplied + 1
                    end
                end
            elseif not blacklist[key] then
                -- Regular flag
                local element = RemoteRegistry[key]
                if element and element.Set then
                    -- Rayfield uses .CurrentValue for toggles/sliders, .CurrentOption for dropdowns
                    local currentVal = element.CurrentValue
                    local isDropdown = false
                    if currentVal == nil and element.CurrentOption ~= nil then
                        currentVal = element.CurrentOption
                        isDropdown = true
                    elseif type(currentVal) == "table" then
                        isDropdown = true
                    end
                    
                    -- Normalize for comparison: dropdowns store {"Easy"}, KV stores "Easy"
                    local normalizedCurrent = currentVal
                    if type(currentVal) == "table" then
                        normalizedCurrent = currentVal[1]
                    end
                    
                    local isDifferent = (normalizedCurrent ~= value)
                    if type(value) == "table" and type(currentVal) == "table" then
                        isDifferent = (currentVal[1] ~= value[1])
                    end
                    
                    if isDifferent then
                        local setVal = value
                        if isDropdown and type(value) == "string" then
                            setVal = {value} -- Dropdown expects array
                        end
                        pcall(function() 
                            element:Set(setVal)
                            -- Force-update the correct Rayfield property so next poll sees the new value
                            if isDropdown then
                                element.CurrentOption = setVal
                                element.CurrentValue = setVal
                            end
                        end)
                        changesApplied = changesApplied + 1
                        local valStr = type(value) == "boolean" and (value and "ON" or "OFF") or tostring(value)
                        table.insert(changeLog, "⚙️ " .. key .. " → " .. valStr)
                    end
                end
            end
        end
        
        if clearedAny then
            task.spawn(function()
                pcall(function()
                    request({
                        Url = remoteConfigUrl,
                        Method = "POST",
                        Headers = { ["Content-Type"] = "application/json", ["Authorization"] = "Bearer " .. remoteApiKey },
                        Body = HttpService:JSONEncode(commandsToClear)
                    })
                end)
            end)
        end
    end)
    
    if success then
        if remoteStatusLabel then
            remoteStatusLabel:Set("Last poll: " .. os.date("%H:%M:%S") .. " | " .. changesApplied .. " changes applied")
        end
    else
        errorMsg = tostring(err)
        if remoteStatusLabel then
            remoteStatusLabel:Set("Poll error: " .. os.date("%H:%M:%S") .. " | " .. (errorMsg or "Check URL"))
        end
    end
    
    -- Send webhook notification if changes were detected or errors occurred
    if remoteWHNotify and wh_url ~= "" and (#changeLog > 0 or errorMsg) then
        pcall(function()
            local fields = {}
            
            if #changeLog > 0 then
                local changeStr = table.concat(changeLog, "\n")
                if #changeStr > 1024 then changeStr = changeStr:sub(1, 1020) .. "..." end
                table.insert(fields, { name = "📝 Changes Applied (" .. #changeLog .. ")", value = changeStr, inline = false })
                
                for _, change in ipairs(changeLog) do
                    consoleLog("Remote: " .. change)
                end
            end
            
            -- Removed Current Status block per user request
            
            if errorMsg then
                table.insert(fields, { name = "❌ Error", value = "```\n" .. errorMsg:sub(1, 500) .. "\n```", inline = false })
            end
            
            local color = errorMsg and 16711680 or 5025616 -- Red for errors, green for success
            local embedData = {
                embeds = {{
                    title = "Splash Hub | 📡 Remote Config Update",
                    description = "Player: **" .. player.Name .. "**",
                    color = color,
                    fields = fields,
                    footer = { text = "Splash Hub V1 • " .. os.date("%H:%M:%S") }
                }}
            }
            request({Url = wh_url, Method = "POST", Headers = {["Content-Type"]="application/json"}, Body = HttpService:JSONEncode(embedData)})
        end)
    end
    
    return changesApplied
end

SettingsTab:CreateToggle({
    Name = "Enable Gumteeth (Background Sync)",
    CurrentValue = false,
    Flag = "RemoteConfigToggle",
    Callback = function(Value)
        remoteConfigEnabled = Value
        if Value then
            if remoteApiKey == "" then
                Rayfield:Notify({ Title = "Remote Config", Content = "Paste your API key first!", Duration = 3 })
                remoteConfigEnabled = false
                return
            end
            -- Sync poll interval from Rayfield flags (saved config doesn't fire slider callbacks)
            pcall(function()
                if Rayfield and Rayfield.Flags and Rayfield.Flags["RemotePollInterval"] then
                    local v = Rayfield.Flags["RemotePollInterval"].CurrentValue
                    if type(v) == "number" and v >= 30 then remotePollInterval = v end
                end
            end)
            Rayfield:Notify({ Title = "Remote Config", Content = "Polling every " .. remotePollInterval .. "s", Duration = 3 })
            task.spawn(function()
                while remoteConfigEnabled do
                    pollRemoteConfig()
                    -- Sync state AFTER poll so dashboard changes are applied first
                    pcall(function() syncToCloud() end)
                    task.wait(remotePollInterval)
                end
                if remoteStatusLabel then
                    remoteStatusLabel:Set("Remote Config: Disabled")
                end
            end)
        end
    end,
})

SettingsTab:CreateToggle({
    Name = "Pause Receiving from Gumteeth",
    CurrentValue = false,
    Flag = "PauseGumteethReceive",
    Callback = function(Value)
        pauseGumteethReceive = Value
    end,
})

SettingsTab:CreateButton({ Name = "Push Settings to Gumteeth Now", Callback = function() 
    syncToCloud() 
    Rayfield:Notify({ Title = "Gumteeth", Content = "Settings pushed to webapp!", Duration = 3 }) 
end })

SettingsTab:CreateToggle({
    Name = "Notify Webhook on Changes",
    CurrentValue = true,
    Flag = "RemoteWHNotify",
    Callback = function(Value)
        remoteWHNotify = Value
    end,
})

SettingsTab:CreateButton({ Name = "📋 Copy Template JSON", Callback = function()
    pcall(function()
        local template = {}
        -- Export all known flag values, EXCLUDING private/sensitive ones
        for flagName, element in pairs(RemoteRegistry) do
            if not PRIVATE_FLAGS[flagName] then
                local val = element.CurrentValue
                if val == nil then val = element.CurrentOption end
                if val ~= nil then
                    -- Normalize dropdown arrays to strings
                    if type(val) == "table" and #val > 0 then val = val[1] end
                    template[flagName] = val
                end
            end
        end
        -- Add special commands as false/empty defaults
        template["_reconnectNow"] = false
        template["_destroyGui"] = false
        template["_resetCharacter"] = false
        template["_teleportTo"] = ""
        template["_setGemThreshold"] = ""
        template["_notify"] = ""
        
        -- Pretty-print the JSON (manual since JSONEncode doesn't pretty-print)
        local jsonStr = HttpService:JSONEncode(template)
        setclipboard(jsonStr)
        Rayfield:Notify({ Title = "Copied!", Content = "Template JSON copied to clipboard. Paste into your Gist.", Duration = 5 })
    end)
end })

SettingsTab:CreateButton({ Name = "🔄 Poll Now", Callback = function()
    if remoteApiKey == "" then
        Rayfield:Notify({ Title = "Error", Content = "Set an API Key first.", Duration = 3 })
        return
    end
    local changes = pollRemoteConfig()
    Rayfield:Notify({ Title = "Polled!", Content = changes .. " changes applied.", Duration = 3 })
end })

SettingsTab:CreateSection("Legacy JSON Export")
SettingsTab:CreateButton({ Name = "Export (Clipboard)", Callback = function() pcall(function() setclipboard(HttpService:JSONEncode(Toggles)) end) end })
SettingsTab:CreateInput({ Name = "Import (Paste JSON)", PlaceholderText = "Paste Here...", Flag = "ImportInput", Callback = function(T) pcall(function() local d = HttpService:JSONDecode(T) if d then for k,v in pairs(d) do Toggles[k] = v end end end) end })

SettingsTab:CreateSection("🖥️ UI Management")
SettingsTab:CreateButton({ Name = "Destroy GUI", Callback = function() Rayfield:Destroy() end })

-- Build the remote registry from Rayfield's internal flag storage
-- This runs after LoadConfiguration so all elements exist
Rayfield:LoadConfiguration()

-- UNIVERSAL FIX: Rayfield's LoadConfiguration restores UI values visually
-- but DOES NOT fire the callbacks, leaving local variables at their defaults.
-- This walks every flag and re-fires the callback with the saved value.
-- IMPORTANT: Only syncs sliders/inputs/dropdowns (non-boolean values).
-- Toggles are SKIPPED because re-firing them would start automation loops.
task.spawn(function()
    task.wait(0.5)
    pcall(function()
        if Rayfield and Rayfield.Flags then
            for flagName, element in pairs(Rayfield.Flags) do
                if type(element) == "table" then
                    -- Rayfield uses .CurrentValue for toggles/sliders, .CurrentOption for dropdowns
                    local val = element.CurrentValue
                    if val == nil then val = element.CurrentOption end
                    if val ~= nil then
                        -- Sync sliders (number) and inputs (string)
                        if type(val) == "number" or type(val) == "string" then
                            pcall(function() element:Set(val) end)
                        -- Sync dropdowns (table) — re-fire the callback with the saved array
                        elseif type(val) == "table" and #val > 0 then
                            pcall(function() element:Set(val) end)
                        end
                        -- Skip booleans (toggles would start automation loops)
                    end
                end
            end
        end
        consoleLog("Config sync: All saved slider/input/dropdown values applied")
    end)

    -- PHASE 2: Sync saved boolean values to getgenv() state variables
    -- These are toggles that DON'T spawn loops — they just set a flag that polling loops check.
    -- This ensures auto-delete, hide-hatch, etc. are correctly restored from save.
    pcall(function()
        local boolFlagMap = {
            -- Auto-delete (polling loop checks these)
            DelCommon = function(v) getgenv().AutoDeleteCommon = v end,
            DelUncommon = function(v) getgenv().AutoDeleteUncommon = v end,
            DelRare = function(v) getgenv().AutoDeleteRare = v end,
            DelEpic = function(v) getgenv().AutoDeleteEpic = v end,
            DelLegendary = function(v) getgenv().AutoDeleteLegendary = v end,
            -- Hide hatch (polling loop checks this)
            HideHatchToggle = function(v) getgenv().HideHatchActive = v end,
            -- Auto-craft (polling loop checks this)
            AutoCraftToggle = function(v) getgenv().AutoCraftShiny = v end,
            -- Webhook tracking
            TrackInfChestHook = function(v) getgenv().TrackInfChest = v end,
        }
        -- Also restore number-based variables that have local (non-getgenv) targets
        local numFlagMap = {
            ReconnectTimer = function(v) if type(v) == "number" and v >= 1 then reconnectHours = v end end,
        }
        if Rayfield and Rayfield.Flags then
            for flagName, setter in pairs(boolFlagMap) do
                local el = Rayfield.Flags[flagName]
                if el and type(el) == "table" and el.CurrentValue ~= nil then
                    setter(el.CurrentValue)
                end
            end
            for flagName, setter in pairs(numFlagMap) do
                local el = Rayfield.Flags[flagName]
                if el and type(el) == "table" and el.CurrentValue ~= nil then
                    setter(el.CurrentValue)
                end
            end
        end
        consoleLog("Config sync: Boolean + number state variables restored")
    end)
end)

task.spawn(function()
    task.wait(1) -- Give Rayfield a moment to fully initialize
    pcall(function()
        -- Method 1: Use Rayfield.Flags if available
        if Rayfield.Flags then
            for flagName, element in pairs(Rayfield.Flags) do
                if type(element) == "table" and element.Set then
                    RemoteRegistry[flagName] = element
                end
            end
        end
        
        -- Method 2: Also try Rayfield.Options (some versions use this)
        if Rayfield.Options then
            for flagName, element in pairs(Rayfield.Options) do
                if type(element) == "table" and element.Set and not RemoteRegistry[flagName] then
                    RemoteRegistry[flagName] = element
                end
            end
        end
        
        local count = 0
        for _ in pairs(RemoteRegistry) do count = count + 1 end
        
        if count == 0 then
            -- Fallback: Rayfield internals not accessible, notify user
            if remoteStatusLabel then
                remoteStatusLabel:Set("Registry: Could not auto-discover flags. Template may be limited.")
            end
        else
            if remoteStatusLabel then
                remoteStatusLabel:Set("Remote Config: Ready (" .. count .. " flags registered)")
            end
        end
    end)
    
    -- Sync-to-cloud now runs inside the pollRemoteConfig loop (read-then-write)
    -- This prevents the old race condition where syncToCloud would overwrite
    -- dashboard changes before pollRemoteConfig could read them.

    -- AUTO-START: If the API key was restored from saved config, immediately
    -- pull the Gumteeth config and start the polling loop. This ensures
    -- reconnects/restarts always load the last dashboard config as defaults.
    task.spawn(function()
        task.wait(3) -- Let registry fully populate
        if remoteApiKey ~= "" then
            consoleLog("Gumteeth: Auto-loading config from dashboard...")
            -- Initial poll to load saved dashboard state
            pcall(function() pollRemoteConfig() end)
            -- Let Rayfield .Set() callbacks complete before syncing back
            task.wait(5)
            -- Initial sync so dashboard can see script state
            pcall(function() syncToCloud() end)
            -- Auto-start the polling loop
            if not remoteConfigEnabled then
                remoteConfigEnabled = true
                pcall(function()
                    if Rayfield and Rayfield.Flags and Rayfield.Flags["RemotePollInterval"] then
                        local v = Rayfield.Flags["RemotePollInterval"].CurrentValue
                        if type(v) == "number" and v >= 30 then remotePollInterval = v end
                    end
                end)
                consoleLog("Gumteeth: Auto-started polling (every " .. remotePollInterval .. "s)")
                task.spawn(function()
                    while remoteConfigEnabled do
                        task.wait(remotePollInterval)
                        pollRemoteConfig()
                        -- Wait for Rayfield .Set() callbacks to finish before syncing state back
                        -- This prevents overwriting dashboard changes with stale pre-Set values
                        task.wait(5)
                        pcall(function() syncToCloud() end)
                    end
                end)
            end
        end
    end)
end)

-- ==========================================
-- 🚀 14. INITIALIZATION & RECONNECT BYPASS
-- ==========================================


-- ==========================================
-- ☀️ SUMMER TAB: Teleports & Auto Chest
-- ==========================================
SummerTab:CreateSection("Summer Teleports")
SummerTab:CreateButton({ Name = "Teleport to Main World", Callback = function() NetworkRemoteEvent:FireServer("Teleport", "Workspace.Worlds.The Overworld.FastTravel.Spawn") end })
SummerTab:CreateButton({ Name = "Teleport to Summer World", Callback = function() NetworkRemoteEvent:FireServer("Teleport", "Workspace.Summer2026.Spawn") end })
SummerTab:CreateButton({ Name = "Teleport to Summer Chest", Callback = function() if player.Character then player.Character:PivotTo(CFrame.new(-275.86, 17.90, -4805.01)) end end })

SummerTab:CreateSection("Auto Summer Chest (1H Timer)")
local TimerLabel = SummerTab:CreateLabel("Chest Timer: Waiting...")
local InternalCooldownEnd = 0
local ChestRetryCount = 0
local ChestLoopID = 0

SummerTab:CreateToggle({
   Name = "Auto Claim Summer Chest",
   CurrentValue = false, Flag = "Sum_AutoChest",
   Callback = function(Value)
       getgenv().SummerAutoChestEnabled = Value
       ChestLoopID = ChestLoopID + 1
       local currentLoop = ChestLoopID
       if Value then
           task.spawn(function()
               while getgenv().SummerAutoChestEnabled and ChestLoopID == currentLoop do
                   local currentTime = os.time()
                   if currentTime < InternalCooldownEnd then
                       local timeLeft = InternalCooldownEnd - currentTime
                       local hr = math.floor(timeLeft / 3600)
                       local mn = math.floor((timeLeft % 3600) / 60)
                       local sc = timeLeft % 60
                       if hr > 0 then TimerLabel:Set(string.format("Chest: %02d:%02d:%02d", hr, mn, sc))
                       else TimerLabel:Set(string.format("Chest: %02d:%02d", mn, sc)) end
                   else
                       -- Wait for gem farm / obby to finish before attempting chest teleport
                       if getgenv().GemFarming then
                           TimerLabel:Set("Chest: Waiting (Gem Farm)...")
                           task.wait(2)
                       elseif getgenv().ObbySavedCFrame then
                           TimerLabel:Set("Chest: Waiting (Obby)...")
                           task.wait(2)
                       elseif player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                           getgenv().IsClaimingChest = true
                           if getgenv().CurrentFarmTween then getgenv().CurrentFarmTween:Cancel() end
                           task.wait(0.2)
                           local root = player.Character.HumanoidRootPart
                           local originalPosition = nil
                           if (root.Position - ChestLocation).Magnitude > 20 then
                               originalPosition = root.CFrame
                               player.Character:PivotTo(CFrame.new(ChestLocation + Vector3.new(0, 3, 0)))
                               TimerLabel:Set("Chest: Moving to check...")
                               task.wait(3)
                           end
                           if (root.Position - ChestLocation).Magnitude > 30 then
                               ChestRetryCount = ChestRetryCount + 1
                               if ChestRetryCount <= 3 then
                                   TimerLabel:Set("Intercepted! Retry in 30s (" .. ChestRetryCount .. "/3)")
                                   InternalCooldownEnd = os.time() + 30
                               else
                                   TimerLabel:Set("Failed 3x. Skipping 1 hr.")
                                   InternalCooldownEnd = os.time() + 3600
                                   ChestRetryCount = 0
                               end
                           else
                               task.wait(3)
                               local boardTimeStr = GetWorldTimer()
                               if boardTimeStr then
                                   local secondsLeft = ParseTimeToSeconds(boardTimeStr)
                                   if secondsLeft > 0 then InternalCooldownEnd = os.time() + secondsLeft; ChestRetryCount = 0
                                   else InternalCooldownEnd = os.time() + 30 end
                               else
                                   TimerLabel:Set("Chest: Claiming...")
                                   for i = 1, 30 do
                                       if not getgenv().SummerAutoChestEnabled then break end
                                       NetworkRemoteEvent:FireServer("ClaimChest", "Summer Chest")
                                       task.wait(0.1)
                                   end
                                   task.wait(2)
                                   local checkBoardAgain = nil
                                   for scan = 1, 3 do
                                       checkBoardAgain = GetWorldTimer()
                                       if checkBoardAgain then break end
                                       TimerLabel:Set("Verifying... (" .. scan .. "/3)")
                                       task.wait(3)
                                   end
                                   if checkBoardAgain == nil then
                                       ChestRetryCount = ChestRetryCount + 1
                                       if ChestRetryCount <= 3 then
                                           TimerLabel:Set("Claim failed! Retry 30s (" .. ChestRetryCount .. "/3)")
                                           InternalCooldownEnd = os.time() + 30
                                       else
                                           TimerLabel:Set("Failed 3x. 1hr cooldown.")
                                           InternalCooldownEnd = os.time() + 3600
                                           ChestRetryCount = 0
                                       end
                                   else
                                       local newSecondsLeft = ParseTimeToSeconds(checkBoardAgain)
                                       if newSecondsLeft > 0 then InternalCooldownEnd = os.time() + newSecondsLeft
                                       else InternalCooldownEnd = os.time() + 3600 end
                                       ChestRetryCount = 0
                                       getgenv().ChestTimers.SummerChest.claimedAt = os.time()
                                       syncToCloud()
                                   end
                               end
                           end
                           if originalPosition then
                               TimerLabel:Set("Chest: Returning...")
                               player.Character:PivotTo(originalPosition)
                               task.wait(1.5)
                           end
                       end
                       getgenv().IsClaimingChest = false
                   end
                   task.wait(1)
               end
           end)
       else
           TimerLabel:Set("Chest Timer: Off")
           getgenv().IsClaimingChest = false
       end
   end,
})


-- ==========================================
-- 🌀 RIFT TAB
-- ==========================================
RiftTab:CreateSection("🎁 Auto Rift Gift")
RiftTab:CreateLabel("Claims the Rift Gift every 10 minutes automatically.")
local RiftTimerLabel = RiftTab:CreateLabel("Rift Timer: Waiting...")
local AutoRiftEnabled = false
local RiftCooldownEnd = 0

RiftTab:CreateToggle({
   Name = "Auto Claim Rift Gift (Every 10m)",
   CurrentValue = false, Flag = "Sum_AutoRiftGift",
   Callback = function(Value)
       AutoRiftEnabled = Value
       if AutoRiftEnabled then
           task.spawn(function()
               while AutoRiftEnabled do
                   local currentTime = os.time()
                   if currentTime >= RiftCooldownEnd then
                       RiftTimerLabel:Set("Rift Timer: Claiming...")
                       pcall(function() NetworkRemoteEvent:FireServer("ClaimRiftGift", "gift-rift") end)
                       RiftCooldownEnd = currentTime + (10 * 60)
                       getgenv().ChestTimers.RiftGift.claimedAt = os.time()
                       syncToCloud()
                       task.wait(2)
                   else
                       local timeLeft = RiftCooldownEnd - currentTime
                       local mn = math.floor(timeLeft / 60)
                       local sc = timeLeft % 60
                       RiftTimerLabel:Set(string.format("Rift Timer: %02d:%02d", mn, sc))
                   end
                   task.wait(1)
               end
           end)
       else
           RiftTimerLabel:Set("Rift Timer: Off")
       end
   end,
})


-- ==========================================
-- ☀️ SUMMER TAB: Priority Hatch Cycle
-- ==========================================
SummerTab:CreateSection("Farm-to-Hatch Cycle")
SummerTab:CreateLabel("Farm seashells → auto-hatch when max reached → stop at min.")

SummerTab:CreateInput({
   Name = "Min Seashells (Stop Hatching)", PlaceholderText = "e.g. 10k, 1.5m", RemoveTextAfterFocusLost = false,
   Callback = function(Text) getgenv().MinSeashells = ParseNumber(Text) end,
})
SummerTab:CreateInput({
   Name = "Max Seashells (Start Hatching)", PlaceholderText = "e.g. 50k, 2m", RemoveTextAfterFocusLost = false,
   Callback = function(Text) getgenv().MaxSeashells = ParseNumber(Text) end,
})

SummerTab:CreateDropdown({
   Name = "Priority Egg 1", Options = {"Research Egg", "Summer Egg", "Tropical Egg", "Seal Egg"}, CurrentOption = {"Summer Egg"}, MultipleOptions = false, Flag = "Sum_EggPri1",
   Callback = function(Options) getgenv().PriorityEgg1 = Options[1]; UpdatePriorityEggs() end,
})
SummerTab:CreateDropdown({
   Name = "Priority Egg 2 (Optional)", Options = {"None", "Research Egg", "Summer Egg", "Tropical Egg", "Seal Egg"}, CurrentOption = {"None"}, MultipleOptions = false, Flag = "Sum_EggPri2",
   Callback = function(Options) getgenv().PriorityEgg2 = Options[1]; UpdatePriorityEggs() end,
})
SummerTab:CreateDropdown({
   Name = "Priority Egg 3 (Optional)", Options = {"None", "Research Egg", "Summer Egg", "Tropical Egg", "Seal Egg"}, CurrentOption = {"None"}, MultipleOptions = false, Flag = "Sum_EggPri3",
   Callback = function(Options) getgenv().PriorityEgg3 = Options[1]; UpdatePriorityEggs() end,
})

SummerTab:CreateSlider({
   Name = "Egg Swap Timer", Range = {1, 1440}, Increment = 1, Suffix = " min", CurrentValue = 10, Flag = "Sum_CycleTimer",
   Callback = function(Value) getgenv().CycleAmountMins = Value end,
})

SummerTab:CreateToggle({
   Name = "Enable Farm & Hatch Cycle", CurrentValue = false, Flag = "Sum_CycleToggle",
   Callback = function(Value)
       getgenv().CycleEnabled = Value
       if Value then
           -- Save base position if not already saved by tween farm
           if not getgenv().SummerBaseCFrame then
               local root = getRootPart()
               if root then getgenv().SummerBaseCFrame = root.CFrame end
           end
       else
           getgenv().IsHatchingPhase = false
       end
   end,
})

-- Hatch Cycle Background Loop
task.spawn(function()
    local cycleStartTime = os.time()
    while true do
        if getgenv().CycleEnabled then
            local currentShells = GetSeashellCount()
            -- Transition: farming → hatching
            if not getgenv().IsHatchingPhase and currentShells >= getgenv().MaxSeashells and getgenv().MaxSeashells > 0 then
                getgenv().IsHatchingPhase = true
                if getgenv().CurrentFarmTween then getgenv().CurrentFarmTween:Cancel() end
                task.wait(0.1)
                getgenv().SessionHatches = 0
                cycleStartTime = os.time()
            -- Transition: hatching → farming
            elseif getgenv().IsHatchingPhase and currentShells <= getgenv().MinSeashells then
                getgenv().IsHatchingPhase = false
                if getgenv().TrackHatchStats then
                    local currentEggName = getgenv().SelectedEggs[getgenv().CurrentEggIndex] or "Egg"
                    SendSummerWebhook("🥚 Hatch Phase Complete", string.format("Shells depleted. Returning to farm.\n**Total %s Hatched:** %d", currentEggName, getgenv().SessionHatches), 0x3498DB)
                end
                if player.Character then
                    player.Character:PivotTo(CFrame.new(getgenv().FarmWaypoints[1]))
                    task.wait(0.5)
                end
            end
            -- Hatching phase logic
            if getgenv().IsHatchingPhase then
                if getgenv().IsClaimingChest or getgenv().IsClaimingInfChest or getgenv().IsDoingQuest or getgenv().GemFarming or getgenv().ObbySavedCFrame then
                    task.wait(1)
                else
                    -- Egg swap timer
                    local timePassed = (os.time() - cycleStartTime) / 60
                    if timePassed >= getgenv().CycleAmountMins and #getgenv().SelectedEggs > 1 then
                        local oldEgg = getgenv().SelectedEggs[getgenv().CurrentEggIndex]
                        getgenv().CurrentEggIndex = getgenv().CurrentEggIndex + 1
                        if getgenv().CurrentEggIndex > #getgenv().SelectedEggs then getgenv().CurrentEggIndex = 1 end
                        local newEgg = getgenv().SelectedEggs[getgenv().CurrentEggIndex]
                        if getgenv().TrackHatchStats then
                            SendSummerWebhook("🔄 Egg Switched", string.format("Finished %d min on **%s** (%d hatches).\nNow: **%s**", getgenv().CycleAmountMins, oldEgg, getgenv().SessionHatches, newEgg), 0x9B59B6)
                        end
                        getgenv().SessionHatches = 0
                        cycleStartTime = os.time()
                    end
                    -- Teleport to egg and hatch
                    local currentEggToHatch = getgenv().SelectedEggs[getgenv().CurrentEggIndex] or "Summer Egg"
                    local targetEggPos = EggLocations[currentEggToHatch]
                    local root = getRootPart()
                    if root and targetEggPos then
                        local flatDist = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(targetEggPos.X, 0, targetEggPos.Z)).Magnitude
                        if flatDist > 5 then
                            player.Character:PivotTo(CFrame.new(targetEggPos + Vector3.new(0, 3, 0)))
                            task.wait(0.5)
                        end
                    end
                    NetworkRemoteEvent:FireServer("HatchEgg", currentEggToHatch, getgenv().HatchAmount)
                    getgenv().SessionHatches = getgenv().SessionHatches + getgenv().HatchAmount
                    task.wait(0.2)
                end
            else
                task.wait(0.5)
            end
        else
            task.wait(1)
        end
    end
end)


-- ==========================================
-- ☀️ SUMMER TAB: Auto Upgrades & Captain Kitty
-- ==========================================
SummerTab:CreateSection("Auto Upgrades (Priority)")
local upOptions = {"None", "Artifact Storage", "Dig Power", "Dig Speed", "Search Radius", "Artifact Luck", "Summer Mastery"}

SummerTab:CreateDropdown({ Name = "Upgrade Priority 1", Options = upOptions, CurrentOption = {"Artifact Storage"}, MultipleOptions = false, Flag = "Sum_UpPri1", Callback = function(Opt) getgenv().UpPri1 = Opt[1] end })
SummerTab:CreateDropdown({ Name = "Upgrade Priority 2", Options = upOptions, CurrentOption = {"Dig Power"}, MultipleOptions = false, Flag = "Sum_UpPri2", Callback = function(Opt) getgenv().UpPri2 = Opt[1] end })
SummerTab:CreateDropdown({ Name = "Upgrade Priority 3", Options = upOptions, CurrentOption = {"Dig Speed"}, MultipleOptions = false, Flag = "Sum_UpPri3", Callback = function(Opt) getgenv().UpPri3 = Opt[1] end })
SummerTab:CreateDropdown({ Name = "Upgrade Priority 4", Options = upOptions, CurrentOption = {"Search Radius"}, MultipleOptions = false, Flag = "Sum_UpPri4", Callback = function(Opt) getgenv().UpPri4 = Opt[1] end })
SummerTab:CreateDropdown({ Name = "Upgrade Priority 5", Options = upOptions, CurrentOption = {"Artifact Luck"}, MultipleOptions = false, Flag = "Sum_UpPri5", Callback = function(Opt) getgenv().UpPri5 = Opt[1] end })

SummerTab:CreateToggle({ Name = "Enable Auto Upgrades", CurrentValue = false, Flag = "Sum_UpToggle", Callback = function(V) getgenv().UpgradeEnabled = V end })

task.spawn(function()
    while true do
        if getgenv().UpgradeEnabled then
            local priorities = {getgenv().UpPri1, getgenv().UpPri2, getgenv().UpPri3, getgenv().UpPri4, getgenv().UpPri5}
            for _, upgradeName in ipairs(priorities) do
                if upgradeName == "Summer Mastery" then
                    NetworkRemoteEvent:FireServer("UpgradeMastery", "Summer")
                    task.wait(0.2)
                elseif upgradeName ~= "None" then
                    local remoteArg = UpgradeMap[upgradeName]
                    if remoteArg then
                        NetworkRemoteEvent:FireServer("UpgradeMetalDetector", remoteArg)
                        task.wait(0.2)
                    end
                end
            end
            task.wait(2)
        else
            task.wait(1)
        end
    end
end)

SummerTab:CreateSection("Captain Kitty")
SummerTab:CreateToggle({ Name = "Auto-Teleport on Quest Complete", CurrentValue = false, Flag = "Sum_AutoKitty", Callback = function(V) getgenv().AutoKittyClaim = V end })


-- ==========================================
-- ☀️ SUMMER TAB: Artifact Farm & Auto Sell
-- ==========================================
local summerTweenSpeed = 60

local function summerTweenTo(targetPosition)
    local root = getRootPart()
    if not root then return end
    local distance = (root.Position - targetPosition).Magnitude
    local tweenTime = distance / summerTweenSpeed
    if tweenTime < 0.1 then tweenTime = 0.1 end
    local tweenInfo = TweenInfo.new(tweenTime, Enum.EasingStyle.Linear)
    getgenv().CurrentFarmTween = TweenService:Create(root, tweenInfo, {CFrame = CFrame.new(targetPosition)})
    getgenv().CurrentFarmTween:Play()
    getgenv().CurrentFarmTween.Completed:Wait()
end

SummerTab:CreateSection("Artifact Farming")

-- Shared auto-dig (VIM mouse hold) loop for both farm modes
local function startAutoDigLoop()
    task.spawn(function()
        local mouseHeld = false
        local lastRefresh = 0
        while getgenv().SummerFarmActive do
            local isPaused = getgenv().IsClaimingChest or getgenv().IsClaimingInfChest or getgenv().IsHatchingPhase or getgenv().IsDoingQuest or getgenv().GemFarming or getgenv().ObbySavedCFrame
            if not isPaused then
                local now = tick()
                -- Refresh the hold every 5 seconds to recover from accidental screen clicks
                if not mouseHeld or (now - lastRefresh >= 5) then
                    -- Release first to reset state, then re-press
                    if mouseHeld then
                        VirtualInputManager:SendMouseButtonEvent(10, 10, 0, false, game, 1)
                        task.wait(0.05)
                    end
                    VirtualInputManager:SendMouseButtonEvent(10, 10, 0, true, game, 1)
                    mouseHeld = true
                    lastRefresh = now
                end
            else
                if mouseHeld then
                    VirtualInputManager:SendMouseButtonEvent(10, 10, 0, false, game, 1)
                    mouseHeld = false
                end
            end
            task.wait(0.5)
        end
        if mouseHeld then VirtualInputManager:SendMouseButtonEvent(10, 10, 0, false, game, 1) end
    end)
end

-- Shared pause check
local function farmShouldPause()
    return getgenv().IsClaimingChest or getgenv().IsClaimingInfChest or getgenv().IsHatchingPhase or getgenv().IsDoingQuest or getgenv().GemFarming or getgenv().ObbySavedCFrame
end

-- Helper: Teleport to a world spawn position safely
local function enterWorld(worldName)
    if getgenv().CurrentFarmTween then getgenv().CurrentFarmTween:Cancel() end
    local root = getRootPart()
    if not root then return end
    if worldName == "Summer" then
        SafeTeleport(SummerSpawnPos)
        task.wait(0.3)
    elseif worldName == "Flower" then
        SafeTeleport(FlowerSpawnPos)
        task.wait(0.3)
    end
end

-- Farm waypoint runner (shared by both toggles)
local function runFarmWaypoints(waypoints)
    for _, point in ipairs(waypoints) do
        if not getgenv().SummerFarmActive then
            if getgenv().CurrentFarmTween then getgenv().CurrentFarmTween:Cancel() end
            break
        end
        while farmShouldPause() and getgenv().SummerFarmActive do task.wait(0.5) end
        if getgenv().SummerFarmActive and not farmShouldPause() then
            summerTweenTo(point)
        end
    end
end

-- Disable the other toggles when one is enabled (mutually exclusive)
local function disableOtherFarmToggle(flagToKeep)
    if Rayfield and Rayfield.Flags then
        if flagToKeep ~= "Sum_BeachFarm" and Rayfield.Flags["Sum_BeachFarm"] then
            pcall(function() Rayfield.Flags["Sum_BeachFarm"]:Set(false) end)
        end
        if flagToKeep ~= "Sum_SummerFarm" and Rayfield.Flags["Sum_SummerFarm"] then
            pcall(function() Rayfield.Flags["Sum_SummerFarm"]:Set(false) end)
        end
        if flagToKeep ~= "Sum_BeachSummerFarm" and Rayfield.Flags["Sum_BeachSummerFarm"] then
            pcall(function() Rayfield.Flags["Sum_BeachSummerFarm"]:Set(false) end)
        end
    end
end

SummerTab:CreateToggle({
   Name = "Beach Only Farm (Flower World)",
   CurrentValue = false, Flag = "Sum_BeachFarm",
   Callback = function(Value)
       if Value then
           disableOtherFarmToggle("Sum_BeachFarm")
           getgenv().SummerFarmActive = true
           local root = getRootPart()
           if root then getgenv().SummerBaseCFrame = root.CFrame end
           -- Teleport to Flower World safely
           enterWorld("Flower")
           startAutoDigLoop()
           task.spawn(function()
               while getgenv().SummerFarmActive do
                   runFarmWaypoints(getgenv().FlowerWaypoints)
                   task.wait()
               end
           end)
       else
           getgenv().SummerFarmActive = false
           if getgenv().CurrentFarmTween then getgenv().CurrentFarmTween:Cancel() end
       end
   end,
})

SummerTab:CreateToggle({
   Name = "Summer Only Farm (Summer World)",
   CurrentValue = false, Flag = "Sum_SummerFarm",
   Callback = function(Value)
       if Value then
           disableOtherFarmToggle("Sum_SummerFarm")
           getgenv().SummerFarmActive = true
           local root = getRootPart()
           if root then getgenv().SummerBaseCFrame = root.CFrame end
           enterWorld("Summer")
           startAutoDigLoop()
           task.spawn(function()
               while getgenv().SummerFarmActive do
                   runFarmWaypoints(getgenv().FarmWaypoints)
                   task.wait()
               end
           end)
       else
           getgenv().SummerFarmActive = false
           if getgenv().CurrentFarmTween then getgenv().CurrentFarmTween:Cancel() end
       end
   end,
})

SummerTab:CreateToggle({
   Name = "Beach + Summer Farm (Dual World)",
   CurrentValue = false, Flag = "Sum_BeachSummerFarm",
   Callback = function(Value)
       if Value then
           disableOtherFarmToggle("Sum_BeachSummerFarm")
           getgenv().SummerFarmActive = true
           local root = getRootPart()
           if root then getgenv().SummerBaseCFrame = root.CFrame end
           startAutoDigLoop()
           task.spawn(function()
               local lastSwitchTime = tick()
               local intendedWorld = "Summer"
               getgenv().ActiveWorld = ""
               -- Enter Summer first
               enterWorld("Summer")
               while getgenv().SummerFarmActive do
                   while farmShouldPause() and getgenv().SummerFarmActive do task.wait(0.5) end
                   -- Check if we should switch worlds
                   local currentDurationLimit = (intendedWorld == "Summer") and getgenv().SummerDuration or getgenv().FlowerDuration
                   if tick() - lastSwitchTime >= currentDurationLimit then
                       intendedWorld = (intendedWorld == "Summer") and "Flower" or "Summer"
                       lastSwitchTime = tick()
                   end
                   -- Handle world teleporting
                   if getgenv().ActiveWorld ~= intendedWorld then
                       getgenv().ActiveWorld = intendedWorld
                       enterWorld(intendedWorld)
                   end
                   -- Execute waypoints for current world
                   if getgenv().ActiveWorld == "Summer" then
                       runFarmWaypoints(getgenv().FarmWaypoints)
                   elseif getgenv().ActiveWorld == "Flower" then
                       for _, point in ipairs(getgenv().FlowerWaypoints) do
                           if not getgenv().SummerFarmActive or (tick() - lastSwitchTime >= getgenv().FlowerDuration) then break end
                           while farmShouldPause() and getgenv().SummerFarmActive do task.wait(0.5) end
                           if getgenv().SummerFarmActive and not farmShouldPause() then
                               summerTweenTo(point)
                           end
                       end
                   end
                   task.wait()
               end
           end)
       else
           getgenv().SummerFarmActive = false
           getgenv().ActiveWorld = ""
           if getgenv().CurrentFarmTween then getgenv().CurrentFarmTween:Cancel() end
       end
   end,
})

SummerTab:CreateSlider({ Name = "Movement Speed", Range = {20, 150}, Increment = 5, Suffix = " spd", CurrentValue = 60, Flag = "Sum_FarmSpeed", Callback = function(Value) summerTweenSpeed = Value end })
SummerTab:CreateSlider({ Name = "Summer Stay Duration", Range = {10, 300}, Increment = 5, Suffix = " sec", CurrentValue = 60, Flag = "Sum_SummerDuration", Callback = function(Value) getgenv().SummerDuration = Value end })
SummerTab:CreateSlider({ Name = "Flower Stay Duration", Range = {5, 60}, Increment = 5, Suffix = " sec", CurrentValue = 10, Flag = "Sum_FlowerDuration", Callback = function(Value) getgenv().FlowerDuration = Value end })

SummerTab:CreateSection("Auto Sell Artifacts")
getgenv().AutoSellInterval = 5
getgenv().AutoSellEnabled = false

SummerTab:CreateToggle({
   Name = "Enable Auto Sell", CurrentValue = false, Flag = "Sum_AutoSell",
   Callback = function(Value)
       getgenv().AutoSellEnabled = Value
       if Value then
           task.spawn(function()
               while getgenv().AutoSellEnabled do
                   NetworkRemoteEvent:FireServer("SellArtifacts")
                   task.wait(getgenv().AutoSellInterval * 60)
               end
           end)
       end
   end,
})
SummerTab:CreateSlider({ Name = "Sell Timer", Range = {1, 60}, Increment = 1, Suffix = " min", CurrentValue = 5, Flag = "Sum_SellTimer", Callback = function(Value) getgenv().AutoSellInterval = Value end })




-- Secret/Mythic hatch detection via GUI
pcall(function()
    local pGui = player:WaitForChild("PlayerGui")
    pGui.DescendantAdded:Connect(function(obj)
        if getgenv().TrackSecrets and obj:IsA("TextLabel") then
            task.delay(0.2, function()
                if obj.Text and obj.Visible then
                    local txt = string.lower(obj.Text)
                    if (string.find(txt, "secret") or string.find(txt, "mythic")) then
                        if os.time() - summerWebhookTimes.secret > 10 then
                            SendSummerWebhook("✨ RARE PET HATCHED!", "**Detected:** " .. obj.Text, 0xFFD700)
                            summerWebhookTimes.secret = os.time()
                        end
                    end
                end
            end)
        end
    end)
end)

-- Periodic summer status webhook loop
task.spawn(function()
    while task.wait(1) do
        local currentTime = os.time()
        local cooldownSecs = (getgenv().SplashWebhookCooldown or 5) * 60
        -- Farm & Shell Status
        if getgenv().TrackStatus then
            if currentTime - summerWebhookTimes.status >= cooldownSecs then
                local shells = GetSeashellCount()
                local phase = getgenv().IsHatchingPhase and "🥚 Hatching" or "⛏️ Farming"
                local desc = "**🐚 Seashells:** " .. tostring(shells) .. "\n**Status:** " .. phase
                if getgenv().IsHatchingPhase then
                    local currentEgg = getgenv().SelectedEggs[getgenv().CurrentEggIndex] or "None"
                    desc = desc .. "\n**Target Egg:** " .. currentEgg .. "\n**Hatches:** " .. tostring(getgenv().SessionHatches)
                end
                SendSummerWebhook("📊 Summer Status", desc, 0x3498DB)
                summerWebhookTimes.status = currentTime
            end
        end
        -- Upgrade Status
        if getgenv().TrackUpgrades and getgenv().UpgradeEnabled then
            if currentTime - summerWebhookTimes.upgrades >= cooldownSecs then
                local desc = "**Auto Upgrades Active**\n1: " .. getgenv().UpPri1 .. "\n2: " .. getgenv().UpPri2 .. "\n3: " .. getgenv().UpPri3
                SendSummerWebhook("🛠️ Upgrades Status", desc, 0xE67E22)
                summerWebhookTimes.upgrades = currentTime
            end
        end
    end
end)

-- ==========================================
-- ☀️ SUMMER: PlayerDataChanged Listener
-- ==========================================
pcall(function()
    local PDC = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("PlayerDataChanged")
    PDC.OnClientEvent:Connect(function(dataType, dataValue)
        -- Seashell tracking
        if dataType == "TropicalSeashells" or dataType == "Seashells" or dataType == "SummerShells" then
            if type(dataValue) == "number" or tonumber(dataValue) then
                local newVal = tonumber(dataValue)
                local oldVal = getgenv().CurrentSeashells
                getgenv().CurrentSeashells = newVal
                -- Webhook: seashell tracking
                if getgenv().TrackArtifacts and oldVal ~= -1 then
                    local diff = newVal - oldVal
                    if diff ~= 0 and (os.time() - (getgenv()._lastShellWebhook or 0) >= 120) then
                        local sign = diff > 0 and "+" or ""
                        SendSummerWebhook("Seashell Update", "**Total:** " .. tostring(newVal) .. "\n**Change:** " .. sign .. tostring(diff), diff > 0 and 0x2ECC71 or 0xE74C3C)
                        getgenv()._lastShellWebhook = os.time()
                    end
                end
            end
        -- Artifact inventory tracking
        elseif dataType == "Artifacts" and type(dataValue) == "table" then
            local count = 0
            for _ in pairs(dataValue) do count = count + 1 end
            local oldCount = getgenv()._artifactCount or 0
            getgenv()._artifactCount = count
            if getgenv().TrackArtifacts and oldCount > 0 then
                local diff = count - oldCount
                if diff ~= 0 and (os.time() - (getgenv()._lastArtifactWebhook or 0) >= 120) then
                    local sign = diff > 0 and "+" or ""
                    SendSummerWebhook("Artifact Update", "**Inventory:** " .. tostring(count) .. " artifacts\n**Change:** " .. sign .. tostring(diff), diff > 0 and 0x3498DB or 0xE67E22)
                    getgenv()._lastArtifactWebhook = os.time()
                end
            end
        -- Potion inventory tracking (for shrine auto-donate)
        elseif dataType == "Potions" and type(dataValue) == "table" then
            getgenv().LivePotions = dataValue
        -- Dream Shrine cooldown tracking
        elseif dataType == "DreamerShrine" and type(dataValue) == "table" then
            if dataValue.LastDonationTime then
                getgenv().DreamShrineLastDonation = dataValue.LastDonationTime
            end
        -- Bubble Shrine cooldown tracking
        elseif dataType == "BubbleShrine" and type(dataValue) == "table" then
            if dataValue.LastDonationTime then
                getgenv().BubbleShrineLastDonation = dataValue.LastDonationTime
            end
        -- Quest tracking (Captain Kitty, Gem Genie, Old Sailor)
        elseif dataType == "Quests" and type(dataValue) == "table" then
            local currentTime = os.time()
            local cooldownSecs = (getgenv().SplashWebhookCooldown or 5) * 60
            for _, quest in ipairs(dataValue) do
                -- Captain Kitty
                if string.find(quest.Id, "captain%-kitty") then
                    if table.find(getgenv().CompletedQuests, quest.Id) then continue end
                    local text, isComplete = "", true
                    for i, taskItem in ipairs(quest.Tasks) do
                        local req = taskItem.Amount
                        local cur = quest.Progress[i] or 0
                        local rarity = taskItem.Rarity or "Any"
                        text = text .. string.format("**%s:** %d / %d\n", rarity, cur, req)
                        if cur < req then isComplete = false end
                    end
                    if isComplete then
                        table.insert(getgenv().CompletedQuests, quest.Id)
                        text = text .. "\n✅ **Quest Complete!**"
                        if getgenv().AutoKittyClaim and not getgenv().IsDoingQuest then
                            while getgenv().IsClaimingChest or getgenv().IsClaimingInfChest or getgenv().GemFarming or getgenv().ObbySavedCFrame do task.wait(1) end
                            getgenv().IsDoingQuest = true
                            if getgenv().CurrentFarmTween then getgenv().CurrentFarmTween:Cancel() end
                            task.wait(0.2)
                            if player.Character then player.Character:PivotTo(CFrame.new(-249.08, 11.01, -4958.27)) end
                            task.spawn(function() task.wait(5); getgenv().IsDoingQuest = false end)
                        end
                    end
                    if getgenv().TrackKitty then
                        if isComplete and getgenv().LastCompletedQuest ~= quest.Id then
                            SendSummerWebhook("🐱 " .. (quest.DisplayName or "Kitty Quest"), text, 0x5865F2)
                            getgenv().LastCompletedQuest = quest.Id
                        elseif not isComplete and (currentTime - summerWebhookTimes.kitty >= cooldownSecs) then
                            SendSummerWebhook("🐱 " .. (quest.DisplayName or "Kitty Quest"), text, 0x5865F2)
                            summerWebhookTimes.kitty = currentTime
                        end
                    end
                end
                -- Gem Genie
                if quest.Id == "gem-genie" and getgenv().TrackGenie then
                    local text, isComplete = "", true
                    local coinReq = quest.Tasks[1].Item.Amount; local coinCur = quest.Progress[1] or 0
                    text = text .. string.format("**Coins:** %s / %s\n", tostring(coinCur), tostring(coinReq))
                    if coinCur < coinReq then isComplete = false end
                    local spotReq = quest.Tasks[2].Amount; local spotCur = quest.Progress[2] or 0
                    text = text .. string.format("**Spotted Eggs:** %d / %d\n", spotCur, spotReq)
                    if spotCur < spotReq then isComplete = false end
                    local neonReq = quest.Tasks[3].Amount; local neonCur = quest.Progress[3] or 0
                    text = text .. string.format("**Neon Eggs:** %d / %d\n", neonCur, neonReq)
                    if neonCur < neonReq then isComplete = false end
                    if isComplete or (currentTime - summerWebhookTimes.genie >= cooldownSecs) then
                        if isComplete then text = text .. "\n💎 **Genie Satisfied!**" end
                        SendSummerWebhook("🧞 Gem Genie", text, 0x9B59B6)
                        summerWebhookTimes.genie = currentTime
                    end
                end
                -- Old Sailor
                if quest.Id == "fishing-quest-9" and getgenv().TrackSailor then
                    local req = quest.Tasks[1].Amount; local cur = quest.Progress[1] or 0; local area = quest.Tasks[1].Area
                    local isComplete = (cur >= req)
                    local text = string.format("**Fish (%s):** %d / %d\n", area, cur, req)
                    if isComplete or (currentTime - summerWebhookTimes.sailor >= cooldownSecs) then
                        if isComplete then text = text .. "\n🎣 **Complete!**" end
                        SendSummerWebhook("⚓ Old Sailor", text, 0x3498DB)
                        summerWebhookTimes.sailor = currentTime
                    end
                end
            end
        end
    end)
end)


-- ==========================================
-- 🤝 TRADING TAB
-- ==========================================


TradeTab:CreateSection("Quick Teleports")
TradeTab:CreateButton({ Name = "Teleport to Trading Plaza", Callback = function()
    pcall(function()
        game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("Teleport", "Workspace.Worlds.The Overworld.FastTravel.Spawn")
    end)
    task.wait(1.5)
    pcall(function()
        game:GetService("ReplicatedStorage").Shared.Framework.Network.Remote.RemoteEvent:FireServer("Teleport", "Workspace.Worlds.The Overworld.Areas.Spawn.Areas.Plaza.Spawn")
    end)
end })

TradeTab:CreateSection("Auto Trade Message")
TradeTab:CreateLabel("Sends a message in chat at a set interval. Great for AFK trade posting.")

getgenv().TradeMessage = ""
getgenv().TradeMessageEnabled = false
getgenv().TradeMessageInterval = 5

TradeTab:CreateInput({
    Name = "Trade Message",
    PlaceholderText = "e.g. Trading Secret XYZ for offers...",
    RemoveTextAfterFocusLost = false,
    Flag = "TradeMsg",
    Callback = function(Text)
        getgenv().TradeMessage = Text
    end,
})

TradeTab:CreateSlider({
    Name = "Message Interval",
    Range = {1, 30},
    Increment = 1,
    Suffix = " min",
    CurrentValue = 5,
    Flag = "TradeMsgInterval",
    Callback = function(Value)
        getgenv().TradeMessageInterval = Value
    end,
})

TradeTab:CreateToggle({
    Name = "Start Auto Message",
    CurrentValue = false,
    Flag = "TradeMsgToggle",
    Callback = function(Value)
        getgenv().TradeMessageEnabled = Value
        if Value and getgenv().TradeMessage ~= "" then
            task.spawn(function()
                while getgenv().TradeMessageEnabled do
                    pcall(function()
                        -- Method 1: TextChatService (modern)
                        local textChat = game:GetService("TextChatService")
                        local channel = textChat.TextChannels:FindFirstChild("RBXGeneral")
                        if channel then
                            channel:SendAsync(getgenv().TradeMessage)
                        else
                            -- Method 2: Legacy chat
                            game:GetService("ReplicatedStorage"):FindFirstChild("DefaultChatSystemChatEvents"):FindFirstChild("SayMessageRequest"):FireServer(getgenv().TradeMessage, "All")
                        end
                    end)
                    task.wait(getgenv().TradeMessageInterval * 60)
                end
            end)
        end
    end,
})

-- Plaza state detection on startup
task.spawn(function()
    pcall(function()
        if isfile and isfile("SplashHub_PlazaState.json") then
            local raw = readfile("SplashHub_PlazaState.json")
            local state = HttpService:JSONDecode(raw)
            if state and state.TargetState == "Plaza" then
                getgenv().CurrentZone = "Plaza"
            elseif state and state.TargetState == "Main" then
                getgenv().CurrentZone = "Main"
                -- Restore saved position after bypassing UI
                if state.SavedX and state.SavedY and state.SavedZ then
                    -- Bypass UI (Spam click for 10s)
                    local endT = os.clock() + 10
                    while os.clock() < endT do
                        pcall(function()
                            for _, gui in pairs(game.Players.LocalPlayer.PlayerGui:GetDescendants()) do
                                if gui:IsA("TextButton") or gui:IsA("ImageButton") then
                                    local t = ""
                                    if gui:IsA("TextButton") then t = gui.Text:lower() end
                                    if t == "" and gui:FindFirstChildOfClass("TextLabel") then
                                        t = gui:FindFirstChildOfClass("TextLabel").Text:lower()
                                    end
                                    if t:find("play") or t:find("optimized") then
                                        pcall(function() for _, c in ipairs(getconnections(gui.MouseButton1Click)) do c:Fire() end end)
                                        pcall(function() for _, c in ipairs(getconnections(gui.MouseButton1Down)) do c:Fire() end end)
                                    end
                                end
                            end
                        end)
                        task.wait(0.2)
                    end
                    -- Teleport back to saved position
                    local char = game.Players.LocalPlayer.Character
                    if char and char:FindFirstChild("HumanoidRootPart") then
                        char.HumanoidRootPart.CFrame = CFrame.new(state.SavedX, state.SavedY, state.SavedZ)
                    end
                end
                -- Clean up state file
                pcall(function() delfile("SplashHub_PlazaState.json") end)
            end
        end
    end)
end)

-- Standard reconnect position restore
task.spawn(function()
    pcall(function()
        if isfile and isfile("SplashHub_SavedPosition.txt") then
            getgenv().IsReconnecting = true
            local posStr = readfile("SplashHub_SavedPosition.txt")
            pcall(function() delfile("SplashHub_SavedPosition.txt") end)
            
            local coords = {}
            for val in posStr:gmatch("[^,]+") do table.insert(coords, tonumber(val)) end
            
            if #coords == 3 then
                -- Bypass UI (Spam click for 10s)
                local endT = os.clock() + 10
                while os.clock() < endT do
                    pcall(function()
                        for _, gui in pairs(game.Players.LocalPlayer.PlayerGui:GetDescendants()) do
                            if gui:IsA("TextButton") or gui:IsA("ImageButton") then
                                local t = ""
                                if gui:IsA("TextButton") then t = gui.Text:lower() end
                                if t == "" and gui:FindFirstChildOfClass("TextLabel") then
                                    t = gui:FindFirstChildOfClass("TextLabel").Text:lower()
                                end
                                if t:find("play") or t:find("optimized") then
                                    pcall(function() for _, c in ipairs(getconnections(gui.MouseButton1Click)) do c:Fire() end end)
                                    pcall(function() for _, c in ipairs(getconnections(gui.MouseButton1Down)) do c:Fire() end end)
                                end
                            end
                        end
                    end)
                    task.wait(0.2)
                end
                
                -- Teleport
                local char = game.Players.LocalPlayer.Character
                if char and char:FindFirstChild("HumanoidRootPart") then
                    char.HumanoidRootPart.CFrame = CFrame.new(coords[1], coords[2], coords[3])
                end
                getgenv().IsReconnecting = false
                
                consoleLog("Successfully Reconnected & Restored Position")
                
                -- Send Webhook Success Ping
                if wh_url and wh_url ~= "" then
                    local contentStr = ""
                    if getgenv().WHPingID and getgenv().WHPingID ~= "" then
                        contentStr = "<@" .. getgenv().WHPingID .. "> "
                    end
                    local embedData = {
                        content = contentStr .. "✅ Successfully reconnected and teleported back to the saved position!",
                        embeds = {{
                            title = "Splash Hub | Auto-Reconnect",
                            description = "Player: **" .. game.Players.LocalPlayer.Name .. "** is back online.",
                            color = 65280,
                            footer = { text = "Splash Hub V1 • " .. os.date("%H:%M:%S") }
                        }}
                    }
                    request({Url = wh_url, Method = "POST", Headers = {["Content-Type"]="application/json"}, Body = HttpService:JSONEncode(embedData)})
                end
            end
        end
    end)
end)

-- ==========================================
-- ðŸ† SEASON PASS AUTOMATION (Auto Season Master V2)
-- ==========================================

-- == DATA ARRAYS & LOCATIONS ==
-- SeasonEggLocations defined at line ~525 (shared with Bubble Up)

-- == ZEN PATHING COORDINATES ==
local ZenPath = {
    Vector3.new(51.26, 15971.73, 40.24),
    Vector3.new(58.28, 15971.73, 23.29),
    Vector3.new(70.14, 15971.73, 4.34),
    Vector3.new(62.59, 15971.73, -10.65),
    Vector3.new(-46.04, 15971.73, 29.85),
    Vector3.new(-49.44, 15971.73, 9.39),
    Vector3.new(-69.18, 15971.73, 14.21),
    Vector3.new(-67.21, 15971.73, -6.19)
}

-- Memory states
local SeasonOriginalCFrame = nil
local IsDoingSeasonTasks = false
local SeasonIsTeleporting = false
getgenv().SeasonTweenSpeed = 100
getgenv().SeasonSendProgressHooks = false
getgenv().SeasonWebhookInterval = 5

-- == SEASON WEBHOOK ==
local function SendSeasonWebhook(title, description, color)
    if not wh_url or wh_url == "" then return end
    
    pcall(function()
        request({
            Url = wh_url,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode({
                embeds = {{
                    title = title,
                    description = description,
                    color = color or 5814783,
                    timestamp = DateTime.now():ToIsoDate()
                }}
            })
        })
    end)
end

local function FormatProgressWebhook(activeTasks, hourlyTimer, dailyTimer)
    local desc = ""
    desc = desc .. "â±ï¸ **Refresh Timers:**\n"
    desc = desc .. "â³ **Hourly Refreshes In:** `" .. (hourlyTimer or "Unknown/Ready") .. "`\n"
    desc = desc .. "â³ **Daily Refreshes In:** `" .. (dailyTimer or "Unknown/Ready") .. "`\n\n"
    desc = desc .. "â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”â”\n\n"

    if #activeTasks == 0 then
        desc = desc .. "âœ… **All available tasks are currently completed!**\n*Idling at last CFrame waiting for refresh.*"
    else
        for _, taskData in ipairs(activeTasks) do
            desc = desc .. "ðŸŽ¯ **Task:** " .. taskData.name .. "\nðŸ“ˆ **Progress:** `" .. taskData.progress .. "`\n\n"
        end
    end
    SendSeasonWebhook("ðŸ“Š Season Progress & Timers", desc, 16753920)
end

-- == HELPER FUNCTIONS ==
local function seasonTeleportTo(target)
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if root and not SeasonIsTeleporting then
        SeasonIsTeleporting = true
        player.Character.Humanoid.Jump = true 
        task.wait(0.1)
        
        if typeof(target) == "Vector3" then
            root.CFrame = CFrame.new(target)
        elseif typeof(target) == "CFrame" then
            root.CFrame = target
        end
        
        task.wait(1) 
        SeasonIsTeleporting = false
    end
end

local function isSeasonNear(targetPosition, distance)
    if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
        local currentPos = player.Character.HumanoidRootPart.Position
        return (currentPos - targetPosition).Magnitude <= distance
    end
    return false
end

local function walkZenPath()
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChild("Humanoid")
    
    if not root or not hum then return end

    for _, pos in ipairs(ZenPath) do
        local distance = (root.Position - pos).Magnitude
        local timeToTween = distance / getgenv().SeasonTweenSpeed
        
        if timeToTween > 0 then
            local tweenInfo = TweenInfo.new(timeToTween, Enum.EasingStyle.Linear)
            local tween = TweenService:Create(root, tweenInfo, {CFrame = CFrame.new(pos)})
            
            tween:Play()
            while tween.PlaybackState == Enum.PlaybackState.Playing do
                hum.Jump = true
                task.wait(0.1)
            end
        end
        task.wait(0.1)
    end
end

local function identifySeasonEggFromText(text)
    local numberMatch = string.match(text, "%d+,?%d*")
    if numberMatch then
        local num = tonumber((string.gsub(numberMatch, ",", "")))
        if num and num >= 1000 then return "Common Egg" end
    end

    if string.find(text, "Legendary") then return "Spikey Egg"
    elseif string.find(text, "Epic") then return "Spotted Egg"
    elseif string.find(text, "Rare") or string.find(text, "Unique") then return "Iceshard Egg"
    elseif string.find(text, "Common") then return "Common Egg" end

    for eggName, _ in pairs(SeasonEggLocations) do
        local baseName = string.gsub(eggName, " Egg", "")
        if string.find(text, baseName) then return eggName end
    end
    
    if string.find(text, "Hatch") then return "Common Egg" end
    return nil
end

-- == SEASON TAB UI ==
SeasonTab:CreateSection("Smart Automation Toggles")

SeasonTab:CreateDropdown({
   Name = "Task Priority",
   Options = {"Egg Priority", "Bubble Priority"},
   CurrentOption = {"Egg Priority"},
   Flag = "SeasonTaskPriority",
   Callback = function(Option) getgenv().SeasonTaskPriority = Option[1] end,
})

getgenv().SeasonAutoEquipTeam = false
SeasonTab:CreateToggle({
   Name = "Auto Equip Best Team (Team 1)",
   CurrentValue = false,
   Flag = "SeasonAutoEquipTeam",
   Callback = function(Value) getgenv().SeasonAutoEquipTeam = Value end,
})

getgenv().SeasonSmartBubbleLock = false
SeasonTab:CreateToggle({
   Name = "Smart Bubble Lock Logic",
   CurrentValue = false,
   Flag = "SeasonSmartBubbleLock",
   Callback = function(Value) getgenv().SeasonSmartBubbleLock = Value end,
})

getgenv().SeasonAutoHourly = false
SeasonTab:CreateToggle({
   Name = "Auto Hourly Challenges",
   CurrentValue = false,
   Flag = "SeasonAutoHourly",
   Callback = function(Value) getgenv().SeasonAutoHourly = Value end,
})

getgenv().SeasonAutoDaily = false
SeasonTab:CreateToggle({
   Name = "Auto Daily Challenges",
   CurrentValue = false,
   Flag = "SeasonAutoDaily",
   Callback = function(Value) getgenv().SeasonAutoDaily = Value end,
})

getgenv().SeasonAutoZenPath = false
SeasonTab:CreateToggle({
   Name = "Auto Collect Coins/Gems in Zen",
   CurrentValue = false,
   Flag = "SeasonAutoZenPath",
   Callback = function(Value) getgenv().SeasonAutoZenPath = Value end,
})

SeasonTab:CreateSection("Webhook (uses main Webhook URL)")
SeasonTab:CreateToggle({
    Name = "Send Interval Progress Updates",
    CurrentValue = false,
    Flag = "SeasonSendProgressHooks",
    Callback = function(Value) getgenv().SeasonSendProgressHooks = Value end,
})
SeasonTab:CreateSlider({
    Name = "Progress Notification Interval (Mins)",
    Range = {1, 60},
    Increment = 1,
    Suffix = " Minutes",
    CurrentValue = 5,
    Flag = "SeasonWebhookInterval",
    Callback = function(Value) getgenv().SeasonWebhookInterval = Value end,
})
SeasonTab:CreateButton({
    Name = "Send Test Webhook",
    Callback = function()
        SendSeasonWebhook("ðŸ§ª Webhook Tester", "Success! Your webhook is configured properly and is ready to track season tasks.", 65280)
    end,
})

-- == SEASON ENGINE ==
task.spawn(function()
    local lastHatchTime = 0 
    local teamEquipped = false
    local TaskStates = {} 
    local lastProgressWebhook = os.time()

    while task.wait(0.1) do 
        if getgenv().SeasonAutoHourly or getgenv().SeasonAutoDaily then
            local activeTaskFound = false
            local challengeUI = player.PlayerGui:FindFirstChild("Season", true)
            local currentActiveTasksData = {} 
            local detectedHourlyTimer = nil
            local detectedDailyTimer = nil
            
            if challengeUI and not SeasonIsTeleporting then
                local pendingEggTask = nil
                local pendingBubbleTask = nil
                local pendingCoinTask = nil
                
                -- SCAN UI FOR TIMERS AND TASKS
                for _, element in pairs(challengeUI:GetDescendants()) do
                    if element:IsA("TextLabel") then
                        local text = element.Text
                        
                        -- Timer Scraping Logic
                        local timeMatch = string.match(text, "%d+:%d+:%d+") or string.match(text, "%d+:%d+")
                        if timeMatch then
                            local parentName = string.lower(element.Parent and element.Parent.Name or "")
                            if string.find(parentName, "hourly") or string.find(string.lower(text), "hourly") then
                                detectedHourlyTimer = timeMatch
                            elseif string.find(parentName, "daily") or string.find(string.lower(text), "daily") then
                                detectedDailyTimer = timeMatch
                            else
                                if string.len(timeMatch) <= 5 then detectedHourlyTimer = timeMatch else detectedDailyTimer = timeMatch end
                            end
                        end

                        -- Task Logic
                        local isCompleted = false
                        local progressText = "0/0"
                        local container = element.Parent
                        
                        if container then
                            for _, desc in pairs(container:GetDescendants()) do
                                if desc:IsA("TextLabel") then
                                    if string.find(desc.Text, "Completed") or string.find(desc.Text, "100%%") then
                                        isCompleted = true
                                        progressText = "Completed"
                                    elseif string.match(desc.Text, "%d+/%d+") or string.match(desc.Text, "%d+%%") then
                                        progressText = desc.Text
                                    end
                                end
                            end
                        end

                        if (string.find(text, "Hatch") or string.find(text, "Blow") or string.find(text, "Collect")) and string.len(text) > 5 then
                            if isCompleted then
                                if TaskStates[text] == false then
                                    SendSeasonWebhook("ðŸŽ‰ Season Task Completed!", "Finished Task: **" .. text .. "**", 65280)
                                    consoleLog("Season: âœ… Completed: " .. text)
                                end
                                TaskStates[text] = true
                            else
                                TaskStates[text] = false
                                table.insert(currentActiveTasksData, {name = text, progress = progressText})
                                
                                if string.find(text, "Hatch") and not pendingEggTask then
                                    pendingEggTask = text
                                elseif string.find(text, "Blow") and string.find(text, "Bubbles") and not pendingBubbleTask then
                                    pendingBubbleTask = text
                                elseif string.find(text, "Collect") and (string.find(text, "Coins") or string.find(text, "Gems")) and not pendingCoinTask then
                                    if getgenv().SeasonAutoZenPath then pendingCoinTask = text end
                                end
                            end
                        end
                    end
                end

                -- Webhook Notification Logic (Progress Interval)
                if getgenv().SeasonSendProgressHooks then
                    if os.time() - lastProgressWebhook >= (getgenv().SeasonWebhookInterval * 60) then
                        FormatProgressWebhook(currentActiveTasksData, detectedHourlyTimer, detectedDailyTimer)
                        lastProgressWebhook = os.time()
                    end
                end

                local activeTaskText = (getgenv().SeasonTaskPriority == "Bubble Priority") and (pendingBubbleTask or pendingEggTask or pendingCoinTask) or (pendingEggTask or pendingBubbleTask or pendingCoinTask)

                if activeTaskText then
                    activeTaskFound = true
                    
                    if not IsDoingSeasonTasks then
                        local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                        if root then SeasonOriginalCFrame = root.CFrame end
                        IsDoingSeasonTasks = true
                    end

                    -- HATCHING LOGIC
                    if string.find(activeTaskText, "Hatch") then
                        local targetEgg = identifySeasonEggFromText(activeTaskText)
                        if targetEgg then
                            if not isSeasonNear(SeasonEggLocations[targetEgg], 20) then
                                seasonTeleportTo(SeasonEggLocations[targetEgg])
                            elseif os.clock() - lastHatchTime >= 1.1 then
                                NetworkRemoteEvent:FireServer("HatchEgg", targetEgg, getgenv().HatchAmount)
                                lastHatchTime = os.clock()
                            end
                        end
                    
                    -- BLOWING LOGIC
                    elseif string.find(activeTaskText, "Blow") then
                        if getgenv().SeasonSmartBubbleLock then NetworkRemoteEvent:FireServer("SetSetting", "Bubble Lock", false) end
                        pcall(function() mouse1click() end)
                        
                    -- ZEN COLLECTION LOGIC (Coins/Gems)
                    elseif string.find(activeTaskText, "Collect") and (string.find(activeTaskText, "Coins") or string.find(activeTaskText, "Gems")) then
                        if not teamEquipped and getgenv().SeasonAutoEquipTeam then
                            task.wait(2)
                            NetworkRemoteEvent:FireServer("EquipTeam", 1)
                            teamEquipped = true
                        end
                        if not isSeasonNear(ZenPath[1], 20) then seasonTeleportTo(ZenPath[1]) end
                        walkZenPath()
                    end
                end
            end

            -- COMPLETION / RETURN TO ORIGINAL CFRAME
            if not activeTaskFound and IsDoingSeasonTasks then
                IsDoingSeasonTasks = false 
                teamEquipped = false
                if SeasonOriginalCFrame then 
                    seasonTeleportTo(SeasonOriginalCFrame) 
                    SendSeasonWebhook("ðŸ’¤ All Tasks Complete", "Returned to last CFrame. Idling until next refresh.", 10181046)
                    consoleLog("Season: All tasks complete, returned to origin.")
                end
                SeasonOriginalCFrame = nil 
            end
        end
    end
end)

-- ==========================================
-- 🧞 GENIE QUEST ENGINE (Final Hatch Fix)
-- ==========================================
QuestTab:CreateSection("Auto Gem Genie")
local GenieTaskLabel = QuestTab:CreateLabel("Task: None")
local GenieProgressLabel = QuestTab:CreateLabel("Progress: 0% | ETA: Calculating...")
local GenieCooldownLabel = QuestTab:CreateLabel("Cooldown: Ready")

-- Status & Quests
QuestTab:CreateSection("Session Stats")
local SessionTimeLabel = QuestTab:CreateLabel("Session Time: 00:00:00")
local QuestsCompletedLabel = QuestTab:CreateLabel("Quests Completed: 0")
local LastRewardsLabel = QuestTab:CreateLabel("Last Rewards: None")

-- Automation Settings
QuestTab:CreateSection("Automation Settings")
getgenv().AutoGenie = false
QuestTab:CreateToggle({
    Name = "Enable Auto Gem Genie",
    CurrentValue = false, Flag = "AutoGenieToggle",
    Callback = function(Value)
        getgenv().AutoGenie = Value
        if Value then
            local root = getRootPart()
            if root then getgenv().GeniePreQuestCFrame = root.CFrame end
            consoleLog("🧞 Auto Genie engaged.")
        end
    end,
})

getgenv().AutoSell = false
QuestTab:CreateToggle({ Name = "Enable Auto-Sell (Zen)", CurrentValue = false, Flag = "GenieAutoSell", Callback = function(V) getgenv().AutoSell = V end })

getgenv().AutoBlow = false
QuestTab:CreateToggle({ Name = "Enable Auto-Blow (Zen)", CurrentValue = false, Flag = "GenieAutoBlow", Callback = function(V) getgenv().AutoBlow = V end })

getgenv().GenieTweenSpeed = 60
QuestTab:CreateSlider({ Name = "Tween Speed", Range = {20, 150}, Increment = 5, Suffix = " SPD", CurrentValue = 60, Flag = "GenieTweenSpeedSlider", Callback = function(V) getgenv().GenieTweenSpeed = V end })

-- Hatching Controls
QuestTab:CreateSection("Hatching Controls")
getgenv().GenieHatchAmount = 5
QuestTab:CreateDropdown({ Name = "Hatch Amount", Options = {"1", "3", "5"}, CurrentOption = {"5"}, MultipleOptions = false, Flag = "GenieHatchAmountDrop", Callback = function(O) getgenv().GenieHatchAmount = tonumber(O[1]) end })

getgenv().GenieFastHatch = true
QuestTab:CreateToggle({ Name = "Fast Hatch Mode", CurrentValue = true, Flag = "GenieFastHatchToggle", Callback = function(V) getgenv().GenieFastHatch = V end })

getgenv().GenieHatchSpeed = 0.5
QuestTab:CreateSlider({ Name = "Hatch Wait Speed", Range = {0, 5}, Increment = 0.1, Suffix = " Secs", CurrentValue = 0.5, Flag = "GenieHatchSpeedSlider", Callback = function(V) getgenv().GenieHatchSpeed = V end })



-- Rewards & Rerolls
QuestTab:CreateSection("Reward Selection")
getgenv().GenieAutoReroll = false
QuestTab:CreateToggle({ Name = "Enable Auto-Reroll", CurrentValue = false, Flag = "GenieAutoRerollToggle", Callback = function(V) getgenv().GenieAutoReroll = V end })

getgenv().GenieMaxRerolls = 5
QuestTab:CreateSlider({ Name = "Max Rerolls", Range = {1, 20}, Increment = 1, Suffix = " Rerolls", CurrentValue = 5, Flag = "GenieMaxRerollsSlider", Callback = function(V) getgenv().GenieMaxRerolls = V end })

getgenv().GeniePrioritizeGems = false
QuestTab:CreateToggle({ Name = "Prioritize High Gems (M/B)", CurrentValue = false, Flag = "GeniePrioritizeGemsToggle", Callback = function(V) getgenv().GeniePrioritizeGems = V end })

getgenv().GenieWantedGodTier = {"Secret Elixir"}
QuestTab:CreateDropdown({ Name = "God Tier Potions", Options = {"Secret Elixir", "Egg Elixir", "Infinity Elixir", "Mythic Infinity", "Lucky Infinity", "Coins Infinity"}, CurrentOption = {"Secret Elixir"}, MultipleOptions = true, Flag = "GenieGodTierDropdown", Callback = function(O) getgenv().GenieWantedGodTier = O end })

getgenv().GenieWantedMidTier = {}
QuestTab:CreateDropdown({ Name = "Tier 4 & 7 Potions", Options = {"Luck VII", "Speed VII", "Mythic IV", "Lucky IV", "Coins IV"}, CurrentOption = {}, MultipleOptions = true, Flag = "GenieMidTierDropdown", Callback = function(O) getgenv().GenieWantedMidTier = O end })


-- ============================================================================
-- MAIN GENIE LOOP
-- ============================================================================
task.spawn(function()
    while task.wait(0.2) do
        local sDiff = os.time() - getgenv().SessionStartTime
        pcall(function() SessionTimeLabel:Set(string.format("Session Time: %02d:%02d:%02d", math.floor(sDiff/3600), math.floor((sDiff%3600)/60), sDiff%60)) end)
        
        if getgenv().AutoGenie then
            if os.time() - genieLastWebhookSent >= getgenv().GenieWebhookInterval then
                sendGenieWebhook("⏳ Auto Genie Status", "Periodic update of quest progress and stats.", "Running")
                genieLastWebhookSent = os.time()
            end
            
            if getgenv().GenieCooldownEndTime and getgenv().GenieCooldownEndTime > os.time() then
                local diff = getgenv().GenieCooldownEndTime - os.time()
                local h, m, s = math.floor(diff / 3600), math.floor((diff % 3600) / 60), diff % 60
                genieCurrentCooldown = h > 0 and string.format("%d:%02d:%02d", h, m, s) or string.format("%d:%02d", m, s)
                genieCurrentTask = "None"
                genieTaskProgress = "0%"
                genieCurrentETA = "N/A"
                
                pcall(function() GenieTaskLabel:Set("Task: Cooldown") end)
                pcall(function() GenieCooldownLabel:Set("Cooldown: " .. genieCurrentCooldown) end)
                pcall(function() GenieProgressLabel:Set("Progress: Cooldown") end)
                continue
            else
                genieCurrentCooldown = "Ready"
            end

            local hudState, hTask, hProg = xRayGenieHUDNew()
            if hudState == "Active" then
                genieHudGraceTimer = 0
                genieIsHudMissing = false
                
                if genieCurrentTask ~= hTask then
                    genieCurrentTask = hTask
                    genieLastTrackedTask = hTask
                    getgenv().CurrentQuestStartTime = os.time()
                    genieLastProgressTime = os.time()
                    genieLastProgressAmt = 0
                    sendGenieWebhook("🚀 Quest Started", "Began working on: " .. hTask, "In Progress")
                end
                
                genieTaskProgress = hProg
                
                local cStr, mStr = string.match(hProg, "([^\n/]+)%s*/%s*(.+)")
                if cStr and mStr then
                    local currentAmt = genieParseProgressValue(cStr)
                    local maxAmt = genieParseProgressValue(mStr)
                    
                    if currentAmt > genieLastProgressAmt then
                        local diffAmt = currentAmt - genieLastProgressAmt
                        local diffTime = os.time() - genieLastProgressTime
                        if diffTime > 0 then
                            local ratePerSec = diffAmt / diffTime
                            local remaining = maxAmt - currentAmt
                            if ratePerSec > 0 then
                                local etaSecs = remaining / ratePerSec
                                if etaSecs > 3600 then
                                    genieCurrentETA = string.format("%dh %dm", math.floor(etaSecs/3600), math.floor((etaSecs%3600)/60))
                                elseif etaSecs > 60 then
                                    genieCurrentETA = string.format("%dm %ds", math.floor(etaSecs/60), math.floor(etaSecs%60))
                                else
                                    genieCurrentETA = string.format("%ds", math.floor(etaSecs))
                                end
                            end
                        end
                        genieLastProgressAmt = currentAmt
                        genieLastProgressTime = os.time()
                    end
                end
                
                pcall(function() GenieTaskLabel:Set("Task: " .. hTask) end)
                pcall(function() GenieProgressLabel:Set("Progress: " .. hProg .. " | ETA: " .. genieCurrentETA) end)
                pcall(function() GenieCooldownLabel:Set("Cooldown: " .. genieCurrentCooldown) end)
                
                local lowerTask = string.lower(hTask)
                
                if string.find(lowerTask, "hatch") then
                    local targetEgg = genieResolveTargetEgg(hTask)
                    if genieEggData[targetEgg] then
                        SafeTeleport(genieEggData[targetEgg])
                        task.wait(0.5)
                        local root = getRootPart()
                        if root then root.CFrame = CFrame.new(genieEggData[targetEgg]) end
                        
                        if getgenv().GenieFastHatch then
                            for i = 1, getgenv().GenieHatchAmount do
                                task.spawn(function()
                                    NetworkRemoteEvent:FireServer("HatchEgg", targetEgg, 1)
                                end)
                            end
                        else
                            NetworkRemoteEvent:FireServer("HatchEgg", targetEgg, getgenv().GenieHatchAmount)
                        end
                        task.wait(getgenv().GenieHatchSpeed)
                    end
                    
                elseif string.find(lowerTask, "blow") or string.find(lowerTask, "bubble") then
                    if getgenv().AutoSell and os.time() - genieLastSellTime > 30 then
                        SafeTeleport(genieSellPos)
                        task.wait(0.5)
                        NetworkRemoteEvent:FireServer("SellBubbles")
                        genieLastSellTime = os.time()
                    end
                    NetworkRemoteEvent:FireServer("SetSetting", "Bubble Lock", false)
                    if getgenv().AutoBlow then
                        NetworkRemoteEvent:FireServer("BlowBubble")
                    end
                    
                elseif string.find(lowerTask, "collect") or string.find(lowerTask, "coin") or string.find(lowerTask, "gem") then
                    if getgenv().AutoSell and os.time() - genieLastSellTime > 30 then
                        SafeTeleport(genieSellPos)
                        task.wait(0.5)
                        NetworkRemoteEvent:FireServer("SellBubbles")
                        genieLastSellTime = os.time()
                    end
                    for _, pos in ipairs(genieZenCoords) do
                        if not getgenv().AutoGenie then break end
                        local cState = xRayGenieHUDNew()
                        if cState == "Done" or cState == "NoHUD" then break end
                        genieTweenTo(pos)
                    end
                end
                
            elseif hudState == "Done" or hudState == "NoHUD" then
                if hudState == "NoHUD" then
                    if not genieIsHudMissing then
                        genieIsHudMissing = true
                        genieHudGraceTimer = os.time()
                    else
                        if os.time() - genieHudGraceTimer < 3 then
                            continue
                        end
                    end
                end
                
                genieIsHudMissing = false
                
                if genieCurrentTask ~= "None" and not getgenv().QuestDebounce then
                    getgenv().QuestDebounce = true
                    getgenv().QuestsCompleted = getgenv().QuestsCompleted + 1
                    local qRews = getgenv().QuestRewards or "Unknown"
                    getgenv().CurrentRewards = getgenv().CurrentRewards and (getgenv().CurrentRewards .. " | " .. qRews) or qRews
                    pcall(function() QuestsCompletedLabel:Set("Quests Completed: " .. getgenv().QuestsCompleted) end)
                    pcall(function() LastRewardsLabel:Set("Last Rewards: " .. qRews) end)
                    sendGenieWebhook("🎉 Quest Completed!", "Finished " .. genieCurrentTask .. "\nRewards Secured: " .. qRews, "Complete")
                    
                    genieCurrentTask = "None"
                    genieTaskProgress = "0%"
                    genieCurrentETA = "N/A"
                    pcall(function() GenieTaskLabel:Set("Task: " .. genieCurrentTask) end)
                    pcall(function() GenieProgressLabel:Set("Progress: " .. genieTaskProgress) end)
                    
                    task.wait(2) 
                    getgenv().QuestDebounce = false
                end
                
                if os.time() >= genieNextBoardVisit then
                    local root = getRootPart()
                    if root then getgenv().GeniePreQuestCFrame = root.CFrame end
                    
                    SafeTeleport(genieIdlePos)
                    task.wait(1.5)
                    NetworkRemoteEvent:FireServer("StartGenieQuest", 2)
                    task.wait(2.5)
                    
                    local attempt = 1
                    local maxAttempts = getgenv().GenieAutoReroll and (getgenv().GenieMaxRerolls + 1) or 1
                    
                    while attempt <= maxAttempts do
                        local bState, bData = scanBoardNew()
                        if bState == "Cooldown" then
                            local h, m, s = string.match(bData or "", "(%d+):(%d+):(%d+)")
                            if not h then h = 0; m, s = string.match(bData or "", "(%d+):(%d+)") end
                            if m and s then
                                getgenv().GenieCooldownEndTime = os.time() + (tonumber(h) * 3600) + (tonumber(m) * 60) + tonumber(s)
                            end
                            consoleLog("🧞 Genie: Cooldown detected.")
                            sendGenieWebhook("🛑 Cooldown Hit", "Awaiting cooldown to refresh.", "Cooldown")
                            break
                        elseif bState == "Choose" then
                            local idx, score, wanted, raw = evaluateCardsNew(bData)
                            if score > 0 or attempt == maxAttempts then
                                NetworkRemoteEvent:FireServer("StartGenieQuest", idx)
                                getgenv().QuestRewards = wanted .. " (" .. raw .. ")"
                                consoleLog("🧞 Genie: Accepted quest with rewards: " .. getgenv().QuestRewards)
                                sendGenieWebhook("🃏 Card Chosen", "Accepted quest with rewards: " .. getgenv().QuestRewards, "Starting")
                                task.wait(2)
                                break
                            else
                                NetworkRemoteEvent:FireServer("RerollGenie")
                                consoleLog("🧞 Genie: Rerolling (" .. attempt .. "/" .. maxAttempts .. ") - Bad cards: " .. raw)
                                sendGenieWebhook("🎲 Rerolling Board", "Attempt " .. attempt .. "/" .. maxAttempts .. "\nRejected: " .. raw, "Rerolling")
                                task.wait(3.5)
                            end
                        elseif bState == "Active" then
                            genieCurrentTask = bData.task
                            break
                        else
                            task.wait(1)
                        end
                        attempt = attempt + 1
                    end
                    
                    if getgenv().GeniePreQuestCFrame then
                        local root2 = getRootPart()
                        if root2 then root2.CFrame = getgenv().GeniePreQuestCFrame end
                    end
                    genieNextBoardVisit = os.time() + 15
                else
                    pcall(function() GenieTaskLabel:Set("Task: Waiting for board...") end)
                end
            end
        end
    end
end)

-- ==========================================
-- 🌸 FLOWER WORLD FEATURES
-- ==========================================
SummerTab:CreateSection("Bubble Up Auto Quests")
SummerTab:CreateToggle({
    Name = "Enable Bubble Up Quests",
    CurrentValue = false, Flag = "AutoBubbleUpToggle",
    Callback = function(Value)
        getgenv().AutoBubbleUpQuest = Value
        if Value then
            task.spawn(function()
                local boardCoords = Vector3.new(-6539.81, 93.60, -4710.16)
                while getgenv().AutoBubbleUpQuest do
                    local taskInfo = GetBubbleUpTask()
                    if taskInfo and taskInfo.Current < taskInfo.Target then
                        -- HATCHING QUEST
                        if taskInfo.Type == "Hatch" then
                            local eggPos = SeasonEggLocations[taskInfo.Egg]
                            if eggPos then
                                SafeTeleport(eggPos)
                                task.wait(1.5)
                                while getgenv().AutoBubbleUpQuest do
                                    local update = GetBubbleUpTask()
                                    if not update or update.Type ~= "Hatch" or update.Egg ~= taskInfo.Egg or update.Current >= update.Target then break end
                                    NetworkRemoteEvent:FireServer("HatchEgg", taskInfo.Egg, getgenv().HatchAmount)
                                    task.wait(1.5)
                                end
                            end
                        -- BUBBLE QUEST
                        elseif taskInfo.Type == "Bubble" then
                            NetworkRemoteEvent:FireServer("SetSetting", "Bubble Lock", false)
                            task.wait(0.5)
                            while getgenv().AutoBubbleUpQuest do
                                local update = GetBubbleUpTask()
                                if not update or update.Type ~= "Bubble" or update.Current >= update.Target then break end
                                NetworkRemoteEvent:FireServer("BlowBubble")
                                task.wait(0.5)
                            end
                            if getgenv().BubbleUpRelockBubbles then
                                NetworkRemoteEvent:FireServer("SetSetting", "Bubble Lock", true)
                            end
                        end
                        task.wait(3.5)
                    else
                        SafeTeleport(boardCoords)
                        task.wait(4)
                    end
                end
            end)
        end
    end,
})

SummerTab:CreateSection("Bubble Quest Settings")
SummerTab:CreateToggle({ Name = "Re-Lock Bubbles After Quest", CurrentValue = true, Flag = "BubbleUpRelockToggle", Callback = function(V) getgenv().BubbleUpRelockBubbles = V end })


SummerTab:CreateSection("Flower Kingdom Egg")
local flowerEggTarget = Vector3.new(-6350.96, 81.33, -4727.72)
getgenv().AutoFlowerEgg = false
SummerTab:CreateToggle({
    Name = "Auto Flower Egg",
    CurrentValue = false, Flag = "AutoFlowerEggToggle",
    Callback = function(Value)
        getgenv().AutoFlowerEgg = Value
        if Value then
            task.spawn(function()
                SafeTeleport(flowerEggTarget)
                task.wait(1.5)
                while getgenv().AutoFlowerEgg do
                    local root = getRootPart()
                    if root then
                        local dist = (root.Position - (flowerEggTarget + Vector3.new(0, 3, 0))).Magnitude
                        if dist > 7 then
                            root.CFrame = CFrame.new(flowerEggTarget + Vector3.new(0, 3, 0))
                            root.Velocity = Vector3.new(0,0,0)
                        end
                    end
                    NetworkRemoteEvent:FireServer("HatchEgg", "Flower Kingdom Egg", getgenv().HatchAmount)
                    task.wait(1.5)
                end
            end)
        end
    end,
})
