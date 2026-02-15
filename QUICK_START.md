# 🚀 快速啟動指南

## 📋 檔案清單

已為您創建以下檔案：

```
/Users/pc/simple-pos-system/
├── index.html          ✅ HTML 入口檔案
├── main.jsx           ✅ React 入口
├── App.jsx            ✅ 主應用組件（核心邏輯）
├── App.css            ✅ 基礎樣式
├── package.json       ✅ 依賴配置
├── vite.config.js     ✅ Vite 設定
├── README.md          ✅ 專案說明
├── LOGIC_FLOW.md      ✅ 邏輯流程詳解
└── QUICK_START.md     ✅ 本檔案
```

---

## 🎯 立即啟動（3 步驟）

### 步驟 1：安裝依賴
```bash
cd /Users/pc/simple-pos-system
npm install
```

⏱️ 預計需要 1-2 分鐘（視網路速度）

### 步驟 2：啟動開發伺服器
```bash
npm run dev
```

您應該會看到：
```
  VITE v5.0.8  ready in 500 ms

  ➜  Local:   http://localhost:5173/
  ➜  Network: use --host to expose
```

### 步驟 3：開啟瀏覽器
訪問 http://localhost:5173

✅ 完成！您應該能看到點餐系統介面了。

---

## 🧪 測試功能

### 測試 1：加入品項
1. 點擊「招牌牛排」旁的「加入」按鈕
2. 右側購物車應顯示：招牌牛排 × 1，小計 $380

### 測試 2：增加數量
1. 點擊「+」按鈕
2. 數量變為 2，小計變為 $760

### 測試 3：減少至移除
1. 點擊「-」按鈕至數量為 1
2. 再點一次「-」按鈕
3. 該品項應從購物車移除

### 測試 4：計算總額
1. 加入多個品項
2. 底部應正確顯示總金額

### 測試 5：送出訂單
1. 點擊「送出訂單」按鈕
2. 彈出 Alert 顯示總金額
3. 購物車清空

---

## 📖 核心邏輯速查

### 加入購物車邏輯
```javascript
const existingItem = cart.find(item => item.id === product.id);
if (existingItem) {
  // 增加數量
} else {
  // 新增品項
}
```

### 計算總額邏輯
```javascript
const total = cart.reduce((sum, item) => sum + (item.price * item.quantity), 0);
```

---

## 🔧 常見問題

### Q1: npm install 失敗怎麼辦？
**A**: 確認已安裝 Node.js (>= 18.0.0)
```bash
node -v  # 檢查版本
npm -v   # 檢查 npm 版本
```

### Q2: 無法啟動開發伺服器？
**A**: 確認端口 5173 未被佔用
```bash
lsof -i :5173        # macOS/Linux
netstat -ano | findstr :5173  # Windows
```

### Q3: 畫面沒有反應？
**A**: 打開瀏覽器開發者工具 (F12) 查看 Console 錯誤訊息

---

## 📚 深入學習

- **README.md** - 完整專案說明與功能列表
- **LOGIC_FLOW.md** - 詳細邏輯流程與 JavaScript 方法解析
- **App.jsx** - 查看完整原始碼與註解

---

## 🎨 自訂修改建議

### 修改菜單項目
編輯 `App.jsx` 中的 `menu` 陣列：
```javascript
const menu = [
  { id: 1, name: '你的品項', price: 100 },
  // 新增更多項目...
];
```

### 修改樣式
編輯 `App.css`：
```css
button {
  background-color: #你的顏色;
}
```

---

## ✅ 檢查清單

啟動前確認：
- [ ] 已安裝 Node.js
- [ ] 已執行 `npm install`
- [ ] 端口 5173 可用
- [ ] 瀏覽器版本較新（支援 ES6+）

功能確認：
- [ ] 可加入品項到購物車
- [ ] 可增減數量
- [ ] 減至 0 時自動移除
- [ ] 總金額計算正確
- [ ] 送出訂單後清空購物車

---

**🎉 祝您使用順利！**

有任何問題，請查看 `LOGIC_FLOW.md` 獲取詳細說明。
