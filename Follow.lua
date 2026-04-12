local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("KONG GUISUS", "DarkTheme")
local Tab = Window:NewTab("Main")
local Section = Tab:NewSection("Advanced Visual Pathing")

-- --- Services ---
local Players = game.Players
local LocalPlayer = Players.LocalPlayer

-- --- Variables ---
local SelectedMode = "Manual"
local SelectedPlayerName = nil
local followDistance = 5
local followEnabled = false
local debugEnabled = false

local lockedTargetPos = nil
local lockTimer = 0

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- --- Folder สำหรับเก็บบล็อก Debug ---
local debugFolder = workspace:FindFirstChild("DebugPathFolder") or Instance.new("Folder", workspace)
debugFolder.Name = "DebugPathFolder"

local function clearBlocks()
    debugFolder:ClearAllChildren()
end

local function createVisualBlock(pos, color)
    if not debugEnabled then return end
    local p = Instance.new("Part")
    p.Size = Vector3.new(1.5, 1.5, 1.5)
    p.Position = pos
    p.Anchored = true
    p.CanCollide = false
    p.Transparency = 0.3
    p.Color = color
    p.Material = Enum.Material.Neon
    p.Parent = debugFolder
    return p
end

local function forceJump(hum)
    if hum.FloorMaterial ~= Enum.Material.Air then
        hum.Jump = true
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end

-- --- ฟังก์ชันใหม่: เช็คว่าพิกัดเป้าหมายอยู่ในของแข็งไหม ---
local function isPositionClear(pos)
    local hitParts = workspace:GetPartBoundsInRadius(pos, 2, rayParams) -- เช็ครัศมี 2 studs
    for _, part in ipairs(hitParts) do
        if part.CanCollide then return false end -- ถ้าเจอ Part ที่มี Collision = ตัน
    end
    return true
end

-- --- Logic ค้นหาทางที่ดีที่สุด ---
local function calculateBestPath(myRoot, targetPos)
    local currentPos = myRoot.Position
    local moveDir = (targetPos - currentPos).Unit
    local stepSize = 4
    
    clearBlocks()

    -- 1. เช็คทางตรง (ลากบล็อก 4 สเต็ป)
    local hitPos = nil
    for i = 1, 4 do
        local checkPos = currentPos + (moveDir * ((i-1) * stepSize))
        local nextExpectedPos = currentPos + (moveDir * (i * stepSize))
        
        local hit = workspace:Raycast(checkPos, moveDir * stepSize, rayParams)
        
        if hit or not isPositionClear(nextExpectedPos) then
            hitPos = hit and hit.Position or nextExpectedPos
            createVisualBlock(hitPos, Color3.fromRGB(255, 0, 0)) -- บล็อกแดง
            break
        else
            createVisualBlock(nextExpectedPos, Color3.fromRGB(0, 255, 0)) -- บล็อกเขียว
        end
    end

    -- 2. ถ้าชนกำแพง ให้วิเคราะห์หาทางออก
    if hitPos then
        -- ** เช็คกระโดด (ต้องผ่าน 2 เงื่อนไข: สูงไม่เกินหัว, หนาไม่เกิน 24 studs) **
        local jumpDir = moveDir
        -- ยิง Ray ข้ามหัว (สูง 4 studs) ไป 24 studs
        local overHeadRay = workspace:Raycast(currentPos + Vector3.new(0, 4, 0), jumpDir * 24, rayParams)
        
        if not overHeadRay then
            -- ถ้าข้ามหัวโล่ง ต้องเช็คว่า "จุดลงจอด" ไม่ทะลุกำแพงด้วย
            local landingPos = hitPos + (jumpDir * 6)
            if isPositionClear(landingPos) then
                createVisualBlock(landingPos, Color3.fromRGB(255, 255, 0)) -- บล็อกเหลือง = ให้กระโดด
                return landingPos, true, true 
            end
        end

        -- ** 3. ถ้ากระโดดไม่ได้ ให้หาทางเลี้ยว (ซ้าย/ขวา) **
        local scanAngles = {90, -90, 45, -45, 135, -135} -- สแกนมุมกว้างขึ้นเพื่อแก้ติดมุม
        local bestPos = nil
        local minDist = math.huge

        for _, angle in ipairs(scanAngles) do
            local dir = (CFrame.Angles(0, math.rad(angle), 0) * moveDir).Unit
            
            -- ยิง Ray เช็คทางเลี้ยว (ระยะ 10 studs)
            local sideHit = workspace:Raycast(currentPos, dir * 10, rayParams)
            
            if not sideHit then
                local testPos = currentPos + (dir * 8)
                
                -- ** แก้บั๊กบล็อกฟ้าทะลุกำแพง: เช็คให้ชัวร์ว่าจุดหมายปลายทางของบล็อกฟ้าว่างจริงๆ **
                if isPositionClear(testPos) then
                    local distToTarget = (testPos - targetPos).Magnitude
                    
                    if distToTarget < minDist then
                        minDist = distToTarget
                        bestPos = testPos
                    end
                end
            end
        end

        if bestPos then
            createVisualBlock(bestPos, Color3.fromRGB(0, 255, 255)) -- บล็อกฟ้า
            return bestPos, true, false
        else
            -- ถ้าตันทุกทาง ให้ถอยหลัง
            local fallback = currentPos - (moveDir * 5)
            if isPositionClear(fallback) then
                createVisualBlock(fallback, Color3.fromRGB(255, 100, 100))
                return fallback, true, false
            end
        end
    end

    return targetPos, false, false
