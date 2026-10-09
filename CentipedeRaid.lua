-- Defeat Anime RNG | Tree Hideout raid - auto Centipede (Loop 10 times then Return)
local CONFIG = {
    ATTACK_INTERVAL   = 0.12,   -- seconds between sword hits
    MOVE_SPEED        = 120,    -- studs per second when sliding to a Centipede
    DODGE_SPEED       = 200,    -- studs per second when leaving a debris zone
    STAND_DISTANCE    = 4,      -- how close to stand to the Centipede
    DEBRIS_MARGIN     = 12,     -- extra studs to keep outside the debris circle (circle radius is 6)
    HIT_OTHER_ENEMIES = true,   -- true = also hit normal enemies while no Centipede is alive
    AUTO_READY        = true,   -- press Ready in the raid lobby
    READY_DELAY       = 6,      -- seconds to wait in the lobby before pressing Ready
    AUTO_REPLAY       = true,   -- press Replay on the result screen
    REPLAY_DELAY      = 3,      -- seconds to wait before pressing the result button
    MAX_RUNS          = 7,      -- จำนวนรอบที่ต้องการให้เล่นซ้ำในห้องนี้ ก่อนจะกดกลับหน้าหลัก
    SHOW_BUTTON       = true,   -- small ON/OFF button on screen

    AUTO_ENTER        = true,       -- in the main game: create the raid party and start it
    RAID_NAME         = "11th Ward", -- Tree Hideout
    DIFFICULTY        = "Hard",  -- locked to Extreme or Hard
    RAID_MODE         = "Kaneki",   -- game mode name of the Tree Hideout raid
    WRONG_EVENT_SECONDS = 12,       -- leave if the game is in another mode for this long
    ENTER_DELAY       = 8,          -- seconds to wait in the main game before entering
    SCRIPT_URL        = "https://raw.githubusercontent.com/llggll285-stack/anime-rng-script/refs/heads/main/CentipedeRaid.lua",
}

if not game:IsLoaded() then game.Loaded:Wait() end

local Players             = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local LocalPlayer       = Players.LocalPlayer or Players.PlayerAdded:Wait()

local env = (getgenv and getgenv()) or _G
if env.__CentipedeRaid then
    pcall(env.__CentipedeRaid.stop)
end

local MAIN_PLACE = 92606991708989
local RAID_PLACE = 134342669880221

local running     = true
local enabled     = true
local status      = "Initializing..."
local connections = {}
local stats       = { runs = 0, wins = 0, losses = 0, debris = 0, dodges = 0, centipedes = 0, hurt = 0 }

local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(connections, c)
    return c
end

-- สร้าง UI แสดงผลทันทีตั้งแต่หน้าแรก (ตัด Status ออก เหลือแค่สถิติและโหมด)
local gui
if CONFIG.SHOW_BUTTON then
    pcall(function()
        gui = Instance.new("ScreenGui")
        gui.Name = "CentipedeRaidGui"
        gui.ResetOnSpawn = false
        local parent = (gethui and gethui()) or game:GetService("CoreGui")
        local okParent = pcall(function() gui.Parent = parent end)
        if not okParent or not gui.Parent then
            gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
        end

        local button = Instance.new("TextButton")
        button.Size = UDim2.fromOffset(210, 34)
        button.Position = UDim2.new(0, 12, 0.5, 0)
        button.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        button.BackgroundTransparency = 0.2
        button.Font = Enum.Font.GothamBold
        button.TextSize = 13
        button.Parent = gui
        Instance.new("UICorner", button).CornerRadius = UDim.new(0, 8)

        local function refresh()
            button.Text = enabled and "Centipede: ON" or "Centipede: OFF"
            button.TextColor3 = enabled and Color3.fromRGB(90, 255, 120) or Color3.fromRGB(255, 90, 90)
        end
        refresh()
        button.Activated:Connect(function()
            enabled = not enabled
            refresh()
        end)

        local label = Instance.new("TextLabel")
        label.Size = UDim2.fromOffset(260, 42)
        label.Position = UDim2.new(0, 12, 0.5, 38)
        label.BackgroundTransparency = 1
        label.TextColor3 = Color3.new(1, 1, 1)
        label.TextStrokeTransparency = 0.5
        label.Font = Enum.Font.Gotham
        label.TextSize = 12
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextYAlignment = Enum.TextYAlignment.Top
        label.Parent = gui
        
        task.spawn(function()
            while running do
                local currentMode = "Lobby/Main"
                pcall(function()
                    currentMode = tostring(workspace:GetAttribute("ActiveGamemode"))
                end)
                -- แสดงเฉพาะสถิติและโหมดปัจจุบัน (ไม่เอา Status)
                label.Text = string.format("Runs: %d/%d | Wins: %d | Centipedes: %d\nMode: %s",
                    stats.runs, CONFIG.MAX_RUNS, stats.wins, stats.centipedes, currentMode)
                task.wait(0.4)
            end
        end)
    end)
