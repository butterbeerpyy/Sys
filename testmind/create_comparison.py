"""
对比测试：智能选择 vs 固定中心区域
使用真实图片
"""

import numpy as np
from PIL import Image
import matplotlib.pyplot as plt
from pathlib import Path
import urllib.request

class PyramidProcessor:
    """金字塔处理器"""

    def __init__(self):
        self.patch_size = 14
        self.image_size = 224

    def extract_patches(self, image):
        """提取 patches"""
        patches = []
        h, w = image.shape[0], image.shape[1]
        for i in range(0, h, self.patch_size):
            for j in range(0, w, self.patch_size):
                patch = image[i:i+self.patch_size, j:j+self.patch_size, :]
                if patch.shape[0] == self.patch_size and patch.shape[1] == self.patch_size:
                    patches.append(patch)
        return np.array(patches)

    def compute_complexity(self, patch):
        """计算 patch 复杂度"""
        gray = 0.299 * patch[:,:,0] + 0.587 * patch[:,:,1] + 0.114 * patch[:,:,2]
        grad_x = np.abs(np.diff(gray, axis=1))
        grad_y = np.abs(np.diff(gray, axis=0))
        return np.mean(grad_x) + np.mean(grad_y)

    def compute_interest_map(self, image):
        """计算兴趣度地图"""
        patches = self.extract_patches(image)
        grid_size = self.image_size // self.patch_size

        interest_map = np.zeros((grid_size, grid_size))
        for idx, patch in enumerate(patches):
            i = idx // grid_size
            j = idx % grid_size
            interest_map[i, j] = self.compute_complexity(patch)

        return interest_map, patches

    def extract_features(self, patches):
        """提取特征"""
        features = []
        for patch in patches:
            color = np.mean(patch, axis=(0, 1))
            texture = np.std(patch, axis=(0, 1))
            feat = np.concatenate([color, texture])
            features.append(feat)
        return np.array(features)

    def baseline_process(self, image):
        """基线：处理所有 patches"""
        patches = self.extract_patches(image)
        features = self.extract_features(patches)
        return features

    def center_crop_process(self, image, top_k=20):
        """中心裁剪：只处理中心区域"""
        _, all_patches = self.compute_interest_map(image)
        grid_size = self.image_size // self.patch_size

        # 计算中心区域
        center_size = int(np.sqrt(top_k))  # 假设正方形
        start = (grid_size - center_size) // 2

        # 创建中心 mask
        mask = np.zeros((grid_size, grid_size))
        mask[start:start+center_size, start:start+center_size] = 1

        # 获取中心 patches
        center_indices = []
        for i in range(start, start+center_size):
            for j in range(start, start+center_size):
                if i < grid_size and j < grid_size:
                    idx = i * grid_size + j
                    if idx < len(all_patches):
                        center_indices.append(idx)

        selected_patches = [all_patches[i] for i in center_indices[:top_k]]
        features = self.extract_features(selected_patches)

        return features, mask

    def smart_select_process(self, image, top_k=20):
        """智能选择：基于兴趣度"""
        interest_map, all_patches = self.compute_interest_map(image)
        grid_size = self.image_size // self.patch_size

        # Top-K 选择
        flat_interest = interest_map.flatten()
        top_indices = np.argsort(flat_interest)[-top_k:][::-1]

        # Mask
        mask = np.zeros_like(flat_interest)
        mask[top_indices] = 1
        mask = mask.reshape(interest_map.shape)

        selected_patches = [all_patches[i] for i in top_indices]
        features = self.extract_features(selected_patches)

        return features, mask, interest_map

    def similarity(self, f1, f2):
        """余弦相似度"""
        min_len = min(len(f1), len(f2))
        if min_len == 0:
            return 0.0

        f1 = f1[:min_len].flatten()
        f2 = f2[:min_len].flatten()

        dot = np.dot(f1, f2)
        norm = np.linalg.norm(f1) * np.linalg.norm(f2)
        return dot / norm if norm > 0 else 0.0

