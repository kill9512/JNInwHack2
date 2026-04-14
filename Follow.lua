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

-- [ใหม่] ระบบความจำสถานที่ (Building Memory)
_G.BuildingMemories = _G.BuildingMemories or {}

-- [ใหม่] สถานะระบบลัดเลาะขอบแบบแยกส่วน
_G.TraceState = {
    Active = false,
    Phase = "None",
    TargetPos = nil,
    StartPos = nil,
    StepCount = 0,
    Visited = {},
    LastMoveTick = 0,
    CurrentDir = nil -- ทิศทางการเดินเลาะ
}

-- --- Debug Visualization ---
local function clearVisuals()
    for _, v in pairs(workspace.Terrain:GetChildren()) do
        if v.Name == "WP_Debug" or v.Name == "DirectTrace" or v.Name == "ProbeTrace" 
        or string.find(v.Name, "Debug_Edge") or string.find(v.Name, "Debug_Ceil") 
        or v.Name == "Debug_TraceYellow" or v.Name == "Debug_TraceGreen" then 
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
    if not debugEnabled then 
        for _, v in pairs(workspace.Terrain:GetChildren()) do
            if string.find(v.Name, "MemPillar_") then v:Destroy() end
        end
        return 
    end
    for i, mem in ipairs(_G.BuildingMemories) do
        local name = "MemPillar_"..i
        local p = workspace.Terrain:FindFirstChild(name)
        if not p then
            p = Instance.new("Part")
            p.Name = name
            p.Size = Vector3.new(2, 50, 2)
            p.Position = mem.ClimbSpot + Vector3.new(0, 25, 0)
            p.Anchored, p.CanCollide, p.CanQuery = true, false, false
            p.Transparency, p.Material = 0.4, Enum.Material.Neon
            p.Color = Color3.fromRGB(0, 255, 255) -- เสาแสงสีฟ้า (ทางขึ้นที่เคยจำไว้)
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

local function moveWithAvoidance(humanoid, pos)
    local hrp = humanoid.Parent:FindFirstChild("HumanoidRootPart")
    if hrp then
        local dir = (pos - hrp.Position).Unit
        local dist = (pos - hrp.Position).Magnitude
        -- เรดาร์หน้าแข้ง: กระโดดหลบหินหรือขั้นบันไดเตี้ยๆ
        local fwdRay = workspace:Raycast(hrp.Position, dir * math.min(dist, 4), rayParams)
        if fwdRay then forceJump(humanoid) end
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

-- [ระบบตรวจเพดาน (Cross Scan)] วัดแกน X Z กากบาท
local function crossScanForEdge(startPos, maxCheckHeight, targetPos)
    local step = 4
    local maxRadius = 60
    local dirs = { Vector3.new(1,0,0), Vector3.new(-1,0,0), Vector3.new(0,0,1), Vector3.new(0,0,-1) }
    local bestEdge = nil
    local bestDist = math.huge
    local allGreenBlocks = {}
    local endYellowBlocks = {}

    if debugEnabled then clearVisuals() end

    for _, dir in ipairs(dirs) do
        local currentGreenLine = {}
        for d = step, maxRadius, step do
            local checkPos = startPos + (dir * d)
            local rayOrigin = checkPos + Vector3.new(0, 1, 0)
            local upRay = workspace:Raycast(rayOrigin, Vector3.new(0, maxCheckHeight, 0), rayParams)
            
            if upRay then
                table.insert(currentGreenLine, {pos = checkPos, y = upRay.Position.Y})
            else
                -- สุดขอบเพดาน สร้างบล็อกเหลืองจำไว้
                table.insert(endYellowBlocks, {pos = checkPos, greens = currentGreenLine})
                break 
            end
        end
    end

    -- เลือกอันที่ใกล้เป้าหมายสุด
    local selectedYellow = nil
    for _, edge in ipairs(endYellowBlocks) do
        local d = (edge.pos - targetPos).Magnitude
        if d < bestDist then
            bestDist = d
            bestEdge = edge.pos
            selectedYellow = edge
        end
    end

    -- วาดเฉพาะทิศทางที่เลือก
    if debugEnabled and selectedYellow then
        for _, g in ipairs(selectedYellow.greens) do
            local p = Instance.new("Part")
            p.Name, p.Size, p.Position = "Debug_CeilGreen", Vector3.new(3, 0.5, 3), g.pos + Vector3.new(0, 2, 0)
            p.Anchored, p.CanCollide, p.Transparency, p.Color = true, false, 0.5, Color3.fromRGB(0, 255, 0)
            p.Material, p.Parent = Enum.Material.Neon, workspace.Terrain
        end
        local p = Instance.new("Part")
        p.Name, p.Size, p.Position = "Debug_EdgeYellow", Vector3.new(3, 0.5, 3), bestEdge + Vector3.new(0, 2, 0)
        p.Anchored, p.CanCollide, p.Transparency, p.Color = true, false, 0.2, Color3.fromRGB(255, 255, 0)
        p.Material, p.Parent = Enum.Material.Neon, workspace.Terrain
    end

    return bestEdge
