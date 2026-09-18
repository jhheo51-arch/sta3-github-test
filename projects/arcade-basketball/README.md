# ARCADE BASKETBALL

설치 없이 브라우저에서 즐기는 아케이드 농구 게임입니다. 현재 기능 버전은 v16입니다.

- 실행 사이트: https://arcade-basketball-20260910.sooyeon-jun-0389.chatgpt.site
- 기획서: [docs/PRD.md](docs/PRD.md)

## 주요 기능

- 선수 이름·국가·외형·등번호·주손 설정
- AI 1대1, 한 키보드 2인 대전, 입장 코드 온라인 대전
- 60초 슈팅 및 5개 위치·장거리 보너스가 있는 3점 콘테스트
- 드리블, 스틸, 크로스오버, 리바운드, 레이업, 덩크
- 3점 콘테스트에서 움직이는 초록 목표 구간과 최고 점수 경기의 소요 시간
- 사이트 참여자 이름별·모드별 전체 상위 5명 랭킹

## 내 컴퓨터에서 실행

Node.js 24 환경에서 저장소 폴더의 터미널에 다음 명령을 순서대로 실행합니다.

```sh
node scripts/build.mjs
node scripts/preview.mjs
```

브라우저에서 http://127.0.0.1:8768 을 엽니다. 로컬 미리보기의 공용 랭킹 데이터는 임시 메모리에 저장되어 서버를 끄면 사라집니다. 실제 사이트의 누적 랭킹과는 별개입니다.

`src/index.html`을 직접 열어 게임 화면을 볼 수도 있지만 전체 참여자 랭킹은 서버 실행이 필요합니다. 온라인 대전은 인터넷 및 상대방과의 연결 환경에 영향을 받습니다.

## 파일 안내

- `src/index.html`: 화면, 캐릭터, 게임 규칙 및 조작
- `worker/api.js`: 전체 참여자 랭킹 저장·조회
- `db/schema.ts`, `drizzle/`: 데이터베이스 구조와 변경 기록
- `scripts/`: 빌드, 미리보기 및 랭킹 검사
- `dist/`: Sites 실행용 생성 파일
- `.openai/hosting.json`: 기존 Sites 연결 정보

## 랭킹 자동 검사

```sh
node scripts/verify-api.mjs
node scripts/verify-time.mjs
```

검사는 임시 데이터베이스에서 수행하며 실제 사이트 기록을 변경하지 않습니다. 자동 검사와 실제 사용자의 조작감 확인은 별개입니다.

## 외부 라이브러리

온라인 연결에 PeerJS를 사용하며 HTML 안에 해당 MIT 라이선스 고지를 포함합니다.
