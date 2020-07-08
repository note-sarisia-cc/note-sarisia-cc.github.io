---
title: Go Module Mirror から壊れたパッケージが落ちてくる
created: 2020-06-21
date: 2020-06-21
slug: go-broken-mirror
tags: [Go]
---

# TL;DR

- パッケージのメンテナがリリースを間違えるとミラーから永遠に壊れたパッケージが落ちてくるのでユーザーは気をつけよう
- パッケージをリリースする人は一度ミラーされたバージョンは永遠に消えないのでかなり気をつけよう

```
$ go version
go version go1.14.1 darwin/amd64
```

# 概要

今日、Go 向け Discord クライアントライブラリの `DiscordGo` にアップデートが降ってきました:

[bwmarrin/discordgo](https://github.com/bwmarrin/discordgo/releases/tag/v0.21.0)

さて、早速自身のプロジェクトの依存関係のアップデートを試みます:

```
$ go get -u github.com/bwmarrin/discordgo
go: downloading github.com/bwmarrin/discordgo v0.21.0
go: downloading golang.org/x/crypto v0.0.0-20200604202706-70a84ac30bf9
go: downloading github.com/gorilla/websocket v1.4.2
go: downloading golang.org/x/sys v0.0.0-20200620081246-981b61492c35
go: github.com/gorilla/websocket upgrade => v1.4.2
go: golang.org/x/crypto upgrade => v0.0.0-20200604202706-70a84ac30bf9
go: golang.org/x/sys upgrade => v0.0.0-20200620081246-981b61492c35
# github.com/bwmarrin/discordgo
../../../../go/pkg/mod/github.com/bwmarrin/discordgo@v0.21.0/wsapi.go:852:19: (*Session).Close redeclared in this block
        previous declaration at ../../../../go/pkg/mod/github.com/bwmarrin/discordgo@v0.21.0/wsapi.go:846:6
```

なんと、ライブラリのビルドに失敗してしまいました。

# 原因を探る

壊れたバージョンをそのままリリースしてしまったのでしょうか。GitHub でホストされているコードを確認します:

[bwmarrin/discordgo](https://github.com/bwmarrin/discordgo/blob/cead8c70f6d1095cf7798efc223ec364a34dd14e/wsapi.go#L846)

`wsapi.go:846`

```go
// Close closes a websocket and stops all listening/heartbeat goroutines.
// TODO: Add support for Voice WS/UDP
func (s *Session) Close() error {
	return s.CloseWithCode(websocket.CloseNormalClosure)
}

// CloseWithCode closes a websocket using the provided closeCode and stops all
// listening/heartbeat goroutines.
// TODO: Add support for Voice WS/UDP connections
func (s *Session) CloseWithCode(closeCode int) (err error) {

	s.log(LogInformational, "called")
	s.Lock()
...
```

特に問題があるようには見えません。

では、実際にダウンロードされたソースコードを見てみます。

`$GOPATH/pkg/mod/github.com/bwmarrin/discordgo@v0.21.0/wsapi.go:846`

```go
func (s *Session) Close() error {
	return s.CloseWithCode(websocket.CloseNormalClosure)
}

// Close closes a websocket and stops all listening/heartbeat goroutines.
// TODO: Add support for Voice WS/UDP
func (s *Session) Close() error {
	return s.CloseWithCode(websocket.CloseNormalClosure)
}
```

なんと、**壊れたコードがダウンロードされているのです**。

# Go Module Mirror

Go 1.13 以降では、モジュールをダウンロードする際に `Go Module Mirror` を使うようになりました:

[golang/go](https://github.com/golang/go/wiki/Modules#go-113)

> The go tool now defaults to downloading modules from the public Go module mirror at [https://proxy.golang.org](https://proxy.golang.org/), and also defaults to validating downloaded modules (regardless of source) against the public Go checksum database at [https://sum.golang.org](https://sum.golang.org/).

`proxy.golang.org` からソースコードのミラーを落とし、 `sum.golang.org` データベースに対してチェックサムの検証を行います。

つまり、今回は Go Module Mirror から壊れたソースコードが落ちてきている疑いがあります。実際に確認をしてみます。

[https://proxy.golang.org/github.com/bwmarrin/discordgo/@v/v0.21.0.zip](https://proxy.golang.org/github.com/bwmarrin/discordgo/@v/v0.21.0.zip) にアクセスすると、ミラーされているソースコードが落ちてきます。これを展開し、中身を確認します:

`wsapi.go:846`

```go
func (s *Session) Close() error {
	return s.CloseWithCode(websocket.CloseNormalClosure)
}

// Close closes a websocket and stops all listening/heartbeat goroutines.
// TODO: Add support for Voice WS/UDP
func (s *Session) Close() error {
	return s.CloseWithCode(websocket.CloseNormalClosure)
}
```

`go get` で落ちてきたものと全く同じ、壊れたコードです。

# 壊れたコードがミラーされている

なぜ壊れたコードが Go Module Mirror や Go Checksum Database に登録されてしまったのでしょうか。

リリースされたブランチを見てみると、実は一度壊れたバージョンがリリースされてしまったのではないかと推察できます。

現在の `v0.21.0` タグの指すコミット:

[Fix double commit on merge · bwmarrin/discordgo@cead8c7](https://github.com/bwmarrin/discordgo/commit/cead8c70f6d1095cf7798efc223ec364a34dd14e)

1つ前のコミット:

[Release version v0.21.0 · bwmarrin/discordgo@1294b31](https://github.com/bwmarrin/discordgo/commit/1294b313b912a44ea9e94860b9b041a1d9fd1029)

おそらく、現在の `v0.21.0` タグがされたコミットの1つ前のコミットが一度リリースされ、後から現在のコミットへタグを張り替えたと考えられますが、 `git reflog` できないので真相はわかりません。

また、 Checksum Database への登録や、 Module Mirror へミラーされるタイミング等が明確に説明されたドキュメントを見つけられていません。

以下のページより:

[Go 1.13 に向けて知っておきたい Go Modules とそれを取り巻くエコシステム - blog.syfm](https://syfm.hatenablog.com/entry/2019/08/10/170730)

> しかし、sumdb が存在していても、世界中で初めてあるモジュールを使用する場合はその真正性をチェックできないという問題はあります。

とあるように、Module Mirror は Checksum Database への初めてリクエストがあった際にミラーや登録が行われていると考えられますが、公式のドキュメントをご存知でしたら是非ご教示ください。

# 回避

ユーザとしてできる回避策としては、一時的に Go Module Mirror を利用せず、ツリーから直接パッケージを取得すれば問題はありません:

`fish shell` なので `env GOPROXY=direct` としていますが、 `bash` 等なら `GOPROXY=direct` としてください ( `env` 不要)

```
$ go clean --modcache
$ env GOPROXY=direct go get github.com/bwmarrin/discordgo@v0.21.0
go: downloading github.com/bwmarrin/discordgo v0.21.0
go get: github.com/bwmarrin/discordgo@v0.21.0: verifying module: checksum mismatch
        downloaded: h1:a4V4v2IPHPy7l5XVbjJkJAj9R2Lhvz7vs5I4Mq3OFYk=
        sum.golang.org: h1:jGuwVZTUHZBUFZ3sm5cOqrwphGQWeL0/9XkaCbDEcrs=

SECURITY ERROR
This download does NOT match the one reported by the checksum server.
The bits may have been replaced on the origin server, or an attacker may
have intercepted the download attempt.

For more information, see 'go help module-auth'.
```

`go clean --modcache` を行わないと、先程ダウンロードされた壊れたソースコードに対してビルドを試みるために失敗します。

また、当然 Checksum Database に対しての検証は失敗するため、セキュリティエラーを吐きます。

## 根本的な解決

結構ありがちな問題らしく、 `proxy.golang.org` へブラウザからアクセスした際に閲覧できる FAQ に記載があります:

[Go modules services](https://proxy.golang.org/)

> I removed a bad release from my repository but it still appears in the mirror, what should I do?
Whenever possible, the mirror aims to cache content in order to avoid breaking builds for people that depend on your package, so this bad release may still be available in the mirror even if it is not available at the origin. The same situation applies if you delete your entire repository. We suggest creating a new version and encouraging people to use that one instead.

ミラーされたパッケージを修正や削除する方法は無いようです。

そのため、パッケージのメンテナに新しいリリースを作成してもらうのが現状ではベターだと考えられます。

今回は Issue を作成しました:

[v0.21.0 mirror hosted by proxy.golang.org is broken · Issue #783 · bwmarrin/discordgo](https://github.com/bwmarrin/discordgo/issues/783)

# まとめ

Module Mirror が導入された時より、「いつか壊れたリリース降ってくるんじゃないか…」と思っていましたが、実際に降ってきてしまったため、良い機会になりました。パッケージをリリースする際は気をつけましょう。