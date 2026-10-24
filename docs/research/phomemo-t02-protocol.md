> 2026-10-24 の調査報告の写し。`<scratchpad>/research/src/` は調査時に一時領域へ clone した repo 群を指す。一時領域は揮発するので、元のソースを見るときは §1 の repo URL と commit SHA から取り直すこと。

# Phomemo T02 BLE 直接制御プロトコル仕様書（調査版）

- 作成日: 2026-10-24
- 対象機: Phomemo T02（53 mm 幅感熱紙のミニプリンタ。Amazon B0CM6H6YWN）
- 目的: 別の実装者がこの文書だけを見て mruby で BLE ドライバを書けるようにする
- 方針: 値はすべて公開実装のソースから転記した。推測で埋めた箇所は「推測」と書く。分からない箇所は「不明」と書く
- 取得したソースは 調査時に clone した repo 群（一時領域 `<scratchpad>/research/src/`。この repo には写していない。§1 の URL と commit SHA から取り直せる） 以下にある（読んだだけで、実行・ビルド・インストールはしていない）

---

## 0. 凡例

### 0.1 確度ラベル

| ラベル | 意味 |
|---|---|
| **N 実装で一致** | 独立した N 個の実装で同じ値。派生コード（コピー）は 1 と数える |
| **1 実装のみ** | 1 つの実装にしか根拠がない |
| **推測** | ソースに直接の記述はなく、複数の記述から筆者が導いた |
| **実機** | その実装が「実機で確認した」とコードかドキュメントに明記している（ラベルに付記する） |
| **兄弟機** | 根拠が T02 ではなく M02 / M02S / M02 Pro / M02X / M08F の実装にしかない |

### 0.2 出典の書き方

`[ID] パス#L開始-L終了` と書く。ID と repo URL・commit SHA の対応は §1 の表にある。GitHub の固定リンクは `https://github.com/<repo>/blob/<SHA>/<パス>#L<開始>-L<終了>` で組み立てられる。

### 0.3 バイト列の書き方

16 進を空白区切りで書く（例: `1b 40`）。多バイト整数はすべてリトルエンディアン（LE）。

---

## 1. 調査した実装

### 1.1 T02 を明示的にサポートする実装

| ID | repo（URL） | commit SHA | 日付 | 言語 / 経路 | 実機確認の記載 | 読んだ範囲 |
|---|---|---|---|---|---|---|
| HA | https://github.com/alexduboiz/ha-phomemo-t02 | 5d9f3f9ea29c64815d69d5e4665814aae855ef82 | 2026-09-06 | Python / bleak / **BLE** | あり（`docs/protocol.md` 冒頭「measured against a physical T02」） | protocol.md, const.py, protocol.py, printer.py, coordinator.py, tests/test_protocol.py, tools/print_test.py, CLAUDE.md, README は全行。config_flow.py は該当部 |
| LNX | https://github.com/mzramna/phomemo-t02-linux | 7a7870f2a0f96acd221408644c330d7c52564529 | 2026-09-25 | Python / bleak + 生 ATT（L2CAP）/ **BLE** | 明記なし（README とコードから実機で使っているのは明らか） | `t02`（708 行）、`cups/t02-backend`、README は全行 |
| PMY | https://github.com/transcriptionstream/phomymo | 1f58d3f0e7f941b9143277cda828380149e56855 | 2026-05-17 | JS / Web Bluetooth / **BLE** | T02 の幅を 54→48 byte に直したコミット 7f1db83（利用者 Alec Holmes）あり | ble.js, printer.js, constants.js, printers.json は全行。canvas.js と app.js は該当部 |
| TIM | https://github.com/Dejniel/TiMini-Print | 95beec7ba0f6422c29fd480ca262e369caf5e375 | 2026-10-20 | Python / BLE + SPP | T02 の実機確認の記載なし（データの `origin_ids` は Phomemo アプリ `com.quyin.phomemo`） | phomemo_esc/*.py と runtime/phomemo*.py は全行。bitmap.py, bluetooth_profiles.py, printer_models*.json, printer_profiles.json, テストは該当部 |
| JPR | https://github.com/jpurnell/T02Protocol | 76b51082308e0add9b4338a0f279e68a2eeb172f | 2025-11-10 | Swift / CoreBluetooth（BLE）+ IOBluetooth RFCOMM + シリアル | 明記なし | Sources 以下と README、t02-print は全行 |
| M5 | https://github.com/otitbridge/m5stick-s3-qr-phomemo | b1a3b758f2dda6b9a82a1b678a60063b058c2cf5 | 2026-05-25 | C++ / ESP32-S3 / NimBLE-Arduino 1.4.3 / **BLE** | あり（HANDOVER.md §6.6「同一プリンタで検証済み」） | main.cpp のプリンタ部（L1-365）全行と残りは該当部、HANDOVER.md 全行 |
| JEF | https://github.com/jeffrafter/phomemo | 972f887db835b1437b6a60e6cec2eb6251fb8a7d | 2025-10-10 | Swift / CoreBluetooth / **BLE** | あり（README に T02 実機の通知ログ） | README, scanner.swift, phomemo.swift, main.swift は全行。phomemo_image.swift は L30-122 |
| TAG | https://github.com/iraum/tagline | f87d12bb6bba6bbfe29c70baaba8f2ef12491e9e | 2026-09-17 | Python / **Classic RFCOMM** | あり（README「Printer notes」は観測値） | t02_print.py, README, CLAUDE.md は全行。server.py は L55-140 |
| ESP | https://github.com/iamjackg/esp32-phomemo-gameboy-printer | acfd698706fe750c6c1046197b5d7f4bde1a3927 | 2021-11-25 | C++ / ESP32 BluetoothSerial / **Classic SPP** | 実機で動かすプロジェクト | main.cpp, GBPrinter.h, README は全行 |
| VIV | https://github.com/vivier/phomemo-tools | 2b767486d4590676f1ffb61c7ca870984978a980 | 2026-10-18 | Python / CUPS / **Classic RFCOMM** + USB | README「Android アプリの Bluetooth パケットを sniff した」 | README, cups/backend/phomemo.py, cups/filter/rastertopm02_t02.py, cups/drv/phomemo-m02_t02.drv, tools/*.py は全行。git 履歴も確認 |
| MDS | https://github.com/matheusdanoite/Phomemo-Swift | 10007f07be6a2368e6d0cb279a23fa696326d98e | 2026-02-16 | Swift / CoreBluetooth / **BLE** | 明記なし | PhomemoCommands, PhomemoDriver, PhomemoImageProcessor は全行 |
| MDA | https://github.com/matheusdanoite/Phomemo-T02-for-Apple | 0629df8ad9c960f8b9b6bf9333a8417d4763beb1 | 2026-02-22 | Swift / CoreBluetooth / **BLE** | 明記なし | iOSApp/PrinterProtocol.swift, iOSApp/BluetoothManager.swift は全行 |
| MDM | https://github.com/matheusdanoite/Phomemo-T02-Driver-for-macOS | 2e59553beadc8e0a6b6b056a1325ec86e1539073 | 2026-02-16 | Python / bleak / **BLE** | README「Status Codes (Dev Notes)」は観測値 | print_phomemo.py, check_status.py, scan_phomemo.py は全行。README は該当部 |
| BEN | https://github.com/benhughes/phomemo-t02 | b2c58d568e79acd90364a1a6a9733a0d8235f0ad | 2026-04-25 | Python / macOS IOBluetooth / **Classic RFCOMM** | 明記なし | 2 ファイル全行 |
| WIN | https://github.com/yo5ptd/phomemowin | f2c1b087ae4dd2d90b1e72d4a4cf1c23ac1d93ad | 2026-09-23 | Python / **USB シリアル（COM3）** | 明記なし | usbprint_t02.py 全行、pdf 版は差分のみ |
| BRU | https://github.com/brunetton/Print-with-Phomemo-T02 | 80a3e3bc999f04e39e1dc15babf66d4a483c7bf2 | 2025-10-17 | Bash（VIV の tools/phomemo-filter.py を rfcomm に流すだけ） | 利用報告のみ | 全行 |
| FCO | https://github.com/fcontr1975/phomemo-T02-CUPS-driver | 993ff4ab73a54e986451e389667f722b2f0c89c5 | 2026-05-15 | VIV の派生（filter と drv は VIV と完全一致、backend は再接続処理を追加） | `scripts/error-logs.txt` に T02 実機の `bluetoothctl info` | VIV との diff と error-logs.txt |

> **独立性の注意**: FCO と BRU は VIV の派生なので数に入れない。MDS・MDA・MDM は同じ著者（matheusdanoite）なので、著者別に数えると 1 になる。BEN、JEF、WIN、LNX、M5 の一部の値（ヘッダ／フッタ／0x0a 置換）は VIV の README や `tools/phomemo-filter.py` からの転記である。「N 実装で一致」は送信方法・待ち時間・実機ログのように各自が独立に決めた（あるいは観測した）値を中心に数えている。

### 1.2 兄弟機の実装（T02 と同系統の M02 ファミリ）

| ID | repo | commit SHA | 機種 / 経路 | 主な根拠 |
|---|---|---|---|---|
| S04 | https://github.com/s04/phomemo | 80d1d355c2f2157ec30f627899e513fecc4a9ce9 | M02 Pro / BLE | `PROTOCOL.md` 全行（「verified on a real M02 Pro (firmware 2.0.6)」） |
| SGR | https://github.com/sgrankin/phomemo | a626a07385c95b6017053991d70eaf74d64a9d9f | M02X / BLE（iOS PacketLogger で確認） | `PROTOCOL.md` 全行、`printer/printer.go` は該当部 |
| SHI | https://github.com/shiruku-shibata/Phomemo-Print | 856da919534d44a2ced8e46e4eff57f3d498bbfc | M02 / BLE（macOS） | `docs/device-notes.md`（実機の GATT ダンプ）、protocol.py, ble.py は全行 |
| THEA | https://github.com/theacodes/phomemo_m02s | dbe985f8f4e8f6a55c42d70e78e6cf865358e724 | M02S / RFCOMM | printer.py, _image_helper.py, README は全行（Android アプリ `PrinterUtils.java` の順に並べたコマンド群） |
| GBL | https://github.com/gbl/phomemo | bbac675072839008cec1b2d6bba25c5b2616c4e1 | M02S / USB・RFCOMM | `phomemo`, `phomemo-status`, README は全行 |
| RYO | https://github.com/ryo-endo/phomemo-printer | dc8d6ef725b8c6fb98447d705249acd0458eafea | M02 Pro / BLE | 全行 |
| AIN | https://github.com/ainehanta/phomemo-ble-rs | 225e26fd5c7b6e98a1824ca44b9660526ef02fb9 | 機種名なし（384 px）/ BLE | `src/lib.rs` 全行 |
| PSB | https://github.com/PassionateBytes/phomemo | 9d248b8b896b900195d5399297bd162ed32df345 | M08F（A4 機）/ BLE | `docs/m08f-protocol-reference.md` の該当部 |
| K0I | https://github.com/K0IN/Phomemo-M02-Web | 3c0972d0b5b978baea7cbfbc8399398fc5b6a665 | M02 / Web Serial（SPP） | `src/logic/phomemo.ts` 全行 |
| VRK | https://github.com/vrk/cli-phomemo-printer | ef1f841072a39004737c8afce630315607ae5409 | M02S / BLE（noble） | `index.js` の主要部 |
| UNX | https://github.com/unixway/phomemo-print | 93fea70649042e61aa67c507eaefd3b538e8d1ad | M02 Pro / RFCOMM | `src/print/*.rs` 全行 |
| HKW | https://github.com/hkeward/phomemo_printer | 086ee95bd0e451827548f51da31585099cf838fb | M02 Pro / RFCOMM | `ESCPOS_constants.py` 全行、`ESCPOS_printer.py` は該当部 |

