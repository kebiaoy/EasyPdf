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

// 标签页内容视图
struct TabContentView: View {
    let tab: TabItem
    
    var body: some View {
        VStack {
            if tab.isHomePage {
                Image(systemName: "house.fill")
                    .imageScale(.large)
                    .foregroundStyle(.blue)
                Text("欢迎来到主页")
                    .font(.title2)
                    .fontWeight(.medium)
                Text("这是默认的主页内容")
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "doc.text")
                    .imageScale(.large)
                    .foregroundStyle(.green)
                Text(tab.title)
                    .font(.title2)
                    .fontWeight(.medium)
                Text("这是 \(tab.title) 的内容")
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.1))
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
