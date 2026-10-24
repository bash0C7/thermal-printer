# M0 spike 結果

- 日付: 2026-10-24
- 環境: macOS 27.0.1（BuildVersion 26A434）、Swift 6.4（`/usr/bin/swift`）、arm64、Ruby 4.0.5（mise）
- 状態: ビルド、TCC の 4 経路、T02 の GATT ダンプ（経路 1 と経路 4）まで実測済み。
- 区別: 「実測」はこの Mac で自分が実行して観測した事実。「推測」は実測から導いた解釈。

## 1. 使った commit

| 対象 | 値 |
|---|---|
| R2P2-darwin（`main`） | `08986d975576b3c836d54d0801ec32ebc0ee5a90` |
| picoruby（`port-darwin` の先頭。R2P2-darwin の `rake setup` が clone） | `31de548847e0a45e5f6619b0eb3edfa154fa18c2`（2026-10-11、`fix(picoruby-ble/darwin): give back a connection the decoder abandoned`） |
| `picoruby -v`（実測） | `picoruby 4.0.4 (2026-10-11T02:28:35Z 31de5488) RITE0400` |

## 2. ビルド

- 手順: `mise exec ruby@4.0.5 -- rake vendor:setup`、続けて `mise exec ruby@4.0.5 -- rake vm:build`（repo の `Rakefile`）。
- Rakefile は起動時に `PATH` の先頭へ Ruby 4.0.5 の bin と `/usr/bin` を足す。`/usr/bin/swift`（Xcode）が `~/.swiftly/bin/swift` より先に来るため、`unknown argument: '-target-arch-variant'` は出なかった（実測）。
- 所要（実測）: `vm:build` は 09:14:16 開始、09:15:52 に `picoruby` 生成で完了（約 1 分 36 秒）。`-sectcreate` 版（別の `MRUBY_BUILD_DIR`）も同程度で、09:21 台に完了。
- 詰まった点: ビルド自体には無かった。エラーも警告による停止も出ていない（実測）。
- build_config: `build_config/darwin-thermal-printer.rb`。stackchan の `darwin-stackchan-pc.rb` から、`ssl`/`crypto` の link、`shell`/`networking` gembox、`picoruby-bin-r2p2` を外した。`hal-task-darwin`、`picoruby-ble`、`picoruby-picotest`、`picoruby-bin-picoruby` を含む。外しても build は通った（実測）。
- 実測: `picoruby spike/hello.rb a b` は `hello` と `argv=["a", "b"]` を出し、`exit(7)` で終了コード 7 を返した。
- 実測: `picoruby` は `@rpath/libPicoBLEDarwin.dylib` に依存し、rpath は `vendor/R2P2-darwin/vendor/picoruby/mrbgems/picoruby-ble/ports/darwin/ext/.build/release` の絶対パス。`picoruby` 1 本を `.app` にコピーしても、vendor ツリーが残っている限り動く。
- 推測: vendor ツリーの無い Mac へ配る `.app` は、dylib の同梱と rpath の書き換えが要る。M0 の範囲では確かめていない。

## 3. TCC の 4 経路

実行元の事実（実測）: このセッションのシェルの祖先は `/Applications/cmux.app`（`com.cmuxterm.app`）。cmux の Info.plist は `NSBluetoothAlwaysUsageDescription` を持つ。Terminal.app（`com.apple.Terminal`）の Info.plist は持たないが、TCC ログは Terminal に対して `Auth Right: Allowed (User Consent)` を返した。つまり両方とも、この Mac では Bluetooth の許可が既にある。

TCC の判定対象は、`responsible_path` を持つ親アプリ（ターミナル、ランチャー）。親のいない launchd 直下では、`picoruby` バイナリ自身（パスが識別子）になる。

### 3.1 結果表

