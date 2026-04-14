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
    StepCount = 0,
    Visited = {},
    BestClimbSpot = nil,
    AreaBounds = {Min = nil, Max = nil},
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
        -- สร้าง Area สีเขียวจางๆ
        if mem.Bounds then
            local area = Instance.new("Part")
            area.Name = "MemArea_"..i
            local sizeX = mem.Bounds.Max.X - mem.Bounds.Min.X
            local sizeZ = mem.Bounds.Max.Z - mem.Bounds.Min.Z
            area.Size = Vector3.new(sizeX, 50, sizeZ)
            area.Position = Vector3.new(mem.Bounds.Min.X + sizeX/2, mem.ClimbSpot.Y + 25, mem.Bounds.Min.Z + sizeZ/2)
            area.Anchored, area.CanCollide, area.CanQuery = true, false, false
            area.Transparency, area.Color = 0.8, Color3.fromRGB(0, 255, 0)
            area.Material, area.Parent = Enum.Material.Neon, workspace.Terrain
        end

        -- แท่งสีฟ้า
        local pillar = Instance.new("Part")
        pillar.Name = "MemPillar_"..i
        local targetY = mem.TargetY or (mem.ClimbSpot.Y + 50)
        local h = math.max(10, targetY - mem.ClimbSpot.Y)
        pillar.Size = Vector3.new(2, h, 2)
        pillar.Position = mem.ClimbSpot + Vector3.new(0, h/2, 0)
        pillar.Anchored, pillar.CanCollide, pillar.CanQuery = true, false, false
        pillar.Transparency, pillar.Material = 0.4, Enum.Material.Neon
        pillar.Color = Color3.fromRGB(0, 255, 255) 
        pillar.Parent = workspace.Terrain
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

-- ตรวจสอบว่าตัวผู้เล่นอยู่ใน Area สีเขียวหรือไม่
local function isInsideMemoryArea(pos)
    for _, mem in ipairs(_G.BuildingMemories) do
        if mem.Bounds then
            local margin = 5 -- ขยายระยะนิดหน่อยให้เซนเซอร์ทำงานง่ายขึ้น
            if pos.X >= mem.Bounds.Min.X - margin and pos.X <= mem.Bounds.Max.X + margin and
               pos.Z >= mem.Bounds.Min.Z - margin and pos.Z <= mem.Bounds.Max.Z + margin then
                return mem
            end
        end
    end
    return nil
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
            if not upRay then table.insert(endpoints, checkPos); break end
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
                        break
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

    if debugEnabled and bestStep then
        local py = Instance.new("Part")
        py.Name, py.Size, py.Position = "TraceTrail_Yellow", Vector3.new(1.5, 0.5, 1.5), bestStep + Vector3.new(0, 2, 0)
        py.Anchored, py.CanCollide, py.CanQuery, py.Transparency, py.Color = true, false, false, 0.2, Color3.fromRGB(255, 255, 0)
        py.Material, py.Parent = Enum.Material.Neon, workspace.Terrain
    end

    return bestStep and {pos = bestStep} or nil
end

