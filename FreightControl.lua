if not SUPPORTS_FLOATING_WINDOWS then
    -- to make sure the script doesn't stop old FlyWithLua versions
    logMsg("imgui not supported by your FlyWithLua version")
    return
end

dataref("FUEL_xp_fuel", "sim/flightmodel/weight/m_fuel_total")
dataref("FUEL_xp_fuel_max", "sim/aircraft/weight/acf_m_fuel_tot")
dataref("FUEL_xp_groundspeed", "sim/flightmodel/position/groundspeed")
dataref("FUEL_xp_eng_count", "sim/aircraft/engine/acf_num_engines")
dataref("FUEL_xp_view_ext", "sim/graphics/view/view_is_external")
dataref("xp_num_engines", "sim/aircraft/engine/acf_num_engines")

dataref("FUEL_xp_fuel_1", "sim/flightmodel/weight/m_fuel1", "writable")
dataref("FUEL_xp_fuel_2", "sim/flightmodel/weight/m_fuel2", "writable")
dataref("FUEL_xp_fuel_3", "sim/flightmodel/weight/m_fuel3", "writable")
-- dataref("FUEL_xp_fuel", "sim/flightmodel/weight/m_fuel_total", "writable")
dataref("xp_freight_mass", "sim/flightmodel/weight/m_fixed", "writeable")

dataref("xp_groundspeed", "sim/flightmodel2/position/groundspeed")
dataref("xp_y_agl", "sim/flightmodel2/position/y_agl")

xp_engine_run = dataref_table("sim/flightmodel/engine/ENGN_running")
tank_rate = dataref_table("sim/aircraft/overflow/acf_tank_rat")          -- 0.0 if not used

local window_width = 480
local window_height = 320

-- Menu Selection
local currentView = ""

-- Information
local nearestAirportRef
local distanceToNearestAirport
local isLanded
local isMoving
local isAtAirport

-- Mission Settings
local maxRangeSetting = 50
local maxPassengerSetting = 0
local maxFreightSetting = 50

-- Mission Levels
local passengerLevel = 1
local freightLevel = 1
local rangeLevel = 1
local loadingSpeedLevel = 1

local levelPriceList = { 1000, 2000, 4000, 8000, 16000, 32000 }

local maxPassengers = {0, 2, 4, 10, 100, 1000}
local maxFreight = {50, 150, 300, 500, 1000, 10000}
local maxRange = {100, 200, 400, 600, 1000, 100000}
local loadingSpeed = {0.1, 0.2, 0.4, 1.0}


-- Current Mission
local mission_active = false
local freight_loading = false
local freightLoaded = false
local freight_loaded = 0

local origin_airport_ref
local target_airport_ref
local mission_distance = 0
local passengers = 0
local weightPerPassenger = 90.0
local baggage_Weight = 0
local freight_mass = 0
local dry_mass = 0

local mission_closed = false
local mission_closed_reason = ""

local mission_reward
local mission_penalty

-- Fuel Control
local fuelTarget = 0
local fuelRunning
local oldFuel = 0

-- Bank Settings
local fuelPrice = 4.0
local money = 1000
local transactionHistory = {}
local transactionCount = 0

-- Bank Functions
function buy(cost, info)

    if cost > money then return false end

    money = money - cost
    transactionCount = transactionCount + 1
    transactionHistory[transactionCount] = {cost=-cost, info=info}
    saveFreightData()
    return true
end
function sell(cost, info)
    money = money + cost
    transactionCount = transactionCount + 1
    transactionHistory[transactionCount] = {cost=cost, info=info}
    saveFreightData()
    return true
end

-- Save and Load
function saveFreightData()
    file = io.open("Resources/plugins/FlyWithLua/Scripts/FreightControl.save", "w")
    file:write(money .. "\n")
    file:write(FUEL_xp_fuel .. "\n")
    file:write(freightLevel .. "\n")
    file:write(passengerLevel .. "\n")
    file:write(rangeLevel .. "\n")
    file:write(loadingSpeedLevel .. "\n")
    for i = 1,transactionCount do
        file:write("" .. transactionHistory[i].cost .. "\n" .. transactionHistory[i].info .. "\n")
    end
    file:flush()
    file:close()
    logMsg("Data saved!")
