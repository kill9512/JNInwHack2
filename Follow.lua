local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("KONG GUISUS - STRATEGIST", "DarkTheme")
local Tab = Window:NewTab("Main")
local Section = Tab:NewSection("Tactical Navigation (Plan in Plan)")

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

-- --- Helper Functions ---
local function forceJump(hum)
    if hum.FloorMaterial ~= Enum.Material.Air then
        hum.Jump = true
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end

-- ฟังก์ชันตรวจสอบ "ความกว้างของช่อง" (Gap Width Check)
local function isGapSafe(pos, moveDir)
    -- ยิง Ray ขนานไปด้านซ้ายและขวา เพื่อดูว่าช่องแคบไปไหม
    local leftDir = (CFrame.Angles(0, math.rad(90), 0) * moveDir).Unit
    local rightDir = (CFrame.Angles(0, math.rad(-90), 0) * moveDir).Unit
    
    local leftHit = workspace:Raycast(pos, leftDir * 3, rayParams) -- เช็คข้างซ้าย 3 studs
    local rightHit = workspace:Raycast(pos, rightDir * 3, rayParams) -- เช็คข้างขวา 3 studs
    
    -- ถ้าติดทั้งสองฝั่งในระยะประชิด แสดงว่าเป็น "คอขวด" หรือช่องที่แคบเกินไป
    if leftHit and rightHit then
        return false 
    end
    return true
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

local MoveSection = Tab:NewSection("Tactical Control")
MoveSection:NewToggle("Enable Follow", "Start Logic", function(s) followEnabled = s end)
MoveSection:NewToggle("Show Debug", "Visuals", function(s) debugEnabled = s end)
MoveSection:NewSlider("Gap", "Distance", 20, 1, function(s) followDistance = s end)

-- --- MAIN LOOP ---
task.spawn(function()
    while true do
        task.wait(0.1)
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
                    -- ** แผน 1: เช็คทางตรงก่อน (Aimbot Mode) **
                    local moveDir = (targetPos - currentPos).Unit
                    local directRay = workspace:Raycast(currentPos, moveDir * dist, rayParams)

                    if not directRay and isGapSafe(currentPos, moveDir) then
                        -- ทางตรงโล่งและกว้างพอ วิ่งเข้าใส่เลย
                        currentWaypoints = {}
                        updateDebug("DirectTrace", currentPos, targetPos, Color3.fromRGB(0, 255, 0))
                        myHuman:MoveTo(targetPos)
                    else
                        -- ** แผน 2: ทางตรงติดขัด หรือเป็นช่องแคบ -> ใช้ Pathfinding (ทางสีฟ้า) **
                        if os.clock() - lastComputeTime > 1.0 or (targetPos - lastTargetPos).Magnitude > 8 then
                            local path = PathfindingService:CreatePath({AgentRadius = 3, AgentHeight = 5, AgentCanJump = true})
                            path:ComputeAsync(currentPos, targetPos)
                            if path.Status == Enum.PathStatus.Success then
                                currentWaypoints = path:GetWaypoints()
                                currentWaypointIndex = 2
                                lastTargetPos, lastComputeTime = targetPos, os.clock()
                            end
                        end

                        -- ** แผน 3: เดินตามทางสีฟ้า แต่ "ตรวจสอบซ้ำ" ทุกก้าว (แผนซ้อนแผน) **
                        if #currentWaypoints > 0 and currentWaypointIndex <= #currentWaypoints then
                            local wp = currentWaypoints[currentWaypointIndex]
                            local wpDir = (wp.Position - currentPos).Unit
                            
                            -- ตรวจสอบว่าจุดสีฟ้าจุดต่อไป มันจะพาเราเข้าช่องแคบไหม?
                            if not isGapSafe(currentPos, wpDir) then
                                -- ถ้าจุดต่อไปดูอันตราย ให้ "ข้าม" หรือ "เบี่ยง" ออกทันที
                                updateDebug("TacticalAlert", currentPos, wp.Position, Color3.fromRGB(255, 0, 0))
                                -- สั่งหักเลี้ยวเล็กน้อยเพื่อหาองศาใหม่
                                local detourDir = (CFrame.Angles(0, math.rad(45), 0) * wpDir).Unit
                                myHuman:MoveTo(currentPos + (detourDir * 5))
                                forceJump(myHuman)
                                currentWaypointIndex = currentWaypointIndex + 1 -- ข้ามจุดนี้ไปเลย
                            else
                                -- ทางสีฟ้ายังโอเค เดินต่อไป
                                myHuman:MoveTo(wp.Position)
                                if (Vector2.new(currentPos.X, currentPos.Z) - Vector2.new(wp.Position.X, wp.Position.Z)).Magnitude < 3.5 then
                                    currentWaypointIndex = currentWaypointIndex + 1
                                end
                                if wp.Action == Enum.PathWaypointAction.Jump then forceJump(myHuman) end
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
