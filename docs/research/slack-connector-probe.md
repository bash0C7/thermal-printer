> 2026-10-24 の調査報告の写し。本文中の `/private/tmp/...scratchpad/...` のパスは調査時の一時領域で、もう存在しない可能性がある。

# Slack 連携 (mcp__claude_ai_Slack__*) 調査結果: 感熱プリンターのカード用データをどこまで取れるか

調査日: 2026-10-24 / 読み取り系ツールのみ使用 (投稿・リアクション・下書き・canvas 作成は一切呼んでいない)
プライバシー: 発言本文・人名・channel 名は記載しない。取れたフィールドの種類、件数、ツールとパラメータだけを書く。

## 結論 (先に要点)

| 知りたいこと | 判定 | 手段 |
|---|---|---|
| 保存済み / Later の一覧 | 取れる (ただし完全性は未確認) | `slack_search_public_and_private` の `filters: "is:saved"` |
| Later の期限 (リマインダー時刻) / 状態 (進行中・完了・アーカイブ) | 取れない | 返却にそのフィールドが無い。リマインダー専用ツールも無い |
| `/remind` のリマインダー | 取れない | 専用ツールが無い。Slackbot 宛の検索でも 0 件 |
| Slack Lists (タスク表) | 部分的 | `type:list` + `content_types: files` で一覧、`slack_read_file` で CSV 本文。行ごとの ID / permalink は無い |
| todo の代用 (リアクション運用) | 取れる | `hasmy::eyes:` など (`hasmy::<emoji>:`) で自分が付けたリアクション付き発言を一覧 |
| permalink から本文・channel 名・投稿者・日時 | 取れる | 後述の手順 (ts 変換規則を含む) |
| channel ID から channel 名 | 取れる | `slack_read_channel` の返却ヘッダ。`slack_search_channels` に ID を渡しても 0 件 |

## 1. 利用可能な Slack ツール (ToolSearch で確認)

読み取り系: `slack_search_public_and_private`, `slack_search_public`, `slack_read_channel`, `slack_read_thread`, `slack_search_channels`, `slack_search_users`, `slack_read_user_profile`, `slack_get_reactions`, `slack_read_file`, `slack_read_canvas`, `slack_list_channel_members`, `slack_search_emojis`
書き込み系 (未使用): `slack_send_message`, `slack_send_message_draft`, `slack_schedule_message`, `slack_add_reaction`, `slack_create_canvas`, `slack_update_canvas`, `slack_create_conversation`

存在しないもの: 保存済み (Later) 専用ツール、リマインダー専用ツール、Lists 専用ツール、permalink 取得専用ツール (`chat.getPermalink` 相当)、workspace 情報ツール (`team.info` 相当)。

## 2. 保存済み / Later の一覧

### 有効な修飾子
- `is:saved` は有効。`slack_search_public_and_private` の description の修飾子一覧に載っているもの。
  - `keywords: []`, `filters: "is:saved"`, `natural_language_query: ""` で 3 件 (messages 3 / files 0)。ページネーションなし (`End of results`)。
  - `slack_search_public` でも同じ 3 件。3 件とも public channel 上の発言だった。private / DM の保存済みが含まれるかは、手元に該当データが無く未確認。
  - 他の条件と合成できる。`after:2026-10-15` を足すと 1 件、`keywords: ["github"]` を足すと 1 件、一致しない語を足すと 0 件。つまり本当に保存済み集合を絞り込んでいる。
  - 並び順は発言の投稿日時 (新しい順)。「保存した日時」ではない。
  - `files` に対する `is:saved` は 0 件。保存済みファイルは対象外か、該当なし。
- `has:star` は 0 件。`is:starred` は無効。

### 無効な修飾子の挙動に注意 (設計上の罠)
- 未知の修飾子はエラーにならず、黙って無視されて無関係な一般検索結果が返る。
  - `is:starred` と、わざと作った `is:foobar` が、同一の 5 件 (保存とは無関係な発言) を返した。
  - skill では `is:saved` 以外の「それっぽい修飾子」を使わない。結果が不自然に多い / 関係なさそうなときは修飾子が無視されたと疑う。

### 取れないもの
- 保存済み一覧の「期限 (リマインダー日時)」「状態 (In progress / Archived / Completed)」「保存した日時」は返却に含まれない。
- 3 件という数が Slack アプリの「後で」タブと一致するかは、この調査では照合できない。Archived / Completed が含まれるかも不明。skill 初回利用時にユーザーが UI の件数と突き合わせて確認する必要がある。

### 同意まわりの制約
- `slack_search_public_and_private` の description に「使う前にユーザー同意を取ること」とある (`slack_search_public` は同意不要)。保存済みは private / DM の可能性があるので、skill では public_and_private を使う前提で同意取得の手順を入れる。

