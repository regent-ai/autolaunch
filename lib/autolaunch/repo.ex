defmodule Autolaunch.Repo do
  use Ecto.Repo,
    otp_app: :autolaunch,
    adapter: Ecto.Adapters.Postgres
end
