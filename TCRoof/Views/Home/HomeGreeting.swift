import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The one-line greeting in the iPhone home header: written by the on-device model (iOS 26, Apple Intelligence)
/// from today's facts, or picked from Thai templates built from the same facts.
enum HomeGreeting {
    struct Facts: Equatable {
        var hour: Int
        /// "NO.224" or the job code of the next appointment.
        var nextName: String?
        var nextTime: String?
        /// Report progress of the next appointment, when it has a report.
        var percent: Int?
        /// "ถังน้ำใส": title of the next step to fill.
        var nextStepTitle: String?
        var pendingSync: Int
    }

    /// "สวัสดีตอนเช้า" / "ตอนบ่าย" / "ตอนเย็น": shown when the AI greeting is switched off.
    static func plain(hour: Int) -> String {
        hour < 12 ? "สวัสดีตอนเช้า" : hour < 17 ? "สวัสดีตอนบ่าย" : "สวัสดีตอนเย็น"
    }

    /// Every template the facts can fill; each mentions at least one real fact.
    static func templates(_ f: Facts) -> [String] {
        var out: [String] = []
        if let name = f.nextName {
            if f.hour < 11 { out.append("ตื่นแล้วเหรอ? หลังคา \(name) ยังรออยู่นะ") }
            if let t = f.nextTime { out.append("\(t) นัดสำรวจ \(name) เตรียมรองเท้าลุยได้เลย") }
            if let p = f.percent, p > 0, p < 100 {
                out.append("อีก \(100 - p)% ก็จบ \(name)" + (f.nextStepTitle.map { " \($0)รอให้ไปวัดอยู่" } ?? " สู้อีกนิดนะ"))
            }
        } else {
            out.append("วันนี้ไม่มีนัดสำรวจ เคลียร์รายงานค้างได้สบาย ๆ")
        }
        if f.pendingSync > 0 {
            out.append("ซิงก์ค้าง \(f.pendingSync) งาน Google Drive เริ่มน้อยใจแล้ว")
        } else if f.nextName == nil {
            out.append("ซิงก์ครบทุกงานแล้ว คลาวด์ยิ้มแก้มปริ")
        }
        return out
    }

    /// The template after `previous` in the list, so each tap shows a different line.
    static func template(_ f: Facts, after previous: String) -> String {
        let list = templates(f)
        guard let i = list.firstIndex(of: previous) else { return list.first ?? plain(hour: f.hour) }
        return list[(i + 1) % list.count]
    }

    /// A line from the on-device model, or nil when it is unavailable, can't write Thai, or leaves out every fact.
    static func onDevice(_ f: Facts, avoiding previous: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) { return await OnDeviceGreeting.make(f, avoiding: previous) }
        #endif
        return nil
    }

    /// Words of the facts; a model line must contain one of them.
    static func factWords(_ f: Facts) -> [String] {
        [f.nextName, f.nextTime, f.percent.map { "\(100 - $0)%" }, f.percent.map { "\($0)%" }, f.nextStepTitle,
         f.pendingSync > 0 ? "\(f.pendingSync)" : nil].compactMap { $0 }
    }
}

#if canImport(FoundationModels)
@available(iOS 26, *)
private enum OnDeviceGreeting {
    static func make(_ f: HomeGreeting.Facts, avoiding previous: String) async -> String? {
        let model = SystemLanguageModel.default
        guard model.availability == .available, model.supportsLocale(Locale(identifier: "th_TH")) else { return nil }
        let session = LanguageModelSession(instructions: """
            คุณเขียนคำทักทายสั้น ๆ บนหน้าแรกของแอปช่างสำรวจโซลาร์เซลล์ \
            ตอบเป็นภาษาไทยหนึ่งประโยค ไม่เกิน 60 ตัวอักษร ขี้เล่นแต่สุภาพ \
            ห้ามใส่ชื่อผู้ใช้ ห้ามใส่ชื่อแอป ต้องพูดถึงข้อเท็จจริงที่ให้มาอย่างน้อยหนึ่งข้อ \
            ตอบเฉพาะประโยคนั้น ไม่มีเครื่องหมายคำพูด
            """)
        var facts = ["ช่วงเวลา: " + (f.hour < 12 ? "เช้า" : f.hour < 17 ? "บ่าย" : "เย็น")]
        if let n = f.nextName { facts.append("นัดสำรวจถัดไป: \(n)" + (f.nextTime.map { " เวลา \($0)" } ?? "")) }
        else { facts.append("วันนี้ไม่มีนัดสำรวจ") }
        if let p = f.percent { facts.append("กรอกแบบสำรวจแล้ว \(p)%") }
        if let s = f.nextStepTitle { facts.append("ขั้นถัดไป: \(s)") }
        facts.append("งานรอซิงก์: \(f.pendingSync) งาน")
        if !previous.isEmpty { facts.append("อย่าซ้ำกับ: \(previous)") }
        guard let reply = try? await session.respond(to: facts.joined(separator: "\n")) else { return nil }
        let line = reply.content.split(separator: "\n").first.map(String.init)?
            .trimmingCharacters(in: CharacterSet(charactersIn: " \"'“”")) ?? ""
        guard !line.isEmpty, line.count <= 70, line != previous,
              HomeGreeting.factWords(f).contains(where: line.contains) else { return nil }
        return line
    }
}
#endif