| 経路 | 起動の形 | 終了コード | SIGABRT | ダイアログ | scan 結果 | stdin | exit code |
|---|---|---|---|---|---|---|---|
| 1a | cmux 直下で直接 exec | 3（スクリプトが決めた「T02 なし」） | なし | なし（許可済み） | 29〜34 台を取得 | 使える | 使える |
| 1b | Terminal.app 直下で直接 exec（`.command` 経由） | 3 | なし | なし（許可済み） | 取得できた | 使える（推測。tty が付くため） | 使える |
| 1c | launchd 直下（責任プロセスなし）で直接 exec | 3（`LastExitStatus` 768） | なし | 出た。対象は `picoruby`（パス `vendor/R2P2-darwin/build/host/bin/picoruby`）。クリック待ち | 0 台 | 未確認 | 使える |
| 2 | `.app` 化 + `open -W -a --args` | `open` が常に 0（スクリプトは 3 で終了、実測） | なし | 出た。対象は `com.bash0c7.thermalprinterspike`。ユーザーが許可した | 許可前は 0 台。許可後の再実行は 27 台、T02 なし | `--stdin <ファイル>` で渡せる | 伝わらない |
| 3a | `-sectcreate` 埋め込み版を cmux 直下で exec | 実行できた | なし | なし（許可済み） | 29 台を取得 | 使える | 使える |
| 3b | `-sectcreate` 埋め込み版を launchd 直下で exec | 3（`LastExitStatus` 768） | なし | 出た。対象は `picoruby`（パス `build/embed/host/bin/picoruby`）。クリック待ち | 0 台 | 未確認 | 使える |
| 4 | Swift 製ランチャー `.app` + `open -W -a --args`（子の `picoruby` を `Process` で起動） | `open` が常に 0。ランチャー単体を直接 exec すると子の終了コード 7 を伝搬した（実測） | なし | 出た。対象は `com.bash0c7.thermalprinterspike.launcher`。ユーザーが許可した | 許可前は 0 台。許可後の再実行は 28 台、T02 なし | `--stdin <ファイル>` で渡せる（実測、`from-stdin-file` を読めた） | `open` 経由では伝わらない |

- 許可後の再実行（実測）: 経路 2 は stdout に `scan done devices=27 T02_hits=0`、経路 4 は `scan done devices=28 T02_hits=0`。stderr はどちらも空。`open` の終了コードは 0。全文は `build/logs/route2b-stdout.log` と `build/logs/route4b-stdout.log`。
- 経路 4 の再実行で、名前付きの広告が 1 台観測された（`F3:C9:FF:7D:71:A7 rssi=-95 name="TNT_BW  " keys=[:complete_local_name]`）。ローカル名が `complete_local_name` として届き、`name_include?` と同じ参照先で前方一致を判定できる（実測）。
- 0 台は「未許可で scan が空振りした」状態。SIGABRT もエラー出力も出さず、`scan` は timeout まで戻り、結果が空になる（実測）。結果ファイルの「devices=0」だけでは、周囲に何も無いのか未許可なのかを区別できない。
- 経路 3 の埋め込み plist は効いていない（実測）。TCC のプロンプト対象が `identifier=picoruby`（パス）のままで、plist の `CFBundleIdentifier`（`com.bash0c7.thermalprinterspike.embed`）にならなかった。`otool -s __TEXT __info_plist` で plist が埋まっていることは確認済み。コード署名は `Info.plist=not bound`。
- 経路 4 の責任プロセス（実測）: TCC ログの `Resp` が `ThermalPrinterSpikeLauncher.app/Contents/MacOS/launcher`（`responsible_path` 付き）。子の `picoruby` ではなく、ランチャーに対するプロンプトになる。設計書 §5.2 の見込みどおり。
- `launchctl submit` のジョブは終了後に自動で再起動するため、実測後に `launchctl remove` した（`job1`、`job2`）。残っていない。

### 3.2 採用推奨

- **CLI（ターミナルからの直接実行）: 経路 1**。実測で、責任プロセスの許可があれば SIGABRT せず、stdin と終了コードが使える。経路 3 は plist が効かないので採らない。
- **Mac アプリからの印刷: 経路 4**。TCC の責任プロセスがランチャーになることを実測で確かめ、許可後に子の `picoruby` の scan が 28 台を返すことも実測で確かめた。
- 経路 2 も許可後に 27 台を返す（実測）。ただし終了コードが `open` で消えるため、結果 JSON に頼る前提になる。経路 4 が通ったので、採らない。
- 経路 4 の子プロセスから T02 への接続、CCCD 購読、notify 受信も通った（実測、§4.3）。経路 1 と同じ 3 件（`01 01`、`02 b6 00`、`1a 3b 04 40 00 00 00`）が届き、再ペアリングは要らなかった。

## 4. GATT ダンプ

