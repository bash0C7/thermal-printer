# DualKey でデバッグ情報を印字する

M5Stack Chain DualKey（ESP32-S3）のボタンを押すと、ヒープや稼働時間などのデバッグ情報を Phomemo T02 に BLE で印字します。ボタン 1（GPIO17）は赤、ボタン 2（GPIO0）は青に、2 つの LED（GPIO21、電源は GPIO40）を光らせます。待機中は暗い緑です。

| ファイル | 内容 |
|---|---|
| `app.rb` | 実機で動くアプリです。`/home/app.mrb` として転送します。 |
| `firmware/main_task.rb` | firmware の起動スクリプトです。標準の `main_task.rb` と置き換えます。 |
| `build_config/esp32-dualkey-report.rb` | firmware の gem の構成です。 |
| `build_config/dualkey_small.sdkconfig` | Wi-Fi を使わず、接続数を 1 にして静的メモリを減らす設定です。 |
| `mrbgems/dualkey-link/` | NimBLE の central 接続に、ペアリング、ATT MTU の交換、切断を足す C の mrbgem です。`DualKeyLink.pair`、`exchange_mtu`、`mtu`、`disconnect` を `app.rb` の `LinkTransport` が呼びます。 |
| `qemu/` | QEMU での確認に使うプローブです。 |

使う gem: [picoruby-debug-probe](https://github.com/bash0C7/picoruby-debug-probe)、[picoruby-text-canvas](https://github.com/bash0C7/picoruby-text-canvas)、[picoruby-phomemo-thermal-printer](https://github.com/bash0C7/picoruby-phomemo-thermal-printer)。`picoruby-debug-probe` と `picoruby-text-canvas` は、このリポジトリと同じ階層に clone します。

## 手順

```
mise exec ruby@4.0.5 -- rake vendor:setup
mise exec ruby@4.0.5 -- rake dualkey:setup        # R2P2-ESP32 を vendor/ にコピーする
mise exec ruby@4.0.5 -- rake dualkey:qemu_check   # firmware を QEMU で起動し、印字経路と app.rb を確認する
mise exec ruby@4.0.5 -- rake dualkey:flash        # ボード用に build して焼く（qemu_check の合格が条件）
mise exec ruby@4.0.5 -- rake dualkey:deploy_app   # storage を消して app.rb を .mrb にし、PicoModem で転送する
mise exec ruby@4.0.5 -- rake dualkey:wipe         # storage を消す。シェルに戻るときに使う
```

- `deploy_app` は `APP=<path>` で別のスクリプトを転送します。
- 基板は USB の製品名 `USB JTAG/serial debug unit` から探し、`ESPPORT=` で指定できます。PSRAM があるチップには書きません。
- `qemu_check` は QEMU（`esp_develop_9.2.2_20250817`）を `build/dualkey/qemu/` に取得します。QEMU には Bluetooth コントローラーがないため、BLE を使う経路は実機で確認します。ホストの負荷が高いと QEMU のシェル初期化が 900 秒を超え、`qemu_check` が FAIL になります。負荷を下げて再実行します。
- `rake test:ruby` の `SUITE=probe`、`SUITE=canvas` で 2 つの gem のテストを実行します。

## メモリ

- heap は、QEMU の確認用が 190 KB、ボード用が 206 KB です（`DK_HEAP_KB`、`DK_BOARD_HEAP_KB`）。
- アプリ開始時の空きは約 45 KB です。BLE の初期化と印字のあとは約 34 KB で安定します。
