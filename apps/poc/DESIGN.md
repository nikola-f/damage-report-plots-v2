# CASA 回避のための client-side 全面移行 — 実現可能性調査 / PoC 設計

## 0. 背景

`gmail.readonly` は restricted スコープであり、外部ユーザーに提供するには
本来 CASA Tier 2 セキュリティ評価（有償・年次更新）が必要。ただし Google 公式は
次を明記している:

> "If you store or transmit restricted scope data on servers, then you need to
> complete a security assessment."
> "consider architecting your app such that the Google user data is only ever
> stored client-side on the user's device."

→ **restricted（Gmail）データが一切バックエンドを経由・保存しない**設計なら
セキュリティ評価は不要（ブランド検証のみで済む）。本ドキュメントはその
client-side 全面移行の実現可能性を PoC で検証するための設計。

出典: https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification

## 1. 目的と成功の定義

- **目的**: Gmail 由来データの取得〜解析〜（必要なら Sheets 書き込み）を
  すべてユーザーのブラウザ内で完結させ、CASA 評価対象外の構成が
  技術的に成立するかを PoC で確認する。
- **成功の定義**: 「Gmail データがバックエンドに触れずに damage report を
  取得・解析・可視化できる」ことをスパイクで実証し、フルスキャン所要時間を実測して
  本移行の Go/No-Go を判断できる状態にする。

## 2. 不変条件（CASA 免除の絶対制約）

移行後アーキテクチャは次を **すべて** 満たさねばならない。1つでも破ると評価対象に戻る。

- [ ] Gmail アクセストークンをバックエンドに送信・保存しない（ブラウザ内のみ）
- [ ] Gmail のメッセージ本文・スレッドデータがバックエンドを経由しない
- [ ] Gmail 由来データ（解析前・解析後を含む）をサーバのログ・DB・キューに残さない
- [ ] OAuth トークン取得もバックエンド（client secret）を介さない
      → Google Identity Services (GIS) の **token model**（PKCE, secret 不要）を使用

補足: Sheets（`spreadsheets`）は **sensitive** であって restricted ではなく、かつ
「ユーザー自身のスプレッドシートをクライアントから操作」する限り評価対象にならない。
評価トリガーは Gmail 側のみ。

## 3. 現行アーキテクチャ（restricted データの流れ）

```
POST /api/v1/sync
  └─ ensure_spreadsheet_exists (Sheets API, サーバ)         apps/api/app/controllers/api/v1/sync_controller.rb:63
  └─ GmailThreadListWorker (Sidekiq)                        apps/api/app/workers/gmail_thread_list_worker.rb
       - 2012-10-15〜現在を 30日窓で走査、threads.list       apps/api/app/models/damage_report_query.rb
       - thread ID を SQS へ (最大 6000, 500/msg)
       └─ GmailThreadBatchWorker                            apps/api/app/workers/gmail_thread_batch_worker.rb
            - threads.get を batch(20件/回,1s sleep)で取得
            - HTML 解析でポータル抽出                        apps/api/lib/email_html_decoder.rb
            - dedupe 後、portal レコードを SQS へ
            └─ SpreadsheetSyncWorker                        apps/api/app/workers/spreadsheet_sync_worker.rb
                 - user のスプレッドシートに append
GET /api/v1/plots → plots!A:F を読んで返す                  apps/api/app/controllers/api/v1/plots_controller.rb
  └─ apps/web / apps/iitc が地図に描画
```

**問題点**: Gmail トークン(Redis保存)・スレッド本文(サーバ処理)・抽出データ(SQS)が
すべてバックエンドを通る = 完全に評価対象。

## 4. 目標アーキテクチャ（client-side）

