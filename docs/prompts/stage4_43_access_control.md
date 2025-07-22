# Stage 4.3: Access Control System Implementation

## Context

You are implementing the Access Control system for the DSPex BridgedState backend. This component provides fine-grained security for variables, ensuring that only authorized sessions can read, write, observe, or optimize specific variables.

## Requirements

The Access Control system must:

1. **Permission Model**: Support read, write, observe, and optimize permissions
2. **Rule-Based Access**: Define access through flexible rule patterns
3. **Session Patterns**: Match sessions using patterns and wildcards
4. **Conditional Access**: Support context-based access decisions
5. **Performance**: Make access decisions with minimal overhead

## Implementation Guide

### 1. Create the Access Control Module

Create `lib/dspex/bridge/access_control.ex`:

```elixir
defmodule DSPex.Bridge.AccessControl do
  @moduledoc """
  Fine-grained access control for variables.
  
  This is a BridgedState-only feature providing security isolation.
  Designed for high-performance permission checking with caching.
  """
  
  require Logger
  
  @type permission :: :read | :write | :observe | :optimize
  @type rule :: %{
    session_pattern: String.t() | :any,
    permissions: [permission()],
    conditions: map(),
    priority: integer()
  }
end
```

### 2. Permission Model

Define the permission hierarchy:

```elixir
# Permission definitions
@permissions [:read, :write, :observe, :optimize]

# Permission implications (having X implies having Y)
@permission_implications %{
  write: [:read],
  optimize: [:read, :write]
}

# Default permissions for owner
@owner_permissions [:read, :write, :observe, :optimize]
```

### 3. Core Access Control API

```elixir
# Check if session has permission
def check_permission(variable, session_id, permission, context \\ %{})

# Validate access rules
def validate_rules(rules)

# Add access rule to variable
def add_rule(variable, rule)

# Remove access rule
def remove_rule(variable, rule_id)

# Get effective permissions for session
def get_permissions(variable, session_id, context \\ %{})

# Filter accessible variables
def filter_accessible_variables(variables, session_id, permission)

# Batch permission check
def check_permissions_batch(var_perms, session_id, context \\ %{})
```

### 4. Rule Structure

Design flexible access rules:

```elixir
@type access_rule :: %{
  # Required fields
  id: String.t(),
  session_pattern: pattern(),
  permissions: [permission()],
  
  # Optional fields
  conditions: %{String.t() => any()},
  priority: integer(),
  expires_at: DateTime.t() | nil,
  granted_by: String.t(),
  granted_at: DateTime.t()
}

@type pattern ::
  :any |                    # Matches any session
  {:exact, String.t()} |    # Exact match
  {:prefix, String.t()} |   # Prefix match
  {:suffix, String.t()} |   # Suffix match
  {:regex, Regex.t()}       # Regex pattern
```

### 5. Pattern Matching

Implement efficient pattern matching:

```elixir
defp matches_pattern?(:any, _session_id), do: true

defp matches_pattern?({:exact, pattern}, session_id) do
  pattern == session_id
end

defp matches_pattern?({:prefix, prefix}, session_id) do
  String.starts_with?(session_id, prefix)
end

defp matches_pattern?({:suffix, suffix}, session_id) do
  String.ends_with?(session_id, suffix)
end

defp matches_pattern?({:regex, regex}, session_id) do
  Regex.match?(regex, session_id)
end

# Compile string patterns
defp compile_pattern("*"), do: :any
defp compile_pattern(pattern) do
  cond do
    String.contains?(pattern, "*") ->
      regex = pattern
      |> String.replace("*", ".*")
      |> Regex.compile!()
      {:regex, regex}
    
    true ->
      {:exact, pattern}
  end
end
```

### 6. Condition Evaluation

Support contextual conditions:

```elixir
@type condition ::
  {:equals, any()} |
  {:not_equals, any()} |
  {:in, [any()]} |
  {:not_in, [any()]} |
  {:matches, Regex.t()} |
  {:custom, (any() -> boolean())}

defp evaluate_condition(context, key, condition) do
  value = Map.get(context, key)
  
  case condition do
    {:equals, expected} ->
      value == expected
    
    {:not_equals, expected} ->
      value != expected
    
    {:in, allowed} ->
      value in allowed
    
    {:not_in, forbidden} ->
      value not in forbidden
    
    {:matches, regex} ->
      is_binary(value) and Regex.match?(regex, value)
    
    {:custom, func} ->
      func.(value)
  end
end
```

### 7. Permission Checking Algorithm

Implement efficient permission checking:

```elixir
def check_permission(variable, session_id, permission, context) do
  # 1. Check if owner
  if is_owner?(variable, session_id) do
    :ok
  else
    # 2. Get applicable rules
    rules = get_applicable_rules(variable, session_id, context)
    
    # 3. Check if any rule grants permission
    if has_permission_in_rules?(rules, permission) do
      :ok
    else
      {:error, :access_denied}
    end
  end
end

defp get_applicable_rules(variable, session_id, context) do
  variable.access_rules
  |> Enum.filter(fn rule ->
    matches_pattern?(rule.session_pattern, session_id) and
    matches_conditions?(rule.conditions, context) and
    not expired?(rule)
  end)
  |> Enum.sort_by(& &1.priority, :desc)
end
```

