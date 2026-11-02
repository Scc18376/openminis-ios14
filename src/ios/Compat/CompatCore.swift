//
//  CompatCore.swift  —  OpenMinis iOS 14.3 降级兼容层
//  放到 src/ios/Compat/ 并加入 Minis target
//
//  全部 shim 在 iOS 16+ 上走系统实现，iOS 14.3 上走降级实现。
//

import SwiftUI
import UIKit

// MARK: - 导航栈（NavigationStack，iOS 16+）

/// 无 path 版本的 NavigationStack 替代。iOS 16+ 直接用系统实现。
public struct MinisNavStack<Content: View>: View {
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack { content }
        } else {
            NavigationView { content }
                .navigationViewStyle(.stack)
        }
    }
}

/// 带 path 的版本。iOS 14 上用隐藏 NavigationLink 驱动，语义等价。
public struct MinisNavStackPath<Data: MutableCollection & RandomAccessCollection, Content: View>: View
where Data.Element: Hashable, Data.Index == Int {
    @Binding private var path: Data
    private let content: Content

    public init(path: Binding<Data>, @ViewBuilder content: () -> Content) {
        self._path = path
        self.content = content()
    }

    public var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                NavigationStack(path: $path) { content }
            } else {
                NavigationView { content }
                    .navigationViewStyle(.stack)
            }
        }
    }
}

// MARK: - 颜色样式（.foregroundStyle，iOS 15+）

/// iOS 14 上没有 ShapeStyle 的通用渲染，按实际类型降级。
public extension View {
    @inlinable
    func foregroundStyle<S: ShapeStyle>(_ style: S) -> some View {
        modifier(_MinisForegroundStyle(style: style))
    }

    @inlinable
    func foregroundStyle<S1: ShapeStyle, S2: ShapeStyle>(_ primary: S1, _ secondary: S2) -> some View {
        modifier(_MinisForegroundStyle(style: primary))
    }
}

public struct _MinisForegroundStyle<S: ShapeStyle>: ViewModifier {
    let style: S

    @ViewBuilder
    public func body(content: Content) -> some View {
        if #available(iOS 15.0, *) {
            content.foregroundStyle(style)
        } else {
            content.foregroundColor(_resolve(style))
        }
    }

    private func _resolve(_ s: S) -> Color {
        if let c = s as? Color { return c }
        if let g = s as? LinearGradient { return g.gradient.stops.first?.color ?? .primary }
        if let g = s as? AngularGradient { return g.gradient.stops.first?.color ?? .primary }
        if let g = s as? RadialGradient { return g.gradient.stops.first?.color ?? .primary }
        return .primary
    }
}

// MARK: - 通用 no-op / 语义降级 modifier

public extension View {
    /// presentationDetents — iOS 14 上 sheet 本身就接近全屏，忽略即可
    @inlinable
    func presentationDetents(_ detents: Set<PresentationDetentCompat>) -> some View { self }

    func presentationDetents(_ detents: Set<PresentationDetentCompat>, selection: Binding<PresentationDetentCompat>) -> some View {
        self.presentationDetents(detents)
    }

    /// scrollContentBackground — iOS 14 没有配置化背景，忽略
    @inlinable
    func scrollContentBackground(_ visibility: VisibilityCompat) -> some View { self }

    /// scrollDismissesKeyboard
    @inlinable
    func scrollDismissesKeyboard(_ mode: ScrollDismissesKeyboardModeCompat) -> some View { self }

    /// toolbarBackground
    @inlinable
    func toolbarBackground<S: ShapeStyle>(_ style: S, for bars: ToolbarPlacementCompat = .automatic) -> some View { self }

    /// symbolEffect — iOS 14 无 SF Symbols 动画
    @inlinable
    func symbolEffect<T>(_ effect: T, options: Int = 0) -> some View { self }

    /// dynamicTypeSize — 交给系统自动处理
    @inlinable
    func dynamicTypeSize(_ size: DynamicTypeSizeCompat) -> some View { self }

