defmodule Mix.Tasks.RunTranslation do
  @moduledoc """
  Mix task to run the translation signature example.
  
  Usage:
    mix run_translation
  """
  
  use Mix.Task
  
  @shortdoc "Run the translation signature example"

  def run(_args) do
    Mix.Task.run("app.start")
    SignatureExample.run_translation_example()
  end
end