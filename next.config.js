/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // 支持部署到子目录
  basePath: '',
  // Vercel 部署不需要 standalone 模式
  // output: 'standalone',
  // API路由配置
  async headers() {
    return [
      {
        source: '/api/:path*',
        headers: [
          { key: 'Access-Control-Allow-Origin', value: '*' },
          { key: 'Access-Control-Allow-Methods', value: 'GET,POST,PUT,DELETE,OPTIONS' },
          { key: 'Access-Control-Allow-Headers', value: 'Content-Type, Authorization' },
        ],
      },
    ];
  },
}

module.exports = nextConfig

