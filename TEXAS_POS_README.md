# 🤠 德州店內點餐系統 MVP

## 📋 系統概述

這是一個極簡的德州點餐系統，支援 **8.25% 銷售稅**和**自定義價格**功能。

**檔案位置**: `/Users/pc/simple-pos-system/texas-pos.html`

---

## 🎯 核心功能

### 1. 固定稅率設定 ✅
- **德州銷售稅**: 8.25%
- 代碼中的常數：`const TEXAS_TAX_RATE = 0.0825;`

### 2. 自定義價格（Open Price）✅
- 購物車內每個品項都有 **可編輯的單價輸入框**
- 店員可隨時修改價格
- 系統即時重新計算總額

### 3. 金額計算公式 ✅

```javascript
// Subtotal = Σ(CustomPrice_i × Quantity_i)
const subtotal = cart.reduce((sum, item) =>
  sum + (item.customPrice * item.quantity), 0
);

// Tax = Subtotal × 0.0825
const tax = subtotal * 0.0825;

// Total = Subtotal + Tax
const total = subtotal + tax;
```

---

## 💡 系統運算流程圖

```
菜單品項
  ↓
[加入購物車]
  ↓
購物車品項 {
  name: "Texas Ribeye Steak",
  originalPrice: 38.00,
  customPrice: 38.00,  ← 可修改
  quantity: 2
}
  ↓
計算小計
Subtotal = $38.00 × 2 = $76.00
  ↓
計算稅金
Tax = $76.00 × 8.25% = $6.27
  ↓
計算總計
Total = $76.00 + $6.27 = $82.27
  ↓
[結帳]
  ↓
輸出訂單 JSON
```

---

## 🧪 測試範例

### 範例 1：基礎點餐
1. 點擊「Texas Ribeye Steak」的「加入」按鈕
2. 購物車顯示：
   - 品項：Texas Ribeye Steak
   - 單價：$38.00（可修改）
   - 數量：1
   - 小計：$38.00
3. 結帳區顯示：
   - Subtotal: $38.00
   - Tax (8.25%): $3.14
   - Total: $41.14

### 範例 2：自定義價格
1. 加入「Texas Ribeye Steak」× 2
2. **修改單價**：將 $38.00 改為 $35.00（今日特價）
3. 小計自動更新：$35.00 × 2 = $70.00
4. 結帳區即時更新：
   - Subtotal: $70.00
   - Tax (8.25%): $5.78
   - Total: $75.78

### 範例 3：混合訂單
1. 加入「Texas Ribeye Steak」× 2，單價 $38.00
2. 加入「BBQ Brisket」× 1，單價 $28.00
3. 加入「Sweet Tea」× 3，單價 $3.50
4. 計算結果：
   - Subtotal: $38×2 + $28×1 + $3.50×3 = $114.50
   - Tax: $114.50 × 8.25% = $9.45
   - Total: $123.95

---

## 🔧 核心代碼解析

### 1. 自定義價格輸入框

```jsx
<input
    type="number"
    className="price-input"
    value={item.customPrice}
    onChange={(e) => updateCustomPrice(item.id, e.target.value)}
    step="0.01"
    min="0"
/>
```

### 2. 更新自定義價格邏輯

```javascript
const updateCustomPrice = (id, newPrice) => {
    const price = parseFloat(newPrice);
    if (!isNaN(price) && price >= 0) {
        setCart(cart.map(item =>
            item.id === id
                ? { ...item, customPrice: price }
                : item
        ));
    }
};
```

### 3. 計算三大金額

```javascript
// Subtotal
const calculateSubtotal = () => {
    return cart.reduce((sum, item) => {
        return sum + (item.customPrice * item.quantity);
    }, 0);
};

// Tax
const calculateTax = () => {
    const subtotal = calculateSubtotal();
    return subtotal * TEXAS_TAX_RATE;  // 8.25%
};

// Total
const calculateTotal = () => {
    return calculateSubtotal() + calculateTax();
};
```

---

## 📊 結帳區顯示

```
┌─────────────────────────────────┐
│  Subtotal:            $114.50   │
│  Tax (8.25%):           $9.45   │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━   │
│  Total:               $123.95   │
└─────────────────────────────────┘
```

---

## 💾 訂單 JSON 輸出

點擊「結帳」後，Console 會輸出完整訂單：

