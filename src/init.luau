local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ServerStorage = game:GetService("ServerStorage")

local Promise = require(script.Parent.Promise)

local Actor = script.Actor

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
  running: { [Promise]: boolean },
}

type ActorStateMap = {
  [Actor]: ActorState,
}

local workersFolder: Instance? = nil
local function getOrFindWorkerFolder(): Instance
  if workersFolder == nil then
    if RunService:IsServer() then
      workersFolder = ServerStorage:FindFirstChild("ParallelWorkers") or Instance.new("Folder")
      workersFolder.Name = "ParallelWorkers"
      workersFolder.Parent = ServerStorage
    elseif RunService:IsClient() then
      workersFolder = script
    end
  end

  return workersFolder
end

local function createTemplatedActor(): Actor
  local actor = Actor:Clone()
  require(actor.Worker)
  return actor
end

-- Parallel class
local Parallel = {}
Parallel.__index = Parallel

function Parallel.of(runnable: (...any?) -> any?): PreparedParallel
  assert(type(runnable) == "function", "Runnable must be a function")
  local self = setmetatable({
    _runnable = runnable,
    _name = "ParallelWorker",
    _actorCount = 1,
    _bindableEvent = Instance.new("BindableEvent"),
    _folder = Instance.new("Folder"),

    _actors = {} :: { Actor },
    _actorState = {} :: ActorStateMap,
    _results = {} :: { [string]: table },

    _connection = nil,
    _destroyed = false,
  }, Parallel)

  self._connection = self._bindableEvent.Event:Connect(function(uuid: string, ...: any)
    self._results[uuid] = {...}
  end)
  self._folder.Parent = getOrFindWorkerFolder()
  self:_createActors()
  return self
end

function Parallel:withName(name: string): PreparedParallel
  assert(not self._destroyed, "Parallel destroyed")
  assert(type(name) == "string", "Name must be a string")
  assert(#name > 0, "Name must be non-empty")
  self._name = name
  self._folder.Name = name
  return self
end

function Parallel:withActors(actorCount: number): PreparedParallel
  assert(not self._destroyed, "Parallel destroyed")
  assert(type(actorCount) == "number", "Actor count must be a number")
  assert(actorCount > 0, "Actor count must be greater than 0")
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

  local promise = nil
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
  local minActor = self._actors[1]
  local min = self._actorState[minActor].count

  for i = 2, #self._actors do
    local actor = self._actors[i]
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
    local actor = createTemplatedActor()
    actor.Parent = self._folder
    actor:SendMessage("Parallel:Init", self._bindableEvent, self._runnable)

    self._actorState[actor] = {
      count = 0,
      running = {},
    }
    table.insert(self._actors, actor)
  end
end

function Parallel:__tostring()
  return string.format("Parallel<%s>", self._name)
end

return Parallel
