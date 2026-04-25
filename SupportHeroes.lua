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


    -- [กรณีที่ 2] หลบกระสุนพุ่งชน (Ultimate V6: Raycast, Timing, Hitbox, Hysteresis)
    elseif isProjectile then
        -- === 1. Configuration & Constants ===
        local REACTION_DELAY = 0.15 -- ชดเชย Latency + Animation Start (Fix #4)
        local PLAYER_RADIUS = 2.5   -- ขนาด Hitbox ผู้เล่นโดยประมาณ (Fix #3)
        local PROJ_RADIUS = 1.5     -- ขนาด Hitbox กระสุนโดยประมาณ (Fix #3)
        local SAFE_MARGIN = 1.0     -- ระยะกันชนเพิ่มเติม
        
        -- === 2. หาทิศทางกระสุนจริง (รองรับ Curved/Homing) (Fix #5) ===
        local currentPos = hazard.Position
        local lastPos = ProjectileHistory[hazard] or currentPos
        ProjectileHistory[hazard] = currentPos -- อัปเดตตำแหน่งล่าสุด
        
        local moveVec = currentPos - lastPos
        local projSpeed = moveVec.Magnitude
        
        -- ถ้ากระสุนอยู่นิ่งหรือเพิ่งเกิด ให้ใช้ Velocity ของวัตถุแทน (เผื่อกรณีเฟรมแรก)
        if projSpeed < 0.1 and hazard.Velocity then
            moveVec = hazard.Velocity
            projSpeed = moveVec.Magnitude
        end

        local pDir = nil
        if projSpeed > 0.1 then
            pDir = moveVec.Unit
        else
            -- ถ้าไม่มีข้อมูลทิศทางเลย (เกิดใหม่กึก) -> อย่าเดาทิศทาง ให้ข้ามไปใช้โหมด 360 ทันที
            pDir = nil 
        end

        -- === 3. Hysteresis System (ป้องกัน Jitter) (Fix #7) ===
        local now = tick()
        local shouldReevaluate = (not lastDodgeCommit) or (now - lastDodgeCommitTime > 0.3)
        
        -- ถ้ายังอยู่ในช่วง Commit และทิศทางเดิมยังปลอดภัย ไม่ต้องคำนวณใหม่
        if not shouldReevaluate and lastDodgeCommit then
            -- ตรวจสอบว่าจุดปลายทางของ Commit ยังปลอดภัยอยู่ไหม (อย่างเร็ว)
            -- ถ้าปลอดภัย ให้เดินต่อ ไม่ต้องหาทางใหม่
            -- (สามารถเพิ่ม logic เช็คความปลอดภัยอย่างด่วนที่นี่ได้)
            -- แต่เพื่อความปลอดภัยสูงสุด เราจะยังเช็ค Threat อยู่เสมอ แต่จะ Prioritize ทิศเดิม
        end

        -- === 4. เตรียมเวกเตอร์ตั้งฉาก (ป้องกัน NaN) (Fix #3 เดิม) ===
        local upVector = Vector3.new(0, 1, 0)
        local rightBase = Vector3.new(1, 0, 0) -- Default fallback
        
        if pDir then
            -- เช็คกรณี pDir ชนกับ upVector (ขนานกัน) ซึ่งจะทำให้ Cross ได้ 0
            if math.abs(pDir:Dot(upVector)) > 0.99 then
                rightBase = Vector3.new(0, 0, 1) -- เปลี่ยนแกนอ้างอิงถ้าพุ่งขึ้น/ลงตรงๆ
            end
            rightBase = pDir:Cross(upVector).Unit
        end
        
        local leftBase = -rightBase

        -- === 5. ฟังก์ชันตรวจสอบความปลอดภัยขั้นสูง (Core Logic) ===
        local function getThreatLevel(targetPos, projectileData)
            local pHaz = projectileData.pos
            local pVelocity = projectileData.dir
            local pSpeed = projectileData.speed
            
            if not pVelocity then return 0 end -- ไม่มีทิศ = ยังประเมินยาก (ถือว่าปลอดภัยชั่วคราว หรือให้ 360 จัดการ)

            -- 5.1 คำนวณเวกเตอร์จากหัวกระสุนไปยังจุดเป้าหมาย
            local vecToTarget = targetPos - pHaz
            
            -- 5.2 Projection (หาความยาวบนเส้นวิถี) -> Fix #1 (Ray vs Line)
            local projectionLen = vecToTarget:Dot(pVelocity)
            
            -- ถ้า projectionLen < 0 แปลว่าจุดอยู่ "ด้านหลัง" หัวกระสุน (ปลอดภัยจากหัว แต่อาจโดนหางถ้ามันยาวมาก)
            -- แต่เราจะสนใจเฉพาะช่วงที่กระสุน "กำลังจะวิ่งไปถึง"
            -- Clamp ให้สนใจเฉพาะช่วงข้างหน้า (0 ถึง อนันต์) หรืออาจจะบวกเผื่อความยาวหางกระสุนนิดหน่อย
            if projectionLen < -5 then return 0 end -- หลังมากเกินไป ไม่สน

            -- 5.3 หาจุดที่ใกล้ที่สุดบนเส้นวิถี (Closest Point on Ray)
            local closestPoint = pHaz + (pVelocity * projectionLen)
            
            -- 5.4 วัดระยะห่างจริง (Perpendicular Distance)
            local distToLine = (targetPos - closestPoint).Magnitude
            
            -- 5.5 คำนวณเวลา (Timing Check) -> Fix #2 (Real Velocity & Delay)
            -- เวลาที่กระสุนจะไปถึงจุดตัด (Closest Point)
            -- ระวัง: ถ้า projectionLen ติดลบ กระสุนวิ่งออกจากจุดนี้แล้ว
            local timeForProj = 0
            if projectionLen > 0 then
                timeForProj = (projectionLen / pSpeed) - REACTION_DELAY
            else
                timeForProj = -1 -- ผ่านไปแล้ว
            end

            -- เวลาที่ผู้เล่นจะเดินไปถึงจุดเป้าหมาย (targetPos)
            -- ใช้ Velocity จริงของผู้เล่น ถ้าหยุดนิ่งให้สมมติว่าเริ่มเดิน
            local playerVel = myRoot.Velocity.Magnitude
            local distToWalk = (targetPos - myPos).Magnitude
            local timeForPlayer = 0
            
            if playerVel > 0.1 then
                timeForPlayer = distToWalk / playerVel
            else
                -- ถ้าผู้เล่นหยุดนิ่ง การหลบคือการเริ่มเคลื่อนที่ สมมติความเร็วเริ่มต้น
                timeForPlayer = distToWalk / 16 -- ความเร็วเดินปกติ
            end

            -- 5.6 ตรวจสอบการชน (Collision Check with Hitbox) -> Fix #3
            -- ต้องรวมรัศมีผู้เล่น + รัศมีกระสุน + ส่วนปลอดภัย
            local requiredMargin = PLAYER_RADIUS + PROJ_RADIUS + SAFE_MARGIN
            
            -- เงื่อนไขอันตราย:
            -- 1. ระยะห่างน้อยกว่าขอบเขตปลอดภัย
            -- 2. กระสุนกำลังจะมาถึง (timeForProj > 0)
            -- 3. เวลาใกล้เคียงกัน (Time Collision Window)
            --    เราต้องไปถึงก่อน หรือ กระสุนผ่านไปก่อน ไม่งั้นชน
            local timeDiff = math.abs(timeForPlayer - timeForProj)
            local isTimingCollision = (timeForProj > 0) and (timeDiff < 0.2) -- ช่องว่างเวลา 0.2 วิ ถือว่าเสี่ยง

            if distToLine < requiredMargin and isTimingCollision then
                return 1 -- อันตราย
            end
            
            return 0 -- ปลอดภัย
        end

        -- === 6. รวบรวมกระสุนทั้งหมดในระยะ (Multi-Projectile) -> Fix #8 ===
        local activeProjectiles = {}
        -- สมมติว่ามีฟังก์ชันหากระสุนรอบๆ หรือใช้จาก Loop หลักที่ส่ง hazard มา
        -- ในที่นี้เราจะสมมติว่าเราเช็ค 'hazard' ตัวปัจจุบัน และควรจะมีตารางเก็บตัวอื่นด้วย
        -- เพื่อให้โค้ดทำงานได้ในบริบทนี้ เราจะใส่ hazard ปัจจุบันเข้าไปก่อน
        if pDir then
            table.insert(activeProjectiles, { pos = hazard.Position, dir = pDir, speed = projSpeed })
        end
        
        -- *หมายเหตุ*: ในโค้ดจริง คุณควรวลูปหา projectiles อื่นๆ ในระยะ 15-20 บล็อค แล้วใส่เข้า activeProjectiles ด้วย
        -- ตัวอย่าง: for _, other in ipairs(NearbyProjectiles) do ... end

        -- ถ้าไม่มีกระสุนที่มีทิศทางชัดเจน ให้ใช้โหมดค้นหา 360 องศาทันที
        if #activeProjectiles == 0 then
             local safeTarget = findSafeDodge(myPos, nil, 8) -- ส่ง nil เพื่อบอกว่าไม่มีทิศอ้างอิง
             if safeTarget then myRoot.CFrame = CFrame.new(safeTarget) end
             return
        end

        -- === 7. ค้นหาจุดปลอดภัยที่ดีที่สุด (Continuous Search) -> Fix #6 ===
        local bestTarget = nil
        local bestScore = -math.huge
        
        -- กำหนดชุดมุมที่จะทดสอบ
        -- ปกติ: 8 ทิศทางหลัก
        -- กรณีฉุกเฉิน (ไม่เจอจุดปลอดภัย): สุ่มเพิ่มหรือละเอียดขึ้น
        local anglesToTest = {}
        local baseAngles = {0, 45, 90, 135, 180, 225, 270, 315}
        
        -- สร้างเวกเตอร์จากมุม
        for _, angle in ipairs(baseAngles) do
            local rad = math.rad(angle)
            -- หมุนเวกเตอร์ขวาฐาน ตามมุมที่ต้องการ
            -- สูตรหมุนเวกเตอร์ในระนาบ XZ
            local cosA = math.cos(rad)
            local sinA = math.sin(rad)
            -- เวกเตอร์ฐานคือขวา (1,0,0) เทียบกับทิศกระสุน? ไม่ เอาเทียบกับโลกแล้วค่อยหมุนตามทิศกระสุนจะยุ่ง
            -- ง่ายสุด: สร้างเวกเตอร์จากทิศกระสุนแล้วหมุน
            -- หรือ ง่ายๆ คือสร้างเวกเตอร์จากโลก แล้วเช็ค
            
            -- วิธีที่เสถียร: ใช้ทิศกระสุนเป็นฐาน 0 องศา แล้วหมุนรอบมัน
            -- แต่เพื่อความครอบคลุมทุกทิศทางในโลก (กรณีกระสุนมาจากทุกทาง)
            -- เราควรสร้างจุดรอบตัวเราแบบวงกลม
            
            local dirX = math.cos(rad)
            local dirZ = math.sin(rad)
            table.insert(anglesToTest, Vector3.new(dirX, 0, dirZ))
        end

        -- เพิ่มการสุ่มมุมเล็กๆ น้อยๆ ถ้าต้องการความละเอียด (Optional)
        -- for i=1, 4 do local r = math.random() * math.pi * 2 ... end

        local dodgeDist = 8 -- ระยะมาตรฐาน
        
        for _, dir in ipairs(anglesToTest) do
            local candidatePos = myPos + (dir * dodgeDist)
            
            -- เช็คสิ่งกีดขวางพื้นฐาน (กำแพง)
            if isSafePosition(myPos, candidatePos) then
                local totalThreat = 0
                
                -- เช็คกับกระสุนทุกลูก (Fix #8)
                local isSafeFromAll = true
                for _, proj in ipairs(activeProjectiles) do
                    if getThreatLevel(candidatePos, proj) > 0 then
                        isSafeFromAll = false
                        break -- เจออันเดียวก็พอ ไม่ปลอดภัย
                    end
                end
                
                if isSafeFromAll then
                    -- ระบบให้คะแนน
                    -- 1. ชอบจุดที่อยู่ "ด้านข้าง" หรือ "ด้านหลัง" กระสุนมากกว่าด้านหน้า
                    -- 2. ชอบจุดที่ใกล้ที่สุด (ประหยัดแรง)
                    
                    local score = 100
                    
                    -- Bonus: ถ้าเป็นทิศทางเดียวกับที่ Commit ไว้ (ลด Jitter)
                    if lastDodgeCommit and (candidatePos - lastDodgeCommit).Magnitude < 2 then
                        score = score + 50
                    end
                    
                    -- Penalty: ถ้ามุมนี้หันหน้าเข้าหากระสุนเยอะเกินไป (เสี่ยงสวน)
                    -- (สามารถเพิ่ม logic นี้ได้ถ้าจำเป็น)

                    if score > bestScore then
                        bestScore = score
                        bestTarget = candidatePos
                    end
                end
            end
        end

        -- === 8. Fallback: Continuous Search (ถ้า 8 มุมไม่รอด) ===
        if not bestTarget then
            -- ลองขยายระยะ หรือ สุ่มมุมเพิ่ม
            -- หรือเรียกใช้ findSafeDodge แบบ 360 องศาเต็มรูปแบบ
            bestTarget = findSafeDodge(myPos, pDir, dodgeDist * 1.5)
        end

        -- === 9. Execute Move & Commit ===
        if bestTarget then
            myRoot.CFrame = CFrame.new(bestTarget)
            
            -- Commit ทิศทางนี้ชั่วคราว (Hysteresis)
            lastDodgeCommit = bestTarget
            lastDodgeCommitTime = now
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
