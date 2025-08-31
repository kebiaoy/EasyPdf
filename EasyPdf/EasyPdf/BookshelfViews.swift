//
//  BookshelfViews.swift
//  EasyPdf
//
//  Created by kb on 2025/8/29.
//

import SwiftUI
import Foundation
import PDFKit
import QuickLook
import QuickLookThumbnailing

// MARK: - PDF缩略图生成器
class PDFThumbnailGenerator: ObservableObject {
    static let shared = PDFThumbnailGenerator()
    private let cache = NSCache<NSString, NSImage>()
    
    private init() {
        cache.countLimit = 100 // 限制缓存数量
    }
    
    func generateThumbnail(for url: URL, size: CGSize = CGSize(width: 120, height: 160)) -> NSImage? {
        let cacheKey = "\(url.path)_\(size.width)x\(size.height)" as NSString
        
        // 检查缓存
        if let cachedImage = cache.object(forKey: cacheKey) {
            return cachedImage
        }
        
        var thumbnail: NSImage?
        
        // 确保我们能访问文件
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("文件不存在: \(url.path)")
            return generateFallbackIcon(size: size)
        }
        
        // 方法1: 优先使用PDFKit直接渲染PDF第一页内容
        print("尝试使用PDFKit生成缩略图: \(url.lastPathComponent)")
        thumbnail = generatePDFKitThumbnail(for: url, size: size)
        
        if thumbnail != nil {
            print("PDFKit生成成功")
        } else {
            print("PDFKit生成失败，尝试QuickLook")
            // 方法2: 使用QuickLook生成真实PDF预览
            thumbnail = generateQuickLookThumbnail(for: url, size: size)
        }
        
        if thumbnail != nil {
            print("QuickLook生成成功")
        } else {
            print("QuickLook生成失败，使用备用方案")
            // 方法3: 最后的备用方案 - 通用PDF文档图标
            thumbnail = generateFallbackIcon(size: size)
        }
        
        // 缓存结果
        if let thumbnail = thumbnail {
            cache.setObject(thumbnail, forKey: cacheKey)
        }
        
