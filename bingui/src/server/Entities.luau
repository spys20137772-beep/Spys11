-- 몸 목록 관리 + NPC 인공지능 + 인구 관리 + 출동(경찰 등)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GD = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameData"))

local Ents = {}
local G
local rng = Random.new()

local list = {}
local byModel = {}
Ents.List = list
local nextId = 0

local CITYZ = { "home", "park", "market", "police", "school", "cafe", "mart", "hosp", "bank", "gas" }

-- 원작 인구의 약 40% (로블록스 서버 성능 고려)
local POP = {
	{ Type = "citizen", N = 60, Spot = function() return G.World.ZoneSpot(CITYZ, true) end },
	{ Type = "mouse", N = 16, Spot = function() return G.World.ZoneSpot({ "home", "market", "park" }) end },
	{ Type = "cat", N = 10, Spot = function() return G.World.ZoneSpot({ "home", "market", "cafe" }) end },
	{ Type = "pigeon", N = 14, Spot = function() return G.World.ZoneSpot({ "park", "market", "school" }) end },
	{ Type = "police", N = 8, Cd = 12, Spot = function() return G.World.ZoneSpot({ "police" }, true) end },
	{ Type = "dog", N = 4, Cd = 15, Spot = function() return G.World.ZoneSpot({ "police" }) end },
	{ Type = "scientist", N = 6, Cd = 10, Spot = function() return G.World.ZoneSpot({ "lab" }, true) end },
	{ Type = "robot", N = 3, Cd = 25, Spot = function() return G.World.ZoneSpot({ "lab" }) end },
	{ Type = "soldier", N = 8, Cd = 10, Spot = function() return G.World.ZoneSpot({ "base" }, true) end },
	{ Type = "tank", N = 2, Cd = 40, Spot = function() return G.World.ZoneSpot({ "base" }) end, AI = "parked" },
	{ Type = "car", N = 16, Car = true },
	{ Type = "pcar", N = 3, Cd = 30, Spot = function() return G.World.ZoneSpot({ "police" }) end, AI = "parked" },
}

-- 적대 NPC 거리 설정 (스터드)
local PREF = { police = 23, soldier = 26, robot = 24, hazmat = 7, dog = 0, tank = 32, exorcist = 20 }
local RANGE = { police = 38, soldier = 41, robot = 39, hazmat = 13, dog = 4.5, tank = 50, exorcist = 38 }
local AWARE = { tank = 40 }

---------------------------------------------------------------------
-- 등록 / 조회
---------------------------------------------------------------------
function Ents.Spawn(bodyType: string, pos: Vector3, opts: { [string]: any }?)
	local def = GD.Bodies[bodyType]
	local model = G.Factory.Make(bodyType, pos, G.World.Folders.Bodies)
	nextId += 1
	local e = {
		Id = nextId,
		Type = bodyType,
		Def = def,
		Model = model,
		Root = model.PrimaryPart,
		Hum = model:FindFirstChildOfClass("Humanoid"),
		HP = def.HP,
		MaxHP = def.HP,
		R = def.R,
		Dead = false,
		Home = pos,
		AI = "wander",
		NextWander = 0,
		Cd = 0,
		StunUntil = 0,
		PanicUntil = 0,
		PanicFrom = pos,
		ProvokedBy = nil,
		ProvokedUntil = 0,
		Aware = false,
		SniffCd = 0,
		FollowUntil = 0,
		SayUntil = 0,
	}
	if opts then
		for k, v in pairs(opts) do
			e[k] = v
		end
	end
	model:SetAttribute("Possessable", not def.Boss)
	table.insert(list, e)
	byModel[model] = e
	return e
end

function Ents.Remove(e)
	byModel[e.Model] = nil
	local idx = table.find(list, e)
	if idx then
		table.remove(list, idx)
	end
	if e.Model then
		e.Model:Destroy()
	end
end

function Ents.FromModel(model: Instance?)
	return model and byModel[model] or nil
end

