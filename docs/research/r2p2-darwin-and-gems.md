> 2026-10-24 の調査報告の写し。本文中の `/private/tmp/...scratchpad/...` のパスは調査時の一時領域で、もう存在しない可能性がある。

# 調査報告: R2P2-darwin / R2P2-dev-harness / picoruby(port-darwin) と新 mrbgem の作法

調査日: 2026-10-24。コード変更・build 試行なし（読み取りと `git fetch` のみ）。

略記: `RD` = `~/ghq/github.com/bash0C7/R2P2-darwin`、`DH` = `~/ghq/github.com/bash0C7/R2P2-dev-harness`、`PR` = `~/ghq/github.com/bash0C7/picoruby`。

---------------------------------------------------------------------

## 0. 先に結論

1. **R2P2-darwin は「PicoRuby を Apple 系 (macOS host / iOS / watchOS) でビルドして動かす harness」**。macOS host では `rake macos:build` が `vendor/picoruby`（fork `bash0C7/picoruby` の `port-darwin` を clone したもの）を `cd vendor/picoruby && rake` でビルドし、`build/host/bin/{picoruby,r2p2}` を作る。`picoruby` は `picoruby [switches] [programfile] [arguments]` 形式で `.rb` を直接実行でき、ARGV / ENV / stdin / exit code が使える。`r2p2` は対話 shell。
2. **R2P2-dev-harness は Pico 2 W / ESP32 の実機を焼く・転送する・走らせる rake タスクと、実機の罠の知見集** であって、macOS CLI 向けの基盤ではない。ただし「新 gem を repo 側 `gems/` に置き、build_config から `conf.gem gemdir:` で指す」「host で picotest を回す」という **gem 置き場とテスト runner の前例** が丸ごとある。
3. **新 gem を picoruby 本体ツリーの外に置くのは問題なくできる。** 前例が 3 つある（RD の iphone-torch gem、RD の `macos:single`、DH の `gems/`、さらに `stackchan-picoruby` の `mrbgems/`）。`conf.gem gemdir: "<絶対パス>"`（または `conf.gem "<絶対パス>"`）で足りる。
4. **gem の作法**は「`mrbgem.rake` + `mrblib/*.rb` (+ `src/` + `include/` + `ports/<platform>/` + `sig/` + `test/*_test.rb`)」。mruby VM と mruby/c の分岐は C 側が `#if defined(PICORB_VM_MRUBY)` で `src/mruby/…` と `src/mrubyc/…` を include、Ruby 側 (mrbgem.rake) が `build.picoruby?` / `build.femtoruby?`。mruby VM だけでよいなら `src/mruby/` だけで足りる（iphone-torch gem は mruby 側のみ）。
5. **テスト**は picotest（`Picotest::Test`、`test/*_test.rb`）。Runner は CRuby で動き、ホストの picoruby VM を子プロセスで起動して結果を JSON で受ける。upstream の `rake test:gems:picoruby[gem]` は `mrbgems/` 直下の gem しか拾わないので、**外置き gem のテスト runner は自前で持つ**（DH の `rakelib/test.rake`、stackchan の `test/picotest/harness.rb` が実装済み）。
6. CLI に要る基本機能（File/IO/Dir/stdin/ARGV/ENV/sleep/Time/pack/unpack/base64/JSON/String のバイト操作）は **`mruby-posix` + `minimum` + `core` + `stdlib` の 4 gembox でほぼ全部入る**。**zlib (inflate) と PNG デコードは無い**。
7. **要注意の最大リスク: BLE の macOS TCC。** R2P2-darwin と stackchan-picoruby の実測では、CoreBluetooth を使う picoruby を **シェルから直接 exec すると SIGABRT**。`NSBluetoothAlwaysUsageDescription` を持つ `.app` bundle 経由（`open -a` または launchd）で起動する必要がある。「普通の CLI として叩く」設計はここで制約を受ける（§8）。

---------------------------------------------------------------------

## 0.1 各 repo の git 状態（`git fetch` 後）

| repo | 現在 branch | HEAD | リモートとの差 | 備考 |
|---|---|---|---|---|
| RD | `main` | `08986d9` build(watchos): drop hal-io-darwin from the watchOS configs | なし (clean, up to date) | remote branch: `origin/main`, `origin/dependabot/github_actions/actions/upload-artifact-7`。`vendor/` `build/` は未生成（まだ一度もビルドされていない） |
| DH | `main` | `e82749c` Merge PR #26 (picoruby-tree-anywhere) | なし (clean) | remote: `claude/ci-execution-conditions-rbp2f8`, `claude/r2p2-dev-harness-issue-4-9i7aup`。`vendor/` には `R2P2-ESP32` のみ |
| PR | **`master`**（`port-darwin` ではない） | `65b7ae62` Update docs (2026-09-17) | origin/master と同じ。untracked `.agents/`（pico-debug skill、無関係） | **`origin/port-darwin` は `31de5488` (2026-10-11)。ローカル未 checkout**。master と port-darwin の merge-base は `77927f45` で、master のみ 6 commit / port-darwin のみ 90 commit（port-darwin は master に対し 6 commit 遅れ） |

- PR は checkout していない（書き込みになるため）。`port-darwin` の内容は `git archive origin/port-darwin` を scratchpad `.../scratchpad/pd/` に展開して読んだ（submodule は含まれない）。mruby 本体 (`mrbgems/picoruby-mruby/lib/mruby` = `7b4e0f3b7`) と mruby-compiler (`beb0107`) は port-darwin と master で同じ SHA（`git ls-tree origin/port-darwin` と `git submodule status` で確認）なので、ローカル checkout 側の mruby ソースを読んだ。
- 以降 `PD:` は `origin/port-darwin` 上のパス（展開コピー `.../scratchpad/pd/<path>` で行番号を取った）。
- RD の `vendor/picoruby` は RD 自身が `rake setup` で別途 clone する（PR の ghq clone は使われない）。

---------------------------------------------------------------------

## 1. R2P2-darwin

### 1.1 何か
- `RD/README.md:7-15`: 「PicoRuby を Apple platforms (macOS host / iOS Simulator・実機 / watchOS) でビルドして動かす」。R2P2 harness family の Apple 版。picoruby を静的ライブラリ `libmruby.a` に cross-build し、C bridge 経由で SwiftUI app に載せる。example app の振る舞いは Ruby ファイル (`app.rb`) に全部ある（prism compiler も VM に入っているので app 内で実行時 compile）。
- R2P2（PicoRuby の対話 shell）は、macOS host では `rake macos:build` が `picoruby-bin-r2p2` 実行ファイルを作り、`rake macos:run` で shell に入れる (`RD/README.md:59-89, 252-263`)。
- `RD/CLAUDE.md` は README に無いことだけを書く方針（`RD/CLAUDE.md:3-5`）。

