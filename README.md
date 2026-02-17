
# ApptestAI-elk

# ELK Dashboard 프로젝트

ELK (Elasticsearch, Logstash, Kibana) 스택을 사용하여 다양한 고객사의 테스트 데이터를 수집, 저장, 시각화하는 대시보드 시스템입니다.

## 프로젝트 개요

이 프로젝트는 MySQL 데이터베이스에서 테스트 데이터를 수집하여 Elasticsearch에 인덱싱하고, Kibana를 통해 대시보드로 시각화합니다. 여러 환경(service, stage, onpremise)과 고객사별로 분리된 Space를 지원합니다.

## 주요 기능

- **데이터 수집**: Logstash를 통해 MySQL에서 주기적으로 데이터 수집 (5분 간격)
- **데이터 저장**: Elasticsearch에 구조화된 인덱스로 데이터 저장
- **시각화**: Kibana를 통한 대시보드 제공
- **다중 환경 지원**: service, stage, onpremise 환경별 설정 분리
- **고객사별 Space**: 각 고객사별로 독립된 Kibana Space 제공

## 프로젝트 구조

```
dashboard_elk/
├── docker/
│   ├── build.sh                    # Docker 이미지 빌드 스크립트
│   ├── run.sh                      # Docker 컨테이너 실행 스크립트
│   ├── start.sh                    # 컨테이너 내부 시작 스크립트
│   ├── dockerfile                  # Docker 이미지 정의
│   ├── elasticsearch.yml           # Elasticsearch 설정
│   ├── kibana.yml                  # Kibana 설정
│   ├── logstash.yml                # Logstash 설정
│   ├── pipelines/                  # Logstash 파이프라인 설정
│   │   ├── pipelines_service.yml
│   │   ├── pipelines_stage.yml
│   │   └── pipelines_onpremise.yml
│   ├── logstash_config/            # Logstash 입력/필터/출력 설정
│   │   └── conf.d/
│   │       ├── service/            # service 환경 설정
│   │       ├── stage/              # stage 환경 설정
│   │       └── on_premise/         # onpremise 환경 설정
│   └── dashboard/                  # Kibana 대시보드 정의 파일
│       ├── apptest-ai/
│       ├── hatci/
│       ├── hmg/
│       ├── hyundai-card/
│       ├── on-premise/
│       └── publicspace/
└── README.md
```

### Docker 이미지 빌드

```bash
cd /opt/apps/apptest.ai/apis
cd dashboard_elk
git checkout branch
git pull origin
cd docker
sudo bash build.sh 0 0 v1.0.0
```

예시:
```bash
./build.sh 0 0 v1.0.0
```

## 실행 방법

### 기본 실행 (stage 환경)

```bash
docker run --net apptestnet -e TZ=Asia/Seoul -p 9203:9200 -p 5601:5601 \
-v /var/lib/elk/elasticsearch:/var/lib/elasticsearch \
-v /var/lib/elk/logstash:/var/lib/logstash \
-v /var/lib/elk/kibana:/var/lib/kibana \
-v /etc/elk/certs:/etc/elasticsearch/certs
--restart unless-stopped \
-e DEPLOY_ENV=stage \
-it -d --name dashboard apptestai/dashboard:v2.0.0
```

### 환경 변수

- `DEPLOY_ENV`: 배포 환경 설정
  - `service`: 서비스 환경 (기본 인덱스: hmg, hyundai_card, page_loading_time_hmg, juis_har, pivot-apptestai)
  - `stage`: 스테이징 환경 (service와 동일)
  - `onpremise`: 온프레미스 환경 (기본값, 최소 설정)

- `TZ`: 타임존 설정 (기본값: Asia/Seoul)

### 포트 매핑

- `9203:9200`: Elasticsearch HTTP API
- `5601:5601`: Kibana 웹 인터페이스

### 볼륨 마운트

