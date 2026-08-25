# Underlab Camera 진단 분류 계약

작성일: 2026-08-26  
대상: Opal 라우터, Nikon D810 PTP 경로, S10 Flutter 애플리케이션

## 1. 목적

DIAG는 단순히 `정상/고장`을 반환하지 않는다. 각 구성 요소를 독립적으로 관측하고,
발생 조건과 실제 영향을 구분하여 가장 작은 범위의 대응을 선택한다.

이 문서는 현재 코드에서 발생 가능한 상태와 프로젝트 구조상 예상 가능한 상태를
정규화한 진단 계약이다. 이후 DIAG 구현과 UI 표시는 이 문서의 코드와 의미를 따른다.

## 2. 상태 정의

운영 상태는 다음 세 가지뿐이다.

| 상태 | UI | 정의 |
|---|---|---|
| `NORMAL` | 초록색 | 해당 기능의 요구 조건과 검증 경로가 모두 정상이다. |
| `LIMITED` | 노란색 | 장비 또는 제조사 정책이 의도적으로 일부 동작을 제한한다. 기능 고장이 아니다. |
| `FAULT` | 빨간색 | 요구된 기능이 비정상 상태이거나 검증된 경로가 망가졌다. |

`UNKNOWN`은 운영 상태가 아니라 **진단 증거 상태**다. 검사하지 못했거나 상위 계층
문제로 검사가 차단됐다는 의미이며, 그 자체를 빨간색 고장으로 표시하지 않는다.

### 2.1 87개 병명의 표시색

운영 상태 색상과 DIAG 목록의 병명 색상은 구분한다.

| 진단 상태 | DIAG 표시색 | 의미 |
|---|---|---|
| `NORMAL` | 초록 | 이 항목은 정상이며 시스템 조치가 필요 없다. |
| `LIMITED` | 노랑 | 기능 제한 또는 성능 제한이 있으나 고장은 아니다. |
| `FAULT` | 빨강 | 기능 고장이 확인됐거나 복구가 필요한 상태다. |
| `TRANSIENT` | 노랑 | 현재 관찰 또는 제한된 재시도 중이며 아직 고장 확정은 아니다. |
| `UNKNOWN` | 노랑 | 증거가 부족하거나 상위 문제로 확인할 수 없어 주의가 필요하다. |

따라서 전체 카메라 상태의 초록·노랑·빨강 규칙은 `NORMAL/LIMITED/FAULT`를 따르고,
DIAG 상세 목록에서는 `TRANSIENT/UNKNOWN`도 노란 주의색으로 표시한다. 이 둘은 빨간색
고장으로 승격되지 않는다. `TRANSIENT`가 재시도 한계를 넘으면 대응 전용 `*_EXHAUSTED`
고장으로 승격하고, `UNKNOWN`이 기능 미검증으로 남으면 사용자에게 확인을 요청한다.

현재 87개 병명의 분포는 빨강 64개, 노랑 20개, 초록 3개다.

## 2.2 11개 분야를 5개 운영 영역으로 통합

기능 매칭 전에 진단의 소유 영역만 확정한다. 아래의 `영역`은 실제로 어느 계층이
판정하고 대응해야 하는지를 뜻하며, 기존 `분야`는 원인 출처와 세부 진단 계층으로
보존한다. 한 병명은 주 영역 하나만 갖는다.

| 운영 영역 | 포함되는 기존 분야 | 영역의 책임 |
|---|---|---|
| `CAMERA` | CAMERA, POWER, STORAGE, CAPTURE | 카메라 본체·전원·저장매체·촬영 결과 |
| `PTP` | PTP, SESSION 일부, RUNTIME 일부 | ddserver·PTP 세션·카메라 기능 인증 |
| `COMMAND` | COMMAND | AF·설정·촬영 명령의 유효성과 결과 |
| `LV` | LV, DELIVERY 일부, SESSION 일부, RUNTIME 일부 | LV 생성·프레임·Opal 전달 |
| `APP` | APP, DELIVERY 일부, SESSION 일부, RUNTIME 일부 | S10 앱·네트워크·앱 작업자·표시 |

### CAMERA 영역 [AREA:CAMERA] — 23개

| 원래 분야 | 병명 ID | 색상 |
|---|---|---|
| CAMERA | `CAMERA.USB_NOT_DETECTED` | 빨강 |
| CAMERA | `CAMERA.HARDWARE_NOT_RECOGNIZED` | 빨강 |
| CAMERA | `CAMERA.DEVICE_SELECTION_FAILED` | 빨강 |
| CAMERA | `CAMERA.PTP_OPEN_REJECTED` | 빨강 |
| CAMERA | `CAMERA.RESPONSE_ERROR` | 빨강 |
| CAMERA | `CAMERA.CONTROL_OWNERSHIP_CONFLICT` | 빨강 |
| POWER | `POWER.LOW_BATTERY` | 노랑 |
| POWER | `POWER.BATTERY_UNREADABLE` | 노랑 |
| POWER | `POWER.BATTERY_STALE` | 노랑 |
| POWER | `POWER.CAMERA_POWER_LOST` | 빨강 |
| STORAGE | `STORAGE.CARD_UNAVAILABLE` | 빨강 |
| STORAGE | `STORAGE.INFO_UNAVAILABLE` | 빨강 |
| STORAGE | `STORAGE.OBJECT_LIST_FAILED` | 빨강 |
| STORAGE | `STORAGE.OBJECT_INFO_FAILED` | 빨강 |
| CAPTURE | `CAPTURE.NO_NEW_OBJECT` | 빨강 |
| CAPTURE | `CAPTURE.JPEG_NOT_FOUND` | 빨강 |
| CAPTURE | `CAPTURE.NEF_NOT_FOUND` | 빨강 |
| CAPTURE | `CAPTURE.THUMB_UNAVAILABLE` | 노랑 |
| CAPTURE | `CAPTURE.OBJECT_BUSY` | 노랑 |
| CAPTURE | `CAPTURE.CHUNK_EMPTY` | 빨강 |
| CAPTURE | `CAPTURE.SIZE_MISMATCH` | 빨강 |
| CAPTURE | `CAPTURE.JPEG_INVALID` | 빨강 |
| CAPTURE | `CAPTURE.SETTING_REJECTED` | 빨강 |

### PTP 영역 [AREA:PTP] — 17개

