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

-- [ใหม่] สถานะการหนีเพดาน
local isEscapingCeiling = false
local escapeTargetPos = nil

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
        or v.Name == "Debug_Ceiling" or v.Name == "Debug_Edge" or v.Name == "CeilingLaser" then 
            v:Destroy() 
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
    local offsets = {
        Vector3.new(0,0,0), 
        Vector3.new(3,0,0), Vector3.new(-3,0,0), 
        Vector3.new(0,0,3), Vector3.new(0,0,-3)
    }
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

local function findPathWithFallback(startPos, targetPos)
    local path = PathfindingService:CreatePath({AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 3})
    
    path:ComputeAsync(startPos, targetPos)
    if path.Status == Enum.PathStatus.Success then return path:GetWaypoints() end
    
    local searchRadii = {10, 20}
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
                                bestScore = score
                                bestNextPos = hitPos
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
                                bestNextPos = climbPos
                                break
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

-- ระบบกางตารางเพดานที่คว้านเนื้อในออก
local function computeCeilingEscapePath(startPos, targetPos)
    local step = 4 
    local maxRadius = 24 -- ลดรัศมีลงนิดหน่อยให้คำนวณเร็วขึ้น
    local maxCheckHeight = math.max(40, targetPos.Y - startPos.Y + 10)
    
    local grid = {} 
    
    for x = -maxRadius, maxRadius, step do
        grid[x] = {}
        for z = -maxRadius, maxRadius, step do
            local checkPos = startPos + Vector3.new(x, 0, z)
            local rayOrigin = checkPos + Vector3.new(0, 1, 0)
            local upRay = workspace:Raycast(rayOrigin, Vector3.new(0, maxCheckHeight, 0), rayParams)
            if upRay then
                grid[x][z] = {hitY = upRay.Position.Y}
            end
        end
    end

    local greenEdges = {}
    local yellowEdges = {}
    local yellowEdgeSet = {} 

    for x = -maxRadius, maxRadius, step do
        for z = -maxRadius, maxRadius, step do
            if grid[x] and grid[x][z] then
                local hitY = grid[x][z].hitY
                local isEdge = false
                
                local neighbors = { {step,0}, {-step,0}, {0,step}, {0,-step} }
                for _, offset in ipairs(neighbors) do
                    local nx, nz = x + offset[1], z + offset[2]
                    
                    if nx >= -maxRadius and nx <= maxRadius and nz >= -maxRadius and nz <= maxRadius then
                        if not (grid[nx] and grid[nx][nz]) then
                            isEdge = true
                            local key = nx..","..nz
                            if not yellowEdgeSet[key] then
                                yellowEdgeSet[key] = true
                                table.insert(yellowEdges, {x = nx, z = nz, hitY = hitY})
                            end
                        end
                    else
                        isEdge = true
                        local key = nx..","..nz
                        if not yellowEdgeSet[key] then
                            yellowEdgeSet[key] = true
                            table.insert(yellowEdges, {x = nx, z = nz, hitY = hitY})
                        end
                    end
                end
                
                if isEdge then
                    table.insert(greenEdges, {x = x, z = z, hitY = hitY})
                end
            end
        end
    end

    if debugEnabled then
        for _, v in pairs(workspace.Terrain:GetChildren()) do
            if v.Name == "Debug_Ceiling" or v.Name == "Debug_Edge" then v:Destroy() end
        end
        for _, ceil in ipairs(greenEdges) do
            local p = Instance.new("Part")
            p.Name, p.Size = "Debug_Ceiling", Vector3.new(step, 0.5, step)
            p.Position = startPos + Vector3.new(ceil.x, (ceil.hitY - startPos.Y) - 0.5, ceil.z)
            p.Anchored, p.CanCollide, p.CanQuery, p.Transparency = true, false, false, 0.4
            p.Color, p.Material = Color3.fromRGB(0, 255, 0), Enum.Material.Neon
            p.Parent = workspace.Terrain
        end
        for _, edge in ipairs(yellowEdges) do
            local p = Instance.new("Part")
            p.Name, p.Size = "Debug_Edge", Vector3.new(step, 0.5, step)
            p.Position = startPos + Vector3.new(edge.x, (edge.hitY - startPos.Y) - 0.5, edge.z)
            p.Anchored, p.CanCollide, p.CanQuery, p.Transparency = true, false, false, 0.2
            p.Color, p.Material = Color3.fromRGB(255, 255, 0), Enum.Material.Neon
            p.Parent = workspace.Terrain
        end
    end

    local bestEdge = nil
    local bestScore = math.huge

    for _, edge in ipairs(yellowEdges) do
        local edgeWorldPos = startPos + Vector3.new(edge.x, 0, edge.z)
        local distToTarget = (Vector2.new(edgeWorldPos.X, edgeWorldPos.Z) - Vector2.new(targetPos.X, targetPos.Z)).Magnitude
        local distFromMe = (Vector2.new(edgeWorldPos.X, edgeWorldPos.Z) - Vector2.new(startPos.X, startPos.Z)).Magnitude

        local score = distToTarget + (distFromMe * 0.5)
        if score < bestScore then
            bestScore = score
            bestEdge = edgeWorldPos
        end
    end

    return bestEdge
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
        isEscapingCeiling = false
        escapeTargetPos = nil
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

                -- เช็คอาการติดแหง็ก
                if (currentPos - lastPosition).Magnitude < 0.5 then
                    if os.clock() - lastMoveTick > 1.5 then 
                        currentWaypoints = {} 
                        lastMoveTick = os.clock()
                        if isFollowingCustomPath or isEscapingCeiling then
                            _G.CustomPathFailTick = os.clock() 
                            isFollowingCustomPath = false
                            isEscapingCeiling = false
                            escapeTargetPos = nil
                        end
                    end
                else
                    lastPosition = currentPos
                    lastMoveTick = os.clock()
                end

                -- [ใหม่] จัดการสถานะการเดินหลบเพดาน
                if isEscapingCeiling and escapeTargetPos then
                    local requiredHeightCheck = math.max(20, targetPos.Y - currentPos.Y + 5)
                    local stillUnderCeiling = checkCeilingAround(currentPos, requiredHeightCheck)
                    
                    local distToEscape = (Vector2.new(currentPos.X, currentPos.Z) - Vector2.new(escapeTargetPos.X, escapeTargetPos.Z)).Magnitude
                    
                    -- ถ้าพ้นเพดานแล้ว หรือ เดินมาถึงจุดสีเหลืองแล้ว ให้ยกเลิกโหมดหนี
                    if not stillUnderCeiling or distToEscape < 2 or os.clock() - lastComputeTime > 5 then
                        isEscapingCeiling = false
                        escapeTargetPos = nil
                        currentWaypoints = {}
                    else
                        -- สร้าง Path สั้นๆ ไปยังจุดสีเหลือง
                        if #currentWaypoints == 0 or os.clock() - lastComputeTime > 1 then
                            local path = PathfindingService:CreatePath({AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = true})
                            path:ComputeAsync(currentPos, escapeTargetPos)
                            if path.Status == Enum.PathStatus.Success then
                                currentWaypoints = path:GetWaypoints()
                                currentWaypointIndex = 2
                            else
                                myHuman:MoveTo(escapeTargetPos) -- เดินตรงไปเลยถ้า Pathing ล้มเหลว
                            end
                            lastComputeTime = os.clock()
                        end
                        -- สั่งเดินตาม Path หนี
                        if currentWaypoints[currentWaypointIndex] then
                            myHuman:MoveTo(currentWaypoints[currentWaypointIndex].Position)
                            if (Vector2.new(currentPos.X, currentPos.Z) - Vector2.new(currentWaypoints[currentWaypointIndex].Position.X, currentWaypoints[currentWaypointIndex].Position.Z)).Magnitude < 3 then
                                currentWaypointIndex = currentWaypointIndex + 1
                            end
                        end
                        return -- ข้าม Logic อื่นๆ ไปเลยจนกว่าจะหนีสำเร็จ
                    end
                end

                -- เดินตาม Path ปีนป่าย
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
                                    forceJump(myHuman)
                                end
                            end
                            local dist2D = (Vector2.new(currentPos.X, currentPos.Z) - Vector2.new(wp.Position.X, wp.Position.Z)).Magnitude
                            local distY = math.abs(currentPos.Y - wp.Position.Y)
                            if dist2D < 3.5 and distY < 4.5 then
                                currentWaypointIndex = currentWaypointIndex + 1
                                lastMoveTick = os.clock() 
                            end
                            lastComputeTime = os.clock()
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
                                        p.Anchored, p.CanCollide, p.CanQuery, p.Transparency = true, false, false, 0.4
                                        p.Color, p.Material = Color3.fromRGB(0, 150, 255), Enum.Material.Neon
                                        p.Parent = workspace.Terrain
                                    end
                                end
                            else
                                local canUseCustomPaths = (_G.CustomPathFailTick == nil) or (os.clock() - _G.CustomPathFailTick > 4)

                                if targetPos.Y > currentPos.Y + 4 and canUseCustomPaths then
                                    local requiredHeightCheck = math.max(20, targetPos.Y - currentPos.Y + 5)
                                    
                                    if checkCeilingAround(currentPos, requiredHeightCheck) then
                                        -- [ใหม่] คำนวณขอบเพดาน 1 ครั้ง แล้วเข้าโหมดหนี
                                        local bestEscapePos = computeCeilingEscapePath(currentPos, targetPos)
                                        if bestEscapePos then
                                            isEscapingCeiling = true
                                            escapeTargetPos = bestEscapePos
                                            lastComputeTime = os.clock()
                                        end
                                    else
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
                        
                        if isProbing then
                            local probeDir = getProbingDirection(myRoot, targetPos)
                            if probeDir then
                                updateDebug("ProbeTrace", currentPos, currentPos + (probeDir * 5), Color3.fromRGB(255, 165, 0))
                                myHuman:MoveTo(currentPos + (probeDir * 8))
                                local wallCheck = workspace:Raycast(currentPos, probeDir * 4, rayParams)
                                if wallCheck then forceJump(myHuman) end
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
