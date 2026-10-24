import Testing
import Foundation
@testable import ThermalPrinterCore

private enum Fixtures {
    static let issueBody = """
    ## 概要

    Phomemo T02に印字するとき、Macアプリのプレビューでは収まっている長い行が、実機の紙では右端で切れることがあります。特にURLや英数字が続く行で起きます。先週の定例で試した3枚のうち2枚で再現しました。

    ## 再現手順

    1. アプリを起動して、GitHubのissue URLを貼り付けて部品を追加する。
    2. 部品の帯が384 dotの幅に収まっていることをプレビューで確認する。
    3. 「印刷」を押して、Phomemo T02から紙を出す。
    4. 紙の右端を見る。URLの末尾の数文字が欠けている。

    ## 期待する動作

    プレビューと同じ位置で折り返され、紙の右端まで文字が出る。左右の余白はそれぞれ8 dotで、印字幅は368 dotのはず。

    ## 実際の動作

    右端の約2 mmが欠ける。左端は問題ない。ラスタ自体は384 dot幅のPBMで作っていて、`thermal-pbm`で書き出したファイルをビューアーで開くと、右端まできちんとインクがある。つまり、Mac側の組版ではなく、送信かプリンター側で欠けている可能性が高い。

    ## 調べたこと

    - 1回の転送を182 byteずつに分けているので、チャンクの境界で欠けているのではないかと疑ったが、欠けるのは行の右端だけで、チャンクの境界とは位置が合わない。
    - 紙の幅は48 mm、印字幅は384 dotの想定だが、Phomemo公式アプリで同じ画像を出すと右端まで出る。
    - 設定の濃度を下げても、欠ける幅は変わらない。
    - 紙を新しいロールに替えても同じ。

    ## 環境

    - macOS 27.0.1、Apple Silicon
    - Phomemo T02、ファームウェア3.0.7
    - アプリは`main`の最新（コミット f13c325）
    - 接続はBLE。電池残量は83%

    ## 考えられる原因

    1. プリンターの実効の印字幅が384 dotより少し狭い。公式アプリは右端を切り詰めて出している可能性がある。
    2. `1d 76 30`のヘッダーの幅の指定（48 byte）が、機種によって扱いが違う。
    3. ヘッドの端の数dotが物理的に熱くならない個体差。

    ## 紙に出た結果の記録

    3枚の部品の帯を同じ設定で出し、定規で右端の欠けを測った。

    - 1枚目（URLが2行）: 右端が約2.0 mm欠ける。URLの末尾が「/issues/1」から「/issues/」になる。
    - 2枚目（日本語の本文のみ）: 欠けは約1.5 mmで、文字が半分見えなくなる行が1つだけあった。
    - 3枚目（QRコード付き）: QRは右上に置いているが、右の静かな領域の一部が欠け、スマートフォンでは読めなかった。

    QRが読めなくなるのは実用上かなり困る。左右の余白を8 dotに決めたのは設計書の初期値で、実機で調整する前提だった。今回の結果は、その調整が必要だという根拠になる。

    ## 影響範囲

    - 部品の帯の長さの計算は変わらない。変わるのは横方向の有効な幅だけ。
    - 写真の部品は384 dot幅いっぱいに出すので、同じ理由で右端が欠ける。ディザの結果には影響しない。
    - 区切り線は左右の余白の外まで引いているため、右端が短く見える。

    ## 提案

    まず、右端に1 dotずつ幅を変えた縞模様のテストパターンを出して、実際に黒く出る最大の幅を測りたい。その結果に応じて、組版の印字幅（今は368 dot）と左右の余白の既定値を見直す。個体差の可能性があるので、設定で余白を変えられるようにするかどうかも合わせて決めたい。

    ## 検証の計画

    縞模様は、幅384 dotのPBMに、左端から数えて1 dot、2 dot、3 dotと太くなる縦線を並べて作る。これを`thermal-pbm`で生成し、CLIで1回だけ出す。紙の右端から何本目の線まで黒く出るかを数えれば、実効の印字幅が求まる。生成するPBMは50行ほどで、紙は3 cmも使わない。測定は2本のロールと、可能なら別のT02でも行う。結果は`docs/research/`に表で残し、既定値の根拠にする。

    ## 補足

    プレビューの寸法は`Bitmap1`をそのまま表示しているので、プレビューと紙の差は必ず送信以降の段階で生じる。この前提でよいか、設計の担当に確認したい。
    """

    static let comment = """
    手元のT02（ファームウェア3.0.7）でも同じ症状を確認しました。縞模様のパターンで測ったところ、右端から約6 dotは黒くなりませんでした。公式アプリの出力は378 dot幅でした。なので原因1の可能性が高いと思います。印字幅を372 dot、左右の余白を8 dotにして、右端の6 dotは常に白にする設定を既定値にするのが現実的ではないでしょうか。個体差があるなら、設定画面で調整できるようにするのがよさそうです。念のため、別のロールでも測ってみます。
    """
}

private func report(_ label: String, _ summary: Summary) {
    print("[summary \(label)] usedModel=\(summary.usedModel) reason=\(summary.fallbackReason ?? "-") chars=\(summary.text.count) lines=\(summary.text.split(separator: "\n").count)")
    print("[summary \(label)] text=\(summary.text)")
}

@Test func theIssueFixtureIsAboutTwoThousandCharacters() {
    #expect((1800...2400).contains(Fixtures.issueBody.count))
}

@Test func availabilityIsReportedInTheTestOutput() {
    let reason = FoundationModelSummarizer.unavailableReason
    print("[availability] reason=\(reason ?? "available")")
    #expect(FoundationModelSummarizer.isAvailable == (reason == nil))
}

@Test func overviewOfAJapaneseIssueFitsThreeLinesOrFallsBackToTruncation() async {
    let summary = await FoundationModelSummarizer().summarize(Fixtures.issueBody, kind: .overview)
    report("overview", summary)
    #expect(summary.text.split(separator: "\n").count <= 3)
    #expect(summary.text.count <= SummaryKind.overview.hardCharacterLimit + 1)
    if FoundationModelSummarizer.isAvailable {
        #expect(summary.usedModel)
        #expect(summary.fallbackReason == nil)
        #expect(summary.text != String(Fixtures.issueBody.prefix(60)))
    } else {
        #expect(summary.usedModel == false)
        #expect(summary.fallbackReason != nil)
        let flat = Fixtures.issueBody.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(summary.text == String(flat.prefix(60)) + "…")
    }
}

@Test func latestCommentFitsTwoLinesOrFallsBackToTruncation() async {
    let summary = await FoundationModelSummarizer().summarize(Fixtures.comment, kind: .comment)
    report("comment", summary)
    #expect(summary.text.split(separator: "\n").count <= 2)
    #expect(summary.text.count <= SummaryKind.comment.hardCharacterLimit + 1)
    if FoundationModelSummarizer.isAvailable {
        #expect(summary.usedModel)
    } else {
        #expect(summary.usedModel == false)
        #expect(summary.text.hasSuffix("…"))
    }
}

@Test func bodyLongerThanTheContextWindowIsStillSummarizedOrFallsBack() async {
    let huge = String(repeating: Fixtures.issueBody + "\n", count: 12)
    let summary = await FoundationModelSummarizer().summarize(huge, kind: .overview)
    report("huge", summary)
    #expect(!summary.text.isEmpty)
    #expect(summary.text.split(separator: "\n").count <= 3)
    if FoundationModelSummarizer.isAvailable {
        #expect(summary.usedModel)
    }
}
