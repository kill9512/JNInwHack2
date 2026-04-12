local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("KONG GUISUS", "DarkTheme")

-- --- Variables (ประกาศตัวแปรไว้บนสุด) ---
local SelectedMode = "Manual"
local SelectedPlayer = nil
local UsePercentage = false
local followDistance = 5
local followEnabled = false
local followMode = "Normal"
local flySpeed = 10 -- ปรับความเร็วได้จาก Slider

-- --- Functions (ฟังก์ชันตัวช่วย) ---
local function getHealth(plr)
    local char = plr.Character
    if char and char:FindFirstChild("Humanoid") then
        if UsePercentage then
            return char.Humanoid.Health / char.Humanoid.MaxHealth
        else
            return char.Humanoid.Health
        end
    end
    return nil
end

local function UpdatePlayerTable()
    local tbl = {"None (Off)"}
    for _, plr in pairs(game.Players:GetPlayers()) do
        if plr.Name ~= game.Players.LocalPlayer.Name then
            table.insert(tbl, plr.Name)
        end
    end
    return tbl
end

-- --- UI: Section 1 (Target Selection) ---
local Tab = Window:NewTab("Main")
local Section = Tab:NewSection("Smart Follow Player")

Section:NewDropdown("Target Mode", "Choose how to find target", {"Manual", "Max HP", "Min HP", "Off"}, function(mode)
    SelectedMode = mode
end)

local drop = Section:NewDropdown("Select Player", "Manual selection", UpdatePlayerTable(), function(name)
    SelectedPlayer = (name == "None (Off)") and nil or name
end)

Section:NewButton("Refresh Players", "Update manual list", function()
    drop:Refresh(UpdatePlayerTable())
end)

Section:NewToggle("Use % Health Logic", "Check health by percentage", function(state)
    UsePercentage = state
end)

-- --- UI: Section 2 (Movement Control) ---
local MoveSection = Tab:NewSection("Movement Control")

MoveSection:NewToggle("Enable Follow", "Start/Stop Movement", function(state)
    followEnabled = state
end)

MoveSection:NewSlider("Follow Distance", "Distance to keep", 20, 1, function(s)
    followDistance = s
end)

MoveSection:NewDropdown("Follow Mode", "Power Selection", {"Normal", "Walk", "TeleportBehind", "CFrameFly"}, function(mode)
    followMode = mode
    if mode == "Normal" then
        local myChar = game.Players.LocalPlayer.Character
        if myChar and myChar:FindFirstChild("Humanoid") then
            myChar.Humanoid.WalkSpeed = 16 
        end
    end
end)

MoveSection:NewSlider("Fly Speed", "Speed for CFrameFly", 100, 1, function(s)
    flySpeed = s
end)

-- --- LOGIC CORE (หัวใจหลักที่คุมทุกอย่าง) ---
task.spawn(function()
    while task.wait(0.01) do -- รันถี่ๆ เพื่อความเนียน
        if not followEnabled then continue end
        
        local finalTarget = nil

        -- 1. ค้นหาเป้าหมายตามโหมดที่เลือก
        if SelectedMode == "Manual" then
            finalTarget = game.Players:FindFirstChild(SelectedPlayer)
        elseif SelectedMode == "Max HP" then
            local highHealth = -1
            for _, p in pairs(game.Players:GetPlayers()) do
                if p ~= game.Players.LocalPlayer then
                    local hp = getHealth(p)
                    if hp and hp > highHealth then highHealth = hp; finalTarget = p end
                end
            end
        elseif SelectedMode == "Min HP" then
            local lowHealth = math.huge
            for _, p in pairs(game.Players:GetPlayers()) do
                if p ~= game.Players.LocalPlayer then
                    local hp = getHealth(p)
                    if hp and hp < lowHealth then lowHealth = hp; finalTarget = p end
                end
            end
        end

        -- 2. สั่งการเคลื่อนไหวไปหา finalTarget
        if finalTarget and finalTarget.Character and finalTarget.Character:FindFirstChild("HumanoidRootPart") then
            local myChar = game.Players.LocalPlayer.Character
            local myRoot = myChar:FindFirstChild("HumanoidRootPart")
            local myHuman = myChar:FindFirstChild("Humanoid")
            local targetRoot = finalTarget.Character.HumanoidRootPart
            
            if myRoot and targetRoot and myHuman then
                local dist = (myRoot.Position - targetRoot.Position).Magnitude

                -- โหมด Walk (เดินตาม)
                if followMode == "Walk" then
                    local targetHuman = finalTarget.Character:FindFirstChild("Humanoid")
                    if targetHuman then myHuman.WalkSpeed = targetHuman.WalkSpeed end
                    if dist > followDistance then
                        local dir = (targetRoot.Position - myRoot.Position).Unit
                        myHuman:MoveTo(targetRoot.Position - (dir * followDistance))
                        
                        -- กันติด (Raycast Jump)
                        local ray = Ray.new(myRoot.Position, dir * 3)
                        local hit = workspace:FindPartOnRayWithIgnoreList(ray, {myChar})
                        if hit and hit.CanCollide then myHuman.Jump = true end
                    end

                -- โหมดผีสิง (Teleport Behind)
                elseif followMode == "TeleportBehind" then
                    local backPos = targetRoot.CFrame * CFrame.new(0, 0, followDistance)
                    myRoot.CFrame = CFrame.lookAt(backPos.Position, targetRoot.Position)

                -- โหมดลอยไปหา (CFrame Fly)
                elseif followMode == "CFrameFly" then
                    if dist > followDistance then
                        local direction = (targetRoot.Position - myRoot.Position).Unit
                        myRoot.CFrame = myRoot.CFrame + (direction * (flySpeed / 100))
                        myRoot.CFrame = CFrame.lookAt(myRoot.Position, targetRoot.Position)
                        myRoot.Velocity = Vector3.new(0, 0, 0) -- กันตัวสั่น
                    end
                end
            end
        end
    end
end)