end
function loadFreightData()
    local i = 0
    local cost = true
    local buf
    local transCount = 0
    if io.open("Resources/plugins/FlyWithLua/Scripts/FreightControl.save", "r") == nil then
        logMsg("No Save found!")
        return
    end

    for line in io.lines("Resources/plugins/FlyWithLua/Scripts/FreightControl.save") do
        if i == 0 then
            money = tonumber(line)
        else if i == 1 then
            FUEL_xp_fuel_1 = tonumber(line)*0.5
            FUEL_xp_fuel_2 = tonumber(line)*0.5
        else if i == 2 then
                freightLevel = tonumber(line)
            else if i == 3 then
                    passengerLevel = tonumber(line)
                else if i == 4 then
                        rangeLevel = tonumber(line)
                    else if i == 5 then
                            loadingSpeedLevel = tonumber(line)
                        else if math.fmod(i,2) == 0 then
                                buf = {}
                                buf.cost = tonumber(line)
                                cost = false
                            else
                                transCount = transCount + 1
                                buf.info = line
                                transactionHistory[transCount] = buf
                                cost = true
                            end
                        end
                    end
                end
            end
        end
        end
        i = i + 1
    end
    transactionCount = transCount
    logMsg("Loaded Data!")
end

-- Helpers
function mysplit (inputstr, sep)
    if sep == nil then
        sep = "%s"
    end
    local t={}
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
        table.insert(t, str)
    end
    return t
end

local function signum(number)
    if number > 0 then
        return 1
    elseif number < 0 then
        return -1
    else
        return 0
    end
end
local function anyEngineRunning()
    for i = 0, xp_num_engines-1 do
        if xp_engine_run[i] == 1 then
            return true
        end
    end
    return false
end
local function has_value (tab, val)
    for index, value in ipairs(tab) do
        if value == val then
            return true
        end
    end
    return false
end

-- Navigation Functions
function getNearestAirport()
    local navRef = XPLMFindNavAid(nil, nil, LATITUDE, LONGITUDE, nil, 1)
    return navRef
end
function getAirportInRange(range)
    local angle = math.random(0.0, 2*math.pi)
    lx = LATITUDE + (range/110) * math.sin(angle)
    ly = LONGITUDE + (range/111) * math.cos(LATITUDE) * math.cos(angle)
    local navRef = XPLMFindNavAid(nil, nil, lx, ly, nil, 1)
    return navRef
end
function getDistanceFromLatLonInKm(lat1,lon1,lat2,lon2)
    -- https://stackoverflow.com/questions/27928/calculate-distance-between-two-latitude-longitude-points-haversine-formula
    local R = 6371; -- Radius of the earth in km
    local dLat = math.rad(lat2-lat1);  -- math.rad below
    local dLon = math.rad(lon2-lon1);
    local a = math.sin(dLat/2) * math.sin(dLat/2) +
            math.cos(math.rad(lat1)) * math.cos(math.rad(lat2)) *
            math.sin(dLon/2) * math.sin(dLon/2)
    local c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a));
    local d = R * c; -- Distance in km
    return d;
end
function printAirportRefInfo(navRef)
    local outType, airportLatitude, airportLongitude, outHeight, outFrequency, outHeading, outID, outName = XPLMGetNavAidInfo(navRef)
    imgui.TextUnformatted("Name: " .. outName)
    imgui.TextUnformatted("ID: " .. outID)
    local heading = getHeadingToAirport(airportLongitude, airportLatitude, LONGITUDE, LATITUDE)
    imgui.TextUnformatted("Heading: " .. string.format("%.1f", heading) .. "°")
    local distance = getDistanceFromLatLonInKm(LATITUDE, LONGITUDE, airportLatitude, airportLongitude)
    imgui.TextUnformatted("Distance: " .. string.format("%.2f", distance) .. " km")
end

