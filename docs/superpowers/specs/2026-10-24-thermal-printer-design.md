# Phomemo T02 感熱プリンター: Mac アプリ + PicoRuby CLI 設計書

- 日付: 2026-10-24
- 状態: builder check 前のドラフト
- 対象機: Phomemo T02（53mm 幅感熱紙のミニ BLE プリンター、Amazon B0CM6H6YWN）

## 0. この文書の読み方

各決定には出どころのラベルを付ける。

- **【ユーザー決定】**: ユーザーが決めたこと。ユーザーの言葉どおりに書く。変えるときはユーザーに確認する。
- **【Claude の判断】**: ブレインストーミング中に Claude が既定値として置いたもの。ユーザーは合意していない。妥当な理由があれば builder が変えてよいが、変えたら理由を残す。
- **【builder に任せる】**: 作る人が決めてよいこと。

調査報告の原本は `docs/research/` にある（§12）。行番号つきの根拠はそちらを見る。
画面と紙面のモックアップは `docs/superpowers/specs/2026-10-24-thermal-printer-mockups/` にある（ブレインストーミングでユーザーが選んだもの）。

---

## 1. 意図と why

ユーザーは Phomemo T02 を買った。Mac から**小さな紙切れを「手に取れる物」として出す**ための道具がほしい。場面は 3 つ。

1. **朝のタスク札**: 朝、今日何をするかを考えるときに、GitHub issue や Apple リマインダー、Slack の TODO に入れた発言を 1 件 1 枚の紙にして、手元のタスク管理に使う。紙には「どこの何か」と要約と、元のページに飛ぶ QR コードが載る。
2. **対面 MTG の手渡しメモ**: 会議メモ（markdown）の要点をその場で印刷して相手に渡す。相手に渡すので、見出しや箇条書きが整って出ることが大事。
3. **記念写真**: ちょっとした相手との記念写真をその場で撮り、印刷して渡す。

【ユーザー決定】形は「**GUI でレイアウトして、CLI から印刷**」。

- GUI（Mac アプリ）: 入力を受け、紙幅の白黒画像に組み、実寸プレビューを見せる。
- CLI（PicoRuby）: 組み上がった画像を BLE でプリンターに送る。
- Phomemo の制御は mrbgem `picoruby-phomemo-thermal-printer` に切り出して抽象化する。

成功の姿: 朝に数枚のタスク札がさっと出る。会議の終わりに、見出しの整ったメモを手渡せる。写真の顔がつぶれずに出る。

---

## 2. Goals / Non-goals / Anti-goals

### Goals

- 次の入力を GUI に渡して印刷できる。
  - 文字列（直接入力）
  - クリップボードの画像
  - テキストファイル
  - markdown ファイル（レンダリングする）
  - 画像ファイル（ドラッグ）
  - URL
- markdown を「白黒の感熱プリンターにフィットするように」レンダリングする。対象は見出し、太字、斜体、リストなど。
- GitHub issue、Slack の発言、リマインダー、任意の URL を「カード」1 枚にして印刷する。
- 朝のための「今日のカード」入口を持つ。自分に assign された open issue と、今日までのリマインダーが並ぶ。
- 長すぎる出力のときに GUI で注意を出す。
- Claude Code から、repo 内の skill で Slack のカードを再現性高く作れる。
- 【ユーザー決定】gem はマイコン（Pico 2 W / ESP32）を見据えた構造にする（`ports/` 分離、行ブロック単位の API。§5.1）。
- 【Claude の判断】写真は、SwiftUI 標準の「iPhone から読み込む」（Continuity Camera）でも取り込める（§5.3.2）。

### Non-goals

- Slack の TODO の一覧の自動取得。【ユーザー決定】Slack からの取得は難しいので、**ユーザーが URL を渡す運用**にする。
- Slack アプリの作成やユーザートークンの発行。【ユーザー決定】会社の Slack では不可。
- BLE 以外のトランスポート（USB、シリアル）。【ユーザー決定】
- mruby/c（femtoruby）対応。【ユーザー決定】mruby VM 専用でよい。
- 【Claude の判断】Phomemo T02 以外の機種への対応。同じプロトコルの兄弟機は、結果として動いても保証しない。
- 【Claude の判断】レイアウトの保存と再読込（文書ファイル化）。v1 では部品リストは揮発でよい。
- 【Claude の判断】常駐 daemon による接続の使い回し。v1 は印刷 1 回 = 接続 1 回。§5.2 の速度が許せないときだけ再検討する。
- 【Claude の判断】知らない URL の中身の取得（ページタイトルの取得など）。【ユーザー決定】「知らないものは URL とその QR コードで ok」。
- 【ユーザー決定】GitHub のアカウント管理。アプリは `gh` の現在のアクティブアカウントにそのまま従う（§5.3.5）。
- 【Claude の判断】マイコン（Pico 2 W / ESP32）実機での動作確認と、`ports/rp2040`・`ports/esp32` の実装。構造は見据えるが、今回の完了条件は darwin だけ（§5.1.2）。
- 【Claude の判断】会議メモからの要点の自動抽出。要点は、ユーザーが範囲を選んでコピーし、⌘V で貼る（§5.3.2）。
- 【Claude の判断】プリンターとの常時接続。状態は必要なときだけ取り直す（§5.3.1）。

### Anti-goals（技術的に動いても、これが起きたら失敗）

1. **文字がはみ出ること**。【ユーザー決定】「ちゃんと折り返して欲しい。日本語もふくめてね」。
   - どんな入力でも、すべてのインクが印字幅の中に収まる。
   - 日本語は禁則処理をする。行頭に `、。」』）！？ー` などを置かず、行末に `「『（` などを置かない。
   - 空白を含まない長い URL や英単語は、文字単位で強制的に折り返す。切り捨てたり縮小したりはしない。
   - markdown のコードブロックやリストの深い入れ子でも同じ。
2. 【Claude の判断】黙って失敗すること。プリンターが見つからない、紙切れ、電池切れ、途中切断は、GUI に分かる言葉で出す。
3. 【Claude の判断】写真の顔がつぶれること。
4. 【Claude の判断】**プリンターを壊すこと**。兄弟機で、未知のコマンドを総当たりしたら電源が入らなくなった報告がある。§6.8 の安全規則（`1f 11` の 0x14 より上を送らない、総当たりしない、allowlist だけ）を守る。

---

## 3. 全体像

```
 入力: 文字列 / テキスト / markdown / 画像 / URL / クリップボード
        │ ドロップ・⌘V・入力欄
        ▼
 ┌──────────── Mac アプリ（SwiftUI） ────────────┐
 │ 今日のカード: gh（assign された open issue）    │ ◀── URL スキーム + カード JSON ──┐
 │              EventKit（今日までのリマインダー） │                                   │
 │ 部品リスト → レンダラ → 384 dot 幅 1bit ラスタ  │      Claude Code skill（repo 内）│
 │ 実寸プレビュー / 長さ表示 / 警告               │      Slack 連携で本文・channel 名・│
 └───────────────┬───────────────────────────────┘      投稿者・日時 → 要約 ───────────┘
                 │ PBM（P4）ファイル（CLI は行ブロック単位で読む）+ 結果ファイル
                 ▼
 PicoRuby CLI（bin/phomemo-print → picoruby cli/print.rb）
                 │ require 'phomemo_thermal_printer'
                 ▼
 mrbgem picoruby-phomemo-thermal-printer
   ├ mrblib/        共通層（純 Ruby・OS 非依存: コマンド組み立て、行ブロック単位の送出、ステータス decode）
   └ ports/darwin/  BLE トランスポート（picoruby-ble darwin 版の癖をここに閉じ込める）
                    （将来 ports/rp2040・ports/esp32 を足せる形。今回は作らない）
                 │ BLE（write without response / notify）
                 ▼
 Phomemo T02
```

レンダリング（文字組み、markdown、ディザリング、QR）はすべて Mac アプリが担う。PicoRuby 側には PNG デコードも zlib もフォント描画も無い（`docs/research/r2p2-darwin-and-gems.md` §6）。CLI は「1bit ラスタを受け取って送るだけ」にする。

---

## 4. 制約（事実）

### 4.1 この Mac の環境（2026-10-24 に確認）

- macOS 27.0.1、Xcode 27.1、Swift 6.4（`/usr/bin/swift`）、arm64。
- `gh` はインストール済み。【ユーザー決定】どのアカウントでログインしているかは気にしない。アプリはアカウントを管理せず、`gh` の現在のアクティブアカウントに従う（§5.3.5）。
- brew `openssl@3`、`xcodegen` あり。
- **シェルの `ruby` は 2.6.10（システム Ruby）**。PicoRuby のビルドには Ruby 3.4 以上が要る。mise に 4.0.3 / 4.0.4 / 4.0.6 は入っている。R2P2-darwin の `.ruby-version`（4.0.5）は未インストール。
- swiftly の swift が PATH で Xcode の swift より先に来ると、picoruby-ble の Swift package がビルドできない（`unknown argument: '-target-arch-variant'`）。
- Apple Foundation Models（オンデバイス LLM）は macOS 26 以降で使える。Apple Intelligence が無効な環境では使えないので、代替経路が要る（§5.3.6）。

