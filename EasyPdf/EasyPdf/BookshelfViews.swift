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

// MARK: - 可编辑的PDF目录项
class EditablePDFOutline: ObservableObject, Identifiable, Codable {
    let id = UUID()
    @Published var label: String
    @Published var children: [EditablePDFOutline] = []
    @Published var isExpanded: Bool = true
    @Published var isEditing: Bool = false
    
    var page: PDFPage?
    var destination: PDFDestination?
    var originalOutline: PDFOutline?
    
    init(label: String, page: PDFPage? = nil, destination: PDFDestination? = nil, originalOutline: PDFOutline? = nil) {
        self.label = label
        self.page = page
        self.destination = destination
        self.originalOutline = originalOutline
    }
    
    convenience init(from pdfOutline: PDFOutline) {
        self.init(
            label: pdfOutline.label ?? "未命名",
            page: pdfOutline.destination?.page,
            destination: pdfOutline.destination,
            originalOutline: pdfOutline
        )
        
        // 递归转换子项
        for i in 0..<pdfOutline.numberOfChildren {
            if let child = pdfOutline.child(at: i) {
                children.append(EditablePDFOutline(from: child))
            }
        }
    }
    
    func addChild(_ child: EditablePDFOutline) {
        children.append(child)
    }
    
    func removeChild(_ child: EditablePDFOutline) {
        children.removeAll { $0.id == child.id }
    }
    
    func moveChild(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex && 
              sourceIndex < children.count && 
              destinationIndex <= children.count else { return }
        
        let movedItem = children.remove(at: sourceIndex)
        let newIndex = sourceIndex < destinationIndex ? destinationIndex - 1 : destinationIndex
        children.insert(movedItem, at: newIndex)
    }
    
    // MARK: - Codable支持
    private enum CodingKeys: String, CodingKey {
        case id, label, children, isExpanded, isEditing
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        children = try container.decode([EditablePDFOutline].self, forKey: .children)
        isExpanded = try container.decode(Bool.self, forKey: .isExpanded)
        isEditing = try container.decode(Bool.self, forKey: .isEditing)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(children, forKey: .children)
        try container.encode(isExpanded, forKey: .isExpanded)
        try container.encode(isEditing, forKey: .isEditing)
    }
}

// MARK: - 目录管理器
class EditableOutlineManager: ObservableObject {
    @Published var outlineItems: [EditablePDFOutline] = []
    private var document: PDFDocument?
    
    func loadFromDocument(_ document: PDFDocument) {
        self.document = document
        
        guard let outline = document.outlineRoot else {
            outlineItems = []
            return
        }
        
        var items: [EditablePDFOutline] = []
        for i in 0..<outline.numberOfChildren {
            if let child = outline.child(at: i) {
                items.append(EditablePDFOutline(from: child))
            }
        }
        outlineItems = items
    }
    
    func addRootItem(_ item: EditablePDFOutline) {
        outlineItems.append(item)
        saveToDocument()
    }
    
    func addChildItem(_ childItem: EditablePDFOutline, to parentItem: EditablePDFOutline) {
        parentItem.addChild(childItem)
        saveToDocument()
    }
    
    func removeItem(_ item: EditablePDFOutline) {
        // 从根项目中移除
        outlineItems.removeAll { $0.id == item.id }
        
        // 从所有父项中递归移除
        removeItemRecursively(item, from: outlineItems)
        saveToDocument()
    }
    
    private func removeItemRecursively(_ itemToRemove: EditablePDFOutline, from items: [EditablePDFOutline]) {
        for item in items {
            item.removeChild(itemToRemove)
            removeItemRecursively(itemToRemove, from: item.children)
        }
    }
    
    func moveItem(_ item: EditablePDFOutline, to newIndex: Int) {
        if let currentIndex = outlineItems.firstIndex(where: { $0.id == item.id }) {
            outlineItems.remove(at: currentIndex)
            let insertIndex = currentIndex < newIndex ? newIndex - 1 : newIndex
            outlineItems.insert(item, at: min(insertIndex, outlineItems.count))
            saveToDocument()
        }
    }
    
