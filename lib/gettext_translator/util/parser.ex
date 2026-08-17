defmodule GettextTranslator.Util.Parser do
  @moduledoc """
  Parse files in the gettext root folder
  """
  import GettextTranslator.Util.Helper

  require Logger

  @default_style "Casual, use simple language"
  @default_persona "You are a proffesional translator. Your goal is to translate the message to the target language and try to keep the same meaning and length of the output sentence as original one."
  @default_source_language "en"

  # The pre-`:default_provider` state: a blank override form that inherits nothing.
  @no_instance_default %{provider: nil, model: nil, adapter: nil, endpoint_config: %{}}

  # provider slug => {LangChain adapter, key under which its API key travels, label}
  #
  # The slugs are also the override form's `<option value>`s, so this map is the
  # single definition of which providers exist. vLLM speaks the OpenAI wire
  # format, so it reuses ChatOpenAI and the openai_key slot; its base URL is
  # threaded in via GettextTranslator.Processor.LLM.build_llm_attrs/1.
  @adapters %{
    "openai" => {LangChain.ChatModels.ChatOpenAI, "openai_key", "OpenAI"},
    "anthropic" => {LangChain.ChatModels.ChatAnthropic, "anthropic_key", "Anthropic"},
    "ollama" => {LangChain.ChatModels.ChatOllamaAI, nil, "Ollama"},
    "google_ai" => {LangChain.ChatModels.ChatGoogleAI, "google_ai_key", "Google AI"},
    "vllm" => {LangChain.ChatModels.ChatOpenAI, "openai_key", "vLLM"}
  }

  @fallback_provider "openai"

  @doc """
  Returns a summary of the configured LLM provider for display in the dashboard.

  Returns `%{configured: true, adapter_name: "ChatOpenAI", model: "gpt-4"}` when
  configured, or `%{configured: false}` otherwise.
  """
  @spec provider_info() ::
          %{configured: boolean(), adapter_name: String.t(), model: String.t()}
          | %{configured: false}
  def provider_info do
    config = Application.get_env(:gettext_translator, GettextTranslator, [])

    with {:ok, adapter} <- Keyword.fetch(config, :endpoint),
         {:ok, model} <- Keyword.fetch(config, :endpoint_model) do
      adapter_name = adapter |> Module.split() |> List.last()
      %{configured: true, adapter_name: adapter_name, model: model}
    else
      _ -> %{configured: false}
    end
  end

  @doc """
  Returns the provider the dashboard should preselect in the LLM override form,
  along with the instance settings that back it.

  An instance that already configures a provider — a self-hosted vLLM gateway
  whose endpoint and API key come from the release's own environment, say —
  should not make an operator retype those into a dashboard form. Set
  `:default_provider` and the override form opens with that adapter selected and
  the configured model filled in, and treats blank credential fields as "use
  whatever the instance is already configured with":

      config :gettext_translator, GettextTranslator,
        endpoint: MyApp.LLM.ChatVLLM,
        endpoint_model: System.get_env("GETTEXT_TRANSLATOR_MODEL", "gemma-4-26b-a4b-it"),
        default_provider: :vllm

  The value may be an atom or a string naming one of the adapters the form offers
  (`:openai`, `:anthropic`, `:ollama`, `:google_ai`, `:vllm`).

  `:provider` is `nil` when `:default_provider` is unset, which leaves the
  override form behaving exactly as it did before this option existed.
  """
  @spec instance_default() :: %{
          provider: String.t() | nil,
          model: String.t() | nil,
          adapter: module() | nil,
          endpoint_config: map()
        }
  def instance_default do
    config = Application.get_env(:gettext_translator, GettextTranslator, [])

    # All-or-nothing on purpose. Reading `:endpoint_model` without an opted-in
    # `:default_provider` would prefill the form's Model field while no <option>
    # carries `selected`, so the browser falls back to the first one — OpenAI. An
    # Anthropic instance would then show a form that looks ready to submit but is
    # pointed at the wrong adapter with the right model name.
    raw = Keyword.get(config, :default_provider)

    case normalize_provider(raw) do
      nil ->
        # A typo here used to be worse than useless: an unrecognized slug matches
        # no <option>, so the browser silently selects the first one (OpenAI)
        # while the model stayed prefilled from config. Refusing the value keeps
        # the form blank, and the log says why rather than leaving an operator to
        # wonder where their default went.
        if raw, do: warn_unknown_provider(raw)
        @no_instance_default

      provider ->
        %{
          provider: provider,
          model: Keyword.get(config, :endpoint_model),
          adapter: Keyword.get(config, :endpoint),
          endpoint_config: config |> Keyword.get(:endpoint_config) |> normalize_endpoint_config()
        }
    end
  end

  @doc """
  The provider slugs the dashboard override form offers, which are also the only
  accepted values of `:default_provider`.
  """
  @spec known_providers() :: [String.t()]
  def known_providers, do: Map.keys(@adapters)

  @doc """
  Human-readable label for a provider slug, or `nil` if it is not a known one.

  `"google_ai"` is not what anyone wants to read in a form label.
  """
  @spec provider_label(String.t() | nil) :: String.t() | nil
  def provider_label(provider) do
    case Map.fetch(@adapters, provider) do
      {:ok, {_adapter, _config_key, label}} -> label
      :error -> nil
    end
  end

  @doc """
  Turns the dashboard override form's params into the provider override map the
  translation chain consumes.

  Lives here rather than in the page because it is provider/config resolution
  rather than view logic, and because the two decisions it makes are worth
  testing directly:

    * **Which adapter module.** Choosing the provider the instance is configured
      for uses that instance's own `:endpoint` module, not the generic LangChain
      one. For a self-hosted gateway that is the whole point: a module like
      `MyApp.LLM.ChatVLLM` resolves its endpoint and bearer token from the
      release environment, where `ChatOpenAI` would need the full completions URL
      typed into the form.

    * **Which credentials.** Blank fields inherit the instance's
      `:endpoint_config`, but *only* when the submitted adapter is the configured
      one — picking a different provider must not send it another provider's key.
      Anything actually typed always wins.
  """
  @spec resolve_override(map(), map()) :: %{
          adapter: module(),
          adapter_name: String.t(),
          model: String.t(),
          config: map()
        }
  def resolve_override(params, defaults) do
    provider =
      normalize_provider(Map.get(params, "adapter")) || defaults.provider || @fallback_provider

    {adapter, config_key, label} = adapter_for(provider, defaults)

    config =
      provider
      |> inherited_endpoint_config(defaults)
      |> maybe_put_config(config_key, Map.get(params, "api_key", ""))
      |> maybe_put_endpoint_url(Map.get(params, "endpoint_url", ""))

    %{
      adapter: adapter,
      adapter_name: label,
      model: presence(Map.get(params, "model")) || defaults.model || "",
      config: config
    }
  end

  # The repeated `provider` binds by equality, so this clause is reached only when
  # the submitted adapter *is* the instance's configured provider.
  defp adapter_for(provider, %{provider: provider, adapter: adapter}) when not is_nil(adapter) do
    {_generic, config_key, label} = Map.fetch!(@adapters, provider)
    {adapter, config_key, label}
  end

  defp adapter_for(provider, _defaults), do: Map.fetch!(@adapters, provider)

  defp inherited_endpoint_config(provider, %{provider: provider} = defaults),
    do: defaults.endpoint_config

  defp inherited_endpoint_config(_provider, _defaults), do: %{}

  defp maybe_put_config(config, nil, _api_key), do: config
  defp maybe_put_config(config, _key, ""), do: config
  defp maybe_put_config(config, key, api_key), do: Map.put(config, key, api_key)

  defp maybe_put_endpoint_url(config, ""), do: config
  defp maybe_put_endpoint_url(config, url), do: Map.put(config, "endpoint", url)

  defp presence(nil), do: nil

  defp presence(value) when is_binary(value),
    do: if(String.trim(value) == "", do: nil, else: value)

  defp presence(_value), do: nil

  defp warn_unknown_provider(raw) do
    Logger.warning(
      "gettext_translator: ignoring unknown :default_provider #{inspect(raw)} — " <>
        "expected one of #{inspect(known_providers())}"
    )
  end

  defp normalize_provider(nil), do: nil

  defp normalize_provider(provider) when is_atom(provider),
    do: provider |> Atom.to_string() |> known_provider()

  defp normalize_provider(provider) when is_binary(provider), do: known_provider(provider)
  defp normalize_provider(_provider), do: nil

  defp known_provider(provider) when is_map_key(@adapters, provider), do: provider
  defp known_provider(_provider), do: nil

  defp normalize_endpoint_config(config) when is_map(config), do: config
  defp normalize_endpoint_config(_config), do: %{}

  def parse_provider do
    config = Application.fetch_env!(:gettext_translator, GettextTranslator)

    %{
      endpoint: %{
        adapter: Keyword.fetch!(config, :endpoint),
        model: Keyword.fetch!(config, :endpoint_model),
        temperature: Keyword.fetch!(config, :endpoint_temperature),
        config: Keyword.fetch!(config, :endpoint_config),
        # Optional. Since LangChain 0.7.0, Req-level HTTP retries are disabled by
        # default and transient 429/503 errors bubble up after `retry_count`
        # attempts (LangChain default: 2). Set `:endpoint_retry_count` to tune it.
        retry_count: Keyword.get(config, :endpoint_retry_count)
      },
      persona: Keyword.get(config, :persona, @default_persona),
      style: Keyword.get(config, :style, @default_style),
      source_language: Keyword.get(config, :source_language, @default_source_language),
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
