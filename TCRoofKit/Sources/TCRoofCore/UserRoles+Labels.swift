import Foundation

// The labels, groups and notes of docs/reference/roles/user-roles.json, for the roles table (`RoleTableTests` checks them).

public struct CapabilityGroup: Identifiable, Sendable {
    public var id: String
    public var label: String
    public var capabilities: [Capability]
}

public extension Capability {
    /// The table's groups, in its order.
    static let groups: [CapabilityGroup] = [
        CapabilityGroup(id: "jobs_plan", label: "งานและแผนงาน", capabilities: [.jobList, .jobEdit, .jobDelete, .assignExternal, .assignTeam, .mpSetup, .mpProgress, .mpWBSTick, .moveToInstall, .installTracking, .overviewReports, .assistantUse]),
        CapabilityGroup(id: "survey_design_price", label: "สำรวจ ออกแบบ และราคา", capabilities: [.surveyEdit, .surveySignRev, .designLibrary, .tankStandard, .boqDraft, .boqApprove, .companyDocs]),
        CapabilityGroup(id: "customer_docs_permits", label: "เอกสารลูกค้าและการขออนุญาต", capabilities: [.customerPersonalDocs, .permitPPIM, .engineerCertify, .attachFiles, .driveUpload, .ercFlow, .stationDocsDrafts]),
        CapabilityGroup(id: "site_contractor", label: "หน้างานและผู้รับเหมา", capabilities: [.workOrder, .changeRequest, .punchList, .dailyFill, .weeklyRequest, .dailySign, .iecFillSubmit, .iecClose, .iclChecklist, .finalSignoff, .feedAckFix]),
        CapabilityGroup(id: "users_system", label: "ผู้ใช้และระบบ", capabilities: [.usersManage, .usersSuspend, .usersPermissions, .usersAdmin, .companyTemplates, .toolsRegister]),
    ]

    var label: String {
        switch self {
        case .jobList: "เห็นรายการงาน"
        case .jobEdit: "สร้างงาน | แก้ลูกค้า ทีม วันสำรวจ / ติดตั้ง"
        case .jobDelete: "ลบงาน"
        case .assignExternal: "มอบหมายงานให้วิศวกรภายนอก / ผู้รับเหมา"
        case .assignTeam: "กำหนดทีมงานของเราในงาน (งานของฉัน | แจ้งเตือนของงานไปถึงคนในทีมงานก่อน)"
        case .mpSetup: "ตั้งแผนงาน MP (วันที่ เกิน 200 kVA)"
        case .mpProgress: "ใส่ % ความคืบหน้าในแผนงาน"
        case .mpWBSTick: "ติ๊กงานย่อย WBS เสร็จ (นับเข้าแผน MP)"
        case .moveToInstall: "ย้ายแบบสำรวจไปงานติดตั้ง"
        case .installTracking: "หน้าติดตามงานติดตั้ง | สาเหตุล่าช้า"
        case .overviewReports: "ภาพรวมทุกสถานี | รายงานสัปดาห์ / เดือน"
        case .assistantUse: "ผู้ช่วยโครงการ (AI): ถามแผนงาน MP | เสนอบันทึกความก้าวหน้า"
        case .surveyEdit: "แบบสำรวจ | แบบไฟฟ้า | รายงานสำรวจ"
        case .surveySignRev: "ลงนามแบบสำรวจ | ออก REV ใหม่"
        case .designLibrary: "บันทึกแบบมาตรฐานลงคลัง | แก้ชื่อ เก็บเข้าคลัง นำเข้า"
        case .tankStandard: "แก้มาตรฐานโครงสร้างแผงบนถัง (แผง เสา ระยะแถว ระยะเว้น)"
        case .boqDraft: "ร่าง BOQ | เห็นราคาและต้นทุน"
        case .boqApprove: "อนุมัติ BOQ | ล็อกขนาดและราคาที่เสนอลูกค้า"
        case .companyDocs: "เอกสารกลางบริษัท (เอกสารวิศวกร สเปก ราคา)"
        case .customerPersonalDocs: "ข้อมูลส่วนตัวลูกค้า (บัตร ทะเบียนบ้าน บิล หนังสือมอบอำนาจ)"
        case .permitPPIM: "ฟอร์ม กฟภ. | ชุดยื่น PPIM | เลขคำขอและผล"
        case .engineerCertify: "เซ็นรับรองในฐานะวิศวกร"
        case .attachFiles: "แนบไฟล์ใน “เอกสารโครงการ”"
        case .driveUpload: "อัปโหลดขึ้น Google Drive (ทีม: Drive กลาง | ผู้รับเหมา: Drive ของตัวเอง)"
        case .ercFlow: "ลำดับ กกพ.: บันทึกวันยื่นและผล"
        case .stationDocsDrafts: "ร่างหนังสือจากแอป (แจ้งดับไฟ) | เอกสาร PWA ทุกสถานี"
        case .workOrder: "ออกใบสั่งงาน | บันทึกส่งของ"
        case .changeRequest: "ใบขอเปลี่ยนแปลง"
        case .punchList: "รายการที่ต้องแก้ (Punch list)"
        case .dailyFill: "รายงานประจำวัน: กรอก | รูป | สแกนเลขเครื่อง | ส่ง"
        case .weeklyRequest: "คำขอรายสัปดาห์ (R1): คน เครื่องมือ แผน ความเสี่ยง | ส่งขออนุมัติ"
        case .dailySign: "วิศวกรเซ็นรับทราบรายงาน (จึงนับเข้าแผน MP) | Inspector รับทราบ"
        case .iecFillSubmit: "ทดสอบ IEC 62446: วัดค่า กรอกผล ถ่ายรูป | ส่งผลให้ทีม"
        case .iecClose: "ทีมภายในปิดการทดสอบ IEC (จึงนับ 3.1 เข้าแผน MP) | ส่งกลับให้แก้"
        case .iclChecklist: "ใบตรวจรับงาน (ICL)"
        case .finalSignoff: "เซ็นตรวจรับงานขั้นสุดท้าย | ยอดค่าแรงและยอดหัก"
        case .feedAckFix: "ฟีดโครงการ: กด แก้แล้ว / รับทราบ"
        case .usersManage: "เพิ่มสมาชิก | ตั้งบทบาท"
        case .usersSuspend: "ปิด / ระงับบัญชีผู้ใช้ | เปิดใช้งานอีกครั้ง"
        case .usersPermissions: "แก้ตารางสิทธิ์และกฎการใช้งาน"
        case .usersAdmin: "เปิดหน้าจัดการผู้ใช้และสิทธิ์ (ต้องใช้คีย์นักพัฒนา)"
        case .companyTemplates: "ตั้งค่าบริษัท | เทมเพลต Excel / PDF"
        case .toolsRegister: "ทะเบียนเครื่องมือวัด"
        }
    }

