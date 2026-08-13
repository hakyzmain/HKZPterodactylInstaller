(function () {
  'use strict';
  var BRAND = 'HAKYZ LLC';
  var FOOTER_RE = /pterodactyl\s*(?:software|®)?\s*(?:©|&copy;|\(c\))?/i;

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

  function scan() {
    var nodes = document.querySelectorAll('footer, footer *, [class*="Footer"], [class*="footer"]');
    var i;
    for (i = 0; i < nodes.length; i++) patchNode(nodes[i]);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', scan);
  } else {
    scan();
  }
})();
