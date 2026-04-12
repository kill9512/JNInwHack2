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
local isProbing = false
local stuckTimer = 0
local lastPos = Vector3.new()

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

local function clearVisuals()
    for _, v in pairs(workspace.Terrain:GetChildren()) do
        if v.Name == "WP_Debug" or v.Name == "DirectTrace" or v.Name == "ProbeTrace" or v.Name == "ShoulderL" or v.Name == "ShoulderR" then v:Destroy() end
    end
end

-- --- Helper Functions ---
local function forceJump(hum)
    if hum.FloorMaterial ~= Enum.Material.Air then
        hum.Jump = true
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end

-- เช็คว่าช่องข้างหน้าแคบเกินไปสำหรับ "ไหล่" ของบอทไหม
local function checkShoulderClearance(myRoot, moveDir)
    local leftSide = (CFrame.Angles(0, math.rad(45), 0) * moveDir).Unit
    local rightSide = (CFrame.Angles(0, math.rad(-45), 0) * moveDir).Unit
    
    local hitL = workspace:Raycast(myRoot.Position, leftSide * 4, rayParams)
    local hitR = workspace:Raycast(myRoot.Position, rightSide * 4, rayParams)
    
    if debugEnabled then
        updateDebug("ShoulderL", myRoot.Position, myRoot.Position + leftSide * 4, Color3.fromRGB(255, 255, 255))
        updateDebug("ShoulderR", myRoot.Position, myRoot.Position + rightSide * 4, Color3.fromRGB(255, 255, 255))
    end
    
    return hitL, hitR
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

local MoveSection = Tab:NewSection("Tactical Navigation")
MoveSection:NewToggle("Enable Follow", "Start Logic", function(s) 
    followEnabled = s 
    if not s then currentWaypoints = {}; clearVisuals(); isProbing = false end
end)
MoveSection:NewToggle("Show Path", "Visuals", function(s) debugEnabled = s end)
MoveSection:NewSlider("Distance", "Gap", 20, 1, function(s) followDistance = s end)

-- --- MAIN LOOP ---
task.spawn(function()
    while true do
        task.wait(0.12)
        if not followEnabled then continue end
        
        pcall(function()
            -- [ส่วนค้นหาเป้าหมายเหมือนเดิม]
            local target = nil
            if SelectedMode == "Manual" then target = Players:FindFirstChild(SelectedPlayerName or "")
            else
                local bestHP = (SelectedMode == "Max HP") and -1 or math.huge
                for _, p in pairs(Players:GetPlayers()) do
                    if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("Humanoid") then
                        local hp = p.Character.Humanoid.Health
                        if (SelectedMode == "Max HP" and hp > bestHP) or (SelectedMode == "Min HP" and hp < bestHP) then bestHP = hp; target = p end
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

                -- ระบบ Stuck (แผนซ้อนแผน: ถ้าติดให้ถอยหรือเปลี่ยนแผน)
                if (currentPos - lastPos).Magnitude < 0.3 then stuckTimer += 0.1 else stuckTimer = 0 end
                lastPos = currentPos

                if dist > followDistance then
                    local moveDir = (targetPos - currentPos).Unit
                    local directRay = workspace:Raycast(currentPos, moveDir * dist, rayParams)

                    -- แผน 1: เดินตรง (Line of Sight)
                    if not directRay then
                        isProbing = false; currentWaypoints = {}
                        updateDebug("DirectTrace", currentPos, targetPos, Color3.fromRGB(0, 255, 0))
                        myHuman:MoveTo(targetPos)
                    else
                        -- แผน 2: เดินตามทางสีฟ้า (Global Path)
                        if os.clock() - lastComputeTime > 1.0 or (targetPos - lastTargetPos).Magnitude > 8 or stuckTimer > 1.5 then
                            local path = PathfindingService:CreatePath({AgentRadius = 3, AgentHeight = 5, AgentCanJump = true})
                            path:ComputeAsync(currentPos, targetPos)
                            if path.Status == Enum.PathStatus.Success then
                                isProbing = false; currentWaypoints = path:GetWaypoints(); currentWaypointIndex = 2
                                lastTargetPos = targetPos; lastComputeTime = os.clock()
                                if debugEnabled then clearVisuals() --[วาดจุดสีฟ้าเหมือนเดิม] end
                            else
                                isProbing = true; currentWaypoints = {}
                            end
                        end

                        -- ** แผนซ้อนแผน: ตรวจสอบขณะเดินตามจุดสีฟ้า **
                        if #currentWaypoints > 0 then
                            local wp = currentWaypoints[currentWaypointIndex]
                            if wp then
                                local wpDir = (wp.Position - currentPos).Unit
                                local hitL, hitR = checkShoulderClearance(myRoot, wpDir)

                                -- ถ้าไหล่ซ้ายหรือขวาจะชนขอบทาง (แม้จุดสีฟ้าจะบอกให้ไป)
                                if hitL or hitR or stuckTimer > 0.8 then
                                    -- "ขัดคำสั่งแผนหลัก" -> หักเลี้ยวหนีขอบกำแพงทันที
                                    local detourDir = hitL and (CFrame.Angles(0, math.rad(-60), 0) * wpDir).Unit or (CFrame.Angles(0, math.rad(60), 0) * wpDir).Unit
                                    if stuckTimer > 1.2 then -- ถ้าติดหนักมาก ให้ถอยหลัง/หันกลับ
                                        myHuman:MoveTo(currentPos - wpDir * 10)
                                        forceJump(myHuman)
                                        currentWaypoints = {} -- ล้างแผนเก่าทิ้งเพื่อให้คำนวณใหม่
                                    else
                                        myHuman:MoveTo(currentPos + detourDir * 5)
                                        forceJump(myHuman)
                                    end
                                else
                                    -- ทางสีฟ้ายังปลอดภัย เดินต่อไป
                                    myHuman:MoveTo(wp.Position)
                                    if (Vector2.new(currentPos.X, currentPos.Z) - Vector2.new(wp.Position.X, wp.Position.Z)).Magnitude < 3.5 then
                                        currentWaypointIndex = currentWaypointIndex + 1
                                    end
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
