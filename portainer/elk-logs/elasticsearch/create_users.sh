#!/usr/bin/env sh
set -eu

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
