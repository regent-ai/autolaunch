defmodule Autolaunch.Repo.Migrations.AlignXmtpRoomsToMirrorModel do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE xmtp_rooms
      ADD COLUMN IF NOT EXISTS xmtp_group_id varchar(255),
      ADD COLUMN IF NOT EXISTS name varchar(255),
      ADD COLUMN IF NOT EXISTS presence_ttl_seconds integer DEFAULT 120
    """)

    execute("""
    ALTER TABLE xmtp_rooms
      ALTER COLUMN conversation_id DROP NOT NULL,
      ALTER COLUMN agent_wallet_address DROP NOT NULL,
      ALTER COLUMN agent_inbox_id DROP NOT NULL,
      ALTER COLUMN room_name DROP NOT NULL,
      ALTER COLUMN created_at_ns DROP NOT NULL,
      ALTER COLUMN last_activity_ns DROP NOT NULL
    """)

    execute("""
    UPDATE xmtp_rooms
       SET name = COALESCE(NULLIF(name, ''), NULLIF(room_name, ''), room_key),
           xmtp_group_id = COALESCE(NULLIF(xmtp_group_id, ''), NULLIF(conversation_id, '')),
           presence_ttl_seconds = COALESCE(presence_ttl_seconds, 120)
    """)

    execute("""
    INSERT INTO xmtp_rooms (
      room_key,
      xmtp_group_id,
      name,
      status,
      capacity,
      presence_ttl_seconds,
      snapshot,
      inserted_at,
      updated_at
    )
    VALUES (
      'public-chatbox',
      'xmtp-public-chatbox',
      'Autolaunch Room',
      'active',
      200,
      120,
      '{}',
      now(),
      now()
    )
    ON CONFLICT (room_key) DO UPDATE
       SET xmtp_group_id = COALESCE(xmtp_rooms.xmtp_group_id, EXCLUDED.xmtp_group_id),
           name = COALESCE(NULLIF(xmtp_rooms.name, ''), EXCLUDED.name),
           presence_ttl_seconds = COALESCE(xmtp_rooms.presence_ttl_seconds, EXCLUDED.presence_ttl_seconds),
           updated_at = now()
    """)

    execute("""
    CREATE UNIQUE INDEX IF NOT EXISTS xmtp_rooms_xmtp_group_id_index
      ON xmtp_rooms (xmtp_group_id)
      WHERE xmtp_group_id IS NOT NULL
    """)

    execute(
      "ALTER TABLE xmtp_rooms DROP CONSTRAINT IF EXISTS xmtp_rooms_presence_ttl_seconds_check"
    )

    create constraint(:xmtp_rooms, :xmtp_rooms_presence_ttl_seconds_check,
             check: "presence_ttl_seconds >= 15 AND presence_ttl_seconds <= 3600"
           )

    create_if_not_exists table(:xmtp_messages) do
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

    create_if_not_exists unique_index(:xmtp_messages, [:xmtp_message_id])
    create_if_not_exists index(:xmtp_messages, [:room_id, :inserted_at])
    create_if_not_exists index(:xmtp_messages, [:reply_to_message_id])

    create_if_not_exists table(:xmtp_membership_commands) do
      add :room_id, references(:xmtp_rooms, on_delete: :delete_all), null: false
      add :human_user_id, references(:autolaunch_human_users, on_delete: :nilify_all)
      add :op, :string, null: false
      add :xmtp_inbox_id, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :attempt_count, :integer, null: false, default: 0
      add :last_error, :text

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists index(:xmtp_membership_commands, [:room_id, :status])
    create_if_not_exists index(:xmtp_membership_commands, [:xmtp_inbox_id])

    execute(
      "ALTER TABLE xmtp_membership_commands DROP CONSTRAINT IF EXISTS xmtp_membership_commands_op_check"
    )

    create constraint(:xmtp_membership_commands, :xmtp_membership_commands_op_check,
             check: "op IN ('add_member', 'remove_member')"
           )

    execute(
      "ALTER TABLE xmtp_membership_commands DROP CONSTRAINT IF EXISTS xmtp_membership_commands_status_check"
    )

    create constraint(:xmtp_membership_commands, :xmtp_membership_commands_status_check,
             check: "status IN ('pending', 'processing', 'done', 'failed')"
           )

    create_if_not_exists table(:xmtp_presence_heartbeats) do
      add :room_id, references(:xmtp_rooms, on_delete: :delete_all), null: false
      add :human_user_id, references(:autolaunch_human_users, on_delete: :delete_all), null: false
      add :xmtp_inbox_id, :string, null: false
      add :last_seen_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :evicted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists unique_index(:xmtp_presence_heartbeats, [:room_id, :xmtp_inbox_id],
                           name: :xmtp_presence_heartbeats_room_inbox_uidx
                         )

    create_if_not_exists index(:xmtp_presence_heartbeats, [:room_id, :expires_at],
                           where: "evicted_at IS NULL",
                           name: :xmtp_presence_heartbeats_active_expiry_idx
                         )
  end

  def down do
    :ok
  end
end
