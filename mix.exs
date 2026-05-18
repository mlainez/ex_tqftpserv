defmodule ExTqftpserv.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :ex_tqftpserv,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Supervises the Qualcomm tqftpserv daemon under MuonTrap.",
      package: package()
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
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/mlainez/ex_tqftpserv"}
    ]
  end
end
