# GitHub の repo 指定・TaskForge の札・QR 読み取り Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** この Mac で Mac アプリをビルド・起動できるようにし、GitHub の欄を repo で絞れるようにし、TaskForge の未完了タスクを札にして、その QR をアプリのカメラで読んでタスクを開けるようにする。

**Architecture:** 判定と組み立ては `app/Core`（`ThermalPrinterCore`、Swift Testing で単体テスト）に置き、`app/App` は表示と `UserDefaults` と OS の API（AVFoundation、`NSWorkspace`）だけを持つ。gh のアカウントは、`~/ghq/github.com/<owner>/` を作業ディレクトリにした `/bin/zsh` 経由で gh を起動して、ユーザーの `~/.zshenv` に決めさせる。QR の読み取りは Vision で、Core に置いてカメラなしで往復テストする。

**Tech Stack:** Swift 6 / SwiftUI（macOS 27）、Swift Testing、Vision、AVFoundation、xcodegen、rake（mise の Ruby 4.0.5）。

**Spec:** `docs/superpowers/specs/2026-11-09-repo-filter-and-taskforge-design.md`

## Global Constraints

- 対象は Mac アプリだけ。`ios/` には手を入れない（ユーザー: 「いまはmacアプリだけでok」）。
- vault には書き込まない。読むだけ。
- org → gh アカウントの対応表をアプリに持たせない。正本は `~/.zshenv`。
- repo 欄が空のときの gh 呼び出しは今と同じ（`GH_CONFIG_DIR` を設定しない）。
- 「URL を直接指定」欄の挙動は変えない。
- レビュー依頼は個人宛てだけ: 検索語 `user-review-requested:@me`。`--review-requested` は使わない。
- TaskForge で除く status は `done` と `cancelled` だけ。
- QR を読んで開いてよい scheme は `taskforge`、`obsidian`、`x-apple-reminderkit`、`https`、`http` だけ。
- プリンターの印字経路には手を入れない（CLAUDE.md の安全規則、親設計書 §6.8）。
- 画面・カメラ・プリンターに触る確認（UI テスト、カメラ読み取り、実機印字）は、毎回ユーザーに内容・時刻・影響・止め方を伝えて返事を受けてから行う。
- コードにはHow、テストにはWhat、コミットログにはWhy。コードは名前と構造で読める形にし、コメントで補わない。
- `vendor/` と `build/` は編集しない。
- Core のテストは `mise exec ruby@4.0.5 -- rake app:test`（= `swift test --package-path app/Core`）。単体だけを回すときは `swift test --package-path app/Core --filter <Suite名>`。Swift は `/usr/bin/swift`。

## Review Focus

- repo 欄に `github.com/owner/repo`（scheme なし）、末尾の `.git` や `/`、前後の空白、大文字小文字違いの owner（`Octo-Org` を `octo-org`）が入る → どれも同じ repo として扱い、作業ディレクトリは実在するディレクトリ名の綴りで選ぶ（Task 2、Task 3）。
- タスクのファイル名に `&`、`+`、`#`、`?`、空白、`—`、`'` が含まれる → `obsidian://` の `file` 値として厳密に percent-encode され、QR を読んで元のパスに戻る（Task 7）。
- frontmatter がない、閉じの `---` がない、値が `"…"` で囲まれている、`projects:` が空、のファイル → 落ちずに、タスクでないものは並ばず、引用符は外れる（Task 5）。
- vault のパスが存在しない・dialect.json が壊れている → 一覧の下にメッセージを出し、dialect は既定値で読む（Task 5、Task 6、Task 10）。
- リンクが長すぎて QR に入らない → 札の作成が例外で失敗せず、QR を省いて注記が出る（Task 7）。

---

## File Structure

Core（`app/Core/Sources/ThermalPrinterCore/`）:

- `Printer/ProcessRunner.swift`（変更）: `SystemProcessRunner` に作業ディレクトリを足す。
- `Sources/GitHub/RepoRef.swift`（新規）: repo 欄の文字列 → `owner/repo`。
- `Sources/GitHub/GitHubListing.swift`（新規）: 一覧の1行の型、gh 検索の引数、結果のまとめ、読み込み。
- `Sources/GitHub/GHAccountScope.swift`（新規）: owner → 作業ディレクトリ、zsh 経由で gh を起動する `ProcessRunner`。
- `Sources/TaskForge/TaskNote.swift`（新規）: TaskNotes ファイル1つの読み取り。
- `Sources/TaskForge/TaskForgeDialect.swift`（新規）: dialect.json の必要な部分。
- `Sources/TaskForge/TaskForgeSource.swift`（新規）: vault から未完了タスクを並べる。
- `Sources/TaskForge/TaskForgeCard.swift`（新規）: リンクと札。
- `QR/QRReader.swift`（新規）: CGImage から QR の文字列を読む（Vision）。
- `QR/ScannedPayload.swift`（新規）: 読んだ文字列を「開く / 見せる」に振り分ける。
- `Card/Card.swift`（変更）: `Kind.task` を足す。

Core のテスト（`app/Core/Tests/ThermalPrinterCoreTests/`）: 上と同じ並びで `Sources/GitHub/`、`Sources/TaskForge/`（fixture は `Sources/TaskForge/Fixtures/vault/`）、`QR/` に置く。fixture ディレクトリは `Package.swift` のテスト target の `exclude` に足す。

結合テスト: `app/Core/Tests/ThermalPrinterIntegrationTests/TaskCardRoundTripTests.swift`（新規）。

E2E: `test/fixtures/cards/task.json`、`test/e2e/preview/task.md`（新規）。

App（`app/App/`）:

- `TodayLoader.swift`（変更）: GitHub の読み込みを Core に移した分を削る。
- `AppModel.swift`（変更）: repo、TaskForge、QR 読み取りの状態。
- `TodayColumn.swift`（変更）: repo 欄、TaskForge の節。
- `SettingsView.swift`（変更）: vault の場所。
- `QRScanView.swift`（新規）: カメラの映像と読み取り。
- `Info.plist`（変更）: `NSCameraUsageDescription`。

