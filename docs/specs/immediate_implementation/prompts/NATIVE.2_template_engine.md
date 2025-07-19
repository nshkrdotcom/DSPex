# Task NATIVE.2: Template Engine Integration

## Task Overview
**ID**: NATIVE.2  
**Component**: Native Implementation  
**Priority**: P0 (Critical)  
**Estimated Time**: 6 hours  
**Dependencies**: CORE.1 (Project setup must be complete)  
**Status**: Not Started

## Objective
Integrate EEx (Embedded Elixir) as the template engine for DSPex, ensuring templates compile correctly, variable binding works properly, nested data access is supported, error handling for missing variables is implemented, template caching is in place, and performance benchmarks pass.

## Required Reading

### 1. Current Implementation
- **File**: `/home/home/p/g/n/dspex/lib/dspex/native/template.ex`
  - Review any existing template implementation
  - Understand current approach

### 2. Architecture Context
- **File**: `/home/home/p/g/n/dspex/CLAUDE.md`
  - Lines 71-76: Native implementation strategy
  - Templates are native using EEx

### 3. EEx Documentation
- Elixir EEx module documentation
- Understanding of compile-time vs runtime compilation
- Safe evaluation practices

## Implementation Requirements

### Template Features
1. **Variable Interpolation**: `<%= @variable %>`
2. **Nested Access**: `<%= @user.name %>`, `<%= @data["key"] %>`
3. **Conditionals**: `<%= if @condition do %>...`
4. **Loops**: `<%= for item <- @items do %>...`
5. **Safe HTML**: Auto-escape by default
6. **Raw Output**: `<%=raw @html %>` when needed
7. **Comments**: `<%# This is a comment %>`

### Error Handling
- Missing variables should provide helpful error messages
- Type mismatches should be caught early
- Template syntax errors should be clear

## Implementation Steps

### Step 1: Create Template Module
Create or update `/home/home/p/g/n/dspex/lib/dspex/native/template.ex`:

