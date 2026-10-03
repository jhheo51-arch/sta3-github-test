# MEMOIVE 이어서 작업하기

MEMOIVE는 저장한 콘텐츠와 내 생각을 연결해 실제 글·기획안의 재료로 만드는 모바일 중심 웹 시제품입니다. 한국어로 설명하고, 기존 기록과 디자인을 보존하세요. 이 문서는 다른 AI 도구에서 저장소 작업을 재개하기 위한 안내이며 Claude에서 실제 실행 검증을 마쳤다는 뜻은 아닙니다.

## 먼저 확인할 문서

1. [README](README.md): 실행 방법과 현재 한계.
2. [최신 제출 PRD](docs/PRD_MEMOIVE_2026-10-03-v02.md): 앱 v22 기준.
3. [수요와 차별성 검토](docs/demand-differentiation-2026-10-03-v01.md): 경쟁 기능 중복과 미검증 가설.
4. [저장과 모바일 검사](docs/stability-mobile-verification-2026-10-03-v01.md): 가상 기술 시험과 실제 효과의 구분.
5. [Worker 안내](cloudflare-worker/README.md): Gemini 연결 준비 상태.

## 실행과 검사

저장소 루트에서 `memoive` 폴더로 이동한 다음 실행합니다. Python 3와 Node.js가 필요하며 기본 웹 기능은 별도 패키지나 API 키 없이 사용할 수 있습니다.

```sh
python scripts/serve.py --port 4182
```

`http://127.0.0.1:4182/`에서 확인합니다. 종료는 해당 터미널의 Ctrl+C입니다. 이 미리보기는 허용된 앱 파일만 내보내며 `.env`, 서버 소스, 폴더 목록은 제공하지 않습니다. 실제 키가 있는 폴더를 일반 파일 서버나 공개 웹 경로로 노출하지 마세요.

```sh
node tests/submission-self-check.cjs
node tests/cases-use-check.cjs
node tests/navigation-order-check.cjs
node tests/before-after-check.cjs
node tests/storage-safety-check.cjs
python tests/preview-safety-check.py
```

앱은 HTML·CSS·JavaScript이며 `app.js`가 화면, `data-tools.js`가 데이터 변환, `storage-guard.js`가 기존 기기 저장 보호, `accessibility.js`가 창의 키보드 접근을 담당합니다. `sw.js` 자산 목록과 HTML의 버전 표기를 함께 관리하세요. 개인 자료가 아닌 가상 자료로 새 주소에서 검사하세요.

## 키와 AI 연결 상태

키 이름은 `GEMINI_API_KEY`입니다. 새로 복제한 환경에서는 빈 `.env.example`을 참고해 로컬 `.env`를 만들되 기존 파일이 있으면 덮어쓰지 마세요. 사용자의 TOBEA 환경은 대표 폴더 `project/memoive/.env`를 사용합니다. 그 안의 최신 코드는 별도 중첩 작업 폴더에 있으므로 키를 코드 폴더에 복제하지 마세요.

`.env`는 로컬 준비 파일일 뿐 자동으로 읽거나 연결하는 처리가 없습니다. 운영 Worker는 비밀 설정값 `GEMINI_API_KEY`를 읽습니다. 브라우저의 `config.js`에는 키가 아니라 Worker의 `/v1/refine` 주소만 넣어야 합니다. 실제 연결 요청을 받은 뒤 서버 비밀 설정을 등록하고 인증·사용량 제한·기록 전송 동의·실제 응답을 확인하세요.

`wrangler.toml`의 모델명은 확인 전의 준비값입니다. 사용 가능한 모델과 프로젝트별 한도를 확인하기 전 특정 모델·무료 요청 횟수를 확정하지 마세요. 현재 `config.js`의 연결 주소는 비어 있으며 기본 양식 초안이 동작합니다. API 키를 채웠다는 사실을 생성 성공으로 보고하지 마세요.

실제 키·개인 기록·백업을 출력하거나 커밋·업로드하지 마세요. `.env.example`에는 빈 값만 둡니다. 다른 프로젝트의 키를 찾아 쓰지 않습니다. 백업과 실제 사용 자료도 Git 제외 대상입니다.

## 제품과 배포 원칙

- 핵심 흐름은 저장 → 내 생각 → 단어 검색 → 결과물 편집·저장·재열기입니다.
- 커피색·모바일 구성·작은 아이콘을 유지합니다. 스크롤 막대만 숨기고 내용 이동과 키보드 접근을 막지 않습니다.
- 요약·적용 가설·사용자 의견을 구분하고, 예시·가상 시험을 고객 성과로 집계하지 않습니다.
- 실제 활용 효과는 사용자가 수집할 예정입니다. 수요·경쟁 우위·AI 품질 검증 완료를 만들어내지 마세요.
- 기기 내 저장과 백업만 제공하며 서버 동기화는 없습니다. 저장 구조를 바꿀 때 기존 자료 보존·이전·복구 검사를 먼저 설계합니다.
- 공개 GitHub 코드와 비공개 운영 사이트는 별개입니다. PR 병합만으로 Site가 자동 배포되지는 않습니다.
- 이 저장소에는 소유자 전용 Sites 인증이 없습니다. 다른 도구에서 무단으로 새 사이트를 만들거나 공개 권한으로 변경하지 마세요. 배포가 필요하면 기존 Site의 인증된 작업 환경에서 진행합니다.
- 다른 프로젝트 폴더는 수정하지 않고, MEMOIVE 변경만 검토 후 커밋합니다.
