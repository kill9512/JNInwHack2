local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("KONG GUISUS - INDOOR PRO", "DarkTheme")
local Tab = Window:NewTab("Main")
local Section = Tab:NewSection("Indoor & Tight Spaces Pathing")

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

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- --- Core Functions ---
local function forceJump(hum)
    if hum.FloorMaterial ~= Enum.Material.Air then
        hum.Jump = true
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end

local function clearVisuals()
    for _, v in pairs(workspace.Terrain:GetChildren()) do
        if v.Name == "WP_Debug" or v.Name == "DirectTrace" then v:Destroy() end
    end
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

local MoveSection = Tab:NewSection("Control")
MoveSection:NewToggle("Enable Follow", "Start Logic", function(s) 
    followEnabled = s 
    if not s then currentWaypoints = {}; clearVisuals() end
end)
MoveSection:NewToggle("Show Path", "Visuals", function(s) debugEnabled = s end)
MoveSection:NewSlider("Gap", "Distance", 20, 1, function(s) followDistance = s end)

-- --- MAIN LOOP ---
task.spawn(function()
    while true do
        task.wait(0.1) -- ความถี่กำลังดีสำหรับในอาคาร
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
                
                -- ** ระบบเช็คว่าอยู่ Indoor หรือไม่ (ยิงขึ้นฟ้า) **
                local ceilingCheck = workspace:Raycast(currentPos, Vector3.new(0, 20, 0), rayParams)
                local isIndoor = ceilingCheck ~= nil

                if dist > followDistance then
                    rayParams.FilterDescendantsInstances = {myChar, target.Character}
                    local moveDir = (targetPos - currentPos).Unit
                    
                    -- ** ถ้าอยู่ Indoor หรือมองไม่เห็นตัว ให้ใช้ Pathfinding ทันที **
                    local directRay = workspace:Raycast(currentPos, moveDir * dist, rayParams)
                    
                    if not directRay and not isIndoor then
                        -- ทางโล่ง (Outdoor เท่านั้น)
                        currentWaypoints = {}
                        myHuman:MoveTo(targetPos)
                    else
                        -- ในตึก หรือ ทางตัน -> คำนวณทางล่วงหน้าด้วย Parameter ที่ "เล็ก" ลง
                        if (os.clock() - lastComputeTime > 1.0) or (targetPos - lastTargetPos).Magnitude > 5 then
                            local path = PathfindingService:CreatePath({
                                AgentRadius = 1.8, -- เล็กลงเพื่อมุดประตู
                                AgentHeight = 5,
                                AgentCanJump = true,
                                AgentMaxSlope = 55 -- ชันขึ้นเพื่อบันไดในบ้าน
                            })
                            
                            path:ComputeAsync(currentPos, targetPos)
                            
                            if path.Status == Enum.PathStatus.Success then
                                currentWaypoints = path:GetWaypoints()
                                currentWaypointIndex = 2
                                lastTargetPos = targetPos
                                lastComputeTime = os.clock()
                                
                                if debugEnabled then
                                    clearVisuals()
                                    for i, wp in ipairs(currentWaypoints) do
                                        local p = Instance.new("Part")
                                        p.Name, p.Size, p.Position = "WP_Debug", Vector3.new(0.6, 0.6, 0.6), wp.Position
                                        p.Anchored, p.CanCollide, p.CanQuery = true, false, false
                                        p.Color = (i == currentWaypointIndex) and Color3.fromRGB(255, 255, 0) or Color3.fromRGB(0, 200, 255)
                                        p.Material = Enum.Material.Neon
                                        p.Parent = workspace.Terrain
                                    end
                                end
                            end
                        end

                        -- เดินตาม Waypoints (ระบบมุด)
                        if #currentWaypoints > 0 and currentWaypointIndex <= #currentWaypoints then
                            local wp = currentWaypoints[currentWaypointIndex]
                            local dist2D = (Vector2.new(currentPos.X, currentPos.Z) - Vector2.new(wp.Position.X, wp.Position.Z)).Magnitude
                            
                            -- ถ้ามองเห็น Waypoint ถัดไป (Shortcut) ให้ข้ามจุดปัจจุบันไปเลย (กันเดินชนขอบประตู)
                            if currentWaypoints[currentWaypointIndex + 1] then
                                local nextWp = currentWaypoints[currentWaypointIndex + 1]
                                local lookNext = workspace:Raycast(currentPos, (nextWp.Position - currentPos).Unit * (nextWp.Position - currentPos).Magnitude, rayParams)
                                if not lookNext then
                                    currentWaypointIndex = currentWaypointIndex + 1
                                    wp = nextWp
                                end
                            end

                            if dist2D < 2.5 then -- ระยะเช็คจุดที่แคบลงเพื่อความแม่นยำในอาคาร
                                currentWaypointIndex = currentWaypointIndex + 1
                            end
                            
                            if wp then
                                myHuman:MoveTo(wp.Position)
                                if wp.Action == Enum.PathWaypointAction.Jump or wp.Position.Y > currentPos.Y + 1.5 then
                                    forceJump(myHuman)
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
