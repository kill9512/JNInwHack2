local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("KONG GUISUS", "DarkTheme")
local Tab = Window:NewTab("Main")
local Section = Tab:NewSection("Smart Follow Player")

-- --- Services ---
local Players = game.Players
local LocalPlayer = Players.LocalPlayer

-- --- Variables ---
local SelectedMode = "Manual"
local SelectedPlayerName = nil
local followDistance = 5
local followEnabled = false

local lastPos = Vector3.new(0,0,0)
local stuckTime = 0
local detourTimer = 0 -- ตัวนับเวลาการเดินอ้อม
local lockedDir = nil -- ทิศทางที่ถูกล็อกไว้
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- --- ฟังก์ชันวิเคราะห์ทางเบี่ยง (เพิ่มระบบป้องกันการสลับฝั่ง) ---
local function getBestEscapeDir(myRoot, moveDir)
    local scanAngles = {45, -45, 90, -90, 135, -135}
    local bestDir = nil
    local maxFreeDist = 0

    for _, angle in ipairs(scanAngles) do
        local rotatedDir = (CFrame.Angles(0, math.rad(angle), 0) * Vector3.new(moveDir.X, 0, moveDir.Z)).Unit
        -- ยิง Ray 2 เส้นคู่ขนานเพื่อเช็คความกว้างตัวละคร (ไหล่ซ้าย-ขวา)
        local offset = Vector3.new(0, 0.5, 0)
        local result = workspace:Raycast(myRoot.Position + offset, rotatedDir * 10, rayParams)
        
        local freeDist = result and result.Distance or 10
        if freeDist > maxFreeDist then
            maxFreeDist = freeDist
            bestDir = rotatedDir
        end
    end
    return bestDir
end

-- --- UI Setup ---
Section:NewDropdown("Target Mode", "Mode", {"Manual", "Max HP", "Min HP"}, function(m) SelectedMode = m end)
local drop = Section:NewDropdown("Select Player", "Select Target", {}, function(s) 
    SelectedPlayerName = s:match("@([^%)]+)") 
end)

local function refresh()
    local t = {"None (Off)"}
    for _, p in pairs(Players:GetPlayers()) do 
        if p ~= LocalPlayer then table.insert(t, p.DisplayName.." (@"..p.Name..")") end 
    end
    drop:Refresh(t)
end
Section:NewButton("Refresh Players", "Update List", refresh)
refresh()

local MoveSection = Tab:NewSection("Movement Control")
MoveSection:NewToggle("Enable Follow", "Start Movement", function(state) followEnabled = state end)
MoveSection:NewSlider("Distance", "Follow Gap", 20, 1, function(s) followDistance = s end)

-- --- LOGIC CORE ---
task.spawn(function()
    while task.wait(0.1) do
        if not followEnabled then continue end
        
        local target = nil
        -- [ส่วนหาเป้าหมาย]
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
                local dist = (myRoot.Position - tRoot.Position).Magnitude
                local moveDir = (tRoot.Position - myRoot.Position).Unit
                local jumpable = (myHuman.JumpPower > 0 or myHuman.JumpHeight > 0)

                -- ** 1. ระบบจัดการสถานะการเดินอ้อม (Detour State) **
                if detourTimer > 0 then
                    detourTimer = detourTimer - 0.1
                    if lockedDir then
                        myHuman:MoveTo(myRoot.Position + (lockedDir * 10))
                        if jumpable then myHuman.Jump = true end
                        
                        -- เช็คว่าทางข้างหน้าเป้าหมายจริงๆ เริ่มโล่งหรือยัง ถ้าโล่งแล้วให้ยกเลิกการอ้อมก่อนกำหนด
                        local clearRay = workspace:Raycast(myRoot.Position, moveDir * 6, rayParams)
                        if not clearRay then detourTimer = 0 end
                        
                        continue -- ล็อกคำสั่งเดินอ้อมไว้ ห้ามทำอย่างอื่น
                    end
                end

                -- ตรวจจับการติดนิ่ง
                if (myRoot.Position - lastPos).Magnitude < 0.4 and myHuman.MoveDirection.Magnitude > 0 then
                    stuckTime = stuckTime + 0.1
                else
                    stuckTime = 0
                end
                lastPos = myRoot.Position

                if dist > followDistance then
                    -- เช็คสิ่งกีดขวางข้างหน้าตรงๆ
                    local frontHit = workspace:Raycast(myRoot.Position, moveDir * 6, rayParams)
                    local headHit = workspace:Raycast(myRoot.Position + Vector3.new(0, 2.5, 0), moveDir * 6, rayParams)

                    -- ** 2. เงื่อนไขการเข้าสู่โหมดเดินอ้อม **
                    if stuckTime > 0.3 or frontHit then
                        local bestDir = getBestEscapeDir(myRoot, moveDir)
                        if bestDir then
                            lockedDir = bestDir
                            detourTimer = 1.2 -- ล็อกให้เดินอ้อมเป็นเวลา 1.2 วินาที (ห้ามวอกแวก)
                            stuckTime = 0
                            
                            if jumpable and not headHit then myHuman.Jump = true end
                        end
                    else
                        -- 3. ทางสะดวก เดินปกติ
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
