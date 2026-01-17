# 🚀 Vercel 一键部署（无需腾讯云）

## 超简单部署步骤

### 第1步：在Vercel导入项目（1分钟）

1. 打开：https://vercel.com/new
2. 用GitHub登录
3. 找到 `sqwz1126` 仓库，点击 **Import**

### 第2步：配置环境变量（1分钟）

在Vercel配置页面，添加以下2个环境变量：

```
JWT_SECRET=my-super-secret-jwt-key-2024
DEFAULT_ADMIN_USERNAME=admin
DEFAULT_ADMIN_PASSWORD=admin123456
```

**说明：**
- `JWT_SECRET` - 随便填一个长字符串即可
- `DEFAULT_ADMIN_USERNAME` - 管理员用户名
- `DEFAULT_ADMIN_PASSWORD` - 管理员密码

### 第3步：添加Vercel KV数据库（2分钟）

1. 点击 **Deploy** 按钮，等待部署完成
2. 部署完成后，进入项目控制台
3. 点击顶部菜单 **Storage** 标签
4. 点击 **Create Database**
5. 选择 **KV** (Redis)
6. 输入数据库名称（比如：`mt5-auth-db`）
7. 点击 **Create**
8. 系统会自动将数据库连接到你的项目

### 第4步：重新部署（1分钟）

1. 在项目控制台，点击顶部 **Deployments** 标签
2. 点击最新的部署右侧的 **...** 按钮
3. 选择 **Redeploy**
4. 等待重新部署完成

---

## ✅ 完成！

你的授权系统已经部署成功！

**你的网站地址：**
```
https://your-project.vercel.app
```

**管理后台登录：**
```
https://your-project.vercel.app/login
用户名: admin
密码: admin123456
```

**授权API地址：**
```
https://your-project.vercel.app/api/verify
```

---

## 📝 下一步

### 1. 初始化系统

首次使用需要初始化，访问：
```
https://your-project.vercel.app/api/admin/init
```

或者在管理后台登录时会自动初始化。

### 2. 修改MQ5文件

编辑 `网站授权版3-2.mq5` 第14行：

```cpp
input string AuthServerURL = "https://your-project.vercel.app/api/verify";
```

**替换 `your-project` 为你的实际Vercel项目域名。**

### 3. 添加授权

1. 登录管理后台
2. 点击"添加授权"
3. 输入MT5账号和授权时长
4. 保存

### 4. 测试EA

在MT5中加载EA，查看是否能正常验证授权。

---

## 🎉 优势

✅ **完全免费** - Vercel和KV数据库都有免费额度  
✅ **无需腾讯云** - 不需要任何第三方云服务  
✅ **自动扩展** - Vercel自动处理流量  
✅ **全球CDN** - 访问速度快  
✅ **简单维护** - Git推送自动部署  

---

## 💡 免费额度说明

**Vercel免费版：**
- 100GB带宽/月
- 无限请求
- 自动HTTPS
- 全球CDN

**Vercel KV免费版：**
- 256MB存储
- 30,000次读取/月
- 1,000次写入/月
- 对于个人使用完全够用

---

## 🔄 后续更新

修改代码后，只需：

```bash
git add .
git commit -m "更新说明"
git push
```

Vercel会自动重新部署。

---

## ⚠️ 注意事项

1. **修改默认密码**：首次登录后，建议修改管理员密码
2. **保护JWT_SECRET**：不要泄露你的JWT密钥
3. **国内访问**：Vercel在国内可能偶尔不稳定，但MT5服务器通常在国外，不影响EA使用

---

## 🆘 常见问题

**Q: 部署后访问500错误？**  
A: 确保已经创建了KV数据库并重新部署

**Q: 登录失败？**  
A: 先访问 `/api/admin/init` 初始化系统

**Q: KV数据库额度用完了？**  
A: 升级到Vercel Pro（$20/月）或优化请求频率

**Q: 想要更多存储？**  
A: 可以改用Vercel Postgres数据库（免费版有256MB）

---

## 📚 相关文档

- Vercel文档：https://vercel.com/docs
- Vercel KV文档：https://vercel.com/docs/storage/vercel-kv








