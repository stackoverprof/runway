import SwiftUI
import AppKit

struct ResizableBox: View {
    let id: UUID
    let workspace: Workspace
    @Binding var name: String
    @Binding var detail: String
    var state: AgentState = .idle
    let config: TerminalConfig
    @Binding var height: CGFloat
    var isFocused: Bool = false
    /// When non-nil (accordion mode) the box uses this height and the resize
    /// handle is disabled.
    var fixedHeight: CGFloat? = nil
    @State private var startHeight: CGFloat?
    @State private var isEditingName = false
    @State private var isEditingDetail = false
    @State private var isHoveringHeader = false
    @State private var isPulsing = false
    @State private var shimmerOffset: CGFloat = -0.8
    @State private var pulseTask: Task<Void, Never>? = nil

    private let maxDetail = 40

    private let minHeight: CGFloat = 60
    private let maxHeight: CGFloat = 1400
    private let edgeGrab: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .background(
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RunwayTerminal.headerBar
                            if isPulsing {
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.clear,
                                        Color(red: 0.91, green: 0.62, blue: 0.20).opacity(0.10),
                                        Color.clear
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: geo.size.width * 0.8)
                                .offset(x: geo.size.width * shimmerOffset)
                            }
                        }
                    }
                )
            TerminalSurfaceView(boxID: id, workspace: workspace, config: config)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 10)   // + 2 window-padding ≈ 12, aligns with the header
                .padding(.bottom, 2)        // tiny inset to clear the rounded corners
        }
        .frame(height: fixedHeight ?? height)
        .background(RunwayTerminal.body)                 // darker body fills the inset
        .clipShape(RoundedRectangle(cornerRadius: 9))
        // Focus: a very slight brighter border + faint white glow.
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(isFocused ? Color.white.opacity(0.30) : Color.white.opacity(0.07),
                        lineWidth: 1)
        )
        .shadow(color: isFocused ? Color.white.opacity(0.14) : .clear,
                radius: isFocused ? 11 : 0)
        .overlay(alignment: .bottom) {
            if fixedHeight == nil { bottomEdgeHandle }   // no resize in accordion mode
        }
        .onChange(of: state) { old, new in
            if new == .needsAction {
                pulseTask?.cancel()
                shimmerOffset = -0.8
                pulseTask = Task {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        shimmerOffset = 1.0
                    }
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isPulsing = false
                        shimmerOffset = -0.8
                    }
                }
                withAnimation(.easeInOut(duration: 0.3)) {
                    isPulsing = true
                }
            } else {
                pulseTask?.cancel()
                withAnimation(.easeInOut(duration: 0.3)) {
                    isPulsing = false
                    shimmerOffset = -0.8
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(state.color)
                .frame(width: 6, height: 6)
                .shadow(color: state.glows ? state.color.opacity(0.9) : .clear, radius: 4)
            nameField
                .layoutPriority(1)
            Spacer(minLength: 8)
            detailField
                .layoutPriority(0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { isHoveringHeader = $0 }
        .onTapGesture { workspace.focusedID = id }
    }

    /// The agent name: a label that becomes an inline text field when clicked.
    @ViewBuilder
    private var nameField: some View {
        if isEditingName {
            InlineField(
                text: $name,
                font: .monospacedSystemFont(ofSize: 11, weight: .medium),
                color: .white,
                onEnd: { isEditingName = false }
            )
            .fixedSize()
        } else {
            Text(name)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(1)
                .contentShape(Rectangle())
                .onTapGesture { workspace.focusedID = id; isEditingName = true }
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
                }
        }
    }

    /// Editable gray description (max 40 chars), right-aligned. Truncates with an
    /// ellipsis when the header gets tight on a narrow window.
    @ViewBuilder
    private var detailField: some View {
        if isEditingDetail {
            InlineField(
                text: $detail,
                font: .monospacedSystemFont(ofSize: 10, weight: .regular),
                color: NSColor.white.withAlphaComponent(0.55),
                alignment: .right,
                placeholder: "Add a description",
                maxLength: maxDetail,
                onEnd: { isEditingDetail = false }
            )
            .frame(maxWidth: 280)
        } else if !detail.isEmpty {
            detailLabel(detail, opacity: 0.45)
        } else if isHoveringHeader {
            // Empty + hovering the header → reveal the placeholder.
            detailLabel("Add a description", opacity: 0.22)
        }
        // Empty + not hovering → show nothing.
    }

    private func detailLabel(_ text: String, opacity: Double) -> some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(Color.white.opacity(opacity))
            .lineLimit(1)
            .truncationMode(.tail)
            .contentShape(Rectangle())
            .onTapGesture { workspace.focusedID = id; isEditingDetail = true }
            .onHover { hovering in
                if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
            }
    }

    /// Drag handle on the bottom edge only; the top edge is inert.
    private var bottomEdgeHandle: some View {
        Color.clear
            .frame(height: edgeGrab)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
            }
            // High priority so resizing wins over the ScrollView's own drag.
            // Measure in .global space so the moving edge doesn't feed back into
            // the gesture and cause jitter.
            .highPriorityGesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        if startHeight == nil { startHeight = height }
                        let base = startHeight ?? height
                        height = min(max(minHeight, base + value.translation.height), maxHeight)
                    }
                    .onEnded { _ in startHeight = nil }
            )
    }
}
