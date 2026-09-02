--------------------------------------------------------------------------------
-- Total RP 3 Extended - WotLK 3.3.5a compatibility layer
-- Alpha 1: targets the public joyvanderveeken/Total-RP-3-WotLK backport.
-- This file deliberately patches only Extended's environment; totalRP3 itself
-- remains unmodified.
--------------------------------------------------------------------------------

TRP3X_WOTLK = TRP3X_WOTLK or {};
TRP3X_WOTLK.alpha = "9";
-- The stock WotLK TRP3 toolbar crashes when an addon registers its first button
-- because toolbar.lua assumes GetPushedTexture() is non-nil. Keep the public
-- base addon untouched and suppress Extended toolbar registration for now.
TRP3X_WOTLK.disableStockToolbarIntegration = true;

local API = TRP3_API;
if not API then return; end


-- ---------------------------------------------------------------------------
-- API-34 utility compatibility used by Extended/Tools but absent from API 11.
-- ---------------------------------------------------------------------------
API.utils = API.utils or {};
API.utils.color = API.utils.color or {};
API.utils.serial = API.utils.serial or {};
API.utils.event = API.utils.event or {};

-- Later TRP3 accepts a {r,g,b} table directly. API 11 only exposes the
-- three-number colorCodeFloat helper.
if not API.utils.color.colorCodeFloatTab then
    function API.utils.color.colorCodeFloatTab(color)
        color = color or {};
        local r, g, b = color.r or color[1] or 1, color.g or color[2] or 1, color.b or color[3] or 1;
        if API.utils.color.colorCodeFloat then
            return API.utils.color.colorCodeFloat(r, g, b);
        end
        return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5));
    end
end

-- Legion introduced LE_ITEM_QUALITY_* constants. Wrath uses the same numeric
-- quality IDs but does not expose the LE_ names.
LE_ITEM_QUALITY_POOR      = LE_ITEM_QUALITY_POOR      or 0;
LE_ITEM_QUALITY_COMMON    = LE_ITEM_QUALITY_COMMON    or 1;
LE_ITEM_QUALITY_UNCOMMON  = LE_ITEM_QUALITY_UNCOMMON  or 2;
LE_ITEM_QUALITY_RARE      = LE_ITEM_QUALITY_RARE      or 3;
LE_ITEM_QUALITY_EPIC      = LE_ITEM_QUALITY_EPIC      or 4;
LE_ITEM_QUALITY_LEGENDARY = LE_ITEM_QUALITY_LEGENDARY or 5;
LE_ITEM_QUALITY_ARTIFACT  = LE_ITEM_QUALITY_ARTIFACT  or 6;
LE_ITEM_QUALITY_HEIRLOOM  = LE_ITEM_QUALITY_HEIRLOOM  or 7;

-- Some 3.3.5 clients expose ITEM_QUALITY_COLORS but not the later bag alias.
if not BAG_ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS then
    BAG_ITEM_QUALITY_COLORS = ITEM_QUALITY_COLORS;
end

-- Safe import helper used by the creation database. Preserve API-11's
-- deserialize behavior while turning malformed pasted data into nil.
if not API.utils.serial.safeDeserialize then
    function API.utils.serial.safeDeserialize(value)
        if not API.utils.serial.deserialize then return nil; end
        local ok, result = pcall(API.utils.serial.deserialize, value);
        if ok then return result; end
        return nil;
    end
end

-- Extended's synthetic events use the newer Utils.event.fireEvent alias. The
-- API-11 event bus already implements the exact behavior under API.events.
if not API.utils.event.fireEvent and API.events and API.events.fireEvent then
    API.utils.event.fireEvent = API.events.fireEvent;
end

