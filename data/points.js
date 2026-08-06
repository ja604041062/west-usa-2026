// 地點定義檔 —— 這是整個網站唯一需要手動編輯的檔案
//
// 陣列順序 = 行程順序 = 路線計算的途經順序。
//
// showMarker 與 inRoute 是兩個各自獨立的開關：
//   showMarker: true,  inRoute: true   → 自駕路線上的編號停留點
//   showMarker: false, inRoute: true   → 只用來校正路線、地圖上看不到
//   showMarker: true,  inRoute: false  → 有照片但不在自駕路線上（藍線不會延伸過去）
//   showMarker: false, inRoute: false  → 停用中，資料留著但完全不出現
//
// srcFolder 對應到來源照片資料夾名稱，可以自由命名（中文、空格、編號前綴都可以）。
// description 留空時，面板不會顯示文字區塊；想寫遊記就直接填在這裡，存檔重新整理即可。
// date 留空時，面板不會顯示日期。

window.TRIP_POINTS = {
  "photoSourceRoot": "../Soap美西",

  "points": [
    {
      "id": "los-angeles",
      "srcFolder": "10.Los Angels",
      "name": "洛杉磯",
      "coords": [34.0522, -118.2437],
      "date": "",
      "description": "",
      "showMarker": true,
      "inRoute": true
    },
    {
      "id": "joshua-tree",
      "srcFolder": "1.joshua tree",
      "name": "Joshua Tree",
      "coords": [33.8734, -115.9010],
      "date": "",
      "description": "",
      "showMarker": true,
      "inRoute": true
    },
    {
      "id": "grand-canyon",
      "srcFolder": "2.Grant Canyon",
      "name": "大峽谷",
      "coords": [36.0544, -112.1401],
      "date": "",
      "description": "",
      "showMarker": true,
      "inRoute": true
    },
    {
      "id": "lower-antelope-canyon",
      "srcFolder": "3.lower antelope canyon",
      "name": "下羚羊谷",
      "coords": [36.8619, -111.4239],
      "date": "",
      "description": "",
      "showMarker": true,
      "inRoute": true
    },
    {
      "id": "horseshoe-bend",
      "srcFolder": "4.馬蹄灣",
      "name": "馬蹄灣",
      "coords": [36.8791, -111.5104],
      "date": "",
      "description": "",
      "showMarker": true,
      "inRoute": true
    },
    {
      "id": "las-vegas",
      "srcFolder": "5.Las Vegas",
      "name": "拉斯維加斯",
      "coords": [36.1699, -115.1398],
      "date": "",
      "description": "",
      "showMarker": true,
      "inRoute": true
    },
    {
      // 途經點：把路線壓回實際走的 I-15 南下路徑
      "id": "baker",
      "srcFolder": null,
      "name": "Baker, CA",
      "coords": [35.2686, -116.0764],
      "date": "",
      "description": "",
      "showMarker": false,
      "inRoute": true
    },
    {
      // 途經點：把路線壓回 CA-58 經 Tehachapi 的路徑
      "id": "bealville",
      "srcFolder": null,
      "name": "Bealville, CA",
      "coords": [35.2139, -118.5589],
      "date": "",
      "description": "",
      "showMarker": false,
      "inRoute": true
    },
    {
      "id": "yosemite",
      "srcFolder": "6.Yosemite",
      "name": "優勝美地",
      "coords": [37.7456, -119.5936],
      "date": "",
      "description": "",
      "showMarker": true,
      "inRoute": true
    },
    {
      "id": "enroute-yosemite-sf",
      "srcFolder": "7.yosemite to SFO沿途",
      "name": "優勝美地→舊金山 沿途",
      "coords": [37.0058, -121.5683],
      "date": "",
      "description": "",
      "showMarker": true,
      "inRoute": true
    },
    {
      "id": "san-francisco",
      "srcFolder": "8.SFO",
      "name": "舊金山",
      "coords": [37.8087, -122.4098],
      "date": "",
      "description": "",
      "showMarker": true,
      "inRoute": true
    },
    {
      // 不在自駕路線上：有標記、有照片，但藍線不延伸過去
      "id": "napa-valley",
      "srcFolder": "9. Napa Valley",
      "name": "Napa Valley",
      "coords": [38.2975, -122.2869],
      "date": "",
      "description": "",
      "showMarker": true,
      "inRoute": false
    }
  ]
};
