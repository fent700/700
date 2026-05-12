-- ==========================================
-- SPLASH HUB LITE — Standalone Script
-- Features: Hatching, Potions, Summer, Obbys, Shops, Webhook, Reconnect, Anti-Lag
-- No Gumteeth Remote — Saves config locally
-- ==========================================

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local VirtualUser = game:GetService("VirtualUser")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local player = Players.LocalPlayer

local Toggles = {
    AntiAFK = true, AnimSkip = false,
    SummerFarm = false, SummerChestOpen = false,
    ObbyQueue = false, AutoReconnect = false,
    AutoLuck = false, AutoSpeed = false, AutoCoins = false, AutoMythic = false, AutoTickets = false,
    AutoEgg = false, AutoSecret = false, AutoInf = false, AutoAnniPot = false, AutoFestive = false,
    LuckRune = false, BubblesRune = false, SecretRune = false,
    WHInventory = false, WHShowQty = true, WHRareOnly = false,
    WHPingSecret = true, WHPingInf = true, WHPingMythic = true, WHPingShiny = true, WHPingSuper = true,
    EventChests = false,
}
local autoBuyActive = false
local shopPurchaseLog = {}

-- ==========================================
-- HELPERS
-- ==========================================
local function formatGemValue(n)
    if type(n) ~= "number" then return tostring(n) end
    if n >= 1e9 then return string.format("%.2fB", n / 1e9)
    elseif n >= 1e6 then return string.format("%.2fM", n / 1e6)
    elseif n >= 1e3 then return string.format("%.2fK", n / 1e3)
    else return tostring(n) end
end

-- Console
getgenv().ConsoleLogs = {}
local function consoleLog(msg)
    local logMsg = string.format("%s [Info] %s", os.date("[%H:%M:%S]"), msg)
    table.insert(getgenv().ConsoleLogs, logMsg)
    if #getgenv().ConsoleLogs > 50 then table.remove(getgenv().ConsoleLogs, 1) end
end

-- ==========================================
-- ANTI-AFK
-- ==========================================
player.Idled:Connect(function()
    if Toggles.AntiAFK then VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new()) end
end)
task.spawn(function()
    while true do
        task.wait(300)
        if Toggles.AntiAFK then pcall(function() VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new()) end) end
    end
end)

