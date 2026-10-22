# Provider artwork

Provider icons are used solely to identify the corresponding services. They remain the property of their respective owners, are not covered by this project's MIT license, and do not imply affiliation or endorsement. Artwork is bundled locally; the app does not contact these sites to load icons.

Retrieved 2026-10-22:

| Asset | Owner | Official source | Usage |
| --- | --- | --- | --- |
| `openai.png` | OpenAI | [OpenAI Developers favicon](https://developers.openai.com/favicon.png) | OpenAI provider identification |
| `claude.svg`, `claude.png` | Anthropic | [Claude favicon](https://claude.ai/favicon.svg) | Claude starburst; PNG rendered from the original SVG using macOS `sips`, with proportions and colors preserved |
| `gemini.png` | Google | [Gemini site favicon](https://www.gstatic.com/lamda/images/gemini_sparkle_4g_512_lt_f94943af3be039176192d.png) linked by [Gemini](https://gemini.google.com/) | Gemini / Gemini CLI / AI Studio provider identification |

Brand information: [OpenAI](https://openai.com/brand/), [Anthropic](https://www.anthropic.com/legal/trademark-guidelines), [Google](https://about.google/brand-resource-center/).

Additional artwork is taken from the official CLIProxy management UI, pinned at [714de0760a3ce86094b178fb46f834d34bc4a2a5](https://github.com/router-for-me/Cli-Proxy-API-Management-Center/tree/714de0760a3ce86094b178fb46f834d34bc4a2a5/src/assets/icons). Original SVGs are bundled beside PNG renderings. The upstream MIT license (copyright 2026 Router-For.ME) is retained in `Sources/CliProxyQuota/Resources/ProviderIcons/UPSTREAM_LICENSE.txt`; brand rights remain with their respective owners.

| Assets | Provider / owner |
| --- | --- |
| `codex` | Codex / OpenAI |
| `antigravity`, `vertex` | Antigravity, Vertex AI / Google |
| `kimi-dark`, `kimi-light` | Kimi / Moonshot AI |
| `grok`, `grok-dark` | Grok / xAI |
| `meta` | Meta / Muse |
| `devin`, `devin-dark` | Devin / Cognition |
| `qwen` | Qwen / Alibaba |
| `iflow` | iFlow |
| `deepseek` | DeepSeek |
| `glm` | GLM / Zhipu AI (Z.ai) |
| `minimax` | MiniMax |

`openrouter.png` comes directly from the [OpenRouter site glyph](https://openrouter.ai/favicon/glyph.png). These assets identify compatible or legacy providers as well as current native integrations; an icon does not imply quota API support. `scripts/render-provider-icons.py` reproduces PNGs using macOS `sips`, resolving default SVG `currentColor` to black and setting explicit pixel dimensions without changing the original SVGs.