文書: `README.md`（変更）。

---

### Task 0: この Mac でビルドと起動を通す

**Files:**
- Modify（食い違いがあったときだけ）: `README.md`

**Interfaces:**
- Produces: `vendor/`、`build/`、`vendor/R2P2-darwin/build/host/bin/picoruby`、`~/Applications/ThermalPrinter.app`。以降の Task の `rake app:test` と結合テストの前提。

- [ ] **Step 1: 作業ブランチを作り、設計書と計画を commit する**

```bash
git switch -c feat/repo-filter-and-taskforge
git add docs/superpowers/specs/2026-11-09-repo-filter-and-taskforge-design.md docs/superpowers/plans/2026-11-09-repo-filter-and-taskforge.md
git commit -m "docs: design and plan for the repo filter, TaskForge cards and QR scanning"
```

- [ ] **Step 2: Ruby 4.0.5 を入れる**

Run: `mise install ruby@4.0.5 && mise exec ruby@4.0.5 -- ruby -v`
Expected: `ruby 4.0.5`

- [ ] **Step 3: vendor と VM を作る**

Run: `mise exec ruby@4.0.5 -- rake vendor:setup && mise exec ruby@4.0.5 -- rake vm:build`
Expected: 成功し、`vendor/R2P2-darwin/build/host/bin/picoruby` が実行可能。失敗したら原因を直す。`port-darwin` や gem の改修が要るなら、手を入れる前にユーザーに相談する。

- [ ] **Step 4: 既存のテストが通ることを確かめる（基準線）**

Run: `mise exec ruby@4.0.5 -- rake app:test`
Expected: すべて PASS（結合テストも VM があるので走る）。落ちるテストがあれば、ここで記録してユーザーに報告する（この計画の変更とは切り分けるため）。

- [ ] **Step 5: アプリを作って置く**

Run: `mise exec ruby@4.0.5 -- rake app:install`
Expected: `~/Applications/ThermalPrinter.app` ができる。

- [ ] **Step 6: 起動の確認をユーザーに頼む**

アプリの起動は画面に触るので、ユーザーに「`~/Applications/ThermalPrinter.app` を起動して、左の欄に GitHub とリマインダーが並ぶか見てほしい」と伝えて、結果を受ける。README の手順と食い違った点があれば README を直して commit する（`docs: …`）。

---

### Task 1: `SystemProcessRunner` に作業ディレクトリを足す

**Files:**
- Modify: `app/Core/Sources/ThermalPrinterCore/Printer/ProcessRunner.swift`
- Test: `app/Core/Tests/ThermalPrinterCoreTests/Printer/SystemProcessRunnerTests.swift`（新規。既存があればそこに足す）

**Interfaces:**
- Produces: `SystemProcessRunner.init(outputLimit: Int = defaultOutputLimit, currentDirectory: URL? = nil)`。`currentDirectory` が nil なら今と同じ。

- [ ] **Step 1: Write the failing test**

```swift
@Test func aRunnerGivenADirectoryStartsTheProcessThere() async throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "runner-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let outcome = try await SystemProcessRunner(currentDirectory: dir)
        .run(executable: URL(filePath: "/bin/pwd"), arguments: ["-P"])
    #expect(outcome.output.trimmingCharacters(in: .whitespacesAndNewlines)
        == dir.resolvingSymlinksInPath().path)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path app/Core --filter SystemProcessRunnerTests`
Expected: FAIL（`currentDirectory` という引数がない）

- [ ] **Step 3: `currentDirectory` を保持し、`process.currentDirectoryURL` に入れる**

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path app/Core --filter SystemProcessRunnerTests`
Expected: PASS

- [ ] **Step 5: Commit**（`feat: let the process runner start a command in a given directory` — Why: gh のアカウントを、ユーザーの .zshenv が作業ディレクトリで選ぶため）

---

### Task 2: repo 欄の解釈（`RepoRef`）

**Files:**
- Create: `app/Core/Sources/ThermalPrinterCore/Sources/GitHub/RepoRef.swift`
- Test: `app/Core/Tests/ThermalPrinterCoreTests/Sources/GitHub/RepoRefTests.swift`

**Interfaces:**
- Produces: `public struct RepoRef: Equatable, Sendable, Codable { public let owner: String; public let name: String; public var nameWithOwner: String }`、`public static func parse(_ text: String) -> RepoRef?`

- [ ] **Step 1: Write the failing test**

```swift
@Test(arguments: [
    "octo-org/sample",
    "  octo-org/sample  ",
    "https://github.com/octo-org/sample",
    "https://github.com/octo-org/sample/",
    "https://github.com/octo-org/sample.git",
    "https://github.com/octo-org/sample/issues/12",
    "https://www.github.com/octo-org/sample/pull/3",
    "github.com/octo-org/sample",
])
func everyFormOfTheSameRepoParsesToOwnerAndName(text: String) {
    #expect(RepoRef.parse(text) == RepoRef(owner: "octo-org", name: "sample"))
}

@Test(arguments: ["", "octo-org", "octo-org/sample/extra words", "https://example.com/a/b",
                  "-bad/repo", "owner/..", "owner/re po", "a/b; rm -rf ~"])
