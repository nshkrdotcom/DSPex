defmodule DSPex.Native.Registry do
  @moduledoc """
  Registry for native Elixir implementations.

  Tracks available native modules and their capabilities.
  """

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Initialize with known native modules
    registry = %{
      signature: DSPex.Native.Signature,
      template: DSPex.Native.Template,
      validator: DSPex.Native.Validator
    }

    {:ok, registry}
  end

  @doc """
  List all registered native modules.
  """
  def list do
    GenServer.call(__MODULE__, :list)
  end

  @doc """
  Register a native implementation.
  """
  def register(name, module) do
    GenServer.call(__MODULE__, {:register, name, module})
  end

  @doc """
  Get a native implementation by name.
  """
  def get(name) do
    GenServer.call(__MODULE__, {:get, name})
  end

  # Server callbacks

  @impl true
  def handle_call(:list, _from, registry) do
    {:reply, Map.keys(registry), registry}
  end

  @impl true
  def handle_call({:register, name, module}, _from, registry) do
    new_registry = Map.put(registry, name, module)
    {:reply, :ok, new_registry}
  end

  @impl true
  def handle_call({:get, name}, _from, registry) do
    {:reply, Map.get(registry, name), registry}
  end
end
