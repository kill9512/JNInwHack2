local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("KONG GUISUS", "DarkTheme")

-- --- Variables (ค่าเริ่มต้นตามที่มึงสั่ง) ---
local SelectedMode = "Manual"
local SelectedPlayer = nil
local UsePercentage = false
local followDistance = 5
local followEnabled = false
local followMode = "Normal" -- Default เป็น Normal
local flySpeed = 10

-- --- Functions ---
local function getHealth(plr)
    local char = plr.Character
    if char and char:FindFirstChild("Humanoid") then
        return UsePercentage and (char.Humanoid.Health / char.Humanoid.MaxHealth) or char.Humanoid.Health
    end
    return nil
end

local function UpdatePlayerTable()
    local tbl = {"None (Off)"} -- Default หัวแถว
    for _, plr in pairs(game.Players:GetPlayers()) do
        if plr.Name ~= game.Players.LocalPlayer.Name then
            table.insert(tbl, plr.Name)
        end
    end
    return tbl
end

-- --- UI: Main Tab ---
local Tab = Window:NewTab("Main")
local Section = Tab:NewSection("Smart Follow Player")

-- 1. Target Mode (Default: Manual)
Section:NewDropdown("Target Mode", "Choose find mode", {"Manual", "Max HP", "Min HP", "Off"}, function(mode)
    SelectedMode = mode
end)

-- 2. Select Player (Default: None (Off))
local drop = Section:NewDropdown("Select Player", "Manual selection", UpdatePlayerTable(), function(name)
    if name == "None (Off)" then
        SelectedPlayer = nil
    else
        SelectedPlayer = name
    end
end)

-- 3. ปุ่ม Refresh (แบบล้างค่าผีออก)
Section:NewButton("Refresh Players", "Update list & Reset Selection", function()
    local newList = UpdatePlayerTable()
    drop:Refresh(newList)
    SelectedPlayer = nil -- ล้างค่าตัวแปร
    -- หมายเหตุ: Kavo ไม่รองรับการบังคับ Text ใน Dropdown ให้เปลี่ยนผ่าน Script 
    -- แต่มันจะล้างค่าในระบบให้เพื่อป้องกันตัวละครวิ่งไปหาคนที่ไม่อยู่แล้ว
    Library:Notify("Refreshed", "Selection reset to None", 2)
end)

Section:NewToggle("Use % Health Logic", "Percentage mode", function(state)
    UsePercentage = state
end)

-- --- UI: Movement Section ---
local MoveSection = Tab:NewSection("Movement Control")

MoveSection:NewToggle("Enable Follow", "Start/Stop Movement", function(state)
    followEnabled = state
end)

MoveSection:NewSlider("Follow Distance", "Distance to keep", 20, 1, function(s)
    followDistance = s
end)

-- 3. Follow Mode (Default: Normal)
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

-- --- LOGIC CORE ( optimization ) ---
task.spawn(function()
    while task.wait(0.01) do
        if not followEnabled then continue end
        
        local finalTarget = nil

        -- ค้นหาเป้าหมาย
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

        -- การเคลื่อนไหว
        if finalTarget and finalTarget.Character and finalTarget.Character:FindFirstChild("HumanoidRootPart") then
            local myChar = game.Players.LocalPlayer.Character
            local myRoot = myChar:FindFirstChild("HumanoidRootPart")
            local myHuman = myChar:FindFirstChild("Humanoid")
            local targetRoot = finalTarget.Character.HumanoidRootPart
            
            if myRoot and targetRoot and myHuman then
                local dist = (myRoot.Position - targetRoot.Position).Magnitude

                if followMode == "Walk" then
                    local targetHuman = finalTarget.Character:FindFirstChild("Humanoid")
                    if targetHuman then myHuman.WalkSpeed = targetHuman.WalkSpeed end
                    if dist > followDistance then
                        local dir = (targetRoot.Position - myRoot.Position).Unit
                        myHuman:MoveTo(targetRoot.Position - (dir * followDistance))
                        
                        -- Raycast Jump
                        local ray = Ray.new(myRoot.Position, dir * 3)
                        local hit = workspace:FindPartOnRayWithIgnoreList(ray, {myChar})
                        if hit and hit.CanCollide then myHuman.Jump = true end
                    end
                elseif followMode == "TeleportBehind" then
                    myRoot.CFrame = targetRoot.CFrame * CFrame.new(0, 0, followDistance) * CFrame.Angles(0, math.pi, 0)
                elseif followMode == "CFrameFly" then
                    if dist > followDistance then
                        local direction = (targetRoot.Position - myRoot.Position).Unit
                        myRoot.CFrame = myRoot.CFrame + (direction * (flySpeed / 100))
                        myRoot.CFrame = CFrame.lookAt(myRoot.Position, targetRoot.Position)
                        myRoot.Velocity = Vector3.new(0, 0, 0)
                    end
                end
            end
        end
    end
end)
