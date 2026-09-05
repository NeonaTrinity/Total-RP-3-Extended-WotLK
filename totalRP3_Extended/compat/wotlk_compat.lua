--------------------------------------------------------------------------------
-- Total RP 3 Extended - WotLK 3.3.5a compatibility layer
-- Alpha 1: targets the public joyvanderveeken/Total-RP-3-WotLK backport.
-- This file deliberately patches only Extended's environment; totalRP3 itself
-- remains unmodified.
--------------------------------------------------------------------------------

TRP3X_WOTLK = TRP3X_WOTLK or {};
TRP3X_WOTLK.alpha = "38";
-- The stock WotLK TRP3 toolbar crashes when an addon registers its first button
-- because toolbar.lua assumes GetPushedTexture() is non-nil. Keep the public
-- base addon untouched; Alpha 16 keeps the Extended buttons on a small
-- compatibility action bar instead of feeding them into the broken stock bar.
TRP3X_WOTLK.disableStockToolbarIntegration = true;

local API = TRP3_API;
if not API then return; end


-- ---------------------------------------------------------------------------
-- API-11 communication compatibility.
--
-- Extended 1.0.7 was written against a later TRP3 communication layer that
-- exposed reserved message IDs and per-message progress callbacks. The public
-- WotLK backport transports the same request/response objects by protocol
-- prefix, but those two cosmetic/progress helpers do not exist and sendObject
-- ignores the later fifth "message id" argument.
--
-- Provide harmless reservation tokens and a no-op progress hook. Functional
-- request/response delivery still goes through API-11's native sendObject().
-- ---------------------------------------------------------------------------
API.communication = API.communication or {};
if not API.communication.getMessageIDAndIncrement then
    local trp3xCompatMessageID = 0;
    function API.communication.getMessageIDAndIncrement()
        trp3xCompatMessageID = trp3xCompatMessageID + 1;
        if trp3xCompatMessageID > 999999 then trp3xCompatMessageID = 1; end
        return "W" .. tostring(trp3xCompatMessageID);
    end
end
if not API.communication.addMessageIDHandler then
    function API.communication.addMessageIDHandler()
        -- API 11 has no packet-progress callback layer. Completion is detected
        -- by the normal Extended response protocol instead.
        return false;
    end
end

-- ---------------------------------------------------------------------------
-- WotLK-safe Extended action bar.
--
-- We intentionally do not patch totalRP3/modules/toolbar/toolbar.lua. Instead,
-- all historical Extended toolbar entries are routed here when the public
-- backport's stock toolbar integration is disabled.
-- ---------------------------------------------------------------------------
TRP3X_WOTLK.actionButtons = TRP3X_WOTLK.actionButtons or {};
TRP3X_WOTLK.actionButtonOrder = TRP3X_WOTLK.actionButtonOrder or {};

local ACTION_BAR_DEFAULT_POINT = "TOP";
local ACTION_BAR_DEFAULT_RELATIVE_POINT = "TOP";
local ACTION_BAR_DEFAULT_X = 0;
local ACTION_BAR_DEFAULT_Y = -72;

local function getTRP3XCharacterSettings()
    -- This table is declared as SavedVariablesPerCharacter in the Extended TOC.
    -- Keep the action-bar data isolated so future per-character compatibility
    -- settings can coexist without changing the saved-variable format.
    TRP3X_WotLK_Character = TRP3X_WotLK_Character or {};
    TRP3X_WotLK_Character.actionBar = TRP3X_WotLK_Character.actionBar or {};
    return TRP3X_WotLK_Character;
end

local function restoreTRP3XActionBarPosition(bar)
    local settings = getTRP3XCharacterSettings().actionBar;
    bar:ClearAllPoints();
    if settings.point and settings.relativePoint and type(settings.x) == "number" and type(settings.y) == "number" then
        bar:SetPoint(settings.point, UIParent, settings.relativePoint, settings.x, settings.y);
    else
        bar:SetPoint(ACTION_BAR_DEFAULT_POINT, UIParent, ACTION_BAR_DEFAULT_RELATIVE_POINT, ACTION_BAR_DEFAULT_X, ACTION_BAR_DEFAULT_Y);
    end
end

local function saveTRP3XActionBarPosition(bar)
    if not bar or not bar.GetPoint then return; end
    local point, _, relativePoint, x, y = bar:GetPoint(1);
    if not point then return; end
    local settings = getTRP3XCharacterSettings().actionBar;
    settings.point = point;
    settings.relativePoint = relativePoint or point;
    settings.x = tonumber(x) or 0;
    settings.y = tonumber(y) or 0;
end

local function ensureTRP3XActionBar()
    if TRP3X_WOTLK.actionBar then return TRP3X_WOTLK.actionBar; end

    local bar = CreateFrame("Frame", "TRP3X_WotLKActionBar", UIParent);
    bar:SetWidth(48);
    bar:SetHeight(40);
    restoreTRP3XActionBarPosition(bar);
    bar:SetFrameStrata("HIGH");
    if bar.SetClampedToScreen then bar:SetClampedToScreen(true); end
    bar:SetMovable(true);
    bar:EnableMouse(true);
    bar:RegisterForDrag("LeftButton");

    local bg = bar:CreateTexture(nil, "BACKGROUND");
    bg:SetAllPoints(bar);
    bg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background");
    if bg.SetVertexColor then bg:SetVertexColor(0, 0, 0, 0.72); end
    bar.background = bg;

    bar:SetScript("OnDragStart", function(self)
        self:StartMoving();
    end);
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing();
        saveTRP3XActionBarPosition(self);
    end);

    TRP3X_WOTLK.actionBar = bar;
    return bar;
end

