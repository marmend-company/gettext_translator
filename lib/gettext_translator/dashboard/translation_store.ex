defmodule GettextTranslator.Dashboard.TranslationStore do
  @moduledoc """
  In-memory store for translation entries using ETS.
  This module manages the storage and retrieval of translations for the dashboard.
  """

  use GenServer
  require Logger
  alias Expo.{Message, PO}
  alias GettextTranslator.Util.Parser
  alias GettextTranslator.Util.PathHelper
  import GettextTranslator.Util.Helper

  @table_name :gettext_translator_entries
  @changelog_table :gettext_translator_changelog

  # Client API

  @doc """
  Starts the translation store.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Scans the gettext directories and loads all translations into memory.
  Also loads associated changelog files.
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

        # Update changelog status if this was an approval
        updated =
          if params[:status] == :translated and Map.has_key?(translation, :changelog_id) and
               not is_nil(translation.changelog_id) do
            case update_changelog_status(translation.changelog_id, "APPROVED") do
              {:ok, _changelog_entry} ->
                Map.put(updated, :changelog_status, "APPROVED")

              _ ->
                updated
            end
          else
            updated
          end

        {:ok, updated}

      error ->
        error
    end
  end

  @doc """
  Updates the status of a changelog entry.
  """
  def update_changelog_status(changelog_id, status) when is_binary(changelog_id) do
    case :ets.lookup(@changelog_table, changelog_id) do
      [{^changelog_id, entry}] ->
        # Only mark as modified if status is changing
        modified = entry.status != status

        updated =
          Map.merge(entry, %{
            status: status,
            modified: modified
          })

        :ets.insert(@changelog_table, {changelog_id, updated})
        {:ok, updated}

      [] ->
        {:error, :not_found}
    end
  end

  # Server callbacks

  @impl true
  def init(_) do
    # Create ETS tables
    :ets.new(@table_name, [:set, :named_table, :public, read_concurrency: true])
    :ets.new(@changelog_table, [:set, :named_table, :public, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:load_translations, gettext_path}, _from, state) do
    # First reset the tables
    :ets.delete_all_objects(@table_name)
    :ets.delete_all_objects(@changelog_table)

    # Ensure changelog directory exists
    PathHelper.ensure_changelog_dir()

    result =
      case Parser.scan(gettext_path) do
        {:ok, folders} ->
          # Process PO files first
          translation_entries = process_translation_folders(folders)

          # Then process changelog files
          changelog_entries = load_changelog_files(folders)

          # Match changelog entries with translations
          match_changelog_with_translations(changelog_entries)

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
          type: :singular,
          # Will be updated from changelog
          changelog_status: nil
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
          type: :plural,
          # Will be updated from changelog
          changelog_status: nil
        }
    end
  end

  defp load_changelog_files(folders) do
    Logger.info("Loading changelog files")

    result =
      Enum.flat_map(folders, fn %{language_code: code, files: files} ->
        Enum.flat_map(files, fn file_path ->
          # Use PathHelper to get consistent changelog path
          changelog_path = PathHelper.changelog_path_for_po(file_path)

          Logger.debug("Checking for changelog at: #{changelog_path}")
          entries = process_changelog_file(changelog_path, file_path, code)
          Logger.debug("Found #{length(entries)} entries in #{changelog_path}")
          entries
        end)
      end)

    Logger.info("Loaded #{length(result)} total changelog entries")
    result
  end

  @doc """
  Creates a changelog entry for a translation.
  """
  def create_changelog_entry(translation, status \\ "NEW") do
    # Create a unique entry ID
    entry_id =
      :crypto.hash(
        :sha256,
        "#{translation.file_path}|#{translation.message_id}|#{DateTime.utc_now()}"
      )
      |> Base.encode16()

    original =
      case translation.type do
        :singular -> [translation.message_id]
        :plural -> [translation.message_id, translation.plural_id]
      end

    translated =
      case translation.type do
        :singular -> translation.translation
        :plural -> "#{translation.translation} | #{translation.plural_translation}"
      end

    # Get the domain for the changelog
    # domain = extract_domain_from_path(translation.file_path)

    Logger.debug("Creating changelog entry for #{translation.message_id} with status #{status}")

    changelog_entry = %{
      id: entry_id,
      code: translation.language_code,
      status: status,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      type: Atom.to_string(translation.type),
      original: original,
      translated: translated,
      source_file: translation.file_path,
      # Mark as modified to ensure it gets saved
      modified: true
    }

    # Store in changelog table
    :ets.insert(@changelog_table, {entry_id, changelog_entry})

    # Update the translation with the changelog ID
    updated_translation =
      Map.merge(translation, %{
        changelog_id: entry_id,
        changelog_status: status,
        changelog_timestamp: changelog_entry.timestamp
      })

    :ets.insert(@table_name, {translation.id, updated_translation})

    {:ok, changelog_entry}
  end

  @doc """
  Saves changelog entries to their corresponding files.
  """
  def save_changelog_to_files do
    entries_by_file = get_entries_by_file()

    if Enum.empty?(entries_by_file) do
      []
    else
      # Get the application name from configuration or ETS
      app = get_application()

      # Ensure the directory exists using PathHelper
      GettextTranslator.Util.PathHelper.ensure_changelog_dir(app)

      # Process each file and its entries, passing the app name
      Enum.map(entries_by_file, fn file_entries ->
        process_file_entries(file_entries, app)
      end)
    end
  end

  defp get_application do
    # Try application environment first
    # Then try ETS table if it exists
    # Finally try the global configuration
    Application.get_env(:gettext_translator, :dashboard_application) ||
      case :ets.info(:gettext_translator_config) do
        :undefined ->
          nil

        _ ->
          case :ets.lookup(:gettext_translator_config, :application) do
            [{:application, app}] -> app
            _ -> nil
          end
      end ||
      GettextTranslator.application()
  end

  defp get_entries_by_file do
    :ets.tab2list(@changelog_table)
    |> Enum.map(fn {_, entry} -> entry end)
    |> Enum.group_by(& &1.source_file)
  end

  defp process_file_entries({file_path, entries}, app) do
    # Extract language code and domain
    language_code = List.first(entries).code
    domain = extract_domain_from_path(file_path)

    # Construct the changelog path using PathHelper
    relative_path = "#{language_code}_#{domain}_changelog.json"

    changelog_path =
      if app do
        Path.join(GettextTranslator.Util.PathHelper.translation_changelog_dir(app), relative_path)
      else
        Path.join("priv/translation_changelog", relative_path)
      end

    Logger.debug("Saving changelog to: #{changelog_path}")

    # Get or create the changelog - make sure this function handles absolute paths
    changelog = read_or_create_changelog(changelog_path, language_code, file_path)

    # Get entries that need to be processed
    entries_to_process = filter_entries_to_process(entries)

    if Enum.any?(entries_to_process) do
      # Process and save changelog
      process_and_save_changelog(changelog_path, changelog, entries_to_process)
    else
      {:ok, "No changes for #{changelog_path}"}
    end
  end

  defp read_or_create_changelog(path, language_code, file_path) do
    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, changelog} ->
            changelog

          {:error, reason} ->
            Logger.error("Failed to decode JSON for #{path}: #{inspect(reason)}")
            create_new_changelog(language_code, file_path)
        end

      {:error, :enoent} ->
        # File doesn't exist - create new changelog
        Logger.debug("Creating new changelog file at #{path}")
        create_new_changelog(language_code, file_path)

      {:error, reason} ->
        Logger.error("Error reading changelog file #{path}: #{inspect(reason)}")
        create_new_changelog(language_code, file_path)
    end
  end

  defp create_new_changelog(language_code, file_path) do
    %{"history" => [], "language" => language_code, "source_file" => file_path}
  end

  defp filter_entries_to_process(entries) do
    Enum.filter(entries, fn entry ->
      entry.modified || entry.status == "APPROVED"
    end)
  end

  defp process_and_save_changelog(path, changelog, entries_to_process) do
    history = Map.get(changelog, "history", [])
    entries_by_original = group_entries_by_original(entries_to_process)

    # Update existing history entries
    updated_history = update_existing_history(history, entries_by_original)

    # Check for remaining entries that need new history entries
    remaining_entries = get_remaining_entries(entries_by_original)

    # Create final history with any new entries
    final_history = add_new_history_entries(remaining_entries, updated_history)

    # Save to file
    save_changelog_to_file(path, Map.put(changelog, "history", final_history))
  end

  defp group_entries_by_original(entries) do
    Enum.group_by(
      entries,
      fn entry -> Enum.join(entry.original, "") end
    )
  end

  defp update_existing_history(history, entries_by_original) do
    Enum.map(history, fn history_entry ->
      history_entries = Map.get(history_entry, "entries", [])

      # Update entries in this history record
      updated_entries = update_history_entries(history_entries, entries_by_original)

      # Return the updated history entry
      Map.put(history_entry, "entries", updated_entries)
    end)
  end

  defp update_history_entries(entries, entries_by_original) do
    Enum.map(entries, fn entry ->
      # Get the original text from the entry
      original_text = entry["original"] |> Enum.join("")

      # Check if we have an update for this entry
      case Map.get(entries_by_original, original_text) do
        [updated_entry | _] ->
          update_entry_if_needed(entry, updated_entry, original_text)

        _ ->
          # No change to this entry
          entry
      end
    end)
  end

  defp update_entry_if_needed(entry, updated_entry, original_text) do
    # Check if this is a NEW -> APPROVED transition
    if entry["status"] == "NEW" and updated_entry.status == "APPROVED" do
      # Update the entry status
      Logger.debug("Updating status for #{original_text} from NEW to APPROVED")

      # Mark as not modified since we're updating it here
      :ets.insert(
        @changelog_table,
        {updated_entry.id, Map.put(updated_entry, :modified, false)}
      )

      # Return updated entry with APPROVED status
      %{
        "code" => entry["code"],
        "original" => entry["original"],
        "status" => "APPROVED",
        "timestamp" => updated_entry.timestamp,
        "translated" => entry["translated"],
        "type" => entry["type"]
      }
    else
      # Not a NEW -> APPROVED transition
      entry
    end
  end

  defp get_remaining_entries(entries_by_original) do
    entries_by_original
    |> Map.values()
    |> List.flatten()
    |> Enum.filter(fn entry -> entry.modified end)
  end

  defp add_new_history_entries(remaining_entries, updated_history) do
    if Enum.any?(remaining_entries) do
      # Create a new history entry
      new_history_entry = create_new_history_entry(remaining_entries)

      # Mark these entries as not modified
      mark_entries_as_not_modified(remaining_entries)

      # Add new history entry to the beginning
      [new_history_entry | updated_history]
    else
      # No new entries to add
      updated_history
    end
  end

  defp create_new_history_entry(entries) do
    %{
      "entries" =>
        Enum.map(entries, fn entry ->
          %{
            "code" => entry.code,
            "status" => entry.status,
            "timestamp" => entry.timestamp,
            "type" => entry.type,
            "original" => entry.original,
            "translated" => entry.translated
          }
        end),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp mark_entries_as_not_modified(entries) do
    Enum.each(entries, fn entry ->
      :ets.insert(@changelog_table, {entry.id, Map.put(entry, :modified, false)})
    end)
  end

  defp save_changelog_to_file(path, changelog) do
    case File.write(path, Jason.encode!(changelog, pretty: true)) do
      :ok ->
        {:ok, path}

      {:error, reason} ->
        Logger.error("Failed to write changelog file #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp match_changelog_with_translations(changelog_entries) do
    # Group changelog entries by original text
    entries_by_original =
      Enum.group_by(
        changelog_entries,
        fn entry -> {entry.source_file, Enum.join(entry.original, "")} end
      )

    # Process all translations in the store
    :ets.tab2list(@table_name)
    |> Enum.each(fn {id, translation} ->
      key = {translation.file_path, translation.message_id}

      # Find matching changelog entries
      case Map.get(entries_by_original, key) do
        nil ->
          # No exact match - try with normalized paths
          normalized_entries =
            Enum.filter(entries_by_original, fn {{source_file, msg_id}, _} ->
              po_path =
                PathHelper.po_path_for_changelog(PathHelper.changelog_path_for_po(source_file))

              po_path == translation.file_path && msg_id == translation.message_id
            end)

          case normalized_entries do
            # No match found
            [] -> :ok
            [{_, entries} | _] -> apply_newest_changelog_entry(id, translation, entries)
          end

        entries ->
          apply_newest_changelog_entry(id, translation, entries)
      end
    end)
  end

  defp apply_newest_changelog_entry(id, translation, entries) do
    # Sort by timestamp (newest first)
    sorted_entries =
      Enum.sort_by(
        entries,
        fn entry ->
          case entry.timestamp do
            timestamp when is_binary(timestamp) ->
              case DateTime.from_iso8601(timestamp) do
                {:ok, dt, _} -> dt
                # Default for invalid timestamps
                _ -> ~U[1970-01-01 00:00:00Z]
              end

            # Default for non-string timestamps
            _ ->
              ~U[1970-01-01 00:00:00Z]
          end
        end,
        {:desc, DateTime}
      )

    # Get the newest entry
    newest = List.first(sorted_entries)

    # Update translation with changelog info
    updated =
      Map.merge(translation, %{
        changelog_id: newest.id,
        changelog_status: newest.status,
        changelog_timestamp: newest.timestamp
      })

    :ets.insert(@table_name, {id, updated})
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

  defp process_changelog_file(changelog_path, source_file, _language_code) do
    with {:ok, content} <- File.read(changelog_path),
         {:ok, changelog} <- Jason.decode(content),
         %{"history" => history} when is_list(history) <- changelog do
      Logger.debug("Successfully parsed changelog from #{changelog_path}")
      Logger.debug("History entries: #{length(history)}")

      # Process history entries, newest first
      result =
        history
        |> Enum.flat_map(fn %{"entries" => entries, "timestamp" => history_timestamp} ->
          Logger.debug("Processing history batch with #{length(entries)} entries")

          Enum.map(entries, fn entry ->
            # Create a unique id for this changelog entry
            entry_id =
              :crypto.hash(
                :sha256,
                "#{source_file}|#{inspect(entry["original"])}|#{entry["timestamp"]}"
              )
              |> Base.encode16()

            original = entry["original"]

            changelog_entry = %{
              id: entry_id,
              code: entry["code"],
              status: entry["status"],
              timestamp: entry["timestamp"],
              history_timestamp: history_timestamp,
              type: entry["type"],
              original: original,
              translated: entry["translated"],
              source_file: source_file,
              modified: false
            }

            # Store in changelog table
            :ets.insert(@changelog_table, {entry_id, changelog_entry})

            changelog_entry
          end)
        end)

      Logger.debug("Created #{length(result)} changelog entries")
      result
    else
      {:error, :enoent} ->
        Logger.debug("No changelog file found at #{changelog_path}")
        []

      {:error, reason} ->
        Logger.error("Error reading changelog #{changelog_path}: #{inspect(reason)}")
        []

      error ->
        Logger.error("Unexpected error processing changelog #{changelog_path}: #{inspect(error)}")
        []
    end
  end
end