grep で見ただけで新しい情報がなかったもの: Knightro63/phomemo（1c015d717890844470e1880d631c0f04c2478a51、Dart、M02 は VIV と同じ列）、davestewart/phomemo-cli（4a9b4fb2e75678f13eaaaac3146da81819edcf5f、VRK と同じ列）、Tomatio13/phomemo-printer-skill（a76cda4d5af397a65b7324bc8f1137b5a773dcbe、HKW を包んでいる）、mkuhlmann/pyphomemo（09617e35d3f98822c7a1bf24ac97dce63d2a863e、M110 専用。T02 は「未対応」として登録だけ `src/pyphomemo/models.py#L47`）。

---

## 2. プロトコル系統の区別（cat printer との混同注意）

| 系統 | 見分け方 | T02 との関係 | 出典 |
|---|---|---|---|
| **Phomemo ESC/POS 系**（本書の対象） | GATT サービス `0xff00`、書き込み `0xff02`。コマンドは ESC/POS 風（`1b 40`, `1d 76 30 …`, `1b 64 n`）と独自の `1f 11 xx` | Phomemo T02 はこれ | HA, LNX, PMY, TIM, M5, JEF, MDS, MDA, MDM ほか |
| **"cat printer" 系**（`0x51 0x78` フレーム） | `51 78 <cmd> 00 <lenL> <lenH> <payload> <crc8> ff`。サービスは `0xae30` などが多い | **別物**。M02X に `0x51 0x78 …` を送っても「何の応答もない」 | フレーム形式: [TIM] `timiniprint/protocol/packet.py#L91-100`。M02X での不応答: [SGR] `PROTOCOL.md#L301` |
| **Funny Print LX 系で名前が "T02" の別機種** | BLE 名が同じ `T02` でも、サービス `0xffe6`、書き込み `0xffe1`、通知 `0xffe2` | **別ベンダの機械が同じ名前を名乗る**。TiMini は名前 `T02` だけでは機種を決めない | 名前: [TIM] `timiniprint/data/printer_models_unsupported.json#L2716-2733`（`unsupported_funny_lx_type1`、名前 `TD-11308`, `T02`, `ZH-P06`, `LX-D002`、アプリ `com.lailaixiong.funnyprint`）。同名の扱い: [TIM] `timiniprint/data/printer_models.json#L2370-2388`（`detection_ambiguity_group: "t02_protocol"`）。UUID: [TIM] `timiniprint/devices/bluetooth_profiles.py#L104-110` |

補足:
- JEF の README は T02 を「"Cat printer"」と呼んでいる（`README.md#L3`）。`phomemo.swift` には `51 78` フレームを作る関数 `formatMessage` があるが、どこからも呼ばれていない（`Phomemo/phomemo.swift#L217-240`）。実際の印字は ESC/POS 系で送っている。
- 名前が `T02` でサービス `0xff00` がない機械は、別系統の可能性がある（**推測**。TIM の上記データから導いた）。接続後に `0xff00` / `0xff02` が見つかるかで判定するのが確実。

---

## 3. 最短の結論（実装者向けの要約）

| 項目 | 値 | 確度 |
|---|---|---|
| アドバタイズ名 | `T02` | 6 実装で一致（HA 実機, JEF 実機ログ, FCO 実機, VIV, ESP, TAG） |
| GATT サービス | `0000ff00-0000-1000-8000-00805f9b34fb` | 9 実装で一致（著者別 7。HA 実機, JEF 実機ログ ほか） |
| 書き込み characteristic | `0000ff02-0000-1000-8000-00805f9b34fb`（write と write without response の両方に対応） | 9 実装で一致（著者別 7）。プロパティは HA と JEF が実機で確認 |
| 通知 characteristic | `0000ff03-0000-1000-8000-00805f9b34fb`（notify） | 7 実装で一致（著者別 6。HA 実機, JEF 実機ログ ほか） |
| 1 行 | 384 dot = 48 byte、203 dpi（8 dot/mm）、MSB が左端、ビット 1 = 黒 | 全実装で一致（HA は実機テスト付き） |
| 画像コマンド | `1d 76 30 00 30 00 yL yH` + 48×y byte | 全 BLE 実装で一致 |
| 1 ブロックの行数 | 255 行以下（HA が実機で確認）。255 を超える 1 ブロック送信は競合（§8.5） | 5 実装で一致（≤255） |
| 実機で動いた最小手順 | `1b 40` → `1b 61 00` → ラスタブロック → `1b 64 03` | HA 実機（`tests/test_protocol.py#L55-68` がその時のバイト列） |
| チャンクと間隔 | 197 byte / 10 ms（HA 実機）、128 byte / 20 ms（PMY, TIM, LNX）、128 byte・応答付き（M5 実機） | §6 |
| 印字後 | すぐ切断しない。1.5〜2 s 以上待つか、`1a 0f 0c`（印字完了）を待つ | 6 実装で一致（§12） |
| ステータス | 問い合わせ `1f 11 xx`、応答は `ff03` に `1a <種別> <値…>` | §11 |

---

## 4. デバイス発見（アドバタイズ）

### 4.1 名前

| 項目 | 値 | 出典 | 確度 |
|---|---|---|---|
| ローカル名 | `T02` | [HA] `docs/protocol.md#L7-13`（「Advertised local name `T02`」）、[HA] `custom_components/phomemo_t02/const.py#L19-21`, `manifest.json#L12-16`（`"local_name": "T02"`）、[JEF] `README.md#L29-34`（スキャン結果 `Discovered: T02`）、[FCO] `scripts/error-logs.txt#L36`（`Name: T02`）、[VIV] `cups/backend/phomemo.py#L38-39`（`name == 'T02'`）、[ESP] `src/main.cpp#L93`（`SerialBT.connect("T02")`）、[TAG] `README.md#L24` | 6 実装で一致（うち実機 3） |
| 名前の照合方法 | 前方一致 `startswith("T02")`（HA, LNX）、部分一致 `contains("T02")`（JPR, MDS, MDM）、完全一致（JEF の Scanner, VIV, TIM） | [HA] `config_flow.py#L39-40`、[LNX] `t02#L192-195`, `L477-478`（`"T02"` と `"Mr.in"` の前方一致）、[JPR] `Sources/T02PrintTool/CoreBluetoothConnection.swift#L97`（`"T02"` か `"PHOMEMO"` を含む）、[TIM] `printer_models.json#L2377-2383` | 実装ごとに異なる |
| 同系列の別名 | `T02E`, `C02E`（TIM が T02 の互換機として扱う名前） | [TIM] `README.md#L175`, `printer_models.json#L2377-2383` | 1 実装のみ（実機確認なし） |
| 兄弟機の名前 | M02 は `Mr.in_M02`（[VIV] `README.md#L24`、[SHI] `docs/device-notes.md#L9`）、M02 Pro は `M02 Pro`（[S04] `PROTOCOL.md#L9`） | — | 兄弟機 |

### 4.2 アドバタイズされるサービス UUID（**実装間で食い違う**）

| 観測 | 出典 | 確度 |
|---|---|---|
| T02 は `0xAF30` と `0x1812`（Human Interface Device）を広告し、`0xff00` は広告しない | [JEF] `README.md#L29-34`（スキャナの出力 `└── AF30 …`, `└── Human Interface Device (UUID: 00001812-…`） | 1 実装のみ（実機ログ） |
| `0xAF30` を「広告されるサービス」としてスキャンフィルタに使い、接続後に `0xFF00` を使う | [MDA] `iOSApp/BluetoothManager.swift#L25-27`, `L194-206` | 1 実装（T02） |
| `0xAF30` でスキャンし `0xFF00` に接続（機種名なし、384 px） | [AIN] `src/lib.rs#L14-15`, `L31-44` | 兄弟機 |
| M02 も `af30` と `1812` を広告し、`ff00` は広告しない | [SHI] `docs/device-notes.md#L10` | 兄弟機（実機） |
| T02 の `bluetoothctl info` に UUID `00001101`（Serial Port）、`00001800`、`0000af30`、`0000ff00` が並ぶ（BlueZ は広告と GATT/SDP の結果を合わせて表示する） | [FCO] `scripts/error-logs.txt#L47-50` | 1 実装（実機） |
| **T02 は広告にサービス UUID を何も載せない**。「`ff00` を広告しないので service_uuid での照合は動かない」 | [HA] `docs/protocol.md#L13-17` | 1 実装（実機、Windows + bleak） |

結論: T02 が `0xff00` を広告しないことは JEF と HA が観測している（M02 の SHI も同じ）。FCO の一覧に `ff00` があるのは、BlueZ が GATT 探索の結果も合わせて表示するためと思われる（**推測**。HA の GATT ダンプに `ff00` はあるが `af30` はない: `docs/protocol.md#L24-31`）。`0xaf30` が広告されるかは観測が割れている（JEF・FCO・M02 の SHI は見えた、HA は見えなかった）。名前 `T02` で探すのが最も多数派（§4.1）。

### 4.3 そのほかのアドバタイズ内容（T02 実機、[FCO] `scripts/error-logs.txt#L33-58`）

```
Device C3:2D:F8:47:52:65 (public)
	Name: T02
	Alias: T02
	Class: 0x00100680 (1050240)
	Icon: printer
	...
	UUID: Serial Port               (00001101-0000-1000-8000-00805f9b34fb)
	UUID: Generic Access Profile    (00001800-0000-1000-8000-00805f9b34fb)
	UUID: Unknown                   (0000af30-0000-1000-8000-00805f9b34fb)
	UUID: Unknown                   (0000ff00-0000-1000-8000-00805f9b34fb)
	ManufacturerData.Key: 0x0000 (0)
	ManufacturerData.Value:
  c3 2d f8 47 52 65                                .-.GRe
	ManufacturerData.Key: 0x7262 (29282)
	ManufacturerData.Value:
  32 32 78 78 11 22 33 44 55 66 aa bb 00 00        22xx."3DUf....
	AdvertisingFlags:
  06                                               .
```

- Manufacturer Data のキー `0x0000` の値は、そのデバイスの MAC アドレス（`C3:2D:F8:47:52:65`）と同じ 6 byte である（上のログから読める事実）。M02 でも `manufacturer 0x0000: d1 16 a7 ac 00 7c` が観測されている（[SHI] `docs/device-notes.md#L10`）。
- `Class: 0x00100680` は Classic Bluetooth の Class of Device（プリンタ）。Classic 側の SPP（`0x1101`）があることと合わせ、T02 は Classic と BLE の両方を持つ機械である（§14 参照）。
- 個体の BLE アドレス例: `9C:A8:02:DB:13:95`（[HA] `docs/protocol.md#L12`）、`C3:2D:F8:47:52:65`（[FCO]）、`33:E5:E6:87:AC:7C`（[TAG] `t02_print.py#L9`）、`78:09:32:74:35:ed`（[BEN] `bt_send.py#L12`）。

### 4.4 ペアリングと接続の条件

