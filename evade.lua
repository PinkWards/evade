-- ╔═══════════════════════════════════════════════════════════════╗
-- ║ EVADE HELPER - FIXED ITEM FARM V2                            ║
-- ╚═══════════════════════════════════════════════════════════════╝

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local Debris = game:GetService("Debris")

local Player = Players.LocalPlayer

--══════════════════════════════════════════════════════════════════
-- FEATURE STATES
--══════════════════════════════════════════════════════════════════

local FeatureStates = {
    AntiAFK = true,
    EasyTrimp = false,
    InvisBorder = false,
    AntiNextbot = false,
    AutoItemFarm = false
}

--══════════════════════════════════════════════════════════════════
-- CONFIG
--══════════════════════════════════════════════════════════════════

local FOV_VALUE = 120

-- ITEM FARM CONFIG
local COLLECTION_RADIUS = 25       -- Collect all items within this range
local COLLECT_TIME = 0.3           -- Stay at each spot for this long to collect nearby items

-- ANTI-NEXTBOT CONFIG
local ANTI_NEXTBOT_DISTANCE = 60
local MIN_SAFE_DISTANCE = 100
local TELEPORT_COOLDOWN = 0.1

-- BHOP CONFIG
local BHOP = {
    PredictDistance = 1.6,
    CoyoteTime = 0.06,
    JumpBuffer = 0.08,
    MomentumPreserve = 0.98,
    JumpCooldown = 0.25
}

-- RAMP BOOST
local RAMP_ON = true
local RAMP_MIN_SPEED = 15
local RAMP_MIN_UP = 5
local RAMP_DELAY = 0.15
local RAMP_BOOST_H = 0.35
local RAMP_BOOST_V = 0.15
local RAMP_MAX_H = 25
local RAMP_MAX_V = 12
local RAMP_CD = 0.5

-- FREEFALL BOOST
local FREEFALL_ON = true
local FREEFALL_MIN_FALL = 18
local FREEFALL_MIN_AIR = 0.35
local FREEFALL_BOOST_H = 0.7
local FREEFALL_BOOST_V = 0.5
local FREEFALL_MAX_H = 45
local FREEFALL_MAX_V = 22
local FREEFALL_CD = 0.4

-- SLOPE BOUNCE
local BOUNCE_ON = true
local BOUNCE_MIN_SLOPE = 15
local BOUNCE_MAX_SLOPE = 60
local BOUNCE_MIN_SPEED = 8
local BOUNCE_POWER = 0.12
local BOUNCE_MAX_V = 12
local BOUNCE_CD = 0.2

-- PROTECTION
local SLIDE_PROTECT = 0.4
local BACKSLIDE_PROTECT = 1.0
local MAX_SPEED = 180

-- TRIMP
local TRIMP_BASE_SPEED = 50
local TRIMP_EXTRA_SPEED = 100

--══════════════════════════════════════════════════════════════════
-- STATE
--══════════════════════════════════════════════════════════════════

local Hum, Root
local HoldSpace = false
local FullbrightOn = false
local SavedLight
local GUI, LastCam

local StoredSpd, StoredDirX, StoredDirZ = 0, 0, 0
local WasGnd = true
local LastGndTime = 0
local LastJumpReq = 0
local LastJumpExecute = 0
local JumpBuf = false

local AirStart = 0
local MaxFall = 0
local AirTime = 0
local LaunchY, LaunchSpd, LaunchDirX, LaunchDirZ = 0, 0, 0, 0

local RampCD, FreefallCD, SlideCD, BackslideCD, BounceCD = 0, 0, 0, 0, 0
local RampPending = false
local RampApplied = false
local JustLanded = false
local WasPlayerJump = false

local FrameCount = 0
local AntiAFKConnection = nil

local TrimpSpeed = TRIMP_BASE_SPEED
local TrimpAirTick = 0
local TrimpAirborne = false
local TrimpPush = nil
local TrimpLast = tick()

local SelfReviveCooldown = 0
local LastAntiNextbotTP = 0

-- Item Farm State
local LastItemTP = 0
local CurrentItemPos = nil

-- Connections
local AutoItemFarmConnection = nil
local AntiNextbotConnection = nil

-- Nextbot names cache
local NextbotNames = {}

--══════════════════════════════════════════════════════════════════
-- MATH
--══════════════════════════════════════════════════════════════════

local sqrt = math.sqrt
local clamp = math.clamp
local abs = math.abs
local min = math.min
local max = math.max
local acos = math.acos
local deg = math.deg
local V3 = Vector3.new

--══════════════════════════════════════════════════════════════════
-- RAYCAST
--══════════════════════════════════════════════════════════════════

local RayParams = RaycastParams.new()
RayParams.FilterType = Enum.RaycastFilterType.Exclude
RayParams.IgnoreWater = true

local function GetFilter()
    local f = {}
    local n = 0
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then 
            n = n + 1 
            f[n] = p.Character 
        end
    end
    local nb = workspace:FindFirstChild("Nextbots")
    if nb then n = n + 1; f[n] = nb end
    local npcs = workspace:FindFirstChild("NPCs")
    if npcs then n = n + 1; f[n] = npcs end
    return f
end

local function IsValidGround(instance)
    return instance and instance.CanCollide
end

