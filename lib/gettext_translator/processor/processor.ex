defmodule GettextTranslator.Processor do
  @moduledoc """
  Documentation for `GettextTranslator.Processor`.
  Here we process parsing the PO files and extracting the messages.
  """
  require Logger
  import GettextTranslator.Util.Helper
  alias Expo.Message
  alias Expo.PO
  alias GettextTranslator.Processor.LLM
  alias GettextTranslator.Util.PathHelper

  def run(%{language_code: code, files: files}, provider) do
    Logger.info("#{code}/#{lc_messages()} - starting processing")

    files
    |> Enum.map(&translate_file(provider, code, &1))
    |> Enum.map(fn {_status, count} -> count end)
    |> Enum.sum()
  end

  defp translate_file(provider, code, file_path) do
    with {:ok, file} <- PO.parse_file(file_path),
         {count, messages, translations} <- process_messages(file, provider, code, file_path),
         updated_file = %{file | messages: messages},
         :ok <- File.write(file_path, PO.compose(updated_file)),
         :ok <- append_to_changelog(code, file_path, translations) do
      {:ok, count}
    end
  end

  defp process_messages(file, provider, code, file_path) do
    {to_be_translated, empty_messages, rest_messages} =
      Enum.reduce(file.messages, {0, [], []}, fn message, {count, matched, not_matched} ->
        if translation_empty?(message) do
          {count + 1, [message | matched], not_matched}
        else
          {count, matched, [message | not_matched]}
        end
      end)

    log_translation_status(file_path, to_be_translated, code)

    case to_be_translated do
      0 ->
        {0, file.messages, []}

      _ ->
        {translated_messages, changelog_entries} =
          translate_messages(empty_messages, provider, code, to_be_translated)

        {to_be_translated, translated_messages ++ rest_messages, changelog_entries}
    end
  end

  defp translation_empty?(%Message.Singular{:msgstr => val}) do
    empty_string?(Enum.join(val, " "))
  end

  defp translation_empty?(%Message.Plural{:msgstr => %{0 => val1, 1 => val2}}) do
    empty_string?(Enum.join(val1, " ")) || empty_string?(Enum.join(val2, " "))
  end

  defp translation_empty?(%Message.Plural{:msgstr => msgstr}) do
    msgstr
    |> Map.values()
    |> Enum.any?(fn val -> empty_string?(Enum.join(val, " ")) end)
  end

  defp log_translation_status(file_path, count, code),
    do:
      Logger.info(
        "Translation file `#{file_path}` has #{count} entries that need to be translated to `#{code}`"
      )

  defp translate_messages(messages, provider, code, count) do
    Enum.with_index(messages)
    |> Enum.map_reduce([], fn {message, index}, acc ->
      {translated_message, changelog_entry} =
        translate_message(provider, code, message, index + 1, count)

      {translated_message, [changelog_entry | acc]}
    end)
  end

  defp translate_message(
         provider,
         code,
         %Message.Singular{msgid: val} = message,
         index,
         count
       ) do
    Logger.info("#{index}/#{count} - translating message `#{val}` to `#{code}` ")

    {:ok, translated_value} = translate_text(provider, val, code)
    translated_text = translated_value.last_message.content

    changelog_entry = %{
      type: :singular,
      original: val,
      translated: translated_text,
      code: code,
      status: "NEW",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    {%{message | msgstr: [translated_text]}, changelog_entry}
  end

  defp translate_message(
         provider,
         code,
         %Message.Plural{
           msgid: [value_singular],
           msgid_plural: [value_plural]
         } = message,
         index,
         count
       ) do
    Logger.info(
      "#{index}/#{count} - translating plural message `#{value_singular}` / `#{value_plural}` to `#{code}` "
    )

    {:ok, translated_singular} = translate_text(provider, value_singular, code)
    {:ok, translated_plural} = translate_text(provider, value_plural, code)

    singular_text = translated_singular.last_message.content
    plural_text = translated_plural.last_message.content

    changelog_entry = %{
      type: :plural,
      original_singular: value_singular,
      original_plural: value_plural,
      translated_singular: singular_text,
      translated_plural: plural_text,
      code: code,
      status: "NEW",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    {
      %{
        message
        | msgstr: %{
            0 => [singular_text],
            1 => [plural_text]
          }
      },
      changelog_entry
    }
  end

  defp translate_text(provider, text, code) do
    LLM.translate(provider, %{
      message: text,
      language_code: code
    })
  end

  defp append_to_changelog(_, _, []) do
    :ok
  end

  defp append_to_changelog(code, file_path, translations) do
    # Get the application that is using the processor
    app = GettextTranslator.application()

    # Use the PathHelper to get the proper path and ensure the directory exists
    PathHelper.ensure_changelog_dir(app)

    # Use the PathHelper to get the changelog path
    changelog_file = PathHelper.changelog_path_for_po(file_path, app)

    # Load existing content or create new structure
    existing_content =
      if File.exists?(changelog_file) do
        case File.read!(changelog_file) |> Jason.decode() do
          {:ok, content} -> content
          {:error, _} -> %{"language" => code, "source_file" => file_path, "translations" => %{}}
        end
      else
        %{"language" => code, "source_file" => file_path, "translations" => %{}}
      end

    # Get existing translations map or create a new one
    existing_translations = Map.get(existing_content, "translations", %{})

    # Format and merge new translations
    updated_translations =
      Enum.reduce(translations, existing_translations, fn translation, acc ->
        # Extract the original message ID to use as the key
        message_id =
          case translation do
            %{type: :singular, original: original} when is_list(original) ->
              Enum.join(original, "")

            %{type: :singular, original: original} when is_binary(original) ->
              original

            %{type: :plural, original_singular: singular} ->
              singular

            %{original: original} when is_list(original) ->
              Enum.join(original, "")

            %{original: original} when is_binary(original) ->
              original

            _ ->
              ""
          end

        # Extract the translated text
        translated_text =
          case translation do
            %{type: :singular, translated: text} ->
              text

            %{type: :plural, translated_singular: singular, translated_plural: plural} ->
              "#{singular} | #{plural}"

            %{translated: text} when is_binary(text) ->
              text

            _ ->
              ""
          end

        # Skip if message_id is empty
        if message_id == "" do
          acc
        else
          # Only add if not already exists or if newer
          case Map.get(acc, message_id) do
            nil ->
              # No existing entry, add new one
              Map.put(acc, message_id, %{
                "status" => "pending_review",
                "text" => translated_text,
                "last_updated" => translation.timestamp
              })

            existing ->
              # If existing entry has timestamp, compare it
              existing_timestamp = Map.get(existing, "last_updated", "1970-01-01T00:00:00Z")

              if translation.timestamp > existing_timestamp do
                # New translation is newer, update it
                Map.put(acc, message_id, %{
                  "status" => "pending_review",
                  "text" => translated_text,
                  "last_updated" => translation.timestamp
                })
              else
                # Keep existing entry
                acc
              end
          end
        end
      end)

    # Update the content with merged translations
    updated_content = %{
      "language" => code,
      "source_file" => file_path,
      "translations" => updated_translations
    }

    # Write the updated changelog
    File.write!(changelog_file, Jason.encode!(updated_content, pretty: true))
  end
end
