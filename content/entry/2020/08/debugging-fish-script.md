---
title: fish スクリプトのデバッグ
date: 2020-08-10
slug: debugging-fish-script
tags: [fish, shell]
---

[fish-shell 3.1.0](https://github.com/fish-shell/fish-shell/blob/master/CHANGELOG.rst#fish-310-released-february-12-2020) のリリースで, スクリプトのデバッグ関連機能が非常に豊富になっている事に今更気づいた. いくつか使ってみたので, 簡単な使い方などをメモ.

# `fish_trace`

[Issue #3427](https://github.com/fish-shell/fish-shell/issues/3427) で提案, [Pull Request #6255](https://github.com/fish-shell/fish-shell/pull/6255) で実装された.

[Introduction - fish-shell 3.1.2 documentation](https://fishshell.com/docs/current/index.html)

bash で `set -x` を設定した時のようなスクリプト実行のトレースを出力してくれる:

> fish_trace, if set and not empty, will cause fish to print commands before they execute, similar to set -x in bash. The trace is printed to the path given by the --debug-output option to fish (stderr by default).

`fish_trace` 変数を `1` に設定してスクリプト (関数) を実行するだけ.

`test.fish` :

```bash
echo "test script"
echo $USER
```

```
~> set fish_trace 1
~> source test.fish
+ source test.fish
+++ echo 'test script'
test script
+++ echo sarisia
sarisia
```

`fish --debug-output LOG_FILE` で指定したログファイルに出力することもできる:

```
~> fish --debug-output=fish.log
~> set fish_trace 1
~> source test.fish
test script
sarisia
~> cat fish.log
+ source test.fish
+++ echo 'test script'
+++ echo sarisia
+ cat fish.log
```

変数の展開結果やスクリプトがどこで詰まっているか簡単に確認する時に便利.

`--debug-output` の代わりに `-o` も使えると書いてある[^1]が実際には動かない. バグ？

# `fish --debug`

`fish --debug=DEBUG_GLOB` で指定したカテゴリのログを出力する. 以前のオプション `--debug-level` でもログを出力できたが, ログレベルについての説明がドキュメントに一切なく謎だった. 今回の改善によってログ出力のコントロールがやりやすくなって便利.

カテゴリ一覧は `fish --print-debug-categories` で確認できる:

```
~> fish --print-debug-categories
char-encoding        Character encoding issues
debug                Debugging aid (on by default)
env-export           Changes to exported variables
env-locale           Changes to locale variables
error                Serious unexpected errors (on by default)
exec-fork            Calls to fork()
exec-job-exec        Jobs being executed
exec-job-status      Jobs changing status
history              Command history events
iothread             Background IO thread events
proc-internal-proc   Internal (non-forked) process events
proc-job-run         Jobs getting started or continued
proc-reap-external   Reaping external (forked) processes
proc-reap-internal   Reaping internal (non-forked) processes
proc-termowner       Terminal ownership events
profile-history      History performance measurements
topic-monitor        Internal details of the topic monitor
```

カテゴリ指定には `glob` パターンを利用できる. ドキュメントには一切例がないもののこう書いたら動いた:

```
# env-localeのみ
~> fish --debug=env-locale
env-locale: locale var LANG='en_US.UTF-8'
env-locale: locale var LANGUAGE missing or empty
...

# env系すべて
~> fish --debug="env-*"
env-locale: locale var LANG='en_US.UTF-8'
env-locale: locale var LANGUAGE missing or empty
...
env-export: create_export_array() recalc

# env系すべてとhistory
~> fish --debug="env-*,history"
env-locale: locale var LANG='en_US.UTF-8'
env-locale: locale var LANGUAGE missing or empty
...
env-export: create_export_array() recalc
~> ehistory: Loaded 162 old items

# すべてのログ
~> fish --debug="*"
```

`fish_trace` だけではイマイチ情報が不足しているときに便利. ただ, 膨大な量のログを吐くので, 欲しいカテゴリに当たりをつけたほうがいいかもしれない.

こちらも `--debug-output` でログ出力先を制御できる:

```
~> fish --debug="env-*" --debug-output=fish.log
~> cat fish.log
env-locale: locale var LANG='en_US.UTF-8'
env-locale: locale var LANGUAGE missing or empty
...
env-export: create_export_array() recalc
```

やっぱり `-o` オプション[^1]は動作しない.

# まとめ

fish-shell 3.1 で, カジュアルなトレースも, より詳細なログも非常に取りやすくなった.

デバッグを活用して良き fish ライフを！

[^1]: ヘルプはこれ: [https://fishshell.com/docs/current/cmds/fish.html#cmd-fish](https://fishshell.com/docs/current/cmds/fish.html#cmd-fish)  
Issue 建てた: [https://github.com/fish-shell/fish-shell/issues/7254](https://github.com/fish-shell/fish-shell/issues/7254)