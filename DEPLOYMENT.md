# 🚀 Vercel 部署指南

## 前提准备

✅ 系统已完成 Supabase 集成
✅ 本地测试通过
✅ 所有数据已迁移到云端

---

## 部署步骤

### 方法 1: 通过 Vercel CLI（推荐）

#### 1. 安装 Vercel CLI

```bash
npm install -g vercel
```

#### 2. 登录 Vercel

```bash
vercel login
```

#### 3. 部署项目

```bash
cd /Users/pc/simple-pos-system
vercel
```

按提示操作：
- Set up and deploy? **Y**
- Which scope? 选择你的账号
- Link to existing project? **N**
- Project name? `simple-pos-system` (或自定义)
- In which directory is your code located? **./`**(当前目录)

#### 4. 完成！

部署完成后会显示：
```
✅ Production: https://your-project.vercel.app
```

---

### 方法 2: 通过 Vercel Dashboard（更简单）

#### 1. 访问 Vercel

打开 https://vercel.com/login

#### 2. 创建新项目

1. 点击 "Add New" → "Project"
2. 选择 "Import Git Repository" 或 "Deploy from local"

#### 3. 如果使用 Git：

```bash
cd /Users/pc/simple-pos-system
git init
git add .
git commit -m "Initial commit with Supabase integration"
```

然后推送到 GitHub：
```bash
gh repo create simple-pos-system --public --source=. --remote=origin --push
```

#### 4. 在 Vercel 导入仓库

- 选择你的仓库
- 点击 "Import"
- Vercel 会自动检测配置
- 点击 "Deploy"

---

## 部署后配置

### 1. 设置环境变量（可选）

虽然 Supabase anon key 可以公开，但如果想要额外保护：

在 Vercel Dashboard → Settings → Environment Variables 添加：
- `SUPABASE_URL`: `https://tskelejztsdeewtpjcoq.supabase.co`
- `SUPABASE_ANON_KEY`: `your-anon-key`

### 2. 配置自定义域名（可选）

Vercel Dashboard → Settings → Domains
- 添加你的域名
- 按照提示配置 DNS

### 3. 验证部署

访问部署的 URL：
- **前台**: `https://your-project.vercel.app/`
- **后台**: `https://your-project.vercel.app/admin.html`

测试功能：
- ✅ 菜单显示正常
- ✅ 下单功能正常
- ✅ 后台登录正常
- ✅ 数据同步正常

---

## 常见问题

### Q: 部署后显示 404

**A:** 检查 vercel.json 配置是否正确，确保路由设置正确。

### Q: Supabase 连接失败

**A:** 检查：
1. Supabase URL 和 Key 是否正确
2. RLS 策略是否正确设置
3. 浏览器控制台是否有错误

### Q: 如何更新部署？

**A:** 修改代码后重新运行：
```bash
vercel --prod
```

或者 Git 推送后自动部署：
```bash
git add .
git commit -m "Update"
git push
```

---

## 🎉 部署成功后

系统现在是：
- ☁️ 全球可访问
- 🔒 自动 HTTPS
- ⚡ CDN 加速
- 📱 移动端友好

**下一步：**
- 分享链接给员工
- 开始接收订单
- 监控系统运行

---

## 需要帮助？

如果遇到问题：
1. 检查 Vercel 部署日志
2. 查看浏览器控制台
3. 检查 Supabase Dashboard 的 Logs

**祝生意兴隆！** 🍱✨
