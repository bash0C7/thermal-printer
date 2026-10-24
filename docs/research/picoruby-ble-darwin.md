> 2026-10-24 の調査報告の写し。本文中の `/private/tmp/...scratchpad/...` のパスは調査時の一時領域で、もう存在しない可能性がある。

# picoruby-ble darwin port 調査報告（Phomemo T02 を BLE central で制御する前提）

調査日: 2026-10-24 / 調査者: Claude（読むだけ。コードの変更・checkout はしていない）

## 0. 調査対象と状態

### picoruby（`~/ghq/github.com/bash0C7/picoruby`）

- チェックアウト中は **`master`（65b7ae62）で、`port-darwin` ではない**。`port-darwin` はローカルブランチとして存在せず、`origin/port-darwin` だけがある。
- `git fetch origin` は exit 0、更新なし。`git ls-remote` で `refs/heads/port-darwin = 31de5488`（2026-10-11 "fix(picoruby-ble/darwin): give back a connection the decoder abandoned"）、`origin/port-darwin` と一致。
- `origin/port-darwin` は master より 90 commits 先行、6 commits 遅れ（merge-base 77927f45）。
- 未追跡: `.agents/skills/pico-debug/SKILL.md` だけ（BLE と無関係）。
- 以降の行番号はすべて **`origin/port-darwin`（31de5488）** のもの。読むために `git archive origin/port-darwin mrbgems/picoruby-ble` を
  `<scratchpad>/pd/mrbgems/picoruby-ble/`
  に展開した（リポジトリへは書き込んでいない）。本文中の `picoruby-ble/...` はこの gem の相対パス。
- 他ブランチ・worktree:
  - `origin/picoruby-ble-esp32-port`、`origin/claude/ble-peripheral-disconnect`、ローカルの `codex/pr427-*` は、どれも **`ports/darwin` を変更していない**（変更は `src/`・`include/`・`mrblib/ble.rb`・esp32 の共通部分のみ）。
  - worktree `~/.codex/worktrees/pr427-fixes/picoruby`（`codex/pr427-common-proposals`）は未コミット変更なし。共通コードを大きく書き換えている（`BLE_push_event`/`BLE_heartbeat` の戻り値を `int` に、`BLE_peripheral_notify` も `int` に、`mrblib/ble.rb` の `start` を 100ms ポーリングにするなど。差分 791+/135-）。port-darwin にはまだ入っていないが、**共通 API が動いている最中**だという点は依存側のリスク。
  - worktree `~/.codex/worktrees/pr427-experiment/picoruby`（detached 7529064b）に未コミット変更あり: `ports/esp32/{ble.c,ble_central.c,nimble_owner.c}`、`src/mruby/ble.c`、`src/mrubyc/ble.c`、未追跡 `review-evidence/`。darwin ポートには触れていない。

### R2P2-darwin（`~/ghq/github.com/bash0C7/R2P2-darwin`）

- `main`（08986d9）、clean、origin と一致。vendor は `rake setup` で `bash0C7/picoruby` の `port-darwin` を clone する設計（`README_jp.md:138`, `:393-404`）。ローカルに `vendor/` は無い。

### 追加で参照した実運用コード

- `~/ghq/github.com/bash0C7/stackchan-picoruby`（`main` 9fac444、clean）。**picoruby-ble に依存する mrbgem で、Mac から BLE central として write without response と notify を実運用している**（`mrbgems/picoruby-stackchan-controller`）。ユーザーが作ろうとしているものと構成が同じなので、根拠として多用する。

---

## 1. 結論

**「一部足りない」。ただし「スキャン → 接続 → 発見 → write without response の分割送信 → notify 受信」の一連は今のままで動き、実運用例もある。**

- 動くことの根拠
  - Ruby から `write_value_of_characteristic_without_response(conn, value_handle, data)` と、CCCD への `write_characteristic_descriptor_using_descriptor_handle(conn, cccd, "\x01\x00")` が使える（`src/mruby/ble_central.c:55-83, 148-149`）。darwin 側は CoreBluetooth の `writeValue(..., type: .withoutResponse)` と `setNotifyValue(true)` に繋がっている（`PicoBLECentral.swift:209-229`）。
  - notify は `0xA7` パケットとして Ruby に届く（`PicoBLECentral.swift:337-339`, `PicoBLEPackets.swift:91-95`）。共通 decoder は無視する（TODO）ので、サブクラスで `packet_callback` をオーバーライドして拾う。
  - stackchan-picoruby の Mac daemon が、180 byte チャンクを 20ms 間隔で write without response し、notify で ACK を受ける形で実運用している（`stackchan-picoruby/mrbgems/picoruby-stackchan-controller/mrblib/stackchan-controller/central.rb:143-151`, `picoruby-drb-ble/mrblib/drb-ble.rb:2,116,130`）。
- 足りないもの（大量 write の信頼性と運用に効くもの）
  1. **フロー制御が無い**: `canSendWriteWithoutResponse` も `peripheralIsReady(toSendWriteWithoutResponse:)` も使っておらず、Ruby への通知も無い。SDK ヘッダには「`canSendWriteWithoutResponse` が false のときの write without response は best-effort で、届く保証はない」とある。だから**時間ベースのペーシング（sleep）で代用するしかない**。
  2. **MTU / 1 回の最大 write 長が分からない**: `maximumWriteValueLength(for:)` が未公開。チャンク長は決め打ちになる。
  3. **write の戻り値が常に 0**: 非同期で投げっぱなしで、ハンドル違い・未接続でも黙って捨てられる（`ports/darwin/ble.c:117-122`, `PicoBLECentral.swift:211`）。
  4. **write with response が無い**（API 自体が無いのは全ポート共通）。
  5. **切断 API が無い**（全ポート共通）。プロセスの終了に任せることになる。
  6. **切断イベントの形が他ポートと違う**: darwin は `[0x3E,0x01,0x05]` を送るが、共通 decoder はこれを切断と解釈しない（§3.6）。
  7. CCCD を書いた後の完了イベント（0xA0）が来ない。少し待つ（settle）必要がある。

Phomemo 程度のデータ量（数百 B〜数十 KB）なら、**チャンクを小さめに決め打ちし、`sleep_ms` で間隔を空ける方式で現実的には足りる見込み**。参考までに、scratchpad 内の第三者による Swift 実装も同じく `maximumWriteValueLength` で分割し、20ms スリープで間隔を空けている（`scratchpad/research/src/Phomemo-T02-for-Apple/iOSApp/BluetoothManager.swift:304-317`。第三者コードなので未検証）。ただし picoruby-ble からは最大長が取れないので、チャンク長は実機で決める必要がある。

---

## 2. picoruby-ble の Ruby API 全体

### 2.1 クラス構成

| 定義 | 場所 | 役割 |
|---|---|---|
| `class BLE` | `mrblib/ble.rb:7-167` | 基底。`BLE.new(role, profile_data=nil)`。サブクラスを作ってコールバックをオーバーライドする |
| central 系メソッド | `mrblib/ble_central.rb:1-351`（`class BLE` を再オープン） | scan / connect / 発見の状態機械 / `services` |
| C バインディング | `src/mruby/ble.c`（共通）、`src/mruby/ble_central.c`、`src/mruby/ble_peripheral.c`、`src/mruby/ble_broadcaster.c` | `BLE` のインスタンスメソッドとして定義 |
| `BLE::AdvertisingReport` | `mrblib/ble_advertising_report.rb` | ADV パケットの decode。`name_include?`, `reports`, `address`, `rssi` |
| `BLE::AdvertisingData` | `mrblib/ble_advertising_data.rb` | ADV データの組み立て（peripheral/broadcaster 用） |
| `BLE::GattDatabase` | `mrblib/ble_gatt_database.rb` | GATT DB の組み立て（peripheral 用） |
| `BLE::Utils` | `mrblib/ble_utils.rb` | UUID 変換、LE 整数の変換 |

`Central` という独立したクラスは無い。role は `:central` / `:peripheral` / `:observer` / `:broadcaster` の 4 つ（`src/mruby/ble.c:243-258`）。

- **central**: サポートあり。`init_central` が走るのは `@role == :central` のときだけ（`mrblib/ble.rb:95`）。
- **observer**: C 側は受け付けるが、`scan` 冒頭の `restrict_central` が `@role == :central` 以外で raise する（`ble_central.rb:50-57`）。実質使えない。darwin のテストも「observer は restrict_central の穴があるので central をスキャン専用で使う」と書いている（`ports/darwin/test/e2e_broadcaster_scan_test.rb:4-6`）。
- **peripheral / broadcaster**: サポートあり（今回は対象外）。

### 2.2 イベントの受け取り方

**`Task::Queue` を使ったイベントループで、ポーリングはしない**。