```json
{
  "timestamp": "2026-02-13T21:45:00.000Z",
  "items": [
    {
      "id": 1,
      "name": "Texas Ribeye Steak",
      "originalPrice": 38.00,
      "customPrice": 35.00,
      "quantity": 2,
      "subtotal": 70.00
    },
    {
      "id": 2,
      "name": "BBQ Brisket",
      "originalPrice": 28.00,
      "customPrice": 28.00,
      "quantity": 1,
      "subtotal": 28.00
    }
  ],
  "subtotal": 98.00,
  "taxRate": 0.0825,
  "tax": 8.09,
  "total": 106.09
}
```

---

## 🎨 界面設計

### 極簡原則 ✅
- **純 HTML/CSS**：無 Tailwind，無複雜框架
- **清晰條列**：Subtotal, Tax, Total 一目了然
- **無裝飾**：專注於功能，無多餘視覺元素

### 佈局
```
┌────────────────────────────────────────────────┐
│         德州店內點餐系統 MVP                    │
├───────────────────┬────────────────────────────┤
│   菜單            │   購物車                   │
│                   │                            │
│  品項     原價    │  品項    單價   數量  小計 │
│  Steak   $38.00   │  Steak   [38]   [2]  $76  │
│  Brisket $28.00   │                            │
│  ...              │  Subtotal:        $76.00   │
│                   │  Tax (8.25%):      $6.27   │
│                   │  Total:           $82.27   │
│                   │  [結帳]                     │
└───────────────────┴────────────────────────────┘
```

---

## 🚀 使用方式

### 方式 1：直接開啟 HTML（已執行）
```bash
open /Users/pc/simple-pos-system/texas-pos.html
```

### 方式 2：複製到 CodeSandbox
1. 前往 [CodeSandbox.io](https://codesandbox.io/)
2. 建立新的 **Static** 專案
3. 將 `texas-pos.html` 的內容貼上
4. 立即預覽

### 方式 3：本地測試
直接用瀏覽器開啟 `texas-pos.html` 即可

---

## 🔍 驗證清單

### 功能驗證 ✅
- [ ] 可加入品項到購物車
- [ ] 可修改購物車內的單價
- [ ] 修改單價後小計即時更新
- [ ] 可增減數量（+1 / -1）
- [ ] Subtotal 正確計算
- [ ] Tax 正確計算（8.25%）
- [ ] Total 正確計算（Subtotal + Tax）
- [ ] 結帳後輸出 JSON 到 Console
- [ ] 結帳後購物車清空

### 金額驗證
**測試案例**：
- 品項：Texas Ribeye Steak × 2，單價 $38.00
- 預期 Subtotal: $76.00
- 預期 Tax: $76.00 × 0.0825 = $6.27
- 預期 Total: $82.27

---

## 💡 實作小提醒

### 自定義價格的使用場景

#### 1. 手動調整價格
```
店員：「這份牛排今天特價 $25」
操作：直接在單價輸入框改為 25.00
```

#### 2. 加選項目（未來擴展）
```
顧客：「我要加培根 +$3」
方式 1：直接改單價 $38 → $41
方式 2：未來可加入 Modifiers 功能
```

### 未來擴展方向
- [ ] 加料選項（Modifiers）
- [ ] 優惠折扣（Discounts）
- [ ] 小費功能（Tips）
- [ ] 分帳功能（Split Bill）
- [ ] 列印收據

---

## 📚 技術細節

### React Hooks 使用
```javascript
const [cart, setCart] = useState([]);  // 購物車狀態
```

### 數據結構
```javascript
// 購物車項目
{
  id: 1,
  name: "Texas Ribeye Steak",
  price: 38.00,           // 原始價格
  customPrice: 35.00,     // 自定義價格（可修改）
  quantity: 2
}
```

### 金額格式化
```javascript
amount.toFixed(2)  // 保留兩位小數：$38.00
```

---

## 🎉 完成檢查

✅ 稅率設定：8.25%
✅ 自定義價格：每個品項可修改
✅ 金額計算：Subtotal, Tax, Total
✅ 介面極簡：純 HTML/CSS
✅ 單一檔案：可複製到 CodeSandbox

---

**系統已就緒，請立即測試！**

按 **F12** 開啟 Console 查看詳細訂單 JSON。