### 4.2 PicoRuby / R2P2-darwin（詳細は `docs/research/r2p2-darwin-and-gems.md`）

- 【ユーザー決定】次を活用する。
  - https://github.com/bash0C7/R2P2-darwin
  - https://github.com/bash0C7/R2P2-dev-harness
  - https://github.com/bash0C7/picoruby/tree/port-darwin
- R2P2-darwin は `rake setup` で fork `bash0C7/picoruby` の `port-darwin` を `vendor/picoruby` に clone し（約 1.2GB）、`rake macos:build` で `build/host/bin/picoruby` を作る。`MRUBY_CONFIG=<絶対パス>` で、repo 外の build_config を渡せる。
- 【ユーザー決定】`port-darwin` は commit を固定せず、**ブランチの先頭に追従する**。R2P2-darwin の `rake setup` は先頭を clone し、`rake refresh` は先頭を fetch する前提にする。
- `picoruby script.rb args...` で `ARGV` / `ENV` / `$stdin` / `exit(n)` が使える。未処理例外は終了コード 1 になる。
- 外置き gem は `conf.gem gemdir: "<絶対パス>"` で組み込める。前例は `stackchan-picoruby`。これが「Mac 上の PicoRuby CLI + BLE central + 外置き gem」の完成形なので、ビルドの段取りはこれを手本にする。
- gem の作法:
  - 構成: `mrbgem.rake`（name / license / author 必須、**ASCII のみ**）+ `mrblib/` + `sig/*.rbs` + `test/*_test.rb`
  - テスト: picotest。upstream の test runner は外置き gem を拾わないので、自前の runner が要る。前例は R2P2-dev-harness の `rakelib/test.rake` と、stackchan の `test/picotest/harness.rb`。
  - ライブラリ gem 内は `each` / `times` を避けて `while` を使う（picoruby `AGENTS.md`）。
- **`picoruby-ble` に `add_dependency` した gem を host テスト VM に焼くと、darwin port（`swift build`）が要る。** 流儀は「プロトコルは素の class、BLE は薄い adapter に隔離」。
- R2P2-dev-harness は Pico 2 W / ESP32 の実機向けで、macOS CLI の基盤にはならない。借りるのは gem の置き方、host テストの回し方、規律だけ。その `rake setup` を darwin 用の tree に流してはいけない（古い compiler pin を強制する）。
- ローカルの `~/ghq/github.com/bash0C7/picoruby` は `master` が checkout されている。ビルドは R2P2-darwin の vendor clone を使うので影響は無い。

### 4.3 picoruby-ble の darwin 実装（詳細は `docs/research/picoruby-ble-darwin.md`）

結論は「一部足りないが、印刷はできる見込み」。

- **できること**
  - scan → connect → 自動発見 → `write_value_of_characteristic_without_response` → CCCD に `"\x01\x00"` を書いて notify 購読 → 0xA7 パケットで notify 受信、の一連が動く。
  - stackchan が、180 byte を 20ms 間隔で送る形で実運用している。
- **足りないこと（新 gem の側からは足せない）**
  - フロー制御が無い（`canSendWriteWithoutResponse` / `peripheralIsReady` 未使用）。
  - 1 回の write の最大長（`maximumWriteValueLength`）が取れない。
  - write の戻り値は常に 0。
  - write with response が無い。
  - 切断 API が無い。
  - CCCD 書き込みの完了イベントが来ない。
- **罠**
  - `hal-task-darwin` を build_config に明示しないと、まれにハングする。R2P2-darwin の BLE config には入っていない。
  - `scan` の後に `scan` / `start` を呼ぶと接続が切れる。
  - 切断は `[0x3E,0x01,0x05]` で来て、共通 decoder は拾わない。
  - `scan` には必ず `timeout_ms` を付ける。
  - notify は自前で decode する（255 byte で切り詰め）。
  - UUID は `uuid128` で照合する。
  - ADV に service UUID が載らないので、名前で絞るしかない。
  - 発見時に、読めるものを全部 read する。
- 【ユーザー決定】上の「足りないこと」と「罠」への回避策は、すべて gem の `ports/darwin` に閉じ込める（§5.1）。
- **TCC（Bluetooth 権限）**: 食い違いがあり、未検証。
  - 「CoreBluetooth を使う picoruby をシェルから直接 exec すると SIGABRT」（R2P2-darwin、stackchan の README）
  - 「ターミナルの許可で直接動く」（port README、stackchan CLAUDE.md）
  - 「`-sectcreate` で Info.plist を埋め込めば bare CLI でも通る」（picoruby `darwin-ble-test.rb`）
  
  実績のある組み方は、`.app` + Info.plist の `NSBluetoothAlwaysUsageDescription` + `codesign -s - -r='designated => identifier "<id>"'`（要件を bundle id に固定しないと、再ビルドのたびに許可が消える）+ `open -W -a`（stdin が使えず、exit code の伝搬も未確認）か launchd で起動する形。

### 4.4 Slack（詳細は `docs/research/slack-connector-probe.md`）

- 【ユーザー決定】自分用の Slack アプリを作ってユーザートークンを発行するのは無理。Mac アプリ単体では、Slack の発言本文を取れない。
- Claude Code の claude.ai Slack 連携（`mcp__claude_ai_Slack__*`）なら、permalink 1 本から本文・channel 名・投稿者・日時が取れる。手順は確認済み（§5.4）。

---

## 5. 構成要素ごとの設計

### 5.1 mrbgem `picoruby-phomemo-thermal-printer`

【ユーザー決定】

- mrbgem として Phomemo の制御を抽象化する。
- mruby 専用。
- トランスポートは BLE のみ。
- picoruby-ble に依存する。
- **マイコン（Pico 2 W / ESP32）を見据える。** 他の mrbgem と同じく `ports/` ディレクトリを作り、darwin 依存部分は `ports/darwin` に固める。
- 印刷データは**行ブロック単位で流す API**にする。ジョブ全体を 1 本の String に組まない。
- darwin 固有の回避策は `ports/darwin` 側に閉じ込める。対象は次のとおり。
  - write の戻り値が常に 0
  - CCCD 書き込みの完了イベントが無い
  - uint8 の合成 handle
  - 切断パケット `[0x3E,0x01,0x05]` の判定
  - `scan` 後の `pop_and_dispatch` 自前ループ
  - その他の §4.3 の罠
- picoruby の `port-darwin` は commit を固定せず、ブランチの先頭に追従する。進行中の BLE 共通 API の変更（pr427: `start` のポーリング化、`BLE_push_event` の戻り値変更など）が入っても、影響が `ports/darwin` の中で収まる構造にする。

（ユーザーの綴りは `picoruby-phomeno-thermal-printer` だったが、機種名 Phomemo の誤記と解釈して `phomemo` にする。【Claude の判断】）

#### 5.1.1 構成

```
mrbgems/picoruby-phomemo-thermal-printer/
  mrbgem.rake          # ASCII のみ。add_dependency 'picoruby-ble'
  mrblib/              # 機種・OS に依存しない層（picoruby-ble も参照しない）
  ports/
    darwin/            # macOS の picoruby-ble（CoreBluetooth）向けトランスポート
                       # （将来 rp2040/ esp32/ を足せる形。今回は作らない）
  sig/
  test/
```

- **`mrblib/`（共通層。BLE を知らない、純 Ruby）**
  - §6.4 のジョブを組み立てる。ただし**行ブロック単位で送り出す**。
    1. 前置き: `1b 40` → `1b 61 00` → `1f 11 02 nn`
    2. 255 行以下の `GS v 0` ブロックを、1 つずつ作っては渡す。ヘッダ 8 byte + 48×y byte。
    3. 後置き: `1b 64 03`
    
    入力は「行ブロックを順に返すもの」（例: PBM ファイルから行を読む reader）で、ジョブ全体のバイト列を一度にメモリに持たない。
  - ステータス問い合わせ（§6.7）を組み立て、`ff03` の通知を decode する。電池、紙、カバー、過熱、印字完了、取り消し、`01 01`、`02 b6 00` が対象。連結された通知にも対応する。
  - **§6.8 の allowlist にあるコマンドしか組み立てない**。任意バイト列の送信 API は持たない。
  - ブロックをチャンクに分け、ペーシング（sleep）と完了待ち（§6.6）を行う。時計と sleeper は注入する。
  - 印刷の流れ（事前のステータス確認 → 送信 → 完了待ち）を、下の「トランスポート契約」だけを使って書く。
- **トランスポート契約（mrblib で定め、各 port が実装する）**【Claude の判断】
  - 次の 6 つの操作を持つ。メソッド名と形は【builder に任せる】。
    1. 名前の前方一致で探して接続する（タイムアウト付き）
    2. `ff00` / `ff02` / `ff03` の確認結果を返す
    3. notify を購読する
    4. 1 チャンクを write する
    5. 届いた notify を取り出す（ブロックしない）
    6. 切断する（できない port では何もしない）
  - 契約の外に picoruby-ble の内部（`@event_queue`、`_event_popped`、`@conn_handle`、パケットの形）を漏らさない。
