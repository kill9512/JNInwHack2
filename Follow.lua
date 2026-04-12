local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("KONG GUISUS", "DarkTheme")
local Tab = Window:NewTab("Main")
local Section = Tab:NewSection("Hybrid Pre-calculated Pathing")

-- --- Services ---
local Players = game.Players
local LocalPlayer = Players.LocalPlayer
local PathfindingService = game:GetService("PathfindingService")

-- --- Variables ---
local SelectedMode = "Manual"
local SelectedPlayerName = nil
local followDistance = 5
local followEnabled = false
local debugEnabled = false

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local currentWaypoints = {}
local currentWaypointIndex = 1
local lastTargetPos = Vector3.new()
local isPathfinding = false -- ตัวแปรเช็คสถานะว่ากำลังเดินตามจุดสีฟ้าอยู่ไหม

local stuckTimer = 0
local lastPosForStuck = Vector3.new()

-- --- ฟังก์ชันวาดเส้น Debug ---
local function updateDebugLine(name, startPos, endPos, color)
    local terrain = workspace.Terrain
    local line = terrain:FindFirstChild(name)
    if not debugEnabled then if line then line:Destroy() end return end
    if not line then
        line = Instance.new("LineHandleAdornment")
        line.Name = name
        line.Thickness = 4
        line.Transparency = 0.3
        line.AlwaysOnTop = true
        line.Adornee = terrain
        line.Parent = terrain
    end
    line.Color3 = color
    line.Length = (startPos - endPos).Magnitude
    line.CFrame = CFrame.lookAt(startPos, endPos)
end

-- --- ฟังก์ชันวาดจุด Waypoints ---
local function drawWaypoints(waypoints)
    for _, v in pairs(workspace.Terrain:GetChildren()) do
        if v.Name == "WP_Debug" then v:Destroy() end
    end
    if not debugEnabled or not waypoints then return end
    for i, wp in ipairs(waypoints) do
        local p = Instance.new("Part")
        p.Name = "WP_Debug"
        p.Size = Vector3.new(1, 1, 1)
        p.Position = wp.Position
        p.Anchored = true
        p.CanCollide = false
        p.CanQuery = false
        p.Material = Enum.Material.Neon
        p.Color = Color3.fromRGB(0, 150, 255)
        p.Parent = workspace.Terrain
    end
end

local function forceJump(hum)
    if hum.FloorMaterial ~= Enum.Material.Air then
        hum.Jump = true
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end

-- --- UI Setup ---
Section:NewDropdown("Target Mode", "Mode", {"Manual", "Max HP", "Min HP"}, function(m) SelectedMode = m end)
local drop = Section:NewDropdown("Select Target", "User", {}, function(s) 
    SelectedPlayerName = s:match("@([^%)]+)") 
end)

local function refresh()
    local t = {"None (Off)"}
    for _, p in pairs(Players:GetPlayers()) do 
        if p ~= LocalPlayer then table.insert(t, p.DisplayName.." (@"..p.Name..")") end 
    end
    drop:Refresh(t)
end
Section:NewButton("Refresh List", "Update", refresh)
refresh()

local MoveSection = Tab:NewSection("Control & Debug")
MoveSection:NewToggle("Enable Follow", "Start Logic", function(s) followEnabled = s end)
MoveSection:NewToggle("Show Path", "Draw Lines & Waypoints", function(s) 
    debugEnabled = s 
    if not s then drawWaypoints(nil); updateDebugLine("DirectTrace", Vector3.new(), Vector3.new()) end
end)
MoveSection:NewSlider("Gap", "Distance", 20, 1, function(s) followDistance = s end)

-- --- LOGIC CORE ---
task.spawn(function()
    while task.wait(0.1) do
        if not followEnabled then continue end
        
        local target = nil
        -- [ค้นหาเป้าหมายเหมือนเดิม]
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

        if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
            local myChar = LocalPlayer.Character
            local myHuman = myChar and myChar:FindFirstChild("Humanoid")
            local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
            local tRoot = target.Character.HumanoidRootPart
            
            if myHuman and myRoot then
                rayParams.FilterDescendantsInstances = {myChar, target.Character}
                local currentPos = myRoot.Position
                local targetPos = tRoot.Position
                local distToTarget = (targetPos - currentPos).Magnitude
                local moveDir = (targetPos - currentPos).Unit

                -- ระบบ Stuck
                if (currentPos - lastPosForStuck).Magnitude < 0.2 and myHuman.MoveDirection.Magnitude > 0 then
                    stuckTimer = stuckTimer + 0.1
                else
                    stuckTimer = 0
                end
                lastPosForStuck = currentPos

                if distToTarget > followDistance then
                    -- ** หัวใจสำคัญ: เช็คก่อนว่ามองเห็นตัวตรงๆ หรือยัง **
                    local directRay = workspace:Raycast(currentPos, moveDir * distToTarget, rayParams)

                    if not directRay then
                        -- ** ถ้ามองเห็นตรงๆ = วิ่งใส่เลย **
                        isPathfinding = false
                        currentWaypoints = {}
                        drawWaypoints(nil)
                        updateDebugLine("DirectTrace", currentPos, targetPos, Color3.fromRGB(0, 255, 0))
                        myHuman:MoveTo(targetPos)
                    else
                        -- ** ถ้ามองไม่เห็น (ติดกำแพง) **
                        updateDebugLine("DirectTrace", currentPos, directRay.Position, Color3.fromRGB(255, 0, 0))
                        
                        -- คำนวณทางใหม่ก็ต่อเมื่อไม่มีทางเก่า หรือผู้เล่นขยับหนีไปไกล
                        if #currentWaypoints == 0 or (targetPos - lastTargetPos).Magnitude > 8 then
                            local path = PathfindingService:CreatePath({AgentRadius = 3, AgentHeight = 5, AgentCanJump = true})
                            local success, _ = pcall(function() path:ComputeAsync(currentPos, targetPos) end)
                            
                            if success and path.Status == Enum.PathStatus.Success then
                                currentWaypoints = path:GetWaypoints()
                                currentWaypointIndex = 2
                                lastTargetPos = targetPos
                                drawWaypoints(currentWaypoints)
                                isPathfinding = true
                            end
                        end

                        -- เดินตาม Waypoints แบบไม่รีเซ็ตกลางคัน
                        if isPathfinding and currentWaypoints and currentWaypointIndex <= #currentWaypoints then
                            local wp = currentWaypoints[currentWaypointIndex]
                            local posXZ = Vector3.new(currentPos.X, 0, currentPos.Z)
                            local wpXZ = Vector3.new(wp.Position.X, 0, wp.Position.Z)
                            
                            -- ระยะเช็คจุด (ถ้าติดนานให้ข้าม)
                            if (posXZ - wpXZ).Magnitude < 3.5 or stuckTimer > 1.2 then
                                currentWaypointIndex = currentWaypointIndex + 1
                                if stuckTimer > 1.2 then forceJump(myHuman); stuckTimer = 0 end
                            end
                            
                            if wp then
                                myHuman:MoveTo(wp.Position)
                                if wp.Action == Enum.PathWaypointAction.Jump then forceJump(myHuman) end
                            end
                        end
                    end
                else
                    myHuman:MoveTo(currentPos)
                    updateDebugLine("DirectTrace", currentPos, currentPos, Color3.fromRGB(0,0,0))
                end
            end
        else
            currentWaypoints = {}; drawWaypoints(nil)
        end
    end
end)
