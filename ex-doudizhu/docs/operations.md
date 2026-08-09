# Operations

## Deployment model

The first supported production topology is one Phoenix node and one PostgreSQL database. Do not run multiple application nodes until authoritative per-game ownership and cross-node routing are implemented.

Required environment variables:

```text
DATABASE_URL=ecto://USER:PASSWORD@HOST/DATABASE
SECRET_KEY_BASE=<mix phx.gen.secret output>
PHX_HOST=games.example.com
PHX_SERVER=true
PORT=4000
POOL_SIZE=10
```

TLS should terminate at the hosting proxy. Ensure the proxy supports WebSocket upgrades and does not impose a turn-breaking idle timeout.

## Container release

```sh
docker build -t doudizhu .
docker run --rm \
  -e DATABASE_URL \
  -e SECRET_KEY_BASE \
  -e PHX_HOST \
  -e PHX_SERVER=true \
  -p 4000:4000 \
  doudizhu
```

Run migrations before routing traffic:

```sh
bin/migrate
```

## Health

```sh
curl --fail https://games.example.com/api/health
```

The HTTP health endpoint proves the Endpoint is serving. Database and game command health should additionally be monitored from Ecto and command Telemetry events.

## Recovery model

- PostgreSQL is authoritative after a transition commits.
- `GameServer` processes are caches/serializers and reload explicit versioned snapshots on restart.
- Accepted commands are durable and idempotent by `(game_id, command_id)`.
- Committed observations are written to `outbox_messages` before publication.
- The outbox publisher retries rows with no `published_at` timestamp.
- Clients use game sequence numbers and request `resync` after a gap.

If an individual game process is unhealthy, terminate it under `Doudizhu.Games.GameSupervisor`; the next command/join starts it from the stored snapshot.

## Backups

Take regular encrypted PostgreSQL backups with retention appropriate to the deployment:

```sh
pg_dump --format=custom --no-owner "$DATABASE_URL" > doudizhu-$(date +%F-%H%M).dump
```

Test restoration periodically into an isolated database:

```sh
createdb doudizhu_restore_test
pg_restore --no-owner --dbname=doudizhu_restore_test backup.dump
```

After restore, run current migrations and exercise snapshot decode/recovery in a staging release before promoting the database.

Backups contain private hands, deal history, guest identities, and controller records. Treat them as sensitive data.

## Snapshot upgrades

`games.snapshot_codec_version` and each encoded snapshot's `codec_version` must be understood by the release before deployment. For a breaking storage change:

1. deploy code that reads old and new versions;
2. migrate snapshots transactionally or lazily;
3. verify representative games recover;
4. only later remove the old decoder.

Never persist opaque Erlang terms as a migration shortcut.

## Telemetry

The application emits:

- `[:doudizhu, :command, :dispatch, :start | :stop | :exception]`;
- `[:doudizhu, :games]` with active process count;
- standard Phoenix Endpoint, socket, Channel, VM, and Ecto query events.

Monitor command duration/outcome, database queue/query time, active game processes, Channel joins, crash rates, and unpublished outbox age/count.

Do not attach complete command payloads, hands, bottom cards, tokens, or private snapshots to logs or telemetry.

## Incident checks

1. Verify `/api/health` and PostgreSQL connectivity.
2. Check Ecto pool saturation and query latency.
3. Count unpublished outbox rows and oldest insertion time.
4. Check game process crash logs by game ID only.
5. Confirm clients can `resync` and continue from the persisted sequence.
6. Restore from backup only for durable database loss/corruption, not for an individual process crash.
