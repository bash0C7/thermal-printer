# Phomemo T02感熱プリンター: 実装計画

- 対象: GitHub issue #1の完遂。Phomemo T02に実機で印字できる、使い物になるMacアプリと、mrbgem `picoruby-phomemo-thermal-printer`。
- 設計書: `docs/superpowers/specs/2026-10-24-thermal-printer-design.md`（以下「設計書」）。この計画は設計書の決定を変えない。食い違いは末尾の「設計書への指摘」に書く。
- 調査: `docs/research/`。手本: `~/dev/src/github.com/bash0C7/stackchan-picoruby`（以下「stackchan」）。

## 0. この計画の読み方

各タスクは、独立にsubagentへ渡せる単位にしてある。書式は次のとおり。

- **目的**: 1〜2行。
- **触るファイル**: このタスクだけが作る、または変えるファイル。並列のタスクどうしでは重ならない。
- **依存**: 先に終わっている必要があるタスクと、M0の結果の項目（`R0-n`、§3）。
- **担当**: sonnet（コーディング・調査）、haiku（結果の決まったコマンドの実行）、opus（レビュー・仕様判断）。
- **TDD**: 失敗するテストのWhat → 最小実装 → green → commitのWhy。主要なテストは骨子（アサーション）まで書く。
- **検証**: コマンドと期待される出力。
- **実機**: 実機と人間の物理操作が要るかどうか。

並列の表記: 「並列群」に入ったタスクは同時に走らせてよい。それ以外は依存の順に直列で走らせる。

## 1. 横断ルール

すべてのタスクの依頼文に、この節をそのまま含める。

### 1.1 安全規則（設計書§6.8。プリンターを壊さない）

- `1f 11 <op>`で`op`が0x14を超えるものは、どんな理由でも送らない。
- 未知のコマンドを総当たりで試さない。実機確認のためでも同じ。
- `1b 4e 04 n`、`1b 37 …`（ESC 7）、`1d 7c n`（GS |）、`1d 67 6e`、`SSSGETSN`など、由来不明・効果不明のコマンドを送らない。
- gemは次のallowlistだけを組み立てる。任意のバイト列をプリンターに書く公開APIを作らない。
  - `1b 40`
  - `1b 61 n`（n ∈ 0..2）
  - `1f 11 02 n`（n ∈ 01..05）
  - `1d 76 30 00 30 00 yL yH` + 48×y byte（1 ≤ y ≤ 255）
  - `1b 64 n`（n ∈ 0..255）
  - `1f 11` + {`07`, `08`, `09`, `0e`, `11`, `12`, `13`}
- allowlistに足す必要が出たら、`docs/research/phomemo-t02-protocol.md`に根拠（実装と行番号）があること、`1f 11`なら0x14以下であることを確かめてから、親に戻してユーザーに確認する。subagentは自分で足さない。
- BLEへ書き込むコードは2か所だけに置く。`ports/darwin/transport.rb`の`write_value_of_characteristic_without_response`の呼び出しと、`mrblib/phomemo_thermal_printer/session.rb`の`write_chunk`の呼び出し。`rake check:send_paths`（T1.3）がこれを機械で確かめる。

### 1.2 コードとコミット

- コードにコメントを書かない。変更の理由はコミットメッセージのbodyに書く。コミット前に、差分の追加行に`#`（Ruby）や`//`（Swift）のコメントが無いことを`git diff --cached -U0 | grep -E '^\+.*(#|//)'`で確かめ、出てきた行が文字列やURLの一部だけであることを目で確かめる。
- t-wada流TDD: コードにはHow、テストにはWhat（テスト名）、コミットログにはWhy。
- gem内（`mrbgems/`配下の`mrblib/`と`ports/`）は`each`/`times`/`map`などのブロック反復を使わず、`while`と明示indexで書く。ivarを3回以上参照するならlocalに取る。テストと`cli/`と`tools/`はこの規則の対象外。
- gem内のバイナリは`bytesize`/`getbyte`/`byteslice`/`pack("C*")`で扱う。製品VMもテストVMも`MRB_UTF8_STRING`でビルドするので、`size`/`[]`は文字単位になり、バイト列を壊す。
- `mrbgem.rake`はASCIIのみ。
- `mrblib/`内でsiblingを`require`しない（ビルドが`Dir.glob("mrblib/**/*.rb").sort`の順で全部読む）。ファイルの読み込み順で壊れないように、クラス本体の評価時に別ファイルの定数を参照しない。
- テストファイルは、gemの定数をテストメソッドの中でだけ参照する（picotestのrunnerは、クラスの列挙のためにテストファイルを先にCRubyで`load`する）。
- `vendor/`と`build/`はcommitしない。
- 並列で走るsubagentはcommitしない。親が`git status`と変更ファイルをHEADと突き合わせ、`rake test`の全量を通してからcommitする。subagentの依頼文には、作ってよいファイルの一覧を明記する。
- 並列のsubagentは同じcheckoutで作業する。git worktreeは使わない（`vendor/`はgitignoreなのでworktreeに無く、symlinkした`vendor/`からはpicorubyのビルドが通らない。stackchan CLAUDE.md）。

### 1.3 環境

- Rubyはmiseの4.0.5（`mise ls ruby`で確認済み）。システムの2.6を使わない。`bash -lc`でrake/ruby/bundleを起動しない。repoの外をcwdにしてrubyを呼ばない。rakeはrepo直下で`rake <task>`と叩く。
- PATHでは`~/.swiftly/bin/swift`が`/usr/bin/swift`より先に来る（`which -a swift`で確認済み）。swiftlyのswiftはpicoruby-bleのSwift packageをビルドできない。Rakefileは`/usr/bin`をPATHの先頭に足す。Rakefileを通さずにSwiftを叩くときは`/usr/bin/swift`と絶対パスで書く。
- `gh`と`xcodegen`は`/opt/homebrew/bin`。GUIアプリはシェルのPATHを持たないので、アプリから`gh`を探すときは`/opt/homebrew/bin/gh`、`/usr/local/bin/gh`の順に見る。
- picorubyのビルド（`vm:build`と`picotest:build`）は同じsource tree（`vendor/R2P2-darwin/vendor/picoruby`）を使うので、同時に走らせない。
- `port-darwin`、R2P2-darwin、stackchanなど既存のrepoは変更しない。`port-darwin`自体の改修が要ると判断したら、手を入れる前に親へ戻し、ユーザーに相談する。
- Apple frameworkのAPI（FoundationModels、EventKit、CoreText、CoreImage、SwiftUI）は、記憶上のsignatureに頼らず、Xcodeのlocal docsetかdeveloper.apple.com/documentationで、名前、引数label、availabilityを確かめてから書く。
- Apple Intelligence系（FoundationModels）はローカル実行で課金もrate limitも無い。品質と確実性を、速度と呼び出し回数より優先する。

### 1.4 検証の規律

- 「green」は、テストを実際に走らせた出力で言う。構文チェックだけ、起動に失敗した検査、disableやcomment-outで得たPASSは数えない。
- 完了は実機の印字。hostのテストがgreenでも、実機で出るまで「動いた」と言わない。
- subagentに検証を任せるときは、production codeを変更しないこと、失敗はfailと報告すること、rake本体のexit codeを報告することを依頼文に含める。

## 2. 共通の前提

### 2.1 ディレクトリ構成（完成形）

```
thermal-printer/
  mise.toml                        # ruby = "4.0.5"
  Rakefile                         # 定数とPATHだけ。taskはrakelib/に置く
  rakelib/
    vendor.rake                    # vendor:setup / vendor:refresh（port-darwinのcommitを記録）
    vm.rake                        # vm:build（製品VM）/ picotest:build（テストVM）/ vm:clean
    test.rake                      # test / test:ruby / test:tools / check:send_paths
    cli.rake                       # cli:bundle（M0のR0-3で中身が決まる）
    app.rake                       # app:gen / app:test / app:uitest / app:build / app:install
    device.rake                    # device:s1:* など実機セッションの手順
  build_config/
    darwin-thermal-printer.rb      # 製品VM: BLE + hal-task-darwin + 本gem
    picoruby-test.rb               # テストVM: BLEなし + picotest
  mrbgems/picoruby-phomemo-thermal-printer/
    mrbgem.rake
    mrblib/phomemo_thermal_printer.rb
    mrblib/phomemo_thermal_printer/{chunker,command,job,pbm_reader,result,session,status}.rb
    ports/darwin/{packet,transport}.rb
    sig/phomemo_thermal_printer.rbs
    test/*_test.rb
    test/mock/fake_transport.rb
  cli/{print.rb,phomemo_cli.rb}
  bin/{phomemo-print,add-card,slack-permalink}
  test/picotest/harness.rb
  test/cli/*_test.rb
  test/tools/*_test.rb
  test/fixtures/                   # PBM、結果JSON、カードJSON（RubyとSwiftの境界の契約）
  tools/{make_test_pbm.rb,dither_golden.js}
  app/
    project.yml                    # xcodegen
    Core/Package.swift             # SwiftPM: ThermalPrinterCore + thermal-pbm
    Core/Sources/ThermalPrinterCore/{Raster,Typesetting,Markdown,Image,QR,Card,Sources,Summary,Strip,Printer}/
    Core/Sources/thermal-pbm/main.swift
    Core/Tests/ThermalPrinterCoreTests/
    App/                           # SwiftUIの画面、Info.plist、entitlements
    UITests/
  .claude/skills/print-slack-card/SKILL.md
  docs/research/t02-device-notes.md
  README.md
```

### 2.2 Xcodeプロジェクトの作り方（設計書§11で任されたもの）

**決定: xcodegen（`app/project.yml`）でアプリを組み、ロジックはローカルのSwift package（`app/Core`）に置く。**

| 軸 | xcodegenだけ | SwiftPMだけ | xcodegen + ローカルpackage（採用） |
|---|---|---|---|
| `.app`の要件（Info.plist、URLスキーム、bundle内へのpicoruby同梱、署名） | 満たす | `.app`を作れないので、bundle化を手で書く | 満たす |
| テストの回しやすさ | `xcodebuild test`だけ。遅く、出力が長い | `swift test`で速い | ロジックは`swift test`、画面だけ`xcodebuild test` |
| 並列作業でのファイル競合 | project.ymlのglobで回避できる | package内のglobで回避できる | 両方globで、manifestはT2.1で一度だけ書く |
| 前例と依存 | R2P2-darwinとstackchanがxcodegenを使う。`/opt/homebrew/bin/xcodegen`あり | 追加依存なし | 前例どおり |

理由: `.app`の要件はxcodegenでしか素直に満たせない。文字組みやディザのように、テストの数が多く、anti-goalをテストで縛る部分は、`swift test`で速く回せる場所に置く。

### 2.3 rakeタスクとコマンド

| コマンド | 中身 | 期待 |
|---|---|---|
| `rake vendor:setup` | R2P2-darwinをclone → `rake -C vendor/R2P2-darwin setup` → `build/port-darwin.commit`にpicorubyのHEADを書く | 最後に`[vendor] port-darwin <40桁sha>`を出す |
| `rake vendor:refresh` | `rake -C vendor/R2P2-darwin refresh` → 同上を記録 → `vm:clean` | 同上 |
| `rake vm:build` | `MRUBY_BUILD_DIR=vendor/R2P2-darwin/build MRUBY_CONFIG=build_config/darwin-thermal-printer.rb rake -C vendor/R2P2-darwin/vendor/picoruby`（opensslのflagを足す） | `vendor/R2P2-darwin/build/host/bin/picoruby`ができる |
| `rake picotest:build` | `MRUBY_BUILD_DIR=build/picotest MRUBY_CONFIG=build_config/picoruby-test.rb rake -C …/picoruby` | `build/picotest/host-picotest/bin/picoruby`ができる |
| `rake vm:clean` | `vendor/R2P2-darwin/build/host`と`build/picotest`を消す（hostビルドにはstampの保護が無い。r2p2-darwin-and-gems.md §1.4） | — |
| `rake test` | `check:send_paths` → `test:ruby`（picotest全suite）→ `test:tools`（CRuby）→ `app:test`（`swift test`。M2のT2.1で足す） | 全部exit 0 |
| `SUITE=gem FILTER=command rake test:ruby` | 1 suite・1ファイルだけ | `Total: success: N, failure: 0, exception: 0, crash: 0, crash in loading: 0, skip: 0` |

picotestの出力の最後は`Total: success: N, failure: 0, exception: 0, crash: 0, crash in loading: 0, skip: 0`の形になる（`picotest/runner.rb:230`）。以下、この行を「picotestの合格行」と呼ぶ。

### 2.4 テストの仕組み（stackchan方式）

- テストVMはBLEを含まない（`build_config/picoruby-test.rb`。stackchanの同名ファイルと同じ中身で、build名は`host-picotest`）。
- gemはテストVMに焼かない。CRubyのorchestrator（`test/picotest/harness.rb`）が、suiteごとに「VMのscriptに埋め込むsourceの列」を持ち、`Picotest::Runner.new(dir, load_files:)`に渡す。
- suite:
  - `gem`: dir `mrbgems/picoruby-phomemo-thermal-printer/test`。load_filesは`mrblib/**/*.rb`（sort順）、`ports/darwin/packet.rb`、`test/mock/fake_transport.rb`。`ports/darwin/transport.rb`は入れない（`< BLE`のため）。
  - `cli`: dir `test/cli`。load_filesは`gem`と同じ列 + `cli/phomemo_cli.rb`。
- `test:tools`はCRubyのminitest（`test/tools/*_test.rb`）。`tools/`と`bin/`のCRuby scriptを対象にする。

### 2.5 gemの`ports/darwin`をdarwinのビルドだけに入れる仕掛け（設計書§11で任されたもの）

picorubyのvendor treeに、`ports/`配下にRubyを置くgemの前例は無い（`find …/mrbgems -path "*/ports/*" -name "*.rb"`で、test/とext/を除いて0件）。`ports/`の仕組みはCだけを拾い（`lib/mruby/gem.rb:80-90`、`lib/picoruby/gem.rb:19-31`）、しかも`conf.ports`を書かないhostビルドでは`effective_ports`が`["posix"]`になるので、`ports/darwin`は選ばれない。

そこで設計書§5.1.1の「最小の仕掛け」を採る。`mrbgem.rake`で次の1行を書く。`@rbfiles`はmrbgem.rakeのblockより前に`mrblib/**/*.rb`で埋まる（`lib/mruby/gem.rb:62`、blockの評価は`:106`）ので、後ろに足せばmrblibの後に読まれる。

```ruby
spec.rbfiles.concat(Dir.glob("#{dir}/ports/darwin/*.rb").sort) if build.darwin?
```

### 2.6 トランスポート契約（設計書§5.1.1の6操作）

`sig/phomemo_thermal_printer.rbs`に`interface _Transport`として書き、これを契約の正にする。

| 操作 | メソッド | 戻り値 |
|---|---|---|
| 1. 名前の前方一致で探して接続 | `connect(name_prefix, timeout_ms)` | 見つかって接続できたらtrue |
| 2. `ff00`/`ff02`/`ff03`の確認 | `gatt_report` | `{"service"=>bool, "write"=>bool, "notify"=>bool}` |
| 3. notifyの購読 | `subscribe(settle_ms)` | 購読を要求できたらtrue（darwinは完了を知れないので、届くかどうかは事前確認の応答で判定する） |
| 4. 1チャンクのwrite | `write_chunk(bytes)` | なし |
| 5. 届いたnotifyの取り出し（ブロックしない） | `poll_notifications` | 届いた値（String）のArray。切断を検知していたらnil |
| 6. 切断 | `disconnect` | なし（darwinは何もしない） |

時計と待ちは注入する: `clock.now_ms`と`sleeper.sleep_ms(ms)`。製品では`Machine.board_millis`（`picoruby-machine/src/mruby/machine.c`にある）と`Kernel#sleep_ms`（rootの`sleep_ms`はschedulerに戻るので、BLEのポンプも回る。picoruby-ble-darwin.md §3.2）を包む。

### 2.7 CLIの外形（T1.10で実装する。アプリとskillの前提）

```
bin/phomemo-print [--device T02] [--density 4] [--chunk 128] [--interval 20]
                  [--result PATH] [--dry-run] PBMファイル
bin/phomemo-print --status [--device T02] [--result PATH]
```

- `--chunk`は20〜182、`--interval`は10〜1000、`--density`は1〜5。範囲外はusageエラー。182を超えるチャンクは作れない（設計書§8.1 #2）。
- 結果JSON（`--result`のパスへ、一時ファイルに書いてからrenameする）:

```json
{
  "version": 1,
  "mode": "print",
  "ok": true,
  "error": null,
  "exit_code": 0,
  "hint": null,
  "warnings": [],
  "status": {"battery": 83, "paper": "ok", "cover": "closed", "temperature": "normal",
             "firmware": "3.0.7", "serial": "Q114E48T2580915", "auto_off": 12},
  "job": {"rows": 2400, "blocks": 10, "bytes": 115259, "chunks": 901,
          "chunk_size": 128, "interval_ms": 20, "density": 4},
  "notify": {"acks": 901, "max_write": 182, "events": ["1a0689", "1a0f0c"]},
  "completion": {"state": "notified", "after_send_ms": 2310},
  "elapsed_ms": 21034
}
```

- `mode`: `print` / `status` / `dry_run`。`notify.events`は`01 01`以外の通知のhex。
- `warnings`: `status_partial`（事前確認の4つのうち、電池か温度の応答が来なかった）、`ack_mismatch`（`acks`が`chunks`より少ない）、`completion_unconfirmed`（`1a 0f 0c`が来ないまま時間の上限で終えた）、`battery_low`（10%以下）。
- error種別とexit code:

| error | exit | いつ |
|---|---|---|
| （成功） | 0 | |
| `unknown` | 1 | 未処理例外（picorubyの既定の終了コード） |
| `usage` / `invalid_input` | 2 | 引数の誤り / PBMが読めない・幅が384でない |
| `not_found` | 10 | 時間内に`T02`が見つからない。`hint`に「電源ボタンを押して起こす」「公式アプリの接続を切る」 |
| `wrong_device` | 11 | `ff00`/`ff02`/`ff03`が揃わない。何も送らない |
| `busy` | 12 | 別のCLIがロックを持っている。待たずに失敗する |
| `timeout` | 13 | 接続・発見が時間内に終わらない |
| `disconnected` | 14 | 送信中に切断を検知した |
| `status_unavailable` | 15 | `--status`で、ペアリングの再試行後も応答が1つも来ない。印刷では、紙かカバーの応答が欠けたとき（1つも来ない場合を含む）。印刷では何も送らない |
| `paper_out` / `cover_open` / `overheat` / `low_battery` | 20〜23 | 事前確認か送信中の通知。`low_battery`は5%以下 |
| `print_failed` / `canceled` | 30 / 31 | `1a 0f xx`（xx ≠ 0c）/ `1a 0b b8` |