- `/var/lib/elk/elasticsearch`: Elasticsearch 데이터 영구 저장
- `/var/lib/elk/logstash`: Logstash 데이터 영구 저장
- `/var/lib/elk/kibana`: Kibana 데이터 영구 저장
- SSL 인증서 파일: Kibana HTTPS 설정용

## Elasticsearch 인덱스

### service/stage 환경 인덱스

- **hmg**: 현대자동차 테스트 데이터
- **hyundai_card**: 현대카드 테스트 데이터
- **page_loading_time_hmg**: HMG 페이지 로딩 시간 데이터
- **juis_har**: JUIS HAR 데이터
- **pivot-apptestai**: Apptest AI 피벗 데이터
- **apptestai**: Apptest AI 테스트 데이터 (Logstash 자동 생성)

### 인덱스 생성 시점

- 대부분의 인덱스는 `start.sh`에서 명시적으로 생성됩니다.
- `start.sh`에 명시되지 않은 인덱스는 Logstash가 첫 데이터를 수집할 때 자동으로 생성됩니다.

## Logstash 파이프라인

### service 환경 파이프라인

- `hyundaicard`: 현대카드 데이터 수집
- `hmg`: HMG 데이터 수집
- `apptestai`: Apptest AI 데이터 수집 (5분 간격)
- `juis_har`: JUIS HAR 데이터 수집
- `hatci`: HATCI 데이터 수집
- `hmg_page_loading_time`: HMG 페이지 로딩 시간 데이터 수집

### 데이터 수집 주기

- 대부분의 파이프라인: 5분 간격 (`*/5 * * * * Asia/Seoul`)

## Kibana Space 및 Dashboard

### service/stage 환경 Space

- **apptest-ai**: Apptest AI 대시보드
- **hatci**: HATCI 대시보드
- **hmg**: HMG 대시보드
- **hsc**: 현대카드 대시보드
- **publicspace**: 공개 데이터 대시보드

### onpremise 환경 Space

- **customer**: 고객 대시보드

각 Space는 시작 시 자동으로 생성되며, 해당 디렉토리의 `.ndjson` 파일로부터 대시보드를 자동으로 임포트합니다.

## 서비스 관리

### 컨테이너 접속

```bash
docker exec -it dashboard /bin/bash
```

### Elasticsearch 관리

#### 프로세스 확인

```bash
ps -ef | grep elasticsearch
```

출력 예시:
```
embian         7       1  0 18:07 pts/0    00:00:02 /usr/share/elasticsearch/jdk/bin/java -Xms4m -Xmx64m ...
```
위 예시에서 `7`이 프로세스 ID입니다.

#### 프로세스 종료

```bash
kill -9 <프로세스ID>
```

#### 프로세스 시작

```bash
/usr/share/elasticsearch/bin/elasticsearch &
```

#### 상태 확인

```bash
curl http://localhost:9200
```

#### 인덱스 목록 확인

```bash
curl http://localhost:9200/_cat/indices?v
```

### Logstash 관리

#### 프로세스 확인

```bash
ps -ef | grep logstash
```

출력 예시:
```
embian       923     708 99 18:21 pts/1    00:00:48 /usr/share/logstash/jdk/bin/java -Xms1g -Xmx1g ...
```
위 예시에서 `923`이 프로세스 ID입니다.

#### 프로세스 종료

```bash
kill -9 <프로세스ID>
```

#### 프로세스 시작

```bash
/usr/share/logstash/bin/logstash --path.settings /etc/logstash &
```

#### 로그 확인

```bash
tail -f /var/log/logstash/stdout.log
```

#### 파이프라인 상태 확인

```bash
curl http://localhost:9600/_node/pipelines?pretty
```

### Kibana 관리

#### 프로세스 확인

```bash
ps -ef | grep kibana
```

출력 예시:
```
embian       227       1  3 18:07 pts/0    00:00:40 /usr/share/kibana/bin/../node/glibc-217/bin/node ...
```
위 예시에서 `227`이 프로세스 ID입니다.

