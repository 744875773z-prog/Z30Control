# -*- coding: utf-8 -*-
import os

dim = 17

def gen_cube(filename, title, transform_func):
    lines = [
        f'TITLE "{title}"',
        f'LUT_3D_SIZE {dim}',
        'DOMAIN_MIN 0.0 0.0 0.0',
        'DOMAIN_MAX 1.0 1.0 1.0',
        ''
    ]
    for b_idx in range(dim):
        b = b_idx / (dim - 1)
        for g_idx in range(dim):
            g = g_idx / (dim - 1)
            for r_idx in range(dim):
                r = r_idx / (dim - 1)
                ro, go, bo = transform_func(r, g, b)
                ro = min(1.0, max(0.0, ro))
                go = min(1.0, max(0.0, go))
                bo = min(1.0, max(0.0, bo))
                lines.append(f'{ro:.6f} {go:.6f} {bo:.6f}')
    
    path = os.path.join('Z30Control', 'Resources', 'BuiltinLUTs', filename)
    with open(path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))
    print(f'已生成: {filename}')

# 富士经典正片 (低饱和, 高对比, 冷青绿高光)
def fuji_cc(r, g, b):
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    ro = lum + (r - lum) * 0.8
    go = lum + (g - lum) * 0.85
    bo = lum + (b - lum) * 0.75
    # S 曲线对比度
    ro = pow(ro, 1.12)
    go = pow(go, 1.08)
    bo = pow(bo, 1.05)
    return ro, go, bo

# 好莱坞青橙 (高光暖橙, 阴影冷青)
def teal_orange(r, g, b):
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    ro = r * 1.15 + (1.0 - lum) * 0.02
    go = g * 0.98
    bo = b * 0.85 + (1.0 - lum) * 0.12
    return ro, go, bo

# 柯达经典黑白
def bw_trix(r, g, b):
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    contrast_lum = pow(lum, 1.25)
    return contrast_lum, contrast_lum, contrast_lum

gen_cube('Fuji_Classic_Chrome.cube', 'Fujifilm Classic Chrome', fuji_cc)
gen_cube('Cinematic_Teal_Orange.cube', 'Cinematic Teal and Orange', teal_orange)
gen_cube('TriX_400_BlackAndWhite.cube', 'Kodak Tri-X 400 B&W', bw_trix)
