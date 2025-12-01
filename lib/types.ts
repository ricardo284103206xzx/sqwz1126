// 数据类型定义

export interface Authorization {
  _id: string;
  account: string;
  mt5_account: string;
  status: 'active' | 'expired' | 'cancelled';
  expires_at: string | null;
  is_permanent: boolean;
  duration_days?: number;
  authorized_at: string;
  created_at: string;
  updated_at?: string;
  last_verified_at?: string | null;
  verify_count?: number;
  notes?: string;
  created_by?: string;
  createTime?: string;
  updateTime?: string;
}

export interface Admin {
  _id: string;
  username: string;
  password: string;
  password_hash?: string;
  role?: string;
  created_at?: string;
  last_login_at?: string | null;
}

export interface VerificationLog {
  _id: string;
  mt5_account: string;
  result: 'success' | 'failed';
  message: string;
  ip_address: string;
  timestamp: string;
}

