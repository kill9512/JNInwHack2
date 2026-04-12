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
local followDistance = 5
local followEnabled = false

local lastPos = Vector3.new(0,0,0)
local stuckTime = 0

-- --- Raycast Settings ---
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

-- --- ฟังก์ชันแสกนหาทางเดินอ้อม (ปรับให้กว้างขึ้น) ---
local function getScanDirection(myRoot, moveDir)
    local scanAngles = {45, -45, 90, -90, 135, -135} 
    for _, angle in ipairs(scanAngles) do
        local rotatedDir = (CFrame.Angles(0, math.rad(angle), 0) * Vector3.new(moveDir.X, 0, moveDir.Z)).Unit
        local scanRay = workspace:Raycast(myRoot.Position, rotatedDir * 8, rayParams)
        if not scanRay then return rotatedDir end
    end
    return nil
end

-- --- UI Elements ---
Section:NewDropdown("Target Mode", "Choose target", {"Manual", "Max HP", "Min HP"}, function(mode) SelectedMode = mode end)

local drop = Section:NewDropdown("Select Player", "Selection", (function()
    local t = {"None (Off)"}
    for _, p in pairs(Players:GetPlayers()) do if p ~= LocalPlayer then table.insert(t, p.DisplayName .. " (@" .. p.Name .. ")") end end
    return t
end)(), function(selection)
    if selection == "None (Off)" then SelectedPlayerName = nil
    else SelectedPlayerName = selection:match("@([^%)]+)") end
end)

Section:NewButton("Refresh Players", "Update list", function() drop:Refresh((function()
    local t = {"None (Off)"}
    for _, p in pairs(Players:GetPlayers()) do if p ~= LocalPlayer then table.insert(t, p.DisplayName .. " (@" .. p.Name .. ")") end end
    return t
end)()) end)

local MoveSection = Tab:NewSection("Movement Control")
MoveSection:NewToggle("Enable Follow", "Start following", function(state) followEnabled = state end)
MoveSection:NewSlider("Follow Distance", "Distance", 20, 1, function(s) followDistance = s end)

-- --- LOGIC CORE ---
task.spawn(function()
    while task.wait(0.1) do
        if not followEnabled then continue end
        
        local finalTarget = nil
        if SelectedMode == "Manual" then
            if SelectedPlayerName then finalTarget = Players:FindFirstChild(SelectedPlayerName) end
        else
            -- Logic หา Max/Min HP (ย่อเพื่อความกระชับ)
            local bestHP = (SelectedMode == "Max HP") and -1 or math.huge
            for _, p in pairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("Humanoid") then
                    local hp = p.Character.Humanoid.Health
                    if (SelectedMode == "Max HP" and hp > bestHP) or (SelectedMode == "Min HP" and hp < bestHP) then
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
                rayParams.FilterDescendantsInstances = {myChar, finalTarget.Character}
                local dist = (myRoot.Position - tRoot.Position).Magnitude
                
                -- ตรวจสอบว่าติดมุมหรือไม่ (Stuck Detection)
                if (myRoot.Position - lastPos).Magnitude < 0.5 and myHuman.MoveDirection.Magnitude > 0 then
                    stuckTime = stuckTime + 0.1
                else
                    stuckTime = 0
                end
                lastPos = myRoot.Position

                if dist > followDistance then
                    local moveDir = (tRoot.Position - myRoot.Position).Unit
                    
                    -- โหมดแก้ปัญหาเมื่อติด (Stuck Recovery)
                    if stuckTime > 0.5 then
                        myHuman.Jump = true
                        local escapeDir = getScanDirection(myRoot, moveDir) or -moveDir
                        myHuman:MoveTo(myRoot.Position + (escapeDir * 10))
                        task.wait(0.3) -- ให้เวลามันขยับออกจากมุม
                        stuckTime = 0
                        continue
                    end

                    -- เช็คสิ่งกีดขวางระดับเอวและหัว
                    local lowRay = workspace:Raycast(myRoot.Position + Vector3.new(0,-1,0), moveDir * 6, rayParams)
                    local highRay = workspace:Raycast(myRoot.Position + Vector3.new(0,1.5,0), moveDir * 6, rayParams)

                    if lowRay then
                        -- เจอของขวาง
                        if not highRay then
                            myHuman.Jump = true -- ของเตี้ยโดดข้าม
                        end
                        
                        -- หาทางเบี่ยง
                        local detour = getScanDirection(myRoot, moveDir)
                        if detour then
                            myHuman:MoveTo(myRoot.Position + (detour * 7))
                        else
                            myHuman.Jump = true
                            myHuman:MoveTo(myRoot.Position - (moveDir * 5)) -- ตันถอยหลัง
                        end
                    else
                        -- ทางสะดวก เดินไปหาเป้าหมาย
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
