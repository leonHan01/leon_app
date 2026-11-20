import SwiftUI
import UIKit
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

enum ImagePreparation {
    static func read(_ url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        guard size <= 20*1024*1024 else { throw NativeError(message:"图片不能超过 20 MB。") }
        let input = try InputStream(url:url).unwrap("图片无法读取。")
        input.open(); defer { input.close() }
        var data = Data(), block = [UInt8](repeating:0,count:65536)
        while input.hasBytesAvailable {
            let count = input.read(&block,maxLength:block.count)
            guard count >= 0 else { throw NativeError(message:"图片读取失败。") }; if count == 0 { break }
            guard data.count+count <= 20*1024*1024 else { throw NativeError(message:"图片不能超过 20 MB。") }
            data.append(contentsOf:block.prefix(count))
        }
        return data
    }
    static func normalize(_ data: Data) throws -> DraftImage {
        guard data.count <= 20*1024*1024, let source = CGImageSourceCreateWithData(data as CFData,[kCGImageSourceShouldCache:false] as CFDictionary),
              let metadata = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let width = metadata[kCGImagePropertyPixelWidth] as? Int, let height = metadata[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 16000, height <= 16000, Int64(width)*Int64(height) <= 48_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:1600,kCGImageSourceShouldCacheImmediately:true] as CFDictionary)
        else { throw NativeError(message:"图片格式不受支持或尺寸过大。") }
        let size = CGSize(width:image.width,height:image.height)
        let format = UIGraphicsImageRendererFormat(); format.opaque = true; format.scale = 1
        let flattened = UIGraphicsImageRenderer(size:size,format:format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin:.zero,size:size))
            UIImage(cgImage:image).draw(in:CGRect(origin:.zero,size:size))
        }
        for quality: CGFloat in [0.85,0.65,0.45] {
            if let output = flattened.jpegData(compressionQuality:quality), output.count <= 1_048_576 { return DraftImage(id:UUID().uuidString.lowercased(),data:output) }
        }
        throw NativeError(message:"图片压缩后仍超过 1 MB，请缩小后发送。")
    }
}
enum NativeImageDecoder {
    static func image(_ data:Data,pixels:Int,sourceLimit:Int = 1600) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData,[kCGImageSourceShouldCache:false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width>0,height>0,width<=sourceLimit,height<=sourceLimit,Int64(width)*Int64(height)<=48_000_000,
              let result = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:pixels,kCGImageSourceShouldCacheImmediately:true] as CFDictionary) else {return nil}
        return UIImage(cgImage:result)
    }
}
private extension Optional {
    func unwrap(_ message: String) throws -> Wrapped { guard let value = self else { throw NativeError(message:message) }; return value }
}
@MainActor
func receiveImage(provider: NSItemProvider, origin: ImageOrigin, store: ChatStore) {
    guard let work = store.beginImage(origin:origin) else { store.error = "每条最多 4 张图片。"; return }
    // File access occurs within the provider callback; its URL may expire afterwards.
    provider.loadFileRepresentation(forTypeIdentifier:UTType.image.identifier) { url, failure in
        let result: Result<DraftImage,Error> = Result {
            guard let url else { throw failure ?? NativeError(message:"无法读取所选图片。") }
            return try ImagePreparation.normalize(ImagePreparation.read(url))
        }
        Task { @MainActor in
            switch result { case .success(let image): store.finishImage(work,image:image)
            case .failure(let error): store.finishImage(work,image:nil,failure:error) }
        }
    }
}
@MainActor
func receiveImage(file:URL,origin:ImageOrigin,store:ChatStore) {
    guard let work = store.beginImage(origin:origin) else {store.error = "每条最多 4 张图片。";return}
    Task {
        let result = await Task.detached {() -> Result<DraftImage,Error> in
            Result {
                let scoped = file.startAccessingSecurityScopedResource()
                defer {
                    if scoped {file.stopAccessingSecurityScopedResource()}
                    let path = file.resolvingSymlinksInPath().path
                    let home = URL(fileURLWithPath:NSHomeDirectory()).resolvingSymlinksInPath().path+"/"
                    let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path+"/"
                    if path.hasPrefix(home) && (path.hasPrefix(temporary) || file.deletingLastPathComponent().lastPathComponent.hasSuffix("Inbox")) {try? FileManager.default.removeItem(at:file)}
                }
                return try ImagePreparation.normalize(ImagePreparation.read(file))
            }
        }.value
        switch result {
        case .success(let image):store.finishImage(work,image:image)
        case .failure(let error):store.finishImage(work,image:nil,failure:error)
        }
    }
}
@MainActor
struct ImageFilePicker:UIViewControllerRepresentable {
    let store:ChatStore
    let origin:ImageOrigin
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context:Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes:[.image],asCopy:true)
        picker.allowsMultipleSelection = true;picker.delegate = context.coordinator;return picker
    }
    func updateUIViewController(_ controller:UIDocumentPickerViewController,context:Context) {}
    func makeCoordinator() -> Coordinator {Coordinator(self)}
    final class Coordinator:NSObject,UIDocumentPickerDelegate {
        let parent:ImageFilePicker
        init(_ parent:ImageFilePicker) {self.parent = parent}
        func documentPicker(_ controller:UIDocumentPickerViewController,didPickDocumentsAt urls:[URL]) {
            // asCopy keeps provider files in the app's sandbox after dismissal.
            for file in urls {receiveImage(file:file,origin:parent.origin,store:parent.store)}
            parent.dismiss()
        }
        func documentPickerWasCancelled(_ controller:UIDocumentPickerViewController) {parent.dismiss()}
    }
}
@MainActor
struct PhotoPicker: UIViewControllerRepresentable {
    let store: ChatStore
    let origin: ImageOrigin
    let limit: Int
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(); configuration.filter = .images; configuration.selectionLimit = max(1,limit)
        let picker = PHPickerViewController(configuration:configuration); picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ controller: PHPickerViewController, context: Context) { }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        init(_ parent: PhotoPicker) { self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            for result in results { receiveImage(provider:result.itemProvider,origin:parent.origin,store:parent.store) }
        }
    }
}
@MainActor
struct NativeComposer: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    @Binding var composing: Bool
    @Binding var height: CGFloat
    var suggestionCount: Int
    var submit: () -> Void
    var choose: () -> Void
    var move: (Int) -> Void
    var dismissSuggestions: () -> Void
    var pasteProvider: (NSItemProvider) -> Void
    var beganEditing: () -> Void
    func makeUIView(context: Context) -> ComposerTextView {
        let view = ComposerTextView(); view.delegate = context.coordinator; view.pasteDelegate = context.coordinator
        view.font = UIFontMetrics(forTextStyle:.body).scaledFont(for:UIFont.systemFont(ofSize:16)); view.adjustsFontForContentSizeCategory = true
        view.textColor = UIColor(red:25/255,green:25/255,blue:25/255,alpha:1)
        view.backgroundColor = .white; view.layer.cornerRadius = 5
        view.returnKeyType = .send; view.textContainerInset = UIEdgeInsets(top:10,left:11,bottom:10,right:11);view.textContainer.lineFragmentPadding = 0
        view.pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers:[UTType.image.identifier,UTType.plainText.identifier])
        view.accessibilityLabel = "发送消息";view.accessibilityIdentifier = "chat_input"; return view
    }
    func updateUIView(_ view: ComposerTextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text && view.markedTextRange == nil { view.text = text; view.selectedRange = NSRange(location:min(selection.location,(text as NSString).length),length:0) }
        else if view.markedTextRange == nil, view.selectedRange != selection, NSMaxRange(selection) <= (text as NSString).length { view.selectedRange = selection }
        view.submit = { [weak view] in if let view {context.coordinator.enter(view)} }; view.move = move; view.dismissSuggestions = dismissSuggestions; view.hasSuggestions = suggestionCount > 0
        view.heightChanged = {next in DispatchQueue.main.async {if abs(context.coordinator.parent.height-next)>0.5 {context.coordinator.parent.height = next}}}
        view.reportHeight()
    }
    func sizeThatFits(_ proposal:ProposedViewSize,uiView:ComposerTextView,context:Context) -> CGSize? {
        // Once scrolling is disabled for a short draft, UITextView's intrinsic
        // width follows typed text. Accept the row's width instead, so wrapping
        // and height reporting cannot push the attachment/send controls away.
        guard let width = proposal.width,width.isFinite else {return nil}
        return CGSize(width:max(0,width),height:proposal.height ?? height)
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UITextViewDelegate, UITextPasteDelegate {
        var parent: NativeComposer
        init(_ parent: NativeComposer) { self.parent = parent }
        func textViewDidChange(_ view: UITextView) { parent.text = view.text; parent.selection = view.selectedRange; parent.composing = view.markedTextRange != nil;(view as? ComposerTextView)?.reportHeight() }
        func textViewDidBeginEditing(_ view: UITextView) {parent.beganEditing()}
        func textViewDidChangeSelection(_ view: UITextView) { parent.selection = view.selectedRange; parent.composing = view.markedTextRange != nil }
        func textView(_ view: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n", view.markedTextRange == nil, (view as? ComposerTextView)?.insertingNewline != true { enter(view); return false }; return true
        }
        func enter(_ view:UITextView) {
            guard view.markedTextRange == nil else {return}
            parent.composing = false
            if parent.suggestionCount>0 {parent.choose()} else {parent.submit()}
        }
        func textPasteConfigurationSupporting(_ supporting: UITextPasteConfigurationSupporting, transform item: UITextPasteItem) {
            if item.itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) { parent.pasteProvider(item.itemProvider); item.setNoResult() }
            else { item.setDefaultResult() }
        }
    }
}
@MainActor
final class ComposerTextView: UITextView {
    var insertingNewline = false
    var submit: (() -> Void)?; var move: ((Int) -> Void)?; var dismissSuggestions: (() -> Void)?
    var hasSuggestions = false
    var heightChanged: ((CGFloat) -> Void)?
    private let placeholderLabel = UILabel()
    private var reportedHeight:CGFloat = 0
    override init(frame:CGRect,textContainer:NSTextContainer?) {super.init(frame:frame,textContainer:textContainer);configurePlaceholder()}
    required init?(coder:NSCoder) {super.init(coder:coder);configurePlaceholder()}
    private func configurePlaceholder() {placeholderLabel.text = "发送消息";placeholderLabel.textColor = UIColor(white:170/255,alpha:1);placeholderLabel.isUserInteractionEnabled = false;addSubview(placeholderLabel)}
    override func layoutSubviews() {
        super.layoutSubviews();placeholderLabel.font = font
        placeholderLabel.frame = CGRect(x:textContainerInset.left,y:textContainerInset.top,width:max(0,bounds.width-textContainerInset.left-textContainerInset.right),height:font?.lineHeight ?? 20)
        reportHeight()
    }
    func reportHeight() {
        placeholderLabel.isHidden = !text.isEmpty
        guard bounds.width>0 else {return}
        let ideal = sizeThatFits(CGSize(width:bounds.width,height:.greatestFiniteMagnitude)).height
        let maximum = (font?.lineHeight ?? 20)*4+20,next = min(maximum,max(40,ceil(ideal)))
        let scrolling = ideal>maximum+0.5
        if isScrollEnabled != scrolling {isScrollEnabled = scrolling}
        if abs(reportedHeight-next)>0.5 {reportedHeight = next;heightChanged?(next)}
    }
    override var keyCommands: [UIKeyCommand]? {
        guard markedTextRange == nil else {return super.keyCommands}
        var commands = [UIKeyCommand(input:"\r",modifierFlags:.shift,action:#selector(newline)),UIKeyCommand(input:"\r",modifierFlags:.command,action:#selector(send))]
        if hasSuggestions,markedTextRange == nil { commands += [UIKeyCommand(input:UIKeyCommand.inputUpArrow,modifierFlags:[],action:#selector(up)),UIKeyCommand(input:UIKeyCommand.inputDownArrow,modifierFlags:[],action:#selector(down)),UIKeyCommand(input:"\t",modifierFlags:[],action:#selector(send)),UIKeyCommand(input:UIKeyCommand.inputEscape,modifierFlags:[],action:#selector(escape))] }
        for command in commands {command.wantsPriorityOverSystemBehavior = true}
        return commands + (super.keyCommands ?? [])
    }
    @objc private func newline() { guard markedTextRange == nil else { return }; insertingNewline = true; insertText("\n"); insertingNewline = false }
    @objc private func send() { if markedTextRange == nil { submit?() } }
    @objc private func up() { move?(-1) }; @objc private func down() { move?(1) }; @objc private func escape() { dismissSuggestions?() }
}