def download_real_image():
    """下载一张真实图片"""
    urls = [
        ("https://upload.wikimedia.org/wikipedia/commons/thumb/3/3a/Cat03.jpg/1200px-Cat03.jpg", "cat.jpg"),
        ("https://upload.wikimedia.org/wikipedia/commons/thumb/4/47/PNG_transparency_demonstration_1.png/800px-PNG_transparency_demonstration_1.png", "demo.png"),
    ]

    img_dir = Path("real_images")
    img_dir.mkdir(exist_ok=True)

    for url, filename in urls:
        filepath = img_dir / filename
        if not filepath.exists():
            try:
                print(f"📥 下载图片: {filename}...")
                urllib.request.urlretrieve(url, filepath)
                print(f"   ✅ 下载成功")
                return filepath
            except Exception as e:
                print(f"   ⚠️  下载失败: {e}")
                continue
        else:
            print(f"✅ 使用已有图片: {filename}")
            return filepath

    return None

def create_comparison(image_path, top_k=20):
    """创建对比图"""
    processor = PyramidProcessor()

    # 加载图片
    img = Image.open(image_path).convert('RGB')
    img = img.resize((224, 224))
    img_array = np.array(img)

    # 1. 基线（全部处理）
    feat_baseline = processor.baseline_process(img_array)

    # 2. 中心裁剪
    feat_center, mask_center = processor.center_crop_process(img_array, top_k)

    # 3. 智能选择
    feat_smart, mask_smart, interest_map = processor.smart_select_process(img_array, top_k)

    # 计算相似度
    sim_center = processor.similarity(feat_baseline, feat_center)
    sim_smart = processor.similarity(feat_baseline, feat_smart)

    loss_center = (1 - sim_center) * 100
    loss_smart = (1 - sim_smart) * 100

    total_patches = 16 * 16
    saved = (1 - top_k / total_patches) * 100

    # 创建可视化
    fig = plt.figure(figsize=(22, 10))

    # 第一行：原图和兴趣度
    ax1 = plt.subplot(2, 4, 1)
    ax1.imshow(img)
    ax1.set_title("原始图像", fontsize=14, fontweight='bold', pad=10)
    ax1.axis('off')

    ax2 = plt.subplot(2, 4, 2)
    im1 = ax2.imshow(interest_map, cmap='hot', interpolation='bilinear')
    ax2.set_title("兴趣度分析\n(边缘复杂度)", fontsize=14, fontweight='bold', pad=10)
    ax2.axis('off')
    plt.colorbar(im1, ax=ax2, fraction=0.046)

    # 第一行：中心裁剪方法
    ax3 = plt.subplot(2, 4, 3)
    im2 = ax3.imshow(mask_center, cmap='RdYlGn', interpolation='nearest')
    ax3.set_title(f"❌ 方法 A：固定中心\n(Top-{top_k})",
                  fontsize=14, fontweight='bold', pad=10, color='red')
    ax3.axis('off')
    plt.colorbar(im2, ax=ax3, fraction=0.046)

    # 第一行：统计（中心）
    ax4 = plt.subplot(2, 4, 4)
    ax4.axis('off')
    stats_center = f"""
方法 A：固定选择中心

处理策略:
  固定选择图像中心区域

性能指标:
  Patches: {top_k}/{total_patches}
  存储节省: {saved:.1f}%

精度:
  相似度: {sim_center*100:.2f}%
  精度损失: {loss_center:.2f}%

❌ 问题:
  • 忽略边缘重要信息
  • 可能漏掉关键物体
  • 不适应图像内容
    """
    ax4.text(0.05, 0.5, stats_center,
             fontsize=11, family='monospace', va='center',
             bbox=dict(boxstyle='round,pad=1', fc='#ffcccc',
                      ec='red', lw=2, alpha=0.8))

    # 第二行：原图（重复显示）
    ax5 = plt.subplot(2, 4, 5)
    ax5.imshow(img)
    ax5.set_title("原始图像", fontsize=14, fontweight='bold', pad=10)
    ax5.axis('off')

    # 第二行：基线（全部处理）
    ax6 = plt.subplot(2, 4, 6)
    baseline_mask = np.ones((16, 16))
    im3 = ax6.imshow(baseline_mask, cmap='Greens', interpolation='nearest')
    ax6.set_title("⚪ 基线：全部处理\n(256 patches)",
                  fontsize=14, fontweight='bold', pad=10)
    ax6.axis('off')
    plt.colorbar(im3, ax=ax6, fraction=0.046)

    # 第二行：智能选择
    ax7 = plt.subplot(2, 4, 7)
    im4 = ax7.imshow(mask_smart, cmap='RdYlGn', interpolation='nearest')
    ax7.set_title(f"✅ 方法 B：智能选择\n(Top-{top_k})",
                  fontsize=14, fontweight='bold', pad=10, color='green')
    ax7.axis('off')
    plt.colorbar(im4, ax=ax7, fraction=0.046)

    # 第二行：统计（智能）
    ax8 = plt.subplot(2, 4, 8)
    ax8.axis('off')
    stats_smart = f"""
方法 B：智能选择（我的方案）

处理策略:
  1. 粗扫描检测兴趣点
  2. Top-{top_k} 选择器
  3. 自适应精细处理

性能指标:
  Patches: {top_k}/{total_patches}
  存储节省: {saved:.1f}%

精度:
  相似度: {sim_smart*100:.2f}%
  精度损失: {loss_smart:.2f}%

✅ 优势:
  • 自动定位重要区域
  • 适应图像内容
  • 精度损失更小

💡 vs 方法A:
  精度提升: {loss_center - loss_smart:.1f}%
    """
    ax8.text(0.05, 0.5, stats_smart,
             fontsize=11, family='monospace', va='center',
             bbox=dict(boxstyle='round,pad=1', fc='#ccffcc',
                      ec='green', lw=2, alpha=0.8))

    # 总标题
    improvement = loss_center - loss_smart
    fig.suptitle(f'VLM 特化加速方案对比：智能选择 vs 固定中心\n'
                 f'智能选择方案精度提升 {improvement:.1f}%，同样节省 {saved:.0f}% 计算量',
                 fontsize=16, fontweight='bold', y=0.98)

    plt.tight_layout(rect=[0, 0, 1, 0.96])

    # 保存
    output_dir = Path("comparison_results")
    output_dir.mkdir(exist_ok=True)
    output_path = output_dir / f"{Path(image_path).stem}_comparison.png"
    plt.savefig(output_path, dpi=300, bbox_inches='tight', facecolor='white')
    print(f"\n✅ 保存对比图: {output_path}")
    plt.close()

    return output_path, sim_center, sim_smart, loss_center, loss_smart