### 1.2 picoruby の取り込み方（submodule ではなく「gitignore された clone」）
- `RD/Rakefile:6-10`: `PICORUBY_REPO`（既定 `https://github.com/bash0C7/picoruby.git`）、`PICORUBY_REF`（既定 `port-darwin`）、`PICORUBY_SRC = RD/vendor/picoruby`、`BUILD_DIR = RD/build`。
- `RD/Rakefile:336-343` `rake setup`: `git clone --recursive --branch $PICORUBY_REF $PICORUBY_REPO vendor/picoruby` + prism の `diagnostic.h` 生成 (`generate_prism_templates`, `RD/Rakefile:88-102`)。約 1.2 GB（build 後は約 3 GB, `RD/README.md:55-57`）。`rake refresh` で `PICORUBY_REF` を fetch し直す（`RD/Rakefile:345-350`）。
- `vendor/` と `build/` は `.gitignore` 済み（`RD/.gitignore`）。`RD/CLAUDE.md:14`: `vendor/picoruby` は生成物で commit しない。
- 未 push の fork commit を試すには `PICORUBY_REPO=<ローカルパス> PICORUBY_REF=port-darwin rake refresh`（`RD/CLAUDE.md:17-21`）。
- なぜ fork か: upstream picoruby master には darwin port (ble, rng, mbedtls, io-console, machine, socket) が無い (`RD/README.md:415-426`)。

### 1.3 ビルド手順と前提ツール（macOS host）
README `RD/README.md:252-278`、`RD/rakelib/macos.rake`:

```sh
rake macos:check     # Xcode CLT, brew openssl@3, Swift を確認 (macos.rake:19-42)
rake macos:build     # cd vendor/picoruby && rake  → ./build/host/bin/{picoruby,r2p2}
rake macos:run                    # r2p2 shell (macos.rake:49-61)
rake macos:run APP=path/to.rb     # picoruby で .rb を 1 本実行 (exec pr app。引数は渡せない)
rake macos:single APP=x.rb        # スクリプト埋め込みの単体バイナリ (§1.5)
MRUBY_CONFIG=build_config/r2p2-picoruby-darwin-ble.rb rake macos:build   # BLE 付き
```

- 前提: Xcode Command Line Tools、Homebrew `openssl@3`（networking gembox が ssl/crypto を link する）、Swift（picoruby-ble の darwin port が `swift build` で dylib を作る。`PD:mrbgems/picoruby-ble/mrbgem.rake:12-41`、Swift 6.3+ — `PD:.../ports/darwin/README.md:143`）、Ruby ≥ 2.7（Rakefile を回す側。`.ruby-version` は 4.0.5）。picoruby 自身の README は CRuby 3.4+ を求める (`PD:README.md` Build 節)。iOS/watchOS を作る時だけフル Xcode と `xcodegen`。
- `macos_build_env` (`macos.rake:6-16`): `MRUBY_BUILD_DIR=RD/build`、brew の openssl を `LDFLAGS`/`CFLAGS` に足す、`MRUBY_CONFIG` は環境変数優先（`File.absolute_path` するので **任意の絶対パスの build_config を渡せる**）。
- **この Mac の実測（読み取りのみ）**: `/usr/bin/swift` = Swift 6.4、Xcode.app あり、`/opt/homebrew/opt/openssl@3` あり、`xcodegen` あり。**ただしこのシェルの `ruby -v` は 2.6.10（システム Ruby）**。mise には 4.0.3 / 4.0.4 / 4.0.6 が入っているが、RD の `.ruby-version` が要求する 4.0.5 は未インストール（`mise exec -- ruby -v` も 2.6.10 を返した）。**ビルド前に Ruby ≥ 3.4 を有効にする必要がある**。
- stackchan-picoruby の `CLAUDE.md` の実測メモ: swiftly の Swift (`~/.swiftly/bin`) が PATH で Xcode の `/usr/bin/swift` より先に来ると picoruby-ble の Swift package が build できない（`unknown argument: '-target-arch-variant'`）。Xcode の `swift` が先に来る PATH で回す。また `vendor/` が symlink の checkout からは build が通らない。

### 1.4 生成物
- `RD/build/host/bin/picoruby`（`.rb`/`.mrb` ランナー）、`RD/build/host/bin/r2p2`（対話 shell）。`MRuby::Build.new` に名前を付けなければ build 名は `host`（`RD/build_config/r2p2-picoruby-darwin.rb:8`）。
- iOS/watchOS 向けは `build/<name>/lib/libmruby.a` + headers を各 example の `Vendor/` に stage（`RD/Rakefile:56-69`）。
- build dir の stale 化は `.r2p2-build-stamp`（picoruby SHA + build_config の digest）で防ぐ（`RD/Rakefile:20-51`）。**host build (`macos:build`) は `stage_libmruby` を通らないので、この stamp の保護は無い**（`rake refresh` 後は `rake clobber` 的に `build/host` を消すのが安全、と読める）。

### 1.5 build_config と gem の選び方
- ホスト用 3 本 (`RD/build_config/`):
  - `r2p2-picoruby-darwin.rb`（基本）: `conf.toolchain :gcc`、defines（`PICORB_PLATFORM_POSIX` と `PICORB_PLATFORM_DARWIN` の **両方**、`MRB_INT64`, `MRB_NO_BOXING`, `MRB_UTF8_STRING`, `MRB_TICK_UNIT=4`, `MRB_TIMESLICE_TICK_COUNT=3`, `PICORB_ALLOC_ALIGN=8`, `PICORB_ALLOC_ESTALLOC`）、`conf.picoruby`、`conf.linker.libraries << "ssl" << "crypto"`、`conf.gembox` を `mruby-posix` / `minimum` / `core` / `stdlib` / `shell` / `networking`、`conf.gem core: "picoruby-bin-picoruby"` / `picoruby-bin-r2p2` / `picoruby-shinonome`（`:8-35`）。
  - `r2p2-picoruby-darwin-ble.rb`: 上に `picoruby-ble` と `picoruby-picotest` を足しただけ（`:35-36`）。
  - `r2p2-picoruby-darwin-single.rb`: `picoruby-bin-picoruby` / `picoruby-bin-r2p2` を外し、`mruby-compiler` + `mruby-bin-mrbc` + `picoruby-mruby` + gembox (`mruby-posix`, `core`, `stdlib`) + **`conf.gem bin_gem`（絶対パス、環境変数 `R2P2_SINGLE_GEM_PATH` 経由）** (`:23-37`)。
- 約束事 (`RD/CLAUDE.md:28-66`): 共有 base に example 固有 gem を足さない（そのgemを使わない example が未解決シンボルで壊れる）。`picoruby-ble` の `picoruby-mbedtls` / `picoruby-rng` 依存を外さない（外すと BLE の Ruby 層が丸ごと未ロードになり `BLE.new` が `wrong number of arguments`）。`conf.ports :darwin, :posix` で「gem が `ports/darwin/` を持てばそれ、無ければ `ports/posix/`」。
- **未反映の差（要確認）**: stackchan-picoruby の Mac 用 config（`stackchan-picoruby/build_config/darwin-stackchan-pc.rb:29`）は `conf.gem core: "hal-task-darwin"` を足している。port-darwin の `mrbgems/hal-task-darwin/`（`PD:mrbgems/hal-task-darwin/mrbgem.rake`, `src/task_hal.c:1-30`）は「SIGALRM を VM thread だけに配送する POSIX HAL」で、CoreBluetooth / dispatch timer の別 thread で `mrb_tick` が走る競合を避ける。**RD の `r2p2-picoruby-darwin-ble.rb` にはこの gem が入っていない**（RD 内で `hal-task-darwin` は 0 件）。macOS host で BLE を使う自前 config には足すのが安全（iOS/watchOS config には足さない: `bridge/task_hal_ios.c` と二重定義, `stackchan CLAUDE.md` launchd 節）。

