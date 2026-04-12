local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("KONG GUISUS", "DarkTheme")
local Tab = Window:NewTab("Main")
local Section = Tab:NewSection("Smart Follow Player")

local Players = game.Players
local LocalPlayer = Players.LocalPlayer

local SelectedPlayerName = nil
local followDistance = 5
local followEnabled = false
local lastPos = Vector3.new(0,0,0)
local stuckTime = 0

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- --- ฟังก์ชันเช็คว่า "กระโดดได้ไหม" ---
local function canGameJump(humanoid)
    local hasPower = humanoid.JumpPower > 0 or humanoid.JumpHeight > 0
    local isStateEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping)
    return hasPower and isStateEnabled
end

-- --- ฟังก์ชันแสกนหาทางที่โล่งที่สุด ---
local function getBestDir(myRoot, moveDir)
    local scanAngles = {45, -45, 90, -90}
    local best = nil
    local maxDist = 0
    for _, angle in ipairs(scanAngles) do
        local rotDir = (CFrame.Angles(0, math.rad(angle), 0) * Vector3.new(moveDir.X, 0, moveDir.Z)).Unit
        local res = workspace:Raycast(myRoot.Position, rotDir * 8, rayParams)
        local d = res and res.Distance or 8
        if d > maxDist then maxDist = d; best = rotDir end
    end
    return best
end

-- [UI Setup ส่วนที่เหลือเหมือนเดิม...]
local drop = Section:NewDropdown("Select Player", "Select Target", {}, function(s) SelectedPlayerName = s:match("@([^%)]+)") end)
local function refresh()
    local t = {"None (Off)"}
    for _, p in pairs(Players:GetPlayers()) do if p ~= LocalPlayer then table.insert(t, p.DisplayName.." (@"..p.Name..")") end end
    drop:Refresh(t)
end
Section:NewButton("Refresh Players", "Update", refresh)
refresh()

local MoveSection = Tab:NewSection("Movement Control")
MoveSection:NewToggle("Enable Follow", "Start", function(state) followEnabled = state end)
MoveSection:NewSlider("Distance", "Gap", 20, 1, function(s) followDistance = s end)

-- --- LOGIC CORE ---
task.spawn(function()
    while task.wait(0.1) do
        if not followEnabled then continue end
        
        local target = Players:FindFirstChild(SelectedPlayerName or "")
        if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
            local myChar = LocalPlayer.Character
            local myHuman = myChar and myChar:FindFirstChild("Humanoid")
            local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
            local tRoot = target.Character.HumanoidRootPart
            
            if myHuman and myRoot then
                rayParams.FilterDescendantsInstances = {myChar, target.Character}
                local moveDir = (tRoot.Position - myRoot.Position).Unit
                local dist = (myRoot.Position - tRoot.Position).Magnitude
                
                -- ตรวจสอบว่า "กระโดดได้ไหม" ในเกมนี้
                local ableToJump = canGameJump(myHuman)

                -- Stuck Detection
                if (myRoot.Position - lastPos).Magnitude < 0.4 and myHuman.MoveDirection.Magnitude > 0 then
                    stuckTime = stuckTime + 0.1
                else stuckTime = 0 end
                lastPos = myRoot.Position

                if dist > followDistance then
                    -- 1. ยิง Ray เช็ค 3 ระดับ (เท้า, เอว, เหนือหัว)
                    local footHit = workspace:Raycast(myRoot.Position + Vector3.new(0, -1.5, 0), moveDir * 4, rayParams)
                    local waistHit = workspace:Raycast(myRoot.Position + Vector3.new(0, 0, 0), moveDir * 4, rayParams)
                    local headHit = workspace:Raycast(myRoot.Position + Vector3.new(0, 3, 0), moveDir * 4, rayParams)

                    -- 2. ตัดสินใจ "กระโดด" (เพิ่มลำดับความสำคัญให้สูงขึ้น)
                    if ableToJump and (footHit or waistHit) then
                        if not headHit then
                            -- ถ้าเท้าติดหรือเอวติด แต่หัวว่าง = "กระโดดอัดเข้าไปเลย"
                            myHuman.Jump = true
                        end
                    end

                    -- 3. ถ้าติดมุม (Stuck) หรือโดดแล้วไม่ไป ให้พยายาม "หักเลี้ยว"
                    if stuckTime > 0.3 or (waistHit and headHit) then
                        if ableToJump then myHuman.Jump = true end -- ลองโดดเผื่อไว้
                        local detour = getBestDir(myRoot, moveDir)
                        if detour then
                            myHuman:MoveTo(myRoot.Position + (detour * 6))
                            if ableToJump and stuckTime > 0.5 then myHuman.Jump = true end
                        end
                    else
                        -- ทางสะดวก เดินไปหาเป้าหมาย
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
