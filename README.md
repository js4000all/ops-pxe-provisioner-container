# ops-pxe-provisioner-container

Windows + Docker Desktop 上で Pixiecore の PXE/ProxyDHCP が利用できるかを確認するための最小 Compose 構成です。Linux Docker Engine でも利用できます。

**現時点では PoC です。** Docker Desktop の host networking は Linux ホストと同等ではなく、物理 LAN からの DHCP/PXE ブロードキャスト到達と応答は実機検証が必要です。動作確認済みとは扱いません。

## 構成

- `files`: nginx。ホストの TCP `8080` (変更可) で `assets/` を HTTP 配信します。
- `pixiecore`: `network_mode: host` で動かす ProxyDHCP/PXE サーバ。`pxe` profile を付け、通常の `up` では起動させません。
- `assets/`: Git 管理しないカーネル、initrd、ISO、autoinstall 関連ファイルの置き場所。

既存 LAN の DHCP サーバを置き換える構成ではありません。Pixiecore の `--dhcp-no-bind` を使用し、通常の DHCP サーバとの共存を試みます。

## 前提条件

- Windows 11 + Docker Desktop 4.34 以降（Linux コンテナモード）。Docker Desktop の **Settings → Resources → Network → Enable host networking** を有効化。設定名や表示位置は Docker Desktop のバージョンにより異なる場合があります。
- または Linux + Docker Engine / Compose plugin。
- 対象 PXE クライアントと管理 PC が同一ブロードキャストドメインにいること。Wi-Fi のクライアント分離や VLAN に注意してください。
- 既存の DHCP サーバはそのまま利用します。検証時には Windows Defender Firewall 等の影響も確認してください。

## 準備

リポジトリ直下で `.env.example` を `.env` にコピーします。

PowerShell:

```powershell
Copy-Item .env.example .env
New-Item -ItemType Directory -Force assets/boot, assets/iso
```

対象ディストリビューションの PXE 用 kernel と initrd を以下に配置します。名称は固定です。

```text
assets/
├── boot/
│   ├── vmlinuz
│   └── initrd
└── iso/
    └── ubuntu-live-server.iso  # 必要な場合。ファイル名は任意
```

Ubuntu Server の live installer を使う場合、対応する ISO 内の `casper/vmlinuz` と `casper/initrd` を抽出します。ISO を `assets/iso/` に置き、`.env` の `KERNEL_CMDLINE` を変更してください。例えば管理 PC の LAN IP が `192.168.1.10` なら:

```dotenv
KERNEL_CMDLINE=ip=dhcp url=http://192.168.1.10:8080/iso/ubuntu-live-server.iso
```

ISO ファイル名、カーネル起動引数、インストーラへの追加設定は実際の ISO と既存プロビジョニング環境に合わせて調整します。**127.0.0.1、localhost、host.docker.internal は PXE クライアントから参照する URL として使わないでください。**

## 起動と検証

まず静的ファイル配信のみ起動します。

```powershell
docker compose config -q
docker compose up -d files
```

対象ネットワーク上の別端末から `http://<管理PCのLAN IP>:8080/iso/<ISOファイル名>` を取得できることを確認してください。PowerShell では、管理 PC 自身から次のように確認できます。

```powershell
Invoke-WebRequest http://localhost:8080/boot/vmlinuz -Method Head
```

HTTP が確認できたら PXE サービスを起動します（ファイルを用意してから実行）。

```powershell
docker compose --profile pxe up -d pixiecore
docker compose logs -f pixiecore
```

対象 PC でネットワークブートを実行し、ProxyDHCP 応答、iPXE への移行、kernel/initrd の取得、ISO 取得を段階的に確認します。失敗した場合は **Windows ホスト上のパケットキャプチャ** と Pixiecore ログを照合し、ブロードキャストが届かないのか、応答が返らないのかを切り分けます。

停止:

```powershell
docker compose --profile pxe down
```

## 制約と次段階

Docker Desktop の host networking は TCP/UDP に対するレイヤー 4 の機能です。物理 NIC とコンテナが同一の L2 ネットワークに参加するわけではなく、PXE/ProxyDHCP で必要なブロードキャスト挙動は保証されません。Windows で起動できたことだけでは成功と判定しません。

この PoC は既存のプロビジョニング CLI、Ansible、WoL、Web UI を移植していません。まず Pixiecore の動作可否を確定し、問題がある場合のみ Windows ネイティブの PXE 機能や別の Linux ネットワーク実行環境を検討します。

参考:
- [Pixiecore (upstream)](https://github.com/danderson/netboot/tree/main/pixiecore)
- [Docker host network driver](https://docs.docker.com/engine/network/drivers/host/)
