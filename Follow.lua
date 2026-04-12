local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("KONG GUISUS", "DarkTheme")
local Tab = Window:NewTab("Main")
local Section = Tab:NewSection("Advanced Follow + Debug")

-- --- Services ---
local Players = game.Players
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")
local Terrain = workspace:FindFirstChildOfClass("Terrain") -- นิยาม Terrain ให้ชัดเจน

-- --- Variables ---
local SelectedMode = "Manual"
local SelectedPlayerName = nil
local followDistance = 5
local followEnabled = false
local debugEnabled = false

local lastJump = 0
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- --- ฟังก์ชันวาดเส้น Debug (ปรับปรุงให้ปลอดภัยขึ้น) ---
local function updateDebugLine(name, startPos, endPos, color)
    if not debugEnabled or not startPos or not endPos then 
        if Terrain:FindFirstChild(name) then Terrain[name]:Destroy() end
        return 
    end
    
    local line = Terrain:FindFirstChild(name) or Instance.new("LineHandleAdornment")
    line.Name = name
    line.Length = (startPos - endPos).Magnitude
    line.Thickness = 5
    line.Color3 = color or Color3.fromRGB(255, 0, 0)
    line.Adornee = Terrain
    line.CFrame = CFrame.lookAt(startPos, endPos)
    line.AlwaysOnTop = true
    line.Parent = Terrain
end

-- --- ฟังก์ชันคำนวณการกระจัด ---
local function calculateDisplacementPath(myRoot, moveDir)
    local scanAngles = {15, -15, 30, -30, 45, -45, 60, -60}
    local bestPoint = nil
    local minAngle = math.huge

    for _, angle in ipairs(scanAngles) do
        local rotatedDir = (CFrame.Angles(0, math.rad(angle), 0) * Vector3.new(moveDir.X, 0, moveDir.Z)).Unit
        local result = workspace:Raycast(myRoot.Position, rotatedDir * 12, rayParams)
        
        if not result then
            if math.abs(angle) < minAngle then
                minAngle = math.abs(angle)
                bestPoint = myRoot.Position + (rotatedDir * 10)
            end
        end
    end
    return bestPoint
end

-- --- UI Elements ---
Section:NewDropdown("Target Mode", "Choose Mode", {"Manual", "Max HP", "Min HP"}, function(m) 
    SelectedMode = m 
end)

local drop = Section:NewDropdown("Select Target", "User", {}, function(s) 
    local name = s:match("@([^%)]+)")
    SelectedPlayerName = name
end)

local function refresh()
    local t = {"None (Off)"}
    for _, p in pairs(Players:GetPlayers()) do 
        if p ~= LocalPlayer then 
            table.insert(t, p.DisplayName .. " (@" .. p.Name .. ")") 
        end 
    end
    drop:Refresh(t)
end

Section:NewButton("Refresh List", "Update", refresh)
refresh()

local MoveSection = Tab:NewSection("Control & Debug")
MoveSection:NewToggle("Enable Follow", "Start Follow Logic", function(s) followEnabled = s end)
MoveSection:NewToggle("Show Debug Lines", "Visual Pathing (Lines)", function(s) 
    debugEnabled = s 
    if not s then
        for _, v in pairs(Terrain:GetChildren()) do
            if v.Name:find("DebugLine") then v:Destroy() end
        end
    end
end)
MoveSection:NewSlider("Follow Distance", "Gap", 20, 1, function(s) followDistance = s end)

-- --- LOGIC CORE ---
task.spawn(function()
    while true do
        task.wait(0.05)
        if not followEnabled then 
            -- ล้างเส้นถ้าไม่ได้เปิดใช้งาน
            updateDebugLine("DebugLine_Main", nil, nil)
            updateDebugLine("DebugLine_Detour", nil, nil)
            continue 
        end
        
        -- ใช้ pcall ครอบเพื่อไม่ให้ลูปตายถ้ามี Error
        pcall(function()
            local target = nil
            if SelectedMode == "Manual" then
                if SelectedPlayerName then
                    target = Players:FindFirstChild(SelectedPlayerName)
                end
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
                    local moveVec = (targetPos - currentPos)
                    local dist = moveVec.Magnitude
                    local moveDir = moveVec.Unit

                    if dist > followDistance then
                        local directRay = workspace:Raycast(currentPos, moveDir * 10, rayParams)
                        
                        if directRay then
                            -- ติดกำแพง (เส้นแดง)
                            updateDebugLine("DebugLine_Main", currentPos, directRay.Position, Color3.fromRGB(255, 0, 0))
                            
                            -- เช็คกระโดด
                            local headCheck = workspace:Raycast(currentPos + Vector3.new(0, 2, 0), moveDir * 5, rayParams)
                            if not headCheck and tick() - lastJump > 0.7 then
                                myHuman.Jump = true
                                lastJump = tick()
                            end
                            
                            -- คำนวณทางเลี่ยง (เส้นฟ้า)
                            local detour = calculateDisplacementPath(myRoot, moveDir)
                            if detour then
                                updateDebugLine("DebugLine_Detour", currentPos, detour, Color3.fromRGB(0, 255, 255))
                                myHuman:MoveTo(detour)
                            else
                                myHuman:MoveTo(currentPos - (moveDir * 2)) -- ถอยถ้าตัน
                            end
                        else
                            -- ทางโล่ง (เส้นเขียว)
                            updateDebugLine("DebugLine_Main", currentPos, targetPos, Color3.fromRGB(0, 255, 0))
                            if Terrain:FindFirstChild("DebugLine_Detour") then Terrain.DebugLine_Detour:Destroy() end
                            myHuman:MoveTo(targetPos)
                        end
                    else
                        -- ระยะประชิด
                        myHuman:MoveTo(currentPos)
                        local lookAt = Vector3.new(targetPos.X, currentPos.Y, targetPos.Z)
                        myRoot.CFrame = myRoot.CFrame:Lerp(CFrame.lookAt(currentPos, lookAt), 0.2)
                        
                        updateDebugLine("DebugLine_Main", nil, nil)
                        updateDebugLine("DebugLine_Detour", nil, nil)
                    end
                end
            else
                -- ถ้าไม่มีเป้าหมาย ให้ล้างเส้น
                updateDebugLine("DebugLine_Main", nil, nil)
                updateDebugLine("DebugLine_Detour", nil, nil)
            end
        end)
    end
end)
