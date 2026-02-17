# ELK Docker 기반 보안 및 운영 자동화

## 1. 프로젝트 개요

- **프로젝트명**: ELK Docker 기반 보안 및 운영 자동화
- **프로젝트 소속**: ApptestAI
- **프로젝트 기간**: 2025.12 ~ 2026.02
- **프로젝트 인원**: 1명

### 프로젝트 개요
본 프로젝트는 기존에 **SaaS 환경에서 직접 설치·운영되던 Elasticsearch, Logstash, Kibana(ELK)** 시스템을  
보안 강화 및 유지보수 효율 향상을 목적으로 **Docker 기반 표준 이미지 구조로 재설계**하고,  
**버전 업그레이드 및 보안 설정 자동화**를 수행한 프로젝트이다.

**ELK(Stack)** 는 대규모 서비스 환경에서 발생하는 로그 및 이벤트 데이터를  
수집(Logstash) · 저장/검색(Elasticsearch) · 시각화(Kibana)하는  
로그 분석 및 모니터링 플랫폼으로,  
SaaS 서비스의 운영 안정성과 장애 대응에 핵심적인 역할을 수행한다.

기존 ELK 시스템은 버전이 오래되었으며,  
보안 설정(TLS, 인증)이 단계적으로 적용되지 않아  
SaaS / On-Premise 환경별 설정이 혼재된 상태였다.

이에 따라 본 프로젝트에서는  
**ELK 8.x 버전 기준 보안 정책을 반영한 컨테이너 표준 이미지 아키텍처를 설계하고**,  
운영 환경별 설정 자동화 및 배포 안정성을 확보하는 것을 목표로 진행되었다.

---

## 2. 시스템 아키텍처

본 시스템은 **Elasticsearch · Logstash · Kibana를 하나의 Docker 이미지로 구성**하고,  
컨테이너 기동 시 Bash 스크립트를 통해 각 컴포넌트의 초기 설정 및 실행을 제어하는 구조로 설계되었다.

단일 이미지 구조는 SaaS 환경에서의 빠른 배포, 버전 일관성 확보,
운영 복잡도 감소를 우선한 설계 선택이다.

### 아키텍처 설명
- **단일 ELK Docker 이미지**: Elasticsearch, Logstash, Kibana를 하나의 컨테이너에 포함
- **자동화 스크립트**: 컨테이너 시작 시 `start.sh`를 통해 인증서 생성, 보안 설정, 서비스 기동 자동화
- **TLS 암호화**: Elasticsearch HTTP(9200) / Transport(9300) 통신에 TLS 적용
- **환경별 설정 분리**: Logstash Pipeline, Kibana Dashboard, 보안 설정은 환경별 파일로 분리
- **멀티 환경 지원**: SaaS / Stage / On-Premise 환경에 동일 이미지 배포 가능

### 주요 구성 요소

#### Docker 이미지 구조
```
docker/
├── dockerfile              # ELK 8.15.2 통합 이미지 정의
├── start.sh                # 컨테이너 시작 시 실행 스크립트 (자동화 핵심)
├── build.sh                # 이미지 빌드 스크립트
├── run.sh                  # 컨테이너 실행 스크립트
├── elasticsearch.yml       # Elasticsearch 설정 (SaaS/Stage용)
├── kibana.yml              # Kibana 설정 (SaaS/Stage용)
├── logstash.yml            # Logstash 공통 설정
├── pipelines/              # 환경별 Logstash 파이프라인 설정
│   ├── pipelines_service.yml
│   ├── pipelines_stage.yml
│   └── pipelines_onpremise.yml
├── logstash_config/        # 환경별 Logstash 입력/필터/출력 설정
│   └── conf.d/
│       ├── service/
│       ├── stage/
│       └── on_premise/
├── dashboard/              # 고객사별 Kibana Dashboard (ndjson)
│   ├── apptest-ai/
│   ├── hatci/
│   ├── hmg/
│   ├── hyundai-card/
│   ├── on-premise/
│   └── publicspace/
└── unsecured_onpremise/    # On-Premise용 비보안 설정
    ├── elasticsearch.yml
    └── kibana.yml
```

---

## 3. 담당 역할