end

local queueTeleport = queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport)
if queueTeleport and CONFIG.SCRIPT_URL ~= "" then
    pcall(queueTeleport, string.format('loadstring(game:HttpGet("%s"))()', CONFIG.SCRIPT_URL))
end

if game.PlaceId ~= RAID_PLACE then
    local TeleportService = game:GetService("TeleportService")

    if game.PlaceId ~= MAIN_PLACE then
        status = "Wrong place, returning..."
        print("[CentipedeRaid] wrong place, going back to the main game")
        for _ = 1, 20 do
            pcall(TeleportService.Teleport, TeleportService, MAIN_PLACE, LocalPlayer)
            task.wait(10)
        end
        return
    end

    if not CONFIG.AUTO_ENTER then return end

    local events = ReplicatedStorage:WaitForChild("RemoteEvents", 60)
    local party  = events and events:WaitForChild("RaidPartyRequestFunction", 30)
    if not party then return end
    task.wait(CONFIG.ENTER_DELAY)

    for _ = 1, 60 do
        pcall(party.InvokeServer, party, "Create", CONFIG.RAID_NAME, CONFIG.DIFFICULTY)
        task.wait(1)
        local ok2, started, why = pcall(party.InvokeServer, party, "Start")
        if ok2 and started then
            print("[CentipedeRaid] raid started")
            return
        end
        if why == "PrestigeRequired" then
            warn("[CentipedeRaid] this account needs the Gold I prestige rank to enter the raid")
            return
        end
        task.wait(5)
    end
    return
end

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local AttackEvent  = RemoteEvents:WaitForChild("PlayerAttackEvent")
local WeaponsDatabase
pcall(function()
    WeaponsDatabase = require(ReplicatedStorage:WaitForChild("Databases"):WaitForChild("WeaponsDatabase"))
end)

local function isWeapon(tool)
    if not tool:IsA("Tool") then return false end
    if WeaponsDatabase then return WeaponsDatabase[tool.Name] ~= nil end
    return true
end

local function ensureWeapon(char, hum)
    local held = char:FindFirstChildOfClass("Tool")
    if held and isWeapon(held) then return end
    for _, tool in ipairs(LocalPlayer.Backpack:GetChildren()) do
        if isWeapon(tool) then
            hum:EquipTool(tool)
            return
        end
    end
end

local function getBase()
    local bases = workspace:FindFirstChild("Bases")
    if not bases then return nil end
    local id = tostring(LocalPlayer.UserId)
    for _, base in ipairs(bases:GetChildren()) do
        local owner = base:FindFirstChild("Owner")
        if owner and owner.Value == id then return base end
    end
    return nil
end

local function rootOf(model)
    return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
end

local function isAlive(model)
    if not model:IsA("Model") then return false end
    local hum = model:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > 0 and rootOf(model) ~= nil
end

local function nearestIn(holder, from, centipedeOnly)
    if not holder then return nil end
    local best, bestDist
    for _, child in ipairs(holder:GetChildren()) do
        if isAlive(child) and (not centipedeOnly or string.find(string.lower(child.Name), "centipede", 1, true)) then
            local d = (rootOf(child).Position - from).Magnitude
            if not bestDist or d < bestDist then
                best, bestDist = child, d
            end
        end
    end
    return best