-- PlayerModel animation changed after Wrath. FreezeAnimation was only added
-- much later. Prefer the native method when available and fall back to the
-- old Model:SetSequence API; pose-time precision is cosmetic only.
TRP3X_WOTLK.applyModelAnimation = TRP3X_WOTLK.applyModelAnimation or function(model, sequence, sequenceTime)
    if not model then return false; end
    sequence = tonumber(sequence) or 0;
    if model.FreezeAnimation then
        local ok = pcall(model.FreezeAnimation, model, sequence, 0, tonumber(sequenceTime) or 0);
        if ok then return true; end
    end
    if model.SetAnimation then
        local ok = pcall(model.SetAnimation, model, sequence, 0);
        if ok then return true; end
    end
    if model.SetSequence then
        local ok = pcall(model.SetSequence, model, sequence);
        if ok then return true; end
    end
    return false;
end;


-- ---------------------------------------------------------------------------
-- API-34 event names absent from the API-11 WotLK backport.
-- Register them early so Extended modules can safely listen/fire regardless of
-- which TRP3 module starts first. pcall makes this idempotent.
-- ---------------------------------------------------------------------------
TRP3X_WOTLK.ensureEvent = TRP3X_WOTLK.ensureEvent or function(eventName)
    if not eventName then return nil; end
    if API.events and API.events.registerEvent then
        pcall(API.events.registerEvent, eventName);
    end
    return eventName;
end

do
    local eventNames = {
        "CAMPAIGN_REFRESH_LOG",
        "ON_OBJECT_UPDATED",
        "NAVIGATION_RESIZED",
        "NAVIGATION_EXTENDED_RESIZED",
    };
    for _, eventName in ipairs(eventNames) do
        if not API.events[eventName] then API.events[eventName] = eventName; end
        TRP3X_WOTLK.ensureEvent(API.events[eventName]);
    end
end

-- Extended 1.0.7 stores world drops/stashes by realm. The public 3.3.5
-- TRP3 backport intentionally removed realm-qualified player IDs and therefore
-- never defines globals.player_realm. Give Extended its own stable realm key.
if not API.globals.player_realm or API.globals.player_realm == "" then
    local realm = GetRealmName and GetRealmName() or nil;
    API.globals.player_realm = (realm and realm ~= "") and realm or "WotLK";
end

-- ---------------------------------------------------------------------------
-- Timer compatibility
-- ---------------------------------------------------------------------------
C_Timer = C_Timer or {};
if not C_Timer.NewTicker then
    function C_Timer.NewTicker(interval, callback, iterations)
        interval = tonumber(interval) or 0;
        if interval <= 0 then interval = 0.01; end
        local ticker = CreateFrame("Frame");
        ticker.elapsed = 0;
        ticker.cancelled = false;
        ticker.remaining = iterations and tonumber(iterations) or nil;
        function ticker:Cancel()
            self.cancelled = true;
            self:SetScript("OnUpdate", nil);
            self:Hide();
        end
        ticker:SetScript("OnUpdate", function(self, elapsed)
            if self.cancelled then return; end
            self.elapsed = self.elapsed + elapsed;
            while self.elapsed >= interval and not self.cancelled do
                self.elapsed = self.elapsed - interval;
                if callback then callback(self); end
                if self.remaining then
                    self.remaining = self.remaining - 1;
                    if self.remaining <= 0 then self:Cancel(); return; end
                end
            end
        end);
        ticker:Show();
        return ticker;
    end
end

-- ---------------------------------------------------------------------------
-- World/map compatibility. 3.3.5 does not expose UnitPosition. We use the
-- normalized world-map coordinates multiplied to a stable local coordinate
-- space. This is sufficient for Extended proximity logic inside one map.
-- ---------------------------------------------------------------------------
if not UnitPosition then
    function UnitPosition(unit)
        unit = unit or "player";
        if not UnitExists(unit) then return nil; end
        if SetMapToCurrentZone then SetMapToCurrentZone(); end
        local x, y = 0, 0;
        if GetPlayerMapPosition then
            x, y = GetPlayerMapPosition(unit);
            x, y = x or 0, y or 0;
        end
        local mapID = GetCurrentMapAreaID and GetCurrentMapAreaID() or 0;
        return y * 10000, x * 10000, 0, mapID;
    end
end

