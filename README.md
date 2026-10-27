# thermal-printer

Phomemo T02 感熱プリンターに、Mac から BLE で印字する道具です。

- Mac アプリ（SwiftUI）が、カード、Markdown、写真、QR コードなどを幅 384 dot の白黒ビットマップに組み、紙の実寸でプレビューします。
- 印字は、アプリが同梱の PicoRuby CLI `phomemo-print` を子プロセスで起動して行います。CLI は単独でも使えます。
- プリンターの制御は mrbgem [picoruby-phomemo-thermal-printer](https://github.com/bash0C7/picoruby-phomemo-thermal-printer) にあります。`vendor:setup` が `vendor/` に取得します。

設計は `docs/superpowers/specs/`、実装計画は `docs/superpowers/plans/`、調査は `docs/research/` にあります。

## 必要なもの

- macOS 14 以降、Xcode、xcodegen（`/opt/homebrew/bin/xcodegen`）、mise（Ruby 4.0.5）
- Phomemo T02

## セットアップ

```
mise exec ruby@4.0.5 -- rake vendor:setup
mise exec ruby@4.0.5 -- rake vm:build
```

`vendor:setup` が [R2P2-darwin](https://github.com/bash0C7/R2P2-darwin)、[port-darwin](https://github.com/bash0C7/picoruby/tree/port-darwin) ブランチの picoruby、gem を取得し、使った port-darwin と gem の commit を `build/port-darwin.commit` と `build/phomemo-gem.commit` に記録します。`vm:build` が製品の picoruby VM を `vendor/R2P2-darwin/build/host/bin/picoruby` に作ります。

初めて印字するときは、macOS の Bluetooth 許可と、T02 とのペアリング確認が出ます。どちらも許可します。

## CLI

```
bin/phomemo-print [options] <file.pbm>
bin/phomemo-print --status
bin/phomemo-print --dry-run [--png out.png] <file.pbm>
```

入力は、幅 384 の PBM（P4）です。

| オプション | 既定 | 内容 |
|---|---|---|
| `--device NAME` | `T02` | 接続するプリンターの名前 |
| `--density N` | 4 | 濃度。1〜5 |
| `--chunk N` | 128 | 1 回の書き込みのバイト数。20〜182 |
| `--interval MS` | 20 | 書き込みの間隔。10〜1000 |
| `--result PATH` | なし | 結果を JSON でこのファイルに書く |
| `--status` | | プリンターの状態を取得する |
| `--dry-run` | | 送るチャンクを一覧する。プリンターなしで動く |
| `--png PATH` | | `--dry-run` と一緒に使い、印字されるビットマップを PNG に書く |

環境変数 `PHOMEMO_FEED`（0〜255、既定 1）で、印字の最後の紙送りを指定します。1 単位は約 2 mm（16 dot）です。

結果の JSON は、`--result` を指定しなければ標準出力に出ます。終了コードは次のとおりです。

| コード | error | 内容 |
|---|---|---|
| 0 | | 成功 |
| 1 | `unknown` | 想定外の例外 |
| 2 | `usage` | 引数の誤り、PBM が読めない |
| 10 | `not_found` | T02 が見つからない |
| 11 | `wrong_device` | 必要な GATT サービスが揃わない |
| 12 | `busy` | 別の `phomemo-print` が実行中 |
| 13 | `timeout` | 接続が時間内に終わらない |
| 14 | `disconnected` | 送信中に切断された |
| 15 | `status_unavailable` | 紙とカバーの状態を取得できなかった。印字データの送信前に止まる |
| 20 | `paper_out` | 紙がない |
| 21 | `cover_open` | カバーが開いている |
| 22 | `overheat` | 過熱 |
| 23 | `low_battery` | 電池が 5% 以下 |
| 30 | `print_failed` | プリンターが印字の失敗を返した |
| 31 | `canceled` | プリンターが印字を取り消した |

T02 が見つからないときは、電源ボタンを押して起こし、公式アプリの接続を切ります。

## アプリ

```
mise exec ruby@4.0.5 -- rake app:build
mise exec ruby@4.0.5 -- rake app:install
```

`app:build` が `build/app/stage/ThermalPrinter.app` を作ります。`app:install` が `~/Applications/ThermalPrinter.app` に置きます。アプリは picoruby、BLE の dylib、CLI のソースを同梱します。

テキストボックスに文章を書くと markdown として組まれます。画像を貼ると `[Image #1]` と出て、その位置に画像が組まれます。「見出しと要約にして、原文をQRに圧縮」で、見出しと要約のカードに置き換わります。原文は QR に入り（`TP1:` + Base45 + raw deflate、CyberChef の「From Base45」「Raw Inflate」で戻せます）、日本語で 500〜800 文字、英語で 2,000 文字前後まで入ります。URL 欄は GitHub 以外の http / https も `curl` で取り込み、本文を要約します。

## iPhone アプリ

```
mise exec ruby@4.0.5 -- rake ios:all
mise exec ruby@4.0.5 -- rake ios:device:check
mise exec ruby@4.0.5 -- rake ios:device:all
```

リマインダーの読み込み、テキストと画像の貼り付け、ファイルと写真のピッカー、markdown の描画、要約、プレビュー、印刷を備えます。Mac アプリの部分集合です。T02 の gem と CLI の Runner は、同梱の mruby VM の中で動きます。

- `ios:all`は、シミュレーター向けの libmruby のビルド、プロジェクト生成、ビルド、起動までを通します。
- `ios:device:check`は、署名なしで実機向けにリンクします。
- `ios:device:all`は、署名済みで接続中の iPhone に入れて起動します。
- `ios:lib`と`ios:device:lib`は同じ `ios/Vendor/lib/libmruby.a` を書き換えます。切り替えたら、使う側の`lib`を先に流します。

## テスト

```
mise exec ruby@4.0.5 -- rake test
mise exec ruby@4.0.5 -- rake test:unit
mise exec ruby@4.0.5 -- rake test:integration
FILTER=options mise exec ruby@4.0.5 -- rake test:ruby
```

- `rake test`は、単体と結合の両方を実行します。
- `rake test:unit`は、CLIのpicotest、CRubyのツールのテスト、送信経路の検査（`rake check:send_paths`）、Swiftの単体テストを実行します。gemの単体テストは、gemのrepoで実行します。
- `rake test:integration`は、製品VMを使うCRubyのテストとSwiftの結合テストを実行します。製品VMは`rake vm:build`で作ります。
- `FILTER`（ファイル名の一部）で、picotestを絞り込めます。
- `rake test:e2e`は、カードのfixtureからCLIのプレビューPNGを作り、`claude -p`が期待（`test/e2e/preview/`）と照らして判定します。トークンを使うので、`rake test`には含まれません。

どれも実機なしで動きます。

## 紙面の配置

- ヘッドは 384 dot（8 dot が 1 mm）で、ドット 0 は紙の左端から約 16 dot（2 mm）内側にあります。
- 紙幅は約 50 mm（約 404 dot）です。本文は 368 dot を、ドット 2 から左右均等に置きます。
- 本文の下に白を 48 行（6 mm）と、最後の紙送りを足します。切り取り位置はヘッドの約 7 mm 先です。

## 安全

- gem は、許可された印字コマンドだけを組み立て、プリンターへの書き込みもそのコマンドだけが通ります。
- `1f 11 <op>` は、`op` が 0x14 以下のものだけを送ります。

## ライセンス

MIT。`LICENSE` を参照してください。
