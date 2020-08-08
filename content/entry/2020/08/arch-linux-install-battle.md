---
title: Arch Linux Install Battle
date: 2020-08-08
slug: arch-linux-install-battle
tags: ["Arch Linux", Linux]
---

Arch Linux 何度もインストールしているのに毎回何かしら忘れて敗北してしまうのでさすがにやることメモを作っておく.

CLI のみ, 最低限リモートから SSH で作業できるような環境を整えるまでが目標.

# インストール

インストールガイドの通りにやるだけですね.

[インストールガイド](https://wiki.archlinux.jp/index.php/%E3%82%A4%E3%83%B3%E3%82%B9%E3%83%88%E3%83%BC%E3%83%AB%E3%82%AC%E3%82%A4%E3%83%89)

### インターネット接続

有線なら起動時に勝手に `dhcpcd` してくれるので既に繋がっているはず.

無線は Archiso なら `networkmanager`, `wpa_supplicant` あたりは使える. どちらもワンライナーでなんとかなる. 今回は `wpa_supplicant`.

[wpa_supplicant](https://wiki.archlinux.jp/index.php/Wpa_supplicant)

```
# ip link
# wpa_supplicant -B -i <interface> -c <(wpa_passphrase <YOUR_SSID> <YOUR_PASSPHRASE>)
# ping archlinux.jp
```

### システムクロック

```
# timiedatectl set-ntp true
```

### パーティショニング

最低限 EFI System と ext4 を作れば良い.

```
# fdisk -l
# fdisk /dev/sda
# mkfs.fat -F32 /dev/sda1
# mkfs.ext4 /dev/sda2
# mount /dev/sda2 /mnt
# mkdir /mnt/boot
# mount /dev/sda1 /mnt/boot
```

### `pacstrap`

```
# pacstrap /mnt base linux linux-firmware
```

### 諸設定

```
# genfstab -U /mnt >> /mnt/etc/fstab
# arch-chroot /mnt
# ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
# hwclock --systohc

# nano /etc/locale.gen
# locale-gen

# echo "LANG=en_US.UTF-8" > /etc/locale.conf
# echo HOSTNAME > /etc/hostname
# nano /etc/hosts
# passwd
```

## ブートローダ

Ubuntu や Debian に甘やかされているとなぜか忘れてしまうブートローダ.

`grub` は単純な構成ならブートエントリを書かなくて済むのでいつもこれでやっている.

[GRUB](https://wiki.archlinux.jp/index.php/GRUB)

```
# pacman -S grub efibootmgr
# grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=grub
```

### `ucode`

いつもすぐに設定ファイルを生成したくなってしまい, マイクロコードを入れ忘れて二度手間になる. `intel-ucode` または `amd-ucode` を導入.

[マイクロコード](https://wiki.archlinux.jp/index.php/%E3%83%9E%E3%82%A4%E3%82%AF%E3%83%AD%E3%82%B3%E3%83%BC%E3%83%89)

パッケージを入れたら `grub` 設定を生成する:

```
# pacman -S intel-ucode
# grub-mkconfig -o /boot/grub/grub.cfg
```

基本的なインストールはこれで終了.

# インストール後設定

## インターネット

有線, 無線どちらのツールも入れておいたほうがいい. `dhcpcd` を入れ忘れて無線でパッケージを取ろうとして `wpa_supplicant` を入れ忘れて詰んでしまった (1敗).

`networkmanager` 入れておけば何でもできて安心かもしれない.

```
# pacman -S wpa_supplicant dhcpcd
# systemctl enable dhcpcd@eth1
```

## `sshd`

HID 外したあとに SSH 設定忘れていて孤独のサーバが完成する.

[Secure Shell](https://wiki.archlinux.jp/index.php/Secure_Shell)

```
# pacman -S openssh
# nano /etc/ssh/sshd_config
# systemctl enable sshd
```

## ユーザ

ユーザを作成する. SSH ルートログインは切っておくべきだが, ここでユーザを作り忘れていると敗北する.

```
# useradd -G wheel -m sarisia
# passwd sarisia
```

## `sudo`

今回は完璧だと思っていたのに `sudo` の設定を忘れていて敗北してしまった. 結構忘れやすいと思う.

`visudo` を通さないと怖い. エディタは `EDITOR` 環境変数で変えられる.

[Sudo](https://wiki.archlinux.jp/index.php/Sudo)

```
# pacman -S sudo
# EDITOR=nano visudo
```

# まとめ

ここまで設定すれば最低限違和感なくリモート作業できるようになると思う.

次こそ勝利したい.