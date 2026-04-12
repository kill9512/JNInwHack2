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
local detourTarget = nil -- พิกัดเป้าหมายชั่วคราวเพื่อหลบกำแพง
local detourTimer = 0
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- --- ฟังก์ชันวิเคราะห์ทางหลบที่ฉลาดที่สุด ---
local function getBestDetourPoint(myRoot, moveDir)
    -- แสกนมุมกว้างขึ้นเพื่อหา "ช่องว่าง" ไม่ใช่แค่ทางที่ไกลที่สุด
    local scanAngles = {60, -60, 90, -90, 120, -120}
    local bestPoint = nil
    local maxDist = 0

    for _, angle in ipairs(scanAngles) do
        local rotatedDir = (CFrame.Angles(0, math.rad(angle), 0) * Vector3.new(moveDir.X, 0, moveDir.Z)).Unit
        local result = workspace:Raycast(myRoot.Position, rotatedDir * 12, rayParams)
        
        local currentDist = result and result.Distance or 12
        if currentDist > maxDist then
            maxDist = currentDist
            bestPoint = myRoot.Position + (rotatedDir * 10) -- สร้างจุดเป้าหมายห่างออกไป 10 Studs
        end
    end
    return bestPoint
end

-- --- UI Setup ---
Section:NewDropdown("Target Mode", "Mode", {"Manual", "Max HP", "Min HP"}, function(m) SelectedMode = m end)
local drop = Section:NewDropdown("Select Target", "Select Player", {}, function(s) 
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
                local canJump = (myHuman.JumpPower > 0 or myHuman.JumpHeight > 0)

                -- 1. ระบบเช็คการติด (Stuck Detection)
                if (myRoot.Position - lastPos).Magnitude < 0.5 and myHuman.MoveDirection.Magnitude > 0 then
                    stuckTime = stuckTime + 0.1
                else
                    stuckTime = 0
                end
                lastPos = myRoot.Position

                -- 2. ระบบจัดการทิศทาง (Decision Logic)
                if dist > followDistance then
                    -- เช็คว่ากำลังอยู่ในโหมด "เดินเลี่ยงกำแพง" หรือไม่
                    if detourTarget and detourTimer > 0 then
                        detourTimer = detourTimer - 0.1
                        myHuman:MoveTo(detourTarget)
                        if stuckTime > 0.2 and canJump then myHuman.Jump = true end
                        
                        -- ถ้าถึงจุดเลี่ยงแล้ว หรือติดหนัก ให้เลิกเลี่ยงเพื่อคำนวณใหม่
                        if (myRoot.Position - detourTarget).Magnitude < 2 or stuckTime > 0.6 then
                            detourTarget = nil
                            detourTimer = 0
                        end
                        continue
                    end

                    -- เช็คสิ่งกีดขวางข้างหน้า (Low, Mid, High)
                    local lowHit = workspace:Raycast(myRoot.Position + Vector3.new(0,-1.2,0), moveDir * 6, rayParams)
                    local midHit = workspace:Raycast(myRoot.Position, moveDir * 6, rayParams)
                    local highHit = workspace:Raycast(myRoot.Position + Vector3.new(0,2.5,0), moveDir * 6, rayParams)

                    if stuckTime > 0.4 or lowHit or midHit then
                        -- ** ตรวจพบสิ่งกีดขวาง: เข้าโหมดเดินเลี่ยง **
                        local newPoint = getBestDetourPoint(myRoot, moveDir)
                        if newPoint then
                            detourTarget = newPoint
                            detourTimer = 1.5 -- บังคับเดินเลี่ยง 1.5 วินาที
                            if canJump and not highHit then myHuman.Jump = true end
                            myHuman:MoveTo(detourTarget)
                        end
                    else
                        -- ทางสะดวก: เดินตรงไป
                        myHuman:MoveTo(tRoot.Position)
                    end
                else
                    -- ถึงระยะแล้ว: หยุดและหันหน้า
                    detourTarget = nil
                    myHuman:MoveTo(myRoot.Position)
                    myRoot.CFrame = CFrame.lookAt(myRoot.Position, Vector3.new(tRoot.Position.X, myRoot.Position.Y, tRoot.Position.Z))
                end
            end
        end
    end
end)
