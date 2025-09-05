import SwiftUI
import UIKit

// ---------- Small, compiler-friendly data ----------
enum Mode: String, CaseIterable { case scale = "Scale", chord = "Chord", custom = "Custom" }

let ROOTS: [String] = ["C","C#","Db","D","D#","Eb","E","F","F#","Gb","G","G#","Ab","A","A#","Bb","B"]
let SCALE_NAMES: [String] = ["Major (Ionian)","Natural Minor (Aeolian)","Dorian","Phrygian","Lydian","Mixolydian","Locrian","Major Pentatonic","Minor Pentatonic","Blues","Harmonic Minor","Melodic Minor (Jazz)"]
let CHORD_NAMES: [String] = ["Major (Triad)","Minor (Triad)","Diminished (Triad)","Augmented (Triad)","Maj7","m7","7 (Dominant)","m(maj7)","m7(b5)","dim7","sus2","sus4","add9","6","m6","9","m9"]

let NAMES_SHARP = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
let NAMES_FLAT  = ["C","Db","D","Eb","E","F","Gb","G","Ab","A","Bb","B"]
@inline(__always) func isBlackPC(_ pc: Int) -> Bool { [1,3,6,8,10].contains(pc) }
@inline(__always) func pcName(_ pc: Int, preferFlat: Bool) -> String { (preferFlat ? NAMES_FLAT : NAMES_SHARP)[(pc%12+12)%12] }

func parseNote(_ s: String) -> (pc: Int, octave: Int?)? {
    let s = s.trimmingCharacters(in: .whitespaces)
    let pattern = #"^([A-Ga-g])([#b]?)(\d+)?"#
    guard let re = try? NSRegularExpression(pattern: pattern),
          let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
    func part(_ i: Int) -> String? { Range(m.range(at: i), in: s).map { String(s[$0]) } }
    guard let Ls = part(1) else { return nil }
    let L = Ls.uppercased(), acc = part(2) ?? "", octStr = part(3)
    let base = ["C":0,"D":2,"E":4,"F":5,"G":7,"A":9,"B":11][L]!
    var pc = base + (acc=="#" ? 1 : (acc=="b" ? -1 : 0))
    pc = (pc%12+12)%12
    return (pc, octStr.flatMap{ Int($0) })
}
@inline(__always) func pcFrom(_ s: String) -> Int? { parseNote(s)?.pc }

// Intervals
let SCALES: [String:[Int]] = [
    "Major (Ionian)":[0,2,4,5,7,9,11],
    "Natural Minor (Aeolian)":[0,2,3,5,7,8,10],
    "Dorian":[0,2,3,5,7,9,10],
    "Phrygian":[0,1,3,5,7,8,10],
    "Lydian":[0,2,4,6,7,9,11],
    "Mixolydian":[0,2,4,5,7,9,10],
    "Locrian":[0,1,3,5,6,8,10],
    "Major Pentatonic":[0,2,4,7,9],
    "Minor Pentatonic":[0,3,5,7,10],
    "Blues":[0,3,5,6,7,10],
    "Harmonic Minor":[0,2,3,5,7,8,11],
    "Melodic Minor (Jazz)":[0,2,3,5,7,9,11],
]
let CHORDS: [String:[Int]] = [
    "Major (Triad)":[0,4,7], "Minor (Triad)":[0,3,7], "Diminished (Triad)":[0,3,6], "Augmented (Triad)":[0,4,8],
    "Maj7":[0,4,7,11], "m7":[0,3,7,10], "7 (Dominant)":[0,4,7,10], "m(maj7)":[0,3,7,11],
    "m7(b5)":[0,3,6,10], "dim7":[0,3,6,9], "sus2":[0,2,7], "sus4":[0,5,7],
    "add9":[0,4,7,14], "6":[0,4,7,9], "m6":[0,3,7,9], "9":[0,4,7,10,14], "m9":[0,3,7,10,14]
]

