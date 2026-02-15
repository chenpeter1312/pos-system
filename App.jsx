import React, { useState } from 'react';
import './App.css';

function App() {
  // 菜單資料
  const menu = [
    { id: 1, name: '招牌牛排', price: 380 },
    { id: 2, name: '炸雞排', price: 180 },
    { id: 3, name: '義大利麵', price: 220 },
    { id: 4, name: '凱薩沙拉', price: 150 },
    { id: 5, name: '薯條', price: 80 },
    { id: 6, name: '可樂', price: 50 },
    { id: 7, name: '咖啡', price: 90 },
    { id: 8, name: '提拉米蘇', price: 120 }
  ];

  // 購物車狀態
  const [cart, setCart] = useState([]);

  // 加入購物車
  const addToCart = (product) => {
    const existingItem = cart.find(item => item.id === product.id);

    if (existingItem) {
      // 如果已存在，數量 +1
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

  // 增加數量
  const increaseQuantity = (id) => {
    setCart(cart.map(item =>
      item.id === id
        ? { ...item, quantity: item.quantity + 1 }
        : item
    ));
  };

  // 減少數量
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

  // 計算總金額
  const calculateTotal = () => {
    return cart.reduce((sum, item) => sum + (item.price * item.quantity), 0);
  };

  // 送出訂單
  const submitOrder = () => {
    const total = calculateTotal();
    alert(`訂單已送出！\n總金額：$${total}`);
    setCart([]); // 清空購物車
  };

  return (
    <div className="app">
      <h1>店內點餐系統</h1>

      <div className="container">
        {/* 左側：菜單 */}
        <div className="menu-section">
          <h2>菜單</h2>
          <table>
            <thead>
              <tr>
                <th>品項</th>
                <th>價格</th>
                <th>操作</th>
              </tr>
            </thead>
            <tbody>
              {menu.map(item => (
                <tr key={item.id}>
                  <td>{item.name}</td>
                  <td>${item.price}</td>
                  <td>
                    <button onClick={() => addToCart(item)}>加入</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        {/* 右側：購物車 */}
        <div className="cart-section">
          <h2>購物車</h2>

          {cart.length === 0 ? (
            <p>購物車是空的</p>
          ) : (
            <>
              <table>
                <thead>
                  <tr>
                    <th>品項</th>
                    <th>單價</th>
                    <th>數量</th>
                    <th>小計</th>
                  </tr>
                </thead>
                <tbody>
                  {cart.map(item => (
                    <tr key={item.id}>
                      <td>{item.name}</td>
                      <td>${item.price}</td>
                      <td>
                        <button onClick={() => decreaseQuantity(item.id)}>-</button>
                        <span className="quantity">{item.quantity}</span>
                        <button onClick={() => increaseQuantity(item.id)}>+</button>
                      </td>
                      <td>${item.price * item.quantity}</td>
                    </tr>
                  ))}
                </tbody>
              </table>

              <div className="total">
                <h3>總金額：${calculateTotal()}</h3>
              </div>

              <button className="submit-btn" onClick={submitOrder}>
                送出訂單
              </button>
            </>
          )}
        </div>
      </div>
    </div>
  );
}

export default App;
