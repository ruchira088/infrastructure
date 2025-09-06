#!/usr/bin/env sh

curl -s -X POST \
  "$ELASTICSEARCH_HOST/_security/user/$KIBANA_USERNAME" \
  -u "$ELASTICSEARCH_USERNAME:$ELASTICSEARCH_PASSWORD" \
  -H "Content-Type: application/json" \
  --data "{
    \"password\" : \"$KIBANA_PASSWORD\",
    \"roles\" : [ \"superuser\", \"kibana_admin\", \"kibana_system\" ]
  }"

curl -s -X POST \
  "$ELASTICSEARCH_HOST/_security/user/$LOGSTASH_USERNAME" \
  -u "$ELASTICSEARCH_USERNAME:$ELASTICSEARCH_PASSWORD" \
  -H "Content-Type: application/json" \
  --data "{
    \"password\" : \"$LOGSTASH_PASSWORD\",
    \"roles\" : [ \"superuser\" ]
  }"