#### 프로세스 종료

```bash
kill -9 <프로세스ID>
```

#### 프로세스 시작

```bash
/usr/share/kibana/bin/kibana -c /etc/kibana/kibana.yml &
```

#### 상태 확인

```bash
curl http://localhost:5601/api/status
```

## 트러블슈팅

### Elasticsearch가 시작되지 않는 경우

1. 로그 확인:
   ```bash
   tail -f /var/log/elasticsearch/stdout.log
   ```

2. 디렉토리 권한 확인:
   ```bash
   ls -la /var/lib/elasticsearch
   chown -R elasticsearch:elasticsearch /var/lib/elasticsearch
   ```

### Logstash가 데이터를 수집하지 않는 경우

1. 로그 확인:
   ```bash
   tail -f /var/log/logstash/stdout.log
   ```

2. MySQL 연결 확인:
   - Logstash 설정 파일에서 데이터베이스 연결 정보 확인
   - 네트워크 연결 가능 여부 확인

3. 파이프라인 설정 확인:
   ```bash
   cat /etc/logstash/pipelines.yml
   ```

### Kibana가 접속되지 않는 경우

1. 로그 확인:
   ```bash
   tail -f /var/log/kibana/stdout.log
   ```

2. Elasticsearch 연결 확인:
   ```bash
   curl http://localhost:9200
   ```

3. 포트 확인:
   ```bash
   netstat -tlnp | grep 5601
   ```

### 인덱스가 생성되지 않는 경우

- `apptestai` 인덱스는 Logstash가 첫 데이터를 수집할 때 자동 생성됩니다.
- 최대 5분 정도 기다린 후 확인:
  ```bash
  curl http://localhost:9200/_cat/indices?v | grep apptestai
  ```

### 대시보드가 표시되지 않는 경우

1. Kibana Space 확인:
   - Kibana 웹 인터페이스에서 Space 목록 확인
   - Space가 생성되지 않았다면 컨테이너 재시작

2. 대시보드 파일 확인:
   ```bash
   ls -la /home/dashboard/
   ```

## 참고 사항

- 모든 서비스는 컨테이너 시작 시 자동으로 시작됩니다.
- 초기 설정은 `/home/elastic_setup_done` 플래그 파일로 관리됩니다.
- 인덱스 매핑은 `start.sh`에서 명시적으로 정의됩니다.
- 대시보드는 컨테이너 시작 시 자동으로 임포트됩니다.
- ELK 버전: 8.15.2 (dockerfile에서 고정)
- MySQL Connector 버전: 8.0.28

## 버전 정보

- **Elasticsearch**: 8.15.2
- **Logstash**: 8.15.2
- **Kibana**: 8.15.2
- **MySQL Connector**: 8.0.28
- **Base Image**: Ubuntu 22.04 LTS (Jammy)

## 접속 정보

### Elasticsearch
- URL: `http://localhost:9203` (호스트에서)
- 컨테이너 내부: `http://localhost:9200`
- 기본 인증: `elastic` / `embian1001` (service/stage 환경)

### Kibana
- URL: `http://localhost:5601`
- 기본 인증: `elastic` / `embian1001` (service/stage 환경)

## 주의사항

1. **데이터 영구 저장**: 볼륨 마운트를 통해 데이터를 영구 저장하도록 설정되어 있습니다.
2. **네트워크**: Docker 네트워크 설정이 필요합니다 (`--net apptestnet` 또는 `--net ptero_network`).
3. **SSL 인증서**: Kibana HTTPS 설정을 위해 SSL 인증서 파일이 필요합니다.
4. **초기 설정**: 첫 실행 시 인덱스 생성 및 대시보드 임포트에 시간이 걸릴 수 있습니다.
5. **메모리**: ELK 스택은 메모리를 많이 사용하므로 충분한 리소스를 할당해야 합니다.
>>>>>>> f3e00f2 (elk dashboard)
