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

-- ล็อคระยะหลบแค่ 5 ตามสั่ง
local dodgeDistance = 5 
local lastDodgeTime = 0 -- ตัวแปรคูลดาวน์การหลบ

local currentWaypoints = {}
local currentWaypointIndex = 1
local lastComputeTime = 0
local lastTargetPos = Vector3.new()
local isProbing = false

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

SupportSection:NewToggle("Smart Dodge v2", "สไลด์ 5 บล็อค กันกำแพง+เหว", function(state)
    autoDodgeEnabled = state
end)
-- (เอา Slider ออกไปแล้ว ตามคำขอ)

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
    if not s then currentWaypoints = {}; clearVisuals(); isProbing = false end
end)
MoveSection:NewToggle("Show Path", "Visuals", function(s) debugEnabled = s end)
MoveSection:NewSlider("Distance", "Gap", 20, 1, function(s) followDistance = s end)

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

function clearVisuals()
    for _, v in pairs(workspace.Terrain:GetChildren()) do
        if v.Name == "WP_Debug" or v.Name == "DirectTrace" or v.Name == "ProbeTrace" then v:Destroy() end
    end
end

local function forceJump(hum)
    if hum.FloorMaterial ~= Enum.Material.Air then
        hum.Jump = true
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end

-- --- [ระบบใหม่] เรดาร์สแกน 8 ทิศทาง หูตาสับปะรด ---
local function getSafeDodgePosition(myRoot, hazardPos)
    local myPos = myRoot.Position
    local params = RaycastParams.new()
    -- ไม่สแกนโดนตัวเราและไม่สแกนโดนของอันตรายนั้นๆ
    params.FilterDescendantsInstances = {LocalPlayer.Character, workspace:FindFirstChild("Dungeon")}
    params.FilterType = Enum.RaycastFilterType.Exclude

    -- มุมที่จะลองหนี (0 คือตรงไปข้างหน้า, 180 คือถอยหลัง, 90/-90 คือออกซ้ายขวา)
    local scanAngles = {180, 90, -90, 135, -135, 45, -45, 0}
    
    -- หาเวกเตอร์ที่ชี้ไปหาของอันตราย (ถ้าของมันเสกตรงตีนเป๊ะๆ จะใช้ทิศทางที่หน้าเราหันอยู่แทน)
    local toHazard = (hazardPos - myPos)
    toHazard = Vector3.new(toHazard.X, 0, toHazard.Z)
    if toHazard.Magnitude < 0.1 then
        toHazard = myRoot.CFrame.LookVector
    else
        toHazard = toHazard.Unit
    end

    for _, angle in ipairs(scanAngles) do
        -- หมุนทิศทางหนี
        local escapeDir = CFrame.Angles(0, math.rad(angle), 0) * toHazard
        local testPos = myPos + (escapeDir * dodgeDistance)
        
        -- 1. [เช็คกำแพง] ยิงเลเซอร์ขนานพื้นไปข้างหน้า 5 บล็อค
        local wallHit = workspace:Raycast(myPos, escapeDir * dodgeDistance, params)
        local actualTarget = testPos
        local isWallSafe = true
        
        if wallHit then
            -- ถ้ายิงเจอกำแพงในระยะใกล้กว่า 2 บล็อค แปลว่าทางนี้ตัน
            if (wallHit.Position - myPos).Magnitude < 2 then
                isWallSafe = false
            else
                -- ถ้าไกลพอ ให้วาร์ปไปชิดกำแพงแทน (ถอยออกมาก้าวนึงกันทะลุ)
                actualTarget = wallHit.Position - (escapeDir * 1)
            end
        end

        if isWallSafe then
            -- 2. [เช็คเหว] ยิงเลเซอร์จากจุดที่จะไป ลงไปที่พื้น
            local floorRayOrigin = actualTarget + Vector3.new(0, 3, 0)
            local floorHit = workspace:Raycast(floorRayOrigin, Vector3.new(0, -15, 0), params)
            
            if floorHit then
                -- มีพื้นเหยียบ และไม่ทะลุกำแพง = ทางนี้ปลอดภัย!
                return actualTarget
            end
        end
    end
    
    -- ถ้าลอง 8 ทิศแล้วไม่มีทางหนีเลย (โดนรุมปิดมุม/ยืนอยู่บนเสาเล็กๆ) ให้ยืนเฉยๆ ดีกว่าวาร์ปตกแมพ
    return nil 
end

local function executeDodge(hazard)
    -- ถ้าเพิ่งหลบไปเมื่อกี๊ ให้รอ 0.5 วิ ก่อนถึงจะหลบใหม่ได้ (กันสคริปต์รวน)
    if os.clock() - lastDodgeTime < 0.5 then return end
    
    if not hazard or not hazard.Parent then return end
    
    local isDanger = false
    if hazard.Name == "Eruption" or hazard.Name == "Arrow" or hazard.Name:match("Magic$") then
        isDanger = true
    end
    if not isDanger then return end

    local myChar = LocalPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return end

    local hazardPos = nil
    if hazard:IsA("BasePart") then
        hazardPos = hazard.Position
    elseif hazard:IsA("Model") then
        local p = hazard.PrimaryPart or hazard:FindFirstChildWhichIsA("BasePart", true)
        if p then hazardPos = p.Position end
    end

    if hazardPos then
        -- ถ้าวงเวทย์โผล่มาในระยะ 8 บล็อค (ต้องใช้ 8 เพราะระยะหลบคือ 5 จะได้มีช่องว่าง)
        local dist = (myRoot.Position - hazardPos).Magnitude
        if dist < 8 then
            local safePos = getSafeDodgePosition(myRoot, hazardPos)
            if safePos then
                -- รักษาระดับความสูงแกน Y ไว้
                local finalPos = Vector3.new(safePos.X, myRoot.Position.Y, safePos.Z)
                myRoot.CFrame = CFrame.new(finalPos)
                lastDodgeTime = os.clock() -- บันทึกเวลาที่หลบล่าสุด
            end
        end
    end
end

-- --- SUPPORT LOOPS ---
task.spawn(function()
    while true do
        task.wait(0.1)
        if autoCoinEnabled then
            pcall(function()
                local myChar = LocalPlayer.Character
                local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
                if myRoot then
                    local dungeon = workspace:FindFirstChild("Dungeon")
                    local treasure = dungeon and dungeon:FindFirstChild("Treasure")
                    if treasure then
                        for _, item in pairs(treasure:GetChildren()) do
                            if item.Name == "CoinStack" then
                                if item:IsA("BasePart") then
                                    item.CanCollide = false
                                    item.CFrame = myRoot.CFrame
                                elseif item:IsA("Model") then
                                    item:PivotTo(myRoot.CFrame)
                                    for _, part in pairs(item:GetDescendants()) do
                                        if part:IsA("BasePart") then
                                            part.CanCollide = false
                                            if part:FindFirstChild("TouchInterest") then
                                                part.CFrame = myRoot.CFrame
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end)
        end
    end
end)

-- Heartbeat ให้ทำงานไวสุดๆ
RunService.Heartbeat:Connect(function()
    if autoDodgeEnabled then
        pcall(function()
            local dungeon = workspace:FindFirstChild("Dungeon")
            local effects = dungeon and dungeon:FindFirstChild("Effects")
            if effects then
                for _, v in pairs(effects:GetChildren()) do
                    executeDodge(v)
                end
            end
            if getnilinstances then
                for _, v in pairs(getnilinstances()) do
                    executeDodge(v)
                end
            end
        end)
    end
end)

-- --- MAIN FOLLOW LOOP (คงเดิม) ---
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
