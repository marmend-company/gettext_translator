defmodule GettextTranslator.Util.PoHelper do
  @moduledoc """
  Helpers for updating `Expo.Message` structs with translation entries.
  """

  @doc """
  Updates a PO message with a new translation.

  For plural messages the PO file itself defines how many plural forms the
  language uses (one `msgstr[n]` per form), so only the forms tracked by the
  translation entry (`msgstr[0]` and `msgstr[1]`) are replaced. Higher forms
  (`msgstr[2]`+) already present in the file are preserved as-is; they are only
  filled with the generic plural translation when still empty, so newly
  translated messages don't end up with blank forms.

  An explicit `:plural_translation_2` key on the translation entry overrides
  `msgstr[2]` when present and non-empty.
  """
  def update_po_message(%Expo.Message.Singular{} = msg, translation) do
    %{msg | msgstr: [translation.translation]}
  end

  def update_po_message(%Expo.Message.Plural{} = msg, translation) do
    msgstr =
      Map.new(msg.msgstr, fn
        {0, _} -> {0, [translation.translation]}
        {1, _} -> {1, [translation.plural_translation]}
        {index, existing} -> {index, higher_plural_form(translation, index, existing)}
      end)

    %{msg | msgstr: msgstr}
  end

  # Helper function to get the message ID from a PO message
  def get_message_id(%Expo.Message.Singular{msgid: msgid}), do: Enum.join(msgid, "")
  def get_message_id(%Expo.Message.Plural{msgid: msgid}), do: Enum.join(msgid, "")

  defp higher_plural_form(translation, 2, existing) do
    explicit = Map.get(translation, :plural_translation_2)

    cond do
      is_binary(explicit) and explicit != "" -> [explicit]
      empty_form?(existing) -> [translation.plural_translation]
      true -> existing
    end
  end

  defp higher_plural_form(translation, _index, existing) do
    if empty_form?(existing), do: [translation.plural_translation], else: existing
  end

  defp empty_form?(existing), do: Enum.join(existing, "") == ""
end
