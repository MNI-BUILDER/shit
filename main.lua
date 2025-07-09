-- CLEAN REAL-TIME MONITOR - FIXED EGG UPDATES
print("🔥 Clean Real-Time Monitor Starting - FIXED EGG UPDATES...")

-- Configuration
local API_ENDPOINT = "https://groweas.vercel.app/api/data"
local DELETE_ENDPOINT = "https://gagdata.vercel.app/api/delete"
local API_KEY = "GAMERSBERGGAG"
local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1375178535198785586/-kGnmx4QJnWlOOqPutLGurRu132ALTTAne8d4MMgNvTJg825vkpT1yU9R_-s74GBDO9z"
local CHECK_INTERVAL = 1
local HEARTBEAT_INTERVAL = 10
local DISCORD_UPDATE_INTERVAL = 300

-- Session and Cache
local Cache = {
    sessionId = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999)),
    updateCounter = 0,
    lastHeartbeat = 0,
    lastDiscordUpdate = 0,
    currentWeather = "None",
    weatherDuration = 0,
    
    -- Stock caches
    seeds = {}, gear = {}, event = {}, cosmetic = {}, nightevent = {}, honeyevent = {},
    eggs = {}
}

-- UI element patterns to ignore
local IGNORE_PATTERNS = {
    "_padding", "padding", "uilistlayout", "uigridlayout", "uipadding", 
    "uicorner", "uistroke", "uigradient", "uiaspectratioconstraint"
}

-- Check if item should be ignored
local function shouldIgnoreItem(itemName)
    local lowerName = string.lower(itemName)
    for _, pattern in ipairs(IGNORE_PATTERNS) do
        if lowerName:match(pattern) then return true end
    end
    return false
end

-- Discord notification
local function sendToDiscord(content, isError)
    pcall(function()
        local message = {
            content = isError and "💥 **ERROR**" or "📊 **UPDATE**",
            embeds = {{
                description = content,
                color = isError and 16711680 or 65280,
                footer = {text = "Session: " .. Cache.sessionId},
                timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
            }}
        }
        request({
            Url = DISCORD_WEBHOOK,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = game:GetService("HttpService"):JSONEncode(message)
        })
    end)
end

-- AUTO-DELETE function
local function autoDeleteOnCrash()
    pcall(function()
        local deleteData = {
            action = "DELETE_ALL",
            sessionId = Cache.sessionId,
            playerName = game.Players.LocalPlayer.Name,
            timestamp = os.time()
        }
        
        request({
            Url = DELETE_ENDPOINT,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = API_KEY,
                ["X-Session-ID"] = Cache.sessionId
            },
            Body = game:GetService("HttpService"):JSONEncode(deleteData)
        })
        
        sendToDiscord("🗑️ Auto-delete triggered - Data removed from API", true)
    end)
end

-- COLLECT ALL EGGS - REAL-TIME UPDATES
local function collectEggData()
    local eggs = {}
    local eggCounts = {}
    
    local success, result = pcall(function()
        local NPCs = workspace:FindFirstChild("NPCS")
        if not NPCs then return {} end
        
        local PetStand = NPCs:FindFirstChild("Pet Stand")
        if not PetStand then return {} end
        
        -- Try ALL possible egg location folder names
        local possibleNames = {
            "EggLocations", "Egg Locations", "Eggs", "EggLocation", 
            "Egg_Locations", "EggModels", "Egg Models", "PetEggs"
        }
        
        local EggLocations = nil
        for _, name in ipairs(possibleNames) do
            EggLocations = PetStand:FindFirstChild(name)
            if EggLocations then
                break
            end
        end
        
        if not EggLocations then return {} end
        
        -- Count EVERY model in the egg folder (no filtering)
        for _, eggModel in pairs(EggLocations:GetChildren()) do
            local eggName = eggModel.Name
            eggCounts[eggName] = (eggCounts[eggName] or 0) + 1
        end
        
        -- Convert ALL eggs to array format
        for eggName, count in pairs(eggCounts) do
            table.insert(eggs, {name = eggName, quantity = count})
        end
        
        return eggs
    end)
    
    return (success and result) or {}