function Ents.FromPart(inst: Instance?)
	while inst and inst ~= workspace do
		if byModel[inst] then
			return byModel[inst]
		end
		inst = inst.Parent
	end
	return nil
end

function Ents.Pos(e): Vector3
	return e.Root.Position
end

-- 살아있고 보이는 몸만 (영혼 숨김/죽음 제외)
function Ents.Active(e): boolean
	return not e.Dead and not e.Hidden and e.Model.Parent ~= nil
end

function Ents.Near(pos: Vector3, radius: number, filter: ((any) -> boolean)?)
	local out = {}
	for _, e in ipairs(list) do
		if Ents.Active(e) then
			local d = (e.Root.Position - pos).Magnitude
			if d < radius + e.R and (not filter or filter(e)) then
				table.insert(out, e)
			end
		end
	end
	return out
end

function Ents.Nearest(pos: Vector3, bodyType: string, exclude)
	local best, bd = nil, math.huge
	for _, e in ipairs(list) do
		if e.Type == bodyType and Ents.Active(e) and e ~= exclude and not e.Possessor then
			local d = (e.Root.Position - pos).Magnitude
			if d < bd then
				best, bd = e, d
			end
		end
	end
	return best
end

function Ents.IsHuman(e)
	return e.Def.Human == true
end

---------------------------------------------------------------------
-- 이동 헬퍼
---------------------------------------------------------------------
local function moveTo(e, pos: Vector3, speedMul: number)
	e.Hum.WalkSpeed = e.Def.Speed * speedMul
	e.Hum:MoveTo(Vector3.new(pos.X, e.Root.Position.Y, pos.Z))
end

local function stop(e)
	e.Hum:MoveTo(e.Root.Position)
end

local function face(e, pos: Vector3)
	local p = e.Root.Position
	local look = Vector3.new(pos.X, p.Y, pos.Z)
	if (look - p).Magnitude > 0.5 then
		e.Root.CFrame = CFrame.lookAt(p, look)
	end
end

function Ents.Panic(e, from: Vector3, duration: number)
	if e.Def.Hostile or e.Def.Vehicle or e.Possessor or e.Dead then
		return
	end
	e.PanicUntil = math.max(e.PanicUntil, os.clock() + duration)
	e.PanicFrom = from
end

function Ents.PanicNear(pos: Vector3, radius: number, duration: number?)
	for _, e in ipairs(Ents.Near(pos, radius)) do
		Ents.Panic(e, pos, duration or 5)
	end
end

---------------------------------------------------------------------
-- AI
---------------------------------------------------------------------
local function wander(e, now)
	if now < e.NextWander then
		return
	end
	e.NextWander = now + rng:NextNumber(2, 6)
	if rng:NextNumber() < 0.3 and e.Type ~= "pigeon" then
		stop(e)
		return
	end
	local radius = if e.Type == "pigeon" then 40 elseif e.Type == "mouse" then 12 else 25
	for _ = 1, 5 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(3, radius)
		local p = e.Home + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local comp = G.World.InCompound(p)
		if (not comp or GD.Allow[comp][e.Type]) and G.World.InWorld(p) then
			moveTo(e, p, if e.Type == "pigeon" then 0.45 else 0.32)
			return
		end
	end
end

local function civAI(e, now)
	if e.FollowUntil > now and e.FollowPlayer then
		local ps = G.Players.State(e.FollowPlayer)
		local body = ps and ps.Body
		if body and Ents.Active(body) then
			local d = (body.Root.Position - e.Root.Position).Magnitude
			if d > 5 then
				moveTo(e, body.Root.Position, 0.8)
			else
				stop(e)
			end
			return
		end
	end
	if e.PanicUntil > now then
		local away = e.Root.Position - e.PanicFrom
		away = Vector3.new(away.X, 0, away.Z)
		if away.Magnitude < 0.1 then
			away = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
		end
		local dir = (away.Unit + Vector3.new(rng:NextNumber(-0.4, 0.4), 0, rng:NextNumber(-0.4, 0.4))).Unit
		moveTo(e, e.Root.Position + dir * 14, 1.05)
		return
	end
	wander(e, now)
