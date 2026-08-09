---
description: PR マージ後のローカル反映と追加作業チェック
---

PR がマージされたので、以下のマージ後ルーチンを実行してください。
引数(あれば PR 番号): $ARGUMENTS

## 手順

1. **ローカル反映**
   - `git checkout develop && git pull` で develop を最新化(fast-forward を確認)
   - マージ済みのローカルブランチを削除する(`git branch --merged develop` で確認し、
     develop 自身と `ci/parallelize-deploy-dev` 以外の作業ブランチを `git branch -d`)

2. **CI 確認**
   - `gh run list --branch develop --limit 5` で develop push のワークフロー
     (Terraform CI / Web CI など)が成功しているか確認する。
     実行中なら完了を待ってから結果を報告する

3. **マージ内容から追加作業を判定して報告**(今回のマージで変更されたファイルを
   `git log -1 --stat` や `gh pr view <PR番号> --json files` で確認):
   - `apps/web/` に変更あり → ci-web の deploy ジョブが develop push で dev へ
     自動デプロイ(S3 同期 + CloudFront invalidation)。CI 成功を確認すれば OK
   - `terraform/**/iam_cicd.tf` に変更あり → CI ロールは自身の IAM を更新できない
     ため、**ローカルから targeted apply(IAM bootstrap)**が必要。dev/prod 両方の
     要否を判定する
   - その他 `terraform/` に変更あり → Terraform CI の apply 成功を確認すれば OK
   - ドキュメント(AGENTS.md 等)のみ → 追加作業なし

4. **結果報告**
   - 反映結果(develop のコミット範囲、削除したブランチ)
   - CI の状態
   - ユーザーが実施すべき残作業(あれば手順つきで)を簡潔にまとめる
