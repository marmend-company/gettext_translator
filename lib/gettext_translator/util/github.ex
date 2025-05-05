defmodule GettextTranslator.Util.GitHub do
  def create_github_programmatic_pr(repo_url, branch_name, base_branch, file_changes) do
    # Extract owner and repo from the URL
    [owner, repo] =
      repo_url
      |> String.replace(~r{^https://github.com/}, "")
      |> String.replace(~r{\.git$}, "")
      |> String.split("/", parts: 2)

    # Get GitHub token
    config = Application.get_env(:gettext_translator, :git_config, %{})
    token = Map.get(config, :github_token, "")

    if token == "" do
      {:error, "GitHub token not configured"}
    else
      # Get the SHA of the base branch to use as reference
      case get_reference_sha(owner, repo, base_branch, token) do
        {:ok, base_sha} ->
          # Create a new branch and commit in one operation
          result =
            create_branch_with_commit(owner, repo, branch_name, base_sha, file_changes, token)

          case result do
            {:ok, _} ->
              # Create the pull request
              create_github_pull_request(
                owner,
                repo,
                branch_name,
                base_branch,
                "Translation updates #{DateTime.utc_now() |> Calendar.strftime("%Y-%m-%d %H:%M:%S")}",
                "Automated pull request with translation updates",
                token
              )

            error ->
              error
          end

        error ->
          error
      end
    end
  end

  # Get the SHA of the latest commit on a branch
  defp get_reference_sha(owner, repo, branch, token) do
    url = "https://api.github.com/repos/#{owner}/#{repo}/git/refs/heads/#{branch}"

    headers = [
      {"Authorization", "token #{token}"},
      {"Accept", "application/vnd.github.v3+json"}
    ]

    request = Finch.build(:get, url, headers)

    case Finch.request(request, GettextTranslator.Finch) do
      {:ok, %Finch.Response{status: 200, body: response_body}} ->
        response = Jason.decode!(response_body)
        {:ok, response["object"]["sha"]}

      {:ok, %Finch.Response{status: status, body: response_body}} ->
        response = Jason.decode!(response_body)
        error_message = response["message"] || "HTTP Error: #{status}"
        {:error, error_message}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  # Create a branch and commit files in a single operation
  defp create_branch_with_commit(owner, repo, branch_name, base_sha, file_changes, token) do
    # 1. First create the reference (branch)
    create_result = create_github_reference(owner, repo, branch_name, base_sha, token)

    case create_result do
      {:ok, _} ->
        # 2. Create a tree with all file changes
        case create_tree(owner, repo, base_sha, file_changes, token) do
          {:ok, tree_sha} ->
            # 3. Create a commit with the tree
            case create_commit(owner, repo, "Update translations", tree_sha, base_sha, token) do
              {:ok, commit_sha} ->
                # 4. Update the reference to point to the new commit
                update_reference(owner, repo, branch_name, commit_sha, token)

              error ->
                error
            end

          error ->
            error
        end

      error ->
        error
    end
  end

  # Create a new Git reference (branch)
  defp create_github_reference(owner, repo, branch_name, sha, token) do
    url = "https://api.github.com/repos/#{owner}/#{repo}/git/refs"

    headers = [
      {"Authorization", "token #{token}"},
      {"Accept", "application/vnd.github.v3+json"},
      {"Content-Type", "application/json"}
    ]

    body =
      Jason.encode!(%{
        "ref" => "refs/heads/#{branch_name}",
        "sha" => sha
      })

    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, GettextTranslator.Finch) do
      {:ok, %Finch.Response{status: status}} when status in 200..299 ->
        {:ok, branch_name}

      {:ok, %Finch.Response{status: status, body: response_body}} ->
        response = Jason.decode!(response_body)
        error_message = response["message"] || "HTTP Error: #{status}"
        {:error, error_message}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  # Create a tree with all file changes
  defp create_tree(owner, repo, base_sha, file_changes, token) do
    url = "https://api.github.com/repos/#{owner}/#{repo}/git/trees"

    headers = [
      {"Authorization", "token #{token}"},
      {"Accept", "application/vnd.github.v3+json"},
      {"Content-Type", "application/json"}
    ]

    # Convert file changes to GitHub tree format
    tree =
      Enum.map(file_changes, fn %{path: path, content: content} ->
        # Ensure content is a string
        content_str = if is_binary(content), do: content, else: to_string(content)

        %{
          "path" => path,
          # Regular file mode
          "mode" => "100644",
          "type" => "blob",
          "content" => content_str
        }
      end)

    body =
      Jason.encode!(%{
        "base_tree" => base_sha,
        "tree" => tree
      })

    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, GettextTranslator.Finch) do
      {:ok, %Finch.Response{status: status, body: response_body}} when status in 200..299 ->
        response = Jason.decode!(response_body)
        {:ok, response["sha"]}

      {:ok, %Finch.Response{status: status, body: response_body}} ->
        response = Jason.decode!(response_body)
        error_message = response["message"] || "HTTP Error: #{status}"
        {:error, error_message}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  # Create a commit with the tree
  defp create_commit(owner, repo, message, tree_sha, parent_sha, token) do
    url = "https://api.github.com/repos/#{owner}/#{repo}/git/commits"

    headers = [
      {"Authorization", "token #{token}"},
      {"Accept", "application/vnd.github.v3+json"},
      {"Content-Type", "application/json"}
    ]

    body =
      Jason.encode!(%{
        "message" => message,
        "tree" => tree_sha,
        "parents" => [parent_sha]
      })

    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, GettextTranslator.Finch) do
      {:ok, %Finch.Response{status: status, body: response_body}} when status in 200..299 ->
        response = Jason.decode!(response_body)
        {:ok, response["sha"]}

      {:ok, %Finch.Response{status: status, body: response_body}} ->
        response = Jason.decode!(response_body)
        error_message = response["message"] || "HTTP Error: #{status}"
        {:error, error_message}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  # Update a reference to point to the new commit
  defp update_reference(owner, repo, branch_name, commit_sha, token) do
    url = "https://api.github.com/repos/#{owner}/#{repo}/git/refs/heads/#{branch_name}"

    headers = [
      {"Authorization", "token #{token}"},
      {"Accept", "application/vnd.github.v3+json"},
      {"Content-Type", "application/json"}
    ]

    body =
      Jason.encode!(%{
        "sha" => commit_sha,
        "force" => false
      })

    request = Finch.build(:patch, url, headers, body)

    case Finch.request(request, GettextTranslator.Finch) do
      {:ok, %Finch.Response{status: status}} when status in 200..299 ->
        {:ok, branch_name}

      {:ok, %Finch.Response{status: status, body: response_body}} ->
        response = Jason.decode!(response_body)
        error_message = response["message"] || "HTTP Error: #{status}"
        {:error, error_message}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  # Create a pull request
  defp create_github_pull_request(
         owner,
         repo,
         head_branch,
         base_branch,
         title,
         description,
         token
       ) do
    url = "https://api.github.com/repos/#{owner}/#{repo}/pulls"

    headers = [
      {"Authorization", "token #{token}"},
      {"Accept", "application/vnd.github.v3+json"},
      {"Content-Type", "application/json"}
    ]

    body =
      Jason.encode!(%{
        "title" => title,
        "body" => description,
        "head" => head_branch,
        "base" => base_branch
      })

    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, GettextTranslator.Finch) do
      {:ok, %Finch.Response{status: status, body: response_body}} when status in 200..299 ->
        response = Jason.decode!(response_body)
        {:ok, response["html_url"]}

      {:ok, %Finch.Response{status: status, body: response_body}} ->
        response = Jason.decode!(response_body)
        error_message = response["message"] || "HTTP Error: #{status}"
        {:error, error_message}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end
end
