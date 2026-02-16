// 批量更新菜單配置全局選項
const fs = require('fs');

// 讀取 index.html
let html = fs.readFileSync('index.html', 'utf8');

// 為所有菜單項目添加 appliedOptionIds
// 查找並替換菜單數據結構
html = html.replace(
    /(\s+id: \d+,\s+name: '[^']+',[\s\S]*?category: '(?:highlight|fried|bento)',[\s\S]*?(?:description: '[^']*',))(\s+options: \[)/g,
    '$1\n                    // 使用全局選項庫\n                    appliedOptionIds: [1, 2, 3, 4, 5, 6],$2'
);

fs.writeFileSync('index.html', html);
console.log('✅ 菜單已更新！');
