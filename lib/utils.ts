// 通用工具函数
import dayjs from 'dayjs';

// API响应格式
export function apiResponse(success: boolean, data: any = null, message: string = '') {
  return {
    success,
    data,
    message,
    timestamp: Math.floor(Date.now() / 1000),
  };
}

// 计算过期时间
export function calculateExpiryDate(days: number): string | null {
  if (days === -1) return null; // 永久授权
  return dayjs().add(days, 'day').toISOString();
}

// 检查是否过期
export function isExpired(expiresAt: string | null): boolean {
  if (!expiresAt) return false; // 永久授权不过期
  return dayjs(expiresAt).isBefore(dayjs());
}

// 计算剩余天数
export function getRemainingDays(expiresAt: string | null): number {
  if (!expiresAt) return -1; // 永久授权返回-1
  const days = dayjs(expiresAt).diff(dayjs(), 'day');
  return days > 0 ? days : 0;
}

// 格式化日期
export function formatDate(date: string | null): string {
  if (!date) return '永久';
  return dayjs(date).format('YYYY-MM-DD HH:mm:ss');
}

// 获取客户端IP
export function getClientIP(request: Request): string {
  const forwarded = request.headers.get('x-forwarded-for');
  const ip = forwarded ? forwarded.split(',')[0] : 'unknown';
  return ip;
}

