# Minimal DSPy-Ash POC Implementation Plan

## Goal
Create the absolute minimum viable prototype that demonstrates DSPy working through Ash with Python integration. Focus on getting one simple DSPy program working end-to-end.

## Phase 1: Python Bridge (Day 1)
**Just get Python talking to Elixir**

### 1.1 Basic Python Script
```python
# priv/python/simple_dspy_bridge.py
import sys
import json
import struct
import dspy

def read_message():
    length_bytes = sys.stdin.buffer.read(4)
    if len(length_bytes) < 4:
        return None
    length = struct.unpack('>I', length_bytes)[0]
    message_bytes = sys.stdin.buffer.read(length)
    return json.loads(message_bytes.decode('utf-8'))

def write_message(message):
    message_bytes = json.dumps(message).encode('utf-8')
    length = len(message_bytes)
    sys.stdout.buffer.write(struct.pack('>I', length))
    sys.stdout.buffer.write(message_bytes)
    sys.stdout.buffer.flush()

# Configure DSPy with OpenAI
lm = dspy.OpenAI(model='gpt-3.5-turbo', temperature=0)
dspy.settings.configure(lm=lm)

# Simple QA module
qa = dspy.Predict("question -> answer")

while True:
    msg = read_message()
    if msg is None:
        break
    
    try:
        if msg['command'] == 'predict':
            result = qa(question=msg['question'])
            write_message({
                'id': msg['id'],
                'answer': result.answer
            })
    except Exception as e:
        write_message({
            'id': msg['id'],
            'error': str(e)
        })
```

### 1.2 Minimal Elixir Bridge
```elixir
# lib/dspy_ash/python_bridge.ex
defmodule DSPyAsh.PythonBridge do
  use GenServer
  
  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end
  
  def init(_) do
    port = Port.open({:spawn, "python3 priv/python/simple_dspy_bridge.py"}, 
      [:binary, :exit_status, packet: 4])
    {:ok, %{port: port, calls: %{}}}
  end
  
  def predict(question) do
    GenServer.call(__MODULE__, {:predict, question})
  end
  
  def handle_call({:predict, question}, from, state) do
    id = System.unique_integer([:positive])
    msg = Jason.encode!(%{id: id, command: "predict", question: question})
    Port.command(state.port, msg)
    {:noreply, put_in(state.calls[id], from)}
  end
  
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    %{"id" => id} = response = Jason.decode!(data)
    {from, new_calls} = Map.pop(state.calls, id)
    GenServer.reply(from, {:ok, response})
    {:noreply, %{state | calls: new_calls}}
  end
end
```

## Phase 2: Minimal Ash Resources (Day 1-2)
**Just enough Ash to store and execute**

### 2.1 Simple Domain
```elixir
# lib/dspy_ash/simple.ex
defmodule DSPyAsh.Simple do
  use Ash.Domain
  
  resources do
    resource DSPyAsh.Simple.Query
    resource DSPyAsh.Simple.Answer
  end
end
```

### 2.2 Basic Resources
```elixir
# lib/dspy_ash/simple/query.ex
defmodule DSPyAsh.Simple.Query do
  use Ash.Resource,
    domain: DSPyAsh.Simple,
    data_layer: Ash.DataLayer.Ets  # Use ETS for simplicity
  
  attributes do
    uuid_primary_key :id
    attribute :question, :string, allow_nil?: false
    attribute :answer, :string
    timestamps()
  end
  
  actions do
    defaults [:read, :destroy]
    
    create :ask do
      primary? true
      accept [:question]
      
      change fn changeset, _ ->
        question = Ash.Changeset.get_attribute(changeset, :question)
        
        case DSPyAsh.PythonBridge.predict(question) do
          {:ok, %{"answer" => answer}} ->
            Ash.Changeset.change_attribute(changeset, :answer, answer)
          {:error, _} ->
            Ash.Changeset.add_error(changeset, field: :question, message: "Failed to get answer")
        end
      end
    end
  end
  
  code_interface do
    define :ask
    define :read
  end
end
```

## Phase 3: Test the Integration (Day 2)
**Make sure it actually works**

### 3.1 Application Setup
```elixir
# lib/dspy_ash/application.ex
defmodule DSPyAsh.Application do
  use Application
  
  def start(_type, _args) do
    children = [
      DSPyAsh.PythonBridge,
      {Ash.Registry, [domains: [DSPyAsh.Simple]]}
    ]
    
    opts = [strategy: :one_for_one, name: DSPyAsh.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### 3.2 Config
```elixir
# config/config.exs
import Config

config :ash, :use_all_identities_in_manage_relationship?, false

