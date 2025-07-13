defmodule AshDSPexTest do
  use ExUnit.Case
  doctest AshDSPex

  test "version returns a string" do
    version = AshDSPex.version()
    assert is_binary(version)
    assert version =~ ~r/\d+\.\d+\.\d+/
  end
end
