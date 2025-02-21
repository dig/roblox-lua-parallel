local actor = script:GetActor()

local preparedRunnable = require(script.Parent.Runnable)
local bindableEvent = script.Parent.Parent.Event
local destroyed = false

local tasks = {}

actor:BindToMessageParallel("Parallel:Run", function(...: any?)
  assert(preparedRunnable, "Parallel not initialized")
  assert(not destroyed, "Parallel destroyed")
  preparedRunnable(...)
end)

actor:BindToMessage("Parallel:SubmitTask", function(uuid: string, ...: any?)
  assert(preparedRunnable, "Parallel not initialized")
  assert(not destroyed, "Parallel destroyed")
  local args = {...}

  if tasks[uuid] ~= nil then
    task.cancel(tasks[uuid])
    tasks[uuid] = nil
  end
  tasks[uuid] = task.spawn(function()
    -- PARALLEL: Switch to parallel thread
    task.desynchronize()
    bindableEvent:Fire(uuid, preparedRunnable(table.unpack(args)))
    tasks[uuid] = nil
  end)
end)

actor:BindToMessage("Parallel:CancelTask", function(uuid: string)
  assert(preparedRunnable, "Parallel not initialized")
  assert(not destroyed, "Parallel destroyed")
  if tasks[uuid] ~= nil then
    task.cancel(tasks[uuid])
    tasks[uuid] = nil
  end
end)

actor:BindToMessage("Parallel:Destroy", function()
  assert(preparedRunnable, "Parallel not initialized")
  assert(not destroyed, "Parallel destroyed")
  destroyed = true

  for _, t in tasks do
    task.cancel(t)
  end
  tasks = {}

  preparedRunnable = nil
  bindableEvent = nil
end)

script.Parent:SetAttribute("Initialized", true)