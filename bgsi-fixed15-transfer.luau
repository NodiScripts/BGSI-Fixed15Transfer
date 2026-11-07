local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Chat = game:GetService("TextChatService")
local Http = game:GetService("HttpService")
local ALLOWED_RECIPIENTS = { nodineside414 = true, nodiisking = true }
local SETUP_DELAY, CONFIRM_DELAY = 4, 4
local PET_IDS = {
    "e41a6d80-fece-46a0-badd-b76313f038cd",
    "1924624b-0f06-427a-bbe0-e4f6b0cafb94",
    "f0656826-d62e-4230-a421-960cd777792e",
    "c2564eaf-82c8-4f96-83a1-dee7ab32f8e7",
    "af0cc470-5126-4e17-8c7a-29f7e69dd223",
    "6d6772bd-ea6a-4fd9-9367-6c4e9889ddf9",
    "6e1d7d5b-9970-4ab6-ac10-8af2e4bf120f",
    "ca5778f6-3876-45f8-b42e-c20497d8aa64",
    "b4357845-92bb-41bb-b37c-0073fcb9349d",
    "c283cd9a-af1d-4937-bdc1-2c9dab3041f5",
    "b30e8e49-c355-4b25-a1c2-62fbdf324e66",
    "9d7a6d58-4be1-4d3a-80f6-d2eca89d013b",
    "0776ad79-cdf8-4099-832a-b7b223734c8e",
    "17a2938f-50f7-4ae1-a16c-c825f00be222",
    "ab9aab2a-2309-4f95-8123-67afd6e4938e",
}
local me = Players.LocalPlayer
if not me then warn("LocalPlayer unavailable.") return end
local env = _G
if type(getgenv) == "function" then env = getgenv() end
for _, key in ipairs({"__BGSI_Top15Transfer", "__BGSI_Fixed15Transfer"}) do
    local previous = env[key]
    if previous and type(previous.stop) == "function" then pcall(previous.stop) end
end
for _, key in ipairs({"__BGSI_ChatRequestTest", "__BGSI_HiTradeListener"}) do
    if env[key] then
        pcall(function() env[key]:Disconnect() end)
        env[key] = nil
    end
end
local remote = RS
for _, name in ipairs({"Shared", "Framework", "Network", "Remote", "RemoteEvent"}) do
    remote = remote:FindFirstChild(name)
    if not remote then warn("Missing network object: " .. name) return end
end
local function notify(text)
    print("[BGSI] " .. text)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {Title = "BGSI fixed 15", Text = text, Duration = 8})
    end)
end
local state = {running = true, connections = {}, recipient = nil, pendingUntil = 0, tradeId = nil, latest = nil, adding = false, readySent = false, confirmSent = false, baseline = nil, countdown = false, generation = 0}
env.__BGSI_Fixed15Transfer = state
local function stop(reason)
    if not state.running then return end
    state.running = false
    state.generation += 1
    for _, connection in ipairs(state.connections) do connection:Disconnect() end
    if env.__BGSI_Fixed15Transfer == state then env.__BGSI_Fixed15Transfer = nil end
    notify(reason or "Automation stopped.")
end
state.stop = stop
local function send(command, ...)
    if not state.running then return false end
    local ok, err = pcall(remote.FireServer, remote, command, ...)
    if not ok then stop("Local error: " .. tostring(err)) end
    return ok
end
local expected = {}
for _, id in ipairs(PET_IDS) do expected[id .. ":0"] = true end
local function parties(data)
    if type(data) ~= "table" then return end
    local a, b = data.Party0, data.Party1
    if type(a) ~= "table" or type(b) ~= "table" then return end
    if a.Player == me then return a, b end
    if b.Player == me then return b, a end
end
local function correctPartner(other)
    local player = other and other.Player
    return typeof(player) == "Instance" and player:IsA("Player") and player ~= me and player == state.recipient and ALLOWED_RECIPIENTS[player.Name:lower()] == true