end

local function findTarget(from)
    local base = getBase()
    if not base then return nil end
    local target = nearestIn(base:FindFirstChild("PlayerOnlyEnemiesHolder"), from, true)
        or nearestIn(base:FindFirstChild("EnemiesHolder"), from, true)
    if target then return target, true end
    if CONFIG.HIT_OTHER_ENEMIES then
        return nearestIn(base:FindFirstChild("EnemiesHolder"), from, false), false
    end
    return nil
end

local dangerZones = {}

local function flat(v)
    return Vector3.new(v.X, 0, v.Z)
end

local function activeZoneAt(pos)
    local now = os.clock()
    local worst
    for i = #dangerZones, 1, -1 do
        local zone = dangerZones[i]
        if now > zone.expires then
            table.remove(dangerZones, i)
        elseif (flat(pos) - flat(zone.pos)).Magnitude < zone.radius + CONFIG.DEBRIS_MARGIN then
            worst = zone
        end
    end
    return worst
end

local function safePoint(pos, fallbackDir)
    local p = pos
    for _ = 1, 4 do
        local zone = activeZoneAt(p)
        if not zone then return p end
        local away = flat(p) - flat(zone.pos)
        if away.Magnitude < 0.1 then
            away = (fallbackDir and fallbackDir.Magnitude > 0.1) and fallbackDir or Vector3.new(1, 0, 0)
        end
        local edge = flat(zone.pos) + away.Unit * (zone.radius + CONFIG.DEBRIS_MARGIN + 1)
        p = Vector3.new(edge.X, pos.Y, edge.Z)
    end
    return p
end

local debrisEvent = RemoteEvents:FindFirstChild("RaidDebrisEvent")
if debrisEvent then
    connect(debrisEvent.OnClientEvent, function(pos, radius, delayTime, fallTime)
        if typeof(pos) ~= "Vector3" then return end
        stats.debris += 1
        table.insert(dangerZones, {
            pos     = pos,
            radius  = radius or 6,
            expires = os.clock() + (delayTime or 1.5) + (fallTime or 0.45) + 0.6,
        })
    end)
end

local lastAttack   = 0
local wasDodging   = false
local trackedKills = {}

local function countKill(target)
    if trackedKills[target] then return end
    trackedKills[target] = true
    local hum = target:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    hum.Died:Once(function()
        stats.centipedes += 1
    end)
end

local function step(dt)
    local char = LocalPlayer.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not (hum and hrp) or hum.Health <= 0 then return end

    local here = hrp.Position
    local target, isCentipede = findTarget(here)
    local goal = here
    local targetRoot

    if target then
        targetRoot = rootOf(target)
        if isCentipede then countKill(target) end
        local toMe = flat(here) - flat(targetRoot.Position)
        if toMe.Magnitude < 0.1 then toMe = Vector3.new(0, 0, 1) end
        local stand = flat(targetRoot.Position) + toMe.Unit * CONFIG.STAND_DISTANCE
        goal = Vector3.new(stand.X, here.Y, stand.Z)
    end

    local dodging = activeZoneAt(here) ~= nil
    local safeGoal = safePoint(goal, flat(here) - flat(goal))
    if dodging and not wasDodging then stats.dodges += 1 end
    wasDodging = dodging

    local delta = flat(safeGoal) - flat(here)
    local dist  = delta.Magnitude
    if dist > 0.5 then
        local speed = dodging and CONFIG.DODGE_SPEED or CONFIG.MOVE_SPEED
        local move  = math.min(dist, speed * dt)
        local newPos = here + delta.Unit * move
        local look = targetRoot and flat(targetRoot.Position) - flat(newPos) or delta
        if look.Magnitude < 0.1 then look = hrp.CFrame.LookVector end
        hrp.CFrame = CFrame.lookAt(newPos, newPos + Vector3.new(look.X, 0, look.Z))
        hrp.AssemblyLinearVelocity = Vector3.zero
    end

    if not target then return end

    ensureWeapon(char, hum)
    local now = os.clock()
    if now - lastAttack >= CONFIG.ATTACK_INTERVAL then
        lastAttack = now
        AttackEvent:FireServer()
    end