1. ポート（darwin では Swift）が BTstack 形式のバイト列を作り、FIFO に積む。
2. VM スレッドのスケジューラ hook（`ble_scheduler_pump`, `src/mruby/ble.c:122-158`）が FIFO を drain し、`BLE_push_event`（`:57-68`）で `@event_queue`（`Task::Queue`, `ble.rb:84`）に String として push する。未処理イベントの上限は `BLE_MAX_PENDING_EVENTS = 16`（`:55`）。上限に達すると drain を止めるが、残りは FIFO に残るので捨てられない（`:129-132`）。
3. `BLE#start(timeout_ms=nil, stop_state=:no_stop)`（`ble.rb:127-160`）が次を行う。
   - `hci_power_control(ON)` を呼ぶ。
   - `@event_queue.pop(timeout_ms:)` でブロックする。
   - String が来たら `packet_callback(event)` を呼ぶ。`:heartbeat` シンボルが来たら `heartbeat_callback` を呼ぶ（約 1 秒ごと）。
   - `@state == stop_state` になるか timeout で抜け、`ensure` で `hci_power_control(OFF)` を呼ぶ。
4. central では `scan(...)` が `start(timeout_ms, stop_state)` を包んでいる（`ble_central.rb:56-63`）。

コールバック（オーバーライドするもの）:
- `advertising_report_callback(report)`（`ble_central.rb:89-92`）
- `packet_callback(event_packet)`（`ble_central.rb:94-330`）。central の状態機械そのものなので、オーバーライドするときは `super` を呼ぶ。
- `heartbeat_callback`（`ble.rb:117-119`）

`start` の外（`scan` が戻った後）でイベントを拾うには、自前で `@event_queue.pop(timeout_ms: 0)` と `_event_popped` を呼ぶ。stackchan はこれを `pop_and_dispatch` として使っている（`stackchan-controller/radio.rb:15-21`）。e2e テストも同じ（`ports/darwin/test/e2e_central_test.rb:66-72`）。

### 2.3 central の操作ごとの API

| 操作 | Ruby API | 定義 | 備考 |
|---|---|---|---|
| スキャン | `scan(scan_type: :passive, scan_interval: 0x60, scan_window: 0x30, timeout_ms: nil, stop_state: :TC_IDLE, debug: false)` | `ble_central.rb:56-63` | darwin では interval/window/type は無視される（`ports/darwin/ble_central.c:9-14`） |
| 広告の受信 | `advertising_report_callback(report)` | `ble_central.rb:107-109` | `@state == :TC_W4_SCAN_RESULT` のときだけ呼ばれる |
| 接続 | `connect(report)` | `ble_central.rb:72-87` | **`advertising_report_callback` の中からしか呼べない**（それ以外は raise）。内部で `stop_scan` → `gap_connect(addr, type)` |
| 接続完了 → 発見 | 自動 | `ble_central.rb:110-129` | `HCI_EVENT_LE_META`（subevent 0x01）で `@conn_handle` を設定し、`discover_primary_services` |
| サービス・characteristic・descriptor の発見と全値の読み出し | 自動（状態機械） | `ble_central.rb:134-325` | services → 各 service の chars → 全 char の値 read → descriptor 発見 → 全 descriptor の値 read → `:TC_IDLE` |
| 発見結果 | `services` | `ble_central.rb:48` | `[{start_handle:, end_handle:, uuid128:, uuid32:, characteristics: [{start_handle:, value_handle:, end_handle:, properties:, uuid128:, uuid32:, value:, descriptors: [{handle:, uuid128:, uuid32:, value:}]}]}]` |
| 個別 read | `read_value_of_characteristic_using_value_handle(conn, vh)` | `src/mruby/ble_central.c:28-39` | 結果は 0xA5/0xA0。発見後は共通 decoder が拾わないので自前処理が要る |
| **write without response** | `write_value_of_characteristic_without_response(conn, vh, data)` | `src/mruby/ble_central.c:55-68` | `data` は String。長さは `(uint16_t)` にキャストされる（`:65`） |
| **write with response** | **無し** | — | 全ポートで無い |
| descriptor の write（CCCD による notify 購読） | `write_characteristic_descriptor_using_descriptor_handle(conn, dh, "\x01\x00")` | `src/mruby/ble_central.c:70-83` | darwin では CCCD への書き込みが `setNotifyValue` に変換される |
| notify 受信 | `packet_callback` で `event_packet.getbyte(0) == GATT_EVENT_NOTIFICATION`（0xA7）を自前で decode | 共通 decoder は `ble_central.rb:326-328` で TODO のまま | `gatt_event_int16(pkt, 0)` = value handle、`gatt_event_value(pkt)` = 値（`ble_central.rb:335-349`） |
| 切断 | **API 無し** | — | 全ポートで無い（stackchan の README とテストのコメントで確認済み: `e2e_central_test.rb:139-142`） |
| 切断の検知 | `HCI_EVENT_DISCONNECTION_COMPLETE`（0x05） | `ble_central.rb:130-133` | **darwin はこの形で送らない**（§3.6） |
| `conn_handle` | attr 無し。`@conn_handle` を直接読む | `ble_central.rb:41` | stackchan も e2e も自前で reader を足している |

---

## 3. darwin バックエンドの実装

### 3.1 ファイル構成（`picoruby-ble/ports/darwin/`）

| ファイル | 行数 | 内容 |
|---|---|---|
| `ble.c` | 129 | `include/ble.h` のポート側 ABI を実装し、Swift に委譲する。GCD による heartbeat タイマー |
| `ble_central.c` | 32 | `include/ble_central.h`（scan/connect）を Swift に委譲 |
| `ble_peripheral.c` | 46 | peripheral 用 |
| `ble_common.h` | 20 | `pble_take_heartbeat` の宣言 |
| `ext/Package.swift` | 40 | SwiftPM。product `PicoBLEDarwin`（dynamic）。macOS 11 / iOS 13 / watchOS 6 |
| `ext/Sources/PicoBLEDarwin/PicoBLECentral.swift` | 509 | **CBCentralManager バックエンド本体** |
| `ext/Sources/PicoBLEDarwin/PicoBLEExports.swift` | 114 | C から呼べる `@c` export（SE-0495） |
| `ext/Sources/PicoBLEDarwin/PicoBLEPackets.swift` | 109 | BTstack 形式のパケットを組み立てる純関数 |
| `ext/Sources/PicoBLEDarwin/PicoBLEFifo.swift` | 51 | NSLock で守る FIFO |
| `ext/Sources/PicoBLELifetime/PeripheralLifetime.swift` | 56 | 接続の保持・返却の判断（CoreBluetooth に依存しない） |
| `ext/Sources/PicoBLEDarwin/PicoBLEPeripheral.swift` | 407 | CBPeripheralManager（今回は対象外） |
| `README.md` | 234 | ポートの契約 |
| `test/*` | — | §5 |

ビルド: `picoruby-ble/mrbgem.rake:12-41` が担う。`build.darwin?`（`PICORB_PLATFORM_DARWIN` が定義されているか）のとき、rake の読み込み時に `swift build -c release` で dylib と `PicoBLEDarwin-Swift.h` を作り、`-lPicoBLEDarwin` と rpath を足し、`ports/darwin/*.c` をコンパイルする。dylib は `-undefined dynamic_lookup` でリンクされる（`Package.swift:36`）。

### 3.2 スレッドと run loop と mruby VM の橋渡し

- CoreBluetooth は専用のシリアル DispatchQueue `pble.cb` で動く（`PicoBLECentral.swift:58, 96`。`CBCentralManager(delegate: self, queue: cbQueue)`）。**main run loop も NSApplication も要らない**ので、CLI の picoruby バイナリのままで動く。
- delegate は (a) ハンドル表の更新、(b) BTstack 形式のバイト列の組み立て、(c) `pbleSharedFifo.push` の 3 つしかしない。mruby に触らない（`ports/darwin/README.md:56-90`）。
- VM スレッドでは、`mrb_task` のスケジューラループの先頭で呼ばれる hook（`picorb_scheduler_service_add`, `src/mruby/ble.c:305-307`）が `pble_drain_one` を呼び（`PicoBLEExports.swift:87-90`）、`BLE_push_event` で `Task::Queue` に入れる。hook はスケジューラの idle 中も tick ごとに回る（mruby-task `task.c:613-652`）。
  - root コンテキストの `sleep_ms` はタスクを待ちに移してスケジューラに戻るので、ポンプも回る（`task.c:780-829`）。C 関数の境界の内側ではブロッキング sleep にフォールバックし、その間ポンプは回らない（`task.c:780-788`）。ただし FIFO は無制限なので取りこぼしは無く、後でまとめて届く。
- VM からのコマンド（scan/connect/discover/read/write）は `cbQueue.async` で `pble.cb` に投げる。`connect` だけは戻り値が要るので `cbQueue.sync`（`PicoBLECentral.swift:142-156`）。
- heartbeat: GCD タイマーはフラグを立てるだけで（`ports/darwin/ble.c:35-54`）、ポンプが VM スレッドで `BLE_heartbeat()` に変換する（`src/mruby/ble.c:133-136`）。
- この不変条件はコード上で強制されていない（規約だけ）。`ports/darwin/README.md:86-90` に明記されている。
- **関連する重大な修正**: `hal-task-darwin`（e2783d02, 2026-10-03）。mruby-task の POSIX HAL が使う `setitimer` の SIGALRM が CoreBluetooth や dispatch のスレッドに配送されると、`mrb_tick` が VM スレッドと並行に走って待ち行列が循環し、`mrb_task_queue_push` が無限ループする。`hal-task-darwin` は SIGALRM を VM スレッドへ `pthread_kill` で回送する HAL。**ビルド設定で `conf.gem core: "hal-task-darwin"` を明示しないと入らない**（`origin/port-darwin:mrbgems/hal-task-darwin/mrbgem.rake`）。stackchan の Mac 用設定には入っている（`stackchan-picoruby/build_config/darwin-stackchan-pc.rb:29`、`stackchan-picoruby/CLAUDE.md:111`）が、**R2P2-darwin の `build_config/r2p2-picoruby-darwin-ble.rb` と picoruby の `build_config/darwin-ble-test.rb` には入っていない**。