func textThatIsNotARepoParsesToNil(text: String) {
    #expect(RepoRef.parse(text) == nil)
}
```

`"octo-org/sample/extra words"` のように `owner/repo` 形式で3つ目以降の部分があるものは nil（URL 形式のときだけ後ろを捨てる）。owner と repo の文字の規則は `GitHubHandler.isOwner` / `isRepo` と同じにする（そちらを `RepoRef` に移して両方から使う）。

- [ ] **Step 2: Run test to verify it fails** — `swift test --package-path app/Core --filter RepoRefTests` → FAIL（`RepoRef` がない）
- [ ] **Step 3: `RepoRef.parse` を実装し、`GitHubHandler` の owner / repo 判定を `RepoRef` の判定に置き換える**
- [ ] **Step 4: Run tests** — `swift test --package-path app/Core --filter "RepoRefTests|GitHubHandlerTests"` → PASS
- [ ] **Step 5: Commit**（`feat: read a repo from a URL or owner/repo` — Why: GitHub の欄を1つの repo に絞るため）

---

### Task 3: gh をアカウントの決まる場所で起動する（`GHAccountScope`、`ScopedGHRunner`）

**Files:**
- Create: `app/Core/Sources/ThermalPrinterCore/Sources/GitHub/GHAccountScope.swift`
- Test: `app/Core/Tests/ThermalPrinterCoreTests/Sources/GitHub/GHAccountScopeTests.swift`

**Interfaces:**
- Consumes: `RepoRef`（Task 2）、`SystemProcessRunner(currentDirectory:)`（Task 1）
- Produces:
  - `public enum GHAccountScope { public static let defaultGhqRoot: URL /* ~/ghq/github.com */; public static func directory(for owner: String, ghqRoot: URL = defaultGhqRoot, fileManager: FileManager = .default) -> URL? }` — `ghqRoot` 直下で、名前が owner と大文字小文字を無視して一致するディレクトリを、実在する綴りで返す。なければ nil。
  - `public struct ScopedGHRunner: ProcessRunner { public init(base: any ProcessRunner) }` — `run(executable: gh, arguments: args)` を `base.run(executable: URL(filePath: "/bin/zsh"), arguments: ["-c", "exec \"$@\"", "zsh", gh.path] + args)` に変える。
  - `public static func runner(for repo: RepoRef?, ghqRoot: URL = defaultGhqRoot) -> any ProcessRunner`（`GHAccountScope` に置く）— repo が nil か、ディレクトリがなければ `SystemProcessRunner()`。あれば `ScopedGHRunner(base: SystemProcessRunner(currentDirectory: dir))`。

`.zshenv` は `"$PWD/"` を `<owner>/*` と比べるので、`~/ghq/github.com/<owner>` 自体が作業ディレクトリで合う（`*` は空にも一致する。2026-11-09 に `~/ghq/github.com/<owner>` で zsh を起動し、`GH_CONFIG_DIR` が切り替わることを確認済み）。

- [ ] **Step 1: Write the failing tests**

```swift
@Test func theOwnerDirectoryIsFoundIgnoringCaseAndReturnedWithItsRealSpelling() throws {
    let root = try makeTempDir()          // 中に "Octo-Org" と "other-org" を作る
    #expect(GHAccountScope.directory(for: "octo-org", ghqRoot: root)?.lastPathComponent == "Octo-Org")
    #expect(GHAccountScope.directory(for: "other-org", ghqRoot: root)?.lastPathComponent == "other-org")
}

@Test func anOwnerWithoutADirectoryHasNoScope() throws {
    #expect(GHAccountScope.directory(for: "nobody", ghqRoot: try makeTempDir()) == nil)
}

@Test func theScopedRunnerHandsGhAndItsArgumentsToZshAsPositionalArguments() async throws {
    let base = RecordingRunner()
    _ = try await ScopedGHRunner(base: base).run(
        executable: URL(filePath: "/opt/homebrew/bin/gh"), arguments: ["search", "prs", "a/b; rm -rf ~"])
    #expect(base.lastExecutable == URL(filePath: "/bin/zsh"))
    #expect(base.lastArguments == ["-c", "exec \"$@\"", "zsh", "/opt/homebrew/bin/gh", "search", "prs", "a/b; rm -rf ~"])
}

@Test func theScopedRunnerRunsTheCommandInsideZshForReal() async throws {
    let outcome = try await ScopedGHRunner(base: SystemProcessRunner())
        .run(executable: URL(filePath: "/bin/echo"), arguments: ["$HOME", "a b"])
    #expect(outcome.output == "$HOME a b\n")   // 引数がシェルに解釈されない
}
```

`RecordingRunner` は `GitHubHandlerTests` にある fake と同じ形（なければテスト内に置く）。

- [ ] **Step 2: Run** — `swift test --package-path app/Core --filter GHAccountScopeTests` → FAIL
- [ ] **Step 3: 実装する**
- [ ] **Step 4: Run** → PASS
- [ ] **Step 5: Commit**（`feat: start gh from the owner's ghq directory so the user's zshenv picks the account` — Why: org ごとのアカウントの正本を .zshenv だけに保つ）

---

### Task 4: GitHub の一覧（assign とレビュー依頼、repo 絞り込み）を Core に置く

**Files:**
- Create: `app/Core/Sources/ThermalPrinterCore/Sources/GitHub/GitHubListing.swift`
- Modify: `app/App/TodayLoader.swift`（`TodayIssue`、`ghArguments`、`issues`、`search` を削り、Core を使う）、`app/App/AppModel.swift`（`TodayIssue` → `GitHubListing`）、`app/App/TodayColumn.swift`
- Test: `app/Core/Tests/ThermalPrinterCoreTests/Sources/GitHub/GitHubListingTests.swift`

**Interfaces:**
- Consumes: `RepoRef`、`GHLocator`、`ProcessRunner`
- Produces:
  - `public struct GitHubListing: Identifiable, Equatable, Sendable { number: Int; repository: String; title: String; url: String; isPullRequest: Bool; isReviewRequest: Bool; var id: String /* "github:\(url)" */; var label: String }` — `label` は今の `TodayIssue.label`（`"<repo> PR #3"`）に、`isReviewRequest` のとき末尾に `" レビュー依頼"` を付ける（印の体裁は builder に任されているが、この文字列を既定とする）。
  - `public enum GitHubListingLoader { static func arguments(noun: String, assigned: Bool, repo: RepoRef?) -> [String]; public static func load(repo: RepoRef?, runner: any ProcessRunner, locator: GHLocator = GHLocator()) async throws -> [GitHubListing] }`
  - `public enum GitHubListingError: Error, LocalizedError { case ghMissing, ghFailed(String), unreadable }`（今の `TodayLoadError` を移す。メッセージ文言はそのまま）

- [ ] **Step 1: Write the failing tests**

```swift
@Test func assignedSearchesKeepTheirCurrentArgumentsWhenNoRepoIsGiven() {
    #expect(GitHubListingLoader.arguments(noun: "issues", assigned: true, repo: nil) ==
        ["search", "issues", "--assignee", "@me", "--state", "open",
         "--sort", "updated", "--limit", "50", "--json", "number,title,repository,url"])
}

