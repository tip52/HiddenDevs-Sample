-- NOTICE:
-- YOU MUST GO ON ONE OF THE PADS IN THE LOBBY AREA
-- TO GET TO THE GAME PART WHERE THIS SCRIPT IS USED
-- (THE TTD GAME PART)






-- Variables
-- Servces
local players = game:GetService("Players")
local rep = game:WaitForChild("ReplicatedStorage")

-- Modules
local repstore = game:WaitForChild("ServerStorage")
local module = require(repstore:WaitForChild("TDModule"))
local waveData = require(repstore:WaitForChild("waveData"))
local data2 = require(rep:WaitForChild("enemyData"))

-- Constants
local constants = require(rep:WaitForChild("CONSTANTS"))

-- Remotes
local remotes = rep:WaitForChild("remotes")
local skipEvent = remotes:WaitForChild("skipWave")
local canSkipEvent = remotes:WaitForChild("canSkip")
local endscreenData = remotes:WaitForChild("getEndscreenData")
local endEvent = remotes:WaitForChild("endEvent")
local replayEvent = remotes:WaitForChild("replayEvent")
local getCash = remotes:WaitForChild("getCash")

-- Datastore variables
local DataStoreService = game:GetService("DataStoreService")
local CoinsDataStore = DataStoreService:GetDataStore("CoinsData")
local XPDataStore = DataStoreService:GetDataStore("XPData")
local DamageDataStore = DataStoreService:GetDataStore("DamageData")

-- keep track of when we started to send back when the round is finished
_G.startTick = tick()

-- wait for variables script to run
-- -> sets these variables: _G.map, _G.chapter, _G.movepointsFolder, _G.maxHealth, _G.health
repeat
	wait()
until _G.variablesLoaded

-- datastore functions
function getPlayerTotalDamage(player)
	-- _G.globalDamage is handled and updated by damageHandler
	-- _G.globalDamage[player][troop] = {[1]=tick(),[2]=0} -- how it is set in damageHandler

	if not _G.globalDamage[player] then
		return 0
	end

	local total = 0

	-- get all the damage from each troop, add it up, and return
	for _, troop in _G.globalDamage[player] do
		-- ABS as the damage is stored as a negative number, but we want to return a positive number for the end screen
		total += math.abs(troop[2]) -- troop[2] is the total damage the troop has done
	end
	return total
end

local function updateDataStore(dataStore, userId, amount)
	-- check current value for player, pcall incase it fails
	local success, currentValue = pcall(function()
		return dataStore:GetAsync(userId)
	end)

	if success then
		currentValue = currentValue or 0

		-- actually update it to the params
		pcall(function()
			dataStore:SetAsync(userId, currentValue + amount)
		end)
	end
end

local function getDataStoreValue(dataStore, userId)
	-- get data from datastore
	local success, value = pcall(function()
		return dataStore:GetAsync(userId)
	end)

	-- returning and error handling if user isnt in database
	if success then
		return value or 0
	else
		warn("failed to get data for user:", userId)
		return nil
	end
end

-- _G.map is a string
-- find the map, move to workspace
local mapInstance = rep:WaitForChild("maps"):FindFirstChild(_G.map)
local entities = rep:WaitForChild("entities")
mapInstance.Parent = workspace

-- part with the gui that displays your health
local finishBoard = workspace:WaitForChild(_G.map).finish.finish.BillboardGui.Frame.TextLabel

-- put movepoints in workspace (where the enemies will move to for this map)
for _, point in next, _G.movepointsFolder:GetChildren() do
	point.Parent = workspace.GameData.Movepoints
end

local startAnglePos = CFrame.Angles(0, -131, 0)
local spawnppos = CFrame.new(workspace.GameData.Movepoints.spawnpart.CFrame.Position) * startAnglePos
local movepointChildren = workspace.GameData.Movepoints:GetChildren()

-- sort the table by numbered names because sometimes the children arent in the order of their names in getchildren
table.sort(movepointChildren, function(a, b)
	local function extractNumber(name)
		return tonumber(name:match("%d+$")) or -1
	end

	return extractNumber(a.Name) < extractNumber(b.Name)
end)

-- build checkpoints based on the movepoints
local checkpoints = {}

for _, movepoint in ipairs(movepointChildren) do
	if movepoint.Name ~= "spawnpart" then
		table.insert(checkpoints, movepoint)
	end
end

--print(checkpoints)

-- set wave based variables
_G.wave = 0
_G.died = false
_G.spawned = {}
_G.canSkip = true
local lastWave = _G.wave
local enemyHealth = {}
local hasEnded = false
-- get the order of enemies spawned from waveData
_G.spawnData = waveData[_G.map][_G.chapter]

print("Starting")

-- clone it so we arent changing the data in the module
local clonedData = table.clone(_G.spawnData)
replayEvent.OnServerEvent:Connect(function()
	-- Map is being replayed, reset all variables and clean up the workspace for a new round
	_G.wave = 1
	hasEnded = false

	-- delete old enemies and troops from workspace
	for i, v in next, workspace.GameData.Enemys:GetChildren() do
		v:Destroy()
	end
	for i, v in next, workspace.GameData.Troops:GetChildren() do
		v:Destroy()
	end

	-- reset money to the base amount set in consts, and update the clients UI
	for _, player in next, game.Players:GetPlayers() do
		_G.money[player] = constants.baseMoney
		getCash:FireClient(player, _G.money[player])
	end

	-- more vars we reset
	_G.spawned = {}
	_G.startTick = tick()
	_G.health = _G.maxHealth
	clonedData = table.clone(_G.spawnData)
	_G.died = false

	-- rest health bar thingy
	finishBoard.Text = tostring(_G.health) .. "/" .. tostring(_G.maxHealth)

	for i, v in next, game.Players:GetPlayers() do
		v.PlayerGui.endUi.Enabled = false
	end

	-- tell client the wave has been reset to 1
	skipEvent:FireAllClients(_G.wave)
end)

