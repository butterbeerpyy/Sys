@echo off
echo ================================================================================
echo   安装依赖包
echo ================================================================================
echo.

echo [1] 检查 Python...
python --version
if %errorlevel% neq 0 (
    echo ERROR: Python 未安装或不在 PATH 中
    echo 请从 https://www.python.org/downloads/ 下载安装
    pause
    exit /b 1
)

echo.
echo [2] 安装依赖包...
echo    - numpy
echo    - pillow
echo    - matplotlib
echo.

python -m pip install numpy pillow matplotlib

if %errorlevel% neq 0 (
    echo.
    echo 安装失败，尝试使用国内镜像...
    python -m pip install -i https://pypi.tuna.tsinghua.edu.cn/simple numpy pillow matplotlib
)

echo.
echo ================================================================================
echo   安装完成！
echo ================================================================================
echo.
echo 运行测试：
echo   python test_pyramid.py
echo.
pause
