# Opal 메모리 최적화 기록

작성일: 2026-07-20  
대상: GL.iNet Opal(GL-SFT1200), OpenWrt 18.06, 물리 메모리 118,784KB

## 최적화 결과

| 항목 | 최적화 전 | 최적화 후 | 변화 |
|---|---:|---:|---:|
| Tailscale 바이너리 | 24.4MB | 16.5MB | 7.9MB 감소(약 32%) |
| Tailscale RSS | 28.6MB | 18.2MB | 10.4MB 감소(약 36%) |
| 시스템 `MemAvailable` | 46.5MB | 50.3MB | 3.8MB 증가 |
| 카메라 서비스 | 10MB 이하 | 10MB 이하 | 변경 없음 |

Tailscale과 일반 서비스에서 확보한 실질 메모리는 약 12.3MB로 추정한다.
`MemAvailable` 증가량이 이보다 작은 이유는 종료된 실행 파일과 라이브러리 일부가
페이지 캐시에 남기 때문이다. 이 캐시는 메모리 압박 시 커널이 회수할 수 있다.

## Tailscale 최적화

- Opal 전용 MIPS little-endian 바이너리로 다시 빌드했다.
- 고정 IP 접속에 불필요한 DNS, Peer API, userspace netstack, 진단, 로그,
  클라우드 및 부가 기능을 빌드에서 제외했다.
- TUN, WireGuard, OS 라우팅, 방화벽 연동과 일반 노드 접속 기능은 유지했다.
- DNS 수용과 subnet route 수용을 비활성화했다.
- `GOMEMLIMIT=32MiB`는 유지했다.
- 기존 바이너리는 `/overlay/usr/sbin/tailscale.combined.lite.prev`에 보존했다.

## 일반 서비스 최적화

실행 및 부팅을 비활성화한 서비스:

- `gl_clients`: GL.iNet 접속 클라이언트 목록 추적
- `gl_led`: LED 상태 데몬; 현재 LED는 꺼져 있음
- `mwan3`: 다중 WAN 정책 및 주기적 회선 검사

현재 사용하지 않아 부팅만 비활성화한 계층:

- OpenVPN, VPN policy, DNSCrypt, Stubby, Tor
- GL cloud, DDNS, S2S, eQoS
- 모뎀, 테더링, SMS, WAN 속도 보고 계층

Wi-Fi, 기본 라우팅, 방화벽, DNS, SSH, nginx, fcgiwrap, USB 및 카메라 계층은 유지했다.

## 검증 결과

- Tailscale 상태 `Running`, 주소 `100.123.59.97` 유지
- 메인컴 `100.94.174.121`에서 Tailscale ping, 카메라 HTTP API, SSH 확인
- Wi-Fi WAN 인터넷 통신 정상
- 카메라 API `ready`, D810 연결 정상
- 최적화 이후 새로운 OOM 없음
- 과거 OOM 로그는 46MB 수준의 이전 Tailscale 바이너리에서 발생한 기록임

## 충분성 판단 기준

현재 평상시 `MemAvailable`은 약 50MB이므로 추가 감축을 서두를 필요는 없다.
라이브뷰, 연속 촬영, Tailscale 통신을 동시에 실행했을 때 다음 기준을 적용한다.

- 최저 25MB 이상: 현 최적화를 완료 상태로 판단
- 20~25MB: 추적 관찰하되 기능 감축은 보류
- 20MB 미만 또는 OOM 발생: 2차 최적화 검토

2차 최적화가 필요해질 때만 카메라 감시 프로세스 중복과 관리 웹 계층을 조사한다.
현재는 카메라 계층을 변경하지 않는다.

## 관련 파일

- 빌드 스크립트: `scripts/build-tailscale-opal-lite.sh`
- 서비스 작업 및 복구 기록: `docs/opal-service-optimization-2026-07-20.md`
- Opal init 스크립트: `scripts/tailscaled-opal.init`
