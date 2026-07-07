"""
Step 1: Convert image to hex format for Verilog simulation
Mini version: 32x32 grayscale
"""

import numpy as np
from PIL import Image
from pathlib import Path

def img_to_hex(image_path, output_hex="test_image.hex", size=32):
    """
    将图像转换为 hex 格式

    Args:
        image_path: 输入图像路径
        output_hex: 输出 hex 文件路径
        size: 图像大小（默认 32x32）
    """
    # 读取并调整大小
    img = Image.open(image_path).convert('L')  # 灰度
    img = img.resize((size, size))
    img_array = np.array(img)

    # 写入 hex 文件
    with open(output_hex, 'w') as f:
        for row in img_array:
            for pixel in row:
                f.write(f"{pixel:02x}\n")

    print(f"[OK] Converted {image_path} to {output_hex}")
    print(f"     Image size: {size}x{size} = {size*size} pixels")

    return img_array

if __name__ == "__main__":
    # 测试
    import sys

    if len(sys.argv) > 1:
        input_img = sys.argv[1]
    else:
        # 使用默认测试图像
        input_img = "../real_images/dog.jpg"

    if not Path(input_img).exists():
        print(f"ERROR: {input_img} not found")
        print("Creating a test pattern instead...")

        # 创建测试图案
        test_img = np.zeros((32, 32), dtype=np.uint8)
        test_img[8:16, 8:16] = 255  # 中心白块
        test_img[0:8, 24:32] = 200  # 右上灰块
        test_img[24:32, 0:8] = 150  # 左下灰块

        # 保存
        Image.fromarray(test_img).save("test_pattern.png")

        # 转换
        with open("test_image.hex", 'w') as f:
            for row in test_img:
                for pixel in row:
                    f.write(f"{pixel:02x}\n")

        print("[OK] Created test_pattern.png and test_image.hex")
    else:
        output_hex = sys.argv[2] if len(sys.argv) > 2 else "test_image.hex"
        size = int(sys.argv[3]) if len(sys.argv) > 3 else 32
        img_to_hex(input_img, output_hex, size=size)