| 項目 | 内容 | 出典 | 確度 |
|---|---|---|---|
| 書き込みにペアリングは要るか | **要らない**。BLE 接続だけで `ff02` に書ける | [JEF] `README.md#L119`（「the connection is sufficient to _write_ to the write characteristic」）、[HA] はペアリング処理を持たずに印字成功 | 2 実装で一致（実機） |
| 通知（notify）にペアリングは要るか | macOS では**要る**。ペアリングしないと `Notify failed: Encryption is insufficient.` になる | [JEF] `README.md#L110-131`, `Phomemo/phomemo.swift#L85-98` | 1 実装のみ（macOS 実機）。他 OS では不明（HA は Windows で通知を受けているが、ペアリングの有無は書いていない） |
| 同時接続数 | 1 台だけ。公式アプリなど他の接続を切る必要がある | [JEF] `README.md#L108`、[LNX] `README.md#L78` | 2 実装で一致 |
| 広告の時間 | 電源が入っている間だけ広告し、自動スリープするとスキャンに出なくなる | [HA] `docs/protocol.md#L19-20`, `CLAUDE.md#L144-147` | 1 実装（実機） |
| 〃 | 「電源投入後 30 秒以内（BLE 広告期間）」に使う必要がある | [JPR] `README.md#L69` | 1 実装のみ。HA の記述と食い違う |
| ハードリセット | ボタン 20 秒長押しで点滅するまで → リセット。その後 3 秒長押しで接続モード | [JEF] `README.md#L106` | 1 実装のみ |
| Linux の注意 | 切断後 `bluetoothctl disconnect <MAC>` しないと BlueZ が LE 接続を握ったままになり、T02 が再び広告しない | [LNX] `t02#L593-596`, `L650` | 1 実装のみ |
| Linux の注意 | `ProfileUnavailable` が出たら古い bond を削除して再スキャン | [LNX] `README.md#L71-76`, `t02#L499-508` | 1 実装のみ |
| macOS の注意 | アドレスは MAC ではなくホストごとの UUID。名前で照合する | [SGR] `PROTOCOL.md#L31-36`、[SHI] `src/phomemo/ble.py#L1-5` | 兄弟機 2 実装 |

---

## 5. GATT

### 5.1 サービスと characteristic

| UUID | プロパティ | 用途 | 出典 | 確度 |
|---|---|---|---|---|
| サービス `0000ff00-0000-1000-8000-00805f9b34fb` | — | 印字用ベンダサービス | [HA] `docs/protocol.md#L24-31`, `const.py#L15`、[LNX] `t02#L22`、[PMY] `src/web/constants.js#L113`、[M5] `src/main.cpp#L34`、[MDA] `iOSApp/BluetoothManager.swift#L26`、[MDS] `PhomemoCommands.swift#L30`、[MDM] `README.md#L73`、[JEF] `README.md#L48`、[TIM] `bluetooth_profiles.py#L77-83` | 9 実装で一致（著者別 7。HA・JEF は実機ダンプ） |
| `0000ff01-0000-1000-8000-00805f9b34fb` | **read**（HA と JEF の実機ダンプ）／ **notify**（LNX） | 不明（読み出し値は空 `b''`: M02 の実機 [SHI]） | read: [HA] `docs/protocol.md#L28`、[JEF] `README.md#L50-51`（`Char FF01 properties: 2`）、[SHI] `docs/device-notes.md#L16`, `L24`（M02）、[S04] `PROTOCOL.md#L15`（M02 Pro）。notify: [LNX] `t02#L338-340`（CCCD `0x0024` を「ff01 (status/notify)」とする）、`README.md#L83` | 食い違い（§16） |
| `0000ff02-0000-1000-8000-00805f9b34fb` | **write** と **write-without-response** | ホスト → プリンタの全データ（コマンドも画像も） | [HA] `docs/protocol.md#L29`（`['write', 'write-without-response']`）、[JEF] `README.md#L52`（`Char FF02 properties: 12` = 0x04 + 0x08）、[HA] `const.py#L16`、[LNX] `t02#L21`、[PMY] `constants.js#L114`、[M5] `main.cpp#L35`、[MDA] `BluetoothManager.swift#L27`、[MDS] `PhomemoCommands.swift#L31`、[MDM] `print_phomemo.py#L16` | 9 実装で一致（著者別 7。プロパティは 2 実装が実機で確認） |
| `0000ff03-0000-1000-8000-00805f9b34fb` | **notify**（CCCD `0x2902` あり） | プリンタ → ホストの応答とイベント | [HA] `docs/protocol.md#L30`、[JEF] `README.md#L53-54`（`Char FF03 properties: 16`）、[HA] `const.py#L17`、[PMY] `constants.js#L115`、[M5] `main.cpp#L36`, `L140-144`、[MDS] `PhomemoCommands.swift#L32`、[MDM] `print_phomemo.py#L17` | 7 実装で一致（著者別 6。2 実装が実機で確認） |
| `00001800-0000-1000-8000-00805f9b34fb`（GAP） | `2a00` read | 標準 | [HA] `docs/protocol.md#L25-26` | 1 実装（実機） |

**`ff00` 以外のサービス**: JEF の `PhomemoWriter` は `0x1812` でスキャンして接続し、「サービスは 1 つだけ（FF00）」として最初のサービスを使う（[JEF] `Phomemo/phomemo.swift#L10`, `L43-51`）。JEF の環境で接続後に見えたサービスは `FF00` 1 つだけだった（JEF の出力 `Did discover service [<CBService … UUID = FF00>]`、`README.md#L48`）。広告にある `0x1812` が見えない理由は書かれていない（CoreBluetooth がアプリから HID サービスを隠すためと思われる: **推測**）。

### 5.2 ATT ハンドル（参考。固定値として使わないこと）

| ハンドル | 中身 | 出典 |
|---|---|---|
| `0x0025` | `ff02` の characteristic 宣言 | [LNX] `t02#L338-339`（Read By Type が失敗したときの予備値） |
| `0x0026` | `ff02` の値ハンドル（ここに Write Command `0x52` で書く） | 同上 |
| `0x0027` / `0x0028` | `ff03` の宣言 / 値 | 同上 |
| `0x0024` / `0x0029` | CCCD（`ff01` 用 / `ff03` 用）。`01 00` を書くと通知が有効になる | [LNX] `t02#L340`, `L389-391`, `L409-414` |

M02X では書き込みと通知がハンドル `0x0008` / `0x000a` にある（[SGR] `PROTOCOL.md#L316-317`）。機種や個体でハンドルは変わるので、GATT 探索で UUID から引くこと（**推測**。上の 2 例が違うことからの判断）。

### 5.3 write の種類

| 方式 | 使っている実装 | 出典 |
|---|---|---|
| write without response（ATT Write Command `0x52`） | HA（対応していれば）、LNX、PMY（既定。失敗したら with response に切り替え）、MDS、MDA（対応していれば）、MDM、JEF | [HA] `printer.py#L171`, `L187-189`、[LNX] `t02#L563`, `L582`, `L419`、[PMY] `src/web/ble.js#L302-306`, `L373-385`、[MDS] `PhomemoDriver.swift#L112`、[MDA] `BluetoothManager.swift#L304`、[MDM] `print_phomemo.py#L212`、[JEF] `phomemo.swift#L201`, `L207` |
| write with response（ATT Write Request `0x12`） | M5（NimBLE `writeValue(data, n, true)`）、JPR（`.write` があればそちらを優先） | [M5] `src/main.cpp#L83`、[JPR] `CoreBluetoothConnection.swift#L209-210` |

確度: 両方式とも T02 で動いた報告がある（HA = without、M5 = with、どちらも実機）。兄弟機 M02X では「Write Request は長いラスタの途中で止まった」「Write Without Response を使え」とある（[SGR] `PROTOCOL.md#L38-41`）。一方で同じ文書の表は「M02 family: Write Request (`0x12`)」と書いていて（`PROTOCOL.md#L210`）、文書内でも揺れている。

---

## 6. 転送（チャンク・間隔・MTU・フロー制御）

### 6.1 MTU

| 観測 | 出典 | 確度 |
|---|---|---|
| T02、Windows のローカルアダプタで **MTU 200**（書き込み 1 回 197 byte） | [HA] `docs/protocol.md#L33-34`, `const.py#L38-41` | 1 実装（実機） |
| M02、macOS で `max_write_without_response_size` = **197** | [SHI] `docs/device-notes.md#L15-25` | 兄弟機（実機） |
| macOS では MTU 185 → 182 byte。M02X では 182 を超えると（例 194）黙って落ちる | [SGR] `PROTOCOL.md#L43-46`、`printer/printer.go#L89-95` | 兄弟機 |
| 接続直後に `ff03` へ `02 b6 00` が来る（`0x00b6` = 182） | T02: [JEF] `README.md#L60-61`（`-- : [2, 182, 0]`）。M02: [SHI] `docs/device-notes.md#L21`。M02 Pro: [S04] `PROTOCOL.md#L40`（「probably the maximum packet size (0xB6 = 182)」） | 3 実装で観測が一致（意味は推測） |
| 同じ形の M08F の通知 `02 f4 00`（= 244）は MTU 247 − 3 と一致する | [PSB] `docs/m08f-protocol-reference.md#L133-136` | 兄弟機。`02 b6 00` を「1 回の最大書き込み長 182」と読む根拠（**推測**） |
| 要求 MTU: LNX は 185、M5 は 517 | [LNX] `t02#L383`、[M5] `src/main.cpp#L543` | — |

### 6.2 チャンク長と間隔（実装ごと）

| 実装 | 1 回の書き込み長 | 間隔 | 備考 | 出典 |
|---|---|---|---|---|
| HA（実機） | `max(20, min(197, mtu − 3))` | 10 ms | 11,536 byte を 59 回、0.91 s、12.37 KB/s で送れた。設定範囲はチャンク 20〜512、間隔 0〜200 ms | [HA] `printer.py#L34`, `L172-191`、`docs/protocol.md#L79-84`、`config_flow.py#L161-176` |
| LNX | `min(mtu − 3, 128)` | 20 ms | 生 ATT モードは `mtu − 3`、20 ms | [LNX] `t02#L580-583`, `L415-420` |
| PMY | 128 | 20 ms | 送信前後にも待ち（§7.2） | [PMY] `src/web/constants.js#L124-125`, `src/web/printer.js#L976-989` |
| TIM | 128 | 20 ms | | [TIM] `printer_profiles.json#L6495-6498`, `bluetooth_profiles.py#L77-83` |
| M5（実機） | `min(mtu − 3, 128)`（with response） | 行ごとの送信のあと 5 ms、初期化コマンドのあと 50 ms | 1 行ずつ `GS v 0` を送る | [M5] `src/main.cpp#L76-89`, `L251-258`, `L268-283`, `L348-364` |
| MDA | `maximumWriteValueLength(for:)` | 20 ms | | [MDA] `BluetoothManager.swift#L304-318` |
| JPR | 20 | 50 ms | 「20 bytes recommended」「Wait 50ms between chunks」 | [JPR] `CoreBluetoothConnection.swift#L215-234`, `README.md#L293-294` |
| MDS / MDM | 1 ブロック（ヘッダ 8 + 100 行 × 48 = 4,808 byte）を 1 回で | 40 ms | OS の分割に任せている | [MDS] `PhomemoDriver.swift#L83-87`, `PhomemoImageProcessor.swift#L24`, `L78-90`、[MDM] `print_phomemo.py#L61-77`, `L211-213` |
| JEF | ジョブ全体を 1 回で | なし | `writeSlowly = false`。遅い経路（MTU ごと・20 ms）も持つ | [JEF] `phomemo.swift#L186-208` |
| SGR（M02X） | ≤182 | 60 ms（iOS アプリは約 30 ms） | 速すぎると数行印字して黙って止まる | [SGR] `PROTOCOL.md#L212-218`, `printer/printer.go#L306-310` |