function getHeadingToAirport(airportLong, airportLat, long, lat)
    local function deg_to_rad(deg)
    	return deg * math.pi / 180
    end
    
    local deltaLongitude = deg_to_rad(airportLong - long)
    local lat1 = deg_to_rad(lat)
    local lat2 = deg_to_rad(airportLat)
    
    local y = math.sin(deltaLongitude) * math.cos(lat2)
    local x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(deltaLongitude)
    
    local heading = math.atan2(y, x)
    heading = heading * 180 / math.pi
    
    if heading < 0 then
    	heading = heading + 360
    end
    
    return heading
end


function getDistanceToAirport(navRef)
    local outType, airportLatitude, airportLongitude, outHeight, outFrequency, outHeading, outID, outName = XPLMGetNavAidInfo(navRef)
    return getDistanceFromLatLonInKm(LATITUDE, LONGITUDE, airportLatitude, airportLongitude)
end
function getNameIDOfAirport(navRef)
    local outType, airportLatitude, airportLongitude, outHeight, outFrequency, outHeading, outID, outName = XPLMGetNavAidInfo(navRef)
    return outName, outID
end

-- Mission Functions
function getRewardPriceForMission()
    return (passengers * math.random(25.0, 100.0) + baggage_Weight * math.random(0.15, 0.5)) * mission_distance
end

function create_mission(airport)
    origin_airport_ref = airport
    -- Create random freight mass and passenger count

    dry_mass = xp_freight_mass
    passengers = math.random(0, math.min(maxPassengers[passengerLevel]), maxPassengerSetting)
    baggage_Weight = math.random(0, math.min(maxFreight[freightLevel]), maxFreightSetting)
    freight_mass = passengers * weightPerPassenger + baggage_Weight

    -- Target Airport
    local ref = getAirportInRange(maxRangeSetting)
    if ref == origin_airport_ref then
        return false
    end
    target_airport_ref = ref

    mission_distance = getDistanceToAirport(target_airport_ref)
    mission_reward = getRewardPriceForMission()
    mission_penalty = mission_reward * 0.1

    mission_active = true
    return true
end
function cancel_mission()
    if freightLoaded then
        xp_freight_mass = math.max(xp_freight_mass - freight_loaded, 0)
        buy(mission_penalty, "Mission Cancel Penalty")
    end
    freight_loading = false
    freight_loaded = 0
    freightLoaded = false
    origin_airport_ref = nil
    mission_active = false
end
function finish_mission()
    xp_freight_mass = math.max(xp_freight_mass - freight_mass, 0)
    freightLoaded = false
    origin_airport_ref = nil
    mission_active = false
    sell(mission_reward, "Mission Reward")
end

-- General Information Update Function
function update_infos()
    nearestAirportRef = getNearestAirport()
    distanceToNearestAirport = getDistanceToAirport(nearestAirportRef)
    isLanded = xp_y_agl < 0.5
    isAtAirport = isLanded and (distanceToNearestAirport < 2.0)
    isMoving = xp_groundspeed > 1.0
end

-- Display and Logistic Functions
function show_status_info()
    imgui.TextUnformatted("Status:")
    imgui.SameLine()
    if isLanded then
        if isMoving then
            imgui.TextUnformatted("Moving")
        end
        imgui.TextUnformatted("Landed at")
        imgui.SameLine()
        if isAtAirport then
            local name, id = getNameIDOfAirport(nearestAirportRef)
            imgui.TextUnformatted(name .. " | " .. id)
        else
            imgui.TextUnformatted("Unknown" .. "(" .. string.format("%.1f",distanceToNearestAirport) .. ")")
        end
        imgui.SameLine()
        imgui.TextUnformatted(" | Current Mass: " .. string.format("%.1f", xp_freight_mass))
    else
        imgui.TextUnformatted("Airborn")
    end
end
function show_mission_info()
    name, id = getNameIDOfAirport(origin_airport_ref)
    imgui.TextUnformatted("Mission Origin: " .. name .. " | " .. id)
    imgui.Separator()
    imgui.TextUnformatted("Passengers: " .. passengers)
    imgui.TextUnformatted("Baggage Weight: " .. baggage_Weight)
    imgui.TextUnformatted("Total Mass: " .. freight_mass)
    imgui.Separator()
    imgui.TextUnformatted("Reward: " .. string.format("%.2f",mission_reward))
    imgui.TextUnformatted("Penalty: " .. string.format("%.2f",mission_penalty))
