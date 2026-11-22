//
//  PictCtrlView.swift
//  Z30Control
//
//  v1.0.28：机身滤镜——选 C1–C9 里的一个空槽，把内置滤镜写进相机，直出带风格。
//  36 字节槽（相机菜单里建过的）不给写；非空槽写之前弹确认（会先备份）。
//  iOS 14 兼容：只用旧式 .alert、NavigationLink、sheet，不用 iOS 15+ API。
//

import SwiftUI

public struct PictCtrlView: View {
    @ObservedObject var service = PictCtrlService.shared

    @State private var selectedSlot: PictCtrlSlot? = nil
    @State private var pendingPreset: PictCtrlPreset? = nil
    @State private var activeAlert: PictCtrlAlert? = nil
    @State private var showBackups = false

    private enum PictCtrlAlert: Identifiable {
        case writeConfirm
        case message(String)
        var id: String {
            switch self {
            case .writeConfirm: return "writeConfirm"
            case .message: return "message"
            }
        }
    }

    public init() {}

    public var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    slotSection
                    presetSection
                    backupEntry
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
            }
            .background(NikonTheme.bgPure.ignoresSafeArea())
            .navigationTitle("机身滤镜")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("重新读取") { refresh() }
                        .disabled(service.isReadingSlots || !service.isConnected)
                }
            }
            .onAppear { refresh() }
            .alert(item: $activeAlert) { alert in
                switch alert {
                case .writeConfirm:
                    return Alert(
                        title: Text("写入机身？"),
                        message: Text(writeConfirmText),
                        primaryButton: .default(Text("写入")) {
                            if let preset = pendingPreset, let slot = selectedSlot {
                                write(preset: preset, to: slot)
                            }
                        },
                        secondaryButton: .cancel(Text("取消"))
                    )
                case .message(let text):
                    return Alert(title: Text("机身滤镜"), message: Text(text),
                                 dismissButton: .default(Text("知道了")))
                }
            }
            .sheet(isPresented: $showBackups) {
                PictCtrlBackupsView()
            }
        }
    }

    private var writeConfirmText: String {
        guard let preset = pendingPreset, let slot = selectedSlot else { return "" }
        let current = service.slotContents[slot]
        switch current {
        case .full(let name):
            return "把「\(preset.displayName)」写进 \(slot.label)？里面现在是「\(name)」，会先备份再覆盖。"
        default:
            return "把「\(preset.displayName)」写进 \(slot.label)？写之前会先备份这个槽原来的内容。"
        }
    }

    // MARK: - 槽位九宫格（用户发的参考样式：3×3 卡片，槽名 + 状态）
    // 九个槽一视同仁：不给 C9 加任何特殊标记（没有“推荐”角标、高亮底色）。

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    private var slotSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("写入目标")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(NikonTheme.textPrimary)
            if !service.isConnected {
                Text("相机没连上，先回控制页连上相机。")
                    .font(.system(size: 13))
                    .foregroundColor(NikonTheme.textSecondary)
            }
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(PictCtrlSlot.allCases) { slot in
                    slotCard(slot)
                }
            }
            if service.isReadingSlots {
                Text("正在读 C1–C9…")
                    .font(.system(size: 12))
                    .foregroundColor(NikonTheme.textTertiary)
            }
        }
        .padding(16)
        .background(NikonTheme.surfaceCard)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(NikonTheme.borderDim, lineWidth: 1.5))
    }

    private func slotCard(_ slot: PictCtrlSlot) -> some View {
        let content = service.slotContents[slot]
        let selectable: Bool = {
            guard service.isConnected, let content = content else { return false }
            switch content {
            case .empty, .full: return true
            case .paramsOnly, .unknown: return false
            }
        }()
        let isSelected = selectedSlot == slot
        return Button(action: {
            if selectable { selectedSlot = slot }
        }) {
            VStack(alignment: .leading, spacing: 6) {
                Text(slot.label)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(NikonTheme.textPrimary)
                Text(slotStateText(content))
                    .font(.system(size: 13))
                    .foregroundColor(NikonTheme.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(red: 0.97, green: 0.95, blue: 0.91))
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? NikonTheme.accentBlue : NikonTheme.borderDim,
                            lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!selectable)
        .opacity(selectable ? 1.0 : 0.6)
    }

    private func slotStateText(_ content: PictCtrlPayload.SlotContent?) -> String {
        guard let content = content else { return "未读取" }
        switch content {
        case .empty: return "空"
        case .paramsOnly: return "仅参数"
        case .full(let name): return name.isEmpty ? "已有配方" : name
        case .unknown: return "状态不明"
        }
    }

    // MARK: - 预设

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("内置滤镜（8 套）")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(NikonTheme.textPrimary)
            Text("写进相机后，不连手机、直接用这个槽拍照，直出就带风格。1D 曲线只改明暗影调，改不了色相。")
                .font(.system(size: 12))
                .foregroundColor(NikonTheme.textTertiary)
            ForEach(PictCtrlPresets.all) { preset in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preset.displayName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(NikonTheme.textPrimary)
                        Text(preset.desc)
                            .font(.system(size: 12))
                            .foregroundColor(NikonTheme.textSecondary)
                    }
                    Spacer()
                    Button("写入") {
                        pendingPreset = preset
                        activeAlert = .writeConfirm
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(canWrite ? NikonTheme.accentBlue : Color.gray)
                    .cornerRadius(9)
                    .disabled(!canWrite)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .background(NikonTheme.surfaceCard)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(NikonTheme.borderDim, lineWidth: 1.5))
    }

    private var canWrite: Bool {
        service.isConnected && selectedSlot != nil
    }

    // MARK: - 备份入口

    private var backupEntry: some View {
        Button(action: { showBackups = true }) {
            HStack {
                Image(systemName: "archivebox.fill")
                    .foregroundColor(NikonTheme.accentBlue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("备份")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(NikonTheme.textPrimary)
                    Text("每次写之前都会先备份这个槽，写坏了能重写回去（\(service.backups.count) 份）")
                        .font(.system(size: 12))
                        .foregroundColor(NikonTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(NikonTheme.textTertiary)
            }
            .padding(16)
            .background(NikonTheme.surfaceCard)
            .cornerRadius(18)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(NikonTheme.borderDim, lineWidth: 1.5))
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - 动作

    private func refresh() {
        service.refreshSlots { _ in
            // 默认选中第一个空槽；没有空槽就不预选，等用户自己点——九个槽一视同仁。
            if selectedSlot == nil {
                selectedSlot = PictCtrlSlot.allCases.first(where: { service.slotContents[$0] == .empty })
            }
        }
    }

    private func write(preset: PictCtrlPreset, to slot: PictCtrlSlot) {
        service.writePreset(preset, to: slot) { _, message in
            DispatchQueue.main.async {
                activeAlert = .message(message)
            }
        }
    }
}

// MARK: - 备份列表

public struct PictCtrlBackupsView: View {
    @ObservedObject var service = PictCtrlService.shared
    @Environment(\.presentationMode) private var presentationMode

    @State private var pendingBackup: PictCtrlBackup? = nil
    @State private var activeAlert: BackupAlert? = nil

    private enum BackupAlert: Identifiable {
        case restoreConfirm
        case message(String)
        var id: String {
            switch self {
            case .restoreConfirm: return "restoreConfirm"
            case .message: return "message"
            }
        }
    }

    public init() {}

    public var body: some View {
        NavigationView {
            Group {
                if service.backups.isEmpty {
                    VStack(spacing: 8) {
                        Text("还没有备份")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(NikonTheme.textPrimary)
                        Text("写一套滤镜进相机时，会先把那个槽原来的内容存到这里。")
                            .font(.system(size: 13))
                            .foregroundColor(NikonTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                } else {
                    List {
                        ForEach(service.backups) { backup in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(backup.slotLabel)
                                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                                        .foregroundColor(NikonTheme.textPrimary)
                                    Text("\(backup.byteCount) 字节")
                                        .font(.system(size: 12))
                                        .foregroundColor(NikonTheme.textSecondary)
                                    Spacer()
                                    Text(dateText(backup.createdAt))
                                        .font(.system(size: 12))
                                        .foregroundColor(NikonTheme.textTertiary)
                                }
                                if backup.restorable {
                                    Button("还原到 \(backup.slotLabel)") {
                                        pendingBackup = backup
                                        activeAlert = .restoreConfirm
                                    }
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(NikonTheme.accentBlue)
                                } else {
                                    Text("空槽或只有参数的备份，无法一键还原。")
                                        .font(.system(size: 12))
                                        .foregroundColor(NikonTheme.textTertiary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .background(NikonTheme.bgPure.ignoresSafeArea())
            .navigationTitle("备份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { presentationMode.wrappedValue.dismiss() }
                }
            }
            .alert(item: $activeAlert) { alert in
                switch alert {
                case .restoreConfirm:
                    return Alert(
                        title: Text("还原备份？"),
                        message: Text(restoreConfirmText),
                        primaryButton: .default(Text("还原")) {
                            if let backup = pendingBackup {
                                service.restoreBackup(backup) { _, message in
                                    DispatchQueue.main.async {
                                        activeAlert = .message(message)
                                    }
                                }
                            }
                        },
                        secondaryButton: .cancel(Text("取消"))
                    )
                case .message(let text):
                    return Alert(title: Text("备份"), message: Text(text),
                                 dismissButton: .default(Text("知道了")))
                }
            }
        }
    }

    private var restoreConfirmText: String {
        guard let backup = pendingBackup else { return "" }
        return "把这份备份重写回 \(backup.slotLabel)？写之前会先备份 \(backup.slotLabel) 现在的内容。"
    }

    private func dateText(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MM-dd HH:mm"
        return fmt.string(from: date)
    }
}