確度: 「128 byte / 20 ms」が 4 実装（PMY, TIM, LNX の上限, M5 の上限）で一致する。実機で計測付きなのは HA（197 / 10 ms）だけ。`02 b6 00` を信じるなら 182 以下が安全（**推測**）。BLE スタックが MTU を交渉できず 23 のままなら、1 回 20 byte（JPR の値、HA の下限 `MIN_CHUNK = 20`）。

### 6.3 フロー制御

| 項目 | 内容 | 出典 | 確度 |
|---|---|---|---|
| 書き込みごとの `01 01` | 印字中や書き込みのたびに `ff03` へ `01 01` が来る | [HA] `docs/protocol.md#L37-38`（「emits `01 01` repeatedly while printing」）、[JEF] `README.md#L58-81`、[S04] `PROTOCOL.md#L41`（「after roughly every written packet … 77 for 76 packets」）、[SHI] `docs/device-notes.md#L20`、[PSB] `m08f-protocol-reference.md#L151`（M08F: 「returns `01 01` for most writes」） | 5 実装で観測が一致 |
| `01 01` をフロー制御に使っているか | **使っている実装は 0**。HA は「意図的に使わない」 | [HA] `printer.py#L158-162` | — |
| `01 01` の意味 | 受領通知らしい | [S04] `PROTOCOL.md#L41`（「probably a flow-control acknowledgement」） | 推測 |
| PMY の解釈 | 2 byte で先頭 `0x01` なら「Result」、3 byte で先頭 `0x02` なら「Printer type」 | [PMY] `src/web/ble.js#L497-505` | 1 実装のみ |
| バッファ溢れの症状 | 文字化け・繰り返し → 書き込み間隔を広げる | [HA] `README.md#L93`, `L103` | 1 実装 |
| 〃（M02X） | 数行印字して黙って止まる | [SGR] `PROTOCOL.md#L215-218` | 兄弟機 |

---

## 7. 初期化シーケンス

### 7.1 各バイトの意味

| バイト | 名前 | 意味 | 出典 | 確度 |
|---|---|---|---|---|
| `1b 40` | ESC @ | プリンタ初期化 | [VIV] `README.md#L427`、[HA] `docs/protocol.md#L44`、ほか多数 | 14 実装で一致（MDA だけ送らない） |
| `1b 61 n` | ESC a n | 位置揃え（n = 0 左、1 中央、2 右） | [VIV] `README.md#L428-430`、[HA] `docs/protocol.md#L45`、[JPR] `T02Protocol.swift#L62-64`, `L294-299` | 値の意味は一致。**ラスタ画像には効かない**（兄弟機 2 件: [HKW] `ESCPOS_constants.py#L12`「everything retains centered alignment」、[PSB] `m08f-protocol-reference.md#L504`「No effect on raster images」） |
| `1f 11 02 n` | ベンダ固有 | 印字濃度とされる。公式アプリは常に `04` を送る | [TAG] `t02_print.py#L14-21`, `README.md#L102`、[VIV] `README.md#L431`（意味の説明なし） | 意味は §9 |

### 7.2 実装ごとの初期化バイト列（原文のまま）

| 実装 | 送る列（順番どおり） | 出典 |
|---|---|---|
| HA（**実機で成功**） | `1b 40` `1b 61 00` | [HA] `protocol.py#L20`, `L24-26`, `L92-94`、`tests/test_protocol.py#L55-66` |
| VIV `tools/phomemo-filter.py` | `1b 40 1b 61 01 1f 11 02 04` | [VIV] `tools/phomemo-filter.py#L13-16` |
| VIV CUPS フィルタ（現行） | `1b 40` `1b 61 01` | [VIV] `cups/filter/rastertopm02_t02.py#L64-76`。`1f 11 02 04` はコミット 1b7c682「cups: remove unidentified codes」で削除（削除前は `b'x1f\x11\x02\x04'` とバックスラッシュ欠けで、正しく送れていなかった） |
| LNX | `1b 40` `1b 61 01` `1f 11 02 04` | [LNX] `t02#L311` |
| JEF | `1b 40 1b 61 01 1f 11 02 04` | [JEF] `Phomemo/phomemo_image.swift#L79-81` |
| TAG | `1b 40 1b 61 01 1f 11 02 n`（n は 1〜5、既定 4） | [TAG] `t02_print.py#L17-21` |
| BEN | `1b 40 1b 61 01 1f 11 02 04` | [BEN] `print_text.py#L20` |
| WIN（USB） | `1b 40`、`1b 61 01`、`1f 11 02 04`、その後 1 s 待つ | [WIN] `usbprint_t02.py#L142-145` |
| ESP（Classic） | `1b 40 1b 61 01 1f 11 02 04` | [ESP] `src/main.cpp#L30-33` |
| M5（実機） | `1b 40` → 50 ms → `1f 11 02 04` → 50 ms | [M5] `src/main.cpp#L348-353` |
| JPR | `1b 40` `1b 61 01` | [JPR] `T02Protocol.swift#L257-259` |
| MDS / MDM | `1b 40` のみ | [MDS] `PhomemoDriver.swift#L78-80`、[MDM] `print_phomemo.py#L57-58` |
| MDA | **何も送らない**（いきなりラスタブロック） | [MDA] `BluetoothManager.swift#L390-401` |
| PMY（T02 は `m-series` 経路） | `1b 40` → 100 ms → `1b 37 07 hh 02` → 30 ms → `1d 7c dd` → 50 ms | [PMY] `src/web/printers.json#L89-105`（T02 = `"protocol": "m-series"`）、`src/web/printer.js#L956-969` |
| TIM（実機確認の記載なし） | `1b 40` `1f 11 02 dd` `1f 11 37 cc` `1f 11 0b` `1f 11 35 00` | [TIM] `phomemo_esc/compact.py#L14-21`, `L47-54` |

確度のまとめ:
- `1b 40` を先頭に送る: 14 実装で一致。
- `1f 11 02 04` を送る: 8 実装（VIV 旧, LNX, JEF, TAG, BEN, WIN, ESP, M5。独立なのは VIV、TAG、M5 程度で、残りは VIV からの転記）。TIM は `1f 11 02` に `01`/`02`/`04` を入れる。**送らなくても印字できる**: HA（実機）と VIV の現行 CUPS フィルタの 2 実装。
- `1b 61 n`: ラスタ印字には効かない（兄弟機 2 件）。送っても害はない。

---

## 8. 画像（ラスタ）

### 8.1 寸法

| 項目 | 値 | 出典 | 確度 |
|---|---|---|---|
| 1 行のドット数 | **384** | [HA] `const.py#L24`, `docs/protocol.md#L64`（「verified: a full-width bar reaches both paper edges with no offset」）、[LNX] `t02#L16`、[JPR] `T02Protocol.swift#L25`、[TAG] `t02_print.py#L11`、[MDS] `PhomemoCommands.swift#L34`、[MDA] `BluetoothManager.swift#L331`、[M5] `main.cpp#L38`、[JEF] `phomemo_image.swift#L7`、[TIM] `core.py#L67`、[PMY] `printers.json#L95` | 10 実装で一致（HA 実機） |
| 1 行のバイト数 | **48**（= 0x30） | 同上 | 10 実装で一致 |
| 解像度 | **203 dpi = 8 dot/mm**（縦横とも） | [HA] `docs/protocol.md#L65-67`（「image height in px ÷ 8 = mm of paper consumed」）、[VIV] `README.md#L464-466`、`cups/drv/phomemo-m02_t02.drv#L38`、[JPR] `T02Protocol.swift#L31`、[TIM] `printer_profiles.json#L6479`（`"dev_dpi": 203`）、[PMY] `src/web/printers.json#L96` | 5 実装で一致 |
| 用紙 / 印字幅 | 用紙 53 mm（50 mm も可）、印字幅約 48 mm | [HA] `docs/protocol.md#L66`、[TAG] `README.md#L5`, `L58`、[SGR] `PROTOCOL.md#L109` | 3 実装で一致 |
| 過去の誤り | PMY は T02 を 54 byte（432 px）としていたが、48 byte に直した | [PMY] コミット 7f1db83「Updated the width of the t02 printer as it's actually only 48mm print head」 | — |

### 8.2 ビットの並びと色

| 項目 | 値 | 出典 | 確度 |
|---|---|---|---|
| ビット順 | 1 byte に 8 dot、**MSB = 左端** | [HA] `protocol.py#L63-76`、`tests/test_protocol.py#L33-41`（x=0 の黒 → `0x80`、x=7 → `0x01`）、[TIM] `encoding.py#L45-62`、[PMY] `canvas.js#L2138-2139`、[M5] `main.cpp#L330-335`、[JPR] `T02Protocol.swift#L179-185` | 全実装で一致 |
| 色 | **ビット 1 = 発熱 = 黒**、0 = 白 | [HA] `docs/protocol.md#L69-77`、`tests/test_protocol.py#L23-30`（全黒 → `ff`×48、全白 → `00`×48）、[TIM] `rendering/renderer.py#L40-45`、[ESP] `main.cpp#L62-73`、[SGR] `PROTOCOL.md#L95-98` | 全実装で一致 |
| 行の順 | 上の行（先に紙から出る側）から順に送る | 全実装 | 全実装で一致 |

PIL のモード `"1"` は 0 が黒なので、PIL を使う実装は反転してから詰めている（[HA] `protocol.py#L72-74`、[TAG] `t02_print.py#L45`）。

### 8.3 画像コマンド GS v 0 の形式

```
1d 76 30 m  xL xH  yL yH  <データ: (xL + xH*256) × (yL + yH*256) byte>
```

| バイト | 意味 | T02 での値 | 出典 | 確度 |
|---|---|---|---|---|
| `1d` | GS | 固定 | [VIV] `README.md#L437`、[HA] `docs/protocol.md#L46` | 全実装 |
| `76` | `'v'` | 固定 | 同上 | 全実装 |
| `30` | `'0'` | 固定 | 同上 | 全実装 |
| `m` | モード: 0 通常、1 横倍、2 縦倍、3 4 倍 | **`00`** | 意味: [VIV] `README.md#L438-439`、[JPR] `T02Protocol.swift#L304-317`。T02 で 0 以外を試した実装はない | 値 0: 全実装。0 以外の動作は**不明** |
| `xL xH` | 1 行のバイト数（LE16） | **`30 00`**（48） | [VIV] `README.md#L440`、[HA] `docs/protocol.md#L49` | 全実装 |
| `yL yH` | このブロックの行数（LE16） | 例: 240 行 → `f0 00`、255 行 → `ff 00` | [HA] `tests/test_protocol.py#L55-67`、[VIV] `README.md#L441` | 全実装（ただし §8.4 の旧バグに注意） |

HA の実機成功時の先頭 13 byte（240 行の画像、[HA] `tests/test_protocol.py#L55-68`）:

```
1b 40  1b 61 00  1d 76 30 00  30 00  f0 00  <48 × 240 byte>  1b 64 03
```

### 8.4 行数フィールドの旧バグと `0x0a` 置換（**重要**）

VIV の初期コード `tools/phomemo-filter.py` は、行数フィールドに「実際の行数 − 1」を書き、ブロックを最大 256 行にし、データ中の `0x0a` を `0x14` に置き換えている:

```python
def print_marker(lines=0x100):
    with os.fdopen(sys.stdout.fileno(), "wb", closefd=False) as stdout:
        stdout.write(0x761d.to_bytes(2, 'little'))
        stdout.write(0x0030.to_bytes(2, 'little'))
        stdout.write(0x0030.to_bytes(2, 'little'))
        stdout.write((lines - 1).to_bytes(2, 'little'))
    return

def print_line(image, line):
    with os.fdopen(sys.stdout.fileno(), "wb", closefd=False) as stdout:
        for x in range(int(image.width / 8)):
            byte = 0
            for bit in range(8):
                if image.getpixel((x * 8 + bit, line)) == 0:
                    byte |= 1 << (7 - bit)
            # 0x0a breaks the rendering
            # 0x0a alone is processed like LineFeed by the printe
            if byte == 0x0a:
                byte = 0x14
            stdout.write(byte.to_bytes(1, 'little'))
    return

remaining = image.height
line=0
print_header()
while remaining > 0:
    lines = remaining
    if lines > 256:
        lines = 256
    print_marker(lines)
    remaining -= lines
    while lines > 0:
        print_line(image, line)
        lines -= 1
        line += 1
print_footer()
```
（[VIV] `tools/phomemo-filter.py#L18-24`, `L36-48`, `L74-87` をそのまま引用）

VIV 自身が CUPS フィルタ側でこれを直している。コミット e9fa4bf のメッセージ:

> cups: print raster bit image
> The number of lines was erroneous, and that fixes also the problem with 0x0a

差分は `(lines - 1)` → `lines`、最大 256 → 255、`0x0a` 置換の削除（`git show e9fa4bf`）。`tools/phomemo-filter.py` は直されないまま残っている。

| 実装 | 行数フィールド | ブロック上限 | `0x0a`→`0x14` | 出典 |
|---|---|---|---|---|
| VIV `tools/phomemo-filter.py`（旧） | 行数 − 1 | 256 | する | 上記 |
| JEF | 行数 − 1 | 256 | する | [JEF] `phomemo_image.swift#L63-77`, `L83-91`, `L104-106` |
| VRK（M02S） | 行数 − 1 | 256 | する | [VRK] `index.js#L178`, `L199`, `L217-219` |
| BEN | 行数（正しい） | 256 | する | [BEN] `print_text.py#L56-75` |
| WIN | 行数（正しい） | 100 | する | [WIN] `usbprint_t02.py#L35-45`, `L149-166` |
| BRU | VIV の旧スクリプトをそのまま使用 | 256 | する | [BRU] `print-with-T02.sh#L16-31` |
| VIV CUPS（現行）、HA、LNX、TAG、JPR、TIM、PMY、M5、MDS、MDA、MDM、ESP | 行数（正しい） | 各実装の値（§8.5） | しない | 各ファイル |

解釈（**推測**）: 行数を 1 少なく申告すると、余った最後の 1 行（48 byte）がコマンドとして読まれる。その行に `0x0a` があると改行（紙送り）として扱われる。だから `0x0a` を消すと「直ったように見えた」。白い行（`00` の並び）なら目立たないので、旧方式でも多くの場合それらしく印字される（JEF のログでは印字成功）。M08F では「`0x0A` handled correctly (no escaping needed)」（[PSB] `m08f-protocol-reference.md#L63`）。
**新しく実装するなら、行数は実際の値を書き、`0x0a` は置き換えない**（HA の実機成功例と VIV の修正コミットに従う）。

### 8.5 1 ブロックの最大行数とブロック分割

| 方針 | 実装 | 出典 | 備考 |
|---|---|---|---|
| **≤255 行**ごとに `GS v 0` を付け直す | HA（実機）、VIV CUPS、JPR、TAG、LNX | [HA] `protocol.py#L96-107`, `const.py#L27`, `tests/test_protocol.py#L76-89`（300 行 → 255 + 45 の 2 ブロック）、[VIV] `cups/filter/rastertopm02_t02.py#L113-118`、[JPR] `T02Protocol.swift#L35-36`, `L261-277`、[TAG] `t02_print.py#L49-52`、[LNX] `t02#L312-315` | 5 実装で一致。HA は「Blocks are capped at 255 lines」と実機記録（`docs/protocol.md#L51`） |
| ≤256 行 | BEN（正しい行数）、VIV 旧・JEF（行数 − 1） | §8.4 | 256 行の正しい申告（`00 01`）は BEN だけ |
| 200 行 | GBL（M02S）、TOM（M02 Pro） | [GBL] `phomemo#L129-148`、[TOM] `src/phomemo_agent/constants.py#L6`（`DEFAULT_CHUNK_ROWS = 200`） | 兄弟機 |
| 128 行 | MDA | [MDA] `BluetoothManager.swift#L334-353` | 「printer buffer overflow を避けるため」とコメント |
| 100 行 | MDS、MDM、WIN（WIN はブロックごとに 2 s 待つ） | [MDS] `PhomemoImageProcessor.swift#L24`、[MDM] `print_phomemo.py#L61`、[WIN] `usbprint_t02.py#L149-171` | |
| 2 行 | ESP（Game Boy の 1 行を 2 行に引き伸ばす都合） | [ESP] `main.cpp#L55-58` | |
| 1 行 | M5（実機）。1 行ごとに `1d 76 30 00 30 00 01 00` + 48 byte を送り、5 ms 待つ | [M5] `main.cpp#L251-258` | |
| **分割しない**（1 ブロックで全高さ。行数は 16 bit） | PMY（T02 経路）、TIM（`max_lines_per_block=0xFFFF`） | [PMY] `printer.js#L261-265`, `L971-973`、[TIM] `compact.py#L55` | T02 での実機確認の記載なし |
| 兄弟機 M02X は分割不要、M02 ファミリは「firmware caps the u16 at 0xFF」 | SGR | [SGR] `PROTOCOL.md#L83-85`, `L240`, `L302-303` | 兄弟機。「≤255」の主張自体は SGR の実測ではない |

結論: **255 行以下に分けるのが安全**（実機で確認済み、多数派）。全高さを 1 ブロックで送れるかは T02 では未確認（2 実装はそうしているが、実機確認の記載なし）。

### 8.6 幅が 384 未満の画像

- VIV CUPS と TIM は画像の幅から `xL` を計算する（[VIV] `cups/filter/rastertopm02_t02.py#L83`、[TIM] `bitmap.py#L159-169`）。その場合に印字位置がどうなるかは**不明**。
- ESP は 40 byte の画像の左右に 4 byte ずつ `00` を足して 48 byte にしている（[ESP] `main.cpp#L39`, `L60`, `L77`）。PMY は左・中央・右のどこに置くかを決めて 48 byte に詰める（[PMY] `canvas.js#L2111-2152`）。
- 迷ったら常に 48 byte の行を送り、ホスト側で余白を白（`00`）で埋める（多数派の方法）。

### 8.7 先頭行が欠ける問題

| 観測 | 出典 | 確度 |
|---|---|---|
| TIM は T02 用レシピで画像の上に白行を 4 行足す（`top_padding=4`） | [TIM] `phomemo_esc/core.py#L67`, `compact.py#L72-76` | 1 実装（実機確認の記載なし） |
| M02S で「最初の数行が印字されない」ので白行 5 行を先に送る | [THEA] `_image_helper.py#L23-28`（「workaround for the printer not printing the first couple lines」） | 兄弟機 |

T02 で実際に欠けるかは**不明**。

---

## 9. 濃度・熱量・速度

| コマンド | 意味 | 値域 | 出典 | T02 での確度 |
|---|---|---|---|---|
| `1f 11 02 n` | 印字濃度 | 公式アプリは常に `04`。1〜5 は受け付ける（TAG）。弱 `01`・普通 `03`・強 `04`（AIN）。TIM の段階: 1→`01`、2→`02`（既定）、3→`04`、4→`04` | [TAG] `t02_print.py#L14-21`, `README.md#L66`, `L102`, `CLAUDE.md#L53`、[AIN] `src/lib.rs#L192-198`、[TIM] `compact.py#L20`, `L47-52`, `printer_profiles.json#L6512-6523`、[UNX] `src/print/printer.rs#L34`（「look lighter if not used (colour density?)」）、[M5] `main.cpp#L350` | 意味は 4 実装で一致（推定の記述）。数値と濃さの対応は**不明** |
| `1f 11 37 c` | 濃度係数 | `0x64`（100）が標準、`0x96`（150）が M02S 用（AIN）。TIM は段階 4 だけ 150、ほかは 100 | [AIN] `src/lib.rs#L185-190`、[TIM] `compact.py#L16`, `L20`, `L51-52`、[SGR] `PROTOCOL.md#L227`（M02X の初期化で `1f 11 37 64`） | 兄弟機と TIM のみ。T02 では**未確認** |
| 濃度コマンドなし | HA は送らずに「sharp and fully black」 | — | [HA] `docs/protocol.md#L53-55`, `CLAUDE.md#L95-96` | 1 実装（実機） |
| `1b 4e 0d n` | M110 系の印字速度（1〜5） | — | [VIV] `README.md#L485-486`（M110 の節）、[HA] `tools/print_test.py#L46-48`（「Unverified on the T02」とコメントし、`--energy` 指定時だけ送る） | T02 では**不明** |
| `1b 4e 04 n` | 濃度（M110 系 01〜0f、M02S アプリの「concentration」） | — | [VIV] `README.md#L487-488`、[THEA] `printer.py#L62-63`、[SGR] `PROTOCOL.md#L129`, `L295-296`（**M02X では送るとプリンタが固まる**） | T02 では**不明**。危険の報告あり（兄弟機） |
| `1b 37 n1 n2 n3` | ESC 7（熱設定） | PMY は `07 hh 02`。hh は濃度 1〜8 → 40, 60, 80, 100, 120, 140, 160, 200（既定 6 → 140 = `0x8c`） | [PMY] `printer.js#L242-247`, `L255-259`, `L963-966` | 1 実装のみ（T02 経路で送っている）。M08F では「No visible effect」（[PSB] `m08f-protocol-reference.md#L503`） |
| `1d 7c n` | GS \|（標準 ESC/POS の濃度） | PMY は濃度 1〜8 をそのまま | [PMY] `printer.js#L253-254`, `L967-969` | 1 実装のみ（「may not work on all printers」とコメント） |
| `15 11 02 n` | NAK 始まりの濃度（M02S アプリ） | — | [THEA] `printer.py#L124-128` | 兄弟機のみ。M08F では効果なし（[PSB] `#L512`） |
| 速度 | T02 用の速度コマンドを使う実装は**なし** | — | — | **不明** |

参考: 印字速度は小売の仕様で 6〜10 mm/s（Web 検索結果: digitec ほか）。TIM の完了見込み時間は「画像の行数 × 0.125 mm × 0.110 s/mm」（[TIM] `compact.py#L65-66`。約 9 mm/s に当たる）。LNX は 20 mm/s と仮置きしている（[LNX] `t02#L19`「velocidade estimada, calibrar se cortar」）。

---

## 10. 紙送り・カット・終了シーケンス

### 10.1 コマンド

| コマンド | 意味 | 出典 | 確度 |
|---|---|---|---|
| `1b 64 n` | ESC d n: バッファを印字して n 行送る | [VIV] `README.md#L452-453`、[HA] `docs/protocol.md#L47`, `protocol.py#L29-31`（0〜255 に丸める） | 全実装で一致 |
| `1b 4a n` | ESC J n: n ドット送る | [PMY] `printer.js#L252`（T02 経路の最後に `1b 4a 20`）、[TIM] `phomemo_esc/core.py#L22`, `L24`, `L85-86`（手動送り `1b 4a 50`） | 2 実装。T02 での送り量の実測なし |
| カット | **ない**（T02 にカッターはない）。`1d 56 01` を M02S で送る実装はあるが効果は不明 | [THEA] `printer.py#L118-122`, `L189` | — |
| 終了専用コマンド | **不要**。「a trailing feed is sufficient」 | [HA] `docs/protocol.md#L57-58` | 1 実装（実機） |