--══════════════════════════════════════════════════════════════════
-- HELPERS
--═══════���══════════════════════════════════════════════════════════

local function IsGnd()
    return Hum and Hum.FloorMaterial ~= Enum.Material.Air
end

local function GetVel()
    if not Root then return 0, 0, 0, 0 end
    local v = Root.AssemblyLinearVelocity
    return v.X, v.Y, v.Z, sqrt(v.X * v.X + v.Z * v.Z)
end

local function GetDir(vx, vz, hs)
    if hs > 0.5 then return vx / hs, vz / hs end
    if not Root then return 0, 1 end
    local l = Root.CFrame.LookVector
    return l.X, l.Z
end

local function SetHVel(x, z)
    if not Root then return end
    local m = x * x + z * z
    if m > MAX_SPEED * MAX_SPEED then
        local s = MAX_SPEED / sqrt(m)
        x, z = x * s, z * s
    end
    Root.AssemblyLinearVelocity = V3(x, Root.AssemblyLinearVelocity.Y, z)
end

local function GetSlopeInfo()
    if not Root then return 0, 0, 0, nil end
    RayParams.FilterDescendantsInstances = GetFilter()
    local result = workspace:Raycast(Root.Position + V3(0, 0.5, 0), V3(0, -4, 0), RayParams)
    if result and result.Instance and IsValidGround(result.Instance) then
        local normal = result.Normal
        return deg(acos(clamp(normal.Y, -1, 1))), normal.X, normal.Z, result.Instance
    end
    return 0, 0, 0, nil
end

local function IsSliding()
    if not IsGnd() then return false end
    local vx, vy, vz, hs = GetVel()
    if hs < 5 then return false end
    local c = workspace.CurrentCamera
    if not c then return false end
    local l = c.CFrame.LookVector
    local dx, dz = GetDir(vx, vz, hs)
    return (l.X * dx + l.Z * dz) < -0.3
end

local function IsUphillBackslide()
    if not IsGnd() then return false end
    local vx, vy, vz, hs = GetVel()
    if hs < 3 then return false end
    local slope, sNX, sNZ = GetSlopeInfo()
    if slope < 10 then return false end
    local c = workspace.CurrentCamera
    if not c then return false end
    local l = c.CFrame.LookVector
    local dx, dz = GetDir(vx, vz, hs)
    if (l.X * dx + l.Z * dz) >= -0.2 then return false end
    local sm = sqrt(sNX * sNX + sNZ * sNZ)
    if sm < 0.01 then return false end
    return (dx * sNX / sm + dz * sNZ / sm) > 0.2
end

local function IsAboutToLand()
    if not Root or Root.AssemblyLinearVelocity.Y > 1 then return false end
    RayParams.FilterDescendantsInstances = GetFilter()
    local result = workspace:Raycast(Root.Position, V3(0, -BHOP.PredictDistance, 0), RayParams)
    return result and result.Instance and IsValidGround(result.Instance)
end

--══════════════════════════════════════════════════════════════════
-- NEXTBOT DETECTION
--══════════════════════════════════════════════════════════════════

local function RefreshNextbotNames()
    NextbotNames = {}
    local npcsFolder = ReplicatedStorage:FindFirstChild("NPCs")
    if npcsFolder then
        for _, npc in ipairs(npcsFolder:GetChildren()) do
            NextbotNames[npc.Name:lower()] = true
        end
    end
end

local function IsNextbot(model)
    if not model or not model:IsA("Model") then return false end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Character == model then return false end
    end
    return NextbotNames[model.Name:lower()] or false
end

--══════════════════════════════════════════════════════════════════
-- INVISIBLE BORDER
--══════════════════════════════════════════════════════════════════

local function ToggleInvisBorder()
    FeatureStates.InvisBorder = not FeatureStates.InvisBorder
    local invisPartsFolder = workspace:FindFirstChild("Game") and workspace.Game:FindFirstChild("Map") and workspace.Game.Map:FindFirstChild("InvisParts")
    if invisPartsFolder then
        for _, obj in ipairs(invisPartsFolder:GetDescendants()) do
            if obj:IsA("BasePart") then obj.CanCollide = not FeatureStates.InvisBorder end
        end
        print("[NOBORDER] " .. (FeatureStates.InvisBorder and "Removed!" or "Restored!"))
    else
        print("[NOBORDER] Not found")
        FeatureStates.InvisBorder = false
    end
    UpdateGUIButtons()
end

--══════════════════════════════════════════════════════════════════
-- ANTI-NEXTBOT
--══════════════════════════════════════════════════════════════════

local function GetAllNextbots()
    local nextbots = {}
    local npcsFolder = workspace:FindFirstChild("NPCs")
    if npcsFolder then
        for _, model in ipairs(npcsFolder:GetChildren()) do
            if model:IsA("Model") and IsNextbot(model) then
                local hrp = model:FindFirstChild("HumanoidRootPart")
                if hrp then table.insert(nextbots, hrp.Position) end
            end
        end
    end
    local playersFolder = workspace:FindFirstChild("Game") and workspace.Game:FindFirstChild("Players")
    if playersFolder then
        for _, model in ipairs(playersFolder:GetChildren()) do
            if model:IsA("Model") and IsNextbot(model) then
                local hrp = model:FindFirstChild("HumanoidRootPart")
                if hrp then table.insert(nextbots, hrp.Position) end
            end
        end
    end
    return nextbots
