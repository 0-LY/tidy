import AppKit

let args = CommandLine.arguments
if args.count > 1, args[1] == "--copy" {
    let text = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
    let pb = NSPasteboard.general
    pb.clearContents()
    let item = NSPasteboardItem()
    item.setString(text, forType: .string)
    item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
    item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
    pb.writeObjects([item])
    exit(0)
}

let state = args.count > 1 ? args[1] : "done"
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name((Bundle.main.bundleIdentifier ?? "app") + ".state"),
    object: state,
    userInfo: nil,
    deliverImmediately: true
)
