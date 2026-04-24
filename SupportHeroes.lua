local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("KONG GUISUS - EXPLORER", "DarkTheme")
local Tab = Window:NewTab("Main")

-- --- Services ---
local Players = game.Players
local LocalPlayer = Players.LocalPlayer
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

-- --- Settings Variables ---
local SelectedMode = "Manual"
local SelectedPlayerName = nil
local followDistance = 5
local followEnabled = false
local debugEnabled = false

local autoCoinEnabled = false 
local autoDodgeEnabled = false
local shieldRange = 100 

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local lastPosition = Vector3.new()
local lastMoveTick = os.clock()
local randomTarget = nil 

-- --- UI Sections ---
local SupportSection = Tab:NewSection("Support Functions") 
local Section = Tab:NewSection("Interior & Building Navigation")
local MoveSection = Tab:NewSection("Navigation Control")

-- --- UI: Support Functions ---
SupportSection:NewToggle("Auto Collect Coins", "ดึงเงินจาก CoinStack อัตโนมัติ", function(state)
    autoCoinEnabled = state
end)

SupportSection:NewToggle("Final Hybrid Defense", "หลบเวทย์เต็มตัว + เสาเข็มหัวแหลม", function(state)
    autoDodgeEnabled = state
end)

SupportSection:NewSlider("Dodge Detect Range", "ระยะตรวจจับ (บล็อค)", 300, 20, function(s)
    shieldRange = s
end)

-- --- UI: Navigation Control ---
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

MoveSection:NewToggle("Enable Follow", "Start Logic", function(s) 
    followEnabled = s 
    if not s then currentWaypoints = {}; isProbing = false end
end)
MoveSection:NewSlider("Distance", "Gap", 20, 1, function(s) followDistance = s end)

-- --- Helper Functions: Safety Scanner ---
local function isSafePosition(startPos, targetPos, hazard)
    local ignoreList = {LocalPlayer.Character}
    if hazard then table.insert(ignoreList, hazard) end
    rayParams.FilterDescendantsInstances = ignoreList
    
    local dir = targetPos - startPos
    local wallHit = workspace:Raycast(startPos, dir, rayParams)
    if wallHit then return false end 

    local groundOrigin = targetPos + Vector3.new(0, 3, 0)
    local groundHit = workspace:Raycast(groundOrigin, Vector3.new(0, -10, 0), rayParams)
    if not groundHit then return false end 

    return true
end

local function findSafeDodge(startPos, baseDir, distance, hazard)
    local target = startPos + (baseDir * distance)
    if isSafePosition(startPos, target, hazard) then return target end
    
    local angles = {45, -45, 90, -90, 135, -135, 180}
    for _, angle in ipairs(angles) do
        local rotatedDir = CFrame.Angles(0, math.rad(angle), 0) * baseDir
        local testTarget = startPos + (rotatedDir * distance)
        if isSafePosition(startPos, testTarget, hazard) then
            return testTarget
        end
    end
    return startPos + (baseDir * (distance * 0.4))
end

-- ==========================================
-- [ระบบที่ 1] หลบ Eruption (Model) แบบพ้นทั้งตัว
-- ==========================================
local function handleEruption(hazard)
    if not hazard:IsA("Model") then return end
    
    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return end

    local cf, sz = hazard:GetBoundingBox()
    local hazardPos = cf.Position
    local myPos = myRoot.Position
    local myPosXZ = Vector3.new(myPos.X, 0, myPos.Z)
    local hazPosXZ = Vector3.new(hazardPos.X, 0, hazardPos.Z)
    
    local distXZ = (myPosXZ - hazPosXZ).Magnitude
    local radius = math.max(sz.X, sz.Z) / 2
    
    -- [แก้คำนวณ] บวกขนาดตัวละครเรา (ประมาณ 3.5 บล็อค) เพื่อให้พ้นทั้งตัว
    local playerSize = 3.5
    local safeRadius = radius + playerSize

    if distXZ < safeRadius then
        local escapeDir = (myPosXZ - hazPosXZ)
        if escapeDir.Magnitude == 0 then escapeDir = Vector3.new(1, 0, 0) end
        escapeDir = escapeDir.Unit
        
        -- ระยะวาร์ปที่ทำให้ตัวเราออกไปอยู่ขอบวงพอดี
        local distanceToMove = (safeRadius + 1) - distXZ
        
        local safeTarget = findSafeDodge(myPos, escapeDir, distanceToMove, hazard)
        if safeTarget then
            myRoot.CFrame = CFrame.new(safeTarget)
        end
    end