-- ==========================================
-- ANIMATION SKIPPER
-- ==========================================
local _animSkipApplied = false
local function ApplyAnimationSkip()
    if _animSkipApplied then return end
    pcall(function()
        local HatchEgg = require(game:GetService("ReplicatedStorage").Client.Effects.HatchEgg)
        if HatchEgg then
            local _origPlay = HatchEgg.Play
            HatchEgg.Play = function(self, ...)
                if Toggles.AnimSkip then pcall(function() self._hatching = false end); return end
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
-- SPLASH1 HATCH BACKEND
-- ==========================================
getgenv().AutoHatch = false
getgenv().HatchAmount = 1
getgenv().HatchDelay = 0.5
getgenv().SelectedEgg = "Magma Egg"
getgenv().HideHatchActive = false
getgenv().CurrentZone = "Main"

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NetworkRemote = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Framework"):WaitForChild("Network"):WaitForChild("Remote"):WaitForChild("RemoteEvent")

-- Inventory sync
local PlayerDataRemote = nil
for _, child in pairs(ReplicatedStorage:GetDescendants()) do
    if child.Name == "PlayerDataChanged" and child:IsA("RemoteEvent") then PlayerDataRemote = child; break end
end
if PlayerDataRemote then
    PlayerDataRemote.OnClientEvent:Connect(function(key, data)
        if key == "Pets" then getgenv().BGSI_Inventory = data end
    end)
end

-- Hide hatch animation
local PlayerGui = player:WaitForChild("PlayerGui")
local systemGuis = {Chat=true, PlayerList=true, Backpack=true, Health=true, ScreenGui=true, BubbleChat=true, TopBarApp=true}
local knownGuiNames = {}
task.spawn(function()
    task.wait(2)
    for _, gui in pairs(PlayerGui:GetChildren()) do
        if gui:IsA("ScreenGui") then knownGuiNames[gui.Name] = true end
    end
    while task.wait(0.15) do
        if getgenv().HideHatchActive then
            for _, gui in pairs(PlayerGui:GetChildren()) do
                if gui:IsA("ScreenGui") and gui.Enabled then
                    local name = string.lower(gui.Name)
                    local hide = false
                    if name:find("hatch") or name:find("egg") or name:find("result") or name:find("reveal") then hide = true end
                    if not hide and not systemGuis[gui.Name] and not knownGuiNames[gui.Name] then
                        pcall(function()
                            for _, child in pairs(gui:GetDescendants()) do
                                local cn = string.lower(child.Name)
                                if cn:find("hatch") or cn:find("petdisplay") or cn:find("eggresult") or cn:find("skip") then hide = true; break end
                            end
                        end)
                    end
                    if hide then gui.Enabled = false end
                end
            end
        end
    end
end)

-- Auto-hatch loop
task.spawn(function()
    while task.wait(getgenv().HatchDelay or 2.5) do
        if getgenv().AutoHatch then
            pcall(function() NetworkRemote:FireServer("HatchEgg", getgenv().SelectedEgg, getgenv().HatchAmount) end)
        end
    end
end)

-- ==========================================
-- RAYFIELD UI
-- ==========================================
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local Window = Rayfield:CreateWindow({
    Name = "Splash Hub Lite",
    LoadingTitle = "Loading Splash Lite...",
    LoadingSubtitle = "by Gumteeth",
    ConfigurationSaving = { Enabled = true, FolderName = "SplashLite", FileName = "SplashLiteConfig" },
    KeySystem = false,
})

local EggTab = Window:CreateTab("🥚 Hatching", 4483362458)
local PotionTab = Window:CreateTab("🧪 Potions", 4483362458)
local SummerTab = Window:CreateTab("☀️ Summer", 4483362458)
local ObbyTab = Window:CreateTab("🕹️ Obbys", 4483362458)
local ShopTab = Window:CreateTab("🛒 Shops", 4483362458)
local WebhookTab = Window:CreateTab("📡 Webhook", 4483362458)
local MiscTab = Window:CreateTab("⚙️ Misc", 4483362458)

-- ==========================================
-- 🥚 HATCHING
-- ==========================================
EggTab:CreateDropdown({
    Name = "Select Egg",
    Options = {"Common Egg","Uncommon Egg","Rare Egg","Epic Egg","Legendary Egg","Water Egg","Fire Egg","Nature Egg","Magic Egg","Alien Egg","Magma Egg","Crystal Egg","Lunar Egg","Void Egg","Heavenly Egg","Nuclear Egg","Infinity Egg","Anniversary Egg","1B Egg","Golf Egg","Cyber Egg"},
    CurrentOption = {"Magma Egg"}, MultipleOptions = false, Flag = "SelectEggDrop",
    Callback = function(O) getgenv().SelectedEgg = O[1] end,
})
EggTab:CreateInput({ Name = "Custom Egg Override", PlaceholderText = "Exact egg name...", Flag = "CustomEggInput", Callback = function(T) if T ~= "" then getgenv().SelectedEgg = T end end })
EggTab:CreateSlider({ Name = "Hatch Amount", Range = {1,12}, Increment = 1, CurrentValue = 1, Flag = "HatchAmountSlider", Callback = function(V) getgenv().HatchAmount = V end })
EggTab:CreateSlider({ Name = "Hatch Delay", Range = {0.1,2}, Increment = 0.1, CurrentValue = 0.5, Suffix = "s", Flag = "HatchSpeedSlider", Callback = function(V) getgenv().HatchDelay = V end })
EggTab:CreateToggle({ Name = "Fast Hatch", CurrentValue = false, Flag = "FastHatchToggle", Callback = function(V) getgenv().AutoHatch = V end })
EggTab:CreateToggle({ Name = "Hide Hatch Animation", CurrentValue = false, Flag = "HideHatchToggle", Callback = function(V) getgenv().HideHatchActive = V end })
EggTab:CreateToggle({ Name = "Animation Skipper", CurrentValue = false, Flag = "AnimSkipToggle", Callback = function(V) Toggles.AnimSkip = V; if V then ApplyAnimationSkip() end end })

task.wait()
-- ==========================================
-- 🧪 POTIONS & RUNES
-- ==========================================
local potionTier = "I"
local runeTier = "I"
local potionInterval = 60
local tierMap = {["I"]=1,["II"]=2,["III"]=3,["IV"]=4,["V"]=5,["Evolved"]=6,["Infinity"]=7}

PotionTab:CreateSection("Potion Settings")
PotionTab:CreateSlider({ Name = "Use Interval", Range = {1,60}, Increment = 1, Suffix = " min", CurrentValue = 1, Flag = "PotionTimer", Callback = function(V) potionInterval = V * 60 end })
PotionTab:CreateDropdown({ Name = "Potion Tier", Options = {"I","II","III","IV","V","Evolved","Infinity"}, CurrentOption = {"I"}, Flag = "PotionTierDrop", Callback = function(O) potionTier = O[1] end })
PotionTab:CreateToggle({ Name = "Auto Lucky Potion", CurrentValue = false, Flag = "AutoLuck", Callback = function(V) Toggles.AutoLuck = V end })
PotionTab:CreateToggle({ Name = "Auto Speed Potion", CurrentValue = false, Flag = "AutoSpeed", Callback = function(V) Toggles.AutoSpeed = V end })
PotionTab:CreateToggle({ Name = "Auto Coins Potion", CurrentValue = false, Flag = "AutoCoins", Callback = function(V) Toggles.AutoCoins = V end })
PotionTab:CreateToggle({ Name = "Auto Mythic Potion", CurrentValue = false, Flag = "AutoMythic", Callback = function(V) Toggles.AutoMythic = V end })
PotionTab:CreateToggle({ Name = "Auto Tickets Potion", CurrentValue = false, Flag = "AutoTickets", Callback = function(V) Toggles.AutoTickets = V end })
PotionTab:CreateSection("Special Elixirs")
PotionTab:CreateToggle({ Name = "Auto Egg Elixir", CurrentValue = false, Flag = "AutoEggElix", Callback = function(V) Toggles.AutoEgg = V end })
PotionTab:CreateToggle({ Name = "Auto Secret Elixir", CurrentValue = false, Flag = "AutoSecret", Callback = function(V) Toggles.AutoSecret = V end })
PotionTab:CreateToggle({ Name = "Auto Infinity Elixir", CurrentValue = false, Flag = "AutoInf", Callback = function(V) Toggles.AutoInf = V end })
PotionTab:CreateToggle({ Name = "Auto Anniversary Elixir", CurrentValue = false, Flag = "AutoAnniPot", Callback = function(V) Toggles.AutoAnniPot = V end })
PotionTab:CreateToggle({ Name = "Auto Festive Elixir", CurrentValue = false, Flag = "AutoFestive", Callback = function(V) Toggles.AutoFestive = V end })
PotionTab:CreateSection("Rune Settings")
PotionTab:CreateDropdown({ Name = "Rune Tier", Options = {"I","II","III"}, CurrentOption = {"I"}, Flag = "RuneTierDrop", Callback = function(O) runeTier = O[1] end })
PotionTab:CreateToggle({ Name = "Auto Luck Rune", CurrentValue = false, Flag = "LuckRune", Callback = function(V) Toggles.LuckRune = V end })
PotionTab:CreateToggle({ Name = "Auto Bubbles Rune", CurrentValue = false, Flag = "BubblesRune", Callback = function(V) Toggles.BubblesRune = V end })
PotionTab:CreateToggle({ Name = "Auto Secret Rune", CurrentValue = false, Flag = "SecretRune", Callback = function(V) Toggles.SecretRune = V end })

task.spawn(function()
    while true do
        local pT = tierMap[potionTier] or 1
        local rT = tierMap[runeTier] or 1
        pcall(function()
            local re = NetworkRemote
            if Toggles.AutoLuck then re:FireServer("UsePotion", "Lucky", pT) end
            if Toggles.AutoSpeed then re:FireServer("UsePotion", "Speed", pT) end
            if Toggles.AutoCoins then re:FireServer("UsePotion", "Coins", pT) end
            if Toggles.AutoMythic then re:FireServer("UsePotion", "Mythic", pT) end
            if Toggles.AutoTickets then re:FireServer("UsePotion", "Tickets", pT) end
            if Toggles.AutoEgg then re:FireServer("UsePotion", "Egg Elixir", pT) end
            if Toggles.AutoSecret then re:FireServer("UsePotion", "Secret Elixir", pT) end
            if Toggles.AutoInf then re:FireServer("UsePotion", "Infinity Elixir", pT) end
            if Toggles.AutoAnniPot then re:FireServer("UsePotion", "Anniversary Elixir", pT) end
            if Toggles.AutoFestive then re:FireServer("UsePotion", "Festive Elixir", pT) end
            if Toggles.LuckRune then re:FireServer("UseRune", "Lucky", rT, 1) end
            if Toggles.BubblesRune then re:FireServer("UseRune", "Bubbles", rT, 1) end
            if Toggles.SecretRune then re:FireServer("UseRune", "Secret", rT, 1) end
        end)
        task.wait(potionInterval)
    end
end)

task.wait()
-- ==========================================
-- ☀️ SUMMER EVENT
-- ==========================================
SummerTab:CreateSection("☀️ Artifact Farm")
SummerTab:CreateLabel("Tweens around summer beach. Press V to pause/resume for digging.")

local summerFarmSpeed = 60
local summerSellInterval = 300
local summerLastSellTime = 0
local summerCurrentTween = nil
local summerIsPaused = false
local summerArtifactsFound = 0
local summerFarmLaps = 0
local summerChestCount = 0
local summerSellTarget = Vector3.new(-251.13, 11.01, -4889.93)

local summerWaypoints = {
    Vector3.new(-324.82, 11.01, -4905.78), Vector3.new(-324.83, 11.01, -4945.48),
    Vector3.new(-324.83, 11.01, -4983.02), Vector3.new(-301.82, 11.01, -4981.65),
    Vector3.new(-302.58, 11.01, -4946.31), Vector3.new(-307.30, 11.01, -4897.26),
    Vector3.new(-310.58, 11.01, -4863.20), Vector3.new(-311.91, 11.01, -4833.42),
    Vector3.new(-280.20, 11.01, -4835.50), Vector3.new(-263.05, 11.01, -4835.81),
    Vector3.new(-263.80, 11.01, -4878.59), Vector3.new(-264.47, 11.01, -4916.67),
    Vector3.new(-265.15, 11.01, -4955.82), Vector3.new(-265.54, 11.01, -4977.79),
}

local function summerTweenTo(pos)
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local t = math.max(0.1, (root.Position - pos).Magnitude / summerFarmSpeed)
    summerCurrentTween = TweenService:Create(root, TweenInfo.new(t, Enum.EasingStyle.Linear), {CFrame = CFrame.new(pos)})
    summerCurrentTween:Play()
    summerCurrentTween.Completed:Wait()
end

UIS.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.V and Toggles.SummerFarm then
        summerIsPaused = not summerIsPaused
        if summerCurrentTween then
            if summerIsPaused then summerCurrentTween:Pause() else summerCurrentTween:Play() end
        end
        Rayfield:Notify({ Title = "Summer Farm", Content = summerIsPaused and "⏸️ Paused" or "▶️ Resumed", Duration = 2 })
    end
end)