### 3.3 central の各操作の実装状況（関数ごと）

凡例: ✅ 実装済み / △ 部分実装・制約あり / ❌ 未実装 / — 無関係

| 層 | 関数 | 場所 | 状態 | 中身・制約 |
|---|---|---|---|---|
| C | `BLE_init` | `ports/darwin/ble.c:56-69` | ✅ | central/observer は `pble_central_init`、heartbeat タイマーを起動 |
| C | `BLE_hci_power_control` | `ble.c:71-80` | △ | ON → `pble_power_on`、OFF → `pble_power_off`。**実際に無線を切ることはしない**（README:94-96） |
| C | `BLE_gap_local_bd_addr` | `ble.c:82-87` | △ | 常に 0 埋め（CoreBluetooth は自機の MAC を見せない） |
| C | `BLE_discover_primary_services` | `ble.c:89-94` | ✅ | 戻り値は常に 0 |
| C | `BLE_discover_characteristics_for_service` | `ble.c:96-101` | ✅ | handle を `(uint8_t)` にキャスト |
| C | `BLE_read_value_of_characteristic_using_value_handle` | `ble.c:103-108` | ✅ | `(uint8_t)` キャスト、戻り値は常に 0 |
| C | `BLE_discover_characteristic_descriptors` | `ble.c:110-115` | ✅ | 同上 |
| C | `BLE_write_value_of_characteristic_without_response` | `ble.c:117-122` | △ | `pble_write_value` に委譲。**戻り値は常に 0** |
| C | `BLE_write_characteristic_descriptor_using_descriptor_handle` | `ble.c:124-129` | △ | 戻り値は常に 0 |
| C | `BLE_central_set_scan_params` | `ports/darwin/ble_central.c:9-14` | ❌（no-op） | CoreBluetooth に該当する設定が無い |
| C | `BLE_central_start_scan` / `stop_scan` | `ble_central.c:16-26` | ✅ | |
| C | `BLE_central_gap_connect` | `ble_central.c:28-32` | ✅ | 0 = 開始、1 = その peripheral を知らない |
| Swift | `setup` | `PicoBLECentral.swift:94-98` | ✅ | `CBCentralManager` を一度だけ作る |
| Swift | `powerOn` | `:100-109` | ✅ | poweredOn なら `[0x60,0x01,0x02]`（WORKING）を送る |
| Swift | `powerOff` | `:111-122` | ✅ | stopScan。**確立前の接続だけ** cancel し、確立済みの link は残す |
| Swift | `startScan` | `:124-132` | ✅ | **保持中の peripheral を（接続済みでも）cancel する**。FIFO を flush。`scanForPeripherals(withServices: nil, options: nil)`（重複報告なし、service UUID で絞らない） |
| Swift | `stopScan` | `:134-140` | ✅ | FIFO を flush（ADV の滞留を捨てる） |
| Swift | `connect` | `:142-156` | ✅ | scan 中に見つけた peripheral から引く。`connect(p, options: nil)`。**CoreBluetooth の connect はタイムアウトしない** |
| Swift | `discoverServices` | `:158-163` | ✅ | ツリーをリセットして `discoverServices(nil)` |
| Swift | 先行発見（eager） | `:299-326` | ✅ | services → 全 characteristic → 全 descriptor をまとめて発見 |
| Swift | `finalizeDiscovery` | `:385-451` | ✅ | 合成 CCCD を足し、pre-order DFS で **uint8 の合成 handle（1..255）** を振る。255 を超えたぶんは捨てる |
| Swift | `discoverCharacteristics` | `:165-176` | ✅ | 既に発見済みのものから 0xA2 を出し、0xA0 で締める |
| Swift | `discoverDescriptors` | `:231-241` | ✅ | 0xA4 を出し、0xA0 で締める |
| Swift | `readValue` | `:178-204` | ✅ | `.read` を持たない char は空値と 0xA0 を即答する。合成 CCCD は保持している状態を返す |
| Swift | **`writeValueWithoutResponse`** | `:208-214` | △ | `p.writeValue(Data(bytes), for: ch, type: .withoutResponse)` のみ。**`canSendWriteWithoutResponse` を見ない。長さを検査しない。結果を返さない。handle が不明なら黙って何もしない** |
| Swift | `writeDescriptor` | `:216-229` | △ | CCCD（合成・実物とも）なら `setNotifyValue(enable)`。それ以外は `writeValue(_:for: CBDescriptor)`。**完了イベントを出さない** |
| Swift | `didUpdateValueFor`（characteristic） | `:328-340` | ✅ | 自分で発行した read なら 0xA5+0xA0、それ以外は **0xA7（notify）** |
| Swift | `didUpdateValueFor`（descriptor） | `:342-346` | ✅ | 0xA5+0xA0 |
| Swift | `didConnect` | `:260-267` | ✅ | `[0x3E,0x01,0x01,0x00,h_lo,h_hi]`（LE Connection Complete）。conn_handle は 0x0040 固定 |
| Swift | `didFailToConnect` / `didDisconnectPeripheral` | `:269-275` → `connectionLost` `:291-295` | △ | **`[0x3E,0x01,0x05]` + 0xA0** を送る。共通 decoder は切断と解釈しない（§3.6） |
| Swift | `centralManager(_:didDiscover:...)` | `:251-258` | △ | ADV TLV に入るのは **local name（0x09）と manufacturer data（0xFF）だけ**（`advTLV` `:488-499`）。service UUID・TX power は入らない。`peripheral.name` への fallback も無い。address は `identifier` をハッシュした 6 byte で、type は 0x01 固定（`:480-486`） |
| Swift | `peripheralIsReady(toSendWriteWithoutResponse:)` | — | ❌ | 未実装 |
| Swift | `canSendWriteWithoutResponse` の参照 | — | ❌ | 未実装 |
| Swift | `maximumWriteValueLength(for:)` | — | ❌ | 未実装（MTU に相当する値を Ruby に出していない） |
| Swift | `writeValue(..., type: .withResponse)` / `didWriteValueFor` | — | ❌ | 未実装 |
| Swift | `didUpdateNotificationStateFor` | — | ❌ | 未実装。購読の成否が分からない |
| Swift | `didWriteValueFor descriptor` | — | ❌ | 未実装 |
| Swift | Ruby から `cancelPeripheralConnection` | — | ❌ | 内部でだけ使う（`:265, :284`） |
| Swift | RSSI 読み出し、scan option、connect option、`didModifyServices` | — | ❌ | 未実装 |

※ `grep` で確認済み: `PicoBLECentral.swift` と `PicoBLEExports.swift` に `didWriteValueFor`、`peripheralIsReady`、`canSendWriteWithoutResponse`、`maximumWriteValueLength`、`didUpdateNotificationStateFor`、`readRSSI`、`AllowDuplicates`、`withResponse` は一つも出てこない。

### 3.4 write の詳細（大量送信に効く部分）

- **without response と with response の区別**: Ruby からは without response しか出せない。CCCD 以外の descriptor への write だけは、CoreBluetooth の仕様で with response になる。
- **1 回の write の最大長**:
  - Ruby → C で `(uint16_t)RSTRING_LEN(data)` にキャストされる（`src/mruby/ble_central.c:65`）。65535 byte を超えると黙って切り詰められる。
  - C → Swift でバイト列をコピーしてから async で投げる（`PicoBLEExports.swift:39-42`）。mruby の String が GC されても安全。
  - CoreBluetooth に渡す前に長さを検査しない。`maximumWriteValueLength(.withoutResponse)` を超えたときの挙動は SDK ヘッダに書かれておらず、本調査でも未検証。**ATT_MTU-3 以下に分割するのは呼び出し側の責任**になる。
- **フロー制御**: 無い。SDK ヘッダ（`xcrun --show-sdk-path` 配下の `CoreBluetooth.framework/Headers/CBPeripheral.h`）には次のようにある。
  - `canSendWriteWithoutResponse`（:105-112）: "YES if the remote device has space to send a write without response. If this value is NO, the value will be set to YES after the current writes have been flushed, and peripheralIsReadyToSendWriteWithoutResponse: will be called."
  - `writeValue:forCharacteristic:type:`（:197-201）: "If the CBCharacteristicWriteWithoutResponse type is specified, and canSendWriteWithoutResponse is false, the delivery of the data is best-effort and may not be guaranteed."
  - したがって Ruby 側で間隔を空けずに連続して write すると、全部が `cbQueue` に積まれて立て続けに `writeValue` が呼ばれ、**取りこぼす可能性がある**。
  - なお、同じリポジトリの `ports/darwin/test/test_flood.swift:89-99` は、`canSendWriteWithoutResponse` を見て `peripheralIsReady` で再開する正しい実装になっている。ただしこれは picoruby-ble を使わない単体の Swift テストドライバ。
