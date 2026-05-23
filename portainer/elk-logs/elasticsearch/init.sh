#!/usr/bin/env sh
set -eu

LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-30}"

curl -s --fail-with-body -X PUT \
  "$ELASTICSEARCH_HOST/_ilm/policy/logs_policy" \
  -u "$ELASTICSEARCH_USERNAME:$ELASTICSEARCH_PASSWORD" \
  -H "Content-Type: application/json" \
  --data "{
    \"policy\": {
      \"phases\": {
        \"hot\": {
          \"min_age\": \"0ms\",
          \"actions\": {}
        },
        \"delete\": {
          \"min_age\": \"${LOG_RETENTION_DAYS}d\",
          \"actions\": { \"delete\": {} }
        }
      }
    }
  }"

curl -s --fail-with-body -X PUT \
  "$ELASTICSEARCH_HOST/_index_template/logs_template" \
  -u "$ELASTICSEARCH_USERNAME:$ELASTICSEARCH_PASSWORD" \
  -H "Content-Type: application/json" \
  --data '{
    "index_patterns": [ "logs-*" ],
    "priority": 100,
    "template": {
      "settings": {
        "index.lifecycle.name": "logs_policy",
        "number_of_shards": 1,
        "number_of_replicas": 0
      }
    }
  }'

curl -s --fail-with-body -X PUT \
  "$ELASTICSEARCH_HOST/_security/role/logstash_writer" \
  -u "$ELASTICSEARCH_USERNAME:$ELASTICSEARCH_PASSWORD" \
  -H "Content-Type: application/json" \
  --data '{
    "cluster": [ "monitor", "manage_index_templates" ],
    "indices": [
      {
        "names": [ "logs*" ],
        "privileges": [ "create_index", "create", "index", "write", "view_index_metadata" ]
      }
    ]
  }'

curl -s --fail-with-body -X POST \
  "$ELASTICSEARCH_HOST/_security/user/$KIBANA_USERNAME" \
  -u "$ELASTICSEARCH_USERNAME:$ELASTICSEARCH_PASSWORD" \
  -H "Content-Type: application/json" \
  --data "{
    \"password\" : \"$KIBANA_PASSWORD\",
    \"roles\" : [ \"kibana_system\" ]
  }"

curl -s --fail-with-body -X POST \
  "$ELASTICSEARCH_HOST/_security/user/$LOGSTASH_USERNAME" \
  -u "$ELASTICSEARCH_USERNAME:$ELASTICSEARCH_PASSWORD" \
  -H "Content-Type: application/json" \
  --data "{
    \"password\" : \"$LOGSTASH_PASSWORD\",
    \"roles\" : [ \"logstash_writer\" ]
  }"
