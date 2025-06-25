defmodule GettextTranslator.Util.GitLab do
  def create_gitlab_programmatic_mr(repo_url, branch_name, base_branch, file_changes) do
    # Extract project ID or path from repo_url
    project_path =
      repo_url
      |> String.replace(~r{^https://gitlab.com/}, "")
      |> String.replace(~r{\.git$}, "")
      |> URI.encode_www_form()

    # Get GitLab token
    config = Application.get_env(:gettext_translator, :git_config, %{})
    token = Map.get(config, :gitlab_token, "")

    if token == "" do
      {:error, "GitLab token not configured"}
    else
      # Create the branch and commit in a single operation
      result =
        create_branch_with_commit(project_path, branch_name, base_branch, file_changes, token)

      case result do
        {:ok, _} ->
          # Create the merge request
          create_gitlab_merge_request(
            project_path,
            branch_name,
            base_branch,
            "Translation updates #{DateTime.utc_now() |> Calendar.strftime("%Y-%m-%d %H:%M:%S")}",
            "Automated merge request with translation updates",
            token
          )

        error ->
          error
      end
    end
  end

  # Single function to create branch and commit files all at once
  defp create_branch_with_commit(project_path, branch_name, base_branch, file_changes, token) do
    url = "https://gitlab.com/api/v4/projects/#{project_path}/repository/commits"

    headers = [
      {"private-token", token},
      {"content-type", "application/json"}
    ]

    # Prepare actions for all files
    actions =
      Enum.map(file_changes, fn %{path: path, content: content} ->
        content_str = if is_binary(content), do: content, else: to_string(content)
        content_base64 = Base.encode64(content_str)

        action = get_file_action(project_path, path, base_branch, token)

        %{
          "action" => action,
          "file_path" => path,
          "content" => content_base64,
          "encoding" => "base64"
        }
      end)

    body =
      Jason.encode!(%{
        "branch" => branch_name,
        # This creates the branch if it doesn't exist
        "start_branch" => base_branch,
        "commit_message" => "Update translations",
        "actions" => actions
      })

    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, GettextTranslator.Finch) do
      {:ok, %Finch.Response{status: status}} when status in 200..299 ->
        {:ok, "Branch created and files committed successfully"}

      {:ok, %Finch.Response{status: status, body: response_body}} ->
        error_msg =
          try do
            parsed = Jason.decode!(response_body)
            parsed["message"] || parsed["error"] || response_body
          rescue
            _ -> response_body
          end

        {:error, "Failed to create branch with commit: HTTP #{status}, #{error_msg}"}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  defp create_gitlab_merge_request(
         project_path,
         source_branch,
         target_branch,
         title,
         description,
         token
       ) do
    url = "https://gitlab.com/api/v4/projects/#{project_path}/merge_requests"

    headers = [
      {"private-token", token},
      {"content-type", "application/json"}
    ]

    body =
      Jason.encode!(%{
        "source_branch" => source_branch,
        "target_branch" => target_branch,
        "title" => title,
        "description" => description,
        "remove_source_branch" => true
      })

    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, GettextTranslator.Finch) do
      {:ok, %Finch.Response{status: status, body: response_body}} when status in 200..299 ->
        response = Jason.decode!(response_body)
        {:ok, response["web_url"]}

      {:ok, %Finch.Response{status: status, body: response_body}} ->
        response = Jason.decode!(response_body)
        error_message = response["message"] || "HTTP Error: #{status}"
        {:error, error_message}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  defp get_file_action(project_path, file_path, branch, token) do
    url =
      "https://gitlab.com/api/v4/projects/#{project_path}/repository/files/#{URI.encode_www_form(file_path)}"

    headers = [{"private-token", token}]
    params = "?ref=#{branch}"

    request = Finch.build(:get, url <> params, headers)

    case Finch.request(request, GettextTranslator.Finch) do
      {:ok, %Finch.Response{status: 200}} -> "update"
      {:ok, %Finch.Response{status: 404}} -> "create"
      # Default to create on errors
      _ -> "create"
    end
  end
end
