
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("KONG GUISUS", "DarkTheme")

local Tab = Window:NewTab("Main")
local Section = Tab:NewSection("Teleport")

_G.distance = 30

-------------------------------------------------
-- Auto Delete (มีเช็ค ObjectValue = kill9512)
-------------------------------------------------
Section:NewToggle("Auto Delete", "", function(t)
    _G.toggle = t
    while _G.toggle do
        wait()

        local enemyFolder = workspace:FindFirstChild("Stuff")
            and workspace.Stuff:FindFirstChild("Enemy")

        if enemyFolder then
            
            -- ตรวจสอบ Players/ObjectValue ชื่อ kill9512
            local playersFolder = enemyFolder:FindFirstChild("Players")
            local hasTarget = false

            if playersFolder then
                for _, obj in pairs(playersFolder:GetChildren()) do
                    if obj:IsA("ObjectValue") and obj.Name == "kill9512" then
                        hasTarget = true
                        break
                    end
                end
            end

            -- ถ้ามี kill9512 → วาร์ปหา monster
            if hasTarget then
                for _, v in pairs(enemyFolder:GetDescendants()) do
                    if v:IsA("Humanoid") and v.Health > 100 then
                        local hrp = v.Parent:FindFirstChild("HumanoidRootPart")
                        if hrp then
                            game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame =
                                hrp.CFrame * CFrame.new(0, 0, _G.distance)
                        end
                    end
                end

            else
                wait(1) -- ไม่มี kill9512 → รอ
            end

        else
            wait(1)
        end
    end
end)

-------------------------------------------------
-- Slider ระยะวาร์ป
-------------------------------------------------
Section:NewSlider("ระยะการวาร์ป", "กำหนดระยะห่างจากศัตรู", 50, 1, function(value)
    _G.distance = value
    print("ระยะปัจจุบัน:", _G.distance)
end)

-------------------------------------------------
-- Teleport ปกติ
-------------------------------------------------
Section:NewButton("Click Tp", "", function()
    game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame =
        CFrame.new(Vector3.new(-31461.613281, 3593.572510, 41.445580))
end)

-------------------------------------------------
-- Click To God
-------------------------------------------------
Section:NewButton("Click To God", "", function()
    local rs = game:GetService("ReplicatedStorage")
    local events = rs:FindFirstChild("Events")
    if not events then return end

    local attackOnClient = events:FindFirstChild("AttackOnClient")
    if attackOnClient then attackOnClient:Destroy() end
end)
-----------------------------------------------------------
-- ⭐ PLAYER SELECTOR + TELEPORT ⭐
-----------------------------------------------------------

-- SafePosition สำหรับ HP ต่ำ
local SafePosition = Vector3.new(-26.996864, 3.928868, 391.019958)

-- Dropdown ผู้เล่น
local PlayerTable = {}
for _, plr in pairs(game.Players:GetPlayers()) do
    table.insert(PlayerTable, plr.Name)
end

local SelectedPlayer = nil
local drop = Section:NewDropdown("เลือกผู้เล่น", "เลือกผู้เล่นเพื่อวาร์ป", PlayerTable, function(name)
    SelectedPlayer = name
end)
-- ปุ่ม Refresh Dropdown
Section:NewButton("Refresh Dropdown", "อัปเดตรายชื่อผู้เล่น", function()
    local newList = {}
    for _, plr in pairs(game.Players:GetPlayers()) do
        table.insert(newList, plr.Name)
    end
    drop:Refresh(newList)
end)
-- Toggle วาร์ปไปหาผู้เล่นทุก 5 วินาที
local teleportToggle = false
Section:NewToggle("Teleport to Player (5s)", "วาร์ปไปหาผู้เล่นทุก 5 วินาที", function(state)
    teleportToggle = state
    spawn(function()
        while teleportToggle do
            wait(5)
            local player = game.Players.LocalPlayer
            local character = player.Character
            if not character or not character:FindFirstChild("HumanoidRootPart") or not character:FindFirstChild("Humanoid") then continue end

            -- เช็ค HP
            if character.Humanoid.Health < 50000 then
                character.HumanoidRootPart.CFrame = CFrame.new(SafePosition)
                wait(1) -- รอให้ไป SafePosition ก่อน
            end

            -- วาร์ปไปหาผู้เล่นที่เลือก
            if SelectedPlayer then
                local target = game.Players:FindFirstChild(SelectedPlayer)
                if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
                    local hrp = target.Character.HumanoidRootPart
                    character.HumanoidRootPart.CFrame = hrp.CFrame * CFrame.new(0, 0, 5)
                end
            end
        end
    end)
end)
-------------------------------------------------
-- Anti Jumpscare
-------------------------------------------------
local antiJumpScareEnabled = false
Section:NewToggle("Anti Jumpscare", "ลบ ImageLabel ทั้งหมด", function(state)
    antiJumpScareEnabled = state

    while antiJumpScareEnabled do
        wait(0.5)
        for _, gui in pairs(game.Players.LocalPlayer.PlayerGui:GetChildren()) do
            if gui:IsA("ScreenGui") and gui.Name ~= "Inventory" and gui.Name ~= "PlayerList" then
                for _, element in pairs(gui:GetDescendants()) do
                    if element:IsA("ImageLabel") then
                        element:Destroy()
                    end
                end
            end
        end
    end
end)

