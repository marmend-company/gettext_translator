defmodule GettextTranslator.MixProject do
  use Mix.Project

  def project do
    [
      app: :gettext_translator,
      version: "0.4.4",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "Elixir Gettext add-on for translations with LLMs and LiveDashboard integration. Suport making pull request from livedashboard.",
      package: package(),
      source_url: "https://github.com/marmend-company/gettext_translator",
      docs: [
        extras: ["README.md", "CHANGELOG.md", "CONTRIBUTING.md"],
        main: "readme",
        groups_for_modules: [
          Core: [
            GettextTranslator,
            GettextTranslator.Processor,
            GettextTranslator.Processor.LLM,
            GettextTranslator.Processor.Translator,
            GettextTranslator.Util.Helper,
            GettextTranslator.Util.Parser,
            GettextTranslator.Util.PoHelper,
            GettextTranslator.Util.MakePullRequest,
            GettextTranslator.Util.PathHelper,
            GettextTranslator.Util.GitHub,
            GettextTranslator.Util.GitLab
          ],
          Dashboard: [
            GettextTranslator.Dashboard,
            GettextTranslator.Dashboard.DashboardPage,
            GettextTranslator.Supervisor
          ],
          Operation: [
            GettextTranslator.Store,
            GettextTranslator.Store.Translation,
            GettextTranslator.Store.Changelog
          ],
          "Mix Tasks": [
            Mix.Tasks.GettextTranslator.Run
          ]
        ]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {GettextTranslator.Application, []}
    ]
  end

  defp package do
    [
      name: :gettext_translator,
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/marmend-company/gettext_translator"},
      maintainers: ["Max Panov"],
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md CONTRIBUTING.md)
    ]
  end

  defp deps do
    [
      {:expo, "~> 1.1.0"},
      {:langchain, "0.3.1"},
      # Dashboard dependencies (all optional)
      {:phoenix_live_dashboard, ">= 0.6.0", optional: true},
      {:phoenix_live_view, ">= 0.17.0", optional: true},
      {:git_cli, "~> 0.3", optional: true},
      {:finch, "~> 0.16"},
      # Dev dependencies
      {:ex_doc, ">= 0.0.0", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
