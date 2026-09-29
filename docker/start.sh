#!/bin/bash
set -e

ES_URL="https://localhost:9200"
ES_CA="/etc/elasticsearch/certs/http_ca.crt"

ES_USER="elastic"
ES_PASS="embian1001"

KBN_URL="http://localhost:5601"
KBN_CURL="curl -s -u ${ES_USER}:${ES_PASS}"

echo "Running as root"

DEPLOY_ENV=${DEPLOY_ENV:-onpremise}

# ====================================
# 1. Elasticsearch 시작
# ====================================
echo "Starting Elasticsearch..."

mkdir -p /var/lib/elasticsearch /var/log/elasticsearch /etc/elasticsearch
chown -R elasticsearch:elasticsearch /var/lib/elasticsearch /var/log/elasticsearch /etc/elasticsearch
chmod -R 775 /var/lib/elasticsearch
chmod 755 /etc/elasticsearch

export ES_PATH_CONF=/etc/elasticsearch

KEYS=(
  xpack.security.transport.ssl.keystore.secure_password
  xpack.security.transport.ssl.truststore.secure_password
  xpack.security.http.ssl.keystore.secure_password
)

for KEY in "${KEYS[@]}"; do
  if su -s /bin/bash elasticsearch -c \
     "export ES_PATH_CONF=/etc/elasticsearch && \
      /usr/share/elasticsearch/bin/elasticsearch-keystore list" | grep -q "^$KEY$"; then

    echo "Removing $KEY from elasticsearch keystore..."

    su -s /bin/bash elasticsearch -c \
      "export ES_PATH_CONF=/etc/elasticsearch && \
       /usr/share/elasticsearch/bin/elasticsearch-keystore remove $KEY"
  else
    echo "Keystore key $KEY not found. Skipping."
  fi
done

if [ "$DEPLOY_ENV" = "onpremise" ]; then
  rm -f /etc/elasticsearch/elasticsearch.yml
  rm -f /etc/kibana/kibana.yml
  cp /etc/elasticsearch/onpremise/elasticsearch.yml /etc/elasticsearch/elasticsearch.yml
  cp /etc/kibana/onpremise/kibana.yml /etc/kibana/kibana.yml
fi
CERT_DIR="/etc/elasticsearch/certs"
CERT_FLAG="${CERT_DIR}/.certs_initialized"

if [ ! -f "$CERT_FLAG" ]; then
  echo "Initializing Elasticsearch TLS certificates..."

  rm -rf "$CERT_DIR"
  mkdir -p "$CERT_DIR"
  chown elasticsearch:elasticsearch "$CERT_DIR"
  chmod 750 "$CERT_DIR"

  # Root CA
  openssl genrsa -out "$CERT_DIR/ca.key" 4096
  openssl req -x509 -new -nodes \
    -key "$CERT_DIR/ca.key" \
    -sha256 -days 3650 \
    -out "$CERT_DIR/ca.crt" \
    -subj "/CN=Apptest-Elastic-Root-CA"

  # HTTP cert (SAN 포함)
  cat > "$CERT_DIR/http.cnf" <<'EOF'
  [ req ]
  default_bits       = 2048
  prompt             = no
  default_md         = sha256
  distinguished_name = dn
  req_extensions     = req_ext

  [ dn ]
  CN = localhost

  [ req_ext ]
  subjectAltName = @alt_names

  [ alt_names ]
  DNS.1 = localhost
  IP.1  = 127.0.0.1