end

local function los(a: Vector3, b: Vector3): boolean
	return G.Combat.LineOfSight(a, b)
end

local function hostileAI(e, now)
	local myPos = e.Root.Position
	local target = nil
	local targetDist = math.huge

	if e.ProvokedBy and now < e.ProvokedUntil then
		local ps = G.Players.State(e.ProvokedBy)
		if ps and ps.Body and Ents.Active(ps.Body) then
			target = ps
			targetDist = (ps.Body.Root.Position - myPos).Magnitude
		end
	end

	if not target and e.Responder then
		local ps = G.Players.State(e.Responder)
		if ps and ps.Body and Ents.Active(ps.Body) and ps.Known and ps.Stars > 0 and not G.Players.IsInvisible(ps) then
			target = ps
			targetDist = (ps.Body.Root.Position - myPos).Magnitude
		end
	end

	if not target then
		local awareRange = AWARE[e.Type] or 32
		for _, ps in ipairs(G.Players.Playing()) do
			local body = ps.Body
			if body and Ents.Active(body) and not G.Players.IsInvisible(ps) then
				local d = (body.Root.Position - myPos).Magnitude
				if d < awareRange and d < targetDist and G.Players.Suspicious(ps) and los(myPos, body.Root.Position) then
					target, targetDist = ps, d
				end
			end
		end
	end

	-- 냄새 맡기 (퇴마사 순찰 / 경찰견)
	if not target and now >= e.SniffCd and ((e.Type == "hazmat" and e.Patrol) or (e.Type == "dog" and not e.Responder)) then
		local range = if e.Type == "dog" then 22 else 18
		for _, ps in ipairs(G.Players.Playing()) do
			if ps.Host and ps.Stars == 0 and not G.Players.IsInvisible(ps) then
				if (ps.Host.Root.Position - myPos).Magnitude < range then
					e.SniffCd = now + (if e.Type == "dog" then 7 else 8)
					G.Fx.Say(e, if e.Type == "dog" then "킁킁… 유령 냄새! 멍멍!" else "영기가 느껴진다!")
					G.Players.Sniffed(ps)
					break
				end
			end
		end
	end

	if target then
		local body = target.Body
		local tpos = body.Root.Position
		local d = (tpos - myPos).Magnitude
		local seen = d < 48 and los(myPos, tpos)
		e.Aware = true
		if seen then
			G.Players.MarkSeen(target, tpos)
		end

		local pref = PREF[e.Type] or 20
		if d > pref + 3 then
			moveTo(e, tpos, 0.9)
		elseif d < pref - 5 and pref > 0 then
			local away = (myPos - tpos) * Vector3.new(1, 0, 1)
			if away.Magnitude > 0.1 then
				moveTo(e, myPos + away.Unit * 8, 0.7)
			end
		else
			stop(e)
			face(e, tpos)
		end

		if d < (RANGE[e.Type] or 30) and now >= e.Cd and seen then
			G.Combat.NpcAttack(e, body)
		end
	else
		e.Aware = false
		if e.Responder then
			local ps = G.Players.State(e.Responder)
			if ps and ps.LastSeen then
				moveTo(e, ps.LastSeen, 0.8)
				return
			end
		end
		wander(e, now)
	end
end

local function berserkAI(e, now)
	if not e.Target or not Ents.Active(e.Target) or now > (e.RetargetAt or 0) then
		e.RetargetAt = now + 0.8
		local best, bd = nil, 50
		for _, o in ipairs(list) do
			if o ~= e and o.Type ~= e.Type and Ents.Active(o) then
				local d = (o.Root.Position - e.Root.Position).Magnitude
				if d < bd then
					best, bd = o, d
				end
			end
		end
		e.Target = best
	end
	local t = e.Target
	if not t then
		civAI(e, now)
		return
	end
	local d = (t.Root.Position - e.Root.Position).Magnitude
	moveTo(e, t.Root.Position, 0.92)
	if d < e.R + t.R + 1.5 and now >= e.Cd then
		e.Cd = now + 0.75
		G.Combat.Hurt(t, 16, e, nil)
		if rng:NextNumber() < 0.4 then
			G.Fx.Say(e, if rng:NextNumber() < 0.5 then "끼에엑!" else "크르르")
		end
	end