- 排他: `/tmp/phomemo-print.lock`を`File#flock(File::LOCK_EX | File::LOCK_NB)`で取る（mruby-ioに`flock`がある: `mruby-io/src/file.c:661`）。ロックファイルには前回の終了時刻（ms）を書き、1.5秒経っていなければ残りを待ってから接続する（設計書§5.2、§6.6）。

### 2.8 印刷セッションの流れ（設計書§6.4〜6.7）

1. `connect`。見つからなければ`not_found`。
2. `gatt_report`。揃わなければ`wrong_device`で、何も書かない。
3. `subscribe(200)`。
4. 事前確認: `1f 11 11`（紙）、`1f 11 12`（カバー）、`1f 11 08`（電池）、`1f 11 13`（温度）を書き、最大1500msの間、20msごとに`poll_notifications`する。4つ揃えば次へ。紙切れ・カバー開・過熱・5%以下なら、ジョブを送らずにエラー。1つも来なければ、6000ms待ってCCCDを書き直してもう一度問い合わせる。そのあとで紙かカバーの応答が欠けていれば、何も送らずに`status_unavailable`で終える。電池か温度だけが欠けていれば、`status_partial`の警告を付けて続ける。
5. 送信: `Job`のsegment（前置き → ブロック → 後置き）を`Command.allowed?`で確かめてから`Chunker`に入れ、出てきたチャンクを`interval_ms`空けて`write_chunk`する。チャンク長は`min(--chunk, 02 b6 00の値)`。writeのたびに`poll_notifications`し、nilなら`disconnected`、紙切れ・カバー開・過熱の通知なら送信をやめてエラー。
6. 完了待ち: 最後のwriteからの経過を測る。`1a 0f 0c`を受け取り、かつ2000ms経ったら終える（`completion.state = "notified"`）。上限`max(2000, rows × 1000 ÷ 48 + 2000)` ms（行数 ÷ 8 mm ÷ 6 mm/s）を過ぎたら、`completion_unconfirmed`の警告を付けて終える。`1a 0f xx`は`print_failed`、`1a 0b b8`は`canceled`。
7. `disconnect`して、プロセスを終える（darwinではプロセスの終了が切断）。

## 3. M0 spike（捨てる前提）

**状態: 完了。** 結果は`docs/research/m0-spike-results.md`にある。判定はT0.9の節に書いた。

M1以降は、M0の結果の次の項目に依存する。

| 項目 | 中身 | 効く先 |
|---|---|---|
| R0-1 | 使った`port-darwin`のcommit | `t02-device-notes.md`（T1.16）、`vendor.rake`の記録形式（T1.1） |
| R0-2 | `build_config/darwin-thermal-printer.rb`（`hal-task-darwin`入り）でビルドが通るか。通すのに要った変更 | T1.1、T1.2 |
| R0-3 | TCCの4経路（直接exec / `.app`+`open -W -a` / `-sectcreate` / アプリが同梱のpicorubyを子プロセスで起動）の可否。通った経路でstdoutとexit codeが取れるか | T1.12（CLIの起動経路）、T2.11（アプリからの呼び出し）、T2.13（アプリbundle） |
| R0-4 | GATTダンプ: アドバタイズ名の実物、`ff00`/`ff02`/`ff03`の有無、`ff01`のプロパティ、`ff03`のCCCD（合成か実物か）、発見時の全readで副作用が無いか | T1.9、チェックリスト#1・#15 |
| R0-5 | CCCD購読でnotifyが届くか。ペアリングが要るか | T1.8の`status_unavailable`経路の重み、T1.15の段取り、チェックリスト#13 |
| R0-6 | 接続直後に来た通知（`01 01`、`02 b6 00`）の実物 | T1.5、T1.8、チェックリスト#2 |

### T0.9 M0の結果の判定（opus）

- 目的: `docs/research/m0-spike-results.md`を読み、R0-1〜R0-6のそれぞれに「確定 / 未確定」を付け、T1.9・T1.12・T2.11・T2.13で採る形を1つに決める。
- 触るファイル: なし（判定は親への報告で返す。計画書の更新は親が行う）。
- 依存: M0の完了。
- 判定の規則: R0-3は、アプリの経路に「4（子プロセス）」、ターミナルの経路に「2か3」を採る（設計書§5.2）。4が通らなければ、アプリも2を使う。どれも通らなければ、ユーザーに戻す。R0-5でnotifyにペアリングが要るなら、利用手順（README）に「初回にシステム設定でペアリング」を足すことを決める。
- 実機: 不要（M0で済んでいる）。

#### T0.9の判定（監督が`m0-spike-results.md`の生出力を読んで下した。すべて実測に基づく）

| 項目 | 判定 | 採る形 |
|---|---|---|
| R0-1 | 確定 | R2P2-darwin `08986d9`、port-darwin `31de548`。`build/port-darwin.commit`に記録する |
| R0-2 | 確定 | `hal-task-darwin`入りのconfigでビルドが通る（約1分36秒）。`picoruby`は`libPicoBLEDarwin.dylib`に絶対パスのrpathで依存する。vendor treeの無い所へ配る`.app`はdylibの同梱とrpath書き換えが要る（T2.13） |
| R0-3 | 確定 | ターミナルからのCLIは**経路1（許可済みターミナルからの直接exec）**。stdin・終了コードが使える。経路3（`-sectcreate`）はTCCの識別に効かないので採らない。経路2（`open -W -a`）は終了コードが消える。アプリからの印刷は**経路4（同梱ランチャー`.app`が子の`picoruby`を起動）**。許可後にscanが通ることを実測した。結果はJSONファイルで受け取る。未許可のscanはクラッシュせず0台になるので、CLIは「0台」を権限未許可の可能性つきで結果に書く（`not_found`の`hint`） |
| R0-4 | 確定 | 広告は`complete_local_name: "T02"`のみ（サービスUUIDは載らない）。サービスは`ff00`の1つで、`ff01`は read（値は空）、`ff02`は write と write without response（props `0x0c`）、`ff03`は notify（CCCD `2902`、初期値`00 00`）。名前の前方一致で接続できる。ATT MTUは527 |
| R0-5 | 確定 | **notifyにペアリングが要る。** 未ペアリングでは最初のCCCD書き込みが`LE_ATT_ERROR_INSUFFICIENT_AUTHENTICATION`になり、notifyは0件。macOSの「Just Works」確認が出て、受理後にペアリングが成立する（成立はCCCD書き込みの約5秒後）。ペアリング後は同じ手順で購読が通る。T1.8の購読は「事前確認の応答が1つも来なければ、6000ms待ってCCCDを書き直し、もう一度待つ。それでも来なければ`status_unavailable`」とする。READMEに「初回はmacOSのペアリング確認を受理する」を足す（T2.17）。このMacはT02とペアリング済みなので、実機セッションでは初回ペアリングは起きない。再現したいときは、システム設定の「Bluetooth」からT02を削除する |
| R0-6 | 確定 | 購読だけで、約60ms後に`01 01`、`02 b6 00`（182）、`1a 3b 04 40 00 00 00`の3件が20ms間隔で届く。`1a 3b …`は設計書に無い通知。**decoderは未知の`1a xx`を捨てずに`unknown`として記録し、エラーにしない**（T1.5）。`01 01`は購読時にも来るので、write回数との突き合わせ（チェックリスト#3）は購読時の1件を引いて数える（T1.8、T1.16） |

## 4. M1 gem + CLI

完了ゲート（設計書§8）: テストパターンのPBMと写真のPBMが実機で正しく印字される。`--status`が動く。共通層のテストがBLEなしのhost VMで通る。§8.1のチェックリスト15項目すべてに、結果、「v1では使わない」、または「未実施（紙の浪費を避けるため。理由と、確認する時期）」が記録されている。

依存の形:

```
T1.1 → T1.2 → 並列群A {T1.3, T1.4, T1.5, T1.6, T1.10a, T1.11}
T1.3 → T1.7 → T1.8 → T1.10b → T1.12 → T1.13（opus） → T1.14 → T1.15（実機） → T1.16 → ゲート
T1.6 + R0-4/5/6 → T1.9 ─┘（T1.13の前に）
T2.4（M2の画像ディザ）→ T1.14（写真PBMを作るため。M2から前倒しで走らせる）
```

### T1.1 repoの基盤: rakelib、テストVM、harness

- 目的: M0のRakefileを`rakelib/`に分け、テストVMとpicotestのharnessを作って、空のsuiteで`rake test`が通る状態にする。
- 触るファイル: `Rakefile`、`rakelib/vendor.rake`、`rakelib/vm.rake`、`rakelib/test.rake`、`build_config/picoruby-test.rb`、`test/picotest/harness.rb`、`mise.toml`、`.gitignore`、`CLAUDE.md`（「テスト」節を足す。コマンドだけ）。
- 依存: M0の完了（`Rakefile`と`build_config/`をM0が書いているため）、R0-2。
- 担当: sonnet。
- 手順:
  1. `Rakefile`は定数（`ROOT`、`RD`、`PICORUBY_SRC`、`TEST_VM`）とPATHの調整（`/usr/bin`とRubyのbindirを先頭に）だけにする。M0の`vendor:setup`と`vm:build`を`rakelib/`へ移す。`vm:build_embed`はR0-3で経路3を採らないなら消す。
  2. `vendor:setup`/`vendor:refresh`の最後で`git -C vendor/R2P2-darwin/vendor/picoruby rev-parse HEAD`を`build/port-darwin.commit`に書き、`[vendor] port-darwin <sha>`と出す。
  3. `build_config/picoruby-test.rb`はstackchanの同名ファイルをそのまま写す。
  4. `test/picotest/harness.rb`はstackchanのharnessを手本に、§2.4の`gem`と`cli`のsuiteだけを持つ。存在しないload_fileは列から外す（gemの中身が無い段階でも走るように）。
  5. `test:ruby`は`picotest:build`をVMが無いときだけ呼び、`PicotestHarness.run(filter: ENV["FILTER"], suite: ENV["SUITE"])`のエラー数をexit codeにする。
- TDD: このタスクはテストの土台なので、失敗するテストは次のスモークで代える。`mrbgems/picoruby-phomemo-thermal-printer/test/harness_smoke_test.rb`に`assert_equal 2, 1 + 1`を1件置いてgreenを見たあと、`assert_equal 3, 1 + 1`に変えてredになること（failure: 1）を一度確かめ、元に戻す。スモークはT1.2で消す。
- 検証:
  - `rake picotest:build` → `build/picotest/host-picotest/bin/picoruby`が存在する（`ls -la`で確認）。
  - `rake test:ruby` → picotestの合格行（success: 1）。exit 0。
  - `rake vendor:refresh`はここでは叩かない（port-darwinの先頭が動くため、T1.15の直前に1回だけ叩く）。
- commitのWhy: 「M0のspikeが作ったビルドの段取りを、タスクごとのファイルに分けて、テストVMを足した。以後のタスクが同じcheckoutで並列に走るとき、Rakefileを取り合わないようにするため。」

### T1.2 gemの骨格と製品VMへの組み込み

- 目的: gemのディレクトリ、`mrbgem.rake`、名前空間とエラークラス、トランスポート契約のRBSを置き、製品VMに焼けることを確かめる。
- 触るファイル: `mrbgems/picoruby-phomemo-thermal-printer/{mrbgem.rake, mrblib/phomemo_thermal_printer.rb, sig/phomemo_thermal_printer.rbs, test/namespace_test.rb}`、`build_config/darwin-thermal-printer.rb`（`conf.gem gemdir:`を1行足す）。スモークテストを消す。
- 依存: T1.1。
- 担当: sonnet。
- `mrbgem.rake`（ASCIIのみ）:

```ruby
MRuby::Gem::Specification.new('picoruby-phomemo-thermal-printer') do |spec|
  spec.license = 'MIT'
  spec.author  = 'bash0C7'
  spec.summary = 'Phomemo T02 thermal printer over BLE'
  spec.require_name = 'phomemo_thermal_printer'
  spec.add_dependency 'picoruby-ble'
  spec.rbfiles.concat(Dir.glob("#{dir}/ports/darwin/*.rb").sort) if build.darwin?
end
```

- `mrblib/phomemo_thermal_printer.rb`: `module PhomemoThermalPrinter`と、`Error < StandardError`、`FormatError < Error`。
- RBS: §2.6の`interface _Transport`、`_Clock`（`now_ms`）、`_Sleeper`（`sleep_ms`）。
- TDD:
  - What: 「名前空間とエラー階層がある」。

```ruby
class NamespaceTest < Picotest::Test
  def test_format_error_is_a_gem_error
    assert_equal PhomemoThermalPrinter::Error, PhomemoThermalPrinter::FormatError.superclass
  end
end
```

  - red（定数が無い）→ 最小実装 → green。
- 検証:
  - `SUITE=gem rake test:ruby` → picotestの合格行。
  - `rake vm:build` → exit 0。gemのmrblibがビルドでcompileされる（構文エラーはここで落ちる）。
  - `vendor/R2P2-darwin/build/host/bin/picoruby -e 'p PhomemoThermalPrinter::Error'` → `PhomemoThermalPrinter::Error`。BLEを初期化しないので、TCCに触れずに直接実行できる見込み。SIGABRTで落ちたら、`-e`の検証をやめ、T1.12の経路で同じことを確かめる（落ちたことを報告に書く）。
- commitのWhy: 「gemを製品VMに焼ける最小の形にした。ports/darwinのRubyをdarwinのビルドだけに入れる仕掛けを、picorubyに前例が無いのでmrbgem.rakeの1行にした。」

### 並列群A（T1.2の後。互いにファイルが重ならない）

#### T1.3 allowlistつきコマンド組み立てと送信経路の検査

- 目的: §1.1のallowlistだけを組み立てる`Command`と、segmentの検査`Command.allowed?`を作る。BLEへのwriteが2か所だけにあることを機械で確かめるrakeタスクを置く。
- 触るファイル: `mrblib/phomemo_thermal_printer/command.rb`、`test/command_test.rb`、`test/allowlist_test.rb`、`rakelib/check.rake`（`check:send_paths`。`test.rake`の`test`の前提に足すのは、このファイルの中で`task test: "check:send_paths"`と書く）。
- 依存: T1.2。
- 担当: sonnet。
- API: `Command.initialize_printer`、`Command.align(n)`、`Command.density(n)`、`Command.raster_header(rows)`、`Command.feed(n)`、`Command.query(op)`、`Command.allowed?(segment)`。範囲外の引数は`ArgumentError`。
- TDD（テストを先に全部書いてredを見る）:

```ruby
class CommandTest < Picotest::Test
  def c; PhomemoThermalPrinter::Command; end

  def test_preamble_bytes_follow_the_ha_minimal_sequence_with_density
    assert_equal "\x1b\x40", c.initialize_printer
    assert_equal "\x1b\x61\x00", c.align(0)
    assert_equal "\x1f\x11\x02\x04", c.density(4)
  end

  def test_raster_header_writes_the_actual_row_count_little_endian
    assert_equal "\x1d\x76\x30\x00\x30\x00\x01\x00", c.raster_header(1)
    assert_equal "\x1d\x76\x30\x00\x30\x00\xff\x00", c.raster_header(255)
  end

  def test_raster_header_rejects_zero_and_more_than_255_rows
    assert_raise(ArgumentError) { c.raster_header(0) }
    assert_raise(ArgumentError) { c.raster_header(256) }
  end

  def test_density_accepts_only_1_to_5
    assert_raise(ArgumentError) { c.density(0) }
    assert_raise(ArgumentError) { c.density(6) }
  end

  def test_feed_is_esc_d_n
    assert_equal "\x1b\x64\x03", c.feed(3)
  end
end

class AllowlistTest < Picotest::Test
  KNOWN = [0x07, 0x08, 0x09, 0x0e, 0x11, 0x12, 0x13]

  def test_status_query_can_be_built_only_for_the_seven_known_opcodes
    op = 0
    while op <= 0xff
      if KNOWN.include?(op)
        assert_equal "\x1f\x11" + [op].pack("C"), PhomemoThermalPrinter::Command.query(op)
      else
        assert_raise(ArgumentError) { PhomemoThermalPrinter::Command.query(op) }
      end
      op += 1
    end
  end

  def test_allowed_rejects_the_commands_the_research_marks_dangerous
    ["\x1f\x11\x14", "\x1f\x11\x38", "\x1f\x11\x63", "\x1b\x4e\x04\x01", "\x1b\x37\x07\x80\x02",
     "\x1d\x7c\x01", "\x1d\x67\x6e", "SSSGETSN\r\n", "\x1f\x11\x02\x00", "\x1f\x11\x02\x06",
     "\x1b\x61\x03", "\x1d\x76\x30\x01\x30\x00\x01\x00" + "\x00" * 48].each do |seg|
      assert_false PhomemoThermalPrinter::Command.allowed?(seg)
    end
  end

  def test_allowed_requires_exactly_48_bytes_per_declared_row
    header = PhomemoThermalPrinter::Command.raster_header(2)
    assert PhomemoThermalPrinter::Command.allowed?(header + "\x00" * 96)
    assert_false PhomemoThermalPrinter::Command.allowed?(header + "\x00" * 95)
    assert_false PhomemoThermalPrinter::Command.allowed?(header + "\x00" * 97)
  end

  def test_every_builder_output_is_allowed
    c = PhomemoThermalPrinter::Command
    [c.initialize_printer, c.align(0), c.align(2), c.density(1), c.density(5),
     c.feed(0), c.feed(255), c.query(0x13)].each { |seg| assert c.allowed?(seg) }
  end
end
```

- `check:send_paths`: CRubyで`mrbgems/`と`cli/`の`*.rb`をgrepし、`write_value_of_characteristic`が`ports/darwin/transport.rb`の外に、`write_chunk`が`ports/darwin/transport.rb`・`session.rb`・`test/mock/fake_transport.rb`の外にあればabortする。まだファイルが無い段階でも通る。
- 検証: `SUITE=gem FILTER=command rake test:ruby`と`FILTER=allowlist`でpicotestの合格行。`rake check:send_paths` → `[check] send paths ok`、exit 0。
- commitのWhy: 「プリンターを壊さないため、組み立てられるコマンドをallowlistに閉じ、その外のバイト列を作れないことと、BLEへの書き込み口が増えていないことを、テストとrakeで縛った。」

