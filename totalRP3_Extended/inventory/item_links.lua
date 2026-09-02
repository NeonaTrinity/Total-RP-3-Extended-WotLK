----------------------------------------------------------------------------------
-- Total RP 3 Extended - WotLK custom item chat links
-- Compatibility feature for the 3.3.5 port.
--
-- 3.3.5 refuses unknown |H...|h hyperlink escape types when SendChatMessage()
-- transmits them to the server. Shift-click therefore inserts a plain-text,
-- server-safe token. Alpha 15 clients convert that token into a clickable local
-- hyperlink when the chat event is displayed.
----------------------------------------------------------------------------------
local API = TRP3_API;
local Globals, Events, Utils = API.globals, API.events, API.utils;
local Comm = API.communication;
local classExists = API.extended.classExists;
local getClass = API.extended.getClass;
local getRootClassID = API.extended.getRootClassID;
local showItemTooltip = API.inventory.showItemTooltip;

local LINK_REQUEST = "ILRQ";
local LINK_RESPONSE = "ILRS";

local function encode(value)
    value = tostring(value or "");
    value = value:gsub("%%", "%%25");
    value = value:gsub(":", "%%3A");
    value = value:gsub(" ", "%%20");
    value = value:gsub("|", "%%7C");
    return value;
end

local function decode(value)
    value = tostring(value or "");
    value = value:gsub("%%7[Cc]", "|");
    value = value:gsub("%%20", " ");
    value = value:gsub("%%3[Aa]", ":");
    value = value:gsub("%%25", "%%");
    return value;
end