end

local function carAI(e, now)
	if e.AI == "parked" then
		stop(e)
		return
	end
	if e.AI == "chase" and e.Responder then
		local ps = G.Players.State(e.Responder)
		if ps and ps.Body and Ents.Active(ps.Body) and ps.Stars > 0 then
			moveTo(e, ps.Body.Root.Position, 0.9)
			e.Chasing = true
			return
		end
		e.Chasing = false
		stop(e)
		return
	end
	-- 도로 주행
	if not e.Dir then
		e.AI = "parked"
		return
	end
	local W = G.World
	local target = W.Intersection(e.IX, e.IY) + W.LaneOffset(e.Dir)
	local pos = e.Root.Position
	if (Vector3.new(target.X, pos.Y, target.Z) - pos).Magnitude < 5 then
		local reverse = (e.Dir + 1) % 4 + 1
		local options = {}
		for d = 1, 4 do
			if d ~= reverse and W.ValidNext(e.IX, e.IY, d) then
				table.insert(options, d)
			end
		end
		e.Dir = if #options > 0 then options[rng:NextInteger(1, #options)] else reverse
		e.IX += W.DIRS[e.Dir][1]
		e.IY += W.DIRS[e.Dir][2]
		target = W.Intersection(e.IX, e.IY) + W.LaneOffset(e.Dir)
	end
	-- 막혔는지 확인
	if now >= (e.StuckCheckAt or 0) then
		if e.LastPos and (pos - e.LastPos).Magnitude < 1.5 then
			local reverse = (e.Dir + 1) % 4 + 1
			if W.ValidNext(e.IX - W.DIRS[e.Dir][1], e.IY - W.DIRS[e.Dir][2], reverse) then
				e.IX -= W.DIRS[e.Dir][1]
				e.IY -= W.DIRS[e.Dir][2]
				e.Dir = reverse
				e.IX += W.DIRS[e.Dir][1]
				e.IY += W.DIRS[e.Dir][2]
			end
		end
		e.LastPos = pos
		e.StuckCheckAt = now + 2.5
	end
	moveTo(e, target, 0.6)
end

local function think(e, now)
	if now < e.StunUntil then
		stop(e)
		return
	end
	local def = e.Def
	if e.Type == "mutant" then
		berserkAI(e, now)
	elseif def.Vehicle and e.Type ~= "tank" then
		carAI(e, now)
	elseif def.Hostile then
		if e.AI == "parked" and not e.Aware and not e.Responder then
			-- 주차된 탱크: 근처에 의심스러운 대상이 있을 때만 깨어남
			for _, ps in ipairs(G.Players.Playing()) do
				if ps.Body and Ents.Active(ps.Body) and (ps.Body.Root.Position - e.Root.Position).Magnitude < 40 and G.Players.Suspicious(ps) then
					e.AI = "hunt"
				end
			end
			if e.AI == "parked" then
				stop(e)
				return
			end
		end
		hostileAI(e, now)
	else
		civAI(e, now)
	end
end

---------------------------------------------------------------------
-- 인구 / 출동 관리
---------------------------------------------------------------------
local function farFromPlayers(pos: Vector3, minDist: number): boolean
	for _, ps in ipairs(G.Players.Playing()) do
		if ps.Body and (ps.Body.Root.Position - pos).Magnitude < minDist then
			return false
		end
	end
	return true
end

