//
//  HistogramOverlayView.swift
//  Z30Control
//
//  专业电影机示波器：实时直方图与双声道立体声音量 VU 电平表
//

import SwiftUI

/// 实时直方图小组件 (支持折叠与拉伸)
public struct HistogramOverlayView: View {
    public let points: [Float]
    
    public var body: some View {
        ZStack(alignment: .bottom) {
            // 背景暗化微玻璃
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.8)
                )
            
            // 直方图波形走势
            GeometryReader { geo in
                Path { path in
                    guard !points.isEmpty else { return }
                    let step = geo.size.width / CGFloat(points.count - 1)
                    let height = geo.size.height
                    
                    path.move(to: CGPoint(x: 0, y: height))
                    for (index, val) in points.enumerated() {
                        let x = CGFloat(index) * step
                        let y = height - (CGFloat(val) * height)
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    path.addLine(to: CGPoint(x: geo.size.width, y: height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.7), Color.white.opacity(0.15)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .padding(4)
        }
        .frame(width: 90, height: 50)
    }
}

/// 视频录制双声道立体声 VU 电平表 (L/R)
public struct AudioVUMeterView: View {
    @State private var levelL: CGFloat = 0.65
    @State private var levelR: CGFloat = 0.60
    
    public var body: some View {
        HStack(spacing: 3) {
            VUMeterBar(level: levelL, channelName: "L")
            VUMeterBar(level: levelR, channelName: "R")
        }
        .frame(width: 22, height: 60)
        .padding(4)
        .background(Color.black.opacity(0.65))
        .cornerRadius(4)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.15), lineWidth: 0.8))
    }
}

struct VUMeterBar: View {
    let level: CGFloat
    let channelName: String
    
    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    Rectangle().fill(Color.white.opacity(0.15))
                    Rectangle()
                        .fill(level > 0.85 ? NikonTheme.tallyRed : (level > 0.7 ? NikonTheme.nikonYellow : NikonTheme.readyGreen))
                        .frame(height: geo.size.height * level)
                }
            }
            Text(channelName)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
        }
    }
}
