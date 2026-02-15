# 極簡店內點餐系統 (Simple POS System)

一個使用 React + Vite 開發的極簡點餐系統原型。

## ✨ 功能特點

- ✅ 菜單展示（使用 HTML 表格）
- ✅ 加入購物車（自動判斷新增或增量）
- ✅ 數量增減（+ / - 按鈕）
- ✅ 自動計算小計與總金額
- ✅ 送出訂單並清空購物車
- ✅ 極簡設計，無複雜動畫與圖標

## 🚀 快速開始

### 1. 安裝依賴
```bash
cd /Users/pc/simple-pos-system
npm install
```

### 2. 啟動開發伺服器
```bash
npm run dev
```

應用將在 `http://localhost:5173` 啟動

### 3. 構建生產版本
```bash
npm run build
```

## 📂 專案結構

```
simple-pos-system/
├── index.html          # HTML 入口
├── main.jsx           # React 入口
├── App.jsx            # 主應用組件
├── App.css            # 基礎樣式
├── package.json       # 依賴配置
├── vite.config.js     # Vite 配置
└── README.md          # 說明文件
```

## 🔑 核心邏輯

### 資料結構

**菜單 (Menu)**
```javascript
const menu = [
  { id: 1, name: '招牌牛排', price: 380 },
  { id: 2, name: '炸雞排', price: 180 },
  // ...
];
```

**購物車 (Cart)**
```javascript
const [cart, setCart] = useState([
  { id: 1, name: '招牌牛排', price: 380, quantity: 2 }
]);
```

### 關鍵功能實作

#### 1. 加入購物車
```javascript
const addToCart = (product) => {
  const existingItem = cart.find(item => item.id === product.id);

  if (existingItem) {
    // 已存在，數量 +1
    setCart(cart.map(item =>
      item.id === product.id
        ? { ...item, quantity: item.quantity + 1 }
        : item
    ));
  } else {
    // 新增品項
    setCart([...cart, { ...product, quantity: 1 }]);
  }
};
```

#### 2. 數量減少（減至 0 時移除）
```javascript
const decreaseQuantity = (id) => {
  const item = cart.find(item => item.id === id);

  if (item.quantity === 1) {
    // 數量為 1 時，移除項目
    setCart(cart.filter(item => item.id !== id));
  } else {
    // 數量 -1
    setCart(cart.map(item =>
      item.id === id
        ? { ...item, quantity: item.quantity - 1 }
        : item
    ));
  }
};
```

#### 3. 計算總金額
```javascript
const calculateTotal = () => {
  return cart.reduce((sum, item) => sum + (item.price * item.quantity), 0);
};
```

#### 4. 送出訂單
```javascript
const submitOrder = () => {
  const total = calculateTotal();
  alert(`訂單已送出！\n總金額：$${total}`);
  setCart([]); // 清空購物車
};
```

## 🎯 使用流程

1. **瀏覽菜單** - 左側顯示所有可點餐品項與價格
2. **點擊「加入」** - 將品項加入右側購物車
3. **調整數量** - 使用 `+` / `-` 按鈕增減數量
4. **查看總額** - 購物車底部自動顯示總金額
5. **送出訂單** - 點擊「送出訂單」按鈕完成點餐

## 📋 測試範例

### 測試案例 1：新增品項
1. 點擊「招牌牛排」旁的「加入」按鈕
2. 購物車應顯示：招牌牛排 × 1，小計 $380

### 測試案例 2：增加數量
1. 點擊「招牌牛排」的「+」按鈕
2. 數量變為 2，小計變為 $760

### 測試案例 3：減少至移除
1. 點擊「招牌牛排」的「-」按鈕至數量為 1
2. 再次點擊「-」按鈕
3. 該品項應從購物車移除

### 測試案例 4：計算總額
1. 加入「招牌牛排」× 2 ($760)
2. 加入「可樂」× 3 ($150)
3. 總金額應顯示 $910

### 測試案例 5：送出訂單
1. 點擊「送出訂單」按鈕
2. 應彈出 Alert：「訂單已送出！總金額：$910」
3. 購物車應清空，顯示「購物車是空的」

## 🛠 技術棧

- **框架**: React 18
- **構建工具**: Vite 5
- **語言**: JavaScript (JSX)
- **樣式**: 原生 CSS

## 📝 待擴展功能（可選）

如需進階功能，可考慮以下擴展：

- [ ] 訂單歷史記錄
- [ ] 菜單分類（主餐、飲料、甜點）
- [ ] 搜尋與篩選功能
- [ ] 列印訂單功能
- [ ] 後端整合（API）
- [ ] 付款方式選擇

## 📄 授權

本專案為教學範例，可自由使用與修改。