`ESC d n` の「1 行」が何ドットかは**不明**（測った実装はない）。手がかり:
- HA は既定 3、VIV の CUPS は T02 の既定 4（M02 は 2）（[HA] `const.py#L43`、[VIV] `cups/drv/phomemo-m02_t02.drv#L74-80`）。
- MDA のコメント「100 にしたらたくさん転がった」→ 既定 5、実際の送信は 1（[MDA] `PrinterProtocol.swift#L10-17`, `BluetoothManager.swift#L399-401`）。
- LNX は n をドットとみなし、mm × 8 を `1b 64 n` で 2 回送る（既定 8 mm → `1b 64 40` ×2）。同時に画像の下に同じ行数の白行も足している（[LNX] `t02#L292-306`, `L316`, `L686-700`）。

### 10.2 実装ごとの終了バイト列（原文のまま）

| 実装 | 終了列 | 出典 |
|---|---|---|
| VIV `tools/phomemo-filter.py`、JEF、BEN、WIN | `1b 64 02` `1b 64 02` `1f 11 08` `1f 11 0e` `1f 11 07` `1f 11 09` | [VIV] `tools/phomemo-filter.py#L26-34`、[JEF] `phomemo_image.swift#L111-120`、[BEN] `print_text.py#L21`、[WIN] `usbprint_t02.py#L177-182` |
| LNX | `1b 64 n` `1b 64 n` `1f 11 08` `1f 11 0e` `1f 11 07` `1f 11 09` | [LNX] `t02#L316` |
| ESP | `1b 64 nn` `1f 11 08` `1f 11 0e` `1f 11 07` `1f 11 09` | [ESP] `main.cpp#L35-38`, `L81-85` |
| TAG | `1b 64 02` `1f 11 08` `1f 11 0e` `1f 11 07` `1f 11 09` | [TAG] `t02_print.py#L25-26` |
| M5（実機） | `1b 64 02` → 50 ms → `1f 11 08` → 50 ms → `1f 11 0e` → 50 ms → `1f 11 07` → 200 ms | [M5] `main.cpp#L355-364` |
| VIV CUPS（現行） | `1b 64 <FeedLines>`（T02 の既定 4） | [VIV] `cups/filter/rastertopm02_t02.py#L91-93`, `L103`, `L119` |
| HA（実機） | `1b 64 03` | [HA] `protocol.py#L109`, `tests/test_protocol.py#L68` |
| JPR | `1b 64 04` | [JPR] `T02Protocol.swift#L40-41`, `L279-280` |
| MDS / MDM | `1b 64 03` | [MDS] `PhomemoDriver.swift#L96-98`、[MDM] `print_phomemo.py#L79-80` |
| MDA | `1b 64 01` | [MDA] `BluetoothManager.swift#L399-401` |
| TIM | `1b 64 02` `1b 64 02` | [TIM] `compact.py#L19`, `L56-57` |
| PMY | 300 ms 待つ → `1b 4a 20`（32 ドット）→ 800 ms 待つ | [PMY] `printer.js#L991-995` |

`1f 11 08 / 0e / 07 / 09` は**ステータス問い合わせ**であって印字には不要（§11）。M02X では無視される（[SGR] `PROTOCOL.md#L245-247`）。VIV は Android アプリの通信を sniff して得た列として載せており（`README.md#L6-7`）、意味は書いていない（`README.md#L449-460`）。GBL は「unknown」とコメントアウトしている（`phomemo#L150-154`）。

---

## 11. ステータス問い合わせと通知

### 11.1 通知の形

- 問い合わせは `ff02` に `1f 11 <opcode>` の 3 byte を書く。
- 応答は `ff03` に通知で来る。形は `1a <種別> <値…>`（[PMY] `ble.js#L488-490`、[S04] `PROTOCOL.md#L50`、[SGR] `PROTOCOL.md#L263-264`）。
- 種別ごとの長さ（先頭の `1a` を除き、種別バイトを含む）: `03`:2、`04`:2、`05`:2、`06`:2、`07`:4、`08`:16、`09`:2、`0b`:2、`0e`:2、`0f`:2、`16`:2、`17`:2、`1d`:2、`20`:2、`35`:2、`3b`:6（[TIM] `phomemo_esc/replies.py#L41-48`）。
- TIM は 1 回の通知に複数の `1a …` が連結されて来る場合と、分割されて来る場合の両方に対応している（`replies.py#L5-38`、テスト `tests/test_phomemo_session.py#L39-60` は合成データ）。実機で連結が起きるかは**不明**。
- 応答の前に `01 01` が来る（[S04] `PROTOCOL.md#L50`「The reply arrives on `ff03` as `01 01`, then `1A TT VV…`」）。

### 11.2 T02 実機の通知ログ（[JEF] `README.md#L44-95`）

JEF は接続後に `SSSGETSN\r\n`、`SSSGETBMAPMODE\r\n`、`1f 11 11`、`1f 11 12` を 0.5 s ごとに送り（`phomemo.swift#L162-180`）、画像を送り、最後に VIV と同じ終了列（`1b 64 02` ×2、`1f 11 08`、`1f 11 0e`、`1f 11 07`、`1f 11 09`）を送っている。そのときの `ff03` 通知（10 進表記を 16 進に直したもの）:

| 原文（10 進） | 16 進 | JEF の表示 |
|---|---|---|
| `[1, 1]` | `01 01` | 🖨️ Ready |
| `[2, 182, 0]` | `02 b6 00` | — |
| `[1, 1]` ×4 | `01 01` | — |
| `[26, 6, 137]` | `1a 06 89` | 📃 Have paper |
| `[26, 5, 152]` | `1a 05 98` | 🚪 Printer cover is closed |
| `[1, 1]` …多数 | `01 01` | — |
| `[26, 4, 83]` | `1a 04 53` | — |
| `[26, 9, 12]` | `1a 09 0c` | — |
| `[26, 7, 3, 0, 7]` | `1a 07 03 00 07` | — |
| `[26, 8, 81, 49, 49, 52, 69, 52, 56, 84, 50, 53, 56, 48, 57, 49, 53]` | `1a 08` + ASCII `Q114E48T2580915` | — |
| `[26, 15, 12]` | `1a 0f 0c` | ✅ Print complete |

`1f 11 08, 0e, 07, 09` の順に送って、`1a 04, 09, 07, 08` の順に返ってきている。VIV も M02 で同じ並び（`1a 04 5a` / `1a 09 0c` / `1a 07 01 00 00` / `1a 08` + シリアル）を記録している（[VIV] `README.md#L468-476`）。

### 11.3 問い合わせ表

| 問い合わせ | 応答 | 意味 | 出典 | 確度 |
|---|---|---|---|---|
| `1f 11 08` | `1a 04 vv` | **電池残量 %**（例 `5a` = 90、`53` = 83） | [TAG] `t02_print.py#L84-101`（T02 実機、Classic で直接対応付け）、[S04] `PROTOCOL.md#L55`（M02 Pro 実機、「seen 5–47」）、[SGR] `PROTOCOL.md#L271`（M02X）、[PMY] `ble.js#L15`, `L523-531`、[GBL] `phomemo-status#L33`（名前「Energy」）、[THEA] `printer.py#L82-84`（`get_energy`）、[K0I] `phomemo.ts#L46-55` | 7 実装で一致（T02 は TAG・PMY、残りは兄弟機。実機は TAG と S04 の 2 件。JEF のログ順も一致）。**TIM だけ食い違う**（下記） |
| `1f 11 0e` | `1a 09 vv` | 自動電源オフのタイマ（単位不明。LNX と TIM は 5 倍して秒とする） | [JEF] ログ（順序から）、[SGR] `PROTOCOL.md#L273`（「(?) — observed 0x02」）、[PMY] `ble.js#L22`, `L557-561`（「power」）、[LNX] `t02#L323`, `L616-617`（`auto-off {v*5}s`）、[GBL] `phomemo-status#L35`（名前「Device Timer」）、[THEA] `printer.py#L86-88` | 6 実装で一致。単位は**不明**（`0c` = 12 → 60 s か 60 分かは分からない） |
| `1f 11 07` | `1a 07 a b c` | ファームウェア版 | [JEF] ログ（`1a 07 03 00 07`）、[S04] `PROTOCOL.md#L54`（「version a.b.c (seen: 2.0.6)」）、[SGR] `PROTOCOL.md#L270`、[LNX] `t02#L612-613`、[PMY] `ble.js#L545-549`（並び順に連結）、[TIM] `runtime/phomemo.py#L162-163` | 6 実装で一致。**バイトの並び順は食い違う**（下記） |
| `1f 11 09` | `1a 08` + ASCII 15 byte | シリアル番号（例 `Q114E48T2580915`） | [JEF] ログ、[SGR] `PROTOCOL.md#L272`、[PMY] `ble.js#L17`, `L551-555`、[LNX] `t02#L614-615`、[GBL] `phomemo-status#L34`（名前「Sn」）、[PSB] `m08f-protocol-reference.md#L78`（M08F で `1f 11 09` → `1a 08`）、長さ: [TIM] `replies.py#L45`（16 = 種別 + 15） | 6 実装で一致 |
| `1f 11 11` | `1a 06 89` / `1a 06 88` | 紙あり / **紙切れ** | [JEF] ログと `phomemo.swift#L133-142`、[S04] `PROTOCOL.md#L56`、[SGR] `PROTOCOL.md#L274`、[PMY] `ble.js#L18`, `L539-543`、[TIM] `runtime/phomemo.py#L89-90`, `L188-192`、[LNX] `t02#L324`, `L538-539` | 6 実装で一致（実機 2） |
| `1f 11 12` | `1a 05 98` / `1a 05 99` | カバー閉 / **カバー開** | [JEF] ログと `phomemo.swift#L122-131`、[S04] `PROTOCOL.md#L57`、[SGR] `PROTOCOL.md#L275`、[TIM] `runtime/phomemo.py#L89`, `L182-187`、[MDM] `README.md#L84-86` | 5 実装で一致（実機 3）。**PMY は逆**、**LNX は問い合わせ番号が違う**（下記） |
| `1f 11 13` | `1a 03 a8` / `1a 03 a9` | 温度正常 / **過熱** | [S04] `PROTOCOL.md#L58`（M02 Pro 実機）、[SGR] `PROTOCOL.md#L276`、値の意味: [JEF] `phomemo.swift#L111-120`、[PMY] `ble.js#L516-521`、[LNX] `t02#L618-619`、[TIM] `runtime/phomemo.py#L157-158` | 応答の意味は 5 実装で一致。`1f 11 13` で問い合わせることは兄弟機 2 実装のみ。**GBL と THEA は「Serial」と呼んでいる**（[GBL] `phomemo-status#L38`、[THEA] `printer.py#L68-75`。THEA のコマンド群は Android アプリの `PrinterUtils.java` の順に並べたもの: `printer.py#L59-60`） |
| `1f 11 38` | `1a 17 vv`（T02 は旧形式で `1a 16 vv`） | チップの種類 | [TIM] `runtime/phomemo.py#L71`, `L78`, `L168-169`、`tests/test_phomemo_session.py#L157-164`、[GBL] `phomemo-status#L40`（「Chip Type」、コメントアウト） | 1 実装のみ（T02 の実機確認の記載なし） |
| `1f 11 14` | `1a 0a 00 00` | 不明 | [SGR] `PROTOCOL.md#L284-286` | 兄弟機のみ |

