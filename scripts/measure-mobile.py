#!/usr/bin/env python3
"""
scripts/measure-mobile.py
390x844 モバイルエミュレーションで主要レイアウト指標を計測する。

使い方:
  1. chromedriver をバックグラウンドで起動:
     chromedriver --port=9515 &
  2. アプリサーバーを起動:
     python3 -m http.server 8000 --directory app &
  3. このスクリプトを実行:
     python3 scripts/measure-mobile.py [userId]
     # userId: dev / feedback / slides （省略時: 未選択）

計測項目:
  HEADER_HEIGHT   - sticky <header> の高さ
  UNREAD_HEIGHT   - 未読通知バーの高さ（未選択ユーザー時は 0）
  FILTER_BAR_H    - フィルタバーの高さ
  VIEW_BAR_H      - ビュー切替バーの高さ
  FIRST_CARD_TOP  - 最初のエントリカードの上端位置（px / 画面比%）
  32px未満        - インタラクティブ要素の一覧
"""

import json, sys, time, urllib.request, urllib.error

PORT_DRIVER = 9515
PORT_APP    = 8000
USER_ID     = sys.argv[1] if len(sys.argv) > 1 else None

def req(method, path, body=None):
    url = f"http://127.0.0.1:{PORT_DRIVER}{path}"
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, method=method,
                               headers={"Content-Type": "application/json"})
    resp = urllib.request.urlopen(r, timeout=10)
    return json.loads(resp.read())

def js(sid, script, args=None):
    return req("POST", f"/session/{sid}/execute/sync",
               {"script": script, "args": args or []})["value"]

caps = {"capabilities": {"alwaysMatch": {
    "browserName": "chrome",
    "goog:chromeOptions": {
        "args": ["--headless=new", "--no-sandbox", "--window-size=390,844"],
        "mobileEmulation": {
            "deviceMetrics": {"width": 390, "height": 844, "pixelRatio": 3, "mobile": True}
        }
    }
}}}

try:
    r = req("POST", "/session", caps)
    sid = r["value"]["sessionId"]
except Exception as e:
    print(f"ERROR: chromedriver に接続できません: {e}")
    print("  chromedriver --port=9515 & を先に実行してください")
    sys.exit(1)

try:
    req("POST", f"/session/{sid}/url", {"url": f"http://127.0.0.1:{PORT_APP}/index.html"})
    time.sleep(0.8)

    # localStorage セットアップ（ユーザー指定時）
    if USER_ID:
        js(sid, "localStorage.setItem('kawaribanko_current_user', arguments[0])", [USER_ID])
        req("POST", f"/session/{sid}/url", {"url": f"http://127.0.0.1:{PORT_APP}/index.html"})
        time.sleep(0.8)

    # 各要素の高さ計測
    header_h = js(sid, """
        var el = document.querySelector('header');
        return el ? Math.round(el.getBoundingClientRect().height) : -1;
    """)

    unread_h = js(sid, """
        var el = document.querySelector('.unread-notice');
        return el ? Math.round(el.getBoundingClientRect().height) : 0;
    """)

    filter_bar_h = js(sid, """
        var el = document.querySelector('.filter-bar');
        return el ? Math.round(el.getBoundingClientRect().height) : 0;
    """)

    view_bar_h = js(sid, """
        var el = document.querySelector('.view-bar');
        return el ? Math.round(el.getBoundingClientRect().height) : 0;
    """)

    first_card_top = js(sid, """
        var el = document.querySelector('.entry-card');
        return el ? Math.round(el.getBoundingClientRect().top + scrollY) : -1;
    """)

    # 32px 未満のインタラクティブ要素一覧
    small_els = js(sid, """
        var min = 32;
        var sel = 'button, input, select, a[href]';
        var res = [];
        document.querySelectorAll(sel).forEach(function(el) {
            var r = el.getBoundingClientRect();
            if (r.width > 0 && r.height > 0 && r.height < min) {
                var label = el.tagName.toLowerCase();
                if (el.id) label += '#' + el.id;
                else if (el.className) label += '.' + String(el.className).split(' ')[0];
                res.push(label + ' h=' + Math.round(r.height));
            }
        });
        return res;
    """)

    screen_pct = round(first_card_top / 844 * 100, 1) if first_card_top >= 0 else '?'

    print(f"=== モバイルレイアウト計測 (390×844) ===")
    print(f"ユーザー         : {USER_ID or '未選択'}")
    print(f"")
    print(f"HEADER_HEIGHT    = {header_h}px")
    print(f"UNREAD_HEIGHT    = {unread_h}px")
    print(f"FILTER_BAR_H     = {filter_bar_h}px")
    print(f"VIEW_BAR_H       = {view_bar_h}px")
    print(f"FIRST_CARD_TOP   = {first_card_top}px ({screen_pct}% of screen)")
    print(f"")
    print(f"32px未満インタラクティブ要素: {len(small_els)}個")
    for s in small_els:
        print(f"  {s}")

finally:
    try:
        req("DELETE", f"/session/{sid}")
    except Exception:
        pass
