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
local detourTimer = 0
local lockedDir = nil
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- --- ฟังก์ชันวิเคราะห์ทาง 180 องศา (7 Rays Scan) ---
local function findBestPath(myRoot, moveDir)
    local scanAngles = {-90, -60, -30, 0, 30, 60, 90} -- 180 องศา ทุกๆ 30 องศา
    local bestDir = nil
    local bestScore = -1

    for _, angle in ipairs(scanAngles) do
        local rotatedDir = (CFrame.Angles(0, math.rad(angle), 0) * Vector3.new(moveDir.X, 0, moveDir.Z)).Unit
        local score = 0
        
        -- เช็ค 3 ระดับความสูง
        local footHit = workspace:Raycast(myRoot.Position + Vector3.new(0, -1.5, 0), rotatedDir * 8, rayParams)
        local kneeHit = workspace:Raycast(myRoot.Position, rotatedDir * 8, rayParams)
        local headHit = workspace:Raycast(myRoot.Position + Vector3.new(0, 2.5, 0), rotatedDir * 8, rayParams)

        if not footHit and not kneeHit then
            score = 10 -- ทางโล่งมาก
        elseif footHit and not headHit then
            score = 5 -- มีของเตี้ย/บันได (กระโดดได้)
        elseif footHit and headHit then
            score = 1 -- กำแพงสูง (อ้อมเท่านั้น)
        end

        -- เพิ่มคะแนนตามระยะทางที่ว่าง
        local dist = (footHit and footHit.Distance) or 8
        score = score + dist

        if score > bestScore then
            bestScore = score
            bestDir = rotatedDir
        end
    end
    return bestDir
end

-- --- UI Setup ---
Section:NewDropdown("Target Mode", "Mode", {"Manual", "Max HP", "Min HP"}, function(m) SelectedMode = m end)
local drop = Section:NewDropdown("Select Player", "Target", {}, function(s) 
    SelectedPlayerName = s:match("@([^%)]+)") 
end)

local function refresh()
    local t = {"None (Off)"}
    for _, p in pairs(Players:GetPlayers()) do 
        if p ~= LocalPlayer then table.insert(t, p.DisplayName.." (@"..p.Name..")") end 
    end
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
            -- [Logic หา HP สูง/ต่ำ]
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

                -- เช็คการติดนิ่ง
                if (myRoot.Position - lastPos).Magnitude < 0.4 and myHuman.MoveDirection.Magnitude > 0 then
                    stuckTime = stuckTime + 0.1
                else
                    stuckTime = 0
                end
                lastPos = myRoot.Position

                if dist > followDistance then
                    -- ** ระบบล็อกการตัดสินใจ (ป้องกันการส่าย) **
                    if detourTimer > 0 then
                        detourTimer = detourTimer - 0.1
                        if lockedDir then
                            myHuman:MoveTo(myRoot.Position + (lockedDir * 5))
                            -- ลองกระโดดตรวจสอบทาง
                            local headCheck = workspace:Raycast(myRoot.Position + Vector3.new(0, 2.5, 0), lockedDir * 3, rayParams)
                            if canJump and not headCheck then myHuman.Jump = true end
                        end
                        continue
                    end

                    -- ตรวจสอบสิ่งกีดขวางข้างหน้าตรงๆ
                    local frontHit = workspace:Raycast(myRoot.Position, moveDir * 5, rayParams)
                    local headHit = workspace:Raycast(myRoot.Position + Vector3.new(0, 2.5, 0), moveDir * 5, rayParams)

                    if stuckTime > 0.3 or frontHit then
                        -- ** เริ่มการสแกนเรดาร์ 180 องศา **
                        local best = findBestPath(myRoot, moveDir)
                        if best then
                            lockedDir = best
                            detourTimer = 1.0 -- ล็อกทิศทางไว้ 1 วินาที
                            if canJump and not headHit then myHuman.Jump = true end
                            myHuman:MoveTo(myRoot.Position + (lockedDir * 5))
                        end
                    else
                        -- ทางสะดวก เดินไปหาเป้าหมาย
                        myHuman:MoveTo(tRoot.Position)
                    end
                else
                    -- ถึงระยะที่กำหนด
                    myHuman:MoveTo(myRoot.Position)
                    myRoot.CFrame = CFrame.lookAt(myRoot.Position, Vector3.new(tRoot.Position.X, myRoot.Position.Y, tRoot.Position.Z))
                end
            end
        end
    end
end)
