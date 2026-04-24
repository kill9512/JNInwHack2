local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("KONG GUISUS - EXPLORER", "DarkTheme")
local Tab = Window:NewTab("Main")

-- --- Services ---
local Players = game.Players
local LocalPlayer = Players.LocalPlayer
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

-- --- Settings ---
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

SupportSection:NewToggle("Auto Collect Coins", "ดึงเงินจาก CoinStack อัตโนมัติ", function(state) autoCoinEnabled = state end)
SupportSection:NewToggle("Final Defense V9", "วาร์ปหนีเวทย์ + เกราะแก้ว 5 ชั้น", function(state) autoDodgeEnabled = state end)
SupportSection:NewSlider("Detect Range", "ระยะตรวจจับ", 300, 20, function(s) shieldRange = s end)

-- --- UI: Navigationเดิมๆ (ข้ามไปเพื่อความกระชับ) ---
Section:NewDropdown("Target Mode", "Mode", {"Manual", "Max HP", "Min HP", "Random"}, function(m) SelectedMode = m end)
local drop = Section:NewDropdown("Select Target", "User", {}, function(s) SelectedPlayerName = s:match("@([^%)]+)") end)
local function refreshList()
    local t = {"None (Off)"}
    for _, p in pairs(Players:GetPlayers()) do if p ~= LocalPlayer then table.insert(t, p.DisplayName.." (@"..p.Name..")") end end
    drop:Refresh(t)
end
Section:NewButton("Refresh List", "Update", refreshList)
refreshList()

MoveSection:NewToggle("Enable Follow", "Start Logic", function(s) followEnabled = s end)
MoveSection:NewSlider("Distance", "Gap", 20, 1, function(s) followDistance = s end)

-- --- Helper Functions ---
local function isSafeGround(pos)
    local rayOrigin = pos + Vector3.new(0, 5, 0)
    local rayDirection = Vector3.new(0, -15, 0)
    rayParams.FilterDescendantsInstances = {LocalPlayer.Character}
    local hit = workspace:Raycast(rayOrigin, rayDirection, rayParams)
    return hit ~= nil -- คืนค่า true ถ้ามีพื้นรองรับ
end

-- ==========================================
-- [ระบบย่อย 1] หลบ Eruption แบบเน้นพิกัด XZ
-- ==========================================
local function handleEruptionV9(hazard)
    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return end

    local hazardPos, hazardSize
    if hazard:IsA("Model") then
        local cf, sz = hazard:GetBoundingBox()
        hazardPos, hazardSize = cf.Position, sz
    else
        hazardPos, hazardSize = hazard.Position, hazard.Size
    end

    local myPos = myRoot.Position
    local distXZ = (Vector2.new(myPos.X, myPos.Z) - Vector2.new(hazardPos.X, hazardPos.Z)).Magnitude
    local radius = math.max(hazardSize.X, hazardSize.Z) / 2
    local safeRadius = radius + 3.5

    -- [หัวใจสำคัญ] ถ้าตัวมึงอยู่ในวง (XZ) สั่งดีดตัวออกทันที!
    if distXZ < safeRadius then
        local escapeDir = (Vector3.new(myPos.X, 0, myPos.Z) - Vector3.new(hazardPos.X, 0, hazardPos.Z))
        if escapeDir.Magnitude == 0 then escapeDir = Vector3.new(1, 0, 0) end
        escapeDir = escapeDir.Unit
        
        local targetPos = hazardPos + (escapeDir * (safeRadius + 1))
        targetPos = Vector3.new(targetPos.X, myPos.Y, targetPos.Z)

        -- เช็คแค่ "เหว" อย่างเดียวพอตอนออกจากวง จะได้ไม่ติดบัคกำแพงทิพย์
        if isSafeGround(targetPos) then
            myRoot.CFrame = CFrame.new(targetPos)
        end
    end
end

-- ==========================================
-- [ระบบย่อย 2] เกราะแก้วซ้อน 5 ชั้น (Anti-Tunneling)
-- ==========================================
local function handleProjectileV9(hazard)
    local mainPart = hazard:IsA("BasePart") and hazard or (hazard:IsA("Model") and (hazard.PrimaryPart or hazard:FindFirstChildWhichIsA("BasePart", true)))
    if not mainPart or mainPart:FindFirstChild("LayeredShield") then return end

    local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not myRoot then return end

    if (mainPart.Position - myRoot.Position).Magnitude > shieldRange then return end

    local dirToPlayer = (myRoot.Position - mainPart.Position).Unit
    
    -- สร้าง Folder เก็บเกราะเพื่อให้เช็คครั้งเดียวผ่าน
    local shieldFolder = Instance.new("Folder")
    shieldFolder.Name = "LayeredShield"
    shieldFolder.Parent = mainPart

    -- [สร้างเกราะ 5 ชั้น] ชี้เป้ามาหาเรา
    for i = 1, 5 do
        local bumper = Instance.new("Part")
        bumper.Name = "BumperLayer_" .. i
        bumper.Size = Vector3.new(12, 12, 2) -- หนาชั้นละ 2 บล็อค
        bumper.Transparency = 0.7
        bumper.Material = Enum.Material.ForceField
        bumper.Color = Color3.fromRGB(0, 255, 255)
        bumper.CanCollide = true
        bumper.CanTouch = false
        bumper.Massless = true
        bumper.Anchored = mainPart.Anchored
        
        -- วางเกราะเรียงแถวหน้ากระดานยื่นมาหาตัวเรา ระยะห่างกันชั้นละ 4 บล็อค
        local offset = i * 6
        bumper.CFrame = CFrame.lookAt(mainPart.Position + (dirToPlayer * offset), myRoot.Position)
        
        local weld = Instance.new("WeldConstraint")
        weld.Part0 = bumper; weld.Part1 = mainPart; weld.Parent = bumper
        bumper.Parent = shieldFolder
    end

    -- ล้าง TouchInterest ของกระสุนดั้งเดิม
    pcall(function()
        mainPart.CanCollide = false
        for _, v in pairs(hazard:GetDescendants()) do
            if v:IsA("BasePart") then v.CanCollide = false end
            if v:IsA("TouchInterest") then v:Destroy() end
        end
    end)
end

-- --- SUPPORT LOOPS ---
RunService.Stepped:Connect(function()
    if autoDodgeEnabled then
        local effects = workspace:FindFirstChild("Dungeon") and workspace.Dungeon:FindFirstChild("Effects")
        if effects then
            for _, v in pairs(effects:GetChildren()) do
                if v:IsA("Model") then -- เช็ค Model เป็นหลัก (รวม Eruption)
                    handleEruptionV9(v)
                elseif v.Name == "Arrow" or v.Name:match("Magic$") then
                    handleProjectileV9(v)
                end
            end
        end
    end
end)

-- Loop ดึงเงิน (เดิมๆ)
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
                            local function getProbingDirection(myR, tPos)
                                local curPos = myR.Position
                                local baseDir = (tPos - curPos).Unit
                                local scanAngles = {0, 30, -30, 60, -60, 90, -90, 135, -135} 
                                local bestDir = nil; local maxDist = 0
                                for _, angle in ipairs(scanAngles) do
                                    local dir = (CFrame.Angles(0, math.rad(angle), 0) * Vector3.new(baseDir.X, 0, baseDir.Z)).Unit
                                    local ray = workspace:Raycast(curPos, dir * 15, rayParams)
                                    local d = ray and ray.Distance or 15
                                    if d > maxDist then maxDist = d; bestDir = dir end
                                end
                                return bestDir
                            end
                            
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
