defmodule Maintenance.Entries.Entry do
  use Ecto.Schema
  import Ecto.Changeset

  schema "entries" do
    field :date_time, :utc_datetime
    field :uptime, :integer

    timestamps(inserted_at: false, updated_at: false)
  end

  @doc false
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:date_time, :uptime])
    |> validate_required([:date_time, :uptime])
  end
end
