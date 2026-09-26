-- =========================================================
-- 화양 스페이스 업데이트용 (이미 D1에 예전 schema.sql을 실행한 경우에만)
-- D1 콘솔에 이 파일 내용을 붙여 넣고 한 번만 실행하세요.
-- 예약·문의 데이터는 그대로 두고, 새 칸(분류·인원)을 추가하고 공간 이름·소개를 새 문구로 바꿉니다.
-- 처음 설치하는 경우에는 이 파일이 아니라 schema.sql을 실행하세요.
-- =========================================================

ALTER TABLE spaces ADD COLUMN category TEXT NOT NULL DEFAULT 'party';
ALTER TABLE spaces ADD COLUMN capacity TEXT;

UPDATE spaces SET name='밍글카페', short='밍글카페', open_label='운영 중', category='lounge',
  description='24시간 문 여는 무인 디저트 카페예요. 키오스크로 주문하고 바로 가져가면 되니까, 늦은 밤 야식이나 모임 전 대기 장소로 딱 맞아요.',
  spec='[["운영","24시간, 연중무휴"],["주문","키오스크"],["예약","필요 없음"]]',
  who='["24시간","디저트","모임 전 대기"]'
  WHERE id='mingle';
UPDATE spaces SET name='게임파티룸', short='게임파티룸', open_label='운영 중', category='party',
  description='소규모 모임용 무인 파티룸이에요. 시간 단위로 예약하고 도어락 비밀번호로 들어가요. 게임하고 얘기하면서 두세 시간 보내기 좋아요.',
  spec='[["예약","2시간부터"],["출입","도어락 비밀번호"],["규모","소규모 모임"]]',
  who='["생일","친구 모임","게임"]'
  WHERE id='gameroom';
UPDATE spaces SET name='이벤트홀', short='이벤트홀', open_label='12월 오픈', category='event',
  description='팬미팅, 상영회, 플리마켓, 팝업처럼 사람이 모이는 행사를 위한 1층 대관 공간이에요. 길에서 바로 들어오는 자리라 홍보물이 그대로 눈에 띄어요.',
  spec='[["대관","4시간부터"],["용도","팬미팅·상영회·플리마켓·팝업"],["위치","1층 전면, 정문 옆"]]',
  who='["팬미팅","플리마켓","팝업"]'
  WHERE id='eventhall';
UPDATE spaces SET name='가챠샵', short='가챠샵', open_label='12월 오픈', category='lounge',
  description='캡슐토이 자판기를 한자리에 모은 무인 매장이에요. 지나가다 들러 몇 개 뽑아 가는 재미, 밤늦게까지 열려 있어요.',
  spec='[["운영","24시간"],["구성","캡슐토이 자판기"],["예약","필요 없음"]]',
  who='["캡슐토이","굿즈","24시간"]'
  WHERE id='gacha';
UPDATE spaces SET name='대형 파티룸', short='대형 파티룸', open_label='12월 오픈', category='party',
  description='동아리, 학과 행사처럼 인원이 많은 모임을 위한 178평 파티룸이에요. 넓은 홀과 바 카운터를 그대로 살렸고, 전국 130여 곳 쏘플파티룸을 운영해 온 방식으로 관리해요.',
  spec='[["예약","3시간부터"],["규모","단체·동아리"],["설비","홀, 바 카운터"]]',
  who='["단체","동아리","회식"]'
  WHERE id='party178';
UPDATE spaces SET name='룸형 파티룸', short='룸형 파티룸', open_label='2027년 4월 오픈', category='party',
  description='소형 룸과 대형 룸으로 나눠 규모에 맞게 고를 수 있어요. 생일 모임부터 중규모 파티까지, 같은 층 대형 파티룸과 함께 운영해요.',
  spec='[["예약","2시간부터"],["구성","소형 룸 + 대형 룸"],["출입","도어락 비밀번호"]]',
  who='["생일","소규모 파티","룸 선택"]'
  WHERE id='party129';
UPDATE spaces SET name='OTT 라운지', short='OTT 라운지', open_label='2027년 6월 오픈', category='lounge',
  description='보드게임과 OTT를 함께 즐기는 체류형 라운지예요. 혼자 쉬거나 둘이서 조용히 시간 보내기 좋게, 파티룸과는 다른 좌석과 룸으로 꾸며요.',
  spec='[["예약","2시간부터"],["구성","보드게임 + OTT 좌석·룸"],["인원","1~2인부터"]]',
  who='["혼자","둘이","보드게임"]'
  WHERE id='ott';
UPDATE spaces SET name='연습실', short='연습실', open_label='2027년 4월 오픈', category='study',
  description='연기, 보컬, 댄스 연습을 위한 룸형 연습실이에요. 3층이라 소음 걱정이 적고, 늦은 시간까지 쓸 수 있어요.',
  spec='[["예약","1시간부터"],["구성","룸형 연습실"],["용도","연기·보컬·댄스"]]',
  who='["연기","보컬","댄스"]'
  WHERE id='practice';
UPDATE spaces SET name='세미나 라운지', short='세미나 라운지', open_label='12월 오픈', category='study',
  description='최상층 185평을 네 개 룸으로 나눠 대관해요. 채광이 좋고 탁 트여 있어서 세미나, 워크숍, 강연에 알맞아요.',
  spec='[["대관","룸 단위, 2시간부터"],["용도","세미나·워크숍·강연"],["위치","최상층"]]',
  who='["세미나","워크숍","강연"]'
  WHERE id='seminar';
