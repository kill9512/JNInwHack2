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

-- 1. เลือกโหมดการทำงาน (ตั้งชื่อหัวข้อเป็น Manual ไปเลย)
Section:NewDropdown("Manual", "Choose how to find target", {"Manual", "Max HP", "Min HP", "Off"}, function(mode)
    SelectedMode = mode
end)

-- 2. เลือกชื่อผู้เล่น (สร้างแบบปกติ ไม่ต้องใส่ในฟังก์ชันให้งง)
local drop = Section:NewDropdown("None (Off)", "Manual selection", UpdatePlayerTable(), function(name)
    if name == "None (Off)" then
        SelectedPlayer = nil
    else
        SelectedPlayer = name
    end
end)

-- 3. ปุ่ม Refresh (แบบล้างชื่อบนปุ่มได้ 100% โดย UI ไม่พัง)
Section:NewButton("Refresh Dropdown", "Update list & Reset selection", function()
    -- 1. ล้างสมองบอท
    SelectedPlayer = nil 
    
    -- 2. จังหวะแรก: บีบให้รายการเหลือแค่ None (Off) อันเดียว
    -- วิธีนี้จะบังคับให้ Label บนปุ่มเด้งกลับมาเป็น None (Off) ทันที
    drop:Refresh({"None (Off)"})
    
    -- 3. คั่นจังหวะนิดนึงให้ UI มันขยับ (ห้ามลบ)
    task.wait(0.1)
    
    -- 4. จังหวะสอง: โหลดรายชื่อผู้เล่นปัจจุบันกลับมา
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

-- --- เพิ่ม Service ที่จำเป็นไว้บนสุดของ Script ---
local PathfindingService = game:GetService("PathfindingService")

-- --- LOGIC CORE (ตัวคำนวณและสั่งเดินแบบฉลาด) ---
task.spawn(function()
    while task.wait(0.1) do 
        if not followEnabled then continue end 
        
        local finalTarget = nil
        -- [ส่วนเลือกเป้าหมาย SelectedMode เหมือนเดิม...]
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

        -- --- ส่วนสั่งเดินแบบ Smart Pathfinding ---
        if finalTarget and finalTarget.Character and finalTarget.Character:FindFirstChild("HumanoidRootPart") then
            local myChar = game.Players.LocalPlayer.Character
            local myHuman = myChar:FindFirstChild("Humanoid")
            local myRoot = myChar:FindFirstChild("HumanoidRootPart")
            local targetRoot = finalTarget.Character.HumanoidRootPart
            
            if myHuman and myRoot and targetRoot then
                local distance = (myRoot.Position - targetRoot.Position).Magnitude
                
                -- ถ้าอยู่ไกลกว่าระยะที่ตั้งไว้ ให้คำนวณทางเดิน
                if distance > followDistance then
                    -- 1. สร้าง Path
                    local path = PathfindingService:CreatePath({
                        AgentCanJump = true, -- อนุญาตให้กระโดดข้ามสิ่งกีดขวาง
                        AgentWaypointSpacing = 2 -- ระยะห่างของจุดเดิน
                    })
                    
                    -- 2. คำนวณเส้นทางจาก 'เรา' ไป 'เป้าหมาย'
                    path:ComputeAsync(myRoot.Position, targetRoot.Position)
                    
                    -- 3. ถ้าคำนวณสำเร็จ ให้เดินตามจุด Waypoints
                    if path.Status == Enum.PathStatus.Success then
                        local waypoints = path:GetWaypoints()
                        
                        -- เดินไปหาจุดที่ 2 (จุดแรกคือที่ที่เรายืนอยู่)
                        if waypoints[2] then
                            local wp = waypoints[2]
                            myHuman:MoveTo(wp.Position)
                            
                            -- ถ้าจุดนั้นบอกให้กระโดด ก็กระโดด
                            if wp.Action == Enum.PathfindingWaypointAction.Jump then
                                myHuman.Jump = true
                            end
                        end
                    else
                        -- ถ้า Pathfinding ล้มเหลว (ทางตัน) ให้เดินตรงๆ ไปก่อนกันนิ่ง
                        myHuman:MoveTo(targetRoot.Position)
                    end
                end
            end
        end
    end
end)
