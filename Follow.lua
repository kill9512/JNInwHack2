local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("KONG GUISUS", "DarkTheme")
local Tab = Window:NewTab("Main")
local Section = Tab:NewSection("Smart Follow Player")

-- --- Variables ---
local SelectedMode = "Manual" 
local SelectedPlayer = nil 
local UsePercentage = false 
local followDistance = 5
local followEnabled = false
local followMode = "Standard" -- [เพิ่มตัวแปรโหมดการเดิน]

-- ฟังก์ชันหาเลือดผู้เล่น
local function getHealth(plr)
    local char = plr.Character
    if char and char:FindFirstChild("Humanoid") then
        return UsePercentage and (char.Humanoid.Health / char.Humanoid.MaxHealth) or char.Humanoid.Health
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

-- --- UI Elements: Targeting ---

-- 1. เลือกโหมดหาเป้าหมาย
Section:NewDropdown("Manual", "Choose how to find target", {"Manual", "Max HP", "Min HP", "Off"}, function(mode)
    SelectedMode = mode
end)

-- 2. เลือกชื่อผู้เล่น
local drop = Section:NewDropdown("None (Off)", "Manual selection", UpdatePlayerTable(), function(name)
    SelectedPlayer = (name == "None (Off)") and nil or name
end)

-- 3. ปุ่ม Refresh (แบบหักดิบชื่อปุ่มกลับเป็น None (Off) ทุกรอบ)
Section:NewButton("Refresh Dropdown", "Update list & Reset selection", function()
    SelectedPlayer = nil 
    drop:Refresh(UpdatePlayerTable())
    
    -- ท่าไม้ตายเปลี่ยนชื่อปุ่มบนหน้าจอ 100%
    pcall(function()
        for _, v in pairs(Section:GetContainer().container:GetChildren()) do
            if v:IsA("Frame") and v:FindFirstChild("Main") and v.Main:FindFirstChild("Title") then
                if v.Main.Title.Text ~= "Manual" then 
                    v.Main.Title.Text = "None (Off)"
                end
            end
        end
    end)
end)

Section:NewToggle("Use % Health Logic", "If ON, check health by percentage", function(state)
    UsePercentage = state
end)

-- --- UI Elements: Movement Control ---
local MoveSection = Tab:NewSection("Movement Control")

MoveSection:NewToggle("Enable Follow", "Start moving to target", function(state)
    followEnabled = state
end)

MoveSection:NewSlider("Follow Distance", "Distance from target", 20, 1, function(s)
    followDistance = s
end)

-- [หยอดโหมด Match Speed และ Teleport Behind ตรงนี้]
MoveSection:NewDropdown("Standard", "Movement Mode", {"Standard", "Match Speed", "Teleport Behind"}, function(mode)
    followMode = mode
    -- ถ้าไม่ใช่ Match Speed ให้คืนค่าความเร็วปกติ
    if mode ~= "Match Speed" then
        pcall(function() game.Players.LocalPlayer.Character.Humanoid.WalkSpeed = 16 end)
    end
end)

-- --- LOGIC CORE (Pathfinding + Super Powers) ---
local PathfindingService = game:GetService("PathfindingService")

task.spawn(function()
    while task.wait(0.1) do 
        if not followEnabled then continue end 
        
        local finalTarget = nil
        -- 1. เลือกเป้าหมาย
        if SelectedMode == "Manual" then
            finalTarget = game.Players:FindFirstChild(SelectedPlayer)
        elseif SelectedMode == "Max HP" or SelectedMode == "Min HP" then
            local bestHP = (SelectedMode == "Max HP") and -1 or math.huge
            for _, p in pairs(game.Players:GetPlayers()) do
                if p ~= game.Players.LocalPlayer then
                    local hp = getHealth(p)
                    if hp then
                        if (SelectedMode == "Max HP" and hp > bestHP) or (SelectedMode == "Min HP" and hp < bestHP) then
                            bestHP = hp; finalTarget = p
                        end
                    end
                end
            end
        end

        -- 2. สั่งเดิน/วาร์ป
        if finalTarget and finalTarget.Character and finalTarget.Character:FindFirstChild("HumanoidRootPart") then
            local myChar = game.Players.LocalPlayer.Character
            local myHuman = myChar:FindFirstChild("Humanoid")
            local myRoot = myChar:FindFirstChild("HumanoidRootPart")
            local targetRoot = finalTarget.Character.HumanoidRootPart
            local targetHuman = finalTarget.Character:FindFirstChild("Humanoid")
            
            if myHuman and myRoot and targetRoot then
                
                -- --- พลังที่ 2: Teleport Behind (สิงหลัง) ---
                if followMode == "Teleport Behind" then
                    -- คำนวณจุดข้างหลังเพื่อน
                    local backPos = targetRoot.CFrame * CFrame.new(0, 0, followDistance)
                    -- วาร์ปไปจุดนั้นและหันหน้าตามเพื่อน
                    myRoot.CFrame = CFrame.new(backPos.Position, targetRoot.Position + targetRoot.CFrame.LookVector * 100)
                
                else
                    -- --- พลังที่ 1: Match Speed (เลียนแบบความเร็ว) ---
                    if followMode == "Match Speed" and targetHuman then
                        myHuman.WalkSpeed = targetHuman.WalkSpeed
                    end

                    -- --- ระบบเดิน Smart Pathfinding (โค้ดดั้งเดิมมึง) ---
                    local distance = (myRoot.Position - targetRoot.Position).Magnitude
                    if distance > followDistance then
                        local path = PathfindingService:CreatePath({AgentCanJump = true, AgentWaypointSpacing = 2})
                        path:ComputeAsync(myRoot.Position, targetRoot.Position)
                        
                        if path.Status == Enum.PathStatus.Success then
                            local waypoints = path:GetWaypoints()
                            if waypoints[2] then
                                local wp = waypoints[2]
                                myHuman:MoveTo(wp.Position)
                                if wp.Action == Enum.PathfindingWaypointAction.Jump then
                                    myHuman.Jump = true
                                end
                            end
                        else
                            myHuman:MoveTo(targetRoot.Position)
                        end
                    end
                end
            end
        end
    end
end)
