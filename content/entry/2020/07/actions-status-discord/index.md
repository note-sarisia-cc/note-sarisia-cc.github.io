---
title: Discord に GitHub Actions の結果を通知するアクションを作った
date: 2020-07-15
slug: actions-status-discord
tags: [Discord, GitHub Actions]
---

# TL;DR

`Actions Status Discord` をもっと使ってほしい

# 概要

[GitHub Actions](https://github.com/features/actions) は GitHub にくっついている CI/CD サービスです。リポジトリにワークフローファイルを置いておくだけで勝手に実行してくれますし、ソースコードと CI/CD の結果が同じ場所で管理できるので大変便利です。

さて、CI/CD を組んでいると欲しくなるのが外部サービスへの通知です。GitHub Actions にはデフォルトで Webhook 通知ができますが、Slack や Discord には味気ない通知しか届きません:

![Discord%20GitHub%20Actions%20aa7d4e052787407bbd8578c6ecb63766/Untitled.png](Discord%20GitHub%20Actions%20aa7d4e052787407bbd8578c6ecb63766/Untitled.png)

GitHub のデフォルト通知を用いた際の Discord 通知

GitHub Actions のアクションは自由に開発・配布できるので、Slack 向けにはいい感じのアクションが存在しています:

[Slack Notify - GitHub Marketplace](https://github.com/marketplace/actions/slack-notify)

しかし、Discord 向けの通知アクションは存在しているものの、テキストしか投稿できなかったり、Docker アクションであったり[^1]と、微妙なものしかありません。

せっかく Discord は Embed スタイルの綺麗なメッセージスタイルをサポートしているので、いい感じに通知を投稿してくれるアクションを作りました[^2]:

[Actions Status Discord - GitHub Marketplace](https://github.com/marketplace/actions/actions-status-discord)

# できること

こんな感じの通知が一瞬で設定できます:

![Discord%20GitHub%20Actions%20aa7d4e052787407bbd8578c6ecb63766/Untitled%201.png](Discord%20GitHub%20Actions%20aa7d4e052787407bbd8578c6ecb63766/Untitled%201.png)

詳細情報を省いたこんな感じのもできます:

![Discord%20GitHub%20Actions%20aa7d4e052787407bbd8578c6ecb63766/Untitled%202.png](Discord%20GitHub%20Actions%20aa7d4e052787407bbd8578c6ecb63766/Untitled%202.png)

## 詳細な紹介

結構好き勝手できるアクションなので、実際のワークフローと出力例を紹介します。

- ステータス通知

    ステータスの成功・失敗・キャンセルによって Embed の色が変わります。

    ```yaml
    - uses: sarisia/actions-status-discord@v1
      if: always()
      env:
        DISCORD_WEBHOOK: ${{ secrets.DISCORD_WEBHOOK }}
      with:
        status: ${{ job.status }}
    ```

    ![Discord%20GitHub%20Actions%20aa7d4e052787407bbd8578c6ecb63766/Untitled%203.png](Discord%20GitHub%20Actions%20aa7d4e052787407bbd8578c6ecb63766/Untitled%203.png)

    ![Discord%20GitHub%20Actions%20aa7d4e052787407bbd8578c6ecb63766/Untitled%204.png](Discord%20GitHub%20Actions%20aa7d4e052787407bbd8578c6ecb63766/Untitled%204.png)

- 豊富なオプション

    タイトルや説明文、Webhook 投稿ユーザの名前やアイコン変更など、多くのオプションを揃えました。

    ```yaml
    - uses: sarisia/actions-status-discord@v1
      if: always()
      with:
        webhook: ${{ secrets.DISCORD_WEBHOOK }}
        status: ${{ job.status }}
        title: "deploy"
        description: "Build and deploy to GitHub Pages"
        nofail: false
        nodetail: false
        color: 0x0000ff
        username: GitHub Actions
        avatar_url: ${{ secrets.AVATAR_URL }}
    ```

    ![Discord%20GitHub%20Actions%20aa7d4e052787407bbd8578c6ecb63766/Untitled%205.png](Discord%20GitHub%20Actions%20aa7d4e052787407bbd8578c6ecb63766/Untitled%205.png)

    詳細情報を一切なくすこともできます。

    ```yaml
    - uses: sarisia/actions-status-discord@v1
      with:
        webhook: ${{ secrets.DISCORD_WEBHOOK }}
        nodetail: true
        title: "We did it!"
    ```

    ![Discord%20GitHub%20Actions%20aa7d4e052787407bbd8578c6ecb63766/Untitled%206.png](Discord%20GitHub%20Actions%20aa7d4e052787407bbd8578c6ecb63766/Untitled%206.png)

- イベントに応じた説明文を自動生成

    GitHub Actions は GitHub の豊富な [Webhook イベント](https://docs.github.com/en/actions/reference/events-that-trigger-workflows)をフックとして実行できます。その時に渡されたイベントタイプと追加情報を元に、いい感じの説明文を生成します。

    - プッシュ

        プッシュに含まれる最新コミットの SHA とコミットメッセージ

        ![Discord%20GitHub%20Actions%20aa7d4e052787407bbd8578c6ecb63766/Untitled%207.png](Discord%20GitHub%20Actions%20aa7d4e052787407bbd8578c6ecb63766/Untitled%207.png)

    - プルリクエスト

        詳細ページへのリンク、タイトル

        ![Discord%20GitHub%20Actions%20aa7d4e052787407bbd8578c6ecb63766/Untitled%208.png](Discord%20GitHub%20Actions%20aa7d4e052787407bbd8578c6ecb63766/Untitled%208.png)

    Discord の Embed もマークダウンに対応しているので、GitHub のメッセージをそのまま持ってくるとリンクやコードブロックが綺麗に整形されます。良いですね。

    他にもいくつかのイベントに対応しています。是非プルリクエストをください。

# 使い方

README により詳細が書いてあります:

[Actions Status Discord - GitHub Marketplace](https://github.com/marketplace/actions/actions-status-discord)

[sarisia/actions-status-discord](https://github.com/sarisia/actions-status-discord)

是非使ってみてください！

[^1]: Docker アクションはイメージのプルとビルドが必要なので遅い: [https://docs.github.com/en/actions/creating-actions/about-actions#types-of-actions](https://docs.github.com/en/actions/creating-actions/about-actions#types-of-actions)

[^2]: 本当は去年リリースしていたが全然発見されず悲しくなったのでこの記事を書いた