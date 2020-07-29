---
title: UWP アプリは localhost へ接続できない
date: 2020-07-29
slug: uwp-localhost
tags: [Charles, MITM, UWP, Windows]
---

# TL;DR

UWP (Windows Store) アプリはデフォルトでループバック (localhost) に接続できないので免除リストに登録する必要がある

# 概要

[Charles](https://www.charlesproxy.com/) で Windows Store アプリ (UWP アプリ) の通信を確認したかったが一向に通信がキャプチャできない. しかも Charles を起動したら UWP アプリだけ一切の通信ができなくなってしまった.

# 原因

UWP アプリはデフォルトでループバックアドレス (localhost) へのアクセスをブロックされている:

[プロセス間通信 (IPC) - UWP applications](https://docs.microsoft.com/ja-jp/windows/uwp/communication/interprocess-communication#loopback)

Charles や MITM Proxy 等はローカルにプロキシサーバを起動し, Windows のプロキシ設定をそこに向ける. Charles の場合, デフォルトでは `127.0.0.1:8888` にプロキシサーバが起動し, Windows のプロキシ設定もそこに向けられていた.

しかし, UWP アプリは `127.0.0.1` にアクセスできないため, 一切の通信が行えなくなった.

# 解決

UWP アプリをループバック規制の免除リストに追加する.

## `PackageFamilyName` を確認

Store ページとかディレクトリとか簡単に確認する方法が無いかいろいろ試したが駄目っぽい. 仕方ないので PowerShell を使う:

```
PS > Get-AppxPackage | Select -Property Name,PackageFamilyName
...
Microsoft.XboxApp                                  Microsoft.XboxApp_8wekyb3d8bbwe
Microsoft.MinecraftUWP                             Microsoft.MinecraftUWP_8wekyb3d8bbwe
Microsoft.BingNews                                 Microsoft.BingNews_8wekyb3d8bbwe
NVIDIACorp.NVIDIAControlPanel                      NVIDIACorp.NVIDIAControlPanel_56jybvy8sckqj
...
```

名前で当たりを付けるなら:

```
PS > PS > Get-AppxPackage | Select -Property Name,PackageFamilyName | Select-String "minecraft"
@{Name=Microsoft.MinecraftUWP; PackageFamilyName=Microsoft.MinecraftUWP_8wekyb3d8bbwe}
```

`Name` にも `PackageFamilyName` にもアプリ名が含まれていないアプリもあったので気合でなんとかする必要もあるかもしれない.

## リストへ追加

管理者権限が必要.

試しに Minecraft を追加してみる.

```
PS > CheckNetIsolation.exe LoopbackExempt -a -n="Microsoft.MinecraftUWP_8wekyb3d8bbwe"
OK.
```

確認する.

```
PS > CheckNetIsolation.exe LoopbackExempt -s
[1] -----------------------------------------------------------------
    Name: microsoft.minecraftuwp_8wekyb3d8bbwe
    SID:  S-1-15-2-1958404141-86561845-1752920682-3514627264-368642714-62675701-733520436

[2] -----------------------------------------------------------------
...
```

追加できているので, アプリでループバックへ接続できるか試す.

# 余談

Minecraft for Windows 10 (Bedrock Edition) でローカルに建てた [Dedicated Server](https://www.minecraft.net/en-us/download/server/bedrock/) に接続できないのも, これが原因である. サーバに同梱されている README にも同じ対処法が記載されている:

> On some systems, when you wish to connect to the server using a client running on the same machine as the server is running on, you will need to exempt the Minecraft client from UWP loopback restrictions:

```
CheckNetIsolation.exe LoopbackExempt –a –p=S-1-15-2-1958404141-86561845-1752920682-3514627264-368642714-62675701-733520436
```

ドキュメントにはマニフェストをいじれば制限の対象外に出来るような記述があったけれど, UWP いじったことないので適当なことは言えない...