### ELK Docker 표준 이미지 설계
- Elasticsearch · Logstash · Kibana Docker 이미지 구조 설계
- 이미지 빌드 시 버전 고정 (`ARG ELK_VERSION=8.15.2`) 적용
- `apt-mark hold`를 통한 버전 고정으로 업그레이드 방지
- root 권한 실행 제한 정책(8.x) 대응

### 보안 설정 및 인증 체계 구축
- **TLS 인증서 자동 생성**: 컨테이너 시작 시 OpenSSL을 통한 자체 서명 인증서 생성
  - Root CA 인증서 (4096bit RSA, 10년 유효기간)
  - HTTP 인증서 (SAN 포함: localhost, 127.0.0.1)
  - Transport 인증서 (노드 간 통신용)
- **Elasticsearch 보안 설정**: HTTP(9200) / Transport(9300) TLS 암호화 적용
- **Kibana ↔ Elasticsearch 인증**: `elasticsearch-reset-password`를 통한 `kibana_system` 비밀번호 자동 발급 및 설정
- **인증서 배포 자동화**: 생성된 인증서를 Kibana, Logstash에 자동 복사 및 권한 설정

### SaaS 운영 자동화
- **Bash 스크립트 기반 자동화**: `start.sh`를 통한 컨테이너 실행·초기화 자동화
- **초기 세팅 자동화**: 
  - Elasticsearch 인덱스 생성 (환경별 인덱스 매핑 정의)
  - Kibana Space 생성 (고객사별 Space 자동 생성)
  - Dashboard 임포트 (ndjson 파일 기반 자동 임포트)
- **플래그 파일 기반 중복 실행 방지**: `/home/elastic_setup_done`, `/.certs_initialized` 등으로 초기화 상태 관리
- **환경별 파이프라인 자동 선택**: `DEPLOY_ENV` 환경 변수에 따라 적절한 파이프라인 설정 파일 자동 선택

### 환경별 설정 분리 관리
- **Logstash Config / Pipeline 분리**: `pipelines_${DEPLOY_ENV}.yml` 형식으로 환경별 분리
- **Kibana Dashboard(ndjson) 환경별 분리**: 고객사별 디렉토리 구조로 관리
- **SaaS / Stage / On-Premise 설정 파일 독립 관리**: 
  - SaaS/Stage: 보안 설정 활성화 (`xpack.security.enabled: true`)
  - On-Premise: 보안 설정 비활성화 (`xpack.security.enabled: false`)

---

## 4. 기술적 문제 및 해결

### 문제 1. ELK 8.x 버전 root 실행 제한 이슈
ELK 8.x 버전에서는  
**Elasticsearch, Kibana, Logstash를 root 권한으로 실행하는 것이 제한**되어 있었으며,  
기존 컨테이너는 root 기반으로 실행되고 있었다.

#### 해결 방법
- Dockerfile에서 각 서비스의 전용 유저(`elasticsearch`, `kibana`, `logstash`) 활용
- `start.sh`에서 `su -s /bin/bash` 명령을 통해 각 서비스를 해당 유저로 실행
- 디렉토리 권한 설정: `chown -R elasticsearch:elasticsearch`, `chown -R kibana:kibana` 등
- 보안 정책을 준수하는 컨테이너 실행 구조로 개선

**구현 예시**:
```bash
# Elasticsearch를 elasticsearch 유저로 실행
nohup su -s /bin/bash elasticsearch -c \
  "/usr/share/elasticsearch/bin/elasticsearch > /var/log/elasticsearch/stdout.log 2>&1 &"
```

---

### 문제 2. 기존 7.x 데이터 볼륨과 8.x 호환성 문제
기존 볼륨 마운트 디렉토리에  
**Elasticsearch 7.16.3 데이터가 남아 있어 8.x 기동 실패** 문제가 발생하였다.

#### 해결 방법
- 볼륨 데이터 정리 후 재기동
- 버전 업그레이드 시 데이터 호환성 이슈 가이드 문서화
- 신규 환경 배포 시 초기화 프로세스 명확화
- 플래그 파일(`/home/elastic_setup_done`)을 통한 초기화 상태 관리로 중복 실행 방지

---

### 문제 3. ELK 이미지 빌드 시 버전 불일치 문제
이미지 생성 시점마다  
Elasticsearch / Logstash / Kibana 버전이 서로 다르게 설치되는 문제가 발생하였다.

