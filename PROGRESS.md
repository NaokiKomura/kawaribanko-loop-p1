# PROGRESS

このファイルは**ループ間で唯一引き継がれる記憶の要約**です。
各サイクルの開発担当が、これを読んでから作業を始め、作業後に書き換えます。

> ルール: 全体で **80行以内** に収めること。
> 増やすのではなく「圧縮して書き換える」。詳細は `docs/journal/` に置き、ここには残さない。

---

## 現在地

- サイクル: 4 / 7
- プロダクト: 交換日記アプリ「かわりばんこ」（要件は `docs/product-brief.md`）
- 実装状況: 読む・書く・出力・スレッド・サイクルグループ・次の番・ユーザー同一性・未読追跡が揃った
- 交換日記: 11件（c0〜c3の10件 + c4-dev）

## アーキテクチャ上の決定（Decision Log）

| # | 決定したこと | 理由 | サイクル |
|---|---|---|---|
| 1 | 静的HTML + バニラJS のみ | 制約準拠・ビルド不要・依存ゼロ | 1 |
| 2 | データ取得は `fetch('data/diary.json')` | CORS回避。エラー時にCORS説明メッセージを表示 | 1 |
| 3 | 著者フィルタはヘッダのチップボタン。1件は必ず表示 | UXのシンプルさ。全員非表示を防ぐ | 1 |
| 4 | ソートは日付→(正本/下書き区別)→元インデックスの3段キー | cycle は同日=同cycleで第2キーとして無効。配列上の位置を第3キーに | 2 |
| 5 | XSS対策: esc()を全補間に適用・色値はstyleプロパティ経由 | フォーム入力が人間による自由入力になるため | 2 |
| 6 | ローカル下書きは localStorage に保存。正本(diary.json)とは分離 | 静的サイトのためサーバ書き込み不可 | 2 |
| 7 | 下書きの非表示トグル（削除不可） | 日記は改竄禁止の原則を localStorage 下書きにも準用 | 2 |
| 8 | JSON出力時に4種の検証を「ブロック」ではなく「警告」に | 静的サイトの出力機能として正しい強度の選び方 | 2 |
| 9 | `.export-overlay:not([hidden]) { display: flex }` | `display: flex` が `[hidden]` を上書きしていた。セレクタを `not([hidden])` に移すことで修正 | 3 |
| 10 | スレッドとサイクルグループを独立モードに | スレッド=「誰が誰に返したか」、グループ=「いつ書いたか」。2軸を混在させると意味が濁る | 3 |
| 11 | ユーザー同一性は localStorage に保存（認証なし） | 静的サイトのスコープ外。3人しかいない選択肢を1回選ぶだけ | 4 |
| 12 | 未読追跡: 起動時に lastRead を自動更新 + sessionNewCount を保持 | セッション単位で「前回から N 件」が自然に定まる。既読ボタンはセッション内消去用 | 4 |
| 13 | CSS hidden チェックを Node.js 静的解析に置換 | CDP/WebSocket は Node 標準モジュール外。静的解析で .compose-panel 注入も検出可能 | 4 |
| 14 | turnOrder を members.inRotation から導出 | 二重定義を解消。owner が回覧外なことをデータで表現 | 4 |

## 未解決の課題・リスク

- **下書きの編集不可**: `saveLocalEntry()` の更新分岐（`idx >= 0`）が到達不能のまま
- **スレッドモードでサイクルヘッダーが消える**: `renderThreaded()` はサイクルグループを描画しない
- **サイクルドットが下書きを見ない**: `officialByCycle` は正本のみ（下書きを書いても「未記入」表示）
- **モバイル入力体験未検証**

## 次のサイクルへの申し送り

- localStorage キー: `kawaribanko_current_user` / `kawaribanko_last_read_{userId}` / `kawaribanko_local_entries` / `kawaribanko_hidden_ids`
- `sessionNewCount` はグローバル変数。起動時に1回設定され render() 内では変わらない
- `getTurnOrder()` = `members.filter(m => m.inRotation).map(m => m.id)` = `['dev','feedback','slides']`
- アプリ確認: `python3 -m http.server 8000 --directory app` 起動後、headless Chrome で 11件のカードが表示、「あなたは誰ですか？」バナーが出ること、フォームIDが `c4-dev` と出ることを確認済み（c3は全員記入済み → 次はサイクル4の dev）
