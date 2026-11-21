import SwiftUI
import UIKit

// Values and vector geometry follow Android ChatUi and res/drawable/ic_*.xml.
enum MobileStyle {
    static let green = color(0x07B75A), ink = color(0x191919), muted = color(0x8A8A8A)
    static let line = color(0xE7E7E7), bar = color(0xF7F7F7), chat = color(0xEDEDED)
    static let outgoing = color(0xB2EC86)
    static let version = "0.16.2"
    static func color(_ rgb: UInt32) -> Color {
        Color(red:Double((rgb >> 16) & 255)/255,green:Double((rgb >> 8) & 255)/255,blue:Double(rgb & 255)/255)
    }
}

enum MobileSymbol { case agents, groups, settings, plus, more, back, chevron, refresh, usage, photo, compact, context, restore, clear, threads, newChat, mention, favorite, document, close }

struct MobileIcon: View {
    let symbol: MobileSymbol
    var size: CGFloat = 24
    var color: Color = MobileStyle.ink
    var lineWidth: CGFloat? = nil
    var body: some View {
        MobileIconPath(symbol:symbol)
            .stroke(color,style:StrokeStyle(lineWidth:(lineWidth ?? (symbol == .settings ? 1.5 : symbol == .more ? 3.5 : 1.7))*size/24,lineCap:.round,lineJoin:.round))
            .overlay { if symbol == .usage { usage.fill(color) } }
            .frame(width:size,height:size).accessibilityHidden(true)
    }
    private var usage: Path {
        var p = Path()
        for (x,y,h): (CGFloat,CGFloat,CGFloat) in [(4,13,8),(10,8,13),(16,3,18)] {
            p.addRect(CGRect(x:x*size/24,y:y*size/24,width:4*size/24,height:h*size/24))
        }
        return p
    }
}
private struct MobileIconPath: Shape {
    let symbol: MobileSymbol
    func path(in rect: CGRect) -> Path {
        var p = Path()
        func line(_ points: [(CGFloat,CGFloat)]) {
            guard let first = points.first else {return};p.move(to:CGPoint(x:first.0,y:first.1))
            for point in points.dropFirst() {p.addLine(to:CGPoint(x:point.0,y:point.1))}
        }
        func curve(_ x: CGFloat,_ y: CGFloat,_ a: CGFloat,_ b: CGFloat,_ c: CGFloat,_ d: CGFloat) {
            p.addCurve(to:CGPoint(x:x,y:y),control1:CGPoint(x:a,y:b),control2:CGPoint(x:c,y:d))
        }
        func quad(_ x: CGFloat,_ y: CGFloat,_ a: CGFloat,_ b: CGFloat) {p.addQuadCurve(to:CGPoint(x:x,y:y),control:CGPoint(x:a,y:b))}
        switch symbol {
        case .agents:
            p.addEllipse(in:CGRect(x:8,y:3,width:8,height:8));line([(4,21),(4,19)])
            curve(12,13,4,15,7.5,13);curve(20,19,16.5,13,20,15);p.addLine(to:CGPoint(x:20,y:21))
        case .groups:
            p.addEllipse(in:CGRect(x:5.5,y:4,width:7,height:7));line([(2,21),(2,18)])
            curve(9,13,2,14.5,5,13);curve(16,18,13,13,16,14.5);p.addLine(to:CGPoint(x:16,y:21))
            p.move(to:CGPoint(x:17,y:4));curve(18,11,21.5,4,22,10)
            p.move(to:CGPoint(x:18,y:14));curve(22,19,21,14.5,22,16.5);p.addLine(to:CGPoint(x:22,y:21))
        case .settings:
            line([(9.5,3),(14.5,3),(15,5.7),(17,6.9),(19.6,6),(22,10.2),(19.9,12),(19.9,14.3),(22,16),(19.6,20.2),(17,19.3),(15,20.5),(14.5,23),(9.5,23),(9,20.5),(7,19.3),(4.4,20.2),(2,16),(4.1,14.3),(4.1,12),(2,10.2),(4.4,6),(7,6.9),(9,5.7)]);p.closeSubpath()
            p.addEllipse(in:CGRect(x:8,y:9,width:8,height:8))
        case .plus:line([(12,4),(12,20)]);line([(4,12),(20,12)])
        case .more:for x: CGFloat in [4,12,20] {line([(x,12),(x+0.1,12)])}
        case .back:line([(15,4),(7,12),(15,20)])
        case .chevron:line([(9,6),(15,12),(9,18)])
        case .close:line([(6,6),(18,18)]);line([(18,6),(6,18)])
        case .photo:
            p.addRoundedRect(in:CGRect(x:4,y:4,width:16,height:16),cornerSize:CGSize(width:3,height:3))
            line([(4,16),(9,11),(13,15),(16,12),(20,16)]);p.addEllipse(in:CGRect(x:13.5,y:7,width:3,height:3))
        case .compact:
            line([(12,3),(12,9)]);line([(9,6),(12,9),(15,6)]);line([(6,12),(18,12)])
            line([(12,21),(12,15)]);line([(9,18),(12,15),(15,18)])
        case .context,.document:
            p.addRoundedRect(in:CGRect(x:6,y:3,width:12,height:18),cornerSize:CGSize(width:2,height:2))
            line([(9,8),(15,8)]);line([(9,12),(15,12)]);line([(9,16),(13,16)])
        case .restore:
            line([(4,14),(4,19)]);quad(6,21,4,21);p.addLine(to:CGPoint(x:18,y:21));quad(20,19,20,21);p.addLine(to:CGPoint(x:20,y:14))
            line([(8,10),(12,14),(16,10)]);line([(12,14),(12,3)])
        case .clear:
            line([(3,6),(21,6)]);line([(9,6),(9,3),(15,3),(15,6)]);line([(5,6),(6,19)]);quad(8,21,6,21);p.addLine(to:CGPoint(x:16,y:21));quad(18,19,18,21);p.addLine(to:CGPoint(x:19,y:6));line([(10,10),(10,17)]);line([(14,10),(14,17)])
        case .threads,.newChat:
            line([(7,4),(17,4)]);quad(20,7,20,4);p.addLine(to:CGPoint(x:20,y:14));quad(17,17,20,17)
            line([(17,17),(11,17),(6,21),(6,17)]);quad(4,14,4,17);p.addLine(to:CGPoint(x:4,y:7));quad(7,4,4,4);p.closeSubpath()
            if symbol == .threads {line([(8,8.5),(16,8.5)]);line([(8,12.5),(14,12.5)])}
            else {line([(9,10.5),(15,10.5)]);line([(12,7.5),(12,13.5)])}
        case .mention:
            p.addEllipse(in:CGRect(x:8,y:8,width:8,height:8));line([(16,8),(16,14)])
            curve(21,13,16,18,21,18);p.addLine(to:CGPoint(x:21,y:12));curve(12,3,21,7,17,3)
            curve(3,12,7,3,3,7);curve(12,21,3,17,7,21);curve(17.5,19,14,21,16,20.5)
        case .refresh:
            p.addArc(center:CGPoint(x:12,y:12),radius:8,startAngle:.degrees(-7),endAngle:.degrees(39),clockwise:true)
            line([(20,4),(20,11),(13,11)])
        case .favorite:
            line([(12,3),(14.8,8.7),(21,9.6),(16.5,14),(17.6,20.2),(12,17.3),(6.4,20.2),(7.5,14),(3,9.6),(9.2,8.7)]);p.closeSubpath()
        case .usage:break
        }
        return p.applying(CGAffineTransform(scaleX:rect.width/24,y:rect.height/24))
    }
}

