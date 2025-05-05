defmodule GettextTranslator.Util.PoHelper do
  # Helper function to update a PO message with new translation
  def update_po_message(%Expo.Message.Singular{} = msg, translation) do
    %{msg | msgstr: [translation.translation]}
  end

  def update_po_message(%Expo.Message.Plural{} = msg, translation) do
    # Base msgstr with the first two forms
    initial_msgstr = %{
      0 => [translation.translation],
      1 => [translation.plural_translation]
    }

    # Add third form for languages that need it (like Ukrainian)
    # The language_code should be available in the translation struct
    msgstr =
      case translation.language_code do
        "uk" ->
          # For Ukrainian, we need the third form
          third_form = Map.get(translation, :plural_translation_2, translation.plural_translation)
          Map.put(initial_msgstr, 2, [third_form])

        # Add other languages that need 3+ forms here
        "ru" ->
          Map.put(initial_msgstr, 2, [translation.plural_translation])

        "pl" ->
          Map.put(initial_msgstr, 2, [translation.plural_translation])

        # For languages with just 2 forms
        _ ->
          initial_msgstr
      end

    %{msg | msgstr: msgstr}
  end

  # Helper function to get the message ID from a PO message
  def get_message_id(%Expo.Message.Singular{msgid: msgid}), do: Enum.join(msgid, "")
  def get_message_id(%Expo.Message.Plural{msgid: msgid}), do: Enum.join(msgid, "")
end