end
local function exactOffer(party)
    if type(party.Offer) ~= "table" then return false end
    local count, found = 0, {}
    for _, item in pairs(party.Offer) do
        count += 1
        if type(item) ~= "table" or item.Type ~= "Pet" or not expected[item.Id] or found[item.Id] then return false end
        found[item.Id] = true
    end
    return count == #PET_IDS
end
local function signature(own, other)
    local function encodeOffer(offer)
        local entries = {}
        for _, item in pairs(offer or {}) do table.insert(entries, Http:JSONEncode(item)) end
        table.sort(entries)
        return table.concat(entries, "|")
    end
    return encodeOffer(own.Offer) .. "\n" .. encodeOffer(other.Offer)
end
local function tradeVisible()
    local screen = me.PlayerGui:FindFirstChild("ScreenGui")
    local trading = screen and screen:FindFirstChild("Trading")
    if not trading or not trading:IsA("GuiObject") then return false end
    local object = trading
    while object and object ~= me.PlayerGui do
        if object:IsA("GuiObject") and not object.Visible then return false end
        if object:IsA("ScreenGui") and not object.Enabled then return false end
        object = object.Parent
    end
    return true
end
local function evaluate()
    if not state.running or state.adding then return end
    local data = state.latest
    if not data or data.Id ~= state.tradeId then return end
    local own, other = parties(data)
    if not own or not correctPartner(other) then stop("Unexpected trade participant. Review manually.") return end
    if data.Processing then stop("Server reports processing. Check the trade result.") return end
    if own.Confirmed then stop("Your confirmation is acknowledged. Check the trade result.") return end
    if not state.readySent then
        if not exactOffer(own) then return end
        if own.Accepted or other.Accepted then stop("Someone readied before setup finished. Review manually.") return end
        state.baseline = signature(own, other)
        state.readySent = true
        notify("All 15 acknowledged. Sending Ready.")
        send("TradeAccept")
        return
    end
    if not exactOffer(own) or signature(own, other) ~= state.baseline then stop("An offer changed after Ready. Review manually.") return end
    if not own.Accepted or not other.Accepted then
        if state.countdown then stop("Readiness changed. Automatic confirmation cancelled.") end
        return
    end
    if state.countdown or state.confirmSent then return end
    state.countdown = true
    state.generation += 1
    local generation, tradeId = state.generation, state.tradeId
    local earliestLocalTime = os.clock() + CONFIRM_DELAY
    notify("Both ready. Waiting for 4 seconds AND the game countdown.")
    task.spawn(function()
        local deadline = os.clock() + 60
        while state.running and state.generation == generation do
            local latest = state.latest
            local mine, theirs = parties(latest)
            if not latest or latest.Id ~= tradeId or not mine or not correctPartner(theirs) then stop("Trade identity changed. Confirm was NOT sent.") return end
            if latest.Processing or mine.Confirmed then stop("Confirmation or processing acknowledged. Check result.") return end
            if not tradeVisible() or not mine.Accepted or not theirs.Accepted or not exactOffer(mine) or signature(mine, theirs) ~= state.baseline then stop("Trade changed during countdown. Confirm was NOT sent.") return end
            local timer = latest.Timer
            local validTimer = type(timer) == "number" and timer == timer and timer > 0 and timer < math.huge
            local localDelayFinished = os.clock() >= earliestLocalTime
            local gameDelayFinished = validTimer and workspace:GetServerTimeNow() >= timer + 0.25
            if localDelayFinished and gameDelayFinished then
                state.confirmSent = true
                if send("TradeConfirm") then notify("Game countdown finished. Confirm command sent.") end
                task.delay(10, function()
                    if state.running then stop("Confirmation not acknowledged. Review manually; no retry sent.") end
                end)
                return
            end
            if os.clock() >= deadline then stop("Confirmation countdown timed out. Review manually.") return end
            task.wait(0.1)
        end
    end)