#### T1.4 PBMの行ブロックreader

- 目的: PBM P4（幅384）を、ヘッダの後を最大255行ずつ読み、`[rows, bytes]`を順に返す。ファイル全体を1本のStringにしない。
- 触るファイル: `mrblib/phomemo_thermal_printer/pbm_reader.rb`、`test/pbm_reader_test.rb`、`test/fixtures/stripes-600.pbm`（384×600。行ごとに`ff`と`00`が交互。テストのsetupでは作らず、repoに置く小さいfixture）。
- 依存: T1.2。
- 担当: sonnet。
- 事実: PBM P4は1が黒、MSBが左、行はbyte境界で詰める。384 ÷ 8 = 48なので、P4の1行はそのまま`GS v 0`の1行になる（変換不要）。
- API: `PbmReader.new(io, max_rows: 255)`、`#width`、`#height`、`#next_block`（`[rows, bytes]`かnil）。`io`は`read(n)`だけを使う（ヘッダは`read(1)`で読む）。
- TDD:

```ruby
class PbmReaderTest < Picotest::Test
  class ChunkIO
    attr_reader :max_read
    def initialize(s); @s = s; @pos = 0; @max_read = 0; end
    def read(n)
      @max_read = n if n > @max_read
      return nil if @pos >= @s.bytesize
      r = @s.byteslice(@pos, n); @pos += r.bytesize; r
    end
  end

  def pbm(rows, comment: false)
    head = comment ? "P4\n# made by test\n384 #{rows}\n" : "P4\n384 #{rows}\n"
    body = ""
    i = 0
    while i < rows
      body << ((i % 2 == 0) ? "\xff" : "\x00") * 48
      i += 1
    end
    head + body
  end

  def test_600_rows_come_out_as_255_255_90
    r = PhomemoThermalPrinter::PbmReader.new(ChunkIO.new(pbm(600)))
    assert_equal 384, r.width
    assert_equal 600, r.height
    sizes = []
    while (b = r.next_block)
      assert_equal b[0] * 48, b[1].bytesize
      sizes << b[0]
    end
    assert_equal [255, 255, 90], sizes
  end

  def test_blocks_concatenate_to_the_original_raster
    src = pbm(600, comment: true)
    r = PhomemoThermalPrinter::PbmReader.new(ChunkIO.new(src))
    out = ""
    while (b = r.next_block)
      out << b[1]
    end
    assert_equal src.byteslice(src.bytesize - 600 * 48, 600 * 48), out
  end

  def test_reads_at_most_one_block_at_a_time
    io = ChunkIO.new(pbm(600))
    r = PhomemoThermalPrinter::PbmReader.new(io)
    while r.next_block; end
    assert io.max_read <= 255 * 48
  end

  def test_width_other_than_384_is_a_format_error
    assert_raise(PhomemoThermalPrinter::FormatError) do
      PhomemoThermalPrinter::PbmReader.new(ChunkIO.new("P4\n383 1\n" + "\x00" * 48))
    end
  end

  def test_truncated_raster_is_a_format_error
    r = PhomemoThermalPrinter::PbmReader.new(ChunkIO.new(pbm(10).byteslice(0, 9 + 48 * 9)))
    assert_raise(PhomemoThermalPrinter::FormatError) { while r.next_block; end }
  end

  def test_p1_ascii_pbm_is_a_format_error
    assert_raise(PhomemoThermalPrinter::FormatError) do
      PhomemoThermalPrinter::PbmReader.new(ChunkIO.new("P1\n384 1\n"))
    end
  end
end
```

  - fixtureのファイル（`stripes-600.pbm`）は、CLIのテスト（T1.10b）とSwiftのPBM writer（T2.1）の契約に使う。
- 検証: `SUITE=gem FILTER=pbm_reader rake test:ruby` → picotestの合格行。
- commitのWhy: 「PBMを行ブロック単位で読むことで、ジョブ全体をメモリに持たない形（マイコンを見据えたユーザー決定）にした。P4の行はGS v 0の行と同じ並びなので、変換せずに流す。」

#### T1.5 ステータスのdecode（連結・分割された通知を含む）

- 目的: `ff03`の通知のバイト列を、イベントの列にdecodeする。1回の通知に複数の`1a …`が連結されていても、1つの応答が2回に分かれて来ても扱う。
- 触るファイル: `mrblib/phomemo_thermal_printer/status.rb`、`test/status_test.rb`。
- 依存: T1.2。R0-6は、実物の通知をテストの入力に1件足すためにだけ使う（無くても進める）。
- 担当: sonnet。
- 種別の長さ（`1a`の後ろ、種別byteを含む。protocol §11.1、TIMの表）: `03`:2、`04`:2、`05`:2、`06`:2、`07`:4、`08`:16、`09`:2、`0b`:2、`0e`:2、`0f`:2、`16`:2、`17`:2、`1d`:2、`20`:2、`35`:2、`3b`:6。
- API: `StatusDecoder.new`、`#feed(bytes)` → イベントのArray。足りないぶんはbufferに残し、次の`feed`で続ける。
- イベント: `[:ack]`、`[:max_write, 182]`、`[:battery, 83]`（`a1`/`a2`/`a3`/`a4`は10/5/3/0）、`[:paper, :ok|:out]`、`[:cover, :closed|:open]`、`[:temperature, :normal|:overheat]`、`[:firmware, "3.0.7"]`、`[:serial, "Q114E48T2580915"]`、`[:auto_off, 12]`、`[:print_complete]`、`[:print_failed, xx]`、`[:canceled]`、`[:unknown, "hex"]`。
- TDD:

```ruby
class StatusTest < Picotest::Test
  def decode(s); PhomemoThermalPrinter::StatusDecoder.new.feed(s); end

  def test_the_t02_log_from_jef_decodes_in_order
    assert_equal [[:ack], [:max_write, 182]], decode("\x01\x01\x02\xb6\x00")
    assert_equal [[:paper, :ok], [:cover, :closed]], decode("\x1a\x06\x89\x1a\x05\x98")
    assert_equal [[:battery, 83]], decode("\x1a\x04\x53")
    assert_equal [[:firmware, "3.0.7"]], decode("\x1a\x07\x03\x00\x07")
    assert_equal [[:serial, "Q114E48T2580915"]], decode("\x1a\x08Q114E48T2580915")
    assert_equal [[:print_complete]], decode("\x1a\x0f\x0c")
  end

  def test_majority_meanings_win_over_minority_readings
    assert_equal [[:cover, :open]], decode("\x1a\x05\x99")
    assert_equal [[:paper, :out]], decode("\x1a\x06\x88")
    assert_equal [[:temperature, :overheat]], decode("\x1a\x03\xa9")
  end

  def test_battery_special_values_map_to_percent
    assert_equal [[:battery, 10], [:battery, 5], [:battery, 3], [:battery, 0]],
                 decode("\x1a\x04\xa1\x1a\x04\xa2\x1a\x04\xa3\x1a\x04\xa4")
  end

  def test_a_reply_split_across_two_notifications_is_joined
    d = PhomemoThermalPrinter::StatusDecoder.new
    assert_equal [], d.feed("\x1a\x07\x03")
    assert_equal [[:firmware, "3.0.7"]], d.feed("\x00\x07")
  end

  def test_failure_and_cancel_are_distinct_events
    assert_equal [[:print_failed, 1]], decode("\x1a\x0f\x01")
    assert_equal [[:canceled]], decode("\x1a\x0b\xb8")
  end

  def test_known_length_unknown_meaning_types_are_skipped_as_unknown
    assert_equal [[:unknown, "1a3b0102030405"], [:paper, :ok]], decode("\x1a\x3b\x01\x02\x03\x04\x05\x1a\x06\x89")
  end

  def test_an_unparseable_byte_becomes_unknown_and_resets_the_buffer
    d = PhomemoThermalPrinter::StatusDecoder.new
    assert_equal [[:unknown, "ee0102"]], d.feed("\xee\x01\x02")
    assert_equal [[:paper, :ok]], d.feed("\x1a\x06\x89")
  end
end
```

- 検証: `SUITE=gem FILTER=status rake test:ruby` → picotestの合格行。
- commitのWhy: 「プリンターの状態を、紙切れ・カバー開・過熱・電池・印字完了の判断に使うため。実機で連結や分割が起きるかは不明（調査書§11.1）なので、両方に備えた。」

#### T1.6 `ports/darwin`の純粋な部分: パケットのdecodeと切断判定

- 目的: picoruby-bleのdarwin版のパケットの形を知るコードのうち、無線なしで確かめられる部分を、`BLE`を参照しないmoduleにして単体テストする。
- 触るファイル: `ports/darwin/packet.rb`、`test/darwin_packet_test.rb`。
- 依存: T1.2。R0-4は、テストの`services`に実物の形を1件足すために使う（無くても進める）。
- 担当: sonnet。
- 先に読むもの: `vendor/R2P2-darwin/vendor/picoruby/mrbgems/picoruby-ble/mrblib/{ble_central.rb, ble_utils.rb, ble_advertising_report.rb}`（`services`の要素の形、`uuid128`の表現、`reports`のkey）、stackchanの`mrbgems/picoruby-stackchan-controller/mrblib/stackchan-controller/{radio.rb, gatt.rb}`、`docs/research/picoruby-ble-darwin.md` §3.5・§3.6・§9。
- API（`module PhomemoThermalPrinter::Darwin::Packet`）:
  - `disconnect?(pkt)`: `[0x05, …]`か`[0x3E, _, 0x05]`。
  - `notification(pkt)`: `0xA7`なら`[value_handle, value]`（handleはoffset 8のLE16、長さはoffset 10のLE16、値はoffset 12から）。それ以外はnil。
  - `name_matches?(reports, prefix)`: `complete_local_name`か`shortened_local_name`が`prefix`で**始まる**（`AdvertisingReport#name_include?`は部分一致なので使わない）。
  - `uuid128_for(short)`: 16bit UUIDを、`services`の`uuid128`と同じ表現に直す。
  - `gatt_report(services)`: `{"service"=>…, "write"=>…, "notify"=>…, "write_handle"=>…, "cccd_handle"=>…}`。`ff03`のCCCDは、descriptorのUUID `0x2902`で引く。
- TDD:

```ruby
class DarwinPacketTest < Picotest::Test
  def p; PhomemoThermalPrinter::Darwin::Packet; end

  def test_darwin_disconnect_shape_is_detected
    assert p.disconnect?([0x3E, 0x01, 0x05].pack("C*"))
  end

  def test_btstack_and_esp32_disconnect_shape_is_detected
    assert p.disconnect?([0x05, 4, 0x40, 0x00, 0x00, 0x13].pack("C*"))
  end

  def test_connection_complete_is_not_a_disconnect
    assert_false p.disconnect?([0x3E, 0x01, 0x01, 0x00, 0x40, 0x00].pack("C*"))
  end

  def test_notification_packet_yields_handle_and_value
    value = "\x1a\x06\x89"
    pkt = [0xA7, 12 + 3, 0, 0, 0, 0, 0, 0, 0x2a, 0, 3, 0].pack("C*") + value
    assert_equal [0x2a, value], p.notification(pkt)
  end

  def test_non_notification_packet_is_nil
    assert_nil p.notification([0xA0, 0].pack("C*"))
  end

  def test_name_is_matched_by_prefix_not_substring
    assert p.name_matches?({complete_local_name: "T02"}, "T02")
    assert p.name_matches?({complete_local_name: "T02E"}, "T02")
    assert_false p.name_matches?({complete_local_name: "MyT02"}, "T02")
    assert_false p.name_matches?({}, "T02")
  end

  def test_phomemo_gatt_is_ready
    r = p.gatt_report(phomemo_services)
    assert_equal true, r["service"]
    assert_equal true, r["write"]
    assert_equal true, r["notify"]
  end

  def test_funny_print_lx_named_t02_is_not_ready
    r = p.gatt_report(funny_print_services)
    assert_equal false, r["service"]
  end
end
```

  - `phomemo_services`と`funny_print_services`は、`ble_central.rb`の`services`の形（`{start_handle:, end_handle:, uuid128:, characteristics: [{value_handle:, properties:, uuid128:, descriptors: [{handle:, uuid128:}]}]}`）で、テストクラスの中のメソッドとして合成する。Funny Print LX系はサービス`ffe6`、write `ffe1`、notify `ffe2`（設計書§6.1）。
- 検証: `SUITE=gem FILTER=darwin_packet rake test:ruby` → picotestの合格行。
- commitのWhy: 「port-darwinの先頭追従で壊れうるパケットの形の知識を、BLEなしで回帰検出できる場所に切り出した。名前がT02の別機種に何も送らないため、GATTの判定をここでテストする。」

#### T1.10a CLIの部品: 引数、ロック、結果ファイル、exit code

- 目的: CLIのうちBLEにもgemのセッションにも触らない部品を作る。後置きの`1b 64 n`のnは既定3で、チェックリスト#7のためだけに環境変数`PHOMEMO_FEED`（0〜255。allowlistの範囲）で変えられるようにする。引数には足さない（アプリは常に既定値で送る）。
- 触るファイル: `cli/phomemo_cli.rb`（`module PhomemoCLI`の`Options`、`Lock`、`ResultFile`、`EXIT_CODES`だけ）、`test/cli/options_test.rb`、`test/cli/lock_test.rb`、`test/cli/result_file_test.rb`、`test/fixtures/result_print_ok.json`、`test/fixtures/result_status_ok.json`、`test/fixtures/result_not_found.json`。
- 依存: T1.2（テストのsuite）。§2.7の外形。
- 担当: sonnet。
- TDD:

```ruby
class OptionsTest < Picotest::Test
  def parse(a); PhomemoCLI::Options.parse(a); end

  def test_defaults_follow_the_design
    o = parse(["a.pbm"])
    assert_equal "T02", o.device
    assert_equal 4, o.density
    assert_equal 128, o.chunk
    assert_equal 20, o.interval
    assert_equal "a.pbm", o.pbm
  end

  def test_chunk_above_182_is_a_usage_error
    assert_equal :usage, parse(["--chunk", "183", "a.pbm"]).error
  end

  def test_density_outside_1_to_5_and_interval_below_10_are_usage_errors
    assert_equal :usage, parse(["--density", "6", "a.pbm"]).error
    assert_equal :usage, parse(["--interval", "9", "a.pbm"]).error
  end

  def test_status_needs_no_pbm_but_print_does
    assert_nil parse(["--status"]).error
    assert_equal :usage, parse([]).error
  end

  def test_feed_comes_from_the_environment_within_esc_d_range
    assert_equal 3, PhomemoCLI::Options.parse(["a.pbm"], env: {}).feed
    assert_equal 6, PhomemoCLI::Options.parse(["a.pbm"], env: {"PHOMEMO_FEED" => "6"}).feed
    assert_equal :usage, PhomemoCLI::Options.parse(["a.pbm"], env: {"PHOMEMO_FEED" => "256"}).error
  end
end

class LockTest < Picotest::Test
  def test_a_second_holder_is_refused_without_waiting
    path = "/tmp/phomemo-print-locktest-#{Machine.board_millis}.lock"
    a = PhomemoCLI::Lock.acquire(path)
    assert_not_nil a
    assert_nil PhomemoCLI::Lock.acquire(path)
    a.release(now_ms: 1000)
    assert_not_nil PhomemoCLI::Lock.acquire(path)
  end

  def test_the_gap_since_the_last_job_is_padded_to_1500ms
    clock = FakeClock.new(10_000)
    sleeper = FakeSleeper.new(clock)
    lock = PhomemoCLI::Lock.acquire(tmp_path, last_finished_ms: 9_000)
    lock.wait_for_gap(clock, sleeper)
    assert_equal [500], sleeper.slept
  end
end

class ResultFileTest < Picotest::Test
  def test_written_keys_match_the_contract_fixture
    path = "/tmp/phomemo-result-test.json"
    PhomemoCLI::ResultFile.write(path, sample_ok_result)
    written = JSON.parse(File.open(path, "r") { |f| f.read })
    fixture = JSON.parse(File.open(fixture_path("result_print_ok.json"), "r") { |f| f.read })
    assert_equal fixture.keys.sort, written.keys.sort
    assert_false File.exist?(path + ".tmp")
  end

  def test_every_error_kind_has_a_distinct_exit_code
    codes = PhomemoCLI::EXIT_CODES.values
    assert_equal codes.size, codes.uniq.size
    assert_equal 10, PhomemoCLI::EXIT_CODES["not_found"]
  end
end
```

  - `FakeClock`/`FakeSleeper`は`test/mock/fake_transport.rb`に置く予定のものと同じ形なので、このタスクで`test/mock/fake_transport.rb`に時計と待ちだけを先に作る（トランスポート本体はT1.8で足す）。並列群AでこのファイルはT1.10aだけが触る。
  - `Machine.board_millis`がテストVMに無ければ、一意なパスの作り方を変える（報告に書く）。
- 検証: `SUITE=cli rake test:ruby` → picotestの合格行。
- commitのWhy: 「アプリがopen経由でstdoutとexit codeを受け取れない場合に備え、結果をJSONファイルで返す契約をfixtureで固定した。T02は1台にしか繋がらないので、2本目は待たずにbusyで返す。」

#### T1.11 テストパターンのPBM生成ツール

- 目的: 実機確認に使うPBMを、CRubyで決定的に作る。
- 触るファイル: `tools/make_test_pbm.rb`、`test/tools/make_test_pbm_test.rb`、`rakelib/test.rake`には触らず、`test:tools`はT1.1で`test/tools/*_test.rb`をglobする形にしてある前提。
- 依存: T1.1。
- 担当: sonnet。
- パターン（`ruby tools/make_test_pbm.rb <pattern> <out.pbm> [args]`）:
  - `topline`: 1行目から3行が黒、続けて1mm（8行）ごとに目盛り（チェックリスト#10）。
  - `ruler`: 長さ20mm（160行）、1mmごとの短い目盛りと10mmごとの長い目盛り、末尾に印（#7で紙送りを測る基準）。
  - `density`: 16段×8行（16mm）の灰色の帯（Floyd–Steinbergでなく、決定的な順序ディザ）。#8で濃度ごとに印字して比べる。
  - `chunk`: 長さ15mm（120行）の細かい格子（#2で、チャンク長ごとの欠けを見る）。
  - `topline`は12mm（96行）。
  - `label TEXT`: 5×7の小さなビットマップ文字（数字、A〜Z、`=`、`-`）でTEXTを描いた帯（約3.3mm）。`--label`で各パターンの先頭に付け、どの条件の印字かを紙で分かるようにする。
  - 255行ごとの分割は、紙の上の専用パターンでは確かめない。gemのJobとPbmReaderのテストで担保し、32mmを超える通常の印字で継ぎ目の有無を見る。
