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
if [ "$ERRORS" -eq 0 ]; then
  echo "✅ 全チェック通過"
else
  echo "❌ ${ERRORS}件のエラーが見つかりました"
  exit 1
fi
