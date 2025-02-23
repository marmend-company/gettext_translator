defmodule GettextTranslator.Processor.LLM do
  @moduledoc """
   LLM processor for the translator behaviour.
  """
  require Logger

  @behaviour GettextTranslator.Processor.Translator

  alias GettextTranslator.Processor.Translator
  alias LangChain.Chains.LLMChain
  alias LangChain.Message

  @spec translate(Translator.provider(), Translator.opts()) :: {:ok, String.t()} | {:error, any()}
  def translate(provider, %{language_code: code, message: message}) do
    configure_langchain(provider.endpoint.config)

    case create_translation_chain(provider, code, message) do
      {:ok, result} ->
        {:ok, result}

      {:error, _, reason} ->
        Logger.error("Error while translating `#{message}` to `#{code}`: #{inspect(reason)}")

        # return empty translation
        {:ok, ""}
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

  defp create_translation_chain(provider, code, message) do
    llm =
      provider.endpoint.adapter.new!(%{
        model: provider.endpoint.model,
        temperature: provider.endpoint.temperature
      })

    messages = [
      Message.new_system!("#{provider.persona}. Your translation style is #{provider.style}"),
      Message.new_user!(build_translation_prompt(message, code))
    ]

    LLMChain.new!(%{llm: llm})
    |> LLMChain.add_messages(messages)
    |> LLMChain.run()
  end

  defp build_translation_prompt(message, code) do
    """
    Translate the message between <|input_start|> and <|input_end|> into language with POSIX code '#{code}'. \
    Your answer must contain only the message translation. \
    The message to be translated is <|input_start|>#{message}<|input_end|>
    """
  end
end
