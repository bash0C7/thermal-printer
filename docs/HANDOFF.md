# HANDOFF

作業の入口は GitHub issue #1。設計は `docs/superpowers/specs/2026-10-24-thermal-printer-design.md`、計画は `docs/superpowers/plans/2026-10-24-thermal-printer-implementation.md`、実機の記録は `docs/research/t02-device-notes.md`。

## 状態

- gem、CLI、Mac アプリは揃っている。BLE は `picoruby-ble` の公開 API とフックだけで動く。
- 実機（T02）への印字は、CLI 経由とアプリ経由の両方で確認している。紙面の配置は `README.md` の「紙面の配置」にある。
- テストは単体、結合、E2E の 3 層。`rake test` が単体と結合、`rake test:e2e` が E2E、`rake app:uitest` が UI テスト。
- 製品 VM（`vendor/R2P2-darwin/build/host/bin/picoruby`）は gem と CLI のソースを変えるたびに `rake vm:build` で作り直す。

## 残り

- M3: カード JSON の検査、URL スキームの受け口、補助スクリプト、skill、最終レビュー、紙なしの実行（設計書と計画を参照）。
- 実機の確認項目のうち未実施のもの: `t02-device-notes.md` の「未確定」。

## 守ること

- 安全: `1f 11 <op>` で op が 0x14 を超えるものを送らない。未知のコマンドを総当たりで試さない。任意バイト列を送る API を作らない。BLE の write 呼び出しは `ports/darwin/transport.rb` と `session.rb` の `emit` の 2 か所だけ（`rake check:send_paths`）。
- 紙: 連続用紙なので、印字で確かめるのは画面では分からない物理だけにする。印字は毎回、ユーザーの明示の許可を得てから行う。
- 実機で出るまで「動いた」と言わない。
- コードにコメントを書かない。commit は明示 path で行う。

## 未解決のリスク

- 書き込みが落ちても検知できない（write-without-response）。port-darwin が `canSendWriteWithoutResponse` を見ていない。軽減策は `ack_mismatch` の警告。根本修正は port-darwin への変更なので、手を入れる前にユーザーに相談する。
- Continuity Camera のメニュー、EventKit の実機挙動は未確認。

## コマンド

```
mise exec ruby@4.0.5 -- rake test
mise exec ruby@4.0.5 -- rake vm:build
mise exec ruby@4.0.5 -- rake app:build
mise exec ruby@4.0.5 -- rake test:e2e
```