function TRP3X_WOTLK.resetActionBarPosition()
    local settings = getTRP3XCharacterSettings().actionBar;
    wipe(settings);
    local bar = ensureTRP3XActionBar();
    bar:ClearAllPoints();
    bar:SetPoint(ACTION_BAR_DEFAULT_POINT, UIParent, ACTION_BAR_DEFAULT_RELATIVE_POINT, ACTION_BAR_DEFAULT_X, ACTION_BAR_DEFAULT_Y);
end

local function refreshTRP3XActionBar()
    local bar = ensureTRP3XActionBar();
    local visibleCount = 0;
    for _, id in ipairs(TRP3X_WOTLK.actionButtonOrder) do
        local entry = TRP3X_WOTLK.actionButtons[id];
        if entry and entry.button then
            local shouldShow = entry.structure.visible ~= false;
            if shouldShow then
                visibleCount = visibleCount + 1;
                entry.button:ClearAllPoints();
                entry.button:SetPoint("LEFT", bar, "LEFT", 7 + ((visibleCount - 1) * 34), 0);
                entry.button:Show();
            else
                entry.button:Hide();
            end
        end
    end
    if visibleCount > 0 then
        bar:SetWidth(14 + visibleCount * 34);
        bar:Show();
    else
        bar:Hide();
    end
end

function TRP3X_WOTLK.registerToolbarButton(structure)
    if not structure or not structure.id then return; end

    if not TRP3X_WOTLK.disableStockToolbarIntegration and API.toolbar and API.toolbar.toolbarAddButton then
        return API.toolbar.toolbarAddButton(structure);
    end

    if TRP3X_WOTLK.actionButtons[structure.id] then
        TRP3X_WOTLK.actionButtons[structure.id].structure = structure;
        refreshTRP3XActionBar();
        return;
    end

    local bar = ensureTRP3XActionBar();
    local index = #TRP3X_WOTLK.actionButtonOrder + 1;
    local button = CreateFrame("Button", "TRP3X_WotLKActionButton" .. index, bar);
    button:SetWidth(30);
    button:SetHeight(30);
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp");

    local icon = button:CreateTexture(nil, "ARTWORK");
    icon:SetAllPoints(button);
    icon:SetTexture("Interface\\ICONS\\" .. (structure.icon or "INV_Misc_QuestionMark"));
    button.Icon = icon;

    local highlight = button:CreateTexture(nil, "HIGHLIGHT");
    highlight:SetAllPoints(button);
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square");
    highlight:SetBlendMode("ADD");

    button:SetScript("OnClick", function(self, mouseButton)
        local current = TRP3X_WOTLK.actionButtons[structure.id];
        local data = current and current.structure or structure;
        if data and data.onClick then
            data.onClick(self, data, mouseButton);
        end
    end);
    button:SetScript("OnEnter", function(self)
        local current = TRP3X_WOTLK.actionButtons[structure.id];
        local data = current and current.structure or structure;
        if data and data.onEnter then data.onEnter(self, data); end
        if GameTooltip and data then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM");
            GameTooltip:SetText(data.tooltip or data.configText or structure.id, 1, 1, 1);
            if data.tooltipSub and data.tooltipSub ~= "" then
                GameTooltip:AddLine(data.tooltipSub, 1, 0.82, 0, true);
            end
            GameTooltip:Show();
        end
    end);
    button:SetScript("OnLeave", function(self)
        local current = TRP3X_WOTLK.actionButtons[structure.id];
        local data = current and current.structure or structure;
        if data and data.onLeave then data.onLeave(self, data); end
        if GameTooltip then GameTooltip:Hide(); end
    end);

    button._trp3xElapsed = 0;
    button:SetScript("OnUpdate", function(self, elapsed)
        self._trp3xElapsed = (self._trp3xElapsed or 0) + elapsed;
        if self._trp3xElapsed >= 0.2 then
            self._trp3xElapsed = 0;
            local current = TRP3X_WOTLK.actionButtons[structure.id];
            local data = current and current.structure or structure;
            if data and data.onUpdate then data.onUpdate(self, data); end
            if data and data.icon and self.Icon then
                self.Icon:SetTexture("Interface\\ICONS\\" .. data.icon);
            end
        end
    end);

    TRP3X_WOTLK.actionButtons[structure.id] = { structure = structure, button = button };
    table.insert(TRP3X_WOTLK.actionButtonOrder, structure.id);
    refreshTRP3XActionBar();
end

-- Register through the base WotLK TRP3 slash-command API so the command is
-- automatically advertised whenever the player enters /trp3 with no command.
if API.slash and API.slash.registerCommand then
    API.slash.registerCommand({
        id = "exreset",
        helpLine = " - reset the Extended toolbar position for this character",
        handler = function()
            TRP3X_WOTLK.resetActionBarPosition();
            if API.utils and API.utils.message and API.utils.message.displayMessage then
                API.utils.message.displayMessage("Total RP 3 Extended toolbar position reset.");
            end
        end,
    });
end

-- ---------------------------------------------------------------------------
-- Custom drag icon for RP inventory items.
-- WotLK's SetCursor() does not reliably accept arbitrary item texture paths.
-- ---------------------------------------------------------------------------
local function ensureTRP3XDragIcon()
    if TRP3X_WOTLK.dragIconFrame then return TRP3X_WOTLK.dragIconFrame; end
    local frame = CreateFrame("Frame", "TRP3X_WotLKDragIcon", UIParent);
    frame:SetWidth(34);
    frame:SetHeight(34);
    frame:SetFrameStrata("TOOLTIP");
    frame:EnableMouse(false);
    local icon = frame:CreateTexture(nil, "OVERLAY");
    icon:SetAllPoints(frame);
    frame.Icon = icon;
    frame:SetScript("OnUpdate", function(self)
        local x, y = GetCursorPosition();
        local scale = UIParent:GetEffectiveScale();
        self:ClearAllPoints();
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale);
    end);
    frame:Hide();
    TRP3X_WOTLK.dragIconFrame = frame;
    return frame;
