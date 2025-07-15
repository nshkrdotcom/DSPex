defmodule Mix.Tasks.RunAllExamples do
  @moduledoc """
  Mix task to run all signature examples.
  
  Usage:
    mix run_all_examples
  """
  
  use Mix.Task
  
  @shortdoc "Run all signature examples"

  def run(_args) do
    Mix.Task.run("app.start")
    SignatureExample.run_all_examples()
  end
end