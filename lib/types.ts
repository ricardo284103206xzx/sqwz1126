// 数据类型定义

export interface Authorization {
  _id: string;
  account: string;
  status: 'active' | 'expired' | 'cancelled';
  expires_at: string;
  is_permanent: boolean;
  created_at: string;
  updated_at?: string;
  last_verified_at?: string;
  verify_count?: number;
  createTime?: string;
  updateTime?: string;
}

export interface Admin {
  _id: string;
  username: string;
  password: string;
}

export interface VerificationLog {
  _id: string;
  mt5_account: string;
  result: 'success' | 'failed';
  message: string;
  ip_address: string;
  timestamp: string;
}

