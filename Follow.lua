local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("KONG GUISUS - STABLE", "DarkTheme")
local Tab = Window:NewTab("Main")
local Section = Tab:NewSection("Optimized Pathing")

-- --- Services ---
local Players = game.Players
local LocalPlayer = Players.LocalPlayer
local PathfindingService = game:GetService("PathfindingService")

-- --- Settings & States ---
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

-- --- Debug Visualization ---
local function updateDebug(name, startPos, endPos, color)
    if not debugEnabled then 
        if workspace.Terrain:FindFirstChild(name) then workspace.Terrain[name]:Destroy() end
        return 
    end
    local line = workspace.Terrain:FindFirstChild(name) or Instance.new("LineHandleAdornment")
    line.Name = name
    line.Thickness, line.Transparency, line.AlwaysOnTop = 3, 0.4, true
    line.Adornee = workspace.Terrain
    line.Color3 = color
    line.Length = (startPos - endPos).Magnitude
    line.CFrame = CFrame.lookAt(startPos, endPos)
    line.Parent = workspace.Terrain
end

local function clearVisuals()
    for _, v in pairs(workspace.Terrain:GetChildren()) do
        if v.Name == "WP_Debug" or v.Name == "DirectTrace" then v:Destroy() end
    end
end

-- --- Core Functions ---
local function forceJump(hum)
    if hum.FloorMaterial ~= Enum.Material.Air then
        hum.Jump = true
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
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
    if not s then 
        currentWaypoints = {}
        clearVisuals()
    end
end)
MoveSection:NewToggle("Show Path", "Visuals", function(s) debugEnabled = s end)
MoveSection:NewSlider("Distance", "Gap", 20, 1, function(s) followDistance = s end)

-- --- MAIN LOOP ---
task.spawn(function()
    while true do
        local dt = task.wait(0.15) -- เพิ่มดีเลย์เล็กน้อยเพื่อลด CPU Usage
        
        if not followEnabled then continue end
        
        -- ป้องกันสคริปต์ค้างด้วย pcall
        local status, err = pcall(function()
            local target = nil
            if SelectedMode == "Manual" then
                target = Players:FindFirstChild(SelectedPlayerName or "")
            else
                -- [ค้นหาเป้าหมายตาม HP]
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

            if not target or not target.Character or not target.Character:FindFirstChild("HumanoidRootPart") then 
                return 
            end

            local myChar = LocalPlayer.Character
            local myHuman = myChar:FindFirstChildOfClass("Humanoid")
            local myRoot = myChar:FindFirstChild("HumanoidRootPart")
            local tRoot = target.Character.HumanoidRootPart
            
            if myHuman and myRoot then
                local currentPos = myRoot.Position
                local targetPos = tRoot.Position
                local dist = (targetPos - currentPos).Magnitude
                local heightDiff = targetPos.Y - currentPos.Y
                
                if dist > followDistance then
                    rayParams.FilterDescendantsInstances = {myChar, target.Character}
                    local moveDir = (targetPos - currentPos).Unit
                    
                    -- ** เช็คทางตรง (ข้ามไป Pathfinding ทันทีถ้าเป้าหมายอยู่สูงมาก) **
                    local directRay = nil
                    if heightDiff < 10 then -- ถ้าไม่สูงมาก ลองยิงเส้นตรง
                        directRay = workspace:Raycast(currentPos, moveDir * dist, rayParams)
                    end

                    if not directRay and heightDiff < 10 then
                        -- ทางโล่ง (ระดับราบ)
                        currentWaypoints = {}
                        updateDebug("DirectTrace", currentPos, targetPos, Color3.fromRGB(0, 255, 0))
                        myHuman:MoveTo(targetPos)
                    else
                        -- ทางตัน หรือ เป้าหมายอยู่สูงเกินไป -> คำนวณทางล่วงหน้า
                        if (os.clock() - lastComputeTime > 1.2) or (targetPos - lastTargetPos).Magnitude > 8 then
                            local path = PathfindingService:CreatePath({
                                AgentRadius = 3,
                                AgentHeight = 6,
                                AgentCanJump = true,
                                AgentMaxSlope = 45
                            })
                            
                            path:ComputeAsync(currentPos, targetPos)
                            
                            if path.Status == Enum.PathStatus.Success then
                                currentWaypoints = path:GetWaypoints()
                                currentWaypointIndex = 2
                                lastTargetPos = targetPos
                                lastComputeTime = os.clock()
                                
                                if debugEnabled then
                                    clearVisuals()
                                    for _, wp in ipairs(currentWaypoints) do
                                        local p = Instance.new("Part")
                                        p.Name, p.Size, p.Position = "WP_Debug", Vector3.new(1,1,1), wp.Position
                                        p.Anchored, p.CanCollide, p.CanQuery = true, false, false
                                        p.Color, p.Material = Color3.fromRGB(0, 160, 255), Enum.Material.Neon
                                        p.Parent = workspace.Terrain
                                    end
                                end
                            end
                        end

                        -- เดินตาม Waypoints
                        if #currentWaypoints > 0 and currentWaypointIndex <= #currentWaypoints then
                            local wp = currentWaypoints[currentWaypointIndex]
                            local dist2D = (Vector2.new(currentPos.X, currentPos.Z) - Vector2.new(wp.Position.X, wp.Position.Z)).Magnitude
                            
                            if dist2D < 3.5 then
                                currentWaypointIndex = currentWaypointIndex + 1
                            end
                            
                            if wp then
                                myHuman:MoveTo(wp.Position)
                                if wp.Action == Enum.PathWaypointAction.Jump or wp.Position.Y > currentPos.Y + 2 then
                                    forceJump(myHuman)
                                end
                            end
                        end
                        if directRay then updateDebug("DirectTrace", currentPos, directRay.Position, Color3.fromRGB(255, 0, 0)) end
                    end
                else
                    myHuman:MoveTo(currentPos)
                end
            end
        end)
        
        if not status then
            warn("AI Loop Error: " .. err)
            task.wait(1) -- ถ้า Error ให้หยุดพัก 1 วินาทีกันค้าง
        end
    end
end)