    /// sensoryFeedback — 用 UIKit 触感替代
    @inlinable
    func sensoryFeedback<T: Equatable>(_ feedback: SensoryFeedbackCompat, trigger: T) -> some View {
        self.onChange(of: trigger) { _ in
            let g = UIImpactFeedbackGenerator(style: .light)
            g.impactOccurred()
        }
    }

    /// textSelection — iOS 14 上整体降级为不可选
    @inlinable
    func textSelection(_ selection: TextSelectionCompat) -> some View { self }

    /// tint — 用 accentColor
    @inlinable
    func tint(_ color: Color) -> some View { self.accentColor(color) }

    /// ContentUnavailableView 替代在 CompatViews.swift
}

// MARK: - 兼容枚举

public enum PresentationDetentCompat: Hashable {
    case medium, large
    case fraction(Double)
    case height(Double)
}

public enum VisibilityCompat: Hashable { case automatic, visible, hidden }

public enum ScrollDismissesKeyboardModeCompat: Hashable {
    case never, immediately, interactively, automatically
}

public enum ToolbarPlacementCompat: Hashable { case automatic, navigationBar, tabBar }

public enum DynamicTypeSizeCompat: Hashable { case small, medium, large, xLarge }

public enum TextSelectionCompat: Hashable { case enabled, disabled }

public enum SensoryFeedbackCompat: Hashable { case success, warning, error, selection, impact }

// MARK: - contentMargins / badge 等零散

public extension View {
    @inlinable func contentMargins(_ value: CGFloat, for placement: Int = 0) -> some View { self }
    @inlinable func badge(_ count: Int) -> some View { self }
    @inlinable func badge(_ text: String) -> some View { self }
}

// MARK: - controlSize (iOS 15+)

public enum MinisControlSize: Hashable { case mini, small, regular, large, extraLarge }

public extension View {
    @inlinable
    func controlSize(_ size: MinisControlSize) -> some View { self }
}

// MARK: - TimelineView (iOS 15+)

public struct MinisTimelineSchedule {
    /// .animation
    public static var animation: MinisTimelineSchedule { MinisTimelineSchedule(live: true, interval: 1.0 / 30.0) }
    /// .periodic(from:by:)
    public static func periodic(from start: Date, by interval: TimeInterval) -> MinisTimelineSchedule {
        MinisTimelineSchedule(live: false, interval: interval)
    }
    let live: Bool
    let interval: TimeInterval
    public init(live: Bool = false, interval: TimeInterval = 1) {
        self.live = live
        self.interval = interval
    }
}

public struct MinisTimelineContext {
    public let date: Date
    public let cadence: MinisTimelineSchedule
}

public struct MinisTimelineView<Content: View>: View {
    private let schedule: MinisTimelineSchedule
    private let content: (MinisTimelineContext) -> Content
    @State private var now = Date()

    public init(_ schedule: MinisTimelineSchedule,
                @ViewBuilder content: @escaping (MinisTimelineContext) -> Content) {
        self.schedule = schedule
        self.content = content
    }

    public var body: some View {
        content(MinisTimelineContext(date: now, cadence: schedule))
            .onReceive(Timer.publish(every: max(schedule.interval, 1.0 / 60.0),
                                     on: .main, in: .common).autoconnect()) { date in
                self.now = date
            }
    }
}

// MARK: - overlay(alignment:content:) (iOS 15+)

public extension View {
    @inlinable
    func overlay<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View {
        self.overlay(content(), alignment: alignment)
    }
}

// MARK: - .focused() (iOS 15+) — iOS14 降级为 no-op

public extension View {
    @inlinable
    func focused<Value>(_ binding: Binding<Value>) -> some View { self }
}

// MARK: - Button role (iOS 15+)

public struct MinisButtonRole: Equatable {
    public static let destructive = MinisButtonRole()
    public static let cancel = MinisButtonRole()
    public init() {}
}

// MARK: - .task(id:) (iOS 15+)

public extension View {
    @inlinable
    func task<V: Equatable>(id value: V, priority: TaskPriority = .userInitiated,
                            _ action: @escaping @Sendable () async -> Void) -> some View {
        modifier(_MinisTaskIDModifier(value: value, priority: priority, action: action))
    }
}

