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
local isFollowingCustomPath = false -- เพิ่มตัวแปรเช็คการเดินตามบล็อกแนวตั้ง

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
        
        if d > maxDist then
            maxDist = d
            bestDir = dir
        end
    end
    return bestDir
end

-- [ใหม่!] ค้นหาช่องโหว่/บันไดที่ใกล้ที่สุด แล้วต่อบล็อกตรงขึ้นฟ้า
local function findHoleAndClimb(startPos, targetPos)
    local holePos = nil
    local bestScore = math.huge
    local searchRadius = 30 -- รัศมีค้นหา (ไม่กว้างเกินไปจนแลค)
    local step = 4

    -- 1. สแกนหาจุดที่ไม่มีเพดานกั้น (ช่องโหว่, บันได, ลานโล่ง)
    for x = -searchRadius, searchRadius, step do
        for z = -searchRadius, searchRadius, step do
            local testPos = Vector3.new(startPos.X + x, startPos.Y, startPos.Z + z)
            
            local groundCheck = workspace:Raycast(testPos + Vector3.new(0, 5, 0), Vector3.new(0, -10, 0), rayParams)
            if groundCheck and math.abs(groundCheck.Position.Y - startPos.Y) < 5 then
                
                -- ยิง Ray ขึ้นฟ้า ไปจนถึงระดับความสูงของเป้าหมาย
                local heightDiff = targetPos.Y - groundCheck.Position.Y
                local skyCheck = workspace:Raycast(groundCheck.Position + Vector3.new(0, 2, 0), Vector3.new(0, heightDiff + 5, 0), rayParams)
                
                if not skyCheck then
                    -- เจอช่องโล่ง! คำนวณคะแนน (ยิ่งใกล้ตัวเราและใกล้เป้าหมาย ยิ่งดี)
                    local distToHole = (Vector3.new(testPos.X, 0, testPos.Z) - Vector3.new(startPos.X, 0, startPos.Z)).Magnitude
                    local distToTarget = (Vector3.new(testPos.X, 0, testPos.Z) - Vector3.new(targetPos.X, 0, targetPos.Z)).Magnitude
                    
                    local score = distToHole + (distToTarget * 0.5)
                    if score < bestScore then
                        bestScore = score
                        holePos = groundCheck.Position
                    end
                end
            end
        end
    end

    -- 2. ถ้าเจอช่องโหว่ ให้สร้าง Waypoint แนวตั้ง (ต่อบล็อกขึ้นฟ้า)
    if holePos then
        local customWp = {}
        -- เดินไปที่ช่องโหว่
        table.insert(customWp, {Position = holePos, Action = Enum.PathWaypointAction.Walk, IsCustom = true})
        
        -- ต่อบล็อกกระโดดขึ้นฟ้าตรงๆ
        local currentClimbY = holePos.Y + 5
        while currentClimbY < targetPos.Y + 2 do
            table.insert(customWp, {Position = Vector3.new(holePos.X, currentClimbY, holePos.Z), Action = Enum.PathWaypointAction.Jump, IsCustom = true, IsVertical = true})
            currentClimbY = currentClimbY + 5
        end
        
        -- กระโดด/เดิน เข้าหาเป้าหมายจากจุดสูงสุด
        table.insert(customWp, {Position = targetPos, Action = Enum.PathWaypointAction.Walk, IsCustom = true})
        return customWp
    end
    return nil
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
    if not s then currentWaypoints = {}; clearVisuals(); isProbing = false; isFollowingCustomPath = false end
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

                -- เช็คสถานะติดขัด (Stuck)
                if (currentPos - lastPosition).Magnitude < 0.5 then
                    if os.clock() - lastMoveTick > 1.0 then 
                        currentWaypoints = {} -- ถ้าติดนานเกิน 1 วิ ให้ล้างเส้นทางเพื่อหาทางใหม่
                        lastMoveTick = os.clock()
                    end
                else
                    lastPosition = currentPos
                    lastMoveTick = os.clock()
                end

                if hDist > followDistance or vDist > 5 then
                    local moveDir = (targetPos - currentPos).Unit
                    local directRay = workspace:Raycast(currentPos, moveDir * trueDist, rayParams)
                    local headPos = currentPos + Vector3.new(0, 2.5, 0)
                    local targetHeadPos = targetPos + Vector3.new(0, 2.5, 0)
                    local headRay = workspace:Raycast(headPos, (targetHeadPos - headPos).Unit * trueDist, rayParams)

                    local isParkour = false
                    if hDist < 14 and (targetPos.Y > currentPos.Y - 2) and vDist < 8 then
                        if directRay and not headRay then isParkour = true
                        elseif not directRay and vDist >= 5 then isParkour = true
                        end
                    end

                    -- [แก้ปัญหาการลืมเส้นทาง] จะใช้ Parkour ก็ต่อเมื่อไม่ได้เดินตามเส้นทางสีฟ้าอยู่ หรือเส้นทางว่างเปล่า
                    if ((not directRay and vDist < 5) or isParkour) and (#currentWaypoints == 0) then
                        isProbing = false
                        currentWaypoints = {}
                        isFollowingCustomPath = false
                        updateDebug("DirectTrace", currentPos, targetPos, isParkour and Color3.fromRGB(255, 255, 0) or Color3.fromRGB(0, 255, 0))
                        myHuman:MoveTo(targetPos)
                        
                        if isParkour then
                            if directRay then
                                if (directRay.Position - currentPos).Magnitude < 3.5 then forceJump(myHuman) end
                            else
                                if hDist < 4 then forceJump(myHuman) end
                            end
                        end
                    else
                        -- อัพเดตเส้นทางก็ต่อเมื่อเป้าหมายขยับไปไกล หรือยังไม่มีเส้นทาง
                        if os.clock() - lastComputeTime > 0.5 or (targetPos - lastTargetPos).Magnitude > 8 or #currentWaypoints == 0 then
                            
                            -- 1. พยายามใช้โหมดสีฟ้า (Pathfinding เดินอ้อมปกติ) ก่อนเสมอ
                            local path = PathfindingService:CreatePath({ AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 3 })
                            path:ComputeAsync(currentPos, targetPos)
                            
                            if path.Status == Enum.PathStatus.Success then
                                isProbing = false
                                isFollowingCustomPath = false
                                currentWaypoints = path:GetWaypoints()
                                currentWaypointIndex = 2
                                lastTargetPos = targetPos
                                lastComputeTime = os.clock()
                                
                                if debugEnabled then
                                    clearVisuals()
                                    for _, wp in ipairs(currentWaypoints) do
                                        local p = Instance.new("Part"); p.Name, p.Size, p.Position = "WP_Debug", Vector3.new(0.8,0.8,0.8), wp.Position
                                        p.Anchored, p.CanCollide, p.Transparency, p.Color, p.Material = true, false, 0.4, Color3.fromRGB(0, 255, 255), Enum.Material.Neon
                                        p.Parent = workspace.Terrain
                                    end
                                end
                            else
                                -- 2. ถ้า Pathfinding พัง (เช่น อยู่คนละชั้น) ให้ใช้โหมด "เจาะเพดานต่อบล็อกขึ้นฟ้า"
                                if targetPos.Y > currentPos.Y + 5 then
                                    local customWP = findHoleAndClimb(currentPos, targetPos)
                                    if customWP then
                                        currentWaypoints = customWP
                                        isFollowingCustomPath = true
                                        currentWaypointIndex = 1
                                        lastTargetPos = targetPos
                                        lastComputeTime = os.clock()
                                        
                                        if debugEnabled then
                                            clearVisuals()
                                            for _, wp in ipairs(currentWaypoints) do
                                                local p = Instance.new("Part"); p.Name, p.Size, p.Position = "WP_Debug", Vector3.new(1.5,1.5,1.5), wp.Position
                                                p.Anchored, p.CanCollide, p.Transparency, p.Color, p.Material = true, false, 0.4, Color3.fromRGB(255, 0, 255), Enum.Material.Neon -- บล็อกแนวตั้งสีม่วง
                                                p.Parent = workspace.Terrain
                                            end
                                        end
                                    else
                                        isProbing = true
                                        currentWaypoints = {}
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
                        elseif #currentWaypoints > 0 then
                            local wp = currentWaypoints[currentWaypointIndex]

                            if wp then
                                local isClimbing = myHuman:GetState() == Enum.HumanoidStateType.Climbing
                                myHuman:MoveTo(wp.Position)
                                
                                -- สั่งกระโดดถ้าเป็น Waypoint แนวตั้ง หรือ Pathfinding สั่งมา
                                if wp.Action == Enum.PathWaypointAction.Jump or wp.IsVertical then
                                    if myHuman.FloorMaterial ~= Enum.Material.Air and not isClimbing then
                                        forceJump(myHuman)
                                    end
                                end
                                
                                local dist2D = (Vector2.new(currentPos.X, currentPos.Z) - Vector2.new(wp.Position.X, wp.Position.Z)).Magnitude
                                local distY = math.abs(currentPos.Y - wp.Position.Y)
                                
                                -- เลื่อน Index ของเส้นทาง
                                if wp.IsVertical then
                                    -- ถ้าปีนแนวตั้งอยู่ สนใจแค่ความสูง
                                    if currentPos.Y >= wp.Position.Y - 1 or (dist2D < 3 and distY < 3.5) then
                                        currentWaypointIndex = currentWaypointIndex + 1
                                    end
                                else
                                    -- ถ้าเดินปกติ
                                    if dist2D < 4.5 and distY < 3.5 then
                                        currentWaypointIndex = currentWaypointIndex + 1
                                    end
                                end
                            end
                        end
                        updateDebug("DirectTrace", currentPos, directRay and directRay.Position or targetPos, Color3.fromRGB(255, 0, 0))
                    end
                else
                    currentWaypoints = {}
                    myHuman:MoveTo(currentPos)
                end
            end
        end)
    end
end)
