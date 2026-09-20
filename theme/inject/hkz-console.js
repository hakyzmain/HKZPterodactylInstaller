(function () {
  'use strict';

  function cssVar(name, fallback) {
    var v = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
    return v || fallback;
  }

  function parseColor(input) {
    var c = document.createElement('canvas');
    c.width = c.height = 1;
    var ctx = c.getContext('2d');
    if (!ctx) return null;
    ctx.fillStyle = input;
    ctx.fillRect(0, 0, 1, 1);
    var d = ctx.getImageData(0, 0, 1, 1).data;
    return { r: d[0], g: d[1], b: d[2] };
  }

  function rgba(input, alpha) {
    var p = parseColor(input);
    if (!p) return input;
    return 'rgba(' + p.r + ',' + p.g + ',' + p.b + ',' + alpha + ')';
  }

  function patchChart(chart) {
    if (!chart || !chart.data || !chart.options) return;
    var accent2 = cssVar('--hkz-accent-2', '#22d3ee');
    var accent = cssVar('--hkz-accent', '#a855f7');
    var grid = cssVar('--hkz-border', 'rgba(148, 163, 184, 0.35)');
    var tick = cssVar('--hkz-text-dim', '#94a3b8');
    var warn = '#facc15';
    var multi = chart.data.datasets && chart.data.datasets.length > 1;

    if (chart.options.scales && chart.options.scales.y) {
      chart.options.scales.y.grid = chart.options.scales.y.grid || {};
      chart.options.scales.y.grid.color = grid;
      chart.options.scales.y.ticks = chart.options.scales.y.ticks || {};
      chart.options.scales.y.ticks.color = tick;
    }

    chart.data.datasets.forEach(function (ds, idx) {
      if (multi) {
        ds.borderColor = idx === 0 ? accent2 : warn;
        ds.backgroundColor = rgba(idx === 0 ? accent2 : warn, 0.42);
      } else {
        ds.borderColor = accent2;
        ds.backgroundColor = rgba(accent2, 0.42);
      }
    });

    chart.update('none');
  }

  function tintCharts() {
    var Chart = window.Chart;
    if (!Chart) return 0;
    var seen = {};
    var count = 0;

    function apply(ch) {
      if (!ch || !ch.id || seen[ch.id]) return;
      seen[ch.id] = 1;
      patchChart(ch);
      count++;
    }

    if (Chart.instances && typeof Chart.instances === 'object') {
      Object.keys(Chart.instances).forEach(function (key) {
        apply(Chart.instances[key]);
      });
    }

    document.querySelectorAll('[class*="chart_container"] canvas').forEach(function (canvas) {
      if (typeof Chart.getChart === 'function') apply(Chart.getChart(canvas));
    });

    return count;
  }

  function boot() {
    var tries = 0;
    var timer = setInterval(function () {
      tintCharts();
      tries++;
      if (tries > 120) clearInterval(timer);
    }, 200);

    if (typeof MutationObserver !== 'undefined') {
      var root = document.getElementById('app') || document.body;
      var moTimer = null;
      new MutationObserver(function (mutations) {
        var hit = false;
        var i;
        for (i = 0; i < mutations.length; i++) {
          if (
            mutations[i].target &&
            mutations[i].target.closest &&
            mutations[i].target.closest('[class*="chart_container"]')
          ) {
            hit = true;
            break;
          }
        }
        if (!hit) return;
        if (moTimer) clearTimeout(moTimer);
        moTimer = setTimeout(tintCharts, 120);
      }).observe(root, { childList: true, subtree: true });
    }

    window.addEventListener('popstate', tintCharts);
    window.addEventListener('hashchange', tintCharts);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }
})();