### 1.6 `.rb` をシェルから実行できるか / 対話だけか
- **`picoruby` バイナリが直接 `.rb` を実行できる**: `PD:mrbgems/picoruby-bin-picoruby/tools/picoruby/picoruby.c`
  - `:132-150` usage: `picoruby [switches] [programfile] [arguments]`、`-e 'command'`、`-r library`、`-c`（構文チェック）、`-b`（RiteBinary）、`-v`。`a.rb,b.rb` のようにカンマ連結で複数ファイルを別 task として実行も可。`.mrb`（先頭 `RITE`、`picorb_mrb_p` `:160`、読み込み分岐 `:675`）も実行可。
  - `:477-497`: **`ARGV` 定数が定義される**（programfile より後ろの引数）。`$0` も設定。
  - `:762-775`: 未処理例外は stderr にバックトレースを出し **終了コード 1 (`EXIT_FAILURE`)**。
  - `Kernel#exit(status)` は `Machine.exit(status)` → C の `exit(status)`（`PD:mrbgems/picoruby-machine/mrblib/kernel.rb:51-53`、`PD:mrbgems/picoruby-machine/ports/darwin/machine.c:282-284`）。**終了コードは任意に返せる**。
  - bintest (`PD:mrbgems/picoruby-bin-picoruby/bintest/picoruby.rb`) も「未処理例外で out は空、err に `boom (RuntimeError)`、status 失敗」を確認している。
- `r2p2` バイナリは対話 shell（`picoruby-shell`）。`shell.rb` に `Shell.find_executable`（PATH 上のファイルを探して起動, `PD:mrbgems/picoruby-shell/mrblib/shell.rb:273-290`）はあるが未精読。CLI 用途では `picoruby` ランナーを使う（対話 shell は REPL 用途）。
- `rake macos:single APP=x.rb` は gem の mrblib に `x.rb` を埋め込んだ **単体バイナリ**（`macos.rake:63-139`）。ただし生成する C main (`:102-128`) は `picorb_vm_init()` して終わるだけで **ARGV を定義しない**。引数付き CLI には向かない（`picoruby <script> args` + シェルラッパーのほうが素直）。
- `STDIN`/`STDOUT`/`STDERR`/`$stdin` は `PD:mrbgems/picoruby-machine/mrblib/kernel.rb:57-61`。`gets`/`getc` は端末ならHAL ring buffer 経由、リダイレクト時は `$stdin.gets`（`:24-37`、コメントに理由あり）。
- ファイル読み込み: mruby-io (`IO.read`, `File.open`, `File.size`, `File.expand_path`, `File.basename`, `File.join` 等) + mruby-dir (`Dir.entries`, `Dir.children`, `Dir.exist?`, `Dir.mkdir`, `Dir.getwd`)。`RD/examples/macos/ls/ls.rb` が `Dir.entries` / `File.directory?` / `File.size` / `sprintf` を使う動く例。
- 環境変数: `ENV` は `picoruby-env`（`PD:mrbgems/picoruby-env/src/mruby/env.c:104-111`）。**`ENV[]`, `ENV[]=`, `ENV.delete`, `ENV.each`, `ENV.keys` のみ。`ENV.fetch` は無い。** `require "env"` を書いている例が `RD/examples/macos/ble-subscribe/ble-subscribe.rb:7`（`picoruby-time` が env に依存するので core gembox 経由で入るが、明示的に書くのが慣習）。
- スリープ/時刻: `sleep`（秒）、`usleep`、`sleep_ms` は mruby-task が Kernel に定義（`mruby-task/src/task.c:1987-1989`）、`Time` は `picoruby-time`（core gembox）。

### 1.7 BLE を載せた host CLI の実行制約（TCC）
- `RD/README.md:271-278`: BLE config でビルドした `picoruby` は **直接実行不可**。macOS TCC が、LaunchServices が `NSBluetoothAlwaysUsageDescription` を宣言した app bundle から起動したのではないプロセスの CoreBluetooth 呼び出しを `SIGABRT` で落とす（署名や事前許可は無関係）。`RD` 側は binary を作るところまで、bundle 化と `open -a` は consumer の仕事。
- `RD/examples/macos/ble-subscribe/README.md:20-62`: bundle 化の実例 (`~/Applications/PicoRubyBLE.app/Contents/{MacOS/picoruby-bin,Info.plist}` + `codesign --force --deep -s -`)、起動は `open -W -a "$app" --stdout /tmp/x.log --stderr /tmp/x.log --env TARGET_NAME=PicoRuby --args "$PWD/script.rb"`（`open` は絶対パス必須、初回は Bluetooth 許可ダイアログ）。**この方式では stdin は使えず、exit code の伝搬も未確認**。
- 実運用で更に踏み込んだ解は stackchan-picoruby (§3): **daemon を launchd の LaunchAgent として `.app` bundle 内の binary で起動し、CLI は薄いクライアントとして TCP/dRuby で daemon に接続**。署名は `codesign --force --deep -s - -r='designated => identifier "com.bash0c7.stackchanpico"'` で designated requirement を identifier に固定（そうしないと cdhash が要件になり、再 build のたびに別 app 扱いで TCC 許可が消える）。
- 食い違う記述: `PD:build_config/darwin-ble-test.rb:20-24` は「bare CLI Mach-O でも `-Wl,-sectcreate,__TEXT,__info_plist,<plist>` で Info.plist を埋め込めば TCC が読める」というコメントを持つが、同じ作者の RD/stackchan は「直接 fork/exec は署名・許可済みでも必ず crash」と実測で書いている。**どちらが現環境で成り立つかは未検証。** 新 CLI を作る前に、最小の BLE scan スクリプトを 3 通り（直接 / `.app`+`open -a` / sectcreate）で試して確かめるのが安い。

---------------------------------------------------------------------

## 2. R2P2-dev-harness

### 2.1 何のためのものか
- `DH/README.md:3-16`, `DH/CLAUDE.md:3-9`: bash0C7 個人が **PicoRuby の「装置」(Pico 2 W / ESP32) を作るための知見と rake タスクを 1 箇所に集約する repo**。中心は「実機を焼く・転送する・走らせる・再起動する」rake (`rake rp2040:*`, `rake esp32:*`) と、実機の罠 (`DH/docs/spec.md` §6 Pico 2 W、§9 ESP32)。PicoRuby を USB 周辺機器にするライブラリ (`gems/`) と example (`examples/rp2040/`) は、その上に載せた実例のひとつ。
- Claude 用の作業環境でもある: `.claude/skills/r2p2-container/SKILL.md`（Apple Container で build/QEMU を回す手順）、CLAUDE.md が「Pico 2 W は Claude が Bash から直接触る」運用を規定。
- v1 スコープ (`DH/README.md:18-30`): 対象は rp2040 (Pico 2 W) が主、ESP32 は実機 rake のみ。**Mac は「相手役と開発機」で、darwin 版の USB 機器・iPhone/Apple Watch は対象外**。→ **macOS CLI 向けの基盤としては使えない**。そのまま流用できるのは「gem の置き方」「host テストの回し方」「作業規律」。
- 現状の gem は `gems/picoruby-usb-peripheral`, `-cdc-midi`, `-hid-mouse`, `picoruby-ble-dev-bridge`（全て pure Ruby。`DH/README.md:154-185`）。

