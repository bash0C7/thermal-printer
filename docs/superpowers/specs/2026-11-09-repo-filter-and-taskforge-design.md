# Mac アプリ: GitHub の repo 指定と TaskForge タスクの印字 設計書

- 日付: 2026-11-09
- 状態: 実装済み（ユーザーによる実機確認待ち）
- 親設計書: `docs/superpowers/specs/2026-10-24-thermal-printer-design.md`（安全規則・カード・QR・要約の前提はこちら）

## 0. この文書の読み方

親設計書と同じラベルを使う。

- **【ユーザー決定】**: ユーザーが決めたこと。変えるときはユーザーに確認する。
- **【Claude の判断】**: Claude が既定値として置いたもの。理由があれば builder が変えてよい。変えたら理由を残す。
- **【builder に任せる】**: 作る人が決めてよいこと。

---

## 1. 意図と why

ユーザーは Mac アプリの左の欄（`app/App/TodayColumn.swift`）から、朝のタスク札を選んで刷っている。今は次の2つが並んでいる。

- GitHub: 全 repo から、自分に assign された open な issue と PR
- リマインダー: リストで絞れる（Mac と iPhone の両方に実装済み）

ここに2つ足す。

1. **GitHub の repo 指定**: 仕事の repo（例 `octo-org/sample`）に絞って、自分が assign されたものとレビューを頼まれたものだけを並べたい。
2. **TaskForge のタスク**: Obsidian vault で TaskForge（TaskNotes 形式）を使ってタスクを管理している。そこから選んだタスクを、リマインダーと同じく見出し、要約、QR の札にしたい。QR を Mac で読むと、そのタスクが Mac の Obsidian（または TaskForge）で開く【ユーザー決定: 成功の条件を Mac での読み取りにすることに「ok」】。

あわせて、この Mac（clone したばかりで `vendor/` と `build/` がない）で Mac アプリをビルドし、起動できる状態にする。

成功の姿: 左の欄で repo を入れると、その repo の自分宛ての issue と PR だけが並ぶ。TaskForge の未完了タスクが並び、チェックすると札になる。刷った札をアプリの「QR を読む」で Mac のカメラにかざすと、そのタスクが開く。

## 2. Goals / Non-goals / Anti-goals

### Goals

- G1 この Mac で `vendor:setup` → `vm:build` → `app:build` → `app:install` が通り、`~/Applications/ThermalPrinter.app` が起動する。
- G2 GitHub の欄で repo を1つ指定でき、その repo の open な issue / PR のうち、自分に assign されたものと、自分にレビュー依頼が来ている PR が並ぶ。
- G3 TaskForge の未完了タスクが左の欄に並び、チェックすると見出し・要約・QR の札になる。
- G4 アプリの中で紙の QR を読み、中のリンクを開ける。刷った札を Mac のカメラにかざすと、そのタスクが開く（印字 → 読み取り → タスク、のクローズドループ）【ユーザー決定: 「このアプリに組み込む。そうするとクローズドループができるよね」】。

### Non-goals

- iPhone アプリへの追加。vault は Mac にしかなく、iPhone アプリには GitHub の欄もないため【Claude の判断】。
- リマインダーのリスト選択。すでに Mac と iPhone の両方にある【ユーザー決定: 「すでにあるならok」】。
- 複数 repo の同時指定【Claude の判断】。
- 空欄時の gh アカウントの切り替え。空欄のときは今と同じ挙動【ユーザー決定: 空欄のときは今のアカウントのままでよい】。

### Anti-goals（動いても失敗）

- vault に書き込むこと。ID の付与、状態の変更、ファイルの作成をしない。読むだけ【Claude の判断。TaskForge の README が ID 付与は「ユーザーの同意を得た一括操作」としているため】。
- gh アカウントの対応表（org → アカウント）をアプリに持たせること。正本はユーザーの `~/.zshenv` の1か所だけ（§4.2）。
- 完了したタスクを並べること【ユーザー決定: 「完了分は不要」】。
- 親設計書 §6.8 の allowlist を外れたプリンターコマンド。今回は印字経路に手を入れないので、該当する変更はない。

## 3. ビルド環境（G1）

調べた結果（2026-11-09）:

- Xcode 27.2、`/opt/homebrew/bin/xcodegen`、`/opt/homebrew/bin/gh` はある。
- `mise.toml` は Ruby 4.0.5 を指定しているが、未インストール（4.0.3 / 4.0.4 / 4.0.6 のみ）。`mise install` が要る。
- `vendor/` と `build/` がない。README の「セットアップ」と「アプリ」の手順を順に流す。

