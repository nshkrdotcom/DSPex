# Stage 1 Prompt 4: Basic Ash Resources Setup

## OBJECTIVE

Implement foundational Ash resources that model DSPy signatures and programs as domain entities with proper lifecycle management, relationships, and actions. These resources must integrate seamlessly with the signature system and adapter pattern while providing a clean interface for ML operations through Ash's domain modeling capabilities.

## COMPLETE IMPLEMENTATION CONTEXT

### ASH DOMAIN MODELING ARCHITECTURE

From ashDocs/documentation/tutorials/get-started.md and ASH_DSPY_INTEGRATION_ARCHITECTURE.md:

**Core Domain Philosophy:**
- Ash resources serve as domain models for ML operations
- DSPy signatures become Ash resources with attributes and actions
- Programs are resources that reference signatures and manage execution
- Domain provides unified interface for all ML operations
- Resources leverage Ash's lifecycle management and validation

**Domain Architecture:**
```
┌─────────────────────────────────────────────────────────────┐
│                   AshDSPy.ML.Domain                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐│
│  │ Signature       │  │ Program         │  │ Execution    ││
│  │ Resource        │  │ Resource        │  │ Resource     ││
│  │ - Module ref    │  │ - Signature ref │  │ - Program ref││
│  │ - Input/Output  │  │ - Adapter type  │  │ - Input/Output│
│  │ - Validation    │  │ - Lifecycle     │  │ - Status     ││
│  └─────────────────┘  └─────────────────┘  └──────────────┘│
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### COMPLETE DOMAIN SETUP

From STAGE_1_FOUNDATION_IMPLEMENTATION.md:

```elixir
defmodule AshDSPy.ML.Domain do
  @moduledoc """
  ML domain for DSPy resources.
  """
  
  use Ash.Domain
  
  resources do
    resource AshDSPy.ML.Signature
    resource AshDSPy.ML.Program
    resource AshDSPy.ML.Execution
  end
end
```

### ASH RESOURCE PATTERNS FROM DOCUMENTATION

From ashDocs/documentation/tutorials/get-started.md:

**Basic Resource Structure:**
```elixir
defmodule Helpdesk.Support.Ticket do
  use Ash.Resource, domain: Helpdesk.Support

  actions do
    defaults [:read]
    create :open do
      accept [:subject]
    end
    update :close do
      accept []
      validate attribute_does_not_equal(:status, :closed) do
        message "Ticket is already closed"
      end
      change set_attribute(:status, :closed)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :subject, :string do
      allow_nil? false
      public? true
    end
    attribute :status, :atom do
      constraints [one_of: [:open, :closed]]
      default :open
      allow_nil? false
    end
  end
  
  relationships do
    belongs_to :representative, Helpdesk.Support.Representative
  end
