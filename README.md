<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="知了图标">
</p>

<h1 align="center">知了 · Cicada</h1>

<p align="center">
  任何会议、任何直播，没有语言障碍。<br>
  听得懂，说得出，记得住。Mac、Windows、Linux 和 Android 上的实时纪要、双语文字记录、字幕与同声传译。
</p>

<p align="center">
  <a href="https://cicada.indaloop.app"><img src="https://img.shields.io/badge/官网-cicada.indaloop.app-E8552B?style=for-the-badge" alt="官网 cicada.indaloop.app" height="36"></a>
  &nbsp;
  <a href="https://cicada.indaloop.app/download/"><img src="https://img.shields.io/badge/下载-Mac%20·%20Windows%20·%20Linux%20·%20Android-15171C?style=for-the-badge" alt="下载 Mac、Windows、Linux、Android 版" height="36"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.4%2B-black" alt="macOS 14.4+">
  <img src="https://img.shields.io/badge/Windows-10%202004%2B-black" alt="Windows 10 2004+">
  <img src="https://img.shields.io/badge/Ubuntu-22.04%2B-black" alt="Ubuntu 22.04+">
  <img src="https://img.shields.io/badge/Android-10%2B-black" alt="Android 10+">
  <img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="Apache-2.0">
</p>

<p align="center"><a href="README.md">简体中文</a> · <a href="README.en.md">English</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a></p>

开 Zoom、Teams、飞书、腾讯会议，或者听 X Spaces、YouTube 直播，知了都能实时给双语字幕、边听边写结构化纪要。轮到你发言时，按住说话键（Mac 右 `⌥`，Windows 右 `Ctrl`）开口，对方直接在会里听到翻译好的语音。知了直接读系统声音，不往会里塞机器人，对方完全无感。在 Apple 芯片的 Mac 上全部本机识别，声音不出电脑。

**能在哪里用**：电脑能放出声音的都行。腾讯会议、飞书、钉钉、企业微信、Zoom、Teams、Google Meet、Webex、Discord、Telegram 语音，X Spaces、YouTube、Twitch、B 站直播和播客，网页版也行。手机上会议和通话 app 的声音系统不让录，开外放用“面对面”就行。

<p align="center">
  <img src="docs/demo.gif" width="800" alt="YouTube 播着 Bloomberg 英文直播，右边是知了实时整理的中文纪要、议题与鱼骨图，底部是双语字幕">
</p>

## 平台

| 平台 | 系统要求 | 说明 |
|---|---|---|
| Mac | macOS 14.4+，Apple 芯片 / Intel | 功能最全。Apple 芯片本机识别（不填 key 也能用），Intel 版需配置云端语音理解（默认 Ming，也可接兼容接口） |
| Windows | Windows 10 2004+，x64 / ARM64 | 需 Ling、OpenRouter、ZenMux 等 AI 服务 key，见 [windows/](windows/README.md) |
| Linux | Ubuntu 22.04 / 24.04 桌面版 | 需 AI 服务 key；纪要窗会被屏幕共享看到，见 [linux/](linux/README.md) |
| Android | Android 10+ | 需 AI 服务 key；视频与直播字幕、面对面互译，见 [android/](android/README.md) |

