# XMTP Room Alignment

This is the shared room plan for Autolaunch, Platform, and Techtree.

## Goal

All three apps use one product-owned mirror model for XMTP rooms:

- homepage room for people
- homepage room for agents
- app-owned shared rooms:
  - Autolaunch: auctions and tokens
  - Platform: companies
  - Techtree: branches and nodes

There is no parallel shared-room runtime in the Phoenix app. Phoenix reads and writes the mirror tables. The XMTP worker or sidecar creates rooms, ingests messages, leases membership commands, and resolves those commands through internal endpoints.

## Tables

Each app should keep these Ecto schemas and table meanings aligned with Techtree.

`xmtp_rooms`

- `room_key`: stable product key, such as `public-chatbox`, `agent-chatbox`, `auction:<id>`, `token:<id>`, `company:<id>`, `branch:<id>`, or `node:<id>`
- `xmtp_group_id`: XMTP group identifier, nullable until the worker has created the group
- `name`: room display name
- `status`: string, currently `active` for readable rooms
- `presence_ttl_seconds`: heartbeat eviction window, default `120`

`xmtp_messages`

- `room_id`
- `xmtp_message_id`
- `sender_inbox_id`
- `sender_wallet_address`
- `sender_label`
- `sender_type`: `:human`, `:agent`, or `:system`
- `body`
- `sent_at`
- `raw_payload`
- `moderation_state`
- `reply_to_message_id`
- `reactions`

`xmtp_membership_commands`

- `room_id`
- `human_user_id`
- `op`: `add_member` or `remove_member`
- `xmtp_inbox_id`
- `status`: `pending`, `processing`, `done`, or `failed`
- `attempt_count`
- `last_error`

`xmtp_presence_heartbeats`

- `room_id`
- `human_user_id`
- `xmtp_inbox_id`
- `last_seen_at`
- `expires_at`
- `evicted_at`

Historical shared-room tables can remain in place until a separate data-retention decision exists, but app code should not read or write them after the mirror cutover.

## Boundary Rules

- Request payloads, internal endpoint params, CLI payloads, wallet actions, Oban args, and shared helper inputs use string keys.
- Boundary helpers accept the canonical string-key shape only.
- Atom keys stay inside owned structs, Ecto schemas, and internal records.
- Do not add fallback behavior, dual shapes, old field aliases, or tests that preserve old shapes.

## Phoenix Standards

- LiveViews read panel state from the product public-room context.
- Homepage chat stays readable when signed out.
- Joining queues a mirror membership command.
- Posting is allowed only when the mirror membership state is joined.
- Saved mirror messages broadcast one public-site refresh event and update the homepage immediately.
- Browser hooks may animate and heartbeat, but they do not own signing, membership, room state, or message state.

## Ecto Standards

- Use product schema conventions and `:utc_datetime_usec` timestamps.
- Keep changesets focused on the current fields only.
- Keep room and message helpers pure where possible; database writes happen in the mirror context.
- Migrations must preserve live data. Do not drop historical XMTP tables as part of the cutover.

## Oban Standards

- Platform and Techtree Oban jobs that touch rooms should store only string-key args and stable IDs.
- Workers should reload rooms, humans, and commands from the database.
- Workers should resolve `xmtp_membership_commands` as `done` or `failed`; they should not mutate homepage state directly.
- Autolaunch currently does not need an Oban worker for this room path. If one is added later, it follows the same string-key args and database-reload rule.
