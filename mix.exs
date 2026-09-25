defmodule ExTqftpserv.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/mlainez/ex_tqftpserv"

  def project do
    [
      app: :ex_tqftpserv,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Supervises the Qualcomm tqftpserv daemon under MuonTrap.",
      package: package(),
      source_url: @source_url,
      docs: [main: "readme", extras: ["README.md"], source_ref: "v#{@version}"]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:muontrap, "~> 1.0"}
    ]
  end

  defp package do
    [
      files: ~w(lib mix.exs README.md LICENSE),
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
