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

-- ระบบความจำสถานที่ (Building Memory)
_G.BuildingMemories = _G.BuildingMemories or {}

-- สถานะระบบลัดเลาะขอบ
_G.TraceState = {
    Active = false,
    Phase = "None",
    TargetPos = nil,
    StartPos = nil,
    Path = {}, -- เก็บเส้นทางสีเหลืองทั้งหมด
    StepCount = 0,
    Visited = {},
    LastMoveTick = 0
}

-- --- Debug Visualization ---
local function clearVisuals()
    for _, v in pairs(workspace.Terrain:GetChildren()) do
        if v.Name == "WP_Debug" or v.Name == "DirectTrace" or v.Name == "ProbeTrace" 
        or string.find(v.Name, "Debug_Edge") or string.find(v.Name, "Debug_Ceil") 
        or string.find(v.Name, "TraceTrail_") then 
            v:Destroy() 
        end
    end
end

local function updateDebug(name, startPos, endPos, color)
    if not debugEnabled then return end
    local line = workspace.Terrain:FindFirstChild(name) or Instance.new("LineHandleAdornment")
    line.Name, line.Thickness, line.Transparency = name, 3, 0.4
    line.Adornee, line.AlwaysOnTop = workspace.Terrain, true
    line.Color3, line.Length = color, (startPos - endPos).Magnitude
    line.CFrame, line.Parent = CFrame.lookAt(startPos, endPos), workspace.Terrain
end

local function drawMemoryPillars()
    for _, v in pairs(workspace.Terrain:GetChildren()) do
        if string.find(v.Name, "MemPillar_") or string.find(v.Name, "MemArea_") then v:Destroy() end
    end
    if not debugEnabled then return end
    
    for i, mem in ipairs(_G.BuildingMemories) do
        -- วาดแท่งสีฟ้า
        local name = "MemPillar_"..i
        local p = Instance.new("Part")
        p.Name = name
        local targetY = mem.TargetY or (mem.ClimbSpot.Y + 50)
        local h = math.max(10, targetY - mem.ClimbSpot.Y)
        p.Size = Vector3.new(2, h, 2)
        p.Position = mem.ClimbSpot + Vector3.new(0, h/2, 0)
        p.Anchored, p.CanCollide, p.CanQuery = true, false, false
        p.Transparency, p.Material = 0.4, Enum.Material.Neon
        p.Color = Color3.fromRGB(0, 255, 255) 
        p.Parent = workspace.Terrain

        -- วาดพื้นที่สีเขียวจางๆ (Area)
        if mem.PathArea then
            for j, wp in ipairs(mem.PathArea) do
                local ap = Instance.new("Part")
                ap.Name = "MemArea_"..i.."_"..j
                ap.Size = Vector3.new(6, 0.5, 6)
                ap.Position = wp + Vector3.new(0, 1.5, 0)
                ap.Anchored, ap.CanCollide, ap.CanQuery = true, false, false
                ap.Transparency, ap.Material = 0.7, Enum.Material.Neon
                ap.Color = Color3.fromRGB(0, 255, 0)
                ap.Parent = workspace.Terrain
            end
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

local function moveWithAvoidance(humanoid, pos)
    local hrp = humanoid.Parent:FindFirstChild("HumanoidRootPart")
    if hrp then
        local flatPos = Vector3.new(pos.X, hrp.Position.Y, pos.Z)
        local dir = (flatPos - hrp.Position).Unit
        local dist = (flatPos - hrp.Position).Magnitude
        local checkDist = math.min(dist, 5)

        if dir.Magnitude == dir.Magnitude then
            local lowerRay = workspace:Raycast(hrp.Position - Vector3.new(0, 1.5, 0), dir * checkDist, rayParams)
            local upperRay = workspace:Raycast(hrp.Position + Vector3.new(0, 1, 0), dir * checkDist, rayParams)
            if lowerRay or upperRay then forceJump(humanoid) end
        end
    end
    humanoid:MoveTo(pos)
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

-- หาจุดที่ดีที่สุดและแม่นยำในการตั้งแท่งฟ้า (ยืนได้ ถอยจากกำแพงนิดนึง)
local function findAccurateClimbSpot(pathPoints, targetPos)
    local bestSpot = pathPoints[1]
    local bestDist = math.huge
    for _, p in ipairs(pathPoints) do
        local d = (p - targetPos).Magnitude
        if d < bestDist then
            bestDist = d
            bestSpot = p
        end
    end
    
    local dir = (Vector3.new(targetPos.X, bestSpot.Y, targetPos.Z) - bestSpot).Unit
    local wallRay = workspace:Raycast(bestSpot + Vector3.new(0, 1, 0), dir * 15, rayParams)
    if wallRay then
        -- ถ้าชนกำแพง ให้ถอยออกมา 2.5 Studs ตาม Normal
        return wallRay.Position + (wallRay.Normal * 2.5) - Vector3.new(0, 1, 0)
    end
    return bestSpot