- **`ports/darwin/`（darwin 版 picoruby-ble 専用）**
  - `class ... < BLE` のサブクラスで契約を実装する。手順:
    1. 名前の前方一致 `T02` で scan → connect → 発見。
    2. `uuid128` で `ff00` / `ff02` / `ff03` を引く。揃わなければ別機種として中止する（§6.1）。
    3. `ff03` の CCCD を購読する。完了通知が来ないので、一定時間 drain しながら待つ。
    4. `scan` が戻った後は、`pop_and_dispatch` 相当の自前ループで、write と notify の受け取りを回す。
    5. notify（0xA7）を自前で decode する。
  - 切断は `[0x3E,0x01,0x05]` と `[0x05,...]` の両方を判定する。
  - write の戻り値（常に 0）を信用しない。
  - 手本は stackchan-picoruby の `picoruby-stackchan-controller`（`radio.rb` / `central.rb` / `gatt.rb`）。
  - **picoruby-ble の内部に触るコードは、ここにだけ置く**。`port-darwin` の先頭が変わって壊れたら、直すのはここだけで済むようにする。
  - Ruby のファイルを `ports/darwin` に置いて、darwin のビルドのときだけ組み込む方法は【builder に任せる】。ただし、picoruby の既存 gem に前例があればそれに合わせる。無ければ `mrbgem.rake` で `build.darwin?` のときに `ports/darwin` の `.rb` を足す、など最小の仕掛けにする。

#### 5.1.2 マイコン実機について

【Claude の判断】マイコン（Pico 2 W / ESP32）実機での確認は、今回の完了条件に入れない。`ports/rp2040`・`ports/esp32` も作らない。

共通層が darwin に依存していないことは、次の 2 点で担保する。

- BLE を含まない host のテスト VM で、共通層のテストが通ること（§5.1.3）。
- ジョブを行ブロック単位で流すこと（メモリを食わない）。

#### 5.1.3 依存・テスト・送信の方針

【Claude の判断】

- 依存の置き方
  - gem の `mrbgem.rake` に `spec.add_dependency 'picoruby-ble'` を書く（ユーザー指示どおり）。
  - テストは stackchan 方式にする。`mrblib/` の source を、BLE を含まない test VM に埋め込み、契約を満たす fake トランスポートを注入する。
  - `ports/darwin` のうち、パケットの decode や切断判定のように無線なしで確かめられる部分は、合成したバイト列で単体テストする。picoruby-ble の `decoder_contract_test.rb` が前例。
- 送信の方針
  - picoruby-ble は今のまま使う（決め打ちチャンク長 + 毎チャンク `sleep_ms`）。
  - 初期値は **128 byte / 20 ms**（§6.5）。根拠は、4 実装で一致し、`02 b6 00` から推測される上限 182 より下にあること。
  - `02 b6 00` 形式の通知が来たら、その値を上限にする。実機で問題が無ければ、182 byte・10 ms まで詰めてよい。
  - 実機で取りこぼしや印字欠けが出て、`port-darwin` 自体に API（フロー制御・最大 write 長・write 結果・切断）を足す必要があると判断したら、**その時点でユーザーに相談する**。
  - gem 内で独自に CoreBluetooth を叩く案は、「picoruby-ble に依存」に反するので採らない。
- 公開 API の名前と形は【builder に任せる】。ただし次の 3 点は守る。
  - 入力は行ブロックの列にする。
  - 1 ブロックは 255 行以下にする。
  - allowlist 外のバイト列を作る口は持たない。

### 5.2 CLI

【Claude の判断】

- 入口
  - `bin/phomemo-print`（sh ラッパー）が picoruby で `cli/print.rb` を exec する。stackchan の `bin/stackchan` と同じ形。
- 入力
  - **PBM P4（1bit、幅 384 dot）ファイルのみ**。PicoRuby に PNG デコードが無いため。
  - 【Claude の判断】PBM は**行ブロック単位で読み**（ヘッダの後を 48 byte × 255 行以下ずつ）、そのまま gem に流す。ファイル全体を 1 本の String にしない。
  - アプリが作る。手で作った PBM を直接渡してもよい。
- オプション（名前は【builder に任せる】）
  - デバイス名の絞り込み（既定は前方一致 `T02`。§6.2）
  - 濃度（`1f 11 02 n` の n。01〜05、既定 04。§6.4）
  - チャンク長と間隔（既定 128 byte / 20 ms。§6.5）
  - `--dry-run`: BLE に触らず、送るはずのバイト列を hex で出す。テストと実機なし開発用。
  - `--status`: ステータス（電池・紙・カバー・温度・版・シリアル）だけを問い合わせて表示する。接続 → 問い合わせ → 切断で終わり、常時接続はしない。
  - 結果ファイルのパス
- 出力
  - `open -W -a` 経由では stdout と exit code が取れない可能性があるので、**結果を JSON ファイルにも書く**。
  - 中身は、成否、エラー種別、電池残量など取れたもの。
  - エラー種別: not_found / wrong_device / busy / timeout / paper_out / cover_open / overheat / low_battery / print_failed / canceled / disconnected / status_unavailable / unknown。
  - not_found のときは、「電源ボタンで起こす」「公式アプリの接続を切る」という手がかりを添える（§6.2）。
  - 直接実行できる経路では、exit code も返す。
- 起動経路（TCC）: M0 の spike で次の 4 つを試し、通ったものを採る。
  1. 直接 exec
  2. `.app` 化 + `open -W -a ... --args`
  3. `-sectcreate` で Info.plist を埋め込む
  4. **Mac アプリが自分の bundle に同梱した picoruby を子プロセスとして起動する**（責任プロセスが `NSBluetoothAlwaysUsageDescription` を持つアプリになるので、通る見込みがある。未検証）
  
  4 が通れば、アプリからの印刷はそれでよい。ターミナルから直接叩く用途は、2 か 3 で別に確保する。
- 1 回の起動で 1 ジョブ（PBM 1 枚。カード複数枚もアプリが 1 本の帯に連結する）を印刷して終了する。
  - 終了は、送信直後ではなく §6.6 の完了待ちの後にする（プロセスの終了 = 切断）。
  - 連続して起動するときは、1.5 秒以上空ける。
- 【Claude の判断】排他: CLI は同時に 1 プロセスだけ動く（ロックファイルなど）。印刷中に `--status` が来たら、待たずに `busy` で失敗する。T02 は 1 台にしか接続できないため。

### 5.3 Mac アプリ

【Claude の判断】

- 基本
  - SwiftUI、macOS 27 ターゲット、Swift 6.4。
  - アプリ名は仮に "Thermal Printer"、bundle id は `com.bash0c7.thermalprinter`、URL スキームは `thermalprinter://`。
  - プロジェクトの作り方（xcodegen か SwiftPM か）は【builder に任せる】。
- 権限: Bluetooth（§5.2 の経路 4 を使う場合）、リマインダー（EventKit のフルアクセス）、ネットワーク不要。「iPhone から読み込む」にカメラ権限（`NSCameraUsageDescription` など）が要るかは【builder に任せる】（確かめて、要るなら足す）。

#### 5.3.1 画面

【ユーザー決定】**C: 3 ペイン（「今日のカード」入口つき）**。モックアップは `2026-10-24-thermal-printer-mockups/app-window.html` の C。

- **左「今日のカード」**
  - GitHub: 自分に assign された open issue（`gh search issues --assignee @me --state open` 相当。`@me` はその時の `gh` のアクティブアカウント）。
  - リマインダー: 今日まで（期限切れを含む）の未完了。
  - チェックすると、中央の部品リストに入る。更新ボタンがある。Slack はここに出ない（skill 経由で部品に入る）。
- **中央「部品リスト」**
  - ドロップ / ⌘V で追加する。ドラッグで並べ替え、削除する。
  - 選んだ部品の設定を出す（例: 写真の明るさ・コントラスト・ガンマ）。
- **右「実寸プレビュー」**: 実際に印字される 1bit ビットマップそのものを表示する（近似の別描画ではない）。
- **フッター**: 長さ（cm）、警告、濃度、印刷ボタン。
- **タイトルバー**: プリンターの状態（電池、紙、カバー、温度。§6.7）。
  - 【Claude の判断】常時接続しない。アプリの起動時、手動の更新ボタン、印刷の後に `--status` で取り直す。
  - 表示には確認時刻を添える（例「電池 83%・紙あり（10:42 確認）」）。
  - 印刷との排他は CLI 側で行う（§5.2。印刷中は `busy` が返るので、表示を古いままにする）。

長さの警告:

- 【ユーザー決定】長すぎる出力のとき GUI で注意を出す。
- 【Claude の判断】長さは常に表示する。既定 30cm を超えたら、フッターに警告を出す。さらに印刷ボタンを押したときに確認ダイアログを出す。閾値は設定で変えられる。長さは 1bit ビットマップの高さから計算する（203dpi = 8 dot/mm なので、mm = 行数 ÷ 8。§6.4）。