- **MTU**: Ruby に出す手段が無い。central 側は MTU のイベントも出していない（0xB5 は peripheral 用: `PicoBLEPackets.swift:28`、`PicoBLEPeripheral.swift:349`）。CoreBluetooth は MTU を自動で交渉する。
- **実運用での回避策**: stackchan は 180 byte 固定のチャンクを（`picoruby-drb-ble/mrblib/drb-ble.rb:2`）、前回の送信から 20ms 空けて送っている（`central.rb:143-151`）。

### 3.5 notify の受信

- 購読: notify/indicate を持つ characteristic には、CoreBluetooth が CCCD を見せなくても **合成 CCCD（UUID 0x2902）** が付き、handle が振られる（`PicoBLECentral.swift:365-381`）。実物の CCCD が見えている場合も `setNotifyValue` 経由に回す（`:426-435`）。CCCD を直接書くと CoreBluetooth が `NSInternalInconsistencyException` を投げるため。
- 受信: `didUpdateValueFor` で、自分が発行した read でなければ `0xA7` を作る（`:337-339`）。レイアウトは `[0xA7, len, 0,0, 0,0, 0,0, vh, 0, L, 0, value...]`（`PicoBLEPackets.swift:91-95`）。
  - **値は 255 byte で切り詰められる**（`min(value.count, 255)`）。
  - value handle は合成 handle で、`services` の `value_handle` と一致する。
- Ruby 側: 共通 decoder は 0xA7 を TODO として捨てる（`ble_central.rb:326-328`）。**`packet_callback` をオーバーライドして `super` の後に自分で decode する**。
- ⚠ `ports/darwin/README.md:18-20` には「0xA7/0xA8 は合成しない」と書いてあるが、**コードは 0xA7 を合成している（README が古い）**。0xA8（indication）は 0xA7 として届く。
- CCCD を書いた後、完了（0xA0）は来ない。e2e は 10×100ms（`e2e_central_test.rb:162-164`）、stackchan は 200ms（`central.rb:7, 180-190`）待っている。

### 3.6 切断と接続寿命（罠が多い）

- darwin の切断パケットは `pbleDisconnect() = [0x3E, 0x01, 0x05]`（`PicoBLEPackets.swift:41`）。これは「LE_META の subevent 0x05」の形をしている。共通 decoder が切断として扱うのは `getbyte(0) == 0x05` だけ（`ble_central.rb:130-133`）。LE_META は `:TC_W4_CONNECT` のときだけ見て、しかも subevent 0x01 しか扱わない（`:110-129`）。結果として、**darwin では切断が共通 decoder に届かず、`@state` も `@conn_handle` も更新されない**。
  - この形は最初のコミット（2b5b516f, 2026-06-19）から変わっていない。
  - esp32 は `[0x05, 4, h, h, 0, reason]` を送るので decoder が拾える（`ports/esp32/ble.c:453-458`）。
  - stackchan は自前で両方の形を判定している（`stackchan-controller/radio.rb:30-35, 51-55`）。README にも「darwin central reports a disconnect as the packet [0x3E,0x01,0x05]」と書いてある（`stackchan-picoruby/pc/stackchan-pico/README.md:160-164`）。
- 接続の寿命（`ports/darwin/README.md:92-105`, `PeripheralLifetime.swift`）:
  - `scan` が戻ると `start` の `ensure` で power OFF になる。**確立済みの link は残る**ので、`scan` の後も write や notify を使える。
  - **もう一度 `scan`/`start` を呼ぶと、power ON → WORKING → decoder が `start_scan` → `giveBackAtScanStart` の順に進み、保持中の接続を cancel する。** `scan` は最後に `reset_state` で `@state = :TC_OFF` にする（`ble_central.rb:62`）ので、`start` を呼んだだけでもこの流れになる。stackchan の README にも「scan re-powers the controller and the port flushes in-flight packets, so it runs only from connect」とある（`pc/stackchan-pico/README.md:40-42`）。
  - 接続に失敗したときは `[0x3E,0x01,0x05]` + 0xA0 が来るが、`:TC_W4_CONNECT` の decoder はどちらも処理しないので、**`scan` は timeout まで戻らない**。`timeout_ms` は必ず指定すること。
- 接続は 1 本だけ（`PicoBLECentral.swift:66-71`）。

### 3.7 その他の制約

- handle は uint8（1..255）。C で `(uint8_t)` にキャストされる（`ble.c:99,106,113,120,127`）。
- 発見の途中で、**読める全 characteristic と全 descriptor の値を read する**（状態機械の仕様）。
- ADV report は 1 peripheral につき 1 回だけ（`options: nil`）。local name が初回の `advertisementData` に無ければ、名前でのマッチは失敗する（`peripheral.name` への fallback が無い。`test_central.swift:58` は `?? p.name` しているのと対照的）。この点は未検証の懸念。
- service UUID は ADV report に載らない。service UUID で絞ることはできず、名前で絞るしかない。
- `uuid32`: 古いコメントに「バイトスワップする（0x181A が 0x1A180000 になる）」とあるが（`test/gatt_dump_probe.rb:5-7`, `test/esp32_dynamic_read_test.rb:43-48`。どちらも 2026-08-10 以前）、`ble_utils.rb:51-57` は a5f99d3a（2026-09-09, #494）で直っている。decoder の契約テストも 0x180D を期待している（`test/decoder_contract_test.rb:91-93`）。それでも **`uuid128` で照合するのが安全**（stackchan も e2e もそうしている）。
- MacBook 自身が peripheral になったものは同じ Mac から見えない（README:183-186。今回は無関係）。

---

## 4. btstack（rp2040）/ NimBLE（esp32）との API 差異

Ruby API（`src/mruby/ble_central.c` と `mrblib/`）は全ポート共通。差が出るのはポートの振る舞い。

| 項目 | rp2040（BTstack） | esp32（NimBLE） | darwin（CoreBluetooth） |
|---|---|---|---|
| イベントの出所 | BTstack の実パケットをそのまま渡す（`ports/rp2040/ble.c:74-95`） | 合成 | 合成 |
| write without response の戻り値 | BTstack のエラーコード（`ble.c:243-247`）。バッファ満杯や長すぎは非 0 | NimBLE の rc（`ports/esp32/ble.c:768-772`） | **常に 0**（`ports/darwin/ble.c:117-122`） |
| 長すぎる write | BTstack がエラーを返す | NimBLE がエラーを返す | 検査しない |
| CCCD write の完了 0xA0 | 出る（BTstack の gatt_client） | 出る（`write_attr_cb` `ports/esp32/ble.c:725-732`） | **出ない** |
| 切断イベント | `[0x05,...]`（実パケット） | `[0x05,4,h,h,0,reason]`（`ble.c:453-458`） | **`[0x3E,0x01,0x05]`**（decoder が拾えない） |
| 接続失敗 | LE_META status≠0 | LE_META status≠0（`ble.c:430-450`） | 切断と同じパケット（失敗 status を持つ LE_META は出ない） |
| notify（0xA7） | 実パケット | 合成（`ble.c:547-559`） | 合成。255 byte で切り詰め |
| indicate（0xA8） | 出る | 出る | 0xA7 として出る |
| GATT handle | 実 handle（uint16） | 実 handle | 合成 uint8（≤255） |
| scan のパラメータ | 有効 | 有効 | 無視 |
| ADV TLV | 実データ | 実データ | name と mfg data だけ再構成 |
| `gap_local_bd_addr` | 実アドレス | 実アドレス | 0 埋め |
| power OFF | 無線を止める | 止める | 接続中の link は残す |
| MTU イベント（central） | 転送しない | 出さない（peripheral のみ） | 出さない |
| write with response / 切断 API | 無し | 無し | 無し |

---

## 5. テストとサンプル

### 5.1 一覧（central に関係するもの）

| ファイル | 種別 | 中身 |
|---|---|---|
| `picoruby-ble/example/peripheral-central/central/app.rb` | サンプル | scan → connect → 発見 → 表示（write も notify も無し） |
| `picoruby-ble/example/probe/central_paths_probe.rb` | 実機 probe | **write w/o response、CCCD 購読、notify の生パケット受信**（`stop_state: :no_stop` でループ内から駆動） |
| `picoruby-ble/ports/darwin/test/e2e_central_test.rb` | 実機 E2E（`RUN_E2E=1`） | 発見と read。**`scan` 後に購読 → write → notify 待ち**（`pop_and_dispatch` 方式） |
| `picoruby-ble/ports/darwin/test/decoder_contract_test.rb` | 無線不要 | 合成バイト列を decoder に流して services ツリーを検証 |
| `picoruby-ble/ports/darwin/test/nus4_decoder_contract_test.rb` | 無線不要 | NUS 形（2 service / 4 char / 2 CCCD） |
| `picoruby-ble/ports/darwin/test/esp32_dynamic_read_test.rb` | 実機 | read の検証 |
| `picoruby-ble/ports/darwin/test/gatt_dump_probe.rb` | 実機 | GATT を 128bit UUID でダンプ（**Phomemo の GATT 確認にそのまま使える**） |
| `picoruby-ble/ports/darwin/test/heartbeat_probe.rb` | 実機 | heartbeat が届くかを数える |
| `picoruby-ble/ports/darwin/test/e2e_broadcaster_scan_test.rb` | 実機 | scan だけ |
| `picoruby-ble/ports/darwin/ext/Tests/PicoBLELifetimeTests/PeripheralLifetimeTests.swift` | `swift test` | 接続寿命の判断 |
| `picoruby-ble/ports/darwin/test/test_central.swift` / `test_flood.swift` / `test_peripheral.swift` | 単体 Swift | 他ポートを検証する相手役。picoruby-ble は使っていない |
| `R2P2-darwin/examples/macos/ble-subscribe/ble-subscribe.rb` | Mac 用サンプル | scan → 発見 → CCCD 購読 → notify 表示（`stop_state: :no_stop`） |
| `stackchan-picoruby/mrbgems/picoruby-stackchan-controller/mrblib/stackchan-controller/{radio,central,gatt}.rb` | 実運用 gem | 接続、購読、分割 write、ACK、切断検知 |