手順は README のとおり。途中で失敗したら原因を直し、README と食い違っていれば README を直す。`port-darwin` や gem の改修が必要になったら、手を入れる前にユーザーに相談する（CLAUDE.md）。

## 4. GitHub の repo 指定（G2）

### 4.1 入力と絞り込み

- 【ユーザー決定】GitHub の欄に repo の入力欄を置く。`https://github.com/<owner>/<repo>`（後ろに `/issues/1` などが付いてもよい）と `<owner>/<repo>` の両方を受け付ける。
- 【ユーザー決定】並べるのは、その repo の open な issue と PR のうち、自分に assign されたものと、自分にレビュー依頼が来ている PR。
- 【ユーザー決定】レビュー依頼は自分個人宛てのものだけ。チーム宛ては不要（「チーム宛は不要」）。`--review-requested @me` はチーム宛ても拾うので使わず、検索語 `user-review-requested:@me` で取る。
- 【Claude の判断】一度レビューを出すと依頼が外れて一覧から消える。それでよいとする（ユーザーはこの点に異を唱えていない）。
- assign とレビュー依頼の両方に当たる PR は1行にまとめる（URL で重複を除く）【Claude の判断】。
- 行の見出し（`TodayIssue.label`）に、レビュー依頼で入った PR だと分かる印を付ける。印の形は【builder に任せる】。
- 【Claude の判断】repo は1つだけ。入れた値は `UserDefaults` に残し、次の起動でも使う（リマインダーのリスト選択と同じ扱い）。
- 【Claude の判断】空欄のときは全 repo が対象。レビュー依頼の PR も全 repo から取る（空欄時も一覧の意味をそろえるため）。
- 読めない入力（`owner/repo` の形にならない）は、欄の下にメッセージを出して一覧を変えない【Claude の判断】。
- 既存の「URL を直接指定」欄とは別の欄にする。置き方は【builder に任せる】。

### 4.2 どの gh アカウントで呼ぶか

ユーザーの `~/.zshenv` が `$PWD` を見て `GH_CONFIG_DIR` を切り替えている。アプリは `~/ghq/github.com/<owner>` で zsh を起動して、その切り替えに任せる。どの owner がどのアカウントになるかは `.zshenv` だけが知っていて、この文書にもアプリにも書かない。

Finder から起動したアプリは `.zshenv` を読まないので、`GH_CONFIG_DIR` が空になり、`gh` の既定の設定で動く。

- 【ユーザー決定】空欄のときは今のまま（`gh` の既定の設定）。
- 【Claude の判断】repo を入れたときは、`~/ghq/github.com/<owner>/` を作業ディレクトリにして `/bin/zsh -c 'gh …'` で起動する。`.zshenv` は非対話の zsh でも読まれるので、ユーザーの切り替えがそのまま効く。アプリに対応表を持たせない（Anti-goal）。
  - `.zshenv` の `case` は `"$PWD/"` を `<owner>/*` と比べるので、作業ディレクトリは `~/ghq/github.com/<owner>/` の直下ではなく、その中のどこか（例: そこにある repo のディレクトリ、なければ `<owner>/` 自体に `/` を足した形が合うかを builder が確かめる）にする必要があるかもしれない。合う作業ディレクトリの選び方は【builder に任せる】が、テストで確かめる。
  - `~/ghq/github.com/<owner>/` がないときは、今と同じ（`GH_CONFIG_DIR` を設定しない）で呼び、gh が失敗したらそのメッセージを出す【Claude の判断】。
- gh の起動は既存の `ProcessRunner` と `GHLocator` を通す。zsh 経由で引数を渡すときは、repo 名をシェルの文字列に埋め込まず、位置引数（`zsh -c 'gh "$@"' zsh …`）で渡す【Claude の判断。入力欄の値がシェルに解釈されないように】。
- 一覧から札を作るときは、issue / PR 本文の取得（`GitHubHandler`）も、その一覧を取ったときと同じ作業ディレクトリで呼ぶ【Claude の判断。一覧に出たのに札が作れない、を避けるため】。`GitHubHandler` は URL しか受け取らないので、一覧の行から札を作る経路で作業ディレクトリを渡す口を足す。既存の「URL を直接指定」欄は今のまま（`GH_CONFIG_DIR` を設定しない）にする【Claude の判断。ユーザーは空欄時と同じく今の挙動のままでよいとしているため】。
- `~/ghq/github.com/<owner>/` はあるが `.zshenv` が扱わない owner（例: `other-org`）では、`.zshenv` が未ログインの設定を選ぶので gh は失敗する。そのときは gh のメッセージをそのまま欄の下に出し、別アカウントで呼び直さない【Claude の判断。黙って別アカウントに落ちると、誰の一覧か分からなくなるため】。