end
```

**Key Patterns:**
- `use Ash.Resource` with domain specification
- Actions for resource lifecycle (`create`, `read`, `update`, `destroy`)
- Attributes with proper types, constraints, and defaults
- Relationships between resources (`belongs_to`, `has_many`)
- Validations and changes for business logic
- Public attributes for external access

### SIGNATURE RESOURCE IMPLEMENTATION

From STAGE_1_FOUNDATION_IMPLEMENTATION.md with extensions:

```elixir
defmodule AshDSPy.ML.Signature do
  @moduledoc """
  Ash resource for managing DSPy signatures.
  """
  
  use Ash.Resource,
    domain: AshDSPy.ML.Domain,
    data_layer: AshPostgres.DataLayer
  
  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :module, :string, allow_nil?: false, public?: true
    attribute :inputs, {:array, :map}, default: [], public?: true
    attribute :outputs, {:array, :map}, default: [], public?: true
    attribute :description, :string, public?: true
    attribute :version, :string, default: "1.0.0", public?: true
    attribute :status, :atom do
      constraints [one_of: [:draft, :active, :deprecated]]
      default :draft
      public? true
    end
    timestamps()
  end
  
  actions do
    defaults [:read, :create, :update, :destroy]
    
    create :from_module do
      accept [:name, :description, :version]
      argument :signature_module, :atom, allow_nil?: false
      
      change fn changeset, _context ->
        signature_module = Ash.Changeset.get_argument(changeset, :signature_module)
        
        try do
          signature = signature_module.__signature__()
          
          changeset
          |> Ash.Changeset.change_attribute(:module, to_string(signature_module))
          |> Ash.Changeset.change_attribute(:inputs, signature.inputs)
          |> Ash.Changeset.change_attribute(:outputs, signature.outputs)
          |> Ash.Changeset.change_attribute(:name, 
               Ash.Changeset.get_attribute(changeset, :name) || to_string(signature_module))
        rescue
          error ->
            Ash.Changeset.add_error(changeset, 
              field: :signature_module, 
              message: "Invalid signature module: #{inspect(error)}")
        end
      end
    end
    
    update :activate do
      accept []
      validate attribute_equals(:status, :draft) do
        message "Only draft signatures can be activated"
      end
      change set_attribute(:status, :active)
    end
    
    update :deprecate do
      accept []
      validate attribute_equals(:status, :active) do
        message "Only active signatures can be deprecated"
      end
      change set_attribute(:status, :deprecated)
    end
    
    action :validate_module, :boolean do
      argument :signature_module, :atom, allow_nil?: false
      
      run fn input, _context ->
        module = input.arguments.signature_module
        
        try do
          case Code.ensure_loaded(module) do
            {:module, _} ->
              if function_exported?(module, :__signature__, 0) do
                _signature = module.__signature__()
                {:ok, true}
              else
                {:ok, false}
              end
            {:error, _} ->
              {:ok, false}
          end
        rescue
          _ -> {:ok, false}
        end
      end
    end
  end
  
  relationships do
    has_many :programs, AshDSPy.ML.Program
  end
  
  validations do
    validate present([:name, :module, :inputs, :outputs])
    validate match(:module, ~r/^[A-Z][a-zA-Z0-9_.]*$/) do
      message "Module must be a valid Elixir module name"
    end
  end
  
  code_interface do
    define :from_module, args: [:signature_module]
    define :activate
    define :deprecate
    define :validate_module, args: [:signature_module]
  end