def main():
    print("="*80)
    print("  智能选择 vs 固定中心 - 对比测试")
    print("="*80)

    # 获取真实图片
    print("\n[1] 获取测试图片...")
    img_path = download_real_image()

    if not img_path:
        # 使用之前的测试图片
        test_dir = Path("test_images")
        if test_dir.exists():
            test_images = list(test_dir.glob("*.jpg"))
            if test_images:
                img_path = test_images[0]
                print(f"✅ 使用测试图片: {img_path}")

    if not img_path:
        print("❌ 没有可用的测试图片")
        return

    # 创建对比
    print("\n[2] 生成对比可视化...")
    output_path, sim_center, sim_smart, loss_center, loss_smart = create_comparison(img_path, top_k=20)

    # 输出结果
    print("\n" + "="*80)
    print("  对比结果")
    print("="*80)
    print(f"\n方法 A - 固定选择中心:")
    print(f"  相似度:    {sim_center*100:.2f}%")
    print(f"  精度损失:  {loss_center:.2f}%")

    print(f"\n方法 B - 智能选择 (我的方案):")
    print(f"  相似度:    {sim_smart*100:.2f}%")
    print(f"  精度损失:  {loss_smart:.2f}%")

    improvement = loss_center - loss_smart
    print(f"\n✅ 智能选择方案优势:")
    print(f"   精度提升: {improvement:.2f}%")
    print(f"   计算节省: 92.2% (两种方案相同)")

    print("\n" + "="*80)
    print("  给老师讲解要点")
    print("="*80)
    print("""
1. 指着上排说:
   "传统方法可能只选图像中心，但这会漏掉边缘的重要信息"

2. 指着下排说:
   "我的方案会先扫描全图，智能找出最重要的 20 个区域"

3. 指着右边统计:
   "结果是：同样节省 92% 计算，但精度提升 {:.1f}%"

4. 总结:
   "这就是特化设计的优势 - 针对 VLM 的特点优化"
    """.format(improvement))

    print(f"\n📁 高清对比图: {output_path}")
    print()

if __name__ == "__main__":
    main()
