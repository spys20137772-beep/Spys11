-- 플레이어 상태: 영혼/빙의, 경계 단계, 미션, 진화, 구역 장악, 밤낮, 대퇴마사, 저장
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GD = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameData"))

local GS = {}
local G
local rng = Random.new()

local states = {}
local remote: RemoteEvent
local store: DataStore? = nil
local dayT = 20
local wasNight = false
local bossCd = 0

local YELLOW = Color3.fromRGB(255, 224, 102)
local CYAN = Color3.fromRGB(143, 232, 255)
local GREEN = Color3.fromRGB(184, 255, 154)
local PINK = Color3.fromRGB(255, 122, 122)

local function now()
	return os.clock()
end

local function pick(t)
	return t[rng:NextInteger(1, #t)]
end

local function flat(v: Vector3)
	return Vector3.new(v.X, 0, v.Z)
end

---------------------------------------------------------------------
-- 통신
---------------------------------------------------------------------
function GS.Send(player: Player, kind: string, ...)
	if player.Parent then
		remote:FireClient(player, kind, ...)
	end
end

function GS.Broadcast(kind: string, ...)
	remote:FireAllClients(kind, ...)
end

function GS.Toast(player: Player, text: string)
	GS.Send(player, "Toast", text)
end

function GS.Banner(player: Player, title: string, sub: string?)
	GS.Send(player, "Banner", title, sub or "")
end

function GS.Pop(player: Player, pos: Vector3, text: string, color: Color3?)
	GS.Send(player, "Pop", pos, text, color or Color3.new(1, 1, 1))
end

---------------------------------------------------------------------
-- 조회
---------------------------------------------------------------------
function GS.State(player: Player)
	return states[player]
end

function GS.Playing()
	local out = {}
	for _, ps in pairs(states) do
		if ps.Playing then
			table.insert(out, ps)
		end
	end
	return out
end

local function darkness(): number
	local t = dayT % GD.DAYLEN
	if t < 150 then
		return 0
	elseif t < 175 then
		return (t - 150) / 25
	elseif t < 275 then
		return 1
	end
	return 1 - (t - 275) / 25
end

function GS.IsNight(): boolean
	return darkness() > 0.55
end

function GS.IsInvisible(ps): boolean
	return now() < ps.InvisUntil
end

function GS.PowerMul(player: Player): number
	local ps = states[player]
	return if ps then 1 + 0.2 * ps.Upg.power else 1
end

local function lifeMul(ps)
	return 1 + 0.25 * ps.Upg.life
end
local function dryMax(ps)
	return 6 + 2 * ps.Upg.dry
end
local function jumpMul(ps)
	return 1 + 0.2 * ps.Upg.jump
end
local function sneakMul(ps)
	return 1 - 0.12 * ps.Upg.sneak
end

function GS.Suspicious(ps): boolean
	if GS.IsInvisible(ps) then
		return false
	end
	local body = ps.Body
	if not body then
		return false
	end
	if body.IsGhost then
		return true
	end
	if ps.Stars >= 1 and ps.Known then
		return true
	end
	local comp = G.World.InCompound(body.Root.Position)
	if comp and not GD.Allow[comp][body.Type] then
		return true
	end
	return false
end

function GS.MarkSeen(ps, pos: Vector3)
	ps.Known = true
	ps.LastSeen = pos
	ps.LastSeenT = now()
end

function GS.Sniffed(ps)
	ps.Heat = math.max(ps.Heat, GD.Stars[1] + 3)
	ps.LastChaosT = now()
	if ps.Body then
		GS.MarkSeen(ps, ps.Body.Root.Position)
		GS.Pop(ps.Player, ps.Body.Root.Position + Vector3.new(0, 6, 0), "영혼을 눈치챘다!", Color3.fromRGB(255, 154, 122))
	end
end

---------------------------------------------------------------------
-- 깽판 / 경계 / 구역
---------------------------------------------------------------------
local function save(ps)
	if not store or not ps.CanSave then
		return
	end
	local own = {}
	for i = 1, 81 do
		if ps.Own[i] then
			table.insert(own, i)
		end
	end
	local data = { Bio = math.floor(ps.Bio), Upg = ps.Upg, Mi = ps.Mi, Best = ps.Best, Own = own }
	local userId = ps.Player.UserId
	task.spawn(function()
		local ok, err = pcall(function()
			store:SetAsync("u_" .. userId, data, { userId })
		end)
		if not ok then
			warn("[Bingui] 저장 실패:", err)
		end
	end)
end
GS.Save = save

local function addFear(ps, pos: Vector3, pts: number)
	if not G.World.InWorld(pos) then
		return
	end
	local idx = G.World.BlockIndexAt(pos)
	if ps.Own[idx] then
		return
	end
	ps.Fear[idx] = math.min(100, ps.Fear[idx] + pts * 0.5)
	if ps.Fear[idx] >= 100 then
		ps.Own[idx] = true
		local zone = G.World.ZoneAt(pos)
		local count = 0
		for i = 1, 81 do
			if ps.Own[i] then
				count += 1
			end
		end
		GS.Banner(ps.Player, "👑 구역 장악!", `{GD.ZoneKo[zone] or zone} 구역이 유령의 영역이 됐다 ({count}/81)`)
		ps.Bio += 30
		save(ps)
	end
end

local function markSeenByHostiles(ps)
	if GS.IsInvisible(ps) or not ps.Body then
		return
	end
	local pos = ps.Body.Root.Position
	for _, o in ipairs(G.Ents.Near(pos, 45)) do
		if o.Def.Hostile and not o.Possessor and G.Combat.LineOfSight(o.Root.Position, pos) then
			GS.MarkSeen(ps, pos)
			return
		end
	end
end

function GS.AddChaos(player: Player, pts: number, pos: Vector3, show: boolean?)
	local ps = states[player]
	if not ps or not ps.Playing then
		return
	end
	ps.Chaos += pts
	ps.Bio += pts * 0.5
	local owned = G.World.InWorld(pos) and ps.Own[G.World.BlockIndexAt(pos)]
	ps.Heat = math.min(620, ps.Heat + pts * sneakMul(ps) * (if owned then 0.6 else 1))
	addFear(ps, pos, pts)
	ps.LastChaosT = now()
	if pts >= 3 then
		markSeenByHostiles(ps)
	end
	if show ~= false and pts >= 3 then
		GS.Pop(player, pos + Vector3.new(0, 5, 0), `+{math.floor(pts + 0.5)} 깽판`, YELLOW)
	end
end

---------------------------------------------------------------------
-- 미션
---------------------------------------------------------------------
local function hostIs(ps, t)
	return ps.Host and ps.Host.Type == t
end

local CHECK = {
	infect_mouse = function(_, o) return o.k == "infect" and o.type == "mouse" end,
	cat_stall = function(ps, o) return o.k == "break" and o.kind == "stall" and hostIs(ps, "cat") end,
	fridge = function(_, o) return o.k == "ia" and o.kind == "fridge" end,
	poop = function(_, o) return o.k == "poophit" end,
	fountain = function(_, o) return o.k == "fountain" end,
	infect_police = function(_, o) return o.k == "infect" and o.type == "police" end,
	ppc = function(_, o) return o.k == "ia" and o.kind == "ppc" end,
	stars2 = function(_, o) return o.k == "stars" and o.n >= 2 end,
	house = function(_, o) return o.k == "house" end,
	gate_lab = function(_, o) return o.k == "gate" and o.g == "lab" end,
	specimen = function(_, o) return o.k == "ia" and o.kind == "specimen" end,
	infect_robot = function(_, o) return o.k == "infect" and o.type == "robot" end,
	gate_base = function(_, o) return o.k == "gate" and o.g == "base" end,
	infect_tank = function(_, o) return o.k == "infect" and o.type == "tank" end,
	tank5 = function(ps, o) return o.k == "house" and hostIs(ps, "tank") end,
	boss = function(_, o) return o.k == "boss" end,
	s5 = function(_, o) return o.k == "s5tick" end,
}

local AUTO = {
	stars2 = function(ps) return ps.Stars >= 2 end,
	gate_lab = function() return G.World.Gates.lab and G.World.Gates.lab.Open end,
	gate_base = function() return G.World.Gates.base and G.World.Gates.base.Open end,
}

local function completeMission(ps)
	local m = GD.Missions[ps.Mi]
	ps.Bio += m.Reward
	GS.Banner(ps.Player, `미션 완료! +{m.Reward} 🧬`, m.Text)
	ps.Mi += 1
	ps.MProg = 0
	save(ps)
end

function GS.Event(player: Player, o)
	local ps = states[player]
	if not ps or not ps.Playing then
		return
	end
	local m = GD.Missions[ps.Mi]
	if not m then
		return
	end
	local check = CHECK[m.Id]
	if check and check(ps, o) then
		ps.MProg += 1
		if not m.N or ps.MProg >= m.N then
			completeMission(ps)
		end
	end
end

function GS.EventAll(o)
	for _, ps in ipairs(GS.Playing()) do
		GS.Event(ps.Player, o)
	end
end

local function missionHint(ps): Vector3?
	local m = GD.Missions[ps.Mi]
	local body = ps.Body
	if not m or not body then
		return nil
	end
	local pos = body.Root.Position
	local E, W = G.Ents, G.World
	local function ent(t)
		local e = E.Nearest(pos, t, body)
		return e and e.Root.Position
	end
	local function prop(k)
		local p = W.NearestProp(pos, k)
		return p and p.Pos
	end
	local function house()
		local best, bd = nil, math.huge
		for _, b in pairs(W.Buildings) do
			if not b.Destroyed then
				local d = (b.CFrame.Position - pos).Magnitude
				if d < bd then
					best, bd = b.CFrame.Position, d
				end
			end
		end
		return best
	end
	local id = m.Id
	if id == "infect_mouse" then
		return ent("mouse")
	elseif id == "cat_stall" then
		return if hostIs(ps, "cat") then prop("stall") else ent("cat")
	elseif id == "fridge" then
		return prop("fridge")
	elseif id == "poop" then
		return if hostIs(ps, "pigeon") then ent("citizen") else ent("pigeon")
	elseif id == "fountain" then
		if hostIs(ps, "citizen") then
			local best, bd = nil, math.huge
			for _, f in ipairs(W.Fountains) do
				local d = (f.Pos - pos).Magnitude
				if d < bd then
					best, bd = f.Pos, d
				end
			end
			return best
		end
		return ent("citizen")
	elseif id == "infect_police" then
		return ent("police")
	elseif id == "ppc" then
		return prop("ppc")
	elseif id == "house" then
		return if body.Def.Vehicle then house() else ent("car")
	elseif id == "gate_lab" then
		return if hostIs(ps, "scientist") then W.Gates.lab.Pos else (ent("scientist") or W.Gates.lab.Pos)
	elseif id == "specimen" then
		return prop("specimen")
	elseif id == "infect_robot" then
		return ent("robot")
	elseif id == "gate_base" then
		return if hostIs(ps, "soldier") then W.Gates.base.Pos else (ent("soldier") or W.Gates.base.Pos)
	elseif id == "infect_tank" then
		return ent("tank")
	elseif id == "tank5" then
		return if hostIs(ps, "tank") then house() else ent("tank")
	elseif id == "boss" then
		return ent("exorcist")
	end
	return nil
end

---------------------------------------------------------------------
-- 몸 전환 (빙의의 핵심: player.Character 를 바꿔치기)
---------------------------------------------------------------------
local function setCharacter(ps, e)
	ps.Body = e
	e.Hidden = false
	e.Model.Parent = G.World.Folders.Bodies
	ps.Player.Character = e.Model
	pcall(function()
		e.Root:SetNetworkOwner(ps.Player)
	end)
	e.Hum.WalkSpeed = e.Def.Speed
	e.Hum.AutoRotate = true
	G.Fx.UpdateHealthBar(e)
end

local function hideGhost(ps)
	local g = ps.Ghost
	if g then
		g.Hidden = true
		g.Model.Parent = nil
	end
end

local function showGhostAt(ps, pos: Vector3, look: Vector3?)
	local g = ps.Ghost
	local y = 0.4 + g.Hum.HipHeight + g.Root.Size.Y / 2 + 0.2
	local p = Vector3.new(pos.X, y, pos.Z)
	g.Model:PivotTo(if look and look.Magnitude > 0.1 then CFrame.lookAt(p, p + look) else CFrame.new(p))
	setCharacter(ps, g)
end

local function setGroup(e, group: string)
	for _, p in ipairs(e.Model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CollisionGroup = group
		end
	end
end

local function clearHostEffects(ps, h)
	if ps.WallPassOn then
		ps.WallPassOn = false
		setGroup(h, "Bodies")
	end
	if ps.InvisParts then
		for p, tr in pairs(ps.InvisParts) do
			if p.Parent then
				p.Transparency = tr
			end
		end
		ps.InvisParts = nil
	end
	ps.WallPassUntil = 0
	ps.NitroUntil = 0
end

local function releaseHost(ps, h, explodeSrc)
	if not h then
		return
	end
	clearHostEffects(ps, h)
	h.Possessor = nil
	ps.Host = nil
	local pos = h.Root.Position
	h.StunUntil = now() + 1.5
	h.Home = pos
	h.AI = if h.Def.Vehicle then "parked" elseif h.Def.Hostile then "hunt" else "wander"
	h.PanicUntil = 0
	pcall(function()
		h.Root:SetNetworkOwner(nil)
	end)
	h.Hum:MoveTo(pos)
	G.Fx.UpdateHealthBar(h)
	ps.LastHost = h
	ps.LastHostUntil = now() + 0.7
	if not h.Def.Vehicle and h.HP < h.MaxHP * 0.15 then
		G.Combat.Kill(h, nil, nil)
	elseif not h.Def.Vehicle then
		G.Fx.Say(h, pick({ "어? 내가 왜 여기…", "머리가 띵해…", "뭐였지?" }))
	end
	if ps.Upg.boom > 0 and not h.Dead then
		local lv = ps.Upg.boom
		G.Combat.Explode(pos, (45 + 20 * lv) * GD.K, 30 + 25 * lv, ps.Player, explodeSrc)
	end
end

local function canPossess(e): boolean
	if e.Def.Boss then
		return e.HP <= e.MaxHP * 0.2
	end
	return true
end

function GS.Infect(ps, e)
	if ps.Host == e or e.Dead or e.Possessor or e.IsGhost then
		return
	end
	if ps.Host then
		releaseHost(ps, ps.Host, e)
	end
	hideGhost(ps)
	local player = ps.Player
	e.Possessor = player
	e.PanicUntil = 0
	e.FollowUntil = 0
	e.StunUntil = 0
	e.ProvokedUntil = 0
	e.Aware = false
	e.Responder = nil
	e.Chasing = false
	ps.Host = e
	ps.Dry = 0
	ps.AbilityReady = now() + 0.35
	ps.Splashed = false
	setCharacter(ps, e)

	local pos = e.Root.Position
	G.World.Debris(pos + Vector3.new(0, 2, 0), 10, { Color3.fromRGB(207, 234, 255), Color3.fromRGB(179, 156, 255), Color3.new(1, 1, 1) }, 0.5, 18)
	GS.Pop(player, pos + Vector3.new(0, 6, 0), e.Def.Name .. " 빙의!", Color3.fromRGB(207, 234, 255))

	-- 변장: 아무도 안 볼 때 숙주를 바꾸면 경계가 내려감
	local seen = false
	for _, o in ipairs(G.Ents.Near(pos, 43)) do
		if o ~= e and o.Def.Hostile and o.Aware and not o.Possessor then
			seen = true
			break
		end
	end
	if not seen and ps.Heat > 5 then
		ps.Heat *= 0.55
		GS.Pop(player, pos + Vector3.new(0, 8, 0), "변장 성공!", CYAN)
	end
	if ps.Known or seen then
		for _, o in ipairs(G.Ents.List) do
			if o.Def.Hostile and not o.Possessor and not o.Dead then
				if o.Aware and (o.Root.Position - pos).Magnitude < 64 and rng:NextNumber() < 0.6 then
					G.Fx.Say(o, pick({ "어디 갔지?", "사라졌다?!", "놓쳤다!" }))
				end
				o.Aware = false
				if o.ProvokedBy == player then
					o.ProvokedUntil = 0
				end
			end
		end
		if ps.Heat >= GD.Stars[1] then
			GS.Pop(player, pos + Vector3.new(0, 10, 0), "경찰이 너를 놓쳤다!", CYAN)
		end
	end
	ps.Known = false

	-- 공포의 강림
	local fear = ps.Upg.fear
	if fear > 0 then
		local n = 0
		for _, o in ipairs(G.Ents.Near(pos, 12.8 + 2.1 * fear)) do
			if o ~= e and o.Def.Human and not o.Possessor then
				o.StunUntil = now() + 1 + fear
				n += 1
			end
		end
		if n > 0 then
			GS.Pop(player, pos + Vector3.new(0, 9, 0), "혼비백산! x" .. n, Color3.fromRGB(179, 156, 255))
		end
	end

	if e.Type == "exorcist" then
		GS.Event(player, { k = "boss" })
		GS.Broadcast("Toast", "📰 대퇴마사가 유령에게 빙의당했다?!")
	end
	GS.Event(player, { k = "infect", type = e.Type })
end

local function findSoulTarget(ps)
	local src = ps.Body
	if not src then
		return nil
	end
	local pos = src.Root.Position
	local look = flat(src.Root.CFrame.LookVector)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	local range = GD.SoulRange(ps.Upg.jump)
	local best, bs = nil, math.huge
	for _, e in ipairs(G.Ents.Near(pos, range)) do
		if e ~= src and not e.IsGhost and not e.Possessor and canPossess(e) then
			local to = flat(e.Root.Position - pos)
			local d = to.Magnitude
			if d > 0.1 and d <= range then
				local ang = math.acos(math.clamp(look:Dot(to.Unit), -1, 1))
				if not (ang > 0.9 and d > 9.6) then
					local score = d + ang * 17
					if score < bs then
						best, bs = e, score
					end
				end
			end
		end
	end
	return best
end

function GS.Leap(ps)
	if ps.Host or now() < ps.LeapCd then
		return
	end
	ps.LeapCd = now() + 0.45
	ps.LeapUntil = now() + 0.32
	GS.Send(ps.Player, "Dash", 66 * jumpMul(ps), 0.32, true)
end

function GS.Dash(ps, speed: number, duration: number, dmg: number)
	ps.DashUntil = now() + duration + 0.05
	ps.DashHit = {}
	ps.DashDmg = dmg
	GS.Send(ps.Player, "Dash", speed, duration, false)
end

function GS.Nitro(ps, duration: number)
	ps.NitroUntil = now() + duration
	if ps.Host then
		G.World.Debris(ps.Host.Root.Position, 8, { Color3.fromRGB(90, 240, 255), Color3.new(1, 1, 1) }, 0.6, 20)
	end
end

function GS.WallPass(ps, duration: number)
	if not ps.Host then
		return
	end
	ps.WallPassUntil = now() + duration
	ps.WallPassOn = true
	setGroup(ps.Host, "Ghost")
end

function GS.SetInvisible(ps, duration: number)
	ps.InvisUntil = now() + duration
	if ps.Host and not ps.InvisParts then
		ps.InvisParts = {}
		for _, p in ipairs(ps.Host.Model:GetDescendants()) do
			if p:IsA("BasePart") and p.Transparency < 0.5 then
				ps.InvisParts[p] = p.Transparency
				p.Transparency = 0.75
			end
		end
	end
end

local function soulTeleport(ps, target)
	local from = ps.Body.Root.Position
	G.Fx.SoulTrail(from, target.Root.Position)
	ps.TpCd = now() + 0.35
	GS.Infect(ps, target)
end

local function exitHost(ps)
	local h = ps.Host
	if not h then
		return
	end
	local pos = h.Root.Position
	local look = flat(h.Root.CFrame.LookVector)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	releaseHost(ps, h, ps.Ghost)
	showGhostAt(ps, pos + look * (h.R + 1.5), look)
	ps.NoInfUntil = now() + 0.35
	ps.LeapCd = 0
	GS.Leap(ps)
end

local function possessAction(ps)
	if now() < ps.TpCd then
		return
	end
	local t = findSoulTarget(ps)
	if t then
		soulTeleport(ps, t)
	elseif ps.Host then
		exitHost(ps)
	else
		GS.Leap(ps)
	end
end

---------------------------------------------------------------------
-- 영혼 피해 / 몸 사망 / 게임오버
---------------------------------------------------------------------
local function gameOver(ps, why: string)
	if not ps.Playing then
		return
	end
	ps.Playing = false
	ps.Best = math.max(ps.Best, math.floor(ps.Chaos))
	local player = ps.Player
	if ps.Host then
		clearHostEffects(ps, ps.Host)
		ps.Host.Possessor = nil
		ps.Host = nil
	end
	if ps.Ghost then
		G.Ents.Remove(ps.Ghost)
		ps.Ghost = nil
	end
	ps.Body = nil
	player.Character = nil
	G.Ents.ClearResponders(player)
	for _, o in ipairs(G.Ents.List) do
		if o.ProvokedBy == player then
			o.ProvokedUntil = 0
			o.Aware = false
		end
	end
	player:SetAttribute("Playing", false)
	GS.Send(player, "GameOver", {
		Why = why,
		Chaos = math.floor(ps.Chaos),
		Best = ps.Best,
		Bio = math.floor(ps.Bio),
	})
	save(ps)
end

function GS.HurtGhost(player: Player)
	local ps = states[player]
	if not ps or not ps.Playing or ps.Host or now() < ps.InvUntil then
		return
	end
	ps.GhostHP -= 1
	ps.InvUntil = now() + 0.8
	if ps.Ghost then
		GS.Pop(player, ps.Ghost.Root.Position + Vector3.new(0, 4, 0), "아야!", PINK)
		G.World.Debris(ps.Ghost.Root.Position, 8, { Color3.fromRGB(207, 234, 255), Color3.fromRGB(179, 156, 255) }, 0.5, 20)
	end
	if ps.GhostHP <= 0 then
		gameOver(ps, "hit")
	end
end

function GS.OnHostDied(player: Player, e)
	local ps = states[player]
	if not ps or ps.Host ~= e then
		e.Possessor = nil
		return
	end
	clearHostEffects(ps, e)
	ps.Host = nil
	e.Possessor = nil
	local pos = e.Root.Position
	showGhostAt(ps, pos, nil)
	ps.InvUntil = now() + 1.2
	ps.Dry = 0
	ps.NoInfUntil = now() + 0.3
	ps.LastHost = e
	ps.LastHostUntil = now() + 1
	GS.Pop(player, pos + Vector3.new(0, 6, 0), "몸이 쓰러졌다! 다른 몸으로!", GREEN)
end

function GS.BossDefeated(byPlayer: Player?)
	bossCd = now() + 150
	GS.Broadcast("Toast", "📰 충격! 대퇴마사, 정체불명 유령에게 패배")
	if byPlayer then
		local ps = states[byPlayer]
		if ps then
			ps.Bio += 300
			GS.Banner(byPlayer, "대퇴마사 격파!!", "+300 🧬")
			GS.Event(byPlayer, { k = "boss" })
		end
	end
end

---------------------------------------------------------------------
-- 상호작용 / 진화
---------------------------------------------------------------------
local function interact(ps, propId)
	local prop = G.World.Props[propId]
	local h = ps.Host
	if not prop or prop.Broken or not h or not G.Ents.Active(h) then
		return
	end
	if (prop.Pos - h.Root.Position).Magnitude > 9 then
		return
	end
	local t = now()
	if t < (prop.UsedUntil or 0) then
		GS.Toast(ps.Player, "이미 썼어요. 잠시 후에 다시!")
		return
	end
	local player = ps.Player
	local k = prop.Kind
	if k == "fridge" then
		if h.Def.Vehicle then
			return
		end
		prop.UsedUntil = t + 30
		h.HP = h.MaxHP
		G.Fx.Say(h, "냠냠! 배부르다")
		GS.Pop(player, h.Root.Position + Vector3.new(0, 6, 0), "몸 회복!", GREEN)
	elseif k == "ppc" then
		if not h.Def.Human then
			GS.Toast(player, "사람 몸이 필요해요!")
			return
		end
		prop.UsedUntil = t + 20
		ps.Heat = 0
		ps.Known = false
		for _, o in ipairs(G.Ents.List) do
			if o.ProvokedBy == player then
				o.ProvokedUntil = 0
			end
			o.Aware = false
		end
		GS.Banner(player, "🖥️ 수배 기록 삭제!", "경계가 0이 됐다")
	elseif k == "bed" then
		if h.Def.Vehicle then
			return
		end
		prop.UsedUntil = t + 30
		h.HP = h.MaxHP
		ps.Heat *= 0.7
		G.Fx.Say(h, "쿨쿨… 잘 잤다!")
	elseif k == "coffee" then
		if not h.Def.Human then
			GS.Toast(player, "사람 몸이 필요해요!")
			return
		end
		prop.UsedUntil = t + 20
		ps.CoffeeUntil = t + 12
		G.Fx.Say(h, "카페인 충전!")
	elseif k == "specimen" then
		G.World.BreakProp(prop, player)
		return
	elseif k == "atm" then
		G.Fx.Say(h, "돈이다!")
		G.World.BreakProp(prop, player)
		G.Combat.Scare(h, 20, 1, player)
		GS.AddChaos(player, 10, prop.Pos)
	else
		return
	end
	GS.Event(player, { k = "ia", kind = k })
end

local function upgrade(ps, id)
	local def
	for _, u in ipairs(GD.Upgrades) do
		if u.Id == id then
			def = u
		end
	end
	if not def then
		return
	end
	local lv = ps.Upg[id] or 0
	if lv >= def.Max then
		return
	end
	local cost = GD.UpgradeCost(lv)
	if ps.Bio < cost then
		GS.Toast(ps.Player, "🧬이 부족해요!")
		return
	end
	ps.Bio -= cost
	ps.Upg[id] = lv + 1
	if id == "hp" then
		ps.GhostMax += 1
		ps.GhostHP += 1
	end
	GS.Toast(ps.Player, `{def.Icon} {def.Name} Lv.{lv + 1}!`)
	save(ps)
end

---------------------------------------------------------------------
-- 시작
---------------------------------------------------------------------
local function startPlay(ps)
	if ps.Playing or not ps.Loaded then
		return
	end
	local ghost = G.Ents.Spawn("ghost", G.World.StartPos(), { IsGhost = true, Possessor = ps.Player })
	ps.Ghost = ghost
	ps.Host = nil
	ps.GhostMax = 3 + ps.Upg.hp
	ps.GhostHP = ps.GhostMax
	ps.Dry = 0
	ps.Heat = 0
	ps.Chaos = 0
	ps.Stars = 0
	ps.Known = false
	ps.LastSeen = nil
	ps.S5Run = 0
	ps.InvUntil = now() + 1.5
	ps.Playing = true
	setCharacter(ps, ghost)
	ps.Player:SetAttribute("Playing", true)
	GS.Banner(ps.Player, "👻 둥실둥실!", "몸에 닿거나 B(E키)로 빙의해요")
end

local function newState(player: Player)
	local upg = {}
	for _, u in ipairs(GD.Upgrades) do
		upg[u.Id] = 0
	end
	local fear, own = {}, {}
	for i = 1, 81 do
		fear[i] = 0
		own[i] = false
	end
	return {
		Player = player,
		Loaded = false,
		CanSave = false,
		Playing = false,
		Ghost = nil,
		Host = nil,
		Body = nil,
		GhostHP = 3,
		GhostMax = 3,
		InvUntil = 0,
		Dry = 0,
		NoInfUntil = 0,
		LastHost = nil,
		LastHostUntil = 0,
		Heat = 0,
		Chaos = 0,
		Known = false,
		LastSeen = nil,
		LastSeenT = 0,
		LastChaosT = -99,
		Stars = 0,
		S5Run = 0,
		S5Acc = 0,
		AbilityReady = 0,
		SkillReady = 0,
		InvisUntil = 0,
		NitroUntil = 0,
		CoffeeUntil = 0,
		WallPassUntil = 0,
		LeapUntil = 0,
		LeapCd = 0,
		DashUntil = 0,
		TpCd = 0,
		Bio = 0,
		Upg = upg,
		Mi = 1,
		MProg = 0,
		Best = 0,
		Own = own,
		Fear = fear,
		HudT = 0,
		HintT = 0,
	}
end

local function loadData(ps)
	if not store then
		ps.Loaded = true
		return
	end
	local ok, data = pcall(function()
		return store:GetAsync("u_" .. ps.Player.UserId)
	end)
	if ok then
		ps.CanSave = true
		if type(data) == "table" then
			ps.Bio = tonumber(data.Bio) or 0
			ps.Mi = tonumber(data.Mi) or 1
			ps.Best = tonumber(data.Best) or 0
			if type(data.Upg) == "table" then
				for k, v in pairs(data.Upg) do
					if ps.Upg[k] ~= nil then
						ps.Upg[k] = tonumber(v) or 0
					end
				end
			end
			if type(data.Own) == "table" then
				for _, i in ipairs(data.Own) do
					if ps.Own[i] ~= nil then
						ps.Own[i] = true
					end
				end
			end
		end
	else
		warn("[Bingui] 불러오기 실패:", data)
	end
	ps.Loaded = true
end

---------------------------------------------------------------------
-- 매 프레임
---------------------------------------------------------------------
local function updateHud(ps)
	local p = ps.Player
	local body = ps.Body
	p:SetAttribute("Bio", math.floor(ps.Bio))
	p:SetAttribute("Heat", math.floor(ps.Heat))
	p:SetAttribute("Stars", ps.Stars)
	p:SetAttribute("Mission", ps.Mi)
	p:SetAttribute("MProg", ps.MProg)
	p:SetAttribute("Upg", HttpService:JSONEncode(ps.Upg))
	p:SetAttribute("Night", GS.IsNight())
	local owned = 0
	for i = 1, 81 do
		if ps.Own[i] then
			owned += 1
		end
	end
	p:SetAttribute("Owned", owned)
	if body then
		p:SetAttribute("BodyType", body.Type)
		p:SetAttribute("BodyName", body.Def.Name)
		p:SetAttribute("AbilityName", body.Def.Ability or "")
		p:SetAttribute("SkillName", if body.Def.Skill then body.Def.Skill[1] else "")
		if body.IsGhost then
			p:SetAttribute("Life", math.clamp(1 - ps.Dry / dryMax(ps), 0, 1))
		else
			p:SetAttribute("Life", math.clamp(body.HP / body.MaxHP, 0, 1))
		end
	end
	p:SetAttribute("GhostHP", ps.GhostHP)
	p:SetAttribute("GhostMax", ps.GhostMax)
end

local function tickPlayer(ps, dt)
	local t = now()
	local player = ps.Player
	local body = ps.Body
	if not body then
		return
	end

	if ps.Host then
		local h = ps.Host
		local def = h.Def
		local speed = def.Speed
		if t < ps.NitroUntil then
			speed *= 1.8
		end
		if t < ps.CoffeeUntil and not def.Vehicle then
			speed *= 1.55
		end
		h.Hum.WalkSpeed = speed

		h.HP -= h.MaxHP / (def.Life * lifeMul(ps)) * dt
		if h.HP <= 0 then
			G.Combat.Kill(h, nil, nil)
			return
		end

		if def.Key then
			local gate = G.World.Gates[def.Key]
			if gate and not gate.Open and (gate.Pos - h.Root.Position).Magnitude < 12 then
				G.World.OpenGate(def.Key, player)
			end
		end

		if h.Type == "citizen" then
			local inside = false
			for _, f in ipairs(G.World.Fountains) do
				if flat(f.Pos - h.Root.Position).Magnitude < f.R - 0.5 then
					inside = true
				end
			end
			if inside and not ps.Splashed then
				ps.Splashed = true
				G.Fx.Say(h, "퐁당!")
				G.World.Debris(h.Root.Position, 14, { Color3.fromRGB(143, 216, 255), Color3.new(1, 1, 1) }, 0.5, 25)
				GS.AddChaos(player, 8, h.Root.Position)
				GS.Event(player, { k = "fountain" })
			elseif not inside then
				ps.Splashed = false
			end
		end

		if ps.WallPassOn and t >= ps.WallPassUntil then
			ps.WallPassOn = false
			setGroup(h, "Bodies")
		end
		if ps.InvisParts and t >= ps.InvisUntil then
			for p, tr in pairs(ps.InvisParts) do
				if p.Parent then
					p.Transparency = tr
				end
			end
			ps.InvisParts = nil
		end
	else
		-- 영혼 상태
		ps.Dry += dt
		if ps.Dry >= dryMax(ps) then
			G.World.Debris(body.Root.Position, 16, { Color3.fromRGB(207, 234, 255), Color3.fromRGB(179, 156, 255), Color3.new(1, 1, 1) }, 0.6, 20)
			gameOver(ps, "dry")
			return
		end
		if t >= ps.NoInfUntil then
			local bonus = if t < ps.LeapUntil then 1.2 else 0.5
			for _, e in ipairs(G.Ents.Near(body.Root.Position, body.R + 4)) do
				if e ~= body and not e.IsGhost and not e.Possessor and canPossess(e) and not (e == ps.LastHost and t < ps.LastHostUntil) then
					if flat(e.Root.Position - body.Root.Position).Magnitude < body.R + e.R + bonus then
						GS.Infect(ps, e)
						break
					end
				end
			end
		end
	end

	if t < ps.DashUntil then
		G.Combat.DashTick(ps)
	end

	-- 경계 감소
	if t - ps.LastChaosT > 4 then
		ps.Heat = math.max(0, ps.Heat - (5 + ps.Heat * 0.04) * dt)
	end
	if ps.Known and t - ps.LastSeenT > 10 then
		ps.Known = false
	end

	local s = GD.StarsFor(ps.Heat)
	if s > ps.Stars then
		GS.Banner(player, "경계 " .. string.rep("★", s), GD.StarSub[s])
		GS.Event(player, { k = "stars", n = s })
	end
	ps.Stars = s

	if s == 5 then
		ps.S5Acc += dt
		if ps.S5Acc >= 1 then
			ps.S5Acc -= 1
			GS.Event(player, { k = "s5tick" })
		end
		ps.S5Run += dt
	else
		ps.S5Run = 0
	end

	-- 대퇴마사
	if ps.S5Run > 25 and t >= bossCd then
		local alive = false
		for _, e in ipairs(G.Ents.List) do
			if e.Type == "exorcist" and not e.Dead then
				alive = true
			end
		end
		if not alive then
			local p = G.World.RoadPointNear(body.Root.Position, 30, 50)
			if p then
				bossCd = t + 200
				G.Ents.Spawn("exorcist", p, { AI = "hunt", ProvokedBy = player, ProvokedUntil = t + 600 })
				GS.Banner(player, "대퇴마사 등장!!", "결계와 부적을 조심해!")
				GS.Broadcast("Toast", "📰 속보: 대퇴마사, 유령 퇴치를 위해 직접 출동")
			end
		end
	end

	-- 자동 달성 미션
	local m = GD.Missions[ps.Mi]
	if m and AUTO[m.Id] and AUTO[m.Id](ps) then
		completeMission(ps)
	end

	if t >= ps.HintT then
		ps.HintT = t + 1
		local ok, hint = pcall(missionHint, ps)
		player:SetAttribute("Hint", if ok then hint else nil)
	end
	if t >= ps.HudT then
		ps.HudT = t + 0.1
		updateHud(ps)
	end
end

local function tickWorld(dt)
	dayT += dt
	local t = dayT % GD.DAYLEN
	local clock
	if t < 150 then
		clock = 8 + t / 150 * 9
	elseif t < 175 then
		clock = 17 + (t - 150) / 25 * 3
	elseif t < 275 then
		clock = 20 + (t - 175) / 100 * 8
	else
		clock = 4 + (t - 275) / 25 * 4
	end
	Lighting.ClockTime = clock % 24
	local night = GS.IsNight()
	if night ~= wasNight then
		wasNight = night
		if night then
			GS.Broadcast("Banner", "🌙 밤", "퇴마사 순찰 시작")
		else
			GS.Broadcast("Banner", "☀️ 아침", "시민들이 거리로 나온다")
		end
	end
end

---------------------------------------------------------------------
-- 초기화
---------------------------------------------------------------------
function GS.Init(g, remotes: Folder)
	G = g
	remote = remotes:WaitForChild("Event") :: RemoteEvent
	local action = remotes:WaitForChild("Action") :: RemoteEvent

	local ok, err = pcall(function()
		store = DataStoreService:GetDataStore("BinguiData_v1")
	end)
	if not ok then
		warn("[Bingui] DataStore 사용 불가 (Studio라면 API 서비스 접근 허용을 켜세요):", err)
	end

	Lighting.Ambient = Color3.fromRGB(90, 85, 110)
	Lighting.OutdoorAmbient = Color3.fromRGB(120, 115, 140)

	action.OnServerEvent:Connect(function(player, kind, arg)
		local ps = states[player]
		if not ps or type(kind) ~= "string" then
			return
		end
		if kind == "start" then
			startPlay(ps)
			return
		elseif kind == "upgrade" then
			if type(arg) == "string" then
				upgrade(ps, arg)
			end
			return
		end
		if not ps.Playing then
			return
		end
		local okA, errA = pcall(function()
			if kind == "ability" then
				G.Combat.PlayerAbility(ps)
			elseif kind == "possess" then
				possessAction(ps)
			elseif kind == "skill" then
				G.Combat.PlayerSkill(ps)
			elseif kind == "interact" and type(arg) == "number" then
				interact(ps, arg)
			end
		end)
		if not okA then
			warn("[Action]", kind, errA)
		end
	end)

	local function onAdded(player: Player)
		local ps = newState(player)
		states[player] = ps
		loadData(ps)
		if not player.Parent then
			states[player] = nil
			return
		end
		updateHud(ps)
		player:SetAttribute("Loaded", true)
		if not ps.CanSave then
			GS.Toast(player, "⚠ 저장 기능이 꺼져 있어요 (진행이 저장되지 않음)")
		end
	end
	Players.PlayerAdded:Connect(onAdded)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(onAdded, p)
	end

	Players.PlayerRemoving:Connect(function(player)
		local ps = states[player]
		states[player] = nil
		if not ps then
			return
		end
		if ps.Host then
			clearHostEffects(ps, ps.Host)
			releaseHost(ps, ps.Host, nil)
		end
		if ps.Ghost then
			G.Ents.Remove(ps.Ghost)
		end
		G.Ents.ClearResponders(player)
		save(ps)
	end)

	task.spawn(function()
		while true do
			task.wait(60)
			for _, ps in pairs(states) do
				save(ps)
			end
		end
	end)

	game:BindToClose(function()
		for _, ps in pairs(states) do
			save(ps)
		end
		task.wait(3)
	end)

	RunService.Heartbeat:Connect(function(dt)
		tickWorld(dt)
		for _, ps in pairs(states) do
			if ps.Playing then
				local okT, errT = pcall(tickPlayer, ps, dt)
				if not okT then
					warn("[Tick]", errT)
				end
			end
		end
	end)
end

return GS