| 원래 분야 | 병명 ID | 색상 |
|---|---|---|
| RUNTIME | `RUNTIME.DDSERVER_STOPPED` | 빨강 |
| RUNTIME | `RUNTIME.BRIDGE_STOPPED` | 빨강 |
| RUNTIME | `RUNTIME.DUPLICATE_OWNER` | 빨강 |
| RUNTIME | `RUNTIME.STALE_LOCK` | 빨강 |
| RUNTIME | `RUNTIME.DEPENDENCY_UNAVAILABLE` | 빨강 |
| PTP | `PTP.CONNECT_FAILED` | 빨강 |
| PTP | `PTP.SESSION_UNAVAILABLE` | 빨강 |
| PTP | `PTP.SESSION_LOST` | 빨강 |
| PTP | `PTP.WRITE_FAILED` | 빨강 |
| PTP | `PTP.READ_TIMEOUT` | 빨강 |
| PTP | `PTP.CONTAINER_INVALID` | 빨강 |
| PTP | `PTP.PACKET_LENGTH_INVALID` | 빨강 |
| PTP | `PTP.TRANSPORT_CLOSED` | 빨강 |
| PTP | `PTP.PROBE_FAILED` | 빨강 |
| SESSION | `SESSION.CAPABILITY_UNCERTIFIED` | 노랑 |
| SESSION | `SESSION.REQUIRED_PROPERTY_MISSING` | 빨강 |
| SESSION | `SESSION.STORAGE_CERTIFICATION_FAILED` | 빨강 |

### COMMAND 영역 [AREA:COMMAND] — 6개

| 원래 분야 | 병명 ID | 색상 |
|---|---|---|
| COMMAND | `COMMAND.BUSY` | 노랑 |
| COMMAND | `COMMAND.BUSY_EXHAUSTED` | 빨강 |
| COMMAND | `COMMAND.ROUTE_NOT_READY` | 빨강 |
| COMMAND | `COMMAND.APP_NOT_READY` | 노랑 |
| COMMAND | `COMMAND.CAMERA_REJECTED` | 빨강 |
| COMMAND | `COMMAND.AMBIGUOUS_CAPTURE_RESULT` | 노랑 |

### LV 영역 [AREA:LV] — 17개

| 원래 분야 | 병명 ID | 색상 |
|---|---|---|
| RUNTIME | `RUNTIME.WEBSOCKET_STOPPED` | 빨강 |
| SESSION | `SESSION.LV_CERTIFICATION_FAILED` | 빨강 |
| LV | `LV.BLOCKED_LOW_BATTERY` | 노랑 |
| LV | `LV.CAMERA_STATE_MISMATCH` | 빨강 |
| LV | `LV.START_BUSY` | 노랑 |
| LV | `LV.START_FAILED` | 빨강 |
| LV | `LV.RESTORE_FAILED` | 빨강 |
| LV | `LV.STOP_FAILED` | 빨강 |
| LV | `LV.FRAME_EMPTY` | 빨강 |
| LV | `LV.FRAME_NOT_JPEG` | 빨강 |
| LV | `LV.FRAME_STALE` | 빨강 |
| LV | `LV.FRAME_LOCK_TIMEOUT` | 노랑 |
| LV | `LV.FRAME_CACHE_WRITE_FAILED` | 빨강 |
| DELIVERY | `DELIVERY.WS_UNAVAILABLE` | 빨강 |
| DELIVERY | `DELIVERY.FRAME_NOT_PUBLISHED` | 빨강 |
| DELIVERY | `DELIVERY.DIRECT_STREAM_FAILED` | 빨강 |
| DELIVERY | `DELIVERY.FALLBACK_ACTIVE` | 노랑 |

### APP 영역 [AREA:APP] — 21개

| 원래 분야 | 병명 ID | 색상 |
|---|---|---|
| RUNTIME | `RUNTIME.BATTERY_WORKER_STOPPED` | 빨강 |
| RUNTIME | `RUNTIME.SESSION_HEALTH_STOPPED` | 빨강 |
| RUNTIME | `RUNTIME.GUARDIAN_STOPPED` | 빨강 |
| RUNTIME | `RUNTIME.START_LOCK_BUSY` | 노랑 |
| RUNTIME | `RUNTIME.BOOT_BUSY` | 노랑 |
| SESSION | `SESSION.CLIENT_ID_MISSING` | 빨강 |
| SESSION | `SESSION.CLIENT_ID_STALE` | 빨강 |
| SESSION | `SESSION.READINESS_CONTRACT_FAILED` | 빨강 |
| SESSION | `SESSION.RECOVERY_EXHAUSTED` | 빨강 |
| DELIVERY | `DELIVERY.CLIENT_DISCONNECTED` | 노랑 |
| DELIVERY | `DELIVERY.WIFI_UNREACHABLE` | 빨강 |
| DELIVERY | `DELIVERY.HTTP_UNREACHABLE` | 빨강 |
| APP | `APP.STATUS_SINGLE_TIMEOUT` | 노랑 |
| APP | `APP.STATUS_UNAVAILABLE` | 빨강 |
| APP | `APP.CONTRACT_PARSE_FAILED` | 빨강 |
| APP | `APP.WS_RECONNECTING` | 노랑 |
| APP | `APP.FRAME_DECODE_FAILED` | 빨강 |
| APP | `APP.RENDER_STALLED` | 빨강 |
| APP | `APP.FRAME_QUEUE_PRESSURE` | 노랑 |
| APP | `APP.FPS_DEGRADED` | 노랑 |
| APP | `APP.VERSION_MISMATCH` | 빨강 |

이 통합표는 기능 매칭표가 아니다. 예를 들어 `CAMERA` 영역에 속한다고 해서 특정
카메라 기능을 배정한 것이 아니며, 진단을 어느 계층이 소유하는지만 확정한다.

초록 3개(`COMMAND.INVALID_INPUT`, `COMMAND.FOCUS_NOT_ACQUIRED`,
`LV.PRECONDITION_INACTIVE`)는 고장 병명이 아니므로 문제 84개 통합표에서 제외한다.

일시적인 명령 거부는 별도의 사건 속성 `TRANSIENT`로 기록한다. 최초의
`camera_busy`, 잠금 경합, 사용자가 취소한 동작은 즉시 시스템 `FAULT`로 승격하지 않는다.