local function hexEncode(value)
    value = tostring(value or "");
    local out = {};
    for i = 1, string.len(value) do
        out[#out + 1] = string.format("%02X", string.byte(value, i));
    end
    return table.concat(out);
end

local function hexDecode(value)
    value = tostring(value or "");
    if string.len(value) % 2 ~= 0 then return nil; end
    local out = {};
    for i = 1, string.len(value), 2 do
        local byte = tonumber(string.sub(value, i, i + 1), 16);
        if not byte then return nil; end
        out[#out + 1] = string.char(byte);
    end
    return table.concat(out);
end

local function cleanLabel(value)
    value = tostring(value or "RP Item");
    value = value:gsub("|c%x%x%x%x%x%x%x%x", "");
    value = value:gsub("|r", "");
    value = value:gsub("[%[%]<>\r\n]", "");
    if string.len(value) > 42 then value = string.sub(value, 1, 42); end
    if value == "" then value = "RP Item"; end
    return value;
end

local function getVersion(rootID)
    if classExists(rootID) then
        local class = getClass(rootID);
        return (class.MD and tonumber(class.MD.V)) or 0;
    end
    return 0;
end

local function getLabel(itemClass)
    if itemClass and itemClass.BA and itemClass.BA.NA then
        return cleanLabel(itemClass.BA.NA);
    end
    return "RP Item";
end

-- This is intentionally plain ASCII text. Unknown hyperlink escapes are
-- rejected by SendChatMessage() on the 3.3.5 client before they reach chat.
function API.inventory.getItemChatLink(fullID, itemClass)
    if not fullID then return nil; end
    itemClass = itemClass or getClass(fullID);
    local rootID = getRootClassID(fullID);
    local rootVersion = getVersion(rootID);
    local label = getLabel(itemClass);
    return ("[%s]<TRP3X:%s:%d>"):format(label, hexEncode(fullID), rootVersion);
end

local function makeLocalHyperlink(fullID, sender, version, label)
    label = cleanLabel(label);
    return ("|cff33ff99|Htrp3xitem:%s:%s:%d|h[%s]|h|r"):format(
        encode(fullID), encode(sender or ""), tonumber(version) or 0, label
    );
end

local function showLinkTooltip(fullID)
    if not classExists(fullID) then return false; end
    local class = getClass(fullID);
    showItemTooltip(UIParent, { id = fullID, count = 1 }, class, true, "ANCHOR_CURSOR");
    return true;
end

local pendingLinks = {};

local function importRootClass(rootID, class, sender)
    if type(class) ~= "table" or not class.MD then return false; end
    if not classExists(rootID) or getVersion(rootID) < (tonumber(class.MD.V) or 0) then
        TRP3_DB.exchange[rootID] = class;
        if API.security and API.security.computeSecurity then API.security.computeSecurity(rootID, class); end
        API.extended.unregisterObject(rootID);
        API.extended.registerObject(rootID, class, 0);
        if API.script and API.script.clearRootCompilation then API.script.clearRootCompilation(rootID); end
        if API.security and API.security.registerSender then API.security.registerSender(rootID, sender); end
        if API.inventory.EVENT_REFRESH_BAG then Events.fireEvent(API.inventory.EVENT_REFRESH_BAG); end
        if API.quest and API.quest.EVENT_REFRESH_CAMPAIGN then Events.fireEvent(API.quest.EVENT_REFRESH_CAMPAIGN); end
        if Events.ON_OBJECT_UPDATED then Events.fireEvent(Events.ON_OBJECT_UPDATED); end
    end
    return true;
end

local function receiveLinkRequest(request, sender)
    if type(request) ~= "table" or not request.rootID then return; end
    local rootID = request.rootID;
    if not classExists(rootID) then return; end
    Comm.sendObject(LINK_RESPONSE, {
        rootID = rootID,
        class = getClass(rootID),
    }, sender, "BULK");
end

local function receiveLinkResponse(response, sender)
    if type(response) ~= "table" or not response.rootID or type(response.class) ~= "table" then return; end
    local rootID = response.rootID;
    importRootClass(rootID, response.class, sender);
    local pending = pendingLinks[rootID];
    if pending then
        pendingLinks[rootID] = nil;
        for fullID in pairs(pending) do
            if classExists(fullID) then showLinkTooltip(fullID); end
        end
    end
end

Comm.registerProtocolPrefix(LINK_REQUEST, receiveLinkRequest);
Comm.registerProtocolPrefix(LINK_RESPONSE, receiveLinkResponse);

local function handleItemRef(link)
    local encodedID, encodedSender, version = link:match("^trp3xitem:([^:]+):([^:]*):?(%d*)$");
    if not encodedID then return false; end

    local fullID = decode(encodedID);
    local sender = decode(encodedSender);
    local rootID = getRootClassID(fullID);
    local wantedVersion = tonumber(version) or 0;

    if classExists(rootID) and getVersion(rootID) >= wantedVersion and classExists(fullID) then
        showLinkTooltip(fullID);
        return true;
    end

    if sender ~= "" and sender ~= (Globals.player_id or Globals.player) then
        pendingLinks[rootID] = pendingLinks[rootID] or {};
        pendingLinks[rootID][fullID] = true;
        Comm.sendObject(LINK_REQUEST, {
            rootID = rootID,
            v = getVersion(rootID),
        }, sender, "NORMAL");
        Utils.message.displayMessage("Requesting Extended item data from " .. sender .. "...");
    else
        Utils.message.displayMessage("This Extended item is not available locally.");
    end
    return true;
end

-- Convert safe transport tokens into local clickable hyperlinks only after the
-- server has accepted and delivered the chat message.
local function chatTokenFilter(self, event, message, author, ...)
    if type(message) ~= "string" or not message:find("<TRP3X:", 1, true) then
        return false, message, author, ...;
    end
    local sender = author or "";
    if event == "CHAT_MSG_WHISPER_INFORM" or event == "CHAT_MSG_BN_WHISPER_INFORM" then
        sender = Globals.player_id or Globals.player or UnitName("player") or sender;
    end
    local replaced = message:gsub("%[([^%]]-)%]<TRP3X:([0-9A-Fa-f]+):(%d+)>", function(label, encodedID, version)
        local fullID = hexDecode(encodedID);
        if not fullID then return "[" .. label .. "]"; end
        return makeLocalHyperlink(fullID, sender, version, label);
    end);
    return false, replaced, author, ...;
end

if ChatFrame_AddMessageEventFilter and not TRP3X_WOTLK.itemLinkChatFilterInstalled then
    TRP3X_WOTLK.itemLinkChatFilterInstalled = true;
    local events = {
        "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
        "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
        "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
        "CHAT_MSG_CHANNEL", "CHAT_MSG_BATTLEGROUND", "CHAT_MSG_BATTLEGROUND_LEADER",
    };
    for _, event in ipairs(events) do
        pcall(ChatFrame_AddMessageEventFilter, event, chatTokenFilter);
    end
end

-- Chat hyperlink clicks are routed through SetItemRef on the 3.3.5 client.
if SetItemRef and not TRP3X_WOTLK.itemLinkSetItemRefHooked then
    TRP3X_WOTLK.itemLinkSetItemRefHooked = true;
    TRP3X_WOTLK.originalSetItemRef = SetItemRef;
    SetItemRef = function(link, text, button, chatFrame)
        if type(link) == "string" and link:find("^trp3xitem:") then
            if handleItemRef(link) then return; end
        end
        return TRP3X_WOTLK.originalSetItemRef(link, text, button, chatFrame);
    end
end
