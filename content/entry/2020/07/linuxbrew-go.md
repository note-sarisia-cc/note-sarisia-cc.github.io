---
title: Linuxbrew で入れた Go でビルドしたバイナリは可搬性が無い
date: 2020-07-22
slug: linuxbrew-go
tags: [Go, Homebrew, Linux, Linuxbrew]
---

# TL;DR

Linuxbrew で入れた Go でビルドしたダイナミックリンクされたバイナリは大抵別マシンで動かない

# 事の発端

AWS Lambda に入門しようと思い、適当なコードを Go で書いてビルドして[デプロイパッケージ](https://docs.aws.amazon.com/ja_jp/lambda/latest/dg/golang-package.html)にしてアップロードして実行したら失敗した上にエラーメッセージが意味不明だった:

```
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
|   timestamp   |                                                                               message                                                                                |
|---------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 1595370739688 | START RequestId: xxx Version: $LATEST                                                                                               |
| 1595370739689 | fork/exec /var/task/testbin: no such file or directory: PathError null                                                                                            |
| 1595370739689 | END RequestId: xxx                                                                                                                  |
| 1595370739689 | REPORT RequestId: xxx Duration: 0.50 ms Billed Duration: 100 ms Memory Size: 512 MB Max Memory Used: 23 MB Init Duration: 3.14 ms   |
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
```

パッケージ内にバイナリは存在しているし、コンソール上でハンドラも適切に設定されているのに `no such file or directory` はわからない…

# 原因

Linuxbrew で入れた Go がバイナリのインタプリタ (ダイナミックリンカ) を変なものに設定しているのでランタイム環境で **ダイナミックリンカ** が存在しない事に対して `no such file or directory` と怒られている。

## ダイナミックリンク

Go コンパイラは、デフォルトでスタティックリンクされたバイナリを吐き出すが、 `cgo` を用いたコードが含まれているとダイナミックリンクされたバイナリを出力するらしい[^1]。

今回は、AWS Lambda で動かすために `[github.com/aws/aws-lambda-go/lambda](http://github.com/aws/aws-lambda-go/lambda)` パッケージを用いていたが、このパッケージは `net` パッケージに依存しており、 `net` パッケージが `cgo` を利用しているために吐き出されるバイナリがダイナミックリンクされたものになったと考えられる。

## Linuxbrew の Go

ようやく本題に入る。

ダイナミックリンクされたバイナリは、実行時にダイナミックリンカが必要であり、どのダイナミックリンカを利用するかはバイナリ中の `.interp` セクションで指定されている。この値は `file` コマンドで確認することができる。

ここで、ローカルでは動作していたが Lambda にデプロイしても動かなかったバイナリを確認してみる:

```
$ file testbin
testbin: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), dynamically linked, interpreter /home/sarisia/.linuxbrew/lib/ld.so, Go BuildID=C7ri7ELuMn23zSXLRZ70/tza49RIreu-6rC35hD4y/4uNzsaPiAIEgluqCR5SC/E_CdXkyKKn-ONTIUXAJA, not stripped
$ ldd testbin
        linux-vdso.so.1 (0x00007fffe051b000)
        libpthread.so.0 => /lib/x86_64-linux-gnu/libpthread.so.0 (0x00007fc377db4000)
        libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x00007fc377bc2000)
        /home/sarisia/.linuxbrew/lib/ld.so => /lib64/ld-linux-x86-64.so.2 (0x00007fc377de1000)
```

インタプリタ (ダイナミックリンカ) として `/home/sarisia/.linuxbrew/lib/ld.so` が指定されている。こんなものリモート環境にあるはずがない。

## 何故

実は、何故 Linuxbrew の `ld` が参照されてしまうのかは原因が分かっていない。

`LD_LIBRARY_PATH` 等はセットされておらず、どこから `~/.linuxbrew/lib` が参照されているか分からない。

ビルド時の出力からリンカの引数を確認する:

```
$ go build -x
...
/home/sarisia/.linuxbrew/Cellar/go/1.14.4/libexec/pkg/tool/linux_amd64/link -o $WORK/b001/exe/a.out -importcfg $WORK/b001/importcfg.link -buildmode=exe -buildid=C7ri7ELuMn23zSXLRZ70/tza49RIreu-6rC35hD4y/4uNzsaPiAIEgluqCR5SC/C7ri7ELuMn23zSXLRZ70 -extld=gcc-9 /home/sarisia/.cache/go-build/6f/6f404b1d04e8ea7956855a9c485390cc12166c38b1082540b5f23c7de8f46574-d
```

`gcc-9` は `~/.linuxbrew/Homebrew/Library/Homebrew/shims/super/cc` を参照しているように見えるが、 Linuxbrew の内部をよく知らないのでご存知の方がいらっしゃいましたら是非教えて下さい。

# 解決策

いくつかあるので状況に応じて対応する。

## スタティックリンクさせる

一番楽な方法。バイナリがスタティックリンクされていればランタイムに依存せず実行できる。

`net` パッケージは `cgo` が利用できない際のフォールバック実装を持っているので、そちらを利用すれば良い。 `cgo` を無効にするには、環境変数を `CGO_ENABLED=0` に設定する:

```
$ CGO_ENABLED=0 go build
$ file testbin
testbin: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, Go BuildID=e2c96cEh0Furb-jQXPe3/tza49RIreu-6rC35hD4y/4uNzsaPiAIEgluqCR5SC/i0xRPZeJSG9uM89wNRS_, not stripped
$ ldd testbin
        not a dynamic executable
```

スタティックリンクされたバイナリになった。当然依存している共有ライブラリも存在しない。

## Linuxbrew で Go を入れない

`brew install go` した物を使わず、 [go.dev](http://go.dev) から入れたものや、ディストリビューションのリポジトリから入れたものでビルドする。

ここでは、GitHub Actions でビルドしたバイナリを確認してみる:

```
$ file testbin
testbin: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2, Go BuildID=Z6GFdv2uiNpPYLkL1BPg/3kN-MqjuCgKTC0TGWC4o/wP6Kg3NF2wnMoits94nV/avd9kHQHpyrfPJrd2TBW, not stripped
```

インタプリタが `/lib64/ld-linux-x86-64.so.2` に設定されており、これは Alpine Linux 等の特殊な環境でなければ存在するため、このバイナリは大抵の環境で実行できる。そのため、Linux でビルドしたバイナリは他マシンに移しても実行できると考えられがちである。実際 Linuxbrew で入れが Go がおかしいだけである。

# まとめ

根本的な原因が分かっていないのであまり釈然としない。

とりあえずスタティックバイナリを吐き出すように意識していれば間違いない…と思う。

Linuxbrew 、便利だけどちょっとつらいですね。

# 参考

[Statically compiling Go programs](https://www.arp242.net/static-go.html)

[Linuxbrew改めHomebrew@Linuxでrelocation errorに対する対処法](https://rcmdnk.com/blog/2019/05/08/computer-linux-homebrew/)

[^1]: 公式のドキュメントが見つからなかった…ご存知の方がいらっしゃいましたら是非教えて下さい。