## 3. 진단 결과의 필수 필드

각 진단 항목은 다음 필드를 빠짐없이 가진다.

| 필드 | 의미 | 예시 |
|---|---|---|
| `id` | 변경되지 않는 정규 진단 코드 | `POWER.LOW_BATTERY` |
| `domain` | 고장이 실제로 발생한 소유 계층 | `POWER` |
| `component` | 검사 대상 | `camera_battery` |
| `state` | `NORMAL`, `LIMITED`, `FAULT` | `LIMITED` |
| `evidenceState` | `VERIFIED`, `INFERRED`, `UNKNOWN` | `VERIFIED` |
| `reason` | 기계 판독용 원인 | `low_battery` |
| `observedValue` | 실제 측정값 | `20` |
| `expectedValue` | 정상 조건 | `>20` |
| `source` | 증거 출처 | `ptp` |
| `observedAtMs` | 검사 시각 | Unix ms |
| `impact` | 제한되거나 실패한 기능 목록 | `["live_view"]` |
| `blockedBy` | 검사를 막은 상위 진단 코드 | `PTP.SESSION_UNAVAILABLE` |
| `response` | 정규 대응 코드 | `USER_REPLACE_BATTERY` |
| `owner` | `NONE`, `AUTO`, `USER` | `USER` |
| `retryable` | 같은 상태에서 재시도할 수 있는지 | `false` |
| `confidence` | `high`, `medium`, `low` | `high` |
| `displayColor` | `GREEN`, `YELLOW`, `RED` | `YELLOW` |

문자열 메시지는 UI 번역용이며 판정 조건으로 사용하지 않는다.

## 4. 진단 계층과 의존 관계

```text
CAMERA_PHYSICAL
  ├─ POWER
  └─ RUNTIME_PROCESS
       └─ PTP_TRANSPORT
            └─ PTP_SESSION
                 ├─ COMMAND
                 ├─ LIVE_VIEW
                 │    └─ FRAME_DELIVERY
                 │         └─ APPLICATION_RENDER
                 └─ STORAGE
                      └─ CAPTURE_OBJECT
```

상위 계층이 실패하면 하위 계층을 임의로 `FAULT` 처리하지 않는다. 예를 들어 카메라가
분리된 상태에서 LV 프레임을 받을 수 없는 것은 별도의 LV 고장이 아니다. LV 결과는
`UNKNOWN`, `blockedBy=CAMERA.USB_NOT_DETECTED`가 된다.

## 5. 정규 문제 분류

### 5.1 CAMERA — 물리 카메라와 USB

| ID | 상태 | 판정 증거 | 영향 | 대응 |
|---|---|---|---|---|
| `CAMERA.USB_NOT_DETECTED` | FAULT | USB 장치 경로 없음 | 모든 카메라 기능 | `USER_CHECK_POWER_USB` |
| `CAMERA.HARDWARE_NOT_RECOGNIZED` | FAULT | USB는 있으나 Nikon VID/PID 또는 대상 장치 불일치 | 모든 카메라 기능 | `USER_RECONNECT_CAMERA` |
| `CAMERA.DEVICE_SELECTION_FAILED` | FAULT | ddserver 장치 목록은 있으나 대상 카메라 선택 실패 | PTP 이후 전체 | `AUTO_REBUILD_SESSION`, 실패 시 사용자 확인 |
| `CAMERA.PTP_OPEN_REJECTED` | FAULT | 카메라가 장치 연결 또는 세션 열기를 거부 | PTP 이후 전체 | `AUTO_REOPEN_PTP`, 반복 시 `USER_POWER_CYCLE_CAMERA` |
| `CAMERA.RESPONSE_ERROR` | FAULT | Nikon 응답 코드가 해당 명령의 허용 범위 밖 | 해당 명령 또는 기능 | 응답 코드별 최소 복구 |
| `CAMERA.CONTROL_OWNERSHIP_CONFLICT` | FAULT | 다른 호스트/프로세스가 카메라 제어권 보유 | 명령·LV | 중복 소유자 종료 후 세션 재구성 |

### 5.2 POWER — 전원과 제조사 제한

| ID | 상태 | 판정 증거 | 영향 | 대응 |
|---|---|---|---|---|
| `POWER.LOW_BATTERY` | LIMITED | PTP 배터리 값 `<=20%` | LV 시작만 차단 | `USER_REPLACE_BATTERY`, 자동복구 없음 |
| `POWER.BATTERY_UNREADABLE` | UNKNOWN | PTP 배터리 속성 읽기 실패 | 배터리 표시·제한 판정 불확실 | PTP 상태 확인 후 1회 재측정 |
| `POWER.BATTERY_STALE` | UNKNOWN | 측정 시각이 허용 TTL 초과 | 현재 배터리 판단 금지 | 카메라에 직접 재질의 |
| `POWER.CAMERA_POWER_LOST` | FAULT | 이전에 연결됐던 USB 장치와 PTP 응답이 함께 사라짐 | 모든 카메라 기능 | `USER_CHECK_POWER_USB` |

배터리 값을 읽지 못했을 때 `100%` 또는 `0%`를 만들어내지 않는다. 마지막 값이 있더라도
오래됐으면 `UNKNOWN`으로 표시한다.

### 5.3 RUNTIME — Opal 프로세스와 소유권