### 2.2 使い方（要点）
- `rake setup` で `vendor/picoruby`（既定は **upstream** `picoruby/picoruby` master、`DH/Rakefile:7-9`）を `git clone --depth 1`、host build に要る submodule だけ取得 (`DH/Rakefile:29-36`, `DH/rakelib/vendor.rake:1-47`)。`rake test` = `test:host`（picotest）+ `test:examples`（mrbc で example を compile）。`rake -T` で一覧。実機は `rake rp2040:{build,flash,upload,run,reboot}`、`rake esp32:*`、container 経由は `rake "container:rake[<task>]"`。
- `DH/Rakefile:50-54` `SUBMODULE_PINS`: **Pico 2 W が起動時に固まる問題を避けるため mruby-compiler 等 3 つの submodule を古い SHA に固定**。port-darwin の tree にそのまま `rake setup` を流すと compiler pin が変わって破壊的なので、DH の `setup`/`refresh` を darwin 用の tree にかけない。
- `DH/Rakefile:20-25` + `vendor.rake:49-88`: upstream の `build_config/r2p2-picoruby-pico2_w.rb` を `*.upstream.rb` に退避して、harness の build_config を `load` するだけの shim に置き換える（upstream の r2p2 task が build_config の path を決め打つため）。

### 2.3 他 2 repo との関係
- 直接の依存はない。`DH/README.md:5` は R2P2-darwin / R2P2-ESP32 / picoruby/picoruby / picoruby-ble-verify に散らばった知見を集める、と述べる。`DH/docs/spec.md:200` は build dir の stale 化防止（stamp）を「R2P2-darwin と同じ方法」と明記（考え方の借用）。
- picoruby は **upstream master** を `vendor/` へ取得（darwin port なし）。R2P2-darwin の `port-darwin` fork とは別の ref。

### 2.4 決まった開発手順・ルール（DH/CLAUDE.md:11-35, DH/README.md:32-37, DH/docs/spec.md）
- **完了の線引きは実機。** `rake test`（host）が green でも実機で走らせるまで「動いた」と書かない（`CLAUDE.md:13`、`spec.md` §5）。実機が使えない環境では 1 行報告して完了宣言を保留。
- **`vendor/picoruby` は生成物で commit しない。** 変更は `firmware-patches/`（build 中だけ当てる）か build_config の overlay で行う。
- 守る制約 (`README.md:32-37`): 既存 library/repo に直接変更を加えない／git submodule は harness から直接使わない／既にあるライブラリは活かす（置き換えず上に載せる）。
- gem は `gems/<name>/{mrbgem.rake,mrblib,sig,test}`、build_config から `conf.gem gemdir: "#{HARNESS_ROOT}/gems/<name>"`（`spec.md:109-156`）。**build_config は upstream を複製せず `load` して gem を足すだけ**（`DH/build_config/host-test.rb:11-22`, `rp2040-pico2_w.rb:12-19`）。「器と結線は別 gem」。
- **`gems/*/mrbgem.rake` は ASCII だけ**（日本語コメントがあると locale 空の CI で `invalid byte sequence in US-ASCII`）。`mrblib/` の日本語コメントは可（`spec.md:229-237`）。
- 板の serial/USB を開くものは board 単位の lock、`tmo.rb` で時間を区切る、`.rb` は mrbc で `.mrb` にして送る (板上 prism が heap を食うため)、長い処理は `nohup ... & disown` で切り離す、など実機固有の規律（macOS CLI には関係薄）。
- Mac はクリーンに保つ: ESP-IDF / arm-none-eabi / gem は Apple Container 内で回す（host での brew/mise/gem install を提案しない）。ただし picoruby の **host テスト (`rake test:host`) 自体は Mac 上で直接回す**。
- branch/PR: 規則の明文は無し。履歴は `claude/...` branch → PR → merge commit (`e82749c Merge pull request #26 ...`)。TDD の明文規則も無いが、gem ごとに `test/*_test.rb` を必ず持つ構成。

---------------------------------------------------------------------

## 3. 補足: stackchan-picoruby（3 repo 外だが、RD README が worked example として参照している実例）

`~/ghq/github.com/bash0C7/stackchan-picoruby`（ローカル clone 済み）。**「Mac 上の PicoRuby CLI + BLE central + 外置き gem」の完成形** で、今回の計画にほぼそのまま写せる。

- `pc/stackchan-pico/README.md`: 構成は `bin/stackchan`（sh ラッパー: `exec "$VM" boot_cli.rb "$ROOT" "$PORT" "$@"` だけ）→ PicoRuby CLI → drb(TCP) → PicoRuby daemon（BLE central）。daemon は launchd の LaunchAgent で `~/Applications/StackchanPico.app/Contents/MacOS/picoruby` を直接起動。
- `Rakefile` (stackchan) `:783-807`:
  - `pc:vm_build`: `MRUBY_BUILD_DIR=<RD>/build MRUBY_CONFIG=<stackchan>/build_config/darwin-stackchan-pc.rb rake -C <RD>/vendor/picoruby` → **自 repo の build_config と RD の picoruby tree を組み合わせる**。
  - `pc:app_bundle`: build した `picoruby` を `.app` に copy、`Info.plist` を置き、`codesign --force --deep -s - -r='designated => identifier "..."'`。
  - `vendor:r2p2_darwin:setup` (`:34-41`): RD を `vendor/R2P2-darwin` に clone して `rake -C <RD> setup`。
- `build_config/darwin-stackchan-pc.rb:1-30`: RD の darwin-ble config + `hal-task-darwin`（`picoruby-picotest` も）。**gem は VM に焼かず、Ruby source を `load` する運用**（`CLAUDE.md` 構成節: 「VM は StackChan のコードを持たない。daemon は controller gem を source で load」）。iOS/watchOS config では gem を `conf.gem gemdir: File.expand_path("../mrbgems/<gem>", __dir__)` で焼く (`build_config/darwin-stackchan-ios-sim.rb:62-66`)。
- gem 規約（`stackchan CLAUDE.md` PicoRuby らしさ節）: `mrbgem.rake` + `mrblib/<gem>.rb`（+ `mrblib/<gem>/*.rb`）+ `test/*_test.rb`。`mrblib` 内で sibling を `require` しない（build が全部 bundle する）。on-device の `require` 名は gem 名から `picoruby-` を落とした hyphen 形。例外を流れ制御に使わない、など。
- テスト（`CLAUDE.md` テスト節、`test/picotest/harness.rb`）: CRuby orchestrator が「CRuby 側で load するもの」と「VM script に埋め込む source のリスト」を suite ごとに持ち、`build_config/picoruby-test.rb`（upstream の picoruby-test.rb 同等 + picotest）で作った host VM で fake を注入して回す。pc suite は CRuby と host VM の両方で走る。「BLE の実体は薄い adapter に隔離し、ロジックは素の class に出す」が明文の方針。

---------------------------------------------------------------------

## 4. mrbgem の作法（picoruby port-darwin）

### 4.1 ディレクトリ構成（実例）
PD の `mrbgems/picoruby-base64/`（C 拡張あり・mruby/c 両対応・テストあり。ソース全文は本 gem で確認済み）:

