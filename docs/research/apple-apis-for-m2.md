# M2（Macアプリ）向けApple API調査

- 調査日: 2026-10-24
- 環境: macOS 27.0.1、Xcode 27.0（`xcodebuild -version`は27.0）、Swift 6.4（`/usr/bin/swift`）、SDKはMacOSX27.0.sdk、arm64
- 対象: 設計書 §5.3.1〜§5.3.7
- 一次資料: Xcode内にdocsetは無い。SDKのヘッダと`.swiftinterface`（`/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/<Framework>.framework/`）を読んだ。developer.apple.comの記述ページはWebFetchではタイトルしか取れないため、取れたもの（Continuity Cameraの記事）だけを根拠にした。
- 試作物はscratchpad（`/private/tmp/claude-501/-Users-bash-dev-src-github-com-bash0C7-thermal-printer/4554651c-7a3a-4e0b-885f-3c43f63191f0/scratchpad/`）の`fm/`、`kin/`、`md/`、`ek/`、`qr/`、`img/`、`btauth/`、`xg/`、`spm/`にある。repoには入れていない。

根拠の区分は次の3つ。

- **実測**: 小さなプログラムをビルドして実行し、出力を見た。
- **文書**: SDKヘッダ、`.swiftinterface`、Appleの記事から読んだだけ。
- **未確認**: 確かめられなかった。

---

## 1. FoundationModels

### 結論

- 使うAPI: `SystemLanguageModel.default`、`LanguageModelSession`、`session.respond(to:)`。
- 可否判定は`model.availability`の`switch`。`.available`以外は設計書 §5.3.6のフォールバック（本文の先頭を切って「…」）へ落とす。
- 日本語は使える。`@Generable`は不要（`respond(to:)`は`Response<String>`を返し、本文は`.content`）。
- コンテキスト上限は`model.contextSize`（このMacでは8192トークン）。入力と出力とinstructionsの合計に対する上限。事前に`try await model.tokenCount(for: prompt)`で数えられる。

```swift
import FoundationModels
import Foundation

func summarize(_ text: String) async -> String? {
    let model = SystemLanguageModel.default
    guard case .available = model.availability, model.supportsLocale(Locale(identifier: "ja_JP")) else { return nil }
    guard let tokens = try? await model.tokenCount(for: text), tokens < model.contextSize - 1024 else { return nil }
    let session = LanguageModelSession(instructions: "あなたは要約者です。日本語で、3行以内に要約します。")
    return try? await session.respond(to: "次を要約してください。\n\(text)").content
}
```

### 根拠

- 実測: 上のコードの原形をCLIとしてビルドして実行した。`availability`は`.available`、`supportsLocale(ja_JP)`はtrue、`contextSize`は8192。日本語3行の要約が返った。
- 実測: 約23400文字（`tokenCount`で12001）を`respond(to:)`に渡すと、`LanguageModelError`（`contextSizeExceeded`）が`Content contains 12065 tokens, which exceeds the maximum allowed context size of 8192.`で投げられた。
- 実測: `supportedLanguages`の`minimalIdentifier`に`ja`がある（24言語）。`Locale.Language(identifier: "ja")`との`contains`はfalseになる（要素が`ja_JP`と地域つきのため）。判定には`supportsLocale`を使う。
- 文書（`FoundationModels.swiftinterface`）: `SystemLanguageModel.Availability`は`.available`と`.unavailable(UnavailableReason)`。`UnavailableReason`は`.deviceNotEligible`、`.appleIntelligenceNotEnabled`、`.modelNotReady`。

### 罠

- Apple Intelligenceを無効にした状態は**実測していない**（このMacは有効）。`.unavailable(.appleIntelligenceNotEnabled)`になる想定は`.swiftinterface`の読みだけ。実機で設定を切って確かめるのは未確認。
- `LanguageModelSession.GenerationError`はmacOS 27でdeprecated。後継は`LanguageModelError`（`contextSizeExceeded`、`rateLimited`、`guardrailViolation`、`refusal`、`unsupportedLanguageOrLocale`、`timeout`など。`.swiftinterface`で確認）。catchでは`LanguageModelError`を使う。
- macOS 27で`PrivateCloudComputeLanguageModel`が加わった（ネットワークとクォータが絡む）。設計書の「ローカルのみ」に合わせて使わない。
- `contextSize`はmacOS 26.4未満では固定4096を返す（`@backDeployed`）。ターゲットは27なので影響しない。
- GitHubのissue本文は長くなりうる。`tokenCount`で数えて、上限を超えるなら本文を先に切ってから渡す（切らないと例外）。

---

## 2. 日本語の禁則処理つき文字組み

### 結論

**CTTypesetter（`CTTypesetterSuggestLineBreak` + `CTTypesetterCreateLine`）で行を作り、その上に禁則ガード（約20行）を自前で載せる**ことを推奨する。CoreTextもTextKitも、単体では §5.3.7の「行頭に`ー`が来ない」を保証しない。

- 描画は`CTLineDraw`を8bitグレーの`CGContext`に対して呼ぶ。行ごとの幅と改行位置を自分で握れるので、インクが印字幅に収まることをテストで保証しやすい。
- 空白の無い長いURL・英単語は、`CTTypesetterSuggestLineBreak`が自動で文字単位に折り返す（追加の処理は要らない）。
- `NSParagraphStyle.lineBreakMode`は`.byWordWrapping`を使う。`.byCharWrapping`は禁則を無効にする。
- `lineBreakStrategy`は禁則と無関係。`.pushOut`は「段落の最終行に1語だけ残る孤立を避ける」ものとSDKヘッダ（`NSParagraphStyle.h`の`NSLineBreakStrategy`）に書かれている。`.hangulWordPriority`はハングル用。

