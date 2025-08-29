//
//  WorkspaceViews.swift
//  EasyPdf
//
//  Created by kb on 2025/8/29.
//

import SwiftUI
import Foundation

// MARK: - 工作空间面板
struct WorkspacePanel: View {
    @ObservedObject var dataManager: DataManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundColor(.blue)
                Text("工作空间")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            if dataManager.isWorkspaceValid() {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text(URL(fileURLWithPath: dataManager.workspacePath).lastPathComponent)
                            .font(.body)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    
                    Text(dataManager.workspacePath)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            } else {
                Text("未设置工作空间")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            Button(action: {
                FolderPicker.openFolderSelector { path in
                    if let path = path {
                        dataManager.setWorkspacePath(path)
                    }
                }
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text(dataManager.isWorkspaceValid() ? "更改工作空间" : "添加工作空间")
                }
                .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .gray.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

// MARK: - 最近文件面板
struct RecentFilesPanel: View {
    @ObservedObject var dataManager: DataManager
    let onFileSelected: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(.orange)
                Text("最近打开")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            if dataManager.recentFiles.isEmpty {
                VStack {
                    Image(systemName: "doc.text")
                        .font(.title2)
                        .foregroundColor(.gray.opacity(0.6))
                        .padding(.bottom, 4)
                    Text("暂无最近文件")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 12) {
                    ForEach(dataManager.recentFiles.prefix(8), id: \.self) { filePath in
                        Button(action: {
                            onFileSelected(filePath)
                        }) {
                            VStack(spacing: 6) {
                                Image(systemName: "doc.text.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                                    .frame(height: 30)
                                
                                Text(URL(fileURLWithPath: filePath).lastPathComponent)
                                    .font(.caption)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .frame(height: 24)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                            .background(Color.gray.opacity(0.05))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .gray.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

// MARK: - 左侧功能面板
struct LeftFunctionPanels: View {
    @StateObject private var dataManager = DataManager.shared
    let onFileSelected: (String) -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 工作空间面板
                WorkspacePanel(dataManager: dataManager)
                
                // 最近文件面板
                RecentFilesPanel(dataManager: dataManager, onFileSelected: onFileSelected)
                
                Spacer(minLength: 20)
            }
            .padding(16)
        }
        .background(Color.gray.opacity(0.03))
    }
}