pcall(function()
    ReplicatedStorage.Remotes.PlayerDataChanged.OnClientEvent:Connect(function(key, value)
        if key == "TotalArtifactsFound" and type(value) == "number" then summerArtifactsFound = value end
    end)
end)

SummerTab:CreateSlider({ Name = "Move Speed", Range = {20,150}, Increment = 5, Suffix = " spd", CurrentValue = 60, Flag = "SummerSpeed", Callback = function(V) summerFarmSpeed = V end })
SummerTab:CreateSlider({ Name = "Sell Timer", Range = {1,60}, Increment = 1, Suffix = " min", CurrentValue = 5, Flag = "SummerSellTimer", Callback = function(V) summerSellInterval = V * 60 end })

local summerStatusLabel = SummerTab:CreateLabel("Farm: Idle | Laps: 0")

SummerTab:CreateToggle({ Name = "☀️ Auto Artifact Farm", CurrentValue = false, Flag = "SummerFarm", Callback = function(V)
    Toggles.SummerFarm = V
    summerFarmLaps = 0
    if V then
        summerLastSellTime = tick()
        task.spawn(function()
            consoleLog("Summer Farm: Started")
            while Toggles.SummerFarm do
                for _, point in ipairs(summerWaypoints) do
                    if not Toggles.SummerFarm then if summerCurrentTween then summerCurrentTween:Cancel() end break end
                    while summerIsPaused and Toggles.SummerFarm do task.wait(0.5) end
                    if tick() - summerLastSellTime >= summerSellInterval then
                        summerTweenTo(summerSellTarget); task.wait(1.5)
                        pcall(function() NetworkRemote:FireServer("SellArtifacts") end)
                        task.wait(1); summerLastSellTime = tick()
                        consoleLog("Summer Farm: Auto-sold")
                    end
                    summerTweenTo(point)
                end
                summerFarmLaps = summerFarmLaps + 1
                summerStatusLabel:Set("Farm: Running | Laps: " .. summerFarmLaps .. " | Artifacts: " .. summerArtifactsFound)
                task.wait()
            end
            if summerCurrentTween then summerCurrentTween:Cancel() end
            summerStatusLabel:Set("Farm: Idle | Laps: " .. summerFarmLaps)
            consoleLog("Summer Farm: Stopped after " .. summerFarmLaps .. " laps")
        end)
    else
        if summerCurrentTween then summerCurrentTween:Cancel() end
    end
end })

