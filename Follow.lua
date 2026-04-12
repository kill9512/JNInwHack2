local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("KONG GUISUS", "DarkTheme")
local Tab = Window:NewTab("Main")
local Section = Tab:NewSection("Smart Follow Player")

-- --- Services ---
local Players = game.Players
local LocalPlayer = Players.LocalPlayer

-- --- Variables ---
local SelectedMode = "Manual"
local SelectedPlayerName = nil
local followDistance = 5
local followEnabled = false

local lastPos = Vector3.new(0,0,0)
local stuckTime = 0
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- --- ฟังก์ชันวิเคราะห์ทางเบี่ยงที่ฉลาดที่สุด ---
local function getBestEscapeDir(myRoot, moveDir)
    -- แสกนมุมต่างๆ เพื่อหาทางที่ "โล่ง" ที่สุด
    local scanAngles = {30, -30, 60, -60, 90, -90}
    local bestDir = nil
    local maxFreeDist = 0

    for _, angle in ipairs(scanAngles) do
        local rotatedDir = (CFrame.Angles(0, math.rad(angle), 0) * Vector3.new(moveDir.X, 0, moveDir.Z)).Unit
        local result = workspace:Raycast(myRoot.Position, rotatedDir * 8, rayParams)
        
        local freeDist = result and result.Distance or 8
        if freeDist > maxFreeDist then
            maxFreeDist = freeDist
            bestDir = rotatedDir
        end
    end
    return bestDir
end

-- --- UI Setup ---
Section:NewDropdown("Target Mode", "Mode", {"Manual", "Max HP", "Min HP"}, function(m) SelectedMode = m end)
local drop = Section:NewDropdown("Select Player", "Select Target", {}, function(s) 
    SelectedPlayerName = s:match("@([^%)]+)") 
end)

local function refresh()
    local t = {"None (Off)"}
    for _, p in pairs(Players:GetPlayers()) do 
        if p ~= LocalPlayer then table.insert(t, p.DisplayName.." (@"..p.Name..")") end 
    end
    drop:Refresh(t)
end
Section:NewButton("Refresh Players", "Update List", refresh)
refresh()

local MoveSection = Tab:NewSection("Movement Control")
MoveSection:NewToggle("Enable Follow", "Start Movement", function(state) followEnabled = state end)
MoveSection:NewSlider("Distance", "Follow Gap", 20, 1, function(s) followDistance = s end)

-- --- LOGIC CORE ---
task.spawn(function()
    while task.wait(0.1) do
        if not followEnabled then continue end
        
        local target = nil
        if SelectedMode == "Manual" then
            target = Players:FindFirstChild(SelectedPlayerName or "")
        else
            -- Logic ค้นหาตาม HP (ข้ามเพื่อความกระชับ)
            local bestHP = (SelectedMode == "Max HP") and -1 or math.huge
            for _, p in pairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("Humanoid") then
                    local hp = p.Character.Humanoid.Health
                    if (SelectedMode == "Max HP" and hp > bestHP) or (SelectedMode == "Min HP" and hp < bestHP) then
                        bestHP = hp; target = p
                    end
                end
            end
        end

        if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
            local myChar = LocalPlayer.Character
            local myHuman = myChar and myChar:FindFirstChild("Humanoid")
            local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
            local tRoot = target.Character.HumanoidRootPart
            
            if myHuman and myRoot then
                rayParams.FilterDescendantsInstances = {myChar, target.Character}
                local dist = (myRoot.Position - tRoot.Position).Magnitude
                local moveDir = (tRoot.Position - myRoot.Position).Unit

                -- ระบบตรวจจับการติด (Stuck Detection)
                if (myRoot.Position - lastPos).Magnitude < 0.4 and myHuman.MoveDirection.Magnitude > 0 then
                    stuckTime = stuckTime + 0.1
                else
                    stuckTime = 0
                end
                lastPos = myRoot.Position

                if dist > followDistance then
                    -- ** logic แก้ติด: ถ้าหยุดนิ่งเกิน 0.3 วิ ให้ลองกระโดดและเบี่ยงทันที **
                    if stuckTime > 0.3 then
                        myHuman.Jump = true
                        local escape = getBestEscapeDir(myRoot, moveDir) or -moveDir
                        myHuman:MoveTo(myRoot.Position + (escape * 7)) 
                        task.wait(0.2) -- บังคับให้ไถลออกข้าง
                        stuckTime = 0
                        continue
                    end

                    -- ยิง Ray เช็คสิ่งกีดขวางล่วงหน้า
                    local lowHit = workspace:Raycast(myRoot.Position + Vector3.new(0, -1.2, 0), moveDir * 5, rayParams)
                    local midHit = workspace:Raycast(myRoot.Position + Vector3.new(0, 0.5, 0), moveDir * 5, rayParams)
                    local highHit = workspace:Raycast(myRoot.Position + Vector3.new(0, 2.5, 0), moveDir * 5, rayParams)

                    if lowHit or midHit then
                        -- เจอของขวาง: ลองกระโดดถ้าข้างบนว่าง
                        if not highHit then
                            myHuman.Jump = true
                        end
                        
                        -- หาทางเบี่ยงที่ "โล่ง" ที่สุดแทนการเดินชนตรงๆ
                        local bestDir = getBestEscapeDir(myRoot, moveDir)
                        if bestDir then
                            myHuman:MoveTo(myRoot.Position + (bestDir * 6))
                        end
                    else
                        -- ทางสะดวก เดินไปหาเป้าหมายปกติ
                        myHuman:MoveTo(tRoot.Position - (moveDir * followDistance))
                    end
                else
                    -- ถึงระยะแล้ว
                    myHuman:MoveTo(myRoot.Position)
                    myRoot.CFrame = CFrame.lookAt(myRoot.Position, Vector3.new(tRoot.Position.X, myRoot.Position.Y, tRoot.Position.Z))
                end
            end
        end
    end
end)
