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

-- --- ฟังก์ชันวิเคราะห์ทางเดิน (Smart Side Scan) ---
local function getBestEscapeDir(myRoot, moveDir)
    -- ยิง Ray 2 เส้นเพื่อเปรียบเทียบ ซ้าย 45 และ ขวา 45 องศา
    local leftDir = (CFrame.Angles(0, math.rad(45), 0) * moveDir).Unit
    local rightDir = (CFrame.Angles(0, math.rad(-45), 0) * moveDir).Unit
    
    local leftHit = workspace:Raycast(myRoot.Position, leftDir * 7, rayParams)
    local rightHit = workspace:Raycast(myRoot.Position, rightDir * 7, rayParams)
    
    -- ถ้าฝั่งไหนว่างให้ไปฝั่งนั้น
    if not leftHit then return leftDir end
    if not rightHit then return rightDir end
    
    -- ถ้าติดทั้งคู่ ให้ดูว่าอันไหน "ไกลกว่า" (มีพื้นที่มากกว่า)
    if (leftHit.Distance > rightHit.Distance) then
        return leftDir
    else
        return rightDir
    end
end

-- --- UI Elements (เหมือนเดิมแต่ปรับแก้ Dropdown เล็กน้อย) ---
Section:NewDropdown("Target Mode", "Mode", {"Manual", "Max HP", "Min HP"}, function(m) SelectedMode = m end)
local drop = Section:NewDropdown("Select Player", "Select", {}, function(s) 
    SelectedPlayerName = s:match("@([^%)]+)") 
end)

local function refresh()
    local t = {"None (Off)"}
    for _, p in pairs(Players:GetPlayers()) do if p ~= LocalPlayer then table.insert(t, p.DisplayName.." (@"..p.Name..")") end end
    drop:Refresh(t)
end
Section:NewButton("Refresh Players", "Update", refresh)
refresh()

local MoveSection = Tab:NewSection("Movement Control")
MoveSection:NewToggle("Enable Follow", "Start", function(state) followEnabled = state end)
MoveSection:NewSlider("Distance", "Gap", 20, 1, function(s) followDistance = s end)

-- --- LOGIC CORE ---
task.spawn(function()
    while task.wait(0.1) do
        if not followEnabled then continue end
        
        local target = nil
        if SelectedMode == "Manual" then
            target = Players:FindFirstChild(SelectedPlayerName or "")
        else
            -- [Logic หา HP สูง/ต่ำ เหมือนเดิม]
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

                -- ตรวจจับการติด (Stuck Detection)
                if (myRoot.Position - lastPos).Magnitude < 0.3 and myHuman.MoveDirection.Magnitude > 0 then
                    stuckTime = stuckTime + 0.1
                else
                    stuckTime = 0
                end
                lastPos = myRoot.Position

                if dist > followDistance then
                    -- 1. ถ้าติด (Stuck) ให้ "พุ่งตัวและกระโดด" (Panic Mode)
                    if stuckTime > 0.4 then
                        myHuman.Jump = true
                        local escape = getBestEscapeDir(myRoot, moveDir) or -moveDir
                        myHuman:MoveTo(myRoot.Position + (escape * 8)) -- พุ่งไปทิศที่ว่าง
                        task.wait(0.2) -- บังคับให้พุ่งออกไปก่อน
                        stuckTime = 0
                        continue
                    end

                    -- 2. ยิง Ray เช็คระดับต่างๆ
                    local lowHit = workspace:Raycast(myRoot.Position + Vector3.new(0, -1, 0), moveDir * 5, rayParams)
                    local midHit = workspace:Raycast(myRoot.Position + Vector3.new(0, 1, 0), moveDir * 5, rayParams)
                    local highHit = workspace:Raycast(myRoot.Position + Vector3.new(0, 3, 0), moveDir * 5, rayParams)

                    if lowHit then
                        -- ถ้าเจอของขวางเตี้ยๆ ให้กระโดดอัดเข้าไปเลย
                        if not highHit then
                            myHuman.Jump = true
                        end
                        
                        -- หาทางเบี่ยงที่ฉลาดขึ้น
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
