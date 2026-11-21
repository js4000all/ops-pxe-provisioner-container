# Windows + Docker Desktop による PXE ブート検証記録

検証日: 2026-11-21

## 目的と構成

開発者が普段利用している Windows PC を PXE プロビジョニングの管理端末として利用できるか確認する。専用の NixOS 管理 PC を事前構築しなくても、Docker Desktop 上で ISO 準備・HTTP 配信を実行できることを目指す。

```text
同一 LAN
├─ 既存 DHCP サーバ（IP アドレス配布）
├─ Windows 管理 PC（検証時 192.168.1.70）
│  ├─ Tiny PXE Server（Windows ネイティブ、ProxyDHCP + TFTP）
│  └─ Docker Desktop
│     ├─ image-preparer（ISO 取得・検証・kernel/initrd 抽出）
│     └─ nginx / files（HTTP :8080）
└─ PXE 起動する別 PC
   └─ iPXE → HTTP で kernel/initrd → Ubuntu ISO を取得
```

当初は `pixiecore` を Docker Desktop の `network_mode: host` で実行したが、対象 PC は DHCP 待ちでタイムアウトし、pixiecore のログに要求が表示されなかった。一方、対象 PC は内蔵 OS 起動後に SSH 接続できた。Docker Desktop のブロードキャスト到達性に問題がある可能性はあるが、原因は確定していない。

そこで PXE/ProxyDHCP と TFTP のみを Windows ネイティブの Tiny PXE Server へ移し、HTTP 配信は既存の nginx コンテナを使用する構成へ切り替えた。

## 使用したソフトウェア・参照先