@Test func aRepoNarrowsEverySearch() {
    let repo = RepoRef(owner: "octo-org", name: "sample")
    #expect(GitHubListingLoader.arguments(noun: "prs", assigned: true, repo: repo)
        .contains(sequence: ["--repo", "octo-org/sample"]))
}

@Test func reviewRequestsAskForPersonalRequestsOnly() {
    let args = GitHubListingLoader.arguments(noun: "prs", assigned: false, repo: nil)
    #expect(args.contains("user-review-requested:@me"))
    #expect(!args.contains("--review-requested"))
    #expect(!args.contains("--assignee"))
}

@Test func aPullRequestBothAssignedAndUnderReviewIsListedOnceAsAssigned() async throws {
    // fake runner: issues → [#1], prs assigned → [#3], prs review → [#3, #4]
    let listings = try await GitHubListingLoader.load(repo: nil, runner: fake, locator: present)
    #expect(listings.map(\.number) == [1, 3, 4])
    #expect(listings.map(\.isReviewRequest) == [false, false, true])
}

@Test func aFailingGhSurfacesItsFirstLine() async { /* exit 1, "HTTP 401: Bad credentials\n…" → ghFailed("HTTP 401: Bad credentials") */ }
```

並びは今と同じ「issue → assign の PR」の後ろに、レビュー依頼だけの PR を足す。

- [ ] **Step 2: Run** — `swift test --package-path app/Core --filter GitHubListingTests` → FAIL
- [ ] **Step 3: Core に実装し、App 側を `GitHubListing` / `GitHubListingLoader.load(repo: nil, runner: SystemProcessRunner())` に置き換える（この Task では repo 欄はまだ作らない）**
- [ ] **Step 4: Run** — `mise exec ruby@4.0.5 -- rake app:test` → PASS、`mise exec ruby@4.0.5 -- rake app:build` → 成功
- [ ] **Step 5: Commit**（`feat: list pull requests that ask me for a review` — Why: ユーザーは自分宛てのレビュー依頼も朝の札にしたい。チーム宛ては要らない）

---

### Task 5: TaskNotes ファイルと dialect を読む（`TaskNote`、`TaskForgeDialect`）

**Files:**
- Create: `app/Core/Sources/ThermalPrinterCore/Sources/TaskForge/TaskNote.swift`、`TaskForgeDialect.swift`
- Create: `app/Core/Tests/ThermalPrinterCoreTests/Sources/TaskForge/Fixtures/vault/`（下記）
- Modify: `app/Core/Package.swift`（テスト target の `exclude` に `Sources/TaskForge/Fixtures` を足す）
- Test: `app/Core/Tests/ThermalPrinterCoreTests/Sources/TaskForge/TaskNoteTests.swift`

**Interfaces:**
- Produces:
  - `public struct TaskForgeDialect: Equatable, Sendable { folder: String; fields: Fields /* status, priority, due, scheduled, projects, id の項目名 */; public static let standard: TaskForgeDialect /* 00_TaskNotes と既定の項目名 */; public static func load(vault: URL) -> TaskForgeDialect }` — `TaskForge/Settings/dialect.json` の `tasknotes.folder` と `tasknotes.field_names`（`user_task_id` → id）を読む。読めないときは `standard`。
  - `public struct TaskNote: Equatable, Sendable { title: String; relativePath: String /* vault からの相対、.md 込み */; status: String; priority: String?; due: DateComponents?; scheduled: DateComponents?; dueHasTime: Bool; projects: [String] /* [[ ]] を外した名前 */; stableID: String?; body: String }`
  - `public static func parse(relativePath: String, contents: String, dialect: TaskForgeDialect) -> TaskNote?` — frontmatter に status がなければ nil。`title` はファイル名から `.md` を除いたもの。

frontmatter は外部ライブラリを足さず、必要な項目だけを読む小さなパーサにする【Claude の判断: 項目が `key: value` と `key:` + `  - item` のリストだけで足りるため】。値の前後の `"` / `'` は外す。日付は `YYYY-MM-DD` と `YYYY-MM-DDTHH:mm`（秒・タイムゾーン付きも可）を受ける。

fixture（`Fixtures/vault/`）:
- `TaskForge/Settings/dialect.json`: 実 vault の `tasknotes` 部分だけを写したもの
- `00_TaskNotes/週次レポート — draft PR #1234 & 手直し + 提出.md`: status open、projects `"[[Sample Project]]"`、本文あり
- `00_TaskNotes/期限つき.md`: status planned、`due: 2026-11-12`、`scheduled: "2026-11-10T09:00"`、priority high、`id: weekly-report`
- `00_TaskNotes/いつか.md`: status someday、priority none
- `00_TaskNotes/済み.md`: status done
- `00_TaskNotes/取り消し.md`: status cancelled
- `00_TaskNotes/メモ.md`: frontmatter なし
- `00_TaskNotes/壊れ.md`: 閉じの `---` がない

- [ ] **Step 1: Write the failing tests**

