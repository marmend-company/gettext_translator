defmodule GettextTranslator.StoreTest do
  use ExUnit.Case

  alias GettextTranslator.Store
  alias GettextTranslator.Store.Changelog
  alias GettextTranslator.Store.Translation
  alias GettextTranslator.Util.PathHelper

  @test_po_path "test/fixtures/gettext/uk/LC_MESSAGES/default.po"
  @test_changelog_path "test/fixtures/translation_changelog/uk_default_changelog.json"

  setup do
    # Create fixture directories
    File.mkdir_p!(Path.dirname(@test_po_path))
    File.mkdir_p!(Path.dirname(@test_changelog_path))

    # Handle Store startup - check if it's already running
    case Process.whereis(Store) do
      nil ->
        # Not running - start it
        start_supervised!(Store)

      _ ->
        # Already running - reset the tables
        :ets.delete_all_objects(:gettext_translator_entries)
        :ets.delete_all_objects(:gettext_translator_changelog)
    end

    # Clean up after tests
    on_exit(fn ->
      File.rm(@test_po_path)
      File.rm(@test_changelog_path)
    end)

    :ok
  end

  describe "path helpers" do
    test "extracts domain from path" do
      assert "default" == PathHelper.extract_domain("priv/gettext/uk/LC_MESSAGES/default.po")
      assert "emails" == PathHelper.extract_domain("priv/gettext/uk/LC_MESSAGES/emails.po")
    end

    test "extracts language code from path" do
      assert "uk" == PathHelper.extract_language_code("priv/gettext/uk/LC_MESSAGES/default.po")
      assert "de" == PathHelper.extract_language_code("priv/gettext/de/LC_MESSAGES/emails.po")
    end

    test "gets changelog path for po file" do
      po_path = "priv/gettext/uk/LC_MESSAGES/default.po"
      expected = "priv/translation_changelog/uk_default_changelog.json"
      assert expected == PathHelper.changelog_path_for_po(po_path)
    end
  end

  describe "translation management" do
    test "creates and lists translations" do
      # Create a test PO file
      po_content = """
      msgid ""
      msgstr ""
      "Language: uk\\n"

      msgid "Hello"
      msgstr "Привіт"

      msgid "Goodbye"
      msgstr "До побачення"
      """

      File.write!(@test_po_path, po_content)

      # Load translations from the test file
      Translation.load_translations(Path.dirname(Path.dirname(Path.dirname(@test_po_path))))

      # Check if translations were loaded
      translations = Store.list_translations()
      assert length(translations) == 2

      # Check specific translations
      hello_translation = Enum.find(translations, &(&1.message_id == "Hello"))
      assert hello_translation != nil
      assert hello_translation.translation == "Привіт"

      goodbye_translation = Enum.find(translations, &(&1.message_id == "Goodbye"))
      assert goodbye_translation != nil
      assert goodbye_translation.translation == "До побачення"
    end

    test "updates translations" do
      # Create a test PO file
      po_content = """
      msgid ""
      msgstr ""
      "Language: uk\\n"

      msgid "Hello"
      msgstr "Привіт"
      """

      File.write!(@test_po_path, po_content)

      # Load translations
      Translation.load_translations(Path.dirname(Path.dirname(Path.dirname(@test_po_path))))

      # Find the translation
      translations = Store.list_translations()
      translation = List.first(translations)

      # Update the translation
      {:ok, updated} =
        Translation.update_translation(translation.id, %{
          translation: "Вітаю",
          status: :modified
        })

      # Check if translation was updated
      assert updated.translation == "Вітаю"
      assert updated.status == :modified

      # Verify the update in the store
      translations = Store.list_translations()
      updated_translation = List.first(translations)
      assert updated_translation.translation == "Вітаю"
    end
  end

  describe "changelog management" do
    test "creates changelog entries" do
      # Create a test PO file
      po_content = """
      msgid ""
      msgstr ""
      "Language: uk\\n"

      msgid "Hello"
      msgstr "Привіт"
      """

      File.write!(@test_po_path, po_content)

      # Load translations
      Translation.load_translations(Path.dirname(Path.dirname(Path.dirname(@test_po_path))))

      # Find the translation
      translations = Store.list_translations()
      translation = List.first(translations)

      # Create a changelog entry
      entry = Changelog.create_new_changelog_entry(translation, "NEW")

      # Check the entry
      assert entry.status == :translated
      assert entry.message_id == "Hello"
      assert entry.translation == "Привіт"

      # Verify translation has changelog info
      translations = Store.list_translations()
      updated_translation = List.first(translations)
      assert updated_translation.id == entry.id
    end
  end
end
