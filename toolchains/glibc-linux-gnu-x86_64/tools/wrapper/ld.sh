#!/bin/bash

# ==========================================
# 动态查找 GCC 路径并修复 ld 调用的 Wrapper
# ==========================================

# 1. 获取当前工作目录（Bazel execroot）
REPO_ROOT=$(pwd)

# 2. 动态查找 GCC 编译器
#    我们限制查找范围在 external/ 目录下，避免扫描整个 source tree 导致变慢。
#    -print -quit: 找到第一个匹配项后立即停止，提高效率。
GCC_NAME="x86_64-buildroot-linux-gnu-g++"
LD_NAME="x86_64-buildroot-linux-gnu-ld"

# 注意：在 Bazel 的 execroot 中，外部仓库通常位于 external/ 目录下
REL_GCC_PATH=$(find external -name "${GCC_NAME}" -type f -print -quit)

if [[ -z "${REL_GCC_PATH}" ]]; then
    echo "ERROR: [ld.sh] Could not find ${GCC_NAME} in external/" >&2
    # 尝试在当前目录宽泛查找作为备选（以防目录结构差异）
    REL_GCC_PATH=$(find . -name "${GCC_NAME}" -type f -print -quit)
    if [[ -z "${REL_GCC_PATH}" ]]; then
        echo "ERROR: [ld.sh] Fatal error, compiler not found anywhere." >&2
        exit 1
    fi
fi

# 3. 解析绝对路径
#    为了安全起见，我们将路径转换为绝对路径
REAL_GCC="${REPO_ROOT}/${REL_GCC_PATH}"
TOOL_DIR=$(dirname "${REAL_GCC}")
REAL_LD="${TOOL_DIR}/${LD_NAME}"

# 检查 LD 是否存在
if [[ ! -f "${REAL_LD}" ]]; then
    echo "ERROR: [ld.sh] Found GCC at ${REAL_GCC} but LD not found at ${REAL_LD}" >&2
    exit 1
fi

# 4. 创建临时目录并建立 'ld' 软链接
#    这是为了欺骗 GCC，让它在 -B 目录下能找到一个名字叫 'ld' 的文件
TEMP_LD_DIR=$(mktemp -d)

# 创建软链接： ${TEMP_LD_DIR}/ld -> 真正的长名字 ld
ln -sf "${REAL_LD}" "${TEMP_LD_DIR}/ld"

# 5. 调用 GCC 进行链接
#    -B: 优先在临时目录查找工具（从而找到我们伪造的 ld 软链接）
#    "$@": 传递所有 Bazel 传入的参数
exec "${REAL_GCC}" \
    -B "${TEMP_LD_DIR}" \
    "$@"