```swift
@Test func aTaskFileYieldsItsTitleStatusProjectsAndBody() throws {
    let note = try #require(TaskNote.parse(relativePath: "00_TaskNotes/週次レポート — draft PR #1234 & 手直し + 提出.md",
                                           contents: fixture("00_TaskNotes/週次レポート — draft PR #1234 & 手直し + 提出.md"),
                                           dialect: .standard))
    #expect(note.title == "週次レポート — draft PR #1234 & 手直し + 提出")
    #expect(note.status == "open")
    #expect(note.projects == ["Sample Project"])
    #expect(note.body.hasPrefix("## 関連"))
}

@Test func datesPriorityAndTheStableIDAreRead() throws { /* 期限つき.md: due 2026-11-12 (dueHasTime false), scheduled 2026-11-10 09:00, priority "high", stableID "weekly-report" */ }

@Test(arguments: ["00_TaskNotes/メモ.md", "00_TaskNotes/壊れ.md"])
func aFileWithoutAUsableFrontmatterIsNotATask(path: String) throws {
    #expect(TaskNote.parse(relativePath: path, contents: try fixture(path), dialect: .standard) == nil)
}

@Test func theDialectNamesTheFolderAndTheIDField() throws {
    let dialect = TaskForgeDialect.load(vault: fixtureVault)
    #expect(dialect.folder == "00_TaskNotes")
    #expect(dialect.fields.id == "id")
}

@Test func aVaultWithoutADialectFallsBackToTheStandardOne() {
    #expect(TaskForgeDialect.load(vault: URL(filePath: "/nonexistent")) == .standard)
}
```

- [ ] **Step 2: Run** — `swift test --package-path app/Core --filter TaskNoteTests` → FAIL
- [ ] **Step 3: 実装する**
- [ ] **Step 4: Run** → PASS
- [ ] **Step 5: Commit**（`feat: read TaskNotes task files and the TaskForge dialect` — Why: TaskForge のタスクを札にするため。vault には書かない）

---

### Task 6: 未完了タスクを並べる（`TaskForgeSource`）

**Files:**
- Create: `app/Core/Sources/ThermalPrinterCore/Sources/TaskForge/TaskForgeSource.swift`
- Test: `app/Core/Tests/ThermalPrinterCoreTests/Sources/TaskForge/TaskForgeSourceTests.swift`

**Interfaces:**
- Consumes: `TaskNote`、`TaskForgeDialect`（Task 5）
- Produces:
  - `public enum TaskForgeSource { public static let excludedStatuses: Set<String> = ["done", "cancelled"]; public static func openTasks(vault: URL, fileManager: FileManager = .default) throws -> [TaskNote]; static func sorted(_ notes: [TaskNote]) -> [TaskNote] }`
  - `public enum TaskForgeSourceError: Error, LocalizedError { case vaultMissing(String) }` — メッセージ `"vault が見つかりません（<path>）"`
  - `TaskNote.id: String` = `"task:\(relativePath)"`（左の欄のチェックのキー）

並び: `scheduled` 昇順 → `due` 昇順（値のないものは後ろ）→ priority 降順（`highest > high > medium > low > lowest > none`、不明・なしは `none` 扱い）→ タイトル昇順（同順位を安定させる。Claude の判断）。フォルダ直下の `.md` だけを読む（サブフォルダは読まない。今の vault に無く、archive を拾わないため）。

- [ ] **Step 1: Write the failing tests**

```swift
@Test func doneAndCancelledTasksAndNonTasksAreLeftOut() throws {
    let titles = try TaskForgeSource.openTasks(vault: fixtureVault).map(\.title)
    #expect(Set(titles) == ["週次レポート — draft PR #1234 & 手直し + 提出", "期限つき", "いつか"])
}

@Test func deferredIsListedBecauseItIsNotFinished() { /* status deferred の TaskNote を sorted に通すと残る — openTasks のフィルタを純関数 isOpen(_:) にして確かめる */ }

@Test func tasksAreOrderedByScheduledThenDueThenPriority() {
    // a: scheduled 11/10 / b: scheduled なし due 11/11 / c: どちらもなし priority high / d: どちらもなし priority low
    #expect(TaskForgeSource.sorted([d, c, b, a]).map(\.title) == ["a", "b", "c", "d"])
}

@Test func aMissingVaultIsReportedByItsPath() {
    #expect(throws: TaskForgeSourceError.vaultMissing("/nonexistent")) {
        try TaskForgeSource.openTasks(vault: URL(filePath: "/nonexistent"))
    }
}
```

- [ ] **Step 2: Run** — `swift test --package-path app/Core --filter TaskForgeSourceTests` → FAIL
- [ ] **Step 3: 実装する**
- [ ] **Step 4: Run** → PASS
- [ ] **Step 5: Commit**（`feat: list unfinished TaskForge tasks in the Kanban order` — Why: ユーザーは完了分以外をすべて、TaskForge と同じ順で見たい）

---

### Task 7: QR を読む（`QRReader`）と、タスクのリンクと札（`TaskForgeLink`、`TaskForgeCard`）

QR の往復テストで札の QR を確かめるので、読み取りを先に置く。

**Files:**
- Create: `app/Core/Sources/ThermalPrinterCore/QR/QRReader.swift`
- Create: `app/Core/Sources/ThermalPrinterCore/Sources/TaskForge/TaskForgeCard.swift`
- Modify: `app/Core/Sources/ThermalPrinterCore/Card/Card.swift`（`Kind` に `case task`）
- Test: `app/Core/Tests/ThermalPrinterCoreTests/QR/QRReaderTests.swift`、`app/Core/Tests/ThermalPrinterCoreTests/Sources/TaskForge/TaskForgeCardTests.swift`

