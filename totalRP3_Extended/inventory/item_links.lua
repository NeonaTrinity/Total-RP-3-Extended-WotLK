----------------------------------------------------------------------------------
-- Total RP 3 Extended - WotLK custom item chat links
-- Alpha 19 compatibility feature for the 3.3.5 port.
--
-- WoW 3.3.5 rejects unknown |H...|h links in SendChatMessage(). We therefore
-- send only the clean visible text "[Item Name]" through normal chat. In
-- channels that support addon traffic, item metadata is sent separately via
-- SendAddonMessage and Alpha 16 clients locally turn the visible text into a
-- clickable Extended hyperlink. Non-addon clients see only [Item Name].
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
local LINK_ADVERT_PREFIX = "TRP3XIL";
local ADVERT_LIFETIME = 30;

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
    value = value:gsub("[%[%]<>]", "");
    value = value:gsub("[%c]", "");
    if string.len(value) > 42 then value = string.sub(value, 1, 42); end
    if value == "" then value = "RP Item"; end
    return value;
end

local function normalizeName(name)
    name = tostring(name or "");
    name = name:gsub("%-.*$", "");
    return name:lower();
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

local function makeLocalHyperlink(fullID, sender, version, label)
    label = cleanLabel(label);
    return ("|cff33ff99|Htrp3xitem:%s:%s:%d|h[%s]|h|r"):format(
        encode(fullID), encode(sender or ""), tonumber(version) or 0, label
    );
end

-- A clicked chat link is not a hover event. Pin it at the mouse, but give it
-- explicit lifecycle state so UIParent (which is always under the mouse) cannot
-- keep the tooltip alive forever after the timeout expires.
local LINK_TOOLTIP_LIFETIME = 30;
local function hideLinkTooltip()
    if TRP3_ItemTooltip and TRP3_ItemTooltip.trp3xLinkID then
        TRP3_ItemTooltip.trp3xLinkID = nil;
        TRP3_ItemTooltip.trp3xPinnedUntil = nil;
        TRP3_ItemTooltip:Hide();
        return true;
    end
    return false;
end

local function showLinkTooltip(fullID)
    if not classExists(fullID) then return false; end
    if TRP3_ItemTooltip and TRP3_ItemTooltip:IsShown() and TRP3_ItemTooltip.trp3xLinkID == fullID then
        hideLinkTooltip();
        return true;
    end
    if TRP3_ItemTooltip then TRP3_ItemTooltip:Hide(); end
    local class = getClass(fullID);
    showItemTooltip(UIParent, { id = fullID, count = 1 }, class, true, "ANCHOR_CURSOR");
    if TRP3_ItemTooltip then
        TRP3_ItemTooltip.trp3xLinkID = fullID;
        TRP3_ItemTooltip.trp3xPinnedUntil = (GetTime and GetTime() or 0) + LINK_TOOLTIP_LIFETIME;
        TRP3_ItemTooltip:EnableMouse(true);
    end
    return true;
end

-- Clicking the pinned tooltip itself also dismisses it. This only consumes the
-- click while the tooltip is showing a chat-linked Extended item.
if TRP3_ItemTooltip and not TRP3X_WOTLK.itemLinkTooltipClickInstalled then
    TRP3X_WOTLK.itemLinkTooltipClickInstalled = true;
    local previousMouseDown = TRP3_ItemTooltip:GetScript("OnMouseDown");
    TRP3_ItemTooltip:SetScript("OnMouseDown", function(self, button)
        if self.trp3xLinkID then
            hideLinkTooltip();
            return;
        end
        if previousMouseDown then previousMouseDown(self, button); end
    end);
end

-- Metadata advertisements waiting for the matching clean chat line.
local advertisedLinks = {};
local function cacheAdvert(sender, fullID, version, label)
    local key = normalizeName(sender);
    if key == "" then return; end
    advertisedLinks[key] = advertisedLinks[key] or {};
    table.insert(advertisedLinks[key], 1, {
        fullID = fullID,
        version = tonumber(version) or 0,
        label = cleanLabel(label),
        expires = (GetTime and GetTime() or 0) + ADVERT_LIFETIME,
    });
    while #advertisedLinks[key] > 12 do table.remove(advertisedLinks[key]); end
end

