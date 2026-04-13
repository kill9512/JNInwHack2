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

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- --- Debug Visualization ---
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
        p.Material, p.Transparency = Enum.Material.Neon, 0.3
        
        -- ถ้าเป็นจุดที่ต้องกระโดด ให้เป็นสีแดง
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
    if not s then currentWaypoints = {}; clearVisuals() end
end)
MoveSection:NewToggle("Show Path", "Visuals", function(s) 
    debugEnabled = s
    if not s then clearVisuals() end
end)
MoveSection:NewSlider("Distance", "Gap", 20, 1, function(s) followDistance = s end)

-- --- MAIN LOOP ---
task.spawn(function()
    while true do
        task.wait(0.1) -- ลด delay ลงเพื่อให้เดินสมูทขึ้น
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
                    -- เช็คทางตรง (ลบเรื่องแกน Y ออก เพื่อให้มันเช็คทางโล่งได้แม่นขึ้น)
                    local moveDir = (targetPos - currentPos).Unit
                    local directRay = workspace:Raycast(currentPos, moveDir * dist, rayParams)

                    -- คำนวณหา Path ใหม่ เมื่อเป้าหมายขยับเกิน 8 Studs หรือไม่ได้คำนวณมานานกว่า 1 วินาที
                    if os.clock() - lastComputeTime > 1.0 or (targetPos - lastTargetPos).Magnitude > 8 then
                        -- ** ปรับแต่ง AI สำหรับบันไดและบล็อคลอย **
                        local path = PathfindingService:CreatePath({
                            AgentRadius = 1.5,     -- ทำตัวให้ผอมลง จะได้เดินบนบล็อคแคบๆ ได้
                            AgentHeight = 5, 
                            AgentCanJump = true,
                            AgentMaxJumpHeight = 15, -- ยอมให้กระโดดได้สูงขึ้นเพื่อข้ามบล็อคลอย
                            AgentMaxSlope = 50,    -- เดินทางลาดชันได้ดีขึ้น
                            WaypointSpacing = 3    -- วางจุดถี่ขึ้น ทำให้ไม่หล่นเวลาเดินบนบล็อค
                        })
                        
                        path:ComputeAsync(currentPos, targetPos)
                        
                        if path.Status == Enum.PathStatus.Success then
                            currentWaypoints = path:GetWaypoints()
                            currentWaypointIndex = math.min(2, #currentWaypoints)
                            lastTargetPos = targetPos
                            lastComputeTime = os.clock()
                            drawPath(currentWaypoints)
                        else
                            -- ถ้าหาทางไม่ได้จริงๆ (อยู่ใต้เพดานตันๆ) ให้เคลียร์ทางทิ้ง
                            currentWaypoints = {}
                        end
                    end

                    -- ** ระบบเดินตาม Waypoint (แบบคลาสสิกและเสถียรสุด) **
                    if #currentWaypoints > 0 and currentWaypointIndex <= #currentWaypoints then
                        local wp = currentWaypoints[currentWaypointIndex]
                        myHuman:MoveTo(wp.Position)
                        
                        -- เช็คระยะห่างระหว่างบอทกับจุด Waypoint
                        local distXZ = (Vector2.new(currentPos.X, currentPos.Z) - Vector2.new(wp.Position.X, wp.Position.Z)).Magnitude
                        local distY = wp.Position.Y - currentPos.Y

                        -- 1. ถ้าจุดหมายอยู่สูงกว่าตัวเรา หรือเป็นจุดที่ต้องกระโดด ให้กระโดดทันที
                        if wp.Action == Enum.PathWaypointAction.Jump or distY > 1.5 then
                            forceJump(myHuman)
                        end

                        -- 2. ถ้าเดินมาถึงจุดแล้ว (ให้ระยะคลาดเคลื่อนได้ 3 Studs) ให้ขยับไปจุดถัดไป
                        if distXZ < 3 then
                            currentWaypointIndex = currentWaypointIndex + 1
                        end
                    else
                        -- ถ้าไม่มี Waypoint (ทางตัน หรือเดินถึงจุดสุดท้ายแล้วแต่ยังไม่ถึงเป้า) 
                        -- ลองเดินตรงเข้าไปหาเป้าหมายเลย ถ้าติดกำแพงให้กระโดดรัวๆ (แก้บัคติดใต้ผู้เล่น)
                        myHuman:MoveTo(targetPos)
                        if directRay then forceJump(myHuman) end
                    end
                else
                    -- ถึงเป้าหมายแล้ว หยุดเดิน
                    myHuman:MoveTo(currentPos)
                end
            end
        end)
    end
end)
