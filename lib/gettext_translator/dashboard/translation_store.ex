defmodule GettextTranslator.Dashboard.TranslationStore do
  @moduledoc """
  In-memory store for translation entries using ETS.
  This module manages the storage and retrieval of translations for the dashboard.
  """

  use GenServer
  require Logger
  alias Expo.{Message, PO}
  alias GettextTranslator.Util.Parser
  import GettextTranslator.Util.Helper

  @table_name :gettext_translator_entries

  # Client API

  @doc """
  Starts the translation store.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Scans the gettext directories and loads all translations into memory.
  """
  def load_translations(gettext_path) do
    GenServer.call(__MODULE__, {:load_translations, gettext_path}, 30_000)
  end

  @doc """
  Returns all translations.
  """
  def list_translations do
    case :ets.info(@table_name) do
      :undefined ->
        []

      _ ->
        :ets.tab2list(@table_name)
        |> Enum.map(fn {_id, translation} -> translation end)
    end
  end

  @doc """
  Returns translations filtered by criteria.

  ## Examples

  ```elixir
  # Get all Spanish translations
  TranslationStore.filter_translations(%{language_code: "es"})

  # Get all pending translations
  TranslationStore.filter_translations(%{status: :pending})

  # Get all pending Spanish translations
  TranslationStore.filter_translations(%{status: :pending, language_code: "es"})
  ```
  """
  def filter_translations(criteria) when is_map(criteria) do
    list_translations()
    |> Enum.filter(fn translation ->
      Enum.all?(criteria, fn {key, value} ->
        Map.get(translation, key) == value
      end)
    end)
  end

  @doc """
  Gets a specific translation by ID.
  """
  def get_translation(id) when is_binary(id) do
    case :ets.lookup(@table_name, id) do
      [{^id, translation}] -> {:ok, translation}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Updates a translation entry in the ETS store.

  ## Parameters

  * `id` - The ID of the translation to update
  * `params` - A map of attributes to update

  ## Examples

  ```elixir
  # Update a translation with new text
  TranslationStore.update_translation("abc123", %{
    translation: "New translation text",
    status: :modified
  })

  # Approve a translation
  TranslationStore.update_translation("abc123", %{status: :translated})
  ```
  """
  def update_translation(id, params) when is_binary(id) and is_map(params) do
    case get_translation(id) do
      {:ok, translation} ->
        # Merge new params with existing translation
        updated = Map.merge(translation, params)
        # Insert updated translation into ETS
        :ets.insert(@table_name, {id, updated})
        {:ok, updated}

      error ->
        error
    end
  end

  # Server callbacks

  @impl true
  def init(_) do
    # Create ETS table
    :ets.new(@table_name, [:set, :named_table, :public, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:load_translations, gettext_path}, _from, state) do
    result =
      case Parser.scan(gettext_path) do
        {:ok, folders} ->
          translation_entries = process_translation_folders(folders)
          {:ok, length(translation_entries)}

        error ->
          error
      end

    {:reply, result, state}
  end

  # Private functions

  defp process_translation_folders(folders) do
    Enum.flat_map(folders, fn %{language_code: code, files: files} ->
      Enum.flat_map(files, fn file_path ->
        process_po_file(file_path, code)
      end)
    end)
  end

  defp process_po_file(file_path, language_code) do
    case PO.parse_file(file_path) do
      {:ok, po} ->
        domain = extract_domain_from_path(file_path)

        po.messages
        |> Enum.map(fn message ->
          translation = create_translation_entry(message, file_path, language_code, domain)
          :ets.insert(@table_name, {translation.id, translation})
          translation
        end)

      _ ->
        []
    end
  end

  defp create_translation_entry(message, file_path, language_code, domain) do
    id = :crypto.hash(:sha256, "#{file_path}|#{get_msgid(message)}") |> Base.encode16()

    case message do
      %Message.Singular{msgid: msgid, msgstr: msgstr} ->
        %{
          id: id,
          language_code: language_code,
          message_id: Enum.join(msgid, ""),
          translation: Enum.join(msgstr, ""),
          file_path: file_path,
          domain: domain,
          status: get_translation_status(msgstr),
          type: :singular
        }

      %Message.Plural{msgid: msgid, msgid_plural: msgid_plural, msgstr: msgstr} ->
        %{
          id: id,
          language_code: language_code,
          message_id: Enum.join(msgid, ""),
          plural_id: Enum.join(msgid_plural, ""),
          translation: Enum.join(msgstr[0] || [], ""),
          plural_translation: Enum.join(msgstr[1] || [], ""),
          file_path: file_path,
          domain: domain,
          status: get_plural_translation_status(msgstr),
          type: :plural
        }
    end
  end

  defp get_msgid(%Message.Singular{msgid: msgid}), do: Enum.join(msgid, "")
  defp get_msgid(%Message.Plural{msgid: msgid}), do: Enum.join(msgid, "")

  # More robust handling for singular translations
  defp get_translation_status(msgstr) when is_list(msgstr) do
    translation = Enum.join(msgstr, "")
    if empty_string?(translation), do: :pending, else: :translated
  end

  defp get_translation_status(_), do: :pending

  # More robust handling for plural translations
  defp get_plural_translation_status(msgstr) when is_map(msgstr) do
    singular = msgstr[0] || []
    plural = msgstr[1] || []

    singular_str = if is_list(singular), do: Enum.join(singular, ""), else: ""
    plural_str = if is_list(plural), do: Enum.join(plural, ""), else: ""

    if empty_string?(singular_str) or empty_string?(plural_str) do
      :pending
    else
      :translated
    end
  end

  defp get_plural_translation_status(_), do: :pending

  defp extract_domain_from_path(file_path) do
    file_path
    |> Path.basename()
    |> String.replace_suffix(".po", "")
  end
end