end

-- CLEAN STOCK GETTER
local function getStock(item, shopName)
    local shopUI = game.Players.LocalPlayer.PlayerGui:FindFirstChild(shopName)
    if not shopUI then return "0" end

    for _, obj in ipairs(shopUI:GetDescendants()) do
        if obj:IsA("Frame") and obj.Name == item then
            for _, desc in ipairs(obj:GetDescendants()) do
                if desc:IsA("TextLabel") and (desc.Name == "Stock_Text" or desc.Name == "STOCK_TEXT") then
                    return desc.Text:match("%d+") or "0"
                end
            end
        end
    end
    return "0"
end

-- CLEAN ITEM GETTER
local function getAvailableItems(shopName)
    local shopUI = game.Players.LocalPlayer.PlayerGui:FindFirstChild(shopName)
    if not shopUI then return {} end

    local scrollFrame
    if shopUI:FindFirstChild("Frame") and shopUI.Frame:FindFirstChild("ScrollingFrame") then
        scrollFrame = shopUI.Frame.ScrollingFrame
    else
        for _, child in pairs(shopUI:GetDescendants()) do
            if child:IsA("ScrollingFrame") or child.Name == "ContentFrame" then
                scrollFrame = child
                break
            end
        end
    end
    if not scrollFrame then return {} end

    local names = {}
    
    -- Special handling for cosmetic shop
    if shopName == "CosmeticShop_UI" then
        for _, segment in pairs(scrollFrame:GetChildren()) do
            if segment:IsA("Frame") and (segment.Name == "TopSegment" or segment.Name == "BottomSegment") then
                for _, item in pairs(segment:GetChildren()) do
                    if item:IsA("Frame") and not shouldIgnoreItem(item.Name) then
                        table.insert(names, item.Name)
                    end
                end
            end
        end
    else
        for _, item in pairs(scrollFrame:GetChildren()) do
            if item:IsA("Frame") and not shouldIgnoreItem(item.Name) then
                table.insert(names, item.Name)
            end
        end
    end
    
    return names
end

-- CLEAN HONEY EVENT COLLECTION
local function collectHoneyEventData()
    local success, honeyEventNames = pcall(function() 
        return getAvailableItems("HoneyEventShop_UI") 
    end)
    
    if success and #honeyEventNames > 0 then
        local data = {}
        for _, name in ipairs(honeyEventNames) do
            data[name] = getStock(name, "HoneyEventShop_UI")
        end
        return data
    end
    
    -- Alternative method
    local success2, result = pcall(function()
        local shopUI = game.Players.LocalPlayer.PlayerGui:FindFirstChild("HoneyEventShop_UI")
        if not shopUI then return {} end
        
        local data = {}
        for _, obj in ipairs(shopUI:GetDescendants()) do
            if obj:IsA("Frame") and not shouldIgnoreItem(obj.Name) then
                for _, child in ipairs(obj:GetDescendants()) do
                    if child:IsA("TextLabel") and child.Name == "Stock_Text" then
                        data[obj.Name] = tostring(tonumber(child.Text:match("%d+")) or 0)
                        break
                    end
                end
            end
        end
        return data
    end)
    
    return (success2 and result) or {}
end

