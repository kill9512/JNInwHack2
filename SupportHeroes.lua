local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua "))()
local Window = Library.CreateLib("KONG GUISUS - EXPLORER", "DarkTheme")
local Tab = Window:NewTab("Main")

-- --- Services ---
local Players = game.Players
local LocalPlayer = Players.LocalPlayer
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

-- --- Settings Variables ---
local SelectedMode = "Manual"
local SelectedPlayerName = nil
local followDistance = 5
local followEnabled = false
local debugEnabled = false

local autoCoinEnabled = false 
local autoDodgeEnabled = false
local shieldRange = 100 

local currentWaypoints = {}
local currentWaypointIndex = 1
local lastComputeTime = 0
local lastTargetPos = Vector3.new()
local isProbing = false

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local lastPosition = Vector3.new()
local lastMoveTick = os.clock()
local randomTarget = nil 

-- --- UI Sections ---
local SupportSection = Tab:NewSection("Support Functions") 
local Section = Tab:NewSection("Interior & Building Navigation")
local MoveSection = Tab:NewSection("Navigation Control")

-- --- UI: Support Functions ---
SupportSection:NewToggle("Auto Collect Coins", "ดึงเงินจาก CoinStack อัตโนมัติ", function(state)
    autoCoinEnabled = state
end)

SupportSection:NewToggle("Smart Dodge V5", "หลบขอบวงเวทย์ & สไลด์กระสุน (พร้อมแก้ CanCollide)", function(state)
    autoDodgeEnabled = state
end)

SupportSection:NewSlider("Dodge Detect Range", "ระยะตรวจจับ (บล็อค)", 300, 20, function(s)
    shieldRange = s
end)

-- --- UI: Navigation Control ---
Section:NewDropdown("Target Mode", "Mode", {"Manual", "Max HP", "Min HP", "Random"}, function(m) 
    SelectedMode = m 
    if m == "Random" then randomTarget = nil end 
end)

Section:NewTextBox("Search Player", "พิมพ์ชื่อ หรือ Display Name", function(txt)
    local lowerTxt = txt:lower()
    for _, p in pairs(Players:GetPlayers()) do 
        if p ~= LocalPlayer and (p.Name:lower():find(lowerTxt) or p.DisplayName:lower():find(lowerTxt)) then
            SelectedPlayerName = p.Name
            SelectedMode = "Manual" 
            break
        end
    end
end)

local drop = Section:NewDropdown("Select Target", "User", {}, function(s) SelectedPlayerName = s:match("@([^%)]+)") end)

local function refreshList()
    local t = {"None (Off)"}
    for _, p in pairs(Players:GetPlayers()) do 
        if p ~= LocalPlayer then table.insert(t, p.DisplayName.." (@"..p.Name..")") end 
    end
    drop:Refresh(t)
end
Section:NewButton("Refresh List", "Update", refreshList)
refreshList()

MoveSection:NewToggle("Enable Follow", "Start Logic", function(s) 
    followEnabled = s 
    if not s then currentWaypoints = {}; clearVisuals(); isProbing = false end
end)
MoveSection:NewToggle("Show Path", "Visuals", function(s) debugEnabled = s end)
MoveSection:NewSlider("Distance", "Gap", 20, 1, function(s) followDistance = s end)

-- --- Helper Functions ---
local function clearVisuals()
    for _, v in pairs(workspace.Terrain:GetChildren()) do
        if v.Name == "WP_Debug" or v.Name == "DirectTrace" or v.Name == "ProbeTrace" then v:Destroy() end
    end
end

local function updateDebug(name, startPos, endPos, color)
    if not debugEnabled then 
        if workspace.Terrain:FindFirstChild(name) then workspace.Terrain[name]:Destroy() end
        return 
    end
    local line = workspace.Terrain:FindFirstChild(name) or Instance.new("LineHandleAdornment")
    line.Name, line.Thickness, line.Transparency = name, 3, 0.4
    line.Adornee, line.AlwaysOnTop = workspace.Terrain, true
    line.Color3, line.Length = color, (startPos - endPos).Magnitude
    line.CFrame, line.Parent = CFrame.lookAt(startPos, endPos), workspace.Terrain