- 実行（実測）: cmux 直下で `vendor/R2P2-darwin/build/host/bin/picoruby spike/gatt_dump_probe.rb <log> 20000` を直接 exec。T02 が電源投入前は 8 秒の scan で未検出（`RESULT T02 not found`、終了コード 3）。電源投入後は 1 回目の scan で見つかった。
- 書き込みは `ff03` の CCCD（`01 00`）だけ。`ff02` には何も書かず、`1f 11` 系も送っていない。
- 同じ T02 に 2 回接続した。1 回目は macOS 未ペアリング、2 回目はペアリング済み。

### 4.1 1 回目（未ペアリング）の生出力

```
[+0ms] probe start prefix=T02 scan_timeout_ms=20000
[+125ms] target name="T02" addr=E5:17:CD:23:D9:3B rssi=-49
[+125ms] adv reports:
Event Type: connectable_advertising_ind
Address Type: random
Address: E5:17:CD:23:D9:3B
RSSI: -49
Reports:
  complete_local_name: "T02"(len 3)
  manufacturer_specific_data: "\x00\x00\xE8\v\xB3\x0F\x90l"(len 8)
Stopped by state: TC_IDLE
[+1125ms] connected handle=64
[+1126ms] services=1
[+1127ms] service 0000ff00-0000-1000-8000-00805f9b34fb handles=1..8 chars=3
[+1127ms]   char 0000ff01-0000-1000-8000-00805f9b34fb vh=3 props=0x2(read) value=
[+1127ms]   char 0000ff02-0000-1000-8000-00805f9b34fb vh=5 props=0xc(write_no_rsp,write) value=
[+1128ms]   char 0000ff03-0000-1000-8000-00805f9b34fb vh=7 props=0x10(notify) value=
[+1128ms]     desc 00002902-0000-1000-8000-00805f9b34fb handle=8 value=00 00
[+1128ms] RESULT ff00 service: present
[+1129ms] RESULT ff02: present props=0xc(write_no_rsp,write)
[+1129ms] RESULT ff03: present props=0x10(notify)
[+1129ms] drain before subscribe (300ms)
[+1429ms] write CCCD handle=8 value=01 00 (only write in this probe)
[+1430ms] CCCD write rc=0
[+6433ms] RESULT notifications after subscribe=0 disconnected=false
```

- 購読後 5 秒間、notify は 0 件だった。終了コード 0。
- 同じ時刻の `bluetoothd` のログ（実測、`log show`）。
  - 09:56:33.560: `Received "Just Works" pairing request`、`Displaying pairing request alert`（macOS のペアリング確認が表示された）。
  - 09:56:33.800: `GATT is Asking to pair due to LE_ATT_ERROR_INSUFFICIENT_AUTHENTICATION`（CCCD 書き込みの直後）。
  - 09:56:38.786: `Accepting LE pairing`。09:56:39.320: `Pairing succeeded`。ペアリングはプローブの 5 秒の待ち時間が終わった後に完了した。
  - 受理した主体（ユーザーのクリックか自動か）はログから特定できていない。
  - `Encryption is insufficient` という文言は、このセッションのログにも標準出力にも出ていない（`ATT_ERROR_INSUFFICIENT_AUTHENTICATION` が同じ事象）。
  - 09:56:33.021: `GattGateway device ... is ready with mtu 527`（ATT MTU は 527 で合意）。

### 4.2 2 回目（ペアリング済み）の生出力

```
[+0ms] probe start prefix=T02 scan_timeout_ms=20000
[+105ms] target name="T02" addr=E5:17:CD:23:D9:3B rssi=-50
[+105ms] adv reports:
Event Type: connectable_advertising_ind
Address Type: random
Address: E5:17:CD:23:D9:3B
RSSI: -50
Reports:
  complete_local_name: "T02"(len 3)
  manufacturer_specific_data: "\x00\x00\xE8\v\xB3\x0F\x90l"(len 8)
Stopped by state: TC_IDLE
[+781ms] connected handle=64
[+782ms] services=1
[+783ms] service 0000ff00-0000-1000-8000-00805f9b34fb handles=1..8 chars=3
[+784ms]   char 0000ff01-0000-1000-8000-00805f9b34fb vh=3 props=0x2(read) value=
[+784ms]   char 0000ff02-0000-1000-8000-00805f9b34fb vh=5 props=0xc(write_no_rsp,write) value=
[+785ms]   char 0000ff03-0000-1000-8000-00805f9b34fb vh=7 props=0x10(notify) value=
[+785ms]     desc 00002902-0000-1000-8000-00805f9b34fb handle=8 value=00 00
[+785ms] RESULT ff00 service: present
[+786ms] RESULT ff02: present props=0xc(write_no_rsp,write)
[+786ms] RESULT ff03: present props=0x10(notify)
[+786ms] drain before subscribe (300ms)
[+1105ms] write CCCD handle=8 value=01 00 (only write in this probe)
[+1105ms] CCCD write rc=0
[+1165ms] notify#1 handle=7 value=01 01
[+1185ms] notify#2 handle=7 value=02 b6 00
[+1205ms] notify#3 handle=7 value=1a 3b 04 40 00 00 00
[+6125ms] RESULT notifications after subscribe=3 disconnected=false
```

