----------------------------------------------------------------------------------
-- Total RP 3 Extended WotLK map-distance compatibility
--
-- Extended 1.0.7 was written against UnitPosition() world coordinates in yards.
-- Wrath 3.3.5 only exposes normalized zone-map coordinates to addons, and the
-- compatibility UnitPosition() stores those as 0..10000 synthetic coordinates.
-- This file converts differences in that saved coordinate space back to yards.
--
-- Zone dimensions are the 3.3.5-era Astrolabe map measurements (Rev 107,
-- 2009-08-05), rounded only for storage here. The original library documents
-- these values as distances across the world maps in game yards.
----------------------------------------------------------------------------------

TRP3X_WOTLK = TRP3X_WOTLK or {};

local sqrt = math.sqrt;
local abs = math.abs;

-- mapFileName -> { widthYards, heightYards }
-- GetMapInfo() returns these locale-independent map file names on 3.3.5.
local MAP_YARD_SIZE = {
    -- Kalimdor
    Ashenvale = {5766.729, 3843.722},
    Aszhara = {5070.887, 3381.226},
    AzuremystIsle = {4070.877, 2714.564},
    Barrens = {10133.442, 6756.202},
    BloodmystIsle = {3262.536, 2174.984},
    Darkshore = {6550.071, 4366.635},
    Darnassis = {1058.344, 705.724},
    Desolace = {4495.883, 2997.895},
    Durotar = {5287.556, 3524.975},
    Dustwallow = {5250.057, 3499.975},
    Felwood = {5750.063, 3833.306},
    Feralas = {6950.075, 4633.300},
    Moonglade = {2308.360, 1539.572},
    Mulgore = {5137.556, 3424.976},
    Ogrimmar = {1402.619, 935.410},
    Silithus = {3483.372, 2322.901},
    StonetalonMountains = {4883.386, 3256.227},
    Tanaris = {6900.075, 4599.967},
    Teldrassil = {5091.720, 3393.726},
    TheExodar = {1056.783, 704.683},
    ThousandNeedles = {4400.047, 2933.312},
    ThunderBluff = {1043.761, 695.829},
    UngoroCrater = {3700.040, 2466.649},
    Winterspring = {7100.077, 4733.299},

    -- Eastern Kingdoms
    Alterac = {2799.999, 1866.674},
    Arathi = {3600.000, 2400.009},
    Badlands = {2487.501, 1658.340},
    BlastedLands = {3349.999, 2233.342},
    BurningSteppes = {2929.167, 1952.091},
    DeadwindPass = {2499.999, 1666.674},
    DunMorogh = {4925.001, 3283.346},
    Duskwood = {2699.999, 1800.007},
    EasternPlaguelands = {4031.249, 2687.510},
    Elwynn = {3470.833, 2314.592},
    EversongWoods = {4925.003, 3283.346},
    Ghostlands = {3300.002, 2200.009},
    Hilsbrad = {3199.999, 2133.342},
    Hinterlands = {3849.999, 2566.677},
    Ironforge = {790.625, 527.607},
    LochModan = {2758.333, 1839.589},
    Redridge = {2170.833, 1447.922},
    SearingGorge = {2231.250, 1487.505},
    SilvermoonCity = {1211.459, 806.774},
    Silverpine = {4199.999, 2800.011},
    Stormwind = {1737.501, 1158.338},
    Stranglethorn = {6381.248, 4254.183},
    Sunwell = {3327.081, 2218.758},
    SwampOfSorrows = {2293.751, 1529.174},
    Tirisfal = {4518.748, 3012.512},
    Undercity = {959.375, 640.107},
    WesternPlaguelands = {4300.000, 2866.678},
    Westfall = {3500.000, 2333.343},
    Wetlands = {4135.416, 2756.261},

    -- Outland
    BladesEdgeMountains = {5424.971, 3616.554},
    Hellfire = {5164.556, 3443.642},
    Nagrand = {5524.971, 3683.218},
    Netherstorm = {5574.971, 3716.551},
    ShadowmoonValley = {5499.971, 3666.552},
    ShattrathCity = {1306.243, 870.806},
    TerokkarForest = {5399.972, 3599.888},
    Zangarmarsh = {5027.057, 3351.979},

    -- Northrend
    BoreanTundra = {5764.582, 3843.765},
    CrystalsongForest = {2722.917, 1814.590},
    Dalaran = {830.015, 553.342},
    Dragonblight = {5608.332, 3739.598},
    GrizzlyHills = {5249.999, 3500.014},
    HrothgarsLanding = {3677.083, 2452.094},
    HowlingFjord = {6045.832, 4031.265},
    IcecrownGlacier = {6270.833, 4181.267},
    LakeWintergrasp = {2974.999, 1983.341},
    SholazarBasin = {4356.250, 2904.178},
    TheStormPeaks = {7112.498, 4741.685},
    ZulDrak = {4993.749, 3329.180},
};