### 8. Caching Strategy

Implement permission caching for performance:

```elixir
defmodule DSPex.Bridge.AccessControl.Cache do
  use GenServer
  
  @cache_ttl 300_000  # 5 minutes
  
  def check_cached(cache_key) do
    case :ets.lookup(:access_cache, cache_key) do
      [{^cache_key, result, expires_at}] ->
        if System.monotonic_time(:millisecond) < expires_at do
          {:ok, result}
        else
          :miss
        end
      [] ->
        :miss
    end
  end
  
  def cache_result(cache_key, result) do
    expires_at = System.monotonic_time(:millisecond) + @cache_ttl
    :ets.insert(:access_cache, {cache_key, result, expires_at})
  end
end
```

### 9. Audit Logging

Log all access decisions:

```elixir
defp log_access_decision(variable_id, session_id, permission, result, context) do
  event = %{
    timestamp: DateTime.utc_now(),
    variable_id: variable_id,
    session_id: session_id,
    permission: permission,
    result: result,
    context: context
  }
  
  # Emit telemetry
  :telemetry.execute(
    [:dspex, :access_control, :decision],
    %{},
    event
  )
  
  # Log based on result
  case result do
    :ok ->
      Logger.debug("Access granted", event: event)
    {:error, reason} ->
      Logger.info("Access denied: #{reason}", event: event)
  end
end
```

### 10. Integration with Variables

Enhance variable metadata:

```elixir
defmodule DSPex.Bridge.Variables.Variable do
  defstruct [
    # ... existing fields ...
    :owner_session,
    :access_rules,
    :access_mode,  # :private | :protected | :public
    :audit_access  # boolean
  ]
end

# In SessionStore
def update_variable_with_access_check(session_id, var_id, value, metadata) do
  with {:ok, variable} <- get_variable(var_id),
       :ok <- AccessControl.check_permission(variable, session_id, :write, metadata) do
    # Proceed with update
  else
    {:error, :access_denied} = error ->
      log_access_violation(session_id, var_id, :write)
      error
  end
end
```

### 11. Telemetry Events

Emit detailed telemetry:

```elixir
# Access check performed
:telemetry.execute(
  [:dspex, :access_control, :check],
  %{duration_us: duration},
  %{
    variable_id: var_id,
    session_id: session_id,
    permission: permission,
    result: result,
    cache_hit: cache_hit
  }
)

# Rule evaluated
:telemetry.execute(
  [:dspex, :access_control, :rule_evaluated],
  %{},
  %{
    rule_id: rule.id,
    pattern_type: pattern_type,
    matched: matched
  }
)

# Access violation
:telemetry.execute(
  [:dspex, :access_control, :violation],
  %{},
  %{
    variable_id: var_id,
    session_id: session_id,
    permission: permission,
    reason: reason
  }
)
```

### 12. Testing Scenarios

Test comprehensive scenarios:

1. **Basic Access Control**:
   - Owner has all permissions
   - Non-owner denied by default
   - Simple rule grants

2. **Pattern Matching**:
   - Exact session matching
   - Wildcard patterns
   - Regex patterns
   - Multiple pattern types

3. **Conditional Access**:
   - Time-based conditions
   - Context value conditions
   - Complex condition combinations

4. **Rule Priority**:
   - Higher priority overrides
   - Multiple matching rules
   - Explicit deny rules

5. **Performance**:
   - Cache hit rates
   - Batch permission checks
   - Large rule sets

### 13. Example Usage

```elixir
# Define a variable with access rules
variable = %Variable{
  id: "secret_data",
  owner_session: "session_123",
  access_rules: [
    %{
      id: "rule_1",
      session_pattern: {:prefix, "admin_"},
      permissions: [:read, :write],
      conditions: %{},
      priority: 100
    },
    %{
      id: "rule_2", 
      session_pattern: {:regex, ~r/^service_\d+$/},
      permissions: [:read],
      conditions: %{
        "ip_range" => {:in, ["10.0.0.0/8", "172.16.0.0/12"]}
      },
      priority: 50
    }
  ]
}

# Check permissions
:ok = AccessControl.check_permission(variable, "admin_user", :write)
{:error, :access_denied} = AccessControl.check_permission(variable, "user_456", :write)
:ok = AccessControl.check_permission(variable, "service_001", :read, %{"ip_range" => "10.0.0.5"})
```

## Implementation Checklist

- [ ] Create AccessControl module with permission types
- [ ] Implement pattern matching system
- [ ] Add condition evaluation engine
- [ ] Create permission checking algorithm
- [ ] Implement caching layer
- [ ] Add audit logging
- [ ] Integrate with Variable structure
- [ ] Add rule validation
- [ ] Implement batch operations
- [ ] Create comprehensive telemetry
- [ ] Write unit tests for all patterns
- [ ] Add integration tests
- [ ] Benchmark permission checks
- [ ] Document security model

## Success Criteria

1. **Security**: No unauthorized access possible
2. **Flexibility**: Support complex access patterns
3. **Performance**: Sub-microsecond cached decisions
4. **Auditability**: Complete access decision trail
5. **Usability**: Simple API for common cases
6. **Scalability**: Efficient with thousands of rules