end

local function GetClosestNextbotDistance(position, nextbots)
    local closestDist = math.huge
    for _, nextbotPos in ipairs(nextbots) do
        local dist = (position - nextbotPos).Magnitude
        if dist < closestDist then closestDist = dist end
    end
    return closestDist
end

local function GetSafeLocations()
    local locations = {}
    local spawnsFolder = workspace:FindFirstChild("Game") and workspace.Game:FindFirstChild("Map") and workspace.Game.Map:FindFirstChild("Parts") and workspace.Game.Map.Parts:FindFirstChild("Spawns")
    if spawnsFolder then
        for _, spawn in ipairs(spawnsFolder:GetChildren()) do
            if spawn:IsA("BasePart") then table.insert(locations, spawn.Position + V3(0, 3, 0)) end
        end
    end
    local securityPart = workspace:FindFirstChild("SecurityPart")
    if securityPart then table.insert(locations, securityPart.Position + V3(0, 3, 0)) end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= Player and plr.Character then
            local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
            if hrp and not plr.Character:GetAttribute("Downed") then
                table.insert(locations, hrp.Position + V3(0, 3, 0))
            end
        end
    end
    return locations
end

local function FindSafestLocation(myPos, nextbots)
    local safeLocations = GetSafeLocations()
    local bestLocation, bestDistance = nil, 0
    for _, location in ipairs(safeLocations) do
        local distFromNextbots = GetClosestNextbotDistance(location, nextbots)
        local distFromMe = (location - myPos).Magnitude
        if distFromNextbots > MIN_SAFE_DISTANCE and distFromMe > 20 and distFromNextbots > bestDistance then
            bestDistance = distFromNextbots
            bestLocation = location
        end
    end
    if not bestLocation then
        local securityPart = workspace:FindFirstChild("SecurityPart")
        if securityPart then bestLocation = securityPart.Position + V3(0, 3, 0) end
    end
    return bestLocation
end

local function HandleAntiNextbot()
    if not FeatureStates.AntiNextbot then return end
    local now = tick()
    if now - LastAntiNextbotTP < TELEPORT_COOLDOWN then return end
    
    local character = Player.Character
    local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart or character:GetAttribute("Downed") then return end
    
    local myPos = humanoidRootPart.Position
    local nextbots = GetAllNextbots()
    if #nextbots == 0 then return end
    
    if GetClosestNextbotDistance(myPos, nextbots) <= ANTI_NEXTBOT_DISTANCE then
        local safeLocation = FindSafestLocation(myPos, nextbots)
        if safeLocation then
            humanoidRootPart.CFrame = CFrame.new(safeLocation)
            LastAntiNextbotTP = now
        end
    end
end

local function StartAntiNextbot()
    if AntiNextbotConnection then return end
    RefreshNextbotNames()
    AntiNextbotConnection = RunService.RenderStepped:Connect(function()
        if FeatureStates.AntiNextbot then pcall(HandleAntiNextbot) end
    end)
end

local function StopAntiNextbot()
    if AntiNextbotConnection then
        AntiNextbotConnection:Disconnect()
        AntiNextbotConnection = nil
    end
end

local function ToggleAntiNextbot()
    FeatureStates.AntiNextbot = not FeatureStates.AntiNextbot
    if FeatureStates.AntiNextbot then
        StartAntiNextbot()
        print("[ANTI-BOT] ON")
    else
        StopAntiNextbot()
        print("[ANTI-BOT] OFF")
    end
    UpdateGUIButtons()
end

--══════════════════════════════════════════════════════════════════
-- AUTO ITEM FARM (FIXED - NO ELEVATION + BIGGER COLLECTION RANGE)
--══════════════════════════════════════════════════════════════════

local function GetCollectableItems()
    local items = {}
    
    -- Get tickets
    local tickets = workspace:FindFirstChild("Game") and workspace.Game:FindFirstChild("Effects") and workspace.Game.Effects:FindFirstChild("Tickets")
    if tickets then
        for _, ticket in ipairs(tickets:GetChildren()) do
            if ticket:IsA("Model") then
                local ticketHrp = ticket:FindFirstChild("HumanoidRootPart")
                if ticketHrp then table.insert(items, ticketHrp) end
            end
        end
    end
    
    -- Get event items from Effects folder
    local effects = workspace:FindFirstChild("Game") and workspace.Game:FindFirstChild("Effects")
    if effects then
        for _, folder in ipairs(effects:GetChildren()) do
            if folder:IsA("Folder") and folder.Name ~= "Tickets" then
                for _, item in ipairs(folder:GetChildren()) do
                    if item:IsA("Model") then
                        local itemHrp = item:FindFirstChild("HumanoidRootPart")
                        if itemHrp then table.insert(items, itemHrp) end
                    elseif item:IsA("BasePart") then
                        table.insert(items, item)
                    end
                end
            end
        end
    end
    
    -- Get event NPCs (not nextbots)
    local npcsFolder = workspace:FindFirstChild("NPCs")
    if npcsFolder then
        for _, npc in ipairs(npcsFolder:GetChildren()) do
            if npc:IsA("Model") and not IsNextbot(npc) then
                local npcHrp = npc:FindFirstChild("HumanoidRootPart")
                if npcHrp then table.insert(items, npcHrp) end
            end
        end
    end
    
    -- Check Game.Players for event NPCs
    local gamePlayers = workspace:FindFirstChild("Game") and workspace.Game:FindFirstChild("Players")
    if gamePlayers then
        for _, model in ipairs(gamePlayers:GetChildren()) do
            if model:IsA("Model") and not IsNextbot(model) then
                local isPlayer = false
                for _, plr in ipairs(Players:GetPlayers()) do
                    if plr.Character == model then isPlayer = true; break end
                end
                if not isPlayer then
                    local modelHrp = model:FindFirstChild("HumanoidRootPart")
                    if modelHrp then table.insert(items, modelHrp) end
                end
            end
        end
    end
    
    return items