-------------------------------------------------
-- Anti Knockback
-------------------------------------------------
local antiKnockbackEnabled = false
Section:NewToggle("Anti Knockback", "", function(state)
    antiKnockbackEnabled = state
    local player = game.Players.LocalPlayer
    local character = player.Character or player.CharacterAdded:Wait()

    while antiKnockbackEnabled do
        wait(0.1)
        if character and character:FindFirstChild("HumanoidRootPart") then
            character.HumanoidRootPart.Velocity = Vector3.new(0,0,0)
        end
    end
end)

-------------------------------------------------
-- Anti Freeze
-------------------------------------------------
local antiFreezeEnabled = false
Section:NewToggle("Anti Freeze", "", function(state)
    antiFreezeEnabled = state
    local player = game.Players.LocalPlayer
    local character = player.Character or player.CharacterAdded:Wait()

    while antiFreezeEnabled do
        wait(0.1)

        if character then
            for _, part in pairs(character:GetDescendants()) do
                if part:IsA("BodyPosition") or part:IsA("BodyGyro")
                    or part:IsA("BodyVelocity") or part:IsA("AlignPosition") then
                    part:Destroy()
                end
            end

            local hrp = character:FindFirstChild("HumanoidRootPart")
            if hrp then
                hrp.Velocity = Vector3.new(0, 0, 0)
                hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            end
        end
    end
end)

-------------------------------------------------
-- Night Vision
-------------------------------------------------
local nightVision = false
Section:NewToggle("Night Vision", "", function(state)
    nightVision = state
    local Lighting = game:GetService("Lighting")

    if nightVision then
        Lighting.Brightness = 5
        Lighting.Ambient = Color3.new(1, 1, 1)
        Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
        Lighting.FogEnd = 100000
    else
        Lighting.Brightness = 1
        Lighting.Ambient = Color3.new(0.5, 0.5, 0.5)
        Lighting.OutdoorAmbient = Color3.new(0.5, 0.5, 0.5)
        Lighting.FogEnd = 1000
    end
end)

-------------------------------------------------
-- Force Interact
-------------------------------------------------
Section:NewButton("Force Interact", "", function()
    local Prox = workspace.Ohio.SlopMachine5000.Keyboard.Intersection.ProximityPrompt
    local character = game.Players.LocalPlayer.Character
    local hrp = character and character:WaitForChild("HumanoidRootPart")

    if Prox and hrp then
        Prox.MaxActivationDistance = 20

        hrp.CFrame = CFrame.new(-99462.9141, 3593.71729, 57.0312386)

        fireproximityprompt(Prox)
        Prox.HoldDuration = 0
    end
end)

-------------------------------------------------
-- Toggle Fly (Press X)
-------------------------------------------------

