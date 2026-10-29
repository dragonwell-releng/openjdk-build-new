# Dragonwell 25 RISC-V / Anolis 23.5

在 x86_64 Linux 上交叉编译，使用仓库正式的 `build-farm/make-adopt-build-farm.sh` 入口。
目标 sysroot 来自 Anolis 23.5 GA RISC-V DVD；交叉 GCC/binutils 由对应发行版 SRPM
及其补丁生成。C、C++、汇编和 libsleef 统一使用 `-march=rva23u64_zifencei -mabi=lp64d`。

| 输入 | 固定版本 |
| --- | --- |
| sysroot | AnolisOS-23.5-riscv64-dvd.iso，glibc 2.38-26.an23 |
| GCC | gcc-14.3.0-5.an23_rva23.src.rpm（包含发行版 RVA23 补丁） |
| binutils | binutils-2.42-4.an23_rva23.src.rpm |
| x86_64 Boot / Build JDK | OpenJDK 25.0.2 |

`inputs.sha256` 固定以上输入的 SHA-256。来源为
[Anolis GA DVD](https://mirrors.openanolis.cn/anolis/23.5/isos/GA/riscv64/) 和
[对应源码 RPM](https://mirrors.openanolis.cn/anolis/23.5/os/source/Packages/)。
DVD 中的 GCC 是 RISC-V 原生程序，不能直接在 x86_64 上运行，因此由发行版 SRPM 重建交叉工具链。

## 镜像与正式构建

宿主机需要 Bash、curl、tar、sha256sum、flock 和启用 BuildKit 的 Docker，或 Podman。
首次下载 DVD 约 12 GiB，建议工作盘至少预留 100 GiB。

```bash
# 只生成构建镜像，方便单独发布；重复执行复用下载及镜像层。
WORK_DIR=/data/dragonwell25-rv23 JOBS=32 \
  bash docker/dragonwell25-riscv64/build-image.sh

# 构建镜像，然后在镜像中执行与 Jenkins 相同的仓库构建入口，含 SBOM。
WORK_DIR=/data/dragonwell25-rv23 JOBS=32 \
  bash docker/dragonwell25-riscv64/build.sh

# 使用已准备好的镜像。
WORK_DIR=/data/dragonwell25-rv23 SKIP_IMAGE_BUILD=true \
  bash docker/dragonwell25-riscv64/build.sh
```

默认镜像引用为 `alibabadragonwelljdk/dragonwell25-riscv64-build:anolis23.5-rva23-v1`。
此名称是流水线与构建脚本共同使用的发布约定；首次启用 Jenkins 配置前必须先构建并推送该镜像。
可用 `IMAGE` 指定其他 registry/tag，并同步修改流水线的 `dockerImage`。
镜像推送独立于 JDK 构建，脚本不会自动登录或推送：

```bash
docker push alibabadragonwelljdk/dragonwell25-riscv64-build:anolis23.5-rva23-v1
```

发布后建议把流水线镜像引用固定为 registry 返回的 digest。镜像使用 `CMD` 而不是 `ENTRYPOINT`，
兼容 Jenkins Docker Pipeline 的 `inside` 调用。默认在 Jenkins 用户的工作目录编译。

Podman 可把所有存储放到数据盘：

```bash
WORK_DIR=/nvme/dragonwell25-rv23 CONTAINER_ENGINE=podman \
PODMAN_RUNROOT=/run/dragonwell25-rv23 \
BASE_IMAGE=docker.m.daocloud.io/library/ubuntu:24.04 \
APT_MIRROR=http://mirrors.aliyun.com/ubuntu JOBS=48 \
  bash docker/dragonwell25-riscv64/build.sh
```

## 路径、缓存与参数

- `downloads/` 与 `context/inputs/`：校验后的 DVD、SRPM、Boot JDK；尽可能使用硬链接。
- Docker/Podman 缓存：宿主依赖、sysroot、工具链分层；Ant/jq 等 SBOM 依赖位于最终层。
- 大 ISO 通过只读构建挂载使用，不写入最终镜像层。
- `jdk-workspace/`：正式脚本的 workspace，含源码、编译结果与 `target/` 制品。
- `ccache/`：跨容器的编译缓存；`logs/`：镜像与 JDK 构建日志。
- `/opt/anolis23.5/provenance/`：输入校验清单、spec 与 sysroot RPM 列表。

`build.sh` 支持 `BUILD_ARGS`、`CONFIGURE_ARGS`、`FILENAME`、`JOBS`，额外位置参数传给
`make-adopt-build-farm.sh`。正式构建脚本负责下载 Dragonwell 25 源码、打包及生成 SBOM。
`--clean-git-repo` 沿用 build-farm 的源码清理行为；保留工作目录和 ccache 可减少重复准备成本。

平台脚本为 Dragonwell 25 Linux/riscv64 选择 `/opt/anolis23.5/cross` 与
`/opt/anolis23.5/sysroot`；可以覆盖 `RISCV64`、`RISCV_SYSROOT`、`RISCV_MARCH`、
`RISCV_BUILD_JDK`、`RISCV_BUILD_CC`、`RISCV_BUILD_CXX`。目标库不加入宿主 `LD_LIBRARY_PATH`。
纯 `rva23u64` 缺少 HotSpot 使用的 `fence.i` 扩展，故显式加 `zifencei`。

## SBOM 与运行验证

联调期间配套流水线只对非发布的 Dragonwell 25 Linux/riscv64 构建临时跳过 SBOM 校验、
SmokeTests、AQA/TCK 与可复现比较；编译、打包、归档与 SBOM 生成保持开启。
Jenkins 构建描述会标明 BUILD ONLY。恢复时删除流水线 defaults 中的
`postBuildValidation.skip` 对应条目。公共校验任务及新工具链基线适配暂缓。

```bash
# 在已安装 qemu-riscv64 的 Linux 上运行目标 JDK 的编译与运行冒烟。
bash docker/dragonwell25-riscv64/smoke-test.sh /path/to/jdk /opt/anolis23.5/sysroot
```

QEMU 冒烟不替代 RVA23 硬件上的完整回归。

可选的 `SOURCE_GIT_CACHE=/path/to/dragonwell25.git` 接受可信的本地 bare 镜像，
用于离线复用官方源码；源码的 origin URL 和 SBOM 来源仍保留官方地址。
使用者负责先同步缓存到期望提交。不设置时仍从官方 GitHub 仓库获取源码。