### 5.2 全文引用: `picoruby-ble/example/peripheral-central/central/app.rb`

```ruby
require 'ble'

class DemoCentral < BLE
  TARGET_NAME = "PicoRuby"

  def initialize
    super(:central)
  end

  def advertising_report_callback(adv_report)
    return unless adv_report.name_include?(TARGET_NAME)
    puts adv_report.format
    connect(adv_report)
  end
end

central = DemoCentral.new
central.scan(timeout_ms: 30_000, debug: true)

central.services.each do |service|
  puts sprintf("Service 0x%04X", service[:uuid32] || 0)
  service[:characteristics].each do |chara|
    puts sprintf("  Characteristic 0x%04X value: %s", chara[:uuid32] || 0, chara[:value].inspect)
  end
end
```

### 5.3 全文引用: `picoruby-ble/example/probe/central_paths_probe.rb`

```ruby
require 'ble'

# C3 (notification) only surfaces via packet_callback: ble_central.rb's GATT_EVENT_NOTIFICATION branch is an empty TODO.
class CentralPathsProbe < BLE
  TARGET_NAME = "PBLE-DARWIN"
  SERVICE     = 0x181A
  CHAR_NOTIFY = 0x2A6E
  CHAR_WRITE  = 0x2A9F

  def initialize
    super(:central)
    @wrote = false
    @subscribed = false
    @notify_seen = 0
  end

  def advertising_report_callback(adv_report)
    return unless adv_report.name_include?(TARGET_NAME)
    puts "[probe] found #{TARGET_NAME} rssi=#{adv_report.rssi}, connecting"
    connect(adv_report)
  end

  def packet_callback(event_packet)
    if event_packet.getbyte(0) == GATT_EVENT_NOTIFICATION ||
       event_packet.getbyte(0) == GATT_EVENT_INDICATION
      @notify_seen += 1
      kind = (event_packet.getbyte(0) == GATT_EVENT_NOTIFICATION) ? "NOTIFICATION" : "INDICATION"
      puts "[probe] C3 raw #{kind} raw=#{event_packet.bytesize} " \
           "handle=#{Utils.little_endian_to_int16(event_packet.byteslice(GATT_EVENT_PAYLOAD_OFFSET, 2))} count=#{@notify_seen}"
    end
    super
    # drive also runs here so C1/C2 go out on the QUERY_COMPLETE that ends discovery.
    drive
  end

  # Bluetooth Base UUID tail shared by every 16-bit UUID promoted to 128 bits.
  BT_BASE_SUFFIX = "\x00\x00\x10\x00\x80\x00\x00\x80\x5F\x9B\x34\xFB"

  def uuid128_for(uuid16)
    "\x00\x00" + [(uuid16 >> 8) & 0xff, uuid16 & 0xff].pack("CC") + BT_BASE_SUFFIX
  end

  # Matches on uuid128.
  def pick(list, uuid16)
    want = uuid128_for(uuid16)
    found = nil
    list.each { |e| found = e if e[:uuid128] == want } # Array#find isn't in the base VM
    found
  end

  # :TC_IDLE only follows the last GATT_EVENT_QUERY_COMPLETE, so that's what makes @conn_handle/@services safe to read.
  def drive
    return if @wrote
    return if state != :TC_IDLE
    svc = pick(services, SERVICE)
    unless svc
      return if @dumped
      @dumped = true
      puts "[probe] service 0x#{SERVICE.to_s(16)} not discovered; services=#{services.size}"
      services.each do |s|
        puts "[probe]   svc uuid32=0x#{s[:uuid32].to_s(16)} uuid128=#{s[:uuid128].inspect} " \
             "handles=#{s[:start_handle]}..#{s[:end_handle]} chars=#{s[:characteristics].size}"
        s[:characteristics].each do |c|
          puts "[probe]     chr uuid32=0x#{c[:uuid32].to_s(16)} vh=#{c[:value_handle]} props=#{c[:properties]}"
        end
      end
      return
    end
    wr = pick(svc[:characteristics], CHAR_WRITE)
    nt = pick(svc[:characteristics], CHAR_NOTIFY)
    unless wr && nt
      puts "[probe] characteristics missing write=#{!wr.nil?} notify=#{!nt.nil?}"
      return
    end
    rc = write_value_of_characteristic_without_response(@conn_handle, wr[:value_handle], "HELLO")
    puts "[probe] C1 write_value_of_characteristic_without_response rc=#{rc}"

    cccd = pick(nt[:descriptors], CLIENT_CHARACTERISTIC_CONFIGURATION)
    if cccd
      rc = write_characteristic_descriptor_using_descriptor_handle(@conn_handle, cccd[:handle], "\x01\x00")
      puts "[probe] C2 write_characteristic_descriptor_using_descriptor_handle rc=#{rc}"
      @subscribed = true
    else
      # Dumping here saves a device round-trip vs. rediscovering.
      puts "[probe] CCCD descriptor not discovered on the notify characteristic"
      puts "[probe] descriptors=#{nt[:descriptors].inspect}"
    end
    @wrote = true
  end

  def heartbeat_callback
    drive
    puts "[probe] state=#{state} notify_seen=#{@notify_seen}"
  end
end

probe = CentralPathsProbe.new
# debug: pass it to scan; scan assigns @debug itself.
probe.scan(timeout_ms: 120_000, stop_state: :no_stop, debug: true)
```

注: `pick(nt[:descriptors], CLIENT_CHARACTERISTIC_CONFIGURATION)` は uuid128 で照合する `pick` に 16bit の 0x2902 を渡しているので、`uuid128_for(0x2902)` で正しく引ける。

### 5.4 全文引用: `picoruby-ble/ports/darwin/test/e2e_central_test.rb`（1-176 行。177-216 行は他テストと同じ picotest の自前ランナー定型なので省略）

```ruby
# Live-radio E2E for the CoreBluetooth central. Needs a peripheral on a 2nd
# device (a Mac central cannot see a same-Mac peripheral). Skipped without
# RUN_E2E=1. See ports/darwin/README.md for the full procedure.

require "picotest"

class E2ECentral < BLE
  attr_reader :picked, :seen, :notified

  # Not exposed by ble_central.rb's own attr_reader list.
  def conn_handle
    @conn_handle
  end

  def initialize(role, target_name)
    super(role)
    @target_name = target_name
    @seen = []
    @picked = nil
    @notified = []
  end

  def advertising_report_callback(r)
    return unless @state == :TC_W4_SCAN_RESULT
    name = r.reports[:complete_local_name] || r.reports[:shortened_local_name]
    @seen << [r.rssi, r.address, r.address_type_code, name]
    if !@target_name.empty? && name && name.include?(@target_name)
      pick(r.address, r.address_type_code, name, r.rssi)
    end
  end

  def pick(addr, atype, name, rssi)
    return if @picked
    @picked = [addr, atype, name, rssi]
    STDOUT.puts "[central] connecting to #{name.inspect} rssi=#{rssi}"
    stop_scan
    @state = :TC_W4_CONNECT
    gap_connect(addr, atype)
  end

  def connect_strongest
    best = nil
    @seen.each { |e| best = e if best.nil? || e[0] > best[0] }
    return false unless best
    STDOUT.puts "[central] no name match; strongest device rssi=#{best[0]} name=#{best[3].inspect}"
    pick(best[1], best[2], best[3], best[0])
    true
  end

  # Find the first characteristic across all discovered services whose
  # property bitmask includes `prop` (BLE::NOTIFY / BLE::WRITE). Matching on
  # properties, not UUID, sidesteps the byte-swap this port applies to 16-bit
  # UUIDs (see esp32_dynamic_read_test.rb's own comment on the same issue).
  def find_by_property(prop)
    services.each do |s|
      s[:characteristics].each do |ch|
        return ch if (ch[:properties] & prop) != 0
      end
    end
    nil
  end

  # Non-blocking drain of one event from the queue, mirroring
  # pc/stackchan-pico/app/ble_client.rb's StackchanRadio#pop_and_dispatch —
  # this test exercises the exact same primitive the production central uses.
  def pop_and_dispatch
    event = @event_queue.pop(timeout_ms: 0)
    return nil unless event
    _event_popped
    packet_callback(event) if event.is_a?(String)
    event
  end

  # The base packet_callback's GATT_EVENT_NOTIFICATION branch is a bare
  # `# TODO` (ble_central.rb:297) -- notifications are otherwise silently
  # dropped. Decode and log every one so a failed wait leaves evidence behind.
  def packet_callback(event_packet)
    super
    return unless event_packet.getbyte(0) == GATT_EVENT_NOTIFICATION
    # BTstack 1.6+ layout: payload at GATT_EVENT_PAYLOAD_OFFSET(8) —
    # value_handle(8..9), length(10..11), value(12..)
    handle = Utils.little_endian_to_int16(event_packet.byteslice(8, 2))
    len    = Utils.little_endian_to_int16(event_packet.byteslice(10, 2))
    value  = event_packet.byteslice(12, len)
    @notified << [handle, value]
    STDOUT.puts "[notify-e2e] NOTIFY handle=#{handle} value=#{value.inspect}"
  end

  # Cooperative wait for at least one notification, draining via
  # pop_and_dispatch rather than calling scan/start again (which would
  # re-trigger hci_power_control and flush any in-flight packet -- see
  # ble_client.rb's file-level comment for the full rationale).
  def await_notification(ticks, poll_ms)
    i = 0
    while @notified.empty? && i < ticks
      pop_and_dispatch
      sleep_ms(poll_ms)
      i += 1
    end
    @notified.shift
  end
