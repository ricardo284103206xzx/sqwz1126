// EA验证接口（公开接口）
import { NextRequest, NextResponse } from 'next/server';
import { authDB, logDB } from '@/lib/db';
import { apiResponse, isExpired, getRemainingDays } from '@/lib/utils';

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url);
    const account = searchParams.get('account');

    if (!account) {
      return NextResponse.json(
        apiResponse(false, { authorized: false }, 'MT5账号不能为空'),
        { status: 400 }
      );
    }

    // 查询授权记录
    const auth = await authDB.getByAccount(account.toString());

    if (!auth) {
      // 记录验证失败日志
      await logVerification(account, false, '账号未授权', request);
      
      return NextResponse.json(
        apiResponse(false, { 
          authorized: false,
          account: account 
        }, '账号未授权')
      );
    }

    // 检查授权状态
    if (auth.status === 'cancelled') {
      await logVerification(account, false, '授权已取消', request);
      
      return NextResponse.json(
        apiResponse(false, { 
          authorized: false,
          account: account 
        }, '授权已取消')
      );
    }

    // 检查是否过期
    const expired = isExpired(auth.expires_at);
    if (expired) {
      // 更新状态为过期
      await authDB.update(auth._id, {
        status: 'expired' as const,
        updated_at: new Date().toISOString(),
      });
      
      await logVerification(account, false, '授权已过期', request);
      
      return NextResponse.json(
        apiResponse(false, { 
          authorized: false,
          account: account,
          expires_at: auth.expires_at
        }, '授权已过期')
      );
    }

    // 授权有效，更新验证信息
    await authDB.update(auth._id, {
      last_verified_at: new Date().toISOString(),
      verify_count: (auth.verify_count || 0) + 1,
    });

    await logVerification(account, true, '授权有效', request);

    const remainingDays = getRemainingDays(auth.expires_at);

    return NextResponse.json(
      apiResponse(true, {
        authorized: true,
        account: account,
        expires_at: auth.expires_at,
        is_permanent: auth.is_permanent,
        remaining_days: remainingDays,
      }, '授权有效')
    );
  } catch (error: any) {
    console.error('验证授权错误:', error);
    return NextResponse.json(
      apiResponse(false, { authorized: false }, '服务器错误'),
      { status: 500 }
    );
  }
}

// POST方法也支持
export async function POST(request: NextRequest) {
  return GET(request);
}

// 记录验证日志
async function logVerification(
  account: string,
  success: boolean,
  message: string,
  request: NextRequest
) {
  try {
    // 获取IP地址
    const forwarded = request.headers.get('x-forwarded-for');
    const ip = forwarded ? forwarded.split(',')[0] : 'unknown';

    await logDB.create({
      mt5_account: account,
      result: success ? 'success' : 'failed',
      message: message,
      ip_address: ip,
    });
  } catch (error) {
    console.error('记录验证日志错误:', error);
  }
}