end

local function GetItemsNotInRange(items, position, range)
    local outOfRange = {}
    for _, item in ipairs(items) do
        if (item.Position - position).Magnitude > range then
            table.insert(outOfRange, item)
        end
    end
    return outOfRange
end

local function FindBestItemCluster(items, myPos)
    -- Find the item that has the most other items nearby
    local bestItem = nil
    local bestScore = 0
    
    for _, item in ipairs(items) do
        local score = 0
        for _, other in ipairs(items) do
            if other ~= item then
                local dist = (item.Position - other.Position).Magnitude
                if dist <= COLLECTION_RADIUS then
                    score = score + 1
                end
            end
        end
        
        -- Also consider distance from player (prefer closer clusters)
        local distFromMe = (item.Position - myPos).Magnitude
        local distBonus = math.max(0, 500 - distFromMe) / 100
        score = score + distBonus
        
        if score > bestScore then
            bestScore = score
            bestItem = item
        end
    end
    
    return bestItem
end

local function StartAutoItemFarm()
    if AutoItemFarmConnection then return end
    RefreshNextbotNames()
    
    LastItemTP = 0
    CurrentItemPos = nil
    
    AutoItemFarmConnection = RunService.Heartbeat:Connect(function()
        if not FeatureStates.AutoItemFarm then return end
        
        local character = Player.Character
        local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
        if not character or not humanoidRootPart then return end
        
        -- Auto revive if downed
        if character:GetAttribute("Downed") then
            pcall(function()
                ReplicatedStorage.Events.Player.ChangePlayerMode:FireServer(true)
            end)
            local securityPart = workspace:FindFirstChild("SecurityPart")
            if securityPart then
                humanoidRootPart.CFrame = securityPart.CFrame + V3(0, 3, 0)
            end
            CurrentItemPos = nil
            return
        end
        
        local now = tick()
        local myPos = humanoidRootPart.Position
        
        -- Get all items
        local items = GetCollectableItems()
        
        if #items > 0 then
            -- Check if we should stay at current position to collect nearby items
            if CurrentItemPos and (now - LastItemTP) < COLLECT_TIME then
                -- Stay at current position
                humanoidRootPart.CFrame = CFrame.new(CurrentItemPos)
                return
            end
            
            -- Get items that are NOT in our current collection range
            local remainingItems = items
            if CurrentItemPos then
                remainingItems = GetItemsNotInRange(items, CurrentItemPos, COLLECTION_RADIUS)
            end
            
            -- If all items are in range, just stay
            if #remainingItems == 0 and #items > 0 then
                -- All items collected or in range, wait a bit then check again
                if CurrentItemPos then
                    humanoidRootPart.CFrame = CFrame.new(CurrentItemPos)
                end
                return
            end
            
            -- Find best cluster to teleport to
            local targetItem = FindBestItemCluster(remainingItems, myPos)
            
            if targetItem then
                -- Teleport DIRECTLY to item position (no elevation!)
                CurrentItemPos = targetItem.Position
                humanoidRootPart.CFrame = CFrame.new(CurrentItemPos)
                LastItemTP = now
            end
        else
            -- No items, go to security part
            local securityPart = workspace:FindFirstChild("SecurityPart")
            if securityPart then
                humanoidRootPart.CFrame = securityPart.CFrame + V3(0, 3, 0)
            end
            CurrentItemPos = nil
        end
    end)
    
    print("[ITEM FARM] Started - Collection radius: " .. COLLECTION_RADIUS .. " studs")
end

local function StopAutoItemFarm()
    if AutoItemFarmConnection then
        AutoItemFarmConnection:Disconnect()
        AutoItemFarmConnection = nil
    end
    CurrentItemPos = nil
    
    local character = Player.Character
    local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
    local securityPart = workspace:FindFirstChild("SecurityPart")
    if humanoidRootPart and securityPart then
        humanoidRootPart.CFrame = securityPart.CFrame + V3(0, 3, 0)
    end
end

local function ToggleAutoItemFarm()
    FeatureStates.AutoItemFarm = not FeatureStates.AutoItemFarm
    if FeatureStates.AutoItemFarm then
        StartAutoItemFarm()
        print("[ITEM FARM] ON")
    else
        StopAutoItemFarm()
        print("[ITEM FARM] OFF")
    end
    UpdateGUIButtons()
end

--══════════════════════════════════════════════════════════════════
-- FAST REVIVE
--══════════════════════════════════════════════════════════════════

