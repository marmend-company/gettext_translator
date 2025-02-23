defmodule GettextTranslator.Util.Helper do
  @moduledoc """
  Helper functions
  """

  @lc_messages "LC_MESSAGES"
  def lc_messages, do: @lc_messages

  def empty_string?(nil), do: true
  def empty_string?(str) when is_binary(str), do: String.trim(str) == ""
  def empty_string?(str) when is_binary(str), do: false
end