```elixir
defmodule DSPex.Native.Template do
  @moduledoc """
  Native EEx-based template engine for DSPex.
  
  Provides high-performance template rendering with caching,
  variable binding, and comprehensive error handling.
  """
  
  require EEx
  
  @type template :: String.t()
  @type bindings :: keyword() | map()
  @type options :: [
    cache: boolean(),
    escape: boolean(),
    engine: module()
  ]
  
  # Template cache using ETS
  @cache_table :dspex_template_cache
  
  @doc """
  Initialize the template engine.
  Creates the ETS table for template caching.
  """
  @spec init() :: :ok
  def init do
    if :ets.whereis(@cache_table) == :undefined do
      :ets.new(@cache_table, [
        :set,
        :public,
        :named_table,
        read_concurrency: true
      ])
    end
    :ok
  end
  
  @doc """
  Render a template with the given bindings.
  
  ## Options
  - `:cache` - Whether to cache compiled templates (default: true)
  - `:escape` - Whether to HTML-escape output (default: true)
  - `:engine` - EEx engine to use (default: EEx.SmartEngine)
  
  ## Examples
  
      iex> render("Hello <%= @name %>!", name: "World")
      {:ok, "Hello World!"}
      
      iex> render("Users: <%= for u <- @users do %><%= u.name %><% end %>",
      ...>   users: [%{name: "Alice"}, %{name: "Bob"}])
      {:ok, "Users: AliceBob"}
  """
  @spec render(template(), bindings(), options()) :: 
    {:ok, String.t()} | {:error, term()}
  def render(template, bindings \\ [], opts \\ []) do
    cache? = Keyword.get(opts, :cache, true)
    
    try do
      result = if cache? do
        render_cached(template, bindings, opts)
      else
        render_direct(template, bindings, opts)
      end
      
      {:ok, result}
    rescue
      e in [KeyError, ArgumentError, CompileError] ->
        {:error, format_error(e, template, bindings)}
      e ->
        {:error, Exception.format(:error, e)}
    end
  end
  
  @doc """
  Compile a template without rendering.
  Useful for pre-compilation and validation.
  """
  @spec compile(template(), options()) :: 
    {:ok, term()} | {:error, term()}
  def compile(template, opts \\ []) do
    engine = Keyword.get(opts, :engine, EEx.SmartEngine)
    
    try do
      compiled = EEx.compile_string(template, engine: engine)
      {:ok, compiled}
    rescue
      e in CompileError ->
        {:error, format_compile_error(e, template)}
    end
  end
  
  # Private functions
  
  defp render_cached(template, bindings, opts) do
    cache_key = :erlang.phash2({template, opts})
    
    case :ets.lookup(@cache_table, cache_key) do
      [{^cache_key, compiled}] ->
        eval_compiled(compiled, bindings)
      
      [] ->
        engine = Keyword.get(opts, :engine, EEx.SmartEngine)
        compiled = EEx.compile_string(template, engine: engine)
        :ets.insert(@cache_table, {cache_key, compiled})
        eval_compiled(compiled, bindings)
    end
  end
  
  defp render_direct(template, bindings, opts) do
    engine = Keyword.get(opts, :engine, EEx.SmartEngine)
    compiled = EEx.compile_string(template, engine: engine)
    eval_compiled(compiled, bindings)
  end
  
  defp eval_compiled(compiled, bindings) do
    bindings = normalize_bindings(bindings)
    {result, _} = Code.eval_quoted(compiled, bindings)
    to_string(result)
  end
  
  defp normalize_bindings(bindings) when is_list(bindings), do: bindings
  defp normalize_bindings(bindings) when is_map(bindings) do
    Enum.map(bindings, fn {k, v} -> {to_atom(k), v} end)
  end
  
  defp to_atom(key) when is_atom(key), do: key
  defp to_atom(key) when is_binary(key), do: String.to_atom(key)
  
  defp format_error(%KeyError{key: key}, template, bindings) do
    available = bindings |> Keyword.keys() |> Enum.map(&inspect/1) |> Enum.join(", ")
    """
    Missing template variable: #{inspect(key)}
    
    Available variables: #{available}
    
    Template: #{String.slice(template, 0, 100)}...
    """
  end
  
  defp format_error(error, _template, _bindings) do
    Exception.format(:error, error)
  end
  
  defp format_compile_error(%CompileError{} = error, template) do
    """
    Template compilation error: #{error.description}
    
    Line #{error.line}: #{get_line(template, error.line)}
    
    Template:
    #{add_line_numbers(template)}
    """
  end
  
  defp get_line(template, line_num) do
    template
    |> String.split("\n")
    |> Enum.at(line_num - 1, "")
  end
  
  defp add_line_numbers(template) do
    template
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map(fn {line, num} -> "#{num}: #{line}" end)
    |> Enum.join("\n")
  end
end
```

### Step 2: Create Template Cache Manager
Add cache management functions to the template module:

```elixir
# Add to template.ex

@doc """
Clear the template cache.
"""
@spec clear_cache() :: :ok
def clear_cache do
  :ets.delete_all_objects(@cache_table)
  :ok
end

@doc """
Get cache statistics.
"""
@spec cache_stats() :: map()
def cache_stats do
  %{
    size: :ets.info(@cache_table, :size),
    memory: :ets.info(@cache_table, :memory),
    entries: :ets.tab2list(@cache_table) |> length()
  }
end

@doc """
Precompile templates for better performance.
"""
@spec precompile(list({name :: atom(), template()})) :: :ok
def precompile(templates) do
  Enum.each(templates, fn {name, template} ->
    case compile(template) do
      {:ok, compiled} ->
        cache_key = :erlang.phash2({template, []})
        :ets.insert(@cache_table, {cache_key, compiled})
      {:error, error} ->
        raise "Failed to precompile template #{name}: #{inspect(error)}"
    end
  end)
  :ok
end
```

### Step 3: Add Template Helpers
Create `/home/home/p/g/n/dspex/lib/dspex/native/template/helpers.ex`:

```elixir
defmodule DSPex.Native.Template.Helpers do
  @moduledoc """
  Helper functions available in DSPex templates.
  """
  
  @doc """
  Safely access nested data with a default value.
  
  ## Examples
  
      <%= get_in(@data, [:user, :name], "Anonymous") %>
  """
  def safe_get(data, path, default \\ nil)
  def safe_get(nil, _path, default), do: default
  def safe_get(data, path, default) when is_list(path) do
    get_in(data, path) || default
  end
  def safe_get(data, key, default) do
    Map.get(data, key, default)
  end
  
  @doc """
  Format a value as JSON.
  """
  def to_json(value) do
    case Jason.encode(value) do
      {:ok, json} -> json
      {:error, _} -> inspect(value)
    end
  end
  
  @doc """
  Join a list with a separator.
  """
  def join(list, separator \\ ", ") when is_list(list) do
    Enum.join(list, separator)
  end
  
  @doc """
  Truncate text to a maximum length.
  """
  def truncate(text, max_length, suffix \\ "...") do
    text = to_string(text)
    if String.length(text) <= max_length do
      text
    else
      String.slice(text, 0, max_length - String.length(suffix)) <> suffix
    end
  end
  
  @doc """
  Conditional rendering helper.
  """
  def if_present(value, fun) when is_function(fun, 1) do
    if value not in [nil, "", [], %{}] do
      fun.(value)
    else
      ""
    end
  end
end
```

### Step 4: Create Smart Engine Extension
Create `/home/home/p/g/n/dspex/lib/dspex/native/template/engine.ex`:

```elixir
defmodule DSPex.Native.Template.Engine do
  @moduledoc """
  Custom EEx engine with enhanced error handling and features.
  """
  
  use EEx.Engine
  
  @doc """
  Handle missing variable access with better error messages.
  """
  def handle_expr(buffer, "=", expr) do
    expr = wrap_expr(expr)
    EEx.Engine.handle_expr(buffer, "=", expr)
  end
  
  defp wrap_expr(expr) do
    quote do
      case unquote(expr) do
        {:__missing_var__, var} ->
          raise KeyError, key: var, term: var
        value ->
          value
      end
    end
  end
  
  @impl true
  def handle_text(buffer, text) do
    EEx.Engine.handle_text(buffer, text)
  end
  
  @impl true
  def handle_begin(state) do
    EEx.Engine.handle_begin(state)
  end
  
  @impl true
  def handle_end(quoted) do
    EEx.Engine.handle_end(quoted)
  end
end
```

### Step 5: Create Comprehensive Tests
Create `/home/home/p/g/n/dspex/test/dspex/native/template_test.exs`:

```elixir
defmodule DSPex.Native.TemplateTest do
  use ExUnit.Case, async: true
  
  alias DSPex.Native.Template
  
  setup do
    Template.init()
    on_exit(fn -> Template.clear_cache() end)
    :ok
  end
  
  describe "render/3" do
    test "renders simple variable interpolation" do
      assert {:ok, "Hello World!"} = 
        Template.render("Hello <%= @name %>!", name: "World")
    end
    
    test "renders with map bindings" do
      assert {:ok, "Hello Alice!"} = 
        Template.render("Hello <%= @name %>!", %{name: "Alice"})
    end
    
    test "handles nested data access" do
      template = "User: <%= @user.name %> (<%= @user.email %>)"
      bindings = [user: %{name: "Bob", email: "bob@example.com"}]
      
      assert {:ok, "User: Bob (bob@example.com)"} = 
        Template.render(template, bindings)
    end
    
    test "handles conditionals" do
      template = """
      <%= if @show do %>
        Visible content
      <% else %>
        Hidden content
      <% end %>
      """
      
      assert {:ok, result1} = Template.render(template, show: true)
      assert result1 =~ "Visible content"
      assert result1 =~ ~r/Visible content/
      refute result1 =~ "Hidden content"
      
      assert {:ok, result2} = Template.render(template, show: false)
      assert result2 =~ "Hidden content"
      refute result2 =~ "Visible content"
    end
    
    test "handles loops" do
      template = """
      Users:
      <%= for user <- @users do %>
      - <%= user.name %>
      <% end %>
      """
      
      bindings = [users: [
        %{name: "Alice"},
        %{name: "Bob"},
        %{name: "Charlie"}
      ]]
      
      assert {:ok, result} = Template.render(template, bindings)
      assert result =~ "Alice"
      assert result =~ "Bob"
      assert result =~ "Charlie"
    end
    
    test "returns error for missing variable" do
      assert {:error, error} = Template.render("<%= @missing %>", [])
      assert error =~ "Missing template variable: :missing"
    end
    
    test "returns error for invalid syntax" do
      assert {:error, error} = Template.render("<%= if true %>", [])
      assert error =~ "compilation error"
    end
  end
  
  describe "caching" do
    test "caches compiled templates" do
      template = "Hello <%= @name %>!"
      
      # First render compiles
      assert {:ok, "Hello Alice!"} = 
        Template.render(template, name: "Alice")
      
      # Second render uses cache
      assert {:ok, "Hello Bob!"} = 
        Template.render(template, name: "Bob")
      
      # Check cache stats
      stats = Template.cache_stats()
      assert stats.size > 0
    end
    
    test "skips cache when disabled" do
      template = "Hello <%= @name %>!"
      opts = [cache: false]
      
      assert {:ok, "Hello Alice!"} = 
        Template.render(template, [name: "Alice"], opts)
      
      # Cache should be empty
      stats = Template.cache_stats()
      assert stats.size == 0
    end
  end
  
  describe "compile/2" do
    test "compiles valid template" do
      assert {:ok, _compiled} = Template.compile("Hello <%= @name %>!")
    end
    
    test "returns error for invalid template" do
      assert {:error, error} = Template.compile("<%= if true %>")
      assert error =~ "compilation error"
    end
  end
  
  describe "precompile/1" do
    test "precompiles multiple templates" do
      templates = [
        {:greeting, "Hello <%= @name %>!"},
        {:farewell, "Goodbye <%= @name %>!"}
      ]
      
      assert :ok = Template.precompile(templates)
      
      stats = Template.cache_stats()
      assert stats.size >= 2
    end
  end
end
```