SummerTab:CreateButton({ Name = "💰 Sell Artifacts Now", Callback = function()
    pcall(function() NetworkRemote:FireServer("SellArtifacts") end)
    Rayfield:Notify({ Title = "Summer", Content = "Sell sent!", Duration = 2 })
end })

SummerTab:CreateSection("☀️ Summer Chests")
local summerChestLabel = SummerTab:CreateLabel("Chests: 0")
SummerTab:CreateToggle({ Name = "☀️ Auto Open Summer Chests", CurrentValue = false, Flag = "SummerChestOpen", Callback = function(V)
    Toggles.SummerChestOpen = V; summerChestCount = 0
    if V then
        task.spawn(function()
            consoleLog("Summer Chests: Started")
            while Toggles.SummerChestOpen do
                pcall(function() NetworkRemote:FireServer("UnlockEventChest", "Summer Chest", true) end)
                summerChestCount = summerChestCount + 1
                summerChestLabel:Set("Chests: " .. summerChestCount)
                task.wait(0.5)
            end
        end)
    end
end })

task.wait()
-- ==========================================
-- 🕹️ OBBYS
-- ==========================================
ObbyTab:CreateSection("Obby Smart Queue")
ObbyTab:CreateLabel("Priority-based obby queue. Teleports to spawn, runs obby, returns.")

local obbyData = {
    Easy =   { Cooldown = 185,  LastRun = 0, Toggle = false, Priority = 1 },
    Medium = { Cooldown = 305,  LastRun = 0, Toggle = false, Priority = 2 },
    Hard =   { Cooldown = 610,  LastRun = 0, Toggle = false, Priority = 3 },
}
local obbyLagDelay = 2
local spawnLocation = "Workspace.Worlds.Seven Seas.Areas.Classic Island.HouseSpawn"

ObbyTab:CreateToggle({ Name = "Easy Obby (3m CD)", CurrentValue = false, Flag = "ObbyEasy", Callback = function(V) obbyData.Easy.Toggle = V end })
ObbyTab:CreateDropdown({ Name = "Easy Priority", Options = {"1","2","3"}, CurrentOption = {"1"}, Flag = "ObbyEasyPri", Callback = function(v) obbyData.Easy.Priority = tonumber(v[1]) end })
ObbyTab:CreateToggle({ Name = "Medium Obby (5m CD)", CurrentValue = false, Flag = "ObbyMedium", Callback = function(V) obbyData.Medium.Toggle = V end })
ObbyTab:CreateDropdown({ Name = "Medium Priority", Options = {"1","2","3"}, CurrentOption = {"2"}, Flag = "ObbyMedPri", Callback = function(v) obbyData.Medium.Priority = tonumber(v[1]) end })
ObbyTab:CreateToggle({ Name = "Hard Obby (10m CD)", CurrentValue = false, Flag = "ObbyHard", Callback = function(V) obbyData.Hard.Toggle = V end })
ObbyTab:CreateDropdown({ Name = "Hard Priority", Options = {"1","2","3"}, CurrentOption = {"3"}, Flag = "ObbyHardPri", Callback = function(v) obbyData.Hard.Priority = tonumber(v[1]) end })
ObbyTab:CreateSlider({ Name = "Lag Delay", Range = {1,5}, Increment = 0.5, CurrentValue = 2, Suffix = "s", Flag = "ObbyLagDelay", Callback = function(V) obbyLagDelay = V end })

