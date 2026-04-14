local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("KONG GUISUS - EXPLORER", "DarkTheme")
local Tab = Window:NewTab("Main")
local Section = Tab:NewSection("Interior & Building Navigation")

-- --- Services ---
local Players = game.Players
local LocalPlayer = Players.LocalPlayer
local PathfindingService = game:GetService("PathfindingService")

-- --- Settings ---
local SelectedMode = "Manual"
local SelectedPlayerName = nil
local followDistance = 5
local followEnabled = false
local debugEnabled = false

local currentWaypoints = {}
local currentWaypointIndex = 1
local lastComputeTime = 0
local lastTargetPos = Vector3.new()
local isProbing = false
local isFollowingCustomPath = false 

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local lastPosition = Vector3.new()
local lastMoveTick = os.clock()
local randomTarget = nil 

_G.CustomPathFailTick = 0 

-- ==========================================
-- [ใหม่] ระบบความจำและสถานะลัดเลาะ (Spatial Memory)
-- ==========================================
local isTracingCeiling = false
local currentTraceTarget = nil
local BuildingTraceHistory = {} -- จำเส้นทางที่กำลังลัดเลาะ
local KnownStaircases = {} -- ความจำถาวร: จุดที่เคยเจอทางขึ้น {Vector3, Vector3, ...}

-- --- Debug Visualization ---
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

local function clearVisuals()
    for _, v in pairs(workspace.Terrain:GetChildren()) do
        if v.Name == "WP_Debug" or v.Name == "DirectTrace" or v.Name == "ProbeTrace" 
        or v.Name == "Debug_Edge" or v.Name == "Debug_TraceYellow" or v.Name == "Debug_TraceGreen" then 
            v:Destroy() 
        end
    end
end

-- วาดเสาความจำ (ทางขึ้นที่เคยค้นพบ)
local function drawMemoryWaypoints()
    if not debugEnabled then return end
    for i, stairPos in ipairs(KnownStaircases) do
        local name = "MemoryStair_"..i
        if not workspace.Terrain:FindFirstChild(name) then
            local p = Instance.new("Part")
            p.Name, p.Size, p.Position = name, Vector3.new(2, 20, 2), stairPos + Vector3.new(0, 10, 0)
            p.Anchored, p.CanCollide, p.CanQuery, p.Transparency = true, false, false, 0.5
            p.Color, p.Material = Color3.fromRGB(0, 255, 255), Enum.Material.Neon -- เสาสีฟ้าคราม
            p.Parent = workspace.Terrain
        end
    end
end

-- --- Helper Functions ---
local function forceJump(hum)
    if hum.FloorMaterial ~= Enum.Material.Air then
        hum.Jump = true
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end

local function hasHeadroom(pos)
    local checkRay = workspace:Raycast(pos + Vector3.new(0, 1, 0), Vector3.new(0, 6, 0), rayParams)
    return checkRay == nil 
end

local function checkCeilingAround(pos, height)
    local offsets = {Vector3.new(0,0,0), Vector3.new(3,0,0), Vector3.new(-3,0,0), Vector3.new(0,0,3), Vector3.new(0,0,-3)}
    for _, off in ipairs(offsets) do
        if workspace:Raycast(pos + off + Vector3.new(0, 1, 0), Vector3.new(0, height, 0), rayParams) then
            return true
        end
    end
    return false
end

-- หาระยะบันไดที่ใกล้ที่สุดจากความจำ
local function getNearestKnownStaircase(currentPos, targetPos)
    local bestStair = nil
    local bestDist = math.huge
    for _, stairPos in ipairs(KnownStaircases) do
        local distToStair = (currentPos - stairPos).Magnitude
        -- ถ้าบันไดอยู่ใกล้เราในระยะ 150 บล็อก และเป้าหมายอยู่สูงกว่า
        if distToStair < 150 and targetPos.Y > currentPos.Y + 4 then
            if distToStair < bestDist then
                bestDist = distToStair
                bestStair = stairPos
            end
        end
    end
    return bestStair
end