```swift
import AppKit
import CoreText

let headProhibited = Set("、。，．）」』】〕〉》｝！？ー々ぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮ・…‥")
let tailProhibited = Set("（「『【〔〈《｛")

func typesetLines(_ attr: NSAttributedString, width: Double) -> [CTLine] {
    let typesetter = CTTypesetterCreateWithAttributedString(attr)
    let text = attr.string as NSString
    func char(at i: Int) -> Character { Character(text.substring(with: text.rangeOfComposedCharacterSequence(at: i))) }
    var lines: [CTLine] = []
    var start = 0
    while start < text.length {
        let suggested = start + CTTypesetterSuggestLineBreak(typesetter, start, width)
        var end = suggested
        while end < text.length, end > start {
            var last = end - 1
            while last > start, char(at: last) == " " { last -= 1 }
            guard headProhibited.contains(char(at: end)) || tailProhibited.contains(char(at: last)) else { break }
            end = text.rangeOfComposedCharacterSequence(at: end - 1).location
        }
        if end <= start { end = suggested }
        lines.append(CTTypesetterCreateLine(typesetter, CFRange(location: start, length: end - start)))
        start = end
    }
    return lines
}

func render(lines: [CTLine], canvasWidth: Int, margin: CGFloat, lineHeight: CGFloat, padding: CGFloat) -> CGImage {
    let height = Int(ceil(CGFloat(lines.count) * lineHeight + padding * 2))
    let ctx = CGContext(data: nil, width: canvasWidth, height: height, bitsPerComponent: 8, bytesPerRow: canvasWidth,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    ctx.setFillColor(gray: 1, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: height))
    ctx.setFillColor(gray: 0, alpha: 1)
    var baseline = CGFloat(height) - padding - lineHeight * 0.78
    for line in lines {
        ctx.textPosition = CGPoint(x: margin, y: baseline)
        CTLineDraw(line, ctx)
        baseline -= lineHeight
    }
    let p = ctx.data!.bindMemory(to: UInt8.self, capacity: canvasWidth * height)
    for i in 0..<(canvasWidth * height) { p[i] = p[i] < 128 ? 0 : 255 }
    return ctx.makeImage()!
}
```

使い方は`typesetLines(attr, width: 384 - 2 * margin)`の結果を`render`に渡す。属性は`[kCTFontAttributeName as NSAttributedString.Key: ctFont]`（フォントは`CTFontCreateWithName("HiraginoSans-W7" as CFString, 22, nil)`など）。ガードは「次行の先頭が行頭禁則」または「この行の末尾（空白を除く）が行末禁則」のとき、改行位置を1文字ずつ戻す。戻して行が空になるなら元の位置に戻す。

### 根拠（実測）

同じ入力（乱数で作った日本語、句読点、括弧、`ー`、小書き仮名、長いURL、長い数字列、英単語の混在。幅120〜368 dot、Hiragino Sans W6の24pt）を4つの経路に通して行頭・行末を数えた。

| 経路 | `byWordWrapping` | `byCharWrapping` | 備考 |
|---|---|---|---|
| CTTypesetter | 行頭禁則が残る | 禁則なし | `lineBreakStrategy`を変えても結果は同一 |
| CTFramesetter | CTTypesetterと同一 | 禁則なし | |
| TextKit 1（`NSLayoutManager`） | CTTypesetterとほぼ同一 | 禁則なし | 同一 |
| TextKit 2（`NSTextLayoutManager`） | TextKit 1とほぼ同一 | 禁則なし | 同一 |

`byWordWrapping`で残った行頭禁則は、次の3種類に分類できた。

1. **`ー`と小書き仮名（`ゃっ`など）が行頭に来る**。最大の件数。CoreTextの既定は「行頭に置いてよい」側。例: `…コ|ーヒー`（幅368）、`…し|ゃっきり`。
2. **英数字の強制折り返しの直後に`。` `、`が来る**。例: `QRSTUVWXYZ|。次の文`。折り返された英字列の最後の1字を次行へ送る処理が無い。
3. **`」）』。、`のように閉じ括弧・句読点が4つ以上連続する**。ぶら下がりも押し込みもされず、行頭に残る。

行末禁則（`「『（`）は、`byWordWrapping`ではほぼ守られた（TextKitは数件の例外）。

ガード付きの再測定（上の`typesetLines`と同じアルゴリズム。幅200・240・300・368 dotの約2万1千行）:

- 行頭禁則は、幅200 dotで禁則文字が8個連続するという実用外の入力1件だけ残った（幅100 dotの約4文字分では、連続した禁則文字が収まらず多数残る。印字幅は368 dotなので実用外）。
- 行末禁則は0件。
- 各行を8bitグレーの384 dot幅`CGContext`に描き、インクの左右端を測った結果、左右8 dotの余白の外にインクが出た行は0件（斜体なし）。CoreTextはぶら下がり（印字幅を超える句読点）を出さなかった。
- 描いた見本画像（本文W7太字、斜体、長いURL、`ー`、小書き仮名、括弧）を目視で確認した。URLは文字単位で折り返され、禁則の崩れは無かった。

### 罠