```
picoruby-base64/
  mrbgem.rake                  # 5 行
  mrblib/base64.rb             # Ruby 側 (class Base64 ... urlsafe_*)
  src/base64.c                 # VM 共通部 + #if PICORB_VM_MRUBY / MRUBYC で include 分岐
  src/mruby/base64.c           # mruby VM 版の C 実装
  src/mrubyc/base64.c          # mruby/c 版の C 実装
  sig/base64.rbs               # steep 用の型定義
  test/base64_test.rb          # picotest
  README.md
```

`mrbgem.rake` 全文（`PD:mrbgems/picoruby-base64/mrbgem.rake`）:

```ruby
MRuby::Gem::Specification.new('picoruby-base64') do |spec|
  spec.license = 'MIT'
  spec.author  = 'Ryo Kajiwara'
  spec.summary = 'Base64 for PicoRuby'
end
```

必須は name, license, author（無いと build が `required to set name, license(s) and author(s)` で fail: mruby `lib/mruby/gem.rb` の `setup`）。

- 純 Ruby gem は `src/` なし (`picoruby-json`: `mrbgem.rake` + `mrblib/json.rb` + `sig/` + `test/` のみ)。
- **ports 付き gem の例 `picoruby-rng`**（`PD:mrbgems/picoruby-rng/`）: `include/rng.h`（port 契約: `uint8_t rng_random_byte_impl(void);`）、`src/rng.c`（`#if PICORB_VM_MRUBY → #include "mruby/rng.c"`）、`src/mruby/rng.c`（Ruby に公開する C）、`ports/{posix,darwin,rp2040,esp32}/rng.c`（契約の実装）、`mrblib/rng.rb`・`kernel.rb`。darwin port は `SecRandomCopyBytes`（`ports/darwin/rng.c`）。
- **外置き gem の最小実例（mruby VM のみ、C 拡張 + darwin port）** `RD/examples/ios/iphone-torch/picoruby-iphone-torch/`: `mrbgem.rake`（`spec.require_name = 'torch'`、`add_dependency` なし）、`mrblib/torch.rb`、`include/torch.h`、`src/torch.c`（`#if defined(PICORB_VM_MRUBY) #include "mruby/torch.c"`）、`src/mruby/torch.c`、`ports/darwin/torch.c`、`ports/darwin/ext/`（Swift package）。

### 4.2 規約の要点
- **gem 名 → 識別子**: `-` を `_` に（`funcname = @name.tr('-', '_')`, mruby `lib/mruby/gem.rb:220-222`）。C の init/final は **`mrb_<funcname>_gem_init(mrb_state*)` / `mrb_<funcname>_gem_final`**。新 gem `picoruby-phomemo-thermal-printer` なら `mrb_picoruby_phomemo_thermal_printer_gem_init`（torch は `mrb_picoruby_iphone_torch_gem_init`, `RD/.../src/mruby/torch.c:28-39`）。**C 拡張が無ければ init 関数も要らない**（`src/` が空なら `objs` が gem_init だけになり、`mrb_<name>_gem_init` を呼ばない: `gem.rb:289-303`）。
- **mruby VM 版 C の書き方**: `#include "mruby.h"` `"mruby/presym.h"`（`MRB_SYM(...)` を使う）、`mrb_get_args(mrb, "S", &s)` 等、`mrb_define_class_id(mrb, MRB_SYM(Foo), mrb->object_class)`、`mrb_define_method_id`/`mrb_define_class_method_id(..., MRB_SYM(name), fn, MRB_ARGS_REQ(1))`、述語は `MRB_SYM_Q(available)`、setter/bang は `MRB_SYM_E`/`MRB_SYM_B`、演算子は `MRB_OPSYM(aref)`（`PD:picoruby-env/src/mruby/env.c:108-109`）。
- **VM 分岐**:
  - C: `src/<gem>.c` に共通部と `#if defined(PICORB_VM_MRUBY) #include "mruby/<gem>.c" #elif defined(PICORB_VM_MRUBYC) #include "mrubyc/<gem>.c" #endif`（base64, rng, torch 全て同形）。
  - rake: `build.picoruby?`（= `PICORB_VM_MRUBY` define, 別名 `vm_mruby?`）/ `build.femtoruby?`（`vm_mrubyc?`）（`PD:lib/picoruby/build.rb:33-41`）。例: `PD:mrbgems/picoruby-ble/mrbgem.rake:7` `spec.add_dependency 'mruby-task' if build.picoruby?`、`PD:picoruby-require/mrbgem.rake:10-18`。
  - gembox も `if vm_mruby?` / `vm_mrubyc?` で分岐（`PD:mrbgems/stdlib.gembox:8,24-43`）。**ユーザは mruby VM のみで可なので `src/mruby/` だけ書けばよい。** ただし picoruby の in-tree テスト収集は `src/mruby/` か `src/mrubyc/` のどちらかがあれば拾う（`PD:tasks/picoruby/test.rake:123-131`）。
  - **mruby VM では picoruby-* gem の mrblib は VM 起動時 (gem_init) に依存順でロードされる**（`gem.rb:289-298` の `mrb_load_proc`）。mruby/c では逆に `require` で遅延ロード（`PD:lib/picoruby/gem.rb:39-41` が `PICORB_VM_MRUBYC` かつ `picoruby-` 名の gem の `rbfiles` を空にする）。`require "<name>"` は mruby VM では no-op（`prebuilt_gems` を `$LOADED_FEATURES` に初期登録、`PD:picoruby-require/src/mruby/require.c:14-24,45-48`）。ファイル名は `Dir.glob("mrblib/**/*.rb").sort` 順。
- **`require` 名**: `spec.require_name` が無いと `gem 名から "picoruby-" を落とした形`（`PD:picoruby-require/mrbgem.rake:27-36`）。`picoruby-bin-*` は picogem 扱いにならない（`:27`）。例: `picoruby-io-console` は `'io/console'`、`picoruby-ble-dev-bridge` は `'ble_dev_bridge'`。
- **依存**: `spec.add_dependency 'picoruby-xxx'`（名前だけなら `MRUBY_ROOT/mrbgems/<name>` を core として解決、無ければ mgem-list をネット取得しに行く: `mruby lib/mruby/gem.rb` の `default_gem_params`）。mruby 標準 gem は `spec.add_dependency 'mruby-io', gemdir: "#{MRUBY_ROOT}/mrbgems/picoruby-mruby/lib/mruby/mrbgems/mruby-io"` と `gemdir:` を付ける（`PD:picoruby-mruby/mrbgem.rake:12,14`）。**外置き gem に依存する時は同じく `default` として `gemdir:` を付けるか、先に build_config で `conf.gem` しておく**。darwin-ble-test.rb のコメントに実害の例（`mruby-metaprog` を素の名前で依存して mgem-list fetch が走った, `PD:build_config/darwin-ble-test.rb:28-31`）。
- **port 選択**: `conf.ports :darwin, :posix`（`mruby lib/mruby/build.rb:345-352`）。gem が `ports/darwin/` を持てばそれを、無ければ `ports/posix/` をコンパイル。さらに picoruby の `lib/picoruby/gem.rb:3-33` が posix build で `ports/<platform_port>/**/*.c` と `ports/common/**/*.c` を libmruby にリンク（`ports/<port>/ext/` 配下は除外 = Swift package 用）。外部 HAL provider の命名規約 `hal-<short>-<conf>`（`mruby lib/mruby/gem.rb` `resolve_external_hal!`）。判定述語は `build.posix?` / `build.darwin?`（`PD:lib/picoruby/build.rb:161-171`）。
- **`AGENTS.md` (`PD:AGENTS.md`) の gem 実装規約**（ライブラリ gem に適用、アプリ・テストは対象外）: `each`/`times`/`map` 等のブロック反復を避け `while` + 明示 index、ivar を 3 回以上参照するなら local に memoize、submodule を勝手に変更しない。stackchan-picoruby も「コードとファイル配置は picoruby の mrbgems を手本にする」と明記。
- **型定義**: `sig/<name>.rbs`（steep: `rake test:gems:steep`）。DH も各 gem に `sig/` を持つ。

