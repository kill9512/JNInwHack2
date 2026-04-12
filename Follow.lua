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

local function getHealth(plr)
    local char = plr.Character
    if char and char:FindFirstChild("Humanoid") then
        local hum = char.Humanoid
        return UsePercentage and (hum.Health / hum.MaxHealth) or hum.Health
    end
    return nil
end

-- เช็คว่ามองเห็นเป้าหมายตรงๆ หรือไม่ (Line of Sight)
local function canSeeTarget(myRoot, targetRoot)
    rayParams.FilterDescendantsInstances = {LocalPlayer.Character, targetRoot.Parent}
    local direction = (targetRoot.Position - myRoot.Position)
    local result = workspace:Raycast(myRoot.Position, direction, rayParams)
    return result == nil -- ถ้าไม่ติดอะไรเลยแปลว่าเห็น
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
        -- [ส่วนหาเป้าหมายเหมือนเดิม]
        if SelectedMode == "Manual" then
            if SelectedPlayerName then finalTarget = Players:FindFirstChild(SelectedPlayerName) end
        elseif SelectedMode == "Max HP" or SelectedMode == "Min HP" then
            local bestHP = (SelectedMode == "Max HP") and -1 or math.huge
            for _, p in pairs(Players:GetPlayers()) do
                if p ~= LocalPlayer then
                    local hp = getHealth(p)
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
                local heightDiff = math.abs(myRoot.Position.Y - tRoot.Position.Y)
                
                if dist > followDistance then
                    -- **จุดแก้ปัญหาสำคัญ**: ถ้าสูงต่างกัน หรือ มองไม่เห็นตัว ให้ใช้ Pathfinding
                    if heightDiff > 5 or not canSeeTarget(myRoot, tRoot) then
                        local path = PathfindingService:CreatePath({AgentCanJump = true, AgentRadius = 3})
                        path:ComputeAsync(myRoot.Position, tRoot.Position)
                        
                        if path.Status == Enum.PathStatus.Success then
                            local waypoints = path:GetWaypoints()
                            -- เดินไปที่ Waypoint ที่ 2 (จุดถัดไปจากที่ยืนอยู่)
                            if waypoints[2] then
                                if waypoints[2].Action == Enum.PathWaypointAction.Jump then myHuman.Jump = true end
                                myHuman:MoveTo(waypoints[2].Position)
                            end
                        end
                    else
                        -- ถ้าอยู่ชั้นเดียวกันและเห็นตัว ก็เดินตรงๆ (สมูทกว่า)
                        local moveDir = (tRoot.Position - myRoot.Position).Unit
                        myHuman:MoveTo(tRoot.Position - (moveDir * followDistance))
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