Section:NewButton("Toggle Fly (Press X)", "กด X เพื่อเปิด/ปิดการบิน", function()
    local Players = game:GetService("Players")
    local UserInputService = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")

    local Maid = loadstring(game:HttpGet('https://raw.githubusercontent.com/Quenty/NevermoreEngine/main/src/maid/src/Shared/Maid.lua'))()

    shared.Maid = shared.Maid or Maid.new(); local Maid = shared.Maid; Maid:DoCleaning()
    shared.Active = false  -- เปลี่ยนค่าเริ่มต้นเป็น false เพื่อให้ปิดการบิน

    local Ignore = false
    local Offset = 4
    local Camera = workspace.CurrentCamera
    local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
    local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local CurrentPoint = Character:GetPivot()

    local task = table.clone(task)
    local OldDelay = task.delay

    function task.delay(Time, Function)
        local Enabled = true
        OldDelay(Time, function()
            if Enabled then
                Function()
            end
        end)

        return {
            Cancel = function()
                Enabled = false
            end,
            Activate = function()
                Enabled = false
                Function()
            end
        }
    end

    local wait = task.wait

    local function StopVelocity()
        local HumanoidRootPart = Character and Character:FindFirstChild("HumanoidRootPart")
        if not HumanoidRootPart then return end
        HumanoidRootPart.Velocity = Vector3.zero
    end

    Maid:GiveTask(LocalPlayer.CharacterAdded:Connect(function(NewCharacter)
        Character = NewCharacter
    end))

    Maid:GiveTask(RunService.Stepped:Connect(function()
        if shared.Active then
            StopVelocity()
            local CameraCFrame = Camera.CFrame
            CurrentPoint = CFrame.new(CurrentPoint.Position, CurrentPoint.Position + CameraCFrame.LookVector)
            Character:PivotTo(CurrentPoint)
        end
    end))

    local CurrentTask = nil
    local KeyBindStarted = {
        [Enum.KeyCode.Q] = {
            ["FLY_UP"] = function()
                while UserInputService:IsKeyDown(Enum.KeyCode.Q) do
                    RunService.Stepped:Wait()
                    if Ignore then continue end
                    CurrentPoint = CurrentPoint * CFrame.new(0, Offset, 0)
                end
            end
        },
        [Enum.KeyCode.E] = {
            ["FLY_DOWN"] = function()
                while UserInputService:IsKeyDown(Enum.KeyCode.E) do
                    RunService.Stepped:Wait()
                    if Ignore then continue end
                    CurrentPoint = CurrentPoint * CFrame.new(0, -Offset, 0)
                end
            end
        },
        [Enum.KeyCode.W] = {
            ["FLY_FORWARD"] = function()
                while UserInputService:IsKeyDown(Enum.KeyCode.W) do
                    RunService.Stepped:Wait()
                    if Ignore then continue end
                    CurrentPoint = CurrentPoint * CFrame.new(0, 0, -Offset)
                end
            end
        },
        [Enum.KeyCode.S] = {
            ["FLY_BACK"] = function()
                while UserInputService:IsKeyDown(Enum.KeyCode.S) do
                    RunService.Stepped:Wait()
                    if Ignore then continue end
                    CurrentPoint = CurrentPoint * CFrame.new(0, 0, Offset)
                end
            end
        },
        [Enum.KeyCode.A] = {
            ["FLY_LEFT"] = function()
                while UserInputService:IsKeyDown(Enum.KeyCode.A) do
                    RunService.Stepped:Wait()
                    if Ignore then continue end
                    CurrentPoint = CurrentPoint * CFrame.new(-Offset, 0, 0)
                end
            end
        },
        [Enum.KeyCode.D] = {
            ["FLY_RIGHT"] = function()
                while UserInputService:IsKeyDown(Enum.KeyCode.D) do
                    RunService.Stepped:Wait()
                    if Ignore then continue end
                    CurrentPoint = CurrentPoint * CFrame.new(Offset, 0, 0)
                end
            end
        },
        [Enum.KeyCode.Space] = {
            ["IGNORE_ON"] = function()
                Ignore = true
            end
        },
        [Enum.KeyCode.X] = {  -- ปุ่มเปิด/ปิดการบิน
            ["TOGGLE"] = function()
                local Humanoid = Character:FindFirstChild("Humanoid")
                if not Humanoid then return end
                local HumanoidRootPart = Character:FindFirstChild("HumanoidRootPart")
                if not HumanoidRootPart then return end

                if not shared.Active then
                    CurrentPoint = Character:GetPivot()
                else
                    if CurrentTask then
                        CurrentTask:Activate()
                    end
                    StopVelocity()
                    Character:PivotTo(CFrame.new(Character:GetPivot().Position))

                    local RunServiceSignal = RunService.Stepped:Connect(function()
                        local AssemblyAngularVelocity = HumanoidRootPart.AssemblyAngularVelocity
                        if AssemblyAngularVelocity.X > 20 or AssemblyAngularVelocity.Y > 20 or AssemblyAngularVelocity.Z > 20 then
                            Character:PivotTo(CFrame.new(Character:GetPivot().Position))
                        end
                    end)

                    CurrentTask = task.delay(10, function()
                        RunServiceSignal:Disconnect()
                    end)

                    Maid:GiveTask(RunServiceSignal)
                end

                shared.Active = not shared.Active
            end
        }
    }

    local KeyBindEnded = {
        [Enum.KeyCode.Space] = {
            ["IGNORE_OFF"] = function()
                Ignore = false
            end
        }
    }

    Maid:GiveTask(UserInputService.InputBegan:Connect(function(Input, GameProcessedEvent)
        if not GameProcessedEvent then
            if Input.UserInputType == Enum.UserInputType.Keyboard and KeyBindStarted[Input.KeyCode] then
                for _, Function in pairs(KeyBindStarted[Input.KeyCode]) do
                    task.spawn(Function)
                end
            elseif KeyBindStarted[Input.UserInputType] then
                for _, Function in pairs(KeyBindStarted[Input.UserInputType]) do
                    task.spawn(Function)
                end
            end
        end
    end))

    Maid:GiveTask(UserInputService.InputEnded:Connect(function(Input, GameProcessedEvent)
        if not GameProcessedEvent then
            if Input.UserInputType == Enum.UserInputType.Keyboard and KeyBindEnded[Input.KeyCode] then
                for _, Function in pairs(KeyBindEnded[Input.KeyCode]) do
                    task.spawn(Function)
                end
            elseif KeyBindEnded[Input.UserInputType] then
                for _, Function in pairs(KeyBindEnded[Input.UserInputType]) do
                    task.spawn(Function)
                end
            end
        end
    end))
end)

