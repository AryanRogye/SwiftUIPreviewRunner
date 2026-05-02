//
//  CustomTextView.swift
//  ComfyPilot
//
//  Created by Aryan Rogye on 4/24/26.
//


import SwiftUI

#if os(macOS)
import AppKit

struct CustomTextView: View {
    
    @Binding var text: String
    @Binding var isFocused: Bool
    @State private var height: CGFloat = 24
    var onSubmit: () -> Void
    
    init(
        text: Binding<String>,
        isFocused: Binding<Bool> = .constant(false),
        onSubmit: @escaping () -> Void = { }
    ) {
        self._text = text
        self._isFocused = isFocused
        self.onSubmit = onSubmit
    }
    
    var body: some View {
        AppKitTextView(
            text: $text,
            height: $height,
            isFocused: $isFocused,
            placeholder: "Ask Model",
            onSubmit: onSubmit
        )
        .frame(minHeight: 24, idealHeight: height, maxHeight: height)
    }
}

private struct AppKitTextView: NSViewRepresentable {
    
    @Binding var text: String
    @Binding var height: CGFloat
    @Binding var isFocused: Bool
    let placeholder: String
    let onSubmit: () -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, height: $height, isFocused: $isFocused)
    }
    
    func makeNSView(context: Context) -> AutoSizingTextView {
        let view = AutoSizingTextView()
        view.placeholder = placeholder
        view.onTextChange = { context.coordinator.text.wrappedValue = $0 }
        view.onHeightChange = {
            context.coordinator.setHeight($0)
        }
        view.onFocusChange = { context.coordinator.isFocused.wrappedValue = $0 }
        view.onSubmit = onSubmit
        view.string = text
        return view
    }
    
    func updateNSView(_ nsView: AutoSizingTextView, context: Context) {
        nsView.placeholder = placeholder
        nsView.onSubmit = onSubmit
        if nsView.string != text {
            nsView.string = text
        }
        nsView.updateMeasuredHeight()
    }
    
    @MainActor
    final class Coordinator {
        var text: Binding<String>
        var height: Binding<CGFloat>
        var isFocused: Binding<Bool>
        
        public func setHeight(_ height: CGFloat) {
            DispatchQueue.main.async {
                self.height.wrappedValue = height
            }
        }
        
        init(
            text: Binding<String>,
            height: Binding<CGFloat>,
            isFocused: Binding<Bool>
        ) {
            self.text = text
            self.height = height
            self.isFocused = isFocused
        }
    }
}

private final class AutoSizingTextView: NSView, NSTextViewDelegate {
    
    private let scrollView = NSScrollView()
    private let textView = SubmitTextView()
    private let placeholderLabel = NSTextField(labelWithString: "")
    
    var onTextChange: (String) -> Void = { _ in }
    var onHeightChange: (CGFloat) -> Void = { _ in }
    var onFocusChange: (Bool) -> Void = { _ in }
    var onSubmit: () -> Void = { } {
        didSet {
            textView.onSubmit = onSubmit
        }
    }
    
    var placeholder: String = "" {
        didSet {
            placeholderLabel.stringValue = placeholder
        }
    }
    
    var string: String {
        get { textView.string }
        set {
            textView.string = newValue
            placeholderLabel.isHidden = !newValue.isEmpty
            updateMeasuredHeight()
        }
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    override func layout() {
        super.layout()
        updateMeasuredHeight()
    }
    
    private func setup() {
        wantsLayer = true
        
        textView.delegate = self
        textView.onSubmit = onSubmit
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        
        placeholderLabel.textColor = .placeholderTextColor
        placeholderLabel.font = .preferredFont(forTextStyle: .body)
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel)
        
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 2)
        ])
    }
    
    func textDidBeginEditing(_ notification: Notification) {
        onFocusChange(true)
    }
    
    func textDidEndEditing(_ notification: Notification) {
        onFocusChange(false)
    }
    
    func textDidChange(_ notification: Notification) {
        placeholderLabel.isHidden = !textView.string.isEmpty
        onTextChange(textView.string)
        updateMeasuredHeight()
    }
    
    func updateMeasuredHeight() {
        guard bounds.width > 0 else { return }
        
        let fittingWidth = bounds.width
        textView.textContainer?.containerSize = NSSize(
            width: fittingWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        
        let usedRect = textView.layoutManager?.usedRect(for: textView.textContainer!) ?? .zero
        let measuredHeight = ceil(usedRect.height + textView.textContainerInset.height * 2)
        let clampedHeight = min(max(measuredHeight, 24), 104)
        
        onHeightChange(clampedHeight)
    }
}

private final class SubmitTextView: NSTextView {
    
    var onSubmit: () -> Void = { }
    
    override func keyDown(with event: NSEvent) {
        let isReturn = event.charactersIgnoringModifiers == "\r" ||
        event.charactersIgnoringModifiers == "\n"
        let isShiftDown = event.modifierFlags.contains(.shift)
        
        if isReturn && !isShiftDown {
            onSubmit()
            return
        }
        
        super.keyDown(with: event)
    }
}
#else
struct CustomTextView: View {
    @Binding var text: String
    var onSubmit: () -> Void = { }
    
    var body: some View {
        TextEditor(text: $text)
    }
}
#endif