## 3. todo に相当しそうなもの

| 候補 | 結果 |
|---|---|
| Later (保存済み) | 上記の通り `is:saved` で取れる (期限・状態は取れない) |
| `/remind` (Slackbot のリマインダー) | 取れない。`from:@Slackbot` + keyword `Reminder` (include_bots: true) と `in:@Slackbot` (include_bots: true) はどちらも 0 件。リマインダー用ツールも無い |
| Slack Lists | 部分的。`filters: "type:list"` + `content_types: "files"` で list の一覧 (5 件 + 次ページあり)。1 件ごとに title / file type = list / 作成者 / 作成日時 / File ID / list の permalink (`https://<ws>.slack.com/lists/<TEAM_ID>/<FILE_ID>`) が取れる。自分が作成した list は 2 件確認 |
| Lists の中身 | `slack_read_file(file_id)` が CSV 全体を返す (自分の list 2 件で確認)。列はユーザー定義 (列名は伏せる)。行 ID と行ごとの permalink は取れない。セルの中のリンクや mention は生の mrkdwn (`<#C...>`, `<@U...>`) のまま |
| リアクション運用 (例: :eyes: を todo マーカーにする) | 取れる。`filters: "hasmy::eyes:"` で 20 件以上 (次ページあり)。`slack_get_reactions(channel_id, message_ts)` で、自分の ID が :eyes: の reactor に入っていることを確認済み。発言ごとに permalink が付くので、カード化に向く |
| canvas | `slack_read_canvas(canvas_id)` で本文 (markdown) が読める (今回は呼び出さず description のみ確認) |

## 4. 検索結果 1 件から取れるフィールド

`slack_search_public_and_private` / `slack_search_public` の `response_format: "detailed"`, `include_context: false` の 1 件分に含まれていたもの:

- `Channel`: `#<channel名> (ID: C…)`。DM は `DM (ID: D…)` と `Participants:` の一覧。group DM (concise 表示) は `Group DM with <参加者名…>`。private channel も `#<名前>` で出る。
- `From`: 実名 `<メールアドレス> (ID: U…)`
- `Time`: `YYYY-MM-DD HH:MM:SS JST` (ユーザー timezone Asia/Tokyo で整形済み)
- `Message_ts`: Slack の ts (`<10桁秒>.<6桁マイクロ秒>`)。`date -r` で JST 表示と一致することを確認済み
- `Text`: 本文 (mrkdwn のまま)。detailed は全文、concise は途中で `…` と切れる
- `Permalink`: 発言ごとに入っている。スレッド返信は `…/p<ts>?thread_ts=<親ts>&cid=<channel ID>` の形、非スレッドは `?` 無し
- `Reply count`: スレッドの親のときのみ
- `Context before / after`: 前後の発言 (`include_context: true`, 既定)。不要なら `include_context: false`

### 取れないもの / 別ツールが要るもの
- workspace の表示名 / domain の単独取得手段は無い。
  - domain (`<ws>.slack.com`) は、検索結果の `Permalink` から得る (permalink 内にしか出てこない)。
  - team ID (`T…`) は list の permalink (`/lists/<TEAM_ID>/<FILE_ID>`) から得られる。
  - 組織名は `slack_read_user_profile` の `Organization Name` で取れるが、Slack の workspace 表示名と一致する保証は無い。
  - 結論: 1 workspace 運用なら、domain は skill の設定値 (または初回の permalink から推定) として持つ。
- `slack_read_channel` / `slack_read_thread` の返却には `Permalink` が含まれない。必要なら ID と ts から組み立てる (6 章)。

## 5. スレッドの親と返信

- 検索結果がスレッド返信のとき、permalink の `thread_ts` が親の ts。
- `slack_read_thread(channel_id, message_ts=<親ts>)` で、親 + 返信全件 (`limit` 既定 100、`cursor` でページング)。1 件ごとに `From` (表示名 + メール + ID) / `Time` / `Message TS` / 本文 / `Reactions` / `Files` (ID, mime, サイズ) が付く。
- `oldest` / `latest` を指定すると、親 + その範囲の返信だけに絞れる。目的の返信 1 件 + 親だけ取るのに使える (6 章)。
- 非スレッドの発言に対して `slack_read_thread` を呼ぶと、その発言を親として返し `No thread messsages` (原文のまま綴りが違う) と出る。
- 返信の ts を `message_ts` に渡した場合も、その返信 1 件を親として返し、スレッドの親は返さない。親を取るには permalink の `thread_ts` を使う。
- `slack_read_thread` の返却には channel 名が出ない。

