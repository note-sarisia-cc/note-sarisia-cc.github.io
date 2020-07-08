---
title: GitHub Pages URL の挙動
date: 2020-06-25
slug: github-pages-url
tags: [GitHub]
---

# TL;DR

GitHub Pages に安易にオーガニゼーションページ (ユーザーページ) とプロジェクトページを共存させると到達不可能なページが出来てしまうので注意

# 概要

GitHub Pages はリポジトリにファイルを置いておけば勝手に静的サイトをホスティングしてくれるサービス:

[About GitHub Pages](https://help.github.com/en/github/working-with-github-pages/about-github-pages)

GitHub Pages では、デフォルトのページの URL はユーザー名 (オーガニゼーション名) とリポジトリ名によって決定される:

> To publish a user site, you must create a repository owned by your user account that's named `<user>.github.io`. To publish an organization site, you must create a repository owned by an organization that's named `<organization>.github.io`. Unless you're using a custom domain, user and organization sites are available at `http(s)://<username>.github.io` or `http(s)://<organization>.github.io`.

> The source files for a project site are stored in the same repository as their project. Unless you're using a custom domain, project sites are available at `http(s)://<user>.github.io/<repository>` or `http(s)://<organization>.github.io/<repository>`.

例えば、上のドキュメントに従えば:

- `kirchen-bell` というオーガニゼーションに `kirchen-bell.github.io` というリポジトリを作成した場合は `kirchen-bell.github.io` にページがホストされる
- `kirchen-bell` というオーガニゼーションに `pages-router-test` というリポジトリを作成した場合は `kirchen-bell.github.io/pages-router-test` にページがホストされる

## URL の衝突？

さて、ここで `kirchen-bell.github.io` リポジトリに `pages-router-test` ディレクトリを作成した場合:

- `kirchen-bell.github.io` リポジトリの `pages-router-test` ディレクトリ内のページ
- `pages-router-test` リポジトリのページ

の2つはいずれも `kirchen-bell.github.io/pages-router-test` という、同じ URL を持つことになる。この文章では、こういったルーティングが紛らわしい状態において、GitHub Pages の URL がどのような挙動をするのか検証する。

# 検証

## リポジトリ

- オーガニゼーションページ: `kirchen-bell/kirchen-bell.github.io`

    [kirchen-bell/kirchen-bell.github.io](https://github.com/kirchen-bell/kirchen-bell.github.io)

- プロジェクトページ: `kirchen-bell/pages-router-test`

    [kirchen-bell/pages-router-test](https://github.com/kirchen-bell/pages-router-test)

## ページ構造

- オーガニゼーションページ ( `kirchen-bell/kirchen-bell.github.io` )

    ```
    .
    └── pages-router-test
        ├── 404.html
        ├── index.html
        └── subdir
            └── index.html
    ```

- プロジェクトページ ( `kirchen-bell/pages-router-test` )

    ```
    .
    ├── 404.html
    ├── index.html
    └── subdir
        └── index.html
    ```

各 `index.html` や `404.html` はオーガニゼーションページのものかプロジェクトページのものか判別可能にしておく (何か変更を加えておく) 。

## ケース

以下の3つのリポジトリ存在ケースを扱う:

- プロジェクトページのみ存在
- オーガニゼーションページのみ存在
- プロジェクトページとオーガニゼーションページが両方存在

そして、各存在ケースに対してそれぞれ以下のアクセスを行う:

- https://kirchen-bell.github.io/pages-router-test
- https://kirchen-bell.github.io/pages-router-test/
- https://kirchen-bell.github.io/pages-router-test/subdir
- https://kirchen-bell.github.io/pages-router-test/subdir/
- https://kirchen-bell.github.io/pages-router-test/notfound
- https://kirchen-bell.github.io/pages-router-test/notfound/

# 結果

- 全てのリポジトリ存在ケースにおいて、存在しているページへのアクセスは末尾スラッシュ付きの URL へリダイレクトされる
    - 存在していないページへのアクセスはリダイレクトされず、そのまま 404 ページが表示される
- プロジェクトページまたはオーガニゼーションのどちらか片方しか存在しない場合は、そのページが表示される (当たり前)
- プロジェクトページとオーガニゼーションページどちらも存在する場合は、プロジェクトページが表示され、**オーガニゼーションページは一切表示されない**
- サブディレクトリへの 404 ページファイルの設置は効果がない。つまり、オーガニゼーションページのリポジトリの `pages-router-test/404.html` はアクセスできない。
    - オーガニゼーションページのリポジトリ直下に 404 ファイルを置いていれば正しく 404 ページが表示される

## テーブル

- `exists` キー

    `proj` は プロジェクトページのみ存在

    `org` は オーガニゼーションページのみ存在

    `proj + org` は両方存在

- パスは `https://kirchen-bell.github.io/pages-router-test` からの相対表示

    `.` は `https://kirchen-bell.github.io/pages-router-test`

    `./` は `https://kirchen-bell.github.io/pages-router-test/`

- 上段は表示されたページが `proj` (プロジェクトページ) のものか `org` (オーガニゼーションページ) のものか、または `github` (GitHub Pages のデフォルトページ) のものかを表す
- 下段は HTTP ステータスコード、リダイレクト先 (空欄は `200` )

| exists     | .                  | ./   | ./subdir                  | ./subdir/ | ./notfound      | ./notfound/     |
|------------|--------------------|------|---------------------------|-----------|-----------------|-----------------|
| proj       | proj<br>301 → ./ | proj | proj<br>301 → ./subdir/ | proj      | proj<br>404   | proj<br>404   |
| org        | org<br>301 → ./  | org  | org<br>301 → ./subdir/  | org       | github<br>404 | github<br>404 |
| proj + org | proj<br>301 → ./ | proj | proj<br>301 → ./subdir/ | proj      | proj<br>404   | proj<br>404   |

## 追加で検証した事項

- デプロイ順は (ほとんどの場合) 関係ない
    - "プロジェクトページ → オーガニゼーションページ" の順に公開しても、"オーガニゼーションページ → プロジェクトページ" の順にページを公開しても、いずれの場合も**プロジェクトページが存在すればオーガニゼーションページにはアクセスできない**
    - 特殊な状況ではルーティングがおかしくなったりするので再デプロイなどが必要
- プロジェクトページによってオーガニゼーションページが隠される際は透過的ではない

    例えば、プロジェクトページ ( `kirchen-bell/pages-router-test` ) に以下のファイル:

    ```
    .
    ├── 404.html
    └── index.html
    ```

    を設置し、オーガニゼーションページ ( `kirchen-bell/kirchen-bell.github.io` ) に以下のファイルを設置した場合:

    ```
    .
    └── pages-router-test
        ├── 404.html
        ├── index.html
        └── subdir
            └── index.html
    ```

    この場合、もし透過的に隠されていた場合は、 `https://kirchen-bell.github.io/pages-router-test/subdir` のような、プロジェクトページには存在しないがオーガニゼーションページには存在するようなページにはアクセスできるべきだが、**実際には透過的ではないため、このようなアクセスはできない**

- サブドメインを設定した場合も同じ挙動をする

# まとめ

- オーガニゼーションページとプロジェクトページが両方存在する場合は、**URL の重複したページへのアクセスは常にプロジェクトページへのアクセスとなる**
    - プロジェクトページを設置する際は、オーガニゼーションページを隠さないか気をつけなければならない
    - 逆も然りで、オーガニゼーションページを設置する際はプロジェクトページに隠されてアクセスできないページを作らないか気をつけなければならない
- GitHub Pages はファイルを置くだけでデプロイされる単純明快な機能で最高だが、実際にはかなり複雑なルーティングをしている
- この挙動もドキュメントに記載してほしい