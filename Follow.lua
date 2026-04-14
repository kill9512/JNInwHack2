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

-- [ใหม่] ระบบความจำและลัดเลาะ
local isEscapingCeiling = false
local escapePhase = "none"
local currentEscapeTarget = nil
_G.TraceVisited = {} -- รอยเท้าที่เคยเดิน
_G.KnownStairs = _G.KnownStairs or {} -- ความจำถาวร: บันทึกจุดที่ปีนได้ {pos = Vector3, topY = number}

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

-- วาดจุดความจำ (บันไดที่เคยค้นพบ)
local function drawKnownStairs()
    if not debugEnabled then return end
    for _, v in pairs(workspace.Terrain:GetChildren()) do
        if v.Name == "Debug_MemoryStair" then v:Destroy() end
    end
    for _, stair in ipairs(_G.KnownStairs) do
        local p = Instance.new("Part")
        p.Name, p.Size, p.Position = "Debug_MemoryStair", Vector3.new(2, 2, 2), stair.pos + Vector3.new(0, 2, 0)
        p.Anchored, p.CanCollide, p.CanQuery, p.Transparency = true, false, false, 0.3
        p.Color, p.Material = Color3.fromRGB(255, 0, 255), Enum.Material.Neon -- สีชมพู
        p.Parent = workspace.Terrain
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
    local offsets = { Vector3.new(0,0,0), Vector3.new(3,0,0), Vector3.new(-3,0,0), Vector3.new(0,0,3), Vector3.new(0,0,-3) }
    for _, off in ipairs(offsets) do
        if workspace:Raycast(pos + off + Vector3.new(0, 1, 0), Vector3.new(0, height, 0), rayParams) then return true end
    end
    return false
end

local function findNearestCeilingEdgeCross(startPos, targetPos, maxCheckHeight)
    local step = 5
    local maxRadius = 40
    local bestEdge = nil
    local bestDist = math.huge
    local edgesFound = {}

    local directions = { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) }

    if debugEnabled then clearVisuals() end

    for _, dir in ipairs(directions) do
        for d = step, maxRadius, step do
            local checkPos = startPos + (dir * d)
            local upRay = workspace:Raycast(checkPos + Vector3.new(0, 1, 0), Vector3.new(0, maxCheckHeight, 0), rayParams)
            if not upRay then
                table.insert(edgesFound, checkPos)
                break 
            end
        end
    end

    for _, edgePos in ipairs(edgesFound) do
        local score = (edgePos - targetPos).Magnitude
        if score < bestDist then bestDist = score; bestEdge = edgePos end
    end
    return bestEdge
end

