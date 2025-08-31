//
//  TabModels.swift
//  EasyPdf
//
//  Created by kb on 2025/8/29.
//

import SwiftUI
import Foundation

// MARK: - 标签页数据模型
struct TabItem: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let isHomePage: Bool
    let pdfFileURL: URL?
    
    init(title: String, isHomePage: Bool, pdfFileURL: URL? = nil) {
        self.title = title
        self.isHomePage = isHomePage
        self.pdfFileURL = pdfFileURL
    }
    
    static func == (lhs: TabItem, rhs: TabItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - 标签页管理器
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
    
    func addPDFTab(fileURL: URL) {
        // 检查是否已经有相同文件的标签页
        if let existingTab = tabs.first(where: { $0.pdfFileURL?.path == fileURL.path }) {
            selectedTab = existingTab
            print("切换到已存在的PDF标签页: \(existingTab.title)")
            return
        }
        
        let fileName = fileURL.deletingPathExtension().lastPathComponent
        let newTab = TabItem(title: fileName, isHomePage: false, pdfFileURL: fileURL)
        tabs.append(newTab)
        selectedTab = newTab
        
        // 添加到最近文件
        DataManager.shared.addRecentFile(fileURL.path)
        print("创建新的PDF标签页: \(fileName)")
    }
    
    func deleteTab(_ tab: TabItem) {
        guard !tab.isHomePage else { return } // 主页不能删除
        
        if let index = tabs.firstIndex(of: tab) {
            // 如果是PDF标签页，清除其缓存
            if let pdfFileURL = tab.pdfFileURL {
                PDFStateManager.shared.clearState(for: pdfFileURL)
                print("清除PDF缓存: \(tab.title)")
            }
            
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

// MARK: - 单个标签页标签视图
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

// MARK: - 标签页内容视图
struct TabContentView: View {
    let tab: TabItem
    let tabManager: TabManager
    
    var body: some View {
        if tab.isHomePage {
            HomePageSplitView(tabManager: tabManager)
                .id("home-\(tab.id)")
        } else if let pdfFileURL = tab.pdfFileURL {
            PDFViewerView(fileURL: pdfFileURL)
                .id("pdf-\(tab.id)-\(pdfFileURL.path.hashValue)")
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
            .id("content-\(tab.id)")
        }
    }
}