struct MobileDivider: View {
    var leading: CGFloat = 0
    var body: some View {MobileStyle.line.frame(height:0.5).padding(.leading,leading)}
}
struct MobilePressStyle: ButtonStyle {
    var radius: CGFloat = 5
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(Color.black.opacity(configuration.isPressed ? 0.065 : 0),in:RoundedRectangle(cornerRadius:radius))
    }
}
struct MobileTextButton: View {
    let title: String
    var destructive = false
    var action: () -> Void
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action:action) {Text(title).font(.system(size:14)).foregroundStyle(destructive ? Color.red : MobileStyle.green).padding(.horizontal,12).padding(.vertical,8).frame(minHeight:44)}
            .buttonStyle(MobilePressStyle()).opacity(enabled ? 1 : 0.4)
    }
}
struct MobileToolArtwork:View {
    let title:String
    let symbol:MobileSymbol
    var body:some View {
        VStack(spacing:10) {
            MobileIcon(symbol:symbol,color:.black,lineWidth:1.7)
                .frame(width:56,height:56).background(.white,in:RoundedRectangle(cornerRadius:16))
                .overlay(RoundedRectangle(cornerRadius:16).stroke(MobileStyle.color(0xE5E8EB),lineWidth:1))
            Text(title).font(.system(size:12,weight:.regular)).foregroundStyle(.black).lineLimit(2)
        }.padding(.top,6).frame(maxWidth:.infinity,minHeight:96,alignment:.top).contentShape(Rectangle())
    }
}
struct MobileIconButton: View {
    let symbol: MobileSymbol
    let label: String
    var action: () -> Void
    var body: some View {
        Button(action:action) {MobileIcon(symbol:symbol).frame(width:44,height:44).contentShape(Rectangle())}
            .buttonStyle(MobilePressStyle(radius:22)).accessibilityLabel(label)
    }
}
struct MobileHeader<Actions: View>: View {
    let title: String
    var home = false
    var back: (() -> Void)? = nil
    @ViewBuilder var actions: Actions
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:0) {
                if home {
                    Text(title).font(.system(size:21,weight:.bold)).frame(maxWidth:.infinity,alignment:.leading)
                } else {
                    if let back {MobileIconButton(symbol:.back,label:"返回",action:back)} else {Color.clear.frame(width:44,height:44)}
                    Text(title).font(.system(size:16)).lineLimit(1).frame(maxWidth:.infinity)
                }
                actions.frame(width:44,height:44)
            }.foregroundStyle(MobileStyle.ink).padding(.leading,home ? 18 : 4).padding(.trailing,home ? 6 : 4).frame(height:home ? 56 : 48)
            MobileDivider()
        }.background(MobileStyle.bar)
    }
}

