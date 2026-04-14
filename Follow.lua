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

-- [ใหม่] ระบบความจำตึกและลัดเลาะ
local isEscapingCeiling = false
local currentEscapeTarget = nil
_G.TraceVisited = {} -- จดจำบล็อกเหลืองที่เคยเดิน
_G.MapMemory = _G.MapMemory or {} -- สมองส่วนลึก: จำพิกัดบันได/ทางขึ้นถาวร

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

local function drawMemoryWaypoints()
    if not debugEnabled then
        for _, v in pairs(workspace.Terrain:GetChildren()) do
            if v.Name == "Debug_MemoryPillar" then v:Destroy() end
        end
        return
    end
    -- วาดเสาแสงสีฟ้าตรงจุดที่เคยจำว่าขึ้นตึกได้
    for _, memoryPos in ipairs(_G.MapMemory) do
        local pName = "Debug_MemoryPillar_"..tostring(memoryPos)
        if not workspace.Terrain:FindFirstChild(pName) then
            local p = Instance.new("Part")
            p.Name = "Debug_MemoryPillar"
            p.Size = Vector3.new(1.5, 15, 1.5)
            p.Position = memoryPos + Vector3.new(0, 7.5, 0)
            p.Anchored, p.CanCollide, p.CanQuery, p.Transparency = true, false, false, 0.3
            p.Color, p.Material = Color3.fromRGB(0, 150, 255), Enum.Material.Neon
            p.Parent = workspace.Terrain
        end
    end
end

local function clearVisuals()
    for _, v in pairs(workspace.Terrain:GetChildren()) do
        if v.Name == "WP_Debug" or v.Name == "DirectTrace" or v.Name == "ProbeTrace" 
        or v.Name == "Debug_Edge" or v.Name == "Debug_TraceYellow" or v.Name == "Debug_TraceGreen" then 
            v:Destroy() 
        end
    end
    drawMemoryWaypoints()
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

local function getProbingDirection(myRoot, targetPos)
    local currentPos = myRoot.Position
    local baseDir = (targetPos - currentPos).Unit
    local scanAngles = {0, 30, -30, 60, -60, 90, -90, 135, -135} 
    local bestDir = nil
    local maxDist = 0
    for _, angle in ipairs(scanAngles) do
        local dir = (CFrame.Angles(0, math.rad(angle), 0) * Vector3.new(baseDir.X, 0, baseDir.Z)).Unit
        local ray = workspace:Raycast(currentPos, dir * 15, rayParams)
        local d = ray and ray.Distance or 15
        if d > maxDist then maxDist = d; bestDir = dir end
    end
    return bestDir
end

local function computeVerticalClimbPath(startPos, targetPos, myChar, tChar)
    local customWaypoints = {}
    local heightToClimb = targetPos.Y - startPos.Y
    if heightToClimb < 3 then return customWaypoints end

    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {myChar, tChar, workspace.Terrain}

    local currentScanPos = startPos
    local visited = {}
    
    for jump = 1, 20 do
        local bestNextPos = nil
        local bestScore = math.huge
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
                        for _, v in ipairs(visited) do
                            if (v - hitPos).Magnitude < 2.5 then isVisited = true; break end
                        end
                        if not isVisited then
                            local dist2D = (Vector2.new(hitPos.X, hitPos.Z) - Vector2.new(targetPos.X, targetPos.Z)).Magnitude
                            local score = dist2D - (heightDiff * 12)
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
                            for _, v in ipairs(visited) do
                                if (v - climbPos).Magnitude < 2.5 then isVisited = true; break end
                            end
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
        else
            break
        end
    end
    return customWaypoints
end

-- หาระยะขอบแรกสุด (Cross Scan)
local function findNearestCeilingEdgeCross(startPos, targetPos, maxCheckHeight)
    local step = 4
    local bestEdge = nil
    local bestDist = math.huge
    local edgesFound = {}
    local directions = {Vector3.new(1,0,0), Vector3.new(-1,0,0), Vector3.new(0,0,1), Vector3.new(0,0,-1)}

    for _, dir in ipairs(directions) do
        for d = step, 40, step do
            local checkPos = startPos + (dir * d)
            if not workspace:Raycast(checkPos + Vector3.new(0, 1, 0), Vector3.new(0, maxCheckHeight, 0), rayParams) then
                table.insert(edgesFound, checkPos)
                break
            end
        end
    end

    for _, edgePos in ipairs(edgesFound) do
        local score = (edgePos - targetPos).Magnitude
        if score < bestDist then
            bestDist = score
            bestEdge = edgePos
        end
    end
    return bestEdge
end

-- หาบล็อกถัดไปในการลัดเลาะ
local function getNextEdgeTracingStep(currentPos, targetPos, maxCheckHeight)
    local step = 4
    local neighbors = {Vector3.new(step,0,0), Vector3.new(-step,0,0), Vector3.new(0,0,step), Vector3.new(0,0,-step)}
    local validSteps = {}

    for _, offset in ipairs(neighbors) do
        local testPos = currentPos + offset
        
        -- Loop Detection (กันเดินย้อน)
        local visited = false
        for _, vPos in ipairs(_G.TraceVisited or {}) do
            if (vPos - testPos).Magnitude < 1 then visited = true; break end
        end

        if not visited then
            -- ถ้าช่องนี้เดินได้ (ไม่มีเพดาน)
            if not workspace:Raycast(testPos + Vector3.new(0, 1, 0), Vector3.new(0, maxCheckHeight, 0), rayParams) then
                local touchesCeiling = false
                local ceilingPos = nil
                -- เช็คว่ามีขอบเขียว (เพดาน) ติดอยู่ข้างๆ ไหม
                for _, sideOff in ipairs(neighbors) do
                    local sidePos = testPos + sideOff
                    if workspace:Raycast(sidePos + Vector3.new(0, 1, 0), Vector3.new(0, maxCheckHeight, 0), rayParams) then
                        touchesCeiling = true
                        ceilingPos = sidePos
                        break
                    end
                end
                if touchesCeiling then table.insert(validSteps, {pos = testPos, ceilPos = ceilingPos}) end
            end
        end
    end

    local bestStep, bestCeil = nil, nil
    local bestDist = math.huge
    for _, stepData in ipairs(validSteps) do
        local dist = (stepData.pos - targetPos).Magnitude
        if dist < bestDist then
            bestDist = dist; bestStep = stepData.pos; bestCeil = stepData.ceilPos
        end
    end

    if bestStep then
        table.insert(_G.TraceVisited, bestStep)
        
        -- [ระบบตรวจจับการวนลูป (Loop Mapping)]
        if #_G.TraceVisited > 15 then
            local startNode = _G.TraceVisited[1]
            if (bestStep - startNode).Magnitude < step * 1.5 then
                return "LOOP_COMPLETED", nil
            end
        end

        if debugEnabled then
            for _, v in pairs(workspace.Terrain:GetChildren()) do
                if v.Name == "Debug_TraceYellow" or v.Name == "Debug_TraceGreen" then v:Destroy() end
            end
            local py = Instance.new("Part")
            py.Name, py.Size, py.Position = "Debug_TraceYellow", Vector3.new(3.5, 0.5, 3.5), bestStep + Vector3.new(0, 2, 0)
            py.Anchored, py.CanCollide, py.CanQuery, py.Transparency, py.Color, py.Material = true, false, false, 0.2, Color3.fromRGB(255, 255, 0), Enum.Material.Neon
            py.Parent = workspace.Terrain
            if bestCeil then
                local pg = Instance.new("Part")
                pg.Name, pg.Size, pg.Position = "Debug_TraceGreen", Vector3.new(3.5, 0.5, 3.5), bestCeil + Vector3.new(0, 2, 0)
                pg.Anchored, pg.CanCollide, pg.CanQuery, pg.Transparency, pg.Color, pg.Material = true, false, false, 0.5, Color3.fromRGB(0, 255, 0), Enum.Material.Neon
                pg.Parent = workspace.Terrain
            end
        end
        return bestStep, bestCeil
    end
    return nil, nil
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
Section:NewButton("Clear Memory (ลบเสาฟ้า)", "Reset Area", function() _G.MapMemory = {}; clearVisuals() end)
refreshList()

