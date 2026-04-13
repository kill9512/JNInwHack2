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

local lastPosition = Vector3.new()
local lastMoveTick = os.clock()
local randomTarget = nil 

-- --- Helper Functions ---
local function forceJump(hum)
    if hum.FloorMaterial ~= Enum.Material.Air then
        hum.Jump = true
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end

-- [ใหม่] ฟังก์ชันหาบันไดที่ใกล้ที่สุดเมื่อระบบหาทางล้มเหลว
local function findNearestLadder(myPos)
    local nearest = nil
    local minDist = 50 -- ระยะตรวจจับบันได 50 studs
    
    for _, v in pairs(workspace:GetDescendants()) do
        if (v:IsA("TrussPart") or v.Name:lower():find("ladder")) and v:IsA("BasePart") then
            local d = (v.Position - myPos).Magnitude
            if d < minDist then
                minDist = d
                nearest = v
            end
        end
    end
    return nearest
end

local function getProbingDirection(myRoot, targetPos)
    local currentPos = myRoot.Position
    local baseDir = (targetPos - currentPos).Unit
    local scanAngles = {0, 30, -30, 60, -60, 90, -90, 135, -135} 
    
    local bestDir = nil
    local maxDist = 0
    
    for _, angle in ipairs(scanAngles) do
        local dir = (CFrame.Angles(0, math.rad(angle), 0) * Vector3.new(baseDir.X, 0, baseDir.Z)).Unit
        local ray = workspace:Raycast(currentPos, dir * 15, rayParams)
        local d = ray and ray.Distance or 15
        
        if d > maxDist then
            maxDist = d
            bestDir = dir
        end
    end
    return bestDir
end

-- --- UI (เหมือนเดิม) ---
Section:NewDropdown("Target Mode", "Mode", {"Manual", "Max HP", "Min HP", "Random"}, function(m) SelectedMode = m; if m == "Random" then randomTarget = nil end end)
Section:NewTextBox("Search Player", "พิมพ์ชื่อ หรือ Display Name", function(txt)
    local lowerTxt = txt:lower()
    for _, p in pairs(Players:GetPlayers()) do 
        if p ~= LocalPlayer and (p.Name:lower():find(lowerTxt) or p.DisplayName:lower():find(lowerTxt)) then
            SelectedPlayerName = p.Name; SelectedMode = "Manual"; break
        end
    end
end)
local drop = Section:NewDropdown("Select Target", "User", {}, function(s) SelectedPlayerName = s:match("@([^%)]+)") end)
local function refreshList()
    local t = {"None (Off)"}
    for _, p in pairs(Players:GetPlayers()) do if p ~= LocalPlayer then table.insert(t, p.DisplayName.." (@"..p.Name..")") end end
    drop:Refresh(t)
end
Section:NewButton("Refresh List", "Update", refreshList)
refreshList()

local MoveSection = Tab:NewSection("Navigation Control")
MoveSection:NewToggle("Enable Follow", "Start Logic", function(s) followEnabled = s; if not s then currentWaypoints = {}; isProbing = false end end)
MoveSection:NewToggle("Show Path", "Visuals", function(s) debugEnabled = s end)
MoveSection:NewSlider("Distance", "Gap", 20, 1, function(s) followDistance = s end)

-- --- Debug Visualization (เหมือนเดิม) ---
local function updateDebug(name, startPos, endPos, color)
    if not debugEnabled then if workspace.Terrain:FindFirstChild(name) then workspace.Terrain[name]:Destroy() end return end
    local line = workspace.Terrain:FindFirstChild(name) or Instance.new("LineHandleAdornment")
    line.Name, line.Thickness, line.Transparency = name, 3, 0.4
    line.Adornee, line.AlwaysOnTop, line.Color3, line.Length = workspace.Terrain, true, color, (startPos - endPos).Magnitude
    line.CFrame, line.Parent = CFrame.lookAt(startPos, endPos), workspace.Terrain
end

local function clearVisuals()
    for _, v in pairs(workspace.Terrain:GetChildren()) do
        if v.Name == "WP_Debug" or v.Name == "DirectTrace" or v.Name == "ProbeTrace" then v:Destroy() end
    end
