# thermal-printer

Phomemo T02感熱プリンターに、Mac、iPhone、DualKeyからBLEで印字する道具です。

- Macアプリ（SwiftUI）が、カード、Markdown、写真、QRコードなどを幅384 dotの白黒ビットマップに組み、紙の実寸でプレビューします。
- 印字は、アプリが同梱のPicoRuby CLI `phomemo-print`を子プロセスで起動して行います。CLIは単独でも使えます。
- プリンターの制御はmrbgem [picoruby-phomemo-thermal-printer](https://github.com/bash0C7/picoruby-phomemo-thermal-printer)にあります。
- iPhoneアプリ（`ios/`）は、同じgemとCLIをmruby VMに入れて印字します。
- `dualkey/`は、M5Stack Chain DualKeyのボタンでデバッグ情報をT02に印字します。

設計は`docs/superpowers/specs/`、実装計画は`docs/superpowers/plans/`、調査は`docs/research/`にあります。

## 必要なもの

- macOS 27以降、Xcode、xcodegen（`/opt/homebrew/bin/xcodegen`）、mise（Ruby 4.0.5）
- Phomemo T02
- GitHubのカードには、認証済みの`gh`
- 要約には、Apple Intelligence
- iPhoneアプリには、iOS 26.4以降のiPhone

## セットアップ

repoのルートで実行します。

```
mise exec ruby@4.0.5 -- rake vendor:setup
mise exec ruby@4.0.5 -- rake vm:build
```

`vendor:setup`が[R2P2-darwin](https://github.com/bash0C7/R2P2-darwin)、[port-darwin](https://github.com/bash0C7/picoruby/tree/port-darwin)ブランチのpicoruby、gemを`vendor/`に取得し、使ったport-darwinとgemのcommitを`build/port-darwin.commit`と`build/phomemo-gem.commit`に記録します。`vm:build`が製品のpicoruby VMを`vendor/R2P2-darwin/build/host/bin/picoruby`に作ります。

port-darwinとgemの先頭に上げるときは、`vendor:refresh`を流します。commitを記録し直してビルド済みのVMを消すので、続けて`vm:build`を流します。

初めて印字するときは、macOSのBluetooth許可と、T02とのペアリング確認が出ます。どちらも許可します。

## CLI

```
bin/phomemo-print [options] <file.pbm>
bin/phomemo-print --status
bin/phomemo-print --dry-run [--png out.png] <file.pbm>
```

`vm:build`で作ったVMで動きます。環境変数`PHOMEMO_PICORUBY`で別のpicorubyを指定できます。入力は、幅384のPBM（P4）です。

| オプション | 既定 | 内容 |
|---|---|---|
| `--device NAME` | `T02` | 接続するプリンターの名前 |
| `--density N` | 4 | 濃度。1〜5 |
| `--chunk N` | 128 | 1回の書き込みのバイト数。20〜182 |
| `--interval MS` | 20 | 書き込みの間隔。10〜1000 |
| `--result PATH` | なし | 結果をJSONでこのファイルに書く |
| `--status` | | プリンターの状態を取得する |
| `--dry-run` | | 送るチャンクを一覧する。プリンターなしで動く |
| `--png PATH` | | `--dry-run`と一緒に使い、印字されるビットマップをPNGに書く |

環境変数`PHOMEMO_FEED`（0〜255、既定1）で、印字の最後の紙送りを指定します。1単位は約2 mm（16 dot）です。

結果のJSONは、`--result`を指定しなければ標準出力に出ます。終了コードは次のとおりです。

| コード | error | 内容 |
|---|---|---|
| 0 | | 成功 |
| 1 | `unknown` | 想定外の例外 |
| 2 | `usage` | 引数の誤り、PBMが読めない |
| 10 | `not_found` | T02が見つからない |
| 11 | `wrong_device` | 必要なGATTサービスが揃わない |
| 12 | `busy` | 別の`phomemo-print`が実行中 |
| 13 | `timeout` | 接続が時間内に終わらない |
| 14 | `disconnected` | 送信中に切断された |
| 15 | `status_unavailable` | 紙とカバーの状態を取得できなかった。印字データの送信前に止まる |
| 20 | `paper_out` | 紙がない |
| 21 | `cover_open` | カバーが開いている |
| 22 | `overheat` | 過熱 |
| 23 | `low_battery` | 電池が5%以下 |
| 30 | `print_failed` | プリンターが印字の失敗を返した |
| 31 | `canceled` | プリンターが印字を取り消した |

T02が見つからないときは、電源ボタンを押して起こし、公式アプリの接続を切ります。結果のJSONの`detail`に原因が入り、アプリはそれを日本語で表示します。

| detail | 内容 |
|---|---|
| `name_not_seen` | スキャンでT02の名前が一度も見えなかった |
| `pairing_info_removed` | T02が見つかったが、T02がこの端末のペアリング情報を忘れていて接続を拒否した。この端末のBluetooth設定でT02の登録を解除し、T02の電源を入れ直す |
| `auth_failed` | T02が見つかったが、認証に失敗した。この端末のBluetooth設定でT02の登録を解除する |
| `connect_timeout` | T02が見つかったが、接続が時間内に終わらなかった |
| `link_dropped` | T02が見つかったが、接続が成立する前に切れた |

## アプリ

```
mise exec ruby@4.0.5 -- rake app:build
mise exec ruby@4.0.5 -- rake app:install
```

`app:build`が`build/app/stage/ThermalPrinter.app`を作り、`app:install`が`~/Applications/ThermalPrinter.app`に置きます。アプリはpicoruby、BLEのdylib、CLIのソースを同梱するので、置いたアプリだけで印字できます。

- テキストボックスに文章を書くとmarkdownとして組まれます。画像を貼ると`[Image #1]`と出て、その位置に画像が組まれます。
- 「見出しと要約にして、原文をQRに入れる」で、見出しと要約のカードに置き換わります。原文はQRにそのまま入り、iPhoneのカメラで読み取ると原文が表示されます。日本語で300文字前後、英語で900文字前後まで入ります。
- URL欄は、GitHubのissueとPRを`gh`で、それ以外のhttp / httpsを`curl`で取り込み、本文を要約します。
- 左の欄には、自分にassignされたopenのissueとPR、今日以降のリマインダー（期限の昇順）が並び、選ぶとカードになります。リマインダーはリストを選んで絞れます。初回はリマインダーへのアクセス許可が出ます。
- リマインダーのカードは見出しと要約になり、QRにはそのリマインダーを開くリンク（`x-apple-reminderkit://`）が入ります。

## iPhoneアプリ

```
mise exec ruby@4.0.5 -- rake ios:all
mise exec ruby@4.0.5 -- rake ios:device:check
mise exec ruby@4.0.5 -- rake ios:device:all
```

リマインダーの読み込みとリストでの絞り込み、テキストと画像の貼り付け、ファイルと写真のピッカー、markdownの描画、要約、プレビュー、印刷、チェキモードを備えます。T02への印字は、iPhone実機で行います。

- `ios:all`は、シミュレーター向けのlibmruby（`ios:lib`）のビルド、プロジェクト生成、ビルド、起動までを通します。
- `ios:device:check`は、署名なしで実機向けにリンクします。
- `ios:device:all`は、実機向けのlibmruby（`ios:device:lib`）から通し、接続中のiPhoneに入れて起動します。iPhoneのロックを解除し、署名が通り、開発元のプロファイルを信頼（設定 > 一般 > VPNとデバイス管理）している必要があります。
- 実機が複数台あるときは、`DEVICE_NAME`に機種名の一部（例: `16e`）を指定します。
- `ios:device:all`は起動したアプリの終了を待つので、アプリが入れ替わったあとにコマンドがエラーで終わることがあります。
- `ios:lib`と`ios:device:lib`は同じ`ios/Vendor/lib/libmruby.a`を書き換えます。`ios:build`などを単独で流すときは、先に対応する`lib`を流します。

### チェキモード

右下の丸いボタンで、チェキモードに切り替わります。

- 入るときにT02へ接続し、出るときとアプリが背面に回るときに切断します。
- 接続中は「T02に接続中」と出て、タップを受け付けません。前の接続を閉じている間は、丸いボタンが回ります。
- 画面をタップするとインカメで撮り、写真を写真ライブラリに保存して、写真全体を短い辺が紙幅になる白黒ですぐ印刷します。印刷中は、白黒の画像が上から順に出ます。
- T02に繋がっていないときは「T02に繋がっていません（白黒で保存します）」と出て、タップすると白黒の画像（幅368 dot）を写真ライブラリに保存するだけで、印刷しません。

## DualKey

M5Stack Chain DualKey（ESP32-S3）のボタンを押すと、ヒープや稼働時間などのデバッグ情報をT02に印字します。

```
mise exec ruby@4.0.5 -- rake dualkey:setup
mise exec ruby@4.0.5 -- rake dualkey:qemu_check
mise exec ruby@4.0.5 -- rake dualkey:flash
mise exec ruby@4.0.5 -- rake dualkey:deploy_app
```

firmwareは`dualkey:qemu_check`の合格後だけ`dualkey:flash`で焼けます。`app.rb`は`dualkey:deploy_app`で何度でも転送できます。前提と手順は`dualkey/README.md`にあります。

## テスト

```
mise exec ruby@4.0.5 -- rake test
mise exec ruby@4.0.5 -- rake test:unit
mise exec ruby@4.0.5 -- rake test:integration
FILTER=options mise exec ruby@4.0.5 -- rake test:ruby
mise exec ruby@4.0.5 -- rake app:test
mise exec ruby@4.0.5 -- rake test:e2e
mise exec ruby@4.0.5 -- rake app:uitest
GITHUB_URL=<issueのURL> GITHUB_EXPECT_ROW=<カード行の文字> mise exec ruby@4.0.5 -- rake app:uitest:github
```

- `rake test`は、単体と結合の両方を実行します。
- `rake test:unit`は、CLIのpicotest、CRubyのツールのテスト、送信経路の検査（`rake check:send_paths`）、Swiftの単体テストを実行します。gemの単体テストは、gemのrepoで実行します。
- `rake test:integration`は、製品VMを使うCRubyのテストとSwiftの結合テストを実行します。製品VMは`rake vm:build`で作ります。
- `FILTER`（ファイル名の一部）で、picotestを絞り込めます。
- `rake app:test`は、`app/Core`のSwiftテストを結合も含めて全部実行します。
- `rake test:e2e`は、カードのfixtureからCLIのプレビューPNGを作り、`claude -p`が期待（`test/e2e/preview/`）と照らして判定します。トークンを使うので、`rake test`には含まれません。成果物は`build/e2e/preview/`に残ります。
- `rake app:uitest`は、偽のCLIでアプリを操作するUIテストです。画面とクリップボードを使います。
- `rake app:uitest:github`は、実際の`gh`で取得したカードを実CLIの`--dry-run`でプレビューします。

どれも実機なしで動き、印字しません。

## 紙面の配置

- ヘッドは384 dot（8 dotが1 mm）で、ドット0は紙の左端から約16 dot（2 mm）内側にあります。
- 紙幅は約50 mm（約404 dot）です。本文は368 dotを、ドット2から左右均等に置きます。
- 本文の下に白を48行（6 mm）と、最後の紙送りを足します。切り取り位置はヘッドの約7 mm先です。

## 安全

- gemは、許可された印字コマンドだけを組み立て、プリンターへの書き込みもそのコマンドだけが通ります。
- `1f 11 <op>`は、`op`が0x14以下のものだけを送ります。

## ライセンス

MIT。`LICENSE`を参照してください。
