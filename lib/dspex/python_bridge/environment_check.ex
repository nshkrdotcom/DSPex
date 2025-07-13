defmodule DSPex.PythonBridge.EnvironmentCheck do
  @moduledoc """
  Environment validation for Python bridge setup.

  This module validates that the Python environment is properly configured
  for DSPy integration, including Python executable availability, required
  package installations, and script file accessibility.

  ## Validation Checks

  1. **Python Executable**: Verifies that the configured Python executable exists
  2. **DSPy Installation**: Checks that the DSPy package is installed and importable
  3. **Bridge Script**: Validates that the Python bridge script exists and is readable
  4. **Package Dependencies**: Verifies required Python packages are available
  5. **Version Compatibility**: Ensures compatible versions of Python and packages

  ## Configuration

  Environment checks can be configured through application environment:

      config :dspex, :python_bridge,
        python_executable: "python3",
        required_packages: ["dspy-ai", "openai", "numpy"],
        min_python_version: "3.8.0"

  ## Usage

      case DSPex.PythonBridge.EnvironmentCheck.validate_environment() do
        {:ok, environment_info} ->
          Logger.info("Python environment validated successfully")
          start_bridge(environment_info)
        
        {:error, reason} ->
          Logger.error("Python environment validation failed: \#{reason}")
          {:error, reason}
      end
  """

  require Logger

  @type environment_info :: %{
          python_path: String.t(),
          python_version: String.t(),
          script_path: String.t(),
          dspy_version: String.t(),
          packages: [String.t()]
        }

  @type validation_result :: {:ok, environment_info()} | {:error, String.t()}

  @default_config %{
    python_executable: "python3",
    required_packages: ["dspy-ai"],
    min_python_version: "3.8.0",
    script_path: "python/dspy_bridge.py"
  }

  @doc """
  Validates the complete Python environment for DSPy integration.

  Performs all necessary checks to ensure the Python bridge can start
  and function properly. Returns detailed environment information on
  success or a descriptive error message on failure.

  ## Examples

      iex> DSPex.PythonBridge.EnvironmentCheck.validate_environment()
      {:ok, %{
        python_path: "/usr/bin/python3",
        python_version: "3.9.7",
        script_path: "/app/priv/python/dspy_bridge.py",
        dspy_version: "2.4.9",
        packages: ["dspy-ai", "openai", "numpy"]
      }}

      iex> DSPex.PythonBridge.EnvironmentCheck.validate_environment()
      {:error, "Python executable not found: python3"}
  """
  @spec validate_environment() :: validation_result()
  def validate_environment do
    config = get_configuration()

    with {:ok, python_path} <- find_python_executable(config.python_executable),
         {:ok, python_version} <- check_python_version(python_path, config.min_python_version),
         {:ok, script_path} <- validate_bridge_script(config.script_path),
         {:ok, dspy_version} <- check_dspy_installation(python_path),
         {:ok, packages} <- check_required_packages(python_path, config.required_packages) do
      environment_info = %{
        python_path: python_path,
        python_version: python_version,
        script_path: script_path,
        dspy_version: dspy_version,
        packages: packages
      }

      Logger.info("Python environment validation successful: #{inspect(environment_info)}")
      {:ok, environment_info}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validates only the Python executable without checking packages.

  Quick validation that can be used for basic environment checks
  without the overhead of package validation.

  ## Examples

      iex> DSPex.PythonBridge.EnvironmentCheck.validate_python_executable()
      {:ok, "/usr/bin/python3"}

      iex> DSPex.PythonBridge.EnvironmentCheck.validate_python_executable()
      {:error, "Python executable not found: python3"}
  """
  @spec validate_python_executable() :: {:ok, String.t()} | {:error, String.t()}
  def validate_python_executable do
    config = get_configuration()
    find_python_executable(config.python_executable)
  end

  @doc """
  Checks if DSPy is properly installed and importable.

  Validates that the DSPy package can be imported and returns version
  information if available.

  ## Examples

      iex> DSPex.PythonBridge.EnvironmentCheck.check_dspy_availability()
      {:ok, "2.4.9"}

      iex> DSPex.PythonBridge.EnvironmentCheck.check_dspy_availability()
      {:error, "DSPy package not found or not importable"}
  """
  @spec check_dspy_availability() :: {:ok, String.t()} | {:error, String.t()}
  def check_dspy_availability do
    config = get_configuration()

    case find_python_executable(config.python_executable) do
      {:ok, python_path} -> check_dspy_installation(python_path)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validates that the Python bridge script exists and is accessible.

  Checks file existence, readability, and basic syntax validation.

  ## Examples

      iex> DSPex.PythonBridge.EnvironmentCheck.validate_bridge_script()
      {:ok, "/app/priv/python/dspy_bridge.py"}

      iex> DSPex.PythonBridge.EnvironmentCheck.validate_bridge_script()
      {:error, "Bridge script not found: /app/priv/python/dspy_bridge.py"}
  """
  @spec validate_bridge_script() :: {:ok, String.t()} | {:error, String.t()}
  def validate_bridge_script do
    config = get_configuration()
    validate_bridge_script(config.script_path)
  end

  # Private implementation functions

  @spec get_configuration() :: %{
          min_python_version: binary(),
          python_executable: binary(),
          required_packages: [binary()],
          script_path: binary()
        }
  defp get_configuration do
    bridge_config = Application.get_env(:dspex, :python_bridge, %{})
    Map.merge(@default_config, Map.new(bridge_config))
  end

  @spec find_python_executable(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  defp find_python_executable(python_cmd) do
    # Check for explicit path or executable name
    case System.find_executable(python_cmd) do
      nil ->
        # Try common alternative names
        alternatives = ["python3", "python", "python3.9", "python3.8", "python3.10", "python3.11"]

        case find_alternative_python(alternatives) do
          {:ok, path} ->
            Logger.warning("Configured Python '#{python_cmd}' not found, using '#{path}'")
            {:ok, path}

          :not_found ->
            {:error,
             "Python executable not found: #{python_cmd}. Tried alternatives: #{inspect(alternatives)}"}
        end

      path ->
        {:ok, path}
    end
  end

  @spec find_alternative_python([String.t()]) :: {:ok, String.t()} | :not_found
  defp find_alternative_python([]), do: :not_found

  defp find_alternative_python([cmd | rest]) do
    case System.find_executable(cmd) do
      nil -> find_alternative_python(rest)
      path -> {:ok, path}
    end
  end

  @spec check_python_version(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  defp check_python_version(python_path, min_version) do
    case System.cmd(python_path, ["--version"]) do
      {output, 0} ->
        version_string = String.trim(output)

        case extract_version_number(version_string) do
          {:ok, version} ->
            if version_compatible?(version, min_version) do
              {:ok, version}
            else
              {:error, "Python version #{version} is below minimum required #{min_version}"}
            end

          {:error, reason} ->
            {:error, "Could not parse Python version from: #{version_string}. #{reason}"}
        end

      {error, _exit_code} ->
        {:error, "Failed to check Python version: #{error}"}
    end
  end

  @spec extract_version_number(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  defp extract_version_number(version_output) do
    # Match patterns like "Python 3.9.7" or "Python 3.10.0+"
    case Regex.run(~r/Python (\d+\.\d+\.\d+)/, version_output) do
      [_full, version] -> {:ok, version}
      nil -> {:error, "Version string does not match expected format"}
    end
  end

  @spec version_compatible?(String.t(), String.t()) :: boolean()
  defp version_compatible?(current_version, min_version) do
    case {Version.parse(current_version), Version.parse(min_version)} do
      {{:ok, current}, {:ok, minimum}} ->
        Version.compare(current, minimum) != :lt

      _ ->
        # If we can't parse versions, assume compatible to avoid blocking
        Logger.warning("Could not compare versions: #{current_version} vs #{min_version}")
        true
    end
  end

  @spec validate_bridge_script(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  defp validate_bridge_script(script_relative_path) do
    script_path = Path.join(:code.priv_dir(:dspex), script_relative_path)

    cond do
      not File.exists?(script_path) ->
        {:error, "Bridge script not found: #{script_path}"}

      not File.regular?(script_path) ->
        {:error, "Bridge script is not a regular file: #{script_path}"}

      not readable?(script_path) ->
        {:error, "Bridge script is not readable: #{script_path}"}

      true ->
        case validate_script_syntax(script_path) do
          :ok -> {:ok, script_path}
          {:error, reason} -> {:error, "Bridge script syntax error: #{reason}"}
        end
    end
  end

  @spec readable?(String.t()) :: boolean()
  defp readable?(file_path) do
    case File.stat(file_path) do
      {:ok, %File.Stat{access: access}} -> access in [:read, :read_write]
      {:error, _} -> false
    end
  end

  @spec validate_script_syntax(String.t()) :: :ok | {:error, String.t()}
  defp validate_script_syntax(script_path) do
    # Basic validation - check if file contains expected Python patterns
    case File.read(script_path) do
      {:ok, content} ->
        required_patterns = [
          ~r/class DSPyBridge/,
          ~r/def handle_command/,
          ~r/def main\(\)/
        ]

        case find_missing_pattern(content, required_patterns) do
          nil -> :ok
          pattern -> {:error, "Missing required pattern: #{inspect(pattern)}"}
        end

      {:error, reason} ->
        {:error, "Could not read script file: #{reason}"}
    end
  end

  @spec find_missing_pattern(String.t(), [Regex.t()]) :: Regex.t() | nil
  defp find_missing_pattern(content, patterns) do
    Enum.find(patterns, fn pattern ->
      not Regex.match?(pattern, content)
    end)
  end

  @spec check_dspy_installation(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  defp check_dspy_installation(python_path) do
    import_script = "import dspy; print(dspy.__version__)"

    case System.cmd(python_path, ["-c", import_script], stderr_to_stdout: true) do
      {output, 0} ->
        version = String.trim(output)
        Logger.info("DSPy version detected: #{version}")
        {:ok, version}

      {error_output, _exit_code} ->
        error_msg = String.trim(error_output)

        cond do
          String.contains?(error_msg, "ModuleNotFoundError") ->
            {:error, "DSPy package not installed. Install with: pip install dspy-ai"}

          String.contains?(error_msg, "ImportError") ->
            {:error, "DSPy package found but cannot be imported: #{error_msg}"}

          true ->
            {:error, "DSPy installation check failed: #{error_msg}"}
        end
    end
  end

  @spec check_required_packages(String.t(), [String.t()]) ::
          {:ok, [String.t()]} | {:error, String.t()}
  defp check_required_packages(python_path, required_packages) do
    case check_packages_availability(python_path, required_packages) do
      {:ok, available_packages} ->
        {:ok, available_packages}

      {:error, missing_packages} ->
        {:error, "Missing required packages: #{Enum.join(missing_packages, ", ")}"}
    end
  end

  @spec check_packages_availability(String.t(), [String.t()]) ::
          {:ok, [String.t()]} | {:error, [String.t()]}
  defp check_packages_availability(python_path, packages) do
    results =
      Enum.map(packages, fn package ->
        case check_single_package(python_path, package) do
          :ok -> {:ok, package}
          {:error, _} -> {:error, package}
        end
      end)

    {available, missing} = Enum.split_with(results, &match?({:ok, _}, &1))

    available_packages = Enum.map(available, fn {:ok, pkg} -> pkg end)
    missing_packages = Enum.map(missing, fn {:error, pkg} -> pkg end)

    case missing_packages do
      [] -> {:ok, available_packages}
      missing -> {:error, missing}
    end
  end

  @spec check_single_package(String.t(), String.t()) :: :ok | {:error, String.t()}
  defp check_single_package(python_path, package) do
    # Convert package name to import name (e.g., "dspy-ai" -> "dspy")
    import_name = package_to_import_name(package)
    import_script = "import #{import_name}"

    case System.cmd(python_path, ["-c", import_script], stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {error, _} -> {:error, error}
    end
  end

  @spec package_to_import_name(String.t()) :: String.t()
  defp package_to_import_name("dspy-ai"), do: "dspy"
  defp package_to_import_name(package), do: package
end
