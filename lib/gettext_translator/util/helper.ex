defmodule GettextTranslator.Util.Helper do
  @moduledoc """
  Helper functions
  """

  @config_table :gettext_translator_dashboard_config
  @lc_messages "LC_MESSAGES"
  def lc_messages, do: @lc_messages

  def empty_string?(nil), do: true
  def empty_string?(str) when is_binary(str), do: String.trim(str) == ""
  def empty_string?(str) when is_binary(str), do: false

  def store_config(key, value) when not is_nil(value) do
    ensure_config_table()
    :ets.insert(@config_table, {key, value})
  end

  def store_config(_, _), do: :ok

  def get_config(key) do
    ensure_config_table()

    case :ets.lookup(@config_table, key) do
      [{^key, value}] -> value
      _ -> nil
    end
  end

  def ensure_config_table do
    case :ets.info(@config_table) do
      :undefined ->
        # Table doesn't exist, create it
        :ets.new(@config_table, [:set, :public, :named_table])
        true

      _ ->
        # Table already exists
        true
    end
  catch
    # Handle errors (e.g., table already exists)
    :error, _ -> true
  end
end