API.map = API.map or {};
if not API.map.getCurrentCoordinates then
    function API.map.getCurrentCoordinates(unit)
        unit = unit or "player";
        if SetMapToCurrentZone then SetMapToCurrentZone(); end
        local x, y = 0, 0;
        if GetPlayerMapPosition then x, y = GetPlayerMapPosition(unit); end
        return GetCurrentMapAreaID and GetCurrentMapAreaID() or 0, x or 0, y or 0;
    end
end

if not EJ_GetCurrentInstance then
    function EJ_GetCurrentInstance() return 0; end
end

-- ---------------------------------------------------------------------------
-- Companion journal compatibility using Wrath's companion API.
-- ---------------------------------------------------------------------------
local function findCompanion(kind, wanted)
    if not GetNumCompanions or not GetCompanionInfo then return nil; end
    local count = GetNumCompanions(kind) or 0;
    for i = 1, count do
        local creatureID, name, spellID, icon, active = GetCompanionInfo(kind, i);
        if wanted == i or wanted == creatureID or wanted == spellID or wanted == name or wanted == tostring(i) then
            return i, creatureID, name, spellID, icon, active;
        end
    end
end

C_MountJournal = C_MountJournal or {};
if not C_MountJournal.SummonByID then
    function C_MountJournal.SummonByID(id)
        local index = findCompanion("MOUNT", id);
        if index and CallCompanion then CallCompanion("MOUNT", index); return true; end
        return false;
    end
end
if not C_MountJournal.GetMountInfoByID then
    function C_MountJournal.GetMountInfoByID(id)
        local index, creatureID, name, spellID, icon, active = findCompanion("MOUNT", id);
        if not index then return nil; end
        return name, spellID, icon, active, true, 0, false, false, nil, false, true;
    end
end
if not C_MountJournal.GetMountInfoExtraByID then
    function C_MountJournal.GetMountInfoExtraByID(id)
        local index, creatureID = findCompanion("MOUNT", id);
        if not index then return nil; end
        return creatureID, nil, nil, nil, nil, nil, nil, nil;
    end
end

C_PetJournal = C_PetJournal or {};
local function activeCritterIndex()
    if not GetNumCompanions or not GetCompanionInfo then return nil; end
    local count = GetNumCompanions("CRITTER") or 0;
    for i = 1, count do
        local _, _, _, _, active = GetCompanionInfo("CRITTER", i);
        if active then return i; end
    end
end
if not C_PetJournal.GetSummonedPetGUID then
    function C_PetJournal.GetSummonedPetGUID()
        local index = activeCritterIndex();
        return index and ("WOTLKCRITTER:" .. index) or nil;
    end
end
if not C_PetJournal.SummonPetByGUID then
    function C_PetJournal.SummonPetByGUID(guid)
        local index = tonumber(tostring(guid or ""):match("WOTLKCRITTER:(%d+)")) or tonumber(guid);
        if index and CallCompanion then CallCompanion("CRITTER", index); return true; end
        return false;
    end
end
if not C_PetJournal.SummonRandomPet then
    function C_PetJournal.SummonRandomPet()
        local count = GetNumCompanions and (GetNumCompanions("CRITTER") or 0) or 0;
        if count > 0 and CallCompanion then CallCompanion("CRITTER", math.random(1, count)); return true; end
        return false;
    end
end

-- ---------------------------------------------------------------------------
-- TRP3 API additions used by Extended 1.0.7 but absent from API level 11.
-- ---------------------------------------------------------------------------
API.formats = API.formats or {};
API.formats.dropDownElements = API.formats.dropDownElements or "%s: %s";

API.ui = API.ui or {};
API.ui.frame = API.ui.frame or {};
API.ui.tooltip = API.ui.tooltip or {};
API.ui.misc = API.ui.misc or {};



-- API-34 text toolbar passes the toolbar frame itself; API-11 expects the
-- toolbar's global name prefix as a string. Bridge the signature in-place.
API.ui.text = API.ui.text or {};
do
    local oldSetupToolbar = API.ui.text.setupToolbar;
    if oldSetupToolbar and not TRP3X_WOTLK.textToolbarWrapperInstalled then
        API.ui.text.setupToolbar = function(toolbar, textFrame, ...)
            if type(toolbar) ~= "string" then
                if toolbar and toolbar.GetName then toolbar = toolbar:GetName(); end
            end
            if type(toolbar) ~= "string" or toolbar == "" then return; end
            return oldSetupToolbar(toolbar, textFrame);
        end;
        TRP3X_WOTLK.textToolbarWrapperInstalled = true;
    end