- 段落の**先頭文字**が`ー`などのとき、その行は先頭が禁則文字になる（前の行が無いため直せない）。テストの「行頭禁則」は段落の2行目以降だけを見る。
- 行頭禁則文字の集合（`headProhibited`）は自前で決める。小書き仮名と`ー`を含めるかは設計判断（上の集合は含めた）。
- `CTLineGetTypographicBounds`の幅は行末の空白を含む。インクの幅ではない。インクの検査は描画後のビットマップで行う。
- `CTTypesetterSuggestLineBreak`はグリフ1つが幅を超えても最低1クラスタを返す。印字幅368 dotでは起きない。
- 描画後の2値化（しきい値128）はグレーのアンチエイリアスに対してかける（設計書 §5.3.3のとおり）。
- `CTLineDraw`の原点はCG座標（左下原点）。`textPosition`のyは行の基線。上から下へ組むなら基線を行高ぶん減らしていく。

---

## 3. 斜体の合成

### 結論

**`CTFontCreateWithName(name, size, &matrix)`の`matrix`にshear（`c = tan(14°)`、約0.25）を渡してobliqueフォントを作る**。属性文字列の`kCTFontAttributeName`にそのフォントを入れれば、§2の`typesetLines`と`CTLineDraw`がそのまま使える。

```swift
func font(_ postScriptName: String, size: CGFloat, oblique: Bool = false) -> CTFont {
    var shear = CGAffineTransform(a: 1, b: 0, c: oblique ? tan(14 * .pi / 180) : 0, d: 1, tx: 0, ty: 0)
    return CTFontCreateWithName(postScriptName as CFString, size, &shear)
}
```

### 根拠（実測）

縦棒`|`を40ptで描き、インク行の上4分の1と下4分の1の重心のx差（正なら上が右へ傾く）を測った。

| 方法 | `CTLineDraw`で描画 | 結果 |
|---|---|---|
| 何もしない | する | 差0.02（傾かない） |
| `NSFontDescriptor.withSymbolicTraits(.italic)` → `NSFont(descriptor:size:)` | | **`nil`が返る**（Hiragino Sansにitalicが無い） |
| `NSFontManager.convert(_, toHaveTrait: .italicFontMask)` | する | 同じフォント名が返り、傾かない（差0.02） |
| `NSAttributedString.Key.obliqueness`（0.25）+ `CTLineDraw` | する | **傾かない**（差0.02。CoreTextは無視する） |
| `.obliqueness`（0.25）+ `NSAttributedString.draw(at:)` | AppKit描画 | 傾く（差7.73） |
| `CTFontCreateWithName`のmatrix shear（0.25） | する | 傾く（差7.73） |
| `CGContext.textMatrix`にshear | する | 傾く（差7.73） |

### 罠

- `.obliqueness`はAppKitの文字列描画（`NSAttributedString.draw`、TextKit）だけが解釈する。`CTLineDraw`では効かない。§2の経路（CoreText）で使うならfontのmatrixにする。
- フォントmatrixのshearは送り幅（advance）を変えない。折り返し計算はそのまま通る。
- 傾けた字の上端は右へはみ出す。実測（24pt、約14°）で、印字幅の右端から最大5 dot、左端から最大1 dotはみ出した。左右8 dotの余白（設計書 §5.3.7）の内側に収まる。余白を6 dot未満にするなら斜体の右余白を足す。
- `NSFontManager`のitalic変換は例外も出さず、傾かないフォントを返す。「戻り値がitalicかどうか」を信用しない。

---

## 4. swift-markdown

### 結論

**swift-markdown（`swiftlang/swift-markdown`）を使う**。Swift 6.4でビルドでき、GFMのタスクリスト・表・取り消し線をASTで取れる。

- 依存の指定: **セマンティックバージョンのタグが無い**（タグは`swift-6.4.1-RELEASE`と`swift-DEVELOPMENT-SNAPSHOT-…`のみ）。ブランチ`release/6.4.x`を指定する（解決されたrevisionは`bc55d614bc8608d74cdc18d3aa6413bd8661e444`。`Package.resolved`に固定される）。推移依存の`swift-cmark`も同じブランチ名で解決された。
- 走査は`MarkupWalker`（`mutating func defaultVisit`と`descendInto`）か`MarkupVisitor`（`visitText`、`visitStrong`などをoverride）。値を返したいなら`MarkupVisitor`。

```swift
import Markdown

struct Dumper: MarkupWalker {
    var depth = 0
    mutating func defaultVisit(_ markup: any Markup) {
        var extra = ""
        if let item = markup as? ListItem, let box = item.checkbox { extra = " checkbox=\(box)" }
        if let text = markup as? Text { extra = " \"\(text.string)\"" }
        if let heading = markup as? Heading { extra = " level=\(heading.level)" }
        print(String(repeating: "  ", count: depth) + String(describing: type(of: markup)) + extra)
        depth += 1
        descendInto(markup)
        depth -= 1
    }
}

var dumper = Dumper()
dumper.visit(Document(parsing: "- [x] 完了\n- [ ] 未完了\n\n| A | B |\n|---|---|\n| 1 | 2 |\n\n~~消す~~ と *斜体*"))
```

### 根拠（実測）

