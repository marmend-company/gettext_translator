defmodule GettextTranslator.MixProject do
  use Mix.Project

  def project do
    [
      app: :gettext_translator,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Elixir Gettext add-on for translations with LLMs",
      package: package(),
      source_url: "https://github.com/max-marmend/gettext-translator",
      docs: [extras: ["README.md"], main: "readme"]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp package do
    [
      name: :gettext_translator,
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/max-marmend/gettext-translator"},
      maintainers: ["Max Panov"],
      files: ~w(lib mix.exs README.md LICENSE)
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:expo, "~> 1.1.0"},
      {:langchain, "0.3.1"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", runtime: false}
    ]
  end
end