end

-- API 11's tooltip helper assumes every newer XML child exists. Extended 1.0.7
-- has a few cosmetic tooltip targets that are not created by Wrath templates.
-- Missing tooltip-only anchors should not abort the entire Extended Tools module.
do
    local oldSetTooltipAll = API.ui.tooltip.setTooltipAll;
    if oldSetTooltipAll and not TRP3X_WOTLK.tooltipNilGuardInstalled then
        API.ui.tooltip.setTooltipAll = function(frame, ...)
            if not frame then
                return;
            end
            return oldSetTooltipAll(frame, ...);
        end;
        TRP3X_WOTLK.tooltipNilGuardInstalled = true;
    end
end

if not API.ui.frame.setupMove then
    function API.ui.frame.setupMove(frame)
        if not frame or not frame.SetMovable then return; end
        frame:SetMovable(true);
        frame:EnableMouse(true);
        frame:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" and not self.isLocked then self:StartMoving(); end
        end);
        frame:SetScript("OnMouseUp", function(self)
            self:StopMovingOrSizing();
        end);
    end
end

if not API.ui.tooltip.createTooltipBuilder then
    function API.ui.tooltip.createTooltipBuilder(tooltip)
        local builder = { tooltip = tooltip, lines = {} };
        function builder:AddLine(text, r, g, b, size, wrap)
            table.insert(self.lines, {false, text, r, g, b, size, wrap});
            return self;
        end
        function builder:AddDoubleLine(left, right, lr, lg, lb, rr, rg, rb)
            table.insert(self.lines, {true, left, right, lr, lg, lb, rr, rg, rb});
            return self;
        end
        function builder:AddSpace()
            table.insert(self.lines, {false, " "});
            return self;
        end
        function builder:Build()
            if not self.tooltip then return; end
            for _, line in ipairs(self.lines) do
                if line[1] then
                    self.tooltip:AddDoubleLine(line[2] or "", line[3] or "", line[4] or 1, line[5] or 1, line[6] or 1, line[7] or 1, line[8] or 1, line[9] or 1);
                else
                    self.tooltip:AddLine(line[2] or "", line[3] or 1, line[4] or 1, line[5] or 1, line[7]);
                end
            end
            wipe(self.lines);
            self.tooltip:Show();
        end
        return builder;
    end
end

API.register = API.register or {};
if not API.register.getUnitCurrentProfile then
    function API.register.getUnitCurrentProfile(unit)
        if not API.register.getUnitID or not API.register.getUnitIDCurrentProfile then return nil; end
        local unitID = API.register.getUnitID(unit);
        if not unitID then return nil; end
        if unitID == API.globals.player_id and API.globals.player_profile then
            return API.globals.player_profile;
        end
        local ok, profile = pcall(API.register.getUnitIDCurrentProfile, unitID);
        return ok and profile or nil;
    end
end
if not API.register.getUnitRPNameWithID then
    function API.register.getUnitRPNameWithID(unitID)
        if unitID == API.globals.player_id and API.register.getPlayerCompleteName then
            return API.register.getPlayerCompleteName(true);
        end
        if API.register.getUnitIDCurrentProfile and API.register.getCompleteName then
            local ok, profile = pcall(API.register.getUnitIDCurrentProfile, unitID);
            if ok and profile and profile.characteristics then
                return API.register.getCompleteName(profile.characteristics, unitID, true);
            end
        end
        return tostring(unitID or UNKNOWN or "Unknown");
    end
end

API.utils = API.utils or {};
API.utils.str = API.utils.str or {};

