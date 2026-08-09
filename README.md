# Morrow Frontend

Morrow의 React 웹 대시보드, SwiftUI iPhone 앱, Apple Watch 앱을 관리하는 프론트엔드 저장소입니다.

## 구성

```text
web/      React + Vite 웹 대시보드
ios/      SwiftUI iPhone 소스
watch/    SwiftUI watchOS 소스
apple/    Xcode 프로젝트와 iOS·watchOS 타깃 설정
```

백엔드 API는 [AISH-Official/morrow-backend](https://github.com/AISH-Official/morrow-backend), 통합 문서와 전체 아키텍처는 [AISH-Official/morrow-docs](https://github.com/AISH-Official/morrow-docs)에서 관리합니다.

## 웹 실행

```bash
cd web
npm ci
npm run dev
```

- 웹: http://localhost:5173
- 기본 API 프록시: http://localhost:8080
- 공개 데모: https://aish-official.github.io/morrow-frontend/

배포 시 저장소 Actions 변수 `VITE_API_BASE_URL`에 공개 HTTPS API 기준 URL을 설정합니다. 비어 있으면 안전한 데모 데이터로 동작합니다.

## iPhone·Watch 실행

```bash
open apple/Morrow.xcodeproj
```

Xcode에서 Team과 Bundle Identifier를 확인한 뒤 `Morrow` 스킴을 iPhone 또는 Watch가 연결된 iPhone 대상으로 실행합니다. 실제 기기에서 로컬 API를 사용할 때 앱 설정의 서버 주소를 `http://{Mac LAN IP}:8080/api/v1`로 지정합니다.

## 검증

```bash
cd web && npm ci && npm run build
xcodebuild -project apple/Morrow.xcodeproj -scheme Morrow \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

`main` 푸시와 Pull Request에서 웹·Apple 클라이언트 CI가 실행되고, 웹 변경은 GitHub Pages로 자동 배포됩니다.