- 購読の約 60 ms 後から、3 件の notify が 20 ms 間隔で届いた。`ff02` には何も書いていない。終了コード 0。
- `01 01`（受領）は write 無しでも、購読の直後に 1 回来る（実測）。設計書 §6.5 の「write のたびに `01 01`」は、購読時にも来る点を足す必要がある。
- `1a 3b 04 40 00 00 00` は設計書 §6.7 の表に無い通知。意味は不明（推測しない）。M1 の decoder は未知の `1a xx` を捨てずに記録する。
- `ff01` は read で、値は 1 回目も 2 回目も空文字列（実測）。notify ではない。
- 広告（実測）: ローカル名 `T02`、`manufacturer_specific_data` は `00 00 e8 0b b3 0f 90 6c`（末尾 6 byte は `bluetoothd` のログの `E8:0B:B3:0F:90:6C` と一致し、公開アドレスの並びと推測する）。広告にサービス UUID は載らない（`af30` も `ff00` も無い）。
- 生ログ全文: `build/logs/gatt-dump-run1.log`、`build/logs/gatt-dump-run2.log`。

### 4.3 経路 4（ランチャー `.app` の子プロセス）での実行

- 実測: `open -W -a ~/Applications/ThermalPrinterSpikeLauncher.app --stdout … --stderr … --args …/spike/gatt_dump_probe.rb <log> 20000`。`open` の終了コードは 0、stderr は空。
- 出力は §4.2 と同じ構造で、接続 +707ms、CCCD 書き込み +1031ms、`notify#1` `01 01`（+1091ms）、`notify#2` `02 b6 00`、`notify#3` `1a 3b 04 40 00 00 00`、`RESULT notifications after subscribe=3 disconnected=false`。service と characteristic の UUID、props、CCCD の値も §4.2 と一致。
- 全文: `build/logs/route4-gatt-stdout.log`。

## 5. 設計書 §8.1 の答え

| # | 答え |
|---|---|
| 1 | 実測。広告にサービス UUID は載らない（`af30` も `ff00` も無い。載るのはローカル名 `T02` と 8 byte の manufacturer data）。`ff01` は read（props `0x02`）で、notify ではない。値は空。サービスは `ff00` の 1 つで、`ff01`（read）、`ff02`（write と write without response、props `0x0c`）、`ff03`（notify、CCCD `2902` あり、初期値 `00 00`）の 3 characteristic。 |
| 2 | 実測の一部。ATT MTU は 527 で合意された（`bluetoothd` のログ）。購読直後の notify に `02 b6 00` が来た（`0x00b6` = 182、設計書の推測どおり）。182 が 1 回の write の上限として正しいか、128 → 160 → 182 byte の印字の欠けは、印字を伴うので M1 で確かめる。 |
| 13 | 実測。**notify にペアリングが要る。** 未ペアリングでは CCCD 書き込みが `LE_ATT_ERROR_INSUFFICIENT_AUTHENTICATION` になり、notify は 0 件。macOS が "Just Works" のペアリング確認を表示し、受理後にペアリングが成立した。ペアリング後は同じ手順で購読が通り、直後に 3 件届いた。システム設定での手動ペアリングは要らなかった（プローブの購読が自動ペアリングの引き金になった）。 |
| 15 | 実測。`ff00` / `ff02` / `ff03` が全て揃った。この T02 は設計書 §6.1 の判定で本機と確定する。別機種（`ffe6` 系など）との区別のコードは、手元に別機種が無いので判定コードのテストだけで済ませる。 |