### Step 6: Create Performance Benchmarks
Create `/home/home/p/g/n/dspex/bench/template_bench.exs`:

```elixir
defmodule DSPex.TemplateBench do
  use Benchfella
  
  alias DSPex.Native.Template
  
  @simple_template "Hello <%= @name %>!"
  @complex_template """
  <h1><%= @title %></h1>
  <%= if @show_items do %>
    <ul>
    <%= for item <- @items do %>
      <li><%= item.name %> - $<%= item.price %></li>
    <% end %>
    </ul>
  <% end %>
  """
  
  setup_all do
    Template.init()
    {:ok, []}
  end
  
  bench "simple template (cached)" do
    Template.render(@simple_template, name: "World")
  end
  
  bench "simple template (no cache)" do
    Template.render(@simple_template, [name: "World"], cache: false)
  end
  
  bench "complex template (cached)" do
    bindings = [
      title: "Products",
      show_items: true,
      items: [
        %{name: "Widget", price: 9.99},
        %{name: "Gadget", price: 19.99},
        %{name: "Doohickey", price: 29.99}
      ]
    ]
    Template.render(@complex_template, bindings)
  end
  
  bench "precompiled template" do
    # Assumes template was precompiled in setup
    Template.render(@simple_template, name: "World")
  end
end
```

## Acceptance Criteria

- [ ] EEx templates compile correctly without errors
- [ ] Variable binding works for simple and nested data
- [ ] Conditionals and loops function properly
- [ ] Missing variables produce helpful error messages
- [ ] Template compilation errors are clear and actionable
- [ ] Template caching improves performance significantly
- [ ] Performance benchmarks show <1ms for simple templates
- [ ] Helper functions are available and documented
- [ ] All tests pass with 100% coverage

## Expected Deliverables

1. Complete implementation in `/lib/dspex/native/template.ex`
2. Helper module in `/lib/dspex/native/template/helpers.ex`
3. Custom engine in `/lib/dspex/native/template/engine.ex` (optional)
4. Comprehensive test suite with 100% coverage
5. Performance benchmarks showing acceptable performance
6. Documentation with usage examples

## Performance Targets

- Simple template rendering: <0.1ms (cached)
- Complex template rendering: <1ms (cached)
- Cache lookup overhead: <0.01ms
- Memory usage: <1KB per cached template

## Verification

Run these commands to verify implementation:

```bash
# Run tests
mix test test/dspex/native/template_test.exs

# Check coverage
mix test test/dspex/native/template_test.exs --cover

# Run benchmarks
mix run bench/template_bench.exs

# Verify no warnings
mix compile --warnings-as-errors
```

## Notes

- EEx.SmartEngine provides good defaults for HTML safety
- Consider security implications of user-provided templates
- Cache invalidation strategy may be needed for production
- Template syntax should be familiar to web developers
- Error messages are critical for developer experience