```
[Browser SPA / IITC plugin]
  1. GIS token model で email/profile + gmail.readonly (+ spreadsheets) を取得
  2. Gmail threads.list（窓走査・ページング）→ thread IDs        ※ブラウザから直接
  3. Gmail threads.get（並列 or batch）→ HTML 本文                ※ブラウザから直接
  4. DOMParser + document.evaluate(XPath) で解析                 ※EmailHtmlDecoder を TS 移植
  5. dedupe（DamageReportRecord.deduplicate を TS 移植）
  6a. [案A] ユーザーの Google Sheet に直接 append（Sheets API, ブラウザから）
  6b. [案B] 結果を IndexedDB 保存し、そのまま地図描画（Sheets 不使用）
  7. plots を地図に描画（既存 apps/iitc / apps/web 資産を流用）

[Backend]  … 静的配信のみ（または廃止）。Gmail には一切関与しない。
```

### スコープ設計の分岐（案A / 案B）

| | 案A: Sheets 継続 | 案B: Sheets 廃止 |
|---|---|---|
| 要求スコープ | email profile, gmail.readonly, **spreadsheets** | email profile, **gmail.readonly のみ** |
| 永続化 | ユーザーの Google Sheet（共有可・可搬） | ブラウザ IndexedDB（端末ローカル） |
| 集計 | シート QUERY 数式 or ブラウザ | ブラウザ |
| CASA | どちらも評価対象外（Gmail がサーバ非経由なら） | 同左（要求スコープが減りブランド検証がさらに軽い） |
| product 影響 | 既存のスプレッドシート共有機能を維持 | 端末間同期を失う |

→ **決定: 案A（Sheets 継続）を採用**（共有可能な成果物としてのスプレッドシートを維持）。
PoC でも `spreadsheets` スコープの取得とブラウザからの書き込み（R3）を検証対象に含める。
ただし R1・R2 が No-Go なら案A/案Bの別に関わらず移行不成立のため、優先度は R1・R2 が先。

## 5. コンポーネント移行マッピング

| 現行（サーバ Ruby） | 移行先（ブラウザ TS） | 難易度 | 備考 |
|---|---|---|---|
| OAuth (omniauth, client secret) | GIS token model (PKCE) | 中 | refresh token 無し・1h 寿命 |
| `GmailClient#list_threads` | fetch → gmail threads.list | 低 | REST は CORS 対応 |
| `GmailClient#batch_get_threads` | 並列 threads.get **or** batch endpoint | **高** | batch の CORS 可否が最大の未知数 |
| `EmailHtmlDecoder` (Nokogiri/XPath) | DOMParser + document.evaluate | 低 | XPath はブラウザ native |
| `DamageReportRecord.deduplicate` | 純ロジック移植 | 低 | 依存なし |
| `GmailThreadBatchFetcher` の 429 backoff | 同等の指数バックオフ | 低 | |
| `SpreadsheetsClient`（create/append/get） | Sheets REST 直叩き（案A時） | 中 | CORS 対応見込み |
| Sidekiq / SQS / Redis ワーカー | **廃止**（進捗は IndexedDB/state） | — | インフラ大幅簡素化 |
| `plots_controller` + QUERY 集計 | ブラウザ集計 | 中 | 既存 Plot 形状を踏襲 |

## 6. 技術リスクと検証方法（PoC で潰す）

| # | リスク | 深刻度 | 検証方法 |
|---|---|---|---|
| R1 | **Gmail batch endpoint (`/batch/gmail/v1`) が CORS 非対応**でブラウザから叩けない | 高 | 実際に fetch して CORS 可否を確認。ダメなら「個別 threads.get の並列実行（同時 10〜20, quota 250units/user/sec, threads.get=10units → 実質 ~25 req/s）」にフォールバック |
| R2 | **トークン寿命 1h < フル履歴スキャン時間**（2012〜現在, 最大6000件） | 高 | 実測スループットから所要時間を算出。GIS 静かな再取得(silent `requestAccessToken`)の成否確認。窓ごと resume で分割継続できる設計に |
| R3 | Sheets API のブラウザ書き込み CORS（案A） | 中 | values.append / spreadsheets.create を PoC 2 で試験 |
| R4 | quota 超過 / 429 の頻発 | 中 | 並列度と backoff を実測調整 |
| R5 | 長時間実行での UI ブロック | 低 | Web Worker でオフロード |
| R6 | HTML 構造差異による抽出漏れ | 低 | 現行 XPath をそのまま移植し既知メールで一致確認 |

