-- 빙의 대소동 서버 진입점
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 캐릭터는 직접 관리 (영혼/빙의한 몸을 player.Character 로 넣음)
Players.CharacterAutoLoads = false

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local action = Instance.new("RemoteEvent")
action.Name = "Action"
action.Parent = remotes
local event = Instance.new("RemoteEvent")
event.Name = "Event"
event.Parent = remotes
remotes.Parent = ReplicatedStorage

local G = {}
G.World = require(script.Parent:WaitForChild("World"))
G.Fx = require(script.Parent:WaitForChild("Fx"))
G.Factory = require(script.Parent:WaitForChild("BodyFactory"))
G.Ents = require(script.Parent:WaitForChild("Entities"))
G.Combat = require(script.Parent:WaitForChild("Combat"))
G.Players = require(script.Parent:WaitForChild("GameState"))

G.World.Init(G)
G.Fx.Init(G)
G.Ents.Init(G)
G.Combat.Init(G)
G.Players.Init(G, remotes)
G.Ents.Start()

print("[빙의 대소동] 서버 준비 완료")
