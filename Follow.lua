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
    LastMoveTick = 0
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
        if string.find(v.Name, "MemPillar_") or string.find(v.Name, "MemPath_") then v:Destroy() end
    end
    if not debugEnabled then return end
    
    for i, mem in ipairs(_G.BuildingMemories) do
        -- วาดแท่งสีฟ้า (Blue Pillar) ให้ความสูงเป๊ะตามเป้าหมาย
        local name = "MemPillar_"..i
        local p = Instance.new("Part")
        p.Name = name
        
        local targetY = mem.TargetY or mem.ClimbSpot.Y
        local h = math.max(1, targetY - mem.ClimbSpot.Y) -- แก้ให้ความสูงเป๊ะ ไม่บวกเพิ่มมั่ว
        
        p.Size = Vector3.new(2, h, 2)
        p.Position = mem.ClimbSpot + Vector3.new(0, h/2, 0)
        p.Anchored, p.CanCollide, p.CanQuery = true, false, false
        p.Transparency, p.Material = 0.4, Enum.Material.Neon
        p.Color = Color3.fromRGB(0, 255, 255) 
        p.Parent = workspace.Terrain

        -- วาดพื้นที่ Path สีเขียว (Green Area) ตัวแทนพื้นที่สำรวจแล้ว
        if mem.TracePath then
            for j, pData in ipairs(mem.TracePath) do
                local pp = Instance.new("Part")
                pp.Name = "MemPath_"..i.."_"..j
                pp.Size = Vector3.new(6, 0.5, 6)
                pp.Position = pData + Vector3.new(0, 0.5, 0)
                pp.Anchored, pp.CanCollide, pp.CanQuery = true, false, false
                pp.Transparency, pp.Color = 0.6, Color3.fromRGB(0, 255, 0)
                pp.Material, pp.Parent = Enum.Material.Neon, workspace.Terrain
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
        if d < bestDist then
            bestDist = d
            bestEdge = edgePos
        end
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
            -- เช็คให้เข้มงวดขึ้น เพื่อป้องกันการเดินถอยหลัง
            if (v - testPos).Magnitude < 4.5 then visited = true; break end
        end

        if not visited then
            -- ต้องเดินได้ (ไม่มีเพดานกดทับ)
            local isWalkable = not workspace:Raycast(testPos + Vector3.new(0,1,0), Vector3.new(0, maxCheckHeight, 0), rayParams)
            
            if isWalkable then
                -- ต้องมีตึก/กำแพงอยู่ติดกัน (เพื่อเลาะขอบ ไม่เดินออกไปที่โล่ง)
                local isNearWall = false
                for _, subOff in ipairs(neighbors) do
                    local wallCheckPos = testPos + subOff
                    if workspace:Raycast(wallCheckPos + Vector3.new(0,1,0), Vector3.new(0, maxCheckHeight, 0), rayParams) then 
                        isNearWall = true; break
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
    for _, v in pairs(workspace.Terrain:GetChildren()) do
        if string.find(v.Name, "TraceTrail_") then v:Destroy() end
    end
end)

-- โคลนตารางสำหรับย้ายค่า Memory
local function cloneTable(t)
    local newT = {}
    for i, v in ipairs(t) do newT[i] = v end
    return newT
