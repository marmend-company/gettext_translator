defmodule GettextTranslator.Util.PathHelperTest do
  use ExUnit.Case

  alias GettextTranslator.Util.PathHelper

  describe "path manipulation" do
    test "extracts language code from PO path" do
      # Standard case
      assert "uk" == PathHelper.extract_language_code("priv/gettext/uk/LC_MESSAGES/default.po")

      # Different language
      assert "de" == PathHelper.extract_language_code("priv/gettext/de/LC_MESSAGES/emails.po")

      # Path with different structure
      assert "uk" ==
               PathHelper.extract_language_code("/absolute/path/to/gettext/uk/whatever/file.po")

      # Fallback case
      assert "unknown" == PathHelper.extract_language_code("some/invalid/path.po")
    end

    test "extracts domain from PO path" do
      # Standard domains
      assert "default" == PathHelper.extract_domain("priv/gettext/uk/LC_MESSAGES/default.po")
      assert "emails" == PathHelper.extract_domain("priv/gettext/uk/LC_MESSAGES/emails.po")
      assert "errors" == PathHelper.extract_domain("priv/gettext/de/LC_MESSAGES/errors.po")

      # Handle paths with directories
      assert "custom" == PathHelper.extract_domain("/any/path/to/custom.po")
    end

    test "generates changelog path from PO path" do
      # Standard cases
      assert "priv/translation_changelog/uk_default_changelog.json" ==
               PathHelper.changelog_path_for_po("priv/gettext/uk/LC_MESSAGES/default.po")

      assert "priv/translation_changelog/de_emails_changelog.json" ==
               PathHelper.changelog_path_for_po("priv/gettext/de/LC_MESSAGES/emails.po")

      # Handle different path structures
      assert "priv/translation_changelog/fr_errors_changelog.json" ==
               PathHelper.changelog_path_for_po(
                 "/absolute/path/to/gettext/fr/LC_MESSAGES/errors.po"
               )
    end

    test "gets PO path from changelog path" do
      # Standard cases
      assert "priv/gettext/uk/LC_MESSAGES/default.po" ==
               PathHelper.po_path_for_changelog(
                 "priv/translation_changelog/uk_default_changelog.json"
               )

      assert "priv/gettext/de/LC_MESSAGES/emails.po" ==
               PathHelper.po_path_for_changelog(
                 "priv/translation_changelog/de_emails_changelog.json"
               )

      # Handle different path structures
      assert "priv/gettext/fr/LC_MESSAGES/errors.po" ==
               PathHelper.po_path_for_changelog("/any/path/to/fr_errors_changelog.json")

      # Invalid format should return nil
      assert nil == PathHelper.po_path_for_changelog("invalid_format.json")
    end

    test "ensures changelog directory exists" do
      # Clean up any existing directory
      File.rm_rf("priv/translation_changelog")

      # Ensure directory exists
      assert :ok == PathHelper.ensure_changelog_dir()

      # Check if directory was created
      assert File.dir?("priv/translation_changelog")

      # Clean up
      File.rm_rf("priv/translation_changelog")
    end
  end
end
