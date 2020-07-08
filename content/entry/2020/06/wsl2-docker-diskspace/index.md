---
title: WSL2 Docker が PC のディスクを圧迫する
date: 2020-06-06
slug: wsl2-docker-diskspace
tags: [Docker, WSL2]
---

# TL;DR

- WSL2 の Docker はディスクをバカ食いするから手動で掃除しよう

# 概要

WSL2 バックエンドの Docker では、コンテナやボリューム、イメージを削除しても、ホスト (Windows) のディスク容量が解放されない。

# 原因

WSL2 は一度確保したディスクをホストに返さないらしい。Issue が上がっている:

[WSL 2 should automatically release disk space back to the host OS · Issue #4699 · microsoft/WSL](https://github.com/microsoft/WSL/issues/4699)

## 確認

雑に確認してみる。

Docker のディスクファイル (`%LocalAppData%\Docker\wsl\data\ext4.vhdx`) のサイズを確認する。

- WSL2 バックエンドを作成したばかりのまっさらな状態:

    ```
    > docker image ls
    REPOSITORY          TAG                 IMAGE ID            CREATED             SIZE
    > dir

        Directory: C:\Users\Sarisia\AppData\Local\Docker\wsl\data

    Mode                 LastWriteTime         Length Name
    ----                 -------------         ------ ----
    -a----          6/6/2020   7:19 PM     1016070144 ext4.vhdx
    ```

    1016070144 B → **969 MB**

- 大きなイメージを pull した状態:

    ```
    > docker pull docker.pkg.github.com/sarisia/tex/texlive:2019-extra
    2019-extra: Pulling from sarisia/tex/texlive
    5bed26d33875: Pull complete
    f11b29a9c730: Pull complete
    930bda195c84: Pull complete
    78bf9a5ad49e: Pull complete
    5bff6f661674: Pull complete
    1e7babce469c: Pull complete
    bf656e88758e: Pull complete
    ab176992b632: Pull complete
    360f3ee99aa4: Pull complete
    Digest: sha256:f751375c5caad239d135f6aead80597c5b34aeb2b73f7e8d8ad297729c43b6d9
    Status: Downloaded newer image for docker.pkg.github.com/sarisia/tex/texlive:2019-extra
    docker.pkg.github.com/sarisia/tex/texlive:2019-extra
    > docker image ls
    REPOSITORY                                  TAG                 IMAGE ID            CREATED             SIZE
    docker.pkg.github.com/sarisia/tex/texlive   2019-extra          53c218d1c0bf        8 weeks ago         1.13GB
    > dir

        Directory: C:\Users\Sarisia\AppData\Local\Docker\wsl\data

    Mode                 LastWriteTime         Length Name
    ----                 -------------         ------ ----
    -a----          6/6/2020   7:27 PM     2224029696 ext4.vhdx
    ```

    2224029696 B → **2121 MB** (+1152 MB)

    イメージファイルが膨らんでいることが確認できる

- イメージを削除

    ```
    > docker image rm 53c218d1c0bf
    Untagged: docker.pkg.github.com/sarisia/tex/texlive:2019-extra
    Untagged: docker.pkg.github.com/sarisia/tex/texlive@sha256:f751375c5caad239d135f6aead80597c5b34aeb2b73f7e8d8ad297729c43b6d9
    Deleted: sha256:53c218d1c0bf44ef7a63d63111cbe067bd910faee6a1691ec6667e65e81e5439
    Deleted: sha256:f877802904c83a39bab53d6cb306d1d78ff697312fb98709c8cbcc6b6578b92a
    Deleted: sha256:a831a41179769eafa9c3a5c7398b121b76c01f7e781e2bfffde67c61d6c58594
    Deleted: sha256:b85b9c0c60ab67e67fa15e515463588d2315e0efe792f14539164acf3a5144fd
    Deleted: sha256:5e8b2c6dc77ceec953400743a186a5d1368f1ebee6a5b03528a47a47c83523a9
    Deleted: sha256:a2d4715ae3ad3235925b2675aab7e008adb071affc23fd8b4681b88758103200
    Deleted: sha256:1d9112746e9d86157c23e426ce87cc2d7bced0ba2ec8ddbdfbcc3093e0769472
    Deleted: sha256:efcf4a93c18b5d01aa8e10a2e3b7e2b2eef0378336456d8653e2d123d6232c1e
    Deleted: sha256:1e1aa31289fdca521c403edd6b37317bf0a349a941c7f19b6d9d311f59347502
    Deleted: sha256:c8be1b8f4d60d99c281fc2db75e0f56df42a83ad2f0b091621ce19357e19d853
    > docker image ls
    REPOSITORY          TAG                 IMAGE ID            CREATED             SIZE
    > dir

        Directory: C:\Users\Sarisia\AppData\Local\Docker\wsl\data

    Mode                 LastWriteTime         Length Name
    ----                 -------------         ------ ----
    -a----          6/6/2020   7:30 PM     2224029696 ext4.vhdx
    ```

    2224029696 B → **2121 MB** (+0 MB)

    **ホストのディスクが解放されていない。**

# 解決

上の Issue の通り手動で `vhdx` を最適化するか、または一度 Docker の WSL2 バックエンドを吹き飛ばしてしまえばいい。

## 解決策1. `vhdx` を最適化する

Hyper-V が有効である必要がある: **Windows 10 Pro 以上が必要**

既存のコンテナやボリュームを残したまま、ディスクのサイズを縮小できる。

`PowerShell` で `Optimize-VHD` すればよい。ドキュメントは:

[Optimize-VHD (hyper-v)](https://docs.microsoft.com/ja-jp/powershell/module/hyper-v/Optimize-VHD?view=win10-ps)

まず、 WSL の `docker-desktop-data` を停止するため、Windows の Docker Desktop を終了し、WSL を落とす:

```
> wsl --shutdown
```

そして、Administrator の PowerShell で、Docker のディスクファイル (`%LocalAppData%\Docker\wsl\data\ext4.vhdx`) に対して `Optimize-VHD` する:

```
> Optimize-VHD -Path .\ext4.vhdx -Mode full
> dir

    Directory: C:\Users\Sarisia\AppData\Local\Docker\wsl\data

Mode                 LastWriteTime         Length Name
----                 -------------         ------ ----
-a----          6/6/2020   7:33 PM      989855744 ext4.vhdx
```

989855744 B → **944 MB** (-1177 MB)

ディスクファイルのサイズが小さくなり、ホストのディスクが解放された。

## 解決策2. WSL2 バックエンドを作り直す

**既存のコンテナやボリューム、イメージがすべて吹き飛ぶので注意！**

Docker Desktop の設定で `User the WSL 2 based engine` のチェックを外し、 `Apply & Restart` する:

![WSL2%20Docker%20PC%20ad8f30855c0941edb68c18e04056e7f2/Untitled.png](WSL2%20Docker%20PC%20ad8f30855c0941edb68c18e04056e7f2/Untitled.png)

チェックを外すと、Docker は WSL2 を使わなくなるものの、WSL に登録されたディストリビューションは残ったままとなる:

```
> wsl --list --verbose
  NAME                   STATE           VERSION
* Ubuntu                 Stopped         2
  docker-desktop-data    Stopped         2
  docker-desktop         Stopped         2
```

ディストリビューションを削除すれば、ディスクも消える:

```
> wsl --unregister docker-desktop-data
Unregistering...
> wsl --unregister docker-desktop
Unregistering...
> wsl --list --verbose
  NAME      STATE           VERSION
* Ubuntu    Running         2
```

その後、再度 Docker Desktop の設定より、チェックを入れて適用すれば、ディストリビューションが再作成される。ただし、**Docker 上の全てが吹き飛ぶ**。