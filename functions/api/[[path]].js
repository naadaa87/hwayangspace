/* =========================================================
   한아름 (화양동 10-1) 예약·문의 API
   Cloudflare Pages Functions + D1

   필요한 설정 (Cloudflare 대시보드 → Pages 프로젝트 → Settings)
   - Bindings → D1 database : 변수 이름 DB
   - Variables and Secrets  : ADMIN_PASSWORD (관리자 비밀번호, Secret)
   선택 설정 (새 예약·문의 알림 메일)
   - RESEND_API_KEY, NOTIFY_EMAIL, NOTIFY_FROM
========================================================= */

const TOKEN_HOURS = 12;

/* ---------- 공통 유틸 ---------- */
const json = (data, status = 200, headers = {}) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...headers },
  });
const fail = (message, status = 400, extra = {}) => json({ ok: false, error: message, ...extra }, status);

const normPhone = (v) => String(v || "").replace(/\D/g, "");
const isPhone = (v) => /^01[016789]\d{7,8}$/.test(v);
const isDate = (v) => /^\d{4}-\d{2}-\d{2}$/.test(v) && !isNaN(new Date(v + "T00:00:00Z").getTime());
const clip = (v, n) => String(v ?? "").trim().slice(0, n);
const int = (v, d = null) => (Number.isInteger(Number(v)) ? Number(v) : d);

/* 한국 시간 기준 오늘 날짜 (YYYY-MM-DD) */
function todayKST() {
  const t = new Date(Date.now() + 9 * 3600 * 1000);
  return t.toISOString().slice(0, 10);
}
function nowKSTHour() {
  return new Date(Date.now() + 9 * 3600 * 1000).getUTCHours();
}
function dbTime() {
  return new Date(Date.now() + 9 * 3600 * 1000).toISOString().replace("T", " ").slice(0, 19); // 한국 시간
}

function parseSpace(row) {
  if (!row) return null;
  const safe = (s, d) => { try { return s ? JSON.parse(s) : d; } catch { return d; } };
  return {
    ...row,
    bookable: !!row.bookable,
    rooms: safe(row.rooms, null),
    spec: safe(row.spec, []),
    who: safe(row.who, []),
  };
}

function makeCode() {
  const d = todayKST().slice(2).replace(/-/g, "");
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let r = "";
  const buf = new Uint8Array(4);
  crypto.getRandomValues(buf);
  for (const b of buf) r += chars[b % chars.length];
  return `HR-${d}-${r}`;
}

/* ---------- 관리자 토큰 (HMAC) ---------- */
async function hmacKey(secret) {
  const raw = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(secret + "|hanareum-admin"));
  return crypto.subtle.importKey("raw", raw, { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
}
const toHex = (buf) => [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");

async function issueToken(secret) {
  const exp = Date.now() + TOKEN_HOURS * 3600 * 1000;
  const key = await hmacKey(secret);
  const sig = toHex(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(String(exp))));
  return `${exp}.${sig}`;
}
async function verifyToken(secret, token) {
  if (!secret || !token) return false;
  const [expStr, sig] = String(token).split(".");
  const exp = Number(expStr);
  if (!exp || !sig || exp < Date.now()) return false;
  const key = await hmacKey(secret);
  const expect = toHex(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(expStr)));
  if (expect.length !== sig.length) return false;
  let diff = 0;
  for (let i = 0; i < expect.length; i++) diff |= expect.charCodeAt(i) ^ sig.charCodeAt(i);
  return diff === 0;
}
async function requireAdmin(context) {
  const auth = context.request.headers.get("authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  if (!context.env.ADMIN_PASSWORD) return fail("ADMIN_PASSWORD가 설정되지 않았습니다.", 503);
  if (!(await verifyToken(context.env.ADMIN_PASSWORD, token))) return fail("로그인이 필요합니다.", 401);
  return null;
}

/* ---------- 알림 메일 (Resend, 선택) ---------- */
async function notify(env, subject, text) {
  if (!env.RESEND_API_KEY || !env.NOTIFY_EMAIL) return;
  try {
    await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { authorization: `Bearer ${env.RESEND_API_KEY}`, "content-type": "application/json" },
      body: JSON.stringify({
        from: env.NOTIFY_FROM || "한아름 <onboarding@resend.dev>",
        to: [env.NOTIFY_EMAIL],
        subject,
        text,
      }),
    });
  } catch (_) { /* 알림 실패는 무시 */ }
}

