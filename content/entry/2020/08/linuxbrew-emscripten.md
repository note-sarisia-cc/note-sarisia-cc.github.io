---
title: Linuxbrew で emscripten を導入する
date: 2020-08-05
slug: linuxbrew-emscripten
---

WSL2 上の Ubuntu に Linuxbrew で `emscripten` を入れようとしたときにコケたのでメモ.

<!--more-->

# やる

```
$ brew install emscripten
==> Downloading https://github.com/yui/yuicompressor/releases/download/v2.4.8/yuicompressor-2.4.8.zip
Already downloaded: /home/sarisia/.cache/Homebrew/downloads/a2d5c33d46d851dbf82d66ac461b61c365507a824bfc9d1f881269c1772582d1--yuicompressor-2.4.8.zip
==> Downloading https://github.com/emscripten-core/emscripten-fastcomp/archive/1.40.1.tar.gz
Already downloaded: /home/sarisia/.cache/Homebrew/downloads/03a73edc15d6b204d3684c02231dd0188de070c6d68b412778d847c784c6f0c4--emscripten-fastcomp-1.40.1.tar.gz
==> Downloading https://github.com/emscripten-core/emscripten-fastcomp-clang/archive/1.40.1.tar.gz
Already downloaded: /home/sarisia/.cache/Homebrew/downloads/e2d61edc18bf58cb13023f60e1a458f19c32200646f2443950b943a63fc31153--emscripten-fastcomp-clang-1.40.1.tar.gz
==> Downloading https://github.com/emscripten-core/emscripten/archive/1.40.1.tar.gz
Already downloaded: /home/sarisia/.cache/Homebrew/downloads/d46c0c89ba27a7c2fd6587614c6986009f8c9ab828d6271380c5543cb617ba29--emscripten-1.40.1.tar.gz
==> Installing dependencies for emscripten: yuicompressor
==> Installing emscripten dependency: yuicompressor
Error: An exception occurred within a child process:
  UnsatisfiedRequirements: Unsatisfied requirements failed this build.
```

`yuicompressor` のインストールでコケる.

## `yuicompressor`

コケている原因は Java が見つからないため. Linuxbrew ではインストール時にエラーを吐くが macOS ではなぜかインストールは通る[^1]