#### 5.3.2 入力と部品の種類

【ユーザー決定】の入力すべてを受ける。部品の種類は次のとおり。【Claude の判断】

| 部品 | 入り方 | 描画 |
|---|---|---|
| テキスト | 入力欄に文字列を打つ、`.txt` のドロップ | 本文フォントでそのまま組む。文字サイズ 小 / 中 / 大 |
| markdown | ⌘V のテキスト（URL だけのものを除く）、`.md` のドロップ（ファイル丸ごと） | §5.3.3。部品ごとに「プレーンテキストとして組む」へ切り替えられる |
| 画像 | 画像ファイルのドロップ（HEIC / JPEG / PNG など ImageIO が読めるもの）、⌘V の画像、「iPhone から読み込む」 | §5.3.4 |
| カード | URL のドロップ / ⌘V、今日のカード、URL スキーム | §5.3.5 |

【Claude の判断】

- **会議メモの「要点」**: エディタで要点の範囲を選んでコピーし、⌘V で貼る。貼ったテキストは markdown 部品になる。`.md` ファイルのドロップは丸ごと 1 部品になる。要点の自動抽出は作らない。
- **写真の取り込み**: ドロップと ⌘V に加えて、SwiftUI 標準の「iPhone から読み込む」（Continuity Camera。`ImportFromDevicesCommands` などでメニューに出す）を付ける。iPhone で撮った写真が、その場で画像部品として入る。
- ⌘V の振り分け: 画像なら画像部品、URL 1 本だけのテキストならカード部品、それ以外のテキストは markdown 部品。

部品と部品の間には切り取り線（破線）と余白を入れる。帯の最後には、印字がティアバーを越えるだけの紙送りを入れる（量は実機で決める）。

#### 5.3.3 markdown の描画

【ユーザー決定】**A: ミニマル**（`2026-10-24-thermal-printer-mockups/markdown-style.html` の A）。見出し、太字、斜体、リストなどを、白黒の感熱プリンターにフィットするようにレンダリングする。

- H1: 大きく極太。
- H2: 太字に下線（太い罫線）。
- 太字: 極太。
- 斜体: 字を傾ける。日本語フォントには italic が無いので、合成した oblique を使う。
- リスト: 素直な黒丸。
- チェックボックス: `☐` / `☑`。
- 引用: 左に太い縦線。

【Claude の判断】

- H3〜H6 は H2 より一段小さい太字で、下線なしにする。
- 順序付きリスト、入れ子のリスト、区切り線（太い実線）、インラインコード（等幅フォント）、コードブロック（等幅フォント、**折り返す**）に対応する。
- リンクは表示テキストだけを出す（インラインのリンクには QR を付けない）。
- 表は v1 では「セル | セル」の行に崩して出し、折り返す。
- markdown 内の画像参照は、ローカルパスなら画像部品と同じ処理で埋め込む。
- フォントは Hiragino Sans の太いウェイトを基本にする（細い字は感熱紙でかすれる）。
- 文字は、アンチエイリアスで描いてから**しきい値で 2 値化**する（ディザしない。文字が砂目にならないように）。
- パーサーには swift-markdown などの CommonMark + GFM（タスクリスト、表）対応のものを使う。選定は【builder に任せる】。

#### 5.3.4 写真

【ユーザー決定】**誤差拡散（Floyd–Steinberg）**。明るさ・コントラスト・ガンマを印刷のたびに調整できる。

【Claude の判断】

- 調整の既定値は中立（明るさ 0、コントラスト 1.0、ガンマ 1.0）。
- 輝度は `0.299R + 0.587G + 0.114B`。
- 調整の順は、ガンマ → コントラスト（128 中心）→ 明るさ。
- 幅 384 dot にリサイズしてからディザする。モックアップの実装（`2026-10-24-thermal-printer-mockups/photo-dither.html` の JS）が参照実装。
- 縦横の回転ボタンを持つ。
- 感熱紙は実際には濃く出やすいので、既定値は実機で見て調整してよい。

#### 5.3.5 カード

【ユーザー決定】レイアウトは **B: QR は右上に**（`2026-10-24-thermal-printer-mockups/card-layout.html` の B）。

- 上段: 左に出どころ情報、右に QR。
- その下: タイトル（大きく太く）、概要、「最新コメント」見出し付きの要約、を全幅で並べる。
- カードとカードの間に切り取り線。

URL の種類ごとの扱い（【ユーザー決定】「URL は、gh などコマンドラインでサポートするものはそれで取得し、知らないものは URL とその QR コードで ok。Slack はその中間」）:

| URL | 取得 | カードに載るもの |
|---|---|---|
| GitHub issue `https://github.com/<owner>/<repo>/issues/<n>` | `gh issue view <n> -R <owner>/<repo> --json ...` | 上段: `org/repo`、大きく `#番号`、状態・更新日時 / QR: issue の URL / タイトル / 概要の要約 / 最新コメントの要約（Foundation Models） |
| Slack permalink `https://<ws>.slack.com/archives/<C…>/p<16桁>[?thread_ts=…&cid=…]` | 取得しない（アプリ単体） | 上段: workspace（サブドメイン）、channel ID（名称は不明）、日時（ts を JST の日付・時刻に変換）/ QR: その URL |
| Slack（skill 経由） | Claude Code の Slack 連携（§5.4） | 上段: workspace、`#channel 名`、日時（【Claude の判断】取れれば投稿者名も）/ QR / タイトル（発言要約の 1 行）/ 要約 |
| 知らない URL | 取得しない | URL の文字列（強制折り返し）と QR |
| リマインダー（今日のカード） | EventKit | 【Claude の判断】QR なし。上段: リスト名と期限。タイトル: `☐ ` + 件名。メモがあれば本文として折り返す |

【Claude の判断】

- GitHub
  - 【ユーザー決定】アプリは GitHub のアカウントを管理しない。`gh` の現在のアクティブアカウントにそのまま従う。
  - PR の URL（`/pull/<n>`）も `gh pr view` で同じ形にする。
  - `gh` で取れない（未ログイン、そのアカウントに権限なし、404）ときは、知らない URL と同じカードに落とし、理由を部品に小さく出す。
  - 「コマンドラインでサポートするもの」は、URL パターンと取得方法の組を差し込める形（URL ハンドラの登録表）にする。v1 で入れるのは GitHub だけ。
- Slack の ts 変換
  - `p` を除いた 16 桁を、前 10 桁（秒）と後 6 桁（マイクロ秒）に分けて、JST に直す。
  - スレッド返信の URL（`thread_ts` 付き）も、QR には URL をそのまま使う。
- QR
  - CoreImage `CIQRCodeGenerator`、誤り訂正 M。
  - 1 モジュールを整数 dot に拡大し、補間しない。
  - 一辺 128 dot 前後（約 16mm）を目安にする。URL が長くてモジュールが細かくなりすぎる場合は、上段の高さを伸ばしてでも 1 モジュール 3 dot 以上を保つ。
- カード JSON（skill → アプリ、および内部表現）:

```json
{
  "version": 1,
  "kind": "github | slack | url | reminder",
  "url": "QR にする URL。reminder は null",
  "header": {
    "lines": ["bash0C7/thermal-printer"],
    "emphasis": "#12",
    "sublines": ["open ・ 更新 2日前"]
  },
  "title": "長い出力のときに GUI で警告を出す",
  "sections": [
    { "label": null, "text": "概要の要約" },
    { "label": "最新コメント", "text": "最新コメントの要約" }
  ]
}
```

  - Slack なら `lines: ["<workspace>"]`、`emphasis: "#<channel 名>"`（アプリ単体なら channel ID）、`sublines: ["2026/10/23(金) 15:42", "<投稿者>"]` になる。
  - 細部の項目名は【builder に任せる】が、**アプリと skill で同じスキーマを使い、スキーマの検証をアプリ側に持つ**。

#### 5.3.6 要約（Foundation Models）

【ユーザー決定】GitHub の概要と最新コメントの要約に Foundation Model やテキスト処理系の機械学習 API を使えるとなおよい。

【Claude の判断】

- `FoundationModels` の `LanguageModelSession` で、日本語の要約を作る。目安は概要 3 行以内、最新コメント 2 行以内。最新コメントには相対日時（「2日前」）を付ける。
- コメントが無ければ、「最新コメント」の節を出さない。
- モデルが使えない（Apple Intelligence が無効、未対応言語、エラー）ときは、本文の先頭を文字数で切って「…」を付けたものに落とす。そのことを部品に小さく表示する。
- 要約の結果はアプリ内でキャッシュしてよい。

#### 5.3.7 文字組み（anti-goal 対策）

- すべてのテキスト描画は、印字幅（384 dot から左右の内側余白を引いた幅）で組む。
- 禁則処理: CoreText / TextKit の日本語の改行規則を使う。
- 空白の無い長いトークン（URL、長い英単語、長い数字列）は、文字単位で強制的に折り返す。
- 【Claude の判断】左右の内側余白の初期値は 8 dot。実機で調整する。
- テストで保証すること（TDD）:
  - 長い URL、長い英単語、句読点や括弧の多い日本語、深い入れ子のリスト、長いコードブロックを描いて、印字幅の外にインクが無い。
  - 行頭禁則の文字で始まる行が無い。