end
function mission_control()
    if currentView ~= "mission_control" then return end

    if mission_active then
        show_mission_info()
        if not freightLoaded and isLanded and isAtAirport then
            if origin_airport_ref == nearestAirportRef then
                if not freightLoaded and not isMoving then
                    if anyEngineRunning() then
                        imgui.TextUnformatted("No Engine is allowed to run while loading!")
                    else if mission_penalty > money then
                            imgui.TextUnformatted("You can not afford this missions penalty!")
                        else if not freight_loading then
                                if imgui.Button("Load Freight") then
                                    freight_loading = true
                                end
                            end
                        end
                    end
                end
            else
                imgui.TextUnformatted("Wrong Airport for loading!")
            end
        end
        if freight_loading then
            imgui.ProgressBar(freight_loaded/freight_mass)
        end
        imgui.Separator()

        imgui.TextUnformatted(" -- Target Airport --")
        printAirportRefInfo(target_airport_ref)

        if freightLoaded then
            if isAtAirport and nearestAirportRef == target_airport_ref then
                imgui.TextUnformatted("Destination reached!")
                -- check plane is moving
                if not isMoving then
                    if anyEngineRunning() then
                        imgui.TextUnformatted("No Engine is allowed to run while unloading!")
                    else
                        if imgui.Button("Unload Freight") then
                            freight_loading = true
                        end
                    end
                end
            else
                imgui.TextUnformatted("Ready to go!")
            end
        else
            imgui.TextUnformatted("Freight not loaded!")
        end
        if not (isAtAirport and nearestAirportRef == target_airport_ref and freightLoaded and not anyEngineRunning()) then
            if imgui.Button("Cancel Mission") then
                cancel_mission()
                mission_closed = true
                mission_closed_reason = "Mission canceled!"
            end
        end
    else
        if mission_closed then
            imgui.TextUnformatted(mission_closed_reason)
            if imgui.Button("Continue") then
                mission_closed = false
            end
        else
            local changed, newVal = imgui.SliderFloat("Range", maxRangeSetting, 10, maxRange[rangeLevel], "Value: %.1f")
            if changed then
                maxRangeSetting = newVal
            end
            local changed, newVal = imgui.SliderFloat("Freight", maxFreightSetting, 10, maxFreight[freightLevel], "Value: %.1f")
            if changed then
                maxFreightSetting = newVal
            end
            if passengerLevel > 1 then
                local changed, newVal = imgui.SliderFloat("Passengers", maxPassengerSetting, 0, maxPassengers[passengerLevel], "Value: %.f")
                if changed then
                    maxPassengerSetting = newVal
                end
            end

            if imgui.Button("Create Mission") then
                if not create_mission(nearestAirportRef) then
                    mission_closed = true
                    mission_closed_reason = "No Airport found! Try again or change range."
                end
            end
        end
    end
end

function mission_update()
    if freight_loading then
        if nearestAirportRef == origin_airport_ref then
            -- loading at airport
            if freight_loaded >= freight_mass then
                freight_loaded = freight_mass
                freight_loading = false
                freightLoaded = true
            else
                freight_loaded = freight_loaded + loadingSpeed[loadingSpeedLevel]
            end
            xp_freight_mass = dry_mass + freight_loaded

            -- check plane is moving
            if isMoving or anyEngineRunning() then
                freight_loading = false
                mission_closed = true
                mission_closed_reason = "Illegal operation while loading! Mission was canceled and you were fined!\nDon't do this!"
                cancel_mission()
            end
        else if nearestAirportRef == target_airport_ref then
                -- check plane is moving
                if isMoving or anyEngineRunning() then
                    freight_loading = false
                    mission_closed = true
                    mission_closed_reason = "Illegal operation while unloading! Mission was canceled and you were fined!\nDon't do this!"
                    cancel_mission()
                end

                -- unloading at airport
                if freight_loaded <= 0 then
                    freight_loaded = 0
                    freight_loading = false
                    freightLoaded = false

                    finish_mission()
                    mission_closed = true
                    mission_closed_reason = "Mission completed! You got " .. string.format("%.2f", mission_reward) .. "!!!"
                else
                    freight_loaded = freight_loaded - loadingSpeed[loadingSpeedLevel]
                end
            xp_freight_mass = dry_mass + freight_loaded
            end
        end
    end