end

function TRP3X_WOTLK.showDragIcon(iconName)
    local frame = ensureTRP3XDragIcon();
    frame.Icon:SetTexture("Interface\\ICONS\\" .. (iconName or "INV_Misc_QuestionMark"));
    frame:Show();
end

function TRP3X_WOTLK.hideDragIcon()
    if TRP3X_WOTLK.dragIconFrame then TRP3X_WOTLK.dragIconFrame:Hide(); end
end


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
        local index, creatureID, name, spellID = findCompanion("MOUNT", id);
        if not index then return nil; end
        local description = "Wrath 3.3.5 mount";
        if spellID then description = description .. " - spell " .. tostring(spellID); end
        return creatureID, description, nil, nil, nil, nil, nil, nil;
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
-- toolbar's global name prefix as a string. The legacy callbacks also query the
-- edit-box cursor *after* opening a modal popup; on this client that can lose
-- the insertion position. Keep the stock H1/H2/H3/P behavior, then install
-- Extended-safe icon/color/image/link callbacks that preserve the cursor.
API.ui.text = API.ui.text or {};
do
    local oldSetupToolbar = API.ui.text.setupToolbar;

    local function insertAt(frame, index, value, cursorAdvance)
        if not frame or not frame.GetText or not frame.SetText then return; end
        index = tonumber(index) or 0;
        local text = frame:GetText() or "";
        if index < 0 then index = 0; end
        if index > string.len(text) then index = string.len(text); end
        frame:SetText(string.sub(text, 1, index) .. value .. string.sub(text, index + 1));
        if frame.SetCursorPosition then
            frame:SetCursorPosition(index + (cursorAdvance or string.len(value)));
        end
        if frame.SetFocus then frame:SetFocus(); end
    end

    local function hexByte(value)
        value = math.floor((tonumber(value) or 0) + 0.5);
        if value < 0 then value = 0; elseif value > 255 then value = 255; end
        return string.format("%02x", value);
    end

    if oldSetupToolbar and not TRP3X_WOTLK.textToolbarWrapperInstalled then
        API.ui.text.setupToolbar = function(toolbar, textFrame, ...)
            local toolbarFrame = toolbar;
            if type(toolbar) ~= "string" then
                if toolbar and toolbar.GetName then toolbar = toolbar:GetName(); end
            end
            if type(toolbar) ~= "string" or toolbar == "" then return; end

            -- Preserve the API-11 header/alignment dropdown implementation.
            oldSetupToolbar(toolbar, textFrame);

            local iconButton = _G[toolbar .. "_Icon"];
            local colorButton = _G[toolbar .. "_Color"];
            local imageButton = _G[toolbar .. "_Image"];
            local linkButton = _G[toolbar .. "_Link"];

            if iconButton then
                iconButton:SetScript("OnClick", function(self)
                    local cursor = textFrame:GetCursorPosition() or 0;
                    API.popup.showPopup(API.popup.ICONS,
                        { parent = toolbarFrame or self, point = "BOTTOM", parentPoint = "TOP", y = 8 },
                        { function(icon)
                            local tag = ("{icon:%s:25}"):format(tostring(icon or "INV_Misc_QuestionMark"));
                            insertAt(textFrame, cursor, tag);
                        end });
                end);
            end
            if colorButton then
                colorButton:SetScript("OnClick", function(self)
                    local cursor = textFrame:GetCursorPosition() or 0;
                    API.popup.showColorBrowser(function(r, g, b)
                        local openTag = ("{col:%s%s%s}"):format(hexByte(r), hexByte(g), hexByte(b));
                        insertAt(textFrame, cursor, openTag .. "{/col}", string.len(openTag));
                        if _G.TRP3_ColorBrowser then _G.TRP3_ColorBrowser:Hide(); end
                    end);
                    local browser = _G.TRP3_ColorBrowser;
                    if browser then
                        TRP3X_WOTLK.positionPopup(browser, {parent = toolbarFrame or self});
                        if _G.TRP3_PopupsFrame then _G.TRP3_PopupsFrame:Hide(); end
                        browser:Show();
                    end
                end);
            end
            if imageButton then
                imageButton:SetScript("OnClick", function(self)
                    local cursor = textFrame:GetCursorPosition() or 0;
                    API.popup.showImageBrowser(function(image)
                        if not image then return; end
                        local width = math.min(tonumber(image.width) or 256, 512);
                        local height = math.min(tonumber(image.height) or 256, 512);
                        local tag = ("{img:%s:%d:%d}"):format(tostring(image.url or ""), width, height);
                        insertAt(textFrame, cursor, tag);
                    end);
                    local browser = _G.TRP3_ImageBrowser;
                    if browser then
                        TRP3X_WOTLK.positionPopup(browser, {parent = toolbarFrame or self});
                        if _G.TRP3_PopupsFrame then _G.TRP3_PopupsFrame:Hide(); end
                        browser:Show();
                    end
                end);
            end
            if linkButton then
                linkButton:SetScript("OnClick", function(self)
                    local cursor = textFrame:GetCursorPosition() or 0;
                    local tag = "{link*URL*TEXT}";
                    insertAt(textFrame, cursor, tag, 6);
                    if textFrame.HighlightText then textFrame:HighlightText(cursor + 6, cursor + 9); end
                end);
            end
        end;
        TRP3X_WOTLK.textToolbarWrapperInstalled = true;
    end
end