end
```

### PROGRAM RESOURCE IMPLEMENTATION

From STAGE_1_FOUNDATION_IMPLEMENTATION.md with comprehensive extensions:

```elixir
defmodule AshDSPy.ML.Program do
  @moduledoc """
  Ash resource for managing DSPy programs.
  """
  
  use Ash.Resource,
    domain: AshDSPy.ML.Domain,
    data_layer: AshPostgres.DataLayer
  
  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :dspy_program_id, :string, public?: true  # ID in adapter backend
    attribute :adapter_type, :atom do
      constraints [one_of: [:python_port, :native, :mock]]
      default :python_port
      public? true
    end
    attribute :status, :atom do
      constraints [one_of: [:draft, :initializing, :ready, :error, :archived]]
      default :draft
      public? true
    end
    attribute :configuration, :map, default: %{}, public?: true
    attribute :last_executed_at, :utc_datetime, public?: true
    attribute :execution_count, :integer, default: 0, public?: true
    attribute :error_message, :string, public?: true
    timestamps()
  end
  
  relationships do
    belongs_to :signature, AshDSPy.ML.Signature, public?: true
    has_many :executions, AshDSPy.ML.Execution
  end
  
  actions do
    defaults [:read, :update, :destroy]
    
    create :create_with_signature do
      accept [:name, :adapter_type, :configuration]
      argument :signature_module, :atom, allow_nil?: false
      
      change fn changeset, _context ->
        signature_module = Ash.Changeset.get_argument(changeset, :signature_module)
        
        # Validate signature module
        case AshDSPy.ML.Signature.validate_module(%{signature_module: signature_module}) do
          {:ok, true} ->
            # Find or create signature record
            case find_or_create_signature(signature_module) do
              {:ok, signature} ->
                changeset
                |> Ash.Changeset.manage_relationship(:signature, signature, type: :replace)
              {:error, error} ->
                Ash.Changeset.add_error(changeset, 
                  field: :signature_module, 
                  message: "Failed to create signature: #{inspect(error)}")
            end
          {:ok, false} ->
            Ash.Changeset.add_error(changeset, 
              field: :signature_module, 
              message: "Invalid signature module")
          {:error, error} ->
            Ash.Changeset.add_error(changeset, 
              field: :signature_module, 
              message: "Error validating signature: #{inspect(error)}")
        end
      end
    end
    
    update :initialize do
      accept []
      
      validate attribute_equals(:status, :draft) do
        message "Only draft programs can be initialized"
      end
      
      change set_attribute(:status, :initializing)
      
      change fn changeset, _context ->
        # This will be handled by after_action hook
        changeset
      end
      
      change after_action(fn changeset, program, _context ->
        case initialize_program_with_adapter(program) do
          {:ok, program_id} ->
            {:ok, program
             |> Ash.Changeset.for_update(:update, %{
                  dspy_program_id: program_id,
                  status: :ready
                })
             |> Ash.update!()}
          {:error, reason} ->
            {:ok, program
             |> Ash.Changeset.for_update(:update, %{
                  status: :error,
                  error_message: to_string(reason)
                })
             |> Ash.update!()}
        end
      end)
    end
    
    action :execute, :map do
      argument :inputs, :map, allow_nil?: false
      argument :execution_options, :map, default: %{}
      
      run fn input, context ->
        program = context.resource
        
        case program.status do
          :ready ->
            execute_program_with_tracking(program, input.arguments.inputs, input.arguments.execution_options)
          :error ->
            {:error, "Program is in error state: #{program.error_message}"}
          status ->
            {:error, "Program not ready for execution (status: #{status})"}
        end
      end
    end
    
    update :archive do
      accept []
      change set_attribute(:status, :archived)
    end
    
    action :get_stats, :map do
      run fn _input, context ->
        program = context.resource
        
        {:ok, %{
          id: program.id,
          name: program.name,
          status: program.status,
          execution_count: program.execution_count,
          last_executed_at: program.last_executed_at,
          adapter_type: program.adapter_type,
          dspy_program_id: program.dspy_program_id
        }}
      end
    end
  end
  
  validations do
    validate present([:name])
    validate present([:signature])
  end
  
  code_interface do
    define :create_with_signature, args: [:signature_module]
    define :initialize
    define :execute, args: [:inputs]
    define :archive
    define :get_stats
  end
  
  # Private helper functions
  defp find_or_create_signature(signature_module) do
    module_string = to_string(signature_module)
    
    case AshDSPy.ML.Signature
         |> Ash.Query.filter(module == ^module_string)
         |> Ash.read_one() do
      {:ok, nil} ->
        # Create new signature
        AshDSPy.ML.Signature.from_module(%{
          signature_module: signature_module,
          name: module_string
        })
      {:ok, signature} ->
        {:ok, signature}
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp initialize_program_with_adapter(program) do
    adapter = AshDSPy.Adapters.Registry.get_adapter(program.adapter_type)
    signature_module = String.to_existing_atom(program.signature.module)
    
    config = %{
      id: program.id,
      signature: signature_module,
      modules: Map.get(program.configuration, :modules, [])
    }
    
    case adapter.create_program(config) do
      {:ok, program_id} -> {:ok, program_id}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp execute_program_with_tracking(program, inputs, execution_options) do
    adapter = AshDSPy.Adapters.Registry.get_adapter(program.adapter_type)
    
    # Validate inputs against signature
    signature_module = String.to_existing_atom(program.signature.module)
    case signature_module.validate_inputs(inputs) do
      {:ok, validated_inputs} ->
        # Execute with adapter
        case AshDSPy.Adapters.Factory.execute_with_adapter(
               adapter, 
               :execute_program, 
               [program.dspy_program_id, validated_inputs],
               Map.to_list(execution_options)
             ) do
          {:ok, outputs} ->
            # Update execution tracking
            update_execution_tracking(program)
            
            # Create execution record
            create_execution_record(program, validated_inputs, outputs)
            
            {:ok, outputs}
          {:error, reason} ->
            {:error, reason}
        end
      {:error, validation_error} ->
        {:error, "Input validation failed: #{validation_error}"}
    end
  end
  
  defp update_execution_tracking(program) do
    program
    |> Ash.Changeset.for_update(:update, %{
         execution_count: program.execution_count + 1,
         last_executed_at: DateTime.utc_now()
       })
    |> Ash.update()
  end
  
  defp create_execution_record(program, inputs, outputs) do
    AshDSPy.ML.Execution.create(%{
      program_id: program.id,
      inputs: inputs,
      outputs: outputs,
      status: :completed,
      executed_at: DateTime.utc_now()
    })
  end