end

local function crossScanForEdge(startPos, maxCheckHeight, targetPos)
    local step = 6
    local maxRadius = 60
    local dirs = { Vector3.new(1,0,0), Vector3.new(-1,0,0), Vector3.new(0,0,1), Vector3.new(0,0,-1) }
    local endpoints = {}

    for _, dir in ipairs(dirs) do
        for d = step, maxRadius, step do
            local checkPos = startPos + (dir * d)
            local rayOrigin = checkPos + Vector3.new(0, 1, 0)
            local upRay = workspace:Raycast(rayOrigin, Vector3.new(0, maxCheckHeight, 0), rayParams)
            if not upRay then
                table.insert(endpoints, checkPos)
                break 
            end
        end
    end

    local bestEdge = nil
    local bestDist = math.huge
    for _, edgePos in ipairs(endpoints) do
        local d = (edgePos - targetPos).Magnitude
        if d < bestDist then bestDist = d; bestEdge = edgePos end
    end
    return bestEdge
end

local function getNextEdgeTracingStep(currentPos, maxCheckHeight, targetPos)
    local step = 6
    local neighbors = { Vector3.new(step,0,0), Vector3.new(-step,0,0), Vector3.new(0,0,step), Vector3.new(0,0,-step) }
    local validSteps = {}

    for _, offset in ipairs(neighbors) do
        local testPos = currentPos + offset
        
        -- กรองไม่ให้ย้อนกลับ
        local visited = false
        for _, v in ipairs(_G.TraceState.Visited) do
            if (v - testPos).Magnitude < 4.5 then visited = true; break end
        end

        if not visited then
            local isWalkable = not workspace:Raycast(testPos + Vector3.new(0,1,0), Vector3.new(0, maxCheckHeight, 0), rayParams)
            if isWalkable then
                local isNearWall = false
                for _, subOff in ipairs(neighbors) do
                    local wallRay = workspace:Raycast(testPos + subOff + Vector3.new(0,1,0), Vector3.new(0, maxCheckHeight, 0), rayParams)
                    if wallRay then isNearWall = true; break end
                end
                if isNearWall then table.insert(validSteps, testPos) end
            end
        end
    end

    local bestStep = nil
    local bestDist = math.huge
    for _, pos in ipairs(validSteps) do
        local d = (pos - targetPos).Magnitude
        if d < bestDist then bestDist = d; bestStep = pos end
    end

    return bestStep and {pos = bestStep} or nil
end

local function computeVerticalClimbPath(startPos, targetPos, myChar, tChar)
    local customWaypoints = {}
    local heightToClimb = targetPos.Y - startPos.Y
    if heightToClimb < 3 then return customWaypoints end

    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {myChar, tChar, workspace.Terrain}

    local partsNearby = workspace:GetPartBoundsInRadius(startPos + Vector3.new(0, 6, 0), 12, params)
    local bestNextPos = nil
    local bestScore = math.huge
    
    for _, part in ipairs(partsNearby) do
        if part:IsA("BasePart") and part.CanCollide and part.Transparency < 1 then
            local rayOrigin = part.Position + Vector3.new(0, (part.Size.Y/2) + 4, 0)
            local downRay = workspace:Raycast(rayOrigin, Vector3.new(0, -8, 0), rayParams)
            if downRay then
                local hitPos = downRay.Position
                local heightDiff = hitPos.Y - startPos.Y
                if heightDiff > 0.5 and heightDiff <= 8.0 and hasHeadroom(hitPos) then
                    local reqUpDist = math.max(5, targetPos.Y - hitPos.Y)
                    local upRay = workspace:Raycast(hitPos + Vector3.new(0,1,0), Vector3.new(0, reqUpDist, 0), rayParams)
                    local penalty = upRay and (reqUpDist - upRay.Distance)*10 or 0
                    local score = (Vector2.new(hitPos.X, hitPos.Z) - Vector2.new(targetPos.X, targetPos.Z)).Magnitude - (heightDiff*15) + penalty
                    
                    if score < bestScore then bestScore = score; bestNextPos = hitPos end
                end
            end
        end
    end
    
    if bestNextPos then
        table.insert(customWaypoints, {Position = bestNextPos, Action = Enum.PathWaypointAction.Jump})
        if bestNextPos.Y >= targetPos.Y - 2 then
            table.insert(customWaypoints, {Position = targetPos, Action = Enum.PathWaypointAction.Walk})
        end
    end
    return customWaypoints