- `swift build`（`/usr/bin/swift`）で、`branch: "release/6.4.x"`依存のexecutableがビルド・実行できた。xcodegenの`packages:`（`url` + `branch`）経由で`xcodebuild test`でも解決・ビルドでき、Swift Testingのテスト（`ListItem.checkbox == .checked / .unchecked`）が通った。
- 既定の`Document(parsing:)`（オプションなし）で次のノードが出た: `Heading(level:)`、`Strong`、`Emphasis`、`Strikethrough`、`InlineCode`、`Link(destination:)`、`Image(source:)`、`UnorderedList`、`OrderedList`、入れ子の`ListItem`、`ListItem.checkbox`（`.checked` / `.unchecked`）、`BlockQuote`（入れ子可）、`Table`（`Head` / `Body` / `Row` / `Cell`、`columnAlignments`）、`ThematicBreak`、`CodeBlock`（`language`）、`SoftBreak`、`LineBreak`（行末の`\`で確認）。
- 裸のURL（`https://…`だけ）は自動リンクにならず`Text`のまま。
- 比較対象の`AttributedString(markdown:, options: .init(interpretedSyntax: .full))`（実測）:
  - 見出し、リスト、引用、表、取り消し線は`presentationIntent` / `inlinePresentationIntent`で取れる。
  - **タスクリストは取れない**。`- [ ] task`は本文の`[ ] task`という文字列になる。
  - 構造がrunの列で、入れ子のリストと表を組むには`PresentationIntent`のコンポーネントを自分で復元する必要がある。
  - 結論: タスクリスト（`☐` / `☑`）が要件にあるので`AttributedString(markdown:)`は不適。

### 罠

- `Markdown.Table`はSwiftUIの`Table`と名前が衝突する。`Markdown.Table`と修飾する。
- 行末の空白2個による強制改行は、この調査の入力が空白を保てたか確かめられず**未確認**。バックスラッシュによる`LineBreak`は確認済み。
- ブランチ指定の依存は`Package.resolved`をcommitしないと再現しない。
- 空行を含むリスト（loose list）の`Paragraph`の扱い、HTMLブロック、脚注は調べていない（**未確認**）。

---

## 5. EventKit

### 結論

- 権限要求: `try await store.requestFullAccessToReminders()`（macOS 14以上。旧`requestAccess(to:)`はdeprecated）。
- 取得: `store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: 今日の翌日の0時, calendars: nil)`。**開始を`nil`にすると「終了日より前に期限があるすべて」になる**（期限切れを含む）。`fetchReminders(matching:completion:)`は戻り値が`Any`のため自動のasync版が無く、`withCheckedContinuation`で包む。
- Info.plist: `NSRemindersFullAccessUsageDescription`。
- entitlement: サンドボックスを無効にするので不要（想定。下記の根拠のとおり文書の裏取りは取れていない）。

```swift
import EventKit
import Foundation

struct ReminderCard: Sendable {
    let title: String
    let notes: String?
    let listTitle: String
    let due: DateComponents?
    let id: String
}

func fetchDueReminders(store: EKEventStore, now: Date = Date(), calendar: Calendar = .current) async throws -> [ReminderCard] {
    guard try await store.requestFullAccessToReminders() else { return [] }
    let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
    let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: endOfToday, calendars: nil)
    return await withCheckedContinuation { cont in
        store.fetchReminders(matching: predicate) { reminders in
            let cards = (reminders ?? []).map {
                ReminderCard(title: $0.title ?? "", notes: $0.notes, listTitle: $0.calendar.title,
                             due: $0.dueDateComponents, id: $0.calendarItemIdentifier)
            }
            cont.resume(returning: cards)
        }
    }
}
```

### 根拠

- 実測: 上のコードをSwift 6言語モード（`-swift-version 6`）でビルドできた。`EKReminder`（非Sendable）は完了ハンドラの中で値型に写してからcontinuationへ渡している。
- 実測: `EKEventStore.authorizationStatus(for: .reminder)`は呼べる（このMacのターミナル配下では3 = `.fullAccess`、責任プロセスの許可を継承）。**リマインダーの取得自体は実行していない**（個人データを読まないため）。
- 文書（`EKEventStore.h`）: `requestFullAccessToRemindersWithCompletion:`はmacOS 14.0から。`predicateForIncompleteRemindersWithDueDateStarting:ending:calendars:`の説明に「startにnilを渡すとendDateより前に期限のあるものすべて。両方nilなら未完了すべて」とある。
- 文書（Xcodeの`CoreBuildSystem.xcspec`）: ビルド設定`INFOPLIST_KEY_NSRemindersFullAccessUsageDescription`（"Privacy - Reminders Full Access Usage Description"）が存在する。キー名の実在はこれで確認した。
- 未確認: developer.apple.comの該当ページはWebFetchでタイトルしか取れなかった。「サンドボックスでないアプリは`com.apple.security.personal-information.calendars`が要らない」「Hardened Runtimeを有効にしたときの要否」は、文書からも実測からも裏取りできていない。ad-hoc署名でサンドボックスなし・Hardened Runtimeなし（M0と同じ構成）で実際に許可ダイアログが出るかは、実機で確かめる必要がある。

### 罠

- **期限なしのリマインダー**が`ending`だけの述語に含まれるかは未確認（ヘッダ上は「期限が終了日より前」なので含まれない想定）。設計書 §5.3.1は「今日まで（期限切れを含む）」なので、含まれない想定で合う。
- `dueDateComponents`は日付だけ（時刻なし）のことがある。「今日」の境界は`Calendar.current`の`startOfDay`で決める。`ending`が境界の時刻ちょうどを含むかはヘッダに書かれていない（未確認）。翌日0時ちょうどの期限が混ざりうるので、結果側で`dueDateComponents`を再判定すると安全。
- 使用説明キーが無いまま許可を要求するとプロセスが落ちる、と一般に言われている。この調査では落とす実験をしておらず、**未確認**。
- 責任プロセスの許可が子に及ぶ（§9）。アプリ自身が要求する場合は、アプリのInfo.plistのキーが要る。
- ad-hoc署名は、再ビルドで署名が変わるとTCCの許可が失効する（`picoruby-ble-darwin.md`に既出）。リマインダーの許可も同じ。署名のrequirementをbundle idで固定すると、再ビルドをまたいで許可が残る（M0の方針に合わせる）。

