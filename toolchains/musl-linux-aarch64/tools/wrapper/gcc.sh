#!/bin/bash

# ==========================================
# 动态查找 GCC 路径并修复 ld 调用的 Wrapper
# ==========================================

# 1. 获取当前工作目录（Bazel execroot）
REPO_ROOT=$(pwd)
CURRENT_DIR=$(cd $(dirname $0); pwd)

# 2. 动态查找 GCC 编译器
GCC_NAME="aarch64-buildroot-linux-musl-g++.br_real"
AR_NAME="aarch64-buildroot-linux-musl-ar"
AS_NAME="aarch64-buildroot-linux-musl-as"

REL_GCC_PATH=$(find external -name "${GCC_NAME}" -type f -print -quit)

if [[ -z "${REL_GCC_PATH}" ]]; then
    echo "ERROR: [gcc.sh] Could not find ${GCC_NAME} in external/" >&2
    REL_GCC_PATH=$(find . -name "${GCC_NAME}" -type f -print -quit)
    if [[ -z "${REL_GCC_PATH}" ]]; then
        echo "ERROR: [gcc.sh] Fatal error, compiler not found anywhere." >&2
        exit 1
    fi
fi

# 3. 解析绝对路径
REAL_GCC="${REPO_ROOT}/${REL_GCC_PATH}"
TOOL_DIR=$(dirname "${REAL_GCC}")
REAL_AR="${TOOL_DIR}/${AR_NAME}"
REAL_AS="${TOOL_DIR}/${AS_NAME}"

# 检查 AR/AS 是否存在
if [[ ! -f "${REAL_AR}" ]]; then
    echo "ERROR: [gcc.sh] Found GCC at ${REAL_GCC} but AR not found at ${REAL_AR}" >&2
    exit 1
fi
if [[ ! -f "${REAL_AS}" ]]; then
    echo "ERROR: [gcc.sh] Found GCC at ${REAL_GCC} but AS not found at ${REAL_AS}" >&2
    exit 1
fi

# 4. 创建临时目录并建立 'ar'/'as' 软链接
TEMP_DIR=$(mktemp -d)

# 确保脚本退出时删除临时目录
cleanup() {
    rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT

ln -sf "${REAL_AR}" "${TEMP_DIR}/ar"
ln -sf "${REAL_AS}" "${TEMP_DIR}/as"

# 5. 调用 GCC 进行编译/链接
#    注意：这里移除了 'exec'，以便后续修改文件
"${REAL_GCC}" \
    -B "${TEMP_DIR}" \
    "$@"
RET_CODE=$?

# 如果编译失败，直接退出
if [ $RET_CODE -ne 0 ]; then
    exit $RET_CODE
fi

# ==========================================
# 6. 【关键修复】修复 .d 依赖文件中的绝对路径
# ==========================================

# 寻找 -MF 参数后面的文件路径（即 .d 依赖文件）
DEP_FILE=""
PREV_ARG=""

for arg in "$@"; do
    if [ "$PREV_ARG" == "-MF" ]; then
        DEP_FILE="$arg"
        break
    fi
    PREV_ARG="$arg"
done

# 如果找到了 .d 文件，且文件存在，执行替换
if [ -n "$DEP_FILE" ] && [ -f "$DEP_FILE" ]; then
    # 正则逻辑：
    # s|           : 替换开始
    # /            : 匹配以斜杠开头（绝对路径）
    # [^ ]*        : 匹配任意非空格字符（贪婪匹配直到 external）
    # /external/   : 匹配显式的 /external/ 目录分隔符
    # |external/   : 替换为相对路径 external/
    # |g           : 全局替换（处理一行内的多个依赖）

    # 例子：
    # /proc/self/cwd/external/lib/a.h -> external/lib/a.h
    # /proc/226872/root/external/lib/a.h -> external/lib/a.h

    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS sed 需要空后缀
        sed -i "" 's|/[^ ]*/external/|external/|g' "$DEP_FILE"
    else
        # Linux sed
        sed -i 's|/[^ ]*/external/|external/|g' "$DEP_FILE"
    fi
fi

exit $RET_CODE