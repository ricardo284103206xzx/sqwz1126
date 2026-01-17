# Vercel 部署教程

## 📋 前置准备

1. **GitHub 账号**（必需）
2. **Vercel 账号**（免费，使用 GitHub 登录）
3. **腾讯云开发环境**（已有数据库）

---

## 🚀 部署步骤

### 第一步：准备 GitHub 仓库

#### 方法1：使用现有仓库
如果您已经有 GitHub 仓库，跳过此步骤。

#### 方法2：创建新仓库

1. 访问 https://github.com/new
2. 创建新仓库（可以是私有仓库）
3. 在本地项目目录执行：

```bash
# 初始化 Git（如果还没有）
git init

# 添加远程仓库
git remote add origin https://github.com/你的用户名/你的仓库名.git

# 添加所有文件
git add .

# 提交
git commit -m "Initial commit"

# 推送到 GitHub
git push -u origin main
```

---

### 第二步：连接 Vercel

1. **访问 Vercel**
   - 打开 https://vercel.com
   - 点击 "Sign Up" 或 "Login"
   - 选择 "Continue with GitHub"

2. **导入项目**
   - 登录后，点击 "Add New..." → "Project"
   - 选择您的 GitHub 仓库
   - 点击 "Import"

3. **配置项目**
   - **Framework Preset**: 自动检测为 Next.js
   - **Root Directory**: 保持默认 `./`
   - **Build Command**: `npm run build`
   - **Output Directory**: `.next`

---

### 第三步：配置环境变量

在 Vercel 项目配置页面，找到 "Environment Variables" 部分，添加以下变量：

| 变量名 | 值 | 说明 |
|--------|-----|------|
| `JWT_SECRET` | `your-random-secret-key-12345` | JWT 密钥（随机字符串） |
| `TCB_ENV_ID` | `你的腾讯云环境ID` | 腾讯云开发环境 ID |
| `TCB_SECRET_ID` | `你的SecretId` | 腾讯云 API 密钥 ID |
| `TCB_SECRET_KEY` | `你的SecretKey` | 腾讯云 API 密钥 Key |
| `DEFAULT_ADMIN_USERNAME` | `admin` | 默认管理员用户名 |
| `DEFAULT_ADMIN_PASSWORD` | `admin123456` | 默认管理员密码 |

**获取腾讯云密钥：**
1. 访问 https://console.cloud.tencent.com/cam/capi
2. 点击 "新建密钥"
3. 复制 SecretId 和 SecretKey

---

### 第四步：部署

1. 点击 "Deploy" 按钮
2. 等待构建完成（约 2-3 分钟）
3. 部署成功后，您会获得一个域名，例如：
   ```
   https://your-project.vercel.app
   ```

---

### 第五步：测试授权 API

1. **测试 API 端点**
   ```
   https://your-project.vercel.app/api/verify
   ```

2. **使用 Postman 或浏览器测试**
   ```bash
   curl -X POST https://your-project.vercel.app/api/verify \
     -H "Content-Type: application/json" \
     -d '{"mt5_account":"123456"}'
   ```

3. **预期响应**（未授权账户）：
   ```json
   {
     "success": false,
     "message": "账号未授权"
   }
   ```

---

### 第六步：更新 MQ5 文件

修改您的 MQ5 文件中的服务器地址：

```cpp
// 修改前
input string AuthServerURL = "https://mt5-auth-system5-202854-6-1386563557.sh.run.tcloudbase.com/api/verify";

// 修改后
input string AuthServerURL = "https://your-project.vercel.app/api/verify";
```

**替换 `your-project` 为您的实际 Vercel 项目名称。**

---

### 第七步：访问管理后台

1. **访问登录页面**
   ```
   https://your-project.vercel.app/login
   ```

2. **使用默认账号登录**
   - 用户名：`admin`
   - 密码：`admin123456`

3. **初始化数据库**
   - 首次访问会自动初始化
   - 或访问：`https://your-project.vercel.app/api/admin/init`

4. **添加授权**
   - 登录后台
   - 添加 MT5 账号授权
   - 设置到期时间

---

## 🔧 常见问题

### 1. 部署失败怎么办？

**查看构建日志：**
- 在 Vercel 项目页面，点击失败的部署
- 查看 "Build Logs" 查找错误信息

**常见错误：**
- **依赖安装失败**：检查 `package.json` 是否正确
- **环境变量缺失**：确保所有环境变量都已配置
- **TypeScript 错误**：运行 `npm run build` 本地测试

### 2. API 返回 500 错误

**检查环境变量：**
- 确保腾讯云密钥正确
- 确保环境 ID 正确
- 在 Vercel 项目设置中重新检查所有环境变量

### 3. 国内访问 Vercel 不稳定

**解决方案：**
- 使用 Cloudflare 作为 CDN（需要自定义域名）
- 或考虑迁移到腾讯云香港服务器
- 或使用 Vercel 的香港节点（企业版功能）

### 4. 如何更新代码？

**自动部署：**
- 推送代码到 GitHub：`git push`
- Vercel 会自动检测并重新部署

**手动部署：**
- 在 Vercel 项目页面点击 "Redeploy"

### 5. 如何绑定自定义域名？

1. 在 Vercel 项目设置中，找到 "Domains"
2. 添加您的域名
3. 按照提示配置 DNS 记录
4. **注意：国内域名需要备案**

---

## 📊 监控和日志

### 查看访问日志
1. 进入 Vercel 项目页面
2. 点击 "Logs" 标签
3. 查看实时请求日志

### 查看性能指标
1. 点击 "Analytics" 标签
2. 查看访问量、响应时间等

---

## 💰 费用说明

**Vercel 免费版限制：**
- ✅ 无限部署
- ✅ 100GB 带宽/月
- ✅ 100 次无服务器函数调用/天
- ✅ 自动 HTTPS
- ✅ 全球 CDN

**对于 MT5 授权验证系统，免费版完全够用！**

---

## 🔐 安全建议

1. **修改默认管理员密码**
   - 登录后台后立即修改

2. **定期更换 JWT_SECRET**
   - 在 Vercel 环境变量中更新

3. **限制 API 访问**
   - 考虑添加 IP 白名单
   - 添加请求频率限制

4. **备份数据**
   - 定期导出腾讯云数据库数据

---

## 📞 获取帮助

- **Vercel 文档**: https://vercel.com/docs
- **Next.js 文档**: https://nextjs.org/docs
- **腾讯云开发**: https://cloud.tencent.com/document/product/876

---

## ✅ 部署检查清单

- [ ] GitHub 仓库已创建并推送代码
- [ ] Vercel 账号已注册
- [ ] 项目已导入到 Vercel
- [ ] 所有环境变量已配置
- [ ] 部署成功（绿色勾）
- [ ] API 测试通过
- [ ] 管理后台可以访问
- [ ] MQ5 文件已更新服务器地址
- [ ] MT5 EA 测试通过

---

**祝您部署顺利！🎉**