| ID | 상태 | 판정 증거 | 영향 | 대응 |
|---|---|---|---|---|
| `RUNTIME.DDSERVER_STOPPED` | FAULT | 소유 pid 없음, 포트 응답 없음 | PTP 전체 | `AUTO_RESTART_DDSERVER` |
| `RUNTIME.BRIDGE_STOPPED` | FAULT | 브리지 pid/health/포트 모두 실패 | 명령·LV·파일 | `AUTO_RESTART_BRIDGE` |
| `RUNTIME.WEBSOCKET_STOPPED` | FAULT | WS 작업자 없음 또는 health 만료 | LV 전달 | `AUTO_RESTART_WEBSOCKET` |
| `RUNTIME.BATTERY_WORKER_STOPPED` | FAULT | 작업자 pid 없음 | 주기 배터리 갱신 | `AUTO_RESTART_BATTERY_WORKER` |
| `RUNTIME.SESSION_HEALTH_STOPPED` | FAULT | 상태 감시 작업자 없음 | 자동 상태 검증 | `AUTO_RESTART_HEALTH_WORKER` |
| `RUNTIME.GUARDIAN_STOPPED` | FAULT | guardian pid 없음 | 자동복구 능력 | `AUTO_RESTART_GUARDIAN` |
| `RUNTIME.DUPLICATE_OWNER` | FAULT | 동일 구성 요소의 살아 있는 소유 프로세스가 2개 이상 | 명령 충돌·프레임 경합 | 프로젝트 소유 pid만 정리 후 재시작 |
| `RUNTIME.START_LOCK_BUSY` | TRANSIENT | 유효한 시작 잠금 보유자 존재 | 시작 지연 | 잠금 만료까지 대기 |
| `RUNTIME.STALE_LOCK` | FAULT | 소유 pid가 없거나 TTL을 넘긴 잠금 | 해당 작업 차단 | 해당 잠금만 제거 후 재검증 |
| `RUNTIME.BOOT_BUSY` | TRANSIENT | 다른 유효한 session-manager 부팅 진행 중 | 앱 준비 지연 | 기존 부팅 결과 대기 |
| `RUNTIME.DEPENDENCY_UNAVAILABLE` | FAULT | 필수 Lua/socket 런타임 준비 실패 | 브리지 또는 WS 시작 | 프로젝트 런타임 재준비 |

### 5.4 PTP_TRANSPORT — ddserver 전송

| ID | 상태 | 판정 증거 | 영향 | 대응 |
|---|---|---|---|---|
| `PTP.CONNECT_FAILED` | FAULT | ddserver TCP 연결 실패 | PTP 전체 | ddserver 상태 확인 후 `AUTO_REOPEN_PTP` |
| `PTP.SESSION_UNAVAILABLE` | FAULT | 소켓은 있으나 PTP 세션이 열리지 않음 | 카메라 명령 전체 | `AUTO_REOPEN_PTP` |
| `PTP.SESSION_LOST` | FAULT | 명령 전후 세션 손실 응답 | 진행 중 명령과 이후 명령 | 멱등 명령만 1회 재연결·재시도 |
| `PTP.WRITE_FAILED` | FAULT | 요청 패킷 쓰기 실패 | 해당 요청 | 재연결 후 안전한 요청만 재시도 |
| `PTP.READ_TIMEOUT` | FAULT | 제한 시간 안에 응답 없음 | 해당 요청 | 카메라 busy 여부 구분 후 재연결 |
| `PTP.CONTAINER_INVALID` | FAULT | 길이·타입·트랜잭션이 유효하지 않음 | 해당 요청, 세션 신뢰 상실 | 세션 폐기 후 재구성 |
| `PTP.PACKET_LENGTH_INVALID` | FAULT | 최소/최대 범위를 벗어난 패킷 길이 | 전송 안전성 | 세션 폐기, 반복 시 ddserver 재시작 |
| `PTP.TRANSPORT_CLOSED` | FAULT | ddserver가 연결을 닫음 | PTP 전체 | 원인 로그 보존 후 재연결 |
| `PTP.PROBE_FAILED` | FAULT | 읽기 전용 속성 프로브 실패 | 현재 세션 검증 실패 | 세션 재구성 |

### 5.5 SESSION — 세션과 기능 인증

| ID | 상태 | 판정 증거 | 영향 | 대응 |
|---|---|---|---|---|
| `SESSION.CLIENT_ID_MISSING` | FAULT | 명령 세션 ID 누락 | 해당 클라이언트 명령 | 상태 재동기화 후 새 세션 ID 사용 |
| `SESSION.CLIENT_ID_STALE` | FAULT | 클라이언트 ID와 현재 세션 불일치 | 해당 클라이언트 명령 | 앱 상태 갱신, 명령 자동 재전송 금지 |
| `SESSION.CAPABILITY_UNCERTIFIED` | UNKNOWN | 현재 프로세스에서 기능 인증 전 | READY 표시 금지 | 읽기·기능 인증 수행 |
| `SESSION.REQUIRED_PROPERTY_MISSING` | FAULT | 필수 Nikon 속성 읽기 불가 | 관련 기능과 READY | 카메라 모델·모드 확인 |
| `SESSION.STORAGE_CERTIFICATION_FAILED` | FAULT | storage ID/info/object list 검증 실패 | 촬영 파일 경로 | 저장장치 진단으로 이동 |
| `SESSION.LV_CERTIFICATION_FAILED` | FAULT | 제한 상태가 아닌데 유효 JPEG 인증 실패 | LV | LV 계층 진단으로 이동 |
| `SESSION.READINESS_CONTRACT_FAILED` | FAULT | 필수 준비 필드 조합 불일치 | 앱 READY | 실패 필드의 원인 계층 재진단 |
| `SESSION.RECOVERY_EXHAUSTED` | FAULT | 정해진 자동복구 단계 후 동일 증거 유지 | 영향 기능 | 사용자 조치 또는 로그 분석 요청 |

### 5.6 COMMAND — 카메라 명령

| ID | 상태 | 판정 증거 | 영향 | 대응 |
|---|---|---|---|---|
| `COMMAND.BUSY` | TRANSIENT | Nikon DeviceBusy 또는 유효 명령 잠금 | 해당 명령 | 짧은 bounded retry, 전체 장애로 승격 금지 |
| `COMMAND.BUSY_EXHAUSTED` | FAULT | 제한된 재시도 후에도 DeviceBusy | 해당 명령·세션 | 명령 상태 확인 후 세션 재구성 |
| `COMMAND.ROUTE_NOT_READY` | FAULT | command capability 또는 transport false | 명령 전체 | 세션/전송 계층 복구 |
| `COMMAND.APP_NOT_READY` | UNKNOWN | 상위 준비 계약 미완료 | 사용자 명령 차단 | `blockedBy` 원인 해소 대기 |
| `COMMAND.INVALID_INPUT` | NORMAL | 지원하지 않는 값·형식 | 해당 요청만 거부 | UI 입력 수정, 복구 금지 |
| `COMMAND.FOCUS_NOT_ACQUIRED` | NORMAL | AF 수행 후 초점 획득 실패 | 해당 AF/촬영 결과 | 장면·렌즈 상태 안내, 시스템 복구 금지 |
| `COMMAND.CAMERA_REJECTED` | FAULT | 허용되지 않은 Nikon 응답 | 해당 기능 | 응답 코드와 카메라 모드에 따라 대응 |
| `COMMAND.AMBIGUOUS_CAPTURE_RESULT` | UNKNOWN | 셔터 전송 후 연결이 끊겨 실행 여부 불명 | 중복 촬영 위험 | 셔터 재전송 금지, 이벤트·파일로 결과 확인 |