-- API-11 setupIconButton assumes the target texture is always the global
-- <frame name>Icon. Extended's later XML often stores a child frame as .icon,
-- whose actual texture is <child name>Icon. Resolve both layouts so one shim
-- fixes workflow, campaign, document, stash and item editors together.
do
    local oldSetupIconButton = API.ui.frame.setupIconButton;
    if oldSetupIconButton and not TRP3X_WOTLK.setupIconButtonWrapperInstalled then
        API.ui.frame.setupIconButton = function(frame, icon)
            if not frame then return; end

            -- A later Extended XML node can expose .icon/.Icon as a child
            -- *frame*, while the actual texture is <childName>Icon. Alpha 20
            -- could stop on that frame and never reach its texture, leaving
            -- workflow rows on INV_Misc_QuestionMark. Resolve candidates only
            -- when they are actual texture regions, otherwise descend once.
            local function resolveIconTexture(candidate)
                if not candidate then return nil; end
                if candidate.SetTexture then return candidate; end
                if candidate.GetName then
                    local childName = candidate:GetName();
                    local childTexture = childName and _G[childName .. "Icon"];
                    if childTexture and childTexture.SetTexture then
                        return childTexture;
                    end
                end
                return nil;
            end

            local texture;
            local name = frame.GetName and frame:GetName();
            if name then
                texture = resolveIconTexture(_G[name .. "Icon"]);
                if not texture then texture = resolveIconTexture(_G[name .. "icon"]); end
            end
            if not texture then texture = resolveIconTexture(frame.Icon); end
            if not texture then texture = resolveIconTexture(frame.icon); end

            if texture then
                texture:SetTexture("Interface\\ICONS\\" .. (icon or "INV_Misc_QuestionMark"));
                return texture;
            end
            -- Fall back to API-11 for stock frames; keep Extended failures
            -- non-fatal if a purely decorative frame has no icon region.
            local ok, result = pcall(oldSetupIconButton, frame, icon);
            if ok then return result; end
            return nil;
        end;
        TRP3X_WOTLK.setupIconButtonWrapperInstalled = true;
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
    local wotlkSoundIDPaths = {
        -- IDs used by the bundled 1.0.7 Simple Rifle demo. Wrath has no
        -- PlaySoundKitID API, so map them to the equivalent local MPQ sounds.
        [1147] = "Sound\\Item\\Weapons\\Gun\\GunLoad01.wav",
        [37089] = "Sound\\Item\\Weapons\\Gun\\GunFire01.wav",
    };
    if not music.playSoundID then
        function music.playSoundID(soundID, channel, source)
            if soundID == nil then return nil; end
            if type(soundID) == "number" and PlaySoundKitID then
                pcall(PlaySoundKitID, soundID);
            elseif type(soundID) == "number" and wotlkSoundIDPaths[soundID] and PlaySoundFile then
                pcall(PlaySoundFile, wotlkSoundIDPaths[soundID]);
            elseif type(soundID) ~= "number" and PlaySound then
                pcall(PlaySound, soundID);
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

    -- API-11 base TRP3 uses Utils.music.play()/stop() for character themes.
    -- Extended's history only sees the newer playMusic/playSoundID helpers, so
    -- wrap the existing base functions and record those plays too.
    if music.play and not music._trp3xWrappedBasePlay then
        music._trp3xWrappedBasePlay = music.play;
        music.play = function(value, ...)
            local result = music._trp3xWrappedBasePlay(value, ...);
            remember(value, type(value) == "number" and "SFX" or "Music", "TRP3 theme");
            return result;
        end
    end
    if music.stop and not music._trp3xWrappedBaseStop then
        music._trp3xWrappedBaseStop = music.stop;
        music.stop = function(...)
            local result = music._trp3xWrappedBaseStop(...);
            for id, handler in pairs(music._trp3xHandlers) do
                if handler.channel == "Music" then
                    music._trp3xHandlers[id] = nil;
                end
            end
            return result;
        end
    end
end




-- API-34 list boxes separate the visible box width from the popup offset.
-- API-11 accidentally reuses boxWidth as the popup X offset, which pushes
-- Extended's 180-300px workflow/condition menus far to the left. Keep this
-- helper Extended-only so stock TRP3 behavior is untouched.
function TRP3X_WOTLK.setupListBox(listBox, values, callback, defaultText, boxWidth, addCancel)
    assert(listBox and values, "Invalid arguments");
    local name = listBox.GetName and listBox:GetName();
    local button = name and _G[name .. "Button"];
    local textRegion = name and _G[name .. "Text"];
    local middle = name and _G[name .. "Middle"];
    assert(button, "Invalid arguments: listbox doesn't have a button");

    boxWidth = boxWidth or 115;
    listBox.values = values;
    listBox.callback = callback;

    -- Extended 1.0.7 uses deeply nested listbox structures for operands,
    -- effects, conditions and object selectors. API-11's setupListBox only
    -- searches the first level when updating the visible label. Our earlier
    -- compatibility wrapper accidentally made that worse by only firing the
    -- callback when a first-level entry matched, making nested selections look
    -- inert. Resolve labels recursively, but ALWAYS accept/callback a selected
    -- leaf value.
    local function findValueText(entries, wanted)
        for _, tab in pairs(entries or EMPTY) do
            if type(tab) == "table" then
                local value = tab[2];
                if type(value) == "table" then
                    local nested = findValueText(value, wanted);
                    if nested then return nested; end
                elseif value == wanted then
                    return tab[1] or tostring(wanted);
                end
            end
        end
    end

    local function setTextAndValue(value, fireCallback)
        local label = findValueText(values, value);
        if textRegion and label then textRegion:SetText(label); end
        listBox.selectedValue = value;
        if fireCallback and callback then callback(value, listBox); end
        return label ~= nil;
    end

    listBox.SetSelectedIndex = function(self, index)
        assert(self.values and self.values[index], "Array index out of bound");
        local entry = self.values[index];
        if textRegion then textRegion:SetText(entry[1] or ""); end
        self.selectedValue = entry[2];
        if callback then callback(entry[2], self); end
    end;
    listBox.GetSelectedValue = function(self) return self.selectedValue; end;
    listBox.SetSelectedValue = function(self, value) setTextAndValue(value, true); end;

    button:SetScript("OnClick", function()
        TRP3X_WOTLK.displayDropDown(button, values, function(value)
            setTextAndValue(value, true);
        end, -10, addCancel);
    end);

    if defaultText and textRegion then textRegion:SetText(defaultText); end
    if middle then middle:SetWidth(boxWidth); end
    if textRegion then textRegion:SetWidth(boxWidth - 20); end
