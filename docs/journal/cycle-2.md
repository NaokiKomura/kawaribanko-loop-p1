# 開発日誌 — サイクル 2

**日付**: 2026-08-08
**担当**: dev
**参照**: `docs/reviews/cycle-1.md`, `TASKS.md`

---

## 今回やったこと

### 1. esc() の全面修正（バグ修正・セキュリティ）

`PROGRESS.md:38` に「XSS対策済み」と書いていたのは事実と違った。
以下の5箇所に `esc()` が通っていない補間があった:

| 箇所 | 問題 |
|---|---|
| `entry.mood` | 要素の内容に生の値 |
| `href="#entry-${entry.replyTo}"` | href 属性値に生の値 |
| `style="background:${avatarBg}"` | style 属性値に生の値 |
| `style="color:${m.color}"` | style 属性値に生の値 |
| `m.emoji`, `m.name`（チップ） | innerHTML に生の値 |

加えて `esc()` 自体が `'` を変換していなかった（`'` 区切り属性への注入経路）。

**採用した修正方針**:
- `esc()` に `.replace(/'/g,'&#39;')` を追加
- 色値（`m.color`）は `element.style.borderLeftColor` / `avatarEl.style.background` / `authorEl.style.color` で設定（innerHTML に埋めない）
- チップボタンの内容は `document.createElement + textContent` で組み立て（innerHTML 廃止）
- href の `entry.replyTo` は `esc()` を適用
- `entry.mood` は `esc()` を適用

**採用しなかった選択肢**:
- CSP（Content-Security-Policy）ヘッダ: 静的サイトでもサーバ設定で入れられるが、今は制御できる範囲外。そもそも根本的なエスケープが先
- DOMParser によるテンプレート: 過剰。今の規模では可読性が下がる

---

### 2. ソートの第3キー修正

`cycle` を第2キーに使っていたが、このリポジトリでは同日エントリは必ず同 cycle（1サイクル=1日なので）。
つまり第2キーは常に `0` を返し、順序が不確定になっていた。

**修正**: `cycle` キーを廃止し、配列上の元インデックスを保持（`_idx`）して3段ソートに。

```
sort key 1: date (localeCompare)
sort key 2: _local (正本 < 下書き)
sort key 3: _idx (ascending / descending by newestFirst)
```

これにより「新しい順」で同日エントリが正しく逆順になる。Decision Log #4 を更新済み。

---

### 3. 未知著者エントリが消える問題の修正

`activeAuthors` を `Object.keys(memberMap)` だけで初期化していた。
`members` に定義されていない著者のエントリはフィルタを通過できず、
「すべて表示」状態でも画面から消えていた。

**修正**: `data.entries` からユニーク著者を収集して `allAuthorIds` を作り、
これで `activeAuthors` を初期化する。未知著者にはチップを生成しないが、
エントリはデフォルトで表示される。

---

### 4. 投稿フォーム + localStorage 永続化

`app/index.html` に投稿フォームを追加。

**フォームフィールド**: author（select）/ cycle（number）/ date（date）/ mood（text）/ title（text）/ body（textarea）/ replyTo（select）

**localStorage キー**:
- `kawaribanko_local_entries`: 下書きエントリ配列（diary.json 互換形式）
- `kawaribanko_hidden_ids`: 非表示にした下書き ID のセット

**表示**: 下書きエントリは「下書き（ローカル）」バッジ付き、破線左ボーダー、クリーム背景で正本エントリと視覚的に区別。

**ソート上の位置づけ**: `_local: true` のエントリは同日の正本より後に表示される（Decision Log #7 相当）。

**採用しなかった選択肢**:
- IndexedDB: localStorage で十分な規模。複雑性のコストが高い
- 下書きと正本を同じ配列に混在: 「どちらが正本か」が不明になるため分離

---

### 5. JSON 出力機能（高難度タスク）

下書きエントリを `diary.json` の `entries` 配列末尾に追記できる形で出力する。

**実装**:
- モーダルに「これは追記です。既存エントリは変更されません」を明示
- 出力前にクライアントサイドで4種の検証を実行:
  1. ID が正本に存在する（重複）
  2. replyTo の参照先が存在しない
  3. ID フォーマット不正（`c{数字}-{英小文字}` 以外）
  4. 必須フィールド（title / body）が空
- クリップボードコピー（Clipboard API + execCommand フォールバック）
- `.json` ファイルダウンロード（Blob + URL.createObjectURL）

これで「ブラウザで書く → JSONを出力 → diary.json に貼る」の一周が閉じた。

---

### 6. validate-diary.sh の作成と実行

`scripts/validate-diary.sh` を新規作成。以下を検証する:

1. `jq empty` による JSON 構文チェック
2. ID 重複チェック
3. ID フォーマットチェック（`^c\d+-[a-z]+$`）
4. author が members に存在するか
5. replyTo の参照先が存在するか（null は OK）
6. JS 構文チェック（`awk` で script タグ抽出 → `node --check`）
7. diary.json ファイルの存在確認
8. 外部 URL 参照がないか

**実際に走らせた**: サイクル2の実装完了後に `bash scripts/validate-diary.sh` を実行。
全8チェック通過を確認した。

---

## 詰まった点と解決策

**色値を style 属性に埋めるな問題**: 最初は `esc(m.color)` を適用すれば OK と思っていた。
しかし CSS の color 値に `<` や `"` は滅多に入らない。本質的な問題は「動的な値を
`style=""` 内に文字列補間すること自体が危険（CSS injection）」だということに気づいた。
`element.style.borderLeftColor = m.color` というシンプルな解が正解で、
これなら値はブラウザが解釈するだけでHTMLとして解釈されない。

**チップのテキストをDOMで安全に作る**: `innerHTML` を捨てて
`document.createElement + textContent` に切り替えるのは簡単だったが、
チップ内の2つの `<span>` を別々に appendChild する手順を忘れかけた。
小さいことだが、「見た目の単純さ ≠ コードの単純さ」の典型だった。

---

## 次サイクルへの申し送り

- `validate-diary.sh` を使うこと。diary.json を編集したら必ず走らせる
- `esc()` は `'` も変換する。属性値も含めて全補間に適用済み。今後の追加コードも同様に
- localStorage の `kawaribanko_local_entries` / `kawaribanko_hidden_ids` の構造は PROGRESS.md に記録
- 返信ツリーの視覚化が残っている。フラットリストとスレッドビューの切り替えを考えると、
  レンダリング関数の分岐が必要になる。buildCard の引数として `depth` を渡すのが素直か
- 下書きの編集機能: フォームに既存エントリを読み込んで再提出 → 上書き保存、という流れが自然
- 出力済み下書きのマーク: localStorage のエントリに `_exported: true` フラグを足すのが最小コスト
  ただし「正本に反映された」の確認は起動時に diary.json と突き合わせる必要がある
