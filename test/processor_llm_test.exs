defmodule GettextTranslator.Processor.LLMTest do
  use ExUnit.Case, async: true

  alias GettextTranslator.Processor.LLM

  describe "build_llm_attrs/1" do
    test "includes model and temperature" do
      attrs = LLM.build_llm_attrs(%{model: "gpt-4", temperature: 0.2, config: %{}})

      assert attrs.model == "gpt-4"
      assert attrs.temperature == 0.2
    end

    test "omits endpoint when no custom base URL is configured" do
      attrs = LLM.build_llm_attrs(%{model: "gpt-4", temperature: 0, config: %{}})

      refute Map.has_key?(attrs, :endpoint)
    end

    test "threads the vLLM endpoint from the 'endpoint' config key (dashboard override)" do
      attrs =
        LLM.build_llm_attrs(%{
          model: "gemma-4-26b-a4b-it",
          temperature: 0,
          config: %{"endpoint" => "https://llm.example.com/v1/chat/completions"}
        })

      assert attrs.endpoint == "https://llm.example.com/v1/chat/completions"
    end

    test "threads the endpoint from the documented 'openai_endpoint' config key" do
      attrs =
        LLM.build_llm_attrs(%{
          model: "gemma-4-26b-a4b-it",
          temperature: 0,
          config: %{"openai_endpoint" => "https://llm.example.com/v1/chat/completions"}
        })

      assert attrs.endpoint == "https://llm.example.com/v1/chat/completions"
    end

    test "includes retry_count only when provided" do
      with_retry = LLM.build_llm_attrs(%{model: "m", temperature: 0, retry_count: 3, config: %{}})
      without_retry = LLM.build_llm_attrs(%{model: "m", temperature: 0, config: %{}})

      assert with_retry.retry_count == 3
      refute Map.has_key?(without_retry, :retry_count)
    end

    test "tolerates a nil config" do
      attrs = LLM.build_llm_attrs(%{model: "m", temperature: 0, config: nil})

      assert attrs.model == "m"
      refute Map.has_key?(attrs, :endpoint)
    end
  end
end
