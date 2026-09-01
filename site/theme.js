// Theme toggle + theme-aware screenshots.
// The pre-paint script in <head> resolves the initial data-theme; this owns the
// toggle button and swaps any img[data-light] to its light-mode capture when the
// page is light. A missing light file falls back to the dark shot, so screenshots
// can be recaptured theme-by-theme (scripts/capture-screenshots.sh --light).
(function () {
  var root = document.documentElement;
  function dark() { return root.getAttribute('data-theme') === 'dark'; }

  function applyImages() {
    Array.prototype.forEach.call(document.querySelectorAll('img[data-light]'), function (img) {
      if (!img.getAttribute('data-dark')) img.setAttribute('data-dark', img.getAttribute('src'));
      if (dark()) {
        img.src = img.getAttribute('data-dark');
        return;
      }
      img.onerror = function () {
        img.onerror = null;
        img.removeAttribute('data-light');
        img.src = img.getAttribute('data-dark');
      };
      img.src = img.getAttribute('data-light');
    });
  }

  function init() {
    applyImages();
    var btn = document.getElementById('theme-toggle');
    if (!btn) return;
    function render() { btn.textContent = dark() ? '☀︎' : '☾'; }
    render();
    btn.addEventListener('click', function () {
      root.setAttribute('data-theme', dark() ? 'light' : 'dark');
      try { localStorage.setItem('theme', root.getAttribute('data-theme')); } catch (e) {}
      render();
      applyImages();
    });
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
