(function () {
  'use strict';
  var BRAND = 'HAKYZ LLC';
  var FOOTER_RE = /pterodactyl\s*(?:software|®)?\s*(?:©|&copy;|\(c\))?/i;

  function cssVar(name, fallback) {
    try {
      var v = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
      return v || fallback;
    } catch (e) {
      return fallback;
    }
  }

  function isFooterCopyright(el) {
    if (!el || el.nodeType !== 1) return false;
    if (el.closest && el.closest('[role="dialog"], form, [class*="Modal"], [class*="ContentBox"]')) {
      return false;
    }
    var tag = (el.tagName || '').toUpperCase();
    var cls = (el.className || '').toString();
    if (tag !== 'FOOTER' && !/footer|copyright/i.test(cls)) return false;
    var t = (el.textContent || '').trim();
    if (!t || t.indexOf('HAKYZ') !== -1) return false;
    if (t.length > 200) return false;
    return FOOTER_RE.test(t) || (/©\s*20\d{2}/.test(t) && /pterodactyl|software/i.test(t));
  }

  function patchNode(el) {
    if (!isFooterCopyright(el)) return;
    el.textContent = BRAND;
    el.setAttribute('data-hkz-footer', '1');
    el.classList.add('hkz-footer-brand');
  }

  function scanFooter() {
    var nodes = document.querySelectorAll('footer, footer *, [class*="Footer"], [class*="footer"]');
    var i;
    for (i = 0; i < nodes.length; i++) patchNode(nodes[i]);
  }

  function isGrayPaint(style) {
    if (!style) return false;
    var s = String(style).toLowerCase().replace(/\s+/g, '');
    if (!s || s === 'transparent' || s.indexOf('rgba(0,0,0,0)') !== -1) return false;
    if (s.indexOf('#374151') !== -1 || s.indexOf('#4b5563') !== -1 || s.indexOf('#6b7280') !== -1) return true;
    if (s.indexOf('#e5e7eb') !== -1 || s.indexOf('#d1d5db') !== -1 || s.indexOf('#9ca3af') !== -1) return true;
    var m = s.match(/rgba?\((\d+),(\d+),(\d+)/);
    if (!m) return false;
    var r = +m[1];
    var g = +m[2];
    var b = +m[3];
    var max = Math.max(r, g, b);
    var min = Math.min(r, g, b);
    return max - min < 18 && r > 40 && r < 190;
  }

  function inChartCanvas(ctx) {
    try {
      var c = ctx && ctx.canvas;
      return !!(c && c.closest && c.closest('[class*="chart_container"]'));
    } catch (e) {
      return false;
    }
  }

  function hookChartCanvas() {
    if (CanvasRenderingContext2D.prototype.__hkzChartHook) return;
    CanvasRenderingContext2D.prototype.__hkzChartHook = true;
    var proto = CanvasRenderingContext2D.prototype;
    var stroke = proto.stroke;
    var fillText = proto.fillText;
    var strokeRect = proto.strokeRect;

    proto.stroke = function () {
      if (inChartCanvas(this) && isGrayPaint(this.strokeStyle)) {
        this.strokeStyle = cssVar('--hkz-chart-grid', 'rgba(255,255,255,0.08)');
      }
      return stroke.apply(this, arguments);
    };

    proto.strokeRect = function () {
      if (inChartCanvas(this) && isGrayPaint(this.strokeStyle)) {
        this.strokeStyle = cssVar('--hkz-chart-grid', 'rgba(255,255,255,0.08)');
      }
      return strokeRect.apply(this, arguments);
    };

    proto.fillText = function () {
      if (inChartCanvas(this) && isGrayPaint(this.fillStyle)) {
        this.fillStyle = cssVar('--hkz-text', '#e8ecf4');
      }
      return fillText.apply(this, arguments);
    };
  }

  function boot() {
    hookChartCanvas();
    scanFooter();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }

  try {
    var mo = new MutationObserver(function () {
      scanFooter();
    });
    mo.observe(document.documentElement, { childList: true, subtree: true });
  } catch (e) {}
})();
