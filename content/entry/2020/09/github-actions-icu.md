---
title: GitHub ActionsでICU依存の関数を使うな
date: 2020-09-23
slug: github-actions-icu
tags: [GitHub, "GitHub Actions", "Node.js"]
---

### 2020/09/27 追記

この記事で紹介したワークアラウンドを自動化するアクションを作りました:

[GitHub Actions ランタイムを多言語化するアクションを作った](https://note.sarisia.cc/entry/github-actions-setup-icu)

# TL;DR

GitHub Actions の JavaScript アクションは `small-icu` オプションでビルドされた Node.js 12 で走るので `ICU` 依存の関数がまともな結果を返さない. ワークアラウンドはあるが, ユーザーの操作が必要.

# 概要

[actions-readme-feed](https://github.com/sarisia/actions-readme-feed) に日付のフォーマットに用いるロケールを変える機能を実装したが, GitHub Actions 上ではどのロケールにしても常に英語が出力されてしまったので原因を調べた.

## 再現してみる

以下のコードでテストしてみる:

```jsx
console.log(process.versions.node)
console.log((new Date()).toLocaleString('en-US', { month: 'long', weekday: 'long' }))
console.log((new Date()).toLocaleString('ja-JP', { month: 'long', weekday: 'long' }))
```

ローカルでの結果:

```
14.10.1
September Wednesday
9月 水曜日
```

GitHub Actions での結果:

```
12.13.1
Wednesday (month: September)
Wednesday (month: September)
```

ローカルでは `toLocaleString()` に `ja-JP` ロケールを渡すと日本語での表現が返ってくるが, GitHub Actions ではロケールは完全に無視され, 英語の表現が返ってくる.

# 原因

GitHub Actions の JavaScript アクションの実行に用いられる Node.js のバイナリに同梱されている ICU データが部分的 (英語ロケールしか含まない) なので, 英語以外の言語のロケールに対応できない.

## ICU とは

[ICU - International Components for Unicode](http://site.icu-project.org/home)

ソフトウェアの国際化 (≒ 多言語化) に用いるライブラリとそのデータセットを提供. 照合順序とか日付・通貨のフォーマットとかいろいろ機能がある.

glibc のロケールとは別物.

## ICU と Node.js

[Node.js v14.11.0 Documentation](https://nodejs.org/docs/latest/api/intl.html)

Node.js では, `String.prototype.toLowerCase()` や `Date.prototype.toLocaleString()` 等の関数の実装に ICU が用いられており, ビルドオプションによって利用できる機能や関数が制限される.

大雑把なオプション一覧と概要は以下の通り:

- `--with-intl=none` / `--without-intl`

    ICU を利用しない. 国際化にまつわる機能は利用できない.

- `--with-intl=system-icu`

    システムにインストールされた ICU バイナリとデータセットを利用.

- `--with-intl=small-icu`

    ICU バイナリを Node.js のバイナリに含める. 一部の ICU データセット (通常は英語ロケールのみ) を同梱.

- `--with-intl=full-icu`

    ICU バイナリとフルの ICU データセットを同梱. バイナリが大きくなる.

## Node.js 12 までのビルドオプション

Node.js 12 までは, デフォルトのビルド設定として `--with-intl=small-icu` が用いられていたが, Node.js 13 より, デフォルトが `--with-intl=full-icu` に変更された[^1]ため, フルのデータセットを持っている. そのため, 今回の問題は通常 Node.js 13 以降では発生しない.

GitHub Actions は JavaScript アクションの実行ランタイムとして Node.js 12 しか用いることができないため, 今回の問題が発生する.

# ワークアラウンド

最も簡単なのは, [公式ドキュメントのテーブル](https://nodejs.org/docs/latest-v12.x/api/intl.html#intl_options_for_building_node_js) を確認し, `small-icu` で動かない関数を避けることだが, 頑張れば一応 `full-icu` と同じ動作をさせることができる.

## 外部の ICU データセットを利用

[Node.js v14.11.0 Documentation](https://nodejs.org/docs/latest-v12.x/api/intl.html#intl_providing_icu_data_at_runtime)

`small-icu` ビルドでは, 実行時にランタイムが用いる ICU データセットを指定することができるため, データセットを用意し, 環境変数 `NODE_ICU_DATA` を向ければデータセットを読み込んでくれる.

データセットを用意する最も簡単な方法は, `icu4c-data` パッケージをインストールすることである. GitHub Actions の用いる Node.js バージョンは 12.13.x (ランナーのOSによって異なる) であり, 今の所 ICU 64 Low endian のデータセットを読み込むことができる.

以下のようなワークフローを用意する:

```jsx
steps:
  - run: npm install icu4c-data@64l
  - uses: sarisia/action-you-want@v1
    env:
      NODE_ICU_DATA: node_modules/icu4c-data
```

ただし, この方法はアクションのユーザがワークフローに変更を加える必要がある上に, ワーキングディレクトリを汚染するため, 何らかの工夫が必要である.

# まとめ

10月に Node.js 14 が LTS入りするはずなので, GitHub Actions が `node14` アクションに対応してくれるように祈りましょう.

[^1]: [https://github.com/nodejs/node/blob/master/doc/changelogs/CHANGELOG_V13.md#2019-10-22-version-1300-current-bethgriggs](https://github.com/nodejs/node/blob/master/doc/changelogs/CHANGELOG_V13.md#2019-10-22-version-1300-current-bethgriggs)