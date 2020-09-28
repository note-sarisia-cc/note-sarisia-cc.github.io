---
title: GitHub Actions ランタイムを多言語化するアクションを作った
date: 2020-09-27
slug: github-actions-setup-icu
tags: [GitHub, "GitHub Actions", Nodejs]
---

# TL;DR

GitHub Actions が使う Node.js 12 にフルの ICU データセットを自動でインストールするアクションを作った。 `Data.prototype.toLocaleString()` などのロケールを考慮する関数が英語以外の言語のロケールでも正常な結果を返すようになる。

[sarisia/setup-icu](https://github.com/sarisia/setup-icu)

# 概要

先日、[”GitHub ActionsでICU依存の関数を使うな”](https://note.sarisia.cc/entry/github-actions-icu/) という記事を投稿した。その際に、現在の GitHub Actions の JavaScript アクションはロケールを考慮する一部の関数がデフォルトで英語以外の言語に対応していないこと、そしてワークアラウンドを紹介した。

その後、このワークアラウンドをより簡単に適用するアクションを作成したので、今回はその紹介をする。

# sarisia/setup-icu

## 導入

既存のワークフローに一行追加するだけ:

```yaml
steps:
  - uses: sarisia/setup-icu@v1
  - uses: sarisia/action-uses-icu-function@v2
```

`setup-icu` アクションの実行以降のアクションはすべてフルの ICU データセットを読み込んだ状態で実行される。

## 前回のワークアラウンドと比較して

前回のワークアラウンドも、ユーザに対してワークフローファイルへの数行の追加を要求したが、それは今回も変わっていない。

前回のワークフロー:

```yaml
steps:
  - run: npm install icu4c-data@64l
  - uses: sarisia/action-you-want@v1
    env:
      NODE_ICU_DATA: node_modules/icu4c-data
```

対して、今回のワークフロー:

```yaml
steps:
  - uses: sarisia/setup-icu@v1
  - uses: sarisia/action-uses-icu-function@v2
```

以前のワークフローでは、ロケール依存関数を用いるアクション全てに対して環境変数を設定する必要があったのに対し、今回作成したアクションはロケール依存関数を用いたアクションを実行するステップの前に一度だけ実行すればよく、以降実行されるアクション全てにワークアラウンドを適用する。

加えて、前回のワークフローではワーキングディレクトリにデータセットをインストールしていたが、今回作成したアクションはランナーの一時ストレージにデータセットをインストールするため, ワーキングディレクトリの汚染を回避できる。

## 副作用

`setup-icu` アクションはデフォルトで簡単にワークアラウンドを提供してくれる一方で、環境変数を汚染するために、アクションの実行に使われる `Node.js` ランタイムとは別に、 `node` コマンドで実行されるランタイムの挙動も変更する。

ICU データセットは ICU ライブラリのバージョンに合わせたデータセットを用いなければならない。この場合、 `Node.js` ランタイムに合わせた ICU データセットを読み込めなければランタイムは起動に失敗する。

`node` コマンドで実行される `Node.js` は、デフォルトでは `Node.js 12` なので問題ないが、問題となるのは `actions/setup-node` アクションなどでランタイムのバージョンを変更している場合である。例として、 `Node.js 10` や `Node.js 11` では、ICU バージョン不整合によりランタイムが起動できないことを確認している。

この問題の回避策として、環境変数を設定しないオプションを用意している:

```yaml
steps:
  - uses: actions/setup-node@v1
    with:
      node-version: 10
  - uses: sarisia/setup-icu@v1
    id: setup-icu
    with:
      noexport: true
  - uses: sarisia/action-uses-icu-function@v2
    env:
      NODE_ICU_DATA: ${{ steps.setup-icu.outputs.icu-data-dir }}
```

この場合も前回のワークアラウンド同様、アクションごとに環境変数を設定する必要がある。ただし、ICU データセットのインストールされた場所がアウトプットとして提供されるので、これを利用できる。

## 今後について

基本的に必要な機能は提供しているし, これ以上なにかするオプションの追加なども現時点では思いついていない. 多分 `Node.js 14` がランタイムとして利用できるようになればこのアクションも用無しになるので, 長期的なメンテナンスについてもあまり深く考えていない.

# まとめ

早く来て `node14`