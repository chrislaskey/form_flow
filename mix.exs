defmodule FormFlow.MixProject do
  use Mix.Project

  @version "0.18.0"
  @source_url "https://github.com/chrislaskey/form_flow"

  def project do
    [
      app: :form_flow,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      # Extracts colocated hooks (phoenix-colocated/form_flow)
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "FormFlow",
      description: description(),
      package: package(),
      docs: docs(),
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:phoenix_live_view, ">= 1.1.0"},
      # phoenix_live_view already brings this along; declared because
      # FormFlow.Web.Downloads calls Phoenix.Controller.send_download/3 directly
      {:phoenix, ">= 1.7.0"},
      {:phoenix_html, ">= 4.0.0"},
      {:plug, ">= 1.0.0"},
      {:ecto, ">= 3.0.0"},
      # Required for FormFlow.Data.Migration, which runs inside the parent app's
      # migrations. Any app with a repo already depends on it.
      {:ecto_sql, ">= 3.0.0"},
      {:phoenix_select, ">= 0.0.0"},
      {:slab, ">= 0.0.0"},
      {:dynamic_form, ">= 0.0.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:mix_credence, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp description do
    "Batteries included library for creating dynamic form-based user flows in Phoenix"
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      # priv carries the prebuilt editor bundle served by FormFlow.Web.Assets;
      # without it the flow editor cannot load
      files: ~w(lib priv guides mix.exs README.md LICENSE.md CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "LICENSE.md",
        "guides/usage.md",
        "guides/reference.md",
        "guides/development.md",
        "guides/neo4j.md"
      ],
      groups_for_extras: [
        Guides: ~r{guides/}
      ]
    ]
  end
end
