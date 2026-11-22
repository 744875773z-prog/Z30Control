//
//  FilteredCaptureService.swift
//  Z30Control
//
//  v1.0.39：拍完在手机上加滤镜存一份——取景页选了非“原图”的预览滤镜
//  时点快门，拍完自动把带滤镜的版本存一份到系统相册，相机卡里还是原片。
//  背景：取景页的预览滤镜只改手机屏幕显示（LivePreviewRenderer），
//  从不写相机；快门是 InitiateCapture，照片按相机自己的设置存到卡里。
//  所以预览时看着有滤镜、存下来的还是原片——本服务把“拍完补一张滤镜版”
//  接在快门后面：
//  触发：只在快门那一刻选了非“原图”预设时走；选“原图”什么都不做。
//  快门那一刻把选中的预设记下来（快门后中途再换滤镜不影响这次）。
//  取片：优先等相机的 ObjectAdded 事件拿新对象句柄（Wi-Fi 走事件通道、
//  USB 走拍后复查插进图库的通知），拿不到就轮询 GetObjectHandles，
//  用拍前快照做差集认新照片；然后 GetObject 下全分辨率原图。
//  渲染：复用取景预览同一套烘焙（LivePreviewRenderer.applyPreview——
//  1D LUT 烘 32³ CIColorCube + 饱和度），不抄一份数学；全分辨率，
//  只在最后做一次最高质量 JPEG 编码（1.0）。
//  保存：走图库批量保存同一条存相册通道（MediaSyncService）。
//  反馈：存好 / 哪步失败了都由调用方给轻提示；不管成败都不动卡里原片，
//  不卡快门、不冻取景（下载渲染全在后台串行队列上；USB 下原图那一下
//  先停取景帧拉取——ICC 下载和取景抢 PTP 通道会报 -9934，下完恢复；
//  暂停是计数式的，不会把拍后复查那边的暂停提前放掉）。
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

public final class FilteredCaptureService {
    public static let shared = FilteredCaptureService()

    public enum Transport { case usb, wifi }

    public enum SaveError: Error {
        case notFound       // 超时没找到刚拍的照片
        case disconnected   // 下载时相机已断开
        case downloadFailed // 下不到原图
        case notJPEG        // 原图不是 JPEG（RAW 暂不支持滤镜版）
        case renderFailed   // 滤镜渲染失败
        case saveFailed     // 写不进系统相册

        public var message: String {
            switch self {
            case .notFound: return "没找到刚拍的照片"
            case .disconnected: return "相机已断开"
            case .downloadFailed: return "原图下载失败"
            case .notJPEG: return "原图不是 JPEG，暂不支持"
            case .renderFailed: return "滤镜渲染失败"
            case .saveFailed: return "写不进相册"
            }
        }
    }

    public enum Outcome {
        case saved
        case failed(SaveError)
    }

    private final class Request {
        let id = UUID()
        let preset: PictCtrlPreset
        let transport: Transport
        var baseline: Set<UInt32>?
        var baselineReady = false
        let completion: (Outcome) -> Void

        init(preset: PictCtrlPreset, transport: Transport,
             baseline: Set<UInt32>?, completion: @escaping (Outcome) -> Void) {
            self.preset = preset
            self.transport = transport
            self.baseline = baseline
            self.completion = completion
        }
    }

    private let workQueue = DispatchQueue(label: "com.z30control.filteredcapture", qos: .userInitiated)
    private var pending: [Request] = []
    private var active: Request?
    private var activeObserverID: UUID?
    private var activeFinished = false
    private var activeDeadline: Date = .distantPast
    private let pollInterval: TimeInterval = 1.5
    private let waitTimeout: TimeInterval = 20

    private init() {}

    /// 拍完保存滤镜版。baseline：USB 传拍前快照（capturePhoto 在发快门前
    /// 记下的卡内句柄）；Wi-Fi 传 nil，本服务在入队时立刻读一次当基线
    /// （新照片还没写完卡，这时读到的就是“拍之前”的集合）。
    /// 一次只跑一个请求，多拍的按快门顺序排队（基线各记各的，不会认错照片）。
    public func enqueueFilteredSave(preset: PictCtrlPreset, transport: Transport,
                                    baselineHandles: Set<UInt32>?,
                                    completion: @escaping (Outcome) -> Void) {
        workQueue.async { [weak self] in
            guard let self = self else { return }
            let req = Request(preset: preset, transport: transport,
                              baseline: baselineHandles, completion: completion)
            self.pending.append(req)
            if transport == .wifi, baselineHandles == nil {
                // Wi-Fi 无快照：入队当下立刻读基线；读不到（空集合）就只靠事件。
                CameraConnectionService.shared.client.getObjectHandles { [weak self] handles in
                    guard let self = self else { return }
                    self.workQueue.async {
                        req.baseline = handles.isEmpty ? nil : Set(handles)
                        req.baselineReady = true
                        self.pump()
                    }
                }
            } else {
                req.baselineReady = true
            }
            self.pump()
        }
    }

    // MARK: - 队列调度

    private func pump() {
        guard active == nil else { return }
        guard let req = pending.first(where: { $0.baselineReady }) else { return }
        pending.removeAll { $0.id == req.id }
        active = req
        activeFinished = false
        activeDeadline = Date().addingTimeInterval(waitTimeout)
        // 事件快路：Wi-Fi 的 ObjectAdded、USB 拍后复查插进图库的新对象
        // 都会通知到这里；比轮询快，也比轮询先到。
        activeObserverID = MediaSyncService.shared.addObjectAddedObserver { [weak self] handle in
            guard let self = self else { return }
            self.workQueue.async { self.onObjectAdded(handle) }
        }
        pollTick(for: req.id)
    }

