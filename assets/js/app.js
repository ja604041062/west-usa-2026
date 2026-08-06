/* ==========================================================================
   美西自駕 2026 —— 主程式
   ========================================================================== */

(function () {
  'use strict';

  var POINTS = window.TRIP_POINTS.points;

  // -------------------------------------------------------------- 地圖底圖

  var basemaps = {
    light: L.tileLayer(
      'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
      {
        attribution: '&copy; OpenStreetMap contributors &copy; CARTO',
        subdomains: 'abcd',
        maxZoom: 19
      }
    ),
    satellite: L.tileLayer(
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      {
        attribution: 'Tiles &copy; Esri',
        maxZoom: 19
      }
    )
  };

  var map = L.map('map', {
    // 縮放控制項移到左下角，把左上角讓給網站標題，右上角讓給底圖切換鈕
    zoomControl: false,
    layers: [basemaps.light]
  });

  L.control.zoom({ position: 'bottomleft' }).addTo(map);

  // ---------------------------------------------------------------- 路線

  // 由 scripts/build-route.ps1 產生，只涵蓋 inRoute: true 的地點
  // （Napa Valley 不在其中 —— 自駕主軸不延伸過去）。
  if (window.TRIP_ROUTE) {
    L.polyline(window.TRIP_ROUTE.coordinates, {
      color: '#2563eb',
      weight: 4,
      opacity: 0.85,
      lineJoin: 'round'
    }).addTo(map);
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

    marker.bindTooltip(point.name, {
      permanent: true,
      direction: 'right',
      offset: [point.inRoute ? 18 : 15, 0],
      className: 'trip-label' + (point.inRoute ? '' : ' trip-label--offroute')
    });

    marker.on('click', function () { openPanel(point); });

    marker.addTo(map);
    marker.tripPoint = point;
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

  function renderPhotoGrid(pointId, pointName) {
    panelGridEl.innerHTML = '';
    var photos = (window.TRIP_PHOTOS && window.TRIP_PHOTOS[pointId]) || [];

    // 燈箱要能在同一個地點的照片之間左右翻頁，所以把這個地點目前的
    // 照片清單記在面板層級 —— 點哪張縮圖，燈箱就從哪個 index 開始。
    lightboxPhotos = photos;
    lightboxPointName = pointName;

    photos.forEach(function (photo, index) {
      var img = document.createElement('img');
      img.className = 'panel__thumb';
      img.src = photo.thumb;
      img.alt = pointName + ' 照片 ' + (index + 1);
      img.loading = 'lazy';
      // 縮圖還沒載入前就先用原始尺寸的長寬比佔好版面空間，
      // 照片陸續進來時面板不會跳動。
      img.style.aspectRatio = photo.w + ' / ' + photo.h;
      img.addEventListener('click', function () { openLightbox(index); });
      panelGridEl.appendChild(img);
    });
  }

  function openPanel(point) {
    panelTitleEl.textContent = point.name;
    setOptionalText(panelDateEl, point.date);
    setOptionalText(panelDescEl, point.description);
    renderPhotoGrid(point.id, point.name);

    panelScrollEl.scrollTop = 0;
    panelEl.classList.add('is-open');
  }

  function closePanel() {
    panelEl.classList.remove('is-open');
  }

  panelCloseBtn.addEventListener('click', closePanel);

  // ---------------------------------------------------------------- 燈箱

  // 面板負責「這個地點有哪些照片」的概覽（縮圖），燈箱負責「這一張長
  // 什麼樣」的細看（大圖）。大圖只在真的點開某一張時才載入。
  var lightboxEl = document.getElementById('lightbox');
  var lightboxImg = lightboxEl.querySelector('.lightbox__image');
  var lightboxCounter = lightboxEl.querySelector('.lightbox__counter');
  var lightboxCloseBtn = lightboxEl.querySelector('.lightbox__close');
  var lightboxPrevBtn = lightboxEl.querySelector('.lightbox__nav--prev');
  var lightboxNextBtn = lightboxEl.querySelector('.lightbox__nav--next');

  var lightboxPhotos = [];
  var lightboxPointName = '';
  var lightboxIndex = 0;

  function renderLightboxImage() {
    var photo = lightboxPhotos[lightboxIndex];
    lightboxImg.src = photo.large;
    lightboxImg.alt = lightboxPointName + ' 照片 ' + (lightboxIndex + 1);
    lightboxCounter.textContent = (lightboxIndex + 1) + ' / ' + lightboxPhotos.length;
  }

  function openLightbox(index) {
    lightboxIndex = index;
    renderLightboxImage();
    lightboxEl.classList.add('is-open');
  }

  function closeLightbox() {
    lightboxEl.classList.remove('is-open');
  }

  // 首張往前、末張往後都直接繞到另一端，而不是停在原地或讓按鈕失效 ——
  // 使用者連續按下一張時最不會撞到邊界的行為。
  function showPrevPhoto() {
    lightboxIndex = (lightboxIndex - 1 + lightboxPhotos.length) % lightboxPhotos.length;
    renderLightboxImage();
  }

  function showNextPhoto() {
    lightboxIndex = (lightboxIndex + 1) % lightboxPhotos.length;
    renderLightboxImage();
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

  map.fitBounds(bounds, { padding: [70, 70] });

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