-- COLLECT ALL DATA - FIXED TO ALWAYS UPDATE EGGS
local function collectAllData()
    -- ALWAYS collect fresh egg data every time
    local freshEggs = collectEggData()
    
    local data = {
        sessionId = Cache.sessionId,
        timestamp = os.time(),
        updateNumber = Cache.updateCounter + 1,
        playerName = game.Players.LocalPlayer.Name,
        userId = game.Players.LocalPlayer.UserId,
        
        weather = {
            type = Cache.currentWeather,
            duration = Cache.weatherDuration
        },
        
        eggs = freshEggs,  -- ALWAYS use fresh egg data
        seeds = {}, gear = {}, event = {}, cosmetic = {}, nightevent = {}, honeyevent = {}
    }
    
    -- Collect shop data
    local shops = {
        {name = "seeds", ui = "Seed_Shop"},
        {name = "gear", ui = "Gear_Shop"},
        {name = "event", ui = "EventShop_UI"},
        {name = "cosmetic", ui = "CosmeticShop_UI"},
        {name = "nightevent", ui = "NightEventShop_UI"}
    }
    
    for _, shop in ipairs(shops) do
        local items = getAvailableItems(shop.ui)
        for _, item in ipairs(items) do
            data[shop.name][item] = getStock(item, shop.ui)
        end
    end
    
    data.honeyevent = collectHoneyEventData()
    
    return data
end

-- SEND TO API
local function sendToAPI(data)
    local success = pcall(function()
        Cache.updateCounter = Cache.updateCounter + 1
        data.updateNumber = Cache.updateCounter
        
        local jsonStr = game:GetService("HttpService"):JSONEncode(data)
        
        request({
            Url = API_ENDPOINT .. "?session=" .. Cache.sessionId .. "&t=" .. os.time(),
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = API_KEY,
                ["Cache-Control"] = "no-cache, no-store, must-revalidate",
                ["X-Session-ID"] = Cache.sessionId,
                ["X-Update-Number"] = tostring(Cache.updateCounter)
            },
            Body = jsonStr
        })
    end)
    
    return success
end

-- HEARTBEAT
local function sendHeartbeat()
    pcall(function()
        request({
            Url = API_ENDPOINT .. "/heartbeat",
            Method = "POST",
            Headers = {
                ["Authorization"] = API_KEY,
                ["X-Session-ID"] = Cache.sessionId
            },
            Body = game:GetService("HttpService"):JSONEncode({
                sessionId = Cache.sessionId,
                status = "ALIVE",
                timestamp = os.time()
            })
        })
    end)
end