-- ยิงกากบาท หาจุดเริ่มต้นขอบ
local function findNearestCeilingEdgeCross(startPos, targetPos, maxCheckHeight)
    local step = 4
    local maxRadius = 50
    local edgesFound = {}
    local directions = {Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1)}

    for _, dir in ipairs(directions) do
        for d = step, maxRadius, step do
            local checkPos = startPos + (dir * d)
            if not workspace:Raycast(checkPos + Vector3.new(0, 1, 0), Vector3.new(0, maxCheckHeight, 0), rayParams) then
                table.insert(edgesFound, checkPos)
                break
            end
        end
    end

    local bestEdge, bestDist = nil, math.huge
    for _, edgePos in ipairs(edgesFound) do
        local score = (edgePos - targetPos).Magnitude
        if score < bestDist then bestDist = score; bestEdge = edgePos end
    end
    return bestEdge
end

-- คำนวณก้าวถัดไปสำหรับการลัดเลาะ
local function getNextEdgeTracingStep(currentPos, maxCheckHeight)
    local step = 4
    local neighbors = {Vector3.new(step, 0, 0), Vector3.new(-step, 0, 0), Vector3.new(0, 0, step), Vector3.new(0, 0, -step)}
    local validSteps = {}

    for _, offset in ipairs(neighbors) do
        local testPos = currentPos + offset
        
        -- ตรวจสอบว่าเคยเดินผ่านมาแล้วหรือยัง (เช็คประวัติ)
        local visited = false
        for _, vPos in ipairs(BuildingTraceHistory) do
            if (vPos - testPos).Magnitude < 1 then visited = true; break end
        end

        if not visited then
            -- ต้องเป็นช่องที่มองเห็นท้องฟ้า (ทางออก)
            if not workspace:Raycast(testPos + Vector3.new(0, 1, 0), Vector3.new(0, maxCheckHeight, 0), rayParams) then
                -- และต้องมีช่องข้างๆ ที่ติดเพดาน (เพื่อเป็นการเกาะขอบตึก)
                local touchesCeiling = false
                local ceilPos = nil
                for _, sideOff in ipairs(neighbors) do
                    local sidePos = testPos + sideOff
                    if workspace:Raycast(sidePos + Vector3.new(0, 1, 0), Vector3.new(0, maxCheckHeight, 0), rayParams) then
                        touchesCeiling = true
                        ceilPos = sidePos
                        break
                    end
                end

                if touchesCeiling then
                    table.insert(validSteps, {pos = testPos, ceil = ceilPos})
                end
            end
        end
    end

    -- ถ้ามีหลายทาง เลือกทางใดก็ได้เพื่อลัดเลาะต่อไป (ในที่นี้เลือกอันแรกที่เจอ)
    if #validSteps > 0 then return validSteps[1] end
    return nil
end

