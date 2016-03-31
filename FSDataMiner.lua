------------------------------------------------------------------------------------------------
-- FSDataMiner.lua
------------------------------------------------------------------------------------------------
require "Window"

-----------------------------------------------------------------------------------------------
-- FSDataMiner Definition
-----------------------------------------------------------------------------------------------
local FSDataMiner= {}
local Utils = Apollo.GetPackage("SimpleUtils-1.0").tPackage
local ZoneMap

-----------------------------------------------------------------------------------------------
-- FSDataMiner constants
-----------------------------------------------------------------------------------------------
local Major, Minor, Patch, Suffix = 1, 1, 0, 0
local AddonName = "FSDataMiner"
local FSDataMiner_CURRENT_VERSION = string.format("%d.%d.%d", Major, Minor, Patch)

local tDefaultSettings = {
  version = FSDataMiner_CURRENT_VERSION,
  user = {
    debug = false
  },
  positions = {
    main = nil
  },
  zones = {
  },
  continents = {
  },
  itemTypes = {
  },
  itemTypeExamples = {
  }
}

local tDefaultState = {
  isOpen = false,
  windows = {           -- These store windows for lists
    main = nil
  }
}

-----------------------------------------------------------------------------------------------
-- FSDataMiner Constructor
-----------------------------------------------------------------------------------------------
function FSDataMiner:new(o)
  o = o or {}
  setmetatable(o, self)
  self.__index = self

  -- Saved and Restored values are stored here.
  o.settings = shallowcopy(tDefaultSettings)
  -- Volatile values are stored here. These are impermanent and not saved between sessions
  o.state = shallowcopy(tDefaultState)

  return o
end

-----------------------------------------------------------------------------------------------
-- FSDataMiner Init
-----------------------------------------------------------------------------------------------
function FSDataMiner:Init()
  local bHasConfigureFunction = true
  local strConfigureButtonText = AddonName
  local tDependencies = {
    "ZoneMap"
    -- "ZoneMap",
  }
  Apollo.RegisterAddon(self, bHasConfigureFunction, strConfigureButtonText, tDependencies)

  self.settings = shallowcopy(tDefaultSettings)
  -- Volatile values are stored here. These are impermanent and not saved between sessions
  self.state = shallowcopy(tDefaultState)
end

-----------------------------------------------------------------------------------------------
-- FSDataMiner OnLoad
-----------------------------------------------------------------------------------------------
function FSDataMiner:OnLoad()
  self.xmlDoc = XmlDoc.CreateFromFile("FSDataMiner.xml")
  self.xmlDoc:RegisterCallback("OnDocLoaded", self)

  Apollo.RegisterEventHandler("Generic_FSDataMiner", "OnToggleFSDataMiner", self)
  Apollo.RegisterEventHandler("InterfaceMenuListHasLoaded", "OnInterfaceMenuListHasLoaded", self)

  Apollo.RegisterSlashCommand("dataminer", "OnSlashCommand", self)

  -- Events to track
  Apollo.RegisterEventHandler("SubZoneChanged", "OnZoneChanging", self)
  Apollo.RegisterEventHandler("LootedItem", "OnLootedItem", self)
  Apollo.RegisterEventHandler("LootAssigned", "OnLootAssigned", self)
  Apollo.RegisterEventHandler("LootRollWon", "OnLootRollWon", self)
end

-----------------------------------------------------------------------------------------------
-- FSDataMiner OnDocLoaded
-----------------------------------------------------------------------------------------------
function FSDataMiner:OnDocLoaded()
  if self.xmlDoc == nil then
    return
  end

  self.state.windows.main = Apollo.LoadForm(self.xmlDoc, "MainWindow", nil, self)
  self.state.windows.main:Show(false)

  -- Restore positions and junk
  self:RefreshUI()
end

-----------------------------------------------------------------------------------------------
-- FSDataMiner OnInterfaceMenuListHasLoaded
-----------------------------------------------------------------------------------------------
function FSDataMiner:OnInterfaceMenuListHasLoaded()
  Event_FireGenericEvent("InterfaceMenuList_NewAddOn", AddonName, {"Generic_ToggleAddon", "", nil})

  -- Report Addon to OneVersion
  Event_FireGenericEvent("OneVersion_ReportAddonInfo", AddonName, Major, Minor, Patch, Suffix, false)
end

-----------------------------------------------------------------------------------------------
-- FSDataMiner OnSlashCommand
-----------------------------------------------------------------------------------------------
-- Handle slash commands
function FSDataMiner:OnSlashCommand(cmd, params)
  args = params:lower():split("[ ]+")

  if args[1] == "debug" then
    self:ToggleDebug()
  elseif args[1] == "show" then
    self:OnToggleFSDataMiner()
  elseif args[1] == "defaults" then
    self:LoadDefaults()
  elseif args[1] == "preload" then
    self:PreLoadData()
  else
    Utils:cprint("FSDataMiner v" .. self.settings.version)
    Utils:cprint("Usage:  /dataminer <command>")
    Utils:cprint("====================================")
    Utils:cprint("   show           Open Rules Window")
    Utils:cprint("   debug          Toggle Debug")
    Utils:cprint("   defaults       Loads defaults")
  end
end

-----------------------------------------------------------------------------------------------
-- Save/Restore functionality
-----------------------------------------------------------------------------------------------
function FSDataMiner:OnSave(eType)
  if eType ~= GameLib.CodeEnumAddonSaveLevel.Character then return end

  return deepcopy(self.settings)
end