end
```

### EXECUTION RESOURCE FOR TRACKING

**Complete Execution Resource:**
```elixir
defmodule AshDSPy.ML.Execution do
  @moduledoc """
  Ash resource for tracking program executions.
  """
  
  use Ash.Resource,
    domain: AshDSPy.ML.Domain,
    data_layer: AshPostgres.DataLayer
  
  attributes do
    uuid_primary_key :id
    attribute :inputs, :map, allow_nil?: false, public?: true
    attribute :outputs, :map, public?: true
    attribute :status, :atom do
      constraints [one_of: [:pending, :running, :completed, :failed]]
      default :pending
      public? true
    end
    attribute :duration_ms, :integer, public?: true
    attribute :error_message, :string, public?: true
    attribute :executed_at, :utc_datetime, allow_nil?: false, public?: true
    attribute :metadata, :map, default: %{}, public?: true
    timestamps()
  end
  
  relationships do
    belongs_to :program, AshDSPy.ML.Program, public?: true
  end
  
  actions do
    defaults [:read, :create, :update]
    
    create :create_execution do
      accept [:inputs, :metadata]
      argument :program_id, :uuid, allow_nil?: false
      
      change fn changeset, _context ->
        program_id = Ash.Changeset.get_argument(changeset, :program_id)
        
        changeset
        |> Ash.Changeset.manage_relationship(:program, program_id, type: :replace)
        |> Ash.Changeset.change_attribute(:executed_at, DateTime.utc_now())
      end
    end
    
    update :mark_running do
      accept []
      change set_attribute(:status, :running)
    end
    
    update :mark_completed do
      accept [:outputs, :duration_ms]
      change set_attribute(:status, :completed)
    end
    
    update :mark_failed do
      accept [:error_message, :duration_ms]
      change set_attribute(:status, :failed)
    end
    
    read :by_program do
      argument :program_id, :uuid, allow_nil?: false
      filter expr(program_id == ^arg(:program_id))
    end
    
    read :recent_executions do
      argument :limit, :integer, default: 50
      
      prepare fn query, _context ->
        limit = Ash.Query.get_argument(query, :limit)
        
        query
        |> Ash.Query.sort(executed_at: :desc)
        |> Ash.Query.limit(limit)
      end
    end
  end
  
  validations do
    validate present([:inputs, :executed_at])
    validate present([:program])
  end
  
  code_interface do
    define :create_execution, args: [:program_id, :inputs]
    define :mark_running
    define :mark_completed, args: [:outputs, :duration_ms]
    define :mark_failed, args: [:error_message, :duration_ms]
    define :by_program, args: [:program_id]
    define :recent_executions, args: []
  end
end
```

### MANUAL ACTIONS FOR ML OPERATIONS

From ashDocs/documentation/topics/actions/manual-actions.md:

**Manual Action Patterns for ML Operations:**
```elixir
defmodule AshDSPy.ML.Actions.ProgramExecution do
  @moduledoc """
  Manual action for executing ML programs with full lifecycle management.
  """
  
  use Ash.Resource.ManualCreate
  
  def create(changeset, _opts, _context) do
    program_id = Ash.Changeset.get_argument(changeset, :program_id)
    inputs = Ash.Changeset.get_argument(changeset, :inputs)
    options = Ash.Changeset.get_argument(changeset, :execution_options) || %{}
    
    # Load program
    case AshDSPy.ML.Program.get!(program_id) do
      program when program.status == :ready ->
        execute_with_tracking(program, inputs, options)
      
      program ->
        {:error, "Program not ready for execution (status: #{program.status})"}
    end
  rescue
    error ->
      {:error, "Execution failed: #{inspect(error)}"}
  end
  
  defp execute_with_tracking(program, inputs, options) do
    start_time = System.monotonic_time(:millisecond)
    
    # Create execution record
    {:ok, execution} = AshDSPy.ML.Execution.create_execution(%{
      program_id: program.id,
      inputs: inputs,
      metadata: %{
        adapter_type: program.adapter_type,
        options: options
      }
    })
    
    # Mark as running
    {:ok, execution} = AshDSPy.ML.Execution.mark_running(execution)
    
    try do
      # Execute program
      case AshDSPy.ML.Program.execute(program, %{inputs: inputs, execution_options: options}) do
        {:ok, outputs} ->
          duration = System.monotonic_time(:millisecond) - start_time
          {:ok, execution} = AshDSPy.ML.Execution.mark_completed(execution, %{
            outputs: outputs,
            duration_ms: duration
          })
          
          {:ok, %{
            execution_id: execution.id,
            outputs: outputs,
            duration_ms: duration,
            status: :completed
          }}
        
        {:error, reason} ->
          duration = System.monotonic_time(:millisecond) - start_time
          {:ok, _execution} = AshDSPy.ML.Execution.mark_failed(execution, %{
            error_message: to_string(reason),
            duration_ms: duration
          })
          
          {:error, reason}
      end
    rescue
      error ->
        duration = System.monotonic_time(:millisecond) - start_time
        {:ok, _execution} = AshDSPy.ML.Execution.mark_failed(execution, %{
          error_message: "Execution exception: #{inspect(error)}",
          duration_ms: duration
        })
        
        {:error, error}
    end
  end
