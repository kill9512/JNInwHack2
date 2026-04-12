local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("KONG GUISUS", "DarkTheme")
local Tab = Window:NewTab("Main")
local Section = Tab:NewSection("Smart Follow Player")
local PlayerTable = {}

-- --- Variables ---
local SelectedMode = "Manual" -- โหมดเริ่มต้น
local SelectedPlayer = nil -- ชื่อผู้เล่นที่เลือกเอง
local UsePercentage = false -- Toggle สำหรับ % HP
local followMode = "Standard"
local followDistance = 5
local followEnabled = false

-- ฟังก์ชันหาเลือดผู้เล่น
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

-- ฟังก์ชันอัปเดตรายชื่อ
local function UpdatePlayerTable()
    local tbl = {"None (Off)"}
    for _, plr in pairs(game.Players:GetPlayers()) do
        if plr.Name ~= game.Players.LocalPlayer.Name then
            table.insert(tbl, plr.Name)
        end
    end
    return tbl
end

-- --- UI Elements: Section 1 ---
Section:NewDropdown("Target Mode", "Choose how to find target", {"Manual", "Max HP", "Min HP", "Off"}, function(mode)
    SelectedMode = mode
end)

local drop = Section:NewDropdown("Select Player", "Manual selection", UpdatePlayerTable(), function(name)
    if name == "None (Off)" then
        SelectedPlayer = nil
    else
        SelectedPlayer = name
    end
end)

Section:NewButton("Refresh Players", "Update manual list", function()
    drop:Refresh(UpdatePlayerTable())
end)

Section:NewToggle("Use % Health Logic", "If ON, check health by percentage", function(state)
    UsePercentage = state
end)

-- --- UI Elements: Section 2 ---
local MoveSection = Tab:NewSection("Movement Control")

MoveSection:NewToggle("Enable Follow", "Start moving to target", function(state)
    followEnabled = state
end)

MoveSection:NewSlider("Follow Distance", "Distance from target", 20, 1, function(s)
    followDistance = s
end)

MoveSection:NewDropdown("Movement Mode", "Choose how to move", {"Standard", "Match Speed"}, function(mode)
    followMode = mode
    if mode == "Standard" then
        local myChar = game.Players.LocalPlayer.Character
        if myChar and myChar:FindFirstChild("Humanoid") then
            myChar.Humanoid.WalkSpeed = 16 
        end
    end
end)

-- --- LOGIC CORE ---
task.spawn(function()
    while task.wait(0.1) do
        if not followEnabled then continue end 
        
        local finalTarget = nil

        -- 1. เลือกเป้าหมาย
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

        -- 2. สั่งการเคลื่อนไหว
        if finalTarget and finalTarget.Character and finalTarget.Character:FindFirstChild("HumanoidRootPart") then
            local myChar = game.Players.LocalPlayer.Character
            local myHuman = myChar:FindFirstChild("Humanoid")
            local myRoot = myChar:FindFirstChild("HumanoidRootPart")
            local targetRoot = finalTarget.Character.HumanoidRootPart
            local targetHuman = finalTarget.Character:FindFirstChild("Humanoid")
            
            if myHuman and myRoot and targetRoot then
                -- พลัง Match Speed
                if followMode == "Match Speed" and targetHuman then
                    myHuman.WalkSpeed = targetHuman.WalkSpeed
                end

                local distance = (myRoot.Position - targetRoot.Position).Magnitude
                if distance > followDistance then
                    local direction = (targetRoot.Position - myRoot.Position).Unit
                    local destination = targetRoot.Position - (direction * followDistance)
                    myHuman:MoveTo(destination)
                    
                    local ray = Ray.new(myRoot.Position, direction * 3)
                    local hit = workspace:FindPartOnRayWithIgnoreList(ray, {myChar})
                    if hit and hit.CanCollide then
                        myHuman.Jump = true
                    end
                end
            end
        end
    end
end)
