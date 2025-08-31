//
//  DataManager.swift
//  EasyPdf
//
//  Created by kb on 2025/8/29.
//

import SwiftUI
import Foundation

// MARK: - 数据持久化管理类
class DataManager: ObservableObject {
    static let shared = DataManager()
    
    // UserDefaults keys
    private enum Keys {
        static let workspacePath = "workspacePath"
        static let workspaceBookmark = "workspaceBookmark"
        static let recentFiles = "recentFiles"
        static let windowFrame = "windowFrame"
        static let leftPanelWidth = "leftPanelWidth"
    }
    
    @Published var workspacePath: String = ""
    @Published var recentFiles: [String] = []
    
    private init() {
        loadData()
    }
    
    // 加载数据
    private func loadData() {
        workspacePath = UserDefaults.standard.string(forKey: Keys.workspacePath) ?? ""
        recentFiles = UserDefaults.standard.stringArray(forKey: Keys.recentFiles) ?? []
    }
    
    // 保存工作空间路径
    func setWorkspacePath(_ path: String) {
        workspacePath = path
        UserDefaults.standard.set(path, forKey: Keys.workspacePath)
        
        // 创建和保存安全书签
        let url = URL(fileURLWithPath: path)
        do {
            let bookmarkData = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmarkData, forKey: Keys.workspaceBookmark)
        } catch {
            print("无法创建书签: \(error)")
        }
    }
    
    // 添加最近文件
    func addRecentFile(_ filePath: String) {
        // 移除重复项
        recentFiles.removeAll { $0 == filePath }
        // 添加到开头
        recentFiles.insert(filePath, at: 0)
        // 限制最多10个
        if recentFiles.count > 10 {
            recentFiles = Array(recentFiles.prefix(10))
        }
        UserDefaults.standard.set(recentFiles, forKey: Keys.recentFiles)
    }
    
    // 清除最近文件
    func clearRecentFiles() {
        recentFiles.removeAll()
        UserDefaults.standard.removeObject(forKey: Keys.recentFiles)
    }
    
    // 保存左面板宽度
    func saveLeftPanelWidth(_ width: CGFloat) {
        UserDefaults.standard.set(width, forKey: Keys.leftPanelWidth)
    }
    
    // 获取左面板宽度
    func getLeftPanelWidth() -> CGFloat {
        let width = UserDefaults.standard.double(forKey: Keys.leftPanelWidth)
        return width > 0 ? CGFloat(width) : 320 // 默认320
    }
    
    // 检查工作空间是否有效
    func isWorkspaceValid() -> Bool {
        guard !workspacePath.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: workspacePath)
    }
    
    // 获取工作空间中的PDF文件
    func getPDFFilesInWorkspace() -> [URL] {
        guard isWorkspaceValid() else { return [] }
        
        let workspaceURL = URL(fileURLWithPath: workspacePath)
        
        // 尝试使用安全书签访问文件夹
        var stale = false
        var securityScopedURL: URL?
        
        if let bookmarkData = UserDefaults.standard.data(forKey: Keys.workspaceBookmark) {
            do {
                securityScopedURL = try URL(resolvingBookmarkData: bookmarkData, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
                
                if stale {
                    print("书签已过期，需要重新选择文件夹")
                    // 清除过期的书签
                    UserDefaults.standard.removeObject(forKey: Keys.workspaceBookmark)
                    return []
                }
                
                // 开始访问安全范围的资源
                guard let scopedURL = securityScopedURL, scopedURL.startAccessingSecurityScopedResource() else {
                    print("无法访问安全范围的资源")
                    return []
                }
                
                defer {
                    scopedURL.stopAccessingSecurityScopedResource()
                }
                
                let contents = try FileManager.default.contentsOfDirectory(
                    at: scopedURL,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: .skipsHiddenFiles
                )
                
                // 为每个PDF文件创建带有安全书签的URL
                let pdfFiles = contents.filter { url in
                    url.pathExtension.lowercased() == "pdf"
                }.sorted { $0.lastPathComponent < $1.lastPathComponent }
                
                return pdfFiles.compactMap { fileURL in
                    // 为每个文件创建安全书签
                    do {
                        let fileBookmarkData = try fileURL.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                        // 保存文件书签供后续使用
                        UserDefaults.standard.set(fileBookmarkData, forKey: "file_bookmark_\(fileURL.lastPathComponent)")
                        return fileURL
                    } catch {
                        print("无法为文件创建书签: \(fileURL.lastPathComponent), 错误: \(error)")
                        return fileURL // 即使无法创建书签也返回URL
                    }
                }
                
            } catch {
                print("无法解析书签或访问文件夹: \(error)")
                return []
            }
        } else {
            // 如果没有书签，尝试直接访问（可能会失败）
            do {
                let contents = try FileManager.default.contentsOfDirectory(
                    at: workspaceURL,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: .skipsHiddenFiles
                )
                
                return contents.filter { url in
                    url.pathExtension.lowercased() == "pdf"
                }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            } catch {
                print("获取工作空间文件失败: \(error)")
                print("请重新选择工作空间文件夹以授予访问权限")
                return []
            }
        }
    }
    
    // 获取文件的安全书签URL
    func getSecurityScopedURL(for fileURL: URL) -> URL? {
        let bookmarkKey = "file_bookmark_\(fileURL.lastPathComponent)"
        
        if let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) {
            do {
                var stale = false
                let securityScopedURL = try URL(resolvingBookmarkData: bookmarkData, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
                
                if stale {
                    print("文件书签已过期: \(fileURL.lastPathComponent)")
                    UserDefaults.standard.removeObject(forKey: bookmarkKey)
                    return nil
                }
                
                return securityScopedURL
            } catch {
                print("无法解析文件书签: \(error)")
                UserDefaults.standard.removeObject(forKey: bookmarkKey)
                return nil
            }
        }
        
        return nil
    }
}

// MARK: - 文件夹选择器
struct FolderPicker: NSViewRepresentable {
    @Binding var selectedPath: String
    let onPathSelected: (String) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
    
    static func openFolderSelector(completion: @escaping (String?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.title = "选择工作空间文件夹"
        panel.prompt = "选择"
        panel.message = "选择包含PDF文件的文件夹作为工作空间"
        
        // 设置默认目录为用户文档文件夹
        panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                // 确保选择的URL具有安全范围访问权限
                _ = url.startAccessingSecurityScopedResource()
                completion(url.path)
                url.stopAccessingSecurityScopedResource()
            } else {
                completion(nil)
            }
        }
    }
}
