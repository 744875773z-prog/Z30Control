//
//  PictCtrlService.swift
//  Z30Control
//
//  v1.0.28：机身滤镜——把 614 字节载荷写进相机 C1–C9 槽位，直出就带风格。
//  安全流程照搬 1dlut-z30-filters：读槽分类 → 备份落盘 → 写 → 0.3 秒 →
//  读回逐字节比对，不一致只报告、不自动补救、不自动重试。
//  红线：App 里没有任何删除功能（0x90CE 绝不出现）；36 字节槽（相机菜单里
//  建过的）默认不碰——盖掉就无法逐字节还原；还原 = 重写备份文件，不走删除。
//  只有 614 字节非全零备份才能一键还原；空槽/36 字节备份无法一键还原。
//  注意：0x90CD 写 614 字节经 USB（ImageCaptureCore outData）和 Wi-Fi
//  （PTP/IP EndData）都还没在真机上试过——这是 v1.0.28 的未验证点。
//

import Foundation
import SwiftUI

/// 一份槽位备份（Documents/PictCtrlBackups 里的一个文件）
public struct PictCtrlBackup: Identifiable, Equatable {
    public let id: String // 文件名
    public let fileName: String
    public let slotLabel: String
    public let byteCount: Int
    public let createdAt: Date
    /// 只有 614 字节非全零备份才能一键还原（重写回去）
    public let restorable: Bool
}

public final class PictCtrlService: ObservableObject {
    public static let shared = PictCtrlService()

    /// 各槽最新读到的状态（nil = 还没读过）
    @Published public private(set) var slotContents: [PictCtrlSlot: PictCtrlPayload.SlotContent] = [:]
    @Published public private(set) var isReadingSlots = false
    @Published public private(set) var backups: [PictCtrlBackup] = []
    @Published public var lastMessage: String = ""