endscreenData.OnServerEvent:Connect(function(player)
	-- round / map has ended, send end screen data to client and update datastores
	local playerUserId = player.UserId
	local damage = math.floor(getPlayerTotalDamage(player))
	-- coins based on map / wave data
	local coinsAmt = _G.wave * _G.spawnData[0]["coinsGainedPerWave"]

	-- based on coins
	local xpAmt = coinsAmt / 2
	local mapName = _G.map .. " | Chapter " .. tostring(_G.chapter)

	-- update datastores
	updateDataStore(CoinsDataStore, playerUserId, coinsAmt)
	updateDataStore(XPDataStore, playerUserId, xpAmt)
	updateDataStore(DamageDataStore, playerUserId, damage)

	hasEnded = true

	-- send data to client to update end UI
	endscreenData:FireClient(
		player,
		damage,
		_G.startTick,
		coinsAmt,
		mapName,
		xpAmt,
		getDataStoreValue(CoinsDataStore, player.UserId)
	)
end)

skipEvent.OnServerEvent:Connect(function(player)
	-- skip wave event

	-- if u cant skip then return
	if not _G.canSkip then
		return
	end

	for _, player in next, game.Players:GetPlayers() do
		-- if they somehow dont have money, set to base
		if not _G.money[player] then
			_G.money[player] = constants.baseMoney
		end

		-- if the wave is somehow higher than the spawn data, return (shouldnt happen but just in case)
		if not _G.spawnData[_G.wave] then
			return
		end

		-- give the players the bonus for skipping the wave based on the spawn data
		_G.money[player] += _G.spawnData[_G.wave]["bonus"]

		-- update ui on client
		getCash:FireClient(player, _G.money[player])
	end

	-- increase wave and tell clients to update their wave display
	_G.wave += 1
	skipEvent:FireAllClients(_G.wave)

	-- cant skip for 10s
	_G.canSkip = false
	task.delay(10, function()
		_G.canSkip = true
		canSkipEvent:FireAllClients()
	end)
end)

players.PlayerAdded:Connect(function(player)
	-- when a player joins make sure their ui is up to date
	player.CharacterAdded:Wait()
	player.PlayerGui:WaitForChild("SideUi"):WaitForChild("mainFrame"):WaitForChild("coinUi")
	endscreenData:FireClient(player, nil, nil, nil, nil, nil, getDataStoreValue(CoinsDataStore, player.UserId))
end)

-- make sure the enemies cant collide with each other or the map, was having issues for some reason
spawn(function()
	while wait(0.5) do
		for _, enemy in pairs(workspace.GameData.Enemys:GetChildren()) do
			for _, child in pairs(enemy:GetChildren()) do
				if (child:IsA("BasePart") or child:IsA("MeshPart") or child:IsA("Part")) and child.CanCollide then
					child.CanCollide = false
				end
			end
		end
	end
end)

-- main wave loop
spawn(function()
	while task.wait(0.5) do
		print("wave is: ", _G.wave)
		local baseSpawnedEnemys = _G.spawnData[_G.wave]
		local currentSpawnedEnemys = _G.spawned

		for tableWave, data in clonedData do
			-- make sure data is valid and the wave is correct
			if type(tableWave) == "number" and _G.wave >= tableWave then
				-- overwrite so we dont do the same wave twice (cause we are using >= and it could be risky)
				clonedData[tableWave] = nil

				for _, name in data do
					local part

					-- need a new thread because of how makeCharacter works
					spawn(function()
						if type(name) == "string" then
							-- another sanity check
							if _G.wave >= tableWave then
								-- We make the enemy using the module, the module creates it, and MOVES IT
								-- which means that by the time the function is done being called, the moveto is completed
								-- thus the enemy must have made it to the end if it still exists and hasnt been killed / destroyed yet
								part = module:makeCharacter(
									spawnppos,
									checkpoints,
									data2[name].Speed,
									entities:FindFirstChild(name)
								)

								-- If the enemy still exists after the pathfinding is done, it means it made it to the end and we need deal damage
								if part then
									local partHealth = part.Health.Value

									-- if below 0, set to 0 (because we subtract health and we dont want negatives)
									if partHealth < 0 then
										partHealth = 0
									end

									-- subtract health of the enemy from your health
									_G.health -= partHealth

									-- if your health is below 0, enough enemies have reached the end and you died
									if _G.health <= 0 then
										warn("you died")
										--update vars
										_G.health = 0
										_G.died = true
										endEvent:FireAllClients()
									end

									-- update text since you took damage
									finishBoard.Text = tostring(_G.health) .. "/" .. tostring(_G.maxHealth)
									-- delete enemy once reached end
									part:Destroy()

									-- clean up anything in the spawned table
									for i, v in next, _G.spawned do
										if not v or not v.Parent then
											_G.spawned[i] = nil
										end
									end

									-- if the wave was comlpeted and your not dead, give cash and move to the next wave
									if #_G.spawned == 0 and not _G.died then
										warn("Skipping from die")

										for _, player in next, game.Players:GetPlayers() do
											_G.money[player] += _G.spawnData[_G.wave]["bonus"]

											getCash:FireClient(player, _G.money[player])
										end

										_G.wave += 1

										skipEvent:FireAllClients(_G.wave)
									end
								end
							end
						end
					end)

					wait(0.5)
				end
			end
		end
	end
end)