end



-- Later FontString/SimpleHTML conveniences used by 1.0.7 but not guaranteed
-- on the 3.3.5 widget implementations.
function TRP3X_WOTLK.setAlphaGradient(region, start, length)
    if region and region.SetAlphaGradient then
        pcall(region.SetAlphaGradient, region, start or 0, length or 0);
    end
end
function TRP3X_WOTLK.enableHyperlinks(frame, enabled)
    if frame and frame.SetHyperlinksEnabled then
        pcall(frame.SetHyperlinksEnabled, frame, enabled and true or false);
    end
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

-- Tutorial helpers appeared after the base backport. Re-create the small
-- guided tooltip with the stock Wrath GameTooltip so the Extended Tools
-- tutorials can be enabled again.
API.navigation = API.navigation or {};
if not API.navigation.showTutorialTooltip then
    function API.navigation.showTutorialTooltip(anchor)
        if not anchor or not GameTooltip then return; end
        GameTooltip:Hide();
        GameTooltip:SetOwner(anchor, "ANCHOR_NONE");
        GameTooltip:ClearAllPoints();
        local arrow = anchor.arrow or "RIGHT";
        if arrow == "DOWN" then
            GameTooltip:SetPoint("BOTTOM", anchor, "TOP", 0, 8);
        elseif arrow == "UP" then
            GameTooltip:SetPoint("TOP", anchor, "BOTTOM", 0, -8);
        elseif arrow == "LEFT" then
            GameTooltip:SetPoint("RIGHT", anchor, "LEFT", -8, 0);
        else
            GameTooltip:SetPoint("LEFT", anchor, "RIGHT", 8, 0);
        end
        GameTooltip:SetText(anchor.text or "", 1, 1, 1, true);
        GameTooltip:Show();
    end
end
if not API.navigation.hideTutorialTooltip then
    function API.navigation.hideTutorialTooltip()
        if GameTooltip then GameTooltip:Hide(); end
    end
end

-- Fonts referenced by Extended documents/quest HTML on later clients.
-- Use the closest stock Wrath font objects when those globals are absent.
DestinyFontHuge = DestinyFontHuge or GameFontNormalHuge or GameFontNormalLarge;
QuestFont_Huge = QuestFont_Huge or GameFontNormalLarge or GameFontNormal;

-- Command-line fallback for ground-item search. Alpha 13 also restores the
-- historical Extended search button on its own compatibility action bar.
-- /trpext search remains useful for testing and accessibility.
SLASH_TRP3XEXT1 = "/trpext";
SLASH_TRP3XEXT2 = "/trptext"; -- common typo kept as a friendly alias
SLASH_TRP3XEXT3 = "/trpextended";
SlashCmdList["TRP3XEXT"] = function(msg)
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


-- Alpha 19: keep Extended browsers/panels on-screen on low-resolution Wrath
-- clients. API-11 browsers were designed around TRP3_PopupsFrame; Extended
-- reparents them to UIParent, so their original anchors and hide behavior are
-- no longer sufficient.
function TRP3X_WOTLK.positionPopup(frame, anchor, mode)
    if not frame then return; end
    frame:SetParent(UIParent);
    if frame.SetFrameStrata then frame:SetFrameStrata("DIALOG"); end
    if frame.SetClampedToScreen then frame:SetClampedToScreen(true); end
    frame:ClearAllPoints();

    local parent = anchor and anchor.parent;

    -- Quick Item Editor icon selection needs special handling on Wrath. Earlier
    -- builds keyed only off the Inventory page being visible and always placed
    -- the stock 420x400 icon browser *below the character model*. When Quick
    -- Create is open over that model, this can put the browser behind the
    -- editor and can push its lower rows / close button into unusable space.
    -- Keep Quick Create itself untouched and place the browser beside it when
    -- possible; if neither side has enough room, overlay it above the editor at
    -- a higher frame level so every icon and the X remain usable.
    local quickEditor = _G.TRP3_ItemQuickEditor;
    if mode == "inventory-icons" and quickEditor and quickEditor.IsShown and quickEditor:IsShown() then
        parent = quickEditor;
        local uiLeft = UIParent.GetLeft and UIParent:GetLeft() or 0;
        local uiRight = UIParent.GetRight and UIParent:GetRight() or (UIParent:GetWidth() or 1024);
        local parentLeft = parent.GetLeft and parent:GetLeft();
        local parentRight = parent.GetRight and parent:GetRight();
        local popupWidth = (frame.GetWidth and frame:GetWidth()) or 420;
        local gap = 8;
        local roomRight = parentRight and (uiRight - parentRight) or 0;
        local roomLeft = parentLeft and (parentLeft - uiLeft) or 0;

        if roomRight >= popupWidth + gap then
            frame:SetPoint("LEFT", parent, "RIGHT", gap, 0);
        elseif roomLeft >= popupWidth + gap then
            frame:SetPoint("RIGHT", parent, "LEFT", -gap, 0);
        else
            frame:SetPoint("CENTER", parent, "CENTER", 0, 0);
        end

        if frame.SetFrameLevel then
            local parentLevel = parent.GetFrameLevel and parent:GetFrameLevel() or 120;
            frame:SetFrameLevel(parentLevel + 40);
        end
        return;
    elseif mode == "inventory-icons" and _G.TRP3_InventoryPageMain and _G.TRP3_InventoryPageMain.Model then
        -- Preserve Alpha 18's working inventory-page placement for icon pickers
        -- that are not opened from Quick Create.
        parent = _G.TRP3_InventoryPageMain.Model;
        frame:SetPoint("TOP", parent, "BOTTOM", 0, -8);
        if frame.SetFrameLevel and parent.GetFrameLevel then
            frame:SetFrameLevel(parent:GetFrameLevel() + 20);
        end
        return;
    end
    if not parent or not parent.GetCenter then
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0);
        return;
    end

    local px, py = parent:GetCenter();
    local ux, uy = UIParent:GetCenter();
    local uiw, uih = UIParent:GetWidth(), UIParent:GetHeight();
    px, py, ux, uy = px or ux, py or uy, ux or 0, uy or 0;
    uiw, uih = uiw or 1024, uih or 768;

    -- Prefer vertical placement near the top/bottom edges, horizontal placement
    -- through the middle. This mirrors the way modern popovers avoid edges.
    if py > (uih * 0.62) then
        frame:SetPoint("TOP", parent, "BOTTOM", 0, -8);
    elseif py < (uih * 0.38) then
        frame:SetPoint("BOTTOM", parent, "TOP", 0, 8);
    elseif px >= ux then
        frame:SetPoint("RIGHT", parent, "LEFT", -8, 0);
    else
        frame:SetPoint("LEFT", parent, "RIGHT", 8, 0);
    end
