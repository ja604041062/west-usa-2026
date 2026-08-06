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

    marker.addTo(map);
    marker.tripPoint = point;
    markers.push(marker);
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
    basemaps: basemaps
  };
})();