### 5.7 LIVE_VIEW — 카메라 LV 생성

| ID | 상태 | 판정 증거 | 영향 | 대응 |
|---|---|---|---|---|
| `LV.BLOCKED_LOW_BATTERY` | LIMITED | `POWER.LOW_BATTERY` 검증됨 | LV 시작 | 사용자 배터리 교체, 재시도·복구 금지 |
| `LV.PRECONDITION_INACTIVE` | NORMAL | 프레임 요청 시 명시적 LV intent 없음 | 해당 프레임 요청 | 요청 순서 수정, 복구 금지 |
| `LV.CAMERA_STATE_MISMATCH` | FAULT | 앱 intent와 Nikon LV 상태 불일치 | LV | 카메라 상태 재조회 후 한 방향으로 정합화 |
| `LV.START_BUSY` | TRANSIENT | 시작 중 DeviceBusy/비동기 settle | LV 시작 지연 | 정해진 횟수만 대기·재확인 |
| `LV.START_FAILED` | FAULT | 저전압이 아니며 시작 응답이 최종 실패 | LV | 세션 재구성 후 1회 재검증 |
| `LV.RESTORE_FAILED` | FAULT | 전송 복구 후 명시적 LV intent 복원 실패 | LV | 세션 재구성, 반복 시 사용자 조치 |
| `LV.STOP_FAILED` | FAULT | 카메라 LV 종료 확인 실패 | 다음 명령 안정성 | 로컬 producer 차단 후 PTP 재확인 |
| `LV.FRAME_EMPTY` | FAULT | LV payload 비어 있음 | LV 영상 | 프레임 재요청 후 세션 확인 |
| `LV.FRAME_NOT_JPEG` | FAULT | JPEG 시작/끝 마커 또는 최소 길이 불일치 | LV 영상 | 프레임 폐기, 반복 시 세션 재구성 |
| `LV.FRAME_STALE` | FAULT | 최근 프레임 age가 허용치 초과 | 영상 정지 | producer·PTP·delivery 순서로 진단 |
| `LV.FRAME_LOCK_TIMEOUT` | TRANSIENT | 프레임/명령 잠금 경합 | 단일 프레임 | 프레임 폐기, 다음 프레임 진행 |
| `LV.FRAME_CACHE_WRITE_FAILED` | FAULT | Opal 캐시 쓰기 실패 | fallback 전달 | 저장공간·권한 확인, direct stream과 분리 판정 |

### 5.8 DELIVERY — Opal에서 S10까지 프레임 전달

| ID | 상태 | 판정 증거 | 영향 | 대응 |
|---|---|---|---|---|
| `DELIVERY.WS_UNAVAILABLE` | FAULT | WS 프로세스·포트·health 실패 | LV 전달 | WS 작업자 재시작 |
| `DELIVERY.CLIENT_DISCONNECTED` | TRANSIENT | WS close/ping 실패 | 해당 S10 스트림 | 앱 네트워크 확인 후 재접속 |
| `DELIVERY.FRAME_NOT_PUBLISHED` | FAULT | 카메라 프레임은 최신이나 WS publish 시각 만료 | LV 전달 | WS 경로만 복구 |
| `DELIVERY.DIRECT_STREAM_FAILED` | FAULT | bridge→WS direct stream 실패 | LV 성능/전달 | direct stream 재연결, fallback 상태 명시 |
| `DELIVERY.FALLBACK_ACTIVE` | LIMITED | direct stream 실패 후 파일 fallback 정상 | FPS·지연 성능 제한 | 기능 유지, 백그라운드에서 direct 경로 복구 |
| `DELIVERY.WIFI_UNREACHABLE` | FAULT | S10에서 Opal HTTP와 WS 모두 접근 불가 | 앱 전체 원격 기능 | Wi-Fi 연결·라우팅 확인 |
| `DELIVERY.HTTP_UNREACHABLE` | FAULT | Wi-Fi는 연결됐으나 API 요청 실패 | 상태·명령 | Opal HTTP/CGI 경로 확인 |

### 5.9 APPLICATION — S10 앱과 렌더링

| ID | 상태 | 판정 증거 | 영향 | 대응 |
|---|---|---|---|---|
| `APP.STATUS_SINGLE_TIMEOUT` | TRANSIENT | 상태 요청 1~2회 실패 | 표시 갱신 지연 | 기존 정상 상태 유지, 재조회 |
| `APP.STATUS_UNAVAILABLE` | FAULT | 상태 요청 3회 이상 연속 실패 | READY 판정 | 네트워크·HTTP 진단으로 연결 |
| `APP.CONTRACT_PARSE_FAILED` | FAULT | 필수 JSON 필드 타입/형식 오류 | 상태 표시·명령 게이트 | 서버/앱 계약 버전 확인 |
| `APP.WS_RECONNECTING` | TRANSIENT | 연결 복구 진행 중 | LV 일시 중단 | bounded reconnect |
| `APP.FRAME_DECODE_FAILED` | FAULT | JPEG 수신 성공, 디코드 실패 | 화면 표시 | 해당 프레임 폐기, 반복 시 payload 검증 |
| `APP.RENDER_STALLED` | FAULT | 수신 frame ID 증가, 표시 frame ID 정지 | 화면 정지 | 디코드 큐·렌더러 재초기화 |
| `APP.FRAME_QUEUE_PRESSURE` | LIMITED | 수신률이 표시 능력을 지속 초과 | 지연·메모리 | 최신 프레임 우선, 오래된 프레임 폐기 |
| `APP.FPS_DEGRADED` | LIMITED | 기능은 유지되나 목표 FPS 미달 | 사용감·지연 | 병목 계층 계측 후 성능 대응 |
| `APP.VERSION_MISMATCH` | FAULT | 앱과 Opal 계약 버전 불일치 | 일부 또는 전체 기능 | 호환 버전 배포 |