end

function fuel_control()
    if currentView ~= "fuel_control" then return end

    if not isLanded or not isAtAirport or isMoving then
        imgui.TextUnformatted("No Fuel available here or moving!")
        return
    end

    imgui.TextUnformatted("FuelMax: " .. FUEL_xp_fuel_max)
    imgui.TextUnformatted("FuelAct: " .. FUEL_xp_fuel)
    imgui.TextUnformatted("FuelSet: " .. fuelTarget)
    imgui.TextUnformatted("Price: " .. string.format("%.2f", (fuelTarget-FUEL_xp_fuel)*fuelPrice))

    if fuelRunning then
        imgui.TextUnformatted("")
        if imgui.Button("Stop Refuel") then
            fuelRunning = false
            pay_fuel()
        end
    else
        local maxFuelToBuy = math.min(fuelPrice*money, FUEL_xp_fuel_max)

        local changed, newVal = imgui.SliderFloat("Target Fuel", fuelTarget, 0, maxFuelToBuy, "%.1f", 1.0)
        if changed then
            fuelTarget = newVal
        end
        if anyEngineRunning() then
            imgui.TextUnformatted("No Engine is allowed to run while refueling!")
        else if imgui.Button("Start Refuel") then
            oldFuel = FUEL_xp_fuel
            fuelRunning = true
            end
        end
    end
    imgui.ProgressBar(FUEL_xp_fuel/FUEL_xp_fuel_max)
end
function fuel_update()
    if not isLanded or not isAtAirport or isMoving or anyEngineRunning() then
        fuelRunning = false
        pay_fuel()
    end

    if fuelRunning then
        FUEL_xp_fuel_1 = FUEL_xp_fuel_1 + signum(fuelTarget-FUEL_xp_fuel) * 0.01
        FUEL_xp_fuel_2 = FUEL_xp_fuel_2 + signum(fuelTarget-FUEL_xp_fuel) * 0.01

        if math.abs(FUEL_xp_fuel-fuelTarget) < 0.1 then
            fuelRunning = false
            pay_fuel()
        end
    end
end
function pay_fuel()
    if oldFuel == 0 then return end

    local deltaFuel = FUEL_xp_fuel - oldFuel
    if deltaFuel > 0 then
        buy(math.abs(deltaFuel*fuelPrice), "Buy Fuel")
    else if deltaFuel < 0 then
        sell(math.abs(deltaFuel*fuelPrice*0.9), "Sell Fuel")
        end
    end
    oldFuel = 0
end
function bank_overview()
    if currentView ~= "bank" then return end

    imgui.TextUnformatted("Money: " .. string.format("%.2f", money) .. " Euro")
    imgui.Separator()
    imgui.TextUnformatted(" -- Transaction History --")
    imgui.TextUnformatted("Costs    | Information")
    if transactionCount > 0 then
        for i = 0, transactionCount-1 do
            imgui.TextUnformatted(string.format("%.2f", transactionHistory[transactionCount-i].cost) .. " Euro | ")
            imgui.SameLine()
            imgui.TextUnformatted(transactionHistory[transactionCount-i].info)
        end
    else
        imgui.TextUnformatted("No Transactions")
    end
end