安装包都在 [官网下载页](https://cicada.indaloop.app/download/) 和 [Releases](https://github.com/wquguru/cicada/releases)。四个平台共用版本号和会议记录格式，下面以 Mac 版为例说明功能。

## 主要功能

### 实时纪要与双语文字记录

纪要窗口边听边整理总结、议题要点、结论、待办、鱼骨图和人名术语表，点结论或待办就能跳回原话。按 `⌘F` 搜索时，连同识别错的写法也能一起搜出来。

接了 AI 服务后，听错的人名和术语会当场改对：同音错字直接改，生僻名字先问你一次，答“对”以后自动改。常用写法可以贴进设置的“词表”里。会后也能选“改这句…”批量改整场同样的错词，随时可撤销。

### 实时字幕与语言识别

对方开口几秒就能自动认出语言并翻成你的系统语言，按 `⌃⌥S` 切换显示方式。字幕条只在有人说话时出现，鼠标划过自动变透明，不挡按钮。Apple 芯片的 macOS 26 上还会在本机重听校准，15 到 30 秒后修掉错字和断句漏字。

### 线下与混合会议

在会议室里点“打开麦克风”，就能听桌边的人说话。线上线下混合开会也是这一个按钮：电脑声音记为“线上”，麦克风记为“现场”，合在同一份记录里（macOS 14 和 15 打开麦克风时只听桌边）。外放声音传进麦克风时会自动避让并去重，不会记两遍；戴耳机时两边同时说也能记下。Windows 和 Linux 规则相同。

### 同声传译

按住右 `⌥` 说话，对方就能在会议软件里听到翻译后的语音。打开功能时会自动把系统麦克风切到一键下载安装的虚拟驱动 BlackHole 2ch。填了 Ling API key 可以用自然人声，或用 8 到 30 秒录音克隆你自己的声音；不填也能用 Mac 自带语音。

<p align="center">
  <img src="docs/interpreting.png" width="640" alt="同声传译设置页，包含按住右 Option 键说话、目标语言、Ming 声音试听与本机声音选择">
</p>

### 会议记录

双语记录、纪要和原始录音都存在本机。点任意一句就能从那儿回放录音，本机声纹模型会自动区分不同说话人（填了 Ling key 会填上名字），认错了随时改名或合并。会后支持补生成纪要，或导出 Markdown、Word 和 SRT 字幕。点“分享…”可以把纪要（也可以带上双语全文）发成一个链接，能设有效期和密码，链接和密码一键一起复制；上传前会先检查有没有密钥、未公开的公司信息这类敏感内容，有就先拦下。你也可以通过“文件 › 导入录音或视频…”把本地音视频快速转成双语记录。目前记录里的你只包含按住说话键说的话，会上直接开口的部分见[路线图](#路线图)。

<p align="center">
  <img src="docs/records.png" width="640" alt="会议记录窗口，显示识别出的说话人名字和逐句英中双语文字记录">
</p>

## 隐私与权限

**Apple 芯片的 Mac**：声音采集、语言识别、语音识别和会议录音全部在本机完成。离开电脑的只有识别出的文字（去翻译和写纪要），以及配置了云端语音理解后用同传时你说的那几句语音（如果语音模型下载慢你点了“先用 Ling 听”，或你在“设置 › AI 服务 › 按功能换服务”里把语音识别改成了别的机器上的自建服务，会议声音也会发给对应服务；自建服务就在这台 Mac 上时不出本机）。不填 API key 时，实时字幕、翻译、会议记录和同传都能免费用。实时纪要和一步语音翻译需要配置相应的 AI 服务，声音克隆需要你自己的 Ling（蚂蚁集团大模型服务）API key，一小时会大约花 0.15 到 1 元人民币，Ling 每月送 10 元额度，够用 10 到 50 小时。

**Intel 版 Mac、Windows、Linux、Android**：语音识别在云端完成，说话声音会分段发给 Ling 的 Ming 或你选的 OpenRouter、ZenMux 等服务（Intel 版 Mac 也可以单独接兼容的语音理解接口），所以必须填 AI 服务 key。录音和会议记录依然只存在本机。

Mac 版只在用到某项功能时才要权限，拒绝后其他功能照常：

| 权限 | 用途 | 不给的话 |
|---|---|---|
| 录制系统声音（屏幕与系统录音） | 听系统播放的声音出字幕，不录屏幕 | 字幕和纪要都用不了 |
| 麦克风 | 按住说话键做同传；点“打开麦克风”听会议室 | 不能说话翻译，不能听会议室 |
| 输入监控 | 判断右 `⌥` 是否被按下（不拦截、不记别的键） | 设置里改成 `⌃`/`⌘` 组合键就不用这个权限 |
| 管理员密码 | 安装虚拟麦克风 BlackHole 2ch（只问一次） | 对方听不到同传，其余照常 |

- **联网透明**：只有翻译（`translate.googleapis.com`）、你配的 AI 服务（如 `api.ant-ling.com`）、下载苹果公证过的 BlackHole 驱动（会核对 SHA-256）和每天去 GitHub 检查更新会联网。没有统计、没有埋点，也没有我们自己的服务器。
- **数据存本机**：记录和录音存在 `~/Library/Application Support/LiveSubs`。Key 和声音样本只对当前系统账户可读，不进 Time Machine 和日志。
- **防录屏**：Mac 上共享屏幕、录屏和截图都拍不到纪要窗口，录演示时可手动打开“共享屏幕时让对方看到”。

## 用到的模型

以下为 Apple 芯片 Mac 的配置。用自建服务（“其他（兼容 OpenAI）”）时，可在“设置 › AI 服务”打开“语音和文字只发给你的服务”，完全不经过 Google。

| 功能 | 填了 Ling key | 不填 key / 退回 |
|---|---|---|
| 语音识别、语言识别 | Apple `SpeechAnalyzer` / `SpeechTranscriber`（本机）；macOS 14.4–15 为 `SFSpeechRecognizer`（本机，需开听写）；也可换成在这台 Mac 上跑的 Qwen3-ASR（见下） | 同左 |
| 整句翻译 | Ling `Ling-3.1-flash`（可在“设置 › AI 服务”改为 `Ling-3.0-flash`） | Google 翻译 → Apple `Translation`（本机，仅 macOS 26） |
| 正在说的半句话翻译 | Google 翻译 | 只显示原文，说完换整句翻译 |
| 实时纪要、会后完整版 | Ling `Ling-3.1-flash` | 不可用 |
| 检查 key 是否有效 | Ling `Ling-3.0-tiny`（1 token） | — |
| 同传：听懂并翻译 | Ming `Ming-3.0-audio-flash`（一步完成） | Apple 本机识别 + 上述翻译链 |
| 同传：发声与声音克隆 | Ming `Ming-3.0-tts-0.5B` | Mac 自带语音（`AVSpeechSynthesizer`），无克隆 |
| 说话人识别 | WeSpeaker ResNet34-LM（随 app 附带，本机 Core ML 运行） | 同左 |

Mac 上的翻译和纪要、语音理解还可以各自接一个 OpenAI 兼容接口，不跟主服务走：在“设置 › AI 服务”页底部的“按功能换服务”里，把对应一行从“同上”换成“兼容接口”，填入地址（如 `https://api.openai.com/v1`）、模型和 key，再点“保存并检查”。模型名可以手填，也可以先填地址和 key，点模型旁边的“读取模型”从列表里选。检查通过后这一行收成一句话：地址、模型和翻一句要多久；出问题时它会自己展开，写明坏在哪。“翻译和纪要”接管会议字幕和导入录音的整句翻译、实时和会后纪要、说话人姓名猜测；检查会验证翻译和 JSON 能力，不支持 JSON 的接口仍能翻译，但不能写纪要。半句话仍走 Google → Apple，接口不可用时整句也按这个顺序退回。原文的语音识别，以及 Ming 的语音理解、同传声音和声音克隆仍用主服务。主服务选“其他（兼容 OpenAI）”时，翻译和纪要已经在上面填了，这一行就不再重复出现。纪要窗口或菜单栏提示翻译和纪要的接口有问题时，点“配置 AI 服务”会直接翻到这里。

“语音理解”默认同上（Ling 用 `Ming-3.0-audio-flash`）；换成兼容接口时，除了地址、模型和 key，还要按服务要求选 OpenAI（`input_audio`）或 Ming 兼容（`audio_url`）格式，地址填 Ling 的 `api.ant-ling.com` 时会自动选 Ming 兼容。翻译和纪要已经接了兼容接口时，点“用翻译和纪要的地址和 key”就能把同一个地址和 key 带过来，再从读到的列表里挑一个音频模型。“保存并检查”会用一秒实际音频验证。它用于按住说话的语音理解，以及 Intel Mac 或手动选择的云端识别；Apple 芯片 Mac 默认仍在本机识别。翻译和纪要、语音理解的 key 各存一份（0600 权限，只在本机），带过来的 key 也是另存一份、不显示；声音合成和克隆仍使用原来的 Ming TTS 配置。

“语音识别”在 Apple 芯片的 Mac 上默认用本机识别；想要更准的中文、方言和中英混说，可以换成“自建服务”。推荐在这台 Mac 上用 [mlx-audio](https://github.com/Blaizzy/mlx-audio) 跑 Qwen3-ASR，会议的声音同样不出这台 Mac，不管主服务选的是哪家。在终端里装一次、启动它：

```bash
uv tool install --upgrade "mlx-audio[stt,server]"   # 没有 uv 时：pip3 install -U "mlx-audio[stt,server]"（要 Python 3.10+）
mlx_audio.server --port 8000
```

然后在“按功能换服务 › 语音识别”选“自建服务”：地址 `http://localhost:8000/v1` 和模型 `mlx-community/Qwen3-ASR-1.7B-8bit` 已经填好，点“保存并检查”，第一次会下载约 2.5 GB 的模型，要等几分钟。想省内存可以换成 `mlx-community/Qwen3-ASR-0.6B-8bit`（约 1 GB）。在 M4 Pro 上实测，模型加载好以后一段 9 秒的话约 0.5 秒识别完。下一场会议起由它识别，服务没开或连不上时自动换回本机识别。第一次检查说找不到模型，多半是下载没成功，看看启动服务的终端窗口里的报错；经代理下载大文件失败时，启动前加上 `HF_HUB_DISABLE_XET=1`。任何支持 `/audio/transcriptions` 的服务都能接（比如 vLLM 跑的 Qwen3-ASR、Whisper），局域网里的地址可以用 http。MLX 只能跑在 Apple 芯片上：Intel 版 Mac 可以填局域网里另一台 Apple 芯片 Mac 的地址（那边启动时加 `--host 0.0.0.0`）。以前在“其他（兼容 OpenAI）”里设的语音识别会自动搬到这里，步骤也写在网站的[设置页](https://cicada.indaloop.app/start/#local-asr)。

## 配置 Ling API key

1. 去 [Ling 开放平台](https://chat.ant-ling.com/platform/api) 注册登录，创建令牌，复制 `sk-` 开头的 key。
2. 打开知了“设置 › AI 服务”（或纪要窗口顶部提示框），粘贴保存即可。

**注册不了 Ling？** 在“设置 › AI 服务”右上角（或引导页点“用不了 Ling？”）可以换成 OpenRouter、ZenMux、OpenAI，或任何 OpenAI 兼容服务（包括 Ollama、vLLM、SGLang 等本机或局域网服务；引导里选“兼容接口”，填地址、模型和 key，本机和局域网里的服务可不填 key）。实时纪要和整句翻译都能用，OpenRouter 和 ZenMux 还能用 Gemini 的自然人声做同传；声音克隆只有 Ling 支持，Mac 的一步语音翻译也可以单独接兼容的语音理解接口。Mac 的翻译和纪要、语音识别、语音理解还能在“按功能换服务”里各接各的服务，主服务是哪家都行。Windows、Linux、Android 换用其他服务时，“听对方”也交给该服务，字幕比 Ling 晚 1–2 秒。连不上时设置里会直接提示是 key、模型还是代理问题（代理说明见[设置页](https://cicada.indaloop.app/start/#proxy)）。

## 系统要求与安装

安装包都在 [Releases 页面](https://github.com/wquguru/cicada/releases/latest) 或 [官网](https://cicada.indaloop.app)，可用 Releases 里的 `checksums.txt` 核对 SHA-256。有问题可以去 X 找作者 [@wquguru](https://x.com/wquguru)。

### Mac

需要 macOS 14.4+（支持 Apple 芯片与 Intel）。Apple 芯片在 macOS 14.4–15 上要先去系统设置 › 键盘里打开“听写”并添加要听的语言；macOS 26 直接用新本机模型，不用开听写；Intel 版走云端语音理解识别（默认 Ming，要配 Ling key；也可以接兼容接口）。

下载 `Cicada-<版本>-macOS-AppleSilicon.dmg` 或 `Cicada-<版本>-macOS-Intel.dmg`，拖进应用程序文件夹（可用 `shasum -a 256 Cicada-*.dmg` 校验）。目前还没有苹果公证，第一次打开被拦时，去系统设置 › 隐私与安全性里点仍要打开。跟着首次引导开权限、试听示例会议即可。

<p align="center">
  <img src="docs/onboarding.png" width="640" alt="首次引导第二步，播放双人示例会议并实时显示双语字幕">
</p>

### Windows

需要 Windows 10 2004+（x64 或骁龙 ARM64）。下载安装包双击即装，不用管理员权限。SmartScreen 拦下时点更多信息 › 仍要运行。用同传时引导会带你装免费的 VB-Cable 虚拟麦克风。

### Linux

需要 Ubuntu 22.04 或 24.04 桌面版（x86_64 或 arm64）。下载 `Cicada-<版本>-Linux.tar.gz`，终端运行 `tar xzf Cicada-<版本>-Linux.tar.gz && cicada-linux/install.sh`。同传会自动建一个“知了 麦克风”，免装驱动。Linux 窗口无法避开屏幕共享，纪要窗会标明“共享屏幕时此窗口可见”。想打开“设置 › 通用 › 保存会议录音”，需先装系统第三方媒体格式（如 `ubuntu-restricted-extras`）提供 AAC 编码器。打开“设置 › 词表 › 会中改正听错的词”后每句会多发一次文字请求。

### Android

需要 Android 10+。下载 `Cicada-<版本>-Android.apk` 安装；Android 15 起第一次开悬浮字幕要先在应用信息里允许受限制的设置。同样自带本机声纹区分说话人、支持“正在听”时实时改错词。微信通话和会议 app 的声音系统不让内录，开外放、改选“面对面”就行。

## 路线图

按先后排，想要哪一项欢迎提 Issue。细节见 [docs/ROADMAP.zh-CN.md](docs/ROADMAP.zh-CN.md)。

- **记录我的发言**：开会时持续听麦克风并消除回声，把你直接开口说的话也记进记录和纪要。
- **正式签名与公证**：Mac 和 Windows 安装包加上正式签名与公证，不再弹窗拦截，AI key 放回系统钥匙串。
- **声纹识别**：在本机记住常开会同事的声音，下次自动认出。
- **不用 key 也有纪要**：在支持的 Mac 上用 Apple 本机模型整理纪要。
- **Android 上架应用商店**：不用再手动装 APK。
- **iPhone 和 iPad**：先做听会议室、面对面互译和会议记录。

## 卸载

退出知了，从应用程序文件夹拖进废纸篓即可。会议记录和录音在 `~/Library/Application Support/LiveSubs`，不用可手动删。清除设置运行：

```bash
defaults delete com.wquguru.cicada
```

## 开发

Mac 版只需安装 Xcode Command Line Tools（`xcode-select --install`），无第三方依赖。macOS 27 上若报 `SwiftUIMacros` 缺失，安装完整 Xcode 并运行 `sudo xcode-select -s /Applications/Xcode.app`。其他平台构建见 [windows/README.md](windows/README.md)、[linux/README.md](linux/README.md)、[android/README.md](android/README.md)。

```bash
scripts/build.sh            # 编译开发版 → build/Cicada.app（名为 Cicada Dev，可与正式版同时运行）
open build/Cicada.app
scripts/package.sh          # 打包正式版 DMG、zip 和 SHA-256 校验值
```

代码架构见 [AGENTS.md](AGENTS.md)，官网源码在 `site/`（由 `scripts/site.py` 生成），更新记录见 [CHANGELOG.md](CHANGELOG.md) 或[官网更新日志](https://cicada.indaloop.app/changelog/)。

## 开源协议

本项目采用 [Apache-2.0](LICENSE) 协议开源。虚拟麦克风驱动 BlackHole 2ch 采用 GPL 协议，不打包在安装包内，点安装时从其官方地址下载。随附的声纹模型是 [WeSpeaker](https://github.com/wenet-e2e/wespeaker) 在 VoxCeleb 上训练的 ResNet34-LM（CC BY 4.0 协议），由 `scripts/convert-voiceprint.py` 转为 Core ML。
