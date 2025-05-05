defmodule GettextTranslator.Util.MakePullRequest do
  import GettextTranslator.Util.Helper
  import GettextTranslator.Util.PoHelper
  alias GettextTranslator.Dashboard.TranslationStore
  alias GettextTranslator.Util.GitHub
  alias GettextTranslator.Util.GitLab
  alias GettextTranslator.Util.PathHelper

  def create_pull_request(modified_translations, changelog_entries) do
    # Generate a unique branch name based on timestamp
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    branch_name = "translation-updates-#{timestamp}"

    # Configuration
    config = Application.get_env(:gettext_translator, :git_config, %{})
    repo_url = Map.get(config, :repo_url, "")
    base_branch = Map.get(config, :base_branch, "main")
    git_provider = Map.get(config, :provider, "github")

    # Prepare file changes
    translation_files = prepare_translation_file_changes(modified_translations)
    changelog_files = prepare_changelog_file_changes(changelog_entries)
    all_file_changes = translation_files ++ changelog_files

    # Create the pull/merge request based on the provider
    case git_provider do
      "github" ->
        GitHub.create_github_programmatic_pr(repo_url, branch_name, base_branch, all_file_changes)

      "gitlab" ->
        GitLab.create_gitlab_programmatic_mr(repo_url, branch_name, base_branch, all_file_changes)

      unknown ->
        {:error, "Unsupported git provider: #{unknown}"}
    end
  end

  defp prepare_translation_file_changes(modified_translations) do
    # Group translations by file path
    by_file = Enum.group_by(modified_translations, fn t -> t.file_path end)

    # Process each file
    Enum.flat_map(by_file, fn {file_path, file_translations} ->
      # Convert local file path to repository-relative path
      repo_path = local_to_repo_path(file_path)

      case process_translation_file_content(file_path, file_translations) do
        {:ok, content} -> [%{path: repo_path, content: content}]
        _ -> []
      end
    end)
  end

  # Convert local file path to repository-relative path
  defp local_to_repo_path(file_path) do
    [_, path_after_priv] = String.split(file_path, "priv/", parts: 2)
    "priv/#{path_after_priv}"
  end

  defp process_translation_file_content(file_path, translations) do
    # Read existing content
    case File.read(file_path) do
      {:ok, file_content} ->
        # Parse existing PO file
        case Expo.PO.parse_string(file_content) do
          {:ok, po} ->
            # Create a map of message_id -> translation for quick lookup
            translations_map = Map.new(translations, fn t -> {t.message_id, t} end)

            # Update each message in the PO file
            updated_messages =
              Enum.map(po.messages, fn msg ->
                maybe_update_msg(msg, translations_map)
              end)

            # Create updated PO file
            updated_po = %{po | messages: updated_messages}

            # Generate content as a string
            content = Expo.PO.compose(updated_po)
            {:ok, content}

          error ->
            error
        end

      error ->
        error
    end
  end

  defp maybe_update_msg(msg, translations_map) do
    msg_id = get_message_id(msg)

    case Map.get(translations_map, msg_id) do
      nil -> msg
      translation -> update_po_message(msg, translation)
    end
  end

  defp prepare_changelog_file_changes(entries_by_file) do
    if Enum.empty?(entries_by_file) do
      []
    else
      app = get_application()

      Enum.flat_map(entries_by_file, fn {file_path, entries} ->
        {:ok, changelog_path, content} = process_changelog_file_content(file_path, entries, app)
        [%{path: changelog_path, content: content}]
      end)
    end
  end

  defp process_changelog_file_content(file_path, entries, app) do
    # Extract language code and domain
    language_code = List.first(entries).code
    domain = TranslationStore.extract_domain_from_path(file_path)

    # Construct the changelog path
    relative_path = "#{language_code}_#{domain}_changelog.json"

    changelog_path =
      if app do
        Path.join(PathHelper.translation_changelog_dir(app), relative_path)
      else
        Path.join("priv/translation_changelog", relative_path)
      end

    changelog =
      TranslationStore.read_or_create_changelog(changelog_path, language_code, file_path)

    final_history = TranslationStore.process_changelog(changelog, entries)
    json = Jason.encode!(Map.put(changelog, "history", final_history), pretty: true)
    {:ok, changelog_path, json}
  end
end
