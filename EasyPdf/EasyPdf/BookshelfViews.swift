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
import UniformTypeIdentifiers

// MARK: - PDF状态管理
struct PDFViewState {
    var document: PDFDocument?
    var currentPage: PDFPage?
    var scaleFactor: CGFloat = 1.0
    var displayMode: PDFDisplayMode = .singlePageContinuous
    var isLoaded: Bool = false
    var errorMessage: String?
}

// MARK: - PDF状态缓存管理器
class PDFStateManager: ObservableObject {
    static let shared = PDFStateManager()
    
    @Published private var pdfStates: [String: PDFViewState] = [:]
    @Published var lastUpdatedURL: String = ""
    
    private init() {}
    
    func getState(for fileURL: URL) -> PDFViewState {
        let key = fileURL.path
        let state = pdfStates[key] ?? PDFViewState()
        print("获取PDF状态: \(fileURL.lastPathComponent) -> 已加载: \(state.isLoaded)")
        return state
    }
    
    func setState(_ state: PDFViewState, for fileURL: URL) {
        let key = fileURL.path
        pdfStates[key] = state
        lastUpdatedURL = key
        print("保存PDF状态: \(fileURL.lastPathComponent) -> 已加载: \(state.isLoaded)")
    }
    
    func clearState(for fileURL: URL) {
        let key = fileURL.path
        pdfStates.removeValue(forKey: key)
        print("清除PDF状态: \(fileURL.lastPathComponent)")
    }
    
    func clearAllStates() {
        pdfStates.removeAll()
        print("清除所有PDF状态")
    }
    
    func hasState(for fileURL: URL) -> Bool {
        let key = fileURL.path
        return pdfStates[key]?.isLoaded ?? false
    }
}

// MARK: - PDF查看器
struct PDFViewerView: View {
    let fileURL: URL
    @StateObject private var stateManager = PDFStateManager.shared
    @State private var viewState: PDFViewState
    @State private var isLoading: Bool
    
    init(fileURL: URL) {
        self.fileURL = fileURL
        let initialState = PDFStateManager.shared.getState(for: fileURL)
        self._viewState = State(initialValue: initialState)
        self._isLoading = State(initialValue: !initialState.isLoaded)
    }
    
    var body: some View {
        VStack {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("加载PDF文档中...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = viewState.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.orange)
                    
                    Text("无法加载PDF文档")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text(errorMessage)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button("重新加载") {
                        reloadPDF()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let pdfDocument = viewState.document {
                CachedPDFKitView(
                    fileURL: fileURL,
                    document: pdfDocument,
                    viewState: $viewState
                )
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    
                    Text("PDF文档为空")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            print("PDF查看器出现: \(fileURL.lastPathComponent)")
            syncStateAndLoad()
        }
        .onDisappear {
            print("PDF查看器消失: \(fileURL.lastPathComponent)")
            // 保存当前状态
            stateManager.setState(viewState, for: fileURL)
        }
        .onChange(of: fileURL) { newURL in
            print("PDF文件URL变化: \(newURL.lastPathComponent)")
            syncStateAndLoad()
        }
    }
    
    private func syncStateAndLoad() {
        // 从状态管理器获取最新状态
        let latestState = stateManager.getState(for: fileURL)
        
        // 如果状态已加载，直接同步
        if latestState.isLoaded {
            print("PDF已缓存，同步状态: \(fileURL.lastPathComponent)")
            viewState = latestState
            isLoading = false
        } else {
            print("PDF未缓存，开始加载: \(fileURL.lastPathComponent)")
            loadPDF()
        }
    }
    
    private func loadPDFIfNeeded() {
        // 如果已经加载过，直接返回
        if viewState.isLoaded {
            print("PDF已缓存，无需重新加载: \(fileURL.lastPathComponent)")
            return
        }
        
        loadPDF()
    }
    
    private func reloadPDF() {
        // 清除缓存状态，强制重新加载
        stateManager.clearState(for: fileURL)
        viewState = PDFViewState()
        loadPDF()
    }
    
    private func loadPDF() {
        isLoading = true
        viewState.errorMessage = nil
        viewState.document = nil
        
        print("开始加载PDF: \(fileURL.lastPathComponent)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            // 验证文件URL
            guard self.fileURL.isFileURL else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.viewState.errorMessage = "无效的文件URL。"
                }
                return
            }
            
            // 验证文件存在
            guard FileManager.default.fileExists(atPath: self.fileURL.path) else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.viewState.errorMessage = "PDF文件不存在或已被移动。路径：\(self.fileURL.path)"
                }
                return
            }
            
            // 尝试使用安全书签访问文件
            var targetURL = self.fileURL
            var hasSecurityAccess = false
            
            if let securityScopedURL = DataManager.shared.getSecurityScopedURL(for: self.fileURL) {
                targetURL = securityScopedURL
                hasSecurityAccess = targetURL.startAccessingSecurityScopedResource()
                print("PDF查看器使用安全书签URL访问文件: \(hasSecurityAccess)")
            } else {
                // 尝试直接访问
                hasSecurityAccess = self.fileURL.startAccessingSecurityScopedResource()
                print("PDF查看器直接访问文件: \(hasSecurityAccess)")
            }
            
            defer {
                if hasSecurityAccess {
                    targetURL.stopAccessingSecurityScopedResource()
                }
            }
            
            // 检查是否有访问权限
            guard hasSecurityAccess else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.viewState.errorMessage = "无法访问PDF文件，可能需要重新选择工作空间文件夹以获取权限。"
                }
                return
            }
            
            // 加载PDF文档
            guard let document = PDFDocument(url: targetURL) else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.viewState.errorMessage = "无法读取PDF文件，文件可能已损坏或格式不正确。"
                }
                return
            }
            
            // 检查PDF是否有页面
            guard document.pageCount > 0 else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.viewState.errorMessage = "PDF文档没有任何页面。"
                }
                return
            }
            
            DispatchQueue.main.async {
                self.viewState.document = document
                self.viewState.isLoaded = true
                self.isLoading = false
                print("PDF文档加载成功，页面数: \(document.pageCount)")
                
                // 立即保存到缓存
                self.stateManager.setState(self.viewState, for: self.fileURL)
            }
        }
    }
}