### 5.4 Claude Code skill（Slack カード）

【ユーザー決定】

- この repo に SKILL を用意して、Claude Code からの再現性を高める。
- Slack の中身入りカードは、skill に Slack の URL を渡すと、Claude が Slack 連携で本文・channel 名・投稿者・日時を取って要約し、アプリの部品リストに追加する。

【Claude の判断】

- 置き場所は `.claude/skills/<名前>/SKILL.md`（名前は【builder に任せる】、例: `print-slack-card`）。
- 入力は Slack の URL 1 本以上。手順は `docs/research/slack-connector-probe.md` §6 を正とする。
  1. permalink を分解する。ts は整数で ±1µs を計算する（浮動小数点を使わない）。
  2. 非スレッド: `slack_read_channel(channel_id, oldest=ts-1µs, latest=ts+1µs, response_format="detailed")`。返却ヘッダから channel 名を取る。
  3. スレッド返信: `slack_read_thread(channel_id, message_ts=thread_ts, oldest/latest で ±1µs)` で本文を取り、channel 名は `slack_read_channel` を別に 1 回呼んで取る。
  4. 投稿者名を安定させたいときは `slack_read_user_profile`。
  5. Slack 記法を前処理する。`<@U…|名前>` → `@名前`、`<#C…>` → `#名前`、`<URL|ラベル>` → ラベル、`:emoji:` → 削除、`<!here>` など → 平文。
  6. Claude が要約を作る（タイトル 1 行 + 本文の要約）。
  7. カード JSON を作り、`open "thermalprinter://add?..."` でアプリに渡す。受け渡しの形（base64url の JSON をクエリに入れるか、一時ファイルのパスを渡すか）は【builder に任せる】。
- 印刷ボタンはアプリ側で押す（GitHub やリマインダーのカードと一緒に出せるように）。
- 失敗の区別:
  - `channel_not_found` は、未参加の private channel か別 workspace。
  - 0 件は、ts の誤変換か削除済み。
  
  理由をユーザーに伝える。
- `slack_search_public_and_private` は使わない（URL を渡す運用なので要らない。使うなら同意が要る）。
- skill は、上の手順・JSON スキーマ・前処理の規則を本文に明記し、毎回同じ結果になるようにする。

---

## 6. Phomemo T02 プロトコル（実装に使う確定仕様）

根拠は `docs/research/phomemo-t02-protocol.md`（以下「調査書」）。既存のオープンソース実装 17 件（T02）と兄弟機 12 件を、1 byte 単位で読み比べたもの。各項目に確度ラベルを付ける。

- **実機**: その実装が T02 実機で確認したと明記している。
- **N 実装**: 独立した N 実装で一致。
- **推測**: 根拠から導いた値。
- **兄弟機**: M02 系の根拠しかない。

ここに書いた値で gem を実装し、§8 の「実機確認チェックリスト」で確かめる。数値は 16 進、多バイト整数はリトルエンディアン。

### 6.1 系統の区別（混同しない）

- 本機は **Phomemo ESC/POS 系**（GATT サービス `ff00`、コマンドは `1b 40` / `1d 76 30 …` / `1f 11 xx`）。
- **"cat printer" 系**（`51 78 <cmd> 00 <len> … <crc8> ff` のフレーム、サービス `ae30` など）とは別物。混ぜない（調査書 §2）。
- **名前が `T02` でも別ベンダの機械がある**。Funny Print LX 系は、サービス `ffe6`、write `ffe1`、notify `ffe2` を使う（TiMini-Print のデータ）。名前だけで本機と決めない。

【Claude の判断】接続して発見を終えたら、サービス `ff00` と characteristic `ff02` / `ff03` が揃っているかを確かめる。揃っていなければ「T02 という名前の別機種」として、何も送らずにエラーにする（CLI の結果は `wrong_device`）。

### 6.2 発見と接続

| 項目 | 値 | 確度 |
|---|---|---|
| アドバタイズ名 | `T02` | 6 実装（実機 3） |
| 名前の照合 | 前方一致 `T02`（HA・LNX）。`T02E` / `C02E` という互換名もある | 実装ごとに異なる |
| 広告にサービス UUID が載るか | **`ff00` は載らない**（実機 2）。`af30` / `1812` は観測が割れる | 食い違い（調査書 §4.2） |
| ペアリング | write には不要（実機 2）。**macOS では notify に必要**（`Notify failed: Encryption is insufficient.`、JEF） | write は 2 実装、notify は 1 実装（macOS 実機） |
| 同時接続 | 1 台だけ。公式アプリなどの接続を切っておく | 2 実装 |
| スリープ | 自動スリープ中は広告しない。ソフトでは起こせない | 1 実装（実機） |

picoruby-ble の darwin 実装は、ADV に service UUID を載せない（§4.3）。そのため、どのみち**名前 `T02` の前方一致で探す**のが唯一の方法で、上の事実と合っている。

### 6.3 GATT

| UUID（`0000xxxx-0000-1000-8000-00805f9b34fb`） | プロパティ | 用途 | 確度 |
|---|---|---|---|
| サービス `ff00` | — | 印字用ベンダサービス | 9 実装（著者別 7、実機ダンプ 2） |
| `ff02` | write と write without response | ホスト → プリンターの全データ | 9 実装（プロパティは実機 2） |
| `ff03` | notify（CCCD あり） | プリンター → ホストの応答とイベント | 7 実装（実機 2） |
| `ff01` | read（実機 2）/ notify（1 実装） | 不明。使わない | 食い違い |

ATT handle は機種や個体で違う。**必ず UUID（`uuid128`）で引く**。

write の種類は、without response（HA ほか 7 実装、実機あり）と with response（M5、実機あり）の両方で T02 が動いた報告がある。picoruby-ble は without response しか出せないので、without response を使う。

### 6.4 印字ジョブのバイト列

【Claude の判断】既定のジョブは、**HA が実機で成功した最小手順**を骨格にする。そこに、公式アプリが常に送る濃度コマンドを入れる。

```
1b 40                        ESC @           初期化                         14 実装
1b 61 00                     ESC a 0         左揃え（ラスタには効かない）   HA 実機の列に合わせる
1f 11 02 nn                  濃度            nn は 01〜05、既定 04          8 実装（多くは転記）。HA 実機は送らずに成功
（ラスタブロックを繰り返す）
1d 76 30 00 30 00 yL yH      GS v 0          m=0、1 行 48 byte、y 行        全 BLE 実装
<48 × y byte>
1b 64 03                     ESC d 3         印字して 3 行送る              HA 実機
```

ラスタの規則:

| 項目 | 値 | 確度 |
|---|---|---|
| 1 行 | **384 dot = 48 byte**、全幅で紙の両端に届く | 10 実装（HA 実機） |
| 解像度 | **203 dpi = 8 dot/mm**（縦横とも）。紙の長さ（mm）= 行数 ÷ 8 | 5 実装 |
| ビット順 | 1 byte に 8 dot、**MSB が左端** | 全実装 |
| 色 | **ビット 1 = 黒**、0 = 白 | 全実装 |
| 行の順 | 上（先に紙から出る側）から | 全実装 |
| `m` | **`00` 固定**（0 以外の動作は不明） | 全実装 |
| 1 ブロックの行数 | **1〜255 行**。それを超えたらブロックを分けて `GS v 0` を付け直す | 5 実装（HA 実機） |
| 行数フィールド | **実際の行数をそのまま書く**（`- 1` しない） | 多数派。vivier の修正 e9fa4bf に従う |
| `0x0a` の置換 | **しない**（データ中の `0a` を `14` に置き換える古い回避策は、行数を 1 少なく書いていた旧バグの副作用への対処） | 多数派。e9fa4bf に従う |
| 幅 | 常に 48 byte の行を送る。左右の余白はホスト側で白（`00`）として埋める | 多数派 |

- **終了**: `1b 64 n` だけで足りる（HA 実機）。古い実装が末尾に付ける `1f 11 08 / 0e / 07 / 09` はステータス問い合わせで、印字には不要。
- `1b 64 n` の「1 行」が何 dot かは不明。【Claude の判断】切り取りのための余白は、アプリが画像の末尾に白い行（dot 単位で正確）として足す。CLI は最後に `1b 64 03` だけを送る。
- 上端の数行が欠けるか（TiMini は 4 行の白を足す）は不明。§8 で確かめる。

### 6.5 転送（チャンク・間隔）

| 根拠 | 1 回の write 長 | 間隔 |
|---|---|---|
| HA（T02 実機、Windows、MTU 200） | 197 | 10 ms |
| PMY・TIM・LNX・M5 | 128 | 20 ms（M5 は応答付き） |
| 接続直後の notify `02 b6 00` | `0x00b6` = **182** が上限らしい（推測。T02・M02・M02 Pro の 3 実装で観測） | — |
| SGR（M02X、macOS） | 182 を超えると黙って落ちる | 速すぎると数行で止まる |