#### 해결 방법
- Dockerfile 내 ELK 버전 명시적 고정: `ARG ELK_VERSION=8.15.2`
- Elasticsearch, Logstash, Kibana 모두 **8.15.2 통일**
- `apt-mark hold elasticsearch logstash kibana`를 통한 버전 고정
- 운영 환경 간 버전 차이로 인한 장애 요소 제거

**구현 예시**:
```dockerfile
ARG ELK_VERSION=8.15.2
RUN apt-get install -y \
    elasticsearch=${ELK_VERSION} \
    logstash=1:${ELK_VERSION}-1 \
    kibana=${ELK_VERSION} && \
    apt-mark hold elasticsearch logstash kibana
```

---

### 문제 4. Elasticsearch 보안 설정 및 TLS 단계적 적용
기존 시스템은  
HTTP 및 Transport 통신이 평문으로 동작하고 있었으며,  
보안 설정이 부분적으로만 적용된 상태였다.

#### 해결 방법
- **TLS 인증서 자동 생성 스크립트 작성**: 컨테이너 시작 시 OpenSSL을 통한 자체 서명 인증서 생성
  - Root CA 생성 (4096bit RSA, 10년 유효기간)
  - HTTP 인증서 생성 (SAN 포함: localhost, 127.0.0.1)
  - Transport 인증서 생성 (노드 간 통신용)
  - PKCS12 형식으로 변환하여 Elasticsearch에서 사용 가능하도록 구성
- **HTTP(9200) / Transport(9300) 통신 TLS 암호화 적용**
- **인증서 배포 자동화**: 생성된 인증서를 Kibana, Logstash에 자동 복사
- **1단계 → 2단계 보안 적용 프로세스 정립**
- **인증서 발급 및 적용 절차 문서화**

**구현 예시**:
```bash
# Root CA 생성
openssl genrsa -out "$CERT_DIR/ca.key" 4096
openssl req -x509 -new -nodes \
  -key "$CERT_DIR/ca.key" \
  -sha256 -days 3650 \
  -out "$CERT_DIR/ca.crt" \
  -subj "/CN=Apptest-Elastic-Root-CA"

# HTTP 인증서 생성 (SAN 포함)
openssl genrsa -out "$CERT_DIR/http.key" 2048
openssl req -new -key "$CERT_DIR/http.key" -out "$CERT_DIR/http.csr" \
  -config "$CERT_DIR/http.cnf"
openssl x509 -req -in "$CERT_DIR/http.csr" \
  -CA "$CERT_DIR/ca.crt" -CAkey "$CERT_DIR/ca.key" \
  -CAcreateserial -out "$CERT_DIR/http.crt" \
  -days 3650 -sha256 -extensions req_ext -extfile "$CERT_DIR/http.cnf"

# PKCS12 형식으로 변환
openssl pkcs12 -export \
  -inkey "$CERT_DIR/http.key" \
  -in "$CERT_DIR/http.crt" \
  -certfile "$CERT_DIR/ca.crt" \
  -name http -out "$CERT_DIR/http.p12" \
  -passout pass:
```

---

### 문제 5. Kibana 접근 및 인증 설정 이슈
- Kibana ↔ Elasticsearch 인증 토큰 관리가 수동
- SaaS / Stage / On-Premise 환경별 설정 혼재
- Nginx 프록시 설정 문제로 외부 접근 불가

#### 해결 방법
- **Elasticsearch 계정 생성 후 Kibana 비밀번호 자동 발급**: 
  - `elasticsearch-reset-password` 유틸리티를 사용하여 `kibana_system` 계정 비밀번호 자동 생성
  - 생성된 비밀번호를 `kibana.yml`에 자동 설정
- **Kibana 설정 파일 자동 수정 스크립트 작성**: 
  - `sed` 명령을 통해 `elasticsearch.password` 설정 자동 업데이트
- **환경별 Kibana yml 설정 분리**: 
  - SaaS/Stage: HTTPS 연결, 인증 활성화
  - On-Premise: HTTP 연결, 인증 비활성화
- **Nginx 설정 수정 및 접근 가이드 정리**