end

local function forceJump(hum)
    if hum.FloorMaterial ~= Enum.Material.Air then
        hum.Jump = true
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end

local function getProbingDirection(myRoot, targetPos)
    local currentPos = myRoot.Position
    local baseDir = (targetPos - currentPos).Unit
    local scanAngles = {0, 30, -30, 60, -60, 90, -90, 135, -135} 
    local bestDir = nil; local maxDist = 0
    for _, angle in ipairs(scanAngles) do
        local dir = (CFrame.Angles(0, math.rad(angle), 0) * Vector3.new(baseDir.X, 0, baseDir.Z)).Unit
        local ray = workspace:Raycast(currentPos, dir * 15, rayParams)
        local d = ray and ray.Distance or 15
        if d > maxDist then maxDist = d; bestDir = dir end
    end
    return bestDir
end

-- --- ระบบสแกนหาจุดปลอดภัย (แก้บัคติดมุม) ---
local function isSafePosition(startPos, targetPos)
    rayParams.FilterDescendantsInstances = {LocalPlayer.Character}
    
    -- เช็คกำแพงขวางทาง
    local dir = targetPos - startPos
    local wallHit = workspace:Raycast(startPos, dir, rayParams)
    if wallHit then return false end 

    -- เช็คเหว (ยิงเลเซอร์ลงพื้น)
    local groundOrigin = targetPos + Vector3.new(0, 3, 0)
    local groundHit = workspace:Raycast(groundOrigin, Vector3.new(0, -10, 0), rayParams)
    if not groundHit then return false end 

    return true
end

-- [ใหม่] ถัาทางหลักติดกำแพง ให้หมุนหาทางออกรอบตัว 360 องศา
local function findSafeDodge(startPos, baseDir, distance)
    -- ลองทางหลักก่อน
    local target = startPos + (baseDir * distance)
    if isSafePosition(startPos, target) then return target end
    
    -- ถ้าติดกำแพง ลองกวาดมุม 45, 90, 135, 180 องศา ทั้งซ้ายขวา
    local angles = {45, -45, 90, -90, 135, -135, 180}
    for _, angle in ipairs(angles) do
        local rotatedDir = CFrame.Angles(0, math.rad(angle), 0) * baseDir
        local testTarget = startPos + (rotatedDir * distance)
        if isSafePosition(startPos, testTarget) then
            return testTarget
        end
    end
    
    -- ถ้าติดทุกทางจริงๆ (โดนขังขอบแมพ) ยอมขยับไปทางหลักนิดนึงก็ยังดี
    return startPos + (baseDir * (distance * 0.4))
end