- TDD:

```ruby
class MakeTestPbmTest < Minitest::Test
  def test_every_pattern_is_a_384_wide_p4
    %w[topline ruler density chunk].each do |pat|
      data = MakeTestPbm.render(pat)
      assert data.start_with?("P4\n384 ")
      head, rows = header(data)
      assert_equal rows * 48, data.bytesize - head.bytesize
    end
  end

  def test_topline_starts_with_three_black_rows
    data = MakeTestPbm.render("topline")
    head, = header(data)
    assert_equal "\xff".b * (48 * 3), data.byteslice(head.bytesize, 48 * 3)
  end

  def test_ruler_is_20mm
    _, rows = header(MakeTestPbm.render("ruler"))
    assert_equal 160, rows
  end
end
```

  - minitestはRuby 4.0のbundled gemなので、Gemfileなしで`require "minitest/autorun"`が通る見込み。通らなければ`Gemfile`に`minitest`を足し、`bundle install`して`bundle exec`で回す（報告に書く）。
- 検証: `rake test:tools` → `0 failures, 0 errors`。exit 0。
- commitのWhy: 「チェックリストの各項目を、紙の上で条件が分かる形で確かめるため。PicoRubyには画像生成が無いので、CRubyのツールにした。」

### T1.7 ジョブとチャンク分け

- 目的: 行ブロックの列から、前置き → ブロック → 後置きのsegmentを順に作る`Job`と、segmentの連なりを決まった長さのチャンクに分ける`Chunker`を作る。
- 触るファイル: `mrblib/phomemo_thermal_printer/job.rb`、`mrblib/phomemo_thermal_printer/chunker.rb`、`test/job_test.rb`、`test/chunker_test.rb`。
- 依存: T1.3。
- 担当: sonnet。
- API: `Job.new(source, density:, feed: 3)`。`source`は`next_block`に答えるもの（`PbmReader`か、テストの配列）。`#next_segment`（Stringかnil）、`#rows`、`#blocks`、`#bytes`。`Chunker.new(size)`、`#limit(max_write)`、`#push(segment)`（満ちたチャンクのArray）、`#flush`（残り）。sizeは20〜182。
- TDD:

```ruby
class JobTest < Picotest::Test
  class Blocks
    def initialize(list); @list = list; @i = 0; end
    def next_block; b = @list[@i]; @i += 1; b; end
  end

  def all_segments(job)
    out = []
    while (s = job.next_segment)
      out << s
    end
    out
  end

  def test_two_black_rows_match_the_research_example_plus_density
    job = PhomemoThermalPrinter::Job.new(Blocks.new([[2, "\xff" * 96]]), density: 4)
    expected = "\x1b\x40\x1b\x61\x00\x1f\x11\x02\x04\x1d\x76\x30\x00\x30\x00\x02\x00" + "\xff" * 96 + "\x1b\x64\x03"
    assert_equal expected, all_segments(job).join
  end

  def test_every_segment_is_allowed
    job = PhomemoThermalPrinter::Job.new(Blocks.new([[255, "\x00" * 48 * 255], [90, "\x00" * 48 * 90]]), density: 1)
    all_segments(job).each { |s| assert PhomemoThermalPrinter::Command.allowed?(s) }
  end

  def test_no_0x0a_substitution_happens
    job = PhomemoThermalPrinter::Job.new(Blocks.new([[1, "\x0a" * 48]]), density: 4)
    assert all_segments(job).join.include?("\x0a" * 48)
  end
end

class ChunkerTest < Picotest::Test
  def test_chunks_never_exceed_the_size_and_preserve_bytes
    ch = PhomemoThermalPrinter::Chunker.new(128)
    out = ch.push("a" * 300) + ch.push("b" * 10)
    last = ch.flush
    out << last if last
    out.each { |c| assert c.bytesize <= 128 }
    assert_equal "a" * 300 + "b" * 10, out.join
  end

  def test_the_printer_reported_max_write_lowers_the_size
    ch = PhomemoThermalPrinter::Chunker.new(182)
    ch.limit(96)
    ch.push("x" * 500).each { |c| assert c.bytesize <= 96 }
  end

  def test_size_outside_20_to_182_is_rejected
    assert_raise(ArgumentError) { PhomemoThermalPrinter::Chunker.new(183) }
    assert_raise(ArgumentError) { PhomemoThermalPrinter::Chunker.new(19) }
  end
end
```

- 検証: `SUITE=gem FILTER=job rake test:ruby`、`FILTER=chunker`でpicotestの合格行。
- commitのWhy: 「ジョブを1本のStringに組まず、ブロックごとにsegmentを作って流す（ユーザー決定）。チャンク長は182を超えられない形にし、プリンターが通知した上限があればそれに従う。」

### T1.8 印刷セッションとステータスセッション、fakeトランスポート

- 目的: §2.8の流れを、トランスポート契約だけを使って書く。fakeトランスポートで、エラーの全種別と待ち方をテストする。
- 触るファイル: `mrblib/phomemo_thermal_printer/session.rb`（`PrintSession`、`StatusSession`）、`mrblib/phomemo_thermal_printer/result.rb`（`Result`。§2.7のJSONのHashを作る）、`test/mock/fake_transport.rb`（トランスポートを足す）、`test/print_session_test.rb`、`test/status_session_test.rb`。
- 依存: T1.5、T1.7、T1.10a（`test/mock/fake_transport.rb`の時計）。
- 担当: sonnet。
- FakeTransport: `FakeTransport.new(clock, found: true, gatt: READY, replies: {query => notification}, events_at_write: {n => notification}, completion_after_ms: 1500, completion: "\x1a\x0f\x0c", disconnect_at_write: nil)`。writeを`[at_ms, bytes]`で記録する。`replies`の応答は、そのqueryが書かれた次の`poll_notifications`で返す。
- TDD（What。テスト名がそのまま仕様）:

```ruby
class PrintSessionTest < Picotest::Test
  def test_not_found_writes_nothing
    t = fake(found: false)
    r = session(t).print(job(10))
    assert_equal "not_found", r.error
    assert_equal 0, t.writes.size
  end

  def test_a_t02_without_ff00_gets_nothing_at_all
    t = fake(gatt: {"service" => false, "write" => false, "notify" => false})
    r = session(t).print(job(10))
    assert_equal "wrong_device", r.error
    assert_equal 0, t.writes.size
  end

  def test_paper_out_in_the_precheck_sends_only_status_queries
    t = fake(replies: ok_replies.merge("\x1f\x11\x11" => "\x1a\x06\x88"))
    r = session(t).print(job(10))
    assert_equal "paper_out", r.error
    t.writes.each { |w| assert_equal 3, w[1].bytesize }
  end

  def test_cover_open_overheat_and_empty_battery_also_stop_before_the_job
    assert_equal "cover_open", run_with("\x1f\x11\x12" => "\x1a\x05\x99").error
    assert_equal "overheat", run_with("\x1f\x11\x13" => "\x1a\x03\xa9").error
    assert_equal "low_battery", run_with("\x1f\x11\x08" => "\x1a\x04\xa2").error
  end

  def test_the_written_job_bytes_equal_the_job
    t = fake(replies: ok_replies)
    session(t).print(job(300))
    assert_equal job_bytes(300), job_writes(t).map { |w| w[1] }.join
    t.writes_before_job.each { |w| assert PhomemoThermalPrinter::Command.allowed?(w[1]) }
  end

  def test_chunks_are_spaced_by_the_interval
    t = fake(replies: ok_replies)
    session(t, interval: 20).print(job(300))
    data = job_writes(t)
    i = 1
    while i < data.size
      assert data[i][0] - data[i - 1][0] >= 20
      i += 1
    end
  end

  def test_max_write_from_the_printer_caps_the_chunk
    t = fake(replies: ok_replies, connect_notifications: ["\x02\x60\x00"])
    session(t, chunk: 182).print(job(300))
    job_writes(t).each { |w| assert w[1].bytesize <= 96 }
  end

  def test_completion_ends_the_wait_after_at_least_2000ms
    t = fake(replies: ok_replies, completion_after_ms: 500)
    r = session(t).print(job(48))
    assert_equal "notified", r.completion_state
    assert r.after_send_ms >= 2000
    assert r.after_send_ms < 2100
  end

  def test_without_completion_the_wait_ends_at_the_cap_with_a_warning
    t = fake(replies: ok_replies, completion: nil)
    r = session(t).print(job(480))
    assert_equal true, r.ok
    assert r.warnings.include?("completion_unconfirmed")
    assert r.after_send_ms >= 12_000
  end

  def test_silence_in_the_precheck_prints_by_time_with_status_unavailable
    t = fake(replies: {}, completion: nil)
    r = session(t).print(job(48))
    assert_equal true, r.ok
    assert r.warnings.include?("status_unavailable")
    assert job_writes(t).size > 0
  end

  def test_failure_and_cancel_notifications_are_errors
    assert_equal "print_failed", run_with({}, completion: "\x1a\x0f\x01").error
    assert_equal "canceled", run_with({}, completion: "\x1a\x0b\xb8").error
  end

  def test_disconnect_while_sending_stops_writing
    t = fake(replies: ok_replies, disconnect_at_write: 5)
    r = session(t).print(job(300))
    assert_equal "disconnected", r.error
    assert job_writes(t).size <= 5
  end

  def test_cover_opened_while_sending_stops_writing
    t = fake(replies: ok_replies, events_at_write: {3 => "\x1a\x05\x99"})
    r = session(t).print(job(300))
    assert_equal "cover_open", r.error
    assert job_writes(t).size <= 4
  end
end

class StatusSessionTest < Picotest::Test
  def test_status_asks_the_seven_known_queries_in_order
    t = fake(replies: all_replies)
    r = PhomemoThermalPrinter::StatusSession.new(t, clock: t.clock, sleeper: t.sleeper).query
    assert_equal ["\x1f\x11\x08", "\x1f\x11\x11", "\x1f\x11\x12", "\x1f\x11\x13",
                  "\x1f\x11\x07", "\x1f\x11\x09", "\x1f\x11\x0e"], t.writes.map { |w| w[1] }
    assert_equal 83, r.status["battery"]
    assert_equal "3.0.7", r.status["firmware"]
  end

  def test_no_reply_at_all_is_status_unavailable
    t = fake(replies: {})
    r = PhomemoThermalPrinter::StatusSession.new(t, clock: t.clock, sleeper: t.sleeper).query
    assert_equal "status_unavailable", r.error
  end
end
```

  - ヘルパー（`fake`、`session`、`job`、`ok_replies`など）はテストクラスの中のメソッドにする。
- 検証: `SUITE=gem rake test:ruby` → picotestの合格行。`rake check:send_paths` → ok。
- commitのWhy: 「事前確認 → 送信 → 完了待ちを、トランスポート契約だけで書いた。darwinに依存しないので、BLEなしのVMで、紙切れや途中切断を含む全経路を回帰検出できる。」

### T1.9 `ports/darwin`のトランスポート

- 目的: picoruby-bleのdarwin版の上に、トランスポート契約を実装する。picoruby-bleの内部に触るコードはここだけに置く。
- 触るファイル: `ports/darwin/transport.rb`（`class PhomemoThermalPrinter::Darwin::Transport < BLE`）。
- 依存: T1.6、R0-4、R0-5、R0-6。T1.8と並列に走らせてよい（ファイルが重ならない）。
- 担当: sonnet。
- 手本: stackchanの`radio.rb`（`pop_and_dispatch`、`disconnect_packet?`、`advertising_report_callback`）と`central.rb`（`connect_and_discover`、`subscribe`の`settle`、`send_chunk`）。`docs/research/picoruby-ble-darwin.md` §5.6と§9を全部読む。
- 実装の要点:
  - `connect(prefix, timeout_ms)`: `@target = nil`、`@services.clear`、`scan(timeout_ms: timeout_ms, stop_state: :TC_IDLE)`。`advertising_report_callback`で`Packet.name_matches?(report.reports, prefix)`なら`connect(report)`。最初に見つけた1台に繋ぐ（2台以上あっても待たない。別機種への誤接続は`gatt_report`で止める）。
  - `scan`を2回呼ばない（2回目は接続をcancelする。§3.6）。`scan`の後は、`pop_and_dispatch`（`_event_popped`を毎回呼ぶ → `@event_queue.pop(timeout_ms: 0)` → `packet_callback`）を自前で回す。
  - `packet_callback`: `Packet.disconnect?`なら`@lost = true`。`super`の後、`Packet.notification`の値をbufferに積む。
  - `gatt_report`: `Packet.gatt_report(@services)`を返し、handleを覚える。
  - `subscribe(settle_ms)`: CCCDに`"\x01\x00"`を書き、`settle_ms`の間、20msごとに`pop_and_dispatch`と`sleep_ms`。
  - `write_chunk(bytes)`: `write_value_of_characteristic_without_response(@conn_handle, @write_handle, bytes)`。戻り値（常に0）を見ない。
  - `poll_notifications`: `pop_and_dispatch`を空になるまで回し、`@lost`ならnil、そうでなければ積んだ値を返して空にする。
  - `disconnect`: 何もしない。
- TDD: このファイルは`< BLE`なので、テストVMでは読み込めない。ロジックは全部T1.6の`Packet`に出してあり、ここに残るのは数行の配線だけにする。テストの代わりに次で確かめる。
- 検証:
  - `rake vm:build` → exit 0（構文と定数の解決）。
  - 実機での確認はT1.15で行う。ここで実機に繋がない。
- 実機: 不要（T1.15で使う）。
- commitのWhy: 「picoruby-bleのdarwin版の癖（writeの戻り値、CCCDの完了が来ない、切断パケットの形、scan後の自前ループ）を、契約の後ろに閉じ込めた。port-darwinの先頭が変わって壊れたら、直すのはこのファイルとpacket.rbだけで済む。」

### T1.10b CLIの配線

- 目的: 引数 → PBM reader → Job → PrintSession（または`--status`、`--dry-run`）→ 結果JSON → exit codeの流れを組む。
- 触るファイル: `cli/phomemo_cli.rb`（`Runner`を足す）、`cli/print.rb`、`bin/phomemo-print`、`test/cli/runner_test.rb`。
- 依存: T1.8、T1.10a、T1.4。
- 担当: sonnet。
- 入口: `bin/phomemo-print`（sh）が`exec "$VM" "$ROOT/cli/print.rb" "$ROOT" "$@"`。`VM`は`PHOMEMO_PICORUBY`、無ければ`$ROOT/vendor/R2P2-darwin/build/host/bin/picoruby`（stackchanの`bin/stackchan`と同じ形）。`cli/print.rb`は`load "#{ARGV[0]}/cli/phomemo_cli.rb"`して`exit PhomemoCLI::Runner.new(ARGV[1..], transport_factory: -> { PhomemoThermalPrinter::Darwin::Transport.new }).run`。T1.12で、R0-3に応じて入口だけを差し替える。
- `--dry-run`: トランスポートを作らない。`Job`と`Chunker`を回し、チャンクごとに`0001 128 1b401b6100…`（通し番号、長さ、hex）を1行ずつstdoutに出し、最後に`total chunks=N bytes=M rows=R`。結果JSONの`mode`は`dry_run`。
- TDD:

```ruby
class RunnerTest < Picotest::Test
  def test_dry_run_never_builds_a_transport
    out = []
    code = PhomemoCLI::Runner.new(["--dry-run", fixture_path("stripes-600.pbm")],
                                   transport_factory: -> { raise "must not connect" },
                                   stdout: out).run
    assert_equal 0, code
    assert out.last.start_with?("total chunks=")
  end

  def test_dry_run_hex_concatenates_to_the_job_bytes
    out = []
    PhomemoCLI::Runner.new(["--dry-run", "--chunk", "182", fixture_path("stripes-600.pbm")],
                           transport_factory: -> { raise "x" }, stdout: out).run
    hex = out[0..-2].map { |l| l.split(" ")[2] }.join
    assert hex.start_with?("1b401b61001f1102041d7630003000ff00")
    assert hex.end_with?("1b6403")
  end

  def test_busy_is_returned_while_another_holds_the_lock
    other = PhomemoCLI::Lock.acquire(lock_path)
    code = PhomemoCLI::Runner.new(["--status", "--result", result_path], lock_path: lock_path,
                                   transport_factory: -> { fake(replies: all_replies) }).run
    assert_equal 12, code
    assert_equal "busy", read_json(result_path)["error"]
    other.release(now_ms: 0)
  end

  def test_a_print_with_the_fake_writes_an_ok_result
    code = PhomemoCLI::Runner.new(["--result", result_path, fixture_path("stripes-600.pbm")],
                                   lock_path: lock_path, clock: clock, sleeper: sleeper,
                                   transport_factory: -> { fake(replies: ok_replies) }).run
    assert_equal 0, code
    r = read_json(result_path)
    assert_equal true, r["ok"]
    assert_equal 600, r["job"]["rows"]
    assert_equal 3, r["job"]["blocks"]
  end

  def test_a_bad_pbm_is_invalid_input_with_exit_2
    code = PhomemoCLI::Runner.new(["--result", result_path, "/nonexistent.pbm"],
                                   transport_factory: -> { raise "x" }).run
    assert_equal 2, code
    assert_equal "invalid_input", read_json(result_path)["error"]
  end
end
```

- 検証:
  - `SUITE=cli rake test:ruby` → picotestの合格行。
  - `bin/phomemo-print --dry-run test/fixtures/stripes-600.pbm | tail -1` → `total chunks=… bytes=… rows=600`（`--dry-run`はBLEに触らないので、直接execで動く）。
- commitのWhy: 「1回の起動で1ジョブを送り、完了待ちの後に終える。--dry-runは実機なしでバイト列を確かめるための口で、BLEを一切作らない。」

### T1.12 CLIの起動経路（TCC。R0-3で決まる）