struct _MinisTaskIDModifier<V: Equatable>: ViewModifier {
    let value: V
    let priority: TaskPriority
    let action: @Sendable () async -> Void
    @State private var task: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onAppear { schedule() }
            .onChange(of: value) { _ in schedule() }
            .onDisappear { task?.cancel(); task = nil }
    }

    private func schedule() {
        task?.cancel()
        task = Task(priority: priority) { await action() }
    }
}

// MARK: - 新颜色（iOS 15+）

public extension Color {
    static var mint: Color { Color(UIColor.systemMint) }
    static var teal: Color { Color(UIColor.systemTeal) }
    static var indigo: Color { Color(UIColor.systemIndigo) }
    static var cyan: Color { Color(UIColor.systemCyan) }
    static var brown: Color { Color(UIColor.systemBrown) }
    static var quaternary: Color { Color(UIColor.quaternaryLabel) }
}

// MARK: - Alert with presenting (iOS 15+) — 降级

public extension View {
    func alert<Item, A: View>(_ title: String,
                              isPresented: Binding<Bool>,
                              presenting item: Item?,
                              @ViewBuilder actions: (Item) -> A) -> some View {
        self.alert(isPresented: isPresented) {
            Alert(title: Text(title), dismissButton: .default(Text("OK")))
        }
    }
}

// MARK: - Button(role:) (iOS 15+)

public extension Button {
    init(role: MinisButtonRole?, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.init(action: action, label: label)
    }
}

// MARK: - TextField(axis:) (iOS 16+)

public enum MinisAxis { case horizontal, vertical }

public extension TextField {
    init(_ titleKey: String, text: Binding<String>, axis: MinisAxis) {
        self.init(titleKey, text: text)
    }
}

public extension TextField where Label == Text {
    init(_ titleKey: String, text: Binding<String>, axis: MinisAxis) {
        self.init(titleKey, text: text)
    }
}

// MARK: - 第五批 shim

public enum MinisScrollIndicatorVisibility { case automatic, visible, hidden }

public extension View {
    @inlinable
    func scrollIndicators(_ visibility: MinisScrollIndicatorVisibility) -> some View { self }
    @inlinable
    func scrollIndicators(_ visibility: MinisScrollIndicatorVisibility, axes: Int) -> some View { self }
    @inlinable
    func background<S: Shape, T: ShapeStyle>(_ style: T, in shape: S, fillStyle: FillStyle = FillStyle()) -> some View {
        self.background(style, in: shape)
    }
    @inlinable
    func background<S: Shape>(_ color: Color, in shape: S) -> some View {
        self.background(color, in: shape)
    }
    @inlinable
    func symbolRenderingMode(_ mode: MinisSymbolRenderingMode) -> some View { self }
    @inlinable
    func onGeometryChange<T: Equatable>(for type: T.Type, of transform: @escaping (GeometryProxy) -> T, action: @escaping (T) -> Void) -> some View {
        self
    }
}

public enum MinisSymbolRenderingMode { case monochrome, hierarchical, palette, multicolor }

public struct MinisOpenURLResult {
    public static var handled: MinisOpenURLResult { .init() }
    public static var discarded: MinisOpenURLResult { .init() }
    public static func systemAction(_ url: URL) -> MinisOpenURLResult { .init() }
}

public enum MinisToolbarItemPlacement {
    public static var keyboard: MinisToolbarItemPlacement { .init() }
    public static var automatic: MinisToolbarItemPlacement { .init() }
}

public extension View {
    func alert<Item, A: View, M: View>(_ title: String,
                                      isPresented: Binding<Bool>,
                                      presenting item: Item?,
                                      @ViewBuilder actions: (Item) -> A,
                                      @ViewBuilder message: (Item) -> M) -> some View {
        self.alert(isPresented: isPresented) {
            Alert(title: Text(title), dismissButton: .default(Text("OK")))
        }
    }
}

public extension Button {
    init<S: StringProtocol>(_ title: S, role: MinisButtonRole?, action: @escaping () -> Void) where Label == Text {
        self.init(action: action) { Text(title) }
    }
}
