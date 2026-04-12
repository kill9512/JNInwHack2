local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("KONG GUISUS", "DarkTheme")
local Tab = Window:NewTab("Main")
local Section = Tab:NewSection("Smart Follow Player")

-- --- Services ---
local Players = game.Players
local LocalPlayer = Players.LocalPlayer

-- --- Variables ---
local SelectedMode = "Manual" -- เริ่มต้นที่ Manual
local SelectedPlayerName = nil -- เก็บชื่อจริงของผู้เล่น (@Name)
local UsePercentage = false
local followDistance = 5
local followEnabled = false

-- --- Raycast Settings ---
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

-- --- ฟังก์ชันเสริม ---

-- ฟังก์ชันอัปเดตรายชื่อ (แสดงชื่อเล่น + ชื่อจริง)
local function UpdatePlayerTable()
    local tbl = {"None (Off)"}
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            -- ฟอร์แมต: ชื่อเล่น (@ชื่อจริง)
            local entry = plr.DisplayName .. " (@" .. plr.Name .. ")"
            table.insert(tbl, entry)
        end
    end
    return tbl
end

-- ฟังก์ชันหาเลือด
local function getHealth(plr)
    local char = plr.Character
    if char and char:FindFirstChild("Humanoid") then
        local hum = char.Humanoid
        return UsePercentage and (hum.Health / hum.MaxHealth) or hum.Health
    end
    return nil
end

-- ฟังก์ชันแสกนทางเดินอ้อม
local function getScanDirection(myRoot, moveDir)
    local scanAngles = {30, -30, 60, -60, 90, -90}
    for _, angle in ipairs(scanAngles) do
        local rotatedDir = (CFrame.Angles(0, math.rad(angle), 0) * Vector3.new(moveDir.X, 0, moveDir.Z)).Unit
        local scanRay = workspace:Raycast(myRoot.Position, rotatedDir * 7, rayParams)
        if not scanRay then return rotatedDir end
    end
    return nil
end

-- --- UI Elements ---

-- 1. Target Mode (ไม่มี Off, Default เป็น Manual)
Section:NewDropdown("Target Mode", "Choose how to find target", {"Manual", "Max HP", "Min HP"}, function(mode)
    SelectedMode = mode
end)

-- 2. Select Player (แสดงชื่อเล่น, Default เป็น None (Off))
local drop = Section:NewDropdown("Select Player", "Manual selection", UpdatePlayerTable(), function(selection)
    if selection == "None (Off)" then
        SelectedPlayerName = nil
    else
        -- ใช้ String Pattern ดึงชื่อภายใต้เครื่องหมาย @ ออกมา
        local name = selection:match("@([^%)]+)")
        SelectedPlayerName = name
    end
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

        -- ค้นหาเป้าหมาย
        if SelectedMode == "Manual" then
            if SelectedPlayerName then
                finalTarget = Players:FindFirstChild(SelectedPlayerName)
            end
        elseif SelectedMode == "Max HP" or SelectedMode == "Min HP" then
            local bestHP = (SelectedMode == "Max HP") and -1 or math.huge
            for _, p in pairs(Players:GetPlayers()) do
                if p ~= LocalPlayer then
                    local hp = getHealth(p)
                    if hp then
                        if (SelectedMode == "Max HP" and hp > bestHP) or (SelectedMode == "Min HP" and hp < bestHP) then
                            bestHP = hp
                            finalTarget = p
                        end
                    end
                end
            end
        end

        -- สั่งเดิน
        if finalTarget and finalTarget.Character and finalTarget.Character:FindFirstChild("HumanoidRootPart") then
            local myChar = LocalPlayer.Character
            local myHuman = myChar and myChar:FindFirstChild("Humanoid")
            local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
            local tRoot = finalTarget.Character.HumanoidRootPart
            
            if myHuman and myRoot then
                local dist = (myRoot.Position - tRoot.Position).Magnitude
                
                if dist > followDistance then
                    local moveDir = (tRoot.Position - myRoot.Position).Unit
                    rayParams.FilterDescendantsInstances = {myChar, finalTarget.Character}

                    local lowRay = workspace:Raycast(myRoot.Position + Vector3.new(0,-1,0), moveDir * 6, rayParams)
                    local highRay = workspace:Raycast(myRoot.Position + Vector3.new(0,2,0), moveDir * 6, rayParams)

                    if lowRay and lowRay.Instance.CanCollide then
                        if not highRay then myHuman.Jump = true end
                        local detour = getScanDirection(myRoot, moveDir)
                        if detour then
                            myHuman:MoveTo(myRoot.Position + (detour * 5))
                        else
                            myHuman:MoveTo(myRoot.Position - (moveDir * 5))
                        end
                    else
                        myHuman:MoveTo(tRoot.Position - (moveDir * followDistance))
                    end
                else
                    myHuman:MoveTo(myRoot.Position)
                    myRoot.CFrame = CFrame.lookAt(myRoot.Position, Vector3.new(tRoot.Position.X, myRoot.Position.Y, tRoot.Position.Z))
                end
            end
        end
    end
end)
