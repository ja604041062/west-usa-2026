/* ==========================================================================
   美西自駕 2026 —— 主程式
   ========================================================================== */

(function () {
  'use strict';

  var POINTS = window.TRIP_POINTS.points;

  // -------------------------------------------------------------- 地圖底圖

  // 淡色標準地圖原本用 CARTO Positron，這段期間 CARTO 改了免費方案的
  // 政策，圖磚變成整片「API KEY REQUIRED」浮水印。換成 Esri 的淡灰底圖
  // ——跟下面的衛星圖同一家服務，已知不需要金鑰。Esri 這個風格是兩層
  // 疊起來的：Light_Gray_Base 只有底色沒有文字，Light_Gray_Reference
  // 是疊在上面、透明背景的地名層，兩層都要有才等同原本 CARTO 的效果。
  var basemaps = {
    light: L.layerGroup([
      L.tileLayer(
        'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}',
        { attribution: 'Tiles &copy; Esri', maxZoom: 16 }
      ),
      L.tileLayer(
        'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Reference/MapServer/tile/{z}/{y}/{x}',
        { attribution: 'Tiles &copy; Esri', maxZoom: 16 }
      )
    ]),
    satellite: L.tileLayer(
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      {
        attribution: 'Tiles &copy; Esri',
        maxZoom: 19
      }
    )
  };

  var map = L.map('map', {
    // 縮放控制項移到左下角，左上角留給網站標題（底圖切換鈕也做在標題
    // 那個區塊裡 —— 右上角會被面板打開時蓋住，不適合放常駐控制項）
    zoomControl: false,
    layers: [basemaps.light]
  });

  L.control.zoom({ position: 'bottomleft' }).addTo(map);

  // 底圖切換：純粹換圖層，從不呼叫 setView，中心點與縮放層級
  // 自然不會被動到，不需要額外記錄或還原視野。
  var basemapButtons = document.querySelectorAll('.basemap-toggle__btn');
  var activeBasemapKey = 'light';

  basemapButtons.forEach(function (btn) {
    btn.addEventListener('click', function () {
      var key = btn.dataset.basemap;
      if (key === activeBasemapKey) return;

      map.removeLayer(basemaps[activeBasemapKey]);
      map.addLayer(basemaps[key]);
      activeBasemapKey = key;

      basemapButtons.forEach(function (b) {
        b.classList.toggle('is-active', b === btn);
      });
    });
  });

  // ---------------------------------------------------------------- 路線

  // 由 scripts/build-route.ps1 產生，只涵蓋 inRoute: true 的地點
  // （Napa Valley 不在其中 —— 自駕主軸不延伸過去）。
  //
  // 路線一開始不畫滿 —— 開場封面的轉場動畫要把它從空座標逐步畫到完整，
  // 所以這裡只建立圖層本身，實際座標由下方「開場封面與轉場動畫」那節
  // 的 setRouteProgress() 填入。
  var routeCoordsFull = (window.TRIP_ROUTE && window.TRIP_ROUTE.coordinates) || [];
  var routeLine = routeCoordsFull.length
    ? L.polyline([], {
        color: '#2563eb',
        weight: 4,
        opacity: 0.85,
        lineJoin: 'round'
      }).addTo(map)
    : null;

  // 找出 latlng 在路線座標序列中最接近的一點，回傳它在整條路線的進度
  // （0 = 起點 LA，1 = 終點 SF）。給不在路線上的標記（Napa Valley）用
  // 同一套邏輯也能得到一個合理的彈出時機，不需要特殊處理。
  function nearestRouteProgress(coords, latlng) {
    var bestIndex = 0;
    var bestDist = Infinity;
    for (var i = 0; i < coords.length; i++) {
      var dLat = coords[i][0] - latlng[0];
      var dLng = coords[i][1] - latlng[1];
      var dist = dLat * dLat + dLng * dLng;
      if (dist < bestDist) {
        bestDist = dist;
        bestIndex = i;
      }
    }
    return coords.length > 1 ? bestIndex / (coords.length - 1) : 0;
  }

  // ---------------------------------------------------------------- 標記

  // 編號只給「在自駕路線上且顯示標記」的地點。路線外的景點（Napa Valley）
  // 刻意不編號 —— 編號代表行程順序，給它一個號碼會讓人以為它是自駕的一站。
  function buildMarkerIcon(point, stopNumber) {
    var isStop = point.inRoute;
    var modifier = isStop ? 'trip-marker--stop' : 'trip-marker--offroute';
    var label = isStop ? String(stopNumber) : '';
    var size = isStop ? 28 : 22;

    return L.divIcon({
      className: 'trip-marker ' + modifier,
      html: '<div class="trip-marker__dot">' + label + '</div>',
      iconSize: [size, size],
      iconAnchor: [size / 2, size / 2]
    });
  }

  var markers = [];
  var stopNumber = 0;

  POINTS.forEach(function (point) {
    if (!point.showMarker) return;

    if (point.inRoute) stopNumber += 1;

    var marker = L.marker(point.coords, {
      icon: buildMarkerIcon(point, stopNumber),
      title: point.name,
      riseOnHover: true
    });

    // 標籤預設在標記右側、垂直置中。少數彼此距離很近的地點（例如下羚羊谷
    // 與馬蹄灣，實際車程僅約 10 分鐘）在全景縮放層級下標記幾乎重疊，
    // 標籤會疊在一起看不清楚，這種情況由 points.js 的 labelOffset 個別覆寫，
    // 讓其中一個標籤往上、另一個往下錯開，不需要更動任何程式邏輯。
    var defaultLabelOffset = [point.inRoute ? 18 : 15, 0];
    marker.bindTooltip(point.name, {
      permanent: true,
      direction: 'right',
      offset: point.labelOffset || defaultLabelOffset,
      className: 'trip-label' + (point.inRoute ? '' : ' trip-label--offroute')
    });

    marker.on('click', function () { openPanel(point); });

    marker.addTo(map);
    marker.tripPoint = point;

    // 開場動畫要讓標記依路線進度依序彈出，這裡先算好每個標記的彈出時機
    // （0 = 起點附近，1 = 終點附近）。實際加上「待命」樣式要等 fitBounds
    // 設定好地圖視野之後——Leaflet 把 addLayer 的 onAdd／icon 建立動作
    // 延到 map.whenReady()，此時地圖還沒有視野、icon 元素還沒真的生出來，
    // 這裡呼叫 marker.getElement() 一定拿到 null。
    marker._revealAt = routeCoordsFull.length
      ? nearestRouteProgress(routeCoordsFull, point.coords)
      : 0;

    markers.push(marker);
  });

  // ---------------------------------------------------------------- 面板

  // 點任一標記（含不在自駕路線上的 Napa Valley）都走這條路徑，
  // 內容呈現上完全一視同仁 —— 路線上的特殊地位不代表照片瀏覽上的特殊地位。
  var panelEl = document.getElementById('panel');
  var panelTitleEl = panelEl.querySelector('.panel__title');
  var panelDateEl = panelEl.querySelector('.panel__date');
  var panelDescEl = panelEl.querySelector('.panel__description');
  var panelGridEl = panelEl.querySelector('.panel__grid');
  var panelScrollEl = panelEl.querySelector('.panel__scroll');
  var panelCloseBtn = panelEl.querySelector('.panel__close');
  var panelPrevBtn = panelEl.querySelector('.panel__stepper-prev');
  var panelNextBtn = panelEl.querySelector('.panel__stepper-next');

  // 上一站／下一站要在的清單，就是地圖上看得到標記的地點，順序照
  // points.js 陣列順序 —— 跟標記編號、初始視野用的是同一份順序，
  // 逛起來跟地圖上的行程順序一致（含 Napa Valley，它一樣是可以
  // 點開看照片的地點，只是不算在自駕路線上）。
  var stepPoints = POINTS.filter(function (p) { return p.showMarker; });
  var currentPanelPoint = null;

  // 文字欄位為空時整個隱藏，而不是留一段空白 —— 現階段所有 description
  // 都是空的，這條路徑要能撐住「純照片牆」的樣子。
  function setOptionalText(el, text) {
    if (text) {
      el.hidden = false;
      el.textContent = text;
    } else {
      el.hidden = true;
      el.textContent = '';
    }
  }

  // 7.4 -> "0:07"，面板縮圖上的時長標籤用。
  function formatDuration(seconds) {
    var total = Math.round(seconds || 0);
    var m = Math.floor(total / 60);
    var s = total % 60;
    return m + ':' + (s < 10 ? '0' : '') + s;
  }

  function renderPhotoGrid(pointId, pointName) {
    panelGridEl.innerHTML = '';
    var photos = (window.TRIP_PHOTOS && window.TRIP_PHOTOS[pointId]) || [];

    // 燈箱要能在同一個地點的照片／影片之間左右翻頁，所以把這個地點
    // 目前的清單記在面板層級 —— 點哪一項，燈箱就從哪個 index 開始。
    lightboxPhotos = photos;
    lightboxPointName = pointName;

    photos.forEach(function (photo, index) {
      var isVideo = photo.type === 'video';

      // 每一項（照片或影片）都包一層 <button>：影片需要疊播放鍵和
      // 時長標籤，照片沒有疊加內容但用同一種結構，DOM 形狀一致、
      // 版面計算（aspect-ratio 佔位）不用分兩套邏輯。
      var wrap = document.createElement('button');
      wrap.type = 'button';
      wrap.className = 'panel__thumb-wrap';
      // 縮圖還沒載入前就先用原始尺寸的長寬比佔好版面空間，
      // 照片／影片陸續進來時面板不會跳動。
      wrap.style.aspectRatio = photo.w + ' / ' + photo.h;
      wrap.addEventListener('click', function () { openLightbox(index); });

      var img = document.createElement('img');
      img.className = 'panel__thumb';
      img.src = photo.thumb;
      img.alt = pointName + (isVideo ? ' 影片 ' : ' 照片 ') + (index + 1);
      img.loading = 'lazy';
      wrap.appendChild(img);

      if (isVideo) {
        var play = document.createElement('span');
        play.className = 'panel__thumb-play';
        play.setAttribute('aria-hidden', 'true');
        wrap.appendChild(play);

        var badge = document.createElement('span');
        badge.className = 'panel__thumb-duration';
        badge.textContent = formatDuration(photo.duration);
        wrap.appendChild(badge);
      }

      panelGridEl.appendChild(wrap);
    });
  }

  // 讓地圖上的標記跟著面板同步「目前選到的是哪一點」：放大 + 脈動
  // 光暈標出來。面板切換／關閉時記得把上一個標記的醒目樣式收掉，
  // 不然會同時有兩個標記在閃。
  var activeMarker = null;

  function setActiveMarker(point) {
    if (activeMarker) {
      var prevEl = activeMarker.getElement();
      if (prevEl) L.DomUtil.removeClass(prevEl, 'trip-marker--active');
    }
    activeMarker = point
      ? markers.find(function (m) { return m.tripPoint.id === point.id; })
      : null;
    if (activeMarker) {
      var el = activeMarker.getElement();
      if (el) L.DomUtil.addClass(el, 'trip-marker--active');
    }
  }

  function openPanel(point) {
    currentPanelPoint = point;
    setActiveMarker(point);

    panelTitleEl.textContent = point.name;
    setOptionalText(panelDateEl, point.date);
    setOptionalText(panelDescEl, point.description);
    renderPhotoGrid(point.id, point.name);

    var idx = stepPoints.indexOf(point);
    if (idx !== -1) {
      // 按鈕上直接顯示目的地名稱（不是死板的「上一站」四個字），
      // 使用者不用先點下去才知道要去哪 —— 首尾繞回跟燈箱的邏輯一致。
      var prevPoint = stepPoints[(idx - 1 + stepPoints.length) % stepPoints.length];
      var nextPoint = stepPoints[(idx + 1) % stepPoints.length];
      panelPrevBtn.textContent = '‹ ' + prevPoint.name;
      panelNextBtn.textContent = nextPoint.name + ' ›';
      panelPrevBtn.hidden = false;
      panelNextBtn.hidden = false;
    } else {
      // 理論上不會發生（面板只會被地圖上的標記打開，一定在
      // stepPoints 裡），保留這條路徑純粹是防禦性寫法。
      panelPrevBtn.hidden = true;
      panelNextBtn.hidden = true;
    }

    panelScrollEl.scrollTop = 0;
    panelEl.classList.add('is-open');
  }

  function stepPanel(direction) {
    if (!currentPanelPoint) return;
    var idx = stepPoints.indexOf(currentPanelPoint);
    if (idx === -1) return;
    var target = stepPoints[(idx + direction + stepPoints.length) % stepPoints.length];
    openPanel(target);
  }

  panelPrevBtn.addEventListener('click', function () { stepPanel(-1); });
  panelNextBtn.addEventListener('click', function () { stepPanel(1); });

  function closePanel() {
    panelEl.classList.remove('is-open');
    setActiveMarker(null);
    currentPanelPoint = null;
  }

  panelCloseBtn.addEventListener('click', closePanel);

  // ---------------------------------------------------------------- 燈箱

  // 面板負責「這個地點有哪些照片」的概覽（縮圖），燈箱負責「這一張長
  // 什麼樣」的細看（大圖）。大圖只在真的點開某一張時才載入。
  var lightboxEl = document.getElementById('lightbox');
  var lightboxImg = lightboxEl.querySelector('.lightbox__image');
  var lightboxVideo = lightboxEl.querySelector('.lightbox__video');
  var lightboxCounter = lightboxEl.querySelector('.lightbox__counter');
  var lightboxCloseBtn = lightboxEl.querySelector('.lightbox__close');
  var lightboxPrevBtn = lightboxEl.querySelector('.lightbox__nav--prev');
  var lightboxNextBtn = lightboxEl.querySelector('.lightbox__nav--next');

  var lightboxPhotos = [];
  var lightboxPointName = '';
  var lightboxIndex = 0;

  // 停掉影片播放並釋放它的來源 —— 切到下一項或關閉燈箱時都要呼叫，
  // 不然背景會繼續播放聲音、或瀏覽器繼續緩衝看不見的影片。
  function stopLightboxVideo() {
    lightboxVideo.pause();
    lightboxVideo.removeAttribute('src');
    lightboxVideo.load();
  }

  function renderLightboxItem() {
    var item = lightboxPhotos[lightboxIndex];
    var isVideo = item.type === 'video';

    stopLightboxVideo();

    if (isVideo) {
      lightboxImg.hidden = true;
      lightboxVideo.hidden = false;
      lightboxVideo.poster = item.thumb;
      lightboxVideo.src = item.video;
    } else {
      lightboxVideo.hidden = true;
      lightboxImg.hidden = false;
      lightboxImg.src = item.large;
      lightboxImg.alt = lightboxPointName + ' 照片 ' + (lightboxIndex + 1);
    }

    lightboxCounter.textContent = (lightboxIndex + 1) + ' / ' + lightboxPhotos.length;
  }

  function openLightbox(index) {
    lightboxIndex = index;
    renderLightboxItem();
    lightboxEl.classList.add('is-open');
  }

  function closeLightbox() {
    stopLightboxVideo();
    lightboxEl.classList.remove('is-open');
  }

  // 首張往前、末張往後都直接繞到另一端，而不是停在原地或讓按鈕失效 ——
  // 使用者連續按下一張時最不會撞到邊界的行為。照片、影片混排在同一個
  // 清單裡，翻頁邏輯不用區分正在看的是哪一種。
  function showPrevPhoto() {
    lightboxIndex = (lightboxIndex - 1 + lightboxPhotos.length) % lightboxPhotos.length;
    renderLightboxItem();
  }

  function showNextPhoto() {
    lightboxIndex = (lightboxIndex + 1) % lightboxPhotos.length;
    renderLightboxItem();
  }

  lightboxCloseBtn.addEventListener('click', closeLightbox);
  lightboxPrevBtn.addEventListener('click', showPrevPhoto);
  lightboxNextBtn.addEventListener('click', showNextPhoto);

  // 點暗色遮罩本身（不是圖片或按鈕）才關閉 —— e.target 只有在點擊落在
  // 遮罩自己身上時才會等於 lightboxEl，點在子元素上一律不觸發。
  lightboxEl.addEventListener('click', function (e) {
    if (e.target === lightboxEl) closeLightbox();
  });

  document.addEventListener('keydown', function (e) {
    if (!lightboxEl.classList.contains('is-open')) return;
    if (e.key === 'Escape') closeLightbox();
    else if (e.key === 'ArrowLeft') showPrevPhoto();
    else if (e.key === 'ArrowRight') showNextPhoto();
  });

  // ------------------------------------------------------------ 初始視野

  // 框住所有「看得到的」標記，含不在路線上的 Napa Valley。
  var bounds = L.latLngBounds(
    POINTS.filter(function (p) { return p.showMarker; })
          .map(function (p) { return p.coords; })
  );

  // 左上角有網站標題 + 底圖切換鈕這塊常駐 UI，用對稱 padding 算出來的
  // 縮放層級會讓角落的標記（目前是 Napa Valley）被這塊 UI 蓋住。
  // 數值對應標題區塊實際量到的尺寸（約 225×143px）加一點緩衝，
  // 不是憑感覺試出來的數字 —— 這樣視窗尺寸改變、標題內容改變時，
  // 這組數字還站得住腳。右下角沒有常駐 UI，維持一般的留白量即可。
  var headerRect = document.querySelector('.site-header').getBoundingClientRect();
  map.fitBounds(bounds, {
    paddingTopLeft: [headerRect.right + 15, headerRect.bottom + 15],
    paddingBottomRight: [70, 70]
  });

  // ---------------------------------------------------------- 開場封面與轉場動畫

  // 封面每次打開網站都會出現（不記錄「看過了」的狀態），地圖在封面顯示
  // 的同時就已經在背景初始化完成（上面所有程式碼都不是等封面關閉才
  // 執行的）——點「開始」時要做的只是把封面淡出、接上路線動畫。
  var coverEl = document.getElementById('cover');
  var coverStartBtn = coverEl.querySelector('.cover__start');
  var skipHintEl = document.getElementById('route-skip-hint');

  var ROUTE_ANIMATION_MS = 4500; // 封面淡出另計約 350ms，合計約 5 秒
  var animationFrameId = null;
  var animationActive = false;

  // 地圖視野（fitBounds）已經在上面設定完成，這裡地圖已經是 _loaded 狀態，
  // 每個標記的 icon 元素才真的存在，這時加上「待命」樣式才有效。
  markers.forEach(function (marker) {
    var el = marker.getElement();
    if (el) L.DomUtil.addClass(el, 'trip-marker--pending');
  });

  function setRouteProgress(t) {
    if (routeLine) {
      var count = Math.max(2, Math.round(routeCoordsFull.length * t));
      routeLine.setLatLngs(routeCoordsFull.slice(0, count));
    }
    markers.forEach(function (marker) {
      if (t < marker._revealAt) return;
      var el = marker.getElement();
      if (el) L.DomUtil.removeClass(el, 'trip-marker--pending');
    });
  }

  function onSkipKeydown(e) {
    if (e.key === 'Escape') finishRouteAnimation();
  }

  // 逃生閥：動畫播放中點擊畫面任一處或按 Esc 直接跳到最終狀態。這是
  // 必要功能，不是錦上添花——訪客可能在車上用手機重複點開連結，被迫
  // 每次看完整段動畫會是最容易被抱怨的地方。
  //
  // finishRouteAnimation 本身不吃參數，click 事件物件直接傳進來也無妨，
  // 所以拿它自己當 click 監聽器用，不用再包一層轉發用的函式。
  function finishRouteAnimation() {
    if (!animationActive) return;
    animationActive = false;
    if (animationFrameId !== null) cancelAnimationFrame(animationFrameId);
    animationFrameId = null;
    setRouteProgress(1);
    skipHintEl.hidden = true;
    document.removeEventListener('keydown', onSkipKeydown);
    document.removeEventListener('click', finishRouteAnimation);
  }

  function startRouteAnimation() {
    if (!routeCoordsFull.length) return;
    animationActive = true;
    skipHintEl.hidden = false;
    var startTime = null;

    function step(timestamp) {
      if (!animationActive) return;
      if (startTime === null) startTime = timestamp;
      var t = Math.min(1, (timestamp - startTime) / ROUTE_ANIMATION_MS);
      setRouteProgress(t);
      if (t >= 1) {
        finishRouteAnimation();
        return;
      }
      animationFrameId = requestAnimationFrame(step);
    }

    animationFrameId = requestAnimationFrame(step);
    document.addEventListener('keydown', onSkipKeydown);
    document.addEventListener('click', finishRouteAnimation);
  }

  coverStartBtn.addEventListener('click', function () {
    coverEl.classList.add('is-leaving');
  });

  // 封面淡出完全結束才開始畫線（而不是同時開始）——但因為地圖早就
  // 預載好了，淡出後露出的不是空畫面，是已經就緒的靜態全景地圖，
  // 銜接起來不會有空白停頓的觀感。
  coverEl.addEventListener('transitionend', function (e) {
    if (e.target !== coverEl || e.propertyName !== 'opacity') return;
    coverEl.hidden = true;
    startRouteAnimation();
  });

  // 暴露給後續票使用
  window.TRIP_APP = {
    map: map,
    markers: markers,
    basemaps: basemaps,
    openPanel: openPanel,
    closePanel: closePanel,
    openLightbox: openLightbox,
    closeLightbox: closeLightbox
  };
})();
