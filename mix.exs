defmodule GettextTranslator.MixProject do
  use Mix.Project

  def project do
    [
      app: :gettext_translator,
      version: "0.1.1",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Elixir Gettext add-on for translations with LLMs",
      package: package(),
      source_url: "https://github.com/marmend-company/gettext_translator",
      docs: [extras: ["README.md", "CHANGELOG.md", "CONTRIBUTING.md"], main: "readme"]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
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
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", runtime: false}
    ]
  end
end
