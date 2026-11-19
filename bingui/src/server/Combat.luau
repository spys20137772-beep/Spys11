-- 전투: 데미지, 죽음, 폭발, 근접/사격, 몸별 능력(A)과 고유 스킬, 들이받기
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local GD = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameData"))

local Combat = {}
local G
local rng = Random.new()

local YELLOW = Color3.fromRGB(255, 240, 150)
local RED = Color3.fromRGB(255, 70, 70)
local BLUE = Color3.fromRGB(140, 210, 255)
local TAL = Color3.fromRGB(255, 220, 90)

local losParams: RaycastParams

local function now()
	return os.clock()
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function pick(t)
	return t[rng:NextInteger(1, #t)]
end

---------------------------------------------------------------------
-- 시야
---------------------------------------------------------------------
function Combat.LineOfSight(a: Vector3, b: Vector3): boolean
	local from = a + Vector3.new(0, 1.5, 0)
	local to = b + Vector3.new(0, 1.5, 0)
	local result = workspace:Raycast(from, to - from, losParams)
	return result == nil
end

---------------------------------------------------------------------
-- 데미지 / 죽음
---------------------------------------------------------------------
local function playerOf(ent)
	return ent and ent.Possessor or nil
end

function Combat.Hurt(e, dmg: number, src, byPlayer: Player?)
	if not e or e.Dead or e.Hidden then
		return
	end
	if e.IsGhost then
		if byPlayer == nil or byPlayer ~= e.Possessor then
			G.Players.HurtGhost(e.Possessor)
		end
		return
	end
	if byPlayer then
		dmg *= G.Players.PowerMul(byPlayer)
	end
	e.HP -= dmg
	G.Fx.UpdateHealthBar(e)

	if not e.Possessor then
		if e.Def.Hostile then
			if byPlayer then
				e.ProvokedBy = byPlayer
				e.ProvokedUntil = now() + 7
			end
		elseif not e.Def.Vehicle then
			G.Ents.Panic(e, if src and src.Root then src.Root.Position else e.Root.Position, 4)
			if rng:NextNumber() < 0.35 and now() > e.SayUntil then
				G.Fx.Say(e, pick({ "으악!", "살려줘!", "뭐야?!", "아파!" }))
			end
		end
		if byPlayer and dmg >= 5 then
			G.Players.AddChaos(byPlayer, 2, e.Root.Position, false)
		end
	end
	if dmg >= 4 and not e.Def.Vehicle then
		G.World.Debris(e.Root.Position, 3, { if e.Type == "robot" then Color3.fromRGB(255, 216, 74) else Color3.fromRGB(255, 106, 106) }, 0.4, 15)
	end
	if e.HP <= 0 then
		Combat.Kill(e, src, byPlayer)
	end
end

function Combat.Kill(e, src, byPlayer: Player?)
	if e.Dead or e.IsGhost then
		return
	end
	local pos = e.Root.Position
	local host = e.Possessor
	if host then
		G.Players.OnHostDied(host, e)
	end
	e.Dead = true
	e.HP = 0
	e.Model:SetAttribute("Dead", true)
	e.RemoveAt = now() + (if e.Def.Vehicle then 12 elseif e.Def.Human then 16 else 6)

	for _, gui in ipairs(e.Model:GetDescendants()) do
		if gui:IsA("BillboardGui") then
			gui.Enabled = false
		end
	end

	pcall(function()
		e.Hum:MoveTo(pos)
		e.Root.Anchored = true
		if e.Def.Vehicle then
			for _, p in ipairs(e.Model:GetDescendants()) do
				if p:IsA("BasePart") and p ~= e.Root then
					p.Color = p.Color:Lerp(Color3.fromRGB(30, 28, 26), 0.75)
				end
			end
		else
			local yaw = select(2, e.Root.CFrame:ToOrientation())
			e.Model:PivotTo(CFrame.new(pos.X, 0.4 + e.Root.Size.X / 2 + 0.2, pos.Z) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, math.rad(90)))
		end
	end)

	if e.Type == "exorcist" then
		G.Players.BossDefeated(byPlayer)
	end
	if e.Def.Vehicle then
		Combat.Explode(pos, if e.Type == "tank" then 12 else 9, if e.Type == "tank" then 110 else 65, byPlayer, e)
	end
	if byPlayer then
		G.Players.AddChaos(byPlayer, GD.KillPoints[e.Type] or 10, pos)
		G.Players.Event(byPlayer, { k = "kill", type = e.Type })
	end
	G.Ents.PanicNear(pos, 23, 5)
end

---------------------------------------------------------------------
-- 폭발
---------------------------------------------------------------------
function Combat.Explode(pos: Vector3, radius: number, dmg: number, byPlayer: Player?, src)
	G.Fx.Explosion(pos, radius)
	G.Fx.Sound("boom", pos)
	for _, e in ipairs(G.Ents.Near(pos, radius)) do
		if e ~= src then
			local d = (e.Root.Position - pos).Magnitude
			local f = 1 - math.clamp(d / (radius + e.R), 0, 1) * 0.6
			Combat.Hurt(e, dmg * f, src, byPlayer)
			if not e.Dead and e.Type ~= "tank" and not e.Possessor and not e.IsGhost then
				local dir = flat(e.Root.Position - pos)
				if dir.Magnitude > 0.1 then
					e.Root.AssemblyLinearVelocity = dir.Unit * 45 * f + Vector3.new(0, 20 * f, 0)
				end
				e.StunUntil = math.max(e.StunUntil, now() + 0.5)
			end
		end
	end
	for _, prop in ipairs(G.World.PropsNear(pos, radius)) do
		G.World.DamageProp(prop, dmg, byPlayer)
	end
	G.World.HitBuildingsInRadius(pos, radius, dmg, byPlayer)
	for key, gate in pairs(G.World.Gates) do
		if not gate.Open and (gate.Pos - pos).Magnitude < radius + 6 then
			G.World.OpenGate(key, byPlayer)
		end
	end
	G.Ents.PanicNear(pos, 32, 5)
end

---------------------------------------------------------------------
-- 조준 / 근접 / 사격
---------------------------------------------------------------------
local function lookOf(e): Vector3
	local l = flat(e.Root.CFrame.LookVector)
	return if l.Magnitude > 0.01 then l.Unit else Vector3.new(0, 0, -1)
end

local function canTarget(shooter, e): boolean
	if e == shooter or e.Dead or e.Hidden then
		return false
	end
	-- 자기 영혼은 조준 안 함
	if e.IsGhost and shooter.Possessor and e.Possessor == shooter.Possessor then
		return false
	end
	return true
end

function Combat.AimTarget(shooter, range: number)
	local pos = shooter.Root.Position
	local look = lookOf(shooter)
	local best, bs = nil, math.huge
	for _, e in ipairs(G.Ents.Near(pos, range)) do
		if canTarget(shooter, e) and not e.IsGhost then
			local to = flat(e.Root.Position - pos)
			local d = to.Magnitude
			if d > 0.1 then
				local ang = math.acos(math.clamp(look:Dot(to.Unit), -1, 1))
				if ang < 1.1 then
					local score = d + ang * 15 - (if e.Def.Hostile then 6 else 0)
					if score < bs then
						best, bs = e, score
					end
				end
			end
		end
	end
	return best
end

local function aimPoint(shooter, range: number): Vector3
	local t = Combat.AimTarget(shooter, range)
	if t then
		return t.Root.Position
	end
	return shooter.Root.Position + lookOf(shooter) * range
end

function Combat.Melee(attacker, dmg: number, range: number, byPlayer: Player?): boolean
	local pos = attacker.Root.Position
	local look = lookOf(attacker)
	local hit = false
	for _, e in ipairs(G.Ents.Near(pos, attacker.R + range + 1)) do
		if canTarget(attacker, e) and not e.Def.Fly and (not e.IsGhost or byPlayer == nil) then
			local to = flat(e.Root.Position - pos)
			local d = to.Magnitude
			if d <= attacker.R + e.R + range then
				local ok = d < attacker.R + e.R or (d > 0.1 and look:Dot(to.Unit) > math.cos(1.2))
				if ok then
					Combat.Hurt(e, dmg, attacker, byPlayer)
					if not e.Dead and e.Type ~= "tank" and not e.Possessor and not e.IsGhost and d > 0.1 then
						e.Root.AssemblyLinearVelocity = to.Unit * 28 + Vector3.new(0, 8, 0)
						e.StunUntil = math.max(e.StunUntil, now() + 0.35)
					end
					hit = true
				end
			end
		end
	end
	if not hit then
		for _, prop in ipairs(G.World.PropsNear(pos + look * (attacker.R + range * 0.5), range)) do
			G.World.DamageProp(prop, dmg, byPlayer)
			hit = true
			break
		end
	end
	if not hit then
		local result = workspace:Raycast(pos, look * (attacker.R + range), losParams)
		if result then
			local b = G.World.BuildingFromPart(result.Instance)
			if b then
				G.World.DamageBuilding(b, dmg * 0.7, byPlayer)
				hit = true
			end
		end
	end
	G.World.Debris(pos + look * (attacker.R + 1), if hit then 4 else 1, { Color3.new(1, 1, 1) }, 0.3, 12)
	return hit
end

local function shotParams(shooter)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = { shooter.Model, G.World.Folders.Effects }
	-- 플레이어가 쏠 때는 자기 영혼/몸 제외
	params.FilterDescendantsInstances = exclude
	return params
end

function Combat.Shoot(shooter, aimAt: Vector3, opts, byPlayer: Player?)
	local origin = shooter.Root.Position + Vector3.new(0, 1, 0) + lookOf(shooter) * shooter.R
	local target = aimAt + Vector3.new(0, 0.5, 0)
	local dir = target - origin
	if dir.Magnitude < 0.1 then
		dir = lookOf(shooter)
	end
	local spread = opts.Spread or 0
	local yaw = rng:NextNumber(-spread, spread)
	dir = (CFrame.Angles(0, yaw, 0) * dir.Unit) * (opts.Range or 40)
	local result = workspace:Raycast(origin, dir, shotParams(shooter))
	local hitPos = if result then result.Position else origin + dir
	G.Fx.Tracer(origin, hitPos, opts.Color or YELLOW, opts.Width)
	if result then
		local e = G.Ents.FromPart(result.Instance)
		if e then
			if canTarget(shooter, e) then
				Combat.Hurt(e, opts.Dmg, shooter, byPlayer)
			end
			return
		end
		local prop = G.World.PropFromPart(result.Instance)
		if prop then
			G.World.DamageProp(prop, opts.Dmg, byPlayer)
			return
		end
		local b = G.World.BuildingFromPart(result.Instance)
		if b then
			G.World.DamageBuilding(b, opts.Dmg * 0.5, byPlayer)
		end
	end
end

-- 성수 뿌리기 (원뿔 범위)
function Combat.Spray(shooter, dmg: number, range: number, byPlayer: Player?, aimAt: Vector3?)
	local pos = shooter.Root.Position
	local look = if aimAt and flat(aimAt - pos).Magnitude > 0.1 then flat(aimAt - pos).Unit else lookOf(shooter)
	for _, e in ipairs(G.Ents.Near(pos, range)) do
		if canTarget(shooter, e) then
			local to = flat(e.Root.Position - pos)
			if to.Magnitude < 0.1 or look:Dot(to.Unit) > math.cos(0.5) then
				Combat.Hurt(e, dmg, shooter, byPlayer)
			end
		end
	end
	for _ = 1, 2 do
		local a = rng:NextNumber(-0.35, 0.35)
		G.Fx.Tracer(pos + Vector3.new(0, 1, 0), pos + Vector3.new(0, 0.5, 0) + (CFrame.Angles(0, a, 0) * look) * range, BLUE, 0.35)
	end
end

function Combat.Scare(src, radius: number, chaosPer: number, byPlayer: Player?): number
	local pos = src.Root.Position
	local n = 0
	for _, e in ipairs(G.Ents.Near(pos, radius)) do
		if e ~= src and not e.Possessor and not e.Def.Hostile and not e.Def.Vehicle and not e.IsGhost then
			if e.PanicUntil < now() and rng:NextNumber() < 0.3 then
				G.Fx.Say(e, pick({ "꺄악!", "뭐야뭐야", "도망쳐!" }))
			end
			G.Ents.Panic(e, pos, 3.5)
			n += 1
		end
	end
	if byPlayer and chaosPer > 0 and n > 0 then
		G.Players.AddChaos(byPlayer, math.min(8, n * chaosPer), pos)
	end
	return n
end

---------------------------------------------------------------------
-- NPC 공격
---------------------------------------------------------------------
function Combat.NpcAttack(e, target)
	local t = now()
	local tpos = target.Root.Position
	if e.Type == "police" then
		e.Cd = t + 0.8
		Combat.Shoot(e, tpos, { Dmg = 12, Range = 42, Spread = 0.08 })
	elseif e.Type == "soldier" then
		e.Cd = t + 0.35
		Combat.Shoot(e, tpos, { Dmg = 10, Range = 44, Spread = 0.12 })
	elseif e.Type == "robot" then
		e.Cd = t + 0.6
		Combat.Shoot(e, tpos, { Dmg = 18, Range = 42, Spread = 0.04, Color = RED, Width = 0.3 })
	elseif e.Type == "hazmat" then
		e.Cd = t + 0.25
		Combat.Spray(e, 6, 13, nil, tpos)
	elseif e.Type == "dog" then
		e.Cd = t + 0.8
		Combat.Melee(e, 14, 2.5, nil)
		G.Fx.Say(e, "왈!")
	elseif e.Type == "tank" then
		e.Cd = t + 2.5
		local from = e.Root.Position + Vector3.new(0, 3, 0)
		G.Fx.Lob(from, tpos, Color3.fromRGB(60, 60, 60), 1, 0.45, function()
			Combat.Explode(tpos, 9, 60, nil, e)
		end)
	elseif e.Type == "exorcist" then
		e.Cd = t + 1.2
		local look = flat(tpos - e.Root.Position)
		for i = -2, 2 do
			local dir = CFrame.Angles(0, i * 0.18, 0) * (if look.Magnitude > 0.1 then look.Unit else lookOf(e))
			Combat.Shoot(e, e.Root.Position + dir * 38, { Dmg = 10, Range = 38, Color = TAL, Width = 0.4 })
		end
		if t > (e.ZoneCd or 0) then
			e.ZoneCd = t + 8
			Combat.Zone(e, tpos, 14, 40, nil)
			G.Fx.Say(e, "급급여율령!")
		end
	end
end

-- 퇴마진: 1초 뒤 범위 피해
function Combat.Zone(src, pos: Vector3, radius: number, dmg: number, byPlayer: Player?)
	local ring = Instance.new("Part")
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 220, 90)
	ring.Transparency = 0.6
	ring.Size = Vector3.new(0.3, radius * 2, radius * 2)
	ring.CFrame = CFrame.new(pos.X, 0.6, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = G.World.Folders.Effects
	task.delay(1, function()
		TweenService:Create(ring, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		Debris:AddItem(ring, 0.5)
		for _, e in ipairs(G.Ents.Near(pos, radius)) do
			if e ~= src and not (e.IsGhost and byPlayer and e.Possessor == byPlayer) then
				Combat.Hurt(e, dmg, src, byPlayer)
				if not e.Possessor and not e.IsGhost then
					e.StunUntil = math.max(e.StunUntil, now() + 1)
				end
			end
		end
	end)
end

---------------------------------------------------------------------
-- 플레이어 능력 (A)
---------------------------------------------------------------------
local ABILITY_CD = {
	ghost = 0.45, mouse = 1.1, cat = 0.9, pigeon = 0.32, citizen = 0.4, scientist = 1.1, police = 0.28, dog = 0.45,
	hazmat = 0.1, soldier = 0.12, robot = 0.16, mutant = 0.6, car = 1, pcar = 1, tank = 0.85, exorcist = 0.5,
}

function Combat.PlayerAbility(ps)
	local pe = ps.Body
	local t = now()
	if not pe or not G.Ents.Active(pe) or t < ps.AbilityReady then
		return
	end
	local player = ps.Player
	local bt = pe.Type
	ps.AbilityReady = t + (ABILITY_CD[bt] or 0.5)

	if bt == "ghost" then
		local lv = ps.Upg.polter
		if lv > 0 then
			ps.AbilityReady = t + 2.4
			local r = 9.6 + 3.2 * lv
			G.Fx.Explosion(pe.Root.Position, r * 0.5)
			for _, e in ipairs(G.Ents.Near(pe.Root.Position, r)) do
				if e ~= pe and not e.IsGhost then
					local dir = flat(e.Root.Position - pe.Root.Position)
					if e.Type ~= "tank" and not e.Possessor and dir.Magnitude > 0.1 then
						e.Root.AssemblyLinearVelocity = dir.Unit * 48 + Vector3.new(0, 15, 0)
						e.StunUntil = math.max(e.StunUntil, t + 0.8)
					end
					Combat.Hurt(e, 5 * lv, pe, player)
				end
			end
			for _, prop in ipairs(G.World.PropsNear(pe.Root.Position, r)) do
				G.World.DamageProp(prop, 15 * lv, player)
			end
		else
			G.Players.Leap(ps)
		end
	elseif bt == "mutant" then
		Combat.Melee(pe, 32, 3.2, player)
		G.Fx.Say(pe, pick({ "끼에엑!", "크르르", "꾸웩!" }))
	elseif bt == "mouse" then
		G.Fx.Say(pe, "찍찍!")
		Combat.Scare(pe, 18, 1.5, player)
		Combat.Melee(pe, 6, 1, player)
	elseif bt == "cat" then
		G.Fx.Say(pe, "냐앙!")
		G.Players.Dash(ps, 60, 0.25, 26)
	elseif bt == "pigeon" then
		Combat.Poop(ps)
	elseif bt == "citizen" then
		Combat.Melee(pe, 16, 2.6, player)
	elseif bt == "scientist" then
		local to = aimPoint(pe, 28)
		G.Fx.Say(pe, "실험 시작!")
		G.Fx.Lob(pe.Root.Position + Vector3.new(0, 2, 0), to, Color3.fromRGB(120, 255, 120), 0.8, 0.5, function()
			Combat.Explode(to, 6, 30, player, pe)
		end)
	elseif bt == "police" then
		Combat.Shoot(pe, aimPoint(pe, 38), { Dmg = 20, Range = 40, Spread = 0.05 }, player)
	elseif bt == "dog" then
		Combat.Melee(pe, 26, 2.3, player)
		G.Fx.Say(pe, "왈!")
	elseif bt == "hazmat" then
		Combat.Spray(pe, 8, 15, player, aimPoint(pe, 15))
	elseif bt == "soldier" then
		Combat.Shoot(pe, aimPoint(pe, 40), { Dmg = 15, Range = 42, Spread = 0.12 }, player)
	elseif bt == "robot" then
		Combat.Shoot(pe, aimPoint(pe, 40), { Dmg = 22, Range = 42, Spread = 0.03, Color = RED, Width = 0.3 }, player)
	elseif bt == "car" or bt == "pcar" then
		G.Fx.Say(pe, if bt == "car" then "빵빵!" else "삐뽀삐뽀!")
		Combat.Scare(pe, 24, 1, player)
	elseif bt == "exorcist" then
		local base = flat(aimPoint(pe, 38) - pe.Root.Position)
		base = if base.Magnitude > 0.1 then base.Unit else lookOf(pe)
		for i = -2, 2 do
			local dir = CFrame.Angles(0, i * 0.18, 0) * base
			Combat.Shoot(pe, pe.Root.Position + dir * 38, { Dmg = 16, Range = 38, Color = TAL, Width = 0.4 }, player)
		end
	elseif bt == "tank" then
		local to = aimPoint(pe, 49)
		G.Fx.Lob(pe.Root.Position + Vector3.new(0, 3, 0), to, Color3.fromRGB(60, 60, 60), 1, 0.4, function()
			Combat.Explode(to, 9, 90, player, pe)
		end)
	end
end

function Combat.Poop(ps)
	local pe = ps.Body
	local player = ps.Player
	local from = pe.Root.Position - Vector3.new(0, 1, 0)
	local ground = Vector3.new(from.X, 0.6, from.Z) + flat(pe.Root.AssemblyLinearVelocity) * 0.25
	G.Fx.Lob(from, ground, Color3.fromRGB(250, 250, 245), 0.5, 0.3, function()
		for _, e in ipairs(G.Ents.Near(ground, 2.5)) do
			if e ~= pe and not e.IsGhost and not e.Def.Fly and not e.Def.Vehicle then
				Combat.Hurt(e, 3, pe, player)
				G.Fx.Say(e, pick({ "으악 똥!", "내 머리!", "비둘기 이 녀석!" }))
				G.Players.AddChaos(player, 3, ground)
				G.Players.Event(player, { k = "poophit" })
				break
			end
		end
	end)
end

---------------------------------------------------------------------
-- 고유 스킬 (Q)
---------------------------------------------------------------------
local function freeSpot(pos: Vector3, size: Vector3): boolean
	local params = OverlapParams.new()
	params.FilterType = Enum.OverlapFilterType.Include
	params.FilterDescendantsInstances = { workspace.City.Buildings, workspace.City.Compounds }
	local parts = workspace:GetPartBoundsInBox(CFrame.new(pos), size, params)
	return #parts == 0
end

local SKILLS = {}

SKILLS.citizen = function(ps, h)
	G.Fx.Say(h, "꺄아아악!!")
	Combat.Scare(h, 34, 1.2, ps.Player)
	for _, o in ipairs(G.Ents.Near(h.Root.Position, 75, function(o)
		return o.Type == "police" and not o.Possessor and not o.Aware
	end)) do
		o.Home = h.Root.Position
		o.NextWander = 0
	end
end

SKILLS.police = function(ps, h)
	local t = Combat.AimTarget(h, 23)
	if t then
		t.StunUntil = now() + 5
		G.Fx.Say(t, "으앗! 수갑?!")
		G.Players.AddChaos(ps.Player, 3, t.Root.Position)
	else
		G.Fx.Say(h, "아무도 없네")
	end
end

SKILLS.scientist = function(ps, h)
	G.Players.SetInvisible(ps, 8)
	ps.Heat *= 0.7
	for _, e in ipairs(G.Ents.List) do
		e.Aware = false
	end
	G.Fx.Say(h, "짜잔~ 투명!")
end

SKILLS.soldier = function(ps, h)
	local center = h.Root.Position + lookOf(h) * 20
	G.Fx.Say(h, "공습 요청! 좌표 전송!")
	for i = 0, 5 do
		local p = center + Vector3.new(rng:NextNumber(-12, 12), 0, rng:NextNumber(-12, 12))
		task.delay(1.6 + i * 0.25, function()
			Combat.Explode(p, 10, 80, ps.Player, nil)
		end)
	end
end

SKILLS.hazmat = function(ps, h)
	G.Fx.Say(h, "퇴마!")
	for _, e in ipairs(G.Ents.Near(h.Root.Position, 14)) do
		if canTarget(h, e) then
			Combat.Hurt(e, 16, h, ps.Player)
		end
	end
	for i = 0, 11 do
		local dir = CFrame.Angles(0, i / 12 * math.pi * 2, 0) * Vector3.new(0, 0, -1)
		G.Fx.Tracer(h.Root.Position + Vector3.new(0, 1, 0), h.Root.Position + dir * 14, BLUE, 0.35)
	end
end

SKILLS.robot = function(ps, h)
	G.Fx.Explosion(h.Root.Position, 4)
	for _, o in ipairs(G.Ents.Near(h.Root.Position, 30)) do
		if o ~= h and (o.Def.Vehicle or o.Type == "robot") and not o.Possessor then
			o.StunUntil = now() + 4
		end
	end
	for _, prop in ipairs(G.World.PropsNear(h.Root.Position, 30)) do
		if prop.Kind == "lamp" then
			G.World.BreakProp(prop, ps.Player)
		end
	end
	G.Players.AddChaos(ps.Player, 10, h.Root.Position)
end

SKILLS.cat = function(ps, h)
	G.Fx.Say(h, "냥!")
	G.Players.WallPass(ps, 3.5)
end

SKILLS.dog = function(ps, h)
	G.Fx.Say(h, "아우우우~!")
	for _, o in ipairs(G.Ents.Near(h.Root.Position, 64)) do
		if o ~= h and not o.Possessor then
			if o.Type == "dog" then
				o.FollowUntil = now() + 18
				o.FollowPlayer = ps.Player
				o.ProvokedUntil = 0
				o.Aware = false
				o.Responder = nil
				o.AI = "wander"
				o.Def = setmetatable({ Hostile = false }, { __index = GD.Bodies.dog })
			elseif not o.Def.Hostile and not o.Def.Vehicle and (o.Root.Position - h.Root.Position).Magnitude < 21 then
				o.StunUntil = now() + 1.5
			end
		end
	end
end

SKILLS.mouse = function(ps, h)
	local look = lookOf(h)
	for d = 17, 4, -1 do
		local p = h.Root.Position + look * d
		if freeSpot(p, Vector3.new(1.5, 2, 2)) then
			G.World.Debris(h.Root.Position, 6, { Color3.fromRGB(138, 106, 74) }, 0.5, 12)
			h.Model:PivotTo(CFrame.lookAt(p, p + look))
			G.World.Debris(p, 6, { Color3.fromRGB(138, 106, 74) }, 0.5, 12)
			G.Fx.Say(h, "뿅!")
			break
		end
	end
end

SKILLS.pigeon = function(ps, h)
	local t = Combat.AimTarget(h, 18)
	if t then
		Combat.Hurt(t, 20, h, ps.Player)
		if not t.Possessor then
			t.StunUntil = now() + 1
		end
		G.Fx.Say(t, "아악 내 머리!")
	end
end

SKILLS.car = function(ps, h)
	G.Players.Nitro(ps, 2.5)
end
SKILLS.pcar = SKILLS.car

SKILLS.tank = function(ps, h)
	ps.Heat *= 0.7
	for _, e in ipairs(G.Ents.Near(h.Root.Position, 48)) do
		e.Aware = false
	end
	local smoke = Instance.new("Part")
	smoke.Anchored = true
	smoke.CanCollide = false
	smoke.CanQuery = false
	smoke.Transparency = 1
	smoke.Size = Vector3.new(26, 1, 26)
	smoke.CFrame = CFrame.new(h.Root.Position)
	smoke.Parent = G.World.Folders.Effects
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(Color3.fromRGB(200, 200, 200))
	emitter.Size = NumberSequence.new(4, 8)
	emitter.Transparency = NumberSequence.new(0.3, 1)
	emitter.Lifetime = NumberRange.new(2, 3)
	emitter.Rate = 40
	emitter.Speed = NumberRange.new(2, 4)
	emitter.Parent = smoke
	task.delay(5, function()
		emitter.Enabled = false
	end)
	Debris:AddItem(smoke, 8)
end

SKILLS.mutant = function(ps, h)
	local m = G.Ents.Spawn("mutant", h.Root.Position + lookOf(h) * 4)
	m.HP = 70
	G.Fx.Say(m, "끼엑?")
end

SKILLS.exorcist = function(ps, h)
	Combat.Zone(h, h.Root.Position, 16, 60, ps.Player)
	G.Fx.Say(h, "급급여율령!")
end

function Combat.PlayerSkill(ps)
	local h = ps.Host
	local t = now()
	if not h or not G.Ents.Active(h) or t < ps.SkillReady then
		return
	end
	local sk = h.Def.Skill
	local fn = SKILLS[h.Type]
	if not sk or not fn then
		return
	end
	ps.SkillReady = t + sk[2]
	ps.Player:SetAttribute("SkillReadyAt", workspace:GetServerTimeNow() + sk[2])
	fn(ps, h)
end

---------------------------------------------------------------------
-- 소품 / 건물 파괴 결과
---------------------------------------------------------------------
function Combat.OnPropBroken(prop, byPlayer: Player?)
	local pos = prop.Pos
	local k = prop.Kind
	local W = G.World
	local function chaos(n)
		if byPlayer then
			G.Players.AddChaos(byPlayer, n, pos)
		end
	end
	if k == "stall" then
		W.Debris(pos + Vector3.new(0, 2, 0), 12, { Color3.fromRGB(143, 208, 255), Color3.fromRGB(255, 176, 74), Color3.fromRGB(224, 224, 224) }, 0.7, 25)
		chaos(15)
	elseif k == "bin" then
		W.Debris(pos + Vector3.new(0, 1, 0), 8, { Color3.fromRGB(79, 138, 58), Color3.fromRGB(201, 180, 138) }, 0.6, 20)
		chaos(5)
		if rng:NextNumber() < 0.5 then
			G.Ents.Spawn("mouse", pos + Vector3.new(2, 0, 2))
		end
	elseif k == "hydrant" then
		W.Debris(pos + Vector3.new(0, 1, 0), 14, { Color3.fromRGB(143, 216, 255), Color3.new(1, 1, 1) }, 0.6, 30)
		chaos(10)
	elseif k == "barrel" then
		Combat.Explode(pos, 10, 85, byPlayer, nil)
		chaos(15)
	elseif k == "pump" then
		Combat.Explode(pos, 16, 120, byPlayer, nil)
		chaos(30)
	elseif k == "crate" then
		Combat.Explode(pos, 8.5, 70, byPlayer, nil)
	elseif k == "statue" then
		W.Debris(pos + Vector3.new(0, 3, 0), 16, { Color3.fromRGB(168, 172, 180), Color3.fromRGB(200, 204, 212) }, 1, 25)
		chaos(20)
		if byPlayer then
			G.Players.Toast(byPlayer, "📰 공원 동상 쓰러져… 시민들 \"저절로 넘어졌다\"")
		end
	elseif k == "specimen" then
		W.Debris(pos + Vector3.new(0, 3, 0), 16, { Color3.fromRGB(143, 224, 208), Color3.fromRGB(79, 191, 46) }, 0.7, 25)
		local m = G.Ents.Spawn("mutant", pos + Vector3.new(0, 0, 4))
		m.StunUntil = now() + 0.5
		G.Fx.Say(m, "끼에에엑!!")
		chaos(25)
		G.Players.Broadcast("Toast", "📰 연구소에서 정체불명 생명체 탈출!")
		if byPlayer then
			G.Players.Event(byPlayer, { k = "ia", kind = "specimen" })
		end
	elseif k == "tv" or k == "pc" or k == "ppc" or k == "atm" or k == "vending" then
		W.Debris(pos + Vector3.new(0, 2, 0), 10, { Color3.fromRGB(255, 246, 160), Color3.fromRGB(90, 240, 255) }, 0.4, 25)
		chaos(6)
	else
		W.Debris(pos + Vector3.new(0, 1, 0), 8, { Color3.fromRGB(168, 120, 74), Color3.fromRGB(216, 200, 168) }, 0.6, 20)
		chaos(3)
	end
	if byPlayer then
		G.Players.Event(byPlayer, { k = "break", kind = k })
	end
end

function Combat.OnBuildingDestroyed(b, byPlayer: Player?)
	local center = b.CFrame.Position
	local name = GD.BuildingName[b.Kind] or "건물"
	if byPlayer then
		G.Players.AddChaos(byPlayer, GD.BuildingPoints[b.Kind] or 50, center)
		G.Players.Event(byPlayer, { k = "house", kind = b.Kind })
		G.Players.Pop(byPlayer, center + Vector3.new(0, b.Size.Y, 0), "와르르!!", Color3.fromRGB(255, 176, 74))
		G.Players.Broadcast("Toast", pick({ "📰 " .. name .. " 붕괴! 원인 불명의 괴현상", "📰 " .. name .. " 와르르… 목격자 \"유령을 봤다\"", "📰 또 무너졌다! 이번엔 " .. name }))
	end
	local t = if b.Kind == "police" then "police" elseif b.Kind == "lab" then "scientist" elseif b.Kind == "base" then "soldier" else "citizen"
	local n = if b.Kind == "house" then rng:NextInteger(1, 2) else rng:NextInteger(2, 3)
	for _ = 1, n do
		local p = center + Vector3.new(rng:NextNumber(-b.Size.X * 0.3, b.Size.X * 0.3), 2, rng:NextNumber(-b.Size.Z * 0.3, b.Size.Z * 0.3))
		local e = G.Ents.Spawn(t, p)
		e.PanicUntil = now() + 6
		e.PanicFrom = center
		e.StunUntil = now() + 0.4
		G.Fx.Say(e, pick(if b.Kind == "house" then { "우리 집!!", "내 집이…!", "으아악!" } else { "건물이…!", "콜록콜록", "대피해!" }))
		if e.Def.Hostile and byPlayer then
			e.ProvokedBy = byPlayer
			e.ProvokedUntil = now() + 5
		end
	end
	G.Ents.PanicNear(center, 34, 5)
end

---------------------------------------------------------------------
-- 들이받기 (차량) / 덮치기 (고양이)
---------------------------------------------------------------------
local function ramTick(vehicle, byPlayer: Player?)
	local root = vehicle.Root
	local vel = flat(root.AssemblyLinearVelocity)
	local speed = vel.Magnitude
	if speed < 12 then
		return
	end
	local t = now()
	local look = lookOf(vehicle)
	local front = root.Position + look * vehicle.R * 0.8
	local spx = speed / GD.K
	local isTank = vehicle.Type == "tank"
	for _, o in ipairs(G.Ents.Near(front, vehicle.R * 0.8)) do
		if o ~= vehicle and not o.IsGhost and t >= (o.RamCd or 0) and not o.Def.Fly then
			o.RamCd = t + 0.45
			Combat.Hurt(o, (spx - 80) * (if isTank then 0.25 else 0.13), vehicle, byPlayer)
			if not o.Dead and o.Type ~= "tank" and not o.Possessor then
				local dir = flat(o.Root.Position - root.Position)
				dir = if dir.Magnitude > 0.1 then dir.Unit else look
				o.Root.AssemblyLinearVelocity = dir * speed * 0.9 + Vector3.new(0, 12, 0)
				o.StunUntil = math.max(o.StunUntil, t + 0.6)
			end
		end
	end
	for _, prop in ipairs(G.World.PropsNear(front, vehicle.R * 0.6)) do
		G.World.DamageProp(prop, 999, byPlayer)
	end
	if t >= (vehicle.WallRamCd or 0) then
		local result = workspace:Raycast(root.Position, look * (vehicle.R + 2), losParams)
		if result then
			local b = G.World.BuildingFromPart(result.Instance)
			if b then
				vehicle.WallRamCd = t + 0.4
				G.World.DamageBuilding(b, spx * 0.4 * (if isTank then 2 else 1), byPlayer)
				G.World.Debris(result.Position, 5, { b.WallColor }, 1, 20)
			end
			for key, gate in pairs(G.World.Gates) do
				if result.Instance == gate.Part and speed > 20 then
					G.World.OpenGate(key, byPlayer)
				end
			end
		end
	end
end

function Combat.DashTick(ps)
	local pe = ps.Body
	if not pe or not G.Ents.Active(pe) then
		return
	end
	ps.DashHit = ps.DashHit or {}
	for _, o in ipairs(G.Ents.Near(pe.Root.Position, pe.R + 1.5)) do
		if o ~= pe and not o.IsGhost and not o.Def.Fly and not ps.DashHit[o] then
			ps.DashHit[o] = true
			Combat.Hurt(o, ps.DashDmg or 26, pe, ps.Player)
			if not o.Dead and o.Type ~= "tank" and not o.Possessor then
				local dir = flat(o.Root.Position - pe.Root.Position)
				if dir.Magnitude > 0.1 then
					o.Root.AssemblyLinearVelocity = dir.Unit * 32 + Vector3.new(0, 10, 0)
				end
				o.StunUntil = math.max(o.StunUntil, now() + 0.6)
			end
		end
	end
	for _, prop in ipairs(G.World.PropsNear(pe.Root.Position, pe.R + 1)) do
		G.World.DamageProp(prop, 50, ps.Player)
	end
end

function Combat.Init(g)
	G = g
	losParams = RaycastParams.new()
	losParams.FilterType = Enum.RaycastFilterType.Include
	losParams.FilterDescendantsInstances = { workspace:WaitForChild("City"):WaitForChild("Buildings"), workspace.City:WaitForChild("Compounds") }

	-- 차량 들이받기 루프
	task.spawn(function()
		while true do
			task.wait(0.1)
			for _, e in ipairs(G.Ents.List) do
				if e.Def.Vehicle and not e.Dead and (e.Possessor or e.Chasing) then
					local ok, err = pcall(ramTick, e, e.Possessor)
					if not ok then
						warn("[Ram]", err)
					end
				end
			end
		end
	end)
end

return Combat