local InteractEvent = nil
local ReviveRange = 15

local function GetInteractEvent()
    if InteractEvent and InteractEvent.Parent then return InteractEvent end
    pcall(function()
        InteractEvent = ReplicatedStorage:WaitForChild("Events", 5):WaitForChild("Character", 5):WaitForChild("Interact", 5)
    end)
    return InteractEvent
end

local function ReviveNearbyPlayers()
    local event = GetInteractEvent()
    if not event then return end
    local myChar = Player.Character
    if not myChar then return end
    local myHRP = myChar:FindFirstChild("HumanoidRootPart")
    if not myHRP then return end
    
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= Player and plr.Character then
            local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
            if hrp and (myHRP.Position - hrp.Position).Magnitude <= ReviveRange then
                pcall(function() event:FireServer("Revive", true, plr.Name) end)
            end
        end
    end
end

--══════════════════════════════════════════════════════════════════
-- ANTI-AFK
--══════════════════════════════════════════════════════════════════

local function StartAntiAFK()
    if AntiAFKConnection then return end
    AntiAFKConnection = Player.Idled:Connect(function()
        VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        task.wait(1)
        VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    end)
end

--══════════════════════════════════════════════════════════════════
-- SELF REVIVE
--══════════════════════════════════════════════════════════════════

local function DoSelfRevive()
    local now = tick()
    if now - SelfReviveCooldown < 10 then
        print("[SELF REVIVE] Cooldown: " .. math.ceil(10 - (now - SelfReviveCooldown)) .. "s")
        return
    end
    local character = Player.Character
    if not character or not character:GetAttribute("Downed") then 
        print("[SELF REVIVE] Not downed!")
        return 
    end
    SelfReviveCooldown = now
    pcall(function() ReplicatedStorage.Events.Player.ChangePlayerMode:FireServer(true) end)
    print("[SELF REVIVE] Reviving...")
end

--══════════════════════════════════════════════════════════════════
-- EASY TRIMP
--══════════════════════════════════════════════════════════════════

local function HandleEasyTrimp()
    if not FeatureStates.EasyTrimp then
        if TrimpPush then TrimpPush:Destroy() TrimpPush = nil end
        return
    end
    
    local dt = tick() - TrimpLast
    TrimpLast = tick()
    
    if not Player.Character then return end
    local hrp = Player.Character:FindFirstChild("HumanoidRootPart")
    local hum = Player.Character:FindFirstChild("Humanoid")
    if not hrp or not hum then return end
    
    local inAir = hum.FloorMaterial == Enum.Material.Air
    if TrimpAirborne and not inAir then TrimpSpeed = max(TRIMP_BASE_SPEED, TrimpSpeed - 10) end
    TrimpAirborne = inAir
    
    if inAir then
        TrimpAirTick = TrimpAirTick + dt
        while TrimpAirTick >= 0.04 do
            TrimpAirTick = TrimpAirTick - 0.04
            TrimpSpeed = min(TRIMP_BASE_SPEED + TRIMP_EXTRA_SPEED, TrimpSpeed + 0.1)
        end
    else
        TrimpAirTick = 0
        TrimpSpeed = max(TRIMP_BASE_SPEED, TrimpSpeed - (2.5 * dt))
    end
    
    if TrimpPush then TrimpPush:Destroy() end
    
    local camera = workspace.CurrentCamera
    local look = camera.CFrame.LookVector
    local moveDir = V3(look.X, 0, look.Z)
    if moveDir.Magnitude > 0 then moveDir = moveDir.Unit end
    
    local bv = Instance.new("BodyVelocity")
    bv.Velocity = moveDir * TrimpSpeed
    bv.MaxForce = V3(4e5, 0, 4e5)
    bv.P = 1250
    bv.Parent = hrp
    Debris:AddItem(bv, 0.1)
    TrimpPush = bv
end

local function ToggleEasyTrimp()
    FeatureStates.EasyTrimp = not FeatureStates.EasyTrimp
    if FeatureStates.EasyTrimp then
        TrimpSpeed = TRIMP_BASE_SPEED
        TrimpLast = tick()
        print("[TRIMP] ON")
    else
        if TrimpPush then TrimpPush:Destroy() TrimpPush = nil end
        print("[TRIMP] OFF")
    end
    UpdateGUIButtons()
end

--══════════════════════════════════════════════════════════════════
-- FOV + FULLBRIGHT
--══════════════════════════════════════════════════════════════════

local function ForceFOV()
    local c = workspace.CurrentCamera
    if not c then return end
    if c.FieldOfView ~= FOV_VALUE then c.FieldOfView = FOV_VALUE end
    if c ~= LastCam then
        LastCam = c
        c:GetPropertyChangedSignal("FieldOfView"):Connect(function()
            if c.FieldOfView ~= FOV_VALUE then c.FieldOfView = FOV_VALUE end
        end)
    end
end

