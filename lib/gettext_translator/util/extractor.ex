defmodule GettextTranslator.Util.Extractor do
  @moduledoc """
  Handles extraction and merging of gettext translations.

  In development (Mix available), runs `mix gettext.extract --merge --no-fuzzy`.
  In production (no Mix), falls back to merging .pot files into .po files using Expo.
  """

  require Logger

  @doc """
  Extracts and merges gettext translations.

  Uses `mix gettext.extract --merge` in dev, or merges .pot files directly in prod.

  ## Parameters

    - `gettext_path` - The path to the gettext directory

  ## Returns

    - `{:ok, message}` on success
    - `{:error, reason}` on failure

  ## Examples

      iex> Extractor.extract_and_merge("/path/to/priv/gettext")
      {:ok, "Extraction complete: ..."}
  """
  @spec extract_and_merge(String.t()) :: {:ok, String.t()} | {:error, any()}
  def extract_and_merge(gettext_path) do
    if Code.ensure_loaded?(Mix) do
      extract_with_mix()
    else
      extract_with_expo(gettext_path)
    end
  end

  defp extract_with_mix do
    case System.cmd("mix", ["gettext.extract", "--merge", "--no-fuzzy"], stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, "Extraction complete: #{String.trim(output)}"}

      {output, _exit_code} ->
        {:error, "Mix extraction failed: #{String.trim(output)}"}
    end
  rescue
    e -> {:error, "Mix extraction error: #{Exception.message(e)}"}
  end

  defp extract_with_expo(gettext_path) do
    pot_files = find_pot_files(gettext_path)

    if Enum.empty?(pot_files) do
      {:error, "No .pot files found in #{gettext_path}"}
    else
      language_dirs = find_language_dirs(gettext_path)

      results =
        for pot_file <- pot_files,
            lang_dir <- language_dirs do
          merge_pot_into_lang(pot_file, lang_dir, gettext_path)
        end

      errors = Enum.filter(results, &match?({:error, _}, &1))

      if Enum.empty?(errors) do
        {:ok,
         "Merged #{length(pot_files)} .pot file(s) into #{length(language_dirs)} language(s)"}
      else
        error_messages = Enum.map_join(errors, "; ", fn {:error, msg} -> msg end)
        {:error, "Some merges failed: #{error_messages}"}
      end
    end
  end

  defp find_pot_files(gettext_path) do
    pot_pattern = Path.join(gettext_path, "*.pot")

    Path.wildcard(pot_pattern)
  end

  defp find_language_dirs(gettext_path) do
    case File.ls(gettext_path) do
      {:ok, entries} ->
        entries
        |> Enum.filter(fn entry ->
          path = Path.join(gettext_path, entry)
          File.dir?(path) && entry != "." && entry != ".."
        end)

      {:error, _} ->
        []
    end
  end

  defp merge_pot_into_lang(pot_file, lang_dir, gettext_path) do
    domain = pot_file |> Path.basename() |> String.replace_suffix(".pot", "")
    po_dir = Path.join([gettext_path, lang_dir, "LC_MESSAGES"])
    po_file = Path.join(po_dir, "#{domain}.po")

    case Expo.PO.parse_file(pot_file) do
      {:ok, pot_content} ->
        if File.exists?(po_file) do
          case Expo.PO.parse_file(po_file) do
            {:ok, po_content} ->
              merged = merge_messages(po_content, pot_content)
              File.write(po_file, Expo.PO.compose(merged))

            {:error, reason} ->
              {:error, "Failed to parse #{po_file}: #{inspect(reason)}"}
          end
        else
          File.mkdir_p!(po_dir)

          new_po = %Expo.Messages{
            headers: pot_content.headers,
            messages: pot_content.messages
          }

          File.write(po_file, Expo.PO.compose(new_po))
        end

      {:error, reason} ->
        {:error, "Failed to parse #{pot_file}: #{inspect(reason)}"}
    end
  end

  defp merge_messages(po, pot) do
    existing_ids = MapSet.new(po.messages, &get_msg_id/1)

    new_messages =
      pot.messages
      |> Enum.reject(fn msg -> MapSet.member?(existing_ids, get_msg_id(msg)) end)

    %{po | messages: po.messages ++ new_messages}
  end

  defp get_msg_id(%Expo.Message.Singular{msgid: msgid}), do: {:singular, Enum.join(msgid, "")}

  defp get_msg_id(%Expo.Message.Plural{msgid: msgid, msgid_plural: msgid_plural}),
    do: {:plural, Enum.join(msgid, ""), Enum.join(msgid_plural, "")}
end