end

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
                -- [ระบบวิเคราะห์พื้นที่ Green Area Override] 
                -- หากเข้าเขตพื้นที่สีเขียวที่บันทึกไว้ ให้มุ่งหน้าไปแท่งสีฟ้าแล้วปีนทันที
                -- =======================================================
                local activeMem = nil
                for _, mem in ipairs(_G.BuildingMemories) do
                    if mem.TracePath then
                        for _, wp in ipairs(mem.TracePath) do
                            -- ถ้าระยะห่างแบบ 3D (รวมความสูง) อยู่ในเกณฑ์ แสดงว่าเราอยู่ในพื้นที่สีเขียว
                            if (currentPos - wp).Magnitude < 8 then
                                activeMem = mem
                                break
                            end
                        end
                    end
                    if activeMem then break end
                end

                if activeMem then
                    _G.TraceState.Active = false
                    isProbing = false
                    currentWaypoints = {}
                    isFollowingCustomPath = false
                    
                    local pPos = activeMem.ClimbSpot
                    local dToPillar = (Vector3.new(currentPos.X, pPos.Y, currentPos.Z) - pPos).Magnitude
                    
                    if dToPillar < 4.5 then
                        -- ถึงแท่งสีฟ้าแล้ว: หันหน้าเข้าหาจุดศูนย์กลางของพื้นที่สีเขียว (หันเข้ากำแพง)
                        local lookPos = Vector3.new(activeMem.AreaCenter.X, myRoot.Position.Y, activeMem.AreaCenter.Z)
                        if (lookPos - myRoot.Position).Magnitude > 0.1 then
                            myRoot.CFrame = CFrame.lookAt(myRoot.Position, lookPos)
                        end
                        -- เดินอัดกำแพงอย่างไม่หยุดยั้งพร้อมกระโดดเพื่อไต่ขึ้นไป
                        myHuman:MoveTo(activeMem.AreaCenter)
                        forceJump(myHuman)
                    else
                        -- เดินเข้าหาแท่งสีฟ้า
                        moveWithAvoidance(myHuman, pPos)
                    end
                    return -- จบการทำงานลอจิกอื่นๆ ไปเลย เพราะกำลังปีนโหมดลัดเลาะ
                end

                -- =======================================================
                -- [โหมดลัดเลาะขอบ (Edge Tracing Phase)]
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
                        end

                        if st.Phase == "Tracing" then
                            local reqH = math.max(20, targetPos.Y - currentPos.Y + 5)
                            
                            -- ตรวจสอบว่าเดินลัดเลาะจนกลับมาชนบล็อกแรกๆ หรือยัง (Loop Closed)
                            local isLoopClosed = false
                            if st.StepCount > 10 then
                                for i = 1, math.min(3, #st.Visited) do
                                    if (currentPos - st.Visited[i]).Magnitude < 8 then
                                        isLoopClosed = true; break
                                    end
                                end
                            end

                            -- ถ้าครบลูป หรือเดินจนตันแล้ว ให้เซฟพื้นที่เขียวและแท่งสีฟ้า
                            if isLoopClosed or st.StepCount > 40 then
                                local sumX, sumZ = 0, 0
                                for _, v in ipairs(st.Visited) do
                                    sumX = sumX + v.X
                                    sumZ = sumZ + v.Z
                                end
                                local center = Vector3.new(sumX / #st.Visited, currentPos.Y, sumZ / #st.Visited)
                                
                                table.insert(_G.BuildingMemories, {
                                    AreaCenter = center,
                                    ClimbSpot = currentPos, -- ปักแท่งสีฟ้าตรงจุดที่บรรจบ
                                    TargetY = targetPos.Y,
                                    TracePath = cloneTable(st.Visited) -- บันทึกทางสีเขียว
                                })
                                st.Active = false
                            else
                                local nextData = getNextEdgeTracingStep(currentPos, reqH, targetPos)
                                if nextData then
                                    st.TargetPos = nextData.pos
                                    st.LastMoveTick = os.clock()
                                else
                                    st.Active = false
                                end
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
                -- ลำดับการตรวจสอบหลัก (Main Logic)
                -- =======================================================
                if hDist > followDistance or math.abs(vDist) > 5 then
                    
                    local hasLineOfSight = false
                    local dirToTarget = (targetPos - currentPos).Unit
                    if dirToTarget.Magnitude > 0 then
                        local losRay = workspace:Raycast(currentPos + Vector3.new(0, 1.5, 0), dirToTarget * trueDist, rayParams)
                        if not losRay then hasLineOfSight = true end
                    end

                    -- [1] มองเห็นผู้เล่น -> พุ่งตรง
                    if hasLineOfSight and not isStuck then
                        isProbing = false
                        currentWaypoints = {}
                        isFollowingCustomPath = false
                        updateDebug("DirectTrace", currentPos, targetPos, Color3.fromRGB(0, 255, 0)) 
                        moveWithAvoidance(myHuman, targetPos)
                        
                    -- [2] มองไม่เห็น + อยู่สูงกว่าเป้าหมาย -> Drop Mode (หาที่กระโดดลง)
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
                        
                    -- [3] มองไม่เห็นและไม่ได้อยู่สูงกว่า -> เดินอ้อม (Pathfinding)
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
                                -- [4] ติดขัด (Stuck) หรืออ้อมไม่ได้ -> ตรวจเพดาน -> เลาะขอบหาพื้นที่สีเขียว
                                local canUseCustomPaths = (_G.CustomPathFailTick == nil) or (os.clock() - _G.CustomPathFailTick > 4)

                                if canUseCustomPaths then
                                    local requiredHeightCheck = math.max(20, targetPos.Y - currentPos.Y + 5)
                                    
                                    if checkCeilingAround(currentPos, requiredHeightCheck) then
                                        -- เข้าสู่การลัดเลาะขอบ (Edge Tracing) เพื่อวน Loop
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
                                        -- หากไม่ได้อยู่ใต้เพดาน หรือหาเพดานไม่เจอ ก็พยายามดันทุรังไปเป้าหมายโดยตรงเลย
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