-- --- [ระบบอัปเดต V5] โคตรแม่นยำ ---
local function executeSmartDodgeV5(hazard)
    if not hazard or not hazard.Parent then return end
    
    local isAoE = hazard:IsA("Model")
    local isProjectile = (hazard.Name == "Arrow" or hazard.Name:match("Magic$"))
    
    if not (isAoE or isProjectile) then return end

    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return end

    local hazardPos = nil
    local hazardRadius = 2 
    
    -- [แก้ 1: วัดขนาดจาก Part ข้างใน Model แทน BoundingBox]
    if isAoE then
        local parts = {}
        for _, v in pairs(hazard:GetDescendants()) do
            if v:IsA("BasePart") then 
                table.insert(parts, v) 
                -- *** แก้ไขตรงนี้: บังคับเปิด CanCollide ให้ทุก Part ที่เจอใน Model ของ Effects ***
                v.CanCollide = true
                v.CollisionGroup = "Default"
            end
        end
        
        if #parts > 0 then
            -- ใช้จุดศูนย์กลางของชิ้นแรกหรือชิ้นหลัก
            local centerPart = hazard.PrimaryPart or parts[1]
            hazardPos = centerPart.Position
            
            -- หาชิ้นที่ใหญ่ที่สุดใน Model เพื่อกำหนดรัศมีวงเวทย์
            for _, p in pairs(parts) do
                local r = math.max(p.Size.X, p.Size.Z) / 2
                if r > hazardRadius then hazardRadius = r end
            end
        else
            -- ถ้ามันว่างเปล่าจริงๆ ค่อยใช้ BoundingBox กางเกงใน
            local cframe, size = hazard:GetBoundingBox()
            hazardPos = cframe.Position
            hazardRadius = math.max(size.X, size.Z) / 2
        end
    elseif hazard:IsA("BasePart") then
        hazardPos = hazard.Position
        hazardRadius = math.max(hazard.Size.X, hazard.Size.Z) / 2
    end

    if not hazardPos then return end
    
    local myPos = myRoot.Position
    local myPosXZ = Vector3.new(myPos.X, 0, myPos.Z)
    local hazPosXZ = Vector3.new(hazardPos.X, 0, hazardPos.Z)
    local distXZ = (myPosXZ - hazPosXZ).Magnitude

    if distXZ > shieldRange then return end

    -- [กรณีที่ 1] หลบวงเวทย์ (Model ทุกชนิด)
    if isAoE then
        -- ถ้าเราอยู่ในวง (บวกระยะเผื่อ 1.5 บล็อค เพื่อให้หลุดขอบชัวร์ๆ)
        if distXZ < hazardRadius + 2 then 
            local escapeDir = (myPosXZ - hazPosXZ)
            if escapeDir.Magnitude == 0 then escapeDir = Vector3.new(1, 0, 0) end
            escapeDir = escapeDir.Unit
            
            -- คำนวณระยะที่ต้องก้าวออกไปให้พ้นขอบพอดีเป๊ะ
            local distanceToMove = (hazardRadius + 1.5) - distXZ
            
            -- ใช้ฟังก์ชันดิ้นรน 360 องศา เผื่อติดมุม
            local safeTarget = findSafeDodge(myPos, escapeDir, distanceToMove)
            if safeTarget then
                myRoot.CFrame = CFrame.new(safeTarget)
            end
        end


    -- [กรณีที่ 2] หลบกระสุนพุ่งชน (Arrow, Magic, Skill Shot) - V6 Stable
    elseif isProjectile then
        -- 1. ดึงข้อมูล Velocity จริง (แก้เรื่อง Scale และ Delay)
        local projVel = hazard.Velocity
        local projSpeed = projVel.Magnitude
        
        -- ถ้ากระสุนหยุดนิ่งหรือความเร็วต่ำมาก ให้ข้ามไปก่อน (กัน Error)
        if projSpeed < 1 then return end 

        local pDir = projVel.Unit
        
        -- ป้องกัน Vector พัง (NaN) กรณีพุ่งขึ้นฟ้าหรือลงดินตรงๆ
        if pDir.Y > 0.99 or pDir.Y < -0.99 then
            pDir = Vector3.new(1, 0, 0) -- Fallback direction
        end

        -- 2. ระยะกระตุ้น (Trigger Distance) - แก้ Jitter
        -- ถ้ากระสุนยังไกลเกินไป ไม่ต้องหลบ
        local triggerDist = 20 
        if distXZ > triggerDist then return end

        -- 3. ค่าคงที่ Hitbox (แก้เรื่องชนทั้งที่ดูเหมือนรอด)
        local playerRadius = 3  -- รัศมีตัวเรา (เผื่อ Safety)
        local projRadius = 2    -- รัศมีกระสุนโดยประมาณ
        local requiredMargin = playerRadius + projRadius + 2 -- +2 เผื่อ误差
        
        -- 4. คำนวณเวกเตอร์ตั้งฉาก (Side Vector) ครั้งเดียว
        local upVector = Vector3.new(0, 1, 0)
        local rightDir = pDir:Cross(upVector).Unit
        local leftDir = -rightDir
        local backDir = -pDir
        
        -- 5. ฟังก์ชันคำนวณคะแนนความปลอดภัย (Scoring Function)
        -- คืนค่า: คะแนน (ยิ่งสูงยิ่งดี), จุดปลายทาง
        local function getSafetyScore(targetPos)
            local vecToTarget = targetPos - hazard.Position
            
            -- Projection: หาจุดที่ใกล้ที่สุดบน "รังสี" (Ray) ของกระสุน
            local projectionLen = vecToTarget:Dot(pDir)
            
            -- intereset เฉพาะด้านหน้ากระสุน (Ray) ถ้าติดลบแปลว่าอยู่ด้านหลังแหล่งกำเนิด (ปลอดภัยจากหัวกระสุน)
            if projectionLen < 0 then 
                return 1000 -- ปลอดภัยมาก (อยู่หลังคนยิง)
            end
            
            -- หาจุดบนเส้น射线 ที่ใกล้จุดเป้าหมายที่สุด
            local closestPointOnRay = hazard.Position + (pDir * projectionLen)
            local distToLine = (targetPos - closestPointOnRay).Magnitude
            
            -- คะแนนมาจากระยะห่างจากเส้นวิถี
            -- ถ้า distToLine > requiredMargin = รอด
            -- ยิ่งห่างมาก คะแนนยิ่งสูง
            if distToLine < requiredMargin then
                return -1 -- อันตราย ตัดทิ้ง
            end
            
            return distToLine -- คืนค่าระยะห่างเป็นคะแนน
        end

        -- 6. สร้าง Candidate Points (Relative to Projectile Direction)
        local dodgeDist = 8 -- ระยะหลบมาตรฐาน
        local candidates = {
            { name = "Right", pos = myPos + (rightDir * dodgeDist) },
            { name = "Left",  pos = myPos + (leftDir * dodgeDist) },
            { name = "Back",  pos = myPos + (backDir * dodgeDist) },
            { name = "FwdRight", pos = myPos + ((pDir + rightDir).Unit * dodgeDist) },
            { name = "FwdLeft",  pos = myPos + ((pDir + leftDir).Unit * dodgeDist) },
        }

        local bestCandidate = nil
        local bestScore = -math.huge

        -- 7. วนลูปหาจุดที่ดีที่สุด (Multi-Projectile Ready Structure)
        -- หมายเหตุ: ในลูปนี้เราเช็คทีละจุด แต่ฟังก์ชัน getSafetyScore สามารถขยายให้วนลูปเช็คทุก projectile ได้ในอนาคต
        for _, cand in ipairs(candidates) do
            -- เช็คพื้นฐาน: จุดนั้นเดินไปถึงได้ไหม (ไม่ติดกำแพง)
            if isSafePosition(myPos, cand.pos) then
                local score = getSafetyScore(cand.pos)
                
                if score > bestScore then
                    bestScore = score
                    bestCandidate = cand.pos
                end
            end
        end

        -- 8. Fallback: ถ้าทุกจุดที่วางแผนไว้ไม่ดีพอ (เช่น อยู่ในมุมอับ)
        if not bestCandidate or bestScore < 0 then
            -- ใช้ระบบสุ่มมุมละเอียด (Continuous Search) หรือ 360 Dodge
            -- ส่ง pDir ไปเพื่อให้ findSafeDodge รู้ว่าต้องหนีแนวไหน
            bestCandidate = findSafeDodge(myPos, pDir, dodgeDist)
        end

        -- 9. สั่งเคลื่อนที่
        if bestCandidate then
            myRoot.CFrame = CFrame.new(bestCandidate)
        end
    end
    
