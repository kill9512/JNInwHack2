local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("KONG GUISUS", "DarkTheme")
local Tab = Window:NewTab("Main")
local Section = Tab:NewSection("Architect Path Follower")

-- --- Services ---
local Players = game.Players
local LocalPlayer = Players.LocalPlayer

-- --- Variables ---
local SelectedMode = "Manual"
local SelectedPlayerName = nil
local followDistance = 5
local followEnabled = false
local debugEnabled = false

local currentWaypoint = nil -- จุดหมายชั่วคราวเพื่ออ้อมกำแพง
local maxJumpHeight = 7 -- ความสูงที่กระโดดพ้น (ปรับตามเกม)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local debugFolder = workspace:FindFirstChild("ArchitectDebug") or Instance.new("Folder", workspace)
debugFolder.Name = "ArchitectDebug"

-- --- Utility Functions ---
local function clearDebug()
    debugFolder:ClearAllChildren()
end

local function createPoint(pos, color)
    if not debugEnabled then return end
    local p = Instance.new("Part")
    p.Shape = Enum.PartType.Ball
    p.Size = Vector3.new(1.2, 1.2, 1.2)
    p.Position = pos
    p.Anchored = true
    p.CanCollide = false
    p.Color = color
    p.Transparency = 0.4
    p.Material = Enum.Material.Neon
    p.Parent = debugFolder
end

-- --- Logic: วิเคราะห์สิ่งกีดขวางและความสูง ---
local function analyzePath(myRoot, targetPos)
    local startPos = myRoot.Position
    local moveVec = (targetPos - startPos)
    local moveDir = moveVec.Unit
    
    clearDebug()

    -- 1. ยิง Ray เช็คทางตรง
    local mainRay = workspace:Raycast(startPos, moveDir * 15, rayParams)
    
    if mainRay then
        -- ตรวจสอบความสูงตรงจุดที่ชน
        local hitPos = mainRay.Position
        createPoint(hitPos, Color3.fromRGB(255, 0, 0)) -- จุดสีแดง = ชนกำแพง

        -- ยิง Ray ด้านบนเพื่อเช็คว่ากระโดดพ้นไหม
        local topRay = workspace:Raycast(hitPos + Vector3.new(0, maxJumpHeight, 0), moveDir * 2, rayParams)
        local isJumpable = (not topRay)

        if isJumpable then
            -- ถ้ากระโดดพ้น ให้สร้างจุด Waypoint เหนือหัวกำแพง
            return hitPos + Vector3.new(0, maxJumpHeight + 2, 0), true
        else
            -- ถ้ากระโดดไม่พ้น ให้สแกนหา "ทางเลี่ยงซ้าย/ขวา"
            local scanAngles = {30, -30, 60, -60, 90, -90}
            local bestEscape = nil
            local minOffset = math.huge

            for _, angle in ipairs(scanAngles) do
                local scanDir = (CFrame.Angles(0, math.rad(angle), 0) * moveDir).Unit
                local scanRay = workspace:Raycast(startPos, scanDir * 15, rayParams)

                if not scanRay then
                    -- พบทางว่าง! คำนวณจุดอ้อมที่ใกล้เป้าหมายที่สุด
                    local testPos = startPos + (scanDir * 12)
                    local distToTarget = (testPos - targetPos).Magnitude
                    if distToTarget < minOffset then
                        minOffset = distToTarget
                        bestEscape = testPos
                    end
                end
            end
            
            if bestEscape then
                createPoint(bestEscape, Color3.fromRGB(0, 255, 255)) -- จุดสีฟ้า = ทางเบี่ยง
                return bestEscape, false
            end
        end
    end

    return targetPos, false
end

-- --- UI Setup ---
Section:NewDropdown("Target Mode", "Mode", {"Manual", "Max HP", "Min HP"}, function(m) SelectedMode = m end)
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

local MoveSection = Tab:NewSection("Movement Control")
MoveSection:NewToggle("Enable Follow", "Start AI", function(s) followEnabled = s end)
MoveSection:NewToggle("Debug Mode", "Visual Path Points", function(s) debugEnabled = s if not s then clearDebug() end end)
MoveSection:NewSlider("Follow Distance", "Gap", 20, 1, function(s) followDistance = s end)

-- --- LOGIC CORE ---
task.spawn(function()
    while task.wait(0.1) do
        if not followEnabled then continue end
        
        local target = nil
        -- [ค้นหาเป้าหมายคงเดิม]
        if SelectedMode == "Manual" then target = Players:FindFirstChild(SelectedPlayerName or "") end
        
        if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
            local myChar = LocalPlayer.Character
            local myHuman = myChar and myChar:FindFirstChild("Humanoid")
            local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
            local tRoot = target.Character.HumanoidRootPart
            
            if myHuman and myRoot then
                rayParams.FilterDescendantsInstances = {myChar, target.Character, debugFolder}
                local dist = (tRoot.Position - myRoot.Position).Magnitude

                if dist > followDistance then
                    -- ถ้ายันไม่มี Waypoint ชั่วคราว หรือถึง Waypoint เดิมแล้ว ให้คำนวณใหม่
                    if not currentWaypoint or (myRoot.Position - currentWaypoint).Magnitude < 3 then
                        local nextPoint, shouldJump = analyzePath(myRoot, tRoot.Position)
                        currentWaypoint = nextPoint
                        
                        if shouldJump then
                            myHuman.Jump = true
                        end
                    end
                    
                    -- เดินไปหาจุดที่คำนวณได้
                    myHuman:MoveTo(currentWaypoint)
                else
                    myHuman:MoveTo(myRoot.Position)
                    currentWaypoint = nil
                    clearDebug()
                end
            end
        end
    end
end)
