// 管理员登录接口
import { NextRequest, NextResponse } from 'next/server';
import { adminDB } from '@/lib/db';
import { comparePassword, generateToken } from '@/lib/auth';
import { apiResponse } from '@/lib/utils';
import { kv } from '@vercel/kv';

export async function POST(request: NextRequest) {
  try {
    const { username, password } = await request.json();

    if (!username || !password) {
      return NextResponse.json(
        apiResponse(false, null, '用户名和密码不能为空'),
        { status: 400 }
      );
    }

    // 查询管理员
    const admin = await adminDB.getByUsername(username);

    if (!admin) {
      return NextResponse.json(
        apiResponse(false, null, '用户名或密码错误'),
        { status: 401 }
      );
    }

    // 验证密码
    const isPasswordValid = await comparePassword(password, (admin as any).password_hash);
    if (!isPasswordValid) {
      return NextResponse.json(
        apiResponse(false, null, '用户名或密码错误'),
        { status: 401 }
      );
    }

    // 更新最后登录时间
    await kv.set(`admin:${(admin as any)._id}`, {
      ...admin,
      last_login_at: new Date().toISOString(),
    });

    // 生成Token
    const token = generateToken({
      id: (admin as any)._id,
      username: (admin as any).username,
      role: (admin as any).role,
    });

    return NextResponse.json(
      apiResponse(true, {
        token,
        username: (admin as any).username,
        role: (admin as any).role,
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