local obbyStatusLabel = ObbyTab:CreateLabel("Queue: Idle")

ObbyTab:CreateToggle({ Name = "Start Obby Queue", CurrentValue = false, Flag = "ObbyQueue", Callback = function(V)
    Toggles.ObbyQueue = V
    if V then
        task.spawn(function()
            while Toggles.ObbyQueue do
                local ct = os.time()
                local ready = {}
                for name, data in pairs(obbyData) do
                    if data.Toggle and (ct - data.LastRun >= data.Cooldown) then
                        table.insert(ready, { Name = name, Data = data })
                    end
                end
                if #ready > 0 then
                    table.sort(ready, function(a, b) return a.Data.Priority < b.Data.Priority end)
                    local target = ready[1].Name
                    obbyStatusLabel:Set("Queue: Running " .. target)
                    consoleLog("Obby: " .. target)
                    pcall(function()
                        local char = player.Character
                        local root = char and char:FindFirstChild("HumanoidRootPart")
                        local saved = root and root.CFrame or nil
                        getgenv().ObbySavedCFrame = saved
                        NetworkRemote:FireServer("Teleport", spawnLocation)
                        task.wait(obbyLagDelay)
                        NetworkRemote:FireServer("StartObby", target)
                        task.wait(obbyLagDelay)
                        NetworkRemote:FireServer("CompleteObby")
                        task.wait(obbyLagDelay)
                        NetworkRemote:FireServer("ClaimObbyChest", false)
                        task.wait(obbyLagDelay)
                        NetworkRemote:FireServer("ClaimObbyChest", false)
                        task.wait(obbyLagDelay)
                        if saved and root then root.CFrame = saved
                        else NetworkRemote:FireServer("Teleport", spawnLocation) end
                        getgenv().ObbySavedCFrame = nil
                    end)
                    obbyData[target].LastRun = os.time()
                    obbyStatusLabel:Set("Queue: Done " .. target .. ". Waiting...")
                else
                    local minW = math.huge
                    for _, data in pairs(obbyData) do
                        if data.Toggle then
                            local rem = data.Cooldown - (ct - data.LastRun)
                            if rem > 0 and rem < minW then minW = rem end
                        end
                    end
                    obbyStatusLabel:Set(minW < math.huge and ("Queue: Next in ~" .. math.ceil(minW) .. "s") or "Queue: None enabled")
                end
                task.wait(1)
            end
            obbyStatusLabel:Set("Queue: Stopped")
        end)
    end
end })

task.wait()
-- ==========================================
-- 🛒 SHOPS
-- ==========================================
local rerollCooldownWait = 10
local ShopConfig = {
    Alien = { S1=false,S2=false,S3=false,RerollOn=false,MaxRerolls=1 },
    Blackmarket = { S1=false,S2=false,S3=false,RerollOn=false,MaxRerolls=1 },
    Dice = { S1=false,S2=false,S3=false,RerollOn=false,MaxRerolls=1 },
    Shadow = { S1=false,S2=false,S3=false,RerollOn=false,MaxRerolls=1 },
}

ShopTab:CreateSection("Market Automation")
local ShopLogLabel = ShopTab:CreateLabel("Last: Waiting...")

local function buyShopItem(shopId, slot)
    ShopLogLabel:Set("Buying " .. shopId .. " [Slot " .. slot .. "]")
    consoleLog("Buy " .. shopId .. " S" .. slot)
    for i = 1, 2 do pcall(function() NetworkRemote:FireServer("BuyShopItem", shopId, slot, true) end); task.wait(0.1) end
end

local function rerollShop(shopId)
    ShopLogLabel:Set("Rerolling " .. shopId)
    pcall(function() NetworkRemote:FireServer("ShopFreeReroll", shopId) end)
end

local function runShopAuto(shopId, name, cfg)
    if not cfg.S1 and not cfg.S2 and not cfg.S3 and not cfg.RerollOn then return end
    local rerolls = 0
    local maxR = cfg.RerollOn and cfg.MaxRerolls or 0
    while rerolls <= maxR and autoBuyActive do
        local count = 0
        if cfg.S1 then buyShopItem(shopId,1); count=count+1; task.wait(0.3) end
        if cfg.S2 then buyShopItem(shopId,2); count=count+1; task.wait(0.3) end
        if cfg.S3 then buyShopItem(shopId,3); count=count+1; task.wait(0.3) end
        if count > 0 then
            table.insert(shopPurchaseLog, {shop=name, slots=count, time=os.date("%H:%M:%S")})
            if #shopPurchaseLog > 50 then table.remove(shopPurchaseLog, 1) end
        end
        if rerolls < maxR then rerollShop(shopId); task.wait(rerollCooldownWait); rerolls=rerolls+1
        else break end
        task.wait(0.5)
    end
