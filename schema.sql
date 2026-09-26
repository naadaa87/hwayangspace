-- =========================================================
-- 한아름 (화양동 10-1) 예약·문의 데이터베이스 스키마
-- Cloudflare D1 콘솔에 이 파일 내용을 그대로 붙여 넣고 실행하면 됩니다.
-- 여러 번 실행해도 안전합니다. (이미 있는 표와 공간 데이터는 건너뜁니다)
-- =========================================================

CREATE TABLE IF NOT EXISTS spaces (
  id          TEXT PRIMARY KEY,
  sort        INTEGER NOT NULL,
  floor       INTEGER NOT NULL,
  name        TEXT NOT NULL,
  short       TEXT NOT NULL,
  area        REAL NOT NULL,
  status      TEXT NOT NULL DEFAULT 'later',   -- live(운영 중) / soon(2026년 12월 오픈) / later(2027년 오픈)
  open_label  TEXT NOT NULL,                   -- 카드에 표시되는 문구
  open_date   TEXT,                            -- 예약 가능 시작일 YYYY-MM-DD (비우면 오늘부터)
  bookable    INTEGER NOT NULL DEFAULT 1,      -- 0이면 예약 없이 이용(카페·가챠샵)
  rooms       TEXT,                            -- 룸 목록 JSON 배열. 없으면 NULL
  min_hours   INTEGER NOT NULL DEFAULT 1,
  max_hours   INTEGER NOT NULL DEFAULT 12,
  price_note  TEXT,                            -- 예: "시간당 2만원부터" (비우면 표시 안 함)
  description TEXT NOT NULL,
  spec        TEXT NOT NULL,                   -- JSON [["항목","내용"],...]
  who         TEXT NOT NULL,                   -- JSON ["...","..."]
  photo       TEXT                             -- 사진 URL 또는 경로
);

CREATE TABLE IF NOT EXISTS reservations (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  code        TEXT UNIQUE NOT NULL,            -- 예약번호 HR-YYMMDD-XXXX
  kind        TEXT NOT NULL DEFAULT 'booking', -- booking(예약) / block(운영자 차단)
  space_id    TEXT NOT NULL,
  room        TEXT,
  date        TEXT NOT NULL,                   -- YYYY-MM-DD
  start_hour  INTEGER NOT NULL,                -- 0~23
  end_hour    INTEGER NOT NULL,                -- 1~24 (종료 시각, 미포함)
  name        TEXT,
  phone       TEXT,
  headcount   INTEGER,
  purpose     TEXT,
  status      TEXT NOT NULL DEFAULT 'pending', -- pending(대기) / confirmed(확정) / cancelled(취소)
  memo        TEXT,
  created_at  TEXT NOT NULL DEFAULT (datetime('now','+9 hours')),  -- 한국 시간
  updated_at  TEXT
);
CREATE INDEX IF NOT EXISTS idx_res_space_date ON reservations(space_id, date, status);
CREATE INDEX IF NOT EXISTS idx_res_phone ON reservations(phone);

CREATE TABLE IF NOT EXISTS inquiries (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  name        TEXT NOT NULL,
  phone       TEXT NOT NULL,
  email       TEXT,
  space_id    TEXT,
  type        TEXT NOT NULL,                   -- 예약 / 대관 / 제휴 / 기타
  message     TEXT NOT NULL,
  status      TEXT NOT NULL DEFAULT 'new',     -- new(새 문의) / replied(답변함) / closed(종료)
  memo        TEXT,
  created_at  TEXT NOT NULL DEFAULT (datetime('now','+9 hours')),  -- 한국 시간
  updated_at  TEXT
);

-- ---------------------------------------------------------
-- 9개 공간 기본 데이터 (관리자 화면에서 언제든 수정할 수 있습니다)
-- ---------------------------------------------------------
INSERT OR IGNORE INTO spaces (id, sort, floor, name, short, area, status, open_label, open_date, bookable, rooms, min_hours, max_hours, price_note, description, spec, who, photo) VALUES
('mingle', 1, 1, '밍글카페', '밍글 카페', 42, 'live', '운영 중', NULL, 0, NULL, 1, 12, NULL,
 '24시간 문을 여는 무인 디저트 카페입니다. 키오스크로 주문해 바로 가져가면 되니 늦은 밤에도 부담 없이 들를 수 있고, 전면 유리라 밖에서도 안이 훤히 보입니다.',
 '[["운영 시간","24시간, 연중무휴"],["주문","키오스크 셀프 주문"],["예약","필요 없음"]]',
 '["야식·디저트","잠깐 쉬어갈 곳","모임 전 대기"]', NULL),
