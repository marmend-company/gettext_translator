defmodule GettextTranslator.Util.PathHelper do
  @moduledoc """
  Helper functions for working with PO and changelog file paths.
  """

  require Logger

  @doc """
  Gets the changelog path corresponding to a PO file.

  ## Examples

      iex> changelog_path_for_po("priv/gettext/uk/LC_MESSAGES/default.po", :my_app)
      "/path/to/my_app/priv/translation_changelog/uk_default_changelog.json"
  """
  def changelog_path_for_po(po_path, app \\ nil) do
    language_code = extract_language_code(po_path)
    domain = extract_domain(po_path)

    relative_path = "priv/translation_changelog/#{language_code}_#{domain}_changelog.json"

    if app do
      Application.app_dir(app, relative_path)
    else
      relative_path
    end
  end

  @doc """
  Extracts the language code from a PO file path.

  ## Examples

      iex> extract_language_code("priv/gettext/uk/LC_MESSAGES/default.po")
      "uk"
  """
  def extract_language_code(po_path) do
    case Regex.run(~r|/gettext/([^/]+)/|, po_path) do
      [_, language_code] ->
        language_code

      _ ->
        # Fallback to filename-based extraction
        Logger.warning("Could not extract language code from path: #{po_path}")
        "unknown"
    end
  end

  @doc """
  Extracts the domain from a PO file path.

  ## Examples

      iex> extract_domain("priv/gettext/uk/LC_MESSAGES/default.po")
      "default"
  """
  def extract_domain(po_path) do
    po_path
    |> Path.basename()
    |> String.replace_suffix(".po", "")
  end

  @doc """
  Gets the source PO file path from a changelog path.

  ## Examples

      iex> po_path_for_changelog("priv/translation_changelog/uk_default_changelog.json", :my_app)
      "/path/to/my_app/priv/gettext/uk/LC_MESSAGES/default.po"
  """
  def po_path_for_changelog(changelog_path, app \\ nil) do
    # Extract language and domain from the changelog path
    basename = Path.basename(changelog_path)

    case Regex.run(~r|^([^_]+)_([^_]+)_changelog\.json$|, basename) do
      [_, language_code, domain] ->
        relative_path = "priv/gettext/#{language_code}/LC_MESSAGES/#{domain}.po"

        if app do
          Application.app_dir(app, relative_path)
        else
          relative_path
        end

      _ ->
        Logger.warning(
          "Could not extract language and domain from changelog path: #{changelog_path}"
        )

        nil
    end
  end

  @doc """
  Ensures the translation_changelog directory exists.

  ## Examples

      iex> ensure_changelog_dir(:my_app)
      :ok
  """
  def ensure_changelog_dir(app \\ nil) do
    changelog_dir =
      if app do
        Application.app_dir(app, "priv/translation_changelog")
      else
        "priv/translation_changelog"
      end

    case File.mkdir_p(changelog_dir) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to create directory #{changelog_dir}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Returns the appropriate gettext directory path.

  ## Examples

      iex> gettext_dir(:my_app)
      "/path/to/my_app/priv/gettext"
  """
  def gettext_dir(app \\ nil) do
    if app do
      Application.app_dir(app, "priv/gettext")
    else
      "priv/gettext"
    end
  end

  @doc """
  Returns the appropriate translation changelog directory path.

  ## Examples

      iex> translation_changelog_dir(:my_app)
      "/path/to/my_app/priv/translation_changelog"
  """
  def translation_changelog_dir(app \\ nil) do
    if app do
      Application.app_dir(app, "priv/translation_changelog")
    else
      "priv/translation_changelog"
    end
  end
end
