-- CLEAN REAL-TIME MONITOR - MINIMAL LOGGING VERSION
print("🔥 Starting Clean Monitor...")

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
    seeds = {}, gear = {}, event = {}, cosmetic = {}, nightevent = {}, honeyevent = {}, eggs = {}
}

-- UI element patterns to ignore
local IGNORE_PATTERNS = {
    "_padding", "padding", "uilistlayout", "uigridlayout", "uipadding", 
    "uicorner", "uistroke", "uigradient", "uiaspectratioconstraint"
}

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
        request({
            Url = DELETE_ENDPOINT,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = API_KEY,
                ["X-Session-ID"] = Cache.sessionId
            },
            Body = game:GetService("HttpService"):JSONEncode({
                action = "DELETE_ALL",
                sessionId = Cache.sessionId,
                playerName = game.Players.LocalPlayer.Name,
                timestamp = os.time()
            })
        })
    end)
end

-- COLLECT EGGS - SIMPLE & FAST
local function collectEggData()
    local success, result = pcall(function()
        local NPCs = workspace:FindFirstChild("NPCS")
        if not NPCs then return {} end
        
        local PetStand = NPCs:FindFirstChild("Pet Stand")
        if not PetStand then return {} end
        
        local EggLocations = PetStand:FindFirstChild("EggLocations") or 
                            PetStand:FindFirstChild("Egg Locations") or 
                            PetStand:FindFirstChild("Eggs")
        if not EggLocations then return {} end
        
        local eggCounts = {}
        for _, eggModel in pairs(EggLocations:GetChildren()) do
            local eggName = eggModel.Name
            eggCounts[eggName] = (eggCounts[eggName] or 0) + 1
        end
        
        local eggs = {}
        for eggName, count in pairs(eggCounts) do
            table.insert(eggs, {name = eggName, quantity = count})
        end
        
        return eggs
    end)
    
    return (success and result) or {}
end

-- GET STOCK
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

-- GET ITEMS
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

-- HONEY EVENT DATA
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

-- COLLECT ALL DATA WITH MAIN LOGGING
local function collectAllData()
    local freshEggs = collectEggData()
    
    local data = {
        sessionId = Cache.sessionId,
        timestamp = os.time(),
        updateNumber = Cache.updateCounter + 1,
        playerName = game.Players.LocalPlayer.Name,
        userId = game.Players.LocalPlayer.UserId,
        weather = {type = Cache.currentWeather, duration = Cache.weatherDuration},
        eggs = freshEggs,
        seeds = {}, gear = {}, event = {}, cosmetic = {}, nightevent = {}, honeyevent = {}
    }
    
    -- MAIN LOGGING - WHAT WE FOUND
    local foundData = {}
    
    -- Check eggs
    if #freshEggs > 0 then
        foundData.eggs = #freshEggs .. " types"
    else
        foundData.eggs = "NONE"
    end
    
    -- Check shops
    local shops = {
        {name = "seeds", ui = "Seed_Shop", display = "Seeds"},
        {name = "gear", ui = "Gear_Shop", display = "Gear"},
        {name = "event", ui = "EventShop_UI", display = "Event"},
        {name = "cosmetic", ui = "CosmeticShop_UI", display = "Cosmetic"},
        {name = "nightevent", ui = "NightEventShop_UI", display = "Night"}
    }
    
    for _, shop in ipairs(shops) do
        local items = getAvailableItems(shop.ui)
        if #items > 0 then
            for _, item in ipairs(items) do
                data[shop.name][item] = getStock(item, shop.ui)
            end
            foundData[shop.display] = #items .. " items"
        else
            foundData[shop.display] = "NONE"
        end
    end
    
    -- Check honey event
    data.honeyevent = collectHoneyEventData()
    local honeyCount = 0
    for _ in pairs(data.honeyevent) do honeyCount = honeyCount + 1 end
    foundData.Honey = honeyCount > 0 and honeyCount .. " items" or "NONE"
    
    -- LOG WHAT WE FOUND
    local logParts = {}
    for shopName, result in pairs(foundData) do
        table.insert(logParts, shopName .. ":" .. result)
    end
    print("📊 DATA FOUND: " .. table.concat(logParts, " | "))
    
    return data
end