local mapFileByAreaID = {};

local function cacheCurrentMapFile()
    if not GetCurrentMapAreaID or not GetMapInfo then return nil; end
    local areaID = GetCurrentMapAreaID();
    local mapFile = GetMapInfo();
    if areaID and areaID > 0 and mapFile and mapFile ~= "" then
        mapFileByAreaID[areaID] = mapFile;
    end
    return mapFile;
end

local function getMapFileForAreaID(areaID)
    if not areaID or areaID <= 0 then
        return GetMapInfo and GetMapInfo() or nil;
    end

    local cached = mapFileByAreaID[areaID];
    if cached then return cached; end

    local currentArea = GetCurrentMapAreaID and GetCurrentMapAreaID();
    if currentArea == areaID then
        return cacheCurrentMapFile();
    end

    -- SetMapByID exists in the 3.3.5 TRP3 base. Temporarily switch the map API
    -- to the requested WorldMapAreaID, read its locale-independent file name,
    -- then restore the user's previous map immediately. Results are cached so
    -- this normally happens only once per map for the whole session.
    if SetMapByID and GetMapInfo and GetCurrentMapAreaID then
        local restoreArea = currentArea;
        SetMapByID(areaID);
        local resolvedArea = GetCurrentMapAreaID();
        local mapFile = GetMapInfo();
        if resolvedArea and mapFile and mapFile ~= "" then
            mapFileByAreaID[resolvedArea] = mapFile;
        end
        if restoreArea and restoreArea > 0 then
            SetMapByID(restoreArea);
        elseif SetMapToCurrentZone then
            SetMapToCurrentZone();
        end
        return mapFileByAreaID[areaID] or mapFile;
    end

    return nil;
end

function TRP3X_WOTLK.getMapYardSize(areaID)
    local mapFile = getMapFileForAreaID(areaID);
    local size = mapFile and MAP_YARD_SIZE[mapFile];
    if size then
        return size[1], size[2], mapFile;
    end
    return nil, nil, mapFile;
end

-- Convert two positions saved by the WotLK UnitPosition shim back into a real
-- in-zone yard distance. Returns (distance, true) when map dimensions are
-- known. Unknown/custom/instance maps return the legacy synthetic distance and
-- false so callers can use a conservative compatibility fallback.
function TRP3X_WOTLK.getMapDistanceYards(areaID, posY, posX, otherY, otherX)
    posY, posX, otherY, otherX = tonumber(posY), tonumber(posX), tonumber(otherY), tonumber(otherX);
    if not posY or not posX or not otherY or not otherX then return nil, false; end

    local width, height = TRP3X_WOTLK.getMapYardSize(areaID);
    if width and height and width > 0 and height > 0 then
        local dxYards = ((posX - otherX) / 10000) * width;
        local dyYards = ((posY - otherY) / 10000) * height;
        return sqrt(dxYards * dxYards + dyYards * dyYards), true;
    end

    local dx = posX - otherX;
    local dy = posY - otherY;
    return sqrt(dx * dx + dy * dy), false;
end

-- Cache the player's current area immediately when this file loads. This is
-- harmless if the world is not ready yet; normal proximity calls cache it too.
cacheCurrentMapFile();
