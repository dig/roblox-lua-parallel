# roblox-lua-parallel

A simple parallel execution library for Roblox lua. 

This library uses Roblox actors to run tasks in parallel.

Read more about Parallel Luau here: [Parallel Luau](https://create.roblox.com/docs/scripting/multithreading)

## Installation

### Method 1 - Wally
1. Install [Wally](https://wally.run/install)
2. Add the dependency to your project's `wally.toml` file
```toml
[dependencies]
Parallel = "dig/parallel@1.0.1"
```
3. Run `wally install`

### Method 2 - Manual
1. Download the `Parallel.rbxm` file from the latest release
2. Drag it into your `ReplicatedStorage` folder

## Basic Example
This example runs a function that returns "Hello, world!" in a new thread:
```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Packages")

-- Require parallel module
local Parallel = require(Packages.Parallel)

-- Prepare a thread with a runnable function
-- This function will be executed in a new thread
local preparedThread = Parallel.of(function()
  return "Hello, world!"
end)

-- Submit the thread and get the result via promise
local result = preparedThread:submit():expect()
print(result) -- Prints "Hello, world!"

preparedThread:destroy()
```

## Advanced Example
This example runs spatial query function `GetPartBoundsInBox` in a new thread and returns the results:
```lua
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Packages")

-- Require parallel module
local Parallel = require(Packages.Parallel)

-- Prepare a thread with a runnable function
-- This function will be executed in a new thread
local preparedThread = Parallel.of(function(position: CFrame, size: Vector3)
  return workspace:GetPartBoundsInBox(position, size)
end)
  :withName("SpatialQueryWorker")
  :withActors(2)

-- Example zone of 200 x 200 x 200
local zone = Instance.new("Part")
zone.Name = "Zone"
zone.Position = Vector3.new(0, 0, 0)
zone.Size = Vector3.new(200, 200, 200)
zone.Anchored = true
zone.CanCollide = true
zone.Transparency = 0.8
zone.Parent = workspace

while RunService:IsRunning() do
  -- Submit the thread and get the result via promise
  local parts = preparedThread:submit(zone.CFrame, zone.Size):expect()
  print(parts) -- Prints array of instances found inside the provided zone

  task.wait(1)
end

preparedThread:destroy()
```

