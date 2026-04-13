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
local isProbing = false -- โหมดแหย่ทางเมื่อ Pathfinding ล้มเหลว

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

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

-- ฟังก์ชันหาทางเดิน "แหย่" เมื่อติดในตึก
local function getProbingDirection(myRoot, targetPos)
    local currentPos = myRoot.Position
    local baseDir = (targetPos - currentPos).Unit
    local scanAngles = {0, 30, -30, 60, -60, 90, -90, 135, -135} -- กวาดเกือบรอบตัว
    
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

-- --- UI ---
Section:NewDropdown("Target Mode", "Mode", {"Manual", "Max HP", "Min HP"}, function(m) SelectedMode = m end)
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
    if not s then currentWaypoints = {}; clearVisuals(); isProbing = false end
end)
MoveSection:NewToggle("Show Path", "Visuals", function(s) debugEnabled = s end)
MoveSection:NewSlider("Distance", "Gap", 20, 1, function(s) followDistance = s end)

-- --- Helper Functions (เพิ่มฟังก์ชันเช็คเหว) ---
local function forceJump(hum)
    if hum.FloorMaterial ~= Enum.Material.Air then
        hum.Jump = true
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end

-- ฟังก์ชันเช็คว่าข้างหน้ามีพื้นไหม (กันตกเหว)
local function isGapAhead(myRoot, moveDir)
    local checkPos = myRoot.Position + (moveDir * 4) -- มองล่วงหน้าไป 4 สตั๊ด
    local rayDown = workspace:Raycast(checkPos, Vector3.new(0, -10, 0), rayParams) -- ยิงเรย์ลงพื้น 10 สตั๊ด
    return rayDown == nil -- ถ้าเป็น nil แปลว่าไม่มีพื้น (เป็นเหว)
end

-- ฟังก์ชันหาทางเดิน "แหย่" เมื่อติดในตึก (ปรับปรุง)
local function getProbingDirection(myRoot, targetPos)
    local currentPos = myRoot.Position
    local baseDir = (Vector3.new(targetPos.X, currentPos.Y, targetPos.Z) - currentPos).Unit -- ตัดแกน Y ออกเวลาคำนวณทิศ
    local scanAngles = {0, 30, -30, 60, -60, 90, -90, 135, -135} 
    
    local bestDir = nil
    local maxDist = 0
    
    for _, angle in ipairs(scanAngles) do
        local dir = (CFrame.Angles(0, math.rad(angle), 0) * baseDir).Unit
        local ray = workspace:Raycast(currentPos, dir * 15, rayParams)
        local d = ray and ray.Distance or 15
        
        -- เลือกทิศที่ไปได้ไกลที่สุด และ "ต้องไม่มีเหว" ข้างหน้า
        if d > maxDist and not isGapAhead(myRoot, dir) then
            maxDist = d
            bestDir = dir
        end
    end
    return bestDir or baseDir -- ถ้าตันหมดก็พุ่งไปตรงๆ
end

-- --- MAIN LOOP (ปรับปรุงตรรกะการเดิน) ---
task.spawn(function()
    while true do
        task.wait(0.15)
        if not followEnabled then continue end
        
        pcall(function()
            -- (ส่วนการเลือก Target คงเดิม...)
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

            if not target or not target.Character or not target.Character:FindFirstChild("HumanoidRootPart") then return end

            local myChar = LocalPlayer.Character
            local myHuman = myChar:FindFirstChildOfClass("Humanoid")
            local myRoot = myChar:FindFirstChild("HumanoidRootPart")
            local tRoot = target.Character.HumanoidRootPart
            
            if myHuman and myRoot then
                local currentPos = myRoot.Position
                local targetPos = tRoot.Position
                
                -- แยกคำนวณระยะทางแบบ 2D (แนวราบ) และ ความสูง (แนวดิ่ง)
                local dist2D = (Vector2.new(targetPos.X, targetPos.Z) - Vector2.new(currentPos.X, currentPos.Z)).Magnitude
                local distY = targetPos.Y - currentPos.Y
                local totalDist = (targetPos - currentPos).Magnitude
                
                rayParams.FilterDescendantsInstances = {myChar, target.Character}

                -- ถ้าเป้าหมายอยู่สูงมาก และแนวราบอยู่ใกล้กัน (แปลว่าติดอยู่ใต้เท้าเป้าหมาย)
                if distY > 10 and dist2D < 10 then
                    -- แก้ปัญหาติดใต้เท้า: ผู้เล่นกระโดดไม่ถึง ต้องหาทางเลี่ยง หรือใช้ Tween (ในที่นี้บังคับเดินออกห่างก่อน)
                    local retreatDir = (currentPos - Vector3.new(targetPos.X, currentPos.Y, targetPos.Z)).Unit
                    myHuman:MoveTo(currentPos + (retreatDir * 10))
                    return
                end

                if totalDist > followDistance then
                    -- 1. ลองเดินตรง (Line of Sight)
                    local moveDir = (Vector3.new(targetPos.X, currentPos.Y, targetPos.Z) - currentPos).Unit
                    local directRay = workspace:Raycast(currentPos, moveDir * dist2D, rayParams)

                    if not directRay then
                        -- ทางราบโล่ง ลองเช็คว่ามีเหวไหม
                        if isGapAhead(myRoot, moveDir) then
                            forceJump(myHuman) -- ถ้าเป็นเหวให้กระโดดข้าม
                        end
                        isProbing = false
                        currentWaypoints = {}
                        updateDebug("DirectTrace", currentPos, targetPos, Color3.fromRGB(0, 255, 0))
                        myHuman:MoveTo(targetPos)
                    else
                        -- 2. ติดสิ่งกีดขวาง -> ใช้ Pathfinding
                        if os.clock() - lastComputeTime > 1.0 or (targetPos - lastTargetPos).Magnitude > 8 then
                            -- เพิ่ม AgentParameters ให้รองรับพื้นที่กว้างขึ้น
                            local path = PathfindingService:CreatePath({
                                AgentRadius = 2.0, 
                                AgentHeight = 5.0, 
                                AgentCanJump = true,
                                WaypointSpacing = 4 -- บังคับให้จุดถี่ขึ้น
                            })
                            path:ComputeAsync(currentPos, targetPos)
                            
                            if path.Status == Enum.PathStatus.Success then
                                isProbing = false
                                currentWaypoints = path:GetWaypoints()
                                currentWaypointIndex = 2
                                lastTargetPos = targetPos
                                lastComputeTime = os.clock()
                                -- (Debug Visuals คงเดิม...)
                            else
                                isProbing = true
                                currentWaypoints = {}
                            end
                        end

                        -- ** ส่วนตัดสินใจเดิน **
                        if isProbing then
                            local probeDir = getProbingDirection(myRoot, targetPos)
                            if probeDir then
                                updateDebug("ProbeTrace", currentPos, currentPos + (probeDir * 5), Color3.fromRGB(255, 165, 0))
                                
                                -- ถ้าข้างหน้าเป็นกำแพง หรือเป็นเหว ให้กระโดด
                                local wallCheck = workspace:Raycast(currentPos, probeDir * 4, rayParams)
                                if wallCheck or isGapAhead(myRoot, probeDir) then 
                                    forceJump(myHuman) 
                                end
                                
                                myHuman:MoveTo(currentPos + (probeDir * 8))
                            end
                        elseif #currentWaypoints > 0 then
                            local wp = currentWaypoints[currentWaypointIndex]
                            if wp then
                                -- ถ้าตำแหน่ง Waypoint สูงกว่า หรือเป็น Jump Action ให้กระโดด
                                if wp.Action == Enum.PathWaypointAction.Jump or (wp.Position.Y > currentPos.Y + 2) then
                                    forceJump(myHuman)
                                end
                                
                                -- เช็คเหวก่อนเดินตาม Waypoint เพื่อความชัวร์ (บางที NavMesh วาดข้ามเหว)
                                local wpDir = (wp.Position - currentPos).Unit
                                if isGapAhead(myRoot, wpDir) then
                                    forceJump(myHuman)
                                end

                                myHuman:MoveTo(wp.Position)
                                
                                -- เปลี่ยนระยะเช็คความใกล้ของ Waypoint ให้แม่นขึ้น
                                if (Vector3.new(currentPos.X, 0, currentPos.Z) - Vector3.new(wp.Position.X, 0, wp.Position.Z)).Magnitude < 3 then
                                    currentWaypointIndex = currentWaypointIndex + 1
                                end
                            end
                        end
                    end
                else
                    -- หยุดเมื่อถึงเป้าหมาย
                    myHuman:MoveTo(currentPos)
                end
            end
        end)
    end
end)
