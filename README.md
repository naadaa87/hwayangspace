# 화양 스페이스 (Hwayang Space) 공간 안내·예약 홈페이지

서울 광진구 화양동 10-1 건물의 공간 안내와 온라인 예약, 예약 확인·취소, 문의 접수, 관리자 화면까지 실제로 동작하는 홈페이지입니다.
서버는 Cloudflare Pages Functions, 데이터는 Cloudflare D1(데이터베이스)을 씁니다. 둘 다 Cloudflare 무료 요금제 안에서 운영할 수 있고, 별도 서버나 빌드 도구가 필요 없습니다.

## 파일 구성

| 파일 | 역할 |
|---|---|
| `index.html` | 홈페이지 (공간 안내, 빠른 예약, 예약, 예약 확인·취소, 이용 안내·FAQ, 문의) |
| `admin.html` | 관리자 화면 (예약 확정·취소, 시간 차단, 문의 처리, 공간 설정) — 주소는 `/admin.html` |
| `functions/api/[[path]].js` | 예약·문의·관리자 API (Cloudflare Pages Functions) |
| `schema.sql` | 데이터베이스 표와 9개 공간 기본 데이터 (처음 설치할 때) |
| `migrate.sql` | 예전 버전 데이터베이스를 새 버전으로 바꿀 때 한 번만 실행 |

## 설치 순서 (처음 한 번만)

### 1. GitHub에 올리기

1. GitHub에서 새 저장소를 만듭니다. (예: `hanareum-site`)
2. **Add file → Upload files**로 `index.html`, `admin.html`, `schema.sql`, `README.md`를 올리고 커밋합니다.
3. `functions/api/[[path]].js`는 폴더 구조가 중요합니다. 컴퓨터에서 폴더째 끌어다 놓거나, **Add file → Create new file**에서 파일 이름 칸에 `functions/api/[[path]].js`라고 입력한 뒤 파일 내용을 붙여 넣고 커밋하면 폴더가 함께 만들어집니다.

### 2. Cloudflare Pages 연결

