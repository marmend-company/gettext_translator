defmodule GettextTranslator.Store.Changelog do
  @moduledoc """
  Service for managing changelog operations.
  Maintains status history of translations with a simple 1:1 mapping.
  """

  require Logger
  alias GettextTranslator.Store
  alias GettextTranslator.Util.{Helper, PathHelper}

  @doc """
  Loads changelog files for translations.
  Maps each translation to its corresponding status record.
  """
  def load_changelog_files(folders, app) do
    Logger.info("Loading changelog files")

    result =
      Enum.flat_map(folders, fn %{language_code: code, files: files} ->
        Enum.flat_map(files, fn file_path ->
          changelog_path = PathHelper.changelog_path_for_po(file_path, app)
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
  Match changelog entries with translations using message_id as the key.
  """
  def match_changelog_with_translations do
    # Group changelog entries by message_id for easy lookup
    entries_by_key =
      Store.list_changelogs()
      |> Enum.group_by(fn entry ->
        {entry.source_file, Enum.join(entry.original, "")}
      end)

    # Process all translations in the store
    Store.list_translations()
    |> Enum.each(fn translation ->
      key = {translation.file_path, translation.message_id}

      # Find matching changelog entry
      case Map.get(entries_by_key, key) do
        # No changelog entry exists - translation status is unknown
        nil -> :ok
        entries -> update_translation_with_changelog(translation, entries)
      end
    end)
  end

  @doc """
  Updates a changelog entry when a translation is modified from the UI.
  """
  def update_for_modified_translation(translation, params) do
    # Create a unique entry ID if not exists
    entry_id = get_or_create_entry_id(translation)

    # Build the changelog entry
    original = get_original_from_translation(translation)
    translated = build_translated_text(translation, params)

    changelog_entry = %{
      id: entry_id,
      code: translation.language_code,
      # UI modification always sets MODIFIED status
      status: "MODIFIED",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      original: original,
      translated: translated,
      source_file: translation.file_path,
      # Flag for persistence
      modified: true
    }

    # Store in changelog table
    Store.insert_changelog(entry_id, changelog_entry)

    # Return updated translation with changelog info
    Map.merge(translation, %{
      changelog_id: entry_id,
      changelog_status: "MODIFIED",
      changelog_timestamp: changelog_entry.timestamp
    })
  end

  @doc """
  Approves a translation in the changelog.
  """
  def approve_translation(translation) do
    if Map.has_key?(translation, :changelog_id) and not is_nil(translation.changelog_id) do
      case Store.get_changelog(translation.changelog_id) do
        {:ok, entry} ->
          # Update changelog entry to APPROVED
          updated_entry = %{entry | status: "APPROVED", modified: true}
          Store.insert_changelog(translation.changelog_id, updated_entry)

          # Return updated translation with APPROVED status
          Map.put(translation, :changelog_status, "APPROVED")

        _ ->
          # Entry doesn't exist but should
          create_new_changelog_entry(translation, "APPROVED")
      end
    else
      # No existing changelog entry - create a new one
      create_new_changelog_entry(translation, "APPROVED")
    end
  end

  @doc """
  Creates a new changelog entry for a new translation or when one doesn't exist.
  """
  def create_new_changelog_entry(translation, status \\ "NEW") do
    # Create a unique entry ID
    entry_id = get_or_create_entry_id(translation)

    # Build the changelog entry
    original = get_original_from_translation(translation)
    translated = get_translated_from_translation(translation)

    changelog_entry = %{
      id: entry_id,
      code: translation.language_code,
      status: status,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      original: original,
      translated: translated,
      source_file: translation.file_path,
      # Flag for persistence
      modified: true
    }

    # Store in changelog table
    Store.insert_changelog(entry_id, changelog_entry)

    # Return updated translation with changelog info
    Map.merge(translation, %{
      changelog_id: entry_id,
      changelog_status: status,
      changelog_timestamp: changelog_entry.timestamp
    })
  end

  @doc """
  Saves all modified changelog entries to disk, while preserving existing entries.
  Converts MODIFIED status to APPROVED during persistence.
  """
  def save_to_files do
    # Get modified entries grouped by file
    modified_entries_by_file =
      Store.list_changelogs()
      |> Enum.filter(fn entry -> Map.get(entry, :modified, false) end)
      |> Enum.group_by(& &1.source_file)

    if Enum.empty?(modified_entries_by_file) do
      Logger.info("No modified changelog entries to save")
      {:ok, []}
    else
      app = Helper.get_config(:application)
      PathHelper.ensure_changelog_dir(app)

      results =
        Enum.map(modified_entries_by_file, fn {file_path, modified_entries} ->
          # This now includes loading existing entries first
          save_changelog_file_with_merge(file_path, modified_entries, app)
        end)

      {:ok, results}
    end
  end

  # Private functions

  defp save_changelog_file_with_merge(file_path, modified_entries, app) do
    # Extract language code from the first entry
    language_code = List.first(modified_entries).code
    domain = Helper.extract_domain_from_path(file_path)

    # Construct the changelog path
    changelog_path =
      Path.join(
        PathHelper.translation_changelog_dir(app),
        "#{language_code}_#{domain}_changelog.json"
      )

    # 1. Load existing changelog file if it exists
    existing_content = load_existing_changelog(changelog_path, language_code, file_path)

    # 2. Get existing translations map or create a new one
    existing_translations = Map.get(existing_content, "translations", %{})

    # 3. Process modified entries and prepare for saving
    modified_translations =
      Enum.reduce(modified_entries, %{}, fn entry, acc ->
        # Get the original message ID to use as key
        original_key = Enum.join(entry.original, "")

        # Determine status - convert MODIFIED to approved
        status =
          case entry.status do
            "MODIFIED" -> "approved"
            "APPROVED" -> "approved"
            "NEW" -> "pending_review"
            _ -> "pending_review"
          end

        # Create entry for the map
        Map.put(acc, original_key, %{
          "status" => status,
          "text" => entry.translated,
          "last_updated" => entry.timestamp
        })
      end)

    # 4. Merge existing with modified translations, giving priority to modified ones
    # This preserves entries that weren't modified in this session
    merged_translations = Map.merge(existing_translations, modified_translations)

    # 5. Prepare the final changelog structure
    updated_content = %{
      "language" => language_code,
      "source_file" => file_path,
      "translations" => merged_translations
    }

    # 6. Save to file
    case File.write(changelog_path, Jason.encode!(updated_content, pretty: true)) do
      :ok ->
        # 7. Mark entries as not modified after successful save
        Enum.each(modified_entries, fn entry ->
          Store.insert_changelog(entry.id, Map.put(entry, :modified, false))
        end)

        {:ok, changelog_path}

      {:error, reason} ->
        Logger.error("Failed to write changelog file #{changelog_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp load_existing_changelog(changelog_path, language_code, file_path) do
    case File.read(changelog_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, content = %{"translations" => _}} ->
            # Content already has the correct structure
            content

          {:ok, %{"entries" => entries}} when is_list(entries) ->
            # Convert from old structure to new structure
            translations =
              Enum.reduce(entries, %{}, fn entry, acc ->
                Map.put(acc, entry["original"], %{
                  "status" => convert_status(entry["status"]),
                  "text" => entry["translated"],
                  "last_updated" => entry["timestamp"]
                })
              end)

            %{
              "language" => language_code,
              "source_file" => file_path,
              "translations" => translations
            }

          _ ->
            # Invalid format, return empty structure
            %{
              "language" => language_code,
              "source_file" => file_path,
              "translations" => %{}
            }
        end

      {:error, :enoent} ->
        # File doesn't exist yet
        %{
          "language" => language_code,
          "source_file" => file_path,
          "translations" => %{}
        }

      {:error, reason} ->
        Logger.error("Error reading changelog #{changelog_path}: #{inspect(reason)}")

        %{
          "language" => language_code,
          "source_file" => file_path,
          "translations" => %{}
        }
    end
  end

  defp convert_status(status) do
    case status do
      "MODIFIED" -> "approved"
      "APPROVED" -> "approved"
      "NEW" -> "pending_review"
      _ -> "pending_review"
    end
  end

  defp process_changelog_file(changelog_path, source_file, language_code) do
    case File.read(changelog_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, %{"translations" => translations}} when is_map(translations) ->
            # Process new format with translations map
            Enum.map(translations, fn {original, entry} ->
              process_changelog_translation(original, entry, source_file, language_code)
            end)

          {:ok, %{"entries" => entries}} when is_list(entries) ->
            # Process old format with entries array
            Enum.map(entries, fn entry ->
              process_changelog_entry(entry, source_file, language_code)
            end)

          _ ->
            Logger.error("Invalid changelog format: #{changelog_path}")
            []
        end

      {:error, :enoent} ->
        Logger.debug("No changelog file found at #{changelog_path}")
        []

      {:error, reason} ->
        Logger.error("Error reading changelog #{changelog_path}: #{inspect(reason)}")
        []
    end
  end

  defp process_changelog_translation(original, entry, source_file, language_code) do
    # Create a unique ID for this entry
    entry_id =
      :crypto.hash(:sha256, "#{source_file}|#{original}|#{entry["last_updated"]}")
      |> Base.encode16()

    # Convert status back to uppercase format for internal use
    status =
      case entry["status"] do
        "approved" -> "APPROVED"
        "pending_review" -> "NEW"
        _ -> "NEW"
      end

    changelog_entry = %{
      id: entry_id,
      code: language_code,
      status: status,
      timestamp: entry["last_updated"],
      original: [original],
      translated: entry["text"],
      source_file: source_file,
      # Not modified until changed
      modified: false
    }

    # Store in changelog table
    Store.insert_changelog(entry_id, changelog_entry)

    changelog_entry
  end

  defp process_changelog_entry(entry, source_file, language_code) do
    # Create a unique ID for this entry
    entry_id =
      :crypto.hash(:sha256, "#{source_file}|#{entry["original"]}|#{entry["timestamp"]}")
      |> Base.encode16()

    changelog_entry = %{
      id: entry_id,
      code: language_code,
      status: entry["status"],
      timestamp: entry["timestamp"],
      original: [entry["original"]],
      translated: entry["translated"],
      source_file: source_file,
      # Not modified until changed
      modified: false
    }

    # Store in changelog table
    Store.insert_changelog(entry_id, changelog_entry)

    changelog_entry
  end

  defp update_translation_with_changelog(translation, entries) do
    # Get the newest entry (sort by timestamp)
    newest_entry =
      Enum.sort_by(entries, &parse_timestamp/1, {:desc, DateTime})
      |> List.first()

    # Update translation with changelog info
    updated =
      Map.merge(translation, %{
        changelog_id: newest_entry.id,
        changelog_status: newest_entry.status,
        changelog_timestamp: newest_entry.timestamp
      })

    Store.insert_translation(translation.id, updated)
  end

  defp parse_timestamp(entry) do
    case entry.timestamp do
      timestamp when is_binary(timestamp) ->
        case DateTime.from_iso8601(timestamp) do
          {:ok, dt, _} -> dt
          _ -> ~U[1970-01-01 00:00:00Z]
        end

      _ ->
        ~U[1970-01-01 00:00:00Z]
    end
  end

  defp get_or_create_entry_id(translation) do
    if Map.has_key?(translation, :changelog_id) and not is_nil(translation.changelog_id) do
      translation.changelog_id
    else
      :crypto.hash(
        :sha256,
        "#{translation.file_path}|#{translation.message_id}|#{DateTime.utc_now()}"
      )
      |> Base.encode16()
    end
  end

  defp get_original_from_translation(translation) do
    case translation.type do
      :singular -> [translation.message_id]
      :plural -> [translation.message_id, translation.plural_id]
    end
  end

  defp get_translated_from_translation(translation) do
    case translation.type do
      :singular -> translation.translation
      :plural -> "#{translation.translation} | #{translation.plural_translation}"
    end
  end

  defp build_translated_text(translation, params) do
    case translation.type do
      :plural ->
        plural_text = params["plural_translation"] || ""
        "#{params["translation"]} | #{plural_text}"

      _ ->
        params["translation"]
    end
  end
end
