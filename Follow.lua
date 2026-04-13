local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("KONG GUISUS - SMOOTH", "DarkTheme")
local Tab = Window:NewTab("Main")
local Section = Tab:NewSection("Corner Cutting Navigation")

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

-- --- MAIN LOOP ---
task.spawn(function()
    while true do
        task.wait(0.12)
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
                rayParams.FilterDescendantsInstances = {myChar, target.Character}

                if dist > followDistance then
                    local moveDir = (targetPos - currentPos).Unit
                    local directRay = workspace:Raycast(currentPos, moveDir * dist, rayParams)

                    if not directRay then
                        -- 1. ทางโล่ง วิ่งตรงหาตัวเลย
                        isProbing = false
                        currentWaypoints = {}
                        updateDebug("DirectTrace", currentPos, targetPos, Color3.fromRGB(0, 255, 0))
                        myHuman:MoveTo(targetPos)
                    else
                        -- 2. ทางตัน -> คำนวณเส้นทาง
                        if os.clock() - lastComputeTime > 1.2 or (targetPos - lastTargetPos).Magnitude > 8 then
                            local path = PathfindingService:CreatePath({AgentRadius = 3, AgentHeight = 5, AgentCanJump = true})
                            path:ComputeAsync(currentPos, targetPos)
                            
                            if path.Status == Enum.PathStatus.Success then
                                isProbing = false
                                currentWaypoints = path:GetWaypoints()
                                currentWaypointIndex = 2
                                lastTargetPos = targetPos
                                lastComputeTime = os.clock()
                                if debugEnabled then
                                    clearVisuals()
                                    for i, wp in ipairs(currentWaypoints) do
                                        local p = Instance.new("Part")
                                        p.Name, p.Size, p.Position = "WP_Debug", Vector3.new(0.6,0.6,0.6), wp.Position
                                        p.Anchored, p.CanCollide, p.CanQuery, p.Transparency = true, false, false, 0.5
                                        p.Color, p.Material = Color3.fromRGB(0, 255, 255), Enum.Material.Neon
                                        p.Parent = workspace.Terrain
                                    end
                                end
                            else
                                isProbing = true
                                currentWaypoints = {}
                            end
                        end

                        -- ** ส่วนตัดสินใจเดินแบบตัดทางลัด (Path Smoothing) **
                        if #currentWaypoints > 0 then
                            -- มองหาจุดที่ไกลที่สุดที่ยังมองเห็นได้โดยไม่ติดกำแพง
                            local furthestVisibleIndex = currentWaypointIndex
                            
                            for i = currentWaypointIndex, #currentWaypoints do
                                local wp = currentWaypoints[i]
                                local toWP = (wp.Position - currentPos).Unit
                                local distToWP = (wp.Position - currentPos).Magnitude
                                
                                -- ยิง Ray ไปหาจุดบล็อกที่ i
                                local occluder = workspace:Raycast(currentPos, toWP * distToWP, rayParams)
                                
                                if not occluder then
                                    -- ถ้ามองเห็นจุดที่ i ให้จำไว้ว่าเป็นจุดที่ไกลที่สุดที่ตัดทางลัดได้
                                    furthestVisibleIndex = i
                                else
                                    -- ถ้าเริ่มมองไม่เห็นจุดนี้แล้ว แสดงว่ามุมเลี้ยวอยู่ระหว่างทาง หยุดเช็ค
                                    break
                                end
                            end
                            
                            currentWaypointIndex = furthestVisibleIndex
                            local targetWP = currentWaypoints[currentWaypointIndex]
                            
                            if targetWP then
                                myHuman:MoveTo(targetWP.Position)
                                updateDebug("PathTrace", currentPos, targetWP.Position, Color3.fromRGB(255, 255, 0)) -- เส้นเหลืองคือทางลัด
                                
                                -- เช็คระยะแนวราบเพื่อเลื่อน Index
                                local dist2D = (Vector2.new(currentPos.X, currentPos.Z) - Vector2.new(targetWP.Position.X, targetWP.Position.Z)).Magnitude
                                if dist2D < 3.5 then
                                    currentWaypointIndex = currentWaypointIndex + 1
                                end
                                
                                if targetWP.Action == Enum.PathWaypointAction.Jump or targetWP.Position.Y > currentPos.Y + 2 then
                                    forceJump(myHuman)
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
