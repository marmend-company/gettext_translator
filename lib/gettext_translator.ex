defmodule GettextTranslator do
  @moduledoc """
  A module for translating gettext files.

  This module provides functionality to scan directories for gettext files,
  process translation folders, and summarize the results. It leverages helper functions
  and processors defined in other modules.

  ## Overview

  The main entry point of this module is the `translate/2` function which:
    1. Scans the specified root directory for gettext files using `Parser.scan/1`.
    2. Processes each folder corresponding to a language.
    3. Summarizes the total number of translations made.

  Languages that are defined in the `provider`'s `ignored_languages` list will be skipped,
  and a log message is generated.

  ## Example Usage

      iex> provider = %{ignored_languages: ["fr", "de"]}
      iex> root_path = "path/to/gettext"
      iex> GettextTranslator.translate(provider, root_path)
      {:ok, total_translations}

  """

  require Logger
  import GettextTranslator.Util.Helper
  alias GettextTranslator.Processor
  alias GettextTranslator.Util.Parser

  @doc """
  Translates the gettext files located at the given root path.

  This function performs the following steps:
    1. Scans the `root_gettext_path` for gettext files using `Parser.scan/1`.
    2. Processes each language folder found by filtering out languages that are ignored
       (as specified in the `provider` map's `ignored_languages` key) and running the translation
       process on the rest using `Processor.run/2`.
    3. Summarizes the total number of translations performed across all folders.

  ## Parameters

    - `provider`: A map or struct that configures the translation process. It must include an
      `ignored_languages` key which is a list of language codes to be skipped.
    - `root_gettext_path`: The root directory path where gettext files are stored.

  ## Return Value

  Returns `{:ok, total}` where `total` is the sum of translations performed.
  If the scan fails, the function will return the corresponding error tuple.

  ## Examples

      iex> provider = %{ignored_languages: ["fr", "de"]}
      iex> root_gettext_path = "path/to/gettext"
      iex> GettextTranslator.translate(provider, root_gettext_path)
      {:ok, total_translations}

  """
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
