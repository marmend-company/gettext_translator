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
end
