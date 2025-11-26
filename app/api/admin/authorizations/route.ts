// 授权管理接口 - 列表和添加
import { NextRequest, NextResponse } from 'next/server';
import { getDB, COLLECTIONS } from '@/lib/db';
import { authenticateRequest } from '@/lib/auth';
import { apiResponse, calculateExpiryDate, isExpired, getRemainingDays } from '@/lib/utils';

// 获取授权列表
export async function GET(request: NextRequest) {
  try {
    // 验证管理员身份
    const admin = authenticateRequest(request);
    if (!admin) {
      return NextResponse.json(
        apiResponse(false, null, '未授权访问'),
        { status: 401 }
      );
    }

    const db = getDB();
    const collection = db.collection(COLLECTIONS.AUTHORIZATIONS);

    // 获取查询参数
    const { searchParams } = new URL(request.url);
    const status = searchParams.get('status');
    const search = searchParams.get('search');

    // 构建查询条件
    let query: any = {};
    
    if (status && status !== 'all') {
      query.status = status;
    }
    
    if (search) {
      query.mt5_account = new RegExp(search);
    }

    // 查询授权列表
    const { data: authorizations } = await collection
      .where(query)
      .orderBy('created_at', 'desc')
      .get();

    // 处理数据，添加计算字段
    const processedData = authorizations.map((auth: any) => {
      const expired = isExpired(auth.expires_at);
      const remainingDays = getRemainingDays(auth.expires_at);
      
      return {
        ...auth,
        is_expired: expired,
        remaining_days: remainingDays,
        status: expired && auth.status === 'active' ? 'expired' : auth.status,
      };
    });

    return NextResponse.json(
      apiResponse(true, processedData, '获取成功')
    );
  } catch (error: any) {
    console.error('获取授权列表错误:', error);
    return NextResponse.json(
      apiResponse(false, null, '服务器错误'),
      { status: 500 }
    );
  }
}

// 添加授权
export async function POST(request: NextRequest) {
  try {
    // 验证管理员身份
    const admin = authenticateRequest(request);
    if (!admin) {
      return NextResponse.json(
        apiResponse(false, null, '未授权访问'),
        { status: 401 }
      );
    }

    const { mt5_account, duration_days, notes } = await request.json();

    // 验证必填字段
    if (!mt5_account) {
      return NextResponse.json(
        apiResponse(false, null, 'MT5账号不能为空'),
        { status: 400 }
      );
    }

    if (duration_days === undefined || duration_days === null) {
      return NextResponse.json(
        apiResponse(false, null, '授权时长不能为空'),
        { status: 400 }
      );
    }

    const db = getDB();
    const collection = db.collection(COLLECTIONS.AUTHORIZATIONS);

    // 检查账号是否已存在
    const { data: existing } = await collection
      .where({ mt5_account })
      .limit(1)
      .get();

    if (existing && existing.length > 0) {
      return NextResponse.json(
        apiResponse(false, null, '该MT5账号已存在授权记录'),
        { status: 400 }
      );
    }

    // 计算过期时间
    const isPermanent = duration_days === -1;
    const expiresAt = calculateExpiryDate(duration_days);
    const now = new Date();

    // 创建授权记录
    const authData = {
      mt5_account: mt5_account.toString(),
      authorized_at: now,
      expires_at: expiresAt,
      is_permanent: isPermanent,
      duration_days: duration_days,
      status: 'active',
      notes: notes || '',
      created_by: admin.username,
      last_verified_at: null,
      verify_count: 0,
      created_at: now,
      updated_at: now,
    };

    const result = await collection.add(authData);

    return NextResponse.json(
      apiResponse(true, { id: result.id, ...authData }, '授权添加成功')
    );
  } catch (error: any) {
    console.error('添加授权错误:', error);
    return NextResponse.json(
      apiResponse(false, null, '服务器错误'),
      { status: 500 }
    );
  }
}

