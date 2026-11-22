"""v1.0.26 回归：mini 5（iPadOS 14.2）能打开。

Yuan 2026-11-21 23:46：iPad mini 5（iPadOS 14.2，巨魔商店装的）打不开。
原因：project.yml 的 deploymentTarget 是 16.0，14.2 的系统直接不让跑。

修（统一一版，iPhone 和 mini 5 装同一个包）：
1. deploymentTarget 降到 14.0。
2. confirmationDialog（iOS 15+）→ 页内底部面板 gridPickerPanel，
   和参数面板同一个做法。
3. GeometryProxy.safeAreaInsets（iOS 15+）→ bottomSafeInset 助手：
   15+ 走系统值，14 上从当前窗口拿；mini 5 有 Home 键，本来就是 0。
4. ultraThinMaterial（iOS 15+）→ #available 分支：15+ 毛玻璃，
   14 上半透明白底。
5. ConnectionWizardView 的 safeAreaInset（iOS 15+）→ 底部连接栏放进
   VStack 底部。
6. 其他 iOS 15/16/17 API 全扫一遍：没有 NavigationStack、PhotosPicker、
   ShareLink、presentationDetents、AsyncImage、refreshable、searchable、
   swipeActions、scrollContentBackground、.formatted(、AttributedString、
   AnyLayout、ViewThatFits、GridRow、LabeledContent、Gauge、.tint、
   Button(role:、新式 alert、background(_:in:)、闭包式 overlay(alignment:)、
   带位置的 onTapGesture。
   注意：LazyVGrid/GridItem 是 iOS 14 就有的，不算；UIGraphicsImageRenderer
   是 UIKit（iOS 10+），不算；.onTapGesture(count: 2) 不带位置，是 iOS 13
   就有的，不算。

另外提醒过 Yuan：mini 5 是闪电口，有线直连得用苹果闪电转 USB 相机
转换器（没实测过）；Wi-Fi 热点方式直接能用。
"""

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "Tests"))


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


def all_swift():
    out = []
    for dirpath, _, files in os.walk(os.path.join(ROOT, "Z30Control")):
        for name in files:
            if name.endswith(".swift"):
                out.append(os.path.join(dirpath, name))
    return sorted(out)


def run():
    passed = failed = 0

    def check(name, ok, detail=""):
        nonlocal passed, failed
        if ok:
            passed += 1
            print(f"  ✅ {name}")
        else:
            failed += 1
            print(f"  ❌ {name} {detail}")

    yml = read("project.yml")
    plist = read("Z30Control/Info.plist")
    live = read("Z30Control/Views/LiveView/LiveViewMonitorView.swift")
    root = read("Z30Control/App/RootTabView.swift")
    wizard = read("Z30Control/Views/Connection/ConnectionWizardView.swift")
    swift_files = all_swift()
    swift_src = "\n".join(open(p, encoding="utf-8").read() for p in swift_files)

    print("== 版本与部署目标 ==")
    check("deploymentTarget 降到 14.0",
          'deploymentTarget: "14.0"' in yml)
    check("版本 1.0.29 / build 30（两处一致，v1.0.29 起由 test_v129_gallery_delete 再验一遍）",
          "MARKETING_VERSION: 1.0.29" in yml
          and "CURRENT_PROJECT_VERSION: 30" in yml
          and "<string>1.0.29</string>" in plist
          and "<string>30</string>" in plist)

    print("== iOS 15+ API 全清掉或加兜底 ==")
    check("没有 confirmationDialog 调用",
          ".confirmationDialog(" not in swift_src)
    check("没有 safeAreaInset(",
          "safeAreaInset(" not in swift_src)
    for banned in ["NavigationStack", "PhotosPicker", "ShareLink",
                   "presentationDetents", "AsyncImage", "refreshable",
                   "searchable", "swipeActions", "scrollContentBackground",
                   ".formatted(", "AttributedString", "AnyLayout",
                   "ViewThatFits", "GridRow", "LabeledContent", "Gauge(",
                   ".tint(", "role: .cancel", "role: .destructive",
                   "in: RoundedRectangle", "in: Capsule",
                   ".overlay(alignment:", "coordinateSpace"]:
        check(f"没有 {banned}", banned not in swift_src)
    check("没有新式 alert（标题+actions/message 闭包）",
          '.alert("' not in swift_src)
    check("没有带位置的 onTapGesture（iOS 17 才有）",
          "coordinateSpace" not in swift_src
          and "onTapGesture { location" not in swift_src)
    check("safeAreaInsets 只出现在 #available 兜底里",
          all("#available(iOS 15" in open(p, encoding="utf-8").read()
              for p in swift_files
              if "safeAreaInsets" in open(p, encoding="utf-8").read()))
    check("两处都有 bottomSafeInset 助手",
          "func bottomSafeInset" in live and "func bottomSafeInset" in root)
    check("14 上从当前窗口拿安全区",
          "UIApplication.shared.connectedScenes" in live
          and "UIApplication.shared.connectedScenes" in root)
    check("毛玻璃有 #available 分支，14 上是半透明白底",
          "#available(iOS 15" in root
          and "Capsule().fill(.ultraThinMaterial)" in root
          and "Capsule().fill(Color.white.opacity(0.88))" in root)
    check("向导页底部连接栏还在，改走 VStack",
          "bottomConnectBar" in wizard and "VStack(spacing: 0)" in wizard)

    print("== 14 上能用的替代写法都在 ==")
    check("点按对焦改走零距离拖拽手势",
          "DragGesture(minimumDistance: 0)" in live)
    check("进度条改走 .accentColor",
          ".accentColor(NikonTheme.accentBlue)" in swift_src
          and ".accentColor(NikonTheme.readyGreen)" in swift_src)
    check("图库弹窗改走老式 Alert",
          "Alert(" in swift_src)
    check("底栏选中态改走 .fill",
          ".fill(isSelected ? NikonTheme.accentBlue : Color.clear)" in root)
    check("图库多选角标改走 Group 包 overlay",
          "Group {" in swift_src and ", alignment: .topTrailing)" in swift_src)

    print("== 网格选择器还是页内面板（v1.0.25 的功能没丢）==")
    check("gridPickerPanel 在", "func gridPickerPanel" in live)
    check("面板列出 8 个选项", "GridStyle.allCases" in live)
    check("选完保存", "style.save()" in live)

    print(f"\n通过 {passed} 项，失败 {failed} 项")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    run()
