defmodule Mix.Tasks.GettextTranslator.Run do
  @moduledoc ~s"""
   GettextTranslator usage:
   * Base using default gettext folder (priv/gettext)
      ```
      mix gettext_translator.run
      ```

   * Providing specific gettext folder
      ```
      mix gettext_translator.run my_path/gettext
      ```
  """

  @requirements ["app.start"]
  @preferred_cli_env :dev

  use Mix.Task
  alias GettextTranslator.Util.Parser

  @impl Mix.Task
  def run(args) do
    root_dir = Enum.at(args, 0, "priv/gettext")

    config = Parser.parse_provider()

    Mix.shell().info("GettextTranslator has started")

    {:ok, messages_count} =
      GettextTranslator.translate(
        config,
        Path.join([root_dir])
      )

    Mix.shell().info(
      "GettextTranslator has finished with translations. #{messages_count} messages has been translated"
    )
  end
end