#### 食い違い

1. **TIM の対応付け**: TIM は `(0x08, 0x08)`、`(0x09, 0x09)`、`(0x0E, 0x04)`、つまり「`1f 11 08` → `1a 08`（シリアル）」「`1f 11 09` → `1a 09`」「`1f 11 0e` → `1a 04`（電池）」と待つ（[TIM] `runtime/phomemo.py#L77-79`、テストの模擬応答 `tests/test_phomemo_session.py#L50-56`）。TAG（T02 実機）、S04（M02 Pro 実機）、SGR、JEF のログの順序はどれも「`1f 11 08` → `1a 04`」なので、TIM の対応付けは少数派。TIM は応答を種別で解釈し、待ち時間 0.5 s を過ぎても止まらないので、実害は出にくい（`runtime/phomemo.py#L28`, `L76`, `L148-217`）。
2. **カバーの値**: PMY は `98` = open、`99` = closed と逆に解釈している（[PMY] `ble.js#L533-537`）。ほかの 5 実装は `99` = 開。MDM はカバーを開け閉めして `1a 05 99` / `1a 05 98` を観測している（`README.md#L84-86`）。
3. **カバーの問い合わせ番号**: LNX だけ `1f 11 05` を使い、「カバーが開いているときだけ応答がある、閉じていれば応答なし」と書いている（[LNX] `t02#L325`, `L609-611`）。ほかは `1f 11 12`。
4. **ファームウェア版の並び**: 先頭から a.b.c と読むのが JEF・S04・LNX・PMY・TIM・PSB。THEA と K0I は `r[4].r[3].r[2]`（逆順）（[THEA] `printer.py#L77-80`、[K0I] `phomemo.ts#L35-44`）。SGR は「vL.0.vR」。
5. **`1f 11 13`**: 実機で温度が返る（S04）一方、GBL と THEA の名前は「Serial」。THEA は 3 byte の応答をシリアル番号として読んでいる（たぶん温度応答を誤読している。**推測**）。

### 11.4 電池の特殊値

| 値 | 解釈 | 出典 |
|---|---|---|
| `1a 04 a4` | 0 % | [PMY] `ble.js#L524`、[LNX] `t02#L607` |
| `1a 04 a3` | 3 % | 同上、[TIM] `runtime/phomemo.py#L160-161`（低電池扱い） |
| `1a 04 a2` | 5 % | 同上 |
| `1a 04 a1` | 10 % | 同上 |
| `vv ≥ a1` の 2 つ目の `1a 04` | USB 給電中に勝手に来ることがある。充電状態かもしれない（充電中に来なかったこともある） | [S04] `PROTOCOL.md#L60-63`（M02 Pro） |
| `1a 35 02` | 充電中（`02` 以外は非充電） | [TIM] `runtime/phomemo.py#L170-171`（実機確認の記載なし） |

確度: A1〜A4 の % 対応は 3 実装で一致するが、どれも出典を示していない。

### 11.5 問い合わせなしで来る通知（イベント）

| 通知 | 意味 | 出典 | 確度 |
|---|---|---|---|
| `01 01` | 書き込みごとの受領（§6.3） | — | 5 実装で観測 |
| `02 b6 00` | 接続直後。1 回の最大書き込み長 182 らしい（§6.1） | [JEF], [SHI], [S04] | 観測は 3 実装で一致、意味は推測 |
| `1a 05 99` / `1a 05 98` / `1a 06 88` | カバーを開けた / 閉めた / 紙を抜いた | [MDM] `README.md#L77-86`（問い合わせの送信を止めた状態で観測: `check_status.py#L84-100`） | 1 実装（T02） |
| `1a 0f 0c` | **印字完了**（ジョブごとに 1 回、データ送信の約 1.5〜3 s 後） | T02: [JEF] ログと `phomemo.swift#L149-152`。M02 Pro: [S04] `PROTOCOL.md#L42-46`。M02X: [SGR] `PROTOCOL.md#L244-255`。[PMY] `ble.js#L582-585` | 4 実装で一致 |
| `1a 0f xx`（`xx` ≠ `0c`） | 印字失敗 | [TIM] `runtime/phomemo.py#L211-213` | 1 実装のみ |
| `1a 0b b8` | プリンタ側でジョブ取り消し | [JEF] `phomemo.swift#L144-147`、[PMY] `ble.js#L563-566`、[TIM] `runtime/phomemo.py#L201-202`, `runtime/phomemo_esc.py#L19` | 3 実装で一致 |
| `1a 03 a9` | 過熱（ヘッドを冷ます必要あり） | [JEF] `phomemo.swift#L111-115`、[TIM] `runtime/phomemo.py#L251-259`（冷えるまで最大 180 s 待つ） | 2 実装 |

`1a 0f 0c` の信頼性: LNX は「`0x1a 0x0f` is not a reliable end signal」として使わない（[LNX] `t02#L584-585`）。TIM も T02 では完了通知を使わず、行数から時間を見積もって待つ（「deliberately not treated as a physical printer acknowledgement」、[TIM] `compact.py#L60-66`）。S04 と SGR は実機で毎回来たと書いている。

### 11.6 使わない方がよいもの

| 送信 | 理由 | 出典 |
|---|---|---|
| `1f 11 nn`（nn > `0x14`）の総当たり | M02X で `0x00`〜`0x40` を順に試したら、`0x14` の後で応答が途絶え、その後**電源が入らなくなった**。原因は未確定 | [SGR] `PROTOCOL.md#L282-291`、[S04] `PROTOCOL.md#L65-66` |
| 〃（ただし反例） | TIM は接続時に `1f 11 38`, `63`, `5e`, `56`, `51` を送る | [TIM] `runtime/phomemo.py#L77-82`, `tests/test_phomemo_session.py#L18-20` |
| `1d 67 6e` | MDS / MDM が「CHECK_STATUS」として 30 s ごとに送るが、これへの応答を示した記録はない。MDM の README の例は開閉で出たイベント | [MDS] `PhomemoCommands.swift#L7-8`, `PhomemoDriver.swift#L272-282`、[MDM] `print_phomemo.py#L175` |
| `10 04 01`, `1b 76` | MDM が試したが無効化している | [MDM] `check_status.py#L84-100` |
| `SSSGETSN\r\n`, `SSSGETBMAPMODE\r\n` | JEF の起動手順。M02X では無視される | [JEF] `phomemo.swift#L164-169`、[SGR] `PROTOCOL.md#L299-300` |

---

## 12. 既知の癖

| 癖 | 内容 | 出典 | 確度 |
|---|---|---|---|
| 送信直後に切断すると印字が欠ける | 「we need to wait the printer answer before closing the socket otherwise the print is stopped」 | [VIV] `cups/backend/phomemo.py#L174-175`、[SGR] `PROTOCOL.md#L249-255`、[S04] `PROTOCOL.md#L44-46`、[SHI] `ble.py#L37-39` | 4 実装で一致 |
| 送信後の待ち時間 | HA 1.5 s（試験ツールは 2.0 s）。TAG 2 + 行数/100 s。LNX は「通知が 1.5 s 来なくなるまで、ただし最大 3 + 行数/80 s」待って切断し、その後さらに 高さ mm / 20 s 待つ。JPR 5 s。BEN は 8 s 無通信まで。VIV は 8 s の受信タイムアウトまで読み続ける。PMY は送り後 800 ms | [HA] `printer.py#L36`, `L220-221`, `tools/print_test.py#L210`、[TAG] `server.py#L132`、[LNX] `t02#L584-598`、[JPR] `CoreBluetoothConnection.swift#L243-249`、[BEN] `bt_send.py#L82-88`、[VIV] `cups/backend/phomemo.py#L194-198`、[PMY] `printer.js#L995` | 6 実装で「待つ」が一致。長さはまちまち |
| 長い印字は ACK が複数来る | 「A long print can generate several ACKs」→ 8 s の受信タイムアウトで待つ | [VIV] コミット 031c416 | 1 実装（Classic） |
| 連続ジョブの間隔 | HA は 1 部ごとに 1.5 s 待って次を送る。PMY は 500 ms。JPR のデモは 3 s。MDM は PDF のページ間 2 s | [HA] `printer.py#L225-236`、[PMY] `src/web/app.js#L1970`, `L4802`、[JPR] `main.swift#L200-202`、[MDM] `print_phomemo.py#L247` | 待つことは一致、長さはまちまち |
| 印字直後の再接続・問い合わせ | 数秒間は電池の問い合わせを無視し、再接続も断る（`Device or resource busy`） | [TAG] `README.md#L104`, `CLAUDE.md#L55-56` | 1 実装（Classic、実機） |
| スリープ | 自動スリープすると広告しなくなる。ソフトでは起こせない | [HA] `docs/protocol.md#L19-20`, `README.md#L46-47` | 1 実装（実機） |
| 過熱 | `1a 03 a9` の間は送らない | §11.5 | 2 実装 |
| 1 回の書き込みが大きすぎる | M02X は 182 byte を超えると黙って落ちる | [SGR] `printer/printer.go#L89-95` | 兄弟機 |
| 紙の向き | 白紙が出るときは紙の表裏が逆（感熱面をヘッド側へ） | [HA] `README.md#L104` | 1 実装 |
| カバー開・紙切れの状態が残る | 戻らないときはハードリセット | [JEF] `README.md#L133-135` | 1 実装 |

---

## 13. 本体フォントによるテキスト印字

| 項目 | 内容 | 出典 | 確度 |
|---|---|---|---|
| T02 で本体フォントの文字印字を確認した実装 | **見つからなかった**。T02 の実装はすべてホスト側で文字を画像にして `GS v 0` で送る | HA, LNX, TAG, JPR, MDA（`textToImage`）、M5（8×8 ビットマップフォントをホスト側に持つ: `main.cpp#L151-249`） | 不明 |
| `0x0a` が改行として処理される | 「0x0a alone is processed like LineFeed by the printe[r]」 | [VIV] `tools/phomemo-filter.py#L43-44` | 1 実装（旧バグの文脈。§8.4） |
| 文字モード用のコマンドが列挙されている | `1b 45 n`（強調）、`1b 61 n`（揃え）。「text-mode rendering only — irrelevant for raster」 | [SGR] `PROTOCOL.md#L71-75`, `L125-134`、[THEA] `printer.py#L100-116` | 兄弟機。印字できるかは未確認 |
| M08F は本体フォントなし | 「No built-in font — chars ignored, only `0x0A` triggers feed」 | [PSB] `m08f-protocol-reference.md#L102-104`, `L511` | 兄弟機（別系列の A4 機） |

---

## 14. Classic Bluetooth（SPP）と USB（参考）

