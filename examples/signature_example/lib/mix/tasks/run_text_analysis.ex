defmodule Mix.Tasks.RunTextAnalysis do
  @moduledoc """
  Mix task to run the text analysis signature example.
  
  Usage:
    mix run_text_analysis
  """
  
  use Mix.Task
  
  @shortdoc "Run the text analysis signature example"

  def run(_args) do
    Mix.Task.run("app.start")
    SignatureExample.run_text_analysis_example()
  end
end