#!/bin/bash

# Enhanced DSPex Python Process Cleanup Script
# Intelligently kills only orphaned processes, preserves active workers

echo "🔍 Detecting orphaned Python processes..."

# Check if Elixir application is running
if pgrep -f "mix\|iex\|elixir" > /dev/null; then
    echo "📡 Elixir application detected, using intelligent cleanup..."
    
    # Use Elixir's OrphanDetector for safe cleanup
    mix run -e "
    case DSPex.Python.OrphanDetector.cleanup_orphaned_processes() do
      %{found: 0} -> 
        IO.puts(\"✅ No orphaned processes found\")
      %{found: found, terminated: terminated, errors: errors, preserved_active: active} ->
        IO.puts(\"🧹 Cleanup complete:\")
        IO.puts(\"  • Found: #{found} orphaned processes\")
        IO.puts(\"  • Terminated: #{terminated} processes\")
        IO.puts(\"  • Errors: #{errors}\")
        IO.puts(\"  • Preserved: #{active} active workers\")
    end
    " --no-halt 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "✅ Intelligent cleanup completed successfully"
        exit 0
    else
        echo "⚠️  Intelligent cleanup failed, falling back to manual mode..."
    fi
fi

echo "🔧 Manual cleanup mode (Elixir not running or unavailable)"

# Get all dspy_bridge PIDs
ALL_PIDS=$(pgrep -f "dspy_bridge.py" 2>/dev/null | tr '\n' ' ')

if [ -z "$ALL_PIDS" ]; then
    echo "✅ No dspy_bridge.py processes found"
    exit 0
fi

echo "🎯 Found dspy_bridge.py processes: $ALL_PIDS"

# In manual mode, we can't distinguish active from orphaned
echo "⚠️  WARNING: Cannot distinguish active workers from orphaned processes"
echo "   This will kill ALL dspy_bridge.py processes"

# Ask for confirmation in manual mode
read -p "Continue with killing ALL processes? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Aborted by user"
    exit 1
fi

echo "🔥 Terminating all dspy_bridge.py processes..."

# Convert space-separated string to array and kill each process
for pid in $ALL_PIDS; do
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        echo "  • Terminating PID $pid..."
        kill -TERM "$pid" 2>/dev/null
    fi
done

# Wait for graceful shutdown
sleep 2

# Force kill any remaining processes
REMAINING_PIDS=$(pgrep -f "dspy_bridge.py" 2>/dev/null | tr '\n' ' ')
if [ -n "$REMAINING_PIDS" ]; then
    echo "💀 Force-killing remaining processes: $REMAINING_PIDS"
    for pid in $REMAINING_PIDS; do
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill -KILL "$pid" 2>/dev/null
        fi
    done
fi

# Final verification
FINAL_CHECK=$(pgrep -f "dspy_bridge.py" 2>/dev/null)
if [ -z "$FINAL_CHECK" ]; then
    echo "✅ All dspy_bridge.py processes have been terminated"
else
    echo "⚠️  Some processes may still be running: $FINAL_CHECK"
fi