local function spawnFromPop(p, initial: boolean)
	for _ = 1, 3 do
		if p.Car then
			local pos, dir, ix, iy = G.World.CarSpot()
			if pos and (initial or farFromPlayers(pos, 60)) then
				Ents.Spawn("car", pos, { AI = "drive", Dir = dir, IX = ix, IY = iy })
				return true
			end
		else
			local pos = p.Spot()
			if pos and (initial or farFromPlayers(pos, 50)) then
				Ents.Spawn(p.Type, pos, { AI = p.AI or "wander" })
				return true
			end
		end
	end
	return false
end

local function managePopulation(initial: boolean)
	local counts = {}
	for _, e in ipairs(list) do
		if not e.Dead and not e.Responder and not e.Possessor and not e.Patrol then
			counts[e.Type] = (counts[e.Type] or 0) + 1
		end
	end
	for _, p in ipairs(POP) do
		local c = counts[p.Type] or 0
		if initial then
			for _ = c + 1, p.N do
				spawnFromPop(p, true)
			end
		else
			p.CdT = (p.CdT or 0) - 2
			if p.CdT <= 0 and c < p.N then
				if spawnFromPop(p, false) then
					p.CdT = p.Cd or 0
				end
			end
		end
	end

	-- 밤에는 퇴마사 순찰
	if not initial then
		local patrols = {}
		for _, e in ipairs(list) do
			if e.Patrol and not e.Dead then
				table.insert(patrols, e)
			end
		end
		if G.Players.IsNight() then
			if #patrols < 6 then
				local pos = G.World.ZoneSpot(CITYZ, false)
				if pos then
					Ents.Spawn("hazmat", pos, { Patrol = true })
				end
			end
		else
			for _, e in ipairs(patrols) do
				if not e.Possessor and farFromPlayers(e.Root.Position, 60) then
					Ents.Remove(e)
				end
			end
		end
	end
end

local function manageResponders()
	for _, ps in ipairs(G.Players.Playing()) do
		local body = ps.Body
		if body and Ents.Active(body) then
			local s = ps.Stars
			local cnt = {}
			local mine = {}
			for _, e in ipairs(list) do
				if e.Responder == ps.Player and not e.Dead and not e.Possessor then
					cnt[e.Type] = (cnt[e.Type] or 0) + 1
					table.insert(mine, e)
				end
			end
			for _, entry in ipairs(GD.Responders[s]) do
				local t, n = entry[1], entry[2]
				if (cnt[t] or 0) < n then
					local p = G.World.RoadPointNear(body.Root.Position, 45, 75)
					if p then
						Ents.Spawn(t, p, { Responder = ps.Player, AI = if t == "pcar" then "chase" else "hunt" })
					end
					break
				end
			end
			if s == 0 then
				for _, e in ipairs(mine) do
					if (e.Root.Position - body.Root.Position).Magnitude > 60 then
						Ents.Remove(e)
					end
				end
			end
		end
	end
end

-- 플레이어가 나가거나 게임오버 때 출동 인원 정리
function Ents.ClearResponders(player: Player)
	for i = #list, 1, -1 do
		local e = list[i]
		if e.Responder == player and not e.Possessor then
			Ents.Remove(e)
		end
	end
end

function Ents.Init(g)
	G = g
end

function Ents.Start()
	managePopulation(true)

	-- AI 루프
	task.spawn(function()
		while true do
			local now = os.clock()
			for i = #list, 1, -1 do
				local e = list[i]
				if e then
					if e.Dead then
						if now >= (e.RemoveAt or 0) then
							Ents.Remove(e)
						end
					elseif not e.Possessor and not e.IsGhost and e.Model.Parent then
						local ok, err = pcall(think, e, now)
						if not ok then
							warn("[AI]", e.Type, err)
						end
					end
				end
			end
			task.wait(0.2)
		end
	end)

	-- 인구 / 출동 루프
	task.spawn(function()
		while true do
			task.wait(2)
			local ok, err = pcall(managePopulation, false)
			if not ok then
				warn("[Population]", err)
			end
			ok, err = pcall(manageResponders)
			if not ok then
				warn("[Responders]", err)
			end
		end
	end)
end

return Ents
