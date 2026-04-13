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

-- --- Debug Visualization (ใช้แบบใหม่ ลดอาการแลค) ---
local debugFolder = workspace:FindFirstChild("ExplorerDebugVisuals") or Instance.new("Folder")
debugFolder.Name = "ExplorerDebugVisuals"
debugFolder.Parent = workspace

local function clearVisuals()
    debugFolder:ClearAllChildren()
end

local function drawPath(waypoints)
    if not debugEnabled then return end
    clearVisuals()
    for i, wp in ipairs(waypoints) do
        local p = Instance.new("Part")
        p.Size = Vector3.new(0.8, 0.8, 0.8)
        p.Position = wp.Position
        p.Anchored, p.CanCollide, p.CanQuery = true, false, false
        p.Material, p.Transparency = Enum.Material.Neon, 0.4
        
        if wp.Action == Enum.PathWaypointAction.Jump then
            p.Color = Color3.fromRGB(255, 0, 0)
        else
            p.Color = Color3.fromRGB(0, 255, 255)
        end
        p.Parent = debugFolder
    end
end

-- --- Helper Functions ---
local function forceJump(hum)
    if hum.FloorMaterial ~= Enum.Material.Air then
        hum.Jump = true
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end

-- โหมดแหย่ทาง (แก้บัคคณิตศาสตร์ตอนเป้าหมายอยู่บนหัวเป๊ะๆ)
local function getProbingDirection(myRoot, targetPos)
    local currentPos = myRoot.Position
    local baseDirXZ = Vector3.new(targetPos.X - currentPos.X, 0, targetPos.Z - currentPos.Z)
    
    if baseDirXZ.Magnitude < 0.1 then
        baseDirXZ = myRoot.CFrame.LookVector -- ถ้าอยู่ตรงหัวเป๊ะๆ ให้กวาดจากด้านหน้าตัวละคร
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
MoveSection:NewToggle("Show Path", "Visuals", function(s) 
    debugEnabled = s
    if not s then clearVisuals() end
end)
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
                    if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("Humanoid") and p.Character.Humanoid.Health > 0 then
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
            
            if myHuman and myRoot and myHuman.Health > 0 then
                local currentPos = myRoot.Position
                local targetPos = tRoot.Position
                local dist = (targetPos - currentPos).Magnitude
                rayParams.FilterDescendantsInstances = {myChar, target.Character}

                if dist > followDistance then
                    -- เช็คความสูง (Y) ป้องกันการพยายามวิ่งทะลุเพดาน
                    local yDiff = math.abs(targetPos.Y - currentPos.Y)
                    local moveDir = (targetPos - currentPos).Unit
                    local directRay = workspace:Raycast(currentPos, moveDir * dist, rayParams)

                    -- 1. เดินตรงได้ก็ต่อเมื่อ ทางโล่ง และ **อยู่ชั้นเดียวกัน (ความสูงต่างกันไม่เกิน 5)**
                    if not directRay and yDiff < 5 then
                        isProbing = false
                        currentWaypoints = {}
                        myHuman:MoveTo(targetPos)
                    else
                        -- 2. ต้องใช้ Pathfinding (อยู่ในตึก หรือ อยู่คนละชั้น)
                        if os.clock() - lastComputeTime > 1.0 or (targetPos - lastTargetPos).Magnitude > 8 then
                            local path = PathfindingService:CreatePath({
                                AgentRadius = 1.5, -- ผอมลงเพื่อแทรกบันได
                                AgentHeight = 5, 
                                AgentCanJump = true,
                                AgentMaxJumpHeight = 15, -- ปีนบล็อคลอยได้
                                WaypointSpacing = 3
                            })
                            path:ComputeAsync(currentPos, targetPos)
                            
                            if path.Status == Enum.PathStatus.Success then
                                isProbing = false
                                currentWaypoints = path:GetWaypoints()
                                currentWaypointIndex = math.min(2, #currentWaypoints)
                                lastTargetPos = targetPos
                                lastComputeTime = os.clock()
                                drawPath(currentWaypoints)
                            else
                                isProbing = true
                                currentWaypoints = {}
                            end
                        end

                        if isProbing then
                            -- โหมดเดินแหย่
                            local probeDir = getProbingDirection(myRoot, targetPos)
                            if probeDir then
                                myHuman:MoveTo(currentPos + (probeDir * 8))
                                local wallCheck = workspace:Raycast(currentPos, probeDir * 4, rayParams)
                                if wallCheck then forceJump(myHuman) end
                            end
                        elseif #currentWaypoints > 0 and currentWaypointIndex <= #currentWaypoints then
                            
                            -- ** ระบบ Hybrid **
                            local ceilingHit = workspace:Raycast(currentPos, Vector3.new(0, 15, 0), rayParams)
                            local isOutdoors = (ceilingHit == nil)

                            if isOutdoors then
                                -- กลางแจ้ง: ลัด Waypoint ได้ไม่เกิน 4 จุดเพื่อความเร็ว
                                local maxLookAhead = math.min(currentWaypointIndex + 4, #currentWaypoints)
                                local targetIndex = currentWaypointIndex
                                
                                for i = maxLookAhead, currentWaypointIndex + 1, -1 do
                                    local checkWp = currentWaypoints[i]
                                    if checkWp.Action == Enum.PathWaypointAction.Jump or math.abs(checkWp.Position.Y - currentPos.Y) > 2 then
                                        continue
                                    end
                                    local startRay = currentPos + Vector3.new(0, 3, 0)
                                    local endRay = checkWp.Position + Vector3.new(0, 3, 0)
                                    if not workspace:Raycast(startRay, endRay - startRay, rayParams) then
                                        targetIndex = i
                                        break
                                    end
                                end
                                currentWaypointIndex = targetIndex
                            end

                            -- การตัดสินใจเดิน
                            local wp = currentWaypoints[currentWaypointIndex]
                            myHuman:MoveTo(wp.Position)
                            
                            local distXZ = (Vector2.new(currentPos.X, currentPos.Z) - Vector2.new(wp.Position.X, wp.Position.Z)).Magnitude
                            local distY = math.abs(currentPos.Y - wp.Position.Y)

                            -- บังคับกระโดด
                            if wp.Action == Enum.PathWaypointAction.Jump or wp.Position.Y > currentPos.Y + 1.5 then
                                forceJump(myHuman)
                            end

                            -- การเปลี่ยนจุด (แก้ไขแล้ว: ต้องเช็คทั้งแกน XZ และแกน Y จะได้ไม่ติดใต้เท้าผู้เล่น)
                            local passDist = isOutdoors and 4 or 2.5
                            if distXZ < passDist and distY < 4 then
                                currentWaypointIndex = currentWaypointIndex + 1
                            end
                        else
                            -- ถ้า Path หมดแล้วแต่ยังไม่ถึงเป้า
                            myHuman:MoveTo(targetPos)
                            if directRay then forceJump(myHuman) end
                        end
                    end
                else
                    myHuman:MoveTo(currentPos)
                end
            end
        end)
    end
end)
