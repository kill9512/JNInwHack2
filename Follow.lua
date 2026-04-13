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

-- ปรับปรุงการ Probe ให้ฉลาดขึ้นเวลาอยู่ใต้เท้าเป้าหมาย
local function getProbingDirection(myRoot, targetPos)
    local currentPos = myRoot.Position
    local baseDirXZ = Vector3.new(targetPos.X - currentPos.X, 0, targetPos.Z - currentPos.Z)
    
    -- ถ้าอยู่ใต้เท้าเป้าหมายเป๊ะๆ ให้พยายามเดินไปข้างหน้าและกระโดด
    if baseDirXZ.Magnitude < 2 then
        return myRoot.CFrame.LookVector
    end
    
    local baseDir = baseDirXZ.Unit
    local scanAngles = {0, 45, -45, 90, -90, 180}
    local bestDir = nil
    local maxDist = 0
    
    for _, angle in ipairs(scanAngles) do
        local dir = (CFrame.Angles(0, math.rad(angle), 0) * baseDir).Unit
        local ray = workspace:Raycast(currentPos, dir * 10, rayParams)
        local d = ray and ray.Distance or 10
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

-- --- MAIN LOOP ---
task.spawn(function()
    while true do
        task.wait(0.1) -- ปรับให้ไวขึ้นเล็กน้อยเพื่อการตอบสนอง
        if not followEnabled then continue end
        
        pcall(function()
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
                local dist = (targetPos - currentPos).Magnitude
                local distXZ = (Vector2.new(currentPos.X, currentPos.Z) - Vector2.new(targetPos.X, targetPos.Z)).Magnitude
                rayParams.FilterDescendantsInstances = {myChar, target.Character}

                if dist > followDistance then
                    local yDiff = targetPos.Y - currentPos.Y
                    local moveDir = (targetPos - currentPos).Unit
                    local directRay = workspace:Raycast(currentPos, moveDir * dist, rayParams)

                    -- 1. ลองเดินตรง (ถ้าไม่มีอะไรบัง และความสูงไม่ต่างกันมาก)
                    if not directRay and math.abs(yDiff) < 4 then
                        isProbing = false
                        currentWaypoints = {}
                        myHuman:MoveTo(targetPos)
                    else
                        -- 2. ต้องใช้ Pathfinding หรือติดบล็อกลอย
                        if os.clock() - lastComputeTime > 0.8 or (targetPos - lastTargetPos).Magnitude > 5 then
                            local path = PathfindingService:CreatePath({
                                AgentRadius = 2.0, -- ลดขนาดตัวลงเพื่อให้เบียดบล็อกได้ดีขึ้น
                                AgentHeight = 5, 
                                AgentCanJump = true,
                                WaypointSpacing = 3 -- จุดถี่ขึ้นเพื่อบันไดลอย
                            })
                            path:ComputeAsync(currentPos, targetPos)
                            
                            if path.Status == Enum.PathStatus.Success then
                                isProbing = false
                                currentWaypoints = path:GetWaypoints()
                                currentWaypointIndex = 2
                                lastTargetPos = targetPos
                                lastComputeTime = os.clock()
                            else
                                -- **กรณี Path ล้มเหลว (มักเกิดกับบล็อกลอย)**
                                isProbing = true
                                currentWaypoints = {}
                            end
                        end

                        if isProbing then
                            -- แก้ไข: ถ้าเป้าหมายอยู่ข้างบน และเราอยู่ข้างล่างในระยะใกล้ (ติดใต้บันได)
                            if yDiff > 3 and distXZ < 6 then
                                myHuman:MoveTo(targetPos) -- พยายามเดินพุ่งไปหาจุด XZ ของเป้าหมาย
                                forceJump(myHuman) -- บังคับกระโดดไถขึ้นไปเรื่อยๆ
                            else
                                local probeDir = getProbingDirection(myRoot, targetPos)
                                if probeDir then
                                    myHuman:MoveTo(currentPos + (probeDir * 5))
                                    if yDiff > 2 then forceJump(myHuman) end
                                end
                            end
                        elseif #currentWaypoints > 0 then
                            -- เดินตาม Waypoint ปกติพร้อม Smoothing
                            local wp = currentWaypoints[currentWaypointIndex]
                            if wp then
                                myHuman:MoveTo(wp.Position)
                                
                                -- เช็คกระโดด: ถ้าจุดถัดไปสูงกว่าเรา ให้โดดเลยไม่ต้องรอคำสั่ง Action
                                if wp.Action == Enum.PathWaypointAction.Jump or wp.Position.Y > currentPos.Y + 1.5 then
                                    forceJump(myHuman)
                                end

                                if (currentPos - wp.Position).Magnitude < 4 then
                                    currentWaypointIndex = currentWaypointIndex + 1
                                end
                            end
                        end
                    end
                else
                    myHuman:MoveTo(currentPos)
                end
            end
        end)
    end
end)