end

connect(RunService.Heartbeat, function(dt)
    if not running or not enabled then return end
    pcall(step, dt)
end)

local function watchCharacter(char)
    local hum = char:WaitForChild("Humanoid", 10)
    if not hum then return end
    local last = hum.Health
    connect(hum.HealthChanged, function(h)
        if h < last then stats.hurt += 1 end
        last = h
    end)
end
connect(LocalPlayer.CharacterAdded, watchCharacter)
if LocalPlayer.Character then task.spawn(watchCharacter, LocalPlayer.Character) end

local readyEvent  = RemoteEvents:FindFirstChild("RaidReadyRequestEvent")
local lobbyEvent  = RemoteEvents:FindFirstChild("RaidLobbyStatusEvent")
local statusEvent = RemoteEvents:FindFirstChild("RaidStatusEvent")
local resultEvent = RemoteEvents:FindFirstChild("RaidResultEvent")
local actionEvent = RemoteEvents:FindFirstChild("RaidResultActionEvent")

local lobbySeenAt, lastReady = nil, 0
if lobbyEvent and readyEvent then
    connect(lobbyEvent.OnClientEvent, function(info)
        if not (enabled and CONFIG.AUTO_READY) then return end
        if type(info) ~= "table" then return end
        lobbySeenAt = lobbySeenAt or os.clock()
        if info.SelfReady == true then return end
        local char = LocalPlayer.Character
        if not (char and char:FindFirstChild("HumanoidRootPart")) then return end
        if os.clock() - lobbySeenAt < CONFIG.READY_DELAY then return end
        if os.clock() - lastReady < 3 then return end
        lastReady = os.clock()
        readyEvent:FireServer()
    end)
end

if statusEvent then
    connect(statusEvent.OnClientEvent, function(info)
        if type(info) ~= "table" then return end
        if info.Kind == "Start" then
            lobbySeenAt = nil
            stats.runs += 1
            table.clear(dangerZones)
        elseif info.Kind == "Victory" then
            stats.wins += 1
        elseif info.Kind == "Defeat" then
            stats.losses += 1
        end
    end)
end

if resultEvent and actionEvent then
    connect(resultEvent.OnClientEvent, function()
        if not (enabled and CONFIG.AUTO_REPLAY) then return end
        task.delay(CONFIG.REPLAY_DELAY, function()
            if running and enabled then
                if stats.runs >= CONFIG.MAX_RUNS then
                    print("[CentipedeRaid] Completed " .. CONFIG.MAX_RUNS .. " runs, returning to main lobby...")
                    actionEvent:FireServer("Return")
                    task.delay(10, function()
                        if running and enabled and game.PlaceId ~= MAIN_PLACE then
                            pcall(function() game:GetService("TeleportService"):Teleport(MAIN_PLACE, LocalPlayer) end)
                        end
                    end)
                else
                    actionEvent:FireServer("Replay")
                end
            end
        end)
    end)
end

env.__CentipedeRaid = {
    stats = stats,
    stop = function()
        running = false
        for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
        if gui then pcall(function() gui:Destroy() end) end
    end,
}

task.spawn(function()
    local wrongSince
    while running do
        task.wait(2)
        local mode = workspace:GetAttribute("ActiveGamemode")
        if mode == CONFIG.RAID_MODE then
            wrongSince = nil
        else
            wrongSince = wrongSince or os.clock()
            if os.clock() - wrongSince >= CONFIG.WRONG_EVENT_SECONDS then
                print("[CentipedeRaid] stuck in wrong mode, resetting character and going back...")
                local TeleportService = game:GetService("TeleportService")
                local char = LocalPlayer.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                if hum then hum.Health = 0 end
                task.wait(2)
                env.__CentipedeRaid.stop()
                for _ = 1, 20 do
                    pcall(TeleportService.Teleport, TeleportService, MAIN_PLACE, LocalPlayer)
                    task.wait(5)
                end
                return
            end
        end
    end
end)