-- --- SUPPORT LOOPS ---
task.spawn(function()
    while true do
        task.wait(0.1)
        if autoCoinEnabled then
            pcall(function()
                local myChar = LocalPlayer.Character
                local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
                if myRoot then
                    local dungeon = workspace:FindFirstChild("Dungeon")
                    local treasure = dungeon and dungeon:FindFirstChild("Treasure")
                    if treasure then
                        for _, item in pairs(treasure:GetChildren()) do
                            if item.Name == "CoinStack" or item.Name == "TreasureChest" then
                                if item:IsA("BasePart") then
                                    item.CanCollide = false
                                    item.CFrame = myRoot.CFrame
                                elseif item:IsA("Model") then
                                    item:PivotTo(myRoot.CFrame)
                                    for _, part in pairs(item:GetDescendants()) do
                                        if part:IsA("BasePart") then
                                            part.CanCollide = false
                                            if part:FindFirstChild("TouchInterest") then
                                                part.CFrame = myRoot.CFrame
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end)
        end
    end
end)

-- Loop สแกนแบบ Stepped (รันก่อนฟิสิกส์ชนกัน)
-- ส่วนนี้จะเรียก executeSmartDodgeV5 ซึ่งข้างในมีการแก้ CanCollide แล้ว
RunService.Stepped:Connect(function()
    if autoDodgeEnabled then
        pcall(function()
            local dungeon = workspace:FindFirstChild("Dungeon")
            local effects = dungeon and dungeon:FindFirstChild("Effects")
            if effects then
                for _, v in pairs(effects:GetChildren()) do
                    executeSmartDodgeV5(v)
                end
            end
        end)
    end
end)