end

ShopTab:CreateToggle({ Name = "START AUTO-BUY & REROLL", CurrentValue = false, Flag = "MarketMasterToggle", Callback = function(V)
    autoBuyActive = V
    if V then
        task.spawn(function()
            while autoBuyActive do
                runShopAuto("alien-shop", "Alien", ShopConfig.Alien)
                runShopAuto("shard-shop", "Blackmarket", ShopConfig.Blackmarket)
                runShopAuto("dice-shop", "Dice", ShopConfig.Dice)
                runShopAuto("shadow-shop", "Shadow", ShopConfig.Shadow)
                ShopLogLabel:Set("Cycle done. Waiting 30m...")
                for i = 1, 1800 do if not autoBuyActive then break end task.wait(1) end
            end
        end)
    end
end })

ShopTab:CreateSection("Alien Shop")
ShopTab:CreateToggle({Name="Slot 1",Flag="AlienS1",Callback=function(v) ShopConfig.Alien.S1=v end})
ShopTab:CreateToggle({Name="Slot 2",Flag="AlienS2",Callback=function(v) ShopConfig.Alien.S2=v end})
ShopTab:CreateToggle({Name="Slot 3",Flag="AlienS3",Callback=function(v) ShopConfig.Alien.S3=v end})
ShopTab:CreateToggle({Name="Rerolls",Flag="AlienReroll",Callback=function(v) ShopConfig.Alien.RerollOn=v end})
ShopTab:CreateSlider({Name="Max Rerolls",Range={1,5},Increment=1,CurrentValue=1,Flag="AlienMaxR",Callback=function(v) ShopConfig.Alien.MaxRerolls=v end})

ShopTab:CreateSection("Blackmarket")
ShopTab:CreateToggle({Name="Slot 1",Flag="BMS1",Callback=function(v) ShopConfig.Blackmarket.S1=v end})
ShopTab:CreateToggle({Name="Slot 2",Flag="BMS2",Callback=function(v) ShopConfig.Blackmarket.S2=v end})
ShopTab:CreateToggle({Name="Slot 3",Flag="BMS3",Callback=function(v) ShopConfig.Blackmarket.S3=v end})
ShopTab:CreateToggle({Name="Rerolls",Flag="BMReroll",Callback=function(v) ShopConfig.Blackmarket.RerollOn=v end})
ShopTab:CreateSlider({Name="Max Rerolls",Range={1,5},Increment=1,CurrentValue=1,Flag="BMMaxR",Callback=function(v) ShopConfig.Blackmarket.MaxRerolls=v end})

ShopTab:CreateSection("Dice Merchant")
ShopTab:CreateToggle({Name="Slot 1",Flag="DiceS1",Callback=function(v) ShopConfig.Dice.S1=v end})
ShopTab:CreateToggle({Name="Slot 2",Flag="DiceS2",Callback=function(v) ShopConfig.Dice.S2=v end})
ShopTab:CreateToggle({Name="Slot 3",Flag="DiceS3",Callback=function(v) ShopConfig.Dice.S3=v end})
ShopTab:CreateToggle({Name="Rerolls",Flag="DiceReroll",Callback=function(v) ShopConfig.Dice.RerollOn=v end})
ShopTab:CreateSlider({Name="Max Rerolls",Range={1,5},Increment=1,CurrentValue=1,Flag="DiceMaxR",Callback=function(v) ShopConfig.Dice.MaxRerolls=v end})

ShopTab:CreateSection("Shadow Shop")
ShopTab:CreateToggle({Name="Slot 1",Flag="ShadowS1",Callback=function(v) ShopConfig.Shadow.S1=v end})
ShopTab:CreateToggle({Name="Slot 2",Flag="ShadowS2",Callback=function(v) ShopConfig.Shadow.S2=v end})
ShopTab:CreateToggle({Name="Slot 3",Flag="ShadowS3",Callback=function(v) ShopConfig.Shadow.S3=v end})
ShopTab:CreateToggle({Name="Rerolls",Flag="ShadowReroll",Callback=function(v) ShopConfig.Shadow.RerollOn=v end})
ShopTab:CreateSlider({Name="Max Rerolls",Range={1,5},Increment=1,CurrentValue=1,Flag="ShadowMaxR",Callback=function(v) ShopConfig.Shadow.MaxRerolls=v end})

task.wait()
-- ==========================================
-- 📡 WEBHOOK
-- ==========================================
local wh_url = ""
local wh_cool = 5

WebhookTab:CreateInput({ Name = "Webhook URL", PlaceholderText = "Paste here...", Flag = "WH_URL", Callback = function(T) wh_url = T end })
WebhookTab:CreateSlider({ Name = "Cooldown", Range = {1,60}, Increment = 1, Suffix = " min", CurrentValue = 5, Flag = "WH_Slider", Callback = function(V) wh_cool = V end })
WebhookTab:CreateButton({ Name = "Test Connection", Callback = function()
    if wh_url ~= "" then pcall(function() request({Url=wh_url,Method="POST",Headers={["Content-Type"]="application/json"},Body=HttpService:JSONEncode({content="📡 Splash Lite Connected!"})}) end) end
end })

