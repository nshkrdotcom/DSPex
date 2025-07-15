defmodule Mix.Tasks.RunEnhancement do
  @moduledoc """
  Mix task to run the content enhancement signature example.
  
  Usage:
    mix run_enhancement
  """
  
  use Mix.Task
  
  @shortdoc "Run the content enhancement signature example"

  def run(_args) do
    Mix.Task.run("app.start")
    SignatureExample.run_content_enhancement_example()
  end
end