#!/bin/bash

# ==========================================
# 动态查找 GCC 路径并修复 ld 调用的 Wrapper
# ==========================================

# 1. 获取当前工作目录（Bazel execroot）
REPO_ROOT=$(pwd)

# 2. 动态查找 GCC 编译器
#    我们限制查找范围在 external/ 目录下，避免扫描整个 source tree 导致变慢。
#    -print -quit: 找到第一个匹配项后立即停止，提高效率。
GCC_NAME="aarch64-buildroot-linux-musl-ar"

# 注意：在 Bazel 的 execroot 中，外部仓库通常位于 external/ 目录下
REL_GCC_PATH=$(find external -name "${GCC_NAME}" -type f -print -quit)

if [[ -z "${REL_GCC_PATH}" ]]; then
    echo "ERROR: [ar.sh] Could not find ${GCC_NAME} in external/" >&2
    # 尝试在当前目录宽泛查找作为备选（以防目录结构差异）
    REL_GCC_PATH=$(find . -name "${GCC_NAME}" -type f -print -quit)
    if [[ -z "${REL_GCC_PATH}" ]]; then
        echo "ERROR: [ar.sh] Fatal error, compiler not found anywhere." >&2
        exit 1
    fi
fi

# 3. 解析绝对路径
#    为了安全起见，我们将路径转换为绝对路径
REAL_AS="${REPO_ROOT}/${REL_GCC_PATH}"


# 定义新的参数数组
ARGS=()

# 遍历所有传入的参数
for arg in "$@"; do
    case "$arg" in
        # 匹配想要去掉的参数
        -EL)
            ;;

        *)
            # 其他参数原样保留
            ARGS+=("$arg")
            ;;
    esac
done
# 5. 调用 AS 进行链接
#    -B: 优先在临时目录查找工具（从而找到我们伪造的 ld 软链接）
#    "$@": 传递所有 Bazel 传入的参数
exec "${REAL_AS}" \
    "${ARGS[@]}"