【Claude の判断】picoruby-ble は最大 write 長もフロー制御も出さない（§4.3）。そこで、次の初期値から始める。

- **1 回 128 byte、間隔 20 ms**。4 実装が一致し、推測上限 182 より下にある。
- 接続直後に `02 b6 00` 形式の通知が来たら、その値を上限として、チャンク長が超えないようにする。
- 実機で取りこぼしが無ければ、182 まで、または間隔 10 ms まで詰めてよい。
- MTU が 23 のまま（20 byte しか通らない）と分かった場合は、20 byte に落とす。

速度の見積もり: 128 B / 20 ms ≒ 6.4 KB/s。30 cm（2,400 行 × 48 B ≒ 115 KB）で約 18 秒。印字そのものが 6〜10 mm/s（30 cm で 30〜50 秒）なので、BLE は律速にならない。

書き込みのたびに `01 01` が通知されるが（5 実装で観測）、それをフロー制御に使っている実装は無い。v1 では数えるだけで、待ちには使わない。§8 で確かめる。

### 6.6 送信後の待ち（**送信直後に切断しない**）

- 送信直後に切断すると、印字が途中で止まる（4 実装）。
- picoruby-ble には切断 API が無く、**プロセスの終了 = 切断**になる。だから CLI は、送り終えてもすぐ終了しない。
- 【Claude の判断】次の 2 つを満たしてから終了する。
  - 印字完了の通知 `1a 0f 0c` を受け取る（4 実装で観測）。ただし「当てにならない」とする実装もある（LNX、TiMini）。
  - 時間の上限 `max(2 秒, 行数 ÷ 8 ÷ 6 mm/s + 2 秒)` を過ぎる。最低 1.5〜2 秒待つ点は、HA 実機と多数派に合わせた。
- `1a 0f xx`（`xx` ≠ `0c`）は印字失敗（1 実装）。`1a 0b b8` はプリンター側の取り消し（3 実装）。どちらもエラーとして結果に書く。
- 印字直後の数秒は、問い合わせも再接続も断られることがある（TAG、Classic）。連続でジョブを送るときは 1.5 秒以上空ける。

### 6.7 ステータス

問い合わせは `ff02` に `1f 11 <op>` の 3 byte を書く。応答は `ff03` に `1a <種別> <値…>` で来る（前に `01 01` が来ることがある）。

| 問い合わせ | 応答 | 意味 | 確度 / 注記 |
|---|---|---|---|
| `1f 11 08` | `1a 04 vv` | 電池残量 %（`5a` = 90）。`a1`〜`a4` は 10 / 5 / 3 / 0 %（3 実装、出典なし） | 7 実装（T02 実機は TAG）。**TiMini だけ `1f 11 0e` → `1a 04` と対応付けている**が、少数派なので採らない |
| `1f 11 11` | `1a 06 89` / `1a 06 88` | 紙あり / **紙切れ** | 6 実装（実機 2） |
| `1f 11 12` | `1a 05 98` / `1a 05 99` | カバー閉 / **カバー開** | 5 実装（実機 3）。PMY は逆に解釈、LNX は `1f 11 05` を使う。多数派に従う |
| `1f 11 13` | `1a 03 a8` / `1a 03 a9` | 温度正常 / **過熱** | 応答の意味は 5 実装。問い合わせは兄弟機 2 実装のみ（M02 Pro 実機） |
| `1f 11 07` | `1a 07 a b c` | ファームウェア版（先頭から a.b.c） | 6 実装（逆順に読む実装が 2） |
| `1f 11 09` | `1a 08` + ASCII 15 byte | シリアル番号 | 6 実装 |
| `1f 11 0e` | `1a 09 vv` | 自動電源オフのタイマ（単位不明） | 6 実装 |

問い合わせなしで来る通知（イベント）: `01 01`（受領）、`02 b6 00`（最大 write 長）、`1a 05 99/98`（カバーを開けた / 閉めた）、`1a 06 88`（紙を抜いた）、`1a 03 a9`（過熱）、`1a 0f 0c`（印字完了）、`1a 0b b8`（取り消し）。

【Claude の判断】

- 印刷の前に、紙（`1f 11 11`）・カバー（`1f 11 12`）・電池（`1f 11 08`）を問い合わせる。紙切れ・カバー開・過熱なら送らずにエラーにする。
- 事前確認で紙とカバーの応答が得られない場合（macOS でペアリングが要る、など）は、何も送らずに `status_unavailable`（exit 15）で止める。電池か温度だけが得られない場合は、結果の `warnings` に `status_partial` を書いて印刷する。
- 通知は自前で decode する（picoruby-ble は 0xA7 を捨てる）。1 回の通知に複数の `1a …` が連結されて来る場合にも備える。

### 6.8 安全規則（**必ず守る**）

調査書 §11.6 によると、兄弟機 M02X で `1f 11 00`〜`40` を順に試したところ、`0x14` の後で応答が途絶え、その後**電源が入らなくなった**。

1. **`1f 11 <op>` で `op` が `0x14` より大きいものは送らない**（TiMini が `1f 11 38` などを送っていても、真似しない）。
2. **未知のコマンドを総当たりで試さない**。実機確認のためでも同じ。
3. `1b 4e 04 n`（M02X が固まった報告あり）、`1b 37 …`（ESC 7）、`1d 7c n`（GS |）、`1d 67 6e`、`SSSGETSN` などの由来不明・効果不明のコマンドは送らない。
4. 【Claude の判断】**gem は既知コマンドの allowlist だけを組み立てる設計にする**。任意のバイト列をプリンターに書く公開 API は作らない。テストで allowlist 外のバイト列が出ないことを保証する。
   - allowlist（v1）:
     - `1b 40`
     - `1b 61 n`（n ∈ 0..2）
     - `1f 11 02 n`（n ∈ 01..05）
     - `1d 76 30 00 30 00 yL yH` + 48×y byte（1 ≤ y ≤ 255）
     - `1b 64 n`（n ∈ 0..255）
     - ステータス問い合わせ `1f 11` + {`07`, `08`, `09`, `0e`, `11`, `12`, `13`}
   - allowlist に足すときは、調査書に根拠（実装と行番号）があること、`1f 11` なら 0x14 以下であることを確かめ、ユーザーに確認する。

### 6.9 不明のまま実装するもの

ここに挙げるものは、既定値で実装し、§8 のチェックリストで値を決める。

- `1f 11 02 n` の値と濃さの対応
- `1b 64 n` の 1 行の長さ
- 上端の欠け
- `01 01` の粒度
- `1a 0f 0c` の確実さ
- 255 行を超える 1 ブロック（v1 では使わない）
- 速度コマンド（v1 では使わない）
- 本体フォント（v1 では使わない。文字はすべてアプリでラスタ化する）

---

## 7. repo の構成

【Claude の判断】この repo（`bash0C7/thermal-printer`）は 1 つの monorepo にする。現時点では git 管理されていない。git init や remote 作成は、ユーザーに確認してから行う。

```
thermal-printer/
  Rakefile                       # setup / build / test / app_bundle / print などのタスク
  build_config/
    darwin-thermal-printer.rb    # 製品用: RD の darwin-ble 設定 + hal-task-darwin + 本 gem
    picoruby-test.rb             # テスト用 VM（BLE なし + picotest）
  mrbgems/
    picoruby-phomemo-thermal-printer/
      mrbgem.rake                # ASCII のみ
      mrblib/                    # 共通層（OS・BLE 非依存、トランスポート契約）
      ports/darwin/              # darwin 版 picoruby-ble 向けトランスポート（§5.1）
      sig/
      test/
  cli/                           # print.rb など（picoruby で実行）
  bin/phomemo-print              # sh ラッパー
  test/                          # 外置き gem 用の picotest runner（stackchan / DH 方式）
  app/                           # SwiftUI アプリ（Sources / Tests）
  .claude/skills/<slack-card>/SKILL.md
  vendor/R2P2-darwin/            # gitignore。rake setup で clone（port-darwin は先頭に追従）
  docs/
    superpowers/specs/           # 本書とモックアップ
    research/                    # 調査報告
  .gitignore                     # vendor/, build/, .superpowers/ など
```

ビルドは stackchan 方式にする。`MRUBY_BUILD_DIR=<RD>/build MRUBY_CONFIG=<repo>/build_config/darwin-thermal-printer.rb rake -C <RD>/vendor/picoruby`。build_config には `PICORB_PLATFORM_POSIX` と `PICORB_PLATFORM_DARWIN` の両方、`picoruby-ble`、`hal-task-darwin`、本 gem を入れる。

---

## 8. 作る順番とマイルストーン

【ユーザー決定】順番は次の 3 段。

1. gem と CLI で、画像 1 枚を実機で印刷できるところまで
2. Mac アプリ
3. skill

【Claude の判断】

- 1 の前に M0（spike）を置く。
- 各段の「完了」は**macOS から T02 実機に印字されたこと**で判定する。
- マイコン（Pico 2 W / ESP32）実機での確認は、どの段の完了条件にも入れない（§5.1.2）。

