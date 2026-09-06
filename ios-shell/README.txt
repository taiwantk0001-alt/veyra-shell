把 WebView 壳源码放在本目录 ShellApp / ShellApp.xcodeproj。

生成 base.ipa（只需做一次，且必须在 Mac 上）：

  cd 项目根目录
  bash tools/build-ios-shell.sh

成功后会得到：

  ios-shell/base.ipa

说明：
- 服务器（Linux/Windows）无法编译 iOS 程序，只能注入网页到已有壳里
- base.ipa 未签名即可；下载生成的业务 IPA 后，用「轻松签」签名再分发
- 壳内通过本地 www/index.html 打开 APP；打包时会替换 www 目录
