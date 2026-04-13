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

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local lastPosition = Vector3.new()
local lastMoveTick = os.clock()
local randomTarget = nil 
-- --- [เพิ่ม Helper Function ใหม่] ---

-- 1. ฟังก์ชันตรวจจับ "บันไดจำลอง" หรือบล็อกที่ต่อกัน (แก้ปัญหา 1)
local function checkVerticalObstacle(myRoot, moveDir)
    -- ยิง Ray 3 ระดับ: เท้า, เอว, เหนือหัว
    local levels = {0, 3, 6} 
    local hits = 0
    for _, offset in ipairs(levels) do
        local origin = myRoot.Position + Vector3.new(0, offset - 2, 0)
        local ray = workspace:Raycast(origin, moveDir * 3, rayParams)
        if ray then hits = hits + 1 end
    end
    -- ถ้าชนมากกว่า 1 ระดับ แสดงว่าเป็นผนังหรือบันไดที่ปีนได้
    return hits >= 1
end

-- 2. ฟังก์ชันเช็คว่า "โดดลงเหว" ได้ไหม (แก้ปัญหา 2)
local function checkSafeDrop(myRoot, targetPos)
    local horizontalDist = (Vector3.new(targetPos.X, 0, targetPos.Z) - Vector3.new(myRoot.Position.X, 0, myRoot.Position.Z)).Magnitude
    local verticalDist = myRoot.Position.Y - targetPos.Y
    
    -- ถ้าเป้าหมายอยู่ข้างล่าง (เกิน 5 units) และระยะห่างแนวราบไม่ไกลเกินไป
    if verticalDist > 5 and horizontalDist < 15 then
        -- ยิง Ray ลงไปตรงๆ จากขอบเหวเพื่อดูว่ามีพื้นรองรับไหม
        local dropCheck = workspace:Raycast(myRoot.Position + (targetPos - myRoot.Position).Unit * 2, Vector3.new(0, -verticalDist - 5, 0), rayParams)
        if dropCheck then return true end
    end
    return false
end
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
    if not s then currentWaypoints = {}; clearVisuals(); isProbing = false end
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
                
                -- คำนวณระยะทาง
                local trueDist = (targetPos - currentPos).Magnitude
                local hDist = (Vector3.new(targetPos.X, 0, targetPos.Z) - Vector3.new(currentPos.X, 0, currentPos.Z)).Magnitude
                local vDistReal = targetPos.Y - currentPos.Y -- บวก=สูงกว่า / ลบ=ต่ำกว่า
                
                rayParams.FilterDescendantsInstances = {myChar, target.Character}
            
                -- [1. ลำดับความสำคัญสูงสุด: โดดลงเหว]
                if checkSafeDrop(myRoot, targetPos) then
                    updateDebug("DirectTrace", currentPos, targetPos, Color3.fromRGB(255, 0, 255)) -- สีชมพู
                    myHuman:MoveTo(targetPos)
                    -- ถ้าใกล้ขอบ (hDist น้อยลง) ให้กดโดดส่งตัว
                    if hDist < 4 then forceJump(myHuman) end 
                    return -- จบการทำงานรอบนี้ ไม่ต้องไปเช็คอย่างอื่น
                end
            
                -- [2. ปีนบันไดหรือบล็อกลอย]
                local moveDir = (targetPos - currentPos).Unit
                if vDistReal > 2 and hDist < 10 then
                    if checkVerticalObstacle(myRoot, moveDir) or hDist < 4.5 then
                        updateDebug("DirectTrace", currentPos, targetPos, Color3.fromRGB(255, 255, 0)) -- สีเหลือง
                        myHuman:MoveTo(targetPos)
                        forceJump(myHuman)
                        return
                    end
                end
            
                -- [3. การเคลื่อนที่ปกติ (ห่างกว่าระยะ Follow หรือต่างระดับกัน)]
                -- แก้จาก vDist เป็น math.abs(vDistReal)
                if hDist > followDistance or math.abs(vDistReal) > 5 then 
                    local directRay = workspace:Raycast(currentPos, moveDir * trueDist, rayParams)
            
                    -- วิเคราะห์ระดับหัว
                    local headPos = currentPos + Vector3.new(0, 2.5, 0)
                    local headRay = workspace:Raycast(headPos, moveDir * trueDist, rayParams)
            
                    -- วิ่งตรง (ถ้าไม่มีอะไรขวาง หรือขวางแค่ช่วงล่างที่โดดข้ามได้)
                    if not directRay or (directRay and not headRay and hDist < 12) then
                        isProbing = false
                        currentWaypoints = {}
                        myHuman:MoveTo(targetPos)
                        
                        -- ถ้ามีสิ่งกีดขวางเตี้ยๆ ขวางอยู่ ให้โดดข้าม
                        if directRay and (directRay.Position - currentPos).Magnitude < 4.5 then
                            forceJump(myHuman)
                        end
                    else
                        -- [4. Pathfinding สุดท้าย: กรณีทางตันหรือสิ่งกีดขวางสูง]
                        -- (ใช้ Logic Pathfinding เดิมของคุณได้เลยครับ)
                        if os.clock() - lastComputeTime > 0.5 or (targetPos - lastTargetPos).Magnitude > 5 then
                            local path = PathfindingService:CreatePath({
                                AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = true
                            })
                            path:ComputeAsync(currentPos, targetPos)
                            
                            if path.Status == Enum.PathStatus.Success then
                                isProbing = false
                                currentWaypoints = path:GetWaypoints()
                                currentWaypointIndex = 2
                                lastTargetPos = targetPos
                                lastComputeTime = os.clock()
                            else
                                isProbing = true 
                                currentWaypoints = {}
                            end
                        end
                        -- เดินตาม Waypoint ของ Pathfinding
                        if not isProbing and #currentWaypoints > 0 then
                            local wp = currentWaypoints[currentWaypointIndex]
                            if wp then
                                myHuman:MoveTo(wp.Position)
                                if wp.Action == Enum.PathWaypointAction.Jump then forceJump(myHuman) end
                                if (currentPos - wp.Position).Magnitude < 4 then
                                    currentWaypointIndex = currentWaypointIndex + 1
                                end
                            end
                        elseif isProbing then
                            -- โหมด Probing สแกนหาทางออก
                            local probeDir = getProbingDirection(myRoot, targetPos)
                            if probeDir then
                                myHuman:MoveTo(currentPos + (probeDir * 8))
                                if workspace:Raycast(currentPos, probeDir * 4, rayParams) then forceJump(myHuman) end
                            end
                        end
                    end
                else
                    -- อยู่ในระยะหยุด
                    currentWaypoints = {}
                    myHuman:MoveTo(currentPos)
                end
            end
        end)
    end
end)