    // MARK: - 等新照片：事件优先，轮询兜底

    private func onObjectAdded(_ handle: UInt32) {
        guard let req = active, !activeFinished else { return }
        // 事件里也可能是旧对象（比如重连后补推的事件）：在基线里就不是新拍的。
        if let baseline = req.baseline, baseline.contains(handle) { return }
        foundNewObject(handle, for: req)
    }

    private func pollTick(for requestID: UUID) {
        guard let req = active, req.id == requestID, !activeFinished else { return }
        if Date() > activeDeadline {
            finishActive(outcome: .failed(.notFound))
            return
        }
        guard req.baseline != nil else {
            // 无基线（Wi-Fi 基线没读到）：只靠事件，继续等到超时。
            workQueue.asyncAfter(deadline: .now() + pollInterval) { [weak self] in
                self?.pollTick(for: requestID)
            }
            return
        }
        fetchHandles(transport: req.transport) { [weak self] handles in
            guard let self = self else { return }
            self.workQueue.async {
                guard let cur = self.active, cur.id == requestID, !self.activeFinished else { return }
                if let handles = handles {
                    let baseline = cur.baseline ?? []
                    // 句柄按拍摄顺序递增，取不在基线里的最大一个——就是刚拍的。
                    if let newest = handles.filter({ !baseline.contains($0) }).max() {
                        self.foundNewObject(newest, for: cur)
                        return
                    }
                }
                // 没找到（读句柄失败也一样）：继续等到超时，不立刻报错。
                self.workQueue.asyncAfter(deadline: .now() + self.pollInterval) { [weak self] in
                    self?.pollTick(for: requestID)
                }
            }
        }
    }

    private func fetchHandles(transport: Transport, completion: @escaping ([UInt32]?) -> Void) {
        switch transport {
        case .usb:
            UsbCameraManager.shared.fetchAllObjectHandlesPublic(completion: completion)
        case .wifi:
            CameraConnectionService.shared.client.getObjectHandles { handles in
                completion(handles)
            }
        }
    }

    private func foundNewObject(_ handle: UInt32, for req: Request) {
        guard !activeFinished else { return }
        activeFinished = true
        downloadAndSave(handle: handle, request: req)
    }

    private func finishActive(outcome: Outcome) {
        guard let req = active else { return }
        activeFinished = true
        if let oid = activeObserverID {
            MediaSyncService.shared.removeObjectAddedObserver(oid)
            activeObserverID = nil
        }
        active = nil
        DispatchQueue.main.async { req.completion(outcome) }
        pump()
    }

    // MARK: - 下载 + 渲染 + 保存（全在后台，不碰主线程）

    private func downloadAndSave(handle: UInt32, request req: Request) {
        switch req.transport {
        case .usb:
            guard UsbCameraManager.shared.isUsbConnected else {
                finishActive(outcome: .failed(.disconnected))
                return
            }
            // USB：ICC 下载和取景抢 PTP 通道会报 -9934，下原图前先停取景帧
            // 拉取（计数式暂停，拍后复查那边还停着就不会提前恢复），下完恢复。
            // pause/resume 只在主线程调用。
            DispatchQueue.main.async {
                UsbCameraManager.shared.pauseLiveViewFetching()
                UsbCameraManager.shared.downloadRawObjectData(handle: handle, filename: "DSC_\(handle).JPG") { [weak self] data in
                    guard let self = self else { return }
                    DispatchQueue.main.async { UsbCameraManager.shared.resumeLiveViewFetching() }
                    self.workQueue.async { self.renderAndSave(data: data, request: req) }
                }
            }
        case .wifi:
            guard CameraConnectionService.shared.client.isSessionOpen else {
                finishActive(outcome: .failed(.disconnected))
                return
            }
            // Wi-Fi：命令走串行队列，取景帧在事务忙时自动跳过，不用另停取景。
            CameraConnectionService.shared.client.getObject(handle: handle) { [weak self] data in
                guard let self = self else { return }
                self.workQueue.async { self.renderAndSave(data: data, request: req) }
            }
        }
    }

    /// 渲染并保存：JPEG 魔数校验 → 全分辨率解码 → 复用取景预览同一套
    /// 烘焙（LivePreviewRenderer.applyPreview）→ 只做一次 JPEG 编码 → 存相册。
    private func renderAndSave(data: Data?, request req: Request) {
        guard let data = data, !data.isEmpty else {
            finishActive(outcome: .failed(.downloadFailed))
            return
        }
        // JPEG 魔数 FF D8 FF；不是 JPEG（比如 NEF）就报不支持，不硬解。
        guard data.count >= 3, data[0] == 0xFF, data[1] == 0xD8, data[2] == 0xFF else {
            finishActive(outcome: .failed(.notJPEG))
            return
        }
        guard let image = UIImage(data: data) else {
            finishActive(outcome: .failed(.notJPEG))
            return
        }
        // 复用预览的烘焙函数（cubeData + 饱和度），不抄一份数学；
        // 全分辨率渲染，不缩小。
        guard let rendered = LivePreviewRenderer.shared.applyPreview(to: image, preset: req.preset),
              let jpeg = rendered.jpegData(compressionQuality: 1.0) else {
            finishActive(outcome: .failed(.renderFailed))
            return
        }
        // 存相册走图库批量保存同一条通道；卡里原片不动。
        MediaSyncService.shared.saveImageDataToPhotos(jpeg, filename: "DSC_filtered.JPG") { [weak self] ok in
            guard let self = self else { return }
            self.workQueue.async {
                self.finishActive(outcome: ok ? .saved : .failed(.saveFailed))
            }
        }
    }
}
