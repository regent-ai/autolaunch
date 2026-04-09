defmodule Autolaunch.Xmtp.RoomMembership do
  @moduledoc false
  use Autolaunch.Schema

  alias Autolaunch.Xmtp.Room

  schema "autolaunch_xmtp_room_memberships" do
    field :wallet_address, :string
    field :inbox_id, :string
    field :membership_state, :string, default: "joined"
    field :last_seen_at, :utc_datetime_usec

    belongs_to :room, Room

    timestamps()
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:room_id, :wallet_address, :inbox_id, :membership_state, :last_seen_at])
    |> validate_required([:room_id, :wallet_address, :inbox_id, :membership_state])
    |> validate_inclusion(:membership_state, ["joined", "kicked"])
    |> unique_constraint([:room_id, :wallet_address])
    |> unique_constraint([:room_id, :inbox_id])
  end
end
