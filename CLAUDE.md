# thermal-printer

使い方とコマンドは`README.md`、設計書は`docs/superpowers/specs/2026-10-24-thermal-printer-design.md`、T02のプロトコル調査は`docs/research/phomemo-t02-protocol.md`にある。

## 安全規則（プリンターを守る）

- `1f 11 <op>`は`op`が0x14以下のものだけを送る。理由を問わない。
- コマンドは、設計書§6.8のallowlistにあるものだけを使う。実機確認でも同じ。
- allowlistへ足すときは、プロトコル調査に根拠があることを確かめ、ユーザーに確認する。
- BLEのwrite呼び出しはgemの2か所（`transport.rb`の`write_chunk`と、`session.rb`の`emit`）に置く。gemの規律はgem repoのCLAUDE.mdにある。

## 開発規律

- t-wada流TDD。コードにはHow、テストにはWhat、コミットログにはWhyを書く。コードは名前と構造だけで読める形にする。
- ドキュメント生成のための型情報と説明は、コードに書いてよい。
- Swiftは`/usr/bin/swift`（Xcode）。PATHでは`~/.swiftly/bin/swift`より前に置く。
- `vendor/`と`build/`は生成物で、編集しない。
- picoruby-bleは、公開APIと、上書き用のフックだけで使う。使うコードはgemにあり、内部変数、非公開メソッド、`start`の中身の複製には触れない。
- `port-darwin`とgemは、commitを固定せず先頭に追従する。`port-darwin`自体の改修が要ると判断したら、手を入れる前にユーザーに相談する。
- `port-darwin`、R2P2-darwin、stackchan-picorubyなど既存repoの変更は、ユーザーに確認してから行う。
- PicoRubyとCRubyの差（`rescue`内の裸`raise`、`module_function`、regexpの`|`など）の実測メモは`~/dev/src/github.com/bash0C7/stackchan-picoruby/CLAUDE.md`にある。
- 画面、クリップボード、プリンターに触る操作（UIテスト、実機印字）は、実行前にユーザーへ、内容、実行する時刻、影響、止め方を伝え、返事を受けてから実行する。許可は、伝えたその1回にだけ効く。再現確認や再印字も、新しい印字として伝える。ユーザーが操作している最中は、UIテストを走らせない。

## DualKey

- firmwareは`rake dualkey:qemu_check`の合格後に`rake dualkey:flash`で焼く。
- `app.rb`はfirmwareに入らないので、`rake dualkey:deploy_app`で何度でも転送してよい。
- プリンターがOFFのときは、押下から`NOT_FOUND`までの経路で確認する。

## テスト戦略

テストは単体、結合、E2Eの3層に置く。

- 単体: 1つの型または関数の振る舞い。依存はfakeに置き換える。picoruby上で動くコード（CLI）は、`rake test:ruby`が起動するpicotestでpicoruby VM上に実行する。CRubyのminitestはpicoruby上で動かないツール（`test/tools`）に限る。
- 結合: 実物の部品を2つ以上つなぎ、BLEだけをfakeに置き換える。gemとCLIを製品VMでつなぐ`--dry-run`、アプリのCoreが実CLIを子プロセスで起動する経路が対象。
- E2E: アプリ、CLI、製品VMを実プロセスで通す。判定にClaudeの推論を使ってよい（プレビューPNGの読み取り、画面の確認など）。プレビューの期待は`test/e2e/preview/<名前>.md`に、カードのfixtureごとに書く。実機印字は最上位のE2Eで、ユーザーが指示したときだけ行う。
