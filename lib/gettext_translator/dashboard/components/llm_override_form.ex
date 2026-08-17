defmodule GettextTranslator.Dashboard.Components.LLMOverrideForm do
  @moduledoc """
  Component for overriding LLM provider settings per session.
  """
  use Phoenix.Component

  alias GettextTranslator.Util.Parser

  attr(:llm_override, :map, default: nil)
  attr(:llm_provider_info, :map, required: true)
  attr(:show_override_form, :boolean, default: false)

  # Instance configuration, from `GettextTranslator.Util.Parser.instance_default/0`.
  # When `:provider` is set the form opens on that adapter with its model filled
  # in, so the common case — "translate with the gateway this release is already
  # wired to" — is a single click instead of four fields.
  attr(:llm_defaults, :map,
    default: %{provider: nil, model: nil, adapter: nil, endpoint_config: %{}}
  )

  def render(assigns) do
    ~H"""
    <div class="llm-override-card">
      <div class="llm-override-header">
        <button
          type="button"
          class="btn btn-link p-0"
          phx-click="toggle_llm_override_form"
        >
          <%= if @show_override_form do %>
            Hide LLM Override
          <% else %>
            Override LLM Provider
          <% end %>
        </button>
      </div>

      <%= if @llm_override do %>
        <div class="llm-override-active">
          <span class="llm-override-active-label">Active Override:</span>
          <span class="llm-override-active-value">
            {@llm_override.adapter_name} — {@llm_override.model}
          </span>
          <button
            type="button"
            class="btn btn-secondary btn-sm"
            phx-click="clear_llm_override"
          >
            Clear Override
          </button>
        </div>
      <% end %>

      <%= if @show_override_form do %>
        <form phx-submit="update_llm_override" phx-change="noop" class="llm-override-form">
          <div class="form-row">
            <div class="form-group" style="flex: 1;">
              <label class="form-label">Adapter</label>
              <select name="adapter" class="form-control form-select">
                <option value="openai" selected={@llm_defaults.provider == "openai"}>
                  OpenAI
                </option>
                <option value="anthropic" selected={@llm_defaults.provider == "anthropic"}>
                  Anthropic
                </option>
                <option value="ollama" selected={@llm_defaults.provider == "ollama"}>
                  Ollama
                </option>
                <option value="google_ai" selected={@llm_defaults.provider == "google_ai"}>
                  Google AI
                </option>
                <option value="vllm" selected={@llm_defaults.provider == "vllm"}>
                  vLLM (OpenAI-compatible){if @llm_defaults.provider == "vllm", do: " — configured"}
                </option>
              </select>
            </div>

            <div class="form-group" style="flex: 1;">
              <label class="form-label">Model Name</label>
              <input
                type="text"
                name="model"
                class="form-control"
                value={@llm_defaults.model}
                placeholder="e.g. gpt-4, claude-sonnet-4-5-20250929, llama3"
                required
              />
            </div>
          </div>

          <div class="form-row">
            <div class="form-group" style="flex: 1;">
              <label class="form-label">API Key {credential_hint(@llm_defaults)}</label>
              <input
                type="password"
                name="api_key"
                class="form-control"
                placeholder={credential_placeholder(@llm_defaults)}
              />
            </div>

            <div class="form-group" style="flex: 1;">
              <label class="form-label">Endpoint URL {credential_hint(@llm_defaults)}</label>
              <input
                type="text"
                name="endpoint_url"
                class="form-control"
                placeholder={endpoint_placeholder(@llm_defaults)}
              />
            </div>
          </div>

          <div class="form-actions">
            <button type="submit" class="btn btn-primary btn-sm">
              Apply Override
            </button>
          </div>
        </form>
      <% end %>
    </div>
    """
  end

  # These name the provider that inheritance applies to rather than saying a bare
  # "optional", because the form is `phx-change="noop"`: switching the Adapter
  # dropdown does not re-render, so any copy phrased about "the current selection"
  # would keep asserting itself after the operator picked something else. Only the
  # configured provider inherits — see Parser.resolve_override/2 — and an
  # unqualified "optional" left beside a freshly-selected Anthropic would talk an
  # operator out of pasting the key that request genuinely needs.
  #
  # Ollama is already named in the base hint, and it has no API-key slot at all,
  # so an instance defaulting to it must not read "optional for Ollama and Ollama".
  defp credential_hint(%{provider: nil}), do: "(optional for Ollama)"
  defp credential_hint(%{provider: "ollama"}), do: "(optional for Ollama)"

  defp credential_hint(%{provider: provider}),
    do: "(optional for Ollama and #{label(provider)})"

  defp credential_placeholder(%{provider: nil}), do: "sk-... or your provider API key"

  defp credential_placeholder(%{provider: provider}),
    do: "sk-... — blank uses the configured key (#{label(provider)} only)"

  defp endpoint_placeholder(%{provider: nil}),
    do: "e.g. https://llm.example.com/v1/chat/completions for vLLM"

  defp endpoint_placeholder(%{provider: provider}),
    do: "blank uses the configured endpoint (#{label(provider)} only)"

  # "google_ai" is not what anyone wants to read in a form label.
  defp label(provider), do: Parser.provider_label(provider) || provider
end