        return thumbnail
    }
    
    private func generatePDFKitThumbnail(for url: URL, size: CGSize) -> NSImage? {
        // 尝试使用安全书签URL
        var targetURL = url
        var hasSecurityAccess = false
        
        if let securityScopedURL = DataManager.shared.getSecurityScopedURL(for: url) {
            targetURL = securityScopedURL
            hasSecurityAccess = targetURL.startAccessingSecurityScopedResource()
            print("使用安全书签URL访问文件: \(hasSecurityAccess)")
        }
        
        defer {
            if hasSecurityAccess {
                targetURL.stopAccessingSecurityScopedResource()
            }
        }
        
        // 尝试创建PDFDocument
        guard let pdfDocument = PDFDocument(url: targetURL) else {
            print("无法创建PDFDocument: \(url.lastPathComponent)")
            return nil
        }
        
        // 检查页面数量
        let pageCount = pdfDocument.pageCount
        print("PDF页面数: \(pageCount)")
        
        guard pageCount > 0,
              let firstPage = pdfDocument.page(at: 0) else {
            print("无法获取PDF第一页")
            return nil
        }
        
        // 获取页面边界
        let pageRect = firstPage.bounds(for: .mediaBox)
        print("PDF页面尺寸: \(pageRect)")
        
        guard pageRect.width > 0 && pageRect.height > 0 else {
            print("PDF页面尺寸无效")
            return nil
        }
        
        // 计算缩放比例，保持宽高比
        let scaleX = size.width / pageRect.width
        let scaleY = size.height / pageRect.height
        let scaleFactor = min(scaleX, scaleY)
        
        let scaledWidth = pageRect.width * scaleFactor
        let scaledHeight = pageRect.height * scaleFactor
        
        // 创建图像
        let thumbnail = NSImage(size: NSSize(width: scaledWidth, height: scaledHeight))
        
        thumbnail.lockFocus()
        
        // 设置高质量渲染上下文
        guard let context = NSGraphicsContext.current?.cgContext else {
            thumbnail.unlockFocus()
            print("无法获取图形上下文")
            return nil
        }
        
        // 设置渲染质量
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.interpolationQuality = .high
        
        // 填充白色背景
        context.setFillColor(CGColor.white)
        context.fill(CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight))
        
        // 设置变换
        context.saveGState()
        context.scaleBy(x: scaleFactor, y: scaleFactor)
        
        // 绘制PDF页面
        firstPage.draw(with: .mediaBox, to: context)
        
        context.restoreGState()
        thumbnail.unlockFocus()
        
        print("PDFKit缩略图生成成功，尺寸: \(scaledWidth)x\(scaledHeight)")
        return thumbnail
    }
    
    private func getPDFPreviewIcon(for url: URL, size: CGSize) -> NSImage? {
        // 获取系统为PDF文件生成的预览图标
        let workspace = NSWorkspace.shared
        
        // 获取文件的自定义图标（可能包含PDF预览）
        let icon = workspace.icon(forFile: url.path)
        
        // 检查图标是否包含PDF预览内容
        let iconSize = icon.size
        
        // 如果图标尺寸较大，可能包含预览内容
        if iconSize.width > 32 || iconSize.height > 32 {
            return resizeImage(icon, to: size)
        }
        
        // 尝试使用文件类型图标
        let fileType = url.pathExtension
        let typeIcon = workspace.icon(forFileType: fileType)
        return resizeImage(typeIcon, to: size)
    }
    
    private func resizeImage(_ image: NSImage, to size: CGSize) -> NSImage {
        let resizedImage = NSImage(size: size)
        resizedImage.lockFocus()
        
        // 计算保持宽高比的绘制区域
        let aspectRatio = image.size.width / image.size.height
        let targetAspectRatio = size.width / size.height
        
        var drawRect: NSRect
        if aspectRatio > targetAspectRatio {
            // 图像更宽，以宽度为准
            let height = size.width / aspectRatio
            drawRect = NSRect(x: 0, y: (size.height - height) / 2, width: size.width, height: height)
        } else {
            // 图像更高，以高度为准
            let width = size.height * aspectRatio
            drawRect = NSRect(x: (size.width - width) / 2, y: 0, width: width, height: size.height)
        }
        
        // 设置高质量插值
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: drawRect, from: NSRect(origin: .zero, size: image.size), operation: .sourceOver, fraction: 1.0)
        
        resizedImage.unlockFocus()
        return resizedImage
    }
    
    private func getSystemFileIcon(for url: URL, size: CGSize) -> NSImage {
        // 获取系统为该文件生成的图标（包含PDF预览）
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        return resizeImage(icon, to: size)
    }
    
    private func generateFallbackIcon(size: CGSize) -> NSImage? {
        let icon = NSImage(size: size)
        icon.lockFocus()
        
        // 绘制文档样式的背景
        let rect = NSRect(origin: .zero, size: size)
        
        // 渐变背景模拟纸张
        let gradient = NSGradient(colors: [
            NSColor.white,
            NSColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0)
        ])
        gradient?.draw(in: rect, angle: 45)
        
        // 绘制边框
        NSColor.systemGray.withAlphaComponent(0.3).setStroke()
        let borderPath = NSBezierPath(rect: rect.insetBy(dx: 1, dy: 1))
        borderPath.lineWidth = 1
        borderPath.stroke()
        
        // 绘制页面内容线条（模拟文档内容）
        NSColor.systemBlue.withAlphaComponent(0.2).setStroke()
        let lineSpacing = size.height / 8
        for i in 1...5 {
            let y = lineSpacing * CGFloat(i)
            let line = NSBezierPath()
            line.move(to: NSPoint(x: size.width * 0.15, y: y))
            line.line(to: NSPoint(x: size.width * 0.85, y: y))
            line.lineWidth = 1
            line.stroke()
        }
        
        // 绘制PDF标识
        let text = "PDF"
        let font = NSFont.boldSystemFont(ofSize: size.height * 0.12)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.systemRed
        ]
        
        let textSize = text.size(withAttributes: attributes)
        let textRect = NSRect(
            x: (size.width - textSize.width) / 2,
            y: size.height * 0.75,
            width: textSize.width,
            height: textSize.height
        )
        
        text.draw(in: textRect, withAttributes: attributes)
        icon.unlockFocus()
        
        print("生成备用PDF图标")
        return icon
    }
    
    private func generateQuickLookThumbnail(for url: URL, size: CGSize) -> NSImage? {
        if #available(macOS 10.15, *) {
            // 尝试使用安全书签URL
            var targetURL = url
            var hasSecurityAccess = false
            
            if let securityScopedURL = DataManager.shared.getSecurityScopedURL(for: url) {
                targetURL = securityScopedURL
                hasSecurityAccess = targetURL.startAccessingSecurityScopedResource()
                print("QuickLook使用安全书签URL访问文件: \(hasSecurityAccess)")
            } else {
                // 尝试直接访问
                hasSecurityAccess = url.startAccessingSecurityScopedResource()
                print("QuickLook直接访问文件: \(hasSecurityAccess)")
            }
            
            defer {
                if hasSecurityAccess {
                    targetURL.stopAccessingSecurityScopedResource()
                }
            }
            
            // 使用更高的scale以获得更清晰的图像
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            let request = QLThumbnailGenerator.Request(
                fileAt: targetURL,
                size: size,
                scale: scale,
                representationTypes: .thumbnail // 明确请求缩略图类型
            )
            
            let semaphore = DispatchSemaphore(value: 0)
            var resultImage: NSImage?
            var error: Error?
            
            print("开始QuickLook缩略图生成: \(url.lastPathComponent)")
            
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, genError in
                if let thumbnail = thumbnail {
                    resultImage = thumbnail.nsImage
                    print("QuickLook生成成功，图像尺寸: \(thumbnail.nsImage.size)")
                } else if let genError = genError {
                    error = genError
                    print("QuickLook缩略图生成失败: \(genError.localizedDescription)")
                }
                semaphore.signal()
            }
            
            // 设置超时时间，避免无限等待
            let timeout = DispatchTime.now() + .seconds(5)
            let result = semaphore.wait(timeout: timeout)
            
            if result == .timedOut {
                print("QuickLook缩略图生成超时")
                return nil
            }
            
            return resultImage
        }
        return nil
    }
}