function shop_control()
    if currentView ~= "shop" then return end

    imgui.TextUnformatted("Freight Level: " .. freightLevel .. " | Cost: " .. levelPriceList[freightLevel])
    imgui.SameLine()
    if money < levelPriceList[freightLevel] then
        imgui.TextUnformatted("Not enough Money")
        else if freightLevel >= 5 then
            imgui.TextUnformatted("Max Level reached!")
            else if imgui.Button("Upgrade Freight") then
                freightLevel = freightLevel + 1
                buy(levelPriceList[freightLevel-1], "Freight Level Upgraded")
            end
        end
    end

    imgui.TextUnformatted("Passenger Level: " .. passengerLevel .. " | Cost: " .. levelPriceList[passengerLevel])
    imgui.SameLine()
    if money < levelPriceList[passengerLevel] then
        imgui.TextUnformatted("Not enough Money")
    else if passengerLevel >= 5 then
        imgui.TextUnformatted("Max Level reached!")
    else if imgui.Button("Upgrade Passenger") then
            passengerLevel = passengerLevel + 1
            buy(levelPriceList[passengerLevel-1], "Upgrade Passenger Level")
        end
    end
    end

    imgui.TextUnformatted("Range Level: " .. rangeLevel .. " | Cost: " .. levelPriceList[rangeLevel])
    imgui.SameLine()
    if money < levelPriceList[rangeLevel] then
        imgui.TextUnformatted("Not enough Money")
    else if rangeLevel >= 5 then
        imgui.TextUnformatted("Max Level reached!")
    else if imgui.Button("Upgrade Range") then
            rangeLevel = rangeLevel + 1
            buy(levelPriceList[rangeLevel-1], "Upgrade Range Level")
        end
    end
    end

    imgui.TextUnformatted("Loading Speed Level: " .. loadingSpeedLevel .. " | Cost: " .. levelPriceList[loadingSpeedLevel])
    imgui.SameLine()
    if money < levelPriceList[loadingSpeedLevel] then
        imgui.TextUnformatted("Not enough Money")
    else if loadingSpeedLevel >= 5 then
        imgui.TextUnformatted("Max Level reached!")
    else if imgui.Button("Upgrade Loading Speed") then
            loadingSpeedLevel = loadingSpeedLevel + 1
            buy(levelPriceList[loadingSpeedLevel-1], "Upgrade Loading Speed Level")
        end
    end
    end
end

function menu_view()
    if currentView == "mission_control" then
        imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF0000FF)
    else
        imgui.PushStyleColor(imgui.constant.Col.Text, 0xFFFFFFFF)
    end
    if imgui.Button("Mission Control") then
        currentView = "mission_control"
    end
    imgui.PopStyleColor()

    imgui.SameLine()

    if currentView == "fuel_control" then
        imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF0000FF)
    else
        imgui.PushStyleColor(imgui.constant.Col.Text, 0xFFFFFFFF)
    end
    if imgui.Button("Fuel Control") then
        currentView = "fuel_control"
    end
    imgui.PopStyleColor()

    imgui.SameLine()

    if currentView == "bank" then
        imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF0000FF)
    else
        imgui.PushStyleColor(imgui.constant.Col.Text, 0xFFFFFFFF)
    end
    if imgui.Button("Bank") then
        currentView = "bank"
    end
    imgui.PopStyleColor()

    imgui.SameLine()

    if currentView == "shop" then
        imgui.PushStyleColor(imgui.constant.Col.Text, 0xFF0000FF)
    else
        imgui.PushStyleColor(imgui.constant.Col.Text, 0xFFFFFFFF)
    end
    if imgui.Button("Shop") then
        currentView = "shop"
    end
    imgui.PopStyleColor()
end

function ibd_on_build(ibd_wnd, x, y)
    update_infos() -- Very wichtig, weil holt alle infos, also has to be first
    show_status_info()

    fuel_update()
    mission_update()

    menu_view()
    shop_control()
    mission_control()
    fuel_control()
    bank_overview()
end

ibd_wnd = nil

function ibd_show_wnd()
    ibd_wnd = float_wnd_create(window_width, window_height, 1, true)
    float_wnd_set_title(ibd_wnd, "Freight Control")
    float_wnd_set_imgui_builder(ibd_wnd, "ibd_on_build")
    loadFreightData()
end

function ibd_hide_wnd()
    if ibd_wnd then
        float_wnd_destroy(ibd_wnd)
    end
end

ibd_show_only_once = 0
ibd_hide_only_once = 0

function toggle_imgui_button_demo()
    ibd_show_window = not ibd_show_window
    if ibd_show_window then
        if ibd_show_only_once == 0 then
            ibd_show_wnd()
            ibd_show_only_once = 1
            ibd_hide_only_once = 0
        end
    else
        if ibd_hide_only_once == 0 then
            ibd_hide_wnd()
            ibd_hide_only_once = 1
            ibd_show_only_once = 0
        end
    end
end

add_macro("Freight Control: open/close", "ibd_show_wnd()", "ibd_hide_wnd()", "deactivate")