**Interfaces:**
- Consumes: `TaskNote`（Task 5）、`QRCode`、`QRPayload.maxCardModules`、`CardRenderer`、`Bitmap1.cgImage()`、`TextDigest`、`Summarizer`
- Produces:
  - `public enum QRReader { public static func payloads(in image: CGImage) throws -> [String] }` — Vision の `VNDetectBarcodesRequest`、symbology は `.qr` だけ。
  - `public enum TaskForgeLink { public static func url(for task: TaskNote, vaultName: String) -> String }` — `stableID` があれば `"taskforge:///task/" + enc(stableID)`、なければ `"obsidian://open?vault=" + enc(vaultName) + "&file=" + enc(relativePath から末尾の .md を除いたもの)`。`enc` は英数字と `-._~` 以外をすべて percent-encode（`/` も `%2F` にする）。
  - `public enum TaskForgeCard { public static let qrOmittedNote = "リンクが長く QR に入らないため、QR を省いています"; public static func make(_ task: TaskNote, vaultName: String, now: Date, calendar: Calendar = .current, summarizer: any Summarizer) async -> Card }`
    - `kind: .task`、`url`: リンク（`QRCode.moduleCount(for:)` が `QRPayload.maxCardModules` を超えるなら nil にして `note` に `qrOmittedNote`）
    - `header.lines`: `[projects を " ・ " でつないだもの]`（空なら `["TaskForge"]`）、`header.emphasis`: status
    - `header.sublines`: `"予定 <日付>"` と `"期限 <日付>"`（あるものだけ、この順）。日付の書き方は `ReminderCard.dueLine` と同じ（今日 / 明日 / 昨日 / `M/d(曜)` / 年が違えば `yyyy/`、時刻があれば ` HH:mm`）。`ReminderCard` の日付文字列の関数を `internal static` に切り出して共有する。
    - title と sections: `ReminderCard.make` と同じ分岐（`タイトル + 本文` が `SummaryKind.heading.characterLimit` 以下なら `"☐ " + title` と本文そのまま、超えたら `TextDigest`）。本文は frontmatter を除いたもの。

- [ ] **Step 1: Write the failing tests**

```swift
// QRReaderTests
@Test(arguments: [
    "taskforge:///task/weekly-report",
    "obsidian://open?vault=my-vault&file=" + "00_TaskNotes/週次レポート — draft PR #1234 & 手直し + 提出".strictlyEncoded,
    "x-apple-reminderkit://REMCDReminder/0E1F",
])
func aQRDrawnByThisAppIsReadBackToTheSameText(text: String) throws {
    let qr = try QRCode(text)
    var bitmap = Bitmap1(height: qr.sideDots + 32)      // 周りに白の余白
    qr.draw(into: &bitmap, x: 16, y: 16)
    #expect(try QRReader.payloads(in: #require(bitmap.cgImage())) == [text])
}

@Test func anImageWithoutAQRYieldsNothing() throws { /* 白いだけの Bitmap1 → [] */ }

// TaskForgeCardTests
@Test func aTaskWithAStableIDLinksToTaskForge() {
    #expect(TaskForgeLink.url(for: task(stableID: "weekly-report"), vaultName: "my-vault")
        == "taskforge:///task/weekly-report")
}

@Test func aTaskWithoutAStableIDLinksToItsFileInObsidian() {
    #expect(TaskForgeLink.url(for: task(relativePath: "00_TaskNotes/a & b+c #1?.md"), vaultName: "my-vault")
        == "obsidian://open?vault=my-vault&file=00_TaskNotes%2Fa%20%26%20b%2Bc%20%231%3F")
}

@Test func theCardCarriesProjectsStatusDatesAndACheckbox() async { /* projects ["Sample Project"], status "planned", scheduled 今日 09:00, due 明日 → header.lines ["Sample Project"], emphasis "planned", sublines ["予定 今日 09:00", "期限 明日"], title "☐ 期限つき", kind .task */ }

@Test func aLongTaskIsSummarized() async { /* FixedSummarizer で heading/digest が入る（ReminderCardTests と同じ形） */ }

@Test func everyFixtureTaskCardRendersAndItsQRReadsBackToItsLink() async throws {
    for note in try TaskForgeSource.openTasks(vault: fixtureVault) {
        let card = await TaskForgeCard.make(note, vaultName: "my-vault", now: morning, summarizer: Passthrough())
        let rendered = try CardRenderer().render(card)
        #expect(try QRReader.payloads(in: #require(rendered.bitmap.cgImage())) == [card.url!])
    }
}

@Test func aLinkTooLongForTheQRIsLeftOutWithANote() async {
    let card = await TaskForgeCard.make(task(relativePath: "00_TaskNotes/" + String(repeating: "長", count: 400) + ".md"), …)
    #expect(card.url == nil)
    #expect(card.note == TaskForgeCard.qrOmittedNote)
}
```

`strictlyEncoded` はテスト側のヘルパー（`TaskForgeLink` と同じ規則）。実 vault の最長のファイル名と同じ長さ（60字ほど）の名前でも、往復テストに1件足して確かめる。

- [ ] **Step 2: Run** — `swift test --package-path app/Core --filter "QRReaderTests|TaskForgeCardTests"` → FAIL
- [ ] **Step 3: `QRReader` を実装する**
- [ ] **Step 4: Run** — `--filter QRReaderTests` → PASS
- [ ] **Step 5: `Kind.task`、`TaskForgeLink`、`TaskForgeCard` を実装する（`ReminderCard` の日付文字列を共有に切り出す）**
- [ ] **Step 6: Run** — `swift test --package-path app/Core --filter "QRReaderTests|TaskForgeCardTests|ReminderCardTests|CardCodingTests"` → PASS
- [ ] **Step 7: Commit**（`feat: turn a TaskForge task into a card whose QR opens the task` — Why: ID のないタスクは TaskForge の deeplink を作れないので、Obsidian でファイルを開くリンクにする）

---

### Task 8: 読んだ文字列の振り分け（`ScannedPayload`）

**Files:**
- Create: `app/Core/Sources/ThermalPrinterCore/QR/ScannedPayload.swift`
- Test: `app/Core/Tests/ThermalPrinterCoreTests/QR/ScannedPayloadTests.swift`

**Interfaces:**
- Produces: `public enum ScannedPayload: Equatable, Sendable { case open(URL); case show(String); public static let openableSchemes: Set<String> = ["taskforge", "obsidian", "x-apple-reminderkit", "https", "http"]; public static func classify(_ text: String) -> ScannedPayload }`

