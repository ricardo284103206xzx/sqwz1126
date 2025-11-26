// 数据库连接配置
import tcb from '@cloudbase/node-sdk';

let app: any = null;

// 初始化云开发
export function initDB() {
  if (app) return app;
  
  app = tcb.init({
    env: process.env.TCB_ENV_ID,
    secretId: process.env.TCB_SECRET_ID,
    secretKey: process.env.TCB_SECRET_KEY,
  });
  
  return app;
}

// 获取数据库实例
export function getDB() {
  const app = initDB();
  return app.database();
}

// 集合名称
export const COLLECTIONS = {
  AUTHORIZATIONS: 'authorizations',
  ADMINS: 'admins',
  VERIFICATION_LOGS: 'verification_logs',
};