// ---------- UIKit drawing view ----------
final class PianoCGView: UIView {
    // Config
    var showLabels: Bool = true { didSet { setNeedsDisplay() } }
    var preferFlats: Bool = false { didSet { setNeedsDisplay() } }
    var rootPC: Int = 0 { didSet { setNeedsDisplay() } }
    var members = Set<Int>() { didSet { setNeedsDisplay() } }
    
    // C3 (48) … B6 (95)
    let minM = 48, maxM = 95
    
    // Thingy to add support for key touches
    var onTapPC: ((Int) -> Void)?
    
    override class var layerClass: AnyClass { CATiledLayer.self }
    
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        
        let W = bounds.width
        let H = bounds.height
        
        // Count whites in range
        var whiteCount = 0
        for m in minM...maxM { if !isBlackPC(m%12) { whiteCount += 1 } }
        
        // Geometry
        let ww = max(22, floor(W / CGFloat(whiteCount)))
        let wh = H * 0.92
        let bw = floor(ww * 0.58)            // slightly narrower to emphasize “between”
        let bh = floor(wh * 0.62)
        let whiteW = ww - 1                  // actual drawn width of a white key
        
        // Colors & strokes (single blue scheme + thicker separators)
        let memFill     = UIColor.systemBlue.withAlphaComponent(0.85)    // one blue for all highlighted notes
        let memFillBlack    = UIColor.systemBlue                          // opaque for BLACK keys
        let whiteBorder = UIColor.black.withAlphaComponent(0.55)         // darker separators
        let blackBorder = UIColor.black
        let labelDark   = UIColor.label.withAlphaComponent(0.9)
        let labelLight  = UIColor.white.withAlphaComponent(0.95)
        let whiteLineW: CGFloat = 2.0
        let blackLineW: CGFloat = 2.2
        
        // Background
        ctx.setFillColor(UIColor.systemGroupedBackground.cgColor)
        ctx.fill(bounds)
        
        // Draw whites
        var x: CGFloat = 0
        var whiteXByMidi: [Int:CGFloat] = [:]
        for m in minM...maxM {
            let pc = m % 12
            if !isBlackPC(pc) {
                let r = CGRect(x: x, y: 0, width: whiteW, height: wh)
                
                // base white
                ctx.setFillColor(UIColor.white.cgColor)
                ctx.fill(r)
                // thicker separator
                ctx.setLineWidth(whiteLineW)
                ctx.setStrokeColor(whiteBorder.cgColor)
                ctx.stroke(r)
                
                // highlight if member (single blue)
                let isMember = members.contains(pc)
                if isMember {
                    ctx.setFillColor(memFill.cgColor)
                    ctx.fill(r)
                    // redraw border so edges stay visible
                    ctx.setStrokeColor(whiteBorder.cgColor)
                    ctx.stroke(r.insetBy(dx: 1.0, dy: 1.0))
                }
                
                // C locator stripe (orientation aid)
                if pc == 0 {
                    let stripe = CGRect(x: r.minX + 2, y: r.minY + 2, width: r.width - 4, height: 3)
                    ctx.setFillColor(UIColor.systemRed.withAlphaComponent(0.75).cgColor)
                    ctx.fill(stripe)
                }
                
                // label
                if showLabels {
                    let text = "\(pcName(pc, preferFlat: preferFlats))\(m/12 - 1)" as NSString
                    let attrs: [NSAttributedString.Key:Any] = [
                        .font: UIFont.systemFont(ofSize: 10, weight: .regular),
                        .foregroundColor: labelDark
                    ]
                    let size = text.size(withAttributes: attrs)
                    text.draw(at: CGPoint(x: x + (whiteW - size.width)/2, y: wh - 4 - size.height), withAttributes: attrs)
                }
                
                // ROOT badge “R” (on whites, upper third, centered)
                if pc == rootPC {
                    let R = "R" as NSString
                    let Rattrs: [NSAttributedString.Key:Any] = [
                        .font: UIFont.boldSystemFont(ofSize: 12),
                        .foregroundColor: UIColor.systemRed
                    ]
                    let Rsize = R.size(withAttributes: Rattrs)
                    let Rx = x + (whiteW - Rsize.width)/2
                    let Ry = r.minY + max(4, (wh * 0.18) - Rsize.height/2)
                    R.draw(at: CGPoint(x: Rx, y: Ry), withAttributes: Rattrs)
                }
                
                whiteXByMidi[m] = x
                x += ww
            }
        }
        
