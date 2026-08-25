# Underlab Camera Product Source

이 폴더는 현재 작업 트리에서 제품화에 필요한 파일만 모은 기준 묶음이다.
원본 저장소의 경로 구조를 유지하되, 테스트·배포 도구·빌드 산출물·캐시·임시
파일·키는 포함하지 않는다.

## 구성

- `app/flutter_camera`: S10 Flutter 앱 소스와 Android 제품 구성
- `app/remote-ui`: 오팔의 PTP·커맨드·LV·배터리·DIAG·Session Manager 런타임
- `deploy/openwrt`: 오팔 설치 매니페스트와 ddserver 제품 구성
- `docs`: 제품 핵심 설계와 현재 테스트베드 릴리즈 기록
- `tests`: 공개 가능한 진단·병원 역할·준비 상태·오버레이 계약 테스트
- `LICENSE`, `.gitignore`: GitHub 공개 저장소 기본 파일

## 제외 범위

전체 `deploy/scripts`, 테스트 하네스 중 계약 테스트가 아닌 도구, `build`, `.dart_tool`, `node_modules`,
`.wrangler`, APK 산출물, 임시 이미지·로그, SSH 키와 기타 자격증명은 제외했다.

Android Gradle Wrapper는 GitHub에서 재현 가능한 앱 빌드에 필요하므로 제품
구성에 포함했다. 개인 PC 경로가 담긴 `local.properties`는 제외했다.

원본 작업 트리는 그대로 보존하며, 이 폴더를 GitHub 선별 기준선으로 사용한다.