1. Cloudflare 대시보드 → **Workers & Pages** → **Create** → **Pages** → **Connect to Git** → 위 저장소 선택
2. 빌드 설정: Framework preset **None**, Build command **비움**, Build output directory **/**
3. **Save and Deploy** → `xxxx.pages.dev` 주소가 생깁니다. (이 단계에서는 예약 기능이 아직 동작하지 않습니다. 아래 3~5번을 마쳐야 합니다.)

### 3. 데이터베이스(D1) 만들기

1. Cloudflare 대시보드 → **Storage & Databases** → **D1 SQL Database** → **Create Database** → 이름 `hanareum` (아무 이름이나 됩니다)
2. 만든 데이터베이스의 **Console** 탭에서 `schema.sql` 파일 내용을 전부 붙여 넣고 **Execute** 를 누릅니다. 표 3개와 공간 9개가 만들어집니다.

### 4. Pages 프로젝트에 연결 (바인딩·비밀번호)

Pages 프로젝트 → **Settings** 에서

1. **Bindings** → **Add** → **D1 database** → Variable name에 `DB`, 데이터베이스는 방금 만든 것 선택 → Save
2. **Variables and Secrets** → **Add** → Type **Secret**, Variable name `ADMIN_PASSWORD`, Value에 관리자 비밀번호 입력 → Save

### 5. 다시 배포

Pages 프로젝트 → **Deployments** → 가장 최근 배포 옆 **⋯** → **Retry deployment**.
바인딩과 비밀번호는 새로 배포할 때부터 적용됩니다. 이후에는 GitHub에 커밋할 때마다 자동 배포됩니다.

### 6. 확인

- 홈페이지 주소를 열어 **예약하기**에서 공간·날짜를 고르면 시간 칸이 나타나야 합니다.
- `주소/admin.html`에서 `ADMIN_PASSWORD`로 로그인이 되면 설치 완료입니다.

## 선택 설정: 새 예약·문의 알림 메일

[Resend](https://resend.com) 무료 계정을 만들고 API 키를 발급한 뒤, Pages 프로젝트의 Variables and Secrets에 아래를 추가하고 다시 배포하면 새 예약·취소·문의가 들어올 때마다 메일이 옵니다.

| 이름 | 값 |
|---|---|
| `RESEND_API_KEY` | Resend에서 발급한 키 (Secret) |
| `NOTIFY_EMAIL` | 알림을 받을 메일 주소 |
| `NOTIFY_FROM` | (선택) 보내는 주소. Resend에 도메인을 등록했을 때만. 비우면 `onboarding@resend.dev`로 발송 |

설정하지 않아도 예약과 문의는 정상적으로 저장되며, 관리자 화면에서 모두 볼 수 있습니다.

## 운영 방법

**예약 흐름**
1. 손님이 홈페이지에서 공간·날짜·시간을 고르고 예약 요청을 보냅니다. 이미 잡힌 시간은 고를 수 없습니다.
2. 관리자 화면 **예약** 탭에 "확인 대기"로 들어옵니다. 상태를 **확정**으로 바꾸고 저장합니다. **문자** 버튼을 누르면 손님 번호로 문자 앱이 열리므로, 도어락 비밀번호와 이용 안내를 직접 보냅니다.
3. 손님은 홈페이지 **예약 조회**에서 휴대폰 번호로 상태를 확인하고, 이용일 전이면 직접 취소할 수 있습니다.

**시간 차단**: 점검·휴무, 전화로 받은 예약 등으로 손님이 고르지 못하게 막을 시간은 **시간 차단** 탭에서 넣습니다. 룸이 있는 공간에서 룸을 비우면 모든 룸이 막힙니다.

**문의**: **문의** 탭에서 내용을 보고 전화·문자·메일로 답한 뒤 상태를 "답변함"으로 바꿉니다.

**공간 설정**: 공간 이름, 상태(운영 중 / 오픈 예정), 예약 시작일, 예약 가능 여부, 룸 목록, 최소·최대 이용 시간, 분류(홈페이지 탭), 인원 안내, 요금 안내, 소개 문장, 사진 주소를 여기서 고칩니다. 저장 즉시 홈페이지의 공간 카드, 층별 안내, 예약 화면에 반영됩니다.
예를 들어 12월에 이벤트홀이 문을 열면 상태를 "운영 중"으로 바꾸고 예약 시작일을 비우면 됩니다.

**직접 고치는 문구**: 상단 공지 띠, 첫 화면 문구, "이렇게 열려요" 일정, 자주 묻는 질문은 `index.html`에 직접 적혀 있습니다. 바뀌면 GitHub에서 그 부분을 고쳐 주세요.

## 사진 넣기

사진이 없는 동안은 공간마다 정해진 색과 아이콘이 카드 커버로 나옵니다. 저장소에 `images` 폴더를 만들어 사진을 올린 뒤, 관리자 화면 공간 설정의 "사진 주소"에 `images/파일명.jpg`를 적으면 그 자리에 사진이 들어갑니다. 외부 주소(https://…)도 됩니다. 가로 16 : 세로 10 비율이 가장 잘 맞습니다.

## 비밀번호 바꾸기·데이터 확인

- 관리자 비밀번호: Pages 프로젝트 Settings → Variables and Secrets에서 `ADMIN_PASSWORD` 값을 바꾸고 다시 배포합니다.
- 데이터 직접 보기: D1 데이터베이스의 **Console** 또는 **Tables** 탭에서 `reservations`, `inquiries`, `spaces` 표를 볼 수 있습니다. 예: `SELECT * FROM reservations ORDER BY id DESC;`

## 디자인

`index.html`의 `<style>` 맨 위 `:root`에 색상값이 있습니다. 포인트 컬러 `--point` #FF6A3D 하나만 바꾸면 버튼, 배지, 강조가 함께 바뀝니다. 공간별 커버 색과 아이콘은 `<script>` 안 `LOOK`에서 고칩니다. 서체는 Pretendard를 CDN에서 불러오며, 불러오지 못하면 기기 기본 고딕으로 표시됩니다.
