# ELK Logs

A self-hosted ELK (Elasticsearch, Logstash, Kibana) stack for collecting application logs over the network. Logs are received by Logstash on TCP 5001 / UDP 5002, indexed into daily `app-logs-YYYY.MM.DD` indices, retained for 30 days via ILM, and queried through Kibana.

## Components

| Service              | Image                                                  | Purpose                                                       | Host port              |
| -------------------- | ------------------------------------------------------ | ------------------------------------------------------------- | ---------------------- |
| `elasticsearch`      | `docker.elastic.co/elasticsearch/elasticsearch:9.4.1`  | Storage + search                                              | 9200 (127.0.0.1)       |
| `logstash`           | `docker.elastic.co/logstash/logstash:9.4.1`            | Log ingestion pipeline                                        | 5001/tcp, 5002/udp (127.0.0.1) |
| `kibana`             | `docker.elastic.co/kibana/kibana:9.4.1`                | UI                                                            | 5601 (127.0.0.1)       |
| `elasticsearch-init` | `curlimages/curl`                                      | One-shot bootstrap (ILM policy, index template, roles, users) | —                      |

All published ports are bound to `127.0.0.1` only. To accept logs from other machines, either change the port mappings to `0.0.0.0` in `docker-compose.yml` or proxy them through nginx-proxy-manager (NPM supports TCP/UDP streams for ports 5001/5002).

## File layout

```
elk-logs/
├── docker-compose.yml      # The stack definition
├── .env                    # Secrets — gitignored
├── .env.example            # Template for .env (committed)
├── elasticsearch/
│   └── init.sh             # Bootstrap: ILM policy, index template, role, users
└── logstash/
    └── pipeline.conf       # Ingestion pipeline (TCP/UDP in → ES out)
```

## Setup

1. Copy the env template and fill in the values:
   ```bash
   cp .env.example .env
   $EDITOR .env
   ```
2. Generate the three Kibana encryption keys and set them as the `KIBANA_*_KEY` values in `.env`. Each must be 32+ chars:
   ```bash
   openssl rand -base64 32   # run once per key: KIBANA_ENCRYPTEDSAVEDOBJECTS_KEY, KIBANA_REPORTING_KEY, KIBANA_SECURITY_KEY
   ```
3. Bring the stack up:
   ```bash
   docker compose up -d
   ```
4. Watch `elasticsearch-init` complete on first run:
   ```bash
   docker compose logs -f elasticsearch-init
   ```
   It exits 0 once the ILM policy, index template, role, and users are created.

## Logging in to Kibana

Open `http://127.0.0.1:5601` and sign in with one of:

- `elastic` / `$ELASTICSEARCH_PASSWORD` — built-in cluster superuser. Reserve for cluster admin.
- `$ADMIN_USERNAME` / `$ADMIN_PASSWORD` — `kibana_admin` role. Use for day-to-day UI work.

The Kibana service account (`$KIBANA_USERNAME`) cannot log into the UI — it has only `kibana_system` and exists for Kibana's internal use against Elasticsearch.

## Sending logs to Logstash

Logstash listens for newline-delimited JSON on TCP 5001 and UDP 5002.

Java / logback example:

```xml
<appender name="LOGSTASH" class="net.logstash.logback.appender.LogstashTcpSocketAppender">
    <destination>HOSTNAME:5001</destination>
    <encoder class="net.logstash.logback.encoder.LogstashEncoder">
        <includeContext>true</includeContext>
        <includeMdc>true</includeMdc>
    </encoder>
</appender>
```

Use `LogstashTcpSocketAppender` (not `LogstashAccessTcpSocketAppender` — that one is for HTTP access logs via logback-access, not application logs).

## Index strategy

- Logstash writes events into daily indices: `app-logs-YYYY.MM.DD`.
- An ES index template (`app_logs_template`) attaches the `app_logs_policy` ILM policy to every new `app-logs-*` index at creation time.
- The ILM policy deletes indices after `LOG_RETENTION_DAYS` days (default 30, configurable on the `elasticsearch-init` service in `docker-compose.yml`).
- In Kibana, create a data view with pattern `app-logs-*` and time field `@timestamp`. Searches across the wildcard span every matching daily index automatically.

## Operations

Re-run the bootstrap (idempotent — overwrites policy, template, role, users):
```bash
docker compose up -d elasticsearch-init --force-recreate
```

Inspect ILM state on a specific index:
```bash
curl -u elastic:$ELASTICSEARCH_PASSWORD http://127.0.0.1:9200/app-logs-*/_ilm/explain
```

Check template + policy:
```bash
curl -u elastic:$ELASTICSEARCH_PASSWORD http://127.0.0.1:9200/_index_template/app_logs_template
curl -u elastic:$ELASTICSEARCH_PASSWORD http://127.0.0.1:9200/_ilm/policy/app_logs_policy
```

Tear it all down (preserves the `es-data` volume):
```bash
docker compose down
```

Tear it down and wipe all logs:
```bash
docker compose down -v
```

## Notes & limitations

- **Single-node Elasticsearch** (`discovery.type: single-node`). No HA. The index template sets `number_of_replicas: 0` so cluster health stays green.
- **TLS is disabled on ES** (`xpack.security.http.ssl.enabled: false`). Traffic between containers is cleartext — fine on the Docker network, not acceptable if you ever expose port 9200 publicly.
- **Kibana encryption keys** (the `KIBANA_*_KEY` values in `.env`, wired into `XPACK_*_ENCRYPTIONKEY` in `docker-compose.yml`) must stay stable once Kibana has stored encrypted data. Rotating `KIBANA_ENCRYPTEDSAVEDOBJECTS_KEY` after Kibana has stored encrypted saved objects (Fleet sources, alerting connectors, etc.) will make those objects unreadable. Use the `kibana-encryption-keys` CLI for supported rotation.
- **Re-running `init.sh` overwrites users back to the values in `.env`.** If you change a password through the Kibana UI, the next `docker compose up` will reset it. Edit `.env` instead.