end

-- [ระบบลัดเลาะขอบ] เช็คซ้าย/ขวา หน้า/หลัง 
local function getNextEdgeTracingStep(currentPos, maxCheckHeight, targetPos)
    local step = 4
    local neighbors = { Vector3.new(step,0,0), Vector3.new(-step,0,0), Vector3.new(0,0,step), Vector3.new(0,0,-step) }
    local validSteps = {}

    for _, offset in ipairs(neighbors) do
        local testPos = currentPos + offset
        
        -- เช็คกันเดินย้อนรอย (จำทาง)
        local visited = false
        for _, v in ipairs(_G.TraceState.Visited) do
            if (v - testPos).Magnitude < 1 then visited = true; break end
        end

        if not visited then
            -- บล็อกนี้ต้องโล่ง (สีเหลือง)
            local upRay = workspace:Raycast(testPos + Vector3.new(0,1,0), Vector3.new(0, maxCheckHeight, 0), rayParams)
            if not upRay then
                -- ลองเช็คด้านซ้าย/ขวา (บล็อก 3 หรือ 4 ตามภาพ) ว่าติดเพดานไหม
                local isEdge = false
                local ceilPos = nil
                for _, subOff in ipairs(neighbors) do
                    local sidePos = testPos + subOff
                    local sideUp = workspace:Raycast(sidePos + Vector3.new(0,1,0), Vector3.new(0, maxCheckHeight, 0), rayParams)
                    if sideUp then 
                        isEdge = true -- ฝั่งนี้ติดเพดาน (บล็อกเขียว)
                        ceilPos = sidePos
                        break
                    end
                end
                
                if isEdge then 
                    table.insert(validSteps, {pos = testPos, ceilPos = ceilPos}) 
                end
            end
        end
    end

    -- เลือกก้าวถัดไปที่เดินมุ่งหน้าไปหาเป้าหมายมากที่สุด
    local bestStep = nil
    local bestDist = math.huge
    for _, s in ipairs(validSteps) do
        local d = (s.pos - targetPos).Magnitude
        if d < bestDist then 
            bestDist = d
            bestStep = s 
        end
    end
    return bestStep
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
                            if score < bestScore then
                                bestScore = score; bestNextPos = hitPos
                            end
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
                            if not isVisited then
                                bestNextPos = climbPos; break
                            end
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