### 4.3 mruby 標準 gem を使う時の注意（reduced 構成）
RD README `RD/README.md:371-386`: gembox を使わない「Reduced」構成だと `defined?`, `String#ord`, `String#%`, `Array#pack` が無い。`stdlib.gembox` (vm_mruby) は `mruby-string-ext`, `mruby-array-ext`, `mruby-hash-ext`, `mruby-numeric-ext`, `mruby-kernel-ext`, `mruby-sprintf`, `mruby-pack`, `mruby-metaprog`, `mruby-error`, `mruby-math` などを入れる（`PD:mrbgems/stdlib.gembox:29-43`）ので、**macOS host で 4 gembox を使えば足りる**。

---------------------------------------------------------------------

## 5. テストの仕組み

### 5.1 picotest
- `PD:docs/testing-guide.md`（全文確認済み）:
  - `rake test:all`（compiler:picoruby, gems:steep, gems:picoruby, gems:femtoruby）、1 gem は `rake 'test:gems:picoruby[picoruby-some-gem]'` / `test:gems:femtoruby[...]`。
  - Strategy 1（`src/` あり・`ports/` なし）: gem 専用のテスト binary を build。Strategy 2（pure Ruby または `ports/` あり）: 汎用 runner が `mrblib/**/*.rb` を動的ロード、`test/mock/` があればそれも先にロードしてハード依存を mock。
  - テストファイルは `test/*_test.rb`、クラス名は `*Test`、メソッド名は `test_*`、基底は `Picotest::Test`。
  - Runner は **CRuby 上で動き**、テスト対象 VM（picoruby/femtoruby）を子プロセスで起動する。クラスは各テスト後に remove_const される。
- 実装: `PD:mrbgems/picoruby-picotest/mrblib/picotest/runner.rb`
  - `:11-29` `Runner.new(dir, filter:, tmpdir:, require_name:, load_files:, load_path:, entries:)`。`ENV["RUBY"]`（無ければ `RbConfig.ruby`）が VM のパス。
  - `:56-129` 生成する一時 script: `$LOAD_PATH = ['<load_path>']`、LoadError を握りつぶす `require`、`require 'picotest'`、`load_files` の中身を **埋め込み**、`require '<require_name>'`、テストファイルを埋め込み、各 `test_*` を `setup` → test → `teardown`、最後に `JSON.generate(my_test.result)`。
  - `:235-251`: テストファイルはまず **CRuby で `load`** してクラスを列挙する → **VM 固有の定数（`USB::...` 等）をトップレベルで参照すると CRuby で NameError**（DH `hid_mouse_test.rb` はメソッド内で `Class.new` して回避）。
- アサーション: `assert`, `assert_false`, `assert_nil`, `assert_not_nil`, `assert_equal(expected, actual)`, `assert_not_equal`, `assert_raise(*exceptions){}`, `assert_in_delta`, `skip`、`stub(obj).m {}` / `mock(obj)` / `stub_any_instance_of` / `mock_any_instance_of`（`PD:mrbgems/picoruby-picotest/mrblib/picotest/test.rb:41-208`, `README.md`）。
- 例: `PD:mrbgems/picoruby-base64/test/base64_test.rb`（`setup` で `require "base64"`）、`DH/gems/picoruby-ble-dev-bridge/test/framer_test.rb`。

### 5.2 外置き gem をテストする（実装済みの前例が 2 つ）
**upstream の `rake test:gems:picoruby` は `mrbgems/` 直下しか拾わない**（`PD:tasks/picoruby/test.rake:113-115` の `Dir.glob(["#{gems_dir}/picoruby-*", "#{gems_dir}/mruby-*"])`）。DH `docs/spec.md:131-136` も同じ指摘。

(a) **DH 方式 (`DH/rakelib/test.rake:1-121`, `DH/build_config/host-test.rb`)**: `host-test.rb` が upstream の `build_config/picoruby-test.rb` を `load` し、`MRuby.each_target { |conf| conf.gem gemdir: ".../gems/<name>" }` で gem を足す → `MRUBY_CONFIG=<host-test.rb> PICORB_DEBUG=1 rake all`（vendor/picoruby の中で）で host VM を build → CRuby が `require <vendor>/mrbgems/picoruby-picotest/mrblib/picotest.rb`、`ENV["RUBY"] = <host VM>`、gem ごとに `Picotest::Runner.new(test_dir, tmpdir:, require_name:, load_path: gem_dir).run`。`require_name` は `mrbgem.rake` から正規表現で読む（`:112-121`）。VM が今の入力に対して有効かを stamp（picoruby SHA + config digest + gem の mrbgem.rake/mrblib/src/ports/include の digest）で毎回確認（`:65-110`）。

(b) **stackchan 方式 (`test/picotest/harness.rb`)**: gem を VM に焼かず、mrblib source を VM script に **埋め込み**（`load_files`）、CRuby 側にも `load`。fake / stub を注入。VM は `build_config/picoruby-test.rb`（picotest のみ）。gem を変えても VM の再 build が要らない。C 拡張のある gem をテストするには VM に焼く必要があるので (a)。

(c) **素の CRuby テスト**: RD の `examples/ios/tilt-synth/test_mapping.rb`（`ruby test_mapping.rb`、stub を定義してから `require_relative "app"`）、DH の `tools/**/*_test.rb`（minitest）。RD の `rake regress:unit` は `examples/**/test_*.rb` と `rakelib/test_*.rb` を `RbConfig.ruby` で実行 (`RD/Rakefile:829-849`) し、CI が PR ごとに回す。CRuby と PicoRuby VM の差（例: `rescue` 内の裸 `raise`、`module_function` の裸形、regexp の `|`）は stackchan CLAUDE.md に実測メモがある。

### 5.3 注意
- **picoruby-ble を `add_dependency` した gem を host テスト VM に焼くと、host VM 側に darwin port (`PICORB_PLATFORM_DARWIN` + `swift build`) が要る**。`PD:build_config/picoruby-test.rb` は `PICORB_PLATFORM_POSIX` のみで DARWIN を定義せず、ble に posix port は無い。DH の `picoruby-ble-dev-bridge` は「BLE にも DFU にも依存しない純粋なバッファ操作」にして host で完結させた（`DH/gems/picoruby-ble-dev-bridge/mrbgem.rake:6-10`）。stackchan も「BLE の実体は薄い adapter に隔離」。**新 gem は BLE object を注入する形（プロトコル/コマンド組み立ては純 Ruby、BLE への書き込みだけ adapter）にし、`picoruby-ble` は製品 build_config 側で足す** のがこの 3 repo の流儀。
- ble の darwin port 自身のテスト（`PD:mrbgems/picoruby-ble/ports/darwin/test/`）は `build/host/bin/picoruby <test>.rb` を直接叩く形（`decoder_contract_test.rb` は radio 不要、`e2e_*` は `RUN_E2E=1` と実機の相手が必要）。

