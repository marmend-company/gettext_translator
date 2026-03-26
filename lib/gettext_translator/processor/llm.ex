defmodule GettextTranslator.Processor.LLM do
  @moduledoc """
   LLM processor for the translator behaviour.
  """
  require Logger

  @behaviour GettextTranslator.Processor.Translator

  alias GettextTranslator.Processor.Translator
  alias GettextTranslator.Util.LanguageNames
  alias LangChain.Chains.LLMChain
  alias LangChain.Message
  alias LangChain.Message.ContentPart

  @doc """
  Translates a single message using the configured LLM provider, with optional
  additional instructions to guide the translation.

  ## Parameters

    - `provider` - The provider config map from `Parser.parse_provider/0`
    - `opts` - Map with `:language_code`, `:message`, `:type`, and optionally `:plural_message`
    - `additional_instructions` - Optional string with extra instructions for the LLM

  ## Returns

    - `{:ok, %{translation: String.t(), plural_translation: String.t() | nil}}`
    - `{:error, reason}`
  """
  @spec translate_single(Translator.provider(), map(), String.t() | nil) ::
          {:ok, map()} | {:error, any()}
  def translate_single(provider, opts, additional_instructions \\ nil) do
    %{language_code: code, message: message, type: type} = opts

    configure_langchain(provider.endpoint.config)

    with {:ok, translation} <- do_translate(provider, code, message, additional_instructions) do
      if type == :plural do
        plural_message = Map.get(opts, :plural_message, message)

        case do_translate(provider, code, plural_message, additional_instructions) do
          {:ok, plural_translation} ->
            {:ok, %{translation: translation, plural_translation: plural_translation}}

          {:error, reason} ->
            {:error, reason}
        end
      else
        {:ok, %{translation: translation, plural_translation: nil}}
      end
    end
  end

  @spec translate(Translator.provider(), Translator.opts()) :: {:ok, String.t()} | {:error, any()}
  def translate(provider, %{language_code: code, message: message}) do
    configure_langchain(provider.endpoint.config)

    case create_translation_chain(provider, code, message, nil) do
      {:ok, %{last_message: %Message{content: content}}} ->
        # In LangChain 0.4.0, content is a list of ContentPart structs
        # Convert to string using ensure_string/1 helper
        {:ok, ensure_string(content)}

      {:error, _, reason} ->
        Logger.error("Error while translating `#{message}` to `#{code}`: #{inspect(reason)}")

        # return empty translation
        {:ok, ""}
    end
  end

  defp do_translate(provider, code, message, additional_instructions) do
    case create_translation_chain(provider, code, message, additional_instructions) do
      {:ok, %{last_message: %Message{content: content}}} ->
        {:ok, ensure_string(content)}

      {:error, _, reason} ->
        Logger.error("Error while translating `#{message}` to `#{code}`: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp configure_langchain(endpoint_config) do
    endpoint_config
    |> Map.keys()
    |> Enum.each(fn key ->
      :ok = Application.put_env(:langchain, String.to_atom(key), Map.get(endpoint_config, key))
    end)

    :ok
  end

  defp create_translation_chain(provider, code, message, additional_instructions) do
    llm =
      provider.endpoint.adapter.new!(%{
        model: provider.endpoint.model,
        temperature: provider.endpoint.temperature
      })

    messages =
      if translategemma?(provider.endpoint.model) do
        source_lang = Map.get(provider, :source_language, "en")
        [Message.new_user!(build_translategemma_prompt(message, source_lang, code))]
      else
        [
          Message.new_system!("#{provider.persona}. Your translation style is #{provider.style}"),
          Message.new_user!(build_translation_prompt(message, code, additional_instructions))
        ]
      end

    LLMChain.new!(%{llm: llm})
    |> LLMChain.add_messages(messages)
    |> LLMChain.run()
  end

  @doc """
  Checks if the given model name is a TranslateGemma model.

  ## Examples

      iex> GettextTranslator.Processor.LLM.translategemma?("translategemma-27b")
      true

      iex> GettextTranslator.Processor.LLM.translategemma?("gpt-4")
      false
  """
  @spec translategemma?(String.t()) :: boolean()
  def translategemma?(model_name) do
    model_name
    |> String.downcase()
    |> String.contains?("translategemma")
  end

  defp build_translation_prompt(message, code, additional_instructions) do
    base =
      """
      Translate the message between <|input_start|> and <|input_end|> into language with POSIX code '#{code}'. \
      Your answer must contain only the message translation. \
      The message to be translated is <|input_start|>#{message}<|input_end|>
      """

    if additional_instructions && additional_instructions != "" do
      base <> "Additional instructions: #{additional_instructions}"
    else
      base
    end
  end

  @doc """
  Builds a TranslateGemma-formatted prompt for translation.

  TranslateGemma expects a single user message with a specific structure:
  professional translator persona, followed by two blank lines before the text.

  ## Parameters

    - `message` - The text to translate
    - `source_code` - POSIX code of the source language (e.g., "en")
    - `target_code` - POSIX code of the target language (e.g., "es")

  ## Examples

      iex> GettextTranslator.Processor.LLM.build_translategemma_prompt("Hello", "en", "es")
      "You are a professional English (en) to Spanish (es) translator. " <>
      "Your goal is to accurately convey the meaning and nuances of the original English text " <>
      "while adhering to Spanish grammar, vocabulary, and cultural sensitivities.\\n" <>
      "Produce only the Spanish translation, without any additional explanations or commentary. " <>
      "Please translate the following English text into Spanish:\\n\\n\\nHello"
  """
  @spec build_translategemma_prompt(String.t(), String.t(), String.t()) :: String.t()
  def build_translategemma_prompt(message, source_code, target_code) do
    source_name = LanguageNames.language_name(source_code)
    target_name = LanguageNames.language_name(target_code)
    source_iso = LanguageNames.iso_code(source_code)
    target_iso = LanguageNames.iso_code(target_code)

    "You are a professional #{source_name} (#{source_iso}) to #{target_name} (#{target_iso}) translator. " <>
      "Your goal is to accurately convey the meaning and nuances of the original #{source_name} text " <>
      "while adhering to #{target_name} grammar, vocabulary, and cultural sensitivities.\n" <>
      "Produce only the #{target_name} translation, without any additional explanations or commentary. " <>
      "Please translate the following #{source_name} text into #{target_name}:\n\n\n#{message}"
  end

  # Safely convert LLM response content to string
  # Handles both LangChain 0.4.0 (list of ContentPart) and 0.3.3 (string) formats
  defp ensure_string(value) when is_list(value), do: ContentPart.parts_to_string(value) || ""
  defp ensure_string(value) when is_binary(value), do: value
  defp ensure_string(_), do: ""
end
