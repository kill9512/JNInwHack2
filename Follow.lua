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
local isFollowingCustomPath = false -- [ตัวแปรใหม่] ใช้ล็อคบอทไม่ให้เปลี่ยนใจตอนกำลังปีน

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

-- [ใหม่ล่าสุดตามไอเดียคุณ] สร้าง Waypoint ลากเส้นพุ่งขึ้นฟ้าตามแนวกำแพง
local function computeVerticalClimbPath(startPos, targetPos)
    local customWaypoints = {}
    local scanAngles = {0, 15, -15, 30, -30, 45, -45} -- สแกนหากำแพงด้านหน้า
    local baseDir = (Vector3.new(targetPos.X, 0, targetPos.Z) - Vector3.new(startPos.X, 0, startPos.Z)).Unit
    if baseDir.Magnitude ~= baseDir.Magnitude then baseDir = Vector3.new(1,0,0) end

    for _, angle in ipairs(scanAngles) do
        local dir = (CFrame.Angles(0, math.rad(angle), 0) * baseDir).Unit
        local wallRay = workspace:Raycast(startPos + Vector3.new(0, 2, 0), dir * 15, rayParams)

        if wallRay and wallRay.Instance.CanCollide then
            local wallPos = wallRay.Position
            local normal = wallRay.Normal
            local climbStart = wallPos + (normal * 1.5) -- ดันตัวเองออกมาจากกำแพงนิดนึงจะได้มีที่ให้ตัวอยู่

            -- คำนวณความสูงที่ต้องปีน (ให้ถึงระดับเป้าหมาย หรือบวกเผื่อไปอีกนิด)
            local heightToClimb = math.clamp(targetPos.Y - startPos.Y + 3, 5, 50) 
            
            local isValidClimb = false
            local tempWaypoints = {}

            -- ลากเส้น Waypoint ขึ้นไปทีละ 4 stud
            for h = 4, heightToClimb, 4 do
                local checkPos = climbStart + Vector3.new(0, h, 0)

                -- 1. เช็คหลังคา/เพดาน "เหนือจุดที่จะปีนขึ้นไป"
                local ceilingCheck = workspace:Raycast(checkPos - Vector3.new(0, 2, 0), Vector3.new(0, 7, 0), rayParams)
                if ceilingCheck then
                    break -- ติดหลังคา! หยุดสร้างเส้นทางนี้ทันที
                end

                -- 2. เช็คว่ากำแพง/บันได ยังมีให้เกาะอยู่ไหม หรือเราปีนเลยขอบมาแล้ว?
                local wallStillThere = workspace:Raycast(checkPos + (normal * 2), -normal * 4, rayParams)
                if not wallStillThere then
                    -- กำแพงหมดแล้ว! แสดงว่าถึงขอบ (Ledge) ให้สร้างจุดเดินก้าวขึ้นไปบนพื้น
                    local ledgePos = checkPos + Vector3.new(0, 1, 0) - (normal * 3)
                    table.insert(tempWaypoints, {Position = ledgePos, Action = Enum.PathWaypointAction.Walk})
                    isValidClimb = true
                    break
                end

                -- ถ้าโล่งและยังมีกำแพง ให้ใส่จุดกระโดด/ปีน
                table.insert(tempWaypoints, {Position = checkPos, Action = Enum.PathWaypointAction.Jump})
                
                if h >= heightToClimb - 4 then
                    isValidClimb = true -- ถึงความสูงเป้าหมายแล้ว
                end
            end

            -- ถ้านี่คือเส้นทางที่ปีนได้จริง ให้บันทึกและจบการทำงาน
            if isValidClimb and #tempWaypoints > 0 then
                -- จุดแรกคือเดินไปชิดกำแพง
                table.insert(customWaypoints, {Position = climbStart, Action = Enum.PathWaypointAction.Walk})
                for _, wp in ipairs(tempWaypoints) do
                    table.insert(customWaypoints, wp)
                end
                return customWaypoints
            end
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
                local vDist = math.abs(targetPos.Y - currentPos.Y)
                
                rayParams.FilterDescendantsInstances = {myChar, target.Character}

                local isClimbingState = (myHuman:GetState() == Enum.HumanoidStateType.Climbing)
                local stuckLimit = (isClimbingState or isFollowingCustomPath) and 1.5 or 0.7

                if (currentPos - lastPosition).Magnitude < 0.5 then
                    if os.clock() - lastMoveTick > stuckLimit then 
                        currentWaypoints = {} 
                        isFollowingCustomPath = false
                        lastMoveTick = os.clock()
                    end
                else
                    lastPosition = currentPos
                    lastMoveTick = os.clock()
                end

                -- =======================================================
                -- [ระบบล็อคสถานะ] ถ้ากำลังปีนเส้นทางพิเศษ ให้โฟกัสแค่การปีน!
                -- =======================================================
                if isFollowingCustomPath and #currentWaypoints > 0 then
                    local wp = currentWaypoints[currentWaypointIndex]
                    if wp then
                        myHuman:MoveTo(wp.Position)
                        
                        -- กดกระโดดย้ำๆ ถ้าเป็นโหนดกระโดด เพื่อบังคับปีน
                        if wp.Action == Enum.PathWaypointAction.Jump then
                            if myHuman.FloorMaterial ~= Enum.Material.Air and not isClimbingState then
                                forceJump(myHuman)
                            end
                        end
                        
                        local dist2D = (Vector2.new(currentPos.X, currentPos.Z) - Vector2.new(wp.Position.X, wp.Position.Z)).Magnitude
                        local distY = math.abs(currentPos.Y - wp.Position.Y)
                        
                        -- ถ้าระยะใกล้ถึงจุด Waypoint แล้ว ให้ขยับไปจุดต่อไป
                        if dist2D < 3.5 and distY < 4.5 then
                            currentWaypointIndex = currentWaypointIndex + 1
                        end
                        
                        -- อัปเดตเวลาไว้ จะได้ไม่โดนล้าง Path ทิ้ง
                        lastComputeTime = os.clock()
                        return -- จบการทำงานรอบนี้ ไม่ต้องไปสนใจโค้ด Pathfinding ด้านล่าง!
                    else
                        -- ปีนเสร็จแล้ว ปลดล็อค
                        isFollowingCustomPath = false
                        currentWaypoints = {}
                    end
                end
                -- =======================================================

                if hDist > followDistance or vDist > 5 then
                    local moveDir = (targetPos - currentPos).Unit
                    local directRay = workspace:Raycast(currentPos, moveDir * trueDist, rayParams)

                    local headPos = currentPos + Vector3.new(0, 2.5, 0)
                    local targetHeadPos = targetPos + Vector3.new(0, 2.5, 0)
                    local headRay = workspace:Raycast(headPos, (targetHeadPos - headPos).Unit * trueDist, rayParams)
                    
                    -- เช็คว่าหัวชนอะไรไหม (กันวิ่งอัดกำแพงทึบ)
                    local canWalkStraight = (not directRay and not headRay) and (vDist < 5)

                    if canWalkStraight then
                        isProbing = false
                        currentWaypoints = {}
                        updateDebug("DirectTrace", currentPos, targetPos, Color3.fromRGB(0, 255, 0))
                        myHuman:MoveTo(targetPos)
                    else
                        if os.clock() - lastComputeTime > 0.5 or (targetPos - lastTargetPos).Magnitude > 5 then
                            currentWaypoints = {} 
                            isProbing = false
                            
                            -- [เงื่อนไขใหม่] เป้าหมายอยู่สูงเกิน 4 stud และอยู่ในระยะแนวนอน 25 stud 
                            if targetPos.Y > currentPos.Y + 4 and hDist < 25 then
                                currentWaypoints = computeVerticalClimbPath(currentPos, targetPos)
                            end
                            
                            if #currentWaypoints > 0 then
                                -- คำนวณเส้นทางปีนสำเร็จ! ล็อคโหมดเป็นโหมดปีนทันที
                                isFollowingCustomPath = true
                                currentWaypointIndex = 1
                                lastTargetPos = targetPos
                                lastComputeTime = os.clock()
                                
                                if debugEnabled then
                                    clearVisuals()
                                    for _, wp in ipairs(currentWaypoints) do
                                        local p = Instance.new("Part")
                                        p.Name, p.Size, p.Position = "WP_Debug", Vector3.new(1.5, 1.5, 1.5), wp.Position
                                        p.Anchored, p.CanCollide, p.CanQuery, p.Transparency = true, false, false, 0.4
                                        p.Color, p.Material = Color3.fromRGB(255, 255, 0), Enum.Material.Neon
                                        p.Parent = workspace.Terrain
                                    end
                                end
                            else
                                -- ถ้าไม่ต้องปีน ให้ใช้ Pathfinding ดั้งเดิม หาทางอ้อม
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
                                    lastTargetPos = targetPos
                                    lastComputeTime = os.clock()
                                    
                                    if debugEnabled then
                                        clearVisuals()
                                        for _, wp in ipairs(currentWaypoints) do
                                            local p = Instance.new("Part")
                                            p.Name, p.Size, p.Position = "WP_Debug", Vector3.new(0.8,0.8,0.8), wp.Position
                                            p.Anchored, p.CanCollide, p.CanQuery, p.Transparency = true, false, false, 0.4
                                            p.Color, p.Material = Color3.fromRGB(0, 255, 255), Enum.Material.Neon
                                            p.Parent = workspace.Terrain
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
                        elseif #currentWaypoints > 0 and not isFollowingCustomPath then
                            -- นี่คือการเดินตาม Pathfinding ของ Roblox ปกติ (ถ้าไม่ได้อยู่ในโหมดปีนพิเศษ)
                            local lookAheadIndex = currentWaypointIndex
                            local maxLookAhead = math.min(currentWaypointIndex + 6, #currentWaypoints) 
                            
                            for i = maxLookAhead, currentWaypointIndex + 1, -1 do
                                local testWp = currentWaypoints[i]
                                local isHeightSafe = true
                                for j = currentWaypointIndex, i do
                                    if math.abs(currentWaypoints[j].Position.Y - currentPos.Y) > 1.5 then
                                        isHeightSafe = false; break
                                    end
                                end
                                
                                if isHeightSafe then
                                    local hasJump = false
                                    for j = currentWaypointIndex, i do
                                        if currentWaypoints[j].Action == Enum.PathWaypointAction.Jump then
                                            hasJump = true; break
                                        end
                                    end
                                    
                                    if not hasJump then
                                        local rayOrigin = currentPos + Vector3.new(0, 2, 0) 
                                        local targetOrigin = testWp.Position + Vector3.new(0, 2, 0)
                                        local hit = workspace:Raycast(rayOrigin, targetOrigin - rayOrigin, rayParams)
                                        if not hit then lookAheadIndex = i; break end
                                    end
                                end
                            end
                            
                            currentWaypointIndex = lookAheadIndex
                            local wp = currentWaypoints[currentWaypointIndex]

                            if wp then
                                local wpHeightDiff = wp.Position.Y - currentPos.Y 
                                if wpHeightDiff > 12 then
                                    currentWaypoints = {} 
                                    return 
                                end

                                local isGoingUp = (wpHeightDiff > 2.5)
                                local isGoingDownSteeply = (wpHeightDiff < -3.5) 
                                local flatDir = (Vector3.new(wp.Position.X, 0, wp.Position.Z) - Vector3.new(currentPos.X, 0, currentPos.Z))
                                local dist2D = flatDir.Magnitude
                                local distY = math.abs(wpHeightDiff)

                                if isGoingUp and not isClimbingState then
                                    if dist2D > 0.1 then myHuman:MoveTo(wp.Position + (flatDir.Unit * 1.5)) else myHuman:MoveTo(wp.Position) end
                                else
                                    myHuman:MoveTo(wp.Position)
                                end
                                
                                if isGoingDownSteeply and dist2D < 4 and wp.Position.Y < currentPos.Y then
                                    forceJump(myHuman)
                                end
                                
                                if isClimbingState then
                                    if currentPos.Y >= wp.Position.Y - 1 or (dist2D < 5 and distY < 3.5) then
                                        currentWaypointIndex = currentWaypointIndex + 1
                                    end
                                else
                                    if dist2D < 4.5 and distY < 3.5 then
                                        currentWaypointIndex = currentWaypointIndex + 1
                                    end
                                end
                                
                                if not isClimbingState then
                                    if wp.Action == Enum.PathWaypointAction.Jump or (isGoingUp and dist2D < 2) then
                                        forceJump(myHuman)
                                    end
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