('gameroom', 2, 1, '게임파티룸', '게임 파티룸', 15, 'live', '운영 중', NULL, 1, NULL, 2, 8, NULL,
 '소규모 모임에 맞춘 무인 파티룸입니다. 시간 단위로 예약하고 도어락 비밀번호로 들어가며, 게임과 대화 위주의 짧은 모임에 잘 맞습니다.',
 '[["예약","2시간부터, 시간 단위"],["출입","도어락 비밀번호"],["규모","소규모 모임"]]',
 '["생일·기념일","친구 모임","게임 모임"]', NULL),
('eventhall', 3, 1, '팬덤 이벤트홀', '이벤트홀', 70, 'soon', '2026년 12월 오픈', '2026-12-01', 1, NULL, 4, 12, NULL,
 '팬미팅, 상영회, 플리마켓, 팝업처럼 사람을 모으는 행사를 위한 1층 대관 공간입니다. 길에서 바로 들어오는 자리라 행사 홍보물이 그대로 노출됩니다.',
 '[["대관","4시간부터"],["용도","팬미팅·상영회·플리마켓·팝업"],["위치","1층 전면, 정문 바로 옆"]]',
 '["팬클럽·주최자","플리마켓 셀러","브랜드 팝업"]', NULL),
('gacha', 4, 1, '가챠 뽑기샵', '가챠샵', 59, 'soon', '2026년 12월 오픈', '2026-12-01', 0, NULL, 1, 12, NULL,
 '캡슐토이 자판기를 한자리에 모은 무인 매장입니다. 지나가다 들러 몇 개 뽑아 가는 재미로, 밤늦게까지 열려 있습니다.',
 '[["운영 시간","24시간"],["구성","캡슐토이 자판기 중심"],["예약","필요 없음"]]',
 '["캐릭터·굿즈","산책 중 들르기","선물 고르기"]', NULL),
('party178', 5, 2, '파티룸 178평', '파티룸', 178, 'soon', '2026년 12월 오픈', '2026-12-01', 1, NULL, 3, 12, NULL,
 '동아리와 학과 행사처럼 인원이 많은 모임을 위한 대형 파티룸입니다. 넓은 홀과 바 카운터를 그대로 살렸고, 130여 지점을 운영해 온 쏘플파티룸의 방식으로 관리합니다.',
 '[["예약","3시간부터, 시간 단위"],["규모","단체·동아리"],["설비","홀, 바 카운터"]]',
 '["동아리·학과 행사","단체 회식","송년회·MT 전야"]', NULL),
('party129', 6, 2, '파티룸 129평', '파티룸', 129, 'later', '2027년 4월 오픈', '2027-04-01', 1, '["소형 룸","대형 룸"]', 2, 12, NULL,
 '소형 룸과 대형 룸을 나눠 구성해 생일 모임부터 단체 모임까지 규모에 맞게 고를 수 있습니다. 같은 층 파티룸과 함께 운영해 예약이 몰려도 자리를 찾기 쉽습니다.',
 '[["예약","2시간부터, 시간 단위"],["구성","소형 룸 + 대형 룸"],["출입","도어락 비밀번호"]]',
 '["생일·기념일","소규모 파티","중규모 모임"]', NULL),
('ott', 7, 2, 'OTT 라운지', 'OTT 라운지', 89, 'later', '2027년 6월 오픈', '2027-06-01', 1, NULL, 2, 8, NULL,
 '보드게임과 OTT를 함께 즐기는 체류형 공간입니다. 혼자 또는 둘이서 조용히 시간을 보내려는 분을 위해 파티룸과는 다른 좌석과 룸으로 구성합니다.',
 '[["예약","2시간부터, 시간 단위"],["구성","보드게임 + OTT 좌석·룸"],["인원","1~2인부터"]]',
 '["혼자 쉬고 싶은 날","커플·둘이서","보드게임"]', NULL),
('practice', 8, 3, '연습실', '연습실', 68, 'later', '2027년 4월 오픈', '2027-04-01', 1, NULL, 1, 8, NULL,
 '연기, 보컬, 댄스 연습을 위한 룸형 연습실입니다. 3층이라 소음 걱정이 적어 늦은 시간까지 쓸 수 있고, 건대·성수·왕십리에서 오기 좋은 위치입니다.',
 '[["예약","1시간부터, 시간 단위"],["구성","룸형 연습실"],["용도","연기·보컬·댄스·리허설"]]',
 '["공연예술 지망생","오디션 준비","취미 클래스"]', NULL),
('seminar', 9, 4, '세미나 모임공간', '세미나 모임공간', 185, 'soon', '2026년 12월 오픈', '2026-12-01', 1, '["룸 A","룸 B","룸 C","룸 D"]', 2, 12, NULL,
 '최상층 185평을 네 개의 룸으로 나눠 대관하는 세미나·워크숍 공간입니다. 채광과 개방감이 좋고, 이 정도 넓이는 인근에서 찾기 어렵습니다.',
 '[["대관","룸 단위, 2시간부터"],["용도","세미나·워크숍·강연"],["위치","최상층, 채광 좋음"]]',
 '["기업 워크숍","강연·클래스","스터디·정기 모임"]', NULL);
