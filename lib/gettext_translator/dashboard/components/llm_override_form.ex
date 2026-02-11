defmodule GettextTranslator.Dashboard.Components.LLMOverrideForm do
  @moduledoc """
  Component for overriding LLM provider settings per session.
  """
  use Phoenix.Component

  attr(:llm_override, :map, default: nil)
  attr(:llm_provider_info, :map, required: true)
  attr(:show_override_form, :boolean, default: false)

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
                <option value="openai">OpenAI</option>
                <option value="anthropic">Anthropic</option>
                <option value="ollama">Ollama</option>
                <option value="google_ai">Google AI</option>
              </select>
            </div>

            <div class="form-group" style="flex: 1;">
              <label class="form-label">Model Name</label>
              <input
                type="text"
                name="model"
                class="form-control"
                placeholder="e.g. gpt-4, claude-sonnet-4-5-20250929, llama3"
                required
              />
            </div>
          </div>

          <div class="form-row">
            <div class="form-group" style="flex: 1;">
              <label class="form-label">API Key (optional for Ollama)</label>
              <input
                type="password"
                name="api_key"
                class="form-control"
                placeholder="sk-... or your provider API key"
              />
            </div>

            <div class="form-group" style="flex: 1;">
              <label class="form-label">Endpoint URL (optional)</label>
              <input
                type="text"
                name="endpoint_url"
                class="form-control"
                placeholder="e.g. http://localhost:11434 for Ollama"
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
end
