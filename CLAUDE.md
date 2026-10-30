# thermal-printer

Phomemo T02 感熱プリンターに、Mac から印字する道具。Mac アプリ（SwiftUI）が紙幅の白黒ラスタを組み、PicoRuby CLI が BLE で送る。印字を担う Phomemo の制御は mrbgem `picoruby-phomemo-thermal-printer`（`github.com/bash0C7/picoruby-phomemo-thermal-printer`）にあり、`rake vendor:setup` が `vendor/picoruby-phomemo-thermal-printer` に取得する。iPhone アプリ（`ios/`）は、同じ gem と CLI を mruby VM に入れて印字する。

設計書: `docs/superpowers/specs/2026-10-24-thermal-printer-design.md`。実装計画: `docs/superpowers/plans/`。調査: `docs/research/`。使い方: `README.md`。

## 安全規則（プリンターを守る）

- `1f 11 <op>` は `op` が 0x14 以下のものだけを送る。理由を問わない。
- コマンドは、設計書 §6.8 の allowlist にあるものだけを使う。実機確認でも同じ。
- allowlist へ足すときは、`docs/research/phomemo-t02-protocol.md` に根拠があることを確かめ、ユーザーに確認する。
- BLE の write 呼び出しは gem の 2 か所（`transport.rb` の `write_chunk` と、`session.rb` の `emit`）に置く。gem の規律は gem repo の CLAUDE.md にある。`rake check:send_paths` は、この repo の CLI、ツール、rake と、取得した gem の両方を検査する。

## 開発規律

- t-wada 流 TDD。コードには How、テストには What、コミットログには Why を書く。コードは名前と構造だけで読める形にする。
- 完了は、macOS から T02 実機に印字されたとき。host のテストが green でも、実機で出るまで「動いた」と言わず、実機が使えないときは 1 行で報告して完了宣言を保留する。
- Ruby は mise の 4.0.5（`mise exec ruby@4.0.5 -- rake ...`）。rake/bundle/ruby は直接起動し、repo の中を cwd にする。
- Swift は `/usr/bin/swift`（Xcode）。PATH では `~/.swiftly/bin/swift` より前に置く。
- `vendor/` と `build/` は生成物で、git の管理外。
- picoruby-ble は、公開 API と、上書き用のフックだけで使う。使うコードは gem にあり、内部変数、非公開メソッド、`start` の中身の複製には触れない。
- `port-darwin` は commit を固定せず先頭に追従する。gem も `main` の先頭に追従する。`rake vendor:setup` / `vendor:refresh` のたびに使った commit を `build/port-darwin.commit` と `build/phomemo-gem.commit` に記録する。`port-darwin` 自体の改修が要ると判断したら、手を入れる前にユーザーに相談する。
- `port-darwin`、R2P2-darwin、stackchan-picoruby など既存 repo の変更は、ユーザーに確認してから行う。
- PicoRuby と CRuby の差（`rescue` 内の裸 `raise`、`module_function`、regexp の `|` など）の実測メモは `~/dev/src/github.com/bash0C7/stackchan-picoruby/CLAUDE.md` にある。
- コード内にコメントを置かない（コードと乖離するため）。理由はコミットメッセージに書く。ドキュメント生成のための型情報と説明は書いてよい。
- README.md と CLAUDE.md には、最新のスナップショットだけを書く。
- 画面、クリップボード、プリンターに触る操作（UI テスト、実機印字）は、実行前にユーザーへ、内容、実行する時刻、影響、止め方を伝え、返事を受けてから実行する。許可は、伝えたその 1 回にだけ効く。再現確認や再印字も、新しい印字として伝える。ユーザーが操作している最中は、UI テストを走らせない。

## DualKey（ESP32-S3）

`dualkey/` は、Chain DualKey のボタンでデバッグ情報を T02 に印字するアプリと、その firmware の構成。手順とメモリの数値は `dualkey/README.md`。

- firmware は `rake dualkey:qemu_check` の合格後だけ `rake dualkey:flash` で焼く。合格の記録は firmware の入力（`dualkey/firmware`、`dualkey/build_config`、`dualkey/mrbgems`、3 つの gem の `mrblib`）の内容で照合する。
- `app.rb` は firmware に入らない。`rake dualkey:deploy_app` で何度でも転送してよい。
- 実機の印字は、これまでと同じく毎回ユーザーの許可を得る。プリンターが OFF のときは、押下から `NOT_FOUND` までの経路で確認する。

## テスト戦略

テストは単体、結合、E2E の 3 層に置く。gem の単体テストは gem repo にある。

- 単体: 1 つの型または関数の振る舞い。依存は fake に置き換える。picoruby 上で動くコード（CLI）は、`rake test:ruby` が起動する picotest で picoruby VM 上に実行する。CRuby の minitest は picoruby 上で動かないツール（`test/tools`）に限る。Swift の単体テストは `rake test:unit` に含まれる。
- 結合: 実物の部品を 2 つ以上つなぎ、BLE だけを fake に置き換える。gem と CLI を製品 VM でつなぐ `--dry-run`、アプリの Core が実 CLI を子プロセスで起動する経路が対象。
- E2E: アプリ、CLI、製品 VM を実プロセスで通す。判定に Claude の推論を使ってよい（プレビュー PNG の読み取り、画面の確認など）。実機印字は最上位の E2E で、ユーザーが指示したときだけ行う。

## テストの実行

```
mise exec ruby@4.0.5 -- rake vendor:setup      # R2P2-darwin、picoruby、gem を取得し、commit を build/ に記録
mise exec ruby@4.0.5 -- rake picotest:build    # BLE なしのテスト VM (build_config/picoruby-test.rb)
mise exec ruby@4.0.5 -- rake test              # 単体と結合
mise exec ruby@4.0.5 -- rake test:unit         # CLI の picotest、test/tools、check:send_paths、Swiftの単体テスト
mise exec ruby@4.0.5 -- rake test:integration  # test/integrationのCRubyテストとSwiftのThermalPrinterIntegrationTests
FILTER=options mise exec ruby@4.0.5 -- rake test:ruby
mise exec ruby@4.0.5 -- rake vm:build          # 製品 VM (build_config/darwin-thermal-printer.rb)
mise exec ruby@4.0.5 -- rake test:e2e          # カードのプレビュー PNG を claude -p が判定する。トークンを使う
mise exec ruby@4.0.5 -- rake app:uitest        # 偽の CLI でアプリを操作する UI テスト。画面とクリップボードを使う
GITHUB_URL=<issue の URL> GITHUB_EXPECT_ROW=<カード行の文字> mise exec ruby@4.0.5 -- rake app:uitest:github   # 実際の gh で取得したカードを、実 CLI の --dry-run でプレビューする。印字しない
mise exec ruby@4.0.5 -- rake ios:all           # iPhone アプリ（ios/）を Simulator 向けにビルドして起動する。libmruby は ios:lib（実機向けは ios:device:lib）。実機は ios:device:all
DEVICE_NAME=<機種名の一部> mise exec ruby@4.0.5 -- rake ios:device:all   # 実機が複数台あるときの対象の指定
```

- `test:integration`は製品VMを要する。VMがなければ中断して`rake vm:build`を促す。
- `test:e2e`は`rake test`に含まれない。期待は`test/e2e/preview/<名前>.md`に、カードのfixtureごとに書く。成果物は`build/e2e/preview/`に残る。
- `rake app:test`は、app/Coreの全Swiftテスト（結合を含む）を実行する。