local function ToggleBright()
    FullbrightOn = not FullbrightOn
    if FullbrightOn then
        SavedLight = {Lighting.Brightness, Lighting.Ambient, Lighting.OutdoorAmbient, Lighting.ClockTime, Lighting.FogEnd}
        Lighting.Brightness = 2
        Lighting.Ambient = Color3.fromRGB(150, 150, 150)
        Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 150)
        Lighting.ClockTime = 12
        Lighting.FogEnd = 1e9
        for _, o in ipairs(Lighting:GetChildren()) do
            if o:IsA("Atmosphere") then o.Density = 0 end
            if o:IsA("BlurEffect") or o:IsA("BloomEffect") then o.Enabled = false end
        end
    elseif SavedLight then
        Lighting.Brightness = SavedLight[1]
        Lighting.Ambient = SavedLight[2]
        Lighting.OutdoorAmbient = SavedLight[3]
        Lighting.ClockTime = SavedLight[4]
        Lighting.FogEnd = SavedLight[5]
    end
    print("[FULLBRIGHT] " .. (FullbrightOn and "ON" or "OFF"))
    UpdateGUIButtons()
end

--══════════════════════════════════════════════════════════════════
-- BHOP + MOMENTUM + BOOSTS
--══════════════════════════════════════════════════════════════════

local function DoBhop()
    if not Hum or not Root or Hum.Health <= 0 then return end
    local now = tick()
    local gnd = IsGnd()
    if gnd then LastGndTime = now end
    
    local wantJump = HoldSpace or (JumpBuf and now - LastJumpReq < BHOP.JumpBuffer)
    if not wantJump or now - LastJumpExecute < BHOP.JumpCooldown or Root.AssemblyLinearVelocity.Y > 5 then return end
    
    if not (gnd or IsAboutToLand() or (now - LastGndTime < BHOP.CoyoteTime)) then return end
    
    local vx, _, vz, hs = GetVel()
    local dx, dz = GetDir(vx, vz, hs)
    if hs > 1 then StoredSpd, StoredDirX, StoredDirZ = hs, dx, dz end
    
    LastJumpExecute = now
    Hum:ChangeState(Enum.HumanoidStateType.Jumping)
    JumpBuf = false
    
    task.defer(function()
        if Root and Hum and Hum.Health > 0 and StoredSpd > 1 then
            SetHVel(StoredDirX * StoredSpd, StoredDirZ * StoredSpd)
        end
    end)
end

local function DoMomentum()
    if not Root then return end
    local now = tick()
    local gnd = IsGnd()
    local vx, vy, vz, hs = GetVel()
    
    JustLanded = false
    if not gnd then
        if vy < 0 and abs(vy) > MaxFall then MaxFall = abs(vy) end
        AirTime = now - AirStart
    end
    
    if gnd and not WasGnd then
        JustLanded = true
        if StoredSpd > hs + 2 and StoredSpd > 5 and hs > 1 then
            local dx, dz = GetDir(vx, vz, hs)
            SetHVel(dx * StoredSpd * BHOP.MomentumPreserve, dz * StoredSpd * BHOP.MomentumPreserve)
        end
    end
    
    if not gnd and WasGnd then
        AirStart, LaunchY, LaunchSpd = now, vy, hs
        LaunchDirX, LaunchDirZ = GetDir(vx, vz, hs)
        MaxFall, AirTime, RampApplied = 0, 0, false
        WasPlayerJump = (now - LastJumpExecute) < 0.3
        RampPending = not WasPlayerJump and (now - BackslideCD) >= 0.5 and (now - SlideCD) >= 0.3 and LaunchSpd >= RAMP_MIN_SPEED and LaunchY >= RAMP_MIN_UP
    end
    
    if not gnd and hs > StoredSpd * 0.9 then
        StoredSpd = hs
        StoredDirX, StoredDirZ = GetDir(vx, vz, hs)
    end
    WasGnd = gnd
end

local function DoSlopeBounce()
    if not BOUNCE_ON or not Root or not JustLanded or tick() - BounceCD < BOUNCE_CD or IsSliding() or IsUphillBackslide() or HoldSpace then return end
    local vx, vy, vz, hs = GetVel()
    if hs < BOUNCE_MIN_SPEED then return end
    local slope = GetSlopeInfo()
    if slope < BOUNCE_MIN_SLOPE or slope > BOUNCE_MAX_SLOPE then return end
    Root.AssemblyLinearVelocity = V3(vx, clamp(hs * BOUNCE_POWER * clamp((slope - 10) / 30, 0.3, 1.0) * clamp(hs / 20, 0.5, 1.5), 2, BOUNCE_MAX_V), vz)
    BounceCD = tick()
end

local function DoRamp()
    if not RAMP_ON or not Root or HoldSpace or IsGnd() or RampApplied or not RampPending then return end
    local now = tick()
    if now - RampCD < RAMP_CD or now - SlideCD < SLIDE_PROTECT or now - BackslideCD < BACKSLIDE_PROTECT or AirTime < RAMP_DELAY or now - LastJumpExecute < 1.0 then return end
    local vx, vy, vz = GetVel()
    if vy < -5 then return end
    local totalMult = clamp(LaunchSpd / 18, 0.6, 1.3) * clamp(LaunchY / 8, 0.6, 1.2)
    local hB = clamp(LaunchSpd * RAMP_BOOST_H * totalMult, 2, RAMP_MAX_H)
    SetHVel(vx + LaunchDirX * hB, vz + LaunchDirZ * hB)
    Root.AssemblyLinearVelocity = V3(Root.AssemblyLinearVelocity.X, Root.AssemblyLinearVelocity.Y + clamp(LaunchY * RAMP_BOOST_V * totalMult, 1, RAMP_MAX_V), Root.AssemblyLinearVelocity.Z)
    RampCD, RampApplied, RampPending = now, true, false
