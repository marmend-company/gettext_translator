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

  def run(%{language_code: code, files: files}, provider) do
    Logger.info("#{code}/#{lc_messages()} - starting processing")

    files
    |> Enum.map(&translate_file(provider, code, &1))
    |> Enum.map(fn {_status, count} -> count end)
    |> Enum.sum()
  end

  defp translate_file(provider, code, file_path) do
    with {:ok, file} <- PO.parse_file(file_path),
         {count, messages} <- process_messages(file, provider, code, file_path),
         updated_file = %{file | messages: messages},
         :ok <- File.write(file_path, PO.compose(updated_file)) do
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
        {0, file.messages}

      _ ->
        {to_be_translated,
         translate_messages(empty_messages, provider, code, to_be_translated) ++
           rest_messages}
    end
  end

  defp translation_empty?(%Message.Singular{:msgstr => val}) do
    empty_string?(Enum.join(val, " "))
  end

  defp translation_empty?(%Message.Plural{:msgstr => %{0 => val1, 1 => val2}}) do
    empty_string?(Enum.join(val1, " ")) || empty_string?(Enum.join(val2, " "))
  end

  defp log_translation_status(file_path, count, code),
    do:
      Logger.info(
        "Translation file `#{file_path}` has #{count} entries that need to be translated to `#{code}`"
      )

  defp translate_messages(messages, provider, code, count),
    do:
      Enum.with_index(messages)
      |> Enum.map(fn {message, index} ->
        translate_message(provider, code, message, index + 1, count)
      end)

  defp translate_message(
         provider,
         code,
         %Message.Singular{msgid: val} = message,
         index,
         count
       ) do
    Logger.info("#{index}/#{count} - translating message `#{val}` to `#{code}` ")

    {:ok, translated_value} = translate_text(provider, val, code)

    %{message | msgstr: [translated_value.last_message.content]}
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

    %{
      message
      | msgstr: %{
          0 => [translated_singular.last_message.content],
          1 => [translated_plural.last_message.content]
        }
    }
  end

  defp translate_text(provider, text, code) do
    LLM.translate(provider, %{
      message: text,
      language_code: code
    })
  end
end