local function computeVerticalClimbPath(startPos, targetPos, myChar, tChar)
    local customWaypoints = {}
    local currentScanPos = startPos
    local heightToClimb = targetPos.Y - startPos.Y
    if heightToClimb < 3 then return customWaypoints end

    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {myChar, tChar, workspace.Terrain}
    local visited = {}
    
    for jump = 1, 20 do
        local bestNextPos, bestScore = nil, math.huge
        local searchCenter = currentScanPos + Vector3.new(0, 6, 0)
        local partsNearby = workspace:GetPartBoundsInRadius(searchCenter, 8, params)
        
        for _, part in ipairs(partsNearby) do
            if part:IsA("BasePart") and part.CanCollide and part.Transparency < 1 then
                local rayOrigin = part.Position + Vector3.new(0, (part.Size.Y/2) + 4, 0)
                local downRay = workspace:Raycast(rayOrigin, Vector3.new(0, -8, 0), rayParams)
                if downRay then
                    local hitPos = downRay.Position
                    local heightDiff = hitPos.Y - currentScanPos.Y
                    if heightDiff > 0.5 and heightDiff <= 8.0 and hasHeadroom(hitPos) then
                        local isVisited = false
                        for _, v in ipairs(visited) do if (v - hitPos).Magnitude < 2.5 then isVisited = true; break end end
                        if not isVisited then
                            local score = (Vector2.new(hitPos.X, hitPos.Z) - Vector2.new(targetPos.X, targetPos.Z)).Magnitude - (heightDiff * 12)
                            if score < bestScore then bestScore = score; bestNextPos = hitPos end
                        end
                    end
                end
            end
        end
        
        if not bestNextPos then
            local baseDir = (Vector3.new(targetPos.X, 0, targetPos.Z) - Vector3.new(currentScanPos.X, 0, currentScanPos.Z)).Unit
            if baseDir.Magnitude == baseDir.Magnitude then
                for _, angle in ipairs({0, 20, -20}) do
                    local dir = (CFrame.Angles(0, math.rad(angle), 0) * baseDir).Unit
                    local wallRay = workspace:Raycast(currentScanPos + Vector3.new(0, 2, 0), dir * 10, rayParams)
                    if wallRay and wallRay.Instance.CanCollide then
                        local climbPos = wallRay.Position + Vector3.new(0, 6, 0) + (wallRay.Normal * 1.5)
                        if hasHeadroom(climbPos) then
                            local isVisited = false
                            for _, v in ipairs(visited) do if (v - climbPos).Magnitude < 2.5 then isVisited = true; break end end
                            if not isVisited then bestNextPos = climbPos; break end
                        end
                    end
                end
            end
        end

        if bestNextPos then
            table.insert(customWaypoints, {Position = bestNextPos, Action = Enum.PathWaypointAction.Jump})
            table.insert(visited, bestNextPos)
            currentScanPos = bestNextPos
            if currentScanPos.Y >= targetPos.Y - 2 then
                table.insert(customWaypoints, {Position = targetPos, Action = Enum.PathWaypointAction.Walk})
                break
            end
        else break end
    end
    return customWaypoints
end

-- --- UI ---
Section:NewDropdown("Target Mode", "Mode", {"Manual", "Max HP", "Min HP", "Random"}, function(m) 
    SelectedMode = m 
    if m == "Random" then randomTarget = nil end 
end)

