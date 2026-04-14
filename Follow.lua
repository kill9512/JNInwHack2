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
    FirstPos = nil,
    TargetPos = nil,
    StartPos = nil,
    StepCount = 0,
    Visited = {},
    LastMoveTick = 0,
    AreaCenter = nil,
    AreaSize = nil
}

-- --- Debug Visualization ---
local function clearVisuals()
    for _, v in pairs(workspace.Terrain:GetChildren()) do
        if v.Name == "WP_Debug" or v.Name == "DirectTrace" or v.Name == "ProbeTrace" 
        or string.find(v.Name, "Debug_Edge") or string.find(v.Name, "Debug_Ceil") then 
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
        -- แท่งสีฟ้า
        local pName = "MemPillar_"..i
        local p = Instance.new("Part")
        p.Name = pName
        local targetY = mem.TargetY or (mem.ClimbSpot.Y + 50)
        local h = math.max(10, targetY - mem.ClimbSpot.Y)
        p.Size = Vector3.new(2, h, 2)
        p.Position = mem.ClimbSpot + Vector3.new(0, h/2, 0)
        p.Anchored, p.CanCollide, p.CanQuery = true, false, false
        p.Transparency, p.Material = 0.4, Enum.Material.Neon
        p.Color = Color3.fromRGB(0, 255, 255) 
        p.Parent = workspace.Terrain

        -- Area สีเขียวจางๆ
        if mem.AreaCenter and mem.AreaSize then
            local aName = "MemArea_"..i
            local a = Instance.new("Part")
            a.Name = aName
            a.Size = mem.AreaSize
            a.Position = mem.AreaCenter
            a.Anchored, a.CanCollide, a.CanQuery = true, false, false
            a.Transparency, a.Material = 0.85, Enum.Material.Neon
            a.Color = Color3.fromRGB(0, 255, 0)
            a.Parent = workspace.Terrain
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

local function crossScanForEdge(startPos, maxCheckHeight, targetPos)
    local step = 6
    local maxRadius = 60
    local dirs = { Vector3.new(1,0,0), Vector3.new(-1,0,0), Vector3.new(0,0,1), Vector3.new(0,0,-1) }
    local endpoints = {}

    for _, dir in ipairs(dirs) do
        for d = step, maxRadius, step do
            local checkPos = startPos + (dir * d)
            local rayOrigin = checkPos + Vector3.new(0, 1, 0)
            if not workspace:Raycast(rayOrigin, Vector3.new(0, maxCheckHeight, 0), rayParams) then
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
    local visualGreens = {}

    for _, offset in ipairs(neighbors) do
        local testPos = currentPos + offset
        
        local visited = false
        for _, v in ipairs(_G.TraceState.Visited) do
            if (v - testPos).Magnitude < 3 then visited = true; break end
        end

        if not visited then
            local isWalkable = not workspace:Raycast(testPos + Vector3.new(0,1,0), Vector3.new(0, maxCheckHeight, 0), rayParams)
            if isWalkable then
                local isNearWall = false
                for _, subOff in ipairs(neighbors) do
                    local wallCheckPos = testPos + subOff
                    if workspace:Raycast(wallCheckPos + Vector3.new(0,1,0), Vector3.new(0, maxCheckHeight, 0), rayParams) then 
                        isNearWall = true 
                        table.insert(visualGreens, wallCheckPos)
                    end
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

    if debugEnabled then
        for _, gPos in ipairs(visualGreens) do
            local pg = Instance.new("Part")
            pg.Name, pg.Size, pg.Position = "TraceTrail_Green", Vector3.new(1.5, 0.5, 1.5), gPos + Vector3.new(0, 2, 0)
            pg.Anchored, pg.CanCollide, pg.CanQuery, pg.Transparency, pg.Color = true, false, false, 0.4, Color3.fromRGB(0, 255, 0)
            pg.Material, pg.Parent = Enum.Material.Neon, workspace.Terrain
        end
        if bestStep then
            local py = Instance.new("Part")
            py.Name, py.Size, py.Position = "TraceTrail_Yellow", Vector3.new(1.5, 0.5, 1.5), bestStep + Vector3.new(0, 2, 0)
            py.Anchored, py.CanCollide, py.CanQuery, py.Transparency, py.Color = true, false, false, 0.2, Color3.fromRGB(255, 255, 0)
            py.Material, py.Parent = Enum.Material.Neon, workspace.Terrain
        end
    end

    return bestStep and {pos = bestStep} or nil
