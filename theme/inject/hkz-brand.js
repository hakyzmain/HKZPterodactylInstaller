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

  function setImp(el, prop, val) {
    if (!el || !el.style) return;
    el.style.setProperty(prop, val, 'important');
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
    for (var i = 0; i < nodes.length; i++) patchNode(nodes[i]);
  }

  function clearPaint(el) {
    setImp(el, 'background', 'transparent');
    setImp(el, 'background-color', 'transparent');
    setImp(el, 'background-image', 'none');
    setImp(el, 'border', 'none');
    setImp(el, 'box-shadow', 'none');
    setImp(el, 'outline', 'none');
  }

  function paintFiles() {
    var rowBg = cssVar('--hkz-surface-row', 'rgba(255,255,255,0.06)');
    var rows = document.querySelectorAll('#app [class*="file_row"]');
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i];
      setImp(row, 'position', 'relative');
      setImp(row, 'background', rowBg);
      setImp(row, 'background-color', rowBg);
      setImp(row, 'background-image', 'none');
      setImp(row, 'border', 'none');
      setImp(row, 'border-radius', '2px');
      setImp(row, 'margin-bottom', '1px');
      setImp(row, 'box-shadow', 'none');
      setImp(row, 'outline', 'none');
      var kids = row.querySelectorAll('*');
      for (var k = 0; k < kids.length; k++) {
        var kid = kids[k];
        var tag = (kid.tagName || '').toLowerCase();
        if (tag === 'input' && kid.type === 'checkbox') {
          setImp(kid, 'background', 'transparent');
          setImp(kid, 'background-color', 'transparent');
          setImp(kid, 'box-shadow', 'none');
          continue;
        }
        clearPaint(kid);
      }
    }
  }

  function paintConsole() {
    var bg = cssVar('--hkz-surface-console', '#0a0a0c');
    var bar = cssVar('--hkz-surface-console-bar', '#121218');
    var line = cssVar('--hkz-line-soft', 'rgba(255,255,255,0.18)');
    var terminals = document.querySelectorAll('#app [class*="terminal"].relative, #app div[class*="terminal"].relative');
    for (var i = 0; i < terminals.length; i++) {
      var t = terminals[i];
      setImp(t, 'background', bg);
      setImp(t, 'background-color', bg);
      setImp(t, 'border', '1px solid ' + line);
      setImp(t, 'border-radius', '8px');
      setImp(t, 'overflow', 'hidden');
      setImp(t, 'box-shadow', '0 10px 28px rgba(0,0,0,0.35)');
      setImp(t, 'width', '100%');
      setImp(t, 'max-width', '100%');
    }

    var overflows = document.querySelectorAll('#app [class*="overflows_container"]');
    for (var o = 0; o < overflows.length; o++) {
      setImp(overflows[o], 'margin-left', '0');
      setImp(overflows[o], 'margin-right', '0');
      setImp(overflows[o], 'width', '100%');
      setImp(overflows[o], 'max-width', '100%');
    }

    var containers = document.querySelectorAll('#app [class*="terminal"] [class*="container"]');
    for (var c = 0; c < containers.length; c++) {
      setImp(containers[c], 'background', bg);
      setImp(containers[c], 'background-color', bg);
      setImp(containers[c], 'border', 'none');
      setImp(containers[c], 'border-radius', '0');
      setImp(containers[c], 'margin', '0');
      setImp(containers[c], 'width', '100%');
      setImp(containers[c], 'max-width', '100%');
      setImp(containers[c], 'box-shadow', 'none');
    }

    var inputs = document.querySelectorAll('#app input[class*="command_input"]');
    for (var n = 0; n < inputs.length; n++) {
      setImp(inputs[n], 'background', bar);
      setImp(inputs[n], 'background-color', bar);
      setImp(inputs[n], 'border', 'none');
      setImp(inputs[n], 'border-top', '1px solid ' + line);
      setImp(inputs[n], 'border-radius', '0');
      setImp(inputs[n], 'box-shadow', 'none');
      setImp(inputs[n], 'outline', 'none');
    }

    var xparts = document.querySelectorAll(
      '#app [class*="terminal"] .xterm, #app [class*="terminal"] .xterm-viewport, #app [class*="terminal"] .xterm-screen, #app [class*="terminal"] .xterm-rows, #app [class*="terminal"] .xterm-rows > div'
    );
    for (var x = 0; x < xparts.length; x++) {
      setImp(xparts[x], 'background', 'transparent');
      setImp(xparts[x], 'background-color', 'transparent');
      setImp(xparts[x], 'border', 'none');
      setImp(xparts[x], 'box-shadow', 'none');
    }
  }

  function isGrayPaint(style) {
    if (!style) return false;
    var s = String(style).toLowerCase().replace(/\s+/g, '');
    if (!s || s === 'transparent' || s.indexOf('rgba(0,0,0,0)') !== -1) return false;
    if (s.indexOf('#374151') !== -1 || s.indexOf('#4b5563') !== -1 || s.indexOf('#6b7280') !== -1) return true;
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
    proto.stroke = function () {
      if (inChartCanvas(this) && isGrayPaint(this.strokeStyle)) {
        this.strokeStyle = cssVar('--hkz-chart-grid', 'rgba(255,255,255,0.08)');
      }
      return stroke.apply(this, arguments);
    };
    proto.fillText = function () {
      if (inChartCanvas(this) && isGrayPaint(this.fillStyle)) {
        this.fillStyle = cssVar('--hkz-text', '#e8ecf4');
      }
      return fillText.apply(this, arguments);
    };
  }

  function ensureForceStyle() {
    if (document.getElementById('hkz-force-style')) return;
    var s = document.createElement('style');
    s.id = 'hkz-force-style';
    s.textContent =
      '#app [class*="file_row"]{background:var(--hkz-surface-row)!important;background-color:var(--hkz-surface-row)!important;border:none!important;border-radius:2px!important;margin-bottom:1px!important;box-shadow:none!important}' +
      '#app [class*="file_row"] *:not(input){background:transparent!important;background-color:transparent!important;border:none!important;box-shadow:none!important}' +
      '#app [class*="terminal"].relative{background:var(--hkz-surface-console)!important;border:1px solid var(--hkz-line-soft)!important;border-radius:8px!important;overflow:hidden!important}' +
      '#app [class*="overflows_container"]{margin-left:0!important;width:100%!important;max-width:100%!important}' +
      '#app input[class*="command_input"]{background:var(--hkz-surface-console-bar)!important;border:none!important;border-top:1px solid var(--hkz-line-soft)!important;border-radius:0!important;box-shadow:none!important}';
    document.documentElement.appendChild(s);
  }

  function run() {
    ensureForceStyle();
    hookChartCanvas();
    scanFooter();
    paintFiles();
    paintConsole();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', run);
  } else {
    run();
  }

  var t = 0;
  var timer = setInterval(function () {
    run();
    t += 1;
    if (t > 40) clearInterval(timer);
  }, 250);

  try {
    var mo = new MutationObserver(function () {
      paintFiles();
      paintConsole();
      scanFooter();
    });
    mo.observe(document.documentElement, { childList: true, subtree: true });
  } catch (e) {}
})();