## 6. permalink だけから本文を取る手順 (成立を確認済み)

### 6.1 permalink の分解
`https://<ws>.slack.com/archives/<CHANNEL_ID>/p<16桁>[?thread_ts=<親ts>&cid=<CHANNEL_ID>]`

- ts 変換規則: `p` を除いた 16 桁の数字を、前 10 桁 + `.` + 後 6 桁にする。`p<秒10桁><マイクロ秒6桁>` → `<秒>.<マイクロ秒>`。
  - 例の形式: `p1792565843307099` → `1792565843.307099` (実在する検索結果の permalink と Message_ts の対応で一致を確認済み)。
- `thread_ts` はすでに `.` 入りの ts なので変換不要。
- channel ID の先頭文字: `C` = channel、`D` = DM、`G` = 旧 private / group DM。`C…` と `D…` は `slack_read_channel` / `slack_read_thread` の `channel_id` にそのまま渡せた。`G…` は未検証。

### 6.2 channel 名 + 発言本文 + 投稿者 + 日時を 1 回で取る (非スレッド / 単発)
`slack_read_channel(channel_id, oldest=<ts-1µs>, latest=<ts+1µs>, limit=1〜3, response_format="detailed")`

- 重要: `oldest` / `latest` は両端を含まない (exclusive)。`oldest = latest = ts` は 0 件。ts の前後 1 マイクロ秒 (最後の 6 桁を ±1) を指定すると、その発言だけが返った。
- 返却ヘッダに `Channel: #<名前> (<ID>)` (DM は `Channel: DM (<ID>)`) が付く。これが channel ID → channel 名の唯一の手段。
- 返却の発言ブロックに、投稿者の表示名 + メール + user ID、`YYYY-MM-DD HH:MM:SS JST`、`Message TS`、本文、`Reactions`、`Files` (File ID, mime, サイズ)、リンク付き発言の転送注記が入る。
- マイクロ秒の ±1 は、整数 (秒 × 10^6 + µs) で計算する。浮動小数点で計算すると 6 桁目が狂う。µs が `000000` / `999999` のときは繰り上げ / 繰り下げの処理が要る (この境界は未検証)。

### 6.3 スレッド返信 (permalink に `thread_ts` がある)
`slack_read_thread(channel_id, message_ts=<thread_ts>, oldest=<ts-1µs>, latest=<ts+1µs>, limit=5)` → 親 + 目的の返信 1 件だけが返る (確認済み)。範囲指定を省くとスレッド全体。
channel 名が要るときは 6.2 の `slack_read_channel` を別途 1 回呼ぶ (read_thread にはヘッダが無いため)。

### 6.4 投稿者名の揺れ
- 検索結果の `From` は実名 (メール付き)。`slack_read_channel` / `slack_read_thread` の `From` は表示名 (display name) で、不在・休暇などの注記が名前に入っていることがある。
- カードに載せる名前を安定させたいなら、user ID を `slack_read_user_profile(user_id)` に渡して `Real Name` / `Display Name` / `Title` を取る (自分のプロフィールで返却形式を確認済み: User ID, Username, Display Name, Real Name, Title, Email, Organization Name, Timezone, Status, Locale)。

### 6.5 channel ID 単独から channel 名
- `slack_search_channels(keywords=["<ID>"], natural_language_query="…")` は 0 件。ID 検索は不可。名前 / 説明文のキーワード検索のみ。
- `slack_read_channel(channel_id, limit=1)` の返却ヘッダ (`Channel: #<名前> (<ID>)`) で引ける。メッセージ本文も付いてくるので、メッセージ不要なら `oldest` / `latest` を未来の ts にして 0 件にすれば、ヘッダだけ取れる可能性がある (この組み合わせは未検証)。
- 本文中の `<#C…>` 形式のチャンネル言及も、同じ手順で名前に解決できる。
- 存在しない / アクセス権の無い channel ID は `channel_not_found` エラー。skill は、このエラーを「リンク先を読めない (未参加の private channel、別 workspace)」として扱う必要がある。

### 6.6 ID と ts から permalink を作る (read_* の結果をカード化するとき)
- 非スレッド: `https://<ws>.slack.com/archives/<CHANNEL_ID>/p<ts の . を除いた 16 桁>`
- スレッド返信: 上記 + `?thread_ts=<親ts>&cid=<CHANNEL_ID>`
- この形は、検索結果の `Permalink` と同じ規則 (実在の結果で ts との対応を確認済み)。実際にブラウザで開く検証はしていない。
- `<ws>` は 4 章の通り permalink から得る。