---

## 6. CoreImageのQRコード

### 結論

`CIFilter.qrCodeGenerator()`に`message`（UTF-8の`Data`）と`correctionLevel = "M"`を渡す。出力は1モジュール1ピクセルの`CIImage`（静かな領域として周囲に **1モジュール分**の白が付く）。これを`CIContext.createCGImage`で8bitグレー（`.L8`）の`CGImage`にし、整数倍に拡大して描くときは **`CGContext.interpolationQuality = .none`** にする。

```swift
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import Foundation

func qrModules(_ text: String, level: String = "M") -> CGImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(text.utf8)
    filter.correctionLevel = level
    guard let out = filter.outputImage else { return nil }
    let context = CIContext(options: [.workingColorSpace: NSNull()])
    return context.createCGImage(out, from: out.extent, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())
}

func scaledGray(_ modules: CGImage, scale: Int) -> (pixels: [UInt8], side: Int) {
    let side = modules.width * scale
    let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    ctx.interpolationQuality = .none
    ctx.draw(modules, in: CGRect(x: 0, y: 0, width: side, height: side))
    let p = ctx.data!.bindMemory(to: UInt8.self, capacity: side * side)
    return (Array(UnsafeBufferPointer(start: p, count: side * side)), side)
}
```

### 根拠（実測）

- 拡大後の画素値の種類は`{0, 255}`の2値だけ（`.none`）。`.default`（既定）で5倍に拡大すると30階調に滲んだ。
- 出力の幅は、文字`x`で23（版1の21モジュール + 静かな領域1 + 1）。最上行はすべて白。
- URLごとの全体幅（静かな領域を含むモジュール数）:

| URL | 文字数 | 全体のモジュール数 | 128 dot以内の最大倍率 | 3 dotにしたときの一辺 |
|---|---|---|---|---|
| `https://github.com/bash0C7/thermal-printer/issues/12` | 52 | 35 | 3倍（105 dot） | 105 dot |
| Slack permalink（`?thread_ts=…&cid=…`つき） | 104 | 43 | 2倍（86 dot） | 129 dot |
| `https://example.com/a/very/long/path/` + 150字 | 187 | 59 | 2倍（118 dot） | 177 dot |

### 罠

- 設計書 §5.3.5の「一辺128 dot前後、1モジュール3 dot以上」は、GitHubのissue URLでは満たせる。**Slackのpermalink（104文字前後）は3 dotで129 dot**、非常に長いURLは177 dot以上になる。上段の高さを伸ばす前提（設計書にも書いてある）のとおり、倍率を先に決めて一辺を後から決める。
- 静かな領域が1モジュールしかない（QRの規格は4）。カード上の周囲の余白で補う。読み取りは実機のスキャンで確かめる（未確認）。
- 倍率を`Int`で決める。`CIImage.transformed`で拡大すると補間がかかりうる。`CGContext`に描く方法のほうが確実。
- `correctionLevel`の値は`"L"`、`"M"`、`"Q"`、`"H"`の文字列。

---

## 7. 画像の取り込み

### 結論

- 受け口（SwiftUI。コンパイル確認済み）:
  - ⌘V: `.onPasteCommand(of: [UTType], perform: ([NSItemProvider]) -> Void)`
  - ドロップ: `.onDrop(of: [UTType], isTargeted: Binding<Bool>?, perform: ([NSItemProvider]) -> Bool)`
  - 型で受けるなら`.dropDestination(for: T.self)`と`.pasteDestination(for: T.self)`（`T: Transferable`）。
  - 部品の種類の判定には、`NSItemProvider.registeredContentTypes`（`[UTType]`）に`conforms(to:)`を当てるのが素直。
- 振り分けの順序: **`.fileURL` → `.image` → `.url` → テキスト**。ファイルをFinderでコピーすると、ファイルURLとあわせて他の表現（ファイル名の文字列など）が載りうるため、ファイルを先に判定する（Finderの実際の載せ方は未確認）。
- ファイルは`CGImageSourceCreateWithURL`、メモリ上の画像データは`CGImageSourceCreateWithData`で開く。**EXIFの向きを反映するには`CGImageSourceCreateThumbnailAtIndex`を`kCGImageSourceCreateThumbnailWithTransform: true`で呼ぶ**。

```swift
import ImageIO

func loadUpright(_ url: URL, maxPixel: Int = 4096) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
}
```

### 根拠（実測）

- 向き6（右回り90°）で書いた200×100のJPEG、HEIC、PNGを読み戻した。`CGImageSourceCreateImageAtIndex`は3つとも200×100（向きを無視）。`CreateThumbnailAtIndex` + `WithTransform`は3つとも100×200（向きを反映）。
- `CGImageSourceCopyTypeIdentifiers()`に`public.jpeg`、`public.png`、`public.heic`、`public.heics`、`public.jpeg-xl`、`org.webmproject.webp`がある。
- 実測: `onPasteCommand(of: [.image, .fileURL, .url, .plainText])`、`onDrop(of:isTargeted:perform:)`を使ったSwiftUIアプリをSwift 6言語モードでビルドできた。
- 文書（`SwiftUI.swiftinterface`）: `onDrop`、`dropDestination`、`pasteDestination`、`onPasteCommand`、`importsItemProviders`の署名。

### 罠

