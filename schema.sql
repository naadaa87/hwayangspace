-- =========================================================
-- 화양 스페이스 (Hwayang Space · 화양동 10-1) 예약·문의 데이터베이스 스키마
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
  photo       TEXT,                            -- 사진 URL 또는 경로
  category    TEXT NOT NULL DEFAULT 'party',   -- party(파티·모임) / event(행사·대관) / study(연습·세미나) / lounge(카페·라운지)
  capacity    TEXT                             -- 예: "최대 8명" (비우면 표시 안 함)
);

CREATE TABLE IF NOT EXISTS reservations (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  code        TEXT UNIQUE NOT NULL,            -- 예약번호 HS-YYMMDD-XXXX
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
INSERT OR IGNORE INTO spaces (id, sort, floor, name, short, area, status, open_label, open_date, bookable, rooms, min_hours, max_hours, price_note, description, spec, who, photo, category, capacity) VALUES
('mingle', 1, 1, '밍글카페', '밍글카페', 42, 'live', '운영 중', NULL, 0, NULL, 1, 12, NULL,
 '24시간 문 여는 무인 디저트 카페예요. 키오스크로 주문하고 바로 가져가면 되니까, 늦은 밤 야식이나 모임 전 대기 장소로 딱 맞아요.',
 '[["운영","24시간, 연중무휴"],["주문","키오스크"],["예약","필요 없음"]]',
 '["24시간","디저트","모임 전 대기"]', NULL, 'lounge', NULL),
('gameroom', 2, 1, '게임파티룸', '게임파티룸', 15, 'live', '운영 중', NULL, 1, NULL, 2, 8, NULL,
 '소규모 모임용 무인 파티룸이에요. 시간 단위로 예약하고 도어락 비밀번호로 들어가요. 게임하고 얘기하면서 두세 시간 보내기 좋아요.',
 '[["예약","2시간부터"],["출입","도어락 비밀번호"],["규모","소규모 모임"]]',
 '["생일","친구 모임","게임"]', NULL, 'party', NULL),
('eventhall', 3, 1, '이벤트홀', '이벤트홀', 70, 'soon', '12월 오픈', '2026-12-01', 1, NULL, 4, 12, NULL,
 '팬미팅, 상영회, 플리마켓, 팝업처럼 사람이 모이는 행사를 위한 1층 대관 공간이에요. 길에서 바로 들어오는 자리라 홍보물이 그대로 눈에 띄어요.',
 '[["대관","4시간부터"],["용도","팬미팅·상영회·플리마켓·팝업"],["위치","1층 전면, 정문 옆"]]',
 '["팬미팅","플리마켓","팝업"]', NULL, 'event', NULL),
('gacha', 4, 1, '가챠샵', '가챠샵', 59, 'soon', '12월 오픈', '2026-12-01', 0, NULL, 1, 12, NULL,
 '캡슐토이 자판기를 한자리에 모은 무인 매장이에요. 지나가다 들러 몇 개 뽑아 가는 재미, 밤늦게까지 열려 있어요.',
 '[["운영","24시간"],["구성","캡슐토이 자판기"],["예약","필요 없음"]]',
 '["캡슐토이","굿즈","24시간"]', NULL, 'lounge', NULL),
('party178', 5, 2, '대형 파티룸', '대형 파티룸', 178, 'soon', '12월 오픈', '2026-12-01', 1, NULL, 3, 12, NULL,
 '동아리, 학과 행사처럼 인원이 많은 모임을 위한 178평 파티룸이에요. 넓은 홀과 바 카운터를 그대로 살렸고, 전국 130여 곳 쏘플파티룸을 운영해 온 방식으로 관리해요.',
 '[["예약","3시간부터"],["규모","단체·동아리"],["설비","홀, 바 카운터"]]',
 '["단체","동아리","회식"]', NULL, 'party', NULL),
('party129', 6, 2, '룸형 파티룸', '룸형 파티룸', 129, 'later', '2027년 4월 오픈', '2027-04-01', 1, '["소형 룸","대형 룸"]', 2, 12, NULL,
 '소형 룸과 대형 룸으로 나눠 규모에 맞게 고를 수 있어요. 생일 모임부터 중규모 파티까지, 같은 층 대형 파티룸과 함께 운영해요.',
 '[["예약","2시간부터"],["구성","소형 룸 + 대형 룸"],["출입","도어락 비밀번호"]]',
 '["생일","소규모 파티","룸 선택"]', NULL, 'party', NULL),
('ott', 7, 2, 'OTT 라운지', 'OTT 라운지', 89, 'later', '2027년 6월 오픈', '2027-06-01', 1, NULL, 2, 8, NULL,
 '보드게임과 OTT를 함께 즐기는 체류형 라운지예요. 혼자 쉬거나 둘이서 조용히 시간 보내기 좋게, 파티룸과는 다른 좌석과 룸으로 꾸며요.',
 '[["예약","2시간부터"],["구성","보드게임 + OTT 좌석·룸"],["인원","1~2인부터"]]',
 '["혼자","둘이","보드게임"]', NULL, 'lounge', NULL),
('practice', 8, 3, '연습실', '연습실', 68, 'later', '2027년 4월 오픈', '2027-04-01', 1, NULL, 1, 8, NULL,
 '연기, 보컬, 댄스 연습을 위한 룸형 연습실이에요. 3층이라 소음 걱정이 적고, 늦은 시간까지 쓸 수 있어요.',
 '[["예약","1시간부터"],["구성","룸형 연습실"],["용도","연기·보컬·댄스"]]',
 '["연기","보컬","댄스"]', NULL, 'study', NULL),
('seminar', 9, 4, '세미나 라운지', '세미나 라운지', 185, 'soon', '12월 오픈', '2026-12-01', 1, '["룸 A","룸 B","룸 C","룸 D"]', 2, 12, NULL,
 '최상층 185평을 네 개 룸으로 나눠 대관해요. 채광이 좋고 탁 트여 있어서 세미나, 워크숍, 강연에 알맞아요.',
 '[["대관","룸 단위, 2시간부터"],["용도","세미나·워크숍·강연"],["위치","최상층"]]',
 '["세미나","워크숍","강연"]', NULL, 'study', NULL);
