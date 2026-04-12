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

-- --- ฟังก์ชันวิเคราะห์ทาง 180 องศา ---
local function findBestPath(myRoot, moveDir)
    local scanAngles = {-90, -60, -30, 0, 30, 60, 90}
    local bestDir = nil
    local bestScore = -1

    for _, angle in ipairs(scanAngles) do
        local rotatedDir = (CFrame.Angles(0, math.rad(angle), 0) * Vector3.new(moveDir.X, 0, moveDir.Z)).Unit
        local score = 0
        
        -- เช็คความสูง 3 ระดับ
        local footHit = workspace:Raycast(myRoot.Position + Vector3.new(0, -1.8, 0), rotatedDir * 8, rayParams) -- ระดับพื้น
        local kneeHit = workspace:Raycast(myRoot.Position + Vector3.new(0, -0.5, 0), rotatedDir * 8, rayParams) -- ระดับเข่า
        local headHit = workspace:Raycast(myRoot.Position + Vector3.new(0, 2.5, 0), rotatedDir * 8, rayParams) -- ระดับหัว

        if not footHit and not kneeHit then
            score = 10 
        elseif (footHit or kneeHit) and not headHit then
            score = 7 -- เป็นบันไดหรือของเตี้ย (ชอบทิศนี้)
        elseif headHit then
            score = 1 -- กำแพงสูง
        end

        local dist = (kneeHit and kneeHit.Distance) or 8
        score = score + dist

        if score > bestScore then
            bestScore = score
            bestDir = rotatedDir
        end
    end
    return bestDir
end

-- --- UI Setup (เหมือนเดิม) ---
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
                
                -- เช็คว่าเกมนี้กระโดดได้ไหม
                local canJump = (myHuman.JumpPower > 0 or myHuman.JumpHeight > 0)

                -- เช็คการติดนิ่ง
                if (myRoot.Position - lastPos).Magnitude < 0.4 and myHuman.MoveDirection.Magnitude > 0 then
                    stuckTime = stuckTime + 0.1
                else
                    stuckTime = 0
                end
                lastPos = myRoot.Position

                if dist > followDistance then
                    -- ** ระบบกระโดดฉุกเฉินเมื่อติดมุม **
                    if stuckTime > 0.4 and canJump then
                        myHuman.Jump = true
                    end

                    -- ** ระบบล็อกการตัดสินใจ (เลี่ยงกำแพง) **
                    if detourTimer > 0 then
                        detourTimer = detourTimer - 0.1
                        if lockedDir then
                            myHuman:MoveTo(myRoot.Position + (lockedDir * 5))
                            
                            -- เช็คดักหน้าขณะเลี่ยง: ถ้าเจอของเตี้ยให้โดดเรื่อยๆ
                            local obstCheck = workspace:Raycast(myRoot.Position + Vector3.new(0, -0.5, 0), lockedDir * 3, rayParams)
                            local headCheck = workspace:Raycast(myRoot.Position + Vector3.new(0, 2.5, 0), lockedDir * 3, rayParams)
                            if obstCheck and not headCheck and canJump then
                                myHuman.Jump = true
                            end
                        end
                        continue
                    end

                    -- ตรวจสอบสิ่งกีดขวางข้างหน้า (ใช้ 2 ระดับ: เอว และ หัว)
                    local midHit = workspace:Raycast(myRoot.Position + Vector3.new(0, -0.5, 0), moveDir * 4, rayParams)
                    local headHit = workspace:Raycast(myRoot.Position + Vector3.new(0, 2.5, 0), moveDir * 4, rayParams)

                    if stuckTime > 0.3 or midHit then
                        -- ถ้าเจอของขวางระดับเอว แต่หัวว่าง = บันได/กล่อง -> ให้กระโดด
                        if midHit and not headHit and canJump then
                            myHuman.Jump = true
                        end
                        
                        -- เริ่มสแกนหาทางอ้อม
                        local best = findBestPath(myRoot, moveDir)
                        if best then
                            lockedDir = best
                            detourTimer = 1.0 
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
