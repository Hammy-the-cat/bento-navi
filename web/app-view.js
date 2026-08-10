// アプリ(iOS/Android)のアプリ内ブラウザから開かれたときの調整。
//
// アプリからは各ページを ?app=1 付きで開く。そのときは
//   - 「アプリを開く」等のWeb版へのリンクを隠す(既にアプリを使っているため紛らわしい)
//   - 記事間のリンクには ?app=1 を引き継ぐ
//   - 画面上部に「閉じればアプリに戻れる」ことを案内する
// を行う。ブラウザで直接開いた場合は何もしない。
(function () {
  'use strict';
  try {
    if (new URLSearchParams(location.search).get('app') !== '1') return;

    var isAppLink = function (href) {
      return href === './' || href === '.' || href === 'index.html';
    };

    // 「アプリで探す」ボタンはカードごと隠す(見出しだけ残ると不自然なため)
    document.querySelectorAll('a.cta').forEach(function (a) {
      var card = a.closest('.card') || a;
      card.style.display = 'none';
    });

    // ナビ・フッターにあるWeb版アプリへのリンクを隠す
    document.querySelectorAll('nav.site a, footer a').forEach(function (a) {
      if (isAppLink(a.getAttribute('href') || '')) a.style.display = 'none';
    });

    // 記事同士のリンクにはフラグを引き継ぐ
    document.querySelectorAll('a[href$=".html"]').forEach(function (a) {
      var h = a.getAttribute('href') || '';
      if (h.indexOf('://') !== -1 || h.indexOf('app=1') !== -1) return;
      a.setAttribute('href', h + (h.indexOf('?') === -1 ? '?' : '&') + 'app=1');
    });

    // 戻り方の案内
    var bar = document.createElement('div');
    bar.textContent = '← このページを閉じるとアプリに戻ります';
    bar.style.cssText =
      'background:#5D4037;color:#fff;font-size:12px;text-align:center;' +
      'padding:10px 12px;letter-spacing:.5px;';
    document.body.insertBefore(bar, document.body.firstChild);
  } catch (e) {
    // 表示調整の失敗でページ本体を壊さない
  }
})();