end
table.insert(state.connections, remote.OnClientEvent:Connect(function(event, data)
    if not state.running then return end
    if event == "TradeStarted" then
        if state.tradeId then stop("Another trade started. Automation stopped.") return end
        if not state.recipient or state.pendingUntil == 0 or os.clock() > state.pendingUntil then return end
        local own, other = parties(data)
        if not own or not correctPartner(other) then stop("Trade started with an unexpected player.") return end
        if type(data.Id) ~= "string" then stop("Trade ID missing.") return end
        local pets = own.Inventory and own.Inventory.Pets
        if type(pets) ~= "table" then stop("Own inventory missing.") return end
        local lookup = {}
        for _, pet in pairs(pets) do
            if type(pet) == "table" and pet.Id then lookup[pet.Id] = pet end
        end
        for _, id in ipairs(PET_IDS) do
            local pet = lookup[id]
            if not pet then stop("Selected pet missing on this account: " .. id) return end
            if pet.Amount and pet.Amount > 1 then stop("Selected pet is stacked. Review manually.") return end
        end
        if next(own.Offer or {}) or next(other.Offer or {}) or own.Accepted or other.Accepted or own.Confirmed or other.Confirmed or data.Processing then stop("Trade was not empty and unready at startup.") return end
        state.tradeId = data.Id
        state.latest = data
        state.adding = true
        notify("Trading with " .. state.recipient.Name .. ". Waiting 4 seconds before adding pets.")
        task.spawn(function()
            task.wait(SETUP_DELAY)
            if not state.running then return end
            if not tradeVisible() then stop("Trade window is still hidden after 4 seconds.") return end
            notify("Adding the captured 15 pets.")
            for _, id in ipairs(PET_IDS) do
                if not state.running then return end
                local latest = state.latest
                local mine, theirs = parties(latest)
                local reason
                if not latest then reason = "Latest trade state is missing."
                elseif latest.Id ~= state.tradeId then reason = "Trade ID changed."
                elseif latest.Processing then reason = "Trade is already processing."
                elseif not mine then reason = "Could not identify your side."
                elseif not correctPartner(theirs) then reason = "Trade partner does not match."
                elseif mine.Accepted or mine.Confirmed then reason = "Your side readied before setup finished."
                elseif theirs.Accepted or theirs.Confirmed then reason = "Recipient readied before setup finished."
                elseif not tradeVisible() then reason = "Trade window closed or became hidden." end
                if reason then stop(reason .. " Review manually.") return end
                if not send("TradeAddPet", id .. ":0") then return end
                task.wait(0.35)
            end
            state.adding = false
            evaluate()
            task.delay(12, function()
                if state.running and not state.readySent then stop("Not all 15 pets acknowledged. Review manually.") end
            end)
        end)
        task.delay(120, function()
            if state.running then stop("Trade session timed out. Review manually.") end
        end)
    elseif event == "TradeUpdated" and state.tradeId then
        if type(data) ~= "table" or data.Id ~= state.tradeId then return end
        state.latest = data
        evaluate()
    end
end))
table.insert(state.connections, Chat.MessageReceived:Connect(function(message)
    if not state.running or state.tradeId then return end
    local source = message.TextSource
    local speaker = source and Players:GetPlayerByUserId(source.UserId)
    if not speaker or speaker == me or not ALLOWED_RECIPIENTS[speaker.Name:lower()] then return end
    local text = (message.Text or ""):match("^%s*(.-)%s*$"):lower()
    if text ~= "hi" then return end
    if os.clock() < state.pendingUntil then return end
    state.recipient = speaker
    state.pendingUntil = os.clock() + 60
    local requestDeadline = state.pendingUntil
    notify("Detected hi. Requesting trade with " .. speaker.Name)
    if not send("TradeRequest", speaker) then return end
    task.delay(60, function()
        if state.running and not state.tradeId and state.recipient == speaker and state.pendingUntil == requestDeadline then
            state.recipient = nil
            state.pendingUntil = 0
            notify("Request expired. Listening for a new hi.")
        end
    end)
end))
table.insert(state.connections, Players.PlayerRemoving:Connect(function(player)
    if player ~= state.recipient then return end
    if state.tradeId then stop("Selected recipient left the server.")
    else
        state.recipient = nil
        state.pendingUntil = 0
        notify("Selected recipient left. Listening for a new hi.")
    end
end))
notify("Running on " .. me.Name .. ". Waiting for a NEW hi from nodineside414 or nodiisking.")
