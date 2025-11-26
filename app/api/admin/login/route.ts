// 管理员登录接口
import { NextRequest, NextResponse } from 'next/server';
import { getDB, COLLECTIONS } from '@/lib/db';
import { comparePassword, generateToken } from '@/lib/auth';
import { apiResponse } from '@/lib/utils';

export async function POST(request: NextRequest) {
  try {
    const { username, password } = await request.json();

    if (!username || !password) {
      return NextResponse.json(
        apiResponse(false, null, '用户名和密码不能为空'),
        { status: 400 }
      );
    }

    const db = getDB();
    const adminsCollection = db.collection(COLLECTIONS.ADMINS);

    // 查询管理员
    const { data: admins } = await adminsCollection
      .where({ username })
      .limit(1)
      .get();

    if (!admins || admins.length === 0) {
      return NextResponse.json(
        apiResponse(false, null, '用户名或密码错误'),
        { status: 401 }
      );
    }

    const admin = admins[0];

    // 验证密码
    const isPasswordValid = await comparePassword(password, admin.password_hash);
    if (!isPasswordValid) {
      return NextResponse.json(
        apiResponse(false, null, '用户名或密码错误'),
        { status: 401 }
      );
    }

    // 更新最后登录时间
    await adminsCollection.doc(admin._id).update({
      last_login_at: new Date(),
    });

    // 生成Token
    const token = generateToken({
      id: admin._id,
      username: admin.username,
      role: admin.role,
    });

    return NextResponse.json(
      apiResponse(true, {
        token,
        username: admin.username,
        role: admin.role,
      }, '登录成功')
    );
  } catch (error: any) {
    console.error('登录错误:', error);
    return NextResponse.json(
      apiResponse(false, null, '服务器错误'),
      { status: 500 }
    );
  }
}