**구현 예시**:
```bash
# Kibana 비밀번호 자동 발급
OUTPUT=$(cd /usr/share/elasticsearch && \
  bin/elasticsearch-reset-password \
    -u kibana_system \
    --url https://localhost:9200 \
    --batch)

NEW_PASS=$(echo "$OUTPUT" | grep "New value:" | awk '{print $3}')

# kibana.yml에 비밀번호 자동 설정
if grep -q "^elasticsearch.password:" /etc/kibana/kibana.yml; then
  sed -i "s|^elasticsearch.password:.*|elasticsearch.password: \"$NEW_PASS\"|" /etc/kibana/kibana.yml
else
  echo "elasticsearch.password: \"$NEW_PASS\"" >> /etc/kibana/kibana.yml
fi
```

---

### 문제 6. Elasticsearch Keystore 비밀번호 잔재 문제
이미지 빌드 과정에서 생성된 keystore 비밀번호가 남아있어  
컨테이너 시작 시 인증서 설정과 충돌하는 문제가 발생하였다.

#### 해결 방법
- `start.sh`에서 keystore 비밀번호 자동 제거 스크립트 작성
- 다음 키들을 자동으로 확인 및 제거:
  - `xpack.security.transport.ssl.keystore.secure_password`
  - `xpack.security.transport.ssl.truststore.secure_password`
  - `xpack.security.http.ssl.keystore.secure_password`
- 컨테이너 시작 시 keystore 정합성 보장

**구현 예시**:
```bash
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
  fi
done
```

---

## 5. ELK Docker 보안 & 버전 업데이트 이력

### (~1/15)
- SaaS 설정 파일 자동화 스크립트 작성
- Logstash Config / Pipeline / Dashboard 환경별 분리
- ELK 롤링 업데이트 적용
- 보안 설정(yml) 수정
- Kibana 설정 파일 환경별 분리
- 사업 운영팀 협업(대시보드 깨짐 이슈 수정)

### (~2/3)
- Elasticsearch HTTP / Transport TLS 적용 완료
- 인증서 발급 스크립트 및 문서 작성
- 보안 1단계 → 2단계 적용

### (~2/5)
- 2차 보안 업데이트 완료
- 인증서 생성 자동화
- Kibana 비밀번호 발급 및 설정 자동화
- 고객사별 Space / Dashboard 구성 자동화
- 신규 Docker 이미지 생성 및 정상 기동 확인

---

## 6. 결과 및 성과

### 보안 강화
- **ELK 8.x 기준 보안 정책 준수**: TLS 암호화 통신 적용으로 보안 수준 강화
- **인증서 자동 생성 및 배포**: 수동 작업 제거로 인한 보안 설정 오류 방지
- **환경별 보안 정책 분리**: SaaS/Stage는 보안 활성화, On-Premise는 선택적 적용

### 운영 효율성 향상
- **SaaS / Stage / On-Premise 환경별 설정 분리**로 운영 안정성 향상
- **수동 설정 제거**를 통한 초기 세팅 시간 대폭 단축 (예상: 수 시간 → 수 분)
- **버전 고정 및 표준 이미지 도입**으로 배포 신뢰성 확보
- **자동화 스크립트 기반 운영**으로 인적 오류 감소

### 기술적 개선
- **단일 Docker 이미지 구조**: 배포 및 관리 단순화
- **환경 변수 기반 설정**: `DEPLOY_ENV`로 환경별 설정 자동 선택
- **플래그 파일 기반 상태 관리**: 중복 초기화 방지 및 안정성 향상
- **고객사별 Space 자동 생성**: Dashboard 임포트 자동화

### 정량적 성과
- **버전 통일**: Elasticsearch, Logstash, Kibana 모두 8.15.2로 통일
- **환경 지원**: 3개 환경(Service, Stage, On-Premise) 지원
- **고객사 Space**: 6개 고객사별 Kibana Space 자동 생성
- **인덱스 자동 생성**: 환경별 인덱스 매핑 자동 생성

---

## 7. 사용 기술

### Container / Infra
- **Docker**: 컨테이너화 및 이미지 관리
- **Bash Script**: 자동화 스크립트 (`start.sh`, `build.sh`, `run.sh`)
- **Ubuntu 22.04 LTS (Jammy)**: 베이스 이미지

