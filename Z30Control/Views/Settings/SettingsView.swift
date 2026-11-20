//
//  SettingsView.swift
//  Z30Control
//
//  系统偏好、外观切换、时钟同步与高级配置视图 (对齐截图 7)
//

import SwiftUI

public struct SettingsView: View {
    @ObservedObject var cameraState: CameraState
    @ObservedObject var themeManager = ThemeManager.shared
    @State private var isShowingSyncAlert = false
    @State private var quickPreviewDuration: Int = 2 // 0:关闭, 1:1秒, 2:2秒, 3:3秒
    
    public init(cameraState: CameraState) {
        self.cameraState = cameraState
    }
    
    public var body: some View {
        NavigationView {
            List {
                Section(header: Text("界面与交互")) {
                    // 外观深浅切换
                    Picker(selection: $themeManager.preference, label: settingRow(icon: "circle.righthalf.filled", title: "外观主题")) {
                        ForEach(AppThemePreference.allCases, id: \.self) { pref in
                            Text(pref.rawValue).tag(pref)
                        }
                    }
                    
                    // 拍摄后快速回放时长
                    Picker(selection: $quickPreviewDuration, label: settingRow(icon: "eye.fill", title: "拍摄后快速预览")) {
                        Text("关闭").tag(0)
                        Text("1 秒").tag(1)
                        Text("2 秒 (推荐)").tag(2)
                        Text("3 秒").tag(3)
                    }
                    
                    NavigationLink(destination: Text("水印相框模板配置")) {
                        HStack {
                            settingRow(icon: "text.below.photo", title: "水印模板")
                            Spacer()
                            Text("beta")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(NikonTheme.readyGreen)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(NikonTheme.readyGreen.opacity(0.15))
                                .cornerRadius(3)
                        }
                    }
                }
                
                Section(header: Text("相机通信与控制")) {
                    NavigationLink(destination: Text("控制偏好高级选项")) {
                        settingRow(icon: "dial.low", title: "控制按键映射")
                    }
                    NavigationLink(destination: Text("连接配置")) {
                        settingRow(icon: "antenna.radiowaves.left.and.right", title: "连接方式 (Wi-Fi / USB-C)")
                    }
                    
                    // 相机时钟一键同步
                    Button(action: {
                        NikonTheme.triggerHaptic(style: .medium)
                        isShowingSyncAlert = true
                    }) {
                        HStack {
                            Image(systemName: "clock.arrow.2.circlepath")
                                .foregroundColor(NikonTheme.nikonYellow)
                            Text("同步手机时间到 Z30 机身")
                                .proHUDText(size: 13, weight: .semibold)
                                .foregroundColor(Color.primary)
                        }
                    }
                }
                
                Section(header: Text("设备与固件")) {
                    HStack {
                        Text("目标机型")
                        Spacer()
                        Text(cameraState.modelName).foregroundColor(.gray)
                    }
                    HStack {
                        Text("固件版本")
                        Spacer()
                        Text(cameraState.firmwareVersion).foregroundColor(.gray)
                    }
                    HStack {
                        Text("协议版本")
                        Spacer()
                        Text("Nikon PTP/IP v1.0").foregroundColor(.gray)
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .alert(isPresented: $isShowingSyncAlert) {
                Alert(
                    title: Text("时钟同步成功"),
                    message: Text("已将 iPhone 精确原子钟时间写入尼康 Z30 机身！"),
                    dismissButton: .default(Text("确定"))
                )
            }
        }
    }
    
    private func settingRow(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(Color.primary)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(Color.primary)
        }
    }
}