// MARK: - 缓存版PDFKit包装器
struct CachedPDFKitView: NSViewRepresentable {
    let fileURL: URL
    let document: PDFDocument
    @Binding var viewState: PDFViewState
    @StateObject private var stateManager = PDFStateManager.shared
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayDirection = .vertical
        pdfView.displayMode = viewState.displayMode
        pdfView.displaysPageBreaks = true
        
        // 恢复之前的页面和缩放状态
        if let currentPage = viewState.currentPage {
            pdfView.go(to: currentPage)
        }
        
        if viewState.scaleFactor != 1.0 {
            pdfView.scaleFactor = viewState.scaleFactor
        }
        
        // 设置代理来监听状态变化
        let coordinator = context.coordinator
        coordinator.pdfView = pdfView
        coordinator.setup()
        
        print("恢复PDF状态 - 页面: \(viewState.currentPage?.label ?? "首页"), 缩放: \(viewState.scaleFactor)")
        
        return pdfView
    }
    
    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document != document {
            nsView.document = document
        }
        
        // 更新显示模式
        if nsView.displayMode != viewState.displayMode {
            nsView.displayMode = viewState.displayMode
        }
    }
    
    func makeCoordinator() -> PDFCoordinator {
        PDFCoordinator(fileURL: fileURL, viewState: $viewState, stateManager: stateManager)
    }
}

// MARK: - PDF状态协调器
class PDFCoordinator: NSObject {
    let fileURL: URL
    @Binding var viewState: PDFViewState
    let stateManager: PDFStateManager
    weak var pdfView: PDFView?
    
    init(fileURL: URL, viewState: Binding<PDFViewState>, stateManager: PDFStateManager) {
        self.fileURL = fileURL
        self._viewState = viewState
        self.stateManager = stateManager
        super.init()
    }
    
    func setup() {
        guard let pdfView = pdfView else { return }
        
        // 监听页面变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pageChanged),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        
        // 监听缩放变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scaleChanged),
            name: .PDFViewScaleChanged,
            object: pdfView
        )
        
