import Config

# Auto-configure snakepit for snakebridge (replaces 30 lines of boilerplate).
# Skip in tests to avoid starting Python workers during `mix test`.
if config_env() != :test do
  SnakeBridge.ConfigHelper.configure_snakepit!()
end
