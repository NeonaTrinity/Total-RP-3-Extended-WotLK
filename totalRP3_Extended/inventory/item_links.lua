----------------------------------------------------------------------------------
-- Total RP 3 Extended - WotLK custom item chat links
-- Compatibility feature for the 3.3.5 port.
----------------------------------------------------------------------------------
local API = TRP3_API;
local Globals, Events, Utils = API.globals, API.events, API.utils;
local Comm = API.communication;
local classExists = API.extended.classExists;
local getClass = API.extended.getClass;
local getRootClassID = API.extended.getRootClassID;
local getItemLink = API.inventory.getItemLink;
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

local function getVersion(rootID)
	if classExists(rootID) then
		local class = getClass(rootID);
		return (class.MD and tonumber(class.MD.V)) or 0;
	end
	return 0;
end

function API.inventory.getItemChatLink(fullID, itemClass)
	if not fullID then return nil; end
	itemClass = itemClass or getClass(fullID);
	local rootID = getRootClassID(fullID);
	local rootVersion = getVersion(rootID);
	local sender = Globals.player_id or Globals.player or UnitName("player") or "";
	local display = getItemLink(itemClass, fullID);
	return ("|Htrp3xitem:%s:%s:%d|h%s|h"):format(
		encode(fullID), encode(sender), rootVersion, display
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
