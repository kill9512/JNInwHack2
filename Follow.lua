local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("KONG GUISUS", "DarkTheme")
local Tab = Window:NewTab("Main")
local Section = Tab:NewSection("Smart Follow Player")

-- --- Variables ---
local SelectedMode = "Manual"
local SelectedPlayer = nil
local UsePercentage = false
local followDistance = 5
local followEnabled = false
local followPower = "Normal" -- โหมดพลังพิเศษ
local flySpeed = 10 -- ความเร็วในการบิน/วาร์ป

-- ฟังก์ชันหาเลือดผู้เล่น
local function getHealth(plr)
    local char = plr.Character
    if char and char:FindFirstChild("Humanoid") then
        if UsePercentage then
            return char.Humanoid.Health / char.Humanoid.MaxHealth
        else
            return char.Humanoid.Health
        end
    end
    return nil
end

-- ฟังก์ชันอัปเดตรายชื่อ
local function UpdatePlayerTable()
    local tbl = {"None (Off)"}
    for _, plr in pairs(game.Players:GetPlayers()) do
        if plr.Name ~= game.Players.LocalPlayer.Name then
            table.insert(tbl, plr.Name)
        end
    end
    return tbl
end

-- --- UI Elements ---

-- 1. เลือกโหมดการหาเป้าหมาย
Section:NewDropdown("Target Mode", "Choose how to find target", {"Manual", "Max HP", "Min HP", "Off"}, function(mode)
    SelectedMode = mode
end)

-- 2. เลือกชื่อผู้เล่น (Manual)
local drop = Section:NewDropdown("Select Player", "Manual selection", UpdatePlayerTable(), function(name)
    SelectedPlayer = (name == "None (Off)") and nil or name
end)

-- 3. ปุ่ม Refresh รายชื่อ
Section:NewButton("Refresh Players", "Update manual list", function()
    drop:Refresh(UpdatePlayerTable())
end)

-- 4. Toggle ระบบเลือด %
Section:NewToggle("Use % Health Logic", "Check health by percentage", function(state)
    UsePercentage = state
end)

-- --- UI ส่วนควบคุมการเดิน (Movement Control) ---
local MoveSection = Tab:NewSection("Movement Control")

MoveSection:NewToggle("Enable Follow", "Start following system", function(state)
    followEnabled = state
end)

-- 5. Dropdown พลังพิเศษ
MoveSection:NewDropdown("Movement Mode", "Select follow style", {"Normal", "Walk (Copy Speed)", "TeleportBehind", "CFrameFly"}, function(v)
    followPower = v
    -- คืนค่าความเร็วปกติถ้าสลับโหมด
    local myHum = game.Players.LocalPlayer.Character:FindFirstChild("Humanoid")
    if myHum then myHum.WalkSpeed = 16 end
end)

MoveSection:NewSlider("Follow Distance", "Distance from target", 20, 1, function(s)
    followDistance = s
end)

MoveSection:NewSlider("Power Speed", "Speed for Fly/Warp", 100, 1, function(s)
    flySpeed = s
end)

-- --- LOGIC CORE (หัวใจหลักของความเทพ) ---
task.spawn(function()
    while task.wait(0.01) do -- ถี่ขึ้นเพื่อความเนียนในโหมด Fly
        if not followEnabled then continue end
        
        local finalTarget = nil

        -- 1. Logic ค้นหาเป้าหมาย
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

        -- 2. Logic การเคลื่อนไหวเหนือธรรมชาติ
        if finalTarget and finalTarget.Character and finalTarget.Character:FindFirstChild("HumanoidRootPart") then
            local myChar = game.Players.LocalPlayer.Character
            local myRoot = myChar:FindFirstChild("HumanoidRootPart")
            local myHuman = myChar:FindFirstChild("Humanoid")
            local targetRoot = finalTarget.Character.HumanoidRootPart
            
            if myRoot and targetRoot and myHuman then
                local dist = (myRoot.Position - targetRoot.Position).Magnitude
                
                -- --- เช็คโหมดพลังพิเศษ ---
                
                if followPower == "Normal" then
                    -- เดินตามแบบปกติ (Logic เดิม)
                    if dist > followDistance then
                        local dir = (targetRoot.Position - myRoot.Position).Unit
                        myHuman:MoveTo(targetRoot.Position - (dir * followDistance))
                        -- กระโดดเมื่อติด
                        local ray = Ray.new(myRoot.Position, dir * 3)
                        local hit = workspace:FindPartOnRayWithIgnoreList(ray, {myChar})
                        if hit and hit.CanCollide then myHuman.Jump = true end
                    end

                elseif followPower == "Walk (Copy Speed)" then
                    -- เดินตาม + เลียนแบบความเร็ว
                    local targetHum = finalTarget.Character:FindFirstChild("Humanoid")
                    if targetHum then myHuman.WalkSpeed = targetHum.WalkSpeed end
                    if dist > followDistance then
                        myHuman:MoveTo(targetRoot.Position - (targetRoot.CFrame.LookVector * followDistance))
                    end

                elseif followPower == "TeleportBehind" then
                    -- สิงหลัง (ผีหลอก)
                    local backPos = targetRoot.CFrame * CFrame.new(0, 0, followDistance)
                    myRoot.CFrame = CFrame.lookAt(backPos.Position, targetRoot.Position)

                elseif followPower == "CFrameFly" then
                    -- บินไปหา (NoClip Style)
                    if dist > followDistance then
                        local dir = (targetRoot.Position - myRoot.Position).Unit
                        myRoot.CFrame = myRoot.CFrame + (dir * (flySpeed / 50))
                        myRoot.CFrame = CFrame.lookAt(myRoot.Position, targetRoot.Position)
                        myRoot.Velocity = Vector3.new(0, 0, 0) -- กันร่วง
                    end
                end
            end
        end
    end
end)
