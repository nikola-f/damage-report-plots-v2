# apps/poc — CASA client-side 移行 検証スパイク（使い捨て）

Gmail の取得・解析を **ブラウザ内のみ** で完結できるか（＝CASA セキュリティ評価の
対象外構成が技術的に成立するか）を実測するための使い捨て PoC。
設計の全体像は [DESIGN.md](./DESIGN.md) を参照。

> ⚠️ これは Go/No-Go 判断のための調査コード。本実装ではない。判断後に破棄し、
> `apps/web` / `apps/iitc` へ作り直す前提。

## 検証項目

| ID | 内容 | 判定方法 |
|----|------|----------|
| R1 | Gmail の取得がブラウザから可能か（batch / 並列 GET の CORS + 実動作） | ボタン 3a / 3b が ✅ で完了 |
| R2 | トークン寿命(1h)内にフル履歴スキャンが収まるか | スループットからの推定表示 |
| R3 | Sheets 作成+書込がブラウザから可能か（案A の書込経路） | ボタン 4 が ✅ で完了 |

## セットアップ（Google 側）

1. GCP プロジェクト（既存の dev プロジェクト可）で **Gmail API** と **Google Sheets API** を有効化
2. OAuth 2.0 クライアント ID を作成:
   - タイプ: **ウェブアプリケーション**
   - **承認済みの JavaScript 生成元** に `http://localhost:8000` を追加
   - （リダイレクト URI は GIS token model では不要）
3. OAuth 同意画面が「テスト」状態なら、**自分のアカウントをテストユーザーに追加**
4. 対象アカウントに Ingress Damage Report メールが存在すること（無い場合は 0 件になる）

## 実行

```bash
cd apps/poc
python3 -m http.server 8000
```

ブラウザで <http://localhost:8000> を開き:

1. OAuth Client ID を貼り付け → **「1. Google 認可」**
2. **「2. threads.list」**（既定は過去 90 日窓）
3. **「3a. BATCH」** と **「3b. 並列 GET」** を両方実行し、✅/❌ とスループットを比較
4. **「4. Sheets」** で R3 を確認

## 結果の記録

計測後、[RESULTS.md](./RESULTS.md) に ✅/❌・スループット・推定時間を追記し、
DESIGN.md の「8. 成功基準」に照らして Go/No-Go を判断する。

## 移植元（apps/api）

- クエリ: `app/models/damage_report_query.rb`
- 取得フィールド: `lib/gmail_client.rb`（`THREAD_FIELDS`, batch body 生成）
- HTML 解析: `lib/email_html_decoder.rb`（`PORTAL_XPATH` ほか）
