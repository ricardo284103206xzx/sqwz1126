declare module '@vercel/kv' {
  export interface KV {
    get<T = any>(key: string): Promise<T | null>;
    set<T = any>(key: string, value: T): Promise<void>;
    del(...keys: string[]): Promise<number>;
    keys(pattern: string): Promise<string[]>;
    sadd(key: string, ...members: string[]): Promise<number>;
    srem(key: string, ...members: string[]): Promise<number>;
    smembers(key: string): Promise<string[]>;
  }

  export const kv: KV;
}