- 目的: ターミナルからBLEを使う`--status`と印刷が、TCCを通る経路で動くようにする。
- 触るファイル: `rakelib/cli.rake`（`cli:bundle`）、`bin/phomemo-print`（経路の切り替え）、`cli/PhomemoPrint-Info.plist`（経路2のとき）、`build_config/darwin-thermal-printer.rb`（経路3のとき`-sectcreate`の1行）。
- 依存: T1.10b、R0-3、T0.9。
- 担当: sonnet。
- R0-3の結果ごとの形:
  - 経路1（直接exec）が通る: 何も足さない。
  - 経路3（`-sectcreate`）が通る: 製品VMのbuild_configに埋め込みを入れ、`bin/phomemo-print`は直接exec。stdoutとexit codeがそのまま使える。
  - 経路2（`.app` + `open -W -a`）だけが通る: `cli:bundle`がVMを`~/Applications/PhomemoPrint.app/Contents/MacOS/picoruby`に置き、Info.plist（bundle id `com.bash0c7.phomemoprint`、`NSBluetoothAlwaysUsageDescription`）を置き、`codesign --force --deep -s - -r='designated => identifier "com.bash0c7.phomemoprint"'`で署名する（stackchanの`pc:app_bundle`と同じ。requirementを固定しないと、再ビルドのたびに許可が消える）。`bin/phomemo-print`は`open -W -a … --stdout <log> --stderr <log> --args <絶対パス>…`で起動し、結果JSONの`exit_code`を読んで同じcodeで終わる。`vm:build`の後は`cli:bundle`を再実行する。
- TDD: 経路の切り替えはshと署名なので、picotestでは書かない。次の検証を「失敗するテスト」の代わりにする。
- 検証:
  - 経路を入れる前に`bin/phomemo-print --status --result /tmp/phomemo-status.json`を叩き、R0-3のとおりに失敗する（直接execならSIGABRT）ことを確かめる。
  - 入れた後、プリンターの電源が切れた状態で同じコマンド → `not_found`（exit 10）が結果JSONに書かれる。これで「TCCを通ってscanまで進んだ」ことが実機なしで分かる。許可ダイアログが出たら、人間の操作が要る（T1.15の最初の操作にまとめる）。
- 実機: プリンターは不要。Bluetoothの許可ダイアログが初回に1回出る可能性があり、そのクリックだけ人間が要る。T1.15の段取りに入れ、ここでダイアログ待ちになったら、検証をT1.15の最初に回す。
- commitのWhy: 「M0で通った起動経路に合わせて、ターミナルからの印刷とステータスをTCCに通した。open経由ではexit codeが伝わらないので、結果JSONのexit_codeでラッパーの終了コードを揃えた。」

### T1.13 実機に送る前の敵対的レビュー（opus）

- 目的: プリンターを壊すバイト列が送られる経路が無いことを、白紙の文脈で確かめる。
- 触るファイル: なし（指摘を親に返す）。
- 依存: T1.3、T1.7、T1.8、T1.9、T1.10b、T1.12。
- 担当: opus（新しいsubagent。計画書もこの節の結論も渡さず、設計書§6.8とコードだけを渡す）。
- 見ること:
  - BLEへのwriteに至る全経路（`write_chunk`と`write_value_of_characteristic_without_response`の呼び出し元を全部たどる）。allowlist外のバイト列が混ざる経路があるか。
  - `Chunker`がsegmentをまたいでチャンクを切ることで、プリンターにallowlist外のコマンドとして解釈されうる形が生まれないか（例: チャンクの境目でのタイミング）。
  - 引数やPBMの中身から、`1f 11`の0x14超や`1b 4e`を作れる経路があるか。
  - 完了待ちより先にプロセスが終わる経路（印字が途中で止まる）。
- 合格: 指摘0件、または全指摘が直され、`rake test`が通る。

### T1.14 実機セッションS1の準備

- 目的: §8.1のチェックリストを、人間の物理操作が最少になる段取りで流せるようにする。
- 触るファイル: `rakelib/device.rake`、`build/device/`（生成物。commitしない）。
- 依存: T1.11、T1.12、T1.13、T2.4（写真のPBMを作る`thermal-pbm`）。
- 担当: sonnet。
- タスク:
  - `device:s1:prepare`: `tools/make_test_pbm.rb topline`（12mm）と、`thermal-pbm --sample`（36mm）の2つだけを`build/device/s1/`に作る。2つの合計が約5cmを超えるPBMは作らない。両方を`--dry-run`に通し、allowlistの外が出ないことを確かめる。
  - `device:s1:auto`: 下の「段A」を順に流す。各コマンドの結果JSONを`build/device/s1/<番号>-<名前>.json`に保存し、最後に一覧（ok、error、warnings、acks、max_write、completion）を表で出す。連続の起動はCLIのロックが1.5秒空ける。
- 紙の方針: 紙で確かめるのは、画面のビットマップでは分からない物理だけにする。プリンターが受け取るのは384 dot幅のビットマップだけなので、部品の種類（カード、会議メモ、写真）の違いは印字で確かめず、画面とテストで確かめる。S1の印字は2回、合計約5cmだけ。
- 段A（人間は見ているだけでよい）:
  1. `--status`（#11の1回目、#13。紙は使わない）
  2. `topline`（12mm）を既定のチャンク128byteで1回。先に出す安全確認で、#10（上端の欠け）と、書き込み1回ごとに`01 01`が1件届くか（#3、`acks`と`chunks`の一致）を見る。**`acks`と`chunks`が一致するまで、次の印字に進まない**（任意のバイトを含む画像を送ると、欠落時に画像データがコマンドとして誤解釈されうる。T1.13のB2）。
  3. 写真（`thermal-pbm --sample`、36mm = 288行。M1のゲート）を1回。255行（約32mm）を超えるので継ぎ目（複数ブロックの連続）、任意のバイト値、`acks`と`chunks`の一致を同時に確かめる。
  4. `--status`（印字後の状態。紙は使わない）
  5. #12の完了通知までの時間は、上の結果JSON（`completion.after_send_ms`）から取る。専用の印字はしない。1jobあたりの`1a 0f 0c`の回数は、結果JSONの`notify.events`から数える。
- 紙で確かめず、結果に「未実施。S2の実際の印字、または実運用で確認」と記録する項目: #2のチャンク182での取りこぼし（既定の128で運用する）、#7の`1b 64 n`の紙送り量、#8の濃度1〜5の濃さ。
- カバー開・紙切れ・充電中の状態は、紙を使わない`--status`で確かめられるが、人間の物理操作が増えるので、S1では行わない。結果に「未実施。実運用で状態が出たときに確認」と記録する。
- 検証: `rake device:s1:prepare` → `build/device/s1/`にPBMとdry-runの結果ができ、`[device] s1 prepared: N files, allowlist ok`。実機には繋がない。
- 実機: 不要（準備だけ）。

### T1.15 実機セッションS1（人間の物理操作あり）

- 目的: §8.1の15項目に答えを出し、M1のゲートを確かめる。
- 依存: T1.14、R0-5。直前に`rake vendor:refresh`→`rake vm:build`→（経路2なら）`rake cli:bundle`→`rake test`を1回通し、使った`port-darwin`のcommitを控える。
- 担当: 判断と人間への依頼は親（opus）。rakeの実行はhaiku（コマンドをverbatimで渡し、出力をそのまま返させる）。
- 人間への依頼は2回にまとめる。依頼文には、何を、いつまでに、何を見てほしいかを全部書く。
  1. **開始前**（1回目）: 「T02の電源を入れ、紙を入れ、USBは抜いた状態にしてください。Macの前にいて、Bluetoothの許可ダイアログが出たら『許可』を押してください。公式アプリの接続は切ってください。準備ができたら返事をください。段Aが終わるまで約3分、そのまま置いておいてください。紙は約5cm使います。」→ 段Aを流す。段Aの1番で`status_unavailable`なら、段Aを止めて、「システム設定 → BluetoothでT02とペアリングしてください」を追加で1回だけ頼み、1番から流し直す（#13）。
  2. **目視と計測**（2回目）: 印字物を並べた順と、見てほしいこと、記入欄を1つのメッセージで渡す。
     - toplineの1行目の黒が欠けているか、目盛りの数が12mm分そろっているか（#10）
     - 写真の顔がつぶれていないか、約32mmの地点（255行の継ぎ目）に段差・抜けが無いか
- 機械で取る記録: 結果JSONの`notify.max_write`（#2）、`job.chunks`と`notify.acks`の比（#3）、`completion.after_send_ms`（#12）、`status`の各値と時刻（#11）、`gatt_report`（#1、#15）。
- 合格: 段Aの全印字が`ok: true`で`acks`と`chunks`が一致し、目視でテストパターンと写真が正しく出ている。
- 実機: 要る。物理操作は上の2回だけ。

### T1.16 実機の記録と既定値の反映

- 目的: S1の結果を`docs/research/t02-device-notes.md`に記録し、既定値（チャンク長、間隔、`settle_ms`、完了待ちの係数）を結果に合わせる。
- 触るファイル: `docs/research/t02-device-notes.md`（新規）、`cli/phomemo_cli.rb`と`session.rb`の既定値（変えるときだけ）、該当テスト。
- 依存: T1.15。
- 担当: sonnet（記録と変更）→ opus（記録が結果JSONと目視の回答に合っているかのレビュー）。
- `t02-device-notes.md`の形: 日付、ファームウェア版（`1f 11 07`）、シリアル、macOS版、`port-darwin`のcommit、起動経路。§8.1の#1〜#15を1行1項目の表にし、各行に「結果」「根拠（結果JSONのファイル名、目視の回答）」「設計書§6のどの確度を『実機（本機）』に上げたか」を書く。#4・#5・#6・#9・#14は「v1では使わない」。
- 既定値を変えたら、そのテストを先に直してredを見てから変える。
- 検証: `rake test` → 全部exit 0。
- commitのWhy: 「設計書§8.1のとおり、実機の結果で§6の不明点に値を入れた。既定値の変更は、この記録を根拠にする。」

### M1の完了ゲート

次を全部、親が自分で確かめる。

- [ ] `rake test`が全部exit 0（共通層のテストが、BLEなしのテストVMで通る）。
- [ ] テストパターンのPBMと写真のPBMが、T1.15でmacOSからT02実機に印字され、目視で正しい。
- [ ] `bin/phomemo-print --status`が実機の電池・紙・カバー・温度・版・シリアルを返す。
- [ ] `docs/research/t02-device-notes.md`に、§8.1の15項目すべての結果か「v1では使わない」がある。
- [ ] `rake check:send_paths`がok。T1.13の指摘が0件。

## 5. M2 Macアプリ

完了ゲート（設計書§8を、紙の浪費を避ける方針で変更。ユーザー承認済み）: アプリ経由でカード1枚（約6cm）が実機で印字され、はみ出しが無く、QRがスマホで読める。3つの場面（タスク札、会議メモ、写真）は、画面のビットマップとテストで確かめる。

依存の形:

```
T2.1 → 並列群B {T2.2, T2.4, T2.5, T2.8, T2.11}
T2.2 → T2.3
T2.2 + T2.5 → T2.6 → 並列群C {T2.7, T2.9}
T2.3 + T2.4 + T2.6 → T2.10
T2.1 + T1.12 + R0-3 → T2.13（並列群B・Cと並列でよい。触るのはproject.ymlとApp/の設定ファイルだけ）
T2.7 + T2.9 + T2.10 + T2.11 → T2.12 → T2.14 → T2.15（opus）→ T2.16（実機）→ T2.17 → ゲート
```

T2.4はM1のT1.14より前に要る（写真のPBM）。M1と並行して走らせる。

M2の横断:

- テストはSwift Testing（`import Testing`、`@Test`、`#expect`）。`app/Core`は`/usr/bin/swift test --package-path /Users/bash/dev/src/github.com/bash0C7/thermal-printer/app/Core`で回す（`rake app:test`と同じ）。期待される出力: 最後に`Test run with N tests … passed`の形の行があり、`failed`を含む行が無い。exit 0。
- ラスタの型は`Bitmap1`（幅384、1bit、1が黒）。描画はすべて「アンチエイリアスで8bit灰色に描く → しきい値128で2値化」（文字）か、「Floyd–Steinberg」（写真）。プレビューは`Bitmap1`をそのまま表示する（近似の別描画を作らない）。
- 左右の内側余白は8 dot（設計書§5.3.7）。印字幅は368 dot。

### T2.1 Swiftの土台: package、project、Bitmap1、PBM writer

- 目的: `app/Core`（SwiftPM）と`app/project.yml`（xcodegen）を一度に作り、以後のタスクがmanifestを触らずにファイルを足せるようにする。`Bitmap1`とPBM writerを、RubyのPBM readerとの契約テストつきで作る。
- 触るファイル: `app/Core/Package.swift`、`app/Core/Sources/ThermalPrinterCore/Raster/{Bitmap1.swift, PBMWriter.swift}`、`app/Core/Sources/thermal-pbm/main.swift`（引数を受けて終わるだけの空の形）、`app/Core/Tests/ThermalPrinterCoreTests/Raster/{Bitmap1Tests.swift, PBMWriterTests.swift}`、`app/project.yml`、`app/App/{ThermalPrinterApp.swift, Info.plist}`（空のウィンドウ）、`app/UITests/LaunchTests.swift`、`rakelib/app.rake`（`app:gen`、`app:test`、`task test: "app:test"`）。
- 依存: T1.1（rakelib）、T1.4（`test/fixtures/stripes-600.pbm`）。
- 担当: sonnet。
- `Package.swift`: platforms macOS 27（ツールのバージョンが未対応なら書ける最新）、product `ThermalPrinterCore`（library）と`thermal-pbm`（executable）、依存`https://github.com/swiftlang/swift-markdown`（CommonMark + GFMの表とタスクリスト。設計書§11で任された選定）。target `ThermalPrinterCoreTests`。
- `project.yml`: target `ThermalPrinter`（application、macOS 27、bundle id `com.bash0c7.thermalprinter`、sources `App`、local package `Core`の`ThermalPrinterCore`に依存、Info.plistは`App/Info.plist`）、target `ThermalPrinterUITests`（ui-testing）。App Sandboxは使わない（アプリが`gh`と同梱のpicorubyを子プロセスで起動し、`gh`は`~/.config/gh`を読むため）。
- TDD:

```swift
@Test func pbmOfStripesMatchesTheRubyFixtureByteForByte() throws {
    var bmp = Bitmap1(height: 600)
    for y in 0..<600 where y % 2 == 0 { bmp.fillRow(y) }
    let fixture = try Data(contentsOf: repoRoot.appending(path: "test/fixtures/stripes-600.pbm"))
    #expect(PBMWriter.data(bmp) == fixture)
}

@Test func bitmapIsAlways384DotsWide() {
    #expect(Bitmap1(height: 1).width == 384)
}

@Test func inkOutsideColumnsIsReported() {
    var bmp = Bitmap1(height: 2)
    bmp.set(x: 3, y: 1)
    #expect(bmp.blackPixels(inColumns: 0..<8) == [Point(x: 3, y: 1)])
    #expect(bmp.blackPixels(inColumns: 376..<384).isEmpty)
}

@Test func lengthInMillimetersIsRowsOverEight() {
    #expect(Bitmap1(height: 2400).lengthMillimeters == 300)
}
```

- 検証:
  - `rake app:test` → Swift Testingの合格の行。exit 0。
  - `rake app:gen` → `app/ThermalPrinter.xcodeproj`ができる（生成物。`.gitignore`に足す）。
  - `rake test` → Ruby側とSwift側が全部exit 0。
- commitのWhy: 「アプリの.app要件はxcodegenで、テストの多いロジックはswift testで速く回せるpackageに分けた。PBMはRubyのreaderと同じfixtureで、境界の形を固定した。」

### 並列群B（T2.1の後）

#### T2.2 文字組みエンジン（anti-goal: はみ出し、禁則、強制折り返し）

- 目的: どんな入力でも、すべてのインクが印字幅（8〜376 dot）に収まる文字組みを作る。日本語の禁則処理と、空白の無い長いトークンの文字単位の強制折り返しを行う。
- 触るファイル: `app/Core/Sources/ThermalPrinterCore/Typesetting/{TextStyle.swift, Kinsoku.swift, LineBreaker.swift, TextRenderer.swift}`、`app/Core/Tests/ThermalPrinterCoreTests/Typesetting/{AntiGoalTests.swift, KinsokuTests.swift, LineBreakerTests.swift}`。
- 依存: T2.1。
- 担当: sonnet。
- 方針:
  - `TextStyle`: フォント（Hiragino Sansの太いウェイト。細い字は感熱紙でかすれる）、サイズ（小/中/大、見出し）、太さ、合成oblique（日本語フォントにitalicが無いので、shearの変換で傾ける）、等幅。
  - `LineBreaker`: CoreTextの`CTTypesetterSuggestLineBreak`で候補を出し、その行の**インクの幅**（obliqueのshearによる右へのはみ出しを含む）が印字幅を超えたら、`CTTypesetterSuggestClusterBreak`で文字単位に切る。切った後に禁則で調整する: 次の行の先頭が行頭禁則文字なら、今の行の末尾の文字を次の行へ追い出す。今の行の末尾が行末禁則文字なら、それを次の行へ送る。1文字しか残らない行では調整しない（無限ループを避ける）。
  - `Kinsoku`: 行頭禁則に`、。，．・：；？！ー～…‥」』）］｝〕〉》】〙〗’”ゝゞヽヾぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮヵヶ々`と、ASCIIの`,.:;?!)]}`。行末禁則に`「『（［｛〔〈《【〘〖‘“`とASCIIの`([{`。CoreTextの既定規則だけでは`ー`が行頭に来うる（UAX #14でCJ）ので、この表で必ず検査する。
  - `TextRenderer`: 行を8bit灰色のCGContextにアンチエイリアスで描き、しきい値128で`Bitmap1`にする。
- TDD（anti-goalのテストを最初に全部書き、redを見る）:

```swift
enum AntiGoal {
    static let longURL = "https://github.com/bash0C7/thermal-printer/issues/1?" + String(repeating: "q=abcdefghij&", count: 40)
    static let longWord = String(repeating: "Supercalifragilistic", count: 12)
    static let longDigits = String(repeating: "1234567890", count: 30)
    static let punctuatedJapanese = String(repeating: "「これは、テスト。」（括弧）ー長音！？『二重』…", count: 12)
    static let all: [(String, TextStyle)] = [
        (longURL, .body), (longWord, .body), (longDigits, .body), (punctuatedJapanese, .body),
        (punctuatedJapanese, .body.oblique), (longWord, .heading1), (longURL, .monospaced),
    ]
}

@Test(arguments: AntiGoal.all)
func allInkStaysInsideThePrintableWidth(text: String, style: TextStyle) {
    let bmp = TextRenderer(margin: 8).render(text, style: style)
    #expect(bmp.blackPixels(inColumns: 0..<8).isEmpty)
    #expect(bmp.blackPixels(inColumns: 376..<384).isEmpty)
}

@Test(arguments: AntiGoal.all)
func longTokensAreWrappedNotTruncated(text: String, style: TextStyle) {
    let lines = LineBreaker(width: 368).lines(text, style: style)
    #expect(lines.joined() == text)
    #expect(lines.count > 1)
}

@Test func noLineStartsWithALineStartForbiddenCharacter() {
    let lines = LineBreaker(width: 368).lines(AntiGoal.punctuatedJapanese, style: .body)
    for line in lines.dropFirst() {
        #expect(!Kinsoku.lineStartForbidden.contains(line.first!))
    }
}

@Test func noLineEndsWithALineEndForbiddenCharacter() {
    let lines = LineBreaker(width: 368).lines(AntiGoal.punctuatedJapanese, style: .body)
    for line in lines.dropLast() {
        #expect(!Kinsoku.lineEndForbidden.contains(line.last!))
    }
}

@Test func prolongedSoundMarkNeverStartsALine() {
    let text = String(repeating: "あ", count: 22) + "ー" + String(repeating: "い", count: 40)
    for width in stride(from: 200, through: 368, by: 4) {
        for line in LineBreaker(width: width).lines(text, style: .body).dropFirst() {
            #expect(line.first != "ー")
        }
    }
}

@Test func textIsThresholdedNotDithered() {
    let bmp = TextRenderer(margin: 8).render("あ", style: .body)
    #expect(bmp.isolatedSinglePixelCount < 4)
}
```

  - 最後の`isolatedSinglePixelCount`は、周りの8近傍が全部白の黒画素の数（砂目の検出）。
- 検証: `/usr/bin/swift test --package-path …/app/Core --filter Typesetting` → 合格。
- commitのWhy: 「文字のはみ出しはユーザーが決めたanti-goal。CoreTextの改行候補だけでは長音記号や合成obliqueのはみ出しを防げないので、インクの幅と禁則の表で必ず検査する。」

#### T2.4 写真のディザ（Floyd–Steinberg）と`thermal-pbm`ツール

- 目的: 画像を幅384にリサイズし、ガンマ → コントラスト（128中心）→ 明るさの順に調整し、Floyd–Steinbergで2値化する。モックアップのJSを参照実装として、同じ入力で同じビットになることを確かめる。画像ファイルからPBMを作るツールも作る（M1のT1.14が使う）。
- 触るファイル: `app/Core/Sources/ThermalPrinterCore/Image/{PhotoAdjust.swift, FloydSteinberg.swift, ImageLoader.swift}`、`app/Core/Sources/thermal-pbm/main.swift`、`app/Core/Tests/ThermalPrinterCoreTests/Image/{DitherGoldenTests.swift, PhotoAdjustTests.swift}`、`tools/dither_golden.js`、`app/Core/Tests/ThermalPrinterCoreTests/Image/Fixtures/dither-golden-*.txt`。
- 依存: T2.1。
- 担当: sonnet。
- 参照実装: `docs/superpowers/specs/2026-10-24-thermal-printer-mockups/photo-dither.html`の`gray()`と`diffuse()`（84〜106行）。JSは倍精度で計算して`Float32Array`に入れる。Swiftも`Double`で計算して`Float`に入れる（同じ丸めになるように）。
- golden: `tools/dither_golden.js`は`diffuse`と`gray`の調整部分を写し、合成の入力（幅384×高さ32、x方向の階調 + y方向のsin波、整数で決まる値）に、中立（0, 1.0, 1.0）と2通りの調整（明るさ+20/コントラスト1.3/ガンマ0.8など）をかけた結果のビットを、行ごとのhexで出す。`osascript -l JavaScript tools/dither_golden.js > …/dither-golden-neutral.txt`で作り、fixtureとしてcommitする。
- TDD:

```swift
@Test(arguments: DitherCase.all)
func floydSteinbergMatchesTheMockupReference(c: DitherCase) throws {
    let gray = SyntheticGray.make(width: 384, height: 32)
    let adjusted = PhotoAdjust(brightness: c.brightness, contrast: c.contrast, gamma: c.gamma).apply(gray)
    let bits = FloydSteinberg.dither(adjusted)
    #expect(bits.hexRows == try c.goldenRows())
}

@Test func luminanceUsesRec601Weights() {
    #expect(PhotoAdjust.luminance(r: 255, g: 0, b: 0) == 0.299 * 255)
}

@Test func neutralAdjustmentIsIdentity() {
    let gray = SyntheticGray.make(width: 384, height: 4)
    #expect(PhotoAdjust(brightness: 0, contrast: 1, gamma: 1).apply(gray) == gray)
}

@Test func anyImageIsResizedTo384Wide() throws {
    let bmp = try ImageLoader.bitmap(from: sampleJPEG, adjust: .neutral)
    #expect(bmp.width == 384)
    #expect(bmp.height == Int((Double(sampleHeight) * 384 / Double(sampleWidth)).rounded()))
}
```

- `thermal-pbm`: `thermal-pbm <画像> <out.pbm> [--brightness N --contrast X --gamma Y --rotate]`と`thermal-pbm --sample <out.pbm>`（モックアップの`sample()`と同じ構図の合成画像）。
- 検証: `--filter Image`で合格。`/usr/bin/swift run --package-path …/app/Core thermal-pbm --sample /tmp/photo.pbm`の後、`head -c 12 /tmp/photo.pbm | od -c`が`P4\n384 `で始まる。
- commitのWhy: 「写真はFloyd–Steinberg（ユーザー決定）。ブレインストーミングでユーザーが見て選んだモックアップと同じビットになることを、JSを同じ入力で走らせたgoldenで確かめた。」

#### T2.5 QRコード

- 目的: URLから、1モジュールを整数dotに拡大した補間なしのQR（誤り訂正M）を作る。一辺128 dot前後、1モジュール3 dot以上。
- 触るファイル: `app/Core/Sources/ThermalPrinterCore/QR/QRCode.swift`、`app/Core/Tests/ThermalPrinterCoreTests/QR/QRCodeTests.swift`。
- 依存: T2.1。
- 担当: sonnet。
- 方針: CoreImageの`CIQRCodeGenerator`（`inputCorrectionLevel = "M"`）。出力の1画素 = 1モジュール。`scale = max(3, 128 / modules)`の整数倍で`Bitmap1`に写す。
- TDD:

```swift
@Test(arguments: ["https://github.com/bash0C7/thermal-printer/issues/1",
                  "https://example.slack.com/archives/C0123456789/p1792565843307099?thread_ts=1792565800.000100&cid=C0123456789",
                  "https://example.com/" + String(repeating: "a", count: 200)])
func qrDecodesBackToTheURL(url: String) throws {
    let qr = try QRCode(url)
    #expect(try QRDecoder.decode(qr.bitmap) == url)
}

@Test func everyModuleIsAtLeastThreeDots() throws {
    let qr = try QRCode("https://example.com/" + String(repeating: "a", count: 200))
    #expect(qr.dotsPerModule >= 3)
}

@Test func shortURLIsAboutSixteenMillimeters() throws {
    let qr = try QRCode("https://github.com/bash0C7/thermal-printer/issues/1")
    #expect((112...144).contains(qr.sideDots))
}
```

  - `QRDecoder`はテスト側のヘルパーで、`CIDetector(ofType: CIDetectorTypeQRCode)`か`VNDetectBarcodesRequest`で`Bitmap1`を読む（どちらを使うかは、docsetで確かめて動く方）。
- 検証: `--filter QR`で合格。
- commitのWhy: 「カードのQRは、紙の上で読めることが目的。生成した1bitのビットマップをdecoderに読ませて、URLが戻ることを確かめた。」

#### T2.8 要約（Foundation Modelsと先頭切り詰めのフォールバック）

- 目的: GitHubの概要と最新コメントを日本語で要約する。モデルが使えないときは、本文の先頭を文字数で切って「…」を付け、そのことを部品に小さく出せるように印を返す。
- 触るファイル: `app/Core/Sources/ThermalPrinterCore/Summary/{Summarizer.swift, FoundationModelSummarizer.swift, TruncatingSummarizer.swift, SummaryCache.swift}`、`app/Core/Tests/ThermalPrinterCoreTests/Summary/{TruncatingSummarizerTests.swift, SummarizerSelectionTests.swift, FoundationModelSummarizerIntegrationTests.swift}`。
- 依存: T2.1。
- 担当: sonnet。
- 先に確かめること: `FoundationModels`の`SystemLanguageModel`の可用性の判定と、`LanguageModelSession`の作り方と応答の受け方（docsetで名前と引数を確かめる）。
- 方針: `protocol Summarizer { func summarize(_ text: String, kind: SummaryKind) async -> Summary }`。`Summary`は`text`と`usedModel: Bool`。概要は3行以内（目安60文字）、最新コメントは2行以内（目安40文字）。最新コメントの相対日時（「2日前」）は要約の外で付ける。キャッシュは本文のハッシュをkeyにしたメモリ上の辞書。
- TDD:

```swift
@Test func truncationKeepsTheHeadAndAddsAnEllipsis() async {
    let s = await TruncatingSummarizer().summarize(String(repeating: "あ", count: 200), kind: .overview)
    #expect(s.text == String(repeating: "あ", count: 60) + "…")
    #expect(s.usedModel == false)
}

@Test func shortTextIsNotEllipsized() async {
    #expect(await TruncatingSummarizer().summarize("短い", kind: .overview).text == "短い")
}

@Test func unavailableModelFallsBackToTruncation() async {
    let s = await SummarizerSelector(modelAvailable: false).summarizer.summarize(String(repeating: "a", count: 100), kind: .comment)
    #expect(s.usedModel == false)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["RUN_FOUNDATION_MODELS"] == "1"))
func realModelSummarizesJapaneseWithinThreeLines() async throws {
    let s = await FoundationModelSummarizer().summarize(Fixtures.issueBody, kind: .overview)
    #expect(s.usedModel)
    #expect(s.text.count <= 90)
    #expect(s.text.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) })
}
```

- 検証:
  - `--filter Summary`で合格（統合テストはskip）。
  - `RUN_FOUNDATION_MODELS=1 /usr/bin/swift test --package-path …/app/Core --filter Integration`をClaudeが自分で走らせ、合格するか、モデルが使えないならその理由（可用性の値）を報告する。出力された要約の文を報告に貼る（プロンプトの調整の材料。設計書§13.9）。
- commitのWhy: 「要約はFoundation Modelsで作るが、Apple Intelligenceが無効な環境でも黙って失敗しないよう、切り詰めに落ちたことを部品に出せる形にした。」

#### T2.11 CLIの呼び出しと状態の表示

- 目的: アプリからCLIを起動し、結果JSONを読み、エラー種別を日本語の言葉にし、プリンターの状態を確認時刻つきで表示する。
- 触るファイル: `app/Core/Sources/ThermalPrinterCore/Printer/{PrintResult.swift, PrinterClient.swift, ProcessRunner.swift, PrinterStatusText.swift}`、`app/Core/Tests/ThermalPrinterCoreTests/Printer/{PrintResultTests.swift, PrinterClientTests.swift, PrinterStatusTextTests.swift}`。
- 依存: T2.1、T1.10a（`test/fixtures/result_*.json`）、R0-3、T0.9。
- 担当: sonnet。
- 方針: `ProcessRunner`はprotocolにして、テストではfakeを入れる。`PrinterClient`の起動の形はR0-3で決まる: 経路4ならアプリのbundle内の`picoruby`を`Process`で起動し、`[cli/print.rb, cliDir, --result, <一時ファイル>, …]`を渡す。経路2なら`/usr/bin/open -W -a PhomemoPrint.app --args …`。どちらでも結果JSONを読む。
- TDD:

```swift
@Test(arguments: ["result_print_ok", "result_status_ok", "result_not_found"])
func everyRubyResultFixtureDecodes(name: String) throws {
    let data = try Data(contentsOf: repoRoot.appending(path: "test/fixtures/\(name).json"))
    _ = try JSONDecoder().decode(PrintResult.self, from: data)
}

@Test(arguments: PrintResult.ErrorKind.allCases)
func everyErrorKindHasAJapaneseMessage(kind: PrintResult.ErrorKind) {
    #expect(!PrinterStatusText.message(for: kind).isEmpty)
}

@Test func notFoundMessageCarriesTheWakeUpHints() {
    let m = PrinterStatusText.message(for: .notFound)
    #expect(m.contains("電源ボタン"))
    #expect(m.contains("公式アプリ"))
}

@Test func statusLineShowsBatteryPaperAndCheckTime() throws {
    let r = try decodeFixture("result_status_ok")
    let line = PrinterStatusText.titleBar(r.status!, checkedAt: date(hour: 10, minute: 42))
    #expect(line == "電池83%・紙あり・カバー閉・温度正常（10:42確認）")
}

@Test func busyKeepsThePreviousStatus() async {
    let client = PrinterClient(runner: FakeRunner(resultFixture: "result_busy"))
    let before = PrinterStatusSnapshot(line: "電池83%・紙あり（10:42確認）")
    let after = await client.refreshStatus(previous: before)
    #expect(after == before)
}

@Test func printPassesTheResultPathAndDensity() async throws {
    let runner = FakeRunner(resultFixture: "result_print_ok")
    _ = try await PrinterClient(runner: runner).print(pbm: URL(filePath: "/tmp/a.pbm"), density: 3)
    #expect(runner.lastArguments.contains("--density"))
    #expect(runner.lastArguments.contains("3"))
    #expect(runner.lastArguments.contains("--result"))
}
```

  - `result_busy.json`はT1.10aのfixtureの形で、このタスクで`test/fixtures/`に足す（Ruby側の`ResultFileTest`がkeyの集合を検査する対象に入れる）。
- 検証: `--filter Printer`で合格。
- commitのWhy: 「open経由ではstdoutもexit codeも当てにできないので、アプリは結果JSONだけを読む。Ruby側のfixtureをそのままdecodeして、境界の形を固定した。」

### T2.3 markdownレンダラ（A: ミニマル）

- 目的: markdownを、設計書§5.3.3の「A: ミニマル」で`Bitmap1`に描く。すべての文字描画はT2.2の文字組みを通す。
- 触るファイル: `app/Core/Sources/ThermalPrinterCore/Markdown/{MarkdownRenderer.swift, BlockLayout.swift}`、`app/Core/Tests/ThermalPrinterCoreTests/Markdown/{MarkdownAntiGoalTests.swift, MarkdownStyleTests.swift}`。
- 依存: T2.2。
- 担当: sonnet。
- 描き方: H1は大きく極太。H2は太字に太い下線。H3〜H6はH2より一段小さい太字で下線なし。太字は極太、斜体は合成oblique。リストは黒丸、順序付きは番号、入れ子は1段16 dotの字下げ（ただし字下げの合計は印字幅の半分で止める）。チェックボックスは`☐`/`☑`。引用は左に太い縦線。区切り線は太い実線。インラインコードとコードブロックは等幅で、コードブロックも折り返す。リンクは表示テキストだけ。表は「セル | セル」の行に崩して折り返す。ローカルパスの画像はT2.4の処理で埋め込む。
- TDD（anti-goalを先に）:

```swift
@Test(arguments: MarkdownAntiGoal.all)
func markdownInkStaysInsideThePrintableWidth(md: String) {
    let bmp = MarkdownRenderer(margin: 8).render(md)
    #expect(bmp.blackPixels(inColumns: 0..<8).isEmpty)
    #expect(bmp.blackPixels(inColumns: 376..<384).isEmpty)
}

enum MarkdownAntiGoal {
    static let all = [
        (0..<20).map { String(repeating: "  ", count: $0) + "- 入れ子の深いリスト\($0)、とても長い項目の本文が続く" }.joined(separator: "\n"),
        "```\n" + String(repeating: "let x = veryLongIdentifierWithoutSpaces", count: 8) + "\n```",
        "| 列A | 列B |\n|---|---|\n| " + String(repeating: "長いセル", count: 30) + " | b |",
        "# " + String(repeating: "Supercalifragilistic", count: 6),
        "> " + String(repeating: "引用の中の、長い文。", count: 20),
        "- [ ] " + String(repeating: "https://example.com/very/long/path/", count: 6),
        "***" + String(repeating: "太字斜体", count: 40) + "***",
    ]
}

@Test func h2HasAThickRuleUnderIt() {
    let bmp = MarkdownRenderer(margin: 8).render("## 見出し")
    #expect(bmp.rows.contains { $0.blackCount(in: 8..<376) >= 360 })
}

@Test func h3HasNoRule() {
    let bmp = MarkdownRenderer(margin: 8).render("### 見出し")
    #expect(!bmp.rows.contains { $0.blackCount(in: 8..<376) >= 360 })
}

@Test func checkboxesUseBallotBoxGlyphs() {
    #expect(MarkdownRenderer.plainText("- [ ] a\n- [x] b") == "☐ a\n☑ b")
}

@Test func linksShowOnlyTheirText() {
    #expect(MarkdownRenderer.plainText("[設計書](https://example.com)") == "設計書")
}
```

- 検証: `--filter Markdown`で合格。
- commitのWhy: 「会議メモを相手に手渡すので、見出しと箇条書きが整って出ることが大事（ユーザーが選んだA: ミニマル）。深い入れ子やコードブロックでもはみ出さないことを先にテストで縛った。」

### T2.6 カードのモデルとレイアウト（B: QRは右上）

- 目的: カードの内部表現（設計書§5.3.5のJSONと同じ形）と、B案のレイアウトで`Bitmap1`に描く処理を作る。
- 触るファイル: `app/Core/Sources/ThermalPrinterCore/Card/{Card.swift, CardRenderer.swift}`、`app/Core/Tests/ThermalPrinterCoreTests/Card/{CardRendererTests.swift, CardCodingTests.swift}`、`test/fixtures/cards/{github.json, slack.json, url.json, reminder.json}`。
- 依存: T2.2、T2.5。
- 担当: sonnet。
- レイアウト: 上段の左に出どころ（`header.lines`、大きく`header.emphasis`、`header.sublines`）、右にQR（`url`があるとき）。QRの左端から8 dotの間を空け、上段の文字はその幅で組む。上段の高さは、文字とQRの高い方。その下にタイトル（大きく太く）、`sections`（`label`があれば小見出し）を全幅で並べる。reminderはQRなし。
- TDD:

```swift
@Test(arguments: ["github", "slack", "url", "reminder"])
func cardFixturesRoundTrip(name: String) throws {
    let data = try fixtureData("cards/\(name).json")
    let card = try JSONDecoder().decode(Card.self, from: data)
    #expect(try JSONDecoder().decode(Card.self, from: JSONEncoder().encode(card)) == card)
}

@Test func qrSitsInTheTopRightCorner() throws {
    let r = try CardRenderer(margin: 8).render(fixtureCard("github"))
    #expect(r.qrFrame!.maxX <= 376)
    #expect(r.qrFrame!.minY == r.topPadding)
    #expect(r.headerTextFrame.maxX <= r.qrFrame!.minX - 8)
}

@Test func reminderCardHasNoQR() throws {
    #expect(try CardRenderer(margin: 8).render(fixtureCard("reminder")).qrFrame == nil)
}

@Test(arguments: CardAntiGoal.all)
func cardInkStaysInsideThePrintableWidth(card: Card) throws {
    let bmp = try CardRenderer(margin: 8).render(card).bitmap
    #expect(bmp.blackPixels(inColumns: 0..<8).isEmpty)
    #expect(bmp.blackPixels(inColumns: 376..<384).isEmpty)
}

@Test func printedQRStillDecodes() throws {
    let r = try CardRenderer(margin: 8).render(fixtureCard("slack"))
    #expect(try QRDecoder.decode(r.bitmap.crop(r.qrFrame!)) == fixtureCard("slack").url)
}
```

  - `CardAntiGoal.all`は、長いURL・長いrepo名・長いタイトル・長いchannel名を入れたカード。
- 検証: `--filter Card`で合格。
- commitのWhy: 「カードはユーザーが選んだB案（QR右上）。skillとアプリで同じスキーマを使うので、fixtureのJSONを境界の契約にした。」

### 並列群C（T2.6の後）

#### T2.7 URLハンドラ: GitHub（`gh`）、Slack URL、知らないURL

- 目的: URLの種類ごとにカードを作る。GitHubは`gh`で取り、要約する。SlackはURLからworkspace・channel ID・日時を取り出す。知らないURLはURLとQRだけ。
- 触るファイル: `app/Core/Sources/ThermalPrinterCore/Sources/{URLHandlerRegistry.swift, GitHubHandler.swift, SlackURL.swift, UnknownURLHandler.swift, GHLocator.swift, RelativeDate.swift}`、`app/Core/Tests/ThermalPrinterCoreTests/Sources/{GitHubHandlerTests.swift, SlackURLTests.swift, URLHandlerRegistryTests.swift}`、`app/Core/Tests/ThermalPrinterCoreTests/Sources/Fixtures/gh-issue-*.json`。
- 依存: T2.6、T2.8。
- 担当: sonnet。
- 先に確かめること: `gh issue view --help`と`gh pr view --help`で、`--json`に使えるfield名（title、number、state、updatedAt、body、comments、url）を確かめる。fixtureは実際の`gh issue view 1 -R bash0C7/thermal-printer --json …`の出力を写して作る。
- 方針: `URLHandlerRegistry`は「URLパターン → 取得方法」の組の表（v1はGitHubだけ）。`gh`は`GHLocator`が`/opt/homebrew/bin/gh`、`/usr/local/bin/gh`の順に探す。`gh`が失敗したら（未ログイン、権限なし、404）、知らないURLのカードに落とし、理由を部品に小さく出す。アカウントは管理しない（ユーザー決定）。
- TDD:

```swift
@Test func slackPermalinkGivesWorkspaceChannelAndJSTTime() throws {
    let s = try #require(SlackURL("https://example.slack.com/archives/C0123456789/p1792565843307099"))
    #expect(s.workspace == "example")
    #expect(s.channelID == "C0123456789")
    #expect(s.jstText == "2026/10/21(水) 15:57")
}

@Test func slackTimestampIsSplitAsIntegersNotFloats() throws {
    let s = try #require(SlackURL("https://example.slack.com/archives/C0123456789/p1792565843999999"))
    #expect(s.seconds == 1792565843)
    #expect(s.microseconds == 999999)
}

@Test func threadReplyKeepsTheWholeURLForTheQR() throws {
    let u = "https://example.slack.com/archives/C0123456789/p1792565843307099?thread_ts=1792565800.000100&cid=C0123456789"
    #expect(try SlackURL(u)!.card().url == u)
}

@Test func githubIssueBecomesACardWithRepoNumberAndSummaries() async throws {
    let h = GitHubHandler(runner: FakeRunner(stdoutFixture: "gh-issue-with-comments.json"), summarizer: TruncatingSummarizer(), now: fixedNow)
    let card = try await h.card(for: URL(string: "https://github.com/bash0C7/thermal-printer/issues/1")!)
    #expect(card.header.lines == ["bash0C7/thermal-printer"])
    #expect(card.header.emphasis == "#1")
    #expect(card.sections.map(\.label) == [nil, "最新コメント"])
}

@Test func issueWithoutCommentsHasNoLatestCommentSection() async throws {
    let card = try await handler(fixture: "gh-issue-no-comments.json").card(for: issueURL)
    #expect(card.sections.count == 1)
}

@Test func ghFailureFallsBackToTheUnknownURLCardWithAReason() async throws {
    let card = try await handler(failingWith: "HTTP 404").card(for: issueURL)
    #expect(card.kind == .url)
    #expect(card.note?.contains("取得できません") == true)
}

@Test func pullRequestURLUsesGhPrView() async throws {
    let runner = FakeRunner(stdoutFixture: "gh-pr.json")
    _ = try await GitHubHandler(runner: runner, summarizer: TruncatingSummarizer(), now: fixedNow)
        .card(for: URL(string: "https://github.com/bash0C7/thermal-printer/pull/2")!)
    #expect(runner.lastArguments.prefix(2) == ["pr", "view"])
}
```

- 検証: `--filter Sources`で合格。加えて、Claudeが`gh issue view 1 -R bash0C7/thermal-printer --json …`を実際に叩き、その出力でカードが作れることを、fixtureを1件増やす形で確かめる。
- commitのWhy: 「GitHubはgh（ユーザー決定）。取れないときに黙って失敗しないよう、知らないURLのカードに落として理由を出す。Slackのtsは浮動小数点で6桁目が狂うので整数で分ける。」

#### T2.9 リマインダー（EventKit）

- 目的: 今日まで（期限切れを含む）の未完了のリマインダーを取り、カードにする。
- 触るファイル: `app/Core/Sources/ThermalPrinterCore/Sources/{RemindersSource.swift, ReminderCard.swift}`、`app/Core/Tests/ThermalPrinterCoreTests/Sources/ReminderCardTests.swift`。
- 依存: T2.6。
- 担当: sonnet。
- 先に確かめること: EventKitのリマインダーのフルアクセスの要求（macOS 14以降の名前）、期限で絞る述語、`NSRemindersFullAccessUsageDescription`。
- 方針: EventKitに触る部分（`RemindersSource`）は薄く、`EKReminder`を`ReminderItem`（タイトル、リスト名、期限、メモ）に移すだけにする。カードへの変換（`ReminderCard`）は純粋な関数でテストする。カード: QRなし、上段にリスト名と期限、タイトルは`☐ ` + 件名、メモがあれば本文として折り返す。
- TDD:

```swift
@Test func reminderCardHasListAndDueInTheHeaderAndABallotBoxTitle() {
    let card = ReminderCard.make(ReminderItem(title: "牛乳を買う", list: "買い物", due: date(2026, 10, 24, 18, 0), notes: nil), now: date(2026, 10, 24, 9, 0))
    #expect(card.kind == .reminder)
    #expect(card.url == nil)
    #expect(card.header.lines == ["買い物"])
    #expect(card.title == "☐ 牛乳を買う")
}

@Test func overdueAndTodayAreIncludedButTomorrowIsNot() {
    let items = [item(due: yesterday), item(due: todayEvening), item(due: tomorrow), item(due: nil)]
    #expect(TodayFilter.reminders(items, now: todayMorning).count == 2)
}
```

- 検証: `--filter Reminder`で合格。EventKitの実データでの確認は、T2.16で権限ダイアログを出してから行う。
- commitのWhy: 「朝のタスク札のため、今日までのリマインダーを1件1枚にする。EventKitは権限ダイアログを伴うので、テストできる変換を外に出した。」

### T2.10 部品の帯の組み立て、長さ、警告

- 目的: 部品の列（テキスト / markdown / 画像 / カード）を1本の帯（`Bitmap1`）に組む。部品の間に切り取り線（破線）と余白、帯の最後に紙送りの白行、必要なら上端の白行。長さを計算し、警告を判定する。
- 触るファイル: `app/Core/Sources/ThermalPrinterCore/Strip/{Part.swift, StripComposer.swift, LengthPolicy.swift, PasteRouter.swift}`、`app/Core/Tests/ThermalPrinterCoreTests/Strip/{StripComposerTests.swift, LengthPolicyTests.swift, PasteRouterTests.swift}`。
- 依存: T2.3、T2.4、T2.6、T1.16（紙送りの白行の量と上端の白行の有無。無ければ仮の値で進め、T2.16の前に直す）。
- 担当: sonnet。
- TDD:

```swift
@Test func lengthIsRowsOverEightMillimeters() {
    #expect(LengthPolicy.centimeters(rows: 2400) == 30.0)
}

@Test func warningStartsAboveTheThreshold() {
    let p = LengthPolicy(thresholdCentimeters: 30)
    #expect(!p.isTooLong(rows: 2400))
    #expect(p.isTooLong(rows: 2401))
}

@Test func partsAreSeparatedByADashedCutLine() {
    let strip = StripComposer(feedRows: 0, topRows: 0).compose([.text("a"), .text("b")])
    #expect(strip.cutLineRows.count == 1)
    #expect(strip.bitmap.row(strip.cutLineRows[0]).isDashed)
}

@Test func trailingFeedIsAppendedAsWhiteRows() {
    let a = StripComposer(feedRows: 0, topRows: 0).compose([.text("a")]).bitmap.height
    let b = StripComposer(feedRows: 80, topRows: 0).compose([.text("a")]).bitmap.height
    #expect(b - a == 80)
}

@Test(arguments: [("https://github.com/a/b/issues/1", PasteRouter.Kind.card),
                  ("  https://example.com/x  \n", .card),
                  ("# 見出し\n本文 https://example.com", .markdown),
                  ("ただの文", .markdown)])
func pastedTextIsRoutedByContent(text: String, kind: PasteRouter.Kind) {
    #expect(PasteRouter.route(text: text) == kind)
}
```

- 検証: `--filter Strip`で合格。
- commitのWhy: 「カード数枚をアプリが1本の帯に連結し、CLIは1ジョブだけを送る（設計書§5.2）。長すぎる出力の警告（ユーザー決定）は、帯の行数から計算する。」

### T2.13 アプリのbundle、署名、TCCの経路

- 目的: アプリを`.app`として組み、同梱のpicorubyとCLIのsourceを入れ、TCCの許可が再ビルドで消えない署名をして、`~/Applications`に入れる。
- 触るファイル: `app/project.yml`（Info.plistのkey、ビルド後の処理）、`app/App/Info.plist`、`rakelib/app.rake`（`app:build`、`app:install`）。
- 依存: T2.1、T1.12、R0-3、T0.9。
- 担当: sonnet。
- 方針:
  - Info.plist: `NSBluetoothAlwaysUsageDescription`、`NSRemindersFullAccessUsageDescription`、`LSMinimumSystemVersion`。「iPhoneから読み込む」にカメラの宣言が要るかは、docsetとサンプルで確かめ、要るなら足す（設計書§11）。URLスキームはM3のT3.2で足す。
  - `app:build`: `vm:build` → `xcodegen generate` → `xcodebuild -project app/ThermalPrinter.xcodeproj -scheme ThermalPrinter -configuration Release CODE_SIGNING_ALLOWED=NO build` → 生成された`.app`の`Contents/MacOS/picoruby`にVMを、`Contents/Resources/cli/`に`cli/*.rb`を写す → `codesign --force --deep -s - -r='designated => identifier "com.bash0c7.thermalprinter"' <app>`。
  - `app:install`: `~/Applications/Thermal Printer.app`へ写す。
  - R0-3で経路4が通らないなら、picorubyは同梱せず、`PrinterClient`が`PhomemoPrint.app`（T1.12）を`open -W -a`で起動する。
- 検証:
  - `rake app:build` → exit 0。`codesign -d -r- "<app>"`の出力に`designated => identifier "com.bash0c7.thermalprinter"`がある。
  - `"<app>/Contents/MacOS/picoruby" -e 'p PhomemoThermalPrinter::Error'` → `PhomemoThermalPrinter::Error`（VMが同梱されている）。
- 実機: 不要。BLEの許可ダイアログはT2.16の最初にまとめる。
- commitのWhy: 「ad-hocの署名だけでは要件がcdhashになり、再ビルドのたびにBluetoothとリマインダーの許可が消える（stackchanの実測）。要件をbundle idに固定した。」

### T2.12 3ペインの画面、実寸プレビュー、長さの警告、状態表示

- 目的: 画面C（左「今日のカード」、中央「部品リスト」、右「実寸プレビュー」、フッター、タイトルバーの状態）を作る。
- 触るファイル: `app/App/`配下（`ContentView.swift`、`TodayColumn.swift`、`PartsColumn.swift`、`PreviewColumn.swift`、`FooterBar.swift`、`AppModel.swift`、`PhysicalScale.swift`）、`app/Core/Sources/ThermalPrinterCore/Strip/PhysicalScale.swift`と、そのテスト。
- 依存: T2.7、T2.9、T2.10、T2.11、T2.13。
- 担当: sonnet。
- 先に確かめること: `NavigationSplitView`の3列、ドロップ（`dropDestination`か`onDrop`）、⌘V（`onPasteCommand`）、「iPhoneから読み込む」（`ImportFromDevicesCommands`と`importsItemProviders`）、確認ダイアログ（`confirmationDialog`）の名前と引数をdocsetで確かめる。
- 画面の振る舞い:
  - 左: GitHub（`gh search issues --assignee @me --state open --json …`。field名は`--help`で確かめる）とリマインダーを並べ、チェックで中央に入れる。更新ボタン。Slackはここに出さない。
  - 中央: ドロップと⌘Vで追加（`PasteRouter`）。`.txt`はテキスト部品、`.md`は丸ごと1つのmarkdown部品、画像は画像部品。ドラッグで並べ替え、削除。選んだ部品の設定（写真なら明るさ・コントラスト・ガンマ・回転、テキストなら文字サイズ、markdownなら「プレーンテキストとして組む」）。
  - 右: 帯の`Bitmap1`をそのまま、画面上で実寸になる倍率で表示する。倍率は`PhysicalScale`（ディスプレイの物理サイズ`CGDisplayScreenSize`とピクセル数から、1 mmあたりのpointを出す純粋な関数）で決める。
  - フッター: 長さ（cm）、30 cmを超えたら警告、濃度（1〜5。T1.16の#8の結果をラベルにする）、印刷ボタン。長すぎるときは印刷ボタンで確認ダイアログ。
  - タイトルバー: 起動時、手動の更新ボタン、印刷の後に`--status`を取り直し、`PrinterStatusText.titleBar`を出す。`busy`なら前の表示のまま。
  - 印刷の失敗は、`PrinterStatusText.message`の言葉で出す（黙って失敗しない）。
- TDD: 画面そのものはT2.14のUIテストで縛る。ここでは`PhysicalScale`を先にテストする。

```swift
@Test func a27InchFiveKDisplayGivesAboutTwoPointsPerMillimeter() {
    let s = PhysicalScale(pixelsWide: 5120, millimetersWide: 597, backingScale: 2)
    #expect(abs(s.pointsPerMillimeter - 4.288) < 0.01)
}

@Test func previewWidthIs48Millimeters() {
    let s = PhysicalScale(pixelsWide: 5120, millimetersWide: 597, backingScale: 2)
    #expect(abs(s.points(forDots: 384) - 48 * s.pointsPerMillimeter) < 0.01)
}
```

- 検証: `--filter PhysicalScale`で合格。`rake app:build` → exit 0。Claudeがアプリを`open`で起動し、`screencapture -l`か`screencapture -x`で画面を撮って、3ペインが出ていることを自分で見る。
- commitのWhy: 「ユーザーが選んだ画面C。プレビューは印字される1bitのビットマップそのものを実寸で出し、別描画の近似を作らない。」

### T2.14 UIテスト（XCUITest）

- 目的: 画面の主要な操作を、Claudeが人の手を借りずに通せるようにする。
- 触るファイル: `app/UITests/{PasteAndPrintTests.swift, LengthWarningTests.swift, DeviceScenarioTests.swift}`、`app/UITests/Fixtures/fake-cli.sh`、`test/fixtures/meeting-memo.md`、`app/App/`のaccessibility identifier（T2.12のファイルに足すだけ）、`rakelib/app.rake`（`app:uitest`）。
- 依存: T2.12。
- 担当: sonnet。
- 方針: アプリは起動環境変数`THERMALPRINTER_CLI`があれば、そのパスのスクリプトをCLIとして使う（テスト用のfake。結果JSONを書いて終わる）。プロダクトの機能は足さない。
- テスト:
  - 文字列を貼る → 中央に部品が1つ増える → プレビューの高さが0より大きい。
  - URLを1本貼る → カード部品になる。
  - 印刷を押す → fakeが`ok: true`を返す → タイトルバーが更新される。
  - 長い文字列（31 cm以上）を貼る → フッターに警告 → 印刷で確認ダイアログが出る。
  - fakeが`not_found`を返す → 「電源ボタン」を含む言葉が出る。
  - `DeviceScenarioTests`（`RUN_DEVICE=1`のときだけ有効。T2.16で使う）: 場面1と場面2の部品を入れて、本物のCLIで印刷し、結果が`ok`になる。
- 検証: `rake app:uitest` → `** TEST SUCCEEDED **`。初回はmacOSがUIテストの補助（Accessibility / Automation）の許可を求めることがある。そのクリックだけ人間が要る（T2.16の1回目の依頼にまとめ、ここでダイアログ待ちになったら、そこで止めて報告する）。
- commitのWhy: 「GUIの完了を人の目視だけに頼らないため。CLIはfakeに差し替え、実機の印刷はT2.16で別に確かめる。」

### T2.15 敵対的レビュー（opus）