-- Parse both Wrath hexadecimal GUIDs and later hyphenated GUIDs. Extended only
-- needs the unit kind and creature/vehicle entry ID, but keeping the parser
-- generic makes target/mouseover/campaign logic much safer.
if not API.utils.str.getUnitDataFromGUIDDirect then
    function API.utils.str.getUnitDataFromGUIDDirect(guid)
        if not guid or guid == "" then return nil, nil; end
        guid = tostring(guid);

        -- Later clients/private forks may expose Creature-... style GUIDs.
        local kind, entry = guid:match("^([A-Za-z]+)%-.-%-(%d+)%-[^%-]+$");
        if kind then return kind, tonumber(entry); end

        local upper = guid:upper();
        local prefix = upper:match("^0X(%x%x%x%x)");
        local entryHex = upper:match("^0XF1[1345]000(%x%x%x%x)");
        if upper:match("^0XF13000") then
            return "Creature", entryHex and tonumber(entryHex, 16) or nil;
        elseif upper:match("^0XF15000") then
            return "Vehicle", entryHex and tonumber(entryHex, 16) or nil;
        elseif upper:match("^0XF14000") then
            return "Pet", entryHex and tonumber(entryHex, 16) or nil;
        elseif upper:match("^0XF11000") then
            local objectEntry = upper:match("^0XF11000(%x%x%x%x)");
            return "GameObject", objectEntry and tonumber(objectEntry, 16) or nil;
        elseif upper:match("^0XF120") then
            return "Transport", nil;
        elseif upper:match("^0X0") then
            return "Player", nil;
        end
        return nil, nil;
    end
end

if not API.utils.str.getUnitDataFromGUID then
    function API.utils.str.getUnitDataFromGUID(unit)
        if not UnitGUID or not unit then return nil, nil; end
        local guid = UnitGUID(unit);
        if not guid then return nil, nil; end
        return API.utils.str.getUnitDataFromGUIDDirect(guid);
    end
end

-- Unit operand helpers exported by later TRP3 API generations.
API.utils.str.GetGuildName = API.utils.str.GetGuildName or function(unit)
    if not GetGuildInfo then return ""; end
    local guild = GetGuildInfo(unit or "player");
    return guild or "";
end;
API.utils.str.GetGuildRank = API.utils.str.GetGuildRank or function(unit)
    if not GetGuildInfo then return ""; end
    local _, rank = GetGuildInfo(unit or "player");
    return rank or "";
end;
API.utils.str.GetRace = API.utils.str.GetRace or function(unit)
    if not UnitRace then return ""; end
    local localized, english = UnitRace(unit or "player");
    return english or localized or "";
end;
API.utils.str.GetClass = API.utils.str.GetClass or function(unit)
    if not UnitClass then return ""; end
    local localized, english = UnitClass(unit or "player");
    return english or localized or "";
end;
API.utils.str.GetFaction = API.utils.str.GetFaction or function(unit)
    if not UnitFactionGroup then return ""; end
    local faction = UnitFactionGroup(unit or "player");
    return faction or "";
end;
if not API.utils.str.getUnitNPCID then
    function API.utils.str.getUnitNPCID(unit)
        local kind, id = API.utils.str.getUnitDataFromGUID(unit);
        if kind == "Creature" or kind == "Vehicle" or kind == "Pet" then return id; end
        return nil;
    end
end

