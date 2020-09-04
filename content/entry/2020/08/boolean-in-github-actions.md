---
title: GitHub Actions で真偽値を正しく扱う
date: 2020-09-03
slug: boolean-in-github-actions
tags: [ GitHub, "GitHub Actions" ]
---

# TL;DR

- GitHub Actions の `if` などで用いる比較は型厳密
- 公式のベストプラクティス等がないのでアクションごとに出力が異なる
- アクションを使うときはドキュメントを読む, アクションを作るときはドキュメントを書こう

# 概要

値を真偽値 `true` と比較する以下の `if` のうち, 条件が真と判定されるのは1つだけ:

```yaml
if: 'true' == true # false
if: 'false' == true # false
if: '1' == true # TRUE!
if: '0' == true # false
```

似たように, 値を文字列 `'true'` と比較する以下の `if` でも, 条件が真となるのは1つだけ:

```yaml
if: 'true' == 'true' # TRUE!
if: 'false' == 'true # false
if: '1' == 'true' # false
if: '0' == 'true' # false
```

つまり, GitHub Actions は表現に対して型厳密な比較を行う.

## 当たり前だが...

型厳密な比較は当たり前だが, 加えて, GitHub Actions にはいくつかハマりどころが用意されている.

### `outputs` の値は文字列型のみ

[Context and expression syntax for GitHub Actions](https://docs.github.com/en/actions/reference/context-and-expression-syntax-for-github-actions#steps-context)

公式ドキュメントにあるように, アクションの `outputs` の型は `string` であり, `true` や `false` を出力しても `boolean` 型にならず, ただの文字列である.

### 抽象的等価比較

[Context and expression syntax for GitHub Actions](https://docs.github.com/en/actions/reference/context-and-expression-syntax-for-github-actions#operators)

等価比較 (`==`, `!=`) において, 左辺と右辺の型が異なる場合, 比較の前に暗黙的な型変換が行われる.

Actions では, 全ての型を数値に変換する. 変換ルールは上記ページの通りだが, もっとも注意すべきなのは **stringは数値へパースされる** 点である. つまり, `'1'` などの文字列は, 数値の `1` へ暗黙的に変換される.

上記の例で,

```yaml
if: '1' == true # TRUE!
```

が真と評価されたのもこれが理由である. 左辺の `'1'` は文字列からパースされた数値 `1` となり, 右辺の `true` はキャストルールに基づいて `1` となる.

### 複数のキャストルールの存在

前述の等価比較の際のキャストルールの他に, ビルトイン関数内でのキャストルールが別に存在しており, 非常に**紛らわしい.**

ビルトイン関数内でのキャストルールは, すべてを文字列に変換しようとする. 例えば, `contains('true', true)` は第2引数が `'true'` に変換される.

当然, このキャストルールは `if` などでの評価には適用されない. 雑にドキュメントを読んでいたり, どこかで混ざってしまうとハマる.

### ベストプラクティスが提示されない

GitHub Actions のドキュメントにベストプラクティスが提示されていないので, 出力の形式はアクションごとにやりたい放題である. 雰囲気で真偽値の `outputs` を扱うとハマる.

# まとめ

アクションを使う際, そのアクションが真偽値で出力を行うのなら, `true, false` で出力するか, または `1, 0` で出力するかをドキュメントなどでしっかり確認する.

前者なら:

```yaml
if: steps.work.outputs.string-output == 'true'
```

の様に文字列で比較してあげる必要があるし, 後者なら:

```yaml
if: steps.work.outputs.int-output == true
```

の様に, 文字列ではなく `boolean` のリテラルを使ってあげないと思ったように動いてくれない.

# 余談

`if` 内で比較せず, そのままステップの出力をフラグとして扱うことはできない. **すべての文字列が`true` と評価される**.

例えば, `steps.out-true.outputs.out` が `true` のとき, `if: steps.out-true.outputs.out` に対して Actions ランナーは以下のように評価を行う:

```
##[debug]Evaluating condition for step: 'validate true'
##[debug]Evaluating: (success() && steps.out-true.outputs.out)
##[debug]Evaluating And:
##[debug]..Evaluating success:
##[debug]..=> true
##[debug]..Evaluating Index:
##[debug]....Evaluating Index:
##[debug]......Evaluating Index:
##[debug]........Evaluating steps:
##[debug]........=> Object
##[debug]........Evaluating String:
##[debug]........=> 'out-true'
##[debug]......=> Object
##[debug]......Evaluating String:
##[debug]......=> 'outputs'
##[debug]....=> Object
##[debug]....Evaluating String:
##[debug]....=> 'out'
##[debug]..=> 'true'
##[debug]=> 'true'
##[debug]Expanded: (true && 'true')
##[debug]Result: 'true'
```

もうひとつ, `steps.out-one.outputs.out` が `'1'` のとき, `if: steps.out-one.outputs.out` に対しての Actions ランナーの評価は:

```
##[debug]Evaluating condition for step: 'validate one'
##[debug]Evaluating: (success() && steps.out-one.outputs.out)
##[debug]Evaluating And:
##[debug]..Evaluating success:
##[debug]..=> true
##[debug]..Evaluating Index:
##[debug]....Evaluating Index:
##[debug]......Evaluating Index:
##[debug]........Evaluating steps:
##[debug]........=> Object
##[debug]........Evaluating String:
##[debug]........=> 'out-one'
##[debug]......=> Object
##[debug]......Evaluating String:
##[debug]......=> 'outputs'
##[debug]....=> Object
##[debug]....Evaluating String:
##[debug]....=> 'out'
##[debug]..=> '1'
##[debug]=> '1'
##[debug]Expanded: (true && '1')
##[debug]Result: '1'
```

つまり, 等価比較が含まれない場合, Actions は一切の型変換をせず, 値を素通りさせてしまう.

`if` 内ではちゃんと比較かけましょう.