| 段 | 内容 | 完了の条件 |
|---|---|---|
| M0 spike（捨てる前提） | Ruby 3.4+ の用意。R2P2-darwin の setup（`port-darwin` の先頭を clone。使った commit を記録する）。build_config を作ってビルド。TCC の 4 経路を最小の scan スクリプトで試す。T02 の GATT ダンプ（`gatt_dump_probe.rb`、読むだけで何も書かない） | 通る起動経路が決まる。実機でアドバタイズ名 `T02` と `ff00` / `ff02` / `ff03` を確認できる。下のチェックリストの 1・2・13・15 に答えが出る |
| M1 gem + CLI | TDD で共通層（§6.4〜6.8、allowlist、行ブロック単位の送出、トランスポート契約）。`ports/darwin` のトランスポート。`bin/phomemo-print`（PBM を行ブロック単位で読む、排他ロック） | テストパターンの PBM と写真の PBM が実機で正しく印字される。`--status` が動く。共通層のテストが BLE なしの host VM で通る。**下の実機確認チェックリストの全項目に、結果か「v1 では使わない」が記録されている** |
| M2 Mac アプリ | 画面 C。テキスト / markdown / 画像（「iPhone から読み込む」を含む）/ カード（GitHub / Slack URL / 知らない URL / リマインダー）。今日のカード。長さの警告。状態表示（起動時・手動更新・印刷後）。CLI 呼び出し | 3 つの場面（タスク札数枚、会議メモ、写真）が実機で印字され、はみ出しが無い |
| M3 skill | Slack URL → カード JSON → アプリ | Slack のカードが実機で印字される |

### 8.1 M1 の実機確認チェックリスト

調査書 §17 の 15 項目を、手元の T02 で確かめる。結果は `docs/research/t02-device-notes.md`（新規）に、日付・ファームウェア版（`1f 11 07`）・macOS 版を添えて記録し、§6 の確度を「実機（本機）」に更新する。

**§6.8 の安全規則はここでも守る**。確かめるために allowlist 外のコマンドを送らない。allowlist だけで確かめられない項目は「v1 では使わない」と記録して終える。

| # | 確かめること（調査書 §17） | 確かめ方（allowlist の範囲で） | 結果が効く先 |
|---|---|---|---|
| 1 | 広告されるサービス UUID（`af30` の有無）、`ff01` が read か notify か | M0 の GATT ダンプ（読むだけ） | §6.2 / §6.3 |
| 2 | MTU と 1 回の write の上限（`02 b6 00` = 182 は本当か） | 接続直後の通知を記録する。128 → 160 → 182 byte で印字の欠けを見る。**182 を超える長さは試さない** | §6.5 のチャンク長 |
| 3 | `01 01` が write 1 回ごとに 1 回来るか | 送った回数と通知の回数を数える | 来るなら、`port-darwin` 改修なしでフロー制御に使えるかを検討する |
| 4 | 255 行を超える 1 ブロック | **v1 では使わない**（255 行以下で分ける）。確かめない | — |
| 5 | `GS v 0` の `m` ≠ 0（倍角） | **v1 では使わない**（`m=00` 固定）。確かめない | — |
| 6 | 幅 48 byte 未満のブロック | **v1 では使わない**（常に 48 byte）。確かめない | — |
| 7 | `1b 64 n` の 1 行の長さ | n = 1, 3, 6 で紙送り量を定規で測る | 帯の最後の余白（§6.4） |
| 8 | `1f 11 02 n` の値と濃さの対応 | n = 01〜05 で同じグレースケール帯を印字して比べる。`1f 11 37`・ESC 7・GS \| は試さない | アプリの濃度メニュー |
| 9 | 速度コマンド | **v1 では使わない**。既知のものが無いので試さない | — |
| 10 | 上端の数行が欠けるか | 1 行目から罫線の入った画像を印字する | 欠けるなら、アプリが上端に白行を足す |
| 11 | `1a 09 vv` の単位、`1a 04 a1〜a4` の意味、充電中の通知 | `--status` を時間をおいて、また充電しながら記録する | 電池表示 |
| 12 | `1a 0f 0c` が毎回来るか、来るまでの時間 | 長さの違うジョブで、送信完了から通知までの時間を測る | §6.6 の待ち方 |
| 13 | macOS + picoruby-ble で、notify にペアリングが要るか | M0 で CCCD 購読を試す。失敗したら、システム設定でペアリングしてから再試行する | §6.7（`status_unavailable` の扱い）、利用手順 |
| 14 | 本体フォントでの文字印字 | **v1 では使わない**（文字はアプリでラスタ化）。確かめない | — |
| 15 | 名前 `T02` の別機種との区別 | 接続後に `ff00` / `ff02` / `ff03` が揃うかで判定する（§6.1）。手元に別機種が無ければ、判定コードのテストだけで済ませる | §6.1 |

---

## 9. 開発規律

- t-wada 流 TDD: コードには How、テストには What、コミットログには Why、コードコメントには Why not。
- 完了の線引きは実機の印字。host のテストが green でも、実機で出るまで「動いた」と言わない（R2P2-darwin / dev-harness 共通の規律）。
- **プリンターに送るのは §6.8 の allowlist だけ**。実機での試行錯誤やデバッグのときも、未知のコマンドを送らない。`1f 11` の 0x14 より上の番号は、どんな理由でも送らない。
- gem 内は `each` / `times` / `map` を避けて `while` + 明示 index。ivar を 3 回以上参照するなら local に memoize（picoruby `AGENTS.md`）。
- `mrbgem.rake` は ASCII のみ。
- `vendor/` は生成物で、commit しない。
- `port-darwin`、R2P2-darwin、stackchan-picoruby など、既存の repo は直接変えない。変える必要が出たら、ユーザーに確認する。
- 【ユーザー決定】`port-darwin` はブランチの先頭に追従する。先頭の変更（pr427 の BLE 共通 API 変更など）で壊れたら、直すのは gem の `ports/darwin` の中だけにする。【Claude の判断】`port-darwin` 自体の改修が要ると判断したら、手を入れる前に、その時点でユーザーに相談する。この規律は repo の CLAUDE.md などにも残す。
- picoruby-ble の内部（`@event_queue`、`_event_popped`、`@conn_handle`、パケットの形）に触るコードを `ports/darwin` の外に書かない。
- PicoRuby と CRuby の差（`rescue` 内の裸 `raise`、`module_function`、regexp の `|` など）は stackchan の CLAUDE.md に実測メモがある。

---

## 10. Claude の判断の一覧（ユーザー未確認）

