# Local Observability (Logs + Metrics)

This folder spins up a **local centralized observability stack** suitable for multi-node debugging:

- **Grafana** (dashboards)
- **Prometheus** (metrics scraping)
- **Loki** (centralized logs)
- **Promtail** (log shipper that tails node log files)

## What you get immediately

- Per-node Prometheus metrics via the built-in Silica monitoring server (`/metrics`).
- Centralized log search (by `level`, `target`, and message) in Grafana via Loki.

## Run it

1) Start the stack:

- From the repo root: `infrastructure/observability/local/`

2) Run one or more nodes on the host and point them at this stack:

- Set a monitoring port per node:
  - `CHERT_MONITORING_PORT=8080` (node 1)
  - `CHERT_MONITORING_PORT=8081` (node 2)

- Enable file logging for promtail to pick up:
  - `CHERT_LOG_DIR=infrastructure/observability/local/logs/node1`
  - `CHERT_LOG_DIR=infrastructure/observability/local/logs/node2`

- Optional:
  - `CHERT_LOG_FORMAT=pretty|json` (stdout only)
  - `RUST_LOG=info,silica::consensus=debug` (filtering)

## Where things show up

- Grafana: http://localhost:3000 (admin/admin)
- Prometheus: http://localhost:9090
- Loki: http://localhost:3100

In Grafana:
- Explore → **Loki** to query logs.
- Explore → **Prometheus** to query metrics (e.g. `network_messages_received_total`).

## Notes

- Prometheus scrapes `host.docker.internal:8080/metrics` by default.
  - On Linux this is wired via Docker’s `host-gateway` mapping.
  - Add more targets in `config/prometheus.yml` as you run more nodes.

- Logs are discovered from `./logs/**/*.log` mounted into promtail.
  - Each node writes JSON logs to `${CHERT_LOG_DIR}/silica.log` (rolled daily).