-- แยก GetNil Instances ออกมารันช้าๆ ลดแลค
task.spawn(function()
    while true do
        task.wait(0.5) 
        if autoDodgeEnabled then
            pcall(function()
                if getnilinstances then
                    for _, v in pairs(getnilinstances()) do
                        executeSmartDodgeV5(v)
                    end
                end
            end)
        end
    end
end)

-- --- MAIN FOLLOW LOOP ---
task.spawn(function()
    while true do
        task.wait(0.05)
        if not followEnabled then continue end
        
        pcall(function()
            local target = nil
            if SelectedMode == "Manual" then
                target = Players:FindFirstChild(SelectedPlayerName or "")
            elseif SelectedMode == "Random" then
                if not randomTarget or not randomTarget.Parent or not randomTarget.Character or not randomTarget.Character:FindFirstChild("Humanoid") or randomTarget.Character.Humanoid.Health <= 0 then
                    local validPlayers = {}
                    for _, p in pairs(Players:GetPlayers()) do
                        if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("Humanoid") and p.Character.Humanoid.Health > 0 then
                            table.insert(validPlayers, p)
                        end
                    end
                    if #validPlayers > 0 then randomTarget = validPlayers[math.random(1, #validPlayers)] end
                end
                target = randomTarget
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

            if not target or not target.Character or not target.Character:FindFirstChild("HumanoidRootPart") then return end

            local myChar = LocalPlayer.Character
            local myHuman = myChar:FindFirstChildOfClass("Humanoid")
            local myRoot = myChar:FindFirstChild("HumanoidRootPart")
            local tRoot = target.Character.HumanoidRootPart
            
            if myHuman and myRoot then
                local currentPos = myRoot.Position
                local targetPos = tRoot.Position
                local trueDist = (targetPos - currentPos).Magnitude
                local hDist = (Vector3.new(targetPos.X, 0, targetPos.Z) - Vector3.new(currentPos.X, 0, currentPos.Z)).Magnitude
                local vDist = math.abs(targetPos.Y - currentPos.Y)
                
                rayParams.FilterDescendantsInstances = {myChar, target.Character}

                if (currentPos - lastPosition).Magnitude < 0.5 then
                    if os.clock() - lastMoveTick > 0.7 then currentWaypoints = {}; lastMoveTick = os.clock() end
                else
                    lastPosition = currentPos; lastMoveTick = os.clock()
                end

                if hDist > followDistance or vDist > 5 then
                    local moveDir = (targetPos - currentPos).Unit
                    local directRay = workspace:Raycast(currentPos, moveDir * trueDist, rayParams)
                    local headPos = currentPos + Vector3.new(0, 2.5, 0)
                    local targetHeadPos = targetPos + Vector3.new(0, 2.5, 0)
                    local headRay = workspace:Raycast(headPos, (targetHeadPos - headPos).Unit * trueDist, rayParams)

                    local isParkour = false
                    if hDist < 14 and (targetPos.Y > currentPos.Y - 2) and vDist < 8 then
                        if directRay and not headRay then isParkour = true
                        elseif not directRay and vDist >= 5 then isParkour = true end
                    end

                    if (not directRay and vDist < 5) or isParkour then
                        isProbing = false; currentWaypoints = {}
                        updateDebug("DirectTrace", currentPos, targetPos, isParkour and Color3.fromRGB(255, 255, 0) or Color3.fromRGB(0, 255, 0))
                        myHuman:MoveTo(targetPos)
                        if isParkour then
                            if directRay then
                                local distToWall = (directRay.Position - currentPos).Magnitude
                                if distToWall < 3.5 then forceJump(myHuman) end
                            else
                                if hDist < 4 then forceJump(myHuman) end
                            end
                        end
                    else
                        if os.clock() - lastComputeTime > 0.5 or (targetPos - lastTargetPos).Magnitude > 5 then
                            local path = PathfindingService:CreatePath({AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 3})
                            path:ComputeAsync(currentPos, targetPos)
                            if path.Status == Enum.PathStatus.Success then
                                isProbing = false; currentWaypoints = path:GetWaypoints(); currentWaypointIndex = 2
                                lastTargetPos = targetPos; lastComputeTime = os.clock()
                            else
                                isProbing = true; currentWaypoints = {}
                            end
                        end

                        if isProbing then
                            local probeDir = getProbingDirection(myRoot, targetPos)
                            if probeDir then
                                updateDebug("ProbeTrace", currentPos, currentPos + (probeDir * 5), Color3.fromRGB(255, 165, 0))
                                myHuman:MoveTo(currentPos + (probeDir * 8))
                                local wallCheck = workspace:Raycast(currentPos, probeDir * 4, rayParams)
                                if wallCheck then forceJump(myHuman) end
                            end
                        elseif #currentWaypoints > 0 then
                            local lookAheadIndex = currentWaypointIndex
                            local maxLookAhead = math.min(currentWaypointIndex + 6, #currentWaypoints) 
                            for i = maxLookAhead, currentWaypointIndex + 1, -1 do
                                local testWp = currentWaypoints[i]
                                local isHeightSafe = true
                                for j = currentWaypointIndex, i do
                                    if math.abs(currentWaypoints[j].Position.Y - currentPos.Y) > 1.5 then isHeightSafe = false; break end
                                end
                                if isHeightSafe then
                                    local hasJump = false
                                    for j = currentWaypointIndex, i do
                                        if currentWaypoints[j].Action == Enum.PathWaypointAction.Jump then hasJump = true; break end
                                    end
                                    if not hasJump then
                                        local hit = workspace:Raycast(currentPos + Vector3.new(0, 2, 0), (testWp.Position + Vector3.new(0, 2, 0)) - (currentPos + Vector3.new(0, 2, 0)), rayParams)
                                        if not hit then lookAheadIndex = i; break end
                                    end
                                end
                            end
                            currentWaypointIndex = lookAheadIndex
                            local wp = currentWaypoints[currentWaypointIndex]
                            if wp then
                                if math.abs(currentPos.Y - wp.Position.Y) > 6 then currentWaypoints = {}; return end
                                local isClimbing = myHuman:GetState() == Enum.HumanoidStateType.Climbing
                                local isGoingUp = (wp.Position.Y > currentPos.Y + 2.5) 
                                if isGoingUp and not isClimbing then
                                    local flatDir = (Vector3.new(wp.Position.X, 0, wp.Position.Z) - Vector3.new(currentPos.X, 0, currentPos.Z))
                                    if flatDir.Magnitude > 0.1 then myHuman:MoveTo(wp.Position + (flatDir.Unit * 1.5)) 
                                    else myHuman:MoveTo(wp.Position) end
                                else
                                    myHuman:MoveTo(wp.Position)
                                end
                                local dist2D = (Vector2.new(currentPos.X, currentPos.Z) - Vector2.new(wp.Position.X, wp.Position.Z)).Magnitude
                                local distY = math.abs(currentPos.Y - wp.Position.Y)
                                if isClimbing then
                                    if currentPos.Y >= wp.Position.Y - 1 or (dist2D < 5 and distY < 3.5) then currentWaypointIndex = currentWaypointIndex + 1 end
                                else
                                    if dist2D < 4.5 and distY < 3.5 then currentWaypointIndex = currentWaypointIndex + 1 end
                                end
                                if not isClimbing and (wp.Action == Enum.PathWaypointAction.Jump or (isGoingUp and dist2D < 2)) then forceJump(myHuman) end
                            end
                        end
                        updateDebug("DirectTrace", currentPos, directRay and directRay.Position or targetPos, Color3.fromRGB(255, 0, 0))
                    end
                else
                    currentWaypoints = {}; myHuman:MoveTo(currentPos)
                end
            end
        end)
    end
end)