end

class E2ECentralTest < Picotest::Test
  TARGET_NAME = ENV["TARGET_NAME"] || "PBLE-TEST"
  SCAN_MS     = (ENV["SCAN_MS"] || "12000").to_i

  # One test method so the 12s scan runs once, not once per assertion.
  def test_scan_connect_discover_read
    skip "RUN_E2E=1 not set" unless ENV["RUN_E2E"] == "1"

    c = E2ECentral.new(:central, TARGET_NAME)
    c.scan(timeout_ms: SCAN_MS, stop_state: :TC_IDLE, debug: true)
    c.start(15000, :TC_IDLE) if !c.picked && c.connect_strongest

    STDOUT.puts "[central] discovery done; state=#{c.state} services=#{c.services.size}"
    c.services.each do |s|
      STDOUT.puts "  svc uuid32=#{sprintf('0x%08X', s[:uuid32] || 0)} #{s[:start_handle]}..#{s[:end_handle]}"
      s[:characteristics].each do |ch|
        STDOUT.puts "    char uuid32=#{sprintf('0x%08X', ch[:uuid32] || 0)} vh=#{ch[:value_handle]} props=#{ch[:properties]} value=#{ch[:value].inspect}"
        ch[:descriptors].each do |d|
          STDOUT.puts "      desc uuid32=#{sprintf('0x%08X', d[:uuid32] || 0)} handle=#{d[:handle]} value=#{d[:value].inspect}"
        end
      end
    end

    # state == :TC_IDLE is transient — the scan loop stops on it ("Stopped by
    # state: TC_IDLE" in the trace) and the central then transitions to
    # :TC_OFF. Discovery + read completion are what PASS actually means.
    assert(c.services.size >= 1)
    assert(c.services.any? { |s| s[:characteristics].any? { |ch| !ch[:value].nil? } })
  end

  # Counterpart: mrbgems/picoruby-ble/example/esp32/probe/peripheral_paths_probe.rb
  # (bash0C7/picoruby, picoruby-ble-esp32-port branch). That probe's README
  # names "a Central that connects, subscribes, writes" as its required peer;
  # this fills that gap using the exact primitives StackchanCentral (the
  # production Mac-side BLE central) relies on for its write-then-await-ACK
  # path. Scoped to a single connect cycle -- the probe's own disconnect-twice
  # (P6/P7) requirement needs a GAP disconnect this port's central role has no
  # API for at all (verified: no `disconnect` in ble.rbs, ble_central.rb, or
  # PicoBLECentral.swift), so it is out of scope here.
  def test_subscribe_write_receive_notification
    skip "RUN_E2E=1 not set" unless ENV["RUN_E2E"] == "1"

    probe_name = ENV["PROBE_TARGET_NAME"] || "PBLE-PROBE"
    c = E2ECentral.new(:central, probe_name)
    c.scan(timeout_ms: SCAN_MS, stop_state: :TC_IDLE, debug: true)

    STDOUT.puts "[notify-e2e] discovery done; state=#{c.state} services=#{c.services.size}"
    notify_ch = c.find_by_property(BLE::NOTIFY)
    write_ch  = c.find_by_property(BLE::WRITE)
    STDOUT.puts "[notify-e2e] notify_ch=#{notify_ch.inspect}"
    STDOUT.puts "[notify-e2e] write_ch=#{write_ch.inspect}"
    assert(!notify_ch.nil?)
    assert(!write_ch.nil?)
    return unless notify_ch && write_ch

    cccd_handle = notify_ch[:descriptors][0][:handle]
    STDOUT.puts "[notify-e2e] subscribing cccd_handle=#{cccd_handle}"
    c.write_characteristic_descriptor_using_descriptor_handle(c.conn_handle, cccd_handle, "\x01\x00")
    # Settle: give CoreBluetooth's setNotifyValue time to land before the
    # write goes out, matching ble_client.rb's subscribe_tx.
    10.times { c.pop_and_dispatch; sleep_ms(100) }

    payload = "E2E-WRITE-PROBE"
    STDOUT.puts "[notify-e2e] writing #{payload.inspect} to vh=#{write_ch[:value_handle]}"
    c.write_value_of_characteristic_without_response(c.conn_handle, write_ch[:value_handle], payload)

    # 80 x 100ms = 8s -- generous vs. StackchanCentral::ACK_TIMEOUT_TICKS (30
    # x 100ms = 3s) so a slow-but-working path still shows as a PASS here.
    received = c.await_notification(80, 100)
    STDOUT.puts "[notify-e2e] received=#{received.inspect} all_notified=#{c.notified.inspect}"
    assert(!received.nil?)
  end
end
```

注: コメント中の「byte-swap」は #494 で解消済み（§3.7）。`ble_central.rb:297` という行番号も古く、今は `:326-328`。

### 5.5 全文引用: `R2P2-darwin/examples/macos/ble-subscribe/ble-subscribe.rb`

```ruby
# A BLE central for the macOS host. It scans for a peripheral whose name
# includes TARGET_NAME (default "PicoRuby"), connects, discovers its services,
# subscribes to the first characteristic that notifies, and prints every
# notification until the scan window (SCAN_MS, default 40000) closes. The
# picoruby-ble peripheral example on a Pico W / Pico 2 W is the intended peer.

require "env"
require "ble"

class SubscribeCentral < BLE
  def initialize(target_name)
    super(:central)
    @target_name = target_name
    @picked = false
    @subscribed = false
  end

  def advertising_report_callback(report)
    return if @picked || !report.name_include?(@target_name)
    @picked = true
    puts report.format
    connect(report)
  end

  def packet_callback(event_packet)
    super
    if event_packet.getbyte(0) == GATT_EVENT_NOTIFICATION
      # BTstack 1.6+ layout: payload at offset 8 (value_handle, length, value)
      handle = Utils.little_endian_to_int16(event_packet.byteslice(8, 2))
      length = Utils.little_endian_to_int16(event_packet.byteslice(10, 2))
      value = event_packet.byteslice(12, length) || ""
      puts "Notification from handle #{handle}: #{value.inspect} (#{hex_bytes(value)})"
    end
    subscribe if @state == :TC_IDLE && !@subscribed
  end

  def subscribe
    @subscribed = true
    chara = notifying_characteristic
    unless chara
      puts "No characteristic with NOTIFY"
      return
    end
    cccd = client_characteristic_configuration(chara)
    unless cccd
      puts "No CCCD under value handle #{chara[:value_handle]}"
      return
    end
    puts "Subscribing to value handle #{chara[:value_handle]} through CCCD handle #{cccd[:handle]}"
    write_characteristic_descriptor_using_descriptor_handle(@conn_handle, cccd[:handle], "\x01\x00")
  end

  def notifying_characteristic
    services.each do |service|
      service[:characteristics].each do |chara|
        return chara if (chara[:properties] & NOTIFY) != 0
      end
    end
    nil
  end

  def client_characteristic_configuration(chara)
    chara[:descriptors].each do |desc|
      return desc if desc[:uuid128].byteslice(0, 4) == "\x00\x00\x29\x02"
    end
    nil
  end

  def hex_bytes(value)
    value.bytes.map { |b| sprintf("%02X", b) }.join(" ")
  end
end

