#!/bin/bash
echo "================================================================================"
echo "  多分辨率金字塔处理器 - 可行性验证"
echo "================================================================================"
echo ""

# 检查 Python
if ! command -v python3 &> /dev/null; then
    echo "ERROR: Python3 未找到"
    exit 1
fi

# 检查依赖
echo "[1] 检查依赖..."
python3 -c "import numpy; import PIL; import matplotlib" 2>/dev/null
if [ $? -ne 0 ]; then
    echo "    需要安装依赖包"
    echo "    运行: pip3 install numpy pillow matplotlib"
    exit 1
fi
echo "    ✅ 依赖包已安装"

# 运行测试
echo ""
echo "[2] 运行测试..."
python3 test_pyramid.py

echo ""
echo "================================================================================"
echo "  测试完成！查看 results/ 目录"
echo "================================================================================"