성능 저하는 기능 고장과 구분한다. 프레임이 계속 전달되고 조작 가능한 경우
`LIMITED`, 프레임이 멈췄거나 기능 계약을 만족하지 못하면 `FAULT`다.

### 5.10 STORAGE / CAPTURE — 촬영과 파일

| ID | 상태 | 판정 증거 | 영향 | 대응 |
|---|---|---|---|---|
| `STORAGE.CARD_UNAVAILABLE` | FAULT | storage ID 없음 | 카드 촬영·파일 조회 | 사용자 SD카드 확인 |
| `STORAGE.INFO_UNAVAILABLE` | FAULT | storage info 읽기 실패 | 용량·파일 경로 | PTP 재검증 후 카드 확인 |
| `STORAGE.OBJECT_LIST_FAILED` | FAULT | object handle 목록 실패 | 갤러리·촬영 결과 확인 | PTP/카드 경로 복구 |
| `STORAGE.OBJECT_INFO_FAILED` | FAULT | 특정 handle 정보 실패 | 해당 파일 | 목록 새로고침 후 재선택 |
| `CAPTURE.NO_NEW_OBJECT` | FAULT | 셔터 완료 후 새 파일·이벤트 없음 | 촬영 결과 | 재촬영 전 이벤트·카메라 상태 확인 |
| `CAPTURE.JPEG_NOT_FOUND` | FAULT | 최신 JPEG handle 없음 | 미리보기·다운로드 | 포맷·카드 저장 완료 확인 |
| `CAPTURE.NEF_NOT_FOUND` | FAULT | 요청한 NEF handle 없음 | RAW 다운로드 | 촬영 포맷 확인 |
| `CAPTURE.THUMB_UNAVAILABLE` | LIMITED | 원본은 있으나 thumbnail 없음 | 빠른 미리보기 | 원본 JPEG 경로 사용 또는 안내 |
| `CAPTURE.OBJECT_BUSY` | TRANSIENT | 다운로드 직렬화 잠금 사용 중 | 해당 다운로드 | 현재 전송 완료 후 재요청 |
| `CAPTURE.CHUNK_EMPTY` | FAULT | 다운로드 중 빈 chunk | 파일 전송 | 해당 다운로드 중단, PTP 재확인 |
| `CAPTURE.SIZE_MISMATCH` | FAULT | 예상 크기와 수신 바이트 불일치 | 파일 무결성 | 결과 폐기 후 재다운로드 |
| `CAPTURE.JPEG_INVALID` | FAULT | JPEG 마커 검증 실패 | 미리보기·저장 | 결과 폐기, 원본/전송 경로 진단 |
| `CAPTURE.SETTING_REJECTED` | FAULT | RAW/JPEG 크기 등 설정 확인 실패 | 촬영 설정 | 카메라 모드·지원값 확인 |

### 5.11 USER_ACTION — 사용자가 직접 판단해야 하는 문제

다음 문제는 자동으로 고치려 하지 않는다. 시스템은 원인과 증거를 정확히 보여주고,
필요한 사용자 조치만 안내한다. 진단 프로세스는 재시작·설정 변경·반복 명령을 수행하지 않는다.

| 상황 | 상태 | 시스템의 목적 | 금지 동작 | 사용자 안내 |
|---|---|---|---|---|
| 배터리 부족으로 LV 제한 | LIMITED | 제조사 제한임을 알림 | LV 재시도·복구 루프 | 배터리 교체 또는 충전 |
| 카메라 전원/USB 분리 | FAULT | 물리 연결 상실을 알림 | PTP·브리지 반복 재시작 | 카메라 전원·USB 확인 |
| SD카드 없음/오류 | FAULT | 저장 경로 실패를 알림 | 촬영·파일 명령 반복 | SD카드와 저장 매체 확인 |
| 렌즈 초점 획득 실패 | NORMAL 사건 | 촬영 결과를 알림 | 세션 재구성 | 피사체·렌즈·AF 조건 확인 |
| 셔터 실행 여부 불명 | UNKNOWN | 중복 촬영 위험을 알림 | 셔터 재전송 | 카메라와 파일 목록 확인 |
| 카메라 펌웨어/기계장치 거부 | FAULT | 응답 코드와 기능을 알림 | 무제한 재시도 | 카메라 상태와 매뉴얼 확인 |
| 원인 증거 부족 | UNKNOWN | 확인 불가 상태를 알림 | 추측에 의한 복구 | 추가 관찰 또는 사용자 확인 |

사용자 조치 항목의 공통 대응은 `USER_NOTIFY`이며, `owner=USER`,
`autoRecovery=false`, `retryable=false`를 기본값으로 한다. 단순 상태 재조회는 허용하지만
장비 상태를 바꾸는 자동 조치는 수행하지 않는다.

## 6. 고장이 아닌 사건

다음 항목은 단독으로 시스템 `FAULT`를 만들지 않는다.

| 사건 | 처리 |
|---|---|
| `focus_failed` | 장면 또는 렌즈의 초점 획득 결과로 기록한다. |
| 최초 `camera_busy` | `TRANSIENT`로 기록하고 제한된 재시도만 수행한다. |
| `invalid_*` | 사용자/클라이언트 입력 오류로 반환하며 복구하지 않는다. |
| 명시적 `LIVE_STOP` 이후 프레임 없음 | 정상 정지 상태다. |
| 저전압 LV 거부 | `LIMITED`, 자동복구 금지다. |
| 앱이 요청하지 않은 LV가 비활성 | 정상 상태다. |
| 사용자가 취소한 다운로드·화면 전환 | 정상 사용자 행동이다. |

## 7. 대응 코드

| 대응 코드 | 수행 주체 | 의미 |
|---|---|---|
| `NO_ACTION` | NONE | 정상 또는 정보성 결과 |
| `WAIT_AND_RETRY` | AUTO | 같은 작업을 제한 횟수 내 재시도 |
| `REFRESH_STATUS` | AUTO | 상태만 다시 읽음 |
| `REOPEN_PTP` | AUTO | ddserver를 유지하고 PTP 세션만 재구성 |
| `RESTART_COMPONENT` | AUTO | 실패한 작업자 하나만 재시작 |
| `RESTART_BRIDGE` | AUTO | 브리지 프로세스만 교체 |
| `REBUILD_SESSION` | AUTO | 현재 프로젝트 세션을 재구성 |
| `FALLBACK_DEGRADED` | AUTO | 기능을 유지하는 제한 경로로 전환 |
| `USER_REPLACE_BATTERY` | USER | 배터리 교체 또는 충전 |
| `USER_NOTIFY` | USER | 원인과 필요한 조치만 표시하고 자동 변경을 하지 않음 |
| `USER_CHECK_POWER_USB` | USER | 카메라 전원과 USB 연결 확인 |
| `USER_POWER_CYCLE_CAMERA` | USER | 카메라 전원 재시작 |
| `USER_CHECK_STORAGE` | USER | SD카드 상태 확인 |
| `USER_UPDATE_COMPONENTS` | USER | 앱과 Opal 버전 정합화 |

