---
title: ローカルでも CI でも使える卒論ビルド環境
date: 2020-07-06
slug: paper-environment
tags: [Docker, GitHub Actions, LaTeX]
---

# TL;DR

ローカルビルドにも CI にも使える卒論 LaTeX のビルド環境を作った

# 概要

卒論を LaTeX で書くことになったが、環境構築を複数のマシンでするのがつらく、CI の自動ビルドを構築するのもつらい。Docker とビルドスクリプトで両方なんとかならないか考えていたらなんとかなったのでいくつか考慮するポイントを書き残しておく。

# ソースコード

ローカルのビルドにも利用でき、実際に CI も走っているリポジトリ。プレビューは `preview` ブランチ。

[kirchen-bell/paper-env](https://github.com/kirchen-bell/paper-env)

# できること

- ローカルで `docker-compose up` するだけで論文がビルドできる
- GitHub にプッシュすればローカルと同じビルド環境で勝手に CI してくれて `preview` ブランチの PDF が更新される
- `devcontainer` にも対応しているのでビルド環境のシェルでゴニョゴニョできる ( `devcontainer` の起動のために VSCode が必要)

# 解説

CI は [GitHub Actions](https://github.com/features/actions/) で構築するが、 Actions では任意の Docker イメージ上で作業できるため、基本的には:

- ビルド環境の Docker イメージ
- 上のイメージ上で正しく動作するビルドスクリプト

の2つが用意できればローカルでのビルド・CI での自動ビルドどちらも同じ環境で実行できる。

## ビルドスクリプト

以下の2点に気をつける:

- PDF ファイルの出力先を指定できるようにする

    大抵は `.tex` ファイルのあるディレクトリでビルドスクリプトを叩くとそのディレクトリに `.pdf` が生成されることを期待するが、最終的にプレビューブランチにデプロイしたいので、全ての成果物を1つのディレクトリにまとめておきたい。そのため、実行時にデフォルトの出力先を変更できるようにする。

    例えば、 `Makefile` なら:

    ```makefile
    # paper-env/src/Makefile
    # command
    LATEX = platex
    DVIPDF = dvipdfmx
    ...

    # files
    TARGET = paper
    SRC = $(TARGET).tex
    DVI = $(TARGET).dvi
    PDF = $(TARGET).pdf
    ...

    # output directory
    OUT_DIR = $(TARGET).pdf

    $(PDF): $(DVI)
    	$(DVIPDF) -o $(OUT_DIR) $<
    ...
    ```

    そして、実行時に

    ```
    $ make OUT_DIR=[output directory]/paper.pdf
    ```

    とする。

- `GITHUB_WORKSPACE` 環境変数に対応する

    GitHub Actions での CI の際、checkout されたリポジトリが格納されたディレクトリを `GITHUB_WORKSPACE` 環境変数として渡してくれる:

    [Using environment variables](https://docs.github.com/en/actions/configuring-and-managing-workflows/using-environment-variables#default-environment-variables)

    もし、ビルドスクリプト内で絶対パスを用いる必要がある場合は、この環境変数に対応する必要がある。

## Docker, Docker Compose

ビルド環境を Docker イメージとして固めておけば良い。 Docker Hub でも [GitHub Packages](https://github.com/features/packages) でもどちらに置いてもイメージのプルにかかる時間はあまり変わらなかったので、ここはログインなしでもプルできる Docker Hub がおすすめ。 (GitHub Packages はなんでパブリックイメージのプルにもログインが必要なんですか…？)

`LaTeX` や `pandoc` を扱えるイメージはたくさん転がっているため、それらを使っても良いし、自分の都合に合わせて作っても良いと思う。私のビルド環境イメージはこれ:

[sarisia/tex](https://github.com/sarisia/tex)

実行時は、生の `docker` コマンドを叩いても良いが、ディレクトリのマウントやコマンドの指定が面倒なので `docker-compose.yml` を書いておくと楽:

```yaml
# paper-env/docker-compose.yml
version: "3"
services: 
  texlive:
    image: sarisia/texlive:2019
    volumes:
      - .:/workspace:cached
    working_dir: /workspace
    entrypoint: []
    command: [ "make" ]
```

- ワーキングディレクトリをマウントする
- `entrypoint` を指定する

    デフォルトでは、 `Dockerfile` の `ENTRYPOINT` , `CMD` が使われる。また、 `Dockerfile` は親イメージの `ENTRYPOINT` と `CMD` を継承する。 `docker-compose.yml` で `command` だけ指定した場合、もし変な `ENTRYPOINT` が `Dockerfile` やその親イメージで指定されていた場合、おかしな動きをする場合があるため、 `entrypoint` を指定してクリアしておくと安心。

- ビルドスクリプトの起動は `command` で指定する

    後述の `devcontainer` 対応の際、 `devcontainer` の `docker-compose.yml` では `command` をオーバーライドしてコンテナが即死しないようにしているため、 `entrypoint` でビルドスクリプトの起動を指定してしまうと `command` が `entrypoint` の引数として解釈されてコンテナは死ぬ。

これで、ローカルでビルドするときは:

```
$ docker-compose up
```

するだけでビルドできるようになった。

## CI (GitHub Actions)

GitHub にプッシュしたら勝手に PDF にしてどこかに置いておいて欲しい。

GitHub Actions は Docker イメージをアクションとして実行できる。ビルドスクリプトや Docker メージを使い回せるので最高。

### アクション

以下の注意点に従い、 `Dockerfile` と `action.yml` を用意する:

[Dockerfile support for GitHub Actions](https://docs.github.com/en/actions/creating-actions/dockerfile-support-for-github-actions)

```docker
# paper-env/.github/actions/latex-ci/Dockerfile
FROM sarisia/texlive:2019
ENTRYPOINT [ "make" ]
```

ビルドスクリプトの実行は `ENTRYPOINT` で指定すると良い。 `ENTRYPOINT` をオーバーライドすると  `CMD` もリセットされるため、おかしな引数が混入することもない。

```yaml
# paper-env/.github/actions/latex-ci/action.yml
name: "latex ci"
description: "build latex documents"

runs:
  using: "docker"
  image: "Dockerfile"
```

GitHub Actions は、勝手にディレクトリをマウントし、そのディレクトリをワーキングディレクトリに指定しつつ `docker run` してくれる。

### ワークフロー

次に、アクションを利用するワークフローを定義する:

[Workflow syntax for GitHub Actions](https://docs.github.com/en/actions/reference/workflow-syntax-for-github-actions)

```yaml
# paper-env/.github/workflows/preview.yml
name: preview
on:
  push:
    branches:
      - "master"
    tags-ignore:
      - "**"

jobs:
  preview:
    name: preview
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: build documents
        uses: ./.github/actions/latex-ci
      - name: deploy to preview branch
        uses: peaceiris/actions-gh-pages@v3
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./preview
          publish_branch: preview
          keep_files: true
          commit_message: "preview:"
      - name: post status to discord
        uses: sarisia/actions-status-discord@v1
        if: always()
        with:
          webhook: ${{ secrets.DISCORD_WEBHOOK }}
          status: ${{ job.status }}
          job: deploy paper preview
```

`actions/checkout` と `./.github/actions/latex-ci` さえ忘れなければあとは自由。

今回は別ブランチへのコミットとビルド結果の Discord への通知を行っている。

## `devcontainer`

Docker コンテナを作業環境として使えるようにする。いちいち `docker exec` や `docker attach` とかしなくても `Visual Studio Code` ならワンクリックで起動できる。そうじゃなくても頑張って起動はできるのでファイルを置いておいて損はないと思う。

[Developing inside a Container using Visual Studio Code Remote Development](https://code.visualstudio.com/docs/remote/containers)

基本的には VSCode が勝手に自動生成してくれるファイルそのままで動く:

- `devcontainer/docker-compose.yml`

    ```yaml
    # paper-env/.devcontainer/docker-compose.yml
    #-------------------------------------------------------------------------------------------------------------
    # Copyright (c) Microsoft Corporation. All rights reserved.
    # Licensed under the MIT License. See https://go.microsoft.com/fwlink/?linkid=2090316 for license information.
    #-------------------------------------------------------------------------------------------------------------

    version: '3'
    services:
      # Update this to the name of the service you want to work with in your docker-compose.yml file
      texlive:
        # You may want to add a non-root user to your Dockerfile and uncomment the line below
        # to cause all processes to run as this user. Once present, you can also simply
        # use the "remoteUser" property in devcontainer.json if you just want VS Code and
        # its sub-processes (terminals, tasks, debugging) to execute as the user. On Linux,
        # you may need to ensure the UID and GID of the container user you create matches your 
        # local user. See https://aka.ms/vscode-remote/containers/non-root for details.
        # user: vscode

        # Uncomment if you want to add a different Dockerfile in the .devcontainer folder
        # build:
        #   context: .
        #   dockerfile: Dockerfile

        # Uncomment if you want to expose any additional ports. The snippet below exposes port 3000.
        # ports:
        #   - 3000:3000
        
        volumes:
          # Update this to wherever you want VS Code to mount the folder of your project
          - .:/workspace:cached

          # Uncomment the next line to use Docker from inside the container. See https://aka.ms/vscode-remote/samples/docker-in-docker-compose for details.
          # - /var/run/docker.sock:/var/run/docker.sock 

        # Uncomment the next four lines if you will use a ptrace-based debugger like C++, Go, and Rust.
        # cap_add:
        #   - SYS_PTRACE
        # security_opt:
        #   - seccomp:unconfined

        # Overrides default command so things don't shut down after the process ends.
        command: /bin/sh -c "while sleep 1000; do :; done"
    ```

VSCode 外で頑張って起動したいなら:

```
$ docker-compose -f docker-compose.yml -f .devcontainer/docker-compose.yml up -d
$ docker-compose exec texlive /bin/bash
```

# まとめ

今の所は特にストレス無く使えている。

Overleaf や Cloud LaTeX などのオンライン IDE 環境もあるが、コンパイラが制限されていたり UI が煩雑だったりとあまり心地よくなかったので環境が落ち着いてよかった。

GitHub の Codespaces がリリースされれば、 Web エディタや VSCode からのリモート接続もできるようになるので、ローカルへのクローンすら不要になる。楽しみですね。

[Codespaces](https://github.com/features/codespaces/)