    /// A conditional cell's condition, or nil.
    func note(_ role: UserRole) -> String? {
        switch (self, role) {
        case (.jobList, .external): "เฉพาะงานที่ได้รับมอบหมาย"
        case (.installTracking, .external): "ดูงานตัวเอง"
        case (.surveyEdit, .external): "ดู (แก้ได้ถ้าได้รับมอบหมายงานออกแบบ)"
        case (.surveySignRev, .external): "เฉพาะวิศวกรผู้ลงนาม"
        case (.engineerCertify, .manager): "วิศวกรที่มีใบ กว."
        case (.engineerCertify, .internalTeam): "วิศวกรที่มีใบ กว."
        case (.engineerCertify, .external): "เฉพาะงานที่เป็นวิศวกรผู้ลงนาม"
        case (.attachFiles, .external): "แนบได้ เห็นเฉพาะไฟล์หน้างาน"
        case (.driveUpload, .external): "Drive ของตัวเอง เฉพาะงานที่ได้รับมอบหมาย แชร์ให้ทีมอ่าน"
        case (.workOrder, .external): "เซ็นรับ"
        case (.changeRequest, .manager): "อนุมัติ / ไม่อนุมัติ"
        case (.changeRequest, .internalTeam): "สร้าง"
        case (.changeRequest, .external): "ยื่นขอ"
        case (.punchList, .internalTeam): "เปิด / ปิดรายการ"
        case (.punchList, .external): "แก้ แนบรูป ขอปิด"
        case (.dailyFill, .external): "ต้องส่งทุกวันที่เข้างาน | งานตัวเอง"
        case (.mpWBSTick, .manager): "เอาติ๊กออกได้ทุกรายการ"
        case (.mpWBSTick, .internalTeam): "เอาติ๊กของตัวเองออก | วิศวกรคุมงานเอาออกได้ทุกรายการ"
        case (.mpWBSTick, .external): "งานตัวเอง | เอาติ๊กของตัวเองออก"
        case (.weeklyRequest, .internalTeam): "อนุมัติ / ส่งกลับ"
        case (.weeklyRequest, .external): "ต้องส่งทุกสัปดาห์ | งานตัวเอง"
        case (.dailySign, .internalTeam): "ทีมงานของงานนั้นหรือผู้ควบคุมงาน (งานที่ยังไม่มีชื่อใครของเรา: ทีมภายในทุกคน)"
        case (.iecFillSubmit, .external): "ต้องทดสอบและส่งผล ก่อน / หลังขนาน | งานตัวเอง"
        case (.finalSignoff, .internalTeam): "เฉพาะวิศวกรผู้ควบคุมงานของงานนั้น"
        case (.finalSignoff, .external): "ดูยอดของตัวเอง"
        case (.feedAckFix, .external): "แก้แล้ว เฉพาะรายการของตัวเอง"
        case (.stationDocsDrafts, .external): "ดูเอกสารของสถานีที่ได้รับมอบหมาย | แก้ / อัปโหลดไม่ได้"
        default: nil
        }
    }
}
