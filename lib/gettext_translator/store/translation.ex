defmodule GettextTranslator.Store.Translation do
  @moduledoc """
  Service for managing translation operations.
  Handles processing PO files and translation operations.
  """
  import GettextTranslator.Util.PoHelper
  require Logger
  alias Expo.{Message, PO}
  alias GettextTranslator.Store
  alias GettextTranslator.Store.Changelog
  alias GettextTranslator.Util.{Helper, Parser, PathHelper}

  @doc """
  Loads all translations from the gettext directories.
  """
  def load_translations(gettext_path) do
    # Reset storage
    Store.reset_translations()
    Store.reset_changelogs()
    Store.reset_approved_counter()
    app = Helper.get_config(:application)

    # Ensure changelog directory exists
    PathHelper.ensure_changelog_dir()

    ignored_languages =
      Application.get_env(:gettext_translator, GettextTranslator)[:ignored_languages] || []

    case Parser.scan(gettext_path) do
      {:ok, folders} ->
        # Filter out ignored languages
        filtered_folders =
          Enum.reject(folders, fn %{language_code: code} -> code in ignored_languages end)

        # Process PO files
        translation_entries = process_translation_folders(filtered_folders)

        # Load changelog files
        Changelog.load_changelog_files(folders, app)

        # Match changelog entries with translations
        Changelog.match_changelog_with_translations()

        {:ok, length(translation_entries)}

      error ->
        error
    end
  end

  @doc """
  Filters translations by the given criteria.
  """
  def filter_translations(criteria) when is_map(criteria) do
    Store.list_translations()
    |> Enum.filter(fn translation ->
      Enum.all?(criteria, fn {key, value} ->
        Map.get(translation, key) == value
      end)
    end)
  end

  @doc """
  Updates a translation with new values.
  """
  def update_translation(id, params) when is_binary(id) and is_map(params) do
    case Store.get_translation(id) do
      {:ok, translation} ->
        # Merge new params with existing translation
        updated = Map.merge(translation, params)

        # Update changelog based on the operation type
        updated =
          case params[:status] do
            :translated ->
              # Translation has been approved
              Changelog.approve_translation(updated)

            :modified ->
              # Translation has been modified from UI
              Changelog.update_for_modified_translation(updated, params)

            _ ->
              # No status change, just update translation
              updated
          end

        # Insert updated translation into ETS
        Store.insert_translation(id, updated)

        {:ok, updated}

      error ->
        error
    end
  end

  @doc """
  Saves all pending translation changes and changelog entries.
  Called when saving work or making a PR.
  """
  def save_all_changes do
    # Save changelog entries to files
    # This converts MODIFIED status to APPROVED during save
    Changelog.save_to_files()
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
        domain = Helper.extract_domain_from_path(file_path)

        po.messages
        |> Enum.map(fn message ->
          translation = create_translation_entry(message, file_path, language_code, domain)
          Store.insert_translation(translation.id, translation)

          # Create a NEW changelog entry for any new translation
          # This is optional and depends on your requirements
          if translation.status == :pending do
            Changelog.create_new_changelog_entry(translation)
          end

          translation
        end)

      _ ->
        []
    end
  end

  def save_translations_to_file(file_path, translations) do
    # Parse existing PO file
    case Expo.PO.parse_file(file_path) do
      {:ok, po} ->
        # Create a map of message_id -> translation for quick lookup
        translations_map = Map.new(translations, fn t -> {t.message_id, t} end)

        # Update each message in the PO file
        updated_messages =
          Enum.map(po.messages, fn msg ->
            msg_id = get_message_id(msg)

            case Map.get(translations_map, msg_id) do
              # No changes for this message
              nil -> msg
              # Update the message with the new translation
              translation -> update_po_message(msg, translation)
            end
          end)

        # Create updated PO file
        updated_po = %{po | messages: updated_messages}

        # Write the file
        case File.write(file_path, Expo.PO.compose(updated_po)) do
          :ok -> {:ok, file_path}
          error -> error
        end

      error ->
        error
    end
  end

  defp create_translation_entry(message, file_path, language_code, domain) do
    id = :crypto.hash(:sha256, "#{file_path}|#{get_message_id(message)}") |> Base.encode16()

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

  # More robust handling for singular translations
  defp get_translation_status(msgstr) when is_list(msgstr) do
    translation = Enum.join(msgstr, "")
    if Helper.empty_string?(translation), do: :pending, else: :translated
  end

  defp get_translation_status(_), do: :pending

  # More robust handling for plural translations
  defp get_plural_translation_status(msgstr) when is_map(msgstr) do
    singular = msgstr[0] || []
    plural = msgstr[1] || []

    singular_str = if is_list(singular), do: Enum.join(singular, ""), else: ""
    plural_str = if is_list(plural), do: Enum.join(plural, ""), else: ""

    if Helper.empty_string?(singular_str) or Helper.empty_string?(plural_str) do
      :pending
    else
      :translated
    end
  end

  defp get_plural_translation_status(_), do: :pending
end
