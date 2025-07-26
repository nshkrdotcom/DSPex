defmodule DSPex.Bridge.WrapperOrchestrator do
  @moduledoc """
  Orchestrates the execution of wrapper functions with all configured behaviors.
  
  This module is responsible for:
  - Coordinating behavior callbacks in the correct order
  - Managing telemetry events
  - Handling transformations
  - Registering bidirectional tools
  
  The orchestrator ensures that behaviors are independent and can be
  composed in any order without relying on fragile `super` chains.
  """
  
  require Logger
  
  @doc """
  Handle instance creation with all configured behaviors.
  """
  def handle_create(module, python_class, args, behaviors) do
    start_time = System.monotonic_time()
    
    # Pre-execution phase
    with :ok <- run_before_execute(module, :create, args, behaviors),
         # Transform input if needed
         transformed_args <- transform_input(module, args, behaviors),
         # Emit start telemetry
         :ok <- emit_start_telemetry(module, :create, transformed_args, behaviors, start_time) do
      
      # Core execution
      result = DSPex.Bridge.create_instance(python_class, transformed_args)
      
      # Post-execution phase
      case result do
        {:ok, ref} = success ->
          # Register tools if bidirectional
          if :bidirectional in behaviors do
            register_elixir_tools(module, ref)
          end
          
          # Run after_execute callback
          run_after_execute(module, :create, args, success, behaviors)
          
          # Emit stop telemetry
          emit_stop_telemetry(module, :create, transformed_args, behaviors, start_time, true)
          
          success
          
        {:error, _reason} = error ->
          # Run after_execute callback even on error
          run_after_execute(module, :create, args, error, behaviors)
          
          # Emit exception telemetry
          emit_exception_telemetry(module, :create, transformed_args, behaviors, start_time, error)
          
          error
      end
    else
      {:error, _reason} = error ->
        emit_exception_telemetry(module, :create, args, behaviors, start_time, error)
        error
    end
  end
  
  @doc """
  Handle method calls with all configured behaviors.
  """
  def handle_call(module, ref, method, args, behaviors) do
    start_time = System.monotonic_time()
    
    # Pre-execution phase
    with :ok <- run_before_execute(module, :call, %{method: method, args: args}, behaviors),
         # Transform input if needed
         transformed_args <- transform_input(module, args, behaviors),
         # Emit start telemetry
         :ok <- emit_start_telemetry(module, :call, %{method: method, args: transformed_args}, behaviors, start_time) do
      
      # Core execution
      result = DSPex.Bridge.call_method(ref, method, transformed_args)
      
      # Post-execution phase
      case result do
        {:ok, raw_result} ->
          # Transform result if needed
          final_result = transform_result(module, raw_result, behaviors)
          success = {:ok, final_result}
          
          # Run after_execute callback
          run_after_execute(module, :call, %{method: method, args: args}, success, behaviors)
          
          # Emit stop telemetry
          emit_stop_telemetry(module, :call, %{method: method, args: transformed_args}, behaviors, start_time, true)
          
          success
          
        {:error, _reason} = error ->
          # Run after_execute callback even on error
          run_after_execute(module, :call, %{method: method, args: args}, error, behaviors)
          
          # Emit exception telemetry
          emit_exception_telemetry(module, :call, %{method: method, args: transformed_args}, behaviors, start_time, error)
          
          error
      end
    else
      {:error, _reason} = error ->
        emit_exception_telemetry(module, :call, %{method: method, args: args}, behaviors, start_time, error)
        error
    end
  end
  
  # Private helper functions
  
  defp run_before_execute(module, operation, args, behaviors) do
    if :observable in behaviors and function_exported?(module, :before_execute, 2) do
      module.before_execute(operation, args)
    else
      :ok
    end
  end
  
  defp run_after_execute(module, operation, args, result, behaviors) do
    if :observable in behaviors and function_exported?(module, :after_execute, 3) do
      module.after_execute(operation, args, result)
    end
    :ok
  end
  
  defp transform_input(module, args, behaviors) do
    if :result_transform in behaviors and function_exported?(module, :transform_input, 1) do
      module.transform_input(args)
    else
      args
    end
  end
  
  defp transform_result(module, result, behaviors) do
    if :result_transform in behaviors and function_exported?(module, :transform_result, 1) do
      module.transform_result(result)
    else
      result
    end
  end
  
  defp register_elixir_tools(module, ref) do
    if function_exported?(module, :elixir_tools, 0) do
      tools = module.elixir_tools()
      DSPex.Bridge.register_tools(ref, tools)
    end
    :ok
  end
  
  defp emit_start_telemetry(module, operation, args, behaviors, start_time) do
    if :observable in behaviors do
      metadata = get_telemetry_metadata(module, operation, args)
      measurements = %{system_time: System.system_time()}
      
      :telemetry.execute(
        [:dspex, :wrapper, operation, :start],
        measurements,
        Map.merge(metadata, %{module: module, start_time: start_time})
      )
    end
    :ok
  end
  
  defp emit_stop_telemetry(module, operation, args, behaviors, start_time, success) do
    if :observable in behaviors do
      metadata = get_telemetry_metadata(module, operation, args)
      duration = System.monotonic_time() - start_time
      measurements = %{
        duration: System.convert_time_unit(duration, :native, :microsecond)
      }
      
      :telemetry.execute(
        [:dspex, :wrapper, operation, :stop],
        measurements,
        Map.merge(metadata, %{module: module, success: success})
      )
    end
    :ok
  end
  
  defp emit_exception_telemetry(module, operation, args, behaviors, start_time, error) do
    if :observable in behaviors do
      metadata = get_telemetry_metadata(module, operation, args)
      duration = System.monotonic_time() - start_time
      measurements = %{
        duration: System.convert_time_unit(duration, :native, :microsecond)
      }
      
      :telemetry.execute(
        [:dspex, :wrapper, operation, :exception],
        measurements,
        Map.merge(metadata, %{module: module, error: error})
      )
    end
    :ok
  end
  
  defp get_telemetry_metadata(module, operation, args) do
    if function_exported?(module, :telemetry_metadata, 2) do
      module.telemetry_metadata(operation, args)
    else
      %{}
    end
  end
end