API.utils.music = API.utils.music or {};
do
    local music = API.utils.music;
    music._trp3xHandlers = music._trp3xHandlers or {};
    music._trp3xNextHandler = music._trp3xNextHandler or 0;

    local function remember(id, channel, source)
        music._trp3xNextHandler = music._trp3xNextHandler + 1;
        local handlerID = music._trp3xNextHandler;
        music._trp3xHandlers[handlerID] = {
            id = id,
            channel = channel or "SFX",
            source = source,
            handlerID = handlerID,
            date = date and date("%H:%M:%S") or tostring(time and time() or ""),
        };
        return handlerID;
    end

    if not music.playMusic then
        function music.playMusic(path, source)
            if path == nil then return nil; end
            if type(path) == "number" then
                if PlaySoundKitID then pcall(PlaySoundKitID, path); end
            elseif PlayMusic then
                pcall(PlayMusic, path);
            end
            return remember(path, "Music", source);
        end
    end
    if not music.stopMusic then
        function music.stopMusic()
            if StopMusic then pcall(StopMusic); end
            for id, handler in pairs(music._trp3xHandlers) do
                if handler.channel == "Music" then music._trp3xHandlers[id] = nil; end
            end
            return true;
        end
    end
    if not music.playSoundID then
        function music.playSoundID(soundID, channel, source)
            if soundID == nil then return nil; end
            if type(soundID) == "number" and PlaySoundKitID then
                pcall(PlaySoundKitID, soundID);
            elseif PlaySound then
                local ok = pcall(PlaySound, soundID);
                if not ok then pcall(PlaySound, tostring(soundID)); end
            end
            return remember(soundID, channel or "SFX", source);
        end
    end
    if not music.stopSound then
        function music.stopSound(handlerID)
            handlerID = tonumber(handlerID) or handlerID;
            music._trp3xHandlers[handlerID] = nil;
            -- Wrath's sound API does not reliably provide a stoppable handle for
            -- PlaySound/PlaySoundKitID, so removing the history entry is the safe
            -- compatibility behavior.
            return true;
        end
    end
    if not music.stopChannel then
        function music.stopChannel(channel)
            for id, handler in pairs(music._trp3xHandlers) do
                if not channel or handler.channel == channel or handler.channel ~= "Music" then
                    if handler.channel ~= "Music" then music._trp3xHandlers[id] = nil; end
                end
            end
            return true;
        end
    end
    if not music.getHandlers then
        function music.getHandlers() return music._trp3xHandlers; end
    end
    if not music.clearHandlers then
        function music.clearHandlers() wipe(music._trp3xHandlers); end
    end
    if not music.playLocalMusic then music.playLocalMusic = music.playMusic; end
    if not music.playLocalSoundID then music.playLocalSoundID = music.playSoundID; end
end



-- Tooltip exports that are local-only in the older WotLK TRP3 implementation.
API.ui.tooltip.getMainLineFontSize = API.ui.tooltip.getMainLineFontSize or function() return 16; end;
API.ui.tooltip.getSubLineFontSize = API.ui.tooltip.getSubLineFontSize or function() return 12; end;
API.ui.tooltip.getSmallLineFontSize = API.ui.tooltip.getSmallLineFontSize or function() return 10; end;
API.ui.tooltip.getGameTooltipTexts = API.ui.tooltip.getGameTooltipTexts or function(tooltip)
    tooltip = tooltip or GameTooltip;
    local result = {};
    if not tooltip or not tooltip.NumLines then return result; end
    local baseName = tooltip.GetName and tooltip:GetName();
    if not baseName then return result; end
    for i = 1, (tooltip:NumLines() or 0) do
        local left = _G[baseName .. "TextLeft" .. i];
        local right = _G[baseName .. "TextRight" .. i];
        local leftText = left and left.GetText and left:GetText();
        local rightText = right and right.GetText and right:GetText();
        if leftText and leftText ~= "" then table.insert(result, leftText); end
        if rightText and rightText ~= "" then table.insert(result, rightText); end
    end
    return result;
end;

-- Target types introduced after API 11. Preserve the base function, but teach it
-- how to classify Wrath creature/vehicle GUIDs as NPCs for Extended actions.
API.ui.misc.TYPE_NPC = API.ui.misc.TYPE_NPC or "NPC";
API.ui.misc.TYPE_MOUNT = API.ui.misc.TYPE_MOUNT or "MOUNT";
do
    local oldGetTargetType = API.ui.misc.getTargetType;
    if oldGetTargetType and not TRP3X_WOTLK.targetTypeWrapperInstalled then
        API.ui.misc.getTargetType = function(unit)
            local targetType, isMine = oldGetTargetType(unit);
            if targetType then return targetType, isMine; end
            local kind = API.utils.str.getUnitDataFromGUID(unit);
            if kind == "Creature" or kind == "Vehicle" then
                return API.ui.misc.TYPE_NPC, false;
            end
            return nil, false;
        end;
        TRP3X_WOTLK.targetTypeWrapperInstalled = true;
    end
end

