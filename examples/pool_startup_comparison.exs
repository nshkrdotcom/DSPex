#!/usr/bin/env elixir

# Visual comparison of sequential vs concurrent pool startup

IO.puts("\n📊 Pool Startup Time Comparison\n")

IO.puts("Sequential (Traditional Pools like NimblePool/poolboy):")
IO.puts("─" |> String.duplicate(50))
for i <- 1..8 do
  IO.write("Worker #{i}: ")
  start = (i-1) * 2
  finish = i * 2
  IO.puts("[#{start}s ████████ #{finish}s]")
end
IO.puts("Total time: 16 seconds\n")

IO.puts("Concurrent (DSPex V3 Pool):")  
IO.puts("─" |> String.duplicate(50))
for i <- 1..8 do
  IO.write("Worker #{i}: ")
  IO.puts("[0s ██ 2s]")
end
IO.puts("Total time: ~2 seconds")

IO.puts("\n🎯 Key Difference:")
IO.puts("   - Traditional: Workers start one after another")
IO.puts("   - V3 Pool: All workers start at the same time")
IO.puts("   - Result: 8x faster startup for 8 workers!")

IO.puts("\n💡 Why This Matters:")
IO.puts("   - Python processes take 1-2 seconds to initialize")
IO.puts("   - With 8+ workers, sequential startup is painful")
IO.puts("   - V3's concurrent startup makes pools practical")