end

-- ==========================================
-- [ระบบที่ 2] เกราะลิ่มแก้ว (Wedge Deflector)
-- ==========================================
local function handleProjectile(hazard)
    local mainPart = hazard:IsA("BasePart") and hazard or (hazard:IsA("Model") and (hazard.PrimaryPart or hazard:FindFirstChildWhichIsA("BasePart", true)))
    if not mainPart or mainPart:FindFirstChild("WedgeShield") then return end

    local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not myRoot then return end

    if (mainPart.Position - myRoot.Position).Magnitude > shieldRange then return end

    local dirToPlayer = (myRoot.Position - mainPart.Position)
    dirToPlayer = dirToPlayer.Magnitude > 0 and dirToPlayer.Unit or Vector3.new(0, 0, 1)

    -- สร้าง WedgePart (หัวแหลม)
    local wedge = Instance.new("WedgePart")
    wedge.Name = "WedgeShield"
    wedge.Transparency = 0.6
    wedge.Material = Enum.Material.Glass
    wedge.Color = Color3.fromRGB(255, 255, 255)
    
    -- [ความหนาและแหลม] กว้าง 12 สูง 12 ยาว 40 บล็อค
    wedge.Size = Vector3.new(12, 12, 40) 
    wedge.CanCollide = true
    wedge.CanTouch = false
    wedge.Massless = true
    wedge.Anchored = mainPart.Anchored

    -- ตั้งค่าฟิสิกส์ให้ลื่นที่สุด (เพื่อให้มึงสไลด์ออกข้างได้ง่าย)
    wedge.CustomPhysicalProperties = PhysicalProperties.new(0, 0, 0, 0, 0) -- Friction = 0

    -- วางตำแหน่งให้ด้านลาด (Slope) หันมาทางตัวมึง
    -- ขยับจุดศูนย์กลางยื่นออกมาหน้ากระสุน 15 บล็อค
    local centerOfWedge = mainPart.Position + (dirToPlayer * 15)
    
    -- หมุนลิ่มให้ชี้ไปทางตัวมึงตรงๆ
    wedge.CFrame = CFrame.lookAt(centerOfWedge, myRoot.Position) * CFrame.Angles(0, math.pi, 0)
    
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = wedge; weld.Part1 = mainPart; weld.Parent = wedge
    
    wedge.Parent = mainPart

    -- ปิดการชนของดาเมจจริงและลบ Touch
    pcall(function()
        mainPart.CanCollide = false
        for _, v in pairs(hazard:GetDescendants()) do
            if v:IsA("BasePart") then 
                v.CanCollide = false 
                local t = v:FindFirstChild("TouchInterest")
                if t then t:Destroy() end
            end
        end
    end)
end

-- --- SUPPORT LOOPS ---
RunService.Stepped:Connect(function()
    if autoDodgeEnabled then
        local dungeon = workspace:FindFirstChild("Dungeon")
        local effects = dungeon and dungeon:FindFirstChild("Effects")
        if effects then
            for _, v in pairs(effects:GetChildren()) do
                if v:IsA("Model") then -- เช็ค Model (Eruption)
                    handleEruption(v)
                elseif v.Name == "Arrow" or v.Name:match("Magic$") then
                    handleProjectile(v)
                end
            end
        end
    end
end)

-- Loop ดึงเงิน
task.spawn(function()
    while true do
        task.wait(0.1)
        if autoCoinEnabled then
            pcall(function()
                local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                local treasure = workspace:FindFirstChild("Dungeon") and workspace.Dungeon:FindFirstChild("Treasure")
                if myRoot and treasure then
                    for _, item in pairs(treasure:GetChildren()) do
                        if item.Name == "CoinStack" then
                            if item:IsA("BasePart") then
                                item.CanCollide = false; item.CFrame = myRoot.CFrame
                            elseif item:IsA("Model") then
                                item:PivotTo(myRoot.CFrame)
                                for _, p in pairs(item:GetDescendants()) do
                                    if p:IsA("BasePart") then p.CanCollide = false; if p:FindFirstChild("TouchInterest") then p.CFrame = myRoot.CFrame end end
                                end
                            end
                        end
                    end
                end
            end)
        end
    end
end)

