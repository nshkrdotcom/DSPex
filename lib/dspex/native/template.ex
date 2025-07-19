defmodule DSPex.Native.Template do
  @moduledoc """
  Native template rendering using EEx.

  Provides fast string templating for prompt generation without Python overhead.
  """

  require EEx

  @doc """
  Render a template with the given context.

  ## Examples

      iex> DSPex.Native.Template.render("Hello <%= @name %>!", %{name: "World"})
      "Hello World!"
      
      iex> template = \"\"\"
      ...> Question: <%= @question %>
      ...> Context: <%= Enum.join(@context, ", ") %>
      ...> Answer:
      ...> \"\"\"
      ...> DSPex.Native.Template.render(template, %{
      ...>   question: "What is DSPy?",
      ...>   context: ["ML framework", "Stanford"]
      ...> })
  """
  @spec render(String.t(), map()) :: String.t()
  def render(template, context) when is_binary(template) and is_map(context) do
    # Convert map keys to atoms if needed for EEx
    assigns = atomize_keys(context)

    try do
      EEx.eval_string(template, assigns: assigns)
    rescue
      e in CompileError ->
        raise ArgumentError, "Invalid template syntax: #{inspect(e)}"
    end
  end

  @doc """
  Compile a template for repeated use.

  Returns a compiled template function that can be called with context.
  """
  @spec compile(String.t()) :: {:ok, (map() -> any())} | {:error, term()}
  def compile(template) when is_binary(template) do
    try do
      # Generate a unique function name
      fun_name = :"template_#{:erlang.phash2(template)}"

      # Compile the template
      ast = EEx.compile_string(template)

      # Create a module with the compiled template
      module_name = Module.concat([__MODULE__, Compiled, fun_name])

      {:module, ^module_name, _, _} =
        Module.create(
          module_name,
          quote do
            def render(var!(assigns)) do
              unquote(ast)
            end
          end,
          Macro.Env.location(__ENV__)
        )

      # Return a function that calls the compiled template
      fun = fn context ->
        assigns = atomize_keys(context)
        apply(module_name, :render, [assigns])
      end

      {:ok, fun}
    rescue
      e ->
        {:error, e}
    end
  end

  @doc """
  Validate template syntax without rendering.
  """
  @spec validate(String.t()) :: :ok | {:error, String.t()}
  def validate(template) when is_binary(template) do
    try do
      _ast = EEx.compile_string(template)
      :ok
    rescue
      e in CompileError ->
        {:error, Exception.message(e)}
    end
  end

  @doc """
  Execute step for pipeline integration.
  """
  def execute(input, opts) do
    template = Keyword.fetch!(opts, :template)

    try do
      result = render(template, input)
      {:ok, result}
    rescue
      e ->
        {:error, {:template_error, e}}
    end
  end

  # Private functions

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_atom(k), v}
      {k, v} when is_atom(k) -> {k, v}
      {k, v} -> {k, v}
    end)
  end
end
