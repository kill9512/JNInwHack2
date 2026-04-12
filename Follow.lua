local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("KONG GUISUS + PATH DEBUG", "DarkTheme")
local Tab = Window:NewTab("Main")
local Section = Tab:NewSection("Pathfinding Debugger")

-- --- Services ---
local Players = game.Players
local LocalPlayer = Players.LocalPlayer
local Terrain = workspace.Terrain

-- --- Variables ---
local SelectedMode = "Manual"
local SelectedPlayerName = nil
local followDistance = 5
local followEnabled = false
local debugEnabled = false

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- --- ฟังก์ชันวาดเส้น Path ---
local function drawLine(name, startPos, endPos, color, thickness, transparency)
    local line = Terrain:FindFirstChild(name) or Instance.new("LineHandleAdornment")
    line.Name = name
    line.Length = (startPos - endPos).Magnitude
    line.Thickness = thickness or 3
    line.Color3 = color or Color3.fromRGB(255, 255, 255)
    line.Transparency = transparency or 0
    line.Adornee = Terrain
    line.CFrame = CFrame.lookAt(startPos, endPos)
    line.AlwaysOnTop = true
    line.Parent = Terrain
end

local function clearDebug()
    for _, v in pairs(Terrain:GetChildren()) do
        if v.Name:find("PathLine") then v:Destroy() end
    end
end

-- --- UI Setup ---
Section:NewDropdown("Target Mode", "Mode", {"Manual", "Max HP", "Min HP"}, function(m) SelectedMode = m end)
local drop = Section:NewDropdown("Select Player", "User", {}, function(s) 
    SelectedPlayerName = s:match("@([^%)]+)") 
end)

local function refresh()
    local t = {"None (Off)"}
    for _, p in pairs(Players:GetPlayers()) do if p ~= LocalPlayer then table.insert(t, p.DisplayName.." (@"..p.Name..")") end end
    drop:Refresh(t)
end
Section:NewButton("Refresh List", "Update", refresh)
refresh()

local MoveSection = Tab:NewSection("Movement & Visual")
MoveSection:NewToggle("Enable Follow", "Start AI", function(s) followEnabled = s end)
MoveSection:NewToggle("Debug Path (Show Lines)", "Show Scanning Logic", function(s) 
    debugEnabled = s 
    if not s then clearDebug() end
end)
MoveSection:NewSlider("Gap", "Distance", 20, 1, function(s) followDistance = s end)

-- --- LOGIC CORE ---
task.spawn(function()
    while task.wait(0.05) do
        if not debugEnabled and not followEnabled then continue end
        
        -- ค้นหาเป้าหมาย
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

        if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            local myChar = LocalPlayer.Character
            local myRoot = myChar.HumanoidRootPart
            local myHuman = myChar.Humanoid
            local tRoot = target.Character.HumanoidRootPart
            
            rayParams.FilterDescendantsInstances = {myChar, target.Character}
            
            local currentPos = myRoot.Position
            local targetPos = tRoot.Position
            local moveVec = (targetPos - currentPos)
            local moveDir = moveVec.Unit
            
            -- ** 1. แสกนเส้นทางหลัก (Primary Path) **
            local mainRay = workspace:Raycast(currentPos, moveDir * 10, rayParams)
            
            if mainRay then
                -- ติดกำแพง! วาดเส้นแดงไปจุดที่ติด
                if debugEnabled then drawLine("PathLine_Main", currentPos, mainRay.Position, Color3.fromRGB(255, 0, 0), 5, 0) end
                
                -- ** 2. แสกนซ้าย-ขวาเพื่อหาทางเลี่ยง (Displacement Scan) **
                local scanAngles = {30, -30, 60, -60}
                local bestDetour = nil
                local minGapToTarget = math.huge
                
                for i, angle in ipairs(scanAngles) do
                    local rotDir = (CFrame.Angles(0, math.rad(angle), 0) * Vector3.new(moveDir.X, 0, moveDir.Z)).Unit
                    local scanRay = workspace:Raycast(currentPos, rotDir * 10, rayParams)
                    
                    local endPoint = currentPos + (rotDir * 10)
                    local color = Color3.fromRGB(0, 255, 255) -- สีฟ้าสำหรับการแสกน
                    
                    if not scanRay then
                        -- ทางนี้ว่าง! คำนวณว่าถ้าไปทางนี้ จะห่างจากผู้เล่นเท่าไหร่
                        local gap = (endPoint - targetPos).Magnitude
                        if gap < minGapToTarget then
                            minGapToTarget = gap
                            bestDetour = rotDir
                            color = Color3.fromRGB(0, 255, 0) -- สีเขียวคือทางที่เลือก
                        end
                    end
                    if debugEnabled then drawLine("PathLine_Scan"..i, currentPos, endPoint, color, 2, 0.5) end
                end
                
                -- ** 3. สั่งเดินและกระโดด **
                if followEnabled then
                    if bestDetour then
                        myHuman:MoveTo(currentPos + (bestDetour * 5))
                    else
                        myHuman:MoveTo(currentPos - (moveDir * 5)) -- ตันถอยหลัง
                    end
                    
                    -- เช็คความสูงบล็อกที่ขวางอยู่ ถ้าหัวไม่ติด -> กระโดด!
                    local headCheck = workspace:Raycast(currentPos + Vector3.new(0, 2.5, 0), moveDir * 5, rayParams)
                    if not headCheck and mainRay.Distance < 5 then
                        myHuman.Jump = true
                    end
                end
            else
                -- ทางสะดวก!
                if debugEnabled then 
                    drawLine("PathLine_Main", currentPos, targetPos, Color3.fromRGB(0, 255, 0), 3, 0.5)
                    -- ลบเส้นแสกนเก่าๆ
                    for i=1, 4 do if Terrain:FindFirstChild("PathLine_Scan"..i) then Terrain["PathLine_Scan"..i]:Destroy() end end
                end
                if followEnabled and moveVec.Magnitude > followDistance then
                    myHuman:MoveTo(targetPos)
                end
            end
        else
            clearDebug()
        end
    end
end)