-- SEND TO API
local function sendToAPI(data)
    local success = pcall(function()
        Cache.updateCounter = Cache.updateCounter + 1
        data.updateNumber = Cache.updateCounter
        
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
            Body = game:GetService("HttpService"):JSONEncode(data)
        })
    end)
    
    if success then
        print("✅ API UPDATE #" .. Cache.updateCounter)
    else
        print("❌ API FAILED #" .. Cache.updateCounter)
    end
    
    return success
end

-- HEARTBEAT
local function sendHeartbeat()
    pcall(function()
        request({
            Url = API_ENDPOINT .. "/heartbeat",
            Method = "POST",
            Headers = {["Authorization"] = API_KEY, ["X-Session-ID"] = Cache.sessionId},
            Body = game:GetService("HttpService"):JSONEncode({
                sessionId = Cache.sessionId,
                status = "ALIVE",
                timestamp = os.time()
            })
        })
    end)
end

-- CHANGE DETECTION
local function hasChanges(oldData, newData)
    if oldData.weather.type ~= newData.weather.type then return true end
    
    if #oldData.eggs ~= #newData.eggs then return true end
    
    local oldEggLookup = {}
    for _, egg in ipairs(oldData.eggs) do
        oldEggLookup[egg.name] = egg.quantity
    end
    
    for _, egg in ipairs(newData.eggs) do
        if oldEggLookup[egg.name] ~= egg.quantity then return true end
    end
    
    local shopTypes = {"seeds", "gear", "event", "cosmetic", "nightevent", "honeyevent"}
    for _, shopType in ipairs(shopTypes) do
        for itemName, newStock in pairs(newData[shopType]) do
            if oldData[shopType][itemName] ~= newStock then return true end
        end
    end
    
    return false
end

-- SETUP FUNCTIONS
local function setupCrashDetection()
    game.Players.LocalPlayer.AncestryChanged:Connect(function()
        if not game.Players.LocalPlayer.Parent then
            autoDeleteOnCrash()
        end
    end)
end

local function setupAntiAFK()
    local VirtualUser = game:GetService("VirtualUser")
    game.Players.LocalPlayer.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end

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
    print("🔥 MONITOR STARTED | Session: " .. Cache.sessionId)
    
    setupAntiAFK()
    setupWeatherListener()
    setupCrashDetection()
    
    local initialData = collectAllData()
    Cache.seeds = initialData.seeds
    Cache.gear = initialData.gear
    Cache.event = initialData.event
    Cache.cosmetic = initialData.cosmetic
    Cache.nightevent = initialData.nightevent
    Cache.honeyevent = initialData.honeyevent
    Cache.eggs = initialData.eggs
    
    Cache.lastHeartbeat = os.time()
    Cache.lastDiscordUpdate = os.time()
    
    sendToAPI(initialData)
    sendHeartbeat()
    
    print("🚀 MONITORING LOOP STARTED")
    
    -- MAIN LOOP
    while true do
        local success, currentData = pcall(collectAllData)
        
        if success then
            local currentTime = os.time()
            
            local oldData = {
                weather = {type = Cache.currentWeather, duration = Cache.weatherDuration},
                eggs = Cache.eggs,
                seeds = Cache.seeds, gear = Cache.gear, event = Cache.event,
                cosmetic = Cache.cosmetic, nightevent = Cache.nightevent, honeyevent = Cache.honeyevent
            }
            
            local changes = hasChanges(oldData, currentData)
            
            if sendToAPI(currentData) then
                Cache.seeds = currentData.seeds
                Cache.gear = currentData.gear
                Cache.event = currentData.event
                Cache.cosmetic = currentData.cosmetic
                Cache.nightevent = currentData.nightevent
                Cache.honeyevent = currentData.honeyevent
                Cache.eggs = currentData.eggs
                
                if changes then
                    print("🔄 CHANGES DETECTED & SENT")
                end
            end
            
            if (currentTime - Cache.lastHeartbeat) >= HEARTBEAT_INTERVAL then
                sendHeartbeat()
                Cache.lastHeartbeat = currentTime
            end
            
            if (currentTime - Cache.lastDiscordUpdate) >= DISCORD_UPDATE_INTERVAL then
                sendToDiscord("📊 Monitor running - Update #" .. Cache.updateCounter, false)
                Cache.lastDiscordUpdate = currentTime
            end
            
        else
            print("❌ ERROR:", currentData)
            autoDeleteOnCrash()
            break
        end
        
        wait(CHECK_INTERVAL)
    end
end

-- START
startCleanMonitoring()
