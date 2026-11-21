# ops-pxe-provisioner-container

Windows + Docker Desktop 上で Pixiecore の PXE/ProxyDHCP が利用できるかを確認するための最小 Compose 構成です。Linux Docker Engine でも利用できます。

**現時点では PoC です。** Docker Desktop の host networking は Linux ホストと同等ではなく、物理 LAN からの DHCP/PXE ブロードキャスト到達と応答は実機検証が必要です。

## 実機検証記録

Windows ネイティブの Tiny PXE Server と Docker Desktop 上の nginx を組み合わせ、Ubuntu ISO の HTTP ダウンロードまで到達しました。詳細な設定・観測結果・未解決事項は [docs/windows-tiny-pxe-poc.md](docs/windows-tiny-pxe-poc.md) を参照してください。

## サービス

- `image-preparer`：Ubuntu Server の ISO を取得・SHA256 検証し、`casper/vmlinuz` と `casper/initrd` を抽出する一時実行ジョブ。通常起動されません。
- `files`：nginx。ホスト TCP `8080`（変更可）で `assets/` を HTTP 配信します。
- `pixiecore`：`network_mode: host` の PXE/ProxyDHCP サーバ。明示起動のみ。
- `assets/`：ISO と抽出済みファイル。Git 管理対象外で、コンテナ間で共有します。

`image-preparer` と `files` は Windows/Linux 共通で動作する想定です。Pixiecore の Windows 動作は別途実機検証が必要です。

## 初期準備

Windows PowerShell:

```powershell
git clone https://github.com/js4000all/ops-pxe-provisioner-container.git
cd ops-pxe-provisioner-container
Copy-Item .env.example .env
```

Linux では `cp .env.example .env` を使用してください。

`.env` の `ISO_URL` に公式 Ubuntu Server ISO の URL を設定し、`KERNEL_CMDLINE` 内の `192.168.1.10` を管理 PC の実際の LAN アドレスへ変更します。テンプレートの ISO バージョンは例です。取得先に存在するバージョンを指定してください。

`ISO_SHA256` は任意です。空なら `ISO_URL` と同じ配布ディレクトリの `SHA256SUMS` を HTTPS で取得して検証します。署名確認まで必要な環境では、信頼できる経路で得たハッシュを `ISO_SHA256` に固定してください。

## ISO を準備

```shell
docker compose run --build --rm image-preparer prepare
docker compose run --rm image-preparer status
```

既存の ISO と抽出ファイルが対象ハッシュと一致すれば `prepare` は再利用します。ISO のみ検証済みで抽出ファイルが欠けている場合、再ダウンロードせず抽出します。

明示的に再取得する場合:

```shell
docker compose run --rm image-preparer refresh
```

出力:

```text
assets/
├── iso/
│   └── ubuntu-live-server.iso
└── boot/
    ├── vmlinuz
    ├── initrd
    └── source.sha256
```

`status` は ISO の SHA256 と抽出済みファイルの存在および抽出元ハッシュの一致を検査します。**抽出ファイル自体の内容ハッシュまでは再検証しません。** 検証失敗時は非ゼロ終了します。

ダウンロード・検証・抽出の間は一時ディレクトリを使うため、それらの途中で失敗しても公開済みファイルは置き換えません。ただし最終配置の複数ファイル更新は完全にはアトミックではありません。**`refresh` の前に Pixiecore を停止し、進行中の PXE ブートがない状態で実行してください。** 同時に複数の prepare/refresh を実行しないでください。

## ファイル配信・PXE 動作確認

```shell
docker compose config -q
docker compose up -d files
docker compose --profile pxe up -d pixiecore
docker compose logs -f pixiecore
```

PXE クライアントから `http://<管理PCのLAN IP>:8080/iso/ubuntu-live-server.iso` に到達できる必要があります。Windows Firewall 等も確認してください。`localhost` や `host.docker.internal` は PXE クライアント用 URL に使いません。

Windows + Docker Desktop 4.34 以降では host networking を有効にしてください。Docker Desktop の host networking はレイヤー 4 の機能であり、物理 NIC のブロードキャストをコンテナで扱える保証はありません。LAN 側の DHCP/PXE 応答は実機で検証してください。既存 DHCP サーバを置き換えるものではなく、Pixiecore には `--dhcp-no-bind` を渡しています。

停止:

```shell
docker compose --profile pxe down
```

現段階では既存の Ansible / WoL / CLI / Web UI は含みません。

参考: [Pixiecore](https://github.com/danderson/netboot/tree/main/pixiecore) / [Docker host networking](https://docs.docker.com/engine/network/drivers/host/)