end

function TRP3X_WOTLK.hideExtendedPopups()
    for _, name in ipairs({"TRP3_IconBrowser", "TRP3_ColorBrowser", "TRP3_ImageBrowser", "TRP3_ObjectBrowser", "TRP3X_WotLKCompanionBrowser"}) do
        local frame = _G[name];
        if frame and frame.Hide then frame:Hide(); end
    end
    if API.popup and API.popup.POPUPS then
        for _, entry in pairs(API.popup.POPUPS) do
            if entry and entry.frame and entry.frame.Hide then entry.frame:Hide(); end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Native Wrath companion browser for Extended 1.0.7's Summon Mount editor.
-- Retail 1.0.7 opened TRP3's later companion-journal browser. 3.3.5 has no
-- journal UI, but it does expose the player's learned mounts through the old
-- GetNumCompanions/GetCompanionInfo API, which is sufficient to restore the
-- original editor's selection workflow without changing the saved effect.
-- ---------------------------------------------------------------------------
local function trp3xCollectWrathMounts(filterText)
    local result = {};
    filterText = string.lower(tostring(filterText or ""));
    if not GetNumCompanions or not GetCompanionInfo then return result; end
    local count = GetNumCompanions("MOUNT") or 0;
    for index = 1, count do
        local creatureID, name, spellID, icon, active = GetCompanionInfo("MOUNT", index);
        name = name or (GetSpellInfo and spellID and GetSpellInfo(spellID)) or ("Mount " .. index);
        if filterText == "" or string.find(string.lower(name or ""), filterText, 1, true) then
            table.insert(result, {
                index = index,
                id = spellID or creatureID or index,
                creatureID = creatureID,
                name = name,
                spellID = spellID,
                icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
                active = active and true or false,
            });
        end
    end
    table.sort(result, function(a, b) return string.lower(a.name or "") < string.lower(b.name or ""); end);
    return result;
end

