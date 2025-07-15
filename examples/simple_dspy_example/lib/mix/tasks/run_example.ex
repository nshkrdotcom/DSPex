defmodule Mix.Tasks.RunExample do
  @moduledoc """
  Mix task to run the Simple DSPy Example.
  
  ## Usage
  
      mix run_example
      mix run_example models
      mix run_example errors
  """
  
  use Mix.Task

  @shortdoc "Runs the Simple DSPy Example"

  def run(args) do
    # Ensure the application is started
    Mix.Task.run("app.start")
    
    SimpleDspyExample.CLI.main(args)
  end
end