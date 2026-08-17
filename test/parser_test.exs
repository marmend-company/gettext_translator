defmodule GettextTranslator.Util.ParserTest do
  use ExUnit.Case, async: false

  alias GettextTranslator.Util.Parser

  describe "parse_provider/0 endpoint config" do
    setup do
      original = Application.get_env(:gettext_translator, GettextTranslator)

      on_exit(fn ->
        case original do
          nil -> Application.delete_env(:gettext_translator, GettextTranslator)
          config -> Application.put_env(:gettext_translator, GettextTranslator, config)
        end
      end)

      base = [
        endpoint: LangChain.ChatModels.ChatOpenAI,
        endpoint_model: "gpt-4",
        endpoint_temperature: 0,
        endpoint_config: %{}
      ]

      %{base: base}
    end

    test "retry_count defaults to nil when :endpoint_retry_count is unset", %{base: base} do
      Application.put_env(:gettext_translator, GettextTranslator, base)

      provider = Parser.parse_provider()

      assert provider.endpoint.retry_count == nil
    end

    test "retry_count is read from :endpoint_retry_count when configured", %{base: base} do
      Application.put_env(
        :gettext_translator,
        GettextTranslator,
        Keyword.put(base, :endpoint_retry_count, 5)
      )

      provider = Parser.parse_provider()

      assert provider.endpoint.retry_count == 5
    end
  end

  describe "instance_default/0" do
    setup do
      original = Application.get_env(:gettext_translator, GettextTranslator)

      on_exit(fn ->
        case original do
          nil -> Application.delete_env(:gettext_translator, GettextTranslator)
          config -> Application.put_env(:gettext_translator, GettextTranslator, config)
        end
      end)

      base = [
        endpoint: LangChain.ChatModels.ChatOpenAI,
        endpoint_model: "gpt-4",
        endpoint_temperature: 0,
        endpoint_config: %{"openai_key" => "sk-from-config"}
      ]

      %{base: base}
    end

    test "provider is nil when :default_provider is unset", %{base: base} do
      Application.put_env(:gettext_translator, GettextTranslator, base)

      assert Parser.instance_default().provider == nil
    end

    test "an atom :default_provider is normalized to the form's string value", %{base: base} do
      Application.put_env(
        :gettext_translator,
        GettextTranslator,
        Keyword.put(base, :default_provider, :vllm)
      )

      assert Parser.instance_default().provider == "vllm"
    end

    test "a string :default_provider is passed through", %{base: base} do
      Application.put_env(
        :gettext_translator,
        GettextTranslator,
        Keyword.put(base, :default_provider, "ollama")
      )

      assert Parser.instance_default().provider == "ollama"
    end

    test "a nonsense :default_provider degrades to nil rather than raising", %{base: base} do
      Application.put_env(
        :gettext_translator,
        GettextTranslator,
        Keyword.put(base, :default_provider, 42)
      )

      assert Parser.instance_default().provider == nil
    end

    # A slug outside the allowlist matches no <option>, so the browser would
    # select the first one (OpenAI) while the model stayed prefilled from config —
    # the same wrong-adapter trap as an ungated instance_default/0. Refusing the
    # value keeps the form blank instead.
    test "a provider outside the known set is refused, not passed through", %{base: base} do
      for typo <- [:mistral, :gemini, "claude", "vLLM", "openai_key"] do
        Application.put_env(
          :gettext_translator,
          GettextTranslator,
          Keyword.put(base, :default_provider, typo)
        )

        assert Parser.instance_default() == %{
                 provider: nil,
                 model: nil,
                 adapter: nil,
                 endpoint_config: %{}
               },
               "expected #{inspect(typo)} to be refused"
      end
    end

    test "every known provider is accepted", %{base: base} do
      for provider <- Parser.known_providers() do
        Application.put_env(
          :gettext_translator,
          GettextTranslator,
          Keyword.put(base, :default_provider, provider)
        )

        assert Parser.instance_default().provider == provider
      end
    end

    test "the configured adapter, model and endpoint config come along", %{base: base} do
      Application.put_env(
        :gettext_translator,
        GettextTranslator,
        Keyword.put(base, :default_provider, :vllm)
      )

      defaults = Parser.instance_default()

      assert defaults.adapter == LangChain.ChatModels.ChatOpenAI
      assert defaults.model == "gpt-4"
      assert defaults.endpoint_config == %{"openai_key" => "sk-from-config"}
    end

    test "a non-map :endpoint_config degrades to an empty map", %{base: base} do
      Application.put_env(
        :gettext_translator,
        GettextTranslator,
        base |> Keyword.put(:endpoint_config, []) |> Keyword.put(:default_provider, :vllm)
      )

      assert Parser.instance_default().endpoint_config == %{}
    end

    # Regression: reading :endpoint_model without an opted-in :default_provider
    # prefilled the form's Model field while no <option> was marked selected, so
    # the browser defaulted the Adapter to OpenAI. An Anthropic instance saw a
    # form that looked ready to submit but pointed at the wrong adapter.
    test "nothing is inherited unless :default_provider opts in", %{base: base} do
      Application.put_env(
        :gettext_translator,
        GettextTranslator,
        base
        |> Keyword.put(:endpoint, LangChain.ChatModels.ChatAnthropic)
        |> Keyword.put(:endpoint_model, "claude-sonnet-4-5-20250929")
      )

      assert Parser.instance_default() == %{
               provider: nil,
               model: nil,
               adapter: nil,
               endpoint_config: %{}
             }
    end

    test "an absent config yields a fully nil default", %{base: _base} do
      Application.delete_env(:gettext_translator, GettextTranslator)

      assert Parser.instance_default() == %{
               provider: nil,
               model: nil,
               adapter: nil,
               endpoint_config: %{}
             }
    end
  end

  describe "resolve_override/2" do
    @no_default %{provider: nil, model: nil, adapter: nil, endpoint_config: %{}}

    @vllm_default %{
      provider: "vllm",
      model: "gemma-4-26b-a4b-it",
      adapter: FakeGatewayAdapter,
      endpoint_config: %{"openai_key" => "sk-from-release-env"}
    }

    test "without an instance default, behaviour is the pre-feature one" do
      override =
        Parser.resolve_override(
          %{"adapter" => "anthropic", "model" => "claude", "api_key" => "sk-typed"},
          @no_default
        )

      assert override.adapter == LangChain.ChatModels.ChatAnthropic
      assert override.adapter_name == "Anthropic"
      assert override.model == "claude"
      assert override.config == %{"anthropic_key" => "sk-typed"}
    end

    test "blank credentials inherit the instance config for the configured provider" do
      override =
        Parser.resolve_override(
          %{"adapter" => "vllm", "model" => "", "api_key" => "", "endpoint_url" => ""},
          @vllm_default
        )

      # The instance's own adapter, not the generic ChatOpenAI — that module is
      # what resolves the gateway endpoint and bearer token from the environment.
      assert override.adapter == FakeGatewayAdapter
      assert override.adapter_name == "vLLM"
      assert override.model == "gemma-4-26b-a4b-it"
      assert override.config == %{"openai_key" => "sk-from-release-env"}
    end

    test "a typed key overrides the inherited one" do
      override =
        Parser.resolve_override(
          %{"adapter" => "vllm", "model" => "m", "api_key" => "sk-typed"},
          @vllm_default
        )

      assert override.config["openai_key"] == "sk-typed"
    end

    test "another provider does not inherit the configured provider's credentials" do
      override =
        Parser.resolve_override(
          %{"adapter" => "anthropic", "model" => "claude", "api_key" => ""},
          @vllm_default
        )

      assert override.adapter == LangChain.ChatModels.ChatAnthropic
      refute Map.has_key?(override.config, "openai_key")
      assert override.config == %{}
    end

    test "a typed endpoint URL lands under the key the chain reads" do
      override =
        Parser.resolve_override(
          %{"adapter" => "vllm", "model" => "m", "endpoint_url" => "https://llm.example.com/v1"},
          @vllm_default
        )

      assert override.config["endpoint"] == "https://llm.example.com/v1"
    end

    test "Ollama has no API-key slot, so a typed key is dropped rather than misfiled" do
      override =
        Parser.resolve_override(
          %{"adapter" => "ollama", "model" => "llama3", "api_key" => "sk-ignored"},
          @no_default
        )

      assert override.config == %{}
    end

    test "a whitespace-only model falls back to the configured one" do
      override = Parser.resolve_override(%{"adapter" => "vllm", "model" => "   "}, @vllm_default)

      assert override.model == "gemma-4-26b-a4b-it"
    end

    test "an unknown submitted adapter falls back to the instance default" do
      override = Parser.resolve_override(%{"adapter" => "bogus", "model" => "m"}, @vllm_default)

      assert override.adapter == FakeGatewayAdapter
    end

    test "an unknown submitted adapter with no instance default falls back to OpenAI" do
      override = Parser.resolve_override(%{"adapter" => "bogus", "model" => "m"}, @no_default)

      assert override.adapter == LangChain.ChatModels.ChatOpenAI
    end

    test "missing params never raise" do
      override = Parser.resolve_override(%{}, @no_default)

      assert override.adapter == LangChain.ChatModels.ChatOpenAI
      assert override.model == ""
      assert override.config == %{}
    end
  end

  describe "provider_label/1" do
    test "humanizes known slugs" do
      assert Parser.provider_label("google_ai") == "Google AI"
      assert Parser.provider_label("vllm") == "vLLM"
    end

    test "returns nil for anything else" do
      assert Parser.provider_label("mistral") == nil
      assert Parser.provider_label(nil) == nil
    end
  end
end