| 項目 | 内容 | 出典 | 確度 |
|---|---|---|---|
| Classic SPP がある | UUID `00001101`、Class of Device `0x00100680` | [FCO] `scripts/error-logs.txt#L38`, `L47` | 1 実装（実機） |
| RFCOMM チャネル 1 で同じ ESC/POS 列が通る | 印字に使っている | [TAG] `t02_print.py#L10`, `L56-81`（実機）、[BEN] `bt_send.py#L13`、[VIV] `cups/backend/phomemo.py#L142-166`、[ESP] `main.cpp#L92-93`（ESP32 BluetoothSerial） | 4 実装で一致 |
| macOS のシリアルポート | `/dev/cu.T024`、`/dev/cu.T02-SerialPort` | [JPR] `Sources/T02PrintTool/main.swift#L393`, `L437` | 1 実装 |
| **食い違い**: Classic は使えない | 「Classic Bluetooth / RFCOMM does **not** work with this printer; it must be BLE.」 | [LNX] `README.md#L79` | 1 実装（4 実装と食い違う） |
| TIM の既定 | SPP を優先（`"use_spp": true`） | [TIM] `printer_profiles.json#L6481`, `devices/bluetooth_policy.py#L85` | 1 実装 |
| USB | 「USB-C port on the T02 is charge-only」「The USB is power-only」 | [TAG] `README.md#L16`, `CLAUDE.md#L52`、[JEF] `README.md#L137-139` | 2 実装で一致 |
| **食い違い**: USB で印字できる | Windows の `COM3`（115200 bps）に同じ列を送って印字 | [WIN] `usbprint_t02.py#L13-14`, `L129-186`, `README.md#L1` | 1 実装 |
| 個体差 | 小売の仕様は micro USB と Type-C の両方が載っている（Web 検索結果: mediaexpert.pl / digitec.ch など） | — | 版によって USB の機能が違う可能性（**推測**） |

---

## 15. 参考: 本仕様から組み立てた最小送信例（実機未検証）

HA が実機で成功した形（§8.3）に合わせ、384 × 2 行の全黒の帯を印字する例。チャンクと間隔は §6.2 から選ぶ。

```
1b 40                       ESC @          初期化
1b 61 00                    ESC a 0        左揃え（ラスタには効かないが HA の実機成功列に合わせる）
1d 76 30 00 30 00 02 00     GS v 0  m=0  x=48 byte  y=2 行
<1 行目 48 byte>             全部 ff（1 = 黒）
<2 行目 48 byte>             全部 ff
1b 64 03                    ESC d 3        3 行送り
```

送る 112 byte を省略なしで書くと次のとおり（16 進、1 行 16 byte）:

```
1b 40 1b 61 00 1d 76 30 00 30 00 02 00 ff ff ff
ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff
ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff
ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff
ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff
ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff
ff ff ff ff ff ff ff ff ff ff ff ff ff 1b 64 03
```

合計 2 + 3 + 8 + 96 + 3 = 112 byte。この後、`1a 0f 0c` を待つか、最低 1.5 s 待ってから切断する（§12）。

---

## 16. 実装間の食い違い一覧

| # | 項目 | 食い違いの内容 | 多数派 / 実機側 |
|---|---|---|---|
| 1 | 広告されるサービス UUID | JEF・SHI・FCO は `af30`（＋`1812`）を観測、HA は「なし」 | 名前 `T02` で探す（§4） |
| 2 | `ff01` のプロパティ | read（HA・JEF の実機、M02・M02 Pro）／ notify（LNX、M08F） | read（実機 2） |
| 3 | 応答の届く characteristic | `ff03`（T02 の全実装）／ `ff01`（SGR の文書、M08F） | `ff03` |
| 4 | write の種類 | without response（HA など 7）／ with response（M5・JPR） | 両方とも T02 実機で動いた報告あり |
| 5 | 1 回の書き込み長 | 197（HA 実機）／ 128（PMY・TIM・LNX・M5）／ 182 上限（SGR）／ 20（JPR）／ ブロック丸ごと（MDS・MDM・JEF） | 128〜182 |
| 6 | 書き込み間隔 | 0 / 5 / 10 / 20 / 40 / 50 / 60 ms | 20 ms（4 実装） |
| 7 | `1f 11 02 04` の要否 | 送る 8 実装（多くは VIV の転記）／ 送らずに成功（HA 実機、VIV 現行 CUPS） | どちらでも印字できる |
| 8 | 初期化に `1b 61` を入れるか、値は 0 か 1 か | 01（8 実装）／ 00（HA 実機）／ 入れない（6 実装） | ラスタには影響しない |
| 9 | 濃度の値と対応 | TAG（1〜5、既定 4）、AIN（1/3/4）、TIM（1/2/4 + 係数 100/150） | 対応は不明 |
| 10 | ESC 7 / GS \| | PMY の T02 経路だけが送る | 効果は不明 |
| 11 | 1 ブロックの行数 | ≤255（5 実装、HA 実機）／ ≤256（行数 − 1 の旧方式を含む）／ 分割なし（PMY・TIM）／ 100・128・200・2・1 行 | ≤255 |
| 12 | 行数フィールド | 正しい行数（多数）／ 行数 − 1（VIV 旧・JEF・VRK） | 正しい行数（VIV の修正コミット e9fa4bf） |
| 13 | `0x0a`→`0x14` 置換 | する（VIV 旧・JEF・BEN・WIN・VRK）／ しない（多数） | しない |
| 14 | 上端の白行 | TIM 4 行、THEA（M02S）5 行、ほかはなし | 不明 |
| 15 | 終了列 | `1f 11 08 0e 07 09` を付ける（VIV 旧系統）／ `1b 64 n` だけ（HA 実機ほか） | `1b 64 n` だけで足りる |
| 16 | 送り量 | `1b 64` の n = 1〜4 が多い。LNX は n をドット扱い。PMY は `1b 4a 20` | `1 行` の長さは不明 |
| 17 | 電池の問い合わせ | `1f 11 08` → `1a 04`（TAG 実機・S04 実機・SGR・JEF ログ・PMY）／ `1f 11 0e` → `1a 04`（TIM） | `1f 11 08` |
| 18 | カバーの値 | `99` = 開（5 実装、実機 3）／ `98` = 開（PMY） | `99` = 開 |
| 19 | カバーの問い合わせ | `1f 11 12`（5 実装）／ `1f 11 05`（LNX） | `1f 11 12` |
| 20 | ファームウェア版の並び | 先頭から a.b.c（6 実装）／ 逆順（THEA・K0I） | 先頭から |
| 21 | `1f 11 13` の意味 | 温度（S04 実機・SGR）／ シリアル（THEA・K0I・GBL の名前） | 温度（実機） |
| 22 | `1a 0f 0c` の信頼性 | 毎回来る（S04・SGR・JEF ログ）／ 当てにならない（LNX）／ 使わない（TIM） | 待つなら時間の上限も持つ |
| 23 | 広告の継続時間 | スリープまで（HA）／ 電源投入後 30 s（JPR） | 不明 |
| 24 | Classic SPP | 使える（4 実装）／ 使えない（LNX） | 使える（BLE ドライバには無関係） |
| 25 | USB データ | 充電専用（TAG・JEF）／ COM ポートで印字（WIN） | 版による可能性 |
| 26 | 通知にペアリングが要るか | macOS で要る（JEF）／ 他は記載なし | 不明 |
| 27 | `1f 11` の高い番号 | 危険（SGR・S04）／ TIM は `38, 63, 5e, 56, 51` を送る | 送らない方が安全 |

---

## 17. 未解決の不明点（実機で確かめる項目）

1. 自分の個体が広告するサービス UUID（`af30` があるか）と、`ff01` が read か notify か。
2. 交渉される MTU と、1 回の書き込みの上限（`02 b6 00` = 182 が本当に上限か。HA の 197 は通ったが SGR の M02X では 182 超が落ちた）。
3. `01 01` が書き込み 1 回ごとに 1 回来るか（来るならフロー制御に使える）。
4. 255 行を超える `GS v 0` 1 ブロックが印字できるか。
5. `GS v 0` の `m` が 0 以外（倍角）のときの動作。
6. 幅 48 byte 未満のブロックの印字位置。
7. `1b 64 n` の 1 行の長さ（ドット数）と、`1b 4a n` の送り量。
8. `1f 11 02 n` の値と濃さの対応、`1f 11 37 c` が T02 で効くか、ESC 7 と GS \| が効くか。
9. 速度を変えるコマンドがあるか。
10. 上端の数行が欠けるか（TIM の `top_padding=4` が必要か）。
11. `1a 09 vv` の単位、`1a 04 a1〜a4` の意味、`1a 35 02`（充電）が T02 で来るか。
12. `1a 0f 0c` が毎回来るか、来るまでの時間。
13. 通知を受けるのにペアリングが要るか（使う BLE スタックで）。
14. 本体フォントでの文字印字ができるか。
15. 名前 `T02` の別機種（Funny LX 系）と区別する確実な方法（接続後に `ff00` があるかで判定する以外にあるか）。

---

## 18. 取得したソースの場所

調査時に clone した repo 群（一時領域 `<scratchpad>/research/src/`。この repo には写していない。§1 の URL と commit SHA から取り直せる） の下に 1 repo 1 ディレクトリで置いた。ディレクトリ名と repo の対応:

| ディレクトリ | repo |
|---|---|
| `ha-phomemo-t02` | alexduboiz/ha-phomemo-t02 |
| `phomemo-t02-linux` | mzramna/phomemo-t02-linux |
| `phomymo` | transcriptionstream/phomymo（履歴も取得） |
| `TiMini-Print` | Dejniel/TiMini-Print |
| `T02Protocol` | jpurnell/T02Protocol |
| `m5stick-s3-qr-phomemo` | otitbridge/m5stick-s3-qr-phomemo |
| `jeffrafter-phomemo` | jeffrafter/phomemo |
| `tagline` | iraum/tagline |
| `esp32-phomemo-gameboy-printer` | iamjackg/esp32-phomemo-gameboy-printer |
| `phomemo-tools` | vivier/phomemo-tools（履歴も取得） |
| `Phomemo-Swift` | matheusdanoite/Phomemo-Swift |
| `Phomemo-T02-for-Apple` | matheusdanoite/Phomemo-T02-for-Apple |
| `Phomemo-T02-Driver-for-macOS` | matheusdanoite/Phomemo-T02-Driver-for-macOS |
| `phomemo-t02` | benhughes/phomemo-t02 |
| `phomemowin` | yo5ptd/phomemowin |
| `Print-with-Phomemo-T02` | brunetton/Print-with-Phomemo-T02 |
| `phomemo-T02-CUPS-driver` | fcontr1975/phomemo-T02-CUPS-driver |
| `s04-phomemo` | s04/phomemo |
| `sgrankin-phomemo` | sgrankin/phomemo |
| `shiruku-shibata-Phomemo-Print` | shiruku-shibata/Phomemo-Print |
| `phomemo_m02s` | theacodes/phomemo_m02s |
| `gbl-phomemo` | gbl/phomemo |
| `ryo-endo-phomemo-printer` | ryo-endo/phomemo-printer |
| `phomemo-ble-rs` | ainehanta/phomemo-ble-rs |
| `PassionateBytes-phomemo` | PassionateBytes/phomemo |
| `Phomemo-M02-Web` | K0IN/Phomemo-M02-Web |
| `cli-phomemo-printer` | vrk/cli-phomemo-printer |
| `phomemo-print` | unixway/phomemo-print |
| `phomemo_printer` | hkeward/phomemo_printer |
| `Knightro63-phomemo` | Knightro63/phomemo |
| `phomemo-cli` | davestewart/phomemo-cli |
| `phomemo-printer-skill` | Tomatio13/phomemo-printer-skill |
| `pyphomemo` | mkuhlmann/pyphomemo |

Web 検索の出典（小売の仕様）:
- https://www.digitec.ch/en/s1/product/phomemo-t02-micro-usb-receipt-printers-53014719
- https://www.mediaexpert.pl/komputery-i-tablety/drukarki-i-urzadzenia-biurowe/drukarki-etykiet/drukarka-phomemo-t02-bialo-zielony
- https://phomemo.com/es-it/products/phomemo-t02-impresora-mini-sin-tinta-copia
