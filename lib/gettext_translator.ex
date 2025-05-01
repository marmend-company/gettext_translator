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
      iex> GettextTranslator.configure(application: :my_app)
      iex> GettextTranslator.translate(provider, root_path)
      {:ok, total_translations}

  """

  require Logger
  import GettextTranslator.Util.Helper
  alias GettextTranslator.Processor
  alias GettextTranslator.Util.Parser
  alias GettextTranslator.Util.PathHelper

  @doc """
  Configures the GettextTranslator module.

  ## Options
    * `:application` - The OTP application name to use for resolving paths

  ## Example

      iex> GettextTranslator.configure(application: :my_app)
      :ok
  """
  def configure(opts \\ []) do
    app = Keyword.get(opts, :application)

    if app do
      # Store the application name in the application environment
      Application.put_env(:gettext_translator, :application, app)

      # Also set it in the process dictionary for access in different processes
      Process.put(:gettext_translator_application, app)
    end

    :ok
  end

  @doc """
  Returns the configured application name or nil if not configured.
  """
  def application do
    Application.get_env(:gettext_translator, :application) ||
      Process.get(:gettext_translator_application)
  end

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
                          Can be a relative path "priv/gettext" or an absolute path.

  ## Return Value

  Returns `{:ok, total}` where `total` is the sum of translations performed.
  If the scan fails, the function will return the corresponding error tuple.

  ## Examples

      iex> provider = %{ignored_languages: ["fr", "de"]}
      iex> root_gettext_path = "priv/gettext"
      iex> GettextTranslator.translate(provider, root_gettext_path)
      {:ok, total_translations}

  """
  def translate(provider, root_gettext_path) do
    # Resolve the path using PathHelper if it's not absolute
    app = application()

    resolved_path =
      if Path.type(root_gettext_path) == :absolute do
        root_gettext_path
      else
        PathHelper.gettext_dir(app)
      end

    with {:ok, results} <- Parser.scan(resolved_path) do
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
