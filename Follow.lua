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
_G.PatrolIndex = 1 

-- ระบบความจำสถานที่
_G.BuildingMemories = _G.BuildingMemories or {}

-- --- Debug Visualization ---
local function clearVisuals()
    for _, v in pairs(workspace.Terrain:GetChildren()) do
        if v.Name == "WP_Debug" or v.Name == "DirectTrace" or string.find(v.Name, "Laser_Trace") then 
            v:Destroy() 
        end
    end
end

local function clearMemoryAndTrace()
    _G.BuildingMemories = {}
    clearVisuals()
    for _, v in pairs(workspace.Terrain:GetChildren()) do
        if string.find(v.Name, "MemPillar_") or string.find(v.Name, "MemGroup_") then v:Destroy() end
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

-- [อัปเกรด] วาดบล็อกสีเขียวตามรูปทรงตึกจริงๆ ไม่ใช่สี่เหลี่ยมกว้างๆ
local function drawMemoryPillars()
    for _, v in pairs(workspace.Terrain:GetChildren()) do
        if string.find(v.Name, "MemPillar_") then v:Destroy() end
    end
    if not debugEnabled then return end
    
    local currentAreas = {}
    
    for i, mem in ipairs(_G.BuildingMemories) do
        currentAreas["MemGroup_"..i] = true
        
        -- วาดพื้นที่สีเขียวเฉพาะจุดที่มีเพดาน
        if not workspace.Terrain:FindFirstChild("MemGroup_"..i.."_1") then
            for j, node in ipairs(mem.RoofNodes) do
                local nameArea = "MemGroup_"..i.."_"..j
                if not workspace.Terrain:FindFirstChild(nameArea) then
                    local a = Instance.new("Part")
                    a.Name = nameArea
                    a.Size = Vector3.new(6, 2, 6)
                    a.Position = node + Vector3.new(0, 1, 0)
                    a.Anchored, a.CanCollide, a.CanQuery = true, false, false
                    a.Transparency, a.Material = 0.8, Enum.Material.Neon
                    a.Color = Color3.fromRGB(0, 255, 0)
                    a.Parent = workspace.Terrain
                end
            end
        end

        -- ปักเสาสีฟ้า
        if mem.HasPillar and mem.ClimbSpot then
            local namePillar = "MemPillar_"..i
            local p = Instance.new("Part")
            p.Name = namePillar
            local targetY = mem.TargetY
            local bottomY = mem.ClimbSpot.Y
            local h = math.max(10, math.abs(targetY - bottomY))
            p.Size = Vector3.new(2, h, 2)
            p.Position = Vector3.new(mem.ClimbSpot.X, bottomY + (h/2), mem.ClimbSpot.Z)
            p.Anchored, p.CanCollide, p.CanQuery = true, false, false
            p.Transparency, p.Material = 0.4, Enum.Material.Neon
            p.Color = Color3.fromRGB(0, 150, 255) 
            p.Parent = workspace.Terrain
        end
    end
    
    -- ล้างบล็อกตึกเก่าทิ้ง
    for _, v in pairs(workspace.Terrain:GetChildren()) do
        if string.find(v.Name, "MemGroup_") then
            local groupID = string.match(v.Name, "(MemGroup_%d+)")
            if not currentAreas[groupID] then
                v:Destroy()
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
        local checkDist = 4 
        local targetWalkPos = pos

        if dir.Magnitude > 0 then
            local lowerRay = workspace:Raycast(hrp.Position - Vector3.new(0, 1.5, 0), dir * checkDist, rayParams)
            local upperRay = workspace:Raycast(hrp.Position + Vector3.new(0, 1, 0), dir * checkDist, rayParams)
            
            if lowerRay or upperRay then
                local tooTallRay = workspace:Raycast(hrp.Position + Vector3.new(0, 12.0, 0), dir * checkDist, rayParams)
                local ceilRay = workspace:Raycast(hrp.Position + (dir * 2), Vector3.new(0, 7, 0), rayParams)
                
                if tooTallRay or ceilRay then
                    _G.MicroDodgeMem = _G.MicroDodgeMem or {Dir = Vector3.new(), Expire = 0}
                    local dodgeDir
                    
                    if os.clock() < _G.MicroDodgeMem.Expire then
                        dodgeDir = _G.MicroDodgeMem.Dir
                    else
                        local rightDir = (CFrame.Angles(0, math.rad(-60), 0) * dir).Unit
                        local leftDir = (CFrame.Angles(0, math.rad(60), 0) * dir).Unit
                        
                        local rightRay = workspace:Raycast(hrp.Position + Vector3.new(0, 1.5, 0), rightDir * 6, rayParams)
                        local leftRay = workspace:Raycast(hrp.Position + Vector3.new(0, 1.5, 0), leftDir * 6, rayParams)
                        
                        if not rightRay then dodgeDir = rightDir
                        elseif not leftRay then dodgeDir = leftDir
                        else dodgeDir = (CFrame.Angles(0, math.rad(180), 0) * dir).Unit end 
                        
                        _G.MicroDodgeMem = {Dir = dodgeDir, Expire = os.clock() + 0.6} 
                    end
                    targetWalkPos = hrp.Position + (dodgeDir * 6)
                else
                    forceJump(humanoid)
                end
            end
        end
        humanoid:MoveTo(targetWalkPos)
    else
        humanoid:MoveTo(pos)
    end