function FSDataMiner:OnRestore(eType, tSavedData)
  if eType ~= GameLib.CodeEnumAddonSaveLevel.Character then return end

  if tSavedData and tSavedData.user then
    -- Copy the settings wholesale
    self.settings = deepcopy(tSavedData)

    -- Fill in any missing values from the default options
    -- This Protects us from configuration additions in the future versions
    for key, value in pairs(tDefaultSettings) do
      if self.settings[key] == nil then
        self.settings[key] = deepcopy(tDefaultSettings[key])
      end
    end

    -- This section is for converting between versions that saved data differently

    -- Now that we've turned the save data into the most recent version, set it
    self.settings.version = FSDataMiner_CURRENT_VERSION

  else
    self.tConfig = deepcopy(tDefaultOptions)
  end
end

-----------------------------------------------------------------------------------------------
-- Utility functionality
-----------------------------------------------------------------------------------------------
function FSDataMiner:ToggleDebug()
  if self.settings.user.debug then
    self:PrintDB("Debug turned off")
    self.settings.user.debug = false
  else
    self.settings.user.debug = true
    self:PrintDB("Debug turned on")
  end
end

function FSDataMiner:PrintDB(str)
  if self.settings.user.debug then
    Utils:debug(string.format("[%s]: %s", AddonName, str))
  end
end

---------------------------------------------------------------------------------------------------
-- FSDataMiner General UI Functions
---------------------------------------------------------------------------------------------------
function FSDataMiner:OnToggleFSDataMiner()
  if self.state.isOpen == true then
    self.state.isOpen = false
    self:SaveLocation()
    self:CloseMain()
  else
    self.state.isOpen = true
    self.state.windows.main:Invoke() -- show the window
  end
end

function FSDataMiner:SaveLocation()
  self.settings.positions.main = self.state.windows.main:GetLocation():ToTable()
end

function FSDataMiner:CloseMain()
  self.state.windows.main:Close()
end

function FSDataMiner:OnFSDataMinerClose( wndHandler, wndControl, eMouseButton )
  self.state.isOpen = false
  self:SaveLocation()
  self:CloseMain()
end

function FSDataMiner:OnFSDataMinerClosed( wndHandler, wndControl )
  self:SaveLocation()
  self.state.isOpen = false
end

---------------------------------------------------------------------------------------------------
-- FSDataMiner RefreshUI
---------------------------------------------------------------------------------------------------
function FSDataMiner:RefreshUI()
  -- Location Restore
  if self.settings.positions.main ~= nil and self.settings.positions.main ~= {} then
    locSavedLoc = WindowLocation.new(self.settings.positions.main)
    self.state.windows.main:MoveToLocation(locSavedLoc)
  end
end

function FSDataMiner:LoadDefaults()
  -- Load Defaults here
  self:RefreshUI()
end

function FSDataMiner:OnZoneChanging()
  local zoneMap = GameLib.GetCurrentZoneMap()
  -- Add Zone to the Zone list
  if not zoneMap then
    return
  end
  if not self.settings.zones then
    self.settings.zones = {}
  end

  self.settings.zones[zoneMap.id] = {
    continentId = zoneMap.continentId,
    name = zoneMap.strName
  }
end

-----------------------------------------------------------------------------------------------
-- FSDataMiner OnLootedItem
-----------------------------------------------------------------------------------------------
function FSDataMiner:OnLootedItem(itemInstance, itemCount)
  self:AddItemType(itemInstance)
end

-----------------------------------------------------------------------------------------------
-- FSDataMiner OnLootRollWon -- (For Winning Loot Roll) -- Hooked from NeedVsGreed
-----------------------------------------------------------------------------------------------
function FSDataMiner:OnLootRollWon(itemLooted, strWinner, bNeed)
  self:AddItemType(itemInstance)
end

-----------------------------------------------------------------------------------------------
-- FSDataMiner OnLootAssigned (MasterLooting)
-----------------------------------------------------------------------------------------------
function FSDataMiner:OnLootAssigned(itemInstance, strLooter)
  self:AddItemType(itemInstance)
end

function FSDataMiner:AddItemType(item)
  if not item then
    return
  end
  local itemTypeID, itemTypeName = item:GetItemType(), item:GetItemTypeName()
  -- Add ItemType to the ItemType list
  if not self.settings.itemTypes then
    self.settings.itemTypes = {}
  end

  self.settings.itemTypes[itemTypeID] = itemTypeName
end

function FSDataMiner:PreLoadData()
  ZoneMap = Apollo.GetAddon("ZoneMap")
  -- Load zones
  for i=1,1000 do
    local zone = ZoneMap.wndZoneMap:GetZoneInfo(i)
    if zone ~= nil then
      self.settings.zones[zone.id] = {
        continentId = zone.continentId,
        name = zone.strName
      }
    end
  end
  -- Load Continents
  if not self.settings.continents then
    self.settings.continents = {}
  end
  for i=1,1000 do
    local continent = ZoneMap.wndZoneMap:GetContinentInfo(i)
    if continent ~= nil and continent.id ~= nil then
      self.settings.continents[continent.id] = continent.strName
    end
  end

  if not self.settings.itemTypeExamples then
    self.settings.itemTypeExamples = {}
  end
  for i=1,100000 do
    local item = Item.GetDataFromId(i)
    if item ~= nil then
      self:AddItemType(item)
      self.settings.itemTypeExamples[item:GetItemType()] = item:GetName()
    end
  end
end
-----------------------------------------------------------------------------------------------
-- FSDataMinerInstance
-----------------------------------------------------------------------------------------------
local FSDataMinerInst = FSDataMiner:new()
FSDataMinerInst:Init()