        // 监听显示模式变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displayModeChanged),
            name: .PDFViewDisplayModeChanged,
            object: pdfView
        )
    }
    
    @objc private func pageChanged() {
        guard let pdfView = pdfView else { return }
        
        viewState.currentPage = pdfView.currentPage
        saveState()
        
        if let pageLabel = pdfView.currentPage?.label {
            print("页面已切换到: \(pageLabel)")
        }
    }
    
    @objc private func scaleChanged() {
        guard let pdfView = pdfView else { return }
        
        viewState.scaleFactor = pdfView.scaleFactor
        saveState()
        
        print("缩放已更改为: \(pdfView.scaleFactor)")
    }
    
    @objc private func displayModeChanged() {
        guard let pdfView = pdfView else { return }
        
        viewState.displayMode = pdfView.displayMode
        saveState()
        
        print("显示模式已更改为: \(pdfView.displayMode.rawValue)")
    }
    
    private func saveState() {
        // 延迟保存以避免频繁写入
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.stateManager.setState(self.viewState, for: self.fileURL)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - 原版PDFKit包装器（保持兼容性）
struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayDirection = .vertical
        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = true
        return pdfView
    }
    
    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document != document {
            nsView.document = document
        }
    }
}

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
        
        // 验证输入参数
        guard url.isFileURL,
              size.width > 0 && size.height > 0,
              FileManager.default.fileExists(atPath: url.path) else {
            print("输入参数无效或文件不存在: \(url.path)")
            let fallback = generateFallbackIcon(size: size)
            if let fallback = fallback {
                cache.setObject(fallback, forKey: cacheKey)
            }
            return fallback
        }
        
        var thumbnail: NSImage?
        
        // 方法1: 优先使用PDFKit直接渲染PDF第一页内容
        print("尝试使用PDFKit生成缩略图: \(url.lastPathComponent)")
        thumbnail = generatePDFKitThumbnail(for: url, size: size)
        
        if thumbnail != nil {
            print("PDFKit生成成功")
        } else {
            print("PDFKit生成失败，尝试QuickLook")
            // 方法2: 使用QuickLook生成真实PDF预览
            // 添加条件检查，避免在已知会失败的情况下调用QuickLook
            if url.pathExtension.lowercased() == "pdf" {
                thumbnail = generateQuickLookThumbnail(for: url, size: size)
            }
        }
        
        if thumbnail != nil {
            print("QuickLook生成成功")
        } else {
            print("QuickLook生成失败，使用备用方案")
            // 方法3: 最后的备用方案 - 通用PDF文档图标
            thumbnail = generateFallbackIcon(size: size)
        }
        
        // 缓存结果（即使是备用图标也要缓存）
        if let thumbnail = thumbnail {
            cache.setObject(thumbnail, forKey: cacheKey)
        }
        
        return thumbnail
    }
    
    private func generatePDFKitThumbnail(for url: URL, size: CGSize) -> NSImage? {
        // 验证输入参数
        guard url.isFileURL else {
            print("PDFKit: 无效的文件URL")
            return nil
        }
        
        guard size.width > 0 && size.height > 0 else {
            print("PDFKit: 无效的尺寸参数")
            return nil
        }
        
        // 验证文件存在
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("PDFKit: 文件不存在 - \(url.path)")
            return nil
        }
        
        // 尝试使用安全书签URL
        var targetURL = url
        var hasSecurityAccess = false
        
        if let securityScopedURL = DataManager.shared.getSecurityScopedURL(for: url) {
            targetURL = securityScopedURL
            hasSecurityAccess = targetURL.startAccessingSecurityScopedResource()
            print("使用安全书签URL访问文件: \(hasSecurityAccess)")
        } else {
            // 尝试直接访问
            hasSecurityAccess = url.startAccessingSecurityScopedResource()
            print("PDFKit直接访问文件: \(hasSecurityAccess)")
        }
        
        defer {
            if hasSecurityAccess {
                targetURL.stopAccessingSecurityScopedResource()
            }
        }
        
        // 如果没有访问权限，返回nil
        guard hasSecurityAccess else {
            print("PDFKit: 无法获取文件访问权限")
            return nil
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
        if #available(macOS 12.0, *) {
            if let contentType = UTType(filenameExtension: fileType) {
                let typeIcon = workspace.icon(for: contentType)
                return resizeImage(typeIcon, to: size)
            }
        } else {
            let typeIcon = workspace.icon(forFileType: fileType)
            return resizeImage(typeIcon, to: size)
        }
        
        // 备用方案：返回通用文档图标
        if #available(macOS 12.0, *) {
            let typeIcon = workspace.icon(for: .data)
            return resizeImage(typeIcon, to: size)
        } else {
            return resizeImage(workspace.icon(forFileType: ""), to: size)
        }
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
            // 验证URL有效性
            guard url.isFileURL else {
                print("QuickLook: 无效的文件URL")
                return nil
            }
            
            // 验证文件存在
            guard FileManager.default.fileExists(atPath: url.path) else {
                print("QuickLook: 文件不存在 - \(url.path)")
                return nil
            }
            
            // 验证尺寸参数
            guard size.width > 0 && size.height > 0 && size.width <= 1024 && size.height <= 1024 else {
                print("QuickLook: 无效的尺寸参数 - \(size)")
                return nil
            }
            
            // 尝试使用安全书签URL
            var targetURL = url
            var hasSecurityAccess = false
            
            if let securityScopedURL = DataManager.shared.getSecurityScopedURL(for: url) {
                targetURL = securityScopedURL
                hasSecurityAccess = targetURL.startAccessingSecurityScopedResource()
                print("QuickLook使用安全书签URL访问文件: \(hasSecurityAccess)")
            } else {
                // 尝试直接访问（确保URL是安全的）
                if url.startAccessingSecurityScopedResource() {
                    hasSecurityAccess = true
                    targetURL = url
                    print("QuickLook直接访问文件: \(hasSecurityAccess)")
                } else {
                    print("QuickLook: 无法获取文件访问权限")
                    return nil
                }
            }
            
            defer {
                if hasSecurityAccess {
                    targetURL.stopAccessingSecurityScopedResource()
                }
            }
            
            // 使用适当的scale值
            let scale = min(NSScreen.main?.backingScaleFactor ?? 1.0, 3.0) // 限制最大scale为3.0
            
            // 创建QLThumbnailGenerator请求
            let request = QLThumbnailGenerator.Request(
                fileAt: targetURL,
                size: size,
                scale: scale,
                representationTypes: .thumbnail
            )
            
            let semaphore = DispatchSemaphore(value: 0)
            var resultImage: NSImage?
            var generationError: Error?
            
            print("开始QuickLook缩略图生成: \(url.lastPathComponent), 尺寸: \(size), scale: \(scale)")
            
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, genError in
                if let thumbnail = thumbnail {
                    resultImage = thumbnail.nsImage
                    print("QuickLook生成成功，图像尺寸: \(thumbnail.nsImage.size)")
                } else if let genError = genError {
                    generationError = genError
                    print("QuickLook缩略图生成失败: \(genError.localizedDescription)")
                    
                    // 详细错误信息
                    if let nsError = genError as NSError? {
                        print("错误域: \(nsError.domain), 错误代码: \(nsError.code)")
                        if nsError.domain == "NSOSStatusErrorDomain" && nsError.code == -50 {
                            print("参数错误：可能是传入了无效的文件URL或参数")
                        }
                    }
                } else {
                    print("QuickLook: 未知错误，没有返回缩略图或错误信息")
                }
                semaphore.signal()
            }
            
            // 设置更短的超时时间，避免阻塞
            let timeout = DispatchTime.now() + .seconds(3)
            let result = semaphore.wait(timeout: timeout)
            
            if result == .timedOut {
                print("QuickLook缩略图生成超时")
                return nil
            }
            
            if let error = generationError {
                print("最终错误: \(error)")
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
    let tabManager: TabManager
    
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
                                onTap: {
                                    tabManager.addPDFTab(fileURL: fileURL)
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
        }
    }
    
    private func refreshFileList() {
        pdfFiles = dataManager.getPDFFilesInWorkspace()
    }
}

// MARK: - 书本项目视图
struct BookItemView: View {
    let fileURL: URL
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
                    
                    // 悬停效果覆盖层
                    if isHovered {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.1))
                    }
                    
                    // 悬停时显示打开提示
                    if isHovered {
                        VStack {
                            Spacer()
                            HStack {
                                Image(systemName: "arrow.up.right.square.fill")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                Text("打开")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.8))
                            .cornerRadius(8)
                            .padding(.bottom, 8)
                        }
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
                            lineWidth: 1
                        )
                }
                .scaleEffect(isHovered ? 1.02 : 1.0)
                .shadow(
                    color: .black.opacity(0.15),
                    radius: isHovered ? 8 : 4,
                    x: 0,
                    y: isHovered ? 4 : 2
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
        .animation(.easeInOut(duration: 0.2), value: isHovered)
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
