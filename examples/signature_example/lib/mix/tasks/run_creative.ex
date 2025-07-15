defmodule Mix.Tasks.RunCreative do
  @moduledoc """
  Mix task to run the creative writing signature example.
  
  Usage:
    mix run_creative
  """
  
  use Mix.Task
  
  @shortdoc "Run the creative writing signature example"

  def run(_args) do
    Mix.Task.run("app.start")
    SignatureExample.run_creative_writing_example()
  end
end