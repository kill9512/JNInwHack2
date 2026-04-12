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

-- --- Logic ค้นหาทางที่ดีที่สุด ---
local function calculateBestPath(myRoot, targetPos)
    local currentPos = myRoot.Position
    local moveDir = (targetPos - currentPos).Unit
    local stepSize = 4
    
    clearBlocks()

    -- 1. ลากบล็อกทางตรง
    local hitPos = nil
    for i = 1, 4 do
        local checkPos = currentPos + (moveDir * ((i-1) * stepSize))
        local hit = workspace:Raycast(checkPos, moveDir * stepSize, rayParams)
        
        if hit then
            hitPos = hit.Position
            createVisualBlock(hitPos, Color3.fromRGB(255, 0, 0)) -- บล็อกแดง = ชนกำแพง
            break
        else
            createVisualBlock(currentPos + (moveDir * (i * stepSize)), Color3.fromRGB(0, 255, 0)) -- บล็อกเขียว = ทางสะดวก
        end
    end

    -- 2. ถ้าชนกำแพง ให้วิเคราะห์หาทางออก
    if hitPos then
        -- เช็คกระโดด: ยิง Ray เหนือหัว (ความสูง +4) ไปข้างหน้า 15 studs
        local jumpRay = workspace:Raycast(currentPos + Vector3.new(0, 4, 0), moveDir * 15, rayParams)
        
        if not jumpRay then
            -- ถ้าข้างบนโล่ง แปลว่ากำแพงเตี้ยหรือแคบพอจะกระโดดข้ามได้!
            local landingPos = hitPos + (moveDir * 6) -- จุดลงจอดหลังกำแพง
            createVisualBlock(landingPos, Color3.fromRGB(255, 255, 0)) -- บล็อกเหลือง = ให้กระโดด
            return landingPos, true, true -- (ตำแหน่ง, เป็นทางเลี่ยงไหม, ต้องกระโดดไหม)
        end

        -- ถ้ากระโดดไม่ได้ ให้หาทางเลี้ยว (ซ้าย/ขวา)
        -- สแกน 90, 45, -45, -90 องศา
        local scanAngles = {90, 45, -45, -90}
        local bestPos = nil
        local minDist = math.huge

        for _, angle in ipairs(scanAngles) do
            local dir = (CFrame.Angles(0, math.rad(angle), 0) * moveDir).Unit
            
            -- ยิง Ray ไปทางที่จะเลี้ยวว่ามีกำแพงไหม?
            local sideHit = workspace:Raycast(currentPos, dir * 12, rayParams)
            
            if not sideHit then
                -- ถ้าไม่มีกำแพง ลองคำนวณว่าระยะห่างจากจุดนี้ไปหาเป้าหมาย ใกล้ขึ้นไหม?
                local testPos = currentPos + (dir * 10)
                local distToTarget = (testPos - targetPos).Magnitude
                
                if distToTarget < minDist then
                    minDist = distToTarget
                    bestPos = testPos
                end
            end
        end

        if bestPos then
            createVisualBlock(bestPos, Color3.fromRGB(0, 255, 255)) -- บล็อกฟ้า = ทางเลี้ยวที่ปลอดภัย
            return bestPos, true, false
        else
            -- ถ้าตันทุกทาง ให้ถอยหลังนิดหน่อย
            local fallback = currentPos - (moveDir * 5)
            createVisualBlock(fallback, Color3.fromRGB(255, 100, 100))
            return fallback, true, false
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
                    
                    -- ระบบจำเป้าหมาย (Anti-Jitter)
                    if lockTimer > 0 and lockedTargetPos then
                        lockTimer = lockTimer - 0.1
                        myHuman:MoveTo(lockedTargetPos)
                        
                        -- ถ้าระยะถึงบล็อกเป้าหมายแล้ว ให้ปลดล็อกก่อนเวลา
                        if (currentPos - lockedTargetPos).Magnitude < 3 then
                            lockTimer = 0
                        end
                        continue
                    end

                    -- คำนวณทางเดินใหม่
                    local nextMovePoint, isDetour, shouldJump = calculateBestPath(myRoot, targetPos)
                    
                    if isDetour then
                        -- ถ้าเป็นทางเลี้ยวหรือต้องกระโดด ให้ "ล็อก" เป้าหมายนี้ไว้ 1 วินาที
                        lockedTargetPos = nextMovePoint
                        lockTimer = 1.0 
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
