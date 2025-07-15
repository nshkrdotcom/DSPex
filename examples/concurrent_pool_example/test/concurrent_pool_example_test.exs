defmodule ConcurrentPoolExampleTest do
  use ExUnit.Case
  doctest ConcurrentPoolExample

  test "greets the world" do
    assert ConcurrentPoolExample.hello() == :world
  end
end