-- /trp3 roll helper used by the item dice effect in Extended 1.0.7.
API.slash = API.slash or {};
if not API.slash.rollDices then
    function API.slash.rollDices(...)
        local total = 0;
        local hadDice = false;
        local args = {...};
        for _, token in ipairs(args) do
            token = tostring(token or ""):lower();
            local count, sides = token:match("^(%d*)d(%d+)$");
            if sides then
                count = tonumber(count) or 1;
                sides = tonumber(sides) or 100;
                count = math.max(1, math.min(count, 100));
                sides = math.max(1, sides);
                for i = 1, count do total = total + math.random(1, sides); end
                hadDice = true;
            else
                local n = tonumber(token);
                if n then total = total + n; hadDice = true; end
            end
        end
        return hadDice and total or math.random(1, 100);
    end
end

-- Tutorial helpers appeared after the base backport. They are cosmetic.
API.navigation = API.navigation or {};
API.navigation.showTutorialTooltip = API.navigation.showTutorialTooltip or function() end;
API.navigation.hideTutorialTooltip = API.navigation.hideTutorialTooltip or function() end;

-- Fonts referenced by Extended documents/quest HTML on later clients.
-- Use the closest stock Wrath font objects when those globals are absent.
DestinyFontHuge = DestinyFontHuge or GameFontNormalHuge or GameFontNormalLarge;
QuestFont_Huge = QuestFont_Huge or GameFontNormalLarge or GameFontNormal;

-- Development/fallback access to the ground-item search while stock TRP3 toolbar
-- integration remains disabled on the WotLK backport. /trpext search scans for
-- items dropped by this character near the current position.
SLASH_TRP3XEXT1 = SLASH_TRP3XEXT1 or "/trpext";
SlashCmdList["TRP3XEXT"] = SlashCmdList["TRP3XEXT"] or function(msg)
    msg = string.lower(tostring(msg or ""));
    if msg == "search" and TRP3_API.inventory and TRP3_API.inventory.searchForItems then
        TRP3_API.inventory.searchForItems();
    elseif DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00TRP3 Extended WotLK:|r /trpext search - search nearby RP ground items");
    end
end;

-- Model helper globals from later FrameXML. Keep controls usable without the
-- retail model-control implementation.
Model_OnMouseDown = Model_OnMouseDown or function() end;
Model_OnMouseUp = Model_OnMouseUp or function() end;

-- ---------------------------------------------------------------------------
-- Newer dynamic popup registry. Bridge icon/music popups to the older TRP3
-- popup functions and support Extended's own registered custom popups.
-- ---------------------------------------------------------------------------
API.popup = API.popup or {};
API.popup.POPUPS = API.popup.POPUPS or {};
API.popup.ICONS = API.popup.ICONS or "icons";
API.popup.MUSICS = API.popup.MUSICS or "musics";
API.popup.COMPANIONS = API.popup.COMPANIONS or "companions";
local oldShowPopup = API.popup.showPopup;
local oldHidePopups = API.popup.hidePopups;

API.popup.showPopup = function(popupID, anchor, args)
    -- Preserve API 11 behavior if a frame was passed directly.
    if type(popupID) ~= "string" then
        if oldShowPopup then return oldShowPopup(popupID); end
        return;
    end
    args = args or {};
    if popupID == API.popup.ICONS and API.popup.showIconBrowser then
        return API.popup.showIconBrowser(args[1], args[2], false);
    elseif popupID == API.popup.MUSICS and API.popup.showMusicBrowser then
        return API.popup.showMusicBrowser(args[1]);
    elseif popupID == API.popup.COMPANIONS then
        -- There is no battle-pet journal browser in Wrath. Keep this action
        -- non-fatal; companion effects can still be entered/tested manually.
        if API.popup.showAlertPopup then API.popup.showAlertPopup("Companion browser is not available on the 3.3.5 client yet."); end
        return;
    end
    local entry = API.popup.POPUPS[popupID];
    if entry and entry.frame then
        -- Extended custom popup frames are not children of API-11's TRP3_PopupsFrame.
        -- Calling oldShowPopup() here produces an empty modal in front of the actual
        -- browser. Hide the old container and show the custom frame directly instead.
        if oldHidePopups then oldHidePopups(); end
        entry.frame:Show();
        if entry.frame.SetFrameStrata then entry.frame:SetFrameStrata("DIALOG"); end
        if anchor and anchor.parent then
            entry.frame:ClearAllPoints();
            entry.frame:SetPoint(anchor.point or "CENTER", anchor.parent, anchor.parentPoint or "CENTER", anchor.x or 0, anchor.y or 0);
            if entry.frame.SetFrameLevel and anchor.parent.GetFrameLevel then
                entry.frame:SetFrameLevel(anchor.parent:GetFrameLevel() + 20);
            end
        end
        if entry.showMethod then return entry.showMethod(unpack(args)); end
    end