central = SubscribeCentral.new(ENV["TARGET_NAME"] || "PicoRuby")
central.scan(timeout_ms: (ENV["SCAN_MS"] || "40000").to_i, stop_state: :no_stop)
```

### 5.6 全文引用: `stackchan-picoruby/mrbgems/picoruby-stackchan-controller/mrblib/stackchan-controller/radio.rb`（実運用で picoruby-ble に依存する gem）

```ruby
module StackChan
  class Controller
    class Radio < BLE
      attr_reader :target, :conn_handle
      attr_accessor :on_notification, :on_disconnect

      def initialize(name_prefix:)
        @name_prefix    = name_prefix
        @target         = nil
        @on_notification = nil
        @on_disconnect   = nil
        super(:central)
      end

      def pop_and_dispatch
        _event_popped
        event = @event_queue.pop(timeout_ms: 0)
        return nil unless event
        packet_callback(event) if event.is_a?(String)
        event
      end

      def advertising_report_callback(report)
        return if @target
        return unless report.name_include?(@name_prefix)
        @target = report
        connect(report)
      end

      def packet_callback(event_packet)
        if disconnect_packet?(event_packet)
          @conn_handle = HCI_CON_HANDLE_INVALID
          cb = @on_disconnect
          cb.call if cb
        end
        super
        return unless event_packet.getbyte(0) == GATT_EVENT_NOTIFICATION
        cb = @on_notification
        cb.call(gatt_event_int16(event_packet, 0), gatt_event_value(event_packet)) if cb
      end

      def connect_and_discover(timeout_ms)
        @target = nil
        @conn_handle = HCI_CON_HANDLE_INVALID
        @services.clear
        scan(timeout_ms: timeout_ms, stop_state: :TC_IDLE)
      end

      private

      def disconnect_packet?(event_packet)
        type = event_packet.getbyte(0)
        return true if type == HCI_EVENT_DISCONNECTION_COMPLETE
        type == HCI_EVENT_LE_META && event_packet.getbyte(2) == HCI_EVENT_DISCONNECTION_COMPLETE
      end
    end
  end
end
```

同じ gem の `central.rb` から、write と購読の部分を抜粋する（行番号は原文のもの）。
- 定数（`:4-12`）: `CONNECT_TIMEOUT_MS = 15_000`、`POLLING_UNIT_MS = 20`、`ACK_TIMEOUT_MS = 3_000`、`SUBSCRIBE_SETTLE_MS = 200`
- 接続（`:56-71`）: `connect_and_discover` → `target` と `conn_handle` を確認 → `resolve_handles`（uuid128 で照合、`gatt.rb:18-30`） → `subscribe_tx` の順。
- 分割 write（`:143-151`）:

```ruby
      def send_chunk(bytes)
        raise ConnectionError, "not connected" unless @connected
        if @drb_sent_at
          wait = POLLING_UNIT_MS - (Machine.board_millis - @drb_sent_at)
          sleep_ms(wait) if wait > 0
        end
        @radio.write_value_of_characteristic_without_response(@radio.conn_handle, @drb_rx_handle, bytes)
        @drb_sent_at = Machine.board_millis
      end
```

- 購読（`:180-190`）: CCCD に `"\x01\x00"` を書き、`settle(200)` の間 20ms ごとに `drain`（pop_and_dispatch のループ）と `sleep_ms` を繰り返す。
- mrbgem 依存（`mrbgem.rake:6`）: `spec.add_dependency 'picoruby-ble'`

---

## 6. macOS で CoreBluetooth を使う前提（リポジトリ内の記述と工夫）

### 6.1 記述（repo によって食い違いがある点に注意）

| 出典 | 内容 |
|---|---|
| `picoruby-ble/ports/darwin/README.md:143-147, 227-228` | Bluetooth を ON にし、**ターミナル（またはバイナリを起動するアプリ）**が「プライバシーとセキュリティ → Bluetooth」で許可を持っていること。`build/host/bin/picoruby` を直接実行する手順で書かれている |
| `origin/port-darwin:build_config/darwin-ble-test.rb:20-24` + `build_config/darwin-ble-test-Info.plist` | 「バンドルではない CLI の Mach-O でも、TCC は NSBluetoothAlwaysUsageDescription を読める場所に要求する」として、`-Wl,-sectcreate,__TEXT,__info_plist,<plist>` で **Info.plist をバイナリに埋め込んでいる** |
| `picoruby-ble/ports/darwin/test/build_app_bundles.sh:4-7, 15-37` | **`.app` を作って Info.plist（`NSBluetoothAlwaysUsageDescription` / `NSBluetoothPeripheralUsageDescription`）を置き、`codesign --force --deep -s -`（ad-hoc）**。「TCC の許可は ad-hoc 署名に紐づくので、再ビルドのたびに失効する。再許可は手作業でしか戻せない」 |
| `picoruby-ble/ports/darwin/test/heartbeat_probe.rb:9-11`、`esp32_dynamic_read_test.rb:5-8` | 許可済みのバンドルを `open -W -a ~/Applications/<App>.app --stdout LOG --stderr LOG --env K=V --args <絶対パス>` で起動するか、`~/Applications/PicoRubyBLE.app/Contents/MacOS/picoruby-bin <file>` を直接実行する |
| `R2P2-darwin/README_jp.md:255-260` | 「BLE 設定でビルドしたバイナリは、`./build/host/bin/picoruby` を直接実行する形では動かない。macOS の TCC は、`NSBluetoothAlwaysUsageDescription` を宣言したアプリバンドルから LaunchServices 経由で起動されたのでないプロセスの CoreBluetooth 呼び出しを、署名済み・許可済みであっても例外なく `SIGABRT` で落とす」 |
| `R2P2-darwin/examples/macos/ble-subscribe/README_jp.md:28-59` | `.app` 化 → `codesign --force --deep -s -` → `open -W -a "$app" --stdout ... --env ... --args "$PWD/....rb"`。初回に許可ダイアログが出る |
| `stackchan-picoruby/pc/stackchan-pico/README.md:178-193` | 同じく SIGABRT の記述に加えて、**launchd の LaunchAgent から `.app` 内のバイナリを直接起動するのも可**（launchd は TCC の responsible process として認められる） |
| `stackchan-picoruby/CLAUDE.md:115` | **ad-hoc の `codesign -s -` だけだと designated requirement が cdhash になり、再ビルドのたびに別アプリ扱いになる**。launchd から起動した daemon は許可ダイアログ待ちのまま、scan 結果を 1 件も受け取らない。**「Terminal から走らせた scan は Terminal の許可で動くので切り分けにならない」** |
| `stackchan-picoruby/Rakefile:797-806` | 対策: `codesign --force --deep -s - -r='designated => identifier "com.bash0c7.stackchanpico"' <app>`。requirement を bundle id に固定し、再ビルドしても許可が保たれるようにしている |
| `stackchan-picoruby/pc/stackchan-pico/StackchanPico-Info.plist` | `CFBundleExecutable` / `CFBundleIdentifier` / `CFBundleName` / `CFBundlePackageType=APPL` / `CFBundleShortVersionString` / `NSBluetoothAlwaysUsageDescription` / `NSBluetoothPeripheralUsageDescription` |

**食い違い**: 「ターミナルの許可で直接実行して動く」（port README、stackchan CLAUDE.md:115）と「直接実行は必ず SIGABRT」（R2P2-darwin README、stackchan README）が両立していない。起動元（GUI のターミナルか、別プロセスの子か）で responsible process が変わるためと推測されるが、**未検証**。CLI として配る前提なら、実績のある「`.app` + bundle id で固定した ad-hoc 署名 + `open -W -a`（または launchd）」で組むのが安全。この Mac（macOS 27.0.1）でどう動くかは実機での確認が要る。

### 6.2 ビルドの前提

- Swift: `Package.swift` は `swift-tools-version:6.3`。`@c`（SE-0495）を使うので Swift 6.3 以上が必要。この Mac は `/usr/bin/swift` = Apple Swift 6.4（Xcode）なので満たしている。swiftbuild（6.4）がヘッダの出力先を無視する問題は `mrbgem.rake:26-30` で吸収済み。
  - stackchan の注記（`CLAUDE.md:112`）: swiftly の Swift が Xcode の swift より先に PATH にあると、`unknown argument: '-target-arch-variant'` でビルドが失敗する。
- ビルド設定には `PICORB_PLATFORM_DARWIN`（`build.darwin?` の判定）と `PICORB_PLATFORM_POSIX`（mbedtls の `ports/common` を通すため。`darwin-ble-test.rb:8-12`）の両方が要る。`MRB_USE_TASK_SCHEDULER` が無いと `#error` になる（`src/mruby/ble.c:19-21`）。
- `conf.gem core: "hal-task-darwin"` を足す（§3.2）。
- `picoruby-ble` は `picoruby-mbedtls` に依存し、`ble.rb:1` で `require 'mbedtls'` する（R2P2-darwin の `CLAUDE.md:30-32` でも「外すな」とされている）。
- `darwin-ble-test.rb:34-53` のコメントによると、`AdvertisingReport` が `sprintf` と `Array#pack` を使うので、最小構成では `mruby-sprintf` と `mruby-pack` が要る（R2P2-darwin のように gembox `stdlib`/`core` を使う設定なら入っている）。
- OpenSSL（brew `openssl@3`）が要るのは networking gembox を入れる場合だけ（R2P2-darwin `README_jp.md:247-249`）。

---

## 7. 未コミット変更・TODO・既知の制約