- [Tiny PXE Server — プロジェクト](https://github.com/erwan2212/tinypxeserver)
- [Tiny PXE Server — 配布アーカイブの GitHub 表示ページ](https://github.com/erwan2212/tinypxeserver/blob/main/pxesrv.zip)（**直接ダウンロード用 URL ではない**）
- Tiny PXE Server 画面に表示されたバージョン: `1.0.0.23`
- Docker Desktop と本リポジトリの `files`（nginx）、`image-preparer`
- **実際に使用した iPXE ブートローダー:** Tiny PXE Server 配布物の `files` 内に同梱されている `ipxe-undionly.kpxe`。バイナリの個別バージョンは未記録。

## 検証時の Tiny PXE Server 画面

確認された設定・表示:

| 項目 | 値・状態 |
|---|---|
| 管理 PC の IP | `192.168.1.70` |
| ProxyDhcp | 有効 |
| TFTPd | ログ上で有効 |
| HTTPd | 無効 |
| Bind IP | 有効 |
| Option 54 / Next-Server | `192.168.1.70` |
| Option 1 (Subnet Mask) | `255.255.255.0` |
| Option 3 (Router) | `192.168.1.1` |
| Option 6 (DNS Server) | `192.168.1.1` |
| Option 60 (ClassID) | `PXEClient` |
| Boot File / Filename | 画面上は `ipxe.pxe` |
| Filename if user-class=gPXE or iPXE | チェックあり（右欄の値は画面では空欄） |

この表は**設定途中に共有されたスクリーンショットの記録**であり、ISO ダウンロードまで成功した時点の最終設定が同一だったと確認したものではない。成功時に使用したブートローダーのファイル名は `ipxe-undionly.kpxe` と後から確認された。スクリーンショット上の `ipxe.pxe` とは異なるため、最終的な GUI の Filename 入力値は引き続き未確認。

### iPXE ブートローダーの選択

- **今回の実績:** 同梱 `files/ipxe-undionly.kpxe` で Ubuntu ISO のダウンロード段階まで到達。`undionly` 系は一般に Legacy BIOS PXE のための形式であり、この結果のみから UEFI ブートの成功は主張しない。
- **UEFI x64 の候補（未検証）:** 同梱されていると報告された `ipxe-x86_64.efi` および `ipxe-snponly-x86-64.efi`。UEFI PXE の初期起動では EFI 形式のブートローダーが必要となるため、次回 UEFI 機で個別に検証する。

実際の起動モード（Legacy BIOS / UEFI）を明示的に確認した記録はない。UEFI 候補についてはファイル名からの用途推定であり、起動成功の実績ではない。

## Compose 側と iPXE の接続方法

現行の `compose.yaml` では `files` が `./assets` を nginx のドキュメントルートとして公開する。したがって `assets/boot.ipxe` にスクリプトを置けば `http://192.168.1.70:8080/boot.ipxe` から提供できる。

以下は当時提示した **設定例** であり、実機で使われたファイル内容が完全に一致することは未確認:

```ipxe
#!ipxe
dhcp
kernel http://192.168.1.70:8080/boot/vmlinuz ip=dhcp url=http://192.168.1.70:8080/iso/ubuntu-live-server.iso
initrd http://192.168.1.70:8080/boot/initrd
boot
```

Tiny PXE Server は PXE/ProxyDHCP と初期ブートローダーの TFTP 配布を担い、iPXE 起動後は nginx の HTTP URL を用いる。Ubuntu インストーラはカーネル引数の `url=` から ISO を取得する。

使用する管理 PC の IP は各自の LAN 設定に合わせて変更する。Docker 内の `localhost` や `host.docker.internal` を PXE クライアント向けの URL に指定しない。

## 手順（再現のための整理）

1. `.env.example` を `.env` にコピーし、ISO の参照先を設定する。
2. `docker compose run --build --rm image-preparer prepare` で ISO・kernel・initrd を準備する。
3. `docker compose run --rm image-preparer status` で準備状態を確認する。
4. `docker compose up -d files` で nginx 配信を開始する。
5. `assets/boot.ipxe` を配置し、LAN 上から `http://<管理PCのIP>:8080/boot.ipxe` にアクセスできることを確認する。
6. Tiny PXE Server で ProxyDHCP/TFTP と適切な iPXE ブートファイルを設定し、起動する。必要に応じ Windows Firewall の設定を確認する。
7. 別 PC をネットワークブートし、Tiny PXE Server 側のログ、iPXE 画面、HTTP ファイル取得を順に確認する。

これは再現用の手順案であり、実際のオペレーションの全ステップを記録したものではない。また、現状の Compose に残っている `pixiecore` サービスは、この Windows 検証では使わない。

## 実機検証結果

- **到達済み:** Tiny PXE Server を使ったネットワークブートにより、Ubuntu ISO の HTTP ダウンロードまで進行。
- **未完了:** インストーラ起動の完走・自動インストール・OS インストールの成功。
- **発生したエラー:** `No space left`。ISO ダウンロード過程またはその後の一時領域確保で発生した可能性があるが、正確な発生箇所と不足した領域は未調査。
- **未確認:** 対象 PC の搭載 RAM、実際に利用した ISO の版・サイズ、iPXE バイナリの個別バージョンと対象 PC のファームウェア起動モード、起動引数の最終値、Tiny PXE Server の最終設定、Windows Firewall 設定。

今回の結果から、Windows ネイティブの PXE サーバーと Docker Desktop 上の nginx を組み合わせて ISO ダウンロード段階まで到達できることを確認した。ただし、Docker Desktop 上で pixiecore 自体が使えないと一般化するものではない。

## 今後の課題（本記録では対処しない）

- `No space left` の発生元と必要な RAM/一時領域の調査
- iPXE ブートローダーの起動モード別選択と Tiny PXE Server の最終設定値の固定（UEFI 候補の実機検証を含む）
- `boot.ipxe` の Git 管理と管理 PC の IP を埋め込まない生成方法の検討
- Windows ネイティブの PXE サーバーの起動・停止・配布物管理の自動化
- インストーラ完走、および既存 autoinstall 構成との統合検証
