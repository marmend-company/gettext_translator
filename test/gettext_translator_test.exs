defmodule GettextTranslatorTest do
  use ExUnit.Case

  alias GettextTranslator.Util.Helper
  @folder_path "#{System.user_home!()}/test/gettext-translator/test"

  setup do
    {:ok, _} =
      create_folder(%{
        folder_path: @folder_path,
        language_dirs: [
          %{
            language_code: "en",
            files: [
              %{
                name: "default",
                content: ~s"""
                #, elixir-autogen, elixir-format
                msgid "The quick brown fox jumps over the lazy dog"
                msgstr ""
                """
              },
              %{
                name: "errors",
                content: """
                #, elixir-autogen, elixir-format
                msgid "invalid error"
                msgstr ""

                #, elixir-autogen, elixir-format
                msgid "singular - should be at most %{count} byte(s)"
                msgid_plural "plural - should be at most %{count} byte(s)"
                msgstr[0] ""
                msgstr[1] ""
                """
              }
            ]
          },
          %{
            language_code: "de",
            files: [
              %{
                name: "default",
                content: ~s"""
                #, elixir-autogen, elixir-format
                msgid "The quick brown fox jumps over the lazy dog"
                msgstr ""
                """
              },
              %{
                name: "errors",
                content: """
                #, elixir-autogen, elixir-format
                msgid "invalid error"
                msgstr ""

                #, elixir-autogen, elixir-format
                msgid "singular - should be at most %{count} byte(s)"
                msgid_plural "plural - should be at most %{count} byte(s)"
                msgstr[0] ""
                msgstr[1] ""
                """
              }
            ]
          }
        ]
      })

    on_exit(fn ->
      cleanup_folder(@folder_path)
    end)

    :ok
  end

  describe "translate/2" do
    # skipped for Github Actions, as it require a local installation of ollama
    @tag :skip
    test "Langchain based translator generates a translation" do
      {:ok, translation} =
        GettextTranslator.translate(
          config_provider(),
          @folder_path
        )

      assert translation == 3
    end
  end

  defp config_provider do
    %{
      ignored_languages: ["en"],
      persona:
        "You are translating headers, titles, menu items and other such words. Try to keep the translated length as close as possible to the original length. Try to use the same words as much as possible.  If the translation is not a word, use the original word. Use the same word case as the original word. Use the same punctuation as the original word. Do not leave empty spaces in the translation or make the \n line break.",
      style:
        "Casual but respectul. Uses plain plain language that can be understood by all age groups and demographics.",
      endpoint: %{
        config: %{},
        adapter: LangChain.ChatModels.ChatOllamaAI,
        model: "llama3.2:latest",
        temperature: 0
      }
    }
  end

  def create_folder(opts) do
    # Create root dir
    :ok = File.mkdir_p(opts.folder_path)

    # Create language dirs
    Enum.each(opts.language_dirs, fn language_dir ->
      :ok = File.mkdir(Path.join([opts.folder_path, language_dir.language_code]))

      :ok =
        File.mkdir(
          Path.join([opts.folder_path, language_dir.language_code, Helper.lc_messages()])
        )

      Enum.each(language_dir.files, fn file ->
        :ok =
          File.write(
            Path.join([
              opts.folder_path,
              language_dir.language_code,
              Helper.lc_messages(),
              "#{file.name}.po"
            ]),
            file.content
          )
      end)
    end)

    {:ok, Enum.count(opts.language_dirs)}
  end

  def cleanup_folder(folder_path) do
    File.rm_rf(folder_path)
  end

  def read_translation_file(folder_path, language_code, domain) do
    File.read(Path.join([folder_path, language_code, Helper.lc_messages(), "#{domain}.po"]))
  end
end