## 5. TaskForge のタスク（G3）

### 5.1 どこから読むか

- vault: Obsidian vault の場所を設定で指定する。設定画面（`SettingsView`）に入力欄を置き、値は `UserDefaults` に残す。既定値は持たず、空のあいだは TaskForge の欄に「設定で TaskForge の vault の場所を指定してください」と出す【Claude の判断。公開 repo に個人の場所を書かないため】。入力は前後の空白を除き、`~` を展開する。
- タスクの置き場所と項目名は `<vault>/TaskForge/Settings/dialect.json` の `tasknotes` に書かれている（2026-11-09 時点）。
  - フォルダ: `tasknotes.folder` = `00_TaskNotes`
  - タイトル: ファイル名（`filename_format: "title"`、`store_title_in_filename: true`）。拡張子 `.md` を除いた名前がタスク名。
  - 項目名: `tasknotes.field_names`（`status`、`priority`、`due`、`scheduled`、`projects`、`id` など）
- 【Claude の判断】dialect.json を読んでフォルダと項目名を決める。読めないときは上の値を既定にする。dialect.json の他の部分（繰り返し、inline タスク）は扱わない。
- アプリは sandbox なし（`app/project.yml`）なので、ファイルは `FileManager` で直接読める。

### 5.2 どれを並べるか

- 【ユーザー決定】完了していないもの全部。status は open、planned、someday などがある。
- 【Claude の判断】除くのは `status` が `done` と `cancelled` のもの（`status_write_values` の値）。それ以外の status は並べる。dialect の `hidden_statuses` にある `deferred` も、完了ではないので並べる（ユーザーが除くと言ったのは完了分だけのため）。`status` がないファイルはタスクではないので並べない（`identification.method: "property"`, `property_name: "status"`）。
- 【Claude の判断】並び順は TaskForge の Kanban space と同じ: `scheduled` 昇順 → `due` 昇順 → `priority` 降順。値がないものは後ろ。priority の順位は `highest > high > medium > low > lowest > none`。
- 左の欄に「TaskForge」の節を足す。行にはタスク名と、status と期限などの補足を出す。体裁は【builder に任せる】。リマインダーと同じく checkbox で選ぶ。
- 下の「更新」ボタンで読み直す。

### 5.3 札の中身

リマインダーの札（`ReminderCard`）と同じ形にする【ユーザー決定: 「要約やQRコードも対応する」】。

- 見出し: `☐ ` + タスク名。長いときは `TextDigest` で見出しと要約にする（`ReminderCard.make` と同じ分岐）。
- 要約の元: frontmatter を除いた本文。
- header 行: プロジェクト（`projects` の `[[…]]` を外した名前）と status。sublines: 予定日と期限。体裁は【builder に任せる】が、日付の書き方は `ReminderCard.dueLine` に合わせる。
- `Card.Kind` にタスク用の種類を足すか、`.reminder` を流用するかは【builder に任せる】。

### 5.4 QR に入れるリンク

【ユーザー決定】「そのTaskへのTaskForgeへのdeeplink、それがなければ Obsidianでそのタスク詳細がひらけること」。

- TaskForge の deeplink は `taskforge:///task/<ref>`（`TaskForge/Settings/agents.md` 55行目）。`<ref>` には、ずっと変わらない ID（frontmatter の `id`、dialect の `user_task_id`）か、パスから作る ID を使う。
- パスから作る ID は、タイトルやパスを変えると変わり、作り方も書かれていないので使わない【Claude の判断】。
- よって:
  - frontmatter に `id` があるタスク → `taskforge:///task/<id>`（`<id>` は percent-encode）
  - ないタスク → `obsidian://open?vault=<vault のディレクトリ名>&file=<vault からの相対パス、.md なし>`（両方 percent-encode）
- 2026-11-09 時点の実 vault では、どのタスクにも `id` がない（ID の自動付与が切られている）。つまり今はすべて Obsidian のリンクになる。
- QR の容量: 日本語の長いファイル名は percent-encode で3倍に膨らむ。今の最長のファイル名でも QR に収まるか、テストで確かめる。収まらないときの扱い（QR を省いて注記するなど）は【builder に任せる】。

### 5.5 QR の読み取り（G4）

【ユーザー決定】Mac 標準の仕組みを組み合わせて、このアプリに組み込む。

