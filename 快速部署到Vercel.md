# 🚀 快速部署到 Vercel（5分钟完成）

## 一键部署步骤

### 1️⃣ 准备 GitHub 仓库（2分钟）

在项目目录打开终端，执行：

```bash
# 如果还没有初始化 Git
git init

# 添加所有文件
git add .

# 提交
git commit -m "Ready for Vercel deployment"

# 创建 GitHub 仓库后，关联并推送
git remote add origin https://github.com/你的用户名/你的仓库名.git
git push -u origin main
```

### 2️⃣ 导入到 Vercel（1分钟）

1. 访问：https://vercel.com/new
2. 使用 GitHub 登录
3. 选择您的仓库
4. 点击 "Import"

### 3️⃣ 配置环境变量（2分钟）

在 Vercel 配置页面添加以下环境变量：

```
JWT_SECRET=your-random-secret-key-change-this
TCB_ENV_ID=你的腾讯云环境ID
TCB_SECRET_ID=你的腾讯云SecretId
TCB_SECRET_KEY=你的腾讯云SecretKey
DEFAULT_ADMIN_USERNAME=admin
DEFAULT_ADMIN_PASSWORD=admin123456
```

**获取腾讯云密钥：**
https://console.cloud.tencent.com/cam/capi

### 4️⃣ 部署（自动）

点击 "Deploy" 按钮，等待 2-3 分钟。

### 5️⃣ 获取您的 API 地址

部署成功后，您会得到：
```
https://your-project.vercel.app
```

您的授权 API 地址：
```
https://your-project.vercel.app/api/verify
```

### 6️⃣ 更新 MQ5 文件

修改 `网站授权版3-2.mq5` 第 14 行：

```cpp
input string AuthServerURL = "https://your-project.vercel.app/api/verify";
```

**替换 `your-project` 为您的实际 Vercel 项目域名。**

---

## ✅ 完成！

现在您可以：
1. 访问管理后台：`https://your-project.vercel.app/login`
2. 添加 MT5 账号授权
3. 在 MT5 中加载 EA 进行测试

---

## 📝 注意事项

### ⚠️ Vercel 在国内访问问题

Vercel 在国内可能不稳定，如果遇到访问问题：

**临时解决方案：**
- 使用 VPN 或代理
- 使用移动网络（有时比宽带稳定）

**长期解决方案：**
- 迁移到腾讯云香港服务器
- 使用 Cloudflare Workers
- 使用阿里云香港服务器

### 🔄 后续更新

每次修改代码后，只需：
```bash
git add .
git commit -m "更新说明"
git push
```

Vercel 会自动重新部署。

---

## 🆘 遇到问题？

查看详细教程：`Vercel部署教程.md`

常见问题：
- 部署失败 → 检查环境变量
- API 500 错误 → 检查腾讯云密钥
- 国内无法访问 → 考虑香港服务器方案