### ELK Stack
- **Elasticsearch 8.15.2**: 데이터 저장 및 검색 엔진
- **Logstash 8.15.2**: 데이터 수집 및 처리 파이프라인
- **Kibana 8.15.2**: 데이터 시각화 및 대시보드

### Security
- **TLS / SSL 인증서**: OpenSSL 기반 자체 서명 인증서 생성
- **Role / User 기반 접근 제어**: Elasticsearch 기본 인증 (`elastic`, `kibana_system`)
- **Kibana Space**: 고객사별 데이터 격리

### Network / Web
- **HTTP / Transport 통신 구조**: HTTP(9200), Transport(9300) 포트
- **Nginx Reverse Proxy**: 외부 접근 프록시 (운영 환경)

### Database
- **MySQL Connector 8.0.28**: Logstash에서 MySQL 데이터 수집용

### 기타
- **OpenSSL**: 인증서 생성 및 관리
- **jq**: JSON 파싱 및 처리
- **cron**: Logstash 스케줄링 (5분 간격)

---

## 8. 프로젝트 의의

본 프로젝트는 단순한 ELK 버전 업그레이드가 아닌,  
**SaaS 환경에서 운영 중인 로그 분석 플랫폼을 보안·운영 관점에서 재설계한 프로젝트**이다.

ELK 8.x 보안 정책 대응,  
환경별 설정 분리,  
자동화 스크립트 기반 운영 체계 구축을 통해  
**운영 안정성 · 보안성 · 유지보수성을 동시에 개선**하였다.

이를 통해 로그 분석 인프라를  
장기적으로 안정 운영 가능한 **표준 플랫폼 구조**로 전환하였다.

### 핵심 성과 요약
1. **보안 강화**: TLS 암호화 통신 적용, 인증서 자동 생성 및 배포
2. **운영 자동화**: 초기 설정 자동화로 수동 작업 제거
3. **환경 표준화**: 단일 이미지로 다중 환경 지원
4. **버전 통일**: ELK 스택 버전 일관성 확보
5. **유지보수성 향상**: 환경별 설정 분리 및 자동화 스크립트 기반 운영

---

## 9. 기술적 세부사항

### 인증서 생성 프로세스
1. **Root CA 생성**: 4096bit RSA 키, 10년 유효기간
2. **HTTP 인증서 생성**: SAN(Subject Alternative Name) 포함 (localhost, 127.0.0.1)
3. **Transport 인증서 생성**: 노드 간 통신용
4. **PKCS12 변환**: Elasticsearch에서 사용 가능한 형식으로 변환
5. **인증서 배포**: Kibana, Logstash에 CA 인증서 복사 및 권한 설정

### 환경별 설정 분리 전략
- **SaaS / Stage**: 
  - 보안 활성화 (`xpack.security.enabled: true`)
  - TLS 암호화 (HTTP/Transport)
  - 기본 인증 (`elastic` 계정)
  - 다중 고객사 Space 지원
- **On-Premise**: 
  - 보안 비활성화 (`xpack.security.enabled: false`)
  - HTTP 평문 통신
  - 단일 고객사 Space 지원

### 자동화 스크립트 흐름
1. 환경 변수 확인 (`DEPLOY_ENV`)
2. 디렉토리 및 권한 설정
3. Keystore 정합성 확인 및 정리
4. 환경별 설정 파일 선택
5. TLS 인증서 생성 (최초 실행 시)
6. Elasticsearch 시작 및 대기
7. 인덱스 생성 (최초 실행 시)
8. Logstash 시작
9. Kibana 비밀번호 발급 및 설정
10. Kibana 시작 및 대기
11. Space 및 Dashboard 생성/임포트

---

## 10. 향후 개선 방향

1. **Role/User 기반 접근 제어 고도화**: 고객사별 Role 및 User 자동 생성
2. **모니터링 및 알림**: ELK 스택 상태 모니터링 및 장애 알림 체계 구축
3. **백업 및 복구**: 인덱스 데이터 백업 및 복구 프로세스 자동화
4. **성능 최적화**: 인덱스 샤딩 전략 및 성능 튜닝
5. **CI/CD 통합**: Docker 이미지 빌드 및 배포 파이프라인 자동화
