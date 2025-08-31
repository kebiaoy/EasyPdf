//
//  MainLayout.swift
//  EasyPdf
//
//  Created by kb on 2025/8/29.
//

import SwiftUI
import Foundation

// MARK: - 分割线组件
struct SplitterView: View {
    @Binding var offset: CGFloat
    let containerWidth: CGFloat
    let minWidth: CGFloat = 200
    
    @State private var isDragging = false
    
    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.5))
            .frame(width: 4)
            .background(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8) // 更大的点击区域
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        let newOffset = offset + value.translation.width
                        let maxOffset = containerWidth - minWidth
                        offset = max(minWidth, min(maxOffset, newOffset))
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .background(isDragging ? Color.blue.opacity(0.3) : Color.clear)
    }
}

// MARK: - 主页分割视图
struct HomePageSplitView: View {
    @State private var leftPanelWidth: CGFloat = 320
    @State private var containerWidth: CGFloat = 800
    let tabManager: TabManager
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // 左侧功能面板
                LeftFunctionPanels { filePath in
                    // 处理文件选择
                    NSWorkspace.shared.selectFile(filePath, inFileViewerRootedAtPath: "")
                }
                .frame(width: leftPanelWidth)
                
                // 分割线
                SplitterView(
                    offset: $leftPanelWidth,
                    containerWidth: geometry.size.width
                )
                
                // 右侧书架
                BookshelfView(tabManager: tabManager)
                    .frame(maxWidth: .infinity)
            }
            .onAppear {
                containerWidth = geometry.size.width
                leftPanelWidth = min(DataManager.shared.getLeftPanelWidth(), geometry.size.width * 0.4)
            }
            .onChange(of: geometry.size.width) { newWidth in
                containerWidth = newWidth
                // 确保左面板宽度不超过容器宽度的40%
                let maxLeftWidth = newWidth * 0.4
                if leftPanelWidth > maxLeftWidth {
                    leftPanelWidth = maxLeftWidth
                }
            }
            .onChange(of: leftPanelWidth) { newWidth in
                DataManager.shared.saveLeftPanelWidth(newWidth)
            }
        }
    }
}
