local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
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
local randomTarget = nil 

-- --- DODGE SYSTEM VARIABLES (NEW) ---
local ProjectileHistory = {} -- เก็บตำแหน่งเก่าของกระสุน
local lastDodgeTime = 0
local DODGE_COOLDOWN = 0.25 -- หน่วงเวลาหลบกันสั่น
local MAX_HISTORY_SIZE = 10 -- จำกัดจำนวนประวัติกันเมมเต็ม

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local lastPosition = Vector3.new()
local lastMoveTick = os.clock()

-- --- UI Sections ---
local SupportSection = Tab:NewSection("Support Functions") 
local Section = Tab:NewSection("Interior & Building Navigation")
local MoveSection = Tab:NewSection("Navigation Control")

-- --- UI: Support Functions ---
SupportSection:NewToggle("Auto Collect Coins", "ดึงเงินจาก CoinStack อัตโนมัติ", function(state)
    autoCoinEnabled = state
end)

SupportSection:NewToggle("Smart Dodge V5", "หลบขอบวงเวทย์ & สไลด์กระสุน (Geometry Fix)", function(state)
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

local function isSafePosition(startPos, targetPos)
    rayParams.FilterDescendantsInstances = {LocalPlayer.Character}
    local dir = targetPos - startPos
    local wallHit = workspace:Raycast(startPos, dir, rayParams)
    if wallHit then return false end 
    local groundOrigin = targetPos + Vector3.new(0, 3, 0)
    local groundHit = workspace:Raycast(groundOrigin, Vector3.new(0, -10, 0), rayParams)
    if not groundHit then return false end 
    return true
end

local function findSafeDodge(startPos, baseDir, distance)
    local target = startPos + (baseDir * distance)
    if isSafePosition(startPos, target) then return target end
    
    local angles = {45, -45, 90, -90, 135, -135, 180}
    for _, angle in ipairs(angles) do
        local rotatedDir = CFrame.Angles(0, math.rad(angle), 0) * baseDir
        local testTarget = startPos + (rotatedDir * distance)
        if isSafePosition(startPos, testTarget) then
            return testTarget
        end
    end
    return startPos + (baseDir * (distance * 0.4))
end

-- --- [SMART DODGE V5 - FIXED CORE] ---
local function executeSmartDodgeV5(hazard)
    if not hazard or not hazard.Parent then return end
    
    local isAoE = hazard:IsA("Model")
    local isProjectile = (hazard.Name == "Arrow" or hazard.Name:match("Magic$") or hazard.Name:match("Projectile"))
    
    if not (isAoE or isProjectile) then return end

    local myChar = LocalPlayer.Character
    local myHuman = myChar and myChar:FindFirstChildOfClass("Humanoid")
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot or not myHuman then return end

    -- Cooldown Check: กันสั่น
    if tick() - lastDodgeTime < DODGE_COOLDOWN then return end

    local hazardPos = nil
    local hazardRadius = 2 
    
    if isAoE then
        local parts = {}
        for _, v in pairs(hazard:GetDescendants()) do
            if v:IsA("BasePart") then 
                table.insert(parts, v) 
                v.CanCollide = true
            end
        end
        
        if #parts > 0 then
            local centerPart = hazard.PrimaryPart or parts[1]
            hazardPos = centerPart.Position
            for _, p in pairs(parts) do
                local r = math.max(p.Size.X, p.Size.Z) / 2
                if r > hazardRadius then hazardRadius = r end
            end
        else
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

    -- [กรณีที่ 1] หลบวงเวทย์ (AoE)
    if isAoE then
        if distXZ < hazardRadius + 2 and distXZ < shieldRange then 
            local escapeDir = (myPosXZ - hazPosXZ)
            if escapeDir.Magnitude == 0 then escapeDir = Vector3.new(1, 0, 0) end
            escapeDir = escapeDir.Unit
            
            local distanceToMove = (hazardRadius + 1.5) - distXZ
            local safeTarget = findSafeDodge(myPos, escapeDir, math.max(distanceToMove, 4))
            
            if safeTarget then
                myHuman:MoveTo(safeTarget) -- ใช้ MoveTo แทน CFrame
                lastDodgeTime = tick()
            end
        end

    -- [กรณีที่ 2] หลบกระสุน (Projectile) - GEOMETRY & TIMING FIX
    elseif isProjectile then
        if distXZ > shieldRange then return end

        -- 1. หา Direction & Speed ที่แม่นยำ
        local pVel = hazard.Velocity
        local pSpeed = pVel.Magnitude
        local pDir = nil

        if pSpeed > 0.1 then
            pDir = pVel.Unit
        else
            -- Fallback: ใช้ประวัติตำแหน่ง
            local lastPos = ProjectileHistory[hazard]
            if lastPos then
                local moveVec = hazard.Position - lastPos
                if moveVec.Magnitude > 0.1 then
                    pDir = moveVec.Unit
                    pSpeed = moveVec.Magnitude / 0.033 
                end
            end
        end

        if not pDir then return end -- ไม่มีทิศทาง ไม่หลบมั่ว

        -- ✅ FIX 1: เช็คว่ากระสุนพุ่งเข้าหาเราจริงไหม?
        local toMe = (myPos - hazard.Position)
        if toMe:Dot(pDir) < -5 then return end -- วิ่งผ่านไปแล้ว

        -- ✅ FIX 2: กำหนด Ray Origin ให้ถูกต้อง (ถอยหลังไปสร้างเส้นยาว)
        local rayOrigin = hazard.Position - (pDir * 10) 
        
        -- คำนวณเวกเตอร์ตั้งฉาก
        local upVector = Vector3.new(0, 1, 0)
        local rightDir = pDir:Cross(upVector)
        if rightDir.Magnitude < 0.01 then rightDir = Vector3.new(1, 0, 0) else rightDir = rightDir.Unit end
        local leftDir = -rightDir

        local playerRadius = 3
        local projRadius = 2
        local safetyMargin = playerRadius + projRadius + 2 
        local triggerDist = 25 

        -- ✅ FIX 3: เช็คระยะจากตัวเราปัจจุบันไปยังเส้นวิถี
        local vecToPlayer = myPos - rayOrigin
        local projectionLen = vecToPlayer:Dot(pDir)
        local closestPointOnRay = rayOrigin + (pDir * math.max(0, projectionLen))
        local distToLineNow = (myPos - closestPointOnRay).Magnitude

        if distToLineNow > triggerDist then return end -- ไกลเกินไป ไม่ต้องหลบ

        -- ฟังก์ชันเช็คความปลอดภัย (รวม Hitbox)
        local function getSafetyScore(pos)
            local vecToPos = pos - rayOrigin
            local projLen = vecToPos:Dot(pDir)
            if projLen < -5 then return 1000 end 
            local closest = rayOrigin + (pDir * math.max(0, projLen))
            local dist = (pos - closest).Magnitude
            if dist < safetyMargin then return -1000 else return dist end
        end

        -- ✅ FIX 4: Path Check แบบง่าย
        local function isPathSafe(startPos, endPos)
            for i = 1, 3 do
                local t = i / 4
                local checkPos = startPos:Lerp(endPos, t)
                if getSafetyScore(checkPos) < 0 then return false end
            end
            return true
        end

        local candidates = {}
        local dodgeDist = 8
        local directions = {
            { vec = rightDir, name = "Right" },
            { vec = leftDir, name = "Left" },
            { vec = -pDir, name = "Back" },
            { vec = (rightDir - pDir).Unit, name = "BackRight" },
            { vec = (leftDir - pDir).Unit, name = "BackLeft" }
        }

        local bestTarget = nil
        local bestScore = -math.huge

        for _, data in ipairs(directions) do
            local targetPos = myPos + (data.vec * dodgeDist)
            if isSafePosition(myPos, targetPos) then
                if isPathSafe(myPos, targetPos) then
                    local score = getSafetyScore(targetPos)
                    if score > bestScore then
                        bestScore = score
                        bestTarget = targetPos
                    end
                end
            end
        end

        if not bestTarget then
            bestTarget = findSafeDodge(myPos, pDir, dodgeDist)
        end

        if bestTarget then
            myHuman:MoveTo(bestTarget)
            lastDodgeTime = tick()
        end
    end
end

-- --- AUTO COIN FUNCTION ---
local function collectNearestCoin()
    local myChar = LocalPlayer.Character
    if not myChar then return end
    local myRoot = myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return end

    local nearestCoin = nil
    local minDist = math.huge

    -- สแกนหา Coin ใน Workspace (ปรับชื่อตามเกมถ้าจำเป็น เช่น "Coin", "Money")
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj.Name:lower():find("coin") and obj:IsA("BasePart") then
            local d = (myRoot.Position - obj.Position).Magnitude
            if d < 50 and d < minDist then -- ระยะเก็บ 50
                minDist = d
                nearestCoin = obj
            end
        end
    end

    if nearestCoin then
        local myHuman = myChar:FindFirstChildOfClass("Humanoid")
        if myHuman then
            myHuman:MoveTo(nearestCoin.Position)
        end
    end
end

-- --- MAIN LOOP (UPDATED WITH DODGE SCAN & COIN) ---
task.spawn(function()
    while true do
        task.wait(0.05)
        
        pcall(function()
            local myChar = LocalPlayer.Character
            if not myChar then return end
            local myRoot = myChar:FindFirstChild("HumanoidRootPart")
            if not myRoot then return end

            -- 1. Update Projectile History (สำหรับคำนวณทิศทาง)
            if autoDodgeEnabled then
                for _, obj in ipairs(workspace:GetDescendants()) do
                    if obj:IsA("BasePart") and (obj.Name == "Arrow" or obj.Name:match("Magic$") or obj.Name:match("Projectile")) then
                        -- อัปเดตประวัติตำแหน่ง
                        ProjectileHistory[obj] = obj.Position
                        -- ล้างประวัติเก่าถ้าวัตถุหาย (ป้องกันเมมเต็ม ทำในอีกลูปแยกหรือทิ้งไว้ก่อนก็ได้เพราะ Roblox GC จัดการ)
                        
                        -- เรียกฟังก์ชันหลบ
                        executeSmartDodgeV5(obj)
                    end
                end
                
                -- ล้างประวัติกระสุนที่หายไปแล้ว (Optimization)
                for obj, _ in pairs(ProjectileHistory) do
                    if not obj.Parent then
                        ProjectileHistory[obj] = nil
                    end
                end
            end

            -- 2. Auto Coin
            if autoCoinEnabled then
                collectNearestCoin()
            end

            -- 3. Follow Logic (เดิม)
            if not followEnabled then continue end
            
            -- ... (โค้ดส่วน Follow เดิมที่อยู่ด้านล่างต่อจากนี้) ...
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

            local myHuman = myChar:FindFirstChildOfClass("Humanoid")
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
