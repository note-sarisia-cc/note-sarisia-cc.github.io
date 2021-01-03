---
title: Slash CommandsでサーバレスなDiscordアプリを作る
date: Jan 3, 2021
slug: discord-slash-commands
tags: AWS, Discord, Lambda, Python
---

あけましておめでとうございます.

昨年の暮, 12月中旬頃, 突然に Discord の Slash Commands パブリックベータがリリースされました！

ユーザが Bot の機能を利用する際の UX 改善はもちろん, 開発者にとっても構造化されたコマンド情報の取得や Webhook コールバックのサポートなど, ただのコマンド機能に留まらず, Discord での新しいアプリのあり方を定義する大胆な機能追加です.

今回は, Slash Commands とその API について, 概要とその実装例を紹介します.

# Slash Commands

[Discord Developer Portal - API Docs for Bots and Developers](https://discord.com/developers/docs/interactions/slash-commands)

## 概要

従来の Discord API には, Bot がコマンドを実装するための公式な仕組みがありませんでした. そのため, Bot の機能を呼び出すために, ユーザはコマンドやパラメータを覚え, テキストとして気合で入力し送信, 開発者は受信したテキストを気合で処理することで擬似的なコマンド呼び出しを実現していました.

新しい Slash Commands は, Discord 上のアプリ (Bot) を開発・利用する新しい仕組みです. Slash Commands を実装することで, ユーザは Discord クライアント上で以下のようなヘルプ・入力補完を用いてアプリの機能を呼び出すことが出来ます:

![Slash%20Commands%E3%81%A6%E3%82%99%E3%82%B5%E3%83%BC%E3%83%8F%E3%82%99%E3%83%AC%E3%82%B9%E3%81%AADiscord%E3%82%A2%E3%83%95%E3%82%9A%E3%83%AA%E3%82%92%E4%BD%9C%E3%82%8B%209434c0ae99414f14ac3a200d2cad20bc/Untitled.png](Slash%20Commands%E3%81%A6%E3%82%99%E3%82%B5%E3%83%BC%E3%83%8F%E3%82%99%E3%83%AC%E3%82%B9%E3%81%AADiscord%E3%82%A2%E3%83%95%E3%82%9A%E3%83%AA%E3%82%92%E4%BD%9C%E3%82%8B%209434c0ae99414f14ac3a200d2cad20bc/Untitled.png)

そして開発者は, ユーザのコマンド入力を構造化されたデータとして受け取ることができ, また, 容易に応答メッセージを作成することが出来ます.

## 特徴

Slash Commands がどんな物なのか確認したところで, より具体的な特徴を紹介します:

- Discord クライアント上でアプリの持つ機能を確認することができる

    ユーザは `/` をテキストフィールドに入力することで, 利用可能なコマンド, その説明を一覧することが出来ます.

- Discord クライアント上でのヘルプ・入力補完 + 型を持つコマンドパラメータの指定

    ユーザがコマンドをテキストフィールドに入力する際, 画面上にパラメータやその説明を表示することが可能です. また, 各パラメータには "必須であるか" や, `STRING` , `BOOLEAN` , `USER` , `CHANNEL` 等の値の型, 長さやデフォルト値などの制約を指定することができ, ユーザが追加の入力補完を受けることができるほか, 開発者は Discord によってバリデーションされたユーザの入力を受け取ることができます.

- Webhook でのインタラクション受信

    従来の Discord API では, ユーザの入力に対してリアルタイムに応答するためには, WebSocket を用いて "Gateway API" に接続し, 常にサーバとの接続を維持する必要がありました. Slash Commands API では, Gateway API によるインタラクション (コマンド入力) の受信に加えて, 開発者があらかじめ指定したコールバックエンドポイントを叩いてくれる Webhook による受信を選択できるようになりました. これにより, サーバレスな Discord Bot を実装することが可能になり, 常に Gateway API に張り付くプロセスが不要になりました！

- 新しい OAuth2 スコープ, Bot アカウントが不要に

    Slash Commands のリリースに合わせて, Discord API に新しい OAuth2 スコープ `applications.commands` が追加されました. Slash Commands を利用するには, この `applications.commands` スコープが必須であるかわりに, `bot` スコープは不要です. つまり, サーバに Bot ユーザを追加せずともユーザのコマンド入力に応答することが可能になりました！

    (もちろん, 既存の Bot トークンを用いてコマンド関連のリソースを操作することも可能です.)

いかがでしょうか. Discord アプリのあり方を変える, かなり大胆な機能追加であることが感じ取れると思います.

# サーバレスなDiscordアプリを作る

やはり新機能は実際に触ってみないと楽しくありません. シンプルなサーバレスの Slash Commands アプリケーションを作成してみましょう.

## 構成

`/hello` コマンドを作成します.

`/hello` コマンドは `USER` 型のオプション `user` を取ります.

呼び出し例はこんな感じです:

![Slash%20Commands%E3%81%A6%E3%82%99%E3%82%B5%E3%83%BC%E3%83%8F%E3%82%99%E3%83%AC%E3%82%B9%E3%81%AADiscord%E3%82%A2%E3%83%95%E3%82%9A%E3%83%AA%E3%82%92%E4%BD%9C%E3%82%8B%209434c0ae99414f14ac3a200d2cad20bc/Untitled%201.png](Slash%20Commands%E3%81%A6%E3%82%99%E3%82%B5%E3%83%BC%E3%83%8F%E3%82%99%E3%83%AC%E3%82%B9%E3%81%AADiscord%E3%82%A2%E3%83%95%E3%82%9A%E3%83%AA%E3%82%92%E4%BD%9C%E3%82%8B%209434c0ae99414f14ac3a200d2cad20bc/Untitled%201.png)

[AWS SAM](https://aws.amazon.com/jp/serverless/sam/) (Lambda + API Gateway (HTTP API)) を用いて, Discord からのコールバックを受け取る HTTP POST エンドポイントを作成します.

Lambda のランタイムは `python3.8` です. また, デプロイパッケージの作成やデプロイに [aws-sam-cli](https://github.com/aws/aws-sam-cli) を利用します.

ソースコードは以下です:

[](https://github.com/sarisia/discord-slash-commands-helloworld)

## 実装

### リクエストの検証

コールバックが叩かれた際に, リクエストを処理する前に, そのリクエストが本当に Discord から送られたものかを検証する必要があります.

**必ず行ってください！** Discord へのコールバック登録時に**テストリクエストが複数回飛んでくる**ため, 検証をスキップすると Discord に怒られます. テストアプリだからといってサボらないようにしましょう. (1敗)

```python
def callback(event: dict, context: dict):
    headers: dict = event['headers']
    rawBody: str = event['body']

    # validate request
    signature = headers.get('x-signature-ed25519')
    timestamp = headers.get('x-signature-timestamp')
    if not verify(signature, timestamp, rawBody):
        return {
            "cookies": [],
            "isBase64Encoded": False,
            "statusCode": 401,
            "headers": {},
            "body": ""
        }
```

Discord からのリクエストには `X-Signature-Ed25519` と `X-Signature-Timestamp` の2つのヘッダが含まれています. これらを用いて, リクエストの署名を検証します. 以下は `verify()` の中身です:

```python
from nacl.signing import VerifyKey

verify_key = VerifyKey(bytes.fromhex(APPLICATION_PUBLIC_KEY)

def verify(signature: str, timestamp: str, body: str) -> bool:
    try:
        verify_key.verify(f"{timestamp}{body}".encode(), bytes.fromhex(signature))
    except Exception as e:
        print(f"failed to verify request: {e}")
        return False

    return True
```

タイムスタンプとリクエストボディを結合したバイト列を, 事前に Discord より取得した公開鍵 (`APPLICATION_PUBLIC_KEY`) を用いて検証します.  公開鍵は後のステップで Discord Developer Portal より取得します.

検証に失敗した場合は異常なリクエストなので, 処理を中断して HTTP `401` を返す必要があります.

### インタラクションを処理する

Discord から届くインタラクションには現状 `Ping` と `ApplicationCommand` の2種類があります.

`Ping` は, 開発者が Discord Developer Portal からアプリケーションにコールバックを登録しようとする際に届き, 定められた値を JSON で返す必要があります. 以下のような JSON が届きます:

```json
{
    "id": "795057182634541057",
    "token": "...",
    "type": 1,
    "version": 1
}
```

処理するコードは以下です:

```python
    req: dict = json.loads(rawBody)
    if req['type'] == 1: # InteractionType.Ping
        registerCommands()
        return {
            "type": 1 # InteractionResponseType.Pong
        }
```

`ApplicationCommand` は, 実際にユーザがコマンドを実行した際に届きます. レスポンスとしてメッセージを返すことが可能です.

`/hello` コマンドを `user` オプションを指定して実行すると, 以下のような JSON が届きます:

```json
{
    "channel_id": "...",
    "data": {
        "id": "791946542370127923",
        "name": "hello",
        "options": [
            {
                "name": "user",
                "value": "318221692206055424"
            }
        ]
    },
    "guild_id": "...",
    "id": "794678001563861062",
    "member": {
        "deaf": false,
        "is_pending": false,
        "joined_at": "2018-11-07T07:48:32.373000+00:00",
        "mute": false,
        "nick": "Sarisia",
        "pending": false,
        "permissions": "...",
        "premium_since": null,
        "roles": [
            "...",
            "..."
        ],
        "user": {
            "avatar": "42a6a8902f7540b04546b7ee24c272fc",
            "discriminator": "5572",
            "id": "316911818725392384",
            "public_flags": 64,
            "username": "sarisia"
        }
    },
    "token": "...",
    "type": 2,
    "version": 1
}
```

以下のようなコードで処理します:

```python
    elif req['type'] == 2: # InteractionType.ApplicationCommand
        # command options list -> dict
        opts = {v['name']: v['value'] for v in req['data']['options']} if 'options' in req['data'] else {}

        text = "Hello!"
        if 'user' in opts:
            text = f"Hello, <@{opts['user']}>!"

        return {
            "type": 4, # InteractionResponseType.ChannelMessageWithSource
            "data": {
                "content": text
            }
        }
```

レスポンスの `type` にも複数ありますが, ここでは `4 (ChannelMessageWithSource)` で応答しています. 外にも, ユーザの入力メッセージを削除しつつ応答する `ChannelMessage` や, 応答メッセージを返さない `Acknowledge` 等で応答することもできます.

### コマンドの登録

作成したコマンドを実行できるようにするには, Discord にコマンドの情報を登録する必要があります. 今回はテスト目的のため, `Ping` インタラクションが届いたとき, つまり Discord Developer Portal からコールバックを登録したタイミングで `registerCommands()` を叩いてコマンドを登録していますが, 実際にはコードのデプロイ時や, アプリがギルドに追加されたとき等, 様々なタイミングが考えられます.

`registerCommands` のコードです:

```python
def registerCommands():
    endpoint = f"{DISCORD_ENDPOINT}/applications/{APPLICATION_ID}/guilds/{COMMAND_GUILD_ID}/commands"
    print(f"registering commands: {endpoint}")

    commands = [
        {
            "name": "hello",
            "description": "Hello Discord Slash Commands!",
            "options": [
                {
                    "type": 6, # ApplicationCommandOptionType.USER
                    "name": "user",
                    "description": "挨拶する相手",
                    "required": False
                }
            ]
        }
    ]

    headers = {
        "User-Agent": "discord-slash-commands-helloworld",
        "Content-Type": "application/json",
        "Authorization": DISCORD_TOKEN
    }

    for c in commands:
        requests.post(endpoint, headers=headers, json=c).raise_for_status()
```

コマンドには,

- アプリケーションに紐付き, アプリケーションが追加されている全てのギルドで利用可能な `global command`
- アプリケーションとギルドのペアに紐付き, アプリケーションが追加されている特定のギルドでのみ利用可能な `guild command`

の2種類があります. 前者は登録されたコマンドが実際に利用可能になるまで最大1時間かかりますが, 後者は即時に利用可能になることが保証されているため, 今回は後者を登録します. 両者の登録の方法における違いはエンドポイント (`endpoint`) の違いのみです.

コマンドは, 名前, 説明やオプション (任意) で構成されます. オプションは, 型, 名前, 説明のほかに, 必須かどうか, デフォルト値や選択肢を設定することが出来ます. 今回は, `6 (USER)` 型のオプションを設定したことで, ユーザは Discord クライアント上でユーザ一覧などの入力補助を受けることができます.

Discord へのリクエスト認証は `DISCORD_TOKEN` トークンで行います. トークンは, アクセストークンを `Bearer <token>` で利用してもいいですし, Discord Developer Portal で取得できる Bot トークンを `Bot <token>` で利用することもできます. 今回は楽に取得できる Bot トークンを利用します.

## デプロイ

コードができたので, 実際にデプロイして動かしてみましょう！

### Discordから必要な情報を得る

Discord アプリの動作には, 以下の情報が必要です:

- Application ID (Client ID)

    アプリケーションを一意に識別する ID です. コマンドの登録の際に利用します.

- Public Key

    Discord からのリクエストの署名検証に用いる公開鍵です.

- Discord Token

    Discord のトークンです. コマンド登録の際に利用します. アクセストークン, または Bot トークンが利用できます.

- Guild ID

    ギルド (サーバ) を一意に識別する ID です. `guild command` を登録する際に利用します.

これらの情報は, Discord Developer Portal から得ることが出来ます. 取ってきましょう！

[Discord Developer Portal - API Docs for Bots and Developers](https://discord.com/developers/applications)

![Slash%20Commands%E3%81%A6%E3%82%99%E3%82%B5%E3%83%BC%E3%83%8F%E3%82%99%E3%83%AC%E3%82%B9%E3%81%AADiscord%E3%82%A2%E3%83%95%E3%82%9A%E3%83%AA%E3%82%92%E4%BD%9C%E3%82%8B%209434c0ae99414f14ac3a200d2cad20bc/Untitled%202.png](Slash%20Commands%E3%81%A6%E3%82%99%E3%82%B5%E3%83%BC%E3%83%8F%E3%82%99%E3%83%AC%E3%82%B9%E3%81%AADiscord%E3%82%A2%E3%83%95%E3%82%9A%E3%83%AA%E3%82%92%E4%BD%9C%E3%82%8B%209434c0ae99414f14ac3a200d2cad20bc/Untitled%202.png)

### `application.commands` スコープを取得する

冒頭で述べたとおり, Slash Commands は `bot` スコープだけでは動作せず, 新たに `application.commands` スコープが必要です. 以下の URL を叩いてアプリケーションのギルドでのスコープを更新しましょう. `**<YOUR_CLIENT_ID_HERE>` を Application ID で置き換えてください！**

`https://discord.com/api/oauth2/authorize?client_id=<YOUR_CLIENT_ID_HERE>&scope=applications.commands`

### Lambda関数をデプロイ

関数をデプロイしましょう.

SAM CLI を利用するなら:

```
$ sam build
$ sam deploy --guided
---出力
```

で簡単にデプロイできます. デプロイ中にトークンや公開鍵などの必要な情報を聞かれるので, 前のステップで取得した値を入力してください.

### アプリにコールバックURLを登録

Lambda関数をデプロイすると, エンドポイントのURLが得られます. これを Discord Developer Portal で `INTERACTIONS ENDPOINT URL` として登録します.

登録した情報を保存する際に, コールバックに検証リクエストが複数回送信されます. もし保存がエラーになる場合は, 実装やデプロイがうまく行っていない可能性があります.

### 動作確認

ここまでで, Discord 上でコマンドが実行できるようになっていると思います. 実際にコマンドを実行し, 動作確認をしましょう.

# おわりに

少し長くなりましたが, Discord に新しく実装された Slash Commands の概要とサンプルコマンドの実装例を紹介しました.

個人的には, サーバレスでイベント駆動な Discord Bot を書けるようになったのが非常に嬉しい反面, クライアントの自動補完がうまく働かなかったり, リクエストの `options` の配列がやや扱いづらかったりと, まだ荒削りな部分もあると感じました.

ベータを抜ける日が楽しみですね！