---------------------------------------------------------------------

## 6. CLI に使える既存 gem / 機能

「gembox」: `mruby-posix` = mruby-task, mruby-dir, mruby-io, mruby-proc-ext, mruby-method, mruby-error（`PD:mrbgems/mruby-posix.gembox`）。`minimum` = mruby-compiler, mruby-bin-mrbc, picoruby-bin-picoruby, picoruby-mruby。`core` = picoruby-require, -machine, -picorubyvm, -time（posix では mruby-io 経由）。`stdlib` = picoruby-dfu/rng/base16/base64/json/yaml/marshal/data/logger/terminus/karmatic_arcade/regexp_light + mruby の *-ext 群・sprintf・pack・metaprog・math など。

| 欲しいもの | 状況 | 根拠 |
|---|---|---|
| ファイル IO | あり。`File.open`、`IO.read(path)`、`File.size/expand_path/basename/dirname/join/rename/delete`、`IO#read/gets/getc/write/each_*`、`File.directory?` 等 | mruby-io (`mruby-posix` gembox)。`mruby-io/mrblib/io.rb:124` `IO.read`、`src/file.c`、`RD/examples/macos/ls/ls.rb` |
| `File.binread` 等の専用バイナリ API | 未確認（`IO.read` / `File.open(path,"rb"){|f| f.read}` で代替できるはず。実機で要確認） | mruby-io の定義リスト（`binread` は MRB_SYM に無かった） |
| Dir | あり（`entries`, `children`, `exist?`, `mkdir`, `getwd`, `chdir`, `each_child`） | mruby-dir (`mruby-posix`) |
| stdin 読み取り | あり。`$stdin`/`STDIN`/`gets`/`getc`/`IO#read`。端末ではHAL ring buffer 経由、リダイレクトでは `$stdin.gets` | `PD:picoruby-machine/mrblib/kernel.rb:24-37,57-61` |
| ARGV | あり。`picoruby script.rb a b c` で `ARGV = ["a","b","c"]` | `PD:picoruby-bin-picoruby/tools/picoruby/picoruby.c:477-497` |
| exit code | あり。`exit(n)`、未処理例外は 1 | `kernel.rb:51-53`、`picoruby.c:762-775` |
| 環境変数 | `ENV[]`, `ENV[]=`, `ENV.delete`, `ENV.each`, `ENV.keys`（`fetch` なし）。`require "env"` | `PD:picoruby-env`（`picoruby-time` が依存するので core gembox で入る） |
| sleep / time | `sleep(sec)`, `usleep`, `sleep_ms(ms)`（mruby-task、task-aware）、`Time`（picoruby-time） | `mruby-task/src/task.c:1987-1989` |
| pack / unpack | あり（mruby VM: `Array#pack`, `String#unpack/unpack1`、`mruby-pack`。stdlib gembox で入る。mruby/c は `picoruby-pack`） | `mruby-pack/src/pack.c:2137-2139`、`stdlib.gembox:42` |
| String のバイナリ操作 | core: `getbyte/setbyte/byteslice/bytes/bytesize/byteindex/bytesplice`、string-ext: `b`, `append_as_bytes`, `ljust/rjust/center`, `ord`, `hex`, `tr` 等。ビット演算: `picoruby-string-bitops` / `mruby-string-bitops`（stdlib には入っていない） | `mruby/src/string.c`、`mruby-string-ext/src/string.c` |
| base64 / base16 | あり (`Base64.encode64/decode64/urlsafe_*`、`picoruby-base16`) | `PD:picoruby-base64`（注: `decode64` の C は不正文字を ArgumentError にしようとして `base64_convert` が 0 を返すため事実上検出されない） |
| JSON | あり (`JSON.parse/generate`、`JSON::Digger`)。純 Ruby | `PD:picoruby-json` |
| zlib (inflate) | **なし**（`picoruby-shell` の `require 'zlib'` は CRuby 側の rake 評価用）。`picoruby-crc` は `CRC.crc32` のみ | grep 結果 |
| PNG デコード / 画像 | **なし**（bdffont/vram/uc8151 は表示系）。ラスタ化は CRuby 側 (`rmagick` 等) で前処理して生バイト列や 1bit ビットマップを渡す構成が現実的 | grep 結果 |
| BLE | `picoruby-ble`（darwin port: CoreBluetooth、central/observer/peripheral/broadcaster、`require "ble"`、`class X < BLE`） | `PD:picoruby-ble/ports/darwin/README.md`、`RD/examples/macos/ble-subscribe/ble-subscribe.rb` |
| テスト | `picoruby-picotest` | §5 |
| Kernel#sprintf/format | あり (`mruby-sprintf`) | stdlib gembox |

---------------------------------------------------------------------

## 7. 新 gem を picoruby 本体ツリーの外に置いてビルドに組み込めるか → **できる**

- 仕組み: mruby の `conf.gem`（`mruby lib/mruby/build/load_gems.rb:18-33`）は文字列を渡すと `{gemdir: <path>}` 扱い。`gemdir:` に絶対パスを渡せばその下の `mrbgem.rake` を load する。
- 前例（全部この環境内にある）:
  - RD `build_config/r2p2-picoruby-ios-torch-sim.rb:58`: `conf.gem File.expand_path("../examples/ios/iphone-torch/picoruby-iphone-torch", __dir__)`（C 拡張 + `ports/darwin` 込みの外置き gem、`conf.ports :darwin, :posix` 併用）。
  - RD `build_config/r2p2-picoruby-darwin-single.rb:37` `conf.gem bin_gem`（`macos:single` が生成する一時 gem）。
  - DH `build_config/host-test.rb:16-21`、`rp2040-pico2_w.rb:16-19`: `conf.gem gemdir: "#{HARNESS_ROOT}/gems/..."`。
  - stackchan `build_config/darwin-stackchan-ios-sim.rb:65-66`: `conf.gem gemdir: File.expand_path("../mrbgems/picoruby-drb-ble", __dir__)`。
- build_config 自体も repo 外から渡せる: `MRUBY_CONFIG=<絶対パス>`（RD `macos.rake:13-14` は `File.absolute_path`、stackchan `pc:vm_build` が実運用）。`MRUBY_BUILD_DIR` で出力先を picoruby ツリーの外に出せる。
- 外置き gem の挙動: `core?` が false になり全コンパイラ（cc/cxx/objc/asm）に include path 等のルールが定義される（mruby `gem.rb:137-145`）。`picoruby-` で始まる名前なら picogem として `prebuilt_gems` に載り `require "<require_name>"` が通る（`PD:picoruby-require/mrbgem.rake:27-36`）。`ports/darwin` は `conf.ports :darwin, :posix` で選ばれる。
- 注意点:
  - 外置き gem が picoruby の `picoruby-*` gem に依存する場合、素の名前で `spec.add_dependency 'picoruby-ble'` すれば core 解決される（§4.2）。
  - **`mrbgem.rake` は ASCII のみ**（DH の規約。自前の rake 評価が locale に影響される場合の保険）。
  - build_config 内で `MRUBY_ROOT` が使える（vendor/picoruby の Rakefile が定義してから load する）。他 repo の config は `load` で流用できる（DH 方式）が、RD の config は「自己完結（他を require しない）」が方針なので、stackchan 方式（コピーして足す）が無難。

