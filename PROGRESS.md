# PROGRESS

このファイルは**ループ間で唯一引き継がれる記憶の要約**です。
各サイクルの開発担当が、これを読んでから作業を始め、作業後に書き換えます。

> ルール: 全体で **80行以内** に収めること。
> 増やすのではなく「圧縮して書き換える」。詳細は `docs/journal/` に置き、ここには残さない。

---

## 現在地

- サイクル: 6 / 7
- プロダクト: 交換日記アプリ「かわりばんこ」（要件は `docs/product-brief.md`）
- 実装状況: 読む・書く・出力・スレッド・サイクルグループ・次の番・ユーザー同一性・未読追跡・反映済み下書き検出・スレッドソート無効化・全文検索（DOMノードハイライト）が揃った
- 交換日記: 17件（c0〜c5の16件 + c6-dev）

## アーキテクチャ上の決定（Decision Log）

| # | 決定したこと | 理由 | サイクル |
|---|---|---|---|
| 1 | 静的HTML + バニラJS のみ | 制約準拠・ビルド不要・依存ゼロ | 1 |
| 2 | データ取得は `fetch('data/diary.json')` | CORS回避 | 1 |
| 3 | 著者フィルタはヘッダのチップボタン | UXのシンプルさ。全員非表示を防ぐ | 1 |
| 4 | ソートは日付→(正本/下書き区別)→元インデックスの3段キー | 同日=同cycleで第2キーが無効。第3キーで安定 | 2 |
| 5 | XSS対策: esc()を全補間に適用・色値はstyleプロパティ経由 | フォーム入力が人間による自由入力 | 2 |
| 6 | ローカル下書きは localStorage に保存 | 静的サイトのためサーバ書き込み不可 | 2 |
| 7 | 下書きの非表示トグル（削除不可） | 日記は改竄禁止の原則を localStorage 下書きにも準用 | 2 |
| 8 | JSON出力時に4種の検証を「ブロック」ではなく「警告」に | 静的サイトの出力機能として正しい強度 | 2 |
| 9 | `.export-overlay:not([hidden]) { display: flex }` | `display: flex` が `[hidden]` を上書き。セレクタを修正 | 3 |
| 10 | スレッドとサイクルグループを独立モードに | 2軸を混在させると意味が濁る | 3 |
| 11 | ユーザー同一性は localStorage に保存（認証なし） | 静的サイトのスコープ外 | 4 |
| 12 | ~~未読追跡: 起動時に lastRead を自動更新~~ → #15 で置き換え | セッション単位の管理はリロード・名前変更で壊れる | 4→5 |
| 13 | CSS hidden チェックを Node.js 静的解析に置換 | CDP/WebSocket は Node 標準モジュール外 | 4 |
| 14 | turnOrder を members.inRotation から導出 | 二重定義を解消 | 4 |
| 15 | 未読基準を「あなたが最後に書いたエントリ」に変更（#12を置き換え） | リロード・名前変更後も消えない | 5 |
| 16 | スレッドモードでソートボタンを disabled 化 | 一本鎖では兄弟ソートが効かない | 5 |
| 17 | officialByCycle にローカル下書きを含める | 自分の下書きを書いた時点でサイクルドットが埋まる | 5 |
| 18 | CSS 解析: hidden 要素 id/class を HTML から動的抽出 + セレクタをカンマ分割 | 手書きリスト更新忘れの失敗モードを根絶 | 5 |
| 19 | 反映済み下書き: 同 id が正本に存在 = 反映済み | id が正本の一意キー | 5 |
| 20 | 全文検索: indexOf 線形走査 + DOMノードハイライト | データ量（最大21件×500字）で線形走査で十分。DOMノードでXSS対策（#5）を維持 | 6 |
| 21 | 下書きのDOM id を `entry-draft-{id}` に分離 | 返信リンク・ジャンプボタンが正本を確実に指す | 6 |
| 22 | スレッドモードで同id下書きを除外（正本優先） | 件数と描画枚数を一致させる。byIdの競合を避ける | 6 |
| 23 | CSS解析にインライン`style=`の`display:`検出を追加 | `<div style="display:block" hidden>` を素通りしていた穴を塞ぐ | 6 |

## 未解決の課題・リスク

- **下書きの編集不可**: `saveLocalEntry()` の更新分岐（`idx >= 0`）が到達不能のまま（6サイクル持ち越し）
- **モバイルの実測値が取れない**: headless Chromeのdump-domではレイアウト座標が取得できない。CSS変更から推定するしかない状況。

## 次のサイクルへの申し送り

- localStorage キー: `kawaribanko_current_user` / `kawaribanko_last_read_{userId}` / `kawaribanko_local_entries` / `kawaribanko_hidden_ids`
- `getReadFromIdx(userId)` = `max(getUnreadBaseIdx(userId), getLastRead(userId))`
- 下書きのDOM id: `entry-draft-{id}`（正本は `entry-{id}`）
- 全文検索: `searchQuery` グローバル変数。`render()` 内でフィルタ、`highlightText()` でDOMノードハイライト
- スレッドモード: `sorted.filter(e => !e._local || !officialIdSet.has(e.id))` で正本優先除外
- アプリ確認: `python3 -m http.server 8000 --directory app` 起動後、17件のカードが表示されること
