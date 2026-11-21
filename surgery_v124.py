"""v1.0.24 手术：删顶部参数整块，快门居中（满屏切换挪到底部）。"""
import re, sys

P = "Z30Control/Views/LiveView/LiveViewMonitorView.swift"
lines = open(P, encoding="utf-8").read().splitlines(keepends=True)


def find(pred, start=0):
    for i in range(start, len(lines)):
        if pred(lines[i]):
            return i
    raise AssertionError(f"not found: {pred}")


def brace_end(start):
    """从含 { 的起始行起配对花括号，返回闭合行下标。"""
    depth = 0
    for i in range(start, len(lines)):
        depth += lines[i].count("{") - lines[i].count("}")
        if depth == 0 and i > start:
            return i
    raise AssertionError("unbalanced braces")


def delete_span(a, b, label):
    # 含 a..b（闭区间），顺带吃掉后面一个空行
    assert a <= b, label
    end = b + 1
    if end < len(lines) and lines[end].strip() == "":
        end += 1
    del lines[a:end]
    print(f"  deleted {label}: lines {a+1}..{end}")


# --- 1. 底部 deck 换成三组等宽、快门居中（先做，后面删上面不影响它）---
ds = find(lambda l: l.startswith("    private var portraitBottomControlDeck"))
de = brace_end(ds)
new_deck = '''    private var portraitBottomControlDeck: some View {
        // v1.0.24：快门严格居中——三组等宽（左 DISP+满屏 / 中快门 / 右网格+增强），
        // 快门落在屏幕正中央。之前是 Spacer 两边夹，快门被右边两个键顶偏。
        // 满屏/完整切换从顶部挪到这里，功能没删。
        HStack(spacing: 0) {
            // 左组：DISP 清屏 + 满屏/完整切换（靠左）
            HStack(spacing: 12) {
                Button(action: {
                    NikonTheme.triggerHaptic(style: .medium)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCleanScreen = true
                    }
                }) {
                    VStack(spacing: 3) {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 16))
                        Text("DISP")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18), lineWidth: 0.8))
                }

                Button(action: {
                    NikonTheme.triggerHaptic(style: .light)
                    withAnimation(.easeInOut(duration: 0.2)) { isFillScreen.toggle() }
                }) {
                    VStack(spacing: 3) {
                        Image(systemName: isFillScreen ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 16))
                        Text(isFillScreen ? "满屏" : "完整")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18), lineWidth: 0.8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 中：主快门按钮（严格居中）
            Button(action: {
                triggerShutterCapture()
            }) {
                ZStack {
                    Circle()
                        .stroke(NikonTheme.nikonYellow, lineWidth: 4)
                        .frame(width: 66, height: 66)
                        .shadow(color: NikonTheme.nikonYellow.opacity(0.5), radius: 8, x: 0, y: 0)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 50, height: 50)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            // 右组：网格、增强（靠右）
            HStack(spacing: 12) {
                // 辅助网格切换
                Button(action: {
                    NikonTheme.triggerHaptic(style: .light)
                    isShowingGrid.toggle()
                }) {
                    VStack(spacing: 3) {
                        Image(systemName: isShowingGrid ? "grid" : "grid.circle")
                            .font(.system(size: 16))
                        Text(isShowingGrid ? "网格" : "关")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18), lineWidth: 0.8))
                }

                // v1.0.20：取景增强开关（降噪+锐化，默认开）。
                Button(action: {
                    NikonTheme.triggerHaptic(style: .light)
                    streamService.isEnhanceEnabled.toggle()
                }) {
                    VStack(spacing: 3) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 16))
                        Text(streamService.isEnhanceEnabled ? "增强" : "关")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(streamService.isEnhanceEnabled ? NikonTheme.nikonYellow : .white)
                    .frame(width: 48, height: 48)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18), lineWidth: 0.8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
'''
lines[ds:de + 1] = [new_deck]
print(f"  replaced portraitBottomControlDeck (was lines {ds+1}..{de+1})")

# --- 2. portraitProHUD：删顶部整块（从 v1.0.15 注释到第一个 Spacer）---
ps = find(lambda l: "这里不要再加 safeAreaInsets.top" in l)
pe = find(lambda l: l.strip() == "Spacer()", ps)
new_top = '''            VStack(spacing: 0) {
                // v1.0.24：上面参数全删了（用户 2026-11-21 20:43 截图圈的
                // 顶部整块：状态条 + 快门/光圈/ISO + 模式/白平衡/测光/±EV）。
                // 顶部留空，画面干净；满屏/完整切换挪到底部工具组。
                Spacer()
'''
lines[ps:pe + 1] = [new_top]
print(f"  replaced portraitProHUD top block (was lines {ps+1}..{pe+1})")

# --- 3. 自下而上删死代码（每次重新找位置）---
# expandedSpecsStrip 的 MARK + 定义 + modeDisplayText 的 doc 注释 + 定义
s = find(lambda l: l.strip().startswith("// MARK: - 次级参数展开抽屉"))
e = brace_end(find(lambda l: l.startswith("    private var expandedSpecsStrip"), s))
# modeDisplayText：从它上面的 /// 注释起
m = find(lambda l: l.strip().startswith("/// 模式药丸显示"), e)
me = brace_end(find(lambda l: l.startswith("    private var modeDisplayText"), m))
delete_span(s, me, "expandedSpecsStrip + modeDisplayText")

# coreThreeParamsHUD 的 MARK + 定义
s = find(lambda l: l.strip().startswith("// MARK: - 核心可调三要素"))
e = brace_end(find(lambda l: l.startswith("    private var coreThreeParamsHUD"), s))
delete_span(s, e, "coreThreeParamsHUD")

# topConnectionBanner 的定义
s = find(lambda l: l.startswith("    private var topConnectionBanner"))
e = brace_end(s)
delete_span(s, e, "topConnectionBanner")

# liveViewStreamLabel 的注释 + 定义
s = find(lambda l: "取景按钮带上帧分辨率" in l)
e = brace_end(find(lambda l: l.startswith("    private var liveViewStreamLabel"), s))
delete_span(s, e, "liveViewStreamLabel")

# toggleLiveViewForActiveTransport
s = find(lambda l: l.startswith("    private func toggleLiveViewForActiveTransport"))
e = brace_end(s)
delete_span(s, e, "toggleLiveViewForActiveTransport")

# isShowingExpandedParams @State
s = find(lambda l: "isShowingExpandedParams" in l and l.strip().startswith("@State"))
del lines[s]
print(f"  deleted @State isShowingExpandedParams (line {s+1})")

text = "".join(lines)
# 连续 3 个以上空行压成 2 个
text = re.sub(r"\n{4,}", "\n\n\n", text)
open(P, "w", encoding="utf-8").write(text)

# 校验：花括号平衡 + 删掉的东西都没了
assert text.count("{") == text.count("}"), "brace imbalance!"
for gone in ["topConnectionBanner", "coreThreeParamsHUD", "expandedSpecsStrip",
             "isShowingExpandedParams", "modeDisplayText",
             "toggleLiveViewForActiveTransport", "liveViewStreamLabel"]:
    assert gone not in text, f"still present: {gone}"
for keep in ["portraitBottomControlDeck", "isFillScreen.toggle()", "triggerShutterCapture",
             "disconnectedEmptyState", "hudParamPill", "paramPickerPanel"]:
    assert keep in text, f"missing: {keep}"
print("OK: braces balanced, removed gone, kept present")