end

local function findWallDirection(pos)
    local dirs = {Vector3.new(1,0,0), Vector3.new(-1,0,0), Vector3.new(0,0,1), Vector3.new(0,0,-1)}
    for _, d in ipairs(dirs) do
        local ray = workspace:Raycast(pos + Vector3.new(0, 1, 0), d * 8, rayParams)
        if ray then return d, ray end
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
    for _, v in pairs(workspace.Terrain:GetChildren()) do
        if string.find(v.Name, "TraceTrail_") then v:Destroy() end
    end
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
                            _G.TraceState.Active = false
                            currentWaypoints = {}
                        end
                    end
                else
                    lastPosition = currentPos
                    lastMoveTick = os.clock()
                end

                -- =======================================================
                -- [0] ตรวจเช็คพื้นที่ความจำ (Area Zone) - สำคัญสูงสุด
                -- หากหลงเข้ามาใน Area สีเขียว ให้พุ่งไปที่แท่งสีฟ้าแล้วบังคับชนกำแพง
                -- =======================================================
                local activeMemory = nil
                for _, mem in ipairs(_G.BuildingMemories) do
                    if mem.AreaCenter and mem.AreaSize then
                        local dx = math.abs(currentPos.X - mem.AreaCenter.X)
                        local dz = math.abs(currentPos.Z - mem.AreaCenter.Z)
                        if dx < mem.AreaSize.X/2 and dz < mem.AreaSize.Z/2 then
                            activeMemory = mem
                            break
                        end
                    end
                end

                if activeMemory then
                    local flatPillarPos = Vector3.new(activeMemory.ClimbSpot.X, currentPos.Y, activeMemory.ClimbSpot.Z)
                    local distToPillar = (flatPillarPos - currentPos).Magnitude

                    if distToPillar < 3.5 then
                        -- หันหน้าเข้ากำแพง แล้วบังคับดัน (Move ค้างไว้)
                        local lookPos = myRoot.Position + activeMemory.ClimbDir * 10
                        myRoot.CFrame = CFrame.lookAt(myRoot.Position, Vector3.new(lookPos.X, myRoot.Position.Y, lookPos.Z))
                        myHuman:Move(activeMemory.ClimbDir, false)
                        forceJump(myHuman)
                    else
                        -- วิ่งไปหาแท่งสีฟ้า
                        moveWithAvoidance(myHuman, flatPillarPos)
                    end
                    return -- ตัดจบ Loop ตรงนี้เลย
                end

                -- =======================================================
                -- [โหมดลัดเลาะขอบบรรจบรอบวง (Edge Tracing Phase)]
                -- =======================================================
                if _G.TraceState.Active then
                    local st = _G.TraceState
                    local flatTarget = Vector3.new(st.TargetPos.X, currentPos.Y, st.TargetPos.Z)
                    local distToTarget = (flatTarget - currentPos).Magnitude
                    
                    if distToTarget < 2 then
                        table.insert(st.Visited, st.TargetPos)
                        st.StepCount = st.StepCount + 1

                        if st.Phase == "MoveToEdge" then
                            st.Phase = "Tracing"
                            st.StartPos = currentPos
                            st.FirstPos = st.TargetPos -- จำบล็อกสีเหลืองแรก
                        
                        elseif st.Phase == "Tracing" then
                            -- เช็คว่าเดินมาบรรจบกับบล็อกแรกหรือยัง (Loop Completed)
                            if st.StepCount > 10 and (currentPos - st.FirstPos).Magnitude < 10 then
                                st.Phase = "FindClimb"
                                st.StepCount = 1

                                -- คำนวณขอบเขตและวาด Area สีเขียว
                                local minX, maxX = math.huge, -math.huge
                                local minZ, maxZ = math.huge, -math.huge
                                for _, v in ipairs(st.Visited) do
                                    if v.X < minX then minX = v.X end
                                    if v.X > maxX then maxX = v.X end
                                    if v.Z < minZ then minZ = v.Z end
                                    if v.Z > maxZ then maxZ = v.Z end
                                end
                                local cx = (minX + maxX) / 2
                                local cz = (minZ + maxZ) / 2
                                st.AreaCenter = Vector3.new(cx, st.FirstPos.Y + 1, cz)
                                st.AreaSize = Vector3.new(math.max(15, maxX - minX + 10), 50, math.max(15, maxZ - minZ + 10))
                            else
                                -- เดินเลาะหาทางไปเรื่อยๆ
                                local reqH = math.max(20, targetPos.Y - currentPos.Y + 5)
                                local nextData = getNextEdgeTracingStep(currentPos, reqH, targetPos)
                                if nextData then
                                    st.TargetPos = nextData.pos
                                    st.LastMoveTick = os.clock()
                                else
                                    st.Active = false
                                end
                            end
                        
                        elseif st.Phase == "FindClimb" then
                            -- เดินย้อนตามจุดเดิมเพื่อหาจุด Mark แท่งสีฟ้า
                            local scanPos = st.Visited[st.StepCount]
                            if scanPos then
                                st.TargetPos = scanPos
                                st.LastMoveTick = os.clock()

                                -- เช็คชี้ขึ้นบนดูว่าจุดนี้ไต่ได้ไหม
                                local reqH = targetPos.Y - currentPos.Y
                                if reqH < 0 then reqH = 5 end
                                local upRay = workspace:Raycast(currentPos + Vector3.new(0, 1, 0), Vector3.new(0, reqH, 0), rayParams)
                                local canReachHeight = not upRay 

                                local wallDir, wallRay = findWallDirection(currentPos)

                                -- พอซนเจอจุดที่ไต่ได้
                                if canReachHeight and wallRay then
                                    local contactPoint = wallRay.Position
                                    local wallNormal = wallRay.Normal
                                    -- ดันจุด Mark ออกมาจากกำแพงนิดหน่อย (1.5 Stud) ให้พอดีตัว
                                    local exactClimbSpot = contactPoint + (wallNormal * 1.5)
                                    local pushDir = -wallNormal -- ทิศทางที่จะบังคับเดินชน

                                    table.insert(_G.BuildingMemories, {
                                        AreaCenter = st.AreaCenter,
                                        AreaSize = st.AreaSize,
                                        ClimbSpot = exactClimbSpot,
                                        ClimbDir = pushDir,
                                        TargetY = targetPos.Y
                                    })

                                    st.Active = false
                                    currentWaypoints = {}
                                else
                                    st.StepCount = st.StepCount + 1
                                    if st.StepCount > #st.Visited then
                                        st.Active = false
                                    end
                                end
                            else
                                st.Active = false
                            end
                        end
                    else
                        moveWithAvoidance(myHuman, flatTarget)
                        if os.clock() - st.LastMoveTick > 6 then st.Active = false end
                    end
                    return
                end
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
                                if myHuman.FloorMaterial ~= Enum.Material.Air and not isClimbingState then 
                                    local lookPos = Vector3.new(wp.Position.X, myRoot.Position.Y, wp.Position.Z)
                                    if (lookPos - myRoot.Position).Magnitude > 0.1 then
                                        myRoot.CFrame = CFrame.lookAt(myRoot.Position, lookPos)
                                    end
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
                            isFollowingCustomPath = false
                            currentWaypoints = {}
                        end
                    end
                end

                -- =======================================================
                -- ลำดับการตรวจสอบหลัก (General Navigation)
                -- =======================================================
                if hDist > followDistance or math.abs(vDist) > 5 then
                    
                    local hasLineOfSight = false
                    local dirToTarget = (targetPos - currentPos).Unit
                    if dirToTarget.Magnitude > 0 then
                        local losRay = workspace:Raycast(currentPos + Vector3.new(0, 1.5, 0), dirToTarget * trueDist, rayParams)
                        if not losRay then hasLineOfSight = true end
                    end

                    if hasLineOfSight and not isStuck then
                        isProbing = false
                        currentWaypoints = {}
                        isFollowingCustomPath = false
                        updateDebug("DirectTrace", currentPos, targetPos, Color3.fromRGB(0, 255, 0)) 
                        moveWithAvoidance(myHuman, targetPos)
                        
                    elseif vDist < -5 and not isStuck then
                        local flatTargetPos = Vector3.new(targetPos.X, currentPos.Y, targetPos.Z)
                        isProbing = false
                        currentWaypoints = {}
                        isFollowingCustomPath = false
                        updateDebug("DirectTrace", currentPos, flatTargetPos, Color3.fromRGB(255, 128, 0))
                        
                        moveWithAvoidance(myHuman, flatTargetPos)

                        local flatDir = (flatTargetPos - currentPos).Unit
                        if flatDir.Magnitude > 0 then
                            local chestRay = workspace:Raycast(currentPos, flatDir * 4, rayParams)
                            local floorDropRay = workspace:Raycast(currentPos + (flatDir * 4) + Vector3.new(0, 1, 0), Vector3.new(0, -10, 0), rayParams)
                            if chestRay and chestRay.Distance < 3 and not floorDropRay then
                                forceJump(myHuman)
                            end
                        end
                        
                    else
                        if os.clock() - lastComputeTime > 0.5 or (targetPos - lastTargetPos).Magnitude > 5 then
                            lastComputeTime = os.clock()
                            lastTargetPos = targetPos

                            local testWaypoints = findPathWithFallback(currentPos, targetPos)
                            
                            if #testWaypoints > 0 and not isStuck then
                                currentWaypoints = testWaypoints
                                currentWaypointIndex = 2
                                isFollowingCustomPath = true
                                if debugEnabled then
                                    clearVisuals()
                                    for _, wp in ipairs(currentWaypoints) do
                                        local p = Instance.new("Part")
                                        p.Name, p.Size, p.Position = "WP_Debug", Vector3.new(1.2, 1.2, 1.2), wp.Position
                                        p.Anchored, p.CanCollide, p.CanQuery, p.Transparency = true, false, false, 0.4
                                        p.Color, p.Material = Color3.fromRGB(0, 150, 255), Enum.Material.Neon
                                        p.Parent = workspace.Terrain
                                    end
                                end
                            else
                                -- หาทางเดินปกติไม่ได้ หรือติดขัด -> เลาะขอบ
                                local canUseCustomPaths = (_G.CustomPathFailTick == nil) or (os.clock() - _G.CustomPathFailTick > 4)

                                if canUseCustomPaths then
                                    local requiredHeightCheck = math.max(20, targetPos.Y - currentPos.Y + 5)
                                    
                                    if checkCeilingAround(currentPos, requiredHeightCheck) then
                                        local edgeStart = crossScanForEdge(currentPos, requiredHeightCheck, targetPos)
                                        if edgeStart then
                                            _G.TraceState.Active = true
                                            _G.TraceState.Phase = "MoveToEdge"
                                            _G.TraceState.TargetPos = edgeStart
                                            _G.TraceState.Visited = {}
                                            _G.TraceState.StepCount = 0
                                            _G.TraceState.LastMoveTick = os.clock()
                                        end
                                    else
                                        -- บังเอิญเดินมาตรงที่ไม่มีเพดาน ลองเดินไปหาที่ใกล้ๆ เพื่อบังคับปีน
                                        isProbing = false
                                        currentWaypoints = {}
                                        isFollowingCustomPath = false
                                        moveWithAvoidance(myHuman, targetPos)
                                    end
                                else
                                    isProbing = false
                                    currentWaypoints = {}
                                    isFollowingCustomPath = false
                                    moveWithAvoidance(myHuman, targetPos)
                                end
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