- `kCGImageSourceThumbnailMaxPixelSize`は**縮小の上限**でもある。元画像より小さい値を渡すと縮小される。M2は後で384 dotに縮めるので、元の長辺以上（4096など）を渡し、縮小は1回にする（設計書 §5.3.4の「幅384 dotにリサイズしてからディザする」と整合）。
- `CreateImageAtIndex`をそのまま使うと、スマホで縦持ちした写真が横倒しで出る。
- 外部アプリからのコピー（Safariの画像、スクリーンショット、Finderのファイル）が、実際にどの型でpasteboardに載るかは**未確認**（受け口の型を広く取って`registeredContentTypes`で判定する前提）。
- `onPasteCommand`は、フォーカスのあるビューでしか呼ばれない。

---

## 8. 「iPhoneから読み込む」（Continuity Camera）

### 結論

- SwiftUIでは、アプリの`.commands { ImportFromDevicesCommands() }`で **Fileメニューに "Import From Device" が出る**（実測の表示名。OSの言語で変わる）。サブメニューに接続済みiPhoneごとに"Take Photo" / "Scan Documents" / "Add Sketch" が並ぶ。
- 受け取りは、フォーカスのあるビューに`.importableFromServices(for: T.self, action: ([T]) -> Bool)`（macOS 13以上、`T: Transferable`。画像なら`Image`）を付ける。
- AppKitの経路（旧）: `NSResponder.validRequestor(forSendType:returnType:)`で画像型のときに自分を返し、`NSServicesMenuRequestor.readSelection(from:)`で`NSPasteboard`から読む。メニュー項目は`NSMenuItem.importFromDeviceIdentifier`。`NSTextView`は自動対応。SwiftUIの`importableFromServices`は同じServicesの仕組みの上に載っていると読めるが、この調査では対応関係を確認していない。
- `importsItemProviders(_:onImport:)`（macOS 12、`NSItemProvider`を受ける）は別API。

### 根拠

- 実測: `ImportFromDevicesCommands()`だけを入れたアプリ（SwiftPMで手組みした`.app`、ad-hoc署名）を起動し、System Events（AppleScript）でFileメニューを調べた。`Import From Device`が存在し、**このMacに接続されているiPhone 2台それぞれの「Take Photo / Scan Documents / Add Sketch」が並んだ**。
- 実測: 受け口が無い状態では、これらの項目はすべて無効（`enabled`がfalse）。
- 文書（Appleの記事 *Supporting Continuity Camera in Your Mac App*）: AppKitの手順（`validRequestor`、`readSelection(from:)`、`NSMenuItem.importFromDeviceIdentifier`）。権限やカメラのInfo.plistキーの記述は無い。
- 文書（`SwiftUI.swiftinterface`）: `ImportFromDevicesCommands`（macOS 12）、`importableFromServices(for:action:)`（macOS 13）、`importsItemProviders`（macOS 12）。

### 罠

- **`importableFromServices(for: Image.self)` + `.focusable()` + 初期フォーカスを付けても、項目は有効にならなかった**（実測。メニューを開いた状態で確認）。AppKitの`validRequestor` / `readSelection`を実装した`NSView`をfirst responderにした経路でも、無効のままだった。**有効化の条件は未確認**。原因の候補（未検証）は、System Events経由の検査がメニューの検証を正しく走らせない、ビューがkey windowのfirst responderになっていない、iPhoneの状態、のいずれか。実際に写真が撮れて受け口に届くところは、iPhoneを操作する人間の確認が要る（物理操作で代行できない）。
- Swift 6言語モードでは、`NSServicesMenuRequestor`への準拠が`conformance … crosses into main actor-isolated code`で失敗する。`@preconcurrency NSServicesMenuRequestor`と書く（実測）。
- **カメラの権限（`NSCameraUsageDescription`）が要るかは未確認**。Appleの記事には要件の記載が無い。画像の撮影はiPhone側のContinuity Cameraが行い、結果はServices経由で届くので、Macアプリ側のカメラ権限は要らない見込みだが、実機で撮影まで通して確かめる。
- iPhoneが無い環境の挙動は**未確認**（このMacには2台ある）。メニューのサブメニューが空になる想定だが、実測していない。
- メニュー名はOSの言語に従う（AppleScriptの取得では英語の "Import From Device" だった）。

---

## 9. プロセス起動と責任プロセス

### 結論

- アプリが`Process`で同梱の実行ファイルを起動すると、TCC（Bluetoothを含む）の判定は**子ではなくアプリが対象**になる（実測）。設計書 §5.2の経路4の見込みとM0の結果（`m0-spike-results.md` §3）に合う。
- 子の実行ファイルは自分のInfo.plistを持たなくてよい。使用説明キー（`NSBluetoothAlwaysUsageDescription`）は**責任プロセス側のアプリのInfo.plist**に要る。
- サンドボックス無効・entitlementなし・ad-hoc署名のアプリでも`Process`は使える（実測）。

### 根拠

- 実測: `CBManager.authorization`と`EKEventStore.authorizationStatus(for: .reminder)`を表示するだけの小さなCLI（`btauth`）を作り、アプリの`Contents/Resources/`に同梱した。アプリは起動すると`Process`で`btauth`を実行して結果をファイルに書く。
  - アプリの実行ファイルをターミナルから直接実行（責任プロセスはこのセッションの親アプリ）: 子の表示はBluetooth = 3（`allowedAlways`）、リマインダー = 3。親アプリの許可が見えている。
  - `open -W -n -a <app>`で起動（責任プロセスはアプリ自身）: 子の表示はBluetooth = 0（`notDetermined`）、リマインダー = 0。アプリ自身の状態（未要求）が見えている。
  - 同じ子の実行ファイルが、起動経路だけで違う許可状態を見た。TCCの主体は子ではなく責任プロセス。
