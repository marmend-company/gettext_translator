defmodule GettextTranslator do
  @moduledoc """
  Documentation for `GettextTranslator`.
  """
  require Logger
  import GettextTranslator.Util.Helper
  alias GettextTranslator.Processor
  alias GettextTranslator.Util.Parser

  def translate(provider, root_gettext_path) do
    with {:ok, results} <- Parser.scan(root_gettext_path) do
      results
      |> process_folders(provider)
      |> summarize_translations()
    end
  end

  defp process_folders(folders, provider) do
    Enum.map(folders, &process_folder(&1, provider))
  end

  defp process_folder(%{language_code: code} = folder, provider) do
    if code in provider.ignored_languages do
      log_ignored_language(code, provider.ignored_languages)
      0
    else
      Processor.run(folder, provider)
    end
  end

  defp log_ignored_language(code, ignored_languages) do
    Logger.info(
      "#{code}/#{lc_messages()} is in ignored languages [#{Enum.join(ignored_languages, ", ")}] - FINISHED with 0 translations"
    )
  end

  defp summarize_translations(translation_counts) do
    {:ok, Enum.sum(translation_counts)}
  end
end
