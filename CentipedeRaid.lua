-- Defeat Anime RNG | Tree Hideout raid - auto Centipede (Ultimate Edition)
local CONFIG = {
    ATTACK_INTERVAL   = 0.15,  -- ความเร็วในการโจมตี (วินาที)
    MOVE_SPEED        = 120,   -- ความเร็วในการเดินเข้าหาบอส
    DODGE_SPEED       = 200,   -- ความเร็วในการหลบเศษซาก
    STAND_DISTANCE    = 4,     -- ระยะยืนห่างจากตัวบอส
    DEBRIS_MARGIN     = 12,    -- ระยะปลอดภัยจากวงตกของเศษซาก
    HIT_OTHER_ENEMIES = false, -- ตีมอนสเตอร์ตัวอื่นไหมถ้าบอสยังไม่เกิด
    AUTO_READY        = true,  -- กด Ready อัตโนมัติในห้องรอ
    READY_DELAY       = 6,     -- เวลารอก่อนกด Ready
    AUTO_REPLAY       = true,  -- กด Replay อัตโนมัติเมื่อจบรอบ
    REPLAY_DELAY      = 4,     -- เวลารอก่อนกด Replay
    SHOW_BUTTON       = true,  -- แสดงปุ่มเปิด/ปิดบนหน้าจอ
}

if not game:IsLoaded() then game.Loaded:Wait() end

local Players             = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local VirtualUser       = game:GetService("VirtualUser")
local LocalPlayer       = Players.LocalPlayer or Players.PlayerAdded:Wait()

-- ระบบกัน AFK ป้องกันเกมเตะเมื่อปล่อยทิ้งไว้นานๆ
pcall(function()
    LocalPlayer.Idled:Connect(function()
        VirtualUser:Button2Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
        task.wait(1)
        VirtualUser:Button2Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
    end)
end)

local env = (getgenv and getgenv()) or _G
if env.__CentipedeRaid then
    pcall(env.__CentipedeRaid.stop)
end

-- ระบบ Safe WaitFor ป้องกันเกมค้างบนคลาวด์หรือมือถือ
local function safeWaitFor(parent, name, timeout)
    local start = tick()
    local obj = parent:FindFirstChild(name)
    while not obj and (tick() - start < (timeout or 10)) do
        task.wait(0.2)
        obj = parent:FindFirstChild(name)
    end
    return obj
end

local RemoteEvents = safeWaitFor(ReplicatedStorage, "RemoteEvents", 15)
local AttackEvent  = RemoteEvents and safeWaitFor(RemoteEvents, "PlayerAttackEvent", 10)

local WeaponsDatabase
pcall(function()
    WeaponsDatabase = require(ReplicatedStorage:WaitForChild("Databases"):WaitForChild("WeaponsDatabase"))
end)

local running     = true
local enabled     = true
local status      = "Starting"
local connections = {}
local stats       = { runs = 0, wins = 0, losses = 0, debris = 0, dodges = 0, centipedes = 0, hurt = 0 }

local function connect(signal, fn)
    if not signal then return end
    local c = signal:Connect(fn)
    table.insert(connections, c)
    return c
end

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

local debrisEvent = RemoteEvents and RemoteEvents:FindFirstChild("RaidDebrisEvent")
if debrisEvent then
    connect(debrisEvent.OnClientEvent, function(pos, radius, delayTime, fallTime)
        if typeof(pos) ~= "Vector3" then return end
        stats.debris += 1
        table.insert(dangerZones, {
            pos     = pos,
            radius  = radius or 6,
            expires = os.clock() + (delayTime or 1.5) + (fallTime or 0.45) + 0.6,
        })
    end)
end

local lastAttack   = 0
local wasDodging   = false
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
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not (hum and hrp) or hum.Health <= 0 then
        status = "Waiting for character"
        return
    end

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
    local dist  = delta.Magnitude
    if dist > 0.5 then
        local speed = dodging and CONFIG.DODGE_SPEED or CONFIG.MOVE_SPEED
        local move  = math.min(dist, speed * dt)
        local newPos = here + delta.Unit * move
        local look = targetRoot and flat(targetRoot.Position) - flat(newPos) or delta
        if look.Magnitude < 0.1 then look = hrp.CFrame.LookVector end
        hrp.CFrame = CFrame.lookAt(newPos, newPos + Vector3.new(look.X, 0, look.Z))
        hrp.AssemblyLinearVelocity = Vector3.zero
    end

    if not target then
        status = dodging and "Dodging debris" or "Waiting for Centipede"
        return
    end

    ensureWeapon(char, hum)
    local now = os.clock()
    if now - lastAttack >= CONFIG.ATTACK_INTERVAL then
        lastAttack = now
        if AttackEvent then AttackEvent:FireServer() end
    end
    local th = target:FindFirstChildOfClass("Humanoid")
    status = string.format("%s%s (%d HP)", dodging and "Dodging + " or "Hitting ", target.Name, th and th.Health or 0)
end

connect(RunService.Heartbeat, function(dt)
    if not running then return end
    if not enabled then
        status = "OFF"
        return
    end
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

local readyEvent  = RemoteEvents and RemoteEvents:FindFirstChild("RaidReadyRequestEvent")
local lobbyEvent  = RemoteEvents and RemoteEvents:FindFirstChild("RaidLobbyStatusEvent")
local statusEvent = RemoteEvents and RemoteEvents:FindFirstChild("RaidStatusEvent")
local resultEvent = RemoteEvents and RemoteEvents:FindFirstChild("RaidResultEvent")
local actionEvent = RemoteEvents and RemoteEvents:FindFirstChild("RaidResultActionEvent")

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
            if running and enabled and actionEvent then
                pcall(function()
                    actionEvent:FireServer("Replay")
                end)
            end
        end)
    end)
end

-- ระบบตรวจสอบและล็อกห้องเรด (ป้องกันไม่ให้สคริปต์รันเพี้ยนเวลาเซิร์ฟเวอร์มีปัญหา)
task.spawn(function()
    while running do
        task.wait(2)
        pcall(function()
            local base = workspace:FindFirstChild("Bases")
            if not base and running and stats.runs > 0 then
                status = "Out of Raid Zone (Waiting...)"
            end
        end)
    end
end)

local gui
if CONFIG.SHOW_BUTTON then
    pcall(function()
        gui = Instance.new("ScreenGui")
        gui.Name = "CentipedeRaidGui"
        gui.ResetOnSpawn = false
        local targetParent = LocalPlayer:FindFirstChild("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 5)
        gui.Parent = targetParent

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
        label.Size = UDim2.fromOffset(260, 36)
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
                label.Text = string.format("%s\nRuns %d | Wins %d | Centipedes %d | Dodged %d",
                    status, stats.runs, stats.wins, stats.centipedes, stats.dodges)
                task.wait(0.6)
            end
        end)
    end)
end

env.__CentipedeRaid = {
    stats = stats,
    getStatus = function() return status end,
    stop = function()
        running = false
        for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
        if gui then pcall(function() gui:Destroy() end) end
    end,
}