end

local function getRealFloorY(pos)
    local ray = workspace:Raycast(pos + Vector3.new(0, 10, 0), Vector3.new(0, -20, 0), rayParams)
    if ray then return ray.Position.Y else return pos.Y end
end

local function checkCeilingAround(pos, height)
    local offsets = { Vector3.new(0,0,0), Vector3.new(3,0,0), Vector3.new(-3,0,0), Vector3.new(0,0,3), Vector3.new(0,0,-3) }
    for _, off in ipairs(offsets) do
        if workspace:Raycast(pos + off + Vector3.new(0, 1, 0), Vector3.new(0, height, 0), rayParams) then return true end
    end
    return false
end

-- =========================================================================
-- LASER FLOOD-FILL TRACER 
-- =========================================================================
local function floodFillRoofInstantly(startPos, maxCheckHeight)
    local step = 6          
    local maxNodes = 150    
    local maxRadius = 100   
    local queue = {startPos}
    local visited = {}
    local roofNodes = {}
    
    for _, v in pairs(workspace.Terrain:GetChildren()) do
        if string.find(v.Name, "Laser_Trace") then v:Destroy() end
    end

    local startKey = math.floor(startPos.X/step)..","..math.floor(startPos.Z/step)
    visited[startKey] = true
    
    local nodeCount = 0

    while #queue > 0 and nodeCount < maxNodes do
        local curr = table.remove(queue, 1)
        table.insert(roofNodes, curr)
        nodeCount = nodeCount + 1
        
        local neighbors = {
            Vector3.new(step, 0, 0), Vector3.new(-step, 0, 0),
            Vector3.new(0, 0, step), Vector3.new(0, 0, -step)
        }
        
        for _, off in ipairs(neighbors) do
            local testXZ = curr + off
            
            if (Vector3.new(testXZ.X, 0, testXZ.Z) - Vector3.new(startPos.X, 0, startPos.Z)).Magnitude > maxRadius then
                continue
            end
            
            local key = math.floor(testXZ.X/step)..","..math.floor(testXZ.Z/step)
            
            if not visited[key] then
                visited[key] = true
                local floorY = getRealFloorY(testXZ)
                
                if math.abs(floorY - startPos.Y) <= 8 then
                    local testPos = Vector3.new(testXZ.X, floorY, testXZ.Z)
                    local hasCeiling = workspace:Raycast(testPos + Vector3.new(0,1,0), Vector3.new(0, maxCheckHeight, 0), rayParams)
                    
                    if hasCeiling then
                        table.insert(queue, testPos)
                    end
                end
            end
        end
    end
    
    return roofNodes
end

-- [ยกมาใส่คืน] โหมดปีนตัวเก่าที่โคตรเสถียร
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
                    
                    -- ใช้ฟังก์ชันเช็คหัวเดิม เพื่อกันเพดานติด
                    local headClear = not workspace:Raycast(hitPos + Vector3.new(0, 1, 0), Vector3.new(0, 6, 0), rayParams)

                    if heightDiff > 0.5 and heightDiff <= 8.0 and headClear then
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
                        local headClear = not workspace:Raycast(climbPos + Vector3.new(0, 1, 0), Vector3.new(0, 6, 0), rayParams)

                        if headClear then
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
        clearMemoryAndTrace()
        isProbing = false
        isFollowingCustomPath = false 
    end
end)
MoveSection:NewToggle("Show Path", "Visuals", function(s) 
    debugEnabled = s 
    if not s then clearVisuals() end
end)
MoveSection:NewSlider("Distance", "Gap", 20, 1, function(s) followDistance = s end)