-- --- MAIN FOLLOW LOOP ---
task.spawn(function()
    while true do
        task.wait(0.05)
        if not followEnabled then continue end
        
        pcall(function()
            local target = nil
            if SelectedMode == "Manual" then
                target = Players:FindFirstChild(SelectedPlayerName or "")
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

                if (currentPos - lastPosition).Magnitude < 0.5 then
                    if os.clock() - lastMoveTick > 0.7 then currentWaypoints = {}; lastMoveTick = os.clock() end
                else
                    lastPosition = currentPos; lastMoveTick = os.clock()
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
                        elseif not directRay and vDist >= 5 then isParkour = true end
                    end

                    if (not directRay and vDist < 5) or isParkour then
                        isProbing = false; currentWaypoints = {}
                        updateDebug("DirectTrace", currentPos, targetPos, isParkour and Color3.fromRGB(255, 255, 0) or Color3.fromRGB(0, 255, 0))
                        myHuman:MoveTo(targetPos)
                        if isParkour then
                            if directRay then
                                local distToWall = (directRay.Position - currentPos).Magnitude
                                if distToWall < 3.5 then forceJump(myHuman) end
                            else
                                if hDist < 4 then forceJump(myHuman) end
                            end
                        end
                    else
                        if os.clock() - lastComputeTime > 0.5 or (targetPos - lastTargetPos).Magnitude > 5 then
                            local path = PathfindingService:CreatePath({AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 3})
                            path:ComputeAsync(currentPos, targetPos)
                            if path.Status == Enum.PathStatus.Success then
                                isProbing = false; currentWaypoints = path:GetWaypoints(); currentWaypointIndex = 2
                                lastTargetPos = targetPos; lastComputeTime = os.clock()
                            else
                                isProbing = true; currentWaypoints = {}
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
                            local lookAheadIndex = currentWaypointIndex
                            local maxLookAhead = math.min(currentWaypointIndex + 6, #currentWaypoints) 
                            for i = maxLookAhead, currentWaypointIndex + 1, -1 do
                                local testWp = currentWaypoints[i]
                                local isHeightSafe = true
                                for j = currentWaypointIndex, i do
                                    if math.abs(currentWaypoints[j].Position.Y - currentPos.Y) > 1.5 then isHeightSafe = false; break end
                                end
                                if isHeightSafe then
                                    local hasJump = false
                                    for j = currentWaypointIndex, i do
                                        if currentWaypoints[j].Action == Enum.PathWaypointAction.Jump then hasJump = true; break end
                                    end
                                    if not hasJump then
                                        local hit = workspace:Raycast(currentPos + Vector3.new(0, 2, 0), (testWp.Position + Vector3.new(0, 2, 0)) - (currentPos + Vector3.new(0, 2, 0)), rayParams)
                                        if not hit then lookAheadIndex = i; break end
                                    end
                                end
                            end
                            currentWaypointIndex = lookAheadIndex
                            local wp = currentWaypoints[currentWaypointIndex]
                            if wp then
                                if math.abs(currentPos.Y - wp.Position.Y) > 6 then currentWaypoints = {}; return end
                                local isClimbing = myHuman:GetState() == Enum.HumanoidStateType.Climbing
                                local isGoingUp = (wp.Position.Y > currentPos.Y + 2.5) 
                                if isGoingUp and not isClimbing then
                                    local flatDir = (Vector3.new(wp.Position.X, 0, wp.Position.Z) - Vector3.new(currentPos.X, 0, currentPos.Z))
                                    if flatDir.Magnitude > 0.1 then myHuman:MoveTo(wp.Position + (flatDir.Unit * 1.5)) 
                                    else myHuman:MoveTo(wp.Position) end
                                else
                                    myHuman:MoveTo(wp.Position)
                                end
                                local dist2D = (Vector2.new(currentPos.X, currentPos.Z) - Vector2.new(wp.Position.X, wp.Position.Z)).Magnitude
                                local distY = math.abs(currentPos.Y - wp.Position.Y)
                                if isClimbing then
                                    if currentPos.Y >= wp.Position.Y - 1 or (dist2D < 5 and distY < 3.5) then currentWaypointIndex = currentWaypointIndex + 1 end
                                else
                                    if dist2D < 4.5 and distY < 3.5 then currentWaypointIndex = currentWaypointIndex + 1 end
                                end
                                if not isClimbing and (wp.Action == Enum.PathWaypointAction.Jump or (isGoingUp and dist2D < 2)) then forceJump(myHuman) end
                            end
                        end
                        updateDebug("DirectTrace", currentPos, directRay and directRay.Position or targetPos, Color3.fromRGB(255, 0, 0))
                    end
                else
                    currentWaypoints = {}; myHuman:MoveTo(currentPos)
                end
            end
        end)
    end
end)