local function advertiseForActiveChat(fullID, version, label)
    if not ChatEdit_GetActiveWindow or not SendAddonMessage then return; end
    local editBox = ChatEdit_GetActiveWindow();
    if not editBox then return; end
    local chatType = (editBox.GetAttribute and editBox:GetAttribute("chatType")) or editBox.chatType;
    chatType = tostring(chatType or ""):upper();
    local target = (editBox.GetAttribute and editBox:GetAttribute("tellTarget")) or editBox.tellTarget;
    local supported = {
        WHISPER = true, PARTY = true, RAID = true, GUILD = true,
        OFFICER = true, BATTLEGROUND = true,
    };
    if not supported[chatType] then return; end

    local payload = table.concat({hexEncode(fullID), tostring(version or 0), hexEncode(label)}, ":");
    local ok;
    if chatType == "WHISPER" then
        if target and target ~= "" then ok = pcall(SendAddonMessage, LINK_ADVERT_PREFIX, payload, "WHISPER", target); end
    else
        ok = pcall(SendAddonMessage, LINK_ADVERT_PREFIX, payload, chatType);
    end
    if ok then
        cacheAdvert(UnitName("player") or Globals.player_id or Globals.player, fullID, version, label);
    end
end

-- Shift-click always inserts clean server-safe text. The side-channel advert is
-- optional and only possible in whisper/group/guild-style channels.
function API.inventory.getItemChatLink(fullID, itemClass)
    if not fullID then return nil; end
    itemClass = itemClass or getClass(fullID);
    local rootID = getRootClassID(fullID);
    local rootVersion = getVersion(rootID);
    local label = getLabel(itemClass);
    advertiseForActiveChat(fullID, rootVersion, label);
    return ("[%s]"):format(label);
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

    if sender ~= "" and normalizeName(sender) ~= normalizeName(Globals.player_id or Globals.player or UnitName("player")) then
        pendingLinks[rootID] = pendingLinks[rootID] or {};
        pendingLinks[rootID][fullID] = true;
        Comm.sendObject(LINK_REQUEST, { rootID = rootID, v = getVersion(rootID) }, sender, "NORMAL");
        Utils.message.displayMessage("Requesting Extended item data from " .. sender .. "...");
    else
        Utils.message.displayMessage("This Extended item is not available locally.");
    end
    return true;
end

-- Receive the hidden metadata advertisement used only for supported private /
-- group chat types. It contains no executable object data, just ID/version/name.
local advertFrame = CreateFrame("Frame", "TRP3X_ItemLinkAdvertFrame");
advertFrame:RegisterEvent("CHAT_MSG_ADDON");
advertFrame:SetScript("OnEvent", function(self, event, prefix, message, channel, sender)
    if prefix ~= LINK_ADVERT_PREFIX or type(message) ~= "string" then return; end
    local idHex, version, labelHex = message:match("^([0-9A-Fa-f]+):(%d+):([0-9A-Fa-f]+)$");
    if not idHex then return; end
    local fullID, label = hexDecode(idHex), hexDecode(labelHex);
    if fullID and label then cacheAdvert(sender, fullID, tonumber(version) or 0, label); end
end);

local function chatAdvertFilter(self, event, message, author, ...)
    if type(message) ~= "string" then return false, message, author, ...; end
    local sender = author or "";
    if event == "CHAT_MSG_WHISPER_INFORM" then
        sender = UnitName("player") or Globals.player_id or Globals.player or sender;
    end
    local key = normalizeName(sender);
    local list = advertisedLinks[key];
    if not list then return false, message, author, ...; end

    local now = GetTime and GetTime() or 0;
    for i = #list, 1, -1 do
        if list[i].expires < now then table.remove(list, i); end
    end
    for i, advert in ipairs(list) do
        local token = "[" .. advert.label .. "]";
        local startPos, endPos = string.find(message, token, 1, true);
        if startPos then
            local replacement = makeLocalHyperlink(advert.fullID, sender, advert.version, advert.label);
            message = string.sub(message, 1, startPos - 1) .. replacement .. string.sub(message, endPos + 1);
            table.remove(list, i);
            break;
        end
    end
    return false, message, author, ...;
end

if ChatFrame_AddMessageEventFilter and not TRP3X_WOTLK.itemLinkChatFilterInstalled then
    TRP3X_WOTLK.itemLinkChatFilterInstalled = true;
    local events = {
        "CHAT_MSG_PARTY", "CHAT_MSG_RAID", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
        "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BATTLEGROUND",
    };
    for _, event in ipairs(events) do pcall(ChatFrame_AddMessageEventFilter, event, chatAdvertFilter); end
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
