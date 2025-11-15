
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("KONG GUISUS", "DarkTheme")
local Tab = Window:NewTab("Main")
local Section = Tab:NewSection("Teleport")

Section:NewToggle("Auto Delete", "", function(t)
    _G.toggle = t
    while _G.toggle do
        wait()
        local enemyFolder = workspace:FindFirstChild("Stuff") and workspace.Stuff:FindFirstChild("Enemy")
        if enemyFolder then
            for i, v in pairs(enemyFolder:GetDescendants()) do
            if v:IsA("Humanoid") and v.Health > 100 then -- เพิ่มเงื่อนไขการตรวจสอบ humanoid และค่าเลือด
                game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = v.Parent.HumanoidRootPart.CFrame * CFrame.new(0,0,10)
                end
            end
        else
            wait(1)
        end
    end
end)

Section:NewButton("Click To God", "", function()
    local rs = game:GetService("ReplicatedStorage")
    local events = rs:FindFirstChild("Events")
    if not events then return end

    local attackOnClient = events:FindFirstChild("AttackOnClient")

    if attackOnClient then
        attackOnClient:Destroy()
    end
end)


Section:NewButton("Click Tp", "", function()
game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(Vector3.new(-31461.613281, 3593.572510, 41.445580))
end)
local antiJumpScareEnabled = false

Section:NewToggle("Anti Jumpscare", "ลบ ImageLabel ทั้งหมด ยกเว้นใน Inventory และ PlayerList", function(state)
    antiJumpScareEnabled = state
    while antiJumpScareEnabled do
        wait(0.5)
        for _, gui in pairs(game.Players.LocalPlayer.PlayerGui:GetChildren()) do
            -- ตรวจสอบว่าไม่ใช่ Inventory และ PlayerList
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

local antiKnockbackEnabled = false

Section:NewToggle("Anti Knockback", "ป้องกันตัวละครจากการถูกกระแทก", function(state)
    antiKnockbackEnabled = state
    local player = game.Players.LocalPlayer
    local character = player.Character or player.CharacterAdded:Wait()

    while antiKnockbackEnabled do
        wait(0.1)
        if character and character:FindFirstChild("HumanoidRootPart") then
            character.HumanoidRootPart.Velocity = Vector3.new(0,0,0) -- รีเซ็ตความเร็วเพื่อกัน Knockback
        end
    end
end)

local antiFreezeEnabled = false

Section:NewToggle("Anti Freeze", "ป้องกันการถูกขังหรือลอยอยู่กับที่ (ไม่ทำให้ตาย)", function(state)
    antiFreezeEnabled = state
    local player = game.Players.LocalPlayer
    local character = player.Character or player.CharacterAdded:Wait()

    while antiFreezeEnabled do
        wait(0.1)
        if character then
            for _, part in pairs(character:GetDescendants()) do
                if part:IsA("BodyPosition") or part:IsA("BodyGyro") or part:IsA("BodyVelocity") or part:IsA("AlignPosition") then
                    part:Destroy() -- ลบ Object ที่ล็อกตัวละคร
                end
            end

            -- ปลดล็อกฟิสิกส์ของ HumanoidRootPart
            if character:FindFirstChild("HumanoidRootPart") then
                local hrp = character.HumanoidRootPart
                hrp.Velocity = Vector3.new(0, 0, 0) 
                hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0) 
                hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0) 
            end
        end
    end
end)


Section:NewButton("Force Interact", "กด ProximityPrompt ทันที", function()
    local Prox = workspace.Ohio.SlopMachine5000.Keyboard.Intersection.ProximityPrompt
    local character = game.Players.LocalPlayer.Character
    local humanoidRootPart = character and character:WaitForChild("HumanoidRootPart")

    if Prox and humanoidRootPart then
        -- เพิ่มระยะการเห็นให้ ProximityPrompt
        Prox.MaxActivationDistance = 20  -- ตั้งระยะการเห็นเป็น 20 studs

        -- วาร์ปตัวละครไปยังตำแหน่งที่ระบุ
        humanoidRootPart.CFrame = CFrame.new(-99462.9141, 3593.71729, 57.0312386, -0.998897135, -4.62774929e-09, 0.0469521955, -4.81399098e-09, 1, -3.8535517e-09, -0.0469521955, -4.07532896e-09, -0.998897135)
        
        -- กด ProximityPrompt ทันที
        fireproximityprompt(Prox)
        Prox.HoldDuration = 0  -- ปรับ HoldDuration ให้เป็น 0
    end
end)

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
