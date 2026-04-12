local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("KONG GUISUS - COMMITMENT", "DarkTheme")
local Tab = Window:NewTab("Main")
local Section = Tab:NewSection("Deep Pathing & Decision Lock")

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
local commitmentPoint = nil -- จุดที่บอทสัญญาว่าจะเดินไปให้ถึง
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
    line.Name, line.Thickness, line.Transparency = name, 4, 0.3
    line.Adornee, line.AlwaysOnTop, line.Parent = workspace.Terrain, true, workspace.Terrain
    line.Color3, line.Length = color, (startPos - endPos).Magnitude
    line.CFrame = CFrame.lookAt(startPos, endPos)
end

local function forceJump(hum)
    if hum.FloorMaterial ~= Enum.Material.Air then
        hum.Jump = true
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end

-- ฟังก์ชันหาทางอ้อมแบบ "มองให้ไกลที่สุด"
local function getDeepDetour(myRoot, targetPos)
    local currentPos = myRoot.Position
    local moveDir = (targetPos - currentPos).Unit
    local scanAngles = {45, -45, 90, -90, 135, -135}
    
    local bestPoint = nil
    local maxClearance = 0
    
    for _, angle in ipairs(scanAngles) do
        local dir = (CFrame.Angles(0, math.rad(angle), 0) * Vector3.new(moveDir.X, 0, moveDir.Z)).Unit
        -- ยิงเรดาร์ให้ไกลขึ้น (30 studs) เพื่อให้เห็น "จุดสิ้นสุดของกำแพง"
        local ray = workspace:Raycast(currentPos, dir * 30, rayParams)
        local d = ray and ray.Distance or 30
        
        if d > maxClearance then
            maxClearance = d
            bestPoint = currentPos + (dir * (d - 2)) -- ตั้งจุดหมายไว้ก่อนชนกำแพง 2 studs
        end
    end
    return bestPoint
end

-- --- UI ---
Section:NewDropdown("Target Mode", "Mode", {"Manual", "Max HP", "Min HP"}, function(m) SelectedMode = m end)
local drop = Section:NewDropdown("Select Player", "Target", {}, function(s) SelectedPlayerName = s:match("@([^%)]+)") end)

local function refreshList()
    local t = {"None (Off)"}
    for _, p in pairs(Players:GetPlayers()) do 
        if p ~= LocalPlayer then table.insert(t, p.DisplayName.." (@"..p.Name..")") end 
    end
    drop:Refresh(t)
end
Section:NewButton("Refresh List", "Update", refreshList)
refreshList()

local MoveSection = Tab:NewSection("Decision Control")
MoveSection:NewToggle("Enable Follow", "Start Logic", function(s) 
    followEnabled = s 
    if not s then commitmentPoint = nil; currentWaypoints = {} end
end)
MoveSection:NewToggle("Show Decision Path", "Visuals", function(s) debugEnabled = s end)
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
                -- [ค้นหาเป้าหมายตาม HP...]
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

                -- ** ระบบ Commitment: ถ้ามีจุดหมายที่สัญญาไว้ ให้เดินไปให้ถึงก่อน **
                if commitmentPoint then
                    local distToCommit = (Vector2.new(currentPos.X, currentPos.Z) - Vector2.new(commitmentPoint.X, commitmentPoint.Z)).Magnitude
                    updateDebug("CommitTrace", currentPos, commitmentPoint, Color3.fromRGB(255, 170, 0)) -- เส้นสีส้ม = จุดยึดมั่น
                    
                    myHuman:MoveTo(commitmentPoint)
                    
                    -- ถ้าถึงจุดที่สัญญาไว้ หรือเดินติดนานเกินไป ให้ปลดล็อก
                    if distToCommit < 4 then
                        commitmentPoint = nil
                    end
                    -- เช็คกระโดดขณะเดินไปจุดยึดมั่น
                    local frontRay = workspace:Raycast(currentPos, (commitmentPoint - currentPos).Unit * 5, rayParams)
                    if frontRay then forceJump(myHuman) end
                    
                    return -- ข้ามการคำนวณอื่นจนกว่าจะถึงจุดหมายที่เลือกไว้
                end

                if dist > followDistance then
                    local moveDir = (targetPos - currentPos).Unit
                    local directRay = workspace:Raycast(currentPos, moveDir * dist, rayParams)

                    if not directRay then
                        -- ทางโล่ง วิ่งใส่เลย
                        updateDebug("DirectTrace", currentPos, targetPos, Color3.fromRGB(0, 255, 0))
                        myHuman:MoveTo(targetPos)
                    else
                        -- ** ทางตัน: วิเคราะห์หาทางออกให้สุดทาง **
                        updateDebug("DirectTrace", currentPos, directRay.Position, Color3.fromRGB(255, 0, 0))
                        
                        -- ลองแสกนหาจุดที่ "ไปได้ไกลที่สุด" และล็อกเป้าหมายนั้น
                        local bestEscape = getDeepDetour(myRoot, targetPos)
                        if bestEscape then
                            commitmentPoint = bestEscape
                        else
                            -- ถ้าเรดาร์มองไม่เห็นทางออก ให้ใช้ Pathfinding
                            local path = PathfindingService:CreatePath({AgentRadius = 3, AgentHeight = 5, AgentCanJump = true})
                            path:ComputeAsync(currentPos, targetPos)
                            if path.Status == Enum.PathStatus.Success then
                                currentWaypoints = path:GetWaypoints()
                                -- ล็อกเป้าหมายไปที่ Waypoint ที่ 5 (เดินไปให้ไกลหน่อยก่อนค่อยคำนวณใหม่)
                                local targetIndex = math.min(5, #currentWaypoints)
                                commitmentPoint = currentWaypoints[targetIndex].Position
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
