// 初始化接口 - 创建默认管理员
import { NextRequest, NextResponse } from 'next/server';
import { getDB, COLLECTIONS } from '@/lib/db';
import { hashPassword } from '@/lib/auth';
import { apiResponse } from '@/lib/utils';

export async function POST(request: NextRequest) {
  try {
    const db = getDB();
    const adminsCollection = db.collection(COLLECTIONS.ADMINS);

    // 检查是否已有管理员
    const { data: existingAdmins } = await adminsCollection.limit(1).get();

    if (existingAdmins && existingAdmins.length > 0) {
      return NextResponse.json(
        apiResponse(false, null, '系统已初始化，请勿重复操作'),
        { status: 400 }
      );
    }

    // 从环境变量或请求体获取默认管理员信息
    const body = await request.json().catch(() => ({}));
    const username = body.username || process.env.DEFAULT_ADMIN_USERNAME || 'admin';
    const password = body.password || process.env.DEFAULT_ADMIN_PASSWORD || 'admin123456';

    // 创建默认管理员
    const passwordHash = await hashPassword(password);
    
    await adminsCollection.add({
      username: username,
      password_hash: passwordHash,
      role: 'super_admin',
      created_at: new Date(),
      last_login_at: null,
    });

    return NextResponse.json(
      apiResponse(true, { username }, '初始化成功，请使用默认账号登录')
    );
  } catch (error: any) {
    console.error('初始化错误:', error);
    return NextResponse.json(
      apiResponse(false, null, '初始化失败: ' + error.message),
      { status: 500 }
    );
  }
}

// 支持GET请求查看初始化状态
export async function GET(request: NextRequest) {
  try {
    const db = getDB();
    const adminsCollection = db.collection(COLLECTIONS.ADMINS);

    const { data: existingAdmins } = await adminsCollection.limit(1).get();
    const initialized = existingAdmins && existingAdmins.length > 0;

    return NextResponse.json(
      apiResponse(true, { initialized }, initialized ? '系统已初始化' : '系统未初始化')
    );
  } catch (error: any) {
    console.error('检查初始化状态错误:', error);
    return NextResponse.json(
      apiResponse(false, null, '服务器错误'),
      { status: 500 }
    );
  }
}

