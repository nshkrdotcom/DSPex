import Config

# Production-specific configuration
config :logger, level: :info

config :pool_example,
  pool_size: System.get_env("POOL_SIZE", "8") |> String.to_integer(),
  overflow: System.get_env("POOL_OVERFLOW", "4") |> String.to_integer()