private struct DialogContentHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat,nextValue: () -> CGFloat) {value = max(value,nextValue())}
}
struct MobileDialog<Content: View,Actions: View>: View {
    let title: String
    var close: () -> Void
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions
    @State private var contentHeight: CGFloat = 240
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.32).ignoresSafeArea().onTapGesture(perform:close)
                VStack(alignment:.leading,spacing:0) {
                    Text(title).font(.system(size:20,weight:.medium)).padding(.horizontal,24).padding(.top,22).padding(.bottom,12)
                    ScrollView {
                        VStack(alignment:.leading,spacing:0) {content}.frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,24)
                            .background(GeometryReader {proxy in Color.clear.preference(key:DialogContentHeight.self,value:proxy.size.height)})
                    }.frame(height:min(contentHeight,max(100,geometry.size.height-170)))
                        .onPreferenceChange(DialogContentHeight.self) {if abs(contentHeight-$0)>0.5 {contentHeight = $0}}
                    HStack(spacing:4) {Spacer(minLength:0);actions}.padding(.horizontal,12).padding(.top,10).padding(.bottom,12)
                }.foregroundStyle(MobileStyle.ink).background(.white,in:RoundedRectangle(cornerRadius:20))
                    .frame(width:min(560,max(260,geometry.size.width-48))).shadow(color:.black.opacity(0.15),radius:24,y:6)
                    .accessibilityAddTraits(.isModal)
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        }.accessibilityIdentifier("dialog_"+title)
    }
}
struct MobileField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment:.leading,spacing:4) {
            Text(label).font(.system(size:12)).foregroundStyle(MobileStyle.muted)
            content.font(.system(size:15)).padding(.vertical,9)
            MobileStyle.line.frame(height:1)
        }.padding(.top,18)
    }
}
struct MobileBubbleShape: Shape {
    let mine: Bool
    var wide = false
    func path(in rect: CGRect) -> Path {
        guard !wide else {return Path(roundedRect:rect,cornerRadius:5)}
        let body = rect.inset(by:UIEdgeInsets(top:0,left:mine ? 0 : 4,bottom:0,right:mine ? 4 : 0))
        var path = Path(roundedRect:body,cornerRadius:5)
        let edge = mine ? rect.maxX-4 : rect.minX+4,tip = mine ? rect.maxX : rect.minX
        path.move(to:CGPoint(x:edge,y:rect.minY+13));path.addLine(to:CGPoint(x:tip,y:rect.minY+17));path.addLine(to:CGPoint(x:edge,y:rect.minY+21));path.closeSubpath()
        return path
    }
}
