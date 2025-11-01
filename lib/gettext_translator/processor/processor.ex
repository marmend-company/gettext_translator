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
  alias LangChain.Message.ContentPart

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

  defp translation_empty?(%Message.Singular{msgstr: val}) do
    empty_string?(Enum.join(val, " "))
  end

  defp translation_empty?(%Message.Plural{msgstr: %{0 => val1, 1 => val2}}) do
    empty_string?(Enum.join(val1, " ")) || empty_string?(Enum.join(val2, " "))
  end

  defp translation_empty?(%Message.Plural{msgstr: msgstr}) do
    msgstr
    |> Map.values()
    |> Enum.any?(fn val -> empty_string?(Enum.join(val, " ")) end)
  end

  defp log_translation_status(file_path, count, code) do
    Logger.info(
      "Translation file `#{file_path}` has #{count} entries that need to be translated to `#{code}`"
    )
  end

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

    translated_text =
      translated_value.last_message.content
      |> ensure_string()

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

    with {:ok, translated_singular} <- translate_text(provider, value_singular, code),
         {:ok, translated_plural} <- translate_text(provider, value_plural, code) do
      singular_text =
        translated_singular.last_message.content
        |> ensure_string()

      plural_text =
        translated_plural.last_message.content
        |> ensure_string()

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
    else
      {:error, reason} ->
        Logger.error("Failed to translate plural message: #{inspect(reason)}")
        fallback_singular = "[TRANSLATION_FAILED]"
        fallback_plural = "[TRANSLATION_FAILED]"

        changelog_entry = %{
          type: :plural,
          original_singular: value_singular,
          original_plural: value_plural,
          translated_singular: fallback_singular,
          translated_plural: fallback_plural,
          code: code,
          status: "ERROR",
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        }

        {
          %{
            message
            | msgstr: %{
                0 => [fallback_singular],
                1 => [fallback_plural]
              }
          },
          changelog_entry
        }
    end
  end

  defp translate_text(provider, text, code) do
    LLM.translate(provider, %{
      message: text,
      language_code: code
    })
  end

  defp ensure_string(nil), do: ""
  defp ensure_string(value) when is_binary(value), do: value
  defp ensure_string(value) when is_list(value), do: ContentPart.parts_to_string(value) || ""
  defp ensure_string(value), do: to_string(value)

  defp append_to_changelog(_, _, []), do: :ok

  defp append_to_changelog(code, file_path, translations) do
    app = GettextTranslator.application()
    PathHelper.ensure_changelog_dir(app)
    changelog_file = PathHelper.changelog_path_for_po(file_path, app)

    existing_content =
      if File.exists?(changelog_file) do
        case File.read!(changelog_file) |> Jason.decode() do
          {:ok, content} -> content
          {:error, _} -> base_changelog_structure(code, file_path)
        end
      else
        base_changelog_structure(code, file_path)
      end

    existing_translations = Map.get(existing_content, "translations", %{})
    updated_translations = merge_translations(translations, existing_translations)

    updated_content = %{
      "language" => code,
      "source_file" => file_path,
      "translations" => updated_translations
    }

    File.write!(changelog_file, Jason.encode!(updated_content, pretty: true))
  end

  defp base_changelog_structure(code, file_path) do
    %{"language" => code, "source_file" => file_path, "translations" => %{}}
  end

  defp merge_translations(new_translations, existing_translations) do
    Enum.reduce(new_translations, existing_translations, fn translation, acc ->
      message_id = extract_message_id(translation)
      translated_text = extract_translated_text(translation)

      if message_id == "" do
        acc
      else
        case Map.get(acc, message_id) do
          nil ->
            Map.put(acc, message_id, %{
              "status" => "pending_review",
              "text" => translated_text,
              "last_updated" => translation.timestamp
            })

          existing ->
            existing_timestamp = Map.get(existing, "last_updated", "1970-01-01T00:00:00Z")

            if translation.timestamp > existing_timestamp do
              Map.put(acc, message_id, %{
                "status" => "pending_review",
                "text" => translated_text,
                "last_updated" => translation.timestamp
              })
            else
              acc
            end
        end
      end
    end)
  end

  defp extract_message_id(%{type: :singular, original: original}) when is_list(original) do
    Enum.join(original, "")
  end

  defp extract_message_id(%{type: :singular, original: original}) when is_binary(original) do
    original
  end

  defp extract_message_id(%{type: :plural, original_singular: singular}), do: singular

  defp extract_message_id(%{original: original}) when is_list(original) do
    Enum.join(original, "")
  end

  defp extract_message_id(%{original: original}) when is_binary(original), do: original
  defp extract_message_id(_), do: ""

  defp extract_translated_text(%{type: :singular, translated: text}), do: text

  defp extract_translated_text(%{
         type: :plural,
         translated_singular: singular,
         translated_plural: plural
       }) do
    "#{singular} | #{plural}"
  end

  defp extract_translated_text(%{translated: text}) when is_binary(text), do: text
  defp extract_translated_text(_), do: ""
end
