# Direct LM Call Example - Using Generated Native Bindings
#
# Run with: mix run --no-start examples/direct_lm_call.exs

require SnakeBridge

SnakeBridge.script do
  IO.puts("DSPex Direct LM Call Example")
  IO.puts("==============================\n")

  {:ok, lm} = Dspy.LM.new("gemini/gemini-flash-lite-latest", [], temperature: 0.9)

  # Call LM directly (not through a module)
  messages = [
    %{"role" => "user", "content" => "Tell me a one-line joke about programming."}
  ]

  IO.puts("Calling LM directly with messages...\n")

  {:ok, response} = Dspy.LM.forward(lm, [], messages: messages)

  extract_text = fn payload ->
    cond do
      is_map(payload) ->
        case Map.get(payload, "choices") do
          [first | _] when is_map(first) ->
            message = Map.get(first, "message") || %{}

            Map.get(message, "content") || Map.get(first, "text") ||
              inspect(first, limit: 4, printable_limit: 200)

          [first | _] when is_binary(first) ->
            first

          _ ->
            inspect(payload, limit: 4, printable_limit: 200)
        end

      is_list(payload) ->
        case payload do
          [first | _] when is_binary(first) -> first
          [first | _] -> inspect(first, limit: 4, printable_limit: 200)
          _ -> inspect(payload, limit: 4, printable_limit: 200)
        end

      SnakeBridge.ref?(payload) ->
        case SnakeBridge.call("builtins", "repr", [payload]) do
          {:ok, repr} -> to_string(repr)
          {:error, _} -> "<response ref>"
        end

      true ->
        inspect(payload, limit: 4, printable_limit: 200)
    end
  end

  IO.puts("Response: #{extract_text.(response)}\n")

  # Another direct call
  messages2 = [
    %{"role" => "user", "content" => "What's 2+2? Reply with just the number."}
  ]

  {:ok, response2} = Dspy.LM.forward(lm, [], messages: messages2)
  IO.puts("2+2 = #{extract_text.(response2)}")

  IO.puts("\nDone!")
end
