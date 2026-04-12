local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("KONG GUISUS - GOD MODE", "DarkScene")

-- รายแปรหลักที่ดึงมาจากโค้ดที่คุณให้มา
local targetPlayer = nil
local followDistance = 3
local lookAtEnabled = false
local pathfindingEnabled = false
local RunService = game:GetService("RunService")

-- ฟังก์ชันค้นหาชื่อ (ดึง Logic มาจากโค้ดที่คุณส่งมา)
local function findPlayerByName(partialName)
    if partialName == "" then return nil end
    partialName = string.lower(partialName)
    for _, p in pairs(game.Players:GetPlayers()) do
        if string.find(string.lower(p.Name), partialName) or string.find(string.lower(p.DisplayName), partialName) then
            return p
        end
    end
    return nil
end

-- ================= TAB: MAIN =================
local Tab = Window:NewTab("Main")
local FollowSection = Tab:NewSection("Player Tracker")

-- 1. ช่องกรอกชื่อ (TextBox)
FollowSection:NewTextBox("Target Name", "พิมพ์ชื่อคนที่จะตาม", function(txt)
    targetPlayer = findPlayerByName(txt)
    if targetPlayer then
        Library:Notify("Found Player", "Lock on to: " .. targetPlayer.DisplayName, 3)
    end
end)

-- 2. ปุ่มเปิด/ปิดระบบตาม (Toggle)
FollowSection:NewToggle("Enable Follow", "เปิดระบบเดินตามอัจฉริยะ", function(state)
    lookAtEnabled = state
end)

-- 3. ปรับระยะห่าง (Slider)
FollowSection:NewSlider("Distance", "ระยะห่างจากเป้าหมาย", 20, 1, function(s)
    followDistance = s
end)

-- 4. เปิดโหมดเดินอ้อมสิ่งกีดขวาง (Pathfinding)
FollowSection:NewToggle("Smart Pathfinding", "ใช้ AI คำนวณเส้นทางเวลาติดกำแพง", function(state)
    pathfindingEnabled = state
end)

-- ================= TAB: SETTINGS =================
local SettingsTab = Window:NewTab("Settings")
local MiscSection = SettingsTab:NewSection("Others")

MiscSection:NewButton("Destroy UI", "ปิดโปรแกรมนี้", function()
    Library:Destroy()
end)

-- ================= LOGIC CORE (หัวใจสำคัญ) =================
RunService.Heartbeat:Connect(function()
    if lookAtEnabled and targetPlayer and targetPlayer.Character then
        local myRoot = game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        local tRoot = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
        local myHuman = game.Players.LocalPlayer.Character:FindFirstChild("Humanoid")
        
        if myRoot and tRoot and myHuman then
            local dist = (myRoot.Position - tRoot.Position).Magnitude
            
            if dist > followDistance then
                if pathfindingEnabled and dist > 10 then
                    -- Logic Pathfinding แบบย่อจากโค้ดที่คุณส่งมา
                    myHuman:MoveTo(tRoot.Position)
                else
                    -- เดินตรงๆ ถ้าอยู่ใกล้
                    myHuman:MoveTo(tRoot.Position - (tRoot.CFrame.LookVector * followDistance))
                end
            end
        end
    end
end)
