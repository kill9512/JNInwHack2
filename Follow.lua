local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("KONG GUISUS", "DarkTheme")
local Tab = Window:NewTab("Main")
local Section = Tab:NewSection("Smart Follow Player")

-- --- Services ---
local Players = game.Players
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")

-- --- Variables (กำหนดค่าเริ่มต้นให้ครบ) ---
local SelectedMode = "Manual"
local SelectedPlayerName = nil
local UsePercentage = false
local followDistance = 5
local followEnabled = false

local lastPos = Vector3.new(0,0,0)
local stuckTime = 0

-- --- Raycast Settings ---
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

-- --- ฟังก์ชันเสริม (Utilities) ---

local function UpdatePlayerTable()
    local tbl = {"None (Off)"}
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            table.insert(tbl, plr.DisplayName .. " (@" .. plr.Name .. ")")
        end
    end
    return tbl
end

local function canGameJump(humanoid)
    local powerEnabled = (humanoid.JumpPower > 0 or humanoid.JumpHeight > 0)
    local stateEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping)
    return powerEnabled and stateEnabled
end

-- ฟังก์ชันหาทิศทางเลี้ยวเมื่อติดมุม
local function getBestEscapeDir(myRoot, moveDir)
    local scanAngles = {45, -45, 90, -90, 135, -135}
    local bestDir = nil
    local maxDist = 0

    for _, angle in ipairs(scanAngles) do
        local rotatedDir = (CFrame.Angles(0, math.rad(angle), 0) * Vector3.new(moveDir.X, 0, moveDir.Z)).Unit
        local result = workspace:Raycast(myRoot.Position, rotatedDir * 10, rayParams)
        
        local dist = result and result.Distance or 10
        if dist > maxDist then
            maxDist = dist
            bestDir = rotatedDir
        end
    end
    return bestDir
end

-- --- UI Elements ---

Section:NewDropdown("Target Mode", "Choose how to find target", {"Manual", "Max HP", "Min HP"}, function(mode)
    SelectedMode = mode
end)

local drop = Section:NewDropdown("Select Player", "Manual selection", UpdatePlayerTable(), function(selection)
    if selection == "None (Off)" then 
        SelectedPlayerName = nil
    else 
        SelectedPlayerName = selection:match("@([^%)]+)") 
    end
end)

Section:NewButton("Refresh Players", "Update manual list", function()
    drop:Refresh(UpdatePlayerTable())
end)

Section:NewToggle("Use % Health Logic", "Check health by percentage", function(state)
    UsePercentage = state
end)

local MoveSection = Tab:NewSection("Movement Control")
MoveSection:NewToggle("Enable Follow", "Start moving to target", function(state)
    followEnabled = state
end)

MoveSection:NewSlider("Follow Distance", "Distance from target", 20, 1, function(s)
    followDistance = s
end)

-- --- LOGIC CORE (แก้ไขส่วนที่ผิดพลาดทั้งหมด) ---
task.spawn(function()
    while true do
        task.wait(0.1)
        if not followEnabled then continue end
        
        local target = nil
        
        -- 1. การค้นหาเป้าหมาย
        if SelectedMode == "Manual" then
            if SelectedPlayerName then
                target = Players:FindFirstChild(SelectedPlayerName)
            end
        else
            local bestHP = (SelectedMode == "Max HP") and -1 or math.huge
            for _, p in pairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("Humanoid") then
                    local hum = p.Character.Humanoid
                    local hp = UsePercentage and (hum.Health / hum.MaxHealth) or hum.Health
                    if (SelectedMode == "Max HP" and hp > bestHP) or (SelectedMode == "Min HP" and hp < bestHP) then
                        bestHP = hp; target = p
                    end
                end
            end
        end

        -- 2. ระบบการเคลื่อนที่
        if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
            local myChar = LocalPlayer.Character
            local myHuman = myChar and myChar:FindFirstChild("Humanoid")
            local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
            local tRoot = target.Character.HumanoidRootPart
            
            if myHuman and myRoot then
                rayParams.FilterDescendantsInstances = {myChar, target.Character}
                local dist = (myRoot.Position - tRoot.Position).Magnitude
                local moveDir = (tRoot.Position - myRoot.Position).Unit
                local isJumpable = canGameJump(myHuman)

                -- ตรวจจับการติด (Stuck Detection)
                if (myRoot.Position - lastPos).Magnitude < 0.3 and myHuman.MoveDirection.Magnitude > 0 then
                    stuckTime = stuckTime + 0.1
                else
                    stuckTime = 0
                end
                lastPos = myRoot.Position

                if dist > followDistance then
                    -- ** โหมดแก้ติด **
                    if stuckTime > 0.4 then
                        if isJumpable then myHuman.Jump = true end
                        local escape = getBestEscapeDir(myRoot, moveDir) or -moveDir
                        myHuman:MoveTo(myRoot.Position + (escape * 8))
                        task.wait(0.3) -- บังคับให้ไถลออกจากมุม
                        stuckTime = 0
                        continue
                    end

                    -- ** การเช็คสิ่งกีดขวาง (Raycasting) **
                    local rayFoot = workspace:Raycast(myRoot.Position + Vector3.new(0, -1.5, 0), moveDir * 5, rayParams)
                    local rayHead = workspace:Raycast(myRoot.Position + Vector3.new(0, 2, 0), moveDir * 5, rayParams)

                    if rayFoot then
                        -- ถ้าขาติดแต่หัวว่าง -> กระโดด
                        if isJumpable and not rayHead then
                            myHuman.Jump = true
                        end
                        -- ลองหักเลี้ยวด้วย
                        local bestDir = getBestEscapeDir(myRoot, moveDir)
                        if bestDir then
                            myHuman:MoveTo(myRoot.Position + (bestDir * 6))
                        end
                    else
                        -- ทางสะดวก เดินไปหาเป้าหมายปกติ
                        myHuman:MoveTo(tRoot.Position - (moveDir * followDistance))
                    end
                else
                    -- ถึงระยะแล้ว หยุดเดินและหันหน้าหาเป้าหมาย
                    myHuman:MoveTo(myRoot.Position)
                    local lookAtTarget = Vector3.new(tRoot.Position.X, myRoot.Position.Y, tRoot.Position.Z)
                    myRoot.CFrame = CFrame.lookAt(myRoot.Position, lookAtTarget)
                end
            end
        end
    end
end)