end
API.popup.hidePopups = oldHidePopups or function() end;

-- ---------------------------------------------------------------------------
-- Minimal breadcrumb navbar functions used by Extended and Tools.
-- ---------------------------------------------------------------------------
local function navEnsure(nav)
    nav._trp3xButtons = nav._trp3xButtons or {};
    return nav._trp3xButtons;
end
function NavBar_Reset(nav)
    if not nav then return; end
    local buttons = navEnsure(nav);
    for _, button in ipairs(buttons) do button:Hide(); end
    wipe(buttons);
end
function NavBar_ButtonOnEnter(self)
    if self and self.LockHighlight then self:LockHighlight(); end
end
function NavBar_ButtonOnLeave(self)
    if self and self.UnlockHighlight then self:UnlockHighlight(); end
end
function NavBar_Initialize(nav, template, homeData, homeButton, overflowButton)
    if not nav then return; end
    nav._trp3xTemplate = template or "TRP3X_NavButtonTemplate";
    nav._trp3xHomeData = homeData;
    if homeButton and homeData then
        homeButton:SetText(homeData.name or "Home");
        homeButton:SetScript("OnClick", homeData.OnClick);
    end
    if overflowButton then overflowButton:Hide(); end
end
function NavBar_AddButton(nav, data)
    if not nav then return nil; end
    local buttons = navEnsure(nav);
    local index = #buttons + 1;
    local button = CreateFrame("Button", (nav:GetName() or "TRP3XNav") .. "Button" .. index, nav, nav._trp3xTemplate or "TRP3X_NavButtonTemplate");
    button.data = data;
    button:SetText((data and data.name) or "?");
    button:SetScript("OnClick", data and data.OnClick or nil);
    if index == 1 then
        button:SetPoint("LEFT", nav.home or nav, "RIGHT", 4, 0);
    else
        button:SetPoint("LEFT", buttons[index - 1], "RIGHT", 4, 0);
    end
    button:Show();
    table.insert(buttons, button);
    return button;
end

-- ---------------------------------------------------------------------------
-- Missing TRP-Anim-DB git submodule fallback.
-- Basic dialogue rendering remains available; advanced per-model scaling and
-- animation timing are intentionally neutral in this first load-test alpha.
-- ---------------------------------------------------------------------------
if LibStub and LibStub.NewLibrary then
    local scaling = LibStub:NewLibrary("TRP-Dialog-Scaling-DB", 1);
    if scaling then
        scaling.SetModelHeight = scaling.SetModelHeight or function() end;
        scaling.SetModelFeet = scaling.SetModelFeet or function() end;
        scaling.SetModelOffset = scaling.SetModelOffset or function() end;
        scaling.SetModelFacing = scaling.SetModelFacing or function() end;
        scaling.GetModelCoupleProperties = scaling.GetModelCoupleProperties or function() return nil; end;
    end
    local anim = LibStub:NewLibrary("TRP-Dialog-Animation-DB", 1);
    if anim then
        anim.PlayAnimationDelay = anim.PlayAnimationDelay or function(model, animation)
            if model and model.SetAnimation and animation then pcall(model.SetAnimation, model, animation); end
        end;
        anim.GetAnimationDuration = anim.GetAnimationDuration or function() return 0; end;
        anim.GetDialogAnimation = anim.GetDialogAnimation or function(animation) return animation or 0; end;
    end
end