    private func saveToDocument() {
        // TODO: 实现保存到PDF文档的逻辑
        // 这需要创建新的PDFOutline对象并重建文档的目录结构
        print("保存目录到PDF文档 - 目前为演示模式")
    }
}

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
                PDFSplitView(
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
        
        // 监听目录导航请求
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(navigateToPage(_:)),
            name: .pdfShouldNavigateToPage,
            object: nil
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
    
    @objc private func navigateToPage(_ notification: Notification) {
        guard let pdfView = pdfView,
              let userInfo = notification.userInfo,
              let page = userInfo["page"] as? PDFPage else { return }
        
        DispatchQueue.main.async {
            pdfView.go(to: page)
            print("PDF导航到页面: \(page.label ?? "未知")")
        }
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

// MARK: - PDF分割视图
struct PDFSplitView: View {
    let fileURL: URL
    let document: PDFDocument
    @Binding var viewState: PDFViewState
    
    @State private var leftPanelWidth: CGFloat = 250
    @State private var containerWidth: CGFloat = 800
    @State private var showOutline: Bool = true
    
    private let minPanelWidth: CGFloat = 150
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if showOutline {
                    // 左侧PDF目录面板
                    PDFOutlineView(document: document, viewState: $viewState)
                        .frame(width: leftPanelWidth)
                        .background(Color(NSColor.controlBackgroundColor))
                    
                    // 分割线
                    PDFSplitterView(
                        offset: $leftPanelWidth,
                        containerWidth: geometry.size.width,
                        minWidth: minPanelWidth
                    )
                }
                
                // 右侧PDF内容区域
                VStack(spacing: 0) {
                    // 工具栏
                    PDFToolbarView(
                        showOutline: $showOutline,
                        viewState: $viewState
                    )
                    
                    // PDF查看器
                    CachedPDFKitView(
                        fileURL: fileURL,
                        document: document,
                        viewState: $viewState
                    )
                }
            }
            .onAppear {
                containerWidth = geometry.size.width
                leftPanelWidth = min(leftPanelWidth, geometry.size.width * 0.3)
            }
            .onChange(of: geometry.size.width) { newWidth in
                containerWidth = newWidth
                // 确保左面板宽度不超过容器宽度的40%
                let maxLeftWidth = newWidth * 0.4
                if leftPanelWidth > maxLeftWidth {
                    leftPanelWidth = maxLeftWidth
                }
            }
        }
    }
}

// MARK: - PDF分割线
struct PDFSplitterView: View {
    @Binding var offset: CGFloat
    let containerWidth: CGFloat
    let minWidth: CGFloat
    
    @State private var isDragging = false
    
    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(width: 1)
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
                        let maxOffset = containerWidth * 0.6
                        offset = max(minWidth, min(maxOffset, newOffset))
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .background(isDragging ? Color.blue.opacity(0.3) : Color.clear)
    }
}

// MARK: - PDF工具栏
struct PDFToolbarView: View {
    @Binding var showOutline: Bool
    @Binding var viewState: PDFViewState
    