// MARK: - PDF缩略图视图
struct PDFThumbnailView: View {
    let fileURL: URL
    let size: CGSize
    @StateObject private var thumbnailGenerator = PDFThumbnailGenerator.shared
    @State private var thumbnail: NSImage?
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else if isLoading {
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: size.width, height: size.height)
                    
                    VStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("加载中...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                // 备用方案：显示文档图标
                ZStack {
                    Rectangle()
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
                        .frame(width: size.width, height: size.height)
                    
                    VStack {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: size.width * 0.3))
                            .foregroundColor(.white)
                        
                        Text("PDF")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
            }
        }
        .cornerRadius(8)
        .onAppear {
            loadThumbnail()
        }
        .onChange(of: fileURL) { _ in
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        isLoading = true
        thumbnail = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            let generatedThumbnail = thumbnailGenerator.generateThumbnail(for: fileURL, size: size)
            
            DispatchQueue.main.async {
                self.thumbnail = generatedThumbnail
                self.isLoading = false
            }
        }
    }
}

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
                // 书本封面 - 使用真实PDF缩略图
                ZStack {
                    // PDF缩略图
                    PDFThumbnailView(
                        fileURL: fileURL,
                        size: CGSize(width: 120, height: 180)
                    )
                    .frame(height: 180)
                    
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
                    
                    // 悬停效果覆盖层
                    if isHovered {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.1))
                    }
                    
                    // 阴影和边框效果
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.black.opacity(0.1),
                                    Color.clear
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
                .scaleEffect(isSelected ? 1.05 : (isHovered ? 1.02 : 1.0))
                .shadow(
                    color: isSelected ? .blue.opacity(0.3) : .black.opacity(0.15),
                    radius: isSelected ? 10 : 6,
                    x: 0,
                    y: isSelected ? 6 : 3
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