## 6. 設計書の想定との食い違い（実測）

1. **「直接 exec は SIGABRT する」（§4.3、R2P2-darwin の README）は再現しなかった。** cmux 直下、Terminal.app 直下、launchd 直下のいずれでも SIGABRT しなかった。未許可の経路は、クラッシュでなく 0 台の scan とプロンプトになった。許可が既にある責任プロセスの下では、直接 exec が通る。
2. **`-sectcreate` で Info.plist を埋め込んでも、TCC の識別は bundle id にならない**（§4.3 の第 3 の説）。プロンプト対象は `picoruby` のパスのまま。
3. **責任プロセスの許可が子に及ぶ。** ターミナル（cmux、Terminal）とランチャー `.app` のどちらも、子の `picoruby` ではなく親が TCC の対象になる。経路 4 の根拠。
4. **`open -W` は子の終了コードを伝えない**（スクリプトの 3、ランチャーの 7 のどちらも `open` は 0）。設計書 §5.2 の「結果 JSON ファイルにも書く」は必須になる。stdout と stderr は `--stdout` と `--stderr`、stdin は `--stdin <ファイル>` で渡せる（対話的な stdin は不可）。
5. **未許可の scan は黙って空になる。** CLI は「0 台」を `not_found` と同一視せず、権限未許可の可能性を結果に書くとよい（推測。M1 の設計判断）。
6. **`picoruby` は dylib に依存する**（§2）。設計書に記載が無い。
7. **darwin の scan で T02 のローカル名 `T02` が `complete_local_name` として届いた**（2 回とも 1 回目の scan で検出）。名前の前方一致で接続できる。周囲の他の広告は大半が `manufacturer_specific_data` のみで、名前付きは 1 台（`TNT_BW`）だった。
8. **notify にはペアリングが要り、初回の購読は失敗する**（設計書 §6.2 の「macOS では notify に必要」を実測で確認）。初回は CCCD 書き込みの戻り値が 0 のまま、notify が 0 件で終わる。M1 の CLI は、初回にペアリング確認の表示とその受理を待つ手順（または購読のやり直し）を持つ必要がある。`status_unavailable` に落とす前に、再購読を 1 回試すのが妥当（推測。M1 の設計判断）。
9. **購読だけで `01 01`、`02 b6 00`、`1a 3b 04 40 00 00 00` の 3 件が届く**。`ff02` への write が無くても `01 01` が来る。`1a 3b …` は設計書に無い通知で、意味は不明。
10. **ATT MTU は 527 で合意される。** 設計書の「MTU 23 のままなら 20 byte」の心配は、この Mac と T02 の組み合わせでは当たらない。ただし、write 上限は MTU でなく `02 b6 00`（182）が決めると推測する。

## 7. ユーザーにしか頼めない操作

1. M0 の範囲では、ユーザーにしか頼めない操作は残っていない。
2. T02 を macOS から外したいとき（ペアリングのやり直しを試すとき）は、システム設定の「Bluetooth」から T02 を削除する。
3. 許可済みの `ThermalPrinterSpike` と `ThermalPrinterSpikeLauncher` を撤回したいときは、システム設定の「プライバシーとセキュリティ」→「Bluetooth」から外す。
4. launchd 直下の `picoruby`（`build/host/bin/picoruby` と `build/embed/host/bin/picoruby`）に対する未回答のダイアログは、経路 1c と 3b の確認用で、許可は不要。

## 8. 作ったもの

- `Rakefile`（`vendor:setup`、`vm:build`、`vm:build_embed`、`spike:app`、`spike:launcher`）
- `build_config/darwin-thermal-printer.rb`、`build_config/darwin-thermal-printer-embed.rb`
- `spike/scan.rb`、`spike/gatt_dump_probe.rb`、`spike/hello.rb`、`spike/stdin_probe.rb`、`spike/terminal-route1.command`
- `spike/ThermalPrinterSpike-Info.plist`、`spike/Info-embed.plist`、`spike/launcher/`（`main.swift`、`Info.plist`）
- `~/Applications/ThermalPrinterSpike.app`、`~/Applications/ThermalPrinterSpikeLauncher.app`
- 生ログ: `build/logs/`（gitignore 済み）