end

-- --- MAIN LOOP ---
task.spawn(function()
    while true do
        task.wait(0.05)
        if not followEnabled then continue end
        
        pcall(function()
            local target = nil
            -- [Logic เลือกเป้าหมายเหมือนเดิม]
            if SelectedMode == "Manual" then target = Players:FindFirstChild(SelectedPlayerName or "")
            elseif SelectedMode == "Random" then
                if not randomTarget or not randomTarget.Parent or not randomTarget.Character or not randomTarget.Character:FindFirstChild("Humanoid") or randomTarget.Character.Humanoid.Health <= 0 then
                    local vP = {}; for _, p in pairs(Players:GetPlayers()) do if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("Humanoid") then table.insert(vP, p) end end
                    if #vP > 0 then randomTarget = vP[math.random(1, #vP)] end
                end
                target = randomTarget
            else
                local bHP = (SelectedMode == "Max HP") and -1 or math.huge
                for _, p in pairs(Players:GetPlayers()) do if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("Humanoid") then
                    local hp = p.Character.Humanoid.Health
                    if (SelectedMode == "Max HP" and hp > bHP) or (SelectedMode == "Min HP" and hp < bHP) then bHP = hp; target = p end
                end end
            end

            if not target or not target.Character or not target.Character:FindFirstChild("HumanoidRootPart") then return end

            local myChar = LocalPlayer.Character
            local myHuman = myChar:FindFirstChildOfClass("Humanoid")
            local myRoot = myChar:FindFirstChild("HumanoidRootPart")
            local tRoot = target.Character.HumanoidRootPart
            
            if myHuman and myRoot then
                local currentPos = myRoot.Position
                local targetPos = tRoot.Position
                local trueDist = (targetPos - currentPos).Magnitude
                local hDist = (Vector3.new(targetPos.X, 0, targetPos.Z) - Vector3.new(currentPos.X, 0, currentPos.Z)).Magnitude
                local vDist = math.abs(targetPos.Y - currentPos.Y)
                
                rayParams.FilterDescendantsInstances = {myChar, target.Character}

                -- Stuck Detection
                if (currentPos - lastPosition).Magnitude < 0.5 then
                    if os.clock() - lastMoveTick > 0.7 then currentWaypoints = {}; lastMoveTick = os.clock() end
                else lastPosition = currentPos; lastMoveTick = os.clock() end

                if hDist > followDistance or vDist > 5 then
                    local moveDir = (targetPos - currentPos).Unit
                    local directRay = workspace:Raycast(currentPos, moveDir * trueDist, rayParams)
                    
                    -- ระบบ Parkour Check
                    local headPos = currentPos + Vector3.new(0, 2.5, 0)
                    local headRay = workspace:Raycast(headPos, (targetPos + Vector3.new(0, 2.5, 0) - headPos).Unit * trueDist, rayParams)
                    local isParkour = (hDist < 14 and vDist < 8 and ((directRay and not headRay) or (not directRay and vDist >= 5)))

                    if (not directRay and vDist < 5) or isParkour then
                        isProbing = false; currentWaypoints = {}
                        myHuman:MoveTo(targetPos)
                        if isParkour then if directRay and (directRay.Position - currentPos).Magnitude < 3.5 then forceJump(myHuman) elseif hDist < 4 then forceJump(myHuman) end end
                    else
                        -- เรียกใช้ Pathfinding
                        if os.clock() - lastComputeTime > 0.5 or (targetPos - lastTargetPos).Magnitude > 5 then
                            local path = PathfindingService:CreatePath({
                                AgentRadius = 2.0, -- ลดรัศมีลงให้เข้าบันไดแคบๆ ได้ง่ายขึ้น
                                AgentHeight = 5, 
                                AgentCanJump = true,
                                WaypointSpacing = 3 
                            })
                            path:ComputeAsync(currentPos, targetPos)
                            
                            if path.Status == Enum.PathStatus.Success then
                                isProbing = false
                                currentWaypoints = path:GetWaypoints(); currentWaypointIndex = 2
                                lastTargetPos = targetPos; lastComputeTime = os.clock()
                            else
                                -- [จุดที่แก้] ถ้าหาทางไปบ้านต้นไม้ไม่เจอ ให้มองหาบันไดใกล้ตัวแทน
                                isProbing = true
                                currentWaypoints = {}
                            end
                        end

                        if isProbing then
                            -- ถ้าเป้าหมายอยู่สูง แต่หาทางไม่ได้ ให้ลองวิ่งหาบันได (Ladder Rescue)
                            local targetLadder = (vDist > 8) and findNearestLadder(currentPos)
                            if targetLadder then
                                updateDebug("ProbeTrace", currentPos, targetLadder.Position, Color3.fromRGB(255, 100, 255))
                                myHuman:MoveTo(targetLadder.Position)
                                -- ถ้าเข้าใกล้บันไดแล้ว ให้พยายามเดินชนเพื่อให้มันเกาะ
                                if (targetLadder.Position - currentPos).Magnitude < 3 then forceJump(myHuman) end
                            else
                                -- ถ้าไม่มีบันไดจริงๆ ค่อยใช้ลอจิกแหย่ทางเดิม
                                local probeDir = getProbingDirection(myRoot, targetPos)
                                if probeDir then myHuman:MoveTo(currentPos + (probeDir * 8)) end
                            end
                        elseif #currentWaypoints > 0 then
                            -- [ลอจิกเดินตาม Waypoint และ Smooth Path เหมือนเดิม...]
                            local lookAheadIndex = currentWaypointIndex
                            local maxLookAhead = math.min(currentWaypointIndex + 6, #currentWaypoints) 
                            for i = maxLookAhead, currentWaypointIndex + 1, -1 do
                                local isHeightSafe = true
                                for j = currentWaypointIndex, i do if math.abs(currentWaypoints[j].Position.Y - currentPos.Y) > 1.5 then isHeightSafe = false; break end end
                                if isHeightSafe then
                                    local hasJump = false
                                    for j = currentWaypointIndex, i do if currentWaypoints[j].Action == Enum.PathWaypointAction.Jump then hasJump = true; break end end
                                    if not hasJump then
                                        local rO = currentPos + Vector3.new(0, 2, 0)
                                        if not workspace:Raycast(rO, currentWaypoints[i].Position + Vector3.new(0, 2, 0) - rO, rayParams) then lookAheadIndex = i; break end
                                    end
                                end
                            end
                            currentWaypointIndex = lookAheadIndex
                            local wp = currentWaypoints[currentWaypointIndex]
                            if wp then
                                local isClimbing = myHuman:GetState() == Enum.HumanoidStateType.Climbing
                                local isGoingUp = (wp.Position.Y > currentPos.Y + 2.5)
                                if isGoingUp and not isClimbing then
                                    local fDir = (Vector3.new(wp.Position.X, 0, wp.Position.Z) - Vector3.new(currentPos.X, 0, currentPos.Z))
                                    myHuman:MoveTo(wp.Position + (fDir.Magnitude > 0.1 and fDir.Unit * 1.5 or Vector3.zero))
                                else myHuman:MoveTo(wp.Position) end
                                local d2D = (Vector2.new(currentPos.X, currentPos.Z) - Vector2.new(wp.Position.X, wp.Position.Z)).Magnitude
                                if (isClimbing and (currentPos.Y >= wp.Position.Y - 1 or (d2D < 5 and math.abs(currentPos.Y - wp.Position.Y) < 3.5))) or (not isClimbing and d2D < 4.5 and math.abs(currentPos.Y - wp.Position.Y) < 3.5) then
                                    currentWaypointIndex = currentWaypointIndex + 1
                                end
                                if not isClimbing and (wp.Action == Enum.PathWaypointAction.Jump or (isGoingUp and d2D < 2)) then forceJump(myHuman) end
                            end
                        end
                    end
                else
                    currentWaypoints = {}; myHuman:MoveTo(currentPos)
                end
            end
        end)
    end
end)
