local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local Promise = require(script.Parent.Promise)

local ClientActor = script.ClientActor
local ServerActor = script.ServerActor

export type Promise = typeof(Promise)
export type PreparedParallel = {
  withName: (name: string) -> PreparedParallel,
  withActors: (actorCount: number) -> PreparedParallel,
  run: (...any?) -> (),
  submit: (...any?) -> Promise,
  destroy: () -> (),
}

type ActorState = {
  count: number,
  running: {Promise},
}

-- Set correct worker folder depending on
-- client or server context
local workersFolder = nil
if RunService:IsServer() then
  workersFolder = ServerStorage:FindFirstChild("ParallelWorkers") or Instance.new("Folder")
  workersFolder.Name = "ParallelWorkers"
  workersFolder.Parent = ServerStorage
elseif RunService:IsClient() then
  workersFolder = script
end

-- Parallel class
local Parallel = {}
Parallel.__index = Parallel

function Parallel.of(runnable: (...any?) -> any?): PreparedParallel
  local self = setmetatable({
    _runnable = runnable,
    _name = "ParallelWorker",
    _actorCount = 1,
    _bindableEvent = Instance.new("BindableEvent"),
    _folder = Instance.new("Folder"),

    _actors = {},
    _actorState = {} :: ActorState,
    _results = {},

    _connection = nil,
    _destroyed = false,
  }, Parallel)

  self._connection = self._bindableEvent.Event:Connect(function(uuid: string, ...: any)
    self._results[uuid] = {...}
  end)

  self._folder.Parent = workersFolder
  self:_createActors()
  return self
end

function Parallel:withName(name: string): PreparedParallel
  assert(not self._destroyed, "Parallel destroyed")
  self._name = name
  self._folder.Name = name
  return self
end

function Parallel:withActors(actorCount: number): PreparedParallel
  assert(not self._destroyed, "Parallel destroyed")
  self._actorCount = actorCount
  self:_createActors()
  return self
end

function Parallel:run(...: any?)
  assert(not self._destroyed, "Parallel destroyed")
  local args = {...}
  return Promise.promisify(self._findAvailableActor)(self)
    :andThen(function(actor: Actor)
      actor:SendMessage("Parallel:Run", table.unpack(args))
    end)
end

function Parallel:submit(...: any?): Promise
  assert(not self._destroyed, "Parallel destroyed")
  local args = {...}
  local actor = self:_findAvailableActor()
  local uuid = HttpService:GenerateGUID(false)

  local promise
  local function cleanup(status: string)
    if status == "Cancelled" or status == "Rejected" then
      actor:SendMessage("Parallel:CancelTask", uuid)
    end

    self._results[uuid] = nil
    self._actorState[actor].count -= 1
    self._actorState[actor].running[promise] = nil
  end

  promise = Promise.new(function(resolve)
    actor:SendMessage("Parallel:SubmitTask", uuid, table.unpack(args))
    resolve()
  end)
  :andThen(function()
    while self._results[uuid] == nil do
      task.wait()
    end
    return table.unpack(self._results[uuid])
  end)
  :finally(cleanup)

  self._actorState[actor].count += 1
  self._actorState[actor].running[promise] = true
  return promise
end

function Parallel:destroy()
  assert(not self._destroyed, "Parallel already destroyed")
  self._destroyed = true

  self._connection:Disconnect()
  self._connection = nil

  for _, actor in self._actors do
    for runningPromise, _ in self._actorState[actor].running do
      runningPromise:cancel()
    end

    actor:SendMessage("Parallel:Destroy")
  end

  self._actors = {}
  self._actorState = {}
  self._results = {}

  self._bindableEvent:Destroy()
  self._bindableEvent = nil

  self._folder:Destroy()
  self._folder = nil
end

function Parallel:_findAvailableActor(): Actor
  assert(#self._actors > 0, "No available actors")
  
  -- Find actor with least running promises
  local min = 999_999
  local minActor = nil
  for _, actor in self._actors do
    local count = self._actorState[actor].count
    if count < min then
      min = count
      minActor = actor
    end
  end

  return minActor
end

function Parallel:_createActors()
  for _ = 1, self._actorCount - #self._actors do
    local actor = Parallel._createTemplatedActor()
    actor.Parent = self._folder
    actor:SendMessage("Parallel:Init", self._bindableEvent, self._runnable)

    self._actorState[actor] = {
      count = 0,
      running = {},
    }
    table.insert(self._actors, actor)
  end
end

function Parallel._createTemplatedActor(): Actor
  local actor = nil
  if RunService:IsServer() then
    actor = ServerActor:Clone()
  else
    actor = ClientActor:Clone()
  end
  require(actor.Worker)
  return actor
end

function Parallel:__tostring()
  return string.format("Parallel(%s)", self._name)
end

return Parallel
