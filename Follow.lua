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

-- ระบบความจำสถานที่ (จำถาวร ไม่ลบแล้วเว้ย!)
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
        if string.find(v.Name, "MemPillar_") or string.find(v.Name, "MemArea_") then v:Destroy() end
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
        local nameArea = "MemArea_"..i
        local a = Instance.new("Part")
        a.Name = nameArea
        local sizeX = math.max(10, mem.MaxX - mem.MinX + 10)
        local sizeZ = math.max(10, mem.MaxZ - mem.MinZ + 10)
        a.Size = Vector3.new(sizeX, 2, sizeZ)
        a.Position = mem.Center + Vector3.new(0, 1, 0)
        a.Anchored, a.CanCollide, a.CanQuery = true, false, false
        a.Transparency, a.Material = 0.8, Enum.Material.Neon
        a.Color = Color3.fromRGB(0, 255, 0)
        a.Parent = workspace.Terrain

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
                        
                        -- [แก้ปัญหาติดมุม 90 องศา] ถ้าติดซ้ายขวา ให้สะบัดออกมุมกว้าง 135 องศา
                        if not rightRay then dodgeDir = rightDir
                        elseif not leftRay then dodgeDir = leftDir
                        else 
                            local sign = (math.random() > 0.5) and 1 or -1
                            dodgeDir = (CFrame.Angles(0, math.rad(135 * sign), 0) * dir).Unit 
                        end 
                        
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
        if workspace:Raycast(pos + off + Vector3.new(0, 5, 0), Vector3.new(0, height - 5, 0), rayParams) then return true end
    end
    return false
end

-- =========================================================================
-- [ปรับปรุง] วิชาระเบิดรัศมี ใช้อ้างอิงจากจุด Raycast แทน Center Box ปลอมๆ
-- =========================================================================
local function findClimbSpotVineStyle(outerNodes, targetY, centerPos, myChar)
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {myChar, workspace.Terrain}

    for _, node in ipairs(outerNodes) do
        local heightToTarget = targetY - node.Y
        if heightToTarget < 5 then continue end 
        
        local dirToCenter = (Vector3.new(centerPos.X, node.Y, centerPos.Z) - node).Unit
        if dirToCenter.Magnitude == 0 then dirToCenter = Vector3.new(1,0,0) end
        
        local dirs = {
            dirToCenter, 
            Vector3.new(1,0,0), Vector3.new(-1,0,0), 
            Vector3.new(0,0,1), Vector3.new(0,0,-1)
        }
        
        for _, dir in ipairs(dirs) do
            local baseWallRay = workspace:Raycast(node + Vector3.new(0, 2, 0), dir * 8, rayParams)
            
            if baseWallRay and baseWallRay.Instance then
                local p = baseWallRay.Instance
                local topY = p.Position.Y + (p.Size.Y/2)
                local bottomY = p.Position.Y - (p.Size.Y/2)
                
                local canClimb = false
                if topY >= targetY - 10 and bottomY <= node.Y + 8 then
                    canClimb = true
                else
                    local testY = 5
                    canClimb = true
                    while testY < heightToTarget - 5 do
                        local upWallRay = workspace:Raycast(node + Vector3.new(0, testY, 0), dir * 8, rayParams)
                        if not upWallRay then
                            canClimb = false 
                            break
                        end
                        testY = testY + 5
                    end
                end
                
                if canClimb then
                    -- [แก้ปัญหาหาจุดเสาไม่เจอแกนกลางจริง]
                    -- ใช้จุดที่ยิงแสงชนจริงๆ (HitPoint) เป็นจุดอ้างอิงแทนที่จะเหมาทั้ง Part
                    local hitPoint = baseWallRay.Position
                    local ladderCenter = Vector3.new(hitPoint.X, node.Y, hitPoint.Z)
                    
                    local outwardDir = (Vector3.new(node.X, 0, node.Z) - Vector3.new(ladderCenter.X, 0, ladderCenter.Z)).Unit
                    if outwardDir.Magnitude == 0 then outwardDir = -dir end 
                    
                    local bestClimbPos = ladderCenter + (outwardDir * 2.5)
                    
                    return bestClimbPos, ladderCenter, outwardDir
                end
            end
        end
    end
    return nil, nil, nil
end

