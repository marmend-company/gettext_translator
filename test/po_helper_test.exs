defmodule GettextTranslator.Util.PoHelperTest do
  use ExUnit.Case, async: true

  alias Expo.Message
  alias GettextTranslator.Util.PoHelper

  defp plural_message(msgstr) do
    %Message.Plural{
      msgid: ["%{count} credit"],
      msgid_plural: ["%{count} credits"],
      msgstr: msgstr
    }
  end

  defp uk_translation(overrides \\ %{}) do
    Map.merge(
      %{
        translation: "%{count} кредит",
        plural_translation: "%{count} кредити",
        language_code: "uk"
      },
      overrides
    )
  end

  describe "update_po_message/2 with singular messages" do
    test "replaces msgstr with the translation" do
      msg = %Message.Singular{msgid: ["Hello"], msgstr: ["Привіт"]}
      updated = PoHelper.update_po_message(msg, %{translation: "Вітаю"})

      assert updated.msgstr == ["Вітаю"]
    end
  end

  describe "update_po_message/2 with plural messages" do
    test "preserves an existing non-empty third plural form" do
      msg =
        plural_message(%{
          0 => ["%{count} кредит"],
          1 => ["%{count} кредити"],
          2 => ["%{count} кредитів"]
        })

      updated = PoHelper.update_po_message(msg, uk_translation())

      assert updated.msgstr[0] == ["%{count} кредит"]
      assert updated.msgstr[1] == ["%{count} кредити"]
      assert updated.msgstr[2] == ["%{count} кредитів"]
    end

    test "fills an empty third form with the plural translation as fallback" do
      msg = plural_message(%{0 => [""], 1 => [""], 2 => [""]})

      updated = PoHelper.update_po_message(msg, uk_translation())

      assert updated.msgstr[2] == ["%{count} кредити"]
    end

    test "uses an explicit plural_translation_2 when provided" do
      msg =
        plural_message(%{
          0 => ["%{count} кредит"],
          1 => ["%{count} кредити"],
          2 => ["%{count} кредитів"]
        })

      translation = uk_translation(%{plural_translation_2: "%{count} кредитів!"})
      updated = PoHelper.update_po_message(msg, translation)

      assert updated.msgstr[2] == ["%{count} кредитів!"]
    end

    test "does not add extra forms for two-form languages" do
      msg = plural_message(%{0 => ["%{count} Kredit"], 1 => ["%{count} Kredite"]})

      translation = %{
        translation: "%{count} Kredit",
        plural_translation: "%{count} Kredite",
        language_code: "de"
      }

      updated = PoHelper.update_po_message(msg, translation)

      assert Map.keys(updated.msgstr) == [0, 1]
    end

    test "preserves forms beyond the third (e.g. Arabic-style six forms)" do
      msg =
        plural_message(%{
          0 => ["zero"],
          1 => ["one"],
          2 => ["two"],
          3 => ["few"],
          4 => ["many"],
          5 => ["other"]
        })

      translation = %{
        translation: "ZERO",
        plural_translation: "ONE",
        language_code: "ar"
      }

      updated = PoHelper.update_po_message(msg, translation)

      assert updated.msgstr[0] == ["ZERO"]
      assert updated.msgstr[1] == ["ONE"]
      assert updated.msgstr[2] == ["two"]
      assert updated.msgstr[3] == ["few"]
      assert updated.msgstr[4] == ["many"]
      assert updated.msgstr[5] == ["other"]
    end
  end
end