function TRP3X_WOTLK.showCompanionBrowser(anchor, onSelect, companionType)
    -- Extended 1.0.7 only uses this popup for the Summon Mount effect. Keep the
    -- type check explicit so a future pet/critter editor cannot silently use
    -- the wrong collection.
    if companionType and API.ui and API.ui.misc and API.ui.misc.TYPE_MOUNT and companionType ~= API.ui.misc.TYPE_MOUNT then
        if API.popup and API.popup.showAlertPopup then
            API.popup.showAlertPopup("This 3.3.5 companion picker currently supports mounts only.");
        end
        return nil;
    end

    local browser = _G.TRP3X_WotLKCompanionBrowser;
    if not browser then
        browser = CreateFrame("Frame", "TRP3X_WotLKCompanionBrowser", UIParent);
        browser:SetWidth(390); browser:SetHeight(414);
        browser:SetFrameStrata("DIALOG");
        browser:SetClampedToScreen(true);
        browser:EnableMouse(true);
        if browser.SetBackdrop then
            browser:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            });
        end

        browser.title = browser:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge");
        browser.title:SetPoint("TOPLEFT", 18, -16);
        browser.title:SetText("Select a Wrath mount");

        browser.close = CreateFrame("Button", nil, browser, "UIPanelCloseButton");
        browser.close:SetPoint("TOPRIGHT", -4, -4);
        browser.close:SetScript("OnClick", function() browser:Hide(); end);

        browser.filter = CreateFrame("EditBox", "TRP3X_WotLKCompanionFilter", browser, "InputBoxTemplate");
        browser.filter:SetWidth(238); browser.filter:SetHeight(20);
        browser.filter:SetPoint("TOPLEFT", 20, -47);
        browser.filter:SetAutoFocus(false);
        browser.filter:SetMaxLetters(60);

        browser.filterLabel = browser:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
        browser.filterLabel:SetPoint("BOTTOMLEFT", browser.filter, "TOPLEFT", 0, 2);
        browser.filterLabel:SetText("Filter");

        browser.pageText = browser:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
        browser.pageText:SetPoint("TOPRIGHT", -22, -53);

        browser.rows = {};
        for i = 1, 10 do
            local row = CreateFrame("Button", nil, browser);
            row:SetWidth(350); row:SetHeight(29);
            row:SetPoint("TOPLEFT", 20, -80 - ((i - 1) * 30));
            row:RegisterForClicks("LeftButtonUp");
            row.icon = row:CreateTexture(nil, "ARTWORK");
            row.icon:SetWidth(24); row.icon:SetHeight(24);
            row.icon:SetPoint("LEFT", 2, 0);
            row.name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal");
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0);
            row.name:SetPoint("RIGHT", row, "RIGHT", -70, 0);
            row.name:SetJustifyH("LEFT");
            row.status = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
            row.status:SetPoint("RIGHT", -4, 0);
            local hl = row:CreateTexture(nil, "HIGHLIGHT");
            hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight");
            hl:SetBlendMode("ADD");
            hl:SetAllPoints(row);
            row:SetScript("OnClick", function(self)
                local entry = self.entry;
                if not entry then return; end
                if browser.onSelect then
                    local info = string.format("Wrath mount%s", entry.spellID and (" - spell " .. entry.spellID) or "");
                    browser.onSelect({entry.name, entry.icon, info, "Mount", entry.spellID, entry.id});
                end
                browser:Hide();
            end);
            browser.rows[i] = row;
        end

        browser.prev = CreateFrame("Button", nil, browser, "UIPanelButtonTemplate");
        browser.prev:SetWidth(90); browser.prev:SetHeight(22);
        browser.prev:SetPoint("BOTTOMLEFT", 72, 17);
        browser.prev:SetText("Previous");
        browser.next = CreateFrame("Button", nil, browser, "UIPanelButtonTemplate");
        browser.next:SetWidth(90); browser.next:SetHeight(22);
        browser.next:SetPoint("BOTTOMRIGHT", -72, 17);
        browser.next:SetText("Next");

        browser.page = 1;
        browser.refresh = function(self, resetPage)
            if resetPage then self.page = 1; end
            self.entries = trp3xCollectWrathMounts(self.filter:GetText());
            local pageSize = #self.rows;
            local pages = math.max(1, math.ceil(#self.entries / pageSize));
            if self.page > pages then self.page = pages; end
            if self.page < 1 then self.page = 1; end
            local first = ((self.page - 1) * pageSize) + 1;
            for i, row in ipairs(self.rows) do
                local entry = self.entries[first + i - 1];
                row.entry = entry;
                if entry then
                    row.icon:SetTexture(entry.icon);
                    row.name:SetText(entry.name or "Unknown mount");
                    row.status:SetText(entry.active and "Active" or "");
                    row:Show();
                else
                    row:Hide();
                end
            end
            self.pageText:SetText(string.format("%d/%d  (%d)", self.page, pages, #self.entries));
            if self.page <= 1 then self.prev:Disable(); else self.prev:Enable(); end
            if self.page >= pages then self.next:Disable(); else self.next:Enable(); end
        end;

        browser.prev:SetScript("OnClick", function()
            browser.page = browser.page - 1; browser:refresh(false);
        end);
        browser.next:SetScript("OnClick", function()
            browser.page = browser.page + 1; browser:refresh(false);
        end);
        browser.filter:SetScript("OnTextChanged", function() browser:refresh(true); end);
        browser:EnableMouseWheel(true);
        browser:SetScript("OnMouseWheel", function(self, delta)
            if delta > 0 and self.page > 1 then self.page = self.page - 1; self:refresh(false);
            elseif delta < 0 then
                local pages = math.max(1, math.ceil(#(self.entries or {}) / #self.rows));
                if self.page < pages then self.page = self.page + 1; self:refresh(false); end
            end
        end);
    end

    browser.onSelect = onSelect;
    browser.filter:SetText("");
    browser.page = 1;
    browser:refresh(true);
    TRP3X_WOTLK.positionPopup(browser, anchor);
    if _G.TRP3_PopupsFrame then _G.TRP3_PopupsFrame:Hide(); end
    browser:Show();
    return browser;
end

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
        API.popup.showIconBrowser(args[1], args[2], false);
        local browser = _G.TRP3_IconBrowser;
        if browser then
            local specialMode;
            if _G.TRP3_InventoryPageMain and _G.TRP3_InventoryPageMain:IsShown() then specialMode = "inventory-icons"; end
            TRP3X_WOTLK.positionPopup(browser, anchor, specialMode);
            if _G.TRP3_PopupsFrame then _G.TRP3_PopupsFrame:Hide(); end
            browser:Show();
        end
        return browser;
    elseif popupID == API.popup.MUSICS and API.popup.showMusicBrowser then
        return API.popup.showMusicBrowser(args[1]);
    elseif popupID == API.popup.COMPANIONS then
        return TRP3X_WOTLK.showCompanionBrowser(anchor, args[1], args[3]);
    end
    local entry = API.popup.POPUPS[popupID];
    if entry and entry.frame then
        -- Extended custom popup frames are not children of API-11's TRP3_PopupsFrame.
        -- Calling oldShowPopup() here produces an empty modal in front of the actual
        -- browser. Hide the old container and show the custom frame directly instead.
        if oldHidePopups then oldHidePopups(); end
        entry.frame:Show();
        if entry.frame.SetFrameStrata then entry.frame:SetFrameStrata("DIALOG"); end
        entry.frame:ClearAllPoints();
        if popupID == API.popup.OBJECTS then
            -- The historical Create-From anchor can place this 450px browser
            -- beyond the right edge on 4:3 / low-resolution Wrath clients.
            entry.frame:SetParent(UIParent);
            if entry.frame.SetClampedToScreen then entry.frame:SetClampedToScreen(true); end
            entry.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0);
            if entry.frame.SetFrameLevel then entry.frame:SetFrameLevel(100); end
        elseif anchor and anchor.parent then
            TRP3X_WOTLK.positionPopup(entry.frame, anchor);
            if entry.frame.SetFrameLevel and anchor.parent.GetFrameLevel then
                entry.frame:SetFrameLevel(anchor.parent:GetFrameLevel() + 20);
            end
        else
            TRP3X_WOTLK.positionPopup(entry.frame);
        end
        if entry.showMethod then return entry.showMethod(unpack(args)); end
    end
end
API.popup.hidePopups = function()
    if oldHidePopups then oldHidePopups(); end
    TRP3X_WOTLK.hideExtendedPopups();
end;


-- Alpha 28: Extended-only dropdown positioning.
-- Earlier alphas replaced TRP3_API.ui.listbox.displayDropDown globally. That
-- fixed Extended's API-34 menus, but it also meant stock TRP3/third-party code
-- could inherit Extended's zero-offset/re-anchoring behavior. Keep the public
-- API-11 function intact and route only Extended-owned menus through this
-- wrapper.
TRP3X_WOTLK._baseDisplayDropDown = TRP3X_WOTLK._baseDisplayDropDown or API.ui.listbox.displayDropDown;

local function trp3xClampExtendedDropDownLevel(list)
    if not list then return; end
    if list.SetClampedToScreen then list:SetClampedToScreen(true); end
    local right = list.GetRight and list:GetRight();
    local screenRight = UIParent.GetRight and UIParent:GetRight();
    if right and screenRight and right > screenRight - 4 then
        local point, relativeTo, relativePoint, x, y = list:GetPoint(1);
        if relativeTo then
            list:ClearAllPoints();
            list:SetPoint("TOPRIGHT", relativeTo, "TOPLEFT", -4, y or 0);
        end
    end
end

function TRP3X_WOTLK.displayDropDown(anchor, values, callback, space, addCancel)
    local base = TRP3X_WOTLK._baseDisplayDropDown;
    if not base then return; end

    -- API-11 incorrectly treats Extended's width/spacing argument as a large X
    -- offset. Zero is intentional here, but only for Extended callers.
    base(anchor, values, callback, 0, addCancel);

    local root = _G.DropDownList1;
    if root then
        root._trp3xExtendedRoot = true;
        if root.SetClampedToScreen then root:SetClampedToScreen(true); end
        if root:IsShown() and anchor and anchor.GetCenter then
            local ax, ay = anchor:GetCenter();
            local ux, uy = UIParent:GetCenter();
            local h = UIParent:GetHeight() or 768;
            ax, ay, ux = ax or ux, ay or uy, ux or 0;
            root:ClearAllPoints();
            if ay and ay > h * 0.55 then
                if ax and ax > ux then root:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4);
                else root:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4); end
            else
                if ax and ax > ux then root:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 4);
                else root:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 4); end
            end
        end
    end
    for i = 1, 4 do
        trp3xClampExtendedDropDownLevel(_G["DropDownList" .. i]);
    end
end

-- UIDropDownMenu creates deeper levels lazily. Hooks are global frames, but
-- they are inert unless level 1 was opened by TRP3X_WOTLK.displayDropDown().
do
    if not TRP3X_WOTLK.extendedDropDownHooksInstalled then
        local root = _G.DropDownList1;
        if root and root.HookScript then
            root:HookScript("OnHide", function(self) self._trp3xExtendedRoot = nil; end);
        end
        for level = 2, 4 do
            local list = _G["DropDownList" .. level];
            if list and list.HookScript then
                list:HookScript("OnShow", function(self)
                    local owner = _G.DropDownList1;
                    if owner and owner._trp3xExtendedRoot and owner:IsShown() then
                        trp3xClampExtendedDropDownLevel(self);
                    end
                end);
            end
        end
        TRP3X_WOTLK.extendedDropDownHooksInstalled = true;
    end
end

-- ---------------------------------------------------------------------------
-- Minimal breadcrumb navbar functions used by Extended and Tools.
-- ---------------------------------------------------------------------------
local function navEnsure(nav)
    nav._trp3xButtons = nav._trp3xButtons or {};
    -- API-34's navbar exposes the active breadcrumb buttons as .navList.
    -- Tools indexes this immediately after NavBar_AddButton().
    nav.navList = nav._trp3xButtons;
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
    if data then
        -- Later NavBar buttons copy payload fields directly onto the widget.
        -- Quest log callbacks read button.id/button.name rather than .data.
        for key, value in pairs(data) do button[key] = value; end
    end
    local fullText = (data and data.name) or "?";
    button:SetText(fullText);
    local fs = button.GetFontString and button:GetFontString();
    if fs then
        fs:SetWidth(82);
        if fs.SetWordWrap then fs:SetWordWrap(false); end
        local shown = fullText;
        while #shown > 4 and fs.GetStringWidth and fs:GetStringWidth() > 82 do
            shown = shown:sub(1, #shown - 1);
            button:SetText(shown .. "...");
        end
    end
    button:SetScript("OnClick", data and data.OnClick or nil);
    if index == 1 then
        button:SetPoint("LEFT", nav.home or nav, "RIGHT", 8, 0);
    else
        button:SetPoint("LEFT", buttons[index - 1], "RIGHT", 8, 0);
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