# Set OpenAI API key
config :dspy_ash,
  openai_api_key: System.get_env("OPENAI_API_KEY")
```

### 3.3 Test Script
```elixir
# test_poc.exs
# Make sure OPENAI_API_KEY is set in environment

# Start the application
{:ok, _} = Application.ensure_all_started(:dspy_ash)

# Test the integration
{:ok, result} = DSPyAsh.Simple.Query.ask(%{
  question: "What is the capital of France?"
})

IO.puts("Question: #{result.question}")
IO.puts("Answer: #{result.answer}")

# Try a few more
{:ok, result2} = DSPyAsh.Simple.Query.ask(%{
  question: "What is 2+2?"
})

IO.puts("\nQuestion: #{result2.question}")
IO.puts("Answer: #{result2.answer}")

# List all queries
queries = DSPyAsh.Simple.Query.read!()
IO.puts("\nTotal queries: #{length(queries)}")
```

## Phase 4: Add One Advanced Feature (Day 3)
**Prove we can do more complex DSPy operations**

### 4.1 Add Chain of Thought
```python
# Update priv/python/simple_dspy_bridge.py to add:
cot = dspy.ChainOfThought("question -> answer")

# In the message loop:
elif msg['command'] == 'chain_of_thought':
    result = cot(question=msg['question'])
    write_message({
        'id': msg['id'],
        'answer': result.answer,
        'reasoning': result.rationale  # DSPy adds reasoning
    })
```

### 4.2 Update Elixir Bridge
```elixir
# Add to DSPyAsh.PythonBridge
def chain_of_thought(question) do
  GenServer.call(__MODULE__, {:chain_of_thought, question})
end

def handle_call({:chain_of_thought, question}, from, state) do
  id = System.unique_integer([:positive])
  msg = Jason.encode!(%{id: id, command: "chain_of_thought", question: question})
  Port.command(state.port, msg)
  {:noreply, put_in(state.calls[id], from)}
end
```

### 4.3 Add Reasoning Resource
```elixir
# lib/dspy_ash/simple/reasoning_query.ex
defmodule DSPyAsh.Simple.ReasoningQuery do
  use Ash.Resource,
    domain: DSPyAsh.Simple,
    data_layer: Ash.DataLayer.Ets
  
  attributes do
    uuid_primary_key :id
    attribute :question, :string, allow_nil?: false
    attribute :answer, :string
    attribute :reasoning, :string
    timestamps()
  end
  
  actions do
    defaults [:read]
    
    create :ask_with_reasoning do
      primary? true
      accept [:question]
      
      change fn changeset, _ ->
        question = Ash.Changeset.get_attribute(changeset, :question)
        
        case DSPyAsh.PythonBridge.chain_of_thought(question) do
          {:ok, %{"answer" => answer, "reasoning" => reasoning}} ->
            changeset
            |> Ash.Changeset.change_attribute(:answer, answer)
            |> Ash.Changeset.change_attribute(:reasoning, reasoning)
          {:error, _} ->
            Ash.Changeset.add_error(changeset, field: :question, message: "Failed")
        end
      end
    end
  end
end
```

## Setup Instructions

### 1. Create new Phoenix/Elixir project
```bash
mix new dspy_ash --sup
cd dspy_ash
```

### 2. Add dependencies
```elixir
# mix.exs
defp deps do
  [
    {:ash, "~> 3.0"},
    {:jason, "~> 1.4"}
  ]
end
```

### 3. Install Python dependencies
```bash
pip install dspy-ai openai
```

### 4. Set environment variable
```bash
export OPENAI_API_KEY="your-key-here"
```

### 5. Run the POC
```bash
mix deps.get
mix compile
mix run test_poc.exs
```

## Success Criteria

The POC is successful if:

1. ✅ Python bridge starts and maintains connection
2. ✅ Simple DSPy predict call works through Ash
3. ✅ Results are persisted in Ash resources  
4. ✅ Can retrieve historical queries
5. ✅ Chain of Thought works (proving we can use advanced DSPy features)

## What This Proves

- **Python Integration Works**: We can call DSPy from Elixir
- **Ash Integration Works**: We can wrap DSPy operations in Ash resources
- **Persistence Works**: Queries and answers are stored
- **Extensibility**: We can add more complex DSPy features

## Next Steps After POC

Only after POC works:

1. Add proper error handling
2. Add more DSPy modules (ReAct, ProgramOfThought)
3. Add optimization support
4. Build out full resource architecture
5. Add GraphQL/REST APIs
6. Add production features (monitoring, caching, etc.)

This minimal POC should take 2-3 days max and will prove the core concept works before investing in the full architecture.