end

local function findPathWithFallback(startPos, targetPos)
    local path = PathfindingService:CreatePath({AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 4})
    path:ComputeAsync(startPos, targetPos)
    if path.Status == Enum.PathStatus.Success then return path:GetWaypoints() end
    return {} 
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
        _G.TraceState.Active = false
    end
end)
MoveSection:NewToggle("Show Path", "Visuals", function(s) 
    debugEnabled = s 
    if not s then clearVisuals() end
end)
MoveSection:NewSlider("Distance", "Gap", 20, 1, function(s) followDistance = s end)

MoveSection:NewButton("Clear Memory", "ล้างความจำตึกและรอยทาง", function() 
    _G.BuildingMemories = {} 
    drawMemoryPillars()
end)

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
                        if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("Humanoid") and p.Character.Humanoid.Health > 0 then table.insert(validPlayers, p) end
                    end
                    if #validPlayers > 0 then randomTarget = validPlayers[math.random(1, #validPlayers)] end
                end
                target = randomTarget
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

                drawMemoryPillars()

                local isStuck = false
                if (currentPos - lastPosition).Magnitude < 1.0 then 
                    if os.clock() - lastMoveTick > 1.5 then 
                        isStuck = true
                        if isFollowingCustomPath or _G.TraceState.Active then
                            _G.CustomPathFailTick = os.clock() 
                            isFollowingCustomPath = false
                            currentWaypoints = {}
                        end
                    end
                else
                    lastPosition = currentPos
                    lastMoveTick = os.clock()
                end

                -- =======================================================
                -- [1] เช็คการเดินเข้าพื้นที่สีเขียว (Green Area)
                -- =======================================================
                local activeMem = nil
                for _, mem in ipairs(_G.BuildingMemories) do
                    for _, wp in ipairs(mem.PathArea or {}) do
                        if (currentPos - wp).Magnitude < 10 then 
                            activeMem = mem; break
                        end
                    end
                    if activeMem then break end
                end

                if activeMem then
                    local cSpot = activeMem.ClimbSpot
                    local distToPillar = (Vector3.new(currentPos.X, 0, currentPos.Z) - Vector3.new(cSpot.X, 0, cSpot.Z)).Magnitude
                    
                    if distToPillar > 3 then
                        -- มุ่งไปแท่งฟ้า
                        updateDebug("DirectTrace", currentPos, cSpot, Color3.fromRGB(0, 255, 255))
                        moveWithAvoidance(myHuman, cSpot)
                    else
                        -- ถึงแท่งฟ้า -> หันหน้าเข้าหาจุดศูนย์กลางตึก, เดินใส่, กระโดดรัวๆ บังคับปีน
                        local facePoint = activeMem.AreaCenter
                        for _, wp in ipairs(activeMem.PathArea) do
                            if (wp - cSpot).Magnitude > 2 then facePoint = wp; break end
                        end
                        
                        local pushDir = (Vector3.new(facePoint.X, myRoot.Position.Y, facePoint.Z) - myRoot.Position).Unit
                        if pushDir.Magnitude > 0 then
                            myRoot.CFrame = CFrame.lookAt(myRoot.Position, myRoot.Position + pushDir)
                        end
                        
                        myHuman:MoveTo(myRoot.Position + pushDir * 10)
                        forceJump(myHuman)
                        
                        local climbWp = computeVerticalClimbPath(currentPos, targetPos, myChar, target.Character)
                        if #climbWp > 0 then
                            currentWaypoints = climbWp
                            currentWaypointIndex = 1
                            isFollowingCustomPath = true
                        end
                    end
                    return -- ลัดคิวข้ามลอจิกอื่นทั้งหมด
                end

                -- =======================================================
                -- [2] โหมดลัดเลาะขอบ (Edge Tracing Phase)
                -- =======================================================
                if _G.TraceState.Active then
                    local st = _G.TraceState
                    
                    if st.Phase == "MoveToEdge" then
                        local flatTarget = Vector3.new(st.TargetPos.X, currentPos.Y, st.TargetPos.Z)
                        if (flatTarget - currentPos).Magnitude < 2 then
                            st.Phase = "Tracing"
                            st.StartPos = currentPos
                            st.Path = {currentPos}
                            table.insert(st.Visited, currentPos)
                        else
                            moveWithAvoidance(myHuman, flatTarget)
                        end
                        return
                    end

                    if st.Phase == "Tracing" then
                        local flatTarget = Vector3.new(st.TargetPos.X, currentPos.Y, st.TargetPos.Z)
                        if (flatTarget - currentPos).Magnitude < 2.5 then
                            table.insert(st.Visited, st.TargetPos)
                            table.insert(st.Path, st.TargetPos)
                            st.StepCount = st.StepCount + 1

                            local distToStart = (currentPos - st.StartPos).Magnitude
                            local isClosedLoop = (st.StepCount > 6 and distToStart < 10)
                            local reqH = math.max(20, targetPos.Y - currentPos.Y + 5)
                            local nextData = getNextEdgeTracingStep(currentPos, reqH, targetPos)

                            -- ถ้าบรรจบวงลูป, ทางตัน, หรือติดขัด (เกิน 40 ก้าว)
                            if isClosedLoop or not nextData or st.StepCount > 40 then
                                local finalClimbSpot = findAccurateClimbSpot(st.Path, targetPos)
                                table.insert(_G.BuildingMemories, {
                                    AreaCenter = st.StartPos, 
                                    ClimbSpot = finalClimbSpot, 
                                    PathArea = st.Path, 
                                    TargetY = targetPos.Y
                                })
                                st.Active = false
                                clearVisuals()
                            else
                                st.TargetPos = nextData.pos
                                st.LastMoveTick = os.clock()
                                
                                if debugEnabled then
                                    local py = Instance.new("Part")
                                    py.Name, py.Size, py.Position = "TraceTrail_Yellow", Vector3.new(1.5, 0.5, 1.5), st.TargetPos + Vector3.new(0, 2, 0)
                                    py.Anchored, py.CanCollide, py.CanQuery, py.Transparency, py.Color = true, false, false, 0.2, Color3.fromRGB(255, 255, 0)
                                    py.Material, py.Parent = Enum.Material.Neon, workspace.Terrain
                                end
                            end
                        else
                            moveWithAvoidance(myHuman, flatTarget)
                            if os.clock() - st.LastMoveTick > 5 then
                                -- ถ้าเดินค้างที่เดิมนานเกินไป ถือว่าติดขัด จบลูปจำพื้นที่ทันที
                                local finalClimbSpot = findAccurateClimbSpot(st.Path, targetPos)
                                table.insert(_G.BuildingMemories, {
                                    AreaCenter = st.StartPos, ClimbSpot = finalClimbSpot, PathArea = st.Path, TargetY = targetPos.Y
                                })
                                st.Active = false
                                clearVisuals()
                            end
                        end
                        return
                    end
                end

                -- =======================================================
                -- [3] Custom Pathing (เดินตามเวย์พอยต์ที่คำนวณไว้)
                -- =======================================================
                if isFollowingCustomPath and #currentWaypoints > 0 then
                    if (targetPos - lastTargetPos).Magnitude > 15 then
                        isFollowingCustomPath = false; currentWaypoints = {}
                    else
                        local wp = currentWaypoints[currentWaypointIndex]
                        if wp then
                            myHuman:MoveTo(wp.Position)
                            if wp.Action == Enum.PathWaypointAction.Jump then
                                if myHuman.FloorMaterial ~= Enum.Material.Air and not isClimbingState then 
                                    local lookPos = Vector3.new(wp.Position.X, myRoot.Position.Y, wp.Position.Z)
                                    if (lookPos - myRoot.Position).Magnitude > 0.1 then myRoot.CFrame = CFrame.lookAt(myRoot.Position, lookPos) end
                                    forceJump(myHuman) 
                                end
                            end
                            local dist2D = (Vector2.new(currentPos.X, currentPos.Z) - Vector2.new(wp.Position.X, wp.Position.Z)).Magnitude
                            local distY = math.abs(currentPos.Y - wp.Position.Y)
                            if dist2D < 3.5 and distY < 4.5 then
                                currentWaypointIndex = currentWaypointIndex + 1
                                lastMoveTick = os.clock() 
                            end
                            return 
                        else
                            isFollowingCustomPath = false; currentWaypoints = {}
                        end
                    end
                end

                -- =======================================================
                -- [4] ลำดับการตรวจสอบหลัก: มองเห็น -> ต่ำกว่า(Drop) -> เดินอ้อม -> เพดาน/เลาะ -> ปีน
                -- =======================================================
                if hDist > followDistance or math.abs(vDist) > 5 then
                    
                    local hasLineOfSight = false
                    local dirToTarget = (targetPos - currentPos).Unit
                    if dirToTarget.Magnitude > 0 then
                        local losRay = workspace:Raycast(currentPos + Vector3.new(0, 1.5, 0), dirToTarget * trueDist, rayParams)
                        if not losRay then hasLineOfSight = true end
                    end

                    -- [มองเห็น] -> พุ่งตรง
                    if hasLineOfSight and not isStuck then
                        isProbing = false; currentWaypoints = {}; isFollowingCustomPath = false
                        updateDebug("DirectTrace", currentPos, targetPos, Color3.fromRGB(0, 255, 0)) 
                        moveWithAvoidance(myHuman, targetPos)
                        
                    -- [มองไม่เห็น & เราสูงกว่า] -> Drop Mode
                    elseif vDist < -5 and not isStuck then
                        local flatTargetPos = Vector3.new(targetPos.X, currentPos.Y, targetPos.Z)
                        isProbing = false; currentWaypoints = {}; isFollowingCustomPath = false
                        updateDebug("DirectTrace", currentPos, flatTargetPos, Color3.fromRGB(255, 128, 0))
                        moveWithAvoidance(myHuman, flatTargetPos)

                        local flatDir = (flatTargetPos - currentPos).Unit
                        if flatDir.Magnitude > 0 then
                            local chestRay = workspace:Raycast(currentPos, flatDir * 4, rayParams)
                            local floorDropRay = workspace:Raycast(currentPos + (flatDir * 4) + Vector3.new(0, 1, 0), Vector3.new(0, -10, 0), rayParams)
                            if chestRay and chestRay.Distance < 3 and not floorDropRay then forceJump(myHuman) end
                        end
                        
                    -- [โหมดเดินอ้อม & ตรวจเพดาน & เลาะขอบ & ปีน]
                    else
                        if os.clock() - lastComputeTime > 0.5 or (targetPos - lastTargetPos).Magnitude > 5 then
                            lastComputeTime = os.clock()
                            lastTargetPos = targetPos

                            local testWaypoints = findPathWithFallback(currentPos, targetPos)
                            
                            -- เดินอ้อมปกติ
                            if #testWaypoints > 0 and not isStuck then
                                currentWaypoints = testWaypoints
                                currentWaypointIndex = 2
                                isFollowingCustomPath = true
                                if debugEnabled then
                                    clearVisuals()
                                    for _, wp in ipairs(currentWaypoints) do
                                        local p = Instance.new("Part"); p.Name = "WP_Debug"; p.Size = Vector3.new(1.2, 1.2, 1.2); p.Position = wp.Position
                                        p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.Transparency = 0.4
                                        p.Color = Color3.fromRGB(0, 150, 255); p.Material = Enum.Material.Neon; p.Parent = workspace.Terrain
                                    end
                                end
                            else
                                -- ถ้าติดขัด -> เลาะขอบ / ปีน
                                local canUseCustomPaths = (_G.CustomPathFailTick == nil) or (os.clock() - _G.CustomPathFailTick > 4)

                                if canUseCustomPaths then
                                    local reqH = math.max(20, targetPos.Y - currentPos.Y + 5)
                                    
                                    if checkCeilingAround(currentPos, reqH) then
                                        local edgeStart = crossScanForEdge(currentPos, reqH, targetPos)
                                        if edgeStart then
                                            _G.TraceState.Active = true
                                            _G.TraceState.Phase = "MoveToEdge"
                                            _G.TraceState.TargetPos = edgeStart
                                            _G.TraceState.Visited = {}
                                            _G.TraceState.Path = {}
                                            _G.TraceState.StepCount = 0
                                            _G.TraceState.LastMoveTick = os.clock()
                                            clearVisuals()
                                        end
                                    else
                                        currentWaypoints = computeVerticalClimbPath(currentPos, targetPos, myChar, target.Character)
                                        if #currentWaypoints > 0 then
                                            isFollowingCustomPath = true; currentWaypointIndex = 1
                                        end
                                    end
                                else
                                    isProbing = false; currentWaypoints = {}; isFollowingCustomPath = false
                                    moveWithAvoidance(myHuman, targetPos)
                                end
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
