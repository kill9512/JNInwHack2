local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("KONG GUISUS", "DarkTheme")
local Tab = Window:NewTab("Main")
local Section = Tab:NewSection("Smart Follow Player")

-- --- Services ---
local PathfindingService = game:GetService("PathfindingService")
local Players = game.Players
local LocalPlayer = Players.LocalPlayer

-- --- Variables ---
local SelectedMode = "Manual"
local SelectedPlayerName = nil
local UsePercentage = false
local followDistance = 5
local followEnabled = false

-- --- Raycast Settings ---
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

-- --- ฟังก์ชันเสริม ---

local function UpdatePlayerTable()
    local tbl = {"None (Off)"}
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            table.insert(tbl, plr.DisplayName .. " (@" .. plr.Name .. ")")
        end
    end
    return tbl
end

-- เช็คว่ามองเห็นเป้าหมายหรือไม่
local function canSeeTarget(myRoot, targetRoot)
    rayParams.FilterDescendantsInstances = {LocalPlayer.Character, targetRoot.Parent}
    local direction = (targetRoot.Position - myRoot.Position)
    local result = workspace:Raycast(myRoot.Position, direction, rayParams)
    return result == nil
end

-- --- UI Elements ---
Section:NewDropdown("Target Mode", "Choose how to find target", {"Manual", "Max HP", "Min HP"}, function(mode)
    SelectedMode = mode
end)

local drop = Section:NewDropdown("Select Player", "Manual selection", UpdatePlayerTable(), function(selection)
    if selection == "None (Off)" then SelectedPlayerName = nil
    else SelectedPlayerName = selection:match("@([^%)]+)") end
end)

Section:NewButton("Refresh Players", "Update manual list", function()
    drop:Refresh(UpdatePlayerTable())
end)

Section:NewToggle("Use % Health Logic", "Check health by percentage", function(state)
    UsePercentage = state
end)

local MoveSection = Tab:NewSection("Movement Control")
MoveSection:NewToggle("Enable Follow", "Start moving to target", function(state)
    followEnabled = state
end)

MoveSection:NewSlider("Follow Distance", "Distance from target", 20, 1, function(s)
    followDistance = s
end)

-- --- LOGIC CORE ---
task.spawn(function()
    while task.wait(0.1) do
        if not followEnabled then continue end
        
        local finalTarget = nil
        -- [ค้นหาเป้าหมาย]
        if SelectedMode == "Manual" then
            if SelectedPlayerName then finalTarget = Players:FindFirstChild(SelectedPlayerName) end
        elseif SelectedMode == "Max HP" or SelectedMode == "Min HP" then
            local bestHP = (SelectedMode == "Max HP") and -1 or math.huge
            for _, p in pairs(Players:GetPlayers()) do
                if p ~= LocalPlayer then
                    local hp = p.Character and p.Character:FindFirstChild("Humanoid") and p.Character.Humanoid.Health
                    if hp and ((SelectedMode == "Max HP" and hp > bestHP) or (SelectedMode == "Min HP" and hp < bestHP)) then
                        bestHP = hp; finalTarget = p
                    end
                end
            end
        end

        if finalTarget and finalTarget.Character and finalTarget.Character:FindFirstChild("HumanoidRootPart") then
            local myChar = LocalPlayer.Character
            local myHuman = myChar and myChar:FindFirstChild("Humanoid")
            local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
            local tRoot = finalTarget.Character.HumanoidRootPart
            
            if myHuman and myRoot then
                local dist = (myRoot.Position - tRoot.Position).Magnitude
                local heightDiff = tRoot.Position.Y - myRoot.Position.Y -- เช็คว่าเขาอยู่สูงกว่าเราไหม
                
                if dist > followDistance then
                    -- 1. เช็คว่าควรใช้ Pathfinding หรือไม่ (สูงต่างกัน หรือ มองไม่เห็น)
                    if math.abs(heightDiff) > 4 or not canSeeTarget(myRoot, tRoot) then
                        local path = PathfindingService:CreatePath({
                            AgentCanJump = true, 
                            AgentRadius = 2.5,
                            AgentHeight = 5
                        })
                        path:ComputeAsync(myRoot.Position, tRoot.Position)
                        
                        if path.Status == Enum.PathStatus.Success then
                            local waypoints = path:GetWaypoints()
                            local nextWaypoint = waypoints[2]
                            
                            if nextWaypoint then
                                -- **บังคับกระโดดถ้า Waypoint บอก หรือถ้าเป้าหมายอยู่สูงกว่า**
                                if nextWaypoint.Action == Enum.PathWaypointAction.Jump or heightDiff > 2 then
                                    myHuman.Jump = true
                                end
                                myHuman:MoveTo(nextWaypoint.Position)
                            end
                        end
                    else
                        -- 2. เดินตรงปกติ แต่เพิ่มระบบกันติด (Stuck Detection)
                        local moveDir = (tRoot.Position - myRoot.Position).Unit
                        myHuman:MoveTo(tRoot.Position - (moveDir * followDistance))
                        
                        -- ยิง Ray เช็คของขวางระดับเข่า
                        rayParams.FilterDescendantsInstances = {myChar, finalTarget.Character}
                        local hitCheck = workspace:Raycast(myRoot.Position + Vector3.new(0, -1, 0), moveDir * 3, rayParams)
                        
                        if hitCheck and hitCheck.Instance.CanCollide then
                            myHuman.Jump = true -- เจอของขวางให้โดดทันที
                        end
                    end
                    
                    -- 3. ตรวจสอบความเร็ว (ถ้าเดินอยู่แต่ตัวไม่ขยับ = ติดแน่นอน)
                    if myRoot.Velocity.Magnitude < 1 and myHuman.MoveDirection.Magnitude > 0 then
                        myHuman.Jump = true
                    end
                else
                    -- ถึงระยะแล้ว
                    myHuman:MoveTo(myRoot.Position)
                    myRoot.CFrame = CFrame.lookAt(myRoot.Position, Vector3.new(tRoot.Position.X, myRoot.Position.Y, tRoot.Position.Z))
                end
            end
        end
    end
end)
