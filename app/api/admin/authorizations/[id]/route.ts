// 授权管理接口 - 更新和删除
import { NextRequest, NextResponse } from 'next/server';
import { authDB } from '@/lib/db';
import { authenticateRequest } from '@/lib/auth';
import { apiResponse, calculateExpiryDate } from '@/lib/utils';

// 更新授权（延期）
export async function PUT(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  try {
    // 验证管理员身份
    const admin = authenticateRequest(request);
    if (!admin) {
      return NextResponse.json(
        apiResponse(false, null, '未授权访问'),
        { status: 401 }
      );
    }

    const { id } = params;
    const { duration_days, notes } = await request.json();

    // 计算新的过期时间
    const isPermanent = duration_days === -1;
    const expiresAt = calculateExpiryDate(duration_days);

    // 更新授权
    const updateData: any = {
      expires_at: expiresAt,
      is_permanent: isPermanent,
      duration_days: duration_days,
      status: 'active' as const,
      updated_at: new Date().toISOString(),
    };

    if (notes !== undefined) {
      updateData.notes = notes;
    }

    const result = await authDB.update(id, updateData);

    return NextResponse.json(
      apiResponse(true, result, '授权更新成功')
    );
  } catch (error: any) {
    console.error('更新授权错误:', error);
    return NextResponse.json(
      apiResponse(false, null, '服务器错误'),
      { status: 500 }
    );
  }
}

// 删除授权
export async function DELETE(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  try {
    // 验证管理员身份
    const admin = authenticateRequest(request);
    if (!admin) {
      return NextResponse.json(
        apiResponse(false, null, '未授权访问'),
        { status: 401 }
      );
    }

    const { id } = params;

    // 获取查询参数，判断是取消还是删除
    const { searchParams } = new URL(request.url);
    const action = searchParams.get('action') || 'cancel';

    if (action === 'cancel') {
      // 取消授权（软删除）
      await authDB.update(id, {
        status: 'cancelled' as const,
        updated_at: new Date().toISOString(),
      });
      return NextResponse.json(
        apiResponse(true, null, '授权已取消')
      );
    } else {
      // 永久删除
      await authDB.delete(id);
      return NextResponse.json(
        apiResponse(true, null, '授权已删除')
      );
    }
  } catch (error: any) {
    console.error('删除授权错误:', error);
    return NextResponse.json(
      apiResponse(false, null, '服务器错误'),
      { status: 500 }
    );
  }
}