- 実測: アプリはad-hoc署名（`codesign -dvv`で`Signature=adhoc`、`TeamIdentifier=not set`）、`ENABLE_HARDENED_RUNTIME = NO`、entitlementsなしで、`Process.run()`と同梱実行ファイルの実行ができた。
- 公開資料（Apple Developer Forums、スレッド675773）: CLIツールをターミナルから実行すると、ツールが埋め込んだ`__info_plist`に`NSBluetoothAlwaysUsageDescription`があっても、許可はターミナルから継承される。ターミナルにBluetoothを許可すると直る、という回答が採用されている。
- 公開資料（スレッド738748、Appleのエンジニアの発言）: macOS Sonoma以降、IOBluetoothへのアクセスはTCCで制限される。rootのdaemonにはTCCが無い。ユーザーセッションのLaunchAgentは動く。
- 公開資料（第三者のbug報告）: Claude Codeから起動した子プロセスのBluetooth要求が、責任プロセス（Claude Code）のbundleに使用説明キーが無いために拒否された、という報告がある。Appleの一次資料ではない。
- 公開資料では未確認: 「責任プロセス」を決める規則のAppleによる公式な説明。

### 罠

- **未確認（人間の操作が要る）**: アプリの子が`CBCentralManager`を作ったときに、**アプリ名で許可ダイアログが出て、許可後にscan結果が子へ返る**ところまでは確かめていない。ダイアログのクリックが物理操作のため。`m0-spike-results.md` §7の残件と同じ。M0の段階で、ランチャー `.app`が責任プロセスになるところまではTCCログで確認されている。
- ad-hoc署名は再ビルドで変わり、TCCの許可が失効する。同梱の子の実行ファイルを`.app`の署名後に差し替えると、アプリの署名の封印（sealed resources）が壊れる。ビルドの最後に`codesign --force --deep --sign -`をかける。
- `Process`の子に渡す環境変数と引数、標準出力の回収は、アプリ側が受け持つ（`open`経由の起動と違い、`Process`なら`Pipe`で取れる。実測: 子の標準出力を`Pipe`で回収できた）。
- Hardened Runtimeを有効にした場合にBluetoothのentitlementが要るかは**未確認**。この構成（無効）では不要だった。
- `Process`の起動ではアプリが責任プロセスのまま継承されるが、子が`setsid`などで切り離されると変わる可能性がある（**未確認**。今回の構成では切り離さない）。

---

## 10. Xcodeプロジェクトの作り方

### 結論

**xcodegenを推奨する**。理由は、アプリバンドルの組み立て（Info.plistの使用説明キー、リソース同梱、ad-hoc署名）と、`xcodebuild test`（Swift Testing）が宣言的に通るため。純ロジック（文字組み、ディザ、markdown）の高速な反復には、同じ成果物をSwiftPMローカルパッケージとして切り出し、xcodegenから`packages:`で参照する構成にすると、`swift test`も使える（この併用の構成は実測していない）。

最小の`project.yml`（`xcodegen generate` → `xcodebuild test`を実測。`btauth`の行は §9の実験用）:

```yaml
name: Probe
options:
  bundleIdPrefix: com.bash0c7
  deploymentTarget:
    macOS: "27.0"
settings:
  base:
    SWIFT_VERSION: "6.0"
    CODE_SIGN_IDENTITY: "-"
    CODE_SIGN_STYLE: Manual
    ENABLE_HARDENED_RUNTIME: NO
packages:
  swift-markdown:
    url: https://github.com/swiftlang/swift-markdown.git
    branch: release/6.4.x
targets:
  Probe:
    type: application
    platform: macOS
    sources:
      - path: App
        excludes: ["btauth"]
      - path: App/btauth
        buildPhase: resources
    dependencies:
      - package: swift-markdown
        product: Markdown
    info:
      path: App/Info.plist
      properties:
        CFBundleName: Probe
        NSBluetoothAlwaysUsageDescription: probe bluetooth
        NSRemindersFullAccessUsageDescription: probe reminders
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.bash0c7.thermalprinter.probe
        GENERATE_INFOPLIST_FILE: NO
  ProbeTests:
    type: bundle.unit-test
    platform: macOS
    sources: [Tests]
    dependencies:
      - target: Probe
      - package: swift-markdown
        product: Markdown
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.bash0c7.thermalprinter.probe.tests
        GENERATE_INFOPLIST_FILE: YES
schemes:
  Probe:
    build:
      targets:
        Probe: all
    test:
      targets: [ProbeTests]
```

実行は次の2行（`/usr/bin/xcodebuild`を使う）。

```sh
xcodegen generate
xcodebuild test -project Probe.xcodeproj -scheme Probe -destination "platform=macOS" -derivedDataPath build
```

### 根拠（実測。同じ機能の最小例を2通りビルドして比較）

| 観点 | xcodegen + `xcodebuild test` | SwiftPM executable + `swift test` + 手組みの`.app` |
|---|---|---|
| テスト（Swift Testing 3件） | 通る（`** TEST SUCCEEDED **`） | 通る（2件。同じ構成） |
| 冷間（キャッシュなし）の所要 | 同程度（約9秒） | 同程度（約8秒） |
| `.app`の生成 | `xcodebuild`が生成し、ad-hoc署名まで通る | 自作のシェルスクリプトで、`Contents/MacOS`の作成、実行ファイルのコピー、Info.plistの手書き、`codesign --force --sign -`を行う |
| 使用説明キー（Info.plist） | `info.properties`に宣言 | スクリプト内のplistに手書き |
| 子実行ファイル・リソースの同梱 | `buildPhase: resources`で宣言 | スクリプトの`cp` |
| テストがアプリ本体を読む | `@testable import Probe`（アプリがテストホストになり、**テスト中にGUIのアプリが起動する**） | ロジックを別target（`Core`）に分けるので、アプリを起動しない |
| 外部パッケージ（swift-markdown） | `packages:`で宣言、解決・ビルド確認済み | `Package.swift`に宣言、ビルド確認済み |

