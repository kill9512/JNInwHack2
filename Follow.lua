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
local UsePercentage = false
local followDistance = 5
local followEnabled = false

-- --- Raycast Settings ---
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

-- --- ฟังก์ชันเสริม ---

local function UpdatePlayerTable()
    local tbl = {"None (Off)"}
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            table.insert(tbl, plr.DisplayName .. " (@" .. plr.Name .. ")")
        end
    end
    return tbl
end

-- เช็คว่ามองเห็นเป้าหมายหรือไม่
local function canSeeTarget(myRoot, targetRoot)
    rayParams.FilterDescendantsInstances = {LocalPlayer.Character, targetRoot.Parent}
    local direction = (targetRoot.Position - myRoot.Position)
    local result = workspace:Raycast(myRoot.Position, direction, rayParams)
    return result == nil
end

-- --- UI Elements ---
Section:NewDropdown("Target Mode", "Choose how to find target", {"Manual", "Max HP", "Min HP"}, function(mode)
    SelectedMode = mode
end)

local drop = Section:NewDropdown("Select Player", "Manual selection", UpdatePlayerTable(), function(selection)
    if selection == "None (Off)" then SelectedPlayerName = nil
    else SelectedPlayerName = selection:match("@([^%)]+)") end
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

-- --- ฟังก์ชันเช็คว่าเกมนี้กระโดดได้ไหม ---
local function canGameJump(humanoid)
    local powerEnabled = (humanoid.JumpPower > 0 or humanoid.JumpHeight > 0)
    local stateEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping)
    return powerEnabled and stateEnabled
end

-- --- LOGIC CORE (เวอร์ชันอัปเกรดการตรวจจับและกระโดด) ---
task.spawn(function()
    while task.wait(0.1) do
        if not followEnabled then continue end
        
        -- [ส่วนการหา Target เหมือนเดิม]
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
                local dist = (myRoot.Position - tRoot.Position).Magnitude
                local moveDir = (tRoot.Position - myRoot.Position).Unit
                local isJumpable = canGameJump(myHuman) -- เช็คว่าเกมโดดได้ไหม

                -- ระบบตรวจจับการติด (Stuck Detection)
                if (myRoot.Position - lastPos).Magnitude < 0.4 and myHuman.MoveDirection.Magnitude > 0 then
                    stuckTime = stuckTime + 0.1
                else
                    stuckTime = 0
                end
                lastPos = myRoot.Position

                if dist > followDistance then
                    -- ** โหมดแก้ติด: ถ้าเกมโดดได้ ให้ลองโดดรัวๆ ก่อน **
                    if stuckTime > 0.3 then
                        if isJumpable then myHuman.Jump = true end
                        local escape = getBestEscapeDir(myRoot, moveDir) or -moveDir
                        myHuman:MoveTo(myRoot.Position + (escape * 7)) 
                        task.wait(0.2)
                        stuckTime = 0
                        continue
                    end

                    -- ยิง Ray เช็คสิ่งกีดขวาง (ปรับระยะและความสูงใหม่ให้แม่นขึ้น)
                    -- เส้นล่าง (ระดับเข่า): ถ้าโดนแปลว่าต้องโดดหรือเลี้ยว
                    local lowHit = workspace:Raycast(myRoot.Position + Vector3.new(0, -0.8, 0), moveDir * 4, rayParams)
                    -- เส้นกลาง (ระดับอก): ถ้าโดนแปลว่าของสูง
                    local midHit = workspace:Raycast(myRoot.Position + Vector3.new(0, 1.5, 0), moveDir * 4, rayParams)
                    -- เส้นบน (เหนือหัว): ถ้าโดนแปลว่าทางตัน/เพดานต่ำ
                    local highHit = workspace:Raycast(myRoot.Position + Vector3.new(0, 3.5, 0), moveDir * 4, rayParams)

                    if lowHit or midHit then
                        -- 1. ถ้าเกมโดดได้ และข้างบนไม่มีอะไรขวาง -> กระโดดทันที
                        if isJumpable and not highHit then
                            myHuman.Jump = true
                        end
                        
                        -- 2. หักเลี้ยว (ทำควบคู่ไปกับการกระโดด)
                        local bestDir = getBestEscapeDir(myRoot, moveDir)
                        if bestDir then
                            myHuman:MoveTo(myRoot.Position + (bestDir * 6))
                        end
                    else
                        -- ทางสะดวก เดินไปหาเป้าหมายปกติ
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
