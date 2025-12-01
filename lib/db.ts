// 数据库配置 - 使用 Vercel KV (Redis)
import { kv } from '@vercel/kv';
import type { Authorization, Admin, VerificationLog } from './types';

// 数据键前缀
export const KEYS = {
  AUTHORIZATIONS: 'auth:',
  ADMINS: 'admin:',
  VERIFICATION_LOGS: 'log:',
  AUTH_LIST: 'auth_list',
  LOG_LIST: 'log_list',
};

// 获取KV实例
export function getKV() {
  return kv;
}

// 辅助函数：生成唯一ID
export function generateId(): string {
  return Date.now().toString(36) + Math.random().toString(36).substr(2);
}

// 授权数据操作
export const authDB = {
  // 创建授权
  async create(data: Partial<Authorization>): Promise<Authorization> {
    const id = generateId();
    const authData = { ...data, _id: id, createTime: new Date().toISOString() } as Authorization;
    await kv.set(`${KEYS.AUTHORIZATIONS}${id}`, authData);
    await kv.sadd(KEYS.AUTH_LIST, id);
    return authData;
  },
  
  // 获取所有授权
  async getAll(): Promise<Authorization[]> {
    const ids = await kv.smembers(KEYS.AUTH_LIST);
    if (!ids || ids.length === 0) return [];
    const auths = await Promise.all(
      ids.map(id => kv.get(`${KEYS.AUTHORIZATIONS}${id}`))
    );
    return auths.filter(Boolean) as Authorization[];
  },
  
  // 根据ID获取
  async getById(id: string): Promise<Authorization | null> {
    return await kv.get(`${KEYS.AUTHORIZATIONS}${id}`) as Authorization | null;
  },
  
  // 根据账号获取
  async getByAccount(account: string): Promise<Authorization | undefined> {
    const all = await this.getAll();
    return all.find((a: Authorization) => a.account === account);
  },
  
  // 更新授权
  async update(id: string, data: Partial<Authorization>): Promise<Authorization | null> {
    const existing = await this.getById(id);
    if (!existing) return null;
    const updated = { ...existing, ...data, updateTime: new Date().toISOString() } as Authorization;
    await kv.set(`${KEYS.AUTHORIZATIONS}${id}`, updated);
    return updated;
  },
  
  // 删除授权
  async delete(id: string): Promise<boolean> {
    await kv.del(`${KEYS.AUTHORIZATIONS}${id}`);
    await kv.srem(KEYS.AUTH_LIST, id);
    return true;
  }
};

// 管理员数据操作
export const adminDB = {
  // 创建管理员
  async create(data: Partial<Admin>): Promise<Admin> {
    const id = generateId();
    const adminData = { ...data, _id: id } as Admin;
    await kv.set(`${KEYS.ADMINS}${id}`, adminData);
    return adminData;
  },
  
  // 根据用户名获取
  async getByUsername(username: string): Promise<Admin | null> {
    const keys = await kv.keys(`${KEYS.ADMINS}*`);
    for (const key of keys) {
      const admin = await kv.get(key) as Admin | null;
      if (admin && admin.username === username) {
        return admin;
      }
    }
    return null;
  }
};

// 验证日志操作
export const logDB = {
  // 创建日志
  async create(data: Partial<VerificationLog>): Promise<VerificationLog> {
    const id = generateId();
    const logData = { ...data, _id: id, timestamp: new Date().toISOString() } as VerificationLog;
    await kv.set(`${KEYS.VERIFICATION_LOGS}${id}`, logData);
    await kv.sadd(KEYS.LOG_LIST, id);
    return logData;
  },
  
  // 获取所有日志
  async getAll(): Promise<VerificationLog[]> {
    const ids = await kv.smembers(KEYS.LOG_LIST);
    if (!ids || ids.length === 0) return [];
    const logs = await Promise.all(
      ids.map(id => kv.get(`${KEYS.VERIFICATION_LOGS}${id}`))
    );
    return logs.filter(Boolean) as VerificationLog[];
  }
};

