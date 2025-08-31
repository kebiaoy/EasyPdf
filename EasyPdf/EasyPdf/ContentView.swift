//
//  ContentView.swift
//  EasyPdf
//
//  Created by kb on 2025/8/29.
//

import SwiftUI

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
                TabContentView(tab: selectedTab, tabManager: tabManager)
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
