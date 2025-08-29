//
//  BookshelfViews.swift
//  EasyPdf
//
//  Created by kb on 2025/8/29.
//

import SwiftUI
import Foundation

// MARK: - 书架风格的PDF展示
struct BookshelfView: View {
    @StateObject private var dataManager = DataManager.shared
    @State private var pdfFiles: [URL] = []
    @State private var selectedFile: URL?
    
    let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 标题栏
            HStack {
                Image(systemName: "books.vertical.fill")
                    .font(.title2)
                    .foregroundColor(.brown)
                Text("书架")
                    .font(.title)
                    .fontWeight(.bold)
                Spacer()
                
                Text("\(pdfFiles.count) 本书")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Button(action: {
                    refreshFileList()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            // 书架内容
            if !dataManager.isWorkspaceValid() {
                VStack(spacing: 20) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 80))
                        .foregroundColor(.gray.opacity(0.4))
                    
                    VStack(spacing: 8) {
                        Text("书架空空如也")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        Text("请先在左侧添加工作空间来展示您的PDF收藏")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 40)
            } else if pdfFiles.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "tray")
                        .font(.system(size: 80))
                        .foregroundColor(.gray.opacity(0.4))
                    
                    VStack(spacing: 8) {
                        Text("工作空间中没有PDF文件")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        Text("请在工作空间中添加一些PDF文件")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 40)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(pdfFiles, id: \.self) { fileURL in
                            BookItemView(
                                fileURL: fileURL,
                                isSelected: selectedFile == fileURL,
                                onTap: {
                                    selectedFile = fileURL
                                    dataManager.addRecentFile(fileURL.path)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
        .onAppear {
            refreshFileList()
        }
        .onChange(of: dataManager.workspacePath) { _ in
            refreshFileList()
            selectedFile = nil
        }
    }
    
    private func refreshFileList() {
        pdfFiles = dataManager.getPDFFilesInWorkspace()
    }
}

// MARK: - 书本项目视图
struct BookItemView: View {
    let fileURL: URL
    let isSelected: Bool
    let onTap: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // 书本封面
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.blue.opacity(0.8),
                                    Color.blue.opacity(0.6)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 180)
                    
                    VStack {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white)
                            .padding(.bottom, 8)
                        
                        Text("PDF")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    
                    // 选中状态指示器
                    if isSelected {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(.green)
                                    .background(Color.white.clipShape(Circle()))
                                    .padding(8)
                            }
                            Spacer()
                        }
                    }
                    
                    // 悬停效果
                    if isHovered {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.1))
                    }
                }
                .scaleEffect(isSelected ? 1.05 : (isHovered ? 1.02 : 1.0))
                .shadow(
                    color: isSelected ? .blue.opacity(0.3) : .black.opacity(0.1),
                    radius: isSelected ? 8 : 4,
                    x: 0,
                    y: isSelected ? 4 : 2
                )
                
                // 文件名
                VStack(spacing: 4) {
                    Text(fileURL.lastPathComponent)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .truncationMode(.middle)
                    
                    if let fileSize = getFileSize(url: fileURL) {
                        Text(fileSize)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(height: 40)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
    
    private func getFileSize(url: URL) -> String? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? Int64 {
                let formatter = ByteCountFormatter()
                formatter.allowedUnits = [.useKB, .useMB]
                formatter.countStyle = .file
                return formatter.string(fromByteCount: fileSize)
            }
        } catch {
            print("获取文件大小失败: \(error)")
        }
        return nil
    }
}
