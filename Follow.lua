local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("KONG GUISUS", "DarkTheme")
local Tab = Window:NewTab("Main")
local Section = Tab:NewSection("Advanced Follow + Debug")

-- --- Services ---
local Players = game.Players
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")

-- --- Variables ---
local SelectedMode = "Manual"
local SelectedPlayerName = nil
local followDistance = 5
local followEnabled = false
local debugEnabled = false -- ตัวแปรคุมการเปิดปิด Debug

local lastJump = 0
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- --- ฟังก์ชันวาดเส้น Debug ---
local function updateDebugLine(name, startPos, endPos, color)
    if not debugEnabled then 
        if Terrain:FindFirstChild(name) then Terrain[name]:Destroy() end
        return 
    end
    
    local line = Terrain:FindFirstChild(name) or Instance.new("LineHandleAdornment")
    line.Name = name
    line.Length = (startPos - endPos).Magnitude
    line.Thickness = 5
    line.Color3 = color or Color3.fromRGB(255, 0, 0)
    line.Adornee = workspace.Terrain
    line.CFrame = CFrame.lookAt(startPos, endPos)
    line.AlwaysOnTop = true -- ทำให้มองทะลุกำแพงได้เพื่อเช็ค Path
    line.Parent = workspace.Terrain
end

-- --- ฟังก์ชันคำนวณการกระจัด (Displacement) ---
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
Section:NewDropdown("Target Mode", "Choose Mode", {"Manual", "Max HP", "Min HP"}, function(m) SelectedMode = m end)
local drop = Section:NewDropdown("Select Target", "User", {}, function(s) SelectedPlayerName = s:match("@([^%)]+)") end)

local function refresh()
    local t = {"None (Off)"}
    for _, p in pairs(Players:GetPlayers()) do if p ~= LocalPlayer then table.insert(t, p.DisplayName.." (@"..p.Name..")") end end
    drop:Refresh(t)
end
Section:NewButton("Refresh List", "Update", refresh)
refresh()

local MoveSection = Tab:NewSection("Control & Debug")
MoveSection:NewToggle("Enable Follow", "Start Follow Logic", function(s) followEnabled = s end)
MoveSection:NewToggle("Show Debug Lines", "Visual Pathing (Red Lines)", function(s) 
    debugEnabled = s 
    if not s then -- ล้างเส้นเมื่อปิด
        for _, v in pairs(workspace.Terrain:GetChildren()) do
            if v.Name:find("DebugLine") then v:Destroy() end
        end
    end
end)
MoveSection:NewSlider("Follow Distance", "Gap", 20, 1, function(s) followDistance = s end)

-- --- LOGIC CORE ---
task.spawn(function()
    while task.wait(0.05) do
        if not followEnabled then continue end
        
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
                    -- ** 1. Trace เส้นตรงหลัก (Aimbot Path) **
                    local directRay = workspace:Raycast(currentPos, moveDir * 8, rayParams)
                    
                    if directRay then
                        -- วาดเส้น Debug เมื่อติดสิ่งกีดขวาง (เส้นสีแดงเข้ม)
                        updateDebugLine("DebugLine_Main", currentPos, directRay.Position, Color3.fromRGB(150, 0, 0))
                        
                        -- ** 2. วิเคราะห์การกระโดด **
                        local headCheck = workspace:Raycast(currentPos + Vector3.new(0, 2.5, 0), moveDir * 5, rayParams)
                        if not headCheck and tick() - lastJump > 0.6 then
                            myHuman.Jump = true
                            lastJump = tick()
                        end
                        
                        -- ** 3. คำนวณทางกระจัดใหม่ (เส้นสีเขียว/ฟ้าใน Debug) **
                        local detour = calculateDisplacementPath(myRoot, moveDir)
                        if detour then
                            updateDebugLine("DebugLine_Detour", currentPos, detour, Color3.fromRGB(0, 255, 255))
                            myHuman:MoveTo(detour)
                        else
                            myHuman:MoveTo(currentPos - (moveDir * 5)) -- ถอยตั้งหลัก
                        end
                    else
                        -- ** 4. ทางโล่ง วาดเส้นสีเขียวไปหาเป้าหมาย **
                        updateDebugLine("DebugLine_Main", currentPos, targetPos, Color3.fromRGB(0, 255, 0))
                        if workspace.Terrain:FindFirstChild("DebugLine_Detour") then 
                            workspace.Terrain.DebugLine_Detour:Destroy() 
                        end
                        myHuman:MoveTo(targetPos)
                    end
                else
                    -- ถึงระยะแล้ว: หยุดและหันหน้า
                    myHuman:MoveTo(currentPos)
                    local lookAt = Vector3.new(targetPos.X, currentPos.Y, targetPos.Z)
                    myRoot.CFrame = myRoot.CFrame:Lerp(CFrame.lookAt(currentPos, lookAt), 0.2)
                    
                    -- ล้างเส้น Debug เมื่อหยุดเดิน
                    if workspace.Terrain:FindFirstChild("DebugLine_Main") then workspace.Terrain.DebugLine_Main:Destroy() end
                    if workspace.Terrain:FindFirstChild("DebugLine_Detour") then workspace.Terrain.DebugLine_Detour:Destroy() end
                end
            end
        end
    end
end)
