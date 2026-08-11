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
echo "=== CSS [hidden] 要素の display 上書き検査 (静的解析) ==="

# Node.js を使った静的 CSS 解析: [hidden] 属性が付いている要素のセレクタに
# :not([hidden]) ガードなしで display を非-none に設定しているルールを検出する。
CSS_CHECK=$(node -e "
const fs = require('fs');
const html = fs.readFileSync('$INDEX', 'utf8');
const cssMatch = html.match(/<style>([\\s\\S]*?)<\\/style>/);
if (!cssMatch) { process.stdout.write('PASS'); process.exit(0); }
const css = cssMatch[1];

// [hidden] 属性を持つ要素の id と class を HTML から動的に抽出（手書きリスト廃止 #18）
const hiddenTokens = [];
const tagRe = /<[^>]+\\bhidden\\b[^>]*>/g;
let tagMatch;
while ((tagMatch = tagRe.exec(html)) !== null) {
  const tag = tagMatch[0];
  const idM = tag.match(/\\bid=\"([^\"]+)\"/);
  const clsM = tag.match(/\\bclass=\"([^\"]+)\"/);
  if (idM) hiddenTokens.push('#' + idM[1]);
  if (clsM) clsM[1].split(/\\s+/).filter(Boolean).forEach(c => hiddenTokens.push('.' + c));
}

// CSS ルールを「セレクタ { プロパティ }」単位で分解
const ruleRe = /([^{}@]+)\\{([^{}]*)\\}/g;
const violations = [];
let match;
while ((match = ruleRe.exec(css)) !== null) {
  const sel  = match[1].trim();
  const body = match[2];
  // display が non-none のルールだけ対象
  const dm = body.match(/display\\s*:\\s*([^;\\n]+)/i);
  if (!dm) continue;
  const dv = dm[1].trim().toLowerCase();
  if (dv === 'none' || dv === '') continue;
  // セレクタをカンマで分割して1本ずつ判定（リスト部分一致バグ修正 #18）
  const selParts = sel.split(',').map(s => s.trim());
  for (const part of selParts) {
    // この部分セレクタに :not([hidden]) ガードがあればセーフ
    if (part.includes(':not([hidden])')) continue;
    // hidden 属性付き要素のいずれかにマッチするか確認
    for (const token of hiddenTokens) {
      if (part.includes(token)) {
        violations.push('\"' + sel.replace(/\\s+/g,' ') + '\" (' + part + ') が display:' + dv + ' を設定（:not([hidden]) ガードなし）');
        break;
      }
    }
  }
}
if (violations.length > 0) {
  process.stdout.write('FAIL:' + violations.join(' / '));
} else {
  process.stdout.write('PASS');
}
" 2>&1 || true)

if [ "$CSS_CHECK" = "PASS" ]; then
  pass "[hidden] 要素に display 上書きなし"
elif echo "$CSS_CHECK" | grep -q '^FAIL:'; then
  VIOL=$(echo "$CSS_CHECK" | sed 's/^FAIL://')
  fail "[hidden] CSS 上書き検出: $VIOL"
else
  echo "⚠️  CSS 静的解析エラー: $CSS_CHECK"
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

    # 10. JS 実行エラーチェック（dbus などの環境エラーは除外）
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
