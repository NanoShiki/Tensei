"""将生图候选规范化为固定网格。用户已授权脚本透明清理与打包。"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as ndi


def extract(path):
    image = Image.open(path).convert('RGBA')
    frames = []
    for row in range(4):
        for col in range(4):
            # 此处定位候选内的主体；交付图使用下方固定的 256 网格。
            box = (round(col * image.width / 4), round(row * image.height / 4),
                   round((col + 1) * image.width / 4), round((row + 1) * image.height / 4))
            data = np.array(image.crop(box))
            rgb = data[:, :, :3].astype(int)
            mask = (data[:, :, 3] >= 220) & ((rgb.max(2) - rgb.min(2)) < 190)
            labels, count = ndi.label(mask)
            if count == 0:
                raise ValueError(f'空帧 {row},{col}')
            sizes = np.bincount(labels.ravel()); sizes[0] = 0
            mask = ndi.binary_fill_holes(labels == sizes.argmax())
            ys, xs = np.where(mask)
            if min(xs.min(), ys.min(), data.shape[1]-1-xs.max(), data.shape[0]-1-ys.max()) < 2:
                raise ValueError(f'源帧可能越格 {row},{col}')
            # 以可信主体颜色扩展透明边缘，消除被模型污染的彩色边缘像素。
            nearest = ndi.distance_transform_edt(~mask, return_distances=False, return_indices=True)
            clean = data[nearest[0], nearest[1], :].copy()
            clean[:, :, 3] = mask.astype(np.uint8) * 255
            bounds = (int(xs.min()), int(ys.min()), int(xs.max()+1), int(ys.max()+1))
            frames.append((Image.fromarray(clean).crop(bounds), bounds))
    return frames


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('walk'); parser.add_argument('run'); parser.add_argument('--output', default=str(Path(__file__).parent))
    args = parser.parse_args()
    out = Path(args.output); out.mkdir(parents=True, exist_ok=True)
    groups = [extract(args.walk), extract(args.run)]
    # 同一缩放因子用于全部 32 帧，避免每帧拉伸。
    scale = min(192 / max(f.height for group in groups for f, _ in group),
                208 / max(f.width for group in groups for f, _ in group))
    results = []
    for index, (name, frames) in enumerate(zip(['07-俯视行走.png', '08-俯视跑步.png'], groups)):
        sheet = Image.new('RGBA', (1024, 1024))
        boxes = []
        for i, (frame, source_bounds) in enumerate(frames):
            frame = frame.resize((round(frame.width*scale), round(frame.height*scale)), Image.Resampling.LANCZOS)
            col, row = i % 4, i // 4
            # 跑步腾空相位保留地面投影锚点，给予固定的 6px 离地量。
            lift = 6 if index == 1 and col in (1, 3) else 0
            x, y = 128 - frame.width//2, 224 - frame.height - lift
            assert x >= 16 and y >= 16 and x+frame.width <= 240 and y+frame.height <= 240
            sheet.alpha_composite(frame, (col*256+x, row*256+y))
            boxes.append(dict(row=row, column=col, rect=[col*256,row*256,256,256],
                              source_bounds=source_bounds, content_rect=[x,y,frame.width,frame.height], ground_anchor=[128,224], lift=lift))
        path = out/name; sheet.save(path)
        data = np.array(sheet); alpha=data[:,:,3]
        for row in range(4):
            for col in range(4):
                a=alpha[row*256:(row+1)*256,col*256:(col+1)*256]
                assert not a[:16].any() and not a[-16:].any() and not a[:,:16].any() and not a[:,-16:].any()
        results.append(dict(file=name,size=[1024,1024],grid=[4,4],cell=[256,256],directions=['南','东','北','西'],
                            alpha_extrema=[int(alpha.min()),int(alpha.max())],transparent_pixels=int((alpha==0).sum()),
                            sha256=hashlib.sha256(path.read_bytes()).hexdigest(),scale=scale,frames=boxes,
                            status='尺寸、RGBA、安全边距通过；姿态、循环与引擎适配待验收'))
    (out/'动作验证报告.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps([{k:v for k,v in result.items() if k not in ['frames']} for result in results],ensure_ascii=False,indent=2))


if __name__ == '__main__':
    main()