**最重要は R1・R2**。この2つが成立しなければ client-side 移行は非現実的なので、PoC はまずここに集中する。

## 7. PoC スコープ（最小スパイク）

**決定: 置き場所は `apps/poc/`（既存コードと隔離した使い捨て）。**
Go 判断後に本実装（案A採用のため配信は別途 apps/web / apps/iitc へ）へ作り直す前提。

単一の TS/HTML スパイクで、まず R1・R2 を最優先に検証する:

1. GIS token model で `email profile gmail.readonly`（案A検証時は `spreadsheets` も）を取得（テストユーザーで可）
2. 直近 90 日など**狭い窓**で threads.list（既存 `DamageReportQuery` の条件を移植）
3. 取得した thread IDs に対し **R1 検証**: (a) batch endpoint と (b) 並列個別 get の両方を試し、
   CORS 成否・スループット(req/s)・エラー率を計測
4. HTML を DOMParser+XPath で解析し、抽出ポータル数と座標をページに表示
5. 計測値から**フル履歴スキャンの推定所要時間**を算出（R2 判断材料）
6. （R1・R2 が Go の場合）**R3 検証**: `spreadsheets.create` と `values.append` を
   ブラウザから叩き、CORS 成否を確認（案A の書き込み経路が成立するか）

地図描画・resume・Web Worker 化は **PoC では対象外**（Go 判断後の本実装で対応）。

## 8. 成功基準（Go/No-Go）

- **Go**: Gmail データがバックエンド非経由でブラウザ内取得・解析でき、
  かつ現実的な時間（例: フル初回スキャンが分割継続込みで許容範囲）で完了見込みが立つ。
- **No-Go / 再検討**: batch も並列個別 get も CORS で不可、または
  スループットが低すぎてフルスキャンが非現実的（トークン寿命内に窓を進められない）。
  → その場合は「サーバ残置 + CASA Tier 2 受験」案に戻す。

## 9. 既存バックエンドの扱い（移行が成立した場合）

- Sidekiq / SQS(FIFO) / Valkey(Redis) / ワーカー ECS サービス → **廃止可能**
- API は静的 SPA 配信のみ、または完全撤去（IITC プラグイン配布で代替）
- Terraform / ecspresso 構成も大幅縮小（別タスクで段階移行）
- 認証は GIS に一本化、`sessions_controller` / omniauth / rack-attack(auth) は不要化

## 10. 判断ポイント（確定 / 保留）

1. ~~案A/案B~~ → **確定: 案A（Sheets 継続）**。書き込み経路 R3 を PoC 後段で検証。
2. ~~PoC 置き場~~ → **確定: `apps/poc/`（使い捨て）**。
3. **配信形態（保留）** — 本実装時に `apps/web`(React SPA) 主体か `apps/iitc`(IITC プラグイン) 主体か。
   Ingress 用途なら IITC 統合が自然（Intel 地図上で完結）。Go 判断後に決定。

## 11. ステータス

**PoC 完了 — 判定 GO ✅（2026-07-12）。** R1・R2・R3 を実ブラウザで計測し、
Gmail データがバックエンド非経由でブラウザ内完結できることを実証（詳細は
[RESULTS.md](./RESULTS.md)）。次アクションは本実装フェーズの計画（配信形態の決定、
at-scale 再計測、resume / silent 再取得 / 地図統合の設計）。

---

_この設計は client-side 移行の Go/No-Go 判断を目的とした調査フェーズ。実装本体は
R1・R2 の PoC 結果を受けてから着手する。_
