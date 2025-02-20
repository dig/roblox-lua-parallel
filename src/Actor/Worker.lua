local actor = script:GetActor()

local connections = {}
local preparedRunnable = nil
local bindableEvent = nil

local tasks = {}

local destroyed = false

local function add(connection: RBXScriptConnection)
  table.insert(connections, connection)
end

add(actor:BindToMessageParallel("Parallel:Init", function(bindable: BindableEvent, runnable: (...any?) -> any?)
  assert(not destroyed, "Parallel destroyed")
  bindableEvent = bindable
  preparedRunnable = runnable
end))

add(actor:BindToMessageParallel("Parallel:Run", function(...: any?)
  assert(preparedRunnable, "Parallel not initialized")
  assert(not destroyed, "Parallel destroyed")
  preparedRunnable(...)
end))

add(actor:BindToMessageParallel("Parallel:SubmitTask", function(uuid: string, ...: any?)
  assert(preparedRunnable, "Parallel not initialized")
  assert(not destroyed, "Parallel destroyed")
  local args = {...}

  if tasks[uuid] ~= nil then
    task.cancel(tasks[uuid])
    tasks[uuid] = nil
  end
  tasks[uuid] = task.spawn(function()
    bindableEvent:Fire(uuid, preparedRunnable(table.unpack(args)))
  end)
end))

add(actor:BindToMessageParallel("Parallel:CancelTask", function(uuid: string)
  assert(preparedRunnable, "Parallel not initialized")
  assert(not destroyed, "Parallel destroyed")
  if tasks[uuid] ~= nil then
    task.cancel(tasks[uuid])
    tasks[uuid] = nil
  end
end))

add(actor:BindToMessageParallel("Parallel:Destroy", function()
  assert(preparedRunnable, "Parallel not initialized")
  assert(not destroyed, "Parallel destroyed")
  destroyed = true

  for _, connection in connections do
    connection:Disconnect()
  end
  connections = {}

  for _, t in tasks do
    task.cancel(t)
  end
  tasks = {}

  preparedRunnable = nil
  bindableEvent = nil
end))

return nil