- 実測: SwiftPMの`@main`は`main.swift`というファイル名では使えない（`App`型は別名のファイルに置く）。
- 実測: `xcodebuild test`の出力には、アプリ起動時のシステムログ（`com.apple.linkd.autoShortcut`への接続失敗の行など）が大量に混ざる。結果の判定は`** TEST SUCCEEDED **`か、Swift Testingの`✔` / `✘`行を`grep`する。

### 罠

- xcodegenの既定のホストアプリ方式は、テストのたびにGUIを起動する。純ロジックはフレームワークかローカルパッケージに分けると、アプリを起動せずに回せる（構成は未実測）。
- `/usr/bin/swift`と`/usr/bin/xcodebuild`を絶対パスで呼ぶ（`~/.swiftly/bin`のswiftがPATHで先に来ると、一部のビルドが失敗する。設計書 §4.1に既出）。
- 生成物（`*.xcodeproj`）は`project.yml`から再生成できるので、commitしない運用でよい。

---

## 設計書 §5.3への指摘

設計書の想定がAPIの実情と食い違う点を、重要度の順に並べる。

1. **§5.3.7「禁則処理: CoreText / TextKitの日本語の改行規則を使う」は、そのままでは保証にならない**（実測）。`ー`と小書き仮名が行頭に来る、英数字の強制折り返しの直後に`。` `、`が来る、閉じ括弧が4つ以上連続すると行頭に残る。TextKit 1 / 2も同じ。「行頭禁則の文字で始まる行が無い」というテスト要件は、CoreText単体では落ちる。§2のガード（改行位置の巻き戻し）を前提に、設計書の文言を「CTTypesetter + 自前の禁則ガード」へ改める。`lineBreakStrategy`は禁則と無関係。
2. **§5.3.3「斜体: 合成したobliqueを使う」は実現できるが、手段が限られる**。`NSFontDescriptor`のitalicは`nil`、`NSObliqueness`は`CTLineDraw`では無効。CTFontのmatrixで作る（§3）。傾けた字は右へ最大5 dotはみ出すので、§5.3.7の内側余白8 dotで足りる。
3. **§5.3.3「パーサーはswift-markdownなどのCommonMark + GFM（タスクリスト、表）対応のものを使う」**は、swift-markdownで満たせる（実測）。`AttributedString(markdown:)`はタスクリストを取れないので候補から外れる。swift-markdownにはセマンティックバージョンのタグが無く、ブランチ指定（`release/6.4.x`）になる点を、依存の記述に足す。
4. **§5.3.5のQR「一辺128 dot前後、1モジュール3 dot以上」**は、GitHubのissue URLでは満たす。Slackのpermalinkは3 dotで約129 dot、長いURLは約177 dotになる。静かな領域は1モジュールしか付かない。倍率を先に決め、一辺は結果として決めると書くとよい。
5. **§5.3.6のフォールバック判定**: `SystemLanguageModel.default.availability`と`supportsLocale(_:)`の2つで判定する。コンテキストは8192トークンで、GitHubの本文が長いと例外になるので、`tokenCount`で数えて先に切る。エラー型は`LanguageModelError`（`GenerationError`はdeprecated）。
6. **§5.3.2「iPhoneから読み込む」**: 正しいAPI名は`ImportFromDevicesCommands`（メニュー）と`importableFromServices(for:action:)`（受け口）。メニュー自体は実測で出た。受け口を付けても項目が有効にならなかったため、動作確認は手元のiPhoneで行う（設計書の【builderに任せる】に当たる）。カメラ権限は、Appleの記事に要件が無く、要らない見込みだが未確認。
7. **§5.2経路4（アプリが子としてpicorubyを起動）**: 責任プロセスがアプリになることは、この調査でも実測で裏づいた（`m0-spike-results.md`と一致）。残る未確認は「子がCoreBluetoothを使ったときにアプリ名で許可ダイアログが出て、許可後にscanが通る」こと。
8. **§4.1「Xcode 27.1」**: このMacの`xcodebuild -version`は27.0（build 27A266a）。他の記述にXcode 27.1を前提にした部分があれば確認する。
9. **§5.3.1のリマインダー**: 述語は開始`nil`で「今日まで（期限切れを含む）」を表せる。期限なしのリマインダーが含まれるかは未確認。
10. **§5.3.1の権限**: リマインダーのキーは`NSRemindersFullAccessUsageDescription`。実在はビルド設定名で確認した。サンドボックスなしの構成でentitlementが要らないことは、文書からの裏取りが取れていない。

---

## 未確認の一覧

- Apple Intelligenceを無効にしたときの`availability`（§1）
- リマインダーの実際の取得結果と、期限なしの扱い、許可ダイアログ（§5）
- QRの実機スキャン（§6）
- 外部アプリからのコピーでpasteboardに載る型（§7）
- Continuity Cameraの項目が有効になる条件、カメラ権限、iPhoneなしの環境（§8）
- アプリの子がCoreBluetoothを使ったときの許可ダイアログとscan結果、Hardened Runtimeの要否、子が切り離された場合（§9）
- 行末2空白による強制改行、loose list、HTMLブロック、脚注（§4）
- xcodegen + ローカルSwiftPMパッケージの併用構成（§10）