WebhookTab:CreateSection("Auto-Feed")
WebhookTab:CreateToggle({ Name = "Enable Auto-Feed", CurrentValue = false, Flag = "AutoWH", Callback = function(V)
    Toggles.AutoWH = V
    if V then
        task.spawn(function()
            while Toggles.AutoWH do
                if wh_url ~= "" then
                    pcall(function()
                        local fields = {}
                        -- Automation status
                        local autos = {}
                        if getgenv().AutoHatch then table.insert(autos, "🥚 Hatch: Active") end
                        if Toggles.ObbyQueue then table.insert(autos, "🏃 Obby: Active") end
                        if autoBuyActive then table.insert(autos, "🛒 Shops: Active") end
                        if Toggles.SummerFarm then table.insert(autos, "☀️ Farm: " .. summerFarmLaps .. " laps") end
                        if Toggles.SummerChestOpen then table.insert(autos, "☀️ Chests: " .. summerChestCount) end
                        if summerArtifactsFound > 0 then table.insert(autos, "🏝️ Artifacts: " .. summerArtifactsFound) end
                        if #autos > 0 then table.insert(fields, {name="⚙️ Status", value=table.concat(autos,"\n"), inline=false}) end
                        -- Shop log
                        if #shopPurchaseLog > 0 then
                            local s = ""
                            for _, log in ipairs(shopPurchaseLog) do s = s .. log.shop .. ": " .. log.slots .. " [" .. log.time .. "]\n" end
                            table.insert(fields, {name="🛒 Shops", value=s:sub(1,1024), inline=false})
                            shopPurchaseLog = {}
                        end
                        -- Console
                        if getgenv().ConsoleLogs and #getgenv().ConsoleLogs > 0 then
                            local slice = {}
                            local start = math.max(1, #getgenv().ConsoleLogs - 15)
                            for i = start, #getgenv().ConsoleLogs do table.insert(slice, getgenv().ConsoleLogs[i]) end
                            table.insert(fields, {name="💻 Console", value="```\n" .. table.concat(slice,"\n") .. "\n```", inline=false})
                        end
                        request({Url=wh_url,Method="POST",Headers={["Content-Type"]="application/json"},Body=HttpService:JSONEncode({
                            embeds={{title="Splash Lite | Tracker",description="Player: **"..player.Name.."**",color=43775,fields=fields,footer={text="Splash Lite • "..os.date("%H:%M:%S")}}}
                        })})
                    end)
                end
                task.wait(wh_cool * 60)
            end
        end)
    end
end })

WebhookTab:CreateSection("Ping Options")
getgenv().WHPingID = ""
WebhookTab:CreateInput({ Name = "Discord UserID", PlaceholderText = "ID for pings", Flag = "WHPingID", Callback = function(T) getgenv().WHPingID = T end })
WebhookTab:CreateToggle({ Name = "Ping on Secret", CurrentValue = true, Flag = "WHPingSecret", Callback = function(V) Toggles.WHPingSecret = V end })
WebhookTab:CreateToggle({ Name = "Ping on Mythic", CurrentValue = true, Flag = "WHPingMythic", Callback = function(V) Toggles.WHPingMythic = V end })
WebhookTab:CreateToggle({ Name = "Ping on Shiny", CurrentValue = true, Flag = "WHPingShiny", Callback = function(V) Toggles.WHPingShiny = V end })

task.wait()
-- ==========================================
-- ⚙️ MISC, RECONNECT & ANTI-LAG
-- ==========================================
MiscTab:CreateSection("Anti-AFK")
MiscTab:CreateToggle({ Name = "Anti-AFK", CurrentValue = true, Flag = "AntiAFK", Callback = function(V) Toggles.AntiAFK = V end })

MiscTab:CreateSection("Reconnect")
local psLink = ""
local reconnectType = "Current Server"
local reconnectHours = 1
local reconnectTargetTime = 0

MiscTab:CreateInput({ Name = "Private Server Link / JobId", PlaceholderText = "Paste VIP Link...", Flag = "PSInput", Callback = function(T) psLink = T end })
MiscTab:CreateDropdown({ Name = "Reconnect Type", Options = {"Current Server","Private Server"}, CurrentOption = {"Current Server"}, Flag = "ReconnectType", Callback = function(O) reconnectType = O[1] end })
MiscTab:CreateSlider({ Name = "Reconnect Timer", Range = {1,48}, Increment = 1, Suffix = " hrs", CurrentValue = 1, Flag = "ReconnectTimer", Callback = function(V) reconnectHours = V end })

local function DoReconnect()
    local ts = TeleportService
    if reconnectType == "Current Server" then
        pcall(function() ts:TeleportToPlaceInstance(game.PlaceId, game.JobId, player) end)
        task.wait(2)
        pcall(function() ts:Teleport(game.PlaceId, player) end)
    else
        if psLink ~= "" then
            local code = psLink:match("privateServerLinkCode=([^&]+)")
            if code then pcall(function() ts:TeleportToPrivateServer(game.PlaceId, code, {player}) end)
            else pcall(function() ts:TeleportToPlaceInstance(game.PlaceId, psLink, player) end) end
        else pcall(function() ts:Teleport(game.PlaceId, player) end) end
    end
end

local function PrepareAndReconnect()
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        local pos = hrp.Position
        pcall(function() writefile("SplashLite_SavedPos.txt", string.format("%.2f,%.2f,%.2f", pos.X, pos.Y, pos.Z)) end)
    end
    consoleLog("Reconnecting...")
    Rayfield:Notify({Title="Reconnect", Content="Saving position. Reconnecting in 2s...", Duration=2})
    task.wait(2)
    DoReconnect()
end

MiscTab:CreateToggle({ Name = "Auto-Reconnect Timer", CurrentValue = false, Flag = "AutoReconnect", Callback = function(V)
    Toggles.AutoReconnect = V
    if V then
        local hrs = reconnectHours
        pcall(function()
            if Rayfield.Flags and Rayfield.Flags["ReconnectTimer"] then
                local v = Rayfield.Flags["ReconnectTimer"].CurrentValue
                if type(v) == "number" and v >= 1 then hrs = v; reconnectHours = v end
            end
        end)
        reconnectTargetTime = os.time() + (hrs * 3600)
        consoleLog("Auto-Reconnect: " .. hrs .. "h timer")
        task.spawn(function()
            while Toggles.AutoReconnect do
                if os.time() >= reconnectTargetTime - 10 then PrepareAndReconnect(); break end
                task.wait(1)
            end
        end)
    end
end })
MiscTab:CreateButton({ Name = "Reconnect NOW", Callback = function() PrepareAndReconnect() end })

MiscTab:CreateSection("Anti-Lag / FPS Boost")
local mapCache = {}
MiscTab:CreateToggle({ Name = "Hide Map (FPS Boost)", CurrentValue = false, Flag = "HideMap", Callback = function(V)
    task.spawn(function()
        if V then
            pcall(function()
                for _, v in pairs(workspace:GetDescendants()) do
                    if (v:IsA("BasePart") or v:IsA("Texture") or v:IsA("Decal")) and not v.Parent:FindFirstChild("Humanoid") then
                        if not mapCache[v] then mapCache[v] = v.Transparency end
                        v.Transparency = 1
                    end
                end
            end)
        else
            pcall(function()
                for obj, t in pairs(mapCache) do if obj and obj.Parent then obj.Transparency = t end end
                mapCache = {}
            end)
        end
    end)
end })

local blackScreenGui = nil
MiscTab:CreateToggle({ Name = "Black Screen (Max FPS)", CurrentValue = false, Flag = "BlackToggle", Callback = function(V)
    task.spawn(function()
        local pg = player:WaitForChild("PlayerGui")
        if V then
            pcall(function()
                if not blackScreenGui then
                    blackScreenGui = Instance.new("ScreenGui")
                    blackScreenGui.Name = "SplashLiteBlack"
                    blackScreenGui.ResetOnSpawn = false
                    blackScreenGui.IgnoreGuiInset = true
                    local f = Instance.new("Frame"); f.Size = UDim2.new(1,0,1,0); f.BackgroundColor3 = Color3.new(0,0,0); f.Parent = blackScreenGui
                    local t = Instance.new("TextLabel"); t.Size = UDim2.new(1,0,1,0); t.BackgroundTransparency = 1
                    t.Text = "SPLASH LITE — BLACK SCREEN ACTIVE"; t.TextColor3 = Color3.new(1,1,1); t.TextSize = 24; t.Parent = f
                    blackScreenGui.Parent = pg
                    RunService:Set3dRenderingEnabled(false)
                end
            end)
        else
            pcall(function()
                if blackScreenGui then blackScreenGui:Destroy(); blackScreenGui = nil end
                RunService:Set3dRenderingEnabled(true)
            end)
        end
    end)
end })

MiscTab:CreateSection("Tools")
MiscTab:CreateButton({ Name = "Load Cobalt", Callback = function()
    pcall(function() loadstring(game:HttpGet("https://github.com/notpoiu/cobalt/releases/latest/download/Cobalt.luau"))() end)
end })

-- Restore position on rejoin
task.spawn(function()
    task.wait(5)
    pcall(function()
        if isfile and isfile("SplashLite_SavedPos.txt") then
            local raw = readfile("SplashLite_SavedPos.txt")
            local x, y, z = raw:match("([^,]+),([^,]+),([^,]+)")
            if x then
                local char = player.Character or player.CharacterAdded:Wait()
                local hrp = char:WaitForChild("HumanoidRootPart", 10)
                if hrp then
                    hrp.CFrame = CFrame.new(tonumber(x), tonumber(y), tonumber(z))
                    consoleLog("Restored saved position")
                end
            end
            delfile("SplashLite_SavedPos.txt")
        end
    end)
end)

Rayfield:Notify({ Title = "Splash Lite Loaded!", Content = "All features ready. Config saves automatically.", Duration = 5, Image = 4483362458 })
consoleLog("Splash Lite loaded successfully")