end

local function DoFreefall()
    if not FREEFALL_ON or not Root or HoldSpace or not JustLanded then return end
    local now = tick()
    if now - FreefallCD < FREEFALL_CD or now - SlideCD < SLIDE_PROTECT or now - BackslideCD < BACKSLIDE_PROTECT or AirTime < FREEFALL_MIN_AIR or MaxFall < FREEFALL_MIN_FALL or (WasPlayerJump and AirTime < 0.6) or IsSliding() or IsUphillBackslide() then return end
    local vx, vy, vz, hs = GetVel()
    local bx, bz = 0, 1
    if hs > 3 then bx, bz = GetDir(vx, vz, hs)
    else local cam = workspace.CurrentCamera; if cam then local l = cam.CFrame.LookVector; local m = sqrt(l.X * l.X + l.Z * l.Z); if m > 0.1 then bx, bz = l.X / m, l.Z / m end end end
    local totalMult = clamp((MaxFall - 15) / 25, 0.5, 2.0) * clamp((AirTime - 0.3) / 0.5, 0.5, 1.5)
    local hB = clamp(MaxFall * FREEFALL_BOOST_H * totalMult, 8, FREEFALL_MAX_H)
    SetHVel(vx + bx * hB, vz + bz * hB)
    Root.AssemblyLinearVelocity = V3(Root.AssemblyLinearVelocity.X, clamp(MaxFall * FREEFALL_BOOST_V * totalMult, 5, FREEFALL_MAX_V), Root.AssemblyLinearVelocity.Z)
    FreefallCD = now
end

--══════════════════════════════════════════════════════════════════
-- GUI
--══════════════════════════════════════════════════════════════════

function UpdateGUIButtons()
    if not GUI then return end
    local main = GUI:FindFirstChild("Main")
    if not main then return end
    
    local function SetColor(name, active)
        local btn = main:FindFirstChild(name)
        if btn then btn.BackgroundColor3 = active and Color3.fromRGB(0, 200, 100) or Color3.fromRGB(50, 50, 60) end
    end
    
    SetColor("B90", FOV_VALUE == 90)
    SetColor("B120", FOV_VALUE == 120)
    SetColor("FBBtn", FullbrightOn)
    SetColor("TrimpBtn", FeatureStates.EasyTrimp)
    SetColor("InvisBtn", FeatureStates.InvisBorder)
    SetColor("AntiBotBtn", FeatureStates.AntiNextbot)
    SetColor("ItemFarmBtn", FeatureStates.AutoItemFarm)
end

local function CreateButton(parent, name, text, posX, posY, sizeX, callback)
    local btn = Instance.new("TextButton")
    btn.Name = name
    btn.Size = UDim2.new(0, sizeX, 0, 20)
    btn.Position = UDim2.new(0, posX, 0, posY)
    btn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
    btn.BorderSizePixel = 0
    btn.Text = text
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.TextSize = 9
    btn.Font = Enum.Font.GothamBold
    btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    btn.MouseButton1Click:Connect(callback)
    return btn
end

local function MakeGUI()
    pcall(function() if GUI then GUI:Destroy() end end)
    
    GUI = Instance.new("ScreenGui")
    GUI.Name = "EvadeHelper"
    GUI.ResetOnSpawn = false
    pcall(function() GUI.Parent = game:GetService("CoreGui") end)
    if not GUI.Parent then GUI.Parent = Player.PlayerGui end
    
    local F = Instance.new("Frame")
    F.Name = "Main"
    F.Size = UDim2.new(0, 280, 0, 95)
    F.Position = UDim2.new(0, 10, 0, 10)
    F.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
    F.BorderSizePixel = 0
    F.Parent = GUI
    Instance.new("UICorner", F).CornerRadius = UDim.new(0, 8)
    Instance.new("UIStroke", F).Color = Color3.fromRGB(0, 200, 100)
    
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -20, 0, 16)
    title.Position = UDim2.new(0, 5, 0, 2)
    title.BackgroundTransparency = 1
    title.Text = "EVADE HELPER"
    title.TextColor3 = Color3.fromRGB(0, 200, 100)
    title.TextSize = 11
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = F
    
    CreateButton(F, "CloseBtn", "X", 260, 2, 16, function() F.Visible = false end)
    
    CreateButton(F, "B90", "90", 5, 20, 25, function() FOV_VALUE = 90 UpdateGUIButtons() ForceFOV() end)
    CreateButton(F, "B120", "120", 33, 20, 30, function() FOV_VALUE = 120 UpdateGUIButtons() ForceFOV() end)
    CreateButton(F, "FBBtn", "FB", 66, 20, 25, ToggleBright)
    CreateButton(F, "TrimpBtn", "TRIMP", 94, 20, 45, ToggleEasyTrimp)
    CreateButton(F, "InvisBtn", "NOBORDER", 142, 20, 70, ToggleInvisBorder)
    
    CreateButton(F, "AntiBotBtn", "ANTI-BOT", 5, 44, 70, ToggleAntiNextbot)
    CreateButton(F, "ItemFarmBtn", "ITEM FARM", 78, 44, 80, ToggleAutoItemFarm)
    
    local info1 = Instance.new("TextLabel")
    info1.Size = UDim2.new(1, -10, 0, 12)
    info1.Position = UDim2.new(0, 5, 0, 68)
    info1.BackgroundTransparency = 1
    info1.Text = "SPACE=Bhop | E=Revive | Q=Self Revive | P=Bright"
    info1.TextColor3 = Color3.fromRGB(100, 100, 100)
    info1.TextSize = 8
    info1.Font = Enum.Font.Gotham
    info1.TextXAlignment = Enum.TextXAlignment.Left
    info1.Parent = F
    
    local info2 = Instance.new("TextLabel")
    info2.Size = UDim2.new(1, -10, 0, 12)
    info2.Position = UDim2.new(0, 5, 0, 80)
    info2.BackgroundTransparency = 1
    info2.Text = "LShift=Trimp | RShift=GUI | Farm range: 25 studs"
    info2.TextColor3 = Color3.fromRGB(80, 80, 80)
    info2.TextSize = 8
    info2.Font = Enum.Font.Gotham
    info2.TextXAlignment = Enum.TextXAlignment.Left
    info2.Parent = F
    
    local drag, ds, dp
    F.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then drag, ds, dp = true, i.Position, F.Position end end)
    F.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then drag = false end end)
    UserInputService.InputChanged:Connect(function(i) if drag and i.UserInputType == Enum.UserInputType.MouseMovement then local d = i.Position - ds; F.Position = UDim2.new(dp.X.Scale, dp.X.Offset + d.X, dp.Y.Scale, dp.Y.Offset + d.Y) end end)
    
    UpdateGUIButtons()