- カメラ: AVFoundation。内蔵カメラと Continuity Camera（iPhone をカメラにする）の両方を使える。選ぶ UI は【builder に任せる】。
- 検出: Vision の `VNDetectBarcodesRequest`（symbology は QR だけ）。
- 開く: `NSWorkspace.shared.open(URL)`。
- 【Claude の判断】起動は、アプリのどこかに置く「QR を読む」ボタンから。読み取り用の小さなウィンドウ（またはシート）にカメラの映像を出し、QR を見つけたらすぐ閉じてリンクを開く。置き場所と体裁は【builder に任せる】。
- 【Claude の判断】開いてよいのは、このアプリが QR に入れるリンクの形だけ: `taskforge:///task/<id>`、`obsidian://open?…`、`x-apple-reminderkit://…`、ホストのある `https:` と `http:`。同じ scheme でも `obsidian://new`、`obsidian://advanced-uri`、`taskforge:///add` のように vault やタスクを書き換えうるリンクは開かない。それ以外のリンクや、URL でない文字列（メモの札は原文をそのまま QR に入れる）は開かず、読み取った文字列を画面に出す。出し方（シートで見せる、下書きに入れるなど）は【builder に任せる】。理由: 紙の QR は誰でも作れるので、任意の scheme を黙って開かない。
- Info.plist に `NSCameraUsageDescription` を足す。アプリは sandbox なし、hardened runtime なし（`app/project.yml`）なので、entitlement は要らない。初回はカメラの許可が出る。
- 許可されていない、カメラがない、のときは、理由を日本語で出す。

## 6. テスト

CLAUDE.md の3層に置く。

- 単体（`app/Core` の XCTest）:
  - repo 入力の解釈（URL、`owner/repo`、余計な末尾、不正な入力）
  - gh の引数（repo あり / なし、assign / レビュー依頼）と、zsh 経由の起動の組み立て（repo 名がシェルに解釈されないこと）
  - assign とレビュー依頼の重複除去
  - TaskNotes の frontmatter の読み取り（status、priority、due、scheduled、projects、id、本文）
  - 完了除外と並び順
  - QR のリンク（id あり → taskforge、なし → obsidian、日本語と空白と `—` を含むファイル名の percent-encode）
  - 札の組み立て（短い本文 / 長い本文で要約、fake の summarizer）
  - QR の往復: このアプリの QR エンコーダ（`ThermalPrinterCore/QR`）で作ったビットマップを Vision で読み、元の文字列と一致すること。taskforge / obsidian（日本語の長いファイル名）/ reminderkit の各リンクで確かめる。§5.4 の「QR に収まるか」もここで確かめる。
  - 読み取った文字列を「開く / 開かず見せる」に振り分ける判定（scheme ごと、URL でない文字列）
- 結合: fixture の vault（`test/` 配下に数件の TaskNotes ファイルと dialect.json）を読み、札を `--dry-run` でプレビューする経路。
- 結合（追加）: 札を `--dry-run --png` で PNG にし、その PNG から Vision で QR を読み、タスクのリンクに戻ること。カメラを使わないクローズドループの確認。
- E2E: プレビューの期待を `test/e2e/preview/<名前>.md` に書く（TaskForge の札）。UI テストと実機印字は、CLAUDE.md の手順どおり、毎回ユーザーに内容・時刻・影響・止め方を伝えて返事を受けてから行う。
- カメラでの読み取りは画面とカメラに触るので、UI テストと同じく、毎回ユーザーに伝えて返事を受けてから行う。
- `.zshenv` の切り替えが実際に効くか（repo を入れて、その owner に合うアカウントの一覧が出るか）は、実 gh を使う確認として、builder がユーザーに見せて確かめる。

## 7. builder に任せること（まとめ）

- 左の欄の各入力欄と行の体裁、レビュー依頼の印
- `Card.Kind` の扱い
- QR に収まらないときの扱い
- frontmatter の読み取り方（YAML ライブラリを足すか、必要な項目だけ読む小さなパーサにするか。依存を足すなら理由を残す）

## 8. 未確定（builder check 後にユーザーへ確認）

なし。builder check で出た問いは、次のとおり決着した。

- QR を読む端末 → Mac（§1）。読み取りはこのアプリに組み込む（§5.5）。iPhone の Obsidian に vault があるかは問わない。
- レビュー依頼の範囲 → 個人宛てだけ（§4.1）。
- 札を作るときの gh アカウント、`.zshenv` が扱わない owner、`deferred` → Claude の判断（§4.2、§5.2）。
