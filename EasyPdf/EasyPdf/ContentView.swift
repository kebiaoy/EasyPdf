//
//  ContentView.swift
//  EasyPdf
//
//  Created by kb on 2025/8/29.
//

import SwiftUI

// 标签页数据模型
struct TabItem: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let isHomePage: Bool
    
    static func == (lhs: TabItem, rhs: TabItem) -> Bool {
        lhs.id == rhs.id
    }
}

// 标签页管理器
class TabManager: ObservableObject {
    @Published var tabs: [TabItem] = []
    @Published var selectedTab: TabItem?
    
    init() {
        // 创建默认主页标签
        let homeTab = TabItem(title: "主页", isHomePage: true)
        tabs = [homeTab]
        selectedTab = homeTab
    }
    
    func addNewTab() {
        let newTab = TabItem(title: "新标签页 \(tabs.count)", isHomePage: false)
        tabs.append(newTab)
        selectedTab = newTab
    }
    
    func deleteTab(_ tab: TabItem) {
        guard !tab.isHomePage else { return } // 主页不能删除
        
        if let index = tabs.firstIndex(of: tab) {
            tabs.remove(at: index)
            
            // 如果删除的是当前选中的标签，切换到其他标签
            if selectedTab == tab {
                if index < tabs.count {
                    selectedTab = tabs[index]
                } else if !tabs.isEmpty {
                    selectedTab = tabs[tabs.count - 1]
                }
            }
        }
    }
}

// 分割线组件
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

// 主页分割视图
struct HomePageSplitView: View {
    @State private var leftPanelWidth: CGFloat = 300
    @State private var containerWidth: CGFloat = 800
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // 左侧面板
                VStack(alignment: .leading, spacing: 16) {
                    // 左侧标题
                    Text("文档列表")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding(.bottom, 8)
                    
                    // 左侧内容
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(1...10, id: \.self) { index in
                                HStack {
                                    Image(systemName: "doc.text.fill")
                                        .foregroundColor(.blue)
                                    VStack(alignment: .leading) {
                                        Text("文档 \(index)")
                                            .font(.headline)
                                        Text("PDF文档 - \(index * 234) KB")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.white)
                                .cornerRadius(8)
                                .shadow(color: .gray.opacity(0.2), radius: 2, x: 0, y: 1)
                            }
                        }
                    }
                }
                .frame(width: leftPanelWidth)
                .padding(16)
                .background(Color.gray.opacity(0.05))
                
                // 分割线
                SplitterView(
                    offset: $leftPanelWidth,
                    containerWidth: geometry.size.width
                )
                
                // 右侧面板
                VStack(spacing: 16) {
                    // 右侧标题
                    Text("PDF预览")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding(.bottom, 8)
                    
                    // 右侧内容
                    VStack {
                        Image(systemName: "doc.richtext")
                            .font(.system(size: 80))
                            .foregroundColor(.gray.opacity(0.6))
                        
                        Text("选择一个文档进行预览")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        
                        Text("从左侧列表中选择PDF文档")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(color: .gray.opacity(0.1), radius: 4, x: 0, y: 2)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(Color.gray.opacity(0.02))
            }
            .onAppear {
                containerWidth = geometry.size.width
                leftPanelWidth = min(leftPanelWidth, geometry.size.width / 2)
            }
            .onChange(of: geometry.size.width) { newWidth in
                containerWidth = newWidth
                // 确保左面板宽度不超过容器宽度的70%
                let maxLeftWidth = newWidth * 0.7
                if leftPanelWidth > maxLeftWidth {
                    leftPanelWidth = maxLeftWidth
                }
            }
        }
    }
}

// 标签页内容视图
struct TabContentView: View {
    let tab: TabItem
    
    var body: some View {
        if tab.isHomePage {
            HomePageSplitView()
        } else {
            VStack {
                Image(systemName: "doc.text")
                    .imageScale(.large)
                    .foregroundStyle(.green)
                Text(tab.title)
                    .font(.title2)
                    .fontWeight(.medium)
                Text("这是 \(tab.title) 的内容")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.gray.opacity(0.1))
        }
    }
}

// 单个标签页标签视图
struct TabLabelView: View {
    let tab: TabItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Button(action: onSelect) {
                HStack(spacing: 4) {
                    Image(systemName: tab.isHomePage ? "house.fill" : "doc.text")
                        .font(.caption)
                    Text(tab.title)
                        .font(.caption)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Color.blue : Color.clear)
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            
            // 只有非主页标签才显示删除按钮
            if !tab.isHomePage {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .frame(width: 14, height: 14)
            }
        }
        .padding(.horizontal, 4)
    }
}

struct ContentView: View {
    @StateObject private var tabManager = TabManager()
    
    var body: some View {
        VStack(spacing: 0) {
            // 标签栏
            HStack(spacing: 0) {
                // 标签页标签
                HStack(spacing: 2) {
                    ForEach(tabManager.tabs) { tab in
                        TabLabelView(
                            tab: tab,
                            isSelected: tabManager.selectedTab == tab,
                            onSelect: {
                                tabManager.selectedTab = tab
                            },
                            onDelete: {
                                tabManager.deleteTab(tab)
                            }
                        )
                    }
                }
                
                // 添加标签页按钮
                Button(action: {
                    tabManager.addNewTab()
                }) {
                    Image(systemName: "plus")
                        .font(.caption)
                        .frame(width: 20, height: 20)
                        .background(Color.gray.opacity(0.3))
                        .foregroundColor(.primary)
                        .cornerRadius(4)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.leading, 4)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.2))
            .border(Color.gray.opacity(0.3), width: 0.5)
            
            // 标签页内容区域
            if let selectedTab = tabManager.selectedTab {
                TabContentView(tab: selectedTab)
            } else {
                Text("没有选中的标签页")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

#Preview {
    ContentView()
}
