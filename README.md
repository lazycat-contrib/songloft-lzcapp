# songloft-lzcapp

每天 23:00 UTC 检查 `songloft/songloft` 的稳定版本，直接使用上游镜像，自动构建 `<package-id>-v<version>.lpk` GitHub Release，并只提交喵喵私有商店。

需要显式配置 GitHub Secrets：`APPSTORE_URL`、`APPSTORE_TOKEN`，可选 `APP_ID` 和 `PRIVATE_STORE_GROUP_CODES`。组织 Secret 必须授权本仓库。