Section:NewTextBox("Search Player", "พิมพ์ชื่อ หรือ Display Name", function(txt)
    local lowerTxt = txt:lower()
    for _, p in pairs(Players:GetPlayers()) do 
        if p ~= LocalPlayer and (p.Name:lower():find(lowerTxt) or p.DisplayName:lower():find(lowerTxt)) then
            SelectedPlayerName = p.Name; SelectedMode = "Manual"; break
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

local MoveSection = Tab:NewSection("Navigation Control")
MoveSection:NewToggle("Enable Follow", "Start Logic", function(s) 
    followEnabled = s 
    if not s then 
        currentWaypoints = {}
        clearVisuals()
        isProbing = false
        isFollowingCustomPath = false 
        isTracingCeiling = false
        BuildingTraceHistory = {}
    end
end)
MoveSection:NewToggle("Show Path", "Visuals", function(s) debugEnabled = s end)
MoveSection:NewSlider("Distance", "Gap", 20, 1, function(s) followDistance = s end)

-- --- MAIN LOOP ---
task.spawn(function()
    while true do
        task.wait(0.05)
        if not followEnabled then continue end
        
        pcall(function()
            local target = nil
            if SelectedMode == "Manual" then target = Players:FindFirstChild(SelectedPlayerName or "")
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
                        if (SelectedMode == "Max HP" and hp > bestHP) or (SelectedMode == "Min HP" and hp < bestHP) then bestHP = hp; target = p end
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
                local vDist = targetPos.Y - currentPos.Y 
                
                rayParams.FilterDescendantsInstances = {myChar, target.Character}
                local isClimbingState = (myHuman:GetState() == Enum.HumanoidStateType.Climbing)

                drawMemoryWaypoints()

                -- เช็คติดแหง็ก
                if (currentPos - lastPosition).Magnitude < 0.5 then
                    if os.clock() - lastMoveTick > 1.5 then 
                        currentWaypoints = {} 
                        lastMoveTick = os.clock()
                        if isFollowingCustomPath or isTracingCeiling then
                            _G.CustomPathFailTick = os.clock() 
                            isFollowingCustomPath = false
                            isTracingCeiling = false
                        end
                    end
                else
                    lastPosition = currentPos
                    lastMoveTick = os.clock()
                end

                -- =======================================================
                -- [โหมดพิเศษ 1] ลัดเลาะขอบตึก (Edge Tracing Mode)
                -- *บล็อกโค้ดด้านล่างไม่ให้ทำงานเลยถ้าอยู่ในโหมดนี้*
                -- =======================================================
                if isTracingCeiling and currentTraceTarget then
                    local distToTarget = (currentPos - currentTraceTarget).Magnitude
                    
                    if distToTarget < 2 then
                        -- เดินมาถึงจุดเป้าหมาย (บล็อกเหลือง) แล้ว
                        table.insert(BuildingTraceHistory, currentTraceTarget)
                        
                        -- 1. เช็ค Loop: เราเดินวนกลับมาที่เดิมหรือเปล่า? (เช็คก้าวเก่าๆ ห่างไป 5 ก้าวขึ้นไป)
                        local isLoopClosed = false
                        for i = 1, #BuildingTraceHistory - 5 do
                            if (currentTraceTarget - BuildingTraceHistory[i]).Magnitude < 3 then
                                isLoopClosed = true; break
                            end
                        end

                        if isLoopClosed then
                            -- เดินครบลูปแล้วไม่เจอทางขึ้น เลิกหา
                            isTracingCeiling = false
                            BuildingTraceHistory = {}
                            _G.CustomPathFailTick = os.clock()
                            if debugEnabled then clearVisuals() end
                            return
                        end

                        -- 2. ลองสแกนหาทางปีนป่าย ณ จุดนี้ (ความจำถาวร)
                        if targetPos.Y > currentPos.Y + 4 and hasHeadroom(currentPos) then
                            local testClimb = computeVerticalClimbPath(currentPos, targetPos, myChar, target.Character)
                            if #testClimb > 0 then
                                -- เจอทางขึ้นแล้ว! บันทึกใส่สมอง!
                                table.insert(KnownStaircases, currentTraceTarget)
                                isTracingCeiling = false
                                BuildingTraceHistory = {}
                                
                                -- สั่งให้ปีนเลย
                                isFollowingCustomPath = true
                                currentWaypoints = testClimb
                                currentWaypointIndex = 1
                                if debugEnabled then clearVisuals() end
                                return
                            end
                        end

                        -- 3. หาจุดก้าวต่อไป (บล็อกเหลืองอันถัดไป)
                        local requiredHeightCheck = math.max(20, targetPos.Y - currentPos.Y + 5)
                        local nextTraceInfo = getNextEdgeTracingStep(currentTraceTarget, requiredHeightCheck)
                        
                        if nextTraceInfo then
                            currentTraceTarget = nextTraceInfo.pos
                            
                            -- วาดบล็อกเหลืองและเขียวอัปเดต
                            if debugEnabled then
                                clearVisuals()
                                local py = Instance.new("Part")
                                py.Name, py.Size, py.Position = "Debug_TraceYellow", Vector3.new(3.5, 0.5, 3.5), nextTraceInfo.pos + Vector3.new(0, 2, 0)
                                py.Anchored, py.CanCollide, py.CanQuery, py.Transparency = true, false, false, 0.2
                                py.Color, py.Material = Color3.fromRGB(255, 255, 0), Enum.Material.Neon
                                py.Parent = workspace.Terrain
                                
                                if nextTraceInfo.ceil then
                                    local pg = Instance.new("Part")
                                    pg.Name, pg.Size, pg.Position = "Debug_TraceGreen", Vector3.new(3.5, 0.5, 3.5), nextTraceInfo.ceil + Vector3.new(0, 2, 0)
                                    pg.Anchored, pg.CanCollide, pg.CanQuery, pg.Transparency = true, false, false, 0.5
                                    pg.Color, pg.Material = Color3.fromRGB(0, 255, 0), Enum.Material.Neon
                                    pg.Parent = workspace.Terrain
                                end
                            end
                        else
                            -- ตัน ไปต่อไม่ได้
                            isTracingCeiling = false
                            BuildingTraceHistory = {}
                            _G.CustomPathFailTick = os.clock()
                            if debugEnabled then clearVisuals() end
                        end
                    else
                        -- ยังเดินไม่ถึง ให้เดินต่อไป
                        myHuman:MoveTo(currentTraceTarget)
                        
                        -- กระโดดหลบหิน ถ้าย่ำอยู่กับที่นานเกิน 0.7 วิ
                        if os.clock() - lastMoveTick > 0.7 then
                            forceJump(myHuman)
                            lastMoveTick = os.clock()
                        end
                    end
                    return -- จบการทำงานของ Loop นี้ ไม่ให้โค้ดส่วนอื่นทำงานทับ
                end

                -- =======================================================
                -- เดินตาม Path ปกติ / ปีนป่าย
                -- =======================================================
                if isFollowingCustomPath and #currentWaypoints > 0 then
                    if (targetPos - lastTargetPos).Magnitude > 15 then
                        isFollowingCustomPath = false
                        currentWaypoints = {}
                    else
                        local wp = currentWaypoints[currentWaypointIndex]
                        if wp then
                            myHuman:MoveTo(wp.Position)
                            if wp.Action == Enum.PathWaypointAction.Jump then
                                if myHuman.FloorMaterial ~= Enum.Material.Air and not isClimbingState then forceJump(myHuman) end
                            end
                            local dist2D = (Vector2.new(currentPos.X, currentPos.Z) - Vector2.new(wp.Position.X, wp.Position.Z)).Magnitude
                            local distY = math.abs(currentPos.Y - wp.Position.Y)
                            if dist2D < 3.5 and distY < 4.5 then
                                currentWaypointIndex = currentWaypointIndex + 1
                                lastMoveTick = os.clock() 
                            end
                            return 
                        else
                            isFollowingCustomPath = false
                            currentWaypoints = {}
                        end
                    end
                end

                -- =======================================================
                -- โหมดตัดสินใจหลัก (เมื่อไม่ได้ถูกบังคับให้ทำอย่างอื่น)
                -- =======================================================
                if hDist > followDistance or math.abs(vDist) > 5 then
                    local moveDir = (targetPos - currentPos).Unit
                    local directRay = workspace:Raycast(currentPos, moveDir * trueDist, rayParams)
                    local headPos = currentPos + Vector3.new(0, 2.5, 0)
                    local targetHeadPos = targetPos + Vector3.new(0, 2.5, 0)
                    local headRay = workspace:Raycast(headPos, (targetHeadPos - headPos).Unit * trueDist, rayParams)
                    
                    local isSmartDrop = false
                    local shouldJumpDrop = false
                    local flatTargetPos = Vector3.new(targetPos.X, currentPos.Y, targetPos.Z)

                    if vDist < -4 then 
                        local flatDir = (flatTargetPos - currentPos).Unit
                        if flatDir.Magnitude == flatDir.Magnitude then
                            local hRayChest = workspace:Raycast(currentPos, flatDir * hDist, rayParams)
                            local hRayHead = workspace:Raycast(headPos, flatDir * hDist, rayParams)
                            if not hRayHead then
                                isSmartDrop = true
                                if hRayChest and hRayChest.Distance < 4 then shouldJumpDrop = true end
                            end
                        end
                    end

                    local canWalkStraight = (not directRay and not headRay) and (math.abs(vDist) < 5)

                    if isSmartDrop then
                        isProbing = false
                        currentWaypoints = {}
                        isFollowingCustomPath = false
                        updateDebug("DirectTrace", currentPos, flatTargetPos, Color3.fromRGB(255, 128, 0)) 
                        myHuman:MoveTo(flatTargetPos)
                        if shouldJumpDrop then forceJump(myHuman) end

                    elseif canWalkStraight then
                        isProbing = false
                        currentWaypoints = {}
                        updateDebug("DirectTrace", currentPos, targetPos, Color3.fromRGB(0, 255, 0))
                        myHuman:MoveTo(targetPos)
                    
                    else
                        if os.clock() - lastComputeTime > 0.5 or (targetPos - lastTargetPos).Magnitude > 5 then
                            currentWaypoints = {} 
                            isProbing = false
                            
                            local canUseCustomPaths = (_G.CustomPathFailTick == nil) or (os.clock() - _G.CustomPathFailTick > 4)

                            if targetPos.Y > currentPos.Y + 4 and canUseCustomPaths then
                                -- 1. ดึงความจำมาใช้ก่อน! มีบันไดที่เคยค้นพบใกล้ๆ ไหม?
                                local memoryStair = getNearestKnownStaircase(currentPos, targetPos)
                                
                                if memoryStair then
                                    -- วิ่งไปที่เสาแสงสีฟ้า (บันไดที่จำได้) เลย ไม่ต้องหาเพดานแล้ว
                                    local path = PathfindingService:CreatePath({AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = true})
                                    path:ComputeAsync(currentPos, memoryStair)
                                    if path.Status == Enum.PathStatus.Success then
                                        currentWaypoints = path:GetWaypoints()
                                        currentWaypointIndex = 2
                                        isFollowingCustomPath = true
                                        lastComputeTime = os.clock()
                                    else
                                        myHuman:MoveTo(memoryStair) -- พยายามเดินดิ่งไปถ้า Pathfinding พัง
                                    end
                                else
                                    -- 2. ถ้าไม่เคยจำได้ เช็คว่าติดเพดานไหม
                                    local requiredHeightCheck = math.max(20, targetPos.Y - currentPos.Y + 5)
                                    if checkCeilingAround(currentPos, requiredHeightCheck) then
                                        -- ติดเพดาน! เริ่มระบบกากบาทและลัดเลาะ
                                        local edgeStart = findNearestCeilingEdgeCross(currentPos, targetPos, requiredHeightCheck)
                                        if edgeStart then
                                            isTracingCeiling = true
                                            currentTraceTarget = edgeStart
                                            BuildingTraceHistory = {}
                                            lastComputeTime = os.clock()
                                        end
                                    else
                                        -- ไม่ติดเพดาน ลองปีนเลย
                                        currentWaypoints = computeVerticalClimbPath(currentPos, targetPos, myChar, target.Character)
                                        if #currentWaypoints > 0 then
                                            isFollowingCustomPath = true
                                            currentWaypointIndex = 1
                                            lastComputeTime = os.clock()
                                        end
                                    end
                                end
                            end
                            
                            -- ถ้าโหมดพิเศษทั้งหมดไม่ทำงาน ก็เดินอ้อมปกติ
                            if not isTracingCeiling and not isFollowingCustomPath then
                                local path = PathfindingService:CreatePath({AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = true})
                                path:ComputeAsync(currentPos, targetPos)
                                if path.Status == Enum.PathStatus.Success then
                                    currentWaypoints = path:GetWaypoints()
                                    currentWaypointIndex = 2
                                    lastComputeTime = os.clock()
                                    isFollowingCustomPath = false 
                                else
                                    isProbing = true
                                    currentWaypoints = {}
                                end
                            end
                        end
                        
                        -- โหมดงมทางมั่ว
                        if isProbing then
                            local baseDir = (targetPos - currentPos).Unit
                            local scanAngles = {0, 30, -30, 60, -60, 90, -90, 135, -135} 
                            local bestDir, maxDist = nil, 0
                            for _, angle in ipairs(scanAngles) do
                                local dir = (CFrame.Angles(0, math.rad(angle), 0) * Vector3.new(baseDir.X, 0, baseDir.Z)).Unit
                                local ray = workspace:Raycast(currentPos, dir * 15, rayParams)
                                local d = ray and ray.Distance or 15
                                if d > maxDist then maxDist = d; bestDir = dir end
                            end
                            if bestDir then
                                updateDebug("ProbeTrace", currentPos, currentPos + (bestDir * 5), Color3.fromRGB(255, 165, 0))
                                myHuman:MoveTo(currentPos + (bestDir * 8))
                                if workspace:Raycast(currentPos, bestDir * 4, rayParams) then forceJump(myHuman) end
                            end
                        end
                    end
                else
                    currentWaypoints = {}
                    myHuman:MoveTo(currentPos)
                end
            end
        end)
    end
end)