-- CHANGE DETECTION - FIXED EGG COMPARISON
local function hasChanges(oldData, newData)
    -- Weather check
    if oldData.weather.type ~= newData.weather.type then return true end
    
    -- Egg check - compare all eggs properly
    if #oldData.eggs ~= #newData.eggs then 
        print("🥚 Egg count changed: " .. #oldData.eggs .. " -> " .. #newData.eggs)
        return true 
    end
    
    -- Create egg lookup tables for proper comparison
    local oldEggLookup = {}
    for _, egg in ipairs(oldData.eggs) do
        oldEggLookup[egg.name] = egg.quantity
    end
    
    local newEggLookup = {}
    for _, egg in ipairs(newData.eggs) do
        newEggLookup[egg.name] = egg.quantity
    end
    
    -- Check for egg changes
    for eggName, newQuantity in pairs(newEggLookup) do
        local oldQuantity = oldEggLookup[eggName] or 0
        if oldQuantity ~= newQuantity then
            print("🥚 Egg change: " .. eggName .. " changed from " .. oldQuantity .. " to " .. newQuantity)
            return true
        end
    end
    
    -- Check for removed eggs
    for eggName, oldQuantity in pairs(oldEggLookup) do
        if not newEggLookup[eggName] then
            print("🥚 Egg removed: " .. eggName)
            return true
        end
    end
    
    -- Check all shops
    local shopTypes = {"seeds", "gear", "event", "cosmetic", "nightevent", "honeyevent"}
    for _, shopType in ipairs(shopTypes) do
        for itemName, newStock in pairs(newData[shopType]) do
            if oldData[shopType][itemName] ~= newStock then return true end
        end
    end
    
    return false
end

-- SETUP CRASH DETECTION - CLIENT-SIDE ONLY
local function setupCrashDetection()
    game.Players.LocalPlayer.AncestryChanged:Connect(function()
        if not game.Players.LocalPlayer.Parent then
            autoDeleteOnCrash()
        end
    end)
    
    local UserInputService = game:GetService("UserInputService")
    UserInputService.WindowFocusReleased:Connect(function()
        sendHeartbeat()
    end)
end

-- ANTI-AFK
local function setupAntiAFK()
    local VirtualUser = game:GetService("VirtualUser")
    game.Players.LocalPlayer.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end

-- WEATHER LISTENER
local function setupWeatherListener()
    pcall(function()
        game.ReplicatedStorage.GameEvents.WeatherEventStarted.OnClientEvent:Connect(function(weatherType, duration)
            Cache.currentWeather = weatherType or "None"
            Cache.weatherDuration = duration or 0
        end)
    end)
end

-- MAIN FUNCTION
local function startCleanMonitoring()
    print("🔥 Clean Monitor Started | Session: " .. Cache.sessionId)
    print("🥚 REAL-TIME EGG UPDATES - Eggs refresh every second")
    
    sendToDiscord("🔥 Clean monitor started - REAL-TIME EGG UPDATES\nSession: " .. Cache.sessionId, false)
    
    setupAntiAFK()
    setupWeatherListener()
    setupCrashDetection()
    
    -- Initial data collection
    local initialData = collectAllData()
    
    -- Store initial cache
    Cache.seeds = initialData.seeds
    Cache.gear = initialData.gear
    Cache.event = initialData.event
    Cache.cosmetic = initialData.cosmetic
    Cache.nightevent = initialData.nightevent
    Cache.honeyevent = initialData.honeyevent
    Cache.eggs = initialData.eggs  -- Store initial eggs
    
    Cache.lastHeartbeat = os.time()
    Cache.lastDiscordUpdate = os.time()
    
    sendToAPI(initialData)
    sendHeartbeat()
    
    print("🚀 Starting main monitoring loop with real-time egg updates...")
    
    -- MAIN LOOP - EGGS UPDATE EVERY SECOND
    while true do
        local success, currentData = pcall(collectAllData)
        
        if success then
            local currentTime = os.time()
            
            -- Create old data for comparison
            local oldData = {
                weather = {type = Cache.currentWeather, duration = Cache.weatherDuration},
                eggs = Cache.eggs,  -- Use cached eggs for comparison
                seeds = Cache.seeds, gear = Cache.gear, event = Cache.event,
                cosmetic = Cache.cosmetic, nightevent = Cache.nightevent, honeyevent = Cache.honeyevent
            }
            
            -- Check for changes
            local changes = hasChanges(oldData, currentData)
            
            -- Send update every second (eggs are always fresh)
            if sendToAPI(currentData) then
                -- Update cache with new data
                Cache.seeds = currentData.seeds
                Cache.gear = currentData.gear
                Cache.event = currentData.event
                Cache.cosmetic = currentData.cosmetic
                Cache.nightevent = currentData.nightevent
                Cache.honeyevent = currentData.honeyevent
                Cache.eggs = currentData.eggs  -- Update egg cache
                
                -- Log changes
                if changes then
                    print("📊 Update #" .. Cache.updateCounter .. " (Changes detected)")
                    
                    -- Log egg count for debugging
                    local eggCount = #currentData.eggs
                    if eggCount > 0 then
                        print("🥚 Current eggs in API: " .. eggCount .. " types")
                    end
                end
            end
            
            -- Heartbeat every 10 seconds
            if (currentTime - Cache.lastHeartbeat) >= HEARTBEAT_INTERVAL then
                sendHeartbeat()
                Cache.lastHeartbeat = currentTime
            end
            
            -- Discord update every 5 minutes
            if (currentTime - Cache.lastDiscordUpdate) >= DISCORD_UPDATE_INTERVAL then
                local eggCount = #Cache.eggs
                sendToDiscord("📊 Monitor running - Update #" .. Cache.updateCounter .. "\n🥚 Tracking " .. eggCount .. " egg types", false)
                Cache.lastDiscordUpdate = currentTime
            end
            
        else
            print("❌ Error in main loop:", currentData)
            autoDeleteOnCrash()
            break
        end
        
        wait(CHECK_INTERVAL)
    end
end

-- START CLEAN MONITORING
startCleanMonitoring()