local function getNextEdgeTracingStep(currentPos, targetPos, maxCheckHeight)
    local step = 5
    local neighbors = { Vector3.new(step, 0, 0), Vector3.new(-step, 0, 0), Vector3.new(0, 0, step), Vector3.new(0, 0, -step) }
    local validSteps = {}

    for _, offset in ipairs(neighbors) do
        local testPos = currentPos + offset
        
        -- เช็ครอยเท้า ว่าเคยเดินผ่านไปแล้วหรือยัง (ในระยะ 3 studs)
        local visited = false
        for _, vPos in ipairs(_G.TraceVisited or {}) do
            if (vPos - testPos).Magnitude < 3 then visited = true; break end
        end

        if not visited then
            local upRay = workspace:Raycast(testPos + Vector3.new(0, 1, 0), Vector3.new(0, maxCheckHeight, 0), rayParams)
            if not upRay then
                local touchesCeiling = false
                local ceilingPos = nil
                for _, sideOff in ipairs(neighbors) do
                    local sidePos = testPos + sideOff
                    if workspace:Raycast(sidePos + Vector3.new(0, 1, 0), Vector3.new(0, maxCheckHeight, 0), rayParams) then
                        touchesCeiling = true; ceilingPos = sidePos; break
                    end
                end
                if touchesCeiling then table.insert(validSteps, {pos = testPos, ceilPos = ceilingPos}) end
            end
        end
    end

    local bestStep, bestCeil, bestDist = nil, nil, math.huge
    for _, stepData in ipairs(validSteps) do
        local dist = (stepData.pos - targetPos).Magnitude
        if dist < bestDist then
            bestDist = dist; bestStep = stepData.pos; bestCeil = stepData.ceilPos
        end
    end

    if bestStep then
        table.insert(_G.TraceVisited, bestStep)
        
        if debugEnabled then
            for _, v in pairs(workspace.Terrain:GetChildren()) do
                if v.Name == "Debug_TraceYellow" or v.Name == "Debug_TraceGreen" then v:Destroy() end
            end
            local py = Instance.new("Part")
            py.Name, py.Size, py.Position = "Debug_TraceYellow", Vector3.new(4, 0.5, 4), bestStep + Vector3.new(0, 2, 0)
            py.Anchored, py.CanCollide, py.Transparency, py.Color, py.Material = true, false, 0.2, Color3.fromRGB(255, 255, 0), Enum.Material.Neon
            py.Parent = workspace.Terrain
            
            if bestCeil then
                local pg = Instance.new("Part")
                pg.Name, pg.Size, pg.Position = "Debug_TraceGreen", Vector3.new(4, 0.5, 4), bestCeil + Vector3.new(0, 2, 0)
                pg.Anchored, pg.CanCollide, pg.Transparency, pg.Color, pg.Material = true, false, 0.5, Color3.fromRGB(0, 255, 0), Enum.Material.Neon
                pg.Parent = workspace.Terrain
            end
        end
        return bestStep
    end
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
        else
            break
        end
    end
    return customWaypoints
end

-- --- UI ---
Section:NewDropdown("Target Mode", "Mode", {"Manual", "Max HP", "Min HP", "Random"}, function(m) SelectedMode = m end)
Section:NewTextBox("Search Player", "พิมพ์ชื่อ หรือ Display Name", function(txt)
    local lowerTxt = txt:lower()
    for _, p in pairs(Players:GetPlayers()) do 
        if p ~= LocalPlayer and (p.Name:lower():find(lowerTxt) or p.DisplayName:lower():find(lowerTxt)) then
            SelectedPlayerName = p.Name; SelectedMode = "Manual"; break
        end
    end
end)

local MoveSection = Tab:NewSection("Navigation Control")
MoveSection:NewToggle("Enable Follow", "Start Logic", function(s) 
    followEnabled = s 
    if not s then 
        currentWaypoints = {}; clearVisuals(); isProbing = false; isFollowingCustomPath = false 
        isEscapingCeiling = false; escapePhase = "none"; currentEscapeTarget = nil; _G.TraceVisited = {}
    end
end)
MoveSection:NewToggle("Show Path", "Visuals", function(s) debugEnabled = s; drawKnownStairs() end)
MoveSection:NewSlider("Distance", "Gap", 20, 1, function(s) followDistance = s end)