end
```

### DATA LAYER CONFIGURATION

**PostgreSQL Configuration:**
```elixir
# config/config.exs
config :ash_dspy, AshDSPy.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "ash_dspy_dev",
  pool_size: 10

config :ash_dspy, ecto_repos: [AshDSPy.Repo]
```

**Repo Module:**
```elixir
defmodule AshDSPy.Repo do
  use AshPostgres.Repo, otp_app: :ash_dspy
  
  def installed_extensions do
    ["uuid-ossp", "citext"]
  end
end
```

**Migration Files:**
```elixir
# priv/repo/migrations/20240101000001_create_signatures.exs
defmodule AshDSPy.Repo.Migrations.CreateSignatures do
  use Ecto.Migration

  def up do
    create table(:signatures, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string, null: false
      add :module, :string, null: false
      add :inputs, {:array, :map}, default: []
      add :outputs, {:array, :map}, default: []
      add :description, :text
      add :version, :string, default: "1.0.0"
      add :status, :string, default: "draft"
      
      timestamps()
    end
    
    create unique_index(:signatures, [:module])
    create index(:signatures, [:name])
    create index(:signatures, [:status])
  end

  def down do
    drop table(:signatures)
  end
end
```

### COMPREHENSIVE TESTING PATTERNS

**Resource Testing:**
```elixir
defmodule AshDSPy.ML.SignatureTest do
  use ExUnit.Case
  
  alias AshDSPy.ML.Signature
  
  defmodule TestSignature do
    use AshDSPy.Signature
    
    signature question: :string -> answer: :string, confidence: :float
  end
  
  setup do
    # Reset test database
    :ok
  end
  
  test "creates signature from module" do
    {:ok, signature} = Signature.from_module(%{
      signature_module: TestSignature,
      name: "Test QA Signature",
      description: "A test signature for Q&A"
    })
    
    assert signature.name == "Test QA Signature"
    assert signature.module == "AshDSPy.ML.SignatureTest.TestSignature"
    assert length(signature.inputs) == 1
    assert length(signature.outputs) == 2
    assert signature.status == :draft
  end
  
  test "validates signature module" do
    {:ok, true} = Signature.validate_module(%{signature_module: TestSignature})
    {:ok, false} = Signature.validate_module(%{signature_module: NonExistentModule})
  end
  
  test "activates draft signature" do
    {:ok, signature} = Signature.from_module(%{
      signature_module: TestSignature,
      name: "Test Signature"
    })
    
    {:ok, activated} = Signature.activate(signature)
    assert activated.status == :active
  end
  
  test "prevents activating non-draft signature" do
    {:ok, signature} = Signature.from_module(%{
      signature_module: TestSignature,
      name: "Test Signature"
    })
    
    {:ok, activated} = Signature.activate(signature)
    
    # Try to activate again
    assert_raise Ash.Error.Invalid, fn ->
      Signature.activate(activated)
    end
  end
end

defmodule AshDSPy.ML.ProgramTest do
  use ExUnit.Case
  
  alias AshDSPy.ML.{Program, Signature}
  
  defmodule TestSignature do
    use AshDSPy.Signature
    
    signature question: :string -> answer: :string
  end
  
  setup do
    # Ensure mock adapter is available
    {:ok, _} = AshDSPy.Adapters.Mock.start_link()
    AshDSPy.Adapters.Mock.reset()
    
    # Set adapter to mock for testing
    Application.put_env(:ash_dspy, :adapter, :mock)
    
    :ok
  end
  
  test "creates program with signature" do
    {:ok, program} = Program.create_with_signature(%{
      signature_module: TestSignature,
      name: "Test Program",
      adapter_type: :mock
    })
    
    assert program.name == "Test Program"
    assert program.adapter_type == :mock
    assert program.status == :draft
    assert program.signature.module == "AshDSPy.ML.ProgramTest.TestSignature"
  end
  
  test "initializes program with adapter" do
    {:ok, program} = Program.create_with_signature(%{
      signature_module: TestSignature,
      name: "Test Program",
      adapter_type: :mock
    })
    
    {:ok, initialized} = Program.initialize(program)
    assert initialized.status == :ready
    assert initialized.dspy_program_id != nil
  end
  
  test "executes program with valid inputs" do
    {:ok, program} = Program.create_with_signature(%{
      signature_module: TestSignature,
      name: "Test Program",
      adapter_type: :mock
    })
    
    {:ok, program} = Program.initialize(program)
    
    {:ok, result} = Program.execute(program, %{
      inputs: %{question: "What is 2+2?"}
    })
    
    assert Map.has_key?(result, :answer) or Map.has_key?(result, "answer")
  end
  
  test "rejects execution with invalid inputs" do
    {:ok, program} = Program.create_with_signature(%{
      signature_module: TestSignature,
      name: "Test Program",
      adapter_type: :mock
    })
    
    {:ok, program} = Program.initialize(program)
    
    {:error, reason} = Program.execute(program, %{
      inputs: %{wrong_field: "test"}
    })
    
    assert reason =~ "validation failed"
  end
  
  test "tracks execution statistics" do
    {:ok, program} = Program.create_with_signature(%{
      signature_module: TestSignature,
      name: "Test Program",
      adapter_type: :mock
    })
    
    {:ok, program} = Program.initialize(program)
    
    # Execute multiple times
    for _ <- 1..3 do
      Program.execute(program, %{inputs: %{question: "test"}})
    end
    
    {:ok, stats} = Program.get_stats(program)
    assert stats.execution_count >= 3
    assert stats.last_executed_at != nil
  end
end
```

### INTEGRATION WITH CODE INTERFACES

From ashDocs/documentation/topics/resources/code-interfaces.md:

**Enhanced Code Interfaces:**
```elixir
defmodule AshDSPy.ML do
  @moduledoc """
  High-level interface for ML operations.
  """
  
  # Signature operations
  defdelegate create_signature_from_module(signature_module, opts \\ %{}), 
    to: AshDSPy.ML.Signature, as: :from_module
  
  defdelegate activate_signature(signature), 
    to: AshDSPy.ML.Signature, as: :activate
  
  # Program operations
  defdelegate create_program(signature_module, opts \\ %{}), 
    to: AshDSPy.ML.Program, as: :create_with_signature
  
  defdelegate initialize_program(program), 
    to: AshDSPy.ML.Program, as: :initialize
  
  defdelegate execute_program(program, inputs, opts \\ %{}), 
    to: AshDSPy.ML.Program, as: :execute
  
  # Convenience functions
  def quick_execute(signature_module, inputs, opts \\ %{}) do
    adapter_type = Keyword.get(opts, :adapter_type, :mock)
    
    with {:ok, program} <- create_program(signature_module, %{
           name: "Quick Execute - #{signature_module}",
           adapter_type: adapter_type
         }),
         {:ok, program} <- initialize_program(program),
         {:ok, result} <- execute_program(program, inputs) do
      {:ok, result}
    end
  end
  
  def list_active_signatures do
    AshDSPy.ML.Signature
    |> Ash.Query.filter(status == :active)
    |> Ash.read!()
  end
  
  def get_program_statistics(program_id) do
    case AshDSPy.ML.Execution.by_program(%{program_id: program_id}) do
      {:ok, executions} ->
        total_executions = length(executions)
        successful = Enum.count(executions, &(&1.status == :completed))
        failed = Enum.count(executions, &(&1.status == :failed))
        
        avg_duration = executions
                      |> Enum.filter(&(&1.duration_ms != nil))
                      |> Enum.map(&(&1.duration_ms))
                      |> case do
                           [] -> 0
                           durations -> Enum.sum(durations) / length(durations)
                         end
        
        {:ok, %{
          total_executions: total_executions,
          successful_executions: successful,
          failed_executions: failed,
          success_rate: if(total_executions > 0, do: successful / total_executions, else: 0),
          average_duration_ms: avg_duration
        }}
      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

## IMPLEMENTATION TASK

Based on the complete context above, implement the foundational Ash resources system with the following specific requirements:

### FILE STRUCTURE TO CREATE:
```
lib/ash_dspy/ml/
├── domain.ex                # Main domain definition
├── signature.ex             # Signature resource
├── program.ex               # Program resource  
├── execution.ex             # Execution tracking resource
├── actions/
│   ├── program_execution.ex # Manual execution action
│   └── signature_validation.ex # Signature validation action
└── interfaces.ex            # High-level code interfaces

priv/repo/migrations/
├── 001_create_signatures.exs    # Signature table
├── 002_create_programs.exs      # Program table
└── 003_create_executions.exs    # Execution table

test/ash_dspy/ml/
├── domain_test.exs          # Domain functionality tests
├── signature_test.exs       # Signature resource tests
├── program_test.exs         # Program resource tests
├── execution_test.exs       # Execution resource tests
└── integration_test.exs     # Cross-resource integration tests
```

### SPECIFIC IMPLEMENTATION REQUIREMENTS:

1. **Domain Setup (`lib/ash_dspy/ml/domain.ex`)**:
   - Complete domain definition with all resources
   - Proper resource registration and configuration
   - Domain-level policies and authorization setup
   - Integration with application configuration

2. **Signature Resource (`lib/ash_dspy/ml/signature.ex`)**:
   - Complete resource definition with all attributes
   - Actions for lifecycle management (create, activate, deprecate)
   - Signature module validation and integration
   - Proper relationships and constraints

3. **Program Resource (`lib/ash_dspy/ml/program.ex`)**:
   - Comprehensive program lifecycle management
   - Integration with adapter pattern for execution
   - Execution tracking and statistics
   - Error handling and status management

4. **Execution Resource (`lib/ash_dspy/ml/execution.ex`)**:
   - Complete execution tracking with timing
   - Status management and error recording
   - Relationships with programs and metadata
   - Query actions for analytics and reporting

5. **Manual Actions (`lib/ash_dspy/ml/actions/`)**:
   - Complex execution logic with full lifecycle
   - Error handling and recovery patterns
   - Performance tracking and monitoring
   - Integration with adapter pattern

### QUALITY REQUIREMENTS:

- **Data Integrity**: Proper constraints, validations, and relationships
- **Performance**: Efficient queries and minimal database overhead
- **Reliability**: Robust error handling and transaction management
- **Usability**: Clean code interfaces and intuitive APIs
- **Testability**: Comprehensive test coverage for all scenarios
- **Documentation**: Clear documentation for all public APIs
- **Migration Safety**: Safe database migrations with rollback support

### INTEGRATION POINTS:

- Must integrate with signature system for validation
- Should use adapter pattern for execution backend
- Must support configuration-driven data layer selection
- Should provide metrics and monitoring capabilities
- Must handle concurrent operations safely

### SUCCESS CRITERIA:

1. All resources create and manage data correctly
2. Signature integration works seamlessly
3. Program lifecycle management functions properly
4. Execution tracking captures all necessary data
5. Manual actions handle complex workflows
6. Code interfaces provide clean high-level APIs
7. Database migrations run safely
8. All test scenarios pass with comprehensive coverage
9. Performance meets requirements for ML workloads
10. Integration with other system components works correctly

These Ash resources provide the domain modeling foundation that transforms DSPy operations into properly managed, persistent, and queryable entities within the Ash framework ecosystem.