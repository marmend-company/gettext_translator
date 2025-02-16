defmodule GettextTranslator.Util.Parser do
  @moduledoc """
  Parse files in the gettext root folder
  """
  import GettextTranslator.Util.Helper

  @default_style "Casual, use simple language"
  @default_persona "You are a proffesional translator. Your goal is to translate the message to the target language and try to keep the same meaning and length of the output sentence as original one."

  def parse_provider() do
    config = Application.fetch_env!(:gettext_translator, __MODULE__)

    %{
      endpoint: %{
        adapter: Keyword.fetch!(config, :endpoint),
        model: Keyword.fetch!(config, :endpoint_model),
        temperature: Keyword.fetch!(config, :endpoint_temperature),
        config: Keyword.fetch!(config, :endpoint_config)
      },
      persona: Keyword.get(config, :persona, @default_persona),
      style: Keyword.get(config, :style, @default_style),
      ignored_languages: Keyword.get(config, :ignored_languages, [])
    }
  end

  def scan(gettext_root_path) do
    with {:ok, files} <- File.ls(gettext_root_path),
         language_dirs <- find_language_directories(files, gettext_root_path) do
      process_directories(language_dirs, gettext_root_path)
    end
  end

  defp find_language_directories(files, root_path) do
    Enum.filter(files, &File.dir?(Path.join(root_path, &1)))
  end

  defp process_directories(language_dirs, root_path) do
    result =
      Enum.reduce_while(language_dirs, {:ok, []}, fn dir, {:ok, acc} ->
        case get_language_folder_data(dir, root_path) do
          {:ok, folder_data} -> {:cont, {:ok, [folder_data | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case result do
      {:ok, folders} -> {:ok, Enum.reverse(folders)}
      error -> error
    end
  end

  defp get_language_folder_data(language_dir, root_path) do
    path = Path.join(root_path, language_dir)

    case list_files_from_language_folder(path) do
      {:ok, po_files} ->
        {:ok,
         %{
           language_code: language_dir,
           files: po_files
         }}

      error ->
        error
    end
  end

  defp list_files_from_language_folder(language_folder_path) do
    messages_dir = Path.join(language_folder_path, lc_messages())

    with {:ok, files} <- File.ls(messages_dir),
         po_files <- filter_po_files(files) do
      {:ok, Enum.map(po_files, &Path.join([language_folder_path, lc_messages(), &1]))}
    end
  end

  defp filter_po_files(files) do
    Enum.filter(files, &(!File.dir?(&1) && String.ends_with?(&1, ".po")))
  end
end