    public var backupsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("PictCtrlBackups", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private init() {
        refreshBackups()
    }

    // MARK: - 传输层选择

    private var isUsb: Bool { UsbCameraManager.shared.isUsbConnected }
    private var isWifi: Bool { CameraConnectionService.shared.isConnected }
    public var isConnected: Bool { isUsb || isWifi }

    /// 读一个槽的原始字节（USB / Wi-Fi 二选一）
    private func readSlotData(_ slot: PictCtrlSlot, completion: @escaping (Data?, UInt16?) -> Void) {
        if isUsb {
            UsbCameraManager.shared.getPictCtrlData(slot: slot.code, completion: completion)
        } else if isWifi {
            CameraConnectionService.shared.client.getPictCtrlData(slot: slot.code, completion: completion)
        } else {
            completion(nil, nil)
        }
    }

    /// 写一个槽（USB / Wi-Fi 二选一）。成功 = 严格拿到 0x2001。
    private func writeSlotData(_ slot: PictCtrlSlot, payload: Data, completion: @escaping (Bool) -> Void) {
        if isUsb {
            UsbCameraManager.shared.setPictCtrlData(slot: slot.code, payload: payload, completion: completion)
        } else if isWifi {
            CameraConnectionService.shared.client.setPictCtrlData(slot: slot.code, payload: payload, completion: completion)
        } else {
            completion(false)
        }
    }

    /// Wi-Fi 写之前先停取景流（USB 的停取景在 setPictCtrlData 内部做了）。
    /// 返回写之前是不是在取景，写完按这个恢复。
    private func pauseWifiLiveViewIfNeeded() -> Bool {
        let client = CameraConnectionService.shared.client
        guard isWifi, client.isStreamingLiveView else { return false }
        client.stopLiveView()
        return true
    }

    private func resumeWifiLiveViewIfNeeded(_ wasStreaming: Bool) {
        if wasStreaming {
            CameraConnectionService.shared.client.startLiveView()
        }
    }

    // MARK: - 读 C1–C9

    /// 逐个读 C1–C9，核对名字是否和相机菜单一致。
    public func refreshSlots(completion: ((Bool) -> Void)? = nil) {
        guard isConnected else { completion?(false); return }
        isReadingSlots = true
        let slots = PictCtrlSlot.allCases
        readNextSlot(slots, index: 0) { [weak self] in
            DispatchQueue.main.async {
                self?.isReadingSlots = false
                completion?(true)
            }
        }
    }

    private func readNextSlot(_ slots: [PictCtrlSlot], index: Int, done: @escaping () -> Void) {
        guard index < slots.count else { done(); return }
        let slot = slots[index]
        readSlotData(slot) { [weak self] data, _ in
            if let content = PictCtrlPayload.classify(data) {
                DispatchQueue.main.async { self?.slotContents[slot] = content }
            }
            self?.readNextSlot(slots, index: index + 1, done: done)
        }
    }

    // MARK: - 备份

    public func refreshBackups() {
        let dir = backupsDirectory
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])) ?? []
        var list: [PictCtrlBackup] = []
        for url in files where url.pathExtension == "bin" {
            let name = url.lastPathComponent
            // 文件名：C9_20261122-170000_614B.bin
            let parts = name.replacingOccurrences(of: ".bin", with: "").split(separator: "_")
            guard parts.count == 3 else { continue }
            let slotLabel = String(parts[0])
            let byteCount = Int(parts[2].replacingOccurrences(of: "B", with: "")) ?? 0
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let created = (attrs?[.creationDate] as? Date) ?? Date()
            let data = try? Data(contentsOf: url)
            let restorable = byteCount == PictCtrlPayload.size
                && (data.map { !$0.allSatisfy({ $0 == 0 }) } ?? false)
            list.append(PictCtrlBackup(id: name, fileName: name, slotLabel: slotLabel,
                                       byteCount: byteCount, createdAt: created, restorable: restorable))
        }
        DispatchQueue.main.async {
            self.backups = list.sorted { $0.createdAt > $1.createdAt }
        }
    }

    /// 把读到的槽内容存成备份文件。返回文件名，存失败返回 nil。
    private func saveBackup(slot: PictCtrlSlot, data: Data) -> String? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        let fileName = "\(slot.label)_\(fmt.string(from: Date()))_\(data.count)B.bin"
        let url = backupsDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url)
            refreshBackups()
            return fileName
        } catch {
            return nil
        }
    }

    // MARK: - 写滤镜（安全流程）

    /// 把一套内置预设写进目标槽。completion(ok, 说明)。
    /// 流程：读槽分类 → 备份落盘 → 写 → 0.3 秒 → 读回逐字节比对。
    /// 36 字节槽直接拒绝（相机菜单里建过的，盖掉回不去）；未知状态也拒绝。
    public func writePreset(_ preset: PictCtrlPreset, to slot: PictCtrlSlot,
                            completion: @escaping (Bool, String) -> Void) {
        guard let payload = preset.payload, payload.count == PictCtrlPayload.size else {
            completion(false, "配方数据不对（不是 614 字节），没写。")
            return
        }
        writePayload(payload, to: slot, sourceName: preset.displayName, completion: completion)
    }

    /// 还原一份备份：重写备份文件进它原来的槽（只接受 614 字节非全零备份）。
    public func restoreBackup(_ backup: PictCtrlBackup, completion: @escaping (Bool, String) -> Void) {
        guard backup.restorable else {
            completion(false, "这个备份是空槽或只有参数，无法一键还原（还原要靠删槽指令，App 里不做删除）。可以写一套新配方覆盖这个槽。")
            return
        }
        let url = backupsDirectory.appendingPathComponent(backup.fileName)
        guard let payload = try? Data(contentsOf: url), payload.count == PictCtrlPayload.size else {
            completion(false, "备份文件读不出来了。")
            return
        }
        guard let slot = PictCtrlSlot.allCases.first(where: { $0.label == backup.slotLabel }) else {
            completion(false, "备份的槽位认不出来了。")
            return
        }
        writePayload(payload, to: slot, sourceName: "备份 \(backup.fileName)", completion: completion)
    }

    /// 备份 → 写 → 读回校验的完整流程（预设写入和备份还原共用）。
    private func writePayload(_ payload: Data, to slot: PictCtrlSlot, sourceName: String,
                              completion: @escaping (Bool, String) -> Void) {
        guard isConnected else {
            completion(false, "相机没连上，先连上再写。")
            return
        }
        let wasStreamingWifi = pauseWifiLiveViewIfNeeded()
        // 1. 先读目标槽，分类
        readSlotData(slot) { [weak self] current, _ in
            guard let self = self else { return }
            guard let current = current, let content = PictCtrlPayload.classify(current) else {
                self.resumeWifiLiveViewIfNeeded(wasStreamingWifi)
                completion(false, "读 \(slot.label) 失败，没摸清槽里有什么，不敢写。")
                return
            }
            switch content {
            case .paramsOnly:
                self.resumeWifiLiveViewIfNeeded(wasStreamingWifi)
                completion(false, "\(slot.label) 是相机菜单里建的，只有参数，盖掉就回不去了。这个槽不碰，只写空槽。")
                return
            case .unknown(let bytes):
                self.resumeWifiLiveViewIfNeeded(wasStreamingWifi)
                completion(false, "\(slot.label) 读回 \(bytes) 字节，状态不明，不敢写。")
                return
            case .empty, .full:
                break
            }
            // 2. 备份落盘（写之前必须先存好，存不上就不写）
            guard self.saveBackup(slot: slot, data: current) != nil else {
                self.resumeWifiLiveViewIfNeeded(wasStreamingWifi)
                completion(false, "备份没存上，不敢写。")
                return
            }
            // 3. 写
            self.writeSlotData(slot, payload: payload) { ok in
                guard ok else {
                    self.resumeWifiLiveViewIfNeeded(wasStreamingWifi)
                    completion(false, "相机没认这条写入（没拿到 0x2001）。原来的内容还在备份里，没丢。")
                    return
                }
                // 4. 等 0.3 秒，读回逐字节比对
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
                    self.readSlotData(slot) { back, _ in
                        self.resumeWifiLiveViewIfNeeded(wasStreamingWifi)
                        guard let back = back else {
                            completion(false, "写完了，但读回失败，没法确认。去相机菜单里看一眼 \(slot.label) 有没有新配方。")
                            return
                        }
                        if back == payload {
                            DispatchQueue.main.async {
                                self.slotContents[slot] = .full(name: PictCtrlPayload.parseName(payload) ?? "")
                                self.lastMessage = "已写入 \(slot.label)，读回一致。"
                            }
                            completion(true, "已写入 \(slot.label)，读回逐字节一致。用这个槽拍一张看看风格。")
                        } else {
                            let diff = zip(back, payload).filter { $0 != $1 }.count
                            completion(false, "写完读回不一致（差 \(diff) 字节），没敢认成功。原内容在备份里。")
                        }
                    }
                }
            }
        }
    }
}
