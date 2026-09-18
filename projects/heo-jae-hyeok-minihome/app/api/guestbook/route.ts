import { env } from 'cloudflare:workers';
import { isAdmin } from '@/lib/admin-auth';

type GuestbookRow = {
  id: number;
  nickname: string;
  message: string;
  createdAt: number;
};

const listEntriesSql = `
  SELECT id, nickname, message, created_at AS createdAt
  FROM guestbook_entries
  ORDER BY created_at DESC, id DESC
  LIMIT 100
`;

export async function GET() {
  try {
    const result = await env.DB.prepare(listEntriesSql).all<GuestbookRow>();

    return Response.json(
      { entries: result.results },
      { headers: { 'Cache-Control': 'no-store' } },
    );
  } catch (error) {
    console.error('Failed to load guestbook entries', error);
    return Response.json(
      { message: '방명록을 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.' },
      { status: 500 },
    );
  }
}

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as {
      nickname?: unknown;
      message?: unknown;
    };
    const nickname = typeof body.nickname === 'string' ? body.nickname.trim() : '';
    const message = typeof body.message === 'string' ? body.message.trim() : '';

    if (!nickname || !message) {
      return Response.json(
        { message: '닉네임과 메시지를 모두 입력해 주세요.' },
        { status: 400 },
      );
    }

    if (nickname.length > 20 || message.length > 200) {
      return Response.json(
        { message: '닉네임은 20자, 메시지는 200자 이내로 입력해 주세요.' },
        { status: 400 },
      );
    }

    const createdAt = Date.now();
    const entry = await env.DB.prepare(`
      INSERT INTO guestbook_entries (nickname, message, created_at)
      VALUES (?, ?, ?)
      RETURNING id, nickname, message, created_at AS createdAt
    `)
      .bind(nickname, message, createdAt)
      .first<GuestbookRow>();

    return Response.json({ entry }, { status: 201 });
  } catch (error) {
    console.error('Failed to create guestbook entry', error);
    return Response.json(
      { message: '글을 저장하지 못했습니다. 잠시 후 다시 시도해 주세요.' },
      { status: 500 },
    );
  }
}

export async function PATCH(request: Request) {
  if (!(await isAdmin(request))) return Response.json({ message: '허재혁님만 접근이 가능합니다' }, { status: 401 });
  const body = (await request.json()) as { id?: unknown; nickname?: unknown; message?: unknown };
  const id = typeof body.id === 'number' ? body.id : Number(body.id);
  const nickname = typeof body.nickname === 'string' ? body.nickname.trim() : '';
  const message = typeof body.message === 'string' ? body.message.trim() : '';
  if (!Number.isInteger(id) || id < 1 || !nickname || !message) return Response.json({ message: '수정할 글과 내용을 확인해 주세요.' }, { status: 400 });
  if (nickname.length > 20 || message.length > 200) return Response.json({ message: '닉네임은 20자, 메시지는 200자 이내로 입력해 주세요.' }, { status: 400 });
  const entry = await env.DB.prepare(`
    UPDATE guestbook_entries SET nickname = ?, message = ? WHERE id = ?
    RETURNING id, nickname, message, created_at AS createdAt
  `).bind(nickname, message, id).first<GuestbookRow>();
  if (!entry) return Response.json({ message: '해당 방명록 글을 찾지 못했습니다.' }, { status: 404 });
  return Response.json({ entry });
}

export async function DELETE(request: Request) {
  if (!(await isAdmin(request))) return Response.json({ message: '허재혁님만 접근이 가능합니다' }, { status: 401 });
  const body = (await request.json()) as { id?: unknown };
  const id = typeof body.id === 'number' ? body.id : Number(body.id);
  if (!Number.isInteger(id) || id < 1) return Response.json({ message: '삭제할 방명록 글을 확인해 주세요.' }, { status: 400 });
  const deleted = await env.DB.prepare(`DELETE FROM guestbook_entries WHERE id = ? RETURNING id`).bind(id).first<{ id: number }>();
  if (!deleted) return Response.json({ message: '해당 방명록 글을 찾지 못했습니다.' }, { status: 404 });
  return Response.json({ deletedId: deleted.id, message: '방명록 글이 삭제되었습니다.' });
}
