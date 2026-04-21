defmodule Autolaunch.Repo.Migrations.CutOverToMirroredXmtpRooms do
  use Ecto.Migration

  def change do
    alter table(:autolaunch_human_users) do
      add :xmtp_inbox_id, :string
    end

    create unique_index(:autolaunch_human_users, [:xmtp_inbox_id])

    drop_if_exists table(:xmtp_message_logs)
    drop_if_exists table(:xmtp_room_memberships)
    drop_if_exists table(:xmtp_rooms)

    create table(:xmtp_rooms) do
      add :room_key, :string, null: false
      add :xmtp_group_id, :string
      add :name, :string, null: false
      add :status, :string, null: false, default: "active"
      add :presence_ttl_seconds, :integer, null: false, default: 120

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:xmtp_rooms, [:room_key])
    create unique_index(:xmtp_rooms, [:xmtp_group_id])
    create constraint(:xmtp_rooms, :xmtp_rooms_presence_ttl_seconds_check,
             check: "presence_ttl_seconds >= 15 AND presence_ttl_seconds <= 3600"
           )

    create table(:xmtp_messages) do
      add :room_id, references(:xmtp_rooms, on_delete: :delete_all), null: false
      add :xmtp_message_id, :string, null: false
      add :sender_inbox_id, :string, null: false
      add :sender_wallet_address, :string
      add :sender_label, :string
      add :sender_type, :string, null: false
      add :body, :text, null: false
      add :sent_at, :utc_datetime_usec, null: false
      add :raw_payload, :map, null: false, default: %{}
      add :moderation_state, :string, null: false, default: "visible"
      add :reply_to_message_id, references(:xmtp_messages, on_delete: :nilify_all)
      add :reactions, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:xmtp_messages, [:xmtp_message_id])
    create index(:xmtp_messages, [:room_id, :inserted_at])
    create index(:xmtp_messages, [:reply_to_message_id])

    create table(:xmtp_membership_commands) do
      add :room_id, references(:xmtp_rooms, on_delete: :delete_all), null: false
      add :human_user_id, references(:autolaunch_human_users, on_delete: :nilify_all)
      add :op, :string, null: false
      add :xmtp_inbox_id, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :attempt_count, :integer, null: false, default: 0
      add :last_error, :string

      timestamps(type: :utc_datetime_usec)
    end

    create index(:xmtp_membership_commands, [:room_id, :status])
    create index(:xmtp_membership_commands, [:xmtp_inbox_id])

    create constraint(:xmtp_membership_commands, :xmtp_membership_commands_op_check,
             check: "op IN ('add_member', 'remove_member')"
           )

    create constraint(:xmtp_membership_commands, :xmtp_membership_commands_status_check,
             check: "status IN ('pending', 'processing', 'done', 'failed')"
           )

    create table(:xmtp_presence_heartbeats) do
      add :room_id, references(:xmtp_rooms, on_delete: :delete_all), null: false
      add :human_user_id, references(:autolaunch_human_users, on_delete: :delete_all), null: false
      add :xmtp_inbox_id, :string, null: false
      add :last_seen_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :evicted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:xmtp_presence_heartbeats, [:room_id, :xmtp_inbox_id],
             name: :xmtp_presence_heartbeats_room_inbox_uidx
           )

    create index(:xmtp_presence_heartbeats, [:room_id, :expires_at],
             name: :xmtp_presence_heartbeats_active_expiry_idx
           )
  end
end
