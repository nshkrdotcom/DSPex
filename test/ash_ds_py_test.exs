defmodule DSPexTest do
  use ExUnit.Case
  doctest DSPex

  test "version returns a string" do
    version = DSPex.version()
    assert is_binary(version)
    assert version =~ ~r/\d+\.\d+\.\d+/
  end
end