EOF

  openssl genrsa -out "$CERT_DIR/http.key" 2048
  openssl req -new \
    -key "$CERT_DIR/http.key" \
    -out "$CERT_DIR/http.csr" \
    -config "$CERT_DIR/http.cnf"

  openssl x509 -req \
    -in "$CERT_DIR/http.csr" \
    -CA "$CERT_DIR/ca.crt" \
    -CAkey "$CERT_DIR/ca.key" \
    -CAcreateserial \
    -out "$CERT_DIR/http.crt" \
    -days 3650 -sha256 \
    -extensions req_ext \
    -extfile "$CERT_DIR/http.cnf"

  openssl pkcs12 -export \
    -inkey "$CERT_DIR/http.key" \
    -in "$CERT_DIR/http.crt" \
    -certfile "$CERT_DIR/ca.crt" \
    -name http \
    -out "$CERT_DIR/http.p12" \
    -passout pass:

  # Transport cert
  openssl genrsa -out "$CERT_DIR/transport.key" 2048
  openssl req -new -x509 \
    -key "$CERT_DIR/transport.key" \
    -out "$CERT_DIR/transport.crt" \
    -days 3650 \
    -subj "/CN=elasticsearch-transport"

  openssl pkcs12 -export \
    -inkey "$CERT_DIR/transport.key" \
    -in "$CERT_DIR/transport.crt" \
    -out "$CERT_DIR/transport.p12" \
    -name transport \
    -passout pass: \
    -nomac

  cp "$CERT_DIR/ca.crt" "$CERT_DIR/http_ca.crt"

  chown elasticsearch:elasticsearch "$CERT_DIR"/*
  chmod 755 "$CERT_DIR"/*.key "$CERT_DIR"/*.p12 "$CERT_DIR"/*.crt
  chmod 644 "$CERT_DIR/http_ca.crt"

  mkdir -p /usr/share/kibana/config
  cp /etc/elasticsearch/certs/http_ca.crt /usr/share/kibana/config/http_ca.crt
  chown kibana:kibana /usr/share/kibana/config/http_ca.crt
  chmod 755 /usr/share/kibana/config
  chmod 644 /usr/share/kibana/config/http_ca.crt

  mkdir -p /usr/share/logstash/config/certs
  cp /etc/elasticsearch/certs/http_ca.crt /usr/share/logstash/config/certs/http_ca.crt

  chown -R logstash:logstash /usr/share/logstash/config/certs
  chmod 755 /usr/share/logstash/config/certs
  chmod 644 /usr/share/logstash/config/certs/http_ca.crt

  touch "$CERT_FLAG"
else
  echo "TLS certificates already initialized."
fi
# 백그라운드 실행
nohup su -s /bin/bash elasticsearch -c "/usr/share/elasticsearch/bin/elasticsearch > /var/log/elasticsearch/stdout.log 2>&1 &"

echo "Waiting for Elasticsearch to start..."
if [ "$DEPLOY_ENV" = "service" ]|| [ "$DEPLOY_ENV" = "stage" ]; then
  until curl -s --cacert "$ES_CA" -u "$ES_USER:$ES_PASS" "$ES_URL" >/dev/null 2>&1; do
    sleep 2
  done
  echo "Elasticsearch is ready!"
else
  until curl -s localhost:9200 >/dev/null 2>&1; do
    sleep 2
  done
  echo "Elasticsearch is ready!"
fi

# ====================================
# 2. Elasticsearch 초기 세팅
# ====================================
SETUP_FLAG="/home/elastic_setup_done"

if [ ! -f "$SETUP_FLAG" ]; then
  echo "Initializing Elasticsearch indexes..."

  if [ "$DEPLOY_ENV" = "service" ]|| [ "$DEPLOY_ENV" = "stage" ]; then
    # hmg index
    curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASS" -X PUT "$ES_URL/hmg" \
    -H 'Content-Type: application/json' \
    -d '{
      "settings": {
        "index": {
          "number_of_shards": 1,
          "number_of_replicas": 1,
          "refresh_interval": "1s",
          "priority": 1,
          "query.default_field": ["*"],
          "write.wait_for_active_shards": "1",
          "routing": {
            "allocation": {
              "include": {
                "_tier_preference": "data_content"
              }
            }
          }
        }
      },
      "mappings": {
        "properties": {
          "@timestamp": { "type": "date" },
          "@version": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "apk_name": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "app_name": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "app_version": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "brand": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "brand_app_version_date": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "brand_name": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "brand_version": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "brand_version_date": { "type": "date" },
          "created_at": { "type": "date" },
          "created_at_kst_str": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "ctimestamp": { "type": "date" },
          "date": { "type": "date" },
          "date_brand_app_version": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "datetime": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "debug_error": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "debug_error_finished": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "debug_error_finished_kst": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "debug_time_extraction": {
            "properties": {
              "extracted_time": {
                "type": "text",
                "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
              },
              "final_result": {
                "type": "text",
                "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
              },
              "original_created_at": { "type": "date" }
            }
          },
          "debug_timestamp": { "type": "date" },
          "deleted": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "device_id": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "device_name": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "final_debug": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "finished_at": { "type": "date" },
          "finished_at_kst": { "type": "date" },
          "finished_at_kst_str": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "hour": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "id": { "type": "long" },
          "is_ci": { "type": "long" },
          "is_ci_test": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "is_ci_type_true": { "type": "long" },
          "is_crashed": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "is_schedule": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "logstash_processed_at": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "logstash_processed_at_kst": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "logstash_processed_kst": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "minute": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "os": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "os_app_version": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "os_app_version_date": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "os_app_version_date_backup": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "os_version": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "pid": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "project_id": { "type": "long" },
          "run_time_sec": { "type": "long" },
          "scn_type": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "second": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "tags": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "test_date": { "type": "date" },
          "test_datetime_kst": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "test_hour": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "test_result": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "test_run_id": { "type": "long" },
          "test_suite_name": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "test_suite_run_id": { "type": "long" },
          "tid": { "type": "long" },
          "total_test_time_sec": { "type": "long" },
          "translation": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          },
          "week": {
            "type": "text",
            "fields": { "keyword": { "type": "keyword", "ignore_above": 256 } }
          }
        }
      }
    }'
    # pivot-apptestai index
    curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASS" -X PUT "$ES_URL/pivot-apptestai" \
      -H 'Content-Type: application/json' \
      -d '{
        "settings": {
          "index": {
            "number_of_shards": 1,
            "number_of_replicas": 0,
            "auto_expand_replicas": "0-1",
            "routing": {
              "allocation": {
                "include": {
                  "_tier_preference": "data_content"
                }
              }
            }
          }
        },
        "mappings": {
          "_meta": {
            "created_by": "transform",
            "_transform": {
              "transform": "pivot-apptestai",
              "version": {
                "created": "7.16.3"
              },
              "creation_date_in_millis": 1677147914997
            }
          },
          "properties": {
            "@timestamp": {
              "properties": {
                "value_count": {
                  "type": "long"
                }
              }
            },
            "created_at": {
              "type": "date"
            },
            "ctimestamp": {
              "type": "date"
            }
          }
        }
      }'
    # hyundai_card index
    curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASS" -X PUT "$ES_URL/hyundai_card" \
      -H 'Content-Type: application/json' \
      -d '{
        "settings": {
          "index": {
            "number_of_shards": 1,
            "number_of_replicas": 1,
            "routing": {
              "allocation": {
                "include": {
                  "_tier_preference": "data_content"
                }
              }
            }
          }
        },
        "mappings": {
          "properties": {
            "@timestamp": { "type": "date" },
            "@version": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "deleted": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "device": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "device_id": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "device_type": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "duration": { "type": "long" },
            "groupid": { "type": "long" },
            "id": { "type": "long" },
            "os": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "os_version": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "pay_method": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "program": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "result": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "store": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "test_run_id": { "type": "long" },
            "test_suite_run_id": { "type": "long" },
            "tid": { "type": "long" }
          }
        }
      }'

    # page_loading_time_hmg index
    curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASS" -X PUT "$ES_URL/page_loading_time_hmg" \
      -H 'Content-Type: application/json' \
      -d '{
        "settings": {
          "index": {
            "number_of_shards": 1,
            "number_of_replicas": 1,
            "routing": {
              "allocation": {
                "include": {
                  "_tier_preference": "data_content"
                }
              }
            }
          }
        },
        "mappings": {
          "properties": {
            "@timestamp": { "type": "date" },
            "@version": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "action": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "action_label": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "action_time": { "type": "date" },
            "app_name": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "app_version": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "ctimestamp": { "type": "date" },
            "delete_flag": { "type": "boolean" },
            "device": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "duration": { "type": "long" },
            "id": { "type": "long" },
            "name": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "os": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "pid": { "type": "long" },
            "run_result": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "scn_name": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "source": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "test_run_id": { "type": "long" },
            "test_suite_run_id": { "type": "long" },
            "tid": { "type": "long" }
          }
        }
      }'

    # juis index
    curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASS" -X PUT "$ES_URL/juis_har" \
      -H 'Content-Type: application/json' \
      -d '{
        "settings": {
          "index": {
            "number_of_shards": 1,
            "number_of_replicas": 1,
            "routing": {
              "allocation": {
                "include": {
                  "_tier_preference": "data_content"
                }
              }
            }
          }
        },
        "mappings": {
          "properties": {
            "@timestamp": { "type": "date" },
            "@version": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "biz_type": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "content_type": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "filter_type": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "id": { "type": "long" },
            "is_main_page": { "type": "boolean" },
            "is_violation": { "type": "boolean" },
            "method": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "occurred_action": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "page_url": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "referer_url": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "request_url_head": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "request_url_qstring": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "response_size": { "type": "long" },
            "response_time": { "type": "long" },
            "sid": { "type": "long" },
            "started_at": { "type": "date" },
            "status_code": { "type": "long" },
            "status_text": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "tid": { "type": "long" }
          }
        }
      }'

    # hatci index
    curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASS" -X PUT "$ES_URL/hatci" \
      -H 'Content-Type: application/json' \
      -d '{
        "settings": {
          "index": {
            "number_of_shards": 1,
            "number_of_replicas": 1,
            "routing": {
              "allocation": {
                "include": {
                  "_tier_preference": "data_content"
                }
              }
            }
          }
        },
        "mappings": {
          "properties": {
            "@timestamp": { "type": "date" },
            "@version": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "TC_name": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "app_name": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "created_at": { "type": "date" },
            "ctimestamp": { "type": "date" },
            "deleted": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "device_id": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "device_name": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "id": { "type": "long" },
            "is_crashed": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "os": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "os_version": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "run_time": { "type": "long" },
            "scn_type": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "test_result": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "test_run_id": { "type": "long" },
            "test_suite_name": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "test_suite_run_id": { "type": "long" },
            "tid": { "type": "long" },
            "week": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            }
          }
        }
      }'

    # apptestai index
    curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASS" -X PUT "$ES_URL/apptestai" \
      -H 'Content-Type: application/json' \
      -d '{
        "settings": {
          "index": {
            "number_of_shards": 1,
            "number_of_replicas": 1,
            "routing": {
              "allocation": {
                "include": {
                  "_tier_preference": "data_content"
                }
              }
            }
          }
        },
        "mappings": {
          "properties": {
            "@timestamp": { "type": "date" },
            "@version": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "apk_name": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "app_name": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "app_sources": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "created_at": { "type": "date" },
            "ctimestamp": { "type": "date" },
            "device_id": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "device_name": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "id": { "type": "long" },
            "os": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "os_version": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "pet_friends_test_type": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "pid": { "type": "long" },
            "run_time": { "type": "long" },
            "test_result": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "test_run_id": { "type": "long" },
            "test_suite_run_id": { "type": "long" },
            "test_type": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "time_per_step": { "type": "float" },
            "total_step": { "type": "long" },
            "type": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            },
            "uid": { "type": "long" },
            "week": {
              "type": "text",
              "fields": {
                "keyword": { "type": "keyword", "ignore_above": 256 }
              }
            }
          }
        }
      }'
  else
    # customer index
    curl -s -XPUT http://localhost:9200/customer \
     -H 'Content-Type: application/json' \
     -d '{
       "mappings": {
         "properties": {
           "@timestamp": { "type": "date" },
           "@version": {
             "type": "text",
             "fields": {
               "keyword": { "type": "keyword", "ignore_above": 256 }
             }
           },
           "app_name": {
             "type": "text",
             "fields": {
               "keyword": { "type": "keyword", "ignore_above": 256 }
             }
           },
           "app_sources": {
             "type": "text",
             "fields": {
               "keyword": { "type": "keyword", "ignore_above": 256 }
             }
           },
           "created_at": { "type": "date" },
           "ctimestamp": { "type": "date" },
           "device_id": {
             "type": "text",
             "fields": {
               "keyword": { "type": "keyword", "ignore_above": 256 }
             }
           },
           "device_name": {
             "type": "text",
             "fields": {
               "keyword": { "type": "keyword", "ignore_above": 256 }
             }
           },
           "id": { "type": "long" },
           "os": {
             "type": "text",
             "fields": {
               "keyword": { "type": "keyword", "ignore_above": 256 }
             }
           },
           "os_version": {
             "type": "text",
             "fields": {
               "keyword": { "type": "keyword", "ignore_above": 256 }
             }
           },
           "pet_friends_test_type": {
             "type": "text",
             "fields": {
               "keyword": { "type": "keyword", "ignore_above": 256 }
             }
           },
           "pid": { "type": "long" },
           "run_time": { "type": "long" },
           "test_result": {
             "type": "text",
             "fields": {
               "keyword": { "type": "keyword", "ignore_above": 256 }
             }
           },
           "test_type": {
             "type": "text",
             "fields": {
               "keyword": { "type": "keyword", "ignore_above": 256 }
             }
           },
           "time_per_step": { "type": "float" },
           "total_step": { "type": "long" },
           "type": {
             "type": "text",
             "fields": {
               "keyword": { "type": "keyword", "ignore_above": 256 }
             }
           },
           "uid": { "type": "long" },
           "week": {
             "type": "text",
             "fields": {
               "keyword": { "type": "keyword", "ignore_above": 256 }
             }
           }
         }
       }
     }'
  fi

  touch "$SETUP_FLAG"
else
  echo "Elasticsearch setup already done."
fi

# ====================================
# 3. Logstash 시작
# ====================================
echo -e "\nStarting Logstash..."
mkdir -p /var/lib/logstash /var/log/logstash /usr/share/logstash/data /etc/logstash
chown -R logstash:logstash /var/lib/logstash /var/log/logstash /usr/share/logstash/data /etc/logstash
chmod -R 775 /var/lib/logstash /var/log/logstash /usr/share/logstash/data /etc/logstash

PIPELINE_FILE="/etc/logstash/pipelines/pipelines_${DEPLOY_ENV}.yml"

if [ ! -f "$PIPELINE_FILE" ]; then
  echo "Pipeline file not found: $PIPELINE_FILE"
  exit 1
fi

cp "$PIPELINE_FILE" /etc/logstash/pipelines.yml

nohup su -s /bin/bash logstash -c "/usr/share/logstash/bin/logstash --path.settings /etc/logstash > /var/log/logstash/stdout.log 2>&1 &"

# ====================================
# 4. Kibana 초기 세팅
# ====================================
if [ ! -f /etc/kibana/.kibana_pass_initialized ]; then
  OUTPUT=$(
    cd /usr/share/elasticsearch && \
    bin/elasticsearch-reset-password \
      -u kibana_system \
      --url https://localhost:9200 \
      --batch
  )

  NEW_PASS=$(echo "$OUTPUT" | grep "New value:" | awk '{print $3}')

  if [ -z "$NEW_PASS" ]; then
    echo "Password extraction failed"
    exit 1
  fi

  if grep -q "^elasticsearch.password:" /etc/kibana/kibana.yml; then
    sed -i "s|^elasticsearch.password:.*|elasticsearch.password: \"$NEW_PASS\"|" /etc/kibana/kibana.yml
  else
    echo "elasticsearch.password: \"$NEW_PASS\"" >> /etc/kibana/kibana.yml
  fi

  touch /etc/kibana/.kibana_pass_initialized
fi

# ====================================
# 5. Kibana 시작
# ====================================
echo "Starting Kibana..."
mkdir -p /var/lib/kibana /var/log/kibana /usr/share/kibana /etc/kibana
chown -R kibana:kibana /var/lib/kibana /var/log/kibana /etc/kibana

nohup su -s /bin/bash kibana -c "/usr/share/kibana/bin/kibana -c /etc/kibana/kibana.yml > /var/log/kibana/stdout.log 2>&1 &"

echo "Waiting for Kibana to become available..."
if [ "$DEPLOY_ENV" = "service" ]|| [ "$DEPLOY_ENV" = "stage" ]; then
  until (
    $KBN_CURL "$KBN_URL/api/status" | grep -q '"level":"available"' || \
    $KBN_CURL "$KBN_URL/kibana/api/status" | grep -q '"level":"available"'
  ); do
    echo -n "."
    sleep 3
  done
  echo -e "\nKibana is ready!"
else
  until (
    curl -s localhost:5601/api/status | grep -q '"level":"available"' || curl -s localhost:5601/kibana/api/status | grep -q '"level":"available"'
  ); do
    echo -n "."
    sleep 3
  done
  echo -e "\nKibana is ready!"
fi

# ====================================
# 6. Space 및 Dashboard 등록
# ====================================

DASHBOARD_DIR="/home/dashboard"

if [ "$DEPLOY_ENV" = "service" ]|| [ "$DEPLOY_ENV" = "stage" ]; then
  CUSTOMERS=(
    '{"id":"apptest-ai","name":"Apptest AI","description":"Apptest AI Dashboard","color":"#d6bf57","initials":"A","dashboard_dir":"'"${DASHBOARD_DIR}/apptest-ai"'"}'
    '{"id":"hatci","name":"HATCI","description":"Hyundai America Technical Center, Inc. Dashboard","color":"#57bcd6","initials":"B","dashboard_dir":"'"${DASHBOARD_DIR}/hatci"'"}'
    '{"id":"hmg","name":"HMG","description":"","color":"#d657a2","initials":"H","dashboard_dir":"'"${DASHBOARD_DIR}/hmg"'"}'
    '{"id":"hsc","name":"Hyundai Card","description":"","color":"#57d65a","initials":"H","dashboard_dir":"'"${DASHBOARD_DIR}/hyundai-card"'"}'
    '{"id":"publicspace","name":"PublicSpace","description":"전체 공개 가능한 데이터","color":"#57d65a","initials":"P","dashboard_dir":"'"${DASHBOARD_DIR}/publicspace"'"}'
    '{"id":"publicspace_for_us","name":"PublicSpace for US","description":"","color":"#57d65a","initials":"P","dashboard_dir":"'"${DASHBOARD_DIR}/publicspace_for_us"'"}'
  )
else
  CUSTOMERS=(
    '{"id":"customer","name":"Customer","description":"This is the Customer Space","color":"#d6bf57","initials":"C","dashboard_dir":"'"${DASHBOARD_DIR}/on-premise"'"}'
  )
fi


for entry in "${CUSTOMERS[@]}"; do
  SPACE_ID=$(echo "$entry" | jq -r '.id')
  SPACE_NAME=$(echo "$entry" | jq -r '.name')
  SPACE_DESC=$(echo "$entry" | jq -r '.description')
  SPACE_COLOR=$(echo "$entry" | jq -r '.color')
  SPACE_INITIALS=$(echo "$entry" | jq -r '.initials')
  DASHBOARD_PATH=$(echo "$entry" | jq -r '.dashboard_dir')

  # ---------------------------
  # Space 존재 여부 (HTTPS 코드 기준)
  # ---------------------------
  if [ "$DEPLOY_ENV" = "service" ]|| [ "$DEPLOY_ENV" = "stage" ]; then
    space_status=$($KBN_CURL -o /dev/null -w "%{http_code}" \
    "$KBN_URL/api/spaces/space/${SPACE_ID}" \
    -H 'kbn-xsrf: true')
  else
   space_status=$(curl -s -o /dev/null -w "%{http_code}" \
    "http://localhost:5601/api/spaces/space/${SPACE_ID}" \
    -H 'kbn-xsrf: true')
  fi

  if [ "$space_status" != "200" ]; then
    echo "Creating Kibana space [$SPACE_NAME]..."

    payload=$(jq -n \
      --arg id "$SPACE_ID" \
      --arg name "$SPACE_NAME" \
      --arg desc "$SPACE_DESC" \
      --arg color "$SPACE_COLOR" \
      --arg initials "$SPACE_INITIALS" \
      '{
        id: $id,
        name: $name,
        description: $desc,
        color: $color,
        initials: $initials,
        disabledFeatures: [],
        imageUrl: ""
      }'
    )

    if [ "$DEPLOY_ENV" = "service" ]|| [ "$DEPLOY_ENV" = "stage" ]; then
      $KBN_CURL -X POST "$KBN_URL/api/spaces/space" \
      -H 'kbn-xsrf: true' \
      -H 'Content-Type: application/json' \
      -d "$payload" | jq .
    else
      curl -s -X POST "http://localhost:5601/api/spaces/space" \
      -H 'kbn-xsrf: true' \
      -H 'Content-Type: application/json' \
      -d "$payload" | jq .
    fi
  else
    echo "Space [$SPACE_NAME] already exists."
  fi

  # ---------------------------
  # Dashboard 디렉토리 존재 확인
  # ---------------------------
  if [ ! -d "$DASHBOARD_PATH" ]; then
    echo "Dashboard directory not found: $DASHBOARD_PATH"
    continue
  fi

  # ---------------------------
  # ndjson 파일 순회하여 Import
  # ---------------------------
  for ndjson_file in "$DASHBOARD_PATH"/*.ndjson; do
    if [ ! -f "$ndjson_file" ]; then
      echo "No .ndjson files in $DASHBOARD_PATH"
      continue
    fi

    echo "Importing dashboard for [$SPACE_NAME] from [$ndjson_file]..."
    if [ "$DEPLOY_ENV" = "service" ]|| [ "$DEPLOY_ENV" = "stage" ]; then
      $KBN_CURL -X POST \
      "$KBN_URL/s/${SPACE_ID}/api/saved_objects/_import?overwrite=true" \
      -H "kbn-xsrf: true" \
      -F "file=@${ndjson_file}" | jq .
    else
      curl -s -X POST "http://localhost:5601/s/${SPACE_ID}/api/saved_objects/_import?overwrite=true" \
      -H "kbn-xsrf: true" \
      -F "file=@${ndjson_file}" | jq .
    fi
  done

done

echo "All customer spaces and dashboards processed!"

# ====================================
# 7. 종료 방지
# ====================================
echo "All services are up and running."
tail -f /dev/null