자동 대응은 반드시 가장 작은 계층부터 수행한다. PTP 세션 오류에 전체 Opal을 재부팅하거나,
WS 오류에 카메라 세션을 끊는 대응은 금지한다.

- `POLICY.MINIMUM_SCOPE_RECOVERY`: 실패한 가장 작은 구성 요소만 복구한다.
- `POLICY.NON_DESTRUCTIVE_DIAG`: 일반 진단은 촬영·파일 생성·설정 변경을 하지 않는다.
- `POLICY.STATE_FROM_FIELDS_ONLY`: UI는 정규 상태 필드만 사용하며 표시 문구를 해석하지 않는다.

## 8. DIAG 실행 단계

1. `OBSERVE`: 상태 변경 없이 USB, 프로세스, health, PTP 읽기, 프레임 시각을 수집한다.
2. `CLASSIFY`: 모든 축을 판정하고 `FAULT`, `LIMITED`, `UNKNOWN`을 각각 보존한다.
3. `ROOT_CAUSE`: 의존 그래프에서 가장 앞선 검증된 원인을 주원인으로 지정한다.
4. `PLAN`: 각 원인에 대응 코드를 배정하되 중복 복구를 합친다.
5. `RESPOND`: 허용된 최소 자동 대응만 수행한다.
6. `VERIFY`: 대응 전과 동일한 프로브로 실제 회복 여부를 재검증한다.
7. `REPORT`: 전후 증거, 수행한 대응, 남은 제한과 사용자 조치를 반환한다.

일반 DIAG는 셔터를 누르거나 파일을 생성하지 않는다. LV 시작 같은 상태 변경 검사는
`POWER.LOW_BATTERY`가 아니고 사용자가 LV 진단을 요청했을 때만 수행한다.

## 9. 결과 예시

```json
{
  "ok": true,
  "diagnosticState": "LIMITED",
  "primaryFinding": "POWER.LOW_BATTERY",
  "findings": [
    {
      "id": "POWER.LOW_BATTERY",
      "domain": "POWER",
      "component": "camera_battery",
      "state": "LIMITED",
      "evidenceState": "VERIFIED",
      "reason": "low_battery",
      "observedValue": 20,
      "expectedValue": ">20",
      "source": "ptp",
      "impact": ["live_view"],
      "response": "USER_REPLACE_BATTERY",
      "owner": "USER",
      "retryable": false,
      "confidence": "high"
    },
    {
      "id": "LV.BLOCKED_LOW_BATTERY",
      "domain": "LIVE_VIEW",
      "component": "live_view_start",
      "state": "LIMITED",
      "evidenceState": "INFERRED",
      "reason": "blocked_by_power_policy",
      "blockedBy": "POWER.LOW_BATTERY",
      "impact": ["live_view"],
      "response": "NO_ACTION",
      "owner": "NONE",
      "retryable": false,
      "confidence": "high"
    }
  ]
}
```

## 10. 기존 코드와의 정규 매핑

| 현재 코드 | 정규 진단 ID |
|---|---|
| `camera_missing` | 상황에 따라 `CAMERA.USB_NOT_DETECTED`, `CAMERA.DEVICE_SELECTION_FAILED`, `CAMERA.PTP_OPEN_REJECTED` |
| `transport_error` | 세부 증거에 따라 `PTP.*`; 그대로 최종 원인으로 사용 금지 |
| `camera_busy` | `COMMAND.BUSY` 또는 반복 시 `COMMAND.BUSY_EXHAUSTED` |
| `camera_error` | `CAMERA.RESPONSE_ERROR` 또는 `COMMAND.CAMERA_REJECTED` |
| `focus_failed` | `COMMAND.FOCUS_NOT_ACQUIRED` |
| `invalid_control_mode`, `invalid_auto_iso`, `invalid_manual_setting` | `COMMAND.INVALID_INPUT` |
| `invalid_session` | `SESSION.CLIENT_ID_MISSING` 또는 `SESSION.CLIENT_ID_STALE` |
| `capability_verification_failed` | 실패 단계에 따라 `SESSION.REQUIRED_PROPERTY_MISSING`, `SESSION.STORAGE_CERTIFICATION_FAILED`, `SESSION.LV_CERTIFICATION_FAILED` |
| `liveview_limited` | `POWER.LOW_BATTERY` + `LV.BLOCKED_LOW_BATTERY` |
| `liveview_start_failed` | `LV.START_FAILED` |
| `liveview_restore_failed` | `LV.RESTORE_FAILED` |
| `liveview_inactive`, `not_live_view` | intent에 따라 `LV.PRECONDITION_INACTIVE` 또는 `LV.CAMERA_STATE_MISMATCH` |
| `frame_unavailable`, `capture_failed`(LV) | `LV.FRAME_EMPTY`, `LV.FRAME_NOT_JPEG`, `LV.FRAME_STALE` 중 실제 증거 |
| `capture_missing` | `CAPTURE.NO_NEW_OBJECT`, `CAPTURE.JPEG_NOT_FOUND`, `CAPTURE.NEF_NOT_FOUND` |
| `capture_preview_unavailable` | `CAPTURE.THUMB_UNAVAILABLE` |
| `capture_failed`(파일) | `CAPTURE.CHUNK_EMPTY`, `CAPTURE.SIZE_MISMATCH`, `CAPTURE.JPEG_INVALID` |
| `captured_object_busy`, `captured_nef_busy` | `CAPTURE.OBJECT_BUSY` |
| `captured_images_unavailable` | `STORAGE.OBJECT_LIST_FAILED`; 원 응답이 없으면 `evidenceState=UNKNOWN` |
| `captured_object_unavailable` | 원 브리지 오류를 보존하여 `CAPTURE.*`로 분류; CGI 문자열만으로 원인 확정 금지 |
| `captured_nef_unavailable` | `CAPTURE.NEF_NOT_FOUND` 또는 전송 실패; 원 브리지 증거로 구분 |
| `captured_thumbnail_unavailable`, `captured_preview_unavailable` | `CAPTURE.THUMB_UNAVAILABLE` 또는 원본 전송 실패를 증거로 구분 |
| `bridge_unavailable` | `RUNTIME.BRIDGE_STOPPED` 또는 `DELIVERY.HTTP_UNREACHABLE`를 관측 위치로 구분 |
| `app_not_ready` | 원인이 아니라 `blockedBy`를 가진 `COMMAND.APP_NOT_READY` |
| `boot_busy` | `RUNTIME.BOOT_BUSY` |
| `boot_failed` | `RUNTIME`, `PTP`, `SESSION`의 실제 실패 단계로 분해 |
| `worker_failed` | 실패한 작업자별 `RUNTIME.*` 또는 `DELIVERY.WS_UNAVAILABLE` |
| `hard_recovery_failed` | `SESSION.RECOVERY_EXHAUSTED` |
| `treatment_busy` | `RUNTIME.START_LOCK_BUSY`; 다른 session-manager 실행이 끝날 때까지 대기 |
| `treatment_failed` | 치료 후 재검증 결과에 따라 원 병명 유지 또는 `SESSION.RECOVERY_EXHAUSTED` |
| `treatment_complete` | 치료 실행 사건이며 병명이 아님; DIAG 재검증 결과를 사용 |
| `project_transport_unavailable` | `RUNTIME.DDSERVER_STOPPED` 또는 `RUNTIME.DEPENDENCY_UNAVAILABLE` |
| `battery_worker_unavailable` | `RUNTIME.BATTERY_WORKER_STOPPED` |
| `session_health_unavailable` | `RUNTIME.SESSION_HEALTH_STOPPED` |
| `websocket_unavailable` | `RUNTIME.WEBSOCKET_STOPPED` + `DELIVERY.WS_UNAVAILABLE` |
| `live_session_repair_requested` | 고장 원인이 아니라 복구 요청 사건; 기존 LV 진단 결과를 참조 |
| `frame_delivery_not_ready` | `DELIVERY.FRAME_NOT_PUBLISHED` 또는 `APP` 계층 문제로 분해 |
| `unknown` | 알 수 없는 액션이면 `COMMAND.INVALID_INPUT`; 알 수 없는 장비 응답이면 `evidenceState=UNKNOWN`으로 보존 |

