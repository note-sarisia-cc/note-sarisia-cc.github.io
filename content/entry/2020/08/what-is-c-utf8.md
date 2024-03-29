---
title: C.UTF-8 とは何だったのか
date: 2020-08-21
slug: what-is-c-utf8
tags: [Linux, UTF-8]
draft: true
---

# TL;DR

 全ての Linux ディストリビューションが `C.UTF-8` 持っているわけではないのでつらい.

仮に持っていたとしても標準化されていないので如何なる動作も期待すべきではない...かも.

# 概要

最近, Arch Linux に Linuxbrew (Homebrew) を入れたら `brew` する度に " `C.UTF-8` 無いのですが…) と怒られるようになってしまった. 原因は以下の変更だった:

[Change the default locale to C.UTF-8 on Linux by sjackman · Pull Request #8047 · Homebrew/brew](https://github.com/Homebrew/brew/pull/8047)

この PR を見ていくと, 同じように Arch Linux での警告に悩む人や, CentOS でも発生している人を見ることができる. 

そもそも `C.UTF-8` って何だ？と思い調べていると思ったより悩ましい問題が広がっていたので, 今回はそれについて書いておきたい.

# そもそも `C` ロケールって？

`C` ロケールは ISO C (ANSI C) で, `POSIX` ロケールは POSIX で定められている. `POSIX` ロケールは実装上, `C` ロケールのエイリアスである.

これらのロケールは POSIX 準拠のシステムなら必ず利用できるので, アプリケーションやライブラリに, ロケールに依存しない動作をして欲しい時に使う.

実装は `glibc` で提供されているので, GNU/Linux なディストリビューションなら使えると思う.

# `C.UTF-8` ?

glibc wiki に, `C.UTF-8` が望まれる理由が簡潔にまとめられている:

[Proposals/C.UTF-8 - glibc wiki](https://sourceware.org/glibc/wiki/Proposals/C.UTF-8)

読むと,

- `ASCII` は時代遅れ
- `UTF-8` を使いたくても国/言語を指定せず文字コードに `UTF-8` を指定する方法が存在しない
    - (ロケールは国/言語と文字コードのペアなので)
    - 多くのプロジェクトで `UTF-8` なロケールを選択するために `en_US.UTF-8` などいくつかのロケールを見るようハードコードしている
    - ディストリビューションがデフォルトの文字コードを `UTF-8` にできないのはペアになっている国/言語の設定が望ましくないため
- 例えば Python も標準入出力などで外の世界と文字コードを合わせる必要がある時に苦労している

といった理由で, `C` ロケールのような, 国/言語に依存しない `UTF-8` 文字コードのロケールが欲しい, ということらしい.

## じゃあ実装されたの？

**されていない.**

`libc-alpha` での[議論](https://sourceware.org/legacy-ml/libc-alpha/2015-02/msg00247.html)を追うと,

- オプションではなく全ての環境で利用できるスタンダードなロケールとして提供したい
- `ASCII` 範囲の文字だけではなく全ての Unicode 文字をカバーするべき

といった大まかな方向性は示されているものの,

- `C.UTF-8` は全ての Unicode 文字をカバーする必要がある
    - テーブルが巨大になる
        - スタティックリンクされたバイナリが巨大化するのは許容できない
        - `musl libc` のように小さなデータにしたいが, データ構造を大きく変える必要がある

など実装上の問題が大きいらしく, 実装には至っていない.

## `C.UTF-8` あるけど…

今, 一部のディストリビューションにある `C.UTF-8` ロケールは `glibc` 由来ではなくディストリビューションによるパッチによるもの.

# 力尽きた

各ディストリビューションによるパッチの履歴を見た比較を載せようと思ったが, Debian と Fedora を見たあたりで力尽きてしまった. 

大方, どのパッチも照合順序 (COLLATION) はコード順 (numerical order), それ以外は
`C` ロケールに準拠, といった感じの実装だったように見える.

少なくとも, 現時点では `glibc` は `C.UTF-8` ロケールを提供しておらず, ディストリビューションごとに独自のパッチでロケールを追加しているため, 文字コードが `UTF-8` であること以外は
何の動作の一貫性も保証されていないと思ったほうが良さそう.