どうしてか `yuicompressor` の [Formulae](https://github.com/Homebrew/homebrew-core/blob/faad9048c1a533df04af280a9135049dfcf924d0/Formula/yuicompressor.rb) は Java 依存が明記されていないので, ディストリビューションのパッケージを入れる, または Linuxbrew で `openjdk` もしくは `adaptopenjdk` をインストールすれば良い.

とりあえず `Homebrew/homebrew-core` にプルリクエストを送った:

[yuicompressor: add openjdk as dependency by sarisia · Pull Request #59182 · Homebrew/homebrew-core](https://github.com/Homebrew/homebrew-core/pull/59182)

## リトライ

```
$ brew install emscripten
==> Downloading https://github.com/emscripten-core/emscripten-fastcomp/archive/1.40.1.tar.gz
Already downloaded: /home/sarisia/.cache/Homebrew/downloads/03a73edc15d6b204d3684c02231dd0188de070c6d68b412778d847c784c6f0c4--emscripten-fastcomp-1.40.1.tar.gz
==> Downloading https://github.com/emscripten-core/emscripten-fastcomp-clang/archive/1.40.1.tar.gz
Already downloaded: /home/sarisia/.cache/Homebrew/downloads/e2d61edc18bf58cb13023f60e1a458f19c32200646f2443950b943a63fc31153--emscripten-fastcomp-clang-1.40.1.tar.gz
==> Downloading https://github.com/emscripten-core/emscripten/archive/1.40.1.tar.gz
Already downloaded: /home/sarisia/.cache/Homebrew/downloads/d46c0c89ba27a7c2fd6587614c6986009f8c9ab828d6271380c5543cb617ba29--emscripten-1.40.1.tar.gz
==> cmake .. -DCMAKE_INSTALL_PREFIX=/home/sarisia/.linuxbrew/Cellar/emscripten/1.40.1/libexec/llvm -DLLVM_TARGETS_TO_BUI
==> make
Last 15 lines from /home/sarisia/.cache/Homebrew/Logs/emscripten/02.make:
[ 39%] Building CXX object tools/clang/lib/ARCMigrate/CMakeFiles/clangARCMigrate.dir/TransProperties.cpp.o
virtual memory exhausted: Cannot allocate memory
make[2]: *** [tools/clang/lib/ARCMigrate/CMakeFiles/clangARCMigrate.dir/build.make:173: tools/clang/lib/ARCMigrate/CMakeFiles/clangARCMigrate.dir/TransAutoreleasePool.cpp.o] Error 1
make[2]: *** Waiting for unfinished jobs....
g++-9: fatal error: Killed signal terminated program cc1plus
compilation terminated.
make[2]: *** [tools/clang/lib/Sema/CMakeFiles/clangSema.dir/build.make:407: tools/clang/lib/Sema/CMakeFiles/clangSema.dir/SemaExpr.cpp.o] Error 1
make[2]: *** Deleting file 'tools/clang/lib/Sema/CMakeFiles/clangSema.dir/SemaExpr.cpp.o'
[ 39%] Linking CXX static library ../../../../../lib/libclangRewriteFrontend.a
[ 39%] Built target clangRewriteFrontend
[ 39%] Linking CXX static library ../../../../lib/libclangSerialization.a
[ 39%] Built target clangSerialization
make[1]: *** [CMakeFiles/Makefile2:13041: tools/clang/lib/ARCMigrate/CMakeFiles/clangARCMigrate.dir/all] Error 2
make[1]: *** [CMakeFiles/Makefile2:12905: tools/clang/lib/Sema/CMakeFiles/clangSema.dir/all] Error 2
make: *** [Makefile:171: all] Error 2

READ THIS: https://docs.brew.sh/Troubleshooting
```

今度は `emscripten` のビルドでコケている.

## `emscripten`

吐いているエラー: `virtual memory exhausted: Cannot allocate memory` で調べると普通にメモリが足りないらしい. 一応32GBあるのに…

ビルド時のスレッド数 ( `make -jXX` ) を適当に減らせばメモリ使用量も減らせる. Homebrew なら `HOMEBREW_MAKE_JOBS` 環境変数を設定すれば勝手に `make` のオプションとして渡してくれる:

```
$ HOMEBREW_MAKE_JOBS=4 brew install emscripten
==> Downloading https://github.com/emscripten-core/emscripten-fastcomp/archive/1.40.1.tar.gz
Already downloaded: /home/sarisia/.cache/Homebrew/downloads/03a73edc15d6b204d3684c02231dd0188de070c6d68b412778d847c784c6f0c4--emscripten-fastcomp-1.40.1.tar.gz
==> Downloading https://github.com/emscripten-core/emscripten-fastcomp-clang/archive/1.40.1.tar.gz
Already downloaded: /home/sarisia/.cache/Homebrew/downloads/e2d61edc18bf58cb13023f60e1a458f19c32200646f2443950b943a63fc31153--emscripten-fastcomp-clang-1.40.1.tar.gz
==> Downloading https://github.com/emscripten-core/emscripten/archive/1.40.1.tar.gz
Already downloaded: /home/sarisia/.cache/Homebrew/downloads/d46c0c89ba27a7c2fd6587614c6986009f8c9ab828d6271380c5543cb617ba29--emscripten-1.40.1.tar.gz
==> cmake .. -DCMAKE_INSTALL_PREFIX=/home/sarisia/.linuxbrew/Cellar/emscripten/1.40.1/libexec/llvm -DLLVM_TARGETS_TO_BUI
==> make
==> make install
==> npm install -ddd --build-from-source --cache=/home/sarisia/.cache/Homebrew/npm_cache
Warning: emscripten dependency icu4c was built with a different C++ standard
library (libstdc++ from gcc-5). This may cause problems at runtime.
==> Caveats
Manually set LLVM_ROOT to
  /home/sarisia/.linuxbrew/opt/emscripten/libexec/llvm/bin
and BINARYEN_ROOT to
  /home/sarisia/.linuxbrew/opt/binaryen
in ~/.emscripten after running `emcc` for the first time.
==> Summary
🍺  /home/sarisia/.linuxbrew/Cellar/emscripten/1.40.1: 11,268 files, 1GB, built in 26 minutes 33 seconds
```

時間はかかったが無事インストールできた. 10スレッドにしても良かったかも.

[^1]: なぜ macOS だとインストールだけ通るのかは詳しく調べていない. macOS の Java ラッパー ( `java` で実行すると "インストールしろ" と怒ってくるやつ ) が何かしている？