-- --- MAIN LOOP ---
task.spawn(function()
    while true do
        task.wait(0.05)
        if not followEnabled then continue end
        
        pcall(function()
            local target = nil
            if SelectedMode == "Manual" then target = Players:FindFirstChild(SelectedPlayerName or "") end
            -- (ระบบหาเป้าหมายเดิมละไว้เพื่อให้โค้ดไม่ยาวเกินไป ใช้ของเดิมที่คุณมีได้เลยครับ)
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

                -- เช็คติดแหง็ก
                if (currentPos - lastPosition).Magnitude < 0.5 then
                    if os.clock() - lastMoveTick > 1.5 then 
                        currentWaypoints = {} 
                        lastMoveTick = os.clock()
                        if isFollowingCustomPath or isEscapingCeiling then
                            _G.CustomPathFailTick = os.clock() 
                            isFollowingCustomPath = false; isEscapingCeiling = false; escapePhase = "none"; currentEscapeTarget = nil
                        else
                            forceJump(myHuman) -- กระโดดดิ้นถ้าติดปกติ
                        end
                    end
                else
                    lastPosition = currentPos
                    lastMoveTick = os.clock()
                end

                -- =======================================================
                -- [ระบบลัดเลาะขอบเพดาน (Edge Tracing & Memory)]
                -- =======================================================
                if isEscapingCeiling and currentEscapeTarget then
                    local requiredHeightCheck = math.max(20, targetPos.Y - currentPos.Y + 5)
                    local distToEscape = (Vector2.new(currentPos.X, currentPos.Z) - Vector2.new(currentEscapeTarget.X, currentEscapeTarget.Z)).Magnitude
                    
                    -- [ใหม่] เช็คสิ่งกีดขวางด้านหน้าตอนเดินลัดเลาะ (กันชนหิน)
                    local frontRay = workspace:Raycast(currentPos, myRoot.CFrame.LookVector * 4, rayParams)
                    if frontRay and frontRay.Instance.CanCollide then forceJump(myHuman) end

                    -- [ใหม่] ระหว่างเดินลัดเลาะ ให้แอบเช็คทางปีนขึ้นไปด้วย (ค้นหาบันได)
                    local potentialStairs = computeVerticalClimbPath(currentPos, targetPos, myChar, target.Character)
                    if #potentialStairs > 0 then
                        -- เจอบันไดแล้ว! จำไว้ในสมองและเลิกลัดเลาะ
                        table.insert(_G.KnownStairs, {pos = currentPos, topY = targetPos.Y})
                        drawKnownStairs()
                        isEscapingCeiling = false
                        isFollowingCustomPath = true
                        currentWaypoints = potentialStairs
                        currentWaypointIndex = 1
                        if debugEnabled then clearVisuals() end
                        return -- ตัดจบ loop เพื่อไปโหมดปีนทันที
                    end

                    -- ถ้าเดินถึงจุดหมายย่อย (จุดเหลือง)
                    if distToEscape < 2.5 then
                        -- [ใหม่] เช็คว่าเดินวนลูปครบรอบหรือยัง (วงกลมบรรจบ)
                        local isLoopComplete = false
                        if #_G.TraceVisited > 10 then
                            local distToStart = (currentPos - _G.TraceVisited[1]).Magnitude
                            if distToStart < 5 then isLoopComplete = true end
                        end

                        if not checkCeilingAround(currentPos, requiredHeightCheck) or isLoopComplete then
                            -- พ้นตึกแล้ว หรือเดินครบรอบตึกแล้ว
                            isEscapingCeiling = false
                            escapePhase = "none"
                            currentEscapeTarget = nil
                            _G.TraceVisited = {}
                            if debugEnabled then clearVisuals() end
                            return 
                        end

                        -- หาจุดเดินถัดไป
                        escapePhase = "tracing"
                        local nextTraceStep = getNextEdgeTracingStep(currentPos, targetPos, requiredHeightCheck)
                        if nextTraceStep then
                            currentEscapeTarget = nextTraceStep
                            lastComputeTime = os.clock()
                        else
                            -- ติดมุม ไปต่อไม่ได้
                            isEscapingCeiling = false
                            _G.CustomPathFailTick = os.clock()
                        end
                    else
                        myHuman:MoveTo(currentEscapeTarget)
                        if os.clock() - lastComputeTime > 6 then
                             isEscapingCeiling = false
                             _G.CustomPathFailTick = os.clock()
                        end
                    end
                    return -- ล็อคไม่ให้โหมดอื่นแย่งทำงานเด็ดขาด!
                end
                -- =======================================================

                -- เดินตาม Path ปีนป่าย
                if isFollowingCustomPath and #currentWaypoints > 0 then
                    if (targetPos - lastTargetPos).Magnitude > 15 then
                        isFollowingCustomPath = false; currentWaypoints = {}
                    else
                        local wp = currentWaypoints[currentWaypointIndex]
                        if wp then
                            myHuman:MoveTo(wp.Position)
                            if wp.Action == Enum.PathWaypointAction.Jump then
                                if myHuman.FloorMaterial ~= Enum.Material.Air and not isClimbingState then forceJump(myHuman) end
                            end
                            local dist2D = (Vector2.new(currentPos.X, currentPos.Z) - Vector2.new(wp.Position.X, wp.Position.Z)).Magnitude
                            if dist2D < 3.5 and math.abs(currentPos.Y - wp.Position.Y) < 4.5 then
                                currentWaypointIndex = currentWaypointIndex + 1
                                lastMoveTick = os.clock() 
                            end
                            return -- ล็อคไม่ให้โหมดอื่นแย่ง
                        else
                            isFollowingCustomPath = false; currentWaypoints = {}
                        end
                    end
                end

                -- โหมดปกติ (เดินบนพื้นราบ)
                if hDist > followDistance or math.abs(vDist) > 5 then
                    local moveDir = (targetPos - currentPos).Unit
                    local directRay = workspace:Raycast(currentPos, moveDir * trueDist, rayParams)
                    
                    if (not directRay) and (math.abs(vDist) < 5) then
                        isProbing = false; currentWaypoints = {}
                        updateDebug("DirectTrace", currentPos, targetPos, Color3.fromRGB(0, 255, 0))
                        myHuman:MoveTo(targetPos)
                    else
                        if os.clock() - lastComputeTime > 0.5 then
                            -- [ใหม่] ก่อนทำอย่างอื่น เช็คความจำก่อนว่ามีบันไดใกล้ๆ ไหม!
                            local bestMemoryStair = nil
                            local bestMemDist = math.huge
                            for _, stair in ipairs(_G.KnownStairs) do
                                -- เช็คว่าบันไดอยู่ใกล้เรา และเป้าหมายอยู่สูง
                                local distToStair = (currentPos - stair.pos).Magnitude
                                if distToStair < 50 and targetPos.Y > currentPos.Y + 4 then
                                    if distToStair < bestMemDist then bestMemDist = distToStair; bestMemoryStair = stair end
                                end
                            end

                            if bestMemoryStair then
                                -- จำได้ว่ามีบันได! เดินไปหาบันไดเลย ไม่ต้องเสียเวลากางเรดาร์
                                local path = PathfindingService:CreatePath({AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = true})
                                path:ComputeAsync(currentPos, bestMemoryStair.pos)
                                if path.Status == Enum.PathStatus.Success then
                                    currentWaypoints = path:GetWaypoints()
                                    currentWaypointIndex = 2
                                    isFollowingCustomPath = true
                                    lastComputeTime = os.clock()
                                    return
                                end
                            end

                            -- ถ้าไม่มีความจำ ค่อยกางเรดาร์หา
                            local canUseCustomPaths = (_G.CustomPathFailTick == nil) or (os.clock() - _G.CustomPathFailTick > 4)
                            if targetPos.Y > currentPos.Y + 4 and canUseCustomPaths then
                                local requiredHeightCheck = math.max(20, targetPos.Y - currentPos.Y + 5)
                                if checkCeilingAround(currentPos, requiredHeightCheck) then
                                    local edgeStart = findNearestCeilingEdgeCross(currentPos, targetPos, requiredHeightCheck)
                                    if edgeStart then
                                        isEscapingCeiling = true
                                        escapePhase = "findEdge"
                                        currentEscapeTarget = edgeStart
                                        _G.TraceVisited = {currentPos}
                                        lastComputeTime = os.clock()
                                    end
                                else
                                    currentWaypoints = computeVerticalClimbPath(currentPos, targetPos, myChar, target.Character)
                                    if #currentWaypoints > 0 then
                                        isFollowingCustomPath = true; currentWaypointIndex = 1; lastComputeTime = os.clock()
                                    end
                                end
                            end
                        end
                    end
                else
                    myHuman:MoveTo(currentPos)
                end
            end
        end)
    end
end)