## 7. 本文の整形で出てくる Slack 記法 (カード化時の前処理が要る)
- ユーザー言及: `<@U…|表示名>` (list の CSV 内は `<@U…>` で名前なし → profile 引きが必要)
- channel 言及: `<#C…>` (名前なし → 6.5 で解決)
- リンク: `<URL|ラベル>` (ラベルは長い URL だと `…` で短縮される)
- 絵文字: `:name:` のままテキスト。感熱プリンターでは描画できないので、削除 / 置換が必要
- グループ言及: `<@S…>` (user group)、`<!here>` など特殊言及
- 添付: `Files:` 行に File ID / mime / サイズ。画像は `slack_read_file` で base64 が取れる (10MB 上限) が、今回は呼んでいない

## 8. 試した呼び出し一覧 (件数のみ)

| ツール | 主なパラメータ | 結果 |
|---|---|---|
| search_public_and_private | `is:saved` | 3 件 (messages) |
| search_public | `is:saved` | 3 件 (同じ) |
| search_public_and_private | `is:saved` + `content_types: files` | 0 件 |
| search_public_and_private | `is:saved after:2026-10-15` | 1 件 |
| search_public_and_private | `is:saved` + keyword | 1 件 / 0 件 (一致なし) |
| search_public_and_private | `has:star` | 0 件 |
| search_public_and_private | `is:starred` / `is:foobar` | 同じ無関係な 5 件 (無効修飾子) |
| search_public_and_private | `hasmy::eyes:` | 20 件以上 (ページあり)。自分のリアクションを get_reactions で確認 |
| search_public_and_private | `type:list` + `content_types: files` | 5 件 + 次ページ |
| search_public_and_private | `from:@Slackbot` + `Reminder` / `in:@Slackbot` (include_bots) | 各 0 件 |
| search_public_and_private | `is:dm` (形式確認) | DM は `Channel: DM` + `Participants` + permalink (D ID) |
| read_thread | 親 ts / 返信 ts / 非スレッド ts / ±1µs 範囲 | すべて成立 (5 章) |
| read_channel | ±1µs 範囲 (C 始まり 2 channel / D 始まり DM 1 件) | 成立。`oldest=latest` は 0 件 |
| read_channel | `limit=1` | ヘッダから channel 名 |
| search_channels | keywords に channel ID | 0 件 |
| read_thread | 存在しない channel ID | `channel_not_found` |
| read_user_profile | (自分) | 取得可 (4 章 / 6.4 のフィールド) |
| read_file | list の File ID 2 件 | CSV (列ヘッダ + 行) |
| get_reactions | channel_id + ts | 絵文字 / 件数 / reactor の名前と ID |

## 9. skill 設計への示唆

1. 入力は 3 通りに分ける: (a) Slack permalink、(b) 「Later 全件」、(c) リアクション運用 (例: `hasmy::eyes:`) または list の File ID。
2. (a) は 6 章の手順で `{workspace_domain, channel_id, channel_name, ts, thread_ts?, author_user_id, author_name, posted_at_jst, text, permalink}` を作れる。QR にする URL は、入力の permalink そのまま、または 6.6 で作る。
3. (b) は `is:saved` を 1 回呼び、結果の各件が `Channel` (名前 + ID)、`From`、`Time`、`Message_ts`、`Text`、`Permalink` を全部持つので、追加呼び出し無しでカード化できる (非スレッド・スレッドとも)。
4. 「期限」「進行中 / 完了」は Slack から取れないので、カードの項目に入れるなら skill 側でユーザーに聞く、または省く。
5. 発言要約は取得した全文 (detailed) を入力に、skill 内の LLM 要約で作る。concise は本文が切れるので使わない。
6. 本文中の `<@U…>` `<#C…>` `:emoji:` と URL ラベルは前処理で解決・削除してから印字する。
7. 失敗系: `channel_not_found` (未参加 / 別 workspace)、0 件 (ts の誤変換・メッセージ削除)、`is:saved` が 0 件 (本当に無い / private を検索対象から外した) を区別してメッセージを出す。
8. `slack_search_public_and_private` は使用前の同意が必要。skill の手順に同意確認を入れる。

## 10. 未検証 / 要確認
- `is:saved` の 3 件が、Slack アプリの「後で」タブ (進行中 / アーカイブ済み / 完了) のどこまでを網羅しているか。
- private channel / DM に保存した発言が `is:saved` に出るか (今回の 3 件は public のみ)。
- list の行ごとの識別子 / リンクの有無 (今回の list は発言リンクの列を持たなかった)。
- ts のマイクロ秒が `000000` / `999999` の境界での ±1µs 処理。
- `slack_read_channel` でヘッダだけ取る (0 件になる範囲指定) の挙動。
- 構築した permalink をブラウザで開いたときの実際の遷移。