local function findPathWithFallback(startPos, targetPos)
    local path = PathfindingService:CreatePath({AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 4})
    path:ComputeAsync(startPos, targetPos)
    if path.Status == Enum.PathStatus.Success then return path:GetWaypoints() end
    
    local searchRadii = {5, 10, 15}
    local angles = {0, 45, -45, 90, -90, 135, -135, 180}
    for _, r in ipairs(searchRadii) do
        for _, ang in ipairs(angles) do
            local offset = CFrame.Angles(0, math.rad(ang), 0) * Vector3.new(0, 0, r)
            local testPos = targetPos + offset
            local floorRay = workspace:Raycast(testPos + Vector3.new(0, 10, 0), Vector3.new(0, -50, 0), rayParams)
            if floorRay then
                path:ComputeAsync(startPos, floorRay.Position)
                if path.Status == Enum.PathStatus.Success then return path:GetWaypoints() end
            end
        end
    end
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
    clearVisuals()
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

                drawMemoryPillars()

                local isStuck = false
                if (currentPos - lastPosition).Magnitude < 1.0 then 
                    if os.clock() - lastMoveTick > 1.5 then 
                        isStuck = true
                        if isFollowingCustomPath or _G.TraceState.Active then
                            _G.CustomPathFailTick = os.clock() 
                            isFollowingCustomPath = false
                            -- ถ้าติดในตอนเทรซ ให้มันหาระยะใหม่
                            if _G.TraceState.Phase ~= "Tracing" then _G.TraceState.Active = false end
                            currentWaypoints = {}
                        end
                    end
                else
                    lastPosition = currentPos
                    lastMoveTick = os.clock()
                end

                -- =======================================================
                -- [1] ตรวจสอบระบบความจำ (Green Area Box Check) ก่อนลอจิกอื่น
                -- =======================================================
                local activeMemory = isInsideMemoryArea(currentPos)
                if activeMemory then
                    local distToPillar = (currentPos - activeMemory.ClimbSpot).Magnitude
                    if distToPillar > 3.5 then
                        -- มุ่งหน้าไปหาแท่งฟ้า
                        updateDebug("DirectTrace", currentPos, activeMemory.ClimbSpot, Color3.fromRGB(0, 255, 255))
                        moveWithAvoidance(myHuman, activeMemory.ClimbSpot)
                    else
                        -- [ดันกำแพง Force Climb] หันหน้าเข้าหาตึก แล้วเดินชนรัวๆ
                        local dirToCenter = (Vector3.new(activeMemory.AreaCenter.X, myRoot.Position.Y, activeMemory.AreaCenter.Z) - myRoot.Position).Unit
                        if dirToCenter.Magnitude > 0 then
                            myRoot.CFrame = CFrame.lookAt(myRoot.Position, myRoot.Position + dirToCenter)
                            myHuman:MoveTo(myRoot.Position + (dirToCenter * 5)) -- บังคับเดินพุ่งเข้ากำแพงไม่หยุด
                            forceJump(myHuman)
                        end
                    end
                    return -- หลุดลูป ไม่ต้องทำ Pathfind หรือคำนวณอื่น
                end

                -- =======================================================
                -- [2] โหมดลัดเลาะขอบ (Edge Tracing Phase - Closed Loop)
                -- =======================================================
                if _G.TraceState.Active then
                    local st = _G.TraceState
                    
                    if st.Phase == "MoveToEdge" then
                        local flatTarget = Vector3.new(st.TargetPos.X, currentPos.Y, st.TargetPos.Z)
                        if (flatTarget - currentPos).Magnitude < 2 then
                            st.Phase = "Tracing"
                            st.StartPos = currentPos
                            table.insert(st.Visited, currentPos)
                        else
                            moveWithAvoidance(myHuman, flatTarget)
                        end
                        return
                    end

                    if st.Phase == "Tracing" then
                        local flatTarget = Vector3.new(st.TargetPos.X, currentPos.Y, st.TargetPos.Z)
                        if (flatTarget - currentPos).Magnitude < 2 then
                            table.insert(st.Visited, st.TargetPos)
                            st.StepCount = st.StepCount + 1

                            -- เช็คการปิดลูป (เดินวนกลับมาจุดแรก)
                            if st.StepCount > 10 and (currentPos - st.StartPos).Magnitude < 5 then
                                st.Phase = "CalculatingLoop"
                            else
                                local reqH = math.max(20, targetPos.Y - currentPos.Y + 5)
                                local nextData = getNextEdgeTracingStep(currentPos, reqH, targetPos)
                                if nextData then
                                    st.TargetPos = nextData.pos
                                    st.LastMoveTick = os.clock()
                                else
                                    -- วนทางตัน พยายามปิดลูป
                                    st.Phase = "CalculatingLoop"
                                end
                            end
                        else
                            moveWithAvoidance(myHuman, flatTarget)
                            if os.clock() - st.LastMoveTick > 5 then st.Phase = "CalculatingLoop" end
                        end
                        return
                    end

                    if st.Phase == "CalculatingLoop" then
                        -- หาจุด Min/Max เพื่อสร้าง Area Box
                        local minX, minZ = math.huge, math.huge
                        local maxX, maxZ = -math.huge, -math.huge
                        local sumX, sumZ = 0, 0
                        for _, vPos in ipairs(st.Visited) do
                            if vPos.X < minX then minX = vPos.X end
                            if vPos.Z < minZ then minZ = vPos.Z end
                            if vPos.X > maxX then maxX = vPos.X end
                            if vPos.Z > maxZ then maxZ = vPos.Z end
                            sumX = sumX + vPos.X; sumZ = sumZ + vPos.Z
                        end
                        st.AreaBounds = {Min = Vector3.new(minX, 0, minZ), Max = Vector3.new(maxX, 0, maxZ)}
                        local centerPos = Vector3.new(sumX / #st.Visited, currentPos.Y, sumZ / #st.Visited)

                        -- หาจุดที่ดีที่สุดเพื่อตั้งแท่งสีฟ้า (พุ่งชนกำแพงเช็ค Wall Normal เพื่อความแม่นยำ)
                        local bestSpot = nil
                        local bestScore = math.huge
                        local baseDir = (Vector3.new(targetPos.X, 0, targetPos.Z) - Vector3.new(centerPos.X, 0, centerPos.Z)).Unit
                        
                        -- ยิง Ray หาตึกจากจุดกลาง
                        for _, vPos in ipairs(st.Visited) do
                            local lookCenter = (centerPos - vPos).Unit
                            local wallCheck = workspace:Raycast(vPos + Vector3.new(0,2,0), lookCenter * 15, rayParams)
                            if wallCheck then
                                -- คำนวณจุดยืนที่ถูกต้อง (ถอยออกมาจากกำแพง 1.5 Studs ไม่ให้จมดิน/กำแพง)
                                local climbPoint = wallCheck.Position + (wallCheck.Normal * 1.5)
                                climbPoint = Vector3.new(climbPoint.X, vPos.Y, climbPoint.Z)
                                
                                local d = (climbPoint - targetPos).Magnitude
                                if d < bestScore then
                                    bestScore = d
                                    bestSpot = climbPoint
                                end
                            end
                        end

                        if bestSpot then
                            -- บันทึก Memory สร้าง Area และเสา
                            table.insert(_G.BuildingMemories, {
                                Bounds = st.AreaBounds, 
                                AreaCenter = centerPos, 
                                ClimbSpot = bestSpot, 
                                TargetY = targetPos.Y
                            })
                            st.Active = false
                            clearVisuals()
                        else
                            st.Active = false
                        end
                        return
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
                        updateDebug("DirectTrace", currentPos, targetPos, Color3.fromRGB(0, 255, 0)) 
                        moveWithAvoidance(myHuman, targetPos)
                        
                    elseif vDist < -5 and not isStuck then
                        local flatTargetPos = Vector3.new(targetPos.X, currentPos.Y, targetPos.Z)
                        isProbing = false
                        currentWaypoints = {}
                        updateDebug("DirectTrace", currentPos, flatTargetPos, Color3.fromRGB(255, 128, 0))
                        moveWithAvoidance(myHuman, flatTargetPos)

                    else
                        if os.clock() - lastComputeTime > 0.5 or (targetPos - lastTargetPos).Magnitude > 5 then
                            lastComputeTime = os.clock()
                            lastTargetPos = targetPos

                            local testWaypoints = findPathWithFallback(currentPos, targetPos)
                            if #testWaypoints > 0 and not isStuck then
                                currentWaypoints = testWaypoints
                                currentWaypointIndex = 2
                                isFollowingCustomPath = true
                            else
                                local canUseCustomPaths = (_G.CustomPathFailTick == nil) or (os.clock() - _G.CustomPathFailTick > 4)
                                if canUseCustomPaths then
                                    local requiredHeightCheck = math.max(20, targetPos.Y - currentPos.Y + 5)
                                    if checkCeilingAround(currentPos, requiredHeightCheck) then
                                        -- เริ่มลัดเลาะ
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
                                        -- ที่โล่ง หาวิธีปีนง่ายๆ
                                        moveWithAvoidance(myHuman, targetPos)
                                    end
                                else
                                    moveWithAvoidance(myHuman, targetPos)
                                end
                            end
                        end

                        if isFollowingCustomPath and #currentWaypoints > 0 then
                            local wp = currentWaypoints[currentWaypointIndex]
                            if wp then
                                myHuman:MoveTo(wp.Position)
                                if wp.Action == Enum.PathWaypointAction.Jump and myHuman.FloorMaterial ~= Enum.Material.Air then forceJump(myHuman) end
                                local dist2D = (Vector2.new(currentPos.X, currentPos.Z) - Vector2.new(wp.Position.X, wp.Position.Z)).Magnitude
                                if dist2D < 3.5 then
                                    currentWaypointIndex = currentWaypointIndex + 1
                                    lastMoveTick = os.clock() 
                                end
                            else
                                isFollowingCustomPath = false
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
