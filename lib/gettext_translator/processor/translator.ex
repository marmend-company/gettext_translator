defmodule GettextTranslator.Processor.Translator do
  @moduledoc """
  Translator behavior.
  """

  @type endpoint() :: %{
          adapter: module(),
          model: String.t(),
          temperature: float(),
          config: map()
        }

  @type provider() :: %{
          endpoint: endpoint(),
          persona: String.t(),
          style: String.t(),
          ignored_codes: list(String.t())
        }

  @type opts() :: %{
          message: String.t(),
          language_code: String.t()
        }

  @callback translate(provider(), opts()) :: {:ok, String.t()} | {:error, any()}
end
