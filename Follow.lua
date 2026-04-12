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
local SelectedPlayer = nil
local UsePercentage = false
local followDistance = 5
local followEnabled = false

-- --- Raycast Settings ---
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

-- --- ฟังก์ชันเสริม (Utility) ---
local function getHealth(plr)
    local char = plr.Character
    if char and char:FindFirstChild("Humanoid") then
        local hum = char.Humanoid
        return UsePercentage and (hum.Health / hum.MaxHealth) or hum.Health
    end
    return nil
end

local function UpdatePlayerTable()
    local tbl = {"None (Off)"}
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then table.insert(tbl, plr.Name) end
    end
    return tbl
end

-- ฟังก์ชันแสกนหาทางเดินอ้อม (กรณีทางตรงตัน)
local function getScanDirection(myRoot, moveDir)
    local scanAngles = {30, -30, 60, -60, 90, -90} -- มุมที่ใช้แสกน (องศา)
    for _, angle in ipairs(scanAngles) do
        local rotatedDir = (CFrame.Angles(0, math.rad(angle), 0) * Vector3.new(moveDir.X, 0, moveDir.Z)).Unit
        local scanRay = workspace:Raycast(myRoot.Position, rotatedDir * 7, rayParams)
        if not scanRay then return rotatedDir end -- คืนค่าทิศทางแรกที่ว่าง
    end
    return nil
end

-- --- UI Elements ---
Section:NewDropdown("Target Mode", "Choose how to find target", {"Manual", "Max HP", "Min HP", "Off"}, function(mode)
    SelectedMode = mode
end)

local drop = Section:NewDropdown("Select Player", "Manual selection", UpdatePlayerTable(), function(name)
    SelectedPlayer = (name == "None (Off)") and nil or name
end)

Section:NewButton("Refresh Players", "Update manual list", function()
    drop:Refresh(UpdatePlayerTable())
end)

Section:NewToggle("Use % Health Logic", "If ON, check health by percentage", function(state)
    UsePercentage = state
end)

local MoveSection = Tab:NewSection("Movement Control")
MoveSection:NewToggle("Enable Follow", "Start moving to target", function(state)
    followEnabled = state
end)

MoveSection:NewSlider("Follow Distance", "Distance from target", 20, 1, function(s)
    followDistance = s
end)

-- --- LOGIC CORE (Smart Engine) ---
task.spawn(function()
    while task.wait(0.1) do
        if not followEnabled or SelectedMode == "Off" then continue end
        
        local finalTarget = nil

        -- 1. ค้นหาเป้าหมายตามเงื่อนไข
        if SelectedMode == "Manual" then
            finalTarget = Players:FindFirstChild(SelectedPlayer)
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

        -- 2. สั่งเดินอัจฉริยะ
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

                    -- เช็คสิ่งกีดขวางข้างหน้า
                    local lowRay = workspace:Raycast(myRoot.Position + Vector3.new(0,-1,0), moveDir * 6, rayParams)
                    local highRay = workspace:Raycast(myRoot.Position + Vector3.new(0,2,0), moveDir * 6, rayParams)

                    if lowRay and lowRay.Instance.CanCollide then
                        -- ถ้าเจอสิ่งกีดขวาง
                        if not highRay then
                            -- ของเตี้ย -> ลองกระโดด (ถ้าโดนห้ามโดด จะไปเข้า Logic แสกนต่อ)
                            myHuman.Jump = true 
                        end
                        
                        -- แสกนหาทางอ้อม (ไม่ว่าจะกระโดดได้หรือไม่ได้ ระบบนี้จะทำงานร่วมกัน)
                        local detour = getScanDirection(myRoot, moveDir)
                        if detour then
                            myHuman:MoveTo(myRoot.Position + (detour * 5))
                        else
                            -- ตันทุกทาง -> ถอยหลังตั้งหลัก
                            myHuman:MoveTo(myRoot.Position - (moveDir * 5))
                        end
                    else
                        -- ทางสะดวก เดินไปหาจุดหมาย (หยุดก่อนถึงระยะ Follow)
                        local destination = tRoot.Position - (moveDir * followDistance)
                        myHuman:MoveTo(destination)
                    end
                else
                    -- ถึงระยะแล้ว หยุดเดินและหันหน้าหาเป้าหมาย
                    myHuman:MoveTo(myRoot.Position)
                    myRoot.CFrame = CFrame.lookAt(myRoot.Position, Vector3.new(tRoot.Position.X, myRoot.Position.Y, tRoot.Position.Z))
                end
            end
        end
    end
end)