    var body: some View {
        HStack(spacing: 8) {
            // 切换目录显示
            Button(action: {
                showOutline.toggle()
            }) {
                Image(systemName: showOutline ? "sidebar.left" : "sidebar.left.closed")
                    .font(.system(size: 16))
            }
            .buttonStyle(PlainButtonStyle())
            .help("切换目录面板")
            
            Divider()
                .frame(height: 16)
            
            // PDF页面信息
            if let currentPage = viewState.currentPage,
               let document = viewState.document {
                let pageIndex = document.index(for: currentPage)
                Text("\(pageIndex + 1) / \(document.pageCount)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 缩放控制（可以后续添加）
            Text("100%")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .border(Color.gray.opacity(0.2), width: 0.5)
    }
}

// MARK: - PDF目录视图
struct PDFOutlineView: View {
    let document: PDFDocument
    @Binding var viewState: PDFViewState
    
    @StateObject private var outlineManager = EditableOutlineManager()
    @State private var showingContextMenu = false
    @State private var contextMenuLocation: CGPoint = .zero
    @State private var selectedOutlineItem: EditablePDFOutline?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 目录标题
            HStack {
                Text("目录")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                
                // 添加根目录按钮
                Button(action: {
                    addRootOutlineItem()
                }) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("添加根目录")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .border(Color.gray.opacity(0.2), width: 0.5)
            
            // 目录内容
            if outlineManager.outlineItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("此PDF没有目录")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("创建第一个目录") {
                        addRootOutlineItem()
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(outlineManager.outlineItems) { item in
                            EditablePDFOutlineItemView(
                                item: item,
                                level: 0,
                                viewState: $viewState,
                                outlineManager: outlineManager,
                                onContextMenu: { location, outlineItem in
                                    contextMenuLocation = location
                                    selectedOutlineItem = outlineItem
                                    showingContextMenu = true
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }
        }
        .contextMenu {
            if selectedOutlineItem == nil {
                // 空白处右键菜单
                Button("添加根目录") {
                    addRootOutlineItem()
                }
            }
        }
        .popover(isPresented: $showingContextMenu, arrowEdge: .trailing) {
            if let selectedItem = selectedOutlineItem {
                OutlineContextMenu(
                    outlineItem: selectedItem,
                    outlineManager: outlineManager,
                    currentPage: viewState.currentPage,
                    onDismiss: {
                        showingContextMenu = false
                        selectedOutlineItem = nil
                    }
                )
            }
        }
        .onAppear {
            loadOutline()
        }
    }
    
    private func loadOutline() {
        outlineManager.loadFromDocument(document)
    }
    
    private func addRootOutlineItem() {
        let currentPageLabel = if let currentPage = viewState.currentPage,
                                 let document = viewState.document {
            "第 \(document.index(for: currentPage) + 1) 页"
        } else {
            "新目录"
        }
        
        let newItem = EditablePDFOutline(
            label: currentPageLabel,
            page: viewState.currentPage
        )
        outlineManager.addRootItem(newItem)
    }
}

// MARK: - 可编辑的PDF目录项视图
struct EditablePDFOutlineItemView: View {
    @ObservedObject var item: EditablePDFOutline
    let level: Int
    @Binding var viewState: PDFViewState
    let outlineManager: EditableOutlineManager
    let onContextMenu: (CGPoint, EditablePDFOutline) -> Void
    
    @State private var dragOffset: CGSize = .zero
    @State private var editingText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            // 当前项
            HStack(spacing: 4) {
                // 缩进
                if level > 0 {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: CGFloat(level * 16))
                }
                
                // 展开/折叠按钮
                if !item.children.isEmpty {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            item.isExpanded.toggle()
                        }
                    }) {
                        Image(systemName: item.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .frame(width: 16, height: 16)
                } else {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 16, height: 16)
                }
                
                // 标题（可编辑）
                if item.isEditing {
                    TextField("目录标题", text: $editingText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($isTextFieldFocused)
                        .onSubmit {
                            finishEditing()
                        }
                        .onAppear {
                            editingText = item.label
                            isTextFieldFocused = true
                        }
                } else {
                    Button(action: {
                        navigateToItem()
                    }) {
                        Text(item.label)
                            .font(.system(size: 12))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onTapGesture(count: 2) {
                        startEditing()
                    }
                    .onTapGesture(count: 1) {
                        navigateToItem()
                    }
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
            )
            .offset(dragOffset)
            .contextMenu {
                OutlineItemContextMenu(
                    outlineItem: item,
                    outlineManager: outlineManager,
                    currentPage: viewState.currentPage
                )
            }
            .draggable(item) {
                // 拖拽预览
                Text(item.label)
                    .padding(4)
                    .background(Color.gray.opacity(0.3))
                    .cornerRadius(4)
            }
            .dropDestination(for: EditablePDFOutline.self) { droppedItems, location in
                return handleDrop(droppedItems)
            }
            
            // 子项目
            if item.isExpanded && !item.children.isEmpty {
                ForEach(item.children) { child in
                    EditablePDFOutlineItemView(
                        item: child,
                        level: level + 1,
                        viewState: $viewState,
                        outlineManager: outlineManager,
                        onContextMenu: onContextMenu
                    )
                }
            }
        }
    }
    
    private func startEditing() {
        item.isEditing = true
        editingText = item.label
    }
    
    private func finishEditing() {
        item.label = editingText.isEmpty ? "未命名" : editingText
        item.isEditing = false
        isTextFieldFocused = false
    }
    
    private func navigateToItem() {
        guard let page = item.page ?? item.destination?.page else { return }
        
        // 更新当前页面
        viewState.currentPage = page
        
        // 通知PDF视图跳转到指定页面
        NotificationCenter.default.post(
            name: .pdfShouldNavigateToPage,
            object: nil,
            userInfo: ["page": page]
        )
    }
    
    private func handleDrop(_ droppedItems: [EditablePDFOutline]) -> Bool {
        guard let droppedItem = droppedItems.first else { return false }
        
        // 将拖拽的项目作为子项添加到当前项目
        outlineManager.addChildItem(droppedItem, to: item)
        return true
    }
}

// MARK: - 右键菜单
struct OutlineItemContextMenu: View {
    @ObservedObject var outlineItem: EditablePDFOutline
    let outlineManager: EditableOutlineManager
    let currentPage: PDFPage?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("添加子目录") {
                addChildOutline()
            }
            
            Divider()
            
            Button("重命名") {
                outlineItem.isEditing = true
            }
            
            Divider()
            
            Button("删除") {
                outlineManager.removeItem(outlineItem)
            }
            .foregroundColor(.red)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .shadow(radius: 4)
    }
    
    private func addChildOutline() {
        let currentPageLabel = if let currentPage = currentPage {
            "第 \(currentPage.label ?? "?") 页"
        } else {
            "新子目录"
        }
        
        let newChild = EditablePDFOutline(
            label: currentPageLabel,
            page: currentPage
        )
        outlineManager.addChildItem(newChild, to: outlineItem)
    }
}

// MARK: - 弹出式右键菜单
struct OutlineContextMenu: View {
    @ObservedObject var outlineItem: EditablePDFOutline
    let outlineManager: EditableOutlineManager
    let currentPage: PDFPage?
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                addChildOutline()
                onDismiss()
            }) {
                HStack {
                    Image(systemName: "plus.circle")
                    Text("添加子目录")
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: {
                outlineItem.isEditing = true
                onDismiss()
            }) {
                HStack {
                    Image(systemName: "pencil")
                    Text("重命名")
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: {
                outlineManager.removeItem(outlineItem)
                onDismiss()
            }) {
                HStack {
                    Image(systemName: "trash")
                    Text("删除")
                }
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundColor(.red)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .shadow(radius: 4)
    }
    
    private func addChildOutline() {
        let currentPageLabel = if let currentPage = currentPage {
            "第 \(currentPage.label ?? "?") 页"
        } else {
            "新子目录"
        }
        
        let newChild = EditablePDFOutline(
            label: currentPageLabel,
            page: currentPage
        )
        outlineManager.addChildItem(newChild, to: outlineItem)
    }
}

// MARK: - 拖拽支持
extension EditablePDFOutline: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

// MARK: - 原版PDF目录项视图（保持兼容性）
struct PDFOutlineItemView: View {
    let item: PDFOutline
    let level: Int
    @Binding var viewState: PDFViewState
    
    @State private var isExpanded: Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            // 当前项
            HStack(spacing: 4) {
                // 缩进
                if level > 0 {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: CGFloat(level * 16))
                }
                
                // 展开/折叠按钮
                if item.numberOfChildren > 0 {
                    Button(action: {
                        isExpanded.toggle()
                    }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .frame(width: 16, height: 16)
                } else {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 16, height: 16)
                }
                
                // 标题
                Button(action: {
                    navigateToItem()
                }) {
                    Text(item.label ?? "未命名")
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.vertical, 2)
            
            // 子项目
            if isExpanded && item.numberOfChildren > 0 {
                ForEach(0..<item.numberOfChildren, id: \.self) { index in
                    if let child = item.child(at: index) {
                        PDFOutlineItemView(
                            item: child,
                            level: level + 1,
                            viewState: $viewState
                        )
                    }
                }
            }
        }
    }
    
    private func navigateToItem() {
        guard let destination = item.destination,
              let page = destination.page else { return }
        
        // 更新当前页面
        viewState.currentPage = page
        
        // 通知PDF视图跳转到指定页面
        NotificationCenter.default.post(
            name: .pdfShouldNavigateToPage,
            object: nil,
            userInfo: ["page": page]
        )
    }
}

// MARK: - 通知扩展
extension NSNotification.Name {
    static let pdfShouldNavigateToPage = NSNotification.Name("PDFShouldNavigateToPage")
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
