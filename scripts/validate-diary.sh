#!/usr/bin/env bash
# diary.json とアプリの整合性を検証する。
# CI で自動実行される想定だが、手元でも使える。
# 終了コード: 0=全通過 / 1=エラーあり
set -euo pipefail

DIARY="app/data/diary.json"
INDEX="app/index.html"
ERRORS=0

fail() { echo "❌ $1" >&2; ERRORS=$((ERRORS + 1)); }
pass() { echo "✅ $1"; }

# ────────────────────────────────────────
echo "=== diary.json 検証 ==="

# 1. JSON 構文
if jq empty "$DIARY" 2>/dev/null; then
  pass "JSON構文 OK"
else
  fail "JSON構文エラー: $DIARY"
  exit 1
fi

# 2. ID 重複
DUP=$(jq -r '[.entries[].id] | group_by(.) | map(select(length>1)) | flatten | .[]' "$DIARY")
if [ -z "$DUP" ]; then
  pass "IDに重複なし"
else
  fail "重複IDが見つかりました: $DUP"
fi

# 3. ID フォーマット (c{数字}-{英小文字})
BAD_IDS=$(jq -r '[.entries[].id] | map(select(test("^c\\d+-[a-z]+$") | not)) | .[]' "$DIARY")
if [ -z "$BAD_IDS" ]; then
  pass "IDフォーマット OK (c{cycle}-{author})"
else
  fail "IDフォーマット不正: $BAD_IDS"
fi

# 4. author が members に存在するか
UNKNOWN=$(jq -r '
  (.members | map(.id)) as $members |
  [.entries[].author] | unique
  | map(select(. as $a | $members | index($a) | not))
  | .[]
' "$DIARY")
if [ -z "$UNKNOWN" ]; then
  pass "全エントリのauthorがmembersに存在"
else
  fail "membersに存在しないauthor: $UNKNOWN"
fi

# 5. replyTo の参照先が存在するか (null は OK)
BAD_REPLY=$(jq -r '
  (.entries | map(.id)) as $ids |
  [.entries[]
    | select(.replyTo != null)
    | select(.replyTo as $r | $ids | index($r) | not)
    | "\(.id) -> \(.replyTo)"
  ] | .[]
' "$DIARY")
if [ -z "$BAD_REPLY" ]; then
  pass "replyTo参照 OK"
else
  fail "replyToの宛先が見つからない: $BAD_REPLY"
fi

# ────────────────────────────────────────
echo ""
echo "=== app/index.html JS構文チェック ==="

# 6. <script> タグ内の JS を node --check
TMPFILE=$(mktemp /tmp/kawaribanko-check.XXXXXX.js)
trap 'rm -f "$TMPFILE"' EXIT

# <script> から </script> の間を抽出 (行単位)
awk '/<script>/{found=1; next} /<\/script>/{found=0} found{print}' "$INDEX" > "$TMPFILE"

if node --check "$TMPFILE" 2>/dev/null; then
  pass "JS構文 OK"
else
  fail "JS構文エラー (app/index.html の script タグ内)"
  node --check "$TMPFILE" >&2 || true
fi

# ────────────────────────────────────────
echo ""
echo "=== 参照ファイル存在チェック ==="

# 7. diary.json の存在
if [ -f "$DIARY" ]; then
  pass "app/data/diary.json 存在"
else
  fail "app/data/diary.json が見つかりません"
fi

# 8. 外部 URL 参照がないこと (外部依存ゼロの確認)
EXT=$(grep -oE 'https?://[^"]+' "$INDEX" || true)
if [ -z "$EXT" ]; then
  pass "外部URL参照なし"
else
  fail "外部URL参照あり (外部依存禁止): $EXT"
fi

# ────────────────────────────────────────
echo ""
echo "=== ブラウザ描画チェック (headless Chrome) ==="

CHROME_BIN=$(which google-chrome 2>/dev/null || which chromium-browser 2>/dev/null || which chromium 2>/dev/null || echo "")
if [ -z "$CHROME_BIN" ]; then
  echo "⏭️  headless Chrome が見つかりません — 描画チェックをスキップ"
else
  RENDER_PORT=18811
  python3 -m http.server "$RENDER_PORT" --directory app >/dev/null 2>&1 &
  RENDER_PID=$!
  # サーバ起動を待つ（最大1.5秒）
  for _ in 1 2 3; do
    curl -sf "http://127.0.0.1:$RENDER_PORT/" >/dev/null && break
    sleep 0.5
  done

  DOM=$("$CHROME_BIN" --headless=new --no-sandbox --disable-gpu \
    --virtual-time-budget=6000 \
    --dump-dom "http://127.0.0.1:$RENDER_PORT/" 2>/tmp/chrome_validate_err.txt || true)

  kill "$RENDER_PID" 2>/dev/null || true
  wait "$RENDER_PID" 2>/dev/null || true

  if [ -z "$DOM" ]; then
    echo "⚠️  DOM ダンプ取得失敗 — 描画チェックをスキップ"
  else
    # 9. エントリカード数チェック
    ENTRY_COUNT=$(jq '.entries | length' "$DIARY")
    CARD_COUNT=$(echo "$DOM" | grep -cE 'class="entry-card' || true)
    if [ "$CARD_COUNT" -ge "$ENTRY_COUNT" ]; then
      pass "タイムライン: entry-card ${CARD_COUNT} 件描画 (diary.json: ${ENTRY_COUNT} 件)"
    else
      fail "タイムラインのカードが不足 — 期待: ${ENTRY_COUNT}+, 実際: ${CARD_COUNT}"
    fi

    # 10. [hidden] CSS 上書きチェック（ソース検査）
    # .export-overlay:not([hidden]) 形式か、[hidden]{display:none} 補正があればOK
    if grep -qE 'export-overlay:not\(\[hidden\]\)' "$INDEX"; then
      pass "[hidden] CSS 修正済み: .export-overlay:not([hidden]) 形式を使用"
    elif grep -qE '\[hidden\][^{]*\{[^}]*display[^}]*none' "$INDEX"; then
      pass "[hidden] CSS 修正済み: [hidden]{display:none} 上書きあり"
    elif grep -A3 '\.export-overlay\s*{' "$INDEX" 2>/dev/null | grep -qE 'display\s*:\s*flex'; then
      fail ".export-overlay { display: flex } が [hidden] を上書きしています（モーダルが起動時から表示される）"
    else
      pass "[hidden] CSS の衝突なし"
    fi

    # 11. JS 実行エラーチェック（dbus などの環境エラーは除外）
    JS_ERRORS=$(grep -iE 'SyntaxError|ReferenceError|TypeError|Uncaught' \
      /tmp/chrome_validate_err.txt 2>/dev/null || true)
    if [ -z "$JS_ERRORS" ]; then
      pass "JS 実行エラーなし"
    else
      fail "JS 実行エラーが検出されました: $JS_ERRORS"
    fi
  fi
fi

# ────────────────────────────────────────
echo ""
if [ "$ERRORS" -eq 0 ]; then
  echo "✅ 全チェック通過"
else
  echo "❌ ${ERRORS}件のエラーが見つかりました"
  exit 1
fi