- 目的: anti-goal（はみ出し、黙って失敗、顔がつぶれる、プリンターを壊す）に穴が無いかを、白紙の文脈で確かめる。
- 依存: T2.14。
- 担当: opus（新しいsubagent。設計書§2のanti-goalと§5.3、`app/`のコードとテストだけを渡す）。
- 見ること: 文字を描く経路で`TextRenderer`を通らないものが無いか。anti-goalのテストに無い入力の種類（絵文字、結合文字、RTL、全角スペースだけの行、タブ）。CLIの失敗のうち、画面に出ない経路。アプリがCLIに渡す引数から、allowlist外のバイト列を作れる経路。
- 合格: 指摘0件、または全指摘が直され、`rake test`と`rake app:uitest`が通る。

### T2.16 実機セッションS2（人間の物理操作あり）

- 目的: アプリ経由（同梱のpicorubyを子プロセスで起動し、アプリがBluetooth許可の対象になる経路）でも、S1と同じ印字ができ、QRがスマホで読めることを確かめる。
- 紙の方針: 印字は1回、約6cm（GitHubのissue 1枚のカード）だけ。タスク札の残りの種類（リマインダー、Slack、知らないURL）、会議メモ、写真は、プリンターから見れば384 dot幅のビットマップの中身が違うだけなので、画面上のビットマップ（T2.3、T2.4、T2.6、T2.7、T2.9、T2.10のテストと目視のPNG、QRのVision読み戻し）で確かめ、紙には出さない。長尺の安定性（会議メモの26cmなど）は、専用の印字をせず、実際に使うときに確かめる。
- 依存: T2.15。直前に`rake test`、`rake app:build`、`rake app:install`。
- 担当: 判断は親（opus）。コマンドはhaiku。
- 段取り（人間への依頼は1回）:
  1. 「T02の電源を入れ、紙を入れてください。Macの前にいて、出てくる許可ダイアログ（Bluetooth、iCloud Driveのファイル、UIテストの補助）を全部『許可』してください。印字するのはGitHubのissue 1枚のカード（約6cm）だけです。印字物のQRをiPhoneのカメラで読んで、正しいページが開くか、右端・左端で切れている文字が無いか、行頭に『、。」ー』が無いかを、『ok / ng（どこが）』で返事をください。」
     - 返事を受けて、Claudeが実CLIの経路のUIテストを流す。`RUN_DEVICE=1`のときだけ有効な`DeviceScenarioTests`（T2.14で作る）が、`THERMALPRINTER_CLI`を渡さずに起動して、GitHubのissueのURL 1本を貼ってカードにし、本物のCLIで印刷する。
- 合格: 結果JSONが`ok: true`で`acks`と`chunks`が一致し、目視がok。ngなら、その原因をテストで再現してから直す（目視での当て直しをしない）。
- 実機: 要る。物理操作は上の1回だけ。リマインダーとiPhoneからの写真の取り込み（Continuity Camera）は、紙を使わない画面上の確認として、S2のダイアログ許可のあとに行う。

### T2.17 README

- 目的: 使う人が、セットアップから印刷までを手順どおりに進められるようにする。
- 触るファイル: `README.md`。
- 依存: T2.16。
- 担当: sonnet。
- 中身: 事実と手順だけ（理由と経緯を書かない）。前提（macOS、Xcode、mise、gh）、`rake vendor:setup`から`rake app:install`まで、初回の許可（とR0-5で要るならペアリング）、アプリの使い方（今日のカード、⌘V、ドロップ、iPhoneから読み込む、印刷）、ターミナルからの`bin/phomemo-print`、エラーの言葉と対処。
- 検証: 手順のコマンドを、上から順にClaudeが実際に叩いて通ることを確かめる（`vendor:setup`は済んでいれば冪等なので、そのまま叩く）。

### M2の完了ゲート

- [ ] `rake test`（Ruby + `swift test`）と`rake app:uitest`が通る。
- [ ] T2.16で、GitHubのissueのカード1枚が、アプリ経由でmacOSからT02実機に印字され、目視とQRの読み取りがokだった。タスク札の残りの種類、会議メモ、写真は、画面のビットマップとテスト（目視のPNGを含む）で確かめた。
- [ ] 目視で、はみ出し・行頭禁則の違反が無く、QRが読め、写真の顔がつぶれていない。
- [ ] T2.15の指摘が0件。

## 6. M3 skill

完了ゲート（設計書§8を、紙の浪費を避ける方針で変更。ユーザー承認済み）: Slackのカードが、skill経由でアプリの部品リストに正しく入り、QRが読める。紙には出さない。

依存の形:

```
T2.6 → T3.1 → 並列群D {T3.2, T3.3} → T3.4 → T3.5（opus）→ T3.6（実機）→ ゲート
```

### T3.1 カードJSONのスキーマ検証（アプリ側）

- 目的: 設計書§5.3.5のJSONを、アプリとskillで同じスキーマにし、検証をアプリ側に持つ。
- 触るファイル: `app/Core/Sources/ThermalPrinterCore/Card/CardValidator.swift`、`app/Core/Tests/ThermalPrinterCoreTests/Card/CardValidatorTests.swift`、`test/fixtures/cards/invalid-*.json`。
- 依存: T2.6。
- 担当: sonnet。
- 規則: `version`は1。`kind`は`github`/`slack`/`url`/`reminder`。`url`は`reminder`以外で必須、`http`か`https`。`header.lines`は1件以上。`title`は空でない。`sections`の`text`は空でない。未知のkeyはエラー（skillの綴りの誤りを黙って捨てないため）。文字数の上限は設けない（折り返すので）。
- TDD:

```swift
@Test(arguments: ["github", "slack", "url", "reminder"])
func validFixturesPass(name: String) throws {
    #expect(throws: Never.self) { try CardValidator.validate(fixtureData("cards/\(name).json")) }
}

@Test(arguments: [("invalid-version", CardValidator.Failure.unsupportedVersion),
                  ("invalid-kind", .unknownKind),
                  ("invalid-missing-url", .missingURL),
                  ("invalid-unknown-key", .unknownKey("titel")),
                  ("invalid-empty-title", .emptyTitle)])
func invalidFixturesFailWithTheReason(name: String, failure: CardValidator.Failure) {
    #expect(throws: failure) { try CardValidator.validate(fixtureData("cards/\(name).json")) }
}
```

- 検証: `--filter CardValidator`で合格。
- commitのWhy: 「skillが作るJSONの誤りを、アプリの入口で理由つきで止めるため。未知のkeyも止める。」

### 並列群D（T3.1の後）

#### T3.2 URLスキームの受け口

- 目的: `thermalprinter://add?card=<base64urlのJSON>`でカードを受け、検証し、部品リストに入れる。
- 触るファイル: `app/project.yml`（`CFBundleURLTypes`）、`app/App/Info.plist`、`app/App/URLIntake.swift`、`app/Core/Sources/ThermalPrinterCore/Card/CardURL.swift`、`app/Core/Tests/ThermalPrinterCoreTests/Card/CardURLTests.swift`、`app/UITests/URLSchemeTests.swift`。
- 依存: T3.1、T2.12、T2.13。
- 担当: sonnet。
- 受け渡しの形（設計書§11で任されたもの）: base64urlのJSONをクエリに入れる。一時ファイルのパスより、片付けが要らず、ファイルの読み取り権限の問題も無い。Slackの要約カードは数KBで、URLの長さに収まる。
- TDD:

```swift
@Test func base64URLRoundTrips() throws {
    let card = try fixtureCard("slack")
    #expect(try CardURL.decode(CardURL.encode(card)) == card)
}

@Test func invalidPayloadIsRejectedWithTheValidatorReason() {
    #expect(throws: CardValidator.Failure.unknownKind) {
        try CardURL.decode(URL(string: "thermalprinter://add?card=" + base64url(#"{"version":1,"kind":"mail"}"#))!)
    }
}
```

- 検証: `--filter CardURL`で合格。`rake app:uitest`で`URLSchemeTests`（`open`したURLでカード部品が増える。不正なものはエラーの言葉が出る）が通る。
- commitのWhy: 「skillからアプリへカードを渡す口。印刷ボタンはアプリ側で押す（GitHubやリマインダーのカードと一緒に出せるように）。」

#### T3.3 skillの補助スクリプト: permalinkの分解とカードの送り込み

- 目的: skillの手順のうち、決定的に計算できる部分をスクリプトにして、毎回同じ結果にする。
- 触るファイル: `bin/slack-permalink`、`bin/add-card`、`test/tools/slack_permalink_test.rb`、`test/tools/add_card_test.rb`。
- 依存: T3.1（fixture）。
- 担当: sonnet。
- `bin/slack-permalink <URL>`: JSONで`workspace`、`channel_id`、`ts`、`thread_ts`、`oldest`、`latest`（ts ±1µs）、`jst`を出す。±1µsは`秒 × 1_000_000 + µs`の整数で計算する（µsが`000000`と`999999`の繰り上げ・繰り下げを含む）。
- `bin/add-card <card.json>`: JSONを読み、base64urlにして`open "thermalprinter://add?card=…"`を叩く。`--print-url`ならURLを出すだけ。
- TDD:

```ruby
class SlackPermalinkTest < Minitest::Test
  def test_ts_is_split_into_ten_and_six_digits
    r = SlackPermalink.parse("https://example.slack.com/archives/C0123456789/p1792565843307099")
    assert_equal "1792565843.307099", r["ts"]
    assert_equal "1792565843.307098", r["oldest"]
    assert_equal "1792565843.307100", r["latest"]
    assert_equal "2026/10/21(水) 15:57", r["jst"]
  end

  def test_microsecond_borders_carry_and_borrow
    assert_equal "1792565844.000000", SlackPermalink.parse(url("p1792565843999999"))["latest"]
    assert_equal "1792565842.999999", SlackPermalink.parse(url("p1792565843000000"))["oldest"]
  end

  def test_thread_reply_keeps_the_parent_ts
    r = SlackPermalink.parse(url("p1792565843307099") + "?thread_ts=1792565800.000100&cid=C0123456789")
    assert_equal "1792565800.000100", r["thread_ts"]
  end
end

class AddCardTest < Minitest::Test
  def test_print_url_encodes_the_card_as_base64url_without_padding
    url = AddCard.url(File.read(fixture("cards/slack.json")))
    assert url.start_with?("thermalprinter://add?card=")
    payload = url.split("card=").last
    refute_match(/[+\/=]/, payload)
    assert_equal JSON.parse(File.read(fixture("cards/slack.json"))), JSON.parse(Base64.urlsafe_decode64(payload))
  end
end
```

- 検証: `rake test:tools` → `0 failures, 0 errors`。
- commitのWhy: 「tsの±1µsは浮動小数点だと6桁目が狂う（調査で確認済み）。skillの手順のうち計算で決まるところはスクリプトにして、毎回同じ結果にした。」

### T3.4 skill本体

- 目的: Slackのpermalinkを渡すと、Claudeが本文・channel名・投稿者・日時を取り、要約し、カードをアプリに入れるskillを書く。
- 触るファイル: `.claude/skills/print-slack-card/SKILL.md`。
- 依存: T3.2、T3.3。
- 担当: sonnet（下書き）。
- 中身（`docs/research/slack-connector-probe.md` §6を正とする）:
  1. `bin/slack-permalink <URL>`で分解する。
  2. 非スレッド: `slack_read_channel(channel_id, oldest, latest, response_format="detailed")`。返却ヘッダから`#channel名`を取る。
  3. スレッド返信: `slack_read_thread(channel_id, message_ts=thread_ts, oldest, latest)`で本文、channel名は`slack_read_channel`を別に1回。
  4. 投稿者名は`slack_read_user_profile`で安定させる。
  5. Slack記法の前処理: `<@U…|名前>` → `@名前`、`<#C…>` → `#名前`（2の手順で解決）、`<URL|ラベル>` → ラベル、`:emoji:` → 削除、`<!here>`など → 平文。
  6. 要約: タイトル1行（全角30文字以内）と本文の要約（3行以内）。
  7. カードJSONを書く（few-shotで`test/fixtures/cards/slack.json`の中身を示す）→ `bin/add-card <path>`。
  8. 失敗の区別: `channel_not_found`は「未参加のprivate channelか別のworkspace」、0件は「tsの誤変換か削除済み」。理由をユーザーに伝える。
  9. `slack_search_public_and_private`は使わない。
  10. 印刷ボタンはアプリで押す（skillは印刷しない）。
- 検証: T3.5のレビューと、T3.6の実走。

### T3.5 skillの敵対的レビュー（opus）

- 目的: skillが毎回同じ結果になるか、失敗を区別できるかを、白紙の文脈で確かめる。
- 依存: T3.4。
- 担当: opus（新しいsubagent。SKILL.md、`bin/slack-permalink`、`bin/add-card`、`CardValidator.swift`、slack-connector-probe.md §6・§7だけを渡す）。
- 見ること: 手順の分岐の抜け（DM、`G…`のchannel、スレッドの親そのもののURL）、前処理の規則の曖昧さ、JSONがCardValidatorを通らない書き方の余地、要約の長さの基準。
- 合格: 指摘0件、または全指摘が直された。

### T3.6 skillの実走と実機セッションS3

- 目的: 実際のSlackの発言から、skillが正しいカードを作り、アプリに入ることを確かめる。
- 紙の方針: **紙を使わない**。カードの描画と印字の経路は、S1とS2で実機の印字として確認済みで、Slackのカードは別のビットマップの中身が違うだけ。skillの正しさは、アプリの部品リストに入ったカードの内容（channel名、投稿者、日時、要約、QRの読み戻し）を画面上で確かめる。
- 依存: T3.5。
- 担当: 親（opus）がskillを実行する。
- 段取り（人間への依頼は1回）:
  - 「印刷してよいSlackの発言のURLを2本ください（スレッドの外の発言1本、スレッドへの返信1本）。アプリを開いておいてください。」
  - 返事を受けて、Claudeがskillを2本とも実行 → アプリに2枚のカードが入ったことを`screencapture`で確かめる → 部品リストのカードのビットマップをPNGにして、channel名・投稿者・日時・要約を目で確かめ、QRをVisionで読み戻して元の発言のURLと一致することを確かめる → 結果を「ok / ng」でユーザーに報告する。
- 実機: 不要（紙を使わない）。ユーザーに頼む操作はURLの提供だけ。

### M3の完了ゲート

- [ ] `rake test`と`rake app:uitest`が通る。
- [ ] SlackのURL 2本（スレッドの外と返信）のカードが、skill経由でアプリの部品リストに入り、内容（channel名、投稿者、日時、要約）が正しく、QRをVisionで読み戻して元の発言のURLと一致した。
- [ ] 目視で、内容が正しく、QRで元の発言が開く。
- [ ] T3.5の指摘が0件。

## 7. 設計書への指摘

設計書本体は編集していない。根拠つきで並べる。

1. **§4.1の環境の事実が変わっている。** 「R2P2-darwinの`.ruby-version`（4.0.5）は未インストール」とあるが、`mise ls ruby`は`ruby 4.0.5`を返し、repoで`ruby -v`は`ruby 4.0.5`だった。
2. **§7の「現時点ではgit管理されていない」が事実と違う。** repoはgit管理で、`bbc2df9 docs: record the approved design and research for the T02 printer tool`がある。GitHubにissue #1もある。
3. **ローカルcheckoutのパスが違う。** 設計書§4.2と調査書は`~/ghq/github.com/bash0C7/…`と書くが、このMacには`~/ghq/github.com/bash0C7/picoruby`が無く、`~/dev/src/github.com/bash0C7/{picoruby, R2P2-darwin, stackchan-picoruby}`がある。
4. **§6.6の終了条件が2通りに読める。** 「次の2つを満たしてから終了する」を字のとおりに読むと、`1a 0f 0c`が来ても時間の上限まで必ず待つことになり、`1a 0f 0c`を待つ意味が無くなる。計画では「`1a 0f 0c`を受け取り、かつ最後のwriteから2秒経った」か「上限を過ぎた」の早い方で終える（§2.8の6）。
5. **§6.7の事前確認に温度が無いのに、過熱でエラーにする。** 事前確認の問い合わせは紙・カバー・電池の3つだが、「紙切れ・カバー開・過熱なら送らずにエラー」とある。過熱は問い合わせなしの通知でしか分からない。計画では、allowlistにある`1f 11 13`を事前確認に足した（§2.8の4）。
6. **`status_unavailable`の扱い。** 設計書§6.7を、紙かカバーの応答が得られないとき、印刷でも`--status`でもエラー（exit 15）にし、印刷では何も送らない形に直した（§2.7）。電池か温度だけが得られないときは`status_partial`の警告で印刷する。
7. **`low_battery`の閾値が書かれていない。** 計画では5%以下（`a2`〜`a4`を含む）をエラー、10%以下を警告にした。
8. **入力の誤りのエラー種別が無い。** §5.2のエラー種別には、PBMが読めない・幅が384でない・引数の誤りに当たるものが無い。計画では`usage`と`invalid_input`を足した（exit 2）。
9. **M1の完了条件の「写真のPBM」を作る手段がM1に無い。** PicoRubyに画像のデコードは無く、ディザはM2のアプリが担う（§3）。計画では、M2の画像ディザ（T2.4）と、画像からPBMを作る`thermal-pbm`ツールをM1と並行して前倒しで作る。
10. **§3の`require 'phomemo_thermal_printer'`と既定の`require`名が違う。** `spec.require_name`を書かないと`require`名はgem名から`picoruby-`を落とした`phomemo-thermal-printer`になる（r2p2-darwin-and-gems.md §4.2）。計画では`spec.require_name = 'phomemo_thermal_printer'`を書いて設計書に合わせた。mruby VMでは`require`はno-opなので、動作には影響しない。
11. **§5.1.1の「picorubyの既存gemに前例があれば合わせる」について。** 前例は無かった（§2.5）。設計書が代わりに挙げる`build.darwin?`の仕掛けで実装する。設計書との食い違いではないが、確認した事実として残す。
12. **§6.4の「CLIは最後に`1b 64 03`だけを送る」と、§8.1 #7の「n = 1, 3, 6で紙送り量を測る」が両立しない。** #7を確かめるにはnを変えて送る口が要る。計画では、引数には足さず、環境変数`PHOMEMO_FEED`（0〜255。allowlistの範囲）でだけ変えられるようにした（T1.10a）。アプリは常に既定の3で送る。
13. **§13.7の「2台以上見つかったときの扱い」は、picoruby-bleのdarwin版では「最初の1台」しか素直に選べない。** `connect`は`advertising_report_callback`の中でしか呼べず、ADVは1台につき1回しか来ない（picoruby-ble-darwin.md §2.3、§3.7）。計画では最初の1台に繋ぎ、別機種への誤接続は`gatt_report`で止める（T1.9）。