- [ ] **Step 1: Write the failing tests**

```swift
@Test(arguments: ["taskforge:///task/a", "obsidian://open?vault=v&file=f", "x-apple-reminderkit://REMCDReminder/1",
                  "https://github.com/a/b/issues/1", "HTTP://example.com"])
func linksThisAppPutsInQRsAreOpened(text: String) {
    #expect(ScannedPayload.classify(text) == .open(URL(string: text)!))
}

@Test(arguments: ["file:///etc/passwd", "javascript:alert(1)", "tel:0120", "会議メモの原文です", "", "https://"])
func anythingElseIsShownNotOpened(text: String) {
    #expect(ScannedPayload.classify(text) == .show(text))
}
```

`https://` のように host のない http(s) は開かない。

- [ ] **Step 2: Run** → FAIL
- [ ] **Step 3: 実装する**
- [ ] **Step 4: Run** → PASS
- [ ] **Step 5: Commit**（`feat: decide which scanned QR texts may be opened` — Why: 紙の QR は誰でも作れるので、このアプリが入れる種類のリンクだけを開く）

---

### Task 9: App — repo 欄と、そのアカウントでの札作り

**Files:**
- Modify: `app/App/AppModel.swift`、`app/App/TodayColumn.swift`

**Interfaces:**
- Consumes: `RepoRef`、`GHAccountScope.runner(for:)`、`GitHubListingLoader.load`、`URLHandlerRegistry.standard(runner:summarizer:)`
- Produces（App 内）: `AppModel.repoFilter: RepoRef?`、`AppModel.repoText: String`、`AppModel.repoMessage: String?`、`func applyRepoText(_ text: String) async`、`static let repoFilterDefaultsKey = "githubRepoFilter"`

振る舞い:
- 欄の Enter で `applyRepoText`。空なら `repoFilter = nil`。`RepoRef.parse` が nil なら `repoMessage = "owner/repo か GitHub の URL を入れてください"` にして一覧を変えない。読めたら保存して `loadIssues()`。
- `loadIssues()` は `GitHubListingLoader.load(repo: repoFilter, runner: GHAccountScope.runner(for: repoFilter))`。
- 一覧の行から札を作るとき（`setIssue`）は、`URLHandlerRegistry.standard(runner: GHAccountScope.runner(for: repoFilter), summarizer:)` で作った registry を使う。「URL を直接指定」欄は今の `registry` のまま。
- 節の見出しを `"GitHub（自分 assign・レビュー依頼・open）"` に、repo 指定中は `"GitHub（<owner/repo>）"` にする。欄の placeholder は `"repo（owner/repo か URL。空なら全 repo）"`、`accessibilityIdentifier("repoField")`。

- [ ] **Step 1: 実装する**
- [ ] **Step 2: Run** — `mise exec ruby@4.0.5 -- rake app:test && mise exec ruby@4.0.5 -- rake app:build` → 成功
- [ ] **Step 3: 実 gh での確認をユーザーに頼む**（画面に触るので、伝えて返事を受けてから）: アプリを `rake app:install` で入れ替え、repo 欄に `~/ghq/github.com/` にある owner の repo を入れる → その repo の自分宛てだけが並ぶ、別の owner の repo を入れる → その owner に合うアカウントの結果が並ぶ（またはエラーでなく空）、`.zshenv` が扱わない owner の repo を入れる → gh のエラーが欄の下に出る、空に戻す → 今と同じ一覧。
- [ ] **Step 4: Commit**（`feat: narrow the GitHub column to one repo and fetch it as the account that owns it` — Why: 仕事の repo だけを見たい。アカウントはユーザーの .zshenv が決める）

---

### Task 10: App — TaskForge の節と vault の設定

**Files:**
- Modify: `app/App/AppModel.swift`、`app/App/TodayColumn.swift`、`app/App/SettingsView.swift`

**Interfaces:**
- Consumes: `TaskForgeSource.openTasks`、`TaskForgeCard.make`、`TaskNote.id`
- Produces（App 内）: `AppModel.vaultPath: String`（`static let vaultPathDefaultsKey = "taskForgeVaultPath"`、既定は空文字。個人の場所を直書きしない）、`tasks: [TaskNote]`、`tasksMessage: String?`、`tasksLoading: Bool`、`func loadTasks() async`、`func setTask(_ task: TaskNote, checked: Bool)`、`func setVaultPath(_ path: String)`

振る舞い:
- `refreshToday` で GitHub、リマインダーと並べて `loadTasks()` を呼ぶ。「更新」ボタンも同じ。
- ファイルの読み取りはメインスレッドの外で行う（`Task.detached` か nonisolated の関数）。
- 節の見出し `"TaskForge（未完了）"`。行はタスク名と、`status` と期限・予定（あれば）を caption で。`accessibilityIdentifier("todayTask-\(task.title)")`。
- 0件なら `"未完了のタスクはありません"`、エラーなら `localizedDescription` を `tasksMessage` に。
- `setTask` は `setReminder` と同じ形（pendingKeys、pendingCards、`TaskForgeCard.make(task, vaultName: URL(filePath: vaultPath).lastPathComponent, now: Date(), summarizer:)`）。
- 設定画面に vault の場所の TextField（`accessibilityIdentifier("vaultPathField")`）。変えたら `loadTasks()`。

- [ ] **Step 1: 実装する**
- [ ] **Step 2: Run** — `mise exec ruby@4.0.5 -- rake app:test && mise exec ruby@4.0.5 -- rake app:build` → 成功
- [ ] **Step 3: 画面の確認をユーザーに頼む**（伝えて返事を受けてから）: 実 vault の未完了タスク（2026-11-09 時点で20件）が並び、1件チェックすると札のプレビューに見出し・要約・QR が出る。
- [ ] **Step 4: Commit**（`feat: list TaskForge tasks in the Mac app and make cards from them` — Why: TaskForge で管理しているタスクを、リマインダーと同じく朝の札にしたい）

