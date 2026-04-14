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

-- เช็คเพดาน ป้องกันหัวติด
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
-- [ใหม่] สแกนเพดาน ค้นหาเฉพาะ "ขอบเขตที่เปิดโล่ง (บันได/ช่องโหว่)"
-- =======================================================
local function scanCeilingEdge(startPos, targetPos, ceilingY)
    local maxRadius = 30
    local stepSize = 4
    local edgeWaypoints = {}
    local bestEdge = nil
    local bestScore = math.huge

    for x = -maxRadius, maxRadius, stepSize do
        for z = -maxRadius, maxRadius, stepSize do
            local checkPos = Vector3.new(startPos.X + x, ceilingY, startPos.Z + z)
            
            -- ยิงขึ้นฟ้าเช็คเพดานจากจุดนั้น
            local hitCeil = workspace:Raycast(checkPos, Vector3.new(0, 30, 0), rayParams)
            
            -- ถ้า "ไม่ชนอะไรเลย" แสดงว่าตรงนี้เป็นช่องโหว่ หรือขอบบันได!
            if not hitCeil then
                local hitGround = workspace:Raycast(checkPos, Vector3.new(0, -50, 0), rayParams)
                if hitGround and math.abs(hitGround.Position.Y - startPos.Y) < 12 then
                    local edgePos = hitGround.Position
                    table.insert(edgeWaypoints, edgePos)
                    
                    local distToMe = (Vector3.new(edgePos.X, 0, edgePos.Z) - Vector3.new(startPos.X, 0, startPos.Z)).Magnitude
                    local distToTarget = (Vector3.new(edgePos.X, 0, edgePos.Z) - Vector3.new(targetPos.X, 0, targetPos.Z)).Magnitude
                    
                    -- ให้คะแนนความใกล้บันได/เป้าหมาย
                    local score = distToMe + distToTarget
                    if score < bestScore then
                        bestScore = score
                        bestEdge = edgePos
                    end

                    -- สร้าง Block สีฟ้า/เขียวมินต์ เฉพาะจุดขอบที่โล่ง (ลบอันที่ติดเพดานทิ้ง)
                    if debugEnabled then
                        local p = Instance.new("Part")
                        p.Name, p.Size, p.Position = "WP_Debug", Vector3.new(2, 0.5, 2), checkPos
                        p.Anchored, p.CanCollide, p.Transparency = true, false, 0.4
                        p.Color = Color3.fromRGB(0, 255, 255) 
                        p.Parent = workspace.Terrain
                    end
                end
            end
        end
    end
    return bestEdge
end

-- เรดาร์พุ่งขึ้นฟ้า หาบล็อกลอย 
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

                -- แก้ปัญหาบอทลืมโหมด Pathfinding ให้เดินตาม Waypoint อย่างเหนียวแน่นขึ้น
                if #currentWaypoints > 0 and not isProbing then
                    if (currentPos - lastPosition).Magnitude < 0.5 then
                        -- เพิ่มเวลารอให้มากขึ้น จะได้ไม่สลับโหมดง่ายๆ ถ้ายืนติดนิดเดียว
                        if os.clock() - lastMoveTick > 1.5 then 
                            currentWaypoints = {}
                            isFollowingCustomPath = false
                            lastMoveTick = os.clock()
                        end
                    else
                        lastPosition = currentPos
                        lastMoveTick = os.clock()
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
                        -- หน่วงเวลาการคำนวณใหม่ให้นานขึ้น บอทจะได้ไม่รวน
                        if os.clock() - lastComputeTime > 1.0 or (targetPos - lastTargetPos).Magnitude > 10 then
                            lastComputeTime = os.clock()
                            lastTargetPos = targetPos
                            isProbing = false
                            currentWaypoints = {}
                            
                            -- ลำดับที่ 1: พยายามใช้ Pathfinding (หาทางอ้อม/บันได) ก่อนเสมอ!
                            local path = PathfindingService:CreatePath({
                                AgentRadius = 2.5, 
                                AgentHeight = 5, 
                                AgentCanJump = true,
                                WaypointSpacing = 3 
                            })
                            path:ComputeAsync(currentPos, targetPos)
                            
                            if path.Status == Enum.PathStatus.Success then
                                currentWaypoints = path:GetWaypoints()
                                currentWaypointIndex = 2
                                isFollowingCustomPath = false
                            else
                                -- ลำดับที่ 2: ถ้าหาทางอ้อมไม่เจอ และเป้าหมายอยู่ข้างบน
                                if targetPos.Y > currentPos.Y + 4 then
                                    local checkCeil = workspace:Raycast(currentPos + Vector3.new(0,2,0), Vector3.new(0, 30, 0), rayParams)
                                    
                                    if checkCeil then
                                        -- ติดเพดาน! เรียกใช้ตัวสแกนหาขอบบันได
                                        local edgePos = scanCeilingEdge(currentPos, targetPos, checkCeil.Position.Y - 1)
                                        if edgePos then
                                            local escPath = PathfindingService:CreatePath({AgentRadius=2.5, AgentHeight=5, AgentCanJump=true})
                                            escPath:ComputeAsync(currentPos, edgePos)
                                            if escPath.Status == Enum.PathStatus.Success then
                                                currentWaypoints = escPath:GetWaypoints()
                                                currentWaypointIndex = 2
                                                isFollowingCustomPath = false
                                            end
                                        end
                                    end
                                    
                                    -- ลำดับที่ 3: ถ้าเพดานโล่ง หรือหาขอบไม่เจอ ให้ใช้ปีนแนวดิ่ง
                                    if #currentWaypoints == 0 and hDist < 25 then
                                        currentWaypoints = computeVerticalClimbPath(currentPos, targetPos, myChar, target.Character)
                                        if #currentWaypoints > 0 then
                                            isFollowingCustomPath = true
                                            currentWaypointIndex = 1
                                            if debugEnabled then clearVisuals() end
                                        end
                                    end
                                end
                                
                                -- ลำดับที่ 4: จนปัญญาจริงๆ ค่อยเดินคลำกำแพง
                                if #currentWaypoints == 0 then
                                    isProbing = true
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
                        elseif #currentWaypoints > 0 then
                            local wp = currentWaypoints[currentWaypointIndex]
                            if wp then
                                myHuman:MoveTo(wp.Position)
                                
                                local flatDir = (Vector3.new(wp.Position.X, 0, wp.Position.Z) - Vector3.new(currentPos.X, 0, currentPos.Z))
                                local dist2D = flatDir.Magnitude
                                local distY = math.abs(wp.Position.Y - currentPos.Y)
                                
                                if wp.Action == Enum.PathWaypointAction.Jump and not isClimbingState then
                                    if myHuman.FloorMaterial ~= Enum.Material.Air then forceJump(myHuman) end
                                end
                                
                                if dist2D < 4 and distY < 4.5 then
                                    currentWaypointIndex = currentWaypointIndex + 1
                                    lastMoveTick = os.clock()
                                end
                            else
                                currentWaypoints = {}
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
