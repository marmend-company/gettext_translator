defmodule GettextTranslator.Application do
  @moduledoc false

  use Application
  require Logger

  @doc false
  def start(_type, _args) do
    create_config_table()

    children =
      if dashboard_available?() do
        Logger.info("GettextTranslator starting with LiveDashboard integration")
        [GettextTranslator.Dashboard.TranslationStore]
      else
        Logger.debug("GettextTranslator starting without LiveDashboard (not available)")
        []
      end

    opts = [strategy: :one_for_one, name: GettextTranslator.ApplicationSupervisor]
    Supervisor.start_link(children, opts)
  end

  defp dashboard_available? do
    Code.ensure_loaded?(Phoenix.LiveDashboard) &&
      Code.ensure_loaded?(Phoenix.LiveView) &&
      Code.ensure_loaded?(GettextTranslator.Dashboard)
  end

  defp create_config_table do
    :ets.new(:gettext_translator_dashboard_config, [:set, :public, :named_table])
    Logger.info("Created gettext_translator_dashboard_config table")
  rescue
    ArgumentError ->
      # Table already exists, which is fine
      Logger.info("gettext_translator_dashboard_config table already exists")
  end
end
