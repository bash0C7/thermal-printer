# 10/24 打ち合わせメモ

## 決まったこと

- **リリースは 11/15**
- 検証環境は *来週月曜* から
- 費用は前回見積もりのまま
- 担当は次のとおり
  - 設計: 田中さん、**鈴木さん**
    - レビューは *週明け* まで
  - 実装: `bash0C7`
- 詳細は[設計書](https://github.com/bash0C7/thermal-printer/blob/main/docs/superpowers/specs/2026-10-24-thermal-printer-design.md)を参照。

### 手順

1. 見積もりを再提出する
2. デザインを確認する
   1. 配色
   2. 文字組み
3. 承認をもらう、そして「印刷」する。

#### 補足

禁則のテスト：「これは、テスト。」（括弧）ー長音！？『二重』…という、句読点だらけの段落です。日本語の長い文章は、行の途中で折り返されても、、、行頭に句読点が来てはいけません。

長いURLは文字単位で折り返します: https://example.com/archives/C0123456789/p1792565843307099?thread_ts=1792565800.000100&cid=C0123456789&very_long_query_parameter=abcdefghijklmnopqrstuvwxyz0123456789

## 宿題

- [ ] 見積もり再提出（先方）
- [x] デザイン確認（自分）
- [ ] https://example.com/very/long/path/to/the/document/that/never/ends

> 次回 10/31 14:00
> 場所は *第二会議室*。
>
> > 入れ子の引用も、左の縦線が二本になります。

---

## コードと表

```ruby
def very_long_method_name(argument_number_one, argument_number_two)
  puts "a string literal that is long enough to wrap around"
end
```

| 項目 | 担当 | 期限 |
|---|---|---|
| 見積もり | 先方 | 10/31 |
| **デザイン** | 自分 | 11/05 |

~~取り消し~~ と **太字の中の *斜体* と `コード`** の混在。
