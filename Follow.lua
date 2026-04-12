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
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

-- --- ฟังก์ชันเสริม (Helper Functions) ---

local function UpdatePlayerTable()
    local tbl = {"None (Off)"}
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            table.insert(tbl, plr.DisplayName .. " (@" .. plr.Name .. ")")
        end
    end
    return tbl
end

local function getBestEscapeDir(myRoot, moveDir)
    -- แสกนหาทางที่โล่งที่สุดจากมุม 30, 60, 90 องศา ซ้ายและขวา
    local scanAngles = {30, -30, 60, -60, 90, -90}
    local bestDir = nil
    local maxDist = 0

    for _, angle in ipairs(scanAngles) do
        local rotatedDir = (CFrame.Angles(0, math.rad(angle), 0) * Vector3.new(moveDir.X, 0, moveDir.Z)).Unit
        local result = workspace:Raycast(myRoot.Position, rotatedDir * 8, rayParams)
        local dist = result and result.Distance or 8
        
        if dist > maxDist then
            maxDist = dist
            bestDir = rotatedDir
        end
    end
    return bestDir
end

-- --- UI Elements ---
Section:NewDropdown("Target Mode", "Choose target logic", {"Manual", "Max HP", "Min HP"}, function(mode)
    SelectedMode = mode
end)

local drop = Section:NewDropdown("Select Player", "Choose specific person", UpdatePlayerTable(), function(selection)
    if selection == "None (Off)" then SelectedPlayerName = nil
    else SelectedPlayerName = selection:match("@([^%)]+)") end
end)

Section:NewButton("Refresh Players", "Update list", function()
    drop:Refresh(UpdatePlayerTable())
end)

local MoveSection = Tab:NewSection("Movement Control")
MoveSection:NewToggle("Enable Follow", "Start AI movement", function(state)
    followEnabled = state
end)

MoveSection:NewSlider("Follow Distance", "Target gap", 20, 1, function(s)
    followDistance = s
end)

-- --- LOGIC CORE ---
task.spawn(function()
    while task.wait(0.1) do
        if not followEnabled then continue end
        
        local finalTarget = nil
        -- [ค้นหาเป้าหมายตามโหมด]
        if SelectedMode == "Manual" then
            if SelectedPlayerName then finalTarget = Players:FindFirstChild(SelectedPlayerName) end
        else
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
                local moveDir = (tRoot.Position - myRoot.Position).Unit
                
                -- ** AUTO-CHECK: เกมนี้โดดได้ไหม? **
                local canJump = (myHuman.JumpPower > 0 or myHuman.JumpHeight > 0)

                -- Stuck Detection: ถ้าตัวไม่ขยับเลย
                if (myRoot.Position - lastPos).Magnitude < 0.4 and myHuman.MoveDirection.Magnitude > 0 then
                    stuckTime = stuckTime + 0.1
                else
                    stuckTime = 0
                end
                lastPos = myRoot.Position

                if dist > followDistance then
                    -- ** 1. ระบบแก้ติด (Stuck Recovery) **
                    if stuckTime > 0.4 then
                        if canJump then myHuman.Jump = true end
                        local escape = getBestEscapeDir(myRoot, moveDir) or -moveDir
                        myHuman:MoveTo(myRoot.Position + (escape * 7))
                        task.wait(0.2)
                        stuckTime = 0
                        continue
                    end

                    -- ** 2. ระบบนำทางอัจฉริยะ (Smart Navigation) **
                    -- ยิงเลเซอร์ 3 ระดับ: เท้า (-1.5), เอว (0.5), หัว (3)
                    local rayFoot = workspace:Raycast(myRoot.Position + Vector3.new(0, -1.5, 0), moveDir * 5, rayParams)
                    local rayHip = workspace:Raycast(myRoot.Position + Vector3.new(0, 0.5, 0), moveDir * 5, rayParams)
                    local rayHead = workspace:Raycast(myRoot.Position + Vector3.new(0, 3, 0), moveDir * 5, rayParams)

                    if rayFoot or rayHip then
                        -- ถ้าเจอของขวางขา/เอว
                        if canJump and not rayHead then
                            -- ถ้าทางข้างบนว่าง -> กระโดดปีน
                            myHuman.Jump = true
                        end
                        
                        -- ไม่ว่าจะโดดได้หรือไม่ ให้ลองเบี่ยงหาทางที่โล่งกว่าเสมอ
                        local bestDir = getBestEscapeDir(myRoot, moveDir)
                        if bestDir then
                            myHuman:MoveTo(myRoot.Position + (bestDir * 6))
                        end
                    else
                        -- ทางสะดวก เดินเข้าหาเป้าหมาย
                        myHuman:MoveTo(tRoot.Position - (moveDir * followDistance))
                    end
                else
                    -- ถึงระยะแล้ว: หยุดและหันหน้าหาเป้าหมาย
                    myHuman:MoveTo(myRoot.Position)
                    myRoot.CFrame = CFrame.lookAt(myRoot.Position, Vector3.new(tRoot.Position.X, myRoot.Position.Y, tRoot.Position.Z))
                end
            end
        end
    end
end)