        // Draw blacks on top (centered exactly between neighboring whites)
        for m in minM...maxM {
            let pc = m % 12
            guard isBlackPC(pc),
                  let prevX = whiteXByMidi[m - 1],
                  let nextX = whiteXByMidi[m + 1] else { continue }
            
            let prevCenter = prevX + whiteW/2
            let nextCenter = nextX + whiteW/2
            let bx = (prevCenter + nextCenter)/2 - bw/2
            let r = CGRect(x: bx, y: 0, width: bw, height: bh)
            
            let isMember = members.contains(pc)
            
            // fill: members = blue, others = black
            ctx.setFillColor((isMember ? memFillBlack : UIColor.black).cgColor)
            ctx.fill(r.integral)  // integral to avoid half-pixel seams
            
            // border: white edge for members, black otherwise (thicker)
//            ctx.setLineWidth(blackLineW)
            ctx.setLineWidth(2.4)
            if isMember {
                ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.85).cgColor)
                ctx.stroke(r.insetBy(dx: 0.8, dy: 0.8))
            } else {
                ctx.setStrokeColor(blackBorder.cgColor)
                ctx.stroke(r)
            }
            
            // label on black
            if showLabels {
                let text = pcName(pc, preferFlat: preferFlats) as NSString
                let attrs: [NSAttributedString.Key:Any] = [
                    .font : UIFont.systemFont(ofSize: 9, weight: .regular),
                    .foregroundColor : labelLight
                ]
                let size = text.size(withAttributes: attrs)
                text.draw(at: CGPoint(x: bx + (bw - size.width)/2, y: bh - 6 - size.height), withAttributes: attrs)
            }
            
            // ROOT badge “R” on black (white text)
            if pc == rootPC {
                let R = "R" as NSString
                let Rattrs: [NSAttributedString.Key:Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 11),
                    .foregroundColor: UIColor.white
                ]
                let Rsize = R.size(withAttributes: Rattrs)
                let Rx = bx + (bw - Rsize.width)/2
                let Ry = r.minY + max(3, (bh * 0.18) - Rsize.height/2)
                R.draw(at: CGPoint(x: Rx, y: Ry), withAttributes: Rattrs)
            }
        }
    }
    
    private func pcAt(point p: CGPoint) -> Int? {
        // Recompute the same geometry used for drawing
        var whiteCount = 0
        for m in minM...maxM { if !isBlackPC(m%12) { whiteCount += 1 } }
        let ww = max(22, floor(bounds.width / CGFloat(whiteCount)))
        let wh = bounds.height * 0.92
        let bw = floor(ww * 0.58)
        let bh = floor(wh * 0.62)
        let whiteW = ww - 1
        
        // Build white positions
        var x: CGFloat = 0
        var whiteXByMidi: [Int:CGFloat] = [:]
        for m in minM...maxM {
            let pc = m % 12
            if !isBlackPC(pc) {
                whiteXByMidi[m] = x
                x += ww
            }
        }
        
        // 1) Check BLACK keys first (they sit on top)
        for m in minM...maxM {
            let pc = m % 12
            guard isBlackPC(pc),
                  let prevX = whiteXByMidi[m - 1],
                  let nextX = whiteXByMidi[m + 1] else { continue }
            let prevCenter = prevX + whiteW/2
            let nextCenter = nextX + whiteW/2
            let bx = (prevCenter + nextCenter)/2 - bw/2
            let r = CGRect(x: bx, y: 0, width: bw, height: bh)
            if r.contains(p) { return pc }
        }
        
        // 2) Then WHITES
        for m in minM...maxM {
            let pc = m % 12
            if !isBlackPC(pc), let wx = whiteXByMidi[m] {
                let r = CGRect(x: wx, y: 0, width: whiteW, height: wh)
                if r.contains(p) { return pc }
            }
        }
        return nil
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let p = touches.first?.location(in: self),
              let pc = pcAt(point: p) else { return }
        onTapPC?(pc)
    }
    
}

