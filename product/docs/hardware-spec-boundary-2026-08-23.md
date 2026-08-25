# 하드웨어 스펙 및 처리 범위 기준

작성일: 2026-08-23  
상태: 기준 초안  
적용 대상: GL.iNet Opal(GL-SFT1200) + Samsung Galaxy S10 클라이언트

이 문서는 필름 시뮬레이션을 포함한 카메라 기능의 하드웨어 전제를 고정한다.
저장소와 실측 기록에서 확인되지 않은 값은 임의로 채우지 않고 `확인 필요`로 표시한다.

## 1. 시스템 구성

```text
Nikon D810 ─ USB/PTP ─ Opal ─ Wi-Fi/LAN ─ S10
                           라우터·카메라 브리지     클라이언트 UI·이미지 처리
```

| 장비 | 역할 | 주소/접속 | 책임 범위 |
|---|---|---|---|
| Opal | 카메라 연결 라우터 및 브리지 호스트 | 기본 LAN `192.168.8.1` | Wi-Fi, 라우팅, USB/PTP, ddserver, 브리지, WebSocket, 최소 프레임 캐시 |
| S10 | Android 클라이언트 | 현장 기준 `192.168.8.165` | UI, 라이브뷰 디코드/표시, 촬영 명령, 필름 시뮬, 결과 저장/표시 |

## 2. Opal 기준 스펙

| 항목 | 기준값 | 상태/근거 |
|---|---|---|
| 제품 | GL.iNet Opal, GL-SFT1200 | 확정. 기존 운영 문서 |
| OS | OpenWrt 18.06 계열 | 확정. 기존 운영 문서 및 SDK |
| CPU/아키텍처 | Siflower MIPS 계열, little-endian 빌드 | 확인된 빌드 대상. 정확한 SoC/클럭은 확인 필요 |
| 물리 메모리 | `118,784 KB` (약 116 MiB) | 확정. 2026-07-20 실측 기록 |
| 평상시 가용 메모리 | 약 `50 MB` | 확정. 최적화 후 기록 |
| 카메라 연결 | USB/PTP, Nikon D810 | 확정. 실장 경로 |
| 네트워크 | Wi-Fi/LAN 라우터, 기본 주소 `192.168.8.1` | 확정. 현장 기록 |
| 프레임 전달 | WebSocket 직접 스트림 + HTTP 파일 fallback | 확정. 라이브뷰 최적화 기록 |
| 라이브뷰 기준 | 60 fps급 처리율 실측 | 확정. 단, 필름 시뮬 적용 전 기준 |
| 서비스 원칙 | 카메라 계층은 요청 시 시작, 기본 부팅 경로 불변 | 확정. minimal overlay contract |

### Opal에서 허용하는 작업

- 카메라 USB/PTP 통신과 촬영 명령 처리
- 라이브뷰 프레임 수집, 작은 메타데이터 생성, 네트워크 전달
- 연결 상태·세션 상태·재연결 상태 관리
- 필름 시뮬에 필요한 원본 프레임 전달

### Opal에서 제외하는 작업

- JPEG/RAW 전체 이미지에 대한 필름 시뮬 연산
- 고해상도 이미지 디코드·재인코드
- 필터 LUT 적용, 색공간 변환, 장시간 이미지 큐 보관
- 필름 시뮬 때문에 기본 라우터·Wi-Fi·부팅 경로를 변경하는 작업

Opal은 메모리 여유가 제한적이므로 필름 시뮬의 주 처리 장비로 사용하지 않는다.

## 3. S10 기준 스펙

| 항목 | 기준값 | 상태/근거 |
|---|---|---|
| 제품 | Samsung Galaxy S10 | 사용자 지정 기준 |
| 역할 | Android/Flutter 카메라 클라이언트 | 확정. 현재 앱 구조 |
| 연결 | Opal Wi-Fi 네트워크, 현장 주소 `192.168.8.165` | 운영 스크립트 기준 |
| 디버그 | ADB 무선 연결 사용, 포트는 가변 | 확정. 현장 테스트 스크립트 |
| OS 버전 | Android Pie 출시, 현재 설치 버전은 확인 필요 | 삼성 공식 출시 사양 및 단말 실측 필요 |
| SoC/GPU | **Samsung Exynos 9820**, 8nm LPP, Mali-G76 MP12 | Exynos 모델 기준 확정 |
| RAM/저장공간 | **8GB LPDDR4X RAM** | Exynos Galaxy S10 기준 확정. 저장공간은 기능 범위에서 제외 |
| 화면 | 6.1인치 QHD+ Dynamic AMOLED, 기본 FHD+ | 공식 출시 자료. 실제 렌더링 주사율은 확인 필요 |
| 카메라 입력 | Opal에서 전달되는 JPEG 라이브뷰 | 확정. 앱 전달 경로 |
| 이미지 처리 | 디코드, 표시, 필름 시뮬, 결과 미리보기 | 설계 기준 |

## 4. 필름 시뮬 처리 경계

1. Opal은 카메라 프레임을 가능한 한 변형 없이 S10으로 전달한다.
2. S10은 라이브뷰 미리보기와 촬영 결과에 필름 시뮬을 적용한다.
3. 1차 구현은 S10에서 실시간으로 감당 가능한 JPEG 프리뷰 해상도와 FPS를 대상으로 한다.
4. 고해상도 원본의 최종 렌더링은 실시간 경로와 분리한다.
5. 필터 적용 실패나 성능 저하가 네트워크·촬영 명령·세션 상태에 영향을 주면 안 된다.
6. 원본 이미지와 필터 결과를 구분해 보존할 수 있는 구조를 우선한다.

## 5. 아직 확정하지 않는 항목

- S10의 정확한 모델 식별자와 지역별 SoC 변형
- Android 버전, RAM, 여유 저장공간
- S10 화면 주사율과 실제 디코드/렌더링 상한
- 라이브뷰 프레임의 실제 해상도·JPEG 크기 분포
- 필름 시뮬 적용 시 목표 FPS와 허용 지연
- 촬영 결과에 적용할 최대 해상도와 저장 포맷
- 실제 단말 모델 식별자(`SM-G973*`) 확인

## 6. 확정 기준

필름 시뮬 구현은 이 문서의 역할 분리를 기준으로 한다. 새로운 하드웨어 정보나
실측값이 생기면 코드를 먼저 바꾸지 말고 이 문서의 해당 항목과 확인일을 갱신한다.

## 참고 기록

- `docs/opal-memory-optimization-2026-07-20.md`
- `docs/opal-minimal-overlay-contract-2026-08-22.md`
- `docs/0728-5차-프레임-최적화-2026-07-28.md`
- `deploy/scripts/start-field-test.ps1`
- `deploy/scripts/s10-field-ui-test.ps1`
- [Samsung Galaxy S10 Interactive Press Release](https://news.samsung.com/us/galaxy-s10-interactive/)
- [Samsung Galaxy S10 공식 사양 페이지](https://www.samsung.com/ie/smartphones/galaxy-s10/specs/)
- [Samsung Exynos 9820 공식 사양](https://semiconductor.samsung.com/processor/mobile-processor/exynos-9-series-9820/)