1. gem 名の綴りを `phomemo` にした（ユーザー表記は `phomeno`）。
2. アプリは SwiftUI、macOS 27 ターゲット。名前は仮に "Thermal Printer"、bundle id は `com.bash0c7.thermalprinter`、URL スキームは `thermalprinter://`。
3. アプリ → CLI の受け渡しは PBM P4（1bit、384 dot 幅）ファイル。結果は JSON ファイルでも返す。
4. CLI は `bin/phomemo-print`（sh）→ `picoruby cli/print.rb`。印刷 1 回 = 起動 1 回 = 接続 1 回。常駐 daemon は v1 で作らない。
5. TCC は M0 で 4 経路を試す。第 4 経路として、アプリが同梱の picoruby を子プロセスで起動する形を加えた。
6. picoruby-ble は今のまま使う（決め打ちチャンク + sleep）。`port-darwin` 自体に API を足す必要が出たら、その時点でユーザーに相談する（先頭追従はユーザー決定、相談の規律は Claude の判断）。
7. gem は `add_dependency 'picoruby-ble'`。テストは BLE を含まない VM に source を埋め込み、fake を注入する（stackchan 方式）。
8. skill → アプリは URL スキーム + カード JSON。スキーマは §5.3.5。
9. 長さの警告は既定 30cm で、設定で変えられる。フッターの警告に加え、印刷時に確認ダイアログを出す。
10. 部品の種類（テキスト / markdown / 画像 / カード）と、部品間の切り取り線。
11. markdown の H3〜H6、順序付きリスト、入れ子、区切り線、コード、リンク、表、画像の扱い（§5.3.3）。文字はしきい値で 2 値化する。
12. 写真の調整の既定値と計算順、回転ボタン。
13. リマインダーカードの項目（QR なし、リスト名・期限、`☐` + 件名、メモ）。今日のカードは期限切れを含む。
14. GitHub PR の URL も同じ形にする。`gh` で取れないときは「知らない URL」に落とす。URL ハンドラは差し込める形にする。（アカウントを管理せず `gh` のアクティブアカウントに従うのはユーザー決定。）
15. Slack カードに投稿者名を（取れれば）載せる。Slack 記法の前処理の規則。スレッド返信 URL の扱い。`slack_search_public_and_private` は使わない。
16. 要約は Foundation Models。使えないときは先頭切り詰めに落とす。
17. QR の誤り訂正 M、整数倍の拡大、1 モジュール 3 dot 以上。
18. 文字組みの内側余白の初期値 8 dot。
19. repo を monorepo にする構成（§7）。git init / remote 作成はユーザー確認後。
20. Non-goal に入れたもの: T02 以外の機種、レイアウトの保存、daemon、知らない URL の中身の取得。
21. 既定のジョブは、HA 実機の最小手順（`1b 40` → `1b 61 00` → ラスタ → `1b 64 03`）に `1f 11 02 04` を足したもの（§6.4）。行数は実数で書き、`0x0a` は置換しない。古い実装の終了列 `1f 11 08 0e 07 09` は付けない。
22. 濃度は `1f 11 02 n`（n = 01〜05、既定 04）だけを使う。`1f 11 37`、ESC 7、GS | は使わない。
23. チャンクは 128 byte / 20 ms から始める。`02 b6 00` の値を上限にする。実機で 182 byte・10 ms まで詰めてよい（§6.5）。
24. 送信後は `1a 0f 0c` と時間の上限 `max(2 秒, 行数 ÷ 8 ÷ 6 mm/s + 2 秒)` を待ってから終了する（§6.6）。
25. 印刷前に紙・カバー・電池を問い合わせる。紙とカバーの応答が得られなければ、何も送らずに `status_unavailable` で止める（§6.7）。
26. 接続後に `ff00` / `ff02` / `ff03` が揃わなければ別機種として何も送らない（§6.1）。
27. **gem は既知コマンドの allowlist だけを組み立てる。任意バイト列の送信 API は持たない**。allowlist に足すときは、根拠を確かめたうえでユーザーに確認する（§6.8）。
28. 切り取りのための余白は、アプリが白い行として足す。CLI は `1b 64 03` だけを送る（`ESC d` の 1 行の長さが不明なため）。
29. ステータスの食い違いは多数派に従う。電池は `1f 11 08` → `1a 04`（TiMini の対応付けは採らない）。カバーは `1f 11 12` → `99` = 開（PMY の逆解釈、LNX の `1f 11 05` は採らない）。
30. 実機確認の結果は `docs/research/t02-device-notes.md` に記録する。v1 で使わない機能（255 行超のブロック、倍角、幅 48 byte 未満、速度、本体フォント）は確かめない（§8.1）。
31. マイコン（Pico 2 W / ESP32）実機での確認は完了条件に入れない。`ports/rp2040`・`ports/esp32` は作らない。共通層の OS 非依存は、BLE なしの host テストで担保する（§5.1.2）。
32. 共通層と port の境目に「トランスポート契約」（接続・GATT 確認・購読・1 チャンク write・notify 取り出し・切断）を置き、picoruby-ble の内部を契約の外に漏らさない（§5.1.1）。
33. CLI は PBM を行ブロック単位で読み、そのまま gem に流す（§5.2）。
34. プリンター状態は常時接続しない。起動時・手動更新・印刷後に `--status` で取り直し、確認時刻を添えて表示する。CLI は同時に 1 プロセスだけで、2 本目は `busy` で即座に失敗する（§5.2、§5.3.1）。
35. 会議メモの要点は、範囲を選んでコピー → ⌘V で markdown 部品にする。`.md` ファイルのドロップは丸ごと。⌘V のテキストは、URL 1 本だけならカード、それ以外は markdown 部品。自動要点抽出は作らない（§5.3.2）。
36. 写真の取り込みに、SwiftUI 標準の「iPhone から読み込む」（Continuity Camera、`ImportFromDevicesCommands` など）を付ける。カメラ権限の要否は builder が確かめる（§5.3、§5.3.2）。

---

## 11. builder に任せること

- gem の公開 API の名前と形。CLI のオプション名。結果 JSON の項目名。
- Xcode プロジェクトの作り方（xcodegen / SwiftPM）。アプリ内のモジュール分割。
- markdown パーサーの選定。
- skill の名前と、URL スキームでの JSON の渡し方（クエリか一時ファイルか）。
- 実機で決めるもの。いずれも §6 の範囲内で、allowlist の外に出ないこと。
  - チャンク長（182 以下）と間隔
  - CCCD 購読後の待ち時間
  - 完了待ちの上限の係数
  - 帯の最後の白行の量
  - 内側余白
  - QR サイズの微調整
  - 写真の既定値
- 要約のプロンプト文と文字数の目安の微調整。
- Ruby 3.4+ の用意の仕方（mise で 4.0.5 を入れる、または入っている 4.0.x を使う）。ただし、システムの 2.6 は使わない。
- `ports/darwin` の Ruby（と、要るなら C）を darwin のビルドだけに組み込む仕掛け（picoruby の既存 gem の前例に合わせる）。トランスポート契約のメソッド名。
- 1 行ブロックの行数（255 以下）。
- CLI の排他の実装（ロックファイルの置き場所など）。
- 「iPhone から読み込む」にカメラ権限などの宣言が要るかの確認と、その対応。

---

## 12. 調査資料

`docs/research/` に置く（scratchpad の原本から写したもの。scratchpad のパスは揮発する）。

- `phomemo-t02-protocol.md`: Phomemo T02 の BLE プロトコル。T02 の 17 実装と兄弟機 12 実装を読み比べ、各値に出典（repo・commit SHA・行番号）と確度を付けたもの。§6 の根拠。clone した原本のソースは写していないので、必要なら §1 の URL と SHA から取り直す。
- `r2p2-darwin-and-gems.md`: R2P2-darwin / dev-harness / picoruby の作法、ビルド、テスト、CLI 機能、外置き gem、TCC。
- `picoruby-ble-darwin.md`: picoruby-ble の Ruby API、darwin 実装の関数ごとの状況表、central の使用例の全文、罠。
- `slack-connector-probe.md`: Slack 連携で取れるもの、permalink からの取得手順、Slack 記法。
- `t02-device-notes.md`: **M1 で新規作成**。§8.1 の実機確認の結果を記録する。

## 13. 未確定とリスク

1. **Phomemo T02 のプロトコルの実機未確認点**: 大枠（GATT、ジョブの形、ラスタ形式、ステータス）は実装の一致と実機記録で確定した。残る不明点は §6.9 と §8.1 のとおりで、M1 で確かめる。特に、1 回の write の上限（182 か 197 か）、`1a 0f 0c` の確実さ、`1f 11 02 n` と濃さの対応。
2. **macOS で notify にペアリングが要る可能性**（1 実装の報告）: 要るなら、事前確認と完了待ちができないので、何も送らずに `status_unavailable` で止め、初回のペアリングを促す（§6.7）。利用手順に「初回にペアリング」を足すかどうかは M0 で決める。
3. **TCC**: どの起動経路が通るかは未検証。`open -a` 経路しか通らない場合、CLI の stdout と exit code は使えないので、結果ファイルに頼る。
4. **picoruby-ble のフロー制御不足**: 決め打ちとペーシングで取りこぼすなら、`port-darwin` の改修が要る（ユーザー確認）。`01 01` が write ごとに来るなら、改修なしで擬似的なフロー制御にできる可能性がある（§8.1 #3）。
5. **picoruby-ble の共通 API の変更と先頭追従**
   - 【ユーザー決定】`port-darwin` は先頭に追従する。
   - 進行中の pr427（`start` の 100ms ポーリング化、`BLE_push_event` の戻り値変更など）が入ると、`@event_queue` や `_event_popped` に直接触る `pop_and_dispatch` 相当のコードは壊れうる。そうしたコードは `ports/darwin` にだけ置き、壊れたときの修正範囲をそこに限る（§5.1）。
   - 先頭追従なので、ある日ビルドや動作が変わりうる。【Claude の判断】setup / refresh のたびに使った `port-darwin` の commit を記録し、切り分けを速くする。`port-darwin` 自体の改修が要るときはユーザーに相談する。
6. **プリンターを壊す危険**: 兄弟機で、未知の `1f 11` 番号の総当たりの後に電源が入らなくなった報告がある。§6.8 の allowlist で防ぐ。builder が「試しに」コマンドを足すことが最大のリスクなので、allowlist のテストで縛る。
7. **名前 `T02` の別機種**: 別ベンダの機械が同じ名前を名乗る。`ff00` の確認で防ぐ（§6.1）。周りに複数台あると誤接続しうるので、2 台以上見つかったときの扱い（最初の 1 台か、エラーか）は builder が決める。
8. **自動スリープ**: スリープ中は見つからない。not_found のエラーに手がかりを添える。
9. **Foundation Models の日本語要約の品質**: 実際の出力を見て、プロンプトを調整する。
10. **写真の濃さ**: 感熱紙は濃く出やすい。既定値と濃度 n は実機で詰める（§8.1 #8）。
11. **マイコン対応は構造だけ**: マイコン実機では確かめないので、`ports/rp2040`・`ports/esp32` を作るときに、契約の不足（例: write の戻り値が使える port での扱い）が見つかる可能性がある。今回は、契約を darwin の都合に寄せすぎないことだけを気をつける。
12. **Continuity Camera**: iPhone と Mac が同じ Apple ID で近くにあることが前提。使えないときは AirDrop やドロップで代える。