local MoveSection = Tab:NewSection("Navigation Control")
MoveSection:NewToggle("Enable Follow", "Start Logic", function(s) 
    followEnabled = s 
    if not s then 
        currentWaypoints = {}; clearVisuals(); isProbing = false; isFollowingCustomPath = false 
        isEscapingCeiling = false; currentEscapeTarget = nil
    end
end)
MoveSection:NewToggle("Show Path", "Visuals", function(s) debugEnabled = s; drawMemoryWaypoints() end)
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
                if not randomTarget or not randomTarget.Character or randomTarget.Character.Humanoid.Health <= 0 then
                    local vP = {}
                    for _, p in pairs(Players:GetPlayers()) do if p ~= LocalPlayer and p.Character and p.Character.Humanoid.Health > 0 then table.insert(vP, p) end end
                    if #vP > 0 then randomTarget = vP[math.random(1, #vP)] end
                end
                target = randomTarget
            else
                local bestHP = (SelectedMode == "Max HP") and -1 or math.huge
                for _, p in pairs(Players:GetPlayers()) do
                    if p ~= LocalPlayer and p.Character then
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

                -- ตรวจจับอาการเดินติดหิน
                local isStuck = false
                if (currentPos - lastPosition).Magnitude < 0.5 then
                    if os.clock() - lastMoveTick > 0.5 then isStuck = true end -- ติดครึ่งวิกระโดดเลย
                    if os.clock() - lastMoveTick > 1.5 then 
                        currentWaypoints = {}; lastMoveTick = os.clock()
                        if isFollowingCustomPath or isEscapingCeiling then
                            _G.CustomPathFailTick = os.clock() 
                            isFollowingCustomPath = false; isEscapingCeiling = false; currentEscapeTarget = nil
                        end
                    end
                else
                    lastPosition = currentPos; lastMoveTick = os.clock()
                end

                -- =======================================================
                -- [ระบบลัดเลาะขอบเพดานแบบปิดล็อก (Absolute Priority)]
                -- =======================================================
                if isEscapingCeiling and currentEscapeTarget then
                    local requiredHeightCheck = math.max(20, targetPos.Y - currentPos.Y + 5)
                    local distToEscape = (Vector2.new(currentPos.X, currentPos.Z) - Vector2.new(currentEscapeTarget.X, currentEscapeTarget.Z)).Magnitude
                    
                    -- เช็คระหว่างเดินว่า "จุดนี้ปีนได้ไหม" (ดึงความจำขึ้นมา)
                    local testClimb = computeVerticalClimbPath(currentPos, targetPos, myChar, target.Character)
                    if #testClimb > 0 then
                        -- บันทึกพิกัดนี้ลงสมอง!
                        table.insert(_G.MapMemory, currentPos)
                        drawMemoryWaypoints()
                        
                        -- ยกเลิกการลัดเลาะ แล้วเปลี่ยนไปปีนทันที
                        isEscapingCeiling = false
                        currentEscapeTarget = nil
                        currentWaypoints = testClimb
                        isFollowingCustomPath = true
                        currentWaypointIndex = 1
                        lastTargetPos = targetPos
                        lastComputeTime = os.clock()
                        return
                    end

                    if distToEscape < 2.5 then
                        -- คำนวณก้าวถัดไป
                        local nextTraceStep, _ = getNextEdgeTracingStep(currentPos, targetPos, requiredHeightCheck)
                        
                        if nextTraceStep == "LOOP_COMPLETED" then
                            -- เดินวนครบรอบตึกแล้ว!
                            isEscapingCeiling = false
                            currentEscapeTarget = nil
                            _G.CustomPathFailTick = os.clock() -- ยอมแพ้ตึกนี้
                        elseif nextTraceStep then
                            currentEscapeTarget = nextTraceStep
                            lastComputeTime = os.clock()
                        else
                            -- ติดมุม ตัน
                            isEscapingCeiling = false
                            currentEscapeTarget = nil
                            _G.CustomPathFailTick = os.clock() 
                        end
                    else
                        -- เดินไปหาบล็อกเหลือง และกระโดดหลบหินถ้าติด
                        myHuman:MoveTo(currentEscapeTarget)
                        if isStuck then forceJump(myHuman) end
                        
                        if os.clock() - lastComputeTime > 6 then
                             isEscapingCeiling = false; currentEscapeTarget = nil; _G.CustomPathFailTick = os.clock()
                        end
                    end
                    return -- ล็อกห้าม Logic อื่นทำงาน!
                end
                -- =======================================================

                -- โหมดเดินตามบันได
                if isFollowingCustomPath and #currentWaypoints > 0 then
                    if (targetPos - lastTargetPos).Magnitude > 15 then
                        isFollowingCustomPath = false; currentWaypoints = {}
                    else
                        local wp = currentWaypoints[currentWaypointIndex]
                        if wp then
                            myHuman:MoveTo(wp.Position)
                            if wp.Action == Enum.PathWaypointAction.Jump then
                                if myHuman.FloorMaterial ~= Enum.Material.Air and not isClimbingState then forceJump(myHuman) end
                            elseif isStuck then
                                forceJump(myHuman) -- ถ้าเดินติดบันไดให้กระโดด
                            end
                            local dist2D = (Vector2.new(currentPos.X, currentPos.Z) - Vector2.new(wp.Position.X, wp.Position.Z)).Magnitude
                            local distY = math.abs(currentPos.Y - wp.Position.Y)
                            if dist2D < 3.5 and distY < 4.5 then
                                currentWaypointIndex = currentWaypointIndex + 1; lastMoveTick = os.clock() 
                            end
                            return 
                        else
                            isFollowingCustomPath = false; currentWaypoints = {}
                        end
                    end
                end

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
                        isProbing = false; currentWaypoints = {}; isFollowingCustomPath = false
                        updateDebug("DirectTrace", currentPos, flatTargetPos, Color3.fromRGB(255, 128, 0)) 
                        myHuman:MoveTo(flatTargetPos)
                        if shouldJumpDrop or isStuck then forceJump(myHuman) end

                    elseif canWalkStraight then
                        isProbing = false; currentWaypoints = {}
                        updateDebug("DirectTrace", currentPos, targetPos, Color3.fromRGB(0, 255, 0))
                        myHuman:MoveTo(targetPos)
                        if isStuck then forceJump(myHuman) end
                    
                    else
                        if os.clock() - lastComputeTime > 0.5 or (targetPos - lastTargetPos).Magnitude > 5 then
                            currentWaypoints = {}; isProbing = false
                            
                            -- [เช็คระบบความจำตึกก่อน!]
                            local memoryTarget = nil
                            if targetPos.Y > currentPos.Y + 4 then
                                for _, memPos in ipairs(_G.MapMemory) do
                                    -- ถ้าเป้าหมายอยู่ใกล้ๆ เขตเสาฟ้าที่จำไว้ (ระยะ 100 Block)
                                    if (Vector2.new(targetPos.X, targetPos.Z) - Vector2.new(memPos.X, memPos.Z)).Magnitude < 100 then
                                        memoryTarget = memPos
                                        break
                                    end
                                end
                            end

                            if memoryTarget and (Vector2.new(currentPos.X, currentPos.Z) - Vector2.new(memoryTarget.X, memoryTarget.Z)).Magnitude > 5 then
                                -- จำได้ว่าตรงนี้มีบันได เดินไปหาบันไดก่อนเลย!
                                local path = PathfindingService:CreatePath({AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = true})
                                path:ComputeAsync(currentPos, memoryTarget)
                                if path.Status == Enum.PathStatus.Success then
                                    currentWaypoints = path:GetWaypoints()
                                    currentWaypointIndex = 2; lastTargetPos = targetPos; lastComputeTime = os.clock()
                                    isFollowingCustomPath = false
                                end
                            else
                                -- ถ้ายังไม่เคยจำตึกนี้ ก็ใช้ระบบปกติ
                                local path = PathfindingService:CreatePath({AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = true})
                                path:ComputeAsync(currentPos, targetPos)
                                
                                if path.Status == Enum.PathStatus.Success then
                                    currentWaypoints = path:GetWaypoints()
                                    currentWaypointIndex = 2; lastTargetPos = targetPos; lastComputeTime = os.clock()
                                    isFollowingCustomPath = false 
                                else
                                    local canUseCustomPaths = (_G.CustomPathFailTick == nil) or (os.clock() - _G.CustomPathFailTick > 4)

                                    if targetPos.Y > currentPos.Y + 4 and canUseCustomPaths then
                                        local requiredHeightCheck = math.max(20, targetPos.Y - currentPos.Y + 5)
                                        
                                        if checkCeilingAround(currentPos, requiredHeightCheck) then
                                            local edgeStart = findNearestCeilingEdgeCross(currentPos, targetPos, requiredHeightCheck)
                                            if edgeStart then
                                                isEscapingCeiling = true; _G.TraceVisited = {currentPos}; currentEscapeTarget = edgeStart; lastComputeTime = os.clock()
                                            end
                                        else
                                            currentWaypoints = computeVerticalClimbPath(currentPos, targetPos, myChar, target.Character)
                                            if #currentWaypoints > 0 then
                                                isFollowingCustomPath = true; currentWaypointIndex = 1; lastTargetPos = targetPos; lastComputeTime = os.clock()
                                            end
                                        end
                                    else
                                        isProbing = true; currentWaypoints = {}
                                    end
                                end
                            end
                        end
                        
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
                                if workspace:Raycast(currentPos, bestDir * 4, rayParams) or isStuck then forceJump(myHuman) end
                            end
                        end
                    end
                else
                    currentWaypoints = {}; myHuman:MoveTo(currentPos)
                end
            end
        end)
    end
end)