- 未コミット変更: §0 のとおり。darwin ポートに関わるものは無い。
- TODO・FIXME（`picoruby-ble` 内）:
  - `mrblib/ble_central.rb:326-328`: `GATT_EVENT_NOTIFICATION` が `# TODO`。
  - `mrblib/ble_central.rb:280, 317`: 「read_value_of_characteristic_descriptor() doesn't work」のため、descriptor も value handle の read で読んでいる。
  - `src/mruby/ble_central.c:89, 108`: scan filter policy が未実装。
  - `src/ble.c:9-13`: 「critical section が要るかも」（`write_values_mutex`）。
  - `ports/darwin/ble.c:1`、`PicoBLECentral.swift:5, 66`: 「central/observer v1」「v1: one connection」。
- 古い記述（コードと合っていない）:
  - `ports/darwin/README.md:18-20`: 「0xA7/0xA8 は合成しない」→ 実際は 0xA7 を合成している。
  - `ports/darwin/test/gatt_dump_probe.rb:5-7`、`esp32_dynamic_read_test.rb:43-48`、`e2e_central_test.rb:52-53`: uuid32 のバイトスワップ → #494 で修正済み。
  - `PicoBLEFifo.swift:4-5`: 「100ms の poll tick で 1 パケットずつ drain」→ 今はスケジューラ hook で budget 分まとめて drain している（3f2dfa24）。
  - `PicoBLEExports.swift:4-5`: 「Swift never calls back into the gem's C … no -undefined dynamic_lookup」→ peripheral 側が `BLE_read_data`/`BLE_write_data` を呼ぶので、実際は dynamic_lookup でリンクしている（`Package.swift:8-11, 36`）。
  - `R2P2-darwin/docs/superpowers/notes/phase3-picoruby-ble-findings.md`: `pop_packet` の時代のメモで全体に古い。「value_handle は darwin で uint8 に切り詰められる」「write の ACK は無い」は今も正しい。
- 既知の制約（コメントに明記されているもの）: 255 handle と 255 byte の上限（README:117-122）、切断 API が無い（`e2e_central_test.rb:139-142`、stackchan README:120-123, 171-173）、不変条件は規約頼み（README:86-90）、同じ Mac の peripheral は見えない（README:183-186）。

---

## 8. 足りない機能（Phomemo の CLI に効く順）

1. **write without response のフロー制御**（`canSendWriteWithoutResponse`、`peripheralIsReady(toSendWriteWithoutResponse:)`）を Ruby に出すこと。今は時間ベースの sleep で代用するしかない。
2. **最大 write 長**（`maximumWriteValueLength(for: .withoutResponse)`）を取る API。今はチャンク長を決め打ちするしかない。
3. **write の結果を返すこと**（未接続・handle 不明・長すぎを検出できない。常に 0 が返る）。
4. **切断イベントの形を揃えること**（`[0x05,...]` で出すか、decoder に LE_META の subevent 0x05 も切断として扱わせる）。今はサブクラスで自分で判定する。
5. **切断 API**（`cancelPeripheralConnection` を Ruby に出す）。今はプロセスの終了に任せる。
6. write with response（`didWriteValueFor` の 0xA0 も含めて）。Phomemo が without response で足りるなら不要。
7. 購読の完了通知（`didUpdateNotificationStateFor` → 0xA0）。今は固定時間待つ。
8. ADV report に service UUID を載せること、または `peripheral.name` に fallback すること（名前が ADV に無い機種への保険）。
9. notify の 255 byte 上限（Phomemo のステータス通知は短いはずなので影響は小さい見込み。未検証）。

※ 1〜5 は、新しい mrbgem の側からは**足せない**。`PBLECentral` は Swift モジュールの internal な `final class` で、`peripheral` も private（`PicoBLECentral.swift:50, 69-70`）だからだ。選択肢は次の 3 つ。
- (A) picoruby-ble をそのまま使う。チャンクを決め打ちし、sleep で間隔を空け、切断は自前で判定する。
- (B) bash0C7/picoruby の `port-darwin` 側の Swift・C・Ruby バインディングに API を足す。
- (C) 新しい gem が自前の CoreBluetooth バックエンドを持ち、picoruby-ble を使わない。

---

## 9. 実装時に罠になりそうな点

1. **TCC**: `build/host/bin/picoruby` を直接実行すると SIGABRT するという報告がある。`.app` 化と Info.plist、さらに `codesign -s - -r='designated => identifier "<bundle id>"'` で requirement を固定する（これをしないと再ビルドのたびに許可が消え、ダイアログ待ちで scan が黙って空振りする）。起動は `open -W -a <app> --stdout/--stderr --env --args <絶対パス>` で、stdout は `--stdout` でファイルに出す。対話 CLI にするなら、`open` 経由で標準入出力がどうなるかを要検討（stackchan は CLI と daemon に分け、daemon だけを launchd から起動して回避している）。
2. **`hal-task-darwin` を入れ忘れる**: R2P2-darwin の BLE 設定には入っていない。入れないと、CoreBluetooth のスレッドに SIGALRM が届いて、まれに `mrb_task_queue_push` が無限ループする（stackchan で daemon が固まった事例。e2783d02 のメッセージ）。
3. **`scan` の後に `scan` や `start` を呼ばない**: 接続が cancel される（§3.6）。購読・write・notify 待ちは、`scan(stop_state: :TC_IDLE)` が戻った後に `pop_and_dispatch` と `sleep_ms` を自前でループする（stackchan・e2e と同じ方式）。もう一つは `scan(stop_state: :no_stop)` の中から `packet_callback` と `heartbeat_callback` で駆動する方式（ble-subscribe・central_paths_probe）。ただしこちらは heartbeat が 1 秒ごとなので、ペーシングの制御が粗い。
4. **`connect` は `advertising_report_callback` の中でしか呼べない**。`scan` には必ず `timeout_ms` を付ける（接続の失敗も切断も decoder に届かないので、timeout が無いと戻らない）。
5. **write は黙って失敗する**: `rc` は常に 0。handle を間違えても、未接続でも何も起きない。発見後に `services` から uuid128 で value handle を確実に引き、`@conn_handle != HCI_CON_HANDLE_INVALID` を確認する。
6. **チャンク長とペーシング**: 最大長が取れないので決め打ちになる。ATT の既定 MTU 23 なら 20 byte が安全な最小値。180 byte（stackchan の実績値）が Phomemo で通るかは未検証。1 チャンクずつ `sleep_ms` を挟む（例: 20ms）。間を空けないと `canSendWriteWithoutResponse == false` の間に投げた write は best-effort になる。プリンタ側のバッファ溢れ対策としても間隔は要る。スループットは「チャンク長 / 間隔」で決まり、20 byte・20ms なら約 1 KB/s（数十 KB で数十秒）、180 byte・20ms なら約 9 KB/s。1 回の write に 64 KB 以上を渡すと uint16 で切り詰められる。
7. **CCCD の購読は完了が通知されない**: 書いた後 200ms〜1s ほど drain しながら待ってから write を始める。
8. **notify は自前で decode する**: `packet_callback` で `super` の後に 0xA7 を見る。値の長さは offset 10 の LE16、本体は offset 12 から。255 byte を超えると切り詰められる。
9. **切断の検知は `[0x3E,0x01,0x05]` を自前で見る**（stackchan の `disconnect_packet?` と同じ）。
10. **UUID は uuid128 で照合する**。16bit UUID を 128bit の canonical（big-endian）に直して比べる（`central_paths_probe.rb:36-49` や `stackchan gatt.rb` の書き方）。
11. **発見で全部を read する**: 読める characteristic と descriptor を全部読むので、発見に時間がかかる。読むと副作用が出る characteristic があると困る（Phomemo にあるかは未確認）。
12. **名前で絞る**: ADV report には service UUID が載らない。local name が ADV に無い機種はマッチしない。`peripheral.name` への fallback も無い。
13. **CoreBluetooth の GATT キャッシュ**: アドレスごとに GATT をキャッシュするので、古い characteristic が見えることがある（`esp32_dynamic_read_test.rb:43-48` のコメント）。
14. **共通コードが動いている最中**: worktree の `codex/pr427-common-proposals` で、`ble.rb` の `start`、`BLE_push_event` の戻り値、`initialize` が書き換えられつつある。`@event_queue` や `_event_popped` に直接触る `pop_and_dispatch` のようなコードは、これが入ると壊れる可能性がある。
15. **Swift の PATH**: swiftly の swift が先に来るとビルドが失敗する。
16. **ログの出し方**: `debug_puts` は `STDOUT.puts`。`open -a` で起動したときは `--stdout` で指定したファイルにしか出ない。

---

## 付録: 参照したパス

- `~/ghq/github.com/bash0C7/picoruby`（`origin/port-darwin` 31de5488 を `git show` / `git archive` で読んだ）
- 展開したコピー: `<scratchpad>/pd/mrbgems/picoruby-ble/`
- mruby-task（submodule 7b4e0f3b、port-darwin のポインタと一致）: `~/ghq/github.com/bash0C7/picoruby/mrbgems/picoruby-mruby/lib/mruby/mrbgems/mruby-task/src/task.c`
- `~/ghq/github.com/bash0C7/R2P2-darwin`（main 08986d9）
- `~/ghq/github.com/bash0C7/stackchan-picoruby`（main 9fac444）
- SDK ヘッダ: `$(xcrun --show-sdk-path)/System/Library/Frameworks/CoreBluetooth.framework/Headers/CBPeripheral.h`
