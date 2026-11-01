[English](README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [日本語](README.ja.md) · **中文** · [हिन्दी](README.hi.md)

# alto

为 [monome norns](https://monome.org/docs/norns/) 设计的三层复音合成器，几乎只需看着屏幕就能演奏：每一页都是声音的图像，而不是一串数字。

![alto 的全部八页](docs/sheet.png)

- 每个音符叠加 **3 个声部**，每个声部都有独立的引擎（18 种可选）、音量、八度、音准和 LFO
- 带包络、键盘跟随和 K3「扫频」的**滤波器**
- **琶音器**（4 种类型、4 种速度、门限可至连奏）和**和弦模式**（12 种和弦）
- **3 环复节奏音序器**：每个声部一个环，各自拥有独立的长度和方向，并带有生成式旋律
- **效果**：比特粉碎、失真、环形调制、混响，以及从干声到颗粒云再到 shimmer 的颗粒「空间」效果
- **10 个出厂预设 + 10 个用户槽位**
- 支持任意已连接设备的 MIDI 音符输入（端口 1–4）

## 需求

- norns（任意型号：shield、标准版或 fates）
- 用于弹奏音符的 MIDI 键盘；没有键盘时，alto 可通过音序器发声

## 安装

在 maiden 中输入：

```
;install https://github.com/buenosairesfront/alto
```

然后**重启 norns**（SYSTEM > RESTART）以编译新引擎 `UmaFlagship`，再从 SELECT 加载 **alto**。

## 操作

所有页面通用：**K2 + E1** 切换页面，**K1** 开关保持（音符锁定）。按任意键可跳过开场动画。

### 1 · 演奏

![演奏](docs/1_play.png)

| 操作 | 功能 |
|---|---|
| E1 | 空间：干声 → 颗粒云 → shimmer |
| E2 | 滤波器共振 |
| E3 | 滤波器截止频率 |
| K2 | 琶音器 开/关 |
| K2 + E2 / E3 | 琶音类型 / 琶音速度 |
| K2 + E1（琶音菜单打开时） | 琶音门限长度（最大 = 连奏） |
| K3 | 滤波器扫频（按住 = 延音） |
| 按住 K3 0.5 秒 | 和弦模式 开/关 |

### 2 · 声部

![声部](docs/2_voices.png)

| 操作 | 功能 |
|---|---|
| E1 | 选择声部 |
| E2 | 音量 |
| E3 | 引擎 |
| K2 | 声部 开/关 |
| K3 | LFO 开/关 |
| K3 + E1 / E2 / E3 | LFO 速度 / 波形 / 深度 |

引擎：sine, square, tri, fm, phys, perc, pad, pluck, gendy, formant,
pmosc, blip, lfcub, syncsaw, logistic, pink, blit, vosim

### 3 · 调音

![调音](docs/3_tune.png)

| 操作 | 功能 |
|---|---|
| E1 | 选择声部 |
| E2 / E3 | 半音 / 音分 |
| K2 / K3 | 半音 / 音分 归零 |

### 4 · adsr

![adsr](docs/4_adsr.png)

| 操作 | 功能 |
|---|---|
| E2 | 选择节点 |
| E3 | 移动节点 |
| K3 | 包络同时控制滤波器 |

### 5 · 和弦

![和弦](docs/5_chord.png)

**E2** 选择和弦模式使用的和弦：maj, min, sus2, sus4, dim, aug,
maj7, min7, dom7, add9, maj9, min9

### 6 · 音序器

![音序器](docs/6_sequencer.png)

三个椭圆环：外环 **A**、中环 **B**、内环 **C**。每个环只演奏自己的声部，步数也各自独立，因此指针会逐渐错开（复节奏）。每一步随音高向外延伸；底线上的点表示休止。时钟以十六分音符推进，并跟随 norns 时钟。

| 操作 | 功能 |
|---|---|
| K3 | 播放 / 停止（全部环） |
| K3 + E1 | 选择环 |
| K3 + E2 | 方向：正向、反向、往返、随机 |
| K3 + E3 | 所选环 开/关 |
| K2 | 录入到所选环（若已停止则开始播放） |
| E1 | 步数 |
| E2 | 选择步 |
| E3 | 该步音高（最小 = 休止） |
| K2 + E3 | 所选步的时值 |
| K2 + E2 | 所有步的时值（最大 = 连音） |
| K1 + E3 | 生成式旋律（向右 = 新旋律，向左 = 返回上一条） |
| 按住 K1 0.5 秒 | 清除所选步 |

### 7 · 效果

![效果](docs/7_fx.png)

| 操作 | 功能 |
|---|---|
| E1 | 选择效果：crush, dist, ring, verb |
| E2 / E3 | 该效果的两个参数 |
| K2 | 效果 开/关（保留参数值） |

### 8 · 预设

![预设](docs/8_presets.png)

| 操作 | 功能 |
|---|---|
| E2 / E3 | 选择槽位 |
| K2 | 读取 / 保存（用 K2 确认） |
| K3 | 退出 |

出厂预设：glass keys, analog brass, deep sub, acid line, stellar pad,
vox choir, klavinsky, chaos drone, metal bell, perc keys。
用户预设保存在 `~/dust/data/alto/user_presets.tab`。

## 致谢

由 [Buenos Aires Front](https://github.com/buenosairesfront) / U-MA 制作。
MIT 许可证。