/* ---------- 겹치는 예약 확인 ---------- */
async function findOverlap(db, space, room, date, start, end, excludeId = null) {
  let sql = `SELECT id, code, kind, room, start_hour, end_hour FROM reservations
             WHERE space_id = ?1 AND date = ?2 AND status != 'cancelled'
               AND start_hour < ?3 AND end_hour > ?4`;
  const binds = [space.id, date, end, start];
  if (space.rooms) {
    // 룸이 있는 공간: 같은 룸이거나, 룸 지정 없이 걸린 차단(전체) 이면 겹침
    sql += ` AND (room IS NULL OR room = ?5)`;
    binds.push(room);
  }
  if (excludeId) { sql += ` AND id != ?${binds.length + 1}`; binds.push(excludeId); }
  return db.prepare(sql).bind(...binds).first();
}

/* =========================================================
   요청 처리
========================================================= */
export async function onRequest(context) {
  const { request, env, params } = context;
  const path = Array.isArray(params.path) ? params.path : [];
  const method = request.method.toUpperCase();
  const url = new URL(request.url);

  if (!env.DB) return fail("데이터베이스(D1) 바인딩 DB가 설정되지 않았습니다.", 503);
  const db = env.DB;

  let body = {};
  if (method === "POST" || method === "PUT" || method === "PATCH") {
    try { body = await request.json(); } catch { body = {}; }
    if (body._hp) return fail("잘못된 요청입니다."); // 스팸 봇용 숨김 필드
  }

  try {
    /* ---------- 공개 API ---------- */

    // GET /api/spaces
    if (method === "GET" && path[0] === "spaces" && path.length === 1) {
      const { results } = await db.prepare("SELECT * FROM spaces ORDER BY sort").all();
      return json({ ok: true, spaces: results.map(parseSpace), today: todayKST() });
    }

    // GET /api/availability?space_id=&date=
    if (method === "GET" && path[0] === "availability") {
      const spaceId = clip(url.searchParams.get("space_id"), 40);
      const date = clip(url.searchParams.get("date"), 10);
      if (!spaceId || !isDate(date)) return fail("공간과 날짜를 확인해 주세요.");
      const space = parseSpace(await db.prepare("SELECT * FROM spaces WHERE id = ?1").bind(spaceId).first());
      if (!space) return fail("없는 공간입니다.", 404);
      const { results } = await db
        .prepare(`SELECT room, start_hour, end_hour, kind FROM reservations
                  WHERE space_id = ?1 AND date = ?2 AND status != 'cancelled'`)
        .bind(spaceId, date).all();
      return json({ ok: true, date, rooms: space.rooms, booked: results, today: todayKST(), nowHour: nowKSTHour() });
    }

    // POST /api/reservations
    if (method === "POST" && path[0] === "reservations" && path.length === 1) {
      const spaceId = clip(body.space_id, 40);
      const date = clip(body.date, 10);
      const start = int(body.start_hour);
      const end = int(body.end_hour);
      const name = clip(body.name, 40);
      const phone = normPhone(body.phone);
      const headcount = int(body.headcount, null);
      const purpose = clip(body.purpose, 500);
      const room = clip(body.room, 40) || null;

      const space = parseSpace(await db.prepare("SELECT * FROM spaces WHERE id = ?1").bind(spaceId).first());
      if (!space) return fail("없는 공간입니다.", 404);
      if (!space.bookable) return fail("이 공간은 예약 없이 이용하는 공간입니다.");
      if (!isDate(date)) return fail("날짜를 확인해 주세요.");
      const minDate = space.open_date && space.open_date > todayKST() ? space.open_date : todayKST();
      if (date < minDate) return fail(`${minDate} 이후 날짜만 예약할 수 있습니다.`);
      if (start === null || end === null || start < 0 || end > 24 || end <= start) return fail("이용 시간을 확인해 주세요.");
      if (date === todayKST() && start < nowKSTHour()) return fail("이미 지난 시간입니다.");
      const hours = end - start;
      if (hours < space.min_hours) return fail(`이 공간은 ${space.min_hours}시간부터 예약할 수 있습니다.`);
      if (hours > space.max_hours) return fail(`한 번에 최대 ${space.max_hours}시간까지 예약할 수 있습니다.`);
      if (space.rooms && !space.rooms.includes(room)) return fail("룸을 선택해 주세요.");
      if (name.length < 2) return fail("이름을 입력해 주세요.");
      if (!isPhone(phone)) return fail("휴대폰 번호를 확인해 주세요.");
      if (!body.agree) return fail("개인정보 수집·이용에 동의해 주세요.");

      const overlap = await findOverlap(db, space, room, date, start, end);
      if (overlap) return fail("선택한 시간에 이미 예약이 있습니다. 시간을 다시 골라 주세요.", 409);

      let code = makeCode();
      for (let i = 0; i < 5; i++) {
        try {
          await db.prepare(`INSERT INTO reservations
              (code, kind, space_id, room, date, start_hour, end_hour, name, phone, headcount, purpose, status)
              VALUES (?1,'booking',?2,?3,?4,?5,?6,?7,?8,?9,?10,'pending')`)
            .bind(code, space.id, space.rooms ? room : null, date, start, end, name, phone, headcount, purpose)
            .run();
          break;
        } catch (e) {
          if (i === 4) throw e;
          code = makeCode();
        }
      }

      context.waitUntil(notify(env, `[한아름] 새 예약 요청 ${code}`,
        `공간: ${space.name}${room ? " / " + room : ""}\n날짜: ${date} ${start}:00~${end}:00\n이름: ${name}\n연락처: ${phone}\n인원: ${headcount ?? "-"}\n용도: ${purpose || "-"}`));

      return json({ ok: true, code, space: space.name, room: space.rooms ? room : null, date, start_hour: start, end_hour: end,
        prelaunch: space.status !== "live" });
    }

    // POST /api/reservations/lookup  { code?, phone }
    if (method === "POST" && path[0] === "reservations" && path[1] === "lookup") {
      const phone = normPhone(body.phone);
      const code = clip(body.code, 20).toUpperCase();
      if (!isPhone(phone)) return fail("휴대폰 번호를 확인해 주세요.");
      let sql = `SELECT r.code, r.room, r.date, r.start_hour, r.end_hour, r.status, r.headcount, r.created_at,
                        s.name AS space_name, s.floor
                 FROM reservations r JOIN spaces s ON s.id = r.space_id
                 WHERE r.kind = 'booking' AND r.phone = ?1`;
      const binds = [phone];
      if (code) { sql += " AND r.code = ?2"; binds.push(code); }
      sql += " ORDER BY r.date DESC, r.start_hour DESC LIMIT 30";
      const { results } = await db.prepare(sql).bind(...binds).all();
      return json({ ok: true, reservations: results, today: todayKST() });
    }

    // POST /api/reservations/cancel  { code, phone }
    if (method === "POST" && path[0] === "reservations" && path[1] === "cancel") {
      const phone = normPhone(body.phone);
      const code = clip(body.code, 20).toUpperCase();
      const row = await db.prepare("SELECT * FROM reservations WHERE code = ?1 AND phone = ?2 AND kind = 'booking'").bind(code, phone).first();
      if (!row) return fail("예약을 찾을 수 없습니다.", 404);
      if (row.status === "cancelled") return fail("이미 취소된 예약입니다.");
      if (row.date < todayKST()) return fail("지난 예약은 취소할 수 없습니다.");
      await db.prepare("UPDATE reservations SET status = 'cancelled', updated_at = ?2 WHERE id = ?1").bind(row.id, dbTime()).run();
      context.waitUntil(notify(env, `[한아름] 예약 취소 ${code}`, `${row.date} ${row.start_hour}:00~${row.end_hour}:00 / ${row.name} / ${row.phone}`));
      return json({ ok: true });
    }

    // POST /api/inquiries
    if (method === "POST" && path[0] === "inquiries") {
      const name = clip(body.name, 40);
      const phone = normPhone(body.phone);
      const email = clip(body.email, 80);
      const spaceId = clip(body.space_id, 40) || null;
      const type = clip(body.type, 20) || "기타";
      const message = clip(body.message, 2000);
      if (name.length < 2) return fail("이름을 입력해 주세요.");
      if (!isPhone(phone)) return fail("휴대폰 번호를 확인해 주세요.");
      if (message.length < 5) return fail("문의 내용을 조금 더 적어 주세요.");
      if (!body.agree) return fail("개인정보 수집·이용에 동의해 주세요.");
      await db.prepare(`INSERT INTO inquiries (name, phone, email, space_id, type, message) VALUES (?1,?2,?3,?4,?5,?6)`)
        .bind(name, phone, email || null, spaceId, type, message).run();
      context.waitUntil(notify(env, `[한아름] 새 문의 (${type})`, `이름: ${name}\n연락처: ${phone}\n이메일: ${email || "-"}\n공간: ${spaceId || "-"}\n\n${message}`));
      return json({ ok: true });
    }

    /* ---------- 관리자 API ---------- */

    if (path[0] === "admin") {
      // POST /api/admin/login { password }
      if (method === "POST" && path[1] === "login") {
        if (!env.ADMIN_PASSWORD) return fail("ADMIN_PASSWORD가 설정되지 않았습니다.", 503);
        const given = String(body.password || "");
        const expect = String(env.ADMIN_PASSWORD);
        let diff = given.length === expect.length ? 0 : 1;
        for (let i = 0; i < Math.min(given.length, expect.length); i++) diff |= given.charCodeAt(i) ^ expect.charCodeAt(i);
        if (diff !== 0) return fail("비밀번호가 맞지 않습니다.", 401);
        return json({ ok: true, token: await issueToken(expect), expires_in_hours: TOKEN_HOURS });
      }

      const denied = await requireAdmin(context);
      if (denied) return denied;

      // GET /api/admin/overview
      if (method === "GET" && path[1] === "overview") {
        const today = todayKST();
        const [pending, todayCnt, newInq, upcoming] = await Promise.all([
          db.prepare("SELECT COUNT(*) c FROM reservations WHERE kind='booking' AND status='pending'").first(),
          db.prepare("SELECT COUNT(*) c FROM reservations WHERE kind='booking' AND status!='cancelled' AND date=?1").bind(today).first(),
          db.prepare("SELECT COUNT(*) c FROM inquiries WHERE status='new'").first(),
          db.prepare("SELECT COUNT(*) c FROM reservations WHERE kind='booking' AND status='confirmed' AND date>=?1").bind(today).first(),
        ]);
        return json({ ok: true, today, pending: pending.c, todayCount: todayCnt.c, newInquiries: newInq.c, upcoming: upcoming.c });
      }

      // GET /api/admin/reservations?status=&from=&to=&space_id=&q=
      if (method === "GET" && path[1] === "reservations") {
        const p = url.searchParams;
        const conds = ["1=1"]; const binds = [];
        const add = (c, v) => { binds.push(v); conds.push(c.replace("?", `?${binds.length}`)); };
        const kind = p.get("kind");
        if (kind === "block") conds.push("r.kind='block'"); else if (kind !== "all") conds.push("r.kind='booking'");
        if (p.get("status")) add("r.status = ?", clip(p.get("status"), 20));
        if (isDate(p.get("from") || "")) add("r.date >= ?", p.get("from"));
        if (isDate(p.get("to") || "")) add("r.date <= ?", p.get("to"));
        if (p.get("space_id")) add("r.space_id = ?", clip(p.get("space_id"), 40));
        if (p.get("q")) { const q = `%${clip(p.get("q"), 40)}%`; binds.push(q); conds.push(`(r.name LIKE ?${binds.length} OR r.phone LIKE ?${binds.length} OR r.code LIKE ?${binds.length})`); }
        const { results } = await db.prepare(
          `SELECT r.*, s.name AS space_name, s.floor FROM reservations r LEFT JOIN spaces s ON s.id = r.space_id
           WHERE ${conds.join(" AND ")} ORDER BY r.date DESC, r.start_hour DESC, r.id DESC LIMIT 300`).bind(...binds).all();
        return json({ ok: true, reservations: results, today: todayKST() });
      }

      // PATCH /api/admin/reservations/:id { status?, memo? }
      if (method === "PATCH" && path[1] === "reservations" && path[2]) {
        const id = int(path[2]);
        const row = await db.prepare("SELECT * FROM reservations WHERE id = ?1").bind(id).first();
        if (!row) return fail("예약을 찾을 수 없습니다.", 404);
        const status = body.status !== undefined ? clip(body.status, 20) : row.status;
        if (!["pending", "confirmed", "cancelled"].includes(status)) return fail("상태값이 올바르지 않습니다.");
        const memo = body.memo !== undefined ? clip(body.memo, 500) : row.memo;
        if (status !== "cancelled" && row.status === "cancelled") {
          const space = parseSpace(await db.prepare("SELECT * FROM spaces WHERE id = ?1").bind(row.space_id).first());
          const overlap = await findOverlap(db, space, row.room, row.date, row.start_hour, row.end_hour, row.id);
          if (overlap) return fail(`같은 시간에 다른 예약(${overlap.code})이 있어 되돌릴 수 없습니다.`, 409);
        }
        await db.prepare("UPDATE reservations SET status = ?2, memo = ?3, updated_at = ?4 WHERE id = ?1").bind(id, status, memo, dbTime()).run();
        return json({ ok: true });
      }

      // POST /api/admin/blocks { space_id, room?, date, start_hour, end_hour, memo }
      if (method === "POST" && path[1] === "blocks") {
        const spaceId = clip(body.space_id, 40);
        const space = parseSpace(await db.prepare("SELECT * FROM spaces WHERE id = ?1").bind(spaceId).first());
        if (!space) return fail("없는 공간입니다.", 404);
        const date = clip(body.date, 10);
        const start = int(body.start_hour); const end = int(body.end_hour);
        if (!isDate(date)) return fail("날짜를 확인해 주세요.");
        if (start === null || end === null || start < 0 || end > 24 || end <= start) return fail("시간을 확인해 주세요.");
        const room = clip(body.room, 40) || null;
        if (room && space.rooms && !space.rooms.includes(room)) return fail("룸 이름이 맞지 않습니다.");
        const overlap = await findOverlap(db, space, room, date, start, end);
        if (overlap && overlap.kind === "booking") return fail(`이 시간에 예약(${overlap.code})이 있습니다. 먼저 처리해 주세요.`, 409);
        const code = makeCode().replace("HR-", "BL-");
        await db.prepare(`INSERT INTO reservations (code, kind, space_id, room, date, start_hour, end_hour, status, memo)
                          VALUES (?1,'block',?2,?3,?4,?5,?6,'confirmed',?7)`)
          .bind(code, spaceId, room, date, start, end, clip(body.memo, 200) || "운영자 차단").run();
        return json({ ok: true, code });
      }

      // DELETE /api/admin/blocks/:id
      if (method === "DELETE" && path[1] === "blocks" && path[2]) {
        await db.prepare("DELETE FROM reservations WHERE id = ?1 AND kind = 'block'").bind(int(path[2])).run();
        return json({ ok: true });
      }

      // GET /api/admin/inquiries?status=
      if (method === "GET" && path[1] === "inquiries") {
        const status = clip(url.searchParams.get("status"), 20);
        const sql = `SELECT i.*, s.name AS space_name FROM inquiries i LEFT JOIN spaces s ON s.id = i.space_id
                     ${status ? "WHERE i.status = ?1" : ""} ORDER BY i.id DESC LIMIT 300`;
        const stmt = status ? db.prepare(sql).bind(status) : db.prepare(sql);
        const { results } = await stmt.all();
        return json({ ok: true, inquiries: results });
      }

      // PATCH /api/admin/inquiries/:id { status?, memo? }
      if (method === "PATCH" && path[1] === "inquiries" && path[2]) {
        const id = int(path[2]);
        const row = await db.prepare("SELECT * FROM inquiries WHERE id = ?1").bind(id).first();
        if (!row) return fail("문의를 찾을 수 없습니다.", 404);
        const status = body.status !== undefined ? clip(body.status, 20) : row.status;
        if (!["new", "replied", "closed"].includes(status)) return fail("상태값이 올바르지 않습니다.");
        const memo = body.memo !== undefined ? clip(body.memo, 500) : row.memo;
        await db.prepare("UPDATE inquiries SET status = ?2, memo = ?3, updated_at = ?4 WHERE id = ?1").bind(id, status, memo, dbTime()).run();
        return json({ ok: true });
      }

      // PUT /api/admin/spaces/:id
      if (method === "PUT" && path[1] === "spaces" && path[2]) {
        const id = clip(path[2], 40);
        const row = await db.prepare("SELECT * FROM spaces WHERE id = ?1").bind(id).first();
        if (!row) return fail("없는 공간입니다.", 404);
        const status = clip(body.status ?? row.status, 10);
        if (!["live", "soon", "later"].includes(status)) return fail("상태값이 올바르지 않습니다.");
        const openDate = clip(body.open_date ?? row.open_date ?? "", 10);
        if (openDate && !isDate(openDate)) return fail("예약 시작일 형식은 YYYY-MM-DD 입니다.");
        let rooms = row.rooms;
        if (body.rooms !== undefined) {
          const list = Array.isArray(body.rooms) ? body.rooms : String(body.rooms).split(",");
          const clean = list.map((r) => clip(r, 30)).filter(Boolean);
          rooms = clean.length ? JSON.stringify(clean) : null;
        }
        const minH = int(body.min_hours, row.min_hours); const maxH = int(body.max_hours, row.max_hours);
        if (minH < 1 || maxH > 24 || minH > maxH) return fail("이용 시간 범위를 확인해 주세요.");
        let spec = row.spec, who = row.who;
        if (body.spec !== undefined) { try { spec = JSON.stringify(body.spec); } catch { return fail("이용 방식 형식 오류"); } }
        if (body.who !== undefined) { who = JSON.stringify((Array.isArray(body.who) ? body.who : String(body.who).split(",")).map((w) => clip(w, 30)).filter(Boolean)); }
        await db.prepare(`UPDATE spaces SET name=?2, short=?3, status=?4, open_label=?5, open_date=?6, bookable=?7, rooms=?8,
                          min_hours=?9, max_hours=?10, price_note=?11, description=?12, spec=?13, who=?14, photo=?15 WHERE id=?1`)
          .bind(id, clip(body.name ?? row.name, 40), clip(body.short ?? row.short, 20), status, clip(body.open_label ?? row.open_label, 40),
            openDate || null, body.bookable === undefined ? row.bookable : (body.bookable ? 1 : 0), rooms, minH, maxH,
            clip(body.price_note ?? row.price_note ?? "", 80) || null, clip(body.description ?? row.description, 600), spec, who,
            clip(body.photo ?? row.photo ?? "", 300) || null)
          .run();
        return json({ ok: true, space: parseSpace(await db.prepare("SELECT * FROM spaces WHERE id = ?1").bind(id).first()) });
      }
    }

    return fail("없는 주소입니다.", 404);
  } catch (e) {
    const msg = String(e && e.message || e);
    if (/no such table/i.test(msg)) return fail("데이터베이스 표가 아직 없습니다. schema.sql을 D1 콘솔에서 실행해 주세요.", 503);
    return fail("서버 오류: " + msg, 500);
  }
}