---------------------------------------------------------------------

## 8. 「新 gem を作って CLI として動かすまで」の最短手順（見立て）

前提確認（5 分）: Ruby ≥ 3.4 を有効化（今のシェルは 2.6.10）、`swift` が `/usr/bin/swift`（Xcode）、`brew --prefix openssl@3` あり（確認済み）。

**案 A（推奨: stackchan 方式。RD を vendor して、自 repo の gem + build_config を外から渡す）**

1. `thermal-printer` repo に `vendor/R2P2-darwin` を clone し、`rake -C vendor/R2P2-darwin setup`（picoruby `port-darwin` を --recursive clone、1.2GB）。（未 push の fork を使うなら `PICORUBY_REPO`/`PICORUBY_REF`。）
2. gem 作成（TDD）: `mrbgems/picoruby-phomemo-thermal-printer/{mrbgem.rake,mrblib/*.rb,sig/*.rbs,test/*_test.rb}`。`spec.require_name = 'phomemo_thermal_printer'` 等。**プロトコル（ESC/POS 系バイト列、ラスタ、フロー制御）は純 Ruby、BLE への書き込みは注入する adapter に限定** し、host で picotest を回せるようにする。`add_dependency 'picoruby-ble'` は製品 build_config 側で `conf.gem core: "picoruby-ble"` するか、gem 側に置くなら host テスト VM に ble を載せない構成を別に用意（§5.3）。
3. `build_config/darwin-thermal-printer.rb`: RD の `r2p2-picoruby-darwin-ble.rb` を元に、`picoruby-bin-r2p2` / `networking` / `shell` など不要物を削り、`conf.gem core: "picoruby-ble"`、`conf.gem core: "hal-task-darwin"`、`conf.gem gemdir: File.expand_path("../mrbgems/picoruby-phomemo-thermal-printer", __dir__)` を足す。`PICORB_PLATFORM_POSIX` と `PICORB_PLATFORM_DARWIN` を両方定義し、`conf.picoruby`、gembox は `mruby-posix` / `minimum` / `core` / `stdlib`。
4. ビルド: `MRUBY_CONFIG=$PWD/build_config/darwin-thermal-printer.rb rake -C vendor/R2P2-darwin macos:build`（`macos_build_env` が openssl の flag と `MRUBY_BUILD_DIR` を面倒見る）。成果物 `vendor/R2P2-darwin/build/host/bin/picoruby`。
5. CLI 本体 `bin/<cli>` = `exec <picoruby> lib/cli.rb "$@"`（stackchan の `bin/stackchan` と同形）。`cli.rb` は `ARGV` / `ENV` / `$stdin` / `exit(n)` を使う。BLE を使うまでは直接実行で OK（`rake test` 相当と、実プリンタ無しの dry-run 出力で検証）。
6. **BLE を実際に飛ばす段階**: 最初に最小 scan スクリプトで TCC を確認（直接 exec で SIGABRT するか、`.app` + `open -W -a ... --stdout/--stderr --args` なら通るか、`-sectcreate` 埋め込みで通るか）。通る経路が決まったら、`.app` bundle 化（`Info.plist` に `NSBluetoothAlwaysUsageDescription`、`codesign --force --deep -s - -r='designated => identifier "<id>"'`、VM を再 build するたびに再実行）を rake task に。1 発印刷で足りるなら `open -W -a` 方式（stdin/exit code が使えない制約あり）、対話・連続印刷なら daemon + 薄い CLI（stackchan 方式）。
7. 完了の線引きは実機（RD/DH 共通の規律）: 実プリンタに印字されるまで「動いた」と言わない。

**案 B（picoruby ツリーを直接使う）**: ghq の `picoruby` を `port-darwin` に checkout（書き込みを伴うため今回は未実施）し、`MRUBY_CONFIG=<repo>/build_config/xxx.rb MRUBY_BUILD_DIR=<repo>/build rake` を picoruby 直下で実行。RD を経由しない分、`generate_prism_templates`（RD `Rakefile:88-102`）と openssl の `LDFLAGS/CFLAGS` を自分で面倒見る必要があり、利点は少ない。

**案 C（gem 化せず source を `load` する）**: stackchan の daemon/CLI 方式。VM に焼くのは picoruby-ble 等だけで、Ruby コードは `load` で読む。再 build 不要で開発が速いが、user の「mrbgem にする」指示とは合わない。TCC の `.app` コピーを毎回作り直す手間（VM 再 build のたび）を減らせる、という利点だけ留意。

---------------------------------------------------------------------

## 9. リスクと未確認事項

1. **TCC / BLE（最重要）**: 上記 §1.7。RD/stackchan は「直接 exec は必ず SIGABRT」、picoruby の darwin-ble-test config のコメントは「Info.plist を `-sectcreate` で埋め込めば bare CLI でも」。**未検証。** `.app` bundle が必須なら「ユーザが打つ CLI」は `bin/xxx`（sh）→ `open`/launchd 経由の構成になり、stdin/exit code/対話性に制約。再 build ごとに ad-hoc 署名が変わり TCC 許可が消える（designated requirement を identifier に固定して回避, stackchan 実測）。
2. **Ruby 2.6.10**: このシェルの既定 Ruby。mise の 4.0.x を有効にする必要。RD の `.ruby-version` (4.0.5) はこの Mac に無い。
3. **hal-task-darwin が RD の host BLE config に未収載**: stackchan の Mac config は足している。BLE + task を同時に使う CLI では必要になる可能性が高い。
4. **port-darwin が master に 6 commit 遅れ**、ローカル PR clone は master で `port-darwin` 未 checkout。RD の `rake setup` は別途 clone するので影響なし。`RD/CLAUDE.md:23-24` は「port-darwin は upstream master に対し behind 0 を保つ」方針だが、現状 fork の master と比べると 6 commit 遅れ（upstream picoruby/picoruby 本家との差は未確認）。
5. **host build に stamp が無い**: `macos:build` は `build/host` の stale 化防止 (`.r2p2-build-stamp`) を通らない。picoruby/config を変えた後に挙動が変わらない時は `build/host` を消して再 build（RD の記述から推論、未検証）。
6. **BLE の `swift build` が gem の rake 評価中に走る**（`PD:picoruby-ble/mrbgem.rake:22-25`）ので、初回ビルドは長く、Swift 6.3+ と PATH の `swift` 選択（swiftly 問題）に依存。
7. `File.binread` 相当と `IO#read` の挙動（バイナリ安全性・`"rb"` モード・巨大ファイル）は実機で未確認。
8. DH の `rake setup`/`SUBMODULE_PINS` は Pico 2 W 向けの古い compiler pin を強制するので、darwin 用の tree に流用しない（§2.2）。DH は参考実装として読むに留める。
9. R2P2-darwin の `docs/superpowers/` と `docs/plans/`（estalloc クラッシュ調査など）、DH の `docs/research/` `docs/superpowers/` は今回は精読していない（BLE 詳細・実機調査系で、gem の作り方・ビルド手順には直接関係しないと判断）。