-- =========================================================================
-- LASER FLOOD-FILL
-- =========================================================================
local function floodFillRoofInstantly(startPos, maxCheckHeight)
    local step = 6          
    local maxNodes = 300    
    local maxRadius = 150   
    local queue = {startPos}
    local visited = {}
    local roofNodes = {}
    local outerNodes = {} 
    
    clearVisuals()

    local startKey = math.floor(startPos.X/step)..","..math.floor(startPos.Z/step)
    visited[startKey] = true
    
    local nodeCount = 0

    while #queue > 0 and nodeCount < maxNodes do
        local curr = table.remove(queue, 1)
        table.insert(roofNodes, curr)
        nodeCount = nodeCount + 1
        
        if debugEnabled then
            local pg = Instance.new("Part")
            pg.Name = "Laser_Trace_Green_"..nodeCount
            pg.Size = Vector3.new(step*0.8, 0.5, step*0.8)
            pg.Position = curr + Vector3.new(0, 2, 0)
            pg.Anchored = true; pg.CanCollide = false; pg.CanQuery = false
            pg.Transparency = 0.5; pg.Color = Color3.fromRGB(0, 255, 0)
            pg.Material = Enum.Material.Neon; pg.Parent = workspace.Terrain
        end
        
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
                    local hasCeiling = workspace:Raycast(testPos + Vector3.new(0,5,0), Vector3.new(0, maxCheckHeight-5, 0), rayParams)
                    
                    if hasCeiling then
                        table.insert(queue, testPos)
                    else
                        table.insert(outerNodes, testPos)
                        
                        if debugEnabled then
                            local py = Instance.new("Part")
                            py.Name = "Laser_Trace_Yellow"
                            py.Size = Vector3.new(step*0.8, 0.5, step*0.8)
                            py.Position = testPos + Vector3.new(0, 2, 0)
                            py.Anchored = true; py.CanCollide = false; py.CanQuery = false
                            py.Transparency = 0.2; py.Color = Color3.fromRGB(255, 255, 0)
                            py.Material = Enum.Material.Neon; py.Parent = workspace.Terrain
                        end
                    end
                end
            end
        end
    end
    
    return roofNodes, outerNodes
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
                        if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("Humanoid") and p.Character.Health > 0 then
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

                local inMemory = nil
                for _, mem in ipairs(_G.BuildingMemories) do
                    if currentPos.Y >= mem.TargetY - 5 then
                        mem.IsOnRoof = true
                    else
                        local tFloor = getRealFloorY(Vector3.new(targetPos.X, targetPos.Y, targetPos.Z))
                        local bHeight = math.max(10, mem.TargetY - tFloor)
                        if currentPos.Y < mem.TargetY - (bHeight * 0.30) then
                            mem.IsOnRoof = false
                        end
                    end
                    
                    if targetPos.Y >= mem.TargetY - 15 then
                        if targetPos.X >= mem.MinX - 15 and targetPos.X <= mem.MaxX + 15 and
                           targetPos.Z >= mem.MinZ - 15 and targetPos.Z <= mem.MaxZ + 15 then
                            inMemory = mem
                            break
                        end
                    end
                end

                if inMemory then
                    if inMemory.IsOnRoof then
                        updateDebug("DirectTrace", currentPos, targetPos, Color3.fromRGB(0, 255, 0)) 
                        moveWithAvoidance(myHuman, targetPos)
                        return
                    end
                    
                    if inMemory.HasPillar and inMemory.ClimbSpot then
                        inMemory.ClimbPhase = inMemory.ClimbPhase or "Aligning"
                        
                        local outwardDir = inMemory.LadderOutward or Vector3.new(1,0,0)
                        local setupPos = inMemory.LadderCenter + (outwardDir * 10)
                        setupPos = Vector3.new(setupPos.X, inMemory.OriginalClimbSpot.Y, setupPos.Z)
                        
                        local vaultPos = Vector3.new(inMemory.ClimbSpot.X, inMemory.TargetY + 5, inMemory.ClimbSpot.Z) + (-outwardDir * 6)

                        if inMemory.ClimbPhase == "Aligning" then
                            local distToSetup = (Vector3.new(currentPos.X, 0, currentPos.Z) - Vector3.new(setupPos.X, 0, setupPos.Z)).Magnitude
                            updateDebug("DirectTrace", currentPos, setupPos, Color3.fromRGB(255, 165, 0)) 
                            
                            if distToSetup > 4 then
                                moveWithAvoidance(myHuman, setupPos)
                            else
                                inMemory.ClimbPhase = "Climbing"
                                inMemory.ClimbFailTick = os.clock()
                            end
                            
                        elseif inMemory.ClimbPhase == "Climbing" then
                            updateDebug("DirectTrace", currentPos, vaultPos, Color3.fromRGB(255, 0, 255)) 
                            
                            if os.clock() - (inMemory.ClimbFailTick or os.clock()) > 3 then
                                if inMemory.ProbeState == "None" then
                                    inMemory.ProbeState = "Right"
                                    inMemory.ProbeOffset = 0
                                elseif inMemory.ProbeState == "Right" then
                                    inMemory.ProbeOffset = inMemory.ProbeOffset + 2.5 
                                    local testPos = inMemory.OriginalClimbSpot + (inMemory.LadderRight * inMemory.ProbeOffset)
                                    local hit = workspace:Raycast(testPos + Vector3.new(0,2,0), -outwardDir * 8, rayParams)
                                    
                                    if not hit then
                                        inMemory.RightEdge = inMemory.ProbeOffset - 2.5
                                        inMemory.ProbeState = "Left"
                                        inMemory.ProbeOffset = 0
                                    else
                                        inMemory.ClimbSpot = testPos
                                        inMemory.ClimbFailTick = os.clock()
                                    end
                                elseif inMemory.ProbeState == "Left" then
                                    inMemory.ProbeOffset = inMemory.ProbeOffset - 2.5
                                    local testPos = inMemory.OriginalClimbSpot + (inMemory.LadderRight * inMemory.ProbeOffset)
                                    local hit = workspace:Raycast(testPos + Vector3.new(0,2,0), -outwardDir * 8, rayParams)
                                    
                                    if not hit then
                                        inMemory.LeftEdge = inMemory.ProbeOffset + 2.5
                                        inMemory.ProbeState = "Center"
                                    else
                                        inMemory.ClimbSpot = testPos
                                        inMemory.ClimbFailTick = os.clock()
                                    end
                                elseif inMemory.ProbeState == "Center" then
                                    local mid = ((inMemory.RightEdge or 0) + (inMemory.LeftEdge or 0)) / 2
                                    inMemory.ClimbSpot = inMemory.OriginalClimbSpot + (inMemory.LadderRight * mid)
                                    inMemory.ProbeState = "Done"
                                    inMemory.ClimbFailTick = os.clock() + 5 
                                end
                            end

                            local faceDir = -outwardDir
                            if faceDir.Magnitude == 0 then faceDir = Vector3.new(1,0,0) end
                            local lookPos = currentPos + faceDir * 5
                            myRoot.CFrame = CFrame.lookAt(currentPos, Vector3.new(lookPos.X, currentPos.Y, lookPos.Z))
                            
                            myHuman:MoveTo(vaultPos)
                            
                            if os.clock() - (inMemory.ClimbFailTick or os.clock()) > 5 then
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

                -- [แก้ปัญหา ยืนติดอยู่บนหัว (Drop Mode)]
                -- ถ้าระยะห่างแนวนอนน้อยมาก แต่ศัตรูอยู่ข้างล่าง ให้บังคับก้าวลงไป!
                if hDist < 5 and vDist < -10 then
                    local randomDropDir = (myRoot.CFrame.LookVector + Vector3.new(math.random(-1,1), 0, math.random(-1,1))).Unit
                    local dropTarget = currentPos + (randomDropDir * 5)
                    updateDebug("DirectTrace", currentPos, dropTarget, Color3.fromRGB(255, 0, 0))
                    moveWithAvoidance(myHuman, dropTarget)
                    return
                end

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
                                    else 
                                        local sign = (math.random() > 0.5) and 1 or -1
                                        dodgeDir = (CFrame.Angles(0, math.rad(135 * sign), 0) * flatDir).Unit 
                                    end 
                                    
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

                            local canUseCustomPaths = (_G.CustomPathFailTick == nil) or (os.clock() - _G.CustomPathFailTick > 4)

                            if canUseCustomPaths then
                                -- [แก้ปัญหา Flood Fill ผิดจังหวะ]
                                -- จะทำงานหาตึกปีน ก็ต่อเมื่อเป้าหมายอยู่ **สูงกว่าเราเท่านั้น** (targetPos.Y > currentPos.Y + 5)
                                if targetPos.Y > currentPos.Y + 5 and hDist < 15 then
                                    local requiredHeightCheck = math.max(20, targetPos.Y - currentPos.Y + 5)
                                    
                                    if checkCeilingAround(currentPos, requiredHeightCheck) then
                                        local roofNodes, outerNodes = floodFillRoofInstantly(currentPos, requiredHeightCheck)
                                        
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
                                            
                                            local climbSpot, ladderCenter, outwardDir = findClimbSpotVineStyle(outerNodes, targetPos.Y, center, myChar)
                                            
                                            -- [เพิ่มเงื่อนไข Failsafe] ถ้าเจอเสาจริงๆ ค่อยเมมโมรี่!
                                            if climbSpot then
                                                local ladderRight = Vector3.new(1,0,0)
                                                if outwardDir then
                                                    ladderRight = outwardDir:Cross(Vector3.new(0,1,0)).Unit
                                                    if ladderRight.Magnitude == 0 then ladderRight = Vector3.new(1,0,0) end
                                                end

                                                table.insert(_G.BuildingMemories, {
                                                    MinX = minX, MaxX = maxX, MinZ = minZ, MaxZ = maxZ,
                                                    Center = center,
                                                    HasPillar = true,
                                                    ClimbSpot = climbSpot,
                                                    OriginalClimbSpot = climbSpot, 
                                                    LadderCenter = ladderCenter,
                                                    LadderOutward = outwardDir, 
                                                    LadderRight = ladderRight,
                                                    ProbeState = "None",
                                                    ProbeOffset = 0,
                                                    RightEdge = nil,
                                                    LeftEdge = nil,
                                                    ClimbPhase = "Aligning",
                                                    MaxClimbY = currentPos.Y,
                                                    ClimbFailTick = os.clock(),
                                                    TargetY = targetPos.Y,
                                                    IsOnRoof = false 
                                                })
                                            else
                                                -- ถ้าคำนวณแล้วไม่มีเสา ลบทิ้งทันที เด้งกลับไปเดินปกติ
                                                _G.CustomPathFailTick = os.clock()
                                            end
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
                                                else 
                                                    local sign = (math.random() > 0.5) and 1 or -1
                                                    dodgeDir = (CFrame.Angles(0, math.rad(135 * sign), 0) * flatDir).Unit 
                                                end 
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
            end
        end)
    end
end)
