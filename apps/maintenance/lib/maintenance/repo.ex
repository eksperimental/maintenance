defmodule Maintenance.Repo do
  use Ecto.Repo,
    otp_app: :maintenance,
    adapter: CubEcto
end
