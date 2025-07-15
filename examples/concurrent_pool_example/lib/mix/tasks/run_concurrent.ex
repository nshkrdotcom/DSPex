defmodule Mix.Tasks.RunConcurrent do
  @moduledoc """
  Mix task to run the Concurrent Pool Example.
  
  ## Usage
  
      mix run_concurrent
      mix run_concurrent affinity
      mix run_concurrent benchmark
      mix run_concurrent errors
  """
  
  use Mix.Task

  @shortdoc "Runs the Concurrent Pool Example"

  def run(args) do
    # Ensure the application is started
    Mix.Task.run("app.start")
    
    ConcurrentPoolExample.CLI.main(args)
  end
end