`transport_error`, `camera_missing`, `capture_failed`, `boot_failed`, `worker_failed`처럼 범위가 넓은
문자열은 호환용 응답으로만 유지하고 DIAG의 최종 원인 코드로 사용하지 않는다.

## 11. DIAG 실행 계약: 진단 → 병명 확인 → 치료

DIAG의 실행 순서는 다음과 같이 고정한다.

```text
OBSERVE → CLASSIFY → CONFIRM → AUTHORIZE → TREAT → VERIFY
```

- `CLASSIFY`: 현재 관측값을 거친 장애 후보(`domain/stage/reason`)로 묶는다.
- `CONFIRM`: 후보를 87개 정규 진단 ID로 매핑하고 `diagnosisConfirmed`, `state`, `confidence`를 확정한다.
- `AUTHORIZE`: `owner`와 `treatmentAllowed`를 확인한다. `USER`, `UNKNOWN`, `LIMITED`는 자동 치료하지 않는다.
- `TREAT`: 치료 허가가 있는 경우에만 세션 매니저/복구 루틴을 실행하며 `treatmentCode`를 남긴다.
- `VERIFY`: 동일한 상태 프로브로 결과를 재검증한다. 실패하면 새 관측값으로 다시 병명을 확인한다.

현재 `diagnose-recover`는 기존의 거친 분류 결과를 정규 ID로 확인하는 어댑터와 치료 게이트를 제공한다.
아직 개별 프로브가 없는 87개 ID는 임의로 확정하지 않고 `UNKNOWN`으로 보존하며, 해당 병명에 대한 증거 프로브를
추가한 뒤에만 자동 치료 대상으로 승격한다.

### 11.1 병원 역할 계약

- `DIAG(diagnose-recover)`: 증거 수집, 인과관계 분석, 병명 확정, 치료 코드 선택, 치료 후 재검증만 담당한다.
- `session-manager`: DIAG가 허가한 치료 코드를 실행하는 유일한 런타임 변경 주체다.
- `runtime-guardian`: 이상 징후를 관측하면 DIAG를 호출하며 병명을 기록하거나 복구를 직접 수행하지 않는다.
- `action-v21`: 사용자 요청을 전달할 뿐 진단 및 치료 정책을 소유하지 않는다.
- 작업자와 `status-v21`: 관측 증거를 제공하며 다른 구성 요소를 재시작하지 않는다.

DIAG는 `bridge_stop`, 작업자 재시작, PTP `RECOVER`, USB rebind를 직접 수행할 수 없다.
모든 자동 치료 요청은 `treatmentCode + diagnosisId`로 session-manager에 전달되고 실행 로그에 함께 기록된다.

## 12. 완료 기준

DIAG 다각화 구현은 다음 조건을 모두 만족해야 완료다.

- 모든 진단축 결과를 배열로 반환한다.
- 주원인 하나를 선택하더라도 나머지 발견 사항을 삭제하지 않는다.
- `LIMITED`를 `FAULT`로 승격하지 않는다.
- `owner=USER`인 항목은 알림을 최우선으로 하며 자동복구·반복 명령·설정 변경을 수행하지 않는다.
- 상위 실패로 검사하지 못한 하위 계층은 `UNKNOWN + blockedBy`로 반환한다.
- 모든 자동복구는 수행 전후 증거를 남기고 동일 프로브로 검증한다.
- 초점 실패, 유효한 busy, 잘못된 사용자 입력은 시스템 고장으로 기록하지 않는다.
- UI 색상은 운영 상태에서만 결정하고 문자열 메시지로 판정하지 않는다.
- 알려지지 않은 응답은 임의 분류하지 않고 `UNKNOWN`으로 보존한다.