end

--══════════════════════════════════════════════════════════════════
-- INPUT
--══════════════════════════════════════════════════════════════════

UserInputService.InputBegan:Connect(function(i, g)
    if g then return end
    local k = i.KeyCode
    if k == Enum.KeyCode.Space then HoldSpace, JumpBuf, LastJumpReq = true, true, tick()
    elseif k == Enum.KeyCode.E then ReviveNearbyPlayers()
    elseif k == Enum.KeyCode.Q then DoSelfRevive()
    elseif k == Enum.KeyCode.P then ToggleBright()
    elseif k == Enum.KeyCode.LeftShift then ToggleEasyTrimp()
    elseif k == Enum.KeyCode.RightShift then if GUI and GUI:FindFirstChild("Main") then GUI.Main.Visible = not GUI.Main.Visible end end
end)

UserInputService.InputEnded:Connect(function(i)
    if i.KeyCode == Enum.KeyCode.Space then HoldSpace = false end
end)

--══════════════════════════════════════════════════════════════════
-- CHARACTER
--══════════════════════════════════════════════════════════════════

local function Setup(char)
    Hum = char:WaitForChild("Humanoid", 5)
    Root = char:WaitForChild("HumanoidRootPart", 5)
    if not Hum or not Root then return end
    StoredSpd, StoredDirX, StoredDirZ = 0, 0, 0
    WasGnd, LastGndTime, LastJumpExecute = true, tick(), 0
    AirStart, MaxFall, AirTime = 0, 0, 0
    RampCD, FreefallCD, SlideCD, BackslideCD, BounceCD = 0, 0, 0, 0, 0
    RampPending, RampApplied, JustLanded, WasPlayerJump = false, false, false, false
    Hum.Died:Once(function() HoldSpace, JumpBuf = false, false end)
    RefreshNextbotNames()
end

if Player.Character then Setup(Player.Character) end
Player.CharacterAdded:Connect(Setup)

--══════════════════════════════════════════════════════════════════
-- MAIN LOOP
--══════════════════════════════════════════════════════════════════

RunService.Heartbeat:Connect(function()
    FrameCount = FrameCount + 1
    if FrameCount % 60 == 0 then ForceFOV() end
    if not Hum or not Root or Hum.Health <= 0 then return end
    local now = tick()
    if IsSliding() then SlideCD = now end
    if IsUphillBackslide() then BackslideCD = now end
    DoMomentum()
    DoBhop()
    DoSlopeBounce()
    DoRamp()
    DoFreefall()
    if FrameCount >= 3600 then FrameCount = 0 end
end)

RunService.RenderStepped:Connect(function()
    if FeatureStates.EasyTrimp then HandleEasyTrimp() end
end)

--══════════════════════════════════════════════════════════════════
-- INIT
--══════════════════════════════════════════════════════════════════

MakeGUI()
ForceFOV()
StartAntiAFK()
RefreshNextbotNames()

print("═══════════════════════════════════════════════")
print(" EVADE HELPER - ITEM FARM V2")
print("═══════════════════════════════════════════════")
print("")
print(" CONTROLS:")
print("   SPACE = Bhop | E = Revive | Q = Self Revive")
print("   P = Bright | LShift = Trimp | RShift = GUI")
print("")
print(" ITEM FARM (IMPROVED!):")
print("   ✓ No more elevation/floating")
print("   ✓ Teleports directly to items")
print("   ✓ Collection radius: 25 studs")
print("   ✓ Stays 0.3s to collect nearby items")
print("   ✓ Finds item clusters (groups)")
print("")
print("═══════════════════════════════════════════════")