---

### Task 11: App — QR を読む

**Files:**
- Create: `app/App/QRScanView.swift`
- Modify: `app/App/AppModel.swift`、`app/App/ContentView.swift`（または `FooterBar.swift`。ボタンの置き場所は builder に任せる）、`app/App/Info.plist`

**Interfaces:**
- Consumes: `QRReader`（Task 7。カメラのフレームを `CGImage` にして渡すか、`VNDetectBarcodesRequest` を `CVPixelBuffer` に直接かけるかは builder に任せる。判定のロジックを Core と二重に持たないこと）、`ScannedPayload.classify`（Task 8）
- Produces（App 内）: `AppModel.isScanning: Bool`、`scannedText: String?`、`func handleScanned(_ text: String)`

振る舞い:
- 「QR を読む」ボタン（`accessibilityIdentifier("scanQRButton")`）でシートを開き、`AVCaptureSession` の映像を出す。カメラは `AVCaptureDevice.DiscoverySession`（`.builtInWideAngleCamera`、`.continuityCamera`、`.external`）の先頭を既定にし、複数あれば Picker で選べる。
- 最初の QR を読んだらセッションを止めてシートを閉じ、`handleScanned`: `.open(url)` → `NSWorkspace.shared.open(url)`、`.show(text)` → `scannedText` に入れて、読み取った文字列を出すシート（コピーのボタン付き）を見せる。
- カメラが未許可・拒否・見つからないときは、シートに理由を日本語で出す（`"カメラへのアクセスが許可されていません。システム設定の「プライバシーとセキュリティ」で許可してください"`、`"使えるカメラが見つかりません"`）。
- `Info.plist` に `NSCameraUsageDescription`: `"印字した札の QR コードを読み取るためにカメラを使います"`。
- シートを閉じたら、必ずセッションを止める。

- [ ] **Step 1: 実装する**
- [ ] **Step 2: Run** — `mise exec ruby@4.0.5 -- rake app:test && mise exec ruby@4.0.5 -- rake app:install` → 成功
- [ ] **Step 3: カメラでの確認をユーザーに頼む**（カメラと画面に触るので、内容・時刻・影響・止め方を伝えて返事を受けてから）: 画面に出した札のプレビュー、または印字済みの札の QR をかざし、Obsidian でそのタスクが開くこと。メモの札の QR では文字列のシートが出ること。
- [ ] **Step 4: Commit**（`feat: scan a card's QR with the Mac camera and open what it links to` — Why: 印字した札からタスクに戻れる、ループを閉じるため）

---

### Task 12: 結合と E2E — 札を CLI の PNG にして QR を読み戻す

**Files:**
- Create: `app/Core/Tests/ThermalPrinterIntegrationTests/TaskCardRoundTripTests.swift`
- Create: `test/fixtures/cards/task.json`、`test/e2e/preview/task.md`
- Modify: `app/Core/Tests/ThermalPrinterIntegrationTests/RealCLIPreviewTests.swift`（`@Test(arguments:)` に `"task"` を足す）

**Interfaces:**
- Consumes: `RealCLI`（既存）、`TaskForgeSource`、`TaskForgeCard`、`CardRenderer`、`QRReader`

- [ ] **Step 1: Write the test**

```swift
@Suite(.enabled(if: RealCLI.vmExists, "product VM not built: run rake vm:build or set PHOMEMO_PICORUBY"))
struct TaskCardRoundTripTests {
    @Test func aTaskCardPreviewedByTheRealCLIStillCarriesTheTaskLinkInItsQR() async throws {
        // ThermalPrinterCoreTests の fixture vault を #filePath から辿って読む
        let note = try #require(try TaskForgeSource.openTasks(vault: fixtureVault).first)
        let card = await TaskForgeCard.make(note, vaultName: "my-vault", now: Date(), summarizer: Passthrough())
        let bitmap = StripComposer().compose([.card(card)]).bitmap
        let directory = try RealCLI.makeWorkDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try #require(try await RealCLI.client(workDirectory: directory).preview(bitmap).image)
        #expect(try QRReader.payloads(in: image) == [card.url!])
    }
}
```

`task.json` は、`期限つき` 相当の内容（`kind: "task"`、header、title、sections、`url: "obsidian://open?vault=my-vault&file=00_TaskNotes%2F…"`）を `CardCodingTests` の形式で書く。`task.md` は `reminder.md` と同じ書き方で、見出し・status・予定と期限の行・本文・右上の QR を期待として書く。

- [ ] **Step 2: Run** — `mise exec ruby@4.0.5 -- rake app:test` → PASS（新しい結合テストと `"task"` のプレビューを含む）
- [ ] **Step 3: Run** — `mise exec ruby@4.0.5 -- rake test:e2e:preview` → `task` を含めて合格
- [ ] **Step 4: Commit**（`test: check that a task card keeps its link through the real CLI preview` — Why: 印字と同じ経路を通っても QR からタスクに戻れることを、カメラなしで確かめる）

---

### Task 13: README を更新する

**Files:**
- Modify: `README.md`（「アプリ」の節）

- [ ] **Step 1: 書き足す**: repo 欄（受け付ける形、自分 assign と個人宛てレビュー依頼、空なら全 repo、gh アカウントは `~/ghq/github.com/<owner>` で起動した zsh の `.zshenv` が決めること）、TaskForge の節（vault の場所の設定、完了と取り消し以外を Kanban の順で、QR は `id` があれば TaskForge、なければ Obsidian）、「QR を読む」（開くリンクの種類、それ以外は文字列を表示、初回のカメラ許可）。「必要なもの」に Ruby 4.0.5 の `mise install` を足す（Task 0 で要ったため）。
- [ ] **Step 2: Commit**（`docs: describe the repo filter, the TaskForge column and QR scanning`）
