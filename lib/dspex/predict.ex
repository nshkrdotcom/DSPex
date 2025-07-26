defmodule DSPex.Predict do
  @moduledoc """
  Contract-based wrapper for prediction functionality.
  
  This module provides a typed, validated interface for predictions,
  using explicit contracts instead of string-based signatures.
  
  ## Examples
  
      # Create a predictor
      {:ok, predictor} = DSPex.Predict.create(%{signature: "question -> answer"})
      
      # Execute prediction
      {:ok, result} = DSPex.Predict.predict(predictor, %{question: "What is DSPy?"})
      # Returns: %DSPex.Types.Prediction{answer: "...", confidence: 0.95, ...}
      
      # One-shot prediction
      {:ok, result} = DSPex.Predict.call(%{signature: "question -> answer"}, 
                                          %{question: "What is DSPy?"})
  """
  
  use DSPex.Bridge.ContractBased
  use_contract DSPex.Contracts.Predict
  
  alias DSPex.Utils.ID
  
  # Backward compatibility aliases
  @doc false
  def new(signature, opts \\ []) do
    IO.warn("DSPex.Predict.new/2 is deprecated. Use create/2 instead.", Macro.Env.stacktrace(__ENV__))
    
    # Handle session option for backward compatibility
    opts = case Keyword.get(opts, :session) do
      %DSPex.Session{id: session_id} -> Keyword.put(opts, :session_id, session_id)
      nil -> opts
      _ -> opts
    end
    
    create(%{signature: signature}, opts)
  end
  
  @doc false
  def execute(predictor_ref, inputs, opts \\ []) do
    IO.warn("DSPex.Predict.execute/3 is deprecated. Use predict/3 instead.", Macro.Env.stacktrace(__ENV__))
    predict(predictor_ref, inputs, opts)
  end
  
  @doc false
  def call(%DSPex.Session{} = session, inputs) do
    # Support the session-first calling convention from tests
    predictor_ref = "predictor-#{session.id}"
    predict(predictor_ref, inputs, session_id: session.id)
  end
  
  @doc """
  Create and execute in one call (stateless).
  
  Combines create and predict operations for convenience.
  
  ## Examples
  
      {:ok, result} = DSPex.Predict.call(
        %{signature: "question -> answer"},
        %{question: "What is 2+2?"}
      )
  """
  def call(create_params, predict_params, opts \\ []) do
    session_id = opts[:session_id] || ID.generate("session")
    
    with {:ok, predictor_ref} <- create(create_params, Keyword.put(opts, :session_id, session_id)),
         {:ok, result} <- predict(predictor_ref, predict_params, opts) do
      {:ok, result}
    end
  end
end