local function findPathWithFallback(startPos, targetPos)
    local path = PathfindingService:CreatePath({AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 3})
    
    path:ComputeAsync(startPos, targetPos)
    if path.Status == Enum.PathStatus.Success then return path:GetWaypoints() end
    
    -- ขยายรัศมีหาทางอ้อมให้ใกล้เป้าหมาย
    local searchRadii = {10, 20, 30}
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
MoveSection:NewButton("Clear Memory", "ล้างความจำตึก", function() _G.BuildingMemories = {} end)

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

                -- เช็คติดแหง็กทั่วไป
                if (currentPos - lastPosition).Magnitude < 0.5 then
                    if os.clock() - lastMoveTick > 1.5 then 
                        currentWaypoints = {} 
                        lastMoveTick = os.clock()
                        if isFollowingCustomPath or _G.TraceState.Active then
                            _G.CustomPathFailTick = os.clock() 
                            isFollowingCustomPath = false
                            _G.TraceState.Active = false
                        end
                    end
                else
                    lastPosition = currentPos
                    lastMoveTick = os.clock()
                end

                -- =======================================================
                -- [ระบบลัดเลาะขอบ & ระบบความจำ (Edge Tracing & Memory)]
                -- =======================================================
                if _G.TraceState.Active then
                    local st = _G.TraceState
                    local flatTarget = Vector3.new(st.TargetPos.X, currentPos.Y, st.TargetPos.Z)
                    local distToTarget = (flatTarget - currentPos).Magnitude
                    
                    if distToTarget < 2 then
                        -- จำทางที่เดินผ่านมา (ระบบ Array Memory)
                        table.insert(st.Visited, st.TargetPos)
                        st.StepCount = st.StepCount + 1

                        if st.Phase == "MoveToEdge" then
                            st.Phase = "Tracing"
                            st.StartPos = currentPos
                        end

                        if st.Phase == "Tracing" then
                            local reqH = math.max(20, targetPos.Y - currentPos.Y + 5)
                            
                            -- สแกนหาบันได / ที่ปีน
                            local climbWp = computeVerticalClimbPath(currentPos, targetPos, myChar, target.Character)
                            if #climbWp > 0 then
                                -- จำสถานที่ A! ปักหมุดเสาฟ้าถาวร
                                table.insert(_G.BuildingMemories, {AreaCenter = st.StartPos, ClimbSpot = currentPos})
                                st.Active = false
                                currentWaypoints = climbWp
                                currentWaypointIndex = 1
                                isFollowingCustomPath = true
                            else
                                -- เช็คการเดินครบ Loop (วนกลับมาที่เดิม)
                                if st.StepCount > 15 and (currentPos - st.StartPos).Magnitude < 8 then
                                    st.Active = false -- วนรอบตึกแล้วไม่เจอทางขึ้น
                                    _G.CustomPathFailTick = os.clock()
                                else
                                    -- คำนวณหา บล็อก 1-2-3-4
                                    local nextData = getNextEdgeTracingStep(currentPos, reqH, targetPos)
                                    if nextData then
                                        st.TargetPos = nextData.pos
                                        st.LastMoveTick = os.clock()
                                        if debugEnabled then
                                            local py = Instance.new("Part")
                                            py.Name, py.Size, py.Position = "Debug_TraceYellow", Vector3.new(3.5, 0.5, 3.5), nextData.pos + Vector3.new(0, 2, 0)
                                            py.Anchored, py.CanCollide, py.Transparency, py.Color = true, false, 0.2, Color3.fromRGB(255, 255, 0)
                                            py.Material, py.Parent = Enum.Material.Neon, workspace.Terrain
                                            
                                            if nextData.ceilPos then
                                                local pg = Instance.new("Part")
                                                pg.Name, pg.Size, pg.Position = "Debug_TraceGreen", Vector3.new(3.5, 0.5, 3.5), nextData.ceilPos + Vector3.new(0, 2, 0)
                                                pg.Anchored, pg.CanCollide, pg.Transparency, pg.Color = true, false, 0.5, Color3.fromRGB(0, 255, 0)
                                                pg.Material, pg.Parent = Enum.Material.Neon, workspace.Terrain
                                            end
                                        end
                                    else
                                        st.Active = false -- ทางตัน
                                    end
                                end
                            end
                        end
                    else
                        moveWithAvoidance(myHuman, flatTarget)
                        if os.clock() - st.LastMoveTick > 6 then st.Active = false end
                    end
                    return -- ล็อกสถานะ ไม่ให้โดนระบบอื่นแย่งการทำงาน!
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
                            
                            -- ลำดับความสำคัญ 1: โหมดเดินอ้อม ต้องถูกเรียกใช้งานก่อน
                            local testWaypoints = findPathWithFallback(currentPos, targetPos)
                            
                            if #testWaypoints > 0 then
                                currentWaypoints = testWaypoints
                                currentWaypointIndex = 2
                                lastTargetPos = targetPos
                                lastComputeTime = os.clock()
                                isFollowingCustomPath = false 
                                
                                if debugEnabled then
                                    clearVisuals()
                                    for _, wp in ipairs(currentWaypoints) do
                                        local p = Instance.new("Part")
                                        p.Name, p.Size, p.Position = "WP_Debug", Vector3.new(1.2, 1.2, 1.2), wp.Position
                                        p.Anchored, p.CanCollide, p.Transparency = true, false, 0.4
                                        p.Color, p.Material = Color3.fromRGB(0, 150, 255), Enum.Material.Neon
                                        p.Parent = workspace.Terrain
                                    end
                                end
                            else
                                -- ลำดับความสำคัญ 2: ถ้าเดินอ้อมไม่ได้ หรืออยู่ใต้ตีนเป้าหมาย ค่อยเรียกโหมดตรวจเพดาน
                                local isUnderTarget = (hDist < 10 and targetPos.Y > currentPos.Y + 4)
                                local canUseCustomPaths = (_G.CustomPathFailTick == nil) or (os.clock() - _G.CustomPathFailTick > 4)

                                if canUseCustomPaths and (#testWaypoints == 0 or isUnderTarget) then
                                    local requiredHeightCheck = math.max(20, targetPos.Y - currentPos.Y + 5)
                                    
                                    if checkCeilingAround(currentPos, requiredHeightCheck) then
                                        -- เช็คความจำ: ตึกนี้เคยสำรวจทางขึ้นเจอหรือยัง?
                                        local knownClimbSpot = nil
                                        for _, mem in ipairs(_G.BuildingMemories) do
                                            if (currentPos - mem.AreaCenter).Magnitude < 100 then 
                                                knownClimbSpot = mem.ClimbSpot
                                                break
                                            end
                                        end
                                        
                                        if knownClimbSpot then
                                            -- จำได้! ให้ Pathfinding เดินไปที่ "เสาแสงสีฟ้า" ทันที
                                            local path = PathfindingService:CreatePath({AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = true})
                                            path:ComputeAsync(currentPos, knownClimbSpot)
                                            if path.Status == Enum.PathStatus.Success then
                                                currentWaypoints = path:GetWaypoints()
                                                currentWaypointIndex = 2
                                                lastTargetPos = targetPos
                                                lastComputeTime = os.clock()
                                            else
                                                moveWithAvoidance(myHuman, knownClimbSpot) -- เผื่อ Path พัง ให้พุ่งตรงไปดื้อๆ
                                            end
                                        else
                                            -- ไม่เคยมา: ทริกเกอร์ระบบตรวจเพดาน & ลัดเลาะขอบ
                                            local edgeStart = crossScanForEdge(currentPos, requiredHeightCheck, targetPos)
                                            if edgeStart then
                                                _G.TraceState.Active = true
                                                _G.TraceState.Phase = "MoveToEdge"
                                                _G.TraceState.TargetPos = edgeStart
                                                _G.TraceState.Visited = {}
                                                _G.TraceState.StepCount = 0
                                                _G.TraceState.LastMoveTick = os.clock()
                                            end
                                        end
                                    else
                                        -- ไม่ติดเพดาน ลองปีนป่ายปกติ
                                        currentWaypoints = computeVerticalClimbPath(currentPos, targetPos, myChar, target.Character)
                                        if #currentWaypoints > 0 then
                                            isFollowingCustomPath = true
                                            currentWaypointIndex = 1
                                            lastTargetPos = targetPos
                                            lastComputeTime = os.clock()
                                        end
                                    end
                                else
                                    isProbing = true
                                    currentWaypoints = {}
                                end
                            end
                        end
                        
                        -- โหมด Probing สุ่มทาง (กรณีตันสุดๆ)
                        if isProbing then
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
                            if bestDir then
                                updateDebug("ProbeTrace", currentPos, currentPos + (bestDir * 5), Color3.fromRGB(255, 165, 0))
                                moveWithAvoidance(myHuman, currentPos + (bestDir * 8))
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