// SwiftUI wrapper
struct PianoCGViewRepresentable: UIViewRepresentable {
    @Binding var showLabels: Bool
    @Binding var preferFlats: Bool
    @Binding var rootPC: Int
    @Binding var members: Set<Int>
    var onTapPC: (Int) -> Void = { _ in }   // NEW
    
    func makeUIView(context: Context) -> PianoCGView {
        let v = PianoCGView()
        v.isOpaque = true
        v.backgroundColor = .systemGroupedBackground
        v.contentScaleFactor = UIScreen.main.scale
        v.onTapPC = onTapPC                 // NEW
        return v
    }
    func updateUIView(_ uiView: PianoCGView, context: Context) {
        uiView.showLabels = showLabels
        uiView.preferFlats = preferFlats
        uiView.rootPC = rootPC
        uiView.members = members
        uiView.onTapPC = onTapPC            // keep it updated
    }
}

// ---------- ViewModel with precomputed state ----------
final class PianoVM: ObservableObject {
    @Published var mode: Mode = .scale
    @Published var root: String = "C"
    @Published var scaleName: String = "Major (Ionian)"
    @Published var chordName: String = "Major (Triad)"
    @Published var showLabels: Bool = true
    @Published var preferFlats: Bool = false
    @Published var customText: String = ""
    @Published var members = Set<Int>()   // stored result
    
    var rootPC: Int { pcFrom(root) ?? 0 }
    
    func recalcMembers() {
        switch mode {
        case .scale:
            let ivs = SCALES[scaleName] ?? [0,2,4,5,7,9,11]
            members = Set(ivs.map { (rootPC + $0) % 12 })
        case .chord:
            let ivs = CHORDS[chordName] ?? [0,4,7]
            members = Set(ivs.map { (rootPC + $0) % 12 })
        case .custom:
            let pcs = customText.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.compactMap(pcFrom)
            members = Set(pcs)
        }
        preferFlats = root.contains("b") && !root.contains("#")
        updateReadout()
    }
    
    @Published var noteListText: String = ""
    @Published var chordGuessText: String = ""
    
    // Toggle from taps (switch to Custom automatically)
    func toggleFromTap(pc: Int) {
        if mode != .custom { mode = .custom }
        if members.contains(pc) { members.remove(pc) } else { members.insert(pc) }
        updateReadout()
    }
    
    // Rebuild the text readout (note names and a chord guess)
    func updateReadout() {
        // Notes (prefer flats if root is written as flat)
        let preferFlatsNow = root.contains("b") && !root.contains("#")
        let names = members.sorted().map { pcName($0, preferFlat: preferFlatsNow) }
        noteListText = names.joined(separator: ", ")
        
        // Chord detection (simple triad/7th templates, inversion-agnostic)
        chordGuessText = guessChord(pcs: members, preferFlats: preferFlatsNow) ?? "—"
    }
    
    // Very simple chord guesser (triads + sevenths). Returns e.g. "C#m7" or "Fmaj7".
    func guessChord(pcs: Set<Int>, preferFlats: Bool) -> String? {
        if pcs.isEmpty { return nil }
        // Normalize: for each possible root, compute intervals mod 12 and check known shapes
        let triads: [(name: String, ivs:Set<Int>)] = [
            ("maj", [0,4,7]), ("min", [0,3,7]), ("dim", [0,3,6]), ("aug", [0,4,8])
        ]
        let sevenths: [(name: String, ivs:Set<Int>)] = [
            ("maj7", [0,4,7,11]), ("7", [0,4,7,10]), ("m7", [0,3,7,10]),
            ("mMaj7", [0,3,7,11]), ("m7b5", [0,3,6,10]), ("dim7", [0,3,6,9])
        ]
        for root in 0..<12 {
            let rel = Set(pcs.map { ($0 - root + 12) % 12 })
            if rel.count == 3 {
                if let m = triads.first(where: { $0.ivs == rel }) {
                    return "\(pcName(root, preferFlat: preferFlats))" + (m.name == "maj" ? "" : (m.name == "min" ? "m" : m.name))
                }
            } else if rel.count == 4 {
                if let m = sevenths.first(where: { $0.ivs == rel }) {
                    // nicer printing for a few cases
                    switch m.name {
                    case "7": return "\(pcName(root, preferFlat: preferFlats))7"
                    case "maj7": return "\(pcName(root, preferFlat: preferFlats))maj7"
                    case "m7": return "\(pcName(root, preferFlat: preferFlats))m7"
                    case "mMaj7": return "\(pcName(root, preferFlat: preferFlats))m(maj7)"
                    case "m7b5": return "\(pcName(root, preferFlat: preferFlats))m7♭5"
                    case "dim7": return "\(pcName(root, preferFlat: preferFlats))dim7"
                    default: return "\(pcName(root, preferFlat: preferFlats))" + m.name
                    }
                }
            }
        }
        return nil
    }
    
}

