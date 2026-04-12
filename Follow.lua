local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("KONG GUISUS", "DarkTheme")
local Tab = Window:NewTab("Main")
local Section = Tab:NewSection("Smart Follow Player")
local PlayerTable = {}

-- --- Variables ---
local SelectedMode = "Manual" -- โหมดเริ่มต้น
local SelectedPlayer = nil -- ชื่อผู้เล่นที่เลือกเอง
local UsePercentage = false -- Toggle สำหรับ % HP

-- ฟังก์ชันหาเลือดผู้เล่น
local function getHealth(plr)
    local char = plr.Character
    if char and char:FindFirstChild("Humanoid") then
        if UsePercentage then
            -- ส่งคืนค่าเป็น % (เลือดปัจจุบัน / เลือดสูงสุด)
            return char.Humanoid.Health / char.Humanoid.MaxHealth
        else
            -- ส่งคืนค่าเลือดดิบๆ
            return char.Humanoid.Health
        end
    end
    return nil
end

-- ฟังก์ชันอัปเดตรายชื่อ (เหมือนเดิม)
local function UpdatePlayerTable()
    local tbl = {"None (Off)"} -- เพิ่ม Option พิเศษไว้หัวแถว
    for _, plr in pairs(game.Players:GetPlayers()) do
        if plr.Name ~= game.Players.LocalPlayer.Name then
            table.insert(tbl, plr.Name)
        end
    end
    return tbl
end

-- --- UI Elements ---

-- 1. เลือกโหมดการทำงาน
Section:NewDropdown("Target Mode", "Choose how to find target", {"Manual", "Max HP", "Min HP", "Off"}, function(mode)
    SelectedMode = mode
end)

-- 2. เลือกชื่อผู้เล่น (Manual)
local drop = Section:NewDropdown("Select Player", "Manual selection", UpdatePlayerTable(), function(name)
    if name == "None (Off)" then
        SelectedPlayer = nil
    else
        SelectedPlayer = name
    end
end)
drop:Refresh(UpdatePlayerTable())
-- 3. ปุ่ม Refresh รายชื่อ
Section:NewButton("Refresh Players", "Update manual list", function()
    drop:Refresh(UpdatePlayerTable())
end)

-- 4. Toggle ระบบเลือด %
Section:NewToggle("Use % Health Logic", "If ON, check health by percentage", function(state)
    UsePercentage = state
end)

-- --- เพิ่มตัวแปรคุมการเดิน ---
local followDistance = 5
local followEnabled = false

-- --- UI ส่วนควบคุมการเดิน ---
local MoveSection = Tab:NewSection("Movement Control")

MoveSection:NewToggle("Enable Follow", "Start moving to target", function(state)
    followEnabled = state
end)

MoveSection:NewSlider("Follow Distance", "Distance from target", 20, 1, function(s)
    followDistance = s
end)

-- --- LOGIC CORE (ตัวคำนวณและสั่งเดิน) ---
task.spawn(function()
    while task.wait(0.1) do -- ความเร็วในการอัปเดตตำแหน่ง
        if not followEnabled then continue end -- ถ้าปิด Toggle ก็ไม่ต้องทำอะไร
        
        local finalTarget = nil

        -- 1. เลือกเป้าหมายตามโหมด (Logic เดิมที่เราคุยกัน)
        if SelectedMode == "Manual" then
            finalTarget = game.Players:FindFirstChild(SelectedPlayer)
        elseif SelectedMode == "Max HP" then
            local highHealth = -1
            for _, p in pairs(game.Players:GetPlayers()) do
                if p ~= game.Players.LocalPlayer then
                    local hp = getHealth(p)
                    if hp and hp > highHealth then highHealth = hp; finalTarget = p end
                end
            end
        elseif SelectedMode == "Min HP" then
            local lowHealth = math.huge
            for _, p in pairs(game.Players:GetPlayers()) do
                if p ~= game.Players.LocalPlayer then
                    local hp = getHealth(p)
                    if hp and hp < lowHealth then lowHealth = hp; finalTarget = p end
                end
            end
        end

        -- 2. สั่งเดินไปหาเป้าหมาย (Logic จากโค้ดที่คุณให้มา)
        if finalTarget and finalTarget.Character and finalTarget.Character:FindFirstChild("HumanoidRootPart") then
            local myChar = game.Players.LocalPlayer.Character
            local myHuman = myChar:FindFirstChild("Humanoid")
            local myRoot = myChar:FindFirstChild("HumanoidRootPart")
            local targetRoot = finalTarget.Character.HumanoidRootPart
            
            if myHuman and myRoot and targetRoot then
                local distance = (myRoot.Position - targetRoot.Position).Magnitude
                
                -- ถ้าอยู่ไกลเกินระยะที่ตั้งไว้ ให้เดินไปหา
                if distance > followDistance then
                    -- คำนวณจุดที่จะเดินไป (หยุดก่อนถึงตัวตามระยะห่าง)
                    local direction = (targetRoot.Position - myRoot.Position).Unit
                    local destination = targetRoot.Position - (direction * followDistance)
                    
                    -- ใช้ MoveTo เพื่อความลื่นไหล
                    myHuman:MoveTo(destination)
                    
                    -- เช็คสิ่งกีดขวาง (Raycast แบบง่าย)
                    local ray = Ray.new(myRoot.Position, direction * 3)
                    local hit = workspace:FindPartOnRayWithIgnoreList(ray, {myChar})
                    if hit and hit.CanCollide then
                        myHuman.Jump = true -- ถ้าติดกำแพงให้กระโดด
                    end
                end
            end
        end
    end
end)
