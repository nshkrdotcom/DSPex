ExUnit.start()

# Configure test environment
Application.put_env(:logger, :level, :warn)

# Set test mode to ensure proper adapter selection
System.put_env("TEST_MODE", "signature_example")