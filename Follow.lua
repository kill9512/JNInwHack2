-- รอให้เกมโหลดเสร็จก่อน ป้องกัน UI ไม่ขึ้น
if not game:IsLoaded() then game.Loaded:Wait() end

local success, Library = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
end)

if not success or not Library then
    warn("โหลด Kavo UI ไม่สำเร็จ! ลิ้งค์อาจจะล่ม หรือ Executor ไม่รองรับ")
    return
end

local Window = Library.CreateLib("KONG GUISUS - STRATEGIST", "DarkTheme")
local Tab = Window:NewTab("Main")
local Section = Tab:NewSection("Tactical Navigation (Plan in Plan)")

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
local stuckTimer = 0
local lastPos = Vector3.new()

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
        if v.Name == "WP_Debug" or v.Name == "DirectTrace" or v.Name == "ProbeTrace" or v.Name == "ShoulderL" or v.Name == "ShoulderR" then v:Destroy() end
    end
end

-- --- Helper Functions ---
local function forceJump(hum)
    if hum.FloorMaterial ~= Enum.Material.Air then
        hum.Jump = true
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end

-- เช็คความกว้างของช่องทางเดิน
local function checkShoulderClearance(myRoot, moveDir)
    local leftSide = (CFrame.Angles(0, math.rad(45), 0) * moveDir).Unit
    local rightSide = (CFrame.Angles(0, math.rad(-45), 0) * moveDir).Unit
    
    local hitL = workspace:Raycast(myRoot.Position, leftSide * 3.5, rayParams)
    local hitR = workspace:Raycast(myRoot.Position, rightSide * 3.5, rayParams)
    
    if debugEnabled then
        updateDebug("ShoulderL", myRoot.Position, myRoot.Position + leftSide * 3.5, Color3.fromRGB(255, 255, 255))
        updateDebug("ShoulderR", myRoot.Position, myRoot.Position + rightSide * 3.5, Color3.fromRGB(255, 255, 255))
    end
    
    return hitL, hitR
end

-- ฟังก์ชันหาทางแหย่
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
        if d > maxDist then maxDist = d; bestDir = dir end
    end
    return bestDir
end

-- --- UI SETUP (แก้ไขป้องกันบั๊กพัง) ---
Section:NewDropdown("Target Mode", "Mode", {"Manual", "Max HP", "Min HP"}, function(m) SelectedMode = m end)

-- ใส่ "None (Off)" ไว้เป็นค่าเริ่มต้น ป้องกันบั๊ก Kavo ทะลุเวลาอ่านตารางว่าง {}
local drop = Section:NewDropdown("Select Target", "User", {"None (Off)"}, function(s) 
    if s and s ~= "None (Off)" then
        SelectedPlayerName = s:match("@([^%)]+)") 
    else
        SelectedPlayerName = nil
    end
end)

local function refreshList()
    local t = {"None (Off)"}
    for _, p in pairs(Players:GetPlayers()) do 
        if p ~= LocalPlayer then table.insert(t, p.DisplayName.." (@"..p.Name..")") end 
    end
    -- ใช้ pcall กันพังเวลา Kavo หา object ไม่เจอ
    pcall(function() drop:Refresh(t) end)
end
Section:NewButton("Refresh List", "Update", refreshList)

local MoveSection = Tab:NewSection("Tactical Navigation")
MoveSection:NewToggle("Enable Follow", "Start Logic", function(s) 
    followEnabled = s 
    if not s then currentWaypoints = {}; clearVisuals(); isProbing = false end
end)
MoveSection:NewToggle("Show Path", "Visuals", function(s) debugEnabled = s end)
MoveSection:NewSlider("Distance", "Gap", 20, 1, function(s) followDistance = s end)

-- พยายามอัปเดตรายชื่อครั้งแรกแบบปลอดภัย
task.spawn(function() task.wait(0.5); refreshList() end)

-- --- MAIN LOOP ---
task.spawn(function()
    while true do
        task.wait(0.12)
        if not followEnabled then continue end
        
        pcall(function()
            local target = nil
            if SelectedMode == "Manual" then target = Players:FindFirstChild(SelectedPlayerName or "")
            else
                local bestHP = (SelectedMode == "Max HP") and -1 or math.huge
                for _, p in pairs(Players:GetPlayers()) do
                    if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("Humanoid") then
                        local hp = p.Character.Humanoid.Health
                        if (SelectedMode == "Max HP" and hp > bestHP) or (SelectedMode == "Min HP" and hp < bestHP) then bestHP = hp; target = p end
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
                local dist = (targetPos - currentPos).Magnitude
                rayParams.FilterDescendantsInstances = {myChar, target.Character}

                -- ระบบ Anti-Stuck (เช็คเวลาติดกำแพง)
                if (currentPos - lastPos).Magnitude < 0.3 then stuckTimer += 0.12 else stuckTimer = 0 end
                lastPos = currentPos

                if dist > followDistance then
                    local moveDir = (targetPos - currentPos).Unit
                    local directRay = workspace:Raycast(currentPos, moveDir * dist, rayParams)

                    -- แผน 1: เดินตรง (Line of Sight)
                    if not directRay then
                        isProbing = false; currentWaypoints = {}
                        updateDebug("DirectTrace", currentPos, targetPos, Color3.fromRGB(0, 255, 0))
                        myHuman:MoveTo(targetPos)
                    else
                        -- แผน 2: ทางสีฟ้า (Pathfinding)
                        if os.clock() - lastComputeTime > 1.0 or (targetPos - lastTargetPos).Magnitude > 8 or stuckTimer > 1.5 then
                            local path = PathfindingService:CreatePath({AgentRadius = 3, AgentHeight = 5, AgentCanJump = true})
                            path:ComputeAsync(currentPos, targetPos)
                            if path.Status == Enum.PathStatus.Success then
                                isProbing = false; currentWaypoints = path:GetWaypoints(); currentWaypointIndex = 2
                                lastTargetPos = targetPos; lastComputeTime = os.clock()
                                if debugEnabled then clearVisuals() end
                            else
                                isProbing = true; currentWaypoints = {}
                            end
                        end

                        -- แผน 3: แผนซ้อนแผน (แทรกแซงการเดิน)
                        if isProbing then
                            -- โหมดแหย่ทาง (Explorer Mode)
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
                                local wpDir = (wp.Position - currentPos).Unit
                                local hitL, hitR = checkShoulderClearance(myRoot, wpDir)

                                -- ถ้าไหล่ติด หรือเดินติดนานเกินไป
                                if hitL or hitR or stuckTimer > 0.8 then
                                    local detourDir = wpDir
                                    if hitL and not hitR then detourDir = (CFrame.Angles(0, math.rad(-60), 0) * wpDir).Unit
                                    elseif hitR and not hitL then detourDir = (CFrame.Angles(0, math.rad(60), 0) * wpDir).Unit
                                    else detourDir = (CFrame.Angles(0, math.rad(180), 0) * wpDir).Unit end
                                    
                                    if stuckTimer > 1.5 then
                                        currentWaypoints = {} -- ล้างทางทิ้งถ้าติดหนัก
                                        myHuman:MoveTo(currentPos + detourDir * 6)
                                        forceJump(myHuman)
                                    else
                                        myHuman:MoveTo(currentPos + detourDir * 4)
                                        forceJump(myHuman)
                                    end
                                else
                                    -- ทางโล่ง เดินต่อ
                                    myHuman:MoveTo(wp.Position)
                                    if (Vector2.new(currentPos.X, currentPos.Z) - Vector2.new(wp.Position.X, wp.Position.Z)).Magnitude < 3.5 then
                                        currentWaypointIndex = currentWaypointIndex + 1
                                    end
                                    if wp.Action == Enum.PathWaypointAction.Jump or wp.Position.Y > currentPos.Y + 2 then
                                        forceJump(myHuman)
                                    end
                                end
                            end
                        end
                        updateDebug("DirectTrace", currentPos, directRay.Position, Color3.fromRGB(255, 0, 0))
                    end
                else
                    myHuman:MoveTo(currentPos)
                end
            end
        end)
    end
end)
