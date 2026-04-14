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
        if v.Name == "WP_Debug" or v.Name == "DirectTrace" or v.Name == "ProbeTrace" then v:Destroy() end
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

-- =======================================================
-- [ใหม่] ระบบขอบโดนัท (Donut Edge Scanner)
-- หากติดเพดาน จะกางเส้นทางหาขอบ แล้วยื่นออกไป 1 block นอกหลังคา
-- =======================================================
local function findCeilingEdgeDonut(startPos, targetPos)
    local upRay = workspace:Raycast(startPos + Vector3.new(0, 2, 0), Vector3.new(0, 50, 0), rayParams)
    if not upRay then return nil end -- ไม่ได้อยู่ใต้เพดาน ไม่ต้องทำโดนัท

    local ceilingY = upRay.Position.Y - 1
    local edgePos = nil
    local bestScore = math.huge

    -- ทิศทางที่จะสแกน (เน้นพุ่งไปทางเป้าหมายเป็นหลักก่อน แล้วค่อยวนรอบตัว)
    local dirToTarget = (Vector3.new(targetPos.X, 0, targetPos.Z) - Vector3.new(startPos.X, 0, startPos.Z)).Unit
    local searchDirs = {dirToTarget}
    for angle = 45, 315, 45 do
        table.insert(searchDirs, (CFrame.Angles(0, math.rad(angle), 0) * dirToTarget).Unit)
    end

    for _, dir in ipairs(searchDirs) do
        -- กางออกไปทีละ 3 studs จนสุด 30 studs
        for dist = 3, 30, 3 do 
            local checkPos = startPos + (dir * dist)
            local checkUp = workspace:Raycast(checkPos + Vector3.new(0, 2, 0), Vector3.new(0, 50, 0), rayParams)
            
            -- ถ้ายิงขึ้นไปไม่โดนเพดานเดิม แสดงว่าเจอ "ขอบโดนัท" แล้ว!
            if not checkUp or checkUp.Position.Y > ceilingY + 5 then
                -- สร้าง 1 Block ยื่นออกมานอกขอบ (เคลือบน้ำตาล) ระยะ 3 studs
                local safeEdgePos = checkPos + (dir * 3)
                
                -- เช็คว่าขอบนั้นมีพื้นให้ยืนตั้งหลักไหม (ไม่ใช่เหว)
                local groundCheck = workspace:Raycast(safeEdgePos + Vector3.new(0, 5, 0), Vector3.new(0, -20, 0), rayParams)
                if groundCheck and math.abs(groundCheck.Position.Y - startPos.Y) < 10 then
                    local finalPos = groundCheck.Position
                    local score = (finalPos - startPos).Magnitude + (finalPos - targetPos).Magnitude
                    
                    if score < bestScore then
                        bestScore = score
                        edgePos = finalPos
                    end
                end
                break -- หยุดหาในทิศทางนี้ เจอขอบแล้ว
            end
        end
    end

    -- แสดงบล็อกสีฟ้าอมเขียว (Cyan) ตรงขอบโดนัท
    if debugEnabled and edgePos then
        local p = Instance.new("Part")
        p.Name, p.Size, p.Position = "WP_Debug", Vector3.new(2, 0.5, 2), edgePos
        p.Anchored, p.CanCollide, p.Transparency = true, false, 0.4
        p.Color = Color3.fromRGB(0, 255, 255) 
        p.Parent = workspace.Terrain
    end

    return edgePos
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

                -- =======================================================
                -- [แก้ปัญหาบอทลืมทาง] เพิ่มความอดทน (Patience) เป็น 2.5 วิ
                -- =======================================================
                if (currentPos - lastPosition).Magnitude < 0.5 then
                    if os.clock() - lastMoveTick > 2.5 then -- ถ้าติดค้างเกิน 2.5 วิ ค่อยยกเลิกทางเก่า
                        currentWaypoints = {} 
                        lastMoveTick = os.clock()
                    end
                else
                    lastPosition = currentPos
                    if not isFollowingCustomPath then lastMoveTick = os.clock() end
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
                            
                            -- =======================================================
                            -- Priority 1: บังคับใช้โหมดอ้อม (Pathfinding) เสมอก่อนเป็นอันดับแรกสุด!
                            -- =======================================================
                            local path = PathfindingService:CreatePath({
                                AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 3 
                            })
                            path:ComputeAsync(currentPos, targetPos)
                            
                            if path.Status == Enum.PathStatus.Success then
                                -- ถ้า Pathfinding ปกติสำเร็จ ให้ใช้ทันที! และตัดโหมดอื่นออกไป
                                currentWaypoints = path:GetWaypoints()
                                currentWaypointIndex = 2
                                lastTargetPos = targetPos
                                lastComputeTime = os.clock()
                                isFollowingCustomPath = false 
                            else
                                -- =======================================================
                                -- Priority 2: Pathfinding ล้มเหลว ค่อยใช้ระบบโหมดปีน/ขอบโดนัท
                                -- =======================================================
                                if targetPos.Y > currentPos.Y + 4 and hDist < 25 then
                                    local edgePos = findCeilingEdgeDonut(currentPos, targetPos)
                                    
                                    if edgePos then
                                        -- ถ้าเจอขอบโดนัท ให้สร้าง Pathfinding เดินไปหาขอบก่อน
                                        path:ComputeAsync(currentPos, edgePos)
                                        if path.Status == Enum.PathStatus.Success then
                                            currentWaypoints = path:GetWaypoints()
                                            currentWaypointIndex = 2
                                            isFollowingCustomPath = true -- สั่งให้รู้ว่านี่คือทางเดินพิเศษหลบเพดาน
                                            lastComputeTime = os.clock()
                                        end
                                    else
                                        -- ถ้าไม่ติดเพดานเลย ให้สร้างบล็อกกระโดดขึ้นตรงๆ
                                        currentWaypoints = computeVerticalClimbPath(currentPos, targetPos, myChar, target.Character)
                                        if #currentWaypoints > 0 then
                                            isFollowingCustomPath = true
                                            currentWaypointIndex = 1
                                            lastComputeTime = os.clock()
                                        end
                                    end
                                end

                                -- Priority 3: ถ้าทุกอย่างพังหมด ถึงจะยอมใช้ระบบ Probing ชนกำแพงมั่ว
                                if #currentWaypoints == 0 then
                                    isProbing = true
                                end
                            end
                            
                            -- [Debug Visual] วาดจุดอ้อม
                            if debugEnabled and #currentWaypoints > 0 then
                                clearVisuals()
                                for _, wp in ipairs(currentWaypoints) do
                                    local p = Instance.new("Part")
                                    p.Name, p.Size, p.Position = "WP_Debug", Vector3.new(1.5, 1.5, 1.5), wp.Position
                                    p.Anchored, p.CanCollide, p.CanQuery, p.Transparency = true, false, false, 0.4
                                    p.Color, p.Material = Color3.fromRGB(255, 255, 0), Enum.Material.Neon
                                    p.Parent = workspace.Terrain
                                end
                            end
                        end
                        
                        -- Execution ของระบบเดิน
                        if isProbing then
                            local probeDir = getProbingDirection(myRoot, targetPos)
                            if probeDir then
                                updateDebug("ProbeTrace", currentPos, currentPos + (probeDir * 5), Color3.fromRGB(255, 165, 0))
                                myHuman:MoveTo(currentPos + (probeDir * 8))
                                local wallCheck = workspace:Raycast(currentPos, probeDir * 4, rayParams)
                                if wallCheck then forceJump(myHuman) end
                            end
                        elseif #currentWaypoints > 0 then
                            local wp = currentWaypoints[currentWaypointIndex]
                            if wp then
                                myHuman:MoveTo(wp.Position)
                                
                                local wpHeightDiff = wp.Position.Y - currentPos.Y 
                                local isGoingUp = (wpHeightDiff > 2.5)
                                local isGoingDownSteeply = (wpHeightDiff < -3.5) 
                                local flatDir = (Vector3.new(wp.Position.X, 0, wp.Position.Z) - Vector3.new(currentPos.X, 0, currentPos.Z))
                                local dist2D = flatDir.Magnitude
                                local distY = math.abs(wpHeightDiff)

                                if isGoingDownSteeply and dist2D < 4 and wp.Position.Y < currentPos.Y then
                                    forceJump(myHuman)
                                end
                                
                                if isClimbingState then
                                    if currentPos.Y >= wp.Position.Y - 1 or (dist2D < 5 and distY < 3.5) then
                                        currentWaypointIndex = currentWaypointIndex + 1
                                        lastMoveTick = os.clock()
                                    end
                                else
                                    if dist2D < 4.5 and distY < 3.5 then
                                        currentWaypointIndex = currentWaypointIndex + 1
                                        lastMoveTick = os.clock()
                                    end
                                end
                                
                                if not isClimbingState then
                                    if wp.Action == Enum.PathWaypointAction.Jump or (isGoingUp and dist2D < 2) then
                                        forceJump(myHuman)
                                    end
                                end

                                if currentWaypointIndex > #currentWaypoints then
                                    currentWaypoints = {}
                                    isFollowingCustomPath = false
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
