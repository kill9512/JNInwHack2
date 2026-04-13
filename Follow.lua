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
    line.Color3, line.Length = (startPos - endPos).Magnitude
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
    local baseDirXZ = Vector3.new(targetPos.X - currentPos.X, 0, targetPos.Z - currentPos.Z)
    
    if baseDirXZ.Magnitude < 0.1 then
        baseDirXZ = myRoot.CFrame.LookVector 
    else
        baseDirXZ = baseDirXZ.Unit
    end
    
    local scanAngles = {0, 30, -30, 60, -60, 90, -90, 135, -135}
    local bestDir = nil
    local maxDist = 0
    
    for _, angle in ipairs(scanAngles) do
        local dir = (CFrame.Angles(0, math.rad(angle), 0) * baseDirXZ).Unit
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

-- --- MAIN LOOP ---
task.spawn(function()
    while true do
        task.wait(0.15)
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
                    local yDiff = math.abs(targetPos.Y - currentPos.Y)
                    local moveDir = (targetPos - currentPos).Unit
                    local directRay = workspace:Raycast(currentPos, moveDir * dist, rayParams)

                    -- 1. ลองเดินตรง
                    if not directRay and yDiff < 5 then
                        isProbing = false
                        currentWaypoints = {}
                        updateDebug("DirectTrace", currentPos, targetPos, Color3.fromRGB(0, 255, 0))
                        myHuman:MoveTo(targetPos)
                    else
                        -- 2. ทางตัน / อยู่ในตึก / คนละชั้น -> ใช้ Pathfinding
                        if os.clock() - lastComputeTime > 1.0 or (targetPos - lastTargetPos).Magnitude > 8 then
                            local path = PathfindingService:CreatePath({
                                AgentRadius = 2, 
                                AgentHeight = 5, 
                                AgentCanJump = true,
                                AgentMaxJumpHeight = 10, -- เพิ่มค่านี้เพื่อให้ Roblox ยอมคำนวณบล็อคลอยแยกๆ กัน
                                WaypointSpacing = 3 -- บีบระยะห่าง Waypoint ให้ถี่ขึ้นเพื่อกันตกร่อง
                            })
                            path:ComputeAsync(currentPos, targetPos)
                            
                            if path.Status == Enum.PathStatus.Success then
                                isProbing = false
                                currentWaypoints = path:GetWaypoints()
                                currentWaypointIndex = 2
                                lastTargetPos = targetPos
                                lastComputeTime = os.clock()
                                if debugEnabled then
                                    clearVisuals()
                                    for _, wp in ipairs(currentWaypoints) do
                                        local p = Instance.new("Part")
                                        p.Name, p.Size, p.Position = "WP_Debug", Vector3.new(0.8,0.8,0.8), wp.Position
                                        p.Anchored, p.CanCollide, p.CanQuery, p.Transparency = true, false, false, 0.4
                                        p.Color, p.Material = Color3.fromRGB(0, 255, 255), Enum.Material.Neon
                                        p.Parent = workspace.Terrain
                                    end
                                end
                            else
                                isProbing = true
                                currentWaypoints = {}
                            end
                        end

                        if isProbing then
                            local probeDir = getProbingDirection(myRoot, targetPos)
                            if probeDir then
                                updateDebug("ProbeTrace", currentPos, currentPos + (probeDir * 5), Color3.fromRGB(255, 165, 0))
                                myHuman:MoveTo(currentPos + (probeDir * 8))
                                local wallCheck = workspace:Raycast(currentPos, probeDir * 4, rayParams)
                                if wallCheck then forceJump(myHuman) end
                            end
                        elseif #currentWaypoints > 0 then
                            local targetIndex = currentWaypointIndex
                            
                            for i = currentWaypointIndex, #currentWaypoints do
                                local checkWp = currentWaypoints[i]
                                
                                if checkWp.Action == Enum.PathWaypointAction.Jump then
                                    targetIndex = i
                                    break
                                end

                                -- แก้ไขให้เข้มงวดขึ้น: ถ้าความสูงต่างกันแค่ 2 Studs ก็ห้ามข้ามจุดแล้ว (เพื่อบังคับให้ไต่บล็อคลอย)
                                if math.abs(checkWp.Position.Y - currentPos.Y) > 2 then
                                    break
                                end

                                local rayTargetPos = checkWp.Position + Vector3.new(0, 3, 0)
                                local dir = rayTargetPos - currentPos
                                local hit = workspace:Raycast(currentPos, dir, rayParams)
                                
                                if not hit then
                                    targetIndex = i 
                                else
                                    break 
                                end
                            end
                            
                            currentWaypointIndex = targetIndex
                            local wp = currentWaypoints[currentWaypointIndex]
                            
                            if wp then
                                myHuman:MoveTo(wp.Position)
                                
                                local distXZ = (Vector2.new(currentPos.X, currentPos.Z) - Vector2.new(wp.Position.X, wp.Position.Z)).Magnitude
                                local distY = wp.Position.Y - currentPos.Y -- เอาแกน Y เป้าหมาย ลบ ปัจจุบัน

                                -- ** ระบบบังคับกระโดดไต่บล็อคลอย **
                                -- ถ้าจุดหมายอยู่สูงกว่าตัวเรา และเราเดินมาประชิดจุดนั้นในแกนราบแล้ว (ใต้บล็อค) -> ให้กระโดดเลย
                                if distY > 1.2 and distXZ < 4 then
                                    forceJump(myHuman)
                                end

                                if distXZ < 3.5 and math.abs(distY) < 5 then
                                    currentWaypointIndex = currentWaypointIndex + 1
                                end
                                
                                if wp.Action == Enum.PathWaypointAction.Jump or wp.Position.Y > currentPos.Y + 2.5 then
                                    forceJump(myHuman)
                                end
                            end
                        end
                        updateDebug("DirectTrace", currentPos, directRay and directRay.Position or targetPos, Color3.fromRGB(255, 0, 0))
                    end
                else
                    myHuman:MoveTo(currentPos)
                end
            end
        end)
    end
end)