end

-- --- UI Setup ---
Section:NewDropdown("Target Mode", "Choose Mode", {"Manual", "Max HP", "Min HP"}, function(m) SelectedMode = m end)
local drop = Section:NewDropdown("Select Target", "User", {}, function(s) 
    SelectedPlayerName = s:match("@([^%)]+)") 
end)

local function refresh()
    local t = {"None (Off)"}
    for _, p in pairs(Players:GetPlayers()) do 
        if p ~= LocalPlayer then table.insert(t, p.DisplayName.." (@"..p.Name..")") end 
    end
    drop:Refresh(t)
end
Section:NewButton("Refresh List", "Update", refresh)
refresh()

local MoveSection = Tab:NewSection("Control & Debug")
MoveSection:NewToggle("Enable Follow", "Start Follow Logic", function(s) followEnabled = s end)
MoveSection:NewToggle("Show Path Blocks", "Spawn Visual Blocks", function(s) 
    debugEnabled = s 
    if not s then clearBlocks() end
end)
MoveSection:NewSlider("Follow Distance", "Gap", 20, 1, function(s) followDistance = s end)

-- --- LOGIC CORE ---
task.spawn(function()
    while task.wait(0.1) do
        if not followEnabled then continue end
        
        local target = nil
        if SelectedMode == "Manual" then
            target = Players:FindFirstChild(SelectedPlayerName or "")
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

        if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
            local myChar = LocalPlayer.Character
            local myHuman = myChar and myChar:FindFirstChild("Humanoid")
            local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
            local tRoot = target.Character.HumanoidRootPart
            
            if myHuman and myRoot then
                rayParams.FilterDescendantsInstances = {myChar, target.Character, debugFolder}
                local currentPos = myRoot.Position
                local targetPos = tRoot.Position
                local dist = (targetPos - currentPos).Magnitude

                if dist > followDistance then
                    
                    -- ** ระบบจำเป้าหมาย (Anti-Jitter) **
                    -- แก้ปัญหาติดมุม 4 เหลี่ยมแล้วเปลี่ยนใจกลับ
                    if lockTimer > 0 and lockedTargetPos then
                        lockTimer = lockTimer - 0.1
                        myHuman:MoveTo(lockedTargetPos)
                        
                        -- ถ้าระยะถึงบล็อกเป้าหมายแล้ว ให้ปลดล็อก
                        if (currentPos - lockedTargetPos).Magnitude < 3 then
                            lockTimer = 0
                        end
                        continue
                    end

                    -- คำนวณทางเดินใหม่
                    local nextMovePoint, isDetour, shouldJump = calculateBestPath(myRoot, targetPos)
                    
                    if isDetour then
                        -- เพิ่มเวลาล็อกเป้าเป็น 1.5 วินาที เพื่อให้แน่ใจว่าพ้นเหลี่ยมกำแพงจริงๆ
                        lockedTargetPos = nextMovePoint
                        lockTimer = 1.5 
                        myHuman:MoveTo(lockedTargetPos)
                        
                        if shouldJump then
                            forceJump(myHuman)
                        end
                    else
                        -- ทางปกติ
                        myHuman:MoveTo(nextMovePoint)
                    end
                else
                    myHuman:MoveTo(currentPos)
                    clearBlocks()
                end
            end
        else
            clearBlocks()
        end
    end
end)