MoveSection:NewButton("Clear Memory", "ล้างความจำตึกและรอยทาง", function() 
    clearMemoryAndTrace()
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
                        if isFollowingCustomPath then
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
                -- [โหมดตรวจสอบ Bounding Box Area]
                -- =======================================================
                local inMemory = nil
                for i, mem in ipairs(_G.BuildingMemories) do
                    -- เช็คเป้าหมายหนีออกจากโซน หรือตกลงมา
                    local targetFloorY = getRealFloorY(Vector3.new(targetPos.X, targetPos.Y, targetPos.Z))
                    local buildingHeight = math.max(10, mem.TargetY - targetFloorY)
                    if targetPos.Y < mem.TargetY - (buildingHeight * 0.30) then
                        table.remove(_G.BuildingMemories, i)
                        clearVisuals()
                        break
                    end
                    
                    -- ตรวจสอบว่าเป้าหมายอยู่ในเขตรัศมีตึกหรือไม่
                    local isInside = false
                    for _, node in ipairs(mem.RoofNodes) do
                        if math.abs(targetPos.X - node.X) < 15 and math.abs(targetPos.Z - node.Z) < 15 then
                            isInside = true
                            break
                        end
                    end
                    
                    if isInside then
                        inMemory = mem
                        break
                    end
                end

                if inMemory then
                    if not inMemory.HasPillar then
                        -- เดินลาดตระเวนตามมุมตึก
                        local corners = {
                            Vector3.new(inMemory.MinX - 5, currentPos.Y, inMemory.MinZ - 5),
                            Vector3.new(inMemory.MaxX + 5, currentPos.Y, inMemory.MinZ - 5),
                            Vector3.new(inMemory.MaxX + 5, currentPos.Y, inMemory.MaxZ + 5),
                            Vector3.new(inMemory.MinX - 5, currentPos.Y, inMemory.MaxZ + 5)
                        }
                        
                        local targetCorner = corners[_G.PatrolIndex]
                        if (Vector3.new(currentPos.X, 0, currentPos.Z) - Vector3.new(targetCorner.X, 0, targetCorner.Z)).Magnitude < 4 then
                            _G.PatrolIndex = _G.PatrolIndex + 1
                            if _G.PatrolIndex > 4 then _G.PatrolIndex = 1 end
                        end
                        
                        moveWithAvoidance(myHuman, targetCorner)

                        -- ทดสอบปีน
                        local testWps = computeVerticalClimbPath(currentPos, targetPos, myChar, target.Character)
                        local highestY = currentPos.Y
                        for _, wp in ipairs(testWps) do 
                            if wp.Position.Y > highestY then highestY = wp.Position.Y end 
                        end
                        
                        -- ถ้าเจอทางปีนถึงเป้าหมาย ให้ปักเสาตรง "กลางบล็อกแรก" ที่มันจะโดดขึ้นไป
                        if highestY >= inMemory.TargetY - 15 and #testWps > 0 then
                            inMemory.HasPillar = true
                            inMemory.ClimbSpot = testWps[1].Position 
                        end
                    else
                        local distToPillar = (Vector3.new(currentPos.X, 0, currentPos.Z) - Vector3.new(inMemory.ClimbSpot.X, 0, inMemory.ClimbSpot.Z)).Magnitude
                        
                        if distToPillar > 3 then
                            updateDebug("DirectTrace", currentPos, inMemory.ClimbSpot, Color3.fromRGB(0, 0, 255))
                            moveWithAvoidance(myHuman, inMemory.ClimbSpot)
                        else
                            local lookPos = Vector3.new(inMemory.Center.X, currentPos.Y, inMemory.Center.Z)
                            myRoot.CFrame = CFrame.lookAt(currentPos, lookPos)
                            
                            local climbWps = computeVerticalClimbPath(currentPos, targetPos, myChar, target.Character)
                            if #climbWps > 0 then
                                currentWaypoints = climbWps
                                currentWaypointIndex = 1
                                isFollowingCustomPath = true
                            else
                                myHuman:MoveTo(currentPos + myRoot.CFrame.LookVector * 5)
                                forceJump(myHuman)
                            end
                        end
                    end
                    return 
                end

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
                -- ลำดับการตรวจสอบหลัก (ไม่สนใจลัดเลาะแล้ว ใช้ Laser ทันที)
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
                        local flatDir = (flatTargetPos - currentPos).Unit
                        
                        if flatDir.Magnitude > 0 then
                            local fwdRay = workspace:Raycast(currentPos + Vector3.new(0, 1.5, 0), flatDir * 6, rayParams)
                            
                            if fwdRay then
                                _G.DodgeMem = _G.DodgeMem or {Dir = Vector3.new(), Expire = 0}
                                local dodgeDir
                                
                                if os.clock() < _G.DodgeMem.Expire then
                                    dodgeDir = _G.DodgeMem.Dir
                                else
                                    local rightDir = (CFrame.Angles(0, math.rad(-75), 0) * flatDir).Unit
                                    local leftDir = (CFrame.Angles(0, math.rad(75), 0) * flatDir).Unit
                                    
                                    local rightRay = workspace:Raycast(currentPos + Vector3.new(0, 1.5, 0), rightDir * 10, rayParams)
                                    local leftRay = workspace:Raycast(currentPos + Vector3.new(0, 1.5, 0), leftDir * 10, rayParams)
                                    
                                    if not rightRay then dodgeDir = rightDir
                                    elseif not leftRay then dodgeDir = leftDir
                                    else dodgeDir = (CFrame.Angles(0, math.rad(180), 0) * flatDir).Unit end 
                                    
                                    _G.DodgeMem = {Dir = dodgeDir, Expire = os.clock() + 2.0}
                                end
                                
                                local dodgePos = currentPos + (dodgeDir * 8)
                                updateDebug("DirectTrace", currentPos, dodgePos, Color3.fromRGB(255, 128, 0))
                                moveWithAvoidance(myHuman, dodgePos)
                            else
                                isProbing = false
                                currentWaypoints = {}
                                isFollowingCustomPath = false
                                updateDebug("DirectTrace", currentPos, flatTargetPos, Color3.fromRGB(255, 128, 0))
                                moveWithAvoidance(myHuman, flatTargetPos)
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
                                local canUseCustomPaths = (_G.CustomPathFailTick == nil) or (os.clock() - _G.CustomPathFailTick > 4)

                                if canUseCustomPaths then
                                    if hDist < 15 then
                                        local requiredHeightCheck = math.max(20, targetPos.Y - currentPos.Y + 5)
                                        
                                        if checkCeilingAround(currentPos, requiredHeightCheck) then
                                            local roofNodes = floodFillRoofInstantly(currentPos, requiredHeightCheck)
                                            if #roofNodes > 0 then
                                                local minX, maxX = math.huge, -math.huge
                                                local minZ, maxZ = math.huge, -math.huge
                                                for _, p in ipairs(roofNodes) do
                                                    if p.X < minX then minX = p.X end
                                                    if p.X > maxX then maxX = p.X end
                                                    if p.Z < minZ then minZ = p.Z end
                                                    if p.Z > maxZ then maxZ = p.Z end
                                                end
                                                local center = Vector3.new((minX+maxX)/2, currentPos.Y, (minZ+maxZ)/2)
                                                
                                                table.insert(_G.BuildingMemories, {
                                                    RoofNodes = roofNodes,
                                                    MinX = minX, MaxX = maxX, MinZ = minZ, MaxZ = maxZ,
                                                    Center = center,
                                                    HasPillar = false,
                                                    ClimbSpot = nil,
                                                    TargetY = targetPos.Y
                                                })
                                            end
                                        else
                                            currentWaypoints = computeVerticalClimbPath(currentPos, targetPos, myChar, target.Character)
                                            if #currentWaypoints > 0 then
                                                isFollowingCustomPath = true
                                                currentWaypointIndex = 1
                                            end
                                        end
                                    else
                                        local flatTargetPos = Vector3.new(targetPos.X, currentPos.Y, targetPos.Z)
                                        local flatDir = (flatTargetPos - currentPos).Unit
                                        
                                        if flatDir.Magnitude > 0 then
                                            local fwdRay = workspace:Raycast(currentPos + Vector3.new(0, 1.5, 0), flatDir * 6, rayParams)
                                            if fwdRay then
                                                _G.DodgeMem = _G.DodgeMem or {Dir = Vector3.new(), Expire = 0}
                                                local dodgeDir
                                                if os.clock() < _G.DodgeMem.Expire then
                                                    dodgeDir = _G.DodgeMem.Dir
                                                else
                                                    local rightDir = (CFrame.Angles(0, math.rad(-75), 0) * flatDir).Unit
                                                    local leftDir = (CFrame.Angles(0, math.rad(75), 0) * flatDir).Unit
                                                    local rightRay = workspace:Raycast(currentPos + Vector3.new(0, 1.5, 0), rightDir * 10, rayParams)
                                                    local leftRay = workspace:Raycast(currentPos + Vector3.new(0, 1.5, 0), leftDir * 10, rayParams)
                                                    
                                                    if not rightRay then dodgeDir = rightDir
                                                    elseif not leftRay then dodgeDir = leftDir
                                                    else dodgeDir = (CFrame.Angles(0, math.rad(180), 0) * flatDir).Unit end 
                                                    _G.DodgeMem = {Dir = dodgeDir, Expire = os.clock() + 2.0}
                                                end
                                                local dodgePos = currentPos + (dodgeDir * 8)
                                                updateDebug("DirectTrace", currentPos, dodgePos, Color3.fromRGB(0, 255, 255))
                                                moveWithAvoidance(myHuman, dodgePos)
                                            else
                                                updateDebug("DirectTrace", currentPos, flatTargetPos, Color3.fromRGB(0, 255, 255))
                                                moveWithAvoidance(myHuman, flatTargetPos)
                                            end
                                        end
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