// ---------- Minimal SwiftUI UI (tiny, fast) ----------
struct ContentView: View {
    @StateObject var vm = PianoVM()
    
    var body: some View {
        VStack(spacing: 12) {
            // Row 1
            HStack {
                Picker("Mode", selection: $vm.mode) {
                    Text("Scale").tag(Mode.scale)
                    Text("Chord").tag(Mode.chord)
                    Text("Custom").tag(Mode.custom)
                }
                .pickerStyle(.segmented)
                Toggle("Labels", isOn: $vm.showLabels)
                    .frame(width: 120, alignment: .leading)
            }
            // Row 2
            HStack {
                Picker("Root", selection: $vm.root) {
                    ForEach(ROOTS, id:\.self) { Text($0).tag($0) }
                }
                if vm.mode == .scale {
                    Picker("Scale", selection: $vm.scaleName) {
                        ForEach(SCALE_NAMES, id:\.self) { Text($0).tag($0) }
                    }
                } else if vm.mode == .chord {
                    Picker("Chord", selection: $vm.chordName) {
                        ForEach(CHORD_NAMES, id:\.self) { Text($0).tag($0) }
                    }
                }
            }
            // Row 3 (custom)
            if vm.mode == .custom {
                TextField("Custom notes (C4,E4,G4,Bb4)", text: $vm.customText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
            }
            // Legend (unchanged)
            HStack(spacing: 14) {
                Circle().fill(Color.blue).frame(width: 12, height: 12)
                Text("Highlighted notes").font(.footnote)
                RoundedRectangle(cornerRadius: 3).stroke(.gray, lineWidth: 1).frame(width: 14, height: 14)
                Text("“R” marks root").font(.footnote)
                Spacer()
            }
            .opacity(0.9)
            
            // Readout (NEW)
            HStack {
                Text("Notes: ").font(.footnote).foregroundStyle(.secondary)
                Text(vm.noteListText.isEmpty ? "—" : vm.noteListText).font(.footnote)
                Spacer()
                Text("Chord: ").font(.footnote).foregroundStyle(.secondary)
                Text(vm.chordGuessText).font(.footnote).bold()
            }
            .padding(.bottom, 4)
            
            // Keyboard view (pass onTapPC)
            PianoCGViewRepresentable(showLabels: $vm.showLabels,
                                     preferFlats: $vm.preferFlats,
                                     rootPC: .init(get: { vm.rootPC }, set: { _ in }),
                                     members: $vm.members,
                                     onTapPC: { pc in vm.toggleFromTap(pc: pc) })   // ← NEW
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3)))
        }
        .padding()
        .onAppear { vm.recalcMembers() }
        .onChange(of: vm.mode) { _,_ in vm.recalcMembers() }
        .onChange(of: vm.root) { _,_ in vm.recalcMembers() }
        .onChange(of: vm.scaleName) { _,_ in vm.recalcMembers() }
        .onChange(of: vm.chordName) { _,_ in vm.recalcMembers() }
        .onChange(of: vm.customText) { _,_ in